-- MECARDEE_SECURE_DELETED_ENTRIES_V1
-- Password-protected transaction deletion with an admin-only audit report.

create table if not exists public.mecardee_deleted_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  original_transaction_id uuid not null,
  original_sort_order integer not null default 0,
  txn_date date not null,
  txn_type text not null check (txn_type in ('Expense', 'Credit')),
  description text not null,
  category_id text,
  category_name text,
  amount numeric(14, 2) not null check (amount >= 0),
  notes text not null default '',
  source_key text,
  work_id uuid,
  shareholder_id uuid,
  shareholder_name text,
  deleted_by uuid,
  deleted_by_username text not null default 'delvin',
  deleted_at timestamptz not null default now()
);

create index if not exists mecardee_deleted_transactions_deleted_at_idx
on public.mecardee_deleted_transactions (deleted_at desc);

alter table public.mecardee_deleted_transactions enable row level security;

revoke all on public.mecardee_deleted_transactions from anon, authenticated;

create or replace function public.mecardee_require_admin_password(
  p_session_token uuid,
  p_admin_password text
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
    and u.password_hash = extensions.crypt(
      coalesce(p_admin_password, ''),
      u.password_hash
    )
  limit 1;

  if v_user_id is null then
    raise exception 'Incorrect admin password.';
  end if;

  return v_user_id;
end;
$$;

create or replace function public.mecardee_admin_list_deleted_transactions(
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
    d.id,
    d.original_transaction_id,
    d.original_sort_order,
    d.txn_date,
    d.txn_type,
    d.description,
    d.category_id,
    d.category_name,
    d.amount,
    d.notes,
    d.source_key,
    d.work_id,
    d.shareholder_id,
    d.shareholder_name,
    d.deleted_by,
    d.deleted_by_username,
    d.deleted_at
  from public.mecardee_deleted_transactions d
  order by d.deleted_at desc, d.txn_date desc;
end;
$$;

create or replace function public.mecardee_admin_update_transaction_v2(
  p_session_token uuid,
  p_id uuid,
  p_txn_date date,
  p_description text,
  p_category_id text,
  p_shareholder_id uuid,
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
  v_shareholder_name text := 'Other';
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
  elsif v_transaction.txn_type = 'Credit' then
    if p_shareholder_id is not null then
      select name
      into v_shareholder_name
      from public.mecardee_shareholders
      where id = p_shareholder_id;

      if not found then
        raise exception 'Choose a valid credit source.';
      end if;
    end if;
  else
    raise exception 'Only expense and credit transactions can be edited.';
  end if;

  if (
    v_transaction.txn_type = 'Credit'
    and v_transaction.shareholder_id is not null
  ) then
    update public.mecardee_shareholders
    set
      amount = greatest(amount - coalesce(v_transaction.amount, 0), 0),
      updated_at = now()
    where id = v_transaction.shareholder_id;
  end if;

  if (
    v_transaction.txn_type = 'Credit'
    and p_shareholder_id is not null
  ) then
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
        when v_transaction.txn_type = 'Credit' then v_shareholder_name
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
      notes = trim(coalesce(p_notes, '')),
      updated_at = now()
    where id = v_transaction.work_id;
  end if;

  return v_transaction.txn_type || ' updated.';
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
    v_user_id,
    coalesce(v_username, 'delvin')
  );

  if (
    v_transaction.txn_type = 'Credit'
    and v_transaction.shareholder_id is not null
  ) then
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

create or replace function public.mecardee_admin_delete_work_secure(
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
  limit 1;

  if v_transaction_id is not null then
    return public.mecardee_admin_delete_transaction(
      p_session_token,
      v_transaction_id,
      p_admin_password
    );
  end if;

  delete from public.mecardee_tasks
  where id = p_id;

  if not found then
    raise exception 'Work item was not found.';
  end if;

  return 'Work deleted.';
end;
$$;

revoke all on function public.mecardee_require_admin_password(uuid, text) from public;
revoke all on function public.mecardee_admin_list_deleted_transactions(uuid) from public;
revoke all on function public.mecardee_admin_update_transaction_v2(
  uuid, uuid, date, text, text, uuid, numeric, text
) from public;
revoke all on function public.mecardee_admin_delete_transaction(
  uuid, uuid, text
) from public;
revoke all on function public.mecardee_admin_delete_work_secure(
  uuid, uuid, text
) from public;

-- Disable the old two-argument delete RPC so deletion cannot bypass
-- the current admin-password requirement.
revoke execute on function public.mecardee_admin_delete_work(uuid, uuid)
from anon, authenticated;

grant execute on function public.mecardee_admin_list_deleted_transactions(uuid)
to anon, authenticated;

grant execute on function public.mecardee_admin_update_transaction_v2(
  uuid, uuid, date, text, text, uuid, numeric, text
) to anon, authenticated;

grant execute on function public.mecardee_admin_delete_transaction(
  uuid, uuid, text
) to anon, authenticated;

grant execute on function public.mecardee_admin_delete_work_secure(
  uuid, uuid, text
) to anon, authenticated;