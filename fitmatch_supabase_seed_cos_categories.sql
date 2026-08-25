begin;

-- COS KR navigation snapshot collected from the official web storefront.
-- Snapshot date: 2026-08-21. This is the semantic product taxonomy only:
-- campaign, new-arrivals and view-all landing nodes are intentionally not
-- marked as product leaves because they mix multiple garment structures.

create temporary table _fitmatch_cos_category_seed (
  audience text not null,
  external_category_id text not null,
  parent_external_category_id text,
  name text not null,
  original_path text not null,
  depth smallint not null,
  app_category text,
  app_detail_category text,
  is_leaf boolean not null,
  primary key (audience, external_category_id)
) on commit drop;

insert into _fitmatch_cos_category_seed values
  ('WOMEN','249907',null,'여성','여성',0,null,null,false),
  ('WOMEN','250252','249907','CLOTHING','여성 > CLOTHING',1,null,null,false),
  ('WOMEN','251422','250252','여성 니트웨어','여성 > CLOTHING > 여성 니트웨어',2,null,null,false),
  ('WOMEN','251425','251422','가디건','여성 > CLOTHING > 여성 니트웨어 > 가디건',3,'outerwear','cardigan',true),
  ('WOMEN','251427','251422','니트 탑','여성 > CLOTHING > 여성 니트웨어 > 니트 탑',3,'tops','knit_top',true),
  ('WOMEN','251564','250252','여성 아우터웨어','여성 > CLOTHING > 여성 아우터웨어',2,null,null,false),
  ('WOMEN','251565','251564','코트','여성 > CLOTHING > 여성 아우터웨어 > 코트',3,'outerwear','coat',true),
  ('WOMEN','251567','251564','재킷','여성 > CLOTHING > 여성 아우터웨어 > 재킷',3,'outerwear','jacket',true),
  ('WOMEN','251573','251564','블레이저','여성 > CLOTHING > 여성 아우터웨어 > 블레이저',3,'outerwear','blazer',true),
  ('WOMEN','251518','250252','여성 셔츠 & 블라우스','여성 > CLOTHING > 여성 셔츠 & 블라우스',2,'tops','other_tops',true),
  ('WOMEN','251442','250252','여성 트라우저','여성 > CLOTHING > 여성 트라우저',2,null,null,false),
  ('WOMEN','251458','251442','쇼츠','여성 > CLOTHING > 여성 트라우저 > 쇼츠',3,'bottoms','shorts',true),
  ('WOMEN','264244','251442','배럴 레그 트라우저','여성 > CLOTHING > 여성 트라우저 > 배럴 레그 트라우저',3,'bottoms','long_pants',true),
  ('WOMEN','251446','251442','와이드 레그 트라우저','여성 > CLOTHING > 여성 트라우저 > 와이드 레그 트라우저',3,'bottoms','long_pants',true),
  ('WOMEN','251456','251442','진','여성 > CLOTHING > 여성 트라우저 > 진',3,'bottoms','long_pants',true),
  ('WOMEN','251585','250252','여성 티셔츠','여성 > CLOTHING > 여성 티셔츠',2,null,null,false),
  ('WOMEN','807083','251585','슬림 핏 티셔츠','여성 > CLOTHING > 여성 티셔츠 > 슬림 핏 티셔츠',3,'tops','short_sleeve',true),
  ('WOMEN','807087','251585','레귤러 핏 티셔츠','여성 > CLOTHING > 여성 티셔츠 > 레귤러 핏 티셔츠',3,'tops','short_sleeve',true),
  ('WOMEN','815088','251585','베스트 & 슬리브리스','여성 > CLOTHING > 여성 티셔츠 > 베스트 & 슬리브리스',3,'tops','sleeveless',true),
  ('WOMEN','251545','250252','여성 탑','여성 > CLOTHING > 여성 탑',2,null,null,false),
  ('WOMEN','251560','251545','티셔츠','여성 > CLOTHING > 여성 탑 > 티셔츠',3,'tops','short_sleeve',true),
  ('WOMEN','251548','251545','셔츠 & 블라우스','여성 > CLOTHING > 여성 탑 > 셔츠 & 블라우스',3,'tops','other_tops',true),
  ('WOMEN','826114','251545','니트웨어','여성 > CLOTHING > 여성 탑 > 니트웨어',3,'tops','knit_top',true),
  ('WOMEN','251605','250252','여성 데님 & 진','여성 > CLOTHING > 여성 데님 & 진',2,null,null,false),
  ('WOMEN','251610','251605','와이드 레그 진','여성 > CLOTHING > 여성 데님 & 진 > 와이드 레그 진',3,'bottoms','long_pants',true),
  ('WOMEN','251608','251605','스트레이트 레그 진','여성 > CLOTHING > 여성 데님 & 진 > 스트레이트 레그 진',3,'bottoms','long_pants',true),
  ('WOMEN','251620','251605','테이퍼드 레그 진','여성 > CLOTHING > 여성 데님 & 진 > 테이퍼드 레그 진',3,'bottoms','long_pants',true),
  ('WOMEN','251490','250252','여성 드레스','여성 > CLOTHING > 여성 드레스',2,null,null,false),
  ('WOMEN','824608','251490','미니 드레스','여성 > CLOTHING > 여성 드레스 > 미니 드레스',3,'dresses','one_piece',true),
  ('WOMEN','251509','251490','미디 드레스','여성 > CLOTHING > 여성 드레스 > 미디 드레스',3,'dresses','one_piece',true),
  ('WOMEN','251499','251490','롱 드레스','여성 > CLOTHING > 여성 드레스 > 롱 드레스',3,'dresses','one_piece',true),
  ('WOMEN','812086','251490','리넨 드레스','여성 > CLOTHING > 여성 드레스 > 리넨 드레스',3,'dresses','one_piece',true),
  ('WOMEN','251491','251490','셔츠 드레스','여성 > CLOTHING > 여성 드레스 > 셔츠 드레스',3,'dresses','one_piece',true),
  ('WOMEN','251638','250252','여성 스커트','여성 > CLOTHING > 여성 스커트',2,'skirts','skirt',true),
  ('MEN','251646',null,'남성','남성',0,null,null,false),
  ('MEN','251647','251646','CLOTHING','남성 > CLOTHING',1,null,null,false),
  ('MEN','251711','251647','남성 니트웨어','남성 > CLOTHING > 남성 니트웨어',2,null,null,false),
  ('MEN','251728','251711','폴로 셔츠','남성 > CLOTHING > 남성 니트웨어 > 폴로 셔츠',3,'tops','polo_shirt',true),
  ('MEN','251714','251711','가디건','남성 > CLOTHING > 남성 니트웨어 > 가디건',3,'outerwear','cardigan',true),
  ('MEN','251774','251647','남성 셔츠','남성 > CLOTHING > 남성 셔츠',2,null,null,false),
  ('MEN','298371','251774','오버셔츠','남성 > CLOTHING > 남성 셔츠 > 오버셔츠',3,'tops','shirt',true),
  ('MEN','254866','251774','캐주얼 셔츠','남성 > CLOTHING > 남성 셔츠 > 캐주얼 셔츠',3,'tops','shirt',true),
  ('MEN','254864','251774','포멀 셔츠','남성 > CLOTHING > 남성 셔츠 > 포멀 셔츠',3,'tops','shirt',true),
  ('MEN','254349','251774','폴로 셔츠','남성 > CLOTHING > 남성 셔츠 > 폴로 셔츠',3,'tops','polo_shirt',true),
  ('MEN','251867','251647','남성 티셔츠','남성 > CLOTHING > 남성 티셔츠',2,null,null,false),
  ('MEN','251892','251867','슬림 핏 티셔츠','남성 > CLOTHING > 남성 티셔츠 > 슬림 핏 티셔츠',3,'tops','short_sleeve',true),
  ('MEN','251890','251867','레귤러 핏 티셔츠','남성 > CLOTHING > 남성 티셔츠 > 레귤러 핏 티셔츠',3,'tops','short_sleeve',true),
  ('MEN','251888','251867','릴랙스드 핏 티셔츠','남성 > CLOTHING > 남성 티셔츠 > 릴랙스드 핏 티셔츠',3,'tops','short_sleeve',true),
  ('MEN','251901','251867','베스트 & 슬리브리스','남성 > CLOTHING > 남성 티셔츠 > 베스트 & 슬리브리스',3,'tops','sleeveless',true),
  ('MEN','251802','251647','남성 트라우저','남성 > CLOTHING > 남성 트라우저',2,null,null,false),
  ('MEN','251826','251802','와이드 레그 트라우저','남성 > CLOTHING > 남성 트라우저 > 와이드 레그 트라우저',3,'bottoms','long_pants',true),
  ('MEN','251833','251802','스트레이트 레그 트라우저','남성 > CLOTHING > 남성 트라우저 > 스트레이트 레그 트라우저',3,'bottoms','long_pants',true),
  ('MEN','826115','251802','배럴 레그 트라우저','남성 > CLOTHING > 남성 트라우저 > 배럴 레그 트라우저',3,'bottoms','long_pants',true),
  ('MEN','251818','251802','진','남성 > CLOTHING > 남성 트라우저 > 진',3,'bottoms','long_pants',true),
  ('MEN','251814','251802','쇼츠','남성 > CLOTHING > 남성 트라우저 > 쇼츠',3,'bottoms','shorts',true),
  ('MEN','251903','251647','남성 폴로 셔츠','남성 > CLOTHING > 남성 폴로 셔츠',2,'tops','polo_shirt',true),
  ('MEN','251842','251647','남성 아우터웨어','남성 > CLOTHING > 남성 아우터웨어',2,null,null,false),
  ('MEN','251845','251842','재킷','남성 > CLOTHING > 남성 아우터웨어 > 재킷',3,'outerwear','jacket',true),
  ('MEN','251843','251842','코트','남성 > CLOTHING > 남성 아우터웨어 > 코트',3,'outerwear','coat',true),
  ('MEN','298376','251842','오버셔츠','남성 > CLOTHING > 남성 아우터웨어 > 오버셔츠',3,'outerwear','jacket',true);

do $$
declare
  source_uuid uuid;
  seed_row record;
  parent_uuid uuid;
  category_uuid uuid;
begin
  select id into source_uuid from public.sources where code = 'cos';
  if source_uuid is null then
    raise exception 'COS source is missing. Create public.sources(code=''cos'') before running this seed.';
  end if;

  for seed_row in select * from _fitmatch_cos_category_seed order by audience, depth, external_category_id loop
    parent_uuid := null;
    if seed_row.parent_external_category_id is not null then
      select id into parent_uuid from public.source_categories
      where source_id = source_uuid and brand_id is null and audience = seed_row.audience
        and external_category_id = seed_row.parent_external_category_id;
      if parent_uuid is null then
        raise exception 'Missing COS parent category: %, %', seed_row.audience, seed_row.parent_external_category_id;
      end if;
    end if;

    select id into category_uuid from public.source_categories
    where source_id = source_uuid and brand_id is null and audience = seed_row.audience
      and external_category_id = seed_row.external_category_id
    order by created_at limit 1;

    if category_uuid is null then
      insert into public.source_categories (
        source_id, brand_id, parent_id, external_category_id, name, original_path,
        audience, depth, app_category, app_detail_category, metadata, is_active
      ) values (
        source_uuid, null, parent_uuid, seed_row.external_category_id, seed_row.name, seed_row.original_path,
        seed_row.audience, seed_row.depth, seed_row.app_category, seed_row.app_detail_category,
        jsonb_build_object(
          'managed_by','fitmatch_cos_kr_product_navigation_seed',
          'catalog_snapshot_date','2026-08-21',
          'catalog_scope','cos_kr_gnb_semantic_product_categories',
          'external_category_namespace','cos_kr_gnb_sect_id',
          'is_leaf',seed_row.is_leaf,
          'mapping_basis',case when seed_row.is_leaf then 'official_gnb_semantic_path' else null end,
          'fitmatch_taxonomy_version','2026.08.2'
        ), true
      );
    else
      update public.source_categories
      set parent_id = parent_uuid, name = seed_row.name, original_path = seed_row.original_path,
          depth = seed_row.depth, app_category = seed_row.app_category,
          app_detail_category = seed_row.app_detail_category,
          metadata = public.source_categories.metadata || jsonb_build_object(
            'managed_by','fitmatch_cos_kr_product_navigation_seed',
            'catalog_snapshot_date','2026-08-21',
            'catalog_scope','cos_kr_gnb_semantic_product_categories',
            'external_category_namespace','cos_kr_gnb_sect_id',
            'is_leaf',seed_row.is_leaf,
            'mapping_basis',case when seed_row.is_leaf then 'official_gnb_semantic_path' else null end,
            'fitmatch_taxonomy_version','2026.08.2'
          ), is_active = true, updated_at = now()
      where id = category_uuid;
    end if;
  end loop;

  if exists (
    select 1 from public.source_categories c
    join _fitmatch_cos_category_seed s on s.audience = c.audience and s.external_category_id = c.external_category_id
    where c.source_id = source_uuid and c.brand_id is null and s.is_leaf
      and (c.app_category is null or c.app_detail_category is null)
  ) then
    raise exception 'COS category seed validation failed: mapped leaf is incomplete.';
  end if;
end $$;

commit;
