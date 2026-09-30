-- User-authorized development repair. Exact parent/category IDs; retain unmapped recovery.
DO $guard$ BEGIN IF pg_get_functiondef('fitmatch_vnext.product_comparison_group(uuid)'::regprocedure) NOT IN ($original$CREATE OR REPLACE FUNCTION fitmatch_vnext.product_comparison_group(p_product_id uuid)
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
$original$, $updated$CREATE OR REPLACE FUNCTION fitmatch_vnext.product_comparison_group(p_product_id uuid)
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
$updated$) THEN RAISE EXCEPTION 'product_comparison_group drift: re-audit before applying'; END IF; END $guard$;
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
