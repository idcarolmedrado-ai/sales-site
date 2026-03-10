-- ══════════════════════════════════════════════════════════════
--  EA SALES INTELLIGENCE — SUPABASE SCHEMA
--  Carolina Medrado | Ethan Allen | 2026
--
--  HOW TO USE:
--    FRESH PROJECT  → Run the entire file (Steps 1–5)
--    EXISTING DB    → Run only the ALTER TABLE block at bottom
--
--  CHANGELOG:
--    v1 (2026-01) — Initial schema
--    v2 (2026-02) — homeCall, homeCallDate, goldComp added
--    v3 (2026-03) — closeDate (expected close + quarter)
--    v4 (2026-03) — Active client & delivery tracking (Tasks system)
-- ══════════════════════════════════════════════════════════════

-- ── Step 1: Clean slate (drops everything for a fresh install) ──
DROP TABLE   IF EXISTS opportunities CASCADE;
DROP FUNCTION IF EXISTS fn_compute_opp()    CASCADE;
DROP FUNCTION IF EXISTS fn_set_updated_at() CASCADE;

-- ── Step 2: Main opportunities table ──
CREATE TABLE opportunities (
  id                TEXT          PRIMARY KEY DEFAULT gen_random_uuid()::text,

  -- ── Contact ──────────────────────────────────────────────
  first_name        TEXT,
  last_name         TEXT,
  email             TEXT,
  phone             TEXT,
  address           TEXT,

  -- ── Project ──────────────────────────────────────────────
  project_type      TEXT,                        -- Living Room, Dining, Bedroom …
  lead_source       TEXT,                        -- Walk-in, Referral, Online …
  stage             TEXT,                        -- New Lead → Sale Made / Canceled

  -- ── Home call ────────────────────────────────────────────
  home_call         TEXT          DEFAULT 'No',  -- Yes | No
  home_call_date    TEXT,                        -- YYYY-MM-DD

  -- ── Sale ─────────────────────────────────────────────────
  sale_made         TEXT          DEFAULT 'No',  -- Yes | No
  gold_comp         TEXT          DEFAULT 'No',  -- Yes | No

  -- ── Pipeline ─────────────────────────────────────────────
  next_step         TEXT,
  probability       INTEGER       DEFAULT 0,     -- 0-100
  estimate          NUMERIC(12,2) DEFAULT 0,
  follow_up_date    TEXT,                        -- YYYY-MM-DD
  notes             TEXT,

  -- ── Close / quarter tracking (v3) ────────────────────────
  "closeDate"       TEXT,                        -- YYYY-MM-DD expected close
                                                 -- App derives quarter from this

  -- ── Active client tracking (v4) ──────────────────────────
  "customerNumber"  TEXT,        -- e.g. EA-2026-0001 (auto-assigned on first sale)
  "saleDate"        TEXT,        -- YYYY-MM-DD confirmed sale date
  "activePhase"     TEXT,        -- e.g. Design Review, Ordering, Production
  "deliveryDate"    TEXT,        -- YYYY-MM-DD scheduled delivery
  "linkReviewDate"  TEXT,        -- YYYY-MM-DD survey follow-up (auto: deliveryDate+7d)

  -- ── Issue tracking (v4) ──────────────────────────────────
  "issueFlag"       TEXT,        -- Yes | No
  "issueType"       TEXT,        -- Free-text description of issue
  "issueResult"     TEXT,        -- Yes (resolved) | No (open)

  -- ── Computed (set by trigger on every INSERT/UPDATE) ─────
  urgency_score     INTEGER       DEFAULT 0,
  win_tier          TEXT          DEFAULT 'COLD',
  month_auto        TEXT,

  -- ── Timestamps ───────────────────────────────────────────
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
  -- Win Tier
  new.win_tier := CASE
    WHEN new.sale_made = 'Yes'  THEN 'SOLD'
    WHEN new.stage = 'Canceled' THEN 'CANCELED'
    WHEN prob_int >= 75         THEN 'HOT'
    WHEN prob_int >= 50         THEN 'WARM'
    WHEN prob_int >= 25         THEN 'NURTURE'
    ELSE                             'COLD'
  END;

  -- Urgency Score (always 0 for Sold or Canceled)
  IF new.sale_made = 'Yes' OR new.stage = 'Canceled' THEN
    new.urgency_score := 0;
  ELSE
    BEGIN
      fup := new.follow_up_date::DATE;
      days_over := GREATEST(CURRENT_DATE - fup, 0);
    EXCEPTION WHEN OTHERS THEN
      days_over := 0;
    END;
    -- Formula: min( (days_overdue × 3) + (probability × 2) + floor(estimate/1000), 100 )
    new.urgency_score := LEAST((days_over * 3) + (prob_int * 2) + est_k, 100);
  END IF;

  -- Month Auto (for grouping): prefer home_call_date, fallback follow_up_date
  new.month_auto := NULL;
  BEGIN
    IF new.home_call_date IS NOT NULL AND new.home_call_date != '' THEN
      new.month_auto := TO_CHAR(new.home_call_date::DATE, 'Month YYYY');
    ELSIF new.follow_up_date IS NOT NULL AND new.follow_up_date != '' THEN
      new.month_auto := TO_CHAR(new.follow_up_date::DATE, 'Month YYYY');
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  new.updated_at := NOW();
  RETURN new;
END;
$$;

CREATE TRIGGER trg_opp_compute
  BEFORE INSERT OR UPDATE ON opportunities
  FOR EACH ROW EXECUTE FUNCTION fn_compute_opp();

-- ── Step 4: Row Level Security (allow anon read/write for the app) ──
ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_all" ON opportunities;
CREATE POLICY "anon_all" ON opportunities
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ── Step 5: Verify ──
SELECT COUNT(*) AS row_count FROM opportunities;


-- ══════════════════════════════════════════════════════════════
--  EXISTING PROJECT? Run ONLY these ALTER TABLE statements.
--  Each is idempotent (IF NOT EXISTS) — safe to run multiple times.
-- ══════════════════════════════════════════════════════════════

/*  ← Remove this comment line to run on an existing database

ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "closeDate"      TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "customerNumber" TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "saleDate"       TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "activePhase"    TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "deliveryDate"   TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "linkReviewDate" TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "issueFlag"      TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "issueType"      TEXT;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS "issueResult"    TEXT;

    ← Remove this comment line to run on an existing database  */
