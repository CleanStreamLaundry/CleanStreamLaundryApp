# Firebase Reference

Updated 2026-10-03 UTC. Local implementation is not deployed configuration or device-delivery proof. Verification belongs in [operations](operations.md).

## Current Collection Policy

October 4 owner clarification: Analytics is for app operation and reliability,
not advertising or customer profiling. Do not add customer identity, balances,
payment content or support content to events. Firebase automatic installation
identifiers and technical events remain data collection; public wording must not
claim zero user data or anonymity. Keep optional Google/advertising sharing off.
This clarification does not change runtime consent settings or establish store
compliance.

Operational Google Analytics for Firebase is automatically enabled by application
policy after configured startup, subject to platform/privacy restrictions and
deletion cleanup. It processes app-use events and technical app/device information;
there is no in-app Analytics switch. Custom events contain no names, email
addresses, payment details or account identifiers. Advertising storage, advertising
user data and ad personalization consent remain denied. Firebase In-App Messaging
and push remain separate optional choices; no marketing enrollment is added.

This October 3 source change supersedes the earlier Analytics opt-in policy.
All consent-off/opt-in acceptance receipts below describe that earlier policy,
not acceptance of the new automatic-collection behavior. Their historical results
are preserved; the new source and copy changes await Composer's runtime queue.

## Historical Acceptance

Actual Android FIAM provider-backed delivery now passes in the customer Release:
the correct Dev console targeted only the observed QA installation; opt-in,
process restart, service fetch of one message, exact modal rendering and ordinary
dismissal are recorded. Consent restored off, account signed out and emulator
stopped. Test-on-Device automatically created an inactive Draft campaign with no
start date/target; no campaign publication or production messaging. Dev Analytics
overview also shows ingested activity from both registered platforms, not exact
event attribution. The default SDK close-button defect is corrected with two
Android resources. The exact rebuilt APK passes native accessible name,48dp
target and expanded-area touch dismissal in portrait/landscape through the actual
SDK renderer, using an offline synthetic modal. Reporting callbacks are null;
temporary display state is restored. This does not convert the unsuccessful
rebuilt provider retest into a pass or re-prove delivery/consent enforcement.
Receipt: `.campaign-work/firebase-message-delivery-20261002/RESULTS.md`.
iOS actual provider delivery now also passes in the existing customer Debug
simulator: one Test-on-Device target, exact draft title/body, native Close button
and return to the unchanged underlying screen. Consent was enabled via existing
signed-out Privacy controls, then restored off; the two temporary local public
policy entries and debug logging were restored. No login, published campaign or
synthetic message injection. Signed-device push remains separate.
Receipt: `.campaign-work/ios-message-delivery-20261002/RESULTS.md`.

Current native acceptance: existing final iOS Simulator app applies Analytics/FIAM
opt-in and revocation in the actual SDK, persists both across process restarts,
keeps ad consent denied and leaves push off. The native Remote Config and app
caches contain the published nonblocking policy, with successful SDK fetch/apply
recorded00:02:02UTC; the acceptance session reused cache, not a fresh network fetch.
The pending cleanup now has a native diagnosis: the current ad-hoc iOS Debug
build reports APNs unavailable, including after Retry. The separate source-proven
opt-in issue is corrected: pinned Messaging16.7.0 defers APNs registration while
auto-init is false; the driver now briefly enables it only during explicit fresh
iOS token acquisition, subscribing before registration and disabling in finally.
Thirteen actual-SDK/mocked-host cases plus seven related races pass, including
service-listener/account-switch integration. Deletion also now requires successful
push cleanup before durable completion;36 affected cases pass. Both changes have
independent source review and clean analysis. Current unsigned Android/iOS
releases now include them; physical push setup/delivery remains Y9.
Receipt: `.campaign-work/ios-push-optin-20261002/RESULTS.md`.
Neither local acceptance nor the earlier diagnosis proves physical push setup
or successful token deletion on the unprovisioned simulator.
Receipt: `.campaign-work/push-cleanup-attribution-20261002/RESULTS.md`. These facts
do not prove delivery/dashboard ingestion or restrictive device policies.
Receipt: `.campaign-work/acceptance-closeout-20261002/firebase-native.md`.
Actual Android customer Release now also passes native Analytics/FIAM collection
opt-in/revocation and two process restarts, matching app settings with push off.
Five recorded states use only four whitelisted booleans; FIAM 22.0.3 persists
`auto_init`, not its manifest-default key. A separate current-release native
check now proves ad-storage/user-data/personalization denial through analytics
opt-in, revocation and a final restart. FIAM in-memory suppression is a
runtime-only property, not established by persisted collection flags; its
separate runtime acceptance is recorded below.
QA signed out, restored optional consent off, unrooted and stopped the emulator.
Receipt: `.campaign-work/android-firebase-20261002/RESULTS.md`.

Actual iOS FIAM runtime suppression is now accepted independently of persisted
flags. Public native SDK getters show suppressed/collection-off initially,
display-allowed/collection-on after UI opt-in, suppressed/off after messages-only
revocation and Analytics revocation, and suppressed/off after process restart.
All optional consent returned off; debugger detached, app/simulator stopped,
temporary local policy restored. No hosted campaign or message was sent.
Actual delivery remains separate.
Receipt: `.campaign-work/ios-fiam-runtime-20261002/RESULTS.md`.

Android FIAM runtime suppression now also passes in the unchanged current
Release. A disposable, independently reviewed instrumentation APK reads only
the mapped suppression boolean and collection getter in the actual app process.
Initial off, opt-in, messages-only revocation, Analytics revocation and a new
process after revocation all match the real Settings controls.105 reads succeed,
none fail; no SDK setters or product debug API were added. Exact release/mapping
hashes remain unchanged. Consent restored off/push untouched, account signed out,
fixture uninstalled and emulator stopped. This does not prove campaign delivery.
Receipt: `.campaign-work/android-fiam-runtime-20261002/RESULTS.md`.

Actual Android offline release-policy checks now pass: installed-build blocking,
restart/retry/resume retention, maintenance precedence/privacy controls, minimum
version above/equal to installed, and nonmatching-build allowance. A native
recommendation accessibility defect is fixed: isolate Navigator semantics and
use icon labels when root controls have no Tooltip Overlay.56 focused cases pass;
final native notice/dismissal and hard-gate exclusion pass in the rebuilt release.
Original policy/consent restored; no hosted configuration changed.
Receipt: `.campaign-work/native-release-policy-20261002/RESULTS.md`.

Actual iOS cached build/minimum/maintenance gates, privacy access, blocked-process
restart/retry and accessible recommendation dismissal now pass in customer Debug.
Original public native/app policy entries restored; simulator stopped. This is
not genuine offline transport or a fresh hosted fetch. Backend shutdown,
offline iOS acceptance and real store links remain separate.
Receipt: `.campaign-work/ios-release-controls-20261002/RESULTS.md`.

## Access and Environments

- Use the Clean Stream business Google account. The user explicitly authorized its signed-in Chrome console; connector authentication is not a prerequisite for that workflow.
- Do not sign out, replace, disconnect, or modify Gundex's Firebase project or connector setup. Verify the displayed account and project before every remote change.
- Separate development and production projects were created through Chrome and each console confirmed Spark, no-cost ($0/month). Keep one codebase with explicit build configuration and test analytics/messages/release controls away from customers. No billing account or paid service activation is authorized.
- Firebase Terms and the separate Google Analytics Terms were accepted with explicit user approval. Analytics has separate properties and Android/iOS registrations in both projects. SDK configuration is integrated locally. The approved nonblocking release policy is now published as described below; no database or customer campaign was added.
- Optional Gemini, Google Developer Program enrollment, and optional Analytics sharing are not required. Keep them off. Do not replace Supabase Auth with Firebase Auth or provision another database.

| Environment | Verified project | Analytics property ID | Console |
| --- | --- | --- | --- |
| Development | `clean-stream-dev` (Clean Stream Dev) | `556688774` | [Overview](https://console.firebase.google.com/u/2/project/clean-stream-dev/overview) |
| Production | `clean-stream-production` (Clean Stream Production) | `556696345` | [Overview](https://console.firebase.google.com/u/2/project/clean-stream-production/overview) |

Both properties use the Clean Stream account's `Default Account for Firebase` Analytics account (`410162599`). Google Products and Services, Benchmarking, Technical support, and Account specialists sharing were all deselected during account setup. Do not merge development and production properties or enable optional sharing as an SDK prerequisite.

The `/u/2/` account index is specific to the observed Chrome session. Recheck the displayed account rather than assuming that index on another machine/session.

## Existing App Identity

| Platform | Verified local identity |
| --- | --- |
| Android | `com.cleanstreamlaundrysolutions.clean_stream_laundry_app` |
| iOS | `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp` |

These come from `android/app/build.gradle.kts` and `ios/Runner.xcodeproj/project.pbxproj`. Preserve the existing iOS spelling; changing an installed application's bundle ID is not cosmetic cleanup. Both environments retain these identities, selected by explicit Dart defines rather than debug/release fallback.

| Environment | Platform | Verified Firebase app ID |
| --- | --- | --- |
| Development | Android | `1:83380736317:android:7b074a257825c9670af554` |
| Development | iOS | `1:83380736317:ios:3fe930785b224eb30af554` |
| Production | Android | `1:863183154828:android:3c15f3dbc067244de615a9` |
| Production | iOS | `1:863183154828:ios:1f263e0ea3df94bde615a9` |

Project numbers are `83380736317` (development) and `863183154828` (production). Registrations were verified in the console on 2026-09-29. The four user-supplied configurations match this table and are stored in `config/firebase/{dev,prod}`. Source downloads and Gundex were left unchanged. Existing signing identity is preserved; no APNs material or cloud signing configuration was changed.

## Local Build Contract

- Explicitly select `--dart-define-from-file=config/firebase/dev/android.defines.json` (or `dev/ios.defines.json`); production uses the corresponding `prod` file. Missing/invalid selection disables Firebase. Never silently choose production.
- Dart options and Android/iOS native configuration use the same selection. The iOS build phase removes stale config when selection is absent. The approved iOS 15 floor, local push entitlements and background mode are integrated; signed profiles/APNs and physical-device tests remain gates.
- `FirebaseBootstrap` reuses existing Auth, admission, routing and notifications. Native Analytics/FIAM defaults remain off before initialization; the service enables operational Analytics by application policy, not a saved opt-in. FIAM remains off until explicitly enabled. Push still requires opt-in, permission and current admission. No sensitive custom event parameters, automatic marketing enrollment or realtime listener is added.
- Configured builds initialize Firebase and fetch release policy independently of Analytics collection state. Automatic push-token creation stays off because token registration is explicit after opt-in/permission.
- Android explicitly removes inherited advertising-ID and ad-attribution permissions; the recorded release artifact confirms their absence. Automatic operational Analytics does not change denied ad consent or FCM/FIAM choices. Do not reintroduce advertising permissions as a generic Firebase prerequisite.
- Remote Config uses `release_policy_v1` and `config/firebase/release-policy.example.json`: startup/resume/manual fetch, 12-hour minimum interval, eight-second fetch timeout. Persisted valid blocks survive failures; no valid policy defaults to browsing. Privacy controls remain reachable during a client block.
- The local [release-control runbook](../config/firebase/RELEASE-CONTROLS.md) documents the reproducible `remoteconfig.template.json`, parser contract, blank unverified store links, and review/rollback gates. Its nonblocking baseline is now published in both projects. Failed policy-cache writes still enforce fetched blocks/maintenance in memory but cannot clear current restrictions; restart durability requires a successful write.
- Update-link launch failures are visible for both required and recommended updates; retry clears stale feedback. The two-line local fix passes five focused cases at 320px/2x text and independent source review. Gate enforcement, optional consent and recommendation dismissal are unchanged; no store URL was published or opened.
- Push registration is installed in development as `20260930130013` plus `20261001011048`, after independent 51-case acceptance and hosted metadata/history verification. It reuses canonical Home admission, limits each account to 16 active slots and 20 new slots per fixed hour, and exempts valid replay/refresh/revocation. Private session anchors preserve Auth-session cascade cleanup after revocation; this is not guaranteed eventual deletion or a retention policy. Stored tokens never authorize sending; a sender must recheck account/session/lifecycle, environment and freshness. APNs and actual device registration/cleanup/delivery remain unverified.

## Activation Boundaries

### Device Deletion

The local service now requests `FirebaseInstallations.instance.delete()` for the
current subject's server-confirmed pending deletion, alongside existing push
revocation and Analytics reset. Installations0.4.4 adds three Flutter package
nodes and reuses the existing native Firebase SDK; no custom native channel,
Admin credential, cloud service or realtime listener was added. Independent QA
passes32 focused cases after a durable preference-acknowledgment fix. The remaining
nearest cases retain their accepted evidence. CocoaPods integration preserves all
existing pins/checksums. The unsigned iOS plugin and offline Android Kotlin targets
both compile successfully; scoped analysis is clean. October1 full unsigned
Android and iOS Releases also include this plugin and pass artifact checks
(`.campaign-work/android-16kb-20261001/RELEASE-RESULT.md` and
`.campaign-work/ios-release-20261001/RESULT.md`). Signing, APNs and device delivery
remain separate; those binaries predate the subsequent Home/Wallet layout fix.

The current device stores one environment-scoped pending/completed request marker
for retries and duplicate prevention. Confirmed deletion pauses Analytics and
FIAM and clears messaging/push consent. Restoration resumes Analytics by application
policy only after pending cleanup completes; FIAM and push require fresh opt-in.
A restarted pending cleanup stays paused for that session unless restoration is
observed. Release policy cache is retained; new fetches pause only
while deletion is unresolved. Successful subsequent functional fetches may create
a new unrelated FID. This does not identify/delete installations on other devices
that remain closed, nor delete historical Analytics data. Those processor-copy
requirements remain in the retention work, not implied by token deletion.

Firebase documents up to180 days for FID-linked live/backup erasure after its API
call, and explicitly excludes Analytics data from FID deletion. Do not promise
the draft90-day backup target for this provider. [Official installation lifecycle](https://firebase.google.com/docs/projects/manage-installations#delete_a_firebase_installation).

### Hosted Release Policy

On 2026-09-30 the user explicitly approved publishing the reviewed nonblocking configuration. Both consoles initially showed no configuration, then Version 0 with only the new draft parameter. `release_policy_v1` was added as String, with no conditional overrides or other parameters changed. Both Dev and Production now show published **Version 1**, verified again after reload, and remain on Spark/no-cost. For Android and iOS, minimum/recommended are `0.0.0`, blocked builds are empty, maintenance is false and update URLs are empty. No billing, experiment, realtime listener or enabled restriction was introduced. Console persistence is not device fetch/cache acceptance; those tests remain open.

The Dev Remote Config entry page initially displayed an Analytics-not-enabled banner. The existing Dev Project settings > Integrations page subsequently confirmed Google Analytics **Enabled**, resolving that console discrepancy without creating another property or changing settings. This confirms console linkage, not device event delivery or consent behavior.

### Local Native Integration

The pinned Flutter iOS engine cache and lock-preserving CocoaPods install are complete. Only the secure-storage Darwin pod was added; existing pod versions/checksums are unchanged. The unsigned iOS plugin target builds, including its privacy resource, and Android plugin Java compilation plus the actual app manifest merge are verified. The merged manifest retains both backup exclusions, expected identity/themes and all six Firebase consent-off defaults, with no biometric permission. These narrow builds do not prove full-app linking, signing, APNs, encrypted device IO or restart/backup behavior. QA evidence is in `.campaign-work/website-qa/HANDOFF.md`.

### Remaining Boundaries

The full unsigned iOS Runner Release build passed (QA exit 0/6071ff), using pinned Flutter 3.38.10, Dev Firebase selection and one build job. The linked executable, Flutter/assets, secure-storage framework/privacy bundle and Dev identity were verified. Full Android arm64 Debug also passed (exit 0/c0dbd5) after the approved pinned dependency fetch and one offline retry with a 2 GiB Gradle heap and one worker. APK inspection verified debug kernel/assets, secure-storage classes, backup exclusions, all six consent-off defaults and Dev Firebase identity. Bundled `.env` matched the three expected public configuration keys; values were not printed. The 57 protected source/lock snapshots retained only the expected generated local build configuration difference. All processes exited. These builds do not establish physical-device persistence, release signing, APNs or store acceptance.

- Reuse the existing notification service and settings. Add only necessary SDK/configuration and focused service methods, not a parallel notification framework.
- Initial scope is infrastructure and approved test delivery. No customer campaign, automatic newsletter enrollment, or production message sending during setup.
- Preserve native startup defaults, platform/privacy restrictions and deletion pauses while enabling operational Analytics by application policy. In-App Messaging remains separately opt-in. Do not send names, email addresses, payment details, secrets, or raw deep links as custom event data.
- FCM registration/cleanup must account for permission denial, account changes, sign-out, and account deletion. Review foreground/background routes and require normal authorization at the destination; a notification is not proof of permission.
- Remote Config release controls must have safe defaults, cached known blocks, explicit environment targeting, and offline behavior. Backend authorization/shutdown remains independent of client version claims. Reuse existing configuration boundaries.
- Current Spark pricing lists 100,000 Remote Config fetches per day per project, not unlimited fetches. Use deliberate fetch intervals and verify the current quota before rollout. Functional release checks must remain independent of Analytics collection state.
- Current Firebase Flutter setup requires iOS 15 or later. The user explicitly approved raising the existing iOS 13 floor to iOS 15 on 2026-09-30; native configuration and release-build verification must accompany the SDK integration.
- No Supabase Realtime. Do not add Firestore, Realtime Database, WebSockets, or SSE. A quota-reviewed Remote Config realtime listener requires the approved urgent-invalidation use case, not general data refresh.
- Client Firebase configuration is public identification, not server authorization. Never bundle Admin SDK/service-account credentials. APNs signing material stays private and requires a reviewed setup path.
- A development Firebase project does not isolate Supabase, Stripe, email or machine providers. Verify the whole environment before connected testing; use mocks/local backends until a separate staging environment is reviewed. Do not bypass filesystem/privacy controls to obtain a downloaded configuration.

Before rollout, verify dev/prod isolation, consent, no sensitive event payloads, token cleanup, denial/offline behavior, signed-out notification navigation, release-policy fallback, costs/quotas, and both native platforms. Console provisioning alone is not SDK integration or production readiness.

Official references: [environment separation](https://firebase.google.com/docs/projects/dev-workflows/general-best-practices), [pricing](https://firebase.google.com/pricing). Verify current product/SDK documentation before implementation.
