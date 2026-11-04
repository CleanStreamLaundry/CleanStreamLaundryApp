-- GENERATED: exact reviewed DEVELOPMENT C/D installation, no historical backfill.
-- Target: dnuuhupoxjtwqzaqylvb. A/B already installed; never replay foundations.
-- See cd-sources.sha256 and scripts/activation-cd.test.mjs for byte provenance.
BEGIN;

-- SOURCE: supabase/migrations/20260929231120_serialize_wallet_financial_writes.sql

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



-- SOURCE: supabase/migrations/20260930024142_protect_location_membership.sql

-- The reviewed production graph has no parents for either client role. Stop
-- on drift; never revoke another role's grants or membership to force a pass.
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public."Location_to_Admin"'::regclass
      and c.relkind = 'r' and c.relrowsecurity and not c.relforcerowsecurity
      and pg_get_userbyid(c.relowner) = 'postgres'
  ) or current_user <> 'postgres' then
    raise exception 'Membership table ownership or RLS requires review'
      using errcode = '42501';
  end if;
  if (select count(*) from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated')) <> 2
    or exists (select 1 from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated')
        and (rolsuper or rolbypassrls or rolcreaterole))
    or exists (select 1 from pg_catalog.pg_auth_members m
      join pg_catalog.pg_roles r on r.oid = m.member
      where r.rolname in ('anon', 'authenticated')) then
    raise exception 'Client role authority or inheritance requires review'
      using errcode = '42501';
  end if;
end;
$$;

revoke insert, update, delete, truncate, references, trigger, maintain
  on public."Location_to_Admin" from public, anon, authenticated restrict;

do $$
declare
  columns_list text;
begin
  select string_agg(format('%I', attname), ', ' order by attnum)
    into columns_list
  from pg_catalog.pg_attribute
  where attrelid = 'public."Location_to_Admin"'::regclass
    and attnum > 0 and not attisdropped;
  execute format(
    'revoke insert (%1$s), update (%1$s), references (%1$s) on public."Location_to_Admin" from public, anon, authenticated restrict',
    columns_list
  );
  if exists (
    select 1 from (values ('anon'), ('authenticated')) r(name)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
      ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) p(privilege)
    where has_table_privilege(r.name, 'public."Location_to_Admin"', p.privilege)
  ) or exists (
    select 1 from (values ('anon'), ('authenticated')) r(name)
    cross join (values ('INSERT'), ('UPDATE'), ('REFERENCES')) p(privilege)
    where has_any_column_privilege(r.name, 'public."Location_to_Admin"', p.privilege)
  ) then
    raise exception 'Remaining effective membership privileges require review'
      using errcode = '42501';
  end if;
end;
$$;

-- Effective executor, not a forgeable JWT role: trusted definers and FK
-- cascades execute as their database owner. Their authorization is separate.
create function public.guard_location_membership_writes()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon', 'authenticated') then
    raise exception 'Membership writes require a trusted server writer'
      using errcode = '42501';
  end if;
  return null;
end;
$$;

create trigger location_membership_writes_guard
before insert or update or delete or truncate on public."Location_to_Admin"
for each statement execute function public.guard_location_membership_writes();
alter table public."Location_to_Admin"
  enable always trigger location_membership_writes_guard;
revoke all on function public.guard_location_membership_writes()
  from public, anon, authenticated, service_role;



-- SOURCE: supabase/migrations/20260930125554_voluntary_topup_refunds.sql
-- Local candidate only. No historical provenance backfill or provider calls.

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


-- SOURCE: admin-portal-install-no-backfill.sql

-- All portal mutations run through an authenticated Edge Function. These RPCs
-- are invoker functions, callable only with the server's service role.
alter table public."Maintenance"
  add column if not exists status text not null default 'open' check (status in ('open','in_progress','resolved')),
  add column if not exists location_id bigint references public."Locations"(id),
  add column if not exists updated_at timestamptz not null default now();

-- Development install: historical address attribution is deliberately omitted.
-- Existing rows and addresses are preserved; no location ownership is inferred.

create table public.admin_maintenance_history (
  id bigint generated always as identity primary key,
  maintenance_id text not null,
  actor_id uuid references auth.users(id) on delete set null,
  actor_name text not null,
  from_status text not null,
  to_status text not null,
  note text,
  created_at timestamptz not null default now()
);
create index on public.admin_maintenance_history(maintenance_id, created_at desc);
alter table public.admin_maintenance_history enable row level security;
revoke all on public.admin_maintenance_history from anon, authenticated;
grant all on public.admin_maintenance_history to service_role;
grant usage, select on sequence public.admin_maintenance_history_id_seq to service_role;

create table public.admin_invitations (
  user_id uuid not null references auth.users(id) on delete cascade,
  location_id bigint not null references public."Locations"(id) on delete cascade,
  invited_by uuid not null references auth.users(id),
  invited_at timestamptz not null default now(),
  last_sent_at timestamptz,
  delivery_status text not null default 'pending' check (delivery_status in ('pending','sent','failed')),
  primary key(user_id, location_id)
);
alter table public.admin_invitations enable row level security;
revoke all on public.admin_invitations from anon, authenticated;
grant all on public.admin_invitations to service_role;

-- Role assignments cannot be written by a customer or a compromised browser.
create function public.guard_portal_authority() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') then
    if tg_op = 'INSERT' and new.roles::text is distinct from 'User' then
      raise exception 'Role assignment requires a trusted administrator' using errcode = '42501';
    elsif tg_op = 'UPDATE' and new.roles is distinct from old.roles then
      raise exception 'Role assignment requires a trusted administrator' using errcode = '42501';
    end if;
  end if;
  return new;
end; $$;
create trigger portal_authority_guard before insert or update on public.profiles for each row execute function public.guard_portal_authority();
revoke all on function public.guard_portal_authority() from public, anon, authenticated;
revoke insert, update, delete on public."Location_to_Admin" from anon, authenticated;
-- Management writes now use the verified portal RPC. Public/mobile inventory
-- reads and customer maintenance submissions remain available under their RLS.
revoke insert, update, delete on public."Machines", public."Locations", public.washer_size_rates, public.cortina_machine_config from anon, authenticated;
revoke update, delete on public."Maintenance", public."Refunds" from anon, authenticated;

create function public.portal_transaction_location(record jsonb) returns bigint language sql stable security invoker set search_path = '' as $$
  select m."Location_ID" from public.cortina_vend_sessions s
  join public."Machines" m on m.id = s.machine_id
  where s.id::text = record->>'cortina_vend_session_id' limit 1;
$$;
revoke all on function public.portal_transaction_location(jsonb) from public, anon, authenticated;
grant execute on function public.portal_transaction_location(jsonb) to service_role;

create function public.admin_portal_data(actor uuid, action text, payload jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  actor_role text; actor_name text; ids bigint[]; loc bigint; target uuid;
  items jsonb := '[]'; result jsonb; input jsonb := coalesce(payload->'input','{}');
  f jsonb := coalesce(payload->'filters','{}'); page_number integer; total integer;
  row_data record; existing public."Maintenance"%rowtype;
  next_status text; note text; rate public.washer_size_rates%rowtype;
  config jsonb; enabled boolean; valid_config boolean; machine public."Machines"%rowtype;
  business_today date := (now() at time zone 'America/Indiana/Indianapolis')::date;
  start_time timestamptz; end_time timestamptz;
begin
  select p.roles::text, coalesce(nullif(p.full_name,''),p.email,'Team member') into actor_role, actor_name from public.profiles p where p.id = actor;
  if actor_role is null or actor_role not in ('Admin','Owner') then raise exception 'Owner or Admin access required' using errcode='42501'; end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id = actor;
  if action = 'identity' then
    return (select jsonb_build_object('id',p.id,'name',p.full_name,'email',u.email,'role',p.roles) from public.profiles p join auth.users u on u.id=p.id where p.id=actor);
  end if;
  if action = 'locations' then return (select coalesce(jsonb_agg(to_jsonb(l) order by l."Name"),'[]') from public."Locations" l where l.id=any(ids)); end if;
  if action in ('rates','machines') then
    loc := (payload->>'locationId')::bigint;
    if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
    if action='rates' then return (select coalesce(jsonb_agg(to_jsonb(r) order by capacity_kg),'[]') from public.washer_size_rates r where r.location_id=loc); end if;
    return (select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('Price',coalesce(r.price_cents::numeric/100,m."Price"),'cortina_machine_config',to_jsonb(c)) order by m."Name"),'[]') from public."Machines" m left join public.cortina_machine_config c on c.machine_id=m.id left join public.washer_size_rates r on r.id=m.washer_size_rate_id where m."Location_ID"=loc);
  end if;

  if action in ('maintenance','history','updateMaintenance') then
    if action <> 'maintenance' then
      select * into existing from public."Maintenance" where maint_id::text=payload->>'id' for update;
      if not found then raise exception 'Report not found'; end if;
      loc := coalesce(existing.location_id,(select min(id) from public."Locations" where "Address"=existing.location having count(*)=1));
      if not(coalesce(loc=any(ids),false) or (loc is null and actor_role='Owner')) then raise exception 'Report access denied' using errcode='42501'; end if;
      if action='history' then return (select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id desc),'[]') from public.admin_maintenance_history h where h.maintenance_id=existing.maint_id::text); end if;
      next_status := payload->>'status'; note := nullif(btrim(payload->>'note'),'');
      if next_status is null or next_status not in ('open','in_progress','resolved') or length(coalesce(note,''))>4000 then raise exception 'Invalid maintenance update'; end if;
      if (payload->>'expectedUpdatedAt')::timestamptz is distinct from existing.updated_at then raise exception 'This report changed. Close it, refresh the list, and try again.'; end if;
      if next_status=existing.status and note is null then raise exception 'Choose a new status or add a note'; end if;
      update public."Maintenance" set status=next_status,updated_at=clock_timestamp(),location_id=loc where maint_id=existing.maint_id;
      insert into public.admin_maintenance_history(maintenance_id,actor_id,actor_name,from_status,to_status,note) values(existing.maint_id::text,actor,actor_name,existing.status,next_status,note);
      return '{"success":true}';
    end if;
    select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('maint_id',m.maint_id::text,'date',m.created_at) order by m.created_at desc,m.maint_id),'[]') into items from public."Maintenance" m
    where (coalesce(m.location_id,(select min(id) from public."Locations" where "Address"=m.location having count(*)=1))=any(ids)
      or (actor_role='Owner' and coalesce(m.location_id,(select min(id) from public."Locations" where "Address"=m.location having count(*)=1)) is null))
      and (coalesce(f->>'status','unresolved')='all' or (coalesce(f->>'status','unresolved')='unresolved' and m.status<>'resolved') or m.status=f->>'status')
      and (coalesce(f->>'category','')='' or m.category=f->>'category');
  elsif action in ('credits','assertCredit') then
    select coalesce(jsonb_agg(jsonb_build_object('refund_id',r.refund_id,'amount',r.amount,'description',r.description,'date',r.date,'status',r.status,'customer_name',coalesce(p.full_name,'Customer'),'transaction_id',r.transaction_id,'admin_note',r.admin_note,'resolved_at',r.resolved_at,'notification_sent_at',r.notification_sent_at) order by r.date desc,r.refund_id),'[]') into items
    from public."Refunds" r join public.transactions t on t.id=r.transaction_id left join public.profiles p on p.id=r.user_id
    where (public.portal_transaction_location(to_jsonb(t))=any(ids) or (actor_role='Owner' and public.portal_transaction_location(to_jsonb(t)) is null))
      and (action='assertCredit' or coalesce(f->>'status','pending')='all' or r.status::text=coalesce(f->>'status','pending'))
      and (action<>'assertCredit' or r.refund_id::text=payload->>'id');
    if action='assertCredit' then if jsonb_array_length(items)<>1 then raise exception 'Credit request access denied' using errcode='42501'; end if; return '{"success":true}'; end if;
  elsif action='overview' then
    start_time := (business_today-29)::timestamp at time zone 'America/Indiana/Indianapolis'; end_time := (business_today+1)::timestamp at time zone 'America/Indiana/Indianapolis';
    with scoped as (select t.* from public.transactions t where t.created_at>=start_time and t.created_at<end_time and (public.portal_transaction_location(to_jsonb(t))=any(ids) or (actor_role='Owner' and public.portal_transaction_location(to_jsonb(t)) is null))),
    payments as (select * from scoped where description not in ('Loyalty payment on Dryer','Loyalty payment on Washer')),
    daily as (select day::date d,coalesce((select sum(amount) from payments where (created_at at time zone 'America/Indiana/Indianapolis')::date=day::date),0) amount from generate_series((business_today-29)::timestamp,business_today::timestamp,'1 day') day),
    hourly as (select h, (select count(*) from scoped where extract(hour from created_at at time zone 'America/Indiana/Indianapolis')=h) n from generate_series(0,23) h)
    select jsonb_build_object('today',coalesce((select sum(amount) from payments where (created_at at time zone 'America/Indiana/Indianapolis')::date=business_today),0),'total',coalesce((select sum(amount) from payments),0),'daily',(select jsonb_agg(jsonb_build_object('date',d,'amount',amount) order by d) from daily),'hourly',(select jsonb_agg(n order by h) from hourly),'locations',cardinality(ids),'machines',(select count(*) from public."Machines" where "Location_ID"=any(ids)),
      'pendingCredits',(public.admin_portal_data(actor,'credits','{"filters":{"status":"pending"}}')->>'total')::int,
      'openMaintenance',(public.admin_portal_data(actor,'maintenance','{"filters":{"status":"unresolved"}}')->>'total')::int,
      'updatedAt',now(),'financialScope',case when actor_role='Owner' then 'Assigned locations plus legacy transactions without location attribution. Existing revenue inclusion rules retained.' else 'Only transactions reliably linked to your assigned locations.' end) into result;
    return result;
  else
    if actor_role<>'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
    if action='team' then
      select coalesce(jsonb_agg(jsonb_build_object('user_id',p.id,'name',p.full_name,'email',u.email,'role',p.roles,'location_id',l.id,'location_name',l."Name",'assignment_count',(select count(*) from public."Location_to_Admin" all_assignments where all_assignments.user_id=p.id),'invitation_status',case when u.last_sign_in_at is not null then 'active' when i.delivery_status='failed' then 'failed' when i.last_sent_at is not null then 'invited' else 'pending' end,'invited_at',i.invited_at) order by p.full_name,l."Name"),'[]') into items
      from public."Location_to_Admin" a join public.profiles p on p.id=a.user_id join auth.users u on u.id=p.id join public."Locations" l on l.id=a.location_id left join public.admin_invitations i on i.user_id=a.user_id and i.location_id=a.location_id where a.location_id=any(ids);
    elsif action='createLocation' then
      if nullif(btrim(input->>'Name'),'') is null or nullif(btrim(input->>'Address'),'') is null or (input->>'Latitude')::numeric not between -90 and 90 or (input->>'Longitude')::numeric not between -180 and 180 then raise exception 'Enter a valid location name and address'; end if;
      insert into public."Locations"("Name","Address","Latitude","Longitude") values(btrim(input->>'Name'),btrim(input->>'Address'),(input->>'Latitude')::numeric,(input->>'Longitude')::numeric) returning id into loc;
      insert into public."Location_to_Admin"(user_id,location_id) values(actor,loc);
      return (select to_jsonb(l) from public."Locations" l where id=loc);
    elsif action='createMachine' then
      loc := (input->>'Location_ID')::bigint;
      if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
      if nullif(btrim(input->>'Name'),'') is null or coalesce(input->>'Machine_type','') not in ('Washer','Dryer') then raise exception 'Enter a machine name and type'; end if;
      if input->>'Machine_type'='Washer' then
        select * into rate from public.washer_size_rates where id=(input->>'washer_size_rate_id')::bigint and location_id=loc and is_active and not review_required;
        if not found then raise exception 'Select a reviewed washer rate for this location'; end if;
        if coalesce((input->>'Runtime')::int,0) not between 1 and 240 then raise exception 'Enter a cycle runtime between 1 and 240 minutes'; end if;
      elsif coalesce((input->>'Weight_kg')::numeric,0) not between 1 and 200 then raise exception 'Enter a valid machine capacity'; end if;
      -- jsonb_populate_record respects existing enum column types.
      select * into machine from jsonb_populate_record(null::public."Machines",input||jsonb_build_object('Price',case when input->>'Machine_type'='Washer' then rate.price_cents::numeric/100 else .25 end,'Runtime',case when input->>'Machine_type'='Dryer' then 5 else (input->>'Runtime')::int end,'Weight_kg',case when input->>'Machine_type'='Washer' then rate.capacity_kg else (input->>'Weight_kg')::numeric end,'washer_size_rate_id',case when input->>'Machine_type'='Washer' then rate.id else null end,'Status','idle'));
      insert into public."Machines"("Name","Price","Runtime","Status","Location_ID","Machine_type","Weight_kg",washer_size_rate_id) values(machine."Name",machine."Price",machine."Runtime",machine."Status",machine."Location_ID",machine."Machine_type",machine."Weight_kg",machine.washer_size_rate_id);
      return '{"success":true}';
    elsif action='saveRate' then
      input := payload->'rate'; loc := (input->>'location_id')::bigint;
      if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
      if nullif(btrim(input->>'size_label'),'') is null or coalesce((input->>'capacity_kg')::numeric,0) not between 1 and 200 or trunc((input->>'capacity_kg')::numeric)<>(input->>'capacity_kg')::numeric or coalesce((input->>'price_cents')::int,0) not between 25 and 100000 then raise exception 'Enter a valid size, capacity, and price'; end if;
      if coalesce((input->>'id')::bigint,0)>0 then
        update public.washer_size_rates set size_label=btrim(input->>'size_label'),capacity_kg=(input->>'capacity_kg')::bigint,price_cents=(input->>'price_cents')::int,is_active=(input->>'is_active')::boolean,review_required=false where id=(input->>'id')::bigint and location_id=loc;
        if not found then raise exception 'Rate not found in this location'; end if;
        -- A changed price cannot keep an incomplete Nayax price-array mapping
        -- marked ready. Existing quotes retain their snapshotted selectors.
        update public.cortina_machine_config c set is_enabled=false,review_required=true
        from public."Machines" m where m.id=c.machine_id and m.washer_size_rate_id=(input->>'id')::bigint
          and (not (input->>'is_active')::boolean or (c.product_codes is not null and not (c.product_codes ? (input->>'price_cents'))));
      else insert into public.washer_size_rates(location_id,size_label,capacity_kg,price_cents,is_active,review_required) values(loc,btrim(input->>'size_label'),(input->>'capacity_kg')::bigint,(input->>'price_cents')::int,(input->>'is_active')::boolean,false); end if;
      return '{"success":true}';
    elsif action in ('deleteMachine','saveConfig') then
      config := payload->'config';
      select * into machine from public."Machines" where id=coalesce((config->>'machine_id')::bigint,(payload->>'id')::bigint) for update;
      if not found or not(machine."Location_ID"=any(ids)) then raise exception 'Machine access denied' using errcode='42501'; end if;
      if action='deleteMachine' then
        if exists(select 1 from public.cortina_vend_sessions where machine_id=machine.id) then raise exception 'This machine has payment history. Disable payments instead.'; end if;
        delete from public."Machines" where id=machine.id; return '{"success":true}';
      end if;
      enabled := coalesce((config->>'is_enabled')::boolean,false);
      if enabled and machine."Machine_type"::text='Washer' and not exists(select 1 from public.washer_size_rates where id=machine.washer_size_rate_id and location_id=machine."Location_ID" and is_active and not review_required) then raise exception 'Assign an active, reviewed washer rate before enabling payments'; end if;
      if coalesce(config->>'environment','') not in ('sandbox','production') then raise exception 'Choose a valid payment environment'; end if;
      valid_config := nullif(btrim(config->>'nayax_terminal_id'),'') is not null or nullif(btrim(config->>'nayax_uniqr'),'') is not null;
      if jsonb_typeof(config->'product_codes')='object' then
        for row_data in select price from unnest(case when machine."Machine_type"::text='Dryer' then array[50,100,150,200,300,450] else array[coalesce((select price_cents from public.washer_size_rates where id=machine.washer_size_rate_id),round(machine."Price"*100)::int)] end) price loop
          valid_config := valid_config and coalesce((config->'product_codes'->>row_data.price::text) ~ '^[0-9]+$',false) and coalesce((config->'product_codes'->>row_data.price::text)::numeric between 0 and 32767,false);
        end loop;
      else valid_config := valid_config and (machine."Machine_type"::text='Dryer' or coalesce((config->>'pulse_line_number')::int between 1 and 6,false)); end if;
      if enabled and not valid_config then raise exception 'A terminal identifier and a valid selector for every price are required before enabling payments'; end if;
      insert into public.cortina_machine_config(machine_id,nayax_terminal_id,nayax_uniqr,pulse_line_number,product_codes,environment,is_enabled,review_required)
      values(machine.id,nullif(btrim(config->>'nayax_terminal_id'),''),nullif(btrim(config->>'nayax_uniqr'),''),case when jsonb_typeof(config->'product_codes')='object' then null when machine."Machine_type"::text='Dryer' then 1 else (config->>'pulse_line_number')::int end,nullif(config->'product_codes','null'::jsonb),config->>'environment',enabled,not valid_config)
      on conflict(machine_id) do update set nayax_terminal_id=excluded.nayax_terminal_id,nayax_uniqr=excluded.nayax_uniqr,pulse_line_number=excluded.pulse_line_number,product_codes=excluded.product_codes,environment=excluded.environment,is_enabled=excluded.is_enabled,review_required=excluded.review_required;
      return '{"success":true}';
    elsif action in ('assignMember','removeMember','assertMember') then
      loc := (payload->>'locationId')::bigint; target := (payload->>'userId')::uuid;
      if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
      perform 1 from public.profiles where id=target for update;
      if not found then raise exception 'Account profile not found'; end if;
      if exists(select 1 from public.profiles where id=target and roles::text='Owner') then raise exception 'Owner accounts cannot be modified through team management' using errcode='42501'; end if;
      if action='assignMember' then
        update public.profiles set roles='Admin' where id=target;
        insert into public."Location_to_Admin"(user_id,location_id) select target,loc where not exists(select 1 from public."Location_to_Admin" where user_id=target and location_id=loc);
        insert into public.admin_invitations(user_id,location_id,invited_by) values(target,loc,actor) on conflict(user_id,location_id) do nothing;
      elsif action='removeMember' then
        delete from public."Location_to_Admin" where user_id=target and location_id=loc;
        delete from public.admin_invitations where user_id=target and location_id=loc;
        if not exists(select 1 from public."Location_to_Admin" where user_id=target) then update public.profiles set roles='User' where id=target and roles::text='Admin'; end if;
      elsif not exists(select 1 from public."Location_to_Admin" where user_id=target and location_id=loc) then raise exception 'Team member not found in this location'; end if;
      return '{"success":true}';
    else raise exception 'Unknown admin action'; end if;
  end if;
  -- Explicit dates are inclusive business dates; no hidden age cutoff.
  page_number := greatest(1,least(coalesce((f->>'page')::int,1),100000));
  if nullif(f->>'from','') is not null and nullif(f->>'to','') is not null and (f->>'from')::date>(f->>'to')::date then raise exception 'Start date must be before the end date'; end if;
  select coalesce(jsonb_agg(value),'[]') into items from jsonb_array_elements(items) where
    (coalesce(f->>'search','')='' or lower(value::text) like '%'||lower(replace(replace(replace(f->>'search','\','\\'),'%','\%'),'_','\_'))||'%')
    and (nullif(f->>'from','') is null or (value->>'date')::timestamptz >= (f->>'from')::date::timestamp at time zone 'America/Indiana/Indianapolis')
    and (nullif(f->>'to','') is null or (value->>'date')::timestamptz < ((f->>'to')::date+1)::timestamp at time zone 'America/Indiana/Indianapolis');
  total := jsonb_array_length(items);
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value),'[]') from (select value from jsonb_array_elements(items) with ordinality order by ordinality limit 20 offset (page_number-1)*20) page),'total',total,'page',page_number,'pageSize',20);
end; $$;
revoke all on function public.admin_portal_data(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.admin_portal_data(uuid,text,jsonb) to service_role;

create function public.admin_portal_assign_member(actor uuid, target uuid, target_locations bigint[])
returns void language plpgsql security invoker set search_path = '' as $$
declare loc bigint; email_address text;
begin
  if cardinality(target_locations) is null or cardinality(target_locations)<1 or cardinality(target_locations)>50 then raise exception 'Choose at least one location'; end if;
  if not exists(select 1 from public.profiles where id=actor and roles::text='Owner') then raise exception 'Owner access required' using errcode='42501'; end if;
  if exists(select 1 from unnest(target_locations) l where not exists(select 1 from public."Location_to_Admin" where user_id=actor and location_id=l)) then raise exception 'Location access denied' using errcode='42501'; end if;
  select email into email_address from auth.users where id=target;
  if email_address is null then raise exception 'Auth account not found'; end if;
  insert into public.profiles(id,email,roles) values(target,email_address,'User') on conflict(id) do nothing;
  foreach loc in array target_locations loop
    perform public.admin_portal_data(actor,'assignMember',jsonb_build_object('userId',target,'locationId',loc));
  end loop;
end; $$;
revoke all on function public.admin_portal_assign_member(uuid,uuid,bigint[]) from public, anon, authenticated;
grant execute on function public.admin_portal_assign_member(uuid,uuid,bigint[]) to service_role;

-- Operator-only bootstrap; there is deliberately no public HTTP route for this.
create function public.admin_portal_bootstrap_owner(target uuid, target_locations bigint[])
returns void language plpgsql security invoker set search_path = '' as $$
declare email_address text; loc bigint;
begin
  perform pg_advisory_xact_lock(814716290);
  if exists(select 1 from public.profiles where roles::text='Owner' and id<>target) then raise exception 'An owner already exists. Use the existing owner account or an audited administrator recovery process.'; end if;
  select email into email_address from auth.users where id=target;
  if email_address is null then raise exception 'Auth account not found'; end if;
  if exists(select 1 from unnest(target_locations) l where not exists(select 1 from public."Locations" where id=l)) then raise exception 'Unknown location ID'; end if;
  insert into public.profiles(id,email,roles) values(target,email_address,'Owner') on conflict(id) do update set roles='Owner';
  foreach loc in array coalesce(target_locations,'{}') loop
    insert into public."Location_to_Admin"(user_id,location_id) select target,loc where not exists(select 1 from public."Location_to_Admin" where user_id=target and location_id=loc);
  end loop;
end; $$;
revoke all on function public.admin_portal_bootstrap_owner(uuid,bigint[]) from public, anon, authenticated;
grant execute on function public.admin_portal_bootstrap_owner(uuid,bigint[]) to service_role;

-- Restrictive policies also constrain older clients/endpoints that still use
-- broad admin SELECT policies. Customer access to their own records remains.
create schema if not exists private;
grant usage on schema private to authenticated;
create function private.portal_record_access(kind text, record jsonb)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := auth.uid(); viewer_role text; loc bigint; payment jsonb;
begin
  if viewer is null then return false; end if;
  if record->>'user_id'=viewer::text then return true; end if;
  select roles::text into viewer_role from public.profiles where id=viewer;
  if viewer_role is null or viewer_role not in ('Owner','Admin') then return false; end if;
  if kind='maintenance' then
    loc := coalesce((record->>'location_id')::bigint,(select min(id) from public."Locations" where "Address"=record->>'location' having count(*)=1));
  elsif kind='credit' then
    select to_jsonb(t) into payment from public.transactions t where t.id::text=record->>'transaction_id';
    loc := public.portal_transaction_location(payment);
  elsif kind='transaction' then loc := public.portal_transaction_location(record);
  else return false;
  end if;
  return (loc is null and viewer_role='Owner') or exists(select 1 from public."Location_to_Admin" where user_id=viewer and location_id=loc);
end; $$;
revoke all on function private.portal_record_access(text,jsonb) from public,anon;
grant execute on function private.portal_record_access(text,jsonb) to authenticated;
alter table public.transactions enable row level security;
alter table public."Maintenance" enable row level security;
alter table public."Refunds" enable row level security;
create policy portal_transaction_scope on public.transactions as restrictive for select to authenticated using(private.portal_record_access('transaction',to_jsonb(transactions)));
create policy portal_maintenance_scope on public."Maintenance" as restrictive for select to authenticated using(private.portal_record_access('maintenance',to_jsonb("Maintenance")));
create policy portal_credit_scope on public."Refunds" as restrictive for select to authenticated using(private.portal_record_access('credit',to_jsonb("Refunds")));

-- Apply the same authorization inside the existing atomic credit transaction.
-- A rejection here rolls back any ledger entry made earlier in that transaction.
create function public.guard_portal_credit_resolution() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.status is distinct from old.status and new.status::text in ('approved','denied') then
    if current_user in ('anon','authenticated') or new.resolved_by is null then raise exception 'Use the authorized credit resolution service' using errcode='42501'; end if;
    perform public.admin_portal_data(new.resolved_by,'assertCredit',jsonb_build_object('id',new.refund_id));
  end if;
  return new;
end; $$;
create trigger portal_credit_resolution_scope before update on public."Refunds" for each row execute function public.guard_portal_credit_resolution();
revoke all on function public.guard_portal_credit_resolution() from public,anon,authenticated;
grant execute on function public.guard_portal_credit_resolution() to service_role;



-- SOURCE: supabase/migrations/20260928151021_admin_operations_extensions.sql

alter table public."Maintenance"
  add column priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  add column assigned_to uuid references auth.users(id) on delete set null,
  add column due_date date;
alter table public.admin_maintenance_history add column changes jsonb not null default '{}';
create index portal_maintenance_assignment_idx on public."Maintenance"(assigned_to, status, due_date);
create index portal_maintenance_location_idx on public."Maintenance"(location_id, created_at desc);

-- Availability is independent of device status and payment configuration.
alter table public."Machines"
  add column is_out_of_service boolean not null default false,
  add column service_reason text,
  add column service_updated_at timestamptz not null default now(),
  add column service_updated_by uuid;

create table public.admin_audit_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default clock_timestamp(),
  actor_id uuid,
  actor_name text not null,
  entity text not null,
  entity_id text not null,
  operation text not null,
  location_ids bigint[] not null default '{}',
  before_values jsonb,
  after_values jsonb
);
create index admin_audit_date_idx on public.admin_audit_events(created_at desc, id desc);
create index admin_audit_locations_idx on public.admin_audit_events using gin(location_ids);
alter table public.admin_audit_events enable row level security;
revoke all on public.admin_audit_events from public, anon, authenticated, service_role;
grant select, insert on public.admin_audit_events to service_role;
grant usage, select on sequence public.admin_audit_events_id_seq to service_role;

create function private.portal_audit_immutable() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  -- Auth deletion may clear the optional actor reference. Keep the immutable
  -- name snapshot and every business field while allowing that FK cleanup.
  if tg_table_name='admin_maintenance_history' and tg_op='UPDATE'
    and old.actor_id is not null and new.actor_id is null
    and (to_jsonb(old)-'actor_id')=(to_jsonb(new)-'actor_id')
    and not exists(select 1 from auth.users where id=old.actor_id) then return new; end if;
  raise exception 'Audit history cannot be edited or deleted';
end; $$;
create trigger portal_audit_immutable before update or delete on public.admin_audit_events
  for each row execute function private.portal_audit_immutable();
create trigger portal_maintenance_history_immutable before update or delete on public.admin_maintenance_history
  for each row execute function private.portal_audit_immutable();
revoke update,delete,truncate on public.admin_maintenance_history from service_role;

-- Older customer clients keep submitting the same report shape. Management
-- fields always start with server defaults, even if a browser supplies them.
create function private.portal_new_report() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if current_user in ('anon','authenticated') then
    new.status:='open'; new.priority:='normal'; new.assigned_to:=null; new.due_date:=null;
    new.updated_at:=now();
  end if;
  return new;
end; $$;
create trigger portal_new_report before insert on public."Maintenance"
  for each row execute function private.portal_new_report();
revoke all on function private.portal_new_report() from public,anon,authenticated;

-- Snapshots deliberately omit access tokens, credentials, balances, and raw
-- payment-provider payloads. Actor context can only accompany server writes.
create function private.portal_capture_audit() returns trigger
language plpgsql security invoker set search_path='' as $$
declare
  prior jsonb; next_value jsonb; subject jsonb; keys text[];
  event_entity text; event_id text; places bigint[] := '{}';
  who uuid := nullif(current_setting('cleanstream.portal_actor',true),'')::uuid;
  who_name text;
begin
  prior := case when tg_op='INSERT' then null else to_jsonb(old) end;
  next_value := case when tg_op='DELETE' then null else to_jsonb(new) end;
  subject := coalesce(next_value,prior);
  case tg_table_name
    when 'Machines' then
      event_entity := 'machine'; event_id := subject->>'id';
      places := array[(subject->>'Location_ID')::bigint];
      keys := array['Name','Location_ID','Machine_type','Weight_kg','Price','Runtime','washer_size_rate_id','is_out_of_service','service_reason'];
    when 'Locations' then
      event_entity := 'location'; event_id := subject->>'id'; places := array[event_id::bigint];
      keys := array['Name','Address','Latitude','Longitude'];
    when 'washer_size_rates' then
      event_entity := 'washer_rate'; event_id := subject->>'id'; places := array[(subject->>'location_id')::bigint];
      keys := array['size_label','capacity_kg','price_cents','is_active','review_required'];
    when 'cortina_machine_config' then
      event_entity := 'payment_config'; event_id := subject->>'machine_id';
      select array["Location_ID"] into places from public."Machines" where id=event_id::bigint;
      keys := array['nayax_terminal_id','nayax_uniqr','pulse_line_number','product_codes','environment','is_enabled','review_required'];
    when 'Location_to_Admin' then
      event_entity := 'membership'; event_id := (subject->>'user_id')||':'||(subject->>'location_id');
      places := array[(subject->>'location_id')::bigint]; keys := array['user_id','location_id'];
    when 'admin_invitations' then
      event_entity := 'invitation'; event_id := (subject->>'user_id')||':'||(subject->>'location_id');
      places := array[(subject->>'location_id')::bigint];
      keys := array['user_id','location_id','delivery_status','last_sent_at'];
    when 'Maintenance' then
      event_entity := 'maintenance'; event_id := subject->>'maint_id';
      select array[coalesce((subject->>'location_id')::bigint,
        (select min(id) from public."Locations" where "Address"=subject->>'location' having count(*)=1))] into places;
      keys := array['status','priority','assigned_to','due_date','location_id'];
    when 'Refunds' then
      event_entity := 'loyalty_credit'; event_id := subject->>'refund_id';
      who := coalesce(who,(subject->>'resolved_by')::uuid);
      select array[public.portal_transaction_location(to_jsonb(t))] into places
        from public.transactions t where t.id::text=subject->>'transaction_id';
      keys := array['status','amount','admin_note','resolved_at','notification_sent_at'];
    when 'profiles' then
      if prior->'roles' is not distinct from next_value->'roles' then return null; end if;
      event_entity := 'role'; event_id := subject->>'id'; keys := array['roles'];
      select array_agg(location_id::bigint) into places from public."Location_to_Admin" where user_id=event_id::uuid;
    else return null;
  end case;
  if prior is not null then
    select coalesce(jsonb_object_agg(key,value),'{}') into prior from jsonb_each(prior) where key=any(keys);
  end if;
  if next_value is not null then
    select coalesce(jsonb_object_agg(key,value),'{}') into next_value from jsonb_each(next_value) where key=any(keys);
  end if;
  if prior is not distinct from next_value then return null; end if;
  select coalesce(nullif(full_name,''),email) into who_name from public.profiles where id=who;
  insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,before_values,after_values)
    values(who,coalesce(who_name,'System / trusted operator'),event_entity,event_id,lower(tg_op),
      coalesce(array_remove(places,null),'{}'),prior,next_value);
  return null;
end; $$;

create trigger portal_audit_machine after insert or update or delete on public."Machines" for each row execute function private.portal_capture_audit();
create trigger portal_audit_location after insert or update or delete on public."Locations" for each row execute function private.portal_capture_audit();
create trigger portal_audit_rate after insert or update or delete on public.washer_size_rates for each row execute function private.portal_capture_audit();
create trigger portal_audit_config after insert or update or delete on public.cortina_machine_config for each row execute function private.portal_capture_audit();
create trigger portal_audit_membership after insert or update or delete on public."Location_to_Admin" for each row execute function private.portal_capture_audit();
create trigger portal_audit_invitation after insert or update or delete on public.admin_invitations for each row execute function private.portal_capture_audit();
create trigger portal_audit_maintenance after update on public."Maintenance" for each row execute function private.portal_capture_audit();
create trigger portal_audit_credit after update on public."Refunds" for each row execute function private.portal_capture_audit();
create trigger portal_audit_role after update on public.profiles for each row execute function private.portal_capture_audit();
revoke all on function private.portal_capture_audit(), private.portal_audit_immutable() from public, anon, authenticated;
grant execute on function private.portal_capture_audit() to service_role;

-- Serialize new session creation against an availability change. Updates to
-- existing sessions remain available for callbacks and compensation.
create function private.portal_guard_new_vend() returns trigger
language plpgsql security invoker set search_path='' as $$
declare unavailable boolean;
begin
  select is_out_of_service into unavailable from public."Machines" where id=new.machine_id for share;
  if not found or unavailable then
    raise exception 'This machine is out of service. Choose another machine.' using errcode='55000';
  end if;
  return new;
end; $$;
create trigger portal_guard_new_vend before insert on public.cortina_vend_sessions
  for each row execute function private.portal_guard_new_vend();
revoke all on function private.portal_guard_new_vend() from public, anon, authenticated;
grant execute on function private.portal_guard_new_vend() to service_role;

-- A single scoped record source powers both queues and exports. Provider
-- secrets and raw event payloads are never included in these records.
create function public.admin_portal_rows(actor uuid, dataset text)
returns setof jsonb language plpgsql security invoker set search_path='' as $$
declare actor_role text; ids bigint[];
begin
  select roles::text into actor_role from public.profiles where id=actor;
  if actor_role is null or actor_role not in ('Owner','Admin') then
    raise exception 'Owner or Admin access required' using errcode='42501';
  end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id=actor;
  if dataset in ('audit','team') and actor_role<>'Owner' then
    raise exception 'Owner access required' using errcode='42501';
  end if;

  if dataset='transactions' then
    return query
    -- Scan optional legacy links once, rather than rescanning the entire
    -- ledger for every payment attempt. Older schemas may lack this column.
    with ledger as materialized (
      select to_jsonb(t)->>'cortina_vend_session_id' session_id,min(t.id)::text id
      from public.transactions t
      where to_jsonb(t)->>'cortina_vend_session_id' is not null
      group by to_jsonb(t)->>'cortina_vend_session_id'
    )
    select jsonb_build_object(
      'id','vend:'||s.id,'date',s.created_at,'source','machine_payment',
      'customer_name',coalesce(nullif(p.full_name,''),case when s.user_id is null then 'Guest' else 'Customer' end),
      'customer_email',p.email,'location_id',m."Location_ID",'location_name',l."Name",
      'machine_id',m.id,'machine_name',m."Name",'amount',s.amount_cents::numeric/100,'currency',s.currency,
      'payment_method',s.payment_method,'channel',s.channel,'status',s.status,
      'payment_status',case when s.status='refunded' then 'refunded' when s.status='voided' then 'voided'
        when s.status='payment_pending' then 'pending'
        when s.status in ('paid','starting','awaiting_sale','approved','started') then 'received' else 'unconfirmed' end,
      'reference',s.transaction_id,'payment_reference',s.stripe_payment_intent_id,
      'checkout_reference',s.stripe_checkout_session_id,'refund_reference',s.stripe_refund_id,
      'ledger_id',ledger.id,'failure_message',s.failure_message,'completed_at',s.completed_at,
      'description',case when m."Machine_type"::text='Dryer' then 'Dryer payment' else 'Washer payment' end)
    from public.cortina_vend_sessions s
    join public."Machines" m on m.id=s.machine_id
    join public."Locations" l on l.id=m."Location_ID"
    left join public.profiles p on p.id=s.user_id
    left join ledger on ledger.session_id=s.id::text
    where m."Location_ID"=any(ids)
    union all
    select jsonb_build_object(
      'id','legacy:'||t.id,'date',t.created_at,'source','legacy',
      'customer_name',coalesce(nullif(p.full_name,''),'Customer'),'customer_email',p.email,
      'location_id',null,'location_name',null,'machine_id',null,'machine_name',null,
      'amount',t.amount,'currency','USD','payment_method','unattributed','channel',null,
      'status','recorded','payment_status','recorded','reference',t.id::text,
      'payment_reference',null,'checkout_reference',null,'refund_reference',null,
      'ledger_id',t.id::text,'failure_message',null,'completed_at',null,'description',t.description)
    from public.transactions t left join public.profiles p on p.id=t.user_id
    where actor_role='Owner' and not exists(select 1 from public.cortina_vend_sessions s
      where s.id::text=to_jsonb(t)->>'cortina_vend_session_id');

  elsif dataset='maintenance' then
    return query
    select to_jsonb(m)||jsonb_build_object('id',m.maint_id::text,'maint_id',m.maint_id::text,
      'date',m.created_at,'location_id',mapping.location_id,'assigned_name',coalesce(nullif(p.full_name,''),p.email),
      'overdue',m.status<>'resolved' and m.due_date<(now() at time zone 'America/Indiana/Indianapolis')::date)
    from public."Maintenance" m
    left join public.profiles p on p.id=m.assigned_to
    cross join lateral (select coalesce(m.location_id,(select min(id) from public."Locations"
      where "Address"=m.location having count(*)=1)) location_id) mapping
    where mapping.location_id=any(ids) or (mapping.location_id is null and actor_role='Owner');

  elsif dataset='credits' then
    return query
    select jsonb_build_object('id',r.refund_id::text,'refund_id',r.refund_id,'amount',r.amount,
      'description',r.description,'date',r.date,'status',r.status,'customer_name',coalesce(p.full_name,'Customer'),
      'transaction_id',r.transaction_id,'admin_note',r.admin_note,'resolved_at',r.resolved_at,
      'notification_sent_at',r.notification_sent_at,'location_id',mapping.location_id)
    from public."Refunds" r join public.transactions t on t.id=r.transaction_id
    left join public.profiles p on p.id=r.user_id
    cross join lateral (select public.portal_transaction_location(to_jsonb(t)) location_id) mapping
    where mapping.location_id=any(ids) or (mapping.location_id is null and actor_role='Owner');

  elsif dataset='audit' then
    return query select to_jsonb(a)||jsonb_build_object('id',a.id::text,'date',a.created_at)
    from public.admin_audit_events a where a.location_ids && ids
      or (cardinality(a.location_ids)=0 and (a.actor_id=actor or (a.entity='role' and a.entity_id=actor::text) or a.entity in ('maintenance','loyalty_credit')));

  elsif dataset='team' then
    return query select jsonb_build_object('id',p.id||':'||l.id,'user_id',p.id,'name',p.full_name,
      'email',u.email,'role',p.roles,'location_id',l.id,'location_name',l."Name",
      'assignment_count',(select count(*) from public."Location_to_Admin" all_assignments where all_assignments.user_id=p.id),
      'invitation_status',case when u.last_sign_in_at is not null then 'active' when i.delivery_status='failed' then 'failed'
        when i.last_sent_at is not null then 'invited' else 'pending' end,'invited_at',i.invited_at,'date',i.invited_at)
    from public."Location_to_Admin" a join public.profiles p on p.id=a.user_id join auth.users u on u.id=p.id
    join public."Locations" l on l.id=a.location_id left join public.admin_invitations i on i.user_id=a.user_id and i.location_id=a.location_id
    where a.location_id=any(ids);

  elsif dataset='machines' then
    return query select jsonb_build_object('id',m.id::text,'name',m."Name",'location_id',m."Location_ID",'location_name',l."Name",
      'machine_type',m."Machine_type",'status',m."Status",'capacity_kg',m."Weight_kg",'price',coalesce(r.price_cents::numeric/100,m."Price"),
      'is_out_of_service',m.is_out_of_service,'service_reason',m.service_reason,'service_updated_at',m.service_updated_at,
      'payment_enabled',coalesce(c.is_enabled,false),'payment_review_required',coalesce(c.review_required,true),'environment',c.environment)
    from public."Machines" m join public."Locations" l on l.id=m."Location_ID"
    left join public.washer_size_rates r on r.id=m.washer_size_rate_id
    left join public.cortina_machine_config c on c.machine_id=m.id where m."Location_ID"=any(ids);
  else raise exception 'Unknown export dataset';
  end if;
end; $$;
revoke all on function public.admin_portal_rows(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_portal_rows(uuid,text) to service_role;

create function public.admin_portal_records(actor uuid, dataset text, filters jsonb, exporting boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare f jsonb:=coalesce(filters,'{}'); result jsonb; desired_status text;
  page_number integer:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
begin
  if nullif(f->>'from','') is not null and nullif(f->>'to','') is not null and (f->>'from')::date>(f->>'to')::date then
    raise exception 'Start date must be before the end date';
  end if;
  desired_status:=coalesce(nullif(f->>'status',''),case dataset when 'maintenance' then 'unresolved' when 'credits' then 'pending' else 'all' end);
  with filtered as materialized (
    select value from public.admin_portal_rows(actor,dataset) value
    where (coalesce(f->>'search','')='' or position(lower(f->>'search') in lower(
      case when dataset='machines' then value->>'name' else (value-'image_data')::text end))>0)
      and (desired_status='all' or (dataset='maintenance' and desired_status='unresolved' and value->>'status'<>'resolved') or value->>'status'=desired_status)
      and (nullif(f->>'locationId','') is null or value->>'location_id'=f->>'locationId'
        or (dataset='audit' and value->'location_ids' @> jsonb_build_array((f->>'locationId')::bigint)))
      and (nullif(f->>'from','') is null or (value->>'date')::timestamptz >= (f->>'from')::date::timestamp at time zone 'America/Indiana/Indianapolis')
      and (nullif(f->>'to','') is null or (value->>'date')::timestamptz < ((f->>'to')::date+1)::timestamp at time zone 'America/Indiana/Indianapolis')
      and (coalesce(f->>'category','')='' or value->>'category'=f->>'category')
      and (coalesce(f->>'priority','')='' or value->>'priority'=f->>'priority')
      and (coalesce(f->>'entity','')='' or value->>'entity'=f->>'entity')
      and (coalesce(f->>'paymentStatus','')='' or value->>'payment_status'=f->>'paymentStatus')
      and (coalesce(f->>'machineType','')='' or value->>'machine_type'=f->>'machineType')
      and (coalesce(f->>'availability','')='' or (value->>'is_out_of_service')::boolean=(f->>'availability'='out_of_service'))
      and (not coalesce((f->>'overdue')::boolean,false) or coalesce((value->>'overdue')::boolean,false))
      and (coalesce(f->>'assignedTo','')='' or (f->>'assignedTo'='unassigned' and value->>'assigned_to' is null)
        or value->>'assigned_to'=case when f->>'assignedTo'='me' then actor::text else f->>'assignedTo' end)
  ), page as (
    select value from filtered order by (value->>'date')::timestamptz desc nulls last,value->>'id' desc
    limit case when exporting then 5001 else 20 end offset case when exporting then 0 else (page_number-1)*20 end
  )
  select jsonb_build_object('items',(select coalesce(jsonb_agg(value),'[]') from page),
    'total',(select count(*) from filtered),'page',page_number,'pageSize',20,'exportedAt',now()) into result;
  if exporting and (result->>'total')::int>5000 then
    raise exception 'More than 5,000 records match. Narrow your date range or filters before exporting.';
  end if;
  return result;
end; $$;
revoke all on function public.admin_portal_records(uuid,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.admin_portal_records(uuid,text,jsonb,boolean) to service_role;

alter function public.admin_portal_data(uuid,text,jsonb) rename to admin_portal_data_v1;
create function public.admin_portal_data(actor uuid, action text, payload jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  actor_role text; actor_name text; ids bigint[]; loc bigint; target uuid;
  report public."Maintenance"%rowtype; machine public."Machines"%rowtype;
  next_status text; next_priority text; next_assignee uuid; next_due date; note text;
  before_details jsonb; after_details jsonb; new_unavailable boolean; result jsonb;
begin
  select roles::text,coalesce(nullif(full_name,''),email,'Team member') into actor_role,actor_name
    from public.profiles where id=actor;
  if actor_role is null or actor_role not in ('Owner','Admin') then
    raise exception 'Owner or Admin access required' using errcode='42501';
  end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id=actor;
  perform set_config('cleanstream.portal_actor',actor::text,true);

  if action in ('transactions','audit','maintenance','credits','team') then
    return public.admin_portal_records(actor,action,payload->'filters');
  elsif action='exportRecords' then
    if coalesce(payload->>'dataset','') not in ('transactions','audit','maintenance','credits','team','machines') then
      raise exception 'Unknown export dataset';
    end if;
    result:=public.admin_portal_records(actor,payload->>'dataset',payload->'filters',true);
    return jsonb_build_object('rows',result->'items','total',result->'total','exportedAt',result->'exportedAt');
  elsif action in ('assignees','updateMaintenance') then
    -- The original permission check and row lock also protect legacy address mappings.
    perform public.admin_portal_data_v1(actor,'history',payload);
    select * into report from public."Maintenance" where maint_id::text=payload->>'id' for update;
    loc:=coalesce(report.location_id,(select min(id) from public."Locations" where "Address"=report.location having count(*)=1));
    if action='assignees' then
      return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.full_name,''),p.email),'email',p.email) order by p.full_name),'[]')
        from public.profiles p where p.roles::text in ('Owner','Admin')
          and ((loc is null and p.id=actor and p.roles::text='Owner')
            or exists(select 1 from public."Location_to_Admin" where user_id=p.id and location_id=loc)));
    end if;
    next_status:=payload->>'status'; note:=nullif(btrim(payload->>'note'),'');
    next_priority:=coalesce(payload->>'priority',report.priority);
    next_assignee:=case when payload ? 'assignedTo' then nullif(payload->>'assignedTo','')::uuid else report.assigned_to end;
    next_due:=case when payload ? 'dueDate' then nullif(payload->>'dueDate','')::date else report.due_date end;
    if next_status is null or next_status not in ('open','in_progress','resolved')
      or next_priority not in ('low','normal','high','urgent') or length(coalesce(note,''))>4000 then
      raise exception 'Invalid maintenance update';
    end if;
    if next_assignee is not null and not exists(select 1 from public.profiles p
      where p.id=next_assignee and p.roles::text in ('Owner','Admin')
        and ((loc is null and p.id=actor and p.roles::text='Owner') or exists(
          select 1 from public."Location_to_Admin" where user_id=p.id and location_id=loc))) then
      raise exception 'Assign this report to a team member with access to its location';
    end if;
    if (payload->>'expectedUpdatedAt')::timestamptz is distinct from report.updated_at then
      raise exception 'This report changed. Close it, refresh the list, and try again.';
    end if;
    if next_status=report.status and next_priority=report.priority and next_assignee is not distinct from report.assigned_to
      and next_due is not distinct from report.due_date and note is null then raise exception 'Choose a change or add a note'; end if;
    before_details:=jsonb_build_object('priority',report.priority,'assignee',coalesce((select coalesce(nullif(full_name,''),email) from public.profiles where id=report.assigned_to),'Unassigned'),'due_date',report.due_date);
    after_details:=jsonb_build_object('priority',next_priority,'assignee',coalesce((select coalesce(nullif(full_name,''),email) from public.profiles where id=next_assignee),'Unassigned'),'due_date',next_due);
    update public."Maintenance" set status=next_status,priority=next_priority,assigned_to=next_assignee,due_date=next_due,
      updated_at=clock_timestamp(),location_id=loc where maint_id=report.maint_id;
    insert into public.admin_maintenance_history(maintenance_id,actor_id,actor_name,from_status,to_status,note,changes)
      values(report.maint_id::text,actor,actor_name,report.status,next_status,note,jsonb_build_object('before',before_details,'after',after_details));
    return '{"success":true}';

  elsif action='setAvailability' then
    if actor_role<>'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
    select * into machine from public."Machines" where id=(payload->>'id')::bigint for update;
    if not found or not(machine."Location_ID"=any(ids)) then raise exception 'Machine access denied' using errcode='42501'; end if;
    if jsonb_typeof(payload->'outOfService') is distinct from 'boolean' then raise exception 'Choose a valid availability'; end if;
    new_unavailable:=(payload->>'outOfService')::boolean; note:=nullif(btrim(payload->>'reason'),'');
    if new_unavailable and note is null then raise exception 'Enter the reason this machine is out of service'; end if;
    if length(coalesce(note,''))>1000 then raise exception 'Keep the reason under 1,000 characters'; end if;
    if (payload->>'expectedUpdatedAt')::timestamptz is distinct from machine.service_updated_at then
      raise exception 'Machine availability changed. Refresh and try again.';
    end if;
    if new_unavailable=machine.is_out_of_service then raise exception 'This availability is already set'; end if;
    update public."Machines" set is_out_of_service=new_unavailable,service_reason=note,
      service_updated_at=clock_timestamp(),service_updated_by=actor where id=machine.id;
    return '{"success":true}';

  elsif action='recordDelivery' then
    -- Internal action used by the invitation service, excluded from the HTTP allowlist.
    if actor_role<>'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
    target:=(payload->>'userId')::uuid;
    for loc in select value::bigint from jsonb_array_elements_text(payload->'locationIds') loop
      perform public.admin_portal_data_v1(actor,'assertMember',jsonb_build_object('userId',target,'locationId',loc));
      update public.admin_invitations set delivery_status=case when (payload->>'sent')::boolean then 'sent' else 'failed' end,
        last_sent_at=case when (payload->>'sent')::boolean then now() else last_sent_at end
        where user_id=target and location_id=loc;
    end loop;
    return '{"success":true}';
  end if;
  return public.admin_portal_data_v1(actor,action,payload);
end; $$;
revoke all on function public.admin_portal_data(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_portal_data(uuid,text,jsonb) to service_role;
grant usage on schema private to service_role;



-- SOURCE: supabase/migrations/20260930131557_admin_collection_reporting.sql

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



-- SOURCE: supabase/migrations/20260930142406_admin_canonical_authorization.sql

do $$ begin
  if to_regprocedure('private.current_account_access()') is null
    or to_regprocedure('public.admin_portal_data(uuid,text,jsonb)') is null
    or to_regprocedure('public.resolve_refund_request(bigint,text,text,uuid)') is null then
    raise exception 'Canonical admission and reviewed admin/credit prerequisites required';
  end if;
end $$;

-- VOLATILE deliberately obtains a fresh statement snapshot on the post-wait
-- call. The canonical evaluator remains the only session/MFA/lifecycle policy.
create function private.portal_staff_context()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare a jsonb; actor uuid; staff_role text; locations jsonb;
begin
  a:=private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then
    if a->>'account_state'='pending_deletion' or a->>'reason' is not null then
      raise exception 'account_restricted' using errcode='PT403';
    end if;
    case a->>'next_step'
      when 'verify_email' then raise exception 'verify_email' using errcode='PT403';
      when 'enroll_totp' then raise exception 'enroll_totp' using errcode='PT403';
      when 'challenge_totp' then raise exception 'challenge_totp' using errcode='PT403';
      else raise exception 'account_restricted' using errcode='PT403';
    end case;
  end if;
  actor:=(a->>'subject_id')::uuid;
  select roles::text into staff_role from public.profiles where id=actor;
  if staff_role is null or staff_role not in ('Owner','Admin') then
    raise exception 'staff_required' using errcode='PT403';
  end if;
  select coalesce(jsonb_agg(location_id order by location_id),'[]') into locations
    from (select distinct location_id from public."Location_to_Admin" where user_id=actor) assigned;
  return jsonb_build_object('actor',actor,'role',staff_role,'locations',locations);
end; $$;
revoke all on function private.portal_staff_context() from public,anon,authenticated,service_role;

create function public.admin_portal_request(action text, payload jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare before_context jsonb; after_context jsonb; result jsonb;
begin
  before_context:=private.portal_staff_context();
  if action in ('invite','resend','assignMember','recordDelivery','assertMember') then
    raise exception 'admin_onboarding_disabled' using errcode='PT503';
  end if;
  if action is null or action not in ('identity','locations','machines','rates','maintenance','history',
    'updateMaintenance','credits','team','overview','createLocation','createMachine','deleteMachine',
    'saveRate','saveConfig','removeMember','transactions','audit','assignees','setAvailability','exportRecords','assertCredit') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  result:=public.admin_portal_data((before_context->>'actor')::uuid,action,payload);
  after_context:=private.portal_staff_context();
  if action='createLocation' then
    -- Creating a location deliberately adds exactly its creator's membership.
    if after_context->>'actor' is distinct from before_context->>'actor'
      or after_context->>'role' is distinct from before_context->>'role'
      or not ((after_context->'locations') @> (before_context->'locations'))
      or not ((after_context->'locations') <@ ((before_context->'locations')||jsonb_build_array((result->>'id')::bigint))) then
      raise exception 'admin_access_changed' using errcode='PT403';
    end if;
  elsif after_context is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  return result;
end; $$;
revoke all on function public.admin_portal_request(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_portal_request(text,jsonb) to authenticated;

create function public.admin_resolve_credit(target_refund_id bigint, target_decision text, resolution_note text default '')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare before_context jsonb; result jsonb; actor uuid;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if length(coalesce(resolution_note,''))>4000 then raise exception 'invalid_request' using errcode='22023'; end if;
  perform public.admin_portal_data(actor,'assertCredit',jsonb_build_object('id',target_refund_id));
  result:=public.resolve_refund_request(target_refund_id,target_decision,resolution_note,actor);
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  -- The claim's machine may have changed location during an inner wallet wait.
  perform public.admin_portal_data(actor,'assertCredit',jsonb_build_object('id',target_refund_id));
  return result;
end; $$;
revoke all on function public.admin_resolve_credit(bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_resolve_credit(bigint,text,text) to authenticated;

-- Actor-taking implementations are internal, not alternate HTTP/RPC APIs.
-- Keep their bodies intact, including the reporting author's current wrapper.
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (p.proname in ('admin_portal_data','admin_portal_data_v1',
      'admin_portal_data_before_reporting','admin_portal_rows','admin_portal_rows_before_reporting',
      'admin_portal_records','admin_portal_topup_evidence','admin_portal_assign_member',
      'admin_portal_bootstrap_owner','resolve_refund_request'))
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f);
    if has_function_privilege('anon',f,'execute') or has_function_privilege('authenticated',f,'execute')
      or has_function_privilege('service_role',f,'execute') then
      raise exception 'Unexpected inherited inner-helper privileges: %',f;
    end if;
  end loop;
end $$;

-- These legacy global-wallet RPCs have no location authorization contract.
-- Fail closed rather than inventing location ownership or rewriting finance.
revoke all on function public.admin_adjust_wallet(uuid,integer,integer,integer,text) from public,anon,authenticated,service_role;
revoke all on function public.admin_record_legal_cash_redemption(uuid,integer,text,text) from public,anon,authenticated,service_role;
revoke all on function public.admin_set_wallet_status(uuid,text,text) from public,anon,authenticated,service_role;

-- The legacy role predicate also participates in direct table policies and
-- privileged wallet RPCs. Replace its role-only check, not financial logic.
create or replace function public.is_admin_or_owner()
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  return private.current_account_access()->>'account_access'='eligible'
    and exists(select 1 from public.profiles where id=auth.uid() and roles::text in ('Owner','Admin'));
exception when sqlstate 'PT401' then return false;
end; $$;

alter function private.portal_record_access(text,jsonb) rename to portal_record_access_before_authorization;
create function private.portal_record_access(kind text, record jsonb)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if exists(select 1 from public.profiles where id=auth.uid() and roles::text in ('Owner','Admin'))
    and not public.is_admin_or_owner() then return false; end if;
  return private.portal_record_access_before_authorization(kind,record);
end; $$;
revoke all on function private.portal_record_access_before_authorization(text,jsonb) from public,anon,authenticated,service_role;
revoke all on function private.portal_record_access(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.portal_record_access(text,jsonb) to authenticated;
-- Policies reference function OIDs, so rebind after renaming the old body.
alter policy portal_transaction_scope on public.transactions using(private.portal_record_access('transaction',to_jsonb(transactions)));
alter policy portal_maintenance_scope on public."Maintenance" using(private.portal_record_access('maintenance',to_jsonb("Maintenance")));
alter policy portal_credit_scope on public."Refunds" using(private.portal_record_access('credit',to_jsonb("Refunds")));

-- Cross-customer staff data goes through the scoped portal, not broad legacy
-- profile/wallet SELECT policies. Customer self-reads retain their other gates.
create policy portal_profile_direct_self on public.profiles as restrictive for select to authenticated using(id=auth.uid());
create policy portal_wallet_direct_self on public.wallet_accounts as restrictive for select to authenticated using(user_id=auth.uid());
create policy portal_load_direct_self on public.wallet_loads as restrictive for select to authenticated using(user_id=auth.uid());
create policy portal_ledger_direct_self on public.wallet_ledger_entries as restrictive for select to authenticated
  using(exists(select 1 from public.wallet_accounts w where w.id=wallet_account_id and w.user_id=auth.uid()));
create policy portal_redemption_direct_self on public.wallet_redemptions as restrictive for select to authenticated using(user_id=auth.uid());
create policy portal_deleted_complaint_no_direct_staff on public.deleted_account_complaints as restrictive for select to authenticated using(false);
create policy portal_config_admission on public.cortina_machine_config as restrictive for select to authenticated using(public.is_admin_or_owner());
create policy portal_rate_admission on public.washer_size_rates as restrictive for select to authenticated using(public.is_admin_or_owner());
create policy portal_membership_direct_self on public."Location_to_Admin" as restrictive for select to authenticated
  using(user_id=auth.uid() and public.is_admin_or_owner());

-- Table-level revokes do not remove legacy column grants.
do $$ declare tbl text; cols text; begin
  foreach tbl in array array['Machines','Locations','washer_size_rates','cortina_machine_config'] loop
    execute format('revoke insert,update,delete on public.%I from public,anon,authenticated',tbl);
    select string_agg(quote_ident(attname),',') into cols from pg_attribute
      where attrelid=format('public.%I',tbl)::regclass and attnum>0 and not attisdropped;
    execute format('revoke insert (%s),update (%s) on public.%I from public,anon,authenticated',cols,cols,tbl);
  end loop;
  foreach tbl in array array['Maintenance','Refunds'] loop
    execute format('revoke update,delete on public.%I from public,anon,authenticated',tbl);
    select string_agg(quote_ident(attname),',') into cols from pg_attribute
      where attrelid=format('public.%I',tbl)::regclass and attnum>0 and not attisdropped;
    execute format('revoke update (%s) on public.%I from public,anon,authenticated',cols,tbl);
  end loop;
end $$;



-- SOURCE: supabase/migrations/20260930032327_maintenance_authorization.sql
-- LOCAL ONLY: coordinated readers, trusted roles/memberships, approved admission
-- foundations and separate Storage/admin reconciliation are release gates.

do $$
declare
  location_column smallint;
begin
  if current_user <> 'postgres' or not exists (
    select 1 from pg_catalog.pg_class where oid = 'public."Maintenance"'::regclass
      and relkind = 'r' and relrowsecurity and not relforcerowsecurity
      and pg_get_userbyid(relowner) = 'postgres'
  ) or to_regprocedure('private.account_access_allowed()') is null
    or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public.profiles'::regclass
        and tgname = 'profiles_protected_fields_guard' and tgenabled in ('O','A')
        and tgfoid = to_regprocedure('public.guard_profile_protected_fields()'))
    or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public."Location_to_Admin"'::regclass
        and tgname = 'location_membership_writes_guard' and tgenabled = 'A'
        and tgfoid = to_regprocedure('public.guard_location_membership_writes()')) then
    raise exception 'Reviewed maintenance authority prerequisites required' using errcode = '55000';
  end if;
  if exists (select 1 from pg_catalog.pg_roles
      where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls or rolcreaterole))
    or exists (select 1 from pg_catalog.pg_auth_members m
      join pg_catalog.pg_roles r on r.oid = m.member
      where r.rolname in ('anon','authenticated')) then
    raise exception 'Client authority or inheritance requires review' using errcode = '42501';
  end if;

  -- The unshipped portal may already declare this column, but never infer its
  -- correctness from IF NOT EXISTS, nor infer report attribution from an address.
  select attnum into location_column from pg_catalog.pg_attribute
    where attrelid = 'public."Maintenance"'::regclass and attname = 'location_id' and not attisdropped;
  if found then
    if not exists (select 1 from pg_catalog.pg_attribute
        where attrelid = 'public."Maintenance"'::regclass and attnum = location_column
          and atttypid = 'bigint'::regtype and not attnotnull and not atthasdef
          and attidentity = '' and attgenerated = '')
      or (select count(*) from pg_catalog.pg_constraint
        where conrelid = 'public."Maintenance"'::regclass and contype = 'f'
          and location_column = any(conkey)) <> 1
      or not exists (select 1 from pg_catalog.pg_constraint
        where conrelid = 'public."Maintenance"'::regclass and contype = 'f'
          and conkey = array[location_column] and confrelid = 'public."Locations"'::regclass
          and confkey = array[(select attnum from pg_catalog.pg_attribute
            where attrelid = 'public."Locations"'::regclass and attname = 'id')]
          and confupdtype = 'a' and confdeltype = 'a' and confmatchtype = 's'
          and convalidated and not condeferrable) then
      raise exception 'Existing maintenance location definition requires review' using errcode = '55000';
    end if;
  else
    alter table public."Maintenance" add column location_id bigint references public."Locations"(id);
  end if;
end;
$$;

alter table public."Maintenance" add column attachment_ref jsonb;

revoke insert, update, delete, truncate, references, trigger, maintain
  on public."Maintenance" from public, anon, authenticated restrict;
do $$
declare columns_list text;
begin
  select string_agg(format('%I',attname), ', ' order by attnum) into columns_list
    from pg_catalog.pg_attribute where attrelid = 'public."Maintenance"'::regclass
      and attnum > 0 and not attisdropped;
  execute format('revoke insert (%1$s), update (%1$s), references (%1$s) on public."Maintenance" from public, anon, authenticated restrict', columns_list);
  if exists (select 1 from (values ('anon'),('authenticated')) r(name)
      cross join (values ('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) p(privilege)
      where has_table_privilege(r.name,'public."Maintenance"',p.privilege))
    or exists (select 1 from (values ('anon'),('authenticated')) r(name)
      cross join (values ('INSERT'),('UPDATE'),('REFERENCES')) p(privilege)
      where has_any_column_privilege(r.name,'public."Maintenance"',p.privilege)) then
    raise exception 'Remaining effective maintenance writes require review' using errcode = '42501';
  end if;
end;
$$;

create function public.guard_maintenance_writes()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') then
    raise exception 'Maintenance writes require a trusted server writer' using errcode = '42501';
  end if;
  return null;
end;
$$;
create trigger maintenance_writes_guard
before insert or update or delete or truncate on public."Maintenance"
for each statement execute function public.guard_maintenance_writes();
alter table public."Maintenance" enable always trigger maintenance_writes_guard;
revoke all on function public.guard_maintenance_writes() from public, anon, authenticated, service_role;

create function private.maintenance_record_access(report_user_id uuid, report_location_id bigint)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid; caller_role public."Roles";
begin
  if not private.account_access_allowed() then return false; end if;
  caller_id := auth.uid();
  if report_user_id = caller_id then return true; end if;
  select roles into caller_role from public.profiles where id = caller_id;
  return coalesce((caller_role = 'Owner' and report_location_id is null)
    or (caller_role in ('Admin','Owner') and report_location_id is not null and exists (
      select 1 from public."Location_to_Admin" m
      where m.user_id = caller_id and m.location_id = report_location_id
    )), false);
exception
  when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;
revoke all on function private.maintenance_record_access(uuid,bigint) from public, anon, authenticated, service_role;
grant execute on function private.maintenance_record_access(uuid,bigint) to authenticated;
create policy maintenance_record_scope on public."Maintenance"
as restrictive for select to authenticated
using (private.maintenance_record_access(user_id,location_id));

create function public.submit_maintenance_request(p_request jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  caller_id uuid;
  report public."Maintenance"%rowtype;
  target_location bigint;
  attachment_name text;
  attachment jsonb;
  object_count bigint;
  field_name text;
  field_limit integer;
  field_value text;
  utf16_length integer;
begin
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller_id := auth.uid();
  perform 1 from auth.users where id = caller_id for share;
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  if jsonb_typeof(p_request) is distinct from 'object' then
    raise exception 'invalid_request' using errcode = 'PT400';
  end if;
  if p_request ? 'user_id' then
    if jsonb_typeof(p_request->'user_id') is distinct from 'string'
      or (p_request->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    if (p_request->>'user_id')::uuid <> caller_id then
      raise exception 'user_mismatch' using errcode = 'PT403';
    end if;
  end if;
  -- Match JavaScript string limits and trim whitespace without changing text.
  for field_name, field_limit in values ('category',64),('description',4000),('location',1000) loop
    field_value := p_request->>field_name;
    if jsonb_typeof(p_request->field_name) is distinct from 'string'
      or length(field_value) > field_limit
      or btrim(field_value, E' \t\n\r\f' || chr(11) || chr(160) || chr(5760) ||
        chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||
        chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279)) = '' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    select coalesce(sum(case when ascii(c) > 65535 then 2 else 1 end),0)
      into utf16_length from regexp_split_to_table(field_value,'') c;
    if utf16_length > field_limit then raise exception 'invalid_request' using errcode = 'PT400'; end if;
  end loop;
  if p_request->>'category' not in ('Other','Washer/Dryer Maintenance','App Maintenance','Location Maintenance')
    or coalesce(p_request->'image','null'::jsonb) <> 'null'::jsonb then
    raise exception 'invalid_request' using errcode = 'PT400';
  end if;
  if coalesce(p_request->'location_id','null'::jsonb) <> 'null'::jsonb then
    if jsonb_typeof(p_request->'location_id') <> 'string'
      or (p_request->>'location_id') !~ '^[1-9][0-9]{0,18}$' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    if (p_request->>'location_id')::numeric > 9223372036854775807 then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    target_location := (p_request->>'location_id')::bigint;
    if not exists (select 1 from public."Locations" where id = target_location) then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
  end if;
  if coalesce(p_request->'attachment','null'::jsonb) <> 'null'::jsonb then
    if jsonb_typeof(p_request->'attachment') <> 'object'
      or ((p_request->'attachment') - 'name') <> '{}'::jsonb
      or jsonb_typeof(p_request->'attachment'->'name') is distinct from 'string' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    attachment_name := p_request->'attachment'->>'name';
    if length(attachment_name) = 0 or octet_length(attachment_name) > 2048
      or attachment_name ~ '(^/|/$|//|\\|[[:cntrl:]]|(^|/)\.\.?(/|$))' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    select count(*), (jsonb_agg(jsonb_build_object('bucket','maintenance-images',
      'id',o.id,'name',o.name,'version',o.version)) filter (where o.owner_id = caller_id::text))->0
      into object_count, attachment
    from storage.objects o where o.bucket_id = 'maintenance-images' and o.name = attachment_name
      and o.archived_at is null and not o.is_delete_marker;
    if object_count <> 1 or attachment is null then raise exception 'invalid_request' using errcode = 'PT400'; end if;
  end if;

  -- Storage is read-only metadata; no service insertion fallback or URL fetch.
  begin
    insert into public."Maintenance"(user_id,category,description,location,created_at,location_id,attachment_ref,image_data)
    values(caller_id,p_request->>'category',p_request->>'description',p_request->>'location',
      clock_timestamp(),target_location,attachment,null) returning * into report;
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    if attachment is not null and not exists (
      select 1 from storage.objects o where o.id = (attachment->>'id')::uuid
        and o.bucket_id = 'maintenance-images' and o.name = attachment_name
        and o.version is not distinct from attachment->>'version'
        and o.archived_at is null and not o.is_delete_marker and o.owner_id = caller_id::text
    ) then raise exception 'invalid_request' using errcode = 'PT400'; end if;
    return jsonb_build_object('success',true,'message','Request logged','record',jsonb_build_array(to_jsonb(report)));
  exception
    when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
    when sqlstate 'PT403' then raise exception 'account_restricted' using errcode = 'PT403';
    when sqlstate 'PT400' then raise exception 'invalid_request' using errcode = 'PT400';
    when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
  end;
exception
  when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
  when sqlstate 'PT403' then
    if sqlerrm = 'user_mismatch' then raise exception 'user_mismatch' using errcode = 'PT403'; end if;
    raise exception 'account_restricted' using errcode = 'PT403';
  when sqlstate 'PT400' then raise exception 'invalid_request' using errcode = 'PT400';
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;
revoke all on function public.submit_maintenance_request(jsonb) from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.submit_maintenance_request(jsonb) to authenticated;



-- SOURCE: supabase/migrations/20260930171558_human_wallet_spend_admission.sql
-- Human debit boundaries only. Provider settlement/reversal/refund routines and
-- function ACLs are unchanged. Requires the reviewed wallet serialization batch.

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



-- SOURCE: supabase/migrations/20260930184955_wallet_read_admission.sql

do $$
begin
  if to_regprocedure('public.get_admission_status()') is null
    or not exists (select 1 from pg_class where oid = 'public.wallet_balances'::regclass
      and relkind = 'v' and 'security_invoker=true' = any(reloptions))
    or (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
      where c.relnamespace = 'public'::regnamespace and c.relrowsecurity
        and not p.polpermissive and p.polcmd = 'r'
        and 'authenticated'::regrole = any(p.polroles)
        and (c.relname, p.polname) in (
          ('wallet_accounts', 'portal_wallet_direct_self'),
          ('wallet_loads', 'portal_load_direct_self'),
          ('wallet_ledger_entries', 'portal_ledger_direct_self'),
          ('wallet_redemptions', 'portal_redemption_direct_self'))) <> 4 then
    raise exception 'Reviewed canonical admission and self-only wallet policies required'
      using errcode = '55000';
  end if;
end;
$$;

-- AND with existing ownership policies. The scalar subquery evaluates the
-- canonical caller once per scan; no parallel eligibility rules or global role
-- grants. Definer settlement/refund routines retain their existing exceptions.
create policy wallet_accounts_home_admission on public.wallet_accounts
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

create policy wallet_loads_home_admission on public.wallet_loads
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

create policy wallet_ledger_home_admission on public.wallet_ledger_entries
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

create policy wallet_redemptions_home_admission on public.wallet_redemptions
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));



-- SOURCE: supabase/migrations/20260930190143_complaint_admission_recheck.sql

do $$
begin
  if to_regprocedure('private.portal_staff_context()') is null
    or to_regprocedure('public.record_deleted_account_complaint(uuid,text,text)') is null then
    raise exception 'Reviewed staff admission and complaint prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

create or replace function public.record_deleted_account_complaint(
  wallet_id uuid,
  complaint_note text,
  resolution text default 'denied'
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  complaint_id bigint;
  actor uuid;
  staff_context jsonb;
begin
  staff_context := private.portal_staff_context();
  actor := (staff_context->>'actor')::uuid;

  if complaint_note is null or btrim(complaint_note) = '' then
    raise exception 'Complaint note required';
  end if;

  insert into public.deleted_account_complaints(
    wallet_account_id, complaint_note, resolution, created_by
  ) values (
    wallet_id, complaint_note, resolution, actor
  ) returning id into complaint_id;

  -- FK and trigger waits can outlive authority. Reuse the fresh staff evaluator;
  -- wallet complaints do not acquire a new location or customer-terms policy.
  staff_context := private.portal_staff_context();
  if (staff_context->>'actor')::uuid is distinct from actor then
    raise exception 'admin_access_changed' using errcode = 'PT403';
  end if;
  return complaint_id;
end;
$$;



-- SOURCE: supabase/migrations/20260930193130_new_payment_service_control.sql
-- Local new-payment creation control only. No settlement/recovery gates.

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



-- SOURCE: supabase/migrations/20260930180614_legacy_machine_claim_atomicity.sql

do $$
begin
  if current_user <> 'postgres'
    or to_regclass('private.account_lifecycle') is null
    or to_regprocedure('public.get_admission_status()') is null
    or to_regprocedure('public.increment_user_refund_attempts(uuid)') is null
    or to_regprocedure('public.request_cortina_loyalty_credit(bigint,text)') is null then
    raise exception 'Reviewed admission, lifecycle and claim prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- A pending manual claim, not payment proof or a wallet credit. Old direct
-- writers require coordinated client adoption; this RPC does not retire them.
create function public.request_legacy_loyalty_credit(
  target_transaction_id bigint, request_description text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caller uuid;
  payment public.transactions%rowtype;
  request public."Refunds"%rowtype;
  reason text := nullif(btrim(request_description), '');
  matches bigint;
  request_id bigint;
  amount numeric;
begin
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller := auth.uid();
  if reason is null or char_length(reason) > 2000 then
    raise exception 'Enter a reason of 1 to 2000 characters' using errcode = '22023';
  end if;

  select * into payment from public.transactions
  where id = target_transaction_id and user_id = caller for no key update;
  if not found then
    raise exception 'Transaction is not available for this account' using errcode = '42501';
  end if;
  perform 1 from public.profiles where id = caller for no key update;
  if not found then raise exception 'account_restricted' using errcode = 'PT403'; end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  amount := payment.amount::numeric;
  if payment.cortina_vend_session_id is not null or payment.cortina_status is not null
    or payment.type is distinct from 'laundry'
    or amount is null or amount::text in ('NaN','Infinity','-Infinity')
    or amount <= 0 or amount > 21474836.47 or trunc(amount, 2) <> amount then
    raise exception 'Transaction is not eligible for a legacy machine claim' using errcode = '22023';
  end if;

  -- Do not lock an existing Refunds row: admin resolution locks that row before
  -- its transaction/wallet/profile. Ambiguous history is never chosen or merged.
  select count(*), min(refund_id) into matches, request_id
  from public."Refunds" where transaction_id = payment.id;
  if matches > 1 then
    raise exception 'Claim history requires reconciliation' using errcode = '22023';
  elsif matches = 1 then
    select * into request from public."Refunds" where refund_id = request_id;
    if not found or request.user_id is distinct from caller
      or request.transaction_id is distinct from payment.id
      or request.amount::numeric is distinct from amount
      or request.status is null then
      raise exception 'Claim history requires reconciliation' using errcode = '22023';
    end if;
    if public.get_admission_status()->>'next_step' is distinct from 'home' then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    return jsonb_build_object('refund_id', request.refund_id,
      'amount', request.amount, 'status', request.status);
  end if;

  if payment.created_at is null or payment.created_at > clock_timestamp()
    or payment.created_at < clock_timestamp() - interval '14 days' then
    raise exception 'Credit request period has expired' using errcode = '22023';
  end if;
  insert into public."Refunds" (user_id, transaction_id, description, amount)
  values (caller, payment.id, reason, payment.amount) returning * into request;
  update public.transactions set requested_refund = true where id = payment.id;
  perform public.increment_user_refund_attempts(caller);

  -- Trigger waits may outlive authority or the claim window; roll back all
  -- three writes in that case. Notice enqueue is a separate post-commit call.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if payment.created_at < clock_timestamp() - interval '14 days' then
    raise exception 'Credit request period has expired' using errcode = '22023';
  end if;
  return jsonb_build_object('refund_id', request.refund_id,
    'amount', request.amount, 'status', request.status);
end;
$$;

revoke all on function public.request_legacy_loyalty_credit(bigint,text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.request_legacy_loyalty_credit(bigint,text) to authenticated;



-- SOURCE: supabase/migrations/20260930202731_customer_mfa_recovery.sql
-- Owner-supported customer recovery only. No Auth mutation is performed by SQL.

do $$ begin
  if to_regprocedure('private.portal_staff_context()') is null
    or to_regclass('public.admin_audit_events') is null then
    raise exception 'Canonical staff and immutable audit prerequisites required' using errcode='55000';
  end if;
end $$;

create table private.customer_mfa_recovery (
  user_id uuid primary key references public.profiles(id),
  recovery_id uuid not null unique default gen_random_uuid(),
  actor_id uuid not null,
  support_case text not null check (length(support_case) between 1 and 120),
  started_at timestamptz not null default clock_timestamp(),
  factor_ids uuid[] not null check (cardinality(factor_ids) between 1 and 10)
);
alter table private.customer_mfa_recovery enable row level security;
revoke all on private.customer_mfa_recovery from public,anon,authenticated,service_role,supabase_auth_admin;
grant select(created_at) on auth.mfa_factors to postgres;

-- Retain the canonical evaluator and its existing wire values. A recovery row
-- permanently requires MFA; deleting the newly enrolled factor cannot reopen AAL1.
create or replace function private.current_account_access()
returns jsonb language plpgsql stable security definer
set search_path='' set timezone='UTC' as $$
declare
  claims jsonb; caller_id uuid; session_id uuid; jwt_aal text; current_aal text;
  session_factor_id uuid; session_not_after timestamptz; session_created_at timestamptz;
  user_anonymous boolean; user_deleted_at timestamptz; user_banned_until timestamptz;
  user_email_confirmed_at timestamptz; caller_role text;
  has_totp boolean; unsupported_factor boolean; bound_totp boolean;
  lifecycle private.account_lifecycle%rowtype;
  recovery private.customer_mfa_recovery%rowtype;
  pending boolean; result jsonb;
begin
  begin
    claims:=auth.jwt(); caller_id:=auth.uid();
    session_id:=(claims->>'session_id')::uuid; jwt_aal:=claims->>'aal';
    if caller_id is null or session_id is null
      or (claims->>'sub')::uuid is distinct from caller_id
      or claims->>'role' is distinct from 'authenticated'
      or jsonb_typeof(claims->'exp') is distinct from 'number'
      or (claims->>'exp')::numeric <= extract(epoch from clock_timestamp())
      or coalesce(jwt_aal,'') not in ('aal1','aal2') then
      raise exception 'session_invalid' using errcode='PT401';
    end if;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'session_invalid' using errcode='PT401';
  end;
  select s.aal::text,s.factor_id,s.not_after,s.created_at
    into current_aal,session_factor_id,session_not_after,session_created_at
    from auth.sessions s where s.id=session_id and s.user_id=caller_id;
  if not found or coalesce(current_aal,'') not in ('aal1','aal2')
    or session_not_after <= clock_timestamp() then
    raise exception 'session_invalid' using errcode='PT401';
  end if;
  select u.is_anonymous,u.deleted_at,u.banned_until,u.email_confirmed_at
    into user_anonymous,user_deleted_at,user_banned_until,user_email_confirmed_at
    from auth.users u where u.id=caller_id;
  if not found then raise exception 'session_invalid' using errcode='PT401'; end if;
  result:=jsonb_build_object('subject_id',caller_id,'account_access','restricted',
    'next_step','blocked','reason','account_restricted','account_state','blocked',
    'restore_until',null,'provisioning_allowed',false,'lifecycle_identity_allowed',false);
  if user_anonymous is not false or user_deleted_at is not null
    or user_banned_until > clock_timestamp() then return result; end if;
  select * into lifecycle from private.account_lifecycle where user_id=caller_id;
  pending:=found and lifecycle.restored_at is null;
  if lifecycle.restored_at is not null and (session_created_at is null
    or session_created_at <= lifecycle.deletion_requested_at) then
    raise exception 'session_invalid' using errcode='PT401';
  end if;
  select * into recovery from private.customer_mfa_recovery where user_id=caller_id;
  if found and (session_created_at is null or session_created_at <= recovery.started_at
    or session_created_at > clock_timestamp()) then
    raise exception 'session_invalid' using errcode='PT401';
  end if;
  result:=result || jsonb_build_object(
    'account_state',case when pending then 'pending_deletion' else 'legacy_active' end,
    'restore_until',case when pending then lifecycle.restore_until else null end,
    'provisioning_allowed',not pending,'reason',null);
  if user_email_confirmed_at is null then
    return result || jsonb_build_object('next_step','verify_email');
  end if;
  select p.roles::text into caller_role from public.profiles p where p.id=caller_id;
  if not found then return result || jsonb_build_object('reason','profile_missing'); end if;
  if coalesce(caller_role,'') not in ('User','Admin','Owner') then
    return result || jsonb_build_object('reason','role_unavailable');
  end if;
  select coalesce(bool_or(f.status::text='verified' and f.factor_type::text='totp'
      and (recovery.user_id is null or f.created_at>recovery.started_at)),false),
    coalesce(bool_or(coalesce(f.status::text,'') not in ('unverified','verified')
      or (f.status::text='verified' and f.factor_type::text is distinct from 'totp')),false),
    coalesce(bool_or(f.id=session_factor_id and f.status::text='verified'
      and f.factor_type::text='totp'
      and (recovery.user_id is null or f.created_at>recovery.started_at)),false)
    into has_totp,unsupported_factor,bound_totp
    from auth.mfa_factors f where f.user_id=caller_id;
  if unsupported_factor then return result || jsonb_build_object('reason','unsupported_factor'); end if;
  -- Incomplete/unknown Auth outcomes stay fenced, even with a new AAL2 session.
  if recovery.user_id is not null and exists (select 1 from auth.mfa_factors f
    where f.user_id=caller_id and f.id=any(recovery.factor_ids)) then
    return result || jsonb_build_object('reason','account_restricted');
  end if;
  if (caller_role in ('Admin','Owner') or recovery.user_id is not null) and not has_totp then
    return result || jsonb_build_object('next_step','enroll_totp');
  end if;
  if has_totp and (jwt_aal<>'aal2' or current_aal<>'aal2' or not bound_totp) then
    return result || jsonb_build_object('next_step','challenge_totp');
  end if;
  result:=result || jsonb_build_object('lifecycle_identity_allowed',true);
  if pending then
    return result || jsonb_build_object('reason',case when clock_timestamp() >= lifecycle.restore_until
      then 'restore_expired' else 'explicit_restore_required' end);
  end if;
  return result || jsonb_build_object('account_access','eligible','next_step','home');
exception when sqlstate 'PT401' then raise;
  when others then raise exception 'admission_unavailable' using errcode='PT503';
end $$;

-- A target cannot become privileged while any captured factor is removable.
-- Once all captured IDs are absent, stale executions cannot delete a new factor.
create function private.guard_customer_recovery_role()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.roles is distinct from old.roles and exists (
    select 1 from private.customer_mfa_recovery r join auth.mfa_factors f
      on f.user_id=r.user_id and f.id=any(r.factor_ids) where r.user_id=old.id
  ) then raise exception 'customer_recovery_pending' using errcode='PT409'; end if;
  return new;
end $$;
revoke all on function private.guard_customer_recovery_role() from public,anon,authenticated,service_role;
create trigger customer_recovery_role_guard before update of roles on public.profiles
  for each row execute function private.guard_customer_recovery_role();

-- One caller-bound endpoint: inspect an exact UUID, prepare a verified case, or
-- revalidate the same recovery before each external removal. No email authority.
create function public.customer_mfa_recovery_request(
  action text, target_user_id uuid, support_case text default null,
  identity_verified boolean default false, expected_recovery_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  before_context jsonb; actor uuid; session_started timestamptz;
  r private.customer_mfa_recovery%rowtype; ids uuid[]; remaining uuid[];
  actor_name text;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if before_context->>'role' is distinct from 'Owner' or target_user_id is null
    or target_user_id=actor then raise exception 'recovery_forbidden' using errcode='PT403'; end if;
  if action is null or action not in ('inspect','prepare','authorize') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  -- Follow auth -> profile lock order; deterministic order also covers two Owners.
  perform 1 from auth.users where id in (actor,target_user_id) order by id for share;
  perform 1 from public.profiles where id in (actor,target_user_id) order by id for no key update;
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'recovery_forbidden' using errcode='PT403';
  end if;
  select s.created_at into session_started from auth.sessions s
    where s.id=(auth.jwt()->>'session_id')::uuid and s.user_id=actor;
  if session_started is null or session_started <= clock_timestamp()-interval '10 minutes'
    or session_started > clock_timestamp() then
    raise exception 'fresh_sign_in_required' using errcode='PT403';
  end if;
  if not exists (select 1 from public.profiles p join auth.users u on u.id=p.id
    where p.id=target_user_id and p.roles::text='User' and u.is_anonymous is false
      and u.email_confirmed_at is not null and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= clock_timestamp()))
    or exists (select 1 from private.account_lifecycle l where l.user_id=target_user_id and l.restored_at is null) then
    raise exception 'recovery_target_unavailable' using errcode='PT403';
  end if;
  if exists (select 1 from auth.mfa_factors f where f.user_id=target_user_id
    and (f.factor_type::text is distinct from 'totp' or f.status::text not in ('unverified','verified'))) then
    raise exception 'unsupported_factor' using errcode='PT403';
  end if;
  select * into r from private.customer_mfa_recovery where user_id=target_user_id;
  if action='prepare' then
    if identity_verified is distinct from true or support_case is null
      or support_case <> btrim(support_case) or length(support_case) not between 1 and 120
      or support_case ~ '[[:cntrl:]]' then raise exception 'invalid_request' using errcode='22023'; end if;
    if r.user_id is not null and r.support_case=support_case then
      null; -- Exact case replay never expands the captured factor set.
    else
      if r.user_id is not null and exists (select 1 from auth.mfa_factors f
        where f.user_id=target_user_id and f.id=any(r.factor_ids)) then
        raise exception 'customer_recovery_pending' using errcode='PT409';
      end if;
      if not exists (select 1 from auth.mfa_factors f where f.user_id=target_user_id
        and f.status::text='verified' and f.factor_type::text='totp') then
        raise exception 'recovery_target_unavailable' using errcode='PT403';
      end if;
      select array_agg(f.id order by f.id) into ids from auth.mfa_factors f where f.user_id=target_user_id;
      if cardinality(ids)>10 then raise exception 'unsupported_factor' using errcode='PT403'; end if;
      insert into private.customer_mfa_recovery(user_id,actor_id,support_case,factor_ids)
        values(target_user_id,actor,support_case,ids)
      on conflict(user_id) do update set recovery_id=gen_random_uuid(),actor_id=excluded.actor_id,
        support_case=excluded.support_case,started_at=clock_timestamp(),factor_ids=excluded.factor_ids
      returning * into r;
      select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
      insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,after_values)
        values(actor,actor_name,'customer_mfa_recovery',target_user_id::text,'verified_recovery_started',
          jsonb_build_object('recovery_id',r.recovery_id,'support_case',r.support_case,
            'externally_verified',true,'reenrollment_required',true,'factor_count',cardinality(r.factor_ids)));
    end if;
  elsif action='authorize' and (r.recovery_id is null or expected_recovery_id is distinct from r.recovery_id) then
    raise exception 'recovery_conflict' using errcode='PT409';
  end if;
  select coalesce(array_agg(f.id order by f.id),'{}'::uuid[]) into remaining
    from auth.mfa_factors f where f.user_id=target_user_id and f.id=any(r.factor_ids);
  if action='authorize' and cardinality(remaining)>0 then
    select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,after_values)
      values(actor,actor_name,'customer_mfa_recovery',target_user_id::text,'factor_removal_authorized',
        jsonb_build_object('recovery_id',r.recovery_id,'support_case',r.support_case,
          'remaining_factor_count',cardinality(remaining)));
  end if;
  -- Recheck after audit INSERT/trigger waits as well as initial profile locks.
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'recovery_forbidden' using errcode='PT403';
  end if;
  if not exists (select 1 from auth.sessions s where s.id=(auth.jwt()->>'session_id')::uuid
    and s.user_id=actor and s.created_at>clock_timestamp()-interval '10 minutes'
    and s.created_at<=clock_timestamp()) then
    raise exception 'fresh_sign_in_required' using errcode='PT403';
  end if;
  return jsonb_build_object('target_user_id',target_user_id,'recovery_id',r.recovery_id,
    'support_case',r.support_case,'reenrollment_required',r.user_id is not null,
    'remaining_factor_ids',remaining,'state',case when r.user_id is null then 'not_started'
      when cardinality(remaining)>0 then 'removal_pending' else 'reenrollment_required' end);
end $$;
revoke all on function public.customer_mfa_recovery_request(text,uuid,text,boolean,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.customer_mfa_recovery_request(text,uuid,text,boolean,uuid) to authenticated;


-- SOURCE: supabase/migrations/20260930213402_canonical_admin_onboarding.sql

do $$ begin
  if to_regprocedure('private.portal_staff_context()') is null
    or to_regprocedure('public.admin_portal_assign_member(uuid,uuid,bigint[])') is null
    or to_regclass('public.admin_audit_events') is null
    or to_regclass('private.account_lifecycle') is null then
    raise exception 'Reviewed canonical staff, invitation, audit and lifecycle prerequisites required';
  end if;
end $$;

-- Reuse the immutable audit as the bounded request receipt, not a second queue.
create unique index admin_team_onboarding_receipt_once
on public.admin_audit_events(entity_id, operation)
where entity='team_onboarding' and operation in ('completed','delivered');

create function public.admin_team_onboarding(
  action text, target_email text default null, target_locations bigint[] default null,
  target_user_id uuid default null, request_id bigint default null
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  before_context jsonb; actor uuid; actor_name text; mode text;
  email_address text; ids bigint[]; target uuid; matches uuid[];
  receipt public.admin_audit_events%rowtype; receipt_id bigint;
  account record; email_action text:='invite'; target_role text; completed boolean:=false;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if before_context->>'role' is distinct from 'Owner' then
    raise exception 'owner_required' using errcode='PT403';
  end if;
  if action is null or action not in ('invite','resend','authorize','complete') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  if action in ('invite','resend') then
    if request_id is not null or array_ndims(target_locations) is distinct from 1
      or cardinality(target_locations) not between 1 and 50
      or exists(select 1 from unnest(target_locations) n where n is null or n<=0)
      or (action='invite' and (target_user_id is not null or target_email is null
        or length(target_email)>254 or target_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
      or (action='resend' and (target_user_id is null or target_email is not null
        or cardinality(target_locations)<>1)) then
      raise exception 'invalid_request' using errcode='22023';
    end if;
    select array_agg(distinct n order by n) into ids from unnest(target_locations) n;
    mode:=action;
    if mode='invite' then
      email_address:=lower(btrim(target_email));
      select array_agg(id) into matches from auth.users where lower(email)=email_address;
      if cardinality(matches)>1 then raise exception 'invitation_conflict' using errcode='PT409'; end if;
      target:=matches[1];
    else
      target:=target_user_id;
      select lower(email) into email_address from auth.users where id=target;
      if email_address is null then raise exception 'invitation_conflict' using errcode='PT409'; end if;
    end if;
  else
    if request_id is null or target_email is not null or target_locations is not null
      or (action='authorize' and target_user_id is not null)
      or (action='complete' and target_user_id is null) then
      raise exception 'invalid_request' using errcode='22023';
    end if;
    -- Lock the immutable request row to serialize completion and delivery replay.
    select * into receipt from public.admin_audit_events where id=request_id
      and entity='team_onboarding' and operation='requested' for update;
    if not found or receipt.actor_id is distinct from actor
      or receipt.created_at<clock_timestamp()-interval '10 minutes' then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
    receipt_id:=receipt.id; mode:=receipt.after_values->>'mode';
    email_address:=receipt.after_values->>'email'; ids:=receipt.location_ids;
    target:=(receipt.after_values->>'target_user_id')::uuid;
    if action='complete' then
      if target is not null and target is distinct from target_user_id then
        raise exception 'invitation_conflict' using errcode='PT409';
      end if;
      target:=target_user_id;
    end if;
    select exists(select 1 from public.admin_audit_events where entity='team_onboarding'
      and entity_id=receipt_id::text and operation='completed') into completed;
    if action='authorize' and completed then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
  end if;

  if exists(select 1 from unnest(ids) n where not exists(select 1
    from public."Location_to_Admin" where user_id=actor and location_id=n)) then
    raise exception 'location_access_denied' using errcode='PT403';
  end if;
  perform 1 from public."Locations" where id=any(ids) order by id for share;
  if (select count(*) from public."Locations" where id=any(ids))<>cardinality(ids) then
    raise exception 'location_access_denied' using errcode='PT403';
  end if;
  if target is null then
    if mode<>'invite' or action='complete' or exists(select 1 from auth.users where lower(email)=email_address) then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
  else
    -- Same target lock order as lifecycle: Auth SHARE, then profile NO KEY UPDATE.
    select email,email_confirmed_at,is_anonymous,deleted_at,banned_until into account
      from auth.users where id=target for share;
    if not found or account.is_anonymous is distinct from false or account.deleted_at is not null
      or (account.banned_until is not null and account.banned_until>clock_timestamp())
      or lower(account.email) is distinct from email_address then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
    email_action:=case when account.email_confirmed_at is null then 'invite' else 'recovery' end;
    select roles::text into target_role from public.profiles where id=target for no key update;
    if target=actor or target_role='Owner' or exists(select 1 from private.account_lifecycle
      where user_id=target and restored_at is null) then
      raise exception 'target_restricted' using errcode='PT403';
    end if;
    if (mode='resend' or completed) and (target_role is distinct from 'Admin'
      or exists(select 1 from unnest(ids) n where not exists(select 1
        from public."Location_to_Admin" where user_id=target and location_id=n))) then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
  end if;

  if action in ('invite','resend') then
    select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
      values(actor,actor_name,'team_onboarding',coalesce(target::text,email_address),'requested',ids,
        jsonb_build_object('mode',mode,'email',email_address,'target_user_id',target)) returning id into receipt_id;
  elsif action='complete' and not completed then
    if mode='invite' then
      perform public.admin_portal_assign_member(actor,target,ids);
    else
      insert into public.admin_invitations(user_id,location_id,invited_by)
        select target,n,actor from unnest(ids) n on conflict(user_id,location_id) do nothing;
    end if;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
      values(actor,receipt.actor_name,'team_onboarding',receipt_id::text,'completed',ids,
        jsonb_build_object('target_user_id',target));
  end if;
  -- Recheck after membership/FK/audit triggers, not just before their waits.
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  if action in ('authorize','complete') and receipt.created_at<clock_timestamp()-interval '10 minutes' then
    raise exception 'invitation_conflict' using errcode='PT409';
  end if;
  if target is not null and (not exists(select 1 from auth.users where id=target
      and is_anonymous is false and deleted_at is null and lower(email)=email_address
      and (banned_until is null or banned_until<=clock_timestamp()))
    or exists(select 1 from private.account_lifecycle where user_id=target and restored_at is null)
    or exists(select 1 from public.profiles where id=target and roles::text='Owner')
    or (action='complete' and (not exists(select 1 from public.profiles where id=target and roles::text='Admin')
      or exists(select 1 from unnest(ids) n where not exists(select 1 from public."Location_to_Admin"
        where user_id=target and location_id=n))))) then
    raise exception 'target_restricted' using errcode='PT403';
  end if;
  return jsonb_build_object('request_id',receipt_id::text,'actor_id',actor,'target_user_id',target,
    'email',email_address,'location_ids',ids,'email_action',email_action);
end $$;
revoke all on function public.admin_team_onboarding(text,text,bigint[],uuid,bigint)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.admin_team_onboarding(text,text,bigint[],uuid,bigint) to authenticated;

-- Only the trusted Auth adapter records a successful send; a browser cannot
-- forge delivery or use this metadata-only RPC to assign a role/location.
create function public.admin_team_invitation_delivered(request_id bigint, target_user_id uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
declare receipt public.admin_audit_events%rowtype;
begin
  select * into receipt from public.admin_audit_events where id=request_id
    and entity='team_onboarding' and operation='requested' for update;
  if not found or not exists(select 1 from public.admin_audit_events
    where entity='team_onboarding' and entity_id=request_id::text and operation='completed'
      and after_values->>'target_user_id'=target_user_id::text) then
    raise exception 'invitation_conflict' using errcode='PT409';
  end if;
  if exists(select 1 from public.admin_audit_events where entity='team_onboarding'
    and entity_id=request_id::text and operation='delivered') then return; end if;
  update public.admin_invitations set delivery_status='sent',last_sent_at=clock_timestamp()
    where user_id=target_user_id and location_id=any(receipt.location_ids);
  insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
    values(receipt.actor_id,receipt.actor_name,'team_onboarding',request_id::text,'delivered',receipt.location_ids,
      jsonb_build_object('target_user_id',target_user_id));
end $$;
revoke all on function public.admin_team_invitation_delivered(bigint,uuid)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.admin_team_invitation_delivered(bigint,uuid) to service_role;



-- SOURCE: supabase/migrations/20260930220649_customer_record_read_admission.sql
-- Narrow ordinary-record SELECT gate. No data changes or financial RPC edits.

do $$
begin
  if current_user <> 'postgres'
    or to_regprocedure('private.account_access_allowed()') is null
    or to_regclass('private.account_lifecycle') is null
    or to_regprocedure('private.portal_record_access(text,jsonb)') is null
    or to_regprocedure('private.portal_record_access_before_authorization(text,jsonb)') is null then
    raise exception 'Reviewed canonical portal and lifecycle prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- The existing wrapper already gates staff. Extend that same canonical
-- eligibility requirement to customers before the legacy own-record shortcut.
-- Do not require Home/terms here: this is not a wallet-spend permission.
create or replace function private.portal_record_access(kind text, record jsonb)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.account_access_allowed() then return false; end if;
  return private.portal_record_access_before_authorization(kind, record);
end;
$$;

-- CREATE OR REPLACE preserves identity, policy bindings, ownership and ACLs.


-- SOURCE: supabase/migrations/20260930223814_cortina_claim_admission.sql
-- Human claims use canonical admission; clients cannot manufacture financial rows.
-- No historical writes, provider calls, or settlement/refund policy changes.

do $$
begin
  if current_user <> 'postgres'
    or to_regclass('private.account_lifecycle') is null
    or to_regprocedure('public.get_admission_status()') is null
    or to_regprocedure('public.request_cortina_loyalty_credit(bigint,text)') is null
    or to_regprocedure('public.request_legacy_loyalty_credit(bigint,text)') is null
    or to_regprocedure('public.increment_user_refund_attempts(uuid)') is null then
    raise exception 'Reviewed canonical admission and both atomic claim contracts required'
      using errcode = '55000';
  end if;
end;
$$;

create or replace function public.request_cortina_loyalty_credit(
  target_transaction_id bigint, request_description text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  customer_id uuid := auth.uid();
  payment public.transactions%rowtype;
  vend public.cortina_vend_sessions%rowtype;
  request public."Refunds"%rowtype;
  reason text := nullif(btrim(request_description), '');
begin
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if customer_id is null then
    raise exception using errcode = '42501', message = 'Sign in to request loyalty credit';
  end if;
  if reason is null or char_length(reason) > 2000 then
    raise exception using errcode = '22023', message = 'Enter a reason of 1 to 2000 characters';
  end if;
  select * into payment from public.transactions
  where id = target_transaction_id and user_id = customer_id
    and cortina_vend_session_id is not null;
  if not found then
    raise exception using errcode = '42501', message = 'Transaction is not available for this account';
  end if;
  -- Retain the existing session-first lock order shared with callback validation.
  select * into vend from public.cortina_vend_sessions
  where id = payment.cortina_vend_session_id for update;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if vend.status <> 'started' or vend.user_id is distinct from customer_id then
    raise exception using errcode = '22023', message = 'Vend is not eligible for loyalty credit';
  end if;
  select * into request from public."Refunds" where transaction_id = payment.id;
  if not found then
    if payment.created_at < now() - interval '14 days' then
      raise exception using errcode = '22023', message = 'Credit request period has expired';
    end if;
    insert into public."Refunds" (user_id, transaction_id, description, amount)
    values (customer_id, payment.id, reason, vend.amount_cents::numeric / 100)
    returning * into request;
    perform public.increment_user_refund_attempts(customer_id);
  end if;
  -- Trigger/counter waits and read-only replay must not return stale admission.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  return jsonb_build_object('refund_id', request.refund_id,
    'amount', request.amount, 'status', request.status);
end;
$$;

-- Preserve trusted service/definer writers. Table revokes alone leave column
-- grants behind; restrictive policies also deny later accidental client grants.
do $$
declare
  target text;
  columns text;
begin
  foreach target in array array['transactions', 'Refunds'] loop
    if not exists (select 1 from pg_class c where c.oid = format('public.%I', target)::regclass
      and c.relowner = 'postgres'::regrole and c.relrowsecurity and not c.relforcerowsecurity) then
      raise exception 'Reviewed financial table ownership and RLS required' using errcode = '55000';
    end if;
    select string_agg(quote_ident(attname), ', ' order by attnum) into columns
      from pg_attribute where attrelid = format('public.%I', target)::regclass
        and attnum > 0 and not attisdropped;
    execute format('revoke insert on table public.%I from public, anon, authenticated', target);
    execute format('revoke insert (%s) on public.%I from public, anon, authenticated', columns, target);
    if exists (select 1 from (values ('anon'), ('authenticated')) r(role_name)
      where has_table_privilege(r.role_name, format('public.%I', target), 'INSERT')
        or has_any_column_privilege(r.role_name, format('public.%I', target), 'INSERT')) then
      raise exception 'Inherited client financial INSERT privilege requires review' using errcode = '42501';
    end if;
    if not has_table_privilege('service_role', format('public.%I', target), 'INSERT') then
      raise exception 'Existing trusted financial writer privilege must remain' using errcode = '42501';
    end if;
  end loop;
end;
$$;

create policy transactions_server_insert_only on public.transactions
  as restrictive for insert to anon, authenticated with check (false);
create policy refunds_server_insert_only on public."Refunds"
  as restrictive for insert to anon, authenticated with check (false);



-- SOURCE: supabase/migrations/20260930220243_credit_decision_mail_outbox.sql
-- Atomic decision notices only. Financial decisions and provider calls stay separate.

alter table private.mail_outbox
  add column credit_refund_id bigint,
  add column credit_resolved_at timestamptz,
  add column credit_notice jsonb;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check check (kind in (
  'account_welcome','newsletter_confirm','newsletter_welcome','refund_request',
  'account_deletion_scheduled','account_restored','credit_decision'
));
alter table private.mail_outbox add constraint mail_outbox_credit_notice_check check (
  (kind='credit_decision' and credit_refund_id is not null and credit_resolved_at is not null
    and credit_notice is not null and jsonb_typeof(credit_notice)='object'
    and consent_id is null)
  or (kind<>'credit_decision' and credit_refund_id is null
    and credit_resolved_at is null and credit_notice is null)
);
-- No FK may erase the permanent event key when source records are cleaned up.

create or replace function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and (
    (o.kind in ('account_deletion_scheduled','account_restored') and exists (
      select 1 from private.account_lifecycle l where l.user_id=o.user_id
        and l.deletion_requested_at=o.lifecycle_requested_at
        and l.restore_until=o.lifecycle_restore_until
        and ((o.kind='account_deletion_scheduled' and l.restored_at is null
            and l.restore_until>clock_timestamp())
          or (o.kind='account_restored' and l.restored_at=o.lifecycle_restored_at))))
    or (o.kind='credit_decision' and exists (
      select 1 from public."Refunds" r
        join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
      where r.refund_id=o.credit_refund_id and r.user_id=o.user_id
        and r.resolved_at=o.credit_resolved_at and r.resolved_by is not null
        and r.status::text in ('approved','denied')
        and round((r.amount*100)::numeric) between 1 and 2147483647
        and o.credit_notice=jsonb_build_object('refund_id',r.refund_id::text,
          'transaction_id',r.transaction_id::text,'status',r.status::text,
          'amount_cents',round((r.amount*100)::numeric),
          'note',coalesce(r.admin_note,''))
        and (r.status::text='denied' or exists (
          select 1 from public.wallet_ledger_entries e
            join public.wallet_accounts w on w.id=e.wallet_account_id and w.user_id=r.user_id
          where e.refund_request_id=r.refund_id and e.entry_type::text='admin_adjustment'
            and e.amount_cents=round((r.amount*100)::numeric)
            and e.paid_amount_cents=0 and e.promo_amount_cents=e.amount_cents)))
      and not exists (select 1 from private.account_lifecycle l
        where l.user_id=o.user_id and l.restored_at is null))
    or (
      not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
        and (l.restored_at is null or o.kind not in ('account_welcome','refund_request')))
      and (o.kind='account_welcome' or (o.kind='refund_request'
        and exists (select 1 from private.mail_settings s join public.profiles p
          on p.id=s.refund_notice_recipient
          where s.refund_notice_recipient=o.user_id and p.roles::text='Owner')
        and exists (select 1 from public."Refunds" r
          join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
          join auth.users u on u.id=r.user_id
          where r.refund_id=o.refund_id and r.status::text='pending'
            and u.deleted_at is null and u.is_anonymous is false
            and (u.banned_until is null or u.banned_until<=clock_timestamp())
            and not exists (select 1 from private.account_lifecycle l
              where l.user_id=r.user_id and l.restored_at is null)))
        or (o.kind in ('newsletter_confirm','newsletter_welcome') and exists (
          select 1 from private.newsletter_consent c where c.id=o.consent_id
            and c.unsubscribed_at is null and c.email=o.email
            and ((o.kind='newsletter_confirm' and c.confirmed_at is null and c.expires_at>clock_timestamp())
              or (o.kind='newsletter_welcome' and c.confirmed_at is not null)))))
    )
  );
$$;

create function private.mail_credit_decision_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare o private.mail_outbox;
begin
  if old.status::text is distinct from 'pending'
    or new.status::text not in ('approved','denied')
    or new.resolved_at is null or new.resolved_by is null
    or new.amount is null or round((new.amount*100)::numeric) not between 1 and 2147483647
    or not exists (select 1 from private.mail_settings s
      where s.rollout_at is not null and new.resolved_at>=s.rollout_at) then
    return new;
  end if;
  -- Financial writers already hold refund/wallet rows. Nothing holding mail_lock
  -- may acquire those rows: worker completion records only the outbox, not Refunds.
  perform private.mail_lock();
  o.kind:='credit_decision'; o.user_id:=new.user_id;
  o.credit_refund_id:=new.refund_id; o.credit_resolved_at:=new.resolved_at;
  o.credit_notice:=jsonb_build_object('refund_id',new.refund_id::text,
    'transaction_id',new.transaction_id::text,'status',new.status::text,
    'amount_cents',round((new.amount*100)::numeric),'note',coalesce(new.admin_note,''));
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=new.user_id;
  if o.email is null then return new; end if;
  insert into private.mail_outbox(event_key,kind,user_id,email,
    credit_refund_id,credit_resolved_at,credit_notice,state,last_error)
  values ('loyalty_credit_'||new.status::text||'/'||new.refund_id,
    o.kind,o.user_id,o.email,o.credit_refund_id,o.credit_resolved_at,o.credit_notice,
    case when private.mail_allowed(o) then 'ready' else 'suppressed' end,
    case when private.mail_allowed(o) then null else 'suppressed_or_stale' end)
  on conflict(event_key) do nothing;
  return new;
end $$;
revoke all on function private.mail_credit_decision_event()
  from public,anon,authenticated,service_role,supabase_auth_admin;
create trigger mail_credit_decision after update of status on public."Refunds"
  for each row execute function private.mail_credit_decision_event();

-- Preserve the exact canonical caller/location guards and financial call.
-- Only the final result gains current outbox evidence; queued is never sent.
create or replace function public.admin_resolve_credit(target_refund_id bigint, target_decision text, resolution_note text default '')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare before_context jsonb; result jsonb; actor uuid;
  notice private.mail_outbox; notice_state text;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if length(coalesce(resolution_note,''))>4000 then raise exception 'invalid_request' using errcode='22023'; end if;
  perform public.admin_portal_data(actor,'assertCredit',jsonb_build_object('id',target_refund_id));
  result:=public.resolve_refund_request(target_refund_id,target_decision,resolution_note,actor);
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  -- The claim's machine may have changed location during an inner wallet wait.
  perform public.admin_portal_data(actor,'assertCredit',jsonb_build_object('id',target_refund_id));
  select o.* into notice from private.mail_outbox o join public."Refunds" r
    on r.refund_id=o.credit_refund_id and r.resolved_at=o.credit_resolved_at
    where r.refund_id=target_refund_id and o.kind='credit_decision'
      and o.event_key='loyalty_credit_'||r.status::text||'/'||r.refund_id
      and o.credit_notice->>'status'=r.status::text;
  if found then
    notice_state:=case when notice.state in ('ready','leased') and not private.mail_allowed(notice)
      then 'suppressed' else notice.state end;
  else
    notice_state:=case when result->>'notificationSent'='true' then 'legacy_sent' else 'not_queued' end;
  end if;
  return result||jsonb_build_object('notificationState',notice_state,
    'notificationSent',notice_state in ('accepted','delivered','legacy_sent'));
end; $$;

-- Existing ACLs, notify timestamps, retry/finish/webhook RPCs and all financial
-- routines remain unchanged. Disabled delivery retains post-rollout intent only.

-- Preserve installed containment; never silently repair a drifted activation gate.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) r
      WHERE has_function_privilege(r,'public.request_account_deletion()','EXECUTE'))
    OR (SELECT count(*) FROM private.mail_settings) <> 1
    OR EXISTS (SELECT 1 FROM private.mail_settings
      WHERE enabled IS DISTINCT FROM false OR rollout_at IS NOT NULL OR refund_notice_recipient IS NOT NULL) THEN
    RAISE EXCEPTION 'C/D requires deletion held and mail disabled without rollout/recipient' USING ERRCODE='55000';
  END IF;
END;
$$;

COMMIT;
