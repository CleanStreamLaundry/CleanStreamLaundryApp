# Startup Transition Acceptance

October 1, existing iPhone 17 Pro / iOS 26.2, existing Debug Simulator artifact.
No native rebuild, sign-in, credentials, payment or permission submission during
the initial observation. Original OS appearance is light; the app-container
`flutter.themeData` key is absent. App and recorder were stopped afterward.

`startup-light.mp4` records launch through signed-out Login. The video stop tool
first rejected a missing outputFile argument; the corrected stop saved the same
recording. No second recorder was started. The local decoder initially could
not start in the restricted sandbox; its scoped native-media retry exited0
(c31667), decoding302 frames. `startup-light-frames.png` shows the first four
seconds; matching JSON contains per-frame pixel fractions, not a test verdict.

Observed: pre-Flutter black frames approximately0.358-1.298s; branded loading,
then a sliding/fading logo and near-empty white frames2.075-2.350s; Login is
visible by2.417s. The initial native black interval is NOT attributed to a source
bug or accepted as correct; Debug/simulator capture is not release evidence.
The separate outgoing loading-route transition is reproduced by real-router
regressions before a narrow page-wrapper change. Authentication, deep-link
ownership, loading controller and logo animation are outside that change.

## Route Correction

Both initial and callback loading now reuse NoTransitionPage. Independent red8
failed on default iOS500ms/Android450ms; the full nearest file then passes43
(8398d0), with clean two-file analysis (e7f0b8). Controller/URI/auth logic, inner
callback key and logo animation are preserved. Router SHA f9986b6d; test4a94855b.
The one-job incremental build passed794d9f, all ten protected inputs unchanged.
Installed and built kernel SHA4346d111 match; kernel contains exact current
router/loading source (d825fc), so this was not an old-app comparison.

`startup-light-fixed.mp4` / `startup-light-fixed-frames.png` show a shorter but
remaining near-empty white interval2.2567-2.3917s (five decoded frames), forms
by2.428s and Login logo by2.607s. Initial black persists. No-flash acceptance
therefore remains open; 43 widget passes alone did not close it.

## Existing Smaller Asset

Loading/Login decoded the original6300x5232 logo without bounds. Both now use
the already bundled1024x850 splash-logo.png; only two runtime strings changed.
Original files, dimensions, pulse and auth behavior are preserved. Independent
Logo5/Login34 pass (bc6493); analysis has no errors/warnings or new findings,
with six preexisting Login-test infos (5976b4). Nominal RGBA falls from131.85MB
to3.48MB; this is not a measured memory result. Asset covers current3x layout.

Native wrapper and tests must use matching FLUTTER_TOOL_ARGS heap512 because the
pinned launcher includes it in its cache key. The zero-case SDK-bootstrap and
localhost-denied attempts are excluded, not counted as product failures or
passes. Exact diagnostics are in the independent startup-transition/LOGO-RECEIPT.
Final changed-asset build exits0/9b07b8 with all ten protected paths unchanged.
Installed app reaches signed-out Login with six AX controls. App and video
recorder are stopped. `startup-logo-fixed.mp4` and contact sheet decode55 frames
(exit0/a59677). Login and its logo are visible together by2.230s; initial black
persists around0.377-1.235s, and four near-empty white frames remain around
1.983-2.083s. This is one debug launch, not a benchmark. The large-image input is
removed, but neither native black nor the remaining transition is marked fixed.
Frozen four source/test hashes and unchanged asset match independent QA (324eae).
The simulator remains OS-light; no preference was seeded during this check.

No all-device, native splash or saved-theme/OS parity acceptance is implied.

## First-Frame Image Readiness

RootApp now defers the first Flutter frame until its existing shared logo has
decoded. No timer, package, auth/routing change or new splash component. Failure
and disposal release exactly once; theme rebuilds do not acquire another hold.
Independent root9/deep-link64 pass together (dab6de); scoped analysis is clean.
Two missing test-only DI mocks were aligned with existing controller contracts.
Root source SHA84a66dc7, root test e52d277c, links test2bf5fae9 match QA (21a987).
One-job unsigned Debug build4f7266 passes with all ten protected paths unchanged.

`startup-first-frame-fixed.mp4` decodes53 frames (b2fa27), but stops during the
splash crossfade at2.452s. The same installed artifact, with no rebuild or setting
change, was then recorded through settled Login in
`startup-first-frame-settled.mp4`:107 frames through4.108s (586e74).
The three-second observation wait belongs only to the recorder, not app code.
The settled contact sheet shows Login complete by2.008s. Both new JSON samples
contain zero frames over94% white, versus four at1.983-2.083s before this fix
(e0a9fd). Direct visual inspection agrees the former blank interval is absent.
This is scoped debug observation, not a launch-performance benchmark.

Initial native black still appears around0.392-0.983s in the longer recording;
a brief splash-to-Login crossfade is also visible. Full platform/theme splash
acceptance remains open. Native-only independent inspection found no static
configuration defect and changed nothing. Original theme preference remains
absent after reinstall (692cdf); all app/recorder/build/decoder handles are closed.
