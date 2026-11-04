import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { isAbsolute, basename } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.ACTIVATION_APP_ROOT;
assert(root && isAbsolute(root), 'Set absolute read-only ACTIVATION_APP_ROOT');
const active = pathToFileURL(`${root}/`);
const { disposableCluster } = await import(new URL('scripts/test-support/policy-admission-pg.mjs', active));
const read = (p) => readFile(new URL(p, active), 'utf8');
const local = (p) => readFile(new URL(`../${p}`, import.meta.url), 'utf8');
const migration = (n) => read(`supabase/migrations/${n}.sql`);
const artifact = await local('activation-cd.sql');
const manifest = (await local('cd-sources.sha256')).trim().split('\n');
const hash = (s) => createHash('sha256').update(s).digest('hex');
const header = '-- GENERATED: exact reviewed DEVELOPMENT C/D installation, no historical backfill.\n' +
  '-- Target: dnuuhupoxjtwqzaqylvb. A/B already installed; never replay foundations.\n' +
  '-- See cd-sources.sha256 and scripts/activation-cd.test.mjs for byte provenance.\nBEGIN;\n\n';
const guard = `-- Preserve installed containment; never silently repair a drifted activation gate.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) r
      WHERE has_function_privilege(r,'public.request_account_deletion()','EXECUTE'))
    OR (SELECT count(*) FROM private.mail_settings) <> 1
    OR EXISTS (SELECT 1 FROM private.mail_settings
      WHERE enabled IS DISTINCT FROM false OR rollout_at IS NOT NULL OR refund_notice_recipient IS NOT NULL) THEN
    RAISE EXCEPTION 'C/D requires deletion held and mail disabled without rollout/recipient' USING ERRCODE='55000';
  END IF;
END;
$$;

COMMIT;
`;
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const user = uid(1), owner = uid(2), sid = uid(11), ownerSid = uid(12), vend = uid(31);
const q = (v) => `'${String(v).replaceAll("'","''")}'`;
const claims = (extra = {}) => ({sub:user,session_id:sid,role:'authenticated',aal:'aal1',
  exp:Math.floor(Date.now()/1000)+3600,...extra});
const staff = () => claims({sub:owner,session_id:ownerSid,aal:'aal2'});
const context = (jwt = claims(), role = 'authenticated') =>
  `set local request.jwt.claims=${q(JSON.stringify(jwt))}; set local request.jwt.claim.sub=''; set local role ${role};`;
const fail = (code, message) => (e) => {
  assert.equal(e.code,code,e.message); if (message) assert.match(e.message,message); return true;
};

test('exact C/D install on installed A/B preserves history and final authorization', {timeout:180000}, async (t) => {
  await t.test('18 exact accepted inputs assemble once with only documented wrapper/backfill omission', async () => {
    assert.equal(manifest.length,18);
    const parts = [];
    for (const line of manifest) {
      const match = line.match(/^([a-f0-9]{64})  (.+)$/); assert(match);
      const [,digest,path] = match;
      const name = basename(path);
      const sql = name==='admin-portal-install-no-backfill.sql' ? await local(name) : await read(`supabase/migrations/${name}`);
      assert.equal(hash(sql),digest,name);
      assert.equal((sql.match(/^begin;$/gm)||[]).length,1,name);
      assert.equal((sql.match(/^commit;$/gm)||[]).length,1,name);
      parts.push(`-- SOURCE: ${name==='admin-portal-install-no-backfill.sql'?name:`supabase/migrations/${name}`}\n` +
        sql.replace(/^begin;\n/m,'').replace(/^commit;\n?$/m,'')+'\n');
    }
    assert.equal(artifact,header+parts.join('\n')+guard);
    assert.equal((artifact.match(/^BEGIN;$/gm)||[]).length,1);
    assert.equal((artifact.match(/^COMMIT;$/gm)||[]).length,1);
    assert.equal((artifact.match(/^(begin|commit);$/gm)||[]).length,0);
    assert(!artifact.includes('Legacy profiles.balance backfill'));
    assert(!artifact.includes("select public.sync_cortina_transaction"));
    const original = await migration('20260928135006_admin_portal_operations');
    const omitted = '-- Only unambiguous exact address matches are backfilled. Unknown records remain\n' +
      '-- owner-only; legacy mobile clients may continue submitting address strings.\n' +
      'update public."Maintenance" m set location_id = matched.id\n' +
      'from (select min(id) id, "Address" from public."Locations" group by "Address" having count(*) = 1) matched\n' +
      'where m.location_id is null and m.location = matched."Address";';
    assert(original.includes(omitted));
    assert.equal(await local('admin-portal-install-no-backfill.sql'), original.replace(omitted,
      '-- Development install: historical address attribution is deliberately omitted.\n' +
      '-- Existing rows and addresses are preserved; no location ownership is inferred.'));
  });
  const cluster = await disposableCluster(t,process.env.PG_BIN), db = await cluster.connect();
  const run = async (sql) => {
    const s = await cluster.connect();
    try { return await s.query(sql); } finally { await s.close(); }
  };
  const call = (sql,jwt,role) => run(`begin; ${context(jwt,role)} ${sql}; commit;`);
  const json = async (sql,jwt,role) => JSON.parse(await call(sql,jwt,role));

  // Reconstruct only an EMPTY synthetic legacy baseline, then installed A/B.
  // These fixture inputs are never C/D deployment inputs or hosted replays.
  const fixture = (await read('supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS');
  assert.equal(fixture.length,2);
  await db.query('set client_min_messages=warning; create role postgres superuser; set role postgres;');
  await db.query(fixture[0]);
  for (const n of ['20260526010000_wallet_ledger_compliance','20260803150427_cortina_qr_remote_vend',
    '20260807191723_harden_refund_resolution']) await db.query(await migration(n));
  await db.query(`grant execute on function public.is_admin_or_owner() to authenticated;
    create trigger handle_transaction after insert on public.transactions for each row execute function public.update_user_balance();`);
  for (const n of ['20260807195409_configure_dryer_time_options','20260922224735_cortina_price_array_selectors',
    '20260928132533_link_cortina_transaction_history']) await db.query(await migration(n));
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column created_at timestamptz default now(),add column is_anonymous boolean default false,
    add column banned_until timestamptz,add column deleted_at timestamptz,
    add column raw_user_meta_data jsonb default '{}',add column raw_app_meta_data jsonb default '{}',
    add column last_sign_in_at timestamptz;
    alter table public.profiles add column created_at timestamptz default now();
    alter table public."Location_to_Admin" enable row level security;
    alter table public."Locations" alter column id add generated by default as identity,
      add column "Name" text,add column "Address" text,add column "Latitude" double precision,add column "Longitude" double precision;
    alter table public."Machines" add column "Runtime" smallint,add column "Status" text default 'idle';
    alter table public.transactions alter column amount type double precision;
    alter table public."Refunds" alter column amount type double precision,add column date date default current_date;
    create table public."Maintenance"(maint_id bigint primary key,user_id uuid,category text default 'Other',
      description text,created_at timestamptz default now(),location text,image_data varchar);
    alter table public."Maintenance" enable row level security;
    grant execute on function public.increment_user_refund_attempts(uuid) to public,anon,authenticated,service_role;`);
  await db.query(await migration('20260929223124_protect_profile_authority'));
  await db.query(await read('supabase/tests/account_admission.fixture.sql'));
  const ab = await local('activation-ab.sql');
  assert.equal(hash(ab),'bbcf4efb6c60575d6ceb338787e519b140ddb45a3d0232f4f3f9ea20ca03d293');
  await db.query(ab);
  await db.query(`insert into auth.users(id,email,email_confirmed_at) values
      ('${user}','customer@example.invalid',now()),('${owner}','owner@example.invalid',now());
    insert into public.profiles(id,roles,loyalty_policy_version,loyalty_policy_accepted_at,refund_attempts) values
      ('${user}','User',public.get_loyalty_policy_descriptor()->>'required_version',now(),2),
      ('${owner}','Owner',public.get_loyalty_policy_descriptor()->>'required_version',now(),0);
    insert into auth.sessions(id,user_id,aal,created_at,factor_id) values
      ('${sid}','${user}','aal1',now()-interval '1 hour',null),
      ('${ownerSid}','${owner}','aal2',now()-interval '1 hour','${uid(22)}');
    insert into auth.mfa_factors(id,user_id,factor_type,status) values('${uid(22)}','${owner}','totp','verified');
    insert into public."Locations"(id,"Name","Address") values(1,'Synthetic North','Synthetic matched address');
    insert into public."Location_to_Admin" values('${owner}',1);
    insert into public.washer_size_rates(id,location_id,size_label,capacity_kg,price_cents) values(1,1,'Synthetic washer',12,750);
    insert into public."Machines"(id,"Location_ID","Machine_type","Name",washer_size_rate_id)
      values(1,1,'Washer','Synthetic washer',1);
    update public.cortina_machine_config set nayax_terminal_id='synthetic-terminal',pulse_line_number=1,
      environment='sandbox',is_enabled=true,review_required=false where machine_id=1;
    -- Historical synthetic rows, not a call into the known ambiguous legacy
    -- funding RPC. C/D's replacement is exercised only after actual install.
    insert into public.wallet_accounts(id,user_id) values('${uid(41)}','${user}');
    insert into public.wallet_loads(id,wallet_account_id,user_id,amount_cents,paid_amount_cents,promo_amount_cents,stripe_payment_intent_id)
      values(50001,'${uid(41)}','${user}',2000,2000,500,'pi_cd_historical');
    insert into public.wallet_redemptions(id,wallet_account_id,user_id,machine_id,amount_cents,paid_amount_cents,promo_amount_cents)
      values(50001,'${uid(41)}','${user}',1,750,250,500);
    insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents,wallet_load_id,machine_id)
      values('${uid(41)}','load_paid',2000,2000,0,50001,null),
        ('${uid(41)}','load_bonus',500,0,500,50001,null),
        ('${uid(41)}','redeem_paid',-250,-250,0,null,1),
        ('${uid(41)}','redeem_bonus',-500,0,-500,null,1);
    update public.profiles set balance=17.5,reward_tracker=0 where id='${user}';
    insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,user_id,
      amount_cents,payment_method,channel,transaction_id,washer_size_rate_id,pulse_line_number)
      values('${vend}','${vend}','synthetic-only',1,'${user}',750,'wallet','app','${vend}',1,1);
    update public.cortina_vend_sessions set wallet_redemption_id=50001,status='started' where id='${vend}';
    insert into public.transactions(id,user_id,amount,type,description) values
      (100,'${user}',7.50,'laundry','Legacy eligible vend'),(101,'${user}',3,'laundry','Saved claimed vend');
    insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description) values(500,'${user}',101,3,'Historical claim');
    insert into public."Maintenance"(maint_id,user_id,description,location,image_data)
      values(1,'${user}','Historical report','Synthetic matched address','https://synthetic.invalid/storage/v1/object/public/images/original.png');
    grant insert on public.transactions,public."Refunds" to public,anon,authenticated;
    grant insert(amount) on public.transactions,public."Refunds" to anon,authenticated;
    grant select on public.transactions,public."Refunds",public."Maintenance" to authenticated;
    -- Hosted catalog921fdc grants authenticated SELECT on both wallet tables.
    grant select on public.wallet_accounts,public.wallet_loads to authenticated;
    create policy fixture_own_transaction on public.transactions for select to authenticated using(auth.uid()=user_id);
    create policy fixture_refund_read on public."Refunds" for select to authenticated using(true);
    create policy fixture_own_maintenance on public."Maintenance" for select to authenticated using(auth.uid()=user_id);
    grant usage,create on schema public to postgres; grant usage on schema auth to postgres;
    grant create on database loyalty_policy_fixture to postgres;
    grant select(id,email,created_at,is_anonymous,deleted_at,banned_until,email_confirmed_at),update(id),references(id),trigger
      on auth.users to postgres;
    grant select(id,user_id,aal,factor_id,not_after,created_at) on auth.sessions to postgres;
    grant select(id,user_id,factor_type,status,created_at) on auth.mfa_factors to postgres;
    reset role; alter role postgres nosuperuser bypassrls;`);
  const rows = async () => {
    const result = {};
    for (const table of ['auth.users','auth.sessions','auth.mfa_factors','public.profiles','public.wallet_accounts',
      'public.wallet_loads','public.wallet_redemptions','public.cortina_vend_sessions','public.transactions','public."Refunds"']) {
      result[table] = await db.query(`select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]') from ${table} r;`);
    }
    result.ledger = await db.query(`select jsonb_agg(to_jsonb(r)-'voluntary_topup_refund_id' order by id) from public.wallet_ledger_entries r;`);
    result.maintenance = await db.query(`select jsonb_agg(jsonb_build_array(maint_id,user_id,category,description,created_at,location,image_data) order by maint_id) from public."Maintenance";`);
    return result;
  };
  const catalog = () => db.query(`select jsonb_build_object(
    'relations',(select jsonb_agg(jsonb_build_array(c.oid,c.relname,c.relacl,c.relrowsecurity,c.relowner) order by c.oid)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','auth','private')),
    'functions',(select jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proacl) order by p.oid)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','auth','private') and p.prokind='f'),
    'policies',(select jsonb_agg(to_jsonb(p) order by oid) from pg_policy p),
    'triggers',(select jsonb_agg(jsonb_build_array(oid,tgname,tgenabled) order by oid) from pg_trigger where not tgisinternal));`);
  const counter = () => db.query(`select jsonb_build_array(oid,proowner,prosecdef,proconfig,proacl,pg_get_functiondef(oid))
    from pg_proc where oid='public.increment_user_refund_attempts(uuid)'::regprocedure;`);
  const initialRows = await rows(), initialCatalog = await catalog(), initialCounter = await counter();
  await t.test('recorded legacy prerequisites and installed A/B match the bounded rehearsal shape', async () => {
    const hosted = JSON.parse(await local('hosted-catalog.json')).rows[0].jsonb_build_object;
    for (const name of ['wallet_accounts','wallet_loads','wallet_ledger_entries','wallet_redemptions','wallet_balances']) {
      assert.equal(hosted.relations.find((r)=>r.name===`public.${name}`)?.exists,true,name);
    }
    for (const name of ['get_or_create_wallet_account','sync_profile_wallet_balance','record_wallet_load_from_stripe',
      'redeem_wallet_for_machine','redeem_wallet_for_cortina','admin_adjust_wallet','admin_record_legal_cash_redemption',
      'admin_set_wallet_status','reverse_cortina_wallet_redemption','resolve_refund_request','request_cortina_loyalty_credit']) {
      assert(hosted.functions.some((f)=>f.name===name && f.signature && f.owner==='postgres'),name);
    }
    assert.equal(await db.query("select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';"),'t');
    assert.equal(await db.query("select not prosecdef and proconfig=array['search_path=public'] from pg_proc where oid='public.increment_user_refund_attempts(uuid)'::regprocedure;"),'t');
    assert.equal(await db.query("select has_function_privilege('authenticated','public.request_account_deletion()','execute');"),'f');
    assert.equal(await db.query('select enabled=false and rollout_at is null from private.mail_settings;'),'t');
  });
  await t.test('missing direct counter prerequisite aborts every prior C/D change', async () => {
    const broken = artifact.replace('BEGIN;\n','BEGIN;\nALTER FUNCTION public.increment_user_refund_attempts(uuid) RENAME TO fixture_missing_counter;\n');
    await assert.rejects(run(`set role postgres; ${broken}`),fail('55000'));
    assert.equal(await catalog(),initialCatalog); assert.deepEqual(await rows(),initialRows);
  });
  await t.test('late failure after final containment checks rolls back the entire unit', async () => {
    const broken = artifact.replace(/COMMIT;\n$/,()=>"DO $$ BEGIN RAISE EXCEPTION 'synthetic C/D rollback' USING ERRCODE='P0001'; END $$;\nCOMMIT;\n");
    await assert.rejects(run(`set role postgres; ${broken}`),fail('P0001',/synthetic C\/D rollback/));
    assert.equal(await catalog(),initialCatalog); assert.deepEqual(await rows(),initialRows);
  });
  await t.test('mail enablement or deletion ACL drift cannot commit this artifact', async () => {
    for (const drift of ['UPDATE private.mail_settings SET enabled=true,rollout_at=clock_timestamp();',
      'GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;']) {
      const broken = artifact.replace('-- Preserve installed containment;',`${drift}\n-- Preserve installed containment;`);
      await assert.rejects(run(`set role postgres; ${broken}`),fail('55000',/deletion held and mail disabled/));
      assert.equal(await catalog(),initialCatalog); assert.deepEqual(await rows(),initialRows);
    }
  });
  // Required fixture setup also runs when QA filters already-accepted cases.
  await run(`set role postgres; ${artifact}`);
  if (process.env.CORTINA_ROLLOUT_REHEARSAL) {
    assert(isAbsolute(process.env.CORTINA_ROLLOUT_REHEARSAL));
    await t.test('Cortina four prerequisites preserve installed C/D and record one bound payment', async () => {
      const { rehearseCortinaAfterCd } = await import(pathToFileURL(process.env.CORTINA_ROLLOUT_REHEARSAL));
      await rehearseCortinaAfterCd({ db, run, rows, catalog, counter, read, artifact, user });
    });
    return;
  }
  await t.test('exact artifact commits under realistic nonsuperuser owner with installed A/B', async () => {
    assert.equal(await db.query("select to_regclass('private.customer_mfa_recovery') is not null and to_regclass('public.admin_audit_events') is not null;"),'t');
  });
  await t.test('financial history balances profile values and legacy address references remain unchanged', async () => {
    assert.deepEqual(await rows(),initialRows); assert.equal(await counter(),initialCounter);
    assert.equal(await db.query('select location_id is null from public."Maintenance" where maint_id=1;'),'t');
  });
  await t.test('canonical final grants retain human-only entrypoints and deny actor-taking/global wallet RPCs', async () => {
    for (const fn of ['public.admin_portal_request(text,jsonb)','public.admin_resolve_credit(bigint,text,text)',
      'public.customer_mfa_recovery_request(text,uuid,text,boolean,uuid)','public.request_legacy_loyalty_credit(bigint,text)',
      'public.request_cortina_loyalty_credit(bigint,text)']) {
      assert.equal(await db.query(`select has_function_privilege('authenticated',${q(fn)},'execute');`),'t',fn);
      assert.equal(await db.query(`select has_function_privilege('anon',${q(fn)},'execute');`),'f',fn);
    }
    for (const fn of ['public.admin_portal_data(uuid,text,jsonb)','public.admin_portal_bootstrap_owner(uuid,bigint[])',
      'public.admin_adjust_wallet(uuid,integer,integer,integer,text)','public.admin_set_wallet_status(uuid,text,text)']) {
      for (const role of ['anon','authenticated','service_role'])
        assert.equal(await db.query(`select has_function_privilege('${role}',${q(fn)},'execute');`),'f',`${role}:${fn}`);
    }
    assert.equal(await db.query("select reloptions @> array['security_invoker=true'] from pg_class where oid='public.wallet_balances'::regclass;"),'t');
    assert.equal(await db.query(`select count(*) from pg_policy where not polpermissive and polcmd='r'
      and polname in('wallet_accounts_home_admission','wallet_loads_home_admission',
        'wallet_ledger_home_admission','wallet_redemptions_home_admission');`),'4');
    assert.equal(await db.query(`select count(*) from pg_policy where not polpermissive and polcmd='r'
      and polname in('portal_transaction_scope','portal_maintenance_scope','portal_credit_scope');`),'3');
  });
  await t.test('direct financial INSERT is denied at table column inheritance and restrictive policy layers', async () => {
    for (const table of ['transactions','"Refunds"']) {
      for (const role of ['anon','authenticated']) assert.equal(await db.query(`select
        has_table_privilege('${role}','public.${table}','INSERT') or has_any_column_privilege('${role}','public.${table}','INSERT');`),'f');
      assert.equal(await db.query(`select has_table_privilege('service_role','public.${table}','INSERT');`),'t');
    }
    assert.equal(await db.query(`select count(*) from pg_policy where not polpermissive and polcmd='a'
      and polname in('transactions_server_insert_only','refunds_server_insert_only') and pg_get_expr(polwithcheck,polrelid)='false';`),'2');
    await assert.rejects(call(`insert into public.transactions(user_id,amount,type) values('${user}',999,'laundry')`),fail('42501'));
    await assert.rejects(call(`insert into public."Refunds"(user_id,transaction_id,amount) values('${user}',100,999)`),fail('42501'));
  });
  await t.test('no historical provenance audit mail or lifecycle records were generated and gates stay held', async () => {
    for (const table of ['private.topup_refund_provenance','private.topup_refund_spend','private.voluntary_topup_refunds',
      'public.admin_audit_events','public.admin_maintenance_history','private.mail_outbox','private.account_lifecycle'])
      assert.equal(await db.query(`select count(*) from ${table};`),'0',table);
    assert.equal(await db.query('select count(*)=1 and bool_and(not enabled and rollout_at is null and refund_notice_recipient is null) from private.mail_settings;'),'t');
    for (const role of ['anon','authenticated','service_role']) assert.equal(await db.query(`select has_function_privilege('${role}','public.request_account_deletion()','execute');`),'f');
    assert.equal(await db.query("select has_function_privilege('authenticated','public.restore_account()','execute');"),'t');
    assert.equal(await db.query('select enabled from private.new_payment_service_control;'),'t');
    assert.equal(await call('select public.mail_claim() is null',{},'service_role'),'t');
  });
  let claim;
  await t.test('legacy and Cortina definer claims use authoritative amounts with unchanged invoker counter', async () => {
    const payment = await db.query(`select id from public.transactions where cortina_vend_session_id='${vend}';`);
    claim = await json(`select public.request_cortina_loyalty_credit(${payment},'Synthetic machine issue')`);
    assert.equal(claim.amount,7.5); assert.equal(claim.status,'pending');
    assert.deepEqual(await json(`select public.request_cortina_loyalty_credit(${payment},'Retry')`),claim);
    assert.equal((await json("select public.request_legacy_loyalty_credit(100,'Synthetic legacy issue')")).amount,7.5);
    assert.equal(await db.query(`select refund_attempts from public.profiles where id='${user}';`),'4');
    assert.equal(await counter(),initialCounter);
    assert.equal(await db.query('select count(*) from private.mail_outbox;'),'0');
  });
  await t.test('canonical credit resolution and prospective notice coexist atomically while delivery remains off', async () => {
    assert(claim);
    const s = await cluster.connect();
    try {
      await s.query(`begin; update private.mail_settings set rollout_at=clock_timestamp()-interval '1 minute'; ${context(staff())}`);
      const receipt = JSON.parse(await s.query(`select public.admin_resolve_credit(${claim.refund_id},'approved','Synthetic review');`));
      assert.equal(receipt.notificationSent,false); assert.equal(receipt.notificationState,'ready');
      await s.query('reset role;');
      assert.equal(await s.query(`select count(*) from private.mail_outbox where kind='credit_decision' and credit_refund_id=${claim.refund_id};`),'1');
      assert.equal(await s.query(`select paid_amount_cents=0 and promo_amount_cents=750 from public.wallet_ledger_entries where refund_request_id=${claim.refund_id};`),'t');
      assert.equal(await s.query('select enabled from private.mail_settings;'),'f');
      await s.query(`${context(staff())} select public.admin_resolve_credit(${claim.refund_id},'approved','Retry'); reset role;`);
      assert.equal(await s.query(`select count(*) from private.mail_outbox where kind='credit_decision' and credit_refund_id=${claim.refund_id};`),'1');
      await s.query('rollback;');
    } finally { await s.close(); }
    assert.equal(await db.query('select count(*) from private.mail_outbox;'),'0');
    assert.equal(await db.query(`select status::text from public."Refunds" where refund_id=${claim.refund_id};`),'pending');
  });
  await t.test('pending-account installed wallet settlement and dedicated voluntary refund retain trusted exceptions', async () => {
    const s = await cluster.connect();
    try {
      await s.query(`begin; insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
        values('${user}',now(),now()+interval '720 hours'); ${context({},'service_role')}`);
      const funding = `select public.record_wallet_load_from_stripe('${user}',2000,'pi_cd_late')`;
      const first = await s.query(`${funding};`); assert.equal(await s.query(`${funding};`),first);
      assert.equal(await s.query(`select public.record_topup_refund_provenance('pi_cd_late','${user}',2000,clock_timestamp(),'evt_cd_late',false,null);`),'t');
      // C/D preserves these installed service writers. Frozen Cortina card
      // recording is a separate rollout prerequisite, absent from this stage.
      await s.query(`insert into public.transactions(id,user_id,amount,type,description)
          values(50002,'${user}',3,'laundry','Trusted synthetic saved history');
        insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description)
          values(50002,'${user}',50002,3,'Trusted synthetic saved claim'); reset role;`);
      assert.equal(await s.query('select count(*) from public.transactions where id=50002;'),'1');
      assert.equal(await s.query('select count(*) from public."Refunds" where refund_id=50002;'),'1');
      const load = await s.query("select id from public.wallet_loads where stripe_payment_intent_id='pi_cd_late';");
      await s.query(context());
      const refund = JSON.parse(await s.query(`select public.request_voluntary_topup_refund(${load});`));
      assert.equal(refund.principal_cents,2000);
      await s.query(`${context(staff())} select public.review_voluntary_topup_refund('${refund.id}','approve');
        ${context({},'service_role')} select public.prepare_voluntary_topup_refund('${refund.id}');`);
      const settled = JSON.parse(await s.query(`select public.reconcile_voluntary_topup_refund('${refund.id}','re_cd_late','succeeded','pi_cd_late',2000,'usd',false);`));
      assert.equal(settled.status,'succeeded'); await s.query('rollback;');
    } finally { await s.close(); }
  });
  await t.test('pending customer SELECT and new human claims are denied without changing saved records', async () => {
    const saved = await rows();
    for (const table of ['wallet_accounts','wallet_loads'])
      assert(Number(await call(`select count(*) from public.${table}`))>0,`${table}: eligible read precedes lifecycle denial`);
    await db.query(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
      values('${user}',now(),now()+interval '720 hours');`);
    for (const table of ['transactions','"Refunds"','"Maintenance"','wallet_accounts','wallet_loads'])
      assert.equal(await call(`select count(*) from public.${table}`),'0',table);
    await assert.rejects(call("select public.request_legacy_loyalty_credit(100,'Replay')"),fail('PT403'));
    await assert.rejects(call('select public.admin_portal_request(\'dashboard\')',claims({sub:owner,session_id:ownerSid,aal:'aal1'})),fail('PT403'));
    await db.query(`delete from private.account_lifecycle where user_id='${user}';`);
    assert.deepEqual(await rows(),saved);
    assert.equal(await db.query('select count(*) from private.mail_outbox;'),'0');
  });
});
