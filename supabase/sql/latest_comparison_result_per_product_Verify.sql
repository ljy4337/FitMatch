select
    head.user_id,
    head.target_product_id,
    count(*) as head_count
from fitmatch_vnext.comparison_result_heads head
group by head.user_id, head.target_product_id
having count(*) <> 1;

select count(*) as invalid_head_count
from fitmatch_vnext.comparison_result_heads head
join fitmatch_vnext.comparisons comparison_value
  on comparison_value.id = head.comparison_id
where comparison_value.user_id is distinct from head.user_id
   or comparison_value.target_product_id is distinct from head.target_product_id
   or comparison_value.result_status is distinct from 'COMPLETED';

select pg_get_functiondef(
    'fitmatch_vnext.comparison_history()'::regprocedure
);
