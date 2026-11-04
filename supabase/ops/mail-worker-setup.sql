-- Operator-run setup only. No secret values, extension installation or rollout changes.
begin;

do $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null
    or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
    or to_regclass('vault.decrypted_secrets') is null
    or to_regclass('private.mail_settings') is null then
    raise exception 'Mail scheduler requires existing Cron, pg_net, Vault and mail migrations';
  end if;
  if (select count(*) from vault.decrypted_secrets
      where name = 'cleanstream_mail_project_url') <> 1
    or (select count(*) from vault.decrypted_secrets
      where name = 'cleanstream_mail_worker_secret') <> 1 then
    raise exception 'Mail scheduler Vault entries are missing or ambiguous';
  end if;
  if exists (select 1 from cron.job where jobname = 'cleanstream-mail-delivery'
      and (username <> current_user or command <> 'select private.mail_worker_tick();')) then
    raise exception 'Mail scheduler job name is already owned by another configuration';
  end if;
  if exists (select 1 from cron.job where jobname is distinct from 'cleanstream-mail-delivery'
      and (command ilike '%/functions/v1/mail-delivery%'
        or command ilike '%private.mail_worker_tick%')) then
    raise exception 'An existing mail worker schedule must be reconciled before setup';
  end if;
end
$$;

create or replace function private.mail_worker_tick() returns bigint
language plpgsql security invoker set search_path = '' as $$
declare
  project_url text;
  worker_secret text;
begin
  if not exists (select 1 from private.mail_settings
      where enabled and rollout_at is not null and rollout_at <= clock_timestamp()) then
    return null;
  end if;

  select decrypted_secret into strict project_url from vault.decrypted_secrets
    where name = 'cleanstream_mail_project_url';
  select decrypted_secret into strict worker_secret from vault.decrypted_secrets
    where name = 'cleanstream_mail_worker_secret';
  if project_url is null or project_url !~ '^https://[a-z0-9]+[.]supabase[.]co$'
    or project_url <> btrim(project_url) or project_url ~ '[[:cntrl:]]'
    or worker_secret is null or length(worker_secret) < 32
    or worker_secret <> btrim(worker_secret) or worker_secret ~ '[[:cntrl:]]' then
    raise exception 'Mail scheduler configuration invalid';
  end if;

  -- One invocation, one existing worker claim. Never replay a timed-out send here.
  return net.http_post(
    url := project_url || '/functions/v1/mail-delivery',
    headers := jsonb_build_object(
      'Content-Type', 'application/json', 'Authorization', 'Bearer ' || worker_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
exception when others then
  -- Do not propagate extension errors that may include credentials or headers.
  raise exception 'Mail worker scheduling failed; check configuration and restricted diagnostics'
    using errcode = 'P0001';
end
$$;

revoke all on function private.mail_worker_tick() from public, anon, authenticated, service_role;

select cron.schedule(
  'cleanstream-mail-delivery',
  '* * * * *',
  'select private.mail_worker_tick();'
) as mail_worker_job_id;

commit;
