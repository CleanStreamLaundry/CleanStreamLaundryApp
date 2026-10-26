-- Local-only rollout. Configure each location's verified IANA timezone before activation.
-- Historical locations/timezones are deliberately not guessed or backfilled.
begin;

alter table public."Locations" add column machine_issue_timezone text;
-- Exact identities and corrected pins from supabase/ops/20261003_correct_location_coordinates.sql.
-- These are Anderson addresses, not a default for Indiana or for future locations.
update public."Locations" set machine_issue_timezone='America/Indiana/Indianapolis'
where (id=1 and "Name"='Madison Ave.' and "Address"='5330 Madison ave, Anderson, IN'
  and "Latitude"=40.06097 and "Longitude"=-85.69173)
  or (id=2 and "Name"='Columbus Ave.' and "Address"='5107 South Columbus ave, Anderson, IN'
  and "Latitude"=40.06415 and "Longitude"=-85.66733);
alter table public.cortina_vend_sessions
  add column original_location_id bigint,
  add column original_location_timezone text,
  add column funding_source text not null default 'payment' check (funding_source in ('payment','machine_issue')),
  add column complaint_refund_id bigint references public."Refunds"(refund_id);
alter table public.cortina_vend_sessions add constraint complaint_funding_binding check (
  (funding_source='payment' and complaint_refund_id is null) or
  (funding_source='machine_issue' and complaint_refund_id is not null and payment_method='wallet'
    and wallet_redemption_id is null and stripe_payment_intent_id is null));
create unique index cortina_one_complaint_replacement on public.cortina_vend_sessions(complaint_refund_id)
  where complaint_refund_id is not null;
alter table public."Refunds"
  add column policy_version text not null default 'legacy_14_day' check (policy_version in ('legacy_14_day','same_day_v1')),
  add column received_at timestamptz,
  add column original_transaction_at timestamptz,
  add column original_location_id bigint,
  add column original_location_timezone text;
alter table public."Refunds" alter column policy_version set default 'same_day_v1';

create table private.machine_issue_resolutions (
  request_id uuid primary key,
  refund_id bigint not null references public."Refunds"(refund_id),
  actor_id uuid not null,
  resolution text not null check (resolution in ('wallet_refund','replacement_vend','manual_review')),
  state text not null check (state in ('recorded','pending','completed','support_required')),
  at_location boolean not null,
  another_load_completed boolean not null,
  replacement_machine_id bigint,
  note text not null check (length(btrim(note)) between 1 and 4000),
  amount_cents integer,
  paid_amount_cents integer,
  promo_amount_cents integer,
  ledger_entry_id bigint references public.wallet_ledger_entries(id),
  original_session_id uuid references public.cortina_vend_sessions(id),
  replacement_session_id uuid unique references public.cortina_vend_sessions(id),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  check (resolution='manual_review' or (amount_cents>0 and paid_amount_cents>=0 and promo_amount_cents>=0
    and amount_cents=paid_amount_cents+promo_amount_cents and original_session_id is not null))
);
create unique index machine_issue_one_benefit on private.machine_issue_resolutions(refund_id)
  where resolution<>'manual_review';
create unique index machine_issue_original_one_benefit on private.machine_issue_resolutions(original_session_id)
  where resolution<>'manual_review';
alter table private.machine_issue_resolutions enable row level security;
revoke all on private.machine_issue_resolutions from public,anon,authenticated,service_role;

create function private.guard_machine_issue_receipt() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='DELETE' or (to_jsonb(new)-'state'-'completed_at') is distinct from (to_jsonb(old)-'state'-'completed_at')
    or (old.state='support_required' and new.state<>'support_required')
    or (old.state='completed' and new.state not in ('completed','support_required'))
    or (old.state='pending' and new.state not in ('pending','completed','support_required'))
    or (old.state='recorded' and new.state<>'recorded')
    or (new.completed_at is distinct from old.completed_at and not
      (old.state='pending' and new.state='completed' and old.completed_at is null and new.completed_at is not null)) then
    raise exception 'Machine issue receipt is immutable' using errcode='23514';
  end if;
  return new;
end $$;
create trigger machine_issue_receipt_immutable before update or delete on private.machine_issue_resolutions
  for each row execute function private.guard_machine_issue_receipt();

create function private.capture_machine_issue_provenance() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='Locations' then
    if new.machine_issue_timezone is not null and not exists
      (select 1 from pg_timezone_names where name=new.machine_issue_timezone) then
      raise exception 'Invalid IANA location timezone' using errcode='22023';
    end if;
  elsif tg_table_name='cortina_vend_sessions' then
    if tg_op='INSERT' then
      select m."Location_ID",l.machine_issue_timezone into new.original_location_id,new.original_location_timezone
      from public."Machines" m join public."Locations" l on l.id=m."Location_ID" where m.id=new.machine_id for share of m,l;
    elsif row(new.original_location_id,new.original_location_timezone,new.funding_source,new.complaint_refund_id)
      is distinct from row(old.original_location_id,old.original_location_timezone,old.funding_source,old.complaint_refund_id) then
      raise exception 'Original complaint binding is immutable' using errcode='23514';
    end if;
  elsif tg_op='INSERT' then
    new.policy_version:='same_day_v1'; new.received_at:=statement_timestamp();
    select t.created_at,s.original_location_id,s.original_location_timezone
      into new.original_transaction_at,new.original_location_id,new.original_location_timezone
    from public.transactions t left join public.cortina_vend_sessions s on s.id=t.cortina_vend_session_id
    where t.id=new.transaction_id;
  elsif row(new.policy_version,new.received_at,new.original_transaction_at,new.original_location_id,new.original_location_timezone)
    is distinct from row(old.policy_version,old.received_at,old.original_transaction_at,old.original_location_id,old.original_location_timezone) then
    raise exception 'Claim receipt is immutable' using errcode='23514';
  end if;
  return new;
end $$;
create trigger capture_machine_issue_location before insert or update on public."Locations"
  for each row execute function private.capture_machine_issue_provenance();
create trigger capture_machine_issue_vend before insert or update on public.cortina_vend_sessions
  for each row execute function private.capture_machine_issue_provenance();
create trigger capture_machine_issue_receipt before insert or update on public."Refunds"
  for each row execute function private.capture_machine_issue_provenance();

-- The submission is evidence, not an entitlement decision. Keep expired/disputed
-- claims for review; only the new resolution RPC applies the voluntary deadline.
do $$
declare sig text; source text; revised text;
begin
  foreach sig in array array['public.request_cortina_loyalty_credit(bigint,text)',
    'public.request_legacy_loyalty_credit(bigint,text)','public.validate_cortina_credit_request()'] loop
    source:=pg_get_functiondef(sig::regprocedure);
    revised:=replace(source, 'if payment.created_at < now() - interval ''14 days'' then', 'if false then');
    revised:=replace(revised, 'if payment.created_at < clock_timestamp() - interval ''14 days'' then', 'if false then');
    revised:=replace(revised, E'if payment.created_at is null or payment.created_at > clock_timestamp()\n    or payment.created_at < clock_timestamp() - interval ''14 days'' then', 'if false then');
    revised:=replace(revised, 'if vend.status <> ''started'' or vend.user_id is distinct from customer_id then',
      'if vend.user_id is distinct from customer_id then');
    revised:=replace(revised, '(tg_op = ''INSERT'' or new.status::text = ''approved'') and vend.status <> ''started''',
      'new.status::text = ''approved'' and vend.status <> ''started''');
    if revised=source then raise exception 'Reviewed claim policy body required: %',sig; end if;
    execute revised;
  end loop;
end $$;

create function private.machine_issue_review(target bigint,actor uuid,request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public."Refunds"; t public.transactions; s public.cortina_vend_sessions;
  redemption public.wallet_redemptions; benefit private.machine_issue_resolutions; receipt private.machine_issue_resolutions;
  cents integer; reason text; timely boolean:=false; candidates jsonb:='[]';
begin
  select * into r from public."Refunds" where refund_id=target;
  if not found then raise exception 'machine_issue_not_found' using errcode='PT409'; end if;
  select * into t from public.transactions where id=r.transaction_id;
  select * into s from public.cortina_vend_sessions where id=t.cortina_vend_session_id;
  select * into redemption from public.wallet_redemptions where id=s.wallet_redemption_id;
  select * into benefit from private.machine_issue_resolutions where refund_id=target and resolution<>'manual_review';
  select * into receipt from private.machine_issue_resolutions a
    where a.request_id=machine_issue_review.request_id and a.refund_id=target and a.actor_id=actor;
  if t.amount::numeric>0 and t.amount::numeric<=21474836.47 and trunc(t.amount::numeric,2)=t.amount::numeric then
    cents:=(t.amount::numeric*100)::integer;
  end if;
  if r.original_location_timezone is not null and r.original_transaction_at is not null and r.received_at is not null then
    timely:=r.received_at>=r.original_transaction_at and
      (r.received_at at time zone r.original_location_timezone)::date=(r.original_transaction_at at time zone r.original_location_timezone)::date;
  end if;
  if r.status::text<>'pending' or benefit.request_id is not null then reason:='already_dispositioned';
  elsif r.policy_version='legacy_14_day' then reason:='legacy_policy_review';
  elsif r.original_location_id is null or r.original_location_timezone is null then reason:='original_location_unknown';
  elsif not timely then reason:='outside_voluntary_same_day';
  elsif cents is null or r.amount::numeric is distinct from t.amount::numeric or s.amount_cents is distinct from cents
    or t.user_id is distinct from r.user_id or s.user_id is distinct from r.user_id
    or t.created_at is distinct from r.original_transaction_at then reason:='payment_binding_unverified';
  elsif (select count(*) from public."Refunds" where transaction_id=t.id)<>1 then reason:='duplicate_claim_history';
  elsif s.status is distinct from 'started' or s.stripe_refund_id is not null or s.funding_source<>'payment'
    or exists(select 1 from public.wallet_ledger_entries where refund_request_id=r.refund_id)
    then reason:='prior_or_uncertain_compensation';
  elsif s.payment_method='card' then reason:='external_card_refund_review_required';
  elsif redemption.id is null or redemption.status<>'succeeded' or redemption.user_id is distinct from r.user_id
    or redemption.machine_id is distinct from s.machine_id or redemption.amount_cents<>cents
    or redemption.paid_amount_cents+redemption.promo_amount_cents<>cents then reason:='wallet_source_unverified';
  elsif not exists(select 1 from public.wallet_accounts w where w.id=redemption.wallet_account_id and w.user_id=r.user_id
    and w.status in ('active','locked')) then reason:='wallet_requires_review';
  end if;
  if reason is null then
    select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m."Name",'amountCents',cents) order by m.id),'[]') into candidates
    from public."Machines" m join public.cortina_machine_config c on c.machine_id=m.id
      left join public.washer_size_rates rate on rate.id=m.washer_size_rate_id
    where m."Location_ID"=r.original_location_id and m.id<>s.machine_id
      and not m.is_out_of_service and lower(m."Status"::text) in ('idle','available')
      and c.is_enabled and not c.review_required and c.environment=s.nayax_environment
      and lower(m."Machine_type"::text)=(select lower("Machine_type"::text) from public."Machines" where id=s.machine_id)
      and ((lower(m."Machine_type"::text)='washer' and rate.is_active and not rate.review_required and rate.price_cents=cents)
        or (lower(m."Machine_type"::text)='dryer' and cents in (50,100,150,200,300,450)));
  end if;
  return jsonb_build_object('refundId',r.refund_id,'transactionId',r.transaction_id,'status',r.status::text,
    'policyVersion',r.policy_version,'amountCents',cents,'paidAmountCents',redemption.paid_amount_cents,
    'promoAmountCents',redemption.promo_amount_cents,'locationId',r.original_location_id,
    'locationTimezone',r.original_location_timezone,'transactionAt',coalesce(r.original_transaction_at,t.created_at),
    'receivedAt',coalesce(r.received_at,r.date,t.created_at),'sameDayEligible',timely,'manualReviewReason',reason,
    'financialResolution',case when benefit.request_id is not null then jsonb_build_object('kind',benefit.resolution,'state',benefit.state,'requestId',benefit.request_id) end,
    'receipt',case when receipt.request_id is not null then jsonb_build_object('requestId',receipt.request_id,'resolution',receipt.resolution,'state',receipt.state) end,
    'capabilities',jsonb_build_object('walletRefund',reason is null,'replacementVend',reason is null and jsonb_array_length(candidates)>0),
    'replacementMachines',candidates,'replacementUnavailableReason',coalesce(reason,case when candidates='[]' then 'no_same_price_machine_available' end));
end $$;

create function public.admin_machine_issue(action text,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare ctx jsonb; actor uuid; target bigint:=(payload->>'id')::bigint; request uuid:=(payload->>'requestId')::uuid;
  r public."Refunds"; t public.transactions; original public.cortina_vend_sessions; prior private.machine_issue_resolutions;
  redemption public.wallet_redemptions; machine public."Machines"; config public.cortina_machine_config;
  review jsonb; kind text:=payload->>'resolution'; note text:=btrim(payload->>'note'); entry bigint;
  replacement uuid; minutes integer; line integer; code integer; cents integer;
begin
  ctx:=private.portal_staff_context(); actor:=(ctx->>'actor')::uuid;
  perform private.require_portal_action(actor,'resolveCredit','{}');
  if action='machineIssueReview' then return private.machine_issue_review(target,actor,request); end if;
  if action<>'resolveMachineIssue' or request is null or kind not in ('wallet_refund','replacement_vend','manual_review')
    or note is null or length(note) not between 1 and 4000
    or jsonb_typeof(payload->'atLocation') is distinct from 'boolean'
    or jsonb_typeof(payload->'anotherLoadCompleted') is distinct from 'boolean' then
    raise exception 'Invalid machine issue decision' using errcode='22023';
  end if;
  select * into r from public."Refunds" where refund_id=target for update;
  if not found then raise exception 'machine_issue_not_found' using errcode='PT409'; end if;
  select * into prior from private.machine_issue_resolutions where request_id=request;
  if found then
    if prior.refund_id<>target or prior.actor_id<>actor or prior.resolution<>kind or prior.note<>note
      or prior.at_location is distinct from (payload->>'atLocation')::boolean
      or prior.another_load_completed is distinct from (payload->>'anotherLoadCompleted')::boolean
      or prior.replacement_machine_id is distinct from (payload->>'replacementMachineId')::bigint then
      raise exception 'machine_issue_resolution_conflict' using errcode='PT409';
    end if;
    if private.portal_staff_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
    return jsonb_build_object('success',true,'alreadyResolved',true,'review',private.machine_issue_review(target,actor,request));
  end if;
  if kind='manual_review' then
    insert into private.machine_issue_resolutions(request_id,refund_id,actor_id,resolution,state,at_location,another_load_completed,note)
      values(request,target,actor,kind,'recorded',(payload->>'atLocation')::boolean,(payload->>'anotherLoadCompleted')::boolean,note);
  else
    select * into t from public.transactions where id=r.transaction_id for share;
    select * into original from public.cortina_vend_sessions where id=t.cortina_vend_session_id for update nowait;
    select * into redemption from public.wallet_redemptions where id=original.wallet_redemption_id;
    perform 1 from public.wallet_accounts where id=redemption.wallet_account_id for no key update;
    select * into redemption from public.wallet_redemptions where id=original.wallet_redemption_id for update;
    review:=private.machine_issue_review(target,actor,request);
    if review->>'manualReviewReason' is not null or (payload->>'atLocation')::boolean is not true
      or (payload->>'anotherLoadCompleted')::boolean is distinct from (kind='wallet_refund') then
      raise exception 'machine_issue_manual_review_required' using errcode='PT409';
    end if;
    cents:=(review->>'amountCents')::integer;
    if kind='wallet_refund' then
      insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents,
        machine_id,note,created_by,refund_request_id)
      values(redemption.wallet_account_id,'admin_adjustment',cents,redemption.paid_amount_cents,redemption.promo_amount_cents,
        original.machine_id,'Machine issue wallet refund: '||note,actor,target) returning id into entry;
      -- This original debit has now been restored. A later Void must not restore it again.
      update public.wallet_redemptions set status='void' where id=redemption.id;
      perform public.sync_profile_wallet_balance(redemption.wallet_account_id);
    else
      if not exists(select 1 from jsonb_array_elements(review->'replacementMachines') m
        where (m->>'id')::bigint=(payload->>'replacementMachineId')::bigint) then
        raise exception 'machine_issue_replacement_unavailable' using errcode='PT409';
      end if;
      select * into machine from public."Machines" where id=(payload->>'replacementMachineId')::bigint for share;
      select * into config from public.cortina_machine_config where machine_id=machine.id for share nowait;
      if lower(machine."Machine_type"::text)='dryer' then
        select o.minutes,o.line into minutes,line from (values(50,10,1),(100,20,2),(150,30,3),(200,40,4),(300,60,5),(450,90,6))o(cents,minutes,line)
          where o.cents=original.amount_cents;
      end if;
      if config.product_codes is not null then code:=(config.product_codes->>cents::text)::integer; line:=null;
      else line:=coalesce(line,config.pulse_line_number); end if;
      insert into public.cortina_vend_sessions(client_request_id,client_access_token_hash,machine_id,user_id,washer_size_rate_id,
        amount_cents,dryer_minutes,pulse_line_number,product_code,currency,payment_method,channel,status,transaction_id,funding_source,complaint_refund_id)
      values(request,encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),machine.id,r.user_id,
        case when lower(machine."Machine_type"::text)='washer' then machine.washer_size_rate_id end,
        cents,minutes,line,code,'USD','wallet','app','payment_pending','issue-'||replace(request::text,'-',''),'machine_issue',target)
      returning id into replacement;
      if machine."Location_ID" is distinct from r.original_location_id or config.environment is distinct from original.nayax_environment then
        raise exception 'machine_issue_replacement_unavailable' using errcode='PT409';
      end if;
    end if;
    insert into private.machine_issue_resolutions(request_id,refund_id,actor_id,resolution,state,at_location,another_load_completed,
      replacement_machine_id,note,amount_cents,paid_amount_cents,promo_amount_cents,ledger_entry_id,original_session_id,replacement_session_id,completed_at)
    values(request,target,actor,kind,case when kind='wallet_refund' then 'completed' else 'pending' end,true,
      (payload->>'anotherLoadCompleted')::boolean,(payload->>'replacementMachineId')::bigint,note,cents,
      redemption.paid_amount_cents,redemption.promo_amount_cents,entry,original.id,replacement,
      case when kind='wallet_refund' then clock_timestamp() end);
    if kind='wallet_refund' then
      update public."Refunds" set status='approved',resolved_by=actor,resolved_at=clock_timestamp(),admin_note=note where refund_id=target;
    else
      update public.cortina_vend_sessions set status='paid' where id=replacement;
    end if;
  end if;
  if private.portal_staff_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return jsonb_build_object('success',true,'alreadyResolved',false,'review',private.machine_issue_review(target,actor,request),
    'startSessionId',replacement);
exception when unique_violation then
  raise exception 'machine_issue_resolution_conflict' using errcode='PT409';
end $$;

-- Preserve old-policy receipts without allowing the old approval API to bypass
-- new same-day checks or grant a second benefit after a replacement reservation.
alter function public.admin_resolve_credit(bigint,text,text) rename to admin_resolve_credit_before_machine_issues;
create function public.admin_resolve_credit(target_refund_id bigint,target_decision text,resolution_note text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb; policy text;
begin
  ctx:=private.portal_staff_context(); perform private.require_portal_action((ctx->>'actor')::uuid,'resolveCredit','{}');
  select policy_version into policy from public."Refunds" where refund_id=target_refund_id for update;
  if policy='same_day_v1' or exists(select 1 from private.machine_issue_resolutions where refund_id=target_refund_id and resolution<>'manual_review') then
    raise exception 'machine_issue_manual_review_required' using errcode='PT409';
  end if;
  return public.admin_resolve_credit_before_machine_issues(target_refund_id,target_decision,resolution_note);
end $$;

-- Sponsored machine activity is not a second payment or a new claimable charge.
alter function public.sync_cortina_transaction(uuid) rename to sync_cortina_transaction_before_machine_issues;
create function public.sync_cortina_transaction(target_session_id uuid) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if exists(select 1 from public.cortina_vend_sessions where id=target_session_id and funding_source='machine_issue') then return; end if;
  perform public.sync_cortina_transaction_before_machine_issues(target_session_id);
end $$;

create function public.authorize_machine_issue_start(target_session_id uuid,for_start boolean default false) returns boolean
language plpgsql security definer set search_path='' as $$
declare permitted boolean;
begin
  if for_start then perform private.require_new_payments_enabled(); end if;
  select exists(select 1 from private.machine_issue_resolutions r
    join public.cortina_vend_sessions s on s.id=r.replacement_session_id
    join public.cortina_vend_sessions original on original.id=r.original_session_id
    join public.wallet_redemptions debit on debit.id=original.wallet_redemption_id
    join public."Machines" m on m.id=s.machine_id
    join public.cortina_machine_config c on c.machine_id=m.id
    where s.id=target_session_id and r.resolution='replacement_vend' and r.state in ('pending','completed')
      and s.funding_source='machine_issue' and s.complaint_refund_id=r.refund_id
      and original.status='started' and original.stripe_refund_id is null and original.payment_method='wallet'
      and debit.status='succeeded' and s.amount_cents=r.amount_cents and original.amount_cents=r.amount_cents
      and s.user_id=original.user_id and m."Location_ID"=original.original_location_id
      and (not for_start or private.effective_portal_role(r.actor_id)='Owner')
      and (not for_start or (not m.is_out_of_service and lower(m."Status"::text) in ('idle','available')
        and c.is_enabled and not c.review_required and c.environment=s.nayax_environment))) into permitted;
  return permitted;
end $$;

create function private.machine_issue_vend_outcome() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.funding_source='machine_issue' then
    update private.machine_issue_resolutions set state=case when new.status='started' and state='pending' then 'completed'
      when new.status in ('failed','voided','refunded','timed_out','support_required') then 'support_required' else state end,
      completed_at=case when new.status='started' and state='pending' then clock_timestamp() else completed_at end
    where replacement_session_id=new.id;
  elsif new.status<>'started' then
    update private.machine_issue_resolutions set state='support_required'
      where original_session_id=new.id and resolution<>'manual_review';
  end if;
  return new;
end $$;
create trigger machine_issue_vend_outcome after update of status on public.cortina_vend_sessions
  for each row execute function private.machine_issue_vend_outcome();

-- Callback reversal and complaint approval share the original session lock.
alter function public.reverse_cortina_wallet_redemption(uuid) rename to reverse_cortina_wallet_before_machine_issues;
create function public.reverse_cortina_wallet_redemption(target_session_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.cortina_vend_sessions where id=target_session_id for update;
  if exists(select 1 from public.cortina_vend_sessions where id=target_session_id and funding_source='machine_issue')
    or exists(select 1 from private.machine_issue_resolutions where original_session_id=target_session_id and resolution<>'manual_review') then
    update private.machine_issue_resolutions set state='support_required'
      where original_session_id=target_session_id or replacement_session_id=target_session_id;
    return false;
  end if;
  return public.reverse_cortina_wallet_before_machine_issues(target_session_id);
end $$;

revoke all on function private.guard_machine_issue_receipt(),private.capture_machine_issue_provenance(),private.machine_issue_review(bigint,uuid,uuid),
  private.machine_issue_vend_outcome(),public.admin_machine_issue(text,jsonb),public.authorize_machine_issue_start(uuid,boolean),
  public.admin_resolve_credit_before_machine_issues(bigint,text,text),public.admin_resolve_credit(bigint,text,text),
  public.sync_cortina_transaction_before_machine_issues(uuid),public.sync_cortina_transaction(uuid),
  public.reverse_cortina_wallet_before_machine_issues(uuid),public.reverse_cortina_wallet_redemption(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_machine_issue(text,jsonb),public.admin_resolve_credit(bigint,text,text) to authenticated;
grant execute on function public.sync_cortina_transaction(uuid),public.sync_cortina_transaction_before_machine_issues(uuid),
  public.reverse_cortina_wallet_redemption(uuid),public.authorize_machine_issue_start(uuid,boolean) to service_role;

-- Keep the replacement visible as machine activity, never a second collection/debit.
do $$
declare source text; revised text;
begin
  source:=pg_get_functiondef('public.admin_portal_rows_before_roles(uuid,text)'::regprocedure);
  revised:=replace(source, 'if s.payment_method=''wallet'' then',
    E'if s.funding_source=''machine_issue'' then\n        category:=''machine_issue_replacement''; processor:=''none''; gross:=0; net:=0; spent:=0; promo:=0; reconciliation:=''recorded'';\n      elsif s.payment_method=''wallet'' then');
  if revised=source then raise exception 'Reviewed collection reporting body required'; end if;
  execute revised;
end $$;
commit;
