-- ══════════════════════════════════════════════════════════════
--  EA SALES INTELLIGENCE — SUPABASE SCHEMA  v4.3 FINAL
--  Carolina Medrado | Ethan Allen | 2026
--
--  HOW TO USE:
--    FRESH PROJECT  → Run the ENTIRE file (Steps 1–5)
--    EXISTING DB    → Run ONLY the ALTER TABLE block at the bottom
--                     (remove the /* ... */ delimiters first)
--
--  CHANGELOG:
--    v1   (2026-01) — Initial schema
--    v2   (2026-02) — homeCall, homeCallDate, goldComp
--    v3   (2026-03) — closeDate (expected close + EA fiscal quarter)
--    v4   (2026-03) — Active client tracking: customerNumber, saleDate,
--                     activePhase, deliveryDate, linkReviewDate,
--                     issueFlag, issueType, issueResult
--    v4.2 (2026-03) — goldCompValue (separate GoldComp credit field)
--    v4.3 (2026-03) — Final release:
--                     • 125-test suite (100-opp simulation)
--                     • EA fiscal year: Q1=Jul-Sep, Q2=Oct-Dec,
--                       Q3=Jan-Mar, Q4=Apr-Jun
--                     • offsetDate() empty-string guard
--                     • Analytics filtSold respects year/month filter
--                     • monthRevMap includes goldCompValue
--                     • gcSales = goldCompValue || estimate for GoldComp opps
--                     • Tasks dashboard: ✓ Done button + Post-30/60 tasks
--                     • Active tab: Edit / Done / Delete buttons
--                     • Mailing: Mark Sent, Sent box, Contact List + CSV export
--                     • Lead form: Product Value + GoldComp Value fields
--                     • Post-30/60: delivery date auto-pulled from opp record
--                     • Mileage: auto-sync date/name/address from Home Call opp
--                     • Analytics: year + month chip filters
--
--  FISCAL QUARTERS (EA fiscal year):
--    Q1 = Jul–Sep  |  Q2 = Oct–Dec
--    Q3 = Jan–Mar  |  Q4 = Apr–Jun
--
--  JAVASCRIPT BUSINESS LOGIC (app formulas for reference):
--
--    Win Tier:
--      SOLD     → saleMade = 'Yes'
--      CANCELED → stage = 'Canceled'
--      HOT      → probability >= 75
--      WARM     → probability >= 50
--      NURTURE  → probability >= 25
--      COLD     → probability < 25
--
--    Urgency Score (capped at 100):
--      MIN( (days_overdue × 3) + (probability × 2) + FLOOR(estimate/1000), 100 )
--      Always 0 for SOLD or CANCELED records.
--
--    Weighted Pipeline (excludes SOLD and CANCELED):
--      FLOOR( probability/100 × estimate )
--
--    GoldComp Sales Credit:
--      goldCompValue  when goldComp = 'Yes' and goldCompValue > 0
--      estimate       when goldComp = 'Yes' and goldCompValue = 0 (fallback)
--
--    Total Sale per Opportunity:
--      estimate + goldCompValue  (when goldComp = 'Yes')
--      estimate                  (otherwise)
--
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
--  FRESH INSTALL — Steps 1–5
--  (Skip this entire section if your database is already running.)
-- ══════════════════════════════════════════════════════════════

-- ── Step 1: Clean slate ────────────────────────────────────────
DROP TABLE    IF EXISTS opportunities        CASCADE;
DROP FUNCTION IF EXISTS fn_compute_opp()    CASCADE;
DROP FUNCTION IF EXISTS fn_set_updated_at() CASCADE;


-- ── Step 2: Main opportunities table ──────────────────────────
CREATE TABLE opportunities (
  id                TEXT          PRIMARY KEY DEFAULT gen_random_uuid()::text,

  -- ── Contact ────────────────────────────────────────────────
  first_name        TEXT,
  last_name         TEXT,
  email             TEXT,
  phone             TEXT,
  address           TEXT,

  -- ── Project ────────────────────────────────────────────────
  project_type      TEXT,
  lead_source       TEXT,
  stage             TEXT,         -- New Lead | Home Call | Design in Progress |
                                  -- Quote Sent | Follow-up | Pending Decision |
                                  -- Sale Made | Postponed | Canceled

  -- ── Home Call ──────────────────────────────────────────────
  home_call         TEXT          DEFAULT 'No',   -- Yes | No
  home_call_date    TEXT,                          -- YYYY-MM-DD

  -- ── Sale ───────────────────────────────────────────────────
  sale_made         TEXT          DEFAULT 'No',   -- Yes | No
  gold_comp         TEXT          DEFAULT 'No',   -- Yes | No

  -- ── Pipeline ───────────────────────────────────────────────
  next_step         TEXT,
  probability       INTEGER       DEFAULT 0,       -- 0–100 (%)
  estimate          NUMERIC(12,2) DEFAULT 0,       -- Product value USD
  follow_up_date    TEXT,                          -- YYYY-MM-DD
  notes             TEXT,

  -- ── GoldComp Credit (v4.2) ─────────────────────────────────
  --    Separate credit amount earned through the GoldComp program.
  --    Shown alongside estimate in Sales, Active, and Analytics tabs.
  --    gcSales formula: goldCompValue ?? estimate (for GoldComp=Yes opps)
  "goldCompValue"   NUMERIC(12,2) DEFAULT 0,

  -- ── Expected Close / Fiscal Quarter Tracking (v3) ──────────
  "closeDate"       TEXT,                          -- YYYY-MM-DD

  -- ── Active Client Tracking (v4) ────────────────────────────
  --    Populated automatically when sale_made = 'Yes'
  "customerNumber"  TEXT,         -- Manual entry, e.g. C-2026-0042
  "saleDate"        TEXT,         -- YYYY-MM-DD  confirmed sale date
  "activePhase"     TEXT,         -- Design Review | Ordering | Production |
                                  -- In Transit | Delivered
  "deliveryDate"    TEXT,         -- YYYY-MM-DD  scheduled delivery date
                                  -- ← drives Post-30 and Post-60 follow-up tasks
  "linkReviewDate"  TEXT,         -- YYYY-MM-DD  survey/review follow-up date

  -- ── Issue Tracking (v4) ────────────────────────────────────
  "issueFlag"       TEXT,         -- Yes | No
  "issueType"       TEXT,         -- e.g. damage, delay, wrong item
  "issueResult"     TEXT,         -- Yes (resolved) | No (still open)

  -- ── Sale Order Tracking (v4.6) ─────────────────────────────
  "saleOrderNumber" TEXT,         -- Internal sale order reference
  "saleAmount"      NUMERIC(12,2) DEFAULT 0,  -- Actual sale price

  -- ── Cancellation Tracking (v4.7) ───────────────────────────
  "cancelReason"    TEXT,         -- Why the deal was lost
  "cancelNotes"     TEXT,         -- Additional cancellation details

  -- ── Server-computed (set by trigger on every write) ─────────
  urgency_score     INTEGER       DEFAULT 0,
  win_tier          TEXT          DEFAULT 'COLD',
  month_auto        TEXT,         -- e.g. "March 2026"

  -- ── Timestamps ─────────────────────────────────────────────
  created_at        TIMESTAMPTZ   DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   DEFAULT NOW()
);


-- ── Step 3: Computed-fields trigger ────────────────────────────
--
--    Runs BEFORE INSERT OR UPDATE.
--    Keeps win_tier, urgency_score, and month_auto in sync automatically.

CREATE OR REPLACE FUNCTION fn_compute_opp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  days_over INTEGER := 0;
  prob_int  INTEGER := COALESCE(new.probability, 0);
  est_k     INTEGER := FLOOR(COALESCE(new.estimate, 0) / 1000);
  fup       DATE;
BEGIN

  -- ── Win Tier ────────────────────────────────────────────────
  new.win_tier := CASE
    WHEN new.sale_made = 'Yes'  THEN 'SOLD'
    WHEN new.stage = 'Canceled' THEN 'CANCELED'
    WHEN prob_int >= 75         THEN 'HOT'
    WHEN prob_int >= 50         THEN 'WARM'
    WHEN prob_int >= 25         THEN 'NURTURE'
    ELSE                             'COLD'
  END;

  -- ── Urgency Score ───────────────────────────────────────────
  --    MIN( (days_overdue × 3) + (probability × 2) + FLOOR(estimate/1000), 100 )
  IF new.sale_made = 'Yes' OR new.stage = 'Canceled' THEN
    new.urgency_score := 0;
  ELSE
    BEGIN
      fup       := new.follow_up_date::DATE;
      days_over := GREATEST(CURRENT_DATE - fup, 0);
    EXCEPTION WHEN OTHERS THEN
      days_over := 0;
    END;
    new.urgency_score := LEAST((days_over * 3) + (prob_int * 2) + est_k, 100);
  END IF;

  -- ── Month Auto ──────────────────────────────────────────────
  --    Prefers home_call_date; falls back to follow_up_date.
  new.month_auto := NULL;
  BEGIN
    IF new.home_call_date IS NOT NULL AND new.home_call_date <> '' THEN
      new.month_auto := TO_CHAR(new.home_call_date::DATE, 'FMMonth YYYY');
    ELSIF new.follow_up_date IS NOT NULL AND new.follow_up_date <> '' THEN
      new.month_auto := TO_CHAR(new.follow_up_date::DATE, 'FMMonth YYYY');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  new.updated_at := NOW();
  RETURN new;
END;
$$;

CREATE TRIGGER trg_opp_compute
  BEFORE INSERT OR UPDATE ON opportunities
  FOR EACH ROW EXECUTE FUNCTION fn_compute_opp();


-- ── Step 4: Row Level Security ─────────────────────────────────
--    Grants the anonymous (anon) key full read/write access.
--    Tighten these policies when you add user authentication.

ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;

-- Drop legacy catch-all policy if it exists
DROP POLICY IF EXISTS "anon_all" ON opportunities;

CREATE POLICY "anon_select" ON opportunities
  FOR SELECT TO anon USING (true);

CREATE POLICY "anon_insert" ON opportunities
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update" ON opportunities
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_delete" ON opportunities
  FOR DELETE TO anon USING (true);


-- ── Step 5: Verification query ─────────────────────────────────
SELECT
  COUNT(*)                                         AS total_rows,
  COUNT(*) FILTER (WHERE sale_made   = 'Yes')      AS sold,
  COUNT(*) FILTER (WHERE stage       = 'Canceled') AS canceled,
  COUNT(*) FILTER (WHERE sale_made  != 'Yes'
                     AND stage      != 'Canceled') AS active_pipeline,
  COUNT(*) FILTER (WHERE "customerNumber" IS NOT NULL
                     AND "customerNumber" <> '')   AS with_customer_number,
  COUNT(*) FILTER (WHERE "goldCompValue"  > 0)     AS with_goldcomp_value,
  COUNT(*) FILTER (WHERE "issueFlag" = 'Yes'
                     AND "issueResult" <> 'Yes')   AS open_issues
FROM opportunities;


-- ══════════════════════════════════════════════════════════════
--  EXISTING DATABASE — Run ONLY the block below.
--
--  Each ADD COLUMN uses IF NOT EXISTS — fully idempotent.
--  Safe to run multiple times with zero risk of data loss.
--
--  HOW TO RUN:
--    1. Open Supabase project → SQL Editor
--    2. Remove the opening  /*  and closing  */  below
--    3. Paste into the editor and click Run
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this line

-- v3: Expected close date
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "closeDate"      TEXT;

-- v4: Active client tracking
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "customerNumber" TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "saleDate"       TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "activePhase"    TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "deliveryDate"   TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "linkReviewDate" TEXT;

-- v4: Issue tracking
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "issueFlag"      TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "issueType"      TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "issueResult"    TEXT;

-- v4.2 / v4.3: GoldComp credit value
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "goldCompValue"  NUMERIC(12,2) DEFAULT 0;

-- v4.3: Refresh trigger to pick up any function changes
CREATE OR REPLACE FUNCTION fn_compute_opp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  days_over INTEGER := 0;
  prob_int  INTEGER := COALESCE(new.probability, 0);
  est_k     INTEGER := FLOOR(COALESCE(new.estimate, 0) / 1000);
  fup       DATE;
BEGIN
  new.win_tier := CASE
    WHEN new.sale_made = 'Yes'  THEN 'SOLD'
    WHEN new.stage = 'Canceled' THEN 'CANCELED'
    WHEN prob_int >= 75         THEN 'HOT'
    WHEN prob_int >= 50         THEN 'WARM'
    WHEN prob_int >= 25         THEN 'NURTURE'
    ELSE                             'COLD'
  END;
  IF new.sale_made = 'Yes' OR new.stage = 'Canceled' THEN
    new.urgency_score := 0;
  ELSE
    BEGIN
      fup       := new.follow_up_date::DATE;
      days_over := GREATEST(CURRENT_DATE - fup, 0);
    EXCEPTION WHEN OTHERS THEN
      days_over := 0;
    END;
    new.urgency_score := LEAST((days_over * 3) + (prob_int * 2) + est_k, 100);
  END IF;
  new.month_auto := NULL;
  BEGIN
    IF new.home_call_date IS NOT NULL AND new.home_call_date <> '' THEN
      new.month_auto := TO_CHAR(new.home_call_date::DATE, 'FMMonth YYYY');
    ELSIF new.follow_up_date IS NOT NULL AND new.follow_up_date <> '' THEN
      new.month_auto := TO_CHAR(new.follow_up_date::DATE, 'FMMonth YYYY');
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  new.updated_at := NOW();
  RETURN new;
END;
$$;

    ← Remove this line  */


-- ══════════════════════════════════════════════════════════════
--  v4.4 FIELD SEMANTIC UPDATES (no new columns needed)
--
--  The following existing columns have been repurposed in the app:
--
--  issue_flag   → "Next Follow-up (Date)"  — stores a date string (YYYY-MM-DD)
--                  Previously: Yes/No flag. Now: follow-up date for active phase.
--
--  issue_type   → "Details"               — free-text notes about the active phase
--                  Previously: issue description. Now: general phase details.
--
--  issue_result → "Active Phase Result"   — Done | Postpone
--                  Previously: Yes/No resolved flag.
--                  Done    = case closed, removed from Tasks dashboard
--                  Postpone = appears in Tasks dashboard
--
--  active_phase → dropdown:
--                  Design Review | Balance Due | Exchange |
--                  Cancelation | GoldComp | Issue | Other
--
--  customer_number → MANUAL entry only (no auto-generation).
--                    Format recommended: EA-YYYY-XXXX
--
--  link_review_date → AUTO-CALCULATED: delivery_date + 5 days
--                     (previously +7 days)
--
--  PIPELINE rule:
--    sale_made = 'Yes' → client moves to ACTIVES, removed from Pipeline
--
--  POST 60 rule:
--    All sold clients with a delivery date appear in POST 60
--    follow_up_60 = delivery_date + 60 days
--    (previously only Post30 clients where new_opportunity = 'No')
--
--  No ALTER TABLE statements needed — column names unchanged.
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
--  v4.5 DATE & GOALS FIXES (no schema changes needed)
--
--  All fixes are app-logic only — no ALTER TABLE required.
--
--  DATE ASSIGNMENT FIXES:
--    Sales tab / renderSales:
--      Sales are now grouped by closeDate || saleDate only.
--      followUpDate is NO LONGER used as a fallback for sale grouping
--      (followUpDate is the next-action date, not the sale date).
--
--    getMonthAuto() (used by calcKPIs, Dashboard, Analytics):
--      For sold opps: now uses closeDate || saleDate || homeCallDate
--      For pipeline opps: uses homeCallDate || followUpDate (unchanged)
--
--    Sales months displayed in chronological order (oldest → newest).
--
--  MONTHLY GOALS FIXES:
--    Goals are now stored per year: key = "{year}-{monthIndex}"
--      e.g. "2026-2" = March 2026, "2025-10" = November 2025
--    Old format (key = monthIndex integer) is still readable (backward compat).
--
--    Goal editor now shows Month + Year dropdowns — any month in any year
--    can be edited, including past months.
--
--    Year tab now shows Goal ($) and vs Goal (%) per month card,
--    with an Edit Goal button that pre-fills the correct month/year.
--
--  TEST FIX:
--    T84 isDueToday: simplified to followUpDate === todayStr() only.
--    SIM_TODAY in test suite: dynamically set to real today's date.
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
--  v4.6 — Sale Order # and Sale Amount (2026-04)
--
--  New columns for tracking sale order numbers and actual sale amounts.
--  saleAmount allows recording the real sale price separately from estimate.
--
--  For EXISTING databases, run:
--    ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "saleOrderNumber" TEXT;
--    ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "saleAmount" NUMERIC(12,2) DEFAULT 0;
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
--  v4.7 — Cancellation Reason Tracking (2026-04)
--
--  New columns for capturing why deals were lost/canceled.
--  Shown in the lead form when stage = Canceled.
--
--  For EXISTING databases, run:
--    ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "cancelReason" TEXT;
--    ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "cancelNotes" TEXT;
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
--  v5.0 — Cloud Storage for Files (2026-04)
--
--  Moves file attachments (contracts, proposals, POs, photos)
--  and profile pictures from browser localStorage to Supabase
--  Storage. Adds attachments table to track file metadata.
--
--  Run the following in Supabase SQL Editor:
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this line

-- ── Create attachments table for file metadata ────────────────
CREATE TABLE IF NOT EXISTS attachments (
  id           BIGSERIAL PRIMARY KEY,
  opp_id       TEXT NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  file_name    TEXT NOT NULL,
  file_path    TEXT NOT NULL UNIQUE,   -- path in Supabase Storage bucket
  file_size    INTEGER,
  file_type    TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attachments_opp_id ON attachments(opp_id);

-- Enable RLS and allow anon access (matches opportunities policy)
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_att_select" ON attachments;
DROP POLICY IF EXISTS "anon_att_insert" ON attachments;
DROP POLICY IF EXISTS "anon_att_delete" ON attachments;

CREATE POLICY "anon_att_select" ON attachments FOR SELECT TO anon USING (true);
CREATE POLICY "anon_att_insert" ON attachments FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_att_delete" ON attachments FOR DELETE TO anon USING (true);


-- ── Create Storage buckets ────────────────────────────────────
-- attachments: private bucket for lead files (contracts, PDFs)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'attachments',
  'attachments',
  true,                                       -- public for easier downloads (signed URLs)
  10485760,                                   -- 10MB limit
  ARRAY['application/pdf','image/jpeg','image/png','image/gif',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/msword','application/vnd.ms-excel','text/plain']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- avatars: public bucket for profile pictures
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,                                       -- public for display in nav
  1048576,                                    -- 1MB limit
  ARRAY['image/jpeg','image/png','image/gif','image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;


-- ── Storage policies (allow anon read/write) ──────────────────
DROP POLICY IF EXISTS "Attachments anon upload" ON storage.objects;
DROP POLICY IF EXISTS "Attachments anon read"   ON storage.objects;
DROP POLICY IF EXISTS "Attachments anon delete" ON storage.objects;
DROP POLICY IF EXISTS "Avatars anon upload"     ON storage.objects;
DROP POLICY IF EXISTS "Avatars anon read"       ON storage.objects;
DROP POLICY IF EXISTS "Avatars anon delete"     ON storage.objects;

CREATE POLICY "Attachments anon upload" ON storage.objects
  FOR INSERT TO anon WITH CHECK (bucket_id = 'attachments');
CREATE POLICY "Attachments anon read" ON storage.objects
  FOR SELECT TO anon USING (bucket_id = 'attachments');
CREATE POLICY "Attachments anon delete" ON storage.objects
  FOR DELETE TO anon USING (bucket_id = 'attachments');

CREATE POLICY "Avatars anon upload" ON storage.objects
  FOR INSERT TO anon WITH CHECK (bucket_id = 'avatars');
CREATE POLICY "Avatars anon read" ON storage.objects
  FOR SELECT TO anon USING (bucket_id = 'avatars');
CREATE POLICY "Avatars anon delete" ON storage.objects
  FOR DELETE TO anon USING (bucket_id = 'avatars');

    ← Remove this line  */


-- ══════════════════════════════════════════════════════════════
--  v5.1 — Audit Trail + User Settings tables (2026-04)
--
--  Moves audit_trail (stage changes, edit history) and user_settings
--  (profile, password hash) from browser localStorage to Supabase.
--
--  Run in Supabase SQL Editor:
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this line

CREATE TABLE IF NOT EXISTS audit_trail (
  id           BIGSERIAL PRIMARY KEY,
  opp_id       TEXT NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  event_type   TEXT,           -- stage | edit | create | note | sale
  detail       TEXT,
  event_at     TEXT            -- user-local date string like "2026-04-15 14:30"
);
CREATE INDEX IF NOT EXISTS idx_audit_opp_id ON audit_trail(opp_id, id DESC);

ALTER TABLE audit_trail ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_audit_select" ON audit_trail;
DROP POLICY IF EXISTS "anon_audit_insert" ON audit_trail;
DROP POLICY IF EXISTS "anon_audit_delete" ON audit_trail;
CREATE POLICY "anon_audit_select" ON audit_trail FOR SELECT TO anon USING (true);
CREATE POLICY "anon_audit_insert" ON audit_trail FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_audit_delete" ON audit_trail FOR DELETE TO anon USING (true);


CREATE TABLE IF NOT EXISTS user_settings (
  key_name     TEXT PRIMARY KEY,    -- 'profile' | 'password_hash' | 'language' | etc
  value        JSONB,
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_settings_select" ON user_settings;
DROP POLICY IF EXISTS "anon_settings_upsert" ON user_settings;
DROP POLICY IF EXISTS "anon_settings_delete" ON user_settings;
CREATE POLICY "anon_settings_select" ON user_settings FOR SELECT TO anon USING (true);
CREATE POLICY "anon_settings_upsert" ON user_settings FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_settings_update" ON user_settings FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_settings_delete" ON user_settings FOR DELETE TO anon USING (true);

    ← Remove this line  */


-- ══════════════════════════════════════════════════════════════
--  v5.2 — Mileage Records table (2026-04)
--
--  Moves mileage tracking (IRS reimbursement data) from browser
--  localStorage to Supabase for cross-device and loss-proof storage.
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this line

CREATE TABLE IF NOT EXISTS mileage_records (
  id              TEXT PRIMARY KEY,
  date            TEXT,
  "clientName"    TEXT,
  address         TEXT,
  "stopHome1"     NUMERIC(10,2) DEFAULT 0,
  "stopDC1"       NUMERIC(10,2) DEFAULT 0,
  "stopClient"    NUMERIC(10,2) DEFAULT 0,
  "stopHome2"     NUMERIC(10,2) DEFAULT 0,
  "stopDC2"       NUMERIC(10,2) DEFAULT 0,
  "totalMiles"    NUMERIC(10,2) DEFAULT 0,
  "commuteDeduct" NUMERIC(10,2) DEFAULT 0,
  "netMiles"      NUMERIC(10,2) DEFAULT 0,
  "tollsParking"  NUMERIC(10,2) DEFAULT 0,
  "totalReimbursement" NUMERIC(10,2) DEFAULT 0,
  "designPartner" TEXT,
  purpose         TEXT,
  "sourceOppId"   TEXT,
  "isManual"      BOOLEAN DEFAULT FALSE,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE mileage_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_mile_select" ON mileage_records;
DROP POLICY IF EXISTS "anon_mile_insert" ON mileage_records;
DROP POLICY IF EXISTS "anon_mile_update" ON mileage_records;
DROP POLICY IF EXISTS "anon_mile_delete" ON mileage_records;
CREATE POLICY "anon_mile_select" ON mileage_records FOR SELECT TO anon USING (true);
CREATE POLICY "anon_mile_insert" ON mileage_records FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_mile_update" ON mileage_records FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_mile_delete" ON mileage_records FOR DELETE TO anon USING (true);

    ← Remove this line  */


-- ══════════════════════════════════════════════════════════════
--  v5.3 — Post Delivery tracking (Post-30/60) (2026-04)
--
--  Moves delivery follow-up tracking from browser localStorage to
--  Supabase. One row per sold opportunity tracks both 30-day and
--  60-day check-ins.
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this line

CREATE TABLE IF NOT EXISTS post_delivery_records (
  "oppId"             TEXT PRIMARY KEY REFERENCES opportunities(id) ON DELETE CASCADE,
  "deliveryDate"      TEXT,
  "contactReason"     TEXT,
  "newOpportunity"    TEXT,         -- Yes | No | ''
  notes               TEXT,
  "p60_contactReason" TEXT,
  "p60_newOpportunity" TEXT,
  "p60_notes"         TEXT,
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE post_delivery_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_post_select" ON post_delivery_records;
DROP POLICY IF EXISTS "anon_post_insert" ON post_delivery_records;
DROP POLICY IF EXISTS "anon_post_update" ON post_delivery_records;
DROP POLICY IF EXISTS "anon_post_delete" ON post_delivery_records;
CREATE POLICY "anon_post_select" ON post_delivery_records FOR SELECT TO anon USING (true);
CREATE POLICY "anon_post_insert" ON post_delivery_records FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_post_update" ON post_delivery_records FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_post_delete" ON post_delivery_records FOR DELETE TO anon USING (true);

    ← Remove this line  */
