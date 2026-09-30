# Campaign Operations

Updated: 2026-09-30 UTC. Working record, not proof that planned features exist.

## Current Checkpoint

**Approved security containment deployed:** `delete-maintenance` now returns a fixed 403 for every non-OPTIONS request, without credentials, body parsing, clients, or database effects. User explicitly approved this endpoint-only production change; Backend/composer/independent QA each passed 19 safety tests. Chrome deployment and reloaded source were verified; an unauthenticated GET at 2026-09-30 00:22:18 UTC returned the expected JSON and `Cache-Control: no-store`. No record ID/body was sent, records changed, or settings toggled. Runtime SHA-256: `2895ac547629952bed01a455e32257d27d021b34faff8e92ee5d15bdae8f713b` (LF-normalized editor source). Keep denial in place until authorized replacement is reviewed; never restore the vulnerable handler as rollback. Broader maintenance access and the separately requested profile guard remain open.

**Local delivery is underway, not production-ready. The earlier broad VM checkpoint accounts for 2,171 unique passes across 128 compatible files; subsequent overlapping scoped gates are recorded below, not added. The prior full Flutter analysis covered 322 Dart files: 0 errors, 0 warnings, 104 existing infos, not a final check of the integrated campaign. Latest full website TypeScript passes; lint has 2 errors/1 warning, all in the staff-MFA-owned context file. New production migrations, app deployment, key retirement, billing activation and email sends have not occurred.**

**Usage checkpoint:** user reported excessive usage and a required reset. Routine UI work uses medium; auth/backend/complex QA uses high, without automatic extra-high inheritance. Composer reviews evidence instead of routinely running a third copy. Detailed history is linked rather than repeated here; no safety or production approval gate is waived.

**Restart checkpoint:** the host restarted on September 30 at 11:23:27 EDT. The system panic reports a watchdog timeout; preceding diagnostics show substantial Chrome memory use, and the local preview had a repeating Vite console-forwarding failure. These observations do not establish a sole cause. App/web integrated source survived; `/private/tmp/cleanstream-*` worktrees, runtimes and reports did not. All three formerly active agent handles are unavailable, and preview session 7527 is gone. No agent, preview, native build or simulator has been automatically restarted.

Vite browser-console forwarding is now explicitly disabled in the active website configuration to remove the observed forwarding loop. A bounded Node 24 `resolveConfig` assertion confirmed `server.forwardConsole.enabled === false` without starting a server; scoped configuration lint and documentation whitespace checks also passed. Both agent guides require one bounded check at a time, one local Vitest worker, no file parallelism, and small persistent handoffs under the workspace's `.campaign-work/`. Prior results below are historical evidence, not fresh post-restart runs. Integrated regression tests remain available; missing temporary reports are not current artifacts.

| Gate | Status | Evidence needed |
| --- | --- | --- |
| Documentation | Passed 2026-09-29 | Composer minimal-change review; independent Backend and QA review, corrections verified |
| Baseline/contracts | Local test repairs and payment guard fix passed; backend and verification gaps remain | Existing analyzer triage, TS-aware lint, route/DI checks, correct project access, local/deployed reconciliation, reproducible paired commits |
| Feature waves | Scoped theme, auth, refresh and payment patches integrated locally; interrupted work recorded below | Independent verification per patch; hosted web OAuth and full campaign contracts remain open |
| Production release | Not passed | Release evidence, legal/business decisions, rollback rehearsal, explicit approval |
| Legacy-key retirement | Not started | Consumer inventory, replacement verification, monitoring, explicit approval |

Gate evidence: six read-only lane preflights informed the references; Backend corrected the client dollars/cents boundary and current Stripe refund-status gap, then passed. QA corrected command reproducibility, historical evidence labels, and owner-preflight effects, then passed. Composer verified requirement coverage, scoped doc edits, local links, and whitespace. Gundex's useful orientation/verification/data-protection practices were adapted without its product assumptions, machine-specific rules, or full-file response requirements.

Next delivery: finish restart recovery with bounded checks, then resume the incomplete staff-MFA and immutable-payment work from surviving source and recorded contracts. Do not infer that their vanished candidates were integrated. Complete the pending website independent reviews; retain already accepted work without routinely rerunning every suite. Review existing mixed dirty work into owned paired commits before release. The iOS 15 floor is approved; retention/balance treatment and external release access remain separate dependencies.

## Remaining Work

This is the current completion gap, not a second assignment queue. The full scope remains in [priorities](../APP_FIX_PRIORITIES.md).

| Area | Still required |
| --- | --- |
| Recovery and integration | Restore only needed pinned tools; recover lost candidates; complete pending independent reviews; review focused commits; retain resource safeguards. |
| Branding and themes | Native icon/splash generation and background decision; Google OAuth console branding; complete device, light/dark startup and accessibility checks. |
| Auth and onboarding | Safe staff web MFA session adoption, complete backend admission and verified factor recovery; hosted password/social/deep-link/session checks; coordinated terms/MFA activation. |
| Deletion and restoration | Approve retention and remaining-balance treatment; scheduled 30-day cleanup, retry/restore races, provider cleanup and privilege handling; coordinated deployment. |
| Email and newsletters | Identify Clean Stream Resend account; verify sender/DNS, capacity and contact details; configure delivery jobs/webhooks/suppression; approved test sends and end-to-end welcome/consent/unsubscribe/lifecycle/refund verification. |
| Loading and Realtime | Final slow/offline/account/location/device and history-pagination checks; coordinated client/backend rollout removing old subscriptions without breaking pending payments. |
| Payments and refunds | Immutable funding/device/environment bindings; exact authenticated provider matching; durable closed-app timeout/reconciliation; uncertain refunds/reward unwind; public-endpoint abuse controls and capability cleanup; physical washer/six-dryer tests and safe legacy retirement. |
| Admin and reporting | Authorized invite/resend/first-Owner and credit-email replacements; global-wallet role decision and replacement RPCs; private maintenance attachments; responsive/accessible admin; typed/timezone reporting verification; direct Nayax feed entitlement and Maxim request. |
| Firebase and shutdown | APNs/signing and physical-device messaging/consent/routing checks; published release configuration and store links; independent server shutdown preserving settlement; no paid activation. |
| Website and hosting | DNS/SSL/redirects/direct routes/association files; Flutter-web destination; remaining content/contact/link/pay-page/accessibility checks; checkout fallback visual and independent review. |
| Security and packages | Full authorization/RLS/Storage audit; named per-client/environment/component key migration and approved retirement; 11 web development advisories, compatible Flutter/native updates, geocoding restrictions and headers. |
| Policies and release | Align all policy/store disclosures with actual behavior and approved retention; final CI, signed builds, end-to-end/device checks; monitoring/support/rollback rehearsal, staged rollout and explicit production approval. Store approval is external. |

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
| Website | Runtime-security update installed: earlier 722 tests/42 files passed on Node 26. Current Node 24 full strict types pass; earlier build retained. Runtime audit zero; 11 development advisories and lint 2 errors/1 warning remain. Public newsletter 51-case independent acceptance passed. Final links/policies/payment behavior remain release gates. |
| Firebase and release | SDK/config/consent/release controls and approved iOS 15 native wiring integrated locally; privacy fixes independently accepted. Worker Android debug and unsigned iOS Release builds passed. Signing/APNs/device delivery, policy/store checks and rollout remain. |

Accepted and installed website runtime lock SHA-256: `ed902c76179afeb6cbf3d195d5ec4c22e0b1c5b8855a615d2c10528acc3acbc1`; manifest unchanged at `241caa22239ae74979201501073b3e15006c8504f5a9117db1237f54fc301664`. Installation disabled lifecycle scripts and used the accepted offline registry cache. Existing lint/analyzer debt remains; no suppression is authorized.

## Assignment Checkpoint

No delegated assignment is currently running after the restart. Future assignments require a verified persistent root, reviewed baseline and one writer per file; do not recreate the old pool automatically.

| Owner / status | Surviving scope and next boundary |
| --- | --- |
| Composer | Integrated Firebase, customer refunds/newsletter and Owner reporting/refunds; shared routing/settings and post-trigger restoration checks; active app/web |
| Lifecycle UI, medium; closed | Candidate integrated and client integration accepted; temporary source checkout is gone. |
| Refund backend, high; closed | External-replacement fix independently accepted: 131 Deno passes; unchanged 54 PostgreSQL evidence retained. |
| Email backend / QA, high; interrupted | Admin authorization accepted before restart: 42 PostgreSQL/29 Deno/34 unchanged business cases; tests integrated. Pending list/form/checkout independent review was not delivered. Runtime email remains disabled. |
| Firebase author, high; closed | Privacy fixes and final startup-revocation fix independently accepted locally; native/hosted/device gates remain. |
| Backend author, high; interrupted | Immutable Cortina funding/routing and exact Stripe identity/currency/mode matching: no candidate delivered or integrated; temporary root is gone. Preserve accepted refund/auth artifacts. |
| Staff MFA, high; interrupted | Unaccepted UI/provider and SDK candidates were not integrated; temporary root is gone. Recorded real-SDK regressions expose stale account adoption with both refresh variants. A bounded version-locked SDK patch proposal was authorized for review, not installed. |
| Customer refunds / Owner QA, high; closed | Owner/reporting independently accepted: 18 UI/SDK and 20 PostgreSQL tests; test patch integrated. |
| Wallet layout, medium; closed | Four-file fix integrated; 131 neighbors, two original regressions and three synthetic rendered fixtures pass. Composer inspected 320px/2x and 390px/1x screenshots. |
| Website list/form cleanup, medium; pending QA | Seven-file list/type delta (96 author cases) and four-file form delta (31 author cases) integrated; independent review incomplete. MonthlyIncome remains independently accepted at 26 cases. |
| Newsletter preferences, medium; completed | Candidate integrated; no additional assignment. |
| Independent admission QA, high; closed | Both P1s closed before restart; regression tests integrated. Temporary handoff is gone. |

New local composer evidence: 10 admission-gate tests and 18 load-card dialog tests pass. Final independent paired QA confirms **41/41 integration** and **86/86 focused page/router/gate** passes, with clean scoped analysis. Deletion now invalidates shared admission before recovery navigation; read failures remain closed, retry does not repeat deletion, and A-B-A/route departures discard late effects. Prior unchanged lifecycle 164 and neighbors 158 passes are retained, not added. Frozen test patch SHA-256 `5279599b99034137eea2b88b38e28bf4efd3b274f576250628d6b0a8386d824d` is integrated. This proves local client integration, not deployed authorization.

Restoration's mail-trigger race is closed locally: independent QA passes 125 PostgreSQL runner cases across four suites, including unchanged original regressions, error-contract checks and full rollback probes with mail enabled/disabled. Unchanged 73 supplied +8 independent Deno cases are retained. Tests are integrated; exact lifecycle SHA-256 is `bc960d7af1dc61078e1eb849dd2c4e5127867bdba39283ec9dd7f22821bf3315`. No email activation or cleanup is approved. Refund external-replacement fix is independently accepted: sole, complete, agreeing terminal history is required before release; multiple identities remain reserved for manual review. Independent recheck passes 131 Deno; unchanged 54 PostgreSQL evidence retained with corrected lifecycle hash. External refunds after the provider snapshot still require operational controls/monitoring. Callback guard independently passes 35 supplied +18 new cases; tests integrated, no production change or broader callback clearance.

Firebase privacy fixes are independently accepted locally: 129 focused tests closed the original three findings; a further startup race was corrected using a consent revision, then 16 targeted independent cases passed with the new regression unchanged. A newer explicit revocation cannot be overwritten by startup's saved snapshot. Scoped analysis clean; unchanged 28 PostgreSQL/native evidence retained, not rerun. Final artifact: `/private/tmp/cleanstream-delivery-email/FIREBASE-STARTUP-FIX-RECHECK.md`. No collection or delivery activation is implied.

Composer shared integration check: 113 admission/settings and six native/config tests pass after offline dependency resolution; initial zero-case loopback denial is not counted. Owner refund empty-state preview was inspected at desktop and 390px with synthetic data, no submission. Newsletter token-cleanup and eager Auth-bootstrap fixes independently pass 51 supplied/new cases; tests integrated. Owner/reporting independently passes 18 UI/SDK and 20 PostgreSQL cases; supplied 153 UI/64 PostgreSQL evidence retained. These counts overlap other checkpoints.

Real-router QA's three recovery dead ends and two Wallet overflows are fixed and independently accepted locally. Protected presentation is retained only while admission is unresolved; narrow/large-text Wallet content reflows and scrolls without clipping balances. Composer's combined 50-case run and independent unchanged 36-case router/gate recheck pass; scoped analysis clean. MonthlyIncome invalidates obsolete settled income/hover as well as pending completions; independent Node 24 recheck passes 26 cases/scoped lint. Revenue calculations are unchanged.

Website list/form cleanup reuses existing services and preserves calculations. Keyed forms discard departed completions, block duplicate saves and retain unrelated drafts; author 31 cases, scoped lint/types passed before restart. Independent QA is pending for that batch and the earlier 96-case list batch. Composer moved existing query/formatter implementations unchanged out of `ui.tsx`, and resets invalid location selection before child commit; 99 related cases and full Node 24 types passed. Last whole-site lint is **2 errors/1 warning**, all in `admin/context.tsx`, without suppressions. The former preview on port 5173/session 7527 is stopped. Its inspected synthetic reporting fixtures showed unavailable typed totals and disconnected direct Nayax coverage, not live-data results.

Failed-card-vend status repair independently passes 67 Deno cases: only a matching successful full refund is completed; pending/failed/mismatched results keep the provider binding and require support. Existing bindings are retrieved, not recreated. Artifact: `/private/tmp/cleanstream-delivery-email/FAILED-VEND-STATUS-RECHECK.md`. No new automatic reconciliation engine or production behavior is claimed; unknown unbound provider outcomes and closed-app timeout recovery remain delivery work.

Staff MFA checkpoint: direct verify/setSession and both public refresh variants are unsafe in the current tested identity interleavings. Latest JS 2.117.2's refresh guard can capture a replacement session after acquiring the old refresh token, then overwrite it. The unchanged 40-offset real-SDK/fake-HTTP regression fails at offset 5 with an external token and offset 9 without an argument; 16 neighboring cases pass, not feature acceptance. UI/provider and dependency candidates are frozen separately. Composer authorized one bounded upstream-style, version-locked SDK patch proposal instead of an app-wide session framework. It requires compatibility review, unchanged failing regressions, independent QA and an explicit reproducible installation decision before integration. No SDK upgrade or unsafe MFA activation occurred. Earlier route-cancellation evidence stays unchanged; permitted same-session global refresh after navigation is not this identity defect.

Local public-site browser check: Privacy, Terms, Delete account and Support links navigate; location anchor reaches its section. At 320px, Home and those four pages have no horizontal overflow; home bitmap images loaded and its screenshot was inspected. The deliberate missing route renders the recoverable 404. These are local checks, not hosted SSL/redirect/store verification or policy approval. Existing deletion/privacy copy still needs the coordinated lifecycle/retention update. Checkout without public configuration exposed a real DI/render crash; a checkout-only error boundary now offers support/home without replay or error/query disclosure. Composer passes 39 Node 24 route/payment cases, including the real unconfigured route, full strict types and scoped lint. Independent review assigned. Chrome disconnected before post-fix visual verification; that check remains open, not passed. No payments/provider requests or messages were submitted.

Admin authorization is independently accepted locally: **42 PostgreSQL, 29 Deno and 34 unchanged business cases**. Caller-bound canonical wrappers cover current session/email/MFA/lifecycle/role/location checks and post-wait rollback; actor-taking helpers and direct management writes are closed. Independent tests are integrated. Composer added exactly seven missing checksum entries for the already-pinned SDK 2.99.3; active original-workspace frozen/cached 29 tests and all three production entrypoint checks pass. No SDK upgrade or runtime change. Evidence: `/private/tmp/cleanstream-delivery-email/ADMIN-AUTH-INDEPENDENT-QA.md`; its historical missing-lock note is resolved locally by this integration. Hosted JWT/grants, coordinated deployment and MFA activation remain. Invites/resends, credit email and three global-wallet RPCs remain disabled pending reviewed replacements, not accepted permanent removals. User decision requested: Owner-only global wallet controls versus the old Owner/all-Admins authority; wallets have no location association.

September 30 Nayax access check: DEV portal reports are accessible. Three returned vends matched existing Cortina records by provider ID/RRN (two wallet, one Stripe), not additional Nayax collections. Latest stored availability API result is September 28 HTTP 403; no fresh provider call, direct-card sample or transaction API entitlement verified. [Evidence](../NAYAX_AVAILABILITY_RESEARCH.md#access-and-reporting-check---september-30) and [Maxim draft](../NAYAX_MAXIM_AVAILABILITY_EMAIL.md) updated; nothing sent and no credentials changed.

User approved iOS 15. All four Firebase client configurations were retrieved and verified; local SDK integration is complete, with platform/release gates above. The user provided production iOS and authorized Finder retrieval of the other files. No broad OS grant, Gundex modification or provider activation occurred.

Recovery presentation's medium-effort worker wrote its two owned files directly instead of isolating. The exact scope and independent acceptance are recorded below; no unrelated files were touched or reverted. Future dispatch requires composer-verified roots, not an assumed setup. Server reason, not device clock, controls its expired presentation.

Historical review artifacts (temporary paths below no longer exist after the restart; integrated source/tests and repository records survived):
- Accepted small gates: `/private/tmp/cleanstream-qa-maintenance-appbar-provider-20260930/result.json` (108 VM/107 Chrome maintenance, app-bar 13 per SDK, provider 50+59).
- Current integrated gate: `/private/tmp/cleanstream-integrated-independent-qa-20260930/HANDOFF.md` and `combined-receipt.json`; complete VM coverage and retained Chrome/backend receipts, exact owned inputs verified.
- MFA final acceptance: `/private/tmp/cleanstream-mfa-web-independent-qa-20260930/HANDOFF.md`; 70 VM, 5 real Chrome, 4 neighbors, 85 feature cases and full analysis. Temporary GoTrue verification was removed, not patched around; captured-bearer HTTP plus guarded SDK adoption closes the earlier browser finding.
- Recovery acceptance: `/private/tmp/cleanstream-lifecycle-independent-qa-20260930/HANDOFF.md` (345 VM, 41 PostgreSQL, 62 Edge), [wire contract](account-recovery.md), and `/private/tmp/cleanstream-recovery-presentation-independent-qa-20260930/HANDOFF.md` (26 widgets, clean scoped analysis).
- Earlier exact artifacts and hashes: [September 30 archive](verification-20260930.md). These are historical evidence pointers, not available reports or runtime dependencies.
Public policy must remain readable before sign-in. Do not replace it with a verified-user status call. Consent is never automatic; review-only copy does not approve new refund/deletion promises. The local narrow bootstrap is independently accepted but requires coordinated backend deployment; client admission is not active. Eligible users may request support before accepting loyalty terms, but this does not waive current-session, restriction or applicable MFA checks.

Current Home/wallet reads have a 20-second local bound and a 30-second stale-refresh gate; availability has its own 24-second timeout, and storage initialization is outside those bounds. Independently accepted V3 lazily retains only Home/Wallet; leaving that shell disposes them. Completed success/pending funding invalidates Home through a route-local callback, waits out an older read, then quietly reads authoritative data or defers until visible. No amount is copied or inferred. CI compatibility uses `TickerMode.of`, verified in the actual `3.38.10` SDK git object; newer SDK analysis reports three expected deprecation infos.

The deployed legacy `wakeDevice` handler is a random-success simulator, verified by source inspection only. Current scanner defaults to Cortina; the locally integrated `/paymentPage` notice now stops legacy entry before charge. Older binaries remain a release concern; do not disable wake remotely after a charge or infer past customer harm. Preserve captured-payment reconciliation. Broader authorization, Storage and callback gaps remain in [Supabase](supabase.md) and [Payments](payments.md).

## Blockers and Approvals

- Open decisions/approvals: isolated unchanged payment-source test-copy; production profile-authority guard only; square icon background treatment; actual Flutter-web hosting destination; paid-balance/unsettled-payment retention before final deletion. None is implied by a general continue request. The iOS 15 support floor is explicitly approved.
- Correct Supabase access was verified through Chrome before the restart; reestablish the correct account/session before any remote action. MCP exposed only Gundex, which must not be used as a substitute.
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
