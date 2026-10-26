-- Recovery prerequisite only. No policy publication, execution activation or money writes.
-- SHA-256 input (UTF-8, no newline):
-- retention-paid-credit-2026-10-05|restore=90-days-explicit|delete=auth-profile|paid=no-expiry-no-forfeiture|promo=cancel-at-final-deletion|unresolved=retain|reclaim=verified-owner-support
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local timezone = 'UTC';

-- Fail instead of racing a worker transaction or waiting behind its dispatch.
lock table private.account_cleanup_execution, private.account_lifecycle,
  private.account_cleanup_jobs, private.account_retained_subjects,
  private.account_support_retention in access exclusive mode nowait;

do $$
declare signature text; routine regprocedure; subject uuid;
begin
  if current_user <> 'postgres' or not private.account_cleanup_references_ready() then
    raise exception 'Reviewed postgres and retained financial prerequisites required';
  end if;
  if not exists(select 1 from private.account_cleanup_execution where singleton
    and not execution_enabled and not credit_forfeiture_enabled) then
    raise exception 'Stop cleanup execution before changing recovery policy';
  end if;
  -- External calls cannot be undone by a database lock. Resolve these first;
  -- never extend a partly erased identity and present it as fully recoverable.
  if exists(select 1 from private.account_lifecycle l
    join auth.users u on u.id=l.user_id and u.deleted_at is null
    join public.profiles p on p.id=l.user_id
    left join private.account_cleanup_jobs j on j.user_id=l.user_id
    left join private.account_retained_subjects r on r.user_id=l.user_id
    where l.restored_at is null and j.auth_removed_at is null and r.retired_at is null
      and (j.disposition_requested_at is not null or j.local_disposed_at is not null
        or j.external_operation is not null or exists (
          select 1 from private.account_support_retention s where s.user_id=l.user_id
            and s.attachment_outcome in ('dispatched','outcome_unknown')))) then
    raise exception 'Pending destructive cleanup requires reconciliation before extension';
  end if;
  foreach signature in array array['public.request_account_deletion()',
    'private.require_account_cleanup_policy(text,text)',
    'private.guard_account_cleanup_auth_delete()', 'private.prune_account_cleanup_retention()'] loop
    routine := to_regprocedure(signature);
    if routine is null or not exists(select 1 from pg_proc where oid=routine
      and proowner=(select oid from pg_roles where rolname=current_user)) then
      raise exception 'Owned replacement routine required: %',signature;
    end if;
  end loop;
  if to_regprocedure('public.restore_account()') is null then
    raise exception 'Explicit restoration prerequisite required';
  end if;
  -- NOWAIT avoids inversion with an Auth/request transaction already waiting
  -- on our table locks. A failed migration rolls back in full and is retried later.
  for subject in select l.user_id from private.account_lifecycle l
    where l.restored_at is null order by l.user_id loop
    perform 1 from auth.users where id=subject for share nowait;
    perform 1 from public.profiles where id=subject for no key update nowait;
  end loop;
end $$;

-- Keep historical restored/retired requests at their original policy. New
-- requests and still-recoverable pending identities get the new minimum.
alter table private.account_lifecycle
  add column recovery_window_days smallint not null default 30
    check (recovery_window_days in (30,90));
alter table private.account_lifecycle alter column recovery_window_days set default 90;
do $$
declare c record; changed integer := 0;
begin
  for c in select conname from pg_constraint
    where conrelid='private.account_lifecycle'::regclass and contype='c'
      and pg_get_constraintdef(oid) like '%restore_until%deletion_requested_at%'
      and pg_get_constraintdef(oid) not like '%restored_at%' loop
    execute format('alter table private.account_lifecycle drop constraint %I',c.conname);
    changed := changed+1;
  end loop;
  if changed <> 1 then raise exception 'Recovery deadline constraint prerequisite mismatch'; end if;
end $$;
alter table private.account_lifecycle add constraint account_lifecycle_recovery_window_check
  check (restore_until >= deletion_requested_at + recovery_window_days * interval '24 hours');

-- Exact lifecycle matching in mail_allowed remains authoritative. Old notices
-- keep their original timestamps; the existing suppression trigger rejects
-- unsent notices whose deadline is superseded by the extension below.
alter table private.mail_outbox drop constraint mail_outbox_lifecycle_notice_check;
alter table private.mail_outbox add constraint mail_outbox_lifecycle_notice_check check (
  (kind in ('account_deletion_scheduled','account_restored')
    and consent_id is null and lifecycle_requested_at is not null
    and lifecycle_restore_until is not null
    and lifecycle_restore_until >= lifecycle_requested_at + interval '720 hours'
    and ((kind='account_deletion_scheduled' and lifecycle_restored_at is null)
      or (kind='account_restored' and lifecycle_restored_at is not null
        and lifecycle_restored_at > lifecycle_requested_at
        and lifecycle_restored_at < lifecycle_restore_until)))
  or (kind not in ('account_deletion_scheduled','account_restored')
    and lifecycle_requested_at is null and lifecycle_restore_until is null
    and lifecycle_restored_at is null)
);

update private.account_lifecycle l set recovery_window_days=90,
  restore_until=greatest(l.restore_until,l.deletion_requested_at+interval '2160 hours')
where l.restored_at is null
  and exists(select 1 from auth.users u where u.id=l.user_id and u.deleted_at is null)
  and exists(select 1 from public.profiles p where p.id=l.user_id)
  and not exists(select 1 from private.account_retained_subjects r
    where r.user_id=l.user_id and r.retired_at is not null)
  and not exists(select 1 from private.account_cleanup_jobs j
    where j.user_id=l.user_id and j.auth_removed_at is not null);

-- Only the private request duration changes. Preserve the public Owner guard,
-- authority, locking, error handling, OIDs and ACLs.
do $$
declare definition text;
begin
  if strpos(pg_get_functiondef('public.request_account_deletion()'::regprocedure),
    'private.request_account_deletion()')=0 then
    raise exception 'Owner-guarded request wrapper prerequisite mismatch';
  end if;
  definition := pg_get_functiondef('private.request_account_deletion()'::regprocedure);
  if strpos(definition, 'requested_at + interval ''720 hours''')=0
    or strpos(definition, 'restore_until = excluded.restore_until, restored_at = null')=0 then
    raise exception 'Request routine prerequisite mismatch';
  end if;
  definition := replace(definition, 'requested_at + interval ''720 hours''',
    'requested_at + interval ''2160 hours''');
  definition := replace(definition, 'restore_until = excluded.restore_until, restored_at = null',
    'restore_until = excluded.restore_until, restored_at = null, recovery_window_days = 90');
  execute definition;
end $$;

-- Old execution approvals cannot authorize the changed retention schedule.
update private.account_cleanup_execution set execution_enabled=false,
  approved_policy_version=null, approved_policy_sha256=null, final_policy_approved_at=null;
do $$
declare signature text; definition text; c record; changed integer := 0;
begin
  for c in select conname,pg_get_constraintdef(oid) as definition from pg_constraint
    where conrelid='private.account_cleanup_execution'::regclass and contype='c'
      and strpos(pg_get_constraintdef(oid),'retention-paid-credit-2026-10-02')>0 loop
    definition := replace(replace(c.definition,
      'retention-paid-credit-2026-10-02','retention-paid-credit-2026-10-05'),
      '756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592',
      '0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04');
    execute format('alter table private.account_cleanup_execution drop constraint %I, add constraint %I %s',
      c.conname,c.conname,definition);
    changed := changed+1;
  end loop;
  if changed <> 1 then raise exception 'Cleanup policy constraint prerequisite mismatch'; end if;
  foreach signature in array array['private.require_account_cleanup_policy(text,text)',
    'private.guard_account_cleanup_auth_delete()', 'private.prune_account_cleanup_retention()'] loop
    definition := pg_get_functiondef(signature::regprocedure);
    if strpos(definition,'retention-paid-credit-2026-10-02')=0
      or strpos(definition,'756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592')=0 then
      raise exception 'Cleanup policy routine prerequisite mismatch: %',signature;
    end if;
    execute replace(replace(definition,
      'retention-paid-credit-2026-10-02','retention-paid-credit-2026-10-05'),
      '756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592',
      '0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04');
  end loop;
end $$;

-- The obsolete preservation-only .1 publication was removed while this migration
-- was still unapplied. Composer publishes the approved .2 document separately,
-- after action consent and prospective surrender guards are installed.
commit;
