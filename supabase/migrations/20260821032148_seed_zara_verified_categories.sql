begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:seed-zara-verified-categories-v1'));

-- Bounded ZARA KR taxonomy observed from structured product analytics on
-- 2026-08-21. This is not a full navigation taxonomy. The source remains
-- inactive until API authorization, physical-device, and staging E2E gates pass.
insert into public.sources (code, name, base_url, is_active)
values ('zara', 'ZARA', 'https://www.zara.com/kr/ko/', false)
on conflict (code) do update set
  name = excluded.name,
  base_url = excluded.base_url,
  is_active = false,
  updated_at = now();

create temporary table _fitmatch_zara_category_seed (
  audience text not null,
  external_category_id text not null,
  parent_external_category_id text,
  name text not null,
  original_path text not null,
  depth smallint not null,
  app_category text,
  app_detail_category text,
  mapping_status text not null,
  evidence_sample_id text,
  is_leaf boolean not null,
  primary key (audience, external_category_id)
) on commit drop;

insert into _fitmatch_zara_category_seed values
  ('MEN','MAN',null,'남성','ZARA > 남성',0,null,null,'UNMAPPED',null,false),
  ('MEN','MAN:티셔츠','MAN','티셔츠','ZARA > 남성 > 티셔츠',1,'tops',null,'AMBIGUOUS','webview_tshirt_04087432',false),
  ('MEN','MAN:셔츠','MAN','셔츠','ZARA > 남성 > 셔츠',1,'tops','shirt_blouse','EXACT','men_shirt_04166166',false),
  ('MEN','MAN:브레이저','MAN','브레이저','ZARA > 남성 > 브레이저',1,'outerwear','blazer','EXACT','men_blazer_05552381',false),
  ('MEN','MAN:바지','MAN','바지','ZARA > 남성 > 바지',1,'bottoms',null,'AMBIGUOUS','men_pants_06861017|men_denim_04470350',false),
  ('MEN','MAN:스웨터','MAN','스웨터','ZARA > 남성 > 스웨터',1,'tops','knit_sweater','EXACT','men_knit_05987400',false),
  ('MEN','MAN:스포츠 재킷','MAN','스포츠 재킷','ZARA > 남성 > 스포츠 재킷',1,'outerwear','jacket','EXACT','men_outer_06987339',false),
  ('MEN','MAN:버뮤다반바지','MAN','버뮤다반바지','ZARA > 남성 > 버뮤다반바지',1,'bottoms','shorts','EXACT','men_shorts_04090032',false),
  ('MEN','MAN:스웨트 셔츠','MAN','스웨트 셔츠','ZARA > 남성 > 스웨트 셔츠',1,'tops','sweatshirt','EXACT','men_sweatshirt_04087303',false),
  ('MEN','MAN:셔츠:B. Camisería','MAN:셔츠','B. Camisería','ZARA > 남성 > 셔츠 > B. Camisería',2,'tops','shirt_blouse','EXACT','men_shirt_04166166',true),
  ('MEN','MAN:브레이저:Blasier','MAN:브레이저','Blasier','ZARA > 남성 > 브레이저 > Blasier',2,'outerwear','blazer','EXACT','men_blazer_05552381',true),
  ('MEN','MAN:바지:F. Pant Resto','MAN:바지','F. Pant Resto','ZARA > 남성 > 바지 > F. Pant Resto',2,'bottoms',null,'AMBIGUOUS','men_pants_06861017',true),
  ('MEN','MAN:바지:B. Pant Denim','MAN:바지','B. Pant Denim','ZARA > 남성 > 바지 > B. Pant Denim',2,'bottoms','jeans','RULE_BASED','men_denim_04470350',true),
  ('MEN','MAN:스웨터:B. Jersey M/C','MAN:스웨터','B. Jersey M/C','ZARA > 남성 > 스웨터 > B. Jersey M/C',2,'tops','knit_sweater','EXACT','men_knit_05987400',true),
  ('MEN','MAN:스포츠 재킷:B. Cazadora','MAN:스포츠 재킷','B. Cazadora','ZARA > 남성 > 스포츠 재킷 > B. Cazadora',2,'outerwear','jacket','EXACT','men_outer_06987339',true),
  ('MEN','MAN:버뮤다반바지:F.Bermuda Resto','MAN:버뮤다반바지','F.Bermuda Resto','ZARA > 남성 > 버뮤다반바지 > F.Bermuda Resto',2,'bottoms','shorts','EXACT','men_shorts_04090032',true),
  ('MEN','MAN:스웨트 셔츠:F. Sudadera','MAN:스웨트 셔츠','F. Sudadera','ZARA > 남성 > 스웨트 셔츠 > F. Sudadera',2,'tops','sweatshirt','EXACT','men_sweatshirt_04087303',true),
  ('WOMEN','WOMAN',null,'여성','ZARA > 여성',0,null,null,'UNMAPPED',null,false),
  ('WOMEN','WOMAN:티셔츠','WOMAN','티셔츠','ZARA > 여성 > 티셔츠',1,'tops',null,'AMBIGUOUS','women_tshirt_04174325_navy',false),
  ('WOMEN','WOMAN:드레스','WOMAN','드레스','ZARA > 여성 > 드레스',1,'dresses','one_piece','EXACT','women_dress_01058506',false),
  ('WOMEN','WOMAN:셔츠','WOMAN','셔츠','ZARA > 여성 > 셔츠',1,'tops','shirt_blouse','EXACT','women_shirt_08741239',false),
  ('WOMEN','WOMAN:가디건','WOMAN','가디건','ZARA > 여성 > 가디건',1,'outerwear','cardigan','EXACT','women_cardigan_02893103',false),
  ('WOMEN','WOMAN:스포츠 재킷','WOMAN','스포츠 재킷','ZARA > 여성 > 스포츠 재킷',1,'outerwear','jacket','EXACT','women_outer_04391892',false),
  ('WOMEN','WOMAN:바지','WOMAN','바지','ZARA > 여성 > 바지',1,'bottoms',null,'AMBIGUOUS','women_denim_01934230',false),
  ('WOMEN','WOMAN:버뮤다반바지','WOMAN','버뮤다반바지','ZARA > 여성 > 버뮤다반바지',1,'bottoms','shorts','EXACT','women_shorts_04391520',false),
  ('WOMEN','WOMAN:브레이저','WOMAN','브레이저','ZARA > 여성 > 브레이저',1,'outerwear','blazer','EXACT','women_blazer_02753522',false),
  ('WOMEN','WOMAN:치마','WOMAN','치마','ZARA > 여성 > 치마',1,'skirts','skirt','EXACT','women_skirt_08338537',false),
  ('WOMEN','WOMAN:티셔츠:C.CTAS BASICAS','WOMAN:티셔츠','C.CTAS BASICAS','ZARA > 여성 > 티셔츠 > C.CTAS BASICAS',2,'tops',null,'AMBIGUOUS','women_tshirt_04174325_navy',true),
  ('WOMEN','WOMAN:드레스:C.VESTIDO FANTA','WOMAN:드레스','C.VESTIDO FANTA','ZARA > 여성 > 드레스 > C.VESTIDO FANTA',2,'dresses','one_piece','EXACT','women_dress_01058506',true),
  ('WOMEN','WOMAN:셔츠:B.SHIRT','WOMAN:셔츠','B.SHIRT','ZARA > 여성 > 셔츠 > B.SHIRT',2,'tops','shirt_blouse','EXACT','women_shirt_08741239',true),
  ('WOMEN','WOMAN:가디건:KNIT CARDIGAN','WOMAN:가디건','KNIT CARDIGAN','ZARA > 여성 > 가디건 > KNIT CARDIGAN',2,'outerwear','cardigan','EXACT','women_cardigan_02893103',true),
  ('WOMEN','WOMAN:스포츠 재킷:T.SHORT-OUTWEAR','WOMAN:스포츠 재킷','T.SHORT-OUTWEAR','ZARA > 여성 > 스포츠 재킷 > T.SHORT-OUTWEAR',2,'outerwear','jacket','EXACT','women_outer_04391892',true),
  ('WOMEN','WOMAN:바지:B.FOLDER PANTS','WOMAN:바지','B.FOLDER PANTS','ZARA > 여성 > 바지 > B.FOLDER PANTS',2,'bottoms',null,'AMBIGUOUS','women_denim_01934230',true),
  ('WOMEN','WOMAN:버뮤다반바지:T.BERMUDAS','WOMAN:버뮤다반바지','T.BERMUDAS','ZARA > 여성 > 버뮤다반바지 > T.BERMUDAS',2,'bottoms','shorts','EXACT','women_shorts_04391520',true),
  ('WOMEN','WOMAN:브레이저:B.BLAZER','WOMAN:브레이저','B.BLAZER','ZARA > 여성 > 브레이저 > B.BLAZER',2,'outerwear','blazer','EXACT','women_blazer_02753522',true),
  ('WOMEN','WOMAN:치마:T.SKIRT','WOMAN:치마','T.SKIRT','ZARA > 여성 > 치마 > T.SKIRT',2,'skirts','skirt','EXACT','women_skirt_08338537',true);

do $$
declare
  source_uuid uuid;
  seed_row record;
  parent_uuid uuid;
  category_uuid uuid;
  canonical_uuid uuid;
begin
  select id into strict source_uuid from public.sources where code = 'zara';

  for seed_row in
    select * from _fitmatch_zara_category_seed order by audience, depth, external_category_id
  loop
    parent_uuid := null;
    if seed_row.parent_external_category_id is not null then
      select id into parent_uuid from public.source_categories
      where source_id = source_uuid and brand_id is null
        and audience = seed_row.audience
        and external_category_id = seed_row.parent_external_category_id
      order by created_at limit 1;
      if parent_uuid is null then
        raise exception 'Missing ZARA parent category: %, %', seed_row.audience, seed_row.parent_external_category_id;
      end if;
    end if;

    canonical_uuid := null;
    if seed_row.app_category is not null then
      select id into canonical_uuid from public.app_categories
      where code = coalesce(seed_row.app_detail_category, seed_row.app_category) and is_active
      order by depth desc limit 1;
      if canonical_uuid is null then
        raise exception 'Missing FitMatch category code: %/%', seed_row.app_category, seed_row.app_detail_category;
      end if;
    end if;

    select id into category_uuid from public.source_categories
    where source_id = source_uuid and brand_id is null
      and audience = seed_row.audience
      and external_category_id = seed_row.external_category_id
    order by created_at limit 1;

    if category_uuid is null then
      insert into public.source_categories (
        source_id, brand_id, parent_id, external_category_id, name, original_path,
        audience, depth, app_category, app_detail_category, app_category_id, metadata, is_active
      ) values (
        source_uuid, null, parent_uuid, seed_row.external_category_id, seed_row.name,
        seed_row.original_path, seed_row.audience, seed_row.depth,
        seed_row.app_category, seed_row.app_detail_category, canonical_uuid,
        jsonb_build_object(
          'managed_by','fitmatch_zara_kr_verified_sample_seed',
          'catalog_snapshot_date','2026-08-21',
          'catalog_scope','bounded_structured_product_samples_not_full_taxonomy',
          'external_category_namespace','zara_kr_analytics_section_family_subfamily',
          'mapping_status',seed_row.mapping_status,
          'evidence_sample_id',seed_row.evidence_sample_id,
          'is_leaf',seed_row.is_leaf,
          'measurement_mapping_status','NOT_IMPLEMENTED',
          'production_release_eligible',false,
          'fitmatch_taxonomy_version','2026.08.2'
        ), true
      );
    else
      update public.source_categories set
        parent_id = parent_uuid,
        name = seed_row.name,
        original_path = seed_row.original_path,
        depth = seed_row.depth,
        app_category = seed_row.app_category,
        app_detail_category = seed_row.app_detail_category,
        app_category_id = canonical_uuid,
        metadata = public.source_categories.metadata || jsonb_build_object(
          'managed_by','fitmatch_zara_kr_verified_sample_seed',
          'catalog_snapshot_date','2026-08-21',
          'catalog_scope','bounded_structured_product_samples_not_full_taxonomy',
          'external_category_namespace','zara_kr_analytics_section_family_subfamily',
          'mapping_status',seed_row.mapping_status,
          'evidence_sample_id',seed_row.evidence_sample_id,
          'is_leaf',seed_row.is_leaf,
          'measurement_mapping_status','NOT_IMPLEMENTED',
          'production_release_eligible',false,
          'fitmatch_taxonomy_version','2026.08.2'
        ),
        is_active = true,
        updated_at = now()
      where id = category_uuid;
    end if;
  end loop;

  if (
    select count(*) from public.source_categories c
    join _fitmatch_zara_category_seed s
      on s.audience = c.audience and s.external_category_id = c.external_category_id
    where c.source_id = source_uuid and c.brand_id is null
  ) <> 36 then
    raise exception 'ZARA category seed validation failed: expected 36 managed rows.';
  end if;

  if exists (
    select 1 from public.source_categories c
    join _fitmatch_zara_category_seed s
      on s.audience = c.audience and s.external_category_id = c.external_category_id
    where c.source_id = source_uuid and c.app_detail_category is not null
      and c.app_category_id is null
  ) then
    raise exception 'ZARA category seed validation failed: canonical FK missing.';
  end if;
end $$;

commit;
;
