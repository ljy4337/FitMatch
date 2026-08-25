begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:extend-zara-production-sample-categories-v1'));

create temporary table _fitmatch_zara_sample_category_seed (
  audience text not null,
  external_category_id text not null,
  parent_external_category_id text not null,
  name text not null,
  original_path text not null,
  app_category text,
  app_detail_category text,
  garment_type_code text,
  mapping_status text not null,
  evidence_product_id text not null,
  primary key (audience, external_category_id)
) on commit drop;

insert into _fitmatch_zara_sample_category_seed values
  ('WOMEN','WOMAN:드레스:B.DRESS','WOMAN:드레스','B.DRESS','ZARA > 여성 > 드레스 > B.DRESS','dresses','one_piece',null,'review_required','561583709'),
  ('WOMEN','WOMAN:드레스:W.DRESS','WOMAN:드레스','W.DRESS','ZARA > 여성 > 드레스 > W.DRESS','dresses','one_piece',null,'review_required','558215502'),
  ('WOMEN','WOMAN:바지:B.PANTS','WOMAN:바지','B.PANTS','ZARA > 여성 > 바지 > B.PANTS','bottoms',null,'other_standard_pants','confirmed','548577264'),
  ('WOMEN','WOMAN:바지:C.PTON-LEGGING','WOMAN:바지','C.PTON-LEGGING','ZARA > 여성 > 바지 > C.PTON-LEGGING','bottoms',null,null,'review_required','561610369'),
  ('WOMEN','WOMAN:바지:L. PANT. PIJAMA','WOMAN:바지','L. PANT. PIJAMA','ZARA > 여성 > 바지 > L. PANT. PIJAMA','bottoms',null,null,'review_required','545473154'),
  ('WOMEN','WOMAN:스포츠 재킷:B.SHORT-OUTWEAR','WOMAN:스포츠 재킷','B.SHORT-OUTWEAR','ZARA > 여성 > 스포츠 재킷 > B.SHORT-OUTWEAR','outerwear','jacket','generic_jacket','confirmed','545439169'),
  ('WOMEN','WOMAN:티셔츠:C.CTAS FANTASI','WOMAN:티셔츠','C.CTAS FANTASI','ZARA > 여성 > 티셔츠 > C.CTAS FANTASI','tops',null,'tshirt','confirmed','545892778'),
  ('WOMEN','WOMAN:티셔츠:C.CTAS POSICIO','WOMAN:티셔츠','C.CTAS POSICIO','ZARA > 여성 > 티셔츠 > C.CTAS POSICIO','tops',null,'tshirt','confirmed','557446393'),
  ('MEN','MAN:바지:Sastrería Pant.','MAN:바지','Sastrería Pant.','ZARA > 남성 > 바지 > Sastrería Pant.','bottoms',null,'other_standard_pants','confirmed','556139700'),
  ('MEN','MAN:셔츠:F. Camisería','MAN:셔츠','F. Camisería','ZARA > 남성 > 셔츠 > F. Camisería','tops','shirt_blouse','shirt_blouse','confirmed','552163213'),
  ('MEN','MAN:스포츠 재킷:F. Cazadora','MAN:스포츠 재킷','F. Cazadora','ZARA > 남성 > 스포츠 재킷 > F. Cazadora','outerwear','jacket','generic_jacket','confirmed','545406831'),
  ('MEN','MAN:티셔츠:Camiseta M/L','MAN:티셔츠','Camiseta M/L','ZARA > 남성 > 티셔츠 > Camiseta M/L','tops',null,'tshirt','confirmed','550429724'),
  ('MEN','MAN:티셔츠:F. Camiseta','MAN:티셔츠','F. Camiseta','ZARA > 남성 > 티셔츠 > F. Camiseta','tops',null,'tshirt','confirmed','553028015');

do $$
declare
  v_source_id uuid;
  v_row record;
  v_parent_id uuid;
  v_category_id uuid;
  v_app_category_id uuid;
begin
  select id into strict v_source_id from public.sources where code='zara';

  for v_row in select * from _fitmatch_zara_sample_category_seed
  loop
    select id into strict v_parent_id
    from public.source_categories
    where source_id=v_source_id and brand_id is null
      and audience=v_row.audience
      and external_category_id=v_row.parent_external_category_id;

    v_app_category_id := null;
    if v_row.app_category is not null then
      select id into v_app_category_id
      from public.app_categories
      where code=coalesce(v_row.app_detail_category,v_row.app_category) and is_active
      order by depth desc limit 1;
      if v_app_category_id is null then
        raise exception 'Missing FitMatch category %/%',v_row.app_category,v_row.app_detail_category;
      end if;
    end if;

    select id into v_category_id
    from public.source_categories
    where source_id=v_source_id and brand_id is null
      and audience=v_row.audience
      and external_category_id=v_row.external_category_id
    order by created_at limit 1;

    if v_category_id is null then
      insert into public.source_categories (
        source_id,brand_id,parent_id,external_category_id,name,original_path,
        audience,depth,app_category,app_detail_category,app_category_id,metadata,is_active
      ) values (
        v_source_id,null,v_parent_id,v_row.external_category_id,v_row.name,v_row.original_path,
        v_row.audience,2,v_row.app_category,v_row.app_detail_category,v_app_category_id,
        jsonb_build_object(
          'managed_by','fitmatch_zara_production_sample_30',
          'catalog_snapshot_date','2026-08-21',
          'external_category_namespace','zara_kr_analytics_section_family_subfamily',
          'mapping_status',case when v_row.mapping_status='confirmed' then 'EXACT' else 'AMBIGUOUS' end,
          'evidence_product_id',v_row.evidence_product_id,
          'is_leaf',true,
          'measurement_mapping_status','NOT_IMPLEMENTED',
          'production_release_eligible',false
        ),true
      ) returning id into v_category_id;
    else
      update public.source_categories set
        parent_id=v_parent_id,
        name=v_row.name,
        original_path=v_row.original_path,
        app_category=v_row.app_category,
        app_detail_category=v_row.app_detail_category,
        app_category_id=v_app_category_id,
        metadata=public.source_categories.metadata || jsonb_build_object(
          'managed_by','fitmatch_zara_production_sample_30',
          'catalog_snapshot_date','2026-08-21',
          'external_category_namespace','zara_kr_analytics_section_family_subfamily',
          'mapping_status',case when v_row.mapping_status='confirmed' then 'EXACT' else 'AMBIGUOUS' end,
          'evidence_product_id',v_row.evidence_product_id,
          'is_leaf',true,
          'measurement_mapping_status','NOT_IMPLEMENTED',
          'production_release_eligible',false
        ),
        is_active=true,
        updated_at=now()
      where id=v_category_id;
    end if;
  end loop;
end $$;

do $$
declare
  v_source_id uuid;
begin
  select id into strict v_source_id from public.sources where code='zara';

  if exists (
    select 1 from _fitmatch_zara_sample_category_seed seed
    left join public.garment_types garment
      on garment.code=seed.garment_type_code and garment.is_active
    where seed.garment_type_code is not null and garment.id is null
  ) then
    raise exception 'Missing garment type for ZARA production sample category';
  end if;

  insert into public.source_category_mappings (
    source_category_id,garment_type_id,default_sleeve_class_code,
    default_pants_length_code,default_body_length_code,resolution_mode,
    mapping_status,evidence,policy_version
  )
  select category.id,garment.id,null,null,null,
    case when seed.mapping_status='confirmed' then 'explicit_original_path' else 'unresolved' end,
    seed.mapping_status,
    jsonb_build_object(
      'source','zara',
      'basis','official_structured_product_sample_30',
      'evidence_product_id',seed.evidence_product_id,
      'measurement_mapping_status','not_implemented',
      'production_release_eligible',false,
      'fail_closed',seed.mapping_status<>'confirmed'
    ),
    'zara-production-sample-2026-08-21-v1'
  from _fitmatch_zara_sample_category_seed seed
  join public.source_categories category
    on category.source_id=v_source_id and category.brand_id is null
   and category.audience=seed.audience
   and category.external_category_id=seed.external_category_id
  left join public.garment_types garment
    on garment.code=seed.garment_type_code and garment.is_active
  on conflict (source_category_id) do update set
    garment_type_id=excluded.garment_type_id,
    default_sleeve_class_code=excluded.default_sleeve_class_code,
    default_pants_length_code=excluded.default_pants_length_code,
    default_body_length_code=excluded.default_body_length_code,
    resolution_mode=excluded.resolution_mode,
    mapping_status=excluded.mapping_status,
    evidence=excluded.evidence,
    policy_version=excluded.policy_version,
    updated_at=now();

  insert into public.client_source_category_mappings (
    source_category_id,garment_type_id,default_sleeve_class_code,
    default_pants_length_code,default_body_length_code,mapping_status,
    policy_version,source_code,external_category_id,original_path_hash,garment_type_code
  )
  select mapping.source_category_id,mapping.garment_type_id,
    mapping.default_sleeve_class_code,mapping.default_pants_length_code,
    mapping.default_body_length_code,mapping.mapping_status,mapping.policy_version,
    'zara',category.external_category_id,
    encode(extensions.digest(category.original_path,'sha256'),'hex'),garment.code
  from public.source_category_mappings mapping
  join public.source_categories category on category.id=mapping.source_category_id
  left join public.garment_types garment on garment.id=mapping.garment_type_id
  join _fitmatch_zara_sample_category_seed seed
    on seed.audience=category.audience
   and seed.external_category_id=category.external_category_id
  where category.source_id=v_source_id and category.brand_id is null
  on conflict (source_category_id) do update set
    garment_type_id=excluded.garment_type_id,
    default_sleeve_class_code=excluded.default_sleeve_class_code,
    default_pants_length_code=excluded.default_pants_length_code,
    default_body_length_code=excluded.default_body_length_code,
    mapping_status=excluded.mapping_status,
    policy_version=excluded.policy_version,
    source_code=excluded.source_code,
    external_category_id=excluded.external_category_id,
    original_path_hash=excluded.original_path_hash,
    garment_type_code=excluded.garment_type_code,
    updated_at=now();
end $$;

do $$
declare
  v_old_release fitmatch_catalog.releases%rowtype;
  v_new_release_id uuid:=gen_random_uuid();
  v_snapshot_id uuid:=gen_random_uuid();
  v_old_count integer;
  v_confirmed_count integer;
  v_new_count integer;
begin
  select * into strict v_old_release
  from fitmatch_catalog.releases
  where status='active'
  order by activated_at desc nulls last,created_at desc
  limit 1 for update;

  select count(*) into v_old_count
  from fitmatch_catalog.source_category_mappings
  where release_id=v_old_release.id;
  select count(*) into v_confirmed_count
  from _fitmatch_zara_sample_category_seed where mapping_status='confirmed';
  if v_confirmed_count<>9 then
    raise exception 'Expected 9 confirmed ZARA sample categories, got %',v_confirmed_count;
  end if;

  insert into fitmatch_catalog.releases (
    id,release_key,taxonomy_version,policy_version,status,bundle_checksum,
    app_taxonomy_checksum,expected_mapping_count,expected_qa_count,metadata
  ) values (
    v_new_release_id,
    v_old_release.release_key || '__zara-sample30-2026-08-21',
    v_old_release.taxonomy_version,
    v_old_release.policy_version || '+zara-sample30-2026-08-21-v1',
    'loading',
    encode(extensions.digest(v_old_release.bundle_checksum || ':zara-sample30-2026-08-21-v1','sha256'),'hex'),
    v_old_release.app_taxonomy_checksum,
    v_old_count+v_confirmed_count,
    v_old_release.expected_qa_count,
    v_old_release.metadata || jsonb_build_object(
      'copied_from_release_id',v_old_release.id,
      'zara_sample_product_count',30,
      'zara_new_structured_leaf_count',13,
      'zara_new_confirmed_leaf_count',9,
      'zara_measurement_mapping_status','not_implemented',
      'zara_production_release_eligible',false
    )
  );

  insert into fitmatch_catalog.source_category_mappings (
    release_id,source_identity,source,snapshot_id,external_category_id,target,
    normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
    eligibility,semantic_category_code,semantic_garment_type,comparison_family,
    source_external_key,source_external_target_key,source_path_key,
    source_target_path_key,raw_record,created_at
  )
  select v_new_release_id,source_identity,source,snapshot_id,external_category_id,target,
    normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
    eligibility,semantic_category_code,semantic_garment_type,comparison_family,
    source_external_key,source_external_target_key,source_path_key,
    source_target_path_key,raw_record,created_at
  from fitmatch_catalog.source_category_mappings
  where release_id=v_old_release.id;

  insert into fitmatch_catalog.source_category_mappings (
    release_id,source_identity,source,snapshot_id,external_category_id,target,
    normalized_path,decision_status,mapping_status,runtime_lookup_eligible,
    eligibility,semantic_category_code,semantic_garment_type,comparison_family,
    source_external_key,source_external_target_key,source_path_key,
    source_target_path_key,raw_record
  )
  select v_new_release_id,
    concat_ws('|','zara',v_snapshot_id::text,category.external_category_id,
      case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,category.original_path),
    'zara',v_snapshot_id,category.external_category_id,
    case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
    category.original_path,'confirmed','direct',true,true,
    garment.major_category_code,garment.code,garment.comparison_group_code,
    'zara|'||category.external_category_id,
    concat_ws('|','zara',category.external_category_id,
      case category.audience when 'MEN' then 'MALE' else 'FEMALE' end),
    'zara|'||category.original_path,
    concat_ws('|','zara',case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,category.original_path),
    jsonb_build_object(
      'source','zara','snapshotID',v_snapshot_id,
      'externalCategoryID',category.external_category_id,
      'target',case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
      'normalizedPath',category.original_path,'decisionStatus','confirmed',
      'mappingStatus','direct','runtimeLookupEligible',true,'eligibility',true,
      'semanticCategoryCode',garment.major_category_code,
      'semanticGarmentType',garment.code,
      'comparisonFamily',garment.comparison_group_code,
      'resolutionMethod','verified_zara_production_sample_30',
      'policyVersion','zara-production-sample-2026-08-21-v1',
      'measurementMappingStatus','not_implemented',
      'productionReleaseEligible',false
    )
  from _fitmatch_zara_sample_category_seed seed
  join public.sources source on source.code='zara'
  join public.source_categories category
    on category.source_id=source.id and category.brand_id is null
   and category.audience=seed.audience
   and category.external_category_id=seed.external_category_id
  join public.source_category_mappings mapping on mapping.source_category_id=category.id
  join public.garment_types garment on garment.id=mapping.garment_type_id
  where seed.mapping_status='confirmed';

  select count(*) into v_new_count
  from fitmatch_catalog.source_category_mappings where release_id=v_new_release_id;
  if v_new_count<>v_old_count+v_confirmed_count then
    raise exception 'ZARA runtime release count mismatch: expected %, got %',v_old_count+v_confirmed_count,v_new_count;
  end if;

  update fitmatch_catalog.releases set status='retired'
  where id=v_old_release.id;
  update fitmatch_catalog.releases
  set status='active',validated_at=now(),activated_at=now()
  where id=v_new_release_id;
end $$;

do $$
declare
  v_total integer;
  v_confirmed integer;
  v_review integer;
  v_rejected integer;
begin
  select count(*),
    count(*) filter(where mapping_status='confirmed'),
    count(*) filter(where mapping_status='review_required'),
    count(*) filter(where mapping_status='rejected')
  into v_total,v_confirmed,v_review,v_rejected
  from public.client_source_category_mappings where source_code='zara';
  if v_total<>262 or v_confirmed<>65 or v_review<>55 or v_rejected<>142 then
    raise exception 'Unexpected ZARA client mapping totals: total %, confirmed %, review %, rejected %',
      v_total,v_confirmed,v_review,v_rejected;
  end if;
end $$;

commit;
