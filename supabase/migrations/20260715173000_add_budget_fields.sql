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
