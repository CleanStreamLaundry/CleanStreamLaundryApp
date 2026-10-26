# Kisi phone-to-reader access

Branch: `kisi_unlock_feature`. The owner selected **phone-to-reader tap only**.
There will be **no in-app unlock button** and no customer-facing cloud-unlock
endpoint. The native Kisi SDK handles the phone/reader exchange. The existing
Flutter `DoorUnlocker` is a placeholder, not a working integration. Separate
store-preparation changes disable that flow in the working checkout; those
pre-existing uncommitted app changes are not included in this Kisi commit.

## Local sandbox: ready without hardware

Use Node 22.18+ (native TypeScript support). No additional packages, real API key,
Docker, Supabase instance, reader, controller, or Kisi account is required.

```sh
npm run kisi:demo
npm run test:kisi
```

The demo starts a temporary loopback HTTP server, exercises all eight scenarios
through the actual transport, and closes the server. It verifies provider request
and response handling; it does **not** emulate NFC, BLE, the native SDK, or a
physical tap. For a persistent local server:

```sh
npm run kisi:sandbox
curl -s 'http://127.0.0.1:8787/locks?place_id=1' \
  -H 'Authorization: KISI-LOGIN cleanstream-local-kisi-only'
curl -s -X POST 'http://127.0.0.1:8787/locks/101/unlock' \
  -H 'Authorization: KISI-LOGIN cleanstream-local-kisi-only' \
  -H 'Content-Type: application/json' -d '{}'
```

The POST above is a simulation probe, not a customer feature. Stop the persistent
server with Ctrl-C. It stores only synthetic in-memory state and never calls Kisi.
It binds to `127.0.0.1`, accepts only the synthetic credential, and has no browser
CORS. Restarting resets it.

| Synthetic door | Scenario | Client outcome |
| --- | --- | --- |
| 101 | Ready | accepted (simulated) |
| 102 | No controller assigned | controller_unassigned |
| 103 | Offline, HTTP 503 | outcome_unknown, provider code fac001 |
| 104 | Lockdown | locked_down |
| 105 | Access denied | denied |
| 106 | Rate limited | rate_limited, retry metadata |
| 107 | Provider HTTP 500 | outcome_unknown |
| 108 | Connection lost after acceptance | outcome_unknown |

The client never automatically retries an unlock. A timeout, response loss, 5xx,
redirect, or unrecognized success body cannot establish that a relay did not
fire. Even a recognized API acknowledgement is not evidence that someone opened
or passed through a door. These fixtures are deliberately a limited simulation,
not proof of Kisi entitlement or device behavior.

## Implemented transport

`supabase/functions/_shared/kisi.ts` uses Web Fetch APIs with no package imports.
It supports paginated places and place-filtered lock inventories. Hosted mode is
strictly read-only and pinned to `https://api.kisi.io`; its unlock method refuses
to dispatch. Only local-sandbox mode permits simulated unlock calls. No provider
credential may be bundled into Flutter; the future SDK receives a specific
user's device credential through authenticated server provisioning.

Official contract verified October 26, 2026:
[OpenAPI](https://api.kisi.io/openapi/apps.yaml),
[API guide](https://docs.kisi.io/platform/integrate_kisi/integration_methods/user_unlock/implement_in_app_unlocks/).
Collection responses, status flags and place IDs are validated. A returned lock
inventory does not establish physical proximity. Real proximity information must
come from the SDK, not from the location selector or invented coordinates.

## Native integration path

The official [SDK integration guide](https://docs.kisi.io/platform/sdks/integration_process/)
describes BLE on iOS and NFC on Android for phone-to-reader access. Both need a
connected reader and controller for physical acceptance. Native adapters will
initialize access after authorized user provisioning and clear credentials and
SDK state on logout, account replacement, or access revocation. The Flutter bridge
should expose lifecycle/readiness/status only, with no `unlockDoor` UI action.

- [Android SDK](https://github.com/kisi-inc/kisi-android-st2u-sdk-public):
  integrate the versioned AAR and its declared dependencies; initialize the SDK
  in the application lifecycle with the partner ID and per-user login callback.
  The documented callback's `NONE` means the phone/reader exchange completed,
  **not** that access was granted or the door opened. Do not translate it into a
  “Door unlocked” message. Confirm the selected release and manifest behavior
  before installing it; no hand-written NFC service is being added now.
- [iOS SDK](https://github.com/kisi-inc/kisi-ios-st2u-framework): integrate the
  vendor framework/package with its documented configuration and user credentials.
  Confirm the chosen SDK's permissions, background modes, credential cleanup,
  deployment target, and signing requirements before changing the Xcode project.

Both SDKs require a Kisi partner ID. The current [SDK access process](https://docs.kisi.io/platform/integrate_kisi/getting_started/request_sdk_access/)
includes an application, NDA, partner ID, and testing protocol. A dashboard login
alone does not establish SDK approval. No NDA, support email, or application has
been submitted in this batch. SDK binaries have not been installed or pinned yet.

## Existing account and vendor sandbox

Read-only signed-in inspection on October 26 found Clean Stream Laundry
organization `15601`, Madison Avenue place `38748`, and Entrance Door `77048`.
The dashboard reports that door offline and unassigned to a Kisi device. These
are observed provider IDs, not a mapping to a Clean Stream database location.
No settings, keys, grants, schedules, or real unlocks were changed. API entitlement
and the account's license/sandbox status remain unverified.

Kisi offers a [free vendor-provisioned sandbox](https://help.kisi.io/platform/integrate_kisi/getting_started/create_sandbox_account/)
through its partner process. Our local sandbox is usable now while vendor setup
is pending. Kisi also documents a hardware-free unlock response of HTTP 409 for
an unassigned controller; no such real-account probe was performed here.

## Next batch and prerequisites

1. Obtain/confirm Kisi SDK partner approval, partner ID and testing protocol, and
   whether organization `15601` is already a development sandbox.
2. Confirm the access rule and customer-to-Kisi identity provisioning. The old
   UI's local $20 balance check is not an approved server policy. Reuse the
   existing verified caller/session admission; never accept a caller-selected
   identity or place as sufficient authorization to issue device credentials.
3. Implement backend provisioning and revocation, with per-user device tokens,
   existing secure storage, audit records, rate limits, and account-switch guards.
   Restrict users to the intended doors in Kisi. No remote unlock button or
   admin-key unlock endpoint is part of this design.
4. Pin and integrate the official iOS/Android SDKs behind native Flutter lifecycle
   bridges. Keep mocked SDK events explicitly synthetic. Replace/remove the old
   disabled nearest-door/button flow when native integration lands; do not enable
   it as an interim feature.
5. Verify on physical iPhone/Android devices with the delivered reader/controller:
   foreground/background tap, sign-out/revocation, denied access, missing local
   credential, NFC/Bluetooth settings, controller offline, and provider events.

## Verification receipt

October 26: Node 26.7.0, **26 tests passed**, zero failed/skipped, including the
real loopback HTTP transport. The eight-scenario demo completed and closed its
temporary listener. Strict TypeScript 6.0.3 checking passed for all five TS files.
The already-installed sibling TypeScript binary was used read-only; no dependency
or lockfile changed. An initial restricted run passed 25 tests but could not bind
loopback (`EPERM`); the approved loopback run then passed all 26. No Flutter/native
build, hosted API check, SDK integration, or physical tap has been verified.
