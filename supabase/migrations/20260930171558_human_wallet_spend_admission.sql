-- Human debit boundaries only. Provider settlement/reversal/refund routines and
-- function ACLs are unchanged. Requires the reviewed wallet serialization batch.
begin;

do $$
declare signature text;
begin
  if current_user <> 'postgres' or to_regclass('private.account_lifecycle') is null then
    raise exception 'Reviewed lifecycle and wallet prerequisites required' using errcode = '55000';
  end if;
  foreach signature in array array[
    'public.get_admission_status()',
    'public.get_or_create_wallet_account(uuid)',
    'public.sync_profile_wallet_balance(uuid)',
    'public.redeem_wallet_for_machine(uuid,bigint,integer,text)',
    'public.redeem_wallet_for_cortina(uuid)'
  ] loop
    if to_regprocedure(signature) is null then
      raise exception 'Required human wallet routine missing: %', signature using errcode = '55000';
    end if;
  end loop;
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
  -- Canonical Home admission includes current session/MFA, lifecycle and terms.
  -- Its Auth SHARE lock precedes the existing financial locks.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if amount_cents is null or amount_cents <= 0 then
    raise exception 'Invalid amount';
  end if;

  wallet_id := public.get_or_create_wallet_account(target_user_id);
  -- Keep wallet -> profile, shared with funding/cache synchronization. Lifecycle
  -- requests hold this profile lock but never wait for a wallet.
  perform 1 from public.profiles where id = target_user_id for no key update;
  if not found then raise exception 'account_restricted' using errcode = 'PT403'; end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

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
  -- Includes waits inside ledger/cache triggers. A late revocation rolls back
  -- redemption, ledger, spend provenance and compatibility cache together.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  return jsonb_build_object(
    'wallet_account_id', wallet_id, 'redemption_id', redemption_id,
    'paid_debit_cents', paid_debit, 'promo_debit_cents', promo_debit
  );
end;
$$;

create or replace function public.redeem_wallet_for_cortina(
  target_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_session public.cortina_vend_sessions%rowtype;
  redemption jsonb;
begin
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  select * into target_session
  from public.cortina_vend_sessions
  where id = target_session_id
  for update;

  if not found or target_session.payment_method <> 'wallet' or
     target_session.status <> 'payment_pending' then
    raise exception 'Wallet vend session is not payable';
  end if;

  if target_session.user_id is null or
     target_session.user_id is distinct from (select auth.uid()) then
    raise exception 'Unauthorized';
  end if;

  -- Reuses the inner RPC's post-wait admission and wallet -> profile locks.
  redemption := public.redeem_wallet_for_machine(
    target_session.user_id,
    target_session.machine_id,
    target_session.amount_cents,
    'Cortina vend ' || target_session.id
  );

  update public.cortina_vend_sessions
  set
    status = 'paid',
    wallet_redemption_id = (redemption->>'redemption_id')::bigint
  where id = target_session.id;

  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  return redemption;
end;
$$;

commit;
