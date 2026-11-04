# Secure Storage Native Integration

Source-only inspection, 2026-09-30. No native/runtime edits required by inspected
source. No install, precache, build, simulator, device or provider calls executed.
Only this report is authored in the sparse lane. Active dirty native files remain
untouched. Do not copy native source trees, Pods, engine or dependency caches.

## Current QA Receipt

Latest completed phase supersedes earlier blockers below:
- Composer-authorized online manifest-only run with all three exclusions PASSED
  exit0/3e89ad, session75667 closed,64tasks (1executed/63up-to-date),21seconds.
  Parsed actual merged manifest preserves package, both secure-storage XML refs,
  LaunchTheme/NormalTheme, six Firebase consent flags false, no biometric/fingerprint
  permissions. QA corrected its initial resource-name assertion to the actual
  source; final manifest check exit0/fd368d. No native process remains.
  Narrow native integration is accepted; full-app linking/device I/O remain open.
- trunk metadata update exit0/2ce2a8; pod install exit0/fafa5e,43pods. New lock
  entries only secure-storage10.0.0 PODS/dependency/source/checksum plus current
  unchanged Podfile checksum refresh. Existing versions unchanged; Manifest==lock.
- Runner project delta: four empty input/outputPaths arrays removed from two
  CocoaPods phases, no signing/identity/config changes reported.
- Unsigned iOS plugin build PASSED exit0/c6fa83; framework and privacy bundle exist.
- Android plugin Java compilation task completed and class exists. Its enclosing
  earlier combined process remains interrupted exit130, not a full build pass.
- Corrected exclusion dry-run PASSED exit0/7ea524. Offline manifest-only execution
  FAILED exit1/8cd389 on absent runtime dependency closure: exact Flutter engine
  cafcda5721a78a7884db92f13c5e89f7643d52dd armeabi_v7a_debug/arm64_v8a_debug/x86_64_debug,
  Firebase BOM34.19.0 and its five requested managed Firebase modules.
- QA confirms native processes exited (daemon89838 stopped); no full-app or merged
  manifest success. No author native process or source edits.

Possible next step ONLY if composer authorizes: repeat the exact reviewed
manifest-only command with all three exclusions, worker1/no-daemon/heap1024 and
sdkDownload=false, removing --offline to fetch the missing pinned runtime closure
from the configured official Flutter Maven/Google Maven repositories. No new
dry-run/plugin/iOS rerun, version update, SDK install, refresh-dependencies or
cache copying. Stop on any different blocker. Proposal only, not execution grant.

Pinned iOS precache PASSED exit0/ec7963; debug/profile/release framework Info files
present. First pod install FAILED exit31/eca2dd: missing existing locked
Firebase/InAppMessaging12.19.0 spec. No iOS compile attempted. QA confirms24scoped
native/pubspec hashes and Podfile.lock unchanged; Manifest.lock remains absent.
Android plugin compileDebugJavaWithJavac completed, but app manifest target pulled
compileFlutterBuildDebug and began additional engine downloads. QA interrupted
combined process exit130/d0c363; NO combined success or merged-manifest proof.
QA confirms no task children remain and24protected file hashes unchanged.
Do not repeat the original unexcluded Android command below.

Pinned FlutterPlugin.kt642-768 shows packJniLibsflutterBuildDebug is attached as
an API builtBy dependency and depends on compileFlutterBuildDebug;
copyFlutterAssetsDebug also depends on compilation and copies Flutter assets.
Proposed manifest-only graph verification, pending composer grant, active android/:

```sh
env JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home ./gradlew --offline --no-daemon --max-workers=1 -Dorg.gradle.jvmargs=-Xmx1024m -Pandroid.builder.sdkDownload=false :app:processDebugMainManifest -x :app:compileFlutterBuildDebug -x :app:packJniLibsflutterBuildDebug -x :app:copyFlutterAssetsDebug --dry-run
```

Inspect the dry-run task list before executing the identical command without
--dry-run: no alternate Flutter compilation or asset-copy/generation path is
allowed. Stop on a missing excluded output rather than constructing a dummy
libs.jar or patching SDK/app sources. Manifest-only acceptance is not full app
build/link/assets acceptance. Do not rerun the already-completed plugin compile.

Read-only official CDN check succeeded for exact Firebase12.19.0:
https://cdn.cocoapods.org/Specs/0/3/5/Firebase/12.19.0/Firebase.podspec.json
It contains InAppMessaging -> FirebaseInAppMessaging~>12.19.0-beta and iOS15.
Local trunk exact spec directory is absent while its version index exists.
Proposed remediation, pending composer approval: QA runs only
`env COCOAPODS_DISABLE_STATS=true /opt/homebrew/bin/pod repo update trunk`, then
one `pod install`. This refreshes existing official spec metadata, not dependency
versions. No pod update, lock deletion, repo recreation, cache copying or SDK edits.
Stop for a new exact dependency blocker or any unexpected existing-version change.

## Concrete State

- Dart plugin10.3.4 and Darwin0.3.2 sources are in the existing pub cache.
  GeneratedPluginRegistrant.m already imports/registers FlutterSecureStorageDarwinPlugin;
  generated Flutter plugin metadata includes it. Do not hand-edit generated registration.
- Current Podfile retains platform iOS15, use_frameworks, Firebase no-ad-ID and
  permission_handler camera hook. Runner project keeps iOS15/Swift5 and existing
  entitlements. Generated.xcconfig points to pinned Flutter3.38.10 and current app.
- Current Podfile.lock DOES NOT contain flutter_secure_storage_darwin. The matching
  ios/.symlinks/plugins path and local Podspec JSON are absent; Pods/Manifest.lock
  is absent even though an older Pods project exists. CocoaPods install is required.
- Darwin0.3.2 podspec declares internal CocoaPod version10.0.0 (not Dart0.3.2),
  iOS12, Swift5, Flutter-only iOS dependency and packaged PrivacyInfo.xcprivacy.
  iOS15 satisfies it. No additional entitlement, app group, biometric permission,
  deployment-floor or Xcode project edit is justified. Keep groupId null,
  synchronizable false, unlocked_this_device, empty accessControlFlags.
- Pinned SDK ios/ios-profile/ios-release Flutter.xcframework artifacts are absent.
  Its podhelper.rb explicitly errors on missing ios/Flutter.xcframework; do not
  waste a pod-install attempt before the pinned artifact restoration is authorized.
- Xcode iPhoneOS26.2 SDK and /opt/homebrew/bin/pod exist. CocoaPods1.16.2 is recorded
  in the existing lock; executable version was not rerun. No signing inspection/change.
- Android plugin10.3.4: compileSdk36/minSdk23, Java17, own AGP8.13.2 buildscript,
  exact Tink1.21.0. App retains API24/36 from Flutter, AGP8.11.1/Kotlin2.2.20,
  Gradle8.14.3. AGP8.11 and8.13 both require Gradle>=8.13/JDK>=17. No app toolchain
  bump indicated; plugin/app classpath compatibility still needs actual Gradle execution.
  App Java/Kotlin target11 is not itself a reason to rewrite it: plugin Java17 is
  compiled in its own Android library module with the existing compatible JDK.
- Existing Temurin21.0.10 and Homebrew JDK17 binaries are present. SDK android-36,
  Gradle8.14.3 distribution and AGP8.13.2 JAR are cached. Full transitive closure is
  NOT proven cached. Tink1.21.0 is absent from default ~/.gradle modules cache.
- Manifest has both backup XML attributes. Four exact plugin sharedpref exclusions
  are present for legacy backup, cloud-backup and device-transfer. No blanket
  backup disable, unrelated preference exclusion or custom namespace is needed.

## QA Prerequisites and Commands

These are a PROPOSAL, not execution authorization. QA/composer must explicitly
grant each native phase and required official artifact network. Execute one
bounded process at a time against the current active project, not this sparse
report directory. No active source copy or second app checkout is needed.
Before commands, capture scoped native diffs/hashes so existing dirty work can be
distinguished; never reset unrelated edits. No pub resolution/package upgrade.

1. Restore the pinned iOS engine artifacts only (not an SDK upgrade), if approved:

```sh
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 /Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter precache --ios
```

Requires official Flutter artifact network. Do not run flutter upgrade or substitute
global Flutter. Confirm pinned engine artifact paths exist before the next phase.

2. In active app ios/, install the new local pod while retaining existing locks:

```sh
env COCOAPODS_DISABLE_STATS=true /opt/homebrew/bin/pod install
```

No pod update, repo-update flag, lock deletion or dependency-cache copy. Existing
locked pods may require authorized official downloads because surviving Pods is
incomplete; report exact missing artifacts rather than widening versions. Expected
new pod is flutter_secure_storage_darwin(10.0.0) from .symlinks/plugins/.../darwin,
with its dependency/external-source/checksum entries. Review every other lock or
project delta; stop for unexplained Firebase/Stripe/other version movement.
Confirm Podfile.lock equals Pods/Manifest.lock and new target/privacy resource exist.

3. After install/lock review, narrow unsigned iOS native compile, active ios/:

```sh
xcodebuild -project Pods/Pods.xcodeproj -target flutter_secure_storage_darwin -configuration Debug -sdk iphoneos -jobs 1 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
```

This compiles the actual plugin in the integrated Pods graph. It does not build or
launch Runner, exercise Keychain, prove full-app linking or establish signing.
No simulator download/launch, provisioning changes or app.env bundling.

4. Narrow Android plugin compile + app manifest merge, active android/:

```sh
env JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home ./gradlew --offline --no-daemon --max-workers=1 -Dorg.gradle.jvmargs=-Xmx1024m :flutter_secure_storage:compileDebugJavaWithJavac :app:processDebugMainManifest
```

Known default-cache gap: Tink1.21.0. Do not repeatedly run this offline command
against the known missing artifact. QA can instead request ONE approved run of
the identical command without --offline to resolve the exact required closure
from existing google()/mavenCentral() repositories. Do not --refresh-dependencies,
install an SDK/NDK, change AGP/Kotlin/Gradle, or patch the pub cache on failure.
Inspect merged manifest: approved identities/LaunchTheme/NormalTheme/Firebase
consent defaults unchanged; both backup resources referenced, no biometric
permission added. This target does not assemble/install an APK or bundle app.env.

## Acceptance Boundary

Expected local acceptance is CocoaPods lock integration + one plugin-native build
per platform + merged-manifest evidence, with actual exits/logs recorded by QA.
There are zero fresh native passes now. Source/cache presence is not execution.
Full Runner/APK linking, plugin registration at runtime, encrypted write/read/delete
and process-restart recovery, locked-device errors and backup/device-transfer
behavior need a separately authorized app/device phase. Preserve the already
accepted mock89 and resolver6-node evidence; do not rerun unrelated suites.

## Sources

- Exact cached flutter_secure_storage10.3.4 android/build.gradle and Darwin0.3.2
  podspec/Package.swift/native Keychain source; pinned Flutter podhelper.rb.
- https://developer.android.com/build/releases/agp-8-13-0-release-notes
- https://developer.android.com/build/releases/agp-8-11-0-release-notes
- https://guides.cocoapods.org/using/pod-install-vs-update.html
- https://developer.android.com/identity/data/autobackup
- https://developer.apple.com/documentation/security/ksecattraccessgroup
