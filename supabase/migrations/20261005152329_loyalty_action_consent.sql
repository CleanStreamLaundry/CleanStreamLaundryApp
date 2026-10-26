-- Local-only action consent. No publication, cleanup activation or money writes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter table private.mail_outbox add column lifecycle_consent jsonb;
alter table private.mail_outbox add constraint mail_lifecycle_consent_check check (
  lifecycle_consent is null or (kind='account_deletion_scheduled'
    and jsonb_typeof(lifecycle_consent)='object'
    and lifecycle_consent ?& array['policy_version','acknowledgement','purchased_balance_cents','promotional_balance_cents']
    and jsonb_typeof(lifecycle_consent->'policy_version')='string'
    and jsonb_typeof(lifecycle_consent->'acknowledgement')='string'
    and jsonb_typeof(lifecycle_consent->'purchased_balance_cents')='number'
    and jsonb_typeof(lifecycle_consent->'promotional_balance_cents')='number'));
-- The installed worker RPC serializes the complete row, including this field.
-- Preserve its locks, leases, suppression checks and ACL instead of replacing it.
do $$
begin
  if strpos(pg_get_functiondef('public.mail_claim(boolean)'::regprocedure),'return to_jsonb(o)')=0 then
    raise exception 'Whole-row mail claim prerequisite required' using errcode='55000';
  end if;
end $$;

create table private.loyalty_action_contexts (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null,
  session_id uuid not null,
  action text not null check (action in ('wallet_load','account_deletion')),
  policy jsonb not null,
  acknowledgement text not null,
  purchased_balance_cents integer not null,
  promotional_balance_cents integer not null,
  recovery_days integer not null check (recovery_days in (30,90)),
  amount_cents integer check (amount_cents > 0),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp() + interval '10 minutes',
  check (action = 'wallet_load' or amount_cents is null)
);
create table private.loyalty_action_receipts (
  context_id uuid primary key references private.loyalty_action_contexts(id),
  wallet_account_id uuid,
  amount_cents integer,
  channel text not null check (channel in ('payment_intent','checkout','account_deletion')),
  accepted_at timestamptz not null default clock_timestamp(),
  deletion_result jsonb,
  check ((channel = 'account_deletion' and amount_cents is null and deletion_result is not null)
    or (channel <> 'account_deletion' and amount_cents > 0
      and wallet_account_id is not null and deletion_result is null))
);
create index loyalty_action_context_expiry on private.loyalty_action_contexts(expires_at);
create table private.loyalty_action_provider_references (
  context_id uuid primary key references private.loyalty_action_receipts(context_id),
  provider_reference text not null unique,
  recorded_at timestamptz not null default clock_timestamp()
);
alter table private.loyalty_action_contexts enable row level security;
alter table private.loyalty_action_receipts enable row level security;
alter table private.loyalty_action_provider_references enable row level security;
revoke all on private.loyalty_action_contexts, private.loyalty_action_receipts,
  private.loyalty_action_provider_references from public,anon,authenticated,service_role;

create function private.reject_loyalty_action_change()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' and tg_table_name='loyalty_action_contexts' then
    if old.expires_at<=clock_timestamp() and not exists(
      select 1 from private.loyalty_action_receipts where context_id=old.id) then
      return old;
    end if;
  end if;
  raise exception 'Action consent history is immutable' using errcode='23514';
end $$;
revoke all on function private.reject_loyalty_action_change() from public,anon,authenticated,service_role;
create trigger loyalty_action_context_immutable before update or delete on private.loyalty_action_contexts
  for each row execute function private.reject_loyalty_action_change();
create trigger loyalty_action_receipt_immutable before update or delete on private.loyalty_action_receipts
  for each row execute function private.reject_loyalty_action_change();
create trigger loyalty_action_provider_immutable before update or delete on private.loyalty_action_provider_references
  for each row execute function private.reject_loyalty_action_change();

-- Abandoned previews are not audit receipts. Bounded opportunistic pruning also
-- works while destructive account cleanup is held, without enabling that worker.
create function private.prune_unused_loyalty_action_contexts()
returns void language sql volatile security definer set search_path='' as $$
  delete from private.loyalty_action_contexts where id in (
    select preview.id from private.loyalty_action_contexts preview
    where preview.expires_at<=clock_timestamp() and not exists(
      select 1 from private.loyalty_action_receipts receipt where receipt.context_id=preview.id)
    order by preview.expires_at,preview.id limit 100 for update of preview skip locked
  );
$$;
revoke all on function private.prune_unused_loyalty_action_contexts()
  from public,anon,authenticated,service_role,supabase_auth_admin;

-- Freeze the installed request duration, without applying the separate candidate
-- recovery/publication migration or changing an existing deadline.
do $$
declare definition text; days integer;
begin
  definition := pg_get_functiondef('private.request_account_deletion()'::regprocedure);
  if strpos(definition, 'requested_at + interval ''2160 hours''') > 0 then days := 90;
  elsif strpos(definition, 'requested_at + interval ''720 hours''') > 0 then days := 30;
  else raise exception 'Reviewed recovery duration required' using errcode='55000'; end if;
  execute format('create function private.loyalty_action_recovery_days() returns integer
    language sql immutable set search_path='''' as %L', 'select ' || days);
end $$;
revoke all on function private.loyalty_action_recovery_days() from public,anon,authenticated,service_role;

create function public.get_loyalty_action_context(p_action text, p_amount_cents integer default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  c private.loyalty_action_contexts%rowtype;
  state jsonb; document jsonb; policy_version text; wallet uuid; acknowledgement text;
begin
  if p_action is null or p_action not in ('wallet_load','account_deletion')
    or p_amount_cents <= 0 or (p_action = 'account_deletion' and p_amount_cents is not null) then
    raise exception 'invalid_action_context' using errcode='22023';
  end if;
  select version into policy_version from public.loyalty_policy_documents where is_current for share;
  if not found then raise exception 'loyalty_policy_unavailable' using errcode='PT503'; end if;
  state := private.current_account_access();
  if state->>'lifecycle_identity_allowed' is distinct from 'true'
    or state->>'account_state' = 'pending_deletion' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  perform 1 from auth.users where id=auth.uid() for share;
  -- Wallet before profile, matching all financial writers. No wallet is created
  -- just to display a quote; an absent wallet is serialized by the profile lock.
  select id into wallet from public.wallet_accounts where user_id=auth.uid() for no key update;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  if not found then raise exception 'account_restricted' using errcode='PT403'; end if;
  if wallet is null and exists(select 1 from public.wallet_accounts where user_id=auth.uid()) then
    raise exception 'consent_context_stale' using errcode='PT409';
  end if;
  state := private.current_account_access();
  if state->>'lifecycle_identity_allowed' is distinct from 'true'
    or state->>'account_state' = 'pending_deletion' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  if p_action='wallet_load' and public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  c.policy := public.get_loyalty_policy_descriptor();
  if c.policy->>'required_version' is distinct from policy_version then
    raise exception 'consent_context_stale' using errcode='PT409';
  end if;
  document := (c.policy->>'policy_text')::jsonb;
  if document ? 'draft' and document->'draft' is distinct from 'false'::jsonb then
    raise exception 'loyalty_policy_unpublished' using errcode='PT503';
  end if;
  if document ? 'action_acknowledgements' then
    if jsonb_typeof(document->'action_acknowledgements') is distinct from 'object' then
      raise exception 'action_acknowledgement_unavailable' using errcode='PT503';
    end if;
    if (document->'action_acknowledgements') ? p_action then
      if jsonb_typeof(document->'action_acknowledgements'->p_action) is distinct from 'string' then
        raise exception 'action_acknowledgement_unavailable' using errcode='PT503';
      end if;
      -- Keep the exact published bytes; trimming would change the agreed wording.
      acknowledgement := document->'action_acknowledgements'->>p_action;
    end if;
  end if;
  if acknowledgement is null and p_action='wallet_load' then
    acknowledgement := 'I agree to the Loyalty Program Terms for this purchase.';
  elsif acknowledgement is null then
    -- Quote the published wording, not an unpublished surrender proposal.
    select string_agg(paragraph.value, E'\n\n' order by section.n, paragraph.n)
      into acknowledgement
      from jsonb_array_elements(document->'sections') with ordinality section(value,n)
      cross join lateral jsonb_array_elements_text(section.value->'paragraphs')
        with ordinality paragraph(value,n)
      where section.value->>'heading' like '%Account deletion%'
        or section.value->>'heading' like '%Promotional rewards%'
        or section.value->>'heading' like '%Purchased credit after deletion%';
    if acknowledgement is null then
      raise exception 'deletion_acknowledgement_unavailable' using errcode='PT503';
    end if;
    acknowledgement := 'I request account deletion and acknowledge the displayed purchased and promotional balances and these current terms:'
      || E'\n\n' || acknowledgement;
  end if;
  -- Match the renderer's trim() whitespace set, including nonbreaking spaces.
  if btrim(acknowledgement,U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF')=''
    or char_length(acknowledgement)>4000 then
    raise exception 'action_acknowledgement_unavailable' using errcode='PT503';
  end if;
  -- The mail renderer counts UTF-16 code units, not PostgreSQL code points.
  if char_length(acknowledgement) + (select count(*) from regexp_split_to_table(acknowledgement,'') glyph(character)
    where ascii(glyph.character)>65535) > 4000 then
    raise exception 'action_acknowledgement_unavailable' using errcode='PT503';
  end if;
  select coalesce(sum(paid_amount_cents),0)::integer, coalesce(sum(promo_amount_cents),0)::integer
    into c.purchased_balance_cents,c.promotional_balance_cents
    from public.wallet_ledger_entries where wallet_account_id=wallet;
  perform private.prune_unused_loyalty_action_contexts();
  insert into private.loyalty_action_contexts(subject_id,session_id,action,policy,acknowledgement,
    purchased_balance_cents,promotional_balance_cents,recovery_days,amount_cents)
    values(auth.uid(),(auth.jwt()->>'session_id')::uuid,p_action,c.policy,acknowledgement,
      c.purchased_balance_cents,c.promotional_balance_cents,private.loyalty_action_recovery_days(),p_amount_cents)
    returning * into c;
  return jsonb_build_object('context_id',c.id,'subject_id',c.subject_id,'action',c.action,
    'policy',c.policy,'acknowledgement',c.acknowledgement,
    'purchased_balance_cents',c.purchased_balance_cents,'promotional_balance_cents',c.promotional_balance_cents,
    'recovery_days',c.recovery_days,'restore_until',null,'amount_cents',c.amount_cents,'expires_at',c.expires_at);
end $$;
revoke all on function public.get_loyalty_action_context(text,integer) from public,anon,authenticated,service_role;
grant execute on function public.get_loyalty_action_context(text,integer) to authenticated;

-- Caller-bound RPC: Edge must use the captured user JWT, never a service JWT.
create function public.accept_wallet_load_consent(p_context_id uuid, p_acknowledged boolean,
  p_amount_cents integer, p_channel text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c private.loyalty_action_contexts%rowtype; r private.loyalty_action_receipts%rowtype;
  wallet uuid; policy_version text; reference text;
begin
  if p_acknowledged is distinct from true or p_amount_cents is null or p_amount_cents <= 0
    or p_channel is null or p_channel not in ('payment_intent','checkout') then
    raise exception 'consent_required' using errcode='PT409';
  end if;
  select version into policy_version from public.loyalty_policy_documents where is_current for share;
  if not found then raise exception 'loyalty_policy_unavailable' using errcode='PT503'; end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  wallet := public.get_or_create_wallet_account(auth.uid());
  perform 1 from public.profiles where id=auth.uid() for no key update;
  select * into c from private.loyalty_action_contexts where id=p_context_id for update;
  if not found or c.subject_id is distinct from auth.uid()
    or c.session_id is distinct from (auth.jwt()->>'session_id')::uuid or c.action <> 'wallet_load' then
    raise exception 'consent_context_invalid' using errcode='PT409';
  end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  perform private.require_new_payments_enabled();
  select * into r from private.loyalty_action_receipts where context_id=c.id;
  if found then
    if r.amount_cents is distinct from p_amount_cents or r.channel is distinct from p_channel
      or r.wallet_account_id is distinct from wallet then
      raise exception 'consent_replay_mismatch' using errcode='PT409';
    end if;
    select provider_reference into reference from private.loyalty_action_provider_references where context_id=c.id;
    -- Stripe can prune idempotency keys after 24h. Never create a second object
    -- for an unresolved old attempt; known references are retrieved, not created.
    if reference is null and clock_timestamp() >= r.accepted_at + interval '23 hours' then
      raise exception 'payment_reconciliation_required' using errcode='PT409';
    end if;
    if reference is null and c.policy is distinct from public.get_loyalty_policy_descriptor() then
      raise exception 'payment_reconciliation_required' using errcode='PT409';
    end if;
  else
    if clock_timestamp() >= c.expires_at
      or c.policy is distinct from public.get_loyalty_policy_descriptor()
      or c.policy->>'required_version' is distinct from policy_version
      or (c.amount_cents is not null and c.amount_cents <> p_amount_cents) then
      raise exception 'consent_context_stale' using errcode='PT409';
    end if;
    if exists(select 1 from public.wallet_accounts where id=wallet and status <> 'active') then
      raise exception 'account_restricted' using errcode='PT403';
    end if;
    insert into private.loyalty_action_receipts(context_id,wallet_account_id,amount_cents,channel)
      values(c.id,wallet,p_amount_cents,p_channel) returning * into r;
  end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  perform private.require_new_payments_enabled();
  return jsonb_build_object('context_id',c.id,'subject_id',c.subject_id,'wallet_account_id',wallet,
    'amount_cents',r.amount_cents,'channel',r.channel,'accepted_at',r.accepted_at,
    'policy_version',c.policy->>'required_version','policy_sha256',c.policy->>'policy_sha256',
    'provider_reference',reference);
end $$;
revoke all on function public.accept_wallet_load_consent(uuid,boolean,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.accept_wallet_load_consent(uuid,boolean,integer,text) to authenticated;

-- Completion is deliberately independent of current admission/policy: a late
-- Stripe response must retain its reference even after deletion or revocation.
create function public.bind_wallet_load_consent_provider(p_context_id uuid,p_subject_id uuid,
  p_amount_cents integer,p_channel text,p_provider_reference text)
returns void language plpgsql volatile security definer set search_path='' as $$
declare r private.loyalty_action_receipts%rowtype; reference text;
begin
  select * into r from private.loyalty_action_receipts where context_id=p_context_id for update;
  if not found or r.channel not in ('payment_intent','checkout')
    or r.amount_cents is distinct from p_amount_cents or r.channel is distinct from p_channel
    or not exists(select 1 from private.loyalty_action_contexts where id=p_context_id and subject_id=p_subject_id)
    or p_provider_reference is null
    or (p_channel='payment_intent' and p_provider_reference !~ '^pi_[A-Za-z0-9_]+$')
    or (p_channel='checkout' and p_provider_reference !~ '^cs_[A-Za-z0-9_]+$') then
    raise exception 'consent_provider_mismatch' using errcode='PT409';
  end if;
  insert into private.loyalty_action_provider_references(context_id,provider_reference)
    values(p_context_id,p_provider_reference) on conflict(context_id) do nothing;
  select provider_reference into reference from private.loyalty_action_provider_references where context_id=p_context_id;
  if reference is distinct from p_provider_reference then
    raise exception 'consent_provider_mismatch' using errcode='PT409';
  end if;
end $$;
revoke all on function public.bind_wallet_load_consent_provider(uuid,uuid,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.bind_wallet_load_consent_provider(uuid,uuid,integer,text,text) to service_role;

-- Retain the exact Owner guard and inner lifecycle implementation. Preserve the
-- source default closed ACL, or an explicitly enabled installation's permission.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.request_account_deletion()'::regprocedure);
  if strpos(definition,'private.require_other_owner(caller)')=0
    or strpos(definition,'private.request_account_deletion()')=0 then
    raise exception 'Owner-guarded deletion prerequisite required' using errcode='55000';
  end if;
  execute replace(definition,'public.request_account_deletion()',
    'private.request_account_deletion_with_owner_guard()');
end $$;
revoke all on function private.request_account_deletion_with_owner_guard() from public,anon,authenticated,service_role;

create function public.request_account_deletion_with_consent(p_context_id uuid,p_acknowledged boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c private.loyalty_action_contexts%rowtype; r private.loyalty_action_receipts%rowtype;
  state jsonb; result jsonb; wallet uuid; paid integer; promo integer; policy_version text;
begin
  if p_acknowledged is distinct from true then
    raise exception 'consent_required' using errcode='PT409';
  end if;
  select version into policy_version from public.loyalty_policy_documents where is_current for share;
  if not found then raise exception 'loyalty_policy_unavailable' using errcode='PT503'; end if;
  state := private.current_account_access();
  perform pg_advisory_xact_lock(814716290);
  perform 1 from auth.users where id=auth.uid() for share;
  select id into wallet from public.wallet_accounts where user_id=auth.uid() for no key update;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  if wallet is null and exists(select 1 from public.wallet_accounts where user_id=auth.uid()) then
    raise exception 'consent_context_stale' using errcode='PT409';
  end if;
  select * into c from private.loyalty_action_contexts where id=p_context_id for update;
  if not found or c.subject_id is distinct from auth.uid()
    or c.session_id is distinct from (auth.jwt()->>'session_id')::uuid or c.action <> 'account_deletion' then
    raise exception 'consent_context_invalid' using errcode='PT409';
  end if;
  state := private.current_account_access();
  if state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  select * into r from private.loyalty_action_receipts where context_id=c.id;
  if found then
    if r.channel <> 'account_deletion' or state->>'account_state' <> 'pending_deletion'
      or state->>'restore_until' is distinct from r.deletion_result->>'restore_until' then
      raise exception 'consent_replay_mismatch' using errcode='PT409';
    end if;
    return r.deletion_result;
  end if;
  if state->>'account_state'='pending_deletion' then
    raise exception 'consent_context_stale' using errcode='PT409';
  end if;
  select coalesce(sum(paid_amount_cents),0)::integer,coalesce(sum(promo_amount_cents),0)::integer
    into paid,promo from public.wallet_ledger_entries where wallet_account_id=wallet;
  if clock_timestamp() >= c.expires_at or c.policy is distinct from public.get_loyalty_policy_descriptor()
    or c.policy->>'required_version' is distinct from policy_version
    or paid is distinct from c.purchased_balance_cents or promo is distinct from c.promotional_balance_cents then
    raise exception 'consent_context_stale' using errcode='PT409';
  end if;
  result := private.request_account_deletion_with_owner_guard();
  -- Validate after lifecycle/mail triggers and their waits. The old request,
  -- acknowledgement and downstream notices all roll back on a late revocation.
  state := private.current_account_access();
  if state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  if clock_timestamp() >= c.expires_at then
    raise exception 'consent_context_stale' using errcode='PT409';
  end if;
  insert into private.loyalty_action_receipts(context_id,wallet_account_id,channel,deletion_result)
    values(c.id,wallet,'account_deletion',result);
  update private.mail_outbox o set lifecycle_consent=jsonb_build_object(
    'policy_version',c.policy->>'required_version','acknowledgement',c.acknowledgement,
    'purchased_balance_cents',c.purchased_balance_cents,'promotional_balance_cents',c.promotional_balance_cents)
    from private.account_lifecycle l
    where l.user_id=c.subject_id and o.user_id=l.user_id and o.kind='account_deletion_scheduled'
      and o.lifecycle_requested_at=l.deletion_requested_at and o.lifecycle_restore_until=l.restore_until
      and o.state='ready' and o.first_attempt_at is null and o.lifecycle_consent is null;
  state := private.current_account_access();
  if state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode='PT403';
  end if;
  return result;
end $$;
revoke all on function public.request_account_deletion_with_consent(uuid,boolean) from public,anon,authenticated,service_role;
do $$
begin
  if has_function_privilege('authenticated','public.request_account_deletion()','execute') then
    grant execute on function public.request_account_deletion_with_consent(uuid,boolean) to authenticated;
  end if;
end $$;
-- CREATE OR REPLACE preserves the original ACL and OID. Old clients must upgrade;
-- neither a prior policy acceptance nor a forged GUC authorizes deletion.
create or replace function public.request_account_deletion()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin raise exception 'consent_required' using errcode='PT409'; end $$;

-- Supabase project default privileges can include the Auth service owner.
revoke all on private.loyalty_action_contexts,private.loyalty_action_receipts,
  private.loyalty_action_provider_references from supabase_auth_admin;
revoke all on function private.reject_loyalty_action_change(),private.loyalty_action_recovery_days(),
  public.get_loyalty_action_context(text,integer),public.accept_wallet_load_consent(uuid,boolean,integer,text),
  public.bind_wallet_load_consent_provider(uuid,uuid,integer,text,text),
  private.request_account_deletion_with_owner_guard(),public.request_account_deletion_with_consent(uuid,boolean)
  from supabase_auth_admin;

commit;
