-- Queue-only lifecycle notices. No RPC, admission, retention or cleanup changes.
begin;

alter table private.mail_outbox
  add column lifecycle_requested_at timestamptz,
  add column lifecycle_restore_until timestamptz,
  add column lifecycle_restored_at timestamptz;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check check (kind in (
  'account_welcome','newsletter_confirm','newsletter_welcome','refund_request',
  'account_deletion_scheduled','account_restored'
));
alter table private.mail_outbox add constraint mail_outbox_lifecycle_notice_check check (
  (kind in ('account_deletion_scheduled','account_restored')
    and consent_id is null and lifecycle_requested_at is not null
    and lifecycle_restore_until is not null
    and lifecycle_restore_until = lifecycle_requested_at + interval '720 hours'
    and ((kind='account_deletion_scheduled' and lifecycle_restored_at is null)
      or (kind='account_restored' and lifecycle_restored_at is not null
        and lifecycle_restored_at > lifecycle_requested_at
        and lifecycle_restored_at < lifecycle_restore_until)))
  or (kind not in ('account_deletion_scheduled','account_restored')
    and lifecycle_requested_at is null and lifecycle_restore_until is null
    and lifecycle_restored_at is null)
);

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

-- Reuse the existing AFTER trigger and lock ordering. Enqueue is part of the
-- lifecycle transaction, so failed restoration/post-wait checks enqueue nothing.
create or replace function private.mail_lifecycle_suppression() returns trigger
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare
  notice_kind text;
  event_at timestamptz;
  o private.mail_outbox;
begin
  if new.marketing_suppressed then
    perform private.mail_lock();
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason='account_deletion', confirm_hash=null where user_id=new.user_id;
    update private.mail_outbox m set state='suppressed',last_error='account_deletion'
      where user_id=new.user_id and state in ('ready','leased','sending','uncertain')
        and (kind not in ('account_deletion_scheduled','account_restored')
          or not private.mail_allowed(m));
  end if;

  if new.restored_at is null then
    if tg_op='INSERT' then notice_kind:='account_deletion_scheduled';
    elsif new.deletion_requested_at is distinct from old.deletion_requested_at then
      notice_kind:='account_deletion_scheduled';
    end if;
    event_at:=new.deletion_requested_at;
  elsif tg_op='UPDATE' then
    if old.restored_at is null then notice_kind:='account_restored'; end if;
    event_at:=new.restored_at;
  end if;
  if notice_kind is null or not exists (select 1 from private.mail_settings s
    where s.enabled and event_at>=s.rollout_at) then return new; end if;

  o.kind:=notice_kind; o.user_id:=new.user_id;
  o.lifecycle_requested_at:=new.deletion_requested_at;
  o.lifecycle_restore_until:=new.restore_until;
  o.lifecycle_restored_at:=new.restored_at;
  select nullif(lower(btrim(email)),'') into o.email from auth.users where id=new.user_id;
  if o.email is null or not private.mail_allowed(o) then return new; end if;
  insert into private.mail_outbox(event_key,kind,user_id,email,
    lifecycle_requested_at,lifecycle_restore_until,lifecycle_restored_at)
  values (notice_kind||'/'||new.user_id||'/'||
    to_char(new.deletion_requested_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    notice_kind,new.user_id,o.email,new.deletion_requested_at,new.restore_until,new.restored_at)
  on conflict(event_key) do nothing;
  return new;
end $$;

-- CREATE OR REPLACE retains the existing revoked ACLs. No public enqueue RPC,
-- backfill, activation, delivery claim, or permanent-deletion-complete event.
commit;
