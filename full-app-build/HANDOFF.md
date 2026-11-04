# Full-App Native Acceptance Plan

Follow-on, source-ready only: [16 KB accepted-debug-APK inspection](16KB-CHECK.md)
and `inspect-16kb.mjs`. QA executes once; no rebuild or device run. The earlier
full-build commands below are retained as the accepted build plan, not a rerun
request. Full iOS and Android build passes are recorded by QA/composer.

Frozen source-only preparation, 2026-09-30. QA executes only after composer grants
the serial native slot. No author build/install/provider call, no runtime/native
source edits, no cache/source copies. This directory holds the plan, not another
app checkout. Commands below use the CURRENT active app after composer freezes it.

## Preconditions

- Pinned Flutter 3.38.10/Dart 3.10.9; existing Xcode 26.2/iPhoneOS 26.2,
  CocoaPods 1.16.2, Temurin 21, Gradle 8.14.3, AGP 8.11.1/Kotlin 2.2.20.
  Preserve iOS 15 and Flutter Android API 24/36/36, NDK 28.2.13676358.
- Existing generated iOS config and android/local.properties point to the pinned
  Flutter root. Current Podfile.lock and Pods/Manifest.lock contain secure-storage
  Darwin pod 10.0.0 (Dart package 0.3.2), Firebase 12.19.0. QA's accepted pod install,
  iOS plugin build and Android manifest/runtime dependency fetch are prerequisites,
  not full-app passes. Do not rerun those checks or their excluded-task commands.
- Before starting, QA confirms lock/Manifest equality and required SDK/NDK/engine
  paths exist. No SDK downloads, pub resolution, pod update, cache copying or
  refresh-dependencies. If a new exact artifact is missing, report it; do not widen
  versions or retry unchanged input. Older full-build receipts predate this graph.
- Snapshot current scoped source hashes/diff: pubspec.yaml/lock, ios/Podfile/lock,
  Runner.xcodeproj/project.pbxproj, Runner Info.plist/entitlements/privacy/launch
  assets, Android manifest/backup XML, build/settings Gradle files, gradle.properties
  and wrapper properties, scripts/firebase-ios-config.swift. Preserve all dirty
  composer changes. Expected writes are build outputs and generated local Flutter
  configuration only; stop for any unexpected source/lock migration, do not revert.

## Public Configuration Gate

pubspec bundles `.env`; DI loads it at startup. Inspected KEY NAMES ONLY:
SUPABASE_URL, ANON_KEY, STRIPE_PUBLISHABLE_KEY. Values were not read or printed.
Names alone cannot prove the contents are public. Before bundling, composer/QA
must attest via a non-printing local check that there are no additional/duplicate
keys, URL has the intended project origin without userinfo/query credentials,
ANON_KEY is an approved sb_publishable_ key or legacy JWT with role=anon (never
service_role/sb_secret_), and Stripe key is pk_ (never sk_/rk_). A format check is
not proof of server authorization. Never dump values, decoded JWTs, shell tracing,
environment dumps or generated DART_DEFINES into a receipt. No synthetic overwrite
of the active .env. Stop if this gate is not attested.

Use ONLY existing config/firebase/dev/{ios,android}.defines.json. QA verifies
FIREBASE_ENV=dev and native/key identity agreement without printing key values.
Firebase client API keys, native app IDs and project identifiers are public client
configuration, not service-account/APNs/provider secrets. Existing native selectors
verify clean-stream-dev (83380736317) and platform app/key agreement. No prod
fallback, service-account file, server provider key or private signing key bundled.
Building does not launch the app or make Firebase/Supabase/payment provider calls.
Keep optional Analytics/FCM/FIAM consent defaults off; do not change RC or Analytics.

## Serial Commands

Run each numbered process to completion and record exit before the next. Use no
verbose/--info logging. Capture sanitized failures in this lane. A 30-minute wall
limit per build is a stop/report boundary, not permission for automatic retry.
One native build job and 512 MiB Flutter tool heap are set below; these are not a
machine-wide memory ceiling (compiler/native subprocesses have separate memory).

1. Active app cwd `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp`:

```sh
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 COCOAPODS_DISABLE_STATS=true /Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter build ios --release --config-only --no-codesign --no-pub --dart-define-from-file=config/firebase/dev/ios.defines.json
```

Pinned ios/mac.dart updates generated build properties then calls
processPodsIfNeeded BEFORE returning for config-only. This is not a pure read.
The accepted pod graph should be current; unexpected pod resolution/install or
tracked-file migration requires stopping for composer, not silently proceeding.
Verify generated Release/dev selection without printing its encoded defines.

2. Same cwd, full unsigned Runner Release (not a Pods-only target):

```sh
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 COCOAPODS_DISABLE_STATS=true xcrun xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -jobs 1 -quiet -derivedDataPath /Users/jamaki604/CleanStreamProjects/.campaign-work/firebase/full-app-build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY= SWIFT_ENABLE_BATCH_MODE=NO build
```

No archive/export, provisioning updates, signing, simulator or device. Existing
Runner phases compile Flutter AOT, embed assets/frameworks and select Dev Firebase.
Do not override deployment floor, bundle identity or existing entitlements.

3. Only after iOS exits, Android cwd
`/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/android`:

```sh
DART_DEFINES=$(/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node -e 'const fs=require("node:fs");const d=JSON.parse(fs.readFileSync("../config/firebase/dev/android.defines.json","utf8"));if(d.FIREBASE_ENV!=="dev")process.exit(1);process.stdout.write(Object.entries(d).map(([k,v])=>Buffer.from(`${k}=${v}`).toString("base64")).join(","))') || exit 1
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home ./gradlew --offline --no-daemon --max-workers=1 --console=plain -q '-Dorg.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=512m -XX:ActiveProcessorCount=1' -Dorg.gradle.parallel=false -Pkotlin.compiler.execution.strategy=in-process -Pandroid.builder.sdkDownload=false -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart -Pbase-application-name=android.app.Application "-Pdart-defines=$DART_DEFINES" :app:assembleDebug
```

QA first validates the defines file as above; abort if encoding fails. No shell
tracing. Existing local.properties selects pinned Flutter, whose Gradle plugin
invokes the full Flutter debug build and asset pipeline. No task exclusions.
Single arm64 APK is intentional; not multi-ABI/16-KB/store release acceptance.
Override the repository's 8-GiB Gradle default only on this invocation.

SIGNING BOUNDARY: Android assembleDebug uses normal local DEBUG signing, not
production signing credentials. Existing Gradle configuration loads key.properties
if present, even though debug does not select its release signing configuration.
The author did not read that file. If 'no signing' means no debug keystore access
either, do NOT run step 3: composer must approve a separate unsigned Android
variant configuration. No signing bypass/init script or release-key use is proposed.
Offline is deliberate after prepared caches; new missing artifacts are a precise
approval/blocker report, not permission for another installation loop.

## Receipt / Acceptance

Record actual exits, elapsed time and output artifact paths (not a test-case count).
iOS must contain a linked Runner executable, Flutter/App frameworks, Flutter assets,
secure-storage plugin/privacy resources, and built Dev GoogleService-Info.plist with
the expected project/app identity; inspect only non-secret fields. Android must
produce app-debug.apk with Flutter assets/native arm64 library, secure-storage
plugin classes, Dev Firebase resources and the existing backup/consent manifest.
Check packaged .env NAME set without printing contents. Verify protected source
hashes/locks unchanged, except any separately reviewed generated configuration.
Do not count stale artifacts after failure: correlate current output timestamps.

Stop/report actual compile/link failures before editing. No demonstrated compile
contract bug was found during this preparation, so no source fix is proposed.
After child processes exit, release QA queue. Passing builds do not establish
physical-device Keychain/Keystore persistence, restore behavior, APNs credentials,
notification delivery, Firebase Analytics integration, signing or store readiness.
