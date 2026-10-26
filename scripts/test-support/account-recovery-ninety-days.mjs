import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { read, uid } from './account-cleanup.mjs';
import { blocked } from './policy-admission-pg.mjs';

const version = 'retention-paid-credit-2026-10-05';
const hash = '0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04';
const oldVersion = 'retention-paid-credit-2026-10-02';
const oldHash = '756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592';
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const errorCode = code => error => { assert.equal(error.code, code, error.message); return true; };

// Full catalog-matched prerequisite harness, synthetic local identities only.
// Run in the composer serial slot with RECOVERY_90_DAY_ONLY=1.
export async function exerciseNinetyDayRecovery({ db, run, check, cluster }) {
  const migration = await read('supabase/migrations/20261005134908_ninety_day_account_recovery.sql');
  const apply = () => run(`set role postgres; ${migration}`);
  const service = sql => run(`set role service_role; ${sql};`);
  const context = (p, extra = {}) => `set local request.jwt.claims=${q(JSON.stringify({
    sub: p.id, session_id: p.session, role: 'authenticated', aal: 'aal1',
    exp: Math.floor(Date.now() / 1000) + 3600, ...extra,
  }))}; set local request.jwt.claim.sub=''; set local role authenticated;`;
  const human = (p, sql, extra) => run(`begin; ${context(p, extra)} ${sql}; commit;`);
  const row = p => db.query(`select to_jsonb(l) from private.account_lifecycle l where user_id='${p.id}';`).then(JSON.parse);
  const person = async (n, ageDays, restored = false) => {
    const p = { id: uid(n), session: uid(n + 10000), claim: uid(n + 20000) };
    await run(`set role supabase_auth_admin;
      insert into auth.users(id,email,email_confirmed_at) values('${p.id}','recovery-${n}@example.invalid',now());
      insert into auth.sessions(id,user_id,aal,created_at)
        values('${p.session}','${p.id}','aal1',clock_timestamp());`);
    await db.query(`insert into public.profiles(id,email,full_name,roles,reward_tracker,
      loyalty_policy_version,loyalty_policy_accepted_at)
      values('${p.id}','recovery-${n}@example.invalid','Synthetic recovery subject','User',0,
        '2026-10-03.1',clock_timestamp()-interval '1 day');`);
    if (ageDays !== undefined) {
      await db.query(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until,restored_at)
        select '${p.id}',d,d+interval '720 hours',${restored ? "d+interval '1 hour'" : 'null'}
        from (select clock_timestamp()-${ageDays}*interval '24 hours' d) x;`);
    }
    return p;
  };
  // Service has no private-table read grants; pass a captured request timestamp.
  const claimAt = async p => service(`select public.claim_account_cleanup('${p.id}',
    ${q((await row(p)).deletion_requested_at)},'${p.claim}')`);
  const money = () => db.query(`select jsonb_build_object(
    'wallets',(select jsonb_agg(to_jsonb(w) order by id) from public.wallet_accounts w),
    'loads',(select jsonb_agg(to_jsonb(w) order by id) from public.wallet_loads w),
    'ledger',(select jsonb_agg(to_jsonb(w) order by id) from public.wallet_ledger_entries w));`);
  const functions = () => db.query(`select jsonb_agg(jsonb_build_array(oid,proowner,proacl) order by oid)
    from pg_proc where oid in ('public.request_account_deletion()'::regprocedure,
      'private.request_account_deletion()'::regprocedure,
      'public.restore_account()'::regprocedure,'private.require_account_cleanup_policy(text,text)'::regprocedure,
      'private.guard_account_cleanup_auth_delete()'::regprocedure,'private.prune_account_cleanup_retention()'::regprocedure);`);
  const pending = await person(6001, 40), expired = await person(6002, 100);
  const restored = await person(6003, 20, true), retired = await person(6004, 100);
  const longer = await person(6005, 10), newUser = await person(6006);
  const wallet = await service(`select public.record_wallet_load_from_stripe('${pending.id}',2400,'pi_ninety_day');`);
  await db.query(`insert into private.mail_outbox(event_key,kind,user_id,email,
    lifecycle_requested_at,lifecycle_restore_until)
    select 'SYNTHETIC-old-deadline','account_deletion_scheduled',user_id,'recovery-6001@example.invalid',
      deletion_requested_at,restore_until from private.account_lifecycle where user_id='${pending.id}';`);

  await check('90-day fixture: completed removal uses the real cleanup fences and retains paid value', async () => {
    await service(`select public.record_wallet_load_from_stripe('${retired.id}',1500,'pi_ninety_retired')`);
    const requested = (await row(retired)).deletion_requested_at;
    await db.query(`update private.account_cleanup_execution set execution_enabled=true,
      approved_policy_version='${oldVersion}',approved_policy_sha256='${oldHash}',final_policy_approved_at=clock_timestamp();
      insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
        hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
        backup_disposition_reference,financial_retention_reference)
      values('${retired.id}',${q(requested)},'${restored.id}',clock_timestamp(),
        'SYNTHETIC','SYNTHETIC','SYNTHETIC','SYNTHETIC','SYNTHETIC');`);
    const dispatch = JSON.parse(await service(`select public.execute_account_cleanup_step('${retired.claim}',
      '${oldVersion}','${oldHash}','${retired.id}',${q(requested)})`));
    assert.equal(dispatch.action, 'auth');
    await run(`set role supabase_auth_admin; delete from auth.users where id='${retired.id}';`);
    const ack = JSON.parse(await service(`select public.acknowledge_account_cleanup('${retired.id}',
      ${q(requested)},'${retired.claim}','${dispatch.operation_id}','${oldVersion}','${oldHash}','returned')`));
    assert.equal(ack.status, 'account_removed');
  });

  await check('90-day migration refuses enabled cleanup and rolls back without adding columns', async () => {
    await assert.rejects(apply(), /Stop cleanup execution/);
    assert.equal(await db.query(`select count(*) from information_schema.columns
      where table_schema='private' and table_name='account_lifecycle' and column_name='recovery_window_days';`), '0');
    await db.query('update private.account_cleanup_execution set execution_enabled=false;');
  });

  await check('90-day migration refuses an in-flight worker transaction without waiting', async () => {
    const holder = await cluster.connect();
    try {
      await holder.query('begin; select * from private.account_cleanup_execution;');
      await assert.rejects(apply(), errorCode('55P03'));
    } finally { await holder.close(); }
  });

  await check('90-day migration refuses unresolved destructive dispatch and never clears its evidence', async () => {
    assert.equal(JSON.parse(await claimAt(pending)).claimed, true);
    const holder = await cluster.connect();
    try {
      // Commit the synthetic marker, then explicitly remove only this test marker.
      await holder.query(`update private.account_cleanup_jobs set external_operation='{"kind":"auth"}'
        where user_id='${pending.id}';`);
      await assert.rejects(apply(), /requires reconciliation/);
      assert.equal(await db.query(`select external_operation->>'kind' from private.account_cleanup_jobs
        where user_id='${pending.id}';`), 'auth');
      await holder.query(`update private.account_cleanup_jobs set external_operation=null where user_id='${pending.id}';`);
    } finally { await holder.close(); }
  });

  await check('90-day fixture represents a preexisting longer deadline without changing the candidate', async () => {
    // Existing source enforces equality. Model an operator's earlier extension
    // to verify this migration never shortens it, even under a relaxed old check.
    const name = await db.query(`select conname from pg_constraint
      where conrelid='private.account_lifecycle'::regclass and contype='c'
      and pg_get_constraintdef(oid) like '%restore_until%deletion_requested_at%'
      and pg_get_constraintdef(oid) not like '%restored_at%';`);
    assert.match(name, /^[a-z_]+$/);
    await db.query(`alter table private.account_lifecycle drop constraint ${name};
      alter table private.account_lifecycle add constraint ${name}
        check(restore_until>=deletion_requested_at+interval '720 hours');
      update private.account_lifecycle set restore_until=deletion_requested_at+interval '2880 hours'
        where user_id='${longer.id}';`);
  });
  const before = new Map();
  for (const p of [pending, expired, restored, retired, longer]) before.set(p.id, await row(p));
  const moneyBefore = await money(), grantsBefore = await functions();
  const restoreBody = await db.query("select pg_get_functiondef('public.restore_account()'::regprocedure);");
  const requestWrapper = await db.query("select pg_get_functiondef('public.request_account_deletion()'::regprocedure);");
  const oldDocument = await db.query("select document::text from public.loyalty_policy_documents where is_current;");
  const acceptBefore = await db.query(`select jsonb_build_array(loyalty_policy_version,loyalty_policy_accepted_at)
    from public.profiles where id='${newUser.id}';`);

  await check('90-day migration extends only pending surviving identities, preserving money, request clocks and ACLs', async () => {
    await apply();
    for (const p of [pending, expired, longer]) {
      const result = await row(p), old = before.get(p.id);
      assert.equal(result.deletion_requested_at, old.deletion_requested_at);
      assert.equal(Date.parse(result.restore_until), Math.max(Date.parse(old.restore_until),
        Date.parse(old.deletion_requested_at) + 90 * 86400000));
      assert.equal(result.recovery_window_days, 90); assert.equal(result.restored_at, null);
    }
    for (const p of [restored, retired]) {
      const { recovery_window_days, ...result } = await row(p);
      assert.equal(recovery_window_days, 30); assert.deepEqual(result, before.get(p.id));
    }
    assert.equal(await money(), moneyBefore); assert.equal(await functions(), grantsBefore);
    assert.equal(await db.query("select pg_get_functiondef('public.restore_account()'::regprocedure);"), restoreBody);
    assert.equal(await db.query("select pg_get_functiondef('public.request_account_deletion()'::regprocedure);"), requestWrapper);
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${retired.id}')
      and not exists(select 1 from public.profiles where id='${retired.id}');`), 't');
    assert.equal(await db.query(`select state='suppressed'
      and lifecycle_restore_until=lifecycle_requested_at+interval '720 hours'
      from private.mail_outbox where event_key='SYNTHETIC-old-deadline';`), 't');
  });

  await check('90-day policy pins match, old approvals are invalidated and paid credit remains protected', async () => {
    const contract = `${version}|restore=90-days-explicit|delete=auth-profile|paid=no-expiry-no-forfeiture|promo=cancel-at-final-deletion|unresolved=retain|reclaim=verified-owner-support`;
    assert.equal(createHash('sha256').update(contract).digest('hex'), hash);
    const gate = await db.query("select pg_get_functiondef('private.require_account_cleanup_policy(text,text)'::regprocedure);");
    assert(gate.includes(version)); assert(gate.includes(hash));
    assert.equal(await db.query(`select not execution_enabled and not credit_forfeiture_enabled
      and approved_policy_version is null and approved_policy_sha256 is null
      and final_policy_approved_at is null from private.account_cleanup_execution;`), 't');
    assert.deepEqual(JSON.parse(await db.query(`select jsonb_build_array(paid_balance_cents,promo_balance_cents)
      from public.wallet_balances where wallet_account_id='${wallet}';`)), [2400, 500]);
  });

  await check('90-day prerequisite publishes no obsolete .1 policy and preserves every acceptance', async () => {
    const descriptor = JSON.parse(await run('set role anon; select public.get_loyalty_policy_descriptor();'));
    assert.equal(descriptor.required_version, '2026-10-03.1');
    assert.equal(createHash('sha256').update(descriptor.policy_text).digest('hex'), descriptor.policy_sha256);
    assert.equal(descriptor.policy_text, oldDocument);
    assert.equal(await db.query("select count(*) from public.loyalty_policy_documents where version='2026-10-05.1';"),'0');
    assert.equal(await db.query("select document::text from public.loyalty_policy_documents where version='2026-10-03.1';"), oldDocument);
    assert.equal(await db.query(`select jsonb_build_array(loyalty_policy_version,loyalty_policy_accepted_at)
      from public.profiles where id='${newUser.id}';`), acceptBefore);
    assert.equal(JSON.parse(await human(newUser, 'select public.get_admission_status()')).next_step, 'home');
    await assert.rejects(human(newUser, "select public.accept_loyalty_policy('2026-10-05.1')"), errorCode('22023'));
  });

  await check('90-day extended request rejects stale cleanup claim; status alone never restores', async () => {
    assert.equal(JSON.parse(await claimAt(pending)).reason, 'recovery_window_open');
    const state = JSON.parse(await human(pending, 'select public.get_account_lifecycle_status()'));
    assert.equal(state.reason, 'explicit_restore_required'); assert.equal(state.account_access, 'restricted');
    assert.equal((await row(pending)).restored_at, null);
    await assert.rejects(human(expired, 'select public.restore_account()'), /restore_expired/);
    await assert.rejects(human(retired, 'select public.restore_account()'), errorCode('PT401'));
  });

  await check('90-day restore retains fresh-session, subject, verified-email and MFA requirements', async () => {
    await assert.rejects(human(pending, 'select public.restore_account()', { session_id: newUser.session }), errorCode('PT401'));
    await run(`set role supabase_auth_admin; update auth.sessions set created_at=clock_timestamp()-interval '11 minutes'
      where id='${pending.session}';`);
    await assert.rejects(human(pending, 'select public.restore_account()'), /fresh_session_required/);
    await run(`set role supabase_auth_admin; update auth.sessions set created_at=clock_timestamp() where id='${pending.session}';
      update auth.users set email_confirmed_at=null where id='${pending.id}';`);
    await assert.rejects(human(pending, 'select public.restore_account()'), errorCode('PT403'));
    await run(`set role supabase_auth_admin; update auth.users set email_confirmed_at=now() where id='${pending.id}';
      insert into auth.mfa_factors(id,user_id,factor_type,status,created_at)
        values('${uid(6601)}','${pending.id}','totp','verified',now());`);
    await assert.rejects(human(pending, 'select public.restore_account()'), errorCode('PT403'));
    await run(`set role supabase_auth_admin; update auth.sessions set aal='aal2',factor_id='${uid(6601)}'
      where id='${pending.session}';`);
    const restorer = await cluster.connect(), cleaner = await cluster.connect();
    let waiting;
    let result;
    try {
      result = JSON.parse(await restorer.query(`begin; ${context(pending, { aal: 'aal2' })}
        select public.restore_account();`));
      waiting = cleaner.query(`set role service_role; select public.claim_account_cleanup('${pending.id}',
        ${q((await row(pending)).deletion_requested_at)},'${pending.claim}');`)
        .then(value => ({ value }), error => ({ error }));
      await blocked(db, cleaner, restorer); await restorer.query('commit;');
      const outcome = await waiting; assert.ifError(outcome.error);
      assert.equal(JSON.parse(outcome.value).reason, 'request_not_pending');
    } finally { await restorer.close(); await cleaner.close(); if (waiting) await waiting; }
    assert.equal(result.account_state, 'legacy_active'); assert.equal(result.next_step, 'home');
    const stored = await row(pending); assert.equal(stored.marketing_suppressed, true);
    await human(pending, 'select public.restore_account()', { aal: 'aal2' });
    assert.deepEqual(await row(pending), stored); assert.equal(await money(), moneyBefore);
  });

  await check('90-day new requests and re-requests use 2160 UTC hours and duplicates preserve the deadline', async () => {
    assert.equal(await db.query("select has_function_privilege('authenticated','public.request_account_deletion()','execute');"), 'f');
    // Authorized local fixture only: the candidate preserved the held grant.
    await db.query(`grant execute on function public.request_account_deletion() to authenticated;
      update private.mail_settings set enabled=true,rollout_at=clock_timestamp()-interval '1 day';`);
    for (const p of [newUser, restored]) {
      await human(p, 'select public.request_account_deletion()');
      const first = await row(p);
      assert.equal(first.recovery_window_days, 90);
      assert.equal(Date.parse(first.restore_until) - Date.parse(first.deletion_requested_at), 90 * 86400000);
      await human(p, 'select public.request_account_deletion()');
      assert.deepEqual(await row(p), first);
      assert.equal(await db.query(`select count(*) from private.mail_outbox
        where user_id='${p.id}' and kind='account_deletion_scheduled'
          and lifecycle_restore_until=lifecycle_requested_at+interval '2160 hours';`), '1');
      await assert.rejects(human(p, 'select public.restore_account()'), /fresh_session_required/);
    }
  });

  await check('90-day deadline excludes equality and restoration rechecks expiry after a profile lock wait', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    let waiting;
    try {
      await db.query(`update private.account_lifecycle set deletion_requested_at=clock_timestamp()-interval '2161 hours',
        restore_until=clock_timestamp()-interval '1 hour' where user_id='${longer.id}';`);
      await assert.rejects(human(longer, 'select public.restore_account()'), /restore_expired/);
      await db.query(`update private.account_lifecycle set deletion_requested_at=t-interval '2159 hours',
        restore_until=t+interval '1 hour' from (select clock_timestamp() t) x where user_id='${longer.id}';`);
      await holder.query(`begin; update private.account_lifecycle set deletion_requested_at=t-interval '2160 hours',
        restore_until=t from (select clock_timestamp() t) x where user_id='${longer.id}';
        select id from public.profiles where id='${longer.id}' for no key update;`);
      waiting = waiter.query(`begin; ${context(longer)} select public.restore_account(); commit;`)
        .then(value => ({ value }), error => ({ error }));
      await blocked(db, waiter, holder); await holder.query('commit;');
      const outcome = await waiting; assert.equal(outcome.error?.code, 'PT403');
      assert.match(outcome.error.message, /restore_expired/);
      assert.equal((await row(longer)).restored_at, null);
    } finally { await holder.close(); await waiter.close(); if (waiting) await waiting; }
  });
}
