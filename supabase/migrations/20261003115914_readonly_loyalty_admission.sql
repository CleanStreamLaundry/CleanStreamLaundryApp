begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $$
begin
  if to_regprocedure('public.get_loyalty_policy_status()') is null
    or to_regprocedure('private.account_access_allowed()') is null then
    raise exception 'Existing loyalty admission readers required' using errcode = '55000';
  end if;
end;
$$;

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
  -- PostgREST GET uses READ ONLY. Preserve Auth-before-profile locking for
  -- mutation transactions, while SELECT policies use their normal MVCC snapshot.
  if current_setting('transaction_read_only') = 'off' then
    perform 1 from auth.users u where u.id = caller_id for share;
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
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

commit;
