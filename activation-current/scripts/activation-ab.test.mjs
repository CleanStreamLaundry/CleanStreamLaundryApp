import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.ACTIVATION_APP_ROOT;
assert(root && isAbsolute(root), 'Set absolute read-only ACTIVATION_APP_ROOT');
const active = pathToFileURL(`${root}/`);
const { disposableCluster } = await import(new URL('scripts/test-support/policy-admission-pg.mjs', active));
const read = (path) => readFile(new URL(path, active), 'utf8');
const artifact = await readFile(new URL('../activation-ab.sql', import.meta.url), 'utf8');
const sources = [
  ['20260929234955_loyalty_policy_acceptance','259d42771722c6a51f84c9688624db3553fa377d770acedfb41d7f230c9c4c6a'],
  ['20260930005456_account_admission','50f6a4cf08e9bd76d3bde0956d43db79b6fa1cb391191f641e5ea25f5a0f49e0'],
  ['20260930013417_enforce_profile_terms_admission','6a74d173592bb71cf0a314712b40a91c22648359947359d8f1697d98c7660595'],
  ['20260930063923_recoverable_account_deletion','bc960d7af1dc61078e1eb849dd2c4e5127867bdba39283ec9dd7f22821bf3315'],
  ['20260930125527_newsletter_consent_mail_outbox','b1dbb1ef6cd8e673cbcb1e5104d24df7bec7138f784714b3f3883b612390b3ca'],
  ['20260930175136_refund_request_notice_outbox','9996ee41291e3e69d254d0fb3925c7458d48227d90a34cd8134a6dfbe471e6b3'],
  ['20260930213049_account_lifecycle_mail_outbox','f34a12156fe2516beecdd6efdf9cc9c8e48978da8a25e2a8e88d95536af91600'],
];
const header = '-- GENERATED: exact reviewed DEVELOPMENT A/B installation, no backfill.\n' +
  '-- Target: dnuuhupoxjtwqzaqylvb. Composer executes only after rehearsal/review.\n' +
  '-- See sources.sha256 and scripts/activation-ab.test.mjs for byte provenance.\nBEGIN;\n\n';
const hold = '-- Approved temporary hold: ordinary API coverage must precede deletion requests.\n' +
  'REVOKE ALL ON FUNCTION public.request_account_deletion()\n' +
  '  FROM PUBLIC, anon, authenticated, service_role;\n\nCOMMIT;\n';
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const user = uid(1), owner = uid(2), session = uid(11), ownerSession = uid(12);
const claims = (extra = {}) => ({sub:user, session_id:session, role:'authenticated', aal:'aal1',
  exp:Math.floor(Date.now()/1000)+3600, ...extra});
const literal = (value) => `'${String(value).replaceAll("'","''")}'`;

test('exact seven-source A/B transaction installs atomically with deletion held and mail disabled', {timeout:180000}, async (t) => {
  await t.test('artifact exactly equals frozen sources with only outer wrappers replaced and final ACL hold', async () => {
    const parts = [];
    for (const [name, hash] of sources) {
      const sql = await read(`supabase/migrations/${name}.sql`);
      assert.equal(createHash('sha256').update(sql).digest('hex'),hash,name);
      assert.equal((sql.match(/^begin;$/gm) || []).length,1,name);
      assert.equal((sql.match(/^commit;$/gm) || []).length,1,name);
      parts.push(`-- SOURCE: supabase/migrations/${name}.sql\n` +
        sql.replace(/^begin;\n/m,'').replace(/^commit;\n?$/m,'') + '\n');
    }
    assert.equal(artifact,header + parts.join('\n') + hold);
    assert.equal((artifact.match(/^BEGIN;$/gm) || []).length,1);
    assert.equal((artifact.match(/^COMMIT;$/gm) || []).length,1);
    assert.equal((artifact.match(/^begin;$/gm) || []).length,0);
    assert.equal((artifact.match(/^commit;$/gm) || []).length,0);
  });
  const cluster = await disposableCluster(t,process.env.PG_BIN), db = await cluster.connect();
  const run = async (sql) => {
    const connection = await cluster.connect();
    try { return await connection.query(sql); } finally { await connection.close(); }
  };
  const call = (sql, jwt = claims(), role = 'authenticated') => run(`begin;
    set local request.jwt.claims=${literal(JSON.stringify(jwt))}; set local request.jwt.claim.sub='';
    set local role ${role}; ${sql}; commit;`);
  await db.query('set client_min_messages=warning; create role postgres superuser; set role postgres;');
  for (const path of ['supabase/tests/loyalty_policy_acceptance.fixture.sql',
    'supabase/migrations/20260929223124_protect_profile_authority.sql',
    'supabase/tests/account_admission.fixture.sql','supabase/tests/profile_terms_admission.fixture.sql',
    'supabase/tests/account_lifecycle.fixture.sql']) await db.query(await read(path));
  // Existing lifecycle fixture uses UUID stand-ins. Extend EMPTY synthetic tables
  // to the catalog's bigint claim shape; no wallet foundation/backfill is run.
  await db.query(`alter table auth.users add column email text,add column created_at timestamptz default now();
    alter table public.transactions alter column id type bigint using null::bigint,
      alter column amount type numeric,add column description text,add column type text default 'debit';
    alter table public."Refunds" rename column id to refund_id;
    alter table public."Refunds" alter column refund_id type bigint using null::bigint,
      add column transaction_id bigint references public.transactions(id),add column amount double precision,
      add column description text,add column date date;
    insert into auth.users(id,email,email_confirmed_at,created_at) values
      ('${user}','customer@example.invalid',now()-interval '1 day',now()-interval '2 days'),
      ('${owner}','owner@example.invalid',now()-interval '1 day',now()-interval '2 days');
    update public.profiles set balance=42,reward_tracker=3,refund_attempts=2;
    update public.profiles set roles='Owner' where id='${owner}';
    insert into auth.sessions(id,user_id,aal,created_at) values
      ('${session}','${user}','aal1',now()-interval '1 hour'),('${ownerSession}','${owner}','aal1',now()-interval '1 hour');
    insert into public.wallet_accounts values('${uid(31)}','${user}',4200,'2026-01-01Z');
    insert into public.wallet_loads values('${uid(32)}','${uid(31)}','${user}',5000,'2026-01-01Z');
    insert into public.wallet_redemptions values('${uid(33)}','${uid(31)}','${user}',800,true,'2026-01-02Z');
    insert into public.transactions(id,user_id,amount,created_at,description) values(41,'${user}',25,'2026-01-02Z','Preserved vend');
    insert into public."Refunds"(refund_id,user_id,transaction_id,amount,status,description,date)
      values(7,'${user}',41,25,'pending','Saved claim','2026-01-03');
    grant usage,create on schema public to postgres; grant usage on schema auth to postgres;
    grant create on database loyalty_policy_fixture to postgres;
    grant select(id,email,created_at,is_anonymous,deleted_at,banned_until,email_confirmed_at),update(id),references(id),trigger
      on auth.users to postgres;
    grant select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions to postgres;
    grant select(id,user_id,factor_type,status) on auth.mfa_factors to postgres;
    reset role; alter role postgres nosuperuser bypassrls;`);
  const snapshot = async () => {
    const result = {};
    for (const table of ['auth.users','auth.sessions','auth.mfa_factors','public.wallet_accounts',
      'public.wallet_loads','public.wallet_redemptions','public.transactions','public."Refunds"']) {
      result[table] = await db.query(`select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]') from ${table} r;`);
    }
    result.profiles = await db.query(`select jsonb_agg((to_jsonb(p)-'loyalty_policy_version'-'loyalty_policy_accepted_at') order by id)
      from public.profiles p;`);
    return result;
  };
  const catalog = () => db.query(`select jsonb_build_object(
    'relations',(select jsonb_agg(jsonb_build_array(c.oid,c.relname,c.relacl,c.relrowsecurity,c.relowner) order by c.oid)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','auth','private')),
    'functions',(select jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proacl) order by p.oid)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','auth','private') and p.prokind='f'),
    'policies',(select jsonb_agg(to_jsonb(p) order by oid) from pg_policy p),
    'triggers',(select jsonb_agg(jsonb_build_array(oid,tgname,tgenabled) order by oid) from pg_trigger where not tgisinternal));`);
  const protectedGuard = () => db.query(`select jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proacl,t.oid,t.tgenabled)
    from pg_proc p join pg_trigger t on t.tgfoid=p.oid
    where p.oid='public.guard_profile_protected_fields()'::regprocedure and t.tgname='profiles_protected_fields_guard';`);
  const initialRows = await snapshot(), initialCatalog = await catalog(), initialGuard = await protectedGuard();
  await t.test('failure after final ACL hold rolls back every source, metadata change and singleton', async () => {
    const broken = artifact.replace(/COMMIT;\n$/,() => "DO $$ BEGIN RAISE EXCEPTION 'synthetic final failure' USING ERRCODE='P0001'; END $$;\nCOMMIT;\n");
    await assert.rejects(run(`set role postgres; ${broken}`), (e) => {
      assert.equal(e.code,'P0001',e.message); assert.match(e.message,/synthetic final failure/); return true;
    });
    assert.equal(await catalog(),initialCatalog); assert.deepEqual(await snapshot(),initialRows);
    assert.equal(await db.query("select to_regnamespace('private') is null;"),'t');
  });
  await t.test('exact artifact commits once under nonsuperuser postgres with required hosted privileges', async () => {
    assert.equal(await db.query("select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';"),'t');
    await run(`set role postgres; ${artifact}`);
    assert.equal(await db.query("select to_regclass('private.mail_outbox') is not null;"),'t');
  });
  await t.test('existing Auth financial claim rows and protected profile values remain unchanged', async () => {
    assert.deepEqual(await snapshot(),initialRows); assert.equal(await protectedGuard(),initialGuard);
    assert.equal(await db.query('select count(*) from public.profiles where loyalty_policy_version is not null or loyalty_policy_accepted_at is not null;'),'0');
  });
  await t.test('admission policies and lifecycle/mail triggers are installed', async () => {
    assert.equal(await db.query(`select count(*) from pg_policy where polname in
      ('profiles_account_admission','profiles_server_provisioning_only') and not polpermissive;`),'2');
    assert.equal(await db.query(`select count(*) from pg_trigger where not tgisinternal and tgenabled='O'
      and tgname in('profiles_policy_acceptance_guard','mail_verified_account','mail_identity_changed','mail_account_suppression');`),'4');
  });
  await t.test('mail singleton is disabled without rollout/recipient and no history was enqueued', async () => {
    const settings = JSON.parse(await db.query('select to_jsonb(s) from private.mail_settings s;'));
    assert.equal(settings.enabled,false); assert.equal(settings.rollout_at,null); assert.equal(settings.refund_notice_recipient,null);
    assert.equal(await db.query('select count(*) from private.mail_settings;'),'1');
    for (const table of ['account_lifecycle','mail_outbox','newsletter_consent','mail_suppression','mail_webhook_event']) {
      assert.equal(await db.query(`select count(*) from private.${table};`),'0',table);
    }
  });
  await t.test('held deletion is effectively denied to anon authenticated and service callers', async () => {
    for (const role of ['anon','authenticated','service_role']) {
      assert.equal(await db.query(`select has_function_privilege('${role}','public.request_account_deletion()','execute');`),'f',role);
      await assert.rejects(call('select public.request_account_deletion()',claims(),role), (e) => {
        assert.equal(e.code,'42501',e.message); return true;
      });
    }
    assert.equal(await db.query('select count(*) from private.account_lifecycle;'),'0');
  });
  await t.test('status and explicit restoration retain their authenticated grants', async () => {
    for (const fn of ['get_account_lifecycle_status','restore_account']) {
      assert.equal(await db.query(`select has_function_privilege('authenticated','public.${fn}()','execute');`),'t');
      for (const role of ['anon','service_role']) assert.equal(await db.query(`select has_function_privilege('${role}','public.${fn}()','execute');`),'f');
    }
    const status = JSON.parse(await call('select public.get_account_lifecycle_status()'));
    assert.equal(status.subject_id,user); assert.equal(status.account_access,'eligible'); assert.equal(status.next_step,'review_terms');
  });
  await t.test('public descriptor is current and anonymous protected RPC cannot manufacture a session', async () => {
    const descriptor = JSON.parse(await call('select public.get_loyalty_policy_descriptor()',{},'anon'));
    assert.equal(descriptor.required_version,'review-only-loyalty-d08c2c970e4fb2f7');
    await assert.rejects(call('select public.get_admission_status()',{},'authenticated'), (e) => {
      assert.equal(e.code,'PT401'); return true;
    });
    const staff = JSON.parse(await call('select public.get_admission_status()',claims({sub:owner,session_id:ownerSession})));
    assert.equal(staff.account_access,'restricted'); assert.equal(staff.next_step,'enroll_totp');
  });
  await t.test('private rows remain inaccessible directly and disabled worker cannot claim', async () => {
    for (const table of ['account_lifecycle','mail_settings','mail_outbox','newsletter_consent','mail_suppression','mail_webhook_event']) {
      for (const role of ['anon','authenticated','service_role']) {
        assert.equal(await db.query(`select has_table_privilege('${role}','private.${table}','select');`),'f');
        assert.equal(await db.query(`select has_table_privilege('${role}','private.${table}','insert');`),'f');
      }
    }
    assert.equal(await call('select public.mail_claim() is null',{},'service_role'),'t');
  });
  await t.test('new synthetic verified signup while disabled creates no outbox job', async () => {
    await db.query(`insert into auth.users(id,email,email_confirmed_at,created_at)
      values('${uid(99)}','new@example.invalid',clock_timestamp(),clock_timestamp());`);
    assert.equal(await db.query('select count(*) from private.mail_outbox;'),'0');
  });
});
