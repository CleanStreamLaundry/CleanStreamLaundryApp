import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const guardPath = process.env.POLICY_TEST_PROFILE_GUARD;
assert(guardPath && isAbsolute(guardPath), 'Set POLICY_TEST_PROFILE_GUARD to the reviewed authority migration');
const authorityGuard = await readFile(guardPath, 'utf8');
assert.match(authorityGuard, /create function public\.guard_profile_protected_fields\(\)/);
const policyFixture = await read('../supabase/tests/loyalty_policy_acceptance.fixture.sql');
const policyMigration = await read('../supabase/migrations/20260929234955_loyalty_policy_acceptance.sql');
const fixture = await read('../supabase/tests/account_admission.fixture.sql');
const migration = await read('../supabase/migrations/20260930005456_account_admission.sql');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11), otherSid = uid(12), factor = uid(21);
const literal = (v) => v === null ? 'null' : `'${v.replaceAll("'", "''")}'`;
const claims = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (jwt, role = 'authenticated', subject = '') =>
  `set local request.jwt.claims=${literal(JSON.stringify(jwt))};
   set local request.jwt.claim.sub=${literal(subject)}; set local role ${role};`;
const asUser = (jwt, sql, role, subject) => `begin; ${context(jwt, role, subject)} ${sql}; commit;`;
const statusSql = 'select public.get_admission_status()';
const allowedSql = 'select private.account_access_allowed()';
const ensureSql = (name = 'OAuth Name') => `select public.ensure_own_profile(${literal(name)})`;
const expected = (extra = {}) => ({ subject_id: user, account_access: 'restricted',
  next_step: 'blocked', reason: null, account_state: 'legacy_active', restore_until: null, ...extra });
const eligible = expected({ account_access: 'eligible', next_step: 'review_terms' });

test('account admission foundation on disposable PostgreSQL 17', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const run = async (sql) => {
    const s = await cluster.connect();
    try { return await s.query(sql); } finally { await s.close(); }
  };
  const call = async (jwt = claims(), sql = statusSql, role) => JSON.parse(await run(asUser(jwt, sql, role)));
  const error = (sql, code, message) => assert.rejects(run(sql), (e) => {
    assert.equal(e.code, code, e.message);
    if (message) assert.match(e.message, new RegExp(`ERROR:  ${code}: ${message}(?:\\n|$)`));
    assert(!e.message.includes('SYNTHETIC_SECRET_ERROR'), 'Internal failure leaked');
    return true;
  });
  const reset = async () => {
    await db.query(`truncate auth.users cascade;
      insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${other}',now());
      insert into auth.sessions(id,user_id,aal) values ('${sid}','${user}','aal1'),('${otherSid}','${other}','aal1');`);
  };
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });
  const setRole = (role) => db.query(`update public.profiles set roles=${literal(role)} where id='${user}';`);
  const totp = (status = 'verified', id = factor, owner = user, type = 'totp') =>
    db.query(`insert into auth.mfa_factors(id,user_id,factor_type,status)
      values ('${id}','${owner}',${literal(type)},${literal(status)});`);
  const sessionAal2 = (id = factor) => db.query(`update auth.sessions set aal='aal2',factor_id=${literal(id)} where id='${sid}';`);
  const stored = (id = user) => db.query(`select to_jsonb(p) from public.profiles p where id='${id}';`);
  const check = async (value, jwt = claims()) => {
    assert.deepEqual(await call(jwt), value);
    assert.equal(await run(asUser(jwt, allowedSql)), value.account_access === 'eligible' ? 't' : 'f');
  };

  await db.query(policyFixture);
  await db.query(authorityGuard);
  await db.query(policyMigration);
  await db.query(fixture);
  await reset();
  const policyDefinitions = () => db.query(`select jsonb_agg(pg_get_functiondef(p.oid) order by p.proname)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
    and p.proname in ('get_loyalty_policy_descriptor','get_loyalty_policy_status','accept_loyalty_policy');`);
  const existingAccess = () => db.query(`select jsonb_build_object(
    'policies',(select jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname) from pg_policies p),
    'grants',(select jsonb_agg(to_jsonb(g) order by grantee,table_name,column_name,privilege_type)
      from information_schema.column_privileges g where table_schema in ('public','auth')));`);
  const before = { policies: await existingAccess(), definitions: await policyDefinitions(), row: await stored() };
  await db.query(migration);

  await t.test('foundation changes no existing policies, column grants, terms routines or profile rows', async () => {
    assert.equal(await existingAccess(), before.policies);
    assert.equal(await policyDefinitions(), before.definitions);
    assert.equal(await stored(), before.row);
    assert.equal(await db.query(`select count(*) from pg_attribute where attrelid='public.profiles'::regclass
      and attnum>0 and not attisdropped;`), '11');
  });
  await t.test('four narrow functions have explicit signatures, safe paths and API ACLs', async () => {
    const rows = JSON.parse(await db.query(`select jsonb_agg(to_jsonb(g) order by name) from (
      select p.proname as name,p.prosecdef as definer,p.proconfig as config,
      pg_get_function_arguments(p.oid) as args,pg_get_function_result(p.oid) as result
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where (n.nspname,p.proname) in (('private','current_account_access'),('private','account_access_allowed'),
        ('public','get_admission_status'),('public','ensure_own_profile'))) g;`));
    assert.equal(rows.length, 4);
    for (const row of rows) {
      assert.equal(row.definer, true);
      assert.deepEqual(row.config, ['search_path=""']);
      assert.equal(row.args, row.name === 'ensure_own_profile' ? 'p_full_name text' : '');
      assert.equal(row.result, row.name === 'ensure_own_profile' ? 'void'
        : row.name === 'account_access_allowed' ? 'boolean' : 'jsonb');
    }
    assert.equal(await db.query(`select bool_and(not has_function_privilege(r.role,f.fn,'EXECUTE'))
      from (values ('anon'),('service_role'),('supabase_auth_admin'),('policy_no_access')) r(role)
      cross join (values ('private.current_account_access()'),('private.account_access_allowed()'),
        ('public.get_admission_status()'),('public.ensure_own_profile(text)')) f(fn);`), 't');
    assert.equal(await db.query(`select not has_function_privilege('authenticated','private.current_account_access()','EXECUTE')
      and has_function_privilege('authenticated','private.account_access_allowed()','EXECUTE')
      and has_function_privilege('authenticated','public.get_admission_status()','EXECUTE')
      and has_function_privilege('authenticated','public.ensure_own_profile(text)','EXECUTE');`), 't');
    for (const role of ['anon', 'service_role']) {
      await error(asUser(claims(), statusSql, role), '42501');
      await error(asUser(claims(), ensureSql(), role), '42501');
    }
    await error(asUser(claims(), 'select private.current_account_access()'), '42501');
    await error(asUser(claims(), `select public.get_admission_status('${other}',true)`), '42883');
    await error(asUser(claims(), `select public.ensure_own_profile('Name','${other}')`), '42883');
  });
  await fresh('bootstrap exposes six keys only and reuses terms without autoconsent', async () => {
    await check(eligible);
    const row = JSON.parse(await stored());
    assert.equal(row.loyalty_policy_version, null);
    assert.equal(row.loyalty_policy_accepted_at, null);
    const descriptor = await call(claims(), 'select public.get_loyalty_policy_descriptor()');
    const accepted = await call(claims(), `select public.accept_loyalty_policy(${literal(descriptor.required_version)})`);
    await check({ ...eligible, next_step: 'home' });
    assert.equal(JSON.parse(await stored()).loyalty_policy_accepted_at, accepted.accepted_at);
  });

  for (const role of ['User', 'Admin', 'Owner']) {
    for (const state of ['none', 'unverified', 'verified']) {
      await fresh(`${role} with ${state} TOTP at AAL1`, async () => {
        await setRole(role);
        if (state !== 'none') await totp(state);
        const next = state === 'verified' ? 'challenge_totp' : role === 'User' ? 'review_terms' : 'enroll_totp';
        await check(next === 'review_terms' ? eligible : expected({ next_step: next }));
      });
    }
    await fresh(`${role} requires current JWT/session/factor proof for AAL2`, async () => {
      await setRole(role);
      await totp();
      await sessionAal2();
      await check(eligible, claims({ aal: 'aal2' }));
      await check(expected({ next_step: 'challenge_totp' }), claims());
      await db.query(`update auth.sessions set aal='aal1' where id='${sid}';`);
      await check(expected({ next_step: 'challenge_totp' }), claims({ aal: 'aal2' }));
    });
  }
  for (const type of ['phone', 'webauthn', 'recovery_code']) {
    for (const role of ['User', 'Owner']) {
      await fresh(`verified ${type} is unsupported for ${role}, even with separate verified TOTP`, async () => {
        await setRole(role);
        await totp();
        await totp('verified', uid(22), user, type);
        await sessionAal2();
        await check(expected({ reason: 'unsupported_factor' }), claims({ aal: 'aal2' }));
      });
    }
  }
  for (const [name, factorId, setup] of [
    ['null session factor', null, async () => {}],
    ['missing session factor', uid(999), async () => {}],
    ['other-user factor', uid(22), () => totp('verified', uid(22), other)],
    ['unverified session factor', uid(22), () => totp('unverified', uid(22))],
  ]) {
    await fresh(`${name} cannot borrow proof from an unrelated verified factor`, async () => {
      await totp();
      await setup();
      await sessionAal2(factorId);
      await check(expected({ next_step: 'challenge_totp' }), claims({ aal: 'aal2' }));
    });
  }
  await fresh('staff final-factor removal stays blocked despite stale AAL2; optional User may be unenrolled', async () => {
    await setRole('Admin');
    await totp(); await sessionAal2();
    await db.query(`delete from auth.mfa_factors where id='${factor}';`);
    await check(expected({ next_step: 'enroll_totp' }), claims({ aal: 'aal2' }));
    await setRole('User');
    await check(eligible, claims({ aal: 'aal2' }));
  });

  for (const [name, extra] of [
    ['missing subject', { sub: null }], ['invalid subject', { sub: 'not-a-uuid' }],
    ['missing session', { session_id: null }], ['invalid session', { session_id: 'bad-session' }],
    ['wrong-owner session', { session_id: otherSid }], ['absent session', { session_id: uid(999) }],
    ['missing JWT AAL', { aal: null }], ['unknown JWT AAL', { aal: 'aal3' }],
    ['service JWT role', { role: 'service_role' }], ['missing expiry', { exp: null }],
    ['expired JWT', { exp: 0 }], ['nonnumeric expiry', { exp: 'future' }],
    ['string expiry', { exp: '9999999999' }],
  ]) {
    await fresh(`${name} fails closed for bootstrap, boolean and provisioning`, async () => {
      for (const sql of [statusSql, allowedSql, ensureSql()]) {
        await error(asUser(claims(extra), sql), 'PT401', 'session_invalid');
      }
    });
  }
  await fresh('JWT subject must match auth.uid and malformed claims never leak parse errors', async () => {
    await error(asUser(claims(), statusSql, 'authenticated', other), 'PT401', 'session_invalid');
    await error(`begin; set local role authenticated; set local request.jwt.claims='SYNTHETIC_SECRET_ERROR';
      ${statusSql}; commit;`, 'PT401', 'session_invalid');
  });
  for (const [name, sql] of [
    ['null session AAL', `update auth.sessions set aal=null where id='${sid}'`],
    ['unsupported session AAL3', `update auth.sessions set aal='aal3' where id='${sid}'`],
    ['expired not_after', `update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`],
    ['revoked session', `delete from auth.sessions where id='${sid}'`],
    ['deleted Auth user', `delete from auth.users where id='${user}'`],
  ]) {
    await fresh(`${name} is session_invalid`, async () => {
      await db.query(sql);
      for (const fn of [statusSql, allowedSql, ensureSql()]) await error(asUser(claims(), fn), 'PT401', 'session_invalid');
    });
  }
  for (const [name, sql] of [
    ['anonymous', `is_anonymous=true`], ['soft deleted', 'deleted_at=now()'],
    ['banned', "banned_until=now()+interval '1 day'"],
  ]) {
    await fresh(`${name} Auth account gets restricted status and cannot provision`, async () => {
      await db.query(`update auth.users set ${sql} where id='${user}';`);
      await check(expected({ account_state: 'blocked', reason: 'account_restricted' }));
      await error(asUser(claims(), ensureSql()), 'PT403', 'account_restricted');
    });
  }
  await fresh('unverified email can provision defaults but cannot access ordinary account data', async () => {
    await db.query(`update auth.users set email_confirmed_at=null where id='${user}';
      delete from public.profiles where id='${user}';`);
    await check(expected({ next_step: 'verify_email' }));
    assert.equal(await run(asUser(claims(), ensureSql())), '');
    const row = JSON.parse(await stored());
    assert.equal(row.id, user); assert.equal(row.full_name, 'OAuth Name');
    assert.equal(row.roles, 'User'); assert.equal(row.balance, 0); assert.equal(row.reward_tracker, 0);
    assert.equal(row.loyalty_policy_version, null); assert.equal(row.loyalty_policy_accepted_at, null);
    await check(expected({ next_step: 'verify_email' }));
    await error(asUser(claims(), 'select public.get_loyalty_policy_status()'), '42501');
  });
  await fresh('missing profile never auto-provisions on a status read; explicit provisioning inserts name only', async () => {
    await db.query(`delete from public.profiles where id='${user}';`);
    await check(expected({ reason: 'profile_missing' }));
    assert.equal(await stored(), '');
    await run(asUser(claims(), ensureSql("Name ' with quotes")));
    assert.equal(JSON.parse(await stored()).full_name, "Name ' with quotes");
    await check(eligible);
  });
  await fresh('existing profile and consent are unchanged by provisioning replay', async () => {
    const descriptor = await call(claims(), 'select public.get_loyalty_policy_descriptor()');
    await call(claims(), `select public.accept_loyalty_policy(${literal(descriptor.required_version)})`);
    await db.query(`update public.profiles set roles='Owner',balance=25,reward_tracker=3,full_name='Existing' where id='${user}';`);
    const before = await stored(), otherBefore = await stored(other);
    await run(asUser(claims(), ensureSql('Overwrite attempt')));
    assert.equal(await stored(), before); assert.equal(await stored(other), otherBefore);
    await check(expected({ next_step: 'enroll_totp' }));
  });
  await fresh('null or unknown profile role never falls back to User or gets repaired by provisioning', async () => {
    await setRole(null);
    await check(expected({ reason: 'role_unavailable' }));
    await run(asUser(claims(), ensureSql()));
    assert.equal(JSON.parse(await stored()).roles, null);
    await db.query(`alter type public."Roles" add value 'fixture_future_role';`);
    await setRole('fixture_future_role');
    await check(expected({ reason: 'role_unavailable' }));
  });
  await fresh('editable metadata and extra JWT gate flags never bypass current role/factor state', async () => {
    await setRole('Owner');
    await db.query(`update auth.users set raw_user_meta_data='{"roles":"User","mfa_required":false,"account_state":"active"}' where id='${user}';`);
    await check(expected({ next_step: 'enroll_totp' }), claims({ roles: 'User', mfa_override: true, aal: 'aal2' }));
  });
  await fresh('nullable or old activity timestamps invent no timeout when hosted limits are off', async () => {
    await db.query(`update auth.sessions set created_at='2000-01-01',updated_at=null,
      refreshed_at='2000-01-01',not_after=null where id='${sid}';`);
    await check(eligible);
    await error(asUser(claims({ exp: 0 }), statusSql), 'PT401', 'session_invalid');
  });
  await fresh('unknown future factor status is not treated as unverified enrollment', async () => {
    await db.query("alter type auth.factor_status add value 'fixture_future_status';");
    await totp('fixture_future_status');
    await check(expected({ reason: 'unsupported_factor' }));
  });
  await t.test('unsafe private CREATE privileges abort the migration without rewriting functions', async () => {
    const before = await db.query("select pg_get_functiondef('private.current_account_access()'::regprocedure);");
    await db.query('grant create on schema private to authenticated;');
    try {
      await error(migration, '42501', 'Untrusted private schema CREATE privilege requires review');
      assert.equal(await db.query("select pg_get_functiondef('private.current_account_access()'::regprocedure);"), before);
    } finally { await db.query('revoke create on schema private from authenticated;'); }
  });
  await t.test('missing reviewed terms prerequisite aborts migration', async () => {
    await db.query('alter function public.get_loyalty_policy_status() rename to fixture_hidden_policy_status;');
    try { await error(migration, '55000', 'Reviewed loyalty policy prerequisite is missing'); }
    finally { await db.query('alter function public.fixture_hidden_policy_status() rename to get_loyalty_policy_status;'); }
  });

  await fresh('bootstrap/provisioning need no direct profile SELECT and never bypass protected-column guards', async () => {
    await db.query(`create policy fixture_no_profile_access on public.profiles as restrictive
      for all to authenticated using (false) with check (false);
      delete from public.profiles where id='${user}';`);
    try {
      assert.equal(await run(asUser(claims(), 'select count(*) from public.profiles')), '0');
      await run(asUser(claims(), ensureSql()));
      await check(eligible);
      assert.equal(await run(asUser(claims(), 'select count(*) from public.profiles')), '0');
    } finally { await db.query('drop policy fixture_no_profile_access on public.profiles;'); }
    await error(asUser(claims(), `update public.profiles set roles='Owner' where id='${user}'`), '42501');
    await error(asUser(claims(), `update public.profiles set loyalty_policy_version='forged' where id='${user}'`), '42501');
  });
  await fresh('canonical evaluator uses column-limited lookup grants without any Auth secret access', async () => {
    await totp(); await sessionAal2();
    await db.query(`grant usage,create on schema private to admission_lookup_fixture;
      alter function private.current_account_access() owner to admission_lookup_fixture;
      revoke create on schema private from admission_lookup_fixture;
      revoke select on public.profiles from public;`);
    try {
      await check(eligible, claims({ aal: 'aal2' }));
      for (const table of ['sessions', 'mfa_factors']) {
        await error(`begin; set local role admission_lookup_fixture;
          select fixture_secret from auth.${table}; commit;`, '42501');
        await error(asUser(claims(), `select id from auth.${table}`), '42501');
      }
      await error(asUser(claims(), 'select id from auth.users'), '42501');
      await db.query('revoke select(id,user_id,aal,factor_id,not_after) on auth.sessions from admission_lookup_fixture;');
      await error(asUser(claims(), statusSql), 'PT503', 'admission_unavailable');
    } finally {
      await db.query(`alter function private.current_account_access() owner to policy_fixture;
        grant select on public.profiles to public;
        grant select(id,user_id,aal,factor_id,not_after) on auth.sessions to admission_lookup_fixture;`);
    }
  });
  await fresh('missing factor lookup is unavailable, never interpreted as no enrollment', async () => {
    await db.query('alter table auth.mfa_factors rename to fixture_hidden_factors;');
    try {
      for (const sql of [statusSql, allowedSql, ensureSql()]) await error(asUser(claims(), sql), 'PT503', 'admission_unavailable');
    } finally { await db.query('alter table auth.fixture_hidden_factors rename to mfa_factors;'); }
  });
  await fresh('unexpected internal lookup errors are sanitized', async () => {
    const definition = await db.query("select pg_get_functiondef('auth.jwt()'::regprocedure);");
    await db.query(`create or replace function auth.jwt() returns jsonb language plpgsql stable as $$
      begin raise exception 'SYNTHETIC_SECRET_ERROR'; end; $$;`);
    try {
      for (const sql of [statusSql, allowedSql, ensureSql()]) await error(asUser(claims(), sql), 'PT503', 'admission_unavailable');
    } finally { await db.query(definition); }
  });
  await fresh('boolean adapter composes with owner RLS without profile recursion', async () => {
    await db.query(`create table public.fixture_private_rows(user_id uuid);
      insert into public.fixture_private_rows values ('${user}'),('${other}');
      alter table public.fixture_private_rows enable row level security;
      grant select on public.fixture_private_rows to authenticated;
      create policy fixture_owner on public.fixture_private_rows for select to authenticated using (user_id=auth.uid());
      create policy fixture_admission on public.fixture_private_rows as restrictive
        for select to authenticated using ((select private.account_access_allowed()));`);
    try {
      assert.equal(await run(asUser(claims(), 'select count(*) from public.fixture_private_rows')), '1');
      await totp();
      assert.equal(await run(asUser(claims(), 'select count(*) from public.fixture_private_rows')), '0');
      await sessionAal2();
      assert.equal(await run(asUser(claims({ aal: 'aal2' }), 'select count(*) from public.fixture_private_rows')), '1');
    } finally { await db.query('drop table public.fixture_private_rows;'); }
  });
  await fresh('reserved lifecycle states are projection-only compatibility, not implemented deletion', async () => {
    const definition = await db.query("select pg_get_functiondef('private.current_account_access()'::regprocedure);");
    try {
      for (const value of [
        expected({ account_state: 'pending_deletion', next_step: 'account_recovery',
          reason: 'account_restricted', restore_until: '2030-01-01T00:00:00+00:00' }),
        expected({ account_state: 'finalization_due', reason: 'finalization_due' }),
        expected({ account_state: 'blocked', reason: 'lifecycle_not_ready' }),
      ]) {
        // Stub only the canonical branch to test the stable projections. No
        // lifecycle persistence/transitions are introduced by the migration.
        await db.query(`create or replace function private.current_account_access() returns jsonb
          language sql stable security definer set search_path='' as $$
          select ${literal(JSON.stringify({ ...value, provisioning_allowed: false }))}::jsonb; $$;`);
        await check(value);
        await error(asUser(claims(), ensureSql()), 'PT403', 'account_restricted');
      }
    } finally { await db.query(definition); }
    await check(eligible);
  });

  await fresh('a continuing connection sees committed enrollment, role change and session revocation', async () => {
    const reader = await cluster.connect();
    try {
      await reader.query(`begin; ${context(claims())}`);
      assert.deepEqual(JSON.parse(await reader.query(statusSql)), eligible);
      await totp();
      assert.equal(JSON.parse(await reader.query(statusSql)).next_step, 'challenge_totp');
      await sessionAal2();
      assert.equal(JSON.parse(await reader.query(statusSql)).next_step, 'challenge_totp');
      await reader.query(`set local request.jwt.claims=${literal(JSON.stringify(claims({ aal: 'aal2' })))};`);
      assert.deepEqual(JSON.parse(await reader.query(statusSql)), eligible);
      await setRole('Owner');
      await db.query(`delete from auth.mfa_factors where id='${factor}';`);
      assert.equal(JSON.parse(await reader.query(statusSql)).next_step, 'enroll_totp');
      await db.query(`delete from auth.sessions where id='${sid}';`);
      await assert.rejects(reader.query(statusSql), { code: 'PT401' });
    } finally { await reader.close(); }
  });
  for (const finish of ['commit', 'rollback']) {
    await fresh(`concurrent provisioning serializes duplicate inserts after first ${finish}`, async () => {
      await db.query(`delete from public.profiles where id='${user}';`);
      const first = await cluster.connect(), second = await cluster.connect();
      try {
        await first.query(`begin; ${context(claims())}`);
        await first.query(ensureSql('First'));
        await second.query(`begin; ${context(claims())}`);
        const pending = second.query(ensureSql('Second'));
        await blocked(db, second, first);
        await first.query(finish);
        assert.equal(await pending, '');
        await second.query('commit');
        const row = JSON.parse(await stored());
        assert.equal(row.full_name, finish === 'commit' ? 'First' : 'Second');
        assert.equal(row.roles, 'User'); assert.equal(row.loyalty_policy_version, null);
      } finally { await first.close(); await second.close(); }
    });
  }
  for (const change of ['ban', 'delete']) {
    await fresh(`provisioning rechecks Auth ${change} after a real lock wait`, async () => {
      await db.query(`delete from public.profiles where id='${user}';`);
      const first = await cluster.connect(), second = await cluster.connect();
      try {
        await first.query(`begin; ${change === 'ban'
          ? `update auth.users set banned_until=now()+interval '1 day' where id='${user}'`
          : `delete from auth.users where id='${user}'`};`);
        await second.query(`begin; ${context(claims())}`);
        const pending = assert.rejects(second.query(ensureSql()), { code: change === 'ban' ? 'PT403' : 'PT401' });
        await blocked(db, second, first);
        await first.query('commit');
        await pending;
        assert.equal(await stored(), '');
      } finally { await first.close(); await second.close(); }
    });
  }
  await fresh('session revoked during duplicate-profile wait cannot return provisioning success', async () => {
    await db.query(`delete from public.profiles where id='${user}';`);
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; insert into public.profiles(id,full_name) values ('${user}','Concurrent signup');`);
      await second.query(`begin; ${context(claims())}`);
      const pending = assert.rejects(second.query(ensureSql('Stale callback')), { code: 'PT401' });
      await blocked(db, second, first);
      await db.query(`delete from auth.sessions where id='${sid}';`);
      await first.query('commit');
      await pending;
      assert.equal(JSON.parse(await stored()).full_name, 'Concurrent signup');
    } finally { await first.close(); await second.close(); }
  });
  await fresh('revocation during a delayed new insert rolls back that entire profile creation', async () => {
    await db.query(`delete from public.profiles where id='${user}';
      create function public.fixture_delay_profile() returns trigger language plpgsql as $$
      begin perform pg_advisory_xact_lock(41071,1); return new; end; $$;
      create trigger fixture_delay_profile before insert on public.profiles
      for each row execute function public.fixture_delay_profile();`);
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query('begin; select pg_advisory_xact_lock(41071,1);');
      await second.query(`begin; ${context(claims())}`);
      const pending = assert.rejects(second.query(ensureSql()), { code: 'PT401' });
      await blocked(db, second, first);
      await db.query(`delete from auth.sessions where id='${sid}';`);
      await first.query('commit');
      await pending;
      assert.equal(await stored(), '');
    } finally {
      await first.close(); await second.close();
      await db.query('drop trigger fixture_delay_profile on public.profiles; drop function public.fixture_delay_profile();');
    }
  });
  await fresh('bootstrap rechecks factor proof after the existing policy Auth-lock wait', async () => {
    await setRole('Owner'); await totp(); await sessionAal2();
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; update auth.users set raw_user_meta_data='{}' where id='${user}';`);
      await second.query(`begin; ${context(claims({ aal: 'aal2' }))}`);
      const pending = second.query(statusSql);
      await blocked(db, second, first);
      await db.query(`delete from auth.mfa_factors where id='${factor}';`);
      await first.query('commit');
      assert.deepEqual(JSON.parse(await pending), expected({ next_step: 'enroll_totp' }));
      await second.query('commit');
    } finally { await first.close(); await second.close(); }
  });
});
