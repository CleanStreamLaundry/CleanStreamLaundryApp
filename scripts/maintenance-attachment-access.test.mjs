import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const fixture = (name) => read(`supabase/tests/${name}.fixture.sql`);
const migration = (name) => read(`supabase/migrations/${name}.sql`);
const sql = await migration('20260930165320_maintenance_attachment_access');
const policies = await read('supabase/storage/maintenance_attachment_policies.sql');
const body = (value) => value.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const customer = uid(1), other = uid(2), staff = uid(3);
const literal = (v) => v === null ? 'null' : `'${String(v).replaceAll("'", "''")}'`;
const claims = (id = customer, extra = {}) => ({ sub: id, session_id: uid(Number(id.slice(-1)) + 10),
  role: 'authenticated', aal: id === staff ? 'aal2' : 'aal1',
  exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (jwt, role = 'authenticated') =>
  `set local request.jwt.claims=${literal(JSON.stringify(jwt))}; set local request.jwt.claim.sub=''; set local role ${role};`;
const asUser = (query, jwt = claims(), role) => `begin; ${context(jwt, role)} ${query}; commit;`;
const resolve = (id = '1') => `select public.get_maintenance_attachment(${literal(id)})`;
const object = (n, owner = customer, extra = {}) => ({ id: uid(n), bucket_id: 'maintenance-images',
  name: `requests/${n}_123.jpg`, owner_id: owner, version: null, archived_at: null,
  is_delete_marker: false, is_versioned: false, ...extra });
const reference = (o) => ({ bucket: o.bucket_id, id: o.id, name: o.name, version: o.version });

test('maintenance attachment access, real PostgreSQL metadata only', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const run = async (query) => {
    const session = await cluster.connect();
    try { return await session.query(query); } finally { await session.close(); }
  };
  const error = (query, code, message) => assert.rejects(run(query), (e) => {
    assert.equal(e.code, code, e.message);
    if (message) assert.match(e.message, new RegExp(`ERROR:  ${code}: ${message}(?:\\n|$)`));
    assert(!e.message.includes('SYNTHETIC_SECRET'));
    return true;
  });
  for (const name of ['loyalty_policy_acceptance', 'account_admission',
    'profile_terms_admission', 'maintenance_authorization']) await db.query(await fixture(name));
  // The older maintenance fixture predates the lifecycle evaluator's session
  // creation-time read. Synthetic least-privilege setup, not a hosted grant.
  await db.query('grant select(created_at) on auth.sessions to postgres;');
  for (const name of ['20260929223124_protect_profile_authority', '20260929234955_loyalty_policy_acceptance',
    '20260930005456_account_admission', '20260930013417_enforce_profile_terms_admission',
    '20260930024142_protect_location_membership', '20260930032327_maintenance_authorization',
    '20260930063923_recoverable_account_deletion']) {
    await db.query(`set role postgres; ${await migration(name)} reset role;`);
  }
  await db.query(`insert into public."Locations"(id,"Address") values (1,'Shared text'),(2,'Shared text');`);
  const addObject = (o) => db.query(`insert into storage.objects select * from
    jsonb_populate_record(null::storage.objects,${literal(JSON.stringify(o))}::jsonb);`);
  const addReport = (id, owner, location, o, ref = reference(o)) => db.query(`
    insert into public."Maintenance"(maint_id,user_id,created_at,location_id,location,image_data,attachment_ref)
    values (${literal(id)},'${owner}',timestamptz '2026-01-01Z' + interval '${id} seconds',
      ${literal(location)},'Shared text',null,${literal(JSON.stringify(ref))}::jsonb);`);
  const reset = async () => {
    await db.query(`truncate public."Maintenance",storage.objects,private.account_lifecycle;
      truncate auth.users cascade;
      insert into auth.users(id,email_confirmed_at) values ('${customer}',now()),('${other}',now()),('${staff}',now());
      insert into auth.sessions(id,user_id,aal,created_at) values
        ('${uid(11)}','${customer}','aal1',now()),('${uid(12)}','${other}','aal1',now()),('${uid(13)}','${staff}','aal2',now());
      update public.profiles set roles='Admin' where id='${staff}';
      insert into auth.mfa_factors(id,user_id,factor_type,status) values ('${uid(23)}','${staff}','totp','verified');
      update auth.sessions set factor_id='${uid(23)}' where id='${uid(13)}';
      insert into public."Location_to_Admin"(location_id,user_id) values (1,'${staff}');`);
    const o = object(31);
    await addObject(o); await addReport('1', customer, 1, o);
  };
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });
  const visible = (jwt = claims(), role) => run(asUser(`select coalesce(jsonb_agg(name order by name),'[]')
    from storage.objects where bucket_id='maintenance-images'`, jwt, role)).then(JSON.parse);
  const insert = (o) => `insert into storage.objects(id,bucket_id,name,owner_id,version,archived_at,is_delete_marker,is_versioned)
    values (${[o.id,o.bucket_id,o.name,o.owner_id,o.version,o.archived_at].map(literal).join(',')},
      ${o.is_delete_marker === null ? 'null' : o.is_delete_marker},${o.is_versioned});`;
  const changeObject = (set) => db.query(`alter table storage.objects disable trigger update_updated_at;
    update storage.objects set ${set} where id='${uid(31)}';
    alter table storage.objects enable trigger update_updated_at;`);
  const pending = (id = customer, expired = false) => db.query(`insert into private.account_lifecycle
    (user_id,deletion_requested_at,restore_until) select '${id}',at,at+interval '720 hours'
    from (select clock_timestamp()-interval '${expired ? 721 : 1} hours' as at) x;`);
  const frozen = await db.query(`select jsonb_object_agg(p.oid::regprocedure::text,pg_get_functiondef(p.oid))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','private','auth','storage') and p.prokind='f';`);
  const oldPolicies = await db.query(`select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
    where schemaname='storage';`);
  await reset();
  await db.query(`insert into public."Maintenance"(maint_id,user_id,created_at,image_data)
    values (2,'${customer}','2020-01-01','https://legacy.invalid/unchanged.jpg');`);
  const oldRows = await db.query('select jsonb_agg(to_jsonb(m) order by maint_id) from public."Maintenance" m;');
  const oldObjects = await db.query('select jsonb_agg(to_jsonb(o) order by id) from storage.objects o;');
  for (const drift of [
    'alter table storage.objects disable row level security;',
    'alter table public."Location_to_Admin" disable trigger location_membership_writes_guard;',
  ]) await t.test(`prerequisite drift aborts atomically: ${drift}`, async () => {
    await error(`begin; ${drift} set local role postgres; ${body(sql)} commit;`, '55000');
    assert.equal(await db.query(`select to_regprocedure('public.get_maintenance_attachment(text)') is null;`), 't');
  });
  await db.query(`set role postgres; ${sql} reset role;`);
  await t.test('additive migration leaves original functions, reports, objects and Storage policies untouched', async () => {
    const original = JSON.parse(frozen);
    for (const [signature, definition] of Object.entries(original)) {
      assert.equal(await db.query(`select pg_get_functiondef(${literal(signature)}::regprocedure);`), definition.trim());
    }
    assert.equal(await db.query('select jsonb_agg(to_jsonb(m) order by maint_id) from public."Maintenance" m;'), oldRows);
    assert.equal(await db.query('select jsonb_agg(to_jsonb(o) order by id) from storage.objects o;'), oldObjects);
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
      where schemaname='storage';`), oldPolicies);
  });
  await t.test('postgres table access without delegated authority cannot activate Storage policies', async () => {
    await error(`set role postgres; ${policies}`, '55000');
  });
  for (const grants of [{}, { postgres: ['storage.buckets'] }, { authenticated: ['storage.objects'] }]) {
    await t.test(`unrelated policy delegation fails closed: ${JSON.stringify(grants)}`, async () => {
      await error(`begin; set local supautils.policy_grants=${literal(JSON.stringify(grants))};
        set local role postgres; ${body(policies)} commit;`, '55000');
      assert.equal(await db.query(`select jsonb_agg(to_jsonb(p) order by policyname)
        from pg_policies p where schemaname='storage';`), oldPolicies);
    });
  }
  await t.test('a delegation setting alone cannot bypass PostgreSQL policy authority', async () => {
    // This local fixture has no supautils hook. The real deployment must prove
    // provider-managed delegation separately, not grant roles to satisfy a test.
    await error(`begin; set local supautils.policy_grants='{"postgres":["storage.objects"]}';
      set local role postgres; ${body(policies)} commit;`, '42501');
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(p) order by policyname)
      from pg_policies p where schemaname='storage';`), oldPolicies);
  });
  await db.query(`set role supabase_storage_admin; ${policies} reset role;`);
  await t.test('activation preserves rows, old upload policy, Storage owner and triggers', async () => {
    assert.equal(await db.query('select jsonb_agg(to_jsonb(o) order by id) from storage.objects o;'), oldObjects);
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(p) order by policyname) from pg_policies p
      where schemaname='storage' and policyname='objects_insert_fixture';`), oldPolicies);
    assert.equal(await db.query(`select pg_get_userbyid(relowner) from pg_class where oid='storage.objects'::regclass;`), 'supabase_storage_admin');
    assert.equal(await db.query(`select count(*) from pg_trigger where tgrelid='storage.objects'::regclass
      and tgname in ('protect_delete','update_updated_at') and tgenabled='O';`), '2');
  });
  await t.test('RPC/definer ACLs have no anon, service-key or client-create escape', async () => {
    for (const role of ['anon','service_role','supabase_auth_admin','policy_no_access']) {
      await error(asUser(resolve(), {}, role), '42501');
    }
    assert.equal(await db.query(`select bool_and(pg_get_userbyid(proowner)='postgres'
      and proconfig=array['search_path=""']) from pg_proc where oid in
      ('private.maintenance_attachment_allowed(uuid)'::regprocedure,
       'private.maintenance_upload_allowed(text,text,timestamptz,boolean)'::regprocedure,
       'public.get_maintenance_attachment(text)'::regprocedure);`), 't');
    assert.equal(await db.query(`select has_schema_privilege('authenticated','private','CREATE');`), 'f');
  });
  await fresh('own attachment available before terms, exact descriptor and current safe upload preserved', async () => {
    assert.deepEqual(JSON.parse(await run(asUser(resolve()))), { maint_id: '1', attachment: reference(object(31)) });
    assert.deepEqual(await visible(), ['requests/31_123.jpg']);
    await run(asUser(insert(object(32))));
    assert.equal(await db.query('select count(*) from storage.objects;'), '2');
    assert.equal(JSON.parse(await run(asUser('select public.get_admission_status()'))).next_step, 'review_terms');
  });
  await fresh('cross-customer resolver and metadata reads deny; unattached upload is not a report attachment', async () => {
    await error(asUser(resolve(), claims(other)), 'PT404', 'attachment_unavailable');
    assert.deepEqual(await visible(claims(other)), []);
    await addObject(object(32));
    assert.deepEqual(await visible(), ['requests/31_123.jpg']);
    assert.deepEqual(await visible({}, 'anon'), []);
  });
  for (const role of ['Admin','Owner']) await fresh(`${role} uses canonical explicit location scope, not address equality`, async () => {
    await db.query(`update public.profiles set roles='${role}' where id='${staff}';`);
    for (const [n, location] of [[32, 2], [33, null]]) {
      const o = object(n); await addObject(o); await addReport(String(n), customer, location, o);
    }
    assert.deepEqual(await visible(claims(staff)), role === 'Owner'
      ? ['requests/31_123.jpg','requests/33_123.jpg'] : ['requests/31_123.jpg']);
    await error(asUser(resolve('32'), claims(staff)), 'PT404');
    await db.query('delete from public."Location_to_Admin";');
    await error(asUser(resolve(), claims(staff)), 'PT404');
    assert.deepEqual(await visible(claims(staff)), role === 'Owner' ? ['requests/33_123.jpg'] : []);
  });
  await fresh('staff own attachment remains visible without its location membership', async () => {
    const o = object(32, staff); await addObject(o); await addReport('2', staff, 2, o);
    assert.equal(JSON.parse(await run(asUser(resolve('2'), claims(staff)))).attachment.id, o.id);
  });
  for (const expired of [false,true]) await fresh(`pending deletion denied even after deadline=${expired}`, async () => {
    await pending(customer, expired);
    await error(asUser(resolve()), 'PT403', 'account_restricted');
    assert.deepEqual(await visible(), []);
    await error(asUser(insert(object(32))), '42501');
  });
  await fresh('pending staff cannot read a customer attachment', async () => {
    await pending(staff);
    await error(asUser(resolve(), claims(staff)), 'PT403');
    assert.deepEqual(await visible(claims(staff)), []);
  });
  await fresh('restoration does not rehabilitate an old session', async () => {
    await run(asUser('select public.request_account_deletion()'));
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at)
      values ('${uid(41)}','${customer}','aal1',clock_timestamp());`);
    const freshJwt = claims(customer, { session_id: uid(41) });
    await run(asUser('select public.restore_account()', freshJwt));
    await error(asUser(resolve()), 'PT401');
    assert.deepEqual(await visible(), []);
    assert.equal(JSON.parse(await run(asUser(resolve(), freshJwt))).attachment.id, uid(31));
  });
  for (const [name, change, code] of [
    ['session revoked', `delete from auth.sessions where id='${uid(11)}'`, 'PT401'],
    ['session expired', `update auth.sessions set not_after=now()-interval '1 second' where id='${uid(11)}'`, 'PT401'],
    ['banned', `update auth.users set banned_until=now()+interval '1 day' where id='${customer}'`, 'PT403'],
    ['unverified', `update auth.users set email_confirmed_at=null where id='${customer}'`, 'PT403'],
    ['deleted', `update auth.users set deleted_at=now() where id='${customer}'`, 'PT403'],
    ['missing role', `update public.profiles set roles=null where id='${customer}'`, 'PT403'],
  ]) await fresh(`${name} denies each new read and upload`, async () => {
    await db.query(change);
    await error(asUser(resolve()), code);
    assert.deepEqual(await visible(), []);
    await error(asUser(insert(object(32))), '42501');
  });
  await fresh('old AAL1 staff token and removed factor remain denied', async () => {
    await error(asUser(resolve(), claims(staff, { aal: 'aal1' })), 'PT403');
    await db.query('delete from auth.mfa_factors;');
    await error(asUser(resolve(), claims(staff)), 'PT403');
    assert.deepEqual(await visible(claims(staff)), []);
  });
  for (const id of [null,'','0','01','-1','1.0','1e0','bad','9223372036854775808']) {
    await fresh(`invalid report ID ${JSON.stringify(id)} is bounded`, () => error(asUser(resolve(id)), 'PT400'));
  }
  await fresh('full bigint ID stays exact text', async () => {
    await db.query(`update public."Maintenance" set maint_id=9223372036854775807;`);
    assert.equal(JSON.parse(await run(asUser(resolve('9223372036854775807')))).maint_id, '9223372036854775807');
  });
  await fresh('missing report and legacy URL alone share unavailable response; no backfill', async () => {
    await error(asUser(resolve('9')), 'PT404', 'attachment_unavailable');
    await db.query(`update public."Maintenance" set attachment_ref=null,image_data='https://legacy.invalid/image';`);
    await error(asUser(resolve()), 'PT404', 'attachment_unavailable');
    assert.deepEqual(await visible(), []);
    assert.equal(await db.query('select image_data from public."Maintenance";'), 'https://legacy.invalid/image');
  });
  for (const set of ["owner_id=null", `owner_id='${other}'`, "version='replaced'", "name='moved.jpg'",
    "archived_at=now()", 'is_delete_marker=true', "bucket_id='another-bucket'"]) {
    await fresh(`stale object fails exact reference: ${set}`, async () => {
      await changeObject(set);
      await error(asUser(resolve()), 'PT404', 'attachment_unavailable');
      assert.deepEqual(await visible(), []);
    });
  }
  await fresh('replacement at same path with different ID cannot inherit attachment access', async () => {
    await changeObject(`id='${uid(99)}'`);
    await error(asUser(resolve()), 'PT404'); assert.deepEqual(await visible(), []);
  });
  await fresh('a forged cross-account report reference cannot grant staff access at another location', async () => {
    await db.query('update public."Maintenance" set location_id=2;');
    await addReport('2', other, 1, object(31));
    await error(asUser(resolve('2'), claims(staff)), 'PT404');
    assert.deepEqual(await visible(claims(staff)), []);
    await error(asUser(resolve('2'), claims(other)), 'PT404');
  });
  await fresh('archived version is not served but a correctly bound current version is', async () => {
    await changeObject(`version='new',is_versioned=true`);
    await db.query(`update public."Maintenance" set attachment_ref=attachment_ref||'{"version":"new"}';`);
    await addObject(object(32, customer, { name: object(31).name, version: 'old', archived_at: '2020-01-01', is_versioned: true }));
    assert.equal(JSON.parse(await run(asUser(resolve()))).attachment.version, 'new');
    assert.deepEqual(await visible(), [object(31).name]);
  });
  await fresh('ambiguous current versions fail closed even if the index drifts', async () => {
    await db.query('drop index storage.objects_current_fixture;');
    try {
      await changeObject(`version='v1',is_versioned=true`);
      await db.query(`update public."Maintenance" set attachment_ref=attachment_ref||'{"version":"v1"}';`);
      await addObject(object(32, other, { name: object(31).name, version: 'v2', is_versioned: true }));
      await error(asUser(resolve()), 'PT404'); assert.deepEqual(await visible(), []);
    } finally {
      await db.query('truncate storage.objects; create unique index objects_current_fixture on storage.objects(bucket_id,name) where archived_at is null;');
    }
  });
  for (const ref of [{ ...reference(object(31)), extra: 'not-authorized' }, { id: 'invalid' }, [], null]) {
    await fresh(`malformed reference ${JSON.stringify(ref)} is unavailable`, async () => {
      await db.query(`update public."Maintenance" set attachment_ref=${literal(JSON.stringify(ref))}::jsonb;`);
      await error(asUser(resolve()), 'PT404'); assert.deepEqual(await visible(), []);
    });
  }
  for (const extra of [{owner_id:other},{owner_id:null},{archived_at:'2020-01-01'}, {is_delete_marker:true},
    ...['','../bad','/bad','bad/','bad//name','bad/./name','bad\\name','bad\nname','x'.repeat(2049)].map(name=>({name}))]) {
    await fresh(`upload denies unowned/unsafe metadata ${JSON.stringify(extra).slice(0,80)}`, () =>
      error(asUser(insert(object(32, customer, extra))), '42501'));
  }
  await fresh('an accidental permissive policy cannot open other-user reads or maintenance mutations', async () => {
    await db.query(`set role supabase_storage_admin;
      create policy fixture_open on storage.objects for all to public using(true) with check(true); reset role;
      alter table storage.objects disable trigger protect_delete;
      alter table storage.objects disable trigger update_updated_at;`);
    try {
      assert.deepEqual(await visible(claims(other)), []);
      assert.deepEqual(await visible({}, 'anon'), []);
      await error(asUser(insert(object(32, other))), '42501');
      await run(asUser(`update storage.objects set name='overwritten' where id='${uid(31)}'`));
      await run(asUser(`delete from storage.objects where id='${uid(31)}'`));
      assert.equal(await db.query(`select name from storage.objects where id='${uid(31)}';`), object(31).name);
    } finally {
      await db.query(`drop policy fixture_open on storage.objects;
        alter table storage.objects enable trigger protect_delete;
        alter table storage.objects enable trigger update_updated_at;`);
    }
  });
  await fresh('other bucket policies keep their own read/write behavior', async () => {
    await db.query(`set role supabase_storage_admin;
      create policy fixture_other on storage.objects for all to authenticated
        using(bucket_id='other-bucket') with check(bucket_id='other-bucket'); reset role;
      alter table storage.objects disable trigger protect_delete;
      alter table storage.objects disable trigger update_updated_at;`);
    try {
      await run(asUser(insert(object(32, customer, { bucket_id:'other-bucket' }))));
      assert.equal(await run(asUser(`select count(*) from storage.objects where bucket_id='other-bucket'`)), '1');
      await error(asUser(`update storage.objects set bucket_id='maintenance-images' where id='${uid(32)}'`), '42501');
      await run(asUser(`update storage.objects set name='changed' where id='${uid(32)}'`));
      await run(asUser(`delete from storage.objects where id='${uid(32)}'`));
      assert.equal(await db.query(`select count(*) from storage.objects where bucket_id='other-bucket';`), '0');
    } finally {
      await db.query(`drop policy fixture_other on storage.objects;
        alter table storage.objects enable trigger protect_delete;
        alter table storage.objects enable trigger update_updated_at;`);
    }
  });
  await fresh('lookup failure sanitizes database details', async () => {
    await db.query('revoke select(id,user_id,aal,factor_id,not_after) on auth.sessions from postgres;');
    try { await error(asUser(resolve()), 'PT503', 'maintenance_unavailable'); }
    finally { await db.query('grant select(id,user_id,aal,factor_id,not_after) on auth.sessions to postgres;'); }
  });
});
