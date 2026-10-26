# Email and Consent

## Automatic Resolution Follow-Ups (Source Only)

October 5 implementation, **locally tested but not deployed**. No messages sent,
remote settings changed, or new dependencies added in this batch. Earlier hosted
activation receipts below cover the existing mail system only, not these new
outcomes. The new migration is
`20261005135252_automatic_resolution_mail_outbox.sql`; it requires the existing
credit/outbox/top-up/admin migrations and
`20261005135004_machine_issue_resolution.sql` first.

| Committed event | Automatic customer notice |
| --- | --- |
| Legacy claim approved/denied | Existing credit-decision notice, with its existing promo-only ledger check |
| Same-day machine claim wallet restoration | Exact purchased and promotional portions restored, corroborated by the original debit and resulting ledger entry; not a card/cash refund |
| Sponsored replacement reaches confirmed `started` | Replacement machine reference and confirmed start, not cycle completion or a payout |
| Top-up refund `succeeded` | Stripe-confirmed amount to the original payment method, only with provider reference/check, completed reconciliation, refunded load and matching ledger evidence; bank posting time is not promised |
| Top-up denied/failed/canceled | Definitive outcome and released paid reservation, with release ledger evidence; never presented as successful payout |
| Maintenance history moves into resolved | Report reference and saved resolution; no internal staff notes, implied refund or implied machine start |

Pending, approved-but-not-paid, unknown, manual-review and `support_required`
states produce no completed-outcome notice. A manually recorded replacement
arrangement is not a confirmed vend. Machine outcomes do not modify Maintenance.
Same-day claims are excluded from the old credit-decision trigger and its send
eligibility check to prevent duplicate or misleading promo-only notices. Legacy
claims keep their existing path. Internal `admin_note` is no longer rendered in
legacy credit mail either; no explicit customer-visible message field exists.
This changes legacy credit payload hashes, so previously attempted jobs remain
subject to the existing changed-payload refusal/reconciliation rule.

All notices reuse `private.mail_outbox`, the branded HTML/plain-text renderer,
and the existing `mail-delivery` worker. Triggers enqueue in the business
transaction; deferred top-up/machine triggers wait until the related financial
writes in that transaction are complete. Permanent unique event keys are
`topup_refund_outcome/<refund UUID>`, `machine_issue_outcome/<claim ID>`, and
`maintenance_resolved/<history ID>`. Same-status maintenance notes do not enqueue;
a reopen/re-resolution is a new event and suppresses the obsolete unsent one.
There is no historical backfill and no new send endpoint or financial retry.

`mail_allowed` rechecks verified recipient, email changes, account deletion,
bans, bounce/complaint suppression and exact business evidence at claim/prepare.
Machine outcomes also require the original session to remain started without a
refund; a late Void or support escalation suppresses a queued success notice.
Mail failures never repeat the business operation. Existing bounded rate-limit
retries keep the same job/provider idempotency key; ambiguous sends stay
`uncertain` for reconciliation. Queued, provider-accepted and delivered remain
distinct. Already-dispatched mail cannot be recalled after a later state change.
These are transactional only, independent of newsletter consent/postal address.
Replies and customer contact must use `support@cleanstreamlaundry.com`.

### Setup and Serial QA

Before any authorized activation, review/apply the actual machine prerequisite
chain and this email migration, then deploy `mail-delivery` with the updated
`_shared/mail.ts` renderer. Do not deploy the new enqueue migration while an old
worker can claim unsupported kinds: pause the existing worker for the coordinated
change, or deploy the compatible renderer first. Resume only after schema/source
readback. This is a rollout instruction, not authorization to change remote state.

Reuse the already configured verified sender, support reply-to, restricted Resend
key, worker secret/schedule, project/key selector, content/link approval and
database enabled/rollout settings. No additional provider template, API key,
subscription, postal address or scheduler is required. Review new customer copy
under the existing content-approval gate. Verify real activation and scheduler
state before claiming live coverage; missing eligible email or suppression means
the customer needs an in-app/support route. Business records remain authoritative.

The focused SQL and renderer/worker checks passed in the composer's serial QA
queue; see `.campaign-work/review-followup-20261005/QA-RECEIPT.md`. These commands
run from `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp` with
the existing approved Deno cache and `PG_BIN` pointing at the approved PostgreSQL
17 bin directory. No network/provider/database credentials are needed. The SQL
runner creates and removes a disposable local cluster; it must not target a
hosted database.

```sh
deno test --cached-only --frozen supabase/functions/_shared/mail.resolution.test.ts
PG_BIN="$PG_BIN" node --test --test-concurrency=1 scripts/resolution-mail.test.mjs
```

Composer aligned the legacy credit renderer assertions with private-note
exclusion. Both `mail.credit-decision.test.ts` and `mail.resolution.test.ts`
passed; no internal note was restored to make an assertion pass.

The new SQL suite uses the backend's composed machine-issue fixture and actual
migrations. Run its definitive wallet/replacement cases together with backend
machine-resolution acceptance before freezing the integrated batch. Preserve
unchanged existing worker/lifecycle acceptance; do not infer hosted delivery from
mocked transport or disposable PostgreSQL. Approved-recipient end-to-end sending,
provider events and post-deployment readback remain separately authorized work.
Official references checked for this batch: [Supabase triggers](https://supabase.com/docs/guides/database/postgres/triggers),
[Stripe refunds](https://docs.stripe.com/refunds), and
[Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys).

## Current Activation

October 2 Owner clarification: no promotional email or recurring newsletter is
planned; only rare, opted-in informational updates, alongside necessary account,
payment, security and qualifying service notices. No postal address is requested
and it is not an app-release blocker. Preserve consent/unsubscribe/suppression;
do not silently broaden prior consent or label commercial content transactional.
Promotional delivery stays unused. Existing newsletter wording needs a scoped
alignment before optional informational delivery is presented as available.
The actual content determines email classification, not frequency or opt-in.

October2: actual provider replay of the matched support welcome's delivered event
passes: same event, provider attempts1->2, HTTP200, exactly-one welcome/send and
unchanged full outbox/event fingerprints and receipt counts. No email resent,
recipient suppressed or secret read. This closes duplicate hosted delivery-event
acceptance, not bounce/complaint handling. Approval requested for two isolated
official Resend test-recipient Auth accounts; no fixture accounts created yet.
Receipt: `.campaign-work/mail-provider-acceptance-20261002/RESULTS.md`.

October2: actual Android password-reset request delivers the branded recovery
email into the approved support inbox. Its six-digit code verifies in the real
native app and opens the empty new-password form. Two misleading app labels
were changed from link to code;22 existing page tests pass. No new password is
entered/submitted; that final UI action is user-assisted. No resend, newsletter
or provider suppression event. Receipt:
`.campaign-work/password-recovery-20261002/RESULTS.md`.

October2: all13 saved hosted Auth templates pass text-layout inspection at desktop
and346px email widths (26 readings). This is provider-preview layout, not Go
escaping or full email-client proof. The existing Outlook QA confirmation's logo
now decodes correctly at80x64 (natural256x204) after **Show blocked content** for
that message. Outlook explicitly blocked the untrusted sender's external images;
no Safe Senders/global setting, template, security header or resend was needed.
The text wordmark remains visible when images are blocked. Supabase's preview
still fails to load that same valid image, without an image-specific console
error; do not treat that vendor preview as a delivered-email failure.
See `.campaign-work/email-logo-20261002/RESULTS.md` and the retained26 text-layout
readings in `.campaign-work/email-render-acceptance-20261002/RESULTS.md`.

Flutter newsletter status/request/withdraw now share the existing Edge handler,
so transactional-mail activation alone no longer advertises newsletter availability.
Withdrawal remains allowed while newsletter sending is disabled. The two-file
client correction passes88 service/controller/page cases and clean scoped analysis;
no schema or provider setting changed. See `.campaign-work/newsletter-status-20261001/RESULTS.md`.

October 1: transactional delivery is enabled for new eligible events from
`2026-10-01T14:10:00.364071Z`, without backfill. Sender:
`notifications@updates.cleanstreamlaundry.com`; replies: `support@cleanstreamlaundry.com`.
The existing worker and newsletter endpoint now separate postal-dependent newsletter
availability from account-only mail. One service-only claim filter prevents queued
newsletters from blocking transactional jobs. Newsletter sends remain unavailable
until the real mailing address is supplied; unsubscribe remains available.
Hosted support QA now verifies real Auth confirmation/code delivery to the open
Outlook Inbox, followed by one real scheduled welcome and one restoration notice.
Both app notices have correlated sent/delivered webhook rows and one attempt each.
The obsolete deletion notice was suppressed before dispatch after prompt restoration.
No newsletter consent was created. Receipt:
`.campaign-work/hosted-auth-20261001/RESULTS.md`. Other Auth flows/templates and
bounce/complaint/marketing hosted acceptance remain distinct. Local no-login
unsubscribe, sending-disabled withdrawal and signed bounce-adapter checks already
pass in the295 Deno/178 SQL child cases below; do not reopen those unchanged suites.
Promotional end-to-end delivery depends on the assigned postal-address decision.
The duplicate
DMARC record has now been removed in GoDaddy, preserving the existing reject policy,
alignment, reporting recipient and TTL. This supersedes the historical DNS and
disabled-state notes below.
The Owner will not provide a business mailing address and has excluded promotional
email. Do not ask again, invent one or purchase a mailbox. This does not block
transactional mail. Preserve existing consent records rather than silently
repurposing them. Published privacy wording reflects the earlier
split, verified in Chrome after deployment `dpl_ETLphbSywxainWVqUAG7jpEvuzjC`.
Hosted metadata readback `5441a3` confirms worker/newsletter version37 and webhook
version36 ACTIVE, with the reviewed gateway exemptions. This proves configuration,
not successful delivery or signature handling. Postal-split local acceptance now
passes 295 active Deno cases, 14 isolated pre-split payload comparisons and 178 SQL
child cases (six additional parent results). The initial Deno command passed 269
but exited 1 on a scoped environment-permission loader issue; only that blocked
credit module reran and passed 26. No product failure, hosted send or runtime-source
change. Commands, source hashes and logs: `.campaign-work/mail-qa-20261001/HANDOFF.md`.

### Controlled Provider Delivery Check

The22:31-22:41UTC support-account sequence above supersedes the app-delivery gap
below. The earlier console test remains diagnostic, including its unmatched
callbacks; it was not manually correlated or replayed to manufacture a pass.

On October 1 at 16:34 UTC, Resend's built-in draft-template test sent exactly one
message to the approved `support@cleanstreamlaundry.com`, from the configured
notifications sender with support as reply-to. Subject:
`[TEST] Clean Stream email delivery check - no action required`.
Provider email `01a0f851-75f0-73b9-bbd9-99ae21519bdb` shows sent and delivered.
This proves recipient-server acceptance, not inbox placement, human receipt,
the dedicated API key, Auth SMTP, outbox dispatch or customer-template rendering.
The diagnostic template `5eebc2e4-0a81-4645-8cbc-9c0cb710f391` remains an unpublished
draft, disconnected from application flows; no account, consent or financial
event was created and no credential was accessed or changed.

Both provider events reached the configured webhook but returned HTTP503
`mail_request_failed`. The test has no outbox tag or matching provider record;
the deployed `mail_record_webhook` deliberately raises retryable `event_unmatched`
in that case. Read-only query f5555c confirms zero matching outbox/event rows;
its signature/ACL/body were also read back without mutation. Do not
invent an outbox record, weaken correlation or call this successful webhook
reconciliation merely to accept a console test. Matching app-event delivery and
suppression still require acceptance through the real app flow. No manual replay
was triggered; provider retry behavior remains unchanged.

Custom Auth SMTP is already enabled in the correct Supabase project: the rendered
October 1 console shows `smtp.resend.com:465`, sender
`noreply@updates.cleanstreamlaundry.com`, display name `Clean Stream Laundry`.
This existing Auth sender is separate from the notifications worker sender above.
The stored password was not read or changed. Prior references to missing SMTP setup
below are historical; the later support-account confirmation verified actual Auth
inbox delivery as recorded in Current Activation.
After activation, hosted rejection checks `df7045` pass: unauthenticated worker
and newsletter status return 401; unsigned webhook returns 400 `invalid_signature`.
These requests contained no user identity, recipient or valid token/signature.

## Prior Evidence

Updated 2026-09-30. Local consent/outbox/welcome code, Flutter preferences, public newsletter page and worker scheduling are implemented. All 13 branded Auth templates and seven security notifications are saved in hosted development. The current reviewed five-file closure is deployed to all three mail endpoints in `dnuuhupoxjtwqzaqylvb`, each ACTIVE version 6 with unchanged gateway settings. Postflight confirms sending, rollout and refund-recipient configuration remain off. Four non-mutating rejection smokes pass (worker GET 405, unauthenticated worker POST 401, missing newsletter token 400, unsigned webhook 400); signed-event and delivery acceptance remain open. The user-approved seven-source transaction installed base/refund-request/lifecycle mail schema with sending disabled and no rollout date, without historical enqueue/backfill. Resend team/domain, restricted key and six-event delivery webhook are verified. Credit-decision notices pass 79 scoped local cases using this outbox; their newer migration requires admin prerequisites and is not yet hosted. Sender/postal/worker configuration, SMTP, Cron and actual delivery remain; no emails were sent.

Unauthenticated empty-request observations: newsletter returns 401 `session_required`, worker returns 401 `unauthorized`, and webhook returns 503 `webhook_disabled` because its signing secret is absent. The initial smoke assertion expected 401 from all three and exited 1; source confirms the webhook's 503 is intentional. This proves denial while unconfigured, not configured signature validation or delivery. Initial Edge secret-name inspection found no `CLEANSTREAM_MAIL_*`, newsletter or dedicated Resend configuration; the existing legacy `RESEND_API_KEY` was not evidence of component setup.

The user approved the sending-only, domain-restricted worker key and created/copied it from the prepared Clean Stream Resend dialog. It is saved as `CLEANSTREAM_RESEND_API_KEY` in project `dnuuhupoxjtwqzaqylvb`, verified after reloading Edge secrets. The one-time value was transferred directly to the approved server secret, never printed or written to project files; the temporary session copy was cleared after verification. No existing key was replaced/retired and no email was sent. Do not create a duplicate worker key.

The dedicated 256-bit `CLEANSTREAM_MAIL_TOKEN_SECRET`, bound `CLEANSTREAM_MAIL_PROJECT_URL` and `CLEANSTREAM_NEWSLETTER_URL` are now saved, with persisted digests verified. The user-approved Resend webhook `d728bac3-f318-4189-b04f-be44674007ce` is enabled at this project's `/functions/v1/mail-webhook` for sent, delivered, bounced, complained, failed and suppressed events. Its signing secret is saved as `CLEANSTREAM_RESEND_WEBHOOK_SECRET`; the temporary browser copy was cleared and saved metadata verified. An unsigned empty POST returns 400 `invalid_signature`, matching the handler. The smoke command initially expected 401 and exited 1; source inspection confirms 400 is the intended rejection, not signed-event acceptance. Base schema is now installed; signed-event, suppression and actual-delivery acceptance remain unverified.

The user directed all customer-facing contact addresses and email replies to `support@cleanstreamlaundry.com`. `CLEANSTREAM_MAIL_REPLY_TO` now matches that address and its persisted digest is verified. Preserve actual operator login/Owner identities; this is not an account-email migration. Sender and business postal address, remaining settings, schema, Cron/Vault scheduling and controlled delivery still need completion. Sending remains disabled.

## Access and DNS Checkpoint

- The Resend connector still belongs to Gundex; leave it untouched. On 2026-09-30, the user-authorized Chrome session verified team `cleanstreamlaundry`, domain `updates.cleanstreamlaundry.com` with status **Verified**, and the provider's ready-to-send confirmation. Account access and domain verification are no longer blockers.
- Initial read-only Chrome inspection found three existing keys: `refund-supabase-edge` (full access), `Supabase Integration` and `Onboarding` (sending access), and no webhooks. The approved dedicated key and webhook setup above supersede that initial configuration inventory; existing keys were not changed.
- Public TXT lookup returned two DMARC records at `_dmarc.cleanstreamlaundry.com`, one with `p=reject` and another with `p=none`. No TXT answer was returned for `_dmarc.updates.cleanstreamlaundry.com`. Multiple policy records at one target are discarded by DMARC processing; reconcile the duplicate under the DNS owner's approved policy before email launch ([RFC 9989, section 4.10](https://datatracker.ietf.org/doc/html/rfc9989#section-4.10)). Do not simply weaken the policy or remove records without verifying existing mail streams and ownership.
- DNS queries and Resend inspection were read-only. No DNS, sender, credentials, subscriptions or emails were changed. Auth template/settings changes are recorded below. The domain is provider-verified; the previously observed DMARC issue, quotas, webhook suppression and actual delivery still need acceptance.

## Current Source

### Auth Template Design Approval

The user approved the first signup design, then authorized hosted-development setup. All six authentication templates (signup, invitation, magic link/OTP, email change, password reset, reauthentication) and seven security templates (password, email and phone changes; sign-in method linked/removed; MFA method added/removed) are now branded and saved in project `dnuuhupoxjtwqzaqylvb`. Composer compared every persisted body with the reviewed draft and verified every saved subject through DOM or rendered UI. All seven security switches were enabled together and verified after reload. No customer emails were sent.

Source and subject/variable mapping: [Auth templates](../supabase/templates/auth/subjects.json). QA accepted all 13 static mappings; this is not inbox delivery, adversarial Go-template execution or cross-client rendering evidence. Signup, password reset and reauthentication retain OTP; invitation, magic link and email change retain confirmation links.

Before branding, the signup subject was `Confirm Your Signup`; its body displayed `{{ .Token }}` rather than a confirmation link. Signup still routes to `/email-verification`, whose six-digit input calls Supabase `verifyOTP` with `OtpType.signup`. The approved design reuses blue/yellow branding and the 36 KB public website logo. Actual Outlook loading now passes after per-message external-image display; Supabase's preview still fails independently. A stable asset URL remains a future durability concern because the current URL contains a website build hash. Do not alter templates or security headers based only on a preview, or automatically trust senders globally. The local design preview is not a deployable template and is excluded from the repository templates.

- `lib/features/sign_up/controller.dart`: name/email/password signup, no newsletter opt-in. Local `supabase_auth_service.dart` now relies on signup's confirmation request instead of immediately requesting a duplicate; explicit user-requested resend remains. The focused auth file passes 47 tests; independent QA passes both unchanged regression paths. See [Supabase signup](https://supabase.com/docs/reference/dart/auth-signup) and [resend](https://supabase.com/docs/reference/dart/auth-resend).
- `supabase/config.toml` configures local confirmation behavior. Production Auth templates/SMTP must be checked separately.
- `supabase/functions/refund-email/`: locally replaced direct delivery with an authenticated enqueue adapter. `enqueue_refund_request_notice` derives the owned pending claim and verified active Owner recipient server-side, using permanent `loyalty_credit_requested/<refund_id>` outbox keys. Caller-supplied recipient/amount fields no longer authorize delivery. Recipient configuration defaults to NULL, so it cannot activate itself. Escaped HTML/plain text links only to the authenticated portal; emailed approve/deny links are removed. Role/email/settings changes after leasing suppress delivery, and newsletter unsubscribe does not cancel necessary transactional notices. Author 56 Deno checks and 23 SQL scenarios plus parent pass; independent source review accepts. Queued is not sent; no delivery or DNS changes occurred.
- The obsolete `_shared/refund_resolution_backend.ts` direct sender was removed after accepted outbox integration. Credit-decision mail retries independently of the financial decision; its newer migration still needs admin prerequisites before hosted activation.
- `supabase/functions/admin-portal/index.ts`: existing local admin invitations/recovery use Supabase Auth, not a second direct Resend workflow.
- The legacy immediate-deletion caller is replaced locally by server-controlled recovery and explicit restoration. Client integration is independently accepted; production enforcement and retention/balance cleanup gates remain. Published website wording still describes permanent deletion.
- New local `newsletter`, `mail-delivery`, `mail-webhook` and consent/outbox migration cover double opt-in, separate account/newsletter welcomes, deduplication and suppression. See [backend contract](newsletter-backend.md); local independent checks are accepted and hosted sending remains disabled.
- Website `/newsletter` captures a capability fragment, removes it from history, and POSTs only on explicit confirmation/unsubscribe. It does not depend on a stored Auth session or automatically retry uncertain outcomes. Public UI independently passed 51 cases before the restart; Flutter settings opt-in is integrated. Hosted gateway and actual delivery checks remain; no messages were sent during local verification.
- Welcome/confirmation HTML reuses existing brand colors with escaped descriptive links and a plain-text alternative, without remote assets or a new template framework. URL-encoded provider forms can only unsubscribe. Webhook decoding preserves exact UTF-8 bytes (including BOM) before signature verification; invalid encoding and non-string correlation tags fail closed. Independent 94-case review and seven unchanged boundary regressions pass; the author's portable ten-case bounds file also passes. Real email-client rendering remains unverified.
- New HTML changes the payload fingerprint. Preserve outbox event keys and prior-attempt hashes: existing changed-payload protection intentionally refuses uncertain replays. Reconcile attempted jobs before any approved template rollout; never clear their records to force sending.
- [Scheduled worker setup](mail-worker-scheduler.md) is integrated with 25 SQL scenarios plus parent passing independent QA. Explicit operator setup schedules one existing worker invocation per minute with Vault-sourced credentials, preserves rollout gates and refuses duplicate named or unnamed schedules. Disable removes only that job. Synthetic extension tests do not prove hosted Cron execution; no hosted schedule or secret was created in this batch.
- Deletion-scheduled and explicit-restoration notices are now integrated through the same outbox and lifecycle transaction, with 29 SQL plus 30 renderer/worker tests accepted. Exact server timestamps and per-request event keys prevent duplicate/replayed notices; current lifecycle state and mailbox suppression are rechecked before sending. Restoration suppresses obsolete queued deletion notices without reviving newsletters. Copy directs the user to sign in, verify identity and explicitly restore in the app; the existing public deletion page is information, not an authorization link. No new mail service, permanent-cleanup claim, automatic restoration or hosted notice activation was added. The first SQL run found a fixture singleton removed by TRUNCATE CASCADE; only the reset fixture was corrected, with no weakened assertion or production change.
- Named mail-secret selection is integrated locally: 33 new cases independently pass with typecheck; author also retains eight passing adapter regressions. `CLEANSTREAM_MAIL_SECRET_KEY_NAME` selects one exact entry from `SUPABASE_SECRET_KEYS` for privileged RPCs and sends it in `apikey`, never a fake JWT. An explicit missing/invalid selection fails closed; no default or legacy fallback. With the selector absent, existing legacy behavior remains. User-bearing newsletter calls are unchanged. No key, runtime variable, gateway or provider setting was changed; see [cutover](supabase-key-migration.md#mail-component-cutover).
- The separate caller-public selector is now integrated after 32 new plus eight compatibility tests and independent source review. `CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME` selects one exact public entry for authenticated newsletter/refund-notice RPCs while preserving the captured user bearer. Absent selector alone keeps legacy ANON behavior; invalid configuration fails before HTTP. Service/no-login branches remain unchanged. No hosted key was created or retired.
- Live Chrome review on 2026-09-30 UTC found public Privacy/Terms dated August 3, 2026 and deletion instructions describing removal/anonymization without normal wallet restoration. Published retention was up to seven years for financial records and two for security/support/maintenance, with legal exceptions. Those are historical published statements, not approval of the new retention design. The user has now selected `support@cleanstreamlaundry.com` for all customer contact; update the public support/deletion links with the coordinated website release. No messages or deletion requests were sent.

## Approved Targets

| Event | Audience / rule |
| --- | --- |
| Verified account creation | One nonpromotional account welcome, including verified social signup; independent of newsletter choice |
| Newsletter request | Optional unchecked purpose-specific opt-in, separate from signup/terms/purchase; confirmation only |
| Newsletter confirmation | One newsletter welcome after separate confirmation; account verification is not marketing consent |
| Deletion scheduled | Transactional notice after commit, exact deadline/timezone and explicit restore route |
| Restoration complete | Confirm only after successful restore; no duplicate welcome or automatic resubscription |
| Permanent deletion complete | Confirm completion only after successful cleanup; disclose lawful retention exceptions |

- Persist consent purpose/text version, source, request/confirmation times, and unsubscribe state. Use expiring single-use newsletter confirmation and bounded request/resend rates; do not enroll existing users automatically.
- Durable business-event deduplication must survive provider idempotency windows. Retry transient delivery failures independently of the account/refund operation, with bounded backoff, provider IDs, and visible terminal failure. Reconcile uncertain sends instead of blindly replaying them.
- Provide visible no-login unsubscribe and applicable one-click headers, sender identity, and postal/contact details. Unsubscribe immediately prevents queued marketing; necessary account/payment notices remain separate.
- Hard-bounce/complaint suppression must not be bypassed for transactional mail; use an in-app/support path when delivery is unavailable. Verify webhook signatures on raw bodies, deduplicate, and handle reordered events.
- Suppress marketing immediately on deletion request. Restore preserves prior account identity but does not reactivate newsletter consent. Cancel stale deletion-related work after restore/finalization.
- Do not publish 30-day promises until backend recovery exists. Do not add promotional content to an account welcome or conflate terms acceptance with marketing consent.

## Ownership and Launch Gate

Feature 2 owns consent/settings/restore UI; Feature 1 owns templates consistent with existing brand; Backend owns records, delivery, verification, and retries. Prefer a small durable outbox or existing equivalent only where it removes real duplicate/retry complexity, not a general email framework.

Verify sender/domain ownership, SPF/DKIM/DMARC, production Auth templates, quotas, delivery/suppression behavior, privacy disclosures, approved content, postal address, and test recipients before activation. Never print API keys, send to production lists, or activate paid capacity during setup. Platform access and legal/business wording remain gates in [operations](operations.md).

## Acceptance and References

- No newsletter without confirmed opt-in; unchecked consent never subscribes. Replay/refresh/email change/restore does not resend account welcome.
- Unsubscribe wins against queued sends; retries cannot repeat a refund; failed notices remain independently recoverable. Deleted/restored accounts receive only appropriate committed-state notices.
- Test bounce/complaint, duplicate/out-of-order webhook, expired confirmation, already-unsubscribed, rate limit, and uncertain-send handling.
- Recheck official [Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys) and [webhook verification](https://resend.com/docs/webhooks/verify-webhooks-requests) before implementation. Provider idempotency is not permanent application deduplication.
