import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster } from './test-support/policy-admission-pg.mjs';
import { installMachineIssueFixture } from './test-support/machine-issue-fixture.mjs';

const read = path => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = uid(1), customer = uid(3), session = uid(11), factor = uid(21), customerSession = uid(13);
const q = value => `'${String(value).replaceAll("'", "''")}'`;

test('automatic resolution mail uses actual financial and outbox migrations', { timeout: 180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN), db = await cluster.connect();
  const migrate = async name => db.query(await read(`supabase/migrations/${name}.sql`));
  await installMachineIssueFixture(db);
  await db.query("set timezone='UTC';alter table auth.users add column if not exists created_at timestamptz default now();");
  const definitions = () => db.query(`select jsonb_agg(jsonb_build_array(oid,pg_get_functiondef(oid),proacl) order by oid)
    from pg_proc where proname in ('resolve_refund_request','admin_resolve_credit','portal_staff_context',
      'review_voluntary_topup_refund','reconcile_voluntary_topup_refund','prepare_voluntary_topup_refund',
      'admin_machine_issue','machine_issue_vend_outcome',
      'mail_claim','mail_prepare','mail_finish','mail_record_webhook','mail_lifecycle_suppression')`);
  const before = await definitions();
  await migrate('20261005135252_automatic_resolution_mail_outbox');
  const run = async sql => { const c = await cluster.connect(); try { return await c.query(`set timezone='UTC';${sql}`); } finally { await c.close(); } };
  const context = who => `set local request.jwt.claim.sub='';set local role authenticated;
    set local request.jwt.claims=${q(JSON.stringify({ sub: who, session_id: who === owner ? session : customerSession,
      role: 'authenticated', aal: who === owner ? 'aal2' : 'aal1', exp: Math.floor(Date.now()/1000)+3600 }))};`;
  const call = (sql, who = customer) => run(`begin;${context(who)}${sql};commit;`).then(value => JSON.parse(value || 'null'));
  const jobs = () => db.query("select coalesce(jsonb_agg(to_jsonb(o) order by created_at,id),'[]') from private.mail_outbox o").then(JSON.parse);
  const service = sql => run(`begin;set local role service_role;${sql};commit;`).then(value => value === 't' ? true : value === 'f' ? false : JSON.parse(value || 'null'));
  const claim = () => service('select public.mail_claim(false)');
  const prepare = o => service(`select public.mail_prepare('${o.id}','${o.lease_id}','${'b'.repeat(64)}',null,null)`);
  const finish = (o, result) => service(`select public.mail_finish('${o.id}','${o.lease_id}',${q(result)},null)`);
  const financial = () => db.query(`select jsonb_build_object(
    'refunds',(select jsonb_agg(to_jsonb(r) order by id) from private.voluntary_topup_refunds r),
    'loads',(select jsonb_agg(to_jsonb(l) order by id) from public.wallet_loads l),
    'ledger',(select jsonb_agg(to_jsonb(e) order by id) from public.wallet_ledger_entries e))`);
  const reset = async () => {
    await db.query(`truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,private.mail_suppression,private.account_lifecycle;
      update private.mail_settings set enabled=false;
      truncate public.admin_maintenance_history,public."Maintenance";
      truncate auth.users cascade;
      insert into private.mail_settings(singleton) values(true) on conflict do nothing;
      insert into auth.users(id,email,email_confirmed_at,created_at) values
        ('${owner}','owner@example.test',now(),now()-interval '2 days'),('${customer}','customer@example.test',now(),now()-interval '2 days');
      insert into public.profiles(id,roles,loyalty_policy_version,loyalty_policy_accepted_at) values
        ('${owner}','Owner',public.get_loyalty_policy_descriptor()->>'required_version',now()),
        ('${customer}','User',public.get_loyalty_policy_descriptor()->>'required_version',now());
      insert into auth.sessions(id,user_id,aal,created_at,factor_id) values
        ('${session}','${owner}','aal2',now(),'${factor}'),('${customerSession}','${customer}','aal1',now(),null);
      insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${owner}','totp','verified');
      insert into public."Locations"(id,"Name") values(100,'North') on conflict do nothing;
      delete from public."Location_to_Admin";insert into public."Location_to_Admin"(user_id,location_id) values('${owner}',100);
      update private.topup_refund_policy set enabled_at=now()-interval '3 days';
      update private.mail_settings set enabled=true,rollout_at=now()-interval '1 hour',refund_notice_recipient=null;`);
  };
  let count = 0;
  const request = async () => {
    const intent = `pi_synthetic${++count}`;
    await db.query(`select public.record_wallet_load_from_stripe('${customer}',2000,'${intent}');
      select public.record_topup_refund_provenance('${intent}','${customer}',2000,clock_timestamp()-interval '1 minute','evt_${count}',false,null);`);
    const id = await db.query(`select id from public.wallet_loads where stripe_payment_intent_id='${intent}'`);
    const row = await call(`select public.request_voluntary_topup_refund(${id})`);
    return { ...row, intent };
  };
  const review = (r, action = 'approve') => call(`select public.review_voluntary_topup_refund('${r.id}',${q(action)})`, owner);
  const dispatch = r => db.query(`select public.prepare_voluntary_topup_refund('${r.id}')`);
  const settleSql = (r, status) => `select public.reconcile_voluntary_topup_refund('${r.id}','re_synthetic${r.load_id}',${q(status)},'${r.intent}',2000,'usd',false)`;
  const settle = (r, status = 'succeeded') => run(`${settleSql(r,status)};`);
  const machineClaim = async () => {
    const original = uid(1000 + ++count);
    await db.query(`update public."Locations" set machine_issue_timezone='America/Indiana/Indianapolis' where id=100;
      insert into public."Machines"(id,"Location_ID","Name","Machine_type","Status") values
        (101,100,'Dryer A','Dryer','idle'),(102,100,'Dryer B','Dryer','idle')
        on conflict(id) do update set "Status"='idle',is_out_of_service=false;
      update public.cortina_machine_config set nayax_terminal_id='synthetic-terminal-'||machine_id,
        environment='sandbox',pulse_line_number=6,product_codes=null,is_enabled=true,review_required=false
        where machine_id in (101,102);
      select public.record_wallet_load_from_stripe('${customer}',1000,'pi_machine${count}');`);
    const wallet = await db.query(`select id from public.wallet_accounts where user_id='${customer}'`);
    await call(`select public.admin_adjust_wallet('${wallet}',100,0,100,'Synthetic promo source')`, owner);
    await db.query(`insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,user_id,
      amount_cents,dryer_minutes,pulse_line_number,currency,payment_method,channel,status,transaction_id)
      values('${original}','${uid(2000 + count)}','synthetic-hash',101,'${customer}',450,90,6,'USD','wallet','app','payment_pending','mail-test-${count}')`);
    await call(`select public.redeem_wallet_for_cortina('${original}')`);
    await db.query(`update public.cortina_vend_sessions set status='started',completed_at=clock_timestamp() where id='${original}'`);
    const transaction = await db.query(`select id from public.transactions where cortina_vend_session_id='${original}'`);
    const receipt = await call(`select public.request_cortina_loyalty_credit(${transaction},'Synthetic machine issue')`);
    return { id: receipt.refund_id, original, transaction, requestId: uid(3000 + count) };
  };
  const machineSql = (r, resolution) => `select public.admin_machine_issue('resolveMachineIssue',${q(JSON.stringify({
    id: r.id, requestId: r.requestId, resolution, atLocation: true,
    anotherLoadCompleted: resolution === 'wallet_refund', note: 'Internal staff note',
    ...(resolution === 'replacement_vend' ? { replacementMachineId: 102 } : {}),
  }))}::jsonb)`;
  const resolveMachine = (r, resolution = 'wallet_refund') => call(machineSql(r,resolution), owner);
  const report = () => db.query(`insert into public."Maintenance"(maint_id,user_id,category,description,location_id)
    values(901,'${customer}','Washer','Synthetic issue',100)`);
  const resolveReport = (status = 'resolved', from = 'open') => db.query(`begin;
    update public."Maintenance" set status=${q(status)},updated_at=clock_timestamp() where maint_id=901;
    insert into public.admin_maintenance_history(maintenance_id,actor_id,actor_name,from_status,to_status,note)
      values('901','${owner}','Staff',${q(from)},${q(status)},'Internal note must not be emailed');commit;`);
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await fn(); });

  await t.test('migration changes no financial/worker bodies or activation, exposes no new API', async () => {
    assert.equal(await definitions(), before);
    assert.equal(await db.query('select enabled from private.mail_settings'), 'f');
    for (const role of ['anon','authenticated','service_role','supabase_auth_admin']) {
      assert.equal(await db.query(`select has_table_privilege('${role}','private.mail_outbox','INSERT')`), 'f');
      for (const fn of ['mail_topup_refund_event','mail_maintenance_resolved_event','mail_machine_issue_event']) {
        assert.equal(await db.query(`select has_function_privilege('${role}','private.${fn}()','EXECUTE')`), 'f');
      }
    }
  });
  for (const status of ['succeeded','denied','failed','canceled']) await fresh(`topup ${status} queues one corroborated terminal snapshot`, async () => {
    const r = await request();
    if (status === 'denied') await review(r,'deny');
    else { await review(r); await dispatch(r); await settle(r,status); }
    const [o] = await jobs(); assert.equal(o.state, 'ready'); assert.equal(o.kind, 'topup_refund_outcome');
    assert.equal(o.event_key, `topup_refund_outcome/${r.id}`); assert.equal(o.user_id, customer);
    assert.deepEqual(o.followup_notice, { refund_id: r.id, load_id: String(r.load_id), status,
      amount_cents: 2000, provider_refund_id: status === 'denied' ? null : `re_synthetic${r.load_id}` });
    if (status === 'denied') await review(r,'deny'); else await settle(r,status);
    assert.equal((await jobs()).length, 1); assert.equal((await claim()).id, o.id);
  });
  await fresh('requested, approved, unknown, pending and requires_action do not send a resolved notice', async () => {
    const r = await request(); assert.deepEqual(await jobs(), []);
    await review(r); assert.deepEqual(await jobs(), []);
    await dispatch(r); assert.deepEqual(await jobs(), []);
    await settle(r,'pending'); await settle(r,'requires_action'); assert.deepEqual(await jobs(), []);
  });
  await fresh('rollback removes topup outcome and email intent together', async () => {
    const r = await request(); await review(r); await dispatch(r);
    await run(`begin;${settleSql(r,'succeeded')};set constraints all immediate;rollback;`);
    assert.deepEqual(await jobs(), []);
    assert.equal(await db.query(`select status from private.voluntary_topup_refunds where id='${r.id}'`), 'unknown');
  });
  await fresh('parallel reconciliation preserves exactly one durable event', async () => {
    const r = await request(); await review(r); await dispatch(r);
    await Promise.all([settle(r),settle(r),settle(r)]);
    assert.equal((await jobs()).length, 1);
  });
  await fresh('unsubstantiated succeeded state is suppressed, not a refund confirmation', async () => {
    const r = await request();
    await db.query(`update private.voluntary_topup_refunds set status='succeeded',completed_at=clock_timestamp() where id='${r.id}'`);
    assert.equal((await jobs())[0].state, 'suppressed'); assert.equal(await claim(), null);
  });
  await fresh('disabled sending retains intent; pre-rollout resolution is never backfilled', async () => {
    const r = await request(); await db.query('update private.mail_settings set enabled=false');
    await review(r,'deny'); assert.equal((await jobs())[0].state, 'ready'); assert.equal(await claim(), null);
    await db.query("truncate private.mail_outbox;update private.mail_settings set enabled=true,rollout_at=now()+interval '1 day'");
    const second = await request(); await review(second,'deny'); assert.deepEqual(await jobs(), []);
    await db.query("update private.mail_settings set rollout_at=now()-interval '1 day'");
    await review(second,'deny'); assert.deepEqual(await jobs(), []);
  });
  await fresh('notification retry is independent of financial truth and uncertain mail is parked', async () => {
    const r = await request(); await review(r); await dispatch(r); await settle(r);
    const beforeMoney = await financial(), first = await claim();
    assert.equal(await prepare(first), true); await finish(first,'rate_limited');
    await db.query("update private.mail_outbox set next_at=now()-interval '1 second'");
    const retry = await claim(); assert.equal(retry.id, first.id);
    assert.equal(await prepare(retry), true); await finish(retry,'uncertain');
    assert.equal(await claim(), null); await settle(r);
    assert.equal(await financial(), beforeMoney); assert.equal((await jobs()).length, 1);
  });
  for (const mutation of [
    `update auth.users set email='changed@example.test' where id='${customer}'`,
    `insert into private.mail_suppression(email,reason) values('customer@example.test','complaint')`,
    `update auth.users set banned_until=now()+interval '1 day' where id='${customer}'`,
    `update private.voluntary_topup_refunds set provider_refund_id='re_changed'`,
  ]) await fresh(`prepare suppresses stale topup: ${mutation}`, async () => {
    const r = await request(); await review(r); await dispatch(r); await settle(r);
    const o = await claim(); await db.query(mutation);
    assert.equal(await prepare(o), false); assert.equal((await jobs())[0].state, 'suppressed');
  });
  await fresh('maintenance resolution queues customer-only status, not internal notes', async () => {
    await report(); await resolveReport(); const [o] = await jobs();
    assert.equal(o.kind, 'maintenance_resolved'); assert.equal(o.user_id, customer); assert.equal(o.state, 'ready');
    assert.equal(o.event_key, `maintenance_resolved/${o.maintenance_history_id}`);
    assert.deepEqual(o.followup_notice, { report_id: '901', status: 'resolved' });
    await resolveReport('resolved','resolved'); assert.equal((await jobs()).length, 1);
  });
  await fresh('reopen and resolve again suppresses the obsolete notice and creates one new event', async () => {
    await report(); await resolveReport(); const old = await claim();
    await resolveReport('open','resolved'); await resolveReport();
    assert.equal(await prepare(old), false);
    const next = await claim(); assert.notEqual(next.id, old.id); assert.equal((await jobs()).length, 2);
  });
  await fresh('maintenance rollback and in-progress update have no resolution mail', async () => {
    await report(); await resolveReport('in_progress'); assert.deepEqual(await jobs(), []);
    await run(`begin;update public."Maintenance" set status='resolved' where maint_id=901;
      insert into public.admin_maintenance_history(maintenance_id,actor_id,actor_name,from_status,to_status)
      values('901','${owner}','Staff','in_progress','resolved');rollback;`);
    assert.deepEqual(await jobs(), []);
  });
  await fresh('wallet issue outcome keeps exact paid/promo sources and never queues old credit mail', async () => {
    const r = await machineClaim(); await resolveMachine(r);
    const [o] = await jobs(); assert.equal((await jobs()).length, 1);
    assert.equal(o.kind, 'machine_issue_outcome'); assert.equal(o.state, 'ready');
    assert.equal(o.event_key, `machine_issue_outcome/${r.id}`);
    assert.deepEqual(o.machine_issue_notice, { refund_id: String(r.id), transaction_id: r.transaction,
      resolution: 'wallet_refund', amount_cents: 450, paid_amount_cents: 350, promo_amount_cents: 100,
      replacement_machine_id: null, replacement_machine_name: null });
    assert(!JSON.stringify(o.machine_issue_notice).includes('Internal staff note'));
    await resolveMachine(r); assert.equal((await jobs()).length, 1);
    assert.equal(await prepare(await claim()), true);
  });
  await fresh('replacement remains silent until started; duplicate callbacks do not duplicate mail', async () => {
    const r = await machineClaim(); await resolveMachine(r,'replacement_vend');
    assert.deepEqual(await jobs(), []);
    const replacement = await db.query(`select replacement_session_id from private.machine_issue_resolutions where request_id='${r.requestId}'`);
    await db.query(`update public.cortina_vend_sessions set status='started',completed_at=clock_timestamp() where id='${replacement}'`);
    const [o] = await jobs(); assert.equal(o.state, 'ready'); assert.equal(o.kind, 'machine_issue_outcome');
    assert.equal(o.machine_issue_notice.resolution, 'replacement_vend');
    assert.equal(o.machine_issue_notice.replacement_machine_name, 'Dryer B');
    await db.query(`update public.cortina_vend_sessions set status='started' where id='${replacement}'`);
    await resolveMachine(r,'replacement_vend'); assert.equal((await jobs()).length, 1);
    assert.equal(await prepare(await claim()), true);
  });
  await fresh('manual review and support-required replacement never announce resolution', async () => {
    const r = await machineClaim(); await resolveMachine(r,'manual_review'); assert.deepEqual(await jobs(), []);
    r.requestId = uid(4000 + count); await resolveMachine(r,'replacement_vend');
    await db.query(`update public.cortina_vend_sessions set status='support_required'
      where id=(select replacement_session_id from private.machine_issue_resolutions where request_id='${r.requestId}')`);
    assert.deepEqual(await jobs(), []);
  });
  for (const resolution of ['wallet_refund','replacement_vend']) await fresh(`${resolution} late original Void suppresses queued completion`, async () => {
    const r = await machineClaim(); await resolveMachine(r,resolution);
    if (resolution === 'replacement_vend') await db.query(`update public.cortina_vend_sessions set status='started'
      where id=(select replacement_session_id from private.machine_issue_resolutions where request_id='${r.requestId}')`);
    const o = await claim(); assert(o);
    await db.query(`update public.cortina_vend_sessions set status='voided' where id='${r.original}'`);
    assert.equal(await prepare(o), false); assert.equal((await jobs())[0].state, 'suppressed');
  });
  await fresh('wallet resolution rollback removes financial outcome and deferred notice', async () => {
    const r = await machineClaim();
    await run(`begin;${context(owner)}${machineSql(r,'wallet_refund')};set constraints all immediate;rollback;`);
    assert.deepEqual(await jobs(), []);
    assert.equal(await db.query(`select count(*) from private.machine_issue_resolutions where refund_id=${r.id}`), '0');
  });
  await fresh('machine mail uncertain receipt cannot repeat the wallet restoration', async () => {
    const r = await machineClaim(); await resolveMachine(r);
    const o = await claim(); assert.equal(await prepare(o), true); await finish(o,'uncertain');
    const beforeMoney = await financial(); await resolveMachine(r);
    assert.equal(await financial(), beforeMoney); assert.equal(await claim(), null);
    assert.equal((await jobs()).length, 1);
  });
});
