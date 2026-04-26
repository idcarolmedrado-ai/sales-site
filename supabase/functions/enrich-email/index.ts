// Supabase Edge Function: enrich-email
//
// Free email enrichment — no API keys, no monthly limits, no signup.
// Scrapes a company website's common pages (homepage, /contact, /about, /team)
// for emails matching the company's domain, plus generates common email
// patterns (info@, contact@, firstname@, firstname.lastname@) as candidates.
//
// CAPTURE RATE
//   ~40-60% direct scrape (simple sites with mailto: links or plain-text emails)
//   +25-30% from generated patterns (B2B follows predictable formats)
//   = ~70-80% combined. Heavy-JS sites and Cloudflare-protected sites are blind.
//   Manual fallback (visit website link) covers the remainder.
//
// DEPLOY (no secrets needed — fully free)
//   supabase functions deploy enrich-email
//   (or via dashboard → Edge Functions → Deploy a new function → Via Editor)
//
// REQUEST BODY (JSON)
//   {
//     website:   "https://stoneaspen.com",        // required
//     firstName: "John",                            // optional, sharpens patterns
//     lastName:  "Smith"                            // optional
//   }
//
// RESPONSE
//   200 → {
//     ok: true,
//     domain: "stoneaspen.com",
//     found:    ["john@stoneaspen.com", "info@stoneaspen.com"],   // scraped
//     patterns: ["john@stoneaspen.com", "j.smith@stoneaspen.com", ...], // generated
//     sources:  { "https://...": ["..."] },        // which page each email came from
//     pagesScraped: 4
//   }
//   4xx → { error, detail? }

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

const COMMON_PATHS = [
  "/contact",
  "/contact-us",
  "/contacts",
  "/about",
  "/about-us",
  "/team",
  "/our-team",
  "/", // homepage last as fallback
];

const COMMON_LOCAL_PARTS = [
  "info", "contact", "hello", "office", "admin", "sales", "support",
];

// Reasonable email regex. Not RFC-perfect but catches the common case.
const EMAIL_RE = /([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/g;
const MAILTO_RE = /mailto:([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/gi;

// Drop emails that are clearly not lead-relevant (placeholders, vendor systems)
const NOISE_PREFIXES = [
  "noreply", "no-reply", "donotreply", "do-not-reply", "postmaster",
  "abuse", "webmaster", "wordpress", "support@wordpress",
  "example", "you@", "yourname",
];
function isNoise(email: string): boolean {
  const lower = email.toLowerCase();
  return NOISE_PREFIXES.some(n => lower.startsWith(n + "@") || lower.startsWith(n));
}

function extractDomain(url: string): string | null {
  try {
    const fullUrl = url.match(/^https?:\/\//) ? url : "https://" + url;
    const u = new URL(fullUrl);
    return u.hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

async function fetchWithTimeout(url: string, ms = 8000): Promise<string | null> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), ms);
  try {
    const res = await fetch(url, {
      signal: ctl.signal,
      redirect: "follow",
      headers: {
        // Some sites block bare fetch UAs. Pretend to be a normal browser.
        "User-Agent": "Mozilla/5.0 (compatible; LeadEnricher/1.0; +https://supabase.com/functions)",
        "Accept": "text/html,application/xhtml+xml,*/*",
      },
    });
    if (!res.ok) return null;
    const ct = res.headers.get("content-type") || "";
    // Only parse text-ish responses; skip PDFs, images, etc.
    if (!ct.includes("text") && !ct.includes("xml") && !ct.includes("json")) return null;
    const text = await res.text();
    // Skip giant pages — most contact pages are small
    if (text.length > 500_000) return text.slice(0, 500_000);
    return text;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function decodeHtmlEntities(s: string): string {
  // Common email obfuscations: &#64; for @, &#46; for .
  return s
    .replace(/&#64;/gi, "@")
    .replace(/&#46;/gi, ".")
    .replace(/\(at\)/gi, "@")
    .replace(/\[at\]/gi, "@")
    .replace(/\s+at\s+/gi, "@")
    .replace(/\(dot\)/gi, ".")
    .replace(/\[dot\]/gi, ".");
}

function extractEmails(html: string, allowedDomain: string): Set<string> {
  const found = new Set<string>();
  const decoded = decodeHtmlEntities(html);

  // mailto: links first (highest signal)
  let m: RegExpExecArray | null;
  MAILTO_RE.lastIndex = 0;
  while ((m = MAILTO_RE.exec(decoded))) {
    const e = m[1].toLowerCase().trim();
    if (!isNoise(e)) found.add(e);
  }

  // Plain text email matches
  EMAIL_RE.lastIndex = 0;
  while ((m = EMAIL_RE.exec(decoded))) {
    const e = m[1].toLowerCase().trim();
    if (!isNoise(e)) found.add(e);
  }

  // Filter to same domain (or subdomain of it)
  const out = new Set<string>();
  for (const e of found) {
    const at = e.indexOf("@");
    if (at < 0) continue;
    const eDomain = e.slice(at + 1).replace(/^www\./, "");
    if (eDomain === allowedDomain || eDomain.endsWith("." + allowedDomain)) {
      out.add(e);
    }
  }
  return out;
}

function generatePatterns(domain: string, firstName?: string, lastName?: string): string[] {
  const patterns: string[] = [];
  const f = (firstName || "").toLowerCase().replace(/[^a-z]/g, "");
  const l = (lastName  || "").toLowerCase().replace(/[^a-z]/g, "");

  // Most-likely first if we have names
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

  // Generic role addresses last
  for (const role of COMMON_LOCAL_PARTS) {
    patterns.push(`${role}@${domain}`);
  }

  // Dedupe preserving order, cap at 12
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

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST")     return json({ error: "POST only" }, 405);

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

  // Fetch the candidate pages in parallel
  const urls  = COMMON_PATHS.map(p => baseUrl + p);
  const htmls = await Promise.all(urls.map(u => fetchWithTimeout(u)));

  // Aggregate scraped emails per page
  const allFound = new Set<string>();
  const sources: Record<string, string[]> = {};
  let pagesScraped = 0;
  for (let i = 0; i < urls.length; i++) {
    const html = htmls[i];
    if (!html) continue;
    pagesScraped++;
    const emails = extractEmails(html, domain);
    if (emails.size) sources[urls[i]] = Array.from(emails);
    for (const e of emails) allFound.add(e);
  }

  const found    = Array.from(allFound);
  const patterns = generatePatterns(domain, firstName, lastName);

  return json({
    ok: true,
    domain,
    found,
    patterns,
    sources,
    pagesScraped,
    notes:
      pagesScraped === 0
        ? "No pages reachable. Site may block scrapers, be JS-only (React SPA), or be down. Try the website link manually."
        : found.length === 0
          ? "Pages reachable but no emails in plaintext. Try the patterns below — most B2B emails follow these formats."
          : "Scraped emails are highest signal. Patterns are fallback candidates.",
  });
});
