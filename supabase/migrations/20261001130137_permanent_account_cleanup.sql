-- Draft implementation only. No execution, credit forfeiture or historical DML.
begin;

do $$ begin
  if current_user<>'postgres' then raise exception 'Reviewed postgres operator required'; end if;
  if to_regclass('private.account_cleanup_jobs') is null
    or to_regprocedure('public.claim_account_cleanup(uuid,timestamptz,uuid)') is null
    or to_regprocedure('public.retry_account_cleanup(uuid,timestamptz,uuid,text)') is null
    or to_regprocedure('public.restore_account()') is null
    or to_regclass('public.wallet_accounts') is null
    or to_regclass('private.push_installations') is null then
    raise exception 'Reviewed cleanup, recovery, financial and push prerequisites required';
  end if;
end $$;

create table private.account_cleanup_execution (
  singleton boolean primary key default true check (singleton),
  execution_enabled boolean not null default false,
  approved_policy_version text,
  approved_policy_sha256 text,
  final_policy_approved_at timestamptz,
  closed_attachment_inventory_reference text,
  closed_attachment_inventory_at timestamptz,
  closed_attachment_custodian uuid,
  credit_forfeiture_enabled boolean not null default false check (not credit_forfeiture_enabled),
  check (not execution_enabled or (
    approved_policy_version = 'retention-draft-2026-10-01'
    and approved_policy_sha256 = '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be'
    and approved_policy_version is not null and approved_policy_sha256 is not null
    and final_policy_approved_at is not null
  ))
);
insert into private.account_cleanup_execution default values;
alter table private.account_cleanup_execution enable row level security;
revoke all on private.account_cleanup_execution
  from public, anon, authenticated, service_role, supabase_auth_admin;

-- This key is not a replacement account: no credentials, name, address or
-- contact snapshot. The separate reference migration installs validated FKs.
create table private.account_retained_subjects (
  user_id uuid primary key,
  reward_tracker numeric,
  retired_at timestamptz,
  financial_retention_reference text,
  check (reward_tracker is null or reward_tracker between 0 and 19.99)
);
create table private.account_retention_holds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  data_class text not null check (data_class in
    ('identity','financial','support','media','mail','newsletter','security','processor','cleanup')),
  record_key text,
  authority text not null check (length(btrim(authority)) between 1 and 200),
  purpose text not null check (length(btrim(purpose)) between 1 and 200),
  custodian uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  review_at timestamptz not null,
  released_at timestamptz,
  released_by uuid,
  release_reference text,
  check (record_key is null or length(record_key) between 1 and 200),
  check (review_at > created_at),
  check ((released_at is null and released_by is null and release_reference is null)
    or (released_at is not null and released_at >= created_at and released_by is not null and release_reference is not null
      and length(btrim(release_reference)) between 1 and 200))
);
create index account_retention_holds_active on private.account_retention_holds(user_id,data_class)
  where released_at is null;

-- An inventory is evidence that the responsible operator has classified this
-- exact request, NOT an inference that no holds exist. Never seeded by install.
-- References identify external records; never put contact/credential payloads here.
create table private.account_cleanup_inventory (
  user_id uuid not null,
  requested_at timestamptz not null,
  custodian uuid not null,
  recorded_at timestamptz not null,
  hold_inventory_reference text not null,
  processor_disposition_reference text not null,
  media_inventory_reference text not null,
  backup_disposition_reference text not null,
  financial_retention_reference text not null,
  primary key(user_id,requested_at),
  check (recorded_at >= requested_at),
  check (length(btrim(hold_inventory_reference)) between 1 and 200),
  check (length(btrim(processor_disposition_reference)) between 1 and 200),
  check (length(btrim(media_inventory_reference)) between 1 and 200),
  check (length(btrim(backup_disposition_reference)) between 1 and 200),
  check (length(btrim(financial_retention_reference)) between 1 and 200)
);
alter table private.account_retained_subjects enable row level security;
alter table private.account_retention_holds enable row level security;
alter table private.account_cleanup_inventory enable row level security;
revoke all on private.account_retained_subjects, private.account_retention_holds,
  private.account_cleanup_inventory from public,anon,authenticated,service_role,supabase_auth_admin;

alter table private.account_cleanup_jobs
  add column disposition_requested_at timestamptz,
  add column local_disposed_at timestamptz,
  add column auth_removed_at timestamptz,
  add column external_operation jsonb,
  add column next_disposition_at timestamptz,
  add column redaction_xid xid8,
  add column last_retention_at timestamptz,
  add column disposition_policy_version text,
  add column disposition_policy_sha256 text,
  add column retention_reasons text[] not null default '{}',
  add column metadata_compacted_at timestamptz;

-- Only completed, twelve-month-old jobs can become this minimal class link.
-- Live claims retain their original required fields, five attempts and tokens.
alter table private.account_cleanup_jobs
  alter column claim_id drop not null, alter column attempts drop not null,
  alter column used_claim_ids drop not null, alter column lease_until drop not null,
  alter column retry_after drop not null,
  drop constraint account_cleanup_jobs_state_check,
  add constraint account_cleanup_jobs_state_check check (state in ('leased','retry','outcome_unknown','retention_only')),
  add constraint account_cleanup_job_shape check (case when state='retention_only' then
    auth_removed_at is not null and metadata_compacted_at is not null
    and cardinality(retention_reasons)>0 and retention_reasons <@ array['support','newsletter','mail','security']::text[]
    and claim_id is null and attempts is null and used_claim_ids is null
    and lease_until is null and retry_after is null and external_operation is null
    and disposition_requested_at is null and local_disposed_at is null and next_disposition_at is null
    and disposition_policy_version is null and disposition_policy_sha256 is null
  else claim_id is not null and attempts is not null and used_claim_ids is not null
    and lease_until is not null and retry_after is not null
    and metadata_compacted_at is null and cardinality(retention_reasons)=0 end);

-- This mapping expires with the retained support summary, not with Auth.
-- It is required to honor a record/class hold after requester PII is detached.
create table private.account_support_retention (
  maint_id bigint primary key references public."Maintenance"(maint_id),
  user_id uuid not null,
  requested_at timestamptz,
  closed_at timestamptz,
  redacted_at timestamptz,
  attachment_claim_id uuid,
  attachment_operation_id uuid,
  attachment_closed_at timestamptz,
  attachment_lease_until timestamptz,
  attachment_outcome text not null default 'ready' check (attachment_outcome in ('ready','dispatched','outcome_unknown','removed')),
  attachment_object jsonb,
  attachment_attempts integer not null default 0 check (attachment_attempts between 0 and 5),
  attachment_removed_at timestamptz
);
alter table private.account_support_retention enable row level security;
revoke all on private.account_support_retention from public,anon,authenticated,service_role,supabase_auth_admin;
create function private.capture_cleanup_support_closure()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status is distinct from old.status then
    if new.status='resolved' and new.user_id is not null and new.attachment_ref is not null then
      insert into private.account_support_retention(maint_id,user_id,closed_at)
        values(new.maint_id,new.user_id,clock_timestamp()) on conflict(maint_id) do nothing;
    end if;
    update private.account_support_retention set closed_at=case when new.status='resolved' then clock_timestamp() end,
      attachment_outcome=case when attachment_outcome in ('dispatched','outcome_unknown') or new.attachment_ref is null
        then attachment_outcome else 'ready' end,
      attachment_attempts=case when attachment_outcome in ('dispatched','outcome_unknown') or new.attachment_ref is null
        then attachment_attempts else 0 end
      where maint_id=new.maint_id;
  end if;
  return new;
end $$;
create trigger cleanup_support_closure after update of status on public."Maintenance"
  for each row execute function private.capture_cleanup_support_closure();
revoke all on function private.capture_cleanup_support_closure()
  from public,anon,authenticated,service_role,supabase_auth_admin;

create function private.account_cleanup_held(p_user uuid,p_class text,p_record text default null)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.account_retention_holds h
    where h.user_id=p_user and h.data_class=p_class and h.released_at is null
      and (h.record_key is null or p_record is null or h.record_key=p_record));
$$;
revoke all on function private.account_cleanup_held(uuid,text,text)
  from public,anon,authenticated,service_role,supabase_auth_admin;

create function private.lock_account_retention_metadata()
returns trigger language plpgsql security definer set search_path='' as $$
declare subject uuid:=coalesce(new.user_id,old.user_id);
begin
  if tg_op='DELETE' then
    if tg_table_name='account_cleanup_inventory' then
      if exists(select 1 from private.account_cleanup_jobs j where j.user_id=old.user_id
        and j.deletion_requested_at=old.requested_at and j.redaction_xid=pg_current_xact_id()
        and j.auth_removed_at<=clock_timestamp()-interval '12 months' and j.external_operation is null
        and j.state<>'outcome_unknown') and not private.account_cleanup_held(old.user_id,'cleanup') then
        return old;
      end if;
    end if;
    raise exception 'Retain hold/inventory evidence; release explicitly';
  end if;
  if tg_op='UPDATE' and new.user_id is distinct from old.user_id then
    raise exception 'Retention subject is immutable'; end if;
  if tg_table_name='account_retention_holds' and tg_op='UPDATE' then
    if (to_jsonb(new)-array['review_at','released_at','released_by','release_reference'])
      is distinct from (to_jsonb(old)-array['review_at','released_at','released_by','release_reference'])
      or (old.released_at is not null and to_jsonb(new) is distinct from to_jsonb(old)) then
      raise exception 'Hold scope/authority and released evidence are immutable'; end if;
  end if;
  -- Serializes a late identity hold with the Auth DELETE transaction. No hold
  -- expires merely because its review date passed.
  perform private.lock_account_cleanup_subject(subject);
  perform 1 from public.profiles where id=subject for no key update;
  perform 1 from private.account_lifecycle where user_id=subject for update;
  perform 1 from private.account_cleanup_jobs where user_id=subject for update;
  perform 1 from private.account_retained_subjects where user_id=subject for update;
  if tg_table_name='account_retention_holds' then
    if new.data_class='identity'
      and exists(select 1 from private.account_retained_subjects where user_id=subject and retired_at is not null)
      and not exists(select 1 from auth.users where id=subject) then
      raise exception 'Identity removal already committed; record the remaining scoped incident evidence';
    end if;
  end if;
  update private.account_cleanup_jobs set
    next_disposition_at=case when auth_removed_at is null then clock_timestamp() end,
    last_retention_at=case when auth_removed_at is not null then null else last_retention_at end
    where user_id=subject;
  return new;
end $$;
create trigger account_retention_hold_lock before insert or update or delete
  on private.account_retention_holds for each row execute function private.lock_account_retention_metadata();
create trigger account_cleanup_inventory_lock before insert or update or delete
  on private.account_cleanup_inventory for each row execute function private.lock_account_retention_metadata();
revoke all on function private.lock_account_retention_metadata()
  from public,anon,authenticated,service_role,supabase_auth_admin;

create function private.reset_account_cleanup_disposition()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.deletion_requested_at is distinct from old.deletion_requested_at then
    new.disposition_requested_at:=null; new.local_disposed_at:=null;
    new.auth_removed_at:=null; new.external_operation:=null;
    new.next_disposition_at:=null; new.redaction_xid:=null; new.last_retention_at:=null;
    new.disposition_policy_version:=null; new.disposition_policy_sha256:=null;
    new.retention_reasons:='{}'; new.metadata_compacted_at:=null;
  end if;
  return new;
end $$;
create trigger account_cleanup_request_reset before update on private.account_cleanup_jobs
  for each row execute function private.reset_account_cleanup_disposition();
revoke all on function private.reset_account_cleanup_disposition()
  from public,anon,authenticated,service_role,supabase_auth_admin;

create function private.require_account_cleanup_policy(p_version text, p_sha256 text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_version is distinct from 'retention-draft-2026-10-01'
    or p_sha256 is distinct from '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be'
    or not exists (select 1 from private.account_cleanup_execution
      where singleton and execution_enabled and not credit_forfeiture_enabled
        and approved_policy_version = p_version and approved_policy_sha256 = p_sha256
        and final_policy_approved_at <= clock_timestamp()) then
    raise exception 'cleanup_policy_unapproved' using errcode = 'PT503';
  end if;
end $$;
revoke all on function private.require_account_cleanup_policy(text,text)
  from public, anon, authenticated, service_role, supabase_auth_admin;

-- Settlement owns wallet before profile. Never add wallet waits after the old
-- claim's profile lock. Auth SHARE remains first, matching human financial RPCs.
create function private.lock_account_cleanup_subject(p_user_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform 1 from auth.users where id = p_user_id for share;
  perform 1 from public.wallet_accounts where user_id = p_user_id
    order by id for no key update;
end $$;
revoke all on function private.lock_account_cleanup_subject(uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;

-- Keep the reviewed request/deadline/lease bodies intact and reuse their exact
-- retry budget, claim-ID replay fence and parked unknown-outcome semantics.
alter function public.claim_account_cleanup(uuid,timestamptz,uuid) set schema private;
alter function public.retry_account_cleanup(uuid,timestamptz,uuid,text) set schema private;
revoke all on function private.claim_account_cleanup(uuid,timestamptz,uuid),
  private.retry_account_cleanup(uuid,timestamptz,uuid,text)
  from public, anon, authenticated, service_role, supabase_auth_admin;

create function public.claim_account_cleanup(p_user_id uuid, p_requested_at timestamptz, p_claim_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.lock_account_cleanup_subject(p_user_id);
  if exists(select 1 from private.account_cleanup_jobs where user_id=p_user_id and auth_removed_at is not null) then
    return jsonb_build_object('claimed',false,'reason','account_removed','execution_enabled',false); end if;
  return private.claim_account_cleanup(p_user_id,p_requested_at,p_claim_id);
end $$;

create function public.retry_account_cleanup(p_user_id uuid, p_requested_at timestamptz,
  p_claim_id uuid, p_failure text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.lock_account_cleanup_subject(p_user_id);
  return private.retry_account_cleanup(p_user_id,p_requested_at,p_claim_id,p_failure);
end $$;
revoke all on function public.claim_account_cleanup(uuid,timestamptz,uuid),
  public.retry_account_cleanup(uuid,timestamptz,uuid,text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.claim_account_cleanup(uuid,timestamptz,uuid),
  public.retry_account_cleanup(uuid,timestamptz,uuid,text) to service_role;

create or replace function public.preview_account_cleanup(p_limit integer default 25,p_after_user_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare result jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'invalid_limit' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('user_id',x.user_id,
    'deletion_requested_at',x.deletion_requested_at,'restore_until',x.restore_until,
    'blocker',x.blocker,'eligible_to_claim',x.blocker is null) order by x.user_id),'[]'::jsonb)
    into result from (
      select l.user_id,l.deletion_requested_at,l.restore_until,
        case when c.state='outcome_unknown' then 'outcome_unknown'
          when c.state='leased' and c.lease_until>clock_timestamp() then 'lease_active'
          when c.attempts>=5 then 'retry_exhausted'
          when c.retry_after>clock_timestamp() then 'retry_wait' end as blocker
      from private.account_lifecycle l left join private.account_cleanup_jobs c
        on c.user_id=l.user_id and c.deletion_requested_at=l.deletion_requested_at
      where l.restored_at is null and l.restore_until<=clock_timestamp() and c.auth_removed_at is null
        and (p_after_user_id is null or l.user_id>p_after_user_id)
      order by l.user_id limit p_limit
    ) x;
  return jsonb_build_object('execution_enabled',false,'candidates',result,
    'next_cursor',case when jsonb_array_length(result)=p_limit then result->(p_limit-1)->>'user_id' else null end);
end $$;

create function private.require_account_cleanup_request(p_user uuid,p_requested timestamptz,p_claim uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
begin
  perform private.lock_account_cleanup_subject(p_user);
  perform 1 from public.profiles where id=p_user for no key update;
  perform 1 from private.account_lifecycle where user_id=p_user for update;
  perform 1 from private.account_cleanup_jobs where user_id=p_user for update;
  perform 1 from private.account_retained_subjects where user_id=p_user for no key update;
  if not exists(select 1 from private.account_lifecycle l join private.account_cleanup_jobs j using(user_id)
    where l.user_id=p_user and l.deletion_requested_at=p_requested and l.restored_at is null
      and l.restore_until<=clock_timestamp() and j.deletion_requested_at=p_requested
      and j.claim_id=p_claim and j.state='leased' and j.lease_until>clock_timestamp()) then
    raise exception 'cleanup_request_changed' using errcode='PT409';
  end if;
end $$;
revoke all on function private.require_account_cleanup_request(uuid,timestamptz,uuid)
  from public,anon,authenticated,service_role,supabase_auth_admin;

create function private.account_cleanup_note_redaction(p_report text)
returns boolean language sql volatile security definer set search_path='' as $$
  select exists(select 1 from public."Maintenance" m
    join private.account_support_retention s on s.maint_id=m.maint_id
    join private.account_cleanup_jobs j on j.user_id=s.user_id
    join private.account_lifecycle l on l.user_id=j.user_id
    where m.maint_id::text=p_report and m.status='resolved'
      and j.redaction_xid=pg_current_xact_id()
      and (j.auth_removed_at is not null or (j.state='leased' and j.lease_until>clock_timestamp()))
      and j.deletion_requested_at=l.deletion_requested_at and s.requested_at=l.deletion_requested_at
      and (j.disposition_requested_at=l.deletion_requested_at or j.state='retention_only')
      and l.restored_at is null and l.restore_until<=clock_timestamp()
      and not private.account_cleanup_held(j.user_id,'support',p_report));
$$;
revoke all on function private.account_cleanup_note_redaction(text)
  from public,anon,authenticated,service_role,supabase_auth_admin;

create or replace function private.portal_audit_immutable() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_table_name='admin_maintenance_history' then
    if tg_op='UPDATE' then
      if current_user='postgres' and new.note is null and (to_jsonb(old)-'note')=(to_jsonb(new)-'note')
        and private.account_cleanup_note_redaction(old.maintenance_id) then return new; end if;
      if old.actor_id is not null and new.actor_id is null
        and (to_jsonb(old)-'actor_id')=(to_jsonb(new)-'actor_id')
        and not exists(select 1 from auth.users where id=old.actor_id) then return new; end if;
    elsif tg_op='DELETE' and current_user='postgres' then
      if private.account_cleanup_note_redaction(old.maintenance_id)
        and exists(select 1 from private.account_support_retention where maint_id::text=old.maintenance_id
          and closed_at<=clock_timestamp()-interval '12 months' and redacted_at is not null) then return old; end if;
    end if;
  end if;
  raise exception 'Audit history cannot be edited or deleted';
end $$;

-- Start clocks prospectively. Never guess terminal delivery from creation time.
alter table private.mail_outbox add column terminal_at timestamptz;
alter table private.newsletter_consent add column retention_clock_started_at timestamptz,
  add column retention_last_use_at timestamptz;
-- Defaults affect FUTURE inserts only; historical rows remain explicitly unknown.
alter table private.newsletter_consent alter column retention_clock_started_at set default clock_timestamp();
create function private.capture_cleanup_mail_terminal()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.state in ('delivered','failed','suppressed') then
    if tg_op='INSERT' or new.state is distinct from old.state then new.terminal_at:=clock_timestamp(); end if;
  else new.terminal_at:=null; end if;
  if new.kind in ('newsletter_confirm','newsletter_welcome') and new.state='sending' then
    update private.newsletter_consent set retention_last_use_at=clock_timestamp() where id=new.consent_id;
  end if;
  return new;
end $$;
create trigger cleanup_mail_terminal before insert or update of state on private.mail_outbox
  for each row execute function private.capture_cleanup_mail_terminal();
revoke all on function private.capture_cleanup_mail_terminal()
  from public,anon,authenticated,service_role,supabase_auth_admin;

create function private.account_cleanup_references_ready()
returns boolean language sql stable security definer set search_path='' as $$
  select count(*)=12 from (values
    ('public.transactions','user_id','transactions_user_id_fkey'),
    ('public."Refunds"','user_id','Refunds_user_id_fkey1'),
    ('public.wallet_accounts','user_id','wallet_accounts_user_id_fkey'),
    ('public.wallet_loads','user_id','wallet_loads_user_id_fkey'),
    ('public.wallet_redemptions','user_id','wallet_redemptions_user_id_fkey'),
    ('public.wallet_ledger_entries','created_by','wallet_ledger_entries_created_by_fkey'),
    ('public.cortina_vend_sessions','user_id','cortina_vend_sessions_user_id_fkey'),
    ('private.voluntary_topup_refunds','customer_id','voluntary_topup_refunds_customer_id_fkey'),
    ('private.voluntary_topup_refunds','reviewed_by','voluntary_topup_refunds_reviewed_by_fkey'),
    ('private.account_lifecycle','user_id','account_lifecycle_user_id_fkey'),
    ('private.customer_mfa_recovery','user_id','customer_mfa_recovery_user_id_fkey'),
    ('public.admin_invitations','invited_by','admin_invitations_invited_by_fkey')
  ) required(relation,column_name,constraint_name)
  join pg_catalog.pg_constraint c on c.conrelid=required.relation::regclass
    and c.conname=required.constraint_name
  join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attname=required.column_name
  where c.contype='f' and c.convalidated and not c.condeferrable
    and c.confrelid='private.account_retained_subjects'::regclass
    and c.confdeltype='a' and c.confupdtype='a' and c.conkey=array[a.attnum]::smallint[]
    and c.confkey=array[(select attnum from pg_catalog.pg_attribute
      where attrelid=c.confrelid and attname='user_id')]::smallint[];
$$;
revoke all on function private.account_cleanup_references_ready()
  from public,anon,authenticated,service_role,supabase_auth_admin;

-- Independent of D/E: an active customer's closed case can reach ninety days
-- first. The existing support row holds one exact-version operation, not a fake
-- deletion request. Unknown outcomes are inspected, never redispatched.
create function public.claim_closed_attachment_cleanup(p_claim_id uuid,p_policy_version text,p_policy_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare candidate record; m public."Maintenance"; s private.account_support_retention;
  closed timestamptz; object_ref jsonb; result jsonb; operation uuid; expiring boolean:=false;
begin
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  if p_claim_id is null then raise exception 'invalid_request' using errcode='22023'; end if;
  result:=jsonb_build_object('policy_version',p_policy_version,'policy_sha256',p_policy_sha256,'purge_complete',false);
  select maint_id,user_id into candidate from private.account_support_retention
    where attachment_outcome in ('dispatched','outcome_unknown')
      and attachment_lease_until<=clock_timestamp()
    order by attachment_lease_until,maint_id limit 1;
  if not found then
    select report.maint_id,report.user_id into candidate from public."Maintenance" report
      left join private.account_support_retention retention using(maint_id)
      left join lateral (select h.created_at from public.admin_maintenance_history h
        where h.maintenance_id=report.maint_id::text and h.from_status<>'resolved' and h.to_status='resolved'
          and not exists(select 1 from public.admin_maintenance_history later
            where later.maintenance_id=h.maintenance_id and later.to_status<>'resolved'
              and (later.created_at,later.id)>(h.created_at,h.id))
        order by h.created_at desc,h.id desc limit 1) history on true
      where report.status='resolved' and report.user_id is not null and report.attachment_ref is not null
        and (retention.maint_id is null or (retention.attachment_outcome='ready' and retention.attachment_attempts<5))
        and case when retention.maint_id is null then history.created_at else retention.closed_at end
          <=clock_timestamp()-interval '90 days'
        and not private.account_cleanup_held(report.user_id,'media',report.attachment_ref->>'id')
        and not private.account_cleanup_held(report.user_id,'support',report.maint_id::text)
        and not exists(select 1 from private.account_cleanup_jobs j
          where j.user_id=report.user_id and j.external_operation is not null)
        and not exists(select 1 from public."Maintenance" other
          where other.maint_id<>report.maint_id and other.attachment_ref=report.attachment_ref)
        and exists(select 1 from storage.objects o where o.bucket_id='maintenance-images'
          and o.owner_id=report.user_id::text and not coalesce(o.is_delete_marker,false)
          and length(o.version) between 1 and 200 and length(o.name) between 1 and 1024
          and o.created_at<=case when retention.maint_id is null then history.created_at else retention.closed_at end
          and report.attachment_ref=jsonb_build_object('id',o.id,'bucket',o.bucket_id,'name',o.name,'version',o.version))
      order by report.maint_id limit 1;
    if not found then
      select maint_id,user_id into candidate from private.account_support_retention
        where requested_at is null and attachment_outcome='removed'
          and attachment_removed_at<=clock_timestamp()-interval '12 months'
          and not private.account_cleanup_held(user_id,'cleanup')
          and not private.account_cleanup_held(user_id,'support',maint_id::text)
          and not private.account_cleanup_held(user_id,'media',attachment_object->>'id')
        order by attachment_removed_at,maint_id limit 1;
      if not found then return result||jsonb_build_object('status','idle'); end if;
      expiring:=true;
    end if;
  end if;
  perform private.lock_account_cleanup_subject(candidate.user_id);
  perform 1 from public.profiles where id=candidate.user_id for no key update;
  perform 1 from private.account_lifecycle where user_id=candidate.user_id for update;
  perform 1 from private.account_cleanup_jobs where user_id=candidate.user_id for update;
  perform 1 from private.account_retained_subjects where user_id=candidate.user_id for no key update;
  select * into m from public."Maintenance" where maint_id=candidate.maint_id for update nowait;
  if not found then return result||jsonb_build_object('status','idle'); end if;
  select * into s from private.account_support_retention where maint_id=m.maint_id for update;
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  if expiring then
    if s.user_id=candidate.user_id and s.requested_at is null and s.attachment_outcome='removed'
      and s.attachment_removed_at<=clock_timestamp()-interval '12 months' and m.attachment_ref is null
      and not private.account_cleanup_held(s.user_id,'cleanup')
      and not private.account_cleanup_held(s.user_id,'support',s.maint_id::text)
      and not private.account_cleanup_held(s.user_id,'media',s.attachment_object->>'id') then
      delete from private.account_support_retention where maint_id=s.maint_id;
      return result||jsonb_build_object('status','progress');
    end if;
    return result||jsonb_build_object('status','idle');
  end if;
  if s.attachment_outcome in ('dispatched','outcome_unknown') then
    if s.attachment_lease_until>clock_timestamp() then return result||jsonb_build_object('status','idle'); end if;
    return result||jsonb_build_object('status','inspect','report_id',s.maint_id::text,
      'claim_id',s.attachment_claim_id,'operation_id',s.attachment_operation_id,'closed_at',s.attachment_closed_at);
  end if;
  -- Empty holds are not an inventory. This class-scoped operator evidence is
  -- deliberately absent at install, and does not approve account finalization.
  if not exists(select 1 from private.account_cleanup_execution where singleton
    and length(btrim(closed_attachment_inventory_reference)) between 1 and 200
    and closed_attachment_inventory_at<=clock_timestamp() and closed_attachment_custodian is not null) then
    return result||jsonb_build_object('status','held','reason','attachment_inventory_unavailable'); end if;
  if s.maint_id is null then
    select h.created_at into closed from public.admin_maintenance_history h
      where h.maintenance_id=m.maint_id::text and h.from_status<>'resolved' and h.to_status='resolved'
        and not exists(select 1 from public.admin_maintenance_history later
          where later.maintenance_id=h.maintenance_id and later.to_status<>'resolved'
            and (later.created_at,later.id)>(h.created_at,h.id))
      order by h.created_at desc,h.id desc limit 1;
  else closed:=s.closed_at; end if;
  if m.user_id is distinct from candidate.user_id or m.status is distinct from 'resolved'
    or closed is null or closed>clock_timestamp()-interval '90 days'
    or (s.maint_id is not null and (s.user_id is distinct from candidate.user_id
      or s.attachment_outcome<>'ready' or s.attachment_attempts>=5))
    or private.account_cleanup_held(candidate.user_id,'support',m.maint_id::text)
    or private.account_cleanup_held(candidate.user_id,'media',m.attachment_ref->>'id')
    or exists(select 1 from private.account_cleanup_jobs where user_id=candidate.user_id and external_operation is not null)
    or exists(select 1 from public."Maintenance" other where other.maint_id<>m.maint_id
      and other.attachment_ref=m.attachment_ref) then
    return result||jsonb_build_object('status','held','reason','attachment_scope_changed'); end if;
  select jsonb_build_object('id',o.id,'bucket',o.bucket_id,'name',o.name,'version',o.version)
    into object_ref from storage.objects o where o.bucket_id='maintenance-images'
      and o.owner_id=candidate.user_id::text and o.version is not null and length(o.version) between 1 and 200
      and not coalesce(o.is_delete_marker,false) and length(o.name) between 1 and 1024 and o.created_at<=closed
      and m.attachment_ref=jsonb_build_object('id',o.id,'bucket',o.bucket_id,'name',o.name,'version',o.version);
  if object_ref is null then
    return result||jsonb_build_object('status','held','reason','attachment_version_or_owner_unproved'); end if;
  operation:=gen_random_uuid();
  insert into private.account_support_retention(maint_id,user_id,closed_at)
    values(m.maint_id,candidate.user_id,closed) on conflict(maint_id) do nothing;
  update private.account_support_retention set attachment_claim_id=p_claim_id,attachment_operation_id=operation,
    attachment_closed_at=closed,attachment_lease_until=clock_timestamp()+interval '5 minutes',
    attachment_outcome='dispatched',attachment_object=object_ref,attachment_attempts=attachment_attempts+1,
    attachment_removed_at=null where maint_id=m.maint_id;
  return result||jsonb_build_object('status','dispatch','report_id',m.maint_id::text,
    'claim_id',p_claim_id,'operation_id',operation,'closed_at',closed,'objects',jsonb_build_array(object_ref));
end $$;

create function public.acknowledge_closed_attachment_cleanup(p_report_id bigint,p_closed_at timestamptz,
  p_claim_id uuid,p_operation_id uuid,p_policy_version text,p_policy_sha256 text,p_outcome text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare subject uuid; s private.account_support_retention; next_attachment boolean;
begin
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  if p_outcome is null or p_outcome not in ('returned','unknown','inspected') then
    raise exception 'invalid_request' using errcode='22023'; end if;
  select user_id into subject from private.account_support_retention where maint_id=p_report_id;
  perform private.lock_account_cleanup_subject(subject);
  perform 1 from public.profiles where id=subject for no key update;
  perform 1 from private.account_lifecycle where user_id=subject for update;
  perform 1 from private.account_cleanup_jobs where user_id=subject for update;
  perform 1 from private.account_retained_subjects where user_id=subject for no key update;
  perform 1 from public."Maintenance" where maint_id=p_report_id for update nowait;
  select * into s from private.account_support_retention where maint_id=p_report_id for update;
  if not found or p_claim_id is null or p_operation_id is null or p_closed_at is null
    or s.attachment_claim_id is distinct from p_claim_id or s.attachment_operation_id is distinct from p_operation_id
    or s.attachment_closed_at is distinct from p_closed_at
    or s.attachment_outcome not in ('dispatched','outcome_unknown','removed') then
    raise exception 'attachment_operation_changed' using errcode='PT409'; end if;
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  if s.attachment_outcome='removed' then
    return jsonb_build_object('status','attachment_removed','purge_complete',false); end if;
  if exists(select 1 from storage.objects o where o.bucket_id=s.attachment_object->>'bucket'
    and o.name=s.attachment_object->>'name' and o.version=s.attachment_object->>'version') then
    update private.account_support_retention set attachment_outcome='outcome_unknown',
      attachment_lease_until=clock_timestamp()+interval '1 day' where maint_id=p_report_id;
    return jsonb_build_object('status','outcome_unknown','purge_complete',false,'automatic_retry',false);
  end if;
  -- A reopen/replacement after dispatch cannot undo removal. Never clear the
  -- replacement, status, or notes; acknowledge only the exact dispatched version.
  update public."Maintenance" set attachment_ref=null,image_data=null
    where maint_id=p_report_id and attachment_ref=s.attachment_object;
  select exists(select 1 from public."Maintenance" where maint_id=p_report_id and status='resolved'
    and attachment_ref is not null and attachment_ref is distinct from s.attachment_object
    and s.closed_at>s.attachment_closed_at) into next_attachment;
  update private.account_support_retention set attachment_outcome=case when next_attachment then 'ready' else 'removed' end,
    attachment_attempts=case when next_attachment then 0 else attachment_attempts end,
    attachment_removed_at=clock_timestamp(),attachment_lease_until=null where maint_id=p_report_id;
  update private.account_cleanup_jobs set next_disposition_at=clock_timestamp()
    where user_id=subject and auth_removed_at is null;
  return jsonb_build_object('status','attachment_removed','purge_complete',false);
end $$;
revoke all on function public.claim_closed_attachment_cleanup(uuid,text,text),
  public.acknowledge_closed_attachment_cleanup(bigint,timestamptz,uuid,uuid,text,text,text)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.claim_closed_attachment_cleanup(uuid,text,text),
  public.acknowledge_closed_attachment_cleanup(bigint,timestamptz,uuid,uuid,text,text,text) to service_role;

create function public.execute_account_cleanup_step(p_claim_id uuid,p_policy_version text,p_policy_sha256 text,
  p_user_id uuid default null,p_requested_at timestamptz default null)
returns jsonb language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare subject uuid; requested timestamptz; claim jsonb; j private.account_cleanup_jobs;
  objects jsonb; result jsonb; reason text; identity_reason text; operation_id uuid;
begin
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  if not private.account_cleanup_references_ready() then
    raise exception 'cleanup_reference_protocol_missing' using errcode='PT503'; end if;
  result:=jsonb_build_object('policy_version',p_policy_version,'policy_sha256',p_policy_sha256,'purge_complete',false);
  if p_claim_id is null then raise exception 'invalid_request' using errcode='22023'; end if;
  if p_user_id is null then
    -- A lost response is inspected against primary state, never dispatched again.
    select * into j from private.account_cleanup_jobs
      where external_operation is not null and auth_removed_at is null
        and (state='outcome_unknown' or lease_until<=clock_timestamp())
        and (next_disposition_at is null or next_disposition_at<=clock_timestamp())
      order by lease_until,user_id limit 1;
    if found then
      return result||jsonb_build_object('status','inspect','user_id',j.user_id,
        'requested_at',j.deletion_requested_at,'claim_id',j.claim_id,
        'operation_id',j.external_operation->>'operation_id');
    end if;
    select l.user_id,l.deletion_requested_at into subject,requested
      from private.account_lifecycle l left join private.account_cleanup_jobs job using(user_id)
      where l.restored_at is null and l.restore_until<=clock_timestamp()
        and job.auth_removed_at is null
        and (job.next_disposition_at is null or job.next_disposition_at<=clock_timestamp())
        and (job.user_id is null or (job.state='retry' and job.retry_after<=clock_timestamp())
          or (job.state='leased' and job.lease_until<=clock_timestamp()))
        and coalesce(job.attempts,0)<5
        and exists(select 1 from private.account_cleanup_inventory i where i.user_id=l.user_id
          and i.requested_at=l.deletion_requested_at and i.recorded_at<=clock_timestamp())
      order by l.restore_until,l.user_id limit 1;
    if subject is null then
      return result||jsonb_build_object('status',case when private.prune_account_cleanup_retention()
        then 'progress' else 'idle' end);
    end if;
  else subject:=p_user_id; requested:=p_requested_at; end if;
  claim:=public.claim_account_cleanup(subject,requested,p_claim_id);
  if claim->>'claimed' is distinct from 'true' then
    return result||jsonb_build_object('status','held','reason','claim_unavailable'); end if;
  perform private.require_account_cleanup_request(subject,requested,p_claim_id);
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  select * into j from private.account_cleanup_jobs where user_id=subject;
  if j.external_operation is not null then
    return result||jsonb_build_object('status','held','reason','external_outcome_requires_inspection'); end if;
  if not exists(select 1 from private.account_cleanup_inventory i where i.user_id=subject
    and i.requested_at=requested and i.recorded_at<=clock_timestamp()) then reason:='inventory_unavailable'; end if;
  if private.account_cleanup_held(subject,'identity') then identity_reason:='identity_hold'; end if;
  if private.account_cleanup_held(subject,'processor') then identity_reason:='processor_hold'; end if;
  -- Inviter UUIDs are safe only after the exact validated creator FK above is
  -- installed. The invited target's Auth CASCADE and all role checks stay intact.
  if exists(select 1 from private.account_support_retention where user_id=subject
    and attachment_outcome in ('dispatched','outcome_unknown')) then reason:='attachment_outcome_pending'; end if;
  if reason is not null then
    update private.account_cleanup_jobs set next_disposition_at='infinity' where user_id=subject;
    return result||jsonb_build_object('status','held','reason',reason);
  end if;
  update private.account_cleanup_jobs set disposition_requested_at=requested,
    disposition_policy_version=p_policy_version,disposition_policy_sha256=p_policy_sha256 where user_id=subject;

  -- Lifecycle already nulls usable tokens at D. Remove only still-owned rows;
  -- never guess which account owns a revoked installation with NULL user_id.
  delete from private.push_installations where user_id=subject;
  delete from private.push_creation_budget where user_id=subject;

  -- Fixed known bucket only. Ownership is authoritative metadata, never a URL
  -- prefix or legacy path guess. Current AND archived versions are included.
  if exists(select 1 from storage.objects where (owner_id=subject::text or owner=subject)
    and (bucket_id is distinct from 'maintenance-images' or name is null or version is null
      or (owner_id is not null and owner_id<>subject::text))) then
    reason:='media_inventory_requires_supported_mapping';
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'bucket',o.bucket_id,'name',o.name,'version',o.version)
      order by o.id),'[]') into objects from (select * from storage.objects
      where (owner_id=subject::text or (owner_id is null and owner=subject)) and bucket_id='maintenance-images'
        and not private.account_cleanup_held(subject,'media',id::text)
        and not exists(select 1 from public."Maintenance" m where m.user_id=subject
          and m.attachment_ref->>'id'=storage.objects.id::text
          and private.account_cleanup_held(subject,'support',m.maint_id::text))
      order by id limit 100) o;
    if jsonb_array_length(objects)>0 then
      operation_id:=gen_random_uuid();
      update private.account_cleanup_jobs set external_operation=jsonb_build_object('kind','storage',
        'claim_id',p_claim_id,'operation_id',operation_id,'requested_at',requested,'objects',objects,'dispatched_at',clock_timestamp())
        where user_id=subject;
      return result||jsonb_build_object('status','dispatch','action','storage','user_id',subject,
        'requested_at',requested,'claim_id',p_claim_id,'operation_id',operation_id,'objects',objects);
    end if;
    if exists(select 1 from storage.objects where owner_id=subject::text or owner=subject)
      then reason:='media_hold'; end if;
  end if;
  update private.account_cleanup_jobs set redaction_xid=pg_current_xact_id() where user_id=subject;
  -- NOWAIT avoids inverting a staff report-row -> profile lock. A contention
  -- failure rolls back this whole local step and is retried, not partial erasure.
  perform 1 from public."Maintenance" where user_id=subject order by maint_id for update nowait;
  insert into private.account_support_retention(maint_id,user_id,requested_at,closed_at)
    select m.maint_id,subject,requested,case when m.status='resolved' then
      (select max(h.created_at) from public.admin_maintenance_history h where h.maintenance_id=m.maint_id::text
        and h.from_status<>'resolved' and h.to_status='resolved') end
      from public."Maintenance" m where m.user_id=subject
    on conflict(maint_id) do update set requested_at=excluded.requested_at
      where private.account_support_retention.user_id=excluded.user_id;
  update public.admin_maintenance_history h set note=null
    where h.note is not null and private.account_cleanup_note_redaction(h.maintenance_id);
  update public."Maintenance" m set description=null,location=null,image_data=null,attachment_ref=null,user_id=null
    where m.user_id=subject and m.status='resolved'
      and not private.account_cleanup_held(subject,'support',m.maint_id::text)
      and not exists(select 1 from storage.objects o where o.id::text=m.attachment_ref->>'id');
  update private.account_support_retention s set redacted_at=coalesce(redacted_at,clock_timestamp())
    where s.user_id=subject and exists(select 1 from public."Maintenance" m
      where m.maint_id=s.maint_id and m.user_id is null and m.description is null and m.attachment_ref is null);
  perform private.mail_lock();
  insert into private.mail_suppression(email,reason)
    select lower(btrim(email)),'account_deletion' from auth.users where id=subject and email is not null
    on conflict(email) do nothing;
  insert into private.mail_suppression(email,reason)
    select distinct email,'account_deletion' from private.newsletter_consent where user_id=subject
    on conflict(email) do nothing;
  update private.newsletter_consent set confirm_hash=null,unsubscribe_hash=null,
    unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),suppression_reason='account_deletion'
    where user_id=subject;
  -- Financial/lifecycle payloads and all event keys/provider IDs remain intact.
  update private.mail_outbox o set email='removed@invalid.invalid',last_error=null
    where o.user_id=subject and o.kind in ('account_welcome','newsletter_confirm','newsletter_welcome')
      and o.state in ('delivered','failed','suppressed') and o.terminal_at<=clock_timestamp()-interval '30 days'
      and not private.account_cleanup_held(subject,'mail',o.id::text);
  -- Recovery evidence may be security-held. Its reference is retained, not
  -- allowed to block Auth erasure or silently cascade with the profile.
  if coalesce(reason,identity_reason) is not null then
    update private.account_cleanup_jobs set redaction_xid=null,next_disposition_at='infinity' where user_id=subject;
    return result||jsonb_build_object('status','held','reason',coalesce(reason,identity_reason));
  end if;
  operation_id:=gen_random_uuid();
  update private.account_cleanup_jobs set local_disposed_at=clock_timestamp(),redaction_xid=null,
    external_operation=jsonb_build_object('kind','auth','claim_id',p_claim_id,
      'operation_id',operation_id,'requested_at',requested,'dispatched_at',clock_timestamp()) where user_id=subject;
  perform private.require_account_cleanup_request(subject,requested,p_claim_id);
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  return result||jsonb_build_object('status','dispatch','action','auth','user_id',subject,
    'requested_at',requested,'claim_id',p_claim_id,'operation_id',operation_id);
end $$;
revoke all on function public.execute_account_cleanup_step(uuid,text,text,uuid,timestamptz)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.execute_account_cleanup_step(uuid,text,text,uuid,timestamptz) to service_role;

-- Runs INSIDE supported Auth admin DELETE. No SQL directly deletes auth.users.
-- Recheck exact request, policy and newly committed holds after the HTTP gap.
create function private.guard_account_cleanup_auth_delete()
returns trigger language plpgsql security definer set search_path='' as $$
declare j private.account_cleanup_jobs; reward numeric;
begin
  select * into j from private.account_cleanup_jobs where user_id=old.id;
  if not found or j.disposition_requested_at is null then return old; end if;
  perform private.require_account_cleanup_policy('retention-draft-2026-10-01',
    '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be');
  perform private.require_account_cleanup_request(old.id,j.deletion_requested_at,j.claim_id);
  select * into j from private.account_cleanup_jobs where user_id=old.id;
  perform private.require_account_cleanup_policy('retention-draft-2026-10-01',
    '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be');
  if j.external_operation->>'kind' is distinct from 'auth'
    or j.external_operation->>'claim_id' is distinct from j.claim_id::text
    or j.disposition_requested_at is distinct from j.deletion_requested_at
    or j.disposition_policy_version is distinct from 'retention-draft-2026-10-01'
    or j.disposition_policy_sha256 is distinct from '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be'
    or private.account_cleanup_held(old.id,'identity') or private.account_cleanup_held(old.id,'processor')
    or not private.account_cleanup_references_ready()
    or exists(select 1 from storage.objects where owner_id=old.id::text or owner=old.id) then
    raise exception 'cleanup_auth_fence_changed' using errcode='PT409'; end if;
  select coalesce(reward_tracker,0)::numeric into reward from public.profiles where id=old.id;
  if reward is null or reward not between 0 and 19.99 or reward*100<>round(reward*100) then
    raise exception 'cleanup_financial_progress_unavailable' using errcode='PT409'; end if;
  update private.account_retained_subjects set reward_tracker=reward,retired_at=clock_timestamp() where user_id=old.id;
  if not found then raise exception 'cleanup_reference_protocol_missing' using errcode='PT503'; end if;
  return old;
end $$;
create trigger account_cleanup_auth_delete before delete on auth.users
  for each row execute function private.guard_account_cleanup_auth_delete();
revoke all on function private.guard_account_cleanup_auth_delete()
  from public,anon,authenticated,service_role,supabase_auth_admin;

-- Acknowledgement trusts local primary state, not the provider response alone.
-- An unknown result never clears the dispatch marker and never causes a resend.
create function public.acknowledge_account_cleanup(p_user_id uuid,p_requested_at timestamptz,p_claim_id uuid,p_operation_id uuid,
  p_policy_version text,p_policy_sha256 text,p_outcome text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare j private.account_cleanup_jobs; absent boolean;
begin
  perform private.require_account_cleanup_policy(p_policy_version,p_policy_sha256);
  perform private.lock_account_cleanup_subject(p_user_id);
  perform 1 from public.profiles where id=p_user_id for no key update;
  perform 1 from private.account_lifecycle where user_id=p_user_id for update;
  select * into j from private.account_cleanup_jobs where user_id=p_user_id for update;
  if not found or j.deletion_requested_at is distinct from p_requested_at or j.claim_id is distinct from p_claim_id
    or j.disposition_requested_at is distinct from p_requested_at
    or j.external_operation->>'claim_id' is distinct from p_claim_id::text
    or p_operation_id is null or j.external_operation->>'operation_id' is distinct from p_operation_id::text
    or not exists(select 1 from private.account_lifecycle where user_id=p_user_id
      and deletion_requested_at=p_requested_at and restored_at is null and restore_until<=clock_timestamp()) then
    raise exception 'cleanup_request_changed' using errcode='PT409'; end if;
  if p_outcome not in ('returned','unknown','inspected') or p_outcome is null then
    raise exception 'invalid_request' using errcode='22023'; end if;
  if j.external_operation->>'kind'='auth' then
    absent:=not exists(select 1 from auth.users where id=p_user_id)
      and not exists(select 1 from public.profiles where id=p_user_id);
  elsif j.external_operation->>'kind'='storage' then
    absent:=not exists(select 1 from jsonb_array_elements(j.external_operation->'objects') ref
      join storage.objects o on o.id=(ref->>'id')::uuid
        and o.bucket_id=ref->>'bucket' and o.name=ref->>'name' and o.version=ref->>'version');
  else raise exception 'cleanup_dispatch_missing' using errcode='PT409'; end if;
  if absent then
    update private.account_cleanup_jobs set external_operation=null,
      state=case when state='outcome_unknown' then 'retry' else state end,
      retry_after=clock_timestamp(),next_disposition_at=null,
      auth_removed_at=case when j.external_operation->>'kind'='auth' then clock_timestamp() else auth_removed_at end
      where user_id=p_user_id;
    return jsonb_build_object('status',case when j.external_operation->>'kind'='auth' then 'account_removed' else 'progress' end,
      'purge_complete',false,'financial_records_retained',true);
  end if;
  update private.account_cleanup_jobs set state='outcome_unknown',lease_until=clock_timestamp(),
    retry_after='infinity',next_disposition_at='infinity' where user_id=p_user_id;
  return jsonb_build_object('status','outcome_unknown','automatic_retry',false,'purge_complete',false);
end $$;
revoke all on function public.acknowledge_account_cleanup(uuid,timestamptz,uuid,uuid,text,text,text)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.acknowledge_account_cleanup(uuid,timestamptz,uuid,uuid,text,text,text) to service_role;

-- Caller already owns the canonical subject locks. This is deliberately not a
-- public RPC: the inventory DELETE exception is exact-request/transaction bound.
create function private.expire_account_cleanup_metadata(p_user uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
declare j private.account_cleanup_jobs; reasons text[]:='{}'; financial_reference text;
begin
  select * into j from private.account_cleanup_jobs where user_id=p_user for update;
  if not found or j.auth_removed_at is null or j.auth_removed_at>clock_timestamp()-interval '12 months'
    or j.external_operation is not null or j.state='outcome_unknown'
    or j.redaction_xid is distinct from pg_current_xact_id()
    or private.account_cleanup_held(p_user,'cleanup') then return; end if;
  if exists(select 1 from auth.users where id=p_user) or exists(select 1 from public.profiles where id=p_user)
    or not exists(select 1 from private.account_lifecycle where user_id=p_user and restored_at is null
      and deletion_requested_at=j.deletion_requested_at) then
    raise exception 'cleanup_request_changed' using errcode='PT409'; end if;
  if exists(select 1 from private.account_support_retention where user_id=p_user and requested_at is not null)
    then reasons:=array_append(reasons,'support'); end if;
  if exists(select 1 from private.newsletter_consent where user_id=p_user)
    then reasons:=array_append(reasons,'newsletter'); end if;
  if exists(select 1 from private.mail_outbox where user_id=p_user
    and kind in ('account_welcome','newsletter_confirm','newsletter_welcome')
    and (email is distinct from 'removed@invalid.invalid' or last_error is not null))
    then reasons:=array_append(reasons,'mail'); end if;
  if exists(select 1 from private.customer_mfa_recovery where user_id=p_user)
    then reasons:=array_append(reasons,'security'); end if;
  select financial_retention_reference into financial_reference from private.account_cleanup_inventory
    where user_id=p_user and requested_at=j.deletion_requested_at;
  update private.account_retained_subjects set financial_retention_reference=
    coalesce(financial_reference,financial_retention_reference) where user_id=p_user;
  if not found then raise exception 'cleanup_reference_protocol_missing' using errcode='PT503'; end if;
  delete from private.account_cleanup_inventory where user_id=p_user and requested_at=j.deletion_requested_at;
  if cardinality(reasons)=0 then
    delete from private.account_cleanup_jobs where user_id=p_user;
    delete from private.account_lifecycle where user_id=p_user and deletion_requested_at=j.deletion_requested_at;
  else
    update private.account_cleanup_jobs set state='retention_only',retention_reasons=reasons,
      metadata_compacted_at=coalesce(metadata_compacted_at,clock_timestamp()),
      claim_id=null,attempts=null,used_claim_ids=null,lease_until=null,retry_after=null,
      external_operation=null,disposition_requested_at=null,local_disposed_at=null,next_disposition_at=null,
      disposition_policy_version=null,disposition_policy_sha256=null where user_id=p_user;
  end if;
end $$;
revoke all on function private.expire_account_cleanup_metadata(uuid)
  from public,anon,authenticated,service_role,supabase_auth_admin;

-- One already-removed subject per idle invocation. Known clocks only; missing
-- historical clocks do not become invented dates. No financial record deletion.
create function private.prune_account_cleanup_retention()
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare subject uuid; report record; consent record;
begin
  perform private.require_account_cleanup_policy('retention-draft-2026-10-01',
    '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be');
  select user_id into subject from private.account_cleanup_jobs where auth_removed_at is not null
    and (last_retention_at is null or last_retention_at<clock_timestamp()-interval '1 day')
    order by last_retention_at nulls first,user_id limit 1;
  if subject is null then return false; end if;
  perform private.lock_account_cleanup_subject(subject);
  perform 1 from private.account_lifecycle where user_id=subject for update;
  perform 1 from private.account_cleanup_jobs where user_id=subject for update;
  perform 1 from private.account_retained_subjects where user_id=subject for no key update;
  perform private.require_account_cleanup_policy('retention-draft-2026-10-01',
    '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be');
  if exists(select 1 from auth.users where id=subject) or exists(select 1 from public.profiles where id=subject)
    or not exists(select 1 from private.account_lifecycle l join private.account_cleanup_jobs j using(user_id)
      where l.user_id=subject and l.restored_at is null
        and (l.deletion_requested_at=j.disposition_requested_at or j.state='retention_only')
        and l.deletion_requested_at=j.deletion_requested_at and j.auth_removed_at is not null) then
    raise exception 'cleanup_request_changed' using errcode='PT409'; end if;
  update private.account_cleanup_jobs set redaction_xid=pg_current_xact_id() where user_id=subject;
  perform 1 from public."Maintenance" m join private.account_support_retention s using(maint_id)
    where s.user_id=subject order by m.maint_id for update of m nowait;
  update public.admin_maintenance_history h set note=null
    where h.note is not null and private.account_cleanup_note_redaction(h.maintenance_id);
  update public."Maintenance" m set user_id=null,description=null,location=null,image_data=null,attachment_ref=null
    where exists(select 1 from private.account_support_retention s where s.maint_id=m.maint_id and s.user_id=subject)
      and private.account_cleanup_note_redaction(m.maint_id::text)
      and not exists(select 1 from storage.objects o where o.id::text=m.attachment_ref->>'id');
  update private.account_support_retention s set redacted_at=coalesce(redacted_at,clock_timestamp())
    where s.user_id=subject and exists(select 1 from public."Maintenance" m where m.maint_id=s.maint_id
      and m.user_id is null and m.description is null and m.attachment_ref is null);
  for report in select s.maint_id from private.account_support_retention s
    where s.user_id=subject and s.redacted_at is not null
      and s.attachment_outcome not in ('dispatched','outcome_unknown')
      and s.closed_at<=clock_timestamp()-interval '12 months'
      and private.account_cleanup_note_redaction(s.maint_id::text) loop
    delete from public.admin_maintenance_history where maintenance_id=report.maint_id::text;
    delete from private.account_support_retention where maint_id=report.maint_id;
    delete from public."Maintenance" where maint_id=report.maint_id;
  end loop;
  delete from private.customer_mfa_recovery r where user_id=subject
    and started_at<=clock_timestamp()-interval '90 days'
    and not private.account_cleanup_held(subject,'security','mfa/'||r.recovery_id::text);
  perform private.mail_lock();
  update private.mail_outbox o set email='removed@invalid.invalid',last_error=null
    where o.user_id=subject and o.kind in ('account_welcome','newsletter_confirm','newsletter_welcome')
      and o.state in ('delivered','failed','suppressed') and o.terminal_at<=clock_timestamp()-interval '30 days'
      and not private.account_cleanup_held(subject,'mail',o.id::text);
  for consent in select c.id from private.newsletter_consent c where c.user_id=subject
    and c.retention_clock_started_at is not null and c.unsubscribed_at is not null
    and greatest(c.unsubscribed_at,c.retention_last_use_at,c.confirmed_at,c.requested_at)<=clock_timestamp()-interval '3 years'
    and not private.account_cleanup_held(subject,'newsletter',c.id::text)
    and not exists(select 1 from private.mail_outbox o where o.consent_id=c.id
      and (o.state not in ('delivered','failed','suppressed')
        or o.kind not in ('newsletter_confirm','newsletter_welcome')
        or private.account_cleanup_held(subject,'mail',o.id::text))) loop
    -- Keep dedup/event/provider evidence. A late callback cannot recreate mail.
    update private.mail_outbox set consent_id=null where consent_id=consent.id;
    delete from private.newsletter_consent where id=consent.id;
  end loop;
  perform private.expire_account_cleanup_metadata(subject);
  update private.account_cleanup_jobs set redaction_xid=null,last_retention_at=clock_timestamp() where user_id=subject;
  return true;
end $$;
revoke all on function private.prune_account_cleanup_retention()
  from public,anon,authenticated,service_role,supabase_auth_admin;

commit;
