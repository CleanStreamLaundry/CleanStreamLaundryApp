begin;

-- All portal mutations run through an authenticated Edge Function. These RPCs
-- are invoker functions, callable only with the server's service role.
alter table public."Maintenance"
  add column if not exists status text not null default 'open' check (status in ('open','in_progress','resolved')),
  add column if not exists location_id bigint references public."Locations"(id),
  add column if not exists updated_at timestamptz not null default now();

-- Only unambiguous exact address matches are backfilled. Unknown records remain
-- owner-only; legacy mobile clients may continue submitting address strings.
update public."Maintenance" m set location_id = matched.id
from (select min(id) id, "Address" from public."Locations" group by "Address" having count(*) = 1) matched
where m.location_id is null and m.location = matched."Address";

create table public.admin_maintenance_history (
  id bigint generated always as identity primary key,
  maintenance_id text not null,
  actor_id uuid references auth.users(id) on delete set null,
  actor_name text not null,
  from_status text not null,
  to_status text not null,
  note text,
  created_at timestamptz not null default now()
);
create index on public.admin_maintenance_history(maintenance_id, created_at desc);
alter table public.admin_maintenance_history enable row level security;
revoke all on public.admin_maintenance_history from anon, authenticated;
grant all on public.admin_maintenance_history to service_role;
grant usage, select on sequence public.admin_maintenance_history_id_seq to service_role;

create table public.admin_invitations (
  user_id uuid not null references auth.users(id) on delete cascade,
  location_id bigint not null references public."Locations"(id) on delete cascade,
  invited_by uuid not null references auth.users(id),
  invited_at timestamptz not null default now(),
  last_sent_at timestamptz,
  delivery_status text not null default 'pending' check (delivery_status in ('pending','sent','failed')),
  primary key(user_id, location_id)
);
alter table public.admin_invitations enable row level security;
revoke all on public.admin_invitations from anon, authenticated;
grant all on public.admin_invitations to service_role;

-- Role assignments cannot be written by a customer or a compromised browser.
create function public.guard_portal_authority() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') then
    if tg_op = 'INSERT' and new.roles::text is distinct from 'User' then
      raise exception 'Role assignment requires a trusted administrator' using errcode = '42501';
    elsif tg_op = 'UPDATE' and new.roles is distinct from old.roles then
      raise exception 'Role assignment requires a trusted administrator' using errcode = '42501';
    end if;
  end if;
  return new;
end; $$;
create trigger portal_authority_guard before insert or update on public.profiles for each row execute function public.guard_portal_authority();
revoke all on function public.guard_portal_authority() from public, anon, authenticated;
revoke insert, update, delete on public."Location_to_Admin" from anon, authenticated;
-- Management writes now use the verified portal RPC. Public/mobile inventory
-- reads and customer maintenance submissions remain available under their RLS.
revoke insert, update, delete on public."Machines", public."Locations", public.washer_size_rates, public.cortina_machine_config from anon, authenticated;
revoke update, delete on public."Maintenance", public."Refunds" from anon, authenticated;

create function public.portal_transaction_location(record jsonb) returns bigint language sql stable security invoker set search_path = '' as $$
  select m."Location_ID" from public.cortina_vend_sessions s
  join public."Machines" m on m.id = s.machine_id
  where s.id::text = record->>'cortina_vend_session_id' limit 1;
$$;
revoke all on function public.portal_transaction_location(jsonb) from public, anon, authenticated;
grant execute on function public.portal_transaction_location(jsonb) to service_role;

create function public.admin_portal_data(actor uuid, action text, payload jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  actor_role text; actor_name text; ids bigint[]; loc bigint; target uuid;
  items jsonb := '[]'; result jsonb; input jsonb := coalesce(payload->'input','{}');
  f jsonb := coalesce(payload->'filters','{}'); page_number integer; total integer;
  row_data record; existing public."Maintenance"%rowtype;
  next_status text; note text; rate public.washer_size_rates%rowtype;
  config jsonb; enabled boolean; valid_config boolean; machine public."Machines"%rowtype;
  business_today date := (now() at time zone 'America/Indiana/Indianapolis')::date;
  start_time timestamptz; end_time timestamptz;
begin
  select p.roles::text, coalesce(nullif(p.full_name,''),p.email,'Team member') into actor_role, actor_name from public.profiles p where p.id = actor;
  if actor_role is null or actor_role not in ('Admin','Owner') then raise exception 'Owner or Admin access required' using errcode='42501'; end if;
  select coalesce(array_agg(location_id::bigint),'{}') into ids from public."Location_to_Admin" where user_id = actor;
  if action = 'identity' then
    return (select jsonb_build_object('id',p.id,'name',p.full_name,'email',u.email,'role',p.roles) from public.profiles p join auth.users u on u.id=p.id where p.id=actor);
  end if;
  if action = 'locations' then return (select coalesce(jsonb_agg(to_jsonb(l) order by l."Name"),'[]') from public."Locations" l where l.id=any(ids)); end if;
  if action in ('rates','machines') then
    loc := (payload->>'locationId')::bigint;
    if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
    if action='rates' then return (select coalesce(jsonb_agg(to_jsonb(r) order by capacity_kg),'[]') from public.washer_size_rates r where r.location_id=loc); end if;
    return (select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('Price',coalesce(r.price_cents::numeric/100,m."Price"),'cortina_machine_config',to_jsonb(c)) order by m."Name"),'[]') from public."Machines" m left join public.cortina_machine_config c on c.machine_id=m.id left join public.washer_size_rates r on r.id=m.washer_size_rate_id where m."Location_ID"=loc);
  end if;

  if action in ('maintenance','history','updateMaintenance') then
    if action <> 'maintenance' then
      select * into existing from public."Maintenance" where maint_id::text=payload->>'id' for update;
      if not found then raise exception 'Report not found'; end if;
      loc := coalesce(existing.location_id,(select min(id) from public."Locations" where "Address"=existing.location having count(*)=1));
      if not(coalesce(loc=any(ids),false) or (loc is null and actor_role='Owner')) then raise exception 'Report access denied' using errcode='42501'; end if;
      if action='history' then return (select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id desc),'[]') from public.admin_maintenance_history h where h.maintenance_id=existing.maint_id::text); end if;
      next_status := payload->>'status'; note := nullif(btrim(payload->>'note'),'');
      if next_status is null or next_status not in ('open','in_progress','resolved') or length(coalesce(note,''))>4000 then raise exception 'Invalid maintenance update'; end if;
      if (payload->>'expectedUpdatedAt')::timestamptz is distinct from existing.updated_at then raise exception 'This report changed. Close it, refresh the list, and try again.'; end if;
      if next_status=existing.status and note is null then raise exception 'Choose a new status or add a note'; end if;
      update public."Maintenance" set status=next_status,updated_at=clock_timestamp(),location_id=loc where maint_id=existing.maint_id;
      insert into public.admin_maintenance_history(maintenance_id,actor_id,actor_name,from_status,to_status,note) values(existing.maint_id::text,actor,actor_name,existing.status,next_status,note);
      return '{"success":true}';
    end if;
    select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('maint_id',m.maint_id::text,'date',m.created_at) order by m.created_at desc,m.maint_id),'[]') into items from public."Maintenance" m
    where (coalesce(m.location_id,(select min(id) from public."Locations" where "Address"=m.location having count(*)=1))=any(ids)
      or (actor_role='Owner' and coalesce(m.location_id,(select min(id) from public."Locations" where "Address"=m.location having count(*)=1)) is null))
      and (coalesce(f->>'status','unresolved')='all' or (coalesce(f->>'status','unresolved')='unresolved' and m.status<>'resolved') or m.status=f->>'status')
      and (coalesce(f->>'category','')='' or m.category=f->>'category');
  elsif action in ('credits','assertCredit') then
    select coalesce(jsonb_agg(jsonb_build_object('refund_id',r.refund_id,'amount',r.amount,'description',r.description,'date',r.date,'status',r.status,'customer_name',coalesce(p.full_name,'Customer'),'transaction_id',r.transaction_id,'admin_note',r.admin_note,'resolved_at',r.resolved_at,'notification_sent_at',r.notification_sent_at) order by r.date desc,r.refund_id),'[]') into items
    from public."Refunds" r join public.transactions t on t.id=r.transaction_id left join public.profiles p on p.id=r.user_id
    where (public.portal_transaction_location(to_jsonb(t))=any(ids) or (actor_role='Owner' and public.portal_transaction_location(to_jsonb(t)) is null))
      and (action='assertCredit' or coalesce(f->>'status','pending')='all' or r.status::text=coalesce(f->>'status','pending'))
      and (action<>'assertCredit' or r.refund_id::text=payload->>'id');
    if action='assertCredit' then if jsonb_array_length(items)<>1 then raise exception 'Credit request access denied' using errcode='42501'; end if; return '{"success":true}'; end if;
  elsif action='overview' then
    start_time := (business_today-29)::timestamp at time zone 'America/Indiana/Indianapolis'; end_time := (business_today+1)::timestamp at time zone 'America/Indiana/Indianapolis';
    with scoped as (select t.* from public.transactions t where t.created_at>=start_time and t.created_at<end_time and (public.portal_transaction_location(to_jsonb(t))=any(ids) or (actor_role='Owner' and public.portal_transaction_location(to_jsonb(t)) is null))),
    payments as (select * from scoped where description not in ('Loyalty payment on Dryer','Loyalty payment on Washer')),
    daily as (select day::date d,coalesce((select sum(amount) from payments where (created_at at time zone 'America/Indiana/Indianapolis')::date=day::date),0) amount from generate_series((business_today-29)::timestamp,business_today::timestamp,'1 day') day),
    hourly as (select h, (select count(*) from scoped where extract(hour from created_at at time zone 'America/Indiana/Indianapolis')=h) n from generate_series(0,23) h)
    select jsonb_build_object('today',coalesce((select sum(amount) from payments where (created_at at time zone 'America/Indiana/Indianapolis')::date=business_today),0),'total',coalesce((select sum(amount) from payments),0),'daily',(select jsonb_agg(jsonb_build_object('date',d,'amount',amount) order by d) from daily),'hourly',(select jsonb_agg(n order by h) from hourly),'locations',cardinality(ids),'machines',(select count(*) from public."Machines" where "Location_ID"=any(ids)),
      'pendingCredits',(public.admin_portal_data(actor,'credits','{"filters":{"status":"pending"}}')->>'total')::int,
      'openMaintenance',(public.admin_portal_data(actor,'maintenance','{"filters":{"status":"unresolved"}}')->>'total')::int,
      'updatedAt',now(),'financialScope',case when actor_role='Owner' then 'Assigned locations plus legacy transactions without location attribution. Existing revenue inclusion rules retained.' else 'Only transactions reliably linked to your assigned locations.' end) into result;
    return result;
  else
    if actor_role<>'Owner' then raise exception 'Owner access required' using errcode='42501'; end if;
    if action='team' then
      select coalesce(jsonb_agg(jsonb_build_object('user_id',p.id,'name',p.full_name,'email',u.email,'role',p.roles,'location_id',l.id,'location_name',l."Name",'assignment_count',(select count(*) from public."Location_to_Admin" all_assignments where all_assignments.user_id=p.id),'invitation_status',case when u.last_sign_in_at is not null then 'active' when i.delivery_status='failed' then 'failed' when i.last_sent_at is not null then 'invited' else 'pending' end,'invited_at',i.invited_at) order by p.full_name,l."Name"),'[]') into items
      from public."Location_to_Admin" a join public.profiles p on p.id=a.user_id join auth.users u on u.id=p.id join public."Locations" l on l.id=a.location_id left join public.admin_invitations i on i.user_id=a.user_id and i.location_id=a.location_id where a.location_id=any(ids);
    elsif action='createLocation' then
      if nullif(btrim(input->>'Name'),'') is null or nullif(btrim(input->>'Address'),'') is null or (input->>'Latitude')::numeric not between -90 and 90 or (input->>'Longitude')::numeric not between -180 and 180 then raise exception 'Enter a valid location name and address'; end if;
      insert into public."Locations"("Name","Address","Latitude","Longitude") values(btrim(input->>'Name'),btrim(input->>'Address'),(input->>'Latitude')::numeric,(input->>'Longitude')::numeric) returning id into loc;
      insert into public."Location_to_Admin"(user_id,location_id) values(actor,loc);
      return (select to_jsonb(l) from public."Locations" l where id=loc);
    elsif action='createMachine' then
      loc := (input->>'Location_ID')::bigint;
      if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
      if nullif(btrim(input->>'Name'),'') is null or coalesce(input->>'Machine_type','') not in ('Washer','Dryer') then raise exception 'Enter a machine name and type'; end if;
      if input->>'Machine_type'='Washer' then
        select * into rate from public.washer_size_rates where id=(input->>'washer_size_rate_id')::bigint and location_id=loc and is_active and not review_required;
        if not found then raise exception 'Select a reviewed washer rate for this location'; end if;
        if coalesce((input->>'Runtime')::int,0) not between 1 and 240 then raise exception 'Enter a cycle runtime between 1 and 240 minutes'; end if;
      elsif coalesce((input->>'Weight_kg')::numeric,0) not between 1 and 200 then raise exception 'Enter a valid machine capacity'; end if;
      -- jsonb_populate_record respects existing enum column types.
      select * into machine from jsonb_populate_record(null::public."Machines",input||jsonb_build_object('Price',case when input->>'Machine_type'='Washer' then rate.price_cents::numeric/100 else .25 end,'Runtime',case when input->>'Machine_type'='Dryer' then 5 else (input->>'Runtime')::int end,'Weight_kg',case when input->>'Machine_type'='Washer' then rate.capacity_kg else (input->>'Weight_kg')::numeric end,'washer_size_rate_id',case when input->>'Machine_type'='Washer' then rate.id else null end,'Status','idle'));
      insert into public."Machines"("Name","Price","Runtime","Status","Location_ID","Machine_type","Weight_kg",washer_size_rate_id) values(machine."Name",machine."Price",machine."Runtime",machine."Status",machine."Location_ID",machine."Machine_type",machine."Weight_kg",machine.washer_size_rate_id);
      return '{"success":true}';
    elsif action='saveRate' then
      input := payload->'rate'; loc := (input->>'location_id')::bigint;
      if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
      if nullif(btrim(input->>'size_label'),'') is null or coalesce((input->>'capacity_kg')::numeric,0) not between 1 and 200 or trunc((input->>'capacity_kg')::numeric)<>(input->>'capacity_kg')::numeric or coalesce((input->>'price_cents')::int,0) not between 25 and 100000 then raise exception 'Enter a valid size, capacity, and price'; end if;
      if coalesce((input->>'id')::bigint,0)>0 then
        update public.washer_size_rates set size_label=btrim(input->>'size_label'),capacity_kg=(input->>'capacity_kg')::bigint,price_cents=(input->>'price_cents')::int,is_active=(input->>'is_active')::boolean,review_required=false where id=(input->>'id')::bigint and location_id=loc;
        if not found then raise exception 'Rate not found in this location'; end if;
        -- A changed price cannot keep an incomplete Nayax price-array mapping
        -- marked ready. Existing quotes retain their snapshotted selectors.
        update public.cortina_machine_config c set is_enabled=false,review_required=true
        from public."Machines" m where m.id=c.machine_id and m.washer_size_rate_id=(input->>'id')::bigint
          and (not (input->>'is_active')::boolean or (c.product_codes is not null and not (c.product_codes ? (input->>'price_cents'))));
      else insert into public.washer_size_rates(location_id,size_label,capacity_kg,price_cents,is_active,review_required) values(loc,btrim(input->>'size_label'),(input->>'capacity_kg')::bigint,(input->>'price_cents')::int,(input->>'is_active')::boolean,false); end if;
      return '{"success":true}';
    elsif action in ('deleteMachine','saveConfig') then
      config := payload->'config';
      select * into machine from public."Machines" where id=coalesce((config->>'machine_id')::bigint,(payload->>'id')::bigint) for update;
      if not found or not(machine."Location_ID"=any(ids)) then raise exception 'Machine access denied' using errcode='42501'; end if;
      if action='deleteMachine' then
        if exists(select 1 from public.cortina_vend_sessions where machine_id=machine.id) then raise exception 'This machine has payment history. Disable payments instead.'; end if;
        delete from public."Machines" where id=machine.id; return '{"success":true}';
      end if;
      enabled := coalesce((config->>'is_enabled')::boolean,false);
      if enabled and machine."Machine_type"::text='Washer' and not exists(select 1 from public.washer_size_rates where id=machine.washer_size_rate_id and location_id=machine."Location_ID" and is_active and not review_required) then raise exception 'Assign an active, reviewed washer rate before enabling payments'; end if;
      if coalesce(config->>'environment','') not in ('sandbox','production') then raise exception 'Choose a valid payment environment'; end if;
      valid_config := nullif(btrim(config->>'nayax_terminal_id'),'') is not null or nullif(btrim(config->>'nayax_uniqr'),'') is not null;
      if jsonb_typeof(config->'product_codes')='object' then
        for row_data in select price from unnest(case when machine."Machine_type"::text='Dryer' then array[50,100,150,200,300,450] else array[coalesce((select price_cents from public.washer_size_rates where id=machine.washer_size_rate_id),round(machine."Price"*100)::int)] end) price loop
          valid_config := valid_config and coalesce((config->'product_codes'->>row_data.price::text) ~ '^[0-9]+$',false) and coalesce((config->'product_codes'->>row_data.price::text)::numeric between 0 and 32767,false);
        end loop;
      else valid_config := valid_config and (machine."Machine_type"::text='Dryer' or coalesce((config->>'pulse_line_number')::int between 1 and 6,false)); end if;
      if enabled and not valid_config then raise exception 'A terminal identifier and a valid selector for every price are required before enabling payments'; end if;
      insert into public.cortina_machine_config(machine_id,nayax_terminal_id,nayax_uniqr,pulse_line_number,product_codes,environment,is_enabled,review_required)
      values(machine.id,nullif(btrim(config->>'nayax_terminal_id'),''),nullif(btrim(config->>'nayax_uniqr'),''),case when jsonb_typeof(config->'product_codes')='object' then null when machine."Machine_type"::text='Dryer' then 1 else (config->>'pulse_line_number')::int end,nullif(config->'product_codes','null'::jsonb),config->>'environment',enabled,not valid_config)
      on conflict(machine_id) do update set nayax_terminal_id=excluded.nayax_terminal_id,nayax_uniqr=excluded.nayax_uniqr,pulse_line_number=excluded.pulse_line_number,product_codes=excluded.product_codes,environment=excluded.environment,is_enabled=excluded.is_enabled,review_required=excluded.review_required;
      return '{"success":true}';
    elsif action in ('assignMember','removeMember','assertMember') then
      loc := (payload->>'locationId')::bigint; target := (payload->>'userId')::uuid;
      if loc is null or not(loc=any(ids)) then raise exception 'Location access denied' using errcode='42501'; end if;
      perform 1 from public.profiles where id=target for update;
      if not found then raise exception 'Account profile not found'; end if;
      if exists(select 1 from public.profiles where id=target and roles::text='Owner') then raise exception 'Owner accounts cannot be modified through team management' using errcode='42501'; end if;
      if action='assignMember' then
        update public.profiles set roles='Admin' where id=target;
        insert into public."Location_to_Admin"(user_id,location_id) select target,loc where not exists(select 1 from public."Location_to_Admin" where user_id=target and location_id=loc);
        insert into public.admin_invitations(user_id,location_id,invited_by) values(target,loc,actor) on conflict(user_id,location_id) do nothing;
      elsif action='removeMember' then
        delete from public."Location_to_Admin" where user_id=target and location_id=loc;
        delete from public.admin_invitations where user_id=target and location_id=loc;
        if not exists(select 1 from public."Location_to_Admin" where user_id=target) then update public.profiles set roles='User' where id=target and roles::text='Admin'; end if;
      elsif not exists(select 1 from public."Location_to_Admin" where user_id=target and location_id=loc) then raise exception 'Team member not found in this location'; end if;
      return '{"success":true}';
    else raise exception 'Unknown admin action'; end if;
  end if;
  -- Explicit dates are inclusive business dates; no hidden age cutoff.
  page_number := greatest(1,least(coalesce((f->>'page')::int,1),100000));
  if nullif(f->>'from','') is not null and nullif(f->>'to','') is not null and (f->>'from')::date>(f->>'to')::date then raise exception 'Start date must be before the end date'; end if;
  select coalesce(jsonb_agg(value),'[]') into items from jsonb_array_elements(items) where
    (coalesce(f->>'search','')='' or lower(value::text) like '%'||lower(replace(replace(replace(f->>'search','\','\\'),'%','\%'),'_','\_'))||'%')
    and (nullif(f->>'from','') is null or (value->>'date')::timestamptz >= (f->>'from')::date::timestamp at time zone 'America/Indiana/Indianapolis')
    and (nullif(f->>'to','') is null or (value->>'date')::timestamptz < ((f->>'to')::date+1)::timestamp at time zone 'America/Indiana/Indianapolis');
  total := jsonb_array_length(items);
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value),'[]') from (select value from jsonb_array_elements(items) with ordinality order by ordinality limit 20 offset (page_number-1)*20) page),'total',total,'page',page_number,'pageSize',20);
end; $$;
revoke all on function public.admin_portal_data(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.admin_portal_data(uuid,text,jsonb) to service_role;

create function public.admin_portal_assign_member(actor uuid, target uuid, target_locations bigint[])
returns void language plpgsql security invoker set search_path = '' as $$
declare loc bigint; email_address text;
begin
  if cardinality(target_locations) is null or cardinality(target_locations)<1 or cardinality(target_locations)>50 then raise exception 'Choose at least one location'; end if;
  if not exists(select 1 from public.profiles where id=actor and roles::text='Owner') then raise exception 'Owner access required' using errcode='42501'; end if;
  if exists(select 1 from unnest(target_locations) l where not exists(select 1 from public."Location_to_Admin" where user_id=actor and location_id=l)) then raise exception 'Location access denied' using errcode='42501'; end if;
  select email into email_address from auth.users where id=target;
  if email_address is null then raise exception 'Auth account not found'; end if;
  insert into public.profiles(id,email,roles) values(target,email_address,'User') on conflict(id) do nothing;
  foreach loc in array target_locations loop
    perform public.admin_portal_data(actor,'assignMember',jsonb_build_object('userId',target,'locationId',loc));
  end loop;
end; $$;
revoke all on function public.admin_portal_assign_member(uuid,uuid,bigint[]) from public, anon, authenticated;
grant execute on function public.admin_portal_assign_member(uuid,uuid,bigint[]) to service_role;

-- Operator-only bootstrap; there is deliberately no public HTTP route for this.
create function public.admin_portal_bootstrap_owner(target uuid, target_locations bigint[])
returns void language plpgsql security invoker set search_path = '' as $$
declare email_address text; loc bigint;
begin
  perform pg_advisory_xact_lock(814716290);
  if exists(select 1 from public.profiles where roles::text='Owner' and id<>target) then raise exception 'An owner already exists. Use the existing owner account or an audited administrator recovery process.'; end if;
  select email into email_address from auth.users where id=target;
  if email_address is null then raise exception 'Auth account not found'; end if;
  if exists(select 1 from unnest(target_locations) l where not exists(select 1 from public."Locations" where id=l)) then raise exception 'Unknown location ID'; end if;
  insert into public.profiles(id,email,roles) values(target,email_address,'Owner') on conflict(id) do update set roles='Owner';
  foreach loc in array coalesce(target_locations,'{}') loop
    insert into public."Location_to_Admin"(user_id,location_id) select target,loc where not exists(select 1 from public."Location_to_Admin" where user_id=target and location_id=loc);
  end loop;
end; $$;
revoke all on function public.admin_portal_bootstrap_owner(uuid,bigint[]) from public, anon, authenticated;
grant execute on function public.admin_portal_bootstrap_owner(uuid,bigint[]) to service_role;

-- Restrictive policies also constrain older clients/endpoints that still use
-- broad admin SELECT policies. Customer access to their own records remains.
create schema if not exists private;
grant usage on schema private to authenticated;
create function private.portal_record_access(kind text, record jsonb)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := auth.uid(); viewer_role text; loc bigint; payment jsonb;
begin
  if viewer is null then return false; end if;
  if record->>'user_id'=viewer::text then return true; end if;
  select roles::text into viewer_role from public.profiles where id=viewer;
  if viewer_role is null or viewer_role not in ('Owner','Admin') then return false; end if;
  if kind='maintenance' then
    loc := coalesce((record->>'location_id')::bigint,(select min(id) from public."Locations" where "Address"=record->>'location' having count(*)=1));
  elsif kind='credit' then
    select to_jsonb(t) into payment from public.transactions t where t.id::text=record->>'transaction_id';
    loc := public.portal_transaction_location(payment);
  elsif kind='transaction' then loc := public.portal_transaction_location(record);
  else return false;
  end if;
  return (loc is null and viewer_role='Owner') or exists(select 1 from public."Location_to_Admin" where user_id=viewer and location_id=loc);
end; $$;
revoke all on function private.portal_record_access(text,jsonb) from public,anon;
grant execute on function private.portal_record_access(text,jsonb) to authenticated;
alter table public.transactions enable row level security;
alter table public."Maintenance" enable row level security;
alter table public."Refunds" enable row level security;
create policy portal_transaction_scope on public.transactions as restrictive for select to authenticated using(private.portal_record_access('transaction',to_jsonb(transactions)));
create policy portal_maintenance_scope on public."Maintenance" as restrictive for select to authenticated using(private.portal_record_access('maintenance',to_jsonb("Maintenance")));
create policy portal_credit_scope on public."Refunds" as restrictive for select to authenticated using(private.portal_record_access('credit',to_jsonb("Refunds")));

-- Apply the same authorization inside the existing atomic credit transaction.
-- A rejection here rolls back any ledger entry made earlier in that transaction.
create function public.guard_portal_credit_resolution() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.status is distinct from old.status and new.status::text in ('approved','denied') then
    if current_user in ('anon','authenticated') or new.resolved_by is null then raise exception 'Use the authorized credit resolution service' using errcode='42501'; end if;
    perform public.admin_portal_data(new.resolved_by,'assertCredit',jsonb_build_object('id',new.refund_id));
  end if;
  return new;
end; $$;
create trigger portal_credit_resolution_scope before update on public."Refunds" for each row execute function public.guard_portal_credit_resolution();
revoke all on function public.guard_portal_credit_resolution() from public,anon,authenticated;
grant execute on function public.guard_portal_credit_resolution() to service_role;

commit;
