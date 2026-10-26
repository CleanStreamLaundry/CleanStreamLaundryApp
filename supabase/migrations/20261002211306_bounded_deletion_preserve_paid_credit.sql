-- Approved business decision, not deployment/execution authorization.
-- Policy hash is SHA-256 of this exact UTF-8 string, without a trailing newline:
-- retention-paid-credit-2026-10-02|restore=30-days-explicit|delete=auth-profile|paid=no-expiry-no-forfeiture|promo=cancel-at-final-deletion|unresolved=retain|reclaim=verified-owner-support
begin;

do $$
declare signature text; routine regprocedure; caller text;
begin
  if current_user<>'postgres' then raise exception 'Reviewed postgres operator required'; end if;
  if not private.account_cleanup_references_ready()
    or to_regprocedure('public.admin_wallet_read(text,jsonb)') is null
    or to_regprocedure('public.admin_record_legal_cash_redemption(uuid,integer,text,text)') is null then
    raise exception 'Retained financial subjects and canonical Owner wallet tools required';
  end if;
  -- CREATE OR REPLACE must replace an owned routine, never create a missing
  -- default-PUBLIC function. Existing ACLs are retained, not recreated/granted.
  foreach signature in array array['private.require_account_cleanup_policy(text,text)',
    'private.guard_account_cleanup_auth_delete()','private.prune_account_cleanup_retention()',
    'private.capture_topup_refund_spend()','private.capture_topup_refund_provenance()',
    'private.release_topup_refund(uuid)',
    'public.record_wallet_load_from_stripe(uuid,integer,text,text,text,text)'] loop
    routine:=to_regprocedure(signature);
    if routine is null or not exists(select 1 from pg_proc
      where oid=routine and proowner=(select oid from pg_roles where rolname=current_user)) then
      raise exception 'Owned replacement routine prerequisite mismatch: %',signature;
    end if;
    foreach caller in array array['anon','authenticated','supabase_auth_admin'] loop
      if has_function_privilege(caller,routine,'execute') then
        raise exception 'Unexpected replacement routine privilege: % / %',signature,caller;
      end if;
    end loop;
    if has_function_privilege('service_role',routine,'execute') is distinct from
      (signature='public.record_wallet_load_from_stripe(uuid,integer,text,text,text,text)') then
      raise exception 'Unexpected service replacement routine privilege: %',signature;
    end if;
  end loop;
end $$;

-- Invalidate the former draft approval; never activate cleanup in a migration.
update private.account_cleanup_execution set execution_enabled=false,
  approved_policy_version=null,approved_policy_sha256=null,final_policy_approved_at=null;

-- Change only the fixed policy identity in the existing gate/fences. Keep their
-- request, lease, hold, Storage and retention checks and ACLs exactly as installed.
do $$
declare signature text; definition text; c record; changed integer:=0;
begin
  for c in select conname,pg_get_constraintdef(oid) as definition from pg_constraint
    where conrelid='private.account_cleanup_execution'::regclass and contype='c'
      and strpos(pg_get_constraintdef(oid),'retention-draft-2026-10-01')>0 loop
    definition:=replace(replace(c.definition,'retention-draft-2026-10-01','retention-paid-credit-2026-10-02'),
      '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be',
      '756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592');
    execute format('alter table private.account_cleanup_execution drop constraint %I, add constraint %I %s',
      c.conname,c.conname,definition);
    changed:=changed+1;
  end loop;
  if changed<>1 then raise exception 'Cleanup policy constraint prerequisite mismatch'; end if;
  foreach signature in array array['private.require_account_cleanup_policy(text,text)',
    'private.guard_account_cleanup_auth_delete()','private.prune_account_cleanup_retention()'] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    if strpos(definition,'retention-draft-2026-10-01')=0 or
      strpos(definition,'3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be')=0 then
      raise exception 'Cleanup policy routine prerequisite mismatch: %',signature;
    end if;
    definition:=replace(replace(definition,'retention-draft-2026-10-01','retention-paid-credit-2026-10-02'),
      '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be',
      '756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592');
    if signature='private.guard_account_cleanup_auth_delete()' then
      if strpos(definition,'set reward_tracker=reward,retired_at=clock_timestamp()')=0 then
        raise exception 'Cleanup reward retirement prerequisite mismatch'; end if;
      definition:=replace(definition,'set reward_tracker=reward,retired_at=clock_timestamp()',
        'set reward_tracker=0,retired_at=clock_timestamp()');
    end if;
    execute definition;
  end loop;
end $$;

-- A distinct append-only entry identifies cancellation, not customer spending,
-- a cash refund or a reduction of paid principal. Never rewrite earlier entries.
alter table public.wallet_ledger_entries drop constraint wallet_ledger_entries_entry_type_check,
  add constraint wallet_ledger_entries_entry_type_check check(entry_type in
    ('legacy_balance','load_paid','load_bonus','redeem_paid','redeem_bonus','admin_adjustment',
     'legal_cash_redemption','stripe_refund','void','deletion_promo_cancellation')),
  add constraint wallet_deletion_promo_only check(entry_type<>'deletion_promo_cancellation'
    or (paid_amount_cents=0 and promo_amount_cents<0 and amount_cents=promo_amount_cents));

create function private.cancel_retired_account_promo(p_wallet uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
declare subject uuid; promo integer;
begin
  -- The same wallet lock serializes settlement, refund release and retirement.
  select user_id into subject from public.wallet_accounts where id=p_wallet for no key update;
  if not exists(select 1 from private.account_retained_subjects
    where user_id=subject and retired_at is not null) then return; end if;
  select promo_balance_cents into promo from public.wallet_balances where wallet_account_id=p_wallet;
  if promo>0 then
    insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
      paid_amount_cents,promo_amount_cents,note)
    values(p_wallet,'deletion_promo_cancellation',-promo,0,-promo,
      'Free promotional credit cancelled after final account deletion');
  end if;
end $$;

create function private.cancel_account_promo_on_retirement()
returns trigger language plpgsql security definer set search_path='' as $$
declare wallet uuid;
begin
  for wallet in select id from public.wallet_accounts where user_id=new.user_id
    order by id for no key update loop
    perform private.cancel_retired_account_promo(wallet);
    update public.wallet_accounts set status='deleted',deleted_at=coalesce(deleted_at,new.retired_at),
      deleted_reason='Final account deletion; paid credit retained',updated_at=clock_timestamp() where id=wallet;
  end loop;
  return new;
end $$;
create trigger cancel_account_promo_on_retirement after update of retired_at on private.account_retained_subjects
  for each row when (old.retired_at is null and new.retired_at is not null)
  execute function private.cancel_account_promo_on_retirement();

-- Late voids/claim resolutions can restore promo components. Keep their original
-- evidence and append the cancellation; never discard a paid reversal component.
create function private.cancel_retired_account_late_promo()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform private.cancel_retired_account_promo(new.wallet_account_id);
  return new;
end $$;
create trigger cancel_retired_account_late_promo after insert on public.wallet_ledger_entries
  for each row when (new.promo_amount_cents>0)
  execute function private.cancel_retired_account_late_promo();
revoke all on function private.cancel_retired_account_promo(uuid),
  private.cancel_account_promo_on_retirement(),private.cancel_retired_account_late_promo()
  from public,anon,authenticated,service_role,supabase_auth_admin;

create or replace function private.capture_topup_refund_spend()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.wallet_accounts where id=new.wallet_account_id for no key update;
  if new.entry_type<>'deletion_promo_cancellation' and new.voluntary_topup_refund_id is null
    and (new.paid_amount_cents<0 or new.promo_amount_cents<0) then
    insert into private.topup_refund_spend(ledger_id,wallet_id) values(new.id,new.wallet_account_id);
  end if;
  return new;
end $$;

-- Preserve the live-account algorithm, signatures, locks, idempotency and ACLs.
-- Only retired subjects stop accruing promotional value/reward progress.
create or replace function public.record_wallet_load_from_stripe(
  target_user_id uuid, amount_cents integer,
  stripe_payment_intent_id text default null, stripe_checkout_session_id text default null,
  stripe_charge_id text default null, stripe_event_id text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare wallet_id uuid; load_id bigint; existing_wallet_id uuid;
  reward_before_cents integer; combined_cents integer; bonus_count integer;
  bonus_cents integer; remainder_cents integer; retained boolean:=false;
begin
  if target_user_id is null or amount_cents is null or amount_cents<=0 then
    raise exception 'Invalid wallet load'; end if;
  select wl.wallet_account_id into existing_wallet_id from public.wallet_loads wl
    where (record_wallet_load_from_stripe.stripe_payment_intent_id is not null and wl.stripe_payment_intent_id=record_wallet_load_from_stripe.stripe_payment_intent_id)
      or (record_wallet_load_from_stripe.stripe_checkout_session_id is not null and wl.stripe_checkout_session_id=record_wallet_load_from_stripe.stripe_checkout_session_id)
      or (record_wallet_load_from_stripe.stripe_event_id is not null and wl.stripe_event_id=record_wallet_load_from_stripe.stripe_event_id)
    limit 1;
  if existing_wallet_id is not null then return existing_wallet_id; end if;
  wallet_id:=public.get_or_create_wallet_account(target_user_id);
  select wl.wallet_account_id into existing_wallet_id from public.wallet_loads wl
    where (record_wallet_load_from_stripe.stripe_payment_intent_id is not null and wl.stripe_payment_intent_id=record_wallet_load_from_stripe.stripe_payment_intent_id)
      or (record_wallet_load_from_stripe.stripe_checkout_session_id is not null and wl.stripe_checkout_session_id=record_wallet_load_from_stripe.stripe_checkout_session_id)
      or (record_wallet_load_from_stripe.stripe_event_id is not null and wl.stripe_event_id=record_wallet_load_from_stripe.stripe_event_id)
    limit 1;
  if existing_wallet_id is not null then return existing_wallet_id; end if;
  select coalesce(round(p.reward_tracker*100),0)::integer into reward_before_cents
    from public.profiles p where p.id=target_user_id for no key update;
  if not found then
    perform 1 from private.account_retained_subjects s where s.user_id=target_user_id and s.retired_at is not null
      for no key update;
    if not found then raise exception 'Wallet load profile not found'; end if;
    retained:=true;
  end if;
  if retained then
    bonus_cents:=0; remainder_cents:=0;
  else
    combined_cents:=reward_before_cents+amount_cents;
    bonus_count:=combined_cents/2000; bonus_cents:=bonus_count*500; remainder_cents:=combined_cents%2000;
  end if;
  insert into public.wallet_loads(wallet_account_id,user_id,amount_cents,paid_amount_cents,
    promo_amount_cents,stripe_payment_intent_id,stripe_checkout_session_id,stripe_charge_id,stripe_event_id,status,note)
  values(wallet_id,target_user_id,amount_cents,amount_cents,bonus_cents,stripe_payment_intent_id,
    stripe_checkout_session_id,stripe_charge_id,stripe_event_id,'succeeded','Stripe wallet load') returning id into load_id;
  insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,
    promo_amount_cents,wallet_load_id,stripe_payment_intent_id,stripe_charge_id,note)
  values(wallet_id,'load_paid',amount_cents,amount_cents,0,load_id,stripe_payment_intent_id,stripe_charge_id,'Paid loyalty card load');
  if bonus_cents>0 then
    insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,
      promo_amount_cents,wallet_load_id,stripe_payment_intent_id,stripe_charge_id,note)
    values(wallet_id,'load_bonus',bonus_cents,0,bonus_cents,load_id,stripe_payment_intent_id,stripe_charge_id,'Promotional loyalty reward credit');
  end if;
  if retained then
    update private.account_retained_subjects set reward_tracker=0 where user_id=target_user_id;
  else
    update public.profiles set reward_tracker=remainder_cents::numeric/100.0 where id=target_user_id;
  end if;
  perform public.sync_profile_wallet_balance(wallet_id);
  return wallet_id;
end $$;

create or replace function private.capture_topup_refund_provenance()
returns trigger language plpgsql security definer set search_path='' as $$
declare reward integer; retained boolean:=false;
begin
  perform 1 from public.wallet_accounts where id=new.wallet_account_id for no key update;
  select round(reward_tracker*100)::integer into reward from public.profiles where id=new.user_id;
  if not found then
    retained:=exists(select 1 from private.account_retained_subjects where user_id=new.user_id and retired_at is not null);
    if retained then reward:=0; end if;
  end if;
  if reward between 0 and 1999 and new.status='succeeded'
    and new.paid_amount_cents=new.amount_cents
    and new.promo_amount_cents=(case when retained then 0 else ((reward::bigint+new.amount_cents)/2000)*500 end) then
    insert into private.topup_refund_provenance(load_id,reward_before_cents) values(new.id,reward);
  end if;
  return new;
end $$;

create or replace function private.release_topup_refund(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r private.voluntary_topup_refunds%rowtype; reward integer; bonus integer; retained boolean:=false;
begin
  select * into r from private.voluntary_topup_refunds where id=p_id;
  if r.released_at is not null then return; end if;
  select round(reward_tracker*100)::integer into reward from public.profiles
    where id=r.customer_id for no key update nowait;
  if not found then
    perform 1 from private.account_retained_subjects where user_id=r.customer_id and retired_at is not null
      for no key update nowait;
    if not found then raise exception 'reward_provenance_unavailable' using errcode='PT409'; end if;
    retained:=true; reward:=0;
  end if;
  if reward is null or reward not between 0 and 1999 then
    raise exception 'reward_provenance_unavailable' using errcode='PT409'; end if;
  bonus:=case when retained then 0 else ((reward::bigint+r.principal_cents)/2000)*500 end;
  insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
    paid_amount_cents,promo_amount_cents,wallet_load_id,voluntary_topup_refund_id,note)
  values(r.wallet_id,'admin_adjustment',r.principal_cents+bonus,r.principal_cents,bonus,
    r.load_id,r.id,'Voluntary top-up refund reservation released');
  if retained then
    update private.account_retained_subjects set reward_tracker=0 where user_id=r.customer_id;
  else
    update public.profiles set reward_tracker=((reward::bigint+r.principal_cents)%2000)::numeric/100 where id=r.customer_id;
  end if;
  update private.voluntary_topup_refunds set released_at=clock_timestamp() where id=p_id;
  perform public.sync_profile_wallet_balance(r.wallet_id);
end $$;

-- No financial expiry column/job: the retained UUID, wallet, principal, provider
-- references and unresolved refunds survive all cleanup metadata/tax clocks.
-- Existing Owner search/detail and explicit audited remedies remain unchanged.
commit;
