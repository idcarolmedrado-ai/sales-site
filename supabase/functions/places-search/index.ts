// Supabase Edge Function: places-search
//
// Proxies queries to the Google Places API (New) Text Search endpoint
// so the API key stays server-side. The browser cannot call the
// Places API directly (CORS + key exposure).
//
// PURPOSE
// Lead discovery for B2B prospects: builders, realtors, landscapers.
// Google Places returns business listings (name, phone, website,
// address) but NOT email addresses. Email enrichment is a separate
// step (Hunter.io etc) — not included in this function.
//
// DEPLOY
//   supabase functions deploy places-search
//
// SECRETS (one-time, run from project root)
//   supabase secrets set GOOGLE_PLACES_API_KEY=AIza...
//
// REQUEST BODY (JSON)
//   {
//     query:    "luxury home builders",     // required, free-text
//     location: "Aspen, CO" | "Florida",    // optional, narrows results
//     persona:  "builders" | "realtors" | "landscaping",  // optional, used for default queries
//     pageToken: "..."                      // optional, for paging
//   }
//
// RESPONSE
//   200 → { ok:true, results:[{name, phone, website, address, state, googleMapsUri, placeId, rating, userRatingCount}], nextPageToken? }
//   4xx → { error, detail? }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const PLACES_API = "https://places.googleapis.com/v1/places:searchText";
// Field mask — only request what we use, keeps cost down
const FIELD_MASK = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.internationalPhoneNumber",
  "places.nationalPhoneNumber",
  "places.websiteUri",
  "places.googleMapsUri",
  "places.rating",
  "places.userRatingCount",
  "places.addressComponents",
  "nextPageToken",
].join(",");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

// Persona → default query stem if user gives none
const PERSONA_QUERIES: Record<string, string> = {
  builders:    "luxury home builders",
  realtors:    "luxury real estate brokerage",
  landscaping: "landscape design build firm",
};

interface AddressComponent { longText?: string; shortText?: string; types?: string[]; }
interface PlaceResult {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  internationalPhoneNumber?: string;
  nationalPhoneNumber?: string;
  websiteUri?: string;
  googleMapsUri?: string;
  rating?: number;
  userRatingCount?: number;
  addressComponents?: AddressComponent[];
}

function extractState(comps?: AddressComponent[]): string {
  if (!comps) return "";
  const admin = comps.find(c => (c.types || []).includes("administrative_area_level_1"));
  return admin?.shortText || "";
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST")     return json({ error: "POST only" }, 405);

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }

  const apiKey = (Deno.env.get("GOOGLE_PLACES_API_KEY") || (payload.apiKey as string) || "").trim();
  if (!apiKey) return json({ error: "no Google Places API key — set GOOGLE_PLACES_API_KEY secret or pass apiKey" }, 400);

  const persona  = (payload.persona  as string || "").trim().toLowerCase();
  const userQ    = (payload.query    as string || "").trim();
  const location = (payload.location as string || "").trim();
  const pageToken= (payload.pageToken as string || "").trim();

  // Build the textQuery: persona stem + user query + location
  const stem  = PERSONA_QUERIES[persona] || "";
  const parts = [userQ, stem].filter(Boolean);
  const base  = parts.length ? parts.join(" ") : "interior design clients";
  const textQuery = location ? `${base} in ${location}` : base;

  const body: Record<string, unknown> = {
    textQuery,
    languageCode: "en",
    regionCode: "US",
    pageSize: 20,
  };
  if (pageToken) body.pageToken = pageToken;

  const resp = await fetch(PLACES_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": FIELD_MASK,
    },
    body: JSON.stringify(body),
  });

  const data = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    return json({ error: "Places API error", status: resp.status, detail: data }, 502);
  }

  const places: PlaceResult[] = Array.isArray(data.places) ? data.places : [];
  const results = places.map(p => ({
    placeId:        p.id || "",
    name:           p.displayName?.text || "",
    address:        p.formattedAddress || "",
    state:          extractState(p.addressComponents),
    phone:          p.nationalPhoneNumber || p.internationalPhoneNumber || "",
    website:        p.websiteUri || "",
    googleMapsUri:  p.googleMapsUri || "",
    rating:         p.rating || null,
    userRatingCount: p.userRatingCount || 0,
  })).filter(r => r.name); // Drop empty entries

  return json({ ok: true, results, nextPageToken: data.nextPageToken || "", textQuery });
});
