import test from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import { createHash } from 'node:crypto';

import { disposableCluster } from './test-support/policy-admission-pg.mjs';
import { read } from './test-support/account-cleanup.mjs';

test('exact Maintenance key transition, not full migration acceptance', { timeout: 150000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  try {
    const db = await cluster.connect();
    const run = async sql => {
      const connection = await cluster.connect();
      try { return await connection.query(sql); } finally { await connection.close(); }
    };
    const check = async (name, action) => {
      let passed = false;
      await t.test(name, async () => { await action(); passed = true; });
      assert(passed, `Stopped at first failed check: ${name}`);
    };
    const quoteIdentifier = name => `"${name.replaceAll('"', '""')}"`;
    const expectCode = code => error => { assert.equal(error.code, code, error.message); return true; };
    await db.query('set client_min_messages=warning;');
    for (const name of ['loyalty_policy_acceptance', 'account_admission', 'profile_terms_admission', 'maintenance_authorization']) {
      await db.query(await read(`supabase/tests/${name}.fixture.sql`));
    }
    const path = 'supabase/migrations/20261001130950_retained_financial_subjects.sql';
    const migration = await read(path);
    const start = '-- Existing clients still submit their own nonnull subject.';
    const end = '\ncreate or replace function public.record_wallet_load_from_stripe(';
    assert.equal(migration.split(start).length - 1, 1);
    assert.equal(migration.split(end).length - 1, 1);
    const transition = migration.slice(migration.indexOf(start), migration.indexOf(end));
    assert.match(transition, /do \$\$/);
    assert(transition.trimEnd().endsWith('alter table public."Maintenance" alter column user_id drop not null;'));
    t.diagnostic(`SOURCE ${path} sha256=${createHash('sha256').update(migration).digest('hex')}`);
    t.diagnostic(`Complete transition starts at line ${migration.slice(0, migration.indexOf(start)).split('\n').length}; sha256=${createHash('sha256').update(transition).digest('hex')}`);

    // Use the real support table DDL so its FK binds to the pre-existing unique index.
    const cleanup = await read('supabase/migrations/20261001130137_permanent_account_cleanup.sql');
    const supportStart = 'create table private.account_support_retention (';
    const supportEnd = 'create function private.capture_cleanup_support_closure()';
    assert.equal(cleanup.split(supportStart).length - 1, 1);
    assert.equal(cleanup.split(supportEnd).length - 1, 1);
    await db.query(`set role postgres; create schema private authorization postgres;
      ${cleanup.slice(cleanup.indexOf(supportStart), cleanup.indexOf(supportEnd))}
      insert into public."Maintenance"(maint_id,user_id,created_at,description,location,image_data) values
        (101,'00000000-0000-4000-8000-000000000001','2026-01-01Z','First report','Site A','first.jpg'),
        (102,'00000000-0000-4000-8000-000000000002','2026-01-01Z','Second report','Site B','second.jpg'),
        (103,'00000000-0000-4000-8000-000000000001','2026-01-02Z','Retained report','Site A',null);
      insert into private.account_support_retention(maint_id,user_id,closed_at)
        select maint_id,user_id,created_at from public."Maintenance";`);
    const rows = () => db.query('select jsonb_agg(to_jsonb(m) order by maint_id) from public."Maintenance" m;');
    const links = () => db.query('select jsonb_agg(to_jsonb(s) order by maint_id) from private.account_support_retention s;');
    const accessState = () => db.query(`select jsonb_build_object(
      'relations',(select jsonb_agg(jsonb_build_array(oid,relowner,relacl,relrowsecurity,relforcerowsecurity) order by oid)
        from pg_class where oid in ('public."Maintenance"'::regclass,'private.account_support_retention'::regclass,
          'public."Maintenance_id_seq"'::regclass)),
      'columns',(select jsonb_agg(jsonb_build_array(attrelid,attnum,attname,attacl) order by attrelid,attnum)
        from pg_attribute where attrelid in ('public."Maintenance"'::regclass,'private.account_support_retention'::regclass)
          and attnum>0 and not attisdropped),
      'policies',(select jsonb_agg(to_jsonb(p) order by oid) from pg_policy p
        where polrelid in ('public."Maintenance"'::regclass,'private.account_support_retention'::regclass)));`);
    const constraints = () => db.query(`select jsonb_agg(jsonb_build_array(oid,conname,conindid,convalidated,condeferrable,
      pg_get_constraintdef(oid)) order by oid) from pg_constraint
      where conrelid in ('public."Maintenance"'::regclass,'private.account_support_retention'::regclass)
        or confrelid='public."Maintenance"'::regclass;`);
    const shape = () => db.query(`select jsonb_build_object(
      'columns',(select jsonb_agg(jsonb_build_array(attnum,attname,attnotnull,attidentity) order by attnum)
        from pg_attribute where attrelid='public."Maintenance"'::regclass and attnum>0 and not attisdropped),
      'indexes',(select jsonb_agg(to_jsonb(i) order by indexrelid) from pg_index i
        where indrelid='public."Maintenance"'::regclass));`);
    const snapshot = async () => ({ rows: await rows(), links: await links(),
      access: await accessState(), constraints: await constraints(), shape: await shape() });
    const binding = () => db.query(`select jsonb_build_object('fk',f.oid,'index',f.conindid,
      'definition',pg_get_constraintdef(f.oid),'validated',f.convalidated,'unique',u.oid,
      'unique_definition',pg_get_constraintdef(u.oid))
      from pg_constraint f join pg_constraint u on u.conindid=f.conindid and u.contype='u'
      where f.conrelid='private.account_support_retention'::regclass and f.contype='f'
        and u.conrelid='public."Maintenance"'::regclass;`);
    const initialRows = await rows(), initialLinks = await links(), initialAccess = await accessState();
    const initialBinding = await binding();
    const oldKey = await db.query(`select conname from pg_constraint
      where conrelid='public."Maintenance"'::regclass and contype='p';`);
    await check('intact fixture and pre-existing maint_id FK use the documented keys', async () => {
      assert.equal(await db.query(`select pg_get_constraintdef(oid) from pg_constraint
        where conrelid='public."Maintenance"'::regclass and contype='p';`), 'PRIMARY KEY (user_id, created_at)');
      assert.match(await read('docs/supabase.md'), /Maintenance has a composite primary key `\(user_id, created_at\)`/);
      assert.equal(await db.query('select rolsuper from pg_roles where rolname=current_user;'), 'f');
      assert.equal(JSON.parse(initialBinding).unique_definition, 'UNIQUE (maint_id)');
      assert.equal(JSON.parse(initialBinding).validated, true);
      assert.equal(JSON.parse(initialRows).length, 3);
      assert.equal(JSON.parse(initialLinks).length, 3);
    });
    const rejectTransition = async (code, message) => {
      const before = await snapshot();
      await assert.rejects(run(`begin; set local role postgres;
        update public."Maintenance" set description='MUST ROLL BACK' where maint_id=101;
        ${transition} commit;`), error => {
        expectCode(code)(error); assert.match(error.message, message); return true;
      });
      assert.deepEqual(await snapshot(), before, 'DDL, prior DML, ACLs and FK/index identities must roll back');
    };
    await check('changed primary-key signature rejects and rolls back', async () => {
      await db.query(`alter table public."Maintenance" drop constraint ${quoteIdentifier(oldKey)} restrict;
        alter table public."Maintenance" add constraint ${quoteIdentifier(oldKey)} primary key(created_at,user_id);`);
      await rejectTransition('P0001', /Maintenance primary-key prerequisite mismatch/);
      await db.query(`alter table public."Maintenance" drop constraint ${quoteIdentifier(oldKey)} restrict;
        alter table public."Maintenance" add constraint ${quoteIdentifier(oldKey)} primary key(user_id,created_at);`);
    });
    await check('dependent legacy-pair FK rejects RESTRICT and rolls back the added unique constraint', async () => {
      await db.query(`create table private.qa_legacy_maintenance_link(
        user_id uuid, created_at timestamptz,
        foreign key(user_id,created_at) references public."Maintenance"(user_id,created_at));
        insert into private.qa_legacy_maintenance_link select user_id,created_at from public."Maintenance" where maint_id=101;`);
      assert.equal(await db.query(`select f.conindid=p.conindid from pg_constraint f cross join pg_constraint p
        where f.conrelid='private.qa_legacy_maintenance_link'::regclass and f.contype='f'
          and p.conrelid='public."Maintenance"'::regclass and p.contype='p';`), 't');
      await rejectTransition('2BP01', /depend/);
      assert.equal(await db.query('select count(*) from private.qa_legacy_maintenance_link;'), '1');
      await db.query('drop table private.qa_legacy_maintenance_link;');
    });
    await check('complete marked transition preserves rows IDs grants policies and original support FK binding', async () => {
      await run(`begin; set local role postgres; ${transition} commit;`);
      assert.equal(await rows(), initialRows);
      assert.equal(await links(), initialLinks);
      assert.equal(await accessState(), initialAccess);
      assert.equal(await binding(), initialBinding);
      assert.equal(await db.query(`select conname from pg_constraint
        where conrelid='public."Maintenance"'::regclass and contype='p';`), oldKey);
      assert.equal(await db.query(`select pg_get_constraintdef(oid) from pg_constraint
        where conrelid='public."Maintenance"'::regclass and contype='p';`), 'PRIMARY KEY (maint_id)');
      assert.equal(await db.query(`select pg_get_constraintdef(oid) from pg_constraint
        where conrelid='public."Maintenance"'::regclass and conname='Maintenance_user_created_key';`), 'UNIQUE (user_id, created_at)');
    });
    await check('requester-null redaction preserves report identity and support links even at equal timestamps', async () => {
      await db.query(`update public."Maintenance" set user_id=null,description=null,location=null,image_data=null
        where maint_id in (101,102);`);
      const expected = JSON.parse(initialRows).map(row => row.maint_id === 103 ? row :
        { ...row, user_id: null, description: null, location: null, image_data: null });
      assert.deepEqual(JSON.parse(await rows()), expected);
      assert.equal(await links(), initialLinks);
      assert.equal(await binding(), initialBinding);
      assert.equal(await accessState(), initialAccess);
    });
    for (const [name, values] of [
      ['duplicate maint_id', "(101,null,'2026-01-03Z')"],
      ['duplicate nonnull legacy pair', "(104,'00000000-0000-4000-8000-000000000001','2026-01-02Z')"],
    ]) await check(`${name} remains rejected without row changes`, async () => {
      const before = await snapshot();
      await assert.rejects(run(`set role postgres; insert into public."Maintenance"(maint_id,user_id,created_at)
        values ${values};`), expectCode('23505'));
      assert.deepEqual(await snapshot(), before);
    });
    await check('pre-existing support FK still rejects an orphan report', async () => {
      const before = await snapshot();
      await assert.rejects(run(`set role postgres; insert into private.account_support_retention(maint_id,user_id)
        values (999,'00000000-0000-4000-8000-000000000001');`), expectCode('23503'));
      assert.deepEqual(await snapshot(), before);
    });
  } finally {
    await cluster.close();
    await assert.rejects(access(cluster.root), { code: 'ENOENT' });
    t.diagnostic('CLEANUP VERIFIED: all sessions exited, PG stopped, owned cluster directory absent');
  }
});
