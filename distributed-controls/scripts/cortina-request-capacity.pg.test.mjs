import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const table = 'private.cortina_request_capacity';
const consume = "select public.consume_cortina_request_capacity('card');";
const settle = (promise) => promise.then((value) => ({ value }), (error) => ({ error }));
const success = (result) => { assert.ifError(result.error); return JSON.parse(result.value); };

test('distributed capacity across independent PostgreSQL connections', { timeout: 90000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const observer = await cluster.connect();
  await db.query(await read('./test-support/cortina-request-capacity.fixture.sql'));
  await db.query('set role capacity_owner;');
  await db.query(await read('../supabase/migrations/20260930225326_cortina_request_capacity.sql'));
  await db.query('reset role;');
  assert.equal(await db.query(`select not r.rolsuper and not r.rolbypassrls
    from pg_proc p join pg_roles r on r.oid=p.proowner
    where p.oid='public.consume_cortina_request_capacity(text)'::regprocedure;`), 't');

  const snapshot = () => db.query(`select jsonb_agg(to_jsonb(c) order by bucket) from ${table} c;`);
  const reset = () => db.query(`update ${table} set tokens=case bucket when 'quote' then 30 when 'card' then 5 else 120 end,
    updated_at=clock_timestamp()+interval '1 day';`);
  const service = async () => {
    const session = await cluster.connect();
    await session.query('set role service_role;');
    return session;
  };

  await t.test('eight independent concurrent consumes admit exactly the five-token burst', async () => {
    await reset();
    const holder = await cluster.connect();
    const workers = [];
    try {
      for (let n = 0; n < 8; n++) workers.push(await service());
      assert.equal(new Set(workers.map((worker) => worker.pid)).size, 8);
      await holder.query(`begin; select bucket from ${table} where bucket='card' for update;`);
      // Establish a direct blocker before other consumers can enter the tuple queue.
      const pending = [settle(workers[0].query(consume))];
      await blocked(observer, workers[0], holder);
      pending.push(...workers.slice(1).map((worker) => settle(worker.query(consume))));
      await holder.query('commit;');
      const decisions = (await Promise.all(pending)).map(success);
      assert.equal(decisions.filter((decision) => decision.allowed).length, 5);
      assert.equal(decisions.filter((decision) => !decision.allowed).length, 3);
      for (const decision of decisions) assert.deepEqual(decision, decision.allowed
        ? { allowed: true, retry_after_seconds: 0 }
        : { allowed: false, retry_after_seconds: 6 });
      assert.deepEqual(JSON.parse(await snapshot()).map(({ bucket, tokens }) => ({ bucket, tokens })),
        [{ bucket: 'card', tokens: 0 }, { bucket: 'quote', tokens: 30 }, { bucket: 'status', tokens: 120 }]);
      const beforeDenied = await snapshot();
      assert.deepEqual(JSON.parse(await workers[0].query(consume)), { allowed: false, retry_after_seconds: 6 });
      assert.equal(await snapshot(), beforeDenied);
    } finally {
      await holder.close();
      for (const worker of workers) await worker.close();
    }
  });

  await t.test('real lock timeout returns55P03 and leaves tokens unchanged after release', async () => {
    await reset();
    const original = await snapshot();
    const holder = await cluster.connect();
    const waiting = await service();
    try {
      await holder.query(`begin; select bucket from ${table} where bucket='card' for update;`);
      const pending = settle(waiting.query(consume));
      await blocked(observer, waiting, holder);
      const result = await pending;
      assert(result.error, 'The deployed500ms lock timeout must refuse the blocked consume');
      assert.equal(result.error.code, '55P03', result.error.message);
      await holder.query('rollback;');
      assert.equal(await snapshot(), original);
      const retry = await service();
      try {
        assert.deepEqual(JSON.parse(await retry.query(consume)), { allowed: true, retry_after_seconds: 0 });
        assert.equal(await db.query(`select tokens from ${table} where bucket='card';`), '4');
      } finally { await retry.close(); }
    } finally { await holder.close(); await waiting.close(); }
  });

  await t.test('cancelled waiter and disconnected uncommitted consumer cannot leak token debits', async () => {
    await reset();
    const original = await snapshot();
    const holder = await cluster.connect();
    const waiting = await service();
    try {
      await holder.query(`begin; select bucket from ${table} where bucket='card' for update;`);
      const pending = settle(waiting.query(consume));
      await blocked(observer, waiting, holder);
      assert.equal(await observer.query(`select pg_cancel_backend(${waiting.pid});`), 't');
      const result = await pending;
      assert(result.error);
      assert.equal(result.error.code, '57014', result.error.message);
      await holder.query('rollback;');
      assert.equal(await snapshot(), original);
    } finally { await holder.close(); await waiting.close(); }

    const disconnected = await service();
    try {
      assert.deepEqual(JSON.parse(await disconnected.query(`begin; ${consume}`)), { allowed: true, retry_after_seconds: 0 });
      // psql disconnects while the transaction is open; the real backend rolls it back.
    } finally { await disconnected.close(); }
    const next = await service();
    try {
      assert.deepEqual(JSON.parse(await next.query(consume)), { allowed: true, retry_after_seconds: 0 });
      assert.equal(await db.query(`select tokens from ${table} where bucket='card';`), '4');
    } finally { await next.close(); }
  });

  await t.test('refill timestamp and elapsed credit are sampled after the observed lock wait', async () => {
    await reset();
    const anchor = await db.query(`update ${table} set tokens=1.5,updated_at=clock_timestamp()
      where bucket='card' returning updated_at::text;`);
    const holder = await cluster.connect();
    const waiting = await service();
    try {
      await holder.query(`begin; select bucket from ${table} where bucket='card' for update;`);
      const transactionStart = await waiting.query('begin; select transaction_timestamp()::text;');
      const pending = settle(waiting.query(`${consume} commit;`));
      await blocked(observer, waiting, holder);
      const releaseBoundary = await holder.query('select clock_timestamp()::text; commit;');
      assert.deepEqual(success(await pending), { allowed: true, retry_after_seconds: 0 });
      const proof = JSON.parse(await db.query(`select jsonb_build_object(
        'after_release',updated_at >= '${releaseBoundary}'::timestamptz,
        'after_transaction_start',updated_at > '${transactionStart}'::timestamptz,
        'credited_wait',tokens > 0.5,
        'exact_refill',tokens = least(5,1.5+extract(epoch from (updated_at-'${anchor}'::timestamptz))*10/60)-1)
        from ${table} where bucket='card';`));
      assert.deepEqual(proof, { after_release: true, after_transaction_start: true, credited_wait: true, exact_refill: true });
    } finally { await holder.close(); await waiting.close(); }
  });
});
