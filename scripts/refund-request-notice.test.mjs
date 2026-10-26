import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const customer = uid(1), owner = uid(2), other = uid(3), factor = uid(40);
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const hash = 'a'.repeat(64), payload = 'b'.repeat(64);

test('refund request alert reuses transactional outbox without financial writes', { timeout: 180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const migrate = async name => db.query(await read(`../supabase/migrations/${name}.sql`));
  const fixture = (await read('../supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS')[0];
  await db.query(fixture);
  await migrate('20260526010000_wallet_ledger_compliance');
  await migrate('20260807191723_harden_refund_resolution');
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}', add column created_at timestamptz default now();
    alter table public.profiles add column created_at timestamptz default now();`);
  await migrate('20260929223124_protect_profile_authority');
  await migrate('20260929234955_loyalty_policy_acceptance');
  await db.query(await read('../supabase/tests/account_admission.fixture.sql'));
  await migrate('20260930005456_account_admission');
  await migrate('20260930013417_enforce_profile_terms_admission');
  await migrate('20260930063923_recoverable_account_deletion');
  await migrate('20260930125527_newsletter_consent_mail_outbox');
  const grants = () => db.query(`select jsonb_agg(jsonb_build_array(oid::regclass::text,relacl) order by oid)
    from pg_class where relnamespace in ('auth'::regnamespace,'public'::regnamespace) and relkind='r'`);
  const beforeGrants = await grants();
  await migrate('20260930175136_refund_request_notice_outbox');
  await migrate('20261001140307_mail_transactional_postal_split');

  const run = async sql => {
    const c = await cluster.connect();
    try { return await c.query(sql); } finally { await c.close(); }
  };
  const claims = actor => ({ sub: actor, session_id: actor === owner ? uid(12) : actor === other ? uid(13) : uid(11),
    role: 'authenticated', aal: actor === owner ? 'aal2' : 'aal1', exp: Math.floor(Date.now() / 1000) + 3600 });
  const call = async (sql, actor = customer, role = 'authenticated') => {
    const result = await run(`begin;
      set local role ${role};set local request.jwt.claims=${q(JSON.stringify(claims(actor)))};
      set local request.jwt.claim.sub='';${sql};commit;`);
    // psql renders SQL booleans as t/f, unlike JSON-returning RPCs.
    if (result === 't') return true;
    if (result === 'f') return false;
    return JSON.parse(result || 'null');
  };
  const enqueue = (actor = customer, transaction = 41) => call(`select public.enqueue_refund_request_notice(${transaction})`, actor);
  const service = sql => call(sql, customer, 'service_role');
  const snapshot = () => db.query(`select jsonb_build_object(
    'refunds',(select jsonb_agg(to_jsonb(r) order by refund_id) from public."Refunds" r),
    'transactions',(select jsonb_agg(to_jsonb(t) order by id) from public.transactions t),
    'ledger',(select jsonb_agg(to_jsonb(l) order by id) from public.wallet_ledger_entries l),
    'profiles',(select jsonb_agg(to_jsonb(p) order by id) from public.profiles p))`);
  const jobs = async () => JSON.parse(await db.query('select coalesce(jsonb_agg(to_jsonb(o)),\'[]\') from private.mail_outbox o'));
  const reset = async () => {
    await db.query(`truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,
      private.mail_suppression,private.account_lifecycle;
      update private.mail_settings set enabled=false,refund_notice_recipient=null;
      truncate auth.users cascade;
      insert into private.mail_settings(singleton) values(true) on conflict do nothing;
      insert into auth.users(id,email,email_confirmed_at,created_at) values
        ('${customer}','customer@example.test',now(),now()-interval '2 days'),
        ('${owner}','owner@example.test',now(),now()-interval '2 days'),
        ('${other}','other@example.test',now(),now()-interval '2 days');
      insert into public.profiles(id,roles) values('${customer}','User'),('${owner}','Owner'),('${other}','User')
        on conflict(id) do update set roles=excluded.roles;
      insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${owner}','totp','verified');
      insert into auth.sessions(id,user_id,aal,factor_id,created_at) values
        ('${uid(11)}','${customer}','aal1',null,now()-interval '1 hour'),
        ('${uid(12)}','${owner}','aal2','${factor}',now()-interval '1 hour'),
        ('${uid(13)}','${other}','aal1',null,now()-interval '1 hour');
      insert into public.transactions(id,user_id,amount,requested_refund) values(41,'${customer}',25,true);
      insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description)
        values(7,'${customer}',41,25,'Stored <script>reason</script>');
      update private.mail_settings set enabled=true,rollout_at=now()-interval '1 hour',refund_notice_recipient='${owner}';`);
  };
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await fn(); });
  const prepare = o => service(`select public.mail_prepare('${o.id}','${o.lease_id}','${payload}',null,null)`);
  const claim = () => service('select public.mail_claim()');
  const finish = (o, result, id = null) => service(`select public.mail_finish('${o.id}','${o.lease_id}',${q(result)},${id ? q(id) : 'null'})`);

  await t.test('migration keeps existing grants, settings disabled and recipient unset', async () => {
    assert.equal(await grants(), beforeGrants);
    assert.equal(await db.query('select enabled from private.mail_settings'), 'f');
    assert.equal(await db.query('select refund_notice_recipient is null from private.mail_settings'), 't');
    for (const role of ['anon', 'service_role', 'supabase_auth_admin']) {
      assert.equal(await db.query(`select has_function_privilege('${role}','public.enqueue_refund_request_notice(bigint)','execute')`), 'f');
    }
    assert.equal(await db.query(`select has_function_privilege('authenticated','public.enqueue_refund_request_notice(bigint)','execute')`), 't');
    assert.equal(await db.query(`select has_table_privilege('authenticated','private.mail_outbox','INSERT')`), 'f');
  });

  await fresh('server-derived snapshot and exact durable event; claim/ledger remain unchanged', async () => {
    const before = await snapshot();
    assert.deepEqual(await enqueue(), { refund_id: '7', state: 'queued' });
    const [job] = await jobs();
    assert.equal(job.event_key, 'loyalty_credit_requested/7');
    assert.equal(job.user_id, owner);
    assert.equal(job.email, 'owner@example.test');
    assert.equal(job.consent_id, null);
    assert.deepEqual(job.refund_notice, { refund_id: '7', transaction_id: '41', user_id: customer,
      amount: '25', description: 'Stored <script>reason</script>' });
    assert.equal(await snapshot(), before);
  });

  await fresh('concurrent duplicate notices create one event, never another claim', async () => {
    const before = await snapshot();
    const results = await Promise.all(Array.from({ length: 4 }, () => enqueue()));
    assert(results.every(r => r.state === 'queued'));
    assert.equal((await jobs()).length, 1);
    assert.equal(await snapshot(), before);
  });

  await fresh('missing recipient and disabled delivery preserve durable claim', async () => {
    const before = await snapshot();
    await db.query('update private.mail_settings set refund_notice_recipient=null');
    assert.equal((await enqueue()).state, 'recipient_unavailable');
    await db.query(`update private.mail_settings set refund_notice_recipient='${owner}',enabled=false`);
    assert.equal((await enqueue()).state, 'disabled');
    assert.deepEqual(await jobs(), []);
    assert.equal(await snapshot(), before);
  });

  await fresh('foreign caller, missing claim and ambiguous pending rows cannot enqueue', async () => {
    await assert.rejects(() => enqueue(other), e => e.code === 'PT400');
    await assert.rejects(() => enqueue(customer, 42), e => e.code === 'PT400');
    await db.query(`insert into public."Refunds"(refund_id,user_id,transaction_id,amount) values(8,'${customer}',41,25)`);
    await assert.rejects(() => enqueue(), e => e.code === 'PT400');
    assert.deepEqual(await jobs(), []);
  });

  await fresh('transaction ownership is checked independently of refund row ownership', async () => {
    await db.query(`update public.transactions set user_id='${other}' where id=41`);
    await assert.rejects(() => enqueue(), e => e.code === 'PT400');
    assert.deepEqual(await jobs(), []);
  });

  await fresh('expired or revoked caller session cannot enqueue', async () => {
    await db.query(`delete from auth.sessions where id='${uid(11)}'`);
    await assert.rejects(() => enqueue(), e => e.code === 'PT401');
    assert.deepEqual(await jobs(), []);
  });

  for (const [name, sql, state] of [
    ['non-Owner', `update public.profiles set roles='Admin' where id='${owner}'`, 'recipient_unavailable'],
    ['unverified', `update auth.users set email_confirmed_at=null where id='${owner}'`, 'suppressed'],
    ['banned', `update auth.users set banned_until=now()+interval '1 hour' where id='${owner}'`, 'suppressed'],
    ['hard bounce', "insert into private.mail_suppression(email,reason) values('owner@example.test','email.bounced')", 'suppressed'],
  ]) {
    await fresh(`recipient gate: ${name}`, async () => {
      await db.query(sql);
      assert.equal((await enqueue()).state, state);
      assert.deepEqual(await jobs(), []);
    });
  }

  await fresh('Owner demotion after lease is rechecked before dispatch', async () => {
    await enqueue(); const job = await claim();
    await db.query(`update public.profiles set roles='Admin' where id='${owner}'`);
    assert.equal(await prepare(job), false);
    assert.equal((await jobs())[0].state, 'suppressed');
  });

  await fresh('recipient settings switch after lease suppresses without retargeting', async () => {
    await db.query(`update public.profiles set roles='Owner' where id='${other}'`);
    const before = await snapshot();
    await enqueue(); const job = await claim();
    await db.query(`update private.mail_settings set refund_notice_recipient='${other}'`);
    assert.equal(await prepare(job), false);
    assert.equal((await enqueue()).state, 'suppressed');
    const rows = await jobs();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].state, 'suppressed');
    assert.equal(rows[0].user_id, owner);
    assert.equal(rows[0].email, 'owner@example.test');
    assert.equal(rows[0].attempts, 0);
    assert.equal(await snapshot(), before);
  });

  await fresh('customer deletion suppresses queued staff alert without deleting the claim', async () => {
    await enqueue();
    await call('select public.request_account_deletion()');
    assert.equal(await claim(), null);
    assert.equal((await jobs())[0].state, 'suppressed');
    assert.equal(await db.query('select count(*) from public."Refunds" where refund_id=7'), '1');
  });

  await fresh('recipient email change never retargets an existing event', async () => {
    await enqueue();
    await db.query(`update auth.users set email='changed@example.test' where id='${owner}'`);
    assert.equal((await enqueue()).state, 'suppressed');
    assert.equal((await jobs()).length, 1);
    assert.equal((await jobs())[0].email, 'owner@example.test');
  });

  await fresh('resolved or removed claims suppress queued alerts without financial callbacks', async () => {
    await enqueue(); const job = await claim();
    await db.query(`update public."Refunds" set status='denied' where refund_id=7`);
    const before = await snapshot();
    assert.equal(await prepare(job), false);
    assert.equal(await snapshot(), before);
    await db.query('delete from public."Refunds" where refund_id=7');
    assert.equal((await jobs())[0].event_key, 'loyalty_credit_requested/7');
  });

  await fresh('capability and signed-in newsletter unsubscribe leave transactional notice queued', async () => {
    await enqueue();
    await db.query(`insert into private.newsletter_consent(user_id,email,version,consent_text,source,unsubscribe_hash)
      values('${owner}','owner@example.test','newsletter-v1','synthetic','settings','${hash}');
      insert into private.mail_outbox(event_key,kind,user_id,email,consent_id)
      select 'newsletter_confirm/'||id,'newsletter_confirm',user_id,email,id from private.newsletter_consent;`);
    await service(`select public.newsletter_token('unsubscribe','${hash}')`);
    await call('select public.newsletter_withdraw()', owner);
    const rows = await jobs();
    assert.equal(rows.find(r => r.kind === 'refund_request').state, 'ready');
    assert.equal(rows.find(r => r.kind === 'newsletter_confirm').state, 'suppressed');
    const job = await claim();
    assert.equal(job.kind, 'refund_request');
    assert.equal(await prepare(job), true);
  });

  await fresh('existing newsletter confirmation and separate welcome still work', async () => {
    await call("select public.newsletter_request(true,'newsletter-v1','settings')");
    const confirmation = await claim();
    assert.equal(confirmation.kind, 'newsletter_confirm');
    assert.equal(await service(`select public.mail_prepare('${confirmation.id}','${confirmation.lease_id}','${payload}','${hash}','${'d'.repeat(64)}')`), true);
    await finish(confirmation, 'accepted', 'newsletter-provider');
    assert.equal((await service(`select public.newsletter_token('confirm','${hash}')`)).state, 'subscribed');
    const welcome = await claim();
    assert.equal(welcome.kind, 'newsletter_welcome');
    assert.equal(await service(`select public.mail_prepare('${welcome.id}','${welcome.lease_id}','${payload}',null,'${'d'.repeat(64)}')`), true);
  });

  for (const outcome of ['failed', 'uncertain', 'accepted']) {
    await fresh(`enqueue retry preserves ${outcome} attempt and never retries the claim`, async () => {
      const before = await snapshot();
      await enqueue(); const job = await claim(); assert.equal(await prepare(job), true);
      await finish(job, outcome, outcome === 'accepted' ? 'provider-1' : null);
      assert.equal((await enqueue()).state, outcome);
      assert.equal((await jobs()).length, 1);
      assert.equal((await jobs())[0].attempts, 1);
      assert.equal(await claim(), null);
      assert.equal(await snapshot(), before);
    });
  }

  await fresh('rate-limit retry uses same event/id; changed snapshot cannot reuse attempted payload', async () => {
    await enqueue(); const job = await claim(); assert.equal(await prepare(job), true);
    await finish(job, 'rate_limited');
    assert.equal((await enqueue()).state, 'queued');
    assert.equal((await jobs())[0].attempts, 1);
    await db.query("update private.mail_outbox set next_at=now()-interval '1 second'");
    const retry = await claim(); assert.equal(retry.id, job.id);
    assert.equal(await service(`select public.mail_prepare('${retry.id}','${retry.lease_id}','${'c'.repeat(64)}',null,null)`), false);
    assert.equal((await jobs())[0].last_error, 'payload_changed');
  });

  await fresh('webhook complaint suppresses transactional delivery; acceptance is not a business update', async () => {
    const before = await snapshot();
    await enqueue(); const job = await claim(); await prepare(job);
    await finish(job, 'accepted', 'provider-1');
    await service(`select public.mail_record_webhook('event-1','provider-1','email.complained','${job.id}','owner@example.test')`);
    assert.equal((await enqueue()).state, 'suppressed');
    assert.equal(await snapshot(), before);
  });
});
