// PGLITE_MODULE=/path/to/pglite/dist/index.js node --test scripts/cortina-history.test.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, afterEach, test } from 'node:test';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const owner = '11111111-1111-4111-8111-111111111111';
const stranger = '22222222-2222-4222-8222-222222222222';
const admin = '33333333-3333-4333-8333-333333333333';
const session = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const dryer = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
let paymentId;
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const asUser = async (user = owner) => {
  await db.query("select set_config('request.jwt.claim.sub', $1, true)", [user]);
  await db.exec('set local role authenticated');
};
const requestCredit = async (id = paymentId) => one(
  'select public.request_cortina_loyalty_credit($1,$2) as result', [id, 'Machine issue'],
);
const rejects = async (action, pattern) => {
  await db.exec('savepoint rejected_action');
  await assert.rejects(action, pattern);
  await db.exec('rollback to savepoint rejected_action');
};
before(async () => {
  for (const path of [
    'supabase/tests/cortina_history.fixture.sql',
    'supabase/migrations/20260807191723_harden_refund_resolution.sql',
    'supabase/migrations/20260928132533_link_cortina_transaction_history.sql',
  ]) await db.exec(await readFile(new URL(`../${path}`, import.meta.url), 'utf8'));
  paymentId = (await one('select id from public.transactions where cortina_vend_session_id=$1', [session])).id;
});
beforeEach(() => db.exec('begin'));
afterEach(() => db.exec('rollback'));
after(() => db.close());

test('backfills only successful vends, including guest cards, without changing balances', async () => {
  assert.equal((await one('select count(*)::int as n from transactions')).n, 2);
  assert.equal((await one('select balance from profiles where id=$1', [owner])).balance, '7');
  assert.equal((await one('select count(*)::int as n from wallet_ledger_entries')).n, 2);
  assert.deepEqual(await one('select amount,type,description,cortina_status from transactions where id=$1', [paymentId]), {
    amount: '4.0000000000000000', type: 'laundry',
    description: 'Loyalty payment on Washer - Washer 1', cortina_status: 'started',
  });
  assert.equal((await one('select count(*)::int as n from transactions where user_id is null')).n, 1);
});

test('callback replay and queued callers keep one history record', async () => {
  await db.exec('set local role service_role');
  await Promise.all(Array.from({length: 8}, () => db.query(
    'update public.cortina_vend_sessions set status=$1 where id=$2', ['started', session],
  )));
  await db.query('select public.sync_cortina_transaction($1)', [session]);
  assert.equal((await one('select count(*)::int as n from transactions where cortina_vend_session_id=$1', [session])).n, 1);
  assert.equal((await one('select balance from profiles where id=$1', [owner])).balance, '7');
});

test('records final dryer price and completion time, not payment approval', async () => {
  assert.equal((await one('select count(*)::int as n from transactions where cortina_vend_session_id=$1', [dryer])).n, 0);
  await db.query("update cortina_vend_sessions set status='started',completed_at=now() where id=$1", [dryer]);
  const row = await one('select amount,description,created_at=(select completed_at from cortina_vend_sessions where id=$1) as correct_time from transactions where cortina_vend_session_id=$1', [dryer]);
  assert.equal(Number(row.amount), 4.5);
  assert.equal(row.description, 'Card payment on Dryer - Dryer 2');
  assert.equal(row.correct_time, true);
});

test('late reversal preserves history but removes credit eligibility', async () => {
  await db.query("update cortina_vend_sessions set status='refunded' where id=$1", [session]);
  assert.equal((await one('select cortina_status from transactions where id=$1', [paymentId])).cortina_status, 'refunded');
  await asUser();
  await rejects(() => requestCredit(), /not eligible/);
});

test('customers cannot forge a vend link or invoke history synchronization', async () => {
  await asUser();
  await rejects(() => db.query('select public.sync_cortina_transaction($1)', [session]), /permission denied/);
  await rejects(() => db.query("insert into transactions(user_id,amount,type,cortina_vend_session_id,cortina_status) values($1,4,'laundry',$2,'started')", [owner, session]), /row-level security/);
  assert.equal((await db.query('update transactions set amount=99 where id=$1 returning id', [paymentId])).rows.length, 0);
});

test('RLS allows the customer history but not another customer or guest history', async () => {
  await asUser();
  assert.equal((await one('select count(*)::int as n from transactions')).n, 1);
  await db.exec('reset role');
  await asUser(stranger);
  assert.equal((await one('select count(*)::int as n from transactions')).n, 0);
  await rejects(() => requestCredit(), /not available/);
});

test('anonymous credit requests are denied', async () => {
  await db.exec('set local role anon');
  await rejects(() => requestCredit(), /permission denied/);
});

test('credit request is atomic and idempotent, with no wallet credit before approval', async () => {
  await asUser();
  const first = await requestCredit();
  const second = await requestCredit();
  assert.deepEqual(second, first);
  assert.equal(first.result.amount, 4);
  assert.equal((await one('select requested_refund from transactions where id=$1', [paymentId])).requested_refund, true);
  await db.exec('reset role');
  assert.equal((await one('select count(*)::int as n from "Refunds"')).n, 1);
  assert.equal((await one('select refund_attempts from profiles where id=$1', [owner])).refund_attempts, 1);
  assert.equal((await one('select balance from profiles where id=$1', [owner])).balance, '7');
  assert.equal((await one('select count(*)::int as n from wallet_ledger_entries')).n, 2);
});

test('direct requests cannot inflate the amount or claim another customer payment', async () => {
  await asUser();
  await rejects(() => db.query('insert into "Refunds"(user_id,transaction_id,amount,description) values($1,$2,99,$3)', [owner,paymentId,'Bad amount']), /does not match/);
  await db.exec('reset role');
  await asUser(stranger);
  await rejects(() => db.query('insert into "Refunds"(user_id,transaction_id,amount,description) values($1,$2,4,$3)', [stranger,paymentId,'Wrong owner']), /does not match/);
});

test('direct duplicate requests are rejected', async () => {
  await asUser();
  await requestCredit();
  await rejects(() => db.query('insert into "Refunds"(user_id,transaction_id,amount,description) values($1,$2,4,$3)', [owner,paymentId,'Repeat']), /already exists/);
});

test('invalid descriptions and expired payments are rejected', async () => {
  await asUser();
  await rejects(() => db.query('select public.request_cortina_loyalty_credit($1,$2)', [paymentId,' ']), /Enter a reason/);
  await rejects(() => db.query('insert into "Refunds"(user_id,transaction_id,amount,description) values($1,$2,4,$3)', [owner,paymentId,' ']), /Enter a reason/);
  await db.exec('reset role');
  await db.query("update transactions set created_at=now()-interval '15 days' where id=$1", [paymentId]);
  await asUser();
  await rejects(() => requestCredit(), /expired/);
  await rejects(() => db.query('insert into "Refunds"(user_id,transaction_id,amount,description) values($1,$2,4,$3)', [owner,paymentId,'Old vend']), /expired/);
});

test('existing approval creates one loyalty credit, not a card refund or a second debit', async () => {
  await asUser();
  const {result} = await requestCredit();
  await rejects(() => db.query("select public.resolve_refund_request($1,'approved','Test',$2)", [result.refund_id,admin]), /permission denied/);
  await db.exec('reset role; set local role service_role');
  const approve = () => one("select public.resolve_refund_request($1,'approved','Test',$2) as result", [result.refund_id,admin]);
  assert.equal((await approve()).result.alreadyResolved, false);
  assert.equal((await approve()).result.alreadyResolved, true);
  assert.equal((await one('select balance from profiles where id=$1', [owner])).balance, '11.0000000000000000');
  assert.equal((await one('select count(*)::int as n from wallet_ledger_entries')).n, 3);
});

test('late automatic reversal blocks pending manual approval and rolls back its credit', async () => {
  await asUser();
  const {result} = await requestCredit();
  await db.exec('reset role');
  await db.query("update cortina_vend_sessions set status='refunded' where id=$1", [session]);
  await rejects(() => db.query("select public.resolve_refund_request($1,'approved','Test',$2)", [result.refund_id,admin]), /not eligible/);
  assert.equal((await one('select count(*)::int as n from wallet_ledger_entries')).n, 2);
  assert.equal((await one('select status from "Refunds" where refund_id=$1', [result.refund_id])).status, 'pending');
});

test('unrelated legacy history and refund inserts remain supported', async () => {
  await asUser();
  const legacy = await one("insert into transactions(user_id,amount,description,type) values($1,2,'Legacy washer','laundry') returning id", [owner]);
  await db.query('insert into "Refunds"(user_id,transaction_id,amount,description) values($1,$2,2,$3)', [owner,legacy.id,'Legacy reason']);
  assert.equal((await one('select count(*)::int as n from "Refunds"')).n, 1);
});
