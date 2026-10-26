-- New events only; no activation, historical backfill or financial mutation.
begin;

alter table private.mail_outbox
  add column topup_refund_id uuid,
  add column maintenance_history_id bigint,
  add column followup_notice jsonb,
  add column machine_issue_request_id uuid,
  add column machine_issue_notice jsonb;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check check (kind in (
  'account_welcome','newsletter_confirm','newsletter_welcome','refund_request',
  'account_deletion_scheduled','account_restored','credit_decision',
  'topup_refund_outcome','maintenance_resolved','machine_issue_outcome'
));
alter table private.mail_outbox add constraint mail_outbox_followup_notice_check check (
  (kind in ('topup_refund_outcome','maintenance_resolved') and consent_id is null
    and followup_notice is not null and jsonb_typeof(followup_notice)='object'
    and ((kind='topup_refund_outcome' and topup_refund_id is not null and maintenance_history_id is null)
      or (kind='maintenance_resolved' and maintenance_history_id is not null and topup_refund_id is null)))
  or (kind not in ('topup_refund_outcome','maintenance_resolved')
    and topup_refund_id is null and maintenance_history_id is null and followup_notice is null)
);
alter table private.mail_outbox add constraint mail_outbox_machine_issue_notice_check check (
  (kind='machine_issue_outcome' and machine_issue_request_id is not null
    and machine_issue_notice is not null and jsonb_typeof(machine_issue_notice)='object' and consent_id is null)
  or (kind<>'machine_issue_outcome' and machine_issue_request_id is null and machine_issue_notice is null)
);
-- No source FK: cleanup must not erase permanent event deduplication keys.

create or replace function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and (
    (o.kind in ('account_deletion_scheduled','account_restored') and exists (
      select 1 from private.account_lifecycle l where l.user_id=o.user_id
        and l.deletion_requested_at=o.lifecycle_requested_at
        and l.restore_until=o.lifecycle_restore_until
        and ((o.kind='account_deletion_scheduled' and l.restored_at is null
            and l.restore_until>clock_timestamp())
          or (o.kind='account_restored' and l.restored_at=o.lifecycle_restored_at))))
    or (o.kind='credit_decision' and exists (
      select 1 from public."Refunds" r
        join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
      where r.refund_id=o.credit_refund_id and r.user_id=o.user_id
        and r.policy_version='legacy_14_day'
        and r.resolved_at=o.credit_resolved_at and r.resolved_by is not null
        and r.status::text in ('approved','denied')
        and round((r.amount*100)::numeric) between 1 and 2147483647
        and o.credit_notice=jsonb_build_object('refund_id',r.refund_id::text,
          'transaction_id',r.transaction_id::text,'status',r.status::text,
          'amount_cents',round((r.amount*100)::numeric),
          'note',coalesce(r.admin_note,''))
        and (r.status::text='denied' or exists (
          select 1 from public.wallet_ledger_entries e
            join public.wallet_accounts w on w.id=e.wallet_account_id and w.user_id=r.user_id
          where e.refund_request_id=r.refund_id and e.entry_type::text='admin_adjustment'
            and e.amount_cents=round((r.amount*100)::numeric)
            and e.paid_amount_cents=0 and e.promo_amount_cents=e.amount_cents)))
      and not exists (select 1 from private.account_lifecycle l
        where l.user_id=o.user_id and l.restored_at is null))
    or (o.kind='machine_issue_outcome' and exists (
      select 1 from private.machine_issue_resolutions a
        join public."Refunds" r on r.refund_id=a.refund_id and r.policy_version='same_day_v1'
        join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
          and t.cortina_vend_session_id=a.original_session_id
        join public.cortina_vend_sessions original on original.id=a.original_session_id
          and original.user_id=r.user_id and original.funding_source='payment'
          and original.status='started' and original.stripe_refund_id is null
          and original.payment_method='wallet' and original.amount_cents=a.amount_cents
        join public.wallet_redemptions debit on debit.id=original.wallet_redemption_id
          and debit.user_id=r.user_id and debit.machine_id=original.machine_id
          and debit.amount_cents=a.amount_cents and debit.paid_amount_cents=a.paid_amount_cents
          and debit.promo_amount_cents=a.promo_amount_cents
        join public.wallet_accounts w on w.id=debit.wallet_account_id and w.user_id=r.user_id
        left join public."Machines" replacement_machine on replacement_machine.id=a.replacement_machine_id
      where a.request_id=o.machine_issue_request_id and r.user_id=o.user_id
        and a.state='completed' and a.completed_at is not null
        and a.amount_cents>0 and a.paid_amount_cents>=0 and a.promo_amount_cents>=0
        and a.amount_cents=a.paid_amount_cents+a.promo_amount_cents
        and r.amount::numeric*100=a.amount_cents and t.amount::numeric*100=a.amount_cents
        and o.machine_issue_notice=jsonb_build_object('refund_id',r.refund_id::text,
          'transaction_id',r.transaction_id::text,'resolution',a.resolution,'amount_cents',a.amount_cents,
          'paid_amount_cents',a.paid_amount_cents,'promo_amount_cents',a.promo_amount_cents,
          'replacement_machine_id',a.replacement_machine_id::text,
          'replacement_machine_name',case when a.replacement_machine_id is not null then
            left(coalesce(nullif(btrim(replacement_machine."Name"),''),'Machine #'||a.replacement_machine_id),200) end)
        and ((a.resolution='wallet_refund' and a.replacement_session_id is null
          and a.replacement_machine_id is null and debit.status='void'
          and r.status::text='approved' and r.resolved_by=a.actor_id and r.resolved_at is not null
          and exists (select 1 from public.wallet_ledger_entries e where e.id=a.ledger_entry_id
            and e.refund_request_id=r.refund_id and e.wallet_account_id=w.id
            and e.entry_type='admin_adjustment' and e.amount_cents=a.amount_cents
            and e.paid_amount_cents=a.paid_amount_cents and e.promo_amount_cents=a.promo_amount_cents))
        or (a.resolution='replacement_vend' and a.ledger_entry_id is null and debit.status='succeeded'
          and not exists (select 1 from public.wallet_ledger_entries e where e.refund_request_id=r.refund_id)
          and exists (select 1 from public.cortina_vend_sessions replacement
            where replacement.id=a.replacement_session_id and replacement.user_id=r.user_id
              and replacement.machine_id=a.replacement_machine_id and replacement.amount_cents=a.amount_cents
              and replacement.funding_source='machine_issue' and replacement.complaint_refund_id=r.refund_id
              and replacement.status='started' and replacement.stripe_refund_id is null
              and replacement.stripe_payment_intent_id is null and replacement.wallet_redemption_id is null))))
      and not exists (select 1 from private.account_lifecycle l
        where l.user_id=o.user_id and l.restored_at is null))
    or (o.kind='topup_refund_outcome' and exists (
      select 1 from private.voluntary_topup_refunds r
        join public.wallet_loads l on l.id=r.load_id and l.user_id=r.customer_id
          and l.wallet_account_id=r.wallet_id and l.stripe_payment_intent_id=r.stripe_payment_intent_id
          and l.paid_amount_cents=r.principal_cents
        join public.wallet_accounts w on w.id=r.wallet_id and w.user_id=r.customer_id
      where r.id=o.topup_refund_id and r.customer_id=o.user_id
        and o.followup_notice=jsonb_build_object('refund_id',r.id::text,
          'load_id',r.load_id::text,'status',r.status,'amount_cents',r.principal_cents,
          'provider_refund_id',r.provider_refund_id)
        and (
          (r.status='succeeded' and r.completed_at is not null and r.released_at is null
            and r.dispatch_started_at is not null and r.provider_checked_at is not null
            and r.provider_refund_id ~ '^re_[a-zA-Z0-9]{1,200}$' and l.status::text='refunded'
            and exists (select 1 from public.wallet_ledger_entries e
              where e.voluntary_topup_refund_id=r.id and e.wallet_account_id=r.wallet_id
                and e.wallet_load_id=r.load_id and e.paid_amount_cents=-r.principal_cents
                and e.stripe_refund_id=r.provider_refund_id))
          or (r.status in ('denied','failed','canceled') and r.released_at is not null
            and r.completed_at is null
            and ((r.status='denied' and r.reviewed_by is not null and r.reviewed_at is not null
                and r.dispatch_started_at is null and r.provider_refund_id is null)
              or (r.status in ('failed','canceled') and r.dispatch_started_at is not null
                and r.provider_checked_at is not null and r.provider_refund_id ~ '^re_[a-zA-Z0-9]{1,200}$'))
            and exists (select 1 from public.wallet_ledger_entries e
              where e.voluntary_topup_refund_id=r.id and e.wallet_account_id=r.wallet_id
                and e.wallet_load_id=r.load_id and e.entry_type::text='admin_adjustment'
                and e.paid_amount_cents=r.principal_cents))))
      and not exists (select 1 from private.account_lifecycle l
        where l.user_id=o.user_id and l.restored_at is null))
    or (o.kind='maintenance_resolved' and exists (
      select 1 from public.admin_maintenance_history h
        join public."Maintenance" m on m.maint_id::text=h.maintenance_id
      where h.id=o.maintenance_history_id and m.user_id=o.user_id and m.status='resolved'
        and h.from_status<>'resolved' and h.to_status='resolved'
        and o.followup_notice=jsonb_build_object('report_id',h.maintenance_id,'status','resolved')
        -- A reopened report invalidates its previous resolution, even if resolved again.
        and not exists (select 1 from public.admin_maintenance_history newer
          where newer.maintenance_id=h.maintenance_id and newer.id>h.id
            and newer.from_status is distinct from newer.to_status))
      and not exists (select 1 from private.account_lifecycle l
        where l.user_id=o.user_id and l.restored_at is null))
    or (
      not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
        and (l.restored_at is null or o.kind not in ('account_welcome','refund_request')))
      and (o.kind='account_welcome' or (o.kind='refund_request'
        and exists (select 1 from private.mail_settings s join public.profiles p
          on p.id=s.refund_notice_recipient
          where s.refund_notice_recipient=o.user_id and p.roles::text='Owner')
        and exists (select 1 from public."Refunds" r
          join public.transactions t on t.id=r.transaction_id and t.user_id=r.user_id
          join auth.users u on u.id=r.user_id
          where r.refund_id=o.refund_id and r.status::text='pending'
            and u.deleted_at is null and u.is_anonymous is false
            and (u.banned_until is null or u.banned_until<=clock_timestamp())
            and not exists (select 1 from private.account_lifecycle l
              where l.user_id=r.user_id and l.restored_at is null)))
        or (o.kind in ('newsletter_confirm','newsletter_welcome') and exists (
          select 1 from private.newsletter_consent c where c.id=o.consent_id
            and c.unsubscribed_at is null and c.email=o.email
            and ((o.kind='newsletter_confirm' and c.confirmed_at is null and c.expires_at>clock_timestamp())
              or (o.kind='newsletter_welcome' and c.confirmed_at is not null)))))
    )
  );
$$;

create function private.mail_topup_refund_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare o private.mail_outbox; resolved_at timestamptz; allowed boolean;
begin
  if old.status is not distinct from new.status
    or new.status not in ('succeeded','denied','failed','canceled') then return new; end if;
  resolved_at:=case new.status when 'succeeded' then new.completed_at
    when 'denied' then new.reviewed_at else new.provider_checked_at end;
  if not exists (select 1 from private.mail_settings s
    where s.rollout_at is not null and resolved_at>=s.rollout_at) then return new; end if;
  -- Deferred until financial reconciliation has written the load and ledger.
  -- Never take a financial row lock while holding the mail lock.
  perform private.mail_lock();
  o.kind:='topup_refund_outcome'; o.user_id:=new.customer_id; o.topup_refund_id:=new.id;
  o.followup_notice:=jsonb_build_object('refund_id',new.id::text,'load_id',new.load_id::text,
    'status',new.status,'amount_cents',new.principal_cents,'provider_refund_id',new.provider_refund_id);
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=o.user_id;
  if o.email is null then return new; end if;
  allowed:=private.mail_allowed(o);
  insert into private.mail_outbox(event_key,kind,user_id,email,topup_refund_id,followup_notice,state,last_error)
  values ('topup_refund_outcome/'||new.id,o.kind,o.user_id,o.email,o.topup_refund_id,o.followup_notice,
    case when allowed then 'ready' else 'suppressed' end,
    case when allowed then null else 'suppressed_or_stale' end)
  on conflict(event_key) do nothing;
  return new;
end $$;
revoke all on function private.mail_topup_refund_event()
  from public,anon,authenticated,service_role,supabase_auth_admin;
create constraint trigger mail_topup_refund_outcome after update on private.voluntary_topup_refunds
  deferrable initially deferred for each row execute function private.mail_topup_refund_event();

create function private.mail_maintenance_resolved_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare o private.mail_outbox; allowed boolean;
begin
  if new.to_status<>'resolved' or new.from_status='resolved'
    or new.actor_id is null or length(new.maintenance_id) not between 1 and 200
    or not exists (select 1 from private.mail_settings s
      where s.rollout_at is not null and new.created_at>=s.rollout_at) then return new; end if;
  perform private.mail_lock();
  o.kind:='maintenance_resolved'; o.maintenance_history_id:=new.id;
  select m.user_id into o.user_id from public."Maintenance" m where m.maint_id::text=new.maintenance_id;
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=o.user_id;
  if o.email is null then return new; end if;
  -- Staff history notes are internal, not automatically customer-facing copy.
  o.followup_notice:=jsonb_build_object('report_id',new.maintenance_id,'status','resolved');
  allowed:=private.mail_allowed(o);
  insert into private.mail_outbox(event_key,kind,user_id,email,maintenance_history_id,followup_notice,state,last_error)
  values ('maintenance_resolved/'||new.id,o.kind,o.user_id,o.email,o.maintenance_history_id,o.followup_notice,
    case when allowed then 'ready' else 'suppressed' end,
    case when allowed then null else 'suppressed_or_stale' end)
  on conflict(event_key) do nothing;
  return new;
end $$;
revoke all on function private.mail_maintenance_resolved_event()
  from public,anon,authenticated,service_role,supabase_auth_admin;
create trigger mail_maintenance_resolved after insert on public.admin_maintenance_history
  for each row execute function private.mail_maintenance_resolved_event();

-- Legacy promotional-credit copy must never describe paid/promo source restoration.
create or replace function private.mail_credit_decision_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare o private.mail_outbox;
begin
  if new.policy_version<>'legacy_14_day' or old.status::text is distinct from 'pending'
    or new.status::text not in ('approved','denied')
    or new.resolved_at is null or new.resolved_by is null
    or new.amount is null or round((new.amount*100)::numeric) not between 1 and 2147483647
    or not exists (select 1 from private.mail_settings s
      where s.rollout_at is not null and new.resolved_at>=s.rollout_at) then return new; end if;
  perform private.mail_lock();
  o.kind:='credit_decision'; o.user_id:=new.user_id;
  o.credit_refund_id:=new.refund_id; o.credit_resolved_at:=new.resolved_at;
  o.credit_notice:=jsonb_build_object('refund_id',new.refund_id::text,
    'transaction_id',new.transaction_id::text,'status',new.status::text,
    'amount_cents',round((new.amount*100)::numeric),'note',coalesce(new.admin_note,''));
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=new.user_id;
  if o.email is null then return new; end if;
  insert into private.mail_outbox(event_key,kind,user_id,email,
    credit_refund_id,credit_resolved_at,credit_notice,state,last_error)
  values ('loyalty_credit_'||new.status::text||'/'||new.refund_id,
    o.kind,o.user_id,o.email,o.credit_refund_id,o.credit_resolved_at,o.credit_notice,
    case when private.mail_allowed(o) then 'ready' else 'suppressed' end,
    case when private.mail_allowed(o) then null else 'suppressed_or_stale' end)
  on conflict(event_key) do nothing;
  return new;
end $$;

create function private.mail_machine_issue_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare o private.mail_outbox; r public."Refunds"; allowed boolean; machine_name text;
begin
  if new.state<>'completed' or new.resolution not in ('wallet_refund','replacement_vend')
    or new.completed_at is null then return new; end if;
  if tg_op='UPDATE' then
    if old.state='completed' then return new; end if;
  end if;
  if not exists (select 1 from private.mail_settings s
    where s.rollout_at is not null and new.completed_at>=s.rollout_at) then return new; end if;
  perform private.mail_lock();
  select * into r from public."Refunds" where refund_id=new.refund_id;
  if new.replacement_machine_id is not null then
    select left(coalesce(nullif(btrim(m."Name"),''),'Machine #'||m.id),200) into machine_name
      from public."Machines" m where m.id=new.replacement_machine_id;
  end if;
  o.kind:='machine_issue_outcome'; o.user_id:=r.user_id; o.machine_issue_request_id:=new.request_id;
  o.machine_issue_notice:=jsonb_build_object('refund_id',r.refund_id::text,
    'transaction_id',r.transaction_id::text,'resolution',new.resolution,'amount_cents',new.amount_cents,
    'paid_amount_cents',new.paid_amount_cents,'promo_amount_cents',new.promo_amount_cents,
    'replacement_machine_id',new.replacement_machine_id::text,'replacement_machine_name',machine_name);
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=o.user_id;
  if o.email is null then return new; end if;
  allowed:=private.mail_allowed(o);
  insert into private.mail_outbox(event_key,kind,user_id,email,machine_issue_request_id,machine_issue_notice,state,last_error)
  values ('machine_issue_outcome/'||new.refund_id,o.kind,o.user_id,o.email,o.machine_issue_request_id,o.machine_issue_notice,
    case when allowed then 'ready' else 'suppressed' end,
    case when allowed then null else 'suppressed_or_stale' end)
  on conflict(event_key) do nothing;
  return new;
end $$;
revoke all on function private.mail_machine_issue_event()
  from public,anon,authenticated,service_role,supabase_auth_admin;
-- The wallet receipt is inserted before the claim is approved in the same transaction.
create constraint trigger mail_machine_issue_outcome after insert or update on private.machine_issue_resolutions
  deferrable initially deferred for each row execute function private.mail_machine_issue_event();

-- Worker, provider idempotency, webhook, lifecycle and financial RPCs unchanged.
commit;
