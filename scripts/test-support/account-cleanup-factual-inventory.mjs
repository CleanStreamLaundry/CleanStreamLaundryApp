import assert from 'node:assert/strict';
import { read, uid } from './account-cleanup.mjs';

const version='retention-voluntary-surrender-2026-10-05';
const hash='95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac';
const policy=`'${version}','${hash}'`;
const q=value=>`'${String(value).replaceAll("'","''")}'`;

export async function exerciseFactualCleanupInventory({db,run,check}) {
  // Hosted read-only preflight confirms this existing table-level grant. Scope
  // that catalog match to inventory QA; older restricted-column suites stay intact.
  await run('set role supabase_auth_admin; grant select on auth.users to postgres;');
  const service=sql=>run(`set role service_role; ${sql};`).then(JSON.parse);
  const person=async(n,role='User')=>{
    const p={id:uid(n),context:uid(n+30000),session:uid(n+10000),claim:uid(n+20000)};
    await run(`set role supabase_auth_admin;
      insert into auth.users(id,email,email_confirmed_at) values('${p.id}','inventory-${n}@example.invalid',now());
      insert into auth.sessions(id,user_id,aal,created_at) values('${p.session}','${p.id}','aal1',clock_timestamp());`);
    await db.query(`insert into public.profiles(id,email,roles,reward_tracker,loyalty_policy_version,loyalty_policy_accepted_at)
      values('${p.id}','inventory-${n}@example.invalid','${role}',0,'2026-10-05.2',clock_timestamp());`);
    p.wallet=await run(`set role service_role; select public.get_or_create_wallet_account('${p.id}');`);
    return p;
  };
  // Historical test snapshots obey the real 2160-hour constraint. They are
  // fixture data, never a shortening of a real accepted request or a fake review.
  const request=async(p,{hours=2161,eligible=true,restored=false}={})=>{
    await db.query(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until,restored_at)
      select '${p.id}',d,d+interval '2160 hours',${restored?"d+interval '1 hour'":'null'}
      from(select clock_timestamp()-${hours}*interval '1 hour' d)x;
      insert into private.loyalty_action_contexts(id,subject_id,session_id,action,policy,acknowledgement,
        purchased_balance_cents,promotional_balance_cents,recovery_days,created_at,expires_at)
      select '${p.context}','${p.id}','${p.session}','account_deletion',public.get_loyalty_policy_descriptor(),
        (public.get_loyalty_policy_descriptor()->>'policy_text')::jsonb #>> '{action_acknowledgements,account_deletion}',
        b.paid_balance_cents,b.promo_balance_cents,90,l.deletion_requested_at,l.deletion_requested_at+interval '10 minutes'
      from public.wallet_balances b cross join private.account_lifecycle l where b.wallet_account_id='${p.wallet}' and l.user_id='${p.id}';
      insert into private.loyalty_action_receipts(context_id,wallet_account_id,channel,accepted_at,deletion_result,
        surrender_requested_at,surrender_ledger_id)
      select '${p.context}','${p.wallet}','account_deletion',deletion_requested_at,
        jsonb_build_object('restore_until',restore_until),${eligible?'deletion_requested_at':'null'},
        ${eligible?`(select coalesce(max(id),0) from public.wallet_ledger_entries where wallet_account_id='${p.wallet}')`:'null'}
      from private.account_lifecycle where user_id='${p.id}';`);
    p.requested=await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${p.id}';`);
  };
  const dispatch=p=>service(`select public.execute_account_cleanup_step('${p.claim}',${policy})`);
  const finish=async(p,result)=>{
    assert.equal(result.action,'auth'); assert.equal(result.user_id,p.id);
    await run(`set role supabase_auth_admin; delete from auth.users where id='${p.id}';`);
    const ack=await service(`select public.acknowledge_account_cleanup('${p.id}',${q(p.requested)},
      '${result.claim_id}','${result.operation_id}',${policy},'returned')`);
    assert.equal(ack.status,'account_removed');
  };
  await db.query('update private.account_cleanup_execution set execution_enabled=false,credit_forfeiture_enabled=false;');
  await db.query(await read('supabase/migrations/20261005183040_factual_account_cleanup_inventory.sql'));
  await db.query(`update private.account_cleanup_execution set execution_enabled=true,credit_forfeiture_enabled=true,
    approved_policy_version='${version}',approved_policy_sha256='${hash}',final_policy_approved_at=clock_timestamp();`);
  const owner=await person(9100,'Owner');
  await run(`set role supabase_auth_admin; insert into auth.mfa_factors(id,user_id,factor_type,status,created_at)
    values('${uid(49100)}','${owner.id}','totp','verified',clock_timestamp());`);

  await check('automatic inventory: expired empty request dispatches without operator inventory or invented provider completion',async()=>{
    assert.equal(await db.query("select has_table_privilege('postgres','auth.users','SELECT');"),'t');
    const p=await person(9101); await request(p);
    assert.equal(await db.query(`select count(*) from private.account_cleanup_inventory where user_id='${p.id}';`),'0');
    const result=await dispatch(p);
    const inventory=JSON.parse(await db.query(`select to_jsonb(i) from private.account_cleanup_inventory i where user_id='${p.id}';`));
    assert(inventory); assert.equal(inventory.preparation_facts.source,'database_snapshot');
    assert.equal(inventory.preparation_facts.consent_context_id,p.context);
    assert.equal(inventory.preparation_facts.processor_erasure_verified,false);
    assert.equal(inventory.preparation_facts.backup_erasure_verified,false);
    assert.equal(inventory.preparation_facts.media_objects,0);
    assert.match(inventory.backup_disposition_reference,/erasure unverified/);
    assert.equal(await db.query(`select roles::text='Owner' and private.owner_target_restriction(id) is null
      from public.profiles where id='${inventory.custodian}';`),'t');
    const original=JSON.stringify(inventory);
    await db.query('select private.prepare_account_cleanup_inventory();');
    assert.equal(JSON.stringify(JSON.parse(await db.query(`select to_jsonb(i) from private.account_cleanup_inventory i where user_id='${p.id}';`))),original);
    await finish(p,result);
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where surrender_context_id='${p.context}';`),'1');
  });
  await check('automatic inventory: future, restored and old non-surrender receipts never qualify',async()=>{
    const subjects=[];
    for(const [n,options] of [[9102,{hours:2159}],[9103,{restored:true}],[9104,{eligible:false}]]) {
      const p=await person(n); await request(p,options); subjects.push(p);
    }
    assert.equal(await db.query('select private.prepare_account_cleanup_inventory() is null;'),'t');
    for(const p of subjects) assert.equal(await db.query(`select count(*) from private.account_cleanup_inventory where user_id='${p.id}';`),'0');
    for(const role of ['anon','authenticated','service_role','supabase_auth_admin'])
      assert.equal(await db.query(`select has_function_privilege('${role}','private.prepare_account_cleanup_inventory()','execute');`),'f');
  });
  await check('automatic inventory: existing financial hold is factual evidence, not a block on ordinary identity disposal',async()=>{
    const p=await person(9105);
    await run(`set role service_role; select public.record_wallet_load_from_stripe('${p.id}',2400,'pi_factual_inventory_hold');`);
    await request(p);
    await db.query(`insert into private.account_retention_holds(user_id,data_class,authority,purpose,custodian,review_at)
      values('${p.id}','financial','SYNTHETIC specific obligation','SYNTHETIC unresolved claim','${owner.id}',clock_timestamp()+interval '3 months');`);
    const result=await dispatch(p); await finish(p,result);
    assert.equal(await db.query(`select preparation_facts->>'active_holds' from private.account_cleanup_inventory where user_id='${p.id}';`),'1');
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where surrender_context_id='${p.context}';`),'0');
    assert.deepEqual(JSON.parse(await db.query(`select jsonb_build_array(paid_balance_cents,promo_balance_cents)
      from public.wallet_balances where wallet_account_id='${p.wallet}';`)),[2400,500]);
  });
  await check('automatic inventory: missing eligible custodian has an explicit reason and no manufactured row',async()=>{
    const p=await person(9106); await request(p);
    const owners=JSON.parse(await db.query("select jsonb_agg(id) from public.profiles where roles::text='Owner';"));
    const result=JSON.parse(await run(`begin; set local role supabase_auth_admin;
      update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id in (${owners.map(q).join(',')});
      set local role postgres; select private.prepare_account_cleanup_inventory(); rollback;`));
    assert.equal(result.reason,'eligible_owner_custodian_unavailable');
    assert.equal(await db.query(`select count(*) from private.account_cleanup_inventory where user_id='${p.id}';`),'0');
  });
}
