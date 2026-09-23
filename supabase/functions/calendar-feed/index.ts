// Supabase Edge Function: calendar-feed
//
// Serves the dashboard Calendar as an iCalendar (.ics) feed so it can be
// subscribed to from Google Calendar ("Other calendars → From URL").
// One-way: dashboard → Google. Google re-fetches subscribed feeds on its
// own schedule (typically every few hours), so changes are not instant.
//
// EVENTS (all-day, same as the in-app Calendar)
//   Follow-up, Home Call, Delivery, Link Review  ← public.opportunities
//   Personal tasks (not done, with a date)       ← public.tasks
//
// AUTH
//   Google cannot send a JWT, so the function is deployed with
//   verify_jwt = false and instead requires ?token=<secret> matching a row
//   in public.calendar_feed_tokens (readable in-app by the logged-in user).
//   Rotate: delete the row and insert a new one → old subscriptions stop.
//
// DEPLOY
//   supabase functions deploy calendar-feed --no-verify-jwt
//
// REQUEST
//   GET /functions/v1/calendar-feed?token=<secret>
//   200 → text/calendar   401 → invalid token

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APP_URL = "https://sales.carolmedrado.com/";
const UID_DOMAIN = "sales.carolmedrado.com";
// Keep the feed small: skip events older than this
const LOOKBACK_DAYS = 90;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// RFC 5545 text escaping
function esc(s: unknown): string {
  return String(s ?? "")
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

// RFC 5545 line folding (75 octets, continuation lines start with a space)
function fold(line: string): string {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;
  const out: string[] = [];
  let cur = "";
  let curLen = 0;
  for (const ch of line) {
    const n = new TextEncoder().encode(ch).length;
    const limit = out.length === 0 ? 75 : 74;
    if (curLen + n > limit) { out.push(cur); cur = ""; curLen = 0; }
    cur += ch; curLen += n;
  }
  out.push(cur);
  return out.join("\r\n ");
}

function nextDay(ymd: string): string {
  const [y, m, d] = ymd.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + 1));
  return dt.toISOString().slice(0, 10).replace(/-/g, "");
}

type Ev = { uid: string; date: string; summary: string; description: string; location?: string; category: string };

function vevent(e: Ev, stamp: string): string[] {
  const lines = [
    "BEGIN:VEVENT",
    `UID:${e.uid}@${UID_DOMAIN}`,
    `DTSTAMP:${stamp}`,
    `DTSTART;VALUE=DATE:${e.date.replace(/-/g, "")}`,
    `DTEND;VALUE=DATE:${nextDay(e.date)}`,
    `SUMMARY:${esc(e.summary)}`,
    `DESCRIPTION:${esc(e.description)}`,
    `CATEGORIES:${esc(e.category)}`,
    "TRANSP:TRANSPARENT",
  ];
  if (e.location) lines.push(`LOCATION:${esc(e.location)}`);
  lines.push("END:VEVENT");
  return lines;
}

Deno.serve(async (req: Request) => {
  const token = new URL(req.url).searchParams.get("token") || "";
  if (!/^[a-f0-9]{32,128}$/i.test(token)) return new Response("Unauthorized", { status: 401 });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: tok } = await sb.from("calendar_feed_tokens").select("token").eq("token", token).maybeSingle();
  if (!tok) return new Response("Unauthorized", { status: 401 });

  const cutoff = new Date(Date.now() - LOOKBACK_DAYS * 864e5).toISOString().slice(0, 10);

  const [oppsRes, tasksRes] = await Promise.all([
    sb.from("opportunities").select(
      'id, first_name, last_name, phone, email, address, stage, follow_up_date, home_call_date, "deliveryDate", "linkReviewDate", "saleOrderNumber", next_step',
    ),
    sb.from("tasks").select('id, title, "dueDate", notes, "soNumber", priority, done'),
  ]);
  if (oppsRes.error) return new Response("Error loading opportunities", { status: 500 });

  const events: Ev[] = [];
  const ok = (d: unknown): d is string => typeof d === "string" && DATE_RE.test(d) && d >= cutoff;

  for (const o of oppsRes.data || []) {
    const name = `${o.first_name || ""} ${o.last_name || ""}`.trim() || "(no name)";
    const info = [
      o.stage ? `Stage: ${o.stage}` : "",
      o.next_step ? `Next step: ${o.next_step}` : "",
      o.phone ? `Phone: ${o.phone}` : "",
      o.email ? `Email: ${o.email}` : "",
      o.saleOrderNumber ? `SO: ${o.saleOrderNumber}` : "",
      `Open in dashboard: ${APP_URL}`,
    ].filter(Boolean).join("\n");
    const add = (date: unknown, kind: string, label: string, withLocation = false) => {
      if (ok(date)) {
        events.push({
          uid: `${kind}-${o.id}`, date, category: label,
          summary: `${label}: ${name}`, description: info,
          location: withLocation ? (o.address || undefined) : undefined,
        });
      }
    };
    add(o.follow_up_date, "followup", "Follow-up");
    add(o.home_call_date, "homecall", "Home Call", true);
    add(o.deliveryDate, "delivery", "Delivery", true);
    add(o.linkReviewDate, "review", "Link Review");
  }

  for (const t of tasksRes.data || []) {
    if (t.done || !ok(t.dueDate)) continue;
    events.push({
      uid: `task-${t.id}`, date: t.dueDate, category: "Task",
      summary: `Task: ${t.title || ""}`,
      description: [t.soNumber ? `SO: ${t.soNumber}` : "", t.notes || "", `Priority: ${t.priority || "medium"}`]
        .filter(Boolean).join("\n"),
    });
  }

  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Carol Medrado//Sales Dashboard//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Sales Dashboard",
    "X-WR-CALDESC:Follow-ups\\, home calls\\, deliveries\\, link reviews and tasks from the sales dashboard",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    "X-PUBLISHED-TTL:PT1H",
    ...events.flatMap((e) => vevent(e, stamp)),
    "END:VCALENDAR",
  ];

  return new Response(lines.map(fold).join("\r\n") + "\r\n", {
    status: 200,
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="sales-dashboard.ics"',
      "Cache-Control": "no-cache",
    },
  });
});
