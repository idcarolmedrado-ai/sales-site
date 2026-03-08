-- ═══════════════════════════════════════════════════════════
--  EA Sales Intelligence — Supabase Schema
--  Run this in your Supabase SQL Editor (single paste)
-- ═══════════════════════════════════════════════════════════

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ── opportunities table ──────────────────────────────────
create table if not exists opportunities (
  id            uuid primary key default uuid_generate_v4(),
  first_name    text not null,
  last_name     text not null,
  email         text,
  phone         text,
  address       text,
  project_type  text,
  stage         text,
  home_call     text,
  home_call_date date,
  sale_made     text,
  gold_comp     text,
  probability   integer default 0,
  estimate      numeric(12,2) default 0,
  follow_up_date date,
  next_step     text,
  notes         text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ── auto-update updated_at ───────────────────────────────
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger opportunities_updated_at
  before update on opportunities
  for each row execute function update_updated_at();

-- ── Row Level Security ───────────────────────────────────
alter table opportunities enable row level security;

-- Allow all operations with anon key (single-user app)
-- For production, replace with auth-based policies
create policy "Allow all for anon"
  on opportunities for all
  to anon
  using (true)
  with check (true);

-- ── Indexes for performance ──────────────────────────────
create index if not exists idx_opp_stage        on opportunities(stage);
create index if not exists idx_opp_sale_made    on opportunities(sale_made);
create index if not exists idx_opp_follow_up    on opportunities(follow_up_date);
create index if not exists idx_opp_project_type on opportunities(project_type);
create index if not exists idx_opp_created_at   on opportunities(created_at desc);

-- ── Seed demo data ───────────────────────────────────────
insert into opportunities
  (first_name, last_name, email, phone, address, project_type, stage,
   home_call, home_call_date, sale_made, gold_comp, probability, estimate,
   follow_up_date, next_step, notes)
values
  ('Maria','Alvarez','malvarez@email.com','305-111-0001','100 Brickell Ave','Living Room','Sale Made','Yes','2026-01-05','Yes','No',100,18500,'2026-01-20','Delivery Scheduled','Jan sale - living room full set'),
  ('David','Chen','dchen@email.com','305-111-0002','200 Coral Way','Dining','Sale Made','Yes','2026-01-10','Yes','Yes',100,9800,'2026-01-25','In Production','Jan sale - dining set GoldComp'),
  ('Priya','Patel','ppatel@email.com','305-111-0003','300 SW 8th St','Bedroom','Quote Sent','Yes','2026-02-03','No','No',75,14200,current_date - 3,'Follow-Up Call','Hot lead - waiting on quote response'),
  ('Carlos','Torres','ctorres@email.com','305-111-0004','400 NW 2nd Ave','Home Office','Sale Made','No',null,'Yes','No',100,7600,'2026-02-18','SO Made','Feb sale - home office'),
  ('Sarah','Kim','skim@email.com','305-111-0005','500 NE 1st St','Outdoor','Design in Progress','Yes','2026-02-12','No','No',50,21000,current_date + 5,'Send Proposal','Big outdoor project - in design phase'),
  ('Thomas','Williams','twilliams@email.com','561-555-4004','321 Elm Blvd','Home Office','Follow-up','Yes','2026-03-01','No','No',50,5500,current_date - 8,'Follow-Up Call','Needs nudge - been quiet'),
  ('Linda','Brown','lbrown@email.com','305-555-5005','654 Cedar Ln','Outdoor','New Lead','No',null,'No','No',25,7200,current_date + 3,'Schedule Home Visit','New contact from store walk-in'),
  ('Lily','Nguyen','lnguyen@email.com','786-111-0008','600 SW 36th Ave','Bedroom','Sale Made','Yes','2026-03-08','Yes','No',100,11300,'2026-03-20','Delivery Scheduled','Mar sale - master bedroom'),
  ('Isabel','Reyes','ireyes@email.com','305-111-0009','700 Collins Ave','Living Room','Pending Decision','Yes','2026-04-02','No','No',90,28000,current_date - 1,'Awaiting Decision','Very close - needs final push'),
  ('James','Park','jpark@email.com','305-111-0010','800 Ocean Dr','Mix','Sale Made','Yes','2026-04-05','Yes','Yes',100,35000,'2026-04-15','In Production','Biggest April sale - full home mix'),
  ('Ana','Rodriguez','arodriguez@email.com','305-111-0011','900 Alhambra Cir','Dining','Quote Sent','No',null,'No','No',75,8900,current_date + 2,'Send Proposal','Waiting for formal proposal approval'),
  ('Michael','Lee','mlee@email.com','786-111-0012','1000 Miracle Mile','Lighting','Design in Progress','Yes','2026-05-10','No','No',50,4500,current_date + 7,'Presentation / Quote','Lighting redesign whole floor'),
  ('Sofia','Hernandez','shernandez@email.com','305-111-0013','1100 Ponce de Leon','Mix','Sale Made','Yes','2026-06-01','Yes','Yes',100,52000,'2026-06-10','Delivery Scheduled','Biggest sale June - whole home'),
  ('Robert','White','rwhite@email.com','305-111-0014','1200 Biscayne Blvd','Rugs & Flooring','New Lead','No',null,'No','No',10,3200,current_date + 10,'Schedule Home Visit','Early stage - cold contact'),
  ('Elena','Martinez','emartinez@email.com','305-111-0015','1300 SW 107th Ave','Bedroom','Follow-up','Yes','2026-07-07','No','No',75,16500,current_date - 5,'Follow-Up Call','Almost there - one more push'),
  ('Kevin','Davis','kdavis@email.com','786-111-0016','1400 Bird Rd','Living Room','Sale Made','Yes','2026-07-10','Yes','No',100,22000,'2026-07-20','Delivery Scheduled','July sale - LR refresh'),
  ('Patricia','Wilson','pwilson@email.com','305-111-0017','1500 Kendall Dr','Home Office','Quote Sent','No',null,'No','No',90,9800,current_date,'Awaiting Decision','Corporate HO redesign'),
  ('Marcus','Taylor','mtaylor@email.com','305-111-0018','1600 Flagler St','Decor','Sale Made','Yes','2026-09-03','Yes','No',100,6700,'2026-09-12','In Production','Sep sale - decor package'),
  ('Claire','Anderson','canderson@email.com','305-111-0019','1700 SW 8th','Dining','Pending Decision','Yes','2026-10-01','No','No',75,11400,current_date + 1,'Awaiting Decision','Close to yes - holiday timing'),
  ('Brian','Jackson','bjackson@email.com','786-111-0020','1800 NW 7th','Living Room','New Lead','No',null,'No','No',25,19000,current_date + 14,'Schedule Home Visit','Holiday rush - pre-Thanksgiving')
on conflict do nothing;
