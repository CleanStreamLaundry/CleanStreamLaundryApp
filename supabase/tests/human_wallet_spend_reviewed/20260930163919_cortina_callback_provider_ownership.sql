-- Apply only in a transaction. Lock through preflight/index/trigger installation;
-- abort on ambiguous history instead of assigning, deleting or repairing it.
begin;
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
commit;
