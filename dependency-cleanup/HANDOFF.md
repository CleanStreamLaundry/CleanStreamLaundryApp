# Unused Direct Dependency Cleanup

Source-ready only. Own sparse pubspec.yaml/pubspec.lock candidate; active app
files remain untouched. No resolver, test, analyzer, build, native tool or server
was run. Only source/text inspection and existing JSON dependency-graph traversal.

## Exact Change

- Remove unused direct dio 5.9.0 and flutter_svg 2.2.0.
- Move test ^1.26.2 and mocktail ^1.0.4 from dependencies to dev_dependencies;
  constraints unchanged, preserve locked test 1.26.3 and mocktail 1.0.4.
- All other manifest text, branding/splash/assets, SDK bounds and dependency
  constraints preserved. No runtime, native, signing or test source changes.

Baseline copied with apply_patch from CURRENT active
`/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp`:
- pubspec.yaml SHA256 80d09cc9da4ce87c15508385dbe22ccd710409367e8a82fbd7c45fc2306baec4
- pubspec.lock SHA256 1140c43ae82082be8b8e26111855b9d0638b5d3ee8f9a923c64434420fabd314
- Existing package_graph.json SHA256 c8416fc011cd0ee7a4868c383945abcec544b03000320f33eb43216cbddf67fd

Candidate manifest SHA256 a35d56cc84ec75f1f2f73a0e77a1c9abc18dd9e82d78b97c10002c21817bbc6a.
Candidate lock is deliberately still byte-identical to baseline until QA resolves.

## Evidence / Expected Closure

Inspected authored lib/test, scripts, .github, Android/iOS/web/Linux/macOS/Windows
source/build configuration, config/assets references, Dockerfile/docker-compose,
package.json, analysis/devtools options and alternate yaml_V2_Cortina manifest.
Excluded generated dependency/build/cache trees; no .env values read. No Dio/SVG
package or API references, nor vector-graphics compiler/tool references found.
No runtime/tool imports of test/mocktail: package:test is used by the seven-case
QR parser test; mocktail is used across existing tests. Existing CI uses flutter
test and remains unchanged. Initial search included absent integration_test/tool/
tools directories and exited 2; repeated existing-path searches completed with
no non-test matches (rg exit 1 means no matches, not a check failure).

The current 213-node resolved JSON graph, including all root dev dependencies,
predicts exactly seven unreachable nodes after removal (206 remain):

| Removed Node | Locked Version |
| --- | --- |
| dio | 5.9.0 |
| dio_web_adapter | 2.1.1 |
| flutter_svg | 2.2.0 |
| vector_graphics | 1.1.19 |
| vector_graphics_codec | 1.1.13 |
| vector_graphics_compiler | 1.1.19 |
| path_parsing | 1.1.0 |

Existing cached dio/flutter_svg/vector_graphics_compiler manifests corroborate
those dependency edges. No surviving package points into this orphaned closure.
Shared nodes remain: http 1.6.0 (app/Supabase/map), http_parser 4.1.2 (http/shelf),
mime 2.0.0 (storage/image-picker), xml 6.6.1 (splash/image/dbus), args 2.7.0
(generators/test tooling), path/web/async/collection/meta and vector_math (Flutter).
test and mocktail remain installed as direct dev dependencies; their test-tool
closure is NOT removed. This removes seven unused packages, not merely labels;
no assertion about APK byte-size savings is made.

## QA Resolver

Only when QA's serial queue grants execution, cwd this sparse directory:

```sh
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 /Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter pub get --offline
```

Reuse existing pub cache; no copies/downloads/pub upgrade. Deliberately do not use
--enforce-lockfile for this intentional graph deletion/classification change.
Retain every surviving version, source, URL/checksum and SDK constraint exactly.
Expected lock delta: seven nodes removed, test/mocktail direct main -> direct dev,
zero additions/version changes. Stop/report anything else or a cache blocker;
do not widen bounds. Recheck manifest unchanged and review final lock before
composer integration. Generated sparse resolver metadata is not an integration
artifact; no missing lib/assets scaffolding, copied source or native directories.

## Narrow Post-Integration Gate

After composer reviews/integrates only these two files, QA can refresh active
metadata with pinned `flutter pub get --offline --enforce-lockfile` if authorized.
Do not test sparse root or claim its empty-source analysis represents the app.
In active app cwd, serialized commands under a separate QA grant:

```sh
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 /Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter analyze --no-pub
```

Composer requests whole analysis after integration; compare preexisting
diagnostics, no unrelated lint cleanup. Existing Ruby YAML is available for
structured manifest/lock comparison; no parser dependency is needed.

```sh
env CI=true FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 /Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter test --no-pub --no-test-assets --concurrency=1 test/core/di/public_policy_test.dart test/features/login/widgets/social_sign_in_buttons_test.dart test/logic/parsing/qr_parser_test.dart
```

Final composer scope supersedes earlier notification-smoke proposal: actual DI
public policy, login social buttons, seven package:test QR parsing cases. QA
records actual total including parameterized widget cases. No provider, private
env asset, browser or device. No new tests, full suite or native build justified.
Social-button tests explicitly load FontManifest.json, Google Sans Medium, its
license and assets/Google.png. The --no-test-assets command requires the existing
prepared test bundle to contain those current assets; verify that prerequisite
before running. If absent/stale, ask composer to authorize normal Flutter test
asset preparation using the already-attested public config. Do not overwrite
active .env, weaken asset assertions or invent another test harness.
Actual completed check counts: zero; resolution and execution remain QA-owned.
