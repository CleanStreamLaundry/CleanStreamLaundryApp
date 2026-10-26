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
]) prerequisites.push(await read(path));
const migration = await read('../supabase/migrations/20260930013417_enforce_profile_terms_admission.sql');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11), otherSid = uid(12), factor = uid(21);
const literal = (v) => v === null ? 'null' : `'${v.replaceAll("'", "''")}'`;
const claims = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (jwt, role = 'authenticated') =>
  `set local request.jwt.claims=${literal(JSON.stringify(jwt))};
   set local request.jwt.claim.sub=''; set local role ${role};`;
const asUser = (jwt, sql, role) => `begin; ${context(jwt, role)} ${sql}; commit;`;
const statusSql = 'select public.get_loyalty_policy_status()';
const admissionSql = 'select public.get_admission_status()';
const descriptorSql = 'select public.get_loyalty_policy_descriptor()';
const profileSql = 'select count(*) from public.profiles';
const updateSql = `with changed as (update public.profiles set full_name='Customer edit'
  where id='${user}' returning id) select count(*) from changed`;
const restricted = (extra = {}) => ({ subject_id: user, account_access: 'restricted',
  next_step: 'blocked', reason: null, account_state: 'legacy_active', restore_until: null, ...extra });

test('profile and terms enforcement on final replacement functions in disposable PostgreSQL 17',
  { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const run = async (sql) => {
    const session = await cluster.connect();
    try { return await session.query(sql); } finally { await session.close(); }
  };
  const call = async (sql, jwt = claims(), role) => JSON.parse(await run(asUser(jwt, sql, role)));
  const checkError = (code, message) => (error) => {
    assert.equal(error.code, code, error.message);
    if (message) assert.match(error.message, new RegExp(`ERROR:  ${code}: ${message}(?:\\n|$)`));
    assert(!error.message.includes('SYNTHETIC_SECRET_ERROR'), 'Internal failure leaked');
    return true;
  };
  const error = (sql, code, message) => assert.rejects(run(sql), checkError(code, message));
  const reset = () => db.query(`truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${other}',now());
    insert into auth.sessions(id,user_id,aal) values ('${sid}','${user}','aal1'),('${otherSid}','${other}','aal1');`);
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });
  const stored = async (id = user) => JSON.parse(await db.query(`select to_jsonb(p) from public.profiles p where id='${id}';`) || 'null');
  const setRole = (role) => db.query(`update public.profiles set roles=${literal(role)} where id='${user}';`);
  const totp = (type = 'totp', status = 'verified', owner = user) => db.query(`
    insert into auth.mfa_factors(id,user_id,factor_type,status) values
    ('${factor}','${owner}',${literal(type)},${literal(status)});`);
  const elevate = () => db.query(`update auth.sessions set aal='aal2',factor_id='${factor}' where id='${sid}';`);
  const definitions = () => db.query(`select jsonb_object_agg(n.nspname||'.'||p.proname,pg_get_functiondef(p.oid))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','private','auth') and p.prokind='f';`);
  const privileges = () => db.query(`select jsonb_build_object(
    'columns',(select jsonb_agg(to_jsonb(g) order by table_schema,table_name,column_name,grantee,privilege_type)
      from information_schema.column_privileges g where table_schema in ('public','private','auth')),
    'routines',(select jsonb_agg(jsonb_build_array(p.oid,p.proowner,p.proacl) order by p.oid)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth')),
    'schemas',(select jsonb_agg(jsonb_build_array(n.nspname,n.nspacl) order by n.nspname)
      from pg_namespace n where n.nspname in ('public','private','auth')));`);
  for (const sql of prerequisites) await db.query(sql);
  await reset();
  const beforeDefinitions = JSON.parse(await definitions()), beforePrivileges = await privileges();
  const beforePolicies = await db.query(`select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p;`);
  const beforeRow = await stored();
  await db.query(migration);
  const descriptor = await call(descriptorSql, {}, 'anon');
  const version = descriptor.required_version;
  const acceptSql = (v = version) => `select public.accept_loyalty_policy(${literal(v)})`;

  await t.test('only three existing bodies and two restrictive policies change; effective ACLs remain', async () => {
    const after = JSON.parse(await definitions());
    assert.deepEqual(Object.keys(after).sort(), Object.keys(beforeDefinitions).sort());
    assert.deepEqual(Object.keys(after).filter((name) => after[name] !== beforeDefinitions[name]).sort(),
      ['public.accept_loyalty_policy', 'public.get_admission_status', 'public.get_loyalty_policy_status']);
    assert.equal(await privileges(), beforePrivileges);
    assert.deepEqual(await stored(), beforeRow);
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
      where policyname not in ('profiles_account_admission','profiles_server_provisioning_only');`), beforePolicies);
    const policies = JSON.parse(await db.query(`select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
      where policyname in ('profiles_account_admission','profiles_server_provisioning_only');`));
    assert.equal(policies.length, 2);
    for (const policy of policies) {
      assert.equal(policy.permissive, 'RESTRICTIVE');
      assert.deepEqual(policy.roles, ['authenticated']);
    }
    assert.equal(policies[0].cmd, 'ALL');
    assert.match(policies[0].qual, /account_access_allowed/);
    assert.match(policies[0].with_check, /account_access_allowed/);
    assert.equal(policies[1].cmd, 'INSERT');
    assert.equal(policies[1].with_check, 'false');
  });
  await t.test('real owners bypass profile recursion; clients lack Auth/secret reads and private evaluator execution', async () => {
    assert.equal(await db.query(`select bool_and(p.prosecdef and p.proconfig=array['search_path=""']
      and (r.rolsuper or r.rolbypassrls)) from pg_proc p join pg_roles r on r.oid=p.proowner
      where p.oid in ('private.current_account_access()'::regprocedure,'private.account_access_allowed()'::regprocedure,
        'public.get_admission_status()'::regprocedure,'public.get_loyalty_policy_status()'::regprocedure,
        'public.accept_loyalty_policy(text)'::regprocedure);`), 't');
    assert.equal(await db.query(`select bool_and(not rolbypassrls and not rolsuper)
      from pg_roles where rolname in ('anon','authenticated');`), 't');
    assert.equal(await db.query(`select bool_and(not has_table_privilege(r.role,'auth.'||t.name,'SELECT'))
      from (values ('anon'),('authenticated')) r(role)
      cross join (values ('users'),('sessions'),('mfa_factors')) t(name);`), 't');
    assert.equal(await db.query(`select has_schema_privilege('authenticated','private','USAGE')
      and not has_schema_privilege('authenticated','private','CREATE')
      and not has_function_privilege('authenticated','private.current_account_access()','EXECUTE')
      and has_function_privilege('authenticated','private.account_access_allowed()','EXECUTE')
      and to_regprocedure('public.current_account_access()') is null;`), 't');
    assert.equal(await run(asUser(claims(), profileSql)), '1');
    for (const role of ['anon', 'service_role', 'supabase_auth_admin']) {
      for (const sql of [statusSql, acceptSql(), admissionSql]) await error(asUser({}, sql, role), '42501');
    }
    await error(asUser(claims(), 'select private.current_account_access()'), '42501');
    await error(asUser(claims(), `select public.accept_loyalty_policy('${version}','${other}')`), '42883');
  });
  await fresh('public descriptor is unchanged and independent of users, sessions, profiles and MFA', async () => {
    await db.query('truncate auth.users cascade;');
    assert.deepEqual(await call(descriptorSql, {}, 'anon'), descriptor);
    assert.deepEqual(Object.keys(descriptor).sort(), ['policy_sha256', 'policy_text', 'required_version']);
    assert.equal(await db.query('select count(*) from public.profiles;'), '0');
  });

  for (const role of ['User', 'Admin', 'Owner']) for (const enrollment of ['none', 'unverified', 'verified']) {
    for (const aal of ['aal1', 'aal2']) await fresh(`${role}/${enrollment}/${aal}: final RLS and terms share admission`, async () => {
      await setRole(role);
      if (enrollment !== 'none') await totp('totp', enrollment);
      if (aal === 'aal2') await elevate();
      const jwt = claims({ aal });
      const eligible = enrollment === 'verified' ? aal === 'aal2' : role === 'User';
      assert.equal(await run(asUser(jwt, profileSql)), eligible ? (role === 'User' ? '1' : '2') : '0');
      assert.equal(await run(asUser(jwt, updateSql)), eligible ? '1' : '0');
      const access = await call(admissionSql, jwt);
      assert.equal(access.account_access, eligible ? 'eligible' : 'restricted');
      if (eligible) {
        assert.equal((await call(statusSql, jwt)).acceptance_required, true);
        assert.equal((await call(acceptSql(), jwt)).acceptance_required, false);
        assert.equal((await call(admissionSql, jwt)).next_step, 'home');
      } else {
        for (const sql of [statusSql, acceptSql()]) await error(asUser(jwt, sql), 'PT403', 'account_restricted');
        assert.equal((await stored()).loyalty_policy_accepted_at, null);
      }
    });
  }
  for (const type of ['phone', 'webauthn', 'recovery_code']) await fresh(`${type} stays unsupported at AAL2`, async () => {
    await totp(type); await elevate();
    assert.equal(await run(asUser(claims({ aal: 'aal2' }), profileSql)), '0');
    await error(asUser(claims({ aal: 'aal2' }), acceptSql()), 'PT403', 'account_restricted');
    assert.equal((await call(admissionSql, claims({ aal: 'aal2' }))).reason, 'unsupported_factor');
  });
  await fresh('an old AAL1 JWT is not promoted by a now-AAL2 session', async () => {
    await totp(); await elevate();
    assert.equal(await run(asUser(claims(), profileSql)), '0');
    await error(asUser(claims(), statusSql), 'PT403', 'account_restricted');
    assert.equal((await call(admissionSql)).next_step, 'challenge_totp');
  });
  await fresh('factor_id must bind to this user despite absent factor FK', async () => {
    await totp('totp', 'verified', other); await elevate(); await setRole('Owner');
    assert.equal(await run(asUser(claims({ aal: 'aal2' }), profileSql)), '0');
    await error(asUser(claims({ aal: 'aal2' }), acceptSql()), 'PT403');
  });
  for (const [name, extra] of [
    ['expired', { exp: 0 }], ['missing expiry', { exp: null }], ['text expiry', { exp: '99999999999' }],
    ['missing session', { session_id: null }], ['malformed session', { session_id: 'bad' }],
    ['other session', { session_id: otherSid }], ['missing sub', { sub: null }],
    ['bad role', { role: 'service_role' }], ['unsupported aal', { aal: 'aal3' }],
  ]) await fresh(`${name} fails closed on direct profile and RPC paths`, async () => {
    for (const sql of [profileSql, updateSql, statusSql, acceptSql(), admissionSql]) {
      await error(asUser(claims(extra), sql), 'PT401', 'session_invalid');
    }
  });
  for (const [name, sql, code] of [
    ['revoked session', `delete from auth.sessions where id='${sid}'`, 'PT401'],
    ['elapsed not_after', `update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`, 'PT401'],
    ['deleted user', `delete from auth.users where id='${user}'`, 'PT401'],
    ['banned', `update auth.users set banned_until=now()+interval '1 day' where id='${user}'`, 'PT403'],
    ['anonymous', `update auth.users set is_anonymous=true where id='${user}'`, 'PT403'],
    ['soft deleted', `update auth.users set deleted_at=now() where id='${user}'`, 'PT403'],
    ['unverified', `update auth.users set email_confirmed_at=null where id='${user}'`, 'PT403'],
    ['unknown role', `update public.profiles set roles=null where id='${user}'`, 'PT403'],
  ]) await fresh(`${name} is enforced by final RLS and terms`, async () => {
    await db.query(sql);
    for (const operation of [statusSql, acceptSql()]) await error(asUser(claims(), operation), code);
    if (code === 'PT401') await error(asUser(claims(), profileSql), code);
    else {
      assert.equal(await run(asUser(claims(), profileSql)), '0');
      assert.equal(await run(asUser(claims(), updateSql)), '0');
      assert.equal((await call(admissionSql)).account_access, 'restricted');
    }
  });
  await fresh('RLS retains own writes, global admin reads, and additional restrictive scope', async () => {
    assert.equal(await run(asUser(claims(), `with changed as (update public.profiles set full_name='Wrong'
      where id='${other}' returning id) select count(*) from changed`)), '0');
    await setRole('Admin'); await totp(); await elevate();
    const jwt = claims({ aal: 'aal2' });
    assert.equal(await run(asUser(jwt, profileSql)), '2');
    assert.equal(await run(asUser(jwt, `with changed as (update public.profiles set full_name='Wrong'
      where id='${other}' returning id) select count(*) from changed`)), '0');
    await db.query(`create policy fixture_extra_scope on public.profiles as restrictive for select
      to authenticated using (id=auth.uid());`);
    try { assert.equal(await run(asUser(jwt, profileSql)), '1'); }
    finally { await db.query('drop policy fixture_extra_scope on public.profiles;'); }
  });
  await fresh('invoker RPC inherits RLS and cannot bypass MFA or target another profile', async () => {
    await run(asUser(claims(), `select public.increment_user_refund_attempts('${user}');
      select public.increment_user_refund_attempts('${other}')`));
    assert.equal((await stored()).refund_attempts, 1); assert.equal((await stored(other)).refund_attempts, 0);
    await totp();
    await run(asUser(claims(), `select public.increment_user_refund_attempts('${user}')`));
    assert.equal((await stored()).refund_attempts, 1);
  });
  await fresh('direct authenticated INSERT and legacy upsert are denied even for an eligible caller', async () => {
    for (const suffix of ['', 'on conflict(id) do nothing', "on conflict(id) do update set full_name='Override'"]) {
      await error(asUser(claims(), `insert into public.profiles(id,full_name) values ('${user}','Legacy') ${suffix}`), '42501');
    }
    await db.query(`delete from public.profiles where id='${user}';`);
    await error(asUser(claims(), `insert into public.profiles(id,full_name) values ('${user}','Legacy')`), '42501');
    assert.deepEqual(await call(admissionSql), restricted({ reason: 'profile_missing' }));
    await run(asUser(claims(), "select public.ensure_own_profile('Bootstrap')"));
    const row = await stored();
    assert.equal(row.full_name, 'Bootstrap'); assert.equal(row.roles, 'User');
    assert.equal(row.balance, 0); assert.equal(row.reward_tracker, 0); assert.equal(row.loyalty_policy_version, null);
    assert.equal((await call(admissionSql)).next_step, 'review_terms');
  });
  await fresh('unverified bootstrap is allowed but cannot overwrite or enter protected profiles/terms', async () => {
    await db.query(`update auth.users set email_confirmed_at=null where id='${user}';
      delete from public.profiles where id='${user}';`);
    await run(asUser(claims(), "select public.ensure_own_profile('New name')"));
    const before = await stored();
    await run(asUser(claims(), "select public.ensure_own_profile('Overwrite')"));
    assert.deepEqual(await stored(), before);
    assert.equal(await run(asUser(claims(), profileSql)), '0');
    await error(asUser(claims(), acceptSql()), 'PT403');
    assert.equal((await call(admissionSql)).next_step, 'verify_email');
  });
  await fresh('trusted signup, sync and cache writers remain independent of customer gates', async () => {
    await db.query(`insert into auth.users(id,raw_user_meta_data) values ('${uid(3)}',
      '{"full_name":"Signup","roles":"Owner","balance":999,"loyalty_policy_version":"forged"}');`);
    const created = await stored(uid(3));
    assert.equal(created.full_name, 'Signup'); assert.equal(created.roles, 'User');
    assert.equal(created.balance, 0); assert.equal(created.loyalty_policy_version, null);
    await setRole('Owner');
    await db.query(`update auth.users set banned_until=now()+interval '1 day' where id='${user}';`);
    await run(asUser(claims(), `select public.fixture_trusted_profile_sync('${user}','Synced');
      select public.fixture_trusted_cache_write('${user}',125);
      update public.profiles set reward_tracker=4 where id='${user}'`, 'service_role'));
    const row = await stored();
    assert.equal(row.full_name, 'Synced'); assert.equal(row.balance, 125); assert.equal(row.reward_tracker, 4);
    assert.equal(row.loyalty_policy_version, null);
    await error(asUser(claims(), `select public.fixture_trusted_cache_write('${user}',999)`), '42501');
    await error(asUser(claims(), "select public.ensure_own_profile('No bypass')"), 'PT403');
  });
  await fresh('protected grants and invoker guards survive accidental broad grants without admission bypass', async () => {
    for (const column of ['roles', 'balance', 'reward_tracker', 'loyalty_policy_version', 'loyalty_policy_accepted_at']) {
      assert.equal(await db.query(`select has_column_privilege('authenticated','public.profiles','${column}','UPDATE');`), 'f');
    }
    // Roll back grants with the probe: REVOKE table UPDATE also removes column grants.
    const broadContext = () => `begin; grant insert,update,delete on public.profiles to authenticated; ${context(claims())}`;
    for (const assignment of ["roles='Owner'", 'balance=100', 'reward_tracker=100',
      `loyalty_policy_version='${version}',loyalty_policy_accepted_at=now()`]) {
      await error(`${broadContext()} update public.profiles set ${assignment} where id='${user}'; rollback;`, '42501');
    }
    await totp();
    assert.equal(await run(`begin; grant insert,update,delete on public.profiles to authenticated;
      create policy fixture_delete on public.profiles for delete to authenticated using (id=auth.uid());
      ${context(claims())} ${profileSql};
      with removed as (delete from public.profiles returning id) select count(*) from removed; rollback;`), '0\n0');
    await error(`${broadContext()} insert into public.profiles(id,full_name) values
      ('${user}','No bypass') on conflict(id) do nothing; rollback;`, '42501');
  });
  await fresh('terms preserves six keys, explicit acceptance, version rejection and original timestamp', async () => {
    const initial = await call(statusSql);
    assert.deepEqual(initial, { ...descriptor, accepted_version: null, accepted_at: null, acceptance_required: true });
    for (const version of [null, '', 'stale']) await error(asUser(claims(), acceptSql(version)), '22023', 'policy_version_mismatch');
    const accepted = await call(acceptSql());
    assert.deepEqual(await call(acceptSql()), accepted);
    assert.deepEqual(await call(statusSql), accepted);
    assert.deepEqual(await call(admissionSql), restricted({ account_access: 'eligible', next_step: 'home' }));
    assert.equal((await stored()).loyalty_policy_accepted_at, accepted.accepted_at);
  });
  await fresh('lookup permission failure sanitizes profile, terms, and admission paths', async () => {
    await db.query(`grant usage,create on schema private to admission_lookup_fixture;
      alter function private.current_account_access() owner to admission_lookup_fixture;
      revoke create on schema private from admission_lookup_fixture;
      revoke select(id,user_id,aal,factor_id,not_after) on auth.sessions from admission_lookup_fixture;`);
    try {
      for (const sql of [profileSql, updateSql, statusSql, acceptSql(), admissionSql]) {
        await error(asUser(claims(), sql), 'PT503', 'admission_unavailable');
      }
    } finally {
      await db.query(`alter function private.current_account_access() owner to policy_fixture;
        revoke usage on schema private from admission_lookup_fixture;
        grant select(id,user_id,aal,factor_id,not_after) on auth.sessions to admission_lookup_fixture;`);
    }
  });
  for (const code of ['23514', '22023']) await fresh(`unexpected ${code} write error is sanitized and acceptance rolls back`, async () => {
    await db.query(`create function public.fixture_fail_write() returns trigger language plpgsql as $$
      begin raise exception 'SYNTHETIC_SECRET_ERROR' using errcode='${code}'; end; $$;
      create trigger fixture_fail_write before update on public.profiles for each row execute function public.fixture_fail_write();`);
    try {
      await error(asUser(claims(), acceptSql()), 'PT503', 'admission_unavailable');
      assert.equal((await stored()).loyalty_policy_accepted_at, null);
    } finally { await db.query('drop trigger fixture_fail_write on public.profiles; drop function public.fixture_fail_write();'); }
  });

  for (const finish of ['commit', 'rollback']) await fresh(`final acceptance serializes concurrent replay after ${finish}`, async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; ${context(claims())}`);
      const initial = JSON.parse(await first.query(acceptSql()));
      await second.query(`begin; ${context(claims())}`);
      const pending = second.query(acceptSql());
      await blocked(db, second, first);
      assert.equal((await call(statusSql)).accepted_at, null);
      await first.query(finish);
      const accepted = JSON.parse(await pending);
      await second.query('commit');
      if (finish === 'commit') assert.deepEqual(accepted, initial);
      else {
        assert.notEqual(accepted.accepted_at, initial.accepted_at);
        assert(Date.parse(accepted.accepted_at) >= Date.parse(initial.accepted_at));
      }
      assert.deepEqual(await call(statusSql), accepted);
    } finally { await first.close(); await second.close(); }
  });
  for (const operation of [statusSql, acceptSql(), admissionSql]) {
    for (const revoke of [false, true]) await fresh(`${operation}: Auth wait then ${revoke ? 'revocation' : 'factor removal'}`, async () => {
      await setRole('Owner'); await totp(); await elevate();
      const first = await cluster.connect(), second = await cluster.connect();
      try {
        await first.query(`begin; update auth.users set raw_user_meta_data='{}' where id='${user}';`);
        await second.query(`begin; ${context(claims({ aal: 'aal2' }))}`);
        const response = second.query(operation);
        const pending = revoke || operation !== admissionSql
          ? assert.rejects(response, checkError(revoke ? 'PT401' : 'PT403')) : response;
        await blocked(db, second, first);
        await db.query(revoke ? `delete from auth.sessions where id='${sid}';`
          : `delete from auth.mfa_factors where id='${factor}';`);
        await first.query('commit');
        const result = await pending;
        if (!revoke && operation === admissionSql) {
          assert.deepEqual(JSON.parse(result), restricted({ next_step: 'enroll_totp' }));
          await second.query('commit');
        }
        assert.equal((await stored()).loyalty_policy_accepted_at, null);
      } finally { await first.close(); await second.close(); }
    });
  }
  for (const change of ['revoke', 'remove factor', 'delete profile']) await fresh(`acceptance rechecks after profile lock: ${change}`, async () => {
    await setRole('Owner'); await totp(); await elevate();
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; ${change === 'delete profile' ? 'delete from' : 'select 1 from'} public.profiles
        where id='${user}' ${change === 'delete profile' ? '' : 'for no key update'};`);
      await second.query(`begin; ${context(claims({ aal: 'aal2' }))}`);
      const pending = assert.rejects(second.query(acceptSql()), checkError(change === 'revoke' ? 'PT401' : 'PT403'));
      await blocked(db, second, first);
      if (change !== 'delete profile') await db.query(change === 'revoke'
        ? `delete from auth.sessions where id='${sid}';` : `delete from auth.mfa_factors where id='${factor}';`);
      await first.query('commit'); await pending;
      assert.equal((await stored())?.loyalty_policy_accepted_at ?? null, null);
    } finally { await first.close(); await second.close(); }
  });
  await fresh('restriction during UPDATE trigger wait rolls back final acceptance', async () => {
    await setRole('Owner'); await totp(); await elevate();
    await db.query(`create function public.fixture_pause_write() returns trigger language plpgsql as $$
      begin perform pg_advisory_xact_lock(812340); return new; end; $$;
      create trigger fixture_pause_write before update on public.profiles for each row execute function public.fixture_pause_write();`);
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query('begin; select pg_advisory_xact_lock(812340);');
      await second.query(`begin; ${context(claims({ aal: 'aal2' }))}`);
      const pending = assert.rejects(second.query(acceptSql()), checkError('PT403', 'account_restricted'));
      await blocked(db, second, first);
      await db.query(`delete from auth.mfa_factors where id='${factor}';`);
      await first.query('commit'); await pending;
      assert.equal((await stored()).loyalty_policy_accepted_at, null);
    } finally {
      await first.close(); await second.close();
      await db.query('drop trigger fixture_pause_write on public.profiles; drop function public.fixture_pause_write();');
    }
  });
  await fresh('role elevation committed during profile wait applies staff MFA before acceptance', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; update public.profiles set roles='Owner' where id='${user}';`);
      await second.query(`begin; ${context(claims())}`);
      const pending = assert.rejects(second.query(acceptSql()), checkError('PT403', 'account_restricted'));
      await blocked(db, second, first);
      await first.query('commit'); await pending;
      assert.equal((await stored()).loyalty_policy_accepted_at, null);
      assert.deepEqual(await call(admissionSql), restricted({ next_step: 'enroll_totp' }));
    } finally { await first.close(); await second.close(); }
  });
  await fresh('committed ban after Auth lock wait returns restricted six-key wire', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; update auth.users set banned_until=now()+interval '1 day' where id='${user}';`);
      await second.query(`begin; ${context(claims())}`);
      const pending = second.query(admissionSql);
      await blocked(db, second, first);
      await first.query('commit');
      assert.deepEqual(JSON.parse(await pending), restricted({ reason: 'account_restricted', account_state: 'blocked' }));
      await second.query('commit');
    } finally { await first.close(); await second.close(); }
  });
  await fresh('acceptance retains Auth share lock until transaction finishes', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; ${context(claims())}`); await first.query(acceptSql());
      const pending = second.query(`update auth.users set banned_until=now()+interval '1 day' where id='${user}';`);
      await blocked(db, second, first);
      await first.query('commit'); await pending;
      await error(asUser(claims(), acceptSql()), 'PT403');
      assert.notEqual((await stored()).loyalty_policy_accepted_at, null);
    } finally { await first.close(); await second.close(); }
  });
  for (const guard of ['profiles_protected_fields_guard', 'profiles_policy_acceptance_guard']) {
    await fresh(`disabled ${guard} fails migration preflight without altering accepted state`, async () => {
      const before = await definitions();
      await db.query(`alter table public.profiles disable trigger ${guard};`);
      try { await error(migration, '55000', 'Reviewed profile, policy and admission prerequisites required'); }
      finally { await db.query(`alter table public.profiles enable trigger ${guard};`); }
      assert.equal(await definitions(), before);
    });
  }
  await t.test('canonical evaluator/bootstrap/descriptor and all prerequisite ACLs remain unchanged at completion', async () => {
    const final = JSON.parse(await definitions());
    for (const name of ['private.current_account_access', 'private.account_access_allowed',
      'public.ensure_own_profile', 'public.get_loyalty_policy_descriptor']) {
      assert.equal(final[name], beforeDefinitions[name]);
    }
    assert.equal(await privileges(), beforePrivileges);
  });
});
