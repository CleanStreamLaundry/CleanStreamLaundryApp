begin;

-- Profiles and canonical admission keep their existing Roles enum. Missing
-- access rows mean Manager for existing Admins; no person is reassigned here.
create table private.staff_portal_access (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  portal_role text not null check (portal_role in ('Manager','Maintenance'))
);
alter table private.staff_portal_access enable row level security;
revoke all on private.staff_portal_access from public,anon,authenticated,service_role;

create function private.effective_portal_role(actor uuid)
returns text language sql stable security definer set search_path='' as $$
  select case p.roles::text when 'Owner' then 'Owner'
    when 'Admin' then coalesce(a.portal_role,'Manager') end
  from public.profiles p left join private.staff_portal_access a on a.user_id=p.id where p.id=actor;
$$;
create function private.portal_location_ids(actor uuid)
returns bigint[] language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(l.id order by l.id),'{}') from public."Locations" l
  where private.effective_portal_role(actor)='Owner' or exists(
    select 1 from public."Location_to_Admin" m where m.user_id=actor and m.location_id=l.id);
$$;
revoke all on function private.effective_portal_role(uuid),private.portal_location_ids(uuid)
  from public,anon,authenticated,service_role;

alter function private.portal_staff_context() rename to portal_staff_context_before_roles;
create function private.portal_staff_context()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb;
begin
  ctx:=private.portal_staff_context_before_roles();
  return ctx||jsonb_build_object('portalRole',private.effective_portal_role((ctx->>'actor')::uuid),
    'locations',to_jsonb(private.portal_location_ids((ctx->>'actor')::uuid)));
end $$;
revoke all on function private.portal_staff_context(),private.portal_staff_context_before_roles()
  from public,anon,authenticated,service_role;

create function private.require_portal_action(actor uuid,action text,payload jsonb default '{}')
returns void language plpgsql stable security definer set search_path='' as $$
declare role_name text:=private.effective_portal_role(actor);
begin
  if role_name='Owner' then return; end if;
  if role_name in ('Manager','Maintenance') and action in
    ('identity','locations','maintenance','history','updateMaintenance','assignees') then return; end if;
  if role_name='Manager' and action in ('overview','machines','team','setAvailability') then return; end if;
  if action='exportRecords' and
    ((role_name='Manager' and payload->>'dataset' in ('maintenance','machines'))
      or (role_name='Maintenance' and payload->>'dataset'='maintenance')) then return; end if;
  raise exception 'portal_action_forbidden' using errcode='PT403';
end $$;
revoke all on function private.require_portal_action(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Keep the reviewed financial, filter, concurrency and maintenance bodies.
-- Only replace their repeated location projection with the shared Owner-all
-- scope. Exact-source assertions make an unexpected installed body fail closed.
do $$
declare signature text; definition text; previous text; replacement text;
begin
  for signature,previous in values
    ('public.admin_portal_data_v1(uuid,text,jsonb)',
      'select coalesce(array_agg(location_id::bigint),''{}'') into ids from public."Location_to_Admin" where user_id = actor;'),
    ('public.admin_portal_data_before_reporting(uuid,text,jsonb)',
      'select coalesce(array_agg(location_id::bigint),''{}'') into ids from public."Location_to_Admin" where user_id=actor;'),
    ('public.admin_portal_rows_before_reporting(uuid,text)',
      'select coalesce(array_agg(location_id::bigint),''{}'') into ids from public."Location_to_Admin" where user_id=actor;'),
    ('public.admin_portal_data(uuid,text,jsonb)',
      'select coalesce(array_agg(location_id::bigint),''{}'') into ids from public."Location_to_Admin" where user_id=actor;')
  loop
    definition:=pg_get_functiondef(signature::regprocedure);
    if position(previous in definition)=0 then raise exception 'Unreviewed portal scope body: %',signature; end if;
    replacement:=replace(definition,previous,'ids:=private.portal_location_ids(actor);');
    execute replacement;
  end loop;
end $$;

alter function public.admin_portal_rows(uuid,text) rename to admin_portal_rows_before_roles;
create function public.admin_portal_rows(actor uuid,dataset text)
returns setof jsonb language plpgsql security invoker set search_path='' as $$
declare role_name text:=private.effective_portal_role(actor); ids bigint[]:=private.portal_location_ids(actor);
begin
  perform private.require_portal_action(actor,case when dataset='machines' then 'machines' else dataset end);
  if dataset='audit' then
    return query select to_jsonb(a)||jsonb_build_object('id',a.id::text,'date',a.created_at)
      from public.admin_audit_events a;
  elsif dataset='team' then
    return query select jsonb_build_object('id',p.id||':'||l.id,'user_id',p.id,'name',p.full_name,
      'email',u.email,'role',p.roles,'portal_role',private.effective_portal_role(p.id),
      'location_id',l.id,'location_name',l."Name",
      'assignment_count',(select count(*) from public."Location_to_Admin" all_assignments where all_assignments.user_id=p.id),
      'invitation_status',case when u.last_sign_in_at is not null then 'active' when i.delivery_status='failed' then 'failed'
        when i.last_sent_at is not null then 'invited' else 'pending' end,'invited_at',i.invited_at,'date',i.invited_at)
    from public."Location_to_Admin" a join public.profiles p on p.id=a.user_id join auth.users u on u.id=p.id
    join public."Locations" l on l.id=a.location_id left join public.admin_invitations i on i.user_id=a.user_id and i.location_id=a.location_id
    where a.location_id=any(ids);
  elsif dataset='machines' and role_name='Manager' then
    -- Allowlist before search/filter/export, so hidden data is not searchable.
    return query select jsonb_build_object('id',m.id::text,'name',m."Name",'location_id',m."Location_ID",'location_name',l."Name",
      'machine_type',m."Machine_type",'status',m."Status",'capacity_kg',m."Weight_kg",
      'is_out_of_service',m.is_out_of_service,'service_reason',m.service_reason,'service_updated_at',m.service_updated_at)
    from public."Machines" m join public."Locations" l on l.id=m."Location_ID" where m."Location_ID"=any(ids);
  else return query select * from public.admin_portal_rows_before_roles(actor,dataset);
  end if;
end $$;
revoke all on function public.admin_portal_rows(uuid,text),public.admin_portal_rows_before_roles(uuid,text)
  from public,anon,authenticated,service_role;

alter function public.admin_portal_data(uuid,text,jsonb) rename to admin_portal_data_before_roles;
create function public.admin_portal_data(actor uuid,action text,payload jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare role_name text:=private.effective_portal_role(actor); result jsonb;
  ids bigint[]:=private.portal_location_ids(actor); loc bigint; machine public."Machines"%rowtype; note text; unavailable boolean;
begin
  perform private.require_portal_action(actor,action,payload);
  if action='identity' then
    return public.admin_portal_data_before_roles(actor,action,payload)||jsonb_build_object('portalRole',role_name);
  elsif action='overview' and role_name='Manager' then
    return jsonb_build_object('locations',cardinality(ids),
      'machines',(select count(*) from public."Machines" where "Location_ID"=any(ids)),
      'openMaintenance',(public.admin_portal_records(actor,'maintenance','{"status":"unresolved"}')->>'total')::bigint,
      'updatedAt',clock_timestamp());
  elsif action='machines' and role_name='Manager' then
    loc:=(payload->>'locationId')::bigint;
    if loc is null or not(loc=any(ids)) then raise exception 'location_access_denied' using errcode='PT403'; end if;
    return (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'Name',m."Name",'Location_ID',m."Location_ID",
      'Machine_type',m."Machine_type",'Status',m."Status",'Weight_kg',m."Weight_kg",'Runtime',m."Runtime",
      'is_out_of_service',m.is_out_of_service,'service_reason',m.service_reason,'service_updated_at',m.service_updated_at)
      order by m."Name"),'[]') from public."Machines" m where m."Location_ID"=loc);
  elsif action='setAvailability' and role_name='Manager' then
    -- Same lock/version/validation contract as the existing Owner operation.
    select * into machine from public."Machines" where id=(payload->>'id')::bigint for update;
    if not found or not(machine."Location_ID"=any(ids)) then raise exception 'location_access_denied' using errcode='PT403'; end if;
    if jsonb_typeof(payload->'outOfService') is distinct from 'boolean' then raise exception 'Choose a valid availability'; end if;
    unavailable:=(payload->>'outOfService')::boolean; note:=nullif(btrim(payload->>'reason'),'');
    if unavailable and note is null then raise exception 'Enter the reason this machine is out of service'; end if;
    if length(coalesce(note,''))>1000 then raise exception 'Keep the reason under 1,000 characters'; end if;
    if (payload->>'expectedUpdatedAt')::timestamptz is distinct from machine.service_updated_at then
      raise exception 'Machine availability changed. Refresh and try again.'; end if;
    if unavailable=machine.is_out_of_service then raise exception 'This availability is already set'; end if;
    perform set_config('cleanstream.portal_actor',actor::text,true);
    update public."Machines" set is_out_of_service=unavailable,service_reason=note,
      service_updated_at=clock_timestamp(),service_updated_by=actor where id=machine.id;
    return '{"success":true}';
  end if;
  result:=public.admin_portal_data_before_roles(actor,action,payload);
  if action='overview' and role_name='Owner' then
    result:=jsonb_set(result,'{reporting,scope}',to_jsonb('All locations; all unlocated wallet loads and legacy records'::text));
  end if;
  return result;
end $$;
revoke all on function public.admin_portal_data(uuid,text,jsonb),public.admin_portal_data_before_roles(uuid,text,jsonb)
  from public,anon,authenticated,service_role;

-- Financial predicates used by older SQL clients must no longer mean all staff.
-- Dedicated maintenance/membership policies below retain operational access.
create or replace function public.is_admin_or_owner()
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  return private.account_access_allowed() and private.effective_portal_role(auth.uid())='Owner';
exception when sqlstate 'PT401' then return false;
end $$;
create or replace function private.portal_record_access(kind text,record jsonb)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare role_name text;
begin
  if not private.account_access_allowed() then return false; end if;
  if record->>'user_id'=auth.uid()::text then return true; end if;
  role_name:=private.effective_portal_role(auth.uid());
  if role_name='Owner' then return true; end if;
  if kind<>'maintenance' or role_name is null then return false; end if;
  return private.portal_record_access_before_authorization(kind,record);
end $$;
create or replace function private.maintenance_record_access(report_user_id uuid,report_location_id bigint)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare role_name text;
begin
  if not private.account_access_allowed() then return false; end if;
  if report_user_id=auth.uid() then return true; end if;
  role_name:=private.effective_portal_role(auth.uid());
  return coalesce(role_name='Owner' or (role_name in ('Manager','Maintenance') and report_location_id=any(private.portal_location_ids(auth.uid()))),false);
end $$;
revoke all on function private.maintenance_record_access(uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function private.maintenance_record_access(uuid,bigint) to authenticated;
alter policy portal_membership_direct_self on public."Location_to_Admin"
  using(user_id=auth.uid() and private.account_access_allowed());
create policy portal_maintenance_operational_read on public."Maintenance" for select to authenticated
  using(private.maintenance_record_access(user_id,location_id));

-- Existing private Storage policies call maintenance_record_access through the
-- attachment predicate. No bucket policy, public URL or service bypass is added.
-- Raw vend rows expose payment evidence; ordinary customer self-reads survive.
create policy portal_vend_financial_privacy on public.cortina_vend_sessions as restrictive for select to authenticated
  using(user_id=auth.uid() or public.is_admin_or_owner());

alter function public.admin_resolve_credit(bigint,text,text) rename to admin_resolve_credit_before_roles;
create function public.admin_resolve_credit(target_refund_id bigint,target_decision text,resolution_note text default '')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb; result jsonb;
begin
  ctx:=private.portal_owner_context();
  result:=public.admin_resolve_credit_before_roles(target_refund_id,target_decision,resolution_note);
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
revoke all on function public.admin_resolve_credit_before_roles(bigint,text,text),public.admin_resolve_credit(bigint,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_resolve_credit(bigint,text,text) to authenticated;

alter function public.record_deleted_account_complaint(uuid,text,text) rename to record_deleted_account_complaint_before_roles;
create function public.record_deleted_account_complaint(wallet_id uuid,complaint_note text,resolution text default 'denied')
returns bigint language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb; result bigint;
begin
  ctx:=private.portal_owner_context();
  result:=public.record_deleted_account_complaint_before_roles(wallet_id,complaint_note,resolution);
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
revoke all on function public.record_deleted_account_complaint_before_roles(uuid,text,text),public.record_deleted_account_complaint(uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.record_deleted_account_complaint(uuid,text,text) to authenticated;

create unique index admin_staff_role_request_receipt on public.admin_audit_events(entity_id)
  where entity='staff_role_management' and operation='role_change';
create function public.admin_staff_role_management(action text,payload jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb; actor uuid; target uuid; request_id uuid; desired text; expected text; note text;
  prior_role text; canonical jsonb; result jsonb; receipt public.admin_audit_events%rowtype;
begin
  ctx:=private.portal_owner_context(); actor:=(ctx->>'actor')::uuid;
  if jsonb_typeof(payload) is distinct from 'object' then raise exception 'invalid_request' using errcode='22023'; end if;
  request_id:=(payload->>'requestId')::uuid;
  if request_id is null then raise exception 'invalid_request' using errcode='22023'; end if;
  if action='staffRoleStatus' then
    select * into receipt from public.admin_audit_events where entity='staff_role_management'
      and operation='role_change' and entity_id=request_id::text and actor_id=actor;
    result:=case when found then jsonb_build_object('state','completed','result',receipt.after_values->'result')
      else jsonb_build_object('state','not_found') end;
  elsif action='setStaffRole' then
    target:=(payload->>'userId')::uuid; desired:=payload->>'portalRole';
    expected:=payload->>'expectedPortalRole'; note:=btrim(payload->>'note');
    if target is null or coalesce(desired,'') not in ('Manager','Maintenance')
      or coalesce(expected,'') not in ('Manager','Maintenance') or coalesce(note,'')='' or length(note)>4000 then
      raise exception 'invalid_request' using errcode='22023'; end if;
    if target=actor then raise exception 'staff_self_change_forbidden' using errcode='PT403'; end if;
    canonical:=jsonb_build_object('userId',target,'portalRole',desired,'expectedPortalRole',expected,'requestId',request_id,'note',note);
    -- Same global role lock and Auth/profile order as additional-Owner changes.
    perform pg_advisory_xact_lock(814716290);
    perform 1 from auth.users where id in(actor,target) order by id for share;
    perform 1 from public.profiles where id in(actor,target) order by id for no key update;
    if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
    select * into receipt from public.admin_audit_events where entity='staff_role_management'
      and operation='role_change' and entity_id=request_id::text;
    if found then
      if receipt.actor_id is distinct from actor or receipt.after_values->'request' is distinct from canonical then
        raise exception 'staff_role_request_conflict' using errcode='PT409'; end if;
      result:=receipt.after_values->'result';
    else
      prior_role:=private.effective_portal_role(target);
      if prior_role is distinct from expected then raise exception 'staff_role_state_changed' using errcode='PT409'; end if;
      if not exists(select 1 from auth.users where id=target and is_anonymous is false and deleted_at is null
        and (banned_until is null or banned_until<=clock_timestamp()))
        or exists(select 1 from private.account_lifecycle where user_id=target and restored_at is null) then
        raise exception 'staff_role_target_ineligible' using errcode='PT409'; end if;
      insert into private.staff_portal_access(user_id,portal_role) values(target,desired)
        on conflict(user_id) do update set portal_role=excluded.portal_role;
      result:=jsonb_build_object('userId',target,'role','Admin','portalRole',desired,'requestId',request_id,'changed',prior_role<>desired);
      insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,before_values,after_values)
        select actor,coalesce(nullif(full_name,''),email,'Owner'),'staff_role_management',request_id::text,'role_change',
          jsonb_build_object('portalRole',prior_role),jsonb_build_object('request',canonical,'result',result)
        from public.profiles where id=actor;
      if private.effective_portal_role(target) is distinct from desired
        or exists(select 1 from private.account_lifecycle where user_id=target and restored_at is null)
        or not exists(select 1 from auth.users where id=target and is_anonymous is false and deleted_at is null
          and (banned_until is null or banned_until<=clock_timestamp())) then
        raise exception 'staff_role_target_ineligible' using errcode='PT409'; end if;
    end if;
  else raise exception 'invalid_request' using errcode='22023';
  end if;
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
revoke all on function public.admin_staff_role_management(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_staff_role_management(text,jsonb) to authenticated;


-- Owner invitation scope is all locations, without synthetic membership writes.
create or replace function public.admin_portal_assign_member(actor uuid,target uuid,target_locations bigint[])
returns void language plpgsql security invoker set search_path='' as $$
declare loc bigint; email_address text;
begin
  if cardinality(target_locations) is null or cardinality(target_locations)<1 or cardinality(target_locations)>50 then raise exception 'Choose at least one location'; end if;
  if private.effective_portal_role(actor) is distinct from 'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
  if exists(select 1 from unnest(target_locations) l where l is null or not(l=any(private.portal_location_ids(actor)))) then raise exception 'Location access denied' using errcode='42501'; end if;
  select email into email_address from auth.users where id=target;
  if email_address is null then raise exception 'Auth account not found'; end if;
  insert into public.profiles(id,email,roles) values(target,email_address,'User') on conflict(id) do nothing;
  foreach loc in array target_locations loop
    perform public.admin_portal_data(actor,'assignMember',jsonb_build_object('userId',target,'locationId',loc));
  end loop;
end $$;

-- Replace, not overload: old five-argument clients retain the Manager default.
-- Role selection is frozen in the existing immutable onboarding request.
drop function public.admin_team_onboarding(text,text,bigint[],uuid,bigint);
create function public.admin_team_onboarding(
  action text, target_email text default null, target_locations bigint[] default null,
  target_user_id uuid default null, request_id bigint default null, target_portal_role text default 'Manager'
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  before_context jsonb; actor uuid; actor_name text; mode text;
  email_address text; ids bigint[]; target uuid; matches uuid[];
  receipt public.admin_audit_events%rowtype; receipt_id bigint;
  requested_role text; expected_portal_role text;
  account record; email_action text:='invite'; target_role text; completed boolean:=false;
begin
  before_context:=private.portal_staff_context(); actor:=(before_context->>'actor')::uuid;
  if before_context->>'role' is distinct from 'Owner' then
    raise exception 'owner_required' using errcode='PT403';
  end if;
  if action is null or action not in ('invite','resend','authorize','complete') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  if target_portal_role is null or target_portal_role not in ('Manager','Maintenance') then
    raise exception 'invalid_request' using errcode='22023'; end if;
  if action in ('invite','resend') then
    requested_role:=target_portal_role;
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
    requested_role:=coalesce(receipt.after_values->>'portal_role','Manager');
    expected_portal_role:=receipt.after_values->>'expected_portal_role';
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
    from public."Locations" where id=n)) then
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
    expected_portal_role:=private.effective_portal_role(target);
    if mode='resend' then requested_role:=expected_portal_role; end if;
    if target_role='Admin' and requested_role is distinct from expected_portal_role then
      raise exception 'invitation_role_conflict' using errcode='PT409'; end if;
  elsif mode='invite' and not completed and
    private.effective_portal_role(target) is distinct from expected_portal_role then
    raise exception 'invitation_role_conflict' using errcode='PT409';
  end if;

  if action in ('invite','resend') then
    select coalesce(nullif(full_name,''),email,'Owner') into actor_name from public.profiles where id=actor;
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,after_values)
      values(actor,actor_name,'team_onboarding',coalesce(target::text,email_address),'requested',ids,
        jsonb_build_object('mode',mode,'email',email_address,'target_user_id',target,'portal_role',requested_role,'expected_portal_role',expected_portal_role)) returning id into receipt_id;
  elsif action='complete' and not completed then
    if mode='invite' then
      perform public.admin_portal_assign_member(actor,target,ids);
      insert into private.staff_portal_access(user_id,portal_role) values(target,requested_role)
        on conflict(user_id) do update set portal_role=excluded.portal_role;
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
  if action='complete' and private.effective_portal_role(target) is distinct from requested_role then
    raise exception 'invitation_role_conflict' using errcode='PT409'; end if;
  return jsonb_build_object('request_id',receipt_id::text,'actor_id',actor,'target_user_id',target,
    'email',email_address,'location_ids',ids,'email_action',email_action,'portal_role',requested_role);
end $$;
revoke all on function public.admin_team_onboarding(text,text,bigint[],uuid,bigint,text)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.admin_team_onboarding(text,text,bigint[],uuid,bigint,text) to authenticated;

commit;
