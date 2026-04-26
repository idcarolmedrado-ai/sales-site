// Supabase Edge Function: inbound-reply
//
// Receives Resend Inbound webhooks when a prospect replies to a cadence
// email. Verifies the svix signature, looks up the prospect by sender
// email, sets status='replied' + last_reply_at/subject/from on the row.
//
// FLOW
//   prospect@theirsite.com replies → Resend MX → Resend webhook fires →
//   this function verifies + updates Supabase row → next time Carol
//   opens the Today tab, the prospect appears in "Replied — follow up"
//   with no manual "Mark replied" needed.
//
// DEPLOY (no SQL change required if last_reply_subject/from columns exist)
//   supabase functions deploy inbound-reply
//
// SECRETS
//   supabase secrets set RESEND_WEBHOOK_SECRET=whsec_...
//   (the value comes from Resend dashboard → Webhooks → your endpoint)
//
//   SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by
//   Supabase into all Edge Functions — no manual configuration needed.
//
// RESEND CONFIG
//   1. Resend dashboard → Domains → set up MX records on your sending
//      domain (or use the .resend.app fallback for testing)
//   2. Resend dashboard → Webhooks → Create endpoint → URL =
//      https://<your-project-ref>.supabase.co/functions/v1/inbound-reply
//   3. Pick events: email.received
//   4. Copy the signing secret (starts with whsec_) → set as the
//      RESEND_WEBHOOK_SECRET supabase secret above

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, svix-id, svix-timestamp, svix-signature",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

/* ── svix signature verification ── */
function base64Decode(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}
function base64Encode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

async function hmacSha256(keyBytes: Uint8Array, data: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return new Uint8Array(sig);
}

async function verifySvix(secret: string, id: string, timestamp: string, sigHeader: string, body: string): Promise<boolean> {
  // Resend signing secrets are formatted "whsec_BASE64KEY"
  const rawSecret = secret.startsWith("whsec_") ? secret.slice("whsec_".length) : secret;
  let keyBytes: Uint8Array;
  try {
    keyBytes = base64Decode(rawSecret);
  } catch {
    return false;
  }
  const signedContent = `${id}.${timestamp}.${body}`;
  const computed = await hmacSha256(keyBytes, signedContent);
  const expected = base64Encode(computed);
  // Header looks like "v1,<sig> v1,<sig>" — multiple sigs separated by space
  const parts = sigHeader.split(/\s+/);
  for (const p of parts) {
    const tagged = p.split(",", 2);
    if (tagged.length !== 2) continue;
    if (tagged[0] !== "v1") continue;
    // Constant-time compare avoided here for simplicity — these are
    // signed payloads, not user secrets. Direct string compare is fine.
    if (tagged[1] === expected) return true;
  }
  return false;
}

/* ── Reject ancient webhook deliveries to prevent replay ── */
function isFreshTimestamp(ts: string): boolean {
  const n = Number(ts);
  if (!isFinite(n)) return false;
  const now = Math.floor(Date.now() / 1000);
  // 5 minutes either direction (svix default tolerance)
  return Math.abs(now - n) <= 300;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST")     return json({ error: "POST only" }, 405);

  const id        = req.headers.get("svix-id")        || "";
  const timestamp = req.headers.get("svix-timestamp") || "";
  const signature = req.headers.get("svix-signature") || "";
  const body = await req.text();

  // Signature verification (skip only if no secret configured AND the
  // function is being tested manually — production should always have it set)
  const secret = (Deno.env.get("RESEND_WEBHOOK_SECRET") || "").trim();
  if (secret) {
    if (!id || !timestamp || !signature) return json({ error: "missing svix headers" }, 401);
    if (!isFreshTimestamp(timestamp))    return json({ error: "stale timestamp" }, 401);
    const ok = await verifySvix(secret, id, timestamp, signature, body);
    if (!ok) return json({ error: "invalid signature" }, 401);
  }

  let event: Record<string, unknown>;
  try { event = JSON.parse(body); } catch { return json({ error: "invalid JSON" }, 400); }

  // Only handle inbound receive events. Everything else is ignored quietly.
  if (event.type !== "email.received") {
    return json({ ok: true, ignored: event.type || "unknown" });
  }

  const data = (event.data || {}) as Record<string, unknown>;
  const rawFrom = data.from;
  let fromAddr = "";
  // Resend's `from` may be a string ("Name <addr@x>") OR object ({email, name})
  if (typeof rawFrom === "string") {
    const m = rawFrom.match(/<([^>]+)>/);
    fromAddr = (m ? m[1] : rawFrom).trim().toLowerCase();
  } else if (rawFrom && typeof rawFrom === "object") {
    fromAddr = String((rawFrom as Record<string, unknown>).email || "").trim().toLowerCase();
  }
  const subject = String(data.subject || "").slice(0, 500);

  if (!fromAddr) return json({ ok: true, skipped: "no from" });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY) {
    return json({ error: "service env not available — function may not be running on Supabase" }, 500);
  }
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Find the prospect by sender email (case-insensitive)
  const { data: matches, error: qErr } = await supabase
    .from("prospects")
    .select("id, email, status, persona, cadence_step")
    .ilike("email", fromAddr)
    .limit(1);

  if (qErr) return json({ error: "prospect lookup failed", detail: qErr.message }, 500);
  if (!matches || matches.length === 0) {
    return json({ ok: true, status: "no-match", from: fromAddr });
  }

  const p = matches[0];

  // Skip if already archived (opted-out, converted) — those are intentional terminal states
  if (p.status === "opted-out" || p.status === "converted") {
    return json({ ok: true, status: "ignored-archived", prospect_id: p.id });
  }

  // Mark replied — pauses the cadence at the current step
  const { error: uErr } = await supabase
    .from("prospects")
    .update({
      status: "replied",
      last_reply_at: new Date().toISOString(),
      last_reply_subject: subject || null,
      last_reply_from: fromAddr,
    })
    .eq("id", p.id);

  if (uErr) return json({ error: "update failed", detail: uErr.message }, 500);

  return json({
    ok: true,
    status: "marked-replied",
    prospect_id: p.id,
    cadence_step_paused_at: p.cadence_step,
    subject,
  });
});
