# Owner-Supported Customer MFA Recovery

Approved policy: current Owner only, ordinary User target, externally verified
identity and recorded support case, mandatory fresh-session TOTP reenrollment.
Admin, self-recovery and privileged targets are rejected. Case text/email/password
alone are not proof: the Owner attests that external verification of this exact
customer UUID already occurred. No proof documents or credentials are logged.
The four backend/test artifacts are integrated byte-identically into the active
source after composer review and independent QA (48 PostgreSQL, 43 Deno plus
typecheck). This is source integration, not deployment or activation. Composer's
read-only hosted inventory reports 20 functions and no customer-mfa-recovery
function installed; hosted SQL prerequisites are being inspected separately.

## Owned Contract

- `supabase/migrations/20260930202731_customer_mfa_recovery.sql`: one private
  per-customer fence, narrow canonical evaluator replacement, Owner-only
  `customer_mfa_recovery_request(text,uuid,text,boolean,uuid)`, and role guard
  while captured factors remain. SQL never mutates Auth-owned rows.
- `supabase/functions/customer-mfa-recovery/{index.ts,index.test.ts}`: dedicated
  endpoint using unchanged key/captured-bearer helpers and locked SDK2.99.3.
- `scripts/customer-mfa-recovery.test.mjs`: real PG, existing synthetic
  admission/admin fixture chain and disposable private-socket harness.

Reuses `private.portal_staff_context()`, never user_metadata. Owner requires
current bound AAL2 and session created strictly within ten minutes; refresh alone
does not suffice. Rechecks after locks/audit waits and before each removal.
Auth -> profile locks serialize lifecycle/role changes. Target must remain active,
verified, nonanonymous, unbanned, undeleted User. Pending deletion/unsupported
factor types fail closed. No location/global-wallet policy changes.

Fence and immutable verified-case audit commit before any Auth deletion. Capture
only original factor IDs; same-case replay never changes cutoff/snapshot. Each
removal authorization is audited. Unknown external outcome returns sanitized503,
keeps the fence, and is never automatically retried. Deliberate same-case retry
rechecks SQL existence; newly enrolled factors are never removed. Different case
while old factors remain conflicts. No human approval framework or manual SQL
Auth deletion. Already-dispatched Auth cannot be undone by a later actor change.
Target promotion is blocked while any captured factor remains; after those IDs
disappear, stale requests cannot remove replacements.

Canonical admission rejects pre-cutoff sessions permanently, blocks while any
captured factor remains, then requires a factor created after cutoff plus fresh
session and current bound AAL2. Uses existing enroll_totp/challenge_totp/blocked/
review_terms and lifecycle outcomes; admission wire shape unchanged. The retained
row keeps MFA mandatory if the replacement is later removed. Roles, terms,
deletion/financial records and settlement/refund implementations are preserved.
No completion marker falsely grants Home. Privileged/last-Owner recovery remains
external support, not this customer action.

## Frontend API

POST `/functions/v1/customer-mfa-recovery`, original Owner bearer and app apikey:

```json
{"action":"inspect","target_user_id":"customer-uuid"}
```

```json
{"action":"recover","target_user_id":"customer-uuid","support_case":"CASE-123","identity_verified":true}
```

Unknown authority fields rejected; no email lookup or factor selection. Success
returns only target_user_id, recovery_id, support_case, state,
reenrollment_required. State: not_started, removal_pending or
reenrollment_required. Last state means old-factor removal finished, NOT completed
customer authentication. Customer signs in again and uses existing enroll/
challenge/verify followed by admission refresh. No frontend edits in this lane.

Owner UI must collect the exact customer UUID, non-sensitive support case and
explicit confirmation of completed external verification. Hide the action from
Admin/customer views, but rely on the server for authorization. Bind submission
and its result to the initiating signed-in actor, target and case; discard stale
responses after account/target changes. Reset verification confirmation when the
target or case changes. Do not infer eligibility from the displayed role or JWT
user_metadata. Fresh-sign-in refusal requires new sign-in plus current MFA, not
token refresh or automatic replay. Preserve the case for an explicit retry after
an unknown outcome. Do not navigate the recovered customer straight to Home or
mark MFA complete from the Owner endpoint response.

400 invalid request; 401 invalid session; 403 recovery_forbidden or
fresh_sign_in_required; 409 recovery_conflict; 503 recovery_unavailable. On503,
inspect then deliberately retry SAME case; do not silently start another case.
Case reference: non-sensitive, trimmed, 1-120 characters, no controls. Edge never
returns factor IDs, raw Auth diagnostics, client/provider secrets or proof data.

## Release Prerequisites

Existing canonical admission/lifecycle/terms and protected profiles, staff context
from `20260930142406_admin_canonical_authorization.sql`, immutable audit from
`20260928151021_admin_operations_extensions.sql`, then ONLY this new migration
and endpoint. No blanket deployment. Evaluator owner retains minimal Auth/session
reads and adds auth.mfa_factors.created_at SELECT; executor must be permitted to
grant that column to postgres. No Auth write or secret-column grants. Fence RLS
enabled with no client/service privileges; new RPC EXECUTE only authenticated.

Optional exact CLEANSTREAM_MFA_RECOVERY_PUBLISHABLE_KEY_NAME and
CLEANSTREAM_MFA_RECOVERY_SECRET_KEY_NAME reuse existing key maps, absent-only
legacy fallback. Invalid explicit name fails503. Modern secret uses apikey only;
caller RPC preserves original bearer. ADMIN_PORTAL_ORIGIN reuses portal CORS.
Frontend Owner confirmation/reauth and actual development Auth/session invalidation
remain coordinated release checks, not synthetic proof.
Rollback Edge first; never drop fence/evaluator with recovery rows, reopening AAL1.

## Gateway Recommendation

The local configuration explicitly retains gateway verification for this
human-JWT-only function. This is not hosted deployment or activation:

```toml
[functions.customer-mfa-recovery]
verify_jwt = true
```

Current [Edge authorization header documentation](https://supabase.com/docs/guides/functions/auth-headers)
says the gateway supports both legacy HS256 and asymmetric user JWTs, and
recommends verification for user-only functions. Send the original Owner user
JWT in Authorization and the named publishable key in apikey. Named keys are not
user identity; compatibility gateway acceptance of key-only requests does not
authorize recovery. The captured-bearer, caller-bound RPC and canonical current
Owner/session/factor checks remain mandatory regardless of gateway setting.

The [signing-key migration guide](https://supabase.com/docs/guides/auth/signing-keys)
still contains a conflicting warning that rotation may require disabling this
flag. Do not assume that older warning describes the development project's
current gateway. Verify named-key plus actual asymmetric JWT transport against
the selected hosted project before activation. A confirmed incompatibility is a
deployment blocker requiring an explicit per-function decision, not permission
to disable verification globally or weaken the existing handler.

Release checks must distinguish gateway401 from handler/RPC rejection. Use the
nonmutating inspect action to establish valid fresh Owner access and denial for
missing/forged/expired bearer, key-only callers, Admin and restricted targets.
Verify no Auth admin request occurs for rejected callers. This does not test
factor deletion or authorize recovery mutations. Do not change webhook, guest
status, callback or other function settings as part of this recommendation.

Supported API/logouts checked against installed SDK and
[official deleteFactor docs](https://supabase.com/docs/reference/javascript/auth-admin-deletefactor).
No account purge, retention policy, key retirement or remote mutations.

## Accepted Verification

Four artifacts independently QA accepted and integrated exact; no reruns needed.
PostgreSQL47 children + parent =48 passed, zero failures/skips, exit0/chunk48d196.
PG17.11 stopped, owned temp5L0X58 removed. Real-SDK fake-HTTP Deno43 passed plus
typecheck, exit0/chunk3f260e; all processes exited. SDK prints the synthetic timeout
diagnostic to stderr in its failure case; response stays sanitized, no retry.
No hosted/Auth mutation. Tests cover owner/target/freshness, post-wait role/factor changes,
audit rollback, exact cutoff, replay/new-factor preservation and unknown outcomes.
Reproduction commands from the repository root, only in an assigned serial slot:

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/customer-mfa-recovery.test.mjs
```

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env supabase/functions/customer-mfa-recovery/index.test.ts
```

Existing helper owns PG17 relocation, stop and temp deletion. No older suites,
installs/cache copy/fetch. These tests do not establish hosted gateway, deployment,
actual customer session revocation, or frontend integration acceptance.
