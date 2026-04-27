// Supabase Edge Function: enrich-email
//
// Two-layer email discovery:
//   1. Regex scraper  — extracts mailto: links + plain-text emails from HTML
//   2. Gemini Flash   — AI extraction of obfuscated / JS-embedded emails
//                       (optional; set GEMINI_API_KEY secret to enable)
//
// Gemini is called only when regex finds no *personal* email (info@, contact@
// etc. are generic and don't count). This keeps API usage low.
//
// DEPLOY
//   supabase functions deploy enrich-email
//
// SECRETS
//   GEMINI_API_KEY  (optional) — free key from https://aistudio.google.com
//                   500 req/day, 1M tokens/day — well within daily use
//
// REQUEST BODY (JSON)
//   { website, firstName?, lastName? }
//
// RESPONSE
//   { ok, domain, found, patterns, sources, pagesScraped, aiAssisted, notes }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

const COMMON_PATHS = ["/contact", "/contact-us", "/about", "/"];

const COMMON_LOCAL_PARTS = [
  "info", "contact", "hello", "office", "admin", "sales", "support",
];

// Generic role addresses — finding only these doesn't count as a real hit
const GENERIC_LOCAL_PARTS = new Set([
  "info", "contact", "hello", "office", "admin", "sales", "support",
  "marketing", "media", "press", "legal", "billing", "accounting",
  "hr", "jobs", "careers", "team", "mail", "post", "general", "enquiries",
  "enquiry", "noreply", "no-reply", "donotreply", "do-not-reply",
]);

const EMAIL_RE   = /([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/g;
const MAILTO_RE  = /mailto:([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/gi;

const NOISE_PREFIXES = [
  "noreply", "no-reply", "donotreply", "do-not-reply", "postmaster",
  "abuse", "webmaster", "wordpress", "support@wordpress",
  "example", "you@", "yourname",
];
function isNoise(email: string): boolean {
  const lower = email.toLowerCase();
  return NOISE_PREFIXES.some(n => lower.startsWith(n + "@") || lower.startsWith(n));
}

function isGenericEmail(email: string): boolean {
  const local = email.split("@")[0].toLowerCase();
  return GENERIC_LOCAL_PARTS.has(local);
}

function hasPersonalEmail(emails: Set<string>): boolean {
  return [...emails].some(e => !isGenericEmail(e));
}

function extractDomain(url: string): string | null {
  try {
    const fullUrl = url.match(/^https?:\/\//) ? url : "https://" + url;
    return new URL(fullUrl).hostname.replace(/^www\./, "");
  } catch { return null; }
}

async function fetchWithTimeout(url: string, ms = 4000): Promise<string | null> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), ms);
  try {
    const res = await fetch(url, {
      signal: ctl.signal,
      redirect: "follow",
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; LeadEnricher/1.0)",
        "Accept": "text/html,*/*",
      },
    });
    if (!res.ok) return null;
    const ct = res.headers.get("content-type") || "";
    if (!ct.includes("text") && !ct.includes("xml")) return null;
    const reader = res.body?.getReader();
    if (!reader) return null;
    const chunks: Uint8Array[] = [];
    let total = 0;
    const MAX_BYTES = 200_000;
    while (total < MAX_BYTES) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) { chunks.push(value); total += value.length; }
    }
    try { await reader.cancel(); } catch { /* ignore */ }
    const merged = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) { merged.set(c, off); off += c.length; }
    return new TextDecoder("utf-8", { fatal: false }).decode(merged);
  } catch { return null; }
  finally { clearTimeout(timer); }
}

function stripScriptsAndStyles(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ");
}

function stripAllTags(html: string): string {
  return stripScriptsAndStyles(html)
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function decodeHtmlEntities(s: string): string {
  return s
    .replace(/&#64;/gi, "@").replace(/&#46;/gi, ".")
    .replace(/\(at\)/gi, "@").replace(/\[at\]/gi, "@")
    .replace(/\s+at\s+/gi, "@")
    .replace(/\(dot\)/gi, ".").replace(/\[dot\]/gi, ".");
}

function extractEmails(html: string, allowedDomain: string): Set<string> {
  const found = new Set<string>();
  const decoded = decodeHtmlEntities(stripScriptsAndStyles(html));

  let m: RegExpExecArray | null;
  MAILTO_RE.lastIndex = 0;
  while ((m = MAILTO_RE.exec(decoded))) {
    const e = m[1].toLowerCase().trim();
    if (!isNoise(e)) found.add(e);
  }
  EMAIL_RE.lastIndex = 0;
  while ((m = EMAIL_RE.exec(decoded))) {
    const e = m[1].toLowerCase().trim();
    if (!isNoise(e)) found.add(e);
  }

  const out = new Set<string>();
  for (const e of found) {
    const at = e.indexOf("@");
    if (at < 0) continue;
    const eDomain = e.slice(at + 1).replace(/^www\./, "");
    if (eDomain === allowedDomain || eDomain.endsWith("." + allowedDomain)) out.add(e);
  }
  return out;
}

// ── Gemini Flash extraction ──────────────────────────────────────────────────

const GEMINI_MODELS = ["gemini-2.0-flash-lite", "gemini-2.0-flash"];

async function extractEmailsWithAI(
  pageText: string,
  domain: string,
  apiKey: string,
): Promise<Set<string>> {
  // Keep prompt compact — 10 KB of text covers any real contact page
  const text = pageText.slice(0, 10_000);

  const prompt =
    `You are extracting email addresses from company website text.\n` +
    `Domain: ${domain}\n\n` +
    `Find ALL email addresses in the text that belong to "${domain}" or its subdomains.\n` +
    `Also look for obfuscated forms:\n` +
    `- name [at] domain.com\n` +
    `- name(at)domain.com\n` +
    `- name AT domain DOT com\n` +
    `- HTML entities: &#64; = @, &#46; = .\n\n` +
    `Return ONLY emails actually present in the text — do NOT invent or guess.\n` +
    `Return JSON: {"emails":["found@${domain}"]}\n` +
    `If none found: {"emails":[]}\n\n` +
    `TEXT:\n${text}`;

  for (const model of GEMINI_MODELS) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: {
              responseMimeType: "application/json",
              temperature: 0,
              maxOutputTokens: 512,
            },
          }),
          signal: AbortSignal.timeout(10_000),
        },
      );

      if (res.status === 429) { continue; } // quota — try next model
      if (!res.ok) return new Set();

      const data = await res.json().catch(() => ({}));
      const raw: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
      let parsed: { emails?: unknown[] };
      try { parsed = JSON.parse(raw); } catch { return new Set(); }

      const found = new Set<string>();
      for (const e of (parsed.emails ?? [])) {
        if (typeof e !== "string") continue;
        const lower = e.toLowerCase().trim();
        if (isNoise(lower)) continue;
        const at = lower.indexOf("@");
        if (at < 0) continue;
        const eDomain = lower.slice(at + 1).replace(/^www\./, "");
        if (eDomain === domain || eDomain.endsWith("." + domain)) found.add(lower);
      }
      return found;
    } catch { /* timeout / network — fall through */ }
  }
  return new Set();
}

// ── Pattern generator ────────────────────────────────────────────────────────

function generatePatterns(domain: string, firstName?: string, lastName?: string): string[] {
  const patterns: string[] = [];
  const f = (firstName || "").toLowerCase().replace(/[^a-z]/g, "");
  const l = (lastName  || "").toLowerCase().replace(/[^a-z]/g, "");

  if (f && l) {
    patterns.push(`${f}.${l}@${domain}`);
    patterns.push(`${f}${l}@${domain}`);
    patterns.push(`${f[0]}${l}@${domain}`);
    patterns.push(`${f}_${l}@${domain}`);
    patterns.push(`${f}-${l}@${domain}`);
    patterns.push(`${f[0]}.${l}@${domain}`);
  }
  if (f) patterns.push(`${f}@${domain}`);
  if (l) patterns.push(`${l}@${domain}`);
  for (const role of COMMON_LOCAL_PARTS) patterns.push(`${role}@${domain}`);

  const seen = new Set<string>();
  const out: string[] = [];
  for (const p of patterns) {
    if (seen.has(p)) continue;
    seen.add(p);
    out.push(p);
    if (out.length >= 12) break;
  }
  return out;
}

// ── Main handler ─────────────────────────────────────────────────────────────

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST")   return json({ error: "POST only" }, 405);

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }

  const website   = (payload.website   as string || "").trim();
  const firstName = (payload.firstName as string || "").trim();
  const lastName  = (payload.lastName  as string || "").trim();
  if (!website) return json({ error: "website is required" }, 400);

  const domain = extractDomain(website);
  if (!domain) return json({ error: "could not parse domain from website URL" }, 400);

  const baseUrl = website.match(/^https?:\/\//)
    ? website.replace(/\/+$/, "")
    : "https://" + domain;

  const geminiKey = (Deno.env.get("GEMINI_API_KEY") || "").trim();

  const startedAt      = Date.now();
  const TOTAL_BUDGET   = 12_000;
  const urls           = COMMON_PATHS.map(p => baseUrl + p);
  const allFound       = new Set<string>();
  const sources: Record<string, string[]> = {};
  let pagesScraped     = 0;
  let aiAssisted       = false;
  let timedOut         = false;

  for (const u of urls) {
    if (Date.now() - startedAt > TOTAL_BUDGET) { timedOut = true; break; }

    const html = await fetchWithTimeout(u);
    if (!html) continue;
    pagesScraped++;

    // Layer 1: regex
    const regexEmails = extractEmails(html, domain);

    // Layer 2: Gemini — only when regex finds no personal email
    let aiEmails = new Set<string>();
    if (geminiKey && !hasPersonalEmail(regexEmails)) {
      const pageText = stripAllTags(decodeHtmlEntities(html));
      aiEmails = await extractEmailsWithAI(pageText, domain, geminiKey);
      if (aiEmails.size > 0) aiAssisted = true;
    }

    const merged = new Set([...regexEmails, ...aiEmails]);

    if (merged.size > 0) {
      sources[u] = Array.from(merged);
      for (const e of merged) allFound.add(e);
      break; // found what we need
    }
  }

  const found    = Array.from(allFound);
  const patterns = generatePatterns(domain, firstName, lastName);

  const hasReal  = found.some(e => !isGenericEmail(e));
  const notes =
    timedOut
      ? "Site responded slowly — gave up after 12 s. Try patterns below or visit manually."
      : pagesScraped === 0
        ? "No pages reachable. Site may block scrapers, be a JS SPA, or be down. Try the website link manually."
        : found.length === 0
          ? (geminiKey
              ? "Pages reachable but no emails found even with AI extraction. Site likely renders emails in JS client-side. Try patterns below."
              : "Pages reachable but no emails in plain text. Enable Gemini AI (set GEMINI_API_KEY secret) for obfuscated-email detection, or try patterns below.")
          : hasReal
            ? (aiAssisted ? "Email found via AI extraction (obfuscated on page)." : "Email scraped directly from page — highest confidence.")
            : "Only generic role addresses found. Check patterns for personal email.";

  return json({
    ok: true,
    domain,
    found,
    patterns,
    sources,
    pagesScraped,
    aiAssisted,
    timedOut,
    notes,
  });
});
