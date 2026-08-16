-- MECARDEE_FILTERED_TOTALS_CREDIT_SHAREHOLDER_V1
-- Link credit work entries to shareholders and keep shareholder totals synchronized.

alter table public.mecardee_tasks
  add column if not exists credit_shareholder_id uuid;

alter table public.mecardee_transactions
  add column if not exists shareholder_id uuid;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_tasks_credit_shareholder_fk;

alter table public.mecardee_tasks
  add constraint mecardee_tasks_credit_shareholder_fk
  foreign key (credit_shareholder_id)
  references public.mecardee_shareholders(id)
  on update cascade
  on delete set null;

alter table public.mecardee_transactions
  drop constraint if exists mecardee_transactions_shareholder_fk;

alter table public.mecardee_transactions
  add constraint mecardee_transactions_shareholder_fk
  foreign key (shareholder_id)
  references public.mecardee_shareholders(id)
  on update cascade
  on delete set null;

update public.mecardee_transactions
set shareholder_id = (
  select id
  from public.mecardee_shareholders
  where lower(name) = 'dennies'
  limit 1
)
where txn_type = 'Credit'
  and shareholder_id is null
  and lower(description) like '%dennies%';

update public.mecardee_transactions
set shareholder_id = (
  select id
  from public.mecardee_shareholders
  where lower(name) = 'dantees'
  limit 1
)
where txn_type = 'Credit'
  and shareholder_id is null
  and (
    lower(description) like '%dantees%'
    or lower(description) like '%danees%'
    or lower(description) like '%dante%'
  );

update public.mecardee_tasks as task
set credit_shareholder_id = transaction.shareholder_id
from public.mecardee_transactions as transaction
where transaction.work_id = task.id
  and transaction.txn_type = 'Credit'
  and transaction.shareholder_id is not null;

drop function if exists public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, text, integer
);

drop function if exists public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, text, integer
);

create function public.mecardee_admin_save_work(
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
  p_credit_shareholder_id uuid,
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
  v_entry_type text := coalesce(nullif(trim(p_entry_type), ''), 'Expense');
  v_amount numeric := greatest(coalesce(p_amount, 0), 0);
  v_old_entry_type text;
  v_old_amount numeric := 0;
  v_old_shareholder_id uuid;
begin
  perform public.mecardee_require_admin(p_session_token);

  if length(trim(coalesce(p_title, ''))) < 1 then
    raise exception 'Work description is required.';
  end if;

  if not exists (
    select 1
    from public.mecardee_categories
    where id = p_category_id
      and is_active = true
  ) then
    raise exception 'Choose a valid category.';
  end if;

  if v_entry_type not in ('Work', 'Expense', 'Credit') then
    raise exception 'Choose Expense or Credit.';
  end if;

  if v_id is null and v_entry_type = 'Work' then
    raise exception 'New entries must be an Expense or Credit.';
  end if;

  if v_entry_type in ('Expense', 'Credit') and v_amount <= 0 then
    raise exception 'Enter an amount for the transaction.';
  end if;

  if v_entry_type = 'Credit'
     and p_credit_shareholder_id is not null
     and not exists (
       select 1
       from public.mecardee_shareholders
       where id = p_credit_shareholder_id
     ) then
    raise exception 'Choose a valid shareholder or Other.';
  end if;

  if v_id is not null then
    select
      entry_type,
      amount,
      credit_shareholder_id
    into
      v_old_entry_type,
      v_old_amount,
      v_old_shareholder_id
    from public.mecardee_tasks
    where id = v_id
    for update;

    if not found then
      raise exception 'Work item was not found.';
    end if;

    if v_old_entry_type = 'Credit'
       and v_old_shareholder_id is not null
       and coalesce(v_old_amount, 0) > 0 then
      update public.mecardee_shareholders
      set
        amount = greatest(amount - coalesce(v_old_amount, 0), 0),
        updated_at = now()
      where id = v_old_shareholder_id;
    end if;
  end if;

  if v_id is null then
    insert into public.mecardee_tasks (
      title,
      phase,
      owner,
      work_date,
      deadline,
      progress,
      expected_cost,
      actual_cost,
      notes,
      sort_order,
      is_completed,
      entry_type,
      amount,
      credit_shareholder_id
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
      v_amount,
      case when v_entry_type = 'Credit' then p_credit_shareholder_id else null end
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
      amount = v_amount,
      credit_shareholder_id = case
        when v_entry_type = 'Credit' then p_credit_shareholder_id
        else null
      end
    where id = v_id;
  end if;

  if v_entry_type in ('Expense', 'Credit') then
    insert into public.mecardee_transactions (
      sort_order,
      txn_date,
      txn_type,
      description,
      category_id,
      amount,
      notes,
      source_key,
      work_id,
      shareholder_id
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
      v_id,
      case when v_entry_type = 'Credit' then p_credit_shareholder_id else null end
    )
    on conflict (work_id) do update set
      sort_order = excluded.sort_order,
      txn_date = excluded.txn_date,
      txn_type = excluded.txn_type,
      description = excluded.description,
      category_id = excluded.category_id,
      amount = excluded.amount,
      notes = excluded.notes,
      source_key = excluded.source_key,
      shareholder_id = excluded.shareholder_id,
      updated_at = now();
  else
    delete from public.mecardee_transactions
    where work_id = v_id;
  end if;

  if v_entry_type = 'Credit'
     and p_credit_shareholder_id is not null then
    update public.mecardee_shareholders
    set
      amount = amount + v_amount,
      updated_at = now()
    where id = p_credit_shareholder_id;
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
declare
  v_entry_type text;
  v_amount numeric := 0;
  v_shareholder_id uuid;
begin
  perform public.mecardee_require_admin(p_session_token);

  select
    entry_type,
    amount,
    credit_shareholder_id
  into
    v_entry_type,
    v_amount,
    v_shareholder_id
  from public.mecardee_tasks
  where id = p_id
  for update;

  if not found then
    raise exception 'Work item was not found.';
  end if;

  if v_entry_type = 'Credit'
     and v_shareholder_id is not null
     and coalesce(v_amount, 0) > 0 then
    update public.mecardee_shareholders
    set
      amount = greatest(amount - coalesce(v_amount, 0), 0),
      updated_at = now()
    where id = v_shareholder_id;
  end if;

  delete from public.mecardee_tasks
  where id = p_id;

  return 'Work deleted.';
end;
$$;

revoke all on function public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, text, integer
) from public;

grant execute on function public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, text, integer
) to anon, authenticated;
