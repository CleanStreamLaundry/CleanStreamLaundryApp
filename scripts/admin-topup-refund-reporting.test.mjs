import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const customer = uid(1), owner = uid(2), staff = uid(3), session = uid(11), ownerSession = uid(12), factor = uid(20);

test('reporting reads actual voluntary refund and authority migrations without financial writes', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN), db = await cluster.connect();
  const migration = async (file) => db.query(await read(`../supabase/migrations/${file}.sql`));
  const fixture = (await read('../supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS');
  await db.query('create role postgres superuser; set role postgres;');
  await db.query(fixture[0]);
  for (const file of ['20260526010000_wallet_ledger_compliance', '20260803150427_cortina_qr_remote_vend',
    '20260807191723_harden_refund_resolution', '20260929231120_serialize_wallet_financial_writes']) await migration(file);
  await db.query(fixture[1]);
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}', add column last_sign_in_at timestamptz;
    alter table public.profiles add column created_at timestamptz default now();
    alter table public."Location_to_Admin" enable row level security;`);
  for (const file of ['20260929223124_protect_profile_authority', '20260929234955_loyalty_policy_acceptance']) await migration(file);
  await db.query(await read('../supabase/tests/account_admission.fixture.sql'));
  for (const file of ['20260930005456_account_admission', '20260930013417_enforce_profile_terms_admission',
    '20260930024142_protect_location_membership', '20260930063923_recoverable_account_deletion',
    '20260930125554_voluntary_topup_refunds']) await migration(file);
  // Portal-only prerequisites absent from the financial harness. The refund,
  // provenance and wallet schemas above are the actual integrated migrations.
  await db.query(`alter table public."Locations" add column "Name" text, add column "Address" text,
      add column "Latitude" double precision, add column "Longitude" double precision;
    alter table public."Machines" add column "Runtime" integer, add column "Status" text;
    alter table public."Refunds" add column date timestamptz default now();
    create table public."Maintenance"(maint_id text primary key,user_id uuid,category text,
      description text,created_at timestamptz default now(),location text,image_data text);`);
  for (const file of ['20260928135006_admin_portal_operations', '20260928151021_admin_operations_extensions',
    '20260930131557_admin_collection_reporting']) await migration(file);
  const run = async (sql) => { const c = await cluster.connect(); try { return await c.query(sql); } finally { await c.close(); } };
  const call = async (sql, actor = customer) => JSON.parse(await run(`begin;
    set local request.jwt.claims='${JSON.stringify({ sub: actor, session_id: actor === owner ? ownerSession : session,
      role: 'authenticated', aal: actor === owner ? 'aal2' : 'aal1', exp: Math.floor(Date.now()/1000) + 3600 })}';
    set local request.jwt.claim.sub=''; set local role authenticated; ${sql}; commit;`));
  const rpc = async (actor, action, payload = {}) => JSON.parse(await run(`set role service_role;
    select public.admin_portal_data('${actor}','${action}','${JSON.stringify(payload).replaceAll("'", "''")}');`));
  const report = async () => (await rpc(owner, 'overview')).reporting;
  const rows = async (actor = owner, filters = {}) => (await rpc(actor, 'transactions', { filters: { status: 'all', ...filters } })).items;
  const row = async (id) => (await rows()).find((r) => r.id === `load:${id}`);
  const reset = () => db.query(`truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at) values('${customer}',now()),('${owner}',now()),('${staff}',now());
    insert into public.profiles(id,roles) values('${customer}','User'),('${owner}','Owner'),('${staff}','Admin');
    insert into auth.sessions(id,user_id,aal,created_at,factor_id) values
      ('${session}','${customer}','aal1',now()-interval '1 hour',null),('${ownerSession}','${owner}','aal2',now(),'${factor}');
    insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${owner}','totp','verified');
    insert into public."Locations"(id,"Name") values(1,'North'),(2,'South') on conflict do nothing;
    delete from public."Location_to_Admin";
    insert into public."Location_to_Admin" values('${owner}',1),('${staff}',1);
    update private.topup_refund_policy set enabled_at=now()-interval '3 days';`);
  let sequence = 0;
  const load = async ({ live = true, location = 'null', provenance = true, cents = 2000 } = {}) => {
    const intent = `pi_synthetic_${++sequence}`;
    await db.query(`select public.record_wallet_load_from_stripe('${customer}',${cents},'${intent}');`);
    if (provenance) await db.query(`select public.record_topup_refund_provenance('${intent}','${customer}',${cents},
      clock_timestamp()-interval '1 minute','evt_synthetic_${sequence}',${live},${location});`);
    return Number(await db.query(`select id from public.wallet_loads where stripe_payment_intent_id='${intent}';`));
  };
  const request = (id) => call(`select public.request_voluntary_topup_refund(${id})`);
  const review = (id, action = 'approve') => call(`select public.review_voluntary_topup_refund('${id}','${action}')`, owner);
  const prep = (id) => db.query(`select public.prepare_voluntary_topup_refund('${id}');`);
  const reconcile = async (r, status = 'succeeded', live = true) => {
    const intent = await db.query(`select stripe_payment_intent_id from public.wallet_loads where id=${r.load_id};`);
    return db.query(`select public.reconcile_voluntary_topup_refund('${r.id}','re_synthetic_${r.load_id}',
      '${status}','${intent}',${r.principal_cents},'usd',${live});`);
  };
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await fn(); });
  const amounts = (r) => [r.gross_collection_cents, r.refunded_collection_cents, r.net_collection_cents];

  await fresh('new live funding has immutable event/mode evidence; historical is never inferred', async () => {
    const live = await load(), historical = await load({ provenance: false }), sandbox = await load({ live: false });
    assert.equal((await row(live)).environment, 'production');
    assert.equal((await row(live)).environment_evidence, 'stripe_success_event');
    assert.equal((await row(historical)).environment, 'unknown');
    assert.equal((await row(historical)).environment_evidence, 'not_recorded');
    assert.equal((await row(sandbox)).environment, 'sandbox');
    assert.equal((await report()).confirmedCollectionCents, 4000);
    assert.equal((await report()).buckets.filter((b) => b.category === 'wallet_funding').length, 3);
  });
  for (const status of ['requested', 'approved', 'unknown', 'pending']) await fresh(`${status} retains gross but refund/net are unresolved`, async () => {
    const id = await load(), r = await request(id);
    if (status !== 'requested') await review(r.id);
    if (['unknown', 'pending'].includes(status)) await prep(r.id);
    if (status === 'pending') await reconcile(r, 'pending');
    const result = await row(id);
    assert.equal(result.voluntary_refund_status, status);
    assert.deepEqual(amounts(result), [2000, null, null]);
    assert.equal(result.reconciliation, 'refund_or_outcome_unverified');
    assert.equal(result.payment_status, 'unconfirmed');
    assert.equal(result.refund_completed_at, null);
    const summary = await report(); assert.equal(summary.confirmedCollectionCents, 0); assert.equal(summary.unresolvedRecords, 1);
    assert.equal(summary.buckets[0].netCollectionCents, null);
  });
  await fresh('provider-confirmed success and replay reduce original load once, without altering wallet', async () => {
    const id = await load(), r = await request(id); await review(r.id); await prep(r.id); await reconcile(r);
    const wallet = await db.query('select json_agg(row_to_json(w)) from public.wallet_balances w;');
    const result = await row(id);
    assert.deepEqual(amounts(result), [2000, 2000, 0]);
    assert.equal(result.reconciliation, 'refunded_confirmed'); assert.equal(result.payment_status, 'refunded');
    assert.equal(result.refund_reference, `re_synthetic_${id}`); assert.ok(result.refund_completed_at);
    await reconcile(r);
    assert.deepEqual(amounts(await row(id)), [2000, 2000, 0]);
    assert.equal((await rows()).filter((r) => r.id === `load:${id}`).length, 1);
    const summary = await report(); assert.equal(summary.unresolvedRecords, 0);
    assert.equal(summary.buckets[0].grossCollectionCents, 2000); assert.equal(summary.buckets[0].refundedCollectionCents, 2000);
    assert.equal(await db.query('select json_agg(row_to_json(w)) from public.wallet_balances w;'), wallet);
  });
  for (const status of ['denied', 'failed', 'canceled']) await fresh(`${status} released reservation keeps original net collection`, async () => {
    const id = await load(), r = await request(id);
    if (status === 'denied') await review(r.id, 'deny');
    else { await review(r.id); await prep(r.id); await reconcile(r, status); }
    assert.deepEqual(amounts(await row(id)), [2000, 0, 2000]);
    assert.equal((await row(id)).reconciliation, 'recorded');
    assert.equal((await report()).confirmedCollectionCents, 2000);
  });
  await fresh('missing or mismatched immutable success evidence never confirms a refund', async () => {
    const id = await load(), r = await request(id); await review(r.id); await prep(r.id); await reconcile(r);
    await db.query(`update private.topup_refund_provenance set livemode=false where load_id=${id};`);
    assert.deepEqual(amounts(await row(id)), [2000, null, null]);
    await db.query(`delete from private.topup_refund_provenance where load_id=${id};`);
    assert.deepEqual(amounts(await row(id)), [null, null, null]);
    assert.equal((await row(id)).environment, 'unknown');
  });
  await fresh('legacy bookkeeping-only refunded flag still remains unresolved', async () => {
    const id = await load({ provenance: false }); await db.query(`update public.wallet_loads set status='refunded' where id=${id};`);
    assert.deepEqual(amounts(await row(id)), [null, null, null]);
    assert.equal((await row(id)).environment, 'unknown');
  });
  await fresh('immutable location scope applies to Owner loads; Admin gets none', async () => {
    const global = await load(), local = await load({ location: '1' }), foreign = await load({ location: '2' });
    assert.deepEqual((await rows()).map((r) => r.id).sort(), [`load:${global}`, `load:${local}`].sort());
    assert.equal(await row(foreign), undefined); assert.deepEqual(await rows(staff), []);
    assert.deepEqual((await rows(owner, { locationId: 1 })).map((r) => r.id), [`load:${local}`]);
  });
  await fresh('list/export preserve original load business date, not refund date', async () => {
    const id = await load(), r = await request(id); await review(r.id); await prep(r.id); await reconcile(r);
    await db.query(`update public.wallet_loads set created_at='2026-01-01T04:59:59Z' where id=${id};`);
    const filters = { from: '2025-12-31', to: '2025-12-31', status: 'all' };
    const page = await rows(owner, filters), exported = await rpc(owner, 'exportRecords', { dataset: 'transactions', filters });
    assert.deepEqual(page, exported.rows); assert.equal(page.length, 1);
    assert.deepEqual(amounts(page[0]), [2000, 2000, 0]);
    assert.equal((await rows(owner, { ...filters, from: '2026-01-01', to: '2026-01-01' })).length, 0);
    assert.equal((await report()).buckets.length, 0);
  });
  await fresh('read-only service projection does not broaden private-table or client access', async () => {
    await load();
    for (const role of ['anon', 'authenticated', 'service_role']) {
      await assert.rejects(run(`set role ${role}; select * from private.voluntary_topup_refunds;`), /permission denied/);
      await assert.rejects(run(`set role ${role}; select * from private.topup_refund_provenance;`), /permission denied/);
    }
    for (const role of ['anon', 'authenticated']) await assert.rejects(run(`set role ${role}; select * from public.admin_portal_topup_evidence('${owner}');`), /permission denied/);
    assert.equal(await run(`set role service_role; select count(*) from public.admin_portal_topup_evidence('${staff}');`), '0');
    assert.equal(await run(`set role service_role; select count(*) from public.admin_portal_topup_evidence('${customer}');`), '0');
    assert.equal(await run(`set role service_role; select count(*) from public.admin_portal_topup_evidence('${owner}');`), '1');
  });
});
