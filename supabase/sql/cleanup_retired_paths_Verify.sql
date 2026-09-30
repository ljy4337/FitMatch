-- Read-only deployment regression gate. Every passed value must be true.
select 'retired_entrypoints_absent' as check_name,
  to_regprocedure('fitmatch_vnext.effective_target_classification_detail_legacy(uuid)') is null
  and to_regprocedure('fitmatch_vnext.legacy_comparison_group(text)') is null
  and to_regprocedure('fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)') is null as passed
union all
select 'readiness_uses_current_measurement_contract',
  prosrc like '%fitmatch_vnext.product_measurement_readiness(%'
  and prosrc not like '%product_readiness_with_context_v1(%'
  and prosrc like '%product_comparison_unit_decision(%'
from pg_proc where oid='fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure
union all
select 'group_authority_ignores_retired_detail',
  prosrc like '%product_comparison_group(%'
  and prosrc like '%comparison_group_tuple(%'
  and prosrc not like '%effective_target_classification_detail_legacy%'
  and prosrc not like '%user_product_classification_overrides%'
from pg_proc where oid='fitmatch_vnext.effective_target_classification(uuid)'::regprocedure
union all
select 'slacks_mapping_present', count(*)=1
from fitmatch_catalog.source_category_comparison_groups
where policy_version='retailer-comparison-groups-v3-seven-20260911'
  and source_code='musinsa'
  and source_category_key='musinsa-path:바지:슈트 팬츠/슬랙스'
  and group_code='C' and disposition='COMPARABLE'
union all
select 'slacks_length_gate_not_restored',
  -- Reviewed post-slacks validator; a change requires an equivalent regression.
  md5(pg_get_functiondef(oid))='4de8982f8bc4ed8d471e74a4c0561b14'
from pg_proc where oid='fitmatch_vnext.validate_garment_axis_values()'::regprocedure;
