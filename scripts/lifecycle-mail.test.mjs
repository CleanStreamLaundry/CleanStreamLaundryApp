import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Sparse author lane reads only the reviewed active prerequisites/harness.
const baseline = process.env.CLEANSTREAM_LIFECYCLE_BASELINE
  ? pathToFileURL(`${resolve(process.env.CLEANSTREAM_LIFECYCLE_BASELINE)}/`)
  : new URL('../', import.meta.url);
const { disposableCluster, blocked } = await import(new URL('scripts/test-support/policy-admission-pg.mjs', baseline));
const read = path => readFile(new URL(path, baseline), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), owner = uid(2), session = uid(11), freshSession = uid(12);
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const payload = 'b'.repeat(64);

test('lifecycle email reuses committed lifecycle state and the existing durable outbox', { timeout: 180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN), db = await cluster.connect();
  await db.query("set timezone='UTC'");
  const migrate = async name => db.query(await read(`supabase/migrations/${name}.sql`));
  await db.query((await read('supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS')[0]);
  await migrate('20260526010000_wallet_ledger_compliance');
  await migrate('20260807191723_harden_refund_resolution');
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}', add column created_at timestamptz default now();
    alter table public.profiles add column created_at timestamptz default now();`);
  await migrate('20260929223124_protect_profile_authority');
  await migrate('20260929234955_loyalty_policy_acceptance');
  await db.query(await read('supabase/tests/account_admission.fixture.sql'));
  await migrate('20260930005456_account_admission');
  await migrate('20260930013417_enforce_profile_terms_admission');
  await migrate('20260930063923_recoverable_account_deletion');
  await migrate('20260930125527_newsletter_consent_mail_outbox');
  await migrate('20260930154911_account_cleanup_claims');
  await migrate('20260930175136_refund_request_notice_outbox');
  const definitions = () => db.query(`select jsonb_agg(jsonb_build_array(oid,pg_get_functiondef(oid),proacl) order by oid)
    from pg_proc where proname in ('request_account_deletion','restore_account','current_account_access',
      'claim_account_cleanup','retry_account_cleanup','preview_account_cleanup','mail_claim','mail_prepare','mail_finish','mail_record_webhook')`);
  const grants = () => db.query(`select jsonb_agg(jsonb_build_array(oid::regclass::text,relacl) order by oid)
    from pg_class where relnamespace in ('auth'::regnamespace,'public'::regnamespace,'private'::regnamespace) and relkind='r'`);
  await migrate('20261001140307_mail_transactional_postal_split');
  const beforeDefinitions = await definitions(), beforeGrants = await grants();
  await db.query(await readFile(new URL('../supabase/migrations/20260930213049_account_lifecycle_mail_outbox.sql', import.meta.url), 'utf8'));
  const run = async sql => {
    const c = await cluster.connect();
    try { return await c.query(`set timezone='UTC';${sql}`); } finally { await c.close(); }
  };
  const context = (sid = session) => `set local request.jwt.claim.sub='';set local role authenticated;
    set local request.jwt.claims=${q(JSON.stringify({ sub: user, session_id: sid, role: 'authenticated', aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600 }))};`;
  const call = (sql, sid = session) => run(`begin;${context(sid)}${sql};commit;`).then(value => JSON.parse(value || 'null'));
  const request = () => call('select public.request_account_deletion()');
  const restore = () => call('select public.restore_account()', freshSession);
  const login = () => db.query(`insert into auth.sessions(id,user_id,aal,created_at)
    values('${freshSession}','${user}','aal1',clock_timestamp())`);
  const jobs = () => db.query("select coalesce(jsonb_agg(to_jsonb(o) order by created_at,id),'[]') from private.mail_outbox o").then(JSON.parse);
  const lifecycle = () => db.query(`select to_jsonb(l) from private.account_lifecycle l where user_id='${user}'`).then(value => JSON.parse(value || 'null'));
  const service = sql => run(`begin;set local role service_role;${sql};commit;`).then(value => value === 't' ? true : value === 'f' ? false : JSON.parse(value || 'null'));
  const claim = () => service('select public.mail_claim()');
  const prepare = o => service(`select public.mail_prepare('${o.id}','${o.lease_id}','${payload}',null,null)`);
  const finish = (o, result) => service(`select public.mail_finish('${o.id}','${o.lease_id}',${q(result)},${result === 'accepted' ? "'synthetic-provider-id'" : 'null'})`);
  const protectedSnapshot = () => db.query(`select jsonb_build_object(
    'auth',(select jsonb_agg(to_jsonb(u) order by id) from auth.users u),
    'profiles',(select jsonb_agg(to_jsonb(p) order by id) from public.profiles p),
    'refunds',(select jsonb_agg(to_jsonb(r) order by refund_id) from public."Refunds" r),
    'transactions',(select jsonb_agg(to_jsonb(x) order by id) from public.transactions x),
    'ledger',(select jsonb_agg(to_jsonb(e) order by id) from public.wallet_ledger_entries e),
    'cleanup',(select jsonb_agg(to_jsonb(c) order by user_id) from private.account_cleanup_jobs c))`);
  const reset = async () => {
    await db.query(`truncate private.account_cleanup_jobs,private.account_lifecycle,
      private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,private.mail_suppression;
      update private.mail_settings set enabled=false,refund_notice_recipient=null;
      truncate auth.users cascade;
      insert into private.mail_settings(singleton) values(true) on conflict do nothing;
      insert into auth.users(id,email,email_confirmed_at,created_at) values
        ('${user}','customer@example.test',now(),now()-interval '2 days'),
        ('${owner}','owner@example.test',now(),now()-interval '2 days');
      insert into public.profiles(id,roles,balance,reward_tracker,refund_attempts) values
        ('${user}','User',42,3,2),('${owner}','Owner',0,0,0)
        on conflict(id) do update set roles=excluded.roles,balance=excluded.balance,reward_tracker=excluded.reward_tracker,refund_attempts=excluded.refund_attempts;
      insert into auth.sessions(id,user_id,aal,created_at) values('${session}','${user}','aal1',now()-interval '1 hour');
      insert into public.transactions(id,user_id,amount,requested_refund) values(41,'${user}',25,true);
      insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description) values(7,'${user}',41,25,'Saved claim');
      update private.mail_settings set enabled=true,rollout_at=now()-interval '1 hour',refund_notice_recipient='${owner}';`);
  };
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });

  await t.test('migration changes no lifecycle/cleanup/worker RPC definitions, table ACLs or activation settings', async () => {
    assert.equal(await definitions(), beforeDefinitions); assert.equal(await grants(), beforeGrants);
    assert.equal(await db.query('select enabled from private.mail_settings'), 'f');
    for (const role of ['anon', 'authenticated', 'service_role', 'supabase_auth_admin']) {
      assert.equal(await db.query(`select has_table_privilege('${role}','private.mail_outbox','INSERT')`), 'f');
      assert.equal(await db.query(`select has_function_privilege('${role}','private.mail_lifecycle_suppression()','EXECUTE')`), 'f');
    }
  });
  await fresh('request atomically queues one server-bound notice and preserves financial/Auth state', async () => {
    const before = await protectedSnapshot(), response = await request(), [job] = await jobs(), row = await lifecycle();
    assert.equal(response.account_state, 'pending_deletion'); assert.equal(job.kind, 'account_deletion_scheduled');
    assert.equal(job.email, 'customer@example.test'); assert.equal(job.user_id, user); assert.equal(job.consent_id, null);
    assert.equal(job.lifecycle_requested_at, row.deletion_requested_at);
    assert.equal(job.lifecycle_restore_until, row.restore_until); assert.equal(job.lifecycle_restored_at, null);
    assert.match(job.event_key, new RegExp(`^account_deletion_scheduled/${user}/.*Z$`));
    assert.equal(await protectedSnapshot(), before);
    assert.equal(await prepare(await claim()), true);
  });
  await fresh('concurrent duplicate deletion requests retain one event and original deadline', async () => {
    await Promise.all([request(), request(), request()]); const before = await lifecycle();
    await request(); assert.deepEqual(await lifecycle(), before); assert.equal((await jobs()).length, 1);
  });
  await fresh('login/status alone never queues restoration; explicit restore does exactly once', async () => {
    await request(); await login(); await call('select public.get_account_lifecycle_status()', freshSession);
    assert.equal((await jobs()).length, 1); const before = await protectedSnapshot();
    assert.equal((await restore()).account_state, 'legacy_active'); await restore();
    const rows = await jobs(), row = await lifecycle(); assert.equal(rows.length, 2);
    assert.equal(rows[0].state, 'suppressed'); assert.equal(rows[1].kind, 'account_restored');
    assert.equal(rows[1].lifecycle_restored_at, row.restored_at); assert.equal(rows[1].state, 'ready');
    assert.equal(await protectedSnapshot(), before);
  });
  await fresh('stale-session restore failure keeps pending notice and creates no restored event', async () => {
    await request(); const before = await jobs();
    await assert.rejects(() => call('select public.restore_account()'), e => e.code === 'PT403');
    assert.deepEqual(await jobs(), before); assert.equal((await lifecycle()).restored_at, null);
  });
  await fresh('transaction rollback leaves no deletion notice or lifecycle request', async () => {
    await run(`begin;${context()}select public.request_account_deletion();rollback;`);
    assert.deepEqual(await jobs(), []); assert.equal(await lifecycle(), null);
  });
  await fresh('rolled-back restoration restores previous pending notice state', async () => {
    await request(); await login(); const before = await jobs();
    await run(`begin;${context(freshSession)}select public.restore_account();rollback;`);
    assert.deepEqual(await jobs(), before); assert.equal((await lifecycle()).restored_at, null);
  });
  await fresh('a later deletion cycle suppresses old restore notice and receives a distinct event key', async () => {
    await request(); await login(); await restore(); const first = await jobs();
    await call('select public.request_account_deletion()', freshSession); const rows = await jobs();
    assert.equal(rows.length, 3); assert.equal(rows[1].state, 'suppressed');
    assert.equal(rows[2].kind, 'account_deletion_scheduled'); assert.equal(rows[2].state, 'ready');
    assert.notEqual(rows[2].event_key, first[0].event_key);
  });
  await fresh('unrelated no-op lifecycle updates do not suppress or duplicate the current event', async () => {
    await request(); await db.query(`update private.account_lifecycle set marketing_suppressed=true where user_id='${user}'`);
    assert.equal((await jobs()).length, 1); assert.equal((await jobs())[0].state, 'ready');
    await login(); await restore(); await db.query(`update private.account_lifecycle set marketing_suppressed=true where user_id='${user}'`);
    assert.equal((await jobs()).length, 2); assert.equal((await jobs())[1].state, 'ready');
  });
  await fresh('restore after leasing deletion notice makes prepare skip the stale notice', async () => {
    await request(); const leased = await claim(); await login(); await restore();
    assert.equal(await prepare(leased), false); assert.equal((await jobs())[0].state, 'suppressed');
    assert.equal((await claim()).kind, 'account_restored');
  });
  await fresh('new deletion after leasing restored notice makes prepare skip that old notice', async () => {
    await request(); await login(); await restore(); const leased = await claim();
    await call('select public.request_account_deletion()', freshSession);
    assert.equal(await prepare(leased), false);
  });
  for (const [name, sql] of [
    ['email change', `update auth.users set email='changed@example.test' where id='${user}'`],
    ['unverified', `update auth.users set email_confirmed_at=null where id='${user}'`],
    ['banned', `update auth.users set banned_until=now()+interval '1 day' where id='${user}'`],
    ['deleted', `update auth.users set deleted_at=now() where id='${user}'`],
    ['bounce', `insert into private.mail_suppression values('customer@example.test','email.bounced',now())`],
    ['missing lifecycle', `delete from private.account_lifecycle where user_id='${user}'`],
  ]) await fresh(`${name} after lease cannot send to an ineligible/currently stale identity`, async () => {
    await request(); const leased = await claim(); await db.query(sql); assert.equal(await prepare(leased), false);
  });
  await fresh('expired server deadline suppresses scheduled notice without claiming cleanup complete', async () => {
    await db.query(`update private.mail_settings set rollout_at=now()-interval '40 days';
      insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
      select '${user}',at-interval '721 hours',at-interval '1 hour' from (select clock_timestamp() at) x`);
    assert.deepEqual(await jobs(), []); assert.equal(await claim(), null);
    assert.equal((await lifecycle()).restored_at, null);
  });
  await fresh('disabled or pre-rollout events do not backfill when delivery is enabled later', async () => {
    await db.query('update private.mail_settings set enabled=false'); await request();
    await db.query('update private.mail_settings set enabled=true'); await request(); assert.deepEqual(await jobs(), []);
    await login(); await restore(); assert.equal((await jobs()).length, 1); assert.equal((await jobs())[0].kind, 'account_restored');
  });
  await fresh('future rollout excludes new events without changing the lifecycle result', async () => {
    await db.query("update private.mail_settings set rollout_at=now()+interval '1 day'");
    assert.equal((await request()).account_state, 'pending_deletion');
    await login(); assert.equal((await restore()).account_state, 'legacy_active');
    assert.deepEqual(await jobs(), []);
  });
  await fresh('unsubscribe suppresses newsletter only, never the restored transactional notice', async () => {
    await request(); await login(); await restore();
    await call('select public.newsletter_withdraw()', freshSession);
    assert.equal((await jobs())[1].state, 'ready');
    assert.equal((await claim()).kind, 'account_restored');
    assert.equal(await db.query('select count(*) from private.newsletter_consent'), '0');
    assert.equal(await db.query("select count(*) from private.mail_outbox where kind='account_welcome'"), '0');
  });
  await fresh('old newsletter unsubscribe link does not cancel scheduled transactional notice', async () => {
    const hash = 'a'.repeat(64);
    await db.query(`insert into private.newsletter_consent(user_id,email,version,consent_text,source,unsubscribe_hash)
      values('${user}','customer@example.test','newsletter-v1','Synthetic consent','settings','${hash}')`);
    await request(); await service(`select public.newsletter_token('unsubscribe','${hash}')`);
    assert.equal((await jobs())[0].state, 'ready'); assert.equal(await prepare(await claim()), true);
  });
  await fresh('existing rate-limit retry preserves job, event, payload and attempt bounds', async () => {
    await request(); const first = await claim(); assert.equal(await prepare(first), true); await finish(first, 'rate_limited');
    await db.query("update private.mail_outbox set next_at=now()-interval '1 second'");
    const retry = await claim(); assert.equal(retry.id, first.id); assert.equal(retry.event_key, first.event_key);
    assert.equal(await prepare(retry), true); await finish(retry, 'accepted');
    assert.equal((await jobs())[0].attempts, 2); assert.equal(await claim(), null);
  });
  await fresh('uncertain outcome is never automatically re-leased or undone by a restore', async () => {
    await request(); const first = await claim(); assert.equal(await prepare(first), true); await finish(first, 'uncertain');
    assert.equal(await claim(), null); await login(); await restore();
    assert.equal((await jobs())[0].state, 'suppressed'); assert.equal((await jobs())[1].kind, 'account_restored');
  });
  await fresh('existing refund_request branch still enqueues, leases and prepares Owner alert', async () => {
    assert.equal((await call('select public.enqueue_refund_request_notice(41)')).state, 'queued');
    const alert = await claim(); assert.equal(alert.kind, 'refund_request'); assert.equal(alert.user_id, owner);
    assert.equal(await prepare(alert), true);
  });
  await fresh('existing refund_request role/settings revalidation remains fail closed', async () => {
    await call('select public.enqueue_refund_request_notice(41)'); const alert = await claim();
    await db.query('update private.mail_settings set refund_notice_recipient=null');
    assert.equal(await prepare(alert), false);
  });
  await fresh('lifecycle shape constraint rejects deadline tampering and permanent-deletion kinds', async () => {
    await request();
    await assert.rejects(() => run("update private.mail_outbox set lifecycle_restore_until=lifecycle_restore_until+interval '1 second'"), e => e.code === '23514');
    await assert.rejects(() => run("update private.mail_outbox set kind='account_deleted'"), e => e.code === '23514');
  });
  await fresh('restore post-lock session revocation rolls back notice enqueue and original suppression', async () => {
    await request(); await login(); const before = await jobs();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      await holder.query('begin;select private.mail_lock();');
      const outcome = waiter.query(`begin;${context(freshSession)}select public.restore_account();commit;`)
        .then(value => ({ value }), error => ({ error }));
      await blocked(db, waiter, holder);
      await db.query(`delete from auth.sessions where id='${freshSession}'`);
      await holder.query('commit;'); const result = await outcome;
      assert.equal(result.error?.code, 'PT401'); assert.deepEqual(await jobs(), before);
      assert.equal((await lifecycle()).restored_at, null);
    } finally { await holder.close(); await waiter.close(); }
  });
});
