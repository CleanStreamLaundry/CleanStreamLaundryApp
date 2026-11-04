-- Stop future scheduled invocations; do not erase jobs, attempts or credentials.
begin;
do $$
declare job_id bigint;
begin
  if to_regclass('cron.job') is not null
    and to_regprocedure('cron.unschedule(bigint)') is not null then
    for job_id in select jobid from cron.job
      where jobname = 'cleanstream-mail-delivery'
        and username = current_user
        and command = 'select private.mail_worker_tick();'
    loop
      perform cron.unschedule(job_id);
    end loop;
  end if;
end
$$;
commit;
