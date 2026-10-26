# Mail Worker Scheduler

Hosted development setup for the existing outbox and `mail-delivery` function.
One Supabase Cron job invokes the worker once per minute, at most one outbox
claim per call, with a 55-second HTTP timeout. This adds no sending service,
custom retry loop or parallel queue. Setup is an explicit operator action, not
an automatically applied migration, and never changes rollout settings.

## Development Status

Installed October 1, 2026 UTC in `dnuuhupoxjtwqzaqylvb` after explicit approval.
Matching dedicated Edge/Vault credentials and the exact destination were verified
without returning secret values. The reviewed setup created job1, owned by
postgres, with the exact command and no application-role EXECUTE on its invoker
function. Database delivery remains false with null rollout. The first real Cron
run succeeded as a disabled no-op; no HTTP dispatch or email delivery is proven.
The later October 1 activation supersedes that disabled state: transactional mail
is enabled from `2026-10-01T14:10:00.364071Z`, with no historical backfill. The
existing scheduled worker excludes newsletter jobs until a real postal address is
supplied. Controlled later test recipient is approved as support; no manual test
message or delivery acceptance occurred. Never publish a literal postal placeholder.
Receipts and remaining DMARC work are in operations.

## Setup

1. Confirm the intended development project. Deploy the accepted mail migrations
   and worker with its custom bearer authentication (`verify_jwt=false`). Enable
   the project's existing Supabase Cron, pg_net and Vault integrations if needed;
   the SQL stops if those prerequisites are absent and installs nothing itself.
2. In the trusted Supabase Vault UI, create or update these exact named entries:
   `cleanstream_mail_project_url`: the standard HTTPS Supabase project URL, equal
   to Edge `SUPABASE_URL` and `CLEANSTREAM_MAIL_PROJECT_URL`, no trailing slash;
   `cleanstream_mail_worker_secret`: the SAME dedicated value as the Edge secret
   `CLEANSTREAM_MAIL_WORKER_SECRET`, at least 32 characters, no surrounding
   whitespace or control characters. Vault is not automatically synchronized
   with Edge secrets. Use the privileged secret UI, not SQL literals, shell
   arguments, checked-in files or logs. No Resend or service-role key belongs in
   the cron command. Setup checks entry names; each enabled tick validates values.
3. Confirm no other hosted scheduler already invokes this worker; source inspection
   found none, but does not establish hosted state. Setup refuses recognizable
   same-worker cron commands under another name and never replaces other jobs.
   As the trusted database operator (`postgres` on hosted Supabase), run
   `supabase/ops/mail-worker-setup.sql` in that project's SQL editor. It returns
   only the job ID. Running it again updates the same named job, not a second
   service. An existing same-name job with another command/owner stops setup.
4. Keep the existing rollout gates until ready: the database must have
   `private.mail_settings.enabled=true` and a reached nonnull `rollout_at`.
   Edge `CLEANSTREAM_MAIL_ENABLED=true` and all existing mailConfig sender,
   content/link, URL-binding and secret checks must also pass. This setup does
   not enable any gate, backdate rollout or backfill accounts. It may be installed
   while disabled; disabled ticks queue no HTTP and do not read secret values.

The supported scheduler destination is the standard
`https://<project-ref>.supabase.co/functions/v1/mail-delivery`, never Resend or a
request-supplied URL. A custom Supabase domain would need a separately reviewed
destination rule; use the project's standard URL for this setup.

## Observe And Disable

Inspect only nonsecret scheduler metadata:

```sql
select jobid, jobname, schedule, active
from cron.job where jobname = 'cleanstream-mail-delivery';

select runid, status, start_time, end_time
from cron.job_run_details
where jobid in (select jobid from cron.job where jobname = 'cleanstream-mail-delivery')
order by start_time desc limit 10;

select id, status_code, timed_out, created
from net._http_response order by created desc limit 10;
```

Cron success means the HTTP request was queued, NOT that email was sent.
Inspect existing outbox states for actual outcomes. A 401 suggests a mismatched
worker secret/gateway; a 503 can mean disabled/incomplete config or an uncertain
worker outcome. Never reset attempts, payload hashes or event keys to retry.
Existing worker/outbox logic alone handles rate limits, leases and deduplication.

Run `supabase/ops/mail-worker-disable.sql` as the same operator to remove only
this named job/command. Repeating it is harmless and unrelated cron jobs remain.
For immediate delivery pause, also set `private.mail_settings.enabled=false`
and `CLEANSTREAM_MAIL_ENABLED=false` using the existing configuration controls.
Unscheduling cannot cancel an already queued HTTP call or a provider send already
started. Do not erase outbox attempts or credentials. Re-run setup to resume the
schedule only after confirming gates and investigating uncertain sends.

Rotate the dedicated worker secret by pausing both gates and unscheduling, then
updating its Edge and Vault entries together and reinstalling the schedule.
The next tick reads Vault fresh; no secret is embedded in `cron.job.command`.
pg_net temporarily holds request headers in its restricted request queue. Do not
grant application roles access to Vault/cron/net internals, export that queue,
enable parameter/header logging or copy response bodies into general logs.

## Local Verification

QA only, serial: use the existing disposable PostgreSQL 17 helper with
`PG_BIN` pointing to its approved runtime and Node24 heap1024:

```sh
node --max-old-space-size=1024 --test --test-concurrency=1 scripts/mail-worker-scheduler.test.mjs
```

The test substitutes ONLY extension boundaries with synthetic Vault values,
an in-database cron registry and a recording `net.http_post` function. No HTTP,
provider, existing database, real secrets or mail sends occur. It tests the exact
setup/disable SQL and its authority/gates. Real hosted Cron/pg_net execution and
development delivery are separate integration evidence.

References: [Supabase scheduling](https://supabase.com/docs/guides/functions/schedule-functions),
[Vault](https://supabase.com/docs/guides/database/vault),
[pg_net](https://supabase.com/docs/guides/database/extensions/pg_net).
