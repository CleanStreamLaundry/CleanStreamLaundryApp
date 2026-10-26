-- Clean Stream's two existing pins were attached to the opposite addresses.
-- Census address matches confirm Madison is west and Columbus is east.
-- Preserve the precise existing pins, identities and machine membership.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '15s';

do $correction$
declare
  matched integer;
begin
  perform id from public."Locations" where id in (1, 2) order by id for update;
  select count(*) into matched from public."Locations"
  where (id = 1 and "Name" = 'Madison Ave.'
    and "Address" = '5330 Madison ave, Anderson, IN'
    and "Latitude" = 40.06415 and "Longitude" = -85.66733)
    or (id = 2 and "Name" = 'Columbus Ave.'
    and "Address" = '5107 South Columbus ave, Anderson, IN'
    and "Latitude" = 40.06097 and "Longitude" = -85.69173);
  if matched <> 2 then
    raise exception 'Location correction precondition changed; inspect before retry';
  end if;

  update public."Locations" set
    "Latitude" = case id when 1 then 40.06097 else 40.06415 end,
    "Longitude" = case id when 1 then -85.69173 else -85.66733 end
  where id in (1, 2);
end;
$correction$;
commit;

select id, "Name", "Address", "Latitude", "Longitude"
from public."Locations" where id in (1, 2) order by id;
