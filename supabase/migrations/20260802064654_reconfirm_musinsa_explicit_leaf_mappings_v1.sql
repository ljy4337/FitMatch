
with rules(leaf_name, garment_code, sleeve_code, pants_code, body_code) as (
  values
    ('긴소매 티셔츠','tshirt','long_sleeve',null,null),
    ('민소매 티셔츠','tank_top','sleeveless',null,null),
    ('반소매 티셔츠','tshirt','short_sleeve',null,null),
    ('니트/스웨터','knit_sweater',null,null,null),
    ('맨투맨/스웨트','sweatshirt',null,null,null),
    ('셔츠/블라우스','shirt_blouse',null,null,null),
    ('피케/카라 티셔츠','polo_shirt',null,null,null),
    ('후드 티셔츠','hoodie',null,null,null),
    ('데님 팬츠','denim_pants',null,null,null),
    ('레깅스','leggings',null,null,null),
    ('숏 팬츠','other_standard_pants',null,'short_length',null),
    ('슈트 팬츠/슬랙스','slacks_trousers',null,null,null),
    ('코튼 팬츠','chino_cotton_pants',null,null,null),
    ('트레이닝/조거 팬츠','sweat_jogger_pants',null,null,null),
    ('조거 팬츠','sweat_jogger_pants',null,null,null),
    ('트레이닝 팬츠','sweat_jogger_pants',null,null,null),
    ('겨울 기타 코트','coat',null,null,null),
    ('겨울 더블 코트','coat',null,null,null),
    ('겨울 싱글 코트','coat',null,null,null),
    ('환절기 코트','coat',null,null,null),
    ('코트','coat',null,null,null),
    ('경량 패딩','puffer_jacket',null,null,null),
    ('롱패딩/헤비 아우터','puffer_jacket',null,null,'long_body'),
    ('숏패딩/헤비 아우터','puffer_jacket',null,null,'short_body'),
    ('패딩 베스트','puffer_vest',null,null,null),
    ('슈트/블레이저 재킷','blazer',null,null,null),
    ('아노락 재킷','anorak',null,null,null),
    ('베스트','outer_vest',null,null,null),
    ('후드 집업','zip_hoodie',null,null,null),
    ('카디건','cardigan',null,null,null)
)
update public.source_category_mappings m
set garment_type_id = gt.id,
    default_sleeve_class_code = r.sleeve_code,
    default_pants_length_code = r.pants_code,
    default_body_length_code = r.body_code,
    resolution_mode = 'explicit_original_path',
    mapping_status = 'confirmed',
    evidence = jsonb_build_object(
      'rule', 'musinsa_leaf_exact_v1',
      'source_field', 'source_categories.name',
      'leaf_name', sc.name,
      'original_path', sc.original_path,
      'approval_scope', 'explicit_leaf_only',
      'approved_on', '2026-08-02',
      'previous_state', jsonb_build_object(
        'mapping_status', m.mapping_status,
        'policy_version', m.policy_version,
        'resolution_mode', m.resolution_mode,
        'evidence', m.evidence
      )
    ),
    policy_version = 'v1_musinsa_leaf_exact',
    updated_at = now()
from public.source_categories sc
join public.sources s
  on s.id = sc.source_id
 and s.code = 'musinsa'
join rules r
  on r.leaf_name = sc.name
join public.garment_types gt
  on gt.code = r.garment_code
where m.source_category_id = sc.id
  and m.mapping_status = 'review_required'
  and (
    sc.original_path ~ '^(상의|바지|아우터)( >|$)'
    or sc.original_path ~ '^키즈 > (상의|바지|아우터)( >|$)'
  );

update public.client_source_category_mappings c
set garment_type_id = m.garment_type_id,
    default_sleeve_class_code = m.default_sleeve_class_code,
    default_pants_length_code = m.default_pants_length_code,
    default_body_length_code = m.default_body_length_code,
    mapping_status = m.mapping_status,
    policy_version = m.policy_version,
    updated_at = now()
from public.source_category_mappings m
where c.source_category_id = m.source_category_id
  and m.policy_version = 'v1_musinsa_leaf_exact';

do $$
declare
  admin_count bigint;
  client_count bigint;
  mismatch_count bigint;
  unintended_count bigint;
begin
  select count(*) into admin_count
  from public.source_category_mappings
  where mapping_status = 'confirmed'
    and policy_version = 'v1_musinsa_leaf_exact';

  select count(*) into client_count
  from public.client_source_category_mappings
  where mapping_status = 'confirmed'
    and policy_version = 'v1_musinsa_leaf_exact';

  select count(*) into mismatch_count
  from public.source_category_mappings m
  join public.client_source_category_mappings c using (source_category_id)
  where m.policy_version = 'v1_musinsa_leaf_exact'
    and (
      c.garment_type_id is distinct from m.garment_type_id
      or c.default_sleeve_class_code is distinct from m.default_sleeve_class_code
      or c.default_pants_length_code is distinct from m.default_pants_length_code
      or c.default_body_length_code is distinct from m.default_body_length_code
      or c.mapping_status is distinct from m.mapping_status
      or c.policy_version is distinct from m.policy_version
    );

  select count(*) into unintended_count
  from public.source_category_mappings m
  join public.source_categories sc on sc.id = m.source_category_id
  join public.sources s on s.id = sc.source_id
  where m.policy_version = 'v1_musinsa_leaf_exact'
    and (
      s.code <> 'musinsa'
      or not (
        sc.original_path ~ '^(상의|바지|아우터)( >|$)'
        or sc.original_path ~ '^키즈 > (상의|바지|아우터)( >|$)'
      )
    );

  if admin_count <> 44 then
    raise exception 'Expected 44 confirmed admin mappings, got %', admin_count;
  end if;
  if client_count <> 44 then
    raise exception 'Expected 44 confirmed client mappings, got %', client_count;
  end if;
  if mismatch_count <> 0 then
    raise exception 'Admin/client mapping mismatch count: %', mismatch_count;
  end if;
  if unintended_count <> 0 then
    raise exception 'Unintended mapping count: %', unintended_count;
  end if;
end
$$;
;
