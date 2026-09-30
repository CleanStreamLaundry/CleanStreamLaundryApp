import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (p) => readFile(new URL(p, import.meta.url), 'utf8');
const fixtures = await Promise.all(['loyalty_policy_acceptance', 'account_admission',
  'profile_terms_admission', 'maintenance_authorization'].map((n) => read(`../supabase/tests/${n}.fixture.sql`)));
const prerequisites = await Promise.all(['20260929223124_protect_profile_authority',
  '20260929234955_loyalty_policy_acceptance', '20260930005456_account_admission',
  '20260930013417_enforce_profile_terms_admission', '20260930024142_protect_location_membership']
  .map((n) => read(`../supabase/migrations/${n}.sql`)));
const migration = await read('../supabase/migrations/20260930032327_maintenance_authorization.sql');
const body = migration.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11), factor = uid(21), object = uid(31);
const literal = (v) => v === null ? 'null' : `'${String(v).replaceAll("'", "''")}'`;
const claims = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (jwt = claims(), role = 'authenticated') =>
  `set local request.jwt.claims=${literal(JSON.stringify(jwt))}; set local request.jwt.claim.sub=''; set local role ${role};`;
const asUser = (sql, jwt, role) => `begin; ${context(jwt, role)} ${sql}; commit;`;
const input = { category: 'Other', description: '  Original report  ', location: 'Duplicate address' };
const submit = (v = input) => `select public.submit_maintenance_request(${literal(JSON.stringify(v))}::jsonb)`;

test('canonical maintenance authorization on disposable PostgreSQL 17', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const run = async (sql) => {
    const s = await cluster.connect();
    try { return await s.query(sql); } finally { await s.close(); }
  };
  const call = async (v = input, jwt) => JSON.parse(await run(asUser(submit(v), jwt)));
  const error = (sql, code, message) => assert.rejects(run(sql), (e) => {
    assert.equal(e.code, code, e.message);
    if (message) assert.match(e.message, new RegExp(`ERROR:  ${code}: ${message}(?:\\n|$)`));
    assert(!e.message.includes('SYNTHETIC_SECRET_ERROR'), 'Failure detail leaked');
    return true;
  });
  const reset = () => db.query(`truncate public."Maintenance", storage.objects;
    truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at) values('${user}',now()),('${other}',now());
    insert into auth.sessions(id,user_id,aal) values('${sid}','${user}','aal1'),('${uid(12)}','${other}','aal1');`);
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });
  const count = () => db.query('select count(*) from public."Maintenance";');
  const totp = () => db.query(`insert into auth.mfa_factors(id,user_id,factor_type,status)
    values('${factor}','${user}','totp','verified');
    update auth.sessions set aal='aal2',factor_id='${factor}' where id='${sid}';`);
  const addObject = (extra = {}) => {
    const row = { id: object, bucket_id: 'maintenance-images', name: 'requests/1_2.jpg', owner_id: user,
      version: null, archived_at: null, is_delete_marker: false, is_versioned: false, ...extra };
    return db.query(`insert into storage.objects select * from jsonb_populate_record(null::storage.objects,
      ${literal(JSON.stringify(row))}::jsonb);`);
  };
  for (const sql of fixtures) await db.query(sql);
  for (const sql of prerequisites) await db.query(`set role postgres; ${sql} reset role;`);
  await db.query(`insert into public."Locations"(id,"Address") values(1,'Duplicate address'),(2,'Duplicate address'),(3,null);`);
  const protectedSnapshot = () => db.query(`select jsonb_build_object(
    'functions',(select jsonb_object_agg(p.oid::regprocedure::text,pg_get_functiondef(p.oid))
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('public','private','auth','storage') and p.prokind='f'
        and p.proname not in ('guard_maintenance_writes','maintenance_record_access','submit_maintenance_request')),
    'storage',(select to_jsonb(c) from pg_class c where oid='storage.objects'::regclass),
    'policies',(select jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname) from pg_policies p
      where policyname <> 'maintenance_record_scope'));`);
  const frozen = await protectedSnapshot();

  const drift = [
    ['type', 'add column location_id text references public."Locations"("Address")'],
    ['missing FK', 'add column location_id bigint'],
    ['cascade', 'add column location_id bigint references public."Locations"(id) on delete cascade'],
    ['wrong target', 'add column location_id bigint references public."Location_to_Admin"(id)'],
    ['default', 'add column location_id bigint default 1 references public."Locations"(id)'],
    ['not null', 'add column location_id bigint not null references public."Locations"(id)'],
    ['deferred', 'add column location_id bigint references public."Locations"(id) deferrable'],
  ];
  // A text column alone exercises type drift without needing an invalid FK DDL.
  drift[0][1] = 'add column location_id text';
  for (const [name, ddl] of drift) await t.test(`preexisting location ${name} aborts atomically`, async () => {
    await error(`begin; set local role postgres; alter table public."Maintenance" ${ddl}; ${body}; commit;`, '55000');
    assert.equal(await db.query(`select count(*) from pg_attribute where attrelid='public."Maintenance"'::regclass
      and attname in ('location_id','attachment_ref') and not attisdropped;`), '0');
  });
  await t.test('unvalidated existing FK aborts without silently validating historical records',async()=>{
    await error(`begin; set local role postgres; alter table public."Maintenance" add column location_id bigint;
      alter table public."Maintenance" add foreign key(location_id) references public."Locations"(id) not valid;
      ${body}; commit;`,'55000');
  });
  for (const ddl of [
    'alter table public."Maintenance" disable row level security;',
    'alter table public."Location_to_Admin" disable trigger location_membership_writes_guard;',
    'alter table public.profiles disable trigger profiles_protected_fields_guard;',
  ]) await t.test(`missing prerequisite fails: ${ddl}`, async () => {
    await error(`begin; set local role postgres; ${ddl} ${body}; commit;`, '55000');
  });
  for (const options of ['inherit true, set true', 'inherit false, set true', 'inherit true, set false']) {
    await t.test(`unexpected client parent path fails closed (${options})`, async () => {
      await error(`begin; create role fixture_parent; grant fixture_parent to authenticated with ${options};
        set local role postgres; ${body}; commit;`, '42501');
    });
  }
  await t.test('downstream column grant aborts RESTRICT, preserving all prior ACLs', async () => {
    await error(`begin; set local role postgres;
      grant update(description) on public."Maintenance" to authenticated with grant option;
      set local role authenticated; grant update(description) on public."Maintenance" to policy_no_access;
      set local role postgres; ${body}; commit;`, '2BP01');
  });
  await t.test('compatible existing nullable FK is preserved without backfill', async () => {
    await db.query(`begin; set local role postgres; alter table public."Maintenance"
      add column location_id bigint references public."Locations"(id); ${body}; rollback;`);
  });
  await t.test('PUBLIC and direct column grants are revoked without removing SELECT',async()=>{
    await db.query(`begin; set local role postgres;
      grant all on public."Maintenance" to public;
      grant insert(description),update(description),references(description) on public."Maintenance" to anon,authenticated;
      ${body};`);
    assert.equal(await db.query(`select has_table_privilege('authenticated','public."Maintenance"','SELECT')
      and not has_any_column_privilege('authenticated','public."Maintenance"','UPDATE');`),'t');
    await db.query('rollback; reset role;');
  });
  await db.query(`insert into public."Maintenance"(user_id,description,image_data,created_at,location)
    values('${other}','Historical report','https://untrusted.invalid/old.jpg','2020-01-01','Duplicate address');`);
  const oldRows = await db.query('select jsonb_agg(to_jsonb(m)) from public."Maintenance" m;');
  await db.query(`set role postgres; ${migration} reset role;`);

  await t.test('preserves old bytes, frozen authority and all Storage/Auth policies and functions', async () => {
    assert.equal(await protectedSnapshot(), frozen);
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(m)-'location_id'-'attachment_ref') from public."Maintenance" m;`), oldRows);
    assert.equal(await db.query('select count(*) from public."Maintenance" where location_id is not null or attachment_ref is not null;'), '0');
  });
  await t.test('non-superuser live-shaped owner, minimal public RPC and private predicate ACLs', async () => {
    assert.equal(await db.query(`select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';`), 't');
    assert.equal(await db.query(`select bool_and(pg_get_userbyid(proowner)='postgres' and proconfig=array['search_path=""'])
      from pg_proc where oid in ('public.submit_maintenance_request(jsonb)'::regprocedure,
        'private.maintenance_record_access(uuid,bigint)'::regprocedure,'public.guard_maintenance_writes()'::regprocedure);`), 't');
    for (const role of ['anon','service_role','supabase_auth_admin','policy_no_access']) {
      await error(asUser(submit(), {}, role), '42501');
    }
    assert.equal(await db.query(`select has_function_privilege('authenticated','public.submit_maintenance_request(jsonb)','EXECUTE')
      and has_function_privilege('authenticated','private.maintenance_record_access(uuid,bigint)','EXECUTE')
      and not has_function_privilege('authenticated','private.current_account_access()','EXECUTE')
      and not has_schema_privilege('authenticated','private','CREATE')
      and to_regprocedure('public.maintenance_record_access(uuid,bigint)') is null;`), 't');
    assert.equal(await db.query(`select bool_and(not has_table_privilege(r.role,'auth.'||t.name,'SELECT'))
      from (values ('anon'),('authenticated')) r(role) cross join (values ('users'),('sessions'),('mfa_factors')) t(name);`), 't');
    assert.equal(await db.query(`select has_table_privilege('postgres','storage.objects','SELECT')
      and not pg_has_role('postgres','supabase_storage_admin','USAGE')
      and not pg_has_role('postgres','supabase_storage_admin','SET');`), 't');
  });
  await t.test('effective client writes and column paths are revoked, SELECT and trusted writes retained', async () => {
    for (const role of ['anon','authenticated']) {
      assert.equal(await db.query(`select has_table_privilege('${role}','public."Maintenance"','SELECT');`), 't');
      for (const privilege of ['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) {
        assert.equal(await db.query(`select has_table_privilege('${role}','public."Maintenance"','${privilege}');`), 'f');
      }
      for (const privilege of ['INSERT','UPDATE','REFERENCES']) {
        assert.equal(await db.query(`select has_any_column_privilege('${role}','public."Maintenance"','${privilege}');`), 'f');
      }
    }
    assert.equal(await db.query(`select has_table_privilege('service_role','public."Maintenance"','INSERT,UPDATE,DELETE');`), 't');
    assert.equal(await db.query(`select tgenabled='A' from pg_trigger where tgname='maintenance_writes_guard';`), 't');
  });
  for (const role of ['anon','authenticated']) for (const mutation of [
    `insert into public."Maintenance"(user_id,created_at) values('${user}',now())`,
    `update public."Maintenance" set description='forged'`,
    'delete from public."Maintenance"', 'truncate public."Maintenance"',
  ]) await t.test(`accidental regrant defense: ${role} ${mutation.split(' ')[0]}`, async () => {
    await error(`begin; set local role postgres; grant all on public."Maintenance" to ${role};
      create policy fixture_regrant on public."Maintenance" for all to public using(true) with check(true);
      ${context(claims(),role)} ${mutation}; commit;`, '42501');
  });

  await fresh('support succeeds before loyalty acceptance; one durable full row with no client time/identity', async () => {
    const before = Date.now();
    const result = await call({ ...input, user_id: user.toUpperCase(), created_at: '1970-01-01', maint_id: 999,
      image_data: 'https://forged.invalid', status: 'resolved', owner_id: other });
    assert.equal(result.success, true); assert.equal(result.message, 'Request logged');
    assert.equal(result.record.length, 1);
    const row = result.record[0];
    assert.deepEqual(row, JSON.parse(await db.query(`select to_jsonb(m) from public."Maintenance" m;`)));
    assert.equal(row.user_id,user); assert.equal(row.description,input.description);
    assert.equal(row.image_data,null); assert.equal(row.attachment_ref,null); assert.equal(row.location_id,null);
    assert(Date.parse(row.created_at) >= before && Date.parse(row.created_at) <= Date.now());
    assert.notEqual(row.maint_id,999);
    assert.equal(await db.query(`select loyalty_policy_accepted_at is null from public.profiles where id='${user}';`),'t');
    assert.equal(JSON.parse(await run(asUser('select public.get_admission_status()'))).next_step,'review_terms');
  });
  await fresh('explicit location ID is stored; duplicate addresses never infer location', async () => {
    assert.equal((await call({...input,location_id:'2'})).record[0].location_id,2);
    assert.equal((await call()).record[0].location_id,null);
    assert.equal(await count(),'2');
  });
  const invalid = [null, [], {}, { ...input,user_id:null }, { ...input,user_id:'bad' },
    ...['', ' ', '\u00a0', 'x'.repeat(4001), '\u{1f600}'.repeat(2001)].map(description=>({...input,description})),
    ...[null,0,{},'', 'Other '].map(category=>({...input,category})),
    ...['x'.repeat(1001),[],null].map(location=>({...input,location})),
    ...[0,'0','-1','01','1.0','bad','9223372036854775808','9'].map(location_id=>({...input,location_id})),
    ...['https://supabase.invalid/x',{},5].map(image=>({...input,image})),
    ...[[],{},{name:''},{name:'../bad'},{name:'requests//bad'},{name:'requests/a',owner_id:user},
      {name:'requests/a',version:'forged'},{name:'requests/a',id:object}].map(attachment=>({...input,attachment}))];
  for (const [i,value] of invalid.entries()) await fresh(`direct RPC validation ${i+1} has no write`, async () => {
    await error(asUser(submit(value)),'PT400','invalid_request'); assert.equal(await count(),'0');
  });
  await fresh('direct cross-user payload returns only fixed mismatch', async () => {
    await error(asUser(submit({...input,user_id:other})),'PT403','user_mismatch');
  });
  await fresh('UTF-16 exact boundaries accepted without truncating original text', async () => {
    const report={...input,description:'\u{1f600}'.repeat(2000),location:'\u{1f600}'.repeat(500)};
    assert.equal((await call(report)).record[0].description,report.description);
  });
  for (const version of [null,'version-2']) await fresh(`owned current attachment version=${version} is derived from Storage`, async () => {
    await addObject({version,is_versioned:version!==null});
    const row=(await call({...input,attachment:{name:'requests/1_2.jpg'}})).record[0];
    assert.deepEqual(row.attachment_ref,{bucket:'maintenance-images',id:object,name:'requests/1_2.jpg',version});
    assert.equal(row.image_data,null);
  });
  for (const extra of [{owner_id:other},{owner_id:null},{bucket_id:'other'},{archived_at:'2020-01-01'},
    {is_delete_marker:true},{name:'missing.jpg'}]) await fresh(`attachment rejection ${JSON.stringify(extra)}`,async()=>{
    await addObject(extra);
    await error(asUser(submit({...input,attachment:{name:'requests/1_2.jpg'}})),'PT400','invalid_request');
    assert.equal(await count(),'0');
  });
  await fresh('archived history cannot shadow current version',async()=>{
    await addObject({id:uid(32),version:'old',is_versioned:true,archived_at:'2020-01-01'});
    await addObject({version:'new',is_versioned:true});
    assert.equal((await call({...input,attachment:{name:'requests/1_2.jpg'}})).record[0].attachment_ref.version,'new');
  });
  await fresh('foreign current collision cannot be hidden by filtering for only owned objects',async()=>{
    await db.query('drop index storage.objects_current_fixture;');
    try {
      await addObject({version:'a',is_versioned:true});
      await addObject({id:uid(32),owner_id:other,version:'b',is_versioned:true});
      await error(asUser(submit({...input,attachment:{name:'requests/1_2.jpg'}})),'PT400','invalid_request');
    } finally {
      await db.query('truncate storage.objects; create unique index objects_current_fixture on storage.objects(bucket_id,name) where archived_at is null;');
    }
  });
  await fresh('ambiguous current metadata fails closed even if unique index drifts',async()=>{
    await db.query('drop index storage.objects_current_fixture;');
    try {
      await addObject({version:'a',is_versioned:true}); await addObject({id:uid(32),version:'b',is_versioned:true});
      await error(asUser(submit({...input,attachment:{name:'requests/1_2.jpg'}})),'PT400','invalid_request');
    } finally {
      await db.query('truncate storage.objects; create unique index objects_current_fixture on storage.objects(bucket_id,name) where archived_at is null;');
    }
  });

  for (const [name,change,code] of [
    ['revoked',`delete from auth.sessions where id='${sid}'`,'PT401'],
    ['unverified',`update auth.users set email_confirmed_at=null where id='${user}'`,'PT403'],
    ['anonymous',`update auth.users set is_anonymous=true where id='${user}'`,'PT403'],
    ['banned',`update auth.users set banned_until=now()+interval '1 day' where id='${user}'`,'PT403'],
    ['deleted',`update auth.users set deleted_at=now() where id='${user}'`,'PT403'],
    ['missing profile',`delete from public.profiles where id='${user}'`,'PT403'],
    ['unknown role',`update public.profiles set roles=null where id='${user}'`,'PT403'],
    ['staff unenrolled',`update public.profiles set roles='Admin' where id='${user}'`,'PT403'],
    ['session expired',`update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`,'PT401'],
  ]) await fresh(`canonical ${name} denies creation and reads`, async()=>{
    await db.query(change);
    await error(asUser(submit()),code,code==='PT401'?'session_invalid':'account_restricted');
    assert.equal(await count(),'0');
  });
  for (const jwt of [claims({exp:1}),claims({aal:'aal3'}),claims({session_id:uid(12)}),claims({role:'service_role'}),{}]) {
    await fresh(`invalid canonical JWT ${JSON.stringify(jwt)} cannot submit`,async()=>{
      await error(asUser(submit(),jwt),'PT401','session_invalid');
    });
  }
  await fresh('original AAL1 is not promoted; unsupported factor and staff removal fail closed',async()=>{
    await totp(); await error(asUser(submit()),'PT403','account_restricted');
    assert.equal((await call(input,claims({aal:'aal2'}))).success,true);
    await db.query(`update auth.mfa_factors set factor_type='recovery_code' where id='${factor}';`);
    await error(asUser(submit(),claims({aal:'aal2'})),'PT403','account_restricted');
    await db.query('delete from auth.mfa_factors;');
    // Canonical User/no-factor eligibility intentionally stays unchanged.
    assert.equal((await call(input,claims({aal:'aal2'}))).success,true);
    await db.query(`update public.profiles set roles='Admin' where id='${user}';`);
    await error(asUser(submit(),claims({aal:'aal2'})),'PT403','account_restricted');
  });
  for (const role of ['User','Admin','Owner']) await fresh(`read scope for ${role}: own, explicit member, unassigned only`,async()=>{
    await db.query(`update public.profiles set roles='${role}' where id='${user}';
      insert into public."Location_to_Admin"(location_id,user_id) values(1,'${user}'),(1,'${user}');
      insert into public."Maintenance"(user_id,created_at,location_id,description) values
        ('${user}','2020-01-01',2,'own'),('${other}','2020-01-02',1,'member'),
        ('${other}','2020-01-03',2,'other-location'),('${other}','2020-01-04',null,'unassigned');`);
    await totp();
    const query=`select coalesce(jsonb_agg(description order by description),'[]'::jsonb) from public."Maintenance"`;
    const visible=JSON.parse(await run(asUser(query,claims({aal:'aal2'}))));
    assert.deepEqual(visible,role==='User'?['own']:role==='Admin'?['member','own']:['member','own','unassigned']);
    assert.equal(await run(asUser('select count(*) from public."Maintenance"',claims())),'0');
    await db.query(`delete from public."Location_to_Admin";`);
    const after=JSON.parse(await run(asUser(query,claims({aal:'aal2'}))));
    assert.deepEqual(after,role==='Owner'?['own','unassigned']:['own']);
    assert.equal(await run(asUser('select count(*) from public."Maintenance"',{},'anon')),'0');
  });
  await fresh('trusted service writes remain possible without creating a client write path',async()=>{
    await run(asUser(`insert into public."Maintenance"(user_id,created_at) values('${user}',now())`,{},'service_role'));
    assert.equal(await count(),'1');
  });
  await fresh('lookup failure exposes no Auth or SQL details',async()=>{
    await db.query('revoke select(id,user_id,aal,factor_id,not_after) on auth.sessions from postgres;');
    try { await error(asUser(submit()),'PT503','maintenance_unavailable'); }
    finally { await db.query('grant select(id,user_id,aal,factor_id,not_after) on auth.sessions to postgres;'); }
  });
  await fresh('database failure is sanitized and rolled back',async()=>{
    await db.query(`create function public.fixture_fail_report() returns trigger language plpgsql as $$
      begin raise exception 'SYNTHETIC_SECRET_ERROR'; end $$;
      create trigger fixture_fail_report after insert on public."Maintenance" for each row execute function public.fixture_fail_report();`);
    try { await error(asUser(submit()),'PT503','maintenance_unavailable'); assert.equal(await count(),'0'); }
    finally { await db.query('drop trigger fixture_fail_report on public."Maintenance"; drop function public.fixture_fail_report();'); }
  });
  await fresh('Auth lock wait rechecks committed ban before insertion',async()=>{
    const holder=await cluster.connect(), waiter=await cluster.connect();
    await holder.query(`begin; update auth.users set banned_until=now()+interval '1 day' where id='${user}';`);
    const pending=assert.rejects(waiter.query(asUser(submit())),e=>e.code==='PT403');
    await blocked(db,waiter,holder); await holder.query('commit;'); await pending;
    await holder.close(); await waiter.close(); assert.equal(await count(),'0');
  });
  for (const change of ['session','factor','attachment']) await fresh(`post-insert wait rechecks ${change} and rolls back`,async()=>{
    await db.query(`update public.profiles set roles='Admin' where id='${user}';`);
    await totp(); await addObject({version:'v1',is_versioned:true});
    await db.query(`create function public.fixture_wait_report() returns trigger language plpgsql as $$
      begin perform pg_advisory_xact_lock(8391); return new; end $$;
      create trigger fixture_wait_report after insert on public."Maintenance" for each row execute function public.fixture_wait_report();`);
    const holder=await cluster.connect(), waiter=await cluster.connect();
    try {
      await holder.query('begin; select pg_advisory_xact_lock(8391);');
      const pending=assert.rejects(waiter.query(asUser(submit({...input,attachment:{name:'requests/1_2.jpg'}}),claims({aal:'aal2'}))),
        e=>e.code===(change==='session'?'PT401':change==='factor'?'PT403':'PT400'));
      await blocked(db,waiter,holder);
      if(change==='session') await db.query(`delete from auth.sessions where id='${sid}';`);
      else if(change==='factor') await db.query('delete from auth.mfa_factors;');
      else await db.query(`alter table storage.objects disable trigger update_updated_at;
        update storage.objects set version='v2' where id='${object}'; alter table storage.objects enable trigger update_updated_at;`);
      await holder.query('commit;'); await pending; assert.equal(await count(),'0');
    } finally {
      await holder.close(); await waiter.close();
      await db.query('drop trigger fixture_wait_report on public."Maintenance"; drop function public.fixture_wait_report();');
    }
  });
});
