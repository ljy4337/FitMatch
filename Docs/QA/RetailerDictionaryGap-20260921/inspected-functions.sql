CREATE OR REPLACE FUNCTION fitmatch_vnext.normalize_measurement_label(p_label text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
    select nullif(lower(regexp_replace(btrim(coalesce(p_label, '')), '\s+', ' ', 'g')), '');
$function$


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
        -- Exact official category IDs precede presentation-path compatibility.
        (product_row.source_code = 'zara'
         and product_row.source_extra #>> '{structured_facts,retailer_api,details,product,id}' = product_row.source_product_key
         and m.source_category_key = concat('zara:',
           product_row.source_extra #>> '{structured_facts,retailer_api,details,product,section}', ':',
           product_row.source_extra #>> '{structured_facts,retailer_api,details,product,familyId}', ':',
           product_row.source_extra #>> '{structured_facts,retailer_api,details,product,subfamilyId}'))
        or array_to_string(m.category_path, ' > ') =
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
    order by case
      when product_row.source_code = 'zara'
        and product_row.source_extra #>> '{structured_facts,retailer_api,details,product,id}' = product_row.source_product_key
        and m.source_category_key = concat('zara:',
          product_row.source_extra #>> '{structured_facts,retailer_api,details,product,section}', ':',
          product_row.source_extra #>> '{structured_facts,retailer_api,details,product,familyId}', ':',
          product_row.source_extra #>> '{structured_facts,retailer_api,details,product,subfamilyId}') then 0
      when m.source_category_key=legacy_zara_key then 1 else 2 end
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


CREATE OR REPLACE FUNCTION fitmatch_vnext.resolve_measurement(p_source_code text, p_parser_code text, p_raw_measurement_code text, p_raw_label text, p_garment_type_code text DEFAULT NULL::text, p_fitmatch_category_code text DEFAULT NULL::text, p_raw_value numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with exact_candidate as (
    select sm.source_measurement_code, 2147483647 effective_priority,
           'EXACT_CODE' resolution_path
    from fitmatch_vnext.source_measurements sm
    where p_raw_measurement_code is not null
      and sm.source_measurement_code = p_raw_measurement_code
      and sm.source_code = p_source_code
      and sm.is_active and sm.is_comparable
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
    'source_measurement_code', case when outcome_count = 1
        then source_measurement_code end,
    'fitmatch_measurement_code', case when outcome_count = 1
        then fitmatch_measurement_code end,
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
$function$


CREATE OR REPLACE FUNCTION fitmatch_vnext.canonical_measurements_for_size(p_product_size_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with raw_rows as (
    select m.*, p.source_code, p.garment_type_code, gt.category_code
    from fitmatch_vnext.product_size_measurements m
    join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where m.product_size_id = p_product_size_id
      and m.is_current
), decisions as (
    select r.*,
           fitmatch_vnext.resolve_measurement(
               r.source_code, r.parser_code, r.raw_code, r.raw_label,
               r.garment_type_code, r.category_code, r.raw_value
           ) decision
    from raw_rows r
), resolved as (
    select *, decision ->> 'fitmatch_measurement_code' canonical_code,
           (decision ->> 'canonical_value')::numeric canonical_value
    from decisions
    where decision ->> 'resolution_status' = 'RESOLVED'
), conflicts as (
    select canonical_code
    from resolved
    group by canonical_code
    having count(distinct canonical_value) > 1
)
select jsonb_build_object(
    'product_size_id', p_product_size_id,
    'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
    'measurements', coalesce((
        select jsonb_agg(
            jsonb_build_object(
                'product_size_measurement_id', r.id,
                'fitmatch_measurement_code', r.canonical_code,
                'value', r.canonical_value,
                'unit_code', r.decision ->> 'canonical_unit_code',
                'basis_code', r.decision ->> 'canonical_basis_code',
                'source_measurement_code', r.decision ->> 'source_measurement_code',
                'resolution_path', r.decision ->> 'resolution_path',
                'raw_evidence_fingerprint', r.evidence_fingerprint
            ) order by r.canonical_code, r.id
        )
        from resolved r
        where not exists (
            select 1 from conflicts c where c.canonical_code = r.canonical_code
        )
    ), '[]'::jsonb),
    'raw_measurement_count', (select count(*) from raw_rows),
    'unresolved_count', (select count(*) from decisions
        where decision ->> 'resolution_status' <> 'RESOLVED'),
    'semantic_conflict_count', (select count(*) from conflicts)
);
$function$


CREATE OR REPLACE FUNCTION fitmatch_vnext.canonical_measurements_for_size_with_context(p_product_size_id uuid, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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

    -- USER_EXPLICIT and CATEGORY_GROUP both resolve only through the existing,
    -- verified source aliases/mappings. CATEGORY_GROUP chooses the broad
    -- comparison group from retailer category; it does not invent a detailed
    -- garment type or a canonical measurement.
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

    return (
        with raw_rows as (
            select m.*, p.source_code,
                   p_effective_classification ->> 'garment_type_code'
                       garment_type_code,
                   p_effective_classification ->> 'category_code' category_code
            from fitmatch_vnext.product_size_measurements m
            join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
            join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
            join fitmatch_vnext.products p on p.id = pv.product_id
            where m.product_size_id = p_product_size_id and m.is_current
        ), decisions as (
            select r.*, fitmatch_vnext.resolve_measurement(
                r.source_code, r.parser_code, r.raw_code, r.raw_label,
                r.garment_type_code, r.category_code, r.raw_value
            ) decision
            from raw_rows r
        ), resolved as (
            select *, decision ->> 'fitmatch_measurement_code' canonical_code,
                   (decision ->> 'canonical_value')::numeric canonical_value
            from decisions
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
            'unresolved_count', (select count(*) from decisions
                where decision ->> 'resolution_status' <> 'RESOLVED'),
            'semantic_conflict_count', (select count(*) from conflicts),
            'classification_context_source', context_source
        )
    );
end
$function$

