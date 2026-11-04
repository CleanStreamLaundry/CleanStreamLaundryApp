# Dormant Cortina Scheduler

**Stage 1 source implementation complete; UNTESTED / UNDEPLOYED.** No SQL was
executed. No tests, analysis tools, builds, QA, provider calls, credential creation,
cloud installation or deployment verification. Active app/web remain read-only.

Owned root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/reconcile-scheduler`.
Exactly four new files: `cortina-reconcile-setup.sql`,
`cortina-reconcile-disable.sql`, `cortina-reconcile-scheduler.md`, `HANDOFF.md`.

One fixed job **cleanstream-cortina-reconcile**, matching Composer monitoring;
one minutely call to the existing one-row worker, empty body, 55-second timeout.
Environment remains exclusively `CORTINA_RECONCILIATION_ENVIRONMENT` in Edge.
Dedicated Vault names: `cleanstream_cortina_reconcile_project_url` and
`cleanstream_cortina_reconcile_worker_secret`; exact development URL confinement.

Reuses the existing mail scheduler's Cron/Vault/pg_net invoker pattern. Unlike
mail setup, this setup creates/keeps the job inactive in one transaction and
refuses an active/conflicting job. Short Cron metadata locking serializes setup
and disable; no generic flag table. Private invoker rejects non-operator callers,
has API-role EXECUTE revoked and returns without Vault/HTTP while inactive.
Disable pauses only this owned job, retaining job/run history and credentials.
No source removed; no new queue, migration, public RPC, extension or worker rewrite.
Existing leases, claims, financial records, callbacks and mail job stay unchanged.

**Installation now approved:** historical-unresolved migration, endpoint,
dedicated credential and disabled scheduler. Composer owns remote execution;
this lane performed none. The migration is not embedded/replayed by these files.
Approved named-key configuration is separate; old keys remain active. Scheduled
execution stays held; cost/throughput and testing/verification are deferred to
Stage 3. No QA command or activation SQL is queued. Source completion is not a
tested, installed or enabled scheduler. Stop here; newly approved draft-spec
cleanup implementation requires a separate Composer ownership handoff.
