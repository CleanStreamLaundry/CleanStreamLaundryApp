# Clean Stream development on another Mac

The October 26, 2026 handoff preserves the current app and active website source,
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
git clone --branch codex/mac-mini-handoff-20261026 https://github.com/CleanStreamLaundry/CleanStreamLaundryApp.git CleanStreamLaundryApp
git clone --branch codex/mac-mini-handoff-20261026 https://github.com/CleanStreamLaundry/CleanStreamWeb.git CleanStreamWeb-CortinaQR
```

The app snapshot starts from `kisi_unlock_feature` and includes the existing
local work beneath that branch. The website snapshot starts from `CortinaQR`.
`CleanStreamWeb` on `main` is the older checkout, not the active website.
Future work should use a working branch from this paired checkpoint. Push that
branch before switching computers, and pull it before continuing on the other.

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
