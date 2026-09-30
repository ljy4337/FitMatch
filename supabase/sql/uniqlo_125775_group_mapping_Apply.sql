-- Map the official UNIQLO tops breadcrumb for subcategory 125775 to group A.
-- This is category-authoritative and does not infer from the product name.

begin;

insert into fitmatch_catalog.source_category_comparison_groups (
  policy_version,
  source_code,
  source_category_key,
  group_code,
  disposition,
  category_path,
  source_ids,
  source_names,
  audience_codes,
  product_count,
  sample_products,
  mapping_basis,
  notes,
  source_record
)
values (
  'retailer-comparison-groups-v3-seven-20260911',
  'uniqlo',
  'uniqlo:57893:57967:58039:125775',
  'A',
  'COMPARABLE',
  array['MEN', '티셔츠 & 스웨트셔츠 & 후리스', '티셔츠 (긴팔 & 반팔)', '(X)후리스'],
  jsonb_build_object(
    'gender', '57893',
    'class', '57967',
    'category', '58039',
    'subcategory', '125775'
  ),
  jsonb_build_object(
    'gender', 'men',
    'class', 'tops',
    'category', 't shirts',
    'subcategory', 'fleece'
  ),
  array['MEN', 'UNISEX'],
  1,
  jsonb_build_array(
    jsonb_build_object('name', '후리스버튼업풀오버', 'product_id', 'E487929')
  ),
  'UNIQLO_OFFICIAL_BREADCRUMB_GROUP_ONLY',
  array['Official class is tops; detailed subtype is not used for comparison authority'],
  jsonb_build_object(
    'provider', 'uniqlo',
    'category_key', 'uniqlo:57893:57967:58039:125775',
    'category_path', jsonb_build_array(
      'MEN', '티셔츠 & 스웨트셔츠 & 후리스', '티셔츠 (긴팔 & 반팔)', '(X)후리스'
    ),
    'source_ids', jsonb_build_object(
      'gender', '57893',
      'class', '57967',
      'category', '58039',
      'subcategory', '125775'
    ),
    'source_names', jsonb_build_object(
      'gender', 'men',
      'class', 'tops',
      'category', 't shirts',
      'subcategory', 'fleece'
    ),
    'group_codes', jsonb_build_array('A'),
    'group_labels', jsonb_build_array('상의 비교군'),
    'disposition', 'COMPARABLE',
    'audience_codes', jsonb_build_array('MEN', 'UNISEX'),
    'product_count', 1,
    'sample_products', jsonb_build_array(
      jsonb_build_object('name', '후리스버튼업풀오버', 'product_id', 'E487929')
    ),
    'mapping_basis', 'UNIQLO official class tops; group-only authority',
    'seven_group_policy', true,
    'single_group_policy', true
  )
)
on conflict (policy_version, source_code, source_category_key, group_code)
do update set
  disposition = excluded.disposition,
  category_path = excluded.category_path,
  source_ids = excluded.source_ids,
  source_names = excluded.source_names,
  audience_codes = excluded.audience_codes,
  product_count = excluded.product_count,
  sample_products = excluded.sample_products,
  mapping_basis = excluded.mapping_basis,
  notes = excluded.notes,
  source_record = excluded.source_record;

commit;
