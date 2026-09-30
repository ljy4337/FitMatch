-- Authorized narrow repair; target hnkplvyegonlhumlejst (user-confirmed development, newly authorized).
-- ZARA method evidence: measurement master 08 rows 10/11, flat edge-to-edge.
-- No source/canonical/policy/retailer raw/Closet/history changes. Execute atomically.
DO $guard$
BEGIN
 IF pg_get_functiondef('fitmatch_vnext.product_comparison_group(uuid)'::regprocedure)
   NOT IN ($before$CREATE OR REPLACE FUNCTION fitmatch_vnext.product_comparison_group(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  product_row fitmatch_vnext.products%rowtype;
  mapping_row record;
  legacy_zara_key text;
begin
  select * into product_row
  from fitmatch_vnext.products p where p.id = p_product_id;
  if not found then return null; end if;

  select o.group_code, o.disposition, o.source_category_key,
         'PRODUCT_OVERRIDE'::text as mapping_source
    into mapping_row
  from fitmatch_catalog.product_comparison_group_overrides o
  where o.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
    and o.source_code = product_row.source_code
    and o.external_product_id = product_row.source_product_key
  limit 1;

  if not found then
    if product_row.source_code='zara'
       and nullif(product_row.source_extra->>'family_id','') is not null
       and nullif(product_row.source_extra->>'subfamily_id','') is not null then
      legacy_zara_key := 'zara-legacy:'
        || (product_row.source_extra->>'family_id') || ':'
        || (product_row.source_extra->>'subfamily_id');
    end if;

    select m.group_code, m.disposition, m.source_category_key,
           'RETAILER_CATEGORY'::text as mapping_source
      into mapping_row
    from fitmatch_catalog.source_category_comparison_groups m
    where m.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
      and m.source_code = product_row.source_code
      and (
        array_to_string(m.category_path, ' > ') =
          product_row.source_extra ->> 'source_category_path'
        or array_to_string(
          m.category_path[2:cardinality(m.category_path)], ' > '
        ) = product_row.source_extra ->> 'source_category_path'
        or m.source_category_key = legacy_zara_key
      )
    order by case when m.source_category_key=legacy_zara_key then 0 else 1 end
    limit 1;
  end if;

  if not found then
    return jsonb_build_object(
      'status', 'REVIEW', 'group_code', null, 'display_name', null,
      'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
      'mapping_source', 'UNMAPPED'
    );
  end if;

  return jsonb_build_object(
    'status', mapping_row.disposition,
    'group_code', case when mapping_row.group_code in ('A','B','C','D','E','F','G')
      then mapping_row.group_code else null end,
    'display_name', (select g.display_name from fitmatch_catalog.comparison_groups g
      where g.group_code = mapping_row.group_code),
    'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
    'mapping_source', mapping_row.mapping_source,
    'source_category_key', mapping_row.source_category_key
  );
end
$function$
$before$, $after$CREATE OR REPLACE FUNCTION fitmatch_vnext.product_comparison_group(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  product_row fitmatch_vnext.products%rowtype;
  mapping_row record;
  legacy_zara_key text;
begin
  select * into product_row
  from fitmatch_vnext.products p where p.id = p_product_id;
  if not found then return null; end if;

  select o.group_code, o.disposition, o.source_category_key,
         'PRODUCT_OVERRIDE'::text as mapping_source
    into mapping_row
  from fitmatch_catalog.product_comparison_group_overrides o
  where o.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
    and o.source_code = product_row.source_code
    and o.external_product_id = product_row.source_product_key
  limit 1;

  if not found then
    if product_row.source_code='zara'
       and nullif(product_row.source_extra->>'family_id','') is not null
       and nullif(product_row.source_extra->>'subfamily_id','') is not null then
      legacy_zara_key := 'zara-legacy:'
        || (product_row.source_extra->>'family_id') || ':'
        || (product_row.source_extra->>'subfamily_id');
    end if;

    select m.group_code, m.disposition, m.source_category_key,
           'RETAILER_CATEGORY'::text as mapping_source
      into mapping_row
    from fitmatch_catalog.source_category_comparison_groups m
    where m.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
      and m.source_code = product_row.source_code
      and (
        array_to_string(m.category_path, ' > ') =
          product_row.source_extra ->> 'source_category_path'
        or array_to_string(
          m.category_path[2:cardinality(m.category_path)], ' > '
        ) = product_row.source_extra ->> 'source_category_path'
        -- Exact compatibility for two verified UNIQLO breadcrumb renames.
        -- Keep original paths and product overrides; never infer from a leaf/name.
        or (
          product_row.source_code = 'uniqlo'
          and m.source_category_key in (
            'uniqlo:57892:95354:95362:95381',
            'uniqlo:57892:95354:95362:95388'
          )
          and m.category_path[1:3] =
            ARRAY['WOMEN','셔츠 & 블라우스','셔츠 & 블라우스']::text[]
          and product_row.source_extra ->> 'source_category_path' in (
            array_to_string(ARRAY['셔츠 & 블라우스 & 폴로셔츠']
              || m.category_path[3:cardinality(m.category_path)], ' > '),
            array_to_string(ARRAY['WOMEN','셔츠 & 블라우스 & 폴로셔츠']
              || m.category_path[3:cardinality(m.category_path)], ' > ')
          )
        )
        or m.source_category_key = legacy_zara_key
      )
    order by case when m.source_category_key=legacy_zara_key then 0 else 1 end
    limit 1;
  end if;

  if not found then
    return jsonb_build_object(
      'status', 'REVIEW', 'group_code', null, 'display_name', null,
      'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
      'mapping_source', 'UNMAPPED'
    );
  end if;

  return jsonb_build_object(
    'status', mapping_row.disposition,
    'group_code', case when mapping_row.group_code in ('A','B','C','D','E','F','G')
      then mapping_row.group_code else null end,
    'display_name', (select g.display_name from fitmatch_catalog.comparison_groups g
      where g.group_code = mapping_row.group_code),
    'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
    'mapping_source', mapping_row.mapping_source,
    'source_category_key', mapping_row.source_category_key
  );
end
$function$
$after$)
 THEN RAISE EXCEPTION 'Group function drift; review before applying'; END IF;
 IF (SELECT count(*) FROM fitmatch_catalog.source_category_comparison_groups
 WHERE policy_version='retailer-comparison-groups-v3-seven-20260911'
 AND source_category_key IN ('uniqlo:57892:95354:95362:95381','uniqlo:57892:95354:95362:95388')
 AND source_code='uniqlo' AND group_code='A' AND disposition='COMPARABLE') <> 2
 THEN RAISE EXCEPTION 'UNIQLO mapping prerequisites changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION fitmatch_vnext.product_comparison_group(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  product_row fitmatch_vnext.products%rowtype;
  mapping_row record;
  legacy_zara_key text;
begin
  select * into product_row
  from fitmatch_vnext.products p where p.id = p_product_id;
  if not found then return null; end if;

  select o.group_code, o.disposition, o.source_category_key,
         'PRODUCT_OVERRIDE'::text as mapping_source
    into mapping_row
  from fitmatch_catalog.product_comparison_group_overrides o
  where o.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
    and o.source_code = product_row.source_code
    and o.external_product_id = product_row.source_product_key
  limit 1;

  if not found then
    if product_row.source_code='zara'
       and nullif(product_row.source_extra->>'family_id','') is not null
       and nullif(product_row.source_extra->>'subfamily_id','') is not null then
      legacy_zara_key := 'zara-legacy:'
        || (product_row.source_extra->>'family_id') || ':'
        || (product_row.source_extra->>'subfamily_id');
    end if;

    select m.group_code, m.disposition, m.source_category_key,
           'RETAILER_CATEGORY'::text as mapping_source
      into mapping_row
    from fitmatch_catalog.source_category_comparison_groups m
    where m.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
      and m.source_code = product_row.source_code
      and (
        array_to_string(m.category_path, ' > ') =
          product_row.source_extra ->> 'source_category_path'
        or array_to_string(
          m.category_path[2:cardinality(m.category_path)], ' > '
        ) = product_row.source_extra ->> 'source_category_path'
        -- Exact compatibility for two verified UNIQLO breadcrumb renames.
        -- Keep original paths and product overrides; never infer from a leaf/name.
        or (
          product_row.source_code = 'uniqlo'
          and m.source_category_key in (
            'uniqlo:57892:95354:95362:95381',
            'uniqlo:57892:95354:95362:95388'
          )
          and m.category_path[1:3] =
            ARRAY['WOMEN','셔츠 & 블라우스','셔츠 & 블라우스']::text[]
          and product_row.source_extra ->> 'source_category_path' in (
            array_to_string(ARRAY['셔츠 & 블라우스 & 폴로셔츠']
              || m.category_path[3:cardinality(m.category_path)], ' > '),
            array_to_string(ARRAY['WOMEN','셔츠 & 블라우스 & 폴로셔츠']
              || m.category_path[3:cardinality(m.category_path)], ' > ')
          )
        )
        or m.source_category_key = legacy_zara_key
      )
    order by case when m.source_category_key=legacy_zara_key then 0 else 1 end
    limit 1;
  end if;

  if not found then
    return jsonb_build_object(
      'status', 'REVIEW', 'group_code', null, 'display_name', null,
      'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
      'mapping_source', 'UNMAPPED'
    );
  end if;

  return jsonb_build_object(
    'status', mapping_row.disposition,
    'group_code', case when mapping_row.group_code in ('A','B','C','D','E','F','G')
      then mapping_row.group_code else null end,
    'display_name', (select g.display_name from fitmatch_catalog.comparison_groups g
      where g.group_code = mapping_row.group_code),
    'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
    'mapping_source', mapping_row.mapping_source,
    'source_category_key', mapping_row.source_category_key
  );
end
$function$;

DO $aliases$
DECLARE r record; d jsonb;
BEGIN
 FOR r IN SELECT * FROM (VALUES
 ('zone-name-waist','zara.waist_width.waist_edge_to_edge','waist_width','waist_edge_to_edge'),
 ('zone-name-hips','zara.hip_width.hip_at_widest','hip_width','hip_at_widest')
 ) v(raw,source_key,canonical,basis) LOOP
 IF NOT EXISTS (
 SELECT 1 FROM fitmatch_vnext.source_measurements s
 JOIN fitmatch_vnext.source_measurement_mappings m USING(source_measurement_code)
 JOIN fitmatch_vnext.fitmatch_measurements f ON f.measurement_code=m.fitmatch_measurement_code
 WHERE s.source_measurement_code=r.source_key AND s.source_code='zara'
 AND s.measurement_kind='GARMENT_ACTUAL' AND s.native_unit_code='cm'
 AND s.measurement_basis_code=r.basis AND s.representation_code='FLAT_WIDTH'
 AND s.is_active AND s.is_comparable AND m.is_active AND m.is_verified
 AND m.fitmatch_measurement_code=r.canonical AND m.scale_factor=1 AND m.offset_value=0
 AND f.canonical_basis_code=r.basis AND f.canonical_unit_code='cm'
 AND f.representation_code='FLAT_WIDTH' AND f.is_active)
 THEN RAISE EXCEPTION 'ZARA measurement prerequisite changed: %',r.raw; END IF;
 IF EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases a
 WHERE a.source_code='zara' AND a.parser_code='zara_kr_size_measure_guide_v1'
 AND (a.raw_code=r.raw OR (a.raw_code IS NULL AND a.normalized_label=r.raw))
 AND (a.fitmatch_category_code IS NULL OR a.fitmatch_category_code='skirts')
 AND (a.source_measurement_code IS DISTINCT FROM r.source_key
 OR NOT a.is_active OR NOT a.is_verified OR a.garment_type_code IS NOT NULL))
 THEN RAISE EXCEPTION 'Conflicting skirt alias: %',r.raw; END IF;
 INSERT INTO fitmatch_vnext.source_measurement_aliases
 (source_code,parser_code,raw_code,raw_label,normalized_label,fitmatch_category_code,
 garment_type_code,source_measurement_code,priority,is_verified,is_active)
 SELECT 'zara','zara_kr_size_measure_guide_v1',r.raw,r.raw,r.raw,'skirts',NULL,r.source_key,30,true,true
 WHERE NOT EXISTS (SELECT 1 FROM fitmatch_vnext.source_measurement_aliases
 WHERE source_code='zara' AND parser_code='zara_kr_size_measure_guide_v1'
 AND raw_code=r.raw AND fitmatch_category_code='skirts' AND garment_type_code IS NULL);
 d:=fitmatch_vnext.resolve_measurement('zara','zara_kr_size_measure_guide_v1',
 r.raw,r.raw,'comparison_group_skirt','skirts',17);
 IF d->>'resolution_status' IS DISTINCT FROM 'RESOLVED'
 OR d->>'fitmatch_measurement_code' IS DISTINCT FROM r.canonical
 OR (d->>'canonical_value')::numeric IS DISTINCT FROM 17::numeric
 THEN RAISE EXCEPTION 'Skirt resolver postcondition failed: %',r.raw; END IF;
 END LOOP;
END $aliases$;
