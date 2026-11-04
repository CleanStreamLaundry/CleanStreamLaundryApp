-- Local new-payment creation control only. No settlement/recovery gates.
begin;

do $$
begin
  if current_user <> 'postgres' or to_regclass('private.account_lifecycle') is null or
     to_regprocedure('public.get_admission_status()') is null or
     to_regprocedure('public.redeem_wallet_for_machine(uuid,bigint,integer,text)') is null or
     to_regprocedure('public.redeem_wallet_for_cortina(uuid)') is null then
    raise exception 'Reviewed human wallet admission prerequisites required' using errcode = '55000';
  end if;
end;
$$;

create table private.new_payment_service_control (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true
);
alter table private.new_payment_service_control enable row level security;
revoke all on table private.new_payment_service_control from public, anon, authenticated, service_role;
grant usage on schema private to service_role;
grant select on table private.new_payment_service_control to service_role;
grant update (enabled) on table private.new_payment_service_control to service_role;
create policy new_payment_control_service_read on private.new_payment_service_control
  for select to service_role using (true);
create policy new_payment_control_service_update on private.new_payment_service_control
  for update to service_role using (true) with check (singleton is true);

-- Installation is behavior-preserving; absence later must never imply enabled.
insert into private.new_payment_service_control(singleton, enabled) values (true, true);

create function public.new_payments_enabled()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare enabled_now boolean;
begin
  select count(*) = 1 and coalesce(bool_and(singleton is true and enabled is true), false)
    into enabled_now from private.new_payment_service_control;
  return enabled_now is true;
exception when others then
  raise exception 'new_payments_unavailable' using errcode = 'PT503';
end;
$$;
revoke all on function public.new_payments_enabled() from public, anon, authenticated, service_role;
grant execute on function public.new_payments_enabled() to anon, authenticated, service_role;

create function private.require_new_payments_enabled()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if public.new_payments_enabled() is distinct from true then
    raise exception 'new_payments_unavailable' using errcode = 'PT503';
  end if;
end;
$$;
revoke all on function private.require_new_payments_enabled() from public, anon, authenticated, service_role;

-- Preserve both existing contracts and ACLs. Fresh volatile reads after existing
-- waits observe a committed disable without locking the control row against it.
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
  perform private.require_new_payments_enabled();
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
  perform private.require_new_payments_enabled();

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
  perform private.require_new_payments_enabled();
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
  perform private.require_new_payments_enabled();
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

  perform private.require_new_payments_enabled();

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
  perform private.require_new_payments_enabled();
  return redemption;
end;
$$;

commit;
