-- REVIEW-ONLY LOCAL CANDIDATE. DO NOT APPLY TO PRODUCTION.
-- Final campaign policy/version approval and lifecycle/MFA gate integration
-- are release dependencies. The draft below is NOT approved legal policy.
-- No backfill, automatic consent, newsletter enrollment, or lifecycle changes.
begin;

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

commit;
