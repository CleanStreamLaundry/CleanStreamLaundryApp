# App and Website Fix Priorities

User return-to list for the approved minimal-change campaign. This is not an agent instruction file or automatic work queue. Status, owners, evidence, and blockers live in [operations](docs/operations.md), including the [current remaining work](docs/operations.md#remaining-work); implementation rules live in [AGENTS.md](AGENTS.md).

## Current Work Order

### October 19 Nayax implementation and verification

The existing Production Lynx token returns **200** for reader/account requests.
Owner manual Samsung testing reports 1→0 available on INHIBIT/Refresh; provider
70/71 and subsequent backend idle are verified. Return-count and offline/recovery
acceptance remain open. Availability v47 handles actual power-up code 24 (6 tests).
Second reader 0748 remains offline/unassigned. The three historical Nayax sales
match existing app sessions; do not count them as new collections.

Found the original $4 rejection: the reader's price list was reduced September 28
but the app retained code 3/$4. Owner chose the existing $8 option; sandbox machine 1
now quotes800cents/code1, verified in the database and actual checkout.

**Sandbox callback flow succeeds.** At21:48:36UTC, one $8 test Start received
both authenticated Sale and SaleEnd, recorded `started`, and displayed “Machine
started” in the browser. Corrected our saved username, added observed HTTP Basic
support, and matched Pulse's settlement-only final notification to the prior
validated Sale. 237 focused checks/typechecks pass; sandbox v68 and development's
production-route v64 are byte-verified. Production pair absent/payments off.
The existing unsent Cortina reply now asks only for Production credentials and
routing confirmation. Remaining: production setup/activation gate, physical
machine and site-reliability acceptance, historical unknown reconciliation.
Intermittent canceled attempts without callbacks still occurred; no radio cause
is proven. No real funds moved or unknown Starts replayed/refunded.
The separate Yael draft's current sent/draft status was not reverified here.
Guest-card401 is fixed/deployed (21 checks, actual website sandbox checkout).
Other project work retains its October 14 cross-task baseline.
[Current evidence](NAYAX_AVAILABILITY_RESEARCH.md#current-result--october-19).

### October 14 consolidated remaining work

Reviewed the latest Nayax correspondence and the other three project tasks:
**Prioritize app fixes**, **Integrate Cortina QR payments**, and **Redesign Clean
Stream website**. This is the current status list, not approval to execute every
item. The first four rows below incorporate October 19 evidence; other hosted
release evidence remains dated October 5/6 unless stated otherwise.

| Area | What remains | Dependency / next step |
| --- | --- | --- |
| Nayax availability | Confirm returned app count after release; finish offline/recovery, bounded latency and actual-machine acceptance. | October 19 GETs succeed. Owner reports 1 → 0 available on INHIBIT/Refresh; provider 70/71 and backend idle are verified. Power-up code 24 correction deployed. Preserve Home-entry, foreground and manual refresh without a repeating timer. |
| Cortina callbacks and unknown payments | Sandbox authenticated delivery and funded vend acceptance verified October19; finish production setup and reconcile historical support-review sessions, including October 3, from correlated evidence; review app success wording against Pulse semantics. | Actual sandbox Sale/SaleEnd and browser confirmation pass at21:48:36UTC after Basic and Pulse-final-notification fixes;237 focused checks pass. The unsent case03401910 reply asks only for Production credentials and routing. Production operator credentials remain unconfirmed. Shachar Holzer covers until November 2. Pulse SaleEnd is not physical-start proof; missing Last Sales is not failure proof because it depends on our acknowledgment. |
| Machine rollout | Configure additional machines with verified location rates, terminal assignments and all six dryer amount/product/time mappings. | One enabled sandbox washer and no app dryer. Second reader 0748 resolves to Nayax machine 122693305 but is offline; its intended app/dryer assignment is not established. |
| Reader reporting | Obtain direct-reader collection samples/full-period export, refunds and fee evidence; combine with Stripe using verified IDs and matching scope/currency/mode/time. | October 19 matched all 3 available Nayax sales by both IDs and amount/currency: $8 wallet spending + $4 Stripe card vend, not $12 additional collections. Historical mode fields are NULL. API is one option; complete reports/exports are also acceptable. Do not label unverified residual subtraction as reconciled revenue. |
| App content and loyalty rules | Finish welcome-email content and informational-update wording; reconcile the proposed 10% / $5-earned reward design with existing reward arithmetic. | Reuse existing email/consent paths; do not silently change consent or financial rules. October 5 legal publication did not implement new reward arithmetic. |
| Apple, signing and device delivery | Finish native Apple provider/audience/capability/provisioning and relay setup; produce final signed Android/iOS releases and install/test them. | Apple Developer/team/APNs, Android upload signing and real store links remain external inputs. October 5 development-signed APK is ready; Owner deferred Samsung installation. No matching new iOS/store release is established. |
| Scoped acceptance and release checks | Complete remaining hosted/device social sign-in, MFA/recovery/expired-session/password-reset, push/offline, role/private-attachment/machine-remedy, resolution-mail, 90-day Auth/Storage erasure, bounce/complaint, shutdown/restore, CI/rollback, association, store disclosure and targeted accessibility/performance checks. | Use accepted local evidence and test only remaining boundaries. Y9, Y15, Y16 and Y17 below identify unavailable access/participation and bounded test decisions; do not restart broad dependency or test campaigns. |
| Website redesign | Integrate the accepted multipage preview into CleanStreamWeb-CortinaQR; remove preview controls, sync published legal/deletion text, add verified location content and finish responsive/accessibility/routing checks. Contact form is currently a prototype. | Preview remains local at `.campaign-work/website-brand-preview-20261003`; October 5 legal publication did not publish this redesign. Confirm location content, contact form versus direct links/monitored inbox, and final design/copy/publication. Keep app links coming soon until available. |
| External launch setup | Actual Google logo/support-email eligibility, Vercel business billing, store records/submission and final public launch. | Existing Y9/Y10/Y13 assignments remain; no new paid service or public release is implied. |

The Lynx-permission blocker and broad Pulse/SaleEnd question are answered;
see [October 19 Nayax findings](NAYAX_AVAILABILITY_RESEARCH.md#current-result--october-19).
The October 14/16 denials are superseded by successful October 19 reads.
**Location finances,
per-location Stripe routing and cross-location loyalty allocation are deferred by
the Owner on October 14 and excluded from the active work list.**
The legal/consent, admin privacy, machine-remedy and resolution-email release
below remains completed. Do not reopen it because older receipts say local-only.

### October 5 completed publication

October 5 publication update: the approved legal/consent, 90-day recovery,
admin financial privacy, machine-remedy and resolution-email batch is deployed
to Clean Stream. Website Terms, Privacy and deletion pages are published;
Supabase serves final loyalty policy `2026-10-05.2`. Updated Android APK is
ready. The Owner deferred Samsung installation/device testing. Automatic factual
cleanup preparation and the daily 90-day cleanup schedule are installed/enabled;
historical acceptances, recorded holds and unsettled payments remain protected.
This approved October 5 implementation/publication batch is complete. See the
current operations checkpoint for exact evidence.
The local-only descriptions below are historical and superseded by this release;
the separate website redesign and external Apple setup are not included.

### Earlier October 5 Receipts

October 5 follow-up: local three-point consent is implemented and locally checked using the
existing legal renderer, load dialog, deletion confirmation and mail outbox.
Every load requires a separate unchecked agreement; deletion records the displayed
balances and exact acknowledgement. The unpublished full loyalty candidate and
per-action receipt contract are in [loyalty terms](docs/loyalty-terms.md).
Publication and paid-credit forfeiture activation are outside this approval.

Latest October 5 clarification: Terms/Privacy/deletion drafts now specify
restricted-use laundry credit, no general cash withdrawal and forfeiture after
voluntary deletion's 90-day recovery deadline, subject to nonwaivable law. The
existing refund and dispute policies remain, with no new post-deletion payout
right. Draft wording is updated; active loyalty terms, ledger and cleanup are
unchanged. Reconcile publication and financial enforcement before activation;
this is not a missing Owner business decision.

October 5 document-review changes are implemented and locally verified:
90-day restoration, matching app/web legal drafts, Apple native
sign-in, same-day machine-remedy administration and automatic outcome emails.
See the [current checkpoint](docs/operations.md#current-checkpoint). No deployment
of this batch is claimed. Apple provider/provisioning setup remains. The Owner
confirmed same-day reporting while at the location, with same-day resolution as
the operating target; delayed staff review may still approve a timely report.

User-directed sequence, October 1: **1. Implementation/setup, 2. Fixes,
3. Testing/verification.** Current stage: **3**. Agent-actionable implementation,
setup and previously known fixes were completed with the assigned dependencies below still outstanding.
Stage-3 QA found and verified local cleanup, compact Home/Wallet layout and Owner
setup-helper fixes. The current website dependency batch passes1045 UI cases,
26 desktop/mobile browser checks, Auth safeguards, types, lint and build. The
updated unsigned Android and iOS releases and native preferences/path upgrades
pass. Android release Login/Home/Wallet also passes. QA found a newsletter
availability mismatch (fixed,88 focused checks pass) and a sign-out
redirect defect (fixed,59 affected checks pass). The rebuilt Android release
verifies both fixes and stays signed out after a real process restart. Updated
unsigned iOS Release also passes with these fixes. Actual iOS Simulator
Login/Home/Wallet, newsletter status and signed-out process restart now pass.
QA's brief ready-account fallback during login is now reproduced and fixed;
all493 affected admission/MFA/router/Settings cases pass with clean scoped
analysis. Updated Android/iOS release builds include that final correction;
rebuilt iOS login, sign-out and signed-out restart also pass.
Native iOS/Android cancellation links and plain verification navigation now pass.
A repeated recovery-link defect is fixed with128 affected routing cases and
actual reopening acceptance on both platforms; refreshed unsigned releases
include it. Successful social authentication remains a separate check.
Remaining verification is below.
October 2 follow-up: native Google account chooser is implemented locally with
approved Android/iOS OAuth registrations and Supabase client IDs configured.
Focused Auth/login checks and independent source review pass. The refreshed
Samsung APK is installed with data preserved; actual Google native chooser and
cancellation back to Login pass. No account was selected, so complete live token
exchange remains unverified. The personal Gmail MFA screen was caused by its incorrect stored
Owner role, not compulsory customer enrollment. The explicitly approved
development correction is now applied: personal Gmail is `User`, business
`jacob@cleanstreamlaundry.com` is `Owner`; audited with the role guard restored.
No test runs, analysis, builds,
simulator/browser checks, independent QA or verification campaigns during stages
1 and 2. Read the existing implementation as needed to make scoped changes.
Do not remove runtime safeguards or activate destructive work to avoid a check.
At each stage boundary, announce exactly what is finished before advancing.

Latest user instruction: enable completed development features now. Earlier
testing-stage activation holds are superseded; this does not remove identity,
financial-integrity or concrete missing-input safeguards. Sandbox reconciliation
and authenticated deletion requests are enabled, as is transactional email for
new eligible events. October 2: the Owner approved the retention schedule and
credit policy in [retention](docs/retention.md). The October 2 preservation
contract remains implemented, but the latest October 5 business direction above
now calls for voluntary-deletion forfeiture. October 5 extends restoration to
90 days in local source; the recorded hosted version remains 30 days until rollout.
The implemented preservation contract keeps purchased credit separately from the
login/profile and cancels promo/reward progress at final deletion. Neither the
new draft nor deletion creates general cash-redemption or refund rights.
Irreversible cleanup remains unactivated and is not full erasure.
October 2 clarification: no promotional emails or recurring newsletter are wanted;
the Owner will not provide a mailing address. This is not an app-release blocker.
Retain necessary transactional notices and optional informational consent; do not
relabel promotional content as transactional or activate a marketing campaign.

Items requiring the user's decision, credentials, provider access or physical
participation are parked under **Your Assigned Items**, not left on the active
implementation list. They remain unfinished campaign scope. Once the input is
provided, the agent does the dependent work; assignment does not make the user
responsible for writing code. A stage can be reported as agent-actionable work
complete only with these deferred items explicitly identified, never as release
readiness or completion of the entire campaign.

### 1. Implementation And Setup

| ID | Agent-actionable work | Status |
| --- | --- | --- |
| I1 | Install reconciliation migration/endpoint, dedicated credential and scheduler using existing Cron/Vault/pg_net. | Installed and enabled for the existing sandbox routing under the latest instruction. No new charge/refund/vend creation. Functional testing remains later. |
| I2 | Finish operational monitoring and support/incident/rollback instructions using existing records. No paid monitoring service or realtime infrastructure. | Aggregate snapshot executed successfully; incident/rollback procedures written but not rehearsed. Four historical vend sessions remain in support review. |
| I3 | Finish the source-based mobile store data-disclosure inventory and link release preparation to it. Mark unanswered provider/business details explicitly; do not submit forms or certify compliance. | Draft updated with pinned SDKs, installed iOS manifest declarations and primary vendor data/retention facts. Final business/form answers and release-binary verification remain. |
| I4 | Publish the reviewed website, then install the paired vend backend and finish private-attachment/machine-column setup. | Installed: public website, paired vend endpoint, machine-column restrictions and private maintenance bucket. Files retained. Hosted acceptance deferred. |
| I5 | Create individually named Supabase keys and configure their intended clients/components. | All 24 keys created; 21 Edge selectors plus local app/web and Vercel public configuration saved. Named-key website redeployment READY. Mobile/web public-policy reads pass and unauthenticated admission is denied. Authenticated consumers/release binaries remain to verify. Operator key unused; existing keys stay active. |
| I6 | Finish operational cleanup acceptance under the October 2 paid-credit preservation policy (former Y5). | Four migrations, retained financial references, guarded worker, dedicated credentials and dormant scheduler are now deployed. Purchased credit has no automatic expiry/forfeiture; free promo cancels at final retirement. Server-managed terms and Samsung acceptance page are delivered. Focused retention SQL55 and worker105 pass. Remaining agent work: hosted Auth/Storage deletion, truthful per-request hold/media/processor/backup inventories and scheduler activation; website disclosure alignment is local. No cleanup execution/full-erasure claim. No repeat business-policy approval needed. |
| I7 | Remove the active admin location form's dependency on a geocoding provider. | Local manual latitude/longitude entry implemented;40 focused cases pass. Customer map/listings/pins and stored locations remain unchanged. Website publication remains; no provider login, replacement account or API required. |
| I9 | Enable completed transactional email independently of promotional sending. | Enabled; real support QA confirms Auth code delivery, one scheduled welcome and one restoration notice with correlated events. No backfill or automatic subscription. Promotional emails are out of scope by the October 2 decision; mailing-address request withdrawn. |

I8/Y14 Owner assignment is complete following the explicit development correction;
the business profile was created and assigned Owner, and personal Gmail is User.
I7 is now agent work on provider-independent location
entry, not a request for the Owner to sign into geocode.maps.co.

Other code already implemented stays out of this queue. Remaining external
access, final policy, signing and launch dependencies stay below;
the approvals received are no longer treated as user blockers.

### 2. Fixes

- Samsung retained-session MFA screen lacked a way back to Login. Fixed by
  displaying the session email and adding Back to login through the existing
  admission invalidation.48 focused cases and analysis pass; corrected Android
  build installed and actual Log In/Create Account reached. No role, factor,
  saved-session or backend requirement changed. Normal signed-out startup remains
  Login, customer MFA remains optional, and retained staff/recovery sessions may
  still require verification after a later cold start.
- Native scanner acceptance found a checkout Auth replay defect: the valid QR
  decoded, but the initial SDK sign-in replay invalidated the price/retry. The
  eleven-line guard and Start tile button semantics now pass147 unique affected
  cases, scoped analysis and independent source review. Both updated unsigned
  releases pass. Actual16KB Android file-camera scans twice reach the hosted
  Washer1/12kg/$4.00 quote; all three Start tiles expose native buttons. QA signed
  out, temporary permissions/networking restored and emulator stopped. No payment
  or machine operation. Receipt: `.campaign-work/native-scanner-20261002/RESULTS.md`.
- Android native splash now follows the saved app theme on API31+, and initial
  admission checks use the existing branded loader instead of flashing recovery
  controls. Later retries retain visible terms/recovery. Eight branding/172
  admission checks, clean analysis and refreshed unsigned Android/iOS builds pass.
  Actual Android36.1 cold starts pass all four system/app theme pairs and real
  toggles in both directions; QA account signed out and emulator stopped. This
  does not establish pre31/physical-device behavior or remove normal OS fades.
  Receipt: `.campaign-work/android-startup-themes-20261002/RESULTS.md`.
- Android Firebase modal close-button accessibility is fixed using two resources,
  preserving the SDK artwork/renderer and adding a named48dp target. The exact
  rebuilt app passes portrait/landscape native semantics and expanded-area touch
  dismissal through the actual SDK. Independent QA accepts this offline synthetic
  resource check; provider delivery passed separately before this correction.
  Receipt: `.campaign-work/firebase-message-delivery-20261002/RESULTS.md`.
- iOS native appearance now follows the existing saved app theme at launch and
  on actual Settings changes. Cold starts under opposite OS appearance and real
  toggles in both directions pass; Debug and unsigned iOS Release compile with
  protected inputs unchanged. The initial OS launch snapshot and existing Flutter
  splash fade remain distinct platform behavior, not a new blank frame.
  Receipt/review: `.campaign-work/native-startup-themes-20261002/`.
- Password recovery's two misleading "reset link" labels now describe the
  existing six-digit code flow. All22 existing page cases pass; routing/service
  behavior is unchanged. Actual Android request, branded inbox delivery and code
  verification reach the empty password form. Final password submission is Y16;
  both current unsigned release builds include the two labels.
  Receipt: `.campaign-work/password-recovery-20261002/RESULTS.md`.
- Plain recovery-link replay is now fixed in the existing router: four changed
  runtime lines, eight strengthened existing cases and all128 affected routing
  tests pass with clean scoped analysis and independent source review. Rebuilt
  iOS and Android native verification-page reopening now passes after Back to Login.
  Both unsigned releases include the correction; Android's QA-signed derivative
  preserves all1520 release payload entries.
  OAuth and payload-bearing duplicate guards remain intact. Receipt:
  `.campaign-work/native-auth-links-20261002/RESULTS.md`.
- Stage-3 shutdown race is fixed and deployed: Cortina now rechecks new-payment
  availability after admission/capacity waits, before Stripe dispatch. One runtime
  line,88 unique affected cases accepted, development version59 ACTIVE with all11
  source files verified and existing gateway/internal authorization unchanged.
  No payment or machine operation. The hosted pause/restore rehearsal is Y15.
  Receipt: `.campaign-work/shutdown-dispatch-20261002/RESULTS.md`.
- Current stage-3 findings: newsletter status now reuses the existing Edge
  configuration gate; all88 focused checks and scoped analysis pass. The native
  sign-out fallback is reproduced and fixed; all59 affected router/settings cases
  and scoped analysis pass. The rebuilt Android release verifies both fixes;
  sign-out now reaches Login and remains signed out after process restart.
  No new backend, dependency or newsletter activation is required.
- The iOS-observed login transition is fixed in the existing admission gate.
  Five per-frame regressions plus the broader493-case affected suite pass.
  Authorization and account-generation checks are unchanged; no new dependency.
- Finish only concrete unresolved defects recorded during implementation; do not
  invent a redesign or run a discovery/testing campaign in this stage.
- The outdated splash-test expectation has been corrected in source, preserving
  the intentional manual iOS launch storyboard. Its acceptance belongs to stage 3.
- Duplicate DMARC corrected in GoDaddy after final approval: removed only
  `v=DMARC1; p=none;`. The existing reject policy, relaxed alignment, reporting
  address and one-hour TTL remain unchanged. GoDaddy shows one `_dmarc` record.
- First-Owner helper/runbook corrected in source: offline guarded SQL generation
  replaces remote service-key calls, account creation and automatic emails.
  Retired `--apply` is rejected; no revoked API privilege is restored. Five
  replacement offline checks now pass (five tests, exit 0). No role mutation or email.
- Stage-3 finding: cleanup cannot clear a requester that remains part of the
  Maintenance primary key. Local fix retains legacy uniqueness and report-ID
  references while moving the primary key to `maint_id`; eight key regressions
  plus four installation/gate and five lifecycle checks pass independently.
- Cleanup worker type inference and impossible-date acceptance are fixed. Both
  preview and execution reuse the same strict timestamp validator; 84 tests pass.
- Closed-attachment and automatic-account selection alias collisions are fixed in
  the unapplied cleanup migration. The final39-case SQL batch passes, including13
  new race, hold, version and expiry checks. No server configuration was weakened.
- Policy-copy follow-through is agent-owned under I6 after October 2 approval. Google logo/support-identity changes
  belong to Y10. Remaining visual concerns are observations to assess in stage 3,
  not proven bugs.
- Home/Wallet enlarged-text overflows are fixed using three existing layout
  files. Four new light/dark slow/offline-refresh cases and all133 affected
  regressions pass with clean scoped analysis and independent source acceptance.
  Controllers, money flows and normal-size layouts are unchanged; no new dependency.
- Firebase installation-deletion logic passes32 focused independent cases after
  a durable-acknowledgment fix; both native plugin compiles and scoped analysis
  pass. Complete remaining processor disposition and disclose
  actual provider retention limits; device cleanup alone does not erase historical
  Analytics or installations on closed devices. This is agent work, not user coding.
- Notification/permission/timezone updates are integrated and accepted for focused
  logic/native compatibility:24 unique cases, active metadata/analysis, iOS/Android
  plugin compiles and Android app AAR metadata pass. Device delivery, release
  resource retention and signing remain separate checks.
- Published deletion/email status wording now reflects enabled recovery requests
  and transactional email; that earlier publication did not activate cleanup or
  newsletters. Retention business approval was subsequently recorded October 2.
  Twelve public-page tests, scoped lint and hosted readback pass.
- Stripe native13.0.0/web8.0.0 is integrated without runtime payment edits. Six
  package updates,180 unique focused cases, independent source review and both
  native plugin/AAR checks are accepted; device/signed-release checks remain.
- Supabase2.18.0 is integrated with156 focused startup/Auth cases, including a
  no-Realtime lifecycle guard; final fixture analysis passes. Map/scanner/image
  picker updates are integrated after245 author cases and independent source
  review, removing orphan logger. Active combined dependency metadata refresh
  passes. Scanner iOS/Android compile and app AAR checks now pass. The updated
  CameraX still has documented RELRO alignment findings;16KB acceptance remains.
- Nine library/tool pins and required archive update are integrated without
  app-source/native/floor changes. Independent review, active57 tests, enforced
  dependency metadata and clean scoped analysis pass. Other compatible package
  families and final release/device acceptance remain open.
- GoRouter17.5.0 is integrated with a three-line manifest/lock change, retained
  294VM/53Chrome passes, independent review and active locked dependency refresh.
  The older Dev Debug APK reaches Login on a true16KB Android emulator with
  compatibility fallback disabled; current release/scanner acceptance remains.
- Package-info, secure-storage and geolocation updates are integrated together;
  189 unique VM cases,15 Node checks and independent QA pass. Existing splash
  bitmap expectations are corrected with6 branding checks and no asset changes.
  Current unsigned Android and iOS Releases now pass. Native attached-record
  persistence and scoped-clear checks also pass on Android and iOS test targets;
  full payment-flow, physical-device and signing checks remain.
- Android release inspection found and removed three unnecessary advertising
  permissions with16 focused Node checks and actual packaged-manifest acceptance.
  The isolated scanner surface JNI probe passes3/3 on16KB Android with compatibility
  off and read-only protections retained. Full scanner and the release artifact's
  native-path acceptance remain open. All13 RELRO endpoint flags have completed
  static triage with no writable-page collision; published-checklist discrepancy
  remains explicit, not13 proven bugs requiring replacement. No store-readiness claim.
- A further27 transitive dependency updates are integrated without app-code,
  direct Auth/payment-pin or SDK-floor changes. Independent source QA, locked
  metadata refresh and577 unique affected app cases pass; analysis has no errors
  or warnings. The final JNI/FFI closure and website/helper updates are integrated;
  updated unsigned Android/iOS builds and website acceptance pass. Native
  preferences/path upgrade checks now pass on Android and iOS. The updated website is published
  with its Auth patch verified and route/asset HTTP checks passing.

### 3. Testing And Verification

Stages 1 and 2 have been reported agent-actionable complete. Compatible dependency
updates and native upgrade checks are accepted within their recorded scope.
Continue scoped feature acceptance and concrete findings. Reuse valid
prior results; do not repeat whole suites without changed inputs or a release need.

1. Hosted signup/code, password login and one-time terms persistence pass for the
   approved support QA account. Android release Login/Home/Wallet passes; its
   sign-out redirect and signed-out restart now pass in the rebuilt release.
   Updated iOS build and customer Simulator smoke/sign-out restart pass;
   the login transition fix passes493 affected local cases and is included in
   rebuilt release artifacts, with fresh iOS native smoke. Actual iOS/Android cold/warm
   cancellation links, plain recovery navigation and unknown-host rejection now
   pass within their recorded OS behavior; a repeated plain verification-link
   defect is fixed and natively accepted on both. Android refuses the unknown
   host at intent resolution; iOS ignores it in the running app.
   The Google button reaches the correct provider sign-in page without submitting
   credentials on iOS. Real Android recovery-email request, inbox delivery and
   six-digit verification now reach the empty password form. Final password
   entry/submission is user-assisted Y16, not an agent-entered credential.
   Successful social authentication/credential-bearing links, MFA/recovery and
   expired-session acceptance remain.
2. Deletion/restoration/cleanup, Owner management, location restrictions and
   authenticated private attachments, after the required setup is available.
   Hosted30-day recovery, stale-JWT admission, login-without-restoration and explicit
   restoration pass for the zero-balance support account; it remains unprivileged.
3. Retain accepted pricing/all-six-dryer, callback/binding,48-hour refund/bonus,
   PostgreSQL wallet/refund concurrency and synthetic reconciliation checks.
   Three additional independent-connection Cortina funding/callback/lease races
   now pass in real PostgreSQL, with private-cluster cleanup confirmed.
   The real iOS payment page now passes process-restart checks for attached
   wallet and claim-only card records, unresolved payment locks, matched terminal
   outcomes and unrelated-scope preservation. Actual router/controller/native
   storage are used with synthetic services; no provider payout is claimed.
   The selected-dryer contrast defect found there is fixed with three runtime
   lines; two new light/dark and14 existing page cases pass, scoped analysis clean.
   The user reports real-machine
   testing is already done and excludes new machine/test-budget work now.
   Do not initiate real charges, refunds or machine starts as new verification.
   Actual16KB Android camera-to-quote now passes twice in the rebuilt customer
   release after the narrowly corrected initial Auth replay; no payment requested.
4. Home/Wallet local slow/offline retention, pagination, account switching and
   activation checks are accepted; the focused layout batch passes133 cases.
   Native Android/iOS Home/Wallet smoke and both platforms' theme/preferences
   upgrade persistence pass. Remaining: broader native performance/accessibility,
   not repeat dependency-upgrade testing.
   Two unnamed Settings notification controls are now labeled;37 affected local
   cases and scoped analysis pass. Actual rebuilt iOS native accessibility now
   exposes both labels; current customer release artifacts now include them.
   Settings rows now declare button semantics with46 widget/page cases passing;
   actual rebuilt iOS native rows now expose buttons, Newsletter opens through
   semantic tapping and Sign Out reaches empty Login. Layout and navigation are unchanged.
   Native pending-record persistence and unsigned builds pass separately; signed
   releases and full native feature acceptance remain open. The updated unsigned
   release artifacts include the layout fixes and final compatible dependency batch.
5. Auth confirmation, scheduled welcome and restoration delivery now pass with
   actual inbox and correlated webhook evidence. All13 hosted Auth previews pass
   desktop/narrow text-layout checks. The Outlook logo now renders correctly
   after showing blocked content for that one QA email; no sender-trust/global
   setting or source/security change was needed. Supabase preview behavior is
   separate, not evidence of a broken delivered email. Branded password-recovery
   inbox delivery and real Android verification of its code now also pass; this
   is not completion of the user-assisted final password change. Retain accepted295
   Deno/178 SQL mail cases, including no-login unsubscribe and signed bounce
   adapter checks. Actual matched welcome webhook replay now passes HTTP200 with
   provider attempts1->2, unchanged complete outbox/event records and exactly-one
   welcome/send. No email resent. Hosted bounce/complaint fixture approval is Y17.
   Receipt: `.campaign-work/mail-provider-acceptance-20261002/RESULTS.md`.
   Remaining is hosted other-Auth/provider suppression behavior,
   not another local mail-suite run; promotional subscribe/unsubscribe delivery
   depends on Y8.
6. Retain accepted local Firebase consent, notification routing and release-policy
   parser/cache tests. Actual iOS and Android SDK collection opt-in/revocation and
   two process restarts per platform now pass; nonblocking policy is present in iOS native and app caches with a prior
   successful SDK fetch (not a new network-fetch claim). Actual Android offline
   build/minimum/maintenance/restart/retry/resume checks now pass. The native
   recommendation accessibility defect is fixed and dismissal/hard-gate exclusion
   pass in the rebuilt release, with56 focused local cases. Android ad-consent
   denial now passes through analytics opt-in/revocation and final restart.
   Actual iOS cached build/minimum/maintenance gates, privacy access, process
   restart/retry and recommendation dismissal now pass; original caches restored.
   Receipt: `.campaign-work/ios-release-controls-20261002/RESULTS.md`.
   Cortina's late-shutdown creation race is now fixed and deployed with88 affected
   cases accepted. Remaining: genuine iOS offline transport (physical-device Y9), the hosted backend
   pause/restore rehearsal (Y15),
   signed-device push acceptance. Actual iOS provider Test-on-Device delivery
   now passes in the installed customer app: exact title/body, normal close,
   original screen restored, optional consent off and local fixture restored.
   No published campaign or account login. Receipt:
   `.campaign-work/ios-message-delivery-20261002/RESULTS.md`. Actual Android
   Test-on-Device fetch/render/dismiss now passes for the QA installation only;
   optional consent restored off, no published campaign. The default SDK modal
   close-control defect is fixed with two resources. Exact rebuilt native SDK
   modal acceptance passes name,48dp target and real expanded-area dismissal in
   portrait/landscape using an offline synthetic message. This is not a passing
   rebuilt provider retest. Dev dashboard also shows both platforms' Analytics
   activity. Receipt: `.campaign-work/firebase-message-delivery-20261002/RESULTS.md`.
   Native FIAM
   suppression now passes on both platforms: opt-in, messages-only revocation,
   Analytics revocation and process restart, with consent restored off. Android
   uses the unchanged current release and105 native reads with no errors;
   its disposable test runner is removed and emulator stopped.
   Receipt: `.campaign-work/android-fiam-runtime-20261002/RESULTS.md`.
   Receipt: `.campaign-work/ios-fiam-runtime-20261002/RESULTS.md`.
   Fresh iOS opt-in registration is
   corrected with20 SDK-channel/service/race cases passing. Native Debug
   attribution identifies APNs unavailability behind the simulator cleanup warning;
   physical signing/APNs acceptance remains Y9. A separate stale-warning bug is now fixed:
   success clears only that warning, with33 affected cases and analysis passing;
   real failures remain pending. Real-device registration/cleanup/
   delivery and signed notification routing depend on Y9; no duplicate VM reruns.
   Deletion no longer acknowledges completion after failed push cleanup; both
   reproduced failure paths now stay pending across restoration/restart, with36
   affected cases passing. Current unsigned Android/iOS releases include all
   latest corrections; protected build inputs are unchanged. No remote cleanup
   activation changed. Receipt: `.campaign-work/native-release-policy-20261002/RESULTS.md`.
7. Retain accepted website types/lint/build/Auth patch,1045 UI/26 browser cases,
   and published route/asset/association HTTP checks. Hosted missing/unknown
   machine refusal, split return scrubbing and safe reload, actual $4.00 washer
   quote, desktop layout/keyboard focus and support navigation now pass. Focused
   checkout coverage passes28 cases, including all six dryer choices by pointer
   and keyboard. Only one washer is configured remotely; hosted dryer acceptance
   needs a configured dryer. Hosted mobile/touch Chrome now passes12 observations
   at actual320/390 widths: washer quote, working Support/Privacy/Terms links,
   missing-machine and safe incomplete-return states, no overflow/broken images
   or page errors. No payment/refund/machine operation or native Safari claim.
   Receipt: `.campaign-work/hosted-pay-20261002/RESULTS.md`.
   Remaining: hosted privileged
   authenticated admin flows, provider-backed pay states not covered by existing
   acceptance, accessibility, signed-device association, a hosted GitHub CI run,
   rollback rehearsal and final signed-artifact/store disclosure checks. Incident
   snapshot already ran; do not reopen monitoring setup or dependency discovery.
   Report new defects specifically, without restarting broad implementation.

### Your Assigned Items

| ID | Input, approval or external work | Dependent agent work / stage |
| --- | --- | --- |
| Y9 | Supply Apple Developer/team/APNs access or signing material, Android upload-keystore access, actual store app records/links and later physical-device participation. | Complete signing/push/store-link setup, notification checks and genuine iOS offline acceptance. Current simulator tools do not establish app-only transport isolation; no Mac network changes or unsupported sandbox injection. Cached iOS policy tests already pass. No new paid enrollment, invented store URLs or replacement upload key. |
| Y10 | Supply/upload the actual Google logo; resolve an eligible existing support-email identity if changing Google's dropdown. | User-owned branding task. Do not create another Google account. |
| Y12 | Conditional Nayax assistance only if our own reader/API checks expose a gap. Yael confirmed Production Lynx permission on October 8; no repeated access request is needed first. | Agent verifies existing account/token, obtains a populated sample and connects reader sales without double-counting app-funded vends. Exact Cortina callback authentication still needs Maxim's configuration details. New machine tests and a test-charge budget are not assigned. |
| Y13 | Handle Vercel business-plan activation before go-live, as already assigned. | No agent billing activation. Store submission/review, final policy signoff and public launch remain external release steps. |
| Y15 | Approve or defer the requested brief development-only new-payment pause/server-rejection/restore rehearsal. No payment drafts, Stripe/Nayax calls, charges, refunds, machine starts or Firebase policy changes. | Agent performs the bounded hosted rehearsal and restores the prior value; callback/settlement endpoints remain untouched. The one-line shutdown-race fix is already deployed. |
| Y16 | Complete the final QA password entry/submission yourself in a visible simulator when ready; preparation was offered. No new credential will be entered by the agent through the UI. | Recovery email delivery and real Android code verification already pass. Agent prepares the form and observes the result/subsequent login with credentials kept private. No account privilege or financial operation. |
| Y17 | Approve the requested two nonprivileged, zero-balance QA accounts using Resend's official bounced+cleanstream-qa@resend.dev and complained+cleanstream-qa@resend.dev test recipients. | Exercise natural welcome enqueue/delivery and real signed bounce/complaint suppression without touching customer mailboxes, newsletters or finances. No accounts created yet; preserve test receipts. |

**Nayax reply reviewed October 14:** Yael answered the broad Pulse/SaleEnd
question on October 8: Pulse supplies no vend-failure feedback, so SaleEnd is not
proof of a running washer. Last Sales waits for our SaleEnd response, making its
absence inconclusive during callback problems. Exact disconnected-bench timing
remains our own test. Only the callback authentication headers/encoding and
provisioning arrangement remain a provider configuration question; do not resend
answered questions. The October 3 unknown outcome still needs positive correlated
evidence before financial resolution.

Received decisions: website publication; no older-build support; named keys with
old keys retained; disabled reconciliation installation; draft cleanup coding;
scoped DMARC correction; geocoding replacement if access exists; later controlled
mail to support; October 2 retention/credit policy; corrected initial Owner
`jacob@cleanstreamlaundry.com` (not personal `jamaki12345@gmail.com`); exact public
`cortina-vend` gateway/deployment approval. These are no longer
questions. Written, deployed, enabled and tested remain distinct statuses.
No paid activation, destructive cleanup or legacy-key retirement is implied.
Y7 and Y8 are withdrawn: use provider-independent location entry; no promotional
email is planned and no mailing address is requested. Nayax event delivery is
acceptable; Supabase Realtime remains excluded. The Lynx access request has been
submitted by the Owner and answered with a user-level permission grant on
October 8; verification/reporting integration remain agent work under Y12.

## Completion Status

Updated 2026-10-05 UTC for the approved policy/consent release. **Implemented locally** means source is integrated with recorded checks, not deployed or accepted end to end on real services/devices. Hosted deployment and deferred device checks remain distinct. Unchanged rows retain their earlier evidence; no partially implemented parent item is marked complete.

| Original deliverable | Local completion | Work still needed |
| --- | --- | --- |
| Agent guides and reference docs | Complete; entry guides shortened about60%, with required boundary lessons in one shared reference | Maintain only verified lessons and concise current evidence |
| Login redirect / no 404 | Hosted password login and Android/iOS navigation/sign-out/restart pass; transient fallback fixed. Both platforms' cancellation/plain recovery links now pass; repeated recovery-link defect fixed with128 affected cases, native acceptance and refreshed unsigned releases | Successful social authentication and credential-bearing recovery links |
| One-time loyalty terms | Server-managed final JSON `2026-10-05.2` published; one-time admission retained, with separate compact purchase consent and explicit deletion acknowledgement. Updated Android APK built | Owner deferred installation/device checks of this build; future terms edits use a new immutable Supabase publication |
| Home and wallet background refresh | 133 affected local cases pass, including compact light/dark slow/offline checks; updated release builds and actual Android/iOS Home/Wallet smoke pass | Broader native performance/accessibility; do not repeat accepted unchanged checks |
| Remove Supabase Realtime | Complete locally: source scan and real-SDK no-channel lifecycle checks pass; no replacement realtime service | Retain the no-subscription contract during later changes; older builds explicitly need no support |
| Logo, splash and Google branding | Existing logo/loading fixes accepted; iOS saved theme reaches app-owned splash. Android36.1 all four system/app pairs now match saved theme after native registration, without the initial recovery-screen flash. Current unsigned releases pass; Google links/contact saved | First-launch OS snapshots and normal fades remain distinct. Pre31/physical-device startup checks; user-owned actual Google logo and support-email eligibility |
| Dark mode | Checkout/local contrast fixes accepted; iOS native theme bridge accepted. Android36.1 actual Settings toggles preserve screen/process and all four cold-start pairs match persisted theme with a33-line native bridge; refreshed releases pass | Remaining pre31/physical-device and other-surface checks; no repeated accepted native preference checks |
| Supabase MFA | Client/UI implemented locally; Owner-only recovery database contract and endpoint installed in development | Verify real auth/recovery flows and remaining client deployment |
| 90-day deletion and restoration | 90-day recovery, prospective surrender receipts and protected append-only financial disposition deployed; automatic factual inventory and daily schedule enabled; matching public policies published | Actual hosted erasure acceptance remains separate; no customer deletion performed during this release |
| Informational consent and account emails | Hosted confirmation, exactly-one account welcome and restoration notice reach the approved inbox; duplicate DMARC corrected. No promotional campaign is in scope. | Improve account-welcome content; align visible newsletter wording with the clarified informational-only purpose without silently changing existing consent; remaining email-flow acceptance |
| Loyalty refunds and payments | Pricing/binding/callback, wallet/refund PG concurrency and48-hour/bonus contracts accepted; three added Cortina PG races and actual iOS pending-page restart/claim-only/lock/scoped-clear checks pass; backend installed/enabled | Retain synthetic/provider evidence distinction; three-line dryer contrast fix locally accepted; no additional real-machine tests requested |
| Firebase analytics, notifications and messaging | Free dev/prod setup; both platforms' SDK consent/suppression/restarts and actual QA in-app message delivery/dismissal pass. Android close-control correction passes rebuilt native portrait/landscape48dp-area dismissal separately. Both platforms show Dev Analytics activity | APNs/signing and physical-device registration/cleanup/delivery/routing; no rebuilt Android provider-retest claim |
| Version blocking and shutdown | Local controls/server pause accepted; nonblocking Version1 published; Android offline gates and iOS cached gates/dismissal pass; late-shutdown card-creation race fixed,88 affected cases accepted and development endpoint59 verified | Genuine iOS offline transport, hosted pause/restore rehearsal Y15 and verified store links; no fresh hosted-fetch claim |
| Website and pay-page review | Published routes/assets accepted;1045 UI/26 synthetic browser cases retained. Hosted invalid-machine/return states, washer price, desktop keyboard and12 mobile observations at320/390 pass, including Support/Privacy/Terms links;28 focused checkout cases include six dryer choices | Authenticated admin/funded return states, configured dryer, remaining accessibility and device association; no additional real-money tests requested. User owns pre-launch billing activation |
| Admin and transaction reporting | Multi-Owner UI, role-based financial privacy and same-day machine-remedy interface published; backend authorization/remedies/resolution-email outbox deployed. Corrected business Owner/personal User assignment remains | Direct Nayax feed requires Y12; hosted privileged-operation acceptance remains distinct from local regression coverage |
| Security and packages | Access/privacy restrictions and named keys installed; compatible package batches accepted/frozen; current Android/iOS release builds, native persistence upgrades and actual customer smoke pass, including Android16/16KB | Final security/artifact and store acceptance; no fresh blanket upgrade round or legacy-key retirement |
| Privacy, terms and store readiness | Approved Terms, Privacy and deletion pages published effective October 5; matching app copy included in the new Android build. Current immutable loyalty document aligned | Signing/provider and store/artifact checks remain; publication is not a legal-enforceability or store-approval guarantee |

Evidence and current owners: [operations](docs/operations.md#current-checkpoint). Runtime source was rechecked for explicit Supabase database subscription calls; none were found in the app, website or Edge functions. SDK Auth listeners remain intentionally in place.

## Original Scope Grouping

Current customer-app release targets iOS and Android only. A Flutter browser app
and its hosting are deferred. Public website, browser checkout and admin portal
remain in scope.

The current three-stage sequence above controls execution. This older grouping
preserves the full approved feature scope, not an alternative work order.
Dependencies and data protection still apply; blocked items go to the assigned
list rather than triggering repeated testing or an unapproved deployment.

| Order | Work together | Scope |
| --- | --- | --- |
| 0 | Documentation gate | App/web agent guides; Supabase, theming, payments, email references; ownership, checkpoints, and minimal-change review |
| 1 | Baseline + safeguards + dependency audit | Preserve existing work; correct backend access; local/deployed reconciliation; reproducible checks; authorization, wallet concurrency, callbacks, CI/toolchain risks |
| 2 | Branding + dark mode + public presentation | App logo, splash, Google auth branding, assets, saved-theme startup, contrast, public website content and accessibility |
| 3 | Login + MFA + first-run terms | No post-login 404; OAuth/deep links/protected routes; required Owner/Admin TOTP, optional customer MFA/recovery; one-time versioned loyalty acceptance before Home |
| 4 | Account lifecycle + consent + email | 90-day recoverable deletion and explicit restore; transactional welcomes and resolution notices; retries/suppression; no promotional newsletter by the later owner decision |
| 5 | Home/wallet loading + Realtime removal | Keep cached content visible, deduplicate, ignore stale responses, paginate; entry/return/resume-if-stale/manual/write refresh; remove all Supabase subscriptions |
| 6 | Payments + loyalty refund correctness | Browser/app pay UI and status; authoritative pricing; one vend; secure callbacks; machine/failed-vend/top-up flows; Owner refund review |
| 7 | Firebase + notifications + version controls | Create dev/prod projects on free plan; Analytics, FCM, In-App Messaging; consent/routing/tokens; Remote Config build blocks/update/maintenance |
| 8 | Website/admin completion | Hosting/links/pay UI; account/role/location security; privileged operations; reporting, maintenance/Storage, responsive/accessibility, routing and monitoring |
| 9 | Final hardening + dependencies + policies + release | Compatible package/platform updates; fix audit findings; aligned privacy/terms; device/end-to-end/security checks; Apple/Google standards; controlled rollout/rollback |

## Required Outcomes

- **Smallest safe changes:** preserve working behavior, reuse established code, remove verified obsolete code, and refactor only for demonstrated simplification or task necessity. No speculative frameworks, broad formatting, or dependency churn.
- **Branding/theme:** verify app icons, native/web splash, manifests, Google sign-in buttons/text, and light/dark buttons, dialogs, sheets, forms, maps, auth, home, wallet, and payment surfaces.
- **Auth/terms:** persist accepted loyalty version/time once across password/social signup before Home; reaccept only for an explicit required revision. MFA must include backend enforcement, recovery, and error handling.
- **Deletion:** server-controlled 90-day recovery period preserving original account/wallet links; explicit verified restore before deadline; normal access/marketing restricted immediately. Scheduled retry-safe cleanup must serialize with restore. No reset of refund clocks, duplicate rewards/welcomes, revoked-role restoration, or automatic newsletter resubscription. Latest draft requires voluntary-deletion credit forfeiture at the deadline, except where law prohibits it; the implemented preservation contract still needs alignment before enforcement.
- **Retention/legal:** implement the October 2 approved data-class schedule and voluntary-deletion credit policy, preserving mandatory-law and pending settlement/refund record exceptions. Business approval is not legal classification or cleanup activation. Update app/web privacy, terms, support/deletion pages, and lifecycle emails together; never promise full erasure or unimplemented behavior.
- **Newsletter/email:** optional unchecked consent separate from terms; double opt-in; one nonpromotional welcome after verified account creation plus one newsletter welcome after subscription confirmation. Reuse Resend; no-login unsubscribe, delivery dedup/retry, bounce/complaint suppression, no automatic enrollment of existing users.
- **Auth email branding:** approved design is applied to all 13 hosted-development Supabase Auth emails, with purpose-specific subjects and wording. Existing OTP/link contracts are preserved; all seven requested security notifications are enabled and persisted. Source lives in `supabase/templates/auth/`. The approved QA confirmation delivers and renders in Outlook, including its logo after per-message image display; all13 provider previews pass desktop/narrow text-layout checks. Other Auth flows/client compatibility remain separate, not claimed from one delivery.
- **Refresh/cost:** no Supabase Realtime and no general five-second timer. Trigger background pulls while cached content stays visible; bounded polling only for pending payments. Do not display optimistic successful charges or machine starts.
- **Firebase:** dev/prod separation, free plans, token registration/cleanup, foreground/background routing and consent/privacy. Spark projects and registrations exist; environment-specific SDK/consent/release controls and the approved iOS 15 floor are integrated locally. Independent QA, signed builds/APNs and physical-device verification remain (see [Firebase setup](docs/firebase.md)). Infrastructure/test delivery first, no automatic campaigns. No Firestore/Realtime Database/WebSocket/SSE replacement without separate need/cost approval; quota-reviewed Remote Config invalidation may serve urgent release controls.
- **Version control:** minimum/recommended versions, specific blocked builds, store links, maintenance messaging, staged rollout, and emergency override. Honor cached known blocks offline; otherwise permit safe cached browsing. Backend shutdown/authorization is independent of client flags and preserves settlement/refunds.
- **Top-up refunds:** server receipt within 48 hours inclusive of successful funding; no later wallet spend, including bonus-only or subsequently reversed failed-vend spend. Earlier account use is allowed. Owner review, full principal to original payment method, business absorbs fees, no partial voluntary refund initially, no bonus cash. Reserve atomically, unwind reward progress, and reconcile provider uncertainty without duplicate money effects.
- **Separate refund flows:** do not conflate the new top-up policy with machine-claim promo credits, failed-vend reversals, legal remedies, or ledger-only cash bookkeeping. Details: [payments](docs/payments.md).
- **Security/keys:** audit Auth/sessions, RLS/Storage, endpoint authorization, local storage, deep links, payments, logging, abuse controls, and permissions. Named publishable keys per client/environment and named server secrets per component; migrate all consumers before approved legacy-key retirement. Secret keys still bypass RLS.
- **Dependencies:** current compatible supported Flutter/Dart, Firebase/Supabase, Android Gradle/Kotlin, iOS, and web packages; remove unused packages, address vulnerabilities/deprecations, review breaking changes, isolate major upgrades, and verify lockfiles. No blanket automatic upgrade/fix.
- **Release:** align privacy labels/Data Safety with actual SDKs/consent, check current Apple/Google requirements, permissions, reviewer access, policy/deletion links, release builds, physical-machine operation, support/monitoring, rollback, and legal/business signoff.

## Website Detail

Retain the website review below as the detailed checklist; it shares auth, payments, privacy, and backend contracts with the app. Existing local admin work must be reconciled, not rebuilt.

1. Complete production hosting and domain setup.
   - Scope: connect the Vercel project to `cleanstreamlaundry.com`, configure DNS and SSL, redirect `www`, and verify SPA rewrites.
   - Include: `/pay`, `/admin`, legal pages, support, account deletion, Apple association, and Android association routes.

2. Review the public website and content.
   - Scope: verify navigation, location information, contact details, support hours, branding, images, calls to action, and mobile presentation.
   - Include: confirm the correct support email and remove inaccurate or unfinished scaffold copy.

3. Review legal and store-facing pages.
   - Scope: verify Privacy Policy, Terms, account deletion, support, retention language, wallet terms, refund language, and payment disclosures.
   - Include: confirm that the URLs and wording meet Apple, Google Play, Stripe, and business requirements.

4. Finish the browser payment experience.
   - Scope: review machine lookup, washer pricing, the six configured dryer choices, card checkout, wallet availability, cancellation, return routing, and status polling.
   - Include: clear states for invalid QR, disabled machine, changed price, declined payment, starting, started, timed out, refunded, and support required.

5. Review Cortina web and backend integration.
   - Scope: verify server-authoritative pricing, one Nayax Start request, device mapping, dryer product or pulse selection, callbacks, duplicate handling, timeout compensation, and live-device testing.
   - Include: strict transaction, terminal, amount, currency, and environment matching.

6. Harden public payment security.
   - Scope: add rate limiting and abuse protection to public quote, card, and status endpoints.
   - Include: require supported Nayax callback authentication or network controls and remove session access tokens from browser URLs and logs.

7. Fix admin authentication and authorization.
   - Scope: review session restoration, sign-out, token refresh, invalid-role handling, protected-route redirects, MFA, and multi-tab session changes.
   - Include: test Owner, Admin, customer, and anonymous access with crafted Supabase requests and cross-location attempts.

8. Review privileged admin operations.
   - Scope: verify employee assignment, role changes, location creation, machine configuration, washer rates, machine deletion, refunds, and maintenance deletion.
   - Include: transactional updates, server-side authorization, audit records, duplicate-submit prevention, and accurate failure messages.

9. Fix refund processing correctness.
   - Scope: ensure Edge Function errors are thrown instead of returned as successful data.
   - Include: update the displayed refund status only after confirmed success and prevent duplicate approvals, denials, refunds, or notifications.

10. Review reporting and data access.
    - Scope: verify revenue totals, transaction categories, integer-cent handling, location time zones, date boundaries, and location filtering.
    - Separate collection processor (Stripe or direct Nayax), entry channel (app/web/device), and machine-vend provider. A Stripe-funded Nayax vend is one collection, not two. Import direct reader sales only through a verified feed; preserve provider references and flag unmatched records instead of guessing matches from amount/time.
    - Report wallet funding, paid/promo wallet spending, direct machine collections, refunds/reversals and unattributed history separately. Never add wallet funding and its later redemption as two collections. Replace description-based overview exclusions with authoritative typed records and reconcile late reversals.
    - Include: replace unrestricted `select("*")`, full-table browser aggregation, and unpaginated transaction queries with scoped server queries.

11. Review privacy and maintenance data.
    - Scope: verify location-based access to maintenance records, customer information, descriptions, and attachments.
    - Include: secure Storage policies, image validation, retention, removal of unnecessary raw user IDs, and safe attachment links.

12. Complete responsive and accessibility review.
    - Scope: test all public and admin pages on phone, tablet, and desktop.
    - Include: table overflow, form labels, keyboard navigation, modal focus management, icon-button names, screen-reader announcements, contrast, and reduced-motion behavior.

13. Review routing, assets, and failure states.
    - Scope: test direct URLs, refreshes, browser history, unknown routes, expired sessions, and Stripe return links.
    - Include: add a deliberate 404 page and replace remaining development `/src` image paths with production-bundled imports.

14. Complete security and dependency review.
    - Scope: upgrade vulnerable React Router packages, run `npm audit`, review third-party packages, and verify that no service-role secret can enter a browser build.
    - Include: restrict or proxy the geocoding API key, add appropriate security headers, and run Supabase security and performance advisors.

15. Strengthen testing and deployment checks.
    - Scope: add required TypeScript checking, lint, tests, build, dependency audit, and browser end-to-end tests to CI.
    - Include: test real route wiring and dependency injection currently excluded from coverage, not only mocked components.

16. Add production monitoring and support operations.
    - Scope: monitor browser errors, Edge Function failures, failed vends, callback rejection, refunds, and `support_required` sessions.
    - Include: documented machine disablement, manual refund review, deployment rollback, database restore, and incident response.

## Website Release Acceptance

- All public and admin routes load directly from the production domain.
- Apple and Android association files return valid JSON without redirects.
- Owner and Admin access is proven to be location-scoped at the database level.
- Browser washer payments and all six dryer options pass live-device testing.
- Duplicate and failed payment scenarios cannot vend, charge, or refund twice.
- Type checking, lint, tests, build, dependency audit, accessibility checks, and end-to-end tests pass before deployment.

## Shared Boundary

This is a combined app and website campaign. Shared backend changes live in the app repository and have one Backend owner. The website owns browser checkout/admin/public pages and association files; Flutter owns mobile UX. Preserve existing local work and use explicit deployment gates rather than publishing the entire dirty workspace.
