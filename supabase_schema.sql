-- ══════════════════════════════════════════════════════════════
--  EA SALES INTELLIGENCE — SUPABASE SCHEMA
--  Carolina Medrado | Ethan Allen | 2026
--
--  HOW TO USE:
--    FRESH PROJECT  → Run the entire file (Steps 1–5)
--    EXISTING DB    → Run only the ALTER TABLE block at the bottom
--
--  CHANGELOG:
--    v1 (2026-01) — Initial schema
--    v2 (2026-02) — homeCall, homeCallDate, goldComp added
--    v3 (2026-03) — closeDate (expected close + fiscal quarter tracking)
--    v4 (2026-03) — Active client & delivery tracking (customerNumber,
--                   saleDate, activePhase, deliveryDate, linkReviewDate,
--                   issueFlag, issueType, issueResult)
--    v4.1 (2026-03) — App: Tasks tab renamed to Active (post-sale tracker),
--    v4.2 (2026-03) — goldCompValue: separate GoldComp credit field;
--                     task/active/mail completion tracking (localStorage);
--                     mileage auto-seed from home calls; Post-30/60 auto-sync
--                     delivery date from opportunity; sales/analytics line
--                     charts with year/month filter toggles.
--    v4.3 (2026-03) — Contact List export (CSV + Excel 3-sheet) on Mailing tab;
--                     Security Center page with score, audit log, PIN settings;
--                     PIN system: optional startup lock (off by default),
--                     device-unique salt, 4/6-digit support, verify-old flow;
--                     CSP hardened (frame-ancestors:none, no CDN scripts);
--                     Input validation (email, phone, prob, estimate);
--                     getQuarter() fixed to EA fiscal year (Jul=Q1);
--                     135 automated tests (batch 50-opp suite).
--
--  FISCAL QUARTERS (EA year):
--    Q1 = Jul–Sep  |  Q2 = Oct–Dec
--    Q3 = Jan–Mar  |  Q4 = Apr–Jun
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
--  FRESH INSTALL — Steps 1–5
--  Skip this entire section if your database is already running.
-- ══════════════════════════════════════════════════════════════

-- ── Step 1: Clean slate (drops everything for a fresh install) ──
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
  project_type      TEXT,         -- Living Room, Dining, Bedroom, Office,
                                  -- Window Treatment, Drapery …
  lead_source       TEXT,         -- Walk-in, Referral, Online, Social Media …
  stage             TEXT,         -- New Lead | Home Call | Design in Progress |
                                  -- Quote Sent | Follow-up | Pending Decision |
                                  -- Sale Made | Postponed | Canceled

  -- ── Home Call ──────────────────────────────────────────────
  home_call         TEXT          DEFAULT 'No',  -- Yes | No
  home_call_date    TEXT,                         -- YYYY-MM-DD

  -- ── Sale ───────────────────────────────────────────────────
  sale_made         TEXT          DEFAULT 'No',  -- Yes | No
  gold_comp         TEXT          DEFAULT 'No',  -- Yes | No  (GoldComp program)

  -- ── Pipeline ───────────────────────────────────────────────
  next_step         TEXT,                         -- Next required action
  probability       INTEGER       DEFAULT 0,      -- 0–100 (%)
  estimate          NUMERIC(12,2) DEFAULT 0,      -- Project value in USD
  follow_up_date    TEXT,                         -- YYYY-MM-DD
  notes             TEXT,

  -- ── Expected Close / Quarter Tracking (v3) ─────────────────
  "closeDate"       TEXT,         -- YYYY-MM-DD  expected close date
                                  -- App derives fiscal quarter (Q1–Q4) from this

  -- ── Active Client Tracking (v4) ────────────────────────────
  --    These fields are populated automatically when sale_made = 'Yes'
  "customerNumber"  TEXT,         -- EA-YYYY-XXXX  (auto-assigned on first sale)
  "saleDate"        TEXT,         -- YYYY-MM-DD    confirmed sale date
  "activePhase"     TEXT,         -- Design Review | Ordering | Production |
                                  -- In Transit | Delivered
  "deliveryDate"    TEXT,         -- YYYY-MM-DD    scheduled delivery date
  "linkReviewDate"  TEXT,         -- YYYY-MM-DD    survey/review follow-up
                                  --               (auto-set: deliveryDate + 7 days)

  -- ── GoldComp Value (v4.2) ──────────────────────────────────
  --    Separate credit amount for the GoldComp program.
  --    Displayed alongside estimate in Sales, Active, and Analytics tabs.
  "goldCompValue"   NUMERIC(12,2) DEFAULT 0,  -- GoldComp credit USD

  -- ── Issue Tracking (v4) ────────────────────────────────────
  --    Used by the Active Clients tab to flag and resolve post-sale issues
  "issueFlag"       TEXT,         -- Yes | No
  "issueType"       TEXT,         -- Free-text  (e.g. damage, delay, wrong item)
  "issueResult"     TEXT,         -- Yes (resolved) | No (still open)

  -- ── Server-computed fields ──────────────────────────────────
  --    Set automatically by trigger fn_compute_opp() on every INSERT/UPDATE
  urgency_score     INTEGER       DEFAULT 0,
  win_tier          TEXT          DEFAULT 'COLD',
  month_auto        TEXT,         -- e.g. "March 2026"  (for analytics grouping)

  -- ── Timestamps ─────────────────────────────────────────────
  created_at        TIMESTAMPTZ   DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   DEFAULT NOW()
);


-- ── Step 3: Trigger — auto-compute urgency_score, win_tier, month_auto ──

CREATE OR REPLACE FUNCTION fn_compute_opp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  days_over INTEGER := 0;
  prob_int  INTEGER := COALESCE(new.probability, 0);
  est_k     INTEGER := FLOOR(COALESCE(new.estimate, 0) / 1000);
  fup       DATE;
BEGIN

  -- ── Win Tier ────────────────────────────────────────────────
  --    Priority order: SOLD > CANCELED > HOT > WARM > NURTURE > COLD
  new.win_tier := CASE
    WHEN new.sale_made = 'Yes'  THEN 'SOLD'
    WHEN new.stage = 'Canceled' THEN 'CANCELED'
    WHEN prob_int >= 75         THEN 'HOT'
    WHEN prob_int >= 50         THEN 'WARM'
    WHEN prob_int >= 25         THEN 'NURTURE'
    ELSE                             'COLD'
  END;

  -- ── Urgency Score ───────────────────────────────────────────
  --    Formula: MIN( (days_overdue × 3) + (probability × 2) + FLOOR(estimate/1000), 100 )
  --    Always 0 for Sold or Canceled records.
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
  --    For dashboard grouping and analytics pages.
  --    Prefers home_call_date; falls back to follow_up_date.
  --    Uses FMMonth to suppress padding spaces (e.g. "March 2026" not "March     2026").
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


-- ── Step 4: Row Level Security ──────────────────────────────
--    Allows the anonymous (anon) key used by the app to read and write.
--    Tighten this policy if you add user authentication later.

ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;

-- ── Per-operation policies (v4.3 — more granular than anon_all) ─────
--    Replaces the single "anon_all" catch-all with explicit policies.
--    This is the recommended setup. Run the DROP first if upgrading.
DROP POLICY IF EXISTS "anon_all" ON opportunities;

CREATE POLICY "anon_select" ON opportunities
  FOR SELECT TO anon USING (true);

CREATE POLICY "anon_insert" ON opportunities
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update" ON opportunities
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_delete" ON opportunities
  FOR DELETE TO anon USING (true);


-- ── Step 5: Verify ──────────────────────────────────────────
SELECT
  COUNT(*)                                       AS total_rows,
  COUNT(*) FILTER (WHERE sale_made   = 'Yes')    AS sold,
  COUNT(*) FILTER (WHERE stage       = 'Canceled') AS canceled,
  COUNT(*) FILTER (WHERE sale_made  != 'Yes'
                     AND stage      != 'Canceled') AS active_pipeline,
  COUNT(*) FILTER (WHERE "customerNumber" IS NOT NULL
                     AND "customerNumber" <> '')   AS with_customer_number,
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
--    2. Remove the opening  /*  and closing  */  delimiters
--    3. Highlight the ALTER TABLE statements and click Run
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this line to activate

-- v3: Expected close date + quarter tracking
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

-- v4.2: GoldComp credit value (separate from product estimate)
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "goldCompValue"  NUMERIC(12,2) DEFAULT 0;

    ← Remove this line to activate  */
