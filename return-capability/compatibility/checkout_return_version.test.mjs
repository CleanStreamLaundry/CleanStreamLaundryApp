import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, afterEach, before, beforeEach, test } from 'node:test';

const { PGlite } = await import(process.env.PGLITE_MODULE);
const db = new PGlite();
const active = new URL('../../../../CleanStreamLaundryApp/', import.meta.url);
const readActive = (path) => readFile(new URL(path, active), 'utf8');
const one = async (sql, values = []) => (await db.query(sql, values)).rows[0];
const legacyUnbound = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const legacyFunded = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
let previousRows;

const insert = async (patch = {}, conflict = '') => {
  const row = { client_request_id: crypto.randomUUID(), client_access_token_hash: crypto.randomUUID(),
    transaction_id: crypto.randomUUID(), machine_id: 1, washer_size_rate_id: 1, amount_cents: 400,
    payment_method: 'card', channel: 'web', pulse_line_number: 1, ...patch };
  const columns = Object.keys(row);
  return one(`insert into public.cortina_vend_sessions (${columns.join(',')})
    values (${columns.map((_, index) => `$${index + 1}`).join(',')}) ${conflict} returning *`, Object.values(row));
};
const reject = async (operation, pattern) => {
  await db.exec('savepoint invalid_change');
  await assert.rejects(operation, pattern);
  await db.exec('rollback to savepoint invalid_change');
};

before(async () => {
  await db.exec(await readActive('supabase/tests/cortina_payment_binding.fixture.sql'));
  // Existing accepted PGlite convention: only unavailable pgcrypto is omitted.
  await db.exec((await readActive('supabase/migrations/20260803150427_cortina_qr_remote_vend.sql'))
    .replace('create extension if not exists pgcrypto with schema extensions;', ''));
  for (const file of ['20260807195409_configure_dryer_time_options.sql', '20260922224735_cortina_price_array_selectors.sql']) {
    await db.exec(await readActive(`supabase/migrations/${file}`));
  }
  await db.exec(`insert into "Locations" values(1);
    insert into washer_size_rates(id,location_id,size_label,capacity_kg,price_cents) values(1,1,'12 kg',12,400);
    insert into "Machines"(id,"Name","Machine_type","Location_ID",washer_size_rate_id) values(1,'Washer','Washer',1,1);
    update cortina_machine_config set nayax_terminal_id='4434331126150568',pulse_line_number=1,is_enabled=true,review_required=false;
    insert into cortina_vend_sessions(id,client_request_id,client_access_token_hash,transaction_id,machine_id,
      washer_size_rate_id,amount_cents,payment_method,channel,pulse_line_number,status,stripe_checkout_session_id)
    values('${legacyUnbound}',gen_random_uuid(),'legacy-unbound','legacy-unbound',1,1,400,'card','web',1,'payment_pending',null),
      ('${legacyFunded}',gen_random_uuid(),'legacy-funded','legacy-funded',1,1,400,'card','web',1,'paid','cs_legacy');
    create schema private;
    create table private.account_lifecycle(user_id uuid primary key, account_state text);`);
  // Load the actual binding, observation and ownership triggers on this table.
  // Wallet admission/shutdown RPCs are not invoked or stubbed by this SQL batch.
  for (const file of ['20260930154259_freeze_cortina_payment_bindings.sql',
    '20260930161734_cortina_closed_app_reconciliation.sql', '20260930163919_cortina_callback_provider_ownership.sql']) {
    await db.exec(await readActive(`supabase/migrations/${file}`));
  }
  await db.exec('grant all on all tables in schema public to service_role; grant all on all sequences in schema public to service_role;');
  previousRows = (await db.query('select to_jsonb(s) as row from cortina_vend_sessions s order by id')).rows;
  await db.exec(await readFile(new URL('./checkout_return_version.sql', import.meta.url), 'utf8'));
});
beforeEach(() => db.exec('begin; set local role service_role;'));
afterEach(() => db.exec('rollback'));
after(() => db.close());

test('existing bound and unbound rows receive legacy1 without history, timestamp or state edits', async () => {
  const rows = (await db.query("select to_jsonb(s)-'checkout_return_version' as row from cortina_vend_sessions s order by id")).rows;
  assert.deepEqual(rows, previousRows);
  assert.deepEqual((await db.query('select checkout_return_version from cortina_vend_sessions order by id')).rows,
    [{ checkout_return_version: 1 }, { checkout_return_version: 1 }]);
  assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
});

test('omitted version remains legacy1 for old web-card, app-card and wallet writers', async () => {
  for (const [payment_method, channel] of [['card', 'web'], ['card', 'app'], ['wallet', 'web'], ['wallet', 'app']]) {
    assert.equal((await insert({ payment_method, channel })).checkout_return_version, 1);
  }
});

test('explicit new web-card version2 retains the existing routing snapshot and permanent default1', async () => {
  const row = await insert({ checkout_return_version: 2 });
  assert.equal(row.checkout_return_version, 2);
  assert.equal(row.nayax_environment, 'sandbox');
  assert.equal(row.nayax_terminal_id, '4434331126150568');
  assert.equal(row.stripe_livemode, false);
  assert.equal((await insert()).checkout_return_version, 1);
});

test('version2 cannot be selected for app or wallet sessions', async () => {
  for (const [payment_method, channel] of [['card', 'app'], ['wallet', 'web'], ['wallet', 'app']]) {
    await reject(() => insert({ payment_method, channel, checkout_return_version: 2 }), /cortina_checkout_return_version_valid/);
  }
});

test('null and unsupported versions fail the database constraints', async () => {
  for (const value of [null, 0, -1, 3]) {
    await reject(() => insert({ checkout_return_version: value }), /not-null|cortina_checkout_return_version_valid/);
  }
});

test('service writer cannot upgrade legacy, downgrade new or clear a version', async () => {
  const modern = await insert({ checkout_return_version: 2 });
  for (const [id, value] of [[legacyUnbound, 2], [legacyFunded, 2], [modern.id, 1], [modern.id, null]]) {
    await reject(() => db.query('update cortina_vend_sessions set checkout_return_version=$1 where id=$2', [value, id]), /version is immutable/);
  }
  assert.equal((await one('select checkout_return_version from cortina_vend_sessions where id=$1', [modern.id])).checkout_return_version, 2);
});

test('table owner also cannot change an existing return version', async () => {
  await db.exec('reset role');
  await reject(() => db.query('update cortina_vend_sessions set checkout_return_version=2 where id=$1', [legacyUnbound]), /version is immutable/);
});

test('same-version updates and ordinary support-state changes still work', async () => {
  const row = await insert({ checkout_return_version: 2 });
  await db.query("update cortina_vend_sessions set checkout_return_version=2,status='support_required',failure_message='test' where id=$1", [row.id]);
  const current = await one('select checkout_return_version,status,failure_message from cortina_vend_sessions where id=$1', [row.id]);
  assert.deepEqual(current, { checkout_return_version: 2, status: 'support_required', failure_message: 'test' });
});

test('new-writer duplicate cannot replace an old row version, even with an upsert', async () => {
  const original = await one('select * from cortina_vend_sessions where id=$1', [legacyUnbound]);
  const patch = { client_request_id: original.client_request_id, checkout_return_version: 2 };
  assert.equal(await insert(patch, 'on conflict (client_request_id) do nothing'), undefined);
  await reject(() => insert(patch, 'on conflict (client_request_id) do update set checkout_return_version=excluded.checkout_return_version'), /version is immutable/);
  assert.deepEqual(await one('select * from cortina_vend_sessions where id=$1', [legacyUnbound]), original);
});

test('old-writer duplicate cannot downgrade a new row using its legacy default', async () => {
  const original = await insert({ checkout_return_version: 2 });
  const patch = { client_request_id: original.client_request_id };
  assert.equal(await insert(patch, 'on conflict (client_request_id) do nothing'), undefined);
  await reject(() => insert(patch, 'on conflict (client_request_id) do update set checkout_return_version=excluded.checkout_return_version'), /version is immutable/);
  assert.deepEqual(await one('select * from cortina_vend_sessions where id=$1', [original.id]), original);
});

test('existing payment binding guard continues to reject financial or channel changes', async () => {
  const row = await insert({ checkout_return_version: 2 });
  for (const sql of ['amount_cents=401', "channel='app'", "payment_method='wallet'"]) {
    await reject(() => db.query(`update cortina_vend_sessions set ${sql} where id=$1`, [row.id]), /binding is immutable/);
  }
});

for (const role of ['anon', 'authenticated']) {
  test(`${role} gains no session write or trigger execution privilege`, async () => {
    await db.exec(`set local role ${role}`);
    await reject(() => db.query('update cortina_vend_sessions set checkout_return_version=2 where id=$1', [legacyUnbound]), /permission denied/);
    await reject(() => insert({ checkout_return_version: 2 }), /permission denied/);
    await reject(() => db.query('select guard_cortina_checkout_return_version()'), /permission denied/);
  });
}
