-- Do not infer historical payment routing from today's machine configuration.
alter table public.cortina_vend_sessions
  add column nayax_environment text check (nayax_environment in ('sandbox', 'production')),
  add column nayax_terminal_id text,
  add column nayax_uniqr text,
  add column stripe_livemode boolean;

create function public.guard_cortina_payment_binding()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  config public.cortina_machine_config%rowtype;
  machine public."Machines"%rowtype;
  rate public.washer_size_rates%rowtype;
  dryer_line integer;
  selector_code integer;
begin
  if tg_op = 'INSERT' then
    select * into machine from public."Machines" where id = new.machine_id for share;
    if not found or machine.is_out_of_service
      or lower(coalesce(machine."Status"::text, '')) not in ('idle', 'available') then
      raise exception 'Machine is unavailable' using errcode = '55000';
    end if;
    select * into config from public.cortina_machine_config
    where machine_id = new.machine_id for share nowait;
    if not found or not config.is_enabled or config.review_required
      or config.environment not in ('sandbox', 'production')
      or coalesce(nullif(btrim(config.nayax_terminal_id), ''),
                  nullif(btrim(config.nayax_uniqr), '')) is null then
      raise exception 'Machine payment routing needs review' using errcode = '40001';
    end if;
    if new.currency <> 'USD' or new.status <> 'payment_pending'
      or new.stripe_payment_intent_id is not null
      or new.stripe_checkout_session_id is not null or new.stripe_charge_id is not null then
      raise exception 'New vend must be unfunded USD';
    end if;
    if lower(machine."Machine_type"::text) = 'washer' then
      -- Fail/retry instead of waiting behind a rate edit that also updates Machines.
      select * into rate from public.washer_size_rates
      where id = machine.washer_size_rate_id for share nowait;
      if not found or not rate.is_active or rate.review_required
        or new.amount_cents is distinct from rate.price_cents
        or new.washer_size_rate_id is distinct from rate.id
        or new.dryer_minutes is not null then
        raise exception 'Washer price has changed' using errcode = '40001';
      end if;
    elsif lower(machine."Machine_type"::text) = 'dryer' then
      select line into dryer_line from (values
        (50,10,1),(100,20,2),(150,30,3),(200,40,4),(300,60,5),(450,90,6)
      ) as options(cents,minutes,line)
      where cents = new.amount_cents and minutes = new.dryer_minutes;
      if dryer_line is null or new.washer_size_rate_id is not null then
        raise exception 'Invalid dryer selection' using errcode = '40001';
      end if;
    else
      raise exception 'Unsupported machine type';
    end if;
    -- Recheck the selector under the same lock as the routing snapshot. Never
    -- combine a stale application selector with a newer device configuration.
    if config.product_codes is not null then
      selector_code := (config.product_codes->>new.amount_cents::text)::numeric::integer;
      if selector_code is null or new.product_code is distinct from selector_code
        or new.pulse_line_number is not null then
        raise exception 'Machine product selection has changed' using errcode = '40001';
      end if;
    elsif new.product_code is not null or
      new.pulse_line_number is distinct from coalesce(dryer_line, config.pulse_line_number)
      or new.pulse_line_number not between 1 and 6 or new.pulse_line_number is null then
      raise exception 'Machine pulse selection has changed' using errcode = '40001';
    end if;
    new.nayax_environment := config.environment;
    new.nayax_terminal_id := nullif(btrim(config.nayax_terminal_id), '');
    new.nayax_uniqr := nullif(btrim(config.nayax_uniqr), '');
    new.stripe_livemode := case when new.payment_method = 'card'
      then config.environment = 'production' else null end;
  else
    if old.nayax_transaction_id is not null and
      new.nayax_transaction_id is distinct from old.nayax_transaction_id then
      raise exception 'Nayax transaction binding is immutable';
    end if;
    if row(new.machine_id, new.amount_cents, new.currency, new.payment_method,
           new.channel, new.transaction_id, new.client_request_id,
           new.client_access_token_hash, new.dryer_minutes, new.product_code,
           new.pulse_line_number, new.nayax_environment, new.nayax_terminal_id,
           new.nayax_uniqr, new.stripe_livemode)
      is distinct from
       row(old.machine_id, old.amount_cents, old.currency, old.payment_method,
           old.channel, old.transaction_id, old.client_request_id,
           old.client_access_token_hash, old.dryer_minutes, old.product_code,
           old.pulse_line_number, old.nayax_environment, old.nayax_terminal_id,
           old.nayax_uniqr, old.stripe_livemode) then
      raise exception 'Vend payment binding is immutable';
    end if;
    if (old.stripe_payment_intent_id is not null and
        new.stripe_payment_intent_id is distinct from old.stripe_payment_intent_id)
      or (old.stripe_checkout_session_id is not null and
          new.stripe_checkout_session_id is distinct from old.stripe_checkout_session_id)
      or (old.stripe_charge_id is not null and
          new.stripe_charge_id is distinct from old.stripe_charge_id) then
      raise exception 'Stripe payment binding is immutable';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.guard_cortina_payment_binding() from public, anon, authenticated;
create trigger guard_cortina_payment_binding
before insert or update on public.cortina_vend_sessions
for each row execute function public.guard_cortina_payment_binding();

-- Only the verified provider adapter may record funding. Lock, audit and state
-- transition share one transaction; duplicate deliveries never reopen a vend.
create function public.record_cortina_card_payment(
  p_session uuid, p_event text, p_intent text, p_checkout text,
  p_charge text, p_amount integer, p_currency text, p_livemode boolean
)
returns void language plpgsql security invoker set search_path = '' as $$
declare
  session public.cortina_vend_sessions%rowtype;
  prior public.cortina_vend_events%rowtype;
  evidence jsonb;
begin
  select * into session from public.cortina_vend_sessions
  where id = p_session for update;
  if not found or session.payment_method <> 'card'
    or session.nayax_environment is null or session.stripe_livemode is null
    or p_amount is distinct from session.amount_cents
    or upper(p_currency) is distinct from session.currency
    or p_livemode is distinct from session.stripe_livemode
    or nullif(btrim(p_event), '') is null or nullif(btrim(p_intent), '') is null
    or nullif(btrim(p_charge), '') is null
    or (session.channel = 'web' and session.stripe_checkout_session_id is null)
    or (session.channel = 'app' and session.stripe_checkout_session_id is not null)
    or (session.stripe_payment_intent_id is not null and
        session.stripe_payment_intent_id is distinct from p_intent)
    or p_checkout is distinct from session.stripe_checkout_session_id
    or (session.stripe_payment_intent_id is null and p_checkout is null)
    or (session.stripe_charge_id is not null and
        session.stripe_charge_id is distinct from p_charge) then
    raise exception 'Stripe payment does not match the vend session';
  end if;

  evidence := jsonb_build_object('payment_intent_id', p_intent,
    'checkout_session_id', p_checkout, 'charge_id', p_charge,
    'amount_received', p_amount, 'currency', upper(p_currency), 'livemode', p_livemode);

  insert into public.cortina_vend_events(session_id, source, event_type, event_key, payload)
  values (p_session, 'stripe', 'payment_succeeded', 'stripe:' || p_event,
          evidence)
  on conflict (event_key) do nothing;
  select * into prior from public.cortina_vend_events where event_key = 'stripe:' || p_event;
  if prior.session_id is distinct from p_session
    or prior.source <> 'stripe' or prior.event_type <> 'payment_succeeded'
    or prior.payload is distinct from evidence then
    raise exception 'Stripe event is already bound to another payment';
  end if;

  update public.cortina_vend_sessions set
    status = case when status = 'payment_pending' then 'paid'
      when status = 'failed' then 'support_required' else status end,
    stripe_payment_intent_id = p_intent,
    stripe_charge_id = coalesce(stripe_charge_id, p_charge),
    failure_message = case when status = 'failed'
      then 'Payment settled after session failure; reconciliation required'
      else failure_message end
  where id = p_session;
end;
$$;

revoke all on function public.record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)
from public, anon, authenticated;
grant execute on function public.record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)
to service_role;
