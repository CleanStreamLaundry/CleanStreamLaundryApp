-- October 5 initial activation only. Run after the reviewed worker/configuration.
-- Does not invoke cleanup or alter any customer account/balance.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local row_security = off;

do $$
declare job_id bigint; descriptor jsonb;
begin
  if current_user <> 'postgres' then
    raise exception 'Account cleanup activation requires the postgres operator';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('cleanstream-account-cleanup-scheduler', 0));
  perform 1 from private.account_cleanup_execution where singleton for update;
  if not exists(select 1 from supabase_migrations.schema_migrations
      where version='20261005183040')
    or to_regprocedure('private.prepare_account_cleanup_inventory()') is null
    or private.loyalty_action_recovery_days() <> 90
    or not private.account_cleanup_references_ready() then
    raise exception 'Reviewed automatic inventory and 90-day prerequisites required';
  end if;
  descriptor := public.get_loyalty_policy_descriptor();
  if descriptor->>'required_version' is distinct from '2026-10-05.2'
    or descriptor->>'policy_sha256' is distinct from
      'b3dd213035a559debaf1bc5a2893beb7f7a6589a0b7741dae67b6bdc953e34b9'
    or not exists(select 1 from private.account_cleanup_execution where singleton
      and not execution_enabled and not credit_forfeiture_enabled
      and surrender_policy_version=descriptor->>'required_version'
      and surrender_policy_sha256=descriptor->>'policy_sha256'
      and surrender_terms_enabled_at is not null) then
    raise exception 'Stopped execution and exact published policy required';
  end if;
  -- Initial rollout was reviewed with no pending requests. Changed state needs
  -- review, not an automatic replay of this activation script.
  if exists(select 1 from private.account_lifecycle where restored_at is null
      and deletion_requested_at is not null)
    or exists(select 1 from private.account_cleanup_jobs where external_operation is not null) then
    raise exception 'Review newly pending requests or external operations before activation';
  end if;
  if (select count(*) from cron.job where jobname='cleanstream-account-cleanup') <> 1
    or not exists(select 1 from cron.job where jobname='cleanstream-account-cleanup'
      and username=current_user and database=current_database() and not active
      and schedule='0 3 * * *' and command='select private.account_cleanup_tick();')
    or strpos(pg_get_functiondef('private.account_cleanup_tick()'::regprocedure),
      '95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac')=0 then
    raise exception 'Reviewed dormant scheduler required';
  end if;
  update private.account_cleanup_execution set execution_enabled=true,
    credit_forfeiture_enabled=true,
    approved_policy_version='retention-voluntary-surrender-2026-10-05',
    approved_policy_sha256='95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac',
    final_policy_approved_at=clock_timestamp()
    where singleton;
  select jobid into strict job_id from cron.job where jobname='cleanstream-account-cleanup';
  perform cron.alter_job(job_id, active := true);
end $$;

commit;
