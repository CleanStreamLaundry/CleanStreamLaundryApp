-- Prospective explicit consent only. Installation never enables execution or publishes terms.
-- SHA-256 input (UTF-8, no newline):
-- retention-voluntary-surrender-2026-10-05|restore=90-days-explicit|delete=auth-profile|paid=prospective-explicit-receipt-capped|promo=prospective-explicit-receipt-capped|unresolved=retain|law=existing-scoped-holds|late-credit=retain|audit=append-only
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

lock table private.account_cleanup_execution, private.account_lifecycle,
  private.account_cleanup_jobs, private.loyalty_action_receipts in access exclusive mode nowait;
do $$
begin
  if current_user<>'postgres' or private.loyalty_action_recovery_days()<>90
    or not private.account_cleanup_references_ready() then
    raise exception 'Reviewed 90-day, action-consent and retained financial prerequisites required';
  end if;
  if not exists(select 1 from private.account_cleanup_execution where singleton
    and not execution_enabled and not credit_forfeiture_enabled)
    or exists(select 1 from private.account_cleanup_jobs where external_operation is not null) then
    raise exception 'Stop cleanup and reconcile external operations before installing surrender';
  end if;
end $$;

alter table private.account_cleanup_execution
  add column surrender_policy_version text,
  add column surrender_policy_sha256 text,
  add column surrender_terms_enabled_at timestamptz,
  drop constraint account_cleanup_execution_credit_forfeiture_enabled_check,
  add constraint surrender_policy_pin_check check (
    (surrender_policy_version is null and surrender_policy_sha256 is null and surrender_terms_enabled_at is null
      and not credit_forfeiture_enabled)
    or (surrender_policy_version='2026-10-05.2' and surrender_policy_sha256 ~ '^[0-9a-f]{64}$'
      and surrender_policy_version is not null and surrender_policy_sha256 is not null
      and surrender_terms_enabled_at is not null));

-- Composer sets version/hash in the SAME transaction that publishes the final
-- immutable document. This server timestamp cannot retroactively qualify previews.
create function private.guard_surrender_policy_pin()
returns trigger language plpgsql security definer set search_path='' as $$
declare d jsonb;
begin
  if (new.surrender_policy_version,new.surrender_policy_sha256)
    is distinct from (old.surrender_policy_version,old.surrender_policy_sha256) then
    if old.execution_enabled or new.execution_enabled then
      raise exception 'Stop cleanup before changing surrender policy pin'; end if;
    if new.surrender_policy_version is null and new.surrender_policy_sha256 is null then
      new.surrender_terms_enabled_at:=null;
    else
      d:=public.get_loyalty_policy_descriptor();
      if d->>'required_version' is distinct from new.surrender_policy_version
        or d->>'policy_sha256' is distinct from new.surrender_policy_sha256
        or new.surrender_policy_version is distinct from '2026-10-05.2'
        or ((d->>'policy_text')::jsonb ? 'draft'
          and (d->>'policy_text')::jsonb->'draft' is distinct from 'false'::jsonb)
        or jsonb_typeof((d->>'policy_text')::jsonb #> '{action_acknowledgements,account_deletion}') is distinct from 'string'
        or length(btrim((d->>'policy_text')::jsonb #>> '{action_acknowledgements,account_deletion}')) not between 1 and 4000 then
        raise exception 'Published final surrender document and exact hash required'; end if;
      new.surrender_terms_enabled_at:=clock_timestamp();
    end if;
  elsif new.surrender_terms_enabled_at is distinct from old.surrender_terms_enabled_at then
    raise exception 'Surrender activation time is server managed';
  end if;
  return new;
end $$;
create trigger guard_surrender_policy_pin before update on private.account_cleanup_execution
  for each row execute function private.guard_surrender_policy_pin();

alter table private.loyalty_action_receipts
  add column surrender_requested_at timestamptz,
  add column surrender_ledger_id bigint,
  add constraint surrender_receipt_check check (
    (surrender_requested_at is null and surrender_ledger_id is null)
    or (channel='account_deletion' and surrender_requested_at is not null
      and surrender_ledger_id is not null and surrender_ledger_id>=0));
alter table private.account_retained_subjects add column surrender_context_id uuid
  references private.loyalty_action_receipts(context_id);

-- Extend the sole authorized insertion point, not the Owner/session/balance
-- guards. Old receipts stay NULL and no initial acceptance is upgraded.
do $capture$
declare definition text; original text := $old$insert into private.loyalty_action_receipts(context_id,wallet_account_id,channel,deletion_result)
    values(c.id,wallet,'account_deletion',result);$old$;
begin
  definition:=pg_get_functiondef('public.request_account_deletion_with_consent(uuid,boolean)'::regprocedure);
  if strpos(definition,original)=0 then raise exception 'Atomic deletion receipt prerequisite mismatch'; end if;
  execute replace(definition,original,$new$insert into private.loyalty_action_receipts
    (context_id,wallet_account_id,channel,deletion_result,surrender_requested_at,surrender_ledger_id)
    select c.id,wallet,'account_deletion',result,
      case when eligible then l.deletion_requested_at end,
      case when eligible then (select coalesce(max(id),0) from public.wallet_ledger_entries where wallet_account_id=wallet) end
    from private.account_lifecycle l cross join lateral (
      select c.recovery_days=90 and l.restored_at is null
        and l.restore_until=l.deletion_requested_at+interval '2160 hours'
        and (result->>'restore_until')::timestamptz=l.restore_until
        and exists(select 1 from private.account_cleanup_execution e where singleton
          and e.surrender_policy_version=c.policy->>'required_version'
          and e.surrender_policy_sha256=c.policy->>'policy_sha256'
          and c.created_at>=e.surrender_terms_enabled_at
          and l.deletion_requested_at>=e.surrender_terms_enabled_at) as eligible
    ) eligibility where l.user_id=c.subject_id;$new$);
end $capture$;

alter table public.wallet_ledger_entries
  add column surrender_context_id uuid references private.loyalty_action_receipts(context_id),
  add constraint surrender_ledger_context_unique unique(surrender_context_id),
  drop constraint wallet_ledger_entries_entry_type_check,
  add constraint wallet_ledger_entries_entry_type_check check(entry_type in
    ('legacy_balance','load_paid','load_bonus','redeem_paid','redeem_bonus','admin_adjustment',
     'legal_cash_redemption','stripe_refund','void','deletion_promo_cancellation','deletion_credit_surrender')),
  add constraint surrender_ledger_check check (
    (entry_type='deletion_credit_surrender' and surrender_context_id is not null
      and paid_amount_cents<=0 and promo_amount_cents<=0)
    or (entry_type<>'deletion_credit_surrender' and surrender_context_id is null));
create trigger surrender_ledger_immutable_update before update on public.wallet_ledger_entries
  for each row when (old.surrender_context_id is not null or new.surrender_context_id is not null)
  execute function private.reject_loyalty_action_change();
create trigger surrender_ledger_immutable_delete before delete on public.wallet_ledger_entries
  for each row when (old.surrender_context_id is not null)
  execute function private.reject_loyalty_action_change();

create function private.surrender_retired_account_credit(p_user uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
declare r private.loyalty_action_receipts; c private.loyalty_action_contexts;
  paid bigint; promo bigint; paid_debits bigint; promo_debits bigint; wallet uuid;
begin
  perform private.require_account_cleanup_policy('retention-voluntary-surrender-2026-10-05',
    '95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac');
  -- Caller already owns the cleanup subject/lifecycle locks. NOWAIT avoids a
  -- reversed lock order with an in-flight financial writer; the whole step retries.
  select id into wallet from public.wallet_accounts where user_id=p_user for no key update nowait;
  if wallet is null then return; end if;
  select receipt.* into r from private.account_retained_subjects s
    join private.loyalty_action_receipts receipt on receipt.context_id=s.surrender_context_id
    where s.user_id=p_user and s.retired_at is not null;
  if not found or r.wallet_account_id is distinct from wallet or r.surrender_requested_at is null
    or exists(select 1 from public.wallet_ledger_entries where surrender_context_id=r.context_id) then return; end if;
  if not exists(select 1 from private.account_cleanup_execution where singleton
    and execution_enabled and credit_forfeiture_enabled) then return; end if;
  select * into c from private.loyalty_action_contexts where id=r.context_id;
  if not exists(select 1 from private.account_lifecycle l where l.user_id=p_user
    and l.restored_at is null and l.deletion_requested_at=r.surrender_requested_at
    and l.restore_until=(r.deletion_result->>'restore_until')::timestamptz
    and l.restore_until<=clock_timestamp()
    and l.restore_until>=l.deletion_requested_at+interval '2160 hours') then return; end if;
  select coalesce(sum(paid_amount_cents),0),coalesce(sum(promo_amount_cents),0),
    coalesce(sum(greatest(-paid_amount_cents::bigint,0)) filter(where id>r.surrender_ledger_id),0),
    coalesce(sum(greatest(-promo_amount_cents::bigint,0)) filter(where id>r.surrender_ledger_id),0)
    into paid,promo,paid_debits,promo_debits from public.wallet_ledger_entries where wallet_account_id=wallet;
  paid:=greatest(0,least(paid,c.purchased_balance_cents::bigint-paid_debits));
  promo:=greatest(0,least(promo,c.promotional_balance_cents::bigint-promo_debits));
  -- Reuse concrete holds and unresolved financial state. There is no added
  -- per-request legal-approval workflow; an empty disposition waives nothing.
  if (paid>0 or promo>0 or exists(select 1 from private.account_retained_subjects
      where user_id=p_user and coalesce(reward_tracker,0)>0)) and (
    private.account_cleanup_held(p_user,'financial')
    or private.account_cleanup_held(p_user,'processor')
    or exists(select 1 from private.voluntary_topup_refunds where customer_id=p_user
      and status in ('requested','approved','unknown','pending'))
    or exists(select 1 from public.wallet_loads where user_id=p_user and status='pending')
    or exists(select 1 from public."Refunds" where user_id=p_user and status::text='pending')
    or exists(select 1 from public.cortina_vend_sessions where user_id=p_user
      and status not in ('started','refunded','voided'))
    or exists(select 1 from private.loyalty_action_contexts preview
      join private.loyalty_action_receipts receipt on receipt.context_id=preview.id
      left join private.loyalty_action_provider_references ref on ref.context_id=receipt.context_id
      where preview.subject_id=p_user and receipt.channel<>'account_deletion'
        and not exists(select 1 from public.wallet_loads load where load.user_id=p_user
          and load.status in ('succeeded','refunded','void')
          and ref.provider_reference in (load.stripe_payment_intent_id,load.stripe_checkout_session_id)))) then return; end if;
  -- A zero-valued disposition is deliberate: later credits must never be swept.
  insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
    paid_amount_cents,promo_amount_cents,surrender_context_id,note)
  values(wallet,'deletion_credit_surrender',-(paid+promo),-paid,-promo,r.context_id,
    'Voluntary deletion surrender; exact consent retained and unresolved claims protected');
  update private.account_retained_subjects set reward_tracker=0 where user_id=p_user;
end $$;

create or replace function private.cancel_account_promo_on_retirement()
returns trigger language plpgsql security definer set search_path='' as $$
declare wallet uuid; consent uuid;
begin
  select r.context_id into consent from private.loyalty_action_receipts r
    join private.loyalty_action_contexts c on c.id=r.context_id
    join private.account_lifecycle l on l.user_id=c.subject_id
      and l.deletion_requested_at=r.surrender_requested_at and l.restored_at is null
    where c.subject_id=new.user_id and r.channel='account_deletion'
      and (r.deletion_result->>'restore_until')::timestamptz=l.restore_until;
  if consent is not null then
    update private.account_retained_subjects set surrender_context_id=consent where user_id=new.user_id;
    perform private.surrender_retired_account_credit(new.user_id);
  end if;
  for wallet in select id from public.wallet_accounts where user_id=new.user_id order by id for no key update loop
    if consent is null then perform private.cancel_retired_account_promo(wallet); end if;
    update public.wallet_accounts set status='deleted',deleted_at=coalesce(deleted_at,new.retired_at),
      deleted_reason=case when consent is null then 'Final account deletion; paid credit retained'
        else 'Final account deletion; explicit surrender subject to protected claims' end,
      updated_at=clock_timestamp() where id=wallet;
  end loop;
  return new;
end $$;

-- Keep existing fences/OIDs/ACLs. New policy approvals are deliberately empty.
update private.account_cleanup_execution set approved_policy_version=null,
  approved_policy_sha256=null,final_policy_approved_at=null;
do $$
declare signature text; definition text; c record; changed integer:=0;
  old_version text:='retention-paid-credit-2026-10-05';
  new_version text:='retention-voluntary-surrender-2026-10-05';
  old_hash text:='0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04';
  new_hash text:='95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac';
begin
  for c in select conname,pg_get_constraintdef(oid) as definition from pg_constraint
    where conrelid='private.account_cleanup_execution'::regclass and contype='c'
      and strpos(pg_get_constraintdef(oid),old_version)>0 loop
    execute format('alter table private.account_cleanup_execution drop constraint %I, add constraint %I %s',
      c.conname,c.conname,replace(replace(c.definition,old_version,new_version),old_hash,new_hash));
    changed:=changed+1;
  end loop;
  if changed<>1 then raise exception 'Cleanup policy constraint prerequisite mismatch'; end if;
  foreach signature in array array['private.require_account_cleanup_policy(text,text)',
    'private.guard_account_cleanup_auth_delete()','private.prune_account_cleanup_retention()'] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    if strpos(definition,old_version)=0 or strpos(definition,old_hash)=0 then
      raise exception 'Cleanup policy prerequisite mismatch: %',signature; end if;
    definition:=replace(replace(definition,old_version,new_version),old_hash,new_hash);
    if signature='private.require_account_cleanup_policy(text,text)' then
      definition:=replace(definition,' and not credit_forfeiture_enabled','');
      definition:=replace(definition,'begin',
        'begin perform 1 from private.account_cleanup_execution where singleton for share;');
    elsif signature='private.guard_account_cleanup_auth_delete()' then
      definition:=replace(definition,'set reward_tracker=0,retired_at=clock_timestamp()',
        'set reward_tracker=case when exists(select 1 from private.loyalty_action_receipts r
          join private.loyalty_action_contexts c on c.id=r.context_id
          where c.subject_id=old.id and r.surrender_requested_at=j.deletion_requested_at)
          then reward else 0 end,retired_at=clock_timestamp()');
    elsif signature='private.prune_account_cleanup_retention()' then
      definition:=replace(definition,'perform private.expire_account_cleanup_metadata(subject);',
        'perform private.surrender_retired_account_credit(subject); perform private.expire_account_cleanup_metadata(subject);');
    end if;
    execute definition;
  end loop;
  definition:=pg_get_functiondef('private.cancel_retired_account_promo(uuid)'::regprocedure);
  definition:=replace(definition,'if promo>0 then',
    'if promo>0 and not exists(select 1 from private.account_retained_subjects where user_id=subject and surrender_context_id is not null) then');
  execute definition;
  definition:=pg_get_functiondef('private.capture_topup_refund_spend()'::regprocedure);
  definition:=replace(definition,'new.entry_type<>''deletion_promo_cancellation''',
    'new.entry_type not in (''deletion_promo_cancellation'',''deletion_credit_surrender'')');
  execute definition;
  definition:=pg_get_functiondef('private.expire_account_cleanup_metadata(uuid)'::regprocedure);
  definition:=replace(definition,'select * into j from private.account_cleanup_jobs',
    'if exists(select 1 from private.account_retained_subjects s where s.user_id=p_user
      and s.surrender_context_id is not null and not exists(select 1 from public.wallet_ledger_entries e
        where e.surrender_context_id=s.surrender_context_id)) then return; end if;
    select * into j from private.account_cleanup_jobs');
  execute definition;
end $$;

revoke all on function private.guard_surrender_policy_pin(),
  private.surrender_retired_account_credit(uuid)
  from public,anon,authenticated,service_role,supabase_auth_admin;
commit;
