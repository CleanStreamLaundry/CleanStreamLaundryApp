import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const cli = '/opt/homebrew/bin/supabase';
const workdir = '/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp';
const project = 'dnuuhupoxjtwqzaqylvb';

function run(args, input) {
  const result = spawnSync(cli, [...args, '--workdir', workdir], {
    input, encoding: 'utf8', timeout: 120000, maxBuffer: 1024 * 1024,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  // Captured CLI output may contain credentials; never forward it or its errors.
  if (result.error || result.status !== 0) throw new Error('CLI operation did not complete; no secret output exposed.');
  return result.stdout;
}

try {
  if (readFileSync(`${workdir}/supabase/.temp/project-ref`, 'utf8').trim() !== project) {
    throw new Error('Linked project mismatch.');
  }
  run(['secrets', 'set', '--project-ref', project, '--env-file', '/dev/stdin'],
    'CORTINA_RECONCILIATION_ENABLED=false\n');
  console.log('Reconciliation execution explicitly disabled.');

  const sql = `begin;
    set local lock_timeout='5s';
    set local statement_timeout='30s';
    do $$ begin
      if current_user <> 'postgres' then raise exception 'Operator required'; end if;
      perform pg_advisory_xact_lock(hashtextextended('cleanstream-cortina-credential',0));
      if exists(select 1 from cron.job where jobname='cleanstream-cortina-reconcile' and active) then
        raise exception 'Scheduler must remain inactive';
      end if;
      if not exists(select 1 from vault.secrets where name='cleanstream_cortina_reconcile_project_url') then
        perform vault.create_secret('https://dnuuhupoxjtwqzaqylvb.supabase.co',
          'cleanstream_cortina_reconcile_project_url','Clean Stream dormant reconciliation project');
      end if;
      if not exists(select 1 from vault.secrets where name='cleanstream_cortina_reconcile_worker_secret') then
        perform vault.create_secret(encode(extensions.gen_random_bytes(48),'hex'),
          'cleanstream_cortina_reconcile_worker_secret','Clean Stream dedicated reconciliation bearer');
      end if;
      if (select count(*) from vault.secrets where name='cleanstream_cortina_reconcile_project_url')<>1
        or (select count(*) from vault.secrets where name='cleanstream_cortina_reconcile_worker_secret')<>1
        or (select decrypted_secret from vault.decrypted_secrets
          where name='cleanstream_cortina_reconcile_project_url') is distinct from
          'https://dnuuhupoxjtwqzaqylvb.supabase.co' then
        raise exception 'Dedicated configuration conflict';
      end if;
    end $$;
    select decrypted_secret as worker_secret from vault.decrypted_secrets
      where name='cleanstream_cortina_reconcile_worker_secret';
    commit;`;
  const raw = run(['db', 'query', '--linked', '--file', '/dev/stdin', '--output', 'json'], sql);
  let parsed;
  try { parsed = JSON.parse(raw); } catch { throw new Error('Credential response format unavailable; secret remains in Vault.'); }
  const rows = Array.isArray(parsed) ? parsed : parsed.rows;
  const secret = rows?.length === 1 ? rows[0].worker_secret : undefined;
  if (typeof secret !== 'string' || !/^[a-f0-9]{96}$/.test(secret)) {
    throw new Error('Dedicated credential format mismatch; no Edge credential written.');
  }
  run(['secrets', 'set', '--project-ref', project, '--env-file', '/dev/stdin'],
    `CORTINA_RECONCILIATION_ENABLED=false\nCORTINA_RECONCILIATION_WORKER_SECRET=${secret}\n`);
  console.log('Dedicated Vault and Edge credential configured. Execution remains disabled. No worker invocation.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
