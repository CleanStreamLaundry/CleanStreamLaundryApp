# Nonblocking Remote Config Setup

Source-only handoff, 2026-09-30. Local implementation/template is complete; no code
or template changes required. No remote/browser access, publishing, tests or builds
performed. Retain accepted parser/cache40 + renderer4 evidence, no rerun.

## Known Versus Missing State

Project identities/registrations are recorded in docs/firebase.md. The existing
four SDK config files are NOT exports of published Remote Config parameters.
No current Remote Config export was found in active config/firebase or the
campaign's named remoteconfig/release-policy export artifacts. Published version,
parameter existence, conditional overrides and current values remain UNVERIFIED
for both projects. Do not assume either template is empty.

| Console project | Project number | Proposed release parameter |
| --- | --- | --- |
| clean-stream-dev | 83380736317 | Same nonblocking baseline below |
| clean-stream-production | 863183154828 | Same nonblocking baseline below |

No project/app recreation, Analytics enabling, billing, realtime listeners, A/B
test, rollout, personalization, notification campaign or APNs setup is needed.
Preserve Spark and all consent-off defaults. Gundex is outside scope.

## Exact Console Settings

Use Remote Config CLIENT template / Parameters, not server template.
Parameter key: `release_policy_v1`
Type: STRING
Description: `Client release controls; not backend authorization.`
Default value (literal text, not an outer escaped JSON string):

```json
{"schema":1,"android":{"minimum":"0.0.0","recommended":"0.0.0","blocked_builds":[],"maintenance":false,"update_url":""},"ios":{"minimum":"0.0.0","recommended":"0.0.0","blocked_builds":[],"maintenance":false,"update_url":""}}
```

No conditional values on this parameter. No new conditions. Do not delete unrelated
conditions/parameter groups/parameters. Existing remoteconfig.template.json wraps
this exact value and is reusable for an empty template only; do NOT import it over
an unknown full remote template. Prefer one parameter addition/edit after snapshot.
If this parameter exists with the same complete default and no overrides, no
publish is needed. If it has a restrictive default or any conditional override,
stop for explicit review: this baseline is an intentional CLEAR, not a harmless
enablement toggle. Do not automatically discard existing rollout values.

Parser contract: blocked_builds means positive numeric build numbers, not version
strings; applies across every version reusing that build number. Minimum and
recommended are semantic versions. No exact-version block field exists. Empty
store links are intentional until real listings are verified; no guessed URLs.

## Snapshot Required From Composer

For EACH project before any separately authorized publish, capture/export:

1. Displayed project ID/number and Spark plan; confirm intended account/project.
2. Current published CLIENT template JSON, version number, timestamp, description
   and ETag if using an API export. Record explicit no-published-template state if
   console shows that, rather than inventing a version.
3. release_policy_v1 current type/default/conditional values, including any group
   containing it; relevant condition definitions/order and active rollout/experiment
   status. Keep the full export for preserving unrelated fields and rollback review.
4. Pending draft differences, if any. Do not publish someone else's draft changes.

After authorized setup, reload console and export published template/version.
Verify only intended parameter changed; parse its nested JSON and confirm BOTH
platforms have minimum=recommended=0.0.0, blocked_builds=[], maintenance=false,
update_url empty. Confirm no conditional value, experiment or personalization can
override it. Save prior and resulting snapshots separately per project. Never
force an ETag mismatch or roll back the entire project without checking other edits.

Suggested publish description: `Initialize nonblocking release_policy_v1; no
minimum/recommended enforcement, blocked builds, maintenance or store links.`
Dev first; Production needs its own snapshot/review, not a blind copy of Dev state.

## Client Verification Boundary

Console persistence proves hosted configuration, not device consumption. When QA
has a separately approved device/test slot, use explicit matching environment
defines and verify current Firebase app/project identity. For a fresh valid
nonblocking policy, a successful eligible fetch/activation and successful cache
write must leave browsing allowed with no update prompt or maintenance screen.
Optional Analytics/push/FIAM remain off; release checks must work without opt-in.
Offline restart after successful persistence should remain allowed.

Current SDK settings are eight-second timeout and 12-hour minimum fetch interval.
Manual refresh does NOT bypass that interval; repeated taps do not prove a new
network fetch. Use an eligible test installation/window and record actual fetch
success/activated policy, not only a button press or unchanged screen. No runtime
interval changes or realtime listener are proposed for this setup.

Missing/invalid remote data retains the previous policy; an empty SDK default is
not an approved clear. A device retaining an old cached block must successfully
fetch AND persist the explicit nonblocking policy before claiming it was cleared.
Do not clear user app data merely to hide that behavior. Blocking/maintenance
scenarios stay in accepted local fixtures until separately approved Dev-only tests;
this setup publishes no enabled restriction even in Dev.

Official template/version guidance:
https://firebase.google.com/docs/remote-config/templates
Official Flutter fetch/default guidance:
https://firebase.google.com/docs/remote-config/get-started?platform=flutter
