// PGLITE_MODULE=/absolute/path/to/pglite/dist/index.js node --test scripts/cortina-payment-binding.test.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, afterEach, test } from 'node:test';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const legacy = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
let id;
const insert = async (patch = {}) => {
  const row = { machine_id: 1, washer_size_rate_id: 1, amount_cents: 400, payment_method: 'card',
    channel: 'app', pulse_line_number: 1, ...patch };
  const fields = Object.keys(row);
  return one(`insert into public.cortina_vend_sessions
    (client_request_id,client_access_token_hash,transaction_id,${fields.join(',')})
    values(gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,${fields.map((_, i) => `$${i + 1}`).join(',')}) returning *`, Object.values(row));
};
const pay = (patch = {}) => {
  const p = { session: id, event: 'evt_test', intent: 'pi_test', checkout: null,
    charge: 'ch_test', amount: 400, currency: 'usd', livemode: false, ...patch };
  return db.query('select public.record_cortina_card_payment($1,$2,$3,$4,$5,$6,$7,$8)', Object.values(p));
};
const rejects = async (action, pattern) => {
  await db.exec('savepoint rejected_action');
  await assert.rejects(action, pattern);
  await db.exec('rollback to savepoint rejected_action');
};
before(async () => {
  await db.exec(await read('supabase/tests/cortina_payment_binding.fixture.sql'));
  // PGlite provides core gen_random_uuid but not pgcrypto. No tested SQL is altered.
  const foundation = await read('supabase/migrations/20260803150427_cortina_qr_remote_vend.sql');
  await db.exec(foundation.replace('create extension if not exists pgcrypto with schema extensions;', ''));
  for (const file of ['20260807195409_configure_dryer_time_options.sql', '20260922224735_cortina_price_array_selectors.sql']) {
    await db.exec(await read(`supabase/migrations/${file}`));
  }
  await db.exec(`insert into "Locations" values(1);
    insert into washer_size_rates(id,location_id,size_label,capacity_kg,price_cents) values(1,1,'12 kg',12,400);
    insert into "Machines"(id,"Name","Machine_type","Location_ID",washer_size_rate_id)
      values(1,'Washer','Washer',1,1),(2,'Dryer','Dryer',1,null);
    update cortina_machine_config set nayax_terminal_id='443433112615056'||machine_id,
      pulse_line_number=1,is_enabled=true,review_required=false;
    insert into cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,
      amount_cents,payment_method,channel,transaction_id,status,stripe_payment_intent_id)
      values('${legacy}',gen_random_uuid(),'legacy',1,400,'card','app','legacy-trans','paid','pi_legacy');`);
  await db.exec(await read('supabase/migrations/20260930154259_freeze_cortina_payment_bindings.sql'));
  // Supabase's service role grants are modeled explicitly; customer privileges
  // remain those established by the actual Cortina migration.
  await db.exec('grant all on all tables in schema public to service_role; grant all on all sequences in schema public to service_role;');
});
beforeEach(async () => {
  await db.exec('begin; set local role service_role;');
  id = (await insert()).id;
  await db.query('update cortina_vend_sessions set stripe_payment_intent_id=$1 where id=$2', ['pi_test', id]);
});
afterEach(() => db.exec('rollback'));
after(() => db.close());

test('new sessions freeze routing and mode; historical rows are not backfilled', async () => {
  const row = await one('select * from cortina_vend_sessions where id=$1', [id]);
  assert.equal(row.nayax_environment, 'sandbox'); assert.equal(row.nayax_terminal_id, '4434331126150561');
  assert.equal(row.stripe_livemode, false); assert.equal(row.pulse_line_number, 1);
  const old = await one('select * from cortina_vend_sessions where id=$1', [legacy]);
  assert.equal(old.nayax_environment, null); assert.equal(old.stripe_livemode, null);
  assert.equal(old.status, 'paid'); assert.equal(old.stripe_payment_intent_id, 'pi_legacy');
});

for (const [column, value] of Object.entries({
  machine_id: 2, amount_cents: 401, currency: 'EUR', payment_method: 'wallet', channel: 'web',
  transaction_id: 'replacement', client_request_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  client_access_token_hash: 'replacement', dryer_minutes: 20, product_code: 2, pulse_line_number: 2,
  nayax_environment: 'production', nayax_terminal_id: 'wrong', nayax_uniqr: 'wrong', stripe_livemode: true,
})) {
  test(`cannot alter frozen ${column}`, async () => {
    await rejects(() => db.query(`update cortina_vend_sessions set ${column}=$1 where id=$2`, [value, id]), /immutable/);
  });
}

test('machine configuration changes never reroute an existing payment', async () => {
  await db.exec("update cortina_machine_config set environment='production',nayax_terminal_id='changed',pulse_line_number=2 where machine_id=1");
  await pay();
  const row = await one('select status,nayax_environment,nayax_terminal_id,pulse_line_number,stripe_livemode from cortina_vend_sessions where id=$1', [id]);
  assert.deepEqual(row, { status: 'paid', nayax_environment: 'sandbox', nayax_terminal_id: '4434331126150561', pulse_line_number: 1, stripe_livemode: false });
  await rejects(() => insert(), /pulse selection has changed/);
  const next = await insert({ pulse_line_number: 2 }); assert.equal(next.stripe_livemode, true);
});

test('stale price, product, disabled machine and unavailable machine fail before funding', async () => {
  await rejects(() => insert({ amount_cents: 399 }), /price has changed/);
  await db.exec(`update cortina_machine_config set product_codes='{"400":3}',pulse_line_number=null where machine_id=1`);
  await rejects(() => insert({ product_code: 2, pulse_line_number: null }), /product selection has changed/);
  const next = await insert({ product_code: 3, pulse_line_number: null }); assert.equal(next.product_code, 3);
  await db.exec('update cortina_machine_config set is_enabled=false where machine_id=1');
  await rejects(() => insert(), /routing needs review/);
  await db.exec('update "Machines" set is_out_of_service=true where id=1');
  await rejects(() => insert(), /unavailable/);
});

for (const [amount, minutes, line] of [[50,10,1],[100,20,2],[150,30,3],[200,40,4],[300,60,5],[450,90,6]]) {
  test(`dryer ${minutes} minutes freezes its pulse and product-code alternatives`, async () => {
    const patch = { machine_id: 2, washer_size_rate_id: null, amount_cents: amount, dryer_minutes: minutes, pulse_line_number: line };
    assert.equal((await insert(patch)).pulse_line_number, line);
    await rejects(() => insert({ ...patch, dryer_minutes: minutes + 1 }), /Invalid dryer/);
    await db.query('update cortina_machine_config set product_codes=$1,pulse_line_number=null where machine_id=2', [JSON.stringify({ [amount]: line - 1 })]);
    const code = await insert({ ...patch, pulse_line_number: null, product_code: line - 1 });
    assert.equal(code.product_code, line - 1); assert.equal(code.pulse_line_number, null);
  });
}

test('funding records the complete audit atomically and repeats without reopening', async () => {
  await pay(); await pay();
  const events = (await db.query('select * from cortina_vend_events where session_id=$1', [id])).rows;
  assert.equal(events.length, 1);
  assert.deepEqual(events[0].payload, { payment_intent_id: 'pi_test', checkout_session_id: null,
    charge_id: 'ch_test', amount_received: 400, currency: 'USD', livemode: false });
  for (const status of ['starting','awaiting_sale','approved','started','voided','refunded','timed_out','support_required']) {
    await db.query('update cortina_vend_sessions set status=$1 where id=$2', [status,id]);
    await pay();
    assert.equal((await one('select status from cortina_vend_sessions where id=$1', [id])).status, status);
  }
});

test('queued duplicate funding and conditional Start claims yield exactly one claim', async () => {
  // One PGlite connection queues statements; this is not independent-connection lock evidence.
  await Promise.all(Array.from({ length: 8 }, () => pay()));
  const claims = await Promise.all(Array.from({ length: 8 }, () => db.query(
    "update cortina_vend_sessions set status='starting' where id=$1 and status='paid' returning id", [id])));
  assert.equal(claims.reduce((count, result) => count + result.rows.length, 0), 1);
});

for (const patch of [{ amount: 399 }, { currency: null }, { currency: 'eur' }, { livemode: null },
  { livemode: true }, { intent: 'pi_wrong' }, { checkout: 'cs_wrong' }, { charge: null }, { event: '' }]) {
  test(`RPC rejects mismatched evidence ${JSON.stringify(patch)}`, async () => {
    await rejects(() => pay(patch), /does not match/);
    assert.equal((await one('select status from cortina_vend_sessions where id=$1', [id])).status, 'payment_pending');
    assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
  });
}

test('Checkout learns only its verified intent and preserves its binding', async () => {
  const web = await insert({ channel: 'web' });
  await db.query("update cortina_vend_sessions set stripe_checkout_session_id='cs_test' where id=$1", [web.id]);
  await pay({ session: web.id, checkout: 'cs_test', intent: 'pi_web' });
  assert.equal((await one('select stripe_payment_intent_id from cortina_vend_sessions where id=$1', [web.id])).stripe_payment_intent_id, 'pi_web');
  await rejects(() => pay({ session: web.id, checkout: 'cs_other', intent: 'pi_web' }), /does not match/);
  for (const column of ['stripe_payment_intent_id','stripe_checkout_session_id','stripe_charge_id']) {
    await rejects(() => db.query(`update cortina_vend_sessions set ${column}=null where id=$1`, [web.id]), /immutable/);
  }
});

test('event collision cannot fund a second payment or rewrite the first audit', async () => {
  await pay();
  const second = await insert();
  await db.query("update cortina_vend_sessions set stripe_payment_intent_id='pi_second' where id=$1", [second.id]);
  await rejects(() => pay({ session: second.id, intent: 'pi_second' }), /already bound/);
  assert.equal((await one('select status from cortina_vend_sessions where id=$1', [second.id])).status, 'payment_pending');
  assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 1);
});

test('audit insert and paid state roll back together if the state write fails', async () => {
  await db.exec(`reset role;
    create function public.reject_test_paid() returns trigger language plpgsql as $$
      begin if new.status='paid' then raise exception 'synthetic state write failure'; end if; return new; end $$;
    create trigger reject_test_paid before update on cortina_vend_sessions for each row execute function reject_test_paid();
    set local role service_role;`);
  await rejects(() => pay(), /synthetic state write failure/);
  assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
  assert.equal((await one('select status from cortina_vend_sessions where id=$1', [id])).status, 'payment_pending');
});

test('late successful payment is audited and retained for support without restarting a failed session', async () => {
  await db.query("update cortina_vend_sessions set status='failed' where id=$1", [id]); await pay();
  const row = await one('select status,stripe_charge_id from cortina_vend_sessions where id=$1', [id]);
  assert.deepEqual(row, { status: 'support_required', stripe_charge_id: 'ch_test' });
});

test('legacy routing cannot be guessed through backfill or the funding RPC', async () => {
  await rejects(() => pay({ session: legacy, intent: 'pi_legacy' }), /does not match/);
  await rejects(() => db.query("update cortina_vend_sessions set nayax_environment='sandbox' where id=$1", [legacy]), /immutable/);
});

test('wallet snapshots remain immutable without requiring Stripe mode', async () => {
  const wallet = await insert({ payment_method: 'wallet' }); assert.equal(wallet.stripe_livemode, null);
  await rejects(() => pay({ session: wallet.id }), /does not match/);
  await db.query("update cortina_vend_sessions set status='paid' where id=$1", [wallet.id]);
});

for (const role of ['anon','authenticated']) {
  test(`${role} cannot fund or modify a session`, async () => {
    await db.exec(`set local role ${role}`);
    await rejects(() => pay(), /permission denied/);
    await rejects(() => db.query("update cortina_vend_sessions set status='paid' where id=$1", [id]), /permission denied/);
  });
}

test('Nayax transaction binding rejects a conflicting later callback write', async () => {
  await db.query("update cortina_vend_sessions set nayax_transaction_id='12345' where id=$1", [id]);
  await rejects(() => db.query("update cortina_vend_sessions set nayax_transaction_id='67890' where id=$1", [id]), /immutable/);
});
