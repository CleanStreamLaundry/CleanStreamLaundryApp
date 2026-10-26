-- Factual preparation for prospectively acknowledged, expired requests only.
-- No execution activation, provider calls, human-review claims or historic backfill.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

lock table private.account_cleanup_execution in share mode nowait;
do $$
begin
  if current_user<>'postgres' or private.loyalty_action_recovery_days()<>90
    or not private.account_cleanup_references_ready()
    or not exists(select 1 from private.account_cleanup_execution where singleton
      and not execution_enabled and not credit_forfeiture_enabled
      and surrender_policy_version='2026-10-05.2') then
    raise exception 'Stopped cleanup and published prospective-consent prerequisites required';
  end if;
end $$;

alter table private.account_cleanup_inventory add column preparation_facts jsonb
  check (preparation_facts is null or jsonb_typeof(preparation_facts)='object');

create function private.prepare_account_cleanup_inventory()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare subject uuid; requested timestamptz; custodian_id uuid; receipt uuid;
  deadline timestamptz; facts jsonb; captured timestamptz; inserted integer;
begin
  perform private.require_account_cleanup_policy('retention-voluntary-surrender-2026-10-05',
    '95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac');
  select l.user_id,l.deletion_requested_at into subject,requested
    from private.account_lifecycle l
    where l.restored_at is null and l.restore_until<=clock_timestamp()
      and exists(select 1 from auth.users where id=l.user_id)
      and exists(select 1 from public.profiles where id=l.user_id)
      and not exists(select 1 from private.account_cleanup_inventory i
        where i.user_id=l.user_id and i.requested_at=l.deletion_requested_at)
      and not exists(select 1 from private.account_cleanup_jobs j where j.user_id=l.user_id
        and (j.auth_removed_at is not null or j.external_operation is not null))
      and exists(select 1 from private.loyalty_action_receipts r
        join private.loyalty_action_contexts c on c.id=r.context_id
        where c.subject_id=l.user_id and c.action='account_deletion' and c.recovery_days=90
          and r.channel='account_deletion' and r.surrender_requested_at=l.deletion_requested_at
          and (r.deletion_result->>'restore_until')::timestamptz=l.restore_until)
    order by l.restore_until,l.user_id limit 1;
  if subject is null then return null; end if;

  -- Same Owner-change lock, before subject/Auth/wallet locks. It assigns an
  -- existing eligible custodian, not an invented review or a new role.
  if not pg_try_advisory_xact_lock(814716290) then
    return jsonb_build_object('status','held','reason','custodian_state_busy'); end if;
  select p.id into custodian_id from public.profiles p
    where p.roles::text='Owner' and p.id<>subject
      and private.owner_target_restriction(p.id) is null order by p.id limit 1;
  if custodian_id is null then
    return jsonb_build_object('status','held','reason','eligible_owner_custodian_unavailable'); end if;
  perform 1 from auth.users where id=custodian_id for share nowait;
  perform 1 from public.profiles where id=custodian_id and roles::text='Owner' for share nowait;
  if not found or private.owner_target_restriction(custodian_id) is not null then
    return jsonb_build_object('status','held','reason','custodian_state_changed'); end if;

  perform private.lock_account_cleanup_subject(subject);
  perform 1 from public.profiles where id=subject for no key update nowait;
  if not found then return jsonb_build_object('status','held','reason','request_changed'); end if;
  select restore_until into deadline from private.account_lifecycle
    where user_id=subject and deletion_requested_at=requested and restored_at is null for update;
  if not found or deadline>clock_timestamp() or deadline<requested+interval '2160 hours' then
    return jsonb_build_object('status','held','reason','request_changed'); end if;
  select r.context_id into receipt from private.loyalty_action_receipts r
    join private.loyalty_action_contexts c on c.id=r.context_id
    where c.subject_id=subject and c.action='account_deletion' and c.recovery_days=90
      and r.channel='account_deletion' and r.surrender_requested_at=requested
      and (r.deletion_result->>'restore_until')::timestamptz=deadline;
  if receipt is null or exists(select 1 from private.account_cleanup_jobs where user_id=subject
    and (auth_removed_at is not null or external_operation is not null)) then
    return jsonb_build_object('status','held','reason','request_changed'); end if;

  captured:=clock_timestamp();
  facts:=jsonb_build_object('source','database_snapshot','captured_at',captured,
    'consent_context_id',receipt,'requested_at',requested,'restore_until',deadline,
    'retention_policy','retention-voluntary-surrender-2026-10-05',
    'active_holds',(select count(*) from private.account_retention_holds where user_id=subject and released_at is null),
    'pending_refunds',(select count(*) from private.voluntary_topup_refunds where customer_id=subject
      and status in ('requested','approved','unknown','pending')),
    'pending_claims',(select count(*) from public."Refunds" where user_id=subject and status::text='pending'),
    'pending_loads',(select count(*) from public.wallet_loads where user_id=subject and status='pending'),
    'unresolved_vends',(select count(*) from public.cortina_vend_sessions where user_id=subject
      and status not in ('started','refunded','voided')),
    'unsettled_load_receipts',(select count(*) from private.loyalty_action_contexts c
      join private.loyalty_action_receipts r on r.context_id=c.id
      left join private.loyalty_action_provider_references ref on ref.context_id=r.context_id
      where c.subject_id=subject and r.channel<>'account_deletion'
        and not exists(select 1 from public.wallet_loads w where w.user_id=subject
          and w.status in ('succeeded','refunded','void')
          and ref.provider_reference in(w.stripe_payment_intent_id,w.stripe_checkout_session_id))),
    'media_objects',(select count(*) from storage.objects where owner_id=subject::text or owner=subject),
    'unsupported_media_objects',(select count(*) from storage.objects where (owner_id=subject::text or owner=subject)
      and (bucket_id is distinct from 'maintenance-images' or name is null or version is null
        or (owner_id is not null and owner_id<>subject::text))),
    'processor_erasure_verified',false,'backup_erasure_verified',false,
    'financial_records_retained',true);
  -- These are references to facts and approved disposition RULES, not receipts
  -- asserting a human review or completed processor/backup erasure. Existing
  -- executor/financial functions recheck live state, never trust this snapshot.
  insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
    hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
    backup_disposition_reference,financial_retention_reference,preparation_facts)
  values(subject,requested,custodian_id,captured,
    'db:account_retention_holds/user/'||subject,
    'policy:retention-voluntary-surrender-2026-10-05; Auth via fenced API; financial providers retained; erasure unverified',
    'db:storage.objects/owner/'||subject,
    'policy:retention-voluntary-surrender-2026-10-05; backup retention exceptions apply; erasure unverified',
    'db:account_retained_subjects/'||subject,facts)
  on conflict(user_id,requested_at) do nothing;
  get diagnostics inserted=row_count;
  return jsonb_build_object('status','progress','inventory_prepared',inserted=1);
exception when lock_not_available then
  return jsonb_build_object('status','held','reason','inventory_subject_busy');
end $$;
revoke all on function private.prepare_account_cleanup_inventory()
  from public,anon,authenticated,service_role,supabase_auth_admin;

-- One preparation per automatic worker step, then the unchanged selector,
-- request/hold/media fences, provider dispatch and outcome reconciliation.
do $hook$
declare definition text; marker text := '    select l.user_id,l.deletion_requested_at into subject,requested';
  idle text := $old$return result||jsonb_build_object('status',case when private.prune_account_cleanup_retention()
        then 'progress' else 'idle' end);$old$;
begin
  definition:=pg_get_functiondef('public.execute_account_cleanup_step(uuid,text,text,uuid,timestamptz)'::regprocedure);
  if strpos(definition,'operation_id uuid;')=0 or strpos(definition,marker)=0 or strpos(definition,idle)=0 then
    raise exception 'Reviewed cleanup worker hook prerequisite mismatch'; end if;
  definition:=replace(definition,'operation_id uuid;','operation_id uuid; inventory jsonb;');
  definition:=replace(definition,marker,'    inventory:=private.prepare_account_cleanup_inventory();'||chr(10)||marker);
  definition:=replace(definition,idle,$new$if private.prune_account_cleanup_retention() then
        return result||jsonb_build_object('status','progress');
      end if;
      return result||coalesce(inventory,jsonb_build_object('status','idle'));$new$);
  execute definition;
end $hook$;
commit;
