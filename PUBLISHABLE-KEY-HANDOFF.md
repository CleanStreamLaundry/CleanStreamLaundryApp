# Publishable-Key Transport Verification

VERIFIED: eight cases passed, exit 0. No runtime edits.
Owned file: `test/services/supabase/publishable_key_transport_test.dart`.

Uses locked Supabase Flutter 2.17.2 / Supabase 2.16.1 / GoTrue 2.27.2,
PostgREST 2.9.1, Storage 2.8.0 and Functions 2.7.1 with pinned Flutter 3.38.10.
Reuses the existing MockClient wire-test pattern and actual public-policy
factory; no generic harness, dependency changes or SDK upgrades.

Eight cases cover four signed-in paths (REST, RPC, Storage download, Edge),
signed-out SDK REST/RPC, signed-out Storage, signed-out Edge, and public-policy
REST/RPC isolation from an in-memory signed-in SDK client. All requests use
`offline.invalid`, a synthetic `sb_publishable_` key and a synthetic session.
Only in-memory session hydration; no sign-in/out/refresh or storage mutation.
Unexpected routes, including Auth, are rejected. No Realtime channels/connect.

Verified wire distinction, not hidden: this locked SDK sends a
publishable-key fallback bearer on signed-out REST/Storage, but omits it on
signed-out Edge. The actual public-policy client sends apikey only. Signed-in
paths must send exact session bearer plus public apikey. Fake responses cannot
prove deployed gateway acceptance, RLS, Edge JWT configuration or authorize a
production key cutover. No environment or client credential files read.

Executed with pinned Flutter 3.38.10 / Dart 3.10.9 and `CI=true`,
`FLUTTER_SUPPRESS_ANALYTICS=true`, `FLUTTER_TOOL_ARGS=--old_gen_heap_size=512`:

```sh
flutter test --no-pub --no-test-assets --concurrency=1 --reporter=expanded test/services/supabase/publishable_key_transport_test.dart
```

Initial run: four passed / four failed, exit 1. PostgREST 2.9.1 requires
`response.request` during response parsing; the two fake REST/RPC responses
omitted it. Added only `request: request` to those fixtures. Rerun: 8/8,
exit 0; all exact bearer/header/session assertions retained. No code removed.

Composer-authorized active checks ran sequentially, without active edits:
`test/core/branding/branding_config_test.dart`: 5/5, exit 0;
`test/features/refund_request/controller_test.dart`: 24/24, exit 0.
Branding emitted the existing flutter_icons deprecation warning. Read-only
review found no actionable issue in the scoped metadata/path correction;
these checks do not establish browser installability or store readiness.

All test processes exited. Slot explicitly transferred to QA Descartes
`01a0f300-204c-7161-baab-8f8726580213` for the independent wallet suite.
No live gateway/provider verification performed; key cutover remains a
separate approval and deployment gate. Candidate frozen for review.
