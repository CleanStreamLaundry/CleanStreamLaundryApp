begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $publication$
declare
  current_version text;
  revised_document jsonb;
begin
  select version, document into current_version, revised_document
  from public.loyalty_policy_documents
  where is_current
  for update;

  if current_version is distinct from '2026-10-02.1'
     or revised_document #>> '{sections,4,heading}' is distinct from '5. Stripe and Nayax' then
    raise exception 'Unexpected current loyalty publication; review before publishing'
      using errcode = '55000';
  end if;

  revised_document := jsonb_set(revised_document, '{effective_date}', '"2026-10-03"');
  revised_document := jsonb_set(revised_document, '{sections,4,paragraphs}', jsonb_build_array(
    'Stripe processes card payments and refunds made through the Clean Stream app and website. Nayax supports payments at participating machines and helps start connected washers and dryers. Clean Stream remains your contact for laundry-service, payment, and wallet issues.',
    'We share the information needed to process payments and operate machines with these providers, as described in our Privacy Policy.'
  ));

  update public.loyalty_policy_documents set is_current = false
  where version = current_version;
  insert into public.loyalty_policy_documents (version, document, is_current)
  values ('2026-10-03.1', revised_document, true);
end;
$publication$;
commit;
