-- ═══════════════════════════════════════════════════════════
-- FILVEO CRM — SUPABASE SCHEMA
-- New dedicated Filveo Supabase project (NOT shared)
-- Run this in your Supabase SQL editor after creating project
-- ═══════════════════════════════════════════════════════════

-- ── Enable UUID extension
create extension if not exists "uuid-ossp";

-- ── Users table (extends Supabase auth.users)
create table public.filveo_users (
  id          uuid references auth.users(id) primary key,
  email       text not null,
  full_name   text,
  studio_name text,
  plan        text default 'trial' check (plan in ('trial','solo','studio','enterprise')),
  plan_expires_at timestamptz,
  trial_started_at timestamptz default now(),
  settings    jsonb default '{}',
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── Opportunities (Pipeline)
create table public.fvl_opportunities (
  id            uuid default uuid_generate_v4() primary key,
  user_id       uuid references public.filveo_users(id) on delete cascade,
  client_name   text not null,
  client_email  text,
  client_phone  text,
  client_address text,
  project_type  text,
  estimated_value numeric(10,2),
  tier          text default 'WARM' check (tier in ('HOT','WARM','NURTURE','COLD')),
  urgency_score integer default 50,
  stage         text default 'prospect',
  notes         text,
  source        text,
  home_call_date date,
  next_action_date date,
  vendor_credits numeric(10,2) default 0,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ── Active Sales (post-sale lifecycle)
create table public.fvl_actives (
  id              uuid default uuid_generate_v4() primary key,
  user_id         uuid references public.filveo_users(id) on delete cascade,
  opportunity_id  uuid references public.fvl_opportunities(id),
  client_name     text not null,
  client_number   text,
  sale_amount     numeric(10,2),
  vendor_credits  numeric(10,2) default 0,
  delivery_date   date,
  phase           text default 'design_review' check (phase in (
    'design_review','balance_due','scheduled','delivered',
    'post30','post60','complete','issue'
  )),
  post30_date     date,
  post60_date     date,
  post30_done     boolean default false,
  post60_done     boolean default false,
  review_requested boolean default false,
  notes           text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- ── Clients (full history)
create table public.fvl_clients (
  id            uuid default uuid_generate_v4() primary key,
  user_id       uuid references public.filveo_users(id) on delete cascade,
  full_name     text not null,
  email         text,
  phone         text,
  address       text,
  client_number text,
  preferred_contact text,
  notes         text,
  tags          text[],
  total_purchases numeric(10,2) default 0,
  last_purchase_date date,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ── Mileage Log
create table public.fvl_mileage (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.filveo_users(id) on delete cascade,
  client_name text not null,
  destination text,
  visit_date  date not null,
  distance_miles numeric(8,1),
  irs_rate    numeric(4,3) default 0.670,
  deduction   numeric(8,2),
  linked_to   uuid,  -- opportunity_id or active_id
  notes       text,
  created_at  timestamptz default now()
);

-- ── Commission
create table public.fvl_commission (
  id            uuid default uuid_generate_v4() primary key,
  user_id       uuid references public.filveo_users(id) on delete cascade,
  active_id     uuid references public.fvl_actives(id),
  client_name   text,
  sale_amount   numeric(10,2),
  vendor_credits numeric(10,2) default 0,
  commission_rate numeric(5,2),
  commission_earned numeric(10,2),
  period_month  text,  -- e.g. '2026-04'
  fiscal_quarter text, -- e.g. 'FQ1-2026'
  created_at    timestamptz default now()
);

-- ── Expenses
create table public.fvl_expenses (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.filveo_users(id) on delete cascade,
  active_id   uuid references public.fvl_actives(id),
  client_name text,
  category    text check (category in ('samples','travel','materials','other')),
  description text,
  amount      numeric(10,2),
  expense_date date,
  receipt_url text,
  created_at  timestamptz default now()
);

-- ── Follow-ups queue
create table public.fvl_followups (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.filveo_users(id) on delete cascade,
  active_id   uuid references public.fvl_actives(id),
  client_name text,
  type        text check (type in ('post30','post60','review','custom')),
  due_date    date,
  completed   boolean default false,
  completed_at timestamptz,
  notes       text,
  created_at  timestamptz default now()
);

-- ── Email sequences log
create table public.fvl_email_log (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.filveo_users(id) on delete cascade,
  opportunity_id uuid,
  client_name text,
  template_id text,
  subject     text,
  sent_at     timestamptz default now(),
  status      text default 'sent'
);

-- ══════════════════════════════════════════
-- ROW LEVEL SECURITY (Critical — each user
-- can only see their own data)
-- ══════════════════════════════════════════

alter table public.filveo_users    enable row level security;
alter table public.fvl_opportunities enable row level security;
alter table public.fvl_actives     enable row level security;
alter table public.fvl_clients     enable row level security;
alter table public.fvl_mileage     enable row level security;
alter table public.fvl_commission  enable row level security;
alter table public.fvl_expenses    enable row level security;
alter table public.fvl_followups   enable row level security;
alter table public.fvl_email_log   enable row level security;

-- Policies: each user only sees their own rows
create policy "Users own their profile" on public.filveo_users
  for all using (auth.uid() = id);

create policy "Users own opportunities" on public.fvl_opportunities
  for all using (auth.uid() = user_id);

create policy "Users own actives" on public.fvl_actives
  for all using (auth.uid() = user_id);

create policy "Users own clients" on public.fvl_clients
  for all using (auth.uid() = user_id);

create policy "Users own mileage" on public.fvl_mileage
  for all using (auth.uid() = user_id);

create policy "Users own commission" on public.fvl_commission
  for all using (auth.uid() = user_id);

create policy "Users own expenses" on public.fvl_expenses
  for all using (auth.uid() = user_id);

create policy "Users own followups" on public.fvl_followups
  for all using (auth.uid() = user_id);

create policy "Users own email log" on public.fvl_email_log
  for all using (auth.uid() = user_id);

-- ══════════════════════════════════════════
-- INDEXES (performance)
-- ══════════════════════════════════════════

create index on public.fvl_opportunities(user_id, tier);
create index on public.fvl_opportunities(user_id, urgency_score desc);
create index on public.fvl_actives(user_id, phase);
create index on public.fvl_actives(user_id, post30_date) where not post30_done;
create index on public.fvl_actives(user_id, post60_date) where not post60_done;
create index on public.fvl_followups(user_id, due_date) where not completed;
create index on public.fvl_mileage(user_id, visit_date);
create index on public.fvl_commission(user_id, period_month);

-- ══════════════════════════════════════════
-- FUNCTIONS
-- ══════════════════════════════════════════

-- Auto-create follow-up records when active sale is created
create or replace function public.create_followups_on_sale()
returns trigger as $$
begin
  if new.delivery_date is not null then
    -- Post-30 follow-up
    insert into public.fvl_followups (user_id, active_id, client_name, type, due_date)
    values (new.user_id, new.id, new.client_name, 'post30', new.delivery_date + interval '30 days');
    -- Post-60 follow-up
    insert into public.fvl_followups (user_id, active_id, client_name, type, due_date)
    values (new.user_id, new.id, new.client_name, 'post60', new.delivery_date + interval '60 days');
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trigger_create_followups
  after insert on public.fvl_actives
  for each row execute function public.create_followups_on_sale();

-- Updated_at trigger
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_updated_at_opportunities
  before update on public.fvl_opportunities
  for each row execute function public.handle_updated_at();

create trigger set_updated_at_actives
  before update on public.fvl_actives
  for each row execute function public.handle_updated_at();

-- ══════════════════════════════════════════
-- NOTES FOR SETUP
-- ══════════════════════════════════════════
-- 1. Create new project at https://supabase.com/dashboard/projects
-- 2. Copy SQL above into SQL editor and run
-- 3. Copy your Project URL + anon key into .env
-- 4. In app.html Settings tab, enter URL + anon key
-- 5. App will migrate localStorage data to Supabase on first connect
-- This schema is FILVEO ONLY — never shared with other projects
