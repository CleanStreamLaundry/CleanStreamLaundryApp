-- Synthetic pre-Cortina dependencies. Cortina tables, constraints and functions
-- are loaded from the actual migrations by the runner, not duplicated here.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create schema extensions;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create table auth.users(id uuid primary key);
create type public."Roles" as enum ('Customer', 'Admin', 'Owner');
create table public.profiles(id uuid primary key, roles public."Roles");
create table public."Locations"(id bigint primary key);
create table public."Location_to_Admin"(location_id bigint, user_id uuid);
create table public."Machines"(
  id bigint primary key, "Name" text, "Machine_type" text, "Status" text default 'Idle',
  "Location_ID" bigint references public."Locations", "Weight_kg" bigint, "Price" double precision,
  is_out_of_service boolean not null default false
);
create table public.wallet_redemptions(
  id bigint primary key, status text, wallet_account_id uuid,
  amount_cents integer, paid_amount_cents integer, promo_amount_cents integer, machine_id bigint
);
