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
