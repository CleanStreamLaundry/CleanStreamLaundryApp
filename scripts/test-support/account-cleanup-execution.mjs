import assert from 'node:assert/strict';
import { read, uid } from './account-cleanup.mjs';

// Local SQL simulation only. Never an Auth/Storage/provider transport test.
export async function exerciseLifecycle({ db, run, check }) {
  const user = uid(801), restored = uid(802), sid = uid(803), claim = uid(804);
  const version = 'retention-draft-2026-10-01';
  const hash = '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be';
  const q = value => `'${String(value).replaceAll("'", "''")}'`;
  const errorCode = code => error => { assert.equal(error.code, code, error.message); return true; };
  const service = sql => run(`set role service_role; ${sql};`);
  let requested, restoredRequest, wallet, moneyBefore, dispatch;
  const money = async () => {
    const snapshot = {};
    for (const table of ['public.wallet_accounts', 'public.wallet_loads', 'public.wallet_ledger_entries',
      'public.wallet_redemptions', 'public.transactions', 'public."Refunds"', 'private.topup_refund_provenance']) {
      snapshot[table] = await db.query(`select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]') from ${table} r;`);
    }
    return snapshot;
  };
  const step = (id = user, at = requested) => `select public.execute_account_cleanup_step(
    '${claim}','${version}','${hash}','${id}',${q(at)})`;

  await check('lifecycle fixture seeds real wallet funding and linked transaction/refund without provider calls', async () => {
    await run(`set role supabase_auth_admin;
      insert into auth.users(id,email,email_confirmed_at) values
        ('${user}','cleanup-qa@example.invalid',now()),('${restored}','restored-qa@example.invalid',now());
      insert into auth.sessions(id,user_id,aal,created_at) values ('${sid}','${restored}','aal1',clock_timestamp());`);
    await db.query(`insert into public.profiles(id,full_name,reward_tracker)
      values ('${user}','Synthetic cleanup subject',3.50),('${restored}','Synthetic restored subject',0);`);
    wallet = await service(`select public.record_wallet_load_from_stripe('${user}',1700,
      'qa_synthetic_pi',null,'qa_synthetic_charge','qa_synthetic_event')`);
    await db.query(`insert into public.transactions(id,user_id,amount,type,description)
      values (801,'${user}',1.00,'laundry','Synthetic retained transaction');
      insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description)
      values (801,'${user}',801,1.00,'Synthetic retained request');
      insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
        select '${user}',t,t+interval '720 hours' from (select clock_timestamp()-interval '721 hours' t) x;
      insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
        select '${restored}',t,t+interval '720 hours' from (select clock_timestamp()-interval '1 hour' t) x;`);
    requested = await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${user}';`);
    restoredRequest = await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${restored}';`);
    assert.equal(await db.query(`select round(reward_tracker::numeric*100) from public.profiles where id='${user}';`), '50');
    assert.equal(await db.query(`select total_balance_cents from public.wallet_balances where wallet_account_id='${wallet}';`), '2200');
    assert.equal(await db.query('select private.account_cleanup_references_ready();'), 't');
    moneyBefore = await money();
  });

  await check('installed SQL executor refuses unapproved policy without creating jobs or changing money', async () => {
    await assert.rejects(service(step()), error => {
      errorCode('PT503')(error); assert.match(error.message, /cleanup_policy_unapproved/); return true;
    });
    assert.equal(await db.query('select count(*) from private.account_cleanup_jobs;'), '0');
    assert.deepEqual(await money(), moneyBefore);
  });

  await check('actual restore and mismatched request prevent executor dispatch', async () => {
    const jwt = JSON.stringify({ sub: restored, session_id: sid, role: 'authenticated', aal: 'aal1',
      exp: Math.floor(Date.now() / 1000) + 3600 });
    await run(`begin; set local request.jwt.claims=${q(jwt)}; set local request.jwt.claim.sub='';
      set local role authenticated; select public.restore_account(); commit;`);
    assert.equal(await db.query(`select restored_at is not null from private.account_lifecycle where user_id='${restored}';`), 't');
    // Synthetic local authorization/inventory only, never a real policy approval.
    await db.query(`update private.account_cleanup_execution set execution_enabled=true,
      approved_policy_version='${version}',approved_policy_sha256='${hash}',final_policy_approved_at=clock_timestamp();
      insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
        hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
        backup_disposition_reference,financial_retention_reference)
      values ('${user}',${q(requested)},'${restored}',clock_timestamp(),
        'SYNTHETIC-QA-holds','SYNTHETIC-QA-processor','SYNTHETIC-QA-media','SYNTHETIC-QA-backup','SYNTHETIC-QA-financial');`);
    const recovered = JSON.parse(await service(step(restored, restoredRequest)));
    assert.equal(recovered.status, 'held'); assert.equal(recovered.reason, 'claim_unavailable');
    const stale = JSON.parse(await service(`select public.execute_account_cleanup_step('${claim}',
      '${version}','${hash}','${user}',${q(requested)}::timestamptz+interval '1 microsecond')`));
    assert.equal(stale.status, 'held'); assert.equal(stale.reason, 'claim_unavailable');
    assert.equal(await db.query('select count(*) from private.account_cleanup_jobs;'), '0');
    assert.deepEqual(await money(), moneyBefore);
  });

  await check('actual SQL cleanup step dispatches Auth removal for the exact expired request', async () => {
    dispatch = JSON.parse(await service(step()));
    assert.equal(dispatch.status, 'dispatch'); assert.equal(dispatch.action, 'auth');
    assert.equal(dispatch.user_id, user); assert.equal(dispatch.claim_id, claim);
    assert.equal(dispatch.purge_complete, false); assert.match(dispatch.operation_id, /^[0-9a-f-]{36}$/);
    assert.equal(await db.query(`select local_disposed_at is not null and external_operation->>'kind'='auth'
      from private.account_cleanup_jobs where user_id='${user}';`), 't');
    assert.deepEqual(await money(), moneyBefore);
  });

  await check('local Auth deletion simulation runs real fences/cascade and retains financial links and reward', async () => {
    await run(`set role supabase_auth_admin; delete from auth.users where id='${user}';`);
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${user}')
      and not exists(select 1 from public.profiles where id='${user}');`), 't');
    assert.deepEqual(await money(), moneyBefore);
    assert.equal(await db.query(`select retired_at is not null and reward_tracker=0.50
      from private.account_retained_subjects where user_id='${user}';`), 't');
    assert.equal(await db.query(`select count(*) from public.wallet_loads l join public.wallet_accounts w
      on w.id=l.wallet_account_id join private.account_retained_subjects s on s.user_id=l.user_id
      where w.user_id=s.user_id and s.user_id='${user}';`), '1');
    assert.equal(await db.query(`select count(*) from public.transactions t join public."Refunds" r
      on r.transaction_id=t.id join private.account_retained_subjects s on s.user_id=t.user_id
      where r.user_id=s.user_id and s.user_id='${user}';`), '1');
    const receipt = JSON.parse(await service(`select public.acknowledge_account_cleanup('${user}',${q(requested)},
      '${claim}','${dispatch.operation_id}','${version}','${hash}','returned')`));
    assert.equal(receipt.status, 'account_removed'); assert.equal(receipt.purge_complete, false);
    assert.equal(receipt.financial_records_retained, true);
    assert.equal(await db.query(`select auth_removed_at is not null and external_operation is null
      from private.account_cleanup_jobs where user_id='${user}';`), 't');
    assert.equal(await db.query(`select exists(select 1 from auth.users where id='${restored}')
      and exists(select 1 from public.profiles where id='${restored}');`), 't');
  });
}

export async function exercisePopulatedRelations({ db, run, check }) {
  const user = uid(901), other = uid(902), claim = uid(903);
  const version = 'retention-draft-2026-10-01';
  const hash = '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be';
  const q = value => `'${String(value).replaceAll("'", "''")}'`;
  const service = sql => run(`set role service_role; ${sql};`);
  const source = await read('supabase/migrations/20261001130950_retained_financial_subjects.sql');
  const references = [...source.matchAll(/\('([^']+)','([^']+)','([^']+)','([^']+)','([^']+)'\)/g)]
    .map(([, schema, table, column, name]) => ({ relation: `${schema}."${table}"`, column, name }));
  assert.equal(references.length, 12);
  const wallets = {}, refunds = {}, before = new Map();
  let requested, dispatch, financialBefore, unrelatedBefore;
  const rows = (relation, predicate) => db.query(`select coalesce(jsonb_agg(to_jsonb(r)
    order by to_jsonb(r)::text),'[]') from ${relation} r where ${predicate};`);
  const financial = async () => {
    const result = {};
    for (const relation of ['public.wallet_accounts', 'public.wallet_loads', 'public.wallet_redemptions',
      'public.wallet_ledger_entries', 'public.transactions', 'public."Refunds"',
      'public.cortina_vend_sessions', 'private.voluntary_topup_refunds',
      'private.topup_refund_provenance', 'private.topup_refund_spend']) {
      result[relation] = await rows(relation, 'true');
    }
    return result;
  };
  const unrelated = async () => {
    const result = {};
    // Auth is owned by its real fixture role, not the nonsuperuser migration owner.
    result.auth = await run(`set role supabase_auth_admin;
      select to_jsonb(u) from auth.users u where id='${other}';`);
    result.profile = await rows('public.profiles', `id='${other}'`);
    for (const ref of references) result[ref.name] = await rows(ref.relation, `${ref.column}='${other}'`);
    result.ledger = await rows('public.wallet_ledger_entries', `wallet_account_id='${wallets[other]}'`);
    result.provenance = await rows('private.topup_refund_provenance', `load_id in
      (select id from public.wallet_loads where user_id='${other}')`);
    return result;
  };
  const balance = () => db.query(`select jsonb_build_array(paid_balance_cents,promo_balance_cents,
    (select round(reward_tracker*100) from private.account_retained_subjects where user_id='${user}'))
    from public.wallet_balances where wallet_account_id='${wallets[user]}';`).then(JSON.parse);

  await check('populated fixture: both subjects have rows in all twelve switched FK references', async () => {
    assert.equal(await db.query('select rolsuper from pg_roles where rolname=current_user;'), 'f');
    await db.query(`insert into public."Locations"(id) values(901),(902);
      insert into public."Machines"(id,"Location_ID") values(901,901),(902,902);`);
    for (const [index, subject] of [user, other].entries()) {
      const id = 901 + index, session = uid(910 + index), vend = uid(920 + index);
      await run(`set role supabase_auth_admin;
        insert into auth.users(id,email,email_confirmed_at) values('${subject}','populated-${id}@example.invalid',now());
        insert into auth.sessions(id,user_id,aal,created_at) values('${session}','${subject}','aal1',now());`);
      await db.query(`insert into public.profiles(id,full_name,reward_tracker)
        values('${subject}','Synthetic populated subject ${id}',0);`);
      wallets[subject] = await service(`select public.record_wallet_load_from_stripe('${subject}',1500,
        'pi_populated_${id}',null,'ch_populated_${id}','evt_load_${id}')`);
      assert.equal(await service(`select public.record_topup_refund_provenance('pi_populated_${id}',
        '${subject}',1500,clock_timestamp(),'evt_provenance_${id}',false)`), 't');
      const load = await db.query(`select id from public.wallet_loads where stripe_payment_intent_id='pi_populated_${id}';`);
      const jwt = JSON.stringify({ sub: subject, session_id: session, role: 'authenticated', aal: 'aal1',
        exp: Math.floor(Date.now() / 1000) + 3600 });
      refunds[subject] = JSON.parse(await run(`begin; set local request.jwt.claims=${q(jwt)};
        set local request.jwt.claim.sub=''; set local role authenticated;
        select public.request_voluntary_topup_refund(${load}); commit;`)).id;
      // Historical review identity is fixture data; reservation and dispatch preparation
      // still use the installed routines, with every current FK/trigger enabled.
      await db.query(`update private.voluntary_topup_refunds set status='approved',reviewed_by='${subject}',
        reviewed_at=clock_timestamp(),review_note='Synthetic prior reviewer' where id='${refunds[subject]}';`);
      const prepared = JSON.parse(await service(`select public.prepare_voluntary_topup_refund('${refunds[subject]}')`));
      assert.equal(prepared.amount, 1500);
      assert.equal(prepared.may_create, true);
      await service(`select public.record_wallet_load_from_stripe('${subject}',700,'pi_followup_${id}')`);
      await db.query(`insert into public.wallet_redemptions(id,wallet_account_id,user_id,machine_id,
        amount_cents,paid_amount_cents,promo_amount_cents,note)
        values(${id},'${wallets[subject]}','${subject}',${id},100,100,0,'Synthetic retained redemption');
        insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,
          promo_amount_cents,machine_id,created_by,note)
        values('${wallets[subject]}','redeem_paid',-100,-100,0,${id},'${subject}','Synthetic retained creator');
        insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,
          user_id,amount_cents,payment_method,channel,status,transaction_id,wallet_redemption_id)
        values('${vend}','${uid(930 + index)}','synthetic-vend-${id}',${id},'${subject}',100,
          'wallet','app','started','synthetic-vend-${id}',${id});
        insert into public."Refunds"(refund_id,user_id,transaction_id,amount,description)
        select ${id},'${subject}',id,1,'Synthetic retained credit request'
          from public.transactions where cortina_vend_session_id='${vend}';
        insert into private.customer_mfa_recovery(user_id,actor_id,support_case,factor_ids)
        values('${subject}','${uid(802)}','Synthetic retained recovery',array['${uid(940 + index)}'::uuid]);
        insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
          select '${subject}',t,t+interval '720 hours' from (select clock_timestamp()-interval '721 hours' t) x;
        insert into public.admin_invitations(user_id,location_id,invited_by)
        values('${uid(802)}',${id},'${subject}');`);
    }
    for (const ref of references) {
      for (const subject of [user, other]) {
        const snapshot = await rows(ref.relation, `${ref.column}='${subject}'`);
        assert(JSON.parse(snapshot).length > 0, `${ref.name}: populated ${subject}`);
        before.set(`${ref.name}:${subject}`, snapshot);
      }
      assert.equal(await db.query(`select count(*) from pg_constraint c join pg_attribute a
        on a.attrelid=c.conrelid and a.attname='${ref.column}'
        where c.conrelid='${ref.relation}'::regclass and c.conname='${ref.name}'
          and c.confrelid='private.account_retained_subjects'::regclass and c.convalidated
          and not c.condeferrable and c.confdeltype='a' and c.confupdtype='a'
          and c.conkey=array[a.attnum]::smallint[];`), '1', ref.name);
    }
    requested = await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${user}';`);
    financialBefore = await financial();
    unrelatedBefore = await unrelated();
  });

  await check('populated subject dispatch and Auth/profile removal preserve complete financial snapshots', async () => {
    await db.query(`insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
      hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
      backup_disposition_reference,financial_retention_reference)
      values('${user}',${q(requested)},'${uid(802)}',clock_timestamp(),
        'SYNTHETIC-populated-holds','SYNTHETIC-populated-processor','SYNTHETIC-populated-media',
        'SYNTHETIC-populated-backup','SYNTHETIC-populated-financial');`);
    dispatch = JSON.parse(await service(`select public.execute_account_cleanup_step('${claim}',
      '${version}','${hash}','${user}',${q(requested)})`));
    assert.equal(dispatch.status, 'dispatch'); assert.equal(dispatch.action, 'auth');
    await run(`set role supabase_auth_admin; delete from auth.users where id='${user}';`);
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${user}')
      and not exists(select 1 from public.profiles where id='${user}');`), 't');
    assert.deepEqual(await financial(), financialBefore);
    assert.deepEqual(await unrelated(), unrelatedBefore);
    assert.deepEqual(await balance(), [600, 0, 700]);
  });

  for (const ref of references) {
    await check(`populated retention: ${ref.name} preserves nonempty rows and retained-subject links`, async () => {
      const actual = await rows(ref.relation, `${ref.column}='${user}'`);
      assert(JSON.parse(actual).length > 0, ref.name);
      assert.equal(actual, before.get(`${ref.name}:${user}`));
      assert.equal(await db.query(`select count(*) from ${ref.relation} r
        join private.account_retained_subjects s on s.user_id=r.${ref.column}
        where r.${ref.column}='${user}' and s.retired_at is not null;`), String(JSON.parse(actual).length));
      assert.equal(await rows(ref.relation, `${ref.column}='${other}'`), before.get(`${ref.name}:${other}`));
    });
  }

  await check('populated retention: acknowledgements retain vend/load/refund links and unrelated Auth/profile', async () => {
    const receipt = JSON.parse(await service(`select public.acknowledge_account_cleanup('${user}',${q(requested)},
      '${claim}','${dispatch.operation_id}','${version}','${hash}','returned')`));
    assert.equal(receipt.status, 'account_removed');
    assert.equal(receipt.financial_records_retained, true);
    assert.equal(receipt.purge_complete, false);
    assert.deepEqual(await financial(), financialBefore);
    assert.deepEqual(await unrelated(), unrelatedBefore);
    assert.equal(await db.query(`select count(*) from public.transactions t
      join public."Refunds" f on f.transaction_id=t.id and f.user_id=t.user_id
      join public.cortina_vend_sessions v on v.id=t.cortina_vend_session_id and v.user_id=t.user_id
      join public.wallet_redemptions r on r.id=v.wallet_redemption_id and r.user_id=v.user_id
      join public.wallet_accounts w on w.id=r.wallet_account_id and w.user_id=r.user_id
      join private.voluntary_topup_refunds tr on tr.wallet_id=w.id and tr.customer_id=w.user_id
      join public.wallet_loads l on l.id=tr.load_id and l.user_id=tr.customer_id
      join private.topup_refund_provenance p on p.load_id=l.id where t.user_id='${user}';`), '1');
  });

  await check('profile absent: installed funding/provenance routines apply late paid load and reward threshold', async () => {
    assert.equal(await service(`select public.record_wallet_load_from_stripe('${user}',2400,
      'pi_late_populated',null,'ch_late_populated','evt_late_populated')`), wallets[user]);
    assert.deepEqual(await balance(), [3000, 500, 1100]);
    const late = JSON.parse(await db.query(`select jsonb_build_array(l.amount_cents,l.paid_amount_cents,
      l.promo_amount_cents,p.reward_before_cents,l.user_id,l.wallet_account_id)
      from public.wallet_loads l join private.topup_refund_provenance p on p.load_id=l.id
      where l.stripe_payment_intent_id='pi_late_populated';`));
    assert.deepEqual(late, [2400, 2400, 500, 700, user, wallets[user]]);
    assert.equal(await service(`select public.record_topup_refund_provenance('pi_late_populated','${user}',
      2400,clock_timestamp(),'evt_late_success',false)`), 't');
    assert.deepEqual(await unrelated(), unrelatedBefore);
  });

  await check('profile absent: installed refund reconciliation releases reservation with cumulative reward arithmetic once', async () => {
    const reconcile = () => service(`select public.reconcile_voluntary_topup_refund('${refunds[user]}',
      're_populated_failed','failed','pi_populated_901',1500,'usd',false)`);
    assert.equal(JSON.parse(await reconcile()).status, 'failed');
    assert.deepEqual(await balance(), [4500, 1000, 600]);
    assert.equal(await db.query(`select released_at is not null and reviewed_by='${user}' and customer_id='${user}'
      from private.voluntary_topup_refunds where id='${refunds[user]}';`), 't');
    assert.deepEqual(JSON.parse(await db.query(`select jsonb_agg(jsonb_build_array(amount_cents,
      paid_amount_cents,promo_amount_cents) order by id) from public.wallet_ledger_entries
      where voluntary_topup_refund_id='${refunds[user]}';`)), [[-1500, -1500, 0], [2000, 1500, 500]]);
    const settled = await financial();
    assert.equal(JSON.parse(await reconcile()).status, 'failed');
    assert.equal(await service(`select public.record_wallet_load_from_stripe('${user}',2400,
      'pi_late_populated',null,'ch_late_populated','evt_late_populated')`), wallets[user]);
    assert.deepEqual(await financial(), settled);
    assert.deepEqual(await balance(), [4500, 1000, 600]);
    assert.deepEqual(await unrelated(), unrelatedBefore);
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${user}')
      and not exists(select 1 from public.profiles where id='${user}');`), 't');
  });
}
