import assert from 'node:assert/strict';
import { read, uid } from './account-cleanup.mjs';
import { blocked } from './policy-admission-pg.mjs';

const version = 'retention-draft-2026-10-01';
const hash = '3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be';
const policy = `'${version}','${hash}'`;
const q = value => `'${String(value).replaceAll("'", "''")}'`;

// Extends the installed fixture, never replaces a routine, grant, FK or trigger.
// Historical timestamps below are synthetic fixture inputs, not provider evidence.
export async function exerciseBoundaries({ db, run, check, cluster }) {
  const service = sql => run(`set role service_role; ${sql};`).then(JSON.parse);
  const rpc = async expression => {
    const result = await db.query(`set local role service_role; select ${expression}; set local role postgres;`);
    return JSON.parse(result);
  };
  const step = (subject, claim, requested) =>
    `public.execute_account_cleanup_step('${claim}',${policy},'${subject}',${q(requested)})`;
  const attachment = claim => `public.claim_closed_attachment_cleanup('${claim}',${policy})`;
  const rows = (table, where = 'true') => db.query(`select coalesce(jsonb_agg(to_jsonb(r)
    order by to_jsonb(r)::text),'[]') from ${table} r where ${where};`);
  const isolated = (name, action) => check(`boundary: ${name}`, async () => {
    await db.query("begin; set local role postgres; set local timezone='UTC';");
    try { await action(); } finally { if (!db.exited) await db.query('rollback;'); }
  });
  const person = async n => {
    const subject = uid(n), session = uid(n + 10000);
    await db.query(`set role supabase_auth_admin;
      insert into auth.users(id,email,email_confirmed_at) values('${subject}','boundary-${n}@example.invalid',now());
      insert into auth.sessions(id,user_id,aal,created_at) values('${session}','${subject}','aal1',clock_timestamp());
      set role postgres;
      insert into public.profiles(id,full_name,reward_tracker) values('${subject}','Synthetic boundary ${n}',0);`);
    return { subject, session, claim: uid(n + 20000) };
  };
  const pending = async (n, age = "interval '721 hours'") => {
    const p = await person(n);
    await db.query(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
      select '${p.subject}',t,t+interval '720 hours' from (select clock_timestamp()-(${age}) t) x;
      insert into private.account_cleanup_inventory(user_id,requested_at,custodian,recorded_at,
        hold_inventory_reference,processor_disposition_reference,media_inventory_reference,
        backup_disposition_reference,financial_retention_reference)
      select user_id,deletion_requested_at,'${uid(802)}',clock_timestamp(),
        'SYNTHETIC-boundary-holds','SYNTHETIC-boundary-processors','SYNTHETIC-boundary-media',
        'SYNTHETIC-boundary-backups','SYNTHETIC-boundary-financial'
        from private.account_lifecycle where user_id='${p.subject}';`);
    p.requested = await db.query(`select deletion_requested_at from private.account_lifecycle where user_id='${p.subject}';`);
    return p;
  };
  const auth = p => `set local request.jwt.claims=${q(JSON.stringify({ sub: p.subject,
    session_id: p.session, role: 'authenticated', aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600 }))};
    set local request.jwt.claim.sub=''; set local role authenticated;`;
  const hold = (subject, type, key = null) => db.query(`insert into private.account_retention_holds
    (user_id,data_class,record_key,authority,purpose,custodian,created_at,review_at)
    values('${subject}',${q(type)},${key === null ? 'null' : q(key)},'SYNTHETIC-QA','Boundary isolation',
      '${uid(802)}',clock_timestamp()-interval '2 days',clock_timestamp()-interval '1 day');`);
  const report = (subject, id, ref = null) => db.query(`insert into public."Maintenance"
    (maint_id,user_id,created_at,status,description,location,attachment_ref)
    values(${id},'${subject}',clock_timestamp(),'resolved','Synthetic support ${id}','Synthetic location',
      ${ref === null ? 'null' : `${q(JSON.stringify(ref))}::jsonb`});`);
  const object = async (subject, id) => {
    const ref = { id: uid(id), bucket: 'maintenance-images', name: `boundary/${id}.jpg`, version: 'v1' };
    await db.query(`set local role supabase_storage_admin;
      insert into storage.objects(id,bucket_id,name,owner_id,version,created_at,is_versioned)
      values('${ref.id}',${q(ref.bucket)},${q(ref.name)},'${subject}',${q(ref.version)},clock_timestamp()-interval '100 days',true);
      set local role postgres;`);
    return ref;
  };
  const closure = (subject, id, age) => db.query(`insert into private.account_support_retention(maint_id,user_id,closed_at)
    values(${id},'${subject}',clock_timestamp()-(${age}));`);
  const attachmentInventory = () => db.query(`update private.account_cleanup_execution
    set closed_attachment_inventory_reference='SYNTHETIC-boundary-inventory',
      closed_attachment_inventory_at=clock_timestamp(),closed_attachment_custodian='${uid(802)}';`);

  await check('boundary: restore commits first and queued installed executor cannot dispatch', async () => {
    assert.equal(await db.query('select current_user;'), 'postgres');
    assert.equal(await db.query('select rolsuper from pg_roles where rolname=current_user;'), 'f');
    const p = await pending(1001, "interval '1 hour'");
    const holder = await cluster.connect(), waiter = await cluster.connect();
    let waiting;
    try {
      await holder.query(`begin; ${auth(p)} select public.restore_account();`);
      waiting = waiter.query(`set role service_role; select ${step(p.subject, p.claim, p.requested)};`)
        .then(value => ({ value }), error => ({ error }));
      await blocked(db, waiter, holder);
      await holder.query('commit;');
      const outcome = await waiting;
      assert.ifError(outcome.error);
      const result = JSON.parse(outcome.value);
      assert.equal(result.status, 'held'); assert.equal(result.reason, 'claim_unavailable');
      assert.equal(await db.query(`select restored_at is not null from private.account_lifecycle where user_id='${p.subject}';`), 't');
      assert.equal(await db.query(`select count(*) from private.account_cleanup_jobs where user_id='${p.subject}';`), '0');
      assert.equal(await db.query(`select exists(select 1 from auth.users where id='${p.subject}')
        and exists(select 1 from public.profiles where id='${p.subject}');`), 't');
    } finally { await holder.close(); await waiter.close(); if (waiting) await waiting; }
  });

  await check('boundary: dispatch commits first and queued restore cannot undo the expired request', async () => {
    const p = await pending(1002);
    const holder = await cluster.connect(), waiter = await cluster.connect();
    let waiting;
    try {
      const dispatch = JSON.parse(await holder.query(`begin; set local role service_role;
        select ${step(p.subject, p.claim, p.requested)};`));
      assert.equal(dispatch.status, 'dispatch'); assert.equal(dispatch.action, 'auth');
      waiting = waiter.query(`begin; ${auth(p)} select public.restore_account(); commit;`)
        .then(value => ({ value }), error => ({ error }));
      await blocked(db, waiter, holder);
      await holder.query('commit;');
      const outcome = await waiting;
      assert.equal(outcome.error?.code, 'PT403', outcome.error?.message);
      assert.match(outcome.error.message, /restore_expired/);
      assert.equal(await db.query(`select restored_at is null from private.account_lifecycle where user_id='${p.subject}';`), 't');
      assert.equal(await db.query(`select external_operation->>'operation_id' from private.account_cleanup_jobs
        where user_id='${p.subject}';`), dispatch.operation_id);
      const receipt = await service(`select public.acknowledge_account_cleanup('${p.subject}',${q(p.requested)},
        '${p.claim}','${dispatch.operation_id}',${policy},'unknown')`);
      assert.equal(receipt.status, 'outcome_unknown'); assert.equal(receipt.automatic_retry, false);
    } finally { await holder.close(); await waiter.close(); if (waiting) await waiting; }
  });

  await isolated('record support hold preserves only its report, despite overdue review', async () => {
    const p = await pending(1101), other = await person(1102);
    await report(p.subject, 1101); await report(p.subject, 1102); await report(other.subject, 1103);
    await hold(p.subject, 'support', '1101');
    const held = await rows('public."Maintenance"', 'maint_id=1101');
    const unrelated = await rows('public."Maintenance"', 'maint_id=1103');
    const result = await rpc(step(p.subject, p.claim, p.requested));
    assert.equal(result.status, 'dispatch'); assert.equal(result.action, 'auth');
    assert.equal(await rows('public."Maintenance"', 'maint_id=1101'), held);
    assert.equal(await rows('public."Maintenance"', 'maint_id=1103'), unrelated);
    assert.equal(await db.query(`select user_id is null and description is null and location is null
      from public."Maintenance" where maint_id=1102;`), 't');
    assert.equal(await db.query(`select released_at is null from private.account_retention_holds
      where user_id='${p.subject}';`), 't');
  });

  await isolated('class support hold covers its subject without shielding another subject', async () => {
    const held = await pending(1111), free = await pending(1112);
    await report(held.subject, 1111); await report(held.subject, 1112); await report(free.subject, 1113);
    await hold(held.subject, 'support');
    const before = await rows('public."Maintenance"', 'maint_id in (1111,1112)');
    assert.equal((await rpc(step(held.subject, held.claim, held.requested))).action, 'auth');
    assert.equal((await rpc(step(free.subject, free.claim, free.requested))).action, 'auth');
    assert.equal(await rows('public."Maintenance"', 'maint_id in (1111,1112)'), before);
    assert.equal(await db.query('select user_id is null and description is null from public."Maintenance" where maint_id=1113;'), 't');
  });

  await isolated('closed attachments require ninety elapsed days and a known closure clock', async () => {
    const p = await person(1201);
    const ref = await object(p.subject, 1201);
    await report(p.subject, 1201, ref);
    await attachmentInventory();
    assert.equal((await rpc(attachment(p.claim))).status, 'idle', 'No invented closure from report creation');
    await closure(p.subject, 1201, "interval '90 days'-interval '1 hour'");
    const before = await rows('storage.objects');
    assert.equal((await rpc(attachment(p.claim))).status, 'idle', 'Before ninety days');
    await db.query(`update private.account_support_retention set closed_at=clock_timestamp()-interval '90 days'
      where maint_id=1201;`);
    const result = await rpc(attachment(p.claim));
    assert.equal(result.status, 'dispatch'); assert.equal(result.report_id, '1201');
    assert.deepEqual(result.objects, [ref]); assert.equal(result.purge_complete, false);
    assert.equal(await rows('storage.objects'), before, 'SQL dispatch does not mutate Storage');
  });

  await isolated('attachment object id, bucket, name, version, owner and creation clock must all bind', async () => {
    const p = await person(1210), other = await person(1211);
    await attachmentInventory();
    const mismatches = [{ id: uid(99999) }, { bucket: 'different-bucket' },
      { name: 'different/name.jpg' }, { version: 'v2' }];
    for (const [index, mismatch] of mismatches.entries()) {
      const id = 1210 + index, ref = await object(p.subject, id);
      await report(p.subject, id, { ...ref, ...mismatch });
      await closure(p.subject, id, "interval '91 days'");
    }
    const foreign = await object(other.subject, 1214);
    await report(p.subject, 1214, foreign); await closure(p.subject, 1214, "interval '91 days'");
    const newer = await object(p.subject, 1215);
    await report(p.subject, 1215, newer); await closure(p.subject, 1215, "interval '101 days'");
    assert.equal((await rpc(attachment(p.claim))).status, 'idle');
    assert.equal(await db.query('select sum(attachment_attempts) from private.account_support_retention;'), '0');
    const exact = await object(p.subject, 1216);
    await db.query(`set local role supabase_storage_admin;
      insert into storage.objects(id,bucket_id,name,owner_id,version,created_at,archived_at,is_versioned)
      values('${uid(1217)}',${q(exact.bucket)},${q(exact.name)},'${p.subject}','v0',
        clock_timestamp()-interval '101 days',clock_timestamp()-interval '100 days',true);
      set local role postgres;`);
    await report(p.subject, 1216, exact); await closure(p.subject, 1216, "interval '91 days'");
    const before = await rows('storage.objects');
    const result = await rpc(attachment(p.claim));
    assert.equal(result.report_id, '1216'); assert.deepEqual(result.objects, [exact]);
    const ack = (claim, operation, closed) => `public.acknowledge_closed_attachment_cleanup(1216,
      ${closed},'${claim}','${operation}',${policy},'returned')`;
    for (const expression of [ack(uid(99991), result.operation_id, q(result.closed_at)),
      ack(p.claim, uid(99992), q(result.closed_at)),
      ack(p.claim, result.operation_id, `${q(result.closed_at)}::timestamptz+interval '1 microsecond'`)]) {
      await db.query(`set local role service_role; do $$ begin
        perform ${expression}; raise exception 'Stale attachment acknowledgement accepted';
        exception when sqlstate 'PT409' then
          if sqlerrm <> 'attachment_operation_changed' then raise; end if;
        end $$; set local role postgres;`);
    }
    const receipt = await rpc(ack(p.claim, result.operation_id, q(result.closed_at)));
    assert.equal(receipt.status, 'outcome_unknown'); assert.equal(receipt.automatic_retry, false);
    await db.query(`update private.account_support_retention set attachment_lease_until=clock_timestamp()-interval '1 second'
      where maint_id=1216;`);
    const inspection = await rpc(attachment(uid(99993)));
    assert.equal(inspection.status, 'inspect'); assert.equal(inspection.operation_id, result.operation_id);
    assert.equal(inspection.claim_id, p.claim); assert.equal(inspection.objects, undefined);
    assert.equal(await db.query('select attachment_attempts from private.account_support_retention where maint_id=1216;'), '1');
    assert.equal(await rows('storage.objects'), before);
  });

  await isolated('scoped media/support holds exclude only matching closed attachments', async () => {
    const p = await person(1220), other = await person(1221);
    await attachmentInventory();
    const refs = [];
    for (let id = 1220; id < 1224; id++) {
      const subject = id === 1223 ? other.subject : p.subject;
      const ref = await object(subject, id); refs.push(ref);
      await report(subject, id, ref); await closure(subject, id, "interval '91 days'");
    }
    await hold(p.subject, 'media', refs[0].id); await hold(p.subject, 'support', '1221');
    const before = await rows('public."Maintenance"');
    const first = await rpc(attachment(p.claim)), second = await rpc(attachment(other.claim));
    assert.equal(first.report_id, '1222'); assert.deepEqual(first.objects, [refs[2]]);
    assert.equal(second.report_id, '1223'); assert.deepEqual(second.objects, [refs[3]]);
    assert.equal(await db.query(`select count(*) from private.account_support_retention
      where maint_id in (1220,1221) and attachment_outcome='ready' and attachment_attempts=0;`), '2');
    assert.equal(await rows('public."Maintenance"'), before);
  });

  // Drive pruning through the service RPC's idle path. Only scheduling timestamps
  // isolate the new subject from already-accepted fixture subjects, inside rollback.
  const removed = async (n, acknowledge = true) => {
    await db.query('update private.account_cleanup_jobs set last_retention_at=clock_timestamp() where auth_removed_at is not null;');
    const p = await pending(n, "interval '14 months'");
    const dispatch = await rpc(step(p.subject, p.claim, p.requested));
    assert.equal(dispatch.action, 'auth');
    await db.query(`set local role supabase_auth_admin; delete from auth.users where id='${p.subject}'; set local role postgres;`);
    if (acknowledge) {
      const receipt = await rpc(`public.acknowledge_account_cleanup('${p.subject}',${q(p.requested)},
        '${p.claim}','${dispatch.operation_id}',${policy},'returned')`);
      assert.equal(receipt.status, 'account_removed');
    }
    return { ...p, dispatch };
  };
  const ageRemoval = (p, age) => db.query(`update private.account_cleanup_jobs
    set auth_removed_at=clock_timestamp()-(${age}),last_retention_at=null where user_id='${p.subject}';`);
  const prune = () => rpc(`public.execute_account_cleanup_step('${uid(29999)}',${policy})`);
  const metadata = async p => ({
    inventory: await rows('private.account_cleanup_inventory', `user_id='${p.subject}'`),
    lifecycle: await rows('private.account_lifecycle', `user_id='${p.subject}'`),
    job: JSON.parse(await db.query(`select to_jsonb(j)-array['last_retention_at','redaction_xid']
      from private.account_cleanup_jobs j where user_id='${p.subject}';`)),
  });

  await isolated('cleanup metadata stays before twelve months then expires without deleting retained financial identity', async () => {
    const p = await removed(1301);
    const financial = await rows('public.wallet_accounts');
    await ageRemoval(p, "interval '12 months'-interval '1 hour'");
    const before = await metadata(p);
    assert.equal((await prune()).status, 'progress'); assert.deepEqual(await metadata(p), before);
    await ageRemoval(p, "interval '12 months'");
    assert.equal((await prune()).status, 'progress');
    for (const table of ['private.account_cleanup_jobs', 'private.account_cleanup_inventory', 'private.account_lifecycle']) {
      assert.equal(await db.query(`select count(*) from ${table} where user_id='${p.subject}';`), '0', table);
    }
    assert.equal(await db.query(`select financial_retention_reference from private.account_retained_subjects
      where user_id='${p.subject}';`), 'SYNTHETIC-boundary-financial');
    assert.equal(await rows('public.wallet_accounts'), financial);
  });

  await isolated('twelve-month compaction preserves only a needed support link and finishes when support expires', async () => {
    const p = await removed(1310);
    await report(p.subject, 1310);
    await db.query(`insert into private.account_support_retention(maint_id,user_id,requested_at,closed_at)
      values(1310,'${p.subject}',${q(p.requested)},clock_timestamp()-interval '11 months');`);
    await ageRemoval(p, "interval '12 months'");
    assert.equal((await prune()).status, 'progress');
    const compacted = (await metadata(p)).job;
    assert.equal(compacted.state, 'retention_only'); assert.deepEqual(compacted.retention_reasons, ['support']);
    assert(compacted.metadata_compacted_at);
    for (const key of ['claim_id', 'attempts', 'used_claim_ids', 'lease_until', 'retry_after', 'external_operation',
      'disposition_requested_at', 'local_disposed_at', 'next_disposition_at', 'disposition_policy_version', 'disposition_policy_sha256']) {
      assert.equal(compacted[key], null, key);
    }
    assert.equal(await rows('private.account_cleanup_inventory', `user_id='${p.subject}'`), '[]');
    assert.equal(await db.query('select user_id is null and description is null from public."Maintenance" where maint_id=1310;'), 't');
    await db.query(`update private.account_support_retention set closed_at=clock_timestamp()-interval '12 months' where maint_id=1310;
      update private.account_cleanup_jobs set last_retention_at=null where user_id='${p.subject}';`);
    assert.equal((await prune()).status, 'progress');
    assert.equal(await rows('private.account_cleanup_jobs', `user_id='${p.subject}'`), '[]');
    assert.equal(await rows('private.account_lifecycle', `user_id='${p.subject}'`), '[]');
    assert.equal(await rows('public."Maintenance"', 'maint_id=1310'), '[]');
  });

  await isolated('cleanup hold protects expired evidence until explicit release, not its review date', async () => {
    const p = await removed(1320);
    await hold(p.subject, 'cleanup'); await ageRemoval(p, "interval '13 months'");
    const before = await metadata(p);
    assert.equal((await prune()).status, 'progress'); assert.deepEqual(await metadata(p), before);
    await db.query(`update private.account_retention_holds set released_at=clock_timestamp(),released_by='${uid(802)}',
      release_reference='SYNTHETIC-explicit-release' where user_id='${p.subject}';`);
    assert.equal((await prune()).status, 'progress');
    assert.equal(await rows('private.account_cleanup_jobs', `user_id='${p.subject}'`), '[]');
    assert.equal(await db.query(`select released_at is not null from private.account_retention_holds where user_id='${p.subject}';`), 't');
  });

  for (const state of ['leased', 'outcome_unknown']) {
    await isolated(`unresolved ${state} operation preserves twelve-month metadata and exact dispatch identity`, async () => {
      const p = await removed(1330, false);
      // Synthetic historical partial observation: Auth is absent, but the real
      // dispatch has never been acknowledged. Its marker must survive pruning.
      await ageRemoval(p, "interval '13 months'");
      await db.query(`update private.account_cleanup_jobs set state='${state}' where user_id='${p.subject}';`);
      const before = await metadata(p);
      assert.equal(before.job.external_operation.operation_id, p.dispatch.operation_id);
      assert.equal((await prune()).status, 'progress'); assert.deepEqual(await metadata(p), before);
      assert.equal(await db.query(`select financial_retention_reference is null from private.account_retained_subjects
        where user_id='${p.subject}';`), 't');
    });
  }

  await check('boundary: scheduler setup fails closed and disable is harmless with no Cron installed', async () => {
    assert.equal(await db.query(`select to_regclass('cron.job') is null and to_regnamespace('net') is null
      and to_regnamespace('vault') is null;`), 't');
    const before = await rows('private.account_cleanup_execution');
    const jobs = await rows('private.account_cleanup_jobs');
    await assert.rejects(run(`set role postgres; ${await read('supabase/ops/account-cleanup-setup.sql')}`), error => {
      assert.equal(error.code, 'P0001', error.message);
      assert.match(error.message, /requires existing Cron, pg_net, Vault and cleanup SQL/); return true;
    });
    await run(`set role postgres; ${await read('supabase/ops/account-cleanup-disable.sql')}`);
    assert.equal(await rows('private.account_cleanup_execution'), before);
    assert.equal(await rows('private.account_cleanup_jobs'), jobs);
    assert.equal(await db.query("select to_regprocedure('private.account_cleanup_tick()') is null;"), 't');
  });
}
