# Theming and Refresh UX

Local source reviewed 2026-09-29. Paths below are relative to the named repository. These are implementation references, not a new design system or evidence of visual acceptance.

## Finished UI Checklist

- Preserve the requested workflow and existing useful controls. Removing a slider
  does not remove its adjacent stepper. Use familiar icon controls with tooltips
  and at least48dp targets; do not trade usability for fewer widgets.
- Use explicit existing Clean Stream theme colors, not standalone Colors.blue
  or default Material accents. Check light/dark foreground contrast in each
  default, selected, disabled, focused and error state.
  For branded financial dialogs, carry the existing logo mark, blue header and
  restrained yellow accent into the surface; a blue submit button alone is not
  sufficient brand identity. Keep content readable and controls unchanged.
- Add funds uses a clear compact hierarchy:20px heading,24-28px amount,14px controls
  and12px secondary disclosure; other surfaces follow their existing component
  hierarchy. Keep complete legal wording/links unless content
  changes are requested. Body copy must not dominate the primary task. Preserve
  system text scaling and bold text; do not change device preferences to fit.
- Align edges and use consistent8/12/16/20px spacing and8px control corners.
  Preserve the owner's gradient secondary-page headers with the yellow rule and
  red-tinted Danger Zone notice, with its Delete Account button outside the
  notice. Do not flatten accepted brand treatments as
  incidental cleanup. Short forms should use the safe viewport deliberately:
  use spare space for useful form-entry areas, not a relocated blank gap; keep
  actions near the bottom without overlays, while allowing long content,
  enlarged text and keyboard states to scroll.
  Add funds quick amounts stay in one equal-width row, with no selection-dependent
  resizing, checkmark-induced wrapping, clipped text or uneven targets. Retain
  a readable accessibility layout instead of shrinking the user's text scale:
  reflow the surrounding amount controls at enlarged text. If exceptional scaling
  cannot fit even that layout, keep the preset row horizontally scrollable rather
  than clipping or scaling text down.
- Check compact phone widths, current user device settings, keyboard open/closed,
  large text, both themes, Android system insets, errors and selected presets.
  Keep primary/Cancel actions reachable; reserve space rather than overlaying
  content. Scroll long content, not the entire action area.
- A map using remaining column height needs stable surrounding slots during
  loading. Keep availability and optional address space reserved, and constrain
  fitted balance text to its normal line height. Compare first-frame, partial
  load, settled and tab-return geometry; settled screenshots alone miss jumps.
- Before the native build, inspect real-font renders and compare visual hierarchy,
  alignment and preserved actions with the request. After installation, inspect
  the actual screen and provide the final image. Passing geometry tests or taking
  a screenshot alone is not visual acceptance. Fix visible defects before handoff.

These rules adopt Gundex's product-preservation and explicit-brand discipline,
not its product palette, layout or machine-specific rules. This checklist is the
minimum acceptance bar, not authorization for a broad redesign.

## Existing Patterns

- Legal documents use a restrained type hierarchy: 22px title, 16px section
  headings, 14px/1.6 body and 12px date/version metadata, all with zero letter
  spacing. Reuse Material onSurface with explicit body/metadata opacity and
  weights; this repo's unconfigured onSurfaceVariant/outlineVariant can default
  to solid black. Verify rendered alpha-composited contrast, not token names.
  Preserve system bold text/scaling rather than changing device preferences.
  Use consistent section/paragraph spacing and rules to separate metadata and
  agreement controls. Keep long text selectable and reading width constrained;
  do not add decorative cards or override terms content for presentation.

| Surface | Reuse / source |
| --- | --- |
| Flutter | `lib/core/theme/theme.dart`: Material 3 light/dark, blue `#2073A9`, yellow `#F3C404`, custom getters and gradients |
| Flutter preference | `lib/core/theme/theme_manager.dart`, `lib/root_app.dart`: manual persisted toggle; startup waits for preference restoration before the first app frame, with light fallback on storage failure; not system mode |
| Flutter shell | `lib/features/widgets/base_page.dart`, `custom_app_bar.dart`; feature-local widgets |
| Assets | `assets/Icon.png`, `Logo.png`, `Slogan.png`, `splash-logo.png`; `pubspec.yaml`; native/web generated assets |
| Google sign-in | `assets/Google.png`, bundled `assets/fonts/google_sans/GoogleSans-Medium.ttf` and OFL; font used only by the Google label |
| Website public | `src/components/PublicLayout.tsx`, `src/styles/PublicSite.css`, `.public-*`; 800/520px breakpoints |
| Website pay | `src/components/CortinaPayPage.tsx`, `src/styles/CortinaPay.css`, `--pay-*`; 896/560/370px breakpoints |
| Website admin | `src/admin/AdminApp.tsx`, `admin.css`, `ui.tsx`; `.admin-portal`, `--ap-*`, `.ap-*`, Field/Notice/Badge/Modal/pagination |

Website paths refer to the active `CleanStreamWeb-CortinaQR` checkout, not the older main worktree. Resolve its actual path in isolated worktrees. Public, checkout, and admin styling differ intentionally; do not consolidate them merely for uniformity.

## Local State

- Home availability now places status beside its title with a48px refresh icon,
  removing the separate footer without changing snapshot/refresh behavior. The
  existing responsive layout uses the recovered height; smaller/enlarged-text
  screens retain scrolling. BottomNavigationBar owns its system inset directly,
  without the prior82px wrapper. Home33, availability14 and navigation22 cases
  pass, including24px gesture/48px three-button insets in light/dark and2x text;
  seven changed Dart files analyze cleanly. Device delivery is recorded in
  `.campaign-work/home-wallet-20261003/RESULTS.md`.

- Android MainActivity now synchronizes the existing saved Flutter preference
  through API31+ per-app UiModeManager, at startup and preference changes, without
  changing global OS mode or adding a dependency/channel. Android36.1 actual
  Settings toggles retain the screen/process; all four OS/app cold-start pairs
  now match saved mode through native splash and Flutter. Eight branding/172
  admission checks and unsigned Android/iOS builds pass. The shared admission
  page shows the existing logo only during its initial pending check, preserving
  already-shown terms/recovery on later retries. No pre31 or physical-device
  claim; normal system splash fades remain. Evidence:
  `.campaign-work/android-startup-themes-20261002/RESULTS.md` and `QA.md`.

- iOS AppDelegate now reuses `flutter.themeData` to synchronize the app window's
  native appearance at launch and after preference changes. Actual iOS26.2
  cold starts with OS light/saved dark and OS dark/absent-light reach matching
  app-owned splash/Login; real Settings toggles agree with persisted preference
  and native window in both directions without relaunch. Debug and unsigned
  Release compile; protected configuration/dependencies unchanged. Initial
  SpringBoard launch still follows OS appearance, and Flutter's existing splash
  fade remains. Do not claim those earlier OS-owned pixels follow manual prefs.
  Receipt and independent review: `.campaign-work/native-startup-themes-20261002/`.

- Tappable SettingsCard rows now declare button semantics using their existing
  onTap; non-tappable rows and independent trailing controls remain unchanged.
  Two added regressions and all46 widget/page cases pass; scoped analysis clean.
  Actual rebuilt iOS rows expose button roles; Newsletter semantic activation
  and Sign Out reach their expected pages. Notification lead-time labels are
  also confirmed on native accessibility. Current unsigned releases include these changes. Receipt:
  `.campaign-work/acceptance-closeout-20261002/settings-button-roles.md`.

- The selected dryer option now uses white on the existing blue fill; three
  runtime lines fix native-observed blue-on-blue text without changing selection
  or payment behavior. Two new light/dark cases cover all six selections and
  rendered contrast;14 existing page cases pass. The first onPrimaryContainer
  candidate failed dark contrast and was corrected, not accepted by token name.
  Scoped analysis passes; current unsigned customer release artifacts include
  the final color fix. Receipt:
  `.campaign-work/acceptance-closeout-20261002/dryer-selection.md`.
- Home's balance header/body and Wallet's populated Transactions header now reflow
  at the existing enlarged-text threshold. Three runtime files reuse scrolling
  and layout primitives; normal-size layouts and controllers are unchanged.
  Four new360x800/2x light/dark refresh cases reproduce the previous overflows and
  now pass; all133 affected regressions and scoped analysis pass. Independent
  source QA accepts the focused fix. Captures show retained content during slow
  reads; map tiles and complete native/font rendering remain outside this check.
  Receipt: `.campaign-work/home-wallet-acceptance-20261001/RESULTS.md`.
- Launcher generation now uses `scripts/branding/launcher.png`, an opaque square prepared from the unchanged `assets/Icon.png` without cropping/stretching. A separately padded Android12 input respects its circular mask. The existing locked launcher/splash generators each ran once; pixel/dimension checks passed for Android, iOS and web outputs. Web icon/head references now use the generated square icons and favicon, with dark splash CSS. Native cold-launch and installed-mask appearance still require devices; source/artifact checks do not establish installability.
- Saved-theme startup has focused regression and independent QA coverage. The iOS simulator boundary evidence is above; Android and physical-device transitions remain separate, not established by widget tests.
- Password visibility buttons reuse state-aware IconButton tooltips on Login, sign-up and reset. Confirmation actions have distinct wording; reset action text is independent of validation labels. Independent widget47 and clean scoped analysis preserve masking, text and callbacks; actual iOS Login AX announces Show/Hide correctly. Full screen-reader traversal and Android checks remain separate.
- Initial/callback Loading routes use existing NoTransitionPage wrappers (independent43); Loading/Login reuse the existing1024x850 splash logo with dimensions/pulse unchanged (independent39). RootApp defers the first frame only until that logo decodes, releasing on failure/disposal without repeating on theme rebuild (root9/deep-link64). Updated iOS recordings show no blank-white interval through settled Login. The October2 recordings distinguish simulator boot's black spinner from app launch; the brief retained-splash crossfade is Flutter's existing0.2-second fade. Other platforms/devices are not accepted by these captures. Do not add arbitrary startup delays. Latest evidence: `.campaign-work/native-startup-themes-20261002/RESULTS.md`; prior evidence: `.campaign-work/firebase/full-app-build/STARTUP-TRANSITION.md`.
- Android OS-dark splash now uses #212121 with existing centered artwork through night drawable overrides and the API31 night splash background. Matching `flutter_native_splash` Android dark keys preserve regeneration behavior. The three XML files parse and independent source review accepts the four-file change. Light assets, NormalTheme and iOS are unchanged. This does not resolve an OS theme differing from the saved in-app preference or establish device-rendered contrast.
- MainActivity now selects the existing LaunchTheme instead of bypassing it with NormalTheme; Flutter's NormalTheme metadata and MaterialComponents parents remain for runtime/payment compatibility. This matches the pinned Flutter template and [official launch setup](https://docs.flutter.dev/platform-integration/android/splash-screen). Two new source regressions cover theme wiring and night resources; independent source review accepts, execution/device checks are recorded in operations.
- iOS uses a named launch-surface color: white by default, #212121 in OS dark mode. Existing logo image, aspect fit and constraints remain unchanged. `flutter_native_splash.ios=false` now explicitly protects this reviewed storyboard during regeneration; launcher generation remains enabled for iOS. QA's pre/post snapshot confirms the storyboard, launch color, native identity, Pod/Gradle files and Android NormalTheme files were preserved. No device-rendered contrast or saved-theme/OS parity is claimed.
- Official Google mark/font are integrated locally with no runtime font fetch or new SDK. Composer and independent QA pass 29 focused tests and clean scoped analysis; worker render/browser evidence was reviewed. Preserve the supplied mark's aspect ratio and scope Google Sans to its button; do not apply it as the global app font. Follow [Google's current branding guidance](https://developers.google.com/identity/branding-guidelines).
- Flutter `fontPrimary` is white in light mode and black in dark mode; `fontInverted` reverses it. Do not rename globally or assume semantic contrast from names alone.
- App-bar action icons now explicitly use `fontInverted`; the one-line change preserves gradient, navigation and notification behavior. Composer passes all 34 shared-widget tests; independent QA passes 35 including the render harness. Light-action minimum contrast improves from 2.190:1 to 7.744:1 with unchanged dark renders across 12 cases.
- Profile values now wrap within the existing row and the deletion acknowledgement dialog scrolls. Only two runtime layout changes; worker/composer/independent QA pass 49 tests, with 16 worker real-font fixtures. Deletion behavior and acknowledgement requirements are unchanged.
- Navigation dark-label contrast is independently accepted: existing foreground tokens improve minimum rendered contrast from 3.13:1 to 6.01:1. Worker/QA pass 23 tests and verify 28 before/after frame pairs preserving light appearance, icons and safe areas. Route-driven rebuilding remains necessary when using the existing NavBar in a retained shell; the patch adds no route listener.
- Settings contrast and narrow/large-text reflow pass independent 58 tests plus 8 real-font fixtures. Existing theme colors are reused; notification controls move below their labels only when the current two-line layout would truncate. Existing 45 tests, controller behavior and fitting light layouts are preserved, apart from the corrected sign-out button contrast.
- Profile field/danger-text contrast is independently accepted with only three runtime widget edits (net three lines). Existing tokens replace insufficient opacity without changing validation, deletion copy/actions, icons or geometry. Worker/QA pass 49 tests and 24 real-font fixtures; all 128 captures match. Scoped minimum contrast is 5.74:1 dark/4.94:1 light.
- Profile name/email hint and error wrapping is now integrated: six additional runtime lines reuse `fontSecondary` for dark validation text and permit three lines. Author passes 36 unchanged plus 20 new real-font cases; independent QA passes the relocated 20-case VM-only file and reviews before/after PNGs at 320px and 1x/2x text. Dark validation contrast improves from 4.47:1 to 6.01:1; light remains 7.325:1. Validators, controllers and both existing browser-compatible test files are unchanged. Full-page iOS/browser rendering remains unverified.
- Login and Legal action contrast fixes are independently accepted, one runtime line each: existing primary fill/white foreground, no layout or auth/policy behavior change. QA passes 34 Login tests plus 8 real-font fixtures, and 17 Legal plus 4 fixtures; corrected router gate passes 35 and combined app passes 1,832. Contrast is 5.14:1 in both modes; Legal's light renders are unchanged.
- Loading/ErrorView use existing opaque surface/readable tokens, with seven net runtime lines and no controller/animation changes. Independent QA passes 15 tests plus two real-font probes; five sampled frames per mode stay opaque white/#212121. This does not establish native splash-to-Flutter transitions. Login labels independently pass 49 checks: two foreground expressions reuse `fontSecondary`, preserving error text/red cues and geometry; minimum contrast 15.91 light/6.01 dark. The app-bar test's unsupported matcher is replaced with equivalent explicit assertions, independently passing 13 tests and clean scoped analysis on both pinned and installed Flutter; runtime is unchanged.
- Public missing routes now use the existing public document layout with Home/Support links, not an automatic redirect or URL reflection. Footer focus contrast and narrow/enlarged-text wrapping are repaired. Checkout's 896px breakpoint prevents intermediate-width overflow; progress/helper contrast uses existing colors without payment-state changes. Independent QA passes 46 tests, types/scoped lint, and review of 54 browser observations; local acceptance does not change hosting HTTP status behavior.
- Dark card/gradient values remain light in places. Cortina payment surfaces also mix hard-coded white and theme-derived colors. Review actual foreground/background pairs, not only color getters.
- Web `_variables.css` and surface-specific palettes are not one unified token system. No active website dark-mode mechanism was found; app dark-mode fixes do not authorize a website redesign.
- Website Home/newsletter 200% text overflow is repaired in two existing CSS rules: heading overflow wrapping and removal of the hero max-height. Independent browser26 (four text-resize and 22 existing cases), build and scoped lint pass. Text is doubled explicitly in browser tests; this is not native zoom or screen-reader acceptance. Existing support keyboard exits and normal-size behavior are retained, with no new dependency or theme layer.

## Target and Boundaries

- Checkout's remaining light-only page, app bar, payment tiles, checkout bar and washer notice now use existing dark theme surface tokens. Four new light/dark widget checks pass independently; light presentation and payment behavior remain unchanged. Actual device/result-dialog checks remain open.
- Hosted Google OAuth branding belongs to the existing `clean-stream-laundry` project (444847125705), not either new Firebase project. Homepage/privacy/terms links, the Clean Stream authorized domain and support developer contact were saved and reload-verified on 2026-09-30; Testing status, credentials, scopes and callback were unchanged. The user will supply the actual logo: do not substitute the padded app icon. No upload succeeded. The user-support dropdown still offers only the operator address. Approved scoped Admin sign-in requires an administrator account the user does not have. **The user explicitly declined an additional account:** do not create one, purchase Workspace, change IAM, or alter mail routing/aliases to force eligibility. The required Google support field remains unchanged; other configurable contacts use support. [Google requirements](https://support.google.com/cloud/answer/15549049?hl=en).

- Reuse existing tokens/components and scoped CSS. Repair incorrect states and references; do not replace the theme system, introduce a styling library, or change working layouts without a concrete defect.
- Fix logo, splash, Google sign-in presentation, both-mode contrast, and saved-theme startup together. Check buttons, dialogs, sheets, forms, maps, auth, home, wallet, and payments.
- Preserve existing content, scroll, and inputs during background refresh. Full initial loading is for no usable data; refresh errors must not erase usable content. Distinguish unknown/empty/stale states.
- All four main tabs share the retained router shell. Keep their loaded state on
  tab changes; do not add disk storage to compensate for disposing pages. With a
  usable availability snapshot, automatic refresh keeps the status and icon
  unchanged until results arrive. Progress is for first load or explicit Refresh.
  This is session memory, not an offline wallet database; leaving the shell or
  changing account still clears the retained pages.
- Refresh on entry/return, resume when stale, user action, or completed write; ignore old-user/location results. No five-second background refresh loop. Money/machine success remains server-confirmed.
- Keep theme patches separate from payment/auth logic, unrelated dirty controllers, dependency upgrades, and generated asset churn. Regenerate only required platform assets once source/config are verified.

## Verification

- Start with `flutter test test/core/theme`, `flutter test test/features/settings`, and relevant `test/features/widgets` tests. Add saved-theme startup and affected dark payment coverage with the fix.
- Website component tests: `src/components/CortinaPayPage.test.tsx`, `src/admin/AdminWorkspace.test.tsx`. Vitest disables CSS; passing them does not prove layout/contrast.
- Inspect iOS/Android light/dark screens, cold start, narrow screens, large text, focus, keyboard/screen reader, reduced motion, loading/error/empty states, and asset rendering. Use fixture-only screenshots around actual CSS breakpoints for web.
- Record before/after evidence for changed surfaces, not a new screenshot baseline for unrelated screens.
