import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { disposableCluster, blocked } from './test-support/policy-admission-pg.mjs';

const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const user = uid(1), sid = uid(11), freshSid = uid(13), factor = uid(21);
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const context = (extra = {}) => `set local role authenticated; set local request.jwt.claim.sub='';
  set local request.jwt.claims=${q(JSON.stringify({ sub: user, session_id: freshSid,
    role: 'authenticated', aal: 'aal1', exp: Math.floor(Date.now() / 1000) + 3600, ...extra }))};`;
const paths = [
  'supabase/tests/loyalty_policy_acceptance.fixture.sql',
  'supabase/migrations/20260929223124_protect_profile_authority.sql',
  'supabase/migrations/20260929234955_loyalty_policy_acceptance.sql',
  'supabase/tests/account_admission.fixture.sql',
  'supabase/migrations/20260930005456_account_admission.sql',
  'supabase/tests/profile_terms_admission.fixture.sql',
  'supabase/migrations/20260930013417_enforce_profile_terms_admission.sql',
  'supabase/tests/account_lifecycle.fixture.sql',
  'supabase/migrations/20260930063923_recoverable_account_deletion.sql',
  'supabase/tests/newsletter.fixture.sql',
  'supabase/migrations/20260930125527_newsletter_consent_mail_outbox.sql',
  'supabase/migrations/20261001140307_mail_transactional_postal_split.sql',
];

test('independent restore rollback with integrated email triggers', { timeout: 180000 }, async t => {
  const cluster = await disposableCluster(t, process.env.PG_BIN), db = await cluster.connect();
  for (const path of paths) await db.query(await readFile(new URL(`../${path}`, import.meta.url), 'utf8'));
  const run = async sql => {
    const connection = await cluster.connect();
    try { return await connection.query(sql); } finally { await connection.close(); }
  };
  const restore = extra => `begin;${context(extra)}select public.restore_account();commit;`;
  const reset = async enabled => {
    await db.query(`truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,
      private.mail_suppression,private.account_lifecycle;
      truncate auth.users cascade;
      update private.mail_settings set enabled=false,rollout_at=now()-interval '1 hour';
      insert into auth.users(id,email,email_confirmed_at,created_at)
        values('${user}','sentinel@example.test',now(),now()-interval '1 day');
      insert into auth.sessions(id,user_id,aal,created_at)
        values('${sid}','${user}','aal1',now()-interval '1 hour');`);
    await run(`begin;${context({ session_id: sid })}select public.request_account_deletion();commit;`);
    await db.query(`insert into auth.sessions(id,user_id,aal,created_at)
      values('${freshSid}','${user}','aal1',clock_timestamp());
      update private.mail_settings set enabled=${enabled};`);
  };
  // Deliberately seed unsuppressed sentinel rows after deletion: a successful
  // restore must change these, while a rejected restore must undo those writes.
  const seed = () => db.query(`insert into private.newsletter_consent
    (id,user_id,email,version,consent_text,source,confirm_hash)
    values('${uid(31)}','${user}','sentinel@example.test','newsletter-v1','Synthetic rollback sentinel','settings','${'a'.repeat(64)}');
    insert into private.mail_outbox(id,event_key,kind,user_id,email,consent_id)
    values('${uid(32)}','rollback-sentinel','newsletter_confirm','${user}','sentinel@example.test','${uid(31)}');`);
  const snapshot = () => db.query(`select jsonb_build_object(
    'lifecycle',(select to_jsonb(l) from private.account_lifecycle l where user_id='${user}'),
    'consent',(select jsonb_agg(to_jsonb(c) order by id) from private.newsletter_consent c),
    'outbox',(select jsonb_agg(to_jsonb(o) order by id) from private.mail_outbox o),
    'suppression',(select jsonb_agg(to_jsonb(s) order by email) from private.mail_suppression s));`);

  for (const enabled of [false, true]) for (const scenario of ['deadline', 'freshness', 'mfa', 'deleted_session', 'null_created_at', 'success']) {
    await t.test(`mail enabled=${enabled}: ${scenario} checks lifecycle and suppression atomicity`, async () => {
      await reset(enabled);
      if (scenario === 'deadline') await db.query(`update private.account_lifecycle set
        deletion_requested_at=statement_timestamp()-interval '720 hours'+interval '1 second',
        restore_until=statement_timestamp()+interval '1 second';`);
      if (scenario === 'freshness') await db.query(`update private.account_lifecycle set
        deletion_requested_at=now()-interval '1 day',restore_until=now()+interval '29 days';
        update auth.sessions set created_at=clock_timestamp()-interval '10 minutes'+interval '1 second' where id='${freshSid}';`);
      if (scenario === 'mfa') await db.query(`update public.profiles set roles='Owner' where id='${user}';
        insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${user}','totp','verified');
        update auth.sessions set aal='aal2',factor_id='${factor}' where id='${freshSid}';`);
      await seed();
      const before = await snapshot(), holder = await cluster.connect(), waiter = await cluster.connect();
      try {
        await holder.query('begin;select private.mail_lock();');
        const outcome = waiter.query(restore(scenario === 'mfa' ? { aal: 'aal2' } : {}))
          .then(value => ({ value }), error => ({ error }));
        await blocked(db, waiter, holder);
        if (['deadline', 'freshness'].includes(scenario)) await db.query('select pg_sleep(1.1);');
        if (scenario === 'mfa') await db.query(`update auth.mfa_factors set status='unverified' where id='${factor}';`);
        if (scenario === 'deleted_session') await db.query(`delete from auth.sessions where id='${freshSid}';`);
        if (scenario === 'null_created_at') await db.query(`update auth.sessions set created_at=null where id='${freshSid}';`);
        await holder.query('commit;');
        const result = await outcome;
        if (scenario === 'success') {
          assert.equal(result.error, undefined);
          assert.equal(JSON.parse(result.value).account_state, 'legacy_active');
          const after = JSON.parse(await snapshot());
          assert.notEqual(after.lifecycle.restored_at, null);
          assert.equal(after.lifecycle.marketing_suppressed, true);
          assert.equal(after.consent[0].suppression_reason, 'account_deletion');
          assert.notEqual(after.consent[0].unsubscribed_at, null);
          assert.equal(after.consent[0].confirm_hash, null);
          assert.equal(after.outbox[0].state, 'suppressed');
          assert.equal(after.outbox[0].last_error, 'account_deletion');
        } else {
          assert.equal(await snapshot(), before, 'Rejected restore must roll back all lifecycle/consent/outbox/suppression writes');
          const reason = { deadline: 'restore_expired', freshness: 'fresh_session_required',
            mfa: 'account_restricted', deleted_session: 'session_invalid', null_created_at: 'session_invalid' }[scenario];
          assert.equal(result.error?.code, reason === 'session_invalid' ? 'PT401' : 'PT403');
          assert.match(result.error.message, new RegExp(reason));
        }
      } finally { await holder.close(); await waiter.close(); }
    });
  }

  for (const scenario of ['null_session_claim', 'null_created_at_before', 'already_expired']) {
    await t.test(`${scenario}: canonical error and unchanged lifecycle/email rows`, async () => {
      await reset(false);
      if (scenario === 'null_created_at_before') await db.query(`update auth.sessions set created_at=null where id='${freshSid}';`);
      if (scenario === 'already_expired') await db.query(`update private.account_lifecycle set
        deletion_requested_at=now()-interval '721 hours',restore_until=now()-interval '1 hour';`);
      await seed();
      const before = await snapshot();
      const result = await run(restore(scenario === 'null_session_claim' ? { session_id: null } : {}))
        .then(value => ({ value }), error => ({ error }));
      assert.equal(await snapshot(), before, 'Even an unexpected error must leave all rows unchanged');
      t.diagnostic(JSON.stringify({ scenario, code: result.error?.code, message: result.error?.message }));
      const expected = {
        null_session_claim: ['PT401', /session_invalid/],
        null_created_at_before: ['PT403', /fresh_session_required/],
        already_expired: ['PT403', /restore_expired/],
      }[scenario];
      assert.equal(result.error?.code, expected[0]);
      assert.match(result.error.message, expected[1]);
    });
  }
});
