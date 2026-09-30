import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const prerequisites = [];
for (const path of [
  '../supabase/tests/loyalty_policy_acceptance.fixture.sql',
  '../supabase/migrations/20260929223124_protect_profile_authority.sql',
  '../supabase/migrations/20260929234955_loyalty_policy_acceptance.sql',
  '../supabase/tests/account_admission.fixture.sql',
  '../supabase/migrations/20260930005456_account_admission.sql',
  '../supabase/tests/profile_terms_admission.fixture.sql',
  '../supabase/migrations/20260930013417_enforce_profile_terms_admission.sql',
  '../supabase/tests/account_lifecycle.fixture.sql',
]) prerequisites.push(await read(path));
const migration = await read('../supabase/migrations/20260930063923_recoverable_account_deletion.sql');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11), otherSid = uid(12), freshSid = uid(13), factor = uid(21);
const literal = (v) => `'${v.replaceAll("'", "''")}'`;
const claims = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (jwt, role = 'authenticated') =>
  `set local request.jwt.claims=${literal(JSON.stringify(jwt))};
   set local request.jwt.claim.sub=''; set local role ${role};`;
const asUser = (sql, jwt = claims(), role) => `begin; ${context(jwt, role)} ${sql}; commit;`;
const request = 'select public.request_account_deletion()';
const restore = 'select public.restore_account()';
const status = 'select public.get_account_lifecycle_status()';
const freshClaims = (extra = {}) => claims({ session_id: freshSid, ...extra });

test('recoverable lifecycle in disposable PostgreSQL 17', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const run = async (sql) => {
    const connection = await cluster.connect();
    try { return await connection.query(sql); } finally { await connection.close(); }
  };
  const call = async (sql, jwt = claims(), role) => JSON.parse(await run(asUser(sql, jwt, role)));
  const denied = (sql, code = 'PT403', jwt = claims(), role) =>
    assert.rejects(run(asUser(sql, jwt, role)), (error) => {
      assert.equal(error.code, code, error.message); return true;
    });
  for (const sql of prerequisites) await db.query(sql);
  const acl = () => db.query(`select jsonb_agg(jsonb_build_array(oid::regclass::text,relacl) order by oid)
    from pg_class where relnamespace in ('auth'::regnamespace,'public'::regnamespace) and relkind='r';`);
  const beforeAcl = await acl();
  await db.query(migration);
  const reset = () => db.query(`truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${other}',now());
    insert into auth.sessions(id,user_id,aal,created_at) values
      ('${sid}','${user}','aal1',now()-interval '1 hour'),
      ('${otherSid}','${other}','aal1',now()-interval '1 hour');
    update public.profiles set balance=4200,reward_tracker=3,refund_attempts=2,
      loyalty_policy_version='existing-policy',loyalty_policy_accepted_at='2026-01-01Z';
    insert into public.wallet_accounts values ('${uid(31)}','${user}',4200,'2026-01-01Z');
    insert into public.wallet_loads values ('${uid(32)}','${uid(31)}','${user}',5000,'2026-01-01Z');
    insert into public.wallet_redemptions values ('${uid(33)}','${uid(31)}','${user}',800,true,'2026-01-02Z');
    insert into public.transactions values ('${uid(34)}','${user}',800,'2026-01-02Z');
    insert into public."Refunds" values ('${uid(35)}','${user}','pending','2026-01-03Z',null);`);
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });
  const login = () => db.query(`insert into auth.sessions(id,user_id,aal,created_at)
    values ('${freshSid}','${user}','aal1',clock_timestamp());`);
  const stored = async () => JSON.parse(await db.query(`select to_jsonb(l) from private.account_lifecycle l where user_id='${user}';`) || 'null');
  const snapshot = async () => {
    const rows = {};
    for (const table of ['auth.users', 'auth.sessions', 'auth.mfa_factors', 'public.profiles',
      'public.wallet_accounts', 'public.wallet_loads', 'public.wallet_redemptions', 'public.transactions', 'public."Refunds"']) {
      rows[table] = await db.query(`select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from ${table} t;`);
    }
    return rows;
  };
  const totp = async (role = 'User') => db.query(`update public.profiles set roles='${role}' where id='${user}';
    insert into auth.mfa_factors(id,user_id,factor_type,status) values ('${factor}','${user}','totp','verified');
    update auth.sessions set aal='aal2',factor_id='${factor}' where user_id='${user}';`);

  await t.test('migration preserves every existing public/Auth table ACL', async () => assert.equal(await acl(), beforeAcl));
  await fresh('request sets exactly 720 hours, denies stale JWT ordinary access, leaves all records intact', async () => {
    const before = await snapshot();
    const result = await call(request);
    assert.deepEqual(Object.keys(result).sort(), ['subject_id','account_access','next_step','reason','account_state','restore_until'].sort());
    assert.equal(result.account_state, 'pending_deletion');
    assert.equal(result.account_access, 'restricted');
    assert.equal(result.next_step, 'blocked');
    const row = await stored();
    assert.equal(Date.parse(row.restore_until)-Date.parse(row.deletion_requested_at), 30*24*60*60*1000);
    assert.equal(await call('select to_json(private.account_access_allowed())'), false);
    assert.equal(await call('select count(*) from public.profiles'), 0);
    assert.equal(await call(`with changed as (update public.profiles set full_name='changed' returning *) select count(*) from changed`), 0);
    await denied('select public.ensure_own_profile(\'overwrite\')');
    await denied('select public.get_loyalty_policy_status()');
    await denied('select public.accept_loyalty_policy(\'existing-policy\')');
    assert.deepEqual(await snapshot(), before);
    assert.equal(row.marketing_suppressed, true);
  });
  await fresh('duplicates preserve original request/deadline including expired pending', async () => {
    await call(request);
    const before = await stored();
    await call(request);
    assert.deepEqual(await stored(), before);
    await db.query(`update private.account_lifecycle set deletion_requested_at=now()-interval '721 hours',restore_until=now()-interval '1 hour';`);
    const expired = await stored();
    assert.equal((await call(request)).reason, 'restore_expired');
    assert.deepEqual(await stored(), expired);
    assert.equal(await call('select to_json(private.account_access_allowed())'), false);
  });
  await fresh('login/status never restores; explicit restore preserves identity, clocks, records and suppression', async () => {
    await call(request); await login();
    const before = await snapshot();
    assert.equal((await call(status, freshClaims())).account_state, 'pending_deletion');
    assert.equal((await stored()).restored_at, null);
    const result = await call(restore, freshClaims());
    assert.equal(result.account_state, 'legacy_active');
    assert.equal(result.next_step, 'review_terms');
    assert.equal(result.restore_until, null);
    assert.deepEqual(await snapshot(), before);
    const restored = await stored();
    assert.equal(restored.marketing_suppressed, true);
    await call(restore, freshClaims());
    assert.deepEqual(await stored(), restored);
    await denied(status, 'PT401');
    await denied(request, 'PT401');
  });
  await fresh('old session with newly minted JWT cannot restore', async () => {
    await call(request);
    await denied(restore, 'PT403', claims({ iat: Math.floor(Date.now()/1000) }));
    assert.equal((await stored()).restored_at, null);
  });
  for (const created of ['null', "now()+interval '1 minute'", "now()-interval '10 minutes'", "now()-interval '11 minutes'", 'l.deletion_requested_at']) {
    await fresh(`restore denies session created_at ${created}`, async () => {
      await call(request); await login();
      if (created.includes('minutes')) await db.query(`update private.account_lifecycle set deletion_requested_at=now()-interval '1 hour',restore_until=now()+interval '719 hours';`);
      await db.query(`update auth.sessions set created_at=${created} from private.account_lifecycle l where id='${freshSid}';`);
      await denied(restore, 'PT403', freshClaims());
    });
  }
  await fresh('deadline equal to transaction clock rejects restore and cannot be stored as restored_at', async () => {
    await call(request); await login();
    await db.query(`update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours',restore_until=now();`);
    await denied(restore, 'PT403', freshClaims());
    await assert.rejects(run(`update private.account_lifecycle set restored_at=restore_until;`), { code: '23514' });
    assert.equal((await call(status, freshClaims())).reason, 'restore_expired');
    assert.equal((await stored()).restored_at, null);
  });
  await fresh('restore succeeds immediately before deadline', async () => {
    await call(request); await login();
    await db.query(`update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours'+interval '5 seconds',restore_until=now()+interval '5 seconds';`);
    assert.equal((await call(restore, freshClaims())).account_state, 'legacy_active');
  });
  for (const extra of [{ session_id: otherSid }, { session_id: uid(999) }, { exp: 1 }, { aal: 'aal3' }, { role: 'service_role' }, { session_id: 'malformed' }]) {
    await fresh(`invalid caller session ${JSON.stringify(extra)}`, async () => {
      for (const sql of [request, restore, status]) await denied(sql, 'PT401', claims(extra));
      assert.equal(await stored(), null);
    });
  }
  await fresh('other caller cannot inspect or restore target; RPCs accept no target parameter', async () => {
    await call(request);
    const otherJwt = claims({ sub: other, session_id: otherSid });
    assert.equal((await call(status, otherJwt)).subject_id, other);
    assert.equal((await call(status, otherJwt)).restore_until, null);
    await denied(restore, 'PT403', otherJwt);
    await denied(`select public.restore_account('${user}')`, '42883', otherJwt);
    assert.equal((await stored()).restored_at, null);
  });
  for (const restriction of [
    `update auth.users set banned_until=now()+interval '1 hour' where id='${user}'`,
    `update auth.users set email_confirmed_at=null where id='${user}'`,
    `update auth.users set is_anonymous=true where id='${user}'`,
    `update auth.users set deleted_at=now() where id='${user}'`,
    `update public.profiles set roles=null where id='${user}'`,
    `update auth.sessions set not_after=now()-interval '1 second' where user_id='${user}'`,
  ]) {
    await fresh(`current restriction remains authoritative: ${restriction}`, async () => {
      await call(request); await login(); await db.query(restriction);
      const code = restriction.includes('not_after') ? 'PT401' : 'PT403';
      await denied(restore, code, freshClaims()); await denied(request, code);
      assert.equal((await stored()).restored_at, null);
    });
  }
  for (const role of ['User','Admin','Owner']) {
    await fresh(`${role} restoration requires current bound TOTP and both AAL2 values`, async () => {
      await call(request); await login(); await totp(role);
      await denied(restore, 'PT403', freshClaims());
      await db.query(`update auth.sessions set aal='aal1' where id='${freshSid}';`);
      await denied(restore, 'PT403', freshClaims({ aal: 'aal2' }));
      await db.query(`update auth.sessions set aal='aal2',factor_id='${uid(99)}' where id='${freshSid}';`);
      await denied(restore, 'PT403', freshClaims({ aal: 'aal2' }));
      await db.query(`update auth.sessions set factor_id='${factor}' where id='${freshSid}';`);
      assert.equal((await call(restore, freshClaims({ aal: 'aal2' }))).account_access, 'eligible');
    });
  }
  for (const type of ['phone','webauthn','recovery_code']) {
    await fresh(`unsupported verified ${type} blocks request and restore`, async () => {
      await call(request); await login(); await totp();
      await db.query(`update auth.mfa_factors set factor_type='${type}';`);
      await denied(request, 'PT403', claims({ aal: 'aal2' }));
      await denied(restore, 'PT403', freshClaims({ aal: 'aal2' }));
    });
  }
  await fresh('Admin without verified factors remains blocked; role downgrade is never restored', async () => {
    await call(request); await login();
    await db.query(`update public.profiles set roles='Admin' where id='${user}';`);
    await denied(restore, 'PT403', freshClaims());
    await db.query(`update public.profiles set roles='User' where id='${user}';`);
    await call(restore, freshClaims());
    assert.equal(await db.query(`select roles from public.profiles where id='${user}';`), 'User');
  });
  await fresh('removed/foreign factor cannot satisfy Admin recovery', async () => {
    await call(request); await login(); await totp('Admin');
    await db.query(`update auth.mfa_factors set user_id='${other}';`);
    await denied(restore, 'PT403', freshClaims({ aal: 'aal2' }));
  });
  await fresh('private state and RPC ACLs deny public/anon/service bypass', async () => {
    for (const role of ['anon','service_role','supabase_auth_admin']) {
      for (const sql of [request, restore, status]) await denied(sql, '42501', claims(), role);
    }
    for (const sql of ['select * from private.account_lifecycle',
      'update private.account_lifecycle set restored_at=now()', 'select private.current_account_access()']) {
      await denied(sql, '42501');
    }
  });

  await fresh('concurrent duplicate requests serialize and retain one deadline', async () => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${context(claims())}`);
    const first = JSON.parse(await holder.query(request));
    const waiting = waiter.query(asUser(request));
    await blocked(db, waiter, holder);
    await holder.query('commit');
    assert.deepEqual(JSON.parse(await waiting), first);
  });
  await fresh('request wins lock, fresh restore waits then restores the same request', async () => {
    await call(request); await login();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${context(claims())} ${request};`);
    const waiting = waiter.query(asUser(restore, freshClaims()));
    await blocked(db, waiter, holder); await holder.query('commit');
    assert.equal(JSON.parse(await waiting).account_state, 'legacy_active');
  });
  await fresh('restore wins lock; queued old-session request cannot delete restored account', async () => {
    await call(request); await login();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${context(freshClaims())} ${restore};`);
    const waiting = waiter.query(asUser(request));
    const rejected = assert.rejects(waiting, { code: 'PT401' });
    await blocked(db, waiter, holder); await holder.query('commit'); await rejected;
    assert.notEqual((await stored()).restored_at, null);
  });
  await fresh('concurrent restores preserve original restored timestamp', async () => {
    await call(request); await login();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${context(freshClaims())} ${restore};`);
    const waiting = waiter.query(asUser(restore, freshClaims()));
    await blocked(db, waiter, holder); await holder.query('commit');
    const first = await stored(); await waiting;
    assert.deepEqual(await stored(), first);
  });
  await fresh('deadline is checked after lock wait, not transaction/statement start', async () => {
    await call(request); await login();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; select id from public.profiles where id='${user}' for no key update;
      update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours'+interval '300 milliseconds',restore_until=now()+interval '300 milliseconds';`);
    const waiting = waiter.query(asUser(restore, freshClaims()));
    const rejected = assert.rejects(waiting, { code: 'PT403' });
    await blocked(db, waiter, holder); await holder.query('select pg_sleep(0.4); commit'); await rejected;
    assert.equal((await stored()).restored_at, null);
  });
  await fresh('current ban committed during profile wait is rechecked', async () => {
    await call(request); await login();
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; select id from auth.users where id='${user}' for update;
      update auth.users set banned_until=now()+interval '1 hour' where id='${user}';`);
    const waiting = waiter.query(asUser(restore, freshClaims()));
    const rejected = assert.rejects(waiting, { code: 'PT403' });
    await blocked(db, waiter, holder); await holder.query('commit'); await rejected;
    assert.equal((await stored()).restored_at, null);
  });
});
