# Local Account Recovery Contract

LOCALLY INTEGRATED AND INDEPENDENTLY VERIFIED; NOT APPROVED FOR ACTIVATION.
The local endpoint replaces immediate deletion with a pending request. The legacy
deployed endpoint is unchanged; production deployment is not authorized.
Permanent purge, paid-balance/retention decisions, UI activation, marketing and
refund/settlement exceptions require paired work and separate approval.

## Storage and Authority

- `private.account_lifecycle` stores the existing profile ID, last request/deadline,
  optional restoration timestamp and persistent `marketing_suppressed=true`.
  It is private, RLS enabled, has no client/service-role grants or policies, and
  cannot be deleted through a cascading profile FK. No financial or Auth writes.
- The existing `private.current_account_access()` is replaced in place, preserving
  its session binding, verified email, bans, roles and current TOTP checks. Its new
  internal `lifecycle_identity_allowed` is not exposed or callable by clients.
  Pending state always denies `account_access_allowed()`, even after expiry.
- Request and restore take Auth `FOR SHARE`, then the caller's profile
  `FOR NO KEY UPDATE`, then re-evaluate the canonical authority. The profile lock
  serializes first requests (including absent lifecycle rows), duplicate requests,
  and restores, in the same order as the existing terms/provisioning paths.
- All deadlines are server-generated timestamptz values. Exactly 720 hours is
  used for 30 UTC days, independent of DST or caller timezone. Wire timestamps
  are rendered in UTC. Duplicate pending requests never move either timestamp.
- Restore requires a current valid session owned by the caller, verified email,
  applicable current MFA, and `auth.sessions.created_at > deletion_requested_at`.
  At mutation time the session must be no more than ten minutes old (strictly
  less than ten minutes), non-null and not in the future. Ten minutes is a
  technical fresh-auth window for explicit recovery, not a retention decision.
  A refreshed JWT, `iat`, `updated_at`, or MFA challenge on an old session cannot
  substitute for a newly created session. Ordinary login/status never restores.
- Checks use wall-clock time after lock waits. Restore at/after the deadline is
  denied; the row remains pending indefinitely with no cleanup. A restore retry
  inside the same deadline/freshness limits preserves the first restored time.
- Auth/users/sessions/factors, profile IDs/roles, wallet IDs/links, funds, loads,
  rewards, acceptance/refund timestamps and other financial records are unchanged.
  Pre-request sessions cannot regain canonical access after another session
  restores. Restore never reinstates a revoked role or grants privileges.
- No managed Auth SQL mutation, admin sign-out, purge RPC, worker, scheduler or
  provider action is added. Logical restriction is authoritative only on covered
  APIs; it is not a claim of global session revocation. Global sign-out would not
  close missing API gates and a delayed retry could revoke a successful recovery
  session. Any later supported Auth revocation must be separately scoped and
  post-commit with explicit uncertainty/retry behavior, never destructive SQL.

## Wire

Authenticated caller-bound RPCs take **no arguments**:

| RPC | Result / effect |
| --- | --- |
| `request_account_deletion()` | Commit pending state and return the six-key status |
| `get_account_lifecycle_status()` | Read-only alias of existing admission status |
| `restore_account()` | Explicit fresh-auth restore, returning admission status |

The existing six keys remain `subject_id`, `account_access`, `next_step`, `reason`,
`account_state`, `restore_until`. Active accounts still use `legacy_active`.
Pending adds `account_state=pending_deletion`, a non-null UTC `restore_until`,
`account_access=restricted`, and normally `next_step=blocked` with reason
`explicit_restore_required` or `restore_expired`. Email/TOTP/role/factor checks
retain precedence and can return `verify_email`, `enroll_totp`, `challenge_totp`,
`role_unavailable`, or `unsupported_factor` with pending state/deadline. Auth bans
and account restrictions keep the existing blocked response, without a deadline.
No `restore` next-step enum is invented. Status is not a promise that restore is
authorized; the explicit RPC rechecks everything. Restored admission can still
require terms review, without modifying previous consent.

**Paired client:** `AdmissionStatus.fromJson` now validates canonical pending
combinations and UTC deadlines. Existing ProfileService exposes caller-bound
`requestAccountDeletion()` and `restoreAccount()` with identity/expiry completion
guards and exact subject/state acknowledgements; `getAdmissionStatus()` provides
the status check after an unknown outcome. Independent QA passes 345 client and
neighbor cases with clean scoped analysis. Recovery presentation passes 26 independent widget cases;
the old deletion UI and router are not switched over. No mutation retries, automatic
restoration or logout are added by these adapters.

SQL errors: `PT401 session_invalid`, `PT403 account_restricted` or restore-specific
`fresh_session_required` / `restore_expired` / `restore_unavailable`, and sanitized
`PT503` failures. No subject argument, metadata claim, date or client clock is trusted.

`delete-account` retains POST `{ "user_id": "<caller>" }` for compatibility,
validates ownership via `getUser`, then calls the no-argument request RPC using
the exact same bearer with the public anon key. It no longer has a service key,
anonymization or Auth deletion. Success is `{ "success": true, "data": <status> }`.
401/403 are sanitized; uncertain RPC failures return 503
`{ "error": "deletion_outcome_unknown", "retryable": true,
"status_rpc": "get_account_lifecycle_status" }`. Check status before retry;
pending retries preserve the deadline. A lost response is not evidence of rollback.
Success requires an exact six-key canonical pending acknowledgement for the
verified caller, restricted access, a valid UTC deadline, and an allowed pending
next-step/reason combination. Active, unrelated or malformed acknowledgements
return the same unknown-outcome 503. Expired pending and canonical email/MFA/role
prerequisite responses remain valid acknowledgements; the Edge clock does not
decide restoration eligibility. The handler dispatches once and never retries
automatically; `retryable` is guidance for explicit status-led caller recovery.
After explicit restoration a new confirmed request may start a new 30-day period;
do not automatically replay an earlier user intent with a different session.

## Email Suppression

There is no newsletter or outbox in this batch. Request atomically persists
`marketing_suppressed=true`; restore never clears it or recreates consent/welcome
events. A future sender must read committed lifecycle state immediately before
dispatch, honor this suppression plus independent unsubscribe/bounce/complaint
suppression, and require separately approved opt-in before any resubscription.
Future deletion notices must match the current request timestamp and still-pending
state; restore invalidates stale deletion work. No emails/templates/DNS/provider
settings or email framework are created. See the active repository's `docs/email.md`.

## Activation Gaps

Do not deploy this migration/endpoint independently. Source inventory, not a
hosted catalog audit or proof of every effective privilege:

| Surface | Coverage / required paired work |
| --- | --- |
| Profile reads/writes, bootstrap, terms | Existing restrictive policies/RPCs reuse the evaluator and acquire pending denial; ordinary RLS still uses statement snapshots, not cancellation of already-running operations. |
| Maintenance | Local `20260930032327_maintenance_authorization.sql` uses the same authority; not applied by this fixture. Pending support/refund exceptions remain undefined. `delete-maintenance` must remain deny-all. |
| Wallet/ledger/load/redemption reads and wallet balances view | Existing ownership/admin checks lack lifecycle admission; cover RLS and inherited grants without breaking settlement. |
| Wallet creation, `redeem_wallet_for_machine`, `redeem_wallet_for_cortina`, admin wallet adjustments/status/legal cash and complaint RPCs | Integrate the same authority at human mutation boundaries with financial locks and post-wait checks. Existing wallet-locking migration is not lifecycle enforcement. |
| `paymentIntent`, `createCheckoutSession`, `checkPaymentResult`, `verifyPayment`, `paymentIntentStatus`, `cortina-vend` | User funding/vending/status paths and service-role callers need canonical caller-bound gates; keep already-accepted settlement/reversal separate. |
| `admin-portal`, `admin_portal_*`, role helpers, invitations/recovery | Service-role actor arguments/role checks do not supply live caller session/MFA/lifecycle authority. Audit administrative reads and writes. |
| `transactions`, `Refunds`, `request_cortina_loyalty_credit`, `approveRefund`, `denyRefund` | Direct table and RPC paths need paired support/refund eligibility and settlement exceptions; do not indiscriminately block financial completion. |
| `machine-availability`, `ping-device`, `wakeDevice`, Machines/Locations/location membership reads | Public-versus-protected scope and lifecycle checks need explicit coverage, including the simulated `wakeDevice` endpoint's future use. |
| Storage, `changePassword`, `resetToken`, Auth SDK | Signed URLs, direct policies, password/reset entry points, Auth signup/recovery and old clients need a coordinated inventory/test; no Auth-provider claims of revocation here. |
| Stripe/Nayax/Cortina callbacks, reversal/reconciliation, refund notifications | Preserve authenticated provider completion paths and idempotency independently of human MFA/terms; approve explicit pending-account exceptions. |
| Legacy `anonymize_wallet_for_deleted_user` and privileged admin tooling | Historical function remains unchanged (migration revokes public/anon/authenticated execution). No calls from this endpoint; verify effective deployed ACLs and all privileged callers before activation. No permanent cleanup is enabled. |

Also gate on profile authority and existing role legitimacy, production definer
read permissions, gateway/JWT behavior, user-facing deletion/retention wording,
explicit restore UI, and complete API coverage including old clients. An SDK
login success must never be interpreted as lifecycle restoration.

## Local Verification

Independent local gate: 345 client/neighbor VM cases, 41 reported PostgreSQL
passes (40 scenarios plus parent), and all 62 final Edge cases; zero failures.
Scoped client analysis is clean. Evidence and precise boundaries:
`/private/tmp/cleanstream-lifecycle-independent-qa-20260930/HANDOFF.md`.
These are overlapping focused checks, not additions to the campaign full-suite count.

Prerequisites are read-only symlinks to the approved app files: profile authority,
loyalty policy, admission, profile/terms enforcement, their three synthetic fixtures,
and `scripts/test-support/policy-admission-pg.mjs`. No whole workspace or website
financial source was copied. Apply the candidate only after those prerequisites.

Focused SQL: PostgreSQL 17.11 with disposable private Unix socket, no listeners,
40 scenario tests plus the parent test (41 passed). Covers real lock waits,
request/restore ordering, stale/cross-account sessions, bans, current TOTP and
unsupported factors, exact deadline exclusion, session freshness, unchanged
Auth/profile/representative linked financial rows, ACLs and suppression. These
fixtures do not prove hosted JWT signatures, full financial schema compatibility,
or deployed owner privileges. No campaign rerun or production test was performed.

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin node --test scripts/account-lifecycle.test.mjs
DENO_DIR=/tmp/cleanstream-backend-tooling/cache /tmp/cleanstream-backend-tooling/deno-2.9.7/deno test --cached-only --lock=/private/tmp/cleanstream-account-recovery-test.lock --frozen --node-modules-dir=none --allow-env supabase/functions/delete-account
```

Initial Edge verification: 24 tests passed, including real `index.ts` adapter HTTP interception with
no network permission. Actual `deno.json` compiler/test configuration used;
`nodeModulesDir=none` avoids unrelated npm installation. Repository frozen lock
is missing eleven standard-library entries for the already-existing server import.
The temporary test lock copies every repository pin and adds only those eleven
entries. No repository config, dependency or lockfile change. Local package-cache
fetches were needed; no project/provider endpoints were contacted. A frozen run
against the unchanged repository lock remains a pre-existing verification gap.
Formatting and `git diff --check` pass. Default Deno 2.9.7 lint reports four
`no-import-prefix` diagnostics for the repository-style HTTPS imports (including
the new adapter test); no lint config changes or suppression were introduced.

Focused acknowledgement follow-up: 40 changed Edge cases passed, 22 unchanged
cases filtered out, using the same Deno command with
`--filter '/pending acknowledgement|captured bearer|actual adapter/'`.
Coverage includes malformed shapes, exact key membership, wrong subject, active
state, invalid UTC/calendar dates, expired pending, and all canonical pending
prerequisite combinations. Invalid responses dispatch once and return unknown
503, never retry automatically. Only the handler logic, its two nearest test
files and this document changed. Lifecycle migration, SQL fixture and PostgreSQL
runner hashes remain identical; SQL and financial suites were not rerun.

Official references checked: [Supabase sessions](https://supabase.com/docs/guides/auth/sessions)
for `session_id` validation and [RPC](https://supabase.com/docs/reference/javascript/rpc)
for caller-authenticated calls. Read the existing local changelog snapshot after
the markdown endpoint fetch failed; no applicable Auth/RPC breaking change found.
