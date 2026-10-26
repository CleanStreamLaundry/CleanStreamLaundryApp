# Cortina Reconciliation Scheduler

**Installed and enabled in development; functional acceptance UNTESTED.** The
user's later instruction supersedes the initial dormant-installation approval.
Edge execution is true with fixed `sandbox` routing, matching the current machine
configuration; the single Cron job is active (31efc3/028265). No manual test or
payment/provider mutation was invoked; scheduled observation now runs normally.
Receipts: [operations](operations.md). Cost/throughput and functional acceptance
remain unverified, not reasons to describe the feature as disabled.

One fixed job, `cleanstream-cortina-reconcile`, uses `* * * * *` and the command
`select private.cortina_reconcile_tick();`. Initial setup commits it **inactive**;
the separate approved activation is recorded above. The
private invoker reads two dedicated Vault entries only when that exact owned job
is active, then queues one 55-second HTTP request to the existing one-row worker.
It adds no queue, retry engine, public RPC, extension, migration or payment logic.
Claims, leases, evidence and retries remain the existing worker's responsibility.

## Prerequisites And Dormant Installation

1. For the approved installation, use only development project `dnuuhupoxjtwqzaqylvb` and
   its trusted `postgres` operator. Existing Cron/Vault/pg_net must be present;
   the scripts install none and fail closed if required capabilities are absent.
2. Separately install the approved existing
   `supabase/migrations/20260930161734_cortina_closed_app_reconciliation.sql`.
   Its UPDATE queues historical unresolved sessions: this is **not** a no-backfill
   prerequisite to apply casually or replay. Setup only requires the existing
   claim/finish functions; it never runs that migration or changes session rows.
3. Deploy the accepted `supabase/functions/cortina-reconcile/index.ts` closure
   with existing `verify_jwt=false`; the worker validates its dedicated bearer.
   Keep `CORTINA_RECONCILIATION_ENABLED=false` during setup. Its fixed
   `CORTINA_RECONCILIATION_ENVIRONMENT` must be `sandbox` or `production`, aligned
   with the approved worker/provider configuration. It is NOT a body parameter;
   there is no second environment job. Nothing here enables production activity.
4. Use the approved credential setup to securely create exactly one of each Vault entry:
   `cleanstream_cortina_reconcile_project_url` containing the exact standard URL
   `https://dnuuhupoxjtwqzaqylvb.supabase.co` with no trailing slash, and
   `cleanstream_cortina_reconcile_worker_secret` matching Edge
   `CORTINA_RECONCILIATION_WORKER_SECRET`. Use a dedicated value of at least 32
   characters, without surrounding whitespace/control characters. Do not reuse
   mail, Stripe, service-role or named Supabase keys. Use trusted secret UIs, not
   SQL literals, shell arguments, files or logs. A scoped operator may also generate
   the value inside Vault and pipe the captured result in memory to the official
   Edge secrets CLI, without emitting either child's output. Vault and Edge are not auto-synced.
5. Run the complete `cortina-reconcile-setup.sql` transaction in that project's
   operator SQL interface. It requires unique Vault names and serializes these
   setup/disable scripts with a shared advisory lock. Pause independent dashboard
   edits during setup; the managed Cron table cannot be directly locked by this
   operator. An exact inactive job is retained; active, duplicate, foreign
   owner/database/command/schedule or recognizable alternate-worker jobs stop
   setup. A filtered Cron inventory also fails, without changing RLS/privileges.
   Do not split the transaction or change guards to force installation.

The setup never calls the tick, reads decrypted credential values, changes Edge
flags or enables a job. Vault values are validated at dispatch, including an exact
project URL match; setup alone does not prove secret synchronization or delivery.
Approved named Supabase key creation/staged configuration remains a separate
Composer task; the optional worker key selector and absent-only legacy fallback
remain unchanged here, and old keys must remain active.

## Disable And Later Activation

`cortina-reconcile-disable.sql` sets only the matching owned job inactive, keeping
the job and run history. Missing/already-inactive is harmless; an ownership or
command conflict fails instead of modifying another job. It does not touch mail,
claims, attempts, audit/financial records, Vault credentials or worker source.
For an emergency pause, separately set Edge `CORTINA_RECONCILIATION_ENABLED=false`
through the approved configuration path. Neither action cancels queued HTTP or
work already dispatched. Do not reset claims or replay uncertain outcomes.

Activation was separately approved for development. It requires valid
matching credentials, the fixed Edge environment and
`CORTINA_RECONCILIATION_ENABLED=true`, then only
this named job may become active. No enabling command is supplied here. Worker
responses401/503 and Cron success are not reconciliation success; existing session
and event outcomes remain authoritative. Cost/throughput, extension behavior,
auth/ACL, transaction safety, pause and live worker acceptance are **unverified**.

No secrets appear in the Cron command or SQL output. pg_net temporarily holds
authorization headers in its restricted queue; do not export it, log headers or
grant application roles Vault/cron/net access. The tick sanitizes extension errors.
Secret rotation requires pause first, coordinated Edge/Vault updates and later
approved reactivation, never resetting reconciliation history.

Implementation references: [Supabase scheduling](https://supabase.com/docs/guides/functions/schedule-functions),
[Vault](https://supabase.com/docs/guides/database/vault),
[pg_net](https://supabase.com/docs/guides/database/extensions/pg_net),
[pg_cron job controls](https://github.com/citusdata/pg_cron#altering-a-cron-job).
These informed source authoring, not runtime verification.
