-- GENERATED: exact reviewed DEVELOPMENT A/B installation, no backfill.
-- Target: dnuuhupoxjtwqzaqylvb. Composer executes only after rehearsal/review.
-- See sources.sha256 and scripts/activation-ab.test.mjs for byte provenance.
BEGIN;

-- SOURCE: supabase/migrations/20260929234955_loyalty_policy_acceptance.sql
-- REVIEW-ONLY LOCAL CANDIDATE. DO NOT APPLY TO PRODUCTION.
-- Final campaign policy/version approval and lifecycle/MFA gate integration
-- are release dependencies. The draft below is NOT approved legal policy.
-- No backfill, automatic consent, newsletter enrollment, or lifecycle changes.

alter table public.profiles
  add column loyalty_policy_version text,
  add column loyalty_policy_accepted_at timestamptz,
  add constraint profiles_loyalty_policy_acceptance_pair check (
    (loyalty_policy_version is null and loyalty_policy_accepted_at is null)
    or (loyalty_policy_version is not null and loyalty_policy_version <> ''
      and loyalty_policy_accepted_at is not null
      and isfinite(loyalty_policy_accepted_at))
  );

-- Table-level privileges override column revocations. Preserve effective
-- existing-column writes, including server roles inheriting PUBLIC grants.
do $$
declare
  saved_grants jsonb;
  saved_grant jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb) into saved_grants
  from (
    select r.rolname as grantee, p.privilege,
      string_agg(format('%I', a.attname), ', ' order by a.attnum) as columns
    from pg_catalog.pg_roles r
    cross join (values ('INSERT'), ('UPDATE')) as p(privilege)
    join pg_catalog.pg_attribute a on a.attrelid = 'public.profiles'::regclass
      and a.attnum > 0 and not a.attisdropped
    where r.rolname in ('anon', 'authenticated', 'service_role', 'supabase_auth_admin')
      and a.attname not in ('loyalty_policy_version', 'loyalty_policy_accepted_at')
      and has_column_privilege(r.oid, a.attrelid, a.attnum, p.privilege)
    group by r.rolname, p.privilege
  ) g;

  revoke insert, update on public.profiles from public, anon, authenticated;
  revoke insert (loyalty_policy_version, loyalty_policy_accepted_at),
    update (loyalty_policy_version, loyalty_policy_accepted_at)
    on public.profiles from public, anon, authenticated;

  for saved_grant in select value from jsonb_array_elements(saved_grants) loop
    execute format('grant %s (%s) on public.profiles to %I',
      saved_grant->>'privilege', saved_grant->>'columns', saved_grant->>'grantee');
  end loop;

  if exists (
    select 1
    from (values ('anon'), ('authenticated')) r(grantee)
    cross join (values ('INSERT'), ('UPDATE')) p(privilege)
    cross join (values ('loyalty_policy_version'), ('loyalty_policy_accepted_at')) c(column_name)
    where has_column_privilege(r.grantee, 'public.profiles', c.column_name, p.privilege)
  ) then
    raise exception 'Inherited policy acceptance write privileges require review'
      using errcode = '42501';
  end if;
end;
$$;

-- Separate from the profile authority guard: neither migration replaces the
-- other's trigger. Trusted definer RPCs execute as their database owner.
create function public.guard_profile_policy_acceptance()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.loyalty_policy_version is not null
        or new.loyalty_policy_accepted_at is not null then
        raise exception 'Policy acceptance requires the server RPC' using errcode = '42501';
      end if;
    elsif new.loyalty_policy_version is distinct from old.loyalty_policy_version
      or new.loyalty_policy_accepted_at is distinct from old.loyalty_policy_accepted_at then
      raise exception 'Policy acceptance requires the server RPC' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_policy_acceptance_guard
before insert or update on public.profiles
for each row execute function public.guard_profile_policy_acceptance();

revoke all on function public.guard_profile_policy_acceptance()
  from public, anon, authenticated, service_role, supabase_auth_admin;

create function public.get_loyalty_policy_descriptor()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  -- Immutable REVIEW-ONLY draft, rendered by server-fed clients. Paragraphs
  -- use exactly two LF characters; UTF-8, no trailing newline.
  required_version constant text := 'review-only-loyalty-d08c2c970e4fb2f7';
  policy_sha256 constant text := 'd08c2c970e4fb2f7255034ee643f6148454f7aca3c09e595c5eb94d10106e748';
  policy_text constant text := $policy$Loyalty Card loads are prepaid Clean Stream Laundry credit for eligible services. They are not a bank account and do not earn interest. Refunds are available only under the voluntary wallet-load policy below or as required by law.

Promotional bonus credits have no cash value and may be subject to separate terms. Promotional credit is tracked separately from paid credit and is applied before paid credit when a wallet payment is used.

You may request a voluntary refund of the full paid principal of a wallet load if the server receives your request no later than 48 hours after the payment succeeded, including exactly 48 hours. Eligibility uses server-recorded request and successful-payment times. Any wallet spending after that load disqualifies it, including spending only promotional credit or a failed vend later reversed. Earlier wallet use does not disqualify a later load.

An Owner reviews timely requests and may complete that review after the 48-hour deadline. Approved refunds return the full paid principal to the original payment method; Clean Stream absorbs the original processing fees. No partial voluntary refunds or cash refunds of promotional credit are offered. Bonus credit and reward progress attributable to the refunded load are reversed.

These voluntary wallet-load conditions do not limit statutory rights or replace remedies for machine or payment failures.

A deletion request places your account in pending deletion and restricts ordinary app access. You may explicitly restore the original account and its wallet links after verifying ownership and completing any required multi-factor authentication, before the server-set deadline 30 days after the deletion request. Signing in alone does not restore the account. Restoration does not reset refund deadlines or resubscribe you to newsletters. At or after the deadline, restoration is unavailable even if cleanup has not occurred.

Post-deadline data retention and remaining-balance handling are not yet finalized in this draft. This draft does not represent automatic cleanup or balance forfeiture as active.$policy$;
begin
  return jsonb_build_object(
    'required_version', required_version, 'policy_text', policy_text,
    'policy_sha256', policy_sha256
  );
end;
$$;

revoke all on function public.get_loyalty_policy_descriptor()
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.get_loyalty_policy_descriptor() to anon, authenticated;

create function public.get_loyalty_policy_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  accepted_version text;
  accepted_at timestamptz;
  policy_descriptor jsonb;
begin
  if caller_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  -- Auth row before profile: serialize acceptance with Auth deletion, bans,
  -- and verification changes. User metadata is never an eligibility source.
  perform 1 from auth.users u
  where u.id = caller_id and u.is_anonymous is false
    and u.email_confirmed_at is not null and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp())
  for share;
  if not found then
    raise exception 'account_not_eligible' using errcode = '42501';
  end if;

  -- Pending deletion, session revocation, and required MFA are NOT implemented
  -- here. Lifecycle/MFA integration must gate both RPCs before production use.
  select p.loyalty_policy_version, p.loyalty_policy_accepted_at
    into accepted_version, accepted_at
  from public.profiles p where p.id = caller_id;
  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  policy_descriptor := public.get_loyalty_policy_descriptor();
  return policy_descriptor || jsonb_build_object(
    'accepted_version', accepted_version,
    'accepted_at', accepted_at,
    'acceptance_required', accepted_version is distinct from policy_descriptor->>'required_version'
      or accepted_at is null
  );
end;
$$;

create function public.accept_loyalty_policy(p_version text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  policy_status jsonb;
  accepted_version text;
  accepted_at timestamptz;
begin
  -- One source of required-version/text and verified identity checks.
  policy_status := public.get_loyalty_policy_status();
  if p_version is distinct from policy_status->>'required_version' then
    raise exception 'policy_version_mismatch' using errcode = '22023';
  end if;

  select p.loyalty_policy_version, p.loyalty_policy_accepted_at
    into accepted_version, accepted_at
  from public.profiles p where p.id = auth.uid()
  for no key update;
  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  if accepted_version is distinct from p_version or accepted_at is null then
    accepted_at := clock_timestamp();
    update public.profiles set loyalty_policy_version = p_version,
      loyalty_policy_accepted_at = accepted_at where id = auth.uid();
  end if;

  return policy_status || jsonb_build_object(
    'accepted_version', p_version, 'accepted_at', accepted_at,
    'acceptance_required', false
  );
end;
$$;

revoke all on function public.get_loyalty_policy_status(),
  public.accept_loyalty_policy(text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.get_loyalty_policy_status(),
  public.accept_loyalty_policy(text) to authenticated;



-- SOURCE: supabase/migrations/20260930005456_account_admission.sql
-- LOCAL FOUNDATION ONLY. No existing API/RLS enforcement or UI activation.
-- Production release requires profile authority, role legitimacy, hosted JWT/
-- timeout validation, approved policy, and lifecycle/enforcement integration.

create schema if not exists private;
grant usage on schema private to authenticated;

do $$
begin
  if has_schema_privilege('anon', 'private', 'CREATE')
    or has_schema_privilege('authenticated', 'private', 'CREATE') then
    raise exception 'Untrusted private schema CREATE privilege requires review'
      using errcode = '42501';
  end if;
  if to_regprocedure('public.get_loyalty_policy_status()') is null then
    raise exception 'Reviewed loyalty policy prerequisite is missing'
      using errcode = '55000';
  end if;
end;
$$;

create function private.current_account_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb;
  caller_id uuid;
  session_id uuid;
  jwt_aal text;
  current_aal text;
  session_factor_id uuid;
  session_not_after timestamptz;
  user_anonymous boolean;
  user_deleted_at timestamptz;
  user_banned_until timestamptz;
  user_email_confirmed_at timestamptz;
  caller_role text;
  has_totp boolean;
  unsupported_factor boolean;
  bound_totp boolean;
  result jsonb;
begin
  -- Claims are supplied by the JWT-validating Data API, never RPC parameters.
  -- The database checks binding/freshness, not cryptographic JWT signatures.
  begin
    claims := auth.jwt();
    caller_id := auth.uid();
    session_id := (claims->>'session_id')::uuid;
    jwt_aal := claims->>'aal';
    if caller_id is null or session_id is null
      or (claims->>'sub')::uuid is distinct from caller_id
      or claims->>'role' is distinct from 'authenticated'
      or jsonb_typeof(claims->'exp') is distinct from 'number'
      or (claims->>'exp')::numeric <= extract(epoch from statement_timestamp())
      or coalesce(jwt_aal, '') not in ('aal1', 'aal2') then
      raise exception 'session_invalid' using errcode = 'PT401';
    end if;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'session_invalid' using errcode = 'PT401';
  end;

  select s.aal::text, s.factor_id, s.not_after
    into current_aal, session_factor_id, session_not_after
  from auth.sessions s where s.id = session_id and s.user_id = caller_id;
  if not found or coalesce(current_aal, '') not in ('aal1', 'aal2')
    or session_not_after <= statement_timestamp() then
    raise exception 'session_invalid' using errcode = 'PT401';
  end if;

  select u.is_anonymous, u.deleted_at, u.banned_until, u.email_confirmed_at
    into user_anonymous, user_deleted_at, user_banned_until, user_email_confirmed_at
  from auth.users u where u.id = caller_id;
  if not found then
    raise exception 'session_invalid' using errcode = 'PT401';
  end if;

  result := jsonb_build_object(
    'subject_id', caller_id, 'account_access', 'restricted',
    'next_step', 'blocked', 'reason', 'account_restricted',
    'account_state', 'blocked', 'restore_until', null,
    'provisioning_allowed', false
  );
  if user_anonymous is not false or user_deleted_at is not null
    or user_banned_until > statement_timestamp() then
    return result;
  end if;

  -- Lifecycle is NOT implemented. Replace this branch in the same evaluator
  -- when server-owned deletion state exists; never infer recovery eligibility.
  result := result || jsonb_build_object(
    'account_state', 'legacy_active', 'provisioning_allowed', true, 'reason', null
  );
  if user_email_confirmed_at is null then
    return result || jsonb_build_object('next_step', 'verify_email');
  end if;

  select p.roles::text into caller_role from public.profiles p where p.id = caller_id;
  if not found then
    return result || jsonb_build_object('reason', 'profile_missing');
  end if;
  if coalesce(caller_role, '') not in ('User', 'Admin', 'Owner') then
    return result || jsonb_build_object('reason', 'role_unavailable');
  end if;

  select
    coalesce(bool_or(f.status::text = 'verified' and f.factor_type::text = 'totp'), false),
    coalesce(bool_or(coalesce(f.status::text, '') not in ('unverified', 'verified')
      or (f.status::text = 'verified' and f.factor_type::text is distinct from 'totp')), false),
    coalesce(bool_or(f.id = session_factor_id and f.status::text = 'verified'
      and f.factor_type::text = 'totp'), false)
    into has_totp, unsupported_factor, bound_totp
  from auth.mfa_factors f where f.user_id = caller_id;
  if unsupported_factor then
    return result || jsonb_build_object('reason', 'unsupported_factor');
  end if;
  if caller_role in ('Admin', 'Owner') and not has_totp then
    return result || jsonb_build_object('next_step', 'enroll_totp');
  end if;
  if has_totp and (jwt_aal <> 'aal2' or current_aal <> 'aal2' or not bound_totp) then
    return result || jsonb_build_object('next_step', 'challenge_totp');
  end if;
  return result || jsonb_build_object('account_access', 'eligible', 'next_step', 'home');
exception
  when sqlstate 'PT401' then raise;
  when others then
    raise exception 'admission_unavailable' using errcode = 'PT503';
end;
$$;

create function private.account_access_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_account_access()->>'account_access' = 'eligible', false);
$$;

create function public.get_admission_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  access_state jsonb;
  policy_status jsonb;
begin
  access_state := private.current_account_access();
  if access_state->>'account_access' = 'eligible' then
    policy_status := public.get_loyalty_policy_status();
    if jsonb_typeof(policy_status->'acceptance_required') is distinct from 'boolean' then
      raise exception 'admission_unavailable' using errcode = 'PT503';
    end if;
    -- Policy status may have waited on Auth. Recheck after that wait rather
    -- than returning admission based on an earlier eligibility read.
    access_state := private.current_account_access();
    if access_state->>'account_access' = 'eligible' then
      access_state := access_state || jsonb_build_object('next_step',
        case when (policy_status->>'acceptance_required')::boolean then 'review_terms' else 'home' end);
    end if;
  end if;
  return jsonb_build_object(
    'subject_id', access_state->'subject_id', 'account_access', access_state->'account_access',
    'next_step', access_state->'next_step', 'reason', access_state->'reason',
    'account_state', access_state->'account_state', 'restore_until', access_state->'restore_until'
  );
exception
  when sqlstate 'PT401' then raise;
  when others then
    raise exception 'admission_unavailable' using errcode = 'PT503';
end;
$$;

create function public.ensure_own_profile(p_full_name text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  access_state jsonb;
  caller_id uuid;
begin
  access_state := private.current_account_access();
  caller_id := (access_state->>'subject_id')::uuid;
  if access_state->>'provisioning_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  -- This standalone provisioning path takes Auth then profile, like terms.
  -- The reusable evaluator itself never locks rows or writes financial state.
  perform 1 from auth.users u where u.id = caller_id for share;
  access_state := private.current_account_access();
  if access_state->>'provisioning_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  insert into public.profiles(id, full_name)
    values (caller_id, coalesce(p_full_name, '')) on conflict(id) do nothing;
  -- A concurrent insert can block. A committed revocation during that wait
  -- must not turn the resumed operation into successful provisioning.
  access_state := private.current_account_access();
  if access_state->>'provisioning_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
exception
  when sqlstate 'PT401' or sqlstate 'PT403' then raise;
  when others then
    raise exception 'admission_unavailable' using errcode = 'PT503';
end;
$$;

revoke all on function private.current_account_access(), private.account_access_allowed(),
  public.get_admission_status(), public.ensure_own_profile(text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function private.account_access_allowed(),
  public.get_admission_status(), public.ensure_own_profile(text) to authenticated;



-- SOURCE: supabase/migrations/20260930013417_enforce_profile_terms_admission.sql
-- LOCAL CANDIDATE ONLY. Release requires trusted profile authority/roles,
-- compatible bootstrap/MFA clients, final policy and explicit approval.
-- Direct profiles and terms only: no financial, Edge or lifecycle enforcement.

do $$
begin
  if to_regprocedure('private.current_account_access()') is null
    or to_regprocedure('private.account_access_allowed()') is null
    or to_regprocedure('public.ensure_own_profile(text)') is null
    or to_regprocedure('public.get_admission_status()') is null
    or to_regprocedure('public.get_loyalty_policy_status()') is null
    or to_regprocedure('public.accept_loyalty_policy(text)') is null
    or not (select relrowsecurity from pg_catalog.pg_class
      where oid = 'public.profiles'::regclass)
    or (select count(*) from pg_catalog.pg_trigger
      where tgrelid = 'public.profiles'::regclass and not tgisinternal
        and tgenabled in ('O', 'A') and (
          (tgname = 'profiles_protected_fields_guard'
            and tgfoid = to_regprocedure('public.guard_profile_protected_fields()'))
          or (tgname = 'profiles_policy_acceptance_guard'
            and tgfoid = to_regprocedure('public.guard_profile_policy_acceptance()'))
        )) <> 2 then
    raise exception 'Reviewed profile, policy and admission prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- Restrictive predicates AND with, never replace, existing owner/admin rules.
create policy profiles_account_admission on public.profiles
as restrictive for all to authenticated
using ((select private.account_access_allowed()))
with check ((select private.account_access_allowed()));

create policy profiles_server_provisioning_only on public.profiles
as restrictive for insert to authenticated with check (false);

create or replace function public.get_loyalty_policy_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  accepted_version text;
  accepted_at timestamptz;
  policy_descriptor jsonb;
begin
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller_id := auth.uid();
  -- Preserve Auth-before-profile locking; the evaluator owns all eligibility.
  perform 1 from auth.users u where u.id = caller_id for share;
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  select p.loyalty_policy_version, p.loyalty_policy_accepted_at
    into accepted_version, accepted_at
  from public.profiles p where p.id = caller_id;
  if not found then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  policy_descriptor := public.get_loyalty_policy_descriptor();
  return policy_descriptor || jsonb_build_object(
    'accepted_version', accepted_version,
    'accepted_at', accepted_at,
    'acceptance_required', accepted_version is distinct from policy_descriptor->>'required_version'
      or accepted_at is null
  );
exception
  when sqlstate 'PT401' then
    raise exception 'session_invalid' using errcode = 'PT401';
  when sqlstate 'PT403' then
    raise exception 'account_restricted' using errcode = 'PT403';
  when others then
    raise exception 'admission_unavailable' using errcode = 'PT503';
end;
$$;

create or replace function public.accept_loyalty_policy(p_version text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  policy_status jsonb;
  accepted_version text;
  accepted_at timestamptz;
begin
  policy_status := public.get_loyalty_policy_status();
  if p_version is distinct from policy_status->>'required_version' then
    raise exception 'policy_version_mismatch' using errcode = '22023';
  end if;

  -- Only the explicit version check above exposes 22023, not storage errors.
  begin
    select p.loyalty_policy_version, p.loyalty_policy_accepted_at
      into accepted_version, accepted_at
    from public.profiles p where p.id = auth.uid()
    for no key update;
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;

    if accepted_version is distinct from p_version or accepted_at is null then
      accepted_at := clock_timestamp();
      update public.profiles set loyalty_policy_version = p_version,
        loyalty_policy_accepted_at = accepted_at where id = auth.uid();
    end if;
    -- Also cover a wait inside an UPDATE trigger; failure rolls back acceptance.
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;

    return policy_status || jsonb_build_object(
      'accepted_version', p_version, 'accepted_at', accepted_at,
      'acceptance_required', false
    );
  exception
    when sqlstate 'PT401' then
      raise exception 'session_invalid' using errcode = 'PT401';
    when sqlstate 'PT403' then
      raise exception 'account_restricted' using errcode = 'PT403';
    when others then
      raise exception 'admission_unavailable' using errcode = 'PT503';
  end;
end;
$$;

create or replace function public.get_admission_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  access_state jsonb;
  policy_status jsonb;
begin
  access_state := private.current_account_access();
  if access_state->>'account_access' = 'eligible' then
    begin
      policy_status := public.get_loyalty_policy_status();
    exception when sqlstate 'PT403' then
      -- A restriction observed after a wait belongs in the existing wire.
      policy_status := null;
    end;
    access_state := private.current_account_access();
    if access_state->>'account_access' = 'eligible' then
      if jsonb_typeof(policy_status->'acceptance_required') is distinct from 'boolean' then
        raise exception 'admission_unavailable' using errcode = 'PT503';
      end if;
      access_state := access_state || jsonb_build_object('next_step',
        case when (policy_status->>'acceptance_required')::boolean then 'review_terms' else 'home' end);
    end if;
  end if;
  return jsonb_build_object(
    'subject_id', access_state->'subject_id', 'account_access', access_state->'account_access',
    'next_step', access_state->'next_step', 'reason', access_state->'reason',
    'account_state', access_state->'account_state', 'restore_until', access_state->'restore_until'
  );
exception
  when sqlstate 'PT401' then
    raise exception 'session_invalid' using errcode = 'PT401';
  when others then
    raise exception 'admission_unavailable' using errcode = 'PT503';
end;
$$;

revoke all on function public.get_loyalty_policy_status(),
  public.accept_loyalty_policy(text), public.get_admission_status()
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.get_loyalty_policy_status(),
  public.accept_loyalty_policy(text), public.get_admission_status() to authenticated;



-- SOURCE: supabase/migrations/20260930063923_recoverable_account_deletion.sql
-- LOCAL ONLY. Activation is held for the API/client coverage in
-- docs/account-recovery.md. No cleanup or Auth/financial mutations.

do $$
begin
  if to_regprocedure('private.current_account_access()') is null
    or not exists (select 1 from pg_catalog.pg_policy
      where polrelid = 'public.profiles'::regclass
        and polname = 'profiles_account_admission' and not polpermissive) then
    raise exception 'Reviewed profile/terms/admission prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

create table private.account_lifecycle (
  user_id uuid primary key references public.profiles(id),
  deletion_requested_at timestamptz not null,
  restore_until timestamptz not null,
  restored_at timestamptz,
  marketing_suppressed boolean not null default true check (marketing_suppressed),
  check (restore_until = deletion_requested_at + interval '720 hours'),
  check (restored_at is null or
    (restored_at > deletion_requested_at and restored_at < restore_until))
);
alter table private.account_lifecycle enable row level security;
revoke all on private.account_lifecycle from public, anon, authenticated,
  service_role, supabase_auth_admin;

-- Replace the one canonical evaluator, not a second recovery auth engine.
create or replace function private.current_account_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  claims jsonb;
  caller_id uuid;
  session_id uuid;
  jwt_aal text;
  current_aal text;
  session_factor_id uuid;
  session_not_after timestamptz;
  session_created_at timestamptz;
  user_anonymous boolean;
  user_deleted_at timestamptz;
  user_banned_until timestamptz;
  user_email_confirmed_at timestamptz;
  caller_role text;
  has_totp boolean;
  unsupported_factor boolean;
  bound_totp boolean;
  lifecycle private.account_lifecycle%rowtype;
  pending boolean;
  result jsonb;
begin
  begin
    claims := auth.jwt();
    caller_id := auth.uid();
    session_id := (claims->>'session_id')::uuid;
    jwt_aal := claims->>'aal';
    if caller_id is null or session_id is null
      or (claims->>'sub')::uuid is distinct from caller_id
      or claims->>'role' is distinct from 'authenticated'
      or jsonb_typeof(claims->'exp') is distinct from 'number'
      or (claims->>'exp')::numeric <= extract(epoch from clock_timestamp())
      or coalesce(jwt_aal, '') not in ('aal1', 'aal2') then
      raise exception 'session_invalid' using errcode = 'PT401';
    end if;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'session_invalid' using errcode = 'PT401';
  end;

  select s.aal::text, s.factor_id, s.not_after, s.created_at
    into current_aal, session_factor_id, session_not_after, session_created_at
  from auth.sessions s where s.id = session_id and s.user_id = caller_id;
  if not found or coalesce(current_aal, '') not in ('aal1', 'aal2')
    or session_not_after <= clock_timestamp() then
    raise exception 'session_invalid' using errcode = 'PT401';
  end if;

  select u.is_anonymous, u.deleted_at, u.banned_until, u.email_confirmed_at
    into user_anonymous, user_deleted_at, user_banned_until, user_email_confirmed_at
  from auth.users u where u.id = caller_id;
  if not found then
    raise exception 'session_invalid' using errcode = 'PT401';
  end if;

  result := jsonb_build_object(
    'subject_id', caller_id, 'account_access', 'restricted',
    'next_step', 'blocked', 'reason', 'account_restricted',
    'account_state', 'blocked', 'restore_until', null,
    'provisioning_allowed', false, 'lifecycle_identity_allowed', false
  );
  if user_anonymous is not false or user_deleted_at is not null
    or user_banned_until > clock_timestamp() then
    return result;
  end if;

  select * into lifecycle from private.account_lifecycle where user_id = caller_id;
  pending := found and lifecycle.restored_at is null;
  -- Old sessions cannot regain ordinary access when another session restores.
  if lifecycle.restored_at is not null and (session_created_at is null
    or session_created_at <= lifecycle.deletion_requested_at) then
    raise exception 'session_invalid' using errcode = 'PT401';
  end if;
  result := result || jsonb_build_object(
    'account_state', case when pending then 'pending_deletion' else 'legacy_active' end,
    'restore_until', case when pending then lifecycle.restore_until else null end,
    'provisioning_allowed', not pending, 'reason', null
  );
  if user_email_confirmed_at is null then
    return result || jsonb_build_object('next_step', 'verify_email');
  end if;

  select p.roles::text into caller_role from public.profiles p where p.id = caller_id;
  if not found then
    return result || jsonb_build_object('reason', 'profile_missing');
  end if;
  if coalesce(caller_role, '') not in ('User', 'Admin', 'Owner') then
    return result || jsonb_build_object('reason', 'role_unavailable');
  end if;

  select
    coalesce(bool_or(f.status::text = 'verified' and f.factor_type::text = 'totp'), false),
    coalesce(bool_or(coalesce(f.status::text, '') not in ('unverified', 'verified')
      or (f.status::text = 'verified' and f.factor_type::text is distinct from 'totp')), false),
    coalesce(bool_or(f.id = session_factor_id and f.status::text = 'verified'
      and f.factor_type::text = 'totp'), false)
    into has_totp, unsupported_factor, bound_totp
  from auth.mfa_factors f where f.user_id = caller_id;
  if unsupported_factor then
    return result || jsonb_build_object('reason', 'unsupported_factor');
  end if;
  if caller_role in ('Admin', 'Owner') and not has_totp then
    return result || jsonb_build_object('next_step', 'enroll_totp');
  end if;
  if has_totp and (jwt_aal <> 'aal2' or current_aal <> 'aal2' or not bound_totp) then
    return result || jsonb_build_object('next_step', 'challenge_totp');
  end if;
  result := result || jsonb_build_object('lifecycle_identity_allowed', true);
  if pending then
    return result || jsonb_build_object('reason', case
      when clock_timestamp() >= lifecycle.restore_until then 'restore_expired'
      else 'explicit_restore_required' end);
  end if;
  return result || jsonb_build_object('account_access', 'eligible', 'next_step', 'home');
exception
  when sqlstate 'PT401' then raise;
  when others then
    raise exception 'admission_unavailable' using errcode = 'PT503';
end;
$$;

create function public.get_account_lifecycle_status()
returns jsonb
language sql volatile security definer set search_path = ''
as $$ select public.get_admission_status(); $$;

create function public.request_account_deletion()
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  access_state jsonb;
  caller_id uuid;
  requested_at timestamptz;
begin
  access_state := private.current_account_access();
  caller_id := (access_state->>'subject_id')::uuid;
  perform 1 from auth.users where id = caller_id for share;
  perform 1 from public.profiles where id = caller_id for no key update;
  if not found then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  access_state := private.current_account_access();
  if access_state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if access_state->>'account_state' <> 'pending_deletion' then
    requested_at := clock_timestamp();
    insert into private.account_lifecycle(user_id, deletion_requested_at, restore_until)
      values (caller_id, requested_at, requested_at + interval '720 hours')
    on conflict(user_id) do update set deletion_requested_at = excluded.deletion_requested_at,
      restore_until = excluded.restore_until, restored_at = null;
  end if;
  return public.get_account_lifecycle_status();
exception
  when sqlstate 'PT401' or sqlstate 'PT403' then raise;
  when others then
    raise exception 'lifecycle_unavailable' using errcode = 'PT503';
end;
$$;

create function public.restore_account()
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  access_state jsonb;
  caller_id uuid;
  lifecycle private.account_lifecycle%rowtype;
  session_created_at timestamptz;
  restored_at_now timestamptz;
begin
  access_state := private.current_account_access();
  caller_id := (access_state->>'subject_id')::uuid;
  perform 1 from auth.users where id = caller_id for share;
  perform 1 from public.profiles where id = caller_id for no key update;
  if not found then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  access_state := private.current_account_access();
  if access_state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  select * into lifecycle from private.account_lifecycle where user_id = caller_id;
  if not found then
    raise exception 'restore_unavailable' using errcode = 'PT403';
  end if;
  select s.created_at into session_created_at from auth.sessions s
    where s.id = (auth.jwt()->>'session_id')::uuid and s.user_id = caller_id;
  restored_at_now := clock_timestamp();
  if session_created_at is null or session_created_at <= lifecycle.deletion_requested_at
    or session_created_at > restored_at_now
    or session_created_at <= restored_at_now - interval '10 minutes' then
    raise exception 'fresh_session_required' using errcode = 'PT403';
  end if;
  if restored_at_now >= lifecycle.restore_until then
    raise exception 'restore_expired' using errcode = 'PT403';
  end if;
  if lifecycle.restored_at is null then
    update private.account_lifecycle set restored_at = restored_at_now where user_id = caller_id;
  end if;
  -- AFTER triggers can wait on other locks. Recheck authority and wall-clock
  -- boundaries after they return; failure rolls the restoration back atomically.
  access_state := private.current_account_access();
  if access_state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  select s.created_at into session_created_at from auth.sessions s
    where s.id = (auth.jwt()->>'session_id')::uuid and s.user_id = caller_id;
  restored_at_now := clock_timestamp();
  -- Refreshing an old JWT/session does not meet this reauthentication rule.
  if session_created_at is null or session_created_at <= lifecycle.deletion_requested_at
    or session_created_at > restored_at_now
    or session_created_at <= restored_at_now - interval '10 minutes' then
    raise exception 'fresh_session_required' using errcode = 'PT403';
  end if;
  if restored_at_now >= lifecycle.restore_until then
    raise exception 'restore_expired' using errcode = 'PT403';
  end if;
  return public.get_account_lifecycle_status();
exception
  when sqlstate 'PT401' or sqlstate 'PT403' then raise;
  when others then
    raise exception 'lifecycle_unavailable' using errcode = 'PT503';
end;
$$;

revoke all on function public.get_account_lifecycle_status(),
  public.request_account_deletion(), public.restore_account()
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.get_account_lifecycle_status(),
  public.request_account_deletion(), public.restore_account() to authenticated;



-- SOURCE: supabase/migrations/20260930125527_newsletter_consent_mail_outbox.sql
-- Local-only candidate. No scheduler, provider configuration, or financial writes.

create table private.mail_settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  rollout_at timestamptz,
  consent_version text not null default 'newsletter-v1',
  consent_text text not null default 'I would like to receive the Clean Stream newsletter. I can unsubscribe at any time.',
  check (not enabled or rollout_at is not null)
);
insert into private.mail_settings default values;

create table private.newsletter_consent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  email text not null,
  purpose text not null default 'newsletter' check (purpose = 'newsletter'),
  version text not null,
  consent_text text not null,
  source text not null check (source in ('signup', 'settings')),
  requested_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  confirmed_at timestamptz,
  unsubscribed_at timestamptz,
  suppression_reason text,
  confirm_hash text unique check (confirm_hash ~ '^[0-9a-f]{64}$'),
  unsubscribe_hash text unique check (unsubscribe_hash ~ '^[0-9a-f]{64}$')
);
create index on private.newsletter_consent(user_id, requested_at desc);
create index on private.newsletter_consent(email, requested_at desc);

create table private.mail_suppression (
  email text primary key,
  reason text not null,
  created_at timestamptz not null default clock_timestamp()
);
create table private.mail_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  kind text not null check (kind in ('account_welcome', 'newsletter_confirm', 'newsletter_welcome')),
  user_id uuid not null,
  email text not null,
  consent_id uuid references private.newsletter_consent(id),
  state text not null default 'ready' check (state in
    ('ready','leased','sending','uncertain','accepted','delivered','failed','suppressed')),
  created_at timestamptz not null default clock_timestamp(),
  next_at timestamptz not null default clock_timestamp(),
  lease_id uuid,
  lease_until timestamptz,
  attempts integer not null default 0,
  first_attempt_at timestamptz,
  payload_hash text,
  provider_id text unique,
  last_error text
);
create index on private.mail_outbox(next_at) where state in ('ready','leased','sending');
create table private.mail_webhook_event (
  event_id text primary key,
  provider_id text not null,
  event_type text not null,
  outbox_id uuid,
  received_at timestamptz not null default clock_timestamp()
);

-- No client or service direct table access, including inherited PUBLIC grants.
do $$ declare t text; begin
  foreach t in array array['mail_settings','newsletter_consent','mail_suppression','mail_outbox','mail_webhook_event'] loop
    execute format('alter table private.%I enable row level security', t);
    execute format('revoke all on private.%I from public, anon, authenticated, service_role, supabase_auth_admin', t);
  end loop;
end $$;

-- A single short transaction lock keeps this small outbox's state transitions
-- ordered with consent/deletion. Never hold it across a provider HTTP request.
create function private.mail_lock() returns void language sql volatile
set search_path = '' as $$ select pg_advisory_xact_lock(726314, 1); $$;

create function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
    and (l.restored_at is null or o.kind <> 'account_welcome'))
  and (o.kind='account_welcome' or exists (
    select 1 from private.newsletter_consent c where c.id=o.consent_id
      and c.unsubscribed_at is null and c.email=o.email
      and ((o.kind='newsletter_confirm' and c.confirmed_at is null and c.expires_at>clock_timestamp())
        or (o.kind='newsletter_welcome' and c.confirmed_at is not null))));
$$;

create function private.mail_account_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email_confirmed_at is not null and new.email is not null
    and new.is_anonymous is false and new.deleted_at is null
    and exists (select 1 from private.mail_settings s where s.enabled
      and new.created_at >= s.rollout_at) then
    insert into private.mail_outbox(event_key,kind,user_id,email)
    values ('account_welcome/'||new.id,'account_welcome',new.id,lower(btrim(new.email)))
    on conflict(event_key) do nothing;
  end if;
  return new;
end $$;
create trigger mail_verified_account after insert or update of email_confirmed_at on auth.users
for each row execute function private.mail_account_event();

create function private.mail_lifecycle_suppression() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.marketing_suppressed then
    perform private.mail_lock();
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason='account_deletion', confirm_hash=null where user_id=new.user_id;
    update private.mail_outbox set state='suppressed',last_error='account_deletion'
      where user_id=new.user_id and state in ('ready','leased','sending','uncertain');
  end if;
  return new;
end $$;
create trigger mail_account_suppression after insert or update on private.account_lifecycle
for each row execute function private.mail_lifecycle_suppression();

create function private.mail_email_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if lower(btrim(old.email)) is distinct from lower(btrim(new.email)) or new.deleted_at is not null then
    perform private.mail_lock();
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason='identity_changed',confirm_hash=null where user_id=new.id;
    update private.mail_outbox set state='suppressed',last_error='identity_changed'
      where user_id=new.id and state in ('ready','leased','sending','uncertain');
  end if;
  return new;
end $$;
create trigger mail_identity_changed after update of email,deleted_at on auth.users
for each row execute function private.mail_email_change();

create function public.newsletter_status() returns jsonb
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare a jsonb; c private.newsletter_consent; e text; s private.mail_settings;
begin
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  select * into s from private.mail_settings;
  select * into c from private.newsletter_consent where user_id=auth.uid() and email=e order by requested_at desc limit 1;
  return jsonb_build_object('subject_id',auth.uid(),'state',case
    when exists(select 1 from private.account_lifecycle where user_id=auth.uid())
      or exists(select 1 from private.mail_suppression where email=e) then 'suppressed'
    when c.id is null then 'not_subscribed'
    when c.unsubscribed_at is not null then 'unsubscribed'
    when c.confirmed_at is not null then 'subscribed'
    when c.expires_at<=clock_timestamp() then 'expired' else 'pending' end,
    'requested_at',c.requested_at,'confirmed_at',c.confirmed_at,'unsubscribed_at',c.unsubscribed_at,
    'consent_version',s.consent_version,'consent_text',s.consent_text,'enabled',s.enabled);
end $$;

create function public.newsletter_request(p_opt_in boolean, p_version text, p_source text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb; e text; c private.newsletter_consent; s private.mail_settings; n timestamptz;
begin
  -- Match lifecycle's lock order and recheck live session after waiting.
  perform 1 from auth.users where id=auth.uid() for share;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  perform private.mail_lock();
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  if p_opt_in is distinct from true then return public.newsletter_status(); end if;
  select * into s from private.mail_settings;
  if not s.enabled then raise exception 'mail_disabled' using errcode='PT503'; end if;
  if p_version is distinct from s.consent_version or p_source is null or p_source not in ('signup','settings') then
    raise exception 'consent_invalid' using errcode='PT400'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  if e is null or exists(select 1 from private.account_lifecycle where user_id=auth.uid())
    or exists(select 1 from private.mail_suppression where email=e) then
    raise exception 'mail_suppressed' using errcode='PT403'; end if;
  select * into c from private.newsletter_consent where user_id=auth.uid() and email=e
    and unsubscribed_at is null and confirmed_at is not null limit 1;
  if found then return public.newsletter_status(); end if;
  n := clock_timestamp();
  if exists(select 1 from private.newsletter_consent where (user_id=auth.uid() or email=e)
      and requested_at>n-interval '1 minute')
    or (select count(*) from private.newsletter_consent where (user_id=auth.uid() or email=e)
      and requested_at>n-interval '24 hours') >= 3 then
    raise exception 'newsletter_rate_limited' using errcode='PT429'; end if;
  update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,n),
    suppression_reason=coalesce(suppression_reason,'superseded'),confirm_hash=null
    where user_id=auth.uid() and unsubscribed_at is null;
  insert into private.newsletter_consent(user_id,email,version,consent_text,source,requested_at,expires_at)
    values(auth.uid(),e,s.consent_version,s.consent_text,p_source,n,n+interval '24 hours') returning * into c;
  insert into private.mail_outbox(event_key,kind,user_id,email,consent_id)
    values('newsletter_confirm/'||c.id,'newsletter_confirm',c.user_id,e,c.id);
  return public.newsletter_status();
end $$;

create function public.newsletter_withdraw() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb; e text;
begin
  perform 1 from auth.users where id=auth.uid() for share;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  perform private.mail_lock();
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
    suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
    where user_id=auth.uid() and email=e;
  update private.mail_outbox set state='suppressed',last_error='unsubscribe'
    where user_id=auth.uid() and email=e and kind<>'account_welcome'
    and state in ('ready','leased','sending','uncertain');
  return public.newsletter_status();
end $$;

-- Capability endpoints are service-only; raw tokens are hashed in Edge, never stored.
create function public.newsletter_token(p_action text,p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c private.newsletter_consent; o private.mail_outbox;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_action is null or p_action not in ('confirm','unsubscribe') then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  perform private.mail_lock();
  if p_action='unsubscribe' then
    select * into c from private.newsletter_consent where unsubscribe_hash=p_hash;
    if found then
      -- Old links also suppress a later opt-in for the same mailbox/identity.
      update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
        suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
        where user_id=c.user_id and email=c.email;
      update private.mail_outbox set state='suppressed',last_error='unsubscribe'
        where user_id=c.user_id and email=c.email and kind<>'account_welcome'
        and state in ('ready','leased','sending','uncertain');
    end if;
    return jsonb_build_object('state','unsubscribed');
  end if;
  select * into c from private.newsletter_consent where confirm_hash=p_hash;
  if not found or c.confirmed_at is not null or c.unsubscribed_at is not null or c.expires_at<=clock_timestamp() then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  select * into o from private.mail_outbox where consent_id=c.id and kind='newsletter_confirm';
  if not private.mail_allowed(o) then raise exception 'token_invalid' using errcode='PT400'; end if;
  update private.newsletter_consent set confirmed_at=clock_timestamp(),confirm_hash=null where id=c.id;
  insert into private.mail_outbox(event_key,kind,user_id,email,consent_id)
    values('newsletter_welcome/'||c.id,'newsletter_welcome',c.user_id,c.email,c.id) on conflict(event_key) do nothing;
  return jsonb_build_object('state','subscribed');
end $$;

create function public.mail_claim() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  if not exists(select 1 from private.mail_settings where enabled) then return null; end if;
  update private.mail_outbox set state='uncertain',last_error='worker_lost'
    where state='sending' and lease_until<clock_timestamp();
  update private.mail_outbox set state='ready' where state='leased' and lease_until<clock_timestamp();
  update private.mail_outbox m set state='suppressed',last_error='suppressed_or_stale'
    where state in ('ready','leased') and not private.mail_allowed(m);
  update private.mail_outbox set state='failed',last_error='retry_exhausted'
    where state='ready' and (attempts>=5 or first_attempt_at<clock_timestamp()-interval '23 hours');
  select * into o from private.mail_outbox where state='ready' and next_at<=clock_timestamp()
    order by created_at,id limit 1 for update;
  if not found then return null; end if;
  update private.mail_outbox set state='leased',lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes'
    where id=o.id returning * into o;
  return to_jsonb(o);
end $$;

create function public.mail_prepare(p_id uuid,p_lease uuid,p_payload_hash text,p_confirm_hash text,p_unsubscribe_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  select * into o from private.mail_outbox where id=p_id;
  if not found or o.state<>'leased' or o.lease_id is distinct from p_lease or o.lease_until<=clock_timestamp()
    or not exists(select 1 from private.mail_settings where enabled) then return false; end if;
  if not private.mail_allowed(o) then
    update private.mail_outbox set state='suppressed',last_error='suppressed_or_stale' where id=o.id;
    return false;
  end if;
  if p_payload_hash is null or p_payload_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_hash'; end if;
  if o.payload_hash is not null and o.payload_hash<>p_payload_hash then
    update private.mail_outbox set state='failed',last_error='payload_changed' where id=o.id;
    return false;
  end if;
  if o.kind='newsletter_welcome' and not exists(select 1 from private.newsletter_consent
    where id=o.consent_id and unsubscribe_hash=p_unsubscribe_hash) then
    update private.mail_outbox set state='failed',last_error='token_key_changed' where id=o.id;
    return false;
  end if;
  if o.kind='newsletter_confirm' then
    if p_confirm_hash is null or p_unsubscribe_hash is null then raise exception 'missing_hash'; end if;
    update private.newsletter_consent set confirm_hash=p_confirm_hash,unsubscribe_hash=p_unsubscribe_hash where id=o.consent_id;
  end if;
  update private.mail_outbox set state='sending',attempts=attempts+1,payload_hash=p_payload_hash,
    first_attempt_at=coalesce(first_attempt_at,clock_timestamp()) where id=o.id;
  return true;
end $$;

create function public.mail_finish(p_id uuid,p_lease uuid,p_result text,p_provider_id text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  select * into o from private.mail_outbox where id=p_id;
  if not found or o.lease_id is distinct from p_lease then return; end if;
  if p_result not in ('accepted','rate_limited','failed','uncertain') or p_result is null
    or (p_result='accepted' and coalesce(p_provider_id,'')='') then raise exception 'invalid_result'; end if;
  -- Suppression and delivery evidence are monotonic, even if webhook arrived first.
  if p_result='accepted' and o.provider_id is null then
    update private.mail_outbox set provider_id=p_provider_id where id=o.id;
  end if;
  if o.state not in ('sending','uncertain') then return; end if;
  update private.mail_outbox set state=case when p_result='rate_limited' then
      case when attempts>=5 then 'failed' else 'ready' end else p_result end,
    next_at=clock_timestamp()+make_interval(secs=>least(3600,60*power(2,attempts)::integer)),
    last_error=case when p_result='accepted' then null else p_result end where id=o.id;
end $$;

create function public.mail_record_webhook(p_event_id text,p_provider_id text,p_type text,p_outbox_id uuid,p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  if length(p_event_id)>200 or length(p_provider_id)>200 then raise exception 'invalid_event'; end if;
  select * into o from private.mail_outbox where provider_id=p_provider_id
    or (id=p_outbox_id and provider_id is null and first_attempt_at is not null) limit 1;
  if not found or o.email is distinct from lower(btrim(p_email)) then
    -- Retry unmatched events instead of permanently discarding reconciliation evidence.
    raise exception 'event_unmatched' using errcode='PT503'; end if;
  insert into private.mail_webhook_event(event_id,provider_id,event_type,outbox_id)
    values(p_event_id,p_provider_id,p_type,o.id) on conflict do nothing;
  if not found then return; end if;
  update private.mail_outbox set provider_id=p_provider_id where id=o.id;
  if p_type in ('email.bounced','email.complained','email.suppressed') then
    insert into private.mail_suppression(email,reason) values(o.email,p_type) on conflict do nothing;
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason=p_type,confirm_hash=null where email=o.email;
    update private.mail_outbox set state='suppressed',last_error=p_type
      where email=o.email and state<>'delivered';
  elsif p_type='email.delivered' then
    update private.mail_outbox set state='delivered' where id=o.id and state<>'suppressed';
  elsif p_type='email.sent' then
    update private.mail_outbox set state='accepted' where id=o.id and state in ('sending','uncertain','ready','leased');
  elsif p_type='email.failed' then
    update private.mail_outbox set state='failed',last_error=p_type
      where id=o.id and state not in ('delivered','suppressed');
  end if;
end $$;

-- Explicit allowlist, independent of project default function privileges.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='private' and p.proname in ('mail_lock','mail_allowed','mail_account_event','mail_lifecycle_suppression','mail_email_change'))
      or (n.nspname='public' and p.proname in ('newsletter_status','newsletter_request','newsletter_withdraw','newsletter_token',
        'mail_claim','mail_prepare','mail_finish','mail_record_webhook')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role,supabase_auth_admin',f.signature);
  end loop;
end $$;
grant execute on function public.newsletter_status(),public.newsletter_request(boolean,text,text),public.newsletter_withdraw() to authenticated;
grant execute on function public.newsletter_token(text,text), public.mail_claim(),
  public.mail_prepare(uuid,uuid,text,text,text),public.mail_finish(uuid,uuid,text,text),
  public.mail_record_webhook(text,text,text,uuid,text) to service_role;


-- SOURCE: supabase/migrations/20260930175136_refund_request_notice_outbox.sql
-- Queue-only extension. No claim/ledger mutations, sender setup or activation.

alter table private.mail_settings add column refund_notice_recipient uuid
  references auth.users(id) on delete set null;
alter table private.mail_outbox
  add column refund_id bigint,
  add column refund_notice jsonb;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check
  check (kind in ('account_welcome','newsletter_confirm','newsletter_welcome','refund_request'));
alter table private.mail_outbox add constraint mail_outbox_refund_notice_check check (
  (kind='refund_request' and refund_id is not null and refund_notice is not null
    and jsonb_typeof(refund_notice)='object')
  or (kind<>'refund_request' and refund_id is null and refund_notice is null)
);
-- Intentionally no FK back to Refunds: deleting a record must not erase the
-- permanent event key or make an unrelated financial cleanup fail.

create or replace function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
    and (l.restored_at is null or o.kind not in ('account_welcome','refund_request')))
  and (o.kind='account_welcome' or (o.kind='refund_request'
    and exists (select 1 from private.mail_settings s join public.profiles p
      on p.id=s.refund_notice_recipient
      where s.refund_notice_recipient=o.user_id and p.roles::text='Owner')
    and exists (select 1 from public."Refunds" r
      join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
      join auth.users u on u.id=r.user_id
      where r.refund_id=o.refund_id and r.status::text='pending'
        and u.deleted_at is null and u.is_anonymous is false
        and (u.banned_until is null or u.banned_until<=clock_timestamp())
        and not exists (select 1 from private.account_lifecycle l
          where l.user_id=r.user_id and l.restored_at is null)))
    or (o.kind in ('newsletter_confirm','newsletter_welcome') and exists (
      select 1 from private.newsletter_consent c where c.id=o.consent_id
        and c.unsubscribed_at is null and c.email=o.email
        and ((o.kind='newsletter_confirm' and c.confirmed_at is null and c.expires_at>clock_timestamp())
          or (o.kind='newsletter_welcome' and c.confirmed_at is not null)))));
$$;

create function public.enqueue_refund_request_notice(target_transaction_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a jsonb; caller uuid; matches bigint; rid bigint; r public."Refunds";
  settings private.mail_settings; o private.mail_outbox; notice_state text;
begin
  -- This lock orders enqueue with consent, identity changes and suppression.
  -- Do not acquire wallet, transaction or refund row locks for a notice.
  perform private.mail_lock();
  a:=private.current_account_access(); caller:=(a->>'subject_id')::uuid;
  if a->>'account_access' is distinct from 'eligible' then
    raise exception 'account_restricted' using errcode='PT403'; end if;
  if target_transaction_id is null or target_transaction_id<=0 then
    raise exception 'invalid_transaction_id' using errcode='PT400'; end if;
  select count(*),min(f.refund_id) into matches,rid
    from public."Refunds" f join public.transactions t
      on t.id=f.transaction_id and t.user_id=caller
    where f.transaction_id=target_transaction_id and f.user_id=caller and f.status::text='pending';
  if matches<>1 then
    raise exception 'claim_unavailable_or_ambiguous' using errcode='PT400'; end if;
  select * into r from public."Refunds" f where refund_id=rid
    and f.user_id=caller and f.transaction_id=target_transaction_id and f.status::text='pending'
    and exists (select 1 from public.transactions t where t.id=f.transaction_id and t.user_id=caller);
  if not found then raise exception 'claim_unavailable_or_ambiguous' using errcode='PT400'; end if;
  select * into settings from private.mail_settings;
  select * into o from private.mail_outbox
    where event_key='loyalty_credit_requested/'||rid;
  if found then
    if o.state in ('ready','leased') and not private.mail_allowed(o) then
      update private.mail_outbox set state='suppressed',last_error='suppressed_or_stale'
        where id=o.id returning * into o;
    end if;
    notice_state:=case when o.state in ('ready','leased') then 'queued' else o.state end;
  elsif settings.refund_notice_recipient is null then
    notice_state:='recipient_unavailable';
  elsif not settings.enabled then
    notice_state:='disabled';
  else
    o.kind:='refund_request'; o.refund_id:=rid;
    o.user_id:=settings.refund_notice_recipient;
    select nullif(lower(btrim(u.email)),'') into o.email from auth.users u
      join public.profiles p on p.id=u.id
      where u.id=o.user_id and p.roles::text='Owner';
    if o.email is null then notice_state:='recipient_unavailable';
    elsif not private.mail_allowed(o) then notice_state:='suppressed';
    elsif r.amount is null or r.amount<=0 or length(r.amount::text)>30
      or r.amount::text !~ '^[0-9]+(\.[0-9]{1,2})?$' then notice_state:='failed';
    else
      insert into private.mail_outbox(event_key,kind,user_id,email,refund_id,refund_notice)
      values('loyalty_credit_requested/'||rid,'refund_request',o.user_id,o.email,rid,
        jsonb_build_object('refund_id',rid::text,'transaction_id',r.transaction_id::text,
          'user_id',r.user_id::text,'amount',r.amount::text,
          'description',left(coalesce(r.description,''),4000)))
      on conflict(event_key) do nothing;
      notice_state:='queued';
    end if;
  end if;
  return jsonb_build_object('refund_id',rid::text,'state',notice_state);
end $$;
revoke all on function public.enqueue_refund_request_notice(bigint)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.enqueue_refund_request_notice(bigint) to authenticated;

-- Newsletter withdrawal does not withdraw transactional request alerts.
create or replace function public.newsletter_withdraw() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb; e text;
begin
  perform 1 from auth.users where id=auth.uid() for share;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  perform private.mail_lock();
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
    suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
    where user_id=auth.uid() and email=e;
  update private.mail_outbox set state='suppressed',last_error='unsubscribe'
    where user_id=auth.uid() and email=e and kind in ('newsletter_confirm','newsletter_welcome')
    and state in ('ready','leased','sending','uncertain');
  return public.newsletter_status();
end $$;

create or replace function public.newsletter_token(p_action text,p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c private.newsletter_consent; o private.mail_outbox;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_action is null or p_action not in ('confirm','unsubscribe') then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  perform private.mail_lock();
  if p_action='unsubscribe' then
    select * into c from private.newsletter_consent where unsubscribe_hash=p_hash;
    if found then
      update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
        suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
        where user_id=c.user_id and email=c.email;
      update private.mail_outbox set state='suppressed',last_error='unsubscribe'
        where user_id=c.user_id and email=c.email and kind in ('newsletter_confirm','newsletter_welcome')
        and state in ('ready','leased','sending','uncertain');
    end if;
    return jsonb_build_object('state','unsubscribed');
  end if;
  select * into c from private.newsletter_consent where confirm_hash=p_hash;
  if not found or c.confirmed_at is not null or c.unsubscribed_at is not null or c.expires_at<=clock_timestamp() then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  select * into o from private.mail_outbox where consent_id=c.id and kind='newsletter_confirm';
  if not private.mail_allowed(o) then raise exception 'token_invalid' using errcode='PT400'; end if;
  update private.newsletter_consent set confirmed_at=clock_timestamp(),confirm_hash=null where id=c.id;
  insert into private.mail_outbox(event_key,kind,user_id,email,consent_id)
    values('newsletter_welcome/'||c.id,'newsletter_welcome',c.user_id,c.email,c.id) on conflict(event_key) do nothing;
  return jsonb_build_object('state','subscribed');
end $$;



-- SOURCE: supabase/migrations/20260930213049_account_lifecycle_mail_outbox.sql
-- Queue-only lifecycle notices. No RPC, admission, retention or cleanup changes.

alter table private.mail_outbox
  add column lifecycle_requested_at timestamptz,
  add column lifecycle_restore_until timestamptz,
  add column lifecycle_restored_at timestamptz;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check check (kind in (
  'account_welcome','newsletter_confirm','newsletter_welcome','refund_request',
  'account_deletion_scheduled','account_restored'
));
alter table private.mail_outbox add constraint mail_outbox_lifecycle_notice_check check (
  (kind in ('account_deletion_scheduled','account_restored')
    and consent_id is null and lifecycle_requested_at is not null
    and lifecycle_restore_until is not null
    and lifecycle_restore_until = lifecycle_requested_at + interval '720 hours'
    and ((kind='account_deletion_scheduled' and lifecycle_restored_at is null)
      or (kind='account_restored' and lifecycle_restored_at is not null
        and lifecycle_restored_at > lifecycle_requested_at
        and lifecycle_restored_at < lifecycle_restore_until)))
  or (kind not in ('account_deletion_scheduled','account_restored')
    and lifecycle_requested_at is null and lifecycle_restore_until is null
    and lifecycle_restored_at is null)
);

create or replace function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and (
    (o.kind in ('account_deletion_scheduled','account_restored') and exists (
      select 1 from private.account_lifecycle l where l.user_id=o.user_id
        and l.deletion_requested_at=o.lifecycle_requested_at
        and l.restore_until=o.lifecycle_restore_until
        and ((o.kind='account_deletion_scheduled' and l.restored_at is null
            and l.restore_until>clock_timestamp())
          or (o.kind='account_restored' and l.restored_at=o.lifecycle_restored_at))))
    or (
      not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
        and (l.restored_at is null or o.kind not in ('account_welcome','refund_request')))
      and (o.kind='account_welcome' or (o.kind='refund_request'
        and exists (select 1 from private.mail_settings s join public.profiles p
          on p.id=s.refund_notice_recipient
          where s.refund_notice_recipient=o.user_id and p.roles::text='Owner')
        and exists (select 1 from public."Refunds" r
          join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
          join auth.users u on u.id=r.user_id
          where r.refund_id=o.refund_id and r.status::text='pending'
            and u.deleted_at is null and u.is_anonymous is false
            and (u.banned_until is null or u.banned_until<=clock_timestamp())
            and not exists (select 1 from private.account_lifecycle l
              where l.user_id=r.user_id and l.restored_at is null)))
        or (o.kind in ('newsletter_confirm','newsletter_welcome') and exists (
          select 1 from private.newsletter_consent c where c.id=o.consent_id
            and c.unsubscribed_at is null and c.email=o.email
            and ((o.kind='newsletter_confirm' and c.confirmed_at is null and c.expires_at>clock_timestamp())
              or (o.kind='newsletter_welcome' and c.confirmed_at is not null)))))
    )
  );
$$;

-- Reuse the existing AFTER trigger and lock ordering. Enqueue is part of the
-- lifecycle transaction, so failed restoration/post-wait checks enqueue nothing.
create or replace function private.mail_lifecycle_suppression() returns trigger
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare
  notice_kind text;
  event_at timestamptz;
  o private.mail_outbox;
begin
  if new.marketing_suppressed then
    perform private.mail_lock();
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason='account_deletion', confirm_hash=null where user_id=new.user_id;
    update private.mail_outbox m set state='suppressed',last_error='account_deletion'
      where user_id=new.user_id and state in ('ready','leased','sending','uncertain')
        and (kind not in ('account_deletion_scheduled','account_restored')
          or not private.mail_allowed(m));
  end if;

  if new.restored_at is null then
    if tg_op='INSERT' then notice_kind:='account_deletion_scheduled';
    elsif new.deletion_requested_at is distinct from old.deletion_requested_at then
      notice_kind:='account_deletion_scheduled';
    end if;
    event_at:=new.deletion_requested_at;
  elsif tg_op='UPDATE' then
    if old.restored_at is null then notice_kind:='account_restored'; end if;
    event_at:=new.restored_at;
  end if;
  if notice_kind is null or not exists (select 1 from private.mail_settings s
    where s.enabled and event_at>=s.rollout_at) then return new; end if;

  o.kind:=notice_kind; o.user_id:=new.user_id;
  o.lifecycle_requested_at:=new.deletion_requested_at;
  o.lifecycle_restore_until:=new.restore_until;
  o.lifecycle_restored_at:=new.restored_at;
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=new.user_id;
  if o.email is null or not private.mail_allowed(o) then return new; end if;
  insert into private.mail_outbox(event_key,kind,user_id,email,
    lifecycle_requested_at,lifecycle_restore_until,lifecycle_restored_at)
  values (notice_kind||'/'||new.user_id||'/'||
    to_char(new.deletion_requested_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    notice_kind,new.user_id,o.email,new.deletion_requested_at,new.restore_until,new.restored_at)
  on conflict(event_key) do nothing;
  return new;
end $$;

-- CREATE OR REPLACE retains the existing revoked ACLs. No public enqueue RPC,
-- backfill, activation, delivery claim, or permanent-deletion-complete event.

-- Approved temporary hold: ordinary API coverage must precede deletion requests.
REVOKE ALL ON FUNCTION public.request_account_deletion()
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
