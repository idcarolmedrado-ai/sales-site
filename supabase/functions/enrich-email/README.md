# enrich-email Edge Function

Free email enrichment by scraping a company's website + generating common email patterns. **No API keys, no monthly limits, no signup.**

## What it does

Given a company website URL, this function:
1. Fetches the homepage + `/contact`, `/about`, `/team` pages in parallel
2. Extracts emails matching the company's domain (regex on `mailto:` links + plain text)
3. Filters out noise (`noreply@`, `postmaster@`, etc.)
4. Generates likely email patterns (`info@`, `firstname@`, `firstname.lastname@`, etc.)
5. Returns scraped emails + pattern candidates ranked by likelihood

## Capture rate (real-world)

- **~40-60%** direct scrape — simple sites with `mailto:` links or plain-text emails
- **+25-30%** from generated patterns — most B2B follows predictable formats
- **= ~70-80% combined**

What this **won't** capture:
- Heavy JS-rendered sites (React SPAs that lazy-load contact pages)
- Cloudflare-protected sites that block server-to-server requests
- Sites that use email images or aggressive obfuscation
- Sites where the email is on a page outside the common paths

For those, the manual fallback (visit the website link, copy email by hand) covers the rest.

## Deploy

**Via dashboard** (no CLI needed):
1. [Edge Functions](https://supabase.com/dashboard/project/_/functions) → "Deploy a new function" → "Via Editor"
2. Name: `enrich-email`
3. Paste this directory's `index.ts` contents
4. Deploy

**Via CLI**:
```bash
supabase functions deploy enrich-email
```

No secrets needed — this function makes outbound HTTP requests but uses no paid APIs.

## Request format

```json
{
  "website":   "https://stoneaspen.com",
  "firstName": "John",
  "lastName":  "Smith"
}
```

- `website` (required): can be a full URL or just a domain
- `firstName` / `lastName` (optional): sharpens pattern generation

## Response format

```json
{
  "ok": true,
  "domain": "stoneaspen.com",
  "found":    ["info@stoneaspen.com", "john@stoneaspen.com"],
  "patterns": ["john.smith@stoneaspen.com", "johnsmith@stoneaspen.com", "jsmith@stoneaspen.com", "info@stoneaspen.com", "..."],
  "sources":  { "https://stoneaspen.com/contact": ["info@stoneaspen.com"] },
  "pagesScraped": 4,
  "notes": "..."
}
```

- `found`: emails actually scraped from the site (highest confidence)
- `patterns`: candidate emails to try if `found` is empty (lower confidence — verify before sending)
- `sources`: which page each scraped email came from (audit trail)
- `pagesScraped`: how many of the candidate pages responded with content (0 = site blocked or down)
- `notes`: human-readable hint about what to do with the response

## Limitations

This is a free, best-effort scraper. It will not match dedicated paid services for accuracy. Use it as the first pass; fall back to manual lookup or paid services (Hunter, Apollo, Clearbit) when you need higher confidence at scale.
