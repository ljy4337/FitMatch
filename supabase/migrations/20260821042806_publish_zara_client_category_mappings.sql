begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:publish-zara-client-category-mappings-v1'));

-- client_source_category_mappings is a denormalized client read table, not a
-- view. Publish the already-reviewed ZARA source mappings without changing any
-- other provider rows.
insert into public.client_source_category_mappings (
  source_category_id,
  garment_type_id,
  default_sleeve_class_code,
  default_pants_length_code,
  default_body_length_code,
  mapping_status,
  policy_version,
  source_code,
  external_category_id,
  original_path_hash,
  garment_type_code
)
select
  mapping.source_category_id,
  mapping.garment_type_id,
  mapping.default_sleeve_class_code,
  mapping.default_pants_length_code,
  mapping.default_body_length_code,
  mapping.mapping_status,
  mapping.policy_version,
  source.code,
  category.external_category_id,
  encode(extensions.digest(category.original_path, 'sha256'), 'hex'),
  garment.code
from public.source_category_mappings mapping
join public.source_categories category on category.id = mapping.source_category_id
join public.sources source on source.id = category.source_id
left join public.garment_types garment on garment.id = mapping.garment_type_id
where source.code = 'zara'
on conflict (source_category_id) do update set
  garment_type_id = excluded.garment_type_id,
  default_sleeve_class_code = excluded.default_sleeve_class_code,
  default_pants_length_code = excluded.default_pants_length_code,
  default_body_length_code = excluded.default_body_length_code,
  mapping_status = excluded.mapping_status,
  policy_version = excluded.policy_version,
  source_code = excluded.source_code,
  external_category_id = excluded.external_category_id,
  original_path_hash = excluded.original_path_hash,
  garment_type_code = excluded.garment_type_code,
  updated_at = now();

do $$
declare
  v_total integer;
  v_confirmed integer;
  v_review_required integer;
  v_rejected integer;
begin
  select
    count(*),
    count(*) filter (where mapping_status = 'confirmed'),
    count(*) filter (where mapping_status = 'review_required'),
    count(*) filter (where mapping_status = 'rejected')
  into v_total, v_confirmed, v_review_required, v_rejected
  from public.client_source_category_mappings
  where source_code = 'zara';

  if v_total <> 249 or v_confirmed <> 56
     or v_review_required <> 51 or v_rejected <> 142 then
    raise exception 'ZARA client mapping validation failed: total %, confirmed %, review %, rejected %',
      v_total, v_confirmed, v_review_required, v_rejected;
  end if;

  if exists (
    select 1
    from public.client_source_category_mappings client
    join public.source_category_mappings source_mapping
      on source_mapping.source_category_id = client.source_category_id
    where client.source_code = 'zara'
      and (
        client.mapping_status <> source_mapping.mapping_status
        or client.garment_type_id is distinct from source_mapping.garment_type_id
        or client.default_sleeve_class_code is distinct from source_mapping.default_sleeve_class_code
        or client.default_pants_length_code is distinct from source_mapping.default_pants_length_code
        or client.default_body_length_code is distinct from source_mapping.default_body_length_code
      )
  ) then
    raise exception 'ZARA client mapping parity validation failed';
  end if;
end $$;

commit;
;
