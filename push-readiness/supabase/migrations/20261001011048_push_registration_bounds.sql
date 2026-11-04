-- Apply after the accepted push registration contract. No sender or row backfill.
begin;

do $$
begin
  if to_regprocedure('public.prepare_push_installation(uuid,uuid)') is null
    or to_regprocedure('public.register_push_token(uuid,uuid,text,text,text)') is null
    or to_regprocedure('public.revoke_push_installation(uuid,uuid)') is null
    or to_regprocedure('public.get_admission_status()') is null
    or not exists (select 1 from pg_class
      where oid = 'private.push_installations'::regclass and relrowsecurity) then
    raise exception 'Reviewed push registration and admission prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- Revocation still clears the operational user/session fields. This private
-- anchor preserves existing Auth-session cascade cleanup for retired slots too.
-- Existing rows remain untouched; their next registration/revocation fills it.
alter table private.push_installations add column cleanup_session_id uuid
  references auth.sessions(id) on delete cascade;
create index push_installations_user_state on private.push_installations(user_id, revoked);
create index push_installations_session on private.push_installations(session_id);
create index push_installations_cleanup_session on private.push_installations(cleanup_session_id);

-- One fixed creation budget per account, independent of erased installation
-- ownership and session rotation. Not a generic limiter or sending permission.
create table private.push_creation_budget (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  creations integer not null check (creations between 0 and 20)
);
alter table private.push_creation_budget enable row level security;
revoke all on private.push_creation_budget from public, anon, authenticated,
  service_role, supabase_auth_admin;

create or replace function public.prepare_push_installation(p_installation uuid, p_secret uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  caller uuid;
  caller_session uuid;
  capability bytea;
  existing private.push_installations%rowtype;
  budget private.push_creation_budget%rowtype;
  checked_at timestamptz;
begin
  if p_installation is null or p_secret is null then
    raise exception 'invalid_request' using errcode = '22023';
  end if;
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller := auth.uid();
  caller_session := (auth.jwt()->>'session_id')::uuid;
  capability := sha256(convert_to(p_secret::text, 'UTF8'));
  -- Same order as registration/deletion; serializes per-account admission and cap.
  perform 1 from auth.users where id = caller for share;
  perform 1 from public.profiles where id = caller for no key update;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  select * into existing from private.push_installations
    where installation = p_installation for update;
  if found then
    if existing.secret_hash is distinct from capability
      or existing.user_id is distinct from caller or existing.revoked
      or public.get_admission_status()->>'next_step' is distinct from 'home' then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    return; -- Valid prepare replay consumes neither capacity nor creation budget.
  end if;
  if (select count(*) from (select 1 from private.push_installations
        where user_id = caller and not revoked limit 16) live) >= 16 then
    raise exception 'push_capacity_reached' using errcode = 'PT429';
  end if;
  insert into private.push_creation_budget(user_id, window_started_at, creations)
    values(caller, clock_timestamp(), 0) on conflict do nothing;
  select * into strict budget from private.push_creation_budget
    where user_id = caller for update;
  checked_at := clock_timestamp();
  if checked_at >= budget.window_started_at + interval '1 hour' then
    budget.window_started_at := checked_at;
    budget.creations := 0;
  end if;
  if budget.creations >= 20 then
    raise exception 'push_creation_limited' using errcode = 'PT429';
  end if;
  update private.push_creation_budget set window_started_at = budget.window_started_at,
    creations = budget.creations + 1 where user_id = caller;
  insert into private.push_installations(installation, secret_hash, user_id, session_id, cleanup_session_id)
    values(p_installation, capability, caller, caller_session, caller_session)
    on conflict do nothing;
  if not found then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  -- Includes waits on budget, collision and trusted INSERT triggers; failure
  -- rolls back the new slot and its budget charge together.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
exception
  when sqlstate 'PT401' or sqlstate 'PT403' or sqlstate 'PT429' or sqlstate '22023' then raise;
  when others then raise exception 'push_unavailable' using errcode = 'PT503';
end;
$$;

create or replace function public.register_push_token(p_installation uuid, p_secret uuid,
  p_environment text, p_platform text, p_token text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  caller uuid;
  session uuid;
  capability bytea;
begin
  if p_installation is null or p_secret is null or p_environment is null
    or p_environment not in ('dev','prod') or p_platform is null
    or p_platform not in ('android','ios') or p_token is null
    or length(p_token) not between 20 and 4096 then
    raise exception 'invalid_request' using errcode = '22023';
  end if;
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller := auth.uid();
  session := (auth.jwt()->>'session_id')::uuid;
  perform 1 from auth.users u where u.id = caller for share;
  perform 1 from public.profiles p where p.id = caller for no key update;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  capability := sha256(convert_to(p_secret::text, 'UTF8'));
  update private.push_installations as target set
    session_id = session, cleanup_session_id = session, token = p_token,
    environment = p_environment, platform = p_platform, updated_at = clock_timestamp()
  where target.installation = p_installation and not target.revoked
    and target.secret_hash = capability and target.user_id = caller
    and (target.environment is null or target.environment = p_environment)
    and (target.platform is null or target.platform = p_platform);
  if not found or public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
exception
  when sqlstate 'PT401' or sqlstate 'PT403' or sqlstate '22023' then raise;
  when others then raise exception 'push_unavailable' using errcode = 'PT503';
end;
$$;

create or replace function public.revoke_push_installation(p_installation uuid, p_secret uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_installation is null or p_secret is null then
    raise exception 'invalid_request' using errcode = '22023';
  end if;
  update private.push_installations as target set
    cleanup_session_id = coalesce(target.cleanup_session_id, target.session_id),
    revoked = true, token = null, user_id = null, session_id = null,
    updated_at = clock_timestamp()
  where target.installation = p_installation
    and target.secret_hash = sha256(convert_to(p_secret::text, 'UTF8'))
    and (not target.revoked or target.user_id is not null or target.session_id is not null or target.token is not null);
end;
$$;

-- CREATE OR REPLACE preserves existing RPC ACLs; never regrant a service bypass.
commit;
