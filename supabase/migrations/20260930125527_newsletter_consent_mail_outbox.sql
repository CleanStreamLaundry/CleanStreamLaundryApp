-- Local-only candidate. No scheduler, provider configuration, or financial writes.
begin;

create table private.mail_settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  rollout_at timestamptz,
  consent_version text not null default 'newsletter-v1',
  consent_text text not null default 'I would like to receive the Clean Stream newsletter. I can unsubscribe at any time.',
  check (not enabled or rollout_at is not null)
);
insert into private.mail_settings default values;

create table private.newsletter_consent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  email text not null,
  purpose text not null default 'newsletter' check (purpose = 'newsletter'),
  version text not null,
  consent_text text not null,
  source text not null check (source in ('signup', 'settings')),
  requested_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  confirmed_at timestamptz,
  unsubscribed_at timestamptz,
  suppression_reason text,
  confirm_hash text unique check (confirm_hash ~ '^[0-9a-f]{64}$'),
  unsubscribe_hash text unique check (unsubscribe_hash ~ '^[0-9a-f]{64}$')
);
create index on private.newsletter_consent(user_id, requested_at desc);
create index on private.newsletter_consent(email, requested_at desc);

create table private.mail_suppression (
  email text primary key,
  reason text not null,
  created_at timestamptz not null default clock_timestamp()
);
create table private.mail_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  kind text not null check (kind in ('account_welcome', 'newsletter_confirm', 'newsletter_welcome')),
  user_id uuid not null,
  email text not null,
  consent_id uuid references private.newsletter_consent(id),
  state text not null default 'ready' check (state in
    ('ready','leased','sending','uncertain','accepted','delivered','failed','suppressed')),
  created_at timestamptz not null default clock_timestamp(),
  next_at timestamptz not null default clock_timestamp(),
  lease_id uuid,
  lease_until timestamptz,
  attempts integer not null default 0,
  first_attempt_at timestamptz,
  payload_hash text,
  provider_id text unique,
  last_error text
);
create index on private.mail_outbox(next_at) where state in ('ready','leased','sending');
create table private.mail_webhook_event (
  event_id text primary key,
  provider_id text not null,
  event_type text not null,
  outbox_id uuid,
  received_at timestamptz not null default clock_timestamp()
);

-- No client or service direct table access, including inherited PUBLIC grants.
do $$ declare t text; begin
  foreach t in array array['mail_settings','newsletter_consent','mail_suppression','mail_outbox','mail_webhook_event'] loop
    execute format('alter table private.%I enable row level security', t);
    execute format('revoke all on private.%I from public, anon, authenticated, service_role, supabase_auth_admin', t);
  end loop;
end $$;

-- A single short transaction lock keeps this small outbox's state transitions
-- ordered with consent/deletion. Never hold it across a provider HTTP request.
create function private.mail_lock() returns void language sql volatile
set search_path = '' as $$ select pg_advisory_xact_lock(726314, 1); $$;

create function private.mail_allowed(o private.mail_outbox) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id=o.user_id
    and lower(btrim(u.email))=o.email and u.email_confirmed_at is not null
    and u.is_anonymous is false and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= clock_timestamp()))
  and not exists (select 1 from private.mail_suppression s where s.email=o.email)
  and not exists (select 1 from private.account_lifecycle l where l.user_id=o.user_id
    and (l.restored_at is null or o.kind <> 'account_welcome'))
  and (o.kind='account_welcome' or exists (
    select 1 from private.newsletter_consent c where c.id=o.consent_id
      and c.unsubscribed_at is null and c.email=o.email
      and ((o.kind='newsletter_confirm' and c.confirmed_at is null and c.expires_at>clock_timestamp())
        or (o.kind='newsletter_welcome' and c.confirmed_at is not null))));
$$;

create function private.mail_account_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email_confirmed_at is not null and new.email is not null
    and new.is_anonymous is false and new.deleted_at is null
    and exists (select 1 from private.mail_settings s where s.enabled
      and new.created_at >= s.rollout_at) then
    insert into private.mail_outbox(event_key,kind,user_id,email)
    values ('account_welcome/'||new.id,'account_welcome',new.id,lower(btrim(new.email)))
    on conflict(event_key) do nothing;
  end if;
  return new;
end $$;
create trigger mail_verified_account after insert or update of email_confirmed_at on auth.users
for each row execute function private.mail_account_event();

create function private.mail_lifecycle_suppression() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.marketing_suppressed then
    perform private.mail_lock();
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason='account_deletion', confirm_hash=null where user_id=new.user_id;
    update private.mail_outbox set state='suppressed',last_error='account_deletion'
      where user_id=new.user_id and state in ('ready','leased','sending','uncertain');
  end if;
  return new;
end $$;
create trigger mail_account_suppression after insert or update on private.account_lifecycle
for each row execute function private.mail_lifecycle_suppression();

create function private.mail_email_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if lower(btrim(old.email)) is distinct from lower(btrim(new.email)) or new.deleted_at is not null then
    perform private.mail_lock();
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason='identity_changed',confirm_hash=null where user_id=new.id;
    update private.mail_outbox set state='suppressed',last_error='identity_changed'
      where user_id=new.id and state in ('ready','leased','sending','uncertain');
  end if;
  return new;
end $$;
create trigger mail_identity_changed after update of email,deleted_at on auth.users
for each row execute function private.mail_email_change();

create function public.newsletter_status() returns jsonb
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare a jsonb; c private.newsletter_consent; e text; s private.mail_settings;
begin
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  select * into s from private.mail_settings;
  select * into c from private.newsletter_consent where user_id=auth.uid() and email=e order by requested_at desc limit 1;
  return jsonb_build_object('subject_id',auth.uid(),'state',case
    when exists(select 1 from private.account_lifecycle where user_id=auth.uid())
      or exists(select 1 from private.mail_suppression where email=e) then 'suppressed'
    when c.id is null then 'not_subscribed'
    when c.unsubscribed_at is not null then 'unsubscribed'
    when c.confirmed_at is not null then 'subscribed'
    when c.expires_at<=clock_timestamp() then 'expired' else 'pending' end,
    'requested_at',c.requested_at,'confirmed_at',c.confirmed_at,'unsubscribed_at',c.unsubscribed_at,
    'consent_version',s.consent_version,'consent_text',s.consent_text,'enabled',s.enabled);
end $$;

create function public.newsletter_request(p_opt_in boolean, p_version text, p_source text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb; e text; c private.newsletter_consent; s private.mail_settings; n timestamptz;
begin
  -- Match lifecycle's lock order and recheck live session after waiting.
  perform 1 from auth.users where id=auth.uid() for share;
  perform 1 from public.profiles where id=auth.uid() for no key update;
  perform private.mail_lock();
  a := private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then raise exception 'account_restricted' using errcode='PT403'; end if;
  if p_opt_in is distinct from true then return public.newsletter_status(); end if;
  select * into s from private.mail_settings;
  if not s.enabled then raise exception 'mail_disabled' using errcode='PT503'; end if;
  if p_version is distinct from s.consent_version or p_source is null or p_source not in ('signup','settings') then
    raise exception 'consent_invalid' using errcode='PT400'; end if;
  select lower(btrim(email)) into e from auth.users where id=auth.uid();
  if e is null or exists(select 1 from private.account_lifecycle where user_id=auth.uid())
    or exists(select 1 from private.mail_suppression where email=e) then
    raise exception 'mail_suppressed' using errcode='PT403'; end if;
  select * into c from private.newsletter_consent where user_id=auth.uid() and email=e
    and unsubscribed_at is null and confirmed_at is not null limit 1;
  if found then return public.newsletter_status(); end if;
  n := clock_timestamp();
  if exists(select 1 from private.newsletter_consent where (user_id=auth.uid() or email=e)
      and requested_at>n-interval '1 minute')
    or (select count(*) from private.newsletter_consent where (user_id=auth.uid() or email=e)
      and requested_at>n-interval '24 hours') >= 3 then
    raise exception 'newsletter_rate_limited' using errcode='PT429'; end if;
  update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,n),
    suppression_reason=coalesce(suppression_reason,'superseded'),confirm_hash=null
    where user_id=auth.uid() and unsubscribed_at is null;
  insert into private.newsletter_consent(user_id,email,version,consent_text,source,requested_at,expires_at)
    values(auth.uid(),e,s.consent_version,s.consent_text,p_source,n,n+interval '24 hours') returning * into c;
  insert into private.mail_outbox(event_key,kind,user_id,email,consent_id)
    values('newsletter_confirm/'||c.id,'newsletter_confirm',c.user_id,e,c.id);
  return public.newsletter_status();
end $$;

create function public.newsletter_withdraw() returns jsonb
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
    where user_id=auth.uid() and email=e and kind<>'account_welcome'
    and state in ('ready','leased','sending','uncertain');
  return public.newsletter_status();
end $$;

-- Capability endpoints are service-only; raw tokens are hashed in Edge, never stored.
create function public.newsletter_token(p_action text,p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c private.newsletter_consent; o private.mail_outbox;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_action is null or p_action not in ('confirm','unsubscribe') then
    raise exception 'token_invalid' using errcode='PT400'; end if;
  perform private.mail_lock();
  if p_action='unsubscribe' then
    select * into c from private.newsletter_consent where unsubscribe_hash=p_hash;
    if found then
      -- Old links also suppress a later opt-in for the same mailbox/identity.
      update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
        suppression_reason=coalesce(suppression_reason,'unsubscribe'),confirm_hash=null
        where user_id=c.user_id and email=c.email;
      update private.mail_outbox set state='suppressed',last_error='unsubscribe'
        where user_id=c.user_id and email=c.email and kind<>'account_welcome'
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

create function public.mail_claim() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  if not exists(select 1 from private.mail_settings where enabled) then return null; end if;
  update private.mail_outbox set state='uncertain',last_error='worker_lost'
    where state='sending' and lease_until<clock_timestamp();
  update private.mail_outbox set state='ready' where state='leased' and lease_until<clock_timestamp();
  update private.mail_outbox m set state='suppressed',last_error='suppressed_or_stale'
    where state in ('ready','leased') and not private.mail_allowed(m);
  update private.mail_outbox set state='failed',last_error='retry_exhausted'
    where state='ready' and (attempts>=5 or first_attempt_at<clock_timestamp()-interval '23 hours');
  select * into o from private.mail_outbox where state='ready' and next_at<=clock_timestamp()
    order by created_at,id limit 1 for update;
  if not found then return null; end if;
  update private.mail_outbox set state='leased',lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes'
    where id=o.id returning * into o;
  return to_jsonb(o);
end $$;

create function public.mail_prepare(p_id uuid,p_lease uuid,p_payload_hash text,p_confirm_hash text,p_unsubscribe_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  select * into o from private.mail_outbox where id=p_id;
  if not found or o.state<>'leased' or o.lease_id is distinct from p_lease or o.lease_until<=clock_timestamp()
    or not exists(select 1 from private.mail_settings where enabled) then return false; end if;
  if not private.mail_allowed(o) then
    update private.mail_outbox set state='suppressed',last_error='suppressed_or_stale' where id=o.id;
    return false;
  end if;
  if p_payload_hash is null or p_payload_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_hash'; end if;
  if o.payload_hash is not null and o.payload_hash<>p_payload_hash then
    update private.mail_outbox set state='failed',last_error='payload_changed' where id=o.id;
    return false;
  end if;
  if o.kind='newsletter_welcome' and not exists(select 1 from private.newsletter_consent
    where id=o.consent_id and unsubscribe_hash=p_unsubscribe_hash) then
    update private.mail_outbox set state='failed',last_error='token_key_changed' where id=o.id;
    return false;
  end if;
  if o.kind='newsletter_confirm' then
    if p_confirm_hash is null or p_unsubscribe_hash is null then raise exception 'missing_hash'; end if;
    update private.newsletter_consent set confirm_hash=p_confirm_hash,unsubscribe_hash=p_unsubscribe_hash where id=o.consent_id;
  end if;
  update private.mail_outbox set state='sending',attempts=attempts+1,payload_hash=p_payload_hash,
    first_attempt_at=coalesce(first_attempt_at,clock_timestamp()) where id=o.id;
  return true;
end $$;

create function public.mail_finish(p_id uuid,p_lease uuid,p_result text,p_provider_id text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  select * into o from private.mail_outbox where id=p_id;
  if not found or o.lease_id is distinct from p_lease then return; end if;
  if p_result not in ('accepted','rate_limited','failed','uncertain') or p_result is null
    or (p_result='accepted' and coalesce(p_provider_id,'')='') then raise exception 'invalid_result'; end if;
  -- Suppression and delivery evidence are monotonic, even if webhook arrived first.
  if p_result='accepted' and o.provider_id is null then
    update private.mail_outbox set provider_id=p_provider_id where id=o.id;
  end if;
  if o.state not in ('sending','uncertain') then return; end if;
  update private.mail_outbox set state=case when p_result='rate_limited' then
      case when attempts>=5 then 'failed' else 'ready' end else p_result end,
    next_at=clock_timestamp()+make_interval(secs=>least(3600,60*power(2,attempts)::integer)),
    last_error=case when p_result='accepted' then null else p_result end where id=o.id;
end $$;

create function public.mail_record_webhook(p_event_id text,p_provider_id text,p_type text,p_outbox_id uuid,p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  if length(p_event_id)>200 or length(p_provider_id)>200 then raise exception 'invalid_event'; end if;
  select * into o from private.mail_outbox where provider_id=p_provider_id
    or (id=p_outbox_id and provider_id is null and first_attempt_at is not null) limit 1;
  if not found or o.email is distinct from lower(btrim(p_email)) then
    -- Retry unmatched events instead of permanently discarding reconciliation evidence.
    raise exception 'event_unmatched' using errcode='PT503'; end if;
  insert into private.mail_webhook_event(event_id,provider_id,event_type,outbox_id)
    values(p_event_id,p_provider_id,p_type,o.id) on conflict do nothing;
  if not found then return; end if;
  update private.mail_outbox set provider_id=p_provider_id where id=o.id;
  if p_type in ('email.bounced','email.complained','email.suppressed') then
    insert into private.mail_suppression(email,reason) values(o.email,p_type) on conflict do nothing;
    update private.newsletter_consent set unsubscribed_at=coalesce(unsubscribed_at,clock_timestamp()),
      suppression_reason=p_type,confirm_hash=null where email=o.email;
    update private.mail_outbox set state='suppressed',last_error=p_type
      where email=o.email and state<>'delivered';
  elsif p_type='email.delivered' then
    update private.mail_outbox set state='delivered' where id=o.id and state<>'suppressed';
  elsif p_type='email.sent' then
    update private.mail_outbox set state='accepted' where id=o.id and state in ('sending','uncertain','ready','leased');
  elsif p_type='email.failed' then
    update private.mail_outbox set state='failed',last_error=p_type
      where id=o.id and state not in ('delivered','suppressed');
  end if;
end $$;

-- Explicit allowlist, independent of project default function privileges.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='private' and p.proname in ('mail_lock','mail_allowed','mail_account_event','mail_lifecycle_suppression','mail_email_change'))
      or (n.nspname='public' and p.proname in ('newsletter_status','newsletter_request','newsletter_withdraw','newsletter_token',
        'mail_claim','mail_prepare','mail_finish','mail_record_webhook')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role,supabase_auth_admin',f.signature);
  end loop;
end $$;
grant execute on function public.newsletter_status(),public.newsletter_request(boolean,text,text),public.newsletter_withdraw() to authenticated;
grant execute on function public.newsletter_token(text,text), public.mail_claim(),
  public.mail_prepare(uuid,uuid,text,text,text),public.mail_finish(uuid,uuid,text,text),
  public.mail_record_webhook(text,text,text,uuid,text) to service_role;
commit;
