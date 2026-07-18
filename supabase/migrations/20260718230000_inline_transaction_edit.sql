-- MECARDEE_INLINE_TRANSACTION_EDIT_V1
-- Allows Delvin to correct imported expense-register rows directly.

create or replace function public.mecardee_admin_update_transaction(
  p_session_token uuid,
  p_id uuid,
  p_txn_date date,
  p_description text,
  p_category_id text,
  p_amount numeric,
  p_notes text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_work_id uuid;
  v_amount numeric := greatest(coalesce(p_amount, 0), 0);
begin
  perform public.mecardee_require_admin(p_session_token);

  select txn_type, work_id
  into v_type, v_work_id
  from public.mecardee_transactions
  where id = p_id
  for update;

  if not found then
    raise exception 'Transaction was not found.';
  end if;

  if v_type <> 'Expense' then
    raise exception 'Use the credit editor for credit entries.';
  end if;

  if length(trim(coalesce(p_description, ''))) < 1 then
    raise exception 'Description is required.';
  end if;

  if v_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;

  if not exists (
    select 1
    from public.mecardee_categories
    where id = p_category_id
      and is_active = true
  ) then
    raise exception 'Choose a valid active category.';
  end if;

  update public.mecardee_transactions
  set
    txn_date = coalesce(p_txn_date, txn_date),
    description = trim(p_description),
    category_id = p_category_id,
    amount = v_amount,
    notes = trim(coalesce(p_notes, '')),
    updated_at = now()
  where id = p_id;

  if v_work_id is not null then
    update public.mecardee_tasks
    set
      title = trim(p_description),
      phase = p_category_id,
      work_date = coalesce(p_txn_date, work_date),
      amount = v_amount,
      actual_cost = v_amount,
      notes = trim(coalesce(p_notes, '')),
      updated_at = now()
    where id = v_work_id;
  end if;

  return 'Transaction updated.';
end;
$$;

revoke all on function public.mecardee_admin_update_transaction(
  uuid, uuid, date, text, text, numeric, text
) from public;

grant execute on function public.mecardee_admin_update_transaction(
  uuid, uuid, date, text, text, numeric, text
) to anon, authenticated;