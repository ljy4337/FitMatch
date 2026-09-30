-- Read-only post-apply checks for 20260924100000.
-- Run as an authenticated test user with at least one linked Closet item.

select
    to_regprocedure('fitmatch_vnext.update_closet_item(uuid,jsonb)')
        as private_update_owner,
    to_regprocedure('public.fitmatch_vnext_update_closet_item(uuid,jsonb)')
        as public_update_rpc,
    to_regprocedure('fitmatch_vnext.list_closet_items()')
        as private_list_owner,
    to_regprocedure('public.fitmatch_vnext_list_closet_items()')
        as public_list_rpc;

select
    p.proname,
    pg_get_functiondef(p.oid) like '%source_observation_id%' as validates_exact_receipt,
    pg_get_functiondef(p.oid) like '%apply_linked_closet_snapshot_for_swift%' as retains_linked_path,
    pg_get_functiondef(p.oid) like '%apply_closet_comparison_group%' as retains_group_authority
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'fitmatch_vnext_update_closet_item'
  and pg_get_function_identity_arguments(p.oid) = 'p_closet_item_id uuid, p_request jsonb';

select
    item ->> 'id' as closet_item_id,
    item -> 'source_measurement_snapshot' ->> 'source_observation_id' as source_observation_id,
    item -> 'source_measurement_snapshot' ->> 'product_id' as snapshot_product_id,
    item -> 'source_measurement_snapshot' ->> 'product_variant_id' as snapshot_variant_id,
    item -> 'source_measurement_snapshot' ->> 'product_size_id' as snapshot_size_id,
    item -> 'source_measurement_snapshot' ->> 'source_measurement_count' as snapshot_raw_count,
    jsonb_array_length(coalesce(item -> 'source_measurements', '[]'::jsonb)) as returned_raw_count,
    item -> 'comparison_group' ->> 'group_code' as comparison_group_code
from jsonb_array_elements(public.fitmatch_vnext_list_closet_items()) item
where item ? 'source_measurement_snapshot';
