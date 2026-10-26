# Platform Release Preflight

Original configuration fixes reviewed and integrated locally 2026-09-30; current
dependency references refreshed2026-10-01. Static configuration acceptance is not
store approval or a signed-device result. Accepted Firebase behavior is preserved.

The [mobile store-disclosure draft](store-disclosures.md) supplies the source-based
collection/category inventory. It is implementation documentation, not completed
store forms or policy approval. Stage3 verification is active; current artifact
results and remaining checks are in [operations](operations.md#current-checkpoint).

## Local Configuration

- Android: added `ACCESS_COARSE_LOCATION` beside existing fine location. The
  existing `LocationParser` requests geolocator permission; locked
  `geolocator_android 5.1.1` retains the manifest-based request and
  supplies neither permission itself. Fine-only requests can be ignored on
  Android 12; both permissions enable the approximate-location choice.
  [Android location requirements](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime).
- iOS: removed the second identical `CADisableMinimumFrameDurationOnPhone=true`
  entry. Effective intent stays true; dictionary keys are now unambiguous.
  Existing camera/photo/when-in-use purpose strings match QR/photo selection
  and nearest-location source. No microphone or background-location use added.
- iOS Podfile: enable only `PERMISSION_CAMERA=1` for every configuration of the
  `permission_handler_apple` target, preserving inherited/existing definitions
  and Flutter's existing hook. No other permission group is enabled. Existing
  camera purpose text is reused; users still must grant runtime access.
  Current permission plugin configuration is described in [dependencies](dependencies.md).

  Source evidence: `maintenance_request/controller.dart:136-176` requests
  `Permission.camera` and exits on denial before `ImagePicker.pickImage`.
  Current `permission_handler_apple 9.6.2` retains `PERMISSION_CAMERA=0` and
  `PERMISSION_MICROPHONE=0` defaults in `PermissionHandlerEnums.h`.
  `AudioVideoPermissionStrategy.h/.m` therefore selects the inherited
  `UnknownPermissionStrategy`, whose request returns `PermissionStatusPermanentlyDenied`
  without an OS prompt. The original Podfile/podspec supplied no camera override.
  This establishes the original default-build failure path, not a device-test
  result. The October1 scoped pod refresh resolves its pod9.4.8; the existing
  camera-only override remains. The relocated header was re-read, not inferred
  from the older package. No new permission was enabled by the upgrade.
- Preserve iOS 15, Android ID
  `com.cleanstreamlaundrysolutions.clean_stream_laundry_app`, iOS ID
  `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp`, SDK/dependency pins,
  and optional Analytics/FCM/FIAM defaults off. Android INTERNET/CAMERA and
  POST_NOTIFICATIONS are already explicit. Permission declarations do not grant
  runtime consent. [Android notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission).
- PrivacyInfo remains unchanged and is already a Runner resource. Existing
  UserDefaults `CA92.1` is the app-only preferences reason; nontracking flags
  are preserved, not independently certified. Do not infer no collection from
  missing `NSPrivacyCollectedDataTypes`: approved app data-flow inventory and
  third-party privacy-report review are still required before declaring data
  categories/purposes. [Apple reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
  [collection declarations](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest),
  [SDK manifests/signatures](https://developer.apple.com/support/third-party-SDK-requirements/).

## Unresolved Gates

October2 artifact reconciliation: the final unsigned iOS Release plist reports
`iphoneos26.2`, Xcode2620/build17C52; the final Android release manifest reports
compile/target API36. This closes SDK-version inspection for these unsigned
artifacts, not a signed archive/store upload. Current native build/persistence and
Android16/16KB runtime evidence supersede the original source-only preflight;
see `.campaign-work/login-transition-20261002/RESULTS.md` and
`.campaign-work/preferences-path-native-20261001/RESULTS.md`. Do not repeat builds
solely because the historical preflight below did not perform them.

| Owner/surface | Evidence still required |
| --- | --- |
| Native configuration/device owner | The missing camera macro is fixed locally under the expanded assignment. On a separately authorized native build, verify the generated pod-target definition and maintenance photo capture for first prompt, grant, denial and Settings recovery. No pod install, native build or device check performed here. |
| Release artifact owner | Unsigned iOS SDK inspection passes as recorded above. Verify the eventual signed archive and current upload requirements; preserve the approved iOS15 deployment floor. [Apple requirements](https://developer.apple.com/news/upcoming-requirements/). |
| Release artifact owner | Final merged unsigned Android manifest has compile/target36. Verify the eventual signed store artifact and current requirements; no SDK bump is implied by this preflight. [Google target requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-NZ). |
| Release artifact/device owner | Verify all native libraries and packaging on 16 KB devices. Current Android guidance states API 35+ apps need 16 KB support, with update blocking from February 1, 2027; do not infer an app-specific exemption or compliance. [Current 16 KB guidance](https://developer.android.com/guide/practices/page-sizes). |
| Privacy/store owner | Reconcile actual app/backend and SDK collection with App Store privacy labels, Play Data safety and policy links. A plist/permission string is not that inventory. [Apple privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Google Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en). |
| Account/store owner | Existing edit-profile deletion entry point is not proof of complete deletion. Confirm end-to-end disposition/retention and disclosures. Apple requires in-app initiation; Google also requires a functional branded web deletion resource accessible without reinstalling, plus Data safety answers. No URL invented or remote flow invoked. [Apple deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [Google deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en). |
| Signing/device owner | Confirm provisioning/APNs and notification delivery, camera/photo denial and limited access, Android approximate location, and signed release behavior. Reuse prior acceptance; this preflight does not repeat or supersede it. |

## Focused Check

On macOS with Node 24 and system `xmllint`/`plutil`/Ruby, from repository root after
the serialized test-slot grant:

```sh
node --test --test-concurrency=1 scripts/platform-release-config.test.mjs
```

Verification: 12/12 static/configuration tests passed on Node 24.19.0, with zero
failures/skips, in one serialized process. Composer integrated the narrow patch
after source review. No build/install or device validation was performed.
The tests parse XML/plists,
exercise two regression fixtures, and evaluate the actual Podfile post-install
hook with inert Ruby objects (no CocoaPods/SDK), including all plugin build
configurations, repeated application, preserved flags and untouched other pods. They
do not inspect a merged binary, certify privacy completeness, invoke an SDK or
copy environment assets. No dependencies, runtime features or policy copy added.
