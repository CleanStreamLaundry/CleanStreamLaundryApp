# Canonical Admin Onboarding

SOURCE READY, runtime UNRUN. Only this sparse lane was written. Prior hosted
preflight and all active repositories remain untouched. No provider, Auth, email,
database or deployment action. No test process/slot held; QA owns execution.

## Exact Scope

- `supabase/functions/admin-portal/backend.ts`: replace only disabled invite/resend wiring; bound the new caller RPC to eight seconds and scope its conflict error. Existing geocoding, credit, caller capture and other RPC paths retained.
- `supabase/functions/admin-portal/index.ts`: lazy server-key/redirect getter needed by the new adapter. Reuses unchanged `selectNamedSupabaseKey`; optional `CLEANSTREAM_ADMIN_SECRET_KEY_NAME`, absent-only legacy fallback, invalid explicit selection disabled. Modern service transport uses apikey only; human RPCs retain original caller bearer.
- New `supabase/functions/admin-portal/onboarding.ts` and `onboarding.test.ts`.
- CLI-created `supabase/migrations/20260930213402_canonical_admin_onboarding.sql` and new `scripts/admin-onboarding.test.mjs`.
- `qa.import-map.json` is lane-only QA wiring to read actual active dependencies and route the active handler to this candidate backend. Do not deploy/copy it to the active app.

Backend/index baseline source was taken from the current integrated active files;
final targeted diffs show only onboarding changes and no geocoding churn. Apply
these hunks against any subsequently formatted active file, not an older full copy.
No shared helper/SDK/lock, outbox, mail renderer, UI, lifecycle/evaluator, first
Owner bootstrap, global wallet authority or unrelated SQL change.

Frozen SHA256, in scope order (backend, index, helper, Deno test, migration,
PG runner, QA import map):

```text
5b03aa5d5e3dbf79a3ba555ec7f4122179bd4bd1d6f2ef6fec8140222440630f
8372d764eea792c513a7364cbacb64926869b93b0ad2212dbf2c39d923b4626a
4f4d04ae53bce0b2774be60bfe23a7c9fccfe11184921099a51a4ad374aa1b37
a255e8562e674a89024e607b107add0a7eab979e8cb8a04746c403f0bdae50a2
64a0a4377e99a425a01b0a4a26e21cb30911cc1c6fc36277ac0a9a01918661a9
50575ae86c37e7e4a410fddf82ab5ce4fe755cc015ab322fb6598b71941cec35
a36f1758380258ce09dbc727579d649bea89d49b4370db1474a8eb573f944e81
```

## Contract

Existing Team API is unchanged: `invite(email, locationIds)` returns `{}` (existing
optional-warning shape); `resend(userId, locationId)` resolves on success. No
frontend change is required. Existing `/admin/accept-invite` handles both invite
and recovery callbacks; password/email alone still cannot pass canonical staff MFA.

One new caller-bound RPC `admin_team_onboarding(text,text,bigint[],uuid,bigint)`
implements prepare (`invite`/`resend`), `authorize`, and `complete`. Only current
Owner with eligible session/bound AAL2 can use it, only for the Owner's assigned
locations. No customer Home/terms requirement is invented for staff. Owner/self,
pending-deletion, banned, deleted, anonymous and ambiguous targets fail closed.
Resend requires an existing Admin membership and never grants additional access.

Reuse: `private.portal_staff_context`, existing internal
`admin_portal_assign_member`, protected membership/role writes,
`admin_invitations`, and immutable `admin_audit_events`. No new table, queue,
approval framework or email system. An immutable request row is a caller-bound
ten-minute technical receipt; its ID travels as a decimal string. A narrow unique
audit index and request-row lock fence completion/delivery replay. Exact target
Auth email/UUID and current Owner/location/lifecycle are checked after waits,
including assignment/audit triggers. Completed receipts cannot restore removed
membership. Existing actor-taking helpers remain revoked; bootstrap unchanged.

Supabase Auth sends exactly one invite for new/unconfirmed accounts or one recovery
email for existing confirmed accounts. No metadata role, guessed identity, user
listing, generated-link mailer, automatic retry, deletion compensation, password
setting or factor removal. The captured caller reauthorizes immediately before
dispatch; assignment revalidates after Auth returns. If email succeeds but SQL
fails, an ordinary account may exist without staff access. Error503 explicitly
requires team-list recheck/support; no successful grant or safe resend is claimed.

Only service_role can call `admin_team_invitation_delivered(bigint,uuid)` after
the matching completion. It records Auth send acknowledgement in existing
invitation/audit metadata; it cannot grant authority. It does not claim inbox
delivery. Direct browser calls cannot forge this acknowledgement.

## Verification Queue

Source inspection only: expected43 new Deno cases and41 PostgreSQL child cases
+parent=42. Zero completed runtime checks for this batch. Tests cover real-SDK
fake HTTP, captured caller/named keys, scope/receipt substitution, no retry/delete
on unknown outcomes, canonical MFA/lifecycle, immutable delivery, new/existing
identity, post-wait rollback and concurrent completion. The PG fixture reuses
actual current profile/membership/admission/lifecycle/admin/MFA SQL, including
the catalog-faithful membership FKs; it does not replace canonical functions with
test authorization stubs. Frozen source review/QA must precede integration.

From this sparse root, one command at a time in QA's assigned slot:

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --cached-only --no-config --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --frozen --import-map=qa.import-map.json --v8-flags=--max-old-space-size=768 --allow-env supabase/functions/admin-portal/onboarding.test.ts /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/functions/admin-portal/backend.test.ts /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/functions/admin-portal/geocoding.test.ts
```

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin ADMIN_ONBOARDING_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/admin-onboarding.test.mjs
```

Existing disposable helper owns private socket/authorized bottle relocation and
teardown. Do not install, fetch missing pins, copy caches or start global servers.
The runner defaults to its own app root after integration; the environment root
above is needed only for this sparse lane. Report actual case counts, typecheck,
exit and PG stop/temp removal. No older unrelated suites requested.

## Release Prerequisites

Install reviewed profile and membership guards, terms/admission/lifecycle,
admin operations/extensions and canonical staff authorization before this additive
migration. Preserve the integrated customer-MFA recovery extension when present;
the tests include it. Do not replay old finance/backfill migrations from the
synthetic fixture as a deployment plan. Current hosted prerequisites remain a
separate composer-controlled activation gate.

Deploy the paired helper/backend/index only after SQL QA and prerequisite review.
Configure the named server secret, caller publishable key and trusted HTTPS
`ADMIN_PORTAL_ORIGIN`; Auth redirect allowlist/templates must permit the existing
`/admin/accept-invite` route. Auth SMTP/rate limits and named-key gateway behavior
need an explicitly authorized development smoke. No live mail is authorized here;
the saved lifecycle-mail Resend API key does not itself configure Auth SMTP.

No new business-policy decision is assumed: existing Owner-only, assigned-location
Admin onboarding is preserved. First Owner provisioning/recovery is excluded.
Hosted mail configuration and actual delivery remain unverified. Pausing invite/
resend later must not revoke existing staff or remove audit evidence. A dispatched
email/Auth creation cannot be rolled back by HTTP timeout or by restoring code.

Official source checks: [Auth invite API](https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail),
[Auth recovery email API](https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail),
and [Auth invite implementation](https://github.com/supabase/auth/blob/master/internal/api/invite.go).
The latter distinguishes existing confirmed users (invite rejected) from
unconfirmed users; the adapter chooses recovery for confirmed identities. Current
source inspection is not proof of the hosted Auth version or SMTP configuration.
