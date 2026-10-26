-- LOCAL ONLY. Activation is held for the API/client coverage in
-- docs/account-recovery.md. No cleanup or Auth/financial mutations.
begin;

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

commit;
