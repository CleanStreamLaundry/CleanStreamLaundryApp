# Cortina QR rollout setup

The code is implemented but intentionally does not enable or deploy production vending. Complete these items in order.

## Current sandbox state

- The Cortina database migrations are applied to Clean Stream Supabase project `dnuuhupoxjtwqzaqylvb`.
- `cortina-vend`, `nayax-sale-end-sandbox`, `nayax-sale-end`, and the Cortina-aware `stripeWebhook` are deployed.
- The web implementation is deployed from `CortinaQR` to the Vercel project `clean-stream-web`. `cleanstreamlaundry.com` serves the Vercel application and `www.cleanstreamlaundry.com` redirects to the apex domain.
- GoDaddy's apex A record points to Vercel at `216.198.79.1`. The Outlook/Microsoft mail, autodiscover, MX, TXT, SIP, and related DNS records were not changed.
- The production `/pay` browser fallback and Android `assetlinks.json` return HTTP 200. The connected Samsung debug build verifies `cleanstreamlaundry.com` and opens the app directly from the production payment URL.
- Live quote and callback smoke tests pass. Only the sandbox `Washer 1` mapping is enabled; additional machines remain disabled until their rates and device mappings are reviewed.
- The database currently contains one 12 kg sandbox washer at $4.00. There is no dryer machine row yet.
- The Nayax secret received on August 7 is configured for both Sandbox and Production. Nayax confirmed the same value is used in both environments.
- The sandbox washer is mapped to test device 150568 using price-array product code 3 for $4.00 (`product_codes = {"400":3}`, `pulse_line_number = null`). It has passed QR lookup and Stripe payment testing, but Nayax has not yet accepted Start.
- The first paid test used the old $2.00 placeholder. Nayax declined that Start with code 13 and Clean Stream automatically refunded the Stripe test payment. The server rate was then aligned to the first configured Nayax price point at $4.00.
- A follow-up $4.00 test was also declined with code 13 while Start repeated `Price: 4.00`; its Stripe test payment was automatically refunded.
- The Nayax `Live Test` record (`635642176`) in `my.nayax.com` reports `No device`. Its machine number contains `4434331126150568`, but that label alone does not establish the hardware assignment or its QA configuration.
- Device 150568 is hardware serial `4434331126150568`. Nayax's June 15 email confirms that it and `4434331126150748` were configured for sandbox. Do not infer that the hardware needs provisioning or transfer from the production portal record; first verify the sandbox account and effective device mapping used by the `qa2-lynx` Start endpoint.
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

## 1. Nayax

The Clean Stream Start endpoints are configured as:

- Sandbox: `https://qa2-lynx.nayax.com/payment/v2/transactions/cortina/Clean%20Stream%20Laundry%20Solutions/start`
- Production: `https://lynx.nayax.com/payment/v2/transactions/cortina/Clean%20Stream%20Laundry%20Solutions/start`

The URL digests stored in Supabase were verified against these exact endpoints. The integration name matches the payment method visible in the DEV account on September 22. The `qa2-lynx` host comes from the supplied Cortina specification; Maxim is being asked to confirm this exact endpoint while tracing code 13. Nayax's token ID identifies the credential in their system; Static QR `Start` sends the secret token value and does not send the token ID.

The Start request sends exactly one product with either the configured `Code` (price array, zero-based) or `PulseLineNumber` (pulse lines, 1-6), never both, and the server-authoritative decimal `Price`. The Sale callback must still match the amount already paid to Clean Stream before it is approved. A non-null price-array mapping must contain every offered price; missing mappings fail before payment instead of falling back to a pulse line.

The remaining machine-specific configuration for each additional device is:

- `TerminalId` or full `UniQR` for each device
- The device's selection mode and either a `PulseLineNumber` or a product code for every offered amount

Ask Nayax to register these callback bases and append the documented routes:

- Sandbox: `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end-sandbox`
- Production: `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end`
- Routes: `/Cortina/StaticQR/Sale`, `/Cortina/StaticQR/Void`, `/Cortina/SaleEndNotification`

Confirm callback authentication and whether Nayax requires fixed IP allowlisting, VPN, or mTLS.

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
```

Set `NAYAX_CALLBACK_AUTH_TOKEN` only if Nayax agrees to send the same token in `x-nayax-auth` or as a bearer token. Existing `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` must remain configured. `STRIPE_SANDBOX_WEBHOOK_SECRET` is separately configured for the dedicated Stripe sandbox; never replace the live signing secret with the sandbox value.

The callback functions use `verify_jwt = false` because Nayax cannot provide a Supabase user JWT. They correlate the Clean Stream transaction, environment, device, amount, currency, and callback event before approving.

## 3. Stripe

The dedicated sandbox destination `we_1UGRGkLHhN3TvHi6IuJnSUZG` is active at `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/stripeWebhook`. It receives:

- `checkout.session.completed`
- `payment_intent.succeeded`

The handler selects the live or sandbox signing secret from the event mode, then verifies the signature over the unchanged raw body before processing any event. The deployed Supabase JWT gate is OFF, matching `supabase/config.toml`; Stripe signature verification remains mandatory. The existing live destination was left unchanged. Confirm its subscribed events and production Stripe API-key configuration before enabling production vending.

Stripe collects card payments for Clean Stream; no card details or funds are sent to Nayax through this integration. Loyalty vends debit the Clean Stream wallet first. Both paths then use StaticQR Start/Sale for machine authorization. Failed card vends use Stripe refunds with a session-level idempotency key; failed loyalty vends reverse the wallet debit. These automatic failed-vend reversals are separate from the admin loyalty-credit workflow.

The remaining blocker is Nayax's StaticQR Start code 13, even after correcting the selector against the verified DEV device. Its meaning is not documented in the StaticQR decline table. An unsent Outlook reply includes the fresh September 22 request and asks Maxim to trace it, confirm the exact Start endpoint, and confirm the product selection. Do not change prices, credentials, or hardware assignments speculatively.

## 4. Database and functions

Apply migrations `supabase/migrations/20260803150427_cortina_qr_remote_vend.sql`, `supabase/migrations/20260804015500_cortina_rls_policy_cleanup.sql`, `supabase/migrations/20260807195409_configure_dryer_time_options.sql`, and `supabase/migrations/20260922224735_cortina_price_array_selectors.sql`, then deploy:

```text
cortina-vend
nayax-sale-end-sandbox
nayax-sale-end
stripeWebhook
```

Deploy the migration before any function. Do not enable a machine until its migrated washer rate and device mapping have been reviewed.

## 5. Washer rates and machine mappings

In the web location administration page:

1. Review each migrated washer size tier or add the intended per-location tiers. The current 12 kg sandbox tier is $4.00.
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
