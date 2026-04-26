# places-search Edge Function

Proxies queries to the Google Places API (New) Text Search endpoint so the API key stays server-side.

## What this does

Lead discovery for **B2B prospects** (builders, realtors, landscapers). Searches Google Places for businesses matching a query in a US region/city/state, returns name + address + state + phone + website.

**Important**: Google Places does **not** return email addresses. For email enrichment, chain with a separate service (Hunter.io, etc.) — not included here.

## Prerequisites

1. Google Cloud project with the **Places API (New)** enabled — [enable it here](https://console.cloud.google.com/apis/library/places.googleapis.com)
2. Create an API key in the Cloud Console → APIs & Services → Credentials
3. (Recommended) Restrict the key to the Places API (New) only

The free tier covers ~10,000 Text Search requests/month at the time of writing — check current pricing at [Google's pricing page](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing).

## Deploy

```bash
supabase functions deploy places-search
```

## Configure secrets

```bash
supabase secrets set GOOGLE_PLACES_API_KEY=AIza...
```

## Request format

```json
{
  "query":    "luxury home builders",
  "location": "Aspen, CO",
  "persona":  "builders",
  "pageToken": "<from prior response>"
}
```

- `query` (optional, free-text): refines the search
- `location` (optional): narrows by city/state — e.g., "Aspen, CO" or "Florida"
- `persona` (optional, one of `builders` / `realtors` / `landscaping`): adds a sensible default query stem
- `pageToken` (optional): pagination — returned as `nextPageToken` on each response

If neither `query` nor `persona` is provided, the function falls back to "interior design clients" — usually you want at least one.

## Response format

```json
{
  "ok": true,
  "textQuery": "luxury home builders in Aspen, CO",
  "results": [
    {
      "placeId": "ChIJ...",
      "name":    "Mountain Crest Custom Homes",
      "address": "123 Main St, Aspen, CO 81611, USA",
      "state":   "CO",
      "phone":   "(970) 555-1234",
      "website": "https://mountaincrestcustom.com",
      "googleMapsUri": "https://maps.google.com/?cid=...",
      "rating": 4.8,
      "userRatingCount": 23
    }
  ],
  "nextPageToken": "..."
}
```

## Why field masking matters

Google Places (New) charges per requested field via `X-Goog-FieldMask`. The function only requests what the app uses (name, phone, website, address, ratings) which keeps each request in the cheaper SKU tiers. Fields like reviews / photos / opening hours are **not** requested.
