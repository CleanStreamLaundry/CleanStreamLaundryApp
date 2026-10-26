-- Atomic decision notices only. Financial decisions and provider calls stay separate.
begin;

alter table private.mail_outbox
  add column credit_refund_id bigint,
  add column credit_resolved_at timestamptz,
  add column credit_notice jsonb;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check check (kind in (
  'account_welcome','newsletter_confirm','newsletter_welcome','refund_request',
  'account_deletion_scheduled','account_restored','credit_decision'
));
alter table private.mail_outbox add constraint mail_outbox_credit_notice_check check (
  (kind='credit_decision' and credit_refund_id is not null and credit_resolved_at is not null
    and credit_notice is not null and jsonb_typeof(credit_notice)='object'
    and consent_id is null)
  or (kind<>'credit_decision' and credit_refund_id is null
    and credit_resolved_at is null and credit_notice is null)
);
-- No FK may erase the permanent event key when source records are cleaned up.

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

create function private.mail_credit_decision_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare o private.mail_outbox;
begin
  if old.status::text is distinct from 'pending'
    or new.status::text not in ('approved','denied')
    or new.resolved_at is null or new.resolved_by is null
    or new.amount is null or round((new.amount*100)::numeric) not between 1 and 2147483647
    or not exists (select 1 from private.mail_settings s
      where s.rollout_at is not null and new.resolved_at>=s.rollout_at) then
    return new;
  end if;
  -- Financial writers already hold refund/wallet rows. Nothing holding mail_lock
  -- may acquire those rows: worker completion records only the outbox, not Refunds.
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
revoke all on function private.mail_credit_decision_event()
  from public,anon,authenticated,service_role,supabase_auth_admin;
create trigger mail_credit_decision after update of status on public."Refunds"
  for each row execute function private.mail_credit_decision_event();

-- Preserve the exact canonical caller/location guards and financial call.
-- Only the final result gains current outbox evidence; queued is never sent.
create or replace function public.admin_resolve_credit(target_refund_id bigint, target_decision text, resolution_note text default '')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare before_context jsonb; result jsonb; actor uuid;
  notice private.mail_outbox; notice_state text;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if length(coalesce(resolution_note,''))>4000 then raise exception 'invalid_request' using errcode='22023'; end if;
  perform public.admin_portal_data(actor,'assertCredit',jsonb_build_object('id',target_refund_id));
  result:=public.resolve_refund_request(target_refund_id,target_decision,resolution_note,actor);
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  -- The claim's machine may have changed location during an inner wallet wait.
  perform public.admin_portal_data(actor,'assertCredit',jsonb_build_object('id',target_refund_id));
  select o.* into notice from private.mail_outbox o join public."Refunds" r
    on r.refund_id=o.credit_refund_id and r.resolved_at=o.credit_resolved_at
    where r.refund_id=target_refund_id and o.kind='credit_decision'
      and o.event_key='loyalty_credit_'||r.status::text||'/'||r.refund_id
      and o.credit_notice->>'status'=r.status::text;
  if found then
    notice_state:=case when notice.state in ('ready','leased') and not private.mail_allowed(notice)
      then 'suppressed' else notice.state end;
  else
    notice_state:=case when result->>'notificationSent'='true' then 'legacy_sent' else 'not_queued' end;
  end if;
  return result||jsonb_build_object('notificationState',notice_state,
    'notificationSent',notice_state in ('accepted','delivered','legacy_sent'));
end; $$;

-- Existing ACLs, notify timestamps, retry/finish/webhook RPCs and all financial
-- routines remain unchanged. Disabled delivery retains post-rollout intent only.
commit;
