-- SELECT-only verification after 134_*_Apply.sql.
with classifier as (
  select p.*
  from pg_catalog.pg_proc p
  where p.oid = to_regprocedure('fitmatch_vnext.classification_decision(text,text)')
), recovery as (
  select p.*
  from pg_catalog.pg_proc p
  where p.oid = to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)')
)
select
  exists(select 1 from classifier) as classification_function_exists,
  (select md5(replace(prosrc, chr(13), '')) = '10e98b939e3886bdabda5f48bbb3cdc6' from classifier)
    as classification_body_md5_ok,
  (select strpos(prosrc, 'fitmatch-provider-api-policy-20260910-u904-zara-v2-musinsa-r1') > 0 from classifier)
    as provider_policy_version_ok,
  (select strpos(prosrc, $$r.provider IN ('any',p_observation->>'source_code')$$) > 0 from classifier)
    as provider_scope_guard_present,
  (select strpos(prosrc, 'musinsa.r1.category.safari_hunting_jacket') > 0 from classifier)
    as safari_candidate_rule_present,
  (select strpos(prosrc, 'musinsa.r1.category.training_jacket') > 0 from classifier)
    as training_jacket_rule_present,
  (select strpos(prosrc, 'musinsa.r1.category.long_heavy_outer_length') > 0 from classifier)
    as puffer_length_rule_present,
  (select strpos(prosrc, 'provider_parent_with_selected_variant') > 0 from classifier)
    as zara_v2_identity_preserved,
  (select strpos(prosrc, 'uniqlo.u904.') > 0 from classifier)
    as uniqlo_u904_rules_preserved,
  (select md5(replace(prosrc, chr(13), '')) = 'd01db739db96a46d5725fbfb8d215e61' from recovery)
    as recovery_function_unchanged;
