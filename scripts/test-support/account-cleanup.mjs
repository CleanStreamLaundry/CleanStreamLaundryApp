import { readFile } from 'node:fs/promises';

export const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
export const user = uid(1), other = uid(2), session = uid(11), token = uid(21);
export const sqlFiles = [
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
];
export const cleanupPath = 'supabase/migrations/20260930154911_account_cleanup_claims.sql';
export const read = (path) => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
export const seedSQL = `
  insert into auth.users(id,email_confirmed_at) values ('${user}',now()),('${other}',now());
  insert into auth.sessions(id,user_id,aal,created_at) values ('${session}','${user}','aal1',clock_timestamp());
  update public.profiles set balance=4200,reward_tracker=3,refund_attempts=2,
    loyalty_policy_version='existing-policy',loyalty_policy_accepted_at='2026-01-01Z';
  insert into public.wallet_accounts values ('${uid(31)}','${user}',4200,'2026-01-01Z');
  insert into public.wallet_loads values ('${uid(32)}','${uid(31)}','${user}',5000,'2026-01-01Z');
  insert into public.wallet_redemptions values ('${uid(33)}','${uid(31)}','${user}',800,true,'2026-01-02Z');
  insert into public.transactions values ('${uid(34)}','${user}',800,'2026-01-02Z');
  insert into public."Refunds" values ('${uid(35)}','${user}','pending','2026-01-03Z',null);
  insert into private.account_lifecycle(user_id,deletion_requested_at,restore_until)
    select '${user}',t-interval '721 hours',t-interval '1 hour' from (select clock_timestamp() t) x;
  -- As in the existing restore rollback suite, sentinel rows inserted after the
  -- request expose suppression-trigger writes. Claims must leave them untouched;
  -- a successful restore must suppress them even while mail delivery is disabled.
  insert into private.newsletter_consent(id,user_id,email,version,consent_text,source,confirm_hash)
    values ('${uid(41)}','${user}','sentinel@example.test','newsletter-v1','Synthetic sentinel','settings',repeat('a',64));
  insert into private.mail_outbox(id,event_key,kind,user_id,email,consent_id)
    values ('${uid(42)}','cleanup-sentinel','newsletter_confirm','${user}','sentinel@example.test','${uid(41)}');
`;
export const requestTime = `(select deletion_requested_at from private.account_lifecycle where user_id='${user}')`;
export const claimSQL = (id = token, at = requestTime) =>
  `select public.claim_account_cleanup('${user}',${at},'${id}') as result`;
export const retrySQL = (id = token, failure = 'transient_failure', at = requestTime) =>
  `select public.retry_account_cleanup('${user}',${at},'${id}','${failure}') as result`;
export const previewSQL = 'select public.preview_account_cleanup() as result';
export const protectedTables = ['auth.users', 'auth.sessions', 'auth.mfa_factors', 'public.profiles',
  'public.wallet_accounts', 'public.wallet_loads', 'public.wallet_redemptions', 'public.transactions',
  'public."Refunds"', 'private.account_lifecycle', 'private.mail_settings',
  'private.newsletter_consent', 'private.mail_outbox', 'private.mail_suppression', 'private.mail_webhook_event'];
export const authContext = () => `set local request.jwt.claims='${JSON.stringify({
  sub: user, session_id: session, role: 'authenticated', aal: 'aal1', exp: Math.floor(Date.now()/1000)+3600,
})}'; set local request.jwt.claim.sub=''; set local role authenticated;`;
