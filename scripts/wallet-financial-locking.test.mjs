import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFile, mkdtemp, mkdir, chmod, lstat, realpath, rm, access, cp, symlink } from 'node:fs/promises';
import { isAbsolute, join, dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

// This harness NEVER connects to a supplied database. PG_BIN supplies executables
// only; each run creates, checks, stops, and removes its own private Unix cluster.
const pgBin = process.env.PG_BIN;
const guardPath = process.env.WALLET_TEST_PROFILE_GUARD;
const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const migration = await read('../supabase/migrations/20260929231120_serialize_wallet_financial_writes.sql');
const fixture = await read('../supabase/tests/wallet_financial_locking.fixture.sql');
const [prerequisites, liveTriggers, ...extra] = fixture.split('-- AFTER_BASELINE_MIGRATIONS');
assert.equal(extra.length, 0);
assert(liveTriggers);
const baseline = await read('../supabase/migrations/20260526010000_wallet_ledger_compliance.sql');
const cortina = await read('../supabase/migrations/20260803150427_cortina_qr_remote_vend.sql');
const refund = await read('../supabase/migrations/20260807191723_harden_refund_resolution.sql');
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), owner = uid(3), missingProfile = uid(4);
const sid = uid(10);
const names = [
  'get_or_create_wallet_account', 'sync_profile_wallet_balance',
  'record_wallet_load_from_stripe', 'redeem_wallet_for_machine', 'admin_adjust_wallet',
  'admin_record_legal_cash_redemption', 'admin_set_wallet_status',
  'reverse_cortina_wallet_redemption', 'resolve_refund_request',
];
const metadata = `select coalesce(json_agg(row_to_json(p) order by p.name),'[]') from (
  select p.oid::regprocedure::text as name,p.proowner,p.proacl,p.prosecdef,
    pg_get_function_arguments(p.oid) as args,pg_get_function_result(p.oid) as result
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (${names.map((n) => `'${n}'`).join(',')})
) p;`;

async function command(file, args, env, timeout = 20000) {
  const child = spawn(file, args, { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '';
  child.stdout.on('data', (part) => { stdout += part; });
  child.stderr.on('data', (part) => { stderr += part; });
  const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
  try {
    await new Promise((resolve, reject) => {
      child.on('error', reject);
      child.on('close', (code) => code === 0 ? resolve() : reject(new Error(`${file}: ${code}\n${stderr}`)));
    });
    return stdout.trim();
  } finally { clearTimeout(timer); }
}

class Session {
  constructor(cluster) {
    this.child = spawn(join(cluster.bin, 'psql'), [
      '-X', '-A', '-t', '-q', '--no-password', '-v', 'ON_ERROR_STOP=1',
      '-v', 'VERBOSITY=verbose', '-h', cluster.socket, '-p', '55432',
      '-U', 'wallet_fixture', '-d', 'wallet_locking_fixture',
    ], { env: cluster.env, stdio: ['pipe', 'pipe', 'pipe'] });
    this.buffer = '';
    this.stderr = '';
    this.pending = null;
    this.closed = new Promise((resolve) => {
      this.child.on('close', (code) => {
        this.exited = true;
        if (this.pending) {
          const error = new Error(this.stderr || `psql exited ${code}`);
          error.code = this.stderr.match(/ERROR:\s+([A-Z0-9]{5}):/)?.[1];
          this.finish(error);
        }
        resolve();
      });
    });
    this.child.on('error', (error) => this.finish(error));
    this.child.stdin.on('error', (error) => this.finish(error));
    this.child.stderr.on('data', (part) => { this.stderr += part; });
    this.child.stdout.on('data', (part) => {
      this.buffer += part;
      const pending = this.pending;
      if (!pending) return;
      const marker = `${pending.marker}\n`;
      const end = this.buffer.indexOf(marker);
      if (end >= 0) {
        const output = this.buffer.slice(0, end).trim();
        this.buffer = this.buffer.slice(end + marker.length);
        this.finish(null, output);
      }
    });
    cluster.sessions.add(this);
  }
  finish(error, output) {
    if (!this.pending) return;
    const pending = this.pending;
    this.pending = null;
    clearTimeout(pending.timer);
    if (error) pending.reject(error); else pending.resolve(output);
  }
  query(sql) {
    assert(!this.pending && !this.exited, 'Session unavailable');
    return new Promise((resolve, reject) => {
      const marker = `done_${randomUUID().replaceAll('-', '')}`;
      const timer = setTimeout(() => {
        this.finish(new Error('SQL deadline exceeded'));
        this.child.kill('SIGTERM');
      }, 12000);
      this.pending = { marker, timer, resolve, reject };
      this.child.stdin.write(`${sql}\n;\n\\echo ${marker}\n`);
    });
  }
  async close() {
    if (!this.exited) {
      if (this.pending) this.child.kill('SIGTERM');
      else this.child.stdin.end('\\q\n');
    }
    await this.closed;
  }
}

async function disposableCluster(t) {
  assert(pgBin && isAbsolute(pgBin), 'Set PG_BIN to the approved PostgreSQL 17 bin directory');
  let bin = await realpath(pgBin);
  const root = await mkdtemp('/private/tmp/cleanstream-wallet-locking-pg-');
  await chmod(root, 0o700);
  const identity = await lstat(root);
  const socket = join(root, 'socket');
  await mkdir(socket, { mode: 0o700 });
  const data = join(root, 'data');
  const env = {
    PATH: `${bin}:/usr/bin:/bin`, HOME: root, TMPDIR: root, LANG: 'C', LC_ALL: 'C',
    PGCONNECT_TIMEOUT: '5',
  };
  const cluster = { bin, root, socket, env, sessions: new Set() };
  let started = false;
  let startAttempted = false;
  let cleanup;
  let interrupted = false;
  let finishInitialization;
  const initialized = new Promise((resolve) => { finishInitialization = resolve; });
  const signals = new Map();
  const assertOwned = async () => {
    assert(root.startsWith('/private/tmp/cleanstream-wallet-locking-pg-'));
    assert.equal(await realpath(root), root);
    const current = await lstat(root);
    assert(current.isDirectory() && !current.isSymbolicLink());
    assert.equal(current.ino, identity.ino);
    assert.equal(current.dev, identity.dev);
    assert.equal(current.uid, process.getuid());
    assert.equal(current.mode & 0o777, 0o700);
  };
  cluster.close = () => cleanup ??= (async () => {
    for (const [signal, handler] of signals) process.removeListener(signal, handler);
    for (const session of cluster.sessions) await session.close();
    await assertOwned();
    const hasPid = await access(join(data, 'postmaster.pid')).then(() => true, (error) => {
      if (error.code !== 'ENOENT') throw error;
      return false;
    });
    if (started || (startAttempted && hasPid)) {
      try {
        await command(join(bin, 'pg_ctl'), ['-D', data, '-m', 'fast', '-w', '-t', '10', 'stop'], env);
      } catch {
        // Only this freshly initialized cluster can reach the fallback.
        await command(join(bin, 'pg_ctl'), ['-D', data, '-m', 'immediate', '-w', '-t', '10', 'stop'], env);
      }
      started = false;
      t.diagnostic('Owned PostgreSQL cluster stopped');
    }
    await assert.rejects(access(join(data, 'postmaster.pid')), { code: 'ENOENT' });
    await rm(root, { recursive: true });
    t.diagnostic(`Owned disposable directory removed: ${root}`);
  })();
  t.after(cluster.close);
  for (const signal of ['SIGINT', 'SIGTERM']) {
    const handler = () => {
      interrupted = true;
      initialized.then(cluster.close).then(() => process.exit(1), (error) => {
        process.stderr.write(`Disposable cluster cleanup failed: ${error.message}\n`);
        process.exit(1);
      });
    };
    signals.set(signal, handler);
    process.once(signal, handler);
  }
  try {
    const version = await command(join(bin, 'postgres'), ['--version'], env);
    assert.match(version, /PostgreSQL\) 17\./);
    t.diagnostic(`${version}; private Unix socket; listen_addresses empty`);
    const sharedir = await command(join(bin, 'pg_config'), ['--sharedir'], env);
    try {
      await access(join(sharedir, 'postgres.bki'));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      // Unlinked Homebrew bottles retain compiled share/lib paths. PostgreSQL
      // supports relocation when the original bin suffix is preserved. Copy
      // executables only into our disposable root; never link global paths.
      const bottle = bin.match(/^(.*)\/Cellar\/(postgresql@17)\/([^/]+)\/bin$/);
      assert(bottle, 'Runtime share directory missing; supply a complete local PG_BIN');
      const prefix = dirname(bin);
      const runtime = join(root, 'runtime');
      const relocatedBin = join(runtime, 'Cellar', bottle[2], bottle[3], 'bin');
      await cp(bin, relocatedBin, { recursive: true, dereference: true });
      await mkdir(join(runtime, 'share'), { recursive: true });
      await mkdir(join(runtime, 'lib'), { recursive: true });
      await symlink(join(prefix, 'share', 'postgresql'), join(runtime, 'share', bottle[2]));
      await symlink(join(prefix, 'lib', 'postgresql'), join(runtime, 'lib', bottle[2]));
      bin = relocatedBin;
      cluster.bin = bin;
      env.PATH = `${bin}:/usr/bin:/bin`;
      assert.equal(await command(join(bin, 'pg_config'), ['--sharedir'], env), join(runtime, 'share', bottle[2]));
      assert.equal(await command(join(bin, 'pg_config'), ['--pkglibdir'], env), join(runtime, 'lib', bottle[2]));
      t.diagnostic('Unlinked bottle relocated entirely inside owned disposable directory');
    }
    await command(join(bin, 'initdb'), [
      '-D', data, '--username=wallet_fixture', '--auth-local=trust',
      '--auth-host=reject', '--no-locale', '--encoding=UTF8',
    ], env);
    assert(!interrupted, 'Interrupted during cluster initialization');
    await assertOwned();
    startAttempted = true;
    await command(join(bin, 'pg_ctl'), [
      '-D', data, '-l', join(root, 'server.log'), '-w', '-t', '10',
      '-o', `-c listen_addresses='' -c unix_socket_directories='${socket}' -c unix_socket_permissions=0700 -p 55432`,
      'start',
    ], env);
    started = true;
    assert(!interrupted, 'Interrupted during cluster startup');
    await command(join(bin, 'createdb'), [
      '--no-password', '-h', socket, '-p', '55432', '-U', 'wallet_fixture', 'wallet_locking_fixture',
    ], env);
    cluster.connect = async () => {
      const session = new Session(cluster);
      const config = JSON.parse(await session.query(`select json_build_object(
        'db',current_database(),'user',current_user,'data',current_setting('data_directory'),
        'listen',current_setting('listen_addresses'),'address',inet_server_addr(),
        'socket',current_setting('unix_socket_directories'),'pid',pg_backend_pid());`));
      assert.equal(config.db, 'wallet_locking_fixture');
      assert.equal(config.user, 'wallet_fixture');
      assert.equal(config.data, data);
      assert.equal(config.listen, '');
      assert.equal(config.address, null);
      assert.equal(config.socket, socket);
      session.pid = config.pid;
      await session.query("set statement_timeout='10s'; set deadlock_timeout='150ms';");
      return session;
    };
    finishInitialization();
    return cluster;
  } catch (error) {
    finishInitialization();
    await cluster.close();
    throw error;
  }
}

const asUser = (id, statement, role = 'authenticated') => `begin;
  set local request.jwt.claim.sub='${id || ''}'; set local role ${role};
  ${statement}; commit;`;
const load = (id, cents, key) => `select public.record_wallet_load_from_stripe('${id}',${cents},'pi_${key}','cs_${key}',null,'evt_${key}')`;
const spend = (id, cents) => asUser(id, `select public.redeem_wallet_for_machine('${id}',1,${cents},'synthetic spend')`);
// Callers pass known IDs, not fixture-only SELECT subqueries under a client role.
const wallet = (id = user) => `'${id === user ? uid(101) : uid(102)}'`;
const resolve = (decision = 'approved') => `select public.resolve_refund_request(1,'${decision}','test review','${owner}')`;

async function blocked(observer, waiting, holder) {
  const end = Date.now() + 5000;
  while (Date.now() < end) {
    const result = await observer.query(`select ${holder.pid}=any(pg_blocking_pids(${waiting.pid}));`);
    if (result === 't') return;
    await delay(15);
  }
  throw new Error(`Expected blocked backend ${waiting.pid} behind ${holder.pid}`);
}

test('wallet financial contract on an owned, disposable PostgreSQL 17 cluster', { timeout: 180000 }, async (t) => {
  const cluster = await disposableCluster(t);
  const db = await cluster.connect();
  await db.query(prerequisites);
  await db.query(baseline);
  await db.query(cortina);
  await db.query(refund);
  await db.query(liveTriggers);
  if (guardPath) {
    assert(isAbsolute(guardPath), 'Guard fixture input must be an explicit absolute path');
    await db.query(await readFile(guardPath, 'utf8'));
  }
  const before = JSON.parse(await db.query(metadata));
  assert.equal(before.length, 9);
  const originalResolver = JSON.parse(await db.query(`select to_json(pg_get_functiondef(
    'public.resolve_refund_request(bigint,text,text,uuid)'::regprocedure));`));
  await db.query(migration);

  async function reset({ paid = 1000, promo = 0, reward = 0 } = {}) {
    await db.query(`truncate public."Locations",auth.users,public."Refunds",public.transactions restart identity cascade;
      insert into auth.users(id) values('${user}'),('${other}'),('${owner}'),('${missingProfile}');
      insert into public.profiles(id,roles,reward_tracker) values
        ('${user}','User',${reward}),('${other}','User',0),('${owner}','Owner',0);
      insert into public."Locations" values(1);
      insert into public."Machines"(id,"Location_ID","Machine_type","Price","Name") values(1,1,'dryer',10,'Test');
      insert into public.wallet_accounts(id,user_id) values
        (${wallet()},'${user}'),(${wallet(other)},'${other}');
      insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents)
        values(${wallet()},'legacy_balance',${paid + promo},${paid},${promo});
      select public.sync_profile_wallet_balance(${wallet()});`);
  }
  async function state() {
    return JSON.parse(await db.query(`select json_build_object('paid',w.paid_balance_cents,
      'promo',w.promo_balance_cents,'cache',p.balance,'reward',p.reward_tracker,
      'loads',(select count(*) from public.wallet_loads where user_id='${user}'),
      'redemptions',(select count(*) from public.wallet_redemptions where user_id='${user}'))
      from public.wallet_balances w join public.profiles p on p.id=w.user_id where p.id='${user}';`));
  }
  async function once(statement) {
    const connection = await cluster.connect();
    try { return await connection.query(statement); } finally { await connection.close(); }
  }
  async function vendAndClaim() {
    await db.query(`insert into public.cortina_vend_sessions(
      id,client_request_id,client_access_token_hash,machine_id,user_id,amount_cents,payment_method,channel,transaction_id)
      values('${sid}','${uid(11)}','synthetic_hash',1,'${user}',400,'wallet','app','synthetic_vend_01');`);
    await once(asUser(user, `select public.redeem_wallet_for_cortina('${sid}')`));
    await db.query(`update public.cortina_vend_sessions set status='started' where id='${sid}';
      insert into public."Refunds"(user_id,transaction_id,amount,description)
      select '${user}',id,4,'synthetic issue' from public.transactions where cortina_vend_session_id='${sid}';`);
  }

  await t.test('nine replacements preserve signatures, owners, definer mode and ACLs', async () => {
    assert.deepEqual(JSON.parse(await db.query(metadata)), before);
    assert.equal((migration.match(/create or replace function /g) || []).length, 9);
    assert(!/\b(grant|revoke)\s/i.test(migration));
  });

  await t.test('load reward arithmetic, repeated delivery and cache stay consistent', async () => {
    await reset({ paid: 0, reward: 15 });
    const first = await db.query(`${load(user, 1000, 'first')};`);
    assert.equal(await db.query(`${load(user, 1000, 'first')};`), first);
    await db.query(`${load(user, 1000, 'second')};`);
    assert.deepEqual(await state(), { paid: 2000, promo: 500, cache: 25, reward: 15, loads: 2, redemptions: 0 });
  });

  await t.test('customer authorization, locked spending and missing profile fail closed', async () => {
    await reset();
    await assert.rejects(once(asUser(null, `select public.redeem_wallet_for_machine('${user}',1,10)`)), /Unauthorized/);
    await assert.rejects(once(asUser(other, `select public.redeem_wallet_for_machine('${user}',1,10)`)), /Unauthorized/);
    await once(asUser(owner, `select public.admin_set_wallet_status(${wallet()},'locked')`));
    await assert.rejects(once(spend(user, 10)), /not active/);
    await assert.rejects(once(`${load(missingProfile, 100, 'missing')};`), /profile not found/);
    assert.equal(await db.query(`select count(*) from public.wallet_accounts where user_id='${missingProfile}';`), '0');
    await once(asUser(user, `${load(user, 100, 'forbidden')}`)).then(
      () => assert.fail('Customer called service-only recorder'),
      (error) => assert.equal(error.code, '42501'),
    );
  });

  await t.test('locked wallet permits captured settlement and exact-once split reversal', async () => {
    await reset({ paid: 1000, promo: 200 });
    await vendAndClaim();
    await once(asUser(owner, `select public.admin_set_wallet_status(${wallet()},'locked')`));
    await db.query(`${load(user, 100, 'locked')};`);
    assert.equal(await db.query(`select public.reverse_cortina_wallet_redemption('${sid}');`), 't');
    assert.equal(await db.query(`select public.reverse_cortina_wallet_redemption('${sid}');`), 'f');
    assert.deepEqual(await state(), { paid: 1100, promo: 200, cache: 13, reward: 1, loads: 1, redemptions: 1 });
  });

  await t.test('admin debit cannot overdraw either bucket; paid-only cash rule and authorization remain', async () => {
    await reset({ paid: 100, promo: 1000 });
    for (const statement of [
      `select public.admin_adjust_wallet(${wallet()},-101,-101,0,'test')`,
      `select public.admin_adjust_wallet(${wallet()},-1001,0,-1001,'test')`,
      `select public.admin_record_legal_cash_redemption(${wallet()},101,null,'test')`,
    ]) await assert.rejects(once(asUser(owner, statement)), /Insufficient balance/);
    await assert.rejects(once(asUser(user, `select public.admin_adjust_wallet(${wallet()},100,100,0,'test')`)), /Unauthorized/);
    await once(asUser(owner, `select public.admin_record_legal_cash_redemption(${wallet()},100,null,'test')`));
    assert.equal((await state()).paid, 0);
    await db.query(`select public.anonymize_wallet_for_deleted_user('${user}','test');`);
    const deleted = await db.query("select id from public.wallet_accounts where status='deleted';");
    await assert.rejects(once(asUser(owner, `select public.admin_set_wallet_status('${deleted}','active')`)), /deleted/);
  });

  await t.test('resolver preserves authorization, decision idempotency, promo credit and audit', async () => {
    await reset(); await vendAndClaim();
    await assert.rejects(once(`select public.resolve_refund_request(1,'approved','x','${other}');`), /Unauthorized/);
    await once(asUser(owner, `select public.admin_set_wallet_status(${wallet()},'locked')`));
    const result = JSON.parse(await db.query(`${resolve()};`));
    assert.equal(result.alreadyResolved, false);
    assert.equal(result.amount, 4);
    assert.equal((await state()).promo, 400);
    assert.equal(JSON.parse(await db.query(`${resolve()};`)).alreadyResolved, true);
    await assert.rejects(once(`${resolve('denied')};`), /already approved/);
    assert.equal(await db.query(`select count(*) from public.wallet_ledger_entries where refund_request_id=1;`), '1');
    assert.equal(await db.query(`select admin_note||'|'||resolved_by::text||'|'||(resolved_at is not null)::text from public."Refunds" where refund_id=1;`), `test review|${owner}|true`);
  });

  await t.test('denial and legacy non-Cortina claims keep deployed response and credit semantics', async () => {
    await reset(); await vendAndClaim();
    const denied = JSON.parse(await db.query(`${resolve('denied')};`));
    assert.equal(denied.status, 'denied');
    assert.equal(denied.alreadyResolved, false);
    assert.equal(JSON.parse(await db.query(`${resolve('denied')};`)).alreadyResolved, true);
    assert.equal((await state()).promo, 0);
    assert.equal(await db.query('select count(*) from public.wallet_ledger_entries where refund_request_id=1;'), '0');
    await reset();
    await db.query(`insert into public.transactions(user_id,amount,type) values('${user}',4,'laundry');
      insert into public."Refunds"(user_id,transaction_id,amount,description) values('${user}',1,4,'legacy');`);
    assert.equal(JSON.parse(await db.query(`${resolve()};`)).status, 'approved');
    assert.equal((await state()).cache, 14);
  });

  await t.test('new decisions preserve baseline notification=false even on a premarked pending row', async () => {
    for (const decision of ['approved', 'denied']) {
      await reset(); await vendAndClaim();
      await db.query(`update public."Refunds" set notification_sent_at='2026-01-01T00:00:00Z'
        where refund_id=1;`);
      assert.equal(await db.query('select status from public."Refunds" where refund_id=1;'), 'pending');
      const first = JSON.parse(await db.query(`${resolve(decision)};`));
      assert.equal(first.alreadyResolved, false);
      assert.equal(first.notificationSent, false);
      assert.equal(first.status, decision);
      const replay = JSON.parse(await db.query(`${resolve(decision)};`));
      assert.equal(replay.alreadyResolved, true);
      assert.equal(replay.notificationSent, true);
      assert.equal(await db.query(`select notification_sent_at='2026-01-01T00:00:00Z'::timestamptz
        from public."Refunds" where refund_id=1;`), 't');
      assert.equal(await db.query('select count(*) from public.wallet_ledger_entries where refund_request_id=1;'),
        decision === 'approved' ? '1' : '0');
    }
  });

  await t.test('live validation trigger rejects ineligible vend and rolls back attempted credit/cache', async () => {
    await reset(); await vendAndClaim();
    await db.query(`update public.cortina_vend_sessions set status='failed' where id='${sid}';`);
    const before = await state();
    await assert.rejects(once(`${resolve()};`), (error) => error.code === '22023' && /not eligible/.test(error.message));
    assert.deepEqual(await state(), before);
    assert.equal(await db.query('select status from public."Refunds" where refund_id=1;'), 'pending');
    assert.equal(await db.query('select count(*) from public.wallet_ledger_entries where refund_request_id=1;'), '0');
  });

  await t.test('distinct concurrent loads serialize reward progress; unrelated wallet proceeds', async () => {
    await reset({ paid: 0, reward: 15 });
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; ${load(user, 1000, 'race_a')};`);
      const waiting = b.query(`${load(user, 1000, 'race_b')};`);
      await blocked(db, b, a);
      await once(`${load(other, 100, 'independent')};`);
      await a.query('commit;'); await waiting;
      assert.deepEqual(await state(), { paid: 2000, promo: 500, cache: 25, reward: 15, loads: 2, redemptions: 0 });
    } finally { await a.close(); await b.close(); }
  });

  await t.test('same-payment waiter returns existing load without unique-error/double-credit', async () => {
    await reset({ paid: 0 });
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      const first = await a.query(`begin; ${load(user, 2000, 'duplicate')};`);
      const waiting = b.query(`${load(user, 2000, 'duplicate')};`);
      await blocked(db, b, a); await a.query('commit;');
      assert.equal(await waiting, first);
      assert.equal((await state()).loads, 1);
      assert.equal((await state()).promo, 500);
    } finally { await a.close(); await b.close(); }
  });

  await t.test('load and spend serialize promo-first accounting and the balance cache', async () => {
    await reset({ paid: 0, reward: 15 });
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; ${load(user, 1000, 'fund_spend')};`);
      const waiting = b.query(spend(user, 700));
      await blocked(db, b, a); await a.query('commit;'); await waiting;
      assert.deepEqual(await state(), { paid: 800, promo: 0, cache: 8, reward: 5, loads: 1, redemptions: 1 });
    } finally { await a.close(); await b.close(); }
  });

  for (const [key, args] of [
    ['intent', "'pi_shared',null,null,null"],
    ['session', "null,'cs_shared',null,null"],
    ['event', "null,null,null,'evt_shared'"],
  ]) {
    await t.test(`${key}-only duplicate key remains idempotent after a concurrent wait`, async () => {
      await reset({ paid: 0 });
      const a = await cluster.connect(), b = await cluster.connect();
      const call = `select public.record_wallet_load_from_stripe('${user}',2000,${args});`;
      try {
        const id = await a.query(`begin; ${call}`);
        const waiting = b.query(call);
        await blocked(db, b, a); await a.query('commit;');
        assert.equal(await waiting, id);
        assert.equal((await state()).loads, 1);
        assert.equal((await state()).cache, 25);
      } finally { await a.close(); await b.close(); }
    });
  }

  for (const outcome of ['commit', 'rollback']) {
    await t.test(`concurrent first-wallet creation: first delivery ${outcome}`, async () => {
      await reset({ paid: 0 });
      await db.query(`delete from public.wallet_accounts where user_id='${other}';`);
      const a = await cluster.connect(), b = await cluster.connect();
      try {
        await a.query(`begin; ${load(other, 1000, 'new_a')};`);
        const waiting = b.query(`${load(other, 1000, 'new_b')};`);
        await blocked(db, b, a); await a.query(`${outcome};`); await waiting;
        if (outcome === 'rollback') await once(`${load(other, 1000, 'new_a')};`);
        assert.equal(await db.query(`select count(*) from public.wallet_accounts where user_id='${other}';`), '1');
        assert.equal(await db.query(`select paid_balance_cents||'|'||promo_balance_cents from public.wallet_balances where user_id='${other}';`), '2000|500');
      } finally { await a.close(); await b.close(); }
    });
  }

  for (const contender of ['spend', 'adjustment', 'cash']) {
    await t.test(`spend versus ${contender} serializes available funds`, async () => {
      await reset({ paid: 1000 });
      const a = await cluster.connect(), b = await cluster.connect();
      try {
        await a.query(`begin; set local request.jwt.claim.sub='${user}'; set local role authenticated;
          select public.redeem_wallet_for_machine('${user}',1,700,'test');`);
        const action = contender === 'spend' ? spend(user, 700) : asUser(owner, contender === 'cash'
          ? `select public.admin_record_legal_cash_redemption(${wallet()},700,null,'test')`
          : `select public.admin_adjust_wallet(${wallet()},-700,-700,0,'test')`);
        const waiting = b.query(action);
        const rejected = assert.rejects(waiting, /Insufficient balance/);
        await blocked(db, b, a); await a.query('commit;'); await rejected;
        assert.equal((await state()).paid, 300);
        assert.equal((await state()).cache, 3);
      } finally { await a.close(); await b.close(); }
    });
  }

  await t.test('status lock wins against ordinary spend; pending load and cache refresh wait correctly', async () => {
    await reset();
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; set local request.jwt.claim.sub='${owner}';
        select public.admin_set_wallet_status(${wallet()},'locked');`);
      const waiting = b.query(spend(user, 100));
      const rejected = assert.rejects(waiting, /not active/);
      await blocked(db, b, a); await a.query('commit;'); await rejected;
    } finally { await a.close(); await b.close(); }
    const c = await cluster.connect(), d = await cluster.connect();
    try {
      await c.query(`begin; ${load(user, 2000, 'cache')};`);
      const waiting = d.query(`select public.sync_profile_wallet_balance(${wallet()});`);
      await blocked(db, d, c); await c.query('commit;'); await waiting;
      assert.equal((await state()).cache, 35);
    } finally { await c.close(); await d.close(); }
  });

  await t.test('RED: first eight replacements plus deployed resolver reproduce wallet/session deadlock', async () => {
    await reset(); await vendAndClaim();
    await db.query(originalResolver);
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; select id from public.cortina_vend_sessions where id='${sid}' for update;`);
      const resolving = b.query(`${resolve()};`).then(() => null, (error) => error.code);
      await blocked(db, b, a);
      const reversing = a.query(`select public.reverse_cortina_wallet_redemption('${sid}');`).then(() => null, (error) => error.code);
      // One participant is aborted by PostgreSQL's deadlock detector.
      const reverseCode = await reversing;
      await a.close();
      const resolveCode = await resolving;
      assert([reverseCode, resolveCode].includes('40P01'));
    } finally { await a.close(); await b.close(); await db.query(migration); }
  });

  await t.test('GREEN: busy session aborts resolver before wallet; rollback and retry credit once', async () => {
    await reset(); await vendAndClaim();
    const a = await cluster.connect();
    try {
      await a.query(`begin; select id from public.cortina_vend_sessions where id='${sid}' for update;`);
      await assert.rejects(once(`${resolve()};`), (error) => error.code === '55P03' && /busy; retry/.test(error.message));
      await once(`begin; select id from public.wallet_accounts where id=${wallet()} for no key update nowait; rollback;`);
      assert.equal(await db.query(`select status from public."Refunds" where refund_id=1;`), 'pending');
      assert.equal(await db.query('select count(*) from public.wallet_ledger_entries where refund_request_id=1;'), '0');
      await a.query('rollback;');
      assert.equal(JSON.parse(await db.query(`${resolve()};`)).alreadyResolved, false);
      assert.equal(JSON.parse(await db.query(`${resolve()};`)).alreadyResolved, true);
    } finally { await a.close(); }
  });

  await t.test('direct notification tracking precedes resolver without inverted refund/session locks', async () => {
    await reset(); await vendAndClaim();
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; update public."Refunds" set notification_sent_at=now() where refund_id=1;`);
      const waiting = b.query(`${resolve()};`);
      await blocked(db, b, a); await a.query('commit;');
      const result = JSON.parse(await waiting);
      assert.equal(result.alreadyResolved, false);
      assert.equal(result.notificationSent, false);
      assert.equal(JSON.parse(await db.query(`${resolve()};`)).notificationSent, true);
      assert.equal((await state()).promo, 400);
    } finally { await a.close(); await b.close(); }
  });

  await t.test('resolver holding session/wallet permits reversal after commit without deadlock', async () => {
    await reset(); await vendAndClaim();
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; ${resolve()};`);
      const waiting = b.query(`select public.reverse_cortina_wallet_redemption('${sid}');`);
      await blocked(db, b, a); await a.query('commit;');
      assert.equal(await waiting, 't');
      assert.equal(await db.query('select count(*) from public.wallet_ledger_entries where refund_request_id=1;'), '1');
      assert.equal(await db.query("select count(*) from public.wallet_ledger_entries where entry_type='void';"), '1');
      // Preserve deployed semantics: claim credit and later failed-vend reversal
      // are distinct records; changing their business interaction is not this patch.
      assert.equal((await state()).cache, 14);
    } finally { await a.close(); await b.close(); }
  });

  await t.test('reversal waits for anonymization without holding its redemption row', async () => {
    await reset(); await vendAndClaim();
    const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; select id from public.wallet_accounts where id=${wallet()} for no key update;`);
      const waiting = b.query(`select public.reverse_cortina_wallet_redemption('${sid}');`);
      await blocked(db, b, a);
      await a.query(`select public.anonymize_wallet_for_deleted_user('${user}','test'); commit;`);
      assert.equal(await waiting, 't');
      assert.equal(await db.query("select paid_balance_cents from public.wallet_balances where status='deleted';"), '1000');
    } finally { await a.close(); await b.close(); }
  });

  await t.test('unique failure rolls back reward/ledger changes; retry with valid identifiers succeeds', async () => {
    await reset({ paid: 0 });
    await db.query(`select public.record_wallet_load_from_stripe('${user}',1000,'pi_one',null,'ch_unique',null);`);
    const snapshot = await state();
    await assert.rejects(once(`select public.record_wallet_load_from_stripe('${user}',1000,'pi_two',null,'ch_unique',null);`), (error) => error.code === '23505');
    assert.deepEqual(await state(), snapshot);
    await db.query(`${load(user, 1000, 'valid_retry')};`);
    assert.equal((await state()).promo, 500);
  });
  t.diagnostic(guardPath ? 'Approved profile guard included as explicit local fixture input' : 'Profile guard compatibility NOT exercised: no explicit fixture input');
});
