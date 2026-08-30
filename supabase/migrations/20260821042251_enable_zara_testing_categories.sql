begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:enable-zara-testing-categories-v1'));

-- This migration makes the bounded 2026-08-21 ZARA sample taxonomy usable in
-- staging/debug flows. It does not claim full ZARA taxonomy coverage and does
-- not add canonical measurement mappings.
create temporary table _fitmatch_zara_mapping_seed (
  audience text not null,
  external_category_id text not null,
  garment_type_code text,
  default_pants_length_code text,
  mapping_status text not null,
  resolution_mode text not null,
  primary key (audience, external_category_id)
) on commit drop;

insert into _fitmatch_zara_mapping_seed values
  ('MEN','MAN',null,null,'review_required','unresolved'),
  ('MEN','MAN:티셔츠','tshirt',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:셔츠','shirt_blouse',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:브레이저','blazer',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:바지',null,null,'review_required','unresolved'),
  ('MEN','MAN:스웨터','knit_sweater',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:스포츠 재킷','generic_jacket',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:버뮤다반바지','other_standard_pants','short_length','confirmed','explicit_original_path'),
  ('MEN','MAN:스웨트 셔츠','sweatshirt',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:셔츠:B. Camisería','shirt_blouse',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:브레이저:Blasier','blazer',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:바지:F. Pant Resto','other_standard_pants',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:바지:B. Pant Denim','denim_pants',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:스웨터:B. Jersey M/C','knit_sweater',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:스포츠 재킷:B. Cazadora','generic_jacket',null,'confirmed','explicit_original_path'),
  ('MEN','MAN:버뮤다반바지:F.Bermuda Resto','other_standard_pants','short_length','confirmed','explicit_original_path'),
  ('MEN','MAN:스웨트 셔츠:F. Sudadera','sweatshirt',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN',null,null,'review_required','unresolved'),
  ('WOMEN','WOMAN:티셔츠','tshirt',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:드레스',null,null,'review_required','unresolved'),
  ('WOMEN','WOMAN:셔츠','shirt_blouse',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:가디건','cardigan',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:스포츠 재킷','generic_jacket',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:바지',null,null,'review_required','unresolved'),
  ('WOMEN','WOMAN:버뮤다반바지','other_standard_pants','short_length','confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:브레이저','blazer',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:치마','skirt',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:티셔츠:C.CTAS BASICAS','tshirt',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:드레스:C.VESTIDO FANTA',null,null,'review_required','unresolved'),
  ('WOMEN','WOMAN:셔츠:B.SHIRT','shirt_blouse',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:가디건:KNIT CARDIGAN','cardigan',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:스포츠 재킷:T.SHORT-OUTWEAR','generic_jacket',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:바지:B.FOLDER PANTS','other_standard_pants',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:버뮤다반바지:T.BERMUDAS','other_standard_pants','short_length','confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:브레이저:B.BLAZER','blazer',null,'confirmed','explicit_original_path'),
  ('WOMEN','WOMAN:치마:T.SKIRT','skirt',null,'confirmed','explicit_original_path');

do $$
declare
  v_source_id uuid;
  v_seed_count integer;
begin
  select id into strict v_source_id from public.sources where code = 'zara';

  select count(*) into v_seed_count from _fitmatch_zara_mapping_seed;
  if v_seed_count <> 36 then
    raise exception 'Expected 36 ZARA category decisions, got %', v_seed_count;
  end if;

  if exists (
    select 1
    from _fitmatch_zara_mapping_seed seed
    left join public.source_categories category
      on category.source_id = v_source_id
     and category.brand_id is null
     and category.audience = seed.audience
     and category.external_category_id = seed.external_category_id
    where category.id is null
  ) then
    raise exception 'A ZARA source category required by the mapping seed is missing';
  end if;

  if exists (
    select 1
    from _fitmatch_zara_mapping_seed seed
    left join public.garment_types garment
      on garment.code = seed.garment_type_code and garment.is_active
    where seed.garment_type_code is not null and garment.id is null
  ) then
    raise exception 'A garment type required by the ZARA mapping seed is missing';
  end if;

  insert into public.source_category_mappings (
    source_category_id,
    garment_type_id,
    default_sleeve_class_code,
    default_pants_length_code,
    default_body_length_code,
    resolution_mode,
    mapping_status,
    evidence,
    policy_version
  )
  select
    category.id,
    garment.id,
    null,
    seed.default_pants_length_code,
    null,
    seed.resolution_mode,
    seed.mapping_status,
    jsonb_build_object(
      'source','zara',
      'catalog_snapshot_date','2026-08-21',
      'basis','official_structured_section_family_subfamily_sample',
      'measurement_mapping_status','not_implemented',
      'production_release_eligible',false,
      'fail_closed',seed.mapping_status <> 'confirmed'
    ),
    'zara-structured-sample-2026-08-21-v1'
  from _fitmatch_zara_mapping_seed seed
  join public.source_categories category
    on category.source_id = v_source_id
   and category.brand_id is null
   and category.audience = seed.audience
   and category.external_category_id = seed.external_category_id
  left join public.garment_types garment
    on garment.code = seed.garment_type_code and garment.is_active
  on conflict (source_category_id) do update set
    garment_type_id = excluded.garment_type_id,
    default_sleeve_class_code = excluded.default_sleeve_class_code,
    default_pants_length_code = excluded.default_pants_length_code,
    default_body_length_code = excluded.default_body_length_code,
    resolution_mode = excluded.resolution_mode,
    mapping_status = excluded.mapping_status,
    evidence = excluded.evidence,
    policy_version = excluded.policy_version,
    updated_at = now();

  if (
    select count(*)
    from public.source_category_mappings mapping
    join public.source_categories category on category.id = mapping.source_category_id
    where category.source_id = v_source_id and category.brand_id is null
  ) <> 36 then
    raise exception 'Expected 36 public ZARA category mappings';
  end if;

  if (
    select count(*)
    from public.source_category_mappings mapping
    join public.source_categories category on category.id = mapping.source_category_id
    where category.source_id = v_source_id and category.brand_id is null
      and mapping.mapping_status = 'confirmed'
  ) <> 30 then
    raise exception 'Expected 30 confirmed public ZARA category mappings';
  end if;

  update public.sources
  set is_active = true, updated_at = now()
  where id = v_source_id;
end $$;

-- Runtime mappings are immutable release snapshots. Clone the current active
-- release, append only the 30 confirmed ZARA decisions, validate, then switch
-- the active pointer atomically. Review-required rows are intentionally absent
-- so the classifier continues to fail closed for those categories.
do $$
declare
  v_old_release fitmatch_catalog.releases%rowtype;
  v_new_release_id uuid := gen_random_uuid();
  v_snapshot_id uuid := gen_random_uuid();
  v_old_count integer;
  v_zara_count integer;
  v_new_count integer;
begin
  select * into strict v_old_release
  from fitmatch_catalog.releases
  where status = 'active'
  order by activated_at desc nulls last, created_at desc
  limit 1
  for update;

  select count(*) into v_old_count
  from fitmatch_catalog.source_category_mappings
  where release_id = v_old_release.id;

  select count(*) into v_zara_count
  from public.source_category_mappings mapping
  join public.source_categories category on category.id = mapping.source_category_id
  join public.sources source on source.id = category.source_id
  where source.code = 'zara' and mapping.mapping_status = 'confirmed';

  if v_zara_count <> 30 then
    raise exception 'Expected 30 confirmed ZARA runtime mappings, got %', v_zara_count;
  end if;

  insert into fitmatch_catalog.releases (
    id, release_key, taxonomy_version, policy_version, status,
    bundle_checksum, app_taxonomy_checksum,
    expected_mapping_count, expected_qa_count, metadata
  ) values (
    v_new_release_id,
    v_old_release.release_key || '__zara-test-2026-08-21',
    v_old_release.taxonomy_version,
    v_old_release.policy_version || '+zara-test-2026-08-21-v1',
    'loading',
    encode(extensions.digest(v_old_release.bundle_checksum || ':zara-test-2026-08-21-v1', 'sha256'), 'hex'),
    v_old_release.app_taxonomy_checksum,
    v_old_count + v_zara_count,
    v_old_release.expected_qa_count,
    v_old_release.metadata || jsonb_build_object(
      'copied_from_release_id',v_old_release.id,
      'copied_from_release_key',v_old_release.release_key,
      'zara_mapping_scope','30 confirmed bounded structured categories',
      'zara_measurement_mapping_status','not_implemented',
      'zara_production_release_eligible',false
    )
  );

  insert into fitmatch_catalog.source_category_mappings (
    release_id, source_identity, source, snapshot_id, external_category_id,
    target, normalized_path, decision_status, mapping_status,
    runtime_lookup_eligible, eligibility,
    semantic_category_code, semantic_garment_type, comparison_family,
    source_external_key, source_external_target_key,
    source_path_key, source_target_path_key, raw_record, created_at
  )
  select
    v_new_release_id, source_identity, source, snapshot_id, external_category_id,
    target, normalized_path, decision_status, mapping_status,
    runtime_lookup_eligible, eligibility,
    semantic_category_code, semantic_garment_type, comparison_family,
    source_external_key, source_external_target_key,
    source_path_key, source_target_path_key, raw_record, created_at
  from fitmatch_catalog.source_category_mappings
  where release_id = v_old_release.id;

  insert into fitmatch_catalog.source_category_mappings (
    release_id, source_identity, source, snapshot_id, external_category_id,
    target, normalized_path, decision_status, mapping_status,
    runtime_lookup_eligible, eligibility,
    semantic_category_code, semantic_garment_type, comparison_family,
    source_external_key, source_external_target_key,
    source_path_key, source_target_path_key, raw_record
  )
  select
    v_new_release_id,
    concat_ws('|','zara',v_snapshot_id::text,category.external_category_id,
      case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
      category.original_path),
    'zara',
    v_snapshot_id,
    category.external_category_id,
    case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
    category.original_path,
    'confirmed',
    'direct',
    true,
    true,
    garment.major_category_code,
    garment.code,
    garment.comparison_group_code,
    'zara|' || category.external_category_id,
    concat_ws('|','zara',category.external_category_id,
      case category.audience when 'MEN' then 'MALE' else 'FEMALE' end),
    'zara|' || category.original_path,
    concat_ws('|','zara',case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
      category.original_path),
    jsonb_build_object(
      'source','zara',
      'target',case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
      'snapshotID',v_snapshot_id,
      'externalCategoryID',category.external_category_id,
      'normalizedPath',category.original_path,
      'decisionStatus','confirmed',
      'mappingStatus','direct',
      'runtimeLookupEligible',true,
      'eligibility',true,
      'semanticCategoryCode',garment.major_category_code,
      'semanticGarmentType',garment.code,
      'comparisonFamily',garment.comparison_group_code,
      'resolutionMethod','verified_zara_structured_category_sample',
      'policyVersion','zara-structured-sample-2026-08-21-v1',
      'measurementMappingStatus','not_implemented',
      'productionReleaseEligible',false
    )
  from public.source_category_mappings mapping
  join public.source_categories category on category.id = mapping.source_category_id
  join public.sources source on source.id = category.source_id
  join public.garment_types garment on garment.id = mapping.garment_type_id
  where source.code = 'zara' and mapping.mapping_status = 'confirmed';

  select count(*) into v_new_count
  from fitmatch_catalog.source_category_mappings
  where release_id = v_new_release_id;

  if v_new_count <> v_old_count + v_zara_count then
    raise exception 'Runtime release count mismatch: expected %, got %', v_old_count + v_zara_count, v_new_count;
  end if;

  if exists (
    select 1 from fitmatch_catalog.source_category_mappings
    where release_id = v_new_release_id and source = 'zara'
      and (decision_status <> 'confirmed' or not runtime_lookup_eligible or not eligibility)
  ) then
    raise exception 'Unsafe ZARA runtime mapping detected';
  end if;

  update fitmatch_catalog.releases
  set status = 'retired'
  where id = v_old_release.id;

  update fitmatch_catalog.releases
  set status = 'active', validated_at = now(), activated_at = now()
  where id = v_new_release_id;
end $$;

commit;
;
