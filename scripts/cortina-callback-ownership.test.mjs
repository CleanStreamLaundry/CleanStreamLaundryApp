// One PGlite instance; no provider calls or independent-connection concurrency claim.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, afterEach, test } from 'node:test';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const migration = await read('supabase/migrations/20260930163919_cortina_callback_provider_ownership.sql');
// Tests supply the surrounding transaction, retaining every migration statement.
const transactionalMigration = migration.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
let a, b;
const legacy = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const legacyUnbound = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const insert = () => one(`insert into cortina_vend_sessions
  (client_request_id,client_access_token_hash,transaction_id,machine_id,washer_size_rate_id,
   amount_cents,payment_method,channel,pulse_line_number)
  values(gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,1,1,400,'card','app',1) returning *`);
const row = (id) => one('select * from cortina_vend_sessions where id=$1', [id]);
const count = async () => (await one('select count(*)::int n from cortina_vend_events')).n;
const payload = (s, id = '1234567') => ({ BasicInfo: { TransactionId: s.transaction_id,
  NayaxTransactionId: id, Amount: 4, CurrencyCode: 'USD' } });
const event = (s, type, id = '1234567', patch = {}) => {
  const e = { session_id: s.id, source: 'nayax', event_type: type,
    event_key: `nayax:${s.nayax_environment}:${type === 'sale_end' ? 'sale-end' : type}:${id ?? s.transaction_id}`,
    payload: payload(s, id), ...patch };
  return db.query(`insert into cortina_vend_events(session_id,source,event_type,event_key,payload)
    values($1,$2,$3,$4,$5) returning id`, Object.values(e));
};
const rejects = async (action, pattern) => {
  await db.exec('savepoint rejected_action');
  await assert.rejects(action, pattern);
  await db.exec('rollback to savepoint rejected_action');
};
before(async () => {
  await db.exec(await read('supabase/tests/cortina_payment_binding.fixture.sql'));
  const foundation = await read('supabase/migrations/20260803150427_cortina_qr_remote_vend.sql');
  await db.exec(foundation.replace('create extension if not exists pgcrypto with schema extensions;', ''));
  for (const name of ['20260807195409_configure_dryer_time_options.sql','20260922224735_cortina_price_array_selectors.sql']) {
    await db.exec(await read(`supabase/migrations/${name}`));
  }
  await db.exec(`insert into "Locations" values(1);
    insert into washer_size_rates(id,location_id,size_label,capacity_kg,price_cents) values(1,1,'12 kg',12,400);
    insert into "Machines"(id,"Name","Machine_type","Location_ID",washer_size_rate_id) values(1,'Washer','Washer',1,1);
    update cortina_machine_config set nayax_terminal_id='terminal-1',pulse_line_number=1,is_enabled=true,review_required=false;
    insert into cortina_vend_sessions(id,client_request_id,client_access_token_hash,transaction_id,
      machine_id,amount_cents,payment_method,channel,status,nayax_transaction_id)
    values('${legacy}',gen_random_uuid(),'legacy','legacy-transaction',1,400,'card','app','support_required','1234567'),
      ('${legacyUnbound}',gen_random_uuid(),'legacy-unbound','legacy-unbound-transaction',1,400,'card','app','support_required',null);`);
  await db.exec(await read('supabase/migrations/20260930154259_freeze_cortina_payment_bindings.sql'));
  await db.exec(migration);
  await db.exec('grant all on all tables in schema public to service_role; grant all on all sequences in schema public to service_role;');
});
beforeEach(async () => {
  await db.exec('begin; set local role service_role');
  a = await insert(); b = await insert();
  await db.query("update cortina_vend_sessions set status='awaiting_sale' where id in ($1,$2)", [a.id,b.id]);
});
afterEach(() => db.exec('rollback'));
after(() => db.close());

for (const first of ['sale','sale_end','void']) {
  for (const type of ['sale','sale_end','void']) {
  test(`A ${first} owns provider ID; B ${type} cannot bind or poison A's next callback`, async () => {
    await event(a, first);
    await rejects(() => event(b, type), /duplicate key/);
    assert.equal((await row(b.id)).status, 'awaiting_sale');
    assert.equal((await row(b.id)).nayax_transaction_id, null);
    assert.equal((await row(b.id)).stripe_refund_id, null);
    assert.equal(await count(), 1);
    if (type !== first) await event(a, type);
    assert.equal((await row(a.id)).nayax_transaction_id, '1234567');
    assert.equal(await count(), type === first ? 1 : 2);
  });
  }
}

test('same session cross-kind ownership and duplicate retries preserve one audit per kind', async () => {
  for (const type of ['sale','sale_end','void']) {
    await event(a, type);
    await rejects(() => event(a, type), /duplicate key/);
  }
  assert.equal(await count(), 3); assert.equal((await row(a.id)).nayax_transaction_id, '1234567');
});

test('different frozen environments can use the same provider ID and all callback kinds', async () => {
  await db.exec("update cortina_machine_config set environment='production' where machine_id=1");
  const production = await insert();
  await db.query("update cortina_vend_sessions set status='awaiting_sale' where id=$1", [production.id]);
  for (const type of ['sale','sale_end','void']) { await event(a,type); await event(production,type); }
  assert.equal(await count(), 6);
  assert.equal((await row(production.id)).nayax_transaction_id, '1234567');
  assert.equal((await row(a.id)).nayax_transaction_id, '1234567');
});

test('legacy null environment remains untouched and cannot receive automatic callback binding', async () => {
  const prior = await row(legacy);
  await event(a, 'sale');
  await rejects(() => event(prior, 'sale_end'), /frozen session/);
  assert.deepEqual(await row(legacy), prior);
  assert.equal(await count(), 1);
});

test('direct session updates also enforce global frozen provider ownership', async () => {
  await event(a, 'sale');
  await rejects(() => db.query("update cortina_vend_sessions set nayax_transaction_id='1234567' where id=$1", [b.id]), /duplicate key/);
  assert.equal((await row(b.id)).nayax_transaction_id, null);
});

test('audit failure rolls back provider binding and does not reserve another callback kind', async () => {
  await db.exec(`reset role; create function public.reject_callback_audit() returns trigger language plpgsql as $$
    begin raise exception 'synthetic audit failure'; end $$;
    create trigger zz_reject_callback_audit after insert on cortina_vend_events
      for each row execute function public.reject_callback_audit(); set local role service_role;`);
  await rejects(() => event(a,'sale'), /synthetic audit failure/);
  assert.equal((await row(a.id)).nayax_transaction_id, null); assert.equal(await count(), 0);
  await db.exec('reset role; drop trigger zz_reject_callback_audit on cortina_vend_events; set local role service_role');
  await event(b,'sale_end'); assert.equal((await row(b.id)).nayax_transaction_id, '1234567');
});

test('binding failure rolls back audit as well', async () => {
  await db.exec(`reset role; create function public.reject_callback_binding() returns trigger language plpgsql as $$
    begin if new.nayax_transaction_id is not null then raise exception 'synthetic binding failure'; end if; return new; end $$;
    create trigger zz_reject_callback_binding before update on cortina_vend_sessions
      for each row execute function public.reject_callback_binding(); set local role service_role;`);
  await rejects(() => event(a,'sale_end'), /synthetic binding failure/);
  assert.equal((await row(a.id)).nayax_transaction_id, null); assert.equal(await count(), 0);
});

test('ON CONFLICT DO NOTHING cannot bind without an inserted audit', async () => {
  await event(a,'sale');
  await db.query(`insert into cortina_vend_events(session_id,source,event_type,event_key,payload)
    values($1,'nayax','sale','nayax:sandbox:sale:1234567',$2) on conflict(event_key) do nothing`, [b.id,payload(b)]);
  assert.equal((await row(b.id)).nayax_transaction_id, null); assert.equal(await count(), 1);
});

for (const status of ['refunded','voided','support_required','timed_out','failed','paid','payment_pending']) {
  test(`current ${status} state rejects new Sale and SaleEnd audit/binding`, async () => {
    await db.query('update cortina_vend_sessions set status=$1 where id=$2', [status,a.id]);
    for (const type of ['sale','sale_end']) await rejects(() => event(a,type), /no longer eligible/);
    assert.equal((await row(a.id)).status, status); assert.equal((await row(a.id)).nayax_transaction_id, null);
    assert.equal(await count(), 0);
  });
}

test('Void without acknowledged provider ID remains auditable but invents no binding', async () => {
  await event(a,'void',null);
  assert.equal((await row(a.id)).nayax_transaction_id, null); assert.equal(await count(), 1);
});

for (const [name, patch] of [
  ['amount',{ BasicInfo: { Amount: 3.999999999 } }],
  ['currency',{ BasicInfo: { CurrencyCode: 'EUR' } }],
  ['application transaction',{ BasicInfo: { TransactionId: 'another-transaction' } }],
  ['terminal',{ MachineInfo: { TerminalId: 'wrong-terminal' } }],
  ['provider ID',{ BasicInfo: { NayaxTransactionId: 'bad-id' } }],
]) {
  test(`database checks callback ${name} before binding`, async () => {
    const body = payload(a); Object.assign(body,patch,{ BasicInfo: {...body.BasicInfo,...patch.BasicInfo} });
    await rejects(() => event(a,'sale','1234567',{payload:body}), /does not match/);
    assert.equal((await row(a.id)).nayax_transaction_id, null); assert.equal(await count(), 0);
  });
}

test('audit environment key must match the frozen session', async () => {
  await rejects(() => event(a,'sale','1234567',{event_key:'nayax:production:sale:1234567'}), /frozen environment/);
  assert.equal((await row(a.id)).nayax_transaction_id, null); assert.equal(await count(), 0);
});

test('historical unscoped same-session event remains unchanged alongside a scoped retry', async () => {
  await db.exec('reset role; alter table cortina_vend_events disable trigger bind_cortina_callback_provider;');
  await event(a,'sale','1234567',{event_key:'nayax:sale:1234567'});
  await db.exec('alter table cortina_vend_events enable trigger bind_cortina_callback_provider; set local role service_role;');
  const original = await one("select * from cortina_vend_events where event_key='nayax:sale:1234567'");
  await event(a,'sale'); await event(a,'sale_end');
  assert.deepEqual(await one("select * from cortina_vend_events where event_key='nayax:sale:1234567'"),original);
  assert.equal(await count(),3); assert.equal((await row(a.id)).nayax_transaction_id,'1234567');
});

test('historical event with unknown routing cannot be claimed by a new scoped event', async () => {
  await db.exec('reset role; alter table cortina_vend_events disable trigger bind_cortina_callback_provider;');
  await event(await row(legacy),'sale','1234567',{event_key:'nayax:sale:1234567'});
  await db.exec('alter table cortina_vend_events enable trigger bind_cortina_callback_provider; set local role service_role;');
  await rejects(() => event(a,'sale'), /unknown environment owner/);
  assert.equal(await count(),1); assert.equal((await row(a.id)).nayax_transaction_id,null);
});

test('historical unscoped event in known other environment does not block new scoped ownership', async () => {
  await db.exec('reset role; alter table cortina_vend_events disable trigger bind_cortina_callback_provider;');
  await event(a,'sale','1234567',{event_key:'nayax:sale:1234567'});
  await db.exec(`alter table cortina_vend_events enable trigger bind_cortina_callback_provider; set local role service_role;
    update cortina_machine_config set environment='production' where machine_id=1;`);
  const production = await insert();
  await db.query("update cortina_vend_sessions set status='awaiting_sale' where id=$1", [production.id]);
  await event(production,'sale');
  assert.equal(await count(),2); assert.equal((await row(production.id)).nayax_transaction_id,'1234567');
});

for (const role of ['anon','authenticated']) {
  test(`${role} cannot insert ownership audits or change provider bindings`, async () => {
    await db.exec(`set local role ${role}`);
    await rejects(() => event(a,'sale'), /permission denied/);
    await rejects(() => db.query("update cortina_vend_sessions set nayax_transaction_id='1234567' where id=$1", [a.id]), /permission denied/);
  });
}

for (const kind of ['binding','audit']) {
  test(`migration preflight rejects duplicate historical ${kind} without activating or repairing`, async () => {
    await db.exec(`reset role; drop trigger bind_cortina_callback_provider on cortina_vend_events;
      drop function public.bind_cortina_callback_provider(); drop index cortina_nayax_environment_transaction_key;`);
    await db.query("update cortina_vend_sessions set nayax_transaction_id='1234567' where id=$1", [a.id]);
    if (kind === 'binding') await db.query("update cortina_vend_sessions set nayax_transaction_id='1234567' where id=$1", [b.id]);
    else await event(b,'sale_end','1234567',{event_key:'nayax:sale-end:1234567'});
    const oldA = await row(a.id), oldB = await row(b.id), events = await count();
    await rejects(() => db.exec(transactionalMigration), /preflight failed/);
    assert.deepEqual(await row(a.id),oldA); assert.deepEqual(await row(b.id),oldB); assert.equal(await count(),events);
    assert.equal((await one("select to_regclass('public.cortina_nayax_environment_transaction_key') as index")).index,null);
  });
}

for (const routing of ['same','unknown','different']) {
  for (const type of ['sale_end','void']) {
    test(`historical cross-kind: old Sale with ${routing} environment reserves evidence before B ${type}`, async () => {
      let original = routing === 'unknown' ? await row(legacyUnbound) : await row(a.id);
      if (routing === 'different') {
        await db.exec("update cortina_machine_config set environment='production' where machine_id=1");
        original = await insert();
        await db.query("update cortina_vend_sessions set status='awaiting_sale' where id=$1", [original.id]);
        original = await row(original.id);
      }
      // Rehearse the real upgrade boundary: old audit committed, binding absent.
      await db.exec(`reset role; drop trigger bind_cortina_callback_provider on cortina_vend_events;
        drop function public.bind_cortina_callback_provider(); drop index cortina_nayax_environment_transaction_key;`);
      await event(original,'sale','1234567',{event_key:'nayax:sale:1234567'});
      const priorAudit = await one("select * from cortina_vend_events where event_key='nayax:sale:1234567'");
      await db.exec(transactionalMigration);
      await db.exec('set local role service_role');
      assert.equal((await row(original.id)).nayax_transaction_id,null);
      assert.equal((await row(b.id)).nayax_transaction_id,null);

      if (routing === 'different') {
        await event(b,type);
        assert.equal((await row(b.id)).nayax_transaction_id,'1234567');
        assert.equal(await count(),2);
      } else {
        await rejects(() => event(b,type), /unknown environment owner/);
        assert.equal((await row(b.id)).nayax_transaction_id,null);
        assert.equal((await row(b.id)).status,'awaiting_sale');
        assert.equal((await row(b.id)).stripe_refund_id,null);
        assert.equal(await count(),1);
        assert.equal((await one('select count(*)::int n from cortina_vend_events where session_id=$1',[b.id])).n,0);
      }
      if (routing === 'unknown') {
        await rejects(() => event(original,type), /frozen session/);
        assert.deepEqual(await row(original.id),original);
        assert.equal(await count(),1);
      } else {
        // A can retry the later kind directly, without first repairing/replaying Sale.
        await event(original,type);
        assert.equal((await row(original.id)).nayax_transaction_id,'1234567');
        assert.equal(await count(),routing === 'different' ? 3 : 2);
      }
      assert.deepEqual(await one("select * from cortina_vend_events where event_key='nayax:sale:1234567'"),priorAudit);
    });
  }
}
