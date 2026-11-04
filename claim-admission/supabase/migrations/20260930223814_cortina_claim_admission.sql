-- Human claims use canonical admission; clients cannot manufacture financial rows.
-- No historical writes, provider calls, or settlement/refund policy changes.
begin;

do $$
begin
  if current_user <> 'postgres'
    or to_regclass('private.account_lifecycle') is null
    or to_regprocedure('public.get_admission_status()') is null
    or to_regprocedure('public.request_cortina_loyalty_credit(bigint,text)') is null
    or to_regprocedure('public.request_legacy_loyalty_credit(bigint,text)') is null
    or to_regprocedure('public.increment_user_refund_attempts(uuid)') is null then
    raise exception 'Reviewed canonical admission and both atomic claim contracts required'
      using errcode = '55000';
  end if;
end;
$$;

create or replace function public.request_cortina_loyalty_credit(
  target_transaction_id bigint, request_description text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  customer_id uuid := auth.uid();
  payment public.transactions%rowtype;
  vend public.cortina_vend_sessions%rowtype;
  request public."Refunds"%rowtype;
  reason text := nullif(btrim(request_description), '');
begin
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if customer_id is null then
    raise exception using errcode = '42501', message = 'Sign in to request loyalty credit';
  end if;
  if reason is null or char_length(reason) > 2000 then
    raise exception using errcode = '22023', message = 'Enter a reason of 1 to 2000 characters';
  end if;
  select * into payment from public.transactions
  where id = target_transaction_id and user_id = customer_id
    and cortina_vend_session_id is not null;
  if not found then
    raise exception using errcode = '42501', message = 'Transaction is not available for this account';
  end if;
  -- Retain the existing session-first lock order shared with callback validation.
  select * into vend from public.cortina_vend_sessions
  where id = payment.cortina_vend_session_id for update;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if vend.status <> 'started' or vend.user_id is distinct from customer_id then
    raise exception using errcode = '22023', message = 'Vend is not eligible for loyalty credit';
  end if;
  select * into request from public."Refunds" where transaction_id = payment.id;
  if not found then
    if payment.created_at < now() - interval '14 days' then
      raise exception using errcode = '22023', message = 'Credit request period has expired';
    end if;
    insert into public."Refunds" (user_id, transaction_id, description, amount)
    values (customer_id, payment.id, reason, vend.amount_cents::numeric / 100)
    returning * into request;
    perform public.increment_user_refund_attempts(customer_id);
  end if;
  -- Trigger/counter waits and read-only replay must not return stale admission.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  return jsonb_build_object('refund_id', request.refund_id,
    'amount', request.amount, 'status', request.status);
end;
$$;

-- Preserve trusted service/definer writers. Table revokes alone leave column
-- grants behind; restrictive policies also deny later accidental client grants.
do $$
declare
  target text;
  columns text;
begin
  foreach target in array array['transactions', 'Refunds'] loop
    if not exists (select 1 from pg_class c where c.oid = format('public.%I', target)::regclass
      and c.relowner = 'postgres'::regrole and c.relrowsecurity and not c.relforcerowsecurity) then
      raise exception 'Reviewed financial table ownership and RLS required' using errcode = '55000';
    end if;
    select string_agg(quote_ident(attname), ', ' order by attnum) into columns
      from pg_attribute where attrelid = format('public.%I', target)::regclass
        and attnum > 0 and not attisdropped;
    execute format('revoke insert on table public.%I from public, anon, authenticated', target);
    execute format('revoke insert (%s) on public.%I from public, anon, authenticated', columns, target);
    if exists (select 1 from (values ('anon'), ('authenticated')) r(role_name)
      where has_table_privilege(r.role_name, format('public.%I', target), 'INSERT')
        or has_any_column_privilege(r.role_name, format('public.%I', target), 'INSERT')) then
      raise exception 'Inherited client financial INSERT privilege requires review' using errcode = '42501';
    end if;
    if not has_table_privilege('service_role', format('public.%I', target), 'INSERT') then
      raise exception 'Existing trusted financial writer privilege must remain' using errcode = '42501';
    end if;
  end loop;
end;
$$;

create policy transactions_server_insert_only on public.transactions
  as restrictive for insert to anon, authenticated with check (false);
create policy refunds_server_insert_only on public."Refunds"
  as restrictive for insert to anon, authenticated with check (false);

commit;
