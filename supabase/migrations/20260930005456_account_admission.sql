-- LOCAL FOUNDATION ONLY. No existing API/RLS enforcement or UI activation.
-- Production release requires profile authority, role legitimacy, hosted JWT/
-- timeout validation, approved policy, and lifecycle/enforcement integration.
begin;

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

commit;
