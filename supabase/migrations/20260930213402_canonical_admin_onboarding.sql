begin;

do $$ begin
  if to_regprocedure('private.portal_staff_context()') is null
    or to_regprocedure('public.admin_portal_assign_member(uuid,uuid,bigint[])') is null
    or to_regclass('public.admin_audit_events') is null
    or to_regclass('private.account_lifecycle') is null then
    raise exception 'Reviewed canonical staff, invitation, audit and lifecycle prerequisites required';
  end if;
end $$;

-- Reuse the immutable audit as the bounded request receipt, not a second queue.
create unique index admin_team_onboarding_receipt_once
on public.admin_audit_events(entity_id, operation)
where entity='team_onboarding' and operation in ('completed','delivered');

create function public.admin_team_onboarding(
  action text, target_email text default null, target_locations bigint[] default null,
  target_user_id uuid default null, request_id bigint default null
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  before_context jsonb; actor uuid; actor_name text; mode text;
  email_address text; ids bigint[]; target uuid; matches uuid[];
  receipt public.admin_audit_events%rowtype; receipt_id bigint;
  account record; email_action text:='invite'; target_role text; completed boolean:=false;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if before_context->>'role' is distinct from 'Owner' then
    raise exception 'owner_required' using errcode='PT403';
  end if;
  if action is null or action not in ('invite','resend','authorize','complete') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  if action in ('invite','resend') then
    if request_id is not null or array_ndims(target_locations) is distinct from 1
      or cardinality(target_locations) not between 1 and 50
      or exists(select 1 from unnest(target_locations) n where n is null or n<=0)
      or (action='invite' and (target_user_id is not null or target_email is null
        or length(target_email)>254 or target_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
      or (action='resend' and (target_user_id is null or target_email is not null
        or cardinality(target_locations)<>1)) then
      raise exception 'invalid_request' using errcode='22023';
    end if;
    select array_agg(distinct n order by n) into ids from unnest(target_locations) n;
    mode:=action;
    if mode='invite' then
      email_address:=lower(btrim(target_email));
      select array_agg(id) into matches from auth.users where lower(email)=email_address;
      if cardinality(matches)>1 then raise exception 'invitation_conflict' using errcode='PT409'; end if;
      target:=matches[1];
    else
      target:=target_user_id;
      select lower(email) into email_address from auth.users where id=target;
      if email_address is null then raise exception 'invitation_conflict' using errcode='PT409'; end if;
    end if;
  else
    if request_id is null or target_email is not null or target_locations is not null
      or (action='authorize' and target_user_id is not null)
      or (action='complete' and target_user_id is null) then
      raise exception 'invalid_request' using errcode='22023';
    end if;
    -- Lock the immutable request row to serialize completion and delivery replay.
    select * into receipt from public.admin_audit_events where id=request_id
      and entity='team_onboarding' and operation='requested' for update;
    if not found or receipt.actor_id is distinct from actor
      or receipt.created_at<clock_timestamp()-interval '10 minutes' then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
    receipt_id:=receipt.id; mode:=receipt.after_values->>'mode';
    email_address:=receipt.after_values->>'email'; ids:=receipt.location_ids;
    target:=(receipt.after_values->>'target_user_id')::uuid;
    if action='complete' then
      if target is not null and target is distinct from target_user_id then
        raise exception 'invitation_conflict' using errcode='PT409';
      end if;
      target:=target_user_id;
    end if;
    select exists(select 1 from public.admin_audit_events where entity='team_onboarding'
      and entity_id=receipt_id::text and operation='completed') into completed;
    if action='authorize' and completed then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
  end if;

  if exists(select 1 from unnest(ids) n where not exists(select 1
    from public."Location_to_Admin" where user_id=actor and location_id=n)) then
    raise exception 'location_access_denied' using errcode='PT403';
  end if;
  perform 1 from public."Locations" where id=any(ids) order by id for share;
  if (select count(*) from public."Locations" where id=any(ids))<>cardinality(ids) then
    raise exception 'location_access_denied' using errcode='PT403';
  end if;
  if target is null then
    if mode<>'invite' or action='complete' or exists(select 1 from auth.users where lower(email)=email_address) then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
  else
    -- Same target lock order as lifecycle: Auth SHARE, then profile NO KEY UPDATE.
    select email,email_confirmed_at,is_anonymous,deleted_at,banned_until into account
      from auth.users where id=target for share;
    if not found or account.is_anonymous is distinct from false or account.deleted_at is not null
      or (account.banned_until is not null and account.banned_until>clock_timestamp())
      or lower(account.email) is distinct from email_address then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
    email_action:=case when account.email_confirmed_at is null then 'invite' else 'recovery' end;
    select roles::text into target_role from public.profiles where id=target for no key update;
    if target=actor or target_role='Owner' or exists(select 1 from private.account_lifecycle
      where user_id=target and restored_at is null) then
      raise exception 'target_restricted' using errcode='PT403';
    end if;
    if (mode='resend' or completed) and (target_role is distinct from 'Admin'
      or exists(select 1 from unnest(ids) n where not exists(select 1
        from public."Location_to_Admin" where user_id=target and location_id=n))) then
      raise exception 'invitation_conflict' using errcode='PT409';
    end if;
  end if;

  if action in ('invite','resend') then
    select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
      values(actor,actor_name,'team_onboarding',coalesce(target::text,email_address),'requested',ids,
        jsonb_build_object('mode',mode,'email',email_address,'target_user_id',target)) returning id into receipt_id;
  elsif action='complete' and not completed then
    if mode='invite' then
      perform public.admin_portal_assign_member(actor,target,ids);
    else
      insert into public.admin_invitations(user_id,location_id,invited_by)
        select target,n,actor from unnest(ids) n on conflict(user_id,location_id) do nothing;
    end if;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
      values(actor,receipt.actor_name,'team_onboarding',receipt_id::text,'completed',ids,
        jsonb_build_object('target_user_id',target));
  end if;
  -- Recheck after membership/FK/audit triggers, not just before their waits.
  if private.portal_staff_context() is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  if action in ('authorize','complete') and receipt.created_at<clock_timestamp()-interval '10 minutes' then
    raise exception 'invitation_conflict' using errcode='PT409';
  end if;
  if target is not null and (not exists(select 1 from auth.users where id=target
      and is_anonymous is false and deleted_at is null and lower(email)=email_address
      and (banned_until is null or banned_until<=clock_timestamp()))
    or exists(select 1 from private.account_lifecycle where user_id=target and restored_at is null)
    or exists(select 1 from public.profiles where id=target and roles::text='Owner')
    or (action='complete' and (not exists(select 1 from public.profiles where id=target and roles::text='Admin')
      or exists(select 1 from unnest(ids) n where not exists(select 1 from public."Location_to_Admin"
        where user_id=target and location_id=n))))) then
    raise exception 'target_restricted' using errcode='PT403';
  end if;
  return jsonb_build_object('request_id',receipt_id::text,'actor_id',actor,'target_user_id',target,
    'email',email_address,'location_ids',ids,'email_action',email_action);
end $$;
revoke all on function public.admin_team_onboarding(text,text,bigint[],uuid,bigint)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.admin_team_onboarding(text,text,bigint[],uuid,bigint) to authenticated;

-- Only the trusted Auth adapter records a successful send; a browser cannot
-- forge delivery or use this metadata-only RPC to assign a role/location.
create function public.admin_team_invitation_delivered(request_id bigint, target_user_id uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
declare receipt public.admin_audit_events%rowtype;
begin
  select * into receipt from public.admin_audit_events where id=request_id
    and entity='team_onboarding' and operation='requested' for update;
  if not found or not exists(select 1 from public.admin_audit_events
    where entity='team_onboarding' and entity_id=request_id::text and operation='completed'
      and after_values->>'target_user_id'=target_user_id::text) then
    raise exception 'invitation_conflict' using errcode='PT409';
  end if;
  if exists(select 1 from public.admin_audit_events where entity='team_onboarding'
    and entity_id=request_id::text and operation='delivered') then return; end if;
  update public.admin_invitations set delivery_status='sent',last_sent_at=clock_timestamp()
    where user_id=target_user_id and location_id=any(receipt.location_ids);
  insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
    values(receipt.actor_id,receipt.actor_name,'team_onboarding',request_id::text,'delivered',receipt.location_ids,
      jsonb_build_object('target_user_id',target_user_id));
end $$;
revoke all on function public.admin_team_invitation_delivered(bigint,uuid)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.admin_team_invitation_delivered(bigint,uuid) to service_role;

commit;
