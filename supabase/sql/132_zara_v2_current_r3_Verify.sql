-- Read-only verification for 132_zara_v2_current_r3_Apply.sql.
-- This does not mutate product or user data.

with classifier as (
    select p.oid,
           p.prosrc,
           md5(replace(p.prosrc, chr(13), '')) as body_md5,
           p.prosecdef,
           p.proowner,
           p.proacl,
           p.proconfig
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_decision(text,text)'
     )
), recovery as (
    select md5(replace(p.prosrc, chr(13), '')) as body_md5
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_recovery_options(uuid)'
     )
)
select
    c.oid is not null as classification_function_exists,
    strpos(c.prosrc, 'fitmatch-provider-api-policy-20260910-u904-zara-v2-r1') > 0
        as provider_policy_version_ok,
    strpos(c.prosrc, 'fitmatch-retailer-api-v1') > 0
        and strpos(c.prosrc, 'fitmatch-retailer-api-v2') > 0
        as v1_and_v2_contracts_present,
    strpos(c.prosrc, 'provider_parent_with_selected_variant') > 0
        and strpos(c.prosrc,
            $$api_product->>'id' IS DISTINCT FROM product_row.source_product_key$$
        ) > 0
        as parent_identity_guard_present,
    strpos(c.prosrc, $$WHERE c->>'productId'=api_selected_key$$) > 0
        and strpos(c.prosrc,
            $$'/product/'||api_selected_key||'/size-measure-guide([?]|$)'$$
        ) > 0
        as selected_variant_guards_present,
    strpos(c.prosrc, 'zara.v2.kids_tshirt_scope') > 0
        and strpos(c.prosrc, 'zara.v2.kids_sweater_scope') > 0
        and strpos(c.prosrc, 'zara.v2.explicit_named_upper_lower_set') > 0
        as bounded_zara_rules_present,
    strpos(c.prosrc, 'uniqlo.u904.') > 0
        and strpos(c.prosrc,
            $$p_observation->>'source_code'='uniqlo' AND field IN ('category_path','category_id_path')$$
        ) > 0
        as uniqlo_r3_rules_preserved,
    r.body_md5 = 'd01db739db96a46d5725fbfb8d215e61'
        as recovery_function_unchanged,
    c.body_md5 as classification_body_md5,
    r.body_md5 as recovery_body_md5
from classifier c cross join recovery r;

do $verify$
declare
    body text;
    recovery_md5 text;
begin
    select p.prosrc into body
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_decision(text,text)'
     );
    select md5(replace(p.prosrc, chr(13), '')) into recovery_md5
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_recovery_options(uuid)'
     );

    if body is null
       or strpos(body, 'fitmatch-provider-api-policy-20260910-u904-zara-v2-r1') = 0
       or strpos(body, 'fitmatch-retailer-api-v1') = 0
       or strpos(body, 'fitmatch-retailer-api-v2') = 0
       or strpos(body, 'provider_parent_with_selected_variant') = 0
       or strpos(body, 'ZARA_API_V2_IDENTITY_OR_SHAPE') = 0
       or strpos(body, 'zara.v2.kids_tshirt_scope') = 0
       or strpos(body, 'zara.v2.kids_sweater_scope') = 0
       or strpos(body, 'zara.v2.explicit_named_upper_lower_set') = 0
       or strpos(body, 'uniqlo.u904.') = 0 then
        raise exception 'FM_ZARA_V2_VERIFY_FAILED';
    end if;
    if recovery_md5 <> 'd01db739db96a46d5725fbfb8d215e61' then
        raise exception 'FM_ZARA_V2_VERIFY_RECOVERY_CHANGED: %', recovery_md5;
    end if;
end
$verify$;
