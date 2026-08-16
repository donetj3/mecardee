


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."mecardee_add_user"("p_session_token" "uuid", "p_username" "text", "p_password" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_is_admin boolean;
  v_username text := lower(trim(p_username));
begin
  select u.is_admin
  into v_is_admin
  from public.mecardee_user_sessions s
  join public.mecardee_users u on u.id = s.user_id
  where s.token = p_session_token
    and s.expires_at > now()
    and u.is_active = true
  limit 1;

  if coalesce(v_is_admin, false) = false then
    raise exception 'Only Delvin can add users.';
  end if;

  if v_username !~ '^[a-z0-9._-]{3,40}$' then
    raise exception 'Username must contain 3-40 letters, numbers, dots, underscores or hyphens.';
  end if;

  if length(coalesce(p_password, '')) < 4 then
    raise exception 'Password must contain at least 4 characters.';
  end if;

  insert into public.mecardee_users (
    username,
    password_hash,
    is_admin,
    is_active
  )
  values (
    v_username,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    false,
    true
  );

  return 'User "' || v_username || '" created successfully.';
exception
  when unique_violation then
    raise exception 'That username already exists.';
end;
$_$;


ALTER FUNCTION "public"."mecardee_add_user"("p_session_token" "uuid", "p_username" "text", "p_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_delete_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_delete_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_delete_work"("p_session_token" "uuid", "p_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_delete_work"("p_session_token" "uuid", "p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_delete_work_secure"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_delete_work_secure"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_list_deleted_transactions"("p_session_token" "uuid") RETURNS TABLE("id" "uuid", "original_transaction_id" "uuid", "original_sort_order" integer, "txn_date" "date", "txn_type" "text", "description" "text", "category_id" "text", "category_name" "text", "amount" numeric, "notes" "text", "source_key" "text", "work_id" "uuid", "shareholder_id" "uuid", "shareholder_name" "text", "paid_by" "uuid", "paid_by_name" "text", "deleted_by" "uuid", "deleted_by_username" "text", "deleted_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_list_deleted_transactions"("p_session_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_save_category"("p_session_token" "uuid", "p_id" "text", "p_name" "text", "p_icon" "text", "p_budget" numeric, "p_completion" integer, "p_sort_order" integer, "p_is_active" boolean) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_save_category"("p_session_token" "uuid", "p_id" "text", "p_name" "text", "p_icon" "text", "p_budget" numeric, "p_completion" integer, "p_sort_order" integer, "p_is_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_save_project"("p_session_token" "uuid", "p_name" "text", "p_location" "text", "p_opening_date" "date") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_save_project"("p_session_token" "uuid", "p_name" "text", "p_location" "text", "p_opening_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_save_shareholder"("p_session_token" "uuid", "p_id" "uuid", "p_name" "text", "p_amount" numeric, "p_sort_order" integer) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_save_shareholder"("p_session_token" "uuid", "p_id" "uuid", "p_name" "text", "p_amount" numeric, "p_sort_order" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_notes" "text", "p_sort_order" integer) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_notes" "text", "p_sort_order" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_paid_by" "uuid", "p_notes" "text", "p_sort_order" integer) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_paid_by" "uuid", "p_notes" "text", "p_sort_order" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_update_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_amount" numeric, "p_notes" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_update_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_amount" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_update_transaction_v2"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_amount" numeric, "p_notes" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_update_transaction_v2"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_amount" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_admin_update_transaction_v3"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_paid_by" "uuid", "p_amount" numeric, "p_notes" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_admin_update_transaction_v3"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_paid_by" "uuid", "p_amount" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_change_password"("p_session_token" "uuid", "p_current_password" "text", "p_new_password" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user public.mecardee_users%rowtype;
begin
  select u.*
  into v_user
  from public.mecardee_user_sessions s
  join public.mecardee_users u on u.id = s.user_id
  where s.token = p_session_token
    and s.expires_at > now()
    and u.is_active = true
  limit 1;

  if v_user.id is null then
    raise exception 'Your login session has expired. Sign in again.';
  end if;

  if v_user.password_hash <> extensions.crypt(p_current_password, v_user.password_hash) then
    raise exception 'The current password is incorrect.';
  end if;

  if length(coalesce(p_new_password, '')) < 4 then
    raise exception 'The new password must contain at least 4 characters.';
  end if;

  update public.mecardee_users
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf'))
  where id = v_user.id;

  return 'Password changed successfully.';
end;
$$;


ALTER FUNCTION "public"."mecardee_change_password"("p_session_token" "uuid", "p_current_password" "text", "p_new_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_is_named_partner"("p_shareholder_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.mecardee_shareholders shareholder
    where shareholder.id = p_shareholder_id
      and lower(trim(shareholder.name)) in ('delvin', 'dantees', 'dennis')
  );
$$;


ALTER FUNCTION "public"."mecardee_is_named_partner"("p_shareholder_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_login"("p_username" "text", "p_password" "text") RETURNS TABLE("session_token" "uuid", "username" "text", "is_admin" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user public.mecardee_users%rowtype;
  v_token uuid;
begin
  delete from public.mecardee_user_sessions
  where expires_at <= now();

  select u.*
  into v_user
  from public.mecardee_users u
  where u.username = lower(trim(p_username))
    and u.is_active = true
    and u.password_hash = extensions.crypt(p_password, u.password_hash)
  limit 1;

  if v_user.id is null then
    return;
  end if;

  v_token := extensions.gen_random_uuid();

  insert into public.mecardee_user_sessions (
    token,
    user_id,
    expires_at
  )
  values (
    v_token,
    v_user.id,
    now() + interval '12 hours'
  );

  return query
  select v_token, v_user.username, v_user.is_admin;
end;
$$;


ALTER FUNCTION "public"."mecardee_login"("p_username" "text", "p_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_logout"("p_session_token" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  delete from public.mecardee_user_sessions
  where token = p_session_token;
$$;


ALTER FUNCTION "public"."mecardee_logout"("p_session_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_require_admin"("p_session_token" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_require_admin"("p_session_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_require_admin_password"("p_session_token" "uuid", "p_admin_password" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mecardee_require_admin_password"("p_session_token" "uuid", "p_admin_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mecardee_session_info"("p_session_token" "uuid") RETURNS TABLE("username" "text", "is_admin" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select u.username, u.is_admin
  from public.mecardee_user_sessions s
  join public.mecardee_users u on u.id = s.user_id
  where s.token = p_session_token
    and s.expires_at > now()
    and u.is_active = true
  limit 1;
$$;


ALTER FUNCTION "public"."mecardee_session_info"("p_session_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_mecardee_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_mecardee_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."mecardee_categories" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "icon" "text" DEFAULT '•'::"text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "budget" numeric(14,2) DEFAULT 0 NOT NULL,
    "completion" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "mecardee_categories_budget_check" CHECK (("budget" >= (0)::numeric)),
    CONSTRAINT "mecardee_categories_completion_check" CHECK ((("completion" >= 0) AND ("completion" <= 100)))
);


ALTER TABLE "public"."mecardee_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_deleted_transactions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "original_transaction_id" "uuid" NOT NULL,
    "original_sort_order" integer DEFAULT 0 NOT NULL,
    "txn_date" "date" NOT NULL,
    "txn_type" "text" NOT NULL,
    "description" "text" NOT NULL,
    "category_id" "text",
    "category_name" "text",
    "amount" numeric(14,2) NOT NULL,
    "notes" "text" DEFAULT ''::"text" NOT NULL,
    "source_key" "text",
    "work_id" "uuid",
    "shareholder_id" "uuid",
    "shareholder_name" "text",
    "deleted_by" "uuid",
    "deleted_by_username" "text" DEFAULT 'delvin'::"text" NOT NULL,
    "deleted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "paid_by" "uuid",
    "paid_by_name" "text",
    CONSTRAINT "mecardee_deleted_transactions_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "mecardee_deleted_transactions_txn_type_check" CHECK (("txn_type" = ANY (ARRAY['Expense'::"text", 'Credit'::"text"])))
);


ALTER TABLE "public"."mecardee_deleted_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_project" (
    "id" smallint DEFAULT 1 NOT NULL,
    "name" "text" DEFAULT 'Mecardee Car Wash'::"text" NOT NULL,
    "location" "text" DEFAULT 'Kerala, India'::"text" NOT NULL,
    "opening_date" "date" DEFAULT (CURRENT_DATE + 100) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "total_budget" numeric(14,2) DEFAULT 0 NOT NULL,
    "phase_budgets" "jsonb" DEFAULT '{"site": 0, "brand": 0, "water": 0, "launch": 0, "equipment": 0, "electrical": 0}'::"jsonb" NOT NULL,
    CONSTRAINT "mecardee_project_id_check" CHECK (("id" = 1)),
    CONSTRAINT "mecardee_project_total_budget_check" CHECK (("total_budget" >= (0)::numeric))
);


ALTER TABLE "public"."mecardee_project" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_shareholders" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "mecardee_shareholders_amount_check" CHECK (("amount" >= (0)::numeric))
);


ALTER TABLE "public"."mecardee_shareholders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_tasks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "phase" "text" NOT NULL,
    "owner" "text" DEFAULT ''::"text" NOT NULL,
    "deadline" "date" NOT NULL,
    "progress" integer DEFAULT 0 NOT NULL,
    "notes" "text" DEFAULT ''::"text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expected_cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "actual_cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "work_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "is_completed" boolean DEFAULT false NOT NULL,
    "entry_type" "text" DEFAULT 'Work'::"text" NOT NULL,
    "amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "credit_shareholder_id" "uuid",
    "paid_by" "uuid",
    CONSTRAINT "mecardee_task_expense_paid_by_required" CHECK ((("entry_type" <> 'Expense'::"text") OR ("paid_by" IS NOT NULL))),
    CONSTRAINT "mecardee_tasks_actual_cost_check" CHECK (("actual_cost" >= (0)::numeric)),
    CONSTRAINT "mecardee_tasks_entry_type_check" CHECK (("entry_type" = ANY (ARRAY['Work'::"text", 'Expense'::"text", 'Credit'::"text"]))),
    CONSTRAINT "mecardee_tasks_expected_cost_check" CHECK (("expected_cost" >= (0)::numeric)),
    CONSTRAINT "mecardee_tasks_progress_check" CHECK ((("progress" >= 0) AND ("progress" <= 100))),
    CONSTRAINT "mecardee_tasks_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 180)))
);


ALTER TABLE "public"."mecardee_tasks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_transactions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "txn_date" "date" NOT NULL,
    "txn_type" "text" NOT NULL,
    "description" "text" NOT NULL,
    "category_id" "text",
    "amount" numeric(14,2) NOT NULL,
    "notes" "text" DEFAULT ''::"text" NOT NULL,
    "source_key" "text",
    "work_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "shareholder_id" "uuid",
    "paid_by" "uuid",
    CONSTRAINT "mecardee_expense_category_required" CHECK ((("txn_type" = 'Credit'::"text") OR ("category_id" IS NOT NULL))),
    CONSTRAINT "mecardee_expense_paid_by_required" CHECK ((("txn_type" <> 'Expense'::"text") OR ("paid_by" IS NOT NULL))),
    CONSTRAINT "mecardee_transactions_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "mecardee_transactions_description_check" CHECK ((("char_length"("description") >= 1) AND ("char_length"("description") <= 240))),
    CONSTRAINT "mecardee_transactions_txn_type_check" CHECK (("txn_type" = ANY (ARRAY['Expense'::"text", 'Credit'::"text"])))
);


ALTER TABLE "public"."mecardee_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_user_sessions" (
    "token" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '12:00:00'::interval) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mecardee_user_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mecardee_users" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "username" "text" NOT NULL,
    "password_hash" "text" NOT NULL,
    "is_admin" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "mecardee_username_format" CHECK ((("username" = "lower"("username")) AND ("username" ~ '^[a-z0-9._-]{3,40}$'::"text")))
);


ALTER TABLE "public"."mecardee_users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."mecardee_categories"
    ADD CONSTRAINT "mecardee_categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."mecardee_categories"
    ADD CONSTRAINT "mecardee_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_deleted_transactions"
    ADD CONSTRAINT "mecardee_deleted_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_project"
    ADD CONSTRAINT "mecardee_project_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_shareholders"
    ADD CONSTRAINT "mecardee_shareholders_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."mecardee_shareholders"
    ADD CONSTRAINT "mecardee_shareholders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_tasks"
    ADD CONSTRAINT "mecardee_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_source_key_key" UNIQUE ("source_key");



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_work_id_key" UNIQUE ("work_id");



ALTER TABLE ONLY "public"."mecardee_user_sessions"
    ADD CONSTRAINT "mecardee_user_sessions_pkey" PRIMARY KEY ("token");



ALTER TABLE ONLY "public"."mecardee_users"
    ADD CONSTRAINT "mecardee_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mecardee_users"
    ADD CONSTRAINT "mecardee_users_username_key" UNIQUE ("username");



CREATE INDEX "mecardee_deleted_transactions_deleted_at_idx" ON "public"."mecardee_deleted_transactions" USING "btree" ("deleted_at" DESC);



CREATE INDEX "mecardee_tasks_paid_by_idx" ON "public"."mecardee_tasks" USING "btree" ("paid_by") WHERE ("entry_type" = 'Expense'::"text");



CREATE INDEX "mecardee_transactions_paid_by_idx" ON "public"."mecardee_transactions" USING "btree" ("paid_by") WHERE ("txn_type" = 'Expense'::"text");



CREATE OR REPLACE TRIGGER "mecardee_categories_updated_at" BEFORE UPDATE ON "public"."mecardee_categories" FOR EACH ROW EXECUTE FUNCTION "public"."set_mecardee_updated_at"();



CREATE OR REPLACE TRIGGER "mecardee_project_updated_at" BEFORE UPDATE ON "public"."mecardee_project" FOR EACH ROW EXECUTE FUNCTION "public"."set_mecardee_updated_at"();



CREATE OR REPLACE TRIGGER "mecardee_shareholders_updated_at" BEFORE UPDATE ON "public"."mecardee_shareholders" FOR EACH ROW EXECUTE FUNCTION "public"."set_mecardee_updated_at"();



CREATE OR REPLACE TRIGGER "mecardee_tasks_updated_at" BEFORE UPDATE ON "public"."mecardee_tasks" FOR EACH ROW EXECUTE FUNCTION "public"."set_mecardee_updated_at"();



CREATE OR REPLACE TRIGGER "mecardee_transactions_updated_at" BEFORE UPDATE ON "public"."mecardee_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."set_mecardee_updated_at"();



ALTER TABLE ONLY "public"."mecardee_deleted_transactions"
    ADD CONSTRAINT "mecardee_deleted_transactions_paid_by_fk" FOREIGN KEY ("paid_by") REFERENCES "public"."mecardee_shareholders"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mecardee_tasks"
    ADD CONSTRAINT "mecardee_tasks_category_fk" FOREIGN KEY ("phase") REFERENCES "public"."mecardee_categories"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."mecardee_tasks"
    ADD CONSTRAINT "mecardee_tasks_credit_shareholder_fk" FOREIGN KEY ("credit_shareholder_id") REFERENCES "public"."mecardee_shareholders"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mecardee_tasks"
    ADD CONSTRAINT "mecardee_tasks_paid_by_fk" FOREIGN KEY ("paid_by") REFERENCES "public"."mecardee_shareholders"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."mecardee_categories"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_paid_by_fk" FOREIGN KEY ("paid_by") REFERENCES "public"."mecardee_shareholders"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_shareholder_fk" FOREIGN KEY ("shareholder_id") REFERENCES "public"."mecardee_shareholders"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mecardee_transactions"
    ADD CONSTRAINT "mecardee_transactions_work_id_fkey" FOREIGN KEY ("work_id") REFERENCES "public"."mecardee_tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mecardee_user_sessions"
    ADD CONSTRAINT "mecardee_user_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."mecardee_users"("id") ON DELETE CASCADE;



CREATE POLICY "Public can read Mecardee categories" ON "public"."mecardee_categories" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Public can read Mecardee project" ON "public"."mecardee_project" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Public can read Mecardee shareholders" ON "public"."mecardee_shareholders" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Public can read Mecardee tasks" ON "public"."mecardee_tasks" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Public can read Mecardee transactions" ON "public"."mecardee_transactions" FOR SELECT TO "authenticated", "anon" USING (true);



ALTER TABLE "public"."mecardee_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_deleted_transactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_project" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_shareholders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_transactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_user_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mecardee_users" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_add_user"("p_session_token" "uuid", "p_username" "text", "p_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_add_user"("p_session_token" "uuid", "p_username" "text", "p_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_add_user"("p_session_token" "uuid", "p_username" "text", "p_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_add_user"("p_session_token" "uuid", "p_username" "text", "p_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_delete_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_delete_work"("p_session_token" "uuid", "p_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_work"("p_session_token" "uuid", "p_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_delete_work_secure"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_work_secure"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_work_secure"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_delete_work_secure"("p_session_token" "uuid", "p_id" "uuid", "p_admin_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_list_deleted_transactions"("p_session_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_list_deleted_transactions"("p_session_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_list_deleted_transactions"("p_session_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_list_deleted_transactions"("p_session_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_save_category"("p_session_token" "uuid", "p_id" "text", "p_name" "text", "p_icon" "text", "p_budget" numeric, "p_completion" integer, "p_sort_order" integer, "p_is_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_category"("p_session_token" "uuid", "p_id" "text", "p_name" "text", "p_icon" "text", "p_budget" numeric, "p_completion" integer, "p_sort_order" integer, "p_is_active" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_category"("p_session_token" "uuid", "p_id" "text", "p_name" "text", "p_icon" "text", "p_budget" numeric, "p_completion" integer, "p_sort_order" integer, "p_is_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_category"("p_session_token" "uuid", "p_id" "text", "p_name" "text", "p_icon" "text", "p_budget" numeric, "p_completion" integer, "p_sort_order" integer, "p_is_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_save_project"("p_session_token" "uuid", "p_name" "text", "p_location" "text", "p_opening_date" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_project"("p_session_token" "uuid", "p_name" "text", "p_location" "text", "p_opening_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_project"("p_session_token" "uuid", "p_name" "text", "p_location" "text", "p_opening_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_project"("p_session_token" "uuid", "p_name" "text", "p_location" "text", "p_opening_date" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_save_shareholder"("p_session_token" "uuid", "p_id" "uuid", "p_name" "text", "p_amount" numeric, "p_sort_order" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_shareholder"("p_session_token" "uuid", "p_id" "uuid", "p_name" "text", "p_amount" numeric, "p_sort_order" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_shareholder"("p_session_token" "uuid", "p_id" "uuid", "p_name" "text", "p_amount" numeric, "p_sort_order" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_shareholder"("p_session_token" "uuid", "p_id" "uuid", "p_name" "text", "p_amount" numeric, "p_sort_order" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_notes" "text", "p_sort_order" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_notes" "text", "p_sort_order" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_paid_by" "uuid", "p_notes" "text", "p_sort_order" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_paid_by" "uuid", "p_notes" "text", "p_sort_order" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_paid_by" "uuid", "p_notes" "text", "p_sort_order" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_save_work"("p_session_token" "uuid", "p_id" "uuid", "p_title" "text", "p_category_id" "text", "p_owner" "text", "p_work_date" "date", "p_deadline" "date", "p_is_completed" boolean, "p_entry_type" "text", "p_amount" numeric, "p_credit_shareholder_id" "uuid", "p_paid_by" "uuid", "p_notes" "text", "p_sort_order" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_update_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_amount" numeric, "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_amount" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_amount" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_amount" numeric, "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_update_transaction_v2"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_amount" numeric, "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction_v2"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_amount" numeric, "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_admin_update_transaction_v3"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_paid_by" "uuid", "p_amount" numeric, "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction_v3"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_paid_by" "uuid", "p_amount" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction_v3"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_paid_by" "uuid", "p_amount" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_admin_update_transaction_v3"("p_session_token" "uuid", "p_id" "uuid", "p_txn_date" "date", "p_description" "text", "p_category_id" "text", "p_shareholder_id" "uuid", "p_paid_by" "uuid", "p_amount" numeric, "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_change_password"("p_session_token" "uuid", "p_current_password" "text", "p_new_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_change_password"("p_session_token" "uuid", "p_current_password" "text", "p_new_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_change_password"("p_session_token" "uuid", "p_current_password" "text", "p_new_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_change_password"("p_session_token" "uuid", "p_current_password" "text", "p_new_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_is_named_partner"("p_shareholder_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_is_named_partner"("p_shareholder_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_is_named_partner"("p_shareholder_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_is_named_partner"("p_shareholder_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_login"("p_username" "text", "p_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_login"("p_username" "text", "p_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_login"("p_username" "text", "p_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_login"("p_username" "text", "p_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_logout"("p_session_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_logout"("p_session_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_logout"("p_session_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_logout"("p_session_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_require_admin"("p_session_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_require_admin"("p_session_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_require_admin"("p_session_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_require_admin"("p_session_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_require_admin_password"("p_session_token" "uuid", "p_admin_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_require_admin_password"("p_session_token" "uuid", "p_admin_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_require_admin_password"("p_session_token" "uuid", "p_admin_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_require_admin_password"("p_session_token" "uuid", "p_admin_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mecardee_session_info"("p_session_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mecardee_session_info"("p_session_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mecardee_session_info"("p_session_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mecardee_session_info"("p_session_token" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_mecardee_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_mecardee_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_mecardee_updated_at"() TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."mecardee_categories" TO "service_role";



GRANT ALL ON TABLE "public"."mecardee_deleted_transactions" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_project" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_project" TO "authenticated";
GRANT ALL ON TABLE "public"."mecardee_project" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_shareholders" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_shareholders" TO "authenticated";
GRANT ALL ON TABLE "public"."mecardee_shareholders" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_tasks" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."mecardee_tasks" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_transactions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mecardee_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."mecardee_transactions" TO "service_role";



GRANT ALL ON TABLE "public"."mecardee_user_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."mecardee_users" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







