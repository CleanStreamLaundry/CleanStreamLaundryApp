import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const prerequisites = [
  '../supabase/tests/loyalty_policy_acceptance.fixture.sql',
  '../supabase/migrations/20260929223124_protect_profile_authority.sql',
  '../supabase/migrations/20260929234955_loyalty_policy_acceptance.sql',
  '../supabase/tests/account_admission.fixture.sql',
  '../supabase/migrations/20260930005456_account_admission.sql',
  '../supabase/tests/profile_terms_admission.fixture.sql',
  '../supabase/migrations/20260930013417_enforce_profile_terms_admission.sql',
  '../supabase/migrations/20261002211015_server_managed_loyalty_terms.sql',
  '../supabase/migrations/20261003115914_readonly_loyalty_admission.sql',
];
const user = '00000000-0000-4000-8000-000000000001';
const session = '00000000-0000-4000-8000-000000000011';
const literal = value => `'${value.replaceAll("'", "''")}'`;
const claims = { sub: user, session_id: session, role: 'authenticated', aal: 'aal1',
  exp: Math.floor(Date.now() / 1000) + 3600 };
const context = `set local request.jwt.claims=${literal(JSON.stringify(claims))};
  set local request.jwt.claim.sub=''; set local role authenticated;`;

test('server-managed loyalty publications preserve consent and history', { timeout: 120000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN);
  const db = await cluster.connect();
  for (const path of prerequisites) await db.query(await read(path));
  await db.query(`insert into auth.users(id,email_confirmed_at) values ('${user}',now());
    insert into auth.sessions(id,user_id,aal) values ('${session}','${user}','aal1');`);
  const run = async sql => {
    const connection = await cluster.connect();
    try { return await connection.query(sql); } finally { await connection.close(); }
  };
  const call = sql => run(`begin; ${context} ${sql}; commit;`);
  const rejects = (sql, code) => assert.rejects(run(sql), error => error.code === code);
  const policy = JSON.parse(await db.query('select public.get_loyalty_policy_descriptor();'));

  await t.test('anonymous JSON reads have exact hash and approved credit protection', async () => {
    const publicPolicy = JSON.parse(await run('begin; set local role anon; select public.get_loyalty_policy_descriptor(); commit;'));
    assert.deepEqual(publicPolicy, policy);
    assert.equal(policy.required_version, '2026-10-02.1');
    assert.equal(createHash('sha256').update(policy.policy_text).digest('hex'), policy.policy_sha256);
    const document = JSON.parse(policy.policy_text);
    assert.equal(document.title, 'Loyalty Program Terms');
    assert.equal(document.sections.length, 9);
    assert.match(policy.policy_text, /Unused purchased laundry credit is not forfeited/);
  });
  await t.test('clients cannot publish or edit terms, even if signed in', async () => {
    for (const role of ['anon', 'authenticated']) {
      await rejects(`begin; set local role ${role}; update public.loyalty_policy_documents set is_current=false; commit;`, '42501');
      await rejects(`begin; set local role ${role}; insert into public.loyalty_policy_documents(version,document) values ('bad','{}'); commit;`, '42501');
    }
    await rejects("begin; set local role anon; select public.accept_loyalty_policy('2026-10-02.1'); commit;", '42501');
  });
  await t.test('malformed documents and rewriting or deleting history are rejected', async () => {
    await rejects("insert into public.loyalty_policy_documents(version,document) values ('bad','{}');", '23514');
    await rejects("update public.loyalty_policy_documents set document=jsonb_set(document,'{title}','\"Changed\"');", '23514');
    await rejects('delete from public.loyalty_policy_documents;', '23514');
  });
  await t.test('agreement records version/time once and allows Home', async () => {
    const first = JSON.parse(await call("select public.accept_loyalty_policy('2026-10-02.1')"));
    const again = JSON.parse(await call("select public.accept_loyalty_policy('2026-10-02.1')"));
    assert.equal(first.acceptance_required, false);
    assert.equal(first.accepted_at, again.accepted_at);
    assert.equal(JSON.parse(await call('select public.get_admission_status()')).next_step, 'home');
  });
  await t.test('new publication requires its own consent and rejects stale agreement', async () => {
    await db.query(`begin; update public.loyalty_policy_documents set is_current=false;
      insert into public.loyalty_policy_documents(version,document,is_current)
      select '2026-10-02.2',document,true from public.loyalty_policy_documents where version='2026-10-02.1'; commit;`);
    assert.equal(JSON.parse(await call('select public.get_admission_status()')).next_step, 'review_terms');
    await assert.rejects(call("select public.accept_loyalty_policy('2026-10-02.1')"), e => e.code === '22023');
    assert.equal(await db.query(`select loyalty_policy_version from public.profiles where id='${user}';`), '2026-10-02.1');
  });
  await t.test('publication waits for an in-flight acceptance transaction', async () => {
    const accepting = await cluster.connect();
    const publishing = await cluster.connect();
    await accepting.query(`begin; ${context} select public.accept_loyalty_policy('2026-10-02.2');`);
    const update = publishing.query('begin; update public.loyalty_policy_documents set is_current=false where is_current;');
    await blocked(db, publishing, accepting);
    await accepting.query('commit;');
    await update;
    await publishing.query('rollback;');
    assert.equal(JSON.parse(await call('select public.get_admission_status()')).next_step, 'home');
  });
  await t.test('acceptance retries if publication changes while acquiring its lock', async () => {
    const publishing = await cluster.connect();
    const accepting = await cluster.connect();
    await publishing.query(`begin; update public.loyalty_policy_documents set is_current=false where is_current;
      insert into public.loyalty_policy_documents(version,document,is_current)
      select '2026-10-02.3',document,true from public.loyalty_policy_documents where version='2026-10-02.2';`);
    const pending = accepting.query(`begin; ${context} select public.accept_loyalty_policy('2026-10-02.3');`);
    const rejected = assert.rejects(pending, error => error.code === '22023');
    await blocked(db, accepting, publishing);
    await publishing.query('commit;');
    await rejected;
    assert.equal(await db.query(`select loyalty_policy_version from public.profiles where id='${user}';`), '2026-10-02.2');
    const accepted = JSON.parse(await call("select public.accept_loyalty_policy('2026-10-02.3')"));
    assert.equal(accepted.acceptance_required, false);
  });
  await t.test('payment wording revision preserves other terms, history and consent', async () => {
    await db.query(`begin; update public.loyalty_policy_documents set is_current=false;
      update public.loyalty_policy_documents set is_current=true where version='2026-10-02.1'; commit;`);
    const migration = await read('../supabase/migrations/20261003111631_simplify_loyalty_payment_terms.sql');
    await db.query(migration);
    const revised = JSON.parse(await db.query('select public.get_loyalty_policy_descriptor();'));
    assert.equal(revised.required_version, '2026-10-03.1');
    assert.equal(createHash('sha256').update(revised.policy_text).digest('hex'), revised.policy_sha256);
    const expected = JSON.parse(policy.policy_text);
    expected.effective_date = '2026-10-03';
    expected.sections[4].paragraphs = [
      'Stripe processes card payments and refunds made through the Clean Stream app and website. Nayax supports payments at participating machines and helps start connected washers and dryers. Clean Stream remains your contact for laundry-service, payment, and wallet issues.',
      'We share the information needed to process payments and operate machines with these providers, as described in our Privacy Policy.',
    ];
    assert.deepEqual(JSON.parse(revised.policy_text), expected);
    assert.equal(await db.query("select document::text from public.loyalty_policy_documents where version='2026-10-02.1';"), policy.policy_text);
    assert.equal(await db.query(`select loyalty_policy_version from public.profiles where id='${user}';`), '2026-10-02.3');
    assert.equal(JSON.parse(await call('select public.get_admission_status()')).next_step, 'review_terms');
    await assert.rejects(call("select public.accept_loyalty_policy('2026-10-02.1')"), e => e.code === '22023');
    assert.equal(JSON.parse(await call("select public.accept_loyalty_policy('2026-10-03.1')")).acceptance_required, false);
    await rejects(migration, '55000');
    assert.equal(JSON.parse(await db.query('select public.get_loyalty_policy_descriptor();')).required_version, '2026-10-03.1');
  });
});
