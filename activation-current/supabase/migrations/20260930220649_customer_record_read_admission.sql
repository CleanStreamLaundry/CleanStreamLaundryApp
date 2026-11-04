-- Narrow ordinary-record SELECT gate. No data changes or financial RPC edits.
begin;

do $$
begin
  if current_user <> 'postgres'
    or to_regprocedure('private.account_access_allowed()') is null
    or to_regclass('private.account_lifecycle') is null
    or to_regprocedure('private.portal_record_access(text,jsonb)') is null
    or to_regprocedure('private.portal_record_access_before_authorization(text,jsonb)') is null then
    raise exception 'Reviewed canonical portal and lifecycle prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- The existing wrapper already gates staff. Extend that same canonical
-- eligibility requirement to customers before the legacy own-record shortcut.
-- Do not require Home/terms here: this is not a wallet-spend permission.
create or replace function private.portal_record_access(kind text, record jsonb)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.account_access_allowed() then return false; end if;
  return private.portal_record_access_before_authorization(kind, record);
end;
$$;

-- CREATE OR REPLACE preserves identity, policy bindings, ownership and ACLs.
commit;
