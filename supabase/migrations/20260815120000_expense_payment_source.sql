-- Adds an explicit payment source without rewriting any historical row.
-- Legacy expenses keep payment_source NULL so the client can interpret the
-- former Delvin default as Credit Balance while preserving deliberate
-- historical non-Delvin payer selections.

begin;

alter table public.mecardee_tasks
  add column if not exists payment_source text;

alter table public.mecardee_transactions
  add column if not exists payment_source text;

alter table if exists public.mecardee_deleted_transactions
  add column if not exists payment_source text;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_task_expense_paid_by_required;

alter table public.mecardee_tasks
  drop constraint if exists mecardee_tasks_payment_source_check;

alter table public.mecardee_tasks
  add constraint mecardee_tasks_payment_source_check
  check (
    payment_source is null
    or payment_source in ('credit_balance', 'partner')
  );

alter table public.mecardee_tasks
  add constraint mecardee_task_expense_paid_by_required
  check (
    entry_type <> 'Expense'
    or payment_source is null
    or payment_source = 'credit_balance'
    or paid_by is not null
  );

alter table public.mecardee_tasks
  drop constraint if exists mecardee_task_payment_source_consistent;

alter table public.mecardee_tasks
  add constraint mecardee_task_payment_source_consistent
  check (
    payment_source is null
    or (entry_type = 'Expense' and payment_source = 'credit_balance' and paid_by is null)
    or (entry_type = 'Expense' and payment_source = 'partner' and paid_by is not null)
  );

alter table public.mecardee_transactions
  drop constraint if exists mecardee_expense_paid_by_required;

alter table public.mecardee_transactions
  drop constraint if exists mecardee_transactions_payment_source_check;

alter table public.mecardee_transactions
  add constraint mecardee_transactions_payment_source_check
  check (
    payment_source is null
    or payment_source in ('credit_balance', 'partner')
  );

alter table public.mecardee_transactions
  add constraint mecardee_expense_paid_by_required
  check (
    txn_type <> 'Expense'
    or payment_source is null
    or payment_source = 'credit_balance'
    or paid_by is not null
  );

alter table public.mecardee_transactions
  drop constraint if exists mecardee_transaction_payment_source_consistent;

alter table public.mecardee_transactions
  add constraint mecardee_transaction_payment_source_consistent
  check (
    payment_source is null
    or (txn_type = 'Expense' and payment_source = 'credit_balance' and paid_by is null)
    or (txn_type = 'Expense' and payment_source = 'partner' and paid_by is not null)
  );

alter table if exists public.mecardee_deleted_transactions
  drop constraint if exists mecardee_deleted_transactions_payment_source_check;

alter table if exists public.mecardee_deleted_transactions
  add constraint mecardee_deleted_transactions_payment_source_check
  check (
    payment_source is null
    or payment_source in ('credit_balance', 'partner')
  );

create index if not exists mecardee_transactions_payment_source_idx
on public.mecardee_transactions (payment_source)
where txn_type = 'Expense';

create or replace function public.mecardee_admin_save_work_v2(
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
  p_payment_source text,
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
  v_id uuid;
  v_entry_type text := coalesce(nullif(trim(p_entry_type), ''), 'Expense');
  v_payment_source text;
  v_legacy_paid_by uuid := p_paid_by;
begin
  perform public.mecardee_require_admin(p_session_token);

  if v_entry_type = 'Expense' then
    v_payment_source := coalesce(
      nullif(trim(p_payment_source), ''),
      'credit_balance'
    );

    if v_payment_source not in ('credit_balance', 'partner') then
      raise exception 'Choose Credit Balance or a partner in Paid by.';
    end if;

    if v_payment_source = 'partner' then
      if not public.mecardee_is_named_partner(p_paid_by) then
        raise exception 'Choose a valid partner in Paid by.';
      end if;
    else
      select shareholder.id
      into v_legacy_paid_by
      from public.mecardee_shareholders shareholder
      where lower(trim(shareholder.name)) = 'delvin'
      order by shareholder.sort_order, shareholder.id
      limit 1;

      if v_legacy_paid_by is null then
        raise exception 'The Delvin shareholder record is required for backward compatibility.';
      end if;
    end if;
  else
    v_payment_source := null;
    v_legacy_paid_by := null;
  end if;

  -- The legacy function does not know about payment_source. Clear only the
  -- explicit marker inside this transaction so it can update either an
  -- existing Credit Balance expense or change the entry type. The requested
  -- explicit value is restored immediately below, and any failure rolls the
  -- whole transaction back.
  if p_id is not null then
    update public.mecardee_tasks
    set payment_source = null
    where id = p_id;

    update public.mecardee_transactions
    set payment_source = null
    where work_id = p_id;
  end if;

  v_id := public.mecardee_admin_save_work(
    p_session_token,
    p_id,
    p_title,
    p_category_id,
    p_owner,
    p_work_date,
    p_deadline,
    p_is_completed,
    v_entry_type,
    p_amount,
    p_credit_shareholder_id,
    v_legacy_paid_by,
    p_notes,
    p_sort_order
  );

  update public.mecardee_tasks
  set
    payment_source = v_payment_source,
    paid_by = case
      when v_payment_source = 'partner' then p_paid_by
      else null
    end,
    updated_at = now()
  where id = v_id;

  update public.mecardee_transactions
  set
    payment_source = v_payment_source,
    paid_by = case
      when v_payment_source = 'partner' then p_paid_by
      else null
    end,
    updated_at = now()
  where work_id = v_id;

  return v_id;
end;
$$;

create or replace function public.mecardee_admin_update_transaction_v4(
  p_session_token uuid,
  p_id uuid,
  p_txn_date date,
  p_description text,
  p_category_id text,
  p_shareholder_id uuid,
  p_payment_source text,
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
  v_payment_source text;
  v_legacy_paid_by uuid := p_paid_by;
  v_result text;
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

  if v_transaction.txn_type = 'Expense' then
    v_payment_source := coalesce(
      nullif(trim(p_payment_source), ''),
      'credit_balance'
    );

    if v_payment_source not in ('credit_balance', 'partner') then
      raise exception 'Choose Credit Balance or a partner in Paid by.';
    end if;

    if v_payment_source = 'partner' then
      if not public.mecardee_is_named_partner(p_paid_by) then
        raise exception 'Choose a valid partner in Paid by.';
      end if;
    else
      select shareholder.id
      into v_legacy_paid_by
      from public.mecardee_shareholders shareholder
      where lower(trim(shareholder.name)) = 'delvin'
      order by shareholder.sort_order, shareholder.id
      limit 1;

      if v_legacy_paid_by is null then
        raise exception 'The Delvin shareholder record is required for backward compatibility.';
      end if;
    end if;
  else
    v_payment_source := null;
    v_legacy_paid_by := null;
  end if;

  -- See the save wrapper above: temporarily expose the row in its legacy
  -- shape so the v3 updater can run under the new consistency constraints.
  update public.mecardee_transactions
  set payment_source = null
  where id = p_id;

  if v_transaction.work_id is not null then
    update public.mecardee_tasks
    set payment_source = null
    where id = v_transaction.work_id;
  end if;

  v_result := public.mecardee_admin_update_transaction_v3(
    p_session_token,
    p_id,
    p_txn_date,
    p_description,
    p_category_id,
    p_shareholder_id,
    v_legacy_paid_by,
    p_amount,
    p_notes
  );

  update public.mecardee_transactions
  set
    payment_source = v_payment_source,
    paid_by = case
      when v_payment_source = 'partner' then p_paid_by
      else null
    end,
    updated_at = now()
  where id = p_id;

  update public.mecardee_tasks
  set
    payment_source = v_payment_source,
    paid_by = case
      when v_payment_source = 'partner' then p_paid_by
      else null
    end,
    updated_at = now()
  where id = v_transaction.work_id;

  return v_result;
end;
$$;

create or replace function public.mecardee_admin_delete_transaction_v2(
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
  v_payment_source text;
  v_result text;
begin
  perform public.mecardee_require_admin_password(
    p_session_token,
    p_admin_password
  );

  select payment_source
  into v_payment_source
  from public.mecardee_transactions
  where id = p_id
  for update;

  v_result := public.mecardee_admin_delete_transaction(
    p_session_token,
    p_id,
    p_admin_password
  );

  update public.mecardee_deleted_transactions
  set payment_source = v_payment_source
  where original_transaction_id = p_id;

  return v_result;
end;
$$;

create or replace function public.mecardee_admin_delete_work_secure_v2(
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
  v_transaction_id uuid;
begin
  perform public.mecardee_require_admin_password(
    p_session_token,
    p_admin_password
  );

  select id
  into v_transaction_id
  from public.mecardee_transactions
  where work_id = p_id
  limit 1
  for update;

  if v_transaction_id is not null then
    return public.mecardee_admin_delete_transaction_v2(
      p_session_token,
      v_transaction_id,
      p_admin_password
    );
  end if;

  return public.mecardee_admin_delete_work_secure(
    p_session_token,
    p_id,
    p_admin_password
  );
end;
$$;

create or replace function public.mecardee_admin_list_deleted_transactions_v2(
  p_session_token uuid
)
returns table(
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
  payment_source text,
  deleted_by uuid,
  deleted_by_username text,
  deleted_at timestamp with time zone
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
    deleted.payment_source,
    deleted.deleted_by,
    deleted.deleted_by_username,
    deleted.deleted_at
  from public.mecardee_deleted_transactions deleted
  order by deleted.deleted_at desc, deleted.txn_date desc;
end;
$$;

revoke all on function public.mecardee_admin_save_work_v2(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric,
  uuid, text, uuid, text, integer
) from public;
grant execute on function public.mecardee_admin_save_work_v2(
  uuid, uuid, text, text, text, date, date, boolean, text, numeric,
  uuid, text, uuid, text, integer
) to anon, authenticated, service_role;

revoke all on function public.mecardee_admin_update_transaction_v4(
  uuid, uuid, date, text, text, uuid, text, uuid, numeric, text
) from public;
grant execute on function public.mecardee_admin_update_transaction_v4(
  uuid, uuid, date, text, text, uuid, text, uuid, numeric, text
) to anon, authenticated, service_role;

revoke all on function public.mecardee_admin_delete_transaction_v2(
  uuid, uuid, text
) from public;
grant execute on function public.mecardee_admin_delete_transaction_v2(
  uuid, uuid, text
) to anon, authenticated, service_role;

revoke all on function public.mecardee_admin_delete_work_secure_v2(
  uuid, uuid, text
) from public;
grant execute on function public.mecardee_admin_delete_work_secure_v2(
  uuid, uuid, text
) to anon, authenticated, service_role;

revoke all on function public.mecardee_admin_list_deleted_transactions_v2(uuid)
from public;
grant execute on function public.mecardee_admin_list_deleted_transactions_v2(uuid)
to anon, authenticated, service_role;

commit;
