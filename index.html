-- ══════════════════════════════════════════════════════════════
--  EA SALES INTELLIGENCE — SUPABASE SCHEMA (COMPLETE REBUILD)
--  Carolina Medrado | Ethan Allen | 2026
--  Run this entire file in Supabase → SQL Editor → Run
--  Expected result: "count | 0" with no errors
-- ══════════════════════════════════════════════════════════════

-- Step 1: Clean slate
drop table if exists opportunities cascade;
drop function if exists fn_compute_opp() cascade;
drop function if exists fn_set_updated_at() cascade;

-- Step 2: Create opportunities table with ALL columns
create table opportunities (
  id              text          primary key default gen_random_uuid()::text,

  -- Contact
  last_name       text,
  first_name      text,
  address         text,
  phone           text,
  email           text,

  -- Project
  project_type    text,
  lead_source     text,
  stage           text,

  -- Home call
  home_call       text,
  home_call_date  text,

  -- Sale
  sale_made       text          default 'No',
  gold_comp       text          default 'No',

  -- Pipeline
  next_step       text,
  probability     integer       default 0,
  estimate        numeric(12,2) default 0,
  follow_up_date  text,
  notes           text,

  -- Computed (updated by trigger)
  urgency_score   integer       default 0,
  win_tier        text          default 'COLD',
  month_auto      text,

  -- Timestamps
  created_at      timestamptz   default now(),
  updated_at      timestamptz   default now()
);

-- Step 3: Trigger to auto-compute urgency_score, win_tier, month_auto
create or replace function fn_compute_opp()
returns trigger language plpgsql as $$
declare
  days_over integer := 0;
  prob_int  integer := coalesce(new.probability, 0);
  est_k     integer := floor(coalesce(new.estimate, 0) / 1000);
  fup       date;
begin
  -- Win Tier
  new.win_tier := case
    when new.sale_made = 'Yes'  then 'SOLD'
    when new.stage = 'Canceled' then 'CANCELED'
    when prob_int >= 75         then 'HOT'
    when prob_int >= 50         then 'WARM'
    when prob_int >= 25         then 'NURTURE'
    else                             'COLD'
  end;

  -- Urgency Score (0 for Sold/Canceled)
  if new.sale_made = 'Yes' or new.stage = 'Canceled' then
    new.urgency_score := 0;
  else
    begin
      fup := new.follow_up_date::date;
      days_over := greatest(current_date - fup, 0);
    exception when others then
      days_over := 0;
    end;
    new.urgency_score := (days_over * 3) + (prob_int * 2) + est_k;
  end if;

  -- Month Auto (from home_call_date, else follow_up_date)
  new.month_auto := null;
  begin
    if new.home_call_date is not null and new.home_call_date != '' then
      new.month_auto := to_char(new.home_call_date::date, 'Month YYYY');
    elsif new.follow_up_date is not null and new.follow_up_date != '' then
      new.month_auto := to_char(new.follow_up_date::date, 'Month YYYY');
    end if;
  exception when others then
    null;
  end;

  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_opp_compute
  before insert or update on opportunities
  for each row execute function fn_compute_opp();

-- Step 4: Row Level Security
alter table opportunities enable row level security;

drop policy if exists "anon_all" on opportunities;
create policy "anon_all" on opportunities
  for all to anon using (true) with check (true);

-- Step 5: Verify
select count(*) from opportunities;
