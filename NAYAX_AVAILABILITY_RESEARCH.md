# Nayax machine availability research

Updated October 19, 2026. **The existing Production Lynx token now works for the
physical reader.** Sandbox callback header authentication is configured/deployed;
manual Samsung availability testing has begun. The older permission failures and
unconfigured-header findings below are superseded by today's direct evidence.

## Current result — October 19

At approximately 14:08–14:10 UTC, the existing Core user 230347447 and token
returned **HTTP 200** for reader 4434331126150568 → machine 79835724, `status`,
`lastAlerts`, `lastSales`, actor hierarchy, operator device inventory, alternate
machine lookup and operator role groups. Token/base digests match hosted
configuration. No credential replacement, role grant or reader setting was needed.
This is the regular Core account containing the physical reader; the separate QA
account is not required for these reads. The cause/timing of the earlier 403s is
not established and no longer blocks this integration.

**Availability:** the owner chose manual Samsung checks. With the initial state,
Madison Ave showed 1 washer available; after grounding INHIBIT and refreshing,
it showed none available. Direct events confirm 70/Pulse Inhibited at
14:11:59.400 UTC and 71/Pulse Resumed at 14:12:48.630 UTC. The backend cached
idle/71 at 14:12:54.189 UTC (5.559 seconds after the provider event timestamp;
this is not a measured wire-to-screen SLA). Its busy row was already superseded
when inspected. Owner confirmation of release/restored app count, sustained
offline/recovery and a physical laundry cycle remain open.

Observed Device/Vending code 24 is “VMC Power Up Occured.” The existing restart
guard recognized only code 1, so it now also invalidates pre-24 pulse states.
Six availability cases and Deno entrypoint typecheck pass. Availability v47 is
ACTIVE, with all four downloaded runtime files matching the tested local source.
Authentication and existing Home/foreground/manual Refresh behavior are preserved.
No repeating timer, client build or Samsung installation was introduced.

**Pricing:** Core history shows reader 0568's price array changed September 28
from five values to `1000,800`; the app retained code 3/$4. Core logged code11,
“product price is 0.00 on server - auth failed,” at the original October 19
11:22:06 machine-local test time (15:22UTC). The owner chose the existing $8 option.
Only sandbox machine 1's mapping/rate changed, atomically, to code 1/800 cents;
Machines.Price and the actual browser quote both read $8. The original $4
support-required session remains untouched. Reader configuration was not changed.

**Callbacks (latest result): successful at21:48:36UTC.** Session
`f46dad1b-dc66-457d-984f-4306f6c2959c` / transaction
`b696a7656d8d423dbd799b7427c9b558` / Nayax4903267080 has one Start,
authenticated Sale, matched SaleEnd, status `started`, 800cents/USD, no refund.
The browser renders “Machine started.” Bare-reader provider completion is not
physical laundry-start or cycle-completion evidence.

The original saved pair exposed our sandbox username transfer error (corrected
21:14UTC). Actual21:35 traffic then exposed HTTP Basic instead of our assumed
separate headers. Exact Basic pair validation now works. The next final callback
revealed missing BasicInfo amount/currency, AuthAmount=0 and SettAmount=8.
The handler now requires the exact settlement and same-session authenticated Sale
with matching provider ID, frozen environment/device and amount/currency before
recovering omitted currency. Present conflicts remain denied; audit provenance
is explicit and SQL guards are unchanged. 237 checks/typechecks pass; sandbox v68
and development's production-route v64 are downloaded/byte-verified. Production
pair absent and unauthenticated requests denied; production vending remains off.

The21:46 fresh attempt still canceled before any recorded callback; the21:48
fresh attempt succeeded. Reception is a possible contributor, not established.
All historical unknown sessions remain untouched without repeat Start/refund.
The existing unsent Cortina reply now asks only for Production credentials via
the secure method and callback routing confirmation. No Yael/Lynx access request
is needed. Owner sends correspondence.

Guest website/app public-key mismatch is fixed by the existing exact-name resolver
in cortina-vend v65;21 checks/typecheck pass and actual sandbox browser checkouts
now reach Stripe success. Authentication/admission and financial guards remain
intact. Current detailed receipts and baselines:
`../.campaign-work/nayax-pulse-review-20261019/` and
`../.campaign-work/nayax-auth-verification-20261019/`.

**Inventory/reporting:** second reader 4434331126150748 resolves to machine
122693305 under the same actor. It is offline with no reported keepalive/power-up
time; no app machine or dryer assignment was inferred. The three available $4
Last Sales records all match existing sessions by Nayax transaction ID AND
PaymentServiceTransactionID, amount and USD currency: two wallet spends ($8),
one Stripe card vend ($4). The $12 describes machine activity; it is not $12 of
additional Nayax collections. Historical mode/environment snapshots are NULL,
so mode is not inferred/backfilled. Direct-reader card records, complete export
coverage, refunds and fees still require evidence before a complete combined
collections report can be claimed. Location finances remain deferred.

**Correspondence:** Outlook Sent Items confirms the earlier Yael escalation was
sent by the owner at 9:53 AM October 19. A correction reporting successful access
is saved **unsent** in case 03713828 with Yael and ProfessionalServiceSF as the
same recipients. The earlier draft should have been checked against fresh API
results before being cleared for sending. No message was sent by this chat.

Evidence: `../.campaign-work/nayax-setup-20261019/` contains sanitized API reads,
`hosted-callback-auth.json`, `callback-tests.log`, `manual-test-receipt.json`,
`manual-availability-events.json`, `reporting-match.json`, exact before/after
deployment source and `yael-followup-draft.png`. Credential values are excluded.

## Email review — October 19

This earlier review is historical; the fresh verification and sent/draft status
above supersede its pending items.

Reviewed the original Lynx and Cortina threads, and searched Outlook **All folders**
for `from:nayax.com received:10/14/2026..10/19/2026`. The search returned Maxim's
October 15 Cortina response and Kevin Tracy's October 14 hardware message. No
newer Yael response was found; her latest substantive reply in case **03713828**
remains October 8. This is a mailbox-search result, not a quarantine audit.

**Yael reply is reviewed, saved in the existing thread and unsent.** Matched its
timestamps, IDs and correlations to the four saved October 14 evidence files.
Replaced stale “today” wording with October 14 dates, identified `dually-app\jacking`
as the **User login shown under Account Settings → Security and Login**, and added
the accurately limited console observation: successful login/configured
authorization, empty operation sections, no independent machine request. The
reply asks politely for the exact user/role/permission or self-service setting;
it does not claim the physical-reader app flow passed. Original recipients
(`yaelsc@nayax.com`, `ProfessionalServiceSF@nayax.com`), signature and quoted
history are preserved. No credential secret is included. Outlook confirmed saved
October 19 at 9:41 AM. The owner will send it.

**Cortina authentication has a new actionable answer.** In case **03401910**,
Maxim's October 15, 3:08 PM email says he added fields at operator level that will
be sent as request headers and configured credentials for the Sandbox operator.
His inline screenshot identifies separate system names **`username`** and
**`password`**. A secure credential link is present; it was not opened or copied
into project evidence during this review. This supersedes “waiting for Maxim to
identify/configure a method,” but is not proof of actual callback delivery or
backend compatibility. Next: inspect current backend configuration, retrieve the
credentials securely for their intended use, support and configure the separate
headers, then verify authenticated Sale/SaleEnd/Void and reject invalid credentials.
No production-operator configuration was confirmed by this message. Maxim says
he is away until **November 2**, with **Shachar Holzer** providing backup subject
to team availability. No additional support email was drafted or sent.

Kevin's October 14 message confirms **$269 per device** conditional on taking an
additional **50 by year-end**; the thread contains the owner's October 13 statement
that the extra 50 would work at that price. This review did not accept commercial
terms, place an order or verify shipment/payment.

Remaining Nayax work: production Lynx permission resolution and a fresh successful
read of reader 0568; callback-header implementation/configuration and real delivery
verification; reader connectivity and an end-to-end Inhibit/Resume app-count test;
additional machine/dryer mapping; and combined Stripe/Nayax reconciliation. No API,
backend, device or financial operation was run during this email review.

Reviewed draft and screenshot: `../.campaign-work/nayax-review-20261019/`.

## Current result — October 14

### Signed-in production console check — October 14

After the owner asked to try the previously unfamiliar page, entered the existing
Core `User login` value `dually-app\jacking`; the owner entered the password and
successfully signed in. The resulting URL is
`https://lynx.nayax.com/operational/swagger/index.html`. This verifies that the
existing Core credentials work for the console; no separate account was created.

Entered the existing LYNX token with **Set Token**. The Swagger **Authorize** dialog
then displayed **Authorized**. This only establishes the console's configured
authorization state, not a successful API request. Expanded Machines, Permissions,
Actors and Cards showed no operations. A page reload still showed empty expanded
Machines/Permissions sections; the API Token field was empty after reload.
No new machine/role API request could be executed through this console. Do not
interpret its empty sections as proof of a particular missing permission or a
successful/failed independent machine request. The earlier direct 403s remain the
verified provider responses. **Get New Token** was not used.

The linked `/Operational/swagger/v1/swagger.json` downloaded through the browser
to `/Users/jamaki604/Downloads/swagger.json`, but macOS denied filesystem reads,
the document viewer did not open it, and the browser-local file chooser required
extension file-URL access. No OS/extension permission was changed and no file was
uploaded. An unauthenticated fetch of the same URL returned 302 with redirects
disabled, so no public catalog content was obtained. No claim about its path or
role contents is supported. The temporary local viewer exited; research tabs
were closed. The signed-in console remains open for the owner, and in-memory
token variables were cleared. No credential, permission, device setting, backend
configuration, deployment or payment changed. Yael's existing draft remains
unsent and unchanged by this console check.

Evidence: `../.campaign-work/lynx-live-20261014/lynx-console-observation.txt` and
`lynx-console-signed-in.jpg` in the same directory.

### Operator role diagnostic — 20:05 UTC

The owner signed back into the familiar production Core portal. Confirmed user
**230347447**, `dually-app\jacking`, and reused the existing unexpired LYNX token.
The separate Swagger-console login is optional; the earlier request to sign into
it was withdrawn. No additional account or credential is needed for these checks.

`GET /v1/actors/2003775356/roleGroups` returned **HTTP 403, Insufficient permissions
to perform this action**, correlation ID **tfemczdyyEaTrBMx**, at
**2026-10-14T20:05:10Z**. The token and base URL again match the previously verified
hosted configuration. No group IDs were returned, so no group-detail requests or
role mutations were attempted. This diagnostic cannot expose the current role
assignments with the available credential. It does not identify the exact missing
permission or prove that no self-service setting exists anywhere.

Together with the earlier hierarchy/inventory/machine denials, the result supports
asking Yael to inspect the exact production user's endpoint permissions. The broad
documentation and available Core UI review found no supported local correction.
Added this final diagnostic to the existing reply in case **03713828**, preserving
the recipients, original content, signature and quoted history; **not sent**.
Maxim's callback-authentication email was already sent by the owner.

Sanitized evidence: `../.campaign-work/lynx-live-20261014/role-api-evidence.json`.
The one-shot fixed-host read-only probe exited and stored no credential. No device
settings, credentials, permissions, app code or deployed configuration changed.
Remaining dependencies are the precise production API permission correction,
Maxim's callback-authentication contract, and a connected physical reader for the
subsequent end-to-end availability test.

### Broader documentation audit — 19:56 UTC

The owner challenged whether every available document had been checked and reported
that the callback-authentication email to Maxim was sent. The earlier review was
targeted, not exhaustive. Do not describe all self-service diagnostics as exhausted.
The existing reply to Yael remains unsent and was not edited during this audit.

Downloaded all **180 pages in the official Lynx index**, all **11 transaction/event
delivery guides**, **80 Cortina pages**, **6 Core Extension guides**, **4 general
portal pages**, and the **Lynx and Cortina OpenAPI specifications**: 283 successful
downloads, no failed URLs. Searched this corpus for authentication, permissions,
roles, environment selection, activation, token renewal and event delivery, then
read the relevant setup/authentication/reference sections. This is a reproducible
full-text coverage check, not a claim to have read every unrelated page word for
word or every private/unindexed Nayax document. The unrelated 240-page terminal
SDK index was not expanded because this integration uses server-side Lynx/Cortina,
not a custom terminal SDK application. Earlier Pulse hardware and Core configuration
evidence remains applicable.

New findings:

- [Widget API permissions](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/reports/retrieve-machine-widget-data#permissions)
  explicitly documents endpoint-specific menu permission keys and distinguishes
  401 from a 403 caused by a missing permission. This is evidence about widget
  endpoints; it does **not** identify the exact permission key missing from our
  machine/actor requests. The general phrase “Lynx permissions granted” is not
  sufficient evidence that every required endpoint is enabled.
- Two documented read-only diagnostics were not tried in the earlier audit:
  [operator role groups](https://devzone.nayax.com/reference/lynx/actors/get-all-actor-groups-by-actorid),
  `GET /v1/actors/2003775356/roleGroups`, and
  [roles in a returned group](https://devzone.nayax.com/reference/lynx/lookups/get-group-roles),
  `GET /v1/group/{GroupID}/roles`. The latter returns role names and `CKey` values.
  Use only group IDs actually returned for the operator. Actor-level groups are
  not, by themselves, proof of the individual user's effective permissions.
- The October 2 **QA User Creation Is successful** email points to the Lynx
  Swagger console. The [SQS encryption guide](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/set-up-nayax-core/set-up-encryption-on-amazon-sqs-delivery)
  independently documents `https://lynx.nayax.com/operational/signin` with existing
  Core credentials. This console is optional. The owner did not recognize the
  page, so the console sign-in request was withdrawn; the existing token from
  the familiar Core portal was used for the role diagnostic above instead.
  No console sign-in or console API success is claimed.
- Rechecked the original August 14, 2025 **Nayax Payment Solutions** email and
  its 12-page **Solution proposal and SOW - Cortina API- Bee Clean.docx** attachment
  through Outlook's rendered accessible Word view. Section 2.4 discusses Lynx
  prepaid-card creation, updating, lookup and top-up. It does not specify the
  machine-status/last-alerts permissions. A narrower original permission scope
  is therefore a hypothesis to test, not an established cause. The proposal is
  historical and is not evidence of the currently granted permissions.
- The current Security & Token guide and machine/actor OpenAPI entries agree
  with our existing opaque LYNX key sent as `Authorization: Bearer ...` and the
  production `/operational` base. No mandatory token exchange for this key type,
  token replacement after a role grant, extra operator header, or per-device
  Lynx activation requirement was found. App JWT tokens and embedded Core
  Extensions have separate setup requirements; neither is a proven fix here.
- SQS remains a documented alternative event-delivery transport, requiring an
  AWS queue and Core Events Report permission/configuration. Its availability
  to this account has not been established. It was not provisioned or activated.

Evidence inventory: `../.campaign-work/lynx-live-20261014/public-doc-audit/manifest.json`,
`auth-and-setup-search.json` in the same directory, and
`../.campaign-work/lynx-live-20261014/proposal-review-evidence.txt`.
The proposal download event could not be captured; its contents were read through
the authenticated Outlook viewer instead. No attachment was edited.

**Diagnostic follow-through:** the documented operator-group read was attempted
with the existing Core token at 20:05 UTC and denied, as recorded above. Returned
group details therefore could not be inspected. Do not mutate roles, generate
replacement credentials, or change device settings based solely on the existence
of these endpoints. The precise missing permission remains unverified.

### Device setup and account-level isolation — 19:14 UTC

At the owner's request, re-inspected the regular `my.nayax.com` account after a fresh sign-in, reviewed the developer guides/OpenAPI reference and Nayax University role matrix, and checked for an enablement we could apply ourselves before asking Yael.

- Reader **4434331126150568** remains assigned to machine **79835724**, operator **Clean Stream Laundry Solutions - DEV**. Machine status is **Active**, profile **Cashless + Telemetry**, communication mode **MQTT Enabled**.
- General → Pulse/ccTalk shows **Pulse Inhibit = 01, active on logic 0** and **Inhibit Event Timeout = 5 seconds**. Queue shows both values collected on **September 28 at 17:41:56**, **Sent Success**. These are portal-displayed timestamps. Nothing needs to be enabled again for the previously verified Inhibited/Resumed events.
- Reviewed all five pages of the available attribute catalog (994 entries), including disabled attributes. No documented per-device Lynx GET authorization toggle was found. A catalog item called **Lynx Port No** is not evidence of an API permission switch; no network/port/device attributes were changed.
- The device is currently silent: **last communication October 7, 19:07:14** in the portal. A new physical transition test will need the reader powered and connected. This is separate from account API access.
- Account Settings confirms active **dually-app\jacking**, user **230347447**, and the existing unexpired **LYNX** token. Administration → System Users, filtered to the DEV operator with no user-name filter, returns **No Data**, including with Active selected. That screen did not expose this user's editable role assignments; this does not establish the user's exact granted roles.
- [Security & Token](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/security) documents reusing the existing Lynx key as Bearer. The separate [App Token guide](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/app-tokens) requires Nayax-admin-assigned scopes and explicitly describes the same insufficient-permissions 403; creating an App Token is not a self-service fix for this existing LYNX key. No credential was created or replaced.
- [Pulse configuration](https://nayax-u.nayax.com/scenario/understanding-attributes-and-configurations-pulse-11715) confirms the Inhibit event timeout controls alert delivery to the server. [SQS Events Report setup](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/set-up-nayax-core/set-up-events-delivery) is a separate push-delivery setup, not a prerequisite documented for Lynx GETs. No SQS service, subscription or queue was activated.
- Nayax's public role workbook (`../.campaign-work/lynx-live-20261014/nayax-user-roles.xlsx`, six sheets) was read without changes. It maps Core screens and does not list a Lynx/API entitlement. It cannot establish which API scope is assigned to our user.

At **2026-10-14T19:14:06Z**, reused the same existing production token for three additional documented GETs. Token/base digests again match the hosted configuration. All returned **403, Insufficient permissions to perform this action**:

| Read | Path | Nayax correlation ID |
| --- | --- | --- |
| Current user's hierarchy | `/v1/actors/hierarchy` | `Iri48aDiAku0b8S4` |
| DEV operator devices | `/v1/devices?ActorId=2003775356&pageSize=10` | `YI1LzrcuBUq3Tspx` |
| Alternate documented machine lookup | `/v1/machines?DeviceSerial=4434331126150568` | `bQ0Z0fny70SVh3X0` |

The [current-user hierarchy](https://devzone.nayax.com/reference/lynx/actors/get-actor-hierarchy-for-current-user) request supplies no device or machine ID. Its rejection isolates an account/API permission problem from the Inhibit trigger, reader connectivity, or our specific machine lookup. No supported local enablement resolving that denial was found; the exact provider assignment remains unverified.

Sanitized results: `../.campaign-work/lynx-live-20261014/account-api-evidence.json`. The fixed-host probe denied redirects, used the credential only in memory and exited. The existing **unsent reply** in Yael's Lynx case **03713828** now includes the device checks, account-level denial and exact user ID, and asks for the precise self-service role/setting if one exists. Original recipients, signature and quoted conversation were preserved. Nothing was sent; Maxim's separate callback-authentication draft was unchanged.

### Authorized reader verification — 15:35 UTC

After the user completed Nayax SMS sign-in, verified the active operator **Clean Stream Laundry Solutions - DEV**, login **`dually-app\jacking`**, user ID **230347447**. Reused the existing **CleanStream machine availability** Lynx token (`cleanstream-availability-20260928`). Hash comparison confirmed it and `https://lynx.nayax.com/operational` exactly match the hosted `NAYAX_LYNX_TOKEN` and `NAYAX_LYNX_BASE_URL` configuration; neither secret was changed.

At **2026-10-14T15:35:30Z**, all four documented read-only requests returned **HTTP 403: Insufficient permissions to perform this action.**

| Read | Path | Nayax correlation ID |
| --- | --- | --- |
| Device mapping | `/v1/devices/4434331126150568/machine` | `pNaTHxY8A0SHvMOm` |
| Machine status | `/v1/machines/79835724/status` | `0itG2jMzh0G9XybF` |
| Last alerts | `/v1/machines/79835724/lastAlerts` | `JS0qY9ANq0mfWBQe` |
| Last sales | `/v1/machines/79835724/lastSales` | `lLUm2I60qUSQqN0v` |

These requests went directly to Nayax, so the rejection is independent of Clean Stream's callback authentication or app-session checks. The result does not identify which Nayax role/account assignment is wrong; ask Nayax to inspect this exact user/token/endpoint scope rather than claiming a particular cause. Re-read Yael's actual message: it confirms user-level permissions but does not identify the user ID that received them. Current public token guidance permits reuse of an existing Core Lynx token; no documented need to replace it after a grant was found. No speculative credential replacement was performed.

The correct Clean Stream Supabase project was verified healthy and linked. Its read-only mapping still points **Washer 1 → reader 0568 → machine 79835724**, enabled in sandbox. Downloaded deployed `machine-availability` index, logic and admission code match local source byte-for-byte. The backend's stored provider failure still dates to October 3; this probe did not impersonate an app user or modify its cache. Current secret-name inventory also confirms `NAYAX_CALLBACK_AUTH_TOKEN` remains absent, a separate Cortina configuration issue.

Sanitized evidence is in `../.campaign-work/lynx-live-20261014/reader-api-evidence.json` and `setup-evidence.json`. The four-request fixed-host probe used the credential only in memory, denied redirects and exited. No charges, refunds, starts, settings, credential grants, deployments or callback changes occurred. No successful real-reader API data or app transition is claimed. The portal dashboard also showed both readers silent over 24 hours; this is separate from the permission rejection, and a later live transition check needs a powered/connected reader.

**Next dependency:** Yael needs to investigate why the confirmed permissions do not allow these four reads for the existing DEV login. The owner explicitly assigned Lynx to Yael, not Maxim. The [unsent Maxim draft](NAYAX_MAXIM_AVAILABILITY_EMAIL.md#follow-up-preparation--october-14) in Cortina case 03401910 now asks only for the callback authentication contract. A separate reply to Yael and ProfessionalServiceSF is prepared, unsent, in Lynx case 03713828. It contains both verified user IDs, the fresh QA success and four Production request correlation IDs, and asks which Production user received the grant. Body and screenshot: `../.campaign-work/lynx-live-20261014/yael-draft-body.txt` and `yael-draft.jpg`. No additional permissions request was sent.

### QA account recheck — 16:06 UTC

The owner signed into `qa.nayax.com` successfully. Account Settings identifies **`nayaxvend\JacobKing`**, user **1000870211**, email `jacob@cleanstreamlaundry.com`, operator **Clean Stream Laundry Solutions LLC**. This is a separate Nayax user from Production/DEV `dually-app\jacking` (230347447), even though both use the same email. The QA portal lists exactly one **Test Machine**, ID **1003684111**, actor **2011248072**; it is not reader 0568.

Reused existing `Clean Stream Lynx QA` / `cleanstream-lynx-qa` for three read-only requests at **2026-10-14T16:06:11Z**. Status, lastAlerts and lastSales all returned **HTTP 200**. MQTT is false, keepalive/powerup dates are null, and alerts/sales are empty. Sanitized results: `../.campaign-work/lynx-live-20261014/qa-api-evidence.json`. The fixed-QA-host probe denied redirects, kept the credential in memory, and exited. No new token or backend replacement was made. This confirms QA access only; it does not resolve the physical-reader Production 403s.

**Reporting direction confirmed by the user:** combine Stripe reporting with Nayax reporting/exports to produce the full financial picture if Nayax's API cannot supply every field. Use matched periods, currencies, sources and transaction identifiers where available. Stripe collections, direct-reader collections, wallet loads and wallet redemptions must remain distinct; a Nayax record for an app-funded vend is not additional money collected. Calculate a residual only after reconciling its inputs and label unexplained differences rather than inventing certainty. Location finances and per-location routing are deferred for now.

### Earlier email/status review on October 14

Reviewed the Outlook chains and recent Nayax mail through October 14, and consulted **Prioritize app fixes**, **Integrate Cortina QR payments**, and **Redesign Clean Stream website**. This is a status review, not fresh hosted/API/device acceptance or a deployment. The consolidated remaining-work list is [Current Work Order](APP_FIX_PRIORITIES.md#current-work-order).

- **Lynx permission request answered.** In [Yael's October 8 reply, case 03713828](https://outlook.office.com/mail/inbox/id/AAQkADVhNGJkNTVmLTUzMDAtNDhkMy05ZDAwLTAwNDJhNzBjMzAzMgAQAA9BZ5rOjgNKj7OPsiL%2FjmE%3D), she says Production Lynx permissions were granted to the user, not a particular machine/device. Do not send another permission request first. Verify the existing account/token with read-only device lookup, status, lastAlerts and lastSales for physical reader `4434331126150568`, machine `79835724`. A provider-reported grant does not establish that the stored credential now succeeds. Production Lynx access does not itself enable production payments.
- **Pulse/SaleEnd interpretation answered.** Yael explains that Pulse has no vend-failure feedback, so SaleEnd will likely be received even without reliable evidence of physical machine operation. Use the selected Inhibit events for availability; do not treat SaleEnd as proof a washer started or finished. Exact callback timing with the disconnected bench reader remains an empirical check, not a reason to repeat the broad question.
- **Last Sales depends on callback acknowledgment.** Yael says a transaction appears in Last Sales only after Nayax receives our SaleEnd response. Therefore an absent row cannot independently prove a failed vend when callback delivery/acknowledgment is uncertain. Preserve the October 3 unknown-outcome session until positive, correlated evidence supports resolution; absence alone must not trigger a refund, reversal or another Start.
- **One provider configuration question remains:** the exact incoming Cortina callback authentication scheme, header names/encoding and provisioning arrangement. [Maxim's October 6 reply, case 03401910](https://outlook.office.com/mail/id/AAQkADVhNGJkNTVmLTUzMDAtNDhkMy05ZDAwLTAwNDJhNzBjMzAzMgAQAEa%2BFGiI1CpBuUwHox9bIrM%3D) offers operator-level username/password headers without specifying their contract. Yael explicitly refers this to Maxim because Cortina is separate from Lynx. No newer answer was found in the reviewed mail. Existing code accepts `x-nayax-auth` or a Bearer token; do not assume compatibility or weaken authentication. The October 14 secret-name inventory independently confirms the backend secret remains absent. Confirm and match both sides before another funded vend test.
- **Reporting questions are sufficiently answered to continue our own investigation.** Last Sales is limited to 30 days, PaymentMethod separates direct credit-card payments from the Clean Stream method, fuller reporting uses SQS/SFTP/email, and processing fees come from weekly statements. Still obtain populated reader data, validate identifiers and corrections, implement durable capture, and join app wallet/Stripe vends without counting them as new collections. These are implementation/evidence gaps, not unanswered versions of the original questions.
- **Availability remains unverified end to end.** Recheck events 70/71, their category/source, timestamps, latency and recovery through the actual reader/backend/app path. Preserve Home-entry/foreground/manual refresh and no repeating Home timer. SQS is optional future delivery work, not required to perform the existing read-only checks.

The October 6 request was sent by the user; the sent message appears at 3:06 PM in the Lynx chain. The [saved preparation text](NAYAX_MAXIM_AVAILABILITY_EMAIL.md) is historical, not an unsent draft. No external email, payment, credential change or deployment occurred during this October 14 review. Earlier sections below are dated evidence and do not override this checkpoint.

## Current result — October 6

Historical checkpoint, superseded by the October 14 update above for permissions, SaleEnd semantics and sent-email status.

- Completed the user-approved token creation in **qa.nayax.com**, user **JacobKing**: reference **Clean Stream Lynx QA**, token ID `cleanstream-lynx-qa`. The ID is our readable label, not a device number or token secret. The credential was used only in memory for QA checks and was not written to source, logs, the app, or the existing production backend configuration.
- At **2026-10-06 18:04 UTC**, authenticated GET requests to `https://qa-lynx.nayax.com/operational/v1/machines/1003684111/status`, `/lastAlerts`, and `/lastSales` all returned **HTTP 200**. Actor `2011248072`, machine `1003684111`: `MachineMQTTStatus=false`, `LastPowerUpDateTime=null`, empty alert and sales arrays. This proves access and response handling, not real-machine transitions, populated sales schemas, or production access.
- The existing availability parser correctly returns `unknown` / `offline` for that actual QA response. All five focused event-reconciliation tests pass. Sanitized evidence and the one-shot, fixed-QA-host probe are in `../.campaign-work/lynx-qa-20261006/`; the temporary loopback server exited after the check.
- A current read-only hosted database check confirms the app still maps **Washer 1 → reader 4434331126150568 → Nayax machine 79835724**. Its last stored check is October 3, 12:46:12 UTC, `unknown`, HTTP 403 on alerts/status. This is stored evidence, not a fresh October 6 production API request. The production portal requires sign-in; no reader mapping or production credential was replaced with the simulated QA machine.
- Yael's October 4 email states that Nayax grants Production Lynx permissions after QA testing. The required next request is access on the **existing Clean Stream Laundry Solutions - DEV account** for device lookup, status, lastAlerts and lastSales. Production here is the Lynx environment; it does not authorize live card charging or moving the reader between operators.
- Current deployed callback source requires `NAYAX_CALLBACK_AUTH_TOKEN`, but the correct Clean Stream project's secret-name inventory does not contain it. The handler consequently declines callbacks before parsing/logging them. Maxim's October 6 reply says incoming Static QR authentication is absent by default and Nayax can configure username/password headers. The exact header names/encoding and secure provisioning path are not specified in that reply or the reviewed Static QR documentation. Keep authentication enforced and arrange matching provider/server configuration before another funded vend test. A recent October 3 wallet session remains `support_required` / `vend_outcome_unknown`, without a Nayax event or transaction ID; do not infer its financial outcome or compensate it based only on this diagnosis.

### Questions resolved without another email

- [Lynx security](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/security): we create the QA token ourselves; QA and Production use separate credentials. The app continues to call our authenticated backend, which holds the appropriate provider credential.
- Maxim confirmed lastSales covers 30 days, `PaymentMethod` distinguishes credit card from the Clean Stream payment method, and no full historical/corrections query exists. The published schema contains `TransactionID` and `PaymentServiceTransactionID`, but no explicit RRN field. September 30 portal-to-database matching below already proves three existing externally funded vends; a populated API sample is still needed to validate API joins. Do not count those vends as new collections.
- [Transaction delivery](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/set-up-nayax-core/set-up-transaction-delivery): Core supports SQS and hourly/daily SFTP/email CSV/XML reports. Required roles are Transaction Dispatcher and Transactions Report Subscriber; report options include cancelled, refund and declined transactions. This provides an ongoing capture path, not proof of historical backfill or correction semantics. Maxim says processing fees come from weekly reimbursement statements.
- [Event delivery](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/set-up-nayax-core/set-up-events-delivery): VMO - Manager can configure Operator → Events Report → SQS, credentials, validation and event filters. This is a separate push setup, not a prerequisite for the implemented manual/Home-entry Lynx reads. No queue, paid service, subscription or new polling timer was created.
- [SaleEnd](https://devzone.nayax.com/docs/cortina/sale-end-notification) confirms a transaction outcome, not physical washer rotation or completion. Inhibit events remain the selected availability signal. Live event latency and a real wash cycle still need reader testing after access is enabled.

The [reply prepared October 6](NAYAX_MAXIM_AVAILABILITY_EMAIL.md) requested provider access, callback authentication and the pulse-reader trigger for SaleEndNotification, including a disconnected bench test. It was subsequently sent by the user; see the October 14 checkpoint for Yael's answers and the remaining authentication question.

## Access and reporting check - September 30

- Read-only Chrome inspection after the user signed in confirmed active **Clean Stream Laundry Solutions - DEV** account access, its existing LYNX token record, and Dynamic Transactions Monitor. This does not establish production operator access or transaction API entitlement. No credentials, settings, device commands or subscriptions were changed.
- The monitor, filtered to Last 30 Days, returned three USD 4.00 vends, total USD 12.00, zero unsettled vends. They display the Clean Stream mobile payment source and DEV machine group, not independently verified direct reader card collections.
- A read-only query against the correct Clean Stream Supabase project matched all three rows by Nayax transaction ID and authorization RRN, without amount/time heuristics:

| Nayax transaction | RRN | Existing Clean Stream payment | State |
| --- | --- | --- | --- |
| 4784321232 | 128134818454 | App wallet redemption, no session Stripe intent | started, USD 4.00 |
| 4784113034 | 128130722080 | App wallet redemption, no session Stripe intent | started, USD 4.00 |
| 4758557042 | 124134107964 | Web card payment with Stripe intent, no wallet redemption | started, USD 4.00 |

These are three linked machine operations, not an additional USD 12.00 in Nayax collections. This validates the need to separate collections from vends and wallet spending. No actual direct reader card payment was present in this returned sample; it does not prove such payments cannot be reported.

- The live private availability cache contains one row, checked `2026-09-28T21:57:13.918Z`, status `unknown`. Both machine `79835724` reads returned HTTP 403, "Insufficient permissions to perform this action." Correlation IDs: lastAlerts `15h5jPnWoUy20arH`; status `jh0IqGJEu0ydelPM`. This is historical provider evidence freshly read from storage, not a new provider request.
- Remaining verification: transaction-feed endpoint/entitlement, production operator scope, direct-payment/source semantics, incremental corrections/backfill and cost. The portal token list shows existence/use, not endpoint scopes. The [unsent Maxim draft](NAYAX_MAXIM_AVAILABILITY_EMAIL.md) requests these missing contracts plus existing availability access and inbound callback authentication. Never infer reporting API access from a working browser report.
- Official [token documentation](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/security) distinguishes full-account User Tokens from Nayax-admin-scoped App Tokens. No token secret was revealed or copied during this check.

## Implemented app connection — September 28, evening

- Created the explicitly authorized **LYNX** user token with reference **CleanStream machine availability**, token ID `cleanstream-availability-20260928`. Saved its secret only in Supabase Edge Function secrets as `NAYAX_LYNX_TOKEN`; no token is in source code or the APK.
- Deployed `machine-availability` to project `dnuuhupoxjtwqzaqylvb`, with server-side user authentication and private availability cache tables. The cache is separate from `Machines.Status` and payment state. Anonymous requests return 401.
- Home now has **Refresh**, a check when Home opens/returns, foreground refresh, and explicit unknown/error status. Following the user's feedback, **the five-second automatic polling timer was removed**. There are no repeating UI refreshes while Home stays open. Counts are a timestamped snapshot; the backend excludes unknown/stale state when that snapshot is fetched. Refresh cannot force the reader to transmit sooner.
- The first implementation polls the documented Lynx endpoints. **SQS has not been configured**. The earlier SQS proposal below remains a future delivery option, not the implementation that was deployed.
- The only configured app machine is Washer 1 at Madison Ave., linked to reader `4434331126150568`, Nayax machine `79835724`. No dryers are configured in the current inventory.
- Changed **Inhibit Event Timeout (attribute 658)** from 90 to **5 seconds**, leaving Inhibit active on logic 0. Nayax Queue confirmed value 5, sent `9/28/2026 17:41:23`, collected `17:41:56`, **Sent Success**. These are portal-displayed timestamps. Door was not changed.
- Android APK was installed with `adb install -r` on Samsung `RFGYC1WWPCE`, preserving its existing session/data. Inspected the live Home screen and exercised Refresh. It currently shows unconfirmed washer availability, not a fabricated ready count.
- Validation: **80 Flutter Home/machine-service tests passed**, then **66 Home tests passed** after changing refresh behavior, including a new return-to-Home test and a two-minute no-poll test. **5 event-reconciliation tests passed**, Android debug build passed, and live rollback-only SQL checks passed for RLS, grants, and polling leases. Full Flutter analysis reported 116 existing findings; none referenced the changed availability code. Supabase security advisors reported no issues on the new availability tables/functions.

### Concrete external blocker

The documented production API `https://lynx.nayax.com/operational` recognizes the token (Nayax Core's Last Used field updates) but returns **HTTP 403**, with the message **“Insufficient permissions to perform this action.”** Device lookup was rejected; both `/v1/machines/79835724/lastAlerts` and `/v1/machines/79835724/status` were independently confirmed rejected with the same message. Captured correlation IDs at about `2026-09-28T21:54:57Z` are `znpen1bEPEG51hSe` for lastAlerts and `slnt3KfTrU2My9DM` for status.

The documented QA base returned HTTP 401. The backend has been restored to the production base. Permission failures retry no more than once per minute per mapped reader; ordinary successful checks use the five-second cache interval.

This is now a narrow, justified request to Maxim to enable machine-data access for the DEV operator/user token. See `NAYAX_MAXIM_AVAILABILITY_EMAIL.md`. No email has been sent. Do not claim the live Busy/Ready transition has passed through the app: we have verified the app-to-backend request and the reader-to-Nayax portal events separately, but Nayax has not allowed the backend to read those events.

The sections below preserve the earlier research and bench-test chronology. Their descriptions of not-yet-created credentials or not-yet-implemented code refer to that earlier stage.

## Finding

**We found and bench-verified the relevant event pair in Nayax Core: Vending event 70, “Pulse Inhibited,” and Vending event 71, “Pulse Resumed.”** Grounding and then releasing Inhibit on reader 0568 produced both local display changes and the corresponding server events on September 28. Together with the published SQS delivery and Lynx API documentation, this provides a concrete integration path. The earlier broad email to Maxim is unnecessary and has been withdrawn.

We have a functioning sandbox Cortina payment/start exchange and an availability display, but the inspected app code does not connect that display to Nayax machine-state data. Our proposed path is **Nayax machine events → Amazon SQS → backend state updates → app availability counts**. The September 28 bench test confirmed local Busy/ready behavior and both Pulse Inhibited and Pulse Resumed events reaching Nayax from reader 0568. Backend delivery, exact payloads, measured latency, recovery behavior, and mapping a real washer's signals to its cycle still require validation.

The user confirmed that **Inhibit will be the machine feedback signal** and owns the machine/wiring integration. The initial scope was app/backend communication; on September 28 the user explicitly expanded the review to James Price's schematic and the benefit of using separate door-lock and door-position feedback. Ask Maxim only if documentation, account inspection, and our own integration checks cannot resolve a specific issue.

## Event pair verified in the DEV portal

On September 28, 2026, in [Nayax Core Account Settings](https://my.nayax.com/core/public/f?model=myAccount/accountInformation), the **Alert Rules** tab, searched for `pulse`, displayed exactly two results:

| Event category | Event code | Rule name |
| --- | --- | --- |
| Vending | 70 | Pulse Inhibited |
| Vending | 71 | Pulse Resumed |

This was a read-only catalogue lookup; notification subscriptions were not enabled or saved. The portal confirms the names/codes, not that our particular terminals currently emit them or that an SQS subscription is configured. Code numbers are reused across event categories, so production parsing must match the verified event source/category as well as code. Do not guess the numeric source ID from an unrelated example.

For the user's chosen Inhibit signal, the proposed mapping is 70 → inhibited/unavailable and 71 → resumed/eligible for available. The latter still requires fresh connectivity and an operational machine. Validate these transitions against an actual cycle before treating them as authoritative app state.

## What we already have

| Item | Evidence and limitation |
| --- | --- |
| Cortina StaticQR integration | `CORTINA_SETUP.md` records successful sandbox browser payment on September 24 and app wallet payment on September 28. This establishes Start/Sale/SaleEnd exchange. |
| Availability display | `lib/features/home/controller.dart:188` fetches washer/dryer totals and idle counts. `lib/services/supabase/supabase_machine_service.dart:31` and `:50` count `Machines.Status = idle`. |
| Device checking placeholder | `supabase/functions/ping-device/index.ts:16` reads `Machines.Status`. `logic.ts:31` adds random success/failure and artificial delay. It never queries Nayax. |
| Payment completion handling | `supabase/functions/_shared/cortina_callback.ts:245` marks the vend session `started` on SaleEnd; it does not track laundry completion or update machine availability. |
| DEV portal access | Read-only portal inspection showed two terminals under Clean Stream Laundry Solutions - DEV: `4434331126150568` and `4434331126150748`. Dashboard classified one as connected and one as silent more than 24 hours. These are communication categories, not idle/busy counts. |
| Known test mapping | Project notes and the September support case identify terminal `4434331126150568`, device ID `150568`, and Nayax machine ID `79835724`. These are distinct identifiers. |
| Verified app location mapping | September 28 read-only live database query confirmed terminal `4434331126150568` is mapped through `cortina_machine_config` to app machine `1`, **Washer 1**, at location `1`, **Madison Ave.**, `5330 Madison ave, Anderson, IN`. The mapping is enabled and sandbox; stored machine status was `idle`. This is the payment/device assignment, not a working Inhibit availability feed. |
| Current bench setup | User has the standalone test Nayax reader, not a connected washer. The harness has labelled INHIBIT, DOOR, and GND wires. After the successful Inhibit active/released test, the user confirmed the jumper disconnected and the reader back to normal. |
| API credential status | The current DEV login's Account Settings > Security and Login > User Tokens table contained no token rows. This does not establish whether another user/environment holds a credential. No token was created. |

The original `yaml_V2_Cortina.yaml` contains payment routes and SaleEndNotification, with no documented laundry cycle-status route. Its SaleEnd description concerns successful sale completion, consistent with the current [Sale End documentation](https://devzone.nayax.com/docs/cortina/sale-end-notification). Do not treat SaleEnd as “washer finished.”

## First bench-test inspection — September 28, approximately 13:12 Eastern

After the user signed back into Nayax, the actual record for terminal `4434331126150568` / machine `79835724` showed **Online**, with its last heartbeat displayed as `28/09/2026, 13:08`. The operator was **Clean Stream Laundry Solutions - DEV**.

The **Last Alerts** page loaded 13 entries. After refresh, the newest visible timestamp was September 22, 2026 at 12:22:16 (Power up); no September 28 input-test event was observed. This is an observation of the portal's returned history, not proof that every kind of event appears there.

Under **Settings → Pulse → Advanced**, the saved configuration displayed **00 - Inhibit Disabled (Nayax ignores inhibit)** and **Inhibit event timeout(sec): 90**. The dropdown also offers **01 - Inhibit Enabled and Active on logic 0 received from VMC**. This explains why the ground test cannot be expected to produce the intended behavior with the current configuration. The reader's effective applied setting has not been independently read back from the hardware.

The user explicitly approved enabling Inhibit on test reader 0568. The Pulse page was saved with mode **01** and timeout **90**, then its **Update parameters in the Queue → Update** prompt was confirmed. Under **Logs → Queue**, filtered to `Inhibit`, the portal showed:

| Attribute | Value | Sent to queue | Device collected | Status |
| --- | --- | --- | --- | --- |
| 657 — Pulse Inhibit | 1 | 9/28/2026 13:16:10 | 9/28/2026 13:16:19 | Sent Success |
| 658 — Inhibit Event Timeout (sec) | 90 | 9/28/2026 13:16:10 | 9/28/2026 13:16:19 | Sent Success |

The wizard queued a batch of Pulse settings, including the unchanged timeout; mode 01 was the only field intentionally changed. No reload-all, factory reset, firmware update, or restart was sent. Device collection of the Inhibit setting was verified. At that point neither a Pulse Inhibited event nor a Pulse Resumed event from the user's test had been verified. The user then asked to review James Price's schematic and the use of Inhibit with door-lock and door-state signals before continuing the input test.

## Live Inhibit bench test — September 28, approximately 16:30 Eastern

The user connected the labelled INHIBIT and signal GND wires and reported that the standalone reader displayed **Busy immediately on contact**. This confirms the reader's local input behavior independently of server alert timing. The Nayax browser session had expired; the user signed in again before server verification.

In reader `4434331126150568` / machine `79835724` → **Last Alerts**, the loaded table showed 18 entries, including:

| Event | Code | Source | Group / category | Timestamp exactly as displayed by Nayax |
| --- | --- | --- | --- | --- |
| Pulse Inhibited | 70 | Device | Vending / Vending | 9/28/2026, 15:29:09 |
| Pulse Resumed | 71 | Device | Vending / Vending | 9/28/2026, 12:17:48 |

The event-data cells for these rows were blank and Site was `DE`. The new Inhibited row confirms that this reader reports the input to Nayax; this is more than the earlier event-catalogue lookup. The older Resumed row predates the user's latest grounding and must not be counted as the release half of this test. At 20:31 UTC (16:31 Eastern), the portal timestamps appeared one hour behind local Eastern time; retain raw values until the portal/device timestamp basis is resolved. No precise end-to-end latency has been measured.

The user subsequently confirmed **“disconnected nd returned to normal.”** After refreshing Last Alerts, the table showed **19 entries** and a new top row:

| Event | Code | Source | Group / category | Timestamp exactly as displayed by Nayax |
| --- | --- | --- | --- | --- |
| Pulse Resumed | 71 | Device | Vending / Vending | 9/28/2026, 15:31:21 |

This newer Resumed row follows the Inhibited row at 15:29:09 and confirms the release half of the same bench test. Site remained `DE` and Event Data was blank. **Both transitions passed locally and through to Nayax's server.** The user was told to leave the wires disconnected. No app database status was changed, and no SQS or authenticated Lynx payload has yet been captured. Do not describe this as completed app integration or a verified real washer cycle.

## Documented integration options

**Lynx management API.** The documented QA base is `https://qa-lynx.nayax.com/operational`; production is `https://lynx.nayax.com/operational`. Resolve the account's environment through authenticated read-only machine lookup against these documented hosts. The operator name ending in DEV and the Cortina payment host alone do not determine the management environment. This is an access check to perform ourselves, not an unanswered request for base URLs. [Environment documentation](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/lynx-overview)

| Route, relative to the operational base | Use and limitation |
| --- | --- |
| `GET /v1/devices/{DeviceSerialNumber}/machine` | Resolve the terminal serial to Nayax MachineID. [Machine lookup](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/machines/retrieve-machine-information) |
| `GET /v1/machines/{MachineID}` | Machine identity/configuration. `MachineStatusBit` is described as a bit field without an idle/busy mapping. [Basic info](https://devzone.nayax.com/reference/lynx/machines/get-specific-machine-basic-info) |
| `GET /v1/machines/{MachineID}/status` | Includes communication and event timestamps such as `LastKeepAliveDateTime`, reader error/enabled times, and `MachineMQTTStatus`. The published schema does not define a current laundry-running boolean or remaining cycle time. [Statistics](https://devzone.nayax.com/reference/lynx/machines/get-specific-machine-statistics) |
| `GET /v1/machines/{MachineID}/lastAlerts` | Includes event code, description, timestamps, and data. Requires the correct event semantics and recovery behavior before deriving availability. [Alerts](https://devzone.nayax.com/reference/lynx/machines/get-machine-last-alerts) |
| `GET /v1/metadata/v1/event-rules` | Lists configured active rules with name, code, source, category and description. Use this to resolve the full identifiers for Pulse Inhibited/Resumed before writing the parser. [Event rules](https://devzone.nayax.com/reference/lynx/metadata/get-event-rules) |

Lynx uses `Authorization: Bearer <token>`. The documented self-service route is **Account Settings → Security and Login → User Tokens → Add Token → Lynx Token**. User tokens carry the user's account access. Nayax also documents scoped App Tokens whose scopes/claims a Nayax admin assigns. Cortina's payment SecretToken does not establish Lynx authorization. Keep credentials on the backend. No new credential was created during research. [Authentication](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/security), [App Tokens](https://devzone.nayax.com/docs/manage-data-operations/lynx-api/app-tokens)

**Amazon SQS event delivery.** Nayax documents the required role, **VMO - Manager**, and setup under **Administration → Operator → Events Report → General and Alert via SQS**. Configure the queue URL and AWS credentials, validate, and enable the feed. This setup is documented; we do not need Maxim to explain it. No queue or subscription was created during research. [Event and Alert Delivery](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/set-up-nayax-core/set-up-events-delivery)

The event field table includes `machineId`, `deviceId`, `deviceSerial`, `eventSourceId`, `eventCode`, `eventName`, `eventData`, `eventDateTimeGMT`, and `eventDateTimeVMC`. The sample is a power-up event, so it cannot supply the source/data for Pulse events. Some ID names in the sample JSON visually differ from the field table (`machineld` versus `machineId`); use captured messages to establish actual key spelling and types. [Message format](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/set-up-nayax-core/set-up-events-delivery)

**Duplicate, ordering, and retry behavior.** Nayax specifies a Standard SQS queue. AWS documents at-least-once delivery and possible duplicates/out-of-order arrival. Our consumer must apply events idempotently, reject stale state transitions, commit the state update before acknowledging, and retry failed processing. Messages that are not deleted become available again after their visibility timeout; persistent failures can go to a dead-letter queue. These are documented consumer behaviors, not questions for Maxim. They do not establish terminal-to-Nayax or Nayax-to-SQS retry guarantees. [Nayax queue setup](https://devzone.nayax.com/docs/manage-data-operations/amazon-sqs/amazon-queue-setup/create-new-queue), [AWS Standard queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues.html), [AWS visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)

**Inhibit timing.** Nayax documents an Inhibit Event Timeout: the inhibited alert is sent to the server after the configured duration, with a **90-second default**. Reader 0568's timeout of 90 was inspected and its collection verified as recorded above. This matters to app freshness, but is not a promise that every state change reaches the app in 90 seconds. Measure the active and resumed transitions and end-to-end arrival times on the test terminal before choosing the availability freshness policy. [Pulse configuration](https://nayax-u.nayax.com/scenario/understanding-attributes-and-configurations-pulse-11715)

## James Price schematic and independent Door feedback

Found James Price's August 12, 2026, 3:34 PM email in **Nayax Install Assistance**, addressed to Jacob and copied to Kevin Tracy. It contains **5V relay.pdf** (71 KB), which James identifies as the discussed schematic, plus **Multi-Price Upsell Amusements (v2).pdf**. The complete single-page relay schematic was visually inspected in Outlook. The downloaded original is `/Users/jamaki604/Downloads/5V relay.pdf`; macOS permitted file metadata inspection but denied the shell's attempted copy into this project. [Original email](https://outlook.cloud.microsoft/mail/id/AAQkADVhNGJkNTVmLTUzMDAtNDhkMy05ZDAwLTAwNDJhNzBjMzAzMgAQAHi%2F%2FIENPg1GnOWWf2owL2k%3D)

The schematic shows **payment output**, not machine-state feedback: Nayax Pulse 1 goes to the 5 V relay module's IN1; Nayax GND goes to DC−; VCC goes to DC+. The module is marked for low-trigger operation. Its NO contact goes to machine Credit and its common contact goes to machine Common; NC is unused. A separate 24 VAC/DC supply powers the reader through its power input pair. Neither Inhibit nor Door is drawn, and the diagram does not identify washer door-lock terminals or voltage.

For the user's proposed architecture, keep three distinct functions:

| Signal | Proposed source / direction | Information or action |
| --- | --- | --- |
| Pulse 1 | Nayax → existing payment relay → machine Credit/Common | Adds purchased credit. This is what James's schematic covers. |
| Inhibit | Machine busy/locked status → suitable isolated contact/interface → Nayax Inhibit | Prevents accepting more credit while asserted; candidate source for app busy status. It does not command the door lock. |
| Door | Separate physical door-position switch or isolated status → Nayax Door input | Adds physical open/closed history, subject to configuring and testing the input's actual behavior. |

The lock-based Inhibit plan is useful **if** the chosen signal remains asserted throughout the period the machine is unavailable and releases when it is usable again. A lock command, momentary latch pulse, simple door-closed switch, and sustained actual-lock feedback are different signals. The supplied schematic cannot establish which the washer provides. Keep machine lock power on its own side of the suitable relay/interface; a Nayax signal input is not a lock-power connection. No machine-specific terminal numbers or interface ratings have been inferred.

Two independent signals allow a proposed app state history of busy/locked → lock released but door still closed → door opened after the cycle. The middle state can support a **finished / awaiting collection** label after validation against real cycles; the final state establishes that the door was opened, not that clothes were removed or the drum is empty. Door closed alone does not establish running, because a door may be closed before payment or after a completed cycle. Feeding the same lock signal into both inputs would add no independent information.

The Door input can alternatively monitor a **service cabinet** for maintenance/tamper alerts, but then it tells us nothing about customer loading or collection. Nayax's [hardware guide](https://nayax-u.nayax.com/article/pulse-hardware-installation-11793) documents Door alerts separately from Inhibit. Its [Pulse configuration guide](https://nayax-u.nayax.com/scenario/understanding-attributes-and-configurations-pulse-11715) also describes Door mode disabling payment, with contradictory physical-open/closed versus alert labels. The [official Pulse manual](https://nayax-u.nayax.com/article/nayax-pulse-manual-11705), downloaded and text-inspected, lists Door Open, Cash Collect, Increment Source, and Cancel roles; it repeats the label ambiguity and does not establish an alert-only Door mode for this reader.

Recommendation: use validated Inhibit feedback for the first availability integration. Add independent customer-door feedback only if collection/door-state features are wanted and a bench test establishes correct event polarity and acceptable payment behavior. Do not assume Door is passive telemetry or enable a role blindly. Reader 0568's Door setting was not changed. Its exact Door configuration, open/close events, and any effect on payment remain to be tested; the app still has no live Inhibit or Door consumer.

**Current state and recovery.** The public status schema exposes connectivity (`MachineMQTTStatus`, `LastKeepAliveDateTime`) but no explicit current Inhibit boolean. `lastAlerts` is recent event history, not a documented state snapshot or complete replay API. First test whether it contains both Pulse events with enough history to reconcile a restart. Persist state across consumer restarts, drain retained SQS messages, and keep availability unknown when continuity cannot be established. A heartbeat proves communication, not that a missed Inhibit transition has been recovered. If these checks cannot establish current state after a gap, that specific recovery question may require Maxim.

## Prior correspondence checked

- Outlook support case **Cortina Static QR, Case Number: 03401910** confirms Maxim's identity/address (`maxims@nayax.com`), DEV access, payment setup, and the September 24 Start endpoint correction.
- **Integrating the APP with Nayax API**, forwarded February 13, 2026, discusses SQS reporting and a proposed laundry portal view of machine status. The visible correspondence does not supply busy/idle event codes or establish a completed integration.
- Earlier **Nayax Inhibit Wire Testing** and **Nayax Install Assistance** correspondence concerns the user-owned hardware work. It does not supply the app communication specification and is not a vendor question for this task.

Gmail and Drive searches returned no Nayax documents in those connected accounts; the relevant business correspondence was found in Outlook. Searches are not proof that no other documentation exists.

## Next implementation and validation steps

1. Establish backend Lynx access using the documented token process. Read event rules, resolve each terminal to its Nayax MachineID, and inspect `status` and `lastAlerts`. Record actual source/category identifiers for events 70/71. This is still pending; no authenticated Lynx calls were made during this research.
2. Configure the documented SQS feed and capture a complete Inhibit active → released transition in the backend. The standalone reader-to-Nayax portal transition has passed; repeat with message capture and then a real machine. Compare terminal transition time, event time, and receipt time. Check each payment/start path the business uses; one standalone reader test does not establish correct washer-cycle semantics in every mode. Where a terminal serves multiple machine channels, inspect whether the payload identifies each channel before assigning app machines.
3. Map Nayax IDs to app machines/locations and implement the backend consumer. Store state, source, vendor event time, receipt time, and connectivity separately. Deduplicate messages and prevent older events from overwriting newer state. Include an explicit unknown state for missing or unreconciled data.
4. Verify restart, delayed delivery, duplicate delivery, and disconnect/reconnect behavior. Try `lastAlerts` for reconciliation; do not interpret the absence of an alert as proof that a machine is available. Escalate only the specific behavior that documentation and tests cannot resolve.
5. Update `Machines.Status` from validated machine events and refresh Home counts as the database changes and on return to Home. Count only machines with confirmed ready state and fresh communication. Show data-unavailable errors explicitly rather than converting fetch failures to zero. An estimated cycle timer cannot establish availability.

No broad vendor clarification is needed before these steps. `NAYAX_MAXIM_AVAILABILITY_EMAIL.md` now records why the original draft was withdrawn and the narrow conditions for a future question. No email has been sent.
