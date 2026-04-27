// Supabase Edge Function: recent-home-sales
//
// Scrapes Realtor.com recently sold listings for a given city + state.
// Returns property address, sale price, sold date, beds/baths/sqft.
//
// NOTE: Returns property data only — no buyer contact info (public record
// limitation). Use results for direct mail campaigns or skip-trace services.
//
// DEPLOY
//   supabase functions deploy recent-home-sales
//
// REQUEST BODY (JSON)
//   { city: "Denver", state: "CO", days?: 30 }
//
// RESPONSE (success)
//   { ok: true, results: [{address, price, soldDate, beds, baths, sqft, url}], count, manualUrl }
//
// RESPONSE (failure)
//   { ok: false, error, tip, manualUrl, results: [] }

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

interface SoldHome {
  address: string;
  price: number | null;
  soldDate: string | null;
  beds: number | null;
  baths: string | null;
  sqft: number | null;
  url: string | null;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }

  const city  = ((payload.city  as string) || "").trim();
  const state = ((payload.state as string) || "").trim().toUpperCase();
  const days  = Math.min(90, Math.max(7, parseInt(String(payload.days || 30)) || 30));

  if (!city || !state) return json({ error: "city and state are required" }, 400);

  const citySlug  = city.replace(/\s+/g, "_").replace(/[^a-zA-Z0-9_-]/g, "");
  const searchUrl = `https://www.realtor.com/realestateandhomes-search/${citySlug}_${state}/show-recently-sold/`;
  const manualUrl = searchUrl;

  let html: string | null = null;
  let fetchStatus = 0;
  try {
    const res = await fetch(searchUrl, {
      headers: {
        "User-Agent":       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept":           "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language":  "en-US,en;q=0.9",
        "Cache-Control":    "no-cache",
        "Sec-Fetch-Dest":   "document",
        "Sec-Fetch-Mode":   "navigate",
        "Sec-Fetch-Site":   "none",
        "Upgrade-Insecure-Requests": "1",
      },
      redirect:  "follow",
      signal:    AbortSignal.timeout(12_000),
    });
    fetchStatus = res.status;
    if (res.ok) html = await res.text();
  } catch { /* timeout or network error */ }

  if (!html) {
    return json({
      ok:         false,
      error:      fetchStatus === 403 || fetchStatus === 429
                    ? "Realtor.com is blocking automated access (status " + fetchStatus + ")."
                    : "Could not reach Realtor.com (network error or timeout).",
      tip:        "Open the link below, filter to 'Last 30 days', then export to CSV and import it manually.",
      manualUrl,
      results:    [],
    });
  }

  // Detect bot-challenge pages
  const blocked = html.includes("cf-browser-verification") ||
                  html.includes("Just a moment") ||
                  html.toLowerCase().includes("captcha") ||
                  html.includes("Enable JavaScript and cookies");
  if (blocked) {
    return json({
      ok:         false,
      error:      "Realtor.com is serving a bot-challenge page (Cloudflare). Cannot extract data automatically.",
      tip:        "Open the Realtor.com link below in your browser, search for recently sold homes, and export the CSV.",
      manualUrl,
      results:    [],
    });
  }

  // Extract __NEXT_DATA__
  const ndMatch = html.match(/<script\s+id="__NEXT_DATA__"[^>]*>([^<]{10,})<\/script>/);
  if (!ndMatch) {
    return json({
      ok:         false,
      error:      "Could not find structured data on the Realtor.com page. The site layout may have changed.",
      tip:        "Open the Realtor.com link below to search manually.",
      manualUrl,
      results:    [],
    });
  }

  let nextData: unknown;
  try { nextData = JSON.parse(ndMatch[1]); }
  catch {
    return json({ ok: false, error: "Failed to parse page data", manualUrl, results: [] });
  }

  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  const homes  = parseHomes(nextData, cutoff);

  if (homes.length === 0) {
    return json({
      ok:         false,
      error:      `No recently sold homes found in ${city}, ${state} (last ${days} days). Try a nearby larger city or metro area.`,
      tip:        "You can also search Zillow.com → Recently Sold → filter by date sold → Export CSV.",
      manualUrl,
      results:    [],
    });
  }

  return json({ ok: true, results: homes, count: homes.length, manualUrl });
});

// ── Property parsing ─────────────────────────────────────────────────────────

function parseHomes(data: unknown, cutoff: Date): SoldHome[] {
  // Try multiple known __NEXT_DATA__ paths — Realtor.com restructures frequently
  const candidates: unknown[] = [
    getPath(data, ["props","pageProps","initialReduxState","search","resultList"]),
    getPath(data, ["props","pageProps","searchResults","homes"]),
    getPath(data, ["props","pageProps","homes"]),
    getPath(data, ["props","pageProps","results"]),
    findDeepArray(data, "resultList", 8),
    findDeepArray(data, "homes",      8),
    findDeepArray(data, "results",    8),
    findDeepArray(data, "listings",   8),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (!Array.isArray(candidate) || candidate.length === 0) continue;
    const parsed = (candidate as unknown[])
      .map(p => parseProperty(p, cutoff))
      .filter((h): h is SoldHome => h !== null);
    if (parsed.length > 0) return parsed;
  }
  return [];
}

function getPath(obj: unknown, path: string[]): unknown {
  let cur = obj;
  for (const key of path) {
    if (!cur || typeof cur !== "object" || Array.isArray(cur)) return null;
    cur = (cur as Record<string, unknown>)[key];
  }
  return cur;
}

function findDeepArray(obj: unknown, key: string, maxDepth: number, depth = 0): unknown[] | null {
  if (depth > maxDepth || !obj || typeof obj !== "object") return null;
  if (Array.isArray(obj)) {
    for (const item of obj) {
      const r = findDeepArray(item, key, maxDepth, depth + 1);
      if (r) return r;
    }
    return null;
  }
  const record = obj as Record<string, unknown>;
  if (key in record && Array.isArray(record[key]) && (record[key] as unknown[]).length > 1) {
    return record[key] as unknown[];
  }
  for (const v of Object.values(record)) {
    const r = findDeepArray(v, key, maxDepth, depth + 1);
    if (r) return r;
  }
  return null;
}

function parseProperty(p: unknown, cutoff: Date): SoldHome | null {
  if (!p || typeof p !== "object" || Array.isArray(p)) return null;
  const r = p as Record<string, unknown>;

  // Sold date — skip if older than cutoff
  const soldDate = s(r.last_sold_date || r.sold_date);
  if (soldDate) {
    const d = new Date(soldDate);
    if (!isNaN(d.getTime()) && d < cutoff) return null;
  }

  // Address
  const loc  = (r.location as Record<string, unknown>) || {};
  const addr = (loc.address as Record<string, unknown>) || r;
  const line = s(addr.line || r.street_address || r.address_line);
  const city = s(addr.city || r.city);
  const st   = s(addr.state_code || addr.state || r.state_code || r.state);
  const zip  = s(addr.postal_code || r.postal_code || r.zip);
  if (!line) return null;

  const address = [line, city, st ? st + (zip ? " " + zip : "") : zip].filter(Boolean).join(", ");
  const price   = n(r.last_sold_price || r.sold_price || r.price || r.list_price);
  const beds    = n(r.beds || r.beds_min);
  const baths   = s(r.baths_consolidated || r.baths_min) ||
                  (r.baths != null ? String(r.baths) : null);
  const sqft    = n(r.sqft || r.sqft_min || r.building_size);
  const perma   = s(r.permalink);
  const url     = perma ? "https://www.realtor.com" + perma : null;

  return { address, price, soldDate: soldDate || null, beds, baths, sqft, url };
}

function s(v: unknown): string {
  if (v == null) return "";
  return String(v).trim();
}

function n(v: unknown): number | null {
  if (v == null || v === "") return null;
  const parsed = Number(v);
  return isNaN(parsed) ? null : parsed;
}
