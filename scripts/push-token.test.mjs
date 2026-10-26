import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { disposableCluster, blocked } = await import(process.env.PUSH_PG_HELPER ?? './test-support/policy-admission-pg.mjs');
const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), other = uid(2), sid = uid(11), otherSid = uid(12);
const installation = uid(100), secret = uid(101);
const jwt = (extra = {}) => ({ sub: user, session_id: sid, role: 'authenticated',
  aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra });
const context = (claims = jwt(), role = 'authenticated') => `set local role ${role};
  set local request.jwt.claims='${JSON.stringify(claims)}'; set local request.jwt.claim.sub='';`;
const prepare = (s = secret, id = installation) => `select public.prepare_push_installation('${id}','${s}')`;
const register = (s = secret, id = installation) => `${prepare(s,id)}; select public.register_push_token('${id}','${s}','dev','android','test-token-with-at-least-20-characters')`;
const revoke = (s = secret) => `select public.revoke_push_installation('${installation}','${s}')`;

test('push registrations reuse canonical admission in local PostgreSQL', { timeout: 180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
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
  ]) await db.query(await read(path));
  await db.query(`insert into auth.users(id,email_confirmed_at) values ('${uid(90)}',now());
    insert into auth.sessions(id,user_id,aal,created_at) values ('${uid(91)}','${uid(90)}','aal1',now());
    insert into private.push_installations(installation,secret_hash,user_id,session_id)
    values ('${uid(92)}',sha256(convert_to('${secret}','UTF8')),'${uid(90)}','${uid(91)}');`);
  const legacyBefore = await db.query(`select to_jsonb(p) from private.push_installations p where installation='${uid(92)}';`);
  const priorAcl = await db.query(`select jsonb_agg(jsonb_build_array(oid::regprocedure::text,proacl) order by oid)
    from pg_proc where oid in ('public.prepare_push_installation(uuid,uuid)'::regprocedure,
    'public.register_push_token(uuid,uuid,text,text,text)'::regprocedure,
    'public.revoke_push_installation(uuid,uuid)'::regprocedure);`);
  await db.query(await read('../supabase/migrations/20261001011048_push_registration_bounds.sql'));
  await t.test('additive bounds preserve historical row bytes and all three RPC ACLs', async () => {
    assert.equal(await db.query(`select to_jsonb(p)-'cleanup_session_id' from private.push_installations p where installation='${uid(92)}';`), legacyBefore);
    assert.equal(await db.query(`select cleanup_session_id is null from private.push_installations where installation='${uid(92)}';`), 't');
    assert.equal(await db.query(`select jsonb_agg(jsonb_build_array(oid::regprocedure::text,proacl) order by oid)
      from pg_proc where oid in ('public.prepare_push_installation(uuid,uuid)'::regprocedure,
      'public.register_push_token(uuid,uuid,text,text,text)'::regprocedure,
      'public.revoke_push_installation(uuid,uuid)'::regprocedure);`), priorAcl);
  });
  const run = async (sql, claims = jwt(), role = 'authenticated') => {
    const connection = await cluster.connect();
    try { return await connection.query(`begin; ${context(claims, role)} ${sql}; commit;`); }
    finally { await connection.close(); }
  };
  const reset = async () => {
    await db.query(`truncate private.push_installations; truncate auth.users cascade;
      insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${other}',now());
      insert into auth.sessions(id,user_id,aal,created_at) values
        ('${sid}','${user}','aal1',now()-interval '1 hour'),
        ('${otherSid}','${other}','aal1',now()-interval '1 hour');`);
    await run("select public.accept_loyalty_policy((select public.get_loyalty_policy_descriptor()->>'required_version'))");
    await run("select public.accept_loyalty_policy((select public.get_loyalty_policy_descriptor()->>'required_version'))", jwt({sub: other, session_id: otherSid}));
  };
  const fresh = (name, action) => t.test(name, async () => { await reset(); await action(); });
  const state = () => db.query(`select json_build_object('user',user_id,'revoked',revoked,'token',token)
    from private.push_installations where installation='${installation}'`);
  await fresh('valid registration stores only captured subject/session and refreshes idempotently', async () => {
    await run(register()); await run(register());
    assert.equal(await db.query('select count(*) from private.push_installations'), '1');
    assert.equal(JSON.parse(await state()).user, user);
  });
  await fresh('other user cannot take an installation even with its secret', async () => {
    await run(register());
    await assert.rejects(run(register(), jwt({sub: other, session_id: otherSid})), {code: 'PT403'});
    assert.equal(JSON.parse(await state()).user, user);
  });
  await fresh('wrong capability cannot alter or revoke installation', async () => {
    await run(register());
    await assert.rejects(run(register(uid(999))), {code: 'PT403'});
    await run(revoke(uid(999)), {}, 'anon');
    assert.equal(JSON.parse(await state()).revoked, false);
  });
  await fresh('post-logout anonymous capability revokes and clears data, repeat safe', async () => {
    await run(register()); await run(revoke(), {}, 'anon'); await run(revoke(), {}, 'anon');
    assert.deepEqual(JSON.parse(await state()), {user: null, revoked: true, token: null});
    await assert.rejects(run(register()), {code: 'PT403'});
  });
  await fresh('revocation before dispatch prevents late insertion', async () => {
    await run(prepare());
    await run(revoke(), {}, 'anon');
    await assert.rejects(run(register()), {code: 'PT403'});
  });
  await fresh('revocation waiting behind registration wins after commit', async () => {
    await run(prepare()); // The client commits preparation before token dispatch.
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${context()} ${register()};`);
    const waiting = waiter.query(`begin; ${context({}, 'anon')} ${revoke()}; commit;`);
    await blocked(db, waiter, holder); await holder.query('commit'); await waiting;
    assert.equal(JSON.parse(await state()).revoked, true);
  });
  await fresh('late registration waiting behind revocation is rejected', async () => {
    await run(prepare());
    const holder = await cluster.connect(), waiter = await cluster.connect();
    await holder.query(`begin; ${context({}, 'anon')} ${revoke()};`);
    const waiting = waiter.query(`begin; ${context()} ${register()}; commit;`);
    const rejected = assert.rejects(waiting, {code: 'PT403'});
    await blocked(db, waiter, holder); await holder.query('commit'); await rejected;
  });
  for (const [name, restriction, code] of [
    ['unverified', 'update auth.users set email_confirmed_at=null', 'PT403'],
    ['banned', "update auth.users set banned_until=now()+interval '1 hour'", 'PT403'],
    ['unknown role', 'update public.profiles set roles=null', 'PT403'],
    ['MFA required', "update public.profiles set roles='Admin'", 'PT403'],
    ['terms required', 'update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null', 'PT403'],
    ['expired session', "update auth.sessions set not_after=now()-interval '1 hour'", 'PT401'],
  ]) await fresh(`${name} rejects registration`, async () => {
    await db.query(restriction); await assert.rejects(run(register()), {code});
  });
  await fresh('pending deletion revokes all bindings and rejects subsequent registration', async () => {
    await run(register()); await run('select public.request_account_deletion()');
    assert.equal(JSON.parse(await state()).revoked, true);
    assert.equal(JSON.parse(await state()).token, null);
    await assert.rejects(run(register()), {code: 'PT403'});
  });
  await fresh('hard Auth deletion cascades token data', async () => {
    await run(register()); await db.query(`delete from auth.users where id='${user}'`);
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
  });
  await fresh('RPC and table grants deny direct reads/writes and privileged bypass', async () => {
    for (const role of ['anon','authenticated','service_role','supabase_auth_admin']) {
      await assert.rejects(run('select * from private.push_installations', jwt(), role), {code: '42501'});
    }
    for (const role of ['anon','service_role','supabase_auth_admin']) {
      await assert.rejects(run(register(), jwt(), role), {code: '42501'});
    }
  });
  await fresh('invalid platform and undersized token fail without persistence', async () => {
    await assert.rejects(run(`select public.register_push_token('${installation}','${secret}','dev','web','short')`), {code: '22023'});
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
  });
  await fresh('anonymous unknown capability cannot create database rows', async () => {
    await run(revoke(), {}, 'anon');
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
    await assert.rejects(run(prepare(), {}, 'anon'), {code: '42501'});
  });

  const budget = () => db.query(`select creations from private.push_creation_budget where user_id='${user}';`);
  const fill = async (count) => {
    for (let n = 0; n < count; n++) await run(prepare(secret, uid(100 + n)));
  };
  const revokeId = id => `select public.revoke_push_installation('${id}','${secret}')`;
  const churn = async count => {
    for (let n = 0; n < count; n++) {
      const id = uid(500 + n);
      await run(prepare(secret, id));
      await run(revokeId(id), {}, 'anon');
    }
  };
  await fresh('sixteen active slots cap seventeenth without changing rows or budget', async () => {
    await fill(16);
    await assert.rejects(run(prepare(secret, uid(999))), {code: 'PT429'});
    assert.equal(await db.query('select count(*) from private.push_installations'), '16');
    assert.equal(await budget(), '16');
  });
  await fresh('valid prepare replay and token refresh remain available at active cap', async () => {
    await fill(16);
    await run(register()); await run(register());
    assert.equal(await budget(), '16');
    assert.equal(JSON.parse(await state()).token, 'test-token-with-at-least-20-characters');
  });
  await fresh('capability cleanup releases live capacity but never refunds creation budget', async () => {
    await fill(16); await run(revoke(), {}, 'anon');
    await run(prepare(secret, uid(999)));
    assert.equal(await budget(), '17');
    assert.equal(await db.query('select count(*) from private.push_installations where not revoked'), '16');
  });
  await fresh('twenty new slots per hour cannot be bypassed by capability cleanup', async () => {
    await churn(19); await run(prepare());
    await run(register()); // Existing slot replay/refresh does not spend a token.
    await assert.rejects(run(prepare(secret, uid(999))), {code: 'PT429'});
    await run(revoke(), {}, 'anon');
    assert.equal(await budget(), '20');
    assert.equal(await db.query('select count(*) from private.push_installations where not revoked'), '0');
    await assert.rejects(run(prepare(secret, uid(999))), {code: 'PT429'});
  });
  await fresh('fresh Auth session and cascade cleanup do not reset account creation budget', async () => {
    await churn(20);
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values ('${uid(13)}','${user}','aal1',now());
      delete from auth.sessions where id='${sid}';`);
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
    await assert.rejects(run(prepare(secret, uid(999)), jwt({session_id: uid(13)})), {code: 'PT429'});
    assert.equal(await budget(), '20');
  });
  await fresh('expired fixed creation window renews without deleting tombstones', async () => {
    await churn(20);
    await db.query(`update private.push_creation_budget set window_started_at=clock_timestamp()-interval '1 hour 1 second';`);
    await run(prepare());
    assert.equal(await budget(), '1');
    assert.equal(await db.query('select count(*) from private.push_installations'), '21');
  });
  await fresh('capacity and creation budgets are bound to account not caller parameters', async () => {
    await fill(16);
    await run(prepare(secret, uid(999)), jwt({sub: other, session_id: otherSid}));
    assert.equal(await db.query(`select creations from private.push_creation_budget where user_id='${other}'`), '1');
    assert.equal(await budget(), '16');
  });
  await fresh('invalid ownership and capability replay cannot spend another creation', async () => {
    await run(prepare());
    await assert.rejects(run(prepare(uid(999))), {code: 'PT403'});
    await assert.rejects(run(prepare(), jwt({sub: other, session_id: otherSid})), {code: 'PT403'});
    assert.equal(await budget(), '1');
    assert.equal(await db.query('select count(*) from private.push_creation_budget'), '1');
  });
  await fresh('repeat capability cleanup does not rewrite terminal row or timestamps', async () => {
    await run(register()); await run(revoke(), {}, 'anon');
    const before = await db.query(`select xmin::text||':'||to_jsonb(p)::text from private.push_installations p where installation='${installation}';`);
    await run(revoke(), {}, 'anon'); await run(revoke(uid(999)), {}, 'anon');
    assert.equal(await db.query(`select xmin::text||':'||to_jsonb(p)::text from private.push_installations p where installation='${installation}';`), before);
  });
  await fresh('retired slot keeps only cleanup anchor until existing Auth session deletion', async () => {
    await run(register()); await run(revoke(), {}, 'anon');
    assert.deepEqual(JSON.parse(await state()), {user: null, revoked: true, token: null});
    assert.equal(await db.query(`select cleanup_session_id from private.push_installations`), sid);
    await db.query(`delete from auth.sessions where id='${sid}'`);
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
    assert.equal(await budget(), '1');
  });
  await fresh('valid session rebinding moves cleanup anchor instead of deleting refreshed token with old session', async () => {
    await run(register());
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at) values ('${uid(13)}','${user}','aal1',now());`);
    await run(register(), jwt({session_id: uid(13)}));
    await db.query(`delete from auth.sessions where id='${sid}'`);
    assert.equal(await db.query('select cleanup_session_id from private.push_installations'), uid(13));
    assert.equal(JSON.parse(await state()).revoked, false);
  });
  await fresh('known legacy slot fills anchor only during authorized cleanup', async () => {
    await run(register()); await db.query('update private.push_installations set cleanup_session_id=null');
    await run(revoke(), {}, 'anon');
    assert.equal(await db.query('select cleanup_session_id from private.push_installations'), sid);
    await db.query(`delete from auth.sessions where id='${sid}'`);
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
  });
  await fresh('lifecycle revocation stays terminal and capability cleanup still clears operational identity', async () => {
    await run(register()); await run('select public.request_account_deletion()');
    await run(revoke(), {}, 'anon');
    assert.deepEqual(JSON.parse(await state()), {user: null, revoked: true, token: null});
    assert.equal(await budget(), '1');
    await assert.rejects(run(prepare()), {code: 'PT403'});
  });
  await fresh('budget and cleanup anchor expose no client or service mutation surface', async () => {
    for (const role of ['anon','authenticated','service_role','supabase_auth_admin']) {
      for (const sql of ['select * from private.push_creation_budget',
        'delete from private.push_creation_budget',
        'update private.push_creation_budget set creations=0',
        'update private.push_installations set cleanup_session_id=null']) {
        await assert.rejects(run(sql, jwt(), role), {code: '42501'});
      }
    }
    assert.equal(await db.query(`select relrowsecurity from pg_class where oid='private.push_creation_budget'::regclass`), 't');
  });

  const expireWhileBlocked = async (hold, operation, verify) => {
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      await holder.query(`begin; ${hold};`);
      const waiting = waiter.query(`begin; ${context()} ${operation}; commit;`);
      const rejected = assert.rejects(waiting, {code: 'PT401'});
      await blocked(db, waiter, holder);
      await db.query(`update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='${sid}'`);
      await holder.query('commit'); await rejected;
      await verify();
    } finally { await holder.close(); await waiter.close(); }
  };
  await fresh('prepare rechecks admission after profile serialization wait', async () => {
    await expireWhileBlocked(`select id from public.profiles where id='${user}' for no key update`, prepare(), async () => {
      assert.equal(await db.query('select count(*) from private.push_installations'), '0');
      assert.equal(await db.query('select count(*) from private.push_creation_budget'), '0');
    });
  });
  await fresh('prepare valid replay rechecks after installation lock wait', async () => {
    await run(prepare());
    await expireWhileBlocked(`select installation from private.push_installations where installation='${installation}' for update`, prepare(), async () => {
      assert.equal(await budget(), '1');
    });
  });
  await fresh('prepare budget wait rollback leaves no installation or charged creation', async () => {
    await db.query(`insert into private.push_creation_budget values ('${user}',clock_timestamp(),0)`);
    await expireWhileBlocked(`select user_id from private.push_creation_budget where user_id='${user}' for update`, prepare(), async () => {
      assert.equal(await budget(), '0');
      assert.equal(await db.query('select count(*) from private.push_installations'), '0');
    });
  });
  await db.query(`create table public.push_wait_fixture(id integer primary key);
    insert into public.push_wait_fixture values (1);
    create function public.push_wait_fixture_trigger() returns trigger language plpgsql as $$
    begin perform 1 from public.push_wait_fixture where id=1 for update; return new; end; $$;`);
  await fresh('prepare post-insert wait rechecks and atomically refunds failed creation', async () => {
    await db.query(`create trigger push_wait_fixture after insert on private.push_installations
      for each row execute function public.push_wait_fixture_trigger()`);
    try {
      await expireWhileBlocked('select id from public.push_wait_fixture where id=1 for update', prepare(), async () => {
        assert.equal(await db.query('select count(*) from private.push_installations'), '0');
        assert.equal(await db.query('select count(*) from private.push_creation_budget'), '0');
      });
    } finally { await db.query('drop trigger push_wait_fixture on private.push_installations'); }
  });
  for (const limit of ['active', 'hourly']) await fresh(`concurrent preparations cannot exceed ${limit} bound`, async () => {
    if (limit === 'active') await fill(15); else await churn(19);
    const holder = await cluster.connect(), waiter = await cluster.connect();
    try {
      await holder.query(`begin; ${context()} ${prepare(secret, uid(800))};`);
      const waiting = waiter.query(`begin; ${context()} ${prepare(secret, uid(801))}; commit;`);
      const rejected = assert.rejects(waiting, {code: 'PT429'});
      await blocked(db, waiter, holder);
      await holder.query('commit'); await rejected;
      assert.equal(await budget(), limit === 'active' ? '16' : '20');
      assert.equal(await db.query(`select count(*) from private.push_installations where installation='${uid(801)}'`), '0');
    } finally { await holder.close(); await waiter.close(); }
  });
  await fresh('registration post-trigger terms change rolls token and authority change back', async () => {
    await run(prepare());
    await db.query(`create function public.push_terms_fixture_trigger() returns trigger language plpgsql as $$
      begin update public.profiles set loyalty_policy_version=null,loyalty_policy_accepted_at=null where id=new.user_id;
      return new; end; $$;
      create trigger push_terms_fixture after update on private.push_installations
      for each row execute function public.push_terms_fixture_trigger()`);
    try {
      await assert.rejects(run(`select public.register_push_token('${installation}','${secret}','dev','android','test-token-with-at-least-20-characters')`), {code: 'PT403'});
      assert.equal(JSON.parse(await state()).token, null);
      assert.equal(await run("select public.get_admission_status()->>'next_step'"), 'home');
    } finally { await db.query('drop trigger push_terms_fixture on private.push_installations'); }
  });
  await fresh('invalid prepare cannot initialize budget or slot', async () => {
    await assert.rejects(run(`select public.prepare_push_installation(null,'${secret}')`), {code: '22023'});
    assert.equal(await db.query('select count(*) from private.push_creation_budget'), '0');
    assert.equal(await db.query('select count(*) from private.push_installations'), '0');
  });
});
