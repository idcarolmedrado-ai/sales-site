-- ═══════════════════════════════════════════════════════════════════
--  EA Sales Intelligence — Supabase Schema v3 (FIXED)
--  Carolina Medrado | Ethan Allen 2026
--
--  Fix: replaced current_date in GENERATED columns with triggers
--  (Postgres generated columns require immutable expressions only)
--
--  HOW TO USE:
--  1. Go to supabase.com → your project → SQL Editor
--  2. Paste this ENTIRE file and click Run
--  3. Safe to re-run (uses IF NOT EXISTS / OR REPLACE)
-- ═══════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";


-- ════════════════════════════════════════════════════════════════════
-- TABLE: opportunities
-- ════════════════════════════════════════════════════════════════════
create table if not exists opportunities (
  id              uuid          primary key default uuid_generate_v4(),

  last_name       text          not null,
  first_name      text          not null,
  address         text,
  phone           text,
  email           text,

  project_type    text,
  lead_source     text,

  stage           text,
  home_call       text,
  home_call_date  date,
  sale_made       text,
  next_step       text,
  probability     integer       default 0,
  estimate        numeric(12,2) default 0,
  follow_up_date  date,
  notes           text,
  month_auto      text,

  -- Computed by trigger (not generated columns — avoids current_date restriction)
  urgency_score   integer       default 0,
  win_tier        text          default '❓ UNKNOWN',

  created_at      timestamptz   default now(),
  updated_at      timestamptz   default now()
);

-- ── Trigger function: compute urgency_score + win_tier on every insert/update ──
create or replace function compute_opp_fields()
returns trigger language plpgsql as $$
begin
  -- win_tier (immutable logic — no current_date needed)
  new.win_tier := case
    when new.sale_made  = 'Yes'   then '✅ SOLD'
    when new.stage      = 'Canceled' then '❌ CANCELED'
    when new.probability is null  then '❓ UNKNOWN'
    when new.probability >= 75    then '🔥 HOT'
    when new.probability >= 50    then '⚡ WARM'
    when new.probability >= 25    then '📋 NURTURE'
    else                               '❄️ COLD'
  end;

  -- urgency_score (uses current_date — only valid inside a trigger, not generated col)
  new.urgency_score := case
    when new.sale_made = 'Yes'    then 0
    when new.stage = 'Canceled'   then 0
    else coalesce(
      greatest(current_date - new.follow_up_date, 0) * 3
      + coalesce(new.probability, 0) * 2
      + round(coalesce(new.estimate, 0) / 1000)::integer,
      0)
  end;

  -- month_auto: auto-fill if not manually provided
  if new.month_auto is null or new.month_auto = '' then
    if new.home_call_date is not null then
      new.month_auto := to_char(new.home_call_date, 'FMMonth YYYY');
    elsif new.follow_up_date is not null then
      new.month_auto := to_char(new.follow_up_date, 'FMMonth YYYY');
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace trigger opp_compute_fields
  before insert or update on opportunities
  for each row execute function compute_opp_fields();


-- ════════════════════════════════════════════════════════════════════
-- TABLE: actives
-- ════════════════════════════════════════════════════════════════════
create table if not exists actives (
  id                    uuid          primary key default uuid_generate_v4(),
  opportunity_id        uuid          references opportunities(id) on delete set null,

  last_name             text          not null,
  first_name            text          not null,
  customer_number       text,
  gold_comp             text,
  sale_date             date,
  project_type          text,
  gold_comp_value       numeric(12,2) default 0,
  project_value         numeric(12,2) default 0,
  active_phase          text,
  days_before_delivery  integer,
  delivery_date         date,
  last_contact          date,
  followup_link_review  text,
  issue_flag            text,
  issue_type            text,
  issue_followup        text,
  issue_result          text,
  notes                 text,
  days_until_delivery   integer,      -- computed by trigger
  home_call             text,
  home_call_date        date,

  created_at            timestamptz   default now(),
  updated_at            timestamptz   default now()
);

create or replace function compute_actives_fields()
returns trigger language plpgsql as $$
begin
  new.days_until_delivery := case
    when new.delivery_date is null then null
    else (new.delivery_date - current_date)
  end;
  new.updated_at := now();
  return new;
end;
$$;

create or replace trigger actives_compute_fields
  before insert or update on actives
  for each row execute function compute_actives_fields();


-- ════════════════════════════════════════════════════════════════════
-- TABLE: post_30
-- ════════════════════════════════════════════════════════════════════
create table if not exists post_30 (
  id                  uuid          primary key default uuid_generate_v4(),
  active_id           uuid          references actives(id) on delete set null,

  last_name           text          not null,
  first_name          text          not null,
  customer_number     text,
  gold_comp           text,
  sale_date           date,
  project_type        text,
  gold_comp_value     numeric(12,2) default 0,
  project_value       numeric(12,2) default 0,
  delivery_date       date,
  followup_30_date    date          generated always as (delivery_date + interval '30 days') stored,
  contact_reason      text,
  new_opportunity     text,
  notes               text,

  created_at          timestamptz   default now(),
  updated_at          timestamptz   default now()
);

create or replace function update_post30_ts()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

create or replace trigger post_30_updated_at
  before update on post_30
  for each row execute function update_post30_ts();


-- ════════════════════════════════════════════════════════════════════
-- TABLE: post_60
-- ════════════════════════════════════════════════════════════════════
create table if not exists post_60 (
  id                  uuid          primary key default uuid_generate_v4(),
  post_30_id          uuid          references post_30(id) on delete set null,
  active_id           uuid          references actives(id) on delete set null,

  last_name           text          not null,
  first_name          text          not null,
  customer_number     text,
  gold_comp           text,
  sale_date           date,
  project_type        text,
  gold_comp_value     numeric(12,2) default 0,
  project_value       numeric(12,2) default 0,
  delivery_date       date,
  followup_60_date    date          generated always as (delivery_date + interval '60 days') stored,
  contact_reason      text,
  new_opportunity     text,
  notes               text,

  created_at          timestamptz   default now(),
  updated_at          timestamptz   default now()
);

create or replace function update_post60_ts()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

create or replace trigger post_60_updated_at
  before update on post_60
  for each row execute function update_post60_ts();


-- ════════════════════════════════════════════════════════════════════
-- TABLE: mileage
-- (pure math generated columns are fine — no current_date)
-- ════════════════════════════════════════════════════════════════════
create table if not exists mileage (
  id                  uuid          primary key default uuid_generate_v4(),
  opportunity_id      uuid          references opportunities(id) on delete set null,

  trip_date           date,
  client_name         text,
  client_address      text,
  miles_home_dc       numeric(8,2)  default 0,
  miles_dc_client     numeric(8,2)  default 0,
  miles_client_home   numeric(8,2)  default 0,
  miles_dc_home       numeric(8,2)  default 0,

  total_miles         numeric(8,2)  generated always as (
    coalesce(miles_home_dc,    0) +
    coalesce(miles_dc_client,  0) +
    coalesce(miles_client_home,0) +
    coalesce(miles_dc_home,    0)
  ) stored,

  daily_commute       numeric(8,2)  default 0,

  net_miles           numeric(8,2)  generated always as (
    greatest(
      coalesce(miles_home_dc,    0) +
      coalesce(miles_dc_client,  0) +
      coalesce(miles_client_home,0) +
      coalesce(miles_dc_home,    0) -
      coalesce(daily_commute,    0),
    0)
  ) stored,

  tolls_parking       numeric(8,2)  default 0,

  reimbursement       numeric(10,2) generated always as (
    greatest(
      coalesce(miles_home_dc,    0) +
      coalesce(miles_dc_client,  0) +
      coalesce(miles_client_home,0) +
      coalesce(miles_dc_home,    0) -
      coalesce(daily_commute,    0),
    0) * 0.725 + coalesce(tolls_parking, 0)
  ) stored,

  design_partner      text,
  purpose             text          default 'Home Call',
  log_month           text,
  log_year            integer,

  created_at          timestamptz   default now()
);


-- ════════════════════════════════════════════════════════════════════
-- TABLE: year_goals
-- ════════════════════════════════════════════════════════════════════
create table if not exists year_goals (
  id          uuid    primary key default uuid_generate_v4(),
  year        integer not null default 2026,
  month_num   integer not null check (month_num between 1 and 12),
  month_name  text    not null,
  goal_amount numeric(12,2) not null,
  unique (year, month_num)
);

insert into year_goals (year, month_num, month_name, goal_amount) values
  (2026,  1, 'January',   28000),
  (2026,  2, 'February',  28000),
  (2026,  3, 'March',     30000),
  (2026,  4, 'April',     32000),
  (2026,  5, 'May',       32000),
  (2026,  6, 'June',      35000),
  (2026,  7, 'July',      35000),
  (2026,  8, 'August',    35000),
  (2026,  9, 'September', 33000),
  (2026, 10, 'October',   33000),
  (2026, 11, 'November',  30000),
  (2026, 12, 'December',  28000)
on conflict (year, month_num) do update set goal_amount = excluded.goal_amount;


-- ════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════════════
alter table opportunities  enable row level security;
alter table actives        enable row level security;
alter table post_30        enable row level security;
alter table post_60        enable row level security;
alter table mileage        enable row level security;
alter table year_goals     enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='opportunities' and policyname='Allow all for anon') then
    create policy "Allow all for anon" on opportunities for all to anon using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='actives' and policyname='Allow all for anon') then
    create policy "Allow all for anon" on actives for all to anon using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='post_30' and policyname='Allow all for anon') then
    create policy "Allow all for anon" on post_30 for all to anon using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='post_60' and policyname='Allow all for anon') then
    create policy "Allow all for anon" on post_60 for all to anon using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='mileage' and policyname='Allow all for anon') then
    create policy "Allow all for anon" on mileage for all to anon using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='year_goals' and policyname='Allow all for anon') then
    create policy "Allow all for anon" on year_goals for all to anon using (true) with check (true);
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════
-- INDEXES
-- ════════════════════════════════════════════════════════════════════
create index if not exists idx_opp_stage          on opportunities(stage);
create index if not exists idx_opp_sale_made       on opportunities(sale_made);
create index if not exists idx_opp_follow_up       on opportunities(follow_up_date);
create index if not exists idx_opp_project_type    on opportunities(project_type);
create index if not exists idx_opp_urgency_score   on opportunities(urgency_score desc);
create index if not exists idx_opp_win_tier        on opportunities(win_tier);
create index if not exists idx_opp_home_call_date  on opportunities(home_call_date);
create index if not exists idx_opp_created_at      on opportunities(created_at desc);
create index if not exists idx_actives_delivery    on actives(delivery_date);
create index if not exists idx_post30_followup     on post_30(followup_30_date);
create index if not exists idx_post60_followup     on post_60(followup_60_date);
create index if not exists idx_mileage_month       on mileage(log_month, log_year);


-- ════════════════════════════════════════════════════════════════════
-- VIEWS
-- ════════════════════════════════════════════════════════════════════

-- v_priorities: open opps sorted by urgency_score (mirrors Priorities tab)
create or replace view v_priorities as
select
  last_name,
  first_name,
  project_type,
  stage,
  next_step,
  probability,
  estimate,
  follow_up_date,
  case
    when follow_up_date < current_date then current_date - follow_up_date
    else 0
  end             as days_overdue,
  home_call,
  urgency_score,
  win_tier,
  id
from opportunities
where sale_made <> 'Yes'
  and stage     <> 'Canceled'
  and last_name  is not null
order by urgency_score desc;


-- v_dashboard: KPI summary (mirrors Dashboard tab)
create or replace view v_dashboard as
select
  count(*)                                                         as total_opps,
  count(*) filter (where sale_made = 'Yes')                        as sales_made,
  coalesce(sum(estimate) filter (where sale_made = 'Yes'), 0)      as total_sales_usd,
  coalesce(sum(estimate * probability / 100.0)
    filter (where sale_made <> 'Yes' and stage <> 'Canceled'), 0)  as weighted_pipeline,
  round(
    count(*) filter (where sale_made = 'Yes')::numeric
    / nullif(count(*), 0) * 100, 1
  )                                                                as win_rate_pct,
  coalesce(avg(estimate) filter (where sale_made = 'Yes'), 0)      as avg_sale_value,
  count(*) filter (
    where follow_up_date < current_date
      and sale_made <> 'Yes'
      and stage <> 'Canceled'
  )                                                                as overdue_followups,
  count(*) filter (where win_tier = '🔥 HOT')                      as hot_leads,
  count(*) filter (where win_tier = '⚡ WARM')                      as warm_leads,
  coalesce(sum(estimate) filter (
    where sale_made = 'Yes'
      and extract(month from home_call_date) = extract(month from current_date)
      and extract(year  from home_call_date) = extract(year  from current_date)
  ), 0)                                                            as month_sales_usd
from opportunities;


-- v_year_tracker: monthly goal vs actual (mirrors Year_2026 tab)
create or replace view v_year_tracker as
select
  g.month_num,
  g.month_name,
  g.goal_amount,
  coalesce(sum(o.estimate), 0)                                      as actual_sales,
  coalesce(sum(o.estimate), 0) - g.goal_amount                      as vs_goal,
  case
    when coalesce(sum(o.estimate), 0) = 0                           then '—'
    when coalesce(sum(o.estimate), 0) >= g.goal_amount              then '✅ MET'
    when coalesce(sum(o.estimate), 0) >= g.goal_amount * 0.75       then '⚡ CLOSE'
    else '❌ BEHIND'
  end                                                               as status
from year_goals g
left join opportunities o
  on  o.sale_made = 'Yes'
  and extract(month from o.home_call_date) = g.month_num
  and extract(year  from o.home_call_date) = g.year
where g.year = 2026
group by g.month_num, g.month_name, g.goal_amount
order by g.month_num;


-- ════════════════════════════════════════════════════════════════════
-- SEED DATA  (6 test rows — trigger fires automatically on insert)
-- ════════════════════════════════════════════════════════════════════
insert into opportunities
  (last_name, first_name, address, phone, email, project_type, lead_source,
   stage, home_call, home_call_date, sale_made, next_step, probability,
   estimate, follow_up_date, notes)
values
  ('Medrado','Carol','2006 Florine Dr, Apex, NC 27502','919-555-0100','carol@ea.com',
   'Living Room','Referral','Home Call','Yes',current_date,'Yes',
   'Follow-Up Call',100,10000,current_date - 2,'Sale made - living room set'),

  ('Chen','James','412 Walnut Creek Dr, Cary, NC 27511','919-555-0142','jchen@email.com',
   'Home Office','Walk-in','New Lead','No',null,'No',
   'Schedule Home Visit',25,8000,current_date - 15,'Interested in standing desk area'),

  ('Thompson','Sarah','88 Pinecrest Rd, Raleigh, NC 27606','919-555-0287','sthompson@gmail.com',
   'Bedroom','Referral','Quote Sent','Yes',current_date - 21,'No',
   'Follow-Up Call',75,22000,current_date - 5,'Custom headboard confirmed'),

  ('Patel','Priya','201 Elmwood Ave, Durham, NC 27701','984-555-0331','priya@work.com',
   'Living Room','Instagram','Design in Progress','Yes',current_date - 10,'No',
   'Presentation / Quote',50,15000,current_date + 7,'Wants sectional + media console'),

  ('Williams','Linda','55 Oak Ridge Dr, Chapel Hill, NC 27514','919-555-0418','lwilliams@email.com',
   'Dining','Repeat Client','Sale Made','Yes',current_date - 35,'Yes',
   'Follow-Up Call',100,18500,current_date - 2,'GoldComp confirmed'),

  ('Brooks','Michelle','117 Cedar Lane, Apex, NC 27502','984-555-0662','mbrooks@gmail.com',
   'Home Office','Referral','Pending Decision','Yes',current_date - 3,'No',
   'Awaiting Decision',90,12000,current_date + 3,'Decision by end of week')
on conflict do nothing;

-- ── Quick sanity check (optional — run this separately to verify) ──
-- select last_name, urgency_score, win_tier, month_auto
-- from opportunities order by urgency_score desc;
