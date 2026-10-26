begin;

do $$
begin
  if current_user <> 'postgres'
    or to_regclass('private.account_lifecycle') is null
    or to_regprocedure('public.get_admission_status()') is null
    or to_regprocedure('public.increment_user_refund_attempts(uuid)') is null
    or to_regprocedure('public.request_cortina_loyalty_credit(bigint,text)') is null then
    raise exception 'Reviewed admission, lifecycle and claim prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- A pending manual claim, not payment proof or a wallet credit. Old direct
-- writers require coordinated client adoption; this RPC does not retire them.
create function public.request_legacy_loyalty_credit(
  target_transaction_id bigint, request_description text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caller uuid;
  payment public.transactions%rowtype;
  request public."Refunds"%rowtype;
  reason text := nullif(btrim(request_description), '');
  matches bigint;
  request_id bigint;
  amount numeric;
begin
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller := auth.uid();
  if reason is null or char_length(reason) > 2000 then
    raise exception 'Enter a reason of 1 to 2000 characters' using errcode = '22023';
  end if;

  select * into payment from public.transactions
  where id = target_transaction_id and user_id = caller for no key update;
  if not found then
    raise exception 'Transaction is not available for this account' using errcode = '42501';
  end if;
  perform 1 from public.profiles where id = caller for no key update;
  if not found then raise exception 'account_restricted' using errcode = 'PT403'; end if;
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  amount := payment.amount::numeric;
  if payment.cortina_vend_session_id is not null or payment.cortina_status is not null
    or payment.type is distinct from 'laundry'
    or amount is null or amount::text in ('NaN','Infinity','-Infinity')
    or amount <= 0 or amount > 21474836.47 or trunc(amount, 2) <> amount then
    raise exception 'Transaction is not eligible for a legacy machine claim' using errcode = '22023';
  end if;

  -- Do not lock an existing Refunds row: admin resolution locks that row before
  -- its transaction/wallet/profile. Ambiguous history is never chosen or merged.
  select count(*), min(refund_id) into matches, request_id
  from public."Refunds" where transaction_id = payment.id;
  if matches > 1 then
    raise exception 'Claim history requires reconciliation' using errcode = '22023';
  elsif matches = 1 then
    select * into request from public."Refunds" where refund_id = request_id;
    if not found or request.user_id is distinct from caller
      or request.transaction_id is distinct from payment.id
      or request.amount::numeric is distinct from amount
      or request.status is null then
      raise exception 'Claim history requires reconciliation' using errcode = '22023';
    end if;
    if public.get_admission_status()->>'next_step' is distinct from 'home' then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    return jsonb_build_object('refund_id', request.refund_id,
      'amount', request.amount, 'status', request.status);
  end if;

  if payment.created_at is null or payment.created_at > clock_timestamp()
    or payment.created_at < clock_timestamp() - interval '14 days' then
    raise exception 'Credit request period has expired' using errcode = '22023';
  end if;
  insert into public."Refunds" (user_id, transaction_id, description, amount)
  values (caller, payment.id, reason, payment.amount) returning * into request;
  update public.transactions set requested_refund = true where id = payment.id;
  perform public.increment_user_refund_attempts(caller);

  -- Trigger waits may outlive authority or the claim window; roll back all
  -- three writes in that case. Notice enqueue is a separate post-commit call.
  if public.get_admission_status()->>'next_step' is distinct from 'home' then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if payment.created_at < clock_timestamp() - interval '14 days' then
    raise exception 'Credit request period has expired' using errcode = '22023';
  end if;
  return jsonb_build_object('refund_id', request.refund_id,
    'amount', request.amount, 'status', request.status);
end;
$$;

revoke all on function public.request_legacy_loyalty_credit(bigint,text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.request_legacy_loyalty_credit(bigint,text) to authenticated;

commit;
