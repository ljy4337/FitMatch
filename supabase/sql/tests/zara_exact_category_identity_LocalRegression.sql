BEGIN;
CREATE TEMP TABLE zara_repair_before AS SELECT id,fitmatch_vnext.product_comparison_group(id) AS result FROM fitmatch_vnext.products;
INSERT INTO fitmatch_vnext.products(id,source_code,source_product_key,source_extra) VALUES ('e20d50a3-62dc-4635-b764-babdc9fe4072','zara','564222870','{"source_category_path":"ZARA > 남성 > 스웨트 셔츠 > F. Sudadera","structured_facts":{"retailer_api":{"details":{"product":{"id":564222870,"section":2,"familyId":2796,"subfamilyId":12475}}}}}'::jsonb) ON CONFLICT(id) DO UPDATE SET source_extra=excluded.source_extra;
INSERT INTO fitmatch_vnext.products(id,source_code,source_product_key,source_extra) VALUES ('8ab8f7bc-8e74-41ef-9fc5-e786a3d21d8a','zara','564203652','{"source_category_path":"ZARA > 남성 > 스웨트 셔츠 > F. Sudadera","structured_facts":{"retailer_api":{"details":{"product":{"id":564203652,"section":2,"familyId":2796,"subfamilyId":12475}}}}}'::jsonb) ON CONFLICT(id) DO UPDATE SET source_extra=excluded.source_extra;
INSERT INTO fitmatch_vnext.products(id,source_code,source_product_key,source_extra) VALUES ('fb4dff88-ff34-448f-877d-24480d64af86','zara','551126671','{"source_category_path":"ZARA > 남성 > 스웨트 셔츠 > B. Sudadera","structured_facts":{"retailer_api":{"details":{"product":{"id":551126671,"section":2,"familyId":2796,"subfamilyId":12474}}}}}'::jsonb) ON CONFLICT(id) DO UPDATE SET source_extra=excluded.source_extra;
INSERT INTO fitmatch_vnext.products(id,source_code,source_product_key,source_extra) VALUES ('542767aa-9556-4c34-9902-549284d96ce6','zara','545450451','{"source_category_path":"ZARA > 남성 > 스웨터 > B. Jersey M/C","structured_facts":{"retailer_api":{"details":{"product":{"id":545450451,"section":2,"familyId":82,"subfamilyId":12490}}}}}'::jsonb) ON CONFLICT(id) DO UPDATE SET source_extra=excluded.source_extra;
INSERT INTO fitmatch_vnext.products(id,source_code,source_product_key,source_extra) VALUES ('dcfb88de-bd85-4db6-9d38-be13fd11136f','zara','547804819','{"source_category_path":"ZARA > 남성 > 바지 > B. Pant Denim","structured_facts":{"retailer_api":{"details":{"product":{"id":547804819,"section":2,"familyId":73,"subfamilyId":12451}}}}}'::jsonb) ON CONFLICT(id) DO UPDATE SET source_extra=excluded.source_extra;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM fitmatch_vnext.products WHERE source_product_key IN ('564222870','564203652') AND fitmatch_vnext.product_comparison_group(id)->>'group_code' IS NOT NULL) THEN RAISE EXCEPTION 'baseline did not reproduce'; END IF; END $$;
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
;
DO $$ BEGIN
IF (SELECT count(*) FROM fitmatch_vnext.products WHERE source_product_key IN ('564222870','564203652') AND fitmatch_vnext.product_comparison_group(id)->>'group_code'='A')<>2 THEN RAISE EXCEPTION 'two mapped products not repaired'; END IF;
IF EXISTS (SELECT 1 FROM fitmatch_vnext.products WHERE source_product_key IN ('551126671','545450451','547804819') AND fitmatch_vnext.product_comparison_group(id)->>'mapping_source'<>'UNMAPPED') THEN RAISE EXCEPTION 'unregistered category was guessed'; END IF;
IF EXISTS (SELECT 1 FROM zara_repair_before b WHERE b.result IS DISTINCT FROM fitmatch_vnext.product_comparison_group(b.id)) THEN RAISE EXCEPTION 'existing fixture regression'; END IF;
END $$;
UPDATE fitmatch_vnext.products SET source_extra=jsonb_set(source_extra,'{structured_facts,retailer_api,details,product,id}','"wrong-parent"') WHERE source_product_key='564222870';
DO $$ BEGIN IF (SELECT fitmatch_vnext.product_comparison_group(id)->>'mapping_source' FROM fitmatch_vnext.products WHERE source_product_key='564222870')<>'UNMAPPED' THEN RAISE EXCEPTION 'parent mismatch accepted'; END IF; END $$;
ROLLBACK;
