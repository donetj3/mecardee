-- MECARDEE_PAID_BY_PARTNER_CONTRIBUTIONS_V1
-- Adds expense payer tracking and calculated partner contribution reporting.
-- Existing transaction amounts, dates, descriptions, categories and credits are preserved.

insert into public.mecardee_shareholders (name, amount, sort_order)
select partner.name, 0, partner.sort_order
from (
  values
    ('Delvin'::text, 1),
    ('Dantees'::text, 2),
    ('Dennis'::text, 3)
) as partner(name, sort_order)
where not exists (
  select 1
  from public.mecardee_shareholders existing
  where lower(trim(existing.name)) = lower(partner.name)
);

alter table public.mecardee_tasks
  add column if not exists paid_by uuid;

alter table public.mecardee_transactions
  add column if not exists paid_by uuid;

alter table if exists public.mecardee_deleted_transactions
  add column if not exists paid_by uuid;

alter table if exists public.mecardee_deleted_transactions
  add column if not exists paid_by_name text;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_tasks_paid_by_fk;

alter table public.mecardee_tasks
  add constraint mecardee_tasks_paid_by_fk
  foreign key (paid_by)
  references public.mecardee_shareholders(id)
  on update cascade
  on delete restrict;

alter table public.mecardee_transactions
  drop constraint if exists mecardee_transactions_paid_by_fk;

alter table public.mecardee_transactions
  add constraint mecardee_transactions_paid_by_fk
  foreign key (paid_by)
  references public.mecardee_shareholders(id)
  on update cascade
  on delete restrict;

alter table if exists public.mecardee_deleted_transactions
  drop constraint if exists mecardee_deleted_transactions_paid_by_fk;

alter table if exists public.mecardee_deleted_transactions
  add constraint mecardee_deleted_transactions_paid_by_fk
  foreign key (paid_by)
  references public.mecardee_shareholders(id)
  on update cascade
  on delete set null;

create index if not exists mecardee_transactions_paid_by_idx
on public.mecardee_transactions (paid_by)
where txn_type = 'Expense';

create index if not exists mecardee_tasks_paid_by_idx
on public.mecardee_tasks (paid_by)
where entry_type = 'Expense';

do $$
declare
  v_delvin_id uuid;
begin
  select id
  into v_delvin_id
  from public.mecardee_shareholders
  where lower(trim(name)) = 'delvin'
  order by sort_order, id
  limit 1;

  if v_delvin_id is null then
    raise exception 'The Delvin shareholder record is required.';
  end if;

  -- Only the new payer field is changed. All existing financial details remain untouched.
  update public.mecardee_transactions
  set paid_by = v_delvin_id
  where txn_type = 'Expense'
    and paid_by is null;

  update public.mecardee_tasks task
  set paid_by = coalesce(
    (
      select transaction.paid_by
      from public.mecardee_transactions transaction
      where transaction.work_id = task.id
        and transaction.txn_type = 'Expense'
      limit 1
    ),
    v_delvin_id
  )
  where task.entry_type = 'Expense'
    and task.paid_by is null;
end;
$$;

alter table public.mecardee_transactions
  drop constraint if exists mecardee_expense_paid_by_required;

alter table public.mecardee_transactions
  add constraint mecardee_expense_paid_by_required
  check (txn_type <> 'Expense' or paid_by is not null);

alter table public.mecardee_tasks
  drop constraint if exists mecardee_task_expense_paid_by_required;

alter table public.mecardee_tasks
  add constraint mecardee_task_expense_paid_by_required
  check (entry_type <> 'Expense' or paid_by is not null);

create or replace function public.mecardee_is_named_partner(
  p_shareholder_id uuid
)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.mecardee_shareholders shareholder
    where shareholder.id = p_shareholder_id
      and lower(trim(shareholder.name)) in ('delvin', 'dantees', 'dennis')
  );
$$;

drop function if exists public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, uuid, text, integer
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
  p_paid_by uuid,
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

  if v_entry_type in ('Expense', 'Credit') and v_amount <= 0 then
    raise exception 'Enter an amount for the transaction.';
  end if;

  if v_entry_type = 'Expense' and not public.mecardee_is_named_partner(p_paid_by) then
    raise exception 'Choose Delvin, Dantees or Dennis in Paid by.';
  end if;

  if v_entry_type = 'Credit' and not public.mecardee_is_named_partner(p_credit_shareholder_id) then
    raise exception 'Assign the credit to Delvin, Dantees or Dennis.';
  end if;

  if v_id is not null then
    select entry_type, amount, credit_shareholder_id
    into v_old_entry_type, v_old_amount, v_old_shareholder_id
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
      credit_shareholder_id,
      paid_by
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
      case when v_entry_type = 'Credit' then p_credit_shareholder_id else null end,
      case when v_entry_type = 'Expense' then p_paid_by else null end
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
      end,
      paid_by = case
        when v_entry_type = 'Expense' then p_paid_by
        else null
      end,
      updated_at = now()
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
      shareholder_id,
      paid_by
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
      case when v_entry_type = 'Credit' then p_credit_shareholder_id else null end,
      case when v_entry_type = 'Expense' then p_paid_by else null end
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
      paid_by = excluded.paid_by,
      updated_at = now();
  else
    delete from public.mecardee_transactions
    where work_id = v_id;
  end if;

  if v_entry_type = 'Credit' then
    update public.mecardee_shareholders
    set
      amount = amount + v_amount,
      updated_at = now()
    where id = p_credit_shareholder_id;
  end if;

  return v_id;
end;
$$;

drop function if exists public.mecardee_admin_update_transaction_v3(
  uuid, uuid, date, text, text, uuid, uuid, numeric, text
);

create function public.mecardee_admin_update_transaction_v3(
  p_session_token uuid,
  p_id uuid,
  p_txn_date date,
  p_description text,
  p_category_id text,
  p_shareholder_id uuid,
  p_paid_by uuid,
  p_amount numeric,
  p_notes text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction public.mecardee_transactions%rowtype;
  v_amount numeric := greatest(coalesce(p_amount, 0), 0);
  v_shareholder_name text;
begin
  perform public.mecardee_require_admin(p_session_token);

  select *
  into v_transaction
  from public.mecardee_transactions
  where id = p_id
  for update;

  if not found then
    raise exception 'Transaction was not found.';
  end if;

  if length(trim(coalesce(p_description, ''))) < 1 then
    raise exception 'Description is required.';
  end if;

  if v_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;

  if v_transaction.txn_type = 'Expense' then
    if not exists (
      select 1
      from public.mecardee_categories
      where id = p_category_id
        and is_active = true
    ) then
      raise exception 'Choose a valid active category.';
    end if;

    if not public.mecardee_is_named_partner(p_paid_by) then
      raise exception 'Choose Delvin, Dantees or Dennis in Paid by.';
    end if;
  elsif v_transaction.txn_type = 'Credit' then
    if not public.mecardee_is_named_partner(p_shareholder_id) then
      raise exception 'Assign the credit to Delvin, Dantees or Dennis.';
    end if;

    select name
    into v_shareholder_name
    from public.mecardee_shareholders
    where id = p_shareholder_id;
  else
    raise exception 'Only expense and credit transactions can be edited.';
  end if;

  if v_transaction.txn_type = 'Credit'
     and v_transaction.shareholder_id is not null then
    update public.mecardee_shareholders
    set
      amount = greatest(amount - coalesce(v_transaction.amount, 0), 0),
      updated_at = now()
    where id = v_transaction.shareholder_id;
  end if;

  if v_transaction.txn_type = 'Credit' then
    update public.mecardee_shareholders
    set
      amount = amount + v_amount,
      updated_at = now()
    where id = p_shareholder_id;
  end if;

  update public.mecardee_transactions
  set
    txn_date = coalesce(p_txn_date, txn_date),
    description = trim(p_description),
    category_id = case
      when v_transaction.txn_type = 'Expense' then p_category_id
      else null
    end,
    shareholder_id = case
      when v_transaction.txn_type = 'Credit' then p_shareholder_id
      else null
    end,
    paid_by = case
      when v_transaction.txn_type = 'Expense' then p_paid_by
      else null
    end,
    amount = v_amount,
    notes = trim(coalesce(p_notes, '')),
    updated_at = now()
  where id = p_id;

  if v_transaction.work_id is not null then
    update public.mecardee_tasks
    set
      title = trim(p_description),
      phase = case
        when v_transaction.txn_type = 'Expense' then p_category_id
        else phase
      end,
      owner = case
        when v_transaction.txn_type = 'Credit' then coalesce(v_shareholder_name, owner)
        else owner
      end,
      work_date = coalesce(p_txn_date, work_date),
      deadline = case
        when v_transaction.txn_type = 'Credit'
          then coalesce(p_txn_date, work_date)
        else deadline
      end,
      entry_type = v_transaction.txn_type,
      amount = v_amount,
      actual_cost = case
        when v_transaction.txn_type = 'Expense' then v_amount
        else 0
      end,
      credit_shareholder_id = case
        when v_transaction.txn_type = 'Credit' then p_shareholder_id
        else null
      end,
      paid_by = case
        when v_transaction.txn_type = 'Expense' then p_paid_by
        else null
      end,
      notes = trim(coalesce(p_notes, '')),
      updated_at = now()
    where id = v_transaction.work_id;
  end if;

  return v_transaction.txn_type || ' updated.';
end;
$$;

-- Recreate the deleted-entry list with payer information.
drop function if exists public.mecardee_admin_list_deleted_transactions(uuid);

create function public.mecardee_admin_list_deleted_transactions(
  p_session_token uuid
)
returns table (
  id uuid,
  original_transaction_id uuid,
  original_sort_order integer,
  txn_date date,
  txn_type text,
  description text,
  category_id text,
  category_name text,
  amount numeric,
  notes text,
  source_key text,
  work_id uuid,
  shareholder_id uuid,
  shareholder_name text,
  paid_by uuid,
  paid_by_name text,
  deleted_by uuid,
  deleted_by_username text,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.mecardee_require_admin(p_session_token);

  return query
  select
    deleted.id,
    deleted.original_transaction_id,
    deleted.original_sort_order,
    deleted.txn_date,
    deleted.txn_type,
    deleted.description,
    deleted.category_id,
    deleted.category_name,
    deleted.amount,
    deleted.notes,
    deleted.source_key,
    deleted.work_id,
    deleted.shareholder_id,
    deleted.shareholder_name,
    deleted.paid_by,
    deleted.paid_by_name,
    deleted.deleted_by,
    deleted.deleted_by_username,
    deleted.deleted_at
  from public.mecardee_deleted_transactions deleted
  order by deleted.deleted_at desc, deleted.txn_date desc;
end;
$$;

create or replace function public.mecardee_admin_delete_transaction(
  p_session_token uuid,
  p_id uuid,
  p_admin_password text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_username text;
  v_transaction public.mecardee_transactions%rowtype;
  v_category_name text;
  v_shareholder_name text;
  v_paid_by_name text;
begin
  v_user_id := public.mecardee_require_admin_password(
    p_session_token,
    p_admin_password
  );

  select username
  into v_username
  from public.mecardee_users
  where id = v_user_id;

  select *
  into v_transaction
  from public.mecardee_transactions
  where id = p_id
  for update;

  if not found then
    raise exception 'Transaction was not found.';
  end if;

  if v_transaction.category_id is not null then
    select name
    into v_category_name
    from public.mecardee_categories
    where id = v_transaction.category_id;
  end if;

  if v_transaction.shareholder_id is not null then
    select name
    into v_shareholder_name
    from public.mecardee_shareholders
    where id = v_transaction.shareholder_id;
  end if;

  if v_transaction.paid_by is not null then
    select name
    into v_paid_by_name
    from public.mecardee_shareholders
    where id = v_transaction.paid_by;
  end if;

  insert into public.mecardee_deleted_transactions (
    original_transaction_id,
    original_sort_order,
    txn_date,
    txn_type,
    description,
    category_id,
    category_name,
    amount,
    notes,
    source_key,
    work_id,
    shareholder_id,
    shareholder_name,
    paid_by,
    paid_by_name,
    deleted_by,
    deleted_by_username
  )
  values (
    v_transaction.id,
    coalesce(v_transaction.sort_order, 0),
    v_transaction.txn_date,
    v_transaction.txn_type,
    v_transaction.description,
    v_transaction.category_id,
    v_category_name,
    v_transaction.amount,
    coalesce(v_transaction.notes, ''),
    v_transaction.source_key,
    v_transaction.work_id,
    v_transaction.shareholder_id,
    v_shareholder_name,
    v_transaction.paid_by,
    v_paid_by_name,
    v_user_id,
    coalesce(v_username, 'delvin')
  );

  if v_transaction.txn_type = 'Credit'
     and v_transaction.shareholder_id is not null then
    update public.mecardee_shareholders
    set
      amount = greatest(amount - coalesce(v_transaction.amount, 0), 0),
      updated_at = now()
    where id = v_transaction.shareholder_id;
  end if;

  if v_transaction.work_id is not null then
    delete from public.mecardee_tasks
    where id = v_transaction.work_id;
  end if;

  delete from public.mecardee_transactions
  where id = p_id;

  return 'Entry moved to the Deleted Entries Report.';
end;
$$;

revoke all on function public.mecardee_is_named_partner(uuid) from public;
revoke all on function public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, uuid, text, integer
) from public;
revoke all on function public.mecardee_admin_update_transaction_v3(
  uuid, uuid, date, text, text, uuid, uuid, numeric, text
) from public;
revoke all on function public.mecardee_admin_list_deleted_transactions(uuid) from public;
revoke all on function public.mecardee_admin_delete_transaction(uuid, uuid, text) from public;

-- Prevent the old write RPCs from bypassing the new payer requirement.
do $$
begin
  if to_regprocedure(
    'public.mecardee_admin_save_work(uuid,uuid,text,text,text,date,date,boolean,text,numeric,uuid,text,integer)'
  ) is not null then
    execute 'revoke execute on function public.mecardee_admin_save_work(
      uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, text, integer
    ) from anon, authenticated';
  end if;

  if to_regprocedure(
    'public.mecardee_admin_update_transaction_v2(uuid,uuid,date,text,text,uuid,numeric,text)'
  ) is not null then
    execute 'revoke execute on function public.mecardee_admin_update_transaction_v2(
      uuid, uuid, date, text, text, uuid, numeric, text
    ) from anon, authenticated';
  end if;
end;
$$;

grant execute on function public.mecardee_admin_save_work(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric, uuid, uuid, text, integer
) to anon, authenticated;

grant execute on function public.mecardee_admin_update_transaction_v3(
  uuid, uuid, date, text, text, uuid, uuid, numeric, text
) to anon, authenticated;

grant execute on function public.mecardee_admin_list_deleted_transactions(uuid)
to anon, authenticated;

grant execute on function public.mecardee_admin_delete_transaction(uuid, uuid, text)
to anon, authenticated;

notify pgrst, 'reload schema';
