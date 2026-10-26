# Cortina QR rollout setup

The code is implemented but intentionally does not enable or deploy production vending. Complete these items in order.

## Current sandbox state

- **October 19 current result:** authenticated $8 sandbox payment flow succeeds on reader0568. At21:48:36UTC session `f46dad1b-dc66-457d-984f-4306f6c2959c` became `started` after one Start, matching Sale and SaleEnd; Nayax transaction4903267080, no failure/refund. The actual browser shows “Machine started.” This proves provider communication, not physical washer operation.
- **Pricing corrected:** reader price array is `1000,800`; owner chose $8. Sandbox machine1 now uses `product_codes={"800":1}`, sole-consumer rate800cents and Machines.Price=8. The earlier code3/$4 caused Core event11 zero-price rejection. Reader settings were unchanged.
- **Authentication corrected:** our saved-source username transfer error was fixed first. Actual inbound traffic then established HTTP Basic; the callback now validates that complete pair, retaining exact separate-header compatibility. Nine sandbox probes and actual Sale/SaleEnd acceptance pass. No credential values were logged.
- **Pulse SaleEnd corrected:** actual final payload omits BasicInfo amount/currency and supplies AuthAmount=0, SettAmount=8. It now requires the exact settlement plus this session's matching authenticated Sale audit before recovering currency. Present conflicts, missing Sale evidence, wrong binding/environment and closed states remain rejected. Audit records provenance; SQL guards are unchanged.
- **Deployment/verification:** 237 focused tests and both entrypoint typechecks pass. Sandbox adapter v68 and production-route adapter v64 in development are ACTIVE and byte-verified. Production credentials are absent; unauthenticated invalid-body production probe returns code5. Only sandbox machine1 is enabled.
- **Remaining:** configure/confirm Production credentials and callback routing, then the production activation gate below. Existing Cortina case03401910 reply asks only those setup questions, saved unsent. Historical unknown attempts remain preserved; intermittent no-callback cancellations also occurred, including21:46 before the successful21:48 attempt. Site reception/reliability needs acceptance. Evidence: workspace `.campaign-work/nayax-pulse-review-20261019/`.
- **Guest checkout correction:** cortina-vend v65 accepts only the explicitly configured app/web guest key names, preserving verified human admission and the VEND RPC key. 21 focused checks/typecheck pass; both fresh browser checkouts reached Stripe sandbox success. Production vending remains off.
- **Yael's October 8 clarification:** Production Lynx permissions were granted to the user, pending fresh reader API verification. Pulse provides no vend-failure feedback, so SaleEnd cannot prove physical machine start. Last Sales appears only after our SaleEnd response; a missing row is not independent proof of a failed vend and must not authorize compensation or a repeat Start.
- The Cortina database migrations are applied to Clean Stream Supabase project `dnuuhupoxjtwqzaqylvb`.
- `cortina-vend`, `nayax-sale-end-sandbox`, `nayax-sale-end`, and the Cortina-aware `stripeWebhook` are deployed.
- The web implementation is deployed from `CortinaQR` to the Vercel project `clean-stream-web`. `cleanstreamlaundry.com` serves the Vercel application and `www.cleanstreamlaundry.com` redirects to the apex domain.
- GoDaddy's apex A record points to Vercel at `216.198.79.1`. The Outlook/Microsoft mail, autodiscover, MX, TXT, SIP, and related DNS records were not changed.
- The production `/pay` browser fallback and Android `assetlinks.json` return HTTP 200. The connected Samsung debug build verifies `cleanstreamlaundry.com` and opens the app directly from the production payment URL.
- October 19 actual provider authentication and Sale/SaleEnd acceptance are verified with the corrected handler. Only the sandbox `Washer 1` mapping is enabled; additional machines remain disabled until their rates and device mappings are reviewed.
- The database currently contains one 12 kg sandbox washer at $8.00. There is no dryer machine row yet.
- The Nayax secret received on August 7 is configured for both Sandbox and Production. Nayax confirmed the same value is used in both environments.
- The sandbox washer is mapped to test device 150568 using price-array product code 1 for $8.00 (`product_codes = {"800":1}`, `pulse_line_number = null`), as selected by the owner October 19. The earlier code 3/$4 mapping passed browser Stripe sandbox payment September 24 and app loyalty payment September 28, before the reader price list changed. Physical washer operation and the app card success path still require separate verification.
- The first paid test used the old $2.00 placeholder. Nayax declined that Start with code 13 and Clean Stream automatically refunded the Stripe test payment. The server rate was then aligned to the first configured Nayax price point at $4.00.
- A follow-up $4.00 test was also declined with code 13 while Start repeated `Price: 4.00`; its Stripe test payment was automatically refunded.
- The Nayax `Live Test` record (`635642176`) in `my.nayax.com` reports `No device`. Its machine number contains `4434331126150568`, but that label alone does not establish the hardware assignment or its QA configuration.
- Device 150568 is hardware serial `4434331126150568`. Nayax's June 15 email confirms that it and `4434331126150748` were configured for sandbox. Do not infer that the hardware needs provisioning or transfer from the unrelated production portal record. The previously used `qa2-lynx` endpoint was corrected on September 24.
- A September 8 Stripe test sent the $4.00 product price and pulse line to Nayax. Nayax returned HTTP 200 with status code 13, and Clean Stream automatically refunded the card payment.
- A $10 Stripe test wallet load completed successfully. A subsequent $4.00 loyalty vend was debited, received the same Nayax decline, and was automatically reversed; the test account returned to its $11.00 balance.
- On September 16, a $4.00 browser Stripe sandbox checkout initially remained `payment_pending`: the dedicated Stripe sandbox had no webhook destination, and the deployed `stripeWebhook` still required a Supabase JWT. Both configuration gaps were corrected with approval. The live Stripe destination and its signing secret were preserved.
- The existing event `evt_1UGQuOLHhN3TvHi6vkX2bwBL` was replayed through Stripe, without creating another payment. Stripe received HTTP 200. Vend session `551ade6a-9f1b-491d-9ceb-83bd3e3cbf5d` sent one Start at `2026-09-16 22:33:37.738 UTC`; Nayax returned `{"Status":{"Code":13,"Verdict":"Declined"}}`. Stripe confirms the automatic $4.00 refund `re_3UGQuNLHhN3TvHi61ueGfZ5G` succeeded.
- Replaying that same Stripe event again returned HTTP 200 and preserved the original Start timestamp, single Start event, and refund ID. Unsigned and invalid-signature webhook requests returned HTTP 400. The fresh last-hour function logs showed these Stripe requests and no `/functions/v1/nayax-sale-end%` callback requests; this does not prove what occurred inside Nayax.
- A fresh debug build was installed and launched on the connected Samsung on September 16. The 34 focused QR/scanner/payment-controller tests and 9 webhook tests passed. Android domain verification remained valid.
- The app has a server-verified card confirmation fallback. The browser currently relies on webhook delivery and can display `Payment received` while the server is still `payment_pending`; browser recovery and accurate pending messaging remain to be addressed.
- Nayax's Credit Card decline table labels code 13 `Invalid amount`, but the StaticQR table uses code 7 and does not document code 13. The earlier StaticQR Start response alone does not establish an amount error.
- On September 22, Maxim confirmed access through the globe menu in `my.nayax.com`. The verified account is `Clean Stream Laundry Solutions - DEV`; device `4434331126150568` is online under machine `79835724`, with `Clean Stream Laundry Solutions` enabled as its payment method. The earlier production record's `No device` label does not apply to this DEV device.
- The DEV device uses `03 / Use Price Array`, with prices `1000,800,600,400,200` cents. The StaticQR guide requires zero-based `Code` for this mode, so $4 uses `Code: 3`, not `PulseLineNumber: 1`. No Nayax settings were changed.
- Migration `20260922224735_cortina_price_array_selectors.sql` and all four function updates were deployed on September 22. Selectors are validated before payment and snapshotted per session. Existing pulse-line configurations remain supported. Start audit records redact the secret. Callback/start race protection prevents an already approved or completed vend from being overwritten by a late Start failure.
- A fresh September 22 Stripe sandbox test used session `d2f1459c-ac5d-4600-a7f6-91d11bc2768d`, transaction `32f9f108ed69423fa64688decdccfc06`, and one product `{"Code":3,"Price":4}`. The request audit time is `2026-09-22 23:12:16.516 UTC`. Nayax again returned HTTP 200 with `{"Status":{"Code":13,"Verdict":"Declined"}}`. The two Stripe success events produced only one Start. Clean Stream recorded refund `re_3UIcrALHhN3TvHi61VkxHfj1` and session status `refunded`; no Nayax callback event was recorded for the session. This verifies the corrected request and compensation path, not a successful hardware vend.
- The September 22 support reply was sent after user approval. On September 24 at 9:34 AM, Maxim confirmed that the request was correct and the endpoint caused code 13. His exact URL uses `lynx.nayax.com` and the integration slug `clean_stream_laundry_solutions`, not the display name with encoded spaces.
- Both stored Start URL settings were corrected on September 24. No secret tokens, Stripe keys, Nayax portal settings, or machine enablement were changed. Only the existing sandbox washer remains enabled. No application rebuild or function redeployment was needed for this configuration-only correction.

### Successful September 24 sandbox test

- Flow: production website `/pay` -> Stripe sandbox -> one Nayax Start -> Sale -> SaleEnd -> `started`.
- Vend session: `6f72bee8-99af-4f1b-97b8-eb1b8d38a74a`; Clean Stream TransactionId: `7c78037686794f7e83d2a7178b5fff2a`.
- Amount: 400 cents USD; product: `{"Code":3,"Price":4}`; terminal: `4434331126150568`; environment remained `sandbox`.
- Stripe PaymentIntent: `pi_3UJCtSLHhN3TvHi60GEpCEqI`. Both success webhook types arrived, but only one Start was recorded.
- Start request audit: `2026-09-24 13:41:02.004 UTC`; response: `{"Status":{"Code":0,"Verdict":"Approved","StatusMessage":"Transaction is Approved "}}`.
- Sale callback: `13:41:08.622 UTC`; SaleEnd callback: `13:41:25.503 UTC`; final session status: `started`, no failure or refund.
- Nayax TransactionId: `4758557042`; RRN: `124134107964`. The browser displayed `Machine started`.
- This proves the browser/card/backend exchange with the test terminal. App loyalty subsequently passed on September 28; actual washer operation, app card success, all six dryer selections, and production certification remain outstanding.

### September 28 app loyalty audit and display fix

- User-scanned app loyalty vend: session `4a55e969-326e-4ad6-a0ea-5a5bd24fdacd`, TransactionId `b8460a4e5f9c46f8864ce574db89bb3d`, Nayax TransactionId `4784113034`.
- At `13:07:18.913 UTC`, wallet redemption 8 succeeded and ledger entry 18 deducted exactly 400 paid cents. Both `wallet_balances` and the compatibility profile balance reconcile to $7.00, down from $11.00. No reversal was recorded.
- One Start request at `13:07:19.032 UTC` used the sandbox mapping, terminal `4434331126150568`, and `{"Code":3,"Price":4}`. Nayax returned code 0 / Approved at `13:07:21.711 UTC`.
- Sale at `13:07:22.793 UTC` matched the $4 USD amount, terminal, and TransactionId. SaleEnd at `13:07:33.218 UTC` matched Nayax TransactionId and RRN `128130722080`; the session became `started` at `13:07:33.238 UTC`, with no failure or refund.
- Supabase Edge Function request logs showed 12 successful HTTP 200 calls: one quote, one wallet, eight status polls, one Sale, and one SaleEnd. No function warnings or errors appeared in the inspected window. The only database error was an audit SELECT referencing a nonexistent session `environment` column; it was corrected and did not mutate data.
- The old app fetched the wallet only before payment and left checkout open after dismissing success. The app now reloads the server wallet balance after wallet attempts, navigates to a freshly loaded Wallet page after successful loyalty payment (Home after card payment), and prevents payment or price changes on a completed checkout. Balance-refresh failure does not change an already confirmed vend outcome or display stale funds.
- A corrected debug APK was installed on the Samsung without clearing its data. Checkout, Home, and Wallet each showed $7.00; Wallet also displayed the $4.00 machine #1 debit. No additional payment was submitted during this audit. The post-success navigation fix passed a widget regression test; a new physical app payment remains the end-to-end retest.
- Verification: 136 payment, scanner, and loyalty tests passed; focused Flutter analysis passed; debug APK build passed. Existing Gradle/AGP/Kotlin upgrade warnings remain outside this change.
- The missing legacy transaction-history link discovered during this audit was resolved by the migration and app update below.

### September 28 transaction-history and loyalty-credit integration

- Applied migration `20260928132533_link_cortina_transaction_history.sql` to Clean Stream Supabase and recorded its exact source in migration history (MD5 `8a0fbf437f008fe928e0e635866a50e1`). A rollback-only rehearsal passed before deployment.
- Completed Cortina sessions now create one linked `transactions` row on the server. The unique session link prevents duplicates; the explicit `laundry` type avoids the legacy credit/debit balance trigger. Late reversals retain history but remove loyalty-credit eligibility.
- Backfilled transaction 479 for the September 24 guest card vend and transaction 480 for the September 28 signed-in loyalty vend. Both are $4.00. Wallet balance remained $7.00, with 18 ledger entries and no new debit, credit, or refund request.
- Cortina credit requests now use `request_cortina_loyalty_credit`, which validates account ownership, completed status, the server-recorded amount, a nonempty reason, and the 14-day request window. It atomically creates one pending request and marks the transaction. Repeated requests return the same request without incrementing the counter again. Customer-written vend links and direct duplicate or mismatched Cortina refund inserts are rejected.
- Existing admin approval still credits the loyalty wallet, not Stripe. Local database tests verified a single promo credit on approval and no credit if an automatic reversal happened before approval. Already-approved manual credits followed by a later automatic reversal still require reconciliation review; this migration does not redesign that existing compensation workflow.
- On the deployed database, rollback-only tests verified the exact $4 amount, pending status, repeated-request idempotency, cross-account denial, and customer history isolation. The test left zero refund requests, `requested_refund = false`, and the wallet unchanged. Anonymous RPC access is denied; history synchronization is service-role-only.
- Installed the updated debug APK on Samsung `RFGYC1WWPCE`, preserving app data. Home initially showed $7.00, and the request form listed and selected the September 28 $4 washer vend. No loyalty-credit request was submitted. A later payment during verification is recorded below.
- Verification: 14 PGlite/PostgreSQL tests and 223 focused Flutter tests passed; debug APK built successfully. Focused analysis has no errors or warnings, with one pre-existing informational naming lint for `transaction_id`. Existing Android toolchain upgrade warnings were not changed.
- Supabase advisors were reviewed: security has 0 errors / 9 warnings, performance has 0 errors / 19 warnings. The new authenticated SECURITY DEFINER RPC is intentionally flagged for review; its ownership checks and permissions were tested. Other existing warnings and the broad legacy `Refunds` read policy remain part of production security review, not a clean-bill-of-health claim.
- Database regression tests are local-only: install `@electric-sql/pglite@0.5.8` in a temporary directory, then run `PGLITE_MODULE=/path/to/pglite/dist/index.js node --test scripts/cortina-history.test.mjs`. Never deploy `supabase/tests/cortina_history.fixture.sql`; it contains only synthetic test schema and data.

### September 28 follow-up vend at 13:48 UTC

- During final phone verification, the screen changed between observing Settings and a tap intended for Wallet. A new loyalty vend started; whether the user initiated this test or the navigation tap landed on Pay was not yet confirmed. Phone interactions were stopped and the user was asked to confirm. No automatic credit was issued to obscure or reverse a successful vend.
- Session `a6585f57-8b0d-44a8-96cd-9b89330a050e`, TransactionId `dfb2c6abc0d74098be19fff862f50f74`, amount 400 cents USD. Start at `13:48:15.370 UTC`, response at `13:48:18.031 UTC`, Sale at `13:48:19.169 UTC`, and SaleEnd at `13:48:29.597 UTC`; each event appears once.
- Final status `started` at `13:48:29.614 UTC`, no failure code/message. Nayax TransactionId `4784321232`, RRN `128134818454`, wallet redemption 9.
- The newly deployed trigger created exactly one history record, transaction 481, without client insertion. Ledger count increased from 18 to 19 and balance changed from $7.00 to $3.00. There are still zero loyalty-credit requests.
- Read-only phone checks subsequently found Wallet and then Home, with Home displaying $3.00. The recent Android log buffer contained no Flutter exception, fatal crash, PostgREST exception, or RenderFlex error. This confirms live history creation and refreshed balance; the success-dialog dismissal itself was not directly observed.

## 1. Nayax

The Clean Stream Start endpoints are configured as:

- Sandbox: `https://lynx.nayax.com/payment/v2/transactions/cortina/clean_stream_laundry_solutions/start`
- Production: `https://lynx.nayax.com/payment/v2/transactions/cortina/clean_stream_laundry_solutions/start`

Maxim supplied this exact integration URL on September 24, and the sandbox test succeeded with it. Both stored URL digests were verified as `1b0376f7aeda47de2cfea9337b07e2bacf7372b30c79e1efe900876b4a6276ea`. The URL's host does not mean that Stripe or the configured machine should be switched to production: the successful test retained its sandbox configuration. Keep the separate environment settings and callback bases; production vending is not certified or enabled. Do not derive the path from the human-readable payment-method name. The user's original Nayax YAML remains unchanged as a historical vendor document. Nayax's token ID identifies the credential in their system; Static QR `Start` sends the secret token value and does not send the token ID.

The Start request sends exactly one product with either the configured `Code` (price array, zero-based) or `PulseLineNumber` (pulse lines, 1-6), never both, and the server-authoritative decimal `Price`. The Sale callback must still match the amount already paid to Clean Stream before it is approved. A non-null price-array mapping must contain every offered price; missing mappings fail before payment instead of falling back to a pulse line.

The remaining machine-specific configuration for each additional device is:

- `TerminalId` or full `UniQR` for each device
- The device's selection mode and either a `PulseLineNumber` or a product code for every offered amount

The callback bases and documented routes are below. Sandbox Sale and SaleEnd delivery were verified on September 24; confirm production routing before production certification:

- Sandbox: `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end-sandbox`
- Production: `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end`
- Routes: `/Cortina/StaticQR/Sale`, `/Cortina/StaticQR/Void`, `/Cortina/SaleEndNotification`

Maxim's October15 email supplied a Sandbox operator username/password pair but
did not specify their wire representation. Actual October19 traffic uses
`Authorization: Basic <base64(username:password)>`. The backend now validates
that pair; a real Sale and SaleEnd succeeded. No authentication-method question
remains. Production operator values/routing still need confirmation.

Nayax's June 15 email confirms that the two sandbox devices were initially configured with five demo prices, while the platform supports up to six options. The June 29 email confirms the dryer can retain a multi-price configuration and the washer should use a single-price configuration. For Pulse 1-6 / Pulse Line configurations, the StaticQR documentation requires `PulseLineNumber` starting at 1 instead of a product `Code`. Keep additional devices disabled until one serial is assigned as the washer, the other as the dryer, and the final six dryer amount/pulse-line/time mappings replace the demo values. Test device 150568 is the temporary sandbox washer used for the current live test.

The September 16 read-only review found an unrelated `Live Test` record (`635642176`) under Anderson Bee Clean, LLC. Its `No device` state was resolved as a troubleshooting lead on September 22 by locating the actual DEV record `79835724`. Do not transfer or reprovision the terminal based on that production record. No portal settings were changed during either review.

The custom Clean Stream QR uses the opaque `public_machine_token` and does not expose the terminal serial or UniQR. Store the Nayax UniQR separately when Nayax provides it so the backend can use it for Start without placing it in the Clean Stream URL.

## 2. Supabase secrets

Set these secrets in project `dnuuhupoxjtwqzaqylvb`:

```text
NAYAX_SANDBOX_START_URL
NAYAX_PRODUCTION_START_URL
NAYAX_SANDBOX_SECRET_TOKEN
NAYAX_PRODUCTION_SECRET_TOKEN
CLEAN_STREAM_PAY_URL=https://cleanstreamlaundry.com/pay
CLEAN_STREAM_WEB_ORIGIN=https://cleanstreamlaundry.com
CORTINA_VEND_TIMEOUT_SECONDS=45
NAYAX_SANDBOX_CALLBACK_USERNAME
NAYAX_SANDBOX_CALLBACK_PASSWORD
NAYAX_PRODUCTION_CALLBACK_USERNAME
NAYAX_PRODUCTION_CALLBACK_PASSWORD
CLEANSTREAM_VEND_GUEST_PUBLISHABLE_KEY_NAMES=["cleanstream_dev_app","cleanstream_dev_web"]
```

The production pair is listed for future configuration and is **not installed**.
Use the exact production-operator pair supplied/configured by Nayax; do not copy
Sandbox values or use the outgoing Start secret or Lynx token. When either pair
field exists, the entire exact pair is required with no legacy fallback. The
legacy `NAYAX_CALLBACK_AUTH_TOKEN` path applies only when neither pair field is
configured; it is not the current agreed integration method. Existing
`STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` must remain configured.
`STRIPE_SANDBOX_WEBHOOK_SECRET` is separate; never replace the live signing secret
with the sandbox value. The guest-key setting contains names, not credentials;
each must resolve exactly in `SUPABASE_PUBLISHABLE_KEYS`. Its absence preserves
the previous single-key contract; malformed/unresolved names fail closed.

The callback functions use `verify_jwt = false` because Nayax cannot provide a Supabase user JWT. They correlate the Clean Stream transaction, environment, device, amount, currency, and callback event before approving.

### Production credential configuration gate

October26 update: Shachar's October22 reply confirms the endpoint and supplies
a secure note with `Token` and `Token ID`. With the owner's explicit approval,
the open note was saved privately. Read-only digest comparison confirms that
its token already equals both configured Start tokens. It is not the missing
callback Basic pair: both production callback fields remain absent. A reply in
case03401910 asks for that pair, or explicit confirmation that the existing
sandbox pair also applies; it is saved **unsent**. No credentials were replaced.

The production callback adapter is prepared in the existing **development**
project (October 19 source/byte readback verified). This is not production launch.

1. **Done in Sandbox:** actual authenticated Sale/SaleEnd and browser confirmation
   succeeded October19 at21:48:36UTC. Both adapters contain the tested Basic and
   Pulse settlement compatibility fixes. Historical unknown sessions remain
   support-review; never retry their Start or infer refunds from a timeout.
2. Obtain/confirm the production operator's exact HTTP Basic pair and callback base
   `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end` with its
   three routes above. Cortina support/Maxim's cover handles this, not Lynx/Yael.
3. Install both production secret fields together through the approved secret
   manager/CLI, never a client bundle, email body or committed file. Verify
   digests without exposing values; test missing/wrong/partial credentials and
   Sandbox/production isolation using malformed bodies that cannot vend.
4. Keep machine mappings in Sandbox until production payment authorization,
   Stripe live-key/webhook routing, existing-payment recovery, physical device
   mappings and certification are complete. Changing callback credentials alone
   must not change Stripe mode or enable a machine.

## 3. Stripe

The dedicated sandbox destination `we_1UGRGkLHhN3TvHi6IuJnSUZG` is active at `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/stripeWebhook`. It receives:

- `checkout.session.completed`
- `payment_intent.succeeded`

The handler selects the live or sandbox signing secret from the event mode, then verifies the signature over the unchanged raw body before processing any event. The deployed Supabase JWT gate is OFF, matching `supabase/config.toml`; Stripe signature verification remains mandatory. The existing live destination was left unchanged. Confirm its subscribed events and production Stripe API-key configuration before enabling production vending.

Stripe collects card payments for Clean Stream; no card details or funds are sent to Nayax through this integration. Loyalty vends debit the Clean Stream wallet first. Both paths then use StaticQR Start/Sale for machine authorization. Failed card vends use Stripe refunds with a session-level idempotency key; failed loyalty vends reverse the wallet debit. These automatic failed-vend reversals are separate from the admin loyalty-credit workflow.

The StaticQR code 13 blocker was resolved on September 24 by applying Nayax's exact endpoint. The browser Stripe sandbox test and September 28 app loyalty test were approved and completed, without refunds. Transaction-history integration is now deployed. Continue with app card testing, the app completion-screen retest, physical pulse verification, dryer configuration, and the certification checklist below before enabling production.

## 4. Database and functions

Apply migrations `supabase/migrations/20260803150427_cortina_qr_remote_vend.sql`, `supabase/migrations/20260804015500_cortina_rls_policy_cleanup.sql`, `supabase/migrations/20260807195409_configure_dryer_time_options.sql`, `supabase/migrations/20260922224735_cortina_price_array_selectors.sql`, and `supabase/migrations/20260928132533_link_cortina_transaction_history.sql`, then deploy:

```text
cortina-vend
nayax-sale-end-sandbox
nayax-sale-end
stripeWebhook
```

Deploy the migration before any function. Do not enable a machine until its migrated washer rate and device mapping have been reviewed.

## 5. Washer rates and machine mappings

In the web location administration page:

1. Review each migrated washer size tier or add the intended per-location tiers. The current 12 kg sandbox tier is $8.00 (owner-selected October 19).
2. Confirm each washer uses the correct tier. Changing a tier updates future quotes and the compatibility `Machines.Price`; existing vend sessions retain their quoted cents.
3. Open the payment setup action for each machine.
4. Enter `TerminalId` or `UniQR`, sandbox environment, and product-selection mode. For price arrays, enter the actual zero-based code for each offered price; otherwise enter the pulse line.
5. Save, run a physical sandbox vend, and enable only after the mapping is verified.
6. Download and print the generated Clean Stream QR label.

Dryers always quote $0.25 per five minutes. The six server-controlled products are:

| Pulse line | Time | Price |
|---|---:|---:|
| 1 | 10 minutes | $0.50 |
| 2 | 20 minutes | $1.00 |
| 3 | 30 minutes | $1.50 |
| 4 | 40 minutes | $2.00 |
| 5 | 60 minutes | $3.00 |
| 6 | 90 minutes | $4.50 |

The customer defaults to 30 minutes. The table's pulse lines are the existing defaults for Pulse 1-6 devices. Price-array devices instead require an explicit product code for each of those six prices; do not infer codes from this table. The selected code or pulse line is stored with the vend session before payment and is used for the one Nayax Start product. Confirm the resulting dryer time for every selection before enabling the machine.

## 6. Domain links

The Vercel project `clean-stream-web` is live at `https://cleanstreamlaundry.com`. `www.cleanstreamlaundry.com` uses a permanent redirect to the apex domain. Follow `CORTINA_DOMAIN_SETUP.md` in the web repository for the recorded configuration.

Apple association data is ready for the current Team ID and bundle ID. Android `assetlinks.json` includes the certificate for the connected debug build, and Android verified App Links were confirmed on the Samsung. Add the Google Play App Signing SHA-256 certificate before the production app release.

The host serves `/pay` as the React application and both `.well-known` files directly. Keep those files available with HTTP 200, `application/json`, and no redirects when future Vercel or domain settings change.

## 7. Certification

Certify on Nayax sandbox hardware before production:

- Washer flat-rate card and wallet vends
- All six dryer time, amount, and pulse-line products
- Decline, Start rejection, callback mismatch, duplicate callbacks, Void, timeout, refund, and wallet reversal
- iOS Universal Link, Android App Link, ordinary camera browser fallback, and in-app scanner handling

Enable production one machine at a time. Verify its QR token, location price, terminal or UniQR, pulse line, refund path, and physical pulse before moving to the next machine.
