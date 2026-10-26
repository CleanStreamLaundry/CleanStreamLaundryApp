-- SEPARATE APPROVAL REQUIRED. Unapplied reference protocol, not a cleanup run.
-- Projects existing referenced UUIDs only; no financial row/value is rewritten.
begin;

do $$ begin
  if current_user<>'postgres' then raise exception 'Reviewed postgres operator required'; end if;
end $$;

create function private.ensure_account_retained_subject()
returns trigger language plpgsql security definer set search_path='' as $$
declare column_name text; subject uuid;
begin
  foreach column_name in array tg_argv loop
    subject:=(to_jsonb(new)->>column_name)::uuid;
    if subject is null or exists(select 1 from private.account_retained_subjects where user_id=subject) then
      continue;
    end if;
    perform 1 from auth.users where id=subject for key share;
    if not found then raise exception 'Unknown financial subject' using errcode='23503'; end if;
    insert into private.account_retained_subjects(user_id) values(subject) on conflict do nothing;
  end loop;
  return new;
end $$;
revoke all on function private.ensure_account_retained_subject()
  from public,anon,authenticated,service_role,supabase_auth_admin;

-- Fixed scope. Add and validate each replacement BEFORE removing the old FK.
-- No deferrability, orphan allowance, financial cascade, or broad Auth rewrite.
do $$
declare r record; relation regclass; old_fk record; replacement text;
begin
  for r in select * from (values
    ('public','transactions','user_id','transactions_user_id_fkey','auth.users'),
    ('public','Refunds','user_id','Refunds_user_id_fkey1','public.profiles'),
    ('public','wallet_accounts','user_id','wallet_accounts_user_id_fkey','auth.users'),
    ('public','wallet_loads','user_id','wallet_loads_user_id_fkey','auth.users'),
    ('public','wallet_redemptions','user_id','wallet_redemptions_user_id_fkey','auth.users'),
    ('public','wallet_ledger_entries','created_by','wallet_ledger_entries_created_by_fkey','auth.users'),
    ('public','cortina_vend_sessions','user_id','cortina_vend_sessions_user_id_fkey','auth.users'),
    ('private','voluntary_topup_refunds','customer_id','voluntary_topup_refunds_customer_id_fkey','public.profiles'),
    ('private','voluntary_topup_refunds','reviewed_by','voluntary_topup_refunds_reviewed_by_fkey','public.profiles'),
    ('private','account_lifecycle','user_id','account_lifecycle_user_id_fkey','public.profiles'),
    ('private','customer_mfa_recovery','user_id','customer_mfa_recovery_user_id_fkey','public.profiles'),
    ('public','admin_invitations','invited_by','admin_invitations_invited_by_fkey','auth.users')
  ) as f(schema_name,table_name,column_name,constraint_name,parent_name) loop
    relation:=format('%I.%I',r.schema_name,r.table_name)::regclass;
    execute format('lock table %s in access exclusive mode',relation);
    select c.* into old_fk from pg_catalog.pg_constraint c
      where c.conrelid=relation and c.conname=r.constraint_name and c.contype='f';
    if not found or old_fk.confrelid<>r.parent_name::regclass or not old_fk.convalidated
      or old_fk.condeferrable or old_fk.conkey<>array[(select attnum from pg_catalog.pg_attribute
        where attrelid=relation and attname=r.column_name)]::smallint[] then
      raise exception 'Reference protocol prerequisite mismatch: %.%',r.table_name,r.column_name;
    end if;
    execute format('insert into private.account_retained_subjects(user_id)
      select distinct %I from %s where %I is not null on conflict do nothing',r.column_name,relation,r.column_name);
    replacement:=r.constraint_name||'_retained';
    execute format('alter table %s add constraint %I foreign key (%I)
      references private.account_retained_subjects(user_id) on update no action on delete no action',
      relation,replacement,r.column_name);
    execute format('alter table %s drop constraint %I',relation,r.constraint_name);
    execute format('alter table %s rename constraint %I to %I',relation,replacement,r.constraint_name);
    execute format('create trigger %I before insert or update of %I on %s
      for each row execute function private.ensure_account_retained_subject(%L)',
      'retained_subject_'||r.column_name,r.column_name,relation,r.column_name);
  end loop;
end $$;

-- Existing clients still submit their own nonnull subject. Only the cleanup
-- definer can detach resolved, unheld support rows; RLS/grants are unchanged.
-- The legacy primary key includes the requester. Preserve its uniqueness while
-- using the existing report ID as the non-personal row key. Keep the maint_id
-- unique constraint intact because existing support FKs depend on its index.
do $$
declare legacy_key name; expected_columns smallint[];
begin
  lock table public."Maintenance" in access exclusive mode;
  select array[
    (select attnum from pg_catalog.pg_attribute where attrelid='public."Maintenance"'::regclass and attname='user_id'),
    (select attnum from pg_catalog.pg_attribute where attrelid='public."Maintenance"'::regclass and attname='created_at')
  ]::smallint[] into expected_columns;
  select conname into legacy_key from pg_catalog.pg_constraint
    where conrelid='public."Maintenance"'::regclass and contype='p'
      and conkey=expected_columns and convalidated and not condeferrable;
  if legacy_key is null then
    raise exception 'Maintenance primary-key prerequisite mismatch';
  end if;
  alter table public."Maintenance" add constraint "Maintenance_user_created_key"
    unique(user_id,created_at);
  -- RESTRICT is intentional: an unreviewed dependent FK must roll back the batch.
  execute format('alter table public."Maintenance" drop constraint %I restrict',legacy_key);
  execute format('alter table public."Maintenance" add constraint %I primary key(maint_id)',legacy_key);
end $$;
alter table public."Maintenance" alter column user_id drop not null;

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
    select round(s.reward_tracker*100)::integer into reward_before_cents
      from private.account_retained_subjects s where s.user_id=target_user_id and s.retired_at is not null
      for no key update;
    if not found or reward_before_cents is null then raise exception 'Wallet load profile not found'; end if;
    retained:=true;
  end if;
  combined_cents:=reward_before_cents+amount_cents;
  bonus_count:=combined_cents/2000; bonus_cents:=bonus_count*500; remainder_cents:=combined_cents%2000;
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
    update private.account_retained_subjects set reward_tracker=remainder_cents::numeric/100 where user_id=target_user_id;
  else
    update public.profiles set reward_tracker=remainder_cents::numeric/100.0 where id=target_user_id;
  end if;
  perform public.sync_profile_wallet_balance(wallet_id);
  return wallet_id;
end $$;

create or replace function private.capture_topup_refund_provenance()
returns trigger language plpgsql security definer set search_path='' as $$
declare reward integer;
begin
  perform 1 from public.wallet_accounts where id=new.wallet_account_id for no key update;
  select round(reward_tracker*100)::integer into reward from public.profiles where id=new.user_id;
  if not found then select round(reward_tracker*100)::integer into reward
    from private.account_retained_subjects where user_id=new.user_id and retired_at is not null; end if;
  if reward between 0 and 1999 and new.status='succeeded'
    and new.paid_amount_cents=new.amount_cents
    and new.promo_amount_cents=((reward::bigint+new.amount_cents)/2000)*500 then
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
    select round(reward_tracker*100)::integer into reward from private.account_retained_subjects
      where user_id=r.customer_id and retired_at is not null for no key update nowait;
    retained:=true;
  end if;
  if reward is null or reward not between 0 and 1999 then
    raise exception 'reward_provenance_unavailable' using errcode='PT409'; end if;
  bonus:=((reward::bigint+r.principal_cents)/2000)*500;
  insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
    paid_amount_cents,promo_amount_cents,wallet_load_id,voluntary_topup_refund_id,note)
  values(r.wallet_id,'admin_adjustment',r.principal_cents+bonus,r.principal_cents,bonus,
    r.load_id,r.id,'Voluntary top-up refund reservation released');
  if retained then
    update private.account_retained_subjects set reward_tracker=((reward::bigint+r.principal_cents)%2000)::numeric/100
      where user_id=r.customer_id;
  else
    update public.profiles set reward_tracker=((reward::bigint+r.principal_cents)%2000)::numeric/100 where id=r.customer_id;
  end if;
  update private.voluntary_topup_refunds set released_at=clock_timestamp() where id=p_id;
  perform public.sync_profile_wallet_balance(r.wallet_id);
end $$;

-- CREATE OR REPLACE preserves all three existing ACLs; no human permission or
-- financial amount/status algorithm is changed. The public load stays service-only.
commit;
