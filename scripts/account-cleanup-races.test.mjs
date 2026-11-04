// Real independent PostgreSQL sessions are required; PGlite is not lock-race evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';
import { sqlFiles, cleanupPath, read, seedSQL, user, token, uid,
  claimSQL, authContext } from './test-support/account-cleanup.mjs';

test('account cleanup claims serialize with restore and other workers', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  for (const file of [...sqlFiles, cleanupPath]) await db.query(await read(file));
  const reset = async () => {
    await db.query('truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,private.mail_suppression');
    await db.query('truncate auth.users cascade');
    await db.query(seedSQL);
  };
  const requestAt = async () => await db.query(`select deletion_requested_at::text from private.account_lifecycle where user_id='${user}'`);
  const call = async (connection, id, at) => JSON.parse(await connection.query(claimSQL(id, `'${at}'::timestamptz`)));

  await t.test('restore commits first: queued cleanup observes restoration and cannot claim', async () => {
    await reset();
    await db.query("update private.account_lifecycle set deletion_requested_at=now()-interval '719 hours',restore_until=now()+interval '1 hour'");
    const at = await requestAt();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${authContext()} select public.restore_account()`);
    const waiting = call(waiter, token, at);
    await blocked(db, waiter, holder);
    await holder.query('commit');
    assert.deepEqual(await waiting, { claimed: false, reason: 'request_not_pending' });
    assert.equal(await db.query('select count(*) from private.account_cleanup_jobs'), '0');
    await holder.close(); await waiter.close();
  });

  await t.test('claim holds expired request: queued restore still fails and cannot change it', async () => {
    await reset();
    const at = await requestAt();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query('begin');
    assert.equal((await call(holder, token, at)).claimed, true);
    const waiting = waiter.query(`begin; ${authContext()} select public.restore_account(); commit`);
    const rejected = assert.rejects(waiting, { code: 'PT403' });
    await blocked(db, waiter, holder);
    await holder.query('commit'); await rejected;
    assert.equal(await db.query('select restored_at is null from private.account_lifecycle'), 't');
    await holder.close(); await waiter.close();
  });

  await t.test('restore deadline expiring in the real mail trigger rolls back before queued cleanup claims', async () => {
    await reset();
    const holder = await cluster.connect(), restorer = await cluster.connect(), cleaner = await cluster.connect();
    await db.query("update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours'+interval '2 seconds',restore_until=now()+interval '2 seconds'; update private.newsletter_consent set unsubscribed_at=null,suppression_reason=null,confirm_hash=repeat('a',64); update private.mail_outbox set state='ready',last_error=null");
    const at = await requestAt();
    const snapshot = () => db.query(`select jsonb_build_object(
      'lifecycle',(select to_jsonb(l) from private.account_lifecycle l),
      'consent',(select jsonb_agg(to_jsonb(c) order by id) from private.newsletter_consent c),
      'outbox',(select jsonb_agg(to_jsonb(o) order by id) from private.mail_outbox o))`);
    const before = await snapshot();
    try {
      await holder.query('begin; select private.mail_lock()');
      const restoration = restorer.query(`begin; ${authContext()} select public.restore_account(); commit`)
        .then(value => ({ value }), error => ({ error }));
      await blocked(db, restorer, holder);
      const cleanup = call(cleaner, token, at);
      await blocked(db, cleaner, restorer);
      await holder.query('select pg_sleep(2.1); commit');
      const outcome = await restoration;
      assert.equal(outcome.error?.code, 'PT403');
      assert.match(outcome.error.message, /restore_expired/);
      assert.equal((await cleanup).claimed, true);
      assert.equal(await snapshot(), before, 'Failed restore rolls back lifecycle and mail writes; cleanup changes only its job');
    } finally {
      await holder.close(); await restorer.close(); await cleaner.close();
    }
  });

  for (const replay of [false, true]) {
    await t.test(`concurrent ${replay ? 'same-token replay is idempotent' : 'different worker cannot steal live lease'}`, async () => {
      await reset();
      const at = await requestAt();
      const holder = await cluster.connect(), waiter = await cluster.connect();
      await holder.query('begin');
      const first = await call(holder, token, at);
      const waiting = call(waiter, replay ? token : uid(22), at);
      await blocked(db, waiter, holder);
      await holder.query('commit');
      assert.deepEqual(await waiting, replay ? first : { claimed: false, reason: 'lease_active' });
      assert.equal(await db.query('select attempts from private.account_cleanup_jobs'), '1');
      await holder.close(); await waiter.close();
    });
  }

  await t.test('deadline is evaluated after waiting, not at transaction start', async () => {
    await reset();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await waiter.query('begin');
    await db.query("update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours'+interval '1 second',restore_until=now()+interval '1 second'");
    const at = await requestAt();
    assert.equal(await waiter.query("select now()<restore_until from private.account_lifecycle"), 't');
    await holder.query(`begin; select id from public.profiles where id='${user}' for no key update`);
    const waiting = call(waiter, token, at);
    await blocked(db, waiter, holder);
    await holder.query('select pg_sleep(1.1); commit');
    assert.equal((await waiting).claimed, true);
    await waiter.query('commit');
    await holder.close(); await waiter.close();
  });

  await t.test('synthetic lifecycle drift during lock wait invalidates the exact captured request', async () => {
    await reset();
    const at = await requestAt();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; select id from public.profiles where id='${user}' for no key update;
      update private.account_lifecycle set deletion_requested_at=deletion_requested_at+interval '1 minute',
        restore_until=restore_until+interval '1 minute'`);
    const waiting = call(waiter, token, at);
    await blocked(db, waiter, holder);
    await holder.query('commit');
    assert.deepEqual(await waiting, { claimed: false, reason: 'request_not_pending' });
    assert.equal(await db.query('select count(*) from private.account_cleanup_jobs'), '0');
    await holder.close(); await waiter.close();
  });
});
