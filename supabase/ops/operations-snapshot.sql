-- Operator-only aggregate diagnostics: no identities, amounts or provider calls.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s';
set local lock_timeout = '1s';
set local timezone = 'UTC';

-- One result preserves every section in the Management API / CLI response.
with vend as (
  select coalesce(nayax_environment, 'unattributed') as environment,
    payment_method, status, count(*) as session_count,
    min(created_at) as oldest_created_at,
    count(*) filter (where reconcile_after <= current_timestamp
      and (reconcile_claim_until is null or reconcile_claim_until <= current_timestamp))
      as reconciliation_due_count,
    count(*) filter (where reconcile_claim_until > current_timestamp)
      as reconciliation_leased_count,
    min(reconcile_after) as earliest_reconciliation_at
  from public.cortina_vend_sessions
  where status in ('payment_pending', 'paid', 'starting', 'awaiting_sale', 'approved',
    'failed', 'timed_out', 'support_required') or reconcile_after is not null
  group by nayax_environment, payment_method, status
), refunds as (
  select case when livemode then 'live' else 'test' end as stripe_mode,
    status, count(*) as request_count, min(requested_at) as oldest_requested_at,
    min(provider_checked_at) as oldest_provider_check_at,
    count(*) filter (where provider_checked_at is null) as never_checked_count
  from private.voluntary_topup_refunds
  where status in ('requested', 'approved', 'unknown', 'pending', 'failed')
  group by livemode, status
), mail as (
  select state, kind, count(*) as message_count, min(created_at) as oldest_created_at,
    count(*) filter (where next_at <= current_timestamp) as due_count,
    count(*) filter (where lease_until <= current_timestamp) as expired_lease_count,
    max(attempts) as highest_attempt_count
  from private.mail_outbox
  where state in ('ready', 'leased', 'sending', 'uncertain', 'failed')
  group by state, kind
), lifecycle as (
  select count(*) filter (where restore_until > current_timestamp) as recoverable_account_count,
    count(*) filter (where restore_until <= current_timestamp) as expired_pending_account_count,
    min(restore_until) filter (where restore_until <= current_timestamp) as earliest_expired_deadline
  from private.account_lifecycle where restored_at is null
), workers as (
  select job.jobname, job.active, job.schedule,
    last_run.status as last_run_status, last_run.start_time, last_run.end_time
  from cron.job as job
  left join lateral (
    select status, start_time, end_time from cron.job_run_details
    where jobid = job.jobid order by start_time desc nulls last, runid desc limit 1
  ) as last_run on true
  where job.jobname in ('cleanstream-mail-delivery', 'cleanstream-cortina-reconcile')
    and job.username = current_user
)
select jsonb_build_object(
  'snapshot_at_utc', current_timestamp,
  'new_payments_enabled', (select enabled from private.new_payment_service_control where singleton),
  'mail_enabled', (select enabled from private.mail_settings where singleton),
  'mail_rollout_at', (select rollout_at from private.mail_settings where singleton),
  'vend', coalesce((select jsonb_agg(v order by environment,payment_method,status) from vend v), '[]'::jsonb),
  'refunds', coalesce((select jsonb_agg(r order by stripe_mode,status) from refunds r), '[]'::jsonb),
  'mail', coalesce((select jsonb_agg(m order by state,kind) from mail m), '[]'::jsonb),
  'lifecycle', (select jsonb_build_object(
    'recoverable_account_count', recoverable_account_count,
    'expired_pending_account_count', expired_pending_account_count,
    'earliest_expired_deadline', earliest_expired_deadline
  ) from lifecycle),
  'workers', coalesce((select jsonb_agg(w order by jobname) from workers w), '[]'::jsonb)
) as operations_snapshot;

rollback;
