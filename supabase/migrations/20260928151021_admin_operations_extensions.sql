begin;

alter table public."Maintenance"
  add column priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  add column assigned_to uuid references auth.users(id) on delete set null,
  add column due_date date;
alter table public.admin_maintenance_history add column changes jsonb not null default '{}';
create index portal_maintenance_assignment_idx on public."Maintenance"(assigned_to, status, due_date);
create index portal_maintenance_location_idx on public."Maintenance"(location_id, created_at desc);

-- Availability is independent of device status and payment configuration.
alter table public."Machines"
  add column is_out_of_service boolean not null default false,
  add column service_reason text,
  add column service_updated_at timestamptz not null default now(),
  add column service_updated_by uuid;

create table public.admin_audit_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default clock_timestamp(),
  actor_id uuid,
  actor_name text not null,
  entity text not null,
  entity_id text not null,
  operation text not null,
  location_ids bigint[] not null default '{}',
  before_values jsonb,
  after_values jsonb
);
create index admin_audit_date_idx on public.admin_audit_events(created_at desc, id desc);
create index admin_audit_locations_idx on public.admin_audit_events using gin(location_ids);
alter table public.admin_audit_events enable row level security;
revoke all on public.admin_audit_events from public, anon, authenticated, service_role;
grant select, insert on public.admin_audit_events to service_role;
grant usage, select on sequence public.admin_audit_events_id_seq to service_role;

create function private.portal_audit_immutable() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  -- Auth deletion may clear the optional actor reference. Keep the immutable
  -- name snapshot and every business field while allowing that FK cleanup.
  if tg_table_name='admin_maintenance_history' and tg_op='UPDATE'
    and old.actor_id is not null and new.actor_id is null
    and (to_jsonb(old)-'actor_id')=(to_jsonb(new)-'actor_id')
    and not exists(select 1 from auth.users where id=old.actor_id) then return new; end if;
  raise exception 'Audit history cannot be edited or deleted';
end; $$;
create trigger portal_audit_immutable before update or delete on public.admin_audit_events
  for each row execute function private.portal_audit_immutable();
create trigger portal_maintenance_history_immutable before update or delete on public.admin_maintenance_history
  for each row execute function private.portal_audit_immutable();
revoke update,delete,truncate on public.admin_maintenance_history from service_role;

-- Older customer clients keep submitting the same report shape. Management
-- fields always start with server defaults, even if a browser supplies them.
create function private.portal_new_report() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if current_user in ('anon','authenticated') then
    new.status:='open'; new.priority:='normal'; new.assigned_to:=null; new.due_date:=null;
    new.updated_at:=now();
  end if;
  return new;
end; $$;
create trigger portal_new_report before insert on public."Maintenance"
  for each row execute function private.portal_new_report();
revoke all on function private.portal_new_report() from public,anon,authenticated;

-- Snapshots deliberately omit access tokens, credentials, balances, and raw
-- payment-provider payloads. Actor context can only accompany server writes.
create function private.portal_capture_audit() returns trigger
language plpgsql security invoker set search_path='' as $$
declare
  prior jsonb; next_value jsonb; subject jsonb; keys text[];
  event_entity text; event_id text; places bigint[] := '{}';
  who uuid := nullif(current_setting('cleanstream.portal_actor',true),'')::uuid;
  who_name text;
begin
  prior := case when tg_op='INSERT' then null else to_jsonb(old) end;
  next_value := case when tg_op='DELETE' then null else to_jsonb(new) end;
  subject := coalesce(next_value,prior);
  case tg_table_name
    when 'Machines' then
      event_entity := 'machine'; event_id := subject->>'id';
      places := array[(subject->>'Location_ID')::bigint];
      keys := array['Name','Location_ID','Machine_type','Weight_kg','Price','Runtime','washer_size_rate_id','is_out_of_service','service_reason'];
    when 'Locations' then
      event_entity := 'location'; event_id := subject->>'id'; places := array[event_id::bigint];
      keys := array['Name','Address','Latitude','Longitude'];
    when 'washer_size_rates' then
      event_entity := 'washer_rate'; event_id := subject->>'id'; places := array[(subject->>'location_id')::bigint];
      keys := array['size_label','capacity_kg','price_cents','is_active','review_required'];
    when 'cortina_machine_config' then
      event_entity := 'payment_config'; event_id := subject->>'machine_id';
      select array["Location_ID"] into places from public."Machines" where id=event_id::bigint;
      keys := array['nayax_terminal_id','nayax_uniqr','pulse_line_number','product_codes','environment','is_enabled','review_required'];
    when 'Location_to_Admin' then
      event_entity := 'membership'; event_id := (subject->>'user_id')||':'||(subject->>'location_id');
      places := array[(subject->>'location_id')::bigint]; keys := array['user_id','location_id'];
    when 'admin_invitations' then
      event_entity := 'invitation'; event_id := (subject->>'user_id')||':'||(subject->>'location_id');
      places := array[(subject->>'location_id')::bigint];
      keys := array['user_id','location_id','delivery_status','last_sent_at'];
    when 'Maintenance' then
      event_entity := 'maintenance'; event_id := subject->>'maint_id';
      select array[coalesce((subject->>'location_id')::bigint,
        (select min(id) from public."Locations" where "Address"=subject->>'location' having count(*)=1))] into places;
      keys := array['status','priority','assigned_to','due_date','location_id'];
    when 'Refunds' then
      event_entity := 'loyalty_credit'; event_id := subject->>'refund_id';
      who := coalesce(who,(subject->>'resolved_by')::uuid);
      select array[public.portal_transaction_location(to_jsonb(t))] into places
        from public.transactions t where t.id::text=subject->>'transaction_id';
      keys := array['status','amount','admin_note','resolved_at','notification_sent_at'];
    when 'profiles' then
      if prior->'roles' is not distinct from next_value->'roles' then return null; end if;
      event_entity := 'role'; event_id := subject->>'id'; keys := array['roles'];
      select array_agg(location_id::bigint) into places from public."Location_to_Admin" where user_id=event_id::uuid;
    else return null;
  end case;
  if prior is not null then
    select coalesce(jsonb_object_agg(key,value),'{}') into prior from jsonb_each(prior) where key=any(keys);
  end if;
  if next_value is not null then
    select coalesce(jsonb_object_agg(key,value),'{}') into next_value from jsonb_each(next_value) where key=any(keys);
  end if;
  if prior is not distinct from next_value then return null; end if;
  select coalesce(nullif(full_name,''),email) into who_name from public.profiles where id=who;
  insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,location_ids,before_values,after_values)
    values(who,coalesce(who_name,'System / trusted operator'),event_entity,event_id,lower(tg_op),
      coalesce(array_remove(places,null),'{}'),prior,next_value);
  return null;
end; $$;

create trigger portal_audit_machine after insert or update or delete on public."Machines" for each row execute function private.portal_capture_audit();
create trigger portal_audit_location after insert or update or delete on public."Locations" for each row execute function private.portal_capture_audit();
create trigger portal_audit_rate after insert or update or delete on public.washer_size_rates for each row execute function private.portal_capture_audit();
create trigger portal_audit_config after insert or update or delete on public.cortina_machine_config for each row execute function private.portal_capture_audit();
create trigger portal_audit_membership after insert or update or delete on public."Location_to_Admin" for each row execute function private.portal_capture_audit();
create trigger portal_audit_invitation after insert or update or delete on public.admin_invitations for each row execute function private.portal_capture_audit();
create trigger portal_audit_maintenance after update on public."Maintenance" for each row execute function private.portal_capture_audit();
create trigger portal_audit_credit after update on public."Refunds" for each row execute function private.portal_capture_audit();
create trigger portal_audit_role after update on public.profiles for each row execute function private.portal_capture_audit();
revoke all on function private.portal_capture_audit(), private.portal_audit_immutable() from public, anon, authenticated;
grant execute on function private.portal_capture_audit() to service_role;

-- Serialize new session creation against an availability change. Updates to
-- existing sessions remain available for callbacks and compensation.
create function private.portal_guard_new_vend() returns trigger
language plpgsql security invoker set search_path='' as $$
declare unavailable boolean;
begin
  select is_out_of_service into unavailable from public."Machines" where id=new.machine_id for share;
  if not found or unavailable then
    raise exception 'This machine is out of service. Choose another machine.' using errcode='55000';
  end if;
  return new;
end; $$;
create trigger portal_guard_new_vend before insert on public.cortina_vend_sessions
  for each row execute function private.portal_guard_new_vend();
revoke all on function private.portal_guard_new_vend() from public, anon, authenticated;
grant execute on function private.portal_guard_new_vend() to service_role;

-- A single scoped record source powers both queues and exports. Provider
-- secrets and raw event payloads are never included in these records.
create function public.admin_portal_rows(actor uuid, dataset text)
returns setof jsonb language plpgsql security invoker set search_path='' as $$
declare actor_role text; ids bigint[];
begin
  select roles::text into actor_role from public.profiles where id=actor;
  if actor_role is null or actor_role not in ('Owner','Admin') then
    raise exception 'Owner or Admin access required' using errcode='42501';
  end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id=actor;
  if dataset in ('audit','team') and actor_role<>'Owner' then
    raise exception 'Owner access required' using errcode='42501';
  end if;

  if dataset='transactions' then
    return query
    -- Scan optional legacy links once, rather than rescanning the entire
    -- ledger for every payment attempt. Older schemas may lack this column.
    with ledger as materialized (
      select to_jsonb(t)->>'cortina_vend_session_id' session_id,min(t.id)::text id
      from public.transactions t
      where to_jsonb(t)->>'cortina_vend_session_id' is not null
      group by to_jsonb(t)->>'cortina_vend_session_id'
    )
    select jsonb_build_object(
      'id','vend:'||s.id,'date',s.created_at,'source','machine_payment',
      'customer_name',coalesce(nullif(p.full_name,''),case when s.user_id is null then 'Guest' else 'Customer' end),
      'customer_email',p.email,'location_id',m."Location_ID",'location_name',l."Name",
      'machine_id',m.id,'machine_name',m."Name",'amount',s.amount_cents::numeric/100,'currency',s.currency,
      'payment_method',s.payment_method,'channel',s.channel,'status',s.status,
      'payment_status',case when s.status='refunded' then 'refunded' when s.status='voided' then 'voided'
        when s.status='payment_pending' then 'pending'
        when s.status in ('paid','starting','awaiting_sale','approved','started') then 'received' else 'unconfirmed' end,
      'reference',s.transaction_id,'payment_reference',s.stripe_payment_intent_id,
      'checkout_reference',s.stripe_checkout_session_id,'refund_reference',s.stripe_refund_id,
      'ledger_id',ledger.id,'failure_message',s.failure_message,'completed_at',s.completed_at,
      'description',case when m."Machine_type"::text='Dryer' then 'Dryer payment' else 'Washer payment' end)
    from public.cortina_vend_sessions s
    join public."Machines" m on m.id=s.machine_id
    join public."Locations" l on l.id=m."Location_ID"
    left join public.profiles p on p.id=s.user_id
    left join ledger on ledger.session_id=s.id::text
    where m."Location_ID"=any(ids)
    union all
    select jsonb_build_object(
      'id','legacy:'||t.id,'date',t.created_at,'source','legacy',
      'customer_name',coalesce(nullif(p.full_name,''),'Customer'),'customer_email',p.email,
      'location_id',null,'location_name',null,'machine_id',null,'machine_name',null,
      'amount',t.amount,'currency','USD','payment_method','unattributed','channel',null,
      'status','recorded','payment_status','recorded','reference',t.id::text,
      'payment_reference',null,'checkout_reference',null,'refund_reference',null,
      'ledger_id',t.id::text,'failure_message',null,'completed_at',null,'description',t.description)
    from public.transactions t left join public.profiles p on p.id=t.user_id
    where actor_role='Owner' and not exists(select 1 from public.cortina_vend_sessions s
      where s.id::text=to_jsonb(t)->>'cortina_vend_session_id');

  elsif dataset='maintenance' then
    return query
    select to_jsonb(m)||jsonb_build_object('id',m.maint_id::text,'maint_id',m.maint_id::text,
      'date',m.created_at,'location_id',mapping.location_id,'assigned_name',coalesce(nullif(p.full_name,''),p.email),
      'overdue',m.status<>'resolved' and m.due_date<(now() at time zone 'America/Indiana/Indianapolis')::date)
    from public."Maintenance" m
    left join public.profiles p on p.id=m.assigned_to
    cross join lateral (select coalesce(m.location_id,(select min(id) from public."Locations"
      where "Address"=m.location having count(*)=1)) location_id) mapping
    where mapping.location_id=any(ids) or (mapping.location_id is null and actor_role='Owner');

  elsif dataset='credits' then
    return query
    select jsonb_build_object('id',r.refund_id::text,'refund_id',r.refund_id,'amount',r.amount,
      'description',r.description,'date',r.date,'status',r.status,'customer_name',coalesce(p.full_name,'Customer'),
      'transaction_id',r.transaction_id,'admin_note',r.admin_note,'resolved_at',r.resolved_at,
      'notification_sent_at',r.notification_sent_at,'location_id',mapping.location_id)
    from public."Refunds" r join public.transactions t on t.id=r.transaction_id
    left join public.profiles p on p.id=r.user_id
    cross join lateral (select public.portal_transaction_location(to_jsonb(t)) location_id) mapping
    where mapping.location_id=any(ids) or (mapping.location_id is null and actor_role='Owner');

  elsif dataset='audit' then
    return query select to_jsonb(a)||jsonb_build_object('id',a.id::text,'date',a.created_at)
    from public.admin_audit_events a where a.location_ids && ids
      or (cardinality(a.location_ids)=0 and (a.actor_id=actor or (a.entity='role' and a.entity_id=actor::text) or a.entity in ('maintenance','loyalty_credit')));

  elsif dataset='team' then
    return query select jsonb_build_object('id',p.id||':'||l.id,'user_id',p.id,'name',p.full_name,
      'email',u.email,'role',p.roles,'location_id',l.id,'location_name',l."Name",
      'assignment_count',(select count(*) from public."Location_to_Admin" all_assignments where all_assignments.user_id=p.id),
      'invitation_status',case when u.last_sign_in_at is not null then 'active' when i.delivery_status='failed' then 'failed'
        when i.last_sent_at is not null then 'invited' else 'pending' end,'invited_at',i.invited_at,'date',i.invited_at)
    from public."Location_to_Admin" a join public.profiles p on p.id=a.user_id join auth.users u on u.id=p.id
    join public."Locations" l on l.id=a.location_id left join public.admin_invitations i on i.user_id=a.user_id and i.location_id=a.location_id
    where a.location_id=any(ids);

  elsif dataset='machines' then
    return query select jsonb_build_object('id',m.id::text,'name',m."Name",'location_id',m."Location_ID",'location_name',l."Name",
      'machine_type',m."Machine_type",'status',m."Status",'capacity_kg',m."Weight_kg",'price',coalesce(r.price_cents::numeric/100,m."Price"),
      'is_out_of_service',m.is_out_of_service,'service_reason',m.service_reason,'service_updated_at',m.service_updated_at,
      'payment_enabled',coalesce(c.is_enabled,false),'payment_review_required',coalesce(c.review_required,true),'environment',c.environment)
    from public."Machines" m join public."Locations" l on l.id=m."Location_ID"
    left join public.washer_size_rates r on r.id=m.washer_size_rate_id
    left join public.cortina_machine_config c on c.machine_id=m.id where m."Location_ID"=any(ids);
  else raise exception 'Unknown export dataset';
  end if;
end; $$;
revoke all on function public.admin_portal_rows(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_portal_rows(uuid,text) to service_role;

create function public.admin_portal_records(actor uuid, dataset text, filters jsonb, exporting boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare f jsonb:=coalesce(filters,'{}'); result jsonb; desired_status text;
  page_number integer:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
begin
  if nullif(f->>'from','') is not null and nullif(f->>'to','') is not null and (f->>'from')::date>(f->>'to')::date then
    raise exception 'Start date must be before the end date';
  end if;
  desired_status:=coalesce(nullif(f->>'status',''),case dataset when 'maintenance' then 'unresolved' when 'credits' then 'pending' else 'all' end);
  with filtered as materialized (
    select value from public.admin_portal_rows(actor,dataset) value
    where (coalesce(f->>'search','')='' or position(lower(f->>'search') in lower(
      case when dataset='machines' then value->>'name' else (value-'image_data')::text end))>0)
      and (desired_status='all' or (dataset='maintenance' and desired_status='unresolved' and value->>'status'<>'resolved') or value->>'status'=desired_status)
      and (nullif(f->>'locationId','') is null or value->>'location_id'=f->>'locationId'
        or (dataset='audit' and value->'location_ids' @> jsonb_build_array((f->>'locationId')::bigint)))
      and (nullif(f->>'from','') is null or (value->>'date')::timestamptz >= (f->>'from')::date::timestamp at time zone 'America/Indiana/Indianapolis')
      and (nullif(f->>'to','') is null or (value->>'date')::timestamptz < ((f->>'to')::date+1)::timestamp at time zone 'America/Indiana/Indianapolis')
      and (coalesce(f->>'category','')='' or value->>'category'=f->>'category')
      and (coalesce(f->>'priority','')='' or value->>'priority'=f->>'priority')
      and (coalesce(f->>'entity','')='' or value->>'entity'=f->>'entity')
      and (coalesce(f->>'paymentStatus','')='' or value->>'payment_status'=f->>'paymentStatus')
      and (coalesce(f->>'machineType','')='' or value->>'machine_type'=f->>'machineType')
      and (coalesce(f->>'availability','')='' or (value->>'is_out_of_service')::boolean=(f->>'availability'='out_of_service'))
      and (not coalesce((f->>'overdue')::boolean,false) or coalesce((value->>'overdue')::boolean,false))
      and (coalesce(f->>'assignedTo','')='' or (f->>'assignedTo'='unassigned' and value->>'assigned_to' is null)
        or value->>'assigned_to'=case when f->>'assignedTo'='me' then actor::text else f->>'assignedTo' end)
  ), page as (
    select value from filtered order by (value->>'date')::timestamptz desc nulls last,value->>'id' desc
    limit case when exporting then 5001 else 20 end offset case when exporting then 0 else (page_number-1)*20 end
  )
  select jsonb_build_object('items',(select coalesce(jsonb_agg(value),'[]') from page),
    'total',(select count(*) from filtered),'page',page_number,'pageSize',20,'exportedAt',now()) into result;
  if exporting and (result->>'total')::int>5000 then
    raise exception 'More than 5,000 records match. Narrow your date range or filters before exporting.';
  end if;
  return result;
end; $$;
revoke all on function public.admin_portal_records(uuid,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.admin_portal_records(uuid,text,jsonb,boolean) to service_role;

alter function public.admin_portal_data(uuid,text,jsonb) rename to admin_portal_data_v1;
create function public.admin_portal_data(actor uuid, action text, payload jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  actor_role text; actor_name text; ids bigint[]; loc bigint; target uuid;
  report public."Maintenance"%rowtype; machine public."Machines"%rowtype;
  next_status text; next_priority text; next_assignee uuid; next_due date; note text;
  before_details jsonb; after_details jsonb; new_unavailable boolean; result jsonb;
begin
  select roles::text,coalesce(nullif(full_name,''),email,'Team member') into actor_role,actor_name
    from public.profiles where id=actor;
  if actor_role is null or actor_role not in ('Owner','Admin') then
    raise exception 'Owner or Admin access required' using errcode='42501';
  end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id=actor;
  perform set_config('cleanstream.portal_actor',actor::text,true);

  if action in ('transactions','audit','maintenance','credits','team') then
    return public.admin_portal_records(actor,action,payload->'filters');
  elsif action='exportRecords' then
    if coalesce(payload->>'dataset','') not in ('transactions','audit','maintenance','credits','team','machines') then
      raise exception 'Unknown export dataset';
    end if;
    result:=public.admin_portal_records(actor,payload->>'dataset',payload->'filters',true);
    return jsonb_build_object('rows',result->'items','total',result->'total','exportedAt',result->'exportedAt');
  elsif action in ('assignees','updateMaintenance') then
    -- The original permission check and row lock also protect legacy address mappings.
    perform public.admin_portal_data_v1(actor,'history',payload);
    select * into report from public."Maintenance" where maint_id::text=payload->>'id' for update;
    loc:=coalesce(report.location_id,(select min(id) from public."Locations" where "Address"=report.location having count(*)=1));
    if action='assignees' then
      return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.full_name,''),p.email),'email',p.email) order by p.full_name),'[]')
        from public.profiles p where p.roles::text in ('Owner','Admin')
          and ((loc is null and p.id=actor and p.roles::text='Owner')
            or exists(select 1 from public."Location_to_Admin" where user_id=p.id and location_id=loc)));
    end if;
    next_status:=payload->>'status'; note:=nullif(btrim(payload->>'note'),'');
    next_priority:=coalesce(payload->>'priority',report.priority);
    next_assignee:=case when payload ? 'assignedTo' then nullif(payload->>'assignedTo','')::uuid else report.assigned_to end;
    next_due:=case when payload ? 'dueDate' then nullif(payload->>'dueDate','')::date else report.due_date end;
    if next_status is null or next_status not in ('open','in_progress','resolved')
      or next_priority not in ('low','normal','high','urgent') or length(coalesce(note,''))>4000 then
      raise exception 'Invalid maintenance update';
    end if;
    if next_assignee is not null and not exists(select 1 from public.profiles p
      where p.id=next_assignee and p.roles::text in ('Owner','Admin')
        and ((loc is null and p.id=actor and p.roles::text='Owner') or exists(
          select 1 from public."Location_to_Admin" where user_id=p.id and location_id=loc))) then
      raise exception 'Assign this report to a team member with access to its location';
    end if;
    if (payload->>'expectedUpdatedAt')::timestamptz is distinct from report.updated_at then
      raise exception 'This report changed. Close it, refresh the list, and try again.';
    end if;
    if next_status=report.status and next_priority=report.priority and next_assignee is not distinct from report.assigned_to
      and next_due is not distinct from report.due_date and note is null then raise exception 'Choose a change or add a note'; end if;
    before_details:=jsonb_build_object('priority',report.priority,'assignee',coalesce((select coalesce(nullif(full_name,''),email) from public.profiles where id=report.assigned_to),'Unassigned'),'due_date',report.due_date);
    after_details:=jsonb_build_object('priority',next_priority,'assignee',coalesce((select coalesce(nullif(full_name,''),email) from public.profiles where id=next_assignee),'Unassigned'),'due_date',next_due);
    update public."Maintenance" set status=next_status,priority=next_priority,assigned_to=next_assignee,due_date=next_due,
      updated_at=clock_timestamp(),location_id=loc where maint_id=report.maint_id;
    insert into public.admin_maintenance_history(maintenance_id,actor_id,actor_name,from_status,to_status,note,changes)
      values(report.maint_id::text,actor,actor_name,report.status,next_status,note,jsonb_build_object('before',before_details,'after',after_details));
    return '{"success":true}';

  elsif action='setAvailability' then
    if actor_role<>'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
    select * into machine from public."Machines" where id=(payload->>'id')::bigint for update;
    if not found or not(machine."Location_ID"=any(ids)) then raise exception 'Machine access denied' using errcode='42501'; end if;
    if jsonb_typeof(payload->'outOfService') is distinct from 'boolean' then raise exception 'Choose a valid availability'; end if;
    new_unavailable:=(payload->>'outOfService')::boolean; note:=nullif(btrim(payload->>'reason'),'');
    if new_unavailable and note is null then raise exception 'Enter the reason this machine is out of service'; end if;
    if length(coalesce(note,''))>1000 then raise exception 'Keep the reason under 1,000 characters'; end if;
    if (payload->>'expectedUpdatedAt')::timestamptz is distinct from machine.service_updated_at then
      raise exception 'Machine availability changed. Refresh and try again.';
    end if;
    if new_unavailable=machine.is_out_of_service then raise exception 'This availability is already set'; end if;
    update public."Machines" set is_out_of_service=new_unavailable,service_reason=note,
      service_updated_at=clock_timestamp(),service_updated_by=actor where id=machine.id;
    return '{"success":true}';

  elsif action='recordDelivery' then
    -- Internal action used by the invitation service, excluded from the HTTP allowlist.
    if actor_role<>'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
    target:=(payload->>'userId')::uuid;
    for loc in select value::bigint from jsonb_array_elements_text(payload->'locationIds') loop
      perform public.admin_portal_data_v1(actor,'assertMember',jsonb_build_object('userId',target,'locationId',loc));
      update public.admin_invitations set delivery_status=case when (payload->>'sent')::boolean then 'sent' else 'failed' end,
        last_sent_at=case when (payload->>'sent')::boolean then now() else last_sent_at end
        where user_id=target and location_id=loc;
    end loop;
    return '{"success":true}';
  end if;
  return public.admin_portal_data_v1(actor,action,payload);
end; $$;
revoke all on function public.admin_portal_data(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_portal_data(uuid,text,jsonb) to service_role;
grant usage on schema private to service_role;

commit;
