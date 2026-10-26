-- LOCAL ONLY. No sender, provider credentials, campaigns or deployment.
begin;

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
commit;
