# Operations and Incident Response

October 1: the aggregate snapshot executed successfully (`f66dd0`, 14:32:03 UTC).
Containment/rollback procedures have not been rehearsed. They use existing services; no monitoring subscription,
database listener, automatic alert campaign or new permissions are introduced.
Testing/verification is now stage 3 in [priorities](../APP_FIX_PRIORITIES.md).
The Owner assigns an incident lead and support coverage before launch.

## On-Demand Snapshot

[operations-snapshot.sql](../supabase/ops/operations-snapshot.sql) returns aggregate
queue counts, oldest timestamps, rollout switches and the latest two worker job
states. It is one read-only transaction with short statement/lock timeouts, no
provider calls and no customer, token, payload, key or amount output. It requires
the existing operator database role and reviewed mail, lifecycle, refund,
payment-control, reconciliation and Cron objects. A missing prerequisite or
timeout is an incomplete snapshot, not a reason to install objects, widen grants
or report healthy service. Do not expose this script through a client RPC.

Run it only for an authorized connected check with the existing secure
operator connection. Use the CLI's stop-on-error mode; do not put passwords in
commands, screenshots, a web bundle or this document. No schedule is installed
for this report. Capture the UTC timestamp and necessary aggregate output only.
Take a snapshot when investigating an incident and at approved rollout points;
an empty result is not proof of healthy payments, email or customer experience.

| Signal | Response |
| --- | --- |
| `support_required`, `timed_out` or `failed` vend sessions | Open the scoped session through authorized support tooling. Compare its stored provider references and environment with Stripe/Nayax; never infer a refund or repeat Start from a timeout or label alone. |
| Reconciliation due count/oldest time grows across observations | Check the single worker's enabled environment, named-key selector and scheduler state. A completed Cron invocation only proves HTTP enqueue/SQL completion, not worker/provider success. Do not enlarge batches or replay financial actions as an outage workaround. |
| Refund `unknown`/`pending`, or stale `approved` | Owner reviews the existing refund/provider reference. Preserve the reservation and idempotency key; retrieve uncertain outcomes rather than creating another refund. `failed` is not blanket authority to release funds. |
| Mail `uncertain`, expired leases or repeated failures | Preserve permanent outbox keys and suppression. Check restricted worker/provider diagnostics. Do not resend from another service or convert uncertain delivery into a fresh event. New transactional notices are enabled; newsletter delivery still lacks the assigned postal address. |
| Expired pending account count | Record the backlog. Until approved cleanup exists and is enabled, this is a retained pending account, not completed erasure. Never zero credits, delete Auth or release a financial hold manually to clear the counter. |
| Function errors/callback rejection or browser errors | Use the existing Supabase Edge logs, Vercel deployment logs and provider delivery logs for the incident time range. These failures may not produce a database row, so the snapshot cannot count them. Keep tokens, request bodies and personal data out of shared reports. |

## Contain Without Losing Settlement

1. Record UTC start, impacted app/build/location, symptoms and the responsible
   Owner. Preserve audit history and referenced deployments; do not export raw
   customer rows or credentials into a task log.
2. For unsafe new payments, an authorized operator can use the existing
   `private.new_payment_service_control.enabled` switch. Restrict any manual
   update to its singleton row in a transaction. This is server-side admission
   for new operations, not cancellation of a dispatched charge or vend. Leave
   settlement callbacks, status recovery and refund reconciliation available.
3. For a single machine, use its existing authorized configuration workflow to
   disable new vends. Keep terminal mapping and existing payment references;
   do not delete the machine or edit an in-flight payment's immutable binding.
4. For email, use the existing [disable script](../supabase/ops/mail-worker-disable.sql)
   and the mail-settings gate. Stopping future schedules does not cancel a
   request already queued by pg_net or accepted by Resend. Keep the delivery
   webhook available for suppression and final outcomes.
5. For reconciliation, use the [dedicated disable procedure](cortina-reconcile-scheduler.md)
   and its Edge enabled
   flag when deployed. Do not remove leases, event keys or provider references.
   Its worker reads existing provider outcomes; it must never issue a new charge,
   Start or refund as part of a recovery retry.
6. For a bad mobile build, use the existing [release controls](../config/firebase/RELEASE-CONTROLS.md).
   Cached/offline clients and forged version headers still require backend
   authorization. Do not block necessary support/recovery behind optional consent.

Changing gates is an authorized incident action, not part of this implementation
pass. Current paid-service, destructive-cleanup and legacy-key-retirement
approvals remain separate. Do not touch Gundex or rotate a project-wide key as a
substitute for isolating one component.

## Recover and Roll Back

- Prefer the prior compatible client/function artifact or a forward fix. Record
  the exact revision, configuration names and operator; never include key values.
- Preserve read/write compatibility: a version-2 vend writer needs its reader.
  Do not roll the website back to an incompatible return/attachment reader while
  retaining the newer writer or private bucket.
- Never reverse a schema change by deleting ledger/events, dropping protective
  constraints, reverting to a contained insecure endpoint, or replaying callbacks.
  Database restoration needs separate authorization and provider reconciliation;
  restoring a backup does not undo charges, emails or machine starts.
- Leave legacy keys available during approved overlap until all consumers and
  rollback paths are accepted. Never restore a compromised credential.
- Before restoring service in stage 3 or an authorized incident, check pending
  operations, source/provider agreement, admission controls and the affected
  customer path. Perform only the checks relevant to that incident; no automatic
  full-campaign rerun. Record unresolved cases with an Owner and next action.

## Support and Launch Handoff

Customer contact is `support@cleanstreamlaundry.com`. The Owner supplies coverage
hours and escalation contacts; do not invent an SLA or send operational mail to
an unapproved recipient. A restricted support case needs the affected location,
approximate time, error/state and necessary existing transaction reference, not
passwords, card details, MFA seeds or payment access tokens. Owner authority is
required for global-wallet/refund decisions and verified customer MFA recovery.

Launch still requires the assigned provider/access inputs, approved policy and
retention, monitored delivery paths and a stage-3 rollback rehearsal. This file
provides operating procedures, not evidence that those prerequisites passed.
