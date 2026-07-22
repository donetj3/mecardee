-- MECARDEE_CORRECT_TRANSACTION_YEARS_V1
--
-- Keep this one genuine 2025 transaction unchanged:
--   Sl. No. 1 / SIM charge / 24 Jan 2025
--
-- Change every other current transaction dated in 2025 to the same
-- day and month in 2026. No amount, type, description, category,
-- shareholder, payer, notes, source key, or other transaction detail
-- is changed.

do $$
declare
  v_preserved_count integer;
  v_updated_count integer;
begin
  select count(*)
  into v_preserved_count
  from public.mecardee_transactions
  where txn_date = date '2025-01-24'
    and lower(trim(description)) = 'sim charge'
    and (
      source_key = 'excel-1'
      or sort_order = 1
    );

  if v_preserved_count <> 1 then
    raise exception
      'Expected exactly one preserved SIM charge transaction on 24 Jan 2025, but found %.',
      v_preserved_count;
  end if;

  -- Keep linked daily-work records consistent when a transaction was
  -- created through Add work.
  update public.mecardee_tasks as task
  set
    work_date = (transaction.txn_date + interval '1 year')::date,
    deadline = case
      when extract(year from task.deadline) = 2025
        then (task.deadline + interval '1 year')::date
      else task.deadline
    end
  from public.mecardee_transactions as transaction
  where transaction.work_id = task.id
    and transaction.txn_date >= date '2025-01-01'
    and transaction.txn_date < date '2026-01-01'
    and not (
      transaction.txn_date = date '2025-01-24'
      and lower(trim(transaction.description)) = 'sim charge'
      and (
        transaction.source_key = 'excel-1'
        or transaction.sort_order = 1
      )
    );

  update public.mecardee_transactions
  set txn_date = (txn_date + interval '1 year')::date
  where txn_date >= date '2025-01-01'
    and txn_date < date '2026-01-01'
    and not (
      txn_date = date '2025-01-24'
      and lower(trim(description)) = 'sim charge'
      and (
        source_key = 'excel-1'
        or sort_order = 1
      )
    );

  get diagnostics v_updated_count = row_count;

  if exists (
    select 1
    from public.mecardee_transactions
    where txn_date >= date '2025-01-01'
      and txn_date < date '2026-01-01'
      and not (
        txn_date = date '2025-01-24'
        and lower(trim(description)) = 'sim charge'
        and (
          source_key = 'excel-1'
          or sort_order = 1
        )
      )
  ) then
    raise exception 'Some unintended 2025 transactions remain. The migration was rolled back.';
  end if;

  raise notice
    'Corrected % transaction dates from 2025 to 2026. SIM charge on 24 Jan 2025 was preserved.',
    v_updated_count;
end;
$$;