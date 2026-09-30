
alter table public.client_source_category_mappings
  add column source_code text,
  add column external_category_id text,
  add column original_path_hash text,
  add column garment_type_code text;

update public.client_source_category_mappings c
set source_code=s.code,
    external_category_id=sc.external_category_id,
    original_path_hash=encode(digest(lower(btrim(sc.original_path)), 'sha256'), 'hex'),
    garment_type_code=(
      select gt.code from public.garment_types gt where gt.id=c.garment_type_id
    )
from public.source_categories sc
join public.sources s on s.id=sc.source_id
where c.source_category_id=sc.id;

alter table public.client_source_category_mappings
  alter column source_code set not null,
  alter column original_path_hash set not null,
  add constraint client_source_category_mappings_source_code_fkey
    foreign key (source_code) references public.sources(code),
  add constraint client_source_category_mappings_garment_type_code_fkey
    foreign key (garment_type_code) references public.garment_types(code),
  add constraint client_source_category_mappings_path_hash_check
    check (original_path_hash ~ '^[0-9a-f]{64}$');

create index client_source_category_mappings_lookup_idx
  on public.client_source_category_mappings(source_code, original_path_hash)
  where mapping_status='confirmed';

create index client_source_category_mappings_external_lookup_idx
  on public.client_source_category_mappings(source_code, external_category_id)
  where external_category_id is not null and mapping_status='confirmed';

do $$
begin
  if (select count(*) from public.client_source_category_mappings) <> 2031 then
    raise exception 'Expected 2031 client mappings';
  end if;
  if exists (
    select 1 from public.client_source_category_mappings
    where source_code is null or original_path_hash is null
  ) then
    raise exception 'Client lookup key backfill failed';
  end if;
  if exists (
    select 1
    from public.client_source_category_mappings c
    join public.source_categories sc on sc.id=c.source_category_id
    join public.sources s on s.id=sc.source_id
    left join public.garment_types gt on gt.id=c.garment_type_id
    where c.source_code is distinct from s.code
       or c.external_category_id is distinct from sc.external_category_id
       or c.original_path_hash is distinct from encode(digest(lower(btrim(sc.original_path)), 'sha256'), 'hex')
       or c.garment_type_code is distinct from gt.code
  ) then
    raise exception 'Client lookup key verification failed';
  end if;
end $$;
;
