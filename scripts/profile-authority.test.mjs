import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';

// An explicit resolver permits existing tooling outside this repository.
const require = createRequire(process.env.PGLITE_RESOLVE_FROM || import.meta.url);
const { PGlite } = require('@electric-sql/pglite');
const { pgcrypto } = require('@electric-sql/pglite/contrib/pgcrypto');
const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const fixture = await sql('../supabase/tests/profile_authority.fixture.sql');
const wallet = await sql('../supabase/migrations/20260526010000_wallet_ledger_compliance.sql');
const migration = await sql('../supabase/migrations/20260929223124_protect_profile_authority.sql');
const customer = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
const owner = '00000000-0000-4000-8000-000000000003';
const newUser = '00000000-0000-4000-8000-000000000004';

// Exact role-only guard from the uncommitted admin migration; no portal objects
// or sibling checkout are needed to exercise installation-order compatibility.
const portalGuard = `
create function public.guard_portal_authority() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') then
    if tg_op = 'INSERT' and new.roles::text is distinct from 'User' then
      raise exception 'Role assignment requires a trusted administrator' using errcode = '42501';
    elsif tg_op = 'UPDATE' and new.roles is distinct from old.roles then
      raise exception 'Role assignment requires a trusted administrator' using errcode = '42501';
    end if;
  end if;
  return new;
end; $$;
create trigger portal_authority_guard before insert or update on public.profiles for each row execute function public.guard_portal_authority();
revoke all on function public.guard_portal_authority() from public, anon, authenticated;
`;

async function database() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(fixture);
  await db.exec(wallet);
  await db.exec(`
    -- Verified live grant, omitted from the incomplete local wallet baseline.
    grant execute on function public.is_admin_or_owner() to authenticated;
    -- Live legacy trigger; the function body comes from the wallet migration.
    create trigger handle_transaction after insert on public.transactions
      for each row execute function public.update_user_balance();
    insert into auth.users(id) values ('${customer}'),('${other}'),('${owner}'),('${newUser}');
    insert into public.profiles(id,full_name,roles,balance,reward_tracker) values
      ('${customer}','Customer','User',12.5,7.5),
      ('${other}','Other','User',8,1),('${owner}','Owner','Owner',0,0);
    insert into public."Machines" values (1,1);
  `);
  return db;
}

async function asRole(db, role, user, operation) {
  assert(['anon', 'authenticated', 'service_role', 'supabase_auth_admin'].includes(role));
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user || '']);
    await db.exec(`set local role ${role}`);
    return await operation();
  } finally {
    await db.exec('rollback');
  }
}

async function denial(db, role, user, statement, params = [], message) {
  await asRole(db, role, user, async () => {
    await assert.rejects(db.query(statement, params), (error) =>
      error.code === '42501' && (!message || message.test(error.message)));
  });
}

async function privileges(db) {
  return (await db.query(`select r.role, c.column_name, p.privilege,
    has_column_privilege(r.role,'public.profiles',c.column_name,p.privilege) as allowed
    from (values ('anon'),('authenticated')) r(role)
    cross join (values ('roles'),('balance'),('reward_tracker')) c(column_name)
    cross join (values ('INSERT'),('UPDATE')) p(privilege)
    order by 1,2,3`)).rows;
}

async function otherPrivileges(db) {
  return (await db.query(`select r.rolname,a.attname,p.privilege,
    has_column_privilege(r.oid,a.attrelid,a.attnum,p.privilege) as allowed
    from pg_roles r cross join (values ('INSERT'),('UPDATE')) p(privilege)
    join pg_attribute a on a.attrelid='public.profiles'::regclass and a.attnum>0 and not a.attisdropped
    where r.rolname in ('anon','authenticated','service_role','supabase_auth_admin')
      and (r.rolname in ('service_role','supabase_auth_admin') or a.attname not in ('roles','balance','reward_tracker'))
    order by 1,2,3`)).rows;
}

test('synthetic baseline reproduces direct authority writes despite column-only revoke', async () => {
  const db = await database();
  try {
    assert((await privileges(db)).every((row) => row.allowed));
    await asRole(db, 'authenticated', customer, async () => {
      await db.query("update public.profiles set roles='Owner',balance=900,reward_tracker=900 where id=$1", [customer]);
      assert.equal((await db.query('select public.is_admin_or_owner() as allowed')).rows[0].allowed, true);
    });
  } finally { await db.close(); }
});

for (const order of ['standalone', 'portal-before', 'portal-after']) {
  test(`protected profile contract: ${order}`, async (t) => {
    const db = await database();
    try {
      const beforeRows = (await db.query('select * from public.profiles order by id')).rows;
      const beforePrivileges = await otherPrivileges(db);
      const beforePolicies = (await db.query("select policyname,roles,cmd,qual,with_check from pg_policies where schemaname='public' and tablename='profiles' order by policyname")).rows;
      if (order === 'portal-before') await db.exec(portalGuard);
      await db.exec(migration);
      if (order === 'portal-after') await db.exec(portalGuard);

      await t.test('migration changes no profile data and closes effective protected grants', async () => {
        assert.deepEqual((await db.query('select * from public.profiles order by id')).rows, beforeRows);
        assert.deepEqual(await otherPrivileges(db), beforePrivileges);
        assert.deepEqual((await db.query("select policyname,roles,cmd,qual,with_check from pg_policies where schemaname='public' and tablename='profiles' order by policyname")).rows, beforePolicies);
        assert((await privileges(db)).every((row) => !row.allowed));
        const guard = (await db.query(`select p.prosecdef,p.proconfig,
          has_function_privilege('authenticated',p.oid,'EXECUTE') as callable
          from pg_proc p where p.oid='public.guard_profile_protected_fields()'::regprocedure`)).rows[0];
        assert.equal(guard.prosecdef, false);
        assert.equal(guard.callable, false);
        assert.deepEqual(guard.proconfig, ['search_path=""']);
      });

      await t.test('exact client create/upsert accepts defaults and never resets funded profile', async () => {
        await asRole(db, 'authenticated', newUser, async () => {
          await db.query('insert into public.profiles(id,full_name) values($1,$2) on conflict(id) do nothing', [newUser, 'New']);
          assert.deepEqual((await db.query('select roles,balance,reward_tracker from public.profiles where id=$1', [newUser])).rows[0], { roles: 'User', balance: 0, reward_tracker: 0 });
        });
        await asRole(db, 'authenticated', customer, async () => {
          await db.query('insert into public.profiles(id,full_name) values($1,$2) on conflict(id) do nothing', [customer, 'Replacement']);
          assert.deepEqual((await db.query('select full_name,balance,reward_tracker from public.profiles where id=$1', [customer])).rows[0], { full_name: 'Customer', balance: 12.5, reward_tracker: 7.5 });
          await db.query('update public.profiles set full_name=$1,notif_lead_time=3 where id=$2', ['Renamed', customer]);
          assert.equal((await db.query('select full_name from public.profiles where id=$1', [customer])).rows[0].full_name, 'Renamed');
          await db.query('select public.increment_user_refund_attempts($1)', [customer]);
          assert.equal((await db.query('select refund_attempts from public.profiles where id=$1', [customer])).rows[0].refund_attempts, 1);
        });
      });

      await t.test('RLS still denies cross-user insert/update and anonymous creation', async () => {
        await denial(db, 'authenticated', customer, 'insert into public.profiles(id,full_name) values($1,$2)', [newUser, 'Other']);
        await denial(db, 'anon', null, 'insert into public.profiles(id,full_name) values($1,$2)', [newUser, 'Anonymous']);
        await asRole(db, 'authenticated', customer, async () => {
          assert.equal((await db.query('update public.profiles set full_name=$1 where id=$2 returning id', ['Attack', other])).rows.length, 0);
        });
      });

      await t.test('current history types preserve balances while legacy credit/debit writes are denied', async () => {
        for (const type of ['Laundry', 'laundry']) {
          await asRole(db, 'authenticated', customer, async () => {
            await db.query('insert into public.transactions(id,user_id,amount,type) values(1,$1,1,$2)', [customer, type]);
            assert.equal((await db.query('select count(*)::integer as count from public.transactions')).rows[0].count, 1);
            assert.equal((await db.query('select balance from public.profiles where id=$1', [customer])).rows[0].balance, 12.5);
          });
        }
        for (const type of ['credit', 'debit']) {
          await denial(db, 'authenticated', customer,
            'insert into public.transactions(id,user_id,amount,type) values(1,$1,1,$2)', [customer, type]);
        }
        assert.equal((await db.query('select count(*)::integer as count from public.transactions')).rows[0].count, 0);
        assert.equal((await db.query('select balance from public.profiles where id=$1', [customer])).rows[0].balance, 12.5);
      });

      for (const [column, value] of [['roles', 'Owner'], ['balance', 99], ['reward_tracker', 99]]) {
        await t.test(`${column}: direct insert/update/conflict-update denied for customer and owner browsers`, async () => {
          for (const actor of [customer, owner]) {
            await denial(db, 'authenticated', actor, `update public.profiles set ${column}=$1 where id=$2`, [value, actor]);
            await denial(db, 'authenticated', newUser, `insert into public.profiles(id,${column}) values($1,$2)`, [newUser, value]);
            await denial(db, 'authenticated', actor, `insert into public.profiles(id) values($1) on conflict(id) do update set ${column}=$2`, [actor, value]);
          }
        });
      }

      await t.test('trusted server and definer wallet cache writes remain possible', async () => {
        await asRole(db, 'service_role', customer, async () => {
          await db.query("update public.profiles set balance=20,reward_tracker=5 where id=$1", [customer]);
          await db.query("select public.test_server_profile_write($1,'Admin',30,6)", [customer]);
          assert.equal((await db.query('select balance from public.profiles where id=$1', [customer])).rows[0].balance, 30);
          const walletId = (await db.query('select public.get_or_create_wallet_account($1) as id', [customer])).rows[0].id;
          await db.query("insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents) values($1,'load_paid',4500,4500)", [walletId]);
          await db.query('select public.sync_profile_wallet_balance($1)', [walletId]);
          assert.equal((await db.query('select balance from public.profiles where id=$1', [customer])).rows[0].balance, 45);
        });
        await asRole(db, 'supabase_auth_admin', newUser, async () => {
          await db.query("select public.test_server_profile_write($1,'User',0,0)", [newUser]);
        });
        await denial(db, 'authenticated', customer, "select public.test_server_profile_write($1,'Owner',999,999)", [customer]);
        await denial(db, 'authenticated', customer, 'select public.sync_profile_wallet_balance($1)', ['10000000-0000-4000-8000-000000000001']);
      });

      await t.test('existing admin definer routines reject a synthetic ordinary customer', async () => {
        const walletId = (await db.query('select public.get_or_create_wallet_account($1) as id', [customer])).rows[0].id;
        const calls = [
          'select public.admin_adjust_wallet($1,100,100,0,\'test\')',
          'select public.admin_record_legal_cash_redemption($1,100,null,\'test\')',
          'select public.admin_set_wallet_status($1,\'locked\',\'test\')',
          'select public.record_deleted_account_complaint($1,\'test\',\'denied\')',
        ];
        for (const statement of calls) {
          await asRole(db, 'authenticated', customer, async () => {
            await assert.rejects(db.query(statement, [walletId]), /Unauthorized/);
          });
        }
      });

      await t.test('authorized admin and customer wallet RPCs still update the protected cache', async () => {
        await asRole(db, 'service_role', owner, async () => {
          const walletId = (await db.query('select public.get_or_create_wallet_account($1) as id', [customer])).rows[0].id;
          await db.exec('set local role authenticated');
          await db.query("select public.admin_adjust_wallet($1,500,500,0,'synthetic authorized adjustment')", [walletId]);
          assert.equal((await db.query('select balance from public.profiles where id=$1', [customer])).rows[0].balance, 5);
        });
        await asRole(db, 'service_role', customer, async () => {
          const walletId = (await db.query('select public.get_or_create_wallet_account($1) as id', [customer])).rows[0].id;
          await db.query("insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents) values($1,'load_paid',500,500)", [walletId]);
          await db.exec('set local role authenticated');
          await db.query("select public.redeem_wallet_for_machine($1,1,100,'synthetic redemption')", [customer]);
          assert.equal((await db.query('select balance from public.profiles where id=$1', [customer])).rows[0].balance, 4);
        });
        await asRole(db, 'authenticated', customer, async () => {
          await assert.rejects(db.query("select public.redeem_wallet_for_machine($1,1,100,'wrong owner')", [other]), /Unauthorized/);
        });
      });

      await t.test('trigger remains a backstop after accidental broad client regrant', async () => {
        await db.exec('grant insert,update on public.profiles to authenticated');
        try {
          for (const [column, value] of [['roles', 'Owner'], ['roles', null], ['balance', 1], ['balance', null], ['balance', 'NaN'], ['reward_tracker', 1], ['reward_tracker', null]]) {
            const message = column === 'roles' ? /Protected profile|Role assignment/ : /Protected profile/;
            await denial(db, 'authenticated', customer, `update public.profiles set ${column}=$1 where id=$2`, [value, customer], message);
            await denial(db, 'authenticated', newUser, `insert into public.profiles(id,${column}) values($1,$2)`, [newUser, value], message);
          }
          await asRole(db, 'authenticated', customer, async () => {
            await db.query('update public.profiles set full_name=$1,balance=balance,reward_tracker=reward_tracker,roles=roles where id=$2', ['Allowed', customer]);
          });
          await denial(db, 'authenticated', customer, 'insert into public.profiles(id) values($1) on conflict(id) do update set balance=999', [customer], /Protected profile/);
        } finally { await db.exec('revoke insert,update on public.profiles from authenticated'); }
      });
    } finally { await db.close(); }
  });
}

test('unexpected inherited protected privileges abort the migration atomically', async () => {
  const db = await database();
  try {
    await db.exec('create role legacy_profile_writer; grant update on public.profiles to legacy_profile_writer; grant legacy_profile_writer to authenticated;');
    await assert.rejects(db.exec(migration), /Inherited profile write privileges require review/);
    await db.exec('rollback');
    assert((await privileges(db)).every((row) => row.allowed));
    assert.equal((await db.query("select to_regprocedure('public.guard_profile_protected_fields()') as fn")).rows[0].fn, null);
  } finally { await db.close(); }
});
