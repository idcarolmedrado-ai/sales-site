# send-cadence Edge Function

Proxies cadence-step emails to Resend so the API key never leaves the server. The browser cannot call Resend directly — CORS blocks it and the key would be exposed in client JS.

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli/getting-started) installed
- Logged in: `supabase login`
- Project linked: `supabase link --project-ref <your-project-ref>`

## Deploy

From the repo root:

```bash
supabase functions deploy send-cadence
```

That's it — the function is now live at:

```
https://<your-project-ref>.supabase.co/functions/v1/send-cadence
```

## Configure secrets (do this once)

```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxx
supabase secrets set RESEND_FROM='Carol Medrado <carol@yourdomain.com>'
```

The `from` address must be on a domain you've verified in Resend ([resend.com/domains](https://resend.com/domains)). Until verified, sends will fail with a 403.

## Test locally

```bash
supabase functions serve send-cadence --env-file .env.local
```

Then `curl` it:

```bash
curl -X POST http://localhost:54321/functions/v1/send-cadence \
  -H "Content-Type: application/json" \
  -d '{
    "to": "you@yourdomain.com",
    "subject": "Test from send-cadence",
    "text": "Hello from the Edge Function."
  }'
```

## Request format

```json
{
  "to": "prospect@example.com",
  "subject": "Question subject line",
  "text": "Plain-text email body",
  "html": "<p>Optional HTML body</p>",
  "from": "Optional override from",
  "apiKey": "Optional fallback API key (used if RESEND_API_KEY secret not set)"
}
```

## Response

- `200 { ok: true, id: "<resend-id>" }` on success
- `4xx { error, detail? }` on validation or upstream failure

## Security notes

- **Recommended**: store the Resend key as a Supabase secret (`RESEND_API_KEY`). It never leaves the server.
- **Fallback**: if no secret is set, the function accepts `apiKey` in the request body. The browser will pull it from `localStorage.ea_resend_key`. Functional, but less secure — anyone with browser DevTools access can read the key.
- The browser side (in `index.html` → `_sendViaResend`) prefers the secret path and only sends `apiKey` as a fallback.
