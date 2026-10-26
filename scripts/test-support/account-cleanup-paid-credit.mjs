import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { read, uid } from './account-cleanup.mjs';
import { blocked } from './policy-admission-pg.mjs';

const version = 'retention-paid-credit-2026-10-02';
const hash = '756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592';
const policy = `'${version}','${hash}'`;
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const errorCode = code => error => { assert.equal(error.code, code, error.message); return true; };

// Local PostgreSQL/Auth-delete simulation only. No provider calls, hosted
// configuration, real identity verification or cleanup activation.
export async function exercisePaidCreditPreservation({ db, run, check, cluster }) {
  const service = sql => run(`set role service_role; ${sql};`);
  const rows = (table, where) => db.query(`select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]')
    from ${table} r where ${where};`);
  const auth = (p, aal = 'aal1') => `set local request.jwt.claims=${q(JSON.stringify({ sub: p.subject,
    session_id: p.session, role: 'authenticated', aal, exp: Math.floor(Date.now() / 1000) + 3600 }))};
    set local request.jwt.claim.sub=''; set local role authenticated;`;
  const human = (p, sql, aal) => run(`begin; ${auth(p, aal)} ${sql}; commit;`);
  const person = async (n, role = 'User') => {
    const p = { subject: uid(n), session: uid(n + 10000), claim: uid(n + 20000) };
    await run(`set role supabase_auth_admin;
      insert into auth.users(id,email,email_confirmed_at) values('${p.subject}','credit-${n}@example.invalid',now());
      insert into auth.sessions(id,user_id,aal,created_at) values('${p.session}','${p.subject}','aal1',clock_timestamp());`);
    await db.query(`insert into public.profiles(id,email,full_name,roles,reward_tracker)
      values('${p.subject}','credit-${n}@example.invalid','Synthetic retained-credit subject','${role}',0);`);
    return p;
  };
  const load = async (p, cents, reference) => {
    p.wallet = await service(`select public.record_wallet_load_from_stripe('${p.subject}',${cents},${q(reference)})`);
    return db.query(`select id from public.wallet_loads where stripe_payment_intent_id=${q(reference)};`);
  };
  const pending = async (p, age = '721 hours') => {
    await db.query(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
      select '${p.subject}',t,t+interval '720 hours' from (select clock_timestamp()-interval '${age}' t) x;
      insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
        hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
        backup_disposition_reference,financial_retention_reference)
      select user_id,deletion_requested_at,'${uid(802)}',clock_timestamp(),
        'SYNTHETIC-credit-holds','SYNTHETIC-credit-processors','SYNTHETIC-credit-media',
        'SYNTHETIC-credit-backups','SYNTHETIC-credit-claim-evidence'
        from private.account_lifecycle where user_id='${p.subject}';`);
    p.requested = await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${p.subject}';`);
  };
  const step = p => `select public.execute_account_cleanup_step('${p.claim}',${policy},'${p.subject}',${q(p.requested)})`;
  const balance = p => db.query(`select jsonb_build_array(paid_balance_cents,promo_balance_cents)
    from public.wallet_balances where wallet_account_id='${p.wallet}';`).then(JSON.parse);
  const retire = async p => {
    p.dispatch = JSON.parse(await service(step(p)));
    assert.equal(p.dispatch.status, 'dispatch'); assert.equal(p.dispatch.action, 'auth');
    await run(`set role supabase_auth_admin; delete from auth.users where id='${p.subject}';`);
    const ack = JSON.parse(await service(`select public.acknowledge_account_cleanup('${p.subject}',${q(p.requested)},
      '${p.claim}','${p.dispatch.operation_id}',${policy},'returned')`));
    assert.equal(ack.status, 'account_removed'); assert.equal(ack.financial_records_retained, true);
    assert.equal(ack.purge_complete, false);
  };
  const reserve = async (p, amount, reference) => {
    const id = await load(p, amount, reference);
    assert.equal(await service(`select public.record_topup_refund_provenance(${q(reference)},'${p.subject}',
      ${amount},clock_timestamp(),${q(`evt_${reference}`)},false)`), 't');
    const refund = JSON.parse(await human(p, `select public.request_voluntary_topup_refund(${id})`));
    await db.query(`update private.voluntary_topup_refunds set status='approved',reviewed_at=clock_timestamp(),
      review_note='Synthetic already-approved refund' where id='${refund.id}';`);
    assert.equal(JSON.parse(await service(`select public.prepare_voluntary_topup_refund('${refund.id}')`)).may_create, true);
    return refund.id;
  };
  let p, active, owner, admin, refund, beforeLedger, beforeLoads, beforeRefund;

  await check('paid credit: new policy identity is shared and installation never enables cleanup', async () => {
    const contract = 'retention-paid-credit-2026-10-02|restore=30-days-explicit|delete=auth-profile|paid=no-expiry-no-forfeiture|promo=cancel-at-final-deletion|unresolved=retain|reclaim=verified-owner-support';
    assert.equal(createHash('sha256').update(contract).digest('hex'), hash);
    // Historical SQL policy remains immutable. Current worker/scheduler pins
    // are checked by the ninety-day migration suite instead.
    const historical = await read('supabase/migrations/20261002211306_bounded_deletion_preserve_paid_credit.sql');
    assert(historical.includes(contract)); assert(historical.includes(hash));
    assert.equal(await db.query(`select not execution_enabled and not credit_forfeiture_enabled
      and approved_policy_version is null from private.account_cleanup_execution;`), 't');
    await assert.rejects(service(`select public.execute_account_cleanup_step('${uid(25001)}',${policy})`), errorCode('PT503'));
    await db.query(`update private.account_cleanup_execution set execution_enabled=true,
      approved_policy_version='${version}',approved_policy_sha256='${hash}',final_policy_approved_at=clock_timestamp();`);
    await assert.rejects(service(`select public.execute_account_cleanup_step('${uid(25001)}',
      'retention-draft-2026-10-01','3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be')`), errorCode('PT503'));
    for (const role of ['anon', 'authenticated', 'service_role', 'supabase_auth_admin']) {
      for (const signature of ['private.cancel_retired_account_promo(uuid)',
        'private.cancel_account_promo_on_retirement()', 'private.cancel_retired_account_late_promo()']) {
        assert.equal(await db.query(`select has_function_privilege('${role}','${signature}','execute');`), 'f');
      }
    }
  });

  await check('paid credit: live reward rate and pending refund reservation remain unchanged', async () => {
    p = await person(5001); active = await person(5002);
    refund = await reserve(p, 1500, 'pi_credit_reserved');
    await load(p, 2400, 'pi_credit_before_delete');
    await load(active, 2400, 'pi_credit_active_control');
    assert.deepEqual(await balance(p), [2400, 500]);
    assert.deepEqual(await balance(active), [2400, 500]);
    assert.equal(await db.query(`select round(reward_tracker*100) from public.profiles where id='${p.subject}';`), '400');
    await pending(p);
    // A financial hold preserves the obligation, not login credentials.
    await db.query(`insert into private.account_retention_holds(user_id,data_class,authority,purpose,custodian,review_at)
      values('${p.subject}','financial','SYNTHETIC','Open paid-credit claim','${uid(802)}',clock_timestamp()+interval '3 months');`);
    beforeLedger = await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`);
    beforeLoads = await rows('public.wallet_loads', `wallet_account_id='${p.wallet}'`);
    beforeRefund = await rows('private.voluntary_topup_refunds', `id='${refund}'`);
  });

  await check('paid credit: final deletion removes Auth/profile and only appends free-credit cancellation', async () => {
    await retire(p);
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${p.subject}')
      and not exists(select 1 from public.profiles where id='${p.subject}');`), 't');
    assert.deepEqual(await balance(p), [2400, 0]);
    assert.equal(await db.query(`select retired_at is not null and reward_tracker=0
      from private.account_retained_subjects where user_id='${p.subject}';`), 't');
    assert.equal(await db.query(`select status from public.wallet_accounts where id='${p.wallet}';`), 'deleted');
    assert.equal(await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}' and entry_type<>'deletion_promo_cancellation'`), beforeLedger);
    assert.equal(await rows('public.wallet_loads', `wallet_account_id='${p.wallet}'`), beforeLoads);
    assert.equal(await rows('private.voluntary_topup_refunds', `id='${refund}'`), beforeRefund);
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries
      where wallet_account_id='${p.wallet}' and entry_type='deletion_promo_cancellation'
        and paid_amount_cents=0 and promo_amount_cents=-500;`), '1');
    assert.equal(await db.query(`select count(*) from private.topup_refund_spend where wallet_id='${p.wallet}';`), '0');
    assert.deepEqual(await balance(active), [2400, 500]);
    await assert.rejects(human(p, 'select public.restore_account()'), errorCode('PT401'));
  });

  await check('paid credit: repeated retirement/acknowledgement cannot cancel twice', async () => {
    const before = await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`);
    await run(`set role supabase_auth_admin; delete from auth.users where id='${p.subject}';`);
    await db.query(`select private.cancel_retired_account_promo('${p.wallet}');`);
    await assert.rejects(service(`select public.acknowledge_account_cleanup('${p.subject}',${q(p.requested)},
      '${p.claim}','${p.dispatch.operation_id}',${policy},'inspected')`), errorCode('PT409'));
    assert.equal(await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`), before);
  });

  await check('paid credit: a century-old cleanup receipt expires without erasing principal or an unknown refund', async () => {
    const ledger = await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`);
    await db.query(`begin;
      update private.account_cleanup_jobs set auth_removed_at=clock_timestamp()-interval '100 years',
        redaction_xid=pg_current_xact_id() where user_id='${p.subject}';
      select private.expire_account_cleanup_metadata('${p.subject}'); commit;`);
    for (const table of ['private.account_cleanup_jobs', 'private.account_cleanup_inventory', 'private.account_lifecycle']) {
      assert.equal(await rows(table, `user_id='${p.subject}'`), '[]');
    }
    assert.equal(await db.query(`select financial_retention_reference from private.account_retained_subjects
      where user_id='${p.subject}';`), 'SYNTHETIC-credit-claim-evidence');
    assert.equal(await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`), ledger);
    assert.equal(await rows('public.wallet_loads', `wallet_account_id='${p.wallet}'`), beforeLoads);
    assert.equal(await rows('private.voluntary_topup_refunds', `id='${refund}'`), beforeRefund);
    assert.deepEqual(await balance(p), [2400, 0]);
  });

  await check('paid credit: late funding retains all principal with zero new promo/progress and idempotent delivery', async () => {
    const id = await load(p, 2600, 'pi_credit_late');
    assert.deepEqual(await balance(p), [5000, 0]);
    assert.equal(await db.query(`select reward_tracker from private.account_retained_subjects where user_id='${p.subject}';`), '0');
    assert.equal(await db.query(`select promo_amount_cents from public.wallet_loads where id=${id};`), '0');
    assert.equal(await db.query(`select reward_before_cents from private.topup_refund_provenance where load_id=${id};`), '0');
    const before = await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`);
    assert.equal(await load(p, 2600, 'pi_credit_late'), id);
    assert.equal(await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`), before);
  });

  await check('paid credit: failed pending refund restores reserved principal once without reviving free rewards', async () => {
    const reconcile = () => service(`select public.reconcile_voluntary_topup_refund('${refund}',
      're_credit_failed','failed','pi_credit_reserved',1500,'usd',false)`);
    assert.equal(JSON.parse(await reconcile()).status, 'failed');
    assert.deepEqual(await balance(p), [6500, 0]);
    const before = await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`);
    assert.equal(JSON.parse(await reconcile()).status, 'failed');
    assert.equal(await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`), before);
    assert.equal(await db.query(`select reward_tracker from private.account_retained_subjects where user_id='${p.subject}';`), '0');
  });

  await check('paid credit: late mixed reversal keeps its evidence and paid part while cancelling only promo', async () => {
    await db.query(`insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,
      paid_amount_cents,promo_amount_cents,note)
      values('${p.wallet}','void',300,100,200,'Synthetic delayed mixed reversal');`);
    assert.deepEqual(await balance(p), [6600, 0]);
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where wallet_account_id='${p.wallet}'
      and entry_type='void' and paid_amount_cents=100 and promo_amount_cents=200;`), '1');
    assert.equal(await db.query(`select count(*) from private.topup_refund_spend where wallet_id='${p.wallet}';`), '0');
    await assert.rejects(run(`set role postgres; insert into public.wallet_ledger_entries(wallet_account_id,
      entry_type,amount_cents,paid_amount_cents,promo_amount_cents)
      values('${p.wallet}','deletion_promo_cancellation',-200,-100,-100);`), errorCode('23514'));
  });

  await check('paid credit: original-method successful refund after deletion keeps its reservation debit and history', async () => {
    const success = await person(5003);
    const id = await reserve(success, 2000, 'pi_credit_success');
    await load(success, 500, 'pi_credit_success_other');
    await pending(success); await retire(success);
    const before = await balance(success);
    const result = JSON.parse(await service(`select public.reconcile_voluntary_topup_refund('${id}',
      're_credit_success','succeeded','pi_credit_success',2000,'usd',false)`));
    assert.equal(result.status, 'succeeded'); assert.deepEqual(before, [500, 0]);
    assert.deepEqual(await balance(success), before);
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where voluntary_topup_refund_id='${id}'
      and paid_amount_cents=-2000 and stripe_refund_id='re_credit_success';`), '1');
  });

  await check('paid credit: existing Owner tools find a retired wallet by receipt without copying identity', async () => {
    owner = await person(5004, 'Owner'); admin = await person(5005, 'Admin');
    for (const staff of [owner, admin]) {
      const factor = uid(Number(staff.subject.slice(-12)) + 30000);
      await run(`set role supabase_auth_admin;
        insert into auth.mfa_factors(id,user_id,factor_type,status,created_at)
          values('${factor}','${staff.subject}','totp','verified',clock_timestamp()-interval '1 day');
        update auth.sessions set aal='aal2',factor_id='${factor}' where id='${staff.session}';`);
    }
    const search = `select public.admin_wallet_read('search','{"query":"pi_credit_before_delete"}')`;
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${p.subject}')
      and not exists(select 1 from public.profiles where id='${p.subject}')
      and not exists(select 1 from private.account_lifecycle where user_id='${p.subject}');`), 't');
    const result = JSON.parse(await human(owner, search, 'aal2'));
    assert.equal(result.items.length, 1); assert.equal(result.items[0].wallet_account_id, p.wallet);
    assert.equal(result.items[0].user_id, p.subject); assert.equal(result.items[0].paid_balance_cents, 6600);
    const detail = JSON.parse(await human(owner,
      `select public.admin_wallet_read('detail','{"walletId":"${p.wallet}"}')`, 'aal2'));
    assert.equal(detail.balance.promo_balance_cents, 0); assert(detail.loads.length > 0); assert(detail.ledger.length > 0);
    assert(detail.loads.some(l => l.stripe_payment_intent_id === 'pi_credit_before_delete'
      && l.user_id === p.subject && l.paid_amount_cents === 2400));
    for (const reference of [p.wallet, p.subject]) {
      const byId = JSON.parse(await human(owner,
        `select public.admin_wallet_read('search',${q(JSON.stringify({ query: reference }))}::jsonb)`, 'aal2'));
      assert.equal(byId.items.length, 1); assert.equal(byId.items[0].wallet_account_id, p.wallet);
    }
    await assert.rejects(human(admin, search, 'aal2'), errorCode('PT403'));
    await assert.rejects(human(active, search), errorCode('PT403'));
    assert.equal(await db.query(`select count(*) from information_schema.columns where table_schema='private'
      and table_name='account_retained_subjects' and column_name in ('email','full_name','phone','password');`), '0');
    const replacement = await person(5006);
    await run(`set role supabase_auth_admin; update auth.users set email='credit-5001@example.invalid' where id='${replacement.subject}';`);
    await load(replacement, 100, 'pi_credit_new_identity');
    assert.notEqual(replacement.wallet, p.wallet);
    assert.deepEqual(await balance(replacement), [100, 0]); assert.deepEqual(await balance(p), [6600, 0]);
  });

  await check('paid credit: existing Owner can record an explicit remedy without restoring or rebinding the deleted account', async () => {
    const ledger = await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`);
    const remedy = `select public.admin_record_legal_cash_redemption('${p.wallet}',100,null,
      'SYNTHETIC support case: ownership proof reviewed; manual remedy recorded, no provider payout')`;
    await assert.rejects(human(admin, remedy, 'aal2'), errorCode('PT403'));
    await assert.rejects(human(active, remedy), errorCode('PT403'));
    const proof = await cluster.connect();
    try {
      await proof.query(`begin; ${auth(owner, 'aal2')}`);
      const entryId = await proof.query(remedy);
      const detail = JSON.parse(await proof.query(
        `select public.admin_wallet_read('detail','{"walletId":"${p.wallet}"}');`));
      assert.equal(detail.balance.user_id, p.subject); assert.equal(detail.balance.status, 'deleted');
      assert.equal(detail.balance.paid_balance_cents, 6500); assert.equal(detail.balance.promo_balance_cents, 0);
      const entry = detail.ledger.find(e => String(e.id) === entryId);
      assert(entry); assert.equal(entry.created_by, owner.subject);
      assert.equal(entry.entry_type, 'legal_cash_redemption'); assert.equal(entry.paid_amount_cents, -100);
      assert.equal(entry.promo_amount_cents, 0); assert.equal(entry.stripe_refund_id, null);
      assert.match(entry.note, /SYNTHETIC support case/);
      assert.deepEqual(detail.ledger.filter(e => String(e.id) !== entryId).sort((a, b) => a.id - b.id),
        JSON.parse(ledger).sort((a, b) => a.id - b.id));
      await proof.query('rollback;');
    } finally { await proof.close(); }
    assert.equal(await rows('public.wallet_ledger_entries', `wallet_account_id='${p.wallet}'`), ledger);
    assert.deepEqual(await balance(p), [6600, 0]);
    assert.equal(await db.query(`select not exists(select 1 from auth.users where id='${p.subject}')
      and not exists(select 1 from public.profiles where id='${p.subject}');`), 't');
  });

  await check('paid credit: before-expiry login does not restore; explicit restoration preserves free and paid value', async () => {
    const recover = await person(5007);
    await load(recover, 2400, 'pi_credit_restore'); await pending(recover, '1 hour');
    const state = JSON.parse(await human(recover, 'select public.get_account_lifecycle_status()'));
    assert.equal(state.account_state, 'pending_deletion');
    assert.equal(await db.query(`select restored_at is null from private.account_lifecycle where user_id='${recover.subject}';`), 't');
    assert.equal(JSON.parse(await service(step(recover))).status, 'held');
    await human(recover, 'select public.restore_account()');
    assert.deepEqual(await balance(recover), [2400, 500]);
    assert.equal(await db.query(`select round(reward_tracker*100) from public.profiles where id='${recover.subject}';`), '400');
    assert.equal(await db.query(`select retired_at is null from private.account_retained_subjects where user_id='${recover.subject}';`), 't');
  });

  await check('paid credit: expired account cannot restore even while cleanup is delayed', async () => {
    const expired = await person(5008); await load(expired, 2400, 'pi_credit_expired'); await pending(expired);
    await assert.rejects(human(expired, 'select public.restore_account()'), error => {
      errorCode('PT403')(error); assert.match(error.message, /restore_expired/); return true;
    });
    assert.deepEqual(await balance(expired), [2400, 500]);
    assert.equal(await db.query(`select count(*) from auth.users where id='${expired.subject}';`), '1');
  });

  await check('paid credit: late funding waiting on final deletion sees retirement and grants only principal', async () => {
    const race = await person(5009); await load(race, 2400, 'pi_credit_race'); await pending(race);
    const dispatch = JSON.parse(await service(step(race))); assert.equal(dispatch.action, 'auth');
    const holder = await cluster.connect(), waiter = await cluster.connect();
    let waiting;
    try {
      await holder.query(`begin; set local role supabase_auth_admin; delete from auth.users where id='${race.subject}';`);
      waiting = waiter.query(`set role service_role; select public.record_wallet_load_from_stripe(
        '${race.subject}',2600,'pi_credit_race_late');`).then(value => ({ value }), error => ({ error }));
      await blocked(db, waiter, holder); await holder.query('commit;');
      const outcome = await waiting; assert.ifError(outcome.error); assert.equal(outcome.value, race.wallet);
      assert.deepEqual(await balance(race), [5000, 0]);
      assert.equal(await db.query(`select reward_tracker from private.account_retained_subjects where user_id='${race.subject}';`), '0');
    } finally { await holder.close(); await waiter.close(); if (waiting) await waiting; }
  });
}
