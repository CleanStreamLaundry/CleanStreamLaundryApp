# Email and Consent

Local source and public DNS reviewed 2026-09-29; no Clean Stream sender, production SMTP, or remote template configuration verified. Targets below are not implemented. Reuse existing Supabase Auth and Resend infrastructure instead of adding another provider.

## Access and DNS Checkpoint

- The connected Resend account lists only `gundex.io`. Do not add Clean Stream there, replace the connection, or modify that domain without a separately verified account/ownership decision. Clean Stream's existing source sends from `refund@updates.cleanstreamlaundry.com`; verify the account that owns that sender before changes or test sends.
- Public TXT lookup returned two DMARC records at `_dmarc.cleanstreamlaundry.com`, one with `p=reject` and another with `p=none`. No TXT answer was returned for `_dmarc.updates.cleanstreamlaundry.com`. Multiple policy records at one target are discarded by DMARC processing; reconcile the duplicate under the DNS owner's approved policy before email launch ([RFC 9989, section 4.10](https://datatracker.ietf.org/doc/html/rfc9989#section-4.10)). Do not simply weaken the policy or remove records without verifying existing mail streams and ownership.
- DNS queries and domain listing were read-only. No DNS, sender, templates, credentials, subscriptions, or emails were changed. SPF/DKIM, quotas, webhook suppression, and actual delivery remain unverified.

## Current Source

- `lib/features/sign_up/controller.dart`: name/email/password signup, no newsletter opt-in. `lib/services/supabase/supabase_auth_service.dart` performs Supabase signup and requests another verification email; inspect this duplication before adding welcome logic.
- `supabase/config.toml` configures local confirmation behavior. Production Auth templates/SMTP must be checked separately.
- `supabase/functions/refund-email/index.ts`: internal Resend alert; inspected code does not check HTTP success.
- `supabase/functions/_shared/refund_resolution_backend.ts`: decision email checks status and records `notification_sent_at`. The resolution handler skips already-resolved requests, so a failed email is not necessarily retryable independently of the refund.
- `supabase/functions/admin-portal/index.ts`: existing local admin invitations/recovery use Supabase Auth, not a second direct Resend workflow.
- `supabase/functions/delete-account/logic.ts` currently anonymizes wallet links and deletes Auth immediately. Current app/website wording is permanent deletion, not a recoverable state.
- No newsletter double opt-in, consent ledger, welcome sender, durable email retry/suppression workflow, or 30-day restore was found in inspected source.
- Live Chrome review on 2026-09-30 UTC confirms public Privacy/Terms still show August 3, 2026, and deletion instructions describe removal/anonymization without normal wallet restoration. Published retention is up to seven years for financial records and two for security/support/maintenance, with legal exceptions. These are current published statements, not approval of the new retention design. Support/deletion email links currently target `jacob@cleanstreamlaundry.com`; verify the desired contact before coordinated policy/email release. No messages or deletion requests were sent.

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
