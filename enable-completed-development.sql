-- User approved enabling completed development features on 2026-10-01.
-- Enables self-service pending deletion, not erasure or credit forfeiture.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $$
declare job_id bigint;
begin
  if current_user<>'postgres' then raise exception 'Trusted operator required'; end if;
  if to_regprocedure('private.request_account_deletion()') is null
    or to_regprocedure('private.require_other_owner(uuid)') is null
    or to_regprocedure('public.restore_account()') is null then
    raise exception 'Installed guarded lifecycle contract required';
  end if;
  if has_function_privilege('authenticated','private.request_account_deletion()','execute') then
    raise exception 'Inner lifecycle implementation must remain private';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('cleanstream-cortina-scheduler',0));
  select jobid into strict job_id from cron.job
    where jobname='cleanstream-cortina-reconcile'
      and username=current_user and database=current_database()
      and command='select private.cortina_reconcile_tick();'
      and schedule='* * * * *';
  grant execute on function public.request_account_deletion() to authenticated;
  perform cron.alter_job(job_id,active:=true);
end $$;
select jsonb_build_object(
  'deletion_requests_enabled',has_function_privilege('authenticated','public.request_account_deletion()','execute'),
  'reconciliation_scheduler_active',(select active from cron.job where jobname='cleanstream-cortina-reconcile')
) as development_activation_receipt;
commit;
