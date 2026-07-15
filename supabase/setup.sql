-- Mecardee Car Wash launch tracker database
-- Run this once in Supabase SQL Editor, or use: supabase db push

create extension if not exists pgcrypto;

create table if not exists public.mecardee_project (
  id smallint primary key default 1 check (id = 1),
  name text not null default 'Mecardee Car Wash',
  location text not null default 'Kerala, India',
  opening_date date not null default (current_date + 100),
  updated_at timestamptz not null default now()
);

create table if not exists public.mecardee_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 180),
  phase text not null check (phase in ('site', 'water', 'electrical', 'equipment', 'brand', 'launch')),
  owner text not null default '',
  deadline date not null,
  progress integer not null default 0 check (progress between 0 and 100),
  notes text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_mecardee_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists mecardee_project_updated_at on public.mecardee_project;
create trigger mecardee_project_updated_at
before update on public.mecardee_project
for each row execute function public.set_mecardee_updated_at();

drop trigger if exists mecardee_tasks_updated_at on public.mecardee_tasks;
create trigger mecardee_tasks_updated_at
before update on public.mecardee_tasks
for each row execute function public.set_mecardee_updated_at();

alter table public.mecardee_project enable row level security;
alter table public.mecardee_tasks enable row level security;

grant select, insert, update, delete on public.mecardee_project to anon, authenticated;
grant select, insert, update, delete on public.mecardee_tasks to anon, authenticated;

drop policy if exists "Public can read Mecardee project" on public.mecardee_project;
create policy "Public can read Mecardee project"
on public.mecardee_project for select
to anon, authenticated
using (true);

drop policy if exists "Public can insert Mecardee project" on public.mecardee_project;
create policy "Public can insert Mecardee project"
on public.mecardee_project for insert
to anon, authenticated
with check (id = 1);

drop policy if exists "Public can update Mecardee project" on public.mecardee_project;
create policy "Public can update Mecardee project"
on public.mecardee_project for update
to anon, authenticated
using (id = 1)
with check (id = 1);

drop policy if exists "Public can delete Mecardee project" on public.mecardee_project;
create policy "Public can delete Mecardee project"
on public.mecardee_project for delete
to anon, authenticated
using (false);

drop policy if exists "Public can read Mecardee tasks" on public.mecardee_tasks;
create policy "Public can read Mecardee tasks"
on public.mecardee_tasks for select
to anon, authenticated
using (true);

drop policy if exists "Public can insert Mecardee tasks" on public.mecardee_tasks;
create policy "Public can insert Mecardee tasks"
on public.mecardee_tasks for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can update Mecardee tasks" on public.mecardee_tasks;
create policy "Public can update Mecardee tasks"
on public.mecardee_tasks for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "Public can delete Mecardee tasks" on public.mecardee_tasks;
create policy "Public can delete Mecardee tasks"
on public.mecardee_tasks for delete
to anon, authenticated
using (true);

insert into public.mecardee_project (id, name, location, opening_date)
values (1, 'Mecardee Car Wash', 'Kerala, India', current_date + 100)
on conflict (id) do nothing;

insert into public.mecardee_tasks (title, phase, owner, deadline, progress, notes, sort_order)
select seed.title, seed.phase, seed.owner, seed.deadline, seed.progress, seed.notes, seed.sort_order
from (
  values
    ('Complete site clearing and measurements', 'site', 'Civil contractor', current_date + 5, 70, 'Confirm entry and exit vehicle turning space.', 10),
    ('Finish wash-bay flooring and slope', 'site', 'Civil contractor', current_date + 18, 25, 'Use anti-skid flooring and verify drainage slope.', 20),
    ('Install drainage channels', 'water', 'Plumber', current_date + 24, 10, 'Include sludge trap and easy cleaning access.', 30),
    ('Install water tank, pump and pipelines', 'water', 'Plumber', current_date + 32, 0, 'Keep provision for recycling system.', 40),
    ('Complete three-phase wiring and lights', 'electrical', 'Electrician', current_date + 40, 0, 'Separate protected points for pressure washers.', 50),
    ('Install CCTV and fire extinguishers', 'electrical', 'Electrician', current_date + 48, 0, 'Cover wash bay, office, entrance and exit.', 60),
    ('Install pressure washer and compressor', 'equipment', 'Equipment supplier', current_date + 58, 0, 'Test pressure, leakage and warranty documents.', 70),
    ('Set up vacuum and detailing tools', 'equipment', 'Equipment supplier', current_date + 64, 0, 'Prepare locked storage for chemicals and tools.', 80),
    ('Complete signboard and price menu', 'brand', 'Designer', current_date + 72, 0, 'Use Malayalam and English where useful.', 90),
    ('Finish customer waiting and billing area', 'brand', 'Interior team', current_date + 78, 0, 'Add seating, drinking water and UPI QR display.', 100),
    ('Recruit and train wash staff', 'launch', 'Owner', current_date + 86, 0, 'Train on wash sequence, safety and customer handling.', 110),
    ('Trial wash and soft opening', 'launch', 'Owner', current_date + 95, 0, 'Test billing, workflow, water use and turnaround time.', 120)
) as seed(title, phase, owner, deadline, progress, notes, sort_order)
where not exists (select 1 from public.mecardee_tasks limit 1);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mecardee_project'
  ) then
    alter publication supabase_realtime add table public.mecardee_project;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mecardee_tasks'
  ) then
    alter publication supabase_realtime add table public.mecardee_tasks;
  end if;
end $$;

-- MECARDEE_BUDGET_SCHEMA
-- Mecardee budget upgrade
alter table public.mecardee_project
  add column if not exists total_budget numeric(14,2) not null default 0 check (total_budget >= 0);

alter table public.mecardee_project
  add column if not exists phase_budgets jsonb not null default '{"site":0,"water":0,"electrical":0,"equipment":0,"brand":0,"launch":0}'::jsonb;

alter table public.mecardee_tasks
  add column if not exists expected_cost numeric(14,2) not null default 0 check (expected_cost >= 0);

alter table public.mecardee_tasks
  add column if not exists actual_cost numeric(14,2) not null default 0 check (actual_cost >= 0);

update public.mecardee_project
set phase_budgets = '{"site":0,"water":0,"electrical":0,"equipment":0,"brand":0,"launch":0}'::jsonb
where phase_budgets is null;
