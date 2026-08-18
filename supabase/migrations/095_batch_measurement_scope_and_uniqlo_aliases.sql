begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:batch-measurement-scope-v1'));

-- Classify first, then use the canonical major category to disambiguate raw
-- labels such as Musinsa's "허리단면" (top waist vs pants waist).
create or replace function fitmatch_catalog.runtime_ingest_product_payload(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_catalog
as $$
declare
  v_product_id uuid;
  v_variant jsonb;
  v_size jsonb;
  v_measurement jsonb;
  v_variant_id uuid;
  v_size_id uuid;
  v_category_scope text;
  v_variants integer := 0;
  v_sizes integer := 0;
  v_measurements integer := 0;
begin
  v_product_id := fitmatch_catalog.runtime_upsert_product(p_payload);
  select h.category_code into v_category_scope
  from fitmatch_catalog.product_classification_history h
  where h.product_id = v_product_id and h.is_current;

  for v_variant in
    select value from jsonb_array_elements(
      case when jsonb_typeof(p_payload->'variants')='array'
        then p_payload->'variants'
        else jsonb_build_array(jsonb_build_object(
          'external_variant_id','__default__',
          'sizes',coalesce(p_payload->'sizes','[]'::jsonb)
        )) end
    )
  loop
    v_variant_id := fitmatch_catalog.runtime_upsert_variant(v_product_id,v_variant);
    v_variants := v_variants + 1;
    for v_size in
      select value from jsonb_array_elements(
        case when jsonb_typeof(v_variant->'sizes')='array'
          then v_variant->'sizes' else '[]'::jsonb end
      )
    loop
      v_size_id := fitmatch_catalog.runtime_upsert_size(v_variant_id,v_size);
      v_sizes := v_sizes + 1;
      for v_measurement in
        select value from jsonb_array_elements(
          case when jsonb_typeof(v_size->'measurements')='array'
            then v_size->'measurements' else '[]'::jsonb end
        )
      loop
        perform fitmatch_catalog.runtime_upsert_measurement(
          v_size_id,
          case
            when nullif(v_measurement->>'category_scope','') is not null
              or v_category_scope is null then v_measurement
            else v_measurement || jsonb_build_object('category_scope',v_category_scope)
          end
        );
        v_measurements := v_measurements + 1;
      end loop;
    end loop;
  end loop;

  return jsonb_build_object(
    'product_id',v_product_id,
    'variants_processed',v_variants,
    'sizes_processed',v_sizes,
    'measurements_processed',v_measurements
  );
end $$;

create or replace function public.fitmatch_batch_ingest_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  v_ingest jsonb;
  v_promotion jsonb;
  v_comparison_ready boolean;
begin
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'payload_must_be_object';
  end if;
  if coalesce(p_payload->'raw_payload'->>'batch_ingest_version', '') = '' then
    raise exception using errcode = '22023', message = 'batch_ingest_version_required';
  end if;

  v_promotion := fitmatch_catalog.runtime_resolve_and_promote_product(p_payload);
  v_ingest := fitmatch_catalog.runtime_ingest_product_payload(p_payload);
  select (v_promotion->'classification'->>'classification_status' = 'confirmed') and exists (
    select 1
    from fitmatch_catalog.product_variants v
    join fitmatch_catalog.product_sizes s on s.variant_id = v.id and s.is_active
    join fitmatch_catalog.product_measurements m
      on m.product_size_id = s.id and m.is_comparable
    where v.product_id = (v_promotion->>'product_id')::uuid and v.is_active
  ) into v_comparison_ready;

  return v_promotion || jsonb_build_object(
    'variants_processed', coalesce((v_ingest->>'variants_processed')::integer, 0),
    'sizes_processed', coalesce((v_ingest->>'sizes_processed')::integer, 0),
    'measurements_processed', coalesce((v_ingest->>'measurements_processed')::integer, 0),
    'comparison_ready', coalesce(v_comparison_ready, false)
  );
end $$;

insert into fitmatch_taxonomy.source_measurement_aliases (
  source_code, parser_code, raw_code, raw_label, normalized_raw_label,
  measurement_code, raw_representation, comparison_basis,
  conversion_multiplier, category_scopes, is_comparable, evidence, policy_version
) values
  ('uniqlo','official_size_chart','product-length','전체 길이','전체 길이','back_length','back_neck_to_hem','back_neck_to_hem',1,array['tops','outerwear','dresses','underwear','homewear'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','product-length','전체 길이','전체 길이','total_length','waist_to_skirt_hem','waist_to_skirt_hem',1,array['skirts'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','chest-width','가슴너비','가슴너비','chest_width','chest_pit_to_pit','chest_pit_to_pit',1,array['tops','outerwear','dresses','underwear','homewear'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','sleeve-center-back','등 중심부터 소매까지 길이','등 중심부터 소매까지 길이','sleeve_length','sleeve_center_back_to_cuff',null,1,array['tops','outerwear'],false,'Different basis from shoulder-seam sleeve length','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','shoulder-seam','어깨너비(솔기에서 솔기까지)','어깨너비(솔기에서 솔기까지)','shoulder_width','shoulder_seam_to_seam','shoulder_seam_to_seam',1,array['tops','outerwear'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','hip-circumference','엉덩이 둘레','엉덩이 둘레','hip_circumference','garment_hip_circumference','hip_at_widest',0.5,array['bottoms','skirts'],true,'Circumference converted to comparison width','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','waist-circumference','허리 둘레','허리 둘레','waist_circumference','garment_waist_circumference','waist_edge_to_edge',0.5,array['bottoms','skirts'],true,'Circumference converted to comparison width','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','inseam','다리 길이','다리 길이','inseam','crotch_to_inner_hem','crotch_to_inner_hem',1,array['bottoms'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','chest-width-html','몸 너비<br>(주름 및 박음질 포함)','몸 너비<br>(주름 및 박음질 포함)','chest_width','chest_pit_to_pit','chest_pit_to_pit',1,array['tops','outerwear','dresses','underwear','homewear'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','skirt-length-html','치마 길이<br> [페티코트]','치마 길이<br> [페티코트]','total_length','waist_to_skirt_hem','waist_to_skirt_hem',1,array['skirts'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','waist-html','허리<br>[하의]','허리<br>[하의]','waist_circumference','garment_waist_circumference','waist_edge_to_edge',0.5,array['bottoms','skirts'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1'),
  ('uniqlo','official_size_chart','waist-petticoat-html','허리 둘레 (상품 사이즈)<br> [페티코트]','허리 둘레 (상품 사이즈)<br> [페티코트]','waist_circumference','garment_waist_circumference','waist_edge_to_edge',0.5,array['skirts'],true,'UNIQLO KR official sizeChart label','db-runtime-2026-08-18-v1')
on conflict (source_code, raw_label, measurement_code, policy_version)
do update set
  parser_code=excluded.parser_code,
  raw_code=excluded.raw_code,
  normalized_raw_label=excluded.normalized_raw_label,
  raw_representation=excluded.raw_representation,
  comparison_basis=excluded.comparison_basis,
  conversion_multiplier=excluded.conversion_multiplier,
  category_scopes=excluded.category_scopes,
  is_comparable=excluded.is_comparable,
  evidence=excluded.evidence;

revoke all on function fitmatch_catalog.runtime_ingest_product_payload(jsonb)
  from public, anon, authenticated;
grant execute on function fitmatch_catalog.runtime_ingest_product_payload(jsonb)
  to service_role;
revoke all on function public.fitmatch_batch_ingest_product(jsonb)
  from public, anon, authenticated;
grant execute on function public.fitmatch_batch_ingest_product(jsonb)
  to service_role;

commit;
