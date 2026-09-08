# Cortina QR rollout setup

The code is implemented but intentionally does not enable or deploy production vending. Complete these items in order.

## Current sandbox state

- The Cortina database migrations are applied to Clean Stream Supabase project `dnuuhupoxjtwqzaqylvb`.
- `cortina-vend`, `nayax-sale-end-sandbox`, `nayax-sale-end`, and the Cortina-aware `stripeWebhook` are deployed.
- The web implementation is pushed on `CortinaQR`, but `cleanstreamlaundry.com` still points to the GoDaddy site. Vercel deployment and the domain cutover remain required for camera-app browser fallback and verified App Links.
- Live quote and callback smoke tests pass. Only the sandbox `Washer 1` mapping is enabled; additional machines remain disabled until their rates and device mappings are reviewed.
- The database currently contains one 12 kg sandbox washer at $4.00. There is no dryer machine row yet.
- The Nayax secret received on August 7 is configured for both Sandbox and Production. Nayax confirmed the same value is used in both environments.
- The sandbox washer is mapped to test device 150568 on pulse line 1, has passed QR lookup and Stripe payment testing, and is enabled for the next hardware Start test.
- The first paid test used the old $2.00 placeholder. Nayax declined that Start with code 13 and Clean Stream automatically refunded the Stripe test payment. The server rate was then aligned to the first configured Nayax price point at $4.00.
- A follow-up $4.00 test was also declined with code 13 while Start repeated `Price: 4.00`; its Stripe test payment was automatically refunded.
- The Nayax `Live Test` virtual machine (`635642176`) is configured for one pulse at $4.00 on pulse line 1, with `Pay Now` as its display message. The settings are queued, but the record still reports `No device` and cannot collect them.
- Device 150568 is hardware serial `4434331126150568`. That serial is not present in the Anderson Bee Clean, LLC device inventory, so it cannot yet be assigned to `Live Test`. Nayax must provision or transfer that exact device into the operator account before another paid hardware test.
- A September 8 Stripe test sent the $4.00 product price and pulse line to Nayax. Nayax returned HTTP 200 with status code 13, and Clean Stream automatically refunded the card payment.
- A $10 Stripe test wallet load completed successfully. A subsequent $4.00 loyalty vend was debited, received the same Nayax decline, and was automatically reversed; the test account returned to its $11.00 balance.

## 1. Nayax

The Clean Stream Start endpoints are configured as:

- Sandbox: `https://qa2-lynx.nayax.com/payment/v2/transactions/cortina/Clean%20Stream%20Laundry%20Solutions/start`
- Production: `https://lynx.nayax.com/payment/v2/transactions/cortina/Clean%20Stream%20Laundry%20Solutions/start`

The URL digests stored in Supabase were verified against these exact endpoints. Nayax's token ID identifies the credential in their system; Static QR `Start` sends the secret token value and does not send the token ID.

The Start request sends exactly one product with the configured `PulseLineNumber` and the server-authoritative decimal `Price`. The Sale callback must still match the amount already paid to Clean Stream before it is approved.

The remaining machine-specific configuration for each additional device is:

- `TerminalId` or full `UniQR` for each device
- `PulseLineNumber` for each connected washer and dryer

Ask Nayax to register these callback bases and append the documented routes:

- Sandbox: `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end-sandbox`
- Production: `https://dnuuhupoxjtwqzaqylvb.supabase.co/functions/v1/nayax-sale-end`
- Routes: `/Cortina/StaticQR/Sale`, `/Cortina/StaticQR/Void`, `/Cortina/SaleEndNotification`

Confirm callback authentication and whether Nayax requires fixed IP allowlisting, VPN, or mTLS.

Nayax's June 15 email confirms that the two sandbox devices were initially configured with five demo prices, while the platform supports up to six options. The June 29 email confirms the dryer can retain a multi-price configuration and the washer should use a single-price configuration. For Pulse 1-6 / Pulse Line configurations, the StaticQR documentation requires `PulseLineNumber` starting at 1 instead of a product `Code`. Keep additional devices disabled until one serial is assigned as the washer, the other as the dryer, and the final six dryer amount/pulse-line/time mappings replace the demo values. Test device 150568 is the temporary sandbox washer used for the current live test.

The portal review found the `Live Test` machine record (`635642176`). Its pulse settings are now queued as one pulse at $4.00 on pulse line 1, but the Cortex overview still reports `No device`. Nayax must first provision or transfer hardware serial `4434331126150568` into Anderson Bee Clean, LLC. After it appears in inventory, assign that exact device to `Live Test`, confirm it is online, and allow it to collect the queued configuration. Do not substitute one of the other five unassigned devices.

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

Set `NAYAX_CALLBACK_AUTH_TOKEN` only if Nayax agrees to send the same token in `x-nayax-auth` or as a bearer token. Existing `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` must remain configured.

The callback functions use `verify_jwt = false` because Nayax cannot provide a Supabase user JWT. They correlate the Clean Stream transaction, environment, device, amount, currency, and callback event before approving.

## 3. Stripe

Ensure the production webhook endpoint for the existing `stripeWebhook` function receives:

- `checkout.session.completed`
- `payment_intent.succeeded`

The webhook only starts Cortina when Stripe metadata, amount, PaymentIntent, and vend session match. Refund requests use a session-level idempotency key.

## 4. Database and functions

Apply migrations `supabase/migrations/20260803150427_cortina_qr_remote_vend.sql`, `supabase/migrations/20260804015500_cortina_rls_policy_cleanup.sql`, and `supabase/migrations/20260807195409_configure_dryer_time_options.sql`, then deploy:

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
4. Enter `TerminalId` or `UniQR`, pulse line, and sandbox environment.
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

The customer defaults to 30 minutes. The selected pulse line is stored with the vend session before payment and is used for the one Nayax Start product. Confirm these exact pulse-line, price, and time mappings in the Nayax dryer template before enabling the machine.

## 6. Domain links

Follow `CORTINA_DOMAIN_SETUP.md` in the web repository. Apple association data is ready for the current Team ID and bundle ID. Android `assetlinks.json` now includes the certificate for the connected debug build; add the Google Play App Signing SHA-256 certificate before production.

The host must serve `/pay` as the React application and both `.well-known` files directly with HTTP 200, `application/json`, and no redirects.

## 7. Certification

Certify on Nayax sandbox hardware before production:

- Washer flat-rate card and wallet vends
- All six dryer time, amount, and pulse-line products
- Decline, Start rejection, callback mismatch, duplicate callbacks, Void, timeout, refund, and wallet reversal
- iOS Universal Link, Android App Link, ordinary camera browser fallback, and in-app scanner handling

Enable production one machine at a time. Verify its QR token, location price, terminal or UniQR, pulse line, refund path, and physical pulse before moving to the next machine.
