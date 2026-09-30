-- SELECT only. Installation checks are not semantic release approval.
with function_state as (
    select
        p.oid,
        n.nspname,
        p.proname,
        pg_get_function_identity_arguments(p.oid) arguments,
        md5(replace(p.prosrc, chr(13), '')) body_md5,
        p.prosrc,
        p.proacl::text acl,
        pg_get_userbyid(p.proowner) owner_name,
        p.prosecdef,
        p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.oid in (
        to_regprocedure('fitmatch_vnext.classification_decision(text,text)'),
        to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)')
    )
), checks as (
    select 'classification_decision_checksum' check_name,
           coalesce((select body_md5 = '5a81fa24b06a3aa43f7a9ffab553788a'
                     from function_state where proname = 'classification_decision'), false) passed
    union all
    select 'classification_decision_privileges',
           coalesce((select acl = '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}'
                         and owner_name = 'postgres' and not prosecdef
                         and proconfig = array['search_path=""']::text[]
                     from function_state where proname = 'classification_decision'), false)
    union all
    select 'recovery_checksum',
           coalesce((select body_md5 = 'dca1dda221090e661628ffb5811e13ef'
                     from function_state where proname = 'classification_recovery_options'), false)
    union all
    select 'recovery_privileges',
           coalesce((select acl = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
                         and owner_name = 'postgres' and prosecdef
                         and proconfig = array['search_path=""']::text[]
                     from function_state where proname = 'classification_recovery_options'), false)
    union all
    select 'v1_contract_retained',
           coalesce((select position('fitmatch-retailer-api-v1' in prosrc) > 0
                     from function_state where proname = 'classification_decision'), false)
    union all
    select 'zara_v2_parent_and_variant_guards',
           coalesce((select position('fitmatch-retailer-api-v2' in prosrc) > 0
                         and position('provider_parent_with_selected_variant' in prosrc) > 0
                         and position('api_product->>''id'' IS DISTINCT FROM product_row.source_product_key' in prosrc) > 0
                         and position('WHERE c->>''productId''=api_selected_key' in prosrc) > 0
                     from function_state where proname = 'classification_decision'), false)
    union all
    select 'r2_recovery_contract_aligned',
           coalesce((select position('fitmatch-vnext-retailer-api-20260909-r2' in prosrc) > 0
                         and position('fitmatch-vnext-recovery-retailer-api-20260909-r2' in prosrc) > 0
                         and position('count_value>64' in prosrc) > 0
                     from function_state where proname = 'classification_recovery_options'), false)
    union all
    select 'ingress_rpc_unchanged_and_service_only',
           coalesce(
               has_function_privilege('service_role',
                   to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'), 'EXECUTE')
               and not has_function_privilege('anon',
                   to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'), 'EXECUTE')
               and not has_function_privilege('authenticated',
                   to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'), 'EXECUTE'),
               false
           )
)
select check_name, passed from checks order by check_name;

-- Operational inspection only: the candidate itself performs no DML and does
-- not rewrite these rows. Compare these counts to the pre-apply capture made in
-- the same maintenance window.
select
    (select count(*) from fitmatch_vnext.products) products,
    (select count(*) from fitmatch_vnext.product_ingestion_receipts) receipts,
    (select count(*) from fitmatch_vnext.user_product_classification_overrides) user_overrides;
