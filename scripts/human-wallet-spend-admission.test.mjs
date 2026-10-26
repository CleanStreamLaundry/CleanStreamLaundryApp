import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (p) => readFile(new URL(`../${p}`, import.meta.url), 'utf8');
const migration = (n) => read(`supabase/migrations/${n}.sql`);
const candidate = await migration('20260930171558_human_wallet_spend_admission');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), owner = uid(3), sid = uid(11), vendId = uid(31), factor = uid(21);
const quote = (v) => v === null ? 'null' : `'${String(v).replaceAll("'", "''")}'`;
const claims = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now()/1000) + 3600, ...extra });
const context = (jwt = claims(), role = 'authenticated') =>
  `set local request.jwt.claims=${quote(JSON.stringify(jwt))}; set local request.jwt.claim.sub=''; set local role ${role};`;
const asUser = (sql, jwt, role) => `begin; ${context(jwt, role)} ${sql}; commit;`;
const machine = (amount = 750, target = user) =>
  `select public.redeem_wallet_for_machine('${target}',1,${amount},'Original note')`;
const cortina = (id = vendId) => `select public.redeem_wallet_for_cortina('${id}')`;
const wallet = `(select id from public.wallet_accounts where user_id='${user}')`;

test('human wallet spend admission with actual financial/lifecycle contracts', { timeout: 180000 }, async (t) => {
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
  const call = async (sql, jwt) => JSON.parse(await run(asUser(sql, jwt)));
  const service = (sql) => run(asUser(sql, { role: 'service_role' }, 'service_role'));
  const fixture = (await read('supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS');
  assert.equal(fixture.length, 2);
  // Bootstrap synthetic extensions/owners, then remove superuser for all new
  // candidate DDL and runtime definers. No host/production role is changed.
  await db.query('set client_min_messages=warning; create role postgres superuser; set role postgres;');
  await db.query(fixture[0]);
  for (const n of ['20260526010000_wallet_ledger_compliance', '20260803150427_cortina_qr_remote_vend',
    '20260807191723_harden_refund_resolution', '20260929231120_serialize_wallet_financial_writes']) {
    await db.query(await migration(n));
  }
  // Keep the legacy transaction trigger, but load real link-history SQL once
  // instead of also installing its older definitions from fixture[1].
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
    '20260930125554_voluntary_topup_refunds']) await db.query(await migration(n));
  await db.query(`reset role;
    grant usage,create on schema public to postgres;
    grant select(id,is_anonymous,deleted_at,banned_until,email_confirmed_at),update(id) on auth.users to postgres;
    grant select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions to postgres;
    grant select(id,user_id,factor_type,status) on auth.mfa_factors to postgres;
    alter role postgres nosuperuser bypassrls;`);
  const snapshot = () => db.query(`select jsonb_build_object(
    'wallet',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_accounts x),
    'loads',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_loads x),
    'ledger',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_ledger_entries x),
    'redemptions',(select jsonb_agg(to_jsonb(x) order by id) from public.wallet_redemptions x),
    'cache',(select jsonb_agg(jsonb_build_array(id,balance,reward_tracker) order by id) from public.profiles),
    'vends',(select jsonb_agg(to_jsonb(x) order by id) from public.cortina_vend_sessions x),
    'transactions',(select jsonb_agg(to_jsonb(x) order by id) from public.transactions x),
    'refunds',(select jsonb_agg(to_jsonb(x) order by refund_id) from public."Refunds" x),
    'spend',(select jsonb_agg(to_jsonb(x) order by ledger_id) from private.topup_refund_spend x));`);
  const balance = async () => JSON.parse(await db.query(`select jsonb_build_array(
    paid_balance_cents,promo_balance_cents,(select balance from public.profiles where id='${user}'))
    from public.wallet_balances where wallet_account_id=${wallet};`));
  const bindings = () => db.query(`select jsonb_agg(jsonb_build_array(id,machine_id,washer_size_rate_id,
    amount_cents,currency,payment_method,channel,transaction_id,client_request_id,client_access_token_hash,
    dryer_minutes,product_code,pulse_line_number,nayax_environment,nayax_terminal_id,nayax_uniqr,stripe_livemode)
    order by id) from public.cortina_vend_sessions;`);
  const vend = (id = vendId, amount = 750, target = user) => db.query(`insert into public.cortina_vend_sessions
    (id,client_request_id,client_access_token_hash,machine_id,user_id,amount_cents,payment_method,channel,
      transaction_id,washer_size_rate_id,pulse_line_number)
    values ('${id}','${id}','hash-${id}',1,'${target}',${amount},'wallet','app','${id}',1,1);`);
  let loadNumber = 0;
  const load = (amount = 2000, key = `pi_spend_${++loadNumber}`) =>
    service(`select public.record_wallet_load_from_stripe('${user}',${amount},'${key}')`);
  const reset = async ({ vendAmount = 750 } = {}) => {
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
        values (1,1,'Synthetic washer',12,${vendAmount})
        on conflict(id) do update set price_cents=excluded.price_cents;
      insert into public."Machines"(id,"Location_ID","Machine_type","Name",washer_size_rate_id)
        values (1,1,'Washer','Synthetic washer',1) on conflict do nothing;
      update public.cortina_machine_config set nayax_terminal_id='synthetic-terminal',
        pulse_line_number=1,is_enabled=true,review_required=false where machine_id=1;
      update private.topup_refund_policy set enabled_at=now()-interval '3 days';`);
    await load(); await vend(vendId,vendAmount);
  };
  const fresh = (name, fn, options) => t.test(name, async () => { await reset(options); await fn(); });
  const pending = () => call('select public.request_account_deletion()');
  const totp = () => db.query(`insert into auth.mfa_factors(id,user_id,factor_type,status)
    values ('${factor}','${user}','totp','verified');
    update auth.sessions set aal='aal2',factor_id='${factor}' where id='${sid}';`);
  const metadata = () => db.query(`select jsonb_agg(jsonb_build_object('signature',oid::regprocedure::text,
    'owner',proowner,'acl',proacl,'definer',prosecdef,'args',pg_get_function_arguments(oid),
    'result',pg_get_function_result(oid),'settings',proconfig) order by oid) from pg_proc
    where oid in ('public.redeem_wallet_for_machine(uuid,bigint,integer,text)'::regprocedure,
      'public.redeem_wallet_for_cortina(uuid)'::regprocedure);`);
  const otherFunctions = () => db.query(`select jsonb_object_agg(oid::regprocedure::text,pg_get_functiondef(oid))
    from pg_proc where pronamespace in ('public'::regnamespace,'private'::regnamespace,'auth'::regnamespace)
      and prokind='f' and proname not in ('redeem_wallet_for_machine','redeem_wallet_for_cortina');`);
  await reset();
  const originalMetadata = await metadata(), originalFunctions = await otherFunctions(), originalRows = await snapshot();
  await t.test('missing RPC prerequisite aborts without recreating a PUBLIC entrypoint', async () => {
    const body = candidate.replace(/^begin;$/m,'').replace(/^commit;$/m,'');
    await error(`begin; set local role postgres;
      alter function public.redeem_wallet_for_cortina(uuid) rename to fixture_missing_cortina;
      ${body} commit;`, '55000');
    assert.equal(await metadata(), originalMetadata);
  });
  await db.query(`set role postgres; ${candidate} reset role;`);
  await t.test('only two existing bodies replaced; signatures/defaults/ACLs and all other functions/data preserved', async () => {
    assert.equal(await metadata(), originalMetadata);
    assert.equal(await otherFunctions(), originalFunctions);
    assert.equal(await snapshot(), originalRows);
    assert.equal(await db.query(`select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';`), 't');
    assert.equal((candidate.match(/create or replace function /g) ?? []).length, 2);
  });
  await fresh('admitted direct debit preserves promo-first split, cents, notes, cache and original JSON', async () => {
    const result = await call(machine());
    assert.deepEqual(Object.keys(result).sort(), ['paid_debit_cents','promo_debit_cents','redemption_id','wallet_account_id']);
    assert.equal(result.promo_debit_cents, 500); assert.equal(result.paid_debit_cents, 250);
    assert.deepEqual(await balance(), [1750,0,17.5]);
    assert.equal(await db.query(`select note from public.wallet_redemptions where id=${result.redemption_id};`), 'Original note');
    assert.equal(await db.query('select count(*) from private.topup_refund_spend;'), '2');
  });
  await fresh('Cortina debits once, binds redemption, and preserves nonpayable replay rejection', async () => {
    const frozenBinding = await bindings();
    const result = await call(cortina());
    assert.equal(result.paid_debit_cents, 250); assert.equal(result.promo_debit_cents, 500);
    assert.equal(await db.query(`select status||':'||wallet_redemption_id from public.cortina_vend_sessions where id='${vendId}';`), `paid:${result.redemption_id}`);
    const before = await snapshot();
    await error(asUser(cortina()), 'P0001', 'not payable'); assert.equal(await snapshot(), before);
    assert.equal(await bindings(), frozenBinding);
    assert.equal(await db.query(`select nayax_environment||':'||nayax_terminal_id||':'||pulse_line_number
      from public.cortina_vend_sessions where id='${vendId}';`), 'sandbox:synthetic-terminal:1');
  });
  for (const [name, change, code] of [
    ['terms missing', `update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null where id='${user}'`, 'PT403'],
    ['terms stale', `update public.profiles set loyalty_policy_version='old' where id='${user}'`, 'PT403'],
    ['unverified', `update auth.users set email_confirmed_at=null where id='${user}'`, 'PT403'],
    ['anonymous', `update auth.users set is_anonymous=true where id='${user}'`, 'PT403'],
    ['banned', `update auth.users set banned_until=now()+interval '1 day' where id='${user}'`, 'PT403'],
    ['Auth deleted', `update auth.users set deleted_at=now() where id='${user}'`, 'PT403'],
    ['unknown role', `update public.profiles set roles=null where id='${user}'`, 'PT403'],
    ['staff missing MFA', `update public.profiles set roles='Owner' where id='${user}'`, 'PT403'],
    ['session revoked', `delete from auth.sessions where id='${sid}'`, 'PT401'],
    ['session expired', `update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`, 'PT401'],
  ]) await fresh(`${name} denies both human RPCs without financial writes`, async () => {
    await db.query(change); const before = await snapshot();
    await error(asUser(machine()), code); await error(asUser(cortina()), code);
    assert.equal(await snapshot(), before);
  });
  for (const extra of [{ exp:1 }, {session_id:uid(12)}, {aal:'aal3'}, {role:'service_role'}]) {
    await fresh(`canonical claims fail closed ${JSON.stringify(extra)}`, async () => {
      const before = await snapshot();
      await error(asUser(machine(), claims(extra)), 'PT401');
      await error(asUser(cortina(), claims(extra)), 'PT401');
      assert.equal(await snapshot(), before);
    });
  }
  for (const expired of [false,true]) await fresh(`pending deletion rejects both, expired=${expired}`, async () => {
    await pending();
    if (expired) await db.query(`update private.account_lifecycle set deletion_requested_at=now()-interval '721 hours',restore_until=now()-interval '1 hour';`);
    const before = await snapshot();
    await error(asUser(machine()), 'PT403'); await error(asUser(cortina()), 'PT403');
    assert.equal(await snapshot(), before);
  });
  await fresh('restoration admits only a fresh session, preserving prior wallet links', async () => {
    await pending();
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values ('${uid(14)}','${user}','aal1',clock_timestamp());`);
    const jwt = claims({session_id:uid(14)});
    await call('select public.restore_account()', jwt);
    await error(asUser(machine()), 'PT401'); await call(machine(), jwt);
    assert.deepEqual(await balance(), [1750,0,17.5]);
  });
  await fresh('optional customer TOTP and staff TOTP reuse exact current-factor requirements', async () => {
    await totp(); await error(asUser(machine()), 'PT403');
    await call(machine(100), claims({aal:'aal2'}));
    await db.query(`update public.profiles set roles='Admin' where id='${user}';`);
    await call(cortina(), claims({aal:'aal2'}));
    await db.query('delete from auth.mfa_factors;');
    await error(asUser(machine(), claims({aal:'aal2'})), 'PT403');
  });
  await fresh('anon grants and mismatched caller cannot debit; no service attribution invented', async () => {
    const before = await snapshot();
    await error(asUser(machine(), {}, 'anon'), '42501');
    await error(asUser(cortina(), {}, 'anon'), '42501');
    await error(asUser(machine(100, other)), 'P0001', 'Unauthorized');
    await error(asUser(cortina(), claims({sub:other,session_id:uid(12)})), 'P0001', 'Unauthorized');
    await error(asUser(machine(), claims({role:'service_role'}), 'service_role'), 'PT401');
    assert.equal(await snapshot(), before);
  });
  await fresh('locked wallet, insufficient funds and invalid amount retain financial errors', async () => {
    const before = await snapshot();
    await error(asUser(machine(0)), 'P0001', 'Invalid amount');
    await error(asUser(machine(2501)), 'P0001', 'Insufficient balance');
    assert.equal(await snapshot(), before);
    await db.query(`update public.wallet_accounts set status='locked' where user_id='${user}';`);
    const locked = await snapshot();
    await error(asUser(machine()), 'P0001', 'Wallet is not active');
    await error(asUser(cortina()), 'P0001', 'Wallet is not active');
    assert.equal(await snapshot(), locked);
  });
  await fresh('failed first debit cannot leave a newly created empty wallet behind', async () => {
    const before = await snapshot();
    await error(asUser(machine(1,other), claims({sub:other,session_id:uid(12)})), 'P0001', 'Insufficient balance');
    assert.equal(await snapshot(), before);
  });
  await fresh('refund reservation stays unavailable to either debit entrypoint', async () => {
    const intent = await db.query(`select stripe_payment_intent_id from public.wallet_loads where user_id='${user}';`);
    await service(`select public.record_topup_refund_provenance('${intent}','${user}',2000,clock_timestamp()-interval '1 minute','evt_reservation',false)`);
    const id = await db.query(`select id from public.wallet_loads where user_id='${user}';`);
    await call(`select public.request_voluntary_topup_refund(${id})`);
    assert.deepEqual(await balance(), [0,0,0]); const before = await snapshot();
    await error(asUser(machine(1)), 'P0001', 'Insufficient balance');
    await error(asUser(cortina()), 'P0001', 'Insufficient balance');
    assert.equal(await snapshot(), before);
  });
  await fresh('captured funding settles once despite pending deletion and a locked wallet', async () => {
    await pending(); await db.query(`update public.wallet_accounts set status='locked' where user_id='${user}';`);
    const first = await load(1000, 'pi_settlement');
    assert.equal(await load(1000, 'pi_settlement'), first);
    assert.deepEqual(await balance(), [3000,500,35]);
  });
  await fresh('service reversal restores original paid/promo once after deletion request', async () => {
    const frozenBinding = await bindings();
    await call(cortina()); await pending();
    assert.equal(await service(`select public.reverse_cortina_wallet_redemption('${vendId}')`), 't');
    assert.equal(await service(`select public.reverse_cortina_wallet_redemption('${vendId}')`), 'f');
    assert.deepEqual(await balance(), [2000,500,25]);
    assert.equal(await db.query('select status from public.wallet_redemptions;'), 'void');
    assert.equal(await bindings(), frozenBinding);
  });
  await fresh('existing service refund resolution still credits pending-deletion customer', async () => {
    await pending();
    const refundId = await db.query(`insert into public."Refunds"(user_id,amount,description)
      values ('${user}',2,'Existing support claim') returning refund_id;`);
    const result = JSON.parse(await service(`select public.resolve_refund_request(${refundId},'approved','Existing resolution','${owner}')`));
    assert.equal(result.status, 'approved'); assert.deepEqual(await balance(), [2000,700,27]);
  });

  await fresh('Auth lock wait rechecks a committed ban before acquiring money locks', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await snapshot();
      await holder.query(`begin; update auth.users set banned_until=now()+interval '1 day' where id='${user}';`);
      const waiting = assert.rejects(waiter.query(asUser(machine())), failure('PT403'));
      await blocked(db,waiter,holder); await holder.query('commit;'); await waiting;
      assert.equal(await snapshot(), before);
    } finally { await holder.close(); await waiter.close(); }
  });
  for (const restriction of ['deletion','session','terms']) await fresh(`wallet wait rechecks ${restriction} without holding profile first`, async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await snapshot();
      await holder.query(`begin; select id from public.wallet_accounts where id=${wallet} for no key update;`);
      const waiting = assert.rejects(waiter.query(asUser(machine())), failure(restriction==='session'?'PT401':'PT403'));
      await blocked(db,waiter,holder);
      if (restriction === 'deletion') await pending();
      else if (restriction === 'session') await db.query(`delete from auth.sessions where id='${sid}';`);
      else await db.query(`update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null where id='${user}';`);
      await holder.query('commit;'); await waiting; assert.equal(await snapshot(), before);
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('profile wait observes deletion committed while debit owns its wallet lock', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await snapshot();
      await holder.query(`begin; ${context()} select id from public.profiles where id='${user}' for no key update;`);
      const waiting = assert.rejects(waiter.query(asUser(machine())), failure('PT403'));
      await blocked(db,waiter,holder);
      await holder.query('select public.request_account_deletion(); commit;');
      await waiting; assert.equal(await snapshot(), before);
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('Cortina session wait rechecks revoked session before debit', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await snapshot();
      await holder.query(`begin; select id from public.cortina_vend_sessions where id='${vendId}' for update;`);
      const waiting = assert.rejects(waiter.query(asUser(cortina())), failure('PT401'));
      await blocked(db,waiter,holder); await db.query(`delete from auth.sessions where id='${sid}';`);
      await holder.query('commit;'); await waiting; assert.equal(await snapshot(), before);
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('session deadline uses wall clock after a wallet wait, not transaction start', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      await db.query(`update auth.sessions set not_after=clock_timestamp()+interval '1 second' where id='${sid}';`);
      const before = await snapshot();
      await holder.query(`begin; select id from public.wallet_accounts where id=${wallet} for no key update;`);
      const waiting = assert.rejects(waiter.query(asUser(machine())), failure('PT401'));
      await blocked(db,waiter,holder); await db.query('select pg_sleep(1.1);');
      assert.equal(await db.query(`select clock_timestamp()>not_after from auth.sessions where id='${sid}';`), 't');
      await holder.query('commit;'); await waiting; assert.equal(await snapshot(), before);
    } finally { await holder.close(); await waiter.close(); }
  });
  for (const stage of ['ledger','cache','cortina-status']) await fresh(`post-${stage} wait rolls back all money effects after revocation`, async () => {
    const table = stage==='ledger'?'public.wallet_ledger_entries':stage==='cache'?'public.profiles':'public.cortina_vend_sessions';
    const event = stage==='ledger'?'insert':stage==='cache'?'update of balance':'update of status';
    const when = stage==='cortina-status'?"when (new.status='paid')":'';
    await db.query(`create function public.fixture_pause_spend() returns trigger language plpgsql as $$
      begin perform pg_advisory_xact_lock(917558); return new; end $$;
      create trigger fixture_pause_spend after ${event} on ${table} for each row ${when}
        execute function public.fixture_pause_spend();`);
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await snapshot();
      await holder.query('begin; select pg_advisory_xact_lock(917558);');
      const waiting = assert.rejects(waiter.query(asUser(stage==='cortina-status'?cortina():machine())), failure('PT401'));
      await blocked(db,waiter,holder); await db.query(`delete from auth.sessions where id='${sid}';`);
      await holder.query('commit;'); await waiting; assert.equal(await snapshot(), before);
    } finally {
      await holder.close(); await waiter.close();
      await db.query(`drop trigger fixture_pause_spend on ${table}; drop function public.fixture_pause_spend();`);
    }
  });
  await fresh('staff factor removal during ledger-trigger wait rolls back the debit', async () => {
    await totp(); await db.query(`update public.profiles set roles='Admin' where id='${user}';
      create function public.fixture_pause_spend() returns trigger language plpgsql as $$
      begin perform pg_advisory_xact_lock(917558); return new; end $$;
      create trigger fixture_pause_spend after insert on public.wallet_ledger_entries for each row
        execute function public.fixture_pause_spend();`);
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      const before = await snapshot(); await holder.query('begin; select pg_advisory_xact_lock(917558);');
      const waiting = assert.rejects(waiter.query(asUser(machine(),claims({aal:'aal2'}))), failure('PT403'));
      await blocked(db,waiter,holder); await db.query('delete from auth.mfa_factors;');
      await holder.query('commit;'); await waiting; assert.equal(await snapshot(), before);
    } finally {
      await holder.close(); await waiter.close();
      await db.query('drop trigger fixture_pause_spend on public.wallet_ledger_entries; drop function public.fixture_pause_spend();');
    }
  });
  await fresh('admitted debit holding profile completes before a queued deletion request', async () => {
    const spender = await cluster.connect(), deletion = await cluster.connect();
    try {
      await spender.query(`begin; ${context()} ${machine()};`);
      const waiting = deletion.query(asUser('select public.request_account_deletion()'));
      await blocked(db,deletion,spender); await spender.query('commit;'); await waiting;
      assert.deepEqual(await balance(), [1750,0,17.5]);
      await error(asUser(machine(1)), 'PT403');
    } finally { await spender.close(); await deletion.close(); }
  });
  await fresh('different Cortina sessions still serialize against one wallet and cannot overspend', async () => {
    await vend(uid(32),2000);
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; ${context()} ${cortina()};`);
      const waiting = assert.rejects(second.query(asUser(cortina(uid(32)))), failure('P0001','Insufficient balance'));
      await blocked(db,second,first); await first.query('commit;'); await waiting;
      assert.deepEqual(await balance(), [500,0,5]);
      assert.equal(await db.query('select count(*) from public.wallet_redemptions;'), '1');
      assert.equal(await db.query(`select status from public.cortina_vend_sessions where id='${uid(32)}';`), 'payment_pending');
    } finally { await first.close(); await second.close(); }
  }, { vendAmount: 2000 });
  await fresh('canonical lookup failure cannot make a partial debit', async () => {
    const before = await snapshot();
    await db.query('revoke select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions from postgres;');
    try { await error(asUser(machine()), 'PT503'); assert.equal(await snapshot(), before); }
    finally { await db.query('grant select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions to postgres;'); }
  });

  // Observe every waiter before releasing its blocker; retain early SQL errors
  // without leaving a rejected promise unhandled while blocked() is inspecting it.
  const settle = (promise) => promise.then((value) => ({ value }), (error) => ({ error }));
  await fresh('remaining-payment: duplicate card funding and competing Start claims commit once', async () => {
    const id = uid(33), beforeBalance = await balance();
    await db.query(`insert into public.cortina_vend_sessions
      (id,client_request_id,client_access_token_hash,machine_id,user_id,amount_cents,payment_method,channel,
       transaction_id,washer_size_rate_id,pulse_line_number)
      values ('${id}','${id}','hash-${id}',1,'${user}',750,'card','app','${id}',1,1);
      update public.cortina_vend_sessions set stripe_payment_intent_id='pi_remaining_funding' where id='${id}';`);
    const fund = `select public.record_cortina_card_payment('${id}','evt_remaining_funding',
      'pi_remaining_funding',null,'ch_remaining_funding',750,'usd',false)`;
    // Same conditional transition as startVend; no provider Start is invoked.
    const start = `with claimed as (
      update public.cortina_vend_sessions set status='starting',start_requested_at=clock_timestamp()
      where id='${id}' and status='paid' returning id
    ) select count(*) from claimed`;
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      assert.equal(new Set([db.pid,first.pid,second.pid]).size, 3);
      await first.query(`begin; ${context({role:'service_role'},'service_role')} ${fund};`);
      const funding = settle(second.query(asUser(fund,{role:'service_role'},'service_role')));
      await blocked(db,second,first); await first.query('commit;');
      assert.ifError((await funding).error);
      assert.equal(await db.query(`select status from public.cortina_vend_sessions where id='${id}';`), 'paid');
      const audit = `select jsonb_agg(jsonb_build_object('session',session_id,'source',source,'type',event_type,
        'key',event_key,'payload',payload) order by id) from public.cortina_vend_events where session_id='${id}';`;
      assert.deepEqual(JSON.parse(await db.query(audit)), [{ session:id, source:'stripe', type:'payment_succeeded',
        key:'stripe:evt_remaining_funding', payload:{ payment_intent_id:'pi_remaining_funding',
          checkout_session_id:null, charge_id:'ch_remaining_funding', amount_received:750, currency:'USD', livemode:false } }]);
      assert.equal(await first.query(`begin; ${context({role:'service_role'},'service_role')} ${start};`), '1');
      const starting = settle(second.query(asUser(start,{role:'service_role'},'service_role')));
      await blocked(db,second,first); await first.query('commit;');
      const result = await starting;
      assert.ifError(result.error); assert.equal(result.value, '0');
      assert.equal(await db.query(`select status='starting' and start_requested_at is not null
        from public.cortina_vend_sessions where id='${id}';`), 't');
      const started = JSON.parse(await snapshot()), fundedAudit = await db.query(audit);
      await service(fund);
      const replayed = JSON.parse(await snapshot());
      // The existing UPDATE trigger refreshes only this incidental timestamp on a valid replay.
      replayed.vends.find((row) => row.id === id).updated_at = started.vends.find((row) => row.id === id).updated_at;
      assert.deepEqual(replayed, started); assert.equal(await db.query(audit), fundedAudit);
      assert.deepEqual(await balance(), beforeBalance);
      assert.equal(await db.query('select count(*) from public.wallet_redemptions;'), '0');
    } finally { await first.close(); await second.close(); }
  });

  await fresh('remaining-payment: competing callback ownership rolls back the losing audit and binding', async () => {
    const secondId = uid(32), beforeBalance = await balance();
    await vend(secondId);
    // Synthetic callback-eligible states only; this fixture never dispatches a vend.
    await db.query(`update public.cortina_vend_sessions set status='starting' where id in ('${vendId}','${secondId}');`);
    const evidence = (id) => `select jsonb_build_object(
      'session',(select to_jsonb(s) from public.cortina_vend_sessions s where id='${id}'),
      'events',(select jsonb_agg(to_jsonb(e) order by id) from public.cortina_vend_events e where session_id='${id}'));`;
    const callback = (id, kind) => `insert into public.cortina_vend_events(session_id,source,event_type,event_key,payload)
      values ('${id}','nayax','${kind}','nayax:sandbox:${kind==='sale_end'?'sale-end':kind}:7654321',
        jsonb_build_object('BasicInfo',jsonb_build_object('TransactionId','${id}',
          'NayaxTransactionId','7654321','Amount',7.5,'CurrencyCode','USD'),
          'MachineInfo',jsonb_build_object('TerminalId','synthetic-terminal')))`;
    const loserBefore = await db.query(evidence(secondId));
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      assert.equal(new Set([db.pid,first.pid,second.pid]).size, 3);
      await first.query(`begin; ${context({role:'service_role'},'service_role')} ${callback(vendId,'sale')};`);
      const winner = await first.query(evidence(vendId));
      // Different event keys force the provider-ownership index, not event-key deduplication, to arbitrate.
      const waiting = settle(second.query(asUser(callback(secondId,'sale_end'),{role:'service_role'},'service_role')));
      await blocked(db,second,first); await first.query('commit;');
      const result = await waiting;
      assert(result.error); failure('23505','cortina_nayax_environment_transaction_key')(result.error);
      assert.equal(await db.query(evidence(vendId)), winner);
      assert.equal(await db.query(evidence(secondId)), loserBefore);
      assert.equal(await db.query(`select count(*) from public.cortina_vend_sessions
        where nayax_environment='sandbox' and nayax_transaction_id='7654321';`), '1');
      assert.equal(await db.query("select count(*) from public.cortina_vend_events where source='nayax';"), '1');
      assert.deepEqual(await balance(), beforeBalance);
    } finally { await first.close(); await second.close(); }
  });

  await fresh('remaining-payment: reconciliation lease expires during a row wait without a stale write', async () => {
    // Install the real worker contract only for this child, leaving older fixture cases unchanged.
    await db.query(`set role postgres; ${await migration('20260930161734_cortina_closed_app_reconciliation')} reset role;`);
    const due = `update public.cortina_vend_sessions set reconcile_after=clock_timestamp()-interval '1 second'
      where id='${vendId}';`;
    await db.query(due);
    const claim = JSON.parse(await service("select public.claim_cortina_reconciliation('sandbox')"));
    assert.equal(claim.id, vendId); assert(claim.reconcile_claim);
    const finish = (token) => `select public.finish_cortina_reconciliation('${vendId}','${token}',
      'manual_review','synthetic_lease_wait')`;
    const events = 'select coalesce(jsonb_agg(to_jsonb(e) order by id),\'[]\'::jsonb) from public.cortina_vend_events e;';
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      assert.equal(new Set([db.pid,holder.pid,waiter.pid]).size, 3);
      // Shorten only the synthetic lease, then let wall-clock expiry occur while the row is locked.
      await db.query(`update public.cortina_vend_sessions set reconcile_claim_until=clock_timestamp()+interval '2 seconds'
        where id='${vendId}';`);
      const before = await snapshot(), beforeEvents = await db.query(events), beforeBalance = await balance();
      await holder.query(`begin; ${context({role:'service_role'},'service_role')}
        select id from public.cortina_vend_sessions where id='${vendId}' for update;`);
      assert.equal(await db.query(`select clock_timestamp()<reconcile_claim_until
        from public.cortina_vend_sessions where id='${vendId}';`), 't');
      const waiting = settle(waiter.query(asUser(finish(claim.reconcile_claim),{role:'service_role'},'service_role')));
      await blocked(db,waiter,holder);
      assert.equal(await db.query(`select a.query_start<s.reconcile_claim_until
        from pg_stat_activity a cross join public.cortina_vend_sessions s
        where a.pid=${waiter.pid} and s.id='${vendId}';`), 't');
      await holder.query(`select pg_sleep(greatest(0,extract(epoch from (reconcile_claim_until-clock_timestamp())))+0.05)
        from public.cortina_vend_sessions where id='${vendId}';`);
      assert.equal(await db.query(`select clock_timestamp()>reconcile_claim_until
        from public.cortina_vend_sessions where id='${vendId}';`), 't');
      await holder.query('commit;');
      const result = await waiting;
      assert.ifError(result.error); assert.equal(result.value, 'f');
      assert.equal(await snapshot(), before); assert.equal(await db.query(events), beforeEvents);
      await db.query(due);
      const replacement = JSON.parse(await service("select public.claim_cortina_reconciliation('sandbox')"));
      assert.equal(replacement.id, vendId);
      assert.notEqual(replacement.reconcile_claim, claim.reconcile_claim);
      assert.equal(replacement.reconcile_attempts, 2);
      assert.equal(await service(finish(claim.reconcile_claim)), 'f');
      assert.equal(await service(finish(replacement.reconcile_claim)), 't');
      assert.equal(await db.query(`select status='support_required' and reconcile_claim is null and reconcile_after is null
        from public.cortina_vend_sessions where id='${vendId}';`), 't');
      assert.deepEqual(JSON.parse(await db.query(events)).map((event) => event.event_key), [`reconcile:${replacement.reconcile_claim}`]);
      assert.deepEqual(await balance(), beforeBalance);
    } finally { await holder.close(); await waiter.close(); }
  });
});
