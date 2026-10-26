// Offline: PGLITE_MODULE must reference the approved existing read-only package.
import test, { before, beforeEach, afterEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { sqlFiles, cleanupPath, read, seedSQL, user, other, token, uid,
  requestTime, claimSQL, retrySQL, previewSQL, protectedTables, authContext } from './test-support/account-cleanup.mjs';

const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const one = async (sql) => (await db.query(sql)).rows[0];
const result = async (sql) => (await one(sql)).result;
const stored = () => one('select * from private.account_cleanup_jobs');
const reject = async (sql, code = '42501') => {
  await db.exec('savepoint rejected');
  await assert.rejects(db.query(sql), { code });
  await db.exec('rollback to savepoint rejected');
};
const snapshot = async () => {
  const data = {};
  for (const table of protectedTables) data[table] = (await one(
    `select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') as data from ${table} t`,
  )).data;
  return data;
};
let beforeACL, originalFunctions;
const acls = () => one(`select jsonb_agg(jsonb_build_array(oid::text,relacl) order by oid) as acl
  from pg_class where relnamespace in ('public'::regnamespace,'auth'::regnamespace) and relkind='r'`);
const authority = () => one(`select jsonb_agg(pg_get_functiondef(oid) order by oid) as defs from pg_proc
  where oid in ('public.restore_account()'::regprocedure,'public.request_account_deletion()'::regprocedure,
    'private.current_account_access()'::regprocedure)`);
before(async () => {
  for (const path of sqlFiles) await db.exec(await read(path));
  beforeACL = await acls(); originalFunctions = await authority();
  await db.exec(await read(cleanupPath));
});
beforeEach(async () => { await db.exec('begin'); await db.exec(seedSQL); });
afterEach(() => db.exec('rollback'));
after(() => db.close());

test('existing public/Auth ACLs and lifecycle/admission RPC bodies are unchanged', async () => {
  assert.deepEqual(await acls(), beforeACL);
  assert.deepEqual(await authority(), originalFunctions);
});
test('preview is read-only, is not execution approval, and adds no job', async () => {
  const beforeData = await snapshot();
  const preview = await result(previewSQL);
  assert.equal(preview.execution_enabled, false);
  assert.equal(preview.candidates.length, 1);
  assert.equal(preview.candidates[0].blocker, null);
  assert.equal(preview.candidates[0].eligible_to_claim, true);
  assert.equal(await stored(), undefined);
  assert.deepEqual(await snapshot(), beforeData);
});
test('lost claim response replays idempotently and preserves lifecycle, Auth, financial and mail data', async () => {
  const beforeData = await snapshot();
  const first = await result(claimSQL());
  assert.equal(first.claimed, true);
  assert.equal(first.execution_enabled, false);
  assert.equal(first.claim.state, 'leased');
  assert.equal(first.claim.attempts, 1);
  assert.deepEqual(await result(claimSQL()), first);
  assert.deepEqual(await result(claimSQL(uid(22))), { claimed: false, reason: 'lease_active' });
  assert.equal((await result(previewSQL)).candidates[0].blocker, 'lease_active');
  assert.deepEqual(await snapshot(), beforeData);
});
test('request identity preserves microseconds, not rounded client milliseconds', async () => {
  await result(claimSQL());
  assert.equal((await result(claimSQL(token, `${requestTime}+interval '1 microsecond'`))).reason, 'request_not_pending');
  assert.equal((await result(retrySQL(token, 'transient_failure', `${requestTime}+interval '1 microsecond'`))).reason, 'request_not_pending');
});
test('expired lease rotates token and rejects stale release', async () => {
  await result(claimSQL());
  await db.exec("update private.account_cleanup_jobs set lease_until=clock_timestamp()-interval '1 second'");
  assert.equal((await result(claimSQL())).reason, 'claim_id_reused');
  assert.equal((await result(claimSQL(uid(22)))).claim.attempts, 2);
  assert.deepEqual(await result(retrySQL()), { released: false, reason: 'stale_claim' });
  await db.exec("update private.account_cleanup_jobs set lease_until=clock_timestamp()-interval '1 second'");
  assert.equal((await result(claimSQL())).reason, 'claim_id_reused');
});
test('explicit retry is idempotent, delayed, and cannot be released by a foreign token', async () => {
  await result(claimSQL());
  assert.equal((await result(retrySQL(uid(99)))).reason, 'stale_claim');
  assert.deepEqual(await result(retrySQL()), { released: true, state: 'retry' });
  const first = await stored();
  await result(retrySQL());
  assert.deepEqual(await stored(), first);
  assert.equal((await result(claimSQL(uid(22)))).reason, 'retry_wait');
  assert.equal((await one('select retry_after-lease_until >= interval \'59 seconds\' as bounded from private.account_cleanup_jobs')).bounded, true);
});
test('unknown outcome is durably parked and cannot be downgraded or automatically replayed', async () => {
  await result(claimSQL());
  assert.deepEqual(await result(retrySQL(token, 'outcome_unknown')), { released: true, state: 'outcome_unknown' });
  assert.equal((await result(claimSQL(uid(22)))).reason, 'outcome_unknown');
  assert.equal((await result(retrySQL())).reason, 'stale_claim');
  assert.deepEqual(await result(retrySQL(token, 'outcome_unknown')), { released: true, state: 'outcome_unknown' });
  assert.equal((await result(previewSQL)).candidates[0].blocker, 'outcome_unknown');
});
test('five expired leases exhaust the retry budget', async () => {
  for (let attempt = 1; attempt <= 5; attempt++) {
    assert.equal((await result(claimSQL(uid(20 + attempt)))).claim.attempts, attempt);
    await db.exec("update private.account_cleanup_jobs set lease_until=clock_timestamp()-interval '1 second'");
  }
  assert.equal((await result(claimSQL(uid(30)))).reason, 'retry_exhausted');
});
test('expiry is inclusive, and pre-deadline requests cannot be claimed', async () => {
  await db.exec(`update private.account_lifecycle set deletion_requested_at=now()-interval '719 hours',restore_until=now()+interval '1 hour'`);
  assert.equal((await result(claimSQL())).reason, 'recovery_window_open');
  assert.equal((await result(previewSQL)).candidates.length, 0);
  await db.exec("update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours',restore_until=now()");
  assert.equal((await result(claimSQL())).claimed, true);
});
test('existing request remains exactly 720 hours in a non-UTC timezone and expired restore stays rejected', async () => {
  await db.exec("delete from private.account_lifecycle; set local timezone='America/New_York'");
  await db.exec(authContext());
  await result('select public.request_account_deletion() as result');
  await db.exec('reset role');
  assert.equal((await one(`select extract(epoch from restore_until-deletion_requested_at)=2592000 as exact
    from private.account_lifecycle`)).exact, true);
  await reject('update private.account_lifecycle set restored_at=restore_until', '23514');
  await db.exec("update private.account_lifecycle set deletion_requested_at=now()-interval '720 hours',restore_until=now()");
  await db.exec(authContext());
  assert.equal((await result('select public.get_account_lifecycle_status() as result')).reason, 'restore_expired');
  await reject('select public.restore_account()', 'PT403');
});
test('restore preserves marketing suppression; only explicit re-request starts another recovery window', async () => {
  await db.exec("update private.account_lifecycle set deletion_requested_at=now()-interval '719 hours',restore_until=now()+interval '1 hour'");
  const old = (await one('select deletion_requested_at::text as t from private.account_lifecycle')).t;
  // The preceding fixture update fires the actual suppression trigger. Restore
  // must also suppress rows that appear later, as the original rollback suite asserts.
  await db.exec("update private.newsletter_consent set unsubscribed_at=null,suppression_reason=null,confirm_hash=repeat('a',64); update private.mail_outbox set state='ready',last_error=null");
  await db.exec(authContext());
  assert.equal((await result('select public.restore_account() as result')).account_state, 'legacy_active');
  await db.exec('reset role');
  assert.equal((await result(claimSQL())).reason, 'request_not_pending');
  assert.equal((await result(previewSQL)).candidates.length, 0);
  assert.equal((await one('select marketing_suppressed from private.account_lifecycle')).marketing_suppressed, true);
  assert.equal((await one('select state from private.mail_outbox')).state, 'suppressed');
  const consent = await one('select unsubscribed_at,suppression_reason,confirm_hash from private.newsletter_consent');
  assert.notEqual(consent.unsubscribed_at, null);
  assert.equal(consent.suppression_reason, 'account_deletion');
  assert.equal(consent.confirm_hash, null);
  await db.exec(authContext());
  assert.equal((await result('select public.request_account_deletion() as result')).account_state, 'pending_deletion');
  await db.exec('reset role');
  assert.equal((await result(claimSQL())).reason, 'recovery_window_open');
  assert.equal((await result(claimSQL(token, `'${old}'::timestamptz`))).reason, 'request_not_pending');
  assert.equal(await stored(), undefined);
});
test('synthetic generation drift replaces one job row and rejects old request/token completions', async () => {
  await result(claimSQL());
  const old = (await one('select deletion_requested_at::text as t from private.account_lifecycle')).t;
  // Adversarial trusted-state drift only: public restore cannot succeed once a
  // request is expired/claimable, and duplicate deletion never advances its clock.
  await db.exec("update private.account_lifecycle set deletion_requested_at=deletion_requested_at+interval '1 minute',restore_until=restore_until+interval '1 minute'");
  assert.equal((await result(claimSQL(uid(22), `'${old}'::timestamptz`))).reason, 'request_not_pending');
  const next = await result(claimSQL(uid(22)));
  assert.equal(next.claimed, true);
  assert.equal(next.claim.attempts, 1);
  assert.equal((await result(retrySQL())).reason, 'stale_claim');
  assert.equal((await result(retrySQL(token, 'transient_failure', `'${old}'::timestamptz`))).reason, 'request_not_pending');
  assert.equal((await one('select count(*)::int as n from private.account_cleanup_jobs')).n, 1);
});
test('preview paginates past leased rows without exposing lease tokens', async () => {
  await result(claimSQL());
  await db.exec(`insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
    select '${other}',deletion_requested_at,restore_until from private.account_lifecycle where user_id='${user}'`);
  const page = await result('select public.preview_account_cleanup(1) as result');
  assert.equal(page.next_cursor, user);
  assert.deepEqual(page.candidates.map((c) => c.user_id), [user]);
  const next = await result(`select public.preview_account_cleanup(1,'${page.next_cursor}') as result`);
  assert.deepEqual(next.candidates.map((c) => c.user_id), [other]);
  assert.deepEqual(Object.keys(next.candidates[0]).sort(),
    ['user_id','deletion_requested_at','restore_until','blocker','eligible_to_claim'].sort());
});
test('invalid limits, null claim identities and unbounded error strings fail closed', async () => {
  for (const n of ['null', '0', '101']) await reject(`select public.preview_account_cleanup(${n})`, '22023');
  await reject(`select public.claim_account_cleanup(null,${requestTime},'${token}')`, '22023');
  await reject(retrySQL(token, 'secret error'), '22023');
});
for (const role of ['anon', 'authenticated', 'service_role', 'supabase_auth_admin']) {
  test(`${role} cannot directly read/write private job state`, async () => {
    await db.exec(`set local role ${role}`);
    await reject('select * from private.account_cleanup_jobs');
    await reject('delete from private.account_cleanup_jobs');
    await reject("update private.account_cleanup_jobs set state='retry'");
  });
}
for (const role of ['anon', 'authenticated', 'supabase_auth_admin']) {
  test(`${role} has no cleanup RPC authority, even with spoofed service JWT claims`, async () => {
    await db.exec(`set local request.jwt.claims='{"role":"service_role"}'; set local role ${role}`);
    await reject(previewSQL);
    await reject(`select public.claim_account_cleanup('${user}',now(),'${token}')`);
    await reject(`select public.retry_account_cleanup('${user}',now(),'${token}','transient_failure')`);
  });
}
test('service role gets only three job RPCs and the single private job table retains RLS', async () => {
  await db.exec('set local role service_role');
  assert.equal((await result(previewSQL)).execution_enabled, false);
  await db.exec('reset role');
  assert.equal((await one(`select bool_and(relrowsecurity) as guarded from pg_class
    where oid='private.account_cleanup_jobs'::regclass`)).guarded, true);
  assert.equal((await one(`select count(*)::int as n from pg_proc where proname like '%account_cleanup%'
    and has_function_privilege('service_role',oid,'execute')`)).n, 3);
});
