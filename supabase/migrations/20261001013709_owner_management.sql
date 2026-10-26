begin;

-- Existing roles, canonical staff admission and immutable audit only. No users,
-- memberships, balances or lifecycle rows are seeded or backfilled.
create function private.owner_target_restriction(target uuid)
returns text language plpgsql volatile security definer set search_path='' as $$
declare u auth.users%rowtype; r private.customer_mfa_recovery%rowtype; target_role text;
begin
  select * into u from auth.users where id=target;
  if not found or u.is_anonymous is distinct from false or u.deleted_at is not null
    or u.banned_until>clock_timestamp() then return 'account_restricted'; end if;
  select roles::text into target_role from public.profiles where id=target;
  if coalesce(target_role,'') not in ('User','Admin','Owner') then return 'role_unavailable'; end if;
  if exists(select 1 from private.account_lifecycle where user_id=target and restored_at is null)
    then return 'pending_deletion'; end if;
  if u.email_confirmed_at is null then return 'email_unverified'; end if;
  select * into r from private.customer_mfa_recovery where user_id=target;
  if exists(select 1 from auth.mfa_factors f where f.user_id=target and
    (coalesce(f.status::text,'') not in ('unverified','verified') or
      (f.status::text='verified' and f.factor_type::text is distinct from 'totp')))
    then return 'unsupported_factor'; end if;
  if r.user_id is not null and exists(select 1 from auth.mfa_factors f
    where f.user_id=target and f.id=any(r.factor_ids)) then return 'mfa_recovery_required'; end if;
  if not exists(select 1 from auth.mfa_factors f where f.user_id=target
    and f.status::text='verified' and f.factor_type::text='totp'
    and (r.user_id is null or f.created_at>r.started_at)) then
    return case when r.user_id is null then 'mfa_required' else 'mfa_recovery_required' end;
  end if;
  return null;
end $$;
revoke all on function private.owner_target_restriction(uuid) from public,anon,authenticated,service_role;

create function private.require_other_owner(target uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles p where p.roles::text='Owner' and p.id<>target
    and private.owner_target_restriction(p.id) is null) then
    raise exception 'owner_last_required' using errcode='PT409';
  end if;
end $$;
revoke all on function private.require_other_owner(uuid) from public,anon,authenticated,service_role;

-- The RPC takes the existing bootstrap advisory lock BEFORE Auth/profile locks.
-- A defensive trigger never waits for it while already holding a profile tuple:
-- trusted callers with another lock order must roll back and explicitly recheck.
create function private.guard_last_owner()
returns trigger language plpgsql volatile security definer set search_path='' as $$
begin
  if old.roles::text='Owner' and (tg_op='DELETE' or new.roles is distinct from old.roles) then
    if not pg_try_advisory_xact_lock(814716290) then
      raise exception 'owner_state_changed' using errcode='PT409';
    end if;
    perform private.require_other_owner(old.id);
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.guard_last_owner() from public,anon,authenticated,service_role;
create trigger owner_role_removal_guard before update of roles or delete on public.profiles
  for each row execute function private.guard_last_owner();

create unique index admin_owner_request_receipt on public.admin_audit_events(entity_id)
  where entity='owner_management' and operation='role_change';

create function public.admin_owner_management(action text,payload jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  ctx jsonb; actor uuid; target uuid; request_id uuid; desired boolean; expected text; note text;
  prior_role text; next_role text; canonical jsonb; result jsonb; receipt public.admin_audit_events%rowtype;
  old_actor text; query_text text; page_number integer; total bigint; items jsonb; owner_count bigint;
begin
  ctx:=private.portal_staff_context(); actor:=(ctx->>'actor')::uuid;
  if ctx->>'role' is distinct from 'Owner' then raise exception 'owner_required' using errcode='PT403'; end if;
  if jsonb_typeof(payload) is distinct from 'object' then raise exception 'invalid_request' using errcode='22023'; end if;
  if action='ownerAccounts' then
    query_text:=btrim(coalesce(payload->>'query','')); page_number:=coalesce((payload->>'page')::integer,1);
    if length(query_text)>254 or page_number<1 or page_number>100000 then
      raise exception 'invalid_request' using errcode='22023'; end if;
    select count(*) into owner_count from public.profiles p where p.roles::text='Owner'
      and private.owner_target_restriction(p.id) is null;
    select count(*) into total from public.profiles p join auth.users u on u.id=p.id
      where (query_text='' and p.roles::text='Owner') or
        (query_text<>'' and (p.id::text=lower(query_text) or lower(u.email)=lower(query_text)));
    select coalesce(jsonb_agg(v.item order by v.id),'[]') into items from (
      select p.id,jsonb_build_object('userId',p.id,'name',p.full_name,'email',u.email,'role',p.roles,
        'locationIds',coalesce((select jsonb_agg(distinct m.location_id order by m.location_id)
          from public."Location_to_Admin" m where m.user_id=p.id and m.location_id is not null),'[]'),
        'ownerEligible',private.owner_target_restriction(p.id) is null,
        'restriction',private.owner_target_restriction(p.id)) item
      from public.profiles p join auth.users u on u.id=p.id
      where (query_text='' and p.roles::text='Owner') or
        (query_text<>'' and (p.id::text=lower(query_text) or lower(u.email)=lower(query_text)))
      order by p.id limit 25 offset (page_number-1)*25
    ) v;
    result:=jsonb_build_object('items',items,'page',page_number,'pageSize',25,'total',total,'activeOwnerCount',owner_count);
  elsif action='ownerChangeStatus' then
    request_id:=(payload->>'requestId')::uuid;
    if request_id is null then raise exception 'invalid_request' using errcode='22023'; end if;
    select * into receipt from public.admin_audit_events where entity='owner_management'
      and operation='role_change' and entity_id=request_id::text and actor_id=actor;
    result:=case when found then jsonb_build_object('state','completed','result',receipt.after_values->'result')
      else jsonb_build_object('state','not_found') end;
  elsif action='setOwner' then
    target:=(payload->>'userId')::uuid; request_id:=(payload->>'requestId')::uuid;
    expected:=payload->>'expectedRole'; note:=btrim(payload->>'note');
    if target is null or request_id is null or jsonb_typeof(payload->'owner') is distinct from 'boolean'
      or coalesce(expected,'') not in ('User','Admin','Owner') or coalesce(note,'')='' or length(note)>4000
      then raise exception 'invalid_request' using errcode='22023'; end if;
    if target=actor then raise exception 'owner_self_change_forbidden' using errcode='PT403'; end if;
    desired:=(payload->>'owner')::boolean;
    canonical:=jsonb_build_object('userId',target,'owner',desired,'expectedRole',expected,'requestId',request_id,'note',note);
    perform pg_advisory_xact_lock(814716290);
    perform 1 from auth.users where id in(actor,target) order by id for share;
    perform 1 from public.profiles where id in(actor,target) order by id for no key update;
    if private.portal_staff_context() is distinct from ctx then
      raise exception 'admin_access_changed' using errcode='PT403'; end if;
    select * into receipt from public.admin_audit_events where entity='owner_management'
      and operation='role_change' and entity_id=request_id::text;
    if found then
      if receipt.actor_id is distinct from actor or receipt.after_values->'request' is distinct from canonical then
        raise exception 'owner_request_conflict' using errcode='PT409'; end if;
      result:=receipt.after_values->'result';
    else
      select roles::text into prior_role from public.profiles where id=target;
      if not found or prior_role is distinct from expected then
        raise exception 'owner_state_changed' using errcode='PT409'; end if;
      if desired and private.owner_target_restriction(target) is not null then
        raise exception 'owner_target_ineligible' using errcode='PT409'; end if;
      if not desired and prior_role<>'Owner' then raise exception 'owner_state_changed' using errcode='PT409'; end if;
      next_role:=case when desired then 'Owner' when exists(select 1 from public."Location_to_Admin" where user_id=target)
        then 'Admin' else 'User' end;
      old_actor:=current_setting('cleanstream.portal_actor',true);
      perform set_config('cleanstream.portal_actor',actor::text,true);
      if prior_role<>next_role then
        update public.profiles set roles=next_role::public."Roles" where id=target;
      end if;
      result:=jsonb_build_object('userId',target,'role',next_role,'requestId',request_id,'changed',prior_role<>next_role);
      insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,before_values,after_values)
      values(actor,coalesce((select full_name from public.profiles where id=actor),actor::text),
        'owner_management',request_id::text,'role_change',jsonb_build_object('role',prior_role),
        jsonb_build_object('request',canonical,'result',result));
      perform set_config('cleanstream.portal_actor',coalesce(old_actor,''),true);
      -- Audit/role triggers can wait. Recheck the target and the surviving Owners after them.
      if desired and private.owner_target_restriction(target) is not null then
        raise exception 'owner_target_ineligible' using errcode='PT409'; end if;
      if not desired then perform private.require_other_owner(target); end if;
    end if;
  else raise exception 'invalid_request' using errcode='22023'; end if;
  if private.portal_staff_context() is distinct from ctx then
    raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
revoke all on function public.admin_owner_management(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_owner_management(text,jsonb) to authenticated;

-- Retain the installed deletion implementation, triggers and exact deadline.
-- Its existing ACL (currently held closed) is preserved on the public wrapper.
-- No Auth-table trigger or claim of protection against external operator bans.
do $$
begin
  if has_function_privilege('anon','public.request_account_deletion()','execute')
    or has_function_privilege('authenticated','public.request_account_deletion()','execute')
    or has_function_privilege('service_role','public.request_account_deletion()','execute') then
    raise exception 'Deletion ACL must remain held during this installation' using errcode='55000';
  end if;
end $$;
alter function public.request_account_deletion() set schema private;
create function public.request_account_deletion()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare access_state jsonb; caller uuid; result jsonb;
begin
  access_state:=private.current_account_access(); caller:=(access_state->>'subject_id')::uuid;
  perform pg_advisory_xact_lock(814716290);
  perform 1 from auth.users where id=caller for share;
  perform 1 from public.profiles where id=caller for no key update;
  access_state:=private.current_account_access();
  if access_state->>'lifecycle_identity_allowed' is distinct from 'true' then
    raise exception 'account_restricted' using errcode='PT403'; end if;
  if exists(select 1 from public.profiles where id=caller and roles::text='Owner') then
    perform private.require_other_owner(caller);
  end if;
  result:=private.request_account_deletion();
  if exists(select 1 from public.profiles where id=caller and roles::text='Owner') then
    perform private.require_other_owner(caller);
  end if;
  return result;
end $$;
revoke all on function private.request_account_deletion() from public,anon,authenticated,service_role;
revoke all on function public.request_account_deletion() from public,anon,authenticated,service_role;

-- Move the accepted financial bodies intact, including their wallet locks,
-- arithmetic and ledger writes. Only the three caller wrappers regain EXECUTE.
alter function public.admin_adjust_wallet(uuid,integer,integer,integer,text) set schema private;
alter function public.admin_record_legal_cash_redemption(uuid,integer,text,text) set schema private;
alter function public.admin_set_wallet_status(uuid,text,text) set schema private;

create function private.portal_owner_context()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb;
begin
  ctx:=private.portal_staff_context();
  if ctx->>'role' is distinct from 'Owner' then raise exception 'owner_required' using errcode='PT403'; end if;
  return ctx;
end $$;
revoke all on function private.portal_owner_context() from public,anon,authenticated,service_role;

create function public.admin_adjust_wallet(wallet_id uuid,amount_cents integer,paid_amount_cents integer,
  promo_amount_cents integer,adjustment_note text)
returns bigint language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb; result bigint;
begin
  ctx:=private.portal_owner_context();
  result:=private.admin_adjust_wallet(wallet_id,amount_cents,paid_amount_cents,promo_amount_cents,adjustment_note);
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
create function public.admin_record_legal_cash_redemption(wallet_id uuid,amount_cents integer,
  stripe_refund_id text default null,redemption_note text default null)
returns bigint language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb; result bigint;
begin
  ctx:=private.portal_owner_context();
  result:=private.admin_record_legal_cash_redemption(wallet_id,amount_cents,stripe_refund_id,redemption_note);
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
create function public.admin_set_wallet_status(wallet_id uuid,new_status text,status_note text default null)
returns void language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb; before_status text;
begin
  ctx:=private.portal_owner_context();
  select status into before_status from public.wallet_accounts where id=wallet_id for no key update;
  perform private.admin_set_wallet_status(wallet_id,new_status,status_note);
  insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,before_values,after_values)
  values((ctx->>'actor')::uuid,coalesce((select full_name from public.profiles where id=(ctx->>'actor')::uuid),ctx->>'actor'),
    'wallet',wallet_id::text,'status',jsonb_build_object('status',before_status),jsonb_build_object('status',new_status,'note',status_note));
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
end $$;
revoke all on function private.admin_adjust_wallet(uuid,integer,integer,integer,text),
  private.admin_record_legal_cash_redemption(uuid,integer,text,text),private.admin_set_wallet_status(uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.admin_adjust_wallet(uuid,integer,integer,integer,text),
  public.admin_record_legal_cash_redemption(uuid,integer,text,text),public.admin_set_wallet_status(uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_adjust_wallet(uuid,integer,integer,integer,text),
  public.admin_record_legal_cash_redemption(uuid,integer,text,text),public.admin_set_wallet_status(uuid,text,text) to authenticated;

-- Global reads stay behind the same caller-bound Owner boundary. Direct wallet
-- tables and the security_invoker balance view retain their self-only policies.
create function public.admin_wallet_read(action text,payload jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  ctx jsonb; result jsonb; page_number integer; q text; target uuid; total bigint;
  items jsonb; balance jsonb; loads jsonb; redemptions jsonb; ledger jsonb;
  after_id uuid; cursors jsonb; c jsonb; collection text;
begin
  ctx:=private.portal_owner_context();
  if jsonb_typeof(payload) is distinct from 'object' then raise exception 'invalid_request' using errcode='22023'; end if;
  page_number:=coalesce((payload->>'page')::integer,1);
  if page_number<1 or page_number>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  if page_number=1 and payload->'after' is not null and payload->'after'<>'null'::jsonb then
    raise exception 'invalid_request' using errcode='22023'; end if;
  if action='search' then
    q:=lower(btrim(coalesce(payload->>'query','')));
    if length(q)>254 then raise exception 'invalid_request' using errcode='22023'; end if;
    if page_number>1 then
      if jsonb_typeof(payload->'after') is distinct from 'string' then raise exception 'invalid_request' using errcode='22023'; end if;
      after_id:=(payload->>'after')::uuid;
    end if;
    with matches as (
      select b.* from public.wallet_balances b where q='' or strpos(b.wallet_account_id::text,q)>0
        or strpos(b.user_id::text,q)>0 or exists(select 1 from public.profiles p where p.id=b.user_id
          and (strpos(lower(coalesce(p.email,'')),q)>0 or strpos(lower(coalesce(p.full_name,'')),q)>0))
        or exists(select 1 from public.wallet_loads l where l.wallet_account_id=b.wallet_account_id and
          (strpos(lower(coalesce(l.stripe_payment_intent_id,'')),q)>0 or
           strpos(lower(coalesce(l.stripe_checkout_session_id,'')),q)>0 or
           strpos(lower(coalesce(l.stripe_charge_id,'')),q)>0))
    ), page as (select * from matches where after_id is null or wallet_account_id>after_id order by wallet_account_id limit 26)
    select (select count(*) from matches),coalesce(jsonb_agg(to_jsonb(page) order by wallet_account_id),'[]')
      into total,items from page;
    result:=jsonb_build_object('items',items-25,'page',page_number,'pageSize',25,'total',total,
      'nextCursor',case when jsonb_array_length(items)>25 then items->24->>'wallet_account_id' end);
  elsif action='detail' then
    target:=(payload->>'walletId')::uuid;
    if target is null then raise exception 'invalid_request' using errcode='22023'; end if;
    cursors:=payload->'after';
    if page_number>1 then
      if jsonb_typeof(cursors) is distinct from 'object' then raise exception 'invalid_request' using errcode='22023'; end if;
      foreach collection in array array['loads','redemptions','ledger'] loop
        c:=cursors->collection;
        if c is null then raise exception 'invalid_request' using errcode='22023'; end if;
        if c<>'null'::jsonb then
          if jsonb_typeof(c) is distinct from 'object' or jsonb_typeof(c->'id') is distinct from 'string'
            or coalesce(c->>'id','') !~ '^[0-9]+$' or jsonb_typeof(c->'createdAt') is distinct from 'string' then
            raise exception 'invalid_request' using errcode='22023'; end if;
          if (c->>'id')::bigint<=0 or not isfinite((c->>'createdAt')::timestamptz) then
            raise exception 'invalid_request' using errcode='22023'; end if;
        end if;
      end loop;
    end if;
    select to_jsonb(b) into balance from public.wallet_balances b where wallet_account_id=target;
    if not found then raise exception 'wallet_not_found' using errcode='PT404'; end if;
    select coalesce(jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc),'[]') into loads from
      (select * from public.wallet_loads where wallet_account_id=target and (page_number=1 or
        (cursors->'loads'<>'null'::jsonb and (created_at,id)<((cursors->'loads'->>'createdAt')::timestamptz,(cursors->'loads'->>'id')::bigint)))
        order by created_at desc,id desc limit 101) v;
    select coalesce(jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc),'[]') into redemptions from
      (select * from public.wallet_redemptions where wallet_account_id=target and (page_number=1 or
        (cursors->'redemptions'<>'null'::jsonb and (created_at,id)<((cursors->'redemptions'->>'createdAt')::timestamptz,(cursors->'redemptions'->>'id')::bigint)))
        order by created_at desc,id desc limit 101) v;
    select coalesce(jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc),'[]') into ledger from
      (select * from public.wallet_ledger_entries where wallet_account_id=target and (page_number=1 or
        (cursors->'ledger'<>'null'::jsonb and (created_at,id)<((cursors->'ledger'->>'createdAt')::timestamptz,(cursors->'ledger'->>'id')::bigint)))
        order by created_at desc,id desc limit 101) v;
    result:=jsonb_build_object('balance',balance,'loads',loads-100,'redemptions',redemptions-100,'ledger',ledger-100,
      'page',page_number,'pageSize',100,'hasMore',jsonb_build_object('loads',jsonb_array_length(loads)>100,
        'redemptions',jsonb_array_length(redemptions)>100,'ledger',jsonb_array_length(ledger)>100),
      'nextCursor',jsonb_build_object(
        'loads',case when jsonb_array_length(loads)>100 then jsonb_build_object('createdAt',loads->99->'created_at','id',loads->99->>'id') end,
        'redemptions',case when jsonb_array_length(redemptions)>100 then jsonb_build_object('createdAt',redemptions->99->'created_at','id',redemptions->99->>'id') end,
        'ledger',case when jsonb_array_length(ledger)>100 then jsonb_build_object('createdAt',ledger->99->'created_at','id',ledger->99->>'id') end));
  else raise exception 'invalid_request' using errcode='22023'; end if;
  if private.portal_owner_context() is distinct from ctx then raise exception 'admin_access_changed' using errcode='PT403'; end if;
  return result;
end $$;
revoke all on function public.admin_wallet_read(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_wallet_read(text,jsonb) to authenticated;

commit;
