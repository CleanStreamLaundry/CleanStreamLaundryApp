-- Pause only this owned job. Keep job/run history, claims, credentials and mail.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local row_security = off;

do $$
declare job_id bigint;
begin
  if current_user <> 'postgres' then
    raise exception 'Reconciliation scheduler requires the postgres operator';
  end if;
  if to_regclass('cron.job') is null then return; end if;
  if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is null then
    raise exception 'Reconciliation scheduler disable requires existing Cron';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('cleanstream-cortina-scheduler', 0));
  if (select count(*) from cron.job
      where jobname = 'cleanstream-cortina-reconcile') > 1
    or exists (select 1 from cron.job
      where jobname = 'cleanstream-cortina-reconcile'
        and (username is distinct from current_user
          or database is distinct from current_database()
          or command is distinct from 'select private.cortina_reconcile_tick();')) then
    raise exception 'Reconciliation scheduler job name conflicts with existing configuration';
  end if;
  select jobid into job_id from cron.job
    where jobname = 'cleanstream-cortina-reconcile';
  if job_id is not null then
    perform cron.alter_job(job_id, active := false);
  end if;
end
$$;

commit;
