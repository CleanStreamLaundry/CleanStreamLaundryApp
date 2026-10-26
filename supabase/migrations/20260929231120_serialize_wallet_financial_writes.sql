begin;

-- Replacements must never silently create a missing, PUBLIC-executable RPC.
do $$
declare signature text;
begin
  foreach signature in array array[
    'public.get_or_create_wallet_account(uuid)',
    'public.sync_profile_wallet_balance(uuid)',
    'public.record_wallet_load_from_stripe(uuid,integer,text,text,text,text)',
    'public.redeem_wallet_for_machine(uuid,bigint,integer,text)',
    'public.admin_adjust_wallet(uuid,integer,integer,integer,text)',
    'public.admin_record_legal_cash_redemption(uuid,integer,text,text)',
    'public.admin_set_wallet_status(uuid,text,text)',
    'public.reverse_cortina_wallet_redemption(uuid)',
    'public.resolve_refund_request(bigint,text,text,uuid)'
  ] loop
    if to_regprocedure(signature) is null then
      raise exception 'Required wallet routine missing: %', signature;
    end if;
  end loop;
end;
$$;

create or replace function public.get_or_create_wallet_account(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  wallet_id uuid;
begin
  if target_user_id is null then
    raise exception 'Missing user id';
  end if;

  select wa.id into wallet_id
  from public.wallet_accounts wa
  where wa.user_id = target_user_id
  for no key update;

  if wallet_id is null then
    -- The conflict update also holds the wallet row until transaction end.
    insert into public.wallet_accounts(user_id)
    values (target_user_id)
    on conflict (user_id) do update set updated_at = now()
    returning id into wallet_id;
  end if;

  return wallet_id;
end;
$$;

create or replace function public.sync_profile_wallet_balance(wallet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  total_cents integer;
begin
  -- Lock before aggregation: waiting only at the profile UPDATE caches stale totals.
  select wa.user_id into target_user_id
  from public.wallet_accounts wa
  where wa.id = wallet_id
  for no key update;

  if target_user_id is not null then
    select wb.total_balance_cents into total_cents
    from public.wallet_balances wb
    where wb.wallet_account_id = wallet_id;

    update public.profiles
    set balance = coalesce(total_cents, 0)::numeric / 100.0
    where id = target_user_id;
  end if;
end;
$$;

create or replace function public.record_wallet_load_from_stripe(
  target_user_id uuid,
  amount_cents integer,
  stripe_payment_intent_id text default null,
  stripe_checkout_session_id text default null,
  stripe_charge_id text default null,
  stripe_event_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  wallet_id uuid;
  load_id bigint;
  existing_wallet_id uuid;
  reward_before_cents integer;
  combined_cents integer;
  bonus_count integer;
  bonus_cents integer;
  remainder_cents integer;
begin
  if target_user_id is null or amount_cents is null or amount_cents <= 0 then
    raise exception 'Invalid wallet load';
  end if;

  -- Preserve completed-delivery retries, including previously anonymized loads.
  select wl.wallet_account_id into existing_wallet_id
  from public.wallet_loads wl
  where (record_wallet_load_from_stripe.stripe_payment_intent_id is not null and wl.stripe_payment_intent_id = record_wallet_load_from_stripe.stripe_payment_intent_id)
     or (record_wallet_load_from_stripe.stripe_checkout_session_id is not null and wl.stripe_checkout_session_id = record_wallet_load_from_stripe.stripe_checkout_session_id)
     or (record_wallet_load_from_stripe.stripe_event_id is not null and wl.stripe_event_id = record_wallet_load_from_stripe.stripe_event_id)
  limit 1;

  if existing_wallet_id is not null then
    return existing_wallet_id;
  end if;

  wallet_id := public.get_or_create_wallet_account(target_user_id);

  -- A concurrent delivery may have committed while this call waited for the wallet.
  select wl.wallet_account_id into existing_wallet_id
  from public.wallet_loads wl
  where (record_wallet_load_from_stripe.stripe_payment_intent_id is not null and wl.stripe_payment_intent_id = record_wallet_load_from_stripe.stripe_payment_intent_id)
     or (record_wallet_load_from_stripe.stripe_checkout_session_id is not null and wl.stripe_checkout_session_id = record_wallet_load_from_stripe.stripe_checkout_session_id)
     or (record_wallet_load_from_stripe.stripe_event_id is not null and wl.stripe_event_id = record_wallet_load_from_stripe.stripe_event_id)
  limit 1;

  if existing_wallet_id is not null then
    return existing_wallet_id;
  end if;

  select coalesce(round(p.reward_tracker * 100), 0)::integer
    into reward_before_cents
  from public.profiles p
  where p.id = target_user_id
  for no key update;

  if not found then
    raise exception 'Wallet load profile not found';
  end if;

  combined_cents := reward_before_cents + amount_cents;
  bonus_count := combined_cents / 2000;
  bonus_cents := bonus_count * 500;
  remainder_cents := combined_cents % 2000;

  -- Captured Stripe payments settle even when the wallet is locked for spending.
  insert into public.wallet_loads(
    wallet_account_id, user_id, amount_cents, paid_amount_cents,
    promo_amount_cents, stripe_payment_intent_id, stripe_checkout_session_id,
    stripe_charge_id, stripe_event_id, status, note
  ) values (
    wallet_id, target_user_id, amount_cents, amount_cents, bonus_cents,
    stripe_payment_intent_id, stripe_checkout_session_id, stripe_charge_id,
    stripe_event_id, 'succeeded', 'Stripe wallet load'
  ) returning id into load_id;

  insert into public.wallet_ledger_entries(
    wallet_account_id, entry_type, amount_cents, paid_amount_cents,
    promo_amount_cents, wallet_load_id, stripe_payment_intent_id, stripe_charge_id, note
  ) values (
    wallet_id, 'load_paid', amount_cents, amount_cents, 0, load_id,
    stripe_payment_intent_id, stripe_charge_id, 'Paid loyalty card load'
  );

  if bonus_cents > 0 then
    insert into public.wallet_ledger_entries(
      wallet_account_id, entry_type, amount_cents, paid_amount_cents,
      promo_amount_cents, wallet_load_id, stripe_payment_intent_id, stripe_charge_id, note
    ) values (
      wallet_id, 'load_bonus', bonus_cents, 0, bonus_cents, load_id,
      stripe_payment_intent_id, stripe_charge_id, 'Promotional loyalty reward credit'
    );
  end if;

  update public.profiles
  set reward_tracker = remainder_cents::numeric / 100.0
  where id = target_user_id;

  perform public.sync_profile_wallet_balance(wallet_id);
  return wallet_id;
end;
$$;

create or replace function public.redeem_wallet_for_machine(
  target_user_id uuid,
  target_machine_id bigint,
  amount_cents integer,
  redemption_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  wallet_id uuid;
  wallet_status text;
  paid_balance integer;
  promo_balance integer;
  promo_debit integer;
  paid_debit integer;
  redemption_id bigint;
begin
  if target_user_id is null or auth.uid() is null or
     auth.uid() is distinct from target_user_id then
    raise exception 'Unauthorized';
  end if;
  if amount_cents is null or amount_cents <= 0 then
    raise exception 'Invalid amount';
  end if;

  wallet_id := public.get_or_create_wallet_account(target_user_id);
  select wb.status, wb.paid_balance_cents, wb.promo_balance_cents
    into wallet_status, paid_balance, promo_balance
  from public.wallet_balances wb
  where wb.wallet_account_id = wallet_id;

  if wallet_status is distinct from 'active' then
    raise exception 'Wallet is not active';
  end if;
  if paid_balance < 0 or promo_balance < 0 or
     coalesce(paid_balance, 0)::bigint + coalesce(promo_balance, 0) < amount_cents then
    raise exception 'Insufficient balance';
  end if;

  promo_debit := least(coalesce(promo_balance, 0), amount_cents);
  paid_debit := amount_cents - promo_debit;

  insert into public.wallet_redemptions(
    wallet_account_id, user_id, machine_id, amount_cents,
    paid_amount_cents, promo_amount_cents, status, note
  ) values (
    wallet_id, target_user_id, target_machine_id, amount_cents,
    paid_debit, promo_debit, 'succeeded', redemption_note
  ) returning id into redemption_id;

  if promo_debit > 0 then
    insert into public.wallet_ledger_entries(
      wallet_account_id, entry_type, amount_cents, paid_amount_cents,
      promo_amount_cents, machine_id, note
    ) values (
      wallet_id, 'redeem_bonus', -promo_debit, 0, -promo_debit,
      target_machine_id, redemption_note
    );
  end if;
  if paid_debit > 0 then
    insert into public.wallet_ledger_entries(
      wallet_account_id, entry_type, amount_cents, paid_amount_cents,
      promo_amount_cents, machine_id, note
    ) values (
      wallet_id, 'redeem_paid', -paid_debit, -paid_debit, 0,
      target_machine_id, redemption_note
    );
  end if;

  perform public.sync_profile_wallet_balance(wallet_id);
  return jsonb_build_object(
    'wallet_account_id', wallet_id, 'redemption_id', redemption_id,
    'paid_debit_cents', paid_debit, 'promo_debit_cents', promo_debit
  );
end;
$$;

create or replace function public.admin_adjust_wallet(
  wallet_id uuid,
  amount_cents integer,
  paid_amount_cents integer,
  promo_amount_cents integer,
  adjustment_note text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry_id bigint;
  paid_balance integer;
  promo_balance integer;
begin
  if not public.is_admin_or_owner() then
    raise exception 'Unauthorized';
  end if;
  if adjustment_note is null or btrim(adjustment_note) = '' then
    raise exception 'Admin note required';
  end if;
  if amount_cents is null or paid_amount_cents is null or promo_amount_cents is null or
     amount_cents::bigint <> paid_amount_cents::bigint + promo_amount_cents then
    raise exception 'Invalid wallet adjustment';
  end if;

  perform 1 from public.wallet_accounts wa
  where wa.id = wallet_id for no key update;
  if not found then raise exception 'Wallet not found'; end if;

  select wb.paid_balance_cents, wb.promo_balance_cents into paid_balance, promo_balance
  from public.wallet_balances wb where wb.wallet_account_id = wallet_id;
  if paid_balance::bigint + paid_amount_cents < 0 or
     promo_balance::bigint + promo_amount_cents < 0 then
    raise exception 'Insufficient balance';
  end if;

  insert into public.wallet_ledger_entries(
    wallet_account_id, entry_type, amount_cents, paid_amount_cents,
    promo_amount_cents, note, created_by
  ) values (
    wallet_id, 'admin_adjustment', amount_cents, paid_amount_cents,
    promo_amount_cents, adjustment_note, auth.uid()
  ) returning id into entry_id;

  perform public.sync_profile_wallet_balance(wallet_id);
  return entry_id;
end;
$$;

create or replace function public.admin_record_legal_cash_redemption(
  wallet_id uuid,
  amount_cents integer,
  stripe_refund_id text default null,
  redemption_note text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry_id bigint;
  paid_balance integer;
  promo_balance integer;
begin
  if not public.is_admin_or_owner() then
    raise exception 'Unauthorized';
  end if;
  if amount_cents is null or amount_cents <= 0 then
    raise exception 'Invalid amount';
  end if;
  if redemption_note is null or btrim(redemption_note) = '' then
    raise exception 'Admin note required';
  end if;

  perform 1 from public.wallet_accounts wa
  where wa.id = wallet_id for no key update;
  if not found then raise exception 'Wallet not found'; end if;
  select wb.paid_balance_cents, wb.promo_balance_cents into paid_balance, promo_balance
  from public.wallet_balances wb where wb.wallet_account_id = wallet_id;
  if paid_balance < amount_cents or promo_balance < 0 then
    raise exception 'Insufficient balance';
  end if;

  insert into public.wallet_ledger_entries(
    wallet_account_id, entry_type, amount_cents, paid_amount_cents,
    promo_amount_cents, stripe_refund_id, note, created_by
  ) values (
    wallet_id, case when stripe_refund_id is null then 'legal_cash_redemption' else 'stripe_refund' end,
    -amount_cents, -amount_cents, 0, stripe_refund_id, redemption_note, auth.uid()
  ) returning id into entry_id;

  perform public.sync_profile_wallet_balance(wallet_id);
  return entry_id;
end;
$$;

create or replace function public.admin_set_wallet_status(
  wallet_id uuid,
  new_status text,
  status_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare current_status text;
begin
  if not public.is_admin_or_owner() then raise exception 'Unauthorized'; end if;
  if new_status is null or new_status not in ('active', 'locked') then
    raise exception 'Invalid admin wallet status';
  end if;

  select wa.status into current_status from public.wallet_accounts wa
  where wa.id = wallet_id for no key update;
  if not found then raise exception 'Wallet not found'; end if;
  if current_status = 'deleted' then raise exception 'Wallet is deleted'; end if;

  update public.wallet_accounts
  set status = new_status,
      locked_at = case when new_status = 'locked' then now() else null end,
      updated_at = now()
  where id = wallet_id;
end;
$$;

create or replace function public.reverse_cortina_wallet_redemption(target_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_session public.cortina_vend_sessions%rowtype;
  target_redemption public.wallet_redemptions%rowtype;
  wallet_id uuid;
begin
  select * into target_session from public.cortina_vend_sessions
  where id = target_session_id for update;
  if not found or target_session.payment_method <> 'wallet' or
     target_session.wallet_redemption_id is null then
    raise exception 'Wallet vend session not found';
  end if;

  -- Discover the wallet without locking the child ahead of anonymization's parent lock.
  select wr.wallet_account_id into wallet_id from public.wallet_redemptions wr
  where wr.id = target_session.wallet_redemption_id;
  if not found then raise exception 'Wallet redemption not found'; end if;

  perform 1 from public.wallet_accounts wa
  where wa.id = wallet_id for no key update;
  if not found then raise exception 'Wallet not found'; end if;

  select * into target_redemption from public.wallet_redemptions wr
  where wr.id = target_session.wallet_redemption_id and wr.wallet_account_id = wallet_id
  for update;
  if not found then raise exception 'Wallet redemption changed'; end if;
  if target_redemption.status = 'void' then return false; end if;

  insert into public.wallet_ledger_entries(
    wallet_account_id, entry_type, amount_cents, paid_amount_cents,
    promo_amount_cents, machine_id, note
  ) values (
    wallet_id, 'void', target_redemption.amount_cents,
    target_redemption.paid_amount_cents, target_redemption.promo_amount_cents,
    target_redemption.machine_id, 'Cortina vend reversal for session ' || target_session_id
  );
  update public.wallet_redemptions set status = 'void' where id = target_redemption.id;
  perform public.sync_profile_wallet_balance(wallet_id);
  update public.cortina_vend_sessions set status = 'refunded', completed_at = now()
  where id = target_session_id;
  return true;
end;
$$;

create or replace function public.resolve_refund_request(
  target_refund_id bigint,
  target_decision text,
  resolution_note text,
  actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_refund public."Refunds"%rowtype;
  wallet_id uuid;
  refund_amount_cents integer;
  normalized_note text := nullif(btrim(coalesce(resolution_note, '')), '');
  target_session_id uuid;
begin
  if actor_user_id is null or not exists (
    select 1 from public.profiles where id = actor_user_id
      and roles in ('Admin'::public."Roles", 'Owner'::public."Roles")
  ) then
    raise exception using errcode = '42501', message = 'Unauthorized';
  end if;
  if target_decision not in ('approved', 'denied') then
    raise exception using errcode = '22023', message = 'Invalid refund decision';
  end if;

  select * into target_refund from public."Refunds"
  where refund_id = target_refund_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Refund request not found';
  end if;
  if target_refund.status::text <> 'pending' then
    if target_refund.status::text <> target_decision then
      raise exception using errcode = 'P0001',
        message = format('Refund request is already %s', target_refund.status::text);
    end if;
    return jsonb_build_object(
      'success', true, 'alreadyResolved', true, 'refundId', target_refund.refund_id,
      'transactionId', target_refund.transaction_id, 'customerId', target_refund.user_id,
      'amount', target_refund.amount, 'status', target_refund.status::text,
      'notificationSent', target_refund.notification_sent_at is not null
    );
  end if;

  -- Freeze the trigger's session lookup. Direct Refunds updates already hold the
  -- refund row before their trigger requests the session, so do not reverse that
  -- order here. A contended session aborts BEFORE the wallet/credit is touched.
  select t.cortina_vend_session_id into target_session_id
  from public.transactions t where t.id = target_refund.transaction_id for share;
  if target_session_id is not null then
    begin
      perform 1 from public.cortina_vend_sessions
      where id = target_session_id for update nowait;
    exception when lock_not_available then
      raise exception using errcode = '55P03', message = 'Credit request is busy; retry';
    end;
  end if;

  if target_decision = 'approved' then
    refund_amount_cents := round((target_refund.amount * 100)::numeric)::integer;
    if refund_amount_cents is null or refund_amount_cents <= 0 then
      raise exception using errcode = '22023', message = 'Refund amount must be positive';
    end if;
    wallet_id := public.get_or_create_wallet_account(target_refund.user_id);
    insert into public.wallet_ledger_entries(
      wallet_account_id, entry_type, amount_cents, paid_amount_cents,
      promo_amount_cents, note, created_by, refund_request_id
    ) values (
      wallet_id, 'admin_adjustment', refund_amount_cents, 0, refund_amount_cents,
      concat('Approved loyalty balance credit',
        case when normalized_note is null then '' else ': ' || normalized_note end),
      actor_user_id, target_refund.refund_id
    );
    perform public.sync_profile_wallet_balance(wallet_id);
  end if;

  update public."Refunds"
  set status = target_decision::public.refund_status, admin_note = normalized_note,
      resolved_by = actor_user_id, resolved_at = now()
  where refund_id = target_refund.refund_id;
  return jsonb_build_object(
    'success', true, 'alreadyResolved', false, 'refundId', target_refund.refund_id,
    'transactionId', target_refund.transaction_id, 'customerId', target_refund.user_id,
    'amount', target_refund.amount, 'status', target_decision,
    'notificationSent', false
  );
end;
$$;

commit;
