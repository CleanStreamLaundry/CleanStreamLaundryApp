import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11);
const q = value => value == null ? 'null' : `'${String(value).replaceAll("'", "''")}'`;
const hash = 'a'.repeat(64), unsub = 'b'.repeat(64), payload = 'c'.repeat(64);
const jwt = (extra = {}) => ({sub:user,session_id:sid,role:'authenticated',aal:'aal1',exp:Math.floor(Date.now()/1000)+3600,...extra});
const context = (claims = jwt(), role = 'authenticated') => `set local role ${role};set local request.jwt.claims=${q(JSON.stringify(claims))};set local request.jwt.claim.sub='';`;
const request = "select public.newsletter_request(true,'newsletter-v1','signup')";

test('newsletter and outbox PostgreSQL integration', { timeout:180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  const run = async sql => { const c = await cluster.connect(); try { return await c.query(sql); } finally { await c.close(); } };
  const call = async (sql, claims = jwt(), role = 'authenticated') => {
    const value = await run(`begin;${context(claims,role)}${sql};commit;`);
    if (value === 't' || value === 'f') return value === 't';
    return JSON.parse(value || 'null');
  };
  const service = sql => call(sql, {}, 'service_role');
  const denied = (sql, code = 'PT403', claims = jwt(), role = 'authenticated') => assert.rejects(
    run(`begin;${context(claims,role)}${sql};commit;`), error => { assert.equal(error.code,code,error.message); return true; });
  for (const path of [
    '../supabase/tests/loyalty_policy_acceptance.fixture.sql',
    '../supabase/migrations/20260929223124_protect_profile_authority.sql',
    '../supabase/migrations/20260929234955_loyalty_policy_acceptance.sql',
    '../supabase/tests/account_admission.fixture.sql',
    '../supabase/migrations/20260930005456_account_admission.sql',
    '../supabase/tests/profile_terms_admission.fixture.sql',
    '../supabase/migrations/20260930013417_enforce_profile_terms_admission.sql',
    '../supabase/tests/account_lifecycle.fixture.sql',
    '../supabase/migrations/20260930063923_recoverable_account_deletion.sql',
    '../supabase/tests/newsletter.fixture.sql',
  ]) await db.query(await read(path));
  const before = await db.query(`select jsonb_agg(jsonb_build_array(oid::regclass::text,relacl) order by oid) from pg_class
    where relnamespace in ('auth'::regnamespace,'public'::regnamespace) and relkind='r';`);
  await db.query(await read('../supabase/migrations/20260930125527_newsletter_consent_mail_outbox.sql'));
  const postalPreserved = () => db.query(`select jsonb_build_object(
    'settings',(select jsonb_agg(to_jsonb(s)) from private.mail_settings s),
    'outbox',(select jsonb_agg(to_jsonb(o) order by id) from private.mail_outbox o),
    'functions',(select jsonb_agg(jsonb_build_array(oid,pg_get_functiondef(oid),proacl) order by oid)
      from pg_proc where pronamespace in ('private'::regnamespace,'public'::regnamespace)
      and not (pronamespace='public'::regnamespace and proname='mail_claim')),
    'triggers',(select jsonb_agg(jsonb_build_array(oid,pg_get_triggerdef(oid)) order by oid)
      from pg_trigger where not tgisinternal))`);
  const postalBefore = await postalPreserved();
  await db.query(await read('../supabase/migrations/20261001140307_mail_transactional_postal_split.sql'));
  await t.test('postal migration changes no helper, trigger, setting or queued data', async () => {
    assert.equal(await postalPreserved(), postalBefore);
  });
  if (process.env.MAIL_ADVISORS_BIN) {
    const url = `postgresql:///loyalty_policy_fixture?host=${encodeURIComponent(cluster.socket)}&user=policy_fixture&port=55432&sslmode=disable`;
    try {
      const {stdout,stderr} = await promisify(execFile)(process.env.MAIL_ADVISORS_BIN,
        ['db','advisors','--db-url',url,'--type','security','--level','warn'],
        {env:cluster.env,cwd:cluster.root,timeout:30000});
      t.diagnostic(`Local CLI advisors: ${stdout} ${stderr}`);
    } catch (error) {
      t.diagnostic(`CLI advisor unavailable on synthetic fixture (not a pass): ${error.stderr || error.message}`);
    }
  }
  await t.test('migration preserves existing table grants and defaults to disabled', async () => {
    assert.equal(await db.query(`select jsonb_agg(jsonb_build_array(oid::regclass::text,relacl) order by oid) from pg_class
      where relnamespace in ('auth'::regnamespace,'public'::regnamespace) and relkind='r';`),before);
    assert.equal(await db.query('select enabled from private.mail_settings'), 'f');
    assert.equal(await service('select public.mail_claim()'),null);
  });
  const reset = () => db.query(`truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,private.mail_suppression,private.account_lifecycle;
    truncate auth.users cascade;
    update private.mail_settings set enabled=false,rollout_at=clock_timestamp()-interval '1 hour';
    insert into auth.users(id,email,email_confirmed_at,created_at) values
      ('${user}','member@example.test',now(),now()-interval '1 day'),('${other}','other@example.test',now(),now()-interval '1 day');
    insert into auth.sessions(id,user_id,aal,created_at) values ('${sid}','${user}','aal1',now()-interval '1 hour'),('${uid(12)}','${other}','aal1',now()-interval '1 hour');
    update private.mail_settings set enabled=true;`);
  const fresh = (name,fn) => t.test(name, async () => { await reset(); await fn(); });
  const row = async () => JSON.parse(await db.query('select to_jsonb(c) from private.newsletter_consent c order by requested_at desc limit 1') || 'null');
  const jobs = async () => JSON.parse(await db.query("select coalesce(jsonb_agg(to_jsonb(o) order by created_at),'[]') from private.mail_outbox o"));
  const claim = () => service('select public.mail_claim()');
  const prepare = o => service(`select public.mail_prepare('${o.id}','${o.lease_id}','${payload}','${hash}','${unsub}')`);
  const finish = (o,result,id=null) => service(`select public.mail_finish('${o.id}','${o.lease_id}',${q(result)},${q(id)})`);
  const confirm = () => service(`select public.newsletter_token('confirm','${hash}')`);
  const unsubscribe = () => service(`select public.newsletter_token('unsubscribe','${unsub}')`);
  const webhook = (o,type,event='event-1',id='provider-1') => service(`select public.mail_record_webhook(${q(event)},${q(id)},${q(type)},'${o.id}',${q(o.email)})`);
  const sending = async () => { await call(request); const o=await claim(); assert.equal(await prepare(o),true); return o; };

await t.test('postal split has one defaulted service-only signature', async () => {
  const signatures = JSON.parse(await db.query(`select jsonb_agg(jsonb_build_object(
    'args',pg_get_function_identity_arguments(oid),'defaults',pronargdefaults,
    'definer',prosecdef,'config',proconfig)) from pg_proc
    where pronamespace='public'::regnamespace and proname='mail_claim'`));
  assert.equal(signatures.length, 1);
  assert.equal(signatures[0].args, 'p_include_newsletter boolean');
  assert.equal(signatures[0].defaults, 1);
  assert.equal(signatures[0].definer, true);
  assert.ok(signatures[0].config.includes('search_path=""'));
  assert.equal(await db.query(`select exists(select 1 from pg_proc p,
    lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid='public.mail_claim(boolean)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE')`), 'f');
  for (const role of ['anon','authenticated','supabase_auth_admin']) {
    assert.equal(await db.query(`select has_function_privilege('${role}','public.mail_claim(boolean)','EXECUTE')`), 'f');
    for (const args of ['', 'true', 'false', 'null', 'p_include_newsletter => false'])
      await denied(`select public.mail_claim(${args})`, '42501', {}, role);
  }
  assert.equal(await db.query("select has_function_privilege('service_role','public.mail_claim(boolean)','EXECUTE')"), 't');
});

const postalQueue = async (kind) => {
  await call(request);
  if (kind === 'newsletter_welcome') {
    const sent = await claim();
    assert.equal(await prepare(sent), true);
    await finish(sent, 'accepted', 'postal-synthetic-provider');
    assert.equal((await confirm()).state, 'subscribed');
  }
  await db.query(`update private.mail_outbox set created_at=clock_timestamp()-interval '10 minutes'
    where state='ready';`);
  return (await jobs()).find(o => o.state === 'ready');
};
for (const kind of ['newsletter_confirm','newsletter_welcome']) {
  for (const include of ['false','null']) {
    await fresh(`postal split ${include}: ${kind} never starves transactional ordering`, async () => {
      const newsletter = await postalQueue(kind);
      await db.query(`insert into private.mail_outbox(id,event_key,kind,user_id,email,created_at) values
        ('${uid(43)}','postal/late','account_welcome','${user}','member@example.test',now()-interval '1 minute'),
        ('${uid(42)}','postal/second','account_welcome','${user}','member@example.test',now()-interval '2 minutes'),
        ('${uid(41)}','postal/first','account_welcome','${user}','member@example.test',now()-interval '2 minutes')`);
      for (const id of [uid(41),uid(42),uid(43)]) {
        const leased = await service(`select public.mail_claim(${include})`);
        assert.equal(leased.id, id);
        assert.equal(leased.kind, 'account_welcome');
        assert.equal(leased.state, 'leased');
        assert.ok(leased.lease_id);
        const seconds = Number(await db.query(`select extract(epoch from lease_until-clock_timestamp())
          from private.mail_outbox where id='${id}'`));
        assert.ok(seconds > 110 && seconds <= 120);
        assert.deepEqual((await jobs()).find(o => o.id === newsletter.id), newsletter);
      }
      assert.equal(await service(`select public.mail_claim(${include})`), null);
      assert.deepEqual((await jobs()).find(o => o.id === newsletter.id), newsletter);
      assert.equal((await claim()).id, newsletter.id);
    });
    await fresh(`postal split ${include}: ${kind}-only queue remains ready`, async () => {
      const newsletter = await postalQueue(kind);
      assert.equal(await service(`select public.mail_claim(${include})`), null);
      assert.deepEqual((await jobs()).find(o => o.id === newsletter.id), newsletter);
    });
  }
  for (const args of ['', 'true', 'p_include_newsletter => true']) {
    await fresh(`postal split ${kind}: omitted/true ${args} keeps oldest-first`, async () => {
      const newsletter = await postalQueue(kind);
      await db.query(`insert into private.mail_outbox(event_key,kind,user_id,email)
        values('postal/account','account_welcome','${user}','member@example.test')`);
      assert.equal((await service(`select public.mail_claim(${args})`)).id, newsletter.id);
    });
  }
}
await fresh('postal split disabled guard makes no lease or maintenance changes', async () => {
  await postalQueue('newsletter_confirm');
  await db.query('update private.mail_settings set enabled=false');
  const before = await jobs();
  for (const args of ['', 'true', 'false', 'null']) assert.equal(await service(`select public.mail_claim(${args})`), null);
  assert.deepEqual(await jobs(), before);
});
await fresh('postal split still maintains excluded newsletter leases, uncertainty and suppression', async () => {
  const newsletter = await postalQueue('newsletter_confirm');
  const leased = await claim();
  await db.query("update private.mail_outbox set lease_until=clock_timestamp()-interval '1 second'");
  assert.equal(await service('select public.mail_claim(false)'), null);
  assert.equal((await jobs())[0].state, 'ready');
  const retry = await claim();
  assert.notEqual(retry.lease_id, leased.lease_id);
  assert.equal(await prepare(retry), true);
  await db.query("update private.mail_outbox set lease_until=clock_timestamp()-interval '1 second'");
  assert.equal(await service('select public.mail_claim(false)'), null);
  assert.equal((await jobs()).find(o => o.id === newsletter.id).state, 'uncertain');
});
await fresh('postal split still suppresses withdrawn newsletter before filtering', async () => {
  await postalQueue('newsletter_confirm');
  await db.query('update private.newsletter_consent set unsubscribed_at=clock_timestamp()');
  assert.equal(await service('select public.mail_claim(false)'), null);
  assert.equal((await jobs())[0].state, 'suppressed');
  assert.equal((await jobs())[0].last_error, 'suppressed_or_stale');
});
await fresh('postal split still exhausts excluded newsletter attempts', async () => {
  await postalQueue('newsletter_confirm');
  await db.query('update private.mail_outbox set attempts=5');
  assert.equal(await service('select public.mail_claim(false)'), null);
  assert.equal((await jobs())[0].state, 'failed');
  assert.equal((await jobs())[0].last_error, 'retry_exhausted');
});
await fresh('postal split concurrent false claims wait for mail lock and lease distinct eligible jobs', async () => {
  const newsletter = await postalQueue('newsletter_confirm');
  await db.query(`insert into private.mail_outbox(id,event_key,kind,user_id,email,created_at) values
    ('${uid(41)}','postal/first','account_welcome','${user}','member@example.test',now()),
    ('${uid(42)}','postal/second','account_welcome','${user}','member@example.test',now())`);
  const holder = await cluster.connect(), waiter = await cluster.connect();
  try {
    const first = JSON.parse(await holder.query('begin;set local role service_role;select public.mail_claim(false)'));
    const pending = waiter.query('begin;set local role service_role;select public.mail_claim(false);commit;')
      .then(value => ({ value }), error => ({ error }));
    await blocked(db, waiter, holder);
    await holder.query('commit');
    const result = await pending;
    assert.ifError(result.error);
    assert.equal(first.id, uid(41));
    assert.equal(JSON.parse(result.value).id, uid(42));
    assert.deepEqual((await jobs()).find(o => o.id === newsletter.id), newsletter);
  } finally { await holder.close(); await waiter.close(); }
});

  await fresh('unchecked request never creates consent or welcome; terms are separate', async () => {
    assert.equal((await call("select public.newsletter_request(false,'newsletter-v1','signup')")).state,'not_subscribed');
    assert.equal(await row(),null); assert.deepEqual(await jobs(),[]);
    assert.equal(await db.query(`select loyalty_policy_accepted_at is null from public.profiles where id='${user}'`),'t');
  });
  await fresh('existing verified users and old unverified accounts are never welcomed/enrolled', async () => {
    await db.query(`update auth.users set email_confirmed_at=null;update auth.users set email_confirmed_at=now();`);
    assert.deepEqual(await jobs(),[]); assert.equal(await row(),null);
  });
  for (const social of [false,true]) await fresh(`new verified account welcome once; social=${social}`, async () => {
    await db.query(`insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values('${uid(3)}','new@example.test',${social?'now()':'null'},${q(JSON.stringify({provider:social?'google':'email'}))}::jsonb)`);
    assert.equal((await jobs()).length,social?1:0);
    await db.query(`update auth.users set email_confirmed_at=now() where id='${uid(3)}';update auth.users set email_confirmed_at=now() where id='${uid(3)}';`);
    const o=(await jobs())[0];assert.equal(o.kind,'account_welcome');assert.equal((await jobs()).length,1);assert.equal(await row(),null);
    await db.query(`update auth.users set email='new-address@example.test',email_confirmed_at=now() where id='${uid(3)}'`);
    assert.equal((await jobs()).length,1);assert.equal(await claim(),null);
  });
  await fresh('runtime disabled excludes creations and request', async () => {
    await db.query('update private.mail_settings set enabled=false');
    await denied(request,'PT503');
    await db.query(`insert into auth.users(id,email,email_confirmed_at) values('${uid(3)}','new@example.test',now())`);
    assert.deepEqual(await jobs(),[]);
  });
  await fresh('Auth owner can capture verified signup without direct private table access',async()=>{
    await run(`begin;set local role supabase_auth_admin;insert into auth.users(id,email,email_confirmed_at) values('${uid(3)}','new@example.test',now());commit;`);
    assert.equal((await jobs()).length,1);assert.equal((await jobs())[0].kind,'account_welcome');
  });
  await fresh('request stores purpose version text source server times and only confirmation outbox', async () => {
    assert.equal((await call(request)).state,'pending'); const c=await row();
    assert.equal(c.version,'newsletter-v1'); assert.equal(c.source,'signup');assert.equal(c.purpose,'newsletter');
    assert.match(c.consent_text,/unsubscribe/);assert.equal(c.confirm_hash,null);assert.equal(c.confirmed_at,null);
    assert.equal(Date.parse(c.expires_at)-Date.parse(c.requested_at),86400000);
    assert.equal((await jobs())[0].kind,'newsletter_confirm');
  });
  for (const [version,source] of [['old','signup'],['newsletter-v1','terms'],[null,'settings'],['newsletter-v1',null]]) {
    await fresh(`invalid version/source ${version}/${source}`,()=>denied(`select public.newsletter_request(true,${q(version)},${q(source)})`,'PT400'));
  }
  for (const extra of [{session_id:uid(12)},{session_id:uid(99)},{exp:1},{role:'service_role'},{aal:'aal3'}]) {
    await fresh(`live session boundary ${JSON.stringify(extra)}`,()=>denied(request,'PT401',jwt(extra)));
  }
  for (const change of ['email_confirmed_at=null','is_anonymous=true',"banned_until=now()+interval '1 hour'",'deleted_at=now()']) {
    await fresh(`restricted identity ${change}`,async()=>{await db.query(`update auth.users set ${change} where id='${user}'`);await denied(request);});
  }
  await fresh('MFA policy is inherited, not inferred from metadata', async () => {
    await db.query(`update public.profiles set roles='Admin' where id='${user}';update auth.users set raw_user_meta_data='{"aal":"aal2","consent":true}' where id='${user}'`);
    await denied(request);assert.equal(await row(),null);
  });
  await fresh('other user status does not disclose target consent',async()=>{
    await call(request);assert.equal((await call('select public.newsletter_status()',jwt({sub:other,session_id:uid(12)}))).state,'not_subscribed');
  });
  await fresh('minute and daily request/resend bounds',async()=>{
    await call(request);await denied(request,'PT429');
    for(let i=0;i<2;i++){await db.query("update private.newsletter_consent set requested_at=requested_at-interval '2 minutes'");await call(request);}
    await db.query("update private.newsletter_consent set requested_at=requested_at-interval '2 minutes'");await denied(request,'PT429');
    assert.equal((await jobs()).length,3);
  });
  await fresh('confirmed once; replay fails; subscribed request does not resend',async()=>{
    const o=await sending();assert.equal((await row()).confirm_hash,hash);await finish(o,'accepted','provider-1');
    assert.equal((await confirm()).state,'subscribed');assert.equal((await row()).confirm_hash,null);
    await denied(`select public.newsletter_token('confirm','${hash}')`,'PT400',{},'service_role');
    await call(request);assert.equal((await jobs()).filter(o=>o.kind==='newsletter_welcome').length,1);
  });
  await fresh('expiry and superseded requests cannot confirm',async()=>{
    await sending();await db.query("update private.newsletter_consent set expires_at=clock_timestamp()");
    await denied(`select public.newsletter_token('confirm','${hash}')`,'PT400',{},'service_role');
    await db.query("update private.newsletter_consent set requested_at=requested_at-interval '2 minutes'");await call(request);
    await denied(`select public.newsletter_token('confirm','${hash}')`,'PT400',{},'service_role');
  });
  await fresh('unsubscribe idempotent; cancels queued newsletter welcome, not account mail',async()=>{
    const o=await sending();await finish(o,'accepted','provider-1');await confirm();await unsubscribe();await unsubscribe();
    assert.equal((await call('select public.newsletter_status()')).state,'unsubscribed');assert.equal(await claim(),null);
    assert.equal((await jobs()).find(o=>o.kind==='newsletter_welcome').state,'suppressed');
    await db.query(`insert into private.mail_outbox(event_key,kind,user_id,email) values('test/account','account_welcome','${user}','member@example.test')`);
    assert.equal((await claim()).kind,'account_welcome');
  });
  await fresh('unsubscribe wins between claim and prepare',async()=>{
    const o=await sending();await finish(o,'accepted','provider-1');await confirm();const welcome=await claim();
    await unsubscribe();assert.equal(await prepare(welcome),false);assert.equal(await claim(),null);
  });
  await fresh('caller-bound settings withdrawal is idempotent and does not touch another user',async()=>{
    await sending();await confirm();
    assert.equal((await call('select public.newsletter_withdraw()',jwt({sub:other,session_id:uid(12)}))).state,'not_subscribed');
    assert.equal((await row()).unsubscribed_at,null);
    assert.equal((await call('select public.newsletter_withdraw()')).state,'unsubscribed');
    const before=await row();await call('select public.newsletter_withdraw()');assert.deepEqual(await row(),before);assert.equal(await claim(),null);
  });
  await fresh('token key rotation fails closed rather than sending unusable unsubscribe link',async()=>{
    const o=await sending();await finish(o,'accepted','provider-1');await confirm();const welcome=await claim();
    assert.equal(await service(`select public.mail_prepare('${welcome.id}','${welcome.lease_id}','${payload}',null,'${'e'.repeat(64)}')`),false);
    assert.equal((await jobs()).find(o=>o.kind==='newsletter_welcome').last_error,'token_key_changed');
    assert.equal((await unsubscribe()).state,'unsubscribed');
  });
  await fresh('explicit resubscribe requires fresh confirmation and old unsubscribe link still wins',async()=>{
    const o=await sending();await finish(o,'accepted','provider-1');await confirm();await unsubscribe();
    await db.query("update private.newsletter_consent set requested_at=requested_at-interval '2 minutes'");await call(request);
    assert.equal((await row()).confirmed_at,null);assert.equal((await call('select public.newsletter_status()')).state,'pending');
    await unsubscribe();assert.equal((await row()).unsubscribed_at!==null,true);assert.equal(await claim(),null);
  });
  await fresh('email change permanently invalidates consent even if address changes back',async()=>{
    await sending();await confirm();await db.query(`update auth.users set email='changed@example.test' where id='${user}';update auth.users set email='member@example.test' where id='${user}'`);
    assert.equal((await call('select public.newsletter_status()')).state,'unsubscribed');assert.equal(await claim(),null);
  });
  await fresh('deletion suppresses atomically; fresh restore never reenrolls or welcomes',async()=>{
    await sending();await confirm();
    await call('select public.request_account_deletion()');assert.equal((await row()).suppression_reason,'account_deletion');assert.equal(await claim(),null);
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values('${uid(13)}','${user}','aal1',clock_timestamp())`);
    await call('select public.restore_account()',jwt({session_id:uid(13)}));
    assert.equal((await call('select public.newsletter_status()',jwt({session_id:uid(13)}))).state,'suppressed');
    await denied(request,'PT403',jwt({session_id:uid(13)}));assert.equal((await jobs()).length,2);
  });
  await fresh('leases are exclusive; stale lease cannot prepare; pre-send crash is reclaimable',async()=>{
    await call(request);const o=await claim();assert.equal(await claim(),null);
    await db.query("update private.mail_outbox set lease_until=now()-interval '1 minute'");
    const next=await claim();assert.notEqual(next.lease_id,o.lease_id);assert.equal(await prepare(o),false);assert.equal(await prepare(next),true);
  });
  await fresh('crash after prepare is uncertain and never blindly reclaimed',async()=>{
    await sending();await db.query("update private.mail_outbox set lease_until=now()-interval '1 minute'");
    assert.equal(await claim(),null);assert.equal((await jobs())[0].state,'uncertain');assert.equal(await claim(),null);
  });
  await fresh('explicit rate rejection bounded backoff and retry exhaustion',async()=>{
    const first=await sending();await finish(first,'rate_limited');assert.equal(await claim(),null);
    for(let i=1;i<5;i++){await db.query("update private.mail_outbox set next_at=now()-interval '1 second'");const o=await claim();assert.equal(await prepare(o),true);await finish(o,'rate_limited');}
    assert.equal((await jobs())[0].state,'failed');assert.equal((await jobs())[0].attempts,5);
  });
  await fresh('payload/config change cannot alter retry under same key',async()=>{
    const o=await sending();await finish(o,'rate_limited');await db.query("update private.mail_outbox set next_at=now()-interval '1 second'");
    const retry=await claim();assert.equal(await service(`select public.mail_prepare('${retry.id}','${retry.lease_id}','${'d'.repeat(64)}','${hash}','${unsub}')`),false);
    assert.equal((await jobs())[0].last_error,'payload_changed');
  });
  await fresh('provider idempotency window is never used as permanent dedupe',async()=>{
    const o=await sending();await finish(o,'rate_limited');await db.query("update private.mail_outbox set first_attempt_at=now()-interval '24 hours',next_at=now()-interval '1 second'");
    assert.equal(await claim(),null);assert.equal((await jobs())[0].state,'failed');
  });
  for(const type of ['email.bounced','email.complained','email.suppressed'])await fresh(`${type} suppresses all mail despite late sent/delivered`,async()=>{
    const o=await sending();await webhook(o,type);await webhook(o,type);await webhook(o,'email.delivered','event-2');await webhook(o,'email.sent','event-3');await finish(o,'accepted','provider-1');
    assert.equal((await jobs())[0].state,'suppressed');assert.equal(await db.query('select count(*) from private.mail_suppression'),'1');
    await denied(request);assert.equal(await claim(),null);assert.equal(await db.query('select count(*) from private.mail_webhook_event'),'3');
  });
  await fresh('webhook reconciles unknown outcome before/after timeout; out-of-order delivery monotonic',async()=>{
    const o=await sending();await finish(o,'uncertain');await webhook(o,'email.delivered');await webhook(o,'email.sent','event-2');
    await finish(o,'accepted','provider-1');assert.equal((await jobs())[0].state,'delivered');assert.equal((await jobs())[0].provider_id,'provider-1');assert.equal(await claim(),null);
  });
  await fresh('unmatched webhook retries without persisting receipt',async()=>{
    await denied(`select public.mail_record_webhook('unknown','unknown','email.sent','${uid(99)}','member@example.test')`,'PT503',{},'service_role');
    assert.equal(await db.query('select count(*) from private.mail_webhook_event'),'0');
  });
  await fresh('all private email tables have RLS and no client/service direct privileges',async()=>{
    for(const table of ['mail_settings','mail_outbox','mail_suppression','mail_webhook_event','newsletter_consent']){
      assert.equal(await db.query(`select relrowsecurity from pg_class where oid='private.${table}'::regclass`),'t');
      for(const role of ['anon','authenticated','service_role']) for(const permission of ['select','insert','update','delete','truncate'])
        assert.equal(await db.query(`select has_table_privilege('${role}','private.${table}','${permission}')`),'f');
    }
  });
  await fresh('internal RPC allowlist excludes PUBLIC/anon/auth users/Auth owner',async()=>{
    const functions=JSON.parse(await db.query(`select jsonb_agg(oid::regprocedure::text) from pg_proc where pronamespace='public'::regnamespace and proname in ('mail_claim','mail_prepare','mail_finish','mail_record_webhook','newsletter_token')`));
    for(const f of functions)for(const role of ['anon','authenticated','supabase_auth_admin'])assert.equal(await db.query(`select has_function_privilege('${role}',${q(f)},'execute')`),'f');
    await denied('select public.mail_claim()','42501');await denied(request,'42501',{},'anon');await denied(request,'42501',{},'service_role');
  });
  await fresh('concurrent explicit requests serialize and produce one confirmation',async()=>{
    const holder=await cluster.connect(),waiter=await cluster.connect();
    await holder.query(`begin;${context()}${request};`);
    const waiting=waiter.query(`begin;${context()}${request};commit;`);
    const caught=waiting.catch(error=>error);await blocked(db,waiter,holder);await holder.query('commit');
    assert.equal((await caught).code,'PT429');assert.equal((await jobs()).length,1);
  });
  await fresh('deletion commit wins over blocked request',async()=>{
    const holder=await cluster.connect(),waiter=await cluster.connect();
    await holder.query(`begin;${context()}select public.request_account_deletion();`);
    const caught=waiter.query(`begin;${context()}${request};commit;`).catch(error=>error);
    await blocked(db,waiter,holder);await holder.query('commit');assert.equal((await caught).code,'PT403');assert.equal(await row(),null);
  });
  await fresh('deletion wins against confirmation waiting on email lock',async()=>{
    await sending();const holder=await cluster.connect(),waiter=await cluster.connect();
    await holder.query(`begin;${context()}select public.request_account_deletion();`);
    const caught=waiter.query(`begin;set local role service_role;select public.newsletter_token('confirm','${hash}');commit;`).catch(error=>error);
    await blocked(db,waiter,holder);await holder.query('commit');assert.equal((await caught).code,'PT400');
    assert.equal((await jobs()).filter(o=>o.kind==='newsletter_welcome').length,0);
  });
  await fresh('session expiry is rechecked after email lock wait',async()=>{
    const holder=await cluster.connect(),waiter=await cluster.connect();
    await holder.query('begin;select private.mail_lock();');
    const caught=waiter.query(`begin;${context()}${request};commit;`).catch(error=>error);
    await blocked(db,waiter,holder);await db.query(`update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='${sid}'`);
    await holder.query('commit');assert.equal((await caught).code,'PT401');assert.equal(await row(),null);
  });
  await fresh('deletion wins against leased send waiting on email lock',async()=>{
    const sent=await sending();await finish(sent,'accepted','provider-1');await confirm();const welcome=await claim();
    const holder=await cluster.connect(),waiter=await cluster.connect();
    await holder.query(`begin;${context()}select public.request_account_deletion();`);
    const waiting=waiter.query(`begin;set local role service_role;select public.mail_prepare('${welcome.id}','${welcome.lease_id}','${payload}',null,'${unsub}');commit;`);
    await blocked(db,waiter,holder);await holder.query('commit');assert.equal(await waiting,'f');
    assert.equal((await jobs()).find(o=>o.kind==='newsletter_welcome').state,'suppressed');
  });
  await fresh('email flow does not mutate financial/business rows',async()=>{
    await db.query(`insert into public.wallet_accounts values('${uid(31)}','${user}',4200,now());insert into public."Refunds" values('${uid(32)}','${user}','pending',now(),null)`);
    const snapshot=()=>db.query(`select jsonb_build_array((select jsonb_agg(to_jsonb(w)) from public.wallet_accounts w),(select jsonb_agg(to_jsonb(r)) from public."Refunds" r),(select jsonb_agg(to_jsonb(p)) from public.profiles p))`);
    const initial=await snapshot();const o=await sending();await finish(o,'uncertain');await webhook(o,'email.sent');await confirm();await unsubscribe();assert.equal(await snapshot(),initial);
  });
});
