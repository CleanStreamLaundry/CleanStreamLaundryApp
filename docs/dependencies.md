# Dependency Reference

Reviewed 2026-10-01. Registry reports describe available versions and known advisories, not proof of exploitability or release compatibility. Composer owns manifests/locks; use isolated, focused batches and preserve unrelated dirty changes.

## Verified Baseline

- Local Flutter 3.47.2/Dart 3.13.2 differs from CI Flutter 3.38.10. Local Node 26.7.0 differs from CI Node 24. Verify the supported release toolchains before claiming reproducibility; do not silently upgrade global tools.
- Read-only native preflight finds Xcode 26.2 (17C52) and iOS 26.2 SDK. Android delegates compile/target/NDK to Flutter; the installed Flutter source currently supplies API 36 and NDK 28.2.13676358. These are configuration observations, not successful release builds or signing evidence.
- Independent native inventory verifies the cached CI Flutter 3.38.10 source has the same Android min/compile/target 24/36/36 and NDK defaults. AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.3, JDK 21 and CocoaPods 1.16.2 are present. The user approved iOS 15; that floor and Firebase native wiring are now integrated locally. Existing bundle IDs (including the iOS `clenaStreamLaundryApp` spelling) are preserved. Worker Android debug and unsigned iOS Release builds passed; signing and physical-device release evidence remain unverified.
- Framework compatibility is checked against that pinned source: retained Home/Wallet's initial `TickerMode.valuesOf` calls did not exist in 3.38.10. The candidate uses supported `TickerMode.of`, with three honest deprecation infos on newer 3.47. No minimum upgrade or suppression is needed. Passing tests on the newer SDK alone were insufficient.
- The September 30 runtime-only zero/11-development advisory checkpoint is superseded: compatible tooling updates are installed, with **zero reported vulnerabilities** in full and runtime-only lock audits. Vite 8.3.1 and Vitest/coverage 4.1.11 preserve the Auth 2.103.3 pin/patch. Node24 full types, lint, build, installer9 and affected UI118 pass; see operations for retained-versus-rerun scope. Registry findings do not alone prove release compatibility.
- Router 7.14.1 has a compatible update to 7.18.4. The maintainers' [untrusted-path redirect advisory](https://github.com/remix-run/react-router/security/advisories/GHSA-wrjc-x8rr-h8h6) fixes that issue in 7.18.0; use a release covering all applicable advisories. The [ws advisory](https://github.com/websockets/ws/security/advisories/GHSA-96hv-2xvq-fx4p) fixes its 8.x memory-exhaustion issue in 8.21.0. Do not reintroduce subscriptions to test an unused transport.
- Read-only Flutter `pub outdated --json` returned 139 entries with no reported current advisory, retraction or discontinuation flags. This is not a complete security audit. Report: `/private/tmp/cleanstream-flutter-outdated-20260929.json`; temporary evidence is machine-local, not a required repository dependency.
- Runtime-security integration changes exactly three lock nodes: Router/DOM 7.18.4 and ws 8.21.3. Independent QA passed 148 focused tests, strict types and tree/integrity checks. Active `npm ci --offline --ignore-scripts --no-audit --no-fund` now installs those accepted versions without manifest/lock drift. Manifest remains `241caa22239ae74979201501073b3e15006c8504f5a9117db1237f54fc301664`; lock is `ed902c76179afeb6cbf3d195d5ec4c22e0b1c5b8855a615d2c10528acc3acbc1`. Integrated checkpoint: 722 tests/42 files on Node 26.7.0, then strict types and production build on CI-compatible Node 24.19.0. Do not describe that full test run as Node 24 coverage.
- Flutter 3.38.10/Dart 3.10.9 at `/private/tmp/cleanstream-flutter-3.38.10` leaves installed Flutter unchanged. The nine-path SDK batch is integrated: Supabase Flutter 2.17.2, gotrue 2.27.2 and app_links 7.0.0; exactly 21 resolved nodes (11 updates/seven additions/three removals), one Loading API rename and corresponding tests. Active offline `pub get --enforce-lockfile` passed with no lock drift. Integrated independent QA accounts for 2,171 unique VM passes across all 128 compatible files; router Chrome 154 and terms/maintenance Chrome 291 pass. Native-only cases pass VM, not represented as browser passes. Current whole-app analysis baseline is 0 errors/2 warnings/104 infos. Native release checks remain open; earlier zero-case startup attempts are not passes.
- The [upstream refresh-race fix](https://github.com/supabase/supabase-flutter/pull/1351) guards late refresh success/failure against newer session mutations. Prefer verifying this supported upgrade to adding a custom session manager. The paired app_links update requires the documented `getInitialAppLink` -> `getInitialLink` rename and cold/warm callback/native verification. Version 7.0.0 supports the pinned Flutter and existing iOS 13 floor; 7.2.1 requires Flutter 3.44. The transitive Realtime package does not authorize subscriptions; verify no-channel startup remains disconnected.

## Batch Boundaries

October1 combined platform/utility follow-up:27 transitive version/hash updates,
188 unchanged entries,215 total; no additions/removals or manifest/SDK/direct-pin
changes. It combines five mobile implementations,15 Dart utilities and seven
path/permission nodes. Independent source review, enforced-lock resolution and
active offline metadata refresh pass. Focused VM acceptance is577 unique cases;
analysis reports0 errors/0 warnings/106 infos, with the missing-build-configuration
attempt and previous104-info baseline disclosed. Native callback/codec/resource
checks remain separate. Receipt: `.campaign-work/dependency-closure-20261001/INTEGRATED.md`.
The additional JNI/FFI closure is now integrated after independent source QA,
exact pinned resolution, active metadata refresh,92 focused cases and analysis
with0 errors/0 warnings/106 infos. It adds four nodes, updates five and removes
orphan native_toolchain_c; all other accepted updates remain. Native acceptance
is pending, not implied by those VM results. A final package-info10.2.2 patch
changes only its direct pin and lock version/hash; enforced-lock metadata and
scoped iOS pod/config refresh pass, with canonical lock quoting reviewed as
structurally equivalent. Grouped native checks remain. Receipt:
`.campaign-work/native-path-closure-20261001/INTEGRATED.md`.
The frozen website candidate is integrated for independent runtime QA. Earlier
release binaries predate these batches and the Home/Wallet layout fix.

Final84-entry frozen Flutter disposition:
`.campaign-work/flutter-final-dependency-disposition-20261001/HANDOFF.md`.
Keep framework-constrained versions, the coupled map-coordinate major migration,
and desktop/browser-only updates explicitly deferred. These are compatibility/
scope decisions, not claims that retained versions are latest or all incompatible.

October1 follow-up: Supabase Flutter2.18.0/core2.16.2/Storage2.8.1 updates exactly
three nodes;208 unchanged, no floor/native/Auth transport changes. Active156
startup/auth/public-key cases pass; the final two-case SDK lifecycle guard and
its analysis pass. No app Realtime channels, new refresh layer or runtime edits.
Map8.3.2/scanner7.4.2/image-picker1.2.3 then update three disjoint nodes and remove
orphan logger. Independent source review accepts retained245 author cases with
unchanged baseline infos. Combined graph is210 nodes; enforced-lock metadata
refresh passes. Scanner iOS/Android plugin compiles and app AAR metadata pass;
pod versions/checksums are unchanged and actual CameraX1.6.1/coroutines1.11.0/
Kotlin2.2.20 resolution is recorded. Device/release gates remain.
Geolocator14.1.1 is now integrated with package-info10.2.1/storage11.2.0 below;
neither an AGP declaration alone nor static compatibility is a native pass.
Library/tooling follow-up is integrated: nine direct/dev pins and required
archive4.3.0, ten updated nodes and200 unchanged, no additions/removals or floor
changes. GetIt9.3.0, dotenv6.0.1, pub_semver2.2.1, image4.10.1, yaml3.1.4,
launcher-icons0.14.4, mocktail1.0.5, Cupertino1.0.9 and preferences-interface2.4.2
reuse existing application calls. Independent source review, active57 cases,
enforced-lock metadata refresh and clean scoped analysis pass. No assets were
regenerated. Current receipts/ownership are in operations. Earlier2.17.2
statements below describe that baseline. The concrete remaining candidate list,
including incompatible/missing discovery, is
`.campaign-work/dependency-closure-20261001/REMAINING.md`; do not reopen accepted
batches or infer current compatibility from its saved outdated report alone.

GoRouter17.5.0 is integrated with one changed lock node and no runtime edits:
294VM/53Chrome cases, independent review and active offline enforced-lock refresh
pass.17.5.0 is the newest stable release fitting pinned Flutter3.38.10/Dart3.10.9;
18.x requires Flutter3.44/Dart3.12. Receipt: router-update-20261001/INTEGRATED.md
under `.campaign-work/`.

Package-info10.2.1, secure-storage11.2.0 and geolocator14.1.1 are integrated as one
compatible graph:13 changed nodes,5 required additions,197 unchanged,215 total.
The Linux geolocator edge requires this coupled update; no dependency override or
SDK-floor change is used. Active locked resolution,189 unique VM cases,15 Node
checks and independent QA pass. App runtime Dart and financial record options
are unchanged. The manifest removes the newly inherited location-service
permission because the app uses foreground one-shot location. Current unsigned
Android Release passes with merged permission acceptance and no floor/version
changes. iOS refresh changes only the secure-storage pod checksum, followed by a
passing full unsigned device Release and artifact identity/consent/resource checks.
Native attached-record preservation/scoped-clear now passes six phases with
three process restarts per platform; see
`.campaign-work/pending-native-probe-20261001/RESULTS.md`. Claim-only restart,
upgrade/backup, complete payment recovery and signed/physical-device acceptance
remain separate.
Receipt: `.campaign-work/platform-package-update-20261001/INTEGRATED.md`.

Firebase installation deletion adds official `firebase_app_installations`0.4.4,
platform-interface0.1.5 and web0.1.7+13: exactly three new Pub nodes. The existing
Firebase core platform-interface8.1.1 and preferences platform-interface2.4.1 are
declared as test dependencies without version/hash changes. Offline resolution
passes. Native Firebase12.19.0 and all other pod versions/checksums are unchanged;
only the plugin and Firebase/Installations subspec were added. Both native plugin
compiles pass (unsigned iOS, cached Android), alongside32 focused Flutter tests
and clean scoped analysis. No provider, app launch, new platform or paid service.
Subsequent unsigned full Android/iOS Releases include the plugin and pass artifact
checks; signing, push delivery and physical-device acceptance remain separate.

Unused-package cleanup removes `dio`, `flutter_svg` and their five orphaned
dependencies. `test` and `mocktail` retain their locked versions as development
dependencies. No surviving version, checksum or SDK constraint changed. Active
offline enforced-lock resolution passes, as do all 12 targeted QR/notification
tests. Whole-app analysis reports 0 errors, 0 warnings and 108 infos; the earlier
104-info output is unavailable, so an unchanged-baseline claim is not supported.
Four current infos identify undeclared direct imports of already-installed
`collection`, `image` and `yaml` in branding scripts. They are not references to
the removed packages. The follow-up below resolves them. No native rebuild was
needed for this cleanup.

The subsequent pure-Dart batch updates only `intl` 0.18.1 to 0.20.3 and `uuid`
4.5.2 to 4.6.0. Official [intl](https://pub.dev/packages/intl/changelog) and
[UUID](https://pub.dev/packages/uuid/changelog) changes and cached SDK/dependency
constraints were checked against pinned Dart 3.10.9. Existing branding-tool
imports now explicitly declare unchanged `collection` 1.19.1, `image` 4.5.4 and
`yaml` 3.1.3 as development dependencies. Resolution retains all 206 nodes, with
only two version/hash changes and three classifications; no SDK or native
changes. Offline lock enforcement and 68 targeted parser, push-token, refund-UI
and payment-controller tests pass. New literal date/AM-PM/currency and UUID
checks exercise app behavior. Analysis returns to 0 errors/0 warnings/104 infos;
exactly the four undeclared-tool-import infos were removed. No runtime source
or provider behavior changed; native/device acceptance remains separate.

Web staff MFA now pins the existing Supabase/Auth 2.103.3 resolution and applies a reviewed five-file Auth patch through `scripts/auth-refresh/apply.mjs`. No resolved package node changes. Postinstall rejects unknown/partial/link-based SDK trees; the build verifies exact postimages before Vite. Package/lock root metadata is synchronized. Installed SDK/UI46, installer9, whole-site strict types/lint/build and independent native two-tab browser6 pass. Hosted MFA/recovery remains separate. An SDK update must replace and reverify this patch; do not use the older `--ignore-scripts` install recipe without explicitly running the installer afterward. Runtime source maps are not regenerated.

The preferences/URL-launcher slice updates exactly two lock nodes:
`shared_preferences_foundation` 2.5.5 to 2.5.7 and `url_launcher_ios` 6.3.5 to
6.4.2, with registry checksums and no manifest/other-node change. Both fit pinned
Flutter 3.38.10/Dart 3.10.9 and the approved iOS 15 floor. Independent 12 focused
theme, consent, cached release-policy and launch-feedback cases pass against the
resolved lane. Native Pigeon persistence and UIScene URL dispatch still require
device verification; mocked VM checks do not establish those behaviors.
Official [preferences changes](https://pub.dev/packages/shared_preferences_foundation/changelog)
and [launcher changes](https://pub.dev/packages/url_launcher_ios/changelog) were
reviewed before integration.

MFA follow-up promotes the already-locked `http 1.6.0` package to a direct dependency, with no version/checksum/graph change. Its session-free transport replaces temporary Auth clients that share browser broadcast state. Offline pinned lock enforcement passed. Independent transport/feature gates passed, and the final full Flutter analysis has 0 errors/0 warnings/104 unchanged infos. Native release checks remain open.

| Batch | Review before changing |
| --- | --- |
| Web runtime security | Router and transitive ws first; avoid a Supabase upgrade solely for ws if the existing range permits its patched version. Verify auth, redirects, public links, admin routes and pay flows. |
| Web build/test security | Vite 8.0.8 -> compatible 8.3.1; Vitest/coverage 4.1.4 -> compatible 4.1.11 together; affected transitive packages. Keep Vitest 5, TypeScript 7, jsdom 30 and other majors separate. |
| Flutter compatible updates | Review each package's actual constraints/native requirements. Maps, scanner, preferences and other compatible updates still need relevant tests and device coverage. |
| Flutter auth/navigation | Supabase Flutter2.18.0, app_links7.0.0 and GoRouter17.5.0 are locally integrated and accepted as above. Preserve single callback ownership, real-document web tests and no Realtime connections. GoRouter18.x needs a newer Flutter floor; no toolchain migration is included. |
| Flutter notifications/Firebase | Notifications22.3.1, permissions12.0.3 and timezone0.11.1 are integrated with six upgrades/two upstream additions and unchanged SDK constraints. Permissions13 requires compile37; current compile36 is retained. Nine author plus15 independent cases, active enforced-lock metadata refresh/scoped analysis, pod resolution, iOS/Android plugin compiles and Android app AAR metadata pass. Existing Firebase/Stripe pod versions unchanged. Device permissions/delivery, resource shrinking and signed artifacts remain; see notification batch receipt in operations. |
| Flutter payments | Native13.0.0/web8.0.0 integrated: highest stable pairing found compatible with pinned Flutter3.38.10; later13.1/14.x and web8.1/8.2 require Flutter3.41.0. Six Pub nodes updated,205 unchanged, no runtime edits. Independent source QA,180 unique focused cases, active metadata refresh, iOS25.15.0 plugin compile, Android23.9.2 compile/app AAR metadata and final fixture analysis pass. StripeIssuing is a required upstream pod addition; all non-Stripe pod checksums unchanged. Device presentation, signed release and actual browser execution remain separate; receipt in operations. |
| Hosted PostgreSQL | Observed production is 17.6; synthetic concurrency tests use 17.11. Review [Supabase's upgrade caveats](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes), affected extensions/indexes and recovery before any separately approved production upgrade. |

## Verification Rules

Use current official changelogs and registry metadata. Prefer the latest compatible supported version that can be verified; record a concrete blocker for deferred updates. Do not run blanket `audit fix`, force resolutions, weaken tests/types, or add overrides without understanding the dependency tree. Preserve package provenance and lockfile integrity; review lifecycle scripts before installation.

For npm discovery, `npm audit --json --ignore-scripts --package-lock-only`, its `--omit=dev` variant, and `npm outdated --json` are read-only project checks. Sanitize inherited environment and use the official registry. Distinct empty user/global config paths are required: npm rejects loading `/dev/null` as both. For Flutter use `flutter --suppress-analytics --no-version-check pub outdated --json`; it can update the SDK/package cache but does not upgrade project dependencies.

After each batch, verify exact manifest/lock changes, dependency-tree validity, audit delta, focused tests, strict types/analysis, broader tests/builds appropriate to risk, and release-toolchain compatibility. No changed package is accepted from a version number alone. Keep installation and integration evidence in [operations](operations.md).

## Store Build Gates

Earlier read-only inventory: `/private/tmp/cleanstream-qa-native-readiness-20260930.md` (lost after restart). October1 unsigned Android/iOS Releases now pass linking and artifact checks; merged Android release permissions are verified, including INTERNET and removal of unnecessary advertising/background-location permissions. Final signing, device behavior and complete 16 KB acceptance remain gates. These binaries precede the later three-file Home/Wallet layout fix.

The accepted Debug APK was inspected independently without rebuilding or changing it. It contains 17 native libraries: seven arm64, five x86_64 and five ARM32, despite the arm64 Flutter target. Whole-APK ZIP alignment and all 33 LOAD checks for the 12 packaged 64-bit libraries pass. Eight RELRO ends fail the current [Android criterion](https://developer.android.com/guide/practices/page-sizes#relro): graphics-path and datastore-counter on both 64-bit ABIs, arm64 Flutter, x86_64 barcode, and surface-util on both. ARM32 is inventory-only. Evidence: `.campaign-work/firebase/full-app-build/16kb-results/inspection-NThdAI/report.json`; QA exited 1 with findings (4e4bce), and the APK was unchanged.

Current unsigned Dev Release supersedes that older Debug inventory for release
assessment:26 packaged libraries,18 evaluated64-bit, ZIP/LOAD checks pass but13
RELRO endpoint findings remain. Exact current artifact/evidence is in
`.campaign-work/android-16kb-20261001/RELEASE-RESULT.md`. The isolated ARM64
CameraX surface-library probe passes3/3 with16KB pages, compatibility disabled
and read-only protection verified. This is not full scanner, other-library,
x86_64 or store acceptance; newer inspected CameraX artifacts retain the same
endpoint finding. Do not suppress the static criterion or patch prebuilt ELF bytes.

These are static mismatches, not eight demonstrated runtime crashes. The [Android linker implementation](https://android.googlesource.com/platform/bionic/+/refs/heads/main/linker/linker_phdr.cpp) page-rounds RELRO protection; inspected segments do not overlap the next writable LOAD after that rounding. This does not establish release/device compatibility. The exact sources are graphics-path 1.0.1, datastore-core-android 1.1.7, camera-core 1.5.1, barcode-scanning 17.3.0 and the pinned Flutter debug engine. No supported compatible upgrade is yet proven to resolve the finding. Inspect the eventual release artifacts and test on a 16 KB device before acceptance; do not patch binaries, suppress checks, upgrade blindly or repeat unchanged builds.

Rechecked 2026-09-29: Apple submissions require [Xcode 26 and iOS 26 SDK or later](https://developer.apple.com/news/upcoming-requirements/?id=02032026a); this is a build-SDK requirement, not the app's minimum supported iOS version. Google Play app updates require [Android 16/API 36 or later](https://developer.android.com/google/play/requirements/target-sdk?hl=en). Inspect the actual release artifact rather than assuming the CI Flutter version resolves to the same Android defaults. Verify all bundled native libraries against [Android 16 KB page-size requirements](https://developer.android.com/guide/practices/page-sizes), including Flutter and payment/scanner dependencies. No store submission or exemption is assumed.
