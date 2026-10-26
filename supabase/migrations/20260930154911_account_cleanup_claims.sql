-- LOCAL ONLY. A lease is not authority to erase data. The Edge executor rejects
-- unapproved policy before claiming. No schedule, provider call or completed state.
begin;

do $$ begin
  if to_regprocedure('public.restore_account()') is null
    or to_regclass('private.account_lifecycle') is null then
    raise exception 'Reviewed account recovery prerequisite required' using errcode = '55000';
  end if;
end $$;

-- One bounded record per account. A new lifecycle request replaces the prior
-- request's lease state; the exact timestamp fences delayed work from that request.
create table private.account_cleanup_jobs (
  user_id uuid primary key references private.account_lifecycle(user_id),
  deletion_requested_at timestamptz not null,
  claim_id uuid not null unique,
  attempts integer not null check (attempts between 1 and 5),
  used_claim_ids uuid[] not null check (cardinality(used_claim_ids) = attempts),
  state text not null check (state in ('leased', 'retry', 'outcome_unknown')),
  lease_until timestamptz not null,
  retry_after timestamptz not null
);
alter table private.account_cleanup_jobs enable row level security;
revoke all on private.account_cleanup_jobs from public, anon, authenticated,
  service_role, supabase_auth_admin;

create function public.preview_account_cleanup(p_limit integer default 25, p_after_user_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone = 'UTC' as $$
declare result jsonb;
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', x.user_id, 'deletion_requested_at', x.deletion_requested_at,
    'restore_until', x.restore_until, 'blocker', x.blocker,
    'eligible_to_claim', x.blocker is null) order by x.user_id), '[]'::jsonb)
  into result from (
    select l.user_id, l.deletion_requested_at, l.restore_until,
        case when c.state = 'outcome_unknown' then 'outcome_unknown'
          when c.state = 'leased' and c.lease_until > clock_timestamp() then 'lease_active'
          when c.attempts >= 5 then 'retry_exhausted'
          when c.retry_after > clock_timestamp() then 'retry_wait' end as blocker
    from private.account_lifecycle l
    left join private.account_cleanup_jobs c on c.user_id = l.user_id
      and c.deletion_requested_at = l.deletion_requested_at
    where l.restored_at is null and l.restore_until <= clock_timestamp()
      and (p_after_user_id is null or l.user_id > p_after_user_id)
    order by l.user_id limit p_limit
  ) x;
  return jsonb_build_object('execution_enabled', false, 'candidates', result,
    'next_cursor', case when jsonb_array_length(result) = p_limit
      then result->(p_limit - 1)->>'user_id' else null end);
end $$;

create function public.claim_account_cleanup(p_user_id uuid, p_requested_at timestamptz, p_claim_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone = 'UTC' as $$
declare
  reason text;
  lifecycle private.account_lifecycle%rowtype;
  prior private.account_cleanup_jobs%rowtype;
  claimed private.account_cleanup_jobs%rowtype;
begin
  if p_user_id is null or p_requested_at is null or p_claim_id is null then
    raise exception 'invalid_claim' using errcode = '22023';
  end if;
  -- Same Auth -> profile -> lifecycle order as request/restore. Wall-clock
  -- eligibility is re-evaluated after every potentially blocking lock below.
  perform 1 from auth.users where id = p_user_id for share;
  if not found then return jsonb_build_object('claimed', false, 'reason', 'request_not_pending'); end if;
  perform 1 from public.profiles where id = p_user_id for no key update;
  if not found then return jsonb_build_object('claimed', false, 'reason', 'request_not_pending'); end if;
  select * into lifecycle from private.account_lifecycle where user_id = p_user_id for update;
  select * into prior from private.account_cleanup_jobs where user_id = p_user_id for update;
  reason := case when lifecycle.user_id is null
      or lifecycle.deletion_requested_at is distinct from p_requested_at
      or lifecycle.restored_at is not null then 'request_not_pending'
    when lifecycle.restore_until > clock_timestamp() then 'recovery_window_open' end;
  if reason is not null then return jsonb_build_object('claimed', false, 'reason', reason); end if;
  if prior.deletion_requested_at is distinct from p_requested_at then prior := null; end if;
  if prior.state = 'leased' and prior.lease_until > clock_timestamp() then
    if prior.claim_id = p_claim_id then
      return jsonb_build_object('claimed', true, 'execution_enabled', false, 'claim', to_jsonb(prior) - 'used_claim_ids');
    end if;
    return jsonb_build_object('claimed', false, 'reason', 'lease_active');
  end if;
  reason := case when prior.state = 'outcome_unknown' then 'outcome_unknown'
    when prior.attempts >= 5 then 'retry_exhausted'
    when prior.retry_after > clock_timestamp() then 'retry_wait'
    when p_claim_id = any(prior.used_claim_ids) then 'claim_id_reused' end;
  if reason is not null then return jsonb_build_object('claimed', false, 'reason', reason); end if;
  insert into private.account_cleanup_jobs
    (user_id, deletion_requested_at, claim_id, attempts, used_claim_ids, state, lease_until, retry_after)
  values (p_user_id, p_requested_at, p_claim_id,
    coalesce(prior.attempts, 0) + 1, array_append(coalesce(prior.used_claim_ids, '{}'::uuid[]), p_claim_id), 'leased',
    clock_timestamp() + interval '5 minutes', clock_timestamp())
  on conflict (user_id) do update set
    deletion_requested_at = excluded.deletion_requested_at, claim_id = excluded.claim_id,
    attempts = excluded.attempts, used_claim_ids = excluded.used_claim_ids,
    state = excluded.state, lease_until = excluded.lease_until,
    retry_after = excluded.retry_after
  returning * into claimed;
  return jsonb_build_object('claimed', true, 'execution_enabled', false, 'claim', to_jsonb(claimed) - 'used_claim_ids');
end $$;

-- Token-fenced release. Unknown outcomes stay parked, never treated as success
-- or automatically replayed. No approval workflow or arbitrary error/PII logs.
create function public.retry_account_cleanup(p_user_id uuid, p_requested_at timestamptz,
  p_claim_id uuid, p_failure text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  prior private.account_cleanup_jobs%rowtype;
  next_state text;
begin
  if p_failure is null or p_failure not in ('transient_failure', 'outcome_unknown') then
    raise exception 'invalid_failure' using errcode = '22023';
  end if;
  perform 1 from auth.users where id = p_user_id for share;
  perform 1 from public.profiles where id = p_user_id for no key update;
  perform 1 from private.account_lifecycle where user_id = p_user_id for update;
  if not exists (select 1 from private.account_lifecycle where user_id = p_user_id
    and deletion_requested_at = p_requested_at and restored_at is null
    and restore_until <= clock_timestamp()) then
    return jsonb_build_object('released', false, 'reason', 'request_not_pending');
  end if;
  select * into prior from private.account_cleanup_jobs
    where user_id = p_user_id and deletion_requested_at = p_requested_at for update;
  if not found or prior.claim_id is distinct from p_claim_id then
    return jsonb_build_object('released', false, 'reason', 'stale_claim');
  end if;
  next_state := case when p_failure = 'outcome_unknown' then 'outcome_unknown' else 'retry' end;
  if prior.state = next_state then
    return jsonb_build_object('released', true, 'state', prior.state);
  end if;
  if prior.state <> 'leased' or prior.lease_until <= clock_timestamp() then
    return jsonb_build_object('released', false, 'reason', 'stale_claim');
  end if;
  update private.account_cleanup_jobs set
    state = next_state,
    lease_until = clock_timestamp(),
    retry_after = clock_timestamp() + make_interval(secs => 60 * (2 ^ (attempts - 1))::integer)
    where user_id = p_user_id and deletion_requested_at = p_requested_at
    returning * into prior;
  return jsonb_build_object('released', true, 'state', prior.state);
end $$;

revoke all on function public.preview_account_cleanup(integer,uuid), public.claim_account_cleanup(uuid,timestamptz,uuid),
  public.retry_account_cleanup(uuid,timestamptz,uuid,text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.preview_account_cleanup(integer,uuid),
  public.claim_account_cleanup(uuid,timestamptz,uuid),
  public.retry_account_cleanup(uuid,timestamptz,uuid,text) to service_role;
commit;
