import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, afterEach, test } from 'node:test';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const read = (file) => readFile(new URL(`../${file}`, import.meta.url), 'utf8');
const legacy = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const owner = '11111111-1111-4111-8111-111111111111';
let id;
const insert = (channel = 'app') => one(`insert into cortina_vend_sessions(client_request_id,client_access_token_hash,
  transaction_id,machine_id,washer_size_rate_id,amount_cents,payment_method,channel,pulse_line_number)
  values(gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,1,1,400,'card',$1,1) returning *`, [channel]);
const due = (session = id) => db.query("update cortina_vend_sessions set reconcile_after=clock_timestamp()-interval '1 second' where id=$1", [session]);
const claim = (environment = 'sandbox') => one('select claim_cortina_reconciliation($1) result', [environment]).then(row => row.result);
const finish = (session, outcome, evidence = {}, reason = 'test_observation') => one(
  'select finish_cortina_reconciliation($1,$2,$3,$4,$5) result',
  [session.id, session.reconcile_claim, outcome, reason, JSON.stringify(evidence)],
).then(row => row.result);
const row = (session = id) => one('select * from cortina_vend_sessions where id=$1', [session]);
const evidence = (user = null) => ({ payment: { id: 'pi_test', status: 'succeeded', amount: 400, amount_received: 400,
  currency: 'usd', livemode: false, charge_id: 'ch_test', metadata: {
    purpose: 'cortina_vend', cortina_session_id: id, machine_id: '1', amount_cents: '400',
    ...(user ? { user_id: user } : {}),
  } }, refund: { id: 're_test', payment_intent: 'pi_test', charge: 'ch_test', amount: 400,
    currency: 'usd', status: 'succeeded' } });
const bindRefund = () => db.query("update cortina_vend_sessions set stripe_refund_id='re_test',status='support_required' where id=$1", [id]);
const rejects = async (action, pattern) => {
  await db.exec('savepoint rejected_action'); await assert.rejects(action, pattern);
  await db.exec('rollback to savepoint rejected_action');
};

before(async () => {
  await db.exec(await read('supabase/tests/cortina_payment_binding.fixture.sql'));
  // Actual Cortina migrations; only the unavailable pgcrypto extension is omitted.
  await db.exec((await read('supabase/migrations/20260803150427_cortina_qr_remote_vend.sql'))
    .replace('create extension if not exists pgcrypto with schema extensions;', ''));
  for (const file of ['20260807195409_configure_dryer_time_options.sql','20260922224735_cortina_price_array_selectors.sql']) {
    await db.exec(await read(`supabase/migrations/${file}`));
  }
  await db.exec(`insert into "Locations" values(1);
    insert into washer_size_rates(id,location_id,size_label,capacity_kg,price_cents) values(1,1,'12 kg',12,400);
    insert into "Machines"(id,"Name","Machine_type","Location_ID",washer_size_rate_id) values(1,'Washer','Washer',1,1);
    update cortina_machine_config set nayax_terminal_id='4434331126150568',pulse_line_number=1,is_enabled=true,review_required=false;
    insert into cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,amount_cents,
      payment_method,channel,transaction_id,status,stripe_payment_intent_id)
      values('${legacy}',gen_random_uuid(),'legacy',1,400,'card','app','legacy-trans','paid','pi_legacy');
    insert into auth.users values('${owner}'); insert into profiles values('${owner}','Customer');
    create schema private;
    -- Minimal preserved lifecycle record, not a substitute for admission-suite evidence.
    create table private.account_lifecycle(user_id uuid primary key, account_state text);
    insert into private.account_lifecycle values('${owner}','pending_deletion');`);
  for (const file of ['20260930154259_freeze_cortina_payment_bindings.sql',
    '20260930161734_cortina_closed_app_reconciliation.sql','20260930163919_cortina_callback_provider_ownership.sql']) {
    await db.exec(await read(`supabase/migrations/${file}`));
  }
  await db.exec('grant all on all tables in schema public to service_role; grant all on all sequences in schema public to service_role;');
});
beforeEach(async () => {
  await db.exec('begin; set local role service_role; update cortina_vend_sessions set reconcile_after=null;');
  id = (await insert()).id;
  await db.query("update cortina_vend_sessions set stripe_payment_intent_id='pi_test' where id=$1", [id]);
});
afterEach(() => db.exec('rollback'));
after(() => db.close());

test('new sessions queue without app activity, but never before their observation delay', async () => {
  assert.equal((await row()).reconcile_after instanceof Date, true);
  assert.equal(await claim(), null);
  await due(); const claimed = await claim();
  assert.equal(claimed.id, id); assert.equal(claimed.reconcile_attempts, 1);
  assert.match(claimed.reconcile_claim, /^[0-9a-f-]{36}$/);
  assert.equal(await claim(), null);
});

test('one invocation claims one row and filters the configured environment', async () => {
  const second = await insert(); await due(); await due(second.id);
  assert.equal(await claim('production'), null);
  const firstClaim = await claim(); const secondClaim = await claim();
  assert.notEqual(firstClaim.id, secondClaim.id); assert.equal(await claim(), null);
  await rejects(() => claim('unknown'), /Invalid reconciliation environment/);
});

test('expired lease cannot finish and replacement claim invalidates an older result', async () => {
  await due(); const first = await claim();
  await db.query("update cortina_vend_sessions set reconcile_claim_until=clock_timestamp()-interval '1 second' where id=$1", [id]);
  assert.equal(await finish(first, 'manual_review'), false);
  await due(); const next = await claim(); assert.notEqual(next.reconcile_claim, first.reconcile_claim);
  assert.equal(next.reconcile_attempts, 2);
  assert.equal(await finish(first, 'manual_review'), false);
  assert.equal(await finish(next, 'manual_review'), true);
  assert.equal((await row()).reconcile_after, null);
});

for (const change of ["status='started'", "nayax_transaction_id='1234567'", "stripe_refund_id='re_new'",
  "start_requested_at=clock_timestamp()", `user_id='${owner}'`]) {
  test(`callback/binding update cancels the old worker claim: ${change}`, async () => {
    await due(); const session = await claim();
    await db.query(`update cortina_vend_sessions set ${change} where id=$1`, [id]);
    assert.equal(await finish(session, 'payment_verified', evidence()), false);
    assert.equal((await row()).reconcile_claim, null);
    assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
  });
}

test('late verified funding uses the existing audit RPC but never makes a session startable', async () => {
  await due(); const session = await claim();
  assert.equal(await finish(session, 'payment_verified', evidence()), true);
  const current = await row();
  assert.equal(current.status, 'support_required'); assert.equal(current.stripe_charge_id, 'ch_test');
  assert.equal(current.start_requested_at, null); assert.equal(current.stripe_refund_id, null);
  assert.equal(current.reconcile_after, null);
  assert.equal((await one("select count(*)::int n from cortina_vend_events where event_type='payment_succeeded'")).n, 1);
  assert.equal(await finish(session, 'payment_verified', evidence()), false);
});

test('callback audit binding invalidates a worker observation through the ownership trigger', async () => {
  await db.query("update cortina_vend_sessions set status='awaiting_sale' where id=$1", [id]);
  await due(); const session = await claim();
  await db.query(`insert into cortina_vend_events(session_id,source,event_type,event_key,payload)
    values($1,'nayax','sale','nayax:sandbox:sale:1234567',$2)`, [id, {
    BasicInfo: { TransactionId: session.transaction_id, NayaxTransactionId: '1234567', Amount: 4, CurrencyCode: 'USD' },
  }]);
  assert.equal(await finish(session,'payment_verified',evidence()),false);
  assert.equal((await row()).reconcile_claim,null);
  assert.equal((await row()).nayax_transaction_id,'1234567');
  assert.equal((await row()).status,'awaiting_sale');
  assert.equal((await one("select count(*)::int n from cortina_vend_events where event_type='reconciliation'")).n,0);
});

test('matching bound refund commits once and stops the durable queue', async () => {
  await bindRefund(); await due(); const session = await claim();
  assert.equal(await finish(session, 'refund_succeeded', evidence()), true);
  const current = await row(); assert.equal(current.status, 'refunded');
  assert.equal(current.completed_at instanceof Date, true); assert.equal(current.reconcile_after, null);
  assert.equal(current.stripe_refund_id, 're_test'); assert.equal(current.reconcile_claim, null);
  assert.equal(await finish(session, 'refund_succeeded', evidence()), false);
  assert.equal(await claim(), null);
});

test('web settlement binds only its stored Checkout with complete matching evidence', async () => {
  const web = await insert('web');
  await db.query("update cortina_vend_sessions set stripe_checkout_session_id='cs_test' where id=$1", [web.id]);
  await due(web.id); const session = await claim(); assert.equal(session.id, web.id);
  const proof = evidence(); proof.payment.id = 'pi_web'; proof.payment.charge_id = 'ch_web';
  proof.payment.metadata.cortina_session_id = web.id;
  proof.checkout = { id: 'cs_test', payment_intent: 'pi_web', mode: 'payment', status: 'complete', payment_status: 'paid',
    amount_total: 400, currency: 'usd', livemode: false, metadata: { ...proof.payment.metadata } };
  for (const patch of [{ id: 'cs_other' }, { payment_intent: 'pi_other' }, { mode: 'subscription' },
    { status: 'open' }, { payment_status: 'unpaid' }, { amount_total: 399 }, { currency: 'eur' },
    { livemode: true }, { metadata: {} }]) {
    await rejects(() => finish(session, 'payment_verified', { ...proof, checkout: { ...proof.checkout, ...patch } }), /Checkout evidence mismatch/);
    assert.equal((await row(web.id)).stripe_payment_intent_id, null);
  }
  assert.equal(await finish(session, 'payment_verified', proof), true);
  assert.equal((await row(web.id)).stripe_payment_intent_id, 'pi_web');
  assert.equal((await row(web.id)).status, 'support_required');
  assert.equal((await row()).status, 'payment_pending');
});

test('pending refund backs off durably and later success shares the original payment audit', async () => {
  await bindRefund(); await due(); const first = await claim();
  const pending = evidence(); pending.refund.status = 'pending';
  assert.equal(await finish(first, 'refund_pending', pending), true);
  assert.equal((await row()).status, 'support_required'); assert.equal(await claim(), null);
  await due(); const next = await claim(); assert.equal(next.reconcile_attempts, 2);
  assert.equal(await finish(next, 'refund_succeeded', evidence()), true);
  assert.equal((await one("select count(*)::int n from cortina_vend_events where event_type='payment_succeeded'")).n, 1);
  assert.equal((await one("select count(*)::int n from cortina_vend_events where event_type='reconciliation'")).n, 2);
});

test('retry delay is bounded at six hours without losing pending refunds', async () => {
  await bindRefund(); await db.query('update cortina_vend_sessions set reconcile_attempts=20 where id=$1', [id]);
  await due(); const session = await claim(); const pending = evidence(); pending.refund.status = 'requires_action';
  await finish(session, 'refund_pending', pending);
  const delay = Number((await one('select extract(epoch from reconcile_after-clock_timestamp()) seconds from cortina_vend_sessions where id=$1', [id])).seconds);
  assert.ok(delay > 21500 && delay <= 21600);
  assert.equal((await row()).reconcile_attempts, 21); assert.equal((await row()).status, 'support_required');
});

test('provider uncertainty is support-required with backoff, never an inferred failed vend', async () => {
  await db.query("update cortina_vend_sessions set status='awaiting_sale',start_requested_at=now() where id=$1", [id]);
  await due(); const session = await claim(); await finish(session, 'provider_unavailable', {}, 'provider_observation_unavailable');
  const current = await row(); assert.equal(current.status, 'support_required'); assert.notEqual(current.reconcile_after, null);
  assert.equal(current.stripe_refund_id, null); assert.notEqual(current.start_requested_at, null);
});

test('unsettled payment keeps its pending state and a durable retry', async () => {
  await due(); const session = await claim(); await finish(session, 'payment_pending');
  const current = await row(); assert.equal(current.status, 'payment_pending'); assert.notEqual(current.reconcile_after, null);
  assert.equal(current.stripe_charge_id, null); assert.equal(current.start_requested_at, null);
});

for (const [field, value] of [['id','pi_other'],['amount_received',399],['currency','eur'],['livemode',true],['metadata',{}]]) {
  test(`verified payment evidence mismatch rolls back: ${field}`, async () => {
    await due(); const session = await claim(); const proof = evidence(); proof.payment[field] = value;
    await rejects(() => finish(session, 'payment_verified', proof), /mismatch|does not match/);
    assert.equal((await row()).status, 'payment_pending'); assert.equal((await row()).reconcile_claim, session.reconcile_claim);
    assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
  });
}

for (const [field, value] of [['id','re_other'],['payment_intent','pi_other'],['charge','ch_other'],['amount',399],['currency','eur'],['status','pending']]) {
  test(`refund evidence mismatch cannot complete or bind a replacement: ${field}`, async () => {
    await bindRefund(); await due(); const session = await claim(); const proof = evidence(); proof.refund[field] = value;
    await rejects(() => finish(session, 'refund_succeeded', proof), /Refund evidence mismatch/);
    assert.equal((await row()).status, 'support_required'); assert.equal((await row()).stripe_refund_id, 're_test');
    assert.equal((await row()).stripe_charge_id, null);
    assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
  });
}

test('audit failure rolls back funding, status and claim completion together', async () => {
  await due(); const session = await claim();
  await db.exec(`reset role;
    create function public.reject_reconcile_audit() returns trigger language plpgsql as $$
      begin if new.event_type='reconciliation' then raise exception 'synthetic audit failure'; end if; return new; end $$;
    create trigger reject_reconcile_audit before insert on cortina_vend_events for each row execute function reject_reconcile_audit();
    set local role service_role;`);
  await rejects(() => finish(session, 'payment_verified', evidence()), /synthetic audit failure/);
  assert.equal((await row()).status, 'payment_pending'); assert.equal((await row()).stripe_charge_id, null);
  assert.equal((await row()).reconcile_claim, session.reconcile_claim);
  assert.equal((await one('select count(*)::int n from cortina_vend_events')).n, 0);
});

test('lease expiry during nested audit work rolls back the entire settlement', async () => {
  await due(); const session = await claim();
  await db.exec(`reset role;
    create function public.delay_reconcile_audit() returns trigger language plpgsql as $$
    begin
      if new.event_type='reconciliation' then
        perform pg_sleep(greatest(0,extract(epoch from
          current_setting('test.reconciliation_deadline')::timestamptz-clock_timestamp()))::double precision + 0.01);
      end if;
      return new;
    end $$;
    create trigger delay_reconcile_audit before insert on cortina_vend_events
      for each row execute function public.delay_reconcile_audit();
    set local role service_role;`);
  await db.query(`with deadline as (
    update cortina_vend_sessions set reconcile_claim_until=clock_timestamp()+interval '1 second'
    where id=$1 returning reconcile_claim_until)
    select set_config('test.reconciliation_deadline',reconcile_claim_until::text,true) from deadline`, [id]);
  await rejects(() => finish(session,'payment_verified',evidence()), /lease expired during settlement/);
  assert.equal((await row()).status,'payment_pending'); assert.equal((await row()).stripe_charge_id,null);
  assert.equal((await row()).reconcile_claim,session.reconcile_claim);
  assert.equal((await one('select count(*)::int n from cortina_vend_events')).n,0);
});

test('original routing is never backfilled for a historical reconciliation', async () => {
  await due(legacy); const session = await claim(); assert.equal(session.id, legacy);
  await finish(session, 'manual_review', {}, 'original_routing_unavailable');
  const current = await row(legacy); assert.equal(current.status, 'support_required');
  assert.equal(current.nayax_environment, null); assert.equal(current.stripe_livemode, null);
  assert.equal(current.stripe_payment_intent_id, 'pi_legacy'); assert.equal(current.stripe_refund_id, null);
  assert.equal(current.reconcile_after, null);
});

test('settlement retains pending-deletion identity and financial records without opening private lifecycle access', async () => {
  await db.query('update cortina_vend_sessions set user_id=$1 where id=$2', [owner,id]);
  await bindRefund(); await due(); const session = await claim();
  await rejects(() => db.query('select * from private.account_lifecycle'), /permission denied/);
  assert.equal(await finish(session, 'refund_succeeded', evidence(owner)), true);
  assert.equal((await row()).user_id, owner); assert.equal((await row()).status, 'refunded');
  await db.exec('reset role');
  assert.equal((await one('select count(*)::int n from auth.users')).n, 1);
  assert.equal((await one('select count(*)::int n from profiles')).n, 1);
  assert.equal((await one('select account_state from private.account_lifecycle where user_id=$1', [owner])).account_state, 'pending_deletion');
});

for (const role of ['anon','authenticated']) {
  test(`${role} cannot claim or finish scheduled reconciliation`, async () => {
    await due(); const session = await claim(); await db.exec(`set local role ${role}`);
    await rejects(() => claim(), /permission denied/);
    await rejects(() => finish(session, 'refund_succeeded', evidence()), /permission denied/);
  });
}
