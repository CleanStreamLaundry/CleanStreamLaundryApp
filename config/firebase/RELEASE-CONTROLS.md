# Local Release Controls

Local review artifacts only. Nothing here publishes configuration, creates a
project, requests credentials, enables billing, or sends notifications.

## Reproduce the Template

From the repository root, use Node 24 and the pinned Flutter 3.38.10 from the
[toolchain reference](../../docs/dependencies.md). Resolve those versions on
PATH first; do not substitute a newer global Flutter. Follow any active
serialized-test gate in [operations](../../docs/operations.md).

```sh
node --version
node --test scripts/firebase-release-template.test.mjs
node scripts/firebase-release-template.mjs
```

The last command prints the checked-in `remoteconfig.template.json` to stdout.
An optional input path renders another reviewed policy JSON. The renderer only
wraps JSON; it does not replace Dart's authoritative `ReleasePolicy.parse`.
Run the focused parser/cache tests only with the pinned toolchain available:

```sh
flutter --version
flutter test test/services/firebase/release_configuration_test.dart
```

## Policy Contract

`release-policy.example.json` is the nonblocking baseline for both projects.
The template has one STRING parameter, `release_policy_v1`, containing that
complete JSON document, without conditional values or analytics targeting.

| Field (per android/ios) | Meaning |
| --- | --- |
| `minimum` | Semantic version below which the client is blocked; inclusive floor |
| `recommended` | Versions below this are prompted; must be at least minimum |
| `blocked_builds` | Positive integer build numbers, blocked regardless of version |
| `maintenance` | Boolean; maintenance takes precedence over version/build decisions |
| `update_url` | Empty until the actual store listing is verified |

Build blocks apply to every version on that platform with the same numeric
build number. There is no exact-version block field in schema 1. Do not add an
unrecognized field and assume clients enforce it.

Android links must be HTTPS `play.google.com/store/apps/details` with `id` equal
to `com.cleanstreamlaundrysolutions.clean_stream_laundry_app`. iOS links must be
HTTPS `apps.apple.com` paths ending in `/id` followed by digits. The parser
rejects credentials, explicit ports and fragments. A parser-accepted URL is not
proof that the listing belongs to Clean Stream. Verify ownership and availability
before filling either link; test fixture IDs are not production listings.

The driver's empty SDK default is intentional: it is not a remotely approved
clear and must fail parsing instead of replacing a previously cached block.
With no valid cache, `ReleasePolicy.safe()` permits browsing. Fetch or parse
failures retain the previous policy. If a cache write returns false or throws,
a valid fetched block or maintenance policy is still enforced in memory;
a nonrestrictive replacement is not applied, preserving any current restriction.
Successful writes allow all valid replacements, including an explicit clear.
Failed writes produce a diagnostic: after restart the older durable cache may
still apply, so in-memory enforcement is not proof of offline durability.
The nonblocking template is an explicit clear if later published, not a harmless
merge.

## Review Before Any Separately Authorized Rollout

1. Keep dev (`clean-stream-dev`) and prod (`clean-stream-production`) distinct.
   Existing four SDK configurations and Gundex remain untouched.
2. Review the current remote template before any future merge. This local
   one-parameter template must not overwrite unrelated remote parameters.
3. Verify real store URLs, available release versions/builds, and a recovery
   release before setting a minimum or build block. Record the prior policy for
   rollback. Review maintenance independently per platform.
4. In a separately approved development environment, verify each decision,
   offline restart with a known block, invalid policy retention, explicit clear,
   and access to privacy controls. No realtime listeners are introduced.
5. Carry forward the prior independent Firebase privacy/native integration and
   token-backend acceptance recorded in operations. Notification/native rollout
   status is composer-owned; this release-template work neither reopens that
   acceptance nor supplies new credentials, provider calls or delivery evidence.

Keep the existing consent, allowlisted notification destinations, admission
checks and token cleanup. The soft admission-recheck behavior intentionally
preserves push consent; this configuration work does not change it.
