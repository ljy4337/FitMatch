select
  count(*) as total_zara_products,
  count(*) filter(where fitmatch_vnext.product_comparison_group(id)->>'group_code'
    in ('A','B','C','D','E','F','G')) as grouped_products,
  count(*) filter(where fitmatch_vnext.product_comparison_group(id)->>'group_code'
    is null) as still_unmapped
from fitmatch_vnext.products
where source_code='zara';

select source_product_key,
       fitmatch_vnext.product_comparison_group(id) comparison_group
from fitmatch_vnext.products
where source_code='zara'
order by source_product_key
limit 5;
