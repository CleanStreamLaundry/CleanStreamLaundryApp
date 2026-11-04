-- Queue-only extension. No claim/ledger mutations, sender setup or activation.
begin;

alter table private.mail_settings add column refund_notice_recipient uuid
  references auth.users(id) on delete set null;
alter table private.mail_outbox
  add column refund_id bigint,
  add column refund_notice jsonb;
alter table private.mail_outbox drop constraint mail_outbox_kind_check;
alter table private.mail_outbox add constraint mail_outbox_kind_check
  check (kind in ('account_welcome','newsletter_confirm','newsletter_welcome','refund_request'));
alter table private.mail_outbox add constraint mail_outbox_refund_notice_check check (
  (kind='refund_request' and refund_id is not null and refund_notice is not null
    and jsonb_typeof(refund_notice)='object')
  or (kind<>'refund_request' and refund_id is null and refund_notice is null)
);
-- Intentionally no FK back to Refunds: deleting a record must not erase the
-- permanent event key or make an unrelated financial cleanup fail.

create or replace function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
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
          or (o.kind='newsletter_welcome' and c.confirmed_at is not null)))));
$$;

create function public.enqueue_refund_request_notice(target_transaction_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a jsonb; caller uuid; matches bigint; rid bigint; r public."Refunds";
  settings private.mail_settings; o private.mail_outbox; notice_state text;
begin
  -- This lock orders enqueue with consent, identity changes and suppression.
  -- Do not acquire wallet, transaction or refund row locks for a notice.
  perform private.mail_lock();
  a:=private.current_account_access(); caller:=(a->>'subject_id')::uuid;
  if a->>'account_access' is distinct from 'eligible' then
    raise exception 'account_restricted' using errcode='PT403'; end if;
  if target_transaction_id is null or target_transaction_id<=0 then
    raise exception 'invalid_transaction_id' using errcode='PT400'; end if;
  select count(*),min(f.refund_id) into matches,rid
    from public."Refunds" f join public.transactions t
      on t.id=f.transaction_id and t.user_id=caller
    where f.transaction_id=target_transaction_id and f.user_id=caller and f.status::text='pending';
  if matches<>1 then
    raise exception 'claim_unavailable_or_ambiguous' using errcode='PT400'; end if;
  select * into r from public."Refunds" f where refund_id=rid
    and f.user_id=caller and f.transaction_id=target_transaction_id and f.status::text='pending'
    and exists (select 1 from public.transactions t where t.id=f.transaction_id and t.user_id=caller);
  if not found then raise exception 'claim_unavailable_or_ambiguous' using errcode='PT400'; end if;
  select * into settings from private.mail_settings;
  select * into o from private.mail_outbox
    where event_key='loyalty_credit_requested/'||rid;
  if found then
    if o.state in ('ready','leased') and not private.mail_allowed(o) then
      update private.mail_outbox set state='suppressed',last_error='suppressed_or_stale'
        where id=o.id returning * into o;
    end if;
    notice_state:=case when o.state in ('ready','leased') then 'queued' else o.state end;
  elsif settings.refund_notice_recipient is null then
    notice_state:='recipient_unavailable';
  elsif not settings.enabled then
    notice_state:='disabled';
  else
    o.kind:='refund_request'; o.refund_id:=rid;
    o.user_id:=settings.refund_notice_recipient;
    select nullif(lower(btrim(u.email)),'') into o.email from auth.users u
      join public.profiles p on p.id=u.id
      where u.id=o.user_id and p.roles::text='Owner';
    if o.email is null then notice_state:='recipient_unavailable';
    elsif not private.mail_allowed(o) then notice_state:='suppressed';
    elsif r.amount is null or r.amount<=0 or length(r.amount::text)>30
      or r.amount::text !~ '^[0-9]+(\.[0-9]{1,2})?$' then notice_state:='failed';
    else
      insert into private.mail_outbox(event_key,kind,user_id,email,refund_id,refund_notice)
      values('loyalty_credit_requested/'||rid,'refund_request',o.user_id,o.email,rid,
        jsonb_build_object('refund_id',rid::text,'transaction_id',r.transaction_id::text,
          'user_id',r.user_id::text,'amount',r.amount::text,
          'description',left(coalesce(r.description,''),4000)))
      on conflict(event_key) do nothing;
      notice_state:='queued';
    end if;
  end if;
  return jsonb_build_object('refund_id',rid::text,'state',notice_state);
end $$;
revoke all on function public.enqueue_refund_request_notice(bigint)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.enqueue_refund_request_notice(bigint) to authenticated;

-- Newsletter withdrawal does not withdraw transactional request alerts.
create or replace function public.newsletter_withdraw() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb; e text;
begin
  perform 1 from auth.users where id=auth.uid() for share;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  perform private.mail_lock();
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
    suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
    where user_id=auth.uid() and email=e;
  update private.mail_outbox set state='suppressed',last_error='unsubscribe'
    where user_id=auth.uid() and email=e and kind in ('newsletter_confirm','newsletter_welcome')
    and state in ('ready','leased','sending','uncertain');
  return public.newsletter_status();
end $$;

create or replace function public.newsletter_token(p_action text,p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c private.newsletter_consent; o private.mail_outbox;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_action is null or p_action not in ('confirm','unsubscribe') then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  perform private.mail_lock();
  if p_action='unsubscribe' then
    select * into c from private.newsletter_consent where unsubscribe_hash=p_hash;
    if found then
      update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
        suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
        where user_id=c.user_id and email=c.email;
      update private.mail_outbox set state='suppressed',last_error='unsubscribe'
        where user_id=c.user_id and email=c.email and kind in ('newsletter_confirm','newsletter_welcome')
        and state in ('ready','leased','sending','uncertain');
    end if;
    return jsonb_build_object('state','unsubscribed');
  end if;
  select * into c from private.newsletter_consent where confirm_hash=p_hash;
  if not found or c.confirmed_at is not null or c.unsubscribed_at is not null or c.expires_at<=clock_timestamp() then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  select * into o from private.mail_outbox where consent_id=c.id and kind='newsletter_confirm';
  if not private.mail_allowed(o) then raise exception 'token_invalid' using errcode='PT400'; end if;
  update private.newsletter_consent set confirmed_at=clock_timestamp(),confirm_hash=null where id=c.id;
  insert into private.mail_outbox(event_key,kind,user_id,email,consent_id)
    values('newsletter_welcome/'||c.id,'newsletter_welcome',c.user_id,c.email,c.id) on conflict(event_key) do nothing;
  return jsonb_build_object('state','subscribed');
end $$;

commit;
