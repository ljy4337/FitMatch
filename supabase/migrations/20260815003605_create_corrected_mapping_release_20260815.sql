
do $migration$
declare
  v_source_release_id uuid;
  v_new_release_id uuid;
  v_mapping_count integer;
  v_category_count integer;
  v_detail_count integer;
begin
  select id into strict v_source_release_id
  from fitmatch_catalog.releases
  where release_key = 'observed-official-2026-08-03__taxonomy-refined-2026-08-03';

  if not exists (
    select 1
    from fitmatch_taxonomy.policy_versions
    where code = 'taxonomy-corrected-2026-08-14'
      and taxonomy_version = 'observed-official-2026-08-03'
      and status = 'validated'
  ) then
    raise exception 'Validated corrected policy version is missing';
  end if;

  insert into fitmatch_catalog.releases (
    release_key,
    taxonomy_version,
    policy_version,
    status,
    bundle_checksum,
    app_taxonomy_checksum,
    expected_mapping_count,
    expected_qa_count,
    metadata
  )
  values (
    'observed-official-2026-08-03__taxonomy-corrected-2026-08-14',
    'observed-official-2026-08-03',
    'taxonomy-corrected-2026-08-14',
    'loading',
    'acb5d29f00840773f3283fc9ea5e8703078d7bb205a844e4da245940fdca0467',
    '123c693fc38c01d8edf877dbe9b651a6c40451a06752eed4bca3d14c2ac3bd57',
    3426,
    0,
    jsonb_build_object(
      'release_scope', 'mapping_only_snapshot',
      'copied_from_release_key', 'observed-official-2026-08-03__taxonomy-refined-2026-08-03',
      'documents_copied', false,
      'qa_full_validation_included', false,
      'created_reason', 'separate corrected relational mappings from stale refined release metadata'
    )
  )
  returning id into v_new_release_id;

  insert into fitmatch_catalog.app_categories (
    release_id, code, display_name, sort_order, is_active
  )
  select v_new_release_id, code, display_name, sort_order, is_active
  from fitmatch_catalog.app_categories
  where release_id = v_source_release_id;

  insert into fitmatch_catalog.app_category_details (
    release_id, category_code, code, display_name, sort_order, is_active
  )
  select v_new_release_id, category_code, code, display_name, sort_order, is_active
  from fitmatch_catalog.app_category_details
  where release_id = v_source_release_id;

  insert into fitmatch_catalog.source_category_mappings (
    release_id, source_identity, source, snapshot_id, external_category_id,
    target, normalized_path, decision_status, mapping_status,
    runtime_lookup_eligible, eligibility, semantic_category_code,
    semantic_garment_type, comparison_family, source_external_key,
    source_external_target_key, source_path_key, source_target_path_key,
    raw_record
  )
  select
    v_new_release_id, source_identity, source, snapshot_id, external_category_id,
    target, normalized_path, decision_status, mapping_status,
    runtime_lookup_eligible, eligibility, semantic_category_code,
    semantic_garment_type, comparison_family, source_external_key,
    source_external_target_key, source_path_key, source_target_path_key,
    raw_record
  from fitmatch_catalog.source_category_mappings
  where release_id = v_source_release_id;

  select count(*) into v_mapping_count
  from fitmatch_catalog.source_category_mappings
  where release_id = v_new_release_id;

  select count(*) into v_category_count
  from fitmatch_catalog.app_categories
  where release_id = v_new_release_id;

  select count(*) into v_detail_count
  from fitmatch_catalog.app_category_details
  where release_id = v_new_release_id;

  if v_mapping_count <> 3426 or v_category_count <> 11 or v_detail_count <> 75 then
    raise exception 'Clone count mismatch: mappings %, categories %, details %',
      v_mapping_count, v_category_count, v_detail_count;
  end if;

  update fitmatch_catalog.releases
  set status = 'validated',
      validated_at = now()
  where id = v_new_release_id;
end
$migration$;
;
