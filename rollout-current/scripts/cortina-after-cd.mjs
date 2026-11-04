import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const local = (name) => readFile(new URL(`../${name}`, import.meta.url), 'utf8');
const hash = (text) => createHash('sha256').update(text).digest('hex');
const added = ['nayax_environment', 'nayax_terminal_id', 'nayax_uniqr', 'stripe_livemode', 'checkout_return_version'];
const normalize = (snapshot) => Object.fromEntries(Object.entries(snapshot).map(([table, value]) => {
  const rows = JSON.parse(value);
  if (table === 'public.cortina_vend_sessions') {
    for (const row of rows) for (const key of added) delete row[key];
  }
  return [table, rows];
}));

// Called only by the proposed hook in the existing disposable C/D rehearsal.
// No cluster, hosted connection, fixture copy, SDK or provider is introduced.
export async function rehearseCortinaAfterCd({ db, run, rows, catalog, counter, read, artifact, user }) {
  assert.equal(hash(artifact), 'f2788680676ac4021dadd594bc435723dac148e5833a1b00ce4d03a3910a4348');
  const sql = await local('cortina-prerequisites.sql');
  const entries = (await local('migration-sources.sha256')).trim().split('\n');
  assert.equal(entries.length, 4);
  const parts = [];
  for (const [index, line] of entries.entries()) {
    const match = line.match(/^([a-f0-9]{64})  (supabase\/migrations\/.+\.sql)$/);
    assert(match);
    const [, digest, path] = match, source = await read(path);
    assert.equal(hash(source), digest, path);
    assert.equal((source.match(/^begin;$/gm) || []).length, index === 0 ? 0 : 1);
    assert.equal((source.match(/^commit;$/gm) || []).length, index === 0 ? 0 : 1);
    parts.push(`-- SOURCE: ${path}\n` + (index === 0 ? source :
      source.replace(/^begin;\n/m, '').replace(/^commit;\n?$/m, '')) + '\n');
  }
  const header = '-- GENERATED: four accepted Cortina prerequisites; no history replay or routing backfill.\n' +
    '-- Target: DEVELOPMENT dnuuhupoxjtwqzaqylvb, AFTER separately accepted C/D installation.\n' +
    '-- Only outer transaction wrappers are removed; see migration-sources.sha256.\nBEGIN;\n\n';
  assert.equal(sql, header + parts.join('\n') + 'COMMIT;\n');
  assert.equal(await db.query("select not rolsuper and rolbypassrls from pg_roles where rolname='postgres';"), 't');
  assert.equal(await db.query(`select exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='Machines' and column_name='is_out_of_service');`), 't');
  const before = await rows(), beforeCatalog = await catalog(), beforeCounter = await counter();
  const broken = sql.replace(/COMMIT;\n$/, () => "DO $$ BEGIN RAISE EXCEPTION 'synthetic Cortina rollback' USING ERRCODE='P0001'; END $$;\nCOMMIT;\n");
  await assert.rejects(run(`set role postgres; ${broken}`), (error) => error.code === 'P0001');
  assert.equal(await catalog(), beforeCatalog);
  assert.deepEqual(await rows(), before);
  await run(`set role postgres; ${sql}`);
  assert.deepEqual(normalize(await rows()), normalize(before));
  assert.equal(await counter(), beforeCounter);
  assert.equal(await db.query(`select bool_and(nayax_environment is null and nayax_terminal_id is null
    and nayax_uniqr is null and stripe_livemode is null and checkout_return_version=1)
    from public.cortina_vend_sessions;`), 't');
  assert.equal(await db.query(`select count(*) from information_schema.columns where table_schema='public'
    and table_name='cortina_vend_sessions' and column_name like 'reconcile_%';`), '0');
  for (const signature of ['record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)',
    'consume_cortina_request_capacity(text)']) {
    for (const role of ['anon', 'authenticated', 'service_role']) {
      assert.equal(await db.query(`select has_function_privilege('${role}','public.${signature}','execute');`),
        role === 'service_role' ? 't' : 'f');
    }
  }
  for (const role of ['anon', 'authenticated', 'service_role']) {
    assert.equal(await db.query(`select has_function_privilege('${role}','public.request_account_deletion()','execute');`), 'f');
  }
  assert.equal(await db.query('select count(*)=1 and bool_and(not enabled and rollout_at is null and refund_notice_recipient is null) from private.mail_settings;'), 't');
  for (const table of ['private.topup_refund_provenance', 'private.topup_refund_spend', 'private.voluntary_topup_refunds',
    'public.admin_audit_events', 'private.mail_outbox', 'private.account_lifecycle']) {
    assert.equal(await db.query(`select count(*) from ${table};`), '0', table);
  }

  // Synthetic service-side payment evidence exercises the real combined SQL;
  // callback eligibility is fixture state, not a provider Start or refund.
  const id = '00000000-0000-4000-8000-000000000931';
  await run(`begin; set local role service_role;
    insert into public.cortina_vend_sessions(id,client_request_id,client_access_token_hash,machine_id,user_id,
      amount_cents,payment_method,channel,transaction_id,washer_size_rate_id,pulse_line_number,checkout_return_version)
      values('${id}','${id}','synthetic-cortina-after-cd',1,'${user}',750,'card','web','${id}',1,1,2);
    update public.cortina_vend_sessions set stripe_checkout_session_id='cs_combined' where id='${id}';
    select public.record_cortina_card_payment('${id}','evt_combined','pi_combined','cs_combined','ch_combined',750,'USD',false);
    select public.record_cortina_card_payment('${id}','evt_combined','pi_combined','cs_combined','ch_combined',750,'USD',false);
    commit;`);
  assert.equal(await db.query(`select status='paid' and nayax_environment='sandbox'
    and nayax_terminal_id='synthetic-terminal' and stripe_livemode=false and checkout_return_version=2
    from public.cortina_vend_sessions where id='${id}';`), 't');
  assert.equal(await db.query(`select count(*) from public.cortina_vend_events where session_id='${id}' and source='stripe';`), '1');
  await assert.rejects(run(`begin; set local role service_role;
    update public.cortina_vend_sessions set checkout_return_version=1 where id='${id}'; commit;`),
  (error) => error.code === '23514');
  await run(`begin; set local role service_role;
    update public.cortina_vend_sessions set status='awaiting_sale' where id='${id}';
    insert into public.cortina_vend_events(session_id,source,event_type,event_key,payload)
      values('${id}','nayax','sale','nayax:sandbox:sale:931',
        jsonb_build_object('BasicInfo',jsonb_build_object('TransactionId','${id}',
          'NayaxTransactionId','931','Amount','7.50','CurrencyCode','USD'),
          'MachineInfo',jsonb_build_object('TerminalId','synthetic-terminal')));
    commit;`);
  assert.equal(await db.query(`select nayax_transaction_id='931' from public.cortina_vend_sessions where id='${id}';`), 't');
  assert.equal(await run("begin; set local role service_role; select public.consume_cortina_request_capacity('status')->>'allowed'; commit;"), 'true');
  assert.equal(await db.query(`select count(*) from public.cortina_vend_events where session_id='${id}';`), '2');
  assert.equal(await db.query(`select start_requested_at is null and stripe_refund_id is null
    from public.cortina_vend_sessions where id='${id}';`), 't');
}
