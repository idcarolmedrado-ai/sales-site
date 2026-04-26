// Supabase Edge Function: send-cadence
//
// Proxies cadence-step emails to Resend so the Resend API key never
// leaves the server. The browser cannot call Resend directly: CORS
// blocks it and the key would be exposed.
//
// DEPLOY
//   supabase functions deploy send-cadence
//
// SECRETS (one-time, run from project root)
//   supabase secrets set RESEND_API_KEY=re_xxx
//   supabase secrets set RESEND_FROM='Carol Medrado <carol@yourdomain.com>'
//
// Without those secrets, the function falls back to the apiKey/from
// passed in the request body. Less secure (the key is in browser
// localStorage), but lets you test before configuring secrets.
//
// REQUEST BODY (JSON)
//   { to, subject, text?, html?, from?, apiKey? }
//
// RESPONSE
//   200 → { ok: true, id }     // Resend message id
//   4xx → { error, detail? }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const RESEND_API = "https://api.resend.com/emails";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const apiKey = (Deno.env.get("RESEND_API_KEY") || (payload.apiKey as string) || "").trim();
  const fromAddr = ((payload.from as string) || Deno.env.get("RESEND_FROM") || "").trim();
  const to = (payload.to as string || "").trim();
  const subject = (payload.subject as string || "").trim();
  const text = (payload.text as string || "").trim();
  const html = (payload.html as string || "").trim();

  if (!apiKey)   return json({ error: "no Resend API key — set RESEND_API_KEY secret or pass apiKey" }, 400);
  if (!fromAddr) return json({ error: "no from address — set RESEND_FROM secret or pass from" }, 400);
  if (!to)       return json({ error: "missing 'to'" }, 400);
  if (!subject)  return json({ error: "missing 'subject'" }, 400);
  if (!text && !html) return json({ error: "missing 'text' or 'html'" }, 400);

  const resp = await fetch(RESEND_API, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromAddr,
      to,
      subject,
      ...(html ? { html } : {}),
      ...(text ? { text } : {}),
    }),
  });

  const data = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    return json({ error: "resend api error", status: resp.status, detail: data }, 502);
  }
  return json({ ok: true, id: data.id });
});
