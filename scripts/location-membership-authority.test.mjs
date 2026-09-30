import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const fixture = await read('../supabase/tests/location_membership_authority.fixture.sql');
const migration = await read('../supabase/migrations/20260930024142_protect_location_membership.sql');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const table = 'public."Location_to_Admin"';
const writes = ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'];
const quote = (value) => `'${value.replaceAll("'", "''")}'`;
const context = (role, actor = 2) => `set local role ${role};
  set local request.jwt.claim.sub='${uid(actor)}';`;

async function setup(t) {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  await db.query(fixture);
  const run = async (sql) => {
    const session = await cluster.connect();
    try { return await session.query(sql); } finally { await session.close(); }
  };
  const rejected = (sql, code = '42501', message) => assert.rejects(run(sql), (error) => {
    assert.equal(error.code, code, error.message);
    if (message) assert(error.message.includes(message), error.message);
    return true;
  });
  const rows = () => db.query(`select jsonb_agg(to_jsonb(m) order by id) from ${table} m;`);
  const permissions = () => db.query(`select jsonb_build_object(
    'acl',(select relacl from pg_class where oid='${table}'::regclass),
    'columns',(select jsonb_agg(jsonb_build_array(attname,attacl) order by attnum)
      from pg_attribute where attrelid='${table}'::regclass and attnum>0 and not attisdropped),
    'memberships',(select coalesce(jsonb_agg(to_jsonb(m) order by oid),'[]') from pg_auth_members m));`);
  const before = async (sql, expected = '42501', message) => {
    const data = await rows(), acl = await permissions();
    await rejected(sql, expected, message);
    assert.equal(await rows(), data);
    assert.equal(await permissions(), acl);
    assert.equal(await db.query("select to_regprocedure('public.guard_location_membership_writes()') is null;"), 't');
  };
  return { cluster, db, run, rejected, rows, permissions, before };
}

test('membership authority on live-shaped catalog in disposable PostgreSQL 17',
  { timeout: 180000 }, async (t) => {
  const { db, run, rejected, rows, before } = await setup(t);
  const install = `set role postgres; ${migration}`;

  await t.test('baseline has the observed non-superuser owner, no client parents, and broad grants', async () => {
    assert.equal(await db.query(`select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';`), 't');
    assert.equal(await db.query(`select count(*) from pg_auth_members m join pg_roles r on r.oid=m.member
      where r.rolname in ('anon','authenticated');`), '0');
    assert.equal(await db.query(`select bool_and(has_table_privilege(r.name,'${table}',p.name))
      from (values ('anon'),('authenticated'),('service_role')) r(name)
      cross join (values ${['SELECT', ...writes].map((p) => `('${p}')`).join(',')}) p(name);`), 't');
    assert.equal(await db.query(`select count(*) from pg_attribute where attrelid='${table}'::regclass and attacl is not null;`), '0');
    assert.equal(await db.query(`select count(*) from pg_trigger where tgrelid='${table}'::regclass and not tgisinternal;`), '0');
    assert.equal(await db.query(`select bool_and(not has_table_privilege('public','${table}',p.name))
      from (values ${['SELECT', ...writes].map((p) => `('${p}')`).join(',')}) p(name);`), 't');
  });

  await t.test('unexpected migration executor fails without any partial revocation', async () => {
    await before(migration, '42501', 'ownership or RLS requires review');
  });
  for (const attribute of ['bypassrls', 'superuser', 'createrole']) {
    await t.test(`unexpected authenticated ${attribute} fails without changing roles or grants`, async () => {
      await db.query(`alter role authenticated ${attribute};`);
      try { await before(install, '42501', 'authority or inheritance requires review'); }
      finally { await db.query(`alter role authenticated no${attribute};`); }
    });
  }
  for (const change of ['disable row level security', 'force row level security']) {
    await t.test(`unexpected ${change} fails closed`, async () => {
      await db.query(`alter table ${table} ${change};`);
      try { await before(install, '42501', 'ownership or RLS requires review'); }
      finally { await db.query(`alter table ${table} enable row level security; alter table ${table} no force row level security;`); }
    });
  }

  for (const [label, grant] of [
    ['direct automatic inheritance', 'grant membership_parent to anon with inherit true, set false'],
    ['SET-only writer', 'grant membership_parent to authenticated with inherit false, set true'],
    ['disabled membership still needs review', 'grant membership_parent to authenticated with inherit false, set false'],
    ['two-hop mixed SET/INHERIT', 'grant membership_parent to membership_middle with inherit true, set false; grant membership_middle to authenticated with inherit false, set true'],
    ['owner SET path', 'grant postgres to authenticated with inherit false, set true'],
  ]) await t.test(`${label}: inheritance drift is rejected, never repaired by stripping the other role`, async () => {
    await db.query(`create role membership_parent; create role membership_middle;
      set role postgres; grant update on ${table} to membership_parent; reset role; ${grant};`);
    try {
      await before(install, '42501', 'authority or inheritance requires review');
      assert.equal(await db.query(`select has_table_privilege('membership_parent','${table}','UPDATE');`), 't');
    } finally {
      await db.query(`revoke postgres from authenticated;
        revoke membership_parent from anon, authenticated, membership_middle;
        revoke membership_middle from authenticated;
        drop owned by membership_parent, membership_middle;
        drop role membership_parent, membership_middle;`);
    }
  });

  await t.test('inherited column-only UPDATE is rejected with the original grant intact', async () => {
    await db.query(`create role membership_parent;
      set role postgres; revoke update on ${table} from authenticated;
      grant update(location_id) on ${table} to membership_parent; reset role;
      grant membership_parent to authenticated with inherit true, set false;`);
    try {
      assert.equal(await db.query(`select not has_table_privilege('authenticated','${table}','UPDATE')
        and has_column_privilege('authenticated','${table}','location_id','UPDATE');`), 't');
      await before(install, '42501', 'authority or inheritance requires review');
    } finally {
      await db.query(`revoke membership_parent from authenticated;
        drop owned by membership_parent; drop role membership_parent;
        set role postgres; grant update on ${table} to authenticated; reset role;`);
    }
  });

  await t.test('residual column grant from another grantor aborts rather than stripping that grantor', async () => {
    await db.query(`create role membership_grantor;
      set role postgres; grant update on ${table} to membership_grantor with grant option;
      reset role; set role membership_grantor;
      grant update(location_id) on ${table} to authenticated; reset role;`);
    try { await before(install, '42501', 'Remaining effective membership privileges require review'); }
    finally {
      await db.query(`set role membership_grantor; revoke update(location_id) on ${table} from authenticated;
        reset role; drop owned by membership_grantor; drop role membership_grantor;`);
    }
  });

  await t.test('dependent downstream grants abort RESTRICT without cascade revocation', async () => {
    await db.query(`create role membership_downstream;
      set role postgres; grant insert on ${table} to authenticated with grant option; reset role;
      set role authenticated; grant insert on ${table} to membership_downstream; reset role;`);
    try { await before(install, '2BP01'); }
    finally {
      await db.query(`set role authenticated; revoke insert on ${table} from membership_downstream; reset role;
        drop role membership_downstream;
        set role postgres; revoke grant option for insert on ${table} from authenticated; reset role;`);
    }
  });

  const originalRows = await rows();
  const structure = () => db.query(`select jsonb_build_object(
    'table',(select jsonb_build_array(relowner,relrowsecurity,relforcerowsecurity) from pg_class where oid='${table}'::regclass),
    'columns',(select jsonb_agg(jsonb_build_array(a.attname,a.atttypid,a.attnotnull,a.attidentity,pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
      from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
      where a.attrelid='${table}'::regclass and a.attnum>0 and not a.attisdropped),
    'constraints',(select jsonb_agg(pg_get_constraintdef(oid) order by conname) from pg_constraint where conrelid='${table}'::regclass),
    'indexes',(select jsonb_agg(pg_get_indexdef(indexrelid) order by indexrelid) from pg_index where indrelid='${table}'::regclass),
    'policies',(select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p),
    'other_acls',(select jsonb_agg(jsonb_build_array(c.oid,c.relacl) order by c.oid) from pg_class c
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.oid<>'${table}'::regclass),
    'schemas',(select jsonb_agg(jsonb_build_array(nspname,nspacl) order by nspname) from pg_namespace where nspname in ('public','auth')),
    'memberships',(select coalesce(jsonb_agg(to_jsonb(m) order by oid),'[]') from pg_auth_members m));`);
  const originalStructure = await structure();
  await run(install);

  await t.test('installation changes no records, SELECT, policies, schema, identity, indexes or unrelated ACLs', async () => {
    assert.equal(await rows(), originalRows);
    assert.equal(await structure(), originalStructure);
    for (const role of ['anon', 'authenticated']) {
      assert.equal(await db.query(`select has_table_privilege('${role}','${table}','SELECT')
        and not has_table_privilege('${role}','${table}',${quote(writes.join(','))})
        and not has_any_column_privilege('${role}','${table}','INSERT,UPDATE,REFERENCES');`), 't');
      assert.equal(await run(`begin; ${context(role)} select count(*) from ${table}; rollback;`), '5');
    }
    assert.equal(await db.query(`select bool_and(has_table_privilege('service_role','${table}',p.name))
      from (values ${['SELECT', ...writes].map((p) => `('${p}')`).join(',')}) p(name);`), 't');
    assert.equal(await db.query(`select count(*) from ${table} where location_id=1 and user_id='${uid(2)}';`), '2');
    assert.equal(await db.query(`select count(*) from ${table} where location_id is null or user_id is null;`), '3');
  });
  await t.test('one ALWAYS statement trigger has an invoker owner-bound function, empty search_path, and no client EXECUTE', async () => {
    assert.equal(await db.query(`select count(*) from pg_trigger t join pg_proc p on p.oid=t.tgfoid
      where t.tgrelid='${table}'::regclass and not t.tgisinternal and t.tgenabled='A'
      and (t.tgtype::int & 1)=0 and not p.prosecdef and pg_get_userbyid(p.proowner)='postgres'
      and p.proconfig=array['search_path=""'];`), '1');
    for (const role of ['anon', 'authenticated', 'service_role', 'public']) assert.equal(await db.query(`select
      has_function_privilege('${role}','public.guard_location_membership_writes()','EXECUTE');`), 'f');
  });

  const operations = [
    ['insert', `insert into ${table}(id,location_id,user_id) values(100,2,'${uid(2)}')`],
    ['update', `update ${table} set location_id=2 where id=1`],
    ['delete', `delete from ${table} where id=1`],
    ['truncate', `truncate ${table}`],
    ['upsert', `insert into ${table}(id,location_id,user_id) values(1,2,'${uid(2)}') on conflict(id) do update set location_id=2`],
  ];
  for (const role of ['anon', 'authenticated']) for (const actor of [1, 2, 3]) {
    for (const [name, sql] of operations) await t.test(`${role}/${['User','Admin','Owner'][actor - 1]} direct ${name} denied`, async () => {
      await rejected(`begin; ${context(role, actor)} ${sql}; commit;`);
      assert.equal(await rows(), originalRows);
    });
  }
  for (const role of ['anon', 'authenticated']) for (const [name, sql] of operations) {
    await t.test(`${role} ${name} is still blocked after accidental broad PUBLIC/table/column grants`, async () => {
      await rejected(`begin; set local role postgres;
        grant all on ${table} to public, anon, authenticated;
        grant insert(id,location_id,user_id),update(id,location_id,user_id) on ${table} to public,anon,authenticated;
        ${context(role, 3)} set local request.jwt.claim.role='service_role';
        ${sql}; commit;`, '42501', 'Membership writes require a trusted server writer');
      assert.equal(await rows(), originalRows);
      assert.equal(await db.query(`select has_table_privilege('${role}','${table}','INSERT');`), 'f');
    });
  }
  for (const role of ['anon', 'authenticated']) await t.test(`${role} TRUNCATE RESTART IDENTITY also remains denied after broad regrant`, async () => {
    await rejected(`begin; grant all on ${table} to ${role};
      ${context(role, 3)} truncate ${table} restart identity; commit;`);
    assert.equal(await rows(), originalRows);
  });
  await t.test('ALWAYS guard blocks client writes even in replica mode after broad regrant', async () => {
    await rejected(`begin; set local session_replication_role=replica;
      grant all on ${table} to authenticated; ${context('authenticated', 3)}
      delete from ${table}; commit;`, '42501', 'Membership writes require a trusted server writer');
    assert.equal(await rows(), originalRows);
  });
  await t.test('client parent-table TRUNCATE CASCADE cannot bypass the membership guard', async () => {
    await rejected(`begin; grant truncate on public.profiles, ${table} to authenticated;
      ${context('authenticated', 3)} truncate public.profiles cascade; commit;`,
      '42501', 'Membership writes require a trusted server writer');
    assert.equal(await rows(), originalRows);
  });
  for (const role of ['postgres', 'service_role']) await t.test(`${role} trusted insert/update/delete/truncate still works without trigger EXECUTE grants`, async () => {
    assert.equal(await run(`begin; ${context(role)}
      insert into ${table}(id,location_id,user_id) values(100,2,'${uid(2)}');
      update ${table} set location_id=3 where id=100;
      delete from ${table} where id=100;
      truncate ${table}; select count(*) from ${table}; rollback;`), '0');
    assert.equal(await rows(), originalRows);
  });
  for (const role of ['postgres', 'service_role']) {
    await t.test(`${role} profile UPDATE cascade preserves both duplicate memberships`, async () => {
      assert.equal(await run(`begin; ${context(role)}
        update public.profiles set id='${uid(9)}' where id='${uid(2)}';
        select count(*) from ${table} where user_id='${uid(9)}'; rollback;`), '2');
      assert.equal(await rows(), originalRows);
    });
    await t.test(`${role} profile DELETE cascade remains compatible`, async () => {
      assert.equal(await run(`begin; ${context(role)} delete from public.profiles where id='${uid(2)}';
        select count(*) from ${table}; rollback;`), '3');
      assert.equal(await rows(), originalRows);
    });
  }
  await t.test('trusted definer remains governed by its executor, not the caller JWT role', async () => {
    assert.equal(await run(`begin; set local role postgres;
      create function public.fixture_membership_writer() returns bigint language plpgsql security definer set search_path='' as $$
      declare result bigint; begin
        insert into public."Location_to_Admin"(id,location_id,user_id) values(100,2,'${uid(2)}') returning id into result;
        return result;
      end; $$;
      revoke all on function public.fixture_membership_writer() from public;
      grant execute on function public.fixture_membership_writer() to service_role;
      ${context('service_role')} set local request.jwt.claim.role='authenticated';
      select public.fixture_membership_writer(); rollback;`), '100');
    assert.equal(await rows(), originalRows);
  });
});

test('explicit PUBLIC and column grants are removed without changing SELECT or unrelated roles',
  { timeout: 90000 }, async (t) => {
  const { db, run, rows } = await setup(t);
  await db.query(`create role unrelated_writer;
    set role postgres;
    grant update(location_id) on ${table} to unrelated_writer;
    grant insert,update,delete,truncate,references,trigger,maintain on ${table} to public;
    grant select(id),insert(id),update(location_id),references(user_id) on ${table} to public,anon,authenticated;
    reset role;`);
  const beforeRows = await rows();
  await run(`set role postgres; ${migration}`);
  for (const role of ['anon', 'authenticated', 'public']) {
    await t.test(`${role} has no mutation privileges at table or column level; its SELECT remains`, async () => {
      assert.equal(await db.query(`select not has_table_privilege('${role}','${table}',${quote(writes.join(','))})
        and not has_any_column_privilege('${role}','${table}','INSERT,UPDATE,REFERENCES')
        and has_column_privilege('${role}','${table}','id','SELECT');`), 't');
    });
  }
  await t.test('unrelated explicit writer, trusted server ACLs and all records remain intact', async () => {
    assert.equal(await db.query(`select has_column_privilege('unrelated_writer','${table}','location_id','UPDATE')
      and has_table_privilege('service_role','${table}', 'UPDATE');`), 't');
    assert.equal(await rows(), beforeRows);
  });
});
