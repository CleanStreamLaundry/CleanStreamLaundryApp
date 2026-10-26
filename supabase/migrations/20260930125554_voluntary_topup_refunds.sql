-- Local candidate only. No historical provenance backfill or provider calls.
begin;

do $$
begin
  if to_regprocedure('private.current_account_access()') is null
    or to_regclass('private.account_lifecycle') is null
    or not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.profiles'::regclass
      and tgname='profiles_protected_fields_guard' and tgenabled in ('O','A'))
    or not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public."Location_to_Admin"'::regclass
      and tgname='location_membership_writes_guard' and tgenabled='A') then
    raise exception 'Reviewed financial, admission, lifecycle and location authority prerequisites required'
      using errcode='55000';
  end if;
end;
$$;

create table private.topup_refund_policy (
  version text primary key check (version = 'unused-topup-v1'),
  enabled_at timestamptz not null default clock_timestamp()
);
insert into private.topup_refund_policy(version) values ('unused-topup-v1');

create table private.topup_refund_provenance (
  load_id bigint primary key references public.wallet_loads(id),
  recorded_at timestamptz not null default clock_timestamp(),
  reward_before_cents integer not null check (reward_before_cents between 0 and 1999),
  payment_succeeded_at timestamptz,
  stripe_event_id text unique,
  livemode boolean,
  location_id bigint references public."Locations"(id)
);
create table private.topup_refund_spend (
  ledger_id bigint primary key references public.wallet_ledger_entries(id),
  wallet_id uuid not null references public.wallet_accounts(id),
  spent_at timestamptz not null default clock_timestamp()
);
create index on private.topup_refund_spend(wallet_id, spent_at);

create table private.voluntary_topup_refunds (
  id uuid primary key default gen_random_uuid(),
  load_id bigint not null unique references public.wallet_loads(id),
  wallet_id uuid not null references public.wallet_accounts(id),
  customer_id uuid not null references public.profiles(id),
  location_id bigint references public."Locations"(id),
  policy_version text not null default 'unused-topup-v1' references private.topup_refund_policy(version),
  requested_at timestamptz not null,
  payment_succeeded_at timestamptz not null,
  principal_cents integer not null check (principal_cents > 0),
  bonus_reserved_cents integer not null check (bonus_reserved_cents >= 0),
  stripe_payment_intent_id text not null unique,
  livemode boolean not null,
  status text not null default 'requested' check (status in
    ('requested','approved','unknown','pending','succeeded','failed','canceled','denied')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  dispatch_started_at timestamptz,
  provider_refund_id text unique,
  provider_checked_at timestamptz,
  released_at timestamptz,
  completed_at timestamptz,
  check (requested_at between payment_succeeded_at and payment_succeeded_at + interval '48 hours')
);
alter table public.wallet_ledger_entries add column voluntary_topup_refund_id uuid
  references private.voluntary_topup_refunds(id);
create index on public.wallet_ledger_entries(voluntary_topup_refund_id)
  where voluntary_topup_refund_id is not null;

alter table private.topup_refund_policy enable row level security;
alter table private.topup_refund_provenance enable row level security;
alter table private.topup_refund_spend enable row level security;
alter table private.voluntary_topup_refunds enable row level security;
revoke all on private.topup_refund_policy, private.topup_refund_provenance,
  private.topup_refund_spend, private.voluntary_topup_refunds
  from public, anon, authenticated, service_role, supabase_auth_admin;

create function private.capture_topup_refund_provenance()
returns trigger language plpgsql security definer set search_path = '' as $$
declare reward integer;
begin
  perform 1 from public.wallet_accounts where id = new.wallet_account_id for no key update;
  select round(reward_tracker * 100)::integer into reward from public.profiles where id = new.user_id;
  -- Bad/legacy reward state must not prevent already-captured funding settlement.
  if reward between 0 and 1999 and new.status = 'succeeded'
    and new.paid_amount_cents = new.amount_cents
    and new.promo_amount_cents = ((reward::bigint + new.amount_cents) / 2000) * 500 then
    insert into private.topup_refund_provenance(load_id,reward_before_cents) values(new.id,reward);
  end if;
  return new;
end;
$$;
create trigger capture_topup_refund_provenance after insert on public.wallet_loads
  for each row execute function private.capture_topup_refund_provenance();

create function private.capture_topup_refund_spend()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Same lock as the nine accepted financial routines, before recording time.
  perform 1 from public.wallet_accounts where id = new.wallet_account_id for no key update;
  if new.voluntary_topup_refund_id is null
    and (new.paid_amount_cents < 0 or new.promo_amount_cents < 0) then
    insert into private.topup_refund_spend(ledger_id,wallet_id) values(new.id,new.wallet_account_id);
  end if;
  return new;
end;
$$;
create trigger capture_topup_refund_spend after insert on public.wallet_ledger_entries
  for each row execute function private.capture_topup_refund_spend();

-- Only a verified payment_intent.succeeded event may supply this evidence.
-- Checkout creation, Charge creation and load insertion are not success clocks.
create function public.record_topup_refund_provenance(
  p_intent text, p_user uuid, p_amount integer, p_succeeded_at timestamptz,
  p_event text, p_livemode boolean, p_location bigint default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare l public.wallet_loads%rowtype; p private.topup_refund_provenance%rowtype;
begin
  select * into l from public.wallet_loads where stripe_payment_intent_id = p_intent;
  if not found then return false; end if;
  perform 1 from public.wallet_accounts where id = l.wallet_account_id for no key update;
  select * into p from private.topup_refund_provenance where load_id = l.id for update;
  if not found then return false; end if;
  if l.user_id is distinct from p_user or l.paid_amount_cents is distinct from p_amount
    or p_succeeded_at is null or p_livemode is null or p_event is null or p_event !~ '^evt_'
    or p_succeeded_at > clock_timestamp()
    or p_succeeded_at < (select enabled_at from private.topup_refund_policy)
    or (p_location is not null and not exists(select 1 from public."Locations" where id=p_location)) then
    return false;
  end if;
  if p.payment_succeeded_at is not null then
    return p.payment_succeeded_at = p_succeeded_at and p.livemode = p_livemode
      and p.location_id is not distinct from p_location;
  end if;
  update private.topup_refund_provenance set payment_succeeded_at=p_succeeded_at,
    stripe_event_id=p_event, livemode=p_livemode, location_id=p_location where load_id=l.id;
  return true;
end;
$$;

create function private.topup_refund_identity()
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare a jsonb;
begin
  a := private.current_account_access();
  -- This exception is local to refund RPCs, never ordinary account admission.
  if a->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  return (a->>'subject_id')::uuid;
end;
$$;

create function private.topup_refund_owner(p_location bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not private.account_access_allowed() or not exists (
    select 1 from public.profiles where id=auth.uid() and roles='Owner'
  ) then raise exception 'owner_required' using errcode='PT403'; end if;
  -- Wallet funding currently has global (null) scope. Never infer a location
  -- from customer address or accept a reviewer-supplied location override.
  if p_location is not null then
    perform 1 from public."Location_to_Admin" where user_id=auth.uid() and location_id=p_location for share;
    if not found then raise exception 'location_forbidden' using errcode='PT403'; end if;
  end if;
end;
$$;

create function private.topup_refund_wire(r private.voluntary_topup_refunds)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id',r.id,'load_id',r.load_id::text,'customer_id',r.customer_id,'status',r.status,
    'principal_cents',r.principal_cents,'bonus_reserved_cents',r.bonus_reserved_cents,
    'currency','usd','requested_at',r.requested_at,'payment_succeeded_at',r.payment_succeeded_at,
    'reviewed_at',r.reviewed_at,'completed_at',r.completed_at,'policy_version',r.policy_version,
    'location_id',r.location_id::text,'review_note',r.review_note);
$$;

create function public.request_voluntary_topup_refund(p_load_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone='UTC' as $$
declare
  caller uuid; received timestamptz := statement_timestamp();
  l public.wallet_loads%rowtype; p private.topup_refund_provenance%rowtype;
  r private.voluntary_topup_refunds%rowtype; reward integer; bonus integer;
begin
  caller := private.topup_refund_identity();
  perform 1 from auth.users where id=caller for share;
  select * into l from public.wallet_loads where id=p_load_id and user_id=caller;
  if not found then raise exception 'topup_unavailable' using errcode='PT404'; end if;
  perform 1 from public.wallet_accounts where id=l.wallet_account_id and user_id=caller for no key update;
  if not found then raise exception 'topup_unavailable' using errcode='PT404'; end if;
  perform 1 from public.profiles where id=caller for no key update;
  perform private.topup_refund_identity();
  select * into r from private.voluntary_topup_refunds where load_id=l.id;
  if found then return private.topup_refund_wire(r); end if;
  select * into p from private.topup_refund_provenance where load_id=l.id;
  if not found or p.payment_succeeded_at is null or l.stripe_payment_intent_id is null
    or l.status <> 'succeeded' then
    raise exception 'provenance_unavailable' using errcode='PT409';
  end if;
  if received < p.payment_succeeded_at or received > p.payment_succeeded_at + interval '48 hours' then
    raise exception 'refund_window_closed' using errcode='PT409';
  end if;
  if exists(select 1 from private.topup_refund_spend where wallet_id=l.wallet_account_id
    and spent_at >= p.payment_succeeded_at) then
    raise exception 'wallet_used_after_topup' using errcode='PT409';
  end if;
  select round(reward_tracker*100)::integer into reward from public.profiles where id=caller;
  if reward is null or reward not between 0 and 1999 then
    raise exception 'reward_provenance_unavailable' using errcode='PT409';
  end if;
  -- Remove this contribution from cumulative progress, not its original bonus
  -- row: later loads may have crossed a threshold using this load's remainder.
  bonus := ceil((l.paid_amount_cents::numeric - reward) / 2000)::integer * 500;
  if not exists(select 1 from public.wallet_balances where wallet_account_id=l.wallet_account_id
    and paid_balance_cents >= l.paid_amount_cents and promo_balance_cents >= bonus) then
    raise exception 'refund_funds_unavailable' using errcode='PT409';
  end if;
  insert into private.voluntary_topup_refunds(load_id,wallet_id,customer_id,location_id,
    requested_at,payment_succeeded_at,principal_cents,bonus_reserved_cents,stripe_payment_intent_id,livemode)
  values(l.id,l.wallet_account_id,caller,p.location_id,received,p.payment_succeeded_at,
    l.paid_amount_cents,bonus,l.stripe_payment_intent_id,p.livemode) returning * into r;
  insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
    paid_amount_cents,promo_amount_cents,wallet_load_id,voluntary_topup_refund_id,note)
  values(l.wallet_account_id,'admin_adjustment',-l.paid_amount_cents-bonus,
    -l.paid_amount_cents,-bonus,l.id,r.id,'Voluntary top-up refund reservation, not a payout');
  update public.profiles set reward_tracker =
    (reward::bigint-l.paid_amount_cents+(bonus::bigint/500)*2000)::numeric/100 where id=caller;
  perform public.sync_profile_wallet_balance(l.wallet_account_id);
  return private.topup_refund_wire(r);
end;
$$;

create function public.list_voluntary_topup_refunds(p_before timestamptz default null, p_before_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone='UTC' as $$
declare caller uuid;
begin
  caller := private.topup_refund_identity();
  return (select coalesce(jsonb_agg(private.topup_refund_wire(r) order by r.requested_at desc,r.id desc),'[]')
    from (select * from private.voluntary_topup_refunds where customer_id=caller
      and (p_before is null or requested_at < p_before or (requested_at=p_before and id<p_before_id))
      order by requested_at desc,id desc limit 100) r);
end;
$$;

create function private.release_topup_refund(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r private.voluntary_topup_refunds%rowtype; reward integer; bonus integer;
begin
  select * into r from private.voluntary_topup_refunds where id=p_id;
  if r.released_at is not null then return; end if;
  select round(reward_tracker*100)::integer into reward from public.profiles where id=r.customer_id for no key update nowait;
  if reward is null or reward not between 0 and 1999 then
    raise exception 'reward_provenance_unavailable' using errcode='PT409';
  end if;
  bonus := ((reward::bigint+r.principal_cents)/2000)*500;
  insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
    paid_amount_cents,promo_amount_cents,wallet_load_id,voluntary_topup_refund_id,note)
  values(r.wallet_id,'admin_adjustment',r.principal_cents+bonus,r.principal_cents,bonus,
    r.load_id,r.id,'Voluntary top-up refund reservation released');
  update public.profiles set reward_tracker=((reward::bigint+r.principal_cents)%2000)::numeric/100 where id=r.customer_id;
  update private.voluntary_topup_refunds set released_at=clock_timestamp() where id=p_id;
  perform public.sync_profile_wallet_balance(r.wallet_id);
end;
$$;

-- Advisory eligibility only. Request rechecks under the shared wallet lock.
-- Pending deletion can list its own funding without reopening wallet APIs.
create function public.list_voluntary_topup_refund_topups(p_before_load_id bigint default null)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone='UTC' as $$
declare caller uuid;
begin
  caller := private.topup_refund_identity();
  return (select coalesce(jsonb_agg(item order by load_id desc),'[]') from (
    select l.id as load_id, jsonb_build_object('load_id',l.id::text,
      'principal_cents',l.paid_amount_cents,'currency','usd',
      'payment_succeeded_at',p.payment_succeeded_at,
      'request_deadline',p.payment_succeeded_at+interval '48 hours',
      'refund',case when r.id is not null then private.topup_refund_wire(r) else null end,
      'ineligible_reason',case
        when r.id is not null then 'already_requested'
        when p.payment_succeeded_at is null or l.stripe_payment_intent_id is null or l.status<>'succeeded'
          then 'provenance_unavailable'
        when statement_timestamp()<p.payment_succeeded_at
          or statement_timestamp()>p.payment_succeeded_at+interval '48 hours' then 'refund_window_closed'
        when exists(select 1 from private.topup_refund_spend s where s.wallet_id=l.wallet_account_id
          and s.spent_at>=p.payment_succeeded_at) then 'wallet_used_after_topup'
        when round(profile.reward_tracker*100) not between 0 and 1999 or profile.reward_tracker is null
          then 'reward_provenance_unavailable'
        when b.paid_balance_cents<l.paid_amount_cents or b.promo_balance_cents<
          ceil((l.paid_amount_cents::numeric-round(profile.reward_tracker*100))/2000)*500
          then 'refund_funds_unavailable'
        else null end) item
    from public.wallet_loads l
    join public.wallet_accounts w on w.id=l.wallet_account_id and w.user_id=caller
    join public.wallet_balances b on b.wallet_account_id=w.id
    join public.profiles profile on profile.id=caller
    left join private.topup_refund_provenance p on p.load_id=l.id
    left join private.voluntary_topup_refunds r on r.load_id=l.id
    where l.user_id=caller and (p_before_load_id is null or l.id<p_before_load_id)
    order by l.id desc limit 100
  ) page);
end;
$$;

create function public.review_voluntary_topup_refund(p_id uuid, p_action text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone='UTC' as $$
declare r private.voluntary_topup_refunds%rowtype;
begin
  perform private.topup_refund_owner(null);
  if p_action is null or p_action not in ('approve','deny','reconcile') or length(p_note)>2000 then
    raise exception 'invalid_request' using errcode='PT400';
  end if;
  perform 1 from auth.users where id=auth.uid() for share;
  select * into r from private.voluntary_topup_refunds where id=p_id;
  if not found then raise exception 'refund_unavailable' using errcode='PT404'; end if;
  perform 1 from public.wallet_accounts where id=r.wallet_id for no key update;
  -- Do not wait holding one wallet for an actor profile locked by another wallet.
  perform 1 from public.profiles where id=auth.uid() for share nowait;
  perform private.topup_refund_owner(r.location_id);
  select * into r from private.voluntary_topup_refunds where id=p_id for update;
  if r.status='requested' and p_action in ('approve','deny') then
    if p_action='deny' then perform private.release_topup_refund(p_id); end if;
    update private.voluntary_topup_refunds set status=case when p_action='approve' then 'approved' else 'denied' end,
      reviewed_by=auth.uid(),reviewed_at=clock_timestamp(),review_note=p_note where id=p_id returning * into r;
  elsif (p_action='deny' and r.status<>'denied') or (p_action='approve' and r.status='denied') then
    raise exception 'refund_decision_conflict' using errcode='PT409';
  end if;
  return private.topup_refund_wire(r);
end;
$$;

create function public.owner_list_voluntary_topup_refunds(p_before timestamptz default null, p_before_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' set timezone='UTC' as $$
begin
  perform private.topup_refund_owner(null);
  return (select coalesce(jsonb_agg(private.topup_refund_wire(r) order by r.requested_at desc,r.id desc),'[]')
    from (select * from private.voluntary_topup_refunds r where
      (r.location_id is null or exists(select 1 from public."Location_to_Admin" m
        where m.user_id=auth.uid() and m.location_id=r.location_id))
      and (p_before is null or r.requested_at<p_before or (r.requested_at=p_before and r.id<p_before_id))
      order by requested_at desc,id desc limit 100) r);
end;
$$;

-- Service-only dispatch capability is issued only for an already approved row.
-- No client actor argument, amount, destination, clock or status is trusted.
create function public.prepare_voluntary_topup_refund(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r private.voluntary_topup_refunds%rowtype; first_dispatch boolean;
begin
  select * into r from private.voluntary_topup_refunds where id=p_id;
  if not found then raise exception 'refund_unavailable' using errcode='PT404'; end if;
  perform 1 from public.wallet_accounts where id=r.wallet_id for no key update;
  select * into r from private.voluntary_topup_refunds where id=p_id for update;
  if r.status not in ('approved','unknown','pending') then return null; end if;
  first_dispatch := r.dispatch_started_at is null;
  update private.voluntary_topup_refunds set dispatch_started_at=coalesce(dispatch_started_at,clock_timestamp()),
    status=case when status='approved' then 'unknown' else status end where id=p_id returning * into r;
  return jsonb_build_object('id',r.id,'intent',r.stripe_payment_intent_id,'amount',r.principal_cents,
    'livemode',r.livemode,'refund_id',r.provider_refund_id,'idempotency_key','voluntary-topup-v1:'||r.id,
    'may_create',first_dispatch or clock_timestamp()<r.dispatch_started_at+interval '23 hours');
end;
$$;

create function public.reconcile_voluntary_topup_refund(p_id uuid, p_refund_id text,
  p_status text, p_intent text, p_amount integer, p_currency text, p_livemode boolean)
returns jsonb language plpgsql security definer set search_path = '' set timezone='UTC' as $$
declare r private.voluntary_topup_refunds%rowtype;
begin
  select * into r from private.voluntary_topup_refunds where id=p_id;
  if not found then raise exception 'refund_unavailable' using errcode='PT404'; end if;
  perform 1 from public.wallet_accounts where id=r.wallet_id for no key update;
  select * into r from private.voluntary_topup_refunds where id=p_id for update;
  if p_refund_id is null or p_refund_id !~ '^re_' or p_status is null
    or p_status not in ('pending','requires_action','succeeded','failed','canceled')
    or p_intent is distinct from r.stripe_payment_intent_id or p_amount is distinct from r.principal_cents
    or p_currency is distinct from 'usd' or p_livemode is distinct from r.livemode
    or (r.provider_refund_id is not null and r.provider_refund_id<>p_refund_id)
    or r.dispatch_started_at is null then
    raise exception 'provider_mismatch' using errcode='PT409';
  end if;
  if r.status in ('succeeded','failed','canceled','denied') then
    if r.status is distinct from p_status then raise exception 'provider_terminal_conflict' using errcode='PT409'; end if;
    return private.topup_refund_wire(r);
  end if;
  if p_status in ('failed','canceled') then perform private.release_topup_refund(p_id); end if;
  update private.voluntary_topup_refunds set provider_refund_id=p_refund_id,
    provider_checked_at=clock_timestamp(),status=case when p_status='requires_action' then 'pending' else p_status end,
    completed_at=case when p_status='succeeded' then clock_timestamp() else null end where id=p_id returning * into r;
  if p_status='succeeded' then
    update public.wallet_loads set status='refunded' where id=r.load_id;
    update public.wallet_ledger_entries set stripe_refund_id=p_refund_id
      where voluntary_topup_refund_id=p_id;
  end if;
  return private.topup_refund_wire(r);
end;
$$;

revoke all on function private.capture_topup_refund_provenance(), private.capture_topup_refund_spend(),
  private.topup_refund_identity(), private.topup_refund_owner(bigint),
  private.topup_refund_wire(private.voluntary_topup_refunds), private.release_topup_refund(uuid),
  public.record_topup_refund_provenance(text,uuid,integer,timestamptz,text,boolean,bigint),
  public.request_voluntary_topup_refund(bigint), public.list_voluntary_topup_refunds(timestamptz,uuid),
  public.list_voluntary_topup_refund_topups(bigint),
  public.review_voluntary_topup_refund(uuid,text,text), public.owner_list_voluntary_topup_refunds(timestamptz,uuid),
  public.prepare_voluntary_topup_refund(uuid),
  public.reconcile_voluntary_topup_refund(uuid,text,text,text,integer,text,boolean)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.request_voluntary_topup_refund(bigint),
  public.list_voluntary_topup_refund_topups(bigint),
  public.list_voluntary_topup_refunds(timestamptz,uuid), public.review_voluntary_topup_refund(uuid,text,text),
  public.owner_list_voluntary_topup_refunds(timestamptz,uuid) to authenticated;
grant execute on function public.record_topup_refund_provenance(text,uuid,integer,timestamptz,text,boolean,bigint),
  public.prepare_voluntary_topup_refund(uuid),
  public.reconcile_voluntary_topup_refund(uuid,text,text,text,integer,text,boolean) to service_role;
-- Exclude funding that predates installation of the spend audit triggers,
-- including transactions that committed while migration DDL waited for locks.
update private.topup_refund_policy set enabled_at=clock_timestamp();
commit;
