import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const setup = await readFile(new URL('../supabase/ops/mail-worker-setup.sql', import.meta.url), 'utf8');
const disable = await readFile(new URL('../supabase/ops/mail-worker-disable.sql', import.meta.url), 'utf8');
const secret = 'synthetic-worker-secret-not-a-real-key-123456';
const project = 'https://fixture.supabase.co';
const q = value => `'${value.replaceAll("'", "''")}'`;

test('mail scheduler setup/disable reuses the guarded worker', { timeout: 180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  await db.query(`
    create role anon; create role authenticated; create role service_role;
    create schema private; create schema vault; create schema cron; create schema net;
    create table private.mail_settings(enabled boolean, rollout_at timestamptz);
    insert into private.mail_settings values(false,null);
    create table private.mail_outbox(event_key text, attempts integer, state text);
    insert into private.mail_outbox values('retained-event',2,'uncertain');
    create table vault.fixture_secrets(name text, decrypted_secret text);
    create view vault.decrypted_secrets as select * from vault.fixture_secrets;
    create table cron.job(jobid bigserial primary key, jobname text, schedule text,
      command text, username text default current_user, active boolean default true,
      unique(jobname,username));
    create function cron.schedule(p_name text,p_schedule text,p_command text) returns bigint
      language sql as $$
      insert into cron.job(jobname,schedule,command) values(p_name,p_schedule,p_command)
      on conflict(jobname,username) do update set schedule=excluded.schedule,
        command=excluded.command,active=true returning jobid;
      $$;
    create function cron.unschedule(p_id bigint) returns boolean language sql as $$
      with removed as (delete from cron.job where jobid=p_id returning jobid)
      select exists(select 1 from removed);
      $$;
    create table net.calls(id bigserial, url text, body jsonb, params jsonb,
      headers jsonb, timeout_milliseconds integer);
    create table net.fixture_fault(enabled boolean);
    insert into net.fixture_fault values(false);
    create function net.http_post(url text,body jsonb default '{}',params jsonb default '{}',
      headers jsonb default '{}',timeout_milliseconds integer default 2000)
      returns bigint language plpgsql as $$
      declare request_id bigint;
      begin
        if (select enabled from net.fixture_fault) then
          raise exception 'Synthetic extension failure: %', headers;
        end if;
        insert into net.calls(url,body,params,headers,timeout_milliseconds)
          values(url,body,params,headers,timeout_milliseconds) returning id into request_id;
        return request_id;
      end $$;
  `);
  const run = async sql => {
    const connection = await cluster.connect();
    try { return await connection.query(sql); } finally { await connection.close(); }
  };
  const reset = async () => {
    await db.query(`truncate cron.job,net.calls,vault.fixture_secrets;
      update private.mail_settings set enabled=false,rollout_at=null;
      update net.fixture_fault set enabled=false;
      insert into vault.fixture_secrets values
        ('cleanstream_mail_project_url',${q(project)}),
        ('cleanstream_mail_worker_secret',${q(secret)});`);
  };
  const enable = () => db.query("update private.mail_settings set enabled=true,rollout_at=now()-interval '1 minute'");
  const calls = async () => JSON.parse(await db.query("select coalesce(jsonb_agg(to_jsonb(c) order by id),'[]') from net.calls c"));
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await run(setup); await fn(); });
  const tick = () => run('select private.mail_worker_tick()');
  const rejectsSafe = async () => {
    await assert.rejects(tick, error => {
      assert.match(error.message, /Mail worker scheduling failed/);
      assert.equal(error.message.includes(secret), false);
      assert.equal(error.message.includes('Bearer '), false);
      return true;
    });
    assert.deepEqual(await calls(), []);
  };

  await fresh('setup twice keeps one fixed minute job and leaves rollout/outbox unchanged', async () => {
    const firstId = await db.query("select jobid from cron.job where jobname='cleanstream-mail-delivery'");
    await run(setup);
    assert.deepEqual(JSON.parse(await db.query('select jsonb_agg(to_jsonb(j)) from cron.job j')), [{
      jobid: Number(firstId), jobname: 'cleanstream-mail-delivery', schedule: '* * * * *',
      command: 'select private.mail_worker_tick();', username: 'policy_fixture', active: true,
    }]);
    assert.equal(await db.query('select enabled from private.mail_settings'), 'f');
    assert.equal(await db.query('select rollout_at is null from private.mail_settings'), 't');
    assert.equal(await db.query('select event_key||\'/\'||attempts||\'/\'||state from private.mail_outbox'), 'retained-event/2/uncertain');
    assert.equal(setup.includes(secret), false);
    assert.deepEqual(await calls(), []);
  });

  for (const [label, enabled, rollout] of [
    ['disabled', false, "now()-interval '1 minute'"],
    ['rollout unset', true, 'null'],
    ['rollout in future', true, "now()+interval '1 day'"],
  ]) {
    await fresh(`${label} queues no HTTP and needs no decrypted secret`, async () => {
      await db.query(`update private.mail_settings set enabled=${enabled},rollout_at=${rollout};
        delete from vault.fixture_secrets;`);
      assert.equal(await tick(), '');
      assert.deepEqual(await calls(), []);
    });
  }

  await fresh('enabled tick enqueues one exact worker POST with dedicated bearer and bounded timeout', async () => {
    await enable();
    const id = await tick();
    assert.deepEqual(await calls(), [{ id: Number(id), url: `${project}/functions/v1/mail-delivery`,
      body: {}, params: {}, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${secret}` },
      timeout_milliseconds: 55000 }]);
  });

  await fresh('secret rotation is read at next tick, not embedded in the scheduled command', async () => {
    await enable(); await tick();
    const rotated = `${secret}-rotated`;
    await db.query(`update vault.fixture_secrets set decrypted_secret=${q(rotated)}
      where name='cleanstream_mail_worker_secret'`);
    await tick();
    const recorded = await calls();
    assert.equal(recorded.length, 2);
    assert.equal(recorded[1].headers.Authorization, `Bearer ${rotated}`);
    assert.equal(await db.query("select command from cron.job where jobname='cleanstream-mail-delivery'"), 'select private.mail_worker_tick();');
  });

  for (const name of ['cleanstream_mail_project_url', 'cleanstream_mail_worker_secret']) {
    await fresh(`missing ${name} fails closed without HTTP`, async () => {
      await enable();
      await db.query(`delete from vault.fixture_secrets where name=${q(name)}`);
      await rejectsSafe();
    });
  }
  for (const [label, value] of [
    ['null', null], ['short', 'short'], ['whitespace', ` ${secret}`], ['control', `${secret}\n`],
  ]) {
    await fresh(`${label} worker credential fails closed without HTTP`, async () => {
      await enable();
      await db.query(`update vault.fixture_secrets set decrypted_secret=${value === null ? 'null' : q(value)}
        where name='cleanstream_mail_worker_secret'`);
      await rejectsSafe();
    });
  }
  for (const url of [
    'http://fixture.supabase.co', 'https://attacker.invalid',
    'https://fixture.supabase.co/other', 'https://fixture.supabase.co?next=bad',
  ]) {
    await fresh(`rejects destination ${url} without HTTP`, async () => {
      await enable();
      await db.query(`update vault.fixture_secrets set decrypted_secret=${q(url)} where name='cleanstream_mail_project_url'`);
      await rejectsSafe();
    });
  }

  await fresh('extension error cannot expose the worker bearer in cron diagnostics', async () => {
    await enable();
    await db.query('update net.fixture_fault set enabled=true');
    await rejectsSafe();
  });

  await fresh('application roles cannot execute scheduler and no definer authority is introduced', async () => {
    for (const role of ['anon', 'authenticated', 'service_role']) {
      assert.equal(await db.query(`select has_function_privilege(${q(role)},'private.mail_worker_tick()','EXECUTE')`), 'f');
    }
    assert.equal(await db.query("select prosecdef from pg_proc where oid='private.mail_worker_tick()'::regprocedure"), 'f');
  });

  await fresh('setup refuses conflicting same-name command without replacing it', async () => {
    await db.query("update cron.job set command='select 42;' where jobname='cleanstream-mail-delivery'");
    await assert.rejects(() => run(setup), /already owned by another configuration/);
    assert.equal(await db.query("select command from cron.job where jobname='cleanstream-mail-delivery'"), 'select 42;');
  });

  await fresh('disable twice removes only this schedule, preserves gates, other jobs and outbox', async () => {
    await enable();
    await db.query("select cron.schedule('unrelated-worker','*/5 * * * *','select 42;')");
    await run(disable); await run(disable);
    assert.equal(await db.query('select jobname from cron.job'), 'unrelated-worker');
    assert.equal(await db.query('select enabled from private.mail_settings'), 't');
    assert.equal(await db.query('select event_key||\'/\'||attempts||\'/\'||state from private.mail_outbox'), 'retained-event/2/uncertain');
    await run(setup);
    assert.equal(await db.query("select count(*) from cron.job where jobname='cleanstream-mail-delivery'"), '1');
  });

  await t.test('setup refuses a recognizable existing worker under another job name', async () => {
    await reset();
    await db.query("select cron.schedule('older-mail-worker','* * * * *','select private.mail_worker_tick();')");
    await assert.rejects(() => run(setup), /existing mail worker schedule must be reconciled/);
    assert.equal(await db.query('select jobname from cron.job'), 'older-mail-worker');
  });

  await t.test('setup stops with missing Vault names and creates no schedule', async () => {
    await reset(); await db.query('delete from vault.fixture_secrets');
    await assert.rejects(() => run(setup), /Vault entries are missing or ambiguous/);
    assert.equal(await db.query('select count(*) from cron.job'), '0');
  });

  await t.test('setup refuses unnamed wrapper and direct worker schedules', async () => {
    for (const command of [
      'select private.mail_worker_tick();',
      "select net.http_post(url := 'https://fixture.supabase.co/functions/v1/mail-delivery');",
    ]) {
      await reset();
      await db.query(`select cron.schedule(null,'* * * * *',${q(command)})`);
      await assert.rejects(() => run(setup), /existing mail worker schedule must be reconciled/);
      assert.equal(await db.query('select count(*) from cron.job where jobname is null'), '1');
      assert.equal(await db.query("select count(*) from cron.job where jobname='cleanstream-mail-delivery'"), '0');
      assert.deepEqual(await calls(), []);
    }
  });

  await t.test('setup refuses ambiguous Vault names without choosing a credential', async () => {
    await reset();
    await db.query(`insert into vault.fixture_secrets values('cleanstream_mail_worker_secret',${q(`${secret}-other`)})`);
    await assert.rejects(() => run(setup), /Vault entries are missing or ambiguous/);
    assert.equal(await db.query('select count(*) from cron.job'), '0');
  });

  await t.test('setup stops with missing extension boundary and creates no schedule', async () => {
    await reset();
    await db.query('alter function net.http_post(text,jsonb,jsonb,jsonb,integer) rename to unavailable');
    try {
      await assert.rejects(() => run(setup), /requires existing Cron, pg_net, Vault/);
      assert.equal(await db.query('select count(*) from cron.job'), '0');
    } finally {
      await db.query('alter function net.unavailable(text,jsonb,jsonb,jsonb,integer) rename to http_post');
    }
  });
});
