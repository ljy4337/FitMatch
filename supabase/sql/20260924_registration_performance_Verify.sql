-- Read-only deployment postflight. Does not impersonate or mutate a user.
select to_regprocedure('public.fitmatch_vnext_get_closet_item(uuid)') is not null as receipt_rpc_exists,
 has_function_privilege('authenticated','public.fitmatch_vnext_get_closet_item(uuid)','execute') as authenticated_allowed,
 not has_function_privilege('anon','public.fitmatch_vnext_get_closet_item(uuid)','execute') as anon_denied,
 not has_function_privilege('authenticated','fitmatch_vnext.get_product_runtime_base(text,text,boolean)','execute') as incomplete_runtime_private;
select strpos(pg_get_functiondef('fitmatch_vnext.list_closet_items_snapshot_base(uuid)'::regprocedure),'ci.user_id = caller_id')>0 as owner_gate,
 strpos(pg_get_functiondef('fitmatch_vnext.list_closet_items_snapshot_base(uuid)'::regprocedure),'ci.id = p_closet_item_id')>0 as exact_item_gate,
 strpos(pg_get_functiondef('fitmatch_vnext.list_closet_items_snapshot_base(uuid)'::regprocedure),'ci.deleted_at is null')>0 as active_only;
select strpos(pg_get_functiondef('fitmatch_vnext.get_product_runtime_for_swift(text,text)'::regprocedure),'p_source_code, p_source_product_key, false')>0 as discarded_projection_skipped,
 strpos(pg_get_functiondef('fitmatch_vnext.get_product_runtime_for_swift(text,text)'::regprocedure),'canonical_measurements_for_size_with_context')>0 as final_context_preserved,
 strpos(pg_get_functiondef('fitmatch_vnext.get_product_runtime_for_swift(text,text)'::regprocedure),'effective_product_readiness')>0 as final_readiness_preserved;
