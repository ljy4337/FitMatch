select
    p.oid::regprocedure::text as function_name,
    pg_get_functiondef(p.oid) as definition
from pg_proc p
where p.oid in (
    'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure,
    'fitmatch_vnext.effective_product_readiness(uuid)'::regprocedure
)
order by function_name;

select
    source_code,
    source_product_key,
    effective_classification ->> 'classification_status' as classification_status,
    comparison_group ->> 'group_code' as group_code,
    readiness ->> 'status' as readiness_status,
    readiness ->> 'reason' as readiness_reason
from (
    select
        p.source_code,
        p.source_product_key,
        runtime -> 'effective_classification' as effective_classification,
        runtime -> 'comparison_group' as comparison_group,
        runtime -> 'readiness' as readiness
    from fitmatch_vnext.products p
    cross join lateral fitmatch_vnext.get_product_runtime_for_swift(
        p.source_code,
        p.source_product_key
    ) runtime
) inspected
where effective_classification ->> 'classification_status' = 'CONFIRMED'
  and readiness ->> 'status' = 'CLASSIFICATION_REQUIRED';
