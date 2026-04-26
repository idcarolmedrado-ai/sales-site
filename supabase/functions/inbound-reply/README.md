# inbound-reply Edge Function

Receives Resend Inbound webhooks when a prospect replies to a cadence email, looks up the prospect in Supabase, and auto-marks the row `status='replied'`.

## Why this matters

Without it, every cadence reply requires you to manually click **Replied** on the contact. Inbound webhook closes the loop — replies surface in the **Today → Replied — follow up** queue automatically.

## Flow

```
prospect@theirsite.com replies →
  Resend MX receives →
    Resend webhook fires (event=email.received) →
      this Edge Function verifies svix signature →
        looks up prospect by sender email →
          UPDATE prospects SET status='replied', last_reply_at=now(),
                              last_reply_subject=..., last_reply_from=...
```

Skipped cases (returns 200 OK with status note):
- Sender email doesn't match any prospect → `no-match`
- Prospect is `opted-out` or `converted` → `ignored-archived`
- Event type isn't `email.received` → `ignored`

## Setup (one-time)

### 1. Set up Resend Inbound on your sending domain

[Resend dashboard → Domains](https://resend.com/domains) → click your sending domain (e.g. `yourdomain.com`).

You'll see a section for **Receiving** or **Inbound**. Resend provides MX records to add to your DNS. Add them. Wait for verification (usually 5–15 minutes).

If you don't have a custom domain yet, Resend offers `.resend.app` fallback addresses for testing only.

### 2. Deploy this function

Via dashboard:
1. [Edge Functions](https://supabase.com/dashboard/project/_/functions) → Deploy a new function → Via Editor
2. Name: `inbound-reply`
3. Paste this directory's `index.ts`
4. Deploy

Via CLI:
```bash
supabase functions deploy inbound-reply
```

### 3. Add the webhook in Resend

[Resend dashboard → Webhooks](https://resend.com/webhooks) → Create endpoint:
- **URL**: `https://<your-supabase-project-ref>.supabase.co/functions/v1/inbound-reply`
- **Events**: `email.received` (this is the only one we handle)

Resend gives you a **Signing Secret** (`whsec_...`). Copy it.

### 4. Set the webhook secret

Supabase dashboard → [Project Settings → Edge Functions → Secrets](https://supabase.com/dashboard/project/_/settings/functions) → Add:
- Name: `RESEND_WEBHOOK_SECRET`
- Value: the `whsec_...` you copied

Or via CLI:
```bash
supabase secrets set RESEND_WEBHOOK_SECRET=whsec_xxxxx
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected by Supabase — no manual setup needed.

### 5. Verify

Send a test email **to one of your verified domain addresses from a prospect's email address**. Within seconds:
- Resend dashboard → Webhooks → your endpoint → should show 200 OK delivery
- Supabase Functions → inbound-reply → Logs → should show the event
- App → Today tab → that prospect should appear under "Replied — follow up"

## What's NOT in this function (intentional simplification)

- **Email body parsing**: Resend sends only metadata in the webhook. Fetching full body requires a separate API call. The current function flags the reply with subject only — Carol opens her actual email client to read the content. This is the right trade-off for a one-person sales motion.
- **Auto-categorization** (interested vs opt-out): This requires NLP on the body. Carol manually picks the action when she opens the prospect via the existing 3-option Replied modal.
- **Bounce / complaint events**: These come on different webhook event types. If desired, add separate `email.bounced` / `email.complained` handlers in this same function.
- **Threading / conversation tracking**: Each reply just flips the prospect's status. If multiple replies arrive, the latest subject overwrites. Good enough for a 5-step cadence.

## Schema

This function relies on three columns on `prospects` that the app's One-Click Schema SQL adds:
- `last_reply_at timestamptz`
- `last_reply_subject text`
- `last_reply_from text`

If you've run the schema setup recently, you're already good. If sync starts erroring on these columns, re-run Settings → 🛠 → Copy SQL → paste in Supabase → Run.

## Security

- Function rejects any request without a valid svix signature (when `RESEND_WEBHOOK_SECRET` is set)
- Stale-timestamp check (>5 min) prevents replay attacks
- Service-role key never leaves the function's runtime
- No public data is exposed back to the requester (responses confirm action, no prospect details unless needed for debug)
