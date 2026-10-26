# Server-Managed Loyalty Terms

The required document is stored in Supabase `public.loyalty_policy_documents`.
The app automatically calls the existing `get_loyalty_policy_status` RPC and
renders its JSON document as selectable headings and paragraphs. It does not
bundle the current terms or use Realtime. Public read-only policy pages use
`get_loyalty_policy_descriptor` without requiring a session.

## Current Publication (October 5)

Confirmed hosted release: current policy **`2026-10-05.2`**, 90-day recovery,
and `request_account_deletion_with_consent(p_context_id, p_acknowledged)` available.
All seven release migrations through `20261005181711` plus automatic-inventory
migration `20261005183040` are applied. Inventory followed a rolled-back hosted
rehearsal and QA 9/9 records (four install, four behavior, one parent); the one
Deno check is retained. All 13 release functions are deployed, including cleanup
v2 with its final worker hash already verified by readback.

Daily cleanup is enabled under the approved prospective 90-day policy;
past acceptances are not applied retroactively, and holds remain preserved.
Activation SQL exited 0; remote readback confirms execution/surrender enabled,
the daily Cron active, and zero pending requests/external cleanup operations.
No actual customer deletion or provider-erasure test was performed.

Website deployment `dpl_2Sxq9oEkTGrZ2JrsFPVDcTUa82P7` is promoted to
cleanstreamlaundry.com. Asset `index-CMpgsZxw.js` and HTTP 200 for Terms, Privacy
and Account Deletion with the October 5, 2026 effective date are confirmed in the
release handoff. Android build succeeded and the signed APK is ready; the user
explicitly defers Samsung installation/device tests. This docs update performs
no runtime/provider checks and makes no legal-enforceability claim. Composer
owns [operations](operations.md) and the release receipt.

## Historical Local Action-Consent Candidate (October 5)

The local-only publication status below records the pre-release stage and is
superseded by `2026-10-05.2`; do not republish the draft or replay these rollout
steps. The action-consent contract description is retained for reference.

Owner approved local implementation, not publication or forfeiture activation.
`supabase/policies/loyalty-surrender.draft.json` is the full unpublished review
candidate, including prominent initial purchase/deletion disclosures and concise
`action_acknowledgements.wallet_load` / `account_deletion` strings. It is not a
database row or a published version. Its date is provisional. Remove its draft
marker and assign a new unique version only during a separately approved,
coherent publication. Do not reuse the preservation candidate as this policy.

The app fetches `get_loyalty_action_context(p_action)` once when opening a load
or deletion confirmation. It displays the exact verified policy snapshot through
the existing legal renderer. Each load starts unchecked; changing the amount
clears agreement. Both Stripe entrypoints require a caller/session-bound context
and record immutable amount/version/hash/time/provider receipts before checkout.
Stale, changed-policy or mismatched contexts are rejected rather than silently
accepting new text. No new polling, dependencies or pricing/reward changes.

The approved purchase acknowledgement is "I agree to the Loyalty Program Terms
for this purchase." Its terms title opens the exact policy without checking the
box. The server receipt matches the displayed wording; the separate deletion
acknowledgement remains explicit.

Deletion uses `request_account_deletion_with_consent(p_context_id,
p_acknowledged)`, shows purchased/promo balances, and preserves the existing
Owner/fresh-session/explicit-restoration guards. The database rechecks balances,
records the request-time deadline and queues its acknowledgement in the existing
transactional outbox. The old argument-free endpoint cannot bypass consent.
Unknown mutation outcomes still lead to a status check, not an automatic retry.
Old 30-day and new 90-day notices remain renderable with their recorded deadlines.

Runtime wording always comes from the current published document, never this
draft. The new consent migration does not switch policy or change recovery
duration, historical receipts, balances or cleanup activation. Existing local
90-day and consent migrations require a coordinated ordered rollout; neither has
been deployed in this batch. Verification is recorded in operations.

## Initial Acceptance

- `document`: JSON object with `title`, ISO `effective_date`, and `sections`.
  Each section contains `heading` and a nonempty `paragraphs` string array.
- `version`: unique publication ID, such as `2026-10-02.1`.
- `is_current`: the unique index permits at most one current row; publish a
  replacement in the same transaction so the current document remains available.
- The RPC preserves the existing wire fields: `required_version`, `policy_text`
  (the serialized JSON), and `policy_sha256` (SHA-256 of those exact UTF-8 bytes).
- The app verifies the hash before displaying the document. The initially
  unchecked checkbox enables explicit acceptance; the server stores version and
  timestamp and retains its existing verified-session/account/MFA checks.
- Accepted versions and their content are immutable. A newer required version
  causes a new acceptance prompt. Repeated acceptance of the same version does
  not change the original timestamp. Publishing and acceptance serialize on the
  active row; stale submissions must reload and be agreed again.

## Publishing Without An App Release

Use the **Clean Stream** Supabase SQL Editor as an authorized operator. Insert a
new JSON document under a new version and switch `is_current` in one transaction.
Never edit an already published document or change a customer's acceptance.
The database rejects malformed documents and client writes. Example shape:

```sql
begin;
update public.loyalty_policy_documents set is_current = false where is_current;
insert into public.loyalty_policy_documents (version, document, is_current)
values ('NEW-UNIQUE-VERSION', '{
  "title": "Loyalty Program Terms",
  "effective_date": "2026-10-02",
  "sections": [{"heading": "Section title", "paragraphs": ["Approved wording"]}]
}'::jsonb, true);
commit;
```

Replace the example with the complete approved document; do not publish only a
changed paragraph. Read back `select public.get_loyalty_policy_descriptor();`
and check the app before announcing the revision. Publishing is an explicit
decision to require that version, not an automatic response to editing a draft.

## Historical Publication Before October 5 Release

The status and future-tense rollout statements in this section are historical;
the current hosted version is `2026-10-05.2`, not either version below.

The current published version remains **`2026-10-03.1`**, with 30-day recovery
wording. The new **local, unapplied candidate `2026-10-05.1`** in
`20261005134908_ninety_day_account_recovery.sql` changes recovery to 90 days.
It atomically creates a new document and moves the current pointer; it does not
overwrite historical documents, old migrations or customer acceptance records.
Existing users will need explicit acceptance of the new required version after
publication. Restoration does not auto-accept. No new hosted publication occurred.

The user's October 5 duration decision is approved; no renewed retention approval
is needed. Composer owns coherence with the separately revised machine-claim
clause and final publication/version sequence. Do not publish competing documents
under `2026-10-05.1`. Purchased-credit nonexpiration/no-forfeiture remains the
current business policy, not a definitive legal-perpetuity conclusion.

Version `2026-10-03.1` simplifies section 5 to customer-facing Stripe/Nayax
roles, support and necessary data sharing. It removes the internal second-purchase
explanation. The earlier `2026-10-02.1` document remains immutable; no other
policy sections or customer acceptance records were changed. The app reuses
`assets/splash-logo.png` as a static letterhead and labels consent "I have read
and agree to the loyalty card terms." The checkbox and submit action stay in
the Scaffold's reserved bottom area; only the document scrolls. Its persistent
scrollbar shows the remaining content, and end padding keeps the last line
clear of the footer. Scrolling is not an additional acceptance requirement.

## Historical Preservation Candidate Scope

The October5 local `2026-10-05.1` candidate also incorporates the restricted-use,
generally nonrefundable prepayment wording and same-day/on-site machine-remedy
clauses from the review drafts. It preserves mandatory remedies, the48-hour
unused-load refund and paid-credit preservation. It must ship with the matching
machine backend, not as a recovery-only publication. This is not hosted evidence.

The currently published document replaces the earlier review-only text and includes
the former 30-day restoration period; the local candidate implements the approved
90-day replacement. Both preserve unused purchased credit,
separate promotional-credit treatment, existing refund conditions, and support
contact. See [retention](retention.md) for the actual cleanup contract.

This batch does **not** change reward arithmetic. The earlier proposed 10% / $5
reward design remains a separate financial change; terms do not promise a rate
that the ledger does not yet implement. Existing refund deadlines and rights are
not expanded by deleting or restoring an account.

## Historical Candidate Verification

This is the earlier candidate's test plan, not a current unrun release gate.
Use Composer's release receipt for completed verification and remaining work.

New tests are authored, **not run**. In the composer serial stage:

```sh
cd /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp
RECOVERY_90_DAY_ONLY=1 PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --test scripts/account-cleanup-execution.test.mjs
PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --test scripts/server-managed-loyalty-terms.test.mjs
```

The first command covers the new publication's exact descriptor hash, preserved
history/unrelated clauses/acceptance timestamps, required reacceptance and stale
version rejection alongside recovery. The second retains historical publication
and acceptance-lock race coverage. Full client/worker commands and separate
recorded hosted restoration evidence are in [account recovery](account-recovery.md).
The earlier successful hosted restore used the old 30-day policy, not this candidate.
