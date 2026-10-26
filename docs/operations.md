# Campaign Operations

Updated: 2026-10-26. Working record, not proof that planned features exist.

## Current Checkpoint

**October 26 Mac mini handoff:** Owner requested the local work be saved in the
repositories for development on another Mac. The handoff source, templates and
setup guide target `codex/mac-mini-handoff-20261026` in the app and active website
repositories; publication is verified separately. See [Mac development setup](mac-development.md).
This preserves current work, not release acceptance. Local environment/Firebase
configuration, signing material, generated builds and application backups stay
outside the handoff tree. Existing deployment and device gates still apply.

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

**October 26 store preparation:** Owner authorized store/account/signing setup,
TestFlight and a Google test track when ready; public release and Kisi are deferred.
Apple agreement acceptance is confirmed. App6758858954 retains its existing
bundle ID and builds1–7 are expired; next candidate is1.0.0(8). Apple team3843FZGZ7T
has a managed distribution certificate, plus local development signing. Google
app4975882668793223007 was created under the Clean Stream Laundry Solutions LLC
organization8783292919873846884; the reported creation problem is no longer present.
Apple description/links/subtitle/Lifestyle category and manual-release setting are
saved. Google listing copy/privacy URL and internal-release notes are saved drafts.
Android1.0.0(8) is signed, accepted and **available to internal testers**.
The internal track contains only jacob@cleanstreamlaundry.com initially; opt-in:
https://play.google.com/apps/internaltest/4700969703506028817 .
No public store release/review submission. iOS archive is currently compiling
after the owner signed the Clean Stream account into Xcode; first attempt failed
for the missing Xcode account/profile capabilities and is preserved separately.

Implementation/setup is complete for the narrow beta correction: StartPage keeps
the existing laundry controls and defaults unfinished mock door access off. Its
Tap to Pay instruction now fits two lines.24 focused UI/render checks pass;
four changed files analyze cleanly. Real-font light/dark renders at360/430 widths
are inspected. One earlier render-harness wait was stopped and corrected by using
the existing real-clock capture pattern; it was not an app failure or passing run.
Signed Android build passes (216.4s); Google accepts build8 / targetAPI36,
with mapping and native debug symbols. All packaged64-bit ELF LOAD alignments
meet16KB; this is not physical-device/RELRO acceptance. Current stage is iOS
archive/upload and store asset preparation, serialized with browser work.
New Android upload signing material is owner-only and ignored; preserve its private
backup. Store assets, review access, disclosures and final device acceptance remain.
Evidence: workspace `.campaign-work/store-release-20261026/`.

**Nayax October22 response:** Shachar confirms the endpoint and resupplies a note
containing Token and Token ID. Owner authorized secure retrieval and also saved it
in Notes. October26 digest comparison proves that token already matches both stored
Start tokens; both production callback pair fields remain absent. No secret or
payment mode changed. A concise Reply All in existing case03401910 asks for the
production HTTP Basic pair or confirmation of shared sandbox credentials; **unsent**.
This supersedes the older draft status below. No additional Lynx access request.

October 19 items 2–4: current stage is scoped verification and correction.
The existing Core token returns **200** for all four reader endpoints and four
account/role diagnostics. Its digest/base match hosted configuration. The earlier
permission failures are superseded. Project: `dnuuhupoxjtwqzaqylvb` (development).

**Pricing defect found and corrected:** Core history shows the reader's price
array changed September 28 from `1000,800,600,400,200` to `1000,800`, while the app
still requested product code 3/$4. A Core code11 event at the original October 19
11:22:06 machine-local time says “product price is 0.00 on server - auth failed.”
This matches the 15:22UTC test time. The owner selected the existing $8 option;
a guarded transaction changed only sandbox machine 1's mapping to `{"800":1}`
and its sole-consumer washer rate to 800 cents. The trigger set Machines.Price=8;
the actual public checkout displays $8. No reader setting or production mapping
changed. The original $4 unknown session remains preserved without retry/refund.

**Sandbox flow verified at 21:48:36 UTC (5:48:36 PM local).** Session
`f46dad1b-dc66-457d-984f-4306f6c2959c`, transaction
`b696a7656d8d423dbd799b7427c9b558`, Nayax transaction `4903267080`:
exactly one Start, authenticated Sale at21:48:28.777 and SaleEnd at21:48:36.854,
800 cents/USD, status `started`, completed_at21:48:36.872, no failure/refund.
The actual browser displays “Machine started.” This is payment-provider completion
on the bare reader, not evidence of a physical washer cycle. No real funds moved.

Two local compatibility defects are resolved. The saved-source sandbox username
was corrected at21:14UTC (password unchanged). Actual provider diagnostics at
21:35:02 then established **HTTP Basic**, while our parser expected separate
headers. Basic support requires the complete exact environment-specific pair;
partial/wrong explicit headers cannot fall back to Basic or a token. No values,
hashes or full request bodies were logged. Nine sandbox probes and actual
provider acceptance establish the corrected credentials.

After authentication worked, SaleEnd was rejected by our repeated-money check.
A bounded diagnostic at21:44:11 showed BasicInfo amount/currency absent,
PaymentInfo.AuthAmount=0 and SettAmount=8. The corrected handler requires exact
settlement cents, a matching bound provider ID, an approved/started session, and
its same-environment authenticated Sale audit with matching transaction, device,
amount and currency before recovering omitted currency. Present conflicts remain
rejected. Normalized audit money includes explicit provenance; SQL money,
ownership, state and idempotency guards are unchanged. Temporary money-shape
logging was removed after diagnosis. **237 focused tests and both entrypoint
typechecks pass.** Sandbox v68 and the production-route adapter v64 in this
**development** project are ACTIVE; all four runtime files of each match stage.
Production pair remains absent; an unauthenticated invalid-body probe is denied.

Earlier canceled/unknown sessions are preserved without replay or refund,
including the21:46 attempt `981162e0-3095-4f50-9170-8b26d75fc07e` which had an
Approved Start but no recorded callback and owner-reported cancellation. The
following fresh21:48 attempt succeeded. Intermittent delivery/reception remains
an observation to validate at the site, not a proven radio diagnosis.

Cortina case03401910's existing reply is saved **unsent**, revised to ask only for
Production HTTP Basic credentials via the existing secure method and production
callback-base confirmation. The obsolete separate-header/authentication-failure
question was removed. No new Lynx/Yael access request is needed. Owner sends mail.

The guest-card401 correction remains deployed: `cortina-vend` v65 accepts only
explicit guest key names `cleanstream_dev_app` and `cleanstream_dev_web`, preserving
human admission and the outbound VEND key. 21 focused checks/typecheck and hosted
same-request checks pass; the new actual website checkouts also reached Stripe
success. Five broader wallet key-fixture failures reproduce on unchanged baseline
(`new_payments_unavailable`); they are not claimed as passes or changed here.

The production-route adapter now includes the verified compatibility fixes and
remains internally authenticated, with its pair absent. Only sandbox machine 1
is enabled. No production payment activation.
See [credential configuration gate](../CORTINA_SETUP.md#production-credential-configuration-gate).
Current evidence and exact rollback baseline:
workspace `.campaign-work/nayax-pulse-review-20261019/`; earlier guest/auth evidence:
`.campaign-work/nayax-auth-verification-20261019/`.

Owner chose manual Samsung checks: Madison Ave initially showed **1 available**;
after grounding INHIBIT and refreshing, **none available**. Reader 0568 emitted
70 at 14:11:59.400 UTC and 71 at 14:12:48.630; backend cached idle/71 at
14:12:54.189. The busy cache row was superseded before inspection; owner release
and returned-app-count confirmation remain pending. Actual power-up event 24
revealed an old-signal gap: added it to the existing restart guard, **6/6** focused
tests and entrypoint typecheck pass, deployed availability v47 and downloaded
all four runtime files to verify exact match. Home/foreground/manual refresh is
unchanged; no timer or Samsung build/install was added.

Reader 0748 resolves to machine 122693305 but reports offline, without keepalive
or power-up timestamps; intended app/dryer assignment remains unverified. All
three retrieved $4 sales match existing sessions by both provider transaction IDs
and amount/currency: two wallet spends, one Stripe card vend. They are not three
additional Nayax collections. Historical environment fields are NULL; no mode
was inferred or backfilled. Direct-reader collections, fees, full-period exports,
additional mapping and provider-originated payment acceptance remain open.

Outlook Sent Items confirms the owner sent the earlier Yael escalation October
19 at 9:53 AM. A follow-up reporting restored access is saved **unsent** in the
same thread, same two recipients. No mail was sent by this chat. Fresh checks
should have preceded clearing that escalation. Current evidence and rollback:
`.campaign-work/nayax-setup-20261019/`; see
[October 19 results](../NAYAX_AVAILABILITY_RESEARCH.md#current-result--october-19).
Earlier dated Nayax entries below are historical receipts, not current blockers.

October 14 subsequent console check: owner successfully signed into the official
Lynx Swagger page using existing Core credentials. Set the existing LYNX token;
the console's authorization dialog reported Authorized, but expanded API groups
showed no operations, including Machines/Permissions. No independent console API
request ran, so the earlier direct 403 responses remain the verified API result.
Empty groups do not prove a specific permission defect. Linked Swagger catalog
downloaded, but local file access prevented inspecting it; no security setting
was changed to obtain it. No new token, role, device, app or deployment change.
Signed-in console left open; temporary local viewer exited; Yael draft unchanged
and unsent. See [console evidence](../NAYAX_AVAILABILITY_RESEARCH.md#signed-in-production-console-check--october-14).

October 14 role diagnostic at 20:05 UTC: owner signed into the familiar production
Core portal; reused the existing token for user 230347447. The documented
`GET /v1/actors/2003775356/roleGroups` also returned **403**, correlation
`tfemczdyyEaTrBMx`. No returned group IDs, so no dependent group reads or role
changes. Token/base still match hosted configuration. The separate Swagger
console is optional and its sign-in request was withdrawn. The available docs
and Core controls have not yielded a supported local correction; exact missing
permission requires clarification. Added this evidence to Yael's existing thread
reply, **unsent**, with original content/recipients/history preserved. Maxim's
callback-authentication email was sent by the owner. No device, credential,
permission, app or deployment change. The one-shot probe exited and saved only
sanitized evidence. See [role diagnostic](../NAYAX_AVAILABILITY_RESEARCH.md#operator-role-diagnostic--2005-utc).

October 14 broader documentation audit at 19:56 UTC: owner reports Maxim's
callback-authentication email **sent**; Yael's reply remains unsent and unchanged.
The earlier targeted audit was not exhaustive. Downloaded/searched all 180 indexed
Lynx pages, related SQS/Cortina/Core Extension guides and both API specifications
(283 documents/specs total), and read the original onboarding email/proposal.
Found endpoint-specific Lynx permission documentation and previously untried
read-only operator-role-group diagnostics. Their existence does not prove this
user can read or change permissions. The optional production API console was
opened, but its sign-in request was subsequently withdrawn. The existing Core
token was used instead for the 20:05 UTC diagnostic above. No changed credential,
permission, device setting or deployment is claimed. Audit scope:
[broader audit](../NAYAX_AVAILABILITY_RESEARCH.md#broader-documentation-audit--1956-utc).

October 14 self-service investigation at 19:14 UTC: regular-account reader 0568
is Active, Cashless + Telemetry, MQTT Enabled, Inhibit logic 0, timeout 5 seconds;
Queue confirms both Inhibit settings collected successfully September 28.
Checked developer setup/token/reference docs, Core's available attribute catalog
and user-management view. No supported missing device-enable switch was found.
Even `/v1/actors/hierarchy` without a machine/device ID returns 403, as do operator
device inventory and the alternative documented machine lookup. Existing token/base
still match hosted configuration. Exact API scope cannot be inspected/changed in
the available DEV user-management view. Reader last communicated October 7; power
and connectivity are also required for a later physical test. Updated Yael's
existing thread reply with these findings, **unsent**. No device configuration,
roles, credentials, deployment or payments changed. Evidence and remaining scope:
[device/account isolation](../NAYAX_AVAILABILITY_RESEARCH.md#device-setup-and-account-level-isolation--1914-utc).

October 14 authorized Lynx verification supersedes the earlier read-only status
review below: all four direct provider GETs (device mapping, status, alerts and
sales) returned HTTP 403 at 15:35 UTC. Confirmed DEV login `dually-app\jacking`,
user 230347447, reader 0568 and machine 79835724. The tested token/base hashes
match the hosted configuration; deployed availability source matches local.
No credential replacement, permission change, deployment or payment occurred.
Nayax must investigate the exact user/endpoint scope despite its reported grant.
Fresh secret inventory also confirms callback authentication remains unconfigured.
Detailed correlation IDs: [reader verification](../NAYAX_AVAILABILITY_RESEARCH.md#authorized-reader-verification--1535-utc).

October 14 QA recheck at 16:06 UTC: the owner signed in successfully.
QA user `nayaxvend\JacobKing` (1000870211) uses the same email but is distinct
from Production/DEV user 230347447. The only QA machine is simulated 1003684111.
Existing QA token status/alerts/sales reads all return HTTP 200; it remains
offline with empty alerts/sales. No backend credential or device mapping changed.
Owner directs Lynx follow-up to Yael; Maxim’s unsent Cortina draft now contains
only the callback authentication question. A separate unsent reply to Yael in
Lynx case 03713828 asks her to investigate the exact Production user/403 scope.
Full evidence: [QA recheck](../NAYAX_AVAILABILITY_RESEARCH.md#qa-account-recheck--1606-utc).

Owner direction: combine Stripe reporting with Nayax reports/exports if needed
to reconstruct the complete financial picture, preserving collection/vend/wallet
distinctions and reconciled periods/currencies. Location finances and routing are
deferred; remove them from active execution. No new reporting service is implied.

October 14 cross-task/email review: **Prioritize app fixes**, **Integrate Cortina
QR payments**, and **Redesign Clean Stream website** were consulted. The current
consolidated list is [Current Work Order](../APP_FIX_PRIORITIES.md#current-work-order).
This review adds no hosted/API/device acceptance, deployment or financial action.

Yael's October 8 reply confirms Production Lynx permissions were granted to the
user. Replace the old permission-request blocker with fresh read-only verification
against reader 0568 / machine 79835724 using the existing account/token. October 6
QA status/lastAlerts/lastSales HTTP 200 and five reconciliation passes remain valid
receipts for the separate offline sample, not proof of physical-reader access.
Yael also confirms Pulse lacks vend-failure feedback and Last Sales appears only
after our SaleEnd response. A missing sales row therefore cannot establish vend
failure or authorize compensation; SaleEnd does not prove physical washer start.
Only the exact incoming Cortina authentication contract remains unanswered by
Nayax in the reviewed mail. October 6 hosted code required
`NAYAX_CALLBACK_AUTH_TOKEN`, still absent in the fresh October 14 secret inventory. Match provider/server authentication before another funded
vend test. The user sent the October 6 email; it is no longer an unsent draft.
Detailed sources and evidence boundaries:
[Nayax checkpoint](../NAYAX_AVAILABILITY_RESEARCH.md#current-result--october-14).

October 5 approved app/backend/website release: seven migrations through
`20261005181711` are applied; policy `2026-10-05.2`, 90-day recovery and the
authenticated per-action deletion endpoint are confirmed remotely. All thirteen
affected Edge Functions are updated and ACTIVE, with gateway authentication
unchanged. Vercel deployment `dpl_2Sxq9oEkTGrZ2JrsFPVDcTUa82P7` is promoted;
the public Terms, Privacy and deletion routes return the new deployment.
Android signed development APK is ready; Samsung installation/device testing
are expressly deferred by the Owner. No new iOS/store release is claimed.
Core backend QA passes30 runner records; legal checks pass web16/Flutter25.
Automatic inventory migration `20261005183040` is installed; focused QA passes9
runner records and1 Deno case. The existing daily cleanup schedule, matching
Edge configuration and DB execution/surrender controls are enabled. Final hosted
readback confirms zero pending deletion requests/external cleanup operations;
no customer deletion or financial action was dispatched during this release.
Historical acceptances are not retroactively eligible for surrender; concrete
holds and unsettled payments remain protected. Exact release/rollback evidence:
`.campaign-work/action-consent-20261005/RELEASE.md`.
The separate website redesign remains excluded; no billing or Gundex changes.

### Superseded Local Receipts

Entries below describe earlier work at its recorded time. The publication state
above supersedes their local-only and older policy-version statements.

October 5 deletion-copy follow-up: removed only the sentence beginning "Existing
eligible refunds" from the unpublished deletion acknowledgement and its preview
fixture. Full terms, balances, recovery and consent behavior are unchanged.
Four light/dark normal/large-text render checks pass. Gallery refreshed; no
publication or native installation.

October 5 compact purchase consent: replaced the purchase paragraph with
"I agree to the Loyalty Program Terms for this purchase." The terms title links
to the exact policy snapshot; opening it does not check the box. The candidate
and server fallback record the same displayed acknowledgement. Full policy text
and deletion acknowledgement are unchanged. 101 focused Flutter cases (including
12 renders) and 18 disposable PostgreSQL cases pass. Local preview refreshed;
no hosted changes or native installation.

October 5 three-point consent: LOCAL IMPLEMENTATION AND FOCUSED QA COMPLETE.
Owner approved initial prominent disclosures, unchecked agreement on every load,
and explicit deletion acknowledgement with balances/90-day restoration, locally
only. No publication or forfeiture activation. Composer owns Flutter, mail
renderer, docs and unpublished policy JSON; Poincare owns the new consent migration,
Stripe entrypoints/helper and backend tests. Existing initial acceptance is reused.
Current published wording remains authoritative until an approved new publication.
Candidate: `supabase/policies/loyalty-surrender.draft.json`. Backend:
`20261005152329_loyalty_action_consent.sql`; no remote execution. No customer
funds, existing acceptances, reward arithmetic, or retention execution changed.
Serial acceptance: 18 PostgreSQL, 234 payment/consent, 164 email, 495 distinct
Flutter cases and 16 real-font render states pass. Actual Deno entrypoints check.
Scoped analysis retains one preexisting warning/six infos, no errors. Fixed the
deletion preview spinner before confirmation; corrected fixtures without weakening
Auth/financial checks. No new native build, simulator or real provider/customer
action. Screenshot gallery and detailed receipt:
`.campaign-work/action-consent-20261005/index.html` and `QA-RECEIPT.md`.
PG covered the 30-day baseline, email both 30/90 days; coordinated 90-day/policy
migration order remains a rollout check, not a claimed hosted result. Runtime
processes have exited. The preview is queued in Codex; Samsung remains unchanged.

Latest October 5 wording correction: Owner expressly directs no general cash
redemption and forfeiture of remaining credit after voluntary deletion's 90-day
recovery deadline. App/web Terms, Privacy and deletion-page drafts now reflect
that rule with a nonwaivable-law exception. Existing refund deadlines, timely
machine claims and dispute rights remain. This changes review copy only, not
balances, accepted loyalty terms, cleanup execution or hosted configuration.
Business intent is resolved; legal applicability and financial implementation
alignment are separate. Do not reuse the preservation candidate as a matching
publication. The earlier acceptance receipt below predates this wording change.
Copy verification: app/web draft maps and all 61 reading-copy paragraphs match;
16 focused website checks pass across PublicLegalPage and App.public. Scoped
tracked-file whitespace checks pass. No Flutter rerun/native build or hosted
mutation for this prose-only correction. The redesign task reports its saved
preview copy synced, including the draft notice and all deletion paragraphs;
no design, server or deployment changes.

October 5 review follow-up: LOCAL IMPLEMENTATION AND TARGETED ACCEPTANCE COMPLETE.
Composer integrated matching app/web drafts, public deletion copy, 90-day
lifecycle, native Apple sign-in, machine-remedy backend, resolution email and
Owner remedy UI. Zeno ran one serial runtime queue; no competing builds or
browsers. No hosted changes in this batch. That batch preserved paid credit;
the subsequent Owner forfeiture direction is recorded above.
Research distinguishes voluntary cash-out from billing-error/restitution rights
and notes the reloadable/non-gift federal exclusion. See
[prepaid-credit research](prepaid-credit-law-review-20261005.md).

Drafts now state 90 days, same-local-day/on-site voluntary machine remedy,
restricted-use prepaid service, Apple/Hide My Email and resolved-issue notices.
They remain review-only, not the active immutable loyalty publication. Existing
account restoration has prior hosted success evidence, not new 90-day acceptance.
Replacement vending reuses Cortina with a distinct sponsored funding source so
it cannot charge again or trigger duplicate compensation. Automatic remedies
require verified wallet-funded originals; card-funded or uncertain originals
remain manual review. Native Apple uses
the existing isolated Auth exchange; compatible plugin 7.0.1 adds three Pub nodes,
not an SDK upgrade. No real email, vend, refund or account mutation authorized
by these local checks. The redesign task confirmed its saved policy and deletion
copy match. Apple is enabled in the correct hosted project, but its allowed
audience is browser-only; native audience approval was requested. Apple Developer
capability/provisioning and private-relay setup still require account access.
The Owner confirmed: report the same day while at the location; aim to resolve
that day while the customer is still washing. Delayed staff response may still
reconcile and approve a timely report afterward. App/web drafts and the unapplied
loyalty candidate now say this explicitly; eligibility code is unchanged. These
are local review drafts/candidates, not published policies or a deployed remedy.

Acceptance: 143 distinct web cases; 553 Flutter feature/service cases plus 28
router cases; 478 Edge cases plus 105 cleanup-worker cases; 102 SQL runner
records (including five parent records). Admin TypeScript, actual pinned Deno
entrypoint checks and the Auth-patch-verified website build pass. Two synthetic
browser views (1440px/390px) show the new form without overflow; four screenshots
capture its top/bottom. Reporting confirms sponsored starts add no collection
or wallet spend. Full receipt: `.campaign-work/review-followup-20261005/QA-RECEIPT.md`.

The first 90-day attempt caught the Owner migration's public/private request
wrapper split; the candidate now updates only the private body, preserving the
public Owner guard and ACLs. Fixture corrections cover real Auth timestamps,
actual Storage prototypes and the existing capacity RPC. No safety checks were
removed. Node-only `typecheck:admin:edge` still cannot resolve the newly reached
Deno remote imports/ImportMeta; actual Deno checks pass instead. Scoped Flutter
analysis reports one existing warning/seven infos, not a clean analysis result.
No new native binary, signed Apple login, hosted migration, real follow-up email
or payment/provider acceptance is claimed. Existing review server 4176 remains.

October 4 legal drafts and portal roles: local implementation and focused
verification complete, not deployed. Terms/Privacy now have twelve numbered
sections, document typography, selectable app text and explicit draft status.
They preserve current refund/deletion/paid-credit rules; no consent, reward
formula, Analytics runtime or published Supabase loyalty version changed.
Analytics wording reflects the owner's reliability-only/no-advertising purpose
while disclosing automatic technical identifiers. Reading copy and remaining
editorial issues: [legal review](legal-review-20261004.md).

Portal roles are Owner (all), Manager (assigned-location operations without
finance, read-only team), Maintenance (assigned maintenance work only).
Frontend guards/cache/export cleanup and database/Edge denials are implemented;
the existing raw Admin role defaults to Manager. Named account assignments remain
unchanged. New migration `20261004215548_portal_role_financial_privacy.sql` and
admin-portal endpoint require coordinated deployment before hosted enforcement
is claimed. Contract/evidence: [admin permissions](admin-permissions.md).

Verification:225 unique focused web checks,25 Flutter legal checks,18 SQL tests
(17 child scenarios plus parent),186 Edge tests,8 desktop/mobile Playwright cases
passed. Scoped admin TypeScript and the Auth-patch-verified website build passed.
Whole-site typecheck still reports the unrelated pre-existing invalid `exact`
option at `src/components/CortinaPayPage.test.tsx:96`; not changed in this batch.
Initial stale text assertions, duplicate Team panel keys and storage test mocks
were corrected; no safety assertion was relaxed. A pending financial export can
no longer download after role change or unmount. No native rebuild/install,
hosted mutation, email, payment or account-role change occurred.

The user requested coordination with task `Redesign Clean Stream website`.
That task copied the exact drafts into its saved preview and retained its design.
Source ownership stayed separate. Headless desktop/mobile and720px reflow reads
passed; screenshots are in `.campaign-work/legal-roles-20261004/`. The initial
artificial CSS-root zoom probe overflowed its existing header; normal responsive
reflow passes, not a claim of actual-browser zoom coverage. Its previews remain
closed. Current React screenshots are under website `test-results/legal-roles-*`.
No dependencies or frameworks added. Reused legal renderer, portal/API transport,
canonical admission, audited receipts and maintenance controls; supporting guides
updated with durable role, draft-publication and Analytics distinctions.

October 3 quiet main-tab refresh: implemented and installed on Samsung. Start
and Settings now join Home/Wallet in the existing retained router shell; loaded
data, map and preference controls survive tab changes. Availability refreshes
silently with a cached snapshot, and the notification value no longer waits for
the role lookup. Start still rechecks its balance on activation. No Hive, backend,
payment mutation or new polling.153 unique focused checks pass; one unrelated
older Firebase Settings assertion still expects the removed Analytics switch.
Scoped analysis is clean. Android build2m53s/install pass, protected inputs
unchanged; actual early-return Home/Wallet/Settings frames show no initial-load
flash, with balance248 and notification value5 preserved. Phone left on Home.
No iOS rebuild. This is warm main-tab retention, not persistent offline storage.
Receipt: `.campaign-work/quiet-tabs-20261003/RESULTS.md`.

October 3 Home-map sizing correction: three existing widgets now reserve the
availability, address and wallet text slots while data loads. The regression
reproduced a287px-to128px map jump; light/dark loading and tab-return checks now
retain identical map size. No routing/controller, camera, payment or backend
change.35 Home-page checks and62 other Home checks pass; scoped analysis is
clean. The local screenshot helper needed real-clock capture and an isolated map
cache; its initial failures were fixture failures, not passes. Two corrected
real-font render checks pass. Samsung build2m48s and in-place install pass,
with protected inputs unchanged. Actual early/middle/settled Start-to-Home
captures retain the same map bounds and the previous settled size; tiles/pin
render correctly, and the phone is left on Home. No iOS rebuild. Receipt:
`.campaign-work/home-map-20261003/`. The exact pulse-feedback/SaleEnd question
is recorded under Your Assigned Items in APP_FIX_PRIORITIES.md, deferred until
Maxim's next email. No message sent and no pending payment modified.

October 3 name-input follow-up: removed the client length cap and counter from
Create Account/Edit Profile, without a replacement limit or backend change.
81 regressions and4 light/dark render cases pass, including200-character input.
Samsung build/install complete (2m49s, protected inputs unchanged). Actual Profile
counter removal inspected; no account edited/saved. Device left on Edit Profile.
Receipt: `.campaign-work/name-input-20261003/RESULTS.md`.

October 3 owner-requested UI revision: implemented, checked and installed on
Samsung. The owner approved Create Account/Reset Password; those remain fixed.
The follow-up replaces relocated gaps with taller request-description fields and
moves Delete Account outside the red notice. Fixed four collapsed gradient
backgrounds that hid header labels; all affected light/dark headers inspected,
with size regressions added. Gradient headers retain yellow rules. No controller,
policy or backend change.164 initial regressions plus45 focused follow-up cases
and light/dark,2x-text/navigation-inset and keyboard renders pass (counts overlap).
Final build2m48s; protected inputs unchanged. Actual Samsung refund/maintenance
screens inspected, no submission. Phone left on Request Refund. Receipt/gallery:
`.campaign-work/secondary-ui-revision-20261003/RESULTS.md` and `before-after.html`.
The earlier live top-up refund read failure is not resolved by this UI batch.

October 3 secondary-screen polish: eight approved groups implemented, focused QA
complete, final Samsung build/install complete. Home is color-only; other
main tabs,Auth/payment rules and controllers are unchanged.56 matched pairs cover
light/dark pages, confirmations and bottom scroll states. The old maintenance
dropdown overflow is repaired; a new transparent touch-padding defect was fixed
while preserving original center-tap/guard tests. No real refund,deletion,
subscription or payment submitted. Isolated medium-effort authors and one serial
QA runtime were used. Receipt/gallery:
`.campaign-work/secondary-ui-20261003/RESULTS.md` and `before-after.html`.
The Add funds design was accepted by the owner's "much better" reply;
these secondary screens still require owner visual review. No iOS rebuild.
Actual Home confirms unchanged geometry,balance,location/map with corrected dark
colors. Build2m50s passes with protected inputs unchanged. Device Top-up refunds
lists fail to refresh on entry and one retry; cause unestablished, controllers/
services unchanged. This remains a live-service verification issue, not a passed
refund flow. Confirmation screenshots are fixture-only. Failure evidence is in
the receipt; no financial mutation was submitted.

October 3 Add funds branding: implemented and installed on Samsung. The owner
called the corrected layout a solid foundation and requested stronger branding.
Added the existing logo/blue header, yellow rule/selected preset and blue-tinted
controls. Retained editable amounts,25-cent +/- controls,10/15/25/50 in one stable
row, Load/Cancel, full disclosure, limits/default and checkout behavior. The
theming checklist now requires brand identity beyond a blue submit button.

Dialog38/render12 pass (50 unique); final logo-decode assertions pass again in
both themes. All three changed Dart files analyze cleanly. Actual device review
led to bounding the logo decode to its displayed size; the supplied artwork
still has faint edge specks, not claimed fixed. Latest one-worker3GiB build2m49s
passes with protected inputs unchanged. In-place install preserves data/settings;
actual screenshot and aligned selected row reviewed. Dialog open at50.00, no
Load submission or financial mutation. No iOS rebuild/backend/website/Gundex
changes. Branded-design owner review remains pending. Current receipt:
`.campaign-work/add-funds-branding-20261003/RESULTS.md`.

Earlier layout correction/guideline evidence:
`.campaign-work/add-funds-polish-20261003/RESULTS.md`; cent-conversion evidence:
`.campaign-work/add-funds-20261003/RESULTS.md`. The original wrapped presets and
unrequested stepper removal were rejected, not owner-approved by passing tests.

October 3 Home/wallet/location/analytics and availability/navigation fixes:
implementation, focused verification and Samsung delivery COMPLETE. The
PostgREST read-only wallet failure is corrected by deployed migration
`20261003115914`; mutation locking, admission, grants and balances are unchanged.
Authenticated read-only SQL and actual Samsung Home/Wallet now return $3.00.
The original error SnackBar could outlive recovery under accessible navigation;
the new UI closes only its own recovered error. Home renders without waiting for
wallet/GPS; existing account guards, cached-content refresh and timeout limits
are retained. Location details/camera/persistence use the selected record ID.
Public Census address matches confirmed swapped Madison/Columbus coordinates;
the guarded two-row operation corrects pins only, preserving IDs/machine links.

Operational Analytics is automatically enabled after configured startup; the
old toggle/preference is removed. Advertising consent stays denied, messages and
push stay optional, and account-deletion privacy restrictions remain. App and
website privacy copy is aligned locally; the website is not newly published.
Home78/Firebase175 focused cases pass across the initial run and scoped fixes;
the initial GetIt fixture race and eight incorrectly unconfigured notification
fixtures are corrected/re-run, not counted as initial passes. Legal21, website12,
wallet-read SQL60 and terms SQL9 pass. Six changed Dart implementation files
analyze without issues. No dependency, subscription, payment or machine action.
Receipt: `.campaign-work/home-wallet-20261003/RESULTS.md`.

The follow-up availability refresh UI now fits without a separate status footer;
its48dp icon target and counts retain geometry during refresh. Home's existing
layout uses the recovered space, retaining small-screen/enlarged-text scrolling.
Removed the navigation bar's fixed-height wrapper: Flutter reserves the Android
system inset once. Home33/availability14/navigation22 pass, including gesture and
three-button insets in light/dark at1x/2x; seven changed Dart files analyze cleanly.
Map2 covers retained-controller remount and post-resize camera-event ordering,
fixing the blank tiles seen in the intermediate installed build. Fixture font
and stream-disposal failures are corrected and recorded, not counted as passes.
Final one-worker3GiB build passes2m45s, protected inputs unchanged, installed in
place. Actual Samsung screenshot and refresh bounds confirm a complete card above
navigation, correct$3/Columbus details and rendered map without panning. Device
gesture preferences remain unchanged; three-button coverage is fixture-based.
No iOS rebuild or new website publication in this batch.

October 3 terms refinements COMPLETE. Reused the full static Clean Stream logo,
removed "displayed" from consent, and published `2026-10-03.1` with customer-facing
Stripe/Nayax wording instead of the second-purchase explanation. Other policy
sections, financial behavior and customer consent records remain unchanged.
Follow-up requests pin the agreement controls in Scaffold's reserved bottom
area and add a persistent interactive scrollbar to the document. End padding
keeps the final line clear; no scroll-to-accept requirement was introduced.
Terms SQL9 and focused Flutter57 unique cases pass across the initial suites
and scoped reruns; final seven terms checks cover light/dark, large text,
stationary controls and unobstructed final content. Changed Dart files analyze
cleanly. Final one-worker3GiB Android build2m47s passes, protected inputs unchanged,
and is installed in place on Samsung. Consent remains unchecked; device text
preferences preserved. No iOS rebuild. Evidence:
`.campaign-work/loyalty-terms-branding-20261003/RESULTS.md`.

October 2 local / October 3 UTC terms-formatting refinement COMPLETE. Reviewed
Apple and Stripe legal layouts; changed only the shared document renderer and
terms-page presentation, reusing existing Material/intl. Compact navigation,
22/16/14/12px hierarchy, human-readable date, subdued metadata/rules, consistent
paragraph spacing and an8px-radius48px-minimum action replace the initial layout.
No policy content/version, controller, server or consent changes. Device bold
text/scaling remain intact. Focused196 unique cases accepted across the run and
targeted fixture/color reruns; final six layout/contrast checks and four-file
analysis pass. Initial device review caught black fallback color tokens; final
alpha-composited colors are corrected. Final Android build2m49s passes, protected
inputs unchanged, installed in place on Samsung. Actual top and agreement-area
screenshots reviewed; consent remains unchecked. iOS not rerun. Receipt:
`.campaign-work/loyalty-terms-formatting-20261002/RESULTS.md`.

October 2 server-managed terms and Samsung delivery COMPLETE. Version
`2026-10-02.1` is published as JSON in Clean Stream Supabase. The app loads it
automatically, formats selectable legal sections and records explicit versioned
consent. A changed publication rejects stale agreement. Actual Samsung install
preserves app data and displays the server document; scrolling reaches an
unchecked checkbox and disabled-until-checked submit button. No customer terms
were accepted. Current device bold-text accessibility preference is preserved.
Existing admission/services were reused; no dependency, subscription or reward
arithmetic was added. Terms publication: [guide](loyalty-terms.md).

Paid-credit preservation SQL is deployed with its three missing prerequisites
in one atomic four-migration rollout. Purchased credit survives account deletion;
only free promo/reward progress is canceled on final retirement. All twelve
financial references now use retained subjects. The guarded cleanup worker,
dedicated Vault/Edge credential and dormant daily scheduler are installed.
Readback confirms reference readiness, worker v1 gateway configuration,
execution=false, forfeiture=false and inactive Cron. **Permanent cleanup is not
operational yet:** hosted Auth/Storage deletion and truthful per-request
hold/media/processor/backup inventories remain agent-owned acceptance work. No
deletion, refund, ledger adjustment or machine test was invoked by this rollout.
Do not ask for the superseded paid-forfeiture approval again.

Focused evidence: model71, admission/legal196, profile62 and load-dialog18 Flutter
cases pass; seven changed Dart files analyze cleanly. Terms SQL8, retention SQL55
(54 child checks plus parent), Deno105 and website public-page12 pass. Independent
review found one publication lock race, corrected with a regression, and an old
final-sale notice, corrected with its test. Final one-worker3GiB Android release
build passes in2m49s with protected inputs unchanged; installed on Samsung.
Website privacy/deletion wording is aligned locally, not newly published.
Receipt/screenshots: `.campaign-work/loyalty-terms-20261002/RESULTS.md`.

October 2 native Google sign-in correction: Owner clarified the requested UI is
the native account chooser used by Gundex, not branding or browser account selection.
Read Gundex's Google service only; no Gundex files/settings changed. Added pinned
`google_sign_in` 7.2.0 to the existing Supabase service, native ID-token exchange,
quiet cancellation, duplicate-tap prevention and sanitized UI failure reporting.
Browser OAuth remains only on web/unsupported desktop platforms. Six plugin
dependencies resolved without other version changes; iOS pods installed.
Approved Android development and iOS clients were created in the existing
`clean-stream-laundry` Google project and added to Clean Stream Supabase's Google
client list, retaining the web client first. Secret, nonce/email checks, logo,
billing and Firebase projects unchanged. Local iOS client/URL keys are configured.
Independent source review found and resolved a late Google session-adoption
race: native exchange is isolated; current-attempt/account guards precede adoption;
same-user adoption reuses the pinned SDK's guarded refresh to persist/notify.
The final native suite passes22 cases, alongside89 unchanged focused Auth/login
cases from the105-case preceding run. Earlier legal/profile copy checks also pass.
Scoped analysis has no errors/warnings and nine existing informational diagnostics.
Source review is accepted and closed. The user-requested Samsung update is
INSTALLED in place, preserving app data. After regenerating release plugin
registration, the existing one-worker3GiB wrapper passed in3m7s with protected
inputs unchanged. Actual Samsung startup reaches loyalty-term review, not forced
personal-account MFA. Sign in again reaches Login; Google opens Android's native
"Choose an account" dialog for "Clean Stream Laundry". Cancellation returns to
Login with Google enabled. No account selected, no terms accepted, no funds used.
Complete native token exchange with a real selected account and iOS runtime remain
distinct unrun checks. Receipt: `.campaign-work/samsung-google-native-20261002/RESULTS.md`.

October 2 development role correction COMPLETE, explicitly requested without
waiting for business MFA setup: `jamaki12345@gmail.com` is now `User` and
`jacob@cleanstreamlaundry.com` is `Owner`. The business Auth account already
existed and was verified; only its missing profile was created with normal
defaults, then promoted. One locked transaction temporarily disabled only the
last-Owner removal trigger and restored it before commit; existing authority,
recovery, policy and role-audit triggers remained active. The exact role readback
and enabled guard state are confirmed (CLI result d0c62da9). The personal profile's
other fields were asserted unchanged. No sessions, factors, terms acceptance,
balances, memberships or other accounts were modified. Two normal role-audit
events plus an explicit trusted-operator correction receipt were recorded.
Execution SQL: `.campaign-work/owner-role-correction-20261002.sql`.
Y14 is resolved. Owner login still uses existing MFA, not a prerequisite to this
approved operator correction. The user has now requested the new Samsung build.

The earlier October 2 deletion-forfeiture decision and its115-case copy receipt
are superseded by the paid-credit preservation checkpoint above. The 30-day
restoration window remains, but purchased credit has no automatic expiry or
forfeiture. Current business policy: `docs/retention.md`.

October 2 user-reported Samsung entry issue: existing app data/session was preserved
by the requested in-place install. Actual device shows required MFA enrollment,
not a signed-out first-run screen; no factor was enrolled or account role changed.
The required-MFA page lacked a return to Login. Local correction adds that route
and displays the current session email, reusing admission invalidation without
granting access, logging out other devices or changing backend MFA requirements.
48 focused MFA/gate/loading cases and four-file analysis pass; independent
source review found no blocking issue. Android rebuild succeeds with no protected
input changes. Updated test-signed release is installed in place on the Samsung;
the actual visible Back to login action now reaches Log In/Create Account.
No sign-out or first-launch policy change: the pre-existing session remains stored,
so a later cold start may still require MFA for that account. New/signed-out
customers already route to Login; customer enrollment remains optional except
the separately approved recovery path. Receipt:
`.campaign-work/samsung-login-20261002/RESULTS.md`.

Current scope decisions: no promotional emails, no mailing-address request;
necessary transactional messages continue and optional informational wording must
respect existing consent. Geocode-provider login is no longer assigned: replace
the active location form's automatic lookup with validated entered coordinates.
The two-file website correction passes40 focused cases; it is local and NOT
published. Customer map/listing/marker code and saved locations are untouched.
The user clarified that showing laundromat locations is the map's purpose;
coordinate entry is solely an admin setup alternative, not a customer requirement.
The Owner has submitted the Lynx access request and accepts Nayax event delivery;
do not confuse that with permission to restore Supabase Realtime.

Stage 3: scoped verification and correction. Earlier implementation/setup is
agent-actionable complete only with external dependencies still assigned in
[the current queue](../APP_FIX_PRIORITIES.md#current-work-order). The whole campaign
is not release-ready. Do not reopen accepted unchanged suites or package discovery.

User clarification: distinguish implemented features from remaining setup and
verification; do not let verification expand into an apparent implementation
backlog. Composer stopped the additional native Home/Wallet refresh check after
online baselines, without a finding or acceptance claim. Emulator/app stopped,
original network state restored and reviewer closed; QA session remains stored.
Receipt: `.campaign-work/home-wallet-refresh-20261002/RESULTS.md`. Keep subsequent
work tied to a concrete unfinished requirement or supplied external input.

Current cached Android release invocation: existing `android-16kb-20261001/build-release.mjs`
with `--heap-gib=3 --progress` and a fresh lane output directory, offline and one
worker. Do not fall back to its default2GiB: the October2 Auth-link batch spent
273 seconds in full GC and was deliberately stopped, exit143. Both owned JVMs
were confirmed absent before retry. No global Gradle or machine settings changed.

Latest completed verification batch: hosted public checkout now passes12 actual
Chrome mobile/touch observations at320/390 widths: correct washer quote,
Support/Privacy/Terms links, missing-machine refusal and safe incomplete return.
No overflow, broken images, page errors or unexpected network calls; payment,
status, Auth and WebSocket routes blocked, no Pay activation. No product edits,
build or deployment. Initial harness CSS-case/favicon mismatch retained, corrected
run exits0 and isolated browser closed. Independent review accepts all12
screenshots, request evidence and the corrected harness without a blocking finding.
Receipt: `.campaign-work/hosted-pay-20261002/RESULTS.md#hosted-mobile-completion`.

Previous completed implementation/runtime batch: actual Android camera scanning
exposed and now verifies the corrected checkout Auth replay failure. The
eleven-line initial-session guard preserves replacement/recovery invalidation;
147 unique affected tests, scoped analysis and independent source review pass.
Both unsigned releases build without protected input changes. Actual16KB Android
file-camera scans twice reach the hosted Washer1/12kg/$4.00 quote; Start's three
action tiles expose native buttons. QA account signed out, temporary camera and
emulator networking restored, owned runtimes stopped; caffeinate remains. No
payments or machine operations. Independent source/visual/evidence QA accepts
this bounded batch; physical cameras, iOS scanner runtime and signing remain distinct.
Evidence:
`.campaign-work/native-scanner-20261002/RESULTS.md`.

Previous completed batch: matched welcome webhook redelivery passes on the real
provider: attempts1->2, HTTP200, exactly-one welcome/send and unchanged complete
outbox/event fingerprints. No email resent or settings changed. Two isolated
Resend test-recipient account approvals are pending for bounce/complaint checks;
no fixture users created. Backend reviewer closed, owned Chrome tabs closed.
Receipt: `.campaign-work/mail-provider-acceptance-20261002/RESULTS.md`.

Previous completed batch: hosted checkout missing/unknown-machine refusal,
split return scrubbing/reload, actual $4.00 washer quote, desktop layout/keyboard
focus and support navigation. Focused checkout tests now cover all six dryer
choices by pointer/keyboard and rejected quotes:28/28 pass, scoped lint clean.
Only one washer is configured remotely; no hosted dryer claim. Valid payment
returns were excluded because status may reconcile/compensate; no financial or
machine operation. Chrome viewport override did not apply, so no new hosted
mobile claim. Owned tabs closed, override reset, test runtime released.
Receipt: `.campaign-work/hosted-pay-20261002/RESULTS.md`.

Previous completed batch: Android native saved-theme synchronization and
initial-only branded admission loading pass8 branding/172 admission checks,
clean analysis, both unsigned releases and actual Android36.1 four-pair cold
starts/real toggles. QA account signed out, settings restored, emulator/build
workers absent; requested caffeinate remains. Independent QA accepts the bounded
source/runtime/cleanup evidence in `.campaign-work/android-startup-themes-20261002/QA.md`;
feature and QA lanes are closed. No global no-flash, offline or pre31 claim.
Receipt: `.campaign-work/android-startup-themes-20261002/RESULTS.md`.
Genuine iOS offline transport is assigned to physical-device Y9: reviewed
Simulator sandbox approach is unsupported and was not executed. Preserve accepted
cached-policy checks; see `.campaign-work/ios-offline-scope-20261002/PROPOSAL.md`.

### Latest Completed Batch

- iOS actual FIAM provider delivery/dismissal now passes in the unchanged customer
  Debug simulator: one Dev-console test target, exact title/body, native Close
  and original underlying screen. Actual UI consent restored off, push untouched;
  temporary local public policy/debug logging restored, app/log helpers absent
  and simulator Shutdown. No login, publication or product edit. Independent
  QA accepts delivery/dismissal/cleanup in lane QA.md; no duplicate runtime run.
  Receipt: `.campaign-work/ios-message-delivery-20261002/RESULTS.md`.
- Android actual FIAM delivery now passes: Dev-console Test-on-Device to one QA
  installation, real opt-in, restarted customer Release PID4228, service fetch of
  one message, exact modal and normal dismissal to Home. Dev console also shows
  Analytics activity for both platforms. No campaign publication; Test auto-saves
  an inactive Draft. Consent off/sign-out/network restoration complete; emulator
  session70366 exits0 and hostPID27214 absent. Concrete SDK dismiss accessibility
  defect is fixed with two resources; cached Android Release passes. Exact
  rebuilt SDK modal now passes accessible name,48dp bounds and real enlarged-area
  dismissal in portrait/landscape through an offline synthetic fixture. This is
  separate from provider delivery: its rebuilt provider retest did not render.
  Final fixture/emulator cleanup exits0 with no timeout/protected drift, optional
  consent off and QA signed out; the earlier timed-out attempts are not passes.
  Independent QA accepts successful runtime, visuals and cleanup in lane QA.md;
  both feature and QA lanes are closed. Diagnostic fixture is retired until its
  documented failure-path cleanup is hardened before any future reuse. Receipt:
  `.campaign-work/firebase-message-delivery-20261002/RESULTS.md`.
- iOS native saved-theme bridge now passes composer runtime acceptance: opposite
  OS-theme cold starts reach matching retained native splash/Flutter Login and
  actual Settings toggles agree with persisted preference/native window in both
  directions. One product file, existing preference reused, no dependency/channel/
  timer. Debug and unsigned iOS Release pass with protected inputs unchanged;
  Release session88792 exits0 in22 s. Independent source/receipt/visual QA accepts
  this scoped bridge; Android/physical devices and OS-owned snapshots are excluded.
  Existing OS-owned initial snapshot and engine splash fade remain, not a claim
  of no color transition across every native launch. Original absent theme/light
  OS restored, QA signed out, both app PIDs absent, simulator Shutdown.
  Receipt: `.campaign-work/native-startup-themes-20261002/RESULTS.md`.
- Actual Android password recovery now passes request -> real branded Outlook
  delivery -> real six-digit verification -> empty new-password form, using only
  the approved support QA account. No password submitted; final credential entry
  is user-assisted (Y16). Account signed out and emulator stopped, session9613
  exit0/PID18734 absent. Corrected two misleading "reset link" strings to code
  wording; composer-reviewed feature-agent diff and22 nearest page tests pass.
  No service/router/dependency change in that label batch. The newer iOS theme
  build includes these labels, as does the later Android FIAM resource build.
  No standalone copy-only rebuild was needed. Receipt:
  `.campaign-work/password-recovery-20261002/RESULTS.md`.
- Android FIAM in-memory suppression is accepted in the unchanged current
  release: opt-in, messages-only revocation, Analytics revocation and new-process
  restart.105 native reads,0 errors; both bounded sessions exit0. Independent
  source and receipt QA accepted. PID4225 was absent before restartPID4649.
  Actual UI consent restored off/push untouched; account signed out, diagnostic
  package removed, original offline network settings restored. Emulator9489
  exits0, hostPID16768 absent. Release/mapping/driver hashes unchanged; no product
  edit or rebuild. Actual message/push delivery remains separate. Receipt:
  `.campaign-work/android-fiam-runtime-20261002/RESULTS.md`.
- Native iOS Auth-link checks found and fixed plain recovery-link lifetime
  suppression. Four changed runtime lines, sixteen added test lines,128 affected
  routing cases and clean scoped analysis pass; independent source QA accepted.
  Actual rebuilt iOS verification link now reopens after Back to Login (147-150,
  PID13518). Cold/warm cancellation and unknown-host rejection also pass. Google
  reaches the correct provider sign-in page only; no credentials/consent submitted.
  Android exact-release derivative also passes cold verification/reopening,
  cold-query and warm-query/fragment cancellation and unknown-host OS refusal
  (PID3164 ->3422). No account/password/MFA/backend mutation. Both simulators
  stopped and agent closed. Unsigned releases refreshed: Android137 seconds,
  iOS21 seconds, protected inputs unchanged. APK adf6762717cf; QA derivative
  05757f8a01e3 preserves1520 payload entries. iOS App binary fa6be37661e5.
  Receipt: `.campaign-work/native-auth-links-20261002/RESULTS.md`.
- Cortina late-shutdown race reproduced, fixed with one runtime line and deployed
  to development version59.88 unique affected cases accepted across scoped runs;
  stale capacity/status fixtures corrected without relaxing production guards.
  All11 official deployed-source readbacks match, gateway false unchanged.
  No payment/machine operation. Hosted pause/restore rehearsal requested (Y15).
  Receipt: `.campaign-work/shutdown-dispatch-20261002/RESULTS.md`.
- Actual iOS FIAM in-memory suppression/collection getters pass explicit opt-in,
  messages-only revocation, Analytics revocation and real process restart.
  Consent restored off; debugger detached and simulator stopped. No hosted
  campaign or delivery claim. Receipt: `.campaign-work/ios-fiam-runtime-20261002/RESULTS.md`.
- Actual iOS cached release controls pass: blocked-build restart/retry,
  maintenance precedence/privacy, valid minimum/equality boundaries and
  accessible recommendation dismissal. Original public caches restored;
  simulator stopped. No hosted policy or product source changes. Genuine
  offline transport and backend shutdown remain, not repeat cached-policy QA.
  Receipt: `.campaign-work/ios-release-controls-20261002/RESULTS.md`.
- Actual Android offline release gates pass: matching/nonmatching builds,
  minimum-version boundaries, maintenance/privacy, restart/retry/resume retention.
  Found and fixed hidden recommendation semantics and missing root Tooltip
  ancestors with two narrow existing-widget changes.56 focused cases pass;
  native Dismiss and hard-gate exclusion now pass in the updated release.
  Scoped analysis:0 errors/0 warnings/2 existing test-import infos, not exit0.
  Native ad-storage/user-data/personalization denial also passes with analytics
  off/on/revoked and after restart. Receipt:
  `.campaign-work/native-release-policy-20261002/RESULTS.md`.
- Actual Android customer Release: native Analytics/FIAM consent and app settings
  agree across five states and two process restarts; optional consent returned
  off, push stayed off. QA signed out, emulator offline/unrooted and stopped.
  Receipt: `.campaign-work/android-firebase-20261002/RESULTS.md`.
- Actual iOS Debug identifies APNs unavailability behind the cleanup warning.
  A separate fresh-opt-in registration defect is now fixed in the existing driver:
  temporary opt-in-only registration, bounded token wait, guaranteed cleanup
  attempt.13 SDK/channel/integration cases plus7 related race/store cases pass.
  Independent QA's deletion acknowledgment finding was reproduced and fixed;
  pending cleanup now survives failure, restoration and restart.36 related cases
  pass. Scoped analysis clean. Receipt:
  `.campaign-work/ios-push-optin-20261002/RESULTS.md` and its `QA.md`.
- Settings notification lead-time names are confirmed in actual iOS accessibility.
  Tappable row button roles are also corrected locally with46 widget/page cases
  and clean analysis; actual rebuilt iOS row roles, Newsletter semantic tap and
  Sign Out confirmation/empty Login now pass.
  Receipt: `.campaign-work/acceptance-closeout-20261002/settings-button-roles.md`.
- Prior unsigned Android/iOS releases included the preceding fixes:171/21-second
  serial cached builds, protected inputs unchanged. Android manifest/resources
  unchanged,29 native libraries with only Dart libapp changed,16KB ZIP alignment
  passes. iOS identity/floor/dev config/defaults/native framework checked.
  Receipts: native-release-policy-20261002/{android-release,ios-release}.
  iOS native Settings roles and cached restrictive-policy UI are now accepted;
  genuine offline transport is not established.
  The Auth-link batch above supersedes these artifacts without changing native
  dependencies or protected configuration; do not rebuild again without changes.

### Retain Prior Acceptance

Login transition/sign-out/native customer smoke; Home/Wallet compact refresh;
compatible dependency and native storage upgrades; website publication and scoped
browser checks remain accepted. Payment database races and native pending-page
restart/claim-only/lock/scoped-clear checks are closed; dryer contrast is fixed.
Delivered email logo works after Outlook's per-message image unblock. iOS SDK
consent and native nonblocking policy cache are accepted, not a fresh fetch claim.
Relevant receipts are linked in APP_FIX_PRIORITIES.md; consult only the boundary
being changed, not this document's full history.

The Android accessibility build and bounded native check above have completed;
both QA simulators are shut
down and accounts signed out. Android policy/consent restored, diagnostic root
removed. Requested caffeinate39385 remains. No real payments,
machine starts, push sends/permissions, MFA mutations, destructive rollout,
billing, key retirement or Gundex changes occurred. The single approved
development endpoint update is recorded above. QA-only TOTP
approval remains unanswered. Physical push/signing remains Y9; other inputs and
unverified flows remain in the sole queue below.

## Evidence History

The dated receipts below preserve earlier states and failures. Current Checkpoint
and Remaining Work supersede old pending/build/deployment wording; consult only
the receipt relevant to changed inputs, not this entire history on each resume.

**Newsletter availability correction accepted:** hosted QA found that the
Flutter status read uses SQL's transactional-mail flag, bypassing the existing
Edge postal/configuration gate. Requests already use that gate. Rawls prepared a
reviewed, two-file candidate in `.campaign-work/newsletter-status-20261001/`:
reuse the existing Edge path for all three actions and preserve identity guards.
Edge permits withdrawal while sending is unavailable; retaining SQL-only
withdrawal would reintroduce the incorrect availability flag in its response.
No schema, deployment, dependency or newsletter activation change. Composer
accepted the source delta; all88 affected service/controller/page cases pass and
both changed files have clean analysis. The rebuilt Android app also shows the
correct disabled enrollment state without a consent mutation. Initial sandbox loopback denial is
retained, not counted as test execution. Runtime checks are finished.
Hosted comparison receipt: `.campaign-work/hosted-auth-20261001/newsletter-status-comparison.json`.
Acceptance: `.campaign-work/newsletter-status-20261001/RESULTS.md`.

**Native preferences/path upgrade accepted:** actual process restarts and in-place
baseline-to-candidate upgrades pass on Android16/16KB and iOS26.2 Simulator.
Theme, consent, cached release blocks and files persist; privacy cleanup persists
without deleting unrelated state. The exact Android release payload also passes
Login -> Home -> zero-balance Wallet with optional permissions/collection denied.
Sign-out initially reached an admission fallback instead of Login. The actual
router regression reproduces that failure, and the bounded Settings fix now passes
all59 affected route/settings cases and clean scoped analysis. It survives page
disposal while preserving a newer account's route. Updated Android Release passes
in171 seconds; the exact QA-signed payload then returns directly to Login after
sign-out and remains there across an actual process restart (3426 ->4367).
This closes the observed navigation/persistence gap for the development emulator.
Both devices and all owned native processes are stopped. Receipt:
`.campaign-work/preferences-path-native-20261001/RESULTS.md`.
Fix and updated-artifact evidence: `.campaign-work/signout-redirect-20261001/RESULTS.md`.

**Home/Wallet compact refresh accepted locally:** three narrow layout fixes reuse
the existing enlarged-text threshold/scroll path; no controller, payment or
dependency changes. Four new light/dark360x800/2x cases retain content through
delayed/offline reads and explicit retry. All133 cases across the five affected
files pass, including those four; scoped analysis is clean. Independent source QA
finds no blocking issue. Twelve optional captures document the principal content,
not complete font/map/device acceptance. Earlier release binaries predate these
layout edits. Receipt: `.campaign-work/home-wallet-acceptance-20261001/RESULTS.md`.

**27-node dependency batch integrated:** the five mobile implementations,15 Dart
utilities and seven path/permission updates are now one reviewed lock delta.
Independent QA accepts the source; isolated resolution and active offline metadata
refresh pass without drift. Focused checks pass577 unique cases:569 initially,
then the eight notification fixtures with their required synthetic CI defines.
The initial missing-configuration failure remains recorded. Analysis:0 errors/
0 warnings/106 infos versus104 in the recorded prior baseline. No app source,
direct Auth/payment pins, SDK floors or permissions changed in this dependency
batch. Native checks remain; do not reuse older binaries as proof of these updates.
Receipt: `.campaign-work/dependency-closure-20261001/INTEGRATED.md`.

**Native closure integrated:** independent source QA, exact pinned resolution and
active offline metadata refresh pass for the JNI/FFI path-provider closure. Its
92 focused VM cases pass; analysis remains0 errors/0 warnings/106 infos. Initial
sandbox DNS/socket failures remain recorded. The final package-info10.2.2 patch
is also integrated and its enforced-lock metadata refresh passes. Scoped pod
refresh removes the obsolete Foundation pod and updates permission9.4.8 while
preserving all43 other checksums. Normal iOS release configuration passes; Pub's
canonical quote-only lock rewrite was reviewed with full structural equality. No
permission, application API or protected Auth/payment behavior changed. Receipt:
`.campaign-work/native-path-closure-20261001/INTEGRATED.md`.

**Website dependency acceptance passes:** exact install and five-file Auth patch
verification,9 installer cases, strict types, lint, build,1045 UI cases across67
files, and26 serial desktop/mobile browser cases pass on Node24. A narrow Owner
helper fix retains ASCII-control rejection without a lint-forbidden regex;6 Node
cases pass, including every OS-passable ASCII control. No SQL/role/network change.
Full and runtime-only final lock audits both exit0 with zero advisories. Original
runner-config and lint failures remain recorded; accepted earlier steps were not
replayed. Receipt:
`.campaign-work/web-compatible-update-20261001/qa/ACCEPTANCE-RESULT.md`.
The124-file reviewed source snapshot is now published as
`dpl_EV3NWG1WLrt7qq6sMvFFoEDzfnUE`, READY on the public development domain.
Cloud build verifies the five-file Auth patch. Eleven route/association and two
entry-asset HTTP checks pass; association JSON matches source. No billing or Git
push. Receipt: `.campaign-work/website-release/dependency-publication-http.json`.

**Updated native releases pass:** unsigned iOS Release takes140 seconds; Android
Release takes158 seconds with lint, R8 and shrinking enabled. Both preserve
protected inputs. Android's invocation-only3GiB heap resolves the observed2GiB
R8 GC stall; one worker/active processor and512MiB Flutter remain. Earlier timeout
and deliberate-stop receipts are retained. The new APK preserves permissions,
Dev Firebase/consent defaults and public config. Its three new JNI ABI libraries
have no listed alignment failures; all26 prior inspector records, including13
known RELRO flags, are unchanged. This is not full16KB/device/signing acceptance.
Receipt: `.campaign-work/native-path-closure-20261001/android-3g/RESULT.md`.

**Earlier closed assignment:** This QA/fix batch is complete. Rawls and Plato are closed;
all composer commands are terminal, devices shut down and the runtime slot free.
The user-requested caffeinate remains. Latest Android evidence covers both Dart
fixes; the accepted iOS binary predates them. No duplicated dependency audit or
financial test campaign was opened.
Hosted support
QA is complete for signup/code, welcome, terms,
deletion/restoration and actual inbox/webhook checks. The account stays restored,
unprivileged, with no funds or newsletter consent. No concurrent native
build/emulator is authorized. The app/web entry guides are
now about60% shorter; detailed required lessons moved into one shared reference
after source/disposition/link review.

Fresh read-only npm/pinned-Flutter discovery completed20:42UTC with unchanged
manifest/lock hashes, no install or scripts: `.campaign-work/dependency-closure-20261001/`.
The earlier REMAINING.md is historical; `flutter-outdated.json` and
`website-outdated.json` plus their receipts now establish available candidates.
Npm exit1 denotes reported outdated versions, not an install failure. Availability
still does not establish native compatibility. Final source disposition now covers
all84 saved Flutter entries in `.campaign-work/flutter-final-dependency-disposition-20261001/`:
package-info receives one final compatible patch; constrained framework versions,
coupled map majors and desktop/browser-only changes stay explicitly deferred.
Do not restart discovery or expand this release to chase every registry version.
Website/native runtime acceptance remains distinct from source integration.

**Completed dependency lanes:** Supabase2.18.0/core2.16.2/storage2.8.1 are integrated;
156 focused startup/Auth cases pass, including the new two-case no-channel
lifecycle guard. Final fixture analysis is clean; Auth/Realtime transport and
native dependencies are unchanged. Nash's independent source review passes,
without repeating tests. Receipt: `.campaign-work/startup-package-review-20261001/INTEGRATED.md`.
Map8.3.2/scanner7.4.2/image-picker1.2.3 are integrated after245 author passes and
Nash's independent ACCEPT. Orphan logger removed. Combined active enforced-lock
metadata refresh passes(f39a28). Pod refresh preserves all locked nodes; unsigned
iOS scanner compile, Android scanner compile/app AAR metadata and resolved native
graph checks pass. CameraX1.6.1 still fails the documented surface-library RELRO
criterion on both64-bit ABIs; do not claim16KB release acceptance.
Receipt: `.campaign-work/location-media-update-20261001/INTEGRATED.md`.
Franklin's nine library/tool pins plus required archive4.3.0 are integrated after
independent source/evidence acceptance. Active57 tests pass, including all11
new fixtures; final scoped analysis is clean. Existing app source/native graph
unchanged. Receipt: `.campaign-work/library-update-20261001/INTEGRATED.md`.
GoRouter17.5.0 is now integrated: three manifest/lock substitutions, one updated
node, no app/native changes. Author294VM/53Chrome cases and independent source
review are accepted; active offline enforced-lock metadata refresh passes with
unchanged candidate hashes. The disclosed pinned Web SDK cache fill was reviewed;
that Chrome run was not wholly offline. Receipt:
`.campaign-work/router-update-20261001/INTEGRATED.md`.
Composer completed a bounded isolated Android16KB baseline: actual page size16384,
compatibility fallback disabled, existing Dev Debug APK installs and reaches Login.
This older binary does not prove current release/scanner acceptance or close RELRO
findings. The emulator stopped at its240-second cap; no owned runtime remains.
Receipt: `.campaign-work/android-16kb-20261001/BASELINE.md`.
Package-info10.2.1/storage11.2.0/geolocation14.1.1 are integrated together:
13 updated nodes,5 required additions,197 unchanged. Active locked resolution,
189 unique VM cases,15 Node checks,6 branding checks and independent QA pass.
Analysis has0 errors/warnings and104 baseline infos; the two changed Dart tests
have clean scoped analysis. A test-only splash correction verifies existing bitmap
colors rather than changing working assets. Foreground-only location is preserved.
Receipt: `.campaign-work/platform-package-update-20261001/INTEGRATED.md`.
**Android release checkpoint complete:** current unsigned Dev release passes
with lint/shrinking enabled, one worker and unchanged package/native versions.
Release-cache and generated-plugin-registration issues were corrected without
app behavior changes. The final artifact excludes three unnecessary advertising
permissions plus background/location-service permissions; five Firebase optional
collection defaults remain false. The two-file permission fix retains16 passing
Node checks. Bundled public config matches reviewed source.
Receipt: `.campaign-work/android-16kb-20261001/RELEASE-RESULT.md`.
Actual release inspection inventories26 libraries,18 evaluated64-bit libraries:
ZIP and LOAD checks pass;13 documented RELRO endpoint findings remain open.
Independent static triage now classifies those13 as published-checklist warnings,
not demonstrated runtime failures: the saved layouts have no rounded-RELRO collision
with writable data. No dependency replacement or weakened protection is justified
by those flags alone. Keep the original report and the guide discrepancy explicit;
integrated native-path execution on the exact artifact remains a separate gate.
Receipt: `.campaign-work/android-16kb-20261001/ALIGNMENT-TRIAGE.md`.
The exact CameraX ARM64 surface JNI probe passes3/3 on actual16KB pages with
compatibility disabled and read-only RELRO protections observed; independent QA
accepts only that narrow result, not full scanner/x86_64 or other-library safety.
Receipt: `.campaign-work/scanner-alignment-20261001/probe/RESULT.md`.
**Current iOS release also passes:** standard config/pod refresh changes only the
secure-storage pod checksum; all native versions and other tracked inputs remain
unchanged. The full unsigned device Release exits0 in137 seconds with one build
job. Actual artifact retains the app identity, iOS15 floor, Dev Firebase selection,
five optional-collection defaults off, expected native frameworks, privacy resources
and matching bundled public config. Receipt:
`.campaign-work/ios-release-20261001/RESULT.md`.
**Native pending-record checkpoint:** the unchanged store and real secure-storage
plugin pass six phases on Android16/16KB and iOS26.2 Simulator, with three actual
process restarts per platform. Attached records survive; project/account/machine/
guest scopes remain separate; scoped deletion persists. Android runs with networking
and compatibility fallback off. The first unsigned iOS attempt failed; Xcode-managed
simulator ad-hoc signing fixes the test setup without product changes. Physical-device
security, claim-only restart and full lost-response payment recovery remain distinct.
Receipt: `.campaign-work/pending-native-probe-20261001/RESULTS.md`.
All composer build/emulator sessions exited; user-requested caffeinate remains.
Einstein's preparation and Raman's independent saved-evidence QA are complete;
both agents are closed. Android and corrected iOS evidence are accepted within
the isolated protocol's stated limits; no duplicate execution was needed.
Signing, full feature/device acceptance and Android static findings remain open.
No cloud changes, key retirement or new retention approval occurred.

**Hosted Auth and app delivery accepted for the support QA flow:** actual signup
confirmation arrives in Outlook and its code succeeds. One scheduled welcome and
one restoration notice arrive, each delivered once with correlated sent/delivered
events. Prompt restoration suppresses the stale deletion notice before dispatch.
Terms timestamp survives password login/restoration; login alone does not restore
or extend the30-day deadline. Prior JWT admission is restricted during deletion;
the restored zero-balance customer is denied admin identity with403. The harness's
too-narrow post-restore newsletter expectation is corrected to the existing
suppressed state; read-only continuation passes without replaying mutations.
Receipt: `.campaign-work/hosted-auth-20261001/RESULTS.md`. This is not Flutter UI,
OAuth/MFA, funded-wallet isolation, all-template or permanent-cleanup acceptance.

Earlier controlled provider test: one approved
Resend draft-template test reached the `support@cleanstreamlaundry.com` mail server
at16:34 UTC; provider ID `01a0f851-75f0-73b9-bbd9-99ae21519bdb` is delivered.
The signed sent/delivered callbacks returned503 because this console test has no
matching app outbox entry. Deployed SQL deliberately retries unmatched evidence;
no guard, record, key or role was altered to force a pass. The unpublished draft
is diagnostic only; the later real-account sequence supplies independent app
delivery evidence. See [email](email.md#controlled-provider-delivery-check).

**Stripe package batch complete locally:** native13.0.0/web8.0.0 integrated;
six Pub upgrades,205 nodes and runtime payment code unchanged. Later SDK releases
require Flutter3.41.0, above the pinned floor. Independent source QA accepts the
author179-case batch; composer closes its cancellation-assertion gap with one
additional case. Final active12-case fixture and its clean analysis pass;
180 unique cases across retained/final runs, not a sum of repeated executions.
Active offline enforced-lock metadata refresh passes. Stripe iOS25.15.0 resolves
and compiles unsigned; only Stripe-family pod checksums change, with required
StripeIssuing added. Android23.9.2 compiles and app AAR metadata passes using the
existing toolchain. No real payment, simulator, device or signed release claim.
Both agents and all owned processes exited; runtime slot free. Receipt:
`.campaign-work/stripe-update-20261001/INTEGRATED.md`.

**Notification package batch complete locally:** six reviewed source/lock postimages
integrated. Notifications22.3.1, permissions12.0.3 and timezone0.11.1 reuse the
current service. Permissions13 requires compile37 and is not forced into this
compile36 app. Nine author cases plus fifteen independent cases pass; the seven
real-plugin cases are now retained in the app tests, with unchanged bytes. The
eight other QA cases use actual notification/router/admission wiring. Active pub
metadata refresh and enforced-lock resolution pass; scoped active analysis has
no issues. Pod resolution changes only the notification checksum; unsigned iOS
plugin and offline Android notification/permission plugin compiles pass. Android
app AAR metadata acceptance also passes. No simulator/full signed release/device
delivery claim. That batch's agents and owned processes exited; current runtime
ownership is recorded above.
Receipt: `.campaign-work/notification-update-20261001/INTEGRATED.md`.

**Website activation wording fixed and published:** deletion resource no longer
labels the enabled request/recovery flow inactive. Privacy draft correctly separates
enabled transactional mail from postal-dependent newsletters. Twelve public-page
tests and scoped zero-warning lint pass. Only these two runtime files changed in
the existing124-file upload snapshot. Vercel deployment
`dpl_ETLphbSywxainWVqUAG7jpEvuzjC` finished READY and aliased to the public domain
(682e55); Chrome confirms both corrected passages. Draft retention/terms remain
unapproved. No Git push, billing, credentials, customer data or Gundex change.

**Bounded hosted acceptance:** Home at1512/390px, location/support/privacy/terms/
deletion links, deletion reload, safe missing-machine pay state, invalid newsletter
entry, deliberate404/support recovery and signed-out transactions redirect to
`/admin` observed. Mobile admin renders without overflow; measured public pages
and logo assets also fit/load. Seven public GETs (0fa720) confirm HTTPS/www redirects,
pay no-store, protected-route noindex/security headers and both exact association
JSON files. This does not prove authenticated admin, real payment, mobile link
association, full accessibility or inbox/device delivery. Browser overrides reset
and review tabs closed. Retention approval and Y7/Y8/Y14 remain as last clarified;
no approval inferred from automatic continuation.

**Stage 3 begun:** stages 1/2 agent-actionable completion announced; remaining
external inputs stay assigned. The replacement
Owner SQL-generator checks pass5/5, exit0 (f6db6f), no network or role/email action.
The cleanup transport/financial-reference and Firebase privacy QA batches are
complete and their agents are closed. Native plugin integration and cleanup-boundary
acceptance are complete. All owned runtime processes exited; the slot is free.
The Maintenance primary-key defect is closed locally: eight key
regressions, four full-installation/gate checks and five lifecycle checks pass
(17 unique leaf cases, all final runs exit0). Local simulated
Auth/profile removal preserves funded wallet/ledger/transaction/refund/provenance
rows and the retained reward anchor. Restored and stale-request attempts refuse
dispatch. One new fixture alias typo was corrected, not a product-source change.
The same 17 checks now pass from portable repository paths (19 Node results
including parents, session69794 exit0); temporary-path harness rewriting is gone.
Reused `policy-admission-pg.mjs` and `account-cleanup.mjs`; no new dependency.
All SQL clusters/sessions exited and were removed.
This is not hosted deployment, expiry/concurrency acceptance or full purge. Retain earlier evidence
whose inputs did not change; do not restart the broad campaign.

**Worker findings closed:** the checked Deno batch first found TS2322 in inferred
claim-ID assignment, then normalized-calendar-date acceptance. Composer added an
explicit string annotation and reused the existing strict preview timestamp
validator in the executor, removing its weaker duplicate. Exact timestamps and
UUID guards remain. Final four-file run `66f792` passes 84/84 with type-checking,
frozen cached dependencies, no network and a scrubbed environment; independent
source review finds no further issue in that fix. All processes exited.
Accepted source/test details: `.campaign-work/cleanup-qa-20261001/HANDOFF.md`;
portable SQL receipt: `.campaign-work/cleanup-portable-tests-20261001/HANDOFF.md`.
Do not count reruns of the same 17 SQL cases as additional coverage.

**Cleanup transport and financial-reference acceptance complete:** Tesla's 20
enabled-handler tests pass for named/legacy keys, exact version-addressed Storage
and Auth requests, abort/error handling and uncertain acknowledgements. The SQL
batch passes 26 leaves (nine existing plus seventeen new), including every one of
the twelve populated retained FKs, unchanged unrelated-account snapshots and late
funding/refund/reward arithmetic after profile removal. No product defect found.
All processes/clusters exited and were removed; agent closed. With the eight
unchanged key cases, current unique coverage is 34 SQL leaves and 104 worker cases,
not totals inflated by reruns. Receipt: `.campaign-work/cleanup-contract-qa-20261001/HANDOFF.md`.

**Cleanup boundary acceptance complete:** QA exposed SQLSTATE42702 in closed-attachment selection, then in automatic
account selection: query aliases collided with composite variables. Composer
renamed only those aliases in the unapplied migration and inspected neighboring
cleanup functions for the pattern; no predicate, hold, clock or authorization
change. Final39/39 leaves (26 existing plus13 new),40 Node results including parent,
exit0, accept both fixes. Coverage includes restore/dispatch locks, scoped holds,
ninety-day attachments, exact object versions, twelve-month metadata expiry and
unresolved-operation protection. Missing-extension scheduler rejection and no-Cron
disable behavior pass; installed scheduler operation is not covered.
All processes/clusters exited/removed; agent closed. Current unique local coverage:
47 SQL leaves including the8 unchanged key checks,104 worker cases. Receipt:
`.campaign-work/cleanup-boundary-qa-20261001/HANDOFF.md`.

**Next cleanup work:** final financial/provider disposition and Y5; approved hosted
installation, actual scheduler/disable integration and provider compatibility.
Current upstream Storage supports version-addressed removal, but deployed
provider/gateway acceptance remains unestablished. Hosted cleanup remains unapplied;
the tests above do not prove full erasure or authorize irreversible activation.

**Firebase device-erasure local logic accepted:** the official
Installations0.4.4 plugin supplies the deletion API through the existing driver.
Current-subject admission starts device cleanup, clears optional consent, persists
retries and prevents new optional bindings until completion. Restoration does not
restore opt-ins. Exactly three Pub nodes were added; existing versions unchanged.
Offline resolution passed. Independent QA found failed preference writes still
updated the cache; composer moved the durable completion write outside the cache
check. Final focused32/32 pass, exit0, including real FlutterFire fake-channel
dispatch, restart/persistence failures and actual admission wiring. Retain prior
134 nearest passes (126 plus eight requiring synthetic Firebase defines); those
overlap the13 bootstrap cases in the final32 and must not be added as all-new.
Receipt: `.campaign-work/firebase-deletion-qa-20261001/ack-fix-final32.log`.
All QA processes exited. CocoaPods installation passes, with only the plugin and
Firebase/Installations subspec added; every existing pod version/checksum is
unchanged and Manifest.lock matches. Native iOS plugin compile `48f692` and Android
Kotlin compile `9c6bf2` both exit0. Scoped analysis initially found two undeclared
test imports; declaring their existing exact versions as dev dependencies adds no
nodes/version changes. Final scoped analysis `f3eb54` exits0 with no issues.
No new full-app/device or provider run. This is
not closed-app cleanup on other devices or historical Analytics deletion.
Consolidated local implementation/native receipt:
`.campaign-work/firebase-installation-deletion/HANDOFF.md`.

**Postal-split local QA accepted:** 295 active Deno cases plus 14 isolated payload
comparisons, 178 SQL child cases plus six parents. Initial Deno 269 passed but the
combined command exited 1 at an environment-permission loader; only the blocked
credit file reran with the exact synthetic variable permission and passed 26.
Initial sandbox initdb failure likewise had no product failure; identical SQL
passed with local shared-memory access. Seven active test files were integrated;
no runtime/migration change or weakened assertion. All mail QA processes/clusters
exited/removed before cleanup received the slot. Receipt and frozen hashes:
`.campaign-work/mail-qa-20261001/HANDOFF.md`. Actual SMTP/worker inbox delivery
and signed hosted webhook acceptance remain. Read-only Chrome inspection confirms
Auth SMTP is already enabled at Resend465 with existing noreply sender; no password
read/change or email send. Do not reopen SMTP provisioning from stale notes below.
Hosted rejection check `df7045`, exit 0, confirms unauthenticated worker/newsletter
401 and unsigned webhook 400 after activation. No recipient or user identity sent.

**Operations snapshot accepted as an aggregate read, not incident rehearsal:**
`f66dd0`, exit0, `2026-10-01T14:32:03.739322Z`. The CLI returned every section
after replacing multiple SELECT results with one explicit JSON projection.
Mail/new-payment gates are true, mail/refund queues empty, recoverable/expired
pending accounts both zero. Four historical unattributed card sessions remain
`support_required`, with zero due/leased reconciliation entries. Both existing
minute schedulers are active and their latest Cron entries succeeded; that proves
SQL/enqueue completion, not worker/provider delivery. No customer identifiers,
amounts, payloads or credentials were output, and no financial action occurred.

**Hosted configuration/public-key checks passed:** `5441a3`, exit0, confirms
`cortina-vend`58, `cortina-reconcile`4, `mail-delivery`37, `newsletter`37 and
`mail-webhook`36 are ACTIVE with their reviewed `verify_jwt=false` settings.
No endpoint was invoked by that metadata check. `c000e5`, exit0, then used only
the staged mobile/website named publishable keys: both public-policy reads200
with matching content hash; both unauthenticated admission reads401. No accounts,
sessions, emails, financial operations or settings changed. This is narrow
transport/admission evidence, not authenticated-feature or signed-binary acceptance.

**Store disclosure draft refined:** installed iOS manifests and current primary
vendor guides now supply Firebase automatic-data and Stripe declaration facts.
Firebase's published installation-retention limit is 180 days after its deletion
API call; the local device-erasure addition above is accepted for scoped logic/native compilation. Full
processor disposition remains implementation work, not
proof of the draft's 90-day backup target. Final business choices and signed-binary
checks remain in `docs/store-disclosures.md`.

**Stage-2 Owner helper fixed in source:** the website's existing `admin:owner`
command now prints guarded operator SQL only and rejects `--apply`. Removed SDK
connection, credential selection, remote account listing, invitation and reset-mail
paths. Reused the approved operator transaction and installed bootstrap/audit
contract, without restoring API privileges. Runbook corrects initial Owner to
`jake@cleanstreamlaundry.com` and removes the nonexistent onboarding switch.
Five replacement offline checks now pass as recorded above. The website guide records
the new command boundary. No roles/accounts/emails changed.

**DMARC correction complete:** after the user's final deletion approval, GoDaddy
removed only the duplicate `v=DMARC1; p=none;` record for `cleanstreamlaundry.com`.
The saved record list drops from25 to24 and retains only
`v=DMARC1; p=reject; adkim=r; aspf=r; rua=mailto:dmarc_rua@onsecureserver.net;`
at `_dmarc`, with one-hour TTL. No mailbox, MX, SPF, DKIM, other domain or other
DNS record changed. This establishes the saved provider change, not propagation
to every resolver or email delivery. Y6 is complete and removed from assigned inputs.

**Earlier implementation/setup checkpoint (stage 2 subsequently completed):**
External inputs and their dependent unfinished work remain under the assigned list.
No tests, analyzers, builds or functional probes ran in this stage. Cleanup's second
four-file source batch is integrated: ninety-day closed attachments, twelve-month
metadata expiry/compaction and the twelfth retained-subject FK for invitation creators.
No cleanup migration, worker or destructive scheduler has been installed/activated.
Final financial/provider disposition remains input-dependent under Y5, not completed.

**Transactional email enabled independently of newsletter postal details:**
existing queue was empty and database delivery off (297d7d). Migration
`20261001140307_mail_transactional_postal_split` installed (02891a), with one
service-only optional claim filter and no new service/table. `mail-delivery` and
`newsletter` deployed (4a08eb/faa4f4), sender/public-link flags saved (403970), and
the existing scheduler's database gate enabled at `2026-10-01T14:10:00.364071Z`
(3b5337). Sender is `notifications@updates.cleanstreamlaundry.com`; replies remain
`support@cleanstreamlaundry.com`. No backfill or manual test email. Automatic new
eligible events may now send. Missing postal still blocks newsletter claims and
rendering, not account-only notices. Delivery/suppression acceptance stays stage 3.
Candidate and exact later checks: `.campaign-work/mail-transactional-activation/HANDOFF.md`.

**Latest development-activation instruction supersedes testing-only holds.**
Current routing metadata is one sandbox machine configuration; historical20 vend
rows have unknown frozen routing and retain manual-review handling (8105de).
Saved `CORTINA_RECONCILIATION_ENABLED=true` and fixed environment `sandbox`
(31efc3), then activated only `cleanstream-cortina-reconcile` and granted the
guarded public `request_account_deletion()` RPC to authenticated users (028265).
The transaction reports both enabled. Inner helper privileges, identity/MFA/
last-Owner guards and restore requirements are unchanged. No user deletion request,
charge, refund or vend was manually invoked. The scheduled worker may now observe
existing sessions; this is activation, not a functional test. Permanent erasure
is policy-dependent; newsletter delivery lacks the deferred postal address. Neither
is merely waiting for the testing stage. Both agent guides record this distinction.

**Cleanup source integrated:** two local migrations, three worker files and two
dormant scheduler scripts now implement guarded primary removal, scoped holds,
retained financial identities and exact-version media operations. Local gateway
configuration records the dedicated-header contract; no hosted cleanup change.
No new dependency, test, analysis or build. The reference migration is unapplied
and needs separate deployment review because it changes financial FK targets.
The second batch above finishes the ninety-day attachment and cleanup-metadata
expiry source paths. Tax/minimum-record, processor-copy and unknown replay mappings remain
explicit incomplete requirements, not a complete-purge claim.

**Approved website publication completed:** the isolated Clean Stream Vercel CLI
promoted reviewed Preview `dpl_2n5oi4FrRJdJUJuTwo91WF2TirxW`, creating
`dpl_83mKBYEzf16YBukPimvZn1SNBtKw` (45c67e/7aa3cf). Publication finished READY
with aliases `cleanstreamlaundry.com` and `www.cleanstreamlaundry.com` (1529f7).
This is deployment completion, not a website/browser/payment test. No main push,
billing activation, Gundex change or provider transaction occurred. Permission
review initially stopped `cortina-vend` before execution over its explicit
`--no-verify-jwt` option. The user then approved that exact endpoint/configuration;
the same command deployed only the eleven-file `cortina-vend` closure to
`dnuuhupoxjtwqzaqylvb` (ffa498/e3df07, exit 0). No quote, payment, status, wallet or
other test invocation followed. Installed capacity SQL/callbacks were not replayed.
This closes the writer deployment, not stage-3 gateway/provider acceptance.

**Stage-1 setup installed, without functional testing:**

- Machine-column privacy and closed-app reconciliation migrations installed in
  one approved transaction (282a1c). Historical unresolved rows were queued as
  approved, without worker execution or provider activity.
- Dedicated reconciliation credential generated in Vault and transferred in
  memory to Edge; `CORTINA_RECONCILIATION_ENABLED=false` saved (34d17c).
  Worker deployed with its dedicated-bearer contract (3e5335). Cron setup initially
  rolled back on a managed-table lock denial (582db6); replacing that lock with
  shared operator-script advisory coordination required no privilege change.
  Setup then committed the single job inactive (439fbc). The later activation above
  enables its fixed sandbox environment; functional acceptance remains deferred.
- All 24 named keys created through the correct Chrome project catalog. Composer
  saved 21 Edge selectors (80a5ae); local app/web public configuration and Vercel
  Production/Preview now use their respective named public keys (f22f86).
  Vercel required replacing its old Secret-typed public entry as Config, per
  target; earlier failed updates were not successes. Same-source website
  redeployment `dpl_Dw4sqZERapTD88w7yziC2QEPBpZq` is READY with both public domain
  aliases (894533/26f909). This is deployment completion, not an application test.
  Native packaging/testing stays in stage 3. Old/default keys remain
  active. The operator key is reserved, not distributed: the obsolete API-based
  bootstrap tool needs stage-2 alignment with the installed operator-only RPC.
  Do not restore revoked permissions merely to configure that unused key. Browser handoff:
  `.campaign-work/named-key-setup/HANDOFF.md`.
- Published authenticated attachment reader is now paired with the private
  `maintenance-images` bucket (b00eea). No files, policies or records deleted.
- Initial Owner transaction rolled back without changes: exact authorized email
  `jake@cleanstreamlaundry.com` has zero Auth matches (fca4ee). Y14 requests signup
  or the correct existing email. No invitation or reset email sent.
- Existing geocode.maps.co account is not signed in; login is Y7. No key created,
  no new account or paid service, and no old key retired.

The on-demand operations snapshot passed the aggregate read above; incident/rollback
rehearsal and mobile disclosure acceptance remain. Cleanup authoring uses the approved draft plus
catalog-only FK/column/trigger metadata in
`.campaign-work/account-cleanup/cleanup-catalog-inputs.txt`; no customer rows or
financial/provider operations were read or changed for that authoring input.

**User-directed phase order:** implementation/setup and then known fixes were
announced complete apart from assigned inputs; stage 3 is now authorized as recorded
above. The earlier stage-1/2 QA pause no longer applies. The planned native Keychain
restart probe was not implemented or run. Preserve valid prior results without
rerunning them. Current actionable items and all parked user dependencies
are maintained once in [the staged priority list](../APP_FIX_PRIORITIES.md#current-work-order).
Announce stage completion before advancing; parked items are still unfinished,
not silently counted as complete. The user has now approved website publication,
breaking older-build queries (first real release), named keys with old keys
retained, reconciliation installation with execution disabled, draft cleanup
implementation with destructive execution disabled, scoped DMARC correction,
geocoding replacement if access exists and later test mail to support. Initial
Owner is explicitly `jake@cleanstreamlaundry.com`, not the operator login.
The user reports machine tests already done and excludes new machine/test-budget
work; do not launch additional real charges, refunds or vends as verification.
The disclosure draft and incident runbook remain pending acceptance/rehearsal.
Scheduler installation is recorded above, not end-to-end runtime acceptance.

**Password-button accessibility corrected:** the recorded Login button had an
empty native accessibility label. Existing IconButton tooltips now announce
Show/Hide password on Login, sign-up and reset, with distinct confirmation text.
Reset reuses one optional visibility label so validation errors cannot replace
the action description. No controller, layout, dependency or Auth behavior change.
Independent QA accepts43 retained plus4 new widget cases (891fbe), and all seven
touched source/test paths analyze cleanly (0ac510). One-job simulator build4b48d6
passes with all ten protected inputs unchanged. Native Login AX snapshots10-13
show Show -> Hide -> Show with the expected button target; both fields stay empty,
no credentials/provider submission occurs, and the app is stopped. Exact bytes
match QA (6aa1dd). This is not full VoiceOver/Android acceptance. Evidence:
`.campaign-work/website-qa/startup-transition/PASSWORD-ACCESSIBILITY.md` and
`.campaign-work/firebase/full-app-build/NATIVE-ACCESSIBILITY.md`.

**Ordinary-access implementation versus activation:** existing guards, public
return reader/vend, authenticated attachments/private bucket and machine-column
privacy are now installed. Deletion requests were enabled by the latest instruction;
hosted functional acceptance is still outstanding. Draft-supported permanent cleanup
source is integrated with execution off because final disposition is incomplete. Retain
accepted source evidence in
`.campaign-work/account-cleanup/ordinary-api-closure/HANDOFF.md`; do not replay SQL.

**Notification regression retained:** one test-fixture asset allowlist now matches
the accepted smaller startup logo. All eight synthetic FCM/local cold/warm
home/settings routing cases pass (432c00), with clean analysis (8cc9d1).
No runtime code, assertion or provider traffic changed. Both handles are closed;
prior startup73 is retained without another run.

**Startup white interval corrected; native launch still open:** RootApp now uses
Flutter's existing first-frame deferral and image cache to retain the splash
until the shared logo decodes. Failure/disposal releases the hold; theme changes
do not restart it. Independent root9/deep-link64 pass together (dab6de), with
clean scoped analysis. Two stale test DI mocks were aligned with current
controllers; no auth, payment, route, dependency or native configuration changed.
Earlier routing43/logo39 evidence is retained, not repeated. The one-job native
build passes (4f7266), preserving all ten protected inputs. Both new recordings
contain zero near-empty white frames versus four before the fix (e0a9fd); the
longer recording reaches settled Login by2.008s and continues through4.108s.
Independent QA visually confirms the before/after blank-white correction.
These are individual debug observations, not benchmarks. An initial native black
interval and brief splash crossfade remain; **full native/device splash
acceptance is still open**. Static native inspection found no configuration defect
and made no patches. Evidence: `.campaign-work/firebase/full-app-build/STARTUP-TRANSITION.md`
and `.campaign-work/website-qa/startup-transition/ROOT-FIRST-FRAME-RECEIPT.md`.
All test/build/decoder processes, app and recorder are stopped; the originally
absent theme preference is still absent (692cdf). No provider, signing, global
setting or Gundex change. Caffeinate PID39385 remains verified (389200).

**Latest website acceptance:** two existing CSS rules fix actual enlarged-text
Home/newsletter overflow: headings may wrap, and the hero no longer caps content
height. Independent browser26 (new4 15eb0c, existing22 b8470c), Vite build1853
(f90979) and corrected scoped lint (237083) pass. The lint fix only declares
browser globals in serialized test callbacks. Retain unchanged full strict types
(ef51ab), full lint (0eeeff) and Auth patch verification (f1be24); no duplicate
runs. The broader author probe passes18 route/viewport observations (3f1f62).
These simulate 200% text resizing, not native browser zoom or full accessibility.
All local test/server processes exited. Protected Preview
`dpl_2n5oi4FrRJdJUJuTwo91WF2TirxW` is READY (exit0/dc32aa); the 124-file snapshot
matches active source (a63674), authentication stays enabled, productionUrl is
null. Chrome verifies Home and the invalid-link newsletter route; no mutation.
Vercel's existing GitHub integration tracks `main` and auto-assigns the public
domain on successful deployment. Current dirty `CortinaQR` changes remain local;
no push, public alias, billing or Gundex change.

**Retained device acceptance:** reused the existing iOS Simulator artifact and
verified signed-out Login in light and dark, without rebuilding. The app is
stopped and its originally absent theme preference is restored and verified.
Android release-signing inputs are absent; the user was asked whether an existing
upload keystore exists. No key was generated and no signing check was bypassed.
The protected website Preview confirms support addresses, draft policy labels,
refund boundaries and explicit restoration copy. Actual 200% browser zoom could
not be established reliably; zoom was reset and viewport override removed. Do
not count that native zoom attempt or screen-reader checks as passed. Separate
CSS text-only acceptance is recorded above.

**Draft privacy disclosures:** two existing website files now cover optional
Firebase Analytics/In-App Messaging, separate FCM permission and retryable token
cleanup, Remote Config independent of optional consent, Resend delivery data,
double opt-in and no-login unsubscribe. Existing refund/retention wording and
draft label are unchanged; email remains explicitly disabled. Nearest public
route tests pass12 (1cb535) and scoped lint passes (589388); independent QA accepts
the exact copy and assertions (ffbddb), without another test run. Protected
Preview `dpl_6e2m2AnKbG5eTUU5MXBrdAxc4SAd` is READY (987d5b), retaining Vercel
authentication and a null production URL. Chrome confirms the new disclosures
and draft label. Only one runtime file changed in the 124-file curated snapshot
(ed169b); no main push, public alias, billing or Gundex changes. Provider
descriptions were checked against [Firebase privacy](https://firebase.google.com/support/privacy)
and [Resend privacy](https://resend.com/legal/privacy-policy), alongside current
client/outbox contracts. This is not legal approval or email-delivery acceptance.
After the interruption, backend and QA handles were recovered; their current
assignments are below rather than restarting the whole pool.

**Storage policies installed:** the earlier owner-only deployment precondition
missed Supabase's existing `supautils.policy_grants` delegation. Read-only
bb2e9b/801452 verified the configured postgres policy grant and loaded provider
hook; no privilege, ownership or server-setting change was needed. The corrected
guard preserves all five policy bodies and passes independent69 (eb1c6f).
Rollback-only hosted rehearsal3d6873 and unchanged-state readback10e248 passed.
Exact `4ed6c4a3` installed (778b3c), with all five policy predicates/roles/modes
verified in e00a26. Bucket public=true, size/MIME limits, helpers, records and
deletion hold are unchanged. Authenticated HTTP proof and paired public website
rollout still precede making the bucket private; policies alone do not hide
publicly served photos. Do not replay this completed policy installation.

**Anonymous staff assignments protected:** one restrictive SELECT policy closes
the legacy public read of `Location_to_Admin`; authenticated canonical self/staff
access, public machine/location browsing and trusted writers are unchanged.
Independent17 passed (ba5f8f), with its temporary PG cluster stopped/removed.
Exact migration `20261001094740` installed (ee05b4), with policy metadata verified
(d4865d). Readback c1c500 confirms one recorded source matching `d6ad6839`; the
actual anonymous-role query returns no rows (boolean proof10f00e). No records,
grants, helpers or deletion hold changed. Do not repeat installation/history.

**Machine read minimization integrated:** three app count queries now request
only IDs; the existing website repository selects its nine inventory fields and
retains nested configuration normalization. Existing filters/error behavior and
staff service-backed notes are unchanged; no dependency or abstraction added.
Independent PG24 (eb6a45), pinned Flutter15 (8ab311) and website30 (3d6a57)
pass, all processes closed. Exact six-file integration77c206 retains accepted
hashes; scoped whitespace checks pass. The accompanying column-privacy migration
`20261001095826` is NOT deployed: actual compatible client distribution or an
explicit old-client-impact decision must precede it. Old wildcard builds can
fail or show zero counts; source integration alone is insufficient.

**Machines maintenance privileges removed in development:** independent26
(53ffda) passes after a test-only correction preserving existing Owner-only
availability writes and explicit Admin denial. No production behavior changed
to satisfy that assertion. Two exact files integrated (1eff37); approved migration
`20261001101347` installed (b63c6a). Metadata383c4b/088326 proves only the intended
PUBLIC/anon/authenticated TRUNCATE, REFERENCES, TRIGGER and MAINTAIN revokes,
including column REFERENCES. The full preservation snapshot is equal: SELECT,
other DML, trusted rights, functions, policies, triggers, schema and deletion hold.
History2f6072 records one exact source `172b6edb`. No records were changed or
queried. All QA/CLI processes exited; do not replay the deployment. Unlike the
separate column-privacy change, this fix does not require a new client release.

**Other inventory maintenance privileges removed:** independent23 (66339a)
accepts the fixed Locations/washer_size_rates/cortina_machine_config batch.
Exact two-file integration6de0fe and migration `20261001103350` installation
(beb819) are complete. Catalog pre/postflight a8bbdf/53822b proves only intended
PUBLIC/anon/authenticated maintenance and column REFERENCES privileges changed;
all SELECT/DML, trusted rights, policies, functions and deletion hold are equal.
History895772 records exactly one source `eda70cb4`. No application records were
read or changed; all processes exited. This does not deploy Machines column
privacy or require a new client release. Do not replay either completed batch.

**Work-session power:** user-requested `caffeinate -di` is running as PID39385,
verified read-only (fed3f4). It prevents idle sleep, not screen locking or unlock.
Keep it until the campaign is done, then stop only this owned process after
checking its identity. No system power setting was changed.

**Environment and setup approval:** the user clarified that the hosted Clean Stream projects are still development, not a launched product, and explicitly requested enabling the planned features before testing. Provider labels such as `main PRODUCTION` are not evidence of a public release. Proceed with reviewed, scoped hosted-development setup and verification; do not keep asking for a future production-release approval for that work. Preserve existing users/records, keep paid activation, destructive cleanup and legacy-key retirement separately gated, and do not send test campaigns to real customer lists.

**Deployment approval update:** user explicitly stated "deployments are approved"
after the remaining-work list. This releases the reviewed development deployment
gates, including the pending database/function and dormant scheduler setup.
Composer must still verify project, frozen inputs, order, containment and
postflight. It is not permission for billing, customer campaigns, permanent data
deletion or legacy-key retirement, and is not evidence that deployment occurred.

**User-owned release tasks:** the user will handle Vercel activation before
go-live and the actual Google logo. Do not change billing or upload a substitute
logo. These are not blockers to approved development work. The user also
authorized simulator testing where useful; retain the single bounded runtime
queue and do not start concurrent native builds/simulators.

**User decisions, October 1 UTC:** customer app delivery is iOS/Android only;
Flutter-web hosting is deferred, without removing working browser support.
Global wallet authority is Owner-only, with multiple Owners managed by an
existing Owner. Implement canonical MFA, audited grants/removals and a last-Owner
safeguard using existing roles; no real account promotion is authorized by that
feature decision. User requests credits retained through the 30-day recovery
window then forfeited with explicit acknowledgement. This is the intended policy,
not established legal eligibility or permission to erase unsettled financial
claims. The [proposed per-class retention schedule](retention.md) is ready for
review, with primary sources and explicit open decisions; permanent cleanup
remains off pending legal/retention and implementation acceptance. Postal
address/test recipient are deferred placeholders, not usable delivery settings.

**Dormant mail scheduler installed:** user explicitly approved the dedicated
credential. It was generated in memory and saved only through the correct
project's Edge/Vault forms, with reloaded UI and boolean digest/URL match proof
(a3e209); no raw value was logged or written to a file. Before-state289820 had
the required extensions, no job/tick/Vault entries and disabled mail/null rollout.
Exact accepted setup `51524d70` installed job1 (695b3c). Postflight6ca9af confirms
the single named per-minute job, postgres ownership, exact command, invoker tick
with no anon/authenticated/service EXECUTE, and unchanged disabled delivery.
Cron's first passive run succeeded (d29ccd); this proves disabled scheduling,
not HTTP dispatch or email delivery. Sender/postal/DMARC and controlled-recipient
acceptance remain. Do not recreate credentials/jobs or enable sending with
placeholder values. Setup/disable procedure: [mail-worker-scheduler](mail-worker-scheduler.md).

**Security advisor after push:** the read-only hosted advisor completed (e7a29d).
It flags intentionally exposed definer RPCs, including capability-only push
revocation; do not revoke required cleanup merely to silence that generic
warning. The reported disabled leaked-password protection was subsequently
enabled in this project's Email provider settings and verified after reload on
October 1 UTC. Existing Pro entitlement was used; no billing, password-length,
character rules, OTP, email-change or reauthentication setting was changed.
The console confirmed successful persistence; actual rejection/login behavior
is not yet hosted-test evidence. Paired controlled app error handling is now
integrated and independently accepted: real pinned-SDK fake-HTTP9 (five retained
plus four signup cases after a PKCE fixture-only correction, ce55a0/fe2526),
nearest Auth/controller/widget155 (98d65c). Scoped analysis has zero errors and
warnings, six unchanged infos; the corrected HTTP test analyzes clean. Existing
password login and Auth methods remain unchanged; only structured weak/compromised
password reasons reach fixed signup/reset messages. No real credentials or
customer emails were used. This is not a whole-security pass.

**Multi-Owner UI accepted and published to protected Preview:** five files reuse the existing Team page,
captured-bearer API, canonical admission and components. No self-target changes;
explicit account/reason confirmation; caller-bound request IDs survive same-tab
reload for status-only reconciliation. Independent focused tests pass98
(ab097f); full strict types pass (bbc5a2) after four test-only non-null assertions,
and scoped lint passes (cd0cac/6dbe38). Runtime assertions were retained, not
rerun unnecessarily. All check processes exited. Backend canonical Owner grants,
last-Owner safeguard and keyset RPC are now integrated and independently pass43
PostgreSQL cases (d86958) plus96 distinct Deno cases/typechecks across retained
and corrected fixture runs. Flutter caller-binding now passes96 (981a96),
including the prior48 reader cases and actual delayed-dialog/account-change
checks. Four braces-only guards removed the new style diagnostics; affected-page
analysis is clean (e4627d), with other scoped analysis retained. Only reads keep
the existing 10-second deadline; no write timeout, money replay or payout added.
The three accepted website runtime files are now in refreshed
Preview `dpl_BcjaYcu6zQ75wnPkFzR6yDBtsNve` (a65eb8, exit0/READY), with the same
124-file snapshot scope, Auth patch verification and 1,853-module build.
Chrome confirms Home and signed-out `/admin/team` reaching login. Authentication
protection remains enabled; no main push, public alias, billing or Gundex change.
Owner-positive hosted acceptance remains open.

**Owner backend installed in development:** QA-reviewed metadata scripts and
fresh correct-project preflight05c0e9 matched existing bodies/held ACLs. Exact
migration `a66ff411` applied exit0/a89d46. Postflightfbe628 confirms all14 function
bodies, owners, security-definer/search-path settings and ACLs, enabled last-Owner
guard, valid unique receipt index and unchanged wallet policy hash/invoker view.
Deletion and bootstrap remain held. Exact single-version history readback01632b
records `20261001013709`; do not replay it. Paired `admin-portal` is ACTIVEv3 with
gateway verification false and canonical internal Auth/MFA; `delete-account` is
ACTIVEv30/true. Both deployment processes exited0 and empty unauthenticated POSTs
return401 (8d1fd3). No real account, role, balance or financial record was changed.
The security advisor completed (4e7a85), including generic authenticated-definer
warnings for the deliberately guarded Owner wrappers; this is not a whole-security
pass or grounds to revoke required APIs.

**Deletion/payment follow-up accepted92:** same captured caller is rechecked after
the capacity wait and before Stripe creation; only exact PT409/owner_last_required
maps to a deterministic deletion409. Independent27 capacity +65 deletion cases
and typechecks pass (1140e2); all processes exited. The deletion fix is deployed
above. The Cortina writer remains local pending the public return-reader rollout;
deletion activation also still requires the private Storage transition. No new
deletion request, permanent cleanup, provider action or mail sending was enabled.

**Legacy endpoints contained in development:** independent actual-entrypoint95
passes (529066), explicit typecheck5 and lint6 pass; subsequent formatting only
wrapped lines, without changing behavior/assertions. Five fixed credential-free
handlers (`c2d0c421`) replace `wakeDevice`, `ping-device`, `verifyPayment`,
`changePassword`, `resetToken`; ten obsolete logic/test files were removed after
exact baseline hash checks. Supported Cortina, Stripe status and native/web Auth
SDK flows are unchanged. Deployment exited0 (881942); metadata62e390 confirms
ACTIVE versions34/58/28/28/30 respectively, all still `verify_jwt=true`.
Empty POSTs using verified bundled public anonymous configuration returned exact
410/upgrade_required/no-store from all five (02bd89/e55f17). No public key value,
customer identifier, password or financial payload was printed or submitted.
These handlers do not touch DB/provider/credentials. Older binaries can no longer
receive simulated wake success; any charge they made before calling wake still
requires reconciliation. Never roll back to fake success or privileged wrappers.

**C/D development deployment:** the exact 18-source artifact `f2788680` applied
with exit0/bcc2dd after project metadata confirmed Clean Stream's linked healthy
`dnuuhupoxjtwqzaqylvb` and none of the 18 history entries existed. Postflight
5dc449 confirms all expected functions/tables, private/admin RLS, wallet view
invoker mode, guard triggers and restricted direct financial INSERTs. Mail stays
off, deletion requests stay denied and authenticated restoration is preserved.
This metadata check did not read historical customer rows or financial totals.
All nine paired endpoints are deployed and ACTIVE (readback d11da8): admin-portal
1, approveRefund57, denyRefund43, maintenance-request39, paymentIntent39,
createCheckoutSession41, refund-email34, voluntary-topup-refund1 and
customer-mfa-recovery1. Gateway verification remains off only for admin-portal,
which performs canonical caller authentication; the other eight remain on.
All nine reject unauthenticated empty POSTs with 401 (63ef5a/66eedf). Independent
postflight acceptance exits 0 (66eb15). Exact 18-source migration history is
recorded and read back (d55c49), including the actual no-backfill admin split;
do not replay this batch. Cortina claim EXECUTE preserves both authenticated and
service_role access, not authenticated-only. Positive authenticated/provider
flows and subsequent payment/Storage/push/scheduler slices remain open. No money, email, factor
removal, customer deletion or historical backfill was invoked.

**Payment follow-on deployment:** exact four-source artifact `4837e950` applied
exit0/f835ca; metadata postflight exit0/9a505f verifies frozen routing columns,
immutable return versions, unique provider ownership, restricted capacity RPC,
three quota buckets, preserved RLS/triggers and disabled-mail/deletion gates.
No historical routing backfill or provider action occurred. Paired callbacks
are ACTIVE: Nayax sandbox26, Nayax26 and Stripe44, all gateway verification
false (689daa), with internal provider authentication retained. Stripe's first
deployment unexpectedly retained gateway verification despite source config;
explicit `--no-verify-jwt` corrected it. An unsigned empty POST is rejected by
the handler with HTTP400 / No signature (486b6e). Exact four-source history is
recorded and hash-verified (6626c3); do not replay the transaction. Publish the paired website return reader before
deploying the new `cortina-vend`; do not call the mixed-version rollout complete.

**Website prepublication check:** whole typecheck, zero-warning lint, SDK hash
gate and build pass (1,853 modules). VM run: 1,008 passed, two assertion failures;
Auth installer: nine passed; hosting/security: six passed, one assertion failure.
Only the three affected test files were corrected against existing contracts;
focused rerun passes three Vitest cases and four hosting cases. Independent
diff review accepts the local publication gate: 1,010 VM cases across retained
and focused runs, installer9, hosting4, security3. No runtime source/dependency
change or repeat broad suite was needed. All check processes exited. Correct
Vercel team/project access is verified (`CleanStreamLaundry/clean-stream-web`).
The reviewed development Preview is now published as described below; no
public-domain publication or billing change occurred. Isolated
`.campaign-work/website-release/source` is source-closure
accepted: original 122 runtime/build files with 227 resolved local imports;
the browser-test-only update now brings the snapshot to 124 byte-matching files
(manifest `a52e6186`). Environment files,
Git metadata, dependencies and privileged admin tooling excluded. CLI62 is now
cached and uses Node24. Following the user's explicit clarification approving
Clean Stream-only CLI/Preview access, an isolated private CLI state signed in as
`cleanstreamlaundry` (9dd3ac), preserving default/Gundex configuration. Exact
project ID/build settings and the 124-file dry-run were verified (89b474).
Environment variable names were inspected without values; a rejected broad
secret read was not bypassed. The upload/build completed exit0/669397, with Auth
patch/five-file hash verification and 1,853 Vite modules. Protected Preview
`dpl_2NwVurwUP5oDnuVDbeVWKqvjcQnW` is READY at
https://clean-stream-3bcbv5uej-clean-stream-laundry.vercel.app . Hosted Home,
support, deletion resource, deliberate 404, incomplete-payment scrubbing/reload
and signed-out protected-route redirect checks pass. No sign-in/provider
mutation was submitted. Main/GitHub, production alias, billing and Gundex remain
unchanged. This protected Preview does not satisfy the public return-reader
prerequisite for the new vend writer, nor real backend/Auth/provider acceptance.

**Simulator checkpoint:** the first restricted build stopped before compilation
on CoreSimulator permission denial. The one-job retry with native-service access
passed (97a99e), no protected input/device-artifact changes. The new Debug
simulator artifact installed on the already-booted iPhone17Pro (app previously
absent); signed-out Login renders its logo, fields and social buttons, with
matching accessibility controls. No credentials, login, payment or permission
action was submitted. The October 1 follow-up closed the earlier inconclusive
dark capture using the confirmed app-container preference and a directly viewed
dark Login image. The app is stopped and the seeded preference was removed;
structured readback verifies its originally absent state. Do not infer full
contrast, startup-transition or post-login acceptance. Screenshots and receipt are in
`.campaign-work/firebase/full-app-build/SIMULATOR-BUILD.md`. Simulator work and
the subsequent focused QA processes have exited.

**Availability admission:** the four-file endpoint-local change is integrated
byte-for-byte after independent 46-case acceptance (transport20 retained,
SDK/endpoint26 exit0/db4477) and both typechecks. Initial test-fixture typing and
sparse-import permission failures were corrected without weakening assertions.
It reuses canonical admission and named-key selection, preserves eligible
preterms support, and checks captured-caller access around privileged inventory,
leases/provider dispatch and response. No financial, shared-helper or response
contract change. Hosted `machine-availability`13 is ACTIVE/gateway false
(61827a), with internal Auth/admission; unsigned empty POST401 is verified
(ff8b1e). Positive provider reads were not invoked.

**Storage helper:** exact additive migration `fc0f5f16` installed after absence
preflight (e4870f), exit0/7d8631. Postflight4d3644 verifies descriptor access is
authenticated-only, private policy predicates are not service-callable, Storage
RLS/owner unchanged and deletion remains held. No objects/reports were read or
changed. Five policies are not yet installed and the bucket remains public;
this is not completed attachment privacy. Exact one-source history is recorded
and hash-verified (8df2b4); never replay the helper. Paired web reader, supported owner-policy
execution and authenticated HTTP proof must precede bucket privatization.

**Push registration deployed:** independent QA passes 51 cases including two
parents (486d55), with both disposable PostgreSQL clusters stopped/removed.
The exact three integration files match the frozen candidate (8726e9). Correct
project metadata preflight711b97 confirmed no push tables/RPCs/history existed.
Atomic two-source artifact `16bd1741` installed with exit0/637ac8; postflight43cf82
confirms private RLS tables, authenticated-only prepare/register, capability
revocation available to anon/authenticated, no service execute, cleanup-session
cascade/indexes, lifecycle trigger and unchanged deletion containment. Exact two
history sources are recorded and hash-verified (e9c9c4); never replay this batch.
Limits are 16 active slots/account and 20 new slots per fixed hour, with valid
replay/refresh/revocation exempt. Rate limiting and session cascade are not a
retention guarantee. No token/customer rows were inspected, notification sent,
sender enabled or permanent cleanup activated. Device/APNs acceptance remains.

**CI readiness:** the reviewed Flutter workflow now enforces the committed lock,
runs analysis with fatal errors/warnings and nonfatal existing infos, and runs
all three browser-only suites in serial headless Chrome after VM report uploads.
Independent static/config review passes; no new GitHub/browser run is claimed.
Website browser CI is now integrated: 22 desktop/mobile cases for direct/reload
routes, focus, payment entry and signed-out redirects. External HTTP/WebSockets
are blocked, with only local Vite HMR permitted. QA source/workflow validation,
22-case discovery (c58339), final syntax (7ff496) and focused active lint
(0b8c8d) pass. The actual active-site headless Chrome run now passes all 22 cases
(d0f60f), 11 each at desktop/mobile sizes, with external-request and browser-error
assertions intact. One worker, no retries, fresh temporary profiles, no personal
Chrome session or unlock. Owned Chrome/Vite processes exited, profiles were
cleaned and port4176 closed. This is local Vite behavior, not hosted/provider
acceptance or visual approval. Exactly three dev-only
Playwright1.63 nodes were added, with zero existing dependency changes; audit
reports zero known vulnerabilities (ae92bb), offline install adds only those
three (15c11e), and existing Auth SDK patch hashes still pass (bcf909).
Interactive Mac access remains blocked by the last observed lock; user unlock
was requested. Headless synthetic tests did not bypass that screen-access
boundary. Remaining accessibility checks are 200% zoom/text and synthetic admin
pagination/filter focus and result announcements; prior layout acceptance is
retained rather than repeated.

**Latest delivery checkpoint:** all 13 approved Auth templates are saved in the correct hosted project, with persisted bodies/subjects checked; all seven security notifications are enabled and verified after reload. Sources are in `supabase/templates/auth/`; actual inbox rendering/delivery remains open. Server new-payment Edge guards are integrated with 139 accepted targeted tests, preserving settlement/refunds; hosted activation remains. Mail scheduler setup/disable is integrated with 25 SQL scenarios plus parent passing, but not installed remotely. Eight real-router notification tests pass and are integrated. Icon/splash inputs and generated outputs are independently accepted: each generator ran once; six newly generated, unused legacy iOS slots were removed with explicit scoped authorization. Pixel/mask checks and protected native-file comparisons pass. Full native build acceptance is recorded below; device launch remains unverified. These are distinct scopes, not a cumulative campaign test total.

**MFA recovery decision:** user approved Owner-only manual recovery for customers after external identity verification, a recorded support case and required MFA reenrollment. Ordinary Admins and password/email possession alone cannot bypass MFA. Backend migration/endpoint are integrated after independent 48 PostgreSQL and 43 Deno cases plus typecheck. Owner UI/API, real route/nav guards and preview denial are integrated: 70 focused, 39 existing workspace and four independent route cases pass; full website type checking and zero-warning lint pass. See [recovery contract](customer-mfa-recovery.md). Hosted activation and actual Auth factor/session behavior remain unverified; privileged-account recovery is not authorized through this customer path.

**Hosted development access and changes:** correct project `dnuuhupoxjtwqzaqylvb` (PG17.6), with Gundex untouched. After explicit approval of the exact seven-source rollout, the admission/terms, recoverable-lifecycle and base/refund-request/lifecycle-mail schema transaction applied successfully (02d608); only those seven versions were recorded and read back (e3e2c0/e9ce28). Frozen artifact SHA `bbcf4efb6c60575d6ceb338787e519b140ddb45a3d0232f4f3f9ea20ca03d293`; combined independent rehearsal12 includes full rollback and preserved rows. Postflight90555f confirms mail disabled/no rollout, all six private tables RLS-enabled, five guards/triggers enabled, and no client INSERT/UPDATE privileges on roles/balance/rewards/terms fields. Request-deletion EXECUTE is deliberately false for anon/authenticated/service until ordinary API coverage closes; authenticated restoration remains available. Real API smoke5aa8b7 returns the exact review-only descriptor200 and denies unauthenticated admission401. No existing account/balance/history backfill, purge or mail send occurred. All three mail endpoints are now updated to the reviewed current closure (ACTIVE version 6, gateway JWT setting unchanged). Four unauthenticated smokes returned the expected 405/401/400/400; sending/rollout/recipient flags remain false. This is rejection-path evidence, not signed-event or delivery acceptance. Newer admin/MFA-recovery/payment/push contracts remain unapplied. Existing profile guard stays installed; `pg_net`/Vault exist, Cron is missing. Never replay the foundation, old balance backfill or this seven-file batch.

**Earlier approved containment:** `delete-maintenance` returns a fixed 403 for every non-OPTIONS request, without credentials, body parsing, clients, or database effects. User explicitly approved this hosted-development change; Backend/composer/independent QA each passed 19 safety tests. Chrome deployment and reloaded source were verified; an unauthenticated GET at 2026-09-30 00:22:18 UTC returned the expected JSON and `Cache-Control: no-store`. No record ID/body was sent or records changed. Runtime SHA-256: `2895ac547629952bed01a455e32257d27d021b34faff8e92ee5d15bdae8f713b` (LF-normalized editor source). Keep denial until the authorized replacement is reviewed; never restore the vulnerable handler. Broader maintenance/Storage activation remains open; profile protection is now applied above.

**Local delivery is underway, not production-ready. The earlier broad VM checkpoint accounts for 2,171 unique passes across 128 compatible files; subsequent overlapping scoped gates are recorded below, not added. The prior full Flutter analysis covered 322 Dart files: 0 errors, 0 warnings, 104 existing infos, not a final check of the integrated campaign. Website full TypeScript, zero-warning lint and production build pass at the installed-MFA checkpoint; later admin changes require their own integration checks. New production migrations, app deployment, key retirement, billing activation and email sends have not occurred.**

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

Accepted local work includes native secure-storage integration, admin invite/resend, lifecycle notices and public-payment controls; hosted activation is tracked separately below. Geocoding passes 16 runtime cases, whole-web typechecking, scoped web lint and the final two-file Deno lint. Policy alignment passes 37 SQL, 19 Flutter and 11 web cases; no binding policy approval or cleanup authority is inferred. Native branding, Owner recovery UI and encrypted pending-payment recovery are integrated. The narrow `flutter_secure_storage: 10.3.4` graph preserves all 207 prior lock nodes and adds six; Android backup excludes only four plugin files, and iOS uses device-only Keychain access. The rejected plaintext proposal was never integrated. After a queue-lifetime correction all 89 recovery cases pass. The later read-only owner/request lookup passes 53 Deno plus 50 affected Flutter cases (49 retained plus one corrected SDK-exception assertion); it never creates/confirms a new payment, and a missing row never unlocks checkout. Counts overlap and are not added to a campaign total. Native builds now pass; device persistence acceptance remains. Header three-case checks pass. Coding remains parallel with one QA-owned queue. Global-wallet authority, retention/balance treatment and release access remain separate dependencies.

**Email/contact setup:** restricted Resend key, dedicated newsletter-signing secret, exact project/newsletter URLs, approved webhook-signing secret and `support@cleanstreamlaundry.com` Reply-To are saved and metadata-verified. The six-event Resend webhook is enabled; unsigned requests correctly receive 400 `invalid_signature` (an initial smoke expected 401; source confirms 400). The base schema is now installed, but signed-event and suppression behavior still need acceptance. Sender/postal address, remaining settings, Cron/Vault and controlled delivery remain open; no mail was sent. The four public contact surfaces and existing deletion-link test now use support, preserving actual operator/Owner identities. Hosted public source still predates this change and lacks `/newsletter` and the reviewed pay headers. Sixteen bounded public HTTP checks confirmed redirects/TLS/assets and exact association JSON, not rendered routes or device association. Evidence: `.campaign-work/public-ui/hosted-check/HANDOFF.md`.

**New local batches:** lifecycle notices are integrated and independently accepted with 29 SQL and 30 renderer/worker cases; only a fixture singleton reset needed correction. Public Cortina byte/deadline/capability-input limits and sanitized entrypoint errors pass all 32 cases/typecheck after the narrow cleanup, with clean lint on the three new files; three existing `logic.ts` diagnostics remain separate. This is not a distributed request-frequency limit or browser-return capability fix. Owner invite/resend is integrated and independently accepted with 42 SQL plus 68 SDK/nearest-adapter cases. Exactly eight checksum entries for already-cached pinned test imports were added; existing lock entries stayed unchanged and the frozen run passed without downloads. No hosted Auth emails, migrations or payment calls were performed for these batches. Narrow native secure-storage integration passes iOS plugin build, Android plugin compilation and actual manifest checks; full app builds now pass, while device acceptance remains. Both Firebase projects have reload-verified nonblocking Remote Config Version 1 on Spark. All QA processes exited at this checkpoint.

## Remaining Work

Kisi's local transport/sandbox batch is verified. Phone-to-reader SDK integration
requires the partner ID/testing protocol, authorized per-user provisioning and
access policy, and the pending hardware for physical acceptance. No in-app unlock
button will be added. See [next Kisi batch](../KISI_SETUP.md#next-batch-and-prerequisites).

The earlier release execution queue is [Current Work Order](../APP_FIX_PRIORITIES.md#current-work-order).
Current stage is 3: scoped verification and correction of demonstrated defects.
Compatible dependency discovery/updates are frozen at the accepted batch.
The approved October 5 consent, 90-day recovery, legal pages, machine remedies,
resolution-mail and admin financial-privacy batch is deployed. Its Android APK
is built; installation/device checks are deferred by the Owner. Automatic factual
cleanup inventory and the matching daily scheduler are installed and enabled.
No further implementation/publication remains in this approved October 5 batch.
Hosted Auth/Storage erasure acceptance is not claimed. Retention
business approval, Owner identity and provider-independent map entry are already
resolved; do not reopen them as missing user inputs. Apple native provider access
is recorded above; the machine-report timing decision is resolved. Website,
vend, machine privacy and private attachments are installed; sandbox reconciliation
and transactional email are enabled. Do not reopen earlier setup from historical
receipts below or label the campaign release-ready.

## Earlier Integration Evidence

Historical context below is retained evidence, not the current queue. Current
installation receipts and user-directed phase order above supersede older rollout
and compatibility statements.

**Current integration checkpoint:** browser return scrubbing passes 47 affected web cases, typecheck and scoped lint; immutable return-version compatibility passes 29 SQL/Deno cases. New authenticated-card admission passes all 18 cases with typechecking (aecb58) after a fixture-only narrowing correction. Customer transaction/claim SELECT admission passes 27 PostgreSQL cases. Credit notices pass 79 scoped cases with no new lint diagnostics (six baseline remain); the obsolete direct sender was removed. Dark checkout passes four widget cases. Full unsigned Dev iOS Runner Release and Android arm64 Debug pass (6071ff/c0dbd5). The approved offline Android retry used a 2 GiB heap and one worker; packaged Dev identity, consent defaults, secure storage and backup exclusions were checked. All QA processes exited. Device persistence and release signing remain unverified. The seven-source admission/mail rollout is installed; new deletion requests and mail sending remain disabled.

**Google branding constraint:** existing OAuth project `clean-stream-laundry` has reload-verified home/privacy/terms links, Clean Stream authorized domain and support developer contact. Logo upload did not succeed; user will supply the actual logo, not the padded app icon. Google offers only the operator account in its required support dropdown. The user explicitly declined any additional account; leave this field unchanged and do not create Workspace/IAM/mail-routing changes to force it. This does not undo support contacts elsewhere.

**Latest financial guard:** Cortina claim admission and direct client transaction/claim INSERT denial are integrated as the exact reviewed two-file batch (migration `20260930223814`, SHA `c415380e`; runner `d2b1df09`). Independent PostgreSQL QA passes 31 (c73140), including lock/trigger races, unchanged claim replay and trusted settlement/refund exceptions. The hosted rollout remains separate and must include the legacy atomic-claim prerequisite. No accepted test suite or native build was repeated.

**Public-payment capacity guard:** the three quote/card/status buckets and
service-only RPC are already installed and recorded in the four-source payment
batch (f835ca/9a505f/6626c3). Retain SQL17, Deno24 and real-PG5 acceptance; the
accepted post-wait admission correction passes capacity27/typecheck1140e2.
Seven added handler lines belong to ONE remaining `cortina-vend` deployment,
not seven endpoints. Its current eleven-file closure creates version2 web
returns, so the actual public return reader must precede it. Protected Preview
alone does not satisfy that gate. No new code, quota probe, provider call or
duplicate schema deployment is needed. Exact mapping is in
`.campaign-work/account-cleanup/public-payment-capacity-rollout/HANDOFF.md`.
This bounds project capacity, not per-client fairness or volumetric abuse.

**Wallet/refund/admin batch:** the reviewed 18-source `activation-cd.sql`
(`f2788680`) and nine paired endpoints are now deployed in development, as
recorded above. Retain the accepted 15-case local rehearsal; do not replay this
schema. Stripe webhook/Cortina prerequisites, Storage privacy and positive
authenticated/provider acceptance remain separate. Deletion/mail containment is
unchanged.

**Payment deployment prerequisites:** the four-source assembly in `.campaign-work/payments/rollout-current/` and three callback handlers are now installed, with exact history and hosted metadata receipts at the current checkpoint. Retain the accepted combined rehearsal (child plus parent2, exit0/6c6ee7); do not replay it. The website return reader must still be published before the version-2 vend writer. Closed-app reconciliation is a separate rollout because its migration queues historical unresolved rows; it is not part of the no-backfill batch. Actual provider acceptance remains open.

**Website hosting verified read-only:** existing Vercel team `CleanStreamLaundry`, project `clean-stream-web` (`prj_7AP4uioFn8YTFagoGJIyVWFoL8or`) is accessible. It uses the existing GitHub repository, Vite/default commands and output, empty root directory and Node 24. Production tracks `main`; other branches use Preview. The current domain still serves September 22 deployment `5Z7zosXtaTBEUUfxRuwPRKc7LZEp`, sourced from CortinaQR commit `2e64f93`. Access/build-setting discovery is complete; current accepted changes still need a reviewed publishable source and deployment. The existing Hobby plan is restricted to personal/non-commercial use by [Vercel](https://vercel.com/docs/plans/hobby), so business hosting needs an explicit plan/hosting decision. Code-data training is currently opted in; that setting, billing, credentials, domains and deployments were not changed.

**Local rendered website check:** Chrome at 390x844 and 1440x900 confirms Home, support, privacy, terms, account deletion, invalid newsletter and deliberate 404 routes fit without page overflow or broken images. Public skip-link focus works. Mobile synthetic admin navigation traps focus and restores its trigger on Escape; transactions paginate 20/6, the wide table stays inside its scroll container, and the native details dialog fits/scrolls and restores focus on dismissal. These are local synthetic/layout checks, not provider, live-role, complete accessibility or policy acceptance. Missing-config checkout correctly contains failure but lacked the public theme shell; the two-file correction reuses existing shell/lead classes with no new CSS/dependency. Corrected mobile/desktop font, spacing and keyboard Support/Home exits pass; independent regression4 and scoped lint2 pass (d2c4a6/f6803f). The isolated preview used empty Supabase settings, stopped with exit130/026bff, and its tab/viewport override were closed/reset. All QA processes are closed.

This is the completion gap, not another assignment queue. The full scope remains in [priorities](../APP_FIX_PRIORITIES.md). Code completion, hosted setup and acceptance are separate; do not count an unrun test as missing implementation or a local implementation as deployed.

The earlier implementation/fix queues have been removed in favor of the single
current staged list above. Do not infer missing implementation from historical
unrun acceptance, or turn archived deployment prerequisites into new tasks.

Dependency cleanup removes seven unused packages and reclassifies test/mocktail,
with enforced-lock resolution and 12 QR/notification tests passing. The follow-up
intl 0.20.3/uuid 4.6.0 batch is also accepted: sparse resolution changes exactly
two versions/hashes and three existing branding-tool dev classifications, keeping
206 nodes. Active offline lock enforcement exits 0 (a00602), all 68 focused
parser/push/refund/payment-controller tests pass (fbd6b6), and analysis reports
0 errors/0 warnings/104 infos (exit1/993852). Exactly four current branding infos
were removed from the preceding 108; the unavailable older baseline was not
used as proof. Manifest/lock are `8f31846e`/`63aacd9e`, with unchanged reviewed
tests. No runtime source, SDK/native files or hosted services changed. All
processes are closed; broader dependency/device work remains separate.

### Test

- Startup route/logo checks pass43/39; first-frame and deep-link checks pass73. Updated simulator recordings close the measured blank-white interval. Initial native black, splash crossfade and remaining platform/theme checks still precede full splash acceptance. The website integration checkpoint, Owner recovery UI/API and existing route guards already pass; do not repeat unchanged checks.
- Hosted password/social sign-in, cold/warm links, OTP/reset, MFA/recovery, one-time terms and stale/cross-account sessions.
- Slow/offline Home/Wallet refresh, pagination, account/location changes, no visual flashes; real icon/splash masks, light/dark startup and accessibility.
- Device Keychain/Keystore persistence and backup exclusions; restart/lost-response payment recovery; concurrent spending/refunding, callback replay, reward unwind and provider-success/database-failure recovery.
- Actual washer and all six dryer choices, authenticated provider callbacks, direct reader versus Stripe/Nayax reporting and timezone boundaries.
- Approved test-recipient welcome/confirmation/unsubscribe/suppression/refund/lifecycle delivery and all 13 Auth email renderings. No customer campaign is authorized as a test.
- Physical-device FCM/In-App Messaging, denied permissions, consent, signed-out links and version blocks; signed Android/iOS builds and actual CI.
- Hosted links/redirects/SSL/association files/pay-page behavior, responsive keyboard/screen-reader checks, deletion/restore/cleanup races after policy approval, monitoring and rollback rehearsal. Final Apple/Google review remains external.

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
| UX and branding | Theme startup, Google assets, native/web icon and splash generation, responsive app controls, Home/Wallet retention and quiet refresh, public navigation and checkout styling accepted locally. Hosted OAuth and full accessibility/device review remain open. |
| Payments and freshness | Wallet serialization, bounded payment status checks, inert legacy payment route and source Realtime removal accepted locally. Voluntary top-up refunds, provider/callback hardening, physical vending and coordinated production migration remain open. |
| Backend security | Profile/location authority and canonical maintenance with paired client accepted locally. Only approved delete-maintenance deny-all containment is deployed. Public Storage privacy, old admin APIs and full lifecycle/financial coverage remain open. |
| Website | Runtime and development-security updates installed. Latest Node24 strict types, lint and build pass; full/runtime-only lock audits report zero vulnerabilities. Latest affected UI coverage totals 118 distinct cases across retained and corrected runs, not a fresh full suite. Final hosted links/policies/payment behavior remain gates. |
| Firebase and release | SDK/config/consent/release controls and approved iOS 15 native wiring integrated locally; privacy fixes independently accepted. Worker Android debug and unsigned iOS Release builds passed. Signing/APNs/device delivery, policy/store checks and rollout remain. |

The initial runtime-security installation used the accepted offline registry cache with lifecycle scripts disabled. That old manifest/lock fingerprint is superseded by the exact Auth 2.103.3 pin and reviewed postinstall patch; build verifies the five installed SDK files. No suppression of analysis or lint is authorized.

## Assignment Checkpoint

Current stage lanes are below. Prior feature/QA lanes are closed, not evidence
of six running agents. Only the explicitly assigned QA lane may run tests/builds;
other active lanes prepare disjoint source or test changes.

| Current lane | Agent / persistent root | Assignment |
| --- | --- | --- |
| Backend, high, complete | Kant, `01a0f300-1f21-7631-9bdf-de3caf10329b`, `.campaign-work/account-cleanup/permanent-cleanup/` | Both source batches integrated. Remaining disposition needs Y5. No hosted mutation or tests. |
| Mail, high, complete | Nietzsche, `01a0f7c4-c83f-7f02-b40f-69ab3baac193`, `.campaign-work/mail-transactional-activation/` | Postal split integrated; composer deployed and activated transactional delivery. No tests. |
| Provider setup, high, closed | Pascal, `01a0f787-ca2c-7a02-a903-a0591447802d`, `.campaign-work/named-key-setup/` | 24 keys and public configuration handoff complete; geocode requires login. Chrome released; no tests. |
| Cleanup QA, high, closed | Herschel, `01a0f7dc-bf1a-7e70-b3a8-2f74f3036f69`, `.campaign-work/cleanup-qa-20261001/` plus new active `execution.test.ts` |17 SQL checks accepted. Worker findings fixed; composer84 pass plus independent source review. No process or hosted activity. |
| Mail QA, medium, complete | Arendt, `01a0f7dc-bf8b-7610-bd58-24592dba680f`, `.campaign-work/mail-qa-20261001/` plus seven assigned active test files |295 active Deno,14 payload comparisons,178 SQL child cases pass. No owned process, hosted send or runtime-source edit. |
| Portable tests, medium, closed | Dirac, `01a0f7f5-d5bb-7f40-b40c-5a08d6ee9542`, three new repository SQL test/helper files | Same17 checks pass from final paths; one focused run, all clusters removed. |
| Cleanup contract QA, high, closed | Tesla, `01a0f804-d7f1-7742-bbac-be25ba1c2f05`, `.campaign-work/cleanup-contract-qa-20261001/` |20 new transport and17 new SQL cases pass; twelve populated references and late processing accepted locally. |
| Firebase deletion QA, high, closed | Sartre, `01a0f80f-84db-7671-8763-ebad4ef0d8ce`, `.campaign-work/firebase-deletion-qa-20261001/` |32 final focused cases pass after durable-ack fix; real SDK and bootstrap wiring covered. |
| Cleanup boundaries QA, high, closed | Epicurus, `01a0f812-2821-71c2-96a4-0eba239a219b`, `.campaign-work/cleanup-boundary-qa-20261001/` |39 final SQL leaves pass, including13 new boundary checks; all processes removed. |
| Composer | Active repositories and shared status |Firebase integration and cleanup fixes accepted locally; current docs updated. Runtime slot free. |

Composer owns active integration, shared guides/status, low-risk fixes and CI. Historical accepted/interrupted work is archived below; those old owners are not running.

Prior integrated batch details are preserved in the [component-key checkpoint archive](verification-20260930.md#integrated-local-batches-before-component-key-checkpoint). Consult that history only for the affected contract; current acceptance and assignments are summarized here.

Latest integration: attachment helper16 plus corrected page6, payment factory80, status adapters31 and complaint45 pass independent QA. Fourteen attachment/factory/complaint files matched reviewed candidates exactly; all 24 complaint runner prerequisites matched active source. Full-site type checking found one ES-target incompatibility in an attachment BigInt literal; the equivalent string constructor passes the active full-site recheck without changing tsconfig or assertions. Payment status now requests API2023-10-16 matching the locked SDK; staging compatibility remains a release gate.

Status adapter evidence was corrected before integration: an initial type mismatch ran zero cases, then a captured fake-fetch problem produced 6 passes/7 failures. A premature QA pass receipt was retracted immediately. The test-only dispatcher correction subsequently completed all 13 intent cases with exit0; retained checkout18 gives 31 distinct passes, not the failed run. Both guides now require inspection of completed output/counts/exit before issuing a receipt.

Wallet-funding evidence is integrated after independent98 (6 existing intent, 41 focused, 51 affected Checkout checks), typechecking and source review. It reuses the existing writer, removes requested-amount fallback and requires successful USD received principal matching the user, purpose and amount metadata, plus exact returned intent identity. Both provider modes remain supported; boolean mode validation is not independent deployment-environment enforcement. The first fixture typing failure ran zero cases; only the corrected run is accepted.

MFA QR recovery is integrated after independent13 and clean scoped lint. Existing enrollment/setup key survives local bitmap failure, manual verification remains available, and route/account changes discard late secrets/results. No new factor-recovery privilege or Auth transport. The full-site type recheck above predates this two-file batch.

Provider sign-out recovery is integrated after independent10 and clean scoped lint: protected identity/MFA clears immediately, unresolved sign-out stays blocked with honest retry feedback, and stale completion cannot overwrite a newer Auth event. This is UI state protection, not cancellation of an SDK/server call. The initial test-only lint finding was corrected without changing runtime source or assertions. Active full-site types pass with provider, QR, checkout and attachment integrations together. The completed high-effort staff agent is closed; its independent public UI successor uses medium effort rather than inheriting high.

Preferences/URL-launcher dependency slice changes only foundation2.5.5 to2.5.7 and launcher_ios6.3.5 to6.4.2 plus registry hashes. Manifest unchanged; resolution fits pinned Flutter/Dart/iOS floors and independent12 nearest VM cases pass. Active offline enforced-lock resolution passes with identical manifest/lock hashes; native bridge/device behavior remains a release check, not a VM claim.

Composer's browser partial-return fix passes independent26 and clean scoped lint in the active checkout, without copying the restricted source. Incomplete/empty session/access markers go to existing uncertainty/support UI before any quote, status or payment call; complete returns and normal machine links retain their flow. Late old results cannot overwrite that state. This does not protect a newly reopened app or prove hosted/provider behavior.

Funding creation's four-file named-secret batch passes independent47 with typechecking and whitespace checks and is integrated. Intent and Checkout selectors preserve separate public caller admission and absent-only legacy operation; explicit invalid keys fail before provider work. Intent creation now also requests the locked SDK's API2023-10-16, asserted on fake HTTP. No remote Stripe setting, key provisioning or deployment changed; staging remains required.

Vend/refund caller public selectors are integrated after independent23 new plus18 retained checks. The five-file batch preserves actual financial bodies and updates the original ten-case refund fixture to synthetic environment lookup without host key reads. Eight retained vend tests cover pure routing/pricing, not an original wallet-route/provider suite; new tests stop before actual Start. Existing Edge lint findings remain. No cloud keys or provider actions occurred.

Flutter uncertainty protection is integrated and independently passes 45 tests (six unchanged regressions, 33 controller and six widget cases). Unresolved payments lock both methods and amount selection, without claiming unconfirmed funds were received. This is an in-session guard; durable recovery after restarting the app remains open.

The compatible web development-tool update is installed: Vite 8.3.1 and Vitest/coverage 4.1.11, preserving exact Auth 2.103.3 and its reviewed patch. Official-registry install completed with lifecycle scripts disabled; explicit patch apply/verify and installer9 passed. Node24 full types, zero-warning lint and build passed; full/runtime-only lock audits report zero vulnerabilities. Affected UI118 passed across the initial run and focused test-fixture corrections; no repeated full-suite claim.

Accepted source is integrated: new-payment control SQL/runner, six Edge runtime paths with focused tests, operator named-key support/offline30, and the installed web tooling update. SQL has 39 distinct child passes plus parent across retained and corrected runs. Edge has 139 passes with clean typechecks; all six runtime files matched reviewed candidates. It gates only new creation/debit, leaving existing funded replay, callbacks, status, reconciliation and refunds available. No hosted payment toggle/deployment occurred in this batch.

Resend setup has progressed beyond the earlier read-only inspection: the approved six-event webhook and signing secret are configured. Current delivery prerequisites and containment are recorded in the Email/contact setup checkpoint above; no mail has been sent.

Descartes owns the serial test queue. Authors freeze ready batches, send exact commands/prerequisites and continue disjoint implementation; QA writes test outputs, not source. Composer reviews evidence rather than running a third copy. No parallel browsers/native builds. Counts overlap and are not summed.

Earlier integration receipts, superseded worker states and detailed runtime caveats are preserved verbatim in the [September 30 checkpoint archive](verification-20260930.md#superseded-assignment-checkpoint). Current owners and acceptance are above; counts overlap and are not cumulative. Temporary artifact paths in that history no longer exist after the restart.

Keep these release boundaries active: canonical admin guards are deployed but positive authenticated acceptance remains; approved Owner-only global-wallet/multi-Owner changes still need backend acceptance/deployment; permanent cleanup is not approved; direct Nayax reader collections are not connected. Legacy simulator/wrapper endpoints now deny requests; reconcile any preexisting older-client payments separately. See shared backend/payment references before activation.

## Blockers and Approvals

- Development deployments and useful simulator testing are approved. User owns Google logo and Vercel activation before go-live. Owner-only global-wallet/multi-Owner and mobile-only app scope are decided. Requested deletion-credit forfeiture still needs legal/retention review and safe settlement handling; no permanent cleanup is enabled. The iOS 15 floor is already approved; billing, destructive cleanup and legacy-key retirement are not inferred from deployment approval.
- Correct Supabase access was verified through Chrome before the restart; reestablish the correct account/session before any remote action. MCP exposed only Gundex, which must not be used as a substitute.
- Correct Chrome account and official CLI sign-in now both work. The active app link is verified as `dnuuhupoxjtwqzaqylvb`; use explicit project/workdir scoping. Preserve Gundex's connector. CLI access does not authorize blanket deployment, key retirement, financial actions or destructive cleanup.
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
