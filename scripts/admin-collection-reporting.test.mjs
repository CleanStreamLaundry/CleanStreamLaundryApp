import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = uid(1), staff = uid(2), customer = uid(3), other = uid(4);
const sid = '10000000-0000-4000-8000-000000000001';
const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('admin collection reporting on disposable PostgreSQL', async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  for (const path of [
    '../supabase/tests/admin_collection_reporting.fixture.sql',
    '../supabase/migrations/20260928135006_admin_portal_operations.sql',
    '../supabase/migrations/20260928151021_admin_operations_extensions.sql',
    '../supabase/migrations/20260930131557_admin_collection_reporting.sql',
  ]) await db.query(await read(path));
  const rpc = async (actor, action, payload = {}) => JSON.parse(await db.query(
    `select public.admin_portal_data('${actor}','${action}','${JSON.stringify(payload).replaceAll("'", "''")}');`,
  ));
  const overview = () => rpc(owner, 'overview');
  const rows = async (actor = owner, filters = {}) => (await rpc(actor, 'transactions', { filters: { status: 'all', ...filters } })).items;
  const session = async () => (await rows()).find((r) => r.id === `vend:${sid}`);
  const isolated = async (fn) => { await db.query('begin;'); try { await fn(); } finally { await db.query('rollback;'); } };
  const card = () => db.query(`update public.cortina_vend_sessions set status='started',stripe_payment_intent_id='pi_card',nayax_transaction_id='987',nayax_rrn='rrn_987' where id='${sid}';
    insert into public.cortina_vend_events(session_id,source,event_type,event_key,payload) values('${sid}','stripe','payment_succeeded','evt_card','{"payment_intent_id":"pi_card"}');`);
  const load = (id = 1, intent = 'pi_load') => db.query(`insert into public.wallet_loads(id,user_id,amount_cents,paid_amount_cents,promo_amount_cents,stripe_payment_intent_id) values(${id},'${customer}',2000,2000,500,'${intent}');`);

  await t.test('linked history and Nayax references remain one Stripe collection', () => isolated(async () => {
    await card();
    const r = await session();
    assert.equal(r.collection_provider, 'stripe'); assert.equal(r.vend_provider, 'nayax');
    assert.equal(r.nayax_transaction_reference, '987'); assert.equal(r.nayax_rrn, 'rrn_987');
    assert.equal(r.amount_cents, 350); assert.equal(r.net_collection_cents, 350);
    assert.equal((await rows()).filter((r) => r.ledger_id === '1').length, 1);
    assert.equal((await overview()).reporting.confirmedCollectionCents, 350);
    assert.equal((await overview()).reporting.operationalVendCents, 350);
  }));
  await t.test('two wallet and one Stripe four-dollar vends are $12 operational, only $4 newly collected', () => isolated(async () => {
    await card();
    await db.query(`update public.cortina_vend_sessions set amount_cents=400 where id='${sid}';
      insert into public.wallet_redemptions values(11,400,400,0,'succeeded'),(12,400,300,100,'succeeded');
      insert into public.cortina_vend_sessions(id,machine_id,amount_cents,payment_method,channel,status,transaction_id,wallet_redemption_id,nayax_transaction_id,nayax_rrn)
      values('${uid(11)}',1,400,'wallet','app','started','SYNTHETIC-11',11,'synthetic-nayax-11','synthetic-rrn-11'),
        ('${uid(12)}',1,400,'wallet','app','started','SYNTHETIC-12',12,'synthetic-nayax-12','synthetic-rrn-12');
      insert into public.transactions values(11,'${customer}',4,'Loyalty payment on Washer - Washer 1',now(),'${uid(11)}'),
        (12,'${customer}',4,'Loyalty payment on Dryer - Dryer 1',now(),'${uid(12)}');
      insert into public.cortina_vend_events(session_id,source,event_type,event_key,payload)
      values('${sid}','stripe','payment_succeeded','evt_same_payment_replay','{"payment_intent_id":"pi_card"}');`);
    const report = (await overview()).reporting;
    assert.equal(report.confirmedCollectionCents, 400);
    assert.equal(report.walletSpendCents, 800);
    assert.equal(report.operationalVendCents, 1200);
    assert.equal((await rows()).filter((r) => r.source === 'machine_payment').length, 3);
    assert.equal(report.nayaxDirect.netCollectionCents, null);
  }));
  await t.test('named wallet history and promo spend are not new cash', () => isolated(async () => {
    await db.query(`insert into public.wallet_redemptions values(1,350,100,250,'succeeded');
      update public.cortina_vend_sessions set payment_method='wallet',status='started',wallet_redemption_id=1 where id='${sid}';
      update public.transactions set description='Loyalty payment on Washer - Washer 01' where id=1;
      insert into public.transactions values(4,'${customer}',8,'Loyalty payment on Dryer - Dryer 99',now(),null);`);
    const report = await overview();
    assert.equal(report.total, 0); assert.equal(report.reporting.walletSpendCents, 350);
    assert.equal(report.reporting.promoSpendCents, 250);
    assert.equal((await rows()).find((r) => r.id === 'legacy:4').category, 'wallet_spend');
    assert.equal((await rows()).find((r) => r.id === 'legacy:4').wallet_spend_cents, null);
  }));
  await t.test('wallet loads include paid principal once and keep bonus separate', () => isolated(async () => {
    await load();
    const report = await overview();
    assert.equal(report.total, 20); assert.equal(report.reporting.promoIssuedCents, 500);
    assert.equal((await rows()).find((r) => r.source === 'wallet_load').net_collection_cents, 2000);
    assert.equal((await rows(staff)).some((r) => r.source === 'wallet_load'), false);
    assert.equal((await rpc(staff, 'overview')).total, 0);
  }));
  for (const status of ['refunded', 'voided', 'support_required', 'failed', 'timed_out']) {
    await t.test(`late ${status} retains gross evidence without asserting a settled refund/net`, () => isolated(async () => {
      await card(); await db.query(`update public.cortina_vend_sessions set status='${status}',stripe_refund_id='re_pending' where id='${sid}';`);
      const r = await session();
      assert.equal(r.gross_collection_cents, 350); assert.equal(r.refunded_collection_cents, null);
      assert.equal(r.net_collection_cents, null); assert.equal(r.payment_status, 'unconfirmed');
      assert.equal((await overview()).total, 0);
    }));
  }
  await t.test('voided wallet redemption reports no spend or new collection', () => isolated(async () => {
    await db.query(`insert into public.wallet_redemptions values(1,350,100,250,'void');
      update public.cortina_vend_sessions set payment_method='wallet',status='voided',wallet_redemption_id=1 where id='${sid}';`);
    assert.equal((await session()).wallet_spend_cents, 0);
    assert.equal((await session()).reconciliation, 'reversed');
  }));
  await t.test('stable provider overlap suppresses second collection, equal amounts do not', () => isolated(async () => {
    await card(); await load(1, 'pi_card'); await load(2, 'pi_different');
    assert.equal((await session()).reconciliation, 'linked_collection');
    assert.equal((await session()).net_collection_cents, 0);
    assert.equal((await overview()).reporting.confirmedCollectionCents, 4000);
    assert.equal((await rows()).filter((r) => r.source === 'wallet_load').length, 2);
  }));
  await t.test('unknown legacy, environment and disconnected feed are not fabricated', () => isolated(async () => {
    await card();
    await db.query(`insert into public.cortina_machine_config(machine_id,environment,is_enabled,review_required) values(1,'production',false,true);`);
    const report = await overview();
    assert.equal((await session()).environment, 'unknown');
    assert.deepEqual(report.reporting.nayaxDirect, { availability: 'not_connected', lastSyncAt: null, transactionCount: null, netCollectionCents: null });
    const legacy = (await rows()).find((r) => r.id === 'legacy:3');
    assert.equal(legacy.category, 'unknown_legacy'); assert.equal(legacy.net_collection_cents, null);
    assert.equal(report.total, 3.5);
  }));
  await t.test('non-USD values stay separate and never enter USD cash/vend totals', () => isolated(async () => {
    await card(); await db.query(`update public.cortina_vend_sessions set currency='CAD' where id='${sid}';`);
    const report = await overview(); assert.equal(report.total, 0); assert.equal(report.reporting.operationalVendCents, 0);
    assert.equal(report.reporting.buckets.find((b) => b.currency === 'CAD').netCollectionCents, 350);
  }));
  await t.test('list and export share inclusive business dates, scope, categories and IDs', () => isolated(async () => {
    await card();
    await db.query(`update public.cortina_vend_sessions set created_at='2026-01-01T04:59:59Z' where id='${sid}';`);
    const filters = { from: '2025-12-31', to: '2025-12-31', category: 'machine_collection', status: 'all' };
    const list = await rows(owner, filters), exported = await rpc(owner, 'exportRecords', { dataset: 'transactions', filters });
    assert.deepEqual(exported.rows, list); assert.equal(list.length, 1);
    assert.equal((await rows(owner, { ...filters, from: '2026-01-01', to: '2026-01-01' })).length, 0);
    assert.equal((await rows(other, filters)).length, 0);
    assert.equal((await rows(owner, { ...filters, locationId: 3 })).length, 0);
  }));
  await t.test('30 business-day overview is end-exclusive with exact integer cents', () => isolated(async () => {
    await card(); await db.query(`update public.cortina_vend_sessions set amount_cents=101,created_at=((now() at time zone 'America/Indiana/Indianapolis')::date-29)::timestamp at time zone 'America/Indiana/Indianapolis' where id='${sid}';`);
    assert.equal((await overview()).reporting.confirmedCollectionCents, 101);
    assert.equal((await overview()).daily[0].amount, 1.01);
    await db.query(`update public.cortina_vend_sessions set created_at=created_at-interval '1 microsecond' where id='${sid}';`);
    assert.equal((await overview()).total, 0);
    await db.query(`update public.cortina_vend_sessions set created_at=((now() at time zone 'America/Indiana/Indianapolis')::date+1)::timestamp at time zone 'America/Indiana/Indianapolis' where id='${sid}';`);
    assert.equal((await overview()).total, 0);
  }));
  await t.test('refund/void load records do not masquerade as confirmed cash', () => isolated(async () => {
    await load(); await db.query("update public.wallet_loads set status='refunded';");
    assert.equal((await overview()).total, 0);
    assert.equal((await rows()).find((r) => r.source === 'wallet_load').net_collection_cents, null);
  }));
  await t.test('service-only RPC grants and role gate survive wrapper changes', async () => {
    for (const role of ['anon', 'authenticated']) {
      const c = await cluster.connect();
      await assert.rejects(c.query(`set role ${role}; select public.admin_portal_data('${owner}','overview','{}');`), /permission denied/);
      await c.close();
    }
    const c = await cluster.connect();
    await assert.rejects(c.query(`set role service_role; select public.admin_portal_data('${customer}','overview','{}');`), /Owner or Admin/);
    await c.close();
    const service = await cluster.connect();
    assert.equal(JSON.parse(await service.query(`set role service_role; select public.admin_portal_data('${owner}','overview','{}');`)).reporting.version, 1);
    await service.close();
  });
});
