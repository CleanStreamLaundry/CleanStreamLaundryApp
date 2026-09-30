-- Synthetic fixture only. Not a production baseline or deployable migration.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role supabase_auth_admin nologin;
create role policy_no_access nologin;
create schema auth;
grant usage on schema auth, public to anon, authenticated, service_role, supabase_auth_admin;
grant usage on schema public to policy_no_access;
alter default privileges in schema public grant execute on functions
  to anon, authenticated, service_role, supabase_auth_admin;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table auth.users (
  id uuid primary key,
  email_confirmed_at timestamptz,
  is_anonymous boolean not null default false,
  banned_until timestamptz,
  deleted_at timestamptz,
  raw_user_meta_data jsonb not null default '{}',
  raw_app_meta_data jsonb not null default '{}'
);
create type public."Roles" as enum ('User', 'Admin', 'Owner');
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  balance double precision default 0,
  created_at timestamptz default now(),
  refund_attempts integer default 0,
  notif_lead_time integer default 0,
  reward_tracker double precision default 0,
  roles public."Roles" default 'User',
  email text
);
alter table public.profiles enable row level security;
create policy profile_select on public.profiles for select to authenticated using (auth.uid() = id);
create policy profile_insert on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy profile_update on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
-- Exercise inherited PUBLIC/table-wide privileges, not column revocation alone.
grant select, insert, update on public.profiles to public, anon, authenticated;
grant select, insert, update on public.profiles to service_role;

-- Reported live signup body accepts a name, never acceptance from metadata.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();
