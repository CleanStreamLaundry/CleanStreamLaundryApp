# Clean Stream development on another Mac

The November 4, 2026 handoff preserves the current app and active website source,
tests, assets, database migrations, Edge Functions and dependency lockfiles. It is
a development checkpoint, not a new release or a claim that every check passed.
Read `AGENTS.md` and the current checkpoint in [operations](operations.md) before
continuing work.

## Clone the paired checkouts

Use the same handoff branch in both repositories. Keep these folder names as
siblings: website backend tests and shared documentation use the app checkout.
Run these commands in a new destination directory; do not replace an existing
checkout with uncommitted work.

```sh
mkdir -p "$HOME/CleanStreamProjects"
cd "$HOME/CleanStreamProjects"
git clone --branch codex/mac-mini-handoff-20261104 https://github.com/CleanStreamLaundry/CleanStreamLaundryApp.git CleanStreamLaundryApp
git clone --branch codex/mac-mini-handoff-20261104 https://github.com/CleanStreamLaundry/CleanStreamWeb.git CleanStreamWeb-CortinaQR
```

The app snapshot starts from `kisi_unlock_feature` and includes the existing
local work beneath that branch. The website snapshot starts from `CortinaQR`.
`CleanStreamWeb` on `main` is the older checkout, not the active website.
Future work should use a working branch from this paired checkpoint. Push that
branch before switching computers, and pull it before continuing on the other.

## Current destination and remaining setup

On November4, the Mac mini has both sibling repositories under
`/Users/jamaki604/CleanStreamProjects`, with `activate-cleanstream.sh` selecting
isolated Clean Stream tools. Flutter3.38.10/Dart3.10.9, Node24.22.2/npm11.19.1,
CocoaPods1.16.2, JDK21, SDK36 and NDK28.2 are installed. Locked npm/Pub/Pods
installation passed; Supabase CLI2.76.14 was checksum-verified separately.
Xcode is26.1 there versus26.2 on the source Mac; iOS26.1 simulator launch now passes.
The baseline website Auth installer checks and build passed. Its nine test-file
TypeScript errors were corrected in the November4 handoff; destination whole-site typecheck and all80 affected tests now pass. Both
November4 checkouts are clean.

Owner-authorized iCloud Drive packages are under **Clean Stream / Mac mini
handoff**, in **Signing-2026-11-04**, **Configuration-2026-11-04** and
**Release-assets-2026-11-04**. On November4 the destination verified all manifest
checksums and restored all11 client/Firebase files, all3 signing payloads and799
release files without conflicts. Private files are mode600; signing directory700.
Both repositories remain clean. Native iCloud sync recovered after FileProvider
service restart in its dedicated repair chat; no transfer blocker remains.

Artwork, listings, AAB9 and IPA10 retain their `.campaign-work/store-readiness-20261029`
paths. Xcode archive is `CleanStreamLaundryApp/build/ios/archive/testflight-10.xcarchive`.
Destination receipt is `.campaign-work/mac-mini-setup-20261104/setup.json` beneath
CleanStreamProjects. No Apple Keychain identity is in the Android signing package.
Local development acceptance is complete: website rendered at127.0.0.1:4173 with
zero console warnings/errors and was stopped before native work. Existing
iPhone17Pro/iOS26.1 simulator built in21.6s and reached native Login. Supabase
initialized; the documented dev command uses Firebase dev defines and the normal
`.env`, which exactly matches approved test client settings. Packaged `.env` and
Firebase plist were byte-verified. Flutter exited0; the app process stopped and
the existing simulator was preserved. An initial invocation mixed beta JSON
without CLIENT_CHANNEL and correctly rejected startup; it was corrected without
source changes. Use the documented development command or complete beta preset.

Restored archive10 passes `codesign --verify --deep --strict` with normal macOS
trust access and remains iPhone-only. The Mac mini has no valid signing identity
for Clean Stream team3843FZGZ7T. Owner must confirm the appropriate Clean Stream
account in Xcode Settings > Accounts and obtain identity/provisioning access before
signed device/release builds. Do not substitute another team. APNs/device push
acceptance remains separate; the simulator logged an APNs cleanup limitation and
a native_assets SdkRoot diagnostic, neither established a startup failure.
No upload, deployment, backend change or production activation occurred.

The single consolidated queue is [APP_FIX_PRIORITIES.md](../APP_FIX_PRIORITIES.md).
The owner directs continued production work to the Mac mini **Set up dev environment**
chat. Read the bullet checklist and check existing Clean Stream administrative
sessions there before requesting new credentials. Privileged backend/provider
credentials are separate from the transferred public client configuration.

The recovered original website prototype is on web branch
`codex/archive-website-design-20261104` at1c752efb0f6592c22db7963aca17b92925f9ac88,
inside `design-preview/website-brand-preview-20261003`. Extract that folder into
workspace `.campaign-work/website-brand-preview-20261003`; do not merge the whole
archive branch or replace the current active website. All29 files, including
README.txt and original screenshots, are preserved; optional redesign remains
separate from current-site launch.

Branches under `codex/archive-*-20261104` preserve older detached worktree source;
they are historical snapshots, not newer integrated code. The old October26
handoff and legacy website remain available. Do not merge archive branches wholesale.

## Tools

Match the accepted project toolchain before upgrading anything. Keep these tools
scoped to Clean Stream so another project's setup can keep its own versions.

| Tool | Clean Stream baseline |
| --- | --- |
| Flutter / Dart | Flutter **3.38.10**, bundled Dart **3.10.9** |
| Node.js | **24.x**, matching CI and `.nvmrc` |
| Xcode | **26.2** was used on the source Mac; verify any different installation |
| CocoaPods | **1.16.2**, with the committed `ios/Podfile.lock` |
| Android | JDK **21**, Android SDK **36**, NDK **28.2.13676358** |
| Android build tools | Gradle **8.14.3**, AGP **8.11.1**, Kotlin **2.2.20**, set by the project |

`.flutter-version` records the Flutter pin; the file alone does not select an SDK.
Install that release separately from Gundex's SDK using the
[official SDK archive](https://docs.flutter.dev/install/archive), then use its
`bin` directory first in this shell's `PATH`. For example, if installed there:

```sh
export PATH="$HOME/development/flutter-3.38.10/bin:$PATH"
export FLUTTER_TOOL_ARGS=--old_gen_heap_size=512
flutter --version
flutter doctor -v
```

Keep `FLUTTER_TOOL_ARGS` set for subsequent Flutter/native commands. If using nvm,
run `nvm install` and `nvm use` inside each checkout. An existing Node manager is
also fine as long as it selects Node 24. Xcode, simulator and device-signing setup
are covered in the [official iOS setup guide](https://docs.flutter.dev/platform-integration/ios/setup).

## Restore local configuration

The repositories are public. Copy the following files directly from the source
Mac over a trusted transfer, preserving their paths. They are intentionally
ignored in Git. Do not put privileged credentials in the bundled app `.env` or
the website's `VITE_*` variables.

| Path relative to `CleanStreamProjects` | Purpose |
| --- | --- |
| `CleanStreamLaundryApp/.env` | Public Supabase and Stripe client configuration |
| `CleanStreamLaundryApp/config/client/test.defines.json` | Automatic test-payment public settings for both beta channels |
| `CleanStreamWeb-CortinaQR/.env.local` | Public browser Supabase configuration |
| `CleanStreamLaundryApp/config/firebase/dev/` | Development Firebase native files and build defines |
| `CleanStreamLaundryApp/config/firebase/prod/` | Production Firebase files, only for approved production configuration work |

Each Firebase environment directory contains `google-services.json`,
`GoogleService-Info.plist`, `android.defines.json` and `ios.defines.json`. Preserve
the matching native file and defines together. These are client configuration,
not a substitute for backend access credentials. The repo includes `.env.example`
files with placeholders; copying a template alone does not connect the app.

For signed Android release builds, separately transfer `android/key.properties`
and the existing upload keystore through a secure channel. On the source Mac the
keystore lives outside the app repository under
`.campaign-work/store-release-20261026/private/cleanstream-upload.jks`. Update
`storeFile` in the destination `key.properties` to the destination keystore path;
its current value is an absolute source-Mac path. Keep passwords and private keys
out of Git. A debug build does not require this release keystore.

For signed iOS builds, sign into the appropriate Apple Developer account in
Xcode and configure access to the existing Clean Stream team. The repository
contains team/bundle identifiers, not Keychain private keys or provisioning
access. Do not substitute Gundex identities. Ordinary simulator development and
store distribution have different signing requirements.

Cloud service logins and CLI authentication are machine-local. Reauthenticate
only the services needed for the work, verifying the Clean Stream project. Moving
development machines does not require redeploying functions or applying migrations.

## Resolve dependencies and run

After restoring configuration and selecting the pinned tools:

```sh
cd "$HOME/CleanStreamProjects/CleanStreamLaundryApp"
export FLUTTER_TOOL_ARGS=--old_gen_heap_size=512
flutter pub get --enforce-lockfile
npm ci
cd ios
pod install --deployment
cd ..
flutter devices
```

Use a device ID reported by `flutter devices`:

```sh
flutter run -d DEVICE_ID --dart-define-from-file=config/firebase/dev/ios.defines.json
# For Android instead:
flutter run -d DEVICE_ID --dart-define-from-file=config/firebase/dev/android.defines.json
```

If CocoaPods needs to fetch a missing specification, refresh its spec cache and
retry the locked install; do not delete `Podfile.lock` or upgrade dependencies to
work around the first setup error. Start with a development Firebase selection.
Missing configuration intentionally disables Firebase rather than choosing prod.

For the active website:

```sh
cd "$HOME/CleanStreamProjects/CleanStreamWeb-CortinaQR"
npm ci
npm run dev
```

Use `npm ci` with lifecycle scripts enabled: postinstall applies the reviewed
Supabase Auth patch, and `npm run build` verifies its installed bytes. Do not copy
`node_modules`, Pods, Flutter build output, `.dart_tool`, `android/local.properties`
or `ios/Flutter/Generated.xcconfig` from the other Mac. Dependency resolution and
native tooling must regenerate their machine-specific paths. `.campaign-work`
contains historical evidence and caches; it is not a runtime source dependency.
The legacy application backup and generated Android report are omitted from the
handoff tree but retained on the source Mac. Removing them from the new tree does
not erase copies in older Git history.

## Verify on the Mac mini

Run one memory-intensive check at a time. Confirm tool versions and configuration
first, then check website installation and the relevant app area:

```sh
cd "$HOME/CleanStreamProjects/CleanStreamWeb-CortinaQR"
npm run test:auth-sdk
npm run typecheck
npm run build
cd ../CleanStreamLaundryApp
flutter analyze --no-pub --fatal-warnings --no-fatal-infos
```

Use the targeted tests specified in `AGENTS.md` for changes. CI separates the
Firebase-configured and browser-only test cases; do not mistake a default test
invocation for all configured checks. Browser end-to-end tests additionally need
`npx --no-install playwright install chromium`. Backend Deno/database suites have
their own prerequisites and are not needed just to start the mobile or web app.

Successful local installation, a running app on the chosen simulator/device and
the website in the browser establish the new Mac's development readiness. This
handoff was prepared on the source Mac; those destination checks remain to be run.

## Beta payment configuration

Use `node scripts/build_mobile_release.mjs --channel testflight --build-number N`
or `--channel play-internal --build-number N` for future beta builds. These select
ignored `config/client/test.defines.json` and development Firebase automatically;
never substitute a live Stripe key. An explicit production configuration is a
separate requirement and has not been created. The shared backend currently has
one Stripe secret, so changing that secret to live would break beta isolation.
Finish the production-environment work in the consolidated list first.

For Apple, prepare/archive in Xcode and upload through Xcode Organizer as the
owner requested. Existing build10 is iPhone-only; the source upload failed in
transport and is not on TestFlight. Google build9 is already on internal testing.
