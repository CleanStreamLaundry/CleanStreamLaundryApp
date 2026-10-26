begin;

alter table public.transactions
  add column cortina_vend_session_id uuid unique
    references public.cortina_vend_sessions(id) on delete restrict,
  add column cortina_status text;

alter table public.transactions add constraint transactions_cortina_link_status
  check ((cortina_vend_session_id is null) = (cortina_status is null));

-- Existing client-created transactions remain supported, but cannot impersonate
-- server-confirmed vends or change their payment details.
create policy "Cortina history is server-created" on public.transactions
  as restrictive for insert to anon, authenticated
  with check (cortina_vend_session_id is null and cortina_status is null);
create policy "Cortina history is server-managed" on public.transactions
  as restrictive for update to anon, authenticated
  using (cortina_vend_session_id is null)
  with check (cortina_vend_session_id is null and cortina_status is null);

create function public.sync_cortina_transaction(target_session_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare
  vend public.cortina_vend_sessions%rowtype;
begin
  select * into vend from public.cortina_vend_sessions
  where id = target_session_id for update;
  if not found then return; end if;

  if vend.status = 'started' then
    insert into public.transactions (
      user_id, amount, description, type, created_at,
      cortina_vend_session_id, cortina_status
    )
    select vend.user_id, vend.amount_cents::numeric / 100,
      concat(case when vend.payment_method = 'wallet'
        then 'Loyalty payment on ' else 'Card payment on ' end,
        m."Machine_type"::text, ' - ', m."Name"),
      'laundry', coalesce(vend.completed_at, vend.created_at), vend.id, vend.status
    from public."Machines" m where m.id = vend.machine_id
    on conflict (cortina_vend_session_id) do nothing;
  end if;

  -- Preserve the original history and amount if a late Void reverses the vend.
  update public.transactions set cortina_status = vend.status
  where cortina_vend_session_id = vend.id
    and cortina_status is distinct from vend.status;
end;
$$;
revoke all on function public.sync_cortina_transaction(uuid) from public, anon, authenticated;
grant execute on function public.sync_cortina_transaction(uuid) to service_role;

create function public.on_cortina_transaction_status()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  perform public.sync_cortina_transaction(new.id);
  return new;
end;
$$;
revoke all on function public.on_cortina_transaction_status() from public, anon, authenticated;
grant execute on function public.on_cortina_transaction_status() to service_role;

create trigger cortina_transaction_history
after insert or update of status on public.cortina_vend_sessions
for each row execute function public.on_cortina_transaction_status();

select public.sync_cortina_transaction(id)
from public.cortina_vend_sessions where status = 'started';

-- This trigger also protects direct Refunds inserts and the existing admin
-- approval routine. Raising here rolls back any credit made by that routine.
create function public.validate_cortina_credit_request()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  payment public.transactions%rowtype;
  vend public.cortina_vend_sessions%rowtype;
  payment_id bigint;
begin
  payment_id := case when tg_op = 'UPDATE' then old.transaction_id else new.transaction_id end;
  select * into payment from public.transactions where id = payment_id;
  if payment.cortina_vend_session_id is null then return new; end if;

  select * into vend from public.cortina_vend_sessions
  where id = payment.cortina_vend_session_id for update;
  if new.transaction_id is distinct from payment.id
    or new.user_id is distinct from payment.user_id
    or new.user_id is distinct from vend.user_id
    or new.amount::numeric is distinct from (vend.amount_cents::numeric / 100) then
    raise exception using errcode = '22023', message = 'Credit request does not match the paid vend';
  end if;
  if (tg_op = 'INSERT' or new.status::text = 'approved') and vend.status <> 'started' then
    raise exception using errcode = '22023', message = 'Vend is not eligible for loyalty credit';
  end if;
  if tg_op = 'INSERT' then
    if payment.created_at < now() - interval '14 days' then
      raise exception using errcode = '22023', message = 'Credit request period has expired';
    end if;
    if nullif(btrim(new.description), '') is null or char_length(new.description) > 2000 then
      raise exception using errcode = '22023', message = 'Enter a reason of 1 to 2000 characters';
    end if;
    if new.status::text <> 'pending' then
      raise exception using errcode = '22023', message = 'Credit requests must start pending';
    end if;
    if exists (select 1 from public."Refunds" where transaction_id = payment.id) then
      raise exception using errcode = '23505', message = 'A credit request already exists for this vend';
    end if;
    update public.transactions set requested_refund = true where id = payment.id;
  end if;
  return new;
end;
$$;
revoke all on function public.validate_cortina_credit_request() from public, anon, authenticated;

create trigger validate_cortina_credit
before insert or update on public."Refunds"
for each row execute function public.validate_cortina_credit_request();

create function public.request_cortina_loyalty_credit(
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
  -- Use the same session lock as callback updates and credit validation.
  select * into vend from public.cortina_vend_sessions
  where id = payment.cortina_vend_session_id for update;
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
  return jsonb_build_object('refund_id', request.refund_id,
    'amount', request.amount, 'status', request.status);
end;
$$;
revoke all on function public.request_cortina_loyalty_credit(bigint, text) from public, anon;
grant execute on function public.request_cortina_loyalty_credit(bigint, text) to authenticated;

commit;
