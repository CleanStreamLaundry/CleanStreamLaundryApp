import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = (p) => readFile(new URL(p, import.meta.url), 'utf8');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user=uid(1), owner=uid(2), other=uid(3), sid=uid(11), osid=uid(12), factor=uid(20);
const claims = (who=user, extra={}) => ({sub:who,session_id:who===owner?osid:sid,
  role:'authenticated',aal:who===owner?'aal2':'aal1',exp:Math.floor(Date.now()/1000)+3600,...extra});
const context = (who=user, extra={}) => `set local request.jwt.claims='${JSON.stringify(claims(who,extra))}';
  set local request.jwt.claim.sub=''; set local role authenticated;`;
const asUser = (sql, who=user, extra={}) => `begin; ${context(who,extra)} ${sql}; commit;`;
const wallet = `(select id from public.wallet_accounts where user_id='${user}')`;
const migrationPath='../supabase/migrations/20260930125554_voluntary_topup_refunds.sql';

test('voluntary top-up refunds: actual financial and canonical authority migrations', {timeout:180000}, async (t) => {
  const cluster=await disposableCluster(t,process.env.PG_BIN), db=await cluster.connect();
  const run=async(sql)=>{const c=await cluster.connect();try{return await c.query(sql);}finally{await c.close();}};
  const call=async(sql,who=user,extra={})=>JSON.parse(await run(asUser(sql,who,extra)));
  const fails=(sql,pattern,who=user,extra={})=>assert.rejects(run(asUser(sql,who,extra)),pattern);
  const fixture=(await read('../supabase/tests/wallet_financial_locking.fixture.sql')).split('-- AFTER_BASELINE_MIGRATIONS');
  await db.query('create role postgres superuser; set role postgres;');
  await db.query(fixture[0]);
  for(const file of ['20260526010000_wallet_ledger_compliance.sql','20260803150427_cortina_qr_remote_vend.sql',
    '20260807191723_harden_refund_resolution.sql','20260929231120_serialize_wallet_financial_writes.sql']) {
    await db.query(await read(`../supabase/migrations/${file}`));
  }
  await db.query(fixture[1]);
  await db.query(`alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}';
    alter table public.profiles add column created_at timestamptz default now();
    alter table public."Location_to_Admin" enable row level security;`);
  for(const file of ['20260929223124_protect_profile_authority.sql','20260929234955_loyalty_policy_acceptance.sql']) {
    await db.query(await read(`../supabase/migrations/${file}`));
  }
  await db.query(await read('../supabase/tests/account_admission.fixture.sql'));
  for(const file of ['20260930005456_account_admission.sql','20260930013417_enforce_profile_terms_admission.sql',
    '20260930024142_protect_location_membership.sql','20260930063923_recoverable_account_deletion.sql']) {
    await db.query(await read(`../supabase/migrations/${file}`));
  }
  await db.query(await read(migrationPath));
  const reset=()=>db.query(`truncate auth.users cascade;
    insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${owner}',now()),('${other}',now());
    insert into public.profiles(id,roles) values('${user}','User'),('${owner}','Owner'),('${other}','User');
    insert into auth.sessions(id,user_id,aal,created_at,factor_id) values
      ('${sid}','${user}','aal1',now()-interval '1 hour',null),('${osid}','${owner}','aal2',now(),'${factor}');
    insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${owner}','totp','verified');
    insert into public."Locations" values(1),(2) on conflict do nothing;
    insert into public."Machines"(id,"Location_ID") values(1,1) on conflict do nothing;
    insert into public."Location_to_Admin" values('${owner}',1);
    update private.topup_refund_policy set enabled_at=now()-interval '3 days';`);
  let count=0;
  const load=async(amount=2000,age="interval '1 minute'",location='null')=>{
    const key=`${++count}`;
    await db.query(`select public.record_wallet_load_from_stripe('${user}',${amount},'pi_${key}');
      select public.record_topup_refund_provenance('pi_${key}','${user}',${amount},clock_timestamp()-${age},'evt_${key}',false,${location});`);
    return Number(await db.query(`select id from public.wallet_loads where stripe_payment_intent_id='pi_${key}';`));
  };
  const request=(id)=>call(`select public.request_voluntary_topup_refund(${id})`);
  const review=(id,action='approve',who=owner)=>call(`select public.review_voluntary_topup_refund('${id}','${action}')`,who);
  const prep=async(id)=>JSON.parse(await db.query(`select public.prepare_voluntary_topup_refund('${id}');`) || 'null');
  const reconcile=async(r,status='succeeded',overrides={})=>{
    const op=await prep(r.id);
    return JSON.parse(await run(`select public.reconcile_voluntary_topup_refund('${r.id}','re_${r.load_id}',
      '${status}','${overrides.intent??op?.intent??'pi_invalid'}',${overrides.amount??r.principal_cents},'usd',false);`));
  };
  const balance=async()=>JSON.parse(await db.query(`select json_build_array(paid_balance_cents,promo_balance_cents,
    (select round(reward_tracker*100) from public.profiles where id='${user}')) from public.wallet_balances where wallet_account_id=${wallet};`));
  const fresh=(name,fn)=>t.test(name,async()=>{await reset();await fn();});

  await fresh('full principal reserved, replay once, no bookkeeping-only success',async()=>{
    const id=await load(), r=await request(id); assert.equal(r.status,'requested');
    assert.deepEqual(await balance(),[0,0,0]); assert.deepEqual(await request(id),r);
    assert.equal(await db.query(`select status from public.wallet_loads where id=${id};`),'succeeded');
    await review(r.id); assert.equal((await prep(r.id)).amount,2000);
    assert.equal((await reconcile(r)).status,'succeeded');
    assert.equal(await db.query(`select status from public.wallet_loads where id=${id};`),'refunded');
    assert.deepEqual(await balance(),[0,0,0]);
  });
  await fresh('history without provenance fails closed',async()=>{
    const id=await load(); await db.query(`delete from private.topup_refund_provenance where load_id=${id};`);
    await fails(`select public.request_voluntary_topup_refund(${id})`,/provenance_unavailable/);
  });
  await fresh('load insertion time is never substituted for success clock',async()=>{
    await db.query(`select public.record_wallet_load_from_stripe('${user}',2000,'pi_missing');`);
    const id=await db.query("select id from public.wallet_loads where stripe_payment_intent_id='pi_missing';");
    await fails(`select public.request_voluntary_topup_refund(${id})`,/provenance_unavailable/);
  });
  await fresh('inclusive 48h and no client supplied clock',async()=>{
    const id=await load();
    const result=JSON.parse(await run(`begin;
      do $$ begin
        update private.topup_refund_provenance set payment_succeeded_at=statement_timestamp()-interval '48 hours' where load_id=${id};
        perform set_config('request.jwt.claims','${JSON.stringify(claims())}',true);
        perform public.request_voluntary_topup_refund(${id});
      end $$;
      ${context()} select public.request_voluntary_topup_refund(${id}); commit;`));
    assert.equal(result.status,'requested');
  });
  for(const age of ["interval '48 hours 1 second'","interval '-1 second'"]) await fresh(`window rejects ${age}`,async()=>{
    const id=await load(); await db.query(`update private.topup_refund_provenance set payment_succeeded_at=clock_timestamp()-${age} where load_id=${id};`);
    await fails(`select public.request_voluntary_topup_refund(${id})`,/refund_window_closed/);
  });
  await fresh('request receipt precedes wallet wait; Owner may approve after 48h',async()=>{
    const id=await load(), a=await cluster.connect(), b=await cluster.connect();
    try{
      await a.query(`begin; select id from public.wallet_accounts where id=${wallet} for no key update;
        update private.topup_refund_provenance set payment_succeeded_at=clock_timestamp()-interval '48 hours'+interval '500 milliseconds' where load_id=${id};`);
      const waiting=b.query(asUser(`select public.request_voluntary_topup_refund(${id})`));
      await blocked(db,b,a); await db.query('select pg_sleep(0.6);'); await a.query('commit;');
      const r=JSON.parse(await waiting); assert.equal((await review(r.id)).status,'approved');
    }finally{await a.close();await b.close();}
  });
  await fresh('previous usage allowed, promo-only spend after funding disqualifies even reversed',async()=>{
    await load(); await call(`select public.redeem_wallet_for_machine('${user}',1,100,'earlier')`);
    const id=await load(2000,"interval '0 seconds'"); assert.equal((await request(id)).status,'requested');
    const next=await load(2000,"interval '0 seconds'");
    await call(`select public.redeem_wallet_for_machine('${user}',1,100,'later promo')`);
    await db.query(`insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,promo_amount_cents)
      values(${wallet},'void',100,100); update public.wallet_redemptions set status='void';`);
    await fails(`select public.request_voluntary_topup_refund(${next})`,/wallet_used_after_topup/);
  });
  await fresh('subsequent loads and multiple refunds unwind cross-load thresholds',async()=>{
    const a=await load(1500), b=await load(1000);
    assert.deepEqual(await balance(),[2500,500,500]);
    const r=await request(a); assert.equal(r.bonus_reserved_cents,500); assert.deepEqual(await balance(),[1000,0,1000]);
    await request(b); assert.deepEqual(await balance(),[0,0,0]);
    await review(r.id,'deny'); assert.deepEqual(await balance(),[1500,0,1500]);
  });
  await fresh('deny restores cumulative reward contribution after later funding',async()=>{
    const r=await request(await load(1500)); await load(1000);
    await review(r.id,'deny'); assert.deepEqual(await balance(),[2500,500,500]);
    await review(r.id,'deny'); assert.deepEqual(await balance(),[2500,500,500]);
  });
  for(const status of ['pending','requires_action','failed','canceled']) await fresh(`provider ${status}`,async()=>{
    const r=await request(await load()); await review(r.id); const result=await reconcile(r,status);
    assert.equal(result.status,status==='requires_action'?'pending':status);
    assert.deepEqual(await balance(),['failed','canceled'].includes(status)?[2000,500,0]:[0,0,0]);
  });
  await fresh('unknown keeps reservation and old idempotency keys cannot create',async()=>{
    const r=await request(await load()); await review(r.id); const first=await prep(r.id);
    assert.equal(first.may_create,true); assert.deepEqual(await balance(),[0,0,0]);
    await db.query(`update private.voluntary_topup_refunds set dispatch_started_at=now()-interval '24 hours' where id='${r.id}';`);
    const later=await prep(r.id); assert.equal(later.may_create,false); assert.equal(later.idempotency_key,first.idempotency_key);
    await assert.rejects(review(r.id,'deny'),/refund_decision_conflict/);
  });
  await fresh('provider mismatch and reordered terminal updates cannot change money',async()=>{
    const r=await request(await load()); await review(r.id);
    await assert.rejects(reconcile(r,'succeeded',{amount:1000}),/provider_mismatch/);
    await reconcile(r); const intent=await db.query(`select stripe_payment_intent_id from private.voluntary_topup_refunds where id='${r.id}';`);
    await assert.rejects(reconcile(r,'pending',{intent}),/provider_terminal_conflict/);
    assert.equal((await reconcile(r,'succeeded',{intent})).status,'succeeded');
    assert.deepEqual(await balance(),[0,0,0]);
  });
  for(const action of ['spend','cash','adjust']) await fresh(`reservation defeats concurrent ${action} under same wallet lock`,async()=>{
    const id=await load(), a=await cluster.connect(), b=await cluster.connect();
    const walletId=await db.query(`select id from public.wallet_accounts where user_id='${user}';`);
    try{
      await a.query(`begin; ${context()} select public.request_voluntary_topup_refund(${id});`);
      const sql=action==='spend'?`select public.redeem_wallet_for_machine('${user}',1,100,'test')`:
        action==='cash'?`select public.admin_record_legal_cash_redemption('${walletId}',100,null,'test')`:
          `select public.admin_adjust_wallet('${walletId}',-100,-100,0,'test')`;
      const pending=b.query(asUser(sql,action==='spend'?user:owner)); const rejection=assert.rejects(pending,/Insufficient balance/);
      await blocked(db,b,a); await a.query('commit;'); await rejection;
    }finally{await a.close();await b.close();}
  });
  await fresh('spend wins race, refund sees spend after waiting',async()=>{
    const id=await load(), a=await cluster.connect(), b=await cluster.connect();
    try{
      await a.query(`begin; ${context()} select public.redeem_wallet_for_machine('${user}',1,100,'race');`);
      const pending=b.query(asUser(`select public.request_voluntary_topup_refund(${id})`)); const rejection=assert.rejects(pending,/wallet_used_after_topup/);
      await blocked(db,b,a); await a.query('commit;'); await rejection;
    }finally{await a.close();await b.close();}
  });
  await fresh('duplicate requests serialize to one operation/debit',async()=>{
    const id=await load(), a=await cluster.connect(), b=await cluster.connect();
    try{
      const first=await a.query(`begin; ${context()} select public.request_voluntary_topup_refund(${id});`);
      const pending=b.query(asUser(`select public.request_voluntary_topup_refund(${id})`));
      await blocked(db,b,a); await a.query('commit;'); assert.equal(await pending,first);
      assert.equal(await db.query('select count(*) from private.voluntary_topup_refunds;'),'1');
    }finally{await a.close();await b.close();}
  });
  await fresh('current verified pending-deletion session can refund, ordinary APIs remain denied',async()=>{
    const id=await load(); await call('select public.request_account_deletion()');
    assert.equal((await request(id)).status,'requested'); assert.equal((await call('select public.list_voluntary_topup_refunds()')).length,1);
    assert.equal(await call('select to_json(private.account_access_allowed())'),false);
    await fails('select public.get_loyalty_policy_status()',/account_restricted/);
    await db.query(`delete from auth.sessions where id='${sid}';`);
    await fails('select public.list_voluntary_topup_refunds()',/session_invalid/);
  });
  await fresh('customer cannot approve; Owner needs current AAL2 and active lifecycle',async()=>{
    const r=await request(await load()); await assert.rejects(review(r.id,'approve',user),/owner_required/);
    await fails(`select public.review_voluntary_topup_refund('${r.id}','approve')`,/owner_required/,owner,{aal:'aal1'});
    await call('select public.request_account_deletion()',owner);
    await assert.rejects(review(r.id),/owner_required/);
  });
  await fresh('location scope cannot be overridden; list excludes foreign locations',async()=>{
    const r=await request(await load(2000,"interval '1 minute'",'2'));
    await assert.rejects(review(r.id),/location_forbidden/);
    assert.deepEqual(await call('select public.owner_list_voluntary_topup_refunds()',owner),[]);
    await db.query(`insert into public."Location_to_Admin" values('${owner}',2);`);
    assert.equal((await review(r.id)).status,'approved');
  });
  await fresh('cross-user, banned, unverified and stale sessions fail closed',async()=>{
    const id=await load(); await fails(`select public.request_voluntary_topup_refund(${id})`,/topup_unavailable/,owner);
    await db.query(`update auth.users set email_confirmed_at=null where id='${user}';`);
    await fails(`select public.request_voluntary_topup_refund(${id})`,/account_restricted/);
    await db.query(`update auth.users set email_confirmed_at=now(),banned_until=now()+interval '1 hour' where id='${user}';`);
    await fails(`select public.request_voluntary_topup_refund(${id})`,/account_restricted/);
    await fails('select public.list_voluntary_topup_refunds()',/session_invalid/,user,{exp:0});
  });
  await fresh('clients cannot forge provenance, provider success or directly access private records',async()=>{
    const r=await request(await load());
    await fails(`select public.prepare_voluntary_topup_refund('${r.id}')`,/permission denied/);
    await fails(`select public.reconcile_voluntary_topup_refund('${r.id}','re_fake','succeeded','pi_fake',2000,'usd',false)`,/permission denied/);
    await fails('select * from private.voluntary_topup_refunds',/permission denied/);
    await fails("select public.record_topup_refund_provenance('pi_fake',null,2000,now(),'evt_fake',false)",/permission denied/);
    assert.equal(await db.query("select count(*) from pg_class where relnamespace='private'::regnamespace and relname like '%topup%' and not relrowsecurity and relkind='r';"),'0');
  });
  await fresh('customer top-up list is caller-bound, paginated and available during deletion',async()=>{
    const a=await load(1500), b=await load(1000);
    let page=await call('select public.list_voluntary_topup_refund_topups()');
    assert.deepEqual(page.map(r=>r.load_id),[String(b),String(a)]);
    assert.equal(page[0].ineligible_reason,null);
    assert.deepEqual(await call('select public.list_voluntary_topup_refund_topups()',owner),[]);
    await call('select public.request_account_deletion()');
    await request(a);
    page=await call(`select public.list_voluntary_topup_refund_topups(${b})`);
    assert.equal(page.length,1);assert.equal(page[0].ineligible_reason,'already_requested');
    assert.equal(page[0].refund.customer_id,user);
    assert.equal(await call('select to_json(private.account_access_allowed())'),false);
  });
  await fresh('provider success with DB failure rolls back confirmation, reservation survives and retry completes once',async()=>{
    const r=await request(await load());await review(r.id);const op=await prep(r.id);
    await db.query(`create function public.fixture_refund_failure() returns trigger language plpgsql as $$
      begin raise exception 'synthetic DB failure'; end $$;
      create trigger fixture_refund_failure before update of status on public.wallet_loads
      for each row execute function public.fixture_refund_failure();`);
    await assert.rejects(reconcile(r),/synthetic DB failure/);
    assert.deepEqual(await balance(),[0,0,0]);
    assert.equal(await db.query(`select status from private.voluntary_topup_refunds where id='${r.id}';`),'unknown');
    await db.query('drop trigger fixture_refund_failure on public.wallet_loads; drop function public.fixture_refund_failure();');
    assert.equal((await reconcile(r)).status,'succeeded');
    assert.equal((await reconcile(r,'succeeded',{intent:op.intent})).status,'succeeded');
    assert.deepEqual(await balance(),[0,0,0]);
  });
  await fresh('new funding still settles during reservation and pending deletion, duplicate delivery credits once',async()=>{
    const r=await request(await load());await call('select public.request_account_deletion()');
    await load(1000);
    const intent=await db.query('select stripe_payment_intent_id from public.wallet_loads order by id desc limit 1;');
    await db.query(`select public.record_wallet_load_from_stripe('${user}',1000,'${intent}');`);
    assert.deepEqual(await balance(),[1000,0,1000]);await review(r.id);await reconcile(r);
    assert.deepEqual(await balance(),[1000,0,1000]);
  });
  await fresh('operation cursor retains records sharing a receipt timestamp',async()=>{
    await request(await load(500));await request(await load(500));
    await db.query('update private.voluntary_topup_refunds set requested_at=statement_timestamp();');
    const page=await call('select public.list_voluntary_topup_refunds()');
    const cursor=`'${page[0].requested_at}','${page[0].id}'`;
    const next=await call(`select public.list_voluntary_topup_refunds(${cursor})`);
    assert.equal(next.length,1);assert.equal(next[0].id,page[1].id);
    assert.deepEqual(await call(`select public.owner_list_voluntary_topup_refunds(${cursor})`,owner),next);
  });
});
