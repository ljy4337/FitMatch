-- Target ONLY FitMatch hnkplvyegonlhumlejst. User executes in that project's SQL Editor.
-- No category/metric/Closet/History/raw updates. Transaction fails atomically on drift.
-- Preserve raw-measurement semantics independently from comparison-group scope.
-- Prepared only: deploy through the normal migration workflow after isolated-DB verification.

begin;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
LOCK TABLE fitmatch_vnext.source_measurement_aliases IN SHARE ROW EXCLUSIVE MODE;
DO $guard$ BEGIN
IF md5(pg_get_functiondef(to_regprocedure('fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)'))) NOT IN ('87ff9eacdf8c981876ac8e3960135909','c59cc698167dc25362e043068b920670') OR to_regprocedure('fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)') IS NULL THEN RAISE EXCEPTION 'Function changed; stop and review: canonical_measurements_for_size_with_context'; END IF;
IF md5(pg_get_functiondef(to_regprocedure('fitmatch_vnext.product_measurement_readiness(uuid,jsonb)'))) NOT IN ('8d0e9a154cef553cebd3296d13bd4b32','4d9516769c12b658ab5ea05fae7b235f') OR to_regprocedure('fitmatch_vnext.product_measurement_readiness(uuid,jsonb)') IS NULL THEN RAISE EXCEPTION 'Function changed; stop and review: product_measurement_readiness'; END IF;
IF md5(pg_get_functiondef(to_regprocedure('fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric)'))) NOT IN ('26b5834f2f462b39ea842344de9dd3a7','299fe7dcc0862f438a5e49fb7327669f') OR to_regprocedure('fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric)') IS NULL THEN RAISE EXCEPTION 'Function changed; stop and review: resolve_measurement'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'tops' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.chest_width.chest_pit_to_pit','uniqlo.gathered_body_width.body_width_including_gather_and_tack')) THEN RAISE EXCEPTION 'Alias changed: 9156094f-2e30-4d6d-913a-0081f5169ad5'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'outerwear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.chest_width.chest_pit_to_pit','uniqlo.gathered_body_width.body_width_including_gather_and_tack')) THEN RAISE EXCEPTION 'Alias changed: 3e5b0fba-7f41-4c7c-b904-b66b8127e41b'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'dresses' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.chest_width.chest_pit_to_pit','uniqlo.gathered_body_width.body_width_including_gather_and_tack')) THEN RAISE EXCEPTION 'Alias changed: 2f5985d0-df46-4847-a2e5-0855df03c0af'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'underwear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.chest_width.chest_pit_to_pit','uniqlo.gathered_body_width.body_width_including_gather_and_tack')) THEN RAISE EXCEPTION 'Alias changed: 8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'chest-width-html' AND a.raw_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.normalized_label IS NOT DISTINCT FROM '몸 너비<br>(주름 및 박음질 포함)' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'homewear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.chest_width.chest_pit_to_pit','uniqlo.gathered_body_width.body_width_including_gather_and_tack')) THEN RAISE EXCEPTION 'Alias changed: 8f16f198-16ad-4ee6-984a-627d7d76a920'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'waist-petticoat-html' AND a.raw_label IS NOT DISTINCT FROM '허리 둘레 (상품 사이즈)<br> [페티코트]' AND a.normalized_label IS NOT DISTINCT FROM '허리 둘레 (상품 사이즈)<br> [페티코트]' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'skirts' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.waist_circumference.garment_waist_circumference','uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference')) THEN RAISE EXCEPTION 'Alias changed: 6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'size_chart' AND a.raw_code IS NOT DISTINCT FROM 'knit-body-length-front' AND a.raw_label IS NOT DISTINCT FROM '앞기장' AND a.normalized_label IS NOT DISTINCT FROM '앞기장' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'dresses' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.back_length.back_neck_to_hem','uniqlo.front_length.front_neck_to_hem')) THEN RAISE EXCEPTION 'Alias changed: 9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='74df726e-e236-4019-9548-6bc371ce5ad9'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'size_chart' AND a.raw_code IS NOT DISTINCT FROM 'knit-body-length-front' AND a.raw_label IS NOT DISTINCT FROM '앞기장' AND a.normalized_label IS NOT DISTINCT FROM '앞기장' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'underwear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.back_length.back_neck_to_hem','uniqlo.front_length.front_neck_to_hem')) THEN RAISE EXCEPTION 'Alias changed: 74df726e-e236-4019-9548-6bc371ce5ad9'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'size_chart' AND a.raw_code IS NOT DISTINCT FROM 'knit-body-length-front' AND a.raw_label IS NOT DISTINCT FROM '앞기장' AND a.normalized_label IS NOT DISTINCT FROM '앞기장' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'homewear' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.back_length.back_neck_to_hem','uniqlo.front_length.front_neck_to_hem')) THEN RAISE EXCEPTION 'Alias changed: 5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'; END IF;
IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a WHERE a.id='b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid AND a.source_code IS NOT DISTINCT FROM 'uniqlo' AND a.parser_code IS NOT DISTINCT FROM 'official_size_chart' AND a.raw_code IS NOT DISTINCT FROM 'skirt-length-html' AND a.raw_label IS NOT DISTINCT FROM '치마 길이<br> [페티코트]' AND a.normalized_label IS NOT DISTINCT FROM '치마 길이<br> [페티코트]' AND a.fitmatch_category_code IS NOT DISTINCT FROM 'skirts' AND a.garment_type_code IS NOT DISTINCT FROM NULL AND a.priority IS NOT DISTINCT FROM '10' AND a.is_verified IS NOT DISTINCT FROM true AND a.is_active IS NOT DISTINCT FROM true AND a.source_measurement_code IN ('uniqlo.total_length.waist_to_skirt_hem','uniqlo.petticoat_length.petticoat_waist_to_hem')) THEN RAISE EXCEPTION 'Alias changed: b86f0d4a-c767-43fd-8349-265e9ea123b6'; END IF;
END $guard$;


do $preflight$
declare
  required_sources integer;
  required_mappings integer;
  expected_aliases integer;
begin
  select count(*) into required_sources
  from fitmatch_vnext.source_measurements
  where source_measurement_code in (
    'uniqlo.front_length.front_neck_to_hem',
    'uniqlo.gathered_body_width.body_width_including_gather_and_tack',
    'uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference',
    'uniqlo.petticoat_length.petticoat_waist_to_hem'
  )
    and is_active;

  if required_sources <> 4 then
    raise exception 'Measurement semantic repair preflight failed: expected four active verified UNIQLO sources, found %', required_sources;
  end if;

  select count(*) into required_mappings
  from fitmatch_vnext.source_measurement_mappings smm
  join fitmatch_vnext.fitmatch_measurements fm
    on fm.measurement_code=smm.fitmatch_measurement_code and fm.is_active
  where smm.is_active and smm.is_verified
    and (smm.source_measurement_code, smm.fitmatch_measurement_code) in (
      ('uniqlo.front_length.front_neck_to_hem', 'front_length'),
      ('uniqlo.gathered_body_width.body_width_including_gather_and_tack', 'gathered_body_width'),
      ('uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference', 'petticoat_waist_circumference'),
      ('uniqlo.petticoat_length.petticoat_waist_to_hem', 'petticoat_length')
    );
  if required_mappings <> 4 then
    raise exception 'Measurement semantic repair preflight failed: expected four verified canonical mappings, found %', required_mappings;
  end if;

  with expected(id, parser_code, raw_code, raw_label, category_code) as (
    values
      ('9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid, 'official_size_chart', 'chest-width-html', '몸 너비<br>(주름 및 박음질 포함)', 'tops'),
      ('3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid, 'official_size_chart', 'chest-width-html', '몸 너비<br>(주름 및 박음질 포함)', 'outerwear'),
      ('2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid, 'official_size_chart', 'chest-width-html', '몸 너비<br>(주름 및 박음질 포함)', 'dresses'),
      ('8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid, 'official_size_chart', 'chest-width-html', '몸 너비<br>(주름 및 박음질 포함)', 'underwear'),
      ('8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid, 'official_size_chart', 'chest-width-html', '몸 너비<br>(주름 및 박음질 포함)', 'homewear'),
      ('6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid, 'official_size_chart', 'waist-petticoat-html', '허리 둘레 (상품 사이즈)<br> [페티코트]', 'skirts'),
      ('9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid, 'size_chart', 'knit-body-length-front', '앞기장', 'dresses'),
      ('74df726e-e236-4019-9548-6bc371ce5ad9'::uuid, 'size_chart', 'knit-body-length-front', '앞기장', 'underwear'),
      ('5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid, 'size_chart', 'knit-body-length-front', '앞기장', 'homewear'),
      ('b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid, 'official_size_chart', 'skirt-length-html', '치마 길이<br> [페티코트]', 'skirts')
  )
  select count(*) into expected_aliases
  from expected e
  join fitmatch_vnext.source_measurement_aliases a on a.id=e.id
  where a.parser_code=e.parser_code and a.raw_code=e.raw_code
    and a.raw_label=e.raw_label and a.fitmatch_category_code=e.category_code
    and a.is_active and a.is_verified;
  if expected_aliases <> 10 then
    raise exception 'Measurement semantic repair preflight failed: confirmed alias preimage drifted (%/10)', expected_aliases;
  end if;
end
$preflight$;

-- These are source-label-specific corrections.  They do not alter category
-- mappings, product classifications, comparison metrics, or history snapshots.
update fitmatch_vnext.source_measurement_aliases
set source_measurement_code = case id
  when '9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid then 'uniqlo.front_length.front_neck_to_hem'
  when '74df726e-e236-4019-9548-6bc371ce5ad9'::uuid then 'uniqlo.front_length.front_neck_to_hem'
  when '5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid then 'uniqlo.front_length.front_neck_to_hem'
  when '9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid then 'uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference'
  when 'b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid then 'uniqlo.petticoat_length.petticoat_waist_to_hem'
end
where id in (
  '9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid,
  '3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid,
  '2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid,
  '8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid,
  '8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid,
  '6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid,
  '9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid,
  '74df726e-e236-4019-9548-6bc371ce5ad9'::uuid,
  '5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid,
  'b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid
)
and source_measurement_code is distinct from case id
  when '9a7489ef-870c-4b13-8a2b-1e15fa8a3bcc'::uuid then 'uniqlo.front_length.front_neck_to_hem'
  when '74df726e-e236-4019-9548-6bc371ce5ad9'::uuid then 'uniqlo.front_length.front_neck_to_hem'
  when '5e8e11ea-27c4-47db-8dd2-0c9ba9513f46'::uuid then 'uniqlo.front_length.front_neck_to_hem'
  when '9156094f-2e30-4d6d-913a-0081f5169ad5'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '3e5b0fba-7f41-4c7c-b904-b66b8127e41b'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '2f5985d0-df46-4847-a2e5-0855df03c0af'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '8f95a832-e2c3-4e3a-bc46-eb7b562ce93b'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '8f16f198-16ad-4ee6-984a-627d7d76a920'::uuid then 'uniqlo.gathered_body_width.body_width_including_gather_and_tack'
  when '6dbe0706-4ffa-4509-8b7e-b283f1fb71e3'::uuid then 'uniqlo.petticoat_waist_circumference.petticoat_garment_waist_circumference'
  when 'b86f0d4a-c767-43fd-8349-265e9ea123b6'::uuid then 'uniqlo.petticoat_length.petticoat_waist_to_hem'
end;

-- A source can be normalized and retained while still being excluded from
-- score evidence.  Exact-code and alias lookup must therefore have identical
-- source eligibility: comparison eligibility belongs to policy metrics.
create or replace function fitmatch_vnext.resolve_measurement(
    p_source_code text,
    p_parser_code text,
    p_raw_measurement_code text,
    p_raw_label text,
    p_garment_type_code text default null,
    p_fitmatch_category_code text default null,
    p_raw_value numeric default null
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with exact_candidate as (
    select sm.source_measurement_code, 2147483647 effective_priority,
           'EXACT_CODE' resolution_path
    from fitmatch_vnext.source_measurements sm
    where p_raw_measurement_code is not null
      and sm.source_measurement_code = p_raw_measurement_code
      and sm.source_code = p_source_code
      and sm.is_active
), alias_candidates as (
    select a.source_measurement_code, a.priority::integer effective_priority,
           case when a.raw_code is not null then 'ALIAS_CODE' else 'ALIAS_LABEL' end
               resolution_path
    from fitmatch_vnext.source_measurement_aliases a
    where a.source_code = p_source_code
      and a.parser_code = p_parser_code
      and a.is_active and a.is_verified
      and (a.garment_type_code is null or a.garment_type_code = p_garment_type_code)
      and (a.fitmatch_category_code is null
           or a.fitmatch_category_code = p_fitmatch_category_code)
      and (
          (p_raw_measurement_code is not null and a.raw_code = p_raw_measurement_code)
          or
          (a.raw_code is null and a.normalized_label =
              fitmatch_vnext.normalize_measurement_label(p_raw_label))
      )
), candidates as (
    select * from exact_candidate
    union all
    select * from alias_candidates
    where not exists (select 1 from exact_candidate)
), top_candidates as (
    select c.*
    from candidates c
    where c.effective_priority = (select max(effective_priority) from candidates)
), candidate_summary as (
    select count(*) candidate_count,
           count(distinct source_measurement_code) outcome_count
    from top_candidates
), chosen as (
    select * from top_candidates order by source_measurement_code limit 1
), resolved as (
    select c.source_measurement_code, c.resolution_path,
           smm.fitmatch_measurement_code, smm.scale_factor, smm.offset_value,
           fm.canonical_unit_code, fm.canonical_basis_code,
           fm.representation_code, fm.body_region_code,
           s.candidate_count, s.outcome_count
    from candidate_summary s
    left join chosen c on true
    left join fitmatch_vnext.source_measurement_mappings smm
      on smm.source_measurement_code = c.source_measurement_code
     and smm.is_active and smm.is_verified
    left join fitmatch_vnext.fitmatch_measurements fm
      on fm.measurement_code = smm.fitmatch_measurement_code
     and fm.is_active
)
select jsonb_strip_nulls(jsonb_build_object(
    'resolution_status', case
        when candidate_count = 0 then 'UNMAPPED'
        when outcome_count > 1 then 'AMBIGUOUS'
        when fitmatch_measurement_code is null then 'MAPPING_REQUIRED'
        else 'RESOLVED' end,
    'resolution_path', case when outcome_count = 1 then resolution_path end,
    'source_measurement_code', case when outcome_count = 1 then source_measurement_code end,
    'fitmatch_measurement_code', case when outcome_count = 1 then fitmatch_measurement_code end,
    'canonical_value', case when outcome_count = 1 and fitmatch_measurement_code is not null
        and p_raw_value is not null then p_raw_value * scale_factor + offset_value end,
    'canonical_unit_code', case when outcome_count = 1 then canonical_unit_code end,
    'canonical_basis_code', case when outcome_count = 1 then canonical_basis_code end,
    'representation_code', case when outcome_count = 1 then representation_code end,
    'body_region_code', case when outcome_count = 1 then body_region_code end,
    'scale_factor', case when outcome_count = 1 then scale_factor end,
    'offset_value', case when outcome_count = 1 then offset_value end,
    'candidate_count', candidate_count,
    'resolver_version', 'fitmatch-vnext-measurement-resolver-v1'
))
from resolved;
$function$;

create or replace function fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_product_size_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
    actual_product_id uuid;
    context_source text;
begin
    select pv.product_id into actual_product_id
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = p_product_size_id;

    if actual_product_id is null then
        raise exception 'Product size not found';
    end if;

    if actual_product_id is distinct from
       (p_effective_classification ->> 'product_id')::uuid then
        raise exception 'Measurement context product mismatch';
    end if;

    context_source := p_effective_classification ->> 'effective_source';
    if context_source = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.canonical_measurements_for_size(p_product_size_id);
    end if;

    if context_source not in ('USER_EXPLICIT', 'CATEGORY_GROUP') then
        return jsonb_build_object(
            'product_size_id', p_product_size_id,
            'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
            'measurements', '[]'::jsonb,
            'raw_measurement_count', 0,
            'unresolved_count', 0,
            'semantic_conflict_count', 0,
            'classification_context_source', context_source
        );
    end if;

    -- Product-native aliases decide semantics first.  A verified context
    -- fallback is retained only for truly UNMAPPED native rows, preserving
    -- the existing detailed-category-missing recovery path without allowing a
    -- comparison group to overwrite a resolved raw measurement.
    return (
        with raw_rows as (
            select m.*, p.source_code,
                   p.garment_type_code native_garment_type_code,
                   native_gt.category_code native_category_code,
                   p_effective_classification ->> 'garment_type_code' context_garment_type_code,
                   p_effective_classification ->> 'category_code' context_category_code
            from fitmatch_vnext.product_size_measurements m
            join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
            join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
            join fitmatch_vnext.products p on p.id = pv.product_id
            left join fitmatch_vnext.garment_types native_gt
              on native_gt.garment_type_code = p.garment_type_code
            where m.product_size_id = p_product_size_id and m.is_current
        ), decisions as (
            select r.*,
                   fitmatch_vnext.resolve_measurement(
                     r.source_code, r.parser_code, r.raw_code, r.raw_label,
                     r.native_garment_type_code, r.native_category_code, r.raw_value
                   ) native_decision,
                   fitmatch_vnext.resolve_measurement(
                     r.source_code, r.parser_code, r.raw_code, r.raw_label,
                     r.context_garment_type_code, r.context_category_code, r.raw_value
                   ) context_decision
            from raw_rows r
        ), selected as (
            select d.*,
                   case when d.native_decision ->> 'resolution_status' = 'UNMAPPED'
                         and d.context_decision ->> 'resolution_status' = 'RESOLVED'
                        then d.context_decision
                        else d.native_decision
                   end decision
            from decisions d
        ), resolved as (
            select *, decision ->> 'fitmatch_measurement_code' canonical_code,
                   (decision ->> 'canonical_value')::numeric canonical_value
            from selected
            where decision ->> 'resolution_status' = 'RESOLVED'
        ), conflicts as (
            select canonical_code from resolved group by canonical_code
            having count(distinct canonical_value) > 1
        )
        select jsonb_build_object(
            'product_size_id', p_product_size_id,
            'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
            'measurements', coalesce((select jsonb_agg(jsonb_build_object(
                'product_size_measurement_id', r.id,
                'fitmatch_measurement_code', r.canonical_code,
                'value', r.canonical_value,
                'unit_code', r.decision ->> 'canonical_unit_code',
                'basis_code', r.decision ->> 'canonical_basis_code',
                'source_measurement_code', r.decision ->> 'source_measurement_code',
                'resolution_path', r.decision ->> 'resolution_path',
                'raw_evidence_fingerprint', r.evidence_fingerprint
            ) order by r.canonical_code, r.id)
            from resolved r
            where not exists (select 1 from conflicts c
                              where c.canonical_code = r.canonical_code)),
                '[]'::jsonb),
            'raw_measurement_count', (select count(*) from raw_rows),
            'unresolved_count', (select count(*) from selected
                where decision ->> 'resolution_status' <> 'RESOLVED'),
            'semantic_conflict_count', (select count(*) from conflicts),
            'classification_context_source', context_source
        )
    );
end
$function$;

-- Keep the existing readiness gate (one policy metric) while exposing the
-- total canonical count separately from the policy-selected count.
create or replace function fitmatch_vnext.product_measurement_readiness(
  p_product_id uuid,
  p_effective_classification jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
with product_row as (
  select p.*,
    p_effective_classification->>'classification_status' effective_status,
    p_effective_classification->>'comparison_policy_code' effective_policy_code,
    fitmatch_vnext.product_comparison_unit_decision(p.id) comparison_unit
  from fitmatch_vnext.products p where p.id=p_product_id
), policy_metrics as (
  select cm.fitmatch_measurement_code
  from product_row p
  join fitmatch_vnext.comparison_policies cp
    on cp.policy_code=p.effective_policy_code and cp.is_active
  join fitmatch_vnext.comparison_metrics cm
    on cm.comparison_policy_code=cp.policy_code
   and cm.metric_mode='CANONICAL' and cm.is_active
), size_diagnostics as (
  select ps.id product_size_id,ps.size_label,
    coalesce((canonical.payload->>'raw_measurement_count')::integer,0) raw_measurement_count,
    coalesce((canonical.payload->>'semantic_conflict_count')::integer,0) semantic_conflict_count,
    count(distinct measurement->>'fitmatch_measurement_code') canonical_measurement_count,
    count(distinct pm.fitmatch_measurement_code) policy_measurement_count
  from product_row p
  join fitmatch_vnext.product_variants pv on pv.product_id=p.id
  join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id
  cross join lateral (
    select fitmatch_vnext.canonical_measurements_for_size_with_context(
      ps.id,p_effective_classification
    ) payload
  ) canonical
  left join lateral jsonb_array_elements(canonical.payload->'measurements') measurement on true
  left join policy_metrics pm
    on pm.fitmatch_measurement_code=measurement->>'fitmatch_measurement_code'
  group by ps.id,ps.size_label,canonical.payload
), ready_sizes as (
  select * from size_diagnostics
  where semantic_conflict_count=0 and policy_measurement_count>=1
)
select case when not exists(select 1 from product_row) then
  jsonb_build_object(
    'status','CLASSIFICATION_REQUIRED','ready',false,
    'reason_code','CLASSIFICATION_REQUIRED','reason','Unknown product',
    'readiness_version','fitmatch-vnext-readiness-group-only-v1',
    'inventory_ignored_for_readiness',true
  )
else (
  select jsonb_build_object(
    'product_id',p.id,
    'ready',p.effective_status='CONFIRMED'
      and coalesce((p.comparison_unit->>'eligible')::boolean,false)
      and exists(select 1 from ready_sizes),
    'status',case
      when p.effective_status<>'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
      when not coalesce((p.comparison_unit->>'eligible')::boolean,false) then 'NOT_APPLICABLE'
      when not exists(select 1 from policy_metrics) then 'POLICY_UNAVAILABLE'
      when not exists(select 1 from size_diagnostics) then 'NO_AVAILABLE_SIZE'
      when not exists(select 1 from size_diagnostics where raw_measurement_count>0)
        then 'NO_MEASUREMENT_DATA'
      when not exists(select 1 from size_diagnostics
        where semantic_conflict_count=0 and policy_measurement_count>0)
        then 'INSUFFICIENT_MEASUREMENTS'
      else 'READY' end,
    'reason',case
      when p.effective_status<>'CONFIRMED' then 'Comparison group is required'
      when not coalesce((p.comparison_unit->>'eligible')::boolean,false)
        then p.comparison_unit->>'reason'
      when not exists(select 1 from policy_metrics) then 'No active comparison group policy metrics'
      when not exists(select 1 from size_diagnostics) then 'Product has no size rows'
      when not exists(select 1 from size_diagnostics where raw_measurement_count>0)
        then 'Product sizes have no raw measurement evidence'
      when not exists(select 1 from size_diagnostics
        where semantic_conflict_count=0 and policy_measurement_count>0)
        then 'No semantically usable group-policy measurement'
      else 'Comparison group and measurement evidence are ready' end,
    'comparison_policy_code',p.effective_policy_code,
    'comparison_unit',p.comparison_unit,
    'ready_sizes',coalesce((select jsonb_agg(jsonb_build_object(
      'product_size_id',r.product_size_id,'size_label',r.size_label,
      'resolved_measurement_count',r.policy_measurement_count,
      'canonical_measurement_count',r.canonical_measurement_count,
      'required_any_count',0,'semantic_conflict_count',r.semantic_conflict_count,
      'availability_status','UNKNOWN'
    ) order by r.size_label,r.product_size_id) from ready_sizes r),'[]'::jsonb),
    'size_diagnostics',coalesce((select jsonb_agg(jsonb_build_object(
      'product_size_id',d.product_size_id,'size_label',d.size_label,
      'raw_measurement_count',d.raw_measurement_count,
      'canonical_measurement_count',d.canonical_measurement_count,
      'policy_measurement_count',d.policy_measurement_count,
      'required_any_count',0,'semantic_conflict_count',d.semantic_conflict_count,
      'availability_status','UNKNOWN'
    ) order by d.size_label,d.product_size_id) from size_diagnostics d),'[]'::jsonb),
    'readiness_version','fitmatch-vnext-readiness-group-only-v1',
    'inventory_ignored_for_readiness',true,'minimum_common',1,'required_any_min',0
  ) from product_row p
)
end
$function$;

comment on function fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)
is 'Resolves raw semantics from product-native evidence first. Context is only a verified fallback for otherwise unmapped raw rows; comparison scope never overwrites a resolved measurement.';

commit;
