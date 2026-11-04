-- GENERATED: four accepted Cortina prerequisites; no history replay or routing backfill.
-- Target: DEVELOPMENT dnuuhupoxjtwqzaqylvb, AFTER separately accepted C/D installation.
-- Only outer transaction wrappers are removed; see migration-sources.sha256.
BEGIN;

-- SOURCE: supabase/migrations/20260930154259_freeze_cortina_payment_bindings.sql
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


-- SOURCE: supabase/migrations/20260930163919_cortina_callback_provider_ownership.sql
-- Apply only in a transaction. Lock through preflight/index/trigger installation;
-- abort on ambiguous history instead of assigning, deleting or repairing it.
lock table public.cortina_vend_sessions, public.cortina_vend_events in share row exclusive mode;
do $$
begin
  if exists (
    select environment, provider_id from (
      select nayax_environment as environment, nayax_transaction_id as provider_id, id as session_id
      from public.cortina_vend_sessions where nayax_environment is not null and nayax_transaction_id is not null
      union
      select s.nayax_environment,
        coalesce(e.payload #>> '{BasicInfo,NayaxTransactionId}', e.payload ->> 'NayaxTransactionId'), s.id
      from public.cortina_vend_events e join public.cortina_vend_sessions s on s.id=e.session_id
      where s.nayax_environment is not null and e.source='nayax' and e.event_type in ('sale','sale_end','void')
    ) evidence where provider_id is not null
    group by environment, provider_id having count(distinct session_id)>1
  ) then
    raise exception 'Cortina provider ownership preflight failed; reconcile duplicate frozen bindings/audits before activation'
      using errcode='23505';
  end if;
end;
$$;

create unique index cortina_nayax_environment_transaction_key
  on public.cortina_vend_sessions(nayax_environment,nayax_transaction_id)
  where nayax_environment is not null and nayax_transaction_id is not null;

-- Commit audit and provider-ID ownership together. Status CAS and compensation
-- stay in their existing handlers; this trigger never starts or refunds a vend.
create function public.bind_cortina_callback_provider()
returns trigger language plpgsql security invoker set search_path='' as $$
declare
  s public.cortina_vend_sessions%rowtype;
  provider_id text;
  amount_text text;
  terminal_id text;
  expected_key text;
begin
  if new.source <> 'nayax' or new.event_type not in ('sale','sale_end','void') then return new; end if;
  select * into s from public.cortina_vend_sessions where id=new.session_id for update;
  provider_id := coalesce(new.payload #>> '{BasicInfo,NayaxTransactionId}',new.payload ->> 'NayaxTransactionId');
  amount_text := new.payload #>> '{BasicInfo,Amount}';
  terminal_id := nullif(btrim(new.payload #>> '{MachineInfo,TerminalId}'),'');
  if not found or s.nayax_environment is null
    or s.nayax_environment not in ('sandbox','production')
    or coalesce(nullif(btrim(s.nayax_terminal_id),''),nullif(btrim(s.nayax_uniqr),'')) is null
    or s.currency <> 'USD'
    or (s.payment_method='card' and s.stripe_livemode is distinct from (s.nayax_environment='production'))
    or ((s.product_code between 0 and 32767 and s.pulse_line_number is null)
      or (s.product_code is null and s.pulse_line_number between 1 and 6)) is not true
    or btrim(new.payload #>> '{BasicInfo,TransactionId}') is distinct from s.transaction_id
    or upper(new.payload #>> '{BasicInfo,CurrencyCode}') is distinct from s.currency
    or amount_text is null or btrim(amount_text) !~ '^[0-9]+([.][0-9]+)?$'
    or (terminal_id is not null and terminal_id is distinct from s.nayax_terminal_id)
    or (provider_id is not null and provider_id !~ '^[1-9][0-9]*$')
    or (new.event_type <> 'void' and provider_id is null)
    or (s.nayax_transaction_id is not null and provider_id is not null and s.nayax_transaction_id <> provider_id)
  then
    raise exception 'Callback does not match frozen session' using errcode='23514';
  end if;
  if amount_text::numeric * 100 <> s.amount_cents then
    raise exception 'Callback amount does not match frozen session' using errcode='23514';
  end if;
  if (new.event_type in ('sale','sale_end') and s.status not in ('starting','awaiting_sale','approved','started'))
    or (new.event_type='void' and s.status in ('payment_pending','paid')) then
    raise exception 'Callback session state is no longer eligible' using errcode='23514';
  end if;
  expected_key := 'nayax:' || s.nayax_environment || ':' ||
    case new.event_type when 'sale_end' then 'sale-end' else new.event_type end || ':' ||
    coalesce(provider_id,s.transaction_id);
  if new.event_key is distinct from expected_key then
    raise exception 'Callback audit key does not match frozen environment' using errcode='23514';
  end if;
  if exists (
    select 1 from public.cortina_vend_events e
    join public.cortina_vend_sessions owner on owner.id=e.session_id
    -- Old handlers committed audit before binding. Reserve that evidence across
    -- every callback kind without assigning a missing binding or environment.
    where e.event_key in (
      'nayax:sale:' || provider_id,
      'nayax:sale-end:' || provider_id,
      'nayax:void:' || coalesce(provider_id,s.transaction_id)
    )
      and e.session_id <> s.id
      and (owner.nayax_environment is null or owner.nayax_environment=s.nayax_environment)
  ) then
    raise exception 'Historical callback audit has another or unknown environment owner' using errcode='23514';
  end if;
  -- The unique index arbitrates simultaneous callbacks on different sessions.
  -- An INSERT conflict or later trigger error rolls this binding back as well.
  if s.nayax_transaction_id is null and provider_id is not null then
    update public.cortina_vend_sessions set nayax_transaction_id=provider_id where id=s.id;
  end if;
  return new;
end;
$$;
revoke all on function public.bind_cortina_callback_provider() from public, anon, authenticated;
grant execute on function public.bind_cortina_callback_provider() to service_role;
create trigger bind_cortina_callback_provider after insert on public.cortina_vend_events
  for each row execute function public.bind_cortina_callback_provider();


-- SOURCE: supabase/migrations/20260930223000_immutable_checkout_return_version.sql
-- Additive cutover identity. The legacy default is permanent, including old writers.

do $$
begin
  if to_regclass('public.cortina_vend_sessions') is null or
     to_regprocedure('public.guard_cortina_payment_binding()') is null then
    raise exception 'Reviewed Cortina payment bindings required' using errcode = '55000';
  end if;
end;
$$;

alter table public.cortina_vend_sessions
  add column checkout_return_version smallint not null default 1,
  add constraint cortina_checkout_return_version_valid check (
    checkout_return_version in (1, 2) and
    (checkout_return_version = 1 or (payment_method = 'card' and channel = 'web'))
  );

create function public.guard_cortina_checkout_return_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.checkout_return_version is distinct from old.checkout_return_version then
    raise exception 'Checkout return version is immutable' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_cortina_checkout_return_version()
  from public, anon, authenticated, service_role;
create trigger guard_cortina_checkout_return_version
before update on public.cortina_vend_sessions
for each row execute function public.guard_cortina_checkout_return_version();



-- SOURCE: supabase/migrations/20260930225326_cortina_request_capacity.sql

create schema if not exists private;

-- Three project-wide capacity buckets, not caller identities or request history.
create table private.cortina_request_capacity (
  bucket text primary key check (bucket in ('quote', 'card', 'status')),
  tokens numeric not null check (
    tokens >= 0 and tokens <= case bucket when 'quote' then 30 when 'card' then 5 else 120 end
  ),
  updated_at timestamptz not null check (pg_catalog.isfinite(updated_at))
);
alter table private.cortina_request_capacity enable row level security;
revoke all on table private.cortina_request_capacity from public, anon, authenticated, service_role;

insert into private.cortina_request_capacity(bucket, tokens, updated_at)
values ('quote', 30, pg_catalog.clock_timestamp()),
       ('card', 5, pg_catalog.clock_timestamp()),
       ('status', 120, pg_catalog.clock_timestamp());

-- Definer access is narrowly needed for this private table; only service_role may execute.
create function public.consume_cortina_request_capacity(p_bucket text)
returns jsonb language plpgsql security definer
set search_path = '' set lock_timeout = '500ms' as $$
declare
  current_bucket private.cortina_request_capacity%rowtype;
  capacity integer;
  refill_per_minute integer;
  observed_at timestamptz;
  available numeric;
begin
  case p_bucket
    when 'quote' then capacity := 30; refill_per_minute := 120;
    when 'card' then capacity := 5; refill_per_minute := 10;
    when 'status' then capacity := 120; refill_per_minute := 1200;
    else raise exception 'Invalid Cortina capacity bucket' using errcode = '22023';
  end case;

  select * into current_bucket from private.cortina_request_capacity
  where bucket = p_bucket for update;
  if not found then
    raise exception 'Cortina capacity unavailable' using errcode = '55000';
  end if;

  -- Sample after the lock wait. Backward wall-clock changes cannot mint tokens.
  observed_at := greatest(pg_catalog.clock_timestamp(), current_bucket.updated_at);
  available := least(capacity, current_bucket.tokens +
    extract(epoch from (observed_at - current_bucket.updated_at)) * refill_per_minute / 60);
  if available < 1 then
    return pg_catalog.jsonb_build_object('allowed', false,
      'retry_after_seconds', pg_catalog.ceil((1 - available) * 60 / refill_per_minute)::integer);
  end if;

  update private.cortina_request_capacity
  set tokens = available - 1, updated_at = observed_at where bucket = p_bucket;
  return pg_catalog.jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end;
$$;

revoke all on function public.consume_cortina_request_capacity(text)
  from public, anon, authenticated, service_role;
grant execute on function public.consume_cortina_request_capacity(text) to service_role;


COMMIT;
