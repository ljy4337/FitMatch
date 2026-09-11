begin;

create or replace function fitmatch_vnext.comparison_group_tuple(
  p_product_id uuid, p_requested_group_code text default null
)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $function$
declare
  p fitmatch_vnext.products%rowtype;
  resolved jsonb;
  code text;
  garment text;
  category text;
begin
  select * into p from fitmatch_vnext.products where id=p_product_id;
  if not found then return null; end if;
  resolved:=fitmatch_vnext.product_comparison_group(p.id);
  code:=coalesce(nullif(btrim(p_requested_group_code),''),resolved->>'group_code');
  -- SQL NOT IN alone does not reject NULL for an unmapped category.
  if code is null or code not in ('A','B','C','D','E','F','G') then
    return null;
  end if;
  garment:=case code
    when 'A' then 'comparison_group_top'
    when 'B' then 'comparison_group_outerwear'
    when 'C' then 'comparison_group_bottom'
    when 'D' then 'comparison_group_skirt'
    when 'E' then 'comparison_group_onepiece'
    when 'F' then 'comparison_group_innerwear'
    when 'G' then 'comparison_group_homewear' end;
  select category_code into category from fitmatch_vnext.garment_types
  where garment_type_code=garment;
  return jsonb_build_object(
    'group_code',code,'category_code',category,'garment_type_code',garment,
    'audience_code',case when p.audience_code in ('MEN','WOMEN','UNISEX','KIDS','BABY')
      then p.audience_code else 'UNKNOWN' end,
    'sleeve_length_code',null,'lower_length_code',null,'body_length_code',null,
    'policy_version','retailer-comparison-groups-v3-seven-20260911'
  );
end
$function$;

insert into fitmatch_catalog.source_category_comparison_groups(
  policy_version,source_code,source_category_key,group_code,disposition,
  category_path,source_ids,source_names,audience_codes,product_count,
  sample_products,mapping_basis,notes,source_record
)
values (
  'retailer-comparison-groups-v3-seven-20260911','zara',
  'zara-path:MAN:tshirt:B.Camiseta','A','COMPARABLE',
  array['ZARA','남성','티셔츠','B. Camiseta'],
  '{}'::jsonb,jsonb_build_object('family','티셔츠','subfamily','B. Camiseta'),
  array['MEN'],1,'["545482161"]'::jsonb,
  'EXACT_RETAILER_CATEGORY_PATH',
  array['Exact persisted official category path; no product-name or measurement inference'],
  jsonb_build_object('source_category_path','ZARA > 남성 > 티셔츠 > B. Camiseta')
)
on conflict(policy_version,source_code,source_category_key,group_code) do nothing;

commit;
