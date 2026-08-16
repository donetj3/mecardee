-- Correct the shareholder spelling while preserving record IDs and balances.

begin;

update public.mecardee_shareholders
set name = 'Dennies'
where lower(trim(name)) = 'dennis';

update public.mecardee_tasks
set
  title = regexp_replace(title, '\mdennis\M', 'Dennies', 'gi'),
  owner = regexp_replace(owner, '\mdennis\M', 'Dennies', 'gi'),
  notes = regexp_replace(notes, '\mdennis\M', 'Dennies', 'gi')
where title ~* '\mdennis\M'
   or owner ~* '\mdennis\M'
   or notes ~* '\mdennis\M';

update public.mecardee_transactions
set
  description = regexp_replace(description, '\mdennis\M', 'Dennies', 'gi'),
  notes = regexp_replace(notes, '\mdennis\M', 'Dennies', 'gi')
where description ~* '\mdennis\M'
   or notes ~* '\mdennis\M';

update public.mecardee_deleted_transactions
set
  description = regexp_replace(description, '\mdennis\M', 'Dennies', 'gi'),
  notes = regexp_replace(notes, '\mdennis\M', 'Dennies', 'gi'),
  shareholder_name = regexp_replace(shareholder_name, '\mdennis\M', 'Dennies', 'gi')
where description ~* '\mdennis\M'
   or notes ~* '\mdennis\M'
   or shareholder_name ~* '\mdennis\M';

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
      and lower(trim(shareholder.name)) in ('delvin', 'dantees', 'dennies')
  );
$$;

-- Refresh user-facing validation messages in functions already installed by
-- earlier migrations. This keeps an existing database consistent with a fresh
-- install without changing function signatures or permissions.
do $rename_function_messages$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select function_row.oid
    from pg_catalog.pg_proc function_row
    join pg_catalog.pg_namespace namespace_row
      on namespace_row.oid = function_row.pronamespace
    where namespace_row.nspname = 'public'
      and function_row.prokind = 'f'
      and pg_catalog.pg_get_functiondef(function_row.oid) like '%Dennis%'
  loop
    v_definition := pg_catalog.pg_get_functiondef(v_function.oid);
    execute replace(v_definition, 'Dennis', 'Dennies');
  end loop;
end;
$rename_function_messages$;

commit;
