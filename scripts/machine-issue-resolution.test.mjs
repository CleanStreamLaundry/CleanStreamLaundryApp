import test from 'node:test';
import assert from 'node:assert/strict';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';
import { installMachineIssueFixture, machineIssueMigration } from './test-support/machine-issue-fixture.mjs';

const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const context = (n=1) => `set local role authenticated;set local request.jwt.claim.sub='';set local request.jwt.claims=${q(JSON.stringify({
  sub:uid(n),session_id:uid(n+10),role:'authenticated',aal:'aal2',exp:Math.floor(Date.now()/1000)+3600,
}))};`;
const statement = (action,payload) => `select public.admin_machine_issue(${q(action)},${q(JSON.stringify(payload))}::jsonb)`;

test('machine issue same-day policy, exact split and sponsored one-benefit reservations', {timeout:180000}, async t => {
  const cluster = await disposableCluster(t,process.env.PG_BIN), db = await cluster.connect();
  const run = async sql => { const connection=await cluster.connect(); try { return await connection.query(sql); } finally { await connection.close(); } };
  const call = (action,payload,n=1) => run(`begin;${context(n)}${statement(action,payload)};commit;`).then(JSON.parse);
  await installMachineIssueFixture(db,{includeMachineIssue:false});
  await db.query(`insert into auth.users(id,email,email_confirmed_at) values
    ('${uid(1)}','owner@example.invalid',now()),('${uid(2)}','manager@example.invalid',now()),('${uid(3)}','customer@example.invalid',now());
    insert into public.profiles(id,roles,email) values('${uid(1)}','Owner','owner@example.invalid'),
      ('${uid(2)}','Admin','manager@example.invalid'),('${uid(3)}','User','customer@example.invalid');
    insert into auth.sessions(id,user_id,aal,factor_id,created_at) select
      ('00000000-0000-4000-8000-'||lpad((n+10)::text,12,'0'))::uuid,
      ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'aal2',
      ('00000000-0000-4000-8000-'||lpad((n+20)::text,12,'0'))::uuid,now() from generate_series(1,3)n;
    insert into auth.mfa_factors(id,user_id,factor_type,status,created_at) select
      ('00000000-0000-4000-8000-'||lpad((n+20)::text,12,'0'))::uuid,
      ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'totp','verified',now()-interval '1 day' from generate_series(1,3)n;
    update public.profiles set loyalty_policy_version=public.get_loyalty_policy_descriptor()->>'required_version',loyalty_policy_accepted_at=now();
    insert into public."Locations"(id,"Name","Address","Latitude","Longitude") values
      (1,'Madison Ave.','5330 Madison ave, Anderson, IN',40.06097,-85.69173),(100,'Synthetic','Unknown',0,0);
    insert into public."Machines"(id,"Location_ID","Name","Machine_type","Price","Status") values
      (101,1,'Original','Dryer',1.5,'idle'),(102,1,'Replacement','Dryer',1.5,'idle'),(103,100,'Other location','Dryer',1.5,'idle');
    update public.cortina_machine_config set is_enabled=true,review_required=false,
      nayax_terminal_id='synthetic-'||machine_id,pulse_line_number=3;
    insert into public.wallet_accounts(id,user_id,status) values('${uid(50)}','${uid(3)}','active');
    insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents)
      values('${uid(50)}','admin_adjustment',10000,8000,2000);
    insert into public.transactions(id,user_id,amount,type,description) values(999,'${uid(3)}',1.5,'laundry','Legacy receipt');
    insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description) values(999,'${uid(3)}',999,1.5,'Previously received');`);
  await db.query(await machineIssueMigration('20261005135004_machine_issue_resolution'));
  let next=1000;
  const claim = async ({old=false,location=101,method='wallet'}={}) => {
    const n=++next, id=uid(n);
    await db.query(`insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,user_id,
      amount_cents,dryer_minutes,pulse_line_number,currency,payment_method,channel,status,transaction_id)
      values('${id}','${uid(n+10000)}','hash-${n}',${location},'${uid(3)}',150,30,3,'USD','${method}','app','payment_pending','synthetic-${n}');
      insert into public.wallet_redemptions(id,wallet_account_id,user_id,machine_id,amount_cents,paid_amount_cents,promo_amount_cents,status,note)
      values(${n},'${uid(50)}','${uid(3)}',${location},150,100,50,'succeeded','Cortina vend ${id}');
      update public.cortina_vend_sessions set wallet_redemption_id=${method==='wallet'?n:'null'},status='started',
        completed_at=${old?"now()-interval '3 days'":"now()"} where id='${id}';`);
    const tx=await db.query(`select id from public.transactions where cortina_vend_session_id='${id}'`);
    const receipt=JSON.parse(await run(`begin;${context(3)}select public.request_cortina_loyalty_credit(${tx},'Machine failed');commit;`));
    return {id:receipt.refund_id,session:id,redemption:n,transaction:Number(tx)};
  };
  const decision = (id,resolution='wallet_refund',extra={}) => ({id,requestId:uid(++next+30000),resolution,note:'Owner verified report at original location',
    atLocation:true,anotherLoadCompleted:resolution==='wallet_refund',...(resolution==='replacement_vend'?{replacementMachineId:102}:{}),...extra});

  await t.test('known exact Anderson identity gets timezone; unknown location does not',async()=>{
    assert.equal(await db.query('select machine_issue_timezone from public."Locations" where id=1'),'America/Indiana/Indianapolis');
    assert.equal(await db.query('select machine_issue_timezone is null from public."Locations" where id=100'),'t');
  });
  await t.test('pre-cutoff receipt remains legacy and its existing approval works',async()=>{
    assert.equal((await call('machineIssueReview',{id:999})).policyVersion,'legacy_14_day');
    const outcome=JSON.parse(await run(`begin;${context()}select public.admin_resolve_credit(999,'approved','Grandfathered');commit;`));
    assert.equal(outcome.status,'approved');
  });
  await t.test('Owner review derives cents, original split/location/date; Manager has no financial access',async()=>{
    const c=await claim(), review=await call('machineIssueReview',{id:c.id});
    assert.equal(review.sameDayEligible,true);assert.equal(review.amountCents,150);
    assert.equal(review.paidAmountCents,100);assert.equal(review.promoAmountCents,50);
    assert.equal(review.locationId,1);assert.deepEqual(review.replacementMachines,[{id:102,name:'Replacement',amountCents:150}]);
    await assert.rejects(call('machineIssueReview',{id:c.id},2),e=>e.code==='PT403');
    await assert.rejects(call('resolveMachineIssue',decision(c.id),2),e=>e.code==='PT403');
  });
  await t.test('late, unknown-location and card claims save receipts and retain manual review',async()=>{
    for(const [input,reason] of [[{old:true},'outside_voluntary_same_day'],[{location:103},'original_location_unknown'],
      [{method:'card'},'external_card_refund_review_required']]) {
      const c=await claim(input), review=await call('machineIssueReview',{id:c.id});
      assert.equal(review.manualReviewReason,reason);assert.equal(review.capabilities.walletRefund,false);
      const p=decision(c.id,'manual_review'), result=await call('resolveMachineIssue',p);
      assert.equal(result.review.receipt.state,'recorded');assert.equal(result.review.status,'pending');
      assert.equal((await call('machineIssueReview',{id:c.id,requestId:p.requestId})).receipt.requestId,p.requestId);
      assert.equal((await call('machineIssueReview',{id:c.id,requestId:uid(9)})).receipt,null);
    }
  });
  await t.test('wallet refund restores exact original split once and rejects changed request reuse',async()=>{
    const c=await claim(), p=decision(c.id), first=await call('resolveMachineIssue',p);
    assert.equal(first.review.receipt.state,'completed');assert.equal((await call('resolveMachineIssue',p)).alreadyResolved,true);
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where refund_request_id=${c.id}`),'1');
    assert.equal(await db.query(`select paid_amount_cents||':'||promo_amount_cents from public.wallet_ledger_entries where refund_request_id=${c.id}`),'100:50');
    await assert.rejects(call('resolveMachineIssue',{...p,note:'Changed'}),e=>e.code==='PT409');
    assert.equal(await db.query(`select public.reverse_cortina_wallet_redemption('${c.session}')`),'f');
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where refund_request_id=${c.id}`),'1');
  });
  await t.test('replacement reserves one exact-price session, no debit, no retry, no other remedy',async()=>{
    const c=await claim(), p=decision(c.id,'replacement_vend');
    const before=await db.query('select count(*) from public.wallet_ledger_entries');
    const first=await call('resolveMachineIssue',p);assert.ok(first.startSessionId);assert.equal(first.review.receipt.state,'pending');
    const replay=await call('resolveMachineIssue',p);assert.equal(replay.startSessionId,undefined);
    assert.equal(await db.query('select count(*) from public.wallet_ledger_entries'),before);
    await assert.rejects(call('resolveMachineIssue',decision(c.id)),e=>e.code==='PT409');
    await db.query(`update public.cortina_vend_sessions set status='started' where id='${first.startSessionId}'`);
    assert.equal((await call('machineIssueReview',{id:c.id,requestId:p.requestId})).receipt.state,'completed');
    assert.equal(await db.query(`select count(*) from public.transactions where cortina_vend_session_id='${first.startSessionId}'`),'0');
    const report=JSON.parse(await db.query(`select r from public.admin_portal_rows('${uid(1)}','transactions') r
      where r->>'id'='vend:${first.startSessionId}'`));
    assert.equal(report.category,'machine_issue_replacement');
    for(const key of ['gross_collection_cents','net_collection_cents','wallet_spend_cents','promo_spend_cents']) {
      assert.equal(report[key],0,key);
    }
    assert.equal(report.operational_vend_cents,150);
    await db.query(`update public.cortina_vend_sessions set status='voided' where id='${c.session}'`);
    assert.equal(await db.query(`select public.reverse_cortina_wallet_redemption('${c.session}')`),'f');
    assert.equal((await call('machineIssueReview',{id:c.id,requestId:p.requestId})).receipt.state,'support_required');
  });
  await t.test('attestation, exact replacement location and new-API enforcement fail closed',async()=>{
    const c=await claim();
    for(const p of [decision(c.id,'wallet_refund',{atLocation:false}),decision(c.id,'wallet_refund',{anotherLoadCompleted:false}),
      decision(c.id,'replacement_vend',{replacementMachineId:103})]) await assert.rejects(call('resolveMachineIssue',p),e=>e.code==='PT409');
    await assert.rejects(run(`begin;${context()}select public.admin_resolve_credit(${c.id},'approved','Bypass');commit;`),e=>e.code==='PT409');
  });
  await t.test('Owner session revoked during wallet wait rolls back receipt and money',async()=>{
    const c=await claim(), holder=await cluster.connect(), waiter=await cluster.connect();
    try {
      await holder.query(`begin;select 1 from public.wallet_accounts where id='${uid(50)}' for update;`);
      const pending=assert.rejects(waiter.query(`begin;${context()}${statement('resolveMachineIssue',decision(c.id))};commit;`),e=>e.code==='PT401');
      await blocked(db,waiter,holder);await db.query(`delete from auth.sessions where id='${uid(11)}'`);
      await holder.query('commit');await pending;
      assert.equal(await db.query(`select count(*) from private.machine_issue_resolutions where refund_id=${c.id}`),'0');
      assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where refund_request_id=${c.id}`),'0');
    } finally { await holder.close();await waiter.close(); }
  });
});
