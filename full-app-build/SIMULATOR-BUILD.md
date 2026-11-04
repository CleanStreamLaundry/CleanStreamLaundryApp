# Simulator Debug receipt

## Current result

Composer's authorized retry with native-service escalation succeeded: receipt `97a99e`, EXIT 0, `changedProtectedPaths: []` (also confirmed in current `simulator-build-receipt.json`). Artifact: `SimulatorDerivedData/Build/Products/Debug-iphonesimulator/Runner.app`. No package/version changes.

Composer reports the already-booted iPhone 17 Pro received the previously absent app. Signed-out Login screenshot and accessibility inspection passed; original image retained at `login-light.jpg`. No login, payment or push-permission action was performed. This is not proof that startup made no background provider requests.

The initial dark-only check was inconclusive. A bounded October 1 follow-up reused this artifact without rebuilding: light Login renders correctly; the confirmed app-container preference `flutter.themeData=darkMode` produces the dark surface with visible logo, fields, login/social buttons and account/reset links. Dark image: `login-dark.jpg`; MCP capture `1337325f-106c-48b3-9920-f06c97c2e05a`, viewed directly. Matching six AX controls were present. This closes signed-out dark Login rendering only, not contrast certification, startup-transition, current-source whole-app, or authenticated acceptance.

The initial simulator-wide defaults write did not reach the app sandbox and was removed (8ea39c). The second write targeted the verified app-container preferences and a structured plist read confirmed `darkMode` (058b3d). Host `defaults read` returned a stale absence; it was not used as final proof. After capture the app was stopped, the sandbox key was removed (22be67), and a structured plist read verified original absence (bb26a5). No credentials, login, payment or permission action was submitted. No argument-domain override was used: the pinned plugin reads `persistentDomain`, not volatile launch-argument defaults. No app-source/native-config/dependency changes were needed.

Source inspection: the legacy shared_preferences 2.5.5 prefix is `flutter.` and foundation 2.5.7 reads the app's standard UserDefaults. Thus the seed key matches, provided it reached the app's own defaults domain. ThemeManager reads `themeData`, selects darkMode, and runThemedApp awaits initialization before runApp. Login uses an opaque themed Scaffold surface; dark surface is grey.shade900 with contrasting text tokens, with no dark-only visibility branch. Missing/unreadable preference falls back to light, not blank. No demonstrated source bug explains the capture. Capture timing/optimization or compositor behavior remain hypotheses; accessibility alone proves neither dark colors nor correct pixels. No source fix or build proposed.

## Initial restricted attempt (retained)

One authorized attempt, 2026-09-30. Pinned Flutter 3.38.10 engine simulator slice exists; Podfile.lock and Pods/Manifest.lock compare equal. Existing generated configuration selects pinned Flutter and Firebase Dev (values not printed).

Command: existing Node24 with `--max-old-space-size=128 build-simulator-once.mjs`. Runner invokes `xcrun xcodebuild` on current active workspace, Runner Debug, iphonesimulator/generic simulator, arm64, jobs 1, unsigned, Swift batch disabled, Flutter heap 512. No pub/pod install or package update. Isolated output: `SimulatorDerivedData`; existing device DerivedData untouched.

Result: xcodebuild and wrapper EXIT 66 before compilation. CoreSimulator connection/log access was denied/invalid in the restricted execution environment; Xcode then reported `ios/Runner.xcworkspace is not a workspace file`. Both workspace directory and contents.xcworkspacedata were confirmed present/readable. This does not establish a source compile failure or a missing installed simulator runtime. No retry performed.

At that initial exit, no Runner.app existed at `SimulatorDerivedData/Build/Products/Debug-iphonesimulator/Runner.app`. All ten protected input/device-executable hashes were unchanged. No launch/install, provider calls, dependency changes or source edits occurred in that attempt. Child close and wrapper exit observed; independent process inventory unavailable (`pgrep` exit 3: sysmond service not found).

Exact invocation: `build-simulator-once.mjs`. Initial slot was released to composer. The authorized successful retry superseded `simulator-build.log` and `simulator-build-receipt.json`; the initial EXIT 66 history is retained above, not claimed as their current contents.
