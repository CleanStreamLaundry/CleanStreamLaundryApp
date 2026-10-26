-- LOCAL CANDIDATE ONLY. Release requires trusted profile authority/roles,
-- compatible bootstrap/MFA clients, final policy and explicit approval.
-- Direct profiles and terms only: no financial, Edge or lifecycle enforcement.
begin;

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

commit;
