-- Add durable read-only-provider reconciliation to existing vend sessions.
-- No cron, routing backfill, new payout authority, or account cleanup.
alter table public.cortina_vend_sessions
  add column reconcile_after timestamptz,
  add column reconcile_claim uuid,
  add column reconcile_claim_until timestamptz,
  add column reconcile_attempts integer not null default 0 check (reconcile_attempts >= 0),
  add column reconcile_reason text,
  add column reconciled_at timestamptz;

create index cortina_reconcile_due_idx on public.cortina_vend_sessions(reconcile_after, id)
where reconcile_after is not null;

create function public.queue_cortina_reconciliation()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and row(new.status, new.stripe_payment_intent_id,
      new.stripe_checkout_session_id, new.stripe_charge_id, new.stripe_refund_id,
      new.nayax_transaction_id, new.nayax_rrn, new.user_id, new.start_requested_at)
    is not distinct from row(old.status, old.stripe_payment_intent_id,
      old.stripe_checkout_session_id, old.stripe_charge_id, old.stripe_refund_id,
      old.nayax_transaction_id, old.nayax_rrn, old.user_id, old.start_requested_at) then
    return new;
  end if;
  -- A callback/identity change invalidates any in-flight observation. Worker
  -- completion holds the same row lock and writes its final retry policy last.
  new.reconcile_claim := null;
  new.reconcile_claim_until := null;
  new.reconcile_attempts := 0;
  new.reconcile_after := case
    when new.status = 'refunded' then null
    when new.status = 'started' and new.stripe_refund_id is null then null
    else clock_timestamp() + interval '2 minutes' end;
  return new;
end;
$$;
revoke all on function public.queue_cortina_reconciliation() from public, anon, authenticated;
create trigger queue_cortina_reconciliation
before insert or update of status, stripe_payment_intent_id, stripe_checkout_session_id,
  stripe_charge_id, stripe_refund_id, nayax_transaction_id, nayax_rrn, user_id, start_requested_at
on public.cortina_vend_sessions
for each row execute function public.queue_cortina_reconciliation();

-- Queue existing unresolved rows without interpreting or reconstructing their
-- routing. Rows without a frozen snapshot will stop at manual support review.
update public.cortina_vend_sessions set reconcile_after = clock_timestamp() + interval '2 minutes'
where status <> 'refunded' and (status <> 'started' or stripe_refund_id is not null);

create function public.claim_cortina_reconciliation(p_environment text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  session public.cortina_vend_sessions%rowtype;
begin
  if p_environment is null or p_environment not in ('sandbox','production') then
    raise exception 'Invalid reconciliation environment';
  end if;
  select * into session from public.cortina_vend_sessions
  where reconcile_after <= clock_timestamp()
    and (reconcile_claim_until is null or reconcile_claim_until <= clock_timestamp())
    and (nayax_environment = p_environment or nayax_environment is null)
    and status <> 'refunded' and (status <> 'started' or stripe_refund_id is not null)
  order by reconcile_after, id limit 1 for update skip locked;
  if not found then return null; end if;
  update public.cortina_vend_sessions set
    reconcile_claim = gen_random_uuid(),
    reconcile_claim_until = clock_timestamp() + interval '90 seconds',
    reconcile_attempts = least(reconcile_attempts + 1, 1000000),
    reconcile_after = clock_timestamp() + make_interval(secs =>
      least(21600, 60 * power(2, least(reconcile_attempts, 9)))::integer)
  where id = session.id returning * into session;
  return to_jsonb(session);
end;
$$;

create function public.finish_cortina_reconciliation(
  p_session uuid, p_claim uuid, p_outcome text, p_reason text, p_evidence jsonb default '{}'
)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  session public.cortina_vend_sessions%rowtype;
  payment jsonb := p_evidence->'payment';
  checkout jsonb := p_evidence->'checkout';
  refund jsonb := p_evidence->'refund';
  retry_at timestamptz;
begin
  select * into session from public.cortina_vend_sessions where id = p_session for update;
  -- Recheck lease expiry after lock waits; stale workers cannot apply an old
  -- provider response after another claim, callback, or ownership change.
  if not found or p_claim is null or session.reconcile_claim is distinct from p_claim
    or session.reconcile_claim_until is null or session.reconcile_claim_until <= clock_timestamp() then
    return false;
  end if;
  if p_outcome is null or p_outcome not in
      ('payment_pending','payment_verified','refund_pending','refund_succeeded','manual_review','provider_unavailable')
    or p_reason is null or p_reason !~ '^[a-z_]{1,64}$' then
    raise exception 'Invalid reconciliation outcome';
  end if;
  retry_at := case when p_outcome in ('payment_pending','refund_pending','provider_unavailable')
    then greatest(session.reconcile_after, clock_timestamp() + interval '1 minute') else null end;

  if p_outcome in ('payment_verified','refund_pending','refund_succeeded') then
    if session.payment_method <> 'card' or payment is null
      or payment->>'status' is distinct from 'succeeded'
      or (payment->>'amount')::integer is distinct from session.amount_cents
      or (payment->>'amount_received')::integer is distinct from session.amount_cents
      or upper(payment->>'currency') is distinct from session.currency
      or (payment->>'livemode')::boolean is distinct from session.stripe_livemode
      or payment#>>'{metadata,purpose}' is distinct from 'cortina_vend'
      or payment#>>'{metadata,cortina_session_id}' is distinct from session.id::text
      or payment#>>'{metadata,machine_id}' is distinct from session.machine_id::text
      or payment#>>'{metadata,amount_cents}' is distinct from session.amount_cents::text
      or payment#>>'{metadata,user_id}' is distinct from session.user_id::text then
      raise exception 'Payment evidence mismatch';
    end if;
    if session.channel = 'web' and (
      session.stripe_checkout_session_id is null or checkout is null
      or checkout->>'id' is distinct from session.stripe_checkout_session_id
      or checkout->>'payment_intent' is distinct from payment->>'id'
      or checkout->>'mode' is distinct from 'payment'
      or checkout->>'status' is distinct from 'complete'
      or checkout->>'payment_status' is distinct from 'paid'
      or (checkout->>'amount_total')::integer is distinct from session.amount_cents
      or upper(checkout->>'currency') is distinct from session.currency
      or (checkout->>'livemode')::boolean is distinct from session.stripe_livemode
      or checkout#>>'{metadata,purpose}' is distinct from 'cortina_vend'
      or checkout#>>'{metadata,cortina_session_id}' is distinct from session.id::text
      or checkout#>>'{metadata,machine_id}' is distinct from session.machine_id::text
      or checkout#>>'{metadata,amount_cents}' is distinct from session.amount_cents::text
      or checkout#>>'{metadata,user_id}' is distinct from session.user_id::text
    ) then raise exception 'Checkout evidence mismatch'; end if;

    -- Never reopen vending from a delayed scheduled observation. Record the
    -- existing financial contract in the same transaction, without calling Start.
    update public.cortina_vend_sessions set status = 'support_required' where id = p_session;
    perform public.record_cortina_card_payment(
      p_session, 'reconcile:' || p_session || ':' || (payment->>'id'),
      payment->>'id', session.stripe_checkout_session_id, payment->>'charge_id',
      (payment->>'amount_received')::integer, payment->>'currency', (payment->>'livemode')::boolean
    );
    if p_outcome in ('refund_pending','refund_succeeded') and (
      session.stripe_refund_id is null or refund is null
      or refund->>'id' is distinct from session.stripe_refund_id
      or refund->>'payment_intent' is distinct from payment->>'id'
      or refund->>'charge' is distinct from payment->>'charge_id'
      or (refund->>'amount')::integer is distinct from session.amount_cents
      or upper(refund->>'currency') is distinct from session.currency
      or (p_outcome = 'refund_succeeded' and refund->>'status' is distinct from 'succeeded')
      or (p_outcome = 'refund_pending' and coalesce(refund->>'status','') not in ('pending','requires_action'))
    ) then raise exception 'Refund evidence mismatch'; end if;
  end if;

  insert into public.cortina_vend_events(session_id, source, event_type, event_key, payload)
  values(p_session, 'clean_stream', 'reconciliation', 'reconcile:' || p_claim,
    jsonb_build_object('outcome',p_outcome,'reason',p_reason,
      'previous_status',session.status,'payment_intent_id',payment->>'id',
      'refund_id',refund->>'id','refund_status',refund->>'status'));

  update public.cortina_vend_sessions set
    status = case when p_outcome = 'refund_succeeded' then 'refunded'
      when p_outcome = 'payment_pending' and session.status = 'payment_pending' then 'payment_pending'
      else 'support_required' end,
    completed_at = case when p_outcome = 'refund_succeeded' then clock_timestamp() else completed_at end,
    failure_message = case when p_outcome = 'payment_pending' and session.status = 'payment_pending'
      then failure_message else 'Reconciliation: ' || p_reason end
  where id = p_session;
  update public.cortina_vend_sessions set
    reconcile_claim = null, reconcile_claim_until = null,
    reconcile_attempts = session.reconcile_attempts,
    reconcile_after = retry_at, reconcile_reason = p_reason, reconciled_at = clock_timestamp()
  where id = p_session;
  -- Nested audit/unique-index writes can wait after the initial row lock.
  -- Raise (not return false) so an expired observation rolls back every write.
  if session.reconcile_claim_until <= clock_timestamp() then
    raise exception 'Reconciliation lease expired during settlement' using errcode='40001';
  end if;
  return true;
end;
$$;

revoke all on function public.claim_cortina_reconciliation(text) from public, anon, authenticated;
revoke all on function public.finish_cortina_reconciliation(uuid,uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.claim_cortina_reconciliation(text) to service_role;
grant execute on function public.finish_cortina_reconciliation(uuid,uuid,text,text,jsonb) to service_role;
