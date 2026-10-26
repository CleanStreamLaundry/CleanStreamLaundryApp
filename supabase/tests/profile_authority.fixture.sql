-- Synthetic prerequisites only, not a deployed-schema snapshot.
create role anon;
create role authenticated;
create role service_role bypassrls;
create role supabase_auth_admin;
create schema auth;
create schema extensions;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create type public."Roles" as enum ('User', 'Admin', 'Owner');
create table auth.users(id uuid primary key, email text);
create table public.profiles (
  id uuid primary key references auth.users,
  full_name text,
  email text,
  roles public."Roles" default 'User',
  balance double precision default '0'::double precision,
  reward_tracker double precision default '0'::double precision,
  notif_lead_time integer default 5,
  refund_attempts integer default 0
);
create table public."Machines"(id bigint primary key, "Location_ID" bigint);
create table public."Location_to_Admin"(user_id uuid, location_id bigint);
create table public.transactions(id bigint primary key, user_id uuid, amount numeric, type text);
create table public."Refunds"(refund_id bigint primary key, user_id uuid, transaction_id bigint, amount numeric);
create function public.handle_new_user() returns trigger language plpgsql as $$begin return new; end;$$;
create function public.sync_user_full_name() returns trigger language plpgsql as $$begin return new; end;$$;
create function public.increment_loyalty_balance(uuid, numeric) returns void language sql as $$select;$$;

grant usage on schema public, auth to anon, authenticated, service_role, supabase_auth_admin;
grant select, insert, update on public.profiles to public, anon, authenticated;
grant insert (roles, balance, reward_tracker), update (roles, balance, reward_tracker)
  on public.profiles to public, anon, authenticated;
grant all on all tables in schema public, auth to service_role;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

alter table public.profiles enable row level security;
create policy profile_self_update on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);
create policy profile_self_insert on public.profiles for insert
  with check (auth.uid() = id);

grant select, insert on public.transactions to authenticated;
alter table public.transactions enable row level security;
create policy transaction_self_select on public.transactions for select using (auth.uid() = user_id);
create policy transaction_self_insert on public.transactions for insert with check (auth.uid() = user_id);

-- Representative trusted Auth/server entrypoint, deliberately service-only.
create function public.test_server_profile_write(target uuid, new_role public."Roles", new_balance double precision, new_reward double precision)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, roles, balance, reward_tracker)
  values(target, new_role, new_balance, new_reward)
  on conflict(id) do update set roles=excluded.roles, balance=excluded.balance, reward_tracker=excluded.reward_tracker;
end;
$$;
revoke all on function public.test_server_profile_write(uuid, public."Roles", double precision, double precision) from public, anon, authenticated;
grant execute on function public.test_server_profile_write(uuid, public."Roles", double precision, double precision) to service_role, supabase_auth_admin;
