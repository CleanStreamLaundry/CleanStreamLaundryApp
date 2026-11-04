# New-Payment Control: Development Deployment

User identifies the hosted project as DEVELOPMENT and authorizes enabling the
requested features then testing. This file scopes this feature's reviewed
dependencies; it does not claim deployment or authorize paid provider calls,
key retirement, retention cleanup, or a blanket migration push. Composer must
confirm the exact development project and existing prerequisite state first.

## Feature Delta

1. SQL: only `20260930193130_new_payment_service_control.sql`, already accepted
   with 39 distinct child cases plus parent across QA runs. Initial row is enabled.
   Preserve its reviewed bytes; do not reapply if already recorded/applied.
2. Edge deployment targets: `paymentIntent`, `createCheckoutSession`, `cortina-vend`.
   Bundle the new `_shared/new_payment_control.ts` with these three functions.
   Only creation logic/error mapping changes; unchanged named-key transports,
   caller verification and existing runtime helpers must accompany their bundles.
3. No config.toml, gateway verification, public schema exposure, schedule, UI,
   environment-variable addition, SDK/lock or webhook API-version change.

## Existing Prerequisites, Not A Blanket Apply List

- Financial baseline: `20260526010000_wallet_ledger_compliance.sql`,
  `20260803150427_cortina_qr_remote_vend.sql`, and accepted
  `20260929231120_serialize_wallet_financial_writes.sql`; existing wallet account,
  balance view, ledger and Cortina payment/reversal helpers must be present.
- Canonical admission chain: `20260929223124_protect_profile_authority.sql`,
  `20260929234955_loyalty_policy_acceptance.sql`,
  `20260930005456_account_admission.sql`,
  `20260930013417_enforce_profile_terms_admission.sql`,
  `20260930063923_recoverable_account_deletion.sql`, and
  `20260930171558_human_wallet_spend_admission.sql`. Verify current
  `get_admission_status()`, lifecycle tables and both human debit signatures;
  do not substitute a legacy role-only evaluator or overwrite later accepted SQL.
- Accepted Cortina selectors/history/binding/ownership are existing prerequisites
  of the deployed runtime, not new changes from this feature:
  `20260922224735_cortina_price_array_selectors.sql`,
  `20260928132533_link_cortina_transaction_history.sql`,
  `20260930154259_freeze_cortina_payment_bindings.sql`,
  `20260930163919_cortina_callback_provider_ownership.sql`, and the existing
  machine availability column/guard from
  `20260928151021_admin_operations_extensions.sql`.
- Reuse accepted `_shared/supabase_keys.ts`, `_shared/wallet_funding_admission.ts`
  and `_shared/cortina.ts` unchanged, including current outcome safety and
  `record_cortina_card_payment` verification. No refund, callback, reconciliation,
  cleanup, complaint, storage or mail migration is newly required by this delta.

If any prerequisite differs or is absent, stop this feature rollout for an exact
dependency review. The list does not authorize replaying old migrations, applying
all pending migrations, or creating replacement shared routines.

## Behavior And Rollout Boundary

The reader must return literal JSON `true` to allow new payment creation. False,
null, malformed data, missing RPC, database/HTTP failure and the eight-second
deadline all produce sanitized HTTP503 `new_payments_unavailable`.
Funding checks follow existing caller verification/canonical admission, before
wallet creation and after its await immediately before Stripe. Direct-machine
intent/Checkout creation also checks the reader, without inventing admission policy.

Cortina checks after existing frozen-binding/idempotent funded-replay handling,
before new Stripe creation or caller-bound wallet debit. An empty unfunded draft
may be inserted before refusal, as approved; it is not marked failed, charged,
debited or started. Pending replay that could create a provider object is gated.
An exact SQL `PT503/new_payments_unavailable` refusal after the Edge check also
returns sanitized503 without changing the draft or invoking Start; unrelated
wallet failures retain their existing handling.
Funded replay, quote/status/confirmation, paid Start, refunds and reconciliation
remain independent of this switch. Already-dispatched provider work cannot be
undone; the final check is not an atomic transaction with a provider.

Apply SQL before deploying the three creation functions. Confirm enabled reader
and exact EXECUTE/table grants from `NEW-PAYMENT-CONTROL.md`. Enabled preserves
behavior; deployment does not require a false/true operational toggle. Any hosted
disabled-path rehearsal needs explicit development-only scope and must restore
the prior value. No paid service/provider action is part of local verification.
Retain unchanged status/webhook/reconcile deployments; do not disable the function
gateway or bulk-disable machines to simulate this control.

Operational rollback is the reviewed operator-only enabled=true update, not
dropping the reader/table. Code rollback must preserve existing canonical gates
and review all three Edge consumers together. No money cancellation/refund or
queue drainage is implied by either direction of the switch.

## Local QA Accepted

Production delta: six files (new shared reader, two funding logic files, their
two indices, Cortina logic). Existing nearest funding fixtures are updated only
to provide enabled control responses; original behavioral assertions remain.
New coverage uses fake HTTP with the real Supabase/Stripe SDKs and synthetic
credentials. It verifies sanitized refusals, no provider/debit before approval,
unchanged caller/key headers, guest creation, pending/funded replay, actual paid
Start simulation and pending-card confirmation while disabled. No network action.

The lane's historical `_shared/cortina.ts` is not edited/copied. The local-only
`cortina-vend/new-payment-control.import-map.json` points its import at the exact
accepted active helper read-only. Do not deploy/integrate that test import map;
integrated tests use the active helper directly without redirection.

QA accepted **139 passes**: helper15 + Cortina25 + funding adapter65 = 105 focused
cases, zero failures/typecheck0, session93870 exit0/chunk3e246d; original nearest
logic34, zero failures/typecheck0, direct exit0/chunk8fa0ce. All processes exited.
No author checks or SQL reruns. Admission85 fixture was adapted with an enabled
control response but that older suite was NOT rerun; no new runtime claim for it.
Exact late-SQL-refusal regression and unchanged wallet-error controls passed.
Primary executed command, owned lane root:

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env --v8-flags=--max-old-space-size=768 --import-map=supabase/functions/cortina-vend/new-payment-control.import-map.json supabase/functions/_shared/new_payment_control.test.ts supabase/functions/paymentIntent/index.test.ts supabase/functions/createCheckoutSession/index.test.ts supabase/functions/cortina-vend/new-payment-control.test.ts
```

Nearest compatibility files executed separately (no admission85 repetition):

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env --v8-flags=--max-old-space-size=768 supabase/functions/paymentIntent/logic.test.ts supabase/functions/createCheckoutSession/logic.test.ts
```

No network permission; unknown requests fail in fake HTTP dispatchers. Neither
command was run by the author. Hosted deployment/enablement is still separate
from this local evidence; no paid provider or remote action performed here.
