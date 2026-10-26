import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { read, uid } from './account-cleanup.mjs';
import { blocked } from './policy-admission-pg.mjs';

const version = 'retention-voluntary-surrender-2026-10-05';
const hash = '95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac';
const policy = `'${version}','${hash}'`;
const q = value => `'${String(value).replaceAll("'", "''")}'`;

// Focused composition with the real 90-day/consent/cleanup functions. Synthetic
// historical receipts model elapsed 90-day periods; no live request is shortened,
// immutable trigger disabled, authorization replaced, or provider invoked.
export async function exerciseVoluntarySurrender({ db, run, check, cluster }) {
  const install = async name => db.query(await read(`supabase/migrations/${name}.sql`));
  const service = sql => run(`set role service_role; ${sql};`);
  const auth = p => `set local request.jwt.claims=${q(JSON.stringify({ sub: p.id,
    session_id: p.session, role: 'authenticated', aal: 'aal1',
    exp: Math.floor(Date.now() / 1000) + 3600 }))}; set local request.jwt.claim.sub=''; set local role authenticated;`;
  const human = (p, sql) => run(`begin; ${auth(p)} ${sql}; commit;`).then(JSON.parse);
  const person = async n => {
    const p = { id: uid(n), session: uid(n + 10000), claim: uid(n + 20000), context: uid(n + 30000) };
    await run(`set role supabase_auth_admin;
      insert into auth.users(id,email,email_confirmed_at) values('${p.id}','surrender-${n}@example.invalid',now());
      insert into auth.sessions(id,user_id,aal,created_at) values('${p.session}','${p.id}','aal1',clock_timestamp());`);
    await db.query(`insert into public.profiles(id,email,roles,reward_tracker,loyalty_policy_version,loyalty_policy_accepted_at)
      values('${p.id}','surrender-${n}@example.invalid','User',0,
        public.get_loyalty_policy_descriptor()->>'required_version',clock_timestamp());`);
    return p;
  };
  const load = async (p, amount = 2400, ref = `pi_surrender_${p.id.replaceAll('-', '')}`) => {
    p.wallet = await service(`select public.record_wallet_load_from_stripe('${p.id}',${amount},${q(ref)})`);
    return db.query(`select id from public.wallet_loads where stripe_payment_intent_id=${q(ref)};`);
  };
  const balance = p => db.query(`select jsonb_build_array(paid_balance_cents,promo_balance_cents)
    from public.wallet_balances where wallet_account_id='${p.wallet}';`).then(JSON.parse);
  const count = p => db.query(`select count(*) from public.wallet_ledger_entries where surrender_context_id='${p.context}';`);
  const step = p => `select public.execute_account_cleanup_step('${p.claim}',${policy},'${p.id}',${q(p.requested)})`;
  const ack = p => service(`select public.acknowledge_account_cleanup('${p.id}',${q(p.requested)},
    '${p.claim}','${p.dispatch.operation_id}',${policy},'returned')`).then(JSON.parse);
  const retire = async p => {
    p.dispatch = JSON.parse(await service(step(p)));
    assert.equal(p.dispatch.action, 'auth');
    await run(`set role supabase_auth_admin; delete from auth.users where id='${p.id}';`);
    assert.equal((await ack(p)).status, 'account_removed');
  };
  const historical = async (p, { eligible = true, hours = 2161 } = {}) => {
    await db.query(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
      select '${p.id}',d,d+interval '2160 hours' from (select clock_timestamp()-${hours}*interval '1 hour' d) x;
      insert into private.loyalty_action_contexts(id,subject_id,session_id,action,policy,acknowledgement,
        purchased_balance_cents,promotional_balance_cents,recovery_days,created_at,expires_at)
      select '${p.context}','${p.id}','${p.session}','account_deletion',public.get_loyalty_policy_descriptor(),
        (public.get_loyalty_policy_descriptor()->>'policy_text')::jsonb #>> '{action_acknowledgements,account_deletion}',
        b.paid_balance_cents,b.promo_balance_cents,90,l.deletion_requested_at,l.deletion_requested_at+interval '10 minutes'
      from public.wallet_balances b cross join private.account_lifecycle l
      where b.wallet_account_id='${p.wallet}' and l.user_id='${p.id}';
      insert into private.loyalty_action_receipts(context_id,wallet_account_id,channel,accepted_at,deletion_result,
        surrender_requested_at,surrender_ledger_id)
      select '${p.context}','${p.wallet}','account_deletion',l.deletion_requested_at,
        jsonb_build_object('restore_until',l.restore_until),${eligible ? 'l.deletion_requested_at' : 'null'},
        ${eligible ? `(select coalesce(max(id),0) from public.wallet_ledger_entries where wallet_account_id='${p.wallet}')` : 'null'}
      from private.account_lifecycle l where user_id='${p.id}';
      insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
        hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
        backup_disposition_reference,financial_retention_reference)
      select user_id,deletion_requested_at,'${uid(6003)}',clock_timestamp(),
        'SYNTHETIC holds','SYNTHETIC processors','SYNTHETIC media','SYNTHETIC backups','SYNTHETIC financial'
      from private.account_lifecycle where user_id='${p.id}';`);
    p.requested = await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${p.id}';`);
  };
  const retryRetained = async p => {
    await db.query(`update private.account_cleanup_jobs set last_retention_at=null where user_id='${p.id}';`);
    for (let i=0;i<20;i++) {
      await db.query('select private.prune_account_cleanup_retention();');
      if (await db.query(`select last_retention_at is not null from private.account_cleanup_jobs where user_id='${p.id}';`)==='t') return;
    }
    assert.fail('Bounded retention pass did not reach the synthetic subject');
  };

  await install('20261001140307_mail_transactional_postal_split');
  await install('20260930193130_new_payment_service_control');
  // Mirror hosted effective permission, not a source-default privilege change.
  await db.query('grant execute on function public.request_account_deletion() to authenticated;');
  await install('20261005152329_loyalty_action_consent');
  const old = await person(8001); await load(old);
  const preview = await human(old, "select public.get_loyalty_action_context('account_deletion')");
  await human(old, `select public.request_account_deletion_with_consent('${preview.context_id}',true)`);
  const oldReceipt = await db.query(`select to_jsonb(r) from private.loyalty_action_receipts r where context_id='${preview.context_id}';`);
  const acl = await db.query("select proacl from pg_proc where oid='public.request_account_deletion_with_consent(uuid,boolean)'::regprocedure;");
  await install('20261005180901_voluntary_deletion_credit_surrender');
  const finalDocument = JSON.parse(await read('supabase/policies/loyalty-2026-10-05.2.json'));
  const publish = doc => `update public.loyalty_policy_documents set is_current=false where is_current;
    insert into public.loyalty_policy_documents(version,document,is_current) values('2026-10-05.2',${q(JSON.stringify(doc))}::jsonb,true);`;
  const pin = `update private.account_cleanup_execution set surrender_policy_version='2026-10-05.2',
    surrender_policy_sha256=public.get_loyalty_policy_descriptor()->>'policy_sha256';`;

  await check('surrender installation keeps historical receipts, effective ACL, disabled execution and publication intact', async () => {
    assert.equal(await db.query(`select (to_jsonb(r)-array['surrender_requested_at','surrender_ledger_id'])::text
      from private.loyalty_action_receipts r where context_id='${preview.context_id}';`),oldReceipt);
    assert.equal(await db.query(`select surrender_requested_at is null from private.loyalty_action_receipts
      where context_id='${preview.context_id}';`),'t');
    assert.equal(await db.query("select proacl from pg_proc where oid='public.request_account_deletion_with_consent(uuid,boolean)'::regprocedure;"),acl);
    assert.equal(await db.query('select not execution_enabled and not credit_forfeiture_enabled from private.account_cleanup_execution;'),'t');
    assert.equal(await db.query("select public.get_loyalty_policy_descriptor()->>'required_version';"),'2026-10-03.1');
    for (const role of ['anon','authenticated','service_role','supabase_auth_admin']) {
      assert.equal(await db.query(`select has_function_privilege('${role}','private.surrender_retired_account_credit(uuid)','execute');`),'f');
    }
    await assert.rejects(human(old, 'select public.request_account_deletion()'),/consent_required/);
  });
  await check('final publication and pin reject draft/wrong hash atomically; metadata is exact', async () => {
    assert.equal(Object.hasOwn(finalDocument,'draft'),false);
    assert.equal(finalDocument.action_acknowledgements.wallet_load,'I agree to the Loyalty Program Terms for this purchase.');
    assert(!finalDocument.action_acknowledgements.account_deletion.includes('Existing eligible'));
    await assert.rejects(run(`begin; set local role postgres; ${publish({...finalDocument,draft:true})} ${pin} commit;`),/Published final/);
    await assert.rejects(run(`begin; set local role postgres; ${publish(finalDocument)}
      update private.account_cleanup_execution set surrender_policy_version='2026-10-05.2',surrender_policy_sha256=repeat('0',64); commit;`),/Published final/);
    assert.equal(await db.query("select count(*) from public.loyalty_policy_documents where version='2026-10-05.2';"),'0');
    await install('20261005181711_publish_approved_loyalty_policy');
    assert.equal(await db.query("select count(*) from public.loyalty_policy_documents where version='2026-10-05.1';"),'0');
    const descriptor = JSON.parse(await db.query('select public.get_loyalty_policy_descriptor();'));
    assert.equal(descriptor.policy_sha256,createHash('sha256').update(descriptor.policy_text).digest('hex'));
    assert.deepEqual(JSON.parse(descriptor.policy_text),finalDocument);
  });
  await check('real 90-day consent request qualifies prospectively and duplicate preserves full deadline', async () => {
    const p=await person(8002); await load(p);
    const c=await human(p,"select public.get_loyalty_action_context('account_deletion')");
    assert.equal(c.recovery_days,90); assert.equal(c.acknowledgement,finalDocument.action_acknowledgements.account_deletion);
    const call=`select public.request_account_deletion_with_consent('${c.context_id}',true)`;
    const result=await human(p,call); assert.deepEqual(await human(p,call),result);
    assert.equal(await db.query(`select surrender_requested_at is not null and surrender_ledger_id>0
      from private.loyalty_action_receipts where context_id='${c.context_id}';`),'t');
    assert.equal(await db.query(`select restore_until=deletion_requested_at+interval '2160 hours'
      from private.account_lifecycle where user_id='${p.id}';`),'t');
    await assert.rejects(run(`update private.loyalty_action_receipts set surrender_requested_at=null where context_id='${c.context_id}';`),/immutable/);
    assert.deepEqual(await balance(p),[2400,500]);
  });
  await check('surrender policy pins replace preservation approvals without enabling any operation', async () => {
    const contract=`${version}|restore=90-days-explicit|delete=auth-profile|paid=prospective-explicit-receipt-capped|promo=prospective-explicit-receipt-capped|unresolved=retain|law=existing-scoped-holds|late-credit=retain|audit=append-only`;
    assert.equal(createHash('sha256').update(contract).digest('hex'),hash);
    for (const path of ['supabase/functions/account-cleanup/execution.ts','supabase/ops/account-cleanup-setup.sql']) {
      const source=await read(path); assert(source.includes(version)); assert(source.includes(hash));
    }
    await assert.rejects(service(`select public.execute_account_cleanup_step('${uid(38001)}',${policy})`),/cleanup_policy_unapproved/);
    // Explicit local fixture activation only. No synthetic evidence is deployed.
    await db.query(`update private.account_cleanup_execution set execution_enabled=true,credit_forfeiture_enabled=true,
      approved_policy_version='${version}',approved_policy_sha256='${hash}',final_policy_approved_at=clock_timestamp();`);
  });
  await check('pre-consent historical deletion still retains principal under enabled surrender', async () => {
    const p=await person(8003); await load(p); await historical(p,{eligible:false}); await retire(p);
    assert.deepEqual(await balance(p),[2400,0]); assert.equal(await count(p),'0');
  });
  await check('expired acknowledged snapshot appends one immutable surrender and keeps all historical loads/ledger', async () => {
    const p=await person(8004); await load(p); await historical(p);
    const before=await db.query(`select jsonb_agg(to_jsonb(e) order by id) from public.wallet_ledger_entries e where wallet_account_id='${p.wallet}';`);
    await retire(p); assert.deepEqual(await balance(p),[0,0]); assert.equal(await count(p),'1');
    assert.equal(await db.query(`select jsonb_agg(to_jsonb(e) order by id) from public.wallet_ledger_entries e
      where wallet_account_id='${p.wallet}' and surrender_context_id is null;`),before);
    await retryRetained(p); assert.equal(await count(p),'1');
    await assert.rejects(run(`delete from public.wallet_ledger_entries where surrender_context_id='${p.context}';`),/immutable/);
    assert.equal(await db.query(`select count(*) from private.topup_refund_spend where wallet_id='${p.wallet}';`),'0');
    await load(p,1500,'pi_surrender_late');
    await db.query(`insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents)
      values('${p.wallet}','void',300,100,200);`);
    await retryRetained(p); assert.deepEqual(await balance(p),[1600,200]); assert.equal(await count(p),'1');
  });
  await check('mandatory-law financial hold preserves credit; existing retention pass resumes after explicit release', async () => {
    const p=await person(8005); await load(p); await historical(p);
    await db.query(`insert into private.account_retention_holds(user_id,data_class,authority,purpose,custodian,review_at)
      values('${p.id}','financial','SYNTHETIC mandatory law','SYNTHETIC retained claim','${uid(6003)}',clock_timestamp()+interval '3 months');`);
    await retire(p); assert.deepEqual(await balance(p),[2400,500]); assert.equal(await count(p),'0');
    await retryRetained(p); assert.equal(await count(p),'0');
    await db.query(`update private.account_retention_holds set released_at=clock_timestamp(),released_by='${uid(6003)}',
      release_reference='SYNTHETIC resolved claim' where user_id='${p.id}';`);
    await retryRetained(p); assert.deepEqual(await balance(p),[0,0]); assert.equal(await count(p),'1');
  });
  await check('empty snapshot records zero without adding a per-request approval workflow', async () => {
    const p=await person(8006); p.wallet=await service(`select public.get_or_create_wallet_account('${p.id}')`);
    await historical(p); await retire(p);
    assert.equal(await count(p),'1'); assert.deepEqual(await balance(p),[0,0]);
    assert.equal(await db.query("select count(*) from information_schema.columns where table_schema='private' and table_name='account_cleanup_inventory' and column_name like 'credit_surrender%';"),'0');
  });
  await check('post-acknowledgement debits reduce cap and later positive corrections remain intact', async () => {
    const p=await person(8007); await load(p); await historical(p);
    await db.query(`insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents)
      values('${p.wallet}','admin_adjustment',-400,-300,-100),('${p.wallet}','void',1200,1000,200);`);
    await retire(p); assert.deepEqual(await balance(p),[1000,200]);
    assert.equal(await db.query(`select paid_amount_cents||','||promo_amount_cents from public.wallet_ledger_entries
      where surrender_context_id='${p.context}';`),'-2100,-400');
  });
  await check('unresolved per-load provider outcome keeps surrender held despite cleanup inventory', async () => {
    const p=await person(8008); await load(p);
    const c=await human(p,"select public.get_loyalty_action_context('wallet_load')");
    await human(p,`select public.accept_wallet_load_consent('${c.context_id}',true,500,'payment_intent')`);
    await historical(p); await retire(p); assert.equal(await count(p),'0'); assert.deepEqual(await balance(p),[2400,500]);
    await service(`select public.bind_wallet_load_consent_provider('${c.context_id}','${p.id}',500,'payment_intent','pi_surrender_unresolved')`);
    await retryRetained(p); assert.equal(await count(p),'0');
    await load(p,500,'pi_surrender_unresolved'); await retryRetained(p);
    assert.equal(await count(p),'1'); assert.deepEqual(await balance(p),[500,0]);
  });
  await check('unknown refund protects credit and its late failed reservation release is never surrendered', async () => {
    const p=await person(8011),ref='pi_surrender_refund';
    const loadId=await load(p,1500,ref);
    assert.equal(await service(`select public.record_topup_refund_provenance('${ref}','${p.id}',1500,
      clock_timestamp(),'evt_surrender_refund',false)`),'t');
    const refund=await human(p,`select public.request_voluntary_topup_refund(${loadId})`);
    await db.query(`update private.voluntary_topup_refunds set status='approved',reviewed_at=clock_timestamp(),
      review_note='SYNTHETIC approved refund' where id='${refund.id}';`);
    assert.equal(JSON.parse(await service(`select public.prepare_voluntary_topup_refund('${refund.id}')`)).may_create,true);
    await load(p,2400,'pi_surrender_refund_other'); await historical(p); await retire(p);
    assert.equal(await count(p),'0'); assert.deepEqual(await balance(p),[2400,500]);
    const reconcile=()=>service(`select public.reconcile_voluntary_topup_refund('${refund.id}',
      're_surrender_failed','failed','${ref}',1500,'usd',false)`);
    assert.equal(JSON.parse(await reconcile()).status,'failed');
    await retryRetained(p); assert.deepEqual(await balance(p),[1500,0]); assert.equal(await count(p),'1');
    await reconcile(); assert.deepEqual(await balance(p),[1500,0]);
  });
  await check('genuine 90-day future deadline and explicit restoration prevent any surrender', async () => {
    const p=await person(8009); await load(p); await historical(p,{hours:2159});
    assert.equal(JSON.parse(await service(step(p))).status,'held');
    assert.equal((await human(p,'select public.restore_account()')).account_access,'eligible');
    assert.equal(JSON.parse(await service(step(p))).status,'held');
    assert.equal(await count(p),'0'); assert.deepEqual(await balance(p),[2400,500]);
  });
  await check('late financial hold serializes against Auth removal and wins without losing claim balances', async () => {
    const p=await person(8010); await load(p); await historical(p);
    p.dispatch=JSON.parse(await service(step(p))); assert.equal(p.dispatch.action,'auth');
    const holder=await cluster.connect(),deleter=await cluster.connect(); let waiting;
    try {
      await holder.query(`begin; set local role postgres;
        insert into private.account_retention_holds(user_id,data_class,authority,purpose,custodian,review_at)
        values('${p.id}','financial','SYNTHETIC race','SYNTHETIC open claim','${uid(6003)}',clock_timestamp()+interval '3 months');`);
      waiting=deleter.query(`set role supabase_auth_admin; delete from auth.users where id='${p.id}';`)
        .then(value=>({value}),error=>({error}));
      await blocked(db,deleter,holder); await holder.query('commit;');
      assert.ifError((await waiting).error);
    } finally { await holder.close(); await deleter.close(); if(waiting) await waiting; }
    assert.equal((await ack(p)).status,'account_removed');
    assert.equal(await count(p),'0'); assert.deepEqual(await balance(p),[2400,500]);
  });
}
