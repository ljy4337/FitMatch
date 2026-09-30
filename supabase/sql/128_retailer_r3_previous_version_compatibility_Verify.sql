-- SELECT-only verification after applying 128_retailer_r3_previous_version_compatibility_Apply.sql.
-- It does not call resolve(..., true), mutate Product rows, or impersonate a user.

with function_state as (
    select p.prosrc,
           md5(p.prosrc) body_md5,
           p.provolatile,
           p.prosecdef,
           p.proconfig,
           p.proacl::text acl,
           pg_catalog.pg_get_userbyid(p.proowner) owner_name
    from pg_catalog.pg_proc p
    where p.oid = to_regprocedure(
        'fitmatch_vnext.classification_decision(text,text)'
    )
), checks as (
    select 'classification_r3_compat_checksum' check_name,
           coalesce((select body_md5 = '291bf9bdf95b37d234f344e7d4d80303'
                     from function_state), false) passed
    union all
    select 'classification_privileges_preserved',
           coalesce((select owner_name = 'postgres'
                         and not prosecdef
                         and provolatile = 's'
                         and proconfig = array['search_path=""']::text[]
                         and acl = '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}'
                     from function_state), false)
    union all
    select 'outer_previous_version_guard_removed',
           coalesce((select position(
               'A previous resolver version does not invalidate current, identity-verified'
               in prosrc
           ) > 0 from function_state), false)
    union all
    select 'retailer_v1_and_r3_retained',
           coalesce((select position('fitmatch-retailer-api-v1' in prosrc) > 0
                         and position('fitmatch-vnext-retailer-api-20260909-r3' in prosrc) > 0
                     from function_state), false)
    union all
    select 'recovery_r3_contract_retained',
           coalesce((select md5(p.prosrc) = 'd01db739db96a46d5725fbfb8d215e61'
                         and position(
                             'fitmatch-vnext-recovery-retailer-api-20260909-r3'
                             in p.prosrc
                         ) > 0
                     from pg_catalog.pg_proc p
                     where p.oid = to_regprocedure(
                         'fitmatch_vnext.classification_recovery_options(uuid)'
                     )), false)
), decisions as (
    select source_code, source_product_key,
           fitmatch_vnext.classification_decision(
               source_code, source_product_key
           ) decision
    from (values
        ('uniqlo', 'E465185'),
        ('uniqlo', 'E484080'),
        ('musinsa', '5746363')
    ) fixture(source_code, source_product_key)
), semantic_checks as (
    select 'uniqlo_e465185_confirmed_r3' check_name,
           coalesce((select decision->>'classification_status' = 'CONFIRMED'
                         and decision->>'garment_type_code' = 'tshirt'
                         and decision->>'sleeve_length_code' = 'short_sleeve'
                     from decisions
                     where source_code = 'uniqlo'
                       and source_product_key = 'E465185'), false) passed
    union all
    select 'uniqlo_e484080_remains_confirmed',
           coalesce((select decision->>'classification_status' = 'CONFIRMED'
                         and decision->>'garment_type_code' = 'tshirt'
                         and decision->>'sleeve_length_code' = 'long_sleeve'
                     from decisions
                     where source_code = 'uniqlo'
                       and source_product_key = 'E484080'), false)
    union all
    select 'musinsa_5746363_v1_reaches_r3',
           coalesce((select decision->>'classification_status' = 'CONFIRMED'
                         and decision->>'garment_type_code' = 'slacks_trousers'
                         and decision->>'lower_length_code' = 'long_length'
                         and decision->>'resolver_version' =
                             'fitmatch-vnext-retailer-api-20260909-r3'
                     from decisions
                     where source_code = 'musinsa'
                       and source_product_key = '5746363'), false)
)
select check_name, passed from checks
union all
select check_name, passed from semantic_checks
order by check_name;

-- Missing observation remains distinct from a classification failure.
select fitmatch_vnext.classification_decision(
    'musinsa', '5746362'
) as musinsa_5746362_expected_missing_observation;

-- This candidate intentionally performs no data migration.
select
    (select count(*) from fitmatch_vnext.products) products,
    (select count(*) from fitmatch_vnext.product_ingestion_receipts) receipts,
    (select count(*) from fitmatch_vnext.user_product_classification_overrides) user_overrides;
