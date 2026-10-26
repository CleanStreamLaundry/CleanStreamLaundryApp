# Campaign Operations

Updated: 2026-10-26. Working record, not proof that planned features exist.

## Current Checkpoint

**October 26 Kisi development (separate from store preparation):** Owner requested
`kisi_unlock_feature` and sandbox work while hardware is pending, then confirmed
phone-to-reader tap only, with **no in-app unlock button**. The branch was created
from the existing `CortinaQR` checkout without discarding dirty/untracked work.
Initial setup/implementation and scoped verification are complete: server-side
inventory transport and a loopback-only synthetic API simulator;26 tests pass,
eight-scenario demo passes, and strict TypeScript checking passes. Hosted transport
is read-only. No real door, setting, key, dependency, database, or deployment changed.
Read-only dashboard inventory: organization15601, Madison place38748, Entrance
Door77048 offline/unassigned. SDK partner ID, provisioning/access policy and real
hardware acceptance remain open. Separate store-preparation changes disable the
customer placeholder in the working checkout; those pre-existing app changes
are outside the Kisi commit. Owned
additions: `_shared/kisi.ts`, `scripts/kisi/`, `KISI_SETUP.md`; narrow npm script and
operations edits only. See [Kisi setup and receipt](../KISI_SETUP.md).

Kisi's local transport/sandbox batch is verified. Phone-to-reader SDK integration
requires the partner ID/testing protocol, authorized per-user provisioning and
access policy, and the pending hardware for physical acceptance. No in-app unlock
button will be added. See [next Kisi batch](../KISI_SETUP.md#next-batch-and-prerequisites).

**Approved security containment deployed:** `delete-maintenance` now returns a fixed 403 for every non-OPTIONS request, without credentials, body parsing, clients, or database effects. User explicitly approved this endpoint-only production change; Backend/composer/independent QA each passed 19 safety tests. Chrome deployment and reloaded source were verified; an unauthenticated GET at 2026-09-30 00:22:18 UTC returned the expected JSON and `Cache-Control: no-store`. No record ID/body was sent, records changed, or settings toggled. Runtime SHA-256: `2895ac547629952bed01a455e32257d27d021b34faff8e92ee5d15bdae8f713b` (LF-normalized editor source). Keep denial in place until authorized replacement is reviewed; never restore the vulnerable handler as rollback. Broader maintenance access and the separately requested profile guard remain open.

**Local delivery is underway, not production-ready. The latest broad VM checkpoint accounts for 2,171 unique passes across 128 compatible files; subsequent overlapping scoped gates are recorded below, not added to that total. Recovery backend/client/presentation and corrected MFA transport/screens now independently pass. One final full Flutter analysis covers 322 Dart files: 0 errors, 0 warnings, 104 unchanged existing infos (infos still give a nonzero analyzer exit). Website lint remains 16 errors/6 warnings. Firebase projects are registered, but SDK/consent integration and device delivery remain open. No new production migration, app deployment, key retirement, billing activation or email send occurred.**

**Usage checkpoint:** user reported excessive usage and a required reset. Routine recovery presentation used medium; auth/backend/complex QA used high, without automatic extra-high inheritance. All workers are now closed after verified handoffs. Composer reviews evidence instead of routinely running a third copy. Detailed history is linked rather than repeated here; no safety or production approval gate is waived.

| Gate | Status | Evidence needed |
| --- | --- | --- |
| Documentation | Passed 2026-09-29 | Composer minimal-change review; independent Backend and QA review, corrections verified |
| Baseline/contracts | Local test repairs and payment guard fix passed; backend and verification gaps remain | Existing analyzer triage, TS-aware lint, route/DI checks, correct project access, local/deployed reconciliation, reproducible paired commits |
| Feature waves | Scoped theme, auth, refresh and payment patches integrated locally; remaining work assigned below | Independent verification per patch; hosted web OAuth, wallet locking and full campaign contracts remain open |
| Production release | Not passed | Release evidence, legal/business decisions, rollback rehearsal, explicit approval |
| Legacy-key retirement | Not started | Consumer inventory, replacement verification, monitoring, explicit approval |

Gate evidence: six read-only lane preflights informed the references; Backend corrected the client dollars/cents boundary and current Stripe refund-status gap, then passed. QA corrected command reproducibility, historical evidence labels, and owner-preflight effects, then passed. Composer verified requirement coverage, scoped doc edits, local links, and whitespace. Gundex's useful orientation/verification/data-protection practices were adapted without its product assumptions, machine-specific rules, or full-file response requirements.

Next delivery: connect accepted MFA/terms/recovery components to protected startup/routes and replace the legacy deletion caller, paired with remaining backend admission coverage. Preserve Home/Wallet presentation during soft revalidation without allowing unconfirmed mutations. Then continue the campaign priorities, including refunds, consent/email, Firebase/release controls and hardening. Review existing mixed dirty work into owned paired commits before release. Firebase support-floor approval, retention/balance treatment and external release access remain separate dependencies.

## Workspace and Evidence

- App: `CleanStreamLaundryApp`, branch `CortinaQR`, starting HEAD `567fdc4`, with pre-existing dirty/untracked Cortina, availability, admin/backend, platform, test, and priority-note work.
- Active web: `CleanStreamWeb-CortinaQR`, branch `CortinaQR`, starting HEAD `2e64f93`, with pre-existing admin, package, route, Vite, and script changes. `CleanStreamWeb` is the separate `main` worktree; do not edit it for this campaign.
- Shared docs live in the app repository. Resolve actual sibling checkouts before isolated-worktree tasks; record paths in each assignment rather than assuming directory names.
- Prior task reports are context, not current validation: availability intentionally avoids a five-second timer; unknown availability is not zero; admin changes are local; sandbox success does not prove physical/production vending.
- Initial Supabase connector discovery exposed only Gundex. Clean Stream `dnuuhupoxjtwqzaqylvb` remains unavailable through that connector; subsequent read-only inspection uses the approved Chrome session. Verified catalog/function/Auth observations are recorded below, not inferred from connector access.
- Firebase connector inspection reported no authenticated user, selected project, or workspace config; those settings remain untouched. Using the user's explicitly authorized Clean Stream Chrome session, created `clean-stream-dev` and `clean-stream-production` and verified Spark ($0/month) for each. Gundex's Firebase/projects/connections were not changed. See [Firebase](firebase.md) for current setup and remaining integration boundaries.

## Ownership

| Lane | Responsibility |
| --- | --- |
| Composer | Integration, sequencing, minimal-diff review, startup/router/DI coordination, manifests/lockfiles, approvals |
| Feature 1 | Branding/splash/Google branding, themes, public website/accessibility, email presentation |
| Feature 2 | Auth/MFA, terms, newsletter consent, deletion/restoration, settings |
| Feature 3 | Home/wallet, Realtime replacement, app/web payments, customer refunds |
| Feature 4 | Firebase/version controls, notifications, admin/reporting, Owner refund UI |
| Backend | Schema/RLS/Storage/functions, authorization, keys, money, lifecycle jobs, email delivery |
| QA | Independent regression/security/accessibility/device/payment/release verification |

Documentation preflight uses read-only subagents and one composer writer. Feature implementation uses isolated worktrees from a reviewed baseline, never unreviewed dirty snapshots. Dispatch specifies owned files, existing code to reuse, smallest diff, dependencies, tests, and prohibited effects. One writer per file; backend contracts precede clients.

Handoff: changed paths; preserved/changed behavior; reuse/removal/additions; justification for abstractions/dependencies; commands/results; unrun checks; risks; doc updates. QA inspects independently. Net lines are evidence, not a reason to omit security or tests.

## Order and Checkpoints

[Priorities](../APP_FIX_PRIORITIES.md) defines scope. Order: documentation -> baseline/safeguards -> branding and identity -> lifecycle/email -> loading/Realtime -> payments/refunds -> Firebase/version controls -> website/admin -> release. Independent visuals can overlap safeguards after the baseline gate; dependencies outrank easy-first ordering.

Pause after each gate/wave, significant validation failures, and before release/key retirement. Record evidence and next allowed work here. Update AGENTS only with durable lessons; remove obsolete/repeated guidance.

## Command Effects

Run in the correct repository. Inspect scripts and `--help` before first use. Do not install/upgrade tools merely for documentation validation.

| Command | Purpose / boundary |
| --- | --- |
| `git status --short`, `git diff --check` | Local status and whitespace checks |
| `flutter --version`, `flutter test test/<area>`, `flutter analyze` | Flutter inspection/validation; may write tool caches |
| `flutter pub outdated` | Review, not upgrade |
| `npm test -- <test-file>`, `npm run test:coverage` (web) | Tests; inspect exclusions before trusting totals |
| `npm run typecheck` (web) | Whole-site strict types, including tests; emits no files |
| `npm run typecheck:admin`, `npm run typecheck:admin:edge` (web) | Additional scoped checks; Edge source requires the sibling app checkout |
| `npm run test:admin:db`, `npm run test:admin:edge` (web) | Local harnesses; inspect sibling-app path assumptions |
| `npm run lint`, `npm run build` (web) | Lint/bundle; Vite alone does not prove type safety |
| `npm audit`, relevant Supabase advisors | Review; no automatic fixes or unverified remote targets |
| `npm run supabase:update-functions` (app) | **Overwrites local functions from remote**, not discovery |
| `npm run admin:owner` (web) | **Privileged remote preflight; `--apply` enables mutations.** Neither is permitted during documentation discovery |

App CI now pins Flutter 3.38.10 for the lockfile's Flutter >=3.38/Dart >=3.10 requirements; web CI uses Node 24. Hosted execution remains unverified. Web tests still need actual routing/DI validation beyond mocks. Record command, checkout/revision, environment, result, skips, and gaps for every batch.

## Current Delivery Evidence

Detailed commands, earlier failures and integration history are preserved in [verification evidence](verification-20260929.md). Do not reread the full history for an unrelated assignment or treat an earlier pending state as current.

| Area | Current local status / remaining gate |
| --- | --- |
| App verification | Accumulated 2,171 unique VM passes across 128 compatible files; overlapping later scoped checks are recorded separately. Changed terms/maintenance Chrome 291 and unchanged router 154 retained. No full final release run. |
| Identity and lifecycle | Recovery: 345 client VM, 41 reported PostgreSQL, 62 Edge, 26 presentation cases. MFA: 70 transport VM, 5 real Chrome, 4 neighbors, 85 feature cases; the browser isolation P1 is closed locally. No automatic consent/restoration, purge or route activation. Full backend coverage and verified lost-factor recovery remain open. |
| UX and branding | Theme startup, Google assets, responsive app controls, Home/Wallet retention and quiet refresh, public navigation and checkout styling accepted locally. Native icon/splash generation, hosted OAuth, complete accessibility/device review remain open. |
| Payments and freshness | Wallet serialization, bounded payment status checks, inert legacy payment route and source Realtime removal accepted locally. Voluntary top-up refunds, provider/callback hardening, physical vending and coordinated production migration remain open. |
| Backend security | Profile/location authority and canonical maintenance with paired client accepted locally. Only approved delete-maintenance deny-all containment is deployed. Public Storage privacy, old admin APIs and full lifecycle/financial coverage remain open. |
| Website | Runtime-security lock candidate accepted; active installation still awaits coordinated tooling work. Last candidate full run 539/35, strict types accepted; lint 16 errors/6 warnings remains. Live public legal/support routes observed; not proof of every link, final policies or payment behavior. |
| Firebase and release | Two Spark projects, separate Analytics properties, Android/iOS registrations complete. SDK/consent/configuration/device delivery and iOS support-floor approval remain. Native signing/builds, policy/store checks and rollout are not accepted. |

Accepted website runtime lock SHA-256: `ed902c76179afeb6cbf3d195d5ec4c22e0b1c5b8855a615d2c10528acc3acbc1`; manifest unchanged at `241caa22239ae74979201501073b3e15006c8504f5a9117db1237f54fc301664`. Do not attribute candidate results to the old active website installation. Existing lint/analyzer debt remains; no suppression is authorized.

## Assignment Checkpoint

No active workers. The accepted feature/backend/QA batches are integrated locally. Next assignments must name verified isolated writable roots and disjoint owned files before dispatch. Composer owns shared routing/startup/DI integration; backend owns remaining API admission/financial exceptions; QA independently checks each paired change.

Recovery presentation's medium-effort worker wrote its two owned files directly instead of isolating. The exact scope and independent acceptance are recorded below; no unrelated files were touched or reverted. Future dispatch requires composer-verified roots, not an assumed setup. Server reason, not device clock, controls its expired presentation.

Current review artifacts:
- Accepted small gates: `/private/tmp/cleanstream-qa-maintenance-appbar-provider-20260930/result.json` (108 VM/107 Chrome maintenance, app-bar 13 per SDK, provider 50+59).
- Current integrated gate: `/private/tmp/cleanstream-integrated-independent-qa-20260930/HANDOFF.md` and `combined-receipt.json`; complete VM coverage and retained Chrome/backend receipts, exact owned inputs verified.
- MFA final acceptance: `/private/tmp/cleanstream-mfa-web-independent-qa-20260930/HANDOFF.md`; 70 VM, 5 real Chrome, 4 neighbors, 85 feature cases and full analysis. Temporary GoTrue verification was removed, not patched around; captured-bearer HTTP plus guarded SDK adoption closes the earlier browser finding.
- Recovery acceptance: `/private/tmp/cleanstream-lifecycle-independent-qa-20260930/HANDOFF.md` (345 VM, 41 PostgreSQL, 62 Edge), [wire contract](account-recovery.md), and `/private/tmp/cleanstream-recovery-presentation-independent-qa-20260930/HANDOFF.md` (26 widgets, clean scoped analysis).
- Earlier exact artifacts and hashes: [September 30 archive](verification-20260930.md). These temporary artifact paths are evidence pointers, not runtime dependencies.
Public policy must remain readable before sign-in. Do not replace it with a verified-user status call. Consent is never automatic; review-only copy does not approve new refund/deletion promises. The local narrow bootstrap is independently accepted but requires coordinated backend deployment; client admission is not active. Eligible users may request support before accepting loyalty terms, but this does not waive current-session, restriction or applicable MFA checks.

Current Home/wallet reads have a 20-second local bound and a 30-second stale-refresh gate; availability has its own 24-second timeout, and storage initialization is outside those bounds. Independently accepted V3 lazily retains only Home/Wallet; leaving that shell disposes them. Completed success/pending funding invalidates Home through a route-local callback, waits out an older read, then quietly reads authoritative data or defers until visible. No amount is copied or inferred. CI compatibility uses `TickerMode.of`, verified in the actual `3.38.10` SDK git object; newer SDK analysis reports three expected deprecation infos.

The deployed legacy `wakeDevice` handler is a random-success simulator, verified by source inspection only. Current scanner defaults to Cortina; the locally integrated `/paymentPage` notice now stops legacy entry before charge. Older binaries remain a release concern; do not disable wake remotely after a charge or infer past customer harm. Preserve captured-payment reconciliation. Broader authorization, Storage and callback gaps remain in [Supabase](supabase.md) and [Payments](payments.md).

## Blockers and Approvals

- Open decisions/approvals: isolated unchanged payment-source test-copy; production profile-authority guard only; iOS 15 support floor; square icon background treatment; actual Flutter-web hosting destination; paid-balance/unsettled-payment retention before final deletion. None is implied by a general continue request.
- Correct Supabase access is available through Chrome; complete live/local reconciliation before risky backend changes. MCP still exposes only Gundex, which must not be used as a substitute.
- Firebase projects and separate Analytics properties are provisioned on Spark with approved terms; environment-safe app/SDK setup, customer collection consent, and device delivery verification remain. Use free plans; no billing activation. Analytics/FCM/FIAM plus quota-reviewed Remote Config only, not another database. Preserve Gundex and existing connector accounts.
- Approve retention by data class, legal exceptions, and remaining paid-balance treatment before permanent cleanup. Thirty days is a recovery window, not universal financial-record erasure.
- Verify Resend sender ownership/authentication, capacity, suppression, postal/contact details, and test recipients before sends. Do not launch campaigns during setup.
- Provider permissions, callback authentication, physical washer/dryer tests, and production-enable settings remain separate from sandbox success.
- Domain/DNS, signing/APNs, store accounts/reviewer access, legal signoff, and devices are external release dependencies. Unavailable is blocked, not passed.

## Production Procedure

1. Record approved environment, source revision, tested artifacts, consumer inventory, pending payments, migration compatibility, recovery point, and operator.
2. Rehearse additive migrations/backfills on synthetic data and permitted staging. Verify RLS, balances, idempotency, old-client compatibility, and restore. Never reset shared data.
3. Obtain explicit approval for production deployment, destructive work, paid services, and legacy-key retirement. Release compatible backend first; retain old keys until consumers are verified.
4. Monitor browser/function errors, rejected callbacks, failed/unknown vends, pending refunds, delivery, and cleanup. Maintenance must preserve settlement/support.
5. Roll back a compatible artifact or disable the affected feature/machine. Never delete ledger events to undo money. Reconcile provider state before retrying; prefer forward repair for data.

## Release Acceptance

- Auth: password/social, cold/warm deep links, MFA/recovery, stale sessions, terms persistence, cross-account/location denial.
- Lifecycle/email: 30-day boundaries, explicit restore, purge races/retries, stale-token denial, suppression, consent confirmation, welcome deduplication, unsubscribe, provider cleanup.
- Money: duplicate/concurrent requests, 48-hour boundary, bonus/reversed spend, reward unwind, pending/external refunds, provider success plus DB failure, deletion during settlement.
- UX: entry/resume/manual refresh, no cached-content flashes, offline/stale data, account/location races, theme startup, responsive/keyboard/screen-reader/contrast, notification denial/deep links.
- Build/security: Flutter analysis/tests and Android/iOS release builds; web types/lint/tests/build/end-to-end; actual router/DI; dependencies; RLS/Storage/privileged endpoints; no client secrets.
- Public release: direct domain routes, support/legal/deletion links, association JSON without redirects, physical washer/all six dryer options, reporting/time zones, monitoring and rollback.
- Recheck current [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/), [Apple deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/), and [Google deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111). Match privacy labels/Data Safety, permissions, SDK disclosures, reviewer access, and policies to actual behavior. Store approval is not guaranteed.
