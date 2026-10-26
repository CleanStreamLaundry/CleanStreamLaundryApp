begin;

-- Private refund tables deliberately deny service-role SELECT. Expose only a
-- scoped reporting projection; never broaden their table grants or write money.
create function public.admin_portal_topup_evidence(actor uuid)
returns table(load_id bigint, detail jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles where id=actor and roles::text='Owner') then return; end if;
  return query
  select l.id, case when p.payment_succeeded_at is null and r.id is null then '{}'::jsonb else jsonb_build_object(
    'location_id',p.location_id,'location_name',location."Name",
    'environment',case when verified.provenance then case when p.livemode then 'production' else 'sandbox' end else 'unknown' end,
    'environment_evidence',case when verified.provenance then 'stripe_success_event' else 'not_recorded' end,
    'payment_succeeded_at',case when verified.provenance then p.payment_succeeded_at else null end,
    'voluntary_refund_id',r.id,'voluntary_refund_status',r.status,
    'refund_reference',r.provider_refund_id,'refund_completed_at',case when verified.completed then r.completed_at else null end,
    'gross_collection_cents',case when verified.provenance or l.status='succeeded' then l.paid_amount_cents else null end,
    'refunded_collection_cents',case when verified.completed then r.principal_cents
      when r.id is null and l.status='succeeded' then 0
      when r.status in ('denied','failed','canceled') and r.released_at is not null and l.status='succeeded' then 0 else null end,
    'net_collection_cents',case when verified.completed then l.paid_amount_cents-r.principal_cents
      when r.id is null and l.status='succeeded' then l.paid_amount_cents
      when r.status in ('denied','failed','canceled') and r.released_at is not null and l.status='succeeded' then l.paid_amount_cents else null end,
    'reconciliation',case when verified.completed then 'refunded_confirmed'
      when r.id is null and l.status='succeeded' then 'recorded'
      when r.status in ('denied','failed','canceled') and r.released_at is not null and l.status='succeeded' then 'recorded'
      else 'refund_or_outcome_unverified' end,
    'payment_status',case when verified.completed then 'refunded'
      when r.id is null and l.status='succeeded' then 'received'
      when r.status in ('denied','failed','canceled') and r.released_at is not null and l.status='succeeded' then 'received' else 'unconfirmed' end) end
  from public.wallet_loads l
  left join private.topup_refund_provenance p on p.load_id=l.id
  left join private.voluntary_topup_refunds r on r.load_id=l.id
  left join public."Locations" location on location.id=p.location_id
  cross join lateral (select
    p.payment_succeeded_at is not null and p.stripe_event_id is not null and p.livemode is not null as provenance,
    r.status='succeeded' and r.completed_at is not null and r.provider_checked_at is not null
      and r.provider_refund_id is not null and r.released_at is null and l.status='refunded'
      and r.principal_cents=l.paid_amount_cents and r.stripe_payment_intent_id=l.stripe_payment_intent_id
      and p.payment_succeeded_at is not null and p.stripe_event_id is not null and r.livemode=p.livemode as completed
  ) verified
  where (p.location_id is null or exists(select 1 from public."Location_to_Admin" a where a.user_id=actor and a.location_id=p.location_id))
    and (r.location_id is null or exists(select 1 from public."Location_to_Admin" a where a.user_id=actor and a.location_id=r.location_id));
end; $$;
revoke all on function public.admin_portal_topup_evidence(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_portal_topup_evidence(uuid) to service_role;

-- Keep the existing scoped queues, exports, and action wrappers intact.
alter function public.admin_portal_rows(uuid,text) rename to admin_portal_rows_before_reporting;
create function public.admin_portal_rows(actor uuid, dataset text)
returns setof jsonb language plpgsql security invoker set search_path='' as $$
declare
  r jsonb; s public.cortina_vend_sessions%rowtype; w public.wallet_redemptions%rowtype;
  cents bigint; gross bigint; net bigint; spent bigint; promo bigint; vend bigint;
  category text; processor text; reconciliation text; collection_key text;
  paid boolean; linked boolean;
begin
  if dataset<>'transactions' then
    return query select * from public.admin_portal_rows_before_reporting(actor,dataset);
    return;
  end if;
  -- Calling the original source first enforces the same Owner/Admin gate and
  -- machine-location assignments, including the Owner-only legacy branch.
  for r in select * from public.admin_portal_rows_before_reporting(actor,dataset) loop
    cents:=round((r->>'amount')::numeric*100)::bigint;
    gross:=null; net:=null; spent:=0; promo:=0; vend:=0;
    category:='unknown_legacy'; processor:='unknown'; reconciliation:='unknown'; collection_key:=null;
    if r->>'source'='machine_payment' then
      select * into strict s from public.cortina_vend_sessions where 'vend:'||id=r->>'id';
      cents:=s.amount_cents;
      vend:=case when s.status='started' then cents else 0 end;
      if s.payment_method='wallet' then
        category:='wallet_spend'; processor:='none'; gross:=0; net:=0;
        select * into w from public.wallet_redemptions where id=s.wallet_redemption_id;
        if found and w.status='succeeded' and s.status not in ('refunded','voided') then
          spent:=w.amount_cents; promo:=w.promo_amount_cents; reconciliation:='recorded';
        elsif w.status='void' then
          reconciliation:='reversed';
        else
          spent:=null; promo:=null;
        end if;
      else
        category:='machine_collection';
        processor:=case when coalesce(s.stripe_payment_intent_id,s.stripe_checkout_session_id,s.stripe_charge_id) is not null then 'stripe' else 'unknown' end;
        collection_key:=coalesce('stripe:intent:'||s.stripe_payment_intent_id,
          'stripe:checkout:'||s.stripe_checkout_session_id,'stripe:charge:'||s.stripe_charge_id);
        paid:=processor='stripe' and (s.status in ('paid','starting','awaiting_sale','approved','started') or exists(
          select 1 from public.cortina_vend_events e where e.session_id=s.id and e.source='stripe'
            and e.event_type='payment_succeeded' and e.payload->>'payment_intent_id'=s.stripe_payment_intent_id));
        -- A provider reference, never amount/time, identifies shared evidence.
        -- Wallet funding owns any cross-source collection; the vend stays visible.
        linked:=exists(select 1 from public.wallet_loads l where
          l.stripe_payment_intent_id=s.stripe_payment_intent_id or
          l.stripe_checkout_session_id=s.stripe_checkout_session_id or l.stripe_charge_id=s.stripe_charge_id);
        if linked then
          gross:=0; net:=0; reconciliation:='linked_collection';
        elsif paid then
          gross:=cents;
          if s.status in ('paid','starting','awaiting_sale','approved','started') and s.stripe_refund_id is null then
            net:=cents; reconciliation:='recorded';
          else reconciliation:='refund_or_outcome_unverified'; end if;
        elsif s.status='payment_pending' then
          gross:=0; net:=0; reconciliation:='pending';
        end if;
      end if;
      r:=r||jsonb_build_object('vend_provider','nayax','charge_reference',s.stripe_charge_id,
        'nayax_transaction_reference',s.nayax_transaction_id,'nayax_rrn',s.nayax_rrn,
        'session_reference',s.id::text,'wallet_redemption_reference',s.wallet_redemption_id::text);
    else
      -- Legacy prose can establish a wallet label, not a processor or settlement.
      if coalesce(r->>'description','') ~ '^Loyalty payment on (Washer|Dryer)( - .*)?$' then
        category:='wallet_spend'; processor:='none'; gross:=0; net:=0; spent:=null; promo:=null;
      end if;
      r:=r||jsonb_build_object('vend_provider','unknown');
    end if;
    return next r||jsonb_build_object('category',category,'collection_provider',processor,
      'environment','unknown','environment_evidence','not_recorded','amount_cents',cents,
      'collection_key',collection_key,'gross_collection_cents',gross,
      'refunded_collection_cents',case when reconciliation in ('recorded','pending','linked_collection','reversed') then 0 else null end,
      'net_collection_cents',net,'wallet_spend_cents',spent,'promo_spend_cents',promo,
      'operational_vend_cents',vend,'reconciliation',reconciliation,
      'payment_status',case when reconciliation='refund_or_outcome_unverified' then 'unconfirmed' else r->>'payment_status' end);
  end loop;

  -- Only immutable funding provenance may establish location or provider mode.
  -- Historical/unlocated loads remain Owner-only, without inferred membership.
  return query
  with evidence as materialized (select * from public.admin_portal_topup_evidence(actor))
  select jsonb_build_object(
    'id','load:'||l.id,'date',l.created_at,'source','wallet_load',
    'customer_name',coalesce(nullif(p.full_name,''),'Customer'),'customer_email',p.email,
    'location_id',null,'location_name',null,'machine_id',null,'machine_name',null,
    'amount',l.paid_amount_cents::numeric/100,'amount_cents',l.paid_amount_cents,'currency','USD',
    'payment_method','card','channel',null,'status',l.status,
    'payment_status',case when l.status='succeeded' then 'received' when l.status='pending' then 'pending' else 'unconfirmed' end,
    'reference',l.id::text,'payment_reference',l.stripe_payment_intent_id,
    'checkout_reference',l.stripe_checkout_session_id,'charge_reference',l.stripe_charge_id,
    'refund_reference',null,'ledger_id',null,'failure_message',null,'completed_at',null,
    'description','Wallet funding','category','wallet_funding','collection_provider',
      case when coalesce(l.stripe_payment_intent_id,l.stripe_checkout_session_id,l.stripe_charge_id,l.stripe_event_id) is not null then 'stripe' else 'unknown' end,
    'vend_provider','none','environment','unknown','environment_evidence','not_recorded',
    'collection_key',coalesce('stripe:intent:'||l.stripe_payment_intent_id,'stripe:checkout:'||l.stripe_checkout_session_id,
      'stripe:charge:'||l.stripe_charge_id,'stripe:event:'||l.stripe_event_id),
    'gross_collection_cents',case when l.status='succeeded' and coalesce(l.stripe_payment_intent_id,l.stripe_checkout_session_id,l.stripe_charge_id,l.stripe_event_id) is not null then l.paid_amount_cents else null end,
    'refunded_collection_cents',case when l.status='succeeded' then 0 else null end,
    'net_collection_cents',case when l.status='succeeded' and coalesce(l.stripe_payment_intent_id,l.stripe_checkout_session_id,l.stripe_charge_id,l.stripe_event_id) is not null then l.paid_amount_cents else null end,
    'wallet_spend_cents',0,'promo_spend_cents',0,'promo_issued_cents',l.promo_amount_cents,'operational_vend_cents',0,
    'reconciliation',case when l.status='succeeded' and coalesce(l.stripe_payment_intent_id,l.stripe_checkout_session_id,l.stripe_charge_id,l.stripe_event_id) is not null then 'recorded' when l.status='pending' then 'pending' else 'refund_or_outcome_unverified' end)
    || coalesce(e.detail,'{}'::jsonb)
  from public.wallet_loads l left join public.profiles p on p.id=l.user_id
  join evidence e on e.load_id=l.id;
end; $$;
revoke all on function public.admin_portal_rows(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_portal_rows(uuid,text) to service_role;

alter function public.admin_portal_data(uuid,text,jsonb) rename to admin_portal_data_before_reporting;
create function public.admin_portal_data(actor uuid, action text, payload jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; ids bigint[]; actor_role text;
  business_today date:=(now() at time zone 'America/Indiana/Indianapolis')::date;
begin
  if action<>'overview' then return public.admin_portal_data_before_reporting(actor,action,payload); end if;
  select roles::text into actor_role from public.profiles where id=actor;
  if actor_role is null or actor_role not in ('Owner','Admin') then
    raise exception 'Owner or Admin access required' using errcode='42501';
  end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id=actor;
  with scoped as materialized (
    select r, (r->>'date')::timestamptz at time zone 'America/Indiana/Indianapolis' local_date
    from public.admin_portal_rows(actor,'transactions') r
    where (r->>'date')::timestamptz >= (business_today-29)::timestamp at time zone 'America/Indiana/Indianapolis'
      and (r->>'date')::timestamptz < (business_today+1)::timestamp at time zone 'America/Indiana/Indianapolis'
  ), collections as (
    select * from scoped where r->>'collection_provider'='stripe' and r->>'reconciliation' in ('recorded','refunded_confirmed')
      and r->>'currency'='USD' and r->>'environment'<>'sandbox'
  ), buckets as (
    select r->>'category' category,r->>'collection_provider' provider,r->>'environment' environment,r->>'currency' currency,
      count(*) records,sum((r->>'amount_cents')::bigint) amount,
      sum((r->>'gross_collection_cents')::bigint) gross,
      case when count(*)=count(r->>'refunded_collection_cents') then sum((r->>'refunded_collection_cents')::bigint) end refunded,
      case when count(*)=count(r->>'net_collection_cents') then sum((r->>'net_collection_cents')::bigint) end net,
      count(*) filter(where r->>'reconciliation' not in ('recorded','refunded_confirmed','linked_collection','reversed','pending')) unresolved
    from scoped group by 1,2,3,4
  ), daily as (
    select day::date d,coalesce((select sum((r->>'net_collection_cents')::bigint) from collections where local_date::date=day::date),0) cents
    from generate_series((business_today-29)::timestamp,business_today::timestamp,'1 day') day
  )
  select jsonb_build_object(
    'today',coalesce((select sum((r->>'net_collection_cents')::bigint)/100.0 from collections where local_date::date=business_today),0),
    'total',coalesce((select sum((r->>'net_collection_cents')::bigint)/100.0 from collections),0),
    'daily',(select jsonb_agg(jsonb_build_object('date',d,'amount',cents/100.0) order by d) from daily),
    'hourly',(select jsonb_agg(n order by h) from (select h,(select count(*) from scoped where extract(hour from local_date)=h) n from generate_series(0,23) h) hours),
    'locations',cardinality(ids),'machines',(select count(*) from public."Machines" where "Location_ID"=any(ids)),
    'pendingCredits',(public.admin_portal_data_before_reporting(actor,'credits','{"filters":{"status":"pending"}}')->>'total')::int,
    'openMaintenance',(public.admin_portal_data_before_reporting(actor,'maintenance','{"filters":{"status":"unresolved"}}')->>'total')::int,
    'updatedAt',now(),
    'financialScope','Recorded USD Stripe net collections, excluding sandbox. Unknown-mode historical records remain separate in the breakdown; they are not verified live revenue. Confirmed voluntary refunds reduce their original load net, not a cash-flow-on-refund-date report. Uncertain refunds and legacy records excluded. Wallet use and vend value are not additional collections.',
    'reporting',jsonb_build_object('version',1,'currency','USD','environment','mixed',
      'scope',case when actor_role='Owner' then 'Assigned locations; all unlocated wallet loads and legacy records' else 'Assigned locations only; unlocated wallet loads and legacy records excluded' end,
      'nayaxDirect',jsonb_build_object('availability','not_connected','lastSyncAt',null,'transactionCount',null,'netCollectionCents',null),
      'stripe',jsonb_build_object('availability','local_records_only','lastSyncAt',null),
      'confirmedCollectionCents',coalesce((select sum((r->>'net_collection_cents')::bigint) from collections),0),
      'walletSpendCents',coalesce((select sum((r->>'wallet_spend_cents')::bigint) from scoped where r->>'currency'='USD'),0),
      'promoSpendCents',coalesce((select sum((r->>'promo_spend_cents')::bigint) from scoped where r->>'currency'='USD'),0),
      'promoIssuedCents',coalesce((select sum((r->>'promo_issued_cents')::bigint) from scoped where r->>'status'='succeeded'),0),
      'operationalVendCents',coalesce((select sum((r->>'operational_vend_cents')::bigint) from scoped where r->>'currency'='USD'),0),
      'unresolvedRecords',(select count(*) from scoped where r->>'reconciliation' not in ('recorded','refunded_confirmed','linked_collection','reversed','pending')),
      'buckets',(select coalesce(jsonb_agg(jsonb_build_object('category',category,'provider',provider,'environment',environment,'currency',currency,
        'records',records,'amountCents',amount,'grossCollectionCents',gross,'refundedCollectionCents',refunded,'netCollectionCents',net,'unresolvedRecords',unresolved) order by category,provider,environment,currency),'[]') from buckets))) into result;
  return result;
end; $$;
revoke all on function public.admin_portal_data(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_portal_data(uuid,text,jsonb) to service_role;

commit;
