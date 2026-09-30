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
begin
  if tg_op = 'INSERT' then
    select * into config from public.cortina_machine_config
    where machine_id = new.machine_id for share;
    if not found or not config.is_enabled or config.review_required
      or config.environment not in ('sandbox', 'production')
      or coalesce(nullif(btrim(config.nayax_terminal_id), ''),
                  nullif(btrim(config.nayax_uniqr), '')) is null then
      raise exception 'Machine payment routing needs review';
    end if;
    new.nayax_environment := config.environment;
    new.nayax_terminal_id := nullif(btrim(config.nayax_terminal_id), '');
    new.nayax_uniqr := nullif(btrim(config.nayax_uniqr), '');
    new.stripe_livemode := case when new.payment_method = 'card'
      then config.environment = 'production' else null end;
  else
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
begin
  select * into session from public.cortina_vend_sessions
  where id = p_session for update;
  if not found or session.payment_method <> 'card'
    or session.nayax_environment is null or session.stripe_livemode is null
    or p_amount is distinct from session.amount_cents
    or upper(p_currency) is distinct from session.currency
    or p_livemode is distinct from session.stripe_livemode
    or nullif(btrim(p_event), '') is null or nullif(btrim(p_intent), '') is null
    or (session.stripe_payment_intent_id is not null and
        session.stripe_payment_intent_id is distinct from p_intent)
    or p_checkout is distinct from session.stripe_checkout_session_id
    or (session.stripe_payment_intent_id is null and p_checkout is null)
    or (session.stripe_charge_id is not null and
        session.stripe_charge_id is distinct from p_charge) then
    raise exception 'Stripe payment does not match the vend session';
  end if;

  insert into public.cortina_vend_events(session_id, source, event_type, event_key, payload)
  values (p_session, 'stripe', 'payment_succeeded', 'stripe:' || p_event,
          jsonb_build_object('payment_intent_id', p_intent))
  on conflict (event_key) do nothing;
  select * into prior from public.cortina_vend_events where event_key = 'stripe:' || p_event;
  if prior.session_id is distinct from p_session
    or prior.payload->>'payment_intent_id' is distinct from p_intent then
    raise exception 'Stripe event is already bound to another payment';
  end if;

  update public.cortina_vend_sessions set
    status = 'paid', stripe_payment_intent_id = p_intent,
    stripe_charge_id = coalesce(stripe_charge_id, p_charge)
  where id = p_session and status = 'payment_pending';
end;
$$;

revoke all on function public.record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)
from public, anon, authenticated;
grant execute on function public.record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)
to service_role;
