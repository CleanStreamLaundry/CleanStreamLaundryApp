-- Synthetic extension of the reviewed policy fixture, never production schema.
-- Types/nullability/ownership below reflect Composer's catalog-only readback.
create type auth.aal_level as enum ('aal1', 'aal2', 'aal3');
create type auth.factor_type as enum ('totp', 'webauthn', 'phone', 'recovery_code');
create type auth.factor_status as enum ('unverified', 'verified');
create table auth.sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  factor_id uuid,
  aal auth.aal_level,
  not_after timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  refreshed_at timestamp without time zone,
  fixture_secret text default 'synthetic-only-session-secret'
);
create table auth.mfa_factors (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  factor_type auth.factor_type not null,
  status auth.factor_status not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  fixture_secret text default 'synthetic-only-factor-secret'
);
create index on auth.sessions(user_id);
create index on auth.mfa_factors(user_id);
alter table auth.users owner to supabase_auth_admin;
alter table auth.sessions owner to supabase_auth_admin;
alter table auth.mfa_factors owner to supabase_auth_admin;
alter table auth.users enable row level security;
alter table auth.sessions enable row level security;
alter table auth.mfa_factors enable row level security;

create or replace function auth.jwt() returns jsonb language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb;
$$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
    auth.jwt()->>'sub')::uuid;
$$;

-- A non-superuser lookup owner proves the evaluator needs no factor/session
-- secrets or other profile columns. BYPASSRLS mirrors the production definer.
create role admission_lookup_fixture nologin bypassrls;
grant usage on schema auth, public to admission_lookup_fixture;
grant select(id,is_anonymous,deleted_at,banned_until,email_confirmed_at)
  on auth.users to admission_lookup_fixture;
grant select(id,user_id,aal,factor_id,not_after)
  on auth.sessions to admission_lookup_fixture;
grant select(id,user_id,factor_type,status)
  on auth.mfa_factors to admission_lookup_fixture;
grant select(id,roles) on public.profiles to admission_lookup_fixture;
grant execute on function auth.uid(), auth.jwt() to admission_lookup_fixture;
