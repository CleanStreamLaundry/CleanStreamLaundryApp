-- Operator-run, dormant development setup. Not a migration or activation.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
-- Fail rather than inspect a filtered cron inventory; this does not bypass RLS.
set local row_security = off;

do $$
begin
  if current_user <> 'postgres' then
    raise exception 'Account cleanup scheduler requires the postgres operator';
  end if;
  if to_regclass('cron.job') is null
    or to_regprocedure('cron.schedule(text,text,text)') is null
    or to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is null
    or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
    or to_regclass('vault.secrets') is null
    or to_regclass('vault.decrypted_secrets') is null
    or to_regnamespace('private') is null
    or to_regprocedure('public.execute_account_cleanup_step(uuid,text,text,uuid,timestamptz)') is null
    or to_regclass('private.account_cleanup_execution') is null then
    raise exception 'Account cleanup scheduler requires existing Cron, pg_net, Vault and cleanup SQL';
  end if;
  if (select count(*) from vault.secrets
      where name = 'cleanstream_account_cleanup_project_url') <> 1
    or (select count(*) from vault.secrets
      where name = 'cleanstream_account_cleanup_worker_secret') <> 1 then
    raise exception 'Account cleanup scheduler Vault entries are missing or ambiguous';
  end if;
  if not exists(select 1 from private.account_cleanup_execution
    where singleton and not execution_enabled and not credit_forfeiture_enabled) then
    raise exception 'Install only with cleanup execution and forfeiture disabled';
  end if;

  -- Managed Cron does not grant table-lock privileges. This coordinates these
  -- operator scripts only; pause independent dashboard edits during setup.
  perform pg_advisory_xact_lock(hashtextextended('cleanstream-account-cleanup-scheduler', 0));
  if (select count(*) from cron.job
      where jobname = 'cleanstream-account-cleanup') > 1
    or exists (select 1 from cron.job
      where jobname = 'cleanstream-account-cleanup'
        and (username is distinct from current_user
          or database is distinct from current_database()
          or command is distinct from 'select private.account_cleanup_tick();'
          or schedule is distinct from '0 3 * * *')) then
    raise exception 'Account cleanup scheduler job name conflicts with existing configuration';
  end if;
  if exists (select 1 from cron.job
      where jobname = 'cleanstream-account-cleanup' and active is distinct from false) then
    raise exception 'Account cleanup scheduler is active; explicitly disable it before setup';
  end if;
  if exists (select 1 from cron.job
      where jobname is distinct from 'cleanstream-account-cleanup'
        and (command ilike '%/functions/v1/account-cleanup%'
          or command ilike '%account_cleanup_tick%')) then
    raise exception 'Another cleanup schedule must be resolved before setup';
  end if;
  if exists (select 1 from pg_catalog.pg_proc
      where oid = to_regprocedure('private.account_cleanup_tick()')
        and (proowner <> (select oid from pg_catalog.pg_roles where rolname = current_user)
          or prosecdef)) then
    raise exception 'Account cleanup tick has conflicting ownership or authority';
  end if;
end
$$;

create or replace function private.account_cleanup_tick() returns bigint
language plpgsql security invoker set search_path = '' as $$
declare
  project_url text;
  worker_secret text;
begin
  if current_user <> 'postgres' then
    raise exception 'Account cleanup scheduler operator required';
  end if;
  -- Dormant/manual calls do not read decrypted values or queue HTTP.
  if not exists (select 1 from cron.job
      where jobname = 'cleanstream-account-cleanup'
        and username = current_user and database = current_database()
        and command = 'select private.account_cleanup_tick();'
        and schedule = '0 3 * * *' and active) then
    return null;
  end if;

  if not exists(select 1 from private.account_cleanup_execution where singleton and execution_enabled) then
    return null;
  end if;
  perform private.require_account_cleanup_policy('retention-voluntary-surrender-2026-10-05',
    '95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac');

  select decrypted_secret into strict project_url from vault.decrypted_secrets
    where name = 'cleanstream_account_cleanup_project_url';
  select decrypted_secret into strict worker_secret from vault.decrypted_secrets
    where name = 'cleanstream_account_cleanup_worker_secret';
  if project_url is distinct from 'https://dnuuhupoxjtwqzaqylvb.supabase.co'
    or worker_secret is null or length(worker_secret) < 32
    or worker_secret <> btrim(worker_secret) or worker_secret ~ '[[:cntrl:]]' then
    raise exception 'Account cleanup scheduler configuration invalid';
  end if;

  -- One subject, bounded phases; policy/holds and Edge execution remain independently gated.
  return net.http_post(
    url := project_url || '/functions/v1/account-cleanup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json', 'X-Account-Cleanup-Secret', worker_secret
    ),
    body := '{"action":"run"}'::jsonb,
    timeout_milliseconds := 55000
  );
exception when others then
  -- Never propagate extension diagnostics containing headers or credentials.
  raise exception 'Account cleanup scheduling failed; use restricted operator diagnostics'
    using errcode = 'P0001';
end
$$;

revoke all on function private.account_cleanup_tick()
  from public, anon, authenticated, service_role;

do $$
declare job_id bigint;
begin
  select jobid into job_id from cron.job
    where jobname = 'cleanstream-account-cleanup';
  if job_id is null then
    job_id := cron.schedule(
      'cleanstream-account-cleanup', '0 3 * * *',
      'select private.account_cleanup_tick();'
    );
    -- No committed active window: both operations share this transaction.
    perform cron.alter_job(job_id, active := false);
  end if;
  if not exists (select 1 from cron.job
      where jobid = job_id and active is false
        and username = current_user and database = current_database()
        and jobname = 'cleanstream-account-cleanup'
        and schedule = '0 3 * * *'
        and command = 'select private.account_cleanup_tick();') then
    raise exception 'Account cleanup scheduler did not remain dormant';
  end if;
end
$$;

commit;
