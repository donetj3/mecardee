-- MECARDEE_CATEGORIES_REPORTS_PERMISSIONS_V1
-- Dynamic categories, financial report register, shareholder shares and admin-only writes.

create extension if not exists pgcrypto with schema extensions;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_tasks_phase_check;

create table if not exists public.mecardee_categories (
  id text primary key,
  name text not null unique,
  icon text not null default '•',
  sort_order integer not null default 0,
  budget numeric(14,2) not null default 0 check (budget >= 0),
  completion integer not null default 0 check (completion between 0 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.mecardee_categories (
  id, name, icon, sort_order, budget, completion, is_active
)
values
    ('metal-roofing', 'Metal & Roofing', '▰', 10, 0, 0, true),
    ('cement-sand-aggregate', 'Cement, Sand & Aggregate', '▦', 20, coalesce((select nullif(phase_budgets ->> 'site', '')::numeric from public.mecardee_project where id = 1), 0), 0, true),
    ('labour-contractor', 'Labour & Contractor', '◷', 30, 0, 0, true),
    ('equipment-machinery', 'Equipment & Machinery', '⚙', 40, coalesce((select nullif(phase_budgets ->> 'equipment', '')::numeric from public.mecardee_project where id = 1), 0), 0, true),
    ('miscellaneous', 'Miscellaneous', '•', 50, 0, 0, true),
    ('plumbing-water', 'Plumbing & Water', '≈', 60, coalesce((select nullif(phase_budgets ->> 'water', '')::numeric from public.mecardee_project where id = 1), 0), 0, true),
    ('tiles-ceramics', 'Tiles & Ceramics', '◇', 70, 0, 0, true),
    ('fuel-transport', 'Fuel & Transport', '➜', 80, 0, 0, true),
    ('tools-consumables', 'Tools & Consumables', '⌁', 90, 0, 0, true),
    ('food-refreshments', 'Food & Refreshments', '☕', 100, 0, 0, true),
    ('paint-finishing', 'Paint & Finishing', '✦', 110, coalesce((select nullif(phase_budgets ->> 'brand', '')::numeric from public.mecardee_project where id = 1), 0), 0, true),
    ('communication-security', 'Communication & Security', '◉', 120, 0, 0, true),
    ('planning-administration', 'Planning & Administration', '▤', 130, coalesce((select nullif(phase_budgets ->> 'launch', '')::numeric from public.mecardee_project where id = 1), 0), 0, true),
    ('electrical-electronics', 'Electrical & Electronics', 'ϟ', 140, coalesce((select nullif(phase_budgets ->> 'electrical', '')::numeric from public.mecardee_project where id = 1), 0), 0, true)
on conflict (id) do update set
  name = excluded.name,
  icon = excluded.icon,
  sort_order = excluded.sort_order;

alter table public.mecardee_tasks
  add column if not exists work_date date,
  add column if not exists is_completed boolean not null default false,
  add column if not exists entry_type text not null default 'Work',
  add column if not exists amount numeric(14,2) not null default 0;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_tasks_entry_type_check;

alter table public.mecardee_tasks
  add constraint mecardee_tasks_entry_type_check
  check (entry_type in ('Work', 'Expense', 'Credit'));

update public.mecardee_tasks
set phase = case phase
  when 'site' then 'cement-sand-aggregate'
  when 'water' then 'plumbing-water'
  when 'electrical' then 'electrical-electronics'
  when 'equipment' then 'equipment-machinery'
  when 'brand' then 'paint-finishing'
  when 'launch' then 'planning-administration'
  else phase
end
where phase in ('site', 'water', 'electrical', 'equipment', 'brand', 'launch');

update public.mecardee_tasks
set
  work_date = coalesce(work_date, created_at::date, current_date),
  is_completed = coalesce(is_completed, progress >= 100),
  amount = case
    when coalesce(amount, 0) > 0 then amount
    when coalesce(actual_cost, 0) > 0 then actual_cost
    else 0
  end;

alter table public.mecardee_tasks
  alter column work_date set default current_date;

update public.mecardee_tasks
set work_date = current_date
where work_date is null;

alter table public.mecardee_tasks
  alter column work_date set not null;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_tasks_category_fk;

alter table public.mecardee_tasks
  add constraint mecardee_tasks_category_fk
  foreign key (phase) references public.mecardee_categories(id)
  on update cascade;

create table if not exists public.mecardee_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  sort_order integer not null default 0,
  txn_date date not null,
  txn_type text not null check (txn_type in ('Expense', 'Credit')),
  description text not null check (char_length(description) between 1 and 240),
  category_id text references public.mecardee_categories(id) on update cascade,
  amount numeric(14,2) not null check (amount >= 0),
  notes text not null default '',
  source_key text unique,
  work_id uuid unique references public.mecardee_tasks(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mecardee_expense_category_required
    check (txn_type = 'Credit' or category_id is not null)
);

create table if not exists public.mecardee_shareholders (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null unique,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.mecardee_shareholders (name, amount, sort_order)
values
  ('Delvin', 0, 10),
  ('Dennies', 592000, 20),
  ('Dantees', 308000, 30)
on conflict (name) do nothing;

insert into public.mecardee_transactions (
  sort_order, txn_date, txn_type, description, category_id, amount, source_key
)
values
    (1, '2025-01-24'::date, 'Expense', 'SIM charge', 'communication-security', 300, 'excel-1'),
    (2, '2025-04-01'::date, 'Expense', 'Tea expense', 'food-refreshments', 85, 'excel-2'),
    (3, '2025-04-01'::date, 'Expense', 'Lunch expense', 'food-refreshments', 160, 'excel-3'),
    (4, '2025-04-02'::date, 'Expense', 'Tea expense', 'food-refreshments', 177, 'excel-4'),
    (5, '2025-04-02'::date, 'Expense', 'Lunch expense', 'food-refreshments', 160, 'excel-5'),
    (6, '2025-04-04'::date, 'Credit', 'Credit received from Dennies for lift cost', null, 300000, 'excel-6'),
    (7, '2025-04-07'::date, 'Expense', 'Unloading labour (Royal)', 'labour-contractor', 500, 'excel-7'),
    (8, '2025-04-07'::date, 'Credit', 'Credit received from Danees', null, 50000, 'excel-8'),
    (9, '2025-04-07'::date, 'Expense', 'Royal Metals, Paika', 'metal-roofing', 51000, 'excel-9'),
    (10, '2025-04-08'::date, 'Expense', 'Painting roller', 'paint-finishing', 80, 'excel-10'),
    (11, '2025-04-08'::date, 'Expense', 'Lunch expense', 'food-refreshments', 120, 'excel-11'),
    (12, '2025-04-08'::date, 'Expense', 'Petrol', 'fuel-transport', 500, 'excel-12'),
    (13, '2025-04-10'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-13'),
    (14, '2025-04-10'::date, 'Expense', 'Mason/labour', 'labour-contractor', 5300, 'excel-14'),
    (15, '2025-04-10'::date, 'Expense', 'Roofing sheet', 'metal-roofing', 10000, 'excel-15'),
    (16, '2025-04-10'::date, 'Expense', 'Lunch expense', 'food-refreshments', 160, 'excel-16'),
    (17, '2025-04-10'::date, 'Expense', 'Two-person work/labour', 'labour-contractor', 2400, 'excel-17'),
    (18, '2025-04-11'::date, 'Credit', 'Danees Chettan - amount given', null, 25000, 'excel-18'),
    (19, '2025-04-13'::date, 'Expense', 'Tea expense', 'food-refreshments', 178, 'excel-19'),
    (20, '2025-04-14'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-20'),
    (21, '2025-04-14'::date, 'Expense', 'Chain lift expense', 'equipment-machinery', 3800, 'excel-21'),
    (22, '2025-04-15'::date, 'Expense', 'Lift chain', 'equipment-machinery', 3000, 'excel-22'),
    (23, '2025-04-15'::date, 'Expense', 'Tea expense', 'food-refreshments', 125, 'excel-23'),
    (24, '2025-04-15'::date, 'Expense', 'Petrol', 'fuel-transport', 1000, 'excel-24'),
    (25, '2025-04-16'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-25'),
    (26, '2025-04-17'::date, 'Expense', 'Ring-related purchase', 'equipment-machinery', 5000, 'excel-26'),
    (27, '2025-04-17'::date, 'Expense', 'Tea expense', 'food-refreshments', 177, 'excel-27'),
    (28, '2025-04-17'::date, 'Expense', 'Lunch expense', 'food-refreshments', 80, 'excel-28'),
    (29, '2025-04-17'::date, 'Expense', 'Labour - 2 people', 'labour-contractor', 2700, 'excel-29'),
    (30, '2025-04-18'::date, 'Expense', 'Petrol', 'fuel-transport', 200, 'excel-30'),
    (31, '2025-04-18'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-31'),
    (32, '2025-04-18'::date, 'Expense', 'Soda / small refreshment (2)', 'food-refreshments', 45, 'excel-32'),
    (33, '2025-04-18'::date, 'Expense', 'LABOUR PAY.FOR MASON', 'miscellaneous', 50800, 'excel-33'),
    (34, '2025-04-19'::date, 'Expense', 'Freeze Pala compressor', 'equipment-machinery', 450, 'excel-34'),
    (35, '2025-04-19'::date, 'Expense', 'Tea expense', 'food-refreshments', 126, 'excel-35'),
    (36, '2025-04-22'::date, 'Expense', 'Tea expense', 'food-refreshments', 186, 'excel-36'),
    (37, '2025-04-22'::date, 'Expense', 'Petrol', 'fuel-transport', 600, 'excel-37'),
    (38, '2025-04-24'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-38'),
    (39, '2025-04-24'::date, 'Expense', 'Petrol', 'fuel-transport', 200, 'excel-39'),
    (40, '2025-04-24'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-40'),
    (41, '2025-04-27'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-41'),
    (42, '2025-04-29'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 4600, 'excel-42'),
    (43, '2025-04-29'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-43'),
    (44, '2025-04-29'::date, 'Expense', 'Freeze Pala', 'equipment-machinery', 350, 'excel-44'),
    (45, '2025-04-29'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-45'),
    (46, '2025-04-30'::date, 'Expense', 'Union Pala', 'tools-consumables', 100, 'excel-46'),
    (47, '2025-04-30'::date, 'Expense', 'Akshaya Centre / subsidy expense', 'planning-administration', 60, 'excel-47'),
    (48, '2025-04-30'::date, 'Expense', 'Petrol', 'fuel-transport', 200, 'excel-48'),
    (49, '2025-05-01'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-49'),
    (50, '2025-05-02'::date, 'Expense', 'Friends / amount paid', 'miscellaneous', 15000, 'excel-50'),
    (51, '2025-05-03'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-51'),
    (52, '2025-05-05'::date, 'Expense', 'Repair/maintenance work', 'equipment-machinery', 2850, 'excel-52'),
    (53, '2025-05-05'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-53'),
    (54, '2025-05-05'::date, 'Expense', 'Vehicle charge', 'fuel-transport', 400, 'excel-54'),
    (55, '2025-05-06'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-55'),
    (56, '2025-05-07'::date, 'Expense', 'Vehicle/transport charge', 'fuel-transport', 800, 'excel-56'),
    (57, '2025-05-07'::date, 'Expense', '1 kg material/item', 'tools-consumables', 90, 'excel-57'),
    (58, '2025-05-07'::date, 'Expense', 'Lunch expense', 'food-refreshments', 170, 'excel-58'),
    (59, '2025-05-07'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-59'),
    (60, '2025-05-08'::date, 'Credit', 'Credit from Danees Chettan', null, 50000, 'excel-60'),
    (61, '2025-05-09'::date, 'Expense', 'Freeze cutting machine', 'equipment-machinery', 215, 'excel-61'),
    (62, '2025-05-09'::date, 'Expense', 'Lunch expense', 'food-refreshments', 190, 'excel-62'),
    (63, '2025-05-09'::date, 'Expense', 'Extra water pipe', 'plumbing-water', 1508, 'excel-63'),
    (64, '2025-05-09'::date, 'Expense', 'Mason labour - 2 days, 3 people', 'labour-contractor', 5600, 'excel-64'),
    (65, '2025-05-09'::date, 'Expense', 'Cutting machine', 'equipment-machinery', 400, 'excel-65'),
    (66, '2025-05-11'::date, 'Expense', 'Petrol', 'fuel-transport', 300, 'excel-66'),
    (67, '2025-05-11'::date, 'Expense', 'Small site expense', 'tools-consumables', 60, 'excel-67'),
    (68, '2025-05-11'::date, 'Expense', 'Tester', 'electrical-electronics', 40, 'excel-68'),
    (69, '2025-05-11'::date, 'Expense', 'Paper plate', 'food-refreshments', 75, 'excel-69'),
    (70, '2025-05-11'::date, 'Expense', 'Tea/food expense', 'food-refreshments', 725, 'excel-70'),
    (71, '2025-05-11'::date, 'Expense', 'Water expense', 'plumbing-water', 30, 'excel-71'),
    (72, '2025-05-11'::date, 'Expense', 'Pump/site material expense', 'plumbing-water', 2850, 'excel-72'),
    (73, '2025-05-11'::date, 'Expense', 'Plywood sheet', 'tools-consumables', 330, 'excel-73'),
    (74, '2025-05-11'::date, 'Expense', 'Machine labour', 'labour-contractor', 685, 'excel-74'),
    (75, '2025-05-11'::date, 'Expense', 'Cement-related item', 'cement-sand-aggregate', 600, 'excel-75'),
    (76, '2025-05-11'::date, 'Expense', 'Tea expense', 'food-refreshments', 160, 'excel-76'),
    (77, '2025-05-11'::date, 'Expense', 'Overtime', 'labour-contractor', 500, 'excel-77'),
    (78, '2025-05-11'::date, 'Expense', 'Mason overtime', 'labour-contractor', 1000, 'excel-78'),
    (79, '2025-05-11'::date, 'Expense', 'Three tile workers / labour', 'labour-contractor', 2200, 'excel-79'),
    (80, '2025-05-11'::date, 'Expense', 'Mason-related expense', 'labour-contractor', 1000, 'excel-80'),
    (81, '2025-05-11'::date, 'Expense', 'Concrete work/material', 'cement-sand-aggregate', 2400, 'excel-81'),
    (82, '2025-05-11'::date, 'Expense', 'Tube expense', 'plumbing-water', 120, 'excel-82'),
    (83, '2025-05-11'::date, 'Expense', 'Food expense', 'food-refreshments', 660, 'excel-83'),
    (84, '2025-12-31'::date, 'Expense', 'SET OUT BEFORE CLEANING SITE', 'labour-contractor', 1350, 'excel-84'),
    (85, '2025-12-31'::date, 'Expense', 'Tea expense', 'food-refreshments', 150, 'excel-85'),
    (86, '2025-12-31'::date, 'Expense', 'Set-out plan / A2 papers', 'planning-administration', 600, 'excel-86'),
    (87, '2025-12-31'::date, 'Expense', 'Mason/contractor advance', 'labour-contractor', 1000, 'excel-87'),
    (88, '2026-01-07'::date, 'Expense', 'Hitachi work', 'equipment-machinery', 5800, 'excel-88'),
    (89, '2026-01-10'::date, 'Expense', 'Shaji sand', 'cement-sand-aggregate', 18700, 'excel-89'),
    (90, '2026-01-10'::date, 'Expense', 'INITIAL STONE - GRANITE', 'labour-contractor', 500, 'excel-90'),
    (91, '2026-01-10'::date, 'Expense', 'Petrol', 'fuel-transport', 300, 'excel-91'),
    (92, '2026-01-11'::date, 'Expense', 'Water-related work/expense', 'plumbing-water', 500, 'excel-92'),
    (93, '2026-01-11'::date, 'Expense', 'Tea expense', 'food-refreshments', 495, 'excel-93'),
    (94, '2026-01-11'::date, 'Expense', 'Water expense', 'plumbing-water', 80, 'excel-94'),
    (95, '2026-01-11'::date, 'Expense', 'Lunch expense', 'food-refreshments', 225, 'excel-95'),
    (96, '2026-01-11'::date, 'Expense', 'Freeze/tool rent and sheet', 'equipment-machinery', 500, 'excel-96'),
    (97, '2026-01-21'::date, 'Expense', 'Royal Metals, Paika', 'metal-roofing', 227000, 'excel-97'),
    (98, '2026-01-23'::date, 'Expense', 'Key set', 'tools-consumables', 130, 'excel-98'),
    (99, '2026-01-26'::date, 'Expense', 'Camera fitting items', 'communication-security', 250, 'excel-99'),
    (100, '2026-01-27'::date, 'Expense', 'Memory card', 'communication-security', 1600, 'excel-100'),
    (101, '2026-01-27'::date, 'Expense', 'WATER TANK SMALL', 'plumbing-water', 1000, 'excel-101'),
    (102, '2026-01-27'::date, 'Expense', 'JCB/site expense', 'equipment-machinery', 500, 'excel-102'),
    (103, '2026-01-28'::date, 'Expense', 'Cement - Cheruvallil', 'cement-sand-aggregate', 5025, 'excel-103'),
    (104, '2026-01-28'::date, 'Expense', 'Auto charge', 'fuel-transport', 400, 'excel-104'),
    (105, '2026-01-28'::date, 'Expense', 'Food', 'food-refreshments', 125, 'excel-105'),
    (106, '2026-01-28'::date, 'Expense', 'PURCHASE OF MASON EQUIPMENTS LIKE CHATTI.KOTTA,THOOMBA.', 'tools-consumables', 990, 'excel-106'),
    (107, '2026-01-28'::date, 'Expense', 'Water', 'plumbing-water', 60, 'excel-107'),
    (108, '2026-01-28'::date, 'Expense', 'Site tea/small expense', 'food-refreshments', 100, 'excel-108'),
    (109, '2026-01-28'::date, 'Expense', 'Mason labour', 'labour-contractor', 3300, 'excel-109'),
    (110, '2026-01-29'::date, 'Expense', 'Tea expense', 'food-refreshments', 164, 'excel-110'),
    (111, '2026-01-29'::date, 'Expense', 'Lunch expense', 'food-refreshments', 360, 'excel-111'),
    (112, '2026-01-29'::date, 'Expense', 'Mason labour', 'labour-contractor', 3300, 'excel-112'),
    (113, '2026-01-29'::date, 'Expense', 'Ashoka pipe', 'plumbing-water', 1340, 'excel-113'),
    (114, '2026-01-30'::date, 'Expense', 'Tea expense', 'food-refreshments', 125, 'excel-114'),
    (115, '2026-01-30'::date, 'Expense', 'Lunch expense', 'food-refreshments', 380, 'excel-115'),
    (116, '2026-01-30'::date, 'Expense', 'Mason labour', 'labour-contractor', 3300, 'excel-116'),
    (117, '2026-01-30'::date, 'Expense', 'Bike petrol', 'fuel-transport', 600, 'excel-117'),
    (118, '2026-01-31'::date, 'Expense', 'Cement (30+6)', 'cement-sand-aggregate', 11000, 'excel-118'),
    (119, '2026-01-31'::date, 'Expense', 'Shaji sand', 'cement-sand-aggregate', 18700, 'excel-119'),
    (120, '2026-01-31'::date, 'Expense', 'Tea expense', 'food-refreshments', 148, 'excel-120'),
    (121, '2026-01-31'::date, 'Expense', 'Biriyani/food', 'food-refreshments', 150, 'excel-121'),
    (122, '2026-01-31'::date, 'Expense', 'Mason labour', 'labour-contractor', 3300, 'excel-122'),
    (123, '2026-02-02'::date, 'Expense', 'Tea expense', 'food-refreshments', 108, 'excel-123'),
    (124, '2026-02-02'::date, 'Expense', 'Lunch/snacks', 'food-refreshments', 170, 'excel-124'),
    (125, '2026-02-03'::date, 'Expense', 'Tea expense', 'food-refreshments', 61, 'excel-125'),
    (126, '2026-02-03'::date, 'Expense', 'Biriyani/food', 'food-refreshments', 150, 'excel-126'),
    (127, '2026-02-03'::date, 'Expense', 'Labour work - 2 tile workers / 3 people', 'labour-contractor', 6900, 'excel-127'),
    (128, '2026-02-04'::date, 'Expense', 'Timber/tool rent - 6 days', 'equipment-machinery', 800, 'excel-128'),
    (129, '2026-02-04'::date, 'Expense', 'Box/item purchase labour', 'tools-consumables', 250, 'excel-129'),
    (130, '2026-02-10'::date, 'Expense', 'Ring advance', 'equipment-machinery', 5000, 'excel-130'),
    (131, '2026-02-12'::date, 'Expense', 'Tea expense (2 nos.)', 'food-refreshments', 188, 'excel-131'),
    (132, '2026-02-12'::date, 'Expense', 'Hitachi - 1 day', 'equipment-machinery', 12000, 'excel-132'),
    (133, '2026-02-12'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-133'),
    (134, '2026-02-12'::date, 'Expense', 'Small food/tea expense', 'food-refreshments', 111, 'excel-134'),
    (135, '2026-02-13'::date, 'Expense', 'Mason/worker expense', 'labour-contractor', 2300, 'excel-135'),
    (136, '2026-02-16'::date, 'Expense', 'Mason - 1 day', 'labour-contractor', 2300, 'excel-136'),
    (137, '2026-02-16'::date, 'Expense', 'ERP Ring payments', 'equipment-machinery', 157000, 'excel-137'),
    (138, '2026-02-17'::date, 'Expense', 'Tea expense', 'food-refreshments', 102, 'excel-138'),
    (139, '2026-02-17'::date, 'Expense', 'Lunch expense', 'food-refreshments', 310, 'excel-139'),
    (140, '2026-02-17'::date, 'Expense', 'Mason/labour', 'labour-contractor', 3300, 'excel-140'),
    (141, '2026-02-18'::date, 'Expense', 'Mason/labour', 'labour-contractor', 2300, 'excel-141'),
    (142, '2026-02-18'::date, 'Expense', 'Tea expense', 'food-refreshments', 152, 'excel-142'),
    (143, '2026-02-19'::date, 'Expense', 'Tea expense', 'food-refreshments', 141, 'excel-143'),
    (144, '2026-02-19'::date, 'Expense', 'Lunch expense', 'food-refreshments', 320, 'excel-144'),
    (145, '2026-02-19'::date, 'Expense', 'Shaji sand', 'cement-sand-aggregate', 25200, 'excel-145'),
    (146, '2026-02-20'::date, 'Expense', 'Mason/labour', 'labour-contractor', 2300, 'excel-146'),
    (147, '2026-02-20'::date, 'Expense', 'Tea expense', 'food-refreshments', 141, 'excel-147'),
    (148, '2026-02-21'::date, 'Expense', 'Mason labour - 2 persons', 'labour-contractor', 4600, 'excel-148'),
    (149, '2026-02-24'::date, 'Expense', 'Tea expense', 'food-refreshments', 260, 'excel-149'),
    (150, '2026-02-24'::date, 'Expense', 'Fine aggregate/sand - 1 load', 'cement-sand-aggregate', 2700, 'excel-150'),
    (151, '2026-02-24'::date, 'Expense', 'Lime/lemon water expense', 'food-refreshments', 40, 'excel-151'),
    (152, '2026-02-24'::date, 'Expense', 'Lunch expense', 'food-refreshments', 220, 'excel-152'),
    (153, '2026-02-24'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-153'),
    (154, '2026-02-25'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-154'),
    (155, '2026-02-26'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-155'),
    (156, '2026-02-27'::date, 'Expense', 'Freeze/tool rent', 'equipment-machinery', 400, 'excel-156'),
    (157, '2026-02-27'::date, 'Expense', 'Tea expense', 'food-refreshments', 141, 'excel-157'),
    (158, '2026-02-27'::date, 'Expense', 'Sheet/gas small item', 'tools-consumables', 330, 'excel-158'),
    (159, '2026-02-27'::date, 'Expense', 'Lunch/food for workers', 'food-refreshments', 660, 'excel-159'),
    (160, '2026-02-27'::date, 'Expense', 'JCB/site load expense', 'equipment-machinery', 2300, 'excel-160'),
    (161, '2026-02-27'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-161'),
    (162, '2026-02-27'::date, 'Expense', 'Quarry/aggregate - 1 load', 'cement-sand-aggregate', 10000, 'excel-162'),
    (163, '2026-02-28'::date, 'Expense', 'Small site item / cubic jar', 'tools-consumables', 100, 'excel-163'),
    (164, '2026-02-28'::date, 'Expense', 'Cool bag', 'tools-consumables', 190, 'excel-164'),
    (165, '2026-02-28'::date, 'Expense', 'Tea expense', 'food-refreshments', 61, 'excel-165'),
    (166, '2026-02-28'::date, 'Expense', 'Two loads - site material', 'cement-sand-aggregate', 3400, 'excel-166'),
    (167, '2026-02-28'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-167'),
    (168, '2026-03-02'::date, 'Expense', 'Small site item', 'tools-consumables', 72, 'excel-168'),
    (169, '2026-03-02'::date, 'Expense', 'Water expense', 'plumbing-water', 30, 'excel-169'),
    (170, '2026-03-02'::date, 'Expense', 'Lunch for 2 people', 'food-refreshments', 320, 'excel-170'),
    (171, '2026-03-02'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-171'),
    (172, '2026-03-03'::date, 'Expense', 'Mason - Mykal / paid later', 'labour-contractor', 4300, 'excel-172'),
    (173, '2026-03-04'::date, 'Expense', 'Tea expense', 'food-refreshments', 61, 'excel-173'),
    (174, '2026-03-04'::date, 'Expense', 'Danees-related site expense', 'miscellaneous', 1000, 'excel-174'),
    (175, '2026-03-04'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-175'),
    (176, '2026-03-05'::date, 'Expense', 'Freeze tool rent', 'equipment-machinery', 1700, 'excel-176'),
    (177, '2026-03-05'::date, 'Expense', 'Royal Metals, Paika', 'metal-roofing', 58800, 'excel-177'),
    (178, '2026-03-05'::date, 'Expense', 'Lunch expense', 'food-refreshments', 300, 'excel-178'),
    (179, '2026-03-05'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-179'),
    (180, '2026-03-06'::date, 'Expense', 'Tea expense', 'food-refreshments', 141, 'excel-180'),
    (181, '2026-03-06'::date, 'Expense', 'Water expense', 'plumbing-water', 60, 'excel-181'),
    (182, '2026-03-06'::date, 'Expense', 'Lunch expense', 'food-refreshments', 320, 'excel-182'),
    (183, '2026-03-06'::date, 'Expense', 'Chain/tool rental', 'equipment-machinery', 10000, 'excel-183'),
    (184, '2026-03-06'::date, 'Expense', 'Roofing work/material advance', 'metal-roofing', 50000, 'excel-184'),
    (185, '2026-03-07'::date, 'Expense', 'Lunch expense', 'food-refreshments', 285, 'excel-185'),
    (186, '2026-03-10'::date, 'Expense', 'Union/Sunil expense', 'miscellaneous', 500, 'excel-186'),
    (187, '2026-03-10'::date, 'Expense', 'Tea expense', 'food-refreshments', 184, 'excel-187'),
    (188, '2026-03-13'::date, 'Expense', 'Small site expense', 'tools-consumables', 119, 'excel-188'),
    (189, '2026-03-13'::date, 'Expense', 'Tea expense', 'food-refreshments', 180, 'excel-189'),
    (190, '2026-03-13'::date, 'Expense', 'Paint', 'paint-finishing', 4900, 'excel-190'),
    (191, '2026-03-13'::date, 'Expense', 'Cement - 25 bags', 'cement-sand-aggregate', 26000, 'excel-191'),
    (192, '2026-03-14'::date, 'Expense', 'Tea expense', 'food-refreshments', 184, 'excel-192'),
    (193, '2026-03-14'::date, 'Expense', 'JCB/site work', 'equipment-machinery', 1500, 'excel-193'),
    (194, '2026-03-14'::date, 'Expense', 'Tea/food expense', 'food-refreshments', 212, 'excel-194'),
    (195, '2026-03-14'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 4600, 'excel-195'),
    (196, '2026-03-15'::date, 'Expense', 'Ring - 12 units', 'equipment-machinery', 14000, 'excel-196'),
    (197, '2026-03-16'::date, 'Expense', 'Hitachi and related work', 'equipment-machinery', 12400, 'excel-197'),
    (198, '2026-03-16'::date, 'Expense', 'Tea expense', 'food-refreshments', 172, 'excel-198'),
    (199, '2026-03-16'::date, 'Expense', 'Petrol for site/work', 'fuel-transport', 500, 'excel-199'),
    (200, '2026-03-16'::date, 'Expense', 'Meter box / ELCB change', 'electrical-electronics', 800, 'excel-200'),
    (201, '2026-03-16'::date, 'Expense', 'Lunch expense', 'food-refreshments', 240, 'excel-201'),
    (202, '2026-03-16'::date, 'Expense', 'Water expense', 'plumbing-water', 60, 'excel-202'),
    (203, '2026-03-16'::date, 'Expense', 'Cutting machine', 'equipment-machinery', 80, 'excel-203'),
    (204, '2026-03-16'::date, 'Expense', 'Mason - Mykal', 'labour-contractor', 2300, 'excel-204'),
    (205, '2026-03-17'::date, 'Expense', 'Tea expense', 'food-refreshments', 191, 'excel-205'),
    (206, '2026-03-17'::date, 'Expense', 'Lunch expense', 'food-refreshments', 280, 'excel-206'),
    (207, '2026-03-17'::date, 'Expense', 'Flex expense', 'planning-administration', 450, 'excel-207'),
    (208, '2026-03-18'::date, 'Expense', 'Tea expense', 'food-refreshments', 171, 'excel-208'),
    (209, '2026-03-18'::date, 'Expense', 'Paint', 'paint-finishing', 847, 'excel-209'),
    (210, '2026-03-18'::date, 'Expense', 'Lunch expense', 'food-refreshments', 240, 'excel-210'),
    (211, '2026-03-18'::date, 'Expense', 'Paint', 'paint-finishing', 960, 'excel-211'),
    (212, '2026-03-18'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 4600, 'excel-212'),
    (213, '2026-03-19'::date, 'Expense', 'Iron/metal item - 4 units', 'metal-roofing', 10150, 'excel-213'),
    (214, '2026-03-19'::date, 'Expense', 'Vehicle charge', 'fuel-transport', 400, 'excel-214'),
    (215, '2026-03-20'::date, 'Expense', 'Tea expense', 'food-refreshments', 199, 'excel-215'),
    (216, '2026-03-20'::date, 'Expense', 'Lunch expense', 'food-refreshments', 160, 'excel-216'),
    (217, '2026-03-20'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 4600, 'excel-217'),
    (218, '2026-03-21'::date, 'Expense', 'Paint roller', 'paint-finishing', 300, 'excel-218'),
    (219, '2026-03-21'::date, 'Expense', 'Tea expense', 'food-refreshments', 150, 'excel-219'),
    (220, '2026-03-21'::date, 'Expense', 'Water level tube', 'tools-consumables', 85, 'excel-220'),
    (221, '2026-03-21'::date, 'Expense', 'Lunch expense', 'food-refreshments', 250, 'excel-221'),
    (222, '2026-03-21'::date, 'Expense', 'Cement / construction material', 'cement-sand-aggregate', 22600, 'excel-222'),
    (223, '2026-03-21'::date, 'Expense', 'Mason labour (paid 22/03)', 'labour-contractor', 2300, 'excel-223'),
    (224, '2026-03-24'::date, 'Expense', 'Tea expense', 'food-refreshments', 178, 'excel-224'),
    (225, '2026-03-24'::date, 'Expense', 'Pump, wire and net/items', 'plumbing-water', 15680, 'excel-225'),
    (226, '2026-03-24'::date, 'Expense', 'Lunch expense', 'food-refreshments', 249, 'excel-226'),
    (227, '2026-03-24'::date, 'Expense', 'Mason labour (dated 25/03)', 'labour-contractor', 2300, 'excel-227'),
    (228, '2026-03-25'::date, 'Expense', 'Tea expense', 'food-refreshments', 103, 'excel-228'),
    (229, '2026-03-25'::date, 'Expense', 'Pump fitting charge', 'plumbing-water', 1000, 'excel-229'),
    (230, '2026-03-25'::date, 'Expense', 'Small tea/food expense', 'food-refreshments', 110, 'excel-230'),
    (231, '2026-03-25'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-231'),
    (232, '2026-03-25'::date, 'Expense', 'SIM charging (3 numbers)', 'communication-security', 397, 'excel-232'),
    (233, '2026-03-26'::date, 'Expense', 'Tea expense', 'food-refreshments', 96, 'excel-233'),
    (234, '2026-03-26'::date, 'Expense', 'Lunch expense', 'food-refreshments', 160, 'excel-234'),
    (235, '2026-03-26'::date, 'Expense', 'Mason/helpers', 'labour-contractor', 2300, 'excel-235'),
    (236, '2026-03-27'::date, 'Expense', 'Tea expense', 'food-refreshments', 120, 'excel-236'),
    (237, '2026-03-27'::date, 'Expense', 'Lunch expense', 'food-refreshments', 180, 'excel-237'),
    (238, '2026-03-27'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-238'),
    (239, '2026-03-28'::date, 'Expense', 'Tea expense', 'food-refreshments', 281, 'excel-239'),
    (240, '2026-03-28'::date, 'Expense', 'Sheet from Union', 'metal-roofing', 800, 'excel-240'),
    (241, '2026-03-28'::date, 'Expense', 'Paint', 'paint-finishing', 4985, 'excel-241'),
    (242, '2026-03-28'::date, 'Expense', 'CEMENT BRICKS  - 650 nos.', 'tools-consumables', 26000, 'excel-242'),
    (243, '2026-03-28'::date, 'Expense', 'Mason labour', 'labour-contractor', 2300, 'excel-243'),
    (244, '2026-03-29'::date, 'Expense', 'Tea expense', 'food-refreshments', 178, 'excel-244'),
    (245, '2026-03-29'::date, 'Expense', 'Roofing sheet and labour', 'metal-roofing', 30000, 'excel-245'),
    (246, '2026-03-30'::date, 'Expense', 'Small tea expense', 'food-refreshments', 48, 'excel-246'),
    (247, '2026-03-30'::date, 'Expense', 'Hitachi/work food expense', 'food-refreshments', 110, 'excel-247'),
    (248, '2026-03-30'::date, 'Expense', 'Small site expense', 'tools-consumables', 145, 'excel-248'),
    (249, '2026-03-30'::date, 'Expense', 'Tea expense', 'food-refreshments', 160, 'excel-249'),
    (250, '2026-03-31'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-250'),
    (251, '2026-03-31'::date, 'Expense', 'Extra pipe', 'plumbing-water', 1748, 'excel-251'),
    (252, '2026-03-31'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 4600, 'excel-252'),
    (253, '2026-03-31'::date, 'Expense', 'Camera expense', 'communication-security', 3500, 'excel-253'),
    (254, '2026-05-12'::date, 'Expense', 'Shaji sand', 'cement-sand-aggregate', 18700, 'excel-254'),
    (255, '2026-05-12'::date, 'Expense', 'Freeze spoke/light', 'equipment-machinery', 250, 'excel-255'),
    (256, '2026-05-12'::date, 'Expense', 'Tea expense', 'food-refreshments', 180, 'excel-256'),
    (257, '2026-05-12'::date, 'Expense', 'Petrol', 'fuel-transport', 200, 'excel-257'),
    (258, '2026-05-13'::date, 'Expense', 'Mason labour - 2 days / 4 people', 'labour-contractor', 5400, 'excel-258'),
    (259, '2026-05-13'::date, 'Expense', 'Tea expense (welding)', 'food-refreshments', 450, 'excel-259'),
    (260, '2026-05-15'::date, 'Expense', 'Lunch expense', 'food-refreshments', 170, 'excel-260'),
    (261, '2026-05-15'::date, 'Expense', 'Mason labour', 'labour-contractor', 9200, 'excel-261'),
    (262, '2026-05-15'::date, 'Expense', 'Mason/site small expense', 'labour-contractor', 200, 'excel-262'),
    (263, '2026-05-15'::date, 'Expense', 'Tea expense (welding)', 'food-refreshments', 590, 'excel-263'),
    (264, '2026-05-16'::date, 'Expense', 'Shaji sand', 'cement-sand-aggregate', 10000, 'excel-264'),
    (265, '2026-05-16'::date, 'Expense', 'Food expense', 'food-refreshments', 210, 'excel-265'),
    (266, '2026-05-16'::date, 'Expense', 'Mason labour (paid 17/05)', 'labour-contractor', 2300, 'excel-266'),
    (267, '2026-05-18'::date, 'Credit', 'Credit from Danees', null, 50000, 'excel-267'),
    (268, '2026-05-18'::date, 'Expense', 'Tea expense', 'food-refreshments', 111, 'excel-268'),
    (269, '2026-05-18'::date, 'Expense', 'Sand/material expense', 'cement-sand-aggregate', 2200, 'excel-269'),
    (270, '2026-05-18'::date, 'Expense', 'Vehicle charge', 'fuel-transport', 300, 'excel-270'),
    (271, '2026-05-19'::date, 'Expense', 'Tea expense', 'food-refreshments', 155, 'excel-271'),
    (272, '2026-05-19'::date, 'Expense', 'Food/site expense', 'food-refreshments', 295, 'excel-272'),
    (273, '2026-05-19'::date, 'Expense', 'Taxi/small transport', 'fuel-transport', 50, 'excel-273'),
    (274, '2026-05-19'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 9200, 'excel-274'),
    (275, '2026-05-20'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-275'),
    (276, '2026-05-20'::date, 'Expense', 'Freeze cutting machine', 'equipment-machinery', 200, 'excel-276'),
    (277, '2026-05-20'::date, 'Expense', 'Petrol', 'fuel-transport', 600, 'excel-277'),
    (278, '2026-05-20'::date, 'Expense', 'Mason labour - 4 people', 'labour-contractor', 4800, 'excel-278'),
    (279, '2026-05-20'::date, 'Credit', 'Credit from Danees', null, 25000, 'excel-279'),
    (280, '2026-05-20'::date, 'Expense', 'Payment to Danees', 'miscellaneous', 100000, 'excel-280'),
    (281, '2026-05-22'::date, 'Expense', 'Tea expense', 'food-refreshments', 92, 'excel-281'),
    (282, '2026-05-22'::date, 'Expense', 'Lunch expense', 'food-refreshments', 190, 'excel-282'),
    (283, '2026-05-23'::date, 'Credit', 'Credit from Danees Chettan', null, 8000, 'excel-283'),
    (284, '2026-05-23'::date, 'Expense', 'Mason labour - 3 days / 4 people', 'labour-contractor', 14400, 'excel-284'),
    (285, '2026-05-23'::date, 'Expense', 'Tea expense', 'food-refreshments', 130, 'excel-285'),
    (286, '2026-05-25'::date, 'Expense', 'Tea expense', 'food-refreshments', 170, 'excel-286'),
    (287, '2026-05-25'::date, 'Expense', 'Shaji P sand', 'cement-sand-aggregate', 11500, 'excel-287'),
    (288, '2026-05-25'::date, 'Expense', 'Construction material / 23 units', 'cement-sand-aggregate', 50000, 'excel-288'),
    (289, '2026-05-28'::date, 'Expense', 'Tea expense', 'food-refreshments', 180, 'excel-289'),
    (290, '2026-05-28'::date, 'Expense', 'Extra pipe', 'plumbing-water', 1421, 'excel-290'),
    (291, '2026-05-28'::date, 'Expense', 'Bleaching powder', 'plumbing-water', 40, 'excel-291'),
    (292, '2026-05-28'::date, 'Expense', 'Tea expense', 'food-refreshments', 90, 'excel-292'),
    (293, '2026-05-29'::date, 'Expense', 'Tea expense', 'food-refreshments', 84, 'excel-293'),
    (294, '2026-05-29'::date, 'Expense', 'Lunch expense', 'food-refreshments', 225, 'excel-294'),
    (295, '2026-05-30'::date, 'Expense', 'Mason labour - 3 days', 'labour-contractor', 13750, 'excel-295'),
    (296, '2026-05-30'::date, 'Expense', 'Cement - 23', 'cement-sand-aggregate', 15000, 'excel-296'),
    (297, '2026-05-30'::date, 'Expense', 'River sand - 1 load', 'cement-sand-aggregate', 9000, 'excel-297'),
    (298, '2026-05-30'::date, 'Expense', 'Tea expense', 'food-refreshments', 200, 'excel-298'),
    (299, '2026-06-01'::date, 'Expense', 'Union-related site item', 'tools-consumables', 600, 'excel-299'),
    (300, '2026-06-01'::date, 'Expense', 'Lunch expense', 'food-refreshments', 160, 'excel-300'),
    (301, '2026-06-01'::date, 'Expense', 'Petrol', 'fuel-transport', 200, 'excel-301'),
    (302, '2026-06-02'::date, 'Expense', 'Tea expense', 'food-refreshments', 100, 'excel-302'),
    (303, '2026-06-03'::date, 'Expense', 'Tea expense', 'food-refreshments', 115, 'excel-303'),
    (304, '2026-06-03'::date, 'Expense', 'Small labour/site expense', 'labour-contractor', 200, 'excel-304'),
    (305, '2026-06-03'::date, 'Expense', 'Mason labour - 3 days', 'labour-contractor', 13100, 'excel-305'),
    (306, '2026-06-04'::date, 'Expense', 'Royal Metals', 'metal-roofing', 50000, 'excel-306'),
    (307, '2026-06-05'::date, 'Expense', 'Danees - two loads stone/sand', 'cement-sand-aggregate', 24000, 'excel-307'),
    (308, '2026-06-05'::date, 'Credit', 'Credit from Danees', null, 25000, 'excel-308'),
    (309, '2026-06-05'::date, 'Expense', 'Tea expense', 'food-refreshments', 170, 'excel-309'),
    (310, '2026-06-05'::date, 'Expense', 'Lunch expense', 'food-refreshments', 130, 'excel-310'),
    (311, '2026-06-05'::date, 'Expense', 'Petrol', 'fuel-transport', 120, 'excel-311'),
    (312, '2026-06-06'::date, 'Expense', 'Cement - 12th mile, 2 nos.', 'cement-sand-aggregate', 720, 'excel-312'),
    (313, '2026-06-06'::date, 'Expense', 'Tea expense', 'food-refreshments', 240, 'excel-313'),
    (314, '2026-06-06'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 9600, 'excel-314'),
    (315, '2026-06-06'::date, 'Expense', 'Deepu/Friends payment', 'miscellaneous', 12000, 'excel-315'),
    (316, '2026-06-07'::date, 'Expense', 'Freeze compressor - 4 days', 'equipment-machinery', 1400, 'excel-316'),
    (317, '2026-06-08'::date, 'Expense', 'Royal Metals', 'metal-roofing', 13800, 'excel-317'),
    (318, '2026-06-08'::date, 'Expense', 'Freeze compressor', 'equipment-machinery', 250, 'excel-318'),
    (319, '2026-06-08'::date, 'Expense', 'Tea expense', 'food-refreshments', 185, 'excel-319'),
    (320, '2026-06-08'::date, 'Expense', 'Petrol', 'fuel-transport', 800, 'excel-320'),
    (321, '2026-06-09'::date, 'Expense', 'Tea expense', 'food-refreshments', 135, 'excel-321'),
    (322, '2026-06-09'::date, 'Credit', 'Credit from Danees', null, 10000, 'excel-322'),
    (323, '2026-06-10'::date, 'Expense', 'Lunch expense', 'food-refreshments', 170, 'excel-323'),
    (324, '2026-06-11'::date, 'Expense', 'Tea expense', 'food-refreshments', 90, 'excel-324'),
    (325, '2026-06-11'::date, 'Expense', 'Roofing sheet/material', 'metal-roofing', 25000, 'excel-325'),
    (326, '2026-06-12'::date, 'Expense', 'Mason labour - 3 days', 'labour-contractor', 10900, 'excel-326'),
    (327, '2026-06-13'::date, 'Expense', 'Tea expense', 'food-refreshments', 88, 'excel-327'),
    (328, '2026-06-13'::date, 'Expense', 'Cement board', 'cement-sand-aggregate', 22500, 'excel-328'),
    (329, '2026-06-13'::date, 'Expense', 'Royal Metals', 'metal-roofing', 45800, 'excel-329'),
    (330, '2026-06-13'::date, 'Expense', 'Freeze/tool item', 'equipment-machinery', 450, 'excel-330'),
    (331, '2026-06-13'::date, 'Expense', 'Tea expense', 'food-refreshments', 190, 'excel-331'),
    (332, '2026-06-13'::date, 'Expense', 'Petrol', 'fuel-transport', 500, 'excel-332'),
    (333, '2026-06-14'::date, 'Expense', 'Mason labour', 'labour-contractor', 7200, 'excel-333'),
    (334, '2026-06-15'::date, 'Expense', 'Petrol', 'fuel-transport', 500, 'excel-334'),
    (335, '2026-06-16'::date, 'Expense', 'Iron/mason labour', 'labour-contractor', 1300, 'excel-335'),
    (336, '2026-06-16'::date, 'Expense', 'Food expense', 'food-refreshments', 150, 'excel-336'),
    (337, '2026-06-16'::date, 'Expense', 'Petrol', 'fuel-transport', 500, 'excel-337'),
    (338, '2026-06-17'::date, 'Expense', 'Tea expense', 'food-refreshments', 214, 'excel-338'),
    (339, '2026-06-17'::date, 'Expense', 'Tile advance', 'tiles-ceramics', 5000, 'excel-339'),
    (340, '2026-06-18'::date, 'Expense', 'Tea expense', 'food-refreshments', 120, 'excel-340'),
    (341, '2026-06-18'::date, 'Credit', 'Credit from Danees', null, 40000, 'excel-341'),
    (342, '2026-06-19'::date, 'Expense', 'Plumbing', 'plumbing-water', 25000, 'excel-342'),
    (343, '2026-06-19'::date, 'Expense', 'Tea expense', 'food-refreshments', 100, 'excel-343'),
    (344, '2026-06-19'::date, 'Expense', 'Lunch expense', 'food-refreshments', 142, 'excel-344'),
    (345, '2026-06-19'::date, 'Expense', 'Mason/worker labour', 'labour-contractor', 1300, 'excel-345'),
    (346, '2026-06-19'::date, 'Expense', 'Petrol', 'fuel-transport', 600, 'excel-346'),
    (347, '2026-06-20'::date, 'Expense', 'Lunch expense', 'food-refreshments', 190, 'excel-347'),
    (348, '2026-06-20'::date, 'Expense', 'Mason labour - 4 days', 'labour-contractor', 16500, 'excel-348'),
    (349, '2026-06-20'::date, 'Expense', 'Mason/worker labour', 'labour-contractor', 1300, 'excel-349'),
    (350, '2026-06-22'::date, 'Expense', 'Friends / Deepu payment', 'miscellaneous', 3400, 'excel-350'),
    (351, '2026-06-22'::date, 'Expense', 'Petrol', 'fuel-transport', 2000, 'excel-351'),
    (352, '2026-06-22'::date, 'Credit', 'Credit from Danees', null, 25000, 'excel-352'),
    (353, '2026-06-22'::date, 'Expense', 'Pickup/transport', 'fuel-transport', 15000, 'excel-353'),
    (354, '2026-06-22'::date, 'Expense', 'M-sand', 'cement-sand-aggregate', 10000, 'excel-354'),
    (355, '2026-06-23'::date, 'Expense', 'Mason labour', 'labour-contractor', 1300, 'excel-355'),
    (356, '2026-06-24'::date, 'Expense', 'Vazhakkulam trip petrol', 'fuel-transport', 1500, 'excel-356'),
    (357, '2026-06-24'::date, 'Expense', 'Tea expense', 'food-refreshments', 200, 'excel-357'),
    (358, '2026-06-24'::date, 'Expense', 'Lunch expense', 'food-refreshments', 360, 'excel-358'),
    (359, '2026-06-24'::date, 'Expense', 'Tea expense', 'food-refreshments', 200, 'excel-359'),
    (360, '2026-06-24'::date, 'Expense', 'Pradeep mason labour', 'labour-contractor', 1300, 'excel-360'),
    (361, '2026-06-24'::date, 'Credit', 'Credit from Dennies', null, 292000, 'excel-361'),
    (362, '2026-06-25'::date, 'Expense', 'Tea expense', 'food-refreshments', 100, 'excel-362'),
    (363, '2026-06-25'::date, 'Expense', 'Petrol', 'fuel-transport', 1000, 'excel-363'),
    (364, '2026-06-25'::date, 'Expense', 'Pradeep mason labour', 'labour-contractor', 1300, 'excel-364'),
    (365, '2026-06-25'::date, 'Expense', 'Water expense', 'plumbing-water', 30, 'excel-365'),
    (366, '2026-06-25'::date, 'Expense', 'Tea expense', 'food-refreshments', 50, 'excel-366'),
    (367, '2026-06-25'::date, 'Expense', 'Mason labour', 'labour-contractor', 1900, 'excel-367'),
    (368, '2026-06-25'::date, 'Expense', 'Site/mason small expense', 'labour-contractor', 500, 'excel-368'),
    (369, '2026-06-26'::date, 'Expense', 'Tea expense', 'food-refreshments', 120, 'excel-369'),
    (370, '2026-06-26'::date, 'Expense', 'Lunch expense', 'food-refreshments', 110, 'excel-370'),
    (371, '2026-06-26'::date, 'Expense', 'Tea expense', 'food-refreshments', 150, 'excel-371'),
    (372, '2026-06-27'::date, 'Expense', 'Allen Ceramics', 'tiles-ceramics', 8000, 'excel-372'),
    (373, '2026-06-27'::date, 'Expense', 'Exhaust pipe', 'plumbing-water', 130, 'excel-373'),
    (374, '2026-06-27'::date, 'Expense', 'Tea expense', 'food-refreshments', 120, 'excel-374'),
    (375, '2026-06-27'::date, 'Expense', 'Sobana Pala tiles', 'tiles-ceramics', 37000, 'excel-375'),
    (376, '2026-06-27'::date, 'Expense', 'Tile unloading labour', 'labour-contractor', 1000, 'excel-376'),
    (377, '2026-06-27'::date, 'Expense', 'Water', 'plumbing-water', 30, 'excel-377'),
    (378, '2026-06-27'::date, 'Expense', 'Tea expense', 'food-refreshments', 120, 'excel-378'),
    (379, '2026-06-27'::date, 'Expense', 'Petrol', 'fuel-transport', 1000, 'excel-379'),
    (380, '2026-06-28'::date, 'Expense', 'Mason labour - 2 days', 'labour-contractor', 4300, 'excel-380'),
    (381, '2026-06-28'::date, 'Expense', 'Mason/site labour', 'labour-contractor', 2000, 'excel-381'),
    (382, '2026-06-29'::date, 'Expense', 'Allen Ceramic spacer', 'tiles-ceramics', 300, 'excel-382'),
    (383, '2026-06-29'::date, 'Expense', 'Waste/material - 1 kg', 'tools-consumables', 280, 'excel-383'),
    (384, '2026-06-29'::date, 'Expense', 'Lunch expense', 'food-refreshments', 190, 'excel-384'),
    (385, '2026-06-29'::date, 'Expense', 'Tea expense', 'food-refreshments', 100, 'excel-385'),
    (386, '2026-06-29'::date, 'Expense', 'Petrol', 'fuel-transport', 1000, 'excel-386'),
    (387, '2026-06-30'::date, 'Expense', 'Construction/material payment', 'miscellaneous', 8700, 'excel-387'),
    (388, '2026-06-30'::date, 'Expense', 'Tile unloading/labour', 'labour-contractor', 10000, 'excel-388'),
    (389, '2026-06-30'::date, 'Expense', 'Lunch expense', 'food-refreshments', 290, 'excel-389')
on conflict (source_key) do nothing;

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

drop trigger if exists mecardee_categories_updated_at on public.mecardee_categories;
create trigger mecardee_categories_updated_at
before update on public.mecardee_categories
for each row execute function public.set_mecardee_updated_at();

drop trigger if exists mecardee_transactions_updated_at on public.mecardee_transactions;
create trigger mecardee_transactions_updated_at
before update on public.mecardee_transactions
for each row execute function public.set_mecardee_updated_at();

drop trigger if exists mecardee_shareholders_updated_at on public.mecardee_shareholders;
create trigger mecardee_shareholders_updated_at
before update on public.mecardee_shareholders
for each row execute function public.set_mecardee_updated_at();

create or replace function public.mecardee_require_admin(
  p_session_token uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  select u.id
  into v_user_id
  from public.mecardee_user_sessions s
  join public.mecardee_users u on u.id = s.user_id
  where s.token = p_session_token
    and s.expires_at > now()
    and u.is_active = true
    and u.is_admin = true
    and u.username = 'delvin'
  limit 1;

  if v_user_id is null then
    raise exception 'Only Delvin can change project data.';
  end if;

  return v_user_id;
end;
$$;

create or replace function public.mecardee_admin_save_project(
  p_session_token uuid,
  p_name text,
  p_location text,
  p_opening_date date
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.mecardee_require_admin(p_session_token);

  update public.mecardee_project
  set
    name = coalesce(nullif(trim(p_name), ''), name),
    location = coalesce(nullif(trim(p_location), ''), location),
    opening_date = coalesce(p_opening_date, opening_date)
  where id = 1;

  return 'Project settings saved.';
end;
$$;

create or replace function public.mecardee_admin_save_category(
  p_session_token uuid,
  p_id text,
  p_name text,
  p_icon text,
  p_budget numeric,
  p_completion integer,
  p_sort_order integer,
  p_is_active boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := nullif(trim(coalesce(p_id, '')), '');
  v_name text := trim(coalesce(p_name, ''));
begin
  perform public.mecardee_require_admin(p_session_token);

  if length(v_name) < 2 then
    raise exception 'Category name is required.';
  end if;

  if v_id is null then
    v_id := lower(regexp_replace(v_name, '[^a-zA-Z0-9]+', '-', 'g'));
    v_id := trim(both '-' from v_id);
    if v_id = '' then
      v_id := 'category';
    end if;
    if exists (select 1 from public.mecardee_categories where id = v_id) then
      v_id := v_id || '-' || substr(extensions.gen_random_uuid()::text, 1, 6);
    end if;

    insert into public.mecardee_categories (
      id, name, icon, budget, completion, sort_order, is_active
    )
    values (
      v_id,
      v_name,
      coalesce(nullif(trim(p_icon), ''), '•'),
      greatest(coalesce(p_budget, 0), 0),
      greatest(0, least(100, coalesce(p_completion, 0))),
      coalesce(p_sort_order, 0),
      coalesce(p_is_active, true)
    );
  else
    update public.mecardee_categories
    set
      name = v_name,
      icon = coalesce(nullif(trim(p_icon), ''), icon),
      budget = greatest(coalesce(p_budget, 0), 0),
      completion = greatest(0, least(100, coalesce(p_completion, 0))),
      sort_order = coalesce(p_sort_order, sort_order),
      is_active = coalesce(p_is_active, is_active)
    where id = v_id;

    if not found then
      raise exception 'Category was not found.';
    end if;
  end if;

  return 'Category saved.';
end;
$$;

create or replace function public.mecardee_admin_save_shareholder(
  p_session_token uuid,
  p_id uuid,
  p_name text,
  p_amount numeric,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := p_id;
  v_name text := trim(coalesce(p_name, ''));
begin
  perform public.mecardee_require_admin(p_session_token);

  if length(v_name) < 2 then
    raise exception 'Shareholder name is required.';
  end if;

  if v_id is null then
    insert into public.mecardee_shareholders (name, amount, sort_order)
    values (
      v_name,
      greatest(coalesce(p_amount, 0), 0),
      coalesce(p_sort_order, 0)
    )
    returning id into v_id;
  else
    update public.mecardee_shareholders
    set
      name = v_name,
      amount = greatest(coalesce(p_amount, 0), 0),
      sort_order = coalesce(p_sort_order, sort_order)
    where id = v_id;

    if not found then
      raise exception 'Shareholder was not found.';
    end if;
  end if;

  return v_id;
end;
$$;

create or replace function public.mecardee_admin_save_work(
  p_session_token uuid,
  p_id uuid,
  p_title text,
  p_category_id text,
  p_owner text,
  p_work_date date,
  p_deadline date,
  p_is_completed boolean,
  p_entry_type text,
  p_amount numeric,
  p_notes text,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := p_id;
  v_entry_type text := coalesce(nullif(trim(p_entry_type), ''), 'Work');
  v_amount numeric := greatest(coalesce(p_amount, 0), 0);
begin
  perform public.mecardee_require_admin(p_session_token);

  if length(trim(coalesce(p_title, ''))) < 1 then
    raise exception 'Work description is required.';
  end if;

  if not exists (
    select 1 from public.mecardee_categories
    where id = p_category_id and is_active = true
  ) then
    raise exception 'Choose a valid category.';
  end if;

  if v_entry_type not in ('Work', 'Expense', 'Credit') then
    raise exception 'Choose Work, Expense or Credit.';
  end if;

  if v_entry_type in ('Expense', 'Credit') and v_amount <= 0 then
    raise exception 'Enter an amount for a report transaction.';
  end if;

  if v_id is null then
    insert into public.mecardee_tasks (
      title, phase, owner, work_date, deadline, progress,
      expected_cost, actual_cost, notes, sort_order,
      is_completed, entry_type, amount
    )
    values (
      trim(p_title),
      p_category_id,
      trim(coalesce(p_owner, '')),
      coalesce(p_work_date, current_date),
      coalesce(p_deadline, p_work_date, current_date),
      case when coalesce(p_is_completed, false) then 100 else 0 end,
      0,
      case when v_entry_type = 'Expense' then v_amount else 0 end,
      trim(coalesce(p_notes, '')),
      coalesce(p_sort_order, 0),
      coalesce(p_is_completed, false),
      v_entry_type,
      v_amount
    )
    returning id into v_id;
  else
    update public.mecardee_tasks
    set
      title = trim(p_title),
      phase = p_category_id,
      owner = trim(coalesce(p_owner, '')),
      work_date = coalesce(p_work_date, work_date),
      deadline = coalesce(p_deadline, deadline),
      progress = case when coalesce(p_is_completed, false) then 100 else 0 end,
      expected_cost = 0,
      actual_cost = case when v_entry_type = 'Expense' then v_amount else 0 end,
      notes = trim(coalesce(p_notes, '')),
      sort_order = coalesce(p_sort_order, sort_order),
      is_completed = coalesce(p_is_completed, false),
      entry_type = v_entry_type,
      amount = v_amount
    where id = v_id;

    if not found then
      raise exception 'Work item was not found.';
    end if;
  end if;

  if v_entry_type in ('Expense', 'Credit') then
    insert into public.mecardee_transactions (
      sort_order, txn_date, txn_type, description, category_id,
      amount, notes, source_key, work_id
    )
    values (
      coalesce(p_sort_order, 0),
      coalesce(p_work_date, current_date),
      v_entry_type,
      trim(p_title),
      case when v_entry_type = 'Expense' then p_category_id else null end,
      v_amount,
      trim(coalesce(p_notes, '')),
      'work:' || v_id::text,
      v_id
    )
    on conflict (work_id) do update set
      sort_order = excluded.sort_order,
      txn_date = excluded.txn_date,
      txn_type = excluded.txn_type,
      description = excluded.description,
      category_id = excluded.category_id,
      amount = excluded.amount,
      notes = excluded.notes,
      source_key = excluded.source_key;
  else
    delete from public.mecardee_transactions where work_id = v_id;
  end if;

  return v_id;
end;
$$;

create or replace function public.mecardee_admin_delete_work(
  p_session_token uuid,
  p_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.mecardee_require_admin(p_session_token);
  delete from public.mecardee_tasks where id = p_id;
  return 'Work deleted.';
end;
$$;

alter table public.mecardee_categories enable row level security;
alter table public.mecardee_transactions enable row level security;
alter table public.mecardee_shareholders enable row level security;

revoke insert, update, delete on public.mecardee_project from anon, authenticated;
revoke insert, update, delete on public.mecardee_tasks from anon, authenticated;
revoke insert, update, delete on public.mecardee_categories from anon, authenticated;
revoke insert, update, delete on public.mecardee_transactions from anon, authenticated;
revoke insert, update, delete on public.mecardee_shareholders from anon, authenticated;

grant select on public.mecardee_project to anon, authenticated;
grant select on public.mecardee_tasks to anon, authenticated;
grant select on public.mecardee_categories to anon, authenticated;
grant select on public.mecardee_transactions to anon, authenticated;
grant select on public.mecardee_shareholders to anon, authenticated;

drop policy if exists "Public can insert Mecardee project" on public.mecardee_project;
drop policy if exists "Public can update Mecardee project" on public.mecardee_project;
drop policy if exists "Public can delete Mecardee project" on public.mecardee_project;
drop policy if exists "Public can insert Mecardee tasks" on public.mecardee_tasks;
drop policy if exists "Public can update Mecardee tasks" on public.mecardee_tasks;
drop policy if exists "Public can delete Mecardee tasks" on public.mecardee_tasks;

drop policy if exists "Public can read Mecardee categories" on public.mecardee_categories;
create policy "Public can read Mecardee categories"
on public.mecardee_categories for select
to anon, authenticated
using (true);

drop policy if exists "Public can read Mecardee transactions" on public.mecardee_transactions;
create policy "Public can read Mecardee transactions"
on public.mecardee_transactions for select
to anon, authenticated
using (true);

drop policy if exists "Public can read Mecardee shareholders" on public.mecardee_shareholders;
create policy "Public can read Mecardee shareholders"
on public.mecardee_shareholders for select
to anon, authenticated
using (true);

revoke all on function public.mecardee_require_admin(uuid) from public;
revoke all on function public.mecardee_admin_save_project(uuid, text, text, date) from public;
revoke all on function public.mecardee_admin_save_category(uuid, text, text, text, numeric, integer, integer, boolean) from public;
revoke all on function public.mecardee_admin_save_shareholder(uuid, uuid, text, numeric, integer) from public;
revoke all on function public.mecardee_admin_save_work(uuid, uuid, text, text, text, date, date, boolean, text, numeric, text, integer) from public;
revoke all on function public.mecardee_admin_delete_work(uuid, uuid) from public;

grant execute on function public.mecardee_admin_save_project(uuid, text, text, date) to anon, authenticated;
grant execute on function public.mecardee_admin_save_category(uuid, text, text, text, numeric, integer, integer, boolean) to anon, authenticated;
grant execute on function public.mecardee_admin_save_shareholder(uuid, uuid, text, numeric, integer) to anon, authenticated;
grant execute on function public.mecardee_admin_save_work(uuid, uuid, text, text, text, date, date, boolean, text, numeric, text, integer) to anon, authenticated;
grant execute on function public.mecardee_admin_delete_work(uuid, uuid) to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mecardee_categories'
  ) then
    alter publication supabase_realtime add table public.mecardee_categories;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mecardee_transactions'
  ) then
    alter publication supabase_realtime add table public.mecardee_transactions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mecardee_shareholders'
  ) then
    alter publication supabase_realtime add table public.mecardee_shareholders;
  end if;
end $$;
