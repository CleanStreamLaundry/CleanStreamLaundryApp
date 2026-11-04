import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const pgBin = process.env.PG_BIN;
const guardPath = process.env.POLICY_TEST_PROFILE_GUARD;
const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const migration = await read('../supabase/migrations/20260929234955_loyalty_policy_acceptance.sql');
const fixture = await read('../supabase/tests/loyalty_policy_acceptance.fixture.sql');
assert(guardPath && isAbsolute(guardPath), 'Set POLICY_TEST_PROFILE_GUARD to the reviewed authority migration');
const authorityGuard = await readFile(guardPath, 'utf8');
assert.match(authorityGuard, /create function public\.guard_profile_protected_fields\(\)/);
// The SQL descriptor is authoritative; clients render it rather than static copy.
const [, version, sha256, policyText] = migration.match(
  /required_version constant text := '(review-only-loyalty-[a-f0-9]{16})';\s+policy_sha256 constant text := '([a-f0-9]{64})';\s+policy_text constant text := \$policy\$([\s\S]*?)\$policy\$;/,
) ?? [];
assert.ok(policyText, 'Expected the versioned review-only SQL descriptor');
assert.equal(version, `review-only-loyalty-${sha256.slice(0, 16)}`);
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2);
const literal = (value) => value === null ? 'null' : `'${value.replaceAll("'", "''")}'`;
const statusSql = 'select public.get_loyalty_policy_status()';
const descriptorSql = 'select public.get_loyalty_policy_descriptor()';
const descriptor = { required_version: version, policy_text: policyText, policy_sha256: sha256 };
const acceptSql = (v = version) => `select public.accept_loyalty_policy(${literal(v)})`;

const asUser = (id, sql, role = 'authenticated') => `begin;
  set local request.jwt.claim.sub=${literal(id || '')}; set local role ${role};
  ${sql}; commit;`;

const existingPrivileges = `select jsonb_agg(to_jsonb(g) order by grantee,column_name,privilege) from (
  select r.grantee,a.attname as column_name,p.privilege,
    has_column_privilege(r.grantee,'public.profiles',a.attname,p.privilege) as allowed
  from (values ('anon'),('authenticated'),('service_role'),('supabase_auth_admin')) r(grantee)
  cross join (values ('SELECT'),('INSERT'),('UPDATE')) p(privilege)
  join pg_attribute a on a.attrelid='public.profiles'::regclass and a.attnum>0 and not a.attisdropped
  where a.attname not in ('loyalty_policy_version','loyalty_policy_accepted_at')
) g;`;

test('review-only policy acceptance on disposable PostgreSQL 17', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, pgBin);
  const db = await cluster.connect();
  const run = async (sql) => {
    const session = await cluster.connect();
    try { return await session.query(sql); } finally { await session.close(); }
  };
  const call = async (id, sql = statusSql, role) => JSON.parse(await run(asUser(id, sql, role)));
  const error = async (sql, code, message) => assert.rejects(run(sql), (e) => {
    assert.equal(e.code, code, e.message);
    if (message) assert.match(e.message, new RegExp(message));
    return true;
  });
  const resetUsers = () => db.query(`truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at,raw_app_meta_data) values
    ('${user}',now(),'{"provider":"email"}'),('${other}',now(),'{"provider":"google"}');`);
  const fresh = (name, action) => t.test(name, async () => { await resetUsers(); await action(); });
  const beginUser = (s, id = user) => s.query(`begin; set local request.jwt.claim.sub='${id}'; set local role authenticated;`);
  const stored = async (id = user) => JSON.parse(await db.query(`select jsonb_build_object(
    'version',loyalty_policy_version,'at',loyalty_policy_accepted_at)
    from public.profiles where id='${id}';`));

  await db.query(fixture);
  await db.query(authorityGuard);
  await resetUsers();
  const beforePrivileges = await db.query(existingPrivileges);
  const beforeProfiles = await db.query('select jsonb_agg(to_jsonb(p) order by id) from public.profiles p;');
  await db.query(migration);

  await t.test('migration preserves existing rows/grants and never backfills consent', async () => {
    assert.equal(await db.query(existingPrivileges), beforePrivileges);
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(p)-'loyalty_policy_version'-'loyalty_policy_accepted_at'
      order by id) from public.profiles p;`), beforeProfiles);
    assert.equal(await db.query(`select count(*) from public.profiles where
      loyalty_policy_version is not null or loyalty_policy_accepted_at is not null;`), '0');
    assert.equal(await db.query(`select bool_and(not has_column_privilege(r.role,'public.profiles',c.col,p.priv))
      from (values ('anon'),('authenticated')) r(role)
      cross join (values ('loyalty_policy_version'),('loyalty_policy_accepted_at')) c(col)
      cross join (values ('INSERT'),('UPDATE')) p(priv);`), 't');
  });

  await t.test('RPC signatures/ACL/search paths and invoker trigger are explicit', async () => {
    const rows = JSON.parse(await db.query(`select jsonb_agg(to_jsonb(g) order by name) from (
      select p.proname as name,p.prosecdef as definer,p.proconfig as config,
        pg_get_function_arguments(p.oid) as args,pg_get_function_result(p.oid) as result,
        pg_get_userbyid(p.proowner) as owner
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
      and p.proname in ('get_loyalty_policy_descriptor','get_loyalty_policy_status',
        'accept_loyalty_policy','guard_profile_policy_acceptance')
    ) g;`));
    assert.equal(rows.length, 4);
    for (const row of rows) {
      assert.equal(row.owner, 'policy_fixture');
      assert.deepEqual(row.config, ['search_path=""']);
      assert.equal(row.definer, ['get_loyalty_policy_status','accept_loyalty_policy'].includes(row.name));
      assert.equal(row.args, row.name === 'accept_loyalty_policy' ? 'p_version text' : '');
      assert.equal(row.result, row.name === 'guard_profile_policy_acceptance' ? 'trigger' : 'jsonb');
    }
    assert.equal(await db.query(`select bool_and(not has_function_privilege(r.role,f.fn,'EXECUTE'))
      from (values ('anon'),('service_role'),('supabase_auth_admin')) r(role)
      cross join (values ('public.get_loyalty_policy_status()'),('public.accept_loyalty_policy(text)'),
        ('public.guard_profile_policy_acceptance()')) f(fn);`), 't');
    assert.equal(await db.query(`select has_function_privilege('authenticated','public.get_loyalty_policy_status()','EXECUTE')
      and has_function_privilege('authenticated','public.accept_loyalty_policy(text)','EXECUTE')
      and not has_function_privilege('authenticated','public.guard_profile_policy_acceptance()','EXECUTE');`), 't');
    assert.equal(await db.query(`select has_function_privilege('anon','public.get_loyalty_policy_descriptor()','EXECUTE')
      and has_function_privilege('authenticated','public.get_loyalty_policy_descriptor()','EXECUTE')
      and not has_function_privilege('policy_no_access','public.get_loyalty_policy_descriptor()','EXECUTE')
      and not has_function_privilege('service_role','public.get_loyalty_policy_descriptor()','EXECUTE')
      and not has_function_privilege('supabase_auth_admin','public.get_loyalty_policy_descriptor()','EXECUTE');`), 't');
  });

  await fresh('public descriptor has exactly three unchanged keys without a user or profile', async () => {
    await db.query('truncate auth.users cascade;');
    for (const role of ['anon', 'authenticated']) {
      for (const id of ['', uid(999), 'not-a-uuid']) {
        assert.deepEqual(await call(id, descriptorSql, role), descriptor);
      }
    }
    assert.equal(createHash('sha256').update(descriptor.policy_text, 'utf8').digest('hex'), sha256);
    assert.equal(await db.query('select count(*) from public.profiles;'), '0');
  });
  await fresh('restricted identities may read public text but not private status or acceptance', async () => {
    for (const setup of [
      `update auth.users set email_confirmed_at=null where id='${user}'`,
      `update auth.users set email_confirmed_at=now(),is_anonymous=true where id='${user}'`,
      `update auth.users set is_anonymous=false,banned_until=now()+interval '1 day' where id='${user}'`,
      `update auth.users set banned_until=null,deleted_at=now() where id='${user}'`,
    ]) {
      await db.query(setup);
      assert.deepEqual(await call(user, descriptorSql), descriptor);
      for (const sql of [statusSql, acceptSql()]) await error(asUser(user, sql), '42501');
      assert.deepEqual(await stored(), { version: null, at: null });
    }
  });
  await fresh('public descriptor neither reads nor locks Auth or profile tables', async () => {
    const holder = await cluster.connect();
    try {
      await holder.query('begin; lock table auth.users,public.profiles in access exclusive mode;');
      const result = await run(asUser('', `set local statement_timeout='500ms'; ${descriptorSql}`, 'anon'));
      assert.deepEqual(JSON.parse(result), descriptor);
    } finally { await holder.close(); }
  });
  await fresh('public descriptor works read-only and cannot create or modify acceptance', async () => {
    const before = await db.query('select jsonb_agg(to_jsonb(p) order by id) from public.profiles p;');
    const result = await run(asUser('', descriptorSql, 'anon').replace('begin;', 'begin read only;'));
    assert.deepEqual(JSON.parse(result), descriptor);
    assert.equal(await db.query('select jsonb_agg(to_jsonb(p) order by id) from public.profiles p;'), before);
    await error(asUser('', "select public.get_loyalty_policy_descriptor('forged')", 'anon'), '42883');
    await error(asUser('', descriptorSql, 'policy_no_access'), '42501');
    await error(asUser(user, `create or replace function public.get_loyalty_policy_descriptor()
      returns jsonb language sql as $$ select '{}'::jsonb $$`), '42501');
  });
  await fresh('protected status and acceptance each call the public source exactly once', async () => {
    const definition = await db.query("select pg_get_functiondef(to_regprocedure('public.get_loyalty_policy_descriptor()'));");
    assert.match(definition, /CREATE OR REPLACE FUNCTION/);
    await db.query(`create sequence public.fixture_descriptor_calls;
      create or replace function public.get_loyalty_policy_descriptor() returns jsonb
      language plpgsql volatile security invoker set search_path='' as $$
      begin
        perform nextval('public.fixture_descriptor_calls');
        return ${literal(JSON.stringify(descriptor))}::jsonb;
      end; $$;`);
    try {
      const status = await call(user);
      assert.deepEqual(Object.fromEntries(Object.keys(descriptor).map((key) => [key, status[key]])), descriptor);
      assert.equal(await db.query('select last_value from public.fixture_descriptor_calls;'), '1');
      await call(user, acceptSql());
      assert.equal(await db.query('select last_value from public.fixture_descriptor_calls;'), '2');
    } finally {
      await db.query(definition);
      await db.query('drop sequence public.fixture_descriptor_calls;');
    }
  });

  await fresh('wire descriptor binds the exact server draft, without acceptance on read', async () => {
    const result = await call(user);
    assert.deepEqual(Object.keys(result).sort(), ['required_version','policy_text','policy_sha256',
      'accepted_version','accepted_at','acceptance_required'].sort());
    assert.equal(result.required_version, version);
    assert.equal(result.policy_text, policyText);
    assert.equal(result.policy_sha256, sha256);
    assert.equal(createHash('sha256').update(policyText, 'utf8').digest('hex'), sha256);
    assert.equal(result.acceptance_required, true);
    assert.equal(result.accepted_version, null);
    assert.equal(result.accepted_at, null);
    assert.deepEqual(await stored(), { version: null, at: null });
  });

  for (const providerUser of [user, other]) {
    await fresh(`verified ${providerUser === user ? 'password' : 'social'} user explicitly accepts with server time`, async () => {
      const before = await db.query('select clock_timestamp();');
      const result = await call(providerUser, acceptSql());
      const after = await db.query('select clock_timestamp();');
      assert.equal(result.accepted_version, version);
      assert.equal(result.acceptance_required, false);
      assert.equal(await db.query(`select ${literal(result.accepted_at)}::timestamptz
        between ${literal(before)}::timestamptz and ${literal(after)}::timestamptz;`), 't');
      assert.deepEqual(await stored(providerUser), { version, at: result.accepted_at });
      assert.deepEqual(await stored(providerUser === user ? other : user), { version: null, at: null });
    });
  }

  for (const [name, id, setup] of [
    ['missing subject', '', ''],
    ['unverified email', uid(3), `insert into auth.users(id) values ('${uid(3)}');`],
    ['anonymous Auth user', uid(3), `insert into auth.users(id,email_confirmed_at,is_anonymous) values ('${uid(3)}',now(),true);`],
    ['missing/deleted Auth user with stale subject', uid(999), ''],
    ['soft-deleted Auth user', user, `update auth.users set deleted_at=now() where id='${user}';`],
    ['banned Auth user', user, `update auth.users set banned_until=now()+interval '1 day' where id='${user}';`],
    ['forged confirmation/consent in editable metadata', user, `update auth.users set email_confirmed_at=null,
      raw_user_meta_data='{"email_verified":true,"is_anonymous":false,"loyalty_policy_version":"${version}"}' where id='${user}';`],
  ]) {
    await fresh(`both RPCs reject ${name}`, async () => {
      if (setup) await db.query(setup);
      for (const sql of [statusSql, acceptSql()]) await error(asUser(id, sql), '42501');
      assert.equal(await db.query('select count(*) from public.profiles where loyalty_policy_version is not null;'), '0');
    });
  }

  await fresh('anonymous database role cannot execute either RPC even with a subject', async () => {
    for (const sql of [statusSql, acceptSql()]) await error(asUser(user, sql, 'anon'), '42501');
  });
  await fresh('missing profile is an error, never an implicit accepted account', async () => {
    await db.query(`delete from public.profiles where id='${user}';`);
    for (const sql of [statusSql, acceptSql()]) await error(asUser(user, sql), 'P0002', 'profile_not_found');
    assert.equal(await db.query(`select count(*) from public.profiles where id='${user}';`), '0');
  });
  await fresh('null/empty/unknown/stale versions cannot create or downgrade acceptance', async () => {
    for (const v of [null, '', 'unknown', `${version}-stale`]) {
      await error(asUser(user, acceptSql(v)), '22023', 'policy_version_mismatch');
    }
    const accepted = await call(user, acceptSql());
    await error(asUser(user, acceptSql('older')), '22023');
    assert.deepEqual(await call(user), accepted);
    await error(asUser(user, `select public.accept_loyalty_policy('${version}','2000-01-01')`), '42883');
  });
  await fresh('replay preserves the first timestamp exactly', async () => {
    const accepted = await call(user, acceptSql());
    await delay(25);
    assert.deepEqual(await call(user, acceptSql()), accepted);
    assert.deepEqual(await call(user), accepted);
  });

  await fresh('profile creation/name edits/read-only selects and signup metadata stay compatible', async () => {
    await db.query(`delete from public.profiles where id='${user}';`);
    await run(asUser(user, `insert into public.profiles(id,full_name) values ('${user}','Customer')
      on conflict(id) do nothing; update public.profiles set full_name='Edited' where id='${user}'`));
    const row = await call(user, `select to_jsonb(p) from public.profiles p where id='${user}'`);
    assert.equal(row.full_name, 'Edited');
    assert.equal(row.loyalty_policy_version, null);
    assert.equal(row.loyalty_policy_accepted_at, null);
    assert.equal(row.roles, 'User');
    assert.equal(row.balance, 0);
    assert.equal(row.reward_tracker, 0);
    assert.equal(await run(asUser(user, `select count(*) from public.profiles where id='${other}'`)), '0');
    await db.query(`insert into auth.users(id,email_confirmed_at,raw_user_meta_data) values
      ('${uid(3)}',now(),'{"full_name":"Signup","loyalty_policy_version":"${version}","loyalty_policy_accepted_at":"2000-01-01"}');`);
    assert.deepEqual(await stored(uid(3)), { version: null, at: null });
  });
  await fresh('direct column writes and cross-user profile insertion are denied', async () => {
    await error(asUser(user, `update public.profiles set loyalty_policy_version='${version}',
      loyalty_policy_accepted_at='2000-01-01' where id='${user}'`), '42501');
    await error(asUser(user, `insert into public.profiles(id,loyalty_policy_version,loyalty_policy_accepted_at)
      values ('${user}','${version}',now()) on conflict(id) do nothing`), '42501');
    await db.query(`delete from public.profiles where id='${other}';`);
    await error(asUser(user, `insert into public.profiles(id,full_name) values ('${other}','Wrong owner')`), '42501');
    assert.deepEqual(await stored(), { version: null, at: null });
  });
  await fresh('invoker guard survives accidental PUBLIC/table grants: insert/upsert/backdate/clear', async () => {
    const accepted = await call(user, acceptSql());
    await db.query('grant insert,update on public.profiles to public,anon,authenticated;');
    try {
      for (const sql of [
        `update public.profiles set loyalty_policy_accepted_at='2000-01-01' where id='${user}'`,
        `update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null where id='${user}'`,
        `update public.profiles set loyalty_policy_version='forged' where id='${user}'`,
        `insert into public.profiles(id,loyalty_policy_version,loyalty_policy_accepted_at)
          values ('${user}','${version}',now()) on conflict(id) do update set full_name='Upsert'`,
      ]) await error(asUser(user, sql), '42501', 'Policy acceptance requires the server RPC');
      await run(asUser(user, `update public.profiles set full_name='Still editable' where id='${user}'`));
      assert.deepEqual(await call(user), accepted);
      await db.query(`delete from public.profiles where id='${other}';`);
      for (const role of ['authenticated', 'anon']) await error(asUser(other,
        `insert into public.profiles(id,loyalty_policy_version,loyalty_policy_accepted_at)
          values ('${other}','${version}','2000-01-01')`, role), '42501', 'Policy acceptance requires the server RPC');
    } finally { await db.query('revoke insert,update on public.profiles from public,anon,authenticated;'); }
  });
  await fresh('trusted server executor is not confused with its authenticated JWT subject', async () => {
    await run(asUser(user, `update public.profiles set balance=125,full_name='Server'
      where id='${user}'`, 'service_role'));
    assert.equal(await db.query(`select balance from public.profiles where id='${user}';`), '125');
    assert.equal((await call(user, acceptSql())).acceptance_required, false);
    await error(asUser(user, `update public.profiles set roles='Owner' where id='${user}'`), '42501');
  });
  await fresh('pair constraint rejects incomplete/empty/infinite acceptance', async () => {
    for (const assignment of ["loyalty_policy_version='only-version'", "loyalty_policy_accepted_at=now()",
      "loyalty_policy_version='',loyalty_policy_accepted_at=now()",
      "loyalty_policy_version='invalid',loyalty_policy_accepted_at='infinity'"]) {
      await error(`update public.profiles set ${assignment} where id='${user}';`, '23514');
    }
  });
  await fresh('failed profile write never returns accepted and transaction rolls back', async () => {
    await db.query(`create function public.fixture_fail_acceptance() returns trigger language plpgsql as $$
      begin raise exception 'synthetic database failure' using errcode='23514'; end; $$;
      create trigger fixture_fail_acceptance before update on public.profiles
      for each row execute function public.fixture_fail_acceptance();`);
    try {
      await error(asUser(user, acceptSql()), '23514');
      assert.deepEqual(await stored(), { version: null, at: null });
    } finally {
      await db.query('drop trigger fixture_fail_acceptance on public.profiles; drop function public.fixture_fail_acceptance();');
    }
  });

  for (const finish of ['commit', 'rollback']) {
    await fresh(`two real concurrent acceptances serialize after first ${finish}`, async () => {
      const first = await cluster.connect(), second = await cluster.connect();
      try {
        await beginUser(first);
        const initial = JSON.parse(await first.query(acceptSql()));
        await beginUser(second);
        const pending = second.query(acceptSql());
        await blocked(db, second, first);
        assert.equal((await call(user)).acceptance_required, true);
        await delay(25);
        await first.query(finish);
        const result = JSON.parse(await pending);
        await second.query('commit');
        assert.equal(result.acceptance_required, false);
        if (finish === 'commit') assert.deepEqual(result, initial);
        else assert(Date.parse(result.accepted_at) > Date.parse(initial.accepted_at));
        assert.deepEqual(await stored(), { version, at: result.accepted_at });
      } finally { await first.close(); await second.close(); }
    });
  }
  await fresh('different users can accept independently while the first transaction remains open', async () => {
    const first = await cluster.connect();
    try {
      await beginUser(first);
      await first.query(acceptSql());
      assert.equal((await call(other, acceptSql())).acceptance_required, false);
      await first.query('rollback');
      assert.deepEqual(await stored(), { version: null, at: null });
    } finally { await first.close(); }
  });
  await fresh('concurrent profile deletion fails closed after the profile lock wait', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; delete from public.profiles where id='${user}';`);
      await beginUser(second);
      const pending = assert.rejects(second.query(acceptSql()), { code: 'P0002' });
      await blocked(db, second, first);
      await first.query('commit');
      await pending;
    } finally { await first.close(); await second.close(); }
  });
  await fresh('concurrent Auth deletion is rechecked before acceptance after waiting', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await first.query(`begin; delete from auth.users where id='${user}';`);
      await beginUser(second);
      const pending = assert.rejects(second.query(acceptSql()), { code: '42501' });
      await blocked(db, second, first);
      await first.query('commit');
      await pending;
    } finally { await first.close(); await second.close(); }
  });
  await fresh('acceptance holds Auth eligibility stable until commit; deletion then completes', async () => {
    const first = await cluster.connect(), second = await cluster.connect();
    try {
      await beginUser(first);
      await first.query(acceptSql());
      const pending = second.query(`delete from auth.users where id='${user}';`);
      await blocked(db, second, first);
      await first.query('commit');
      await pending;
      await error(asUser(user, statusSql), '42501');
    } finally { await first.close(); await second.close(); }
  });
  await fresh('an explicitly designated next revision requires fresh consent, never auto-upgrades', async () => {
    const initial = await call(user, acceptSql());
    const definition = await db.query("select pg_get_functiondef(to_regprocedure('public.get_loyalty_policy_descriptor()'));");
    assert.match(definition, /CREATE OR REPLACE FUNCTION/);
    const nextText = `${policyText}\n\nSYNTHETIC TEST REVISION ONLY.`;
    const nextHash = createHash('sha256').update(nextText).digest('hex');
    const nextVersion = `review-only-test-${nextHash.slice(0, 16)}`;
    try {
      await db.query(definition.replaceAll(version, nextVersion).replace(sha256, nextHash).replace(policyText, nextText));
      const next = await call(user);
      assert.deepEqual(await call('', descriptorSql, 'anon'), {
        required_version: nextVersion, policy_text: nextText, policy_sha256: nextHash,
      });
      assert.equal(next.required_version, nextVersion);
      assert.equal(next.acceptance_required, true);
      assert.equal(next.accepted_at, initial.accepted_at);
      assert.equal(next.accepted_version, version);
      await error(asUser(user, acceptSql()), '22023');
      await delay(25);
      const accepted = await call(user, acceptSql(nextVersion));
      assert.equal(accepted.accepted_version, nextVersion);
      assert.equal(accepted.acceptance_required, false);
      assert(Date.parse(accepted.accepted_at) > Date.parse(initial.accepted_at));
    } finally { await db.query(definition); }
  });

  const resetSchema = async () => {
    await db.query('drop schema public cascade; drop schema auth cascade; create schema public;');
    await db.query(fixture.slice(fixture.indexOf('create schema auth;')));
    await resetUsers();
  };
  await t.test('reverse installation order preserves both independent profile guards', async () => {
    await resetSchema();
    const before = await db.query(existingPrivileges);
    await db.query(migration);
    assert.equal(await db.query(existingPrivileges), before);
    await db.query(authorityGuard);
    assert.equal((await call(user, acceptSql())).acceptance_required, false);
    await run(asUser(user, `update public.profiles set full_name='Works' where id='${user}'`));
    for (const sql of ["roles='Owner'", "balance=100", "reward_tracker=100", "loyalty_policy_accepted_at='2000-01-01'"]) {
      await error(asUser(user, `update public.profiles set ${sql} where id='${user}'`), '42501');
    }
  });
  await t.test('unreviewed inherited table privileges abort the entire migration', async () => {
    await resetSchema();
    await db.query(`create role fixture_inherited_writer;
      grant insert,update on public.profiles to fixture_inherited_writer;
      grant fixture_inherited_writer to authenticated;`);
    const before = await db.query(existingPrivileges);
    await error(migration, '42501', 'Inherited policy acceptance write privileges require review');
    assert.equal(await db.query(existingPrivileges), before);
    assert.equal(await db.query(`select count(*) from pg_attribute where attrelid='public.profiles'::regclass
      and attname like 'loyalty_policy_%' and not attisdropped;`), '0');
    assert.equal(await db.query("select to_regprocedure('public.get_loyalty_policy_status()') is null;"), 't');
  });
});
