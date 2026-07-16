-- Simple Mecardee users with hashed passwords and short-lived session tokens.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.mecardee_users (
  id uuid primary key default extensions.gen_random_uuid(),
  username text not null unique,
  password_hash text not null,
  is_admin boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint mecardee_username_format
    check (username = lower(username) and username ~ '^[a-z0-9._-]{3,40}$')
);

create table if not exists public.mecardee_user_sessions (
  token uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.mecardee_users(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '12 hours'),
  created_at timestamptz not null default now()
);

alter table public.mecardee_users enable row level security;
alter table public.mecardee_user_sessions enable row level security;

revoke all on public.mecardee_users from anon, authenticated;
revoke all on public.mecardee_user_sessions from anon, authenticated;

insert into public.mecardee_users (
  username,
  password_hash,
  is_admin,
  is_active
)
values (
  'delvin',
  extensions.crypt('admin@2', extensions.gen_salt('bf')),
  true,
  true
)
on conflict (username)
do update set
  is_admin = true,
  is_active = true;

create or replace function public.mecardee_login(
  p_username text,
  p_password text
)
returns table (
  session_token uuid,
  username text,
  is_admin boolean
)
language plpgsql
security definer
set search_path = ''
as $$
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

create or replace function public.mecardee_session_info(
  p_session_token uuid
)
returns table (
  username text,
  is_admin boolean
)
language sql
security definer
set search_path = ''
as $$
  select u.username, u.is_admin
  from public.mecardee_user_sessions s
  join public.mecardee_users u on u.id = s.user_id
  where s.token = p_session_token
    and s.expires_at > now()
    and u.is_active = true
  limit 1;
$$;

create or replace function public.mecardee_add_user(
  p_session_token uuid,
  p_username text,
  p_password text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

create or replace function public.mecardee_change_password(
  p_session_token uuid,
  p_current_password text,
  p_new_password text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
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

create or replace function public.mecardee_logout(
  p_session_token uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.mecardee_user_sessions
  where token = p_session_token;
$$;

revoke all on function public.mecardee_login(text, text) from public;
revoke all on function public.mecardee_session_info(uuid) from public;
revoke all on function public.mecardee_add_user(uuid, text, text) from public;
revoke all on function public.mecardee_change_password(uuid, text, text) from public;
revoke all on function public.mecardee_logout(uuid) from public;

grant execute on function public.mecardee_login(text, text) to anon, authenticated;
grant execute on function public.mecardee_session_info(uuid) to anon, authenticated;
grant execute on function public.mecardee_add_user(uuid, text, text) to anon, authenticated;
grant execute on function public.mecardee_change_password(uuid, text, text) to anon, authenticated;
grant execute on function public.mecardee_logout(uuid) to anon, authenticated;