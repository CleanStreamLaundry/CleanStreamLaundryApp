-- GENERATED two-source DEVELOPMENT push registration install only.
-- Target dnuuhupoxjtwqzaqylvb. Requires BOTH push tables absent, not a replay path.
-- Reuses installed admission/lifecycle; no sender, backfill, schedule or retention purge.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
-- SOURCE 20260930130013_push_token_registration.sql SHA256 ec3075684bd75c87978ef0ed44b77f970d656b906c2c33ba95e037985010b657
-- LOCAL ONLY. No sender, provider credentials, campaigns or deployment.


create table private.push_installations (
  installation uuid primary key,
  secret_hash bytea not null,
  user_id uuid references auth.users(id) on delete cascade,
  session_id uuid references auth.sessions(id) on delete cascade,
  environment text check (environment in ('dev','prod')),
  platform text check (platform in ('android','ios')),
  token text check (length(token) between 20 and 4096),
  updated_at timestamptz not null default clock_timestamp(),
  revoked boolean not null default false,
  check (revoked or (user_id is not null and session_id is not null))
);
create unique index push_installations_active_token
  on private.push_installations(environment, token) where not revoked;
alter table private.push_installations enable row level security;
revoke all on private.push_installations from public, anon, authenticated,
  service_role, supabase_auth_admin;

-- Prepare an empty slot under canonical admission before any token is sent.
-- Anonymous cleanup only updates known slots, preventing arbitrary row creation.
create function public.prepare_push_installation(p_installation uuid, p_secret uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_installation is null or p_secret is null then
    raise exception 'invalid_request' using errcode = '22023';
  end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  insert into private.push_installations(installation,secret_hash,user_id,session_id)
    values(p_installation,sha256(convert_to(p_secret::text,'UTF8')),
      auth.uid(),(auth.jwt()->>'session_id')::uuid) on conflict do nothing;
  if not exists(select 1 from private.push_installations p where
    p.installation=p_installation and p.secret_hash=sha256(convert_to(p_secret::text,'UTF8'))
    and p.user_id=auth.uid() and not p.revoked) then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
end;
$$;

create function public.register_push_token(p_installation uuid, p_secret uuid,
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
  -- Preserve the shared Auth -> profile lock order and canonical authority.
  perform 1 from auth.users u where u.id = caller for share;
  perform 1 from public.profiles p where p.id = caller for no key update;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  capability := sha256(convert_to(p_secret::text, 'UTF8'));
  update private.push_installations as target set
    session_id = session, token = p_token, environment = p_environment,
    platform = p_platform, updated_at = clock_timestamp()
  where target.installation = p_installation and not target.revoked
    and target.secret_hash = capability and target.user_id = caller
    and (target.environment is null or target.environment = p_environment)
    and (target.platform is null or target.platform = p_platform);
  if not found or not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
exception
  when sqlstate 'PT401' or sqlstate 'PT403' or sqlstate '22023' then raise;
  when others then raise exception 'push_unavailable' using errcode = 'PT503';
end;
$$;

-- A random 122-bit capability can only revoke its own installation. This
-- deliberately remains usable after logout/session revocation and never reads.
create function public.revoke_push_installation(p_installation uuid, p_secret uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_installation is null or p_secret is null then
    raise exception 'invalid_request' using errcode = '22023';
  end if;
  update private.push_installations as target set
    revoked = true, token = null, user_id = null, session_id = null,
    updated_at = clock_timestamp()
  where target.installation = p_installation
    and target.secret_hash = sha256(convert_to(p_secret::text, 'UTF8'));
end;
$$;

create function private.revoke_lifecycle_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.restored_at is null then
    update private.push_installations set revoked = true, token = null,
      updated_at = clock_timestamp() where user_id = new.user_id and not revoked;
  end if;
  return new;
end;
$$;
create trigger revoke_lifecycle_push after insert or update on private.account_lifecycle
  for each row execute function private.revoke_lifecycle_push();

revoke all on function public.prepare_push_installation(uuid,uuid),
  public.register_push_token(uuid,uuid,text,text,text),
  public.revoke_push_installation(uuid,uuid), private.revoke_lifecycle_push()
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.register_push_token(uuid,uuid,text,text,text) to authenticated;
grant execute on function public.prepare_push_installation(uuid,uuid) to authenticated;
grant execute on function public.revoke_push_installation(uuid,uuid) to anon, authenticated;


-- SOURCE 20261001011048_push_registration_bounds.sql SHA256 aab8796f25db121884c828adff41cb3c26fe00975b290894565287540d97ffea
-- Apply after the accepted push registration contract. No sender or row backfill.


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


DO $$
BEGIN
  IF has_function_privilege('anon', 'public.request_account_deletion()', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.request_account_deletion()', 'EXECUTE')
    OR has_function_privilege('service_role', 'public.request_account_deletion()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Deletion containment drift; push install aborted' USING ERRCODE = '55000';
  END IF;
END;
$$;
COMMIT;
