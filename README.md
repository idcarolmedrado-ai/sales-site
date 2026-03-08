# EA Sales Intelligence
### Ethan Allen — Sales Performance System for Carolina Medrado

A modern, single-file web app for tracking sales opportunities, monitoring performance, and managing follow-ups — backed by [Supabase](https://supabase.com) (free tier) and hosted on [GitHub Pages](https://pages.github.com) (free).

---

## 🚀 Live Demo

> **URL:** `https://<your-github-username>.github.io/ea-sales-site/`  
> *(available after setup below)*

---

## ✨ Features

| Feature | Description |
|---|---|
| **Dashboard** | Live KPIs — Sales $, Pipeline, Conversion Rate, Overdue Follow-ups |
| **Pipeline** | Full opportunity table with search, stage filters, overdue alerts |
| **Mailing** | Auto-generated email topics per client based on stage & project type |
| **Tests** | 38 automated in-browser tests covering all business logic |
| **Supabase Sync** | Real-time data shared across all your devices |
| **Demo Mode** | Works offline with 20 pre-loaded demo leads |
| **Auto-reconnect** | Remembers your credentials on return visits |

---

## 🛠 Setup — Takes ~10 Minutes

### Step 1 — Fork & Enable GitHub Pages

1. Click **Fork** (top right of this page)
2. Go to your fork → **Settings** → **Pages**
3. Under *Source*, select **Deploy from a branch**
4. Branch: `main` · Folder: `/ (root)` → **Save**
5. Your site goes live at `https://<your-username>.github.io/ea-sales-site/`

---

### Step 2 — Create a Free Supabase Database

1. Go to **[supabase.com](https://supabase.com)** → **Start your project** (free)
2. Sign in with GitHub (easiest) → **New project**
3. Fill in:
   - **Name:** `ea-sales`
   - **Database Password:** anything strong (save it)
   - **Region:** closest to you (e.g. US East)
4. Click **Create new project** — wait ~2 minutes

---

### Step 3 — Run the Database Schema

1. In Supabase, click **SQL Editor** in the left sidebar
2. Click **New query**
3. Open `supabase_schema.sql` from this repo and **copy all contents**
4. Paste into the SQL editor → click **Run** (▶)
5. You should see: *"Success. No rows returned"*

This creates the `opportunities` table with all columns, indexes, Row Level Security, and 20 demo records.

---

### Step 4 — Get Your API Credentials

1. In Supabase → **Project Settings** (gear icon) → **API**
2. Copy two values:
   - **Project URL** — looks like `https://xxxxxxxxxxxx.supabase.co`
   - **anon public** key — long JWT string starting with `eyJ...`

---

### Step 5 — Connect on First Visit

1. Open your GitHub Pages URL
2. You'll see the **Connect Database** screen
3. Paste your **Project URL** and **anon key**
4. Click **Connect →**
5. Done — your data syncs instantly across all devices!

> 💡 Credentials are saved in your browser. You won't need to re-enter them.

---

## 📁 File Structure

```
ea-sales-site/
├── index.html            ← Entire app (single file)
├── supabase_schema.sql   ← Run once in Supabase SQL Editor
├── README.md             ← This file
└── .gitignore            ← Keeps credentials out of git
```

---

## 🔒 Security Notes

- The **anon key** is safe to use in a browser app — it's designed for this
- Row Level Security (RLS) is enabled on the database
- **Never commit your credentials** — they are stored only in your browser's localStorage
- For a team/multi-user setup, add Supabase Auth (see [docs](https://supabase.com/docs/guides/auth))

---

## 🗃 Database Schema

| Column | Type | Description |
|---|---|---|
| `id` | uuid | Primary key (auto) |
| `first_name` | text | Client first name |
| `last_name` | text | Client last name |
| `email` | text | Email address |
| `phone` | text | Phone number |
| `address` | text | Client address |
| `project_type` | text | Living Room, Dining, Bedroom… |
| `stage` | text | New Lead → Sale Made |
| `home_call` | text | Yes / No |
| `home_call_date` | date | Date of home visit |
| `sale_made` | text | Yes / No |
| `gold_comp` | text | Yes / No |
| `probability` | integer | 10 / 25 / 50 / 75 / 90 / 100 |
| `estimate` | numeric | Project value in $ |
| `follow_up_date` | date | Next follow-up date |
| `next_step` | text | Action item |
| `notes` | text | Free text notes |
| `created_at` | timestamptz | Auto-set on insert |
| `updated_at` | timestamptz | Auto-updated on change |

---

## 📊 Business Logic (from Excel)

All formulas from the Excel system are replicated in JavaScript:

| Formula | Location |
|---|---|
| Weighted Pipeline = Probability × Estimate | `BL.getWeightedValue()` |
| Days Overdue = TODAY − Follow-Up Date | `BL.getDaysOverdue()` |
| Smart Email Topic (9-level IF) | `BL.getEmailTopic()` |
| Campaign Priority (SOLD/HIGH/MEDIUM/NURTURE) | `BL.getCampaignPriority()` |
| Conversion Rate = Sold / Total | `BL.calcKPIs()` |
| Monthly Revenue vs Goal | `BL.monthlyRevenue()` |
| GoldComp % of Sales | `BL.calcKPIs()` |

---

## 🔄 Updating the App

To update the app after making changes:

```bash
git add index.html
git commit -m "Update: describe your change"
git push origin main
```

GitHub Pages redeploys automatically within ~60 seconds.

---

## 💡 Tips

- **Offline:** If Supabase is unreachable, the app falls back to localStorage automatically
- **Multiple devices:** Sign in on any device with the same Supabase credentials
- **Export data:** In Supabase → Table Editor → `opportunities` → Download CSV
- **Reset demo:** Clear localStorage in Chrome DevTools → Application → Local Storage

---

## 🆓 Free Tier Limits

| Service | Free Limit | Your Usage |
|---|---|---|
| GitHub Pages | 1 GB storage, 100 GB/month bandwidth | ~1 MB, very low |
| Supabase | 500 MB database, 2 GB bandwidth/month | ~1 MB, very low |

Both are effectively unlimited for a single-user sales tool.

---

*Built for Ethan Allen · Carolina Medrado · 2026*
