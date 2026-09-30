begin;

do $$ begin
  if to_regprocedure('private.current_account_access()') is null
    or to_regprocedure('public.admin_portal_data(uuid,text,jsonb)') is null
    or to_regprocedure('public.resolve_refund_request(bigint,text,text,uuid)') is null then
    raise exception 'Canonical admission and reviewed admin/credit prerequisites required';
  end if;
end $$;

-- VOLATILE deliberately obtains a fresh statement snapshot on the post-wait
-- call. The canonical evaluator remains the only session/MFA/lifecycle policy.
create function private.portal_staff_context()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare a jsonb; actor uuid; staff_role text; locations jsonb;
begin
  a:=private.current_account_access();
  if a->>'account_access' is distinct from 'eligible' then
    if a->>'account_state'='pending_deletion' or a->>'reason' is not null then
      raise exception 'account_restricted' using errcode='PT403';
    end if;
    case a->>'next_step'
      when 'verify_email' then raise exception 'verify_email' using errcode='PT403';
      when 'enroll_totp' then raise exception 'enroll_totp' using errcode='PT403';
      when 'challenge_totp' then raise exception 'challenge_totp' using errcode='PT403';
      else raise exception 'account_restricted' using errcode='PT403';
    end case;
  end if;
  actor:=(a->>'subject_id')::uuid;
  select roles::text into staff_role from public.profiles where id=actor;
  if staff_role is null or staff_role not in ('Owner','Admin') then
    raise exception 'staff_required' using errcode='PT403';
  end if;
  select coalesce(jsonb_agg(location_id order by location_id),'[]') into locations
    from (select distinct location_id from public."Location_to_Admin" where user_id=actor) assigned;
  return jsonb_build_object('actor',actor,'role',staff_role,'locations',locations);
end; $$;
revoke all on function private.portal_staff_context() from public,anon,authenticated,service_role;

create function public.admin_portal_request(action text, payload jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare before_context jsonb; after_context jsonb; result jsonb;
begin
  before_context:=private.portal_staff_context();
  if action in ('invite','resend','assignMember','recordDelivery','assertMember') then
    raise exception 'admin_onboarding_disabled' using errcode='PT503';
  end if;
  if action is null or action not in ('identity','locations','machines','rates','maintenance','history',
    'updateMaintenance','credits','team','overview','createLocation','createMachine','deleteMachine',
    'saveRate','saveConfig','removeMember','transactions','audit','assignees','setAvailability','exportRecords','assertCredit') then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  result:=public.admin_portal_data((before_context->>'actor')::uuid,action,payload);
  after_context:=private.portal_staff_context();
  if action='createLocation' then
    -- Creating a location deliberately adds exactly its creator's membership.
    if after_context->>'actor' is distinct from before_context->>'actor'
      or after_context->>'role' is distinct from before_context->>'role'
      or not ((after_context->'locations') @> (before_context->'locations'))
      or not ((after_context->'locations') <@ ((before_context->'locations')||jsonb_build_array((result->>'id')::bigint))) then
      raise exception 'admin_access_changed' using errcode='PT403';
    end if;
  elsif after_context is distinct from before_context then
    raise exception 'admin_access_changed' using errcode='PT403';
  end if;
  return result;
end; $$;
revoke all on function public.admin_portal_request(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_portal_request(text,jsonb) to authenticated;

create function public.admin_resolve_credit(target_refund_id bigint, target_decision text, resolution_note text default '')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare before_context jsonb; result jsonb; actor uuid;
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
  return result;
end; $$;
revoke all on function public.admin_resolve_credit(bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_resolve_credit(bigint,text,text) to authenticated;

-- Actor-taking implementations are internal, not alternate HTTP/RPC APIs.
-- Keep their bodies intact, including the reporting author's current wrapper.
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (p.proname in ('admin_portal_data','admin_portal_data_v1',
      'admin_portal_data_before_reporting','admin_portal_rows','admin_portal_rows_before_reporting',
      'admin_portal_records','admin_portal_topup_evidence','admin_portal_assign_member',
      'admin_portal_bootstrap_owner','resolve_refund_request'))
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f);
    if has_function_privilege('anon',f,'execute') or has_function_privilege('authenticated',f,'execute')
      or has_function_privilege('service_role',f,'execute') then
      raise exception 'Unexpected inherited inner-helper privileges: %',f;
    end if;
  end loop;
end $$;

-- These legacy global-wallet RPCs have no location authorization contract.
-- Fail closed rather than inventing location ownership or rewriting finance.
revoke all on function public.admin_adjust_wallet(uuid,integer,integer,integer,text) from public,anon,authenticated,service_role;
revoke all on function public.admin_record_legal_cash_redemption(uuid,integer,text,text) from public,anon,authenticated,service_role;
revoke all on function public.admin_set_wallet_status(uuid,text,text) from public,anon,authenticated,service_role;

-- The legacy role predicate also participates in direct table policies and
-- privileged wallet RPCs. Replace its role-only check, not financial logic.
create or replace function public.is_admin_or_owner()
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  return private.current_account_access()->>'account_access'='eligible'
    and exists(select 1 from public.profiles where id=auth.uid() and roles::text in ('Owner','Admin'));
exception when sqlstate 'PT401' then return false;
end; $$;

alter function private.portal_record_access(text,jsonb) rename to portal_record_access_before_authorization;
create function private.portal_record_access(kind text, record jsonb)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if exists(select 1 from public.profiles where id=auth.uid() and roles::text in ('Owner','Admin'))
    and not public.is_admin_or_owner() then return false; end if;
  return private.portal_record_access_before_authorization(kind,record);
end; $$;
revoke all on function private.portal_record_access_before_authorization(text,jsonb) from public,anon,authenticated,service_role;
revoke all on function private.portal_record_access(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.portal_record_access(text,jsonb) to authenticated;
-- Policies reference function OIDs, so rebind after renaming the old body.
alter policy portal_transaction_scope on public.transactions using(private.portal_record_access('transaction',to_jsonb(transactions)));
alter policy portal_maintenance_scope on public."Maintenance" using(private.portal_record_access('maintenance',to_jsonb("Maintenance")));
alter policy portal_credit_scope on public."Refunds" using(private.portal_record_access('credit',to_jsonb("Refunds")));

-- Cross-customer staff data goes through the scoped portal, not broad legacy
-- profile/wallet SELECT policies. Customer self-reads retain their other gates.
create policy portal_profile_direct_self on public.profiles as restrictive for select to authenticated using(id=auth.uid());
create policy portal_wallet_direct_self on public.wallet_accounts as restrictive for select to authenticated using(user_id=auth.uid());
create policy portal_load_direct_self on public.wallet_loads as restrictive for select to authenticated using(user_id=auth.uid());
create policy portal_ledger_direct_self on public.wallet_ledger_entries as restrictive for select to authenticated
  using(exists(select 1 from public.wallet_accounts w where w.id=wallet_account_id and w.user_id=auth.uid()));
create policy portal_redemption_direct_self on public.wallet_redemptions as restrictive for select to authenticated using(user_id=auth.uid());
create policy portal_deleted_complaint_no_direct_staff on public.deleted_account_complaints as restrictive for select to authenticated using(false);
create policy portal_config_admission on public.cortina_machine_config as restrictive for select to authenticated using(public.is_admin_or_owner());
create policy portal_rate_admission on public.washer_size_rates as restrictive for select to authenticated using(public.is_admin_or_owner());
create policy portal_membership_direct_self on public."Location_to_Admin" as restrictive for select to authenticated
  using(user_id=auth.uid() and public.is_admin_or_owner());

-- Table-level revokes do not remove legacy column grants.
do $$ declare tbl text; cols text; begin
  foreach tbl in array array['Machines','Locations','washer_size_rates','cortina_machine_config'] loop
    execute format('revoke insert,update,delete on public.%I from public,anon,authenticated',tbl);
    select string_agg(quote_ident(attname),',') into cols from pg_attribute
      where attrelid=format('public.%I',tbl)::regclass and attnum>0 and not attisdropped;
    execute format('revoke insert (%s),update (%s) on public.%I from public,anon,authenticated',cols,cols,tbl);
  end loop;
  foreach tbl in array array['Maintenance','Refunds'] loop
    execute format('revoke update,delete on public.%I from public,anon,authenticated',tbl);
    select string_agg(quote_ident(attname),',') into cols from pg_attribute
      where attrelid=format('public.%I',tbl)::regclass and attnum>0 and not attisdropped;
    execute format('revoke update (%s) on public.%I from public,anon,authenticated',cols,tbl);
  end loop;
end $$;

commit;
