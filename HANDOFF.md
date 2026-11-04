# Firebase Lane Handoff

## Current Secure Pending-Store Dependency Coordination

Current composer-approved direct pin: `flutter_secure_storage: 10.3.4`.
The 11.2.0 resolver failed exit1 (QA session87956 closed, receipt00ff6f):
its windows ^4.2.2 needs win32 ^6.0.1, but retained package_info_plus9.0.0
requires win32 ^5.5.3. Lock remained byte-identical. Do not upgrade package_info_plus.

10.3.4 official metadata requires Dart >=3.3 <4 / Flutter >=3.19 and permits
windows ^4.1.0; exact windows4.1.0 requires win32 ^5.5.4, intersecting the retained
constraint without overrides. Actual complete resolution remains pending QA.
Official source archive confirms default RSA OAEP SHA256 key wrapping + AES-GCM,
Android minSdk23 / Java17 / Tink1.21.0, compatible with app Android24. No deprecated
encryptedSharedPreferences option is used. Published 2026-09-13, this maintenance
release fixes namespace/migration key-loss races; no formal vendor LTS promise
was established. Required non-biometric security features are present, not weakened.
Its Darwin ^0.3.2 source has iOS12 minimum and maps unlocked_this_device to
WhenUnlockedThisDeviceOnly; fits iOS15. Exact read/write/delete APIs,
setMockInitialValues(Map<String,String>), resetOnError:false and all four backup
filenames below remain supported. No additional entitlement or permission needed.
Metadata: https://pub.dev/api/packages/flutter_secure_storage/versions/10.3.4
Archive: https://pub.dev/api/archives/flutter_secure_storage-10.3.4.tar.gz
Windows: https://pub.dev/api/packages/flutter_secure_storage_windows/versions/4.1.0
10.3.4 transitive ranges: darwin ^0.3.2, linux ^3.0.1, platform_interface ^2.0.1,
web ^2.1.1, windows ^4.1.0, meta ^1.3.0.
QA corrected resolution PASSED exit0, session94032 closed/receipt894968.
Exactly six added lock nodes: flutter_secure_storage10.3.4, darwin0.3.2,
linux3.0.3, platform_interface2.1.1, web2.1.1, windows4.1.0.
QA YAML comparison: all207 existing nodes and SDK constraints unchanged;
pub.dev sources/hashes validated against hosted-hashes, exit0/receipt5d4cf5.
Resolved lock SHA256: 1140c43ae82082be8b8e26111855b9d0638b5d3ee8f9a923c64434420fabd314.
Frozen for composer integration; no further resolver required. These are
dependency-resolution/source receipts, not runtime/native test passes.
Resolver candidate now created via apply_patch at `secure-storage/` with ONLY
pubspec.yaml and pubspec.lock copied from CURRENT active (including branding).
Source diff: exactly one dependency line added; lock cmp exit0 byte-identical.
No native edits. Parent lane manifest remains frozen and is NOT the resolver root.
Dalton owns pending-store runtime/tests; composer owns current-baseline integration;
QA owns bounded `flutter pub get` resolution (not upgrade) and final graph review
after MFA4 per composer; exact root/command sent to QA.
QA resolved the pinned graph above; no author install, runtime test or native build.

Superseded 11.2.0 source review (not the current candidate):
Official metadata: https://pub.dev/api/packages/flutter_secure_storage/versions/11.2.0
requires Dart >=3.8 <4 and Flutter >=3.19. Exact archive Android build.gradle
requires minSdk24, Java17, Tink1.23.0; plugin manifest has no permissions.
Pinned Flutter3.38.10 defaults minSdk24. README's Android23 statement is stale.
Darwin ^0.4.0: exact0.4.0 archive podspec/SPM floor iOS13, compatible with iOS15.
Other direct transitives: linux >=3.0.1 <5, platform_interface ^2.1.0,
web ^2.1.1, windows ^4.2.2, meta ^1.16.0. QA must report actual selected closure
and stop for unrelated dependency movement; no broad upgrade authorization.

Dalton advised to use `AndroidOptions(resetOnError: false)` so plugin errors do
not silently erase recovery data (Dart default is true). Default OAEP/GCM retained,
no biometric constructor/permissions. Proposed iOS option verified in exact source:
`IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device)`;
synchronizable=false, groupId=null, accessControlFlags empty. Native mapping is
WhenUnlockedThisDeviceOnly; no shared group is requested. No extra iOS entitlement
is justified for private default app-ID access. Preserve current APNs/link entitlements.
Apple: https://developer.apple.com/documentation/security/ksecattraccessgroup

Composer Android candidate: add application attributes
`android:fullBackupContent="@xml/secure_storage_backup_rules"` and
`android:dataExtractionRules="@xml/secure_storage_data_extraction_rules"`.
Create corresponding res/xml files with only sharedpref exclusions for:
- FlutterSecureStorage.xml (encrypted data)
- FlutterSecureKeyStorage.xml (wrapped key)
- FlutterSecureStorageConfiguration:FlutterSecureStorage.xml (algorithm markers)
- FlutterSecureStorageConfiguration.xml (legacy fallback markers)
Use full-backup-content for API24-30 and identical exclusions inside BOTH
cloud-backup and device-transfer of data-extraction-rules for API31+.
Do not blanket disable backup or exclude ordinary FlutterSharedPreferences.
These paths assume Dalton keeps default storageNamespace; change rules together
if a namespace is explicitly adopted. Preserve label/icon/LaunchTheme/NormalTheme.
Android: https://developer.android.com/identity/data/autobackup

Checks after resolution: exact SDK mock read/write/delete failure semantics and
Dalton's bounded pending-recovery suite; scoped XML parsing/assertions. Device
Keychain/Keystore persistence, locked-device errors and backup/restore remain gates,
not proven by mocks/XML. Web is WebCrypto/browser storage, not OS Keychain and not
an XSS defense. No broad Auth-storage migration, signing changes or optional biometrics.

## Prior Accepted Work

Status: TEST SLOT RELEASED. Node: 4 completed, 4 passed, 0 failed/skipped.
Flutter: 40 completed, 40 passed, 0 failed/skipped. Ready for composer review.
No provider calls, browser, native builds or full suites executed.

Prior independent acceptance is carried forward unchanged, per the composer's
context correction: operations records 28 PG token-backend cases, 129 privacy
cases, then 16 startup-race cases, plus Firebase privacy/native integration
acceptance. These are prior evidence, not reruns in this lane. No broad retest
or rebuild of that accepted behavior is requested. Shared status-document
corrections belong to the composer.

## Changed Paths

- `lib/services/firebase/firebase_service.dart`: on false or thrown cache writes,
  enforce valid fetched blocks/maintenance in memory but retain the current
  policy for nonrestrictive replacements. Successful writes permit clearing.
- `config/firebase/remoteconfig.template.json`: nonblocking schema-1 payload
  wrapped as the single STRING Remote Config parameter, no conditions.
- `config/firebase/RELEASE-CONTROLS.md`: reproduction, all parser fields, store
  URL verification, cache semantics and separate rollout/notification gates.
- `scripts/firebase-release-template.mjs` and its `.test.mjs`: local deterministic
  renderer and four passing Node tests, with exact checked-in template parity.
- `test/services/firebase/release_configuration_test.dart`: 40 passing Flutter
  cases: four platform defaults/controls cases plus 36 focused cache transitions
  (allowed/blocked/maintenance to allowed/recommended/blocked/maintenance with
  false, thrown and successful writes). Assert decisions, replacement identity,
  listener notifications, write attempts and persistence diagnostics.
- `docs/firebase.md`: link to operational artifact and cache-write behavior.
- `HANDOFF.md`: this status record.

Preserved: SDK initialization/privacy fixes, empty SDK sentinel (cannot clear a
known block), existing parser and schema, notification routing/token/consent
contracts, fetch intervals and environment isolation. Four existing configs,
router, DI, manifests, native signing and shared account tables untouched.
Reused: existing safe policy example, parser, mock driver/token store and Node
built-ins. Removed: no components/dependencies; replaced only the unchecked
cache-write result. No SDK/API change or additional infrastructure.
The durable runbook now uses repo-root Node/pinned Flutter commands and links to
toolchain guidance, with no machine-specific executable path or lane-root wording.
Persistence failures cannot guarantee the new in-memory block survives restart;
the previous durable cache remains the startup fallback. No persistence framework
or unrelated privacy/token changes were added.

## Verification and Gaps

Executed from `/Users/jamaki604/CleanStreamProjects/.campaign-work/firebase`
under the granted serialized slot:

```sh
/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --version
/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --test scripts/firebase-release-template.test.mjs
```

Verified Node v24.19.0; all four Node tests passed, including exact checked-in
template parity and CLI execution.
Deno 2.9.6 is assignment-reported, unused/unverified here (2.9.7 was lost).
PGlite is unused; no cache copied. Exact locked public dependencies were fetched
into the existing pub cache with subsequent composer authorization.

Verified restored SDK Flutter 3.38.10 / Dart 3.10.9 at
`/Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10`.
Executed sequentially with `CI=true FLUTTER_SUPPRESS_ANALYTICS=true
FLUTTER_TOOL_ARGS=--old_gen_heap_size=512` and that SDK's `bin/flutter`:

```sh
flutter test --help
flutter --version
flutter pub get --enforce-lockfile
flutter test --no-pub --no-test-assets --concurrency=1 --reporter=expanded test/services/firebase/release_configuration_test.dart
```

Help confirms `--no-test-assets` and `--concurrency=1` are supported. The earlier
offline-resolution blocker is resolved: authorized online `pub get
--enforce-lockfile` succeeded without upgrades. `git diff --exit-code --
pubspec.yaml pubspec.lock` passed both before and after tests. Existing Node and
version evidence was reused, not rerun in the final slot.

The first Flutter test invocation was blocked before executing cases because
the sandbox disallowed the runner's 127.0.0.1 socket. One elevated retry of the
same command completed all 40 cases successfully (exit 0). No real or synthetic
.env/assets copied. Formatting and analysis were not run; no full-suite claim.

Earlier official SDK bootstrap downloaded fonts, Gradle wrapper and host utility
artifacts along with test prerequisites; no native build/device operation ran.
Installed/global SDK was not changed. No remaining dependency/test blocker.

No published-template validation, remote project changes or delivery testing.
Actual store URLs remain unset pending verification. Notification/native rollout
status stays with the composer's operations record; this lane does not reopen
accepted backend/privacy/native work. No follow-up scope.
