begin;

set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('fitmatch:fix-product-exclusion-resolution'));

create or replace function fitmatch_catalog.runtime_resolve_product_classification_v3(
  p_source text,p_external_product_id text,p_product_name text,
  p_source_category_path text,p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog
as $$
declare
  v_result jsonb;
  v_snapshot fitmatch_catalog.source_product_snapshots%rowtype;
  v_exclusion fitmatch_catalog.classification_exclusion_profiles%rowtype;
  v_fingerprint text:=fitmatch_catalog.runtime_product_fingerprint(
    p_product_name,p_source_category_path
  );
  v_path text:=fitmatch_catalog.runtime_normalized_category_path(p_source_category_path);
begin
  v_result:=fitmatch_catalog.runtime_resolve_product_classification_v2(
    p_source,p_external_product_id,p_product_name,p_source_category_path,p_payload
  );
  if v_result->>'classification_status' in ('confirmed','not_comparable')
     or v_result->>'decision_source'='canonical_product_decision' then
    return v_result;
  end if;

  select * into v_snapshot
  from fitmatch_catalog.source_product_snapshots
  where source=lower(p_source) and external_product_id=p_external_product_id
    and fitmatch_catalog.runtime_product_fingerprint(
      product_name,source_category_path
    )=v_fingerprint
  order by collected_at desc limit 1;
  if v_snapshot.run_id is not null
     and v_snapshot.classification_status='excluded_review'
     and v_snapshot.fitmatch_category_label is null
     and v_snapshot.fitmatch_detail_label is null then
    return jsonb_build_object(
      'category_code',null,'detail_code',null,'family_code',null,'length_code',null,
      'requires_user_confirmation',false,'comparable',false,
      'classification_status','not_comparable','classification_method','category_mapping',
      'decision_source','verified_product_exclusion_snapshot',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',1,'exclusion_reason','not_fitmatch_comparable',
      'snapshot_run_id',v_snapshot.run_id
    );
  end if;

  select * into v_exclusion
  from fitmatch_catalog.classification_exclusion_profiles
  where policy_version='db-auto-classifier-2026-08-18-v2'
    and source=lower(p_source) and normalized_path=v_path and auto_eligible;
  if v_exclusion.policy_version is not null then
    return jsonb_build_object(
      'category_code',null,'detail_code',null,'family_code',null,'length_code',null,
      'requires_user_confirmation',false,'comparable',false,
      'classification_status','not_comparable','classification_method','category_mapping',
      'decision_source','verified_path_exclusion_profile',
      'decision_version','db-auto-classifier-2026-08-18-v2',
      'classifier_policy_version','db-auto-classifier-2026-08-18-v2',
      'confidence',1,'exclusion_reason',v_exclusion.reason_code,
      'sample_count',v_exclusion.sample_count,'evidence',v_exclusion.evidence
    );
  end if;
  return v_result;
end $$;

create or replace function fitmatch_qa.validate_product_runtime_v3()
returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog,fitmatch_qa
as $$
declare
  v_base jsonb:=fitmatch_qa.validate_product_runtime_v2();
  v_known_exclusion jsonb;
  v_path_exclusion jsonb;
begin
  v_known_exclusion:=fitmatch_catalog.runtime_resolve_product_classification_v3(
    'uniqlo','E486202','히트텍스카프','액세서리 > 목도리 > 스카프',
    jsonb_build_object('source','uniqlo','audience','WOMEN',
      'source_category_codes',jsonb_build_array('57972','67132','67133'))
  );
  v_path_exclusion:=fitmatch_catalog.runtime_resolve_product_classification_v3(
    'uniqlo','__NEW_SCARF_VALIDATION__','울 블렌드 스카프',
    '액세서리 > 목도리 > 스카프',
    jsonb_build_object('source','uniqlo','audience','WOMEN')
  );
  return v_base||jsonb_build_object(
    'passed',coalesce((v_base->>'passed')::boolean,false)
      and v_known_exclusion->>'classification_status'='not_comparable'
      and v_path_exclusion->>'classification_status'='not_comparable',
    'known_exclusion_status',v_known_exclusion->>'classification_status',
    'path_exclusion_status',v_path_exclusion->>'classification_status'
  );
end $$;

revoke all on function fitmatch_catalog.runtime_resolve_product_classification_v3(
  text,text,text,text,jsonb
) from public,anon,authenticated;
revoke all on function fitmatch_qa.validate_product_runtime_v3()
  from public,anon,authenticated;
grant execute on function fitmatch_catalog.runtime_resolve_product_classification_v3(
  text,text,text,text,jsonb
),fitmatch_qa.validate_product_runtime_v3() to service_role;

do $$
declare v_result jsonb:=fitmatch_qa.validate_product_runtime_v3();
begin
  if not coalesce((v_result->>'passed')::boolean,false) then
    raise exception 'product runtime v3 validation failed: %',v_result;
  end if;
end $$;

commit;
