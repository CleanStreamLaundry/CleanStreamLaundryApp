-- Owner-supported customer recovery only. No Auth mutation is performed by SQL.
begin;

do $$ begin
  if to_regprocedure('private.portal_staff_context()') is null
    or to_regclass('public.admin_audit_events') is null then
    raise exception 'Canonical staff and immutable audit prerequisites required' using errcode='55000';
  end if;
end $$;

create table private.customer_mfa_recovery (
  user_id uuid primary key references public.profiles(id),
  recovery_id uuid not null unique default gen_random_uuid(),
  actor_id uuid not null,
  support_case text not null check (length(support_case) between 1 and 120),
  started_at timestamptz not null default clock_timestamp(),
  factor_ids uuid[] not null check (cardinality(factor_ids) between 1 and 10)
);
alter table private.customer_mfa_recovery enable row level security;
revoke all on private.customer_mfa_recovery from public,anon,authenticated,service_role,supabase_auth_admin;
grant select(created_at) on auth.mfa_factors to postgres;

-- Retain the canonical evaluator and its existing wire values. A recovery row
-- permanently requires MFA; deleting the newly enrolled factor cannot reopen AAL1.
create or replace function private.current_account_access()
returns jsonb language plpgsql stable security definer
set search_path='' set timezone='UTC' as $$
declare
  claims jsonb; caller_id uuid; session_id uuid; jwt_aal text; current_aal text;
  session_factor_id uuid; session_not_after timestamptz; session_created_at timestamptz;
  user_anonymous boolean; user_deleted_at timestamptz; user_banned_until timestamptz;
  user_email_confirmed_at timestamptz; caller_role text;
  has_totp boolean; unsupported_factor boolean; bound_totp boolean;
  lifecycle private.account_lifecycle%rowtype;
  recovery private.customer_mfa_recovery%rowtype;
  pending boolean; result jsonb;
begin
  begin
    claims:=auth.jwt(); caller_id:=auth.uid();
    session_id:=(claims->>'session_id')::uuid; jwt_aal:=claims->>'aal';
    if caller_id is null or session_id is null
      or (claims->>'sub')::uuid is distinct from caller_id
      or claims->>'role' is distinct from 'authenticated'
      or jsonb_typeof(claims->'exp') is distinct from 'number'
      or (claims->>'exp')::numeric <= extract(epoch from clock_timestamp())
      or coalesce(jwt_aal,'') not in ('aal1','aal2') then
      raise exception 'session_invalid' using errcode='PT401';
    end if;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'session_invalid' using errcode='PT401';
  end;
  select s.aal::text,s.factor_id,s.not_after,s.created_at
    into current_aal,session_factor_id,session_not_after,session_created_at
    from auth.sessions s where s.id=session_id and s.user_id=caller_id;
  if not found or coalesce(current_aal,'') not in ('aal1','aal2')
    or session_not_after <= clock_timestamp() then
    raise exception 'session_invalid' using errcode='PT401';
  end if;
  select u.is_anonymous,u.deleted_at,u.banned_until,u.email_confirmed_at
    into user_anonymous,user_deleted_at,user_banned_until,user_email_confirmed_at
    from auth.users u where u.id=caller_id;
  if not found then raise exception 'session_invalid' using errcode='PT401'; end if;
  result:=jsonb_build_object('subject_id',caller_id,'account_access','restricted',
    'next_step','blocked','reason','account_restricted','account_state','blocked',
    'restore_until',null,'provisioning_allowed',false,'lifecycle_identity_allowed',false);
  if user_anonymous is not false or user_deleted_at is not null
    or user_banned_until > clock_timestamp() then return result; end if;
  select * into lifecycle from private.account_lifecycle where user_id=caller_id;
  pending:=found and lifecycle.restored_at is null;
  if lifecycle.restored_at is not null and (session_created_at is null
    or session_created_at <= lifecycle.deletion_requested_at) then
    raise exception 'session_invalid' using errcode='PT401';
  end if;
  select * into recovery from private.customer_mfa_recovery where user_id=caller_id;
  if found and (session_created_at is null or session_created_at <= recovery.started_at
    or session_created_at > clock_timestamp()) then
    raise exception 'session_invalid' using errcode='PT401';
  end if;
  result:=result || jsonb_build_object(
    'account_state',case when pending then 'pending_deletion' else 'legacy_active' end,
    'restore_until',case when pending then lifecycle.restore_until else null end,
    'provisioning_allowed',not pending,'reason',null);
  if user_email_confirmed_at is null then
    return result || jsonb_build_object('next_step','verify_email');
  end if;
  select p.roles::text into caller_role from public.profiles p where p.id=caller_id;
  if not found then return result || jsonb_build_object('reason','profile_missing'); end if;
  if coalesce(caller_role,'') not in ('User','Admin','Owner') then
    return result || jsonb_build_object('reason','role_unavailable');
  end if;
  select coalesce(bool_or(f.status::text='verified' and f.factor_type::text='totp'
      and (recovery.user_id is null or f.created_at>recovery.started_at)),false),
    coalesce(bool_or(coalesce(f.status::text,'') not in ('unverified','verified')
      or (f.status::text='verified' and f.factor_type::text is distinct from 'totp')),false),
    coalesce(bool_or(f.id=session_factor_id and f.status::text='verified'
      and f.factor_type::text='totp'
      and (recovery.user_id is null or f.created_at>recovery.started_at)),false)
    into has_totp,unsupported_factor,bound_totp
    from auth.mfa_factors f where f.user_id=caller_id;
  if unsupported_factor then return result || jsonb_build_object('reason','unsupported_factor'); end if;
  -- Incomplete/unknown Auth outcomes stay fenced, even with a new AAL2 session.
  if recovery.user_id is not null and exists (select 1 from auth.mfa_factors f
    where f.user_id=caller_id and f.id=any(recovery.factor_ids)) then
    return result || jsonb_build_object('reason','account_restricted');
  end if;
  if (caller_role in ('Admin','Owner') or recovery.user_id is not null) and not has_totp then
    return result || jsonb_build_object('next_step','enroll_totp');
  end if;
  if has_totp and (jwt_aal<>'aal2' or current_aal<>'aal2' or not bound_totp) then
    return result || jsonb_build_object('next_step','challenge_totp');
  end if;
  result:=result || jsonb_build_object('lifecycle_identity_allowed',true);
  if pending then
    return result || jsonb_build_object('reason',case when clock_timestamp() >= lifecycle.restore_until
      then 'restore_expired' else 'explicit_restore_required' end);
  end if;
  return result || jsonb_build_object('account_access','eligible','next_step','home');
exception when sqlstate 'PT401' then raise;
  when others then raise exception 'admission_unavailable' using errcode='PT503';
end $$;

-- A target cannot become privileged while any captured factor is removable.
-- Once all captured IDs are absent, stale executions cannot delete a new factor.
create function private.guard_customer_recovery_role()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.roles is distinct from old.roles and exists (
    select 1 from private.customer_mfa_recovery r join auth.mfa_factors f
      on f.user_id=r.user_id and f.id=any(r.factor_ids) where r.user_id=old.id
  ) then raise exception 'customer_recovery_pending' using errcode='PT409'; end if;
  return new;
end $$;
revoke all on function private.guard_customer_recovery_role() from public,anon,authenticated,service_role;
create trigger customer_recovery_role_guard before update of roles on public.profiles
  for each row execute function private.guard_customer_recovery_role();

-- One caller-bound endpoint: inspect an exact UUID, prepare a verified case, or
-- revalidate the same recovery before each external removal. No email authority.
create function public.customer_mfa_recovery_request(
  action text, target_user_id uuid, support_case text default null,
  identity_verified boolean default false, expected_recovery_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  before_context jsonb; actor uuid; session_started timestamptz;
  r private.customer_mfa_recovery%rowtype; ids uuid[]; remaining uuid[];
  actor_name text;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if before_context->>'role' is distinct from 'Owner' or target_user_id is null
    or target_user_id=actor then raise exception 'recovery_forbidden' using errcode='PT403'; end if;
  if action is null or action not in ('inspect','prepare','authorize') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  -- Follow auth -> profile lock order; deterministic order also covers two Owners.
  perform 1 from auth.users where id in (actor,target_user_id) order by id for share;
  perform 1 from public.profiles where id in (actor,target_user_id) order by id for no key update;
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'recovery_forbidden' using errcode='PT403';
  end if;
  select s.created_at into session_started from auth.sessions s
    where s.id=(auth.jwt()->>'session_id')::uuid and s.user_id=actor;
  if session_started is null or session_started <= clock_timestamp()-interval '10 minutes'
    or session_started > clock_timestamp() then
    raise exception 'fresh_sign_in_required' using errcode='PT403';
  end if;
  if not exists (select 1 from public.profiles p join auth.users u on u.id=p.id
    where p.id=target_user_id and p.roles::text='User' and u.is_anonymous is false
      and u.email_confirmed_at is not null and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= clock_timestamp()))
    or exists (select 1 from private.account_lifecycle l where l.user_id=target_user_id and l.restored_at is null) then
    raise exception 'recovery_target_unavailable' using errcode='PT403';
  end if;
  if exists (select 1 from auth.mfa_factors f where f.user_id=target_user_id
    and (f.factor_type::text is distinct from 'totp' or f.status::text not in ('unverified','verified'))) then
    raise exception 'unsupported_factor' using errcode='PT403';
  end if;
  select * into r from private.customer_mfa_recovery where user_id=target_user_id;
  if action='prepare' then
    if identity_verified is distinct from true or support_case is null
      or support_case <> btrim(support_case) or length(support_case) not between 1 and 120
      or support_case ~ '[[:cntrl:]]' then raise exception 'invalid_request' using errcode='22023'; end if;
    if r.user_id is not null and r.support_case=support_case then
      null; -- Exact case replay never expands the captured factor set.
    else
      if r.user_id is not null and exists (select 1 from auth.mfa_factors f
        where f.user_id=target_user_id and f.id=any(r.factor_ids)) then
        raise exception 'customer_recovery_pending' using errcode='PT409';
      end if;
      if not exists (select 1 from auth.mfa_factors f where f.user_id=target_user_id
        and f.status::text='verified' and f.factor_type::text='totp') then
        raise exception 'recovery_target_unavailable' using errcode='PT403';
      end if;
      select array_agg(f.id order by f.id) into ids from auth.mfa_factors f where f.user_id=target_user_id;
      if cardinality(ids)>10 then raise exception 'unsupported_factor' using errcode='PT403'; end if;
      insert into private.customer_mfa_recovery(user_id,actor_id,support_case,factor_ids)
        values(target_user_id,actor,support_case,ids)
      on conflict(user_id) do update set recovery_id=gen_random_uuid(),actor_id=excluded.actor_id,
        support_case=excluded.support_case,started_at=clock_timestamp(),factor_ids=excluded.factor_ids
      returning * into r;
      select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
      insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,after_values)
        values(actor,actor_name,'customer_mfa_recovery',target_user_id::text,'verified_recovery_started',
          jsonb_build_object('recovery_id',r.recovery_id,'support_case',r.support_case,
            'externally_verified',true,'reenrollment_required',true,'factor_count',cardinality(r.factor_ids)));
    end if;
  elsif action='authorize' and (r.recovery_id is null or expected_recovery_id is distinct from r.recovery_id) then
    raise exception 'recovery_conflict' using errcode='PT409';
  end if;
  select coalesce(array_agg(f.id order by f.id),'{}'::uuid[]) into remaining
    from auth.mfa_factors f where f.user_id=target_user_id and f.id=any(r.factor_ids);
  if action='authorize' and cardinality(remaining)>0 then
    select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,after_values)
      values(actor,actor_name,'customer_mfa_recovery',target_user_id::text,'factor_removal_authorized',
        jsonb_build_object('recovery_id',r.recovery_id,'support_case',r.support_case,
          'remaining_factor_count',cardinality(remaining)));
  end if;
  -- Recheck after audit INSERT/trigger waits as well as initial profile locks.
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'recovery_forbidden' using errcode='PT403';
  end if;
  if not exists (select 1 from auth.sessions s where s.id=(auth.jwt()->>'session_id')::uuid
    and s.user_id=actor and s.created_at>clock_timestamp()-interval '10 minutes'
    and s.created_at<=clock_timestamp()) then
    raise exception 'fresh_sign_in_required' using errcode='PT403';
  end if;
  return jsonb_build_object('target_user_id',target_user_id,'recovery_id',r.recovery_id,
    'support_case',r.support_case,'reenrollment_required',r.user_id is not null,
    'remaining_factor_ids',remaining,'state',case when r.user_id is null then 'not_started'
      when cardinality(remaining)>0 then 'removal_pending' else 'reenrollment_required' end);
end $$;
revoke all on function public.customer_mfa_recovery_request(text,uuid,text,boolean,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.customer_mfa_recovery_request(text,uuid,text,boolean,uuid) to authenticated;
commit;
