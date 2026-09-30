import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const customer = uid(1), owner = uid(2), staff = uid(3);
const customerSession = uid(11), ownerSession = uid(12), factor = uid(20);

test('independent Owner refund/reporting acceptance on integrated migrations', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const migrate = async (name) => db.query(await read(`../supabase/migrations/${name}.sql`));
  const fixture = (await read('../supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS');
  await db.query('create role postgres superuser; set role postgres;');
  await db.query(fixture[0]);
  for (const name of ['20260526010000_wallet_ledger_compliance', '20260803150427_cortina_qr_remote_vend',
    '20260807191723_harden_refund_resolution', '20260929231120_serialize_wallet_financial_writes']) await migrate(name);
  await db.query(fixture[1]);
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}', add column last_sign_in_at timestamptz;
    alter table public.profiles add column created_at timestamptz default now();
    alter table public."Location_to_Admin" enable row level security;`);
  for (const name of ['20260929223124_protect_profile_authority', '20260929234955_loyalty_policy_acceptance']) await migrate(name);
  await db.query(await read('../supabase/tests/account_admission.fixture.sql'));
  for (const name of ['20260930005456_account_admission', '20260930013417_enforce_profile_terms_admission',
    '20260930024142_protect_location_membership', '20260930063923_recoverable_account_deletion',
    '20260930125554_voluntary_topup_refunds']) await migrate(name);
  await db.query(`alter table public."Locations" add column "Name" text, add column "Address" text,
      add column "Latitude" double precision, add column "Longitude" double precision;
    alter table public."Machines" add column "Runtime" integer, add column "Status" text;
    alter table public."Refunds" add column date timestamptz default now();
    create table public."Maintenance"(maint_id text primary key,user_id uuid,category text,
      description text,created_at timestamptz default now(),location text,image_data text);`);
  for (const name of ['20260928135006_admin_portal_operations', '20260928151021_admin_operations_extensions',
    '20260930131557_admin_collection_reporting']) await migrate(name);

  const run = async (sql) => {
    const connection = await cluster.connect();
    try { return await connection.query(sql); } finally { await connection.close(); }
  };
  const call = async (sql, actor = owner, claims = {}) => JSON.parse(await run(`begin;
    set local request.jwt.claims='${JSON.stringify({ sub: actor, session_id: actor === owner ? ownerSession : customerSession,
      role: 'authenticated', aal: actor === owner ? 'aal2' : 'aal1', exp: Math.floor(Date.now()/1000)+3600, ...claims })}';
    set local request.jwt.claim.sub=''; set local role authenticated; ${sql}; commit;`));
  const rpc = async (action, payload = {}) => JSON.parse(await run(`set role service_role;
    select public.admin_portal_data('${owner}','${action}','${JSON.stringify(payload).replaceAll("'", "''")}');`));
  const rows = async (filters = {}) => (await rpc('transactions', { filters: { status: 'all', ...filters } })).items;
  const report = async () => (await rpc('overview')).reporting;
  const request = (id) => call(`select public.request_voluntary_topup_refund(${id})`, customer);
  const review = (id, action = 'approve', claims = {}) => call(`select public.review_voluntary_topup_refund('${id}','${action}')`, owner, claims);
  const queue = (cursor) => call(`select public.owner_list_voluntary_topup_refunds(${cursor ? `'${cursor.requested_at}','${cursor.id}'` : ''})`);
  let sequence = 1000;
  const load = async (location = 'null', cents = 2000) => {
    const intent = `pi_independent_${++sequence}`;
    await db.query(`select public.record_wallet_load_from_stripe('${customer}',${cents},'${intent}');
      select public.record_topup_refund_provenance('${intent}','${customer}',${cents},
        clock_timestamp()-interval '1 minute','evt_independent_${sequence}',true,${location});`);
    return { id: await db.query(`select id from public.wallet_loads where stripe_payment_intent_id='${intent}';`), intent };
  };
  const settle = (r, intent, status) => db.query(`select public.reconcile_voluntary_topup_refund('${r.id}',
    're_independent_${r.load_id}','${status}','${intent}',${r.principal_cents},'usd',true);`);
  const reset = () => db.query(`truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at) values('${customer}',now()),('${owner}',now()),('${staff}',now());
    insert into public.profiles(id,roles) values('${customer}','User'),('${owner}','Owner'),('${staff}','Admin');
    insert into auth.sessions(id,user_id,aal,created_at,factor_id) values
      ('${customerSession}','${customer}','aal1',now(),null),('${ownerSession}','${owner}','aal2',now(),'${factor}');
    insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${owner}','totp','verified');
    insert into public."Locations"(id,"Name") values(1,'Synthetic North'),(2,'Synthetic South') on conflict do nothing;
    delete from public."Location_to_Admin";
    insert into public."Location_to_Admin" values('${owner}',1);
    insert into public."Machines"(id,"Location_ID","Machine_type","Name") values(1,1,'Washer','Synthetic Washer') on conflict do nothing;
    update private.topup_refund_policy set enabled_at=now()-interval '3 days';`);
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await fn(); });
  const cents = (r) => [r.gross_collection_cents, r.refunded_collection_cents, r.net_collection_cents];
  const vend = async (loaded, matchingField) => {
    const id = uid(++sequence);
    const reference = matchingField === 'stripe_payment_intent_id' ? loaded.intent : `synthetic_${sequence}`;
    if (matchingField !== 'stripe_payment_intent_id') await db.query(`update public.wallet_loads set ${matchingField}='${reference}' where id=${loaded.id};`);
    await db.query(`insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,
      user_id,amount_cents,payment_method,channel,status,transaction_id,${matchingField},nayax_transaction_id,nayax_rrn)
      values('${id}','${uid(++sequence)}','synthetic_hash_${sequence}',1,'${customer}',2000,'card','app','started',
        'SYNTHETIC-${sequence}','${reference}','synthetic-nayax-${sequence}','synthetic-rrn-${sequence}');`);
    return id;
  };

  for (const field of ['stripe_payment_intent_id', 'stripe_checkout_session_id', 'stripe_charge_id']) {
    await fresh(`completed refund plus ${field} vend evidence never duplicates collection or refund`, async () => {
      const loaded = await load();
      const r = await request(loaded.id); await review(r.id);
      await db.query(`select public.prepare_voluntary_topup_refund('${r.id}');`);
      await settle(r, loaded.intent, 'succeeded');
      const sid = await vend(loaded, field);
      const before = await db.query('select json_agg(row_to_json(w)) from public.wallet_balances w;');
      const result = await rows(), funding = result.find((row) => row.id === `load:${loaded.id}`);
      const machine = result.find((row) => row.id === `vend:${sid}`);
      assert.deepEqual(cents(funding), [2000, 2000, 0]);
      assert.deepEqual(cents(machine), [0, 0, 0]);
      assert.equal(machine.reconciliation, 'linked_collection');
      assert.equal(result.length, 2, 'linked legacy transaction must not reappear');
      assert.equal((await report()).confirmedCollectionCents, 0);
      assert.equal((await report()).operationalVendCents, 2000);
      assert.deepEqual((await rpc('exportRecords', { dataset: 'transactions', filters: { status: 'all' } })).rows, result);
      await settle(r, loaded.intent, 'succeeded');
      assert.equal((await report()).buckets.reduce((sum, bucket) => sum+(bucket.refundedCollectionCents ?? 0), 0), 2000);
      assert.equal(await db.query('select json_agg(row_to_json(w)) from public.wallet_balances w;'), before);
    });
  }

  for (const status of ['requested', 'approved', 'unknown', 'pending']) {
    await fresh(`mixed ${status} refund and confirmed load keeps bucket unknown without hiding known gross`, async () => {
      const loaded = await load(); await load('null', 700);
      const r = await request(loaded.id);
      if (status !== 'requested') await review(r.id);
      if (['pending', 'unknown'].includes(status)) await db.query(`select public.prepare_voluntary_topup_refund('${r.id}');`);
      if (status === 'pending') await settle(r, loaded.intent, 'pending');
      await vend(loaded, 'stripe_payment_intent_id');
      const overview = await report();
      assert.equal(overview.confirmedCollectionCents, 700);
      const bucket = overview.buckets.find((b) => b.category === 'wallet_funding');
      assert.equal(bucket.grossCollectionCents, 2700);
      assert.equal(bucket.refundedCollectionCents, null);
      assert.equal(bucket.netCollectionCents, null);
      assert.equal(bucket.unresolvedRecords, 1);
      assert.equal(overview.unresolvedRecords, 1);
    });
  }

  await fresh('105 tied timestamps paginate by UUID once each without millisecond coercion', async () => {
    for (let i = 0; i < 105; i++) await request((await load('null', 100)).id);
    await db.query("update private.voluntary_topup_refunds set requested_at=date_trunc('second',statement_timestamp())+interval '1.123456 seconds';");
    const first = await queue(), second = await queue(first.at(-1));
    assert.equal(first.length, 100); assert.equal(second.length, 5);
    const ids = [...first, ...second].map((r) => r.id);
    assert.equal(new Set(ids).size, 105); assert.deepEqual(ids, [...ids].sort().reverse());
    assert.match(first.at(-1).requested_at, /\.123456/);
    assert.deepEqual(await queue(second.at(-1)), []);
  });

  for (const revoke of ['membership', 'factor', 'bound_factor', 'aal', 'session', 'role', 'ban']) {
    await fresh(`Owner list then ${revoke} loss cannot authorize a stale UI decision`, async () => {
      const loaded = await load('1'), r = await request(loaded.id);
      assert.equal((await queue()).length, 1);
      const sql = {
        membership: `delete from public."Location_to_Admin" where user_id='${owner}';`,
        factor: `update auth.mfa_factors set status='unverified' where user_id='${owner}';`,
        bound_factor: `update auth.sessions set factor_id=null where id='${ownerSession}';`,
        aal: `update auth.sessions set aal='aal1' where id='${ownerSession}';`,
        session: `delete from auth.sessions where id='${ownerSession}';`,
        role: `update public.profiles set roles='Admin' where id='${owner}';`,
        ban: `update auth.users set banned_until=now()+interval '1 hour' where id='${owner}';`,
      }[revoke];
      await db.query(sql);
      await assert.rejects(review(r.id), /PT40[13]/);
      if (revoke === 'membership') assert.deepEqual(await queue(), []);
      else await assert.rejects(queue(), /PT40[13]/);
      assert.equal(await db.query(`select status from private.voluntary_topup_refunds where id='${r.id}';`), 'requested');
      assert.equal(await db.query(`select dispatch_started_at is null from private.voluntary_topup_refunds where id='${r.id}';`), 't');
    });
  }

  await fresh('pending-deletion Owner cannot review or list Owner queue', async () => {
    const r = await request((await load()).id);
    await call('select public.request_account_deletion()');
    await assert.rejects(queue(), /PT403/);
    await assert.rejects(review(r.id), /PT403/);
    assert.equal(await db.query(`select status from private.voluntary_topup_refunds where id='${r.id}';`), 'requested');
  });

  await fresh('JWT AAL1 cannot borrow a still-AAL2 database session', async () => {
    const r = await request((await load()).id);
    await assert.rejects(review(r.id, 'approve', { aal: 'aal1' }), /PT403/);
    assert.equal((await review(r.id)).status, 'approved');
  });

  await fresh('concurrent approve and deny produce only one persisted decision and reservation outcome', async () => {
    const r = await request((await load()).id);
    const outcomes = await Promise.allSettled([review(r.id), review(r.id, 'deny')]);
    assert.equal(outcomes.filter((result) => result.status === 'fulfilled').length, 1);
    const status = await db.query(`select status from private.voluntary_topup_refunds where id='${r.id}';`);
    assert(['approved', 'denied'].includes(status));
    const balance = JSON.parse(await db.query('select json_build_array(paid_balance_cents,promo_balance_cents) from public.wallet_balances;'));
    assert.deepEqual(balance, status === 'approved' ? [0, 0] : [2000, 500]);
    assert.equal(await db.query(`select count(*) from private.voluntary_topup_refunds where id='${r.id}';`), '1');
  });

  await fresh('confirmed refund retains original Indianapolis date and separate later completion', async () => {
    const loaded = await load(), r = await request(loaded.id); await review(r.id);
    await db.query(`select public.prepare_voluntary_topup_refund('${r.id}');`); await settle(r, loaded.intent, 'succeeded');
    await db.query(`update public.wallet_loads set created_at='2026-01-01T04:59:59.999999Z' where id=${loaded.id};`);
    const original = await rows({ from: '2025-12-31', to: '2025-12-31' });
    assert.equal(original.length, 1); assert.deepEqual(cents(original[0]), [2000, 2000, 0]);
    assert.notEqual(original[0].date, original[0].refund_completed_at);
    assert.equal((await rows({ from: '2026-01-01', to: '2026-01-01' })).length, 0);
    assert.equal((await report()).confirmedCollectionCents, 0);
  });
});
