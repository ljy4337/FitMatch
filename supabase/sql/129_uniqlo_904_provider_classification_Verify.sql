-- SELECT-only verification for 129_uniqlo_904_provider_classification_Apply.sql.
-- Run first on an isolated/development DB after loading representative Swift v2 payloads.

with classifier as (
    select p.prosrc, p.prosecdef, p.provolatile, p.proconfig, p.proacl::text acl,
           pg_catalog.pg_get_userbyid(p.proowner) owner_name
    from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('fitmatch_vnext.classification_decision(text,text)')
), recovery as (
    select p.prosrc, md5(replace(p.prosrc, chr(13), '')) body_md5
    from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)')
), checks as (
    select 'u904_policy_installed' check_name,
           coalesce((select strpos(prosrc, 'fitmatch-provider-api-policy-20260910-u904-r3') > 0
                     from classifier), false) passed
    union all
    select 'r3_swift_contract_retained',
           coalesce((select strpos(prosrc, 'fitmatch-vnext-retailer-api-20260909-r3') > 0
                         and strpos(prosrc, 'fitmatch-vnext-retailer-api-20260909-r4') = 0
                     from classifier), false)
    union all
    select 'recovery_unchanged',
           coalesce((select body_md5 = 'd01db739db96a46d5725fbfb8d215e61'
                         and strpos(prosrc, 'fitmatch-vnext-recovery-retailer-api-20260909-r3') > 0
                     from recovery), false)
    union all
    select 'function_security_preserved',
           coalesce((select not prosecdef and provolatile = 's'
                         and proconfig = array['search_path=""']::text[]
                         and owner_name = 'postgres'
                     from classifier), false)
    union all
    select 'all_rules_are_uniqlo_scoped',
           coalesce((select not exists (
               select 1
               from unnest(array[
                   'uniqlo.u904.inner_crew','uniqlo.u904.special_polo',
                   'uniqlo.u904.special_tshirt','uniqlo.u904.women_panty_path',
                   'uniqlo.u904.shirt_blouse_path','uniqlo.u904.shirt_sleeveless_axis',
                   'uniqlo.u904.shirt_three_quarter_axis',
                   'uniqlo.u904.bra_path','uniqlo.u904.room_shoes',
                   'uniqlo.u904.hoodie_path','uniqlo.u904.sweat_pants_path',
                   'uniqlo.u904.pocketable_parka','uniqlo.u904.graphic_tshirt'
               ]::text[]) rule_id
               where strpos(classifier.prosrc, rule_id) = 0
           ) from classifier), false)
    union all
    select 'category_path_corroboration_is_uniqlo_only',
           coalesce((select strpos(
               prosrc,
               $$p_observation->>'source_code'='uniqlo' AND field IN ('category_path','category_id_path')$$
           ) > 0 from classifier), false)
)
select check_name, passed from checks order by check_name;

-- Known comparison-path regressions. Missing rows remain visible instead of
-- being silently counted as pass.
with fixtures(source_code, source_product_key, expected_status, expected_garment, expected_sleeve) as (
    values
        ('uniqlo','E465185','CONFIRMED','tshirt','short_sleeve'),
        ('uniqlo','E484080','CONFIRMED','tshirt','long_sleeve'),
        -- Inner/outer evidence conflicts for this item. Keeping review is safer
        -- than forcing a base-layer classification from one path alone.
        ('uniqlo','E482514','REVIEW_REQUIRED',null,null),
        -- Salopette/overall cannot be equated with the current bodysuit_top
        -- contract from a broad newborn one-piece breadcrumb alone.
        ('uniqlo','E487950','REVIEW_REQUIRED',null,null),
        ('uniqlo','E482306','CONFIRMED','polo_shirt','short_sleeve'),
        ('uniqlo','E485454','CONFIRMED','tshirt','short_sleeve')
), decisions as (
    select f.*,
           fitmatch_vnext.classification_decision(f.source_code, f.source_product_key) decision
    from fixtures f
)
select source_code, source_product_key,
       decision->>'classification_status' classification_status,
       decision->>'garment_type_code' garment_type_code,
       decision->>'sleeve_length_code' sleeve_length_code,
       decision->>'resolver_version' resolver_version,
       (decision->>'classification_status' = expected_status
        and (expected_garment is null or decision->>'garment_type_code' = expected_garment)
        and (expected_sleeve is null or decision->>'sleeve_length_code' = expected_sleeve)) passed
from decisions
order by source_product_key;

-- The false-positive discovered in the 904 review proposal must never become
-- a comparable garment.
select 'uniqlo_room_shoes_not_applicable' check_name,
       d->>'classification_status' classification_status,
       (d->>'classification_status' = 'NOT_APPLICABLE') passed
from (select fitmatch_vnext.classification_decision('uniqlo','E461767') d) q;

-- Provider regression visibility. The patch does not alter the resolver
-- contract or any non-UNIQLO policy rule; these rows expose unexpected drift.
select source_code, source_product_key,
       fitmatch_vnext.classification_decision(source_code, source_product_key) decision
from (values
    ('musinsa','5746363'),
    ('zara','555069470')
) fixture(source_code, source_product_key);

-- Review-set coverage after representative payload ingestion. These are the
-- 41 clothing-presence proposals from the 904 corpus; this query reports the
-- actual DB decision and never treats a missing observation as a pass.
with ids(source_product_key) as (
    select unnest(array[
        'E486335','E486336','E487950','E488902','E488903','E489247','E482006',
        'E482514','E482306','E485782','E485454','E487042','E487050','E487064',
        'E487032','E487034','E486718','E461767','E488014','E483880','E492900',
        'E486696','E486697','E486701','E475647','E475649','E483869','E483872',
        'E483890','E484256','E479071','E482825','E484240','E487528','E489229',
        'E489230','E485584','E487989','E479073','E484928','E485265'
    ]::text[])
), decisions as (
    select i.source_product_key,
           fitmatch_vnext.classification_decision('uniqlo', i.source_product_key) decision
    from ids i
)
select coalesce(decision->>'classification_status','MISSING') classification_status,
       count(*) product_count,
       array_agg(source_product_key order by source_product_key) product_keys
from decisions
group by coalesce(decision->>'classification_status','MISSING')
order by classification_status;
