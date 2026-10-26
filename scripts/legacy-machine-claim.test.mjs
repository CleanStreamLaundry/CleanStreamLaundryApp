import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (p) => readFile(new URL(`../${p}`, import.meta.url), 'utf8');
const migration = (n) => read(`supabase/migrations/${n}.sql`);
const candidate = await migration('20260930180614_legacy_machine_claim_atomicity');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), owner = uid(3), sid = uid(11), factor = uid(21), vendId = uid(31);
const quote = (v) => v === null ? 'null' : `'${String(v).replaceAll("'", "''")}'`;
const claims = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (jwt = claims(), role = 'authenticated') =>
  `set local request.jwt.claims=${quote(JSON.stringify(jwt))}; set local request.jwt.claim.sub=''; set local role ${role};`;
const asUser = (sql, jwt, role) => `begin; ${context(jwt, role)} ${sql}; commit;`;
const claim = (id = '100', reason = ' Machine did not clean ') =>
  `select public.request_legacy_loyalty_credit(${id},${quote(reason)})`;

test('atomic legacy machine claims with real admission and financial contracts', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN), db = await cluster.connect();
  const run = async (sql) => {
    const s = await cluster.connect();
    try { return await s.query(sql); } finally { await s.close(); }
  };
  const failure = (code, message) => (e) => {
    assert.equal(e.code, code, e.message);
    if (message) assert.match(e.message, new RegExp(message));
    return true;
  };
  const error = (sql, code, message) => assert.rejects(run(sql), failure(code, message));
  const call = async (sql = claim(), jwt) => JSON.parse(await run(asUser(sql, jwt)));
  const fixture = (await read('supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS');
  assert.equal(fixture.length, 2);
  await db.query('set client_min_messages=warning; create role postgres superuser; set role postgres;');
  await db.query(fixture[0]);
  for (const n of ['20260526010000_wallet_ledger_compliance', '20260803150427_cortina_qr_remote_vend',
    '20260807191723_harden_refund_resolution', '20260929231120_serialize_wallet_financial_writes']) {
    await db.query(await migration(n));
  }
  await db.query(`grant execute on function public.is_admin_or_owner() to authenticated;
    create trigger handle_transaction after insert on public.transactions
      for each row execute function public.update_user_balance();`);
  for (const n of ['20260807195409_configure_dryer_time_options',
    '20260922224735_cortina_price_array_selectors', '20260928132533_link_cortina_transaction_history']) {
    await db.query(await migration(n));
  }
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}';
    alter table public.profiles add column created_at timestamptz default now();
    alter table public."Machines" add column "Status" text default 'Idle',
      add column is_out_of_service boolean not null default false;
    alter table public."Location_to_Admin" enable row level security;`);
  for (const n of ['20260930154259_freeze_cortina_payment_bindings',
    '20260930163919_cortina_callback_provider_ownership']) {
    await db.query(await migration(n));
  }
  for (const n of ['20260929223124_protect_profile_authority', '20260929234955_loyalty_policy_acceptance']) {
    await db.query(await migration(n));
  }
  await db.query(await read('supabase/tests/account_admission.fixture.sql'));
  for (const n of ['20260930005456_account_admission', '20260930013417_enforce_profile_terms_admission',
    '20260930024142_protect_location_membership', '20260930063923_recoverable_account_deletion',
    '20260930125554_voluntary_topup_refunds', '20260930171558_human_wallet_spend_admission']) {
    await db.query(await migration(n));
  }
  await db.query(`reset role; grant usage,create on schema public to postgres;
    grant select(id,is_anonymous,deleted_at,banned_until,email_confirmed_at),update(id) on auth.users to postgres;
    grant select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions to postgres;
    grant select(id,user_id,factor_type,status) on auth.mfa_factors to postgres;
    alter role postgres nosuperuser bypassrls;`);
  const money = () => db.query(`select jsonb_build_object(
    'wallet',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_accounts x),
    'loads',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_loads x),
    'ledger',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_ledger_entries x),
    'redemptions',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_redemptions x),
    'cache',(select jsonb_agg(jsonb_build_array(id,balance,reward_tracker) order by id) from public.profiles),
    'vends',(select jsonb_agg(to_jsonb(x) order by id) from public.cortina_vend_sessions x),
    'provenance',(select jsonb_agg(to_jsonb(x)) from private.topup_refund_provenance x),
    'spend',(select jsonb_agg(to_jsonb(x)) from private.topup_refund_spend x),
    'reservations',(select jsonb_agg(to_jsonb(x)) from private.voluntary_topup_refunds x));`);
  const rows = () => db.query(`select jsonb_build_object(
    'transactions',(select jsonb_agg(to_jsonb(x) order by id) from public.transactions x),
    'refunds',(select jsonb_agg(to_jsonb(x) order by refund_id) from public."Refunds" x),
    'attempts',(select jsonb_agg(jsonb_build_array(id,refund_attempts) order by id) from public.profiles));`);
  const functions = () => db.query(`select jsonb_object_agg(oid::regprocedure::text,
    jsonb_build_array(pg_get_functiondef(oid),proacl,proowner)) from pg_proc
    where pronamespace in ('public'::regnamespace,'private'::regnamespace,'auth'::regnamespace)
      and prokind='f' and proname<>'request_legacy_loyalty_credit';`);
  const reset = async () => {
    await db.query(`truncate auth.users cascade;
      insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${other}',now()),('${owner}',now());
      insert into public.profiles(id,roles,loyalty_policy_version,loyalty_policy_accepted_at) values
        ('${user}','User',public.get_loyalty_policy_descriptor()->>'required_version',now()),
        ('${other}','User',public.get_loyalty_policy_descriptor()->>'required_version',now()),
        ('${owner}','Owner',public.get_loyalty_policy_descriptor()->>'required_version',now());
      insert into auth.sessions(id,user_id,aal,created_at) values
        ('${sid}','${user}','aal1',now()-interval '1 hour'),('${uid(12)}','${other}','aal1',now());
      insert into public."Locations" values (1) on conflict do nothing;
      insert into public.washer_size_rates(id,location_id,size_label,capacity_kg,price_cents)
        values (1,1,'Synthetic washer',12,750) on conflict do nothing;
      insert into public."Machines"(id,"Location_ID","Machine_type","Name",washer_size_rate_id)
        values (1,1,'Washer','Synthetic washer',1) on conflict do nothing;
      update public.cortina_machine_config set nayax_terminal_id='synthetic-terminal',
        pulse_line_number=1,is_enabled=true,review_required=false where machine_id=1;
      select public.record_wallet_load_from_stripe('${user}',2000,'pi_legacy_claim');
      insert into public.transactions(id,user_id,amount,type,description,created_at)
        values (100,'${user}',7.50,'laundry','Loyalty payment on Washer',now()-interval '1 day');`);
  };
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await fn(); });
  const pending = () => call('select public.request_account_deletion()');
  const totp = () => db.query(`insert into auth.mfa_factors(id,user_id,factor_type,status)
    values ('${factor}','${user}','totp','verified');
    update auth.sessions set aal='aal2',factor_id='${factor}' where id='${sid}';`);
  const unchangedFailure = async (sql, code, message) => {
    const before = await rows(), financial = await money();
    await error(sql, code, message);
    assert.equal(await rows(), before); assert.equal(await money(), financial);
  };
  await reset();
  const originalFunctions = await functions(), originalRows = await rows(), originalMoney = await money();
  await t.test('missing canonical prerequisite aborts additive DDL atomically', async () => {
    const body = candidate.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
    await error(`begin; set local role postgres;
      alter function public.get_admission_status() rename to fixture_missing_admission;
      ${body} commit;`, '55000');
    assert.equal(await db.query(`select to_regprocedure('public.request_legacy_loyalty_credit(bigint,text)') is null;`), 't');
    assert.equal(await functions(), originalFunctions);
  });
  await db.query(`set role postgres; ${candidate} reset role;`);
  await t.test('one authenticated-only definer; all existing functions, grants and rows preserved', async () => {
    assert.equal(await functions(), originalFunctions);
    assert.equal(await rows(), originalRows); assert.equal(await money(), originalMoney);
    assert.equal(await db.query(`select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';`), 't');
    const signature = 'public.request_legacy_loyalty_credit(bigint,text)';
    for (const role of ['anon','service_role','supabase_auth_admin']) {
      assert.equal(await db.query(`select has_function_privilege('${role}','${signature}','execute');`), 'f');
    }
    assert.equal(await db.query(`select has_function_privilege('authenticated','${signature}','execute');`), 't');
    assert.equal(await db.query(`select prosecdef and proconfig=array['search_path=""'] from pg_proc where oid='${signature}'::regprocedure;`), 't');
    assert.equal((candidate.match(/create function /g) ?? []).length, 1);
  });
  await fresh('new manual claim atomically stores authoritative dollars, flag and one attempt without money changes', async () => {
    const financial = await money(), receipt = await call();
    assert.deepEqual(Object.keys(receipt).sort(), ['amount','refund_id','status']);
    assert.equal(receipt.amount, 7.5); assert.equal(receipt.status, 'pending');
    assert.equal(await db.query(`select description from public."Refunds" where refund_id=${receipt.refund_id};`), 'Machine did not clean');
    assert.equal(await db.query(`select requested_refund from public.transactions where id=100;`), 't');
    assert.equal(await db.query(`select refund_attempts from public.profiles where id='${user}';`), '1');
    assert.equal(await money(), financial);
  });
  await fresh('decimal-string JSON argument decodes exact bigint above JavaScript safe integer', async () => {
    await db.query('update public.transactions set id=9007199254740993 where id=100;');
    const receipt = await call(`select public.request_legacy_loyalty_credit(a.target_transaction_id,a.request_description)
      from json_to_record('{"target_transaction_id":"9007199254740993","request_description":"Machine issue"}')
        as a(target_transaction_id bigint,request_description text)`);
    assert.equal(receipt.amount, 7.5);
    assert.equal(await db.query(`select transaction_id::text from public."Refunds" where refund_id=${receipt.refund_id};`), '9007199254740993');
  });
  for (const status of ['pending','approved','denied']) await fresh(`${status} replay is read-only, keeps saved description and works after 14 days`, async () => {
    const first = await call();
    await db.query(`update public."Refunds" set status='${status}' where refund_id=${first.refund_id};
      update public.transactions set created_at=now()-interval '15 days',requested_refund=false where id=100;`);
    const before = await rows(), financial = await money();
    assert.deepEqual(await call(claim('100','Changed reason')), { ...first, status });
    assert.equal(await rows(), before); assert.equal(await money(), financial);
  });
  await fresh('a flag-only historical partial failure may create one valid claim', async () => {
    await db.query('update public.transactions set requested_refund=true where id=100;');
    await call(); await call();
    assert.equal(await db.query('select count(*) from public."Refunds";'), '1');
    assert.equal(await db.query(`select refund_attempts from public.profiles where id='${user}';`), '1');
  });
  for (const kind of ['duplicate','foreign','amount']) await fresh(`${kind} existing claim fails closed without reconciliation writes`, async () => {
    await db.query(`insert into public."Refunds"(user_id,transaction_id,amount,description)
      values ('${kind==='foreign'?other:user}',100,${kind==='amount'?8:7.5},'Existing claim');`);
    if (kind==='duplicate') await db.query(`insert into public."Refunds"(user_id,transaction_id,amount,description)
      values ('${user}',100,7.5,'Duplicate');`);
    await unchangedFailure(asUser(claim()), '22023', 'reconciliation');
  });
  for (const reason of [null,'   ','x'.repeat(2001)]) await fresh(`invalid reason ${reason===null?'null':reason.length}`, async () => {
    await unchangedFailure(asUser(claim('100',reason)), '22023');
  });
  for (const [name, change] of [
    ['topup', "type='credit',description='Loyalty Card'"],
    ['reward', "type='reward'"], ['unknown type', 'type=null'],
    ['zero', 'amount=0'], ['negative', 'amount=-1'], ['missing', 'amount=null'],
    ['NaN', "amount='NaN'"], ['infinite', "amount='Infinity'"],
    ['fractional cent', 'amount=7.501'], ['resolution overflow', 'amount=21474836.48'],
    ['outside window', "created_at=clock_timestamp()-interval '14 days'"],
    ['missing date', 'created_at=null'], ['future date', "created_at=now()+interval '1 day'"],
  ]) await fresh(`${name} cannot become a new machine claim`, async () => {
    await db.query(`update public.transactions set ${change} where id=100;`);
    await unchangedFailure(asUser(claim()), '22023');
  });
  await fresh('inside the original fourteen-day machine window remains eligible', async () => {
    await db.query("update public.transactions set created_at=clock_timestamp()-interval '14 days'+interval '1 minute' where id=100;");
    assert.equal((await call()).status, 'pending');
  });
  for (const [name, change, code] of [
    ['terms missing', `update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null where id='${user}'`, 'PT403'],
    ['terms stale', `update public.profiles set loyalty_policy_version='old' where id='${user}'`, 'PT403'],
    ['unverified', `update auth.users set email_confirmed_at=null where id='${user}'`, 'PT403'],
    ['anonymous', `update auth.users set is_anonymous=true where id='${user}'`, 'PT403'],
    ['banned', `update auth.users set banned_until=now()+interval '1 day' where id='${user}'`, 'PT403'],
    ['deleted Auth', `update auth.users set deleted_at=now() where id='${user}'`, 'PT403'],
    ['unknown role', `update public.profiles set roles=null where id='${user}'`, 'PT403'],
    ['staff MFA absent', `update public.profiles set roles='Owner' where id='${user}'`, 'PT403'],
    ['revoked session', `delete from auth.sessions where id='${sid}'`, 'PT401'],
    ['expired session', `update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`, 'PT401'],
  ]) await fresh(`${name} cannot save a claim`, async () => {
    await db.query(change); await unchangedFailure(asUser(claim()), code);
  });
  for (const extra of [{exp:1},{session_id:uid(12)},{aal:'aal3'},{role:'service_role'}]) {
    await fresh(`invalid canonical claims ${JSON.stringify(extra)}`, async () => {
      await unchangedFailure(asUser(claim(),claims(extra)), 'PT401');
    });
  }
  await fresh('missing and other-account transactions, anonymous and service invocations are denied', async () => {
    await unchangedFailure(asUser(claim('999')), '42501');
    await unchangedFailure(asUser(claim(),claims({sub:other,session_id:uid(12)})), '42501');
    await unchangedFailure(asUser(claim(),{},'anon'), '42501');
    await unchangedFailure(asUser(claim(),{role:'service_role'},'service_role'), '42501');
  });
  for (const expired of [false,true]) await fresh(`pending deletion denies new and saved claims, expired=${expired}`, async () => {
    await call(); await pending();
    if (expired) await db.query(`update private.account_lifecycle set deletion_requested_at=now()-interval '721 hours',restore_until=now()-interval '1 hour';`);
    await unchangedFailure(asUser(claim()), 'PT403');
    await db.query('delete from public."Refunds";');
    await unchangedFailure(asUser(claim()), 'PT403');
  });
  await fresh('current customer and staff MFA requirements reused, not bypassed by claim RPC', async () => {
    await totp(); await unchangedFailure(asUser(claim()), 'PT403');
    const receipt = await call(claim(),claims({aal:'aal2'}));
    await db.query(`update public.profiles set roles='Admin' where id='${user}';`);
    assert.deepEqual(await call(claim(),claims({aal:'aal2'})),receipt);
    await db.query('delete from auth.mfa_factors;');
    await unchangedFailure(asUser(claim(),claims({aal:'aal2'})), 'PT403');
  });
  await fresh('restoration permits fresh-session claims without resetting their original deadline', async () => {
    await pending();
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at)
      values ('${uid(14)}','${user}','aal1',clock_timestamp());`);
    const jwt = claims({session_id:uid(14)});
    await call('select public.restore_account()',jwt);
    await unchangedFailure(asUser(claim()),'PT401');
    const createdAt = await db.query('select created_at::text from public.transactions where id=100;');
    assert.equal((await call(claim(),jwt)).status,'pending');
    assert.equal(await db.query('select created_at::text from public.transactions where id=100;'),createdAt);
  });
  await fresh('Cortina started history uses unchanged atomic RPC, never legacy fallback', async () => {
    await db.query(`insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,
      machine_id,user_id,amount_cents,payment_method,channel,transaction_id,washer_size_rate_id,pulse_line_number)
      values ('${vendId}','${vendId}','synthetic-hash',1,'${user}',750,'wallet','app','${vendId}',1,1);`);
    await call(`select public.redeem_wallet_for_cortina('${vendId}')`);
    await db.query(`update public.cortina_vend_sessions set status='started' where id='${vendId}';`);
    const id = await db.query(`select id from public.transactions where cortina_vend_session_id='${vendId}';`);
    await unchangedFailure(asUser(claim(id)), '22023');
    const financial = await money();
    const receipt = await call(`select public.request_cortina_loyalty_credit(${id},'Machine issue')`);
    assert.equal(receipt.amount,7.5); assert.equal(receipt.status,'pending');
    assert.equal(await money(),financial);
  });
  for (const [stage, table, event] of [
    ['insert','public."Refunds"','insert'],
    ['flag','public.transactions','update of requested_refund'],
    ['counter','public.profiles','update of refund_attempts'],
  ]) await fresh(`${stage} failure rolls back claim, flag and attempt together`, async () => {
    await db.query(`create function public.fixture_claim_failure() returns trigger language plpgsql as $$
      begin raise exception 'Synthetic ${stage} failure' using errcode='P0001'; end $$;
      create trigger fixture_claim_failure after ${event} on ${table} for each row execute function public.fixture_claim_failure();`);
    try { await unchangedFailure(asUser(claim()), 'P0001', 'Synthetic'); }
    finally { await db.query(`drop trigger fixture_claim_failure on ${table}; drop function public.fixture_claim_failure();`); }
  });
  await fresh('parallel requests and lost-response replay create one claim and counter increment', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      const financial = await money();
      const receipt = JSON.parse(await first.query(`begin; ${context()} ${claim()};`));
      const waiting = second.query(asUser(claim('100','Concurrent different reason')));
      await blocked(db,second,first); await first.query('commit;');
      assert.deepEqual(JSON.parse(await waiting),receipt);
      assert.deepEqual(await call(),receipt);
      assert.equal(await db.query('select count(*) from public."Refunds";'), '1');
      assert.equal(await db.query(`select refund_attempts from public.profiles where id='${user}';`), '1');
      assert.equal(await money(),financial);
    } finally { await first.close(); await second.close(); }
  });
  await fresh('Auth lock wait rechecks a committed ban before any claim writes', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await rows(), financial = await money();
      await holder.query(`begin; update auth.users set banned_until=now()+interval '1 day' where id='${user}';`);
      const waiting = assert.rejects(waiter.query(asUser(claim())),failure('PT403'));
      await blocked(db,waiter,holder); await holder.query('commit;'); await waiting;
      assert.equal(await rows(),before); assert.equal(await money(),financial);
    } finally { await holder.close(); await waiter.close(); }
  });
  for (const restriction of ['session','terms','deletion','owner']) await fresh(`transaction wait revalidates ${restriction}`, async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      await holder.query('begin; select id from public.transactions where id=100 for no key update;');
      const waiting = assert.rejects(waiter.query(asUser(claim())),failure(restriction==='session'?'PT401':restriction==='owner'?'42501':'PT403'));
      await blocked(db,waiter,holder);
      if (restriction==='session') await db.query(`delete from auth.sessions where id='${sid}';`);
      else if (restriction==='terms') await db.query(`update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null where id='${user}';`);
      else if (restriction==='deletion') await pending();
      else await holder.query(`update public.transactions set user_id='${other}' where id=100;`);
      await holder.query('commit;'); await waiting;
      assert.equal(await db.query('select count(*) from public."Refunds";'),'0');
      assert.equal(await db.query(`select refund_attempts from public.profiles where id='${user}';`),'0');
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('profile wait observes deletion that commits first', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await rows();
      await holder.query(`begin; ${context()} select id from public.profiles where id='${user}' for no key update;`);
      const waiting = assert.rejects(waiter.query(asUser(claim())),failure('PT403'));
      await blocked(db,waiter,holder); await holder.query('select public.request_account_deletion(); commit;');
      await waiting; assert.equal(await rows(),before);
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('session expiry during transaction wait uses wall clock', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await rows();
      await db.query(`update auth.sessions set not_after=clock_timestamp()+interval '1 second' where id='${sid}';`);
      await holder.query('begin; select id from public.transactions where id=100 for no key update;');
      const waiting = assert.rejects(waiter.query(asUser(claim())),failure('PT401'));
      await blocked(db,waiter,holder); await db.query('select pg_sleep(1.1);');
      await holder.query('commit;'); await waiting; assert.equal(await rows(),before);
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('new claim holding profile commits before queued deletion', async () => {
    const creator = await cluster.connect(), deletion = await cluster.connect();
    try {
      await creator.query(`begin; ${context()} ${claim()};`);
      const waiting = deletion.query(asUser('select public.request_account_deletion()'));
      await blocked(db,deletion,creator); await creator.query('commit;'); await waiting;
      assert.equal(await db.query('select count(*) from public."Refunds";'),'1');
      await unchangedFailure(asUser(claim()),'PT403');
    } finally { await creator.close(); await deletion.close(); }
  });
  for (const restriction of ['session','factor','window']) await fresh(`counter-trigger wait rolls all writes back after ${restriction} expires`, async () => {
    if (restriction==='factor') {
      await totp();
      await db.query(`update public.profiles set roles='Admin' where id='${user}';`);
    }
    if (restriction==='window') await db.query("update public.transactions set created_at=clock_timestamp()-interval '14 days'+interval '1 second' where id=100;");
    await db.query(`create function public.fixture_claim_pause() returns trigger language plpgsql as $$
      begin perform pg_advisory_xact_lock(9180614); return new; end $$;
      create trigger fixture_claim_pause after update of refund_attempts on public.profiles
        for each row execute function public.fixture_claim_pause();`);
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await rows(), financial = await money();
      await holder.query('begin; select pg_advisory_xact_lock(9180614);');
      const waiting = assert.rejects(waiter.query(asUser(claim(),claims(restriction==='factor'?{aal:'aal2'}:{}))),
        failure(restriction==='session'?'PT401':restriction==='factor'?'PT403':'22023'));
      await blocked(db,waiter,holder);
      if (restriction==='session') await db.query(`delete from auth.sessions where id='${sid}';`);
      else if (restriction==='factor') await db.query('delete from auth.mfa_factors;');
      else await db.query('select pg_sleep(1.1);');
      await holder.query('commit;'); await waiting;
      assert.equal(await rows(),before); assert.equal(await money(),financial);
    } finally {
      await holder.close(); await waiter.close();
      await db.query('drop trigger fixture_claim_pause on public.profiles; drop function public.fixture_claim_pause();');
    }
  });
  await fresh('read-only replay never waits for an existing refund row held by resolution', async () => {
    const receipt = await call(), resolver = await cluster.connect();
    try {
      const before = await rows();
      await resolver.query(`begin; select refund_id from public."Refunds" where refund_id=${receipt.refund_id} for update;`);
      assert.deepEqual(await call(),receipt); assert.equal(await rows(),before);
      await resolver.query('rollback;');
    } finally { await resolver.close(); }
  });
  await fresh('canonical authority lookup failure cannot save partial claim metadata', async () => {
    await db.query('revoke select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions from postgres;');
    try { await unchangedFailure(asUser(claim()),'PT503'); }
    finally { await db.query('grant select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions to postgres;'); }
  });
});
