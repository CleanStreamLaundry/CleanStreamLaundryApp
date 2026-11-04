import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, afterEach, before, beforeEach, test } from 'node:test';

const { PGlite } = await import(process.env.PGLITE_MODULE);
const db = new PGlite();
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
const consume = async (bucket) => (await one('select public.consume_cortina_request_capacity($1) as decision', [bucket])).decision;
const owner = async (action) => {
  await db.exec('reset role');
  try { return await action(); } finally { await db.exec('set local role service_role'); }
};
const rows = () => owner(async () => (await db.query('select * from private.cortina_request_capacity order by bucket')).rows);
const reject = async (action, pattern) => {
  await db.exec('savepoint rejected');
  await assert.rejects(action, pattern);
  await db.exec('rollback to savepoint rejected');
};

before(async () => {
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema private;
    grant usage on schema private to anon, authenticated, service_role;
    alter default privileges in schema private grant all on tables to public, anon, authenticated, service_role;`);
  await db.exec(await readFile(new URL('../supabase/migrations/20260930225326_cortina_request_capacity.sql', import.meta.url), 'utf8'));
});
beforeEach(() => db.exec(`begin;
  -- Hold time ahead only in this fixture so burst assertions never depend on runner speed.
  update private.cortina_request_capacity set updated_at=clock_timestamp()+interval '1 day';
  set local role service_role;`));
afterEach(() => db.exec('rollback'));
after(() => db.close());

test('exactly three fixed buckets are seeded at approved development burst capacities', async () => {
  assert.deepEqual((await rows()).map(({ bucket, tokens }) => ({ bucket, tokens: Number(tokens) })),
    [{ bucket: 'card', tokens: 5 }, { bucket: 'quote', tokens: 30 }, { bucket: 'status', tokens: 120 }]);
});

test('private RLS and RPC privileges override permissive inherited default grants', async () => {
  const relation = await one("select relrowsecurity from pg_class where oid='private.cortina_request_capacity'::regclass");
  assert.equal(relation.relrowsecurity, true);
  const fn = await one("select prosecdef,proconfig,pronargs from pg_proc where oid='public.consume_cortina_request_capacity(text)'::regprocedure");
  assert.equal(fn.prosecdef, true);
  assert.equal(fn.pronargs, 1);
  assert(fn.proconfig.includes('search_path=""'));
  assert(fn.proconfig.includes('lock_timeout=500ms'));
  for (const role of ['anon', 'authenticated', 'service_role']) {
    const acl = await one(`select has_function_privilege($1,'public.consume_cortina_request_capacity(text)','EXECUTE') as rpc,
      has_table_privilege($1,'private.cortina_request_capacity','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') as direct`, [role]);
    assert.deepEqual(acl, { rpc: role === 'service_role', direct: false });
  }
});

for (const role of ['anon', 'authenticated']) {
  test(`${role} cannot consume capacity via RPC or table access`, async () => {
    await db.exec(`set local role ${role}`);
    await reject(() => consume('card'), /permission denied/);
    await reject(() => db.query('select * from private.cortina_request_capacity'), /permission denied/);
    await reject(() => db.query("update private.cortina_request_capacity set tokens=5 where bucket='card'"), /permission denied/);
  });
}

test('service role may consume but cannot replenish, delete, create or directly read bucket rows', async () => {
  for (const sql of ['select * from private.cortina_request_capacity',
    "update private.cortina_request_capacity set tokens=5 where bucket='card'",
    "delete from private.cortina_request_capacity where bucket='card'",
    "insert into private.cortina_request_capacity values('attacker',1,clock_timestamp())",
    'truncate private.cortina_request_capacity']) {
    await reject(() => db.query(sql), /permission denied/);
  }
  assert.deepEqual(await consume('card'), { allowed: true, retry_after_seconds: 0 });
});

test('unsupported, null and caller-shaped identities cannot create or modify bucket rows', async () => {
  const original = await rows();
  for (const key of [null, '', 'card ', 'CARD', 'wallet', 'confirm', 'user:uuid', '127.0.0.1']) {
    await reject(() => consume(key), /Invalid Cortina capacity bucket/);
  }
  assert.deepEqual(await rows(), original);
});

test('missing seeded row fails closed and is never recreated by a request', async () => {
  await owner(() => db.query("delete from private.cortina_request_capacity where bucket='card'"));
  await reject(() => consume('card'), /Cortina capacity unavailable/);
  assert.deepEqual((await rows()).map((row) => row.bucket), ['quote', 'status']);
});

test('a serialized burst grants exactly capacity and then returns bounded Retry-After', async () => {
  for (const [bucket, capacity, retry] of [['quote', 30, 1], ['card', 5, 6], ['status', 120, 1]]) {
    const result = await db.query('select public.consume_cortina_request_capacity($1) as decision from generate_series(1,$2)', [bucket, capacity + 3]);
    assert.deepEqual(result.rows.slice(0, capacity).map((row) => row.decision),
      Array.from({ length: capacity }, () => ({ allowed: true, retry_after_seconds: 0 })));
    assert.deepEqual(result.rows.slice(capacity).map((row) => row.decision),
      Array.from({ length: 3 }, () => ({ allowed: false, retry_after_seconds: retry })));
  }
});

test('denial does not change tokens or timestamps or extend the next refill', async () => {
  await owner(() => db.exec('update private.cortina_request_capacity set tokens=0'));
  const original = await rows();
  for (let n = 0; n < 3; n++) assert.deepEqual(await consume('card'), { allowed: false, retry_after_seconds: 6 });
  assert.deepEqual(await rows(), original);
});

test('fractional tokens retain credit and round Retry-After upward', async () => {
  await owner(() => db.exec("update private.cortina_request_capacity set tokens=0.5 where bucket='card'"));
  assert.deepEqual(await consume('card'), { allowed: false, retry_after_seconds: 3 });
  await owner(() => db.exec("update private.cortina_request_capacity set tokens=0.99 where bucket='card'"));
  assert.deepEqual(await consume('card'), { allowed: false, retry_after_seconds: 1 });
});

test('long idle time refills only to each burst cap', async () => {
  await owner(() => db.exec("update private.cortina_request_capacity set tokens=0,updated_at=clock_timestamp()-interval '1 day'"));
  for (const bucket of ['quote', 'card', 'status']) assert.equal((await consume(bucket)).allowed, true);
  assert.deepEqual((await rows()).map(({ bucket, tokens }) => ({ bucket, tokens: Number(tokens) })),
    [{ bucket: 'card', tokens: 4 }, { bucket: 'quote', tokens: 29 }, { bucket: 'status', tokens: 119 }]);
});

test('partial refill uses database elapsed time at the exact approved per-minute rates', async () => {
  for (const [bucket, rate, seconds] of [['quote', 120, 1], ['card', 10, 12], ['status', 1200, 0.1]]) {
    const start = await owner(() => one("update private.cortina_request_capacity set tokens=0,updated_at=clock_timestamp()-($2 * interval '1 second') where bucket=$1 returning updated_at::text as t", [bucket, seconds]));
    assert.equal((await consume(bucket)).allowed, true);
    const result = await owner(() => one(`select tokens::float8 as tokens,
      least(case bucket when 'quote' then 30 when 'card' then 5 else 120 end,
        extract(epoch from (updated_at-$2::timestamptz))*$3/60)-1 as expected
      from private.cortina_request_capacity where bucket=$1`, [bucket, start.t, rate]));
    assert(Math.abs(result.tokens - Number(result.expected)) < 1e-9);
  }
});

test('backward clock interval cannot manufacture tokens or a negative Retry-After', async () => {
  await owner(() => db.exec("update private.cortina_request_capacity set tokens=0,updated_at=clock_timestamp()+interval '1 day'"));
  assert.deepEqual(await consume('card'), { allowed: false, retry_after_seconds: 6 });
});

test('quote and card depletion leave the separate status/recovery bucket untouched', async () => {
  const status = (await rows()).find((row) => row.bucket === 'status');
  await owner(() => db.exec("update private.cortina_request_capacity set tokens=0 where bucket in ('quote','card')"));
  assert.equal((await consume('quote')).allowed, false);
  assert.equal((await consume('card')).allowed, false);
  assert.deepEqual((await rows()).find((row) => row.bucket === 'status'), status);
  assert.equal((await consume('status')).allowed, true);
});

test('database rollback restores consumed capacity without touching any financial table', async () => {
  const original = await rows();
  await db.exec('savepoint attempt');
  assert.equal((await consume('card')).allowed, true);
  await db.exec('rollback to savepoint attempt');
  assert.deepEqual(await rows(), original);
});

test('RPC accepts no caller-supplied capacity, timestamp or refill parameters', async () => {
  const original = await rows();
  await reject(() => db.query("select public.consume_cortina_request_capacity('card',100000)"), /does not exist/);
  assert.deepEqual(await rows(), original);
});

test('table constraints bound cardinality and reject invalid numeric or infinite time states', async () => {
  await db.exec('reset role');
  for (const sql of ["insert into private.cortina_request_capacity values('attacker',1,clock_timestamp())",
    "insert into private.cortina_request_capacity values('card',5,clock_timestamp())",
    "update private.cortina_request_capacity set tokens=-1 where bucket='card'",
    "update private.cortina_request_capacity set tokens=6 where bucket='card'",
    "update private.cortina_request_capacity set tokens='NaN'::numeric where bucket='card'",
    "update private.cortina_request_capacity set updated_at='infinity' where bucket='card'"]) {
    await reject(() => db.query(sql), /constraint/);
  }
});
