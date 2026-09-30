
create temporary table tmp_uniqlo_leaf_targets (
  source_category_id uuid primary key,
  garment_code text not null,
  sleeve_code text,
  leg_code text,
  body_code text
) on commit drop;

insert into tmp_uniqlo_leaf_targets
select sc.id,
  case
    when sc.name in ('티셔츠','그래픽 티셔츠','그래픽티셔츠','T-Shirts','티셔츠(긴팔)','티셔츠(반팔)') then 'tshirt'
    when sc.name in ('탱크탑','Tank Top') then 'tank_top'
    when sc.name='니트' and sc.original_path not like '%폴로셔츠%' then 'knit_sweater'
    when sc.name in ('3D 니트','3D Knit','V넥 니트','디자인 니트','메리노 니트','크루넥 니트','폴로 니트','긴팔 니트','반팔 니트') then 'knit_sweater'
    when sc.name in ('가디건','Cardigan') then 'cardigan'
    when sc.name in ('셔츠','Shirts','디자인 블라우스','반팔셔츠') then 'shirt_blouse'
    when sc.name in ('폴로 셔츠','폴로셔츠','폴로셔츠 (카라티)','Polo','DRY-EX Polo Shirts') then 'polo_shirt'
    when sc.name in ('Sweat','Sweats') then 'sweatshirt'
    when sc.name in ('그래픽 스웨트','(X)그래픽 스웨트','드라이 스웨트','드라이스웨트','보아 스웨트')
      and sc.original_path like '%스웨트셔츠 & 후드집업%' then 'sweatshirt'
    when sc.name in ('진','진(청바지)') then 'denim_pants'
    when sc.name='데님' and sc.original_path like '%팬츠%' then 'denim_pants'
    when sc.name='치노 팬츠' then 'chino_cotton_pants'
    when sc.name='카고 팬츠' then 'cargo_pants'
    when sc.name in ('레깅스','크롭레깅스','후리스레깅스') then 'leggings'
    when sc.name in ('쇼트 팬츠','쇼트팬츠','쇼트 팬츠(반바지)','롱 팬츠','롱팬츠') then 'other_standard_pants'
    when sc.name in ('스커트','Skirt','Skirts') then 'skirt'
    when sc.name='블루종' and sc.original_path like '%아우터 > 파카 & 블루종 > 블루종' then 'blouson'
    when sc.name='Blousons' then 'blouson'
    when sc.name='Coats' then 'coat'
    when sc.name='패딩' and sc.original_path like '%아우터%패딩' then 'puffer_jacket'
    when sc.name='베스트' and sc.original_path like '%경량 패딩 (PUFFTECH) > 베스트' then 'puffer_vest'
    when sc.name='베스트' and sc.original_path like '%니트% > 베스트' then 'knit_vest'
    when sc.name='베스트' and sc.original_path like '%아우터 > 베스트' then 'outer_vest'
    when sc.name='풀집 후디' and sc.original_path like '%아우터 > 풀집 후디' then 'zip_hoodie'
    when sc.name='코치재킷' then 'windbreaker'
  end,
  case
    when sc.name in ('탱크탑','Tank Top') then 'sleeveless'
    when sc.name in ('티셔츠(긴팔)','긴팔 니트') then 'long_sleeve'
    when sc.name in ('티셔츠(반팔)','반팔 니트','반팔셔츠') then 'short_sleeve'
    when sc.name='베스트' and sc.original_path like '%니트% > 베스트' then 'sleeveless'
  end,
  case
    when sc.name in ('진','진(청바지)','롱 팬츠','롱팬츠') then 'long_length'
    when sc.name in ('쇼트 팬츠','쇼트팬츠','쇼트 팬츠(반바지)') then 'short_length'
    when sc.name='데님' and sc.original_path like '%쇼트 팬츠(반바지)%' then 'short_length'
    when sc.name='크롭레깅스' then 'cropped_length'
  end,
  null::text
from public.source_categories sc
join public.sources s on s.id=sc.source_id and s.code='uniqlo'
join public.source_category_mappings scm on scm.source_category_id=sc.id
where scm.mapping_status='review_required'
  and (
    sc.name in (
      '티셔츠','그래픽 티셔츠','그래픽티셔츠','T-Shirts','티셔츠(긴팔)','티셔츠(반팔)',
      '탱크탑','Tank Top','3D 니트','3D Knit','V넥 니트','디자인 니트','메리노 니트',
      '크루넥 니트','폴로 니트','긴팔 니트','반팔 니트','가디건','Cardigan','셔츠',
      'Shirts','디자인 블라우스','반팔셔츠','폴로 셔츠','폴로셔츠','폴로셔츠 (카라티)',
      'Polo','DRY-EX Polo Shirts','Sweat','Sweats','진','진(청바지)','치노 팬츠',
      '카고 팬츠','레깅스','크롭레깅스','후리스레깅스','쇼트 팬츠','쇼트팬츠',
      '쇼트 팬츠(반바지)','롱 팬츠','롱팬츠','스커트','Skirt','Skirts','Blousons',
      'Coats','코치재킷'
    )
    or (sc.name='니트' and sc.original_path not like '%폴로셔츠%')
    or (sc.name in ('그래픽 스웨트','(X)그래픽 스웨트','드라이 스웨트','드라이스웨트','보아 스웨트')
        and sc.original_path like '%스웨트셔츠 & 후드집업%')
    or (sc.name='데님' and sc.original_path like '%팬츠%')
    or (sc.name='블루종' and sc.original_path like '%아우터 > 파카 & 블루종 > 블루종')
    or (sc.name='패딩' and sc.original_path like '%아우터%패딩')
    or (sc.name='베스트' and (
        sc.original_path like '%경량 패딩 (PUFFTECH) > 베스트'
        or sc.original_path like '%니트% > 베스트'
        or sc.original_path like '%아우터 > 베스트'
    ))
    or (sc.name='풀집 후디' and sc.original_path like '%아우터 > 풀집 후디')
  );

delete from tmp_uniqlo_leaf_targets where garment_code is null;

do $$
begin
  if (select count(*) from tmp_uniqlo_leaf_targets) <> 165 then
    raise exception 'Expected 165 explicit Uniqlo targets, found %',
      (select count(*) from tmp_uniqlo_leaf_targets);
  end if;
  if exists (
    select 1 from tmp_uniqlo_leaf_targets t
    left join public.garment_types gt on gt.code=t.garment_code
    where gt.id is null
  ) then
    raise exception 'Unknown garment code in Uniqlo target set';
  end if;
  if exists (
    select 1 from tmp_uniqlo_leaf_targets t
    left join public.comparison_length_classes lc
      on lc.code=t.sleeve_code and lc.axis_code='sleeve'
    where t.sleeve_code is not null and lc.code is null
  ) or exists (
    select 1 from tmp_uniqlo_leaf_targets t
    left join public.comparison_length_classes lc
      on lc.code=t.leg_code and lc.axis_code='leg'
    where t.leg_code is not null and lc.code is null
  ) then
    raise exception 'Invalid length code in Uniqlo target set';
  end if;
end $$;

update public.source_category_mappings scm
set garment_type_id=gt.id,
    default_sleeve_class_code=t.sleeve_code,
    default_pants_length_code=t.leg_code,
    default_body_length_code=t.body_code,
    resolution_mode='explicit_original_path',
    mapping_status='confirmed',
    evidence=jsonb_build_object(
      'rule','uniqlo_leaf_and_parent_exact_v1',
      'source_name',sc.name,
      'original_path',sc.original_path,
      'verified_scope','exact_leaf_and_parent_path'
    ),
    policy_version='v1_uniqlo_leaf_exact',
    updated_at=now()
from tmp_uniqlo_leaf_targets t
join public.garment_types gt on gt.code=t.garment_code
join public.source_categories sc on sc.id=t.source_category_id
where scm.source_category_id=t.source_category_id
  and scm.mapping_status='review_required';

update public.client_source_category_mappings c
set garment_type_id=scm.garment_type_id,
    default_sleeve_class_code=scm.default_sleeve_class_code,
    default_pants_length_code=scm.default_pants_length_code,
    default_body_length_code=scm.default_body_length_code,
    mapping_status=scm.mapping_status,
    policy_version=scm.policy_version,
    updated_at=now()
from public.source_category_mappings scm
join tmp_uniqlo_leaf_targets t on t.source_category_id=scm.source_category_id
where c.source_category_id=scm.source_category_id;

do $$
begin
  if (
    select count(*)
    from public.source_category_mappings scm
    join tmp_uniqlo_leaf_targets t on t.source_category_id=scm.source_category_id
    where scm.mapping_status='confirmed'
      and scm.policy_version='v1_uniqlo_leaf_exact'
  ) <> 165 then
    raise exception 'Admin Uniqlo mapping verification failed';
  end if;
  if exists (
    select 1
    from tmp_uniqlo_leaf_targets t
    join public.source_category_mappings scm on scm.source_category_id=t.source_category_id
    join public.client_source_category_mappings c on c.source_category_id=t.source_category_id
    where c.garment_type_id is distinct from scm.garment_type_id
       or c.default_sleeve_class_code is distinct from scm.default_sleeve_class_code
       or c.default_pants_length_code is distinct from scm.default_pants_length_code
       or c.default_body_length_code is distinct from scm.default_body_length_code
       or c.mapping_status is distinct from scm.mapping_status
       or c.policy_version is distinct from scm.policy_version
  ) then
    raise exception 'Client Uniqlo mapping synchronization failed';
  end if;
end $$;
;
