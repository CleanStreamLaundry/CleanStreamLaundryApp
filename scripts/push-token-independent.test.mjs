import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { disposableCluster, blocked } = await import(process.env.PUSH_PG_HELPER ?? './test-support/policy-admission-pg.mjs');
const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11), otherSid = uid(12), installation = uid(100), secret = uid(101);
const claims = (otherUser = false) => ({ sub: otherUser ? other : user, session_id: otherUser ? otherSid : sid,
  role: 'authenticated', aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600 });
const context = (who = claims(), role = 'authenticated') => `set local role ${role};
  set local request.jwt.claims='${JSON.stringify(who)}'; set local request.jwt.claim.sub='';`;
const prepare = (id = installation) => `select public.prepare_push_installation('${id}','${secret}')`;
const register = (env = 'dev', platform = 'android', id = installation) =>
  `select public.register_push_token('${id}','${secret}','${env}','${platform}','independent-test-token-1234567890')`;
const revoke = `select public.revoke_push_installation('${installation}','${secret}')`;

test('independent push-token authority, session and isolation checks', { timeout: 120000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN), db = await cluster.connect();
  for (const path of [
    '../supabase/tests/loyalty_policy_acceptance.fixture.sql',
    '../supabase/migrations/20260929223124_protect_profile_authority.sql',
    '../supabase/migrations/20260929234955_loyalty_policy_acceptance.sql',
    '../supabase/tests/account_admission.fixture.sql',
    '../supabase/migrations/20260930005456_account_admission.sql',
    '../supabase/tests/profile_terms_admission.fixture.sql',
    '../supabase/migrations/20260930013417_enforce_profile_terms_admission.sql',
    '../supabase/tests/account_lifecycle.fixture.sql',
    '../supabase/migrations/20260930063923_recoverable_account_deletion.sql',
    '../supabase/migrations/20260930130013_push_token_registration.sql',
    '../supabase/migrations/20261001011048_push_registration_bounds.sql',
  ]) await db.query(await read(path));
  const run = async (sql, who = claims(), role = 'authenticated') => {
    const c = await cluster.connect();
    try { return await c.query(`begin; ${context(who, role)} ${sql}; commit;`); } finally { await c.close(); }
  };
  const reset = async () => {
    await db.query(`truncate private.push_installations; truncate auth.users cascade;
      insert into auth.users(id,email_confirmed_at) values('${user}',now()),('${other}',now());
      insert into auth.sessions(id,user_id,aal,created_at) values
      ('${sid}','${user}','aal1',now()-interval '1 hour'),('${otherSid}','${other}','aal1',now()-interval '1 hour');`);
    for (const who of [claims(), claims(true)]) await run("select public.accept_loyalty_policy(public.get_loyalty_policy_descriptor()->>'required_version')", who);
  };
  const fresh = (name, fn) => t.test(name, async () => { await reset(); await fn(); });
  const row = async () => JSON.parse(await db.query(`select row_to_json(p) from private.push_installations p where installation='${installation}';`) || 'null');

  await fresh('an empty committed slot still needs anonymous cleanup before account change', async () => {
    await run(prepare());
    assert.equal((await row()).token, null);
    await assert.rejects(run(prepare(), claims(true)), { code: 'PT403' });
    await run(revoke, {}, 'anon');
    await run(`${prepare(uid(200))};${register('dev', 'android', uid(200))}`, claims(true));
    assert.equal((await row()).revoked, true);
  });
  for (const [env, platform] of [['prod', 'android'], ['dev', 'ios']]) await fresh(`bound slot cannot move to ${env}/${platform}`, async () => {
    await run(`${prepare()};${register()}`);
    await assert.rejects(run(register(env, platform)), { code: 'PT403' });
    assert.equal((await row()).environment, 'dev'); assert.equal((await row()).platform, 'android');
  });
  await fresh('same token may exist in separate Firebase projects but not duplicate within one', async () => {
    await run(`${prepare()};${register()};${prepare(uid(200))};${register('prod', 'android', uid(200))}`);
    await run(prepare(uid(300)));
    await assert.rejects(run(register('dev', 'android', uid(300))), { code: 'PT503' });
    assert.equal(await db.query('select count(*) from private.push_installations where token is not null;'), '2');
  });
  await fresh('session expiration during installation lock wait rolls registration back', async () => {
    await run(prepare()); const a = await cluster.connect(), b = await cluster.connect();
    try {
      await a.query(`begin; select installation from private.push_installations where installation='${installation}' for update;`);
      const waiting = b.query(`begin; ${context()} ${register()}; commit;`);
      const rejected = assert.rejects(waiting, { code: 'PT401' });
      await blocked(db, b, a);
      await db.query(`update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='${sid}';`);
      await a.query('commit;'); await rejected;
      assert.equal((await row()).token, null);
    } finally { await a.close(); await b.close(); }
  });
  await fresh('deletion before delayed registration permanently closes capability', async () => {
    await run(prepare()); await run('select public.request_account_deletion()');
    await assert.rejects(run(register()), { code: 'PT403' });
    assert.equal((await row()).revoked, true); assert.equal((await row()).token, null);
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values('${uid(13)}','${user}','aal1',clock_timestamp());`);
    const freshSession = { ...claims(), session_id: uid(13) };
    await run('select public.restore_account()', freshSession);
    await assert.rejects(run(register(), freshSession), { code: 'PT403' });
    assert.equal((await row()).revoked, true);
  });
  await fresh('Auth session deletion removes the associated token row', async () => {
    await run(`${prepare()};${register()}`);
    await db.query(`delete from auth.sessions where id='${sid}';`);
    assert.equal(await row(), null);
  });
  await fresh('capability is hashed and all private writes stay denied', async () => {
    await run(prepare());
    assert.equal(await db.query(`select secret_hash=sha256(convert_to('${secret}','UTF8')) from private.push_installations;`), 't');
    for (const role of ['anon', 'authenticated', 'service_role', 'supabase_auth_admin']) {
      for (const sql of ['delete from private.push_installations', "update private.push_installations set revoked=false"]) {
        await assert.rejects(run(sql, claims(), role), { code: '42501' });
      }
    }
  });
});
