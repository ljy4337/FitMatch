begin;

with legacy_categories(family_id,subfamily_id,family_name,subfamily_name,group_code) as (
  values
    ('73','11453','바지','C.PTON-LEGGING','C'),
    ('73','12099','바지','L. PANT. PIJAMA','G'),
    ('73','12454','바지','F. Pant Resto','C'),
    ('73','12459','바지','Sastrería Pant.','C'),
    ('73','344','바지','B.PANTS','C'),
    ('74','336','드레스','W.DRESS','E'),
    ('74','346','드레스','B.DRESS','E'),
    ('76','12463','셔츠','F. Camisería','A'),
    ('77','348','브레이저','B.BLAZER','B'),
    ('78','12468','스포츠 재킷','F. Cazadora','B'),
    ('78','349','스포츠 재킷','B.SHORT-OUTWEAR','B'),
    ('78','383','스포츠 재킷','T.SHORT-OUTWEAR','B'),
    ('81','11272','가디건','KNIT CARDIGAN','B'),
    ('83','11442','티셔츠','C.CTAS FANTASI','A'),
    ('83','11450','티셔츠','C.CTAS POSICIO','A'),
    ('83','12479','티셔츠','F. Camiseta','A'),
    ('83','12480','티셔츠','Camiseta M/L','A')
), product_counts as (
  select p.source_extra->>'family_id' family_id,
         p.source_extra->>'subfamily_id' subfamily_id,
         count(*)::int product_count,
         jsonb_agg(p.source_product_key order by p.source_product_key) sample_products
  from fitmatch_vnext.products p
  where p.source_code='zara'
  group by 1,2
)
insert into fitmatch_catalog.source_category_comparison_groups(
  policy_version,source_code,source_category_key,group_code,disposition,
  category_path,source_ids,source_names,audience_codes,product_count,
  sample_products,mapping_basis,notes,source_record
)
select
  'retailer-comparison-groups-v3-seven-20260911','zara',
  'zara-legacy:'||c.family_id||':'||c.subfamily_id,
  c.group_code,'COMPARABLE',array[c.family_name,c.subfamily_name],
  jsonb_build_object('family',c.family_id,'subfamily',c.subfamily_id),
  jsonb_build_object('family',c.family_name,'subfamily',c.subfamily_name),
  '{}'::text[],coalesce(pc.product_count,0),coalesce(pc.sample_products,'[]'::jsonb),
  'EXACT_LEGACY_ZARA_CATEGORY_IDS_V1',
  array['category-only compatibility; no product-name or measurement inference'],
  jsonb_build_object('contract','zara-v1','identity','family_id+subfamily_id')
from legacy_categories c
left join product_counts pc using(family_id,subfamily_id)
on conflict(policy_version,source_code,source_category_key,group_code) do update set
  group_code=excluded.group_code,
  disposition=excluded.disposition,
  category_path=excluded.category_path,
  source_ids=excluded.source_ids,
  source_names=excluded.source_names,
  product_count=excluded.product_count,
  sample_products=excluded.sample_products,
  mapping_basis=excluded.mapping_basis,
  notes=excluded.notes,
  source_record=excluded.source_record;

create or replace function fitmatch_vnext.product_comparison_group(p_product_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
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
$function$;

update fitmatch_catalog.comparison_group_policies
set metadata=jsonb_set(metadata,'{zara_v1_category_compatibility}','true'::jsonb,true),
    validated_at=now()
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
