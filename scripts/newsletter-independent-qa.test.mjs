import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const uid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const user=uid(1),other=uid(2),sid=uid(11),freshSid=uid(13),factor=uid(21);
const q=v=>`'${String(v).replaceAll("'","''")}'`;
const jwt=(extra={})=>({sub:user,session_id:sid,role:'authenticated',aal:'aal1',exp:Math.floor(Date.now()/1000)+3600,...extra});
const context=(extra={},role='authenticated')=>`set local role ${role};set local request.jwt.claim.sub='';set local request.jwt.claims=${q(JSON.stringify(jwt(extra)))};`;
const request="select public.newsletter_request(true,'newsletter-v1','signup')";
const paths=[
  'supabase/tests/loyalty_policy_acceptance.fixture.sql',
  'supabase/migrations/20260929223124_protect_profile_authority.sql',
  'supabase/migrations/20260929234955_loyalty_policy_acceptance.sql',
  'supabase/tests/account_admission.fixture.sql',
  'supabase/migrations/20260930005456_account_admission.sql',
  'supabase/tests/profile_terms_admission.fixture.sql',
  'supabase/migrations/20260930013417_enforce_profile_terms_admission.sql',
  'supabase/tests/account_lifecycle.fixture.sql',
  'supabase/migrations/20260930063923_recoverable_account_deletion.sql',
  'supabase/tests/newsletter.fixture.sql',
  'supabase/migrations/20260930125527_newsletter_consent_mail_outbox.sql',
  'supabase/migrations/20261001140307_mail_transactional_postal_split.sql',
];

test('independent email QA: canonical actor, delivery uncertainty and lifecycle overlap', {timeout:180000},async t=>{
  const cluster=await disposableCluster(t,process.env.PG_BIN), db=await cluster.connect();
  for(const path of paths)await db.query(await readFile(new URL(`../${path}`,import.meta.url),'utf8'));
  const run=async sql=>{const c=await cluster.connect();try{return await c.query(sql);}finally{await c.close();}};
  const call=async(sql,extra={},role='authenticated')=>JSON.parse(await run(`begin;${context(extra,role)}${sql};commit;`)||'null');
  const reset=()=>db.query(`truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,private.mail_suppression,private.account_lifecycle;
    truncate auth.users cascade;update private.mail_settings set enabled=false,rollout_at=now()-interval '1 hour';
    insert into auth.users(id,email,email_confirmed_at,created_at) values('${user}','member@example.test',now(),now()-interval '1 day'),('${other}','other@example.test',now(),now()-interval '1 day');
    insert into auth.sessions(id,user_id,aal,created_at) values('${sid}','${user}','aal1',now()-interval '1 hour');
    update private.mail_settings set enabled=true;`);
  const fresh=(name,fn)=>t.test(name,async()=>{await reset();await fn();});

  await fresh('P1 regression: restore must recheck deadline after email-trigger lock wait',async()=>{
    await call('select public.request_account_deletion()');
    await db.query(`update private.account_lifecycle set
      deletion_requested_at=statement_timestamp()-interval '720 hours'+interval '1 second',
      restore_until=statement_timestamp()+interval '1 second';`);
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values('${freshSid}','${user}','aal1',clock_timestamp());`);
    const holder=await cluster.connect(),waiter=await cluster.connect();
    try{
      await holder.query('begin;select private.mail_lock();');
      const outcome=waiter.query(`begin;${context({session_id:freshSid})}select public.restore_account();commit;`).then(value=>({value}),error=>({error}));
      await blocked(db,waiter,holder);
      await db.query('select pg_sleep(1.1);');
      await holder.query('commit;');
      const result=await outcome;
      t.diagnostic(JSON.stringify({restoreResponse:result.value,error:result.error?.message,
        lifecycle:JSON.parse(await db.query(`select jsonb_build_object('restored_at',restored_at,'restore_until',restore_until,
          'observed_at',clock_timestamp(),'deadline_expired',clock_timestamp()>=restore_until) from private.account_lifecycle where user_id='${user}';`))}));
      assert.equal(result.error?.code,'PT403','Restoration must reject after the suppression-trigger wait crosses its deadline');
      assert.match(result.error.message,/restore_expired/);
    }finally{await holder.close();await waiter.close();}
  });

  await fresh('P1 regression: restore must recheck fresh-session age after email-trigger lock wait',async()=>{
    await call('select public.request_account_deletion()');
    await db.query(`update private.account_lifecycle set deletion_requested_at=statement_timestamp()-interval '1 day',
      restore_until=statement_timestamp()+interval '29 days';
      insert into auth.sessions(id,user_id,aal,created_at) values('${freshSid}','${user}','aal1',clock_timestamp()-interval '10 minutes'+interval '1 second');`);
    const holder=await cluster.connect(),waiter=await cluster.connect();
    try{
      await holder.query('begin;select private.mail_lock();');
      const outcome=waiter.query(`begin;${context({session_id:freshSid})}select public.restore_account();commit;`).then(value=>({value}),error=>({error}));
      await blocked(db,waiter,holder);await db.query('select pg_sleep(1.1);');await holder.query('commit;');
      const result=await outcome;
      t.diagnostic(JSON.stringify({restoreResponse:result.value,error:result.error?.message,
        sessionAgeSeconds:await db.query(`select extract(epoch from clock_timestamp()-created_at) from auth.sessions where id='${freshSid}';`)}));
      assert.equal(result.error?.code,'PT403','Restoration must reject when current session reaches ten minutes during suppression wait');
      assert.match(result.error.message,/fresh_session_required/);
    }finally{await holder.close();await waiter.close();}
  });

  await fresh('control: restore crossing deadline while waiting for profile still rejects',async()=>{
    await call('select public.request_account_deletion()');
    await db.query(`update private.account_lifecycle set deletion_requested_at=statement_timestamp()-interval '720 hours'+interval '1 second',
      restore_until=statement_timestamp()+interval '1 second';
      insert into auth.sessions(id,user_id,aal,created_at) values('${freshSid}','${user}','aal1',clock_timestamp());`);
    const holder=await cluster.connect(),waiter=await cluster.connect();
    try{
      await holder.query(`begin;select id from public.profiles where id='${user}' for no key update;`);
      const outcome=waiter.query(`begin;${context({session_id:freshSid})}select public.restore_account();commit;`).catch(error=>error);
      await blocked(db,waiter,holder);await db.query('select pg_sleep(1.1);');await holder.query('commit;');
      const result=await outcome;assert.equal(result.code,'PT403');assert.match(result.message,/restore_expired/);
      assert.equal(await db.query('select restored_at is null from private.account_lifecycle;'),'t');
    }finally{await holder.close();await waiter.close();}
  });

  await fresh('P1 regression: current MFA revocation during email-trigger wait must roll back restore',async()=>{
    await db.query(`insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${user}','totp','verified');
      update public.profiles set roles='Owner' where id='${user}';
      update auth.sessions set aal='aal2',factor_id='${factor}' where id='${sid}';`);
    await call('select public.request_account_deletion()',{aal:'aal2'});
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at,factor_id)
      values('${freshSid}','${user}','aal2',clock_timestamp(),'${factor}');`);
    const holder=await cluster.connect(),waiter=await cluster.connect();
    try{
      await holder.query('begin;select private.mail_lock();');
      const outcome=waiter.query(`begin;${context({session_id:freshSid,aal:'aal2'})}select public.restore_account();commit;`).then(value=>({value}),error=>({error}));
      await blocked(db,waiter,holder);await db.query(`update auth.mfa_factors set status='unverified' where id='${factor}';`);
      await holder.query('commit;');const result=await outcome;
      const restored=await db.query('select restored_at is not null from private.account_lifecycle;');
      t.diagnostic(JSON.stringify({restoreResponse:result.value,error:result.error?.message,restored}));
      assert.equal(restored,'f','Loss of required current MFA must not commit restoration');
      assert.equal(result.error?.code,'PT403');
    }finally{await holder.close();await waiter.close();}
  });

  for(const action of ['request','withdraw']) for(const change of ['delete_session','reassign_session','revoke_totp']) {
    await fresh(`${action} rechecks ${change} after waiting for mail lock`,async()=>{
      if(action==='withdraw')await call(request);
      const extra=change==='revoke_totp'?{aal:'aal2'}:{};
      if(change==='revoke_totp')await db.query(`insert into auth.mfa_factors(id,user_id,factor_type,status)
        values('${factor}','${user}','totp','verified');update public.profiles set roles='Owner' where id='${user}';
        update auth.sessions set aal='aal2',factor_id='${factor}' where id='${sid}';`);
      const before=await db.query('select coalesce(jsonb_agg(to_jsonb(c)),\'[]\') from private.newsletter_consent c;');
      const holder=await cluster.connect(),waiter=await cluster.connect();
      try{
        await holder.query('begin;select private.mail_lock();');
        const outcome=waiter.query(`begin;${context(extra)}${action==='request'?request:'select public.newsletter_withdraw()'};commit;`).catch(error=>error);
        await blocked(db,waiter,holder);
        await db.query(change==='delete_session'?`delete from auth.sessions where id='${sid}';`:
          change==='reassign_session'?`update auth.sessions set user_id='${other}' where id='${sid}';`:
            `update auth.mfa_factors set status='unverified' where id='${factor}';`);
        await holder.query('commit;');
        assert.equal((await outcome).code,change==='revoke_totp'?'PT403':'PT401');
        assert.equal(await db.query('select coalesce(jsonb_agg(to_jsonb(c)),\'[]\') from private.newsletter_consent c;'),before);
      }finally{await holder.close();await waiter.close();}
    });
  }

  await fresh('restore with session invalidated during suppression wait rolls back',async()=>{
    await call('select public.request_account_deletion()');
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values('${freshSid}','${user}','aal1',clock_timestamp());`);
    const holder=await cluster.connect(),waiter=await cluster.connect();
    try{
      await holder.query('begin;select private.mail_lock();');
      const outcome=waiter.query(`begin;${context({session_id:freshSid})}select public.restore_account();commit;`).catch(error=>error);
      await blocked(db,waiter,holder);await db.query(`delete from auth.sessions where id='${freshSid}';`);await holder.query('commit;');
      assert.equal((await outcome).code,'PT401');
      assert.equal(await db.query('select restored_at is null from private.account_lifecycle;'),'t');
    }finally{await holder.close();await waiter.close();}
  });

  const hash='a'.repeat(64),unsub='b'.repeat(64),payload='c'.repeat(64);
  const service=sql=>call(sql,{},'service_role');
  const claim=()=>service('select public.mail_claim()');
  const prepare=o=>run(`begin;${context({},'service_role')}select public.mail_prepare('${o.id}','${o.lease_id}','${payload}','${hash}','${unsub}');commit;`);
  const finish=(o,result,id='null')=>run(`begin;${context({},'service_role')}select public.mail_finish('${o.id}','${o.lease_id}','${result}',${id});commit;`);
  const webhook=(o,event,type)=>run(`begin;${context({},'service_role')}select public.mail_record_webhook('${event}','provider-1','${type}','${o.id}','${o.email}');commit;`);
  const sending=async()=>{await call(request);const o=await claim();assert.equal(await prepare(o),'t');return o;};

  await fresh('unknown dispatch, deletion, restore and late callbacks never restore consent or resend',async()=>{
    const o=await sending();await finish(o,'uncertain');await call('select public.request_account_deletion()');
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values('${freshSid}','${user}','aal1',clock_timestamp());`);
    await call('select public.restore_account()',{session_id:freshSid});
    for(const sql of ['select public.newsletter_status()',request,'select public.newsletter_withdraw()']) {
      await assert.rejects(call(sql),error=>error.code==='PT401');
    }
    assert.equal((await call('select public.newsletter_status()',{session_id:freshSid})).state,'suppressed');
    await assert.rejects(call(request,{session_id:freshSid}),error=>error.code==='PT403');
    await webhook(o,'late-delivered','email.delivered');await finish(o,'accepted',"'provider-1'");
    assert.equal(await db.query(`select state||'|'||provider_id from private.mail_outbox where id='${o.id}';`),'suppressed|provider-1');
    assert.equal(await claim(),null);
    await assert.rejects(service(`select public.newsletter_token('confirm','${hash}')`),error=>error.code==='PT400');
    assert.equal(await db.query('select count(*) from private.mail_outbox;'),'1');
  });

  await fresh('provider acknowledgement loss beyond 24h stays quarantined, signed evidence still reconciles',async()=>{
    const o=await sending();
    await db.query("update private.mail_outbox set first_attempt_at=now()-interval '25 hours',lease_until=now()-interval '24 hours';");
    assert.equal(await claim(),null);assert.equal(await db.query('select state from private.mail_outbox;'),'uncertain');
    await webhook(o,'delayed-delivery','email.delivered');await finish(o,'uncertain');
    assert.equal(await db.query('select state from private.mail_outbox;'),'delivered');assert.equal(await claim(),null);
  });

  await fresh('address change between lease and prepare prevents send after changing back',async()=>{
    await call(request);const o=await claim();
    await db.query(`update auth.users set email='changed@example.test' where id='${user}';
      update auth.users set email='member@example.test' where id='${user}';`);
    assert.equal(await prepare(o),'f');assert.equal(await claim(),null);
    assert.equal((await call('select public.newsletter_status()')).state,'unsubscribed');
  });

  await fresh('two users and stale worker leases cannot rebind or release an uncertain job',async()=>{
    const o=await sending();await finish(o,'uncertain');
    await run(`begin;${context({},'service_role')}select public.mail_finish('${o.id}','${uid(99)}','rate_limited',null);commit;`);
    assert.equal(await db.query('select state from private.mail_outbox;'),'uncertain');
    await assert.rejects(run(`begin;${context({},'service_role')}select public.mail_record_webhook('wrong-recipient','provider-1','email.delivered','${o.id}','other@example.test');commit;`),error=>error.code==='PT503');
    assert.equal(await db.query('select count(*) from private.mail_webhook_event;'),'0');
    assert.equal(await claim(),null);
  });
});
