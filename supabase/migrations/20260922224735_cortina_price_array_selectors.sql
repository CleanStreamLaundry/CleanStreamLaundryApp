begin;

alter table public.cortina_machine_config add column product_codes jsonb;
alter table public.cortina_vend_sessions add column product_code integer
  check (product_code between 0 and 32767);

create function public.valid_cortina_product_codes(codes jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare item record;
begin
  if codes is null then return true; end if;
  if jsonb_typeof(codes) <> 'object' then return false; end if;
  for item in select key, value from jsonb_each(codes) loop
    if item.key !~ '^[1-9][0-9]*$' or jsonb_typeof(item.value) <> 'number' then
      return false;
    end if;
    if (item.value::text)::numeric < 0 or (item.value::text)::numeric > 32767
       or trunc((item.value::text)::numeric) <> (item.value::text)::numeric then
      return false;
    end if;
  end loop;
  return true;
end;
$$;
revoke all on function public.valid_cortina_product_codes(jsonb) from public;
grant execute on function public.valid_cortina_product_codes(jsonb) to authenticated, service_role;

alter table public.cortina_machine_config
  add constraint cortina_product_codes_valid check (public.valid_cortina_product_codes(product_codes)),
  add constraint cortina_selector_exclusive check (product_codes is null or pulse_line_number is null),
  drop constraint cortina_machine_identifier_required;
alter table public.cortina_machine_config
  add constraint cortina_machine_identifier_required check (
    not is_enabled or (
      (nullif(btrim(nayax_terminal_id), '') is not null or nullif(btrim(nayax_uniqr), '') is not null)
      and ((product_codes is null and pulse_line_number is not null)
        or (product_codes is not null and product_codes <> '{}'::jsonb))
      and not review_required
    )
  );

-- Preserve the selector used by existing unpaid/in-progress washer quotes.
update public.cortina_vend_sessions s set pulse_line_number = c.pulse_line_number
from public.cortina_machine_config c
where c.machine_id = s.machine_id and s.pulse_line_number is null
  and s.status in ('payment_pending', 'paid', 'starting', 'awaiting_sale', 'approved');
alter table public.cortina_vend_sessions add constraint cortina_session_selector_exclusive
  check (product_code is null or pulse_line_number is null);

comment on column public.cortina_machine_config.product_codes is
  'NULL uses PulseLineNumber; otherwise maps integer-cent prices to zero-based Nayax price-array Codes. Missing prices must not vend.';
comment on column public.cortina_vend_sessions.product_code is
  'Nayax price-array Code snapshotted before payment. Mutually exclusive with pulse_line_number.';

commit;
