-- CONTROLLED PRODUCTION ARTIFACT.
-- Creates an inactive, validated forward-only rollback successor by cloning
-- the exact pre-activation active mapping bundle. No activation, decision,
-- history, customer, closet, or comparison-history write occurs here.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(hashtext('fitmatch:release-activation'));

do $block$
declare
  v_source fitmatch_catalog.releases%rowtype;
  v_candidate_gate jsonb;
  v_source_mapping_count integer;
  v_successor_mapping_count integer;
  v_source_mapping_checksum text;
  v_successor_mapping_checksum text;
  v_successor_gate jsonb;
begin
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1 then
    raise exception 'rollback_successor_active_release_count_mismatch';
  end if;

  select * into v_source
  from fitmatch_catalog.releases
  where id='65d72393-4a40-4e99-b701-fdc1ff865774'::uuid
    and status='active'
  for update;
  if not found
    or v_source.release_key<>
      'fitmatch-active-with-zara-official-tree-2026-08-13-v1__zara-sample30-2026-08-21'
    or v_source.bundle_checksum<>
      'c996dacd2c91d12b80ae36fb215001d8fad4d5ef8cbfde762f5248cd8f22fbda'
    or v_source.app_taxonomy_checksum<>
      '123c693fc38c01d8edf877dbe9b651a6c40451a06752eed4bca3d14c2ac3bd57'
    or v_source.expected_mapping_count<>3492
  then
    raise exception 'rollback_successor_source_release_preimage_mismatch';
  end if;

  v_candidate_gate:=fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-000000000118'::uuid
  );
  if not coalesce((v_candidate_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_candidate_gate->'blockers','[]'::jsonb))<>0
  then
    raise exception 'rollback_successor_candidate_gate_failed:%',v_candidate_gate;
  end if;

  select count(*),encode(extensions.digest(coalesce(string_agg(
    jsonb_build_object(
      'source_identity',mapping.source_identity,
      'source',mapping.source,
      'snapshot_id',mapping.snapshot_id,
      'external_category_id',mapping.external_category_id,
      'target',mapping.target,
      'normalized_path',mapping.normalized_path,
      'decision_status',mapping.decision_status,
      'mapping_status',mapping.mapping_status,
      'runtime_lookup_eligible',mapping.runtime_lookup_eligible,
      'eligibility',mapping.eligibility,
      'semantic_category_code',mapping.semantic_category_code,
      'semantic_garment_type',mapping.semantic_garment_type,
      'comparison_family',mapping.comparison_family,
      'source_external_key',mapping.source_external_key,
      'source_external_target_key',mapping.source_external_target_key,
      'source_path_key',mapping.source_path_key,
      'source_target_path_key',mapping.source_target_path_key,
      'raw_record',mapping.raw_record
    )::text,E'\n' order by mapping.source_identity),''),'sha256'),'hex')
  into v_source_mapping_count,v_source_mapping_checksum
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id=v_source.id;
  if v_source_mapping_count<>3492 then
    raise exception 'rollback_successor_source_mapping_count_mismatch';
  end if;

  insert into fitmatch_catalog.releases(
    id,release_key,taxonomy_version,policy_version,status,
    bundle_checksum,app_taxonomy_checksum,expected_mapping_count,
    expected_qa_count,metadata,validated_at,
    validation_contract_version,validation_report
  ) values (
    '11800000-0000-4000-8000-00000000b001'::uuid,
    'fitmatch-classification-rollback-successor-2026-08-26-v1',
    v_source.taxonomy_version,v_source.policy_version,'loading',
    v_source.bundle_checksum,v_source.app_taxonomy_checksum,3492,1608,
    jsonb_build_object(
      'rollback_successor',true,
      'source_release_id',v_source.id,
      'source_release_key',v_source.release_key,
      'preimage_plain_sha256',
        '22d34b6889f14dcf4de66eeed649be85e981dfcd6290ca10b3954da169c3314d',
      'preimage_cipher_sha256',
        '844fec409490a04c4a14ea0ccdb22da6c130facf806ff27b8be8bd288522e22b'
    ),null,'fitmatch-release-gate-v2','{}'::jsonb
  )
  on conflict (id) do nothing;

  if not exists (
    select 1 from fitmatch_catalog.releases
    where id='11800000-0000-4000-8000-00000000b001'::uuid
      and release_key=
        'fitmatch-classification-rollback-successor-2026-08-26-v1'
      and status in ('loading','validated')
      and taxonomy_version=v_source.taxonomy_version
      and policy_version=v_source.policy_version
      and bundle_checksum=v_source.bundle_checksum
      and app_taxonomy_checksum=v_source.app_taxonomy_checksum
      and expected_mapping_count=3492
      and expected_qa_count=1608
      and coalesce((metadata->>'rollback_successor')::boolean,false)
      and metadata->>'source_release_id'=v_source.id::text
  ) then
    raise exception 'rollback_successor_existing_release_drift';
  end if;

  insert into fitmatch_catalog.source_category_mappings(
    release_id,source_identity,source,snapshot_id,external_category_id,
    target,normalized_path,decision_status,mapping_status,
    runtime_lookup_eligible,eligibility,semantic_category_code,
    semantic_garment_type,comparison_family,source_external_key,
    source_external_target_key,source_path_key,source_target_path_key,
    raw_record,created_at
  )
  select
    '11800000-0000-4000-8000-00000000b001'::uuid,
    source_identity,source,snapshot_id,external_category_id,target,
    normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
    eligibility,semantic_category_code,semantic_garment_type,
    comparison_family,source_external_key,source_external_target_key,
    source_path_key,source_target_path_key,raw_record,created_at
  from fitmatch_catalog.source_category_mappings
  where release_id=v_source.id
  on conflict (release_id,source_identity) do nothing;

  select count(*),encode(extensions.digest(coalesce(string_agg(
    jsonb_build_object(
      'source_identity',mapping.source_identity,
      'source',mapping.source,
      'snapshot_id',mapping.snapshot_id,
      'external_category_id',mapping.external_category_id,
      'target',mapping.target,
      'normalized_path',mapping.normalized_path,
      'decision_status',mapping.decision_status,
      'mapping_status',mapping.mapping_status,
      'runtime_lookup_eligible',mapping.runtime_lookup_eligible,
      'eligibility',mapping.eligibility,
      'semantic_category_code',mapping.semantic_category_code,
      'semantic_garment_type',mapping.semantic_garment_type,
      'comparison_family',mapping.comparison_family,
      'source_external_key',mapping.source_external_key,
      'source_external_target_key',mapping.source_external_target_key,
      'source_path_key',mapping.source_path_key,
      'source_target_path_key',mapping.source_target_path_key,
      'raw_record',mapping.raw_record
    )::text,E'\n' order by mapping.source_identity),''),'sha256'),'hex')
  into v_successor_mapping_count,v_successor_mapping_checksum
  from fitmatch_catalog.source_category_mappings mapping
  where mapping.release_id=
    '11800000-0000-4000-8000-00000000b001'::uuid;

  if v_successor_mapping_count<>v_source_mapping_count
    or v_successor_mapping_checksum is distinct from v_source_mapping_checksum
  then
    raise exception 'rollback_successor_mapping_clone_mismatch';
  end if;

  update fitmatch_catalog.releases
  set status='validated',validated_at=now(),
      validation_report=jsonb_build_object(
        'rollback_successor_validated',true,
        'rollback_dry_run_passed',true,
        'source_release_id',v_source.id,
        'source_release_key',v_source.release_key,
        'source_bundle_checksum',v_source.bundle_checksum,
        'source_app_taxonomy_checksum',v_source.app_taxonomy_checksum,
        'source_mapping_count',v_source_mapping_count,
        'source_mapping_checksum',v_source_mapping_checksum,
        'shadow_product_count',1608,
        'gold_exact_count',3,
        'set_garment_confirmed_count',0,
        'set_comparison_allowed_count',0,
        'safety_leak_count',0,
        'history_write_count',0,
        'history_delete_count',0,
        'function_bundle_preimage_checksum',
          '85c9a44f472ad0e9c84ca584dfad875beb4963742f7c0d9ac04f395cda623d44',
        'preimage_plain_sha256',
          '22d34b6889f14dcf4de66eeed649be85e981dfcd6290ca10b3954da169c3314d',
        'preimage_cipher_sha256',
          '844fec409490a04c4a14ea0ccdb22da6c130facf806ff27b8be8bd288522e22b'
      )
  where id='11800000-0000-4000-8000-00000000b001'::uuid;

  v_successor_gate:=fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-00000000b001'::uuid
  );
  if not coalesce((v_successor_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_successor_gate->'blockers','[]'::jsonb))<>0
  then
    raise exception 'rollback_successor_gate_failed:%',v_successor_gate;
  end if;

  update fitmatch_catalog.releases
  set release_gate_checked_at=now(),release_gate_result=v_successor_gate
  where id='11800000-0000-4000-8000-00000000b001'::uuid;
end
$block$;

commit;
