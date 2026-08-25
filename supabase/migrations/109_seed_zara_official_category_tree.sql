begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:seed-zara-official-tree-2026-08-13-v1'));

-- User-provided, hash-verified research snapshot collected from ZARA KR public
-- menu/SSR hydration on 2026-08-13. It is evidence for staging/debug taxonomy,
-- not proof of API authorization or a complete production feed.
create temporary table _fitmatch_zara_official_seed (
  audience text not null,
  external_category_id text not null,
  parent_external_category_id text,
  name text,
  original_path text,
  depth smallint not null,
  tree_row_id text not null,
  tree_scope_id text not null,
  section text not null,
  layout text,
  href text,
  source_evidence text,
  path_status text,
  original_mapping_status text not null,
  fitmatch_major_candidate text,
  fitmatch_detail_candidate text,
  garment_type_code text,
  default_pants_length_code text,
  mapping_status text not null,
  resolution_mode text not null,
  app_category text,
  app_detail_category text,
  primary key (audience, external_category_id)
) on commit drop;

insert into _fitmatch_zara_official_seed values
  ('PERFUME','1881296',null,'향수','향수',0,'1881296:ROOT','1881296','PERFUME','section-root-observed',null,'official_menu_section_panel','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','1881288','1881296',null,null,1,'1881296:1881288:MENU:185','1881296','PERFUME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','194501','1881296','+안내','향수 > +안내',1,'1881296:194501:MENU:183','1881296','PERFUME','moreinfo-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2122879','1881296','채용','향수 > 채용',1,'1881296:2122879:MENU:184','1881296','PERFUME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2419523','1881296','JOIN LIFE','향수 > JOIN LIFE',1,'1881296:2419523:MENU:182','1881296','PERFUME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2421283','1881296','03아동','향수 > 아동',1,'1881296:2421283:MENU:177','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2422780','1881296','01여성','향수 > 여성',1,'1881296:2422780:MENU:173','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2422781','1881296','02남성','향수 > 남성',1,'1881296:2422781:MENU:175','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2560957','1881296','앱 다운로드','향수 > 앱 다운로드',1,'1881296:2560957:MENU:181','1881296','PERFUME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2572981','1881296','TRAVEL MODE','향수 > TRAVEL MODE',1,'1881296:2572981:MENU:180','1881296','PERFUME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2419830','2422780','향수','향수 > 여성 > 향수',2,'1881296:2419830:MENU:174','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2421285','2421283','향수','향수 > 아동 > 향수',2,'1881296:2421285:MENU:178','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2436462','2422781','향수','향수 > 남성 > 향수',2,'1881296:2436462:MENU:176','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('PERFUME','2584193','2421283','SALE','향수 > 아동 > SALE',2,'1881296:2584193:MENU:179','1881296','PERFUME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','1881757',null,'여성','여성',0,'1881757:ROOT','1881757','WOMAN','section-root-observed','https://www.zara.com/kr/ko/woman-mkt1000.html','official_menu_section_panel','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','194501','1881757','+안내','여성 > +안내',1,'1881757:194501:MENU:47','1881757','WOMAN','moreinfo-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2418844','1881757','채용','여성 > 채용',1,'1881757:2418844:MENU:46','1881757','WOMAN','marketing-content-view','https://www.zara.com/kr/ko/work-with-us-mkt8081.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2418845','1881757','매장','여성 > 매장',1,'1881757:2418845:MENU:44','1881757','WOMAN','store-locator-view','https://www.zara.com/kr/ko/z-stores-st1404.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2418848','1881757','08세일','여성 > 세일',1,'1881757:2418848:MENU:36','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2419523','1881757','JOIN LIFE','여성 > JOIN LIFE',1,'1881757:2419523:MENU:45','1881757','WOMAN','marketing-content-view','https://www.zara.com/kr/ko/z-join-life-mkt1399.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2560957','1881757','앱 다운로드','여성 > 앱 다운로드',1,'1881757:2560957:MENU:48','1881757','WOMAN','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2572981','1881757','TRAVEL MODE','여성 > TRAVEL MODE',1,'1881757:2572981:MENU:42','1881757','WOMAN','marketing-content-view','https://www.zara.com/kr/ko/zara-travel-mkt15659.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2607111','1881757','09ZARA HOME','여성 > ZARA HOME',1,'1881757:2607111:MENU:37','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2642760','1881757','04슈즈 | 액세서리','여성 > 슈즈 | 액세서리',1,'1881757:2642760:MENU:27','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2642765','1881757','01신상품','여성 > 신상품',1,'1881757:2642765:MENU:0','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2643249','1881757','03컬렉션','여성 > 컬렉션',1,'1881757:2643249:MENU:6','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-collections-l2158.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2643250','1881757','02트렌드','여성 > 트렌드',1,'1881757:2643250:MENU:4','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2643253','1881757','05향수','여성 > 향수',1,'1881757:2643253:MENU:31','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2643259','1881757','06SPECIAL EDITION','여성 > SPECIAL EDITION',1,'1881757:2643259:MENU:33','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-highlight-special-collections-l17362.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2721382','1881757',null,null,1,'1881757:2721382:MENU:49','1881757','WOMAN',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2724986','1881757','07','여성 > 07',1,'1881757:2724986:MENU:34','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/-c2724986.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','757004','1881757','기프트 카드','여성 > 기프트 카드',1,'1881757:757004:MENU:43','1881757','WOMAN','marketing-content-view','https://www.zara.com/kr/ko/man-gift-mkt4100.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2417678','2642760','백','여성 > 슈즈 | 액세서리 > 백',2,'1881757:2417678:MENU:29','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-bags-l1024.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2417770','2643249','자켓 | 점퍼','여성 > 컬렉션 > 자켓 | 점퍼',2,'1881757:2417770:HYDRATION:점퍼 | 자켓','1881757','WOMAN','products-category-view',null,'category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','아우터','점퍼 | 자켓','generic_jacket',null,'confirmed','explicit_original_path','outerwear','jacket'),
  ('WOMEN','2418953','2643249','스윔웨어','여성 > 컬렉션 > 스윔웨어',2,'1881757:2418953:MENU:25','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-beachwear-l1052.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED','스윔웨어',null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2418986','2642760','액세서리 | 주얼리','여성 > 슈즈 | 액세서리 > 액세서리 | 주얼리',2,'1881757:2418986:MENU:30','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-accessories-l1003.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2419159','2642760','슈즈','여성 > 슈즈 | 액세서리 > 슈즈',2,'1881757:2419159:MENU:28','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-shoes-l1251.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2419181','2643249','스웨트셔츠 | 조거 팬츠','여성 > 컬렉션 > 스웨트셔츠 | 조거 팬츠',2,'1881757:2419181:MENU:24','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-sweatshirts-l1320.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2419242','2643249','진 | 데님팬츠','여성 > 컬렉션 > 진 | 데님팬츠',2,'1881757:2419242:MENU:17','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-jeans-l1119.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','하의','데님 팬츠','denim_pants',null,'confirmed','explicit_original_path','bottoms','jeans'),
  ('WOMEN','2419724','2642765','특가 상품','여성 > 신상품 > 특가 상품',2,'1881757:2419724:MENU:3','1881757','WOMAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2419795','2643249','란제리','여성 > 컬렉션 > 란제리',2,'1881757:2419795:MENU:26','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-lingerie-l4021.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','언더웨어','란제리',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2419830','2643253','향수','여성 > 향수 > 향수',2,'1881757:2419830:MENU:32','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-beauty-perfumes-l1415.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2420284','2643249','토탈 룩','여성 > 컬렉션 > 토탈 룩',2,'1881757:2420284:MENU:23','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-co-ords-l1061.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2420293','2643249','니트웨어','여성 > 컬렉션 > 니트웨어',2,'1881757:2420293:MENU:20','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-knitwear-l1152.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','니트웨어','knit_sweater',null,'confirmed','explicit_original_path','tops','knit_sweater'),
  ('WOMEN','2420368','2643249','셔츠','여성 > 컬렉션 > 셔츠',2,'1881757:2420368:MENU:15','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-shirts-l1217.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','셔츠','shirt_blouse',null,'confirmed','explicit_original_path','tops','shirt_blouse'),
  ('WOMEN','2420416','2643249','티셔츠','여성 > 컬렉션 > 티셔츠',2,'1881757:2420416:MENU:14','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-tshirts-l1362.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','티셔츠','tshirt',null,'confirmed','explicit_original_path','tops','tshirt'),
  ('WOMEN','2420453','2643249','스커트','여성 > 컬렉션 > 스커트',2,'1881757:2420453:MENU:19','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-skirts-l1299.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','스커트','스커트','skirt',null,'confirmed','explicit_original_path','skirts','skirt'),
  ('WOMEN','2420482','2643249','쇼츠 | 버뮤다 팬츠','여성 > 컬렉션 > 쇼츠 | 버뮤다 팬츠',2,'1881757:2420482:MENU:18','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-trousers-shorts-l1355.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','하의','쇼츠 | 버뮤다 팬츠','other_standard_pants','short_length','confirmed','explicit_original_path','bottoms','shorts'),
  ('WOMEN','2420794','2643249','팬츠','여성 > 컬렉션 > 팬츠',2,'1881757:2420794:MENU:16','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-trousers-l1335.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','하의','팬츠','other_standard_pants',null,'confirmed','explicit_original_path','bottoms',null),
  ('WOMEN','2420895','2643249','원피스','여성 > 컬렉션 > 원피스',2,'1881757:2420895:MENU:7','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-dresses-l1066.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','원피스','원피스',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2420944','2643249','블레이저','여성 > 컬렉션 > 블레이저',2,'1881757:2420944:MENU:22','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-blazers-l1055.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','아우터','블레이저','blazer',null,'confirmed','explicit_original_path','outerwear','blazer'),
  ('WOMEN','2420954','2643250','베스트셀러','여성 > 트렌드 > 베스트셀러',2,'1881757:2420954:MENU:5','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-best-sellers-l5912.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2526499','2607111','THE NEW','여성 > ZARA HOME > THE NEW',2,'1881757:2526499:MENU:38','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/home-new-collection-l15856.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2526506','2607111','PICNIC | 아웃도어','여성 > ZARA HOME > PICNIC | 아웃도어',2,'1881757:2526506:MENU:41','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/home-outdoors-l7192.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2546081','2642765','THE NEW','여성 > 신상품 > THE NEW',2,'1881757:2546081:MENU:1','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-new-in-l1180.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('WOMEN','2619122','2642765','THE ITEM','여성 > 신상품 > THE ITEM',2,'1881757:2619122:MENU:2','1881757','WOMAN','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2637229','2643249','탑 | 바디수트','여성 > 컬렉션 > 탑 | 바디수트',2,'1881757:2637229:MENU:13','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-tops-l1322.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','탑 | 바디수트',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2664273','2643249','점퍼 | 자켓','여성 > 컬렉션 > 점퍼 | 자켓',2,'1881757:2664273:MENU:21','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-jackets-l1114.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','아우터','점퍼 | 자켓','generic_jacket',null,'confirmed','explicit_original_path','outerwear','jacket'),
  ('WOMEN','2715335','2724986',null,null,2,'1881757:2715335:MENU:35','1881757','WOMAN',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2727525','2607111','아이스크림 컬렉션','여성 > ZARA HOME > 아이스크림 컬렉션',2,'1881757:2727525:MENU:40','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/home-kitchen-ice-cream-l18532.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2732948','2607111','HOME OFFICE','여성 > ZARA HOME > HOME OFFICE',2,'1881757:2732948:MENU:39','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/home-living-room-stationery-l2619.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('WOMEN','2417772','2417770','모두 보기','여성 > 컬렉션 > 자켓 | 점퍼 > 모두 보기',3,'1881757:2417772:HYDRATION:점퍼 | 자켓','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-jackets-l1114.html','category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','아우터','점퍼 | 자켓','generic_jacket',null,'confirmed','explicit_original_path','outerwear','jacket'),
  ('WOMEN','2420417','2420416','모두 보기','여성 > 컬렉션 > 티셔츠 > 모두 보기',3,'1881757:2420417:HYDRATION:티셔츠','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-tshirts-l1362.html','category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','상의','티셔츠','tshirt',null,'confirmed','explicit_original_path','tops','tshirt'),
  ('WOMEN','2420795','2420794','모두 보기','여성 > 컬렉션 > 팬츠 > 모두 보기',3,'1881757:2420795:HYDRATION:팬츠','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-trousers-l1335.html','category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','하의','팬츠','other_standard_pants',null,'confirmed','explicit_original_path','bottoms',null),
  ('WOMEN','2420826','2420895','미니','여성 > 컬렉션 > 원피스 > 미니',3,'1881757:2420826:MENU:10','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-dresses-mini-l1083.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','원피스','미니 원피스',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2420829','2420895','새틴 마감','여성 > 컬렉션 > 원피스 > 새틴 마감',3,'1881757:2420829:MENU:12','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-dresses-camisole-l2184.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','원피스','새틴 원피스',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2420896','2420895','모두 보기','여성 > 컬렉션 > 원피스 > 모두 보기',3,'1881757:2420896:MENU:8','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-dresses-l1066.html','official_menu_dom+category_hydration','COMPLETE_OBSERVED','LOCKED','원피스','원피스',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2420900','2420895','미디 | 맥시','여성 > 컬렉션 > 원피스 > 미디 | 맥시',3,'1881757:2420900:MENU:9','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-dresses-midi-l1081.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','원피스','미디 | 맥시 원피스',null,null,'review_required','unresolved',null,null),
  ('WOMEN','2420907','2420895','점프수트','여성 > 컬렉션 > 원피스 > 점프수트',3,'1881757:2420907:MENU:11','1881757','WOMAN','products-category-view','https://www.zara.com/kr/ko/woman-jumpsuits-l1150.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','점프수트','점프수트',null,null,'review_required','unresolved',null,null),
  ('MEN','1885841',null,'남성','남성',0,'1885841:ROOT','1885841','MAN','section-root-observed','https://www.zara.com/kr/ko/man-l534.html','official_menu_section_panel','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','194501','1885841','+안내','남성 > +안내',1,'1885841:194501:MENU:100','1885841','MAN','moreinfo-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2311136','1885841','매장','남성 > 매장',1,'1885841:2311136:MENU:96','1885841','MAN','store-locator-view','https://www.zara.com/kr/ko/z-stores-st1404.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2419523','1885841','JOIN LIFE','남성 > JOIN LIFE',1,'1885841:2419523:MENU:98','1885841','MAN','marketing-content-view','https://www.zara.com/kr/ko/z-join-life-mkt1399.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2436739','1885841','채용','남성 > 채용',1,'1885841:2436739:MENU:99','1885841','MAN','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2560957','1885841','앱 다운로드','남성 > 앱 다운로드',1,'1885841:2560957:MENU:97','1885841','MAN','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2572981','1885841','TRAVEL MODE','남성 > TRAVEL MODE',1,'1885841:2572981:MENU:94','1885841','MAN','marketing-content-view','https://www.zara.com/kr/ko/zara-travel-mkt15659.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2607111','1885841','09ZARA HOME','남성 > ZARA HOME',1,'1885841:2607111:MENU:89','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2632758','1885841',null,null,1,'1885841:2632758:MENU:101','1885841','MAN',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2642246','1885841','07COLLABS','남성 > COLLABS',1,'1885841:2642246:MENU:84','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-collection-l622.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2643752','1885841','01신상품','남성 > 신상품',1,'1885841:2643752:MENU:50','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2643753','1885841','04컬렉션','남성 > 컬렉션',1,'1885841:2643753:MENU:58','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-collection-l622.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2643757','1885841','06SPECIAL EDITION','남성 > SPECIAL EDITION',1,'1885841:2643757:MENU:83','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-collection-l622.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2658254','1885841','05슈즈 | 액세서리','남성 > 슈즈 | 액세서리',1,'1885841:2658254:MENU:76','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2670294','1885841','03','남성 > 03',1,'1885841:2670294:MENU:55','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2670794','1885841','02','남성 > 02',1,'1885841:2670794:MENU:53','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-origins-l16501.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2721407','1885841','08SALE','남성 > SALE',1,'1885841:2721407:MENU:87','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','757005','1885841','기프트 카드','남성 > 기프트 카드',1,'1885841:757005:MENU:95','1885841','MAN','marketing-content-view','https://www.zara.com/kr/ko/man-gift-mkt4100.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2431932','2643753','모두 보기','남성 > 컬렉션 > 모두 보기',2,'1885841:2431932:MENU:59','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2431948','2643753','베스트셀러','남성 > 컬렉션 > 베스트셀러',2,'1885841:2431948:MENU:60','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-all-products-l7465.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2431957','2643753','린넨 | WITH 린넨','남성 > 컬렉션 > 린넨 | WITH 린넨',2,'1885841:2431957:MENU:61','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-linen-l708.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2431993','2643753','셔츠','남성 > 컬렉션 > 셔츠',2,'1885841:2431993:MENU:63','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-shirts-l737.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','셔츠','shirt_blouse',null,'confirmed','explicit_original_path','tops','shirt_blouse'),
  ('MEN','2432040','2643753','티셔츠','남성 > 컬렉션 > 티셔츠',2,'1885841:2432040:MENU:62','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-tshirts-l855.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','티셔츠','tshirt',null,'confirmed','explicit_original_path','tops','tshirt'),
  ('MEN','2432056','2643753','피케 | 카라 티셔츠','남성 > 컬렉션 > 피케 | 카라 티셔츠',2,'1885841:2432056:MENU:70','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-polos-l733.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','피케 | 카라 티셔츠','polo_shirt',null,'confirmed','explicit_original_path','tops','polo_shirt'),
  ('MEN','2432095','2643753','팬츠','남성 > 컬렉션 > 팬츠',2,'1885841:2432095:MENU:64','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-trousers-l838.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','하의','팬츠','other_standard_pants',null,'confirmed','explicit_original_path','bottoms',null),
  ('MEN','2432130','2643753','데님팬츠','남성 > 컬렉션 > 데님팬츠',2,'1885841:2432130:MENU:65','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-jeans-l659.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','하의','데님 팬츠','denim_pants',null,'confirmed','explicit_original_path','bottoms','jeans'),
  ('MEN','2432163','2643753','반바지 | 버뮤다팬츠','남성 > 컬렉션 > 반바지 | 버뮤다팬츠',2,'1885841:2432163:MENU:66','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-bermudas-l592.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','하의','쇼츠 | 버뮤다 팬츠','other_standard_pants','short_length','confirmed','explicit_original_path','bottoms','shorts'),
  ('MEN','2432191','2643753','수트','남성 > 컬렉션 > 수트',2,'1885841:2432191:MENU:67','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-suits-l808.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2432193','2658254','스윔웨어','남성 > 슈즈 | 액세서리 > 스윔웨어',2,'1885841:2432193:MENU:80','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-beachwear-l590.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2432231','2643753','맨투맨 | 후디','남성 > 컬렉션 > 맨투맨 | 후디',2,'1885841:2432231:MENU:72','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-sweatshirts-l821.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','맨투맨 | 후디',null,null,'review_required','unresolved',null,null),
  ('MEN','2432264','2643753','니트 | 여름 니트','남성 > 컬렉션 > 니트 | 여름 니트',2,'1885841:2432264:MENU:71','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-knitwear-l681.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','상의','니트 | 여름 니트','knit_sweater',null,'confirmed','explicit_original_path','tops','knit_sweater'),
  ('MEN','2432279','2643753','오버셔츠','남성 > 컬렉션 > 오버셔츠',2,'1885841:2432279:MENU:73','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-overshirts-l3174.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','아우터','오버셔츠',null,null,'review_required','unresolved',null,null),
  ('MEN','2436309','2643753','블레이저','남성 > 컬렉션 > 블레이저',2,'1885841:2436309:MENU:68','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-blazers-l608.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','아우터','블레이저','blazer',null,'confirmed','explicit_original_path','outerwear','blazer'),
  ('MEN','2436314','2643753','토탈 룩','남성 > 컬렉션 > 토탈 룩',2,'1885841:2436314:MENU:69','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-total-look-l5490.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2436318','2658254','스니커즈','남성 > 슈즈 | 액세서리 > 스니커즈',2,'1885841:2436318:MENU:78','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-sneakers-l7460.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2436372','2658254','슈즈','남성 > 슈즈 | 액세서리 > 슈즈',2,'1885841:2436372:MENU:77','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-shoes-l769.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2436397','2658254','백','남성 > 슈즈 | 액세서리 > 백',2,'1885841:2436397:MENU:79','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-bags-l563.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2436430','2658254','액세서리','남성 > 슈즈 | 액세서리 > 액세서리',2,'1885841:2436430:MENU:82','1885841','MAN','marketing-content-view','https://www.zara.com/kr/ko/man-accessories-l537.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2436462','2643753','향수','남성 > 컬렉션 > 향수',2,'1885841:2436462:MENU:75','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-accessories-perfumes-l551.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2436579','2670294','ATHLETICZ / 26 1 18 1','남성 > 03 > ATHLETICZ / 26 1 18 1',2,'1885841:2436579:MENU:56','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/zara-athleticz-l4651.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2436600','2670294','러닝','남성 > 03 > 러닝',2,'1885841:2436600:MENU:57','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/zara-athleticz-running-l5146.html','official_menu_dom','COMPLETE_OBSERVED','DATA_FAILURE',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2440816','2721407','모두 보기','남성 > SALE > 모두 보기',2,'1885841:2440816:MENU:88','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/s-man-sale-l10847.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2475845','2670794','ZARA ORIGINS NEW','남성 > 02 > ZARA ORIGINS NEW',2,'1885841:2475845:MENU:54','1885841','MAN','marketing-content-view','https://www.zara.com/kr/ko/origins-collection-l4661.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2526499','2607111','THE NEW','남성 > ZARA HOME > THE NEW',2,'1885841:2526499:MENU:90','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/home-new-collection-l15856.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2526506','2607111','PICNIC | 아웃도어','남성 > ZARA HOME > PICNIC | 아웃도어',2,'1885841:2526506:MENU:93','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/home-outdoors-l7192.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2537410','2643753','점퍼 | 자켓','남성 > 컬렉션 > 점퍼 | 자켓',2,'1885841:2537410:MENU:74','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-jackets-l640.html','official_menu_dom','COMPLETE_OBSERVED','LOCKED','아우터','점퍼 | 자켓','generic_jacket',null,'confirmed','explicit_original_path','outerwear','jacket'),
  ('MEN','2544454','2643752','THE NEW','남성 > 신상품 > THE NEW',2,'1885841:2544454:MENU:51','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-new-in-l711.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2606121','2658254','언더웨어 | 양말','남성 > 슈즈 | 액세서리 > 언더웨어 | 양말',2,'1885841:2606121:MENU:81','1885841','MAN','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','MAJOR_LOCKED_DETAIL_REVIEW','언더웨어',null,null,null,'review_required','unresolved',null,null),
  ('MEN','2632198','2643752','AARON LEVINE x ZARA','남성 > 신상품 > AARON LEVINE x ZARA',2,'1885841:2632198:MENU:52','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-aaron-levine-x-zara-editorial-l17092.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2718332','2642246',null,null,2,'1885841:2718332:MENU:85','1885841','MAN',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2720871','2642246','FIFA ® CLASSICS','남성 > COLLABS > FIFA ® CLASSICS',2,'1885841:2720871:MENU:86','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-fifatmclassics-collection-l18376.html','official_menu_dom','COMPLETE_OBSERVED','USER_CONFIRMATION_REQUIRED',null,null,null,null,'review_required','unresolved',null,null),
  ('MEN','2727525','2607111','아이스크림 컬렉션','남성 > ZARA HOME > 아이스크림 컬렉션',2,'1885841:2727525:MENU:92','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/home-kitchen-ice-cream-l18532.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2732948','2607111','HOME OFFICE','남성 > ZARA HOME > HOME OFFICE',2,'1885841:2732948:MENU:91','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/home-living-room-stationery-l2619.html','official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('MEN','2431994','2431993','모두 보기','남성 > 컬렉션 > 셔츠 > 모두 보기',3,'1885841:2431994:HYDRATION:셔츠','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-shirts-l737.html','category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','상의','셔츠','shirt_blouse',null,'confirmed','explicit_original_path','tops','shirt_blouse'),
  ('MEN','2432042','2432040','모두 보기','남성 > 컬렉션 > 티셔츠 > 모두 보기',3,'1885841:2432042:HYDRATION:티셔츠','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-tshirts-l855.html','category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','상의','티셔츠','tshirt',null,'confirmed','explicit_original_path','tops','tshirt'),
  ('MEN','2432096','2432095','모두 보기','남성 > 컬렉션 > 팬츠 > 모두 보기',3,'1885841:2432096:HYDRATION:팬츠','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-trousers-l838.html','category_hydration_breadcrumb','COMPLETE_OBSERVED','LOCKED','하의','팬츠','other_standard_pants',null,'confirmed','explicit_original_path','bottoms',null),
  ('MEN','2536906','2537410','모두 보기','남성 > 컬렉션 > 점퍼 | 자켓 > 모두 보기',3,'1885841:2536906:HYDRATION:점퍼 | 자켓','1885841','MAN','products-category-view','https://www.zara.com/kr/ko/man-jackets-l640.html','category_hydration_plus_menu_path_reconstruction','RECONSTRUCTED_MISSING_BREADCRUMBS','LOCKED','아우터','점퍼 | 자켓','generic_jacket',null,'confirmed','explicit_original_path','outerwear','jacket'),
  ('KIDS','2112261',null,'키즈','키즈',0,'2112261:ROOT','2112261','KIDS','section-root-observed',null,'official_menu_section_panel','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','194501','2112261','+안내','키즈 > +안내',1,'2112261:194501:MENU:116','2112261','KIDS','moreinfo-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2311136','2112261','매장','키즈 > 매장',1,'2112261:2311136:MENU:113','2112261','KIDS','store-locator-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2421860','2112261','여아18개월-6세','키즈 > 여아18개월-6세',1,'2112261:2421860:MENU:104','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2422499','2112261','남아18개월-6세','키즈 > 남아18개월-6세',1,'2112261:2422499:MENU:105','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2425905','2112261','여아6 - 14세','키즈 > 여아6 - 14세',1,'2112261:2425905:MENU:102','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2426469','2112261','남아6 - 14세','키즈 > 남아6 - 14세',1,'2112261:2426469:MENU:103','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2428025','2112261','베이비0 - 18개월','키즈 > 베이비0 - 18개월',1,'2112261:2428025:MENU:106','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2435024','2112261','액세서리 | 슈즈','키즈 > 액세서리 | 슈즈',1,'2112261:2435024:MENU:107','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2435943','2112261','커리어','키즈 > 커리어',1,'2112261:2435943:MENU:115','2112261','KIDS','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2435945','2112261','JOIN LIFE','키즈 > JOIN LIFE',1,'2112261:2435945:MENU:114','2112261','KIDS','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2565974','2112261','앱 다운로드','키즈 > 앱 다운로드',1,'2112261:2565974:MENU:112','2112261','KIDS','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2572981','2112261','TRAVEL MODE','키즈 > TRAVEL MODE',1,'2112261:2572981:MENU:110','2112261','KIDS','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2605625','2112261','ZARA HOME KIDS','키즈 > ZARA HOME KIDS',1,'2112261:2605625:MENU:109','2112261','KIDS','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','2645264','2112261','KDPT Goods | 베이직0 - 14 | YEARS','키즈 > KDPT Goods | 베이직0 - 14 | YEARS',1,'2112261:2645264:MENU:108','2112261','KIDS','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('KIDS','757007','2112261','기프트 카드','키즈 > 기프트 카드',1,'2112261:757007:MENU:111','2112261','KIDS','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2124389',null,'홈','홈',0,'2124389:ROOT','2124389','HOME','section-root-observed',null,'official_menu_section_panel','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','194501','2124389','+안내','홈 > +안내',1,'2124389:194501:MENU:171','2124389','HOME','moreinfo-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2418844','2124389','채용','홈 > 채용',1,'2124389:2418844:MENU:168','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2418845','2124389','매장','홈 > 매장',1,'2124389:2418845:MENU:167','2124389','HOME','store-locator-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2419523','2124389','JOIN LIFE','홈 > JOIN LIFE',1,'2124389:2419523:MENU:170','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2524961','2124389','침구류','홈 > 침구류',1,'2124389:2524961:MENU:120','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2524965','2124389','피팅룸','홈 > 피팅룸',1,'2124389:2524965:MENU:135','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2525005','2124389','세탁 | 청소','홈 > 세탁 | 청소',1,'2124389:2525005:MENU:134','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2525011','2124389','홈 프레이그런스','홈 > 홈 프레이그런스',1,'2124389:2525011:MENU:139','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2525018','2124389',null,null,1,'2124389:2525018:MENU:158','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2525092','2124389','특가 상품SUMMER','홈 > 특가 상품SUMMER',1,'2124389:2525092:MENU:141','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2525830','2124389','욕실','홈 > 욕실',1,'2124389:2525830:MENU:132','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2526465','2124389','다이닝','홈 > 다이닝',1,'2124389:2526465:MENU:130','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2526548','2124389','주방','홈 > 주방',1,'2124389:2526548:MENU:131','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2526556','2124389',null,null,1,'2124389:2526556:MENU:163','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527476','2124389','즐거운 새학기!','홈 > 즐거운 새학기!',1,'2124389:2527476:MENU:144','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527482','2124389','슈즈 | 액세서리','홈 > 슈즈 | 액세서리',1,'2124389:2527482:MENU:156','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527488','2124389','장식용품','홈 > 장식용품',1,'2124389:2527488:MENU:154','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527489','2124389','키즈 바스켓','홈 > 키즈 바스켓',1,'2124389:2527489:MENU:149','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527510','2124389','식사 시간','홈 > 식사 시간',1,'2124389:2527510:MENU:151','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527511','2124389','침구','홈 > 침구',1,'2124389:2527511:MENU:146','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527513','2124389','장난감','홈 > 장난감',1,'2124389:2527513:MENU:145','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527516','2124389','신생아 용품','홈 > 신생아 용품',1,'2124389:2527516:MENU:148','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527517','2124389','옷과 파자마','홈 > 옷과 파자마',1,'2124389:2527517:MENU:155','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527519','2124389','러그','홈 > 러그',1,'2124389:2527519:MENU:152','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527527','2124389','담요 | 쿠션','홈 > 담요 | 쿠션',1,'2124389:2527527:MENU:153','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527536','2124389','욕실','홈 > 욕실',1,'2124389:2527536:MENU:150','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527547','2124389','가구','홈 > 가구',1,'2124389:2527547:MENU:147','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527552','2124389',null,null,1,'2124389:2527552:MENU:143','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527930','2124389','가구','홈 > 가구',1,'2124389:2527930:MENU:119','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527955','2124389','바스켓','홈 > 바스켓',1,'2124389:2527955:MENU:128','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527956','2124389','쿠션 | 충전재','홈 > 쿠션 | 충전재',1,'2124389:2527956:MENU:126','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527957','2124389','커튼 | 블라인드','홈 > 커튼 | 블라인드',1,'2124389:2527957:MENU:129','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527958','2124389','거울','홈 > 거울',1,'2124389:2527958:MENU:122','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527960','2124389','조명','홈 > 조명',1,'2124389:2527960:MENU:121','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527961','2124389','담요','홈 > 담요',1,'2124389:2527961:MENU:127','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527964','2124389','데코','홈 > 데코',1,'2124389:2527964:MENU:125','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527970','2124389','러그','홈 > 러그',1,'2124389:2527970:MENU:123','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2527978','2124389','반려동물','홈 > 반려동물',1,'2124389:2527978:MENU:140','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2534397','2124389','리콜 상품','홈 > 리콜 상품',1,'2124389:2534397:MENU:172','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2553457','2124389',null,null,1,'2124389:2553457:MENU:160','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2560957','2124389','앱 다운로드','홈 > 앱 다운로드',1,'2124389:2560957:MENU:169','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2563446','2124389','GYM','홈 > GYM',1,'2124389:2563446:MENU:133','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2565975','2124389','홈웨어','홈 > 홈웨어',1,'2124389:2565975:MENU:136','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2566976','2124389','홈 슈즈','홈 > 홈 슈즈',1,'2124389:2566976:MENU:137','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2566977','2124389','백 | 액세서리','홈 > 백 | 액세서리',1,'2124389:2566977:MENU:138','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2572981','2124389','TRAVEL MODE','홈 > TRAVEL MODE',1,'2124389:2572981:MENU:165','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2601110','2124389','홈 오피스','홈 > 홈 오피스',1,'2124389:2601110:MENU:124','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2608124','2124389',null,null,1,'2124389:2608124:MENU:118','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2624639','2124389','MR PÉREZ','홈 > MR PÉREZ',1,'2124389:2624639:MENU:157','2124389','HOME','products-category-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2644753','2124389',null,null,1,'2124389:2644753:MENU:117','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2659762','2124389',null,null,1,'2124389:2659762:MENU:142','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2663269','2124389',null,null,1,'2124389:2663269:MENU:161','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2708805','2124389',null,null,1,'2124389:2708805:MENU:159','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2715384','2124389',null,null,1,'2124389:2715384:MENU:164','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','2724448','2124389',null,null,1,'2124389:2724448:MENU:162','2124389','HOME',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('HOME','757004','2124389','기프트 카드','홈 > 기프트 카드',1,'2124389:757004:MENU:166','2124389','HOME','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('TRAVEL','2572981',null,'여행','여행',0,'2572981:ROOT','2572981','TRAVEL','section-root-observed',null,'official_menu_section_panel','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('TRAVEL','2576513','2572981','ABOUT','여행 > ABOUT',1,'2572981:2576513:MENU:186','2572981','TRAVEL','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('TRAVEL','2577013','2572981','THE GUIDES','여행 > THE GUIDES',1,'2572981:2577013:MENU:187','2572981','TRAVEL','marketing-content-view',null,'official_menu_dom','COMPLETE_OBSERVED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('TRAVEL','2732917','2572981',null,null,1,'2572981:2732917:MENU:188','2572981','TRAVEL',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2719339',null,null,null,0,'2719339:ROOT','2719339','UNKNOWN','section-root-observed',null,'official_menu_section_panel','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2714854','2719339',null,null,1,'2719339:2714854:MENU:197','2719339','UNKNOWN',null,null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2715858','2719339','DISCOVER',null,1,'2719339:2715858:MENU:189','2719339','UNKNOWN','products-category-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2715838','2715858','LOOKBOOK',null,2,'2719339:2715838:MENU:192','2719339','UNKNOWN','bamo-products-category-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2715839','2715858','CAMPAIGN',null,2,'2719339:2715839:MENU:194','2719339','UNKNOWN','marketing-content-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2716341','2715858','매장',null,2,'2719339:2716341:MENU:195','2719339','UNKNOWN','marketing-content-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2716885','2715858','POP UPS',null,2,'2719339:2716885:MENU:196','2719339','UNKNOWN','marketing-content-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2718337','2715858','NEWS',null,2,'2719339:2718337:MENU:190','2719339','UNKNOWN','marketing-content-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2719340','2715858','VIDEO',null,2,'2719339:2719340:MENU:193','2719339','UNKNOWN','marketing-content-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null),
  ('UNKNOWN','2720346','2715858','컬렉션',null,2,'2719339:2720346:MENU:191','2719339','UNKNOWN','bamo-products-category-view',null,'official_menu_dom','INCOMPLETE_NAME_NOT_EXPOSED','UNSUPPORTED',null,null,null,null,'rejected','unresolved',null,null);

do $$
declare
  v_source_id uuid;
  v_row record;
  v_parent_id uuid;
  v_category_id uuid;
  v_app_category_id uuid;
begin
  select id into strict v_source_id from public.sources where code = 'zara';

  if (select count(*) from _fitmatch_zara_official_seed) <> 213 then
    raise exception 'Expected 213 official ZARA taxonomy rows';
  end if;

  for v_row in
    select * from _fitmatch_zara_official_seed
    order by audience, depth, external_category_id
  loop
    v_parent_id := null;
    if v_row.parent_external_category_id is not null then
      select id into v_parent_id
      from public.source_categories
      where source_id = v_source_id and brand_id is null
        and audience = v_row.audience
        and external_category_id = v_row.parent_external_category_id
      order by created_at limit 1;
      if v_parent_id is null then
        raise exception 'Missing official ZARA parent: %/%', v_row.audience, v_row.parent_external_category_id;
      end if;
    end if;

    v_app_category_id := null;
    if v_row.app_category is not null then
      select id into v_app_category_id
      from public.app_categories
      where code = coalesce(v_row.app_detail_category, v_row.app_category) and is_active
      order by depth desc limit 1;
      if v_app_category_id is null then
        raise exception 'Missing FitMatch app category: %/%', v_row.app_category, v_row.app_detail_category;
      end if;
    end if;

    select id into v_category_id
    from public.source_categories
    where source_id = v_source_id and brand_id is null
      and audience = v_row.audience
      and external_category_id = v_row.external_category_id
    order by created_at limit 1;

    if v_category_id is null then
      insert into public.source_categories (
        source_id, brand_id, parent_id, external_category_id, name, original_path,
        audience, depth, app_category, app_detail_category, app_category_id,
        metadata, is_active
      ) values (
        v_source_id, null, v_parent_id, v_row.external_category_id,
        coalesce(nullif(v_row.name,''), '미확인 카테고리 ' || v_row.external_category_id),
        coalesce(nullif(v_row.original_path,''), 'ZARA > ' || v_row.section || ' > ' || v_row.external_category_id),
        v_row.audience, v_row.depth, v_row.app_category, v_row.app_detail_category,
        v_app_category_id,
        jsonb_build_object(
          'managed_by','fitmatch_zara_official_tree_seed',
          'external_category_namespace','zara_kr_official_numeric_category_id',
          'tree_row_id',v_row.tree_row_id,
          'tree_scope_id',v_row.tree_scope_id,
          'section',v_row.section,
          'layout',v_row.layout,
          'href',v_row.href,
          'source_evidence',v_row.source_evidence,
          'path_status',v_row.path_status,
          'original_mapping_status',v_row.original_mapping_status,
          'fitmatch_major_candidate',v_row.fitmatch_major_candidate,
          'fitmatch_detail_candidate',v_row.fitmatch_detail_candidate,
          'collection_date','2026-08-13',
          'category_tree_sha256','aa4f9b781c0e437891df44acd66cbdefa5b06bf7a07df11c6cc3d05a338fa7c4',
          'mapping_candidates_sha256','404d009213f05b38b5e33faac7edafc6a522e6c5a961d0b5bfb164b5dec57e26',
          'production_release_eligible',false
        ), true
      ) returning id into v_category_id;
    else
      update public.source_categories set
        parent_id = v_parent_id,
        name = coalesce(nullif(v_row.name,''), public.source_categories.name),
        original_path = coalesce(nullif(v_row.original_path,''), public.source_categories.original_path),
        depth = v_row.depth,
        app_category = v_row.app_category,
        app_detail_category = v_row.app_detail_category,
        app_category_id = v_app_category_id,
        metadata = public.source_categories.metadata || jsonb_build_object(
          'managed_by','fitmatch_zara_official_tree_seed',
          'external_category_namespace','zara_kr_official_numeric_category_id',
          'tree_row_id',v_row.tree_row_id,
          'tree_scope_id',v_row.tree_scope_id,
          'section',v_row.section,
          'layout',v_row.layout,
          'href',v_row.href,
          'source_evidence',v_row.source_evidence,
          'path_status',v_row.path_status,
          'original_mapping_status',v_row.original_mapping_status,
          'fitmatch_major_candidate',v_row.fitmatch_major_candidate,
          'fitmatch_detail_candidate',v_row.fitmatch_detail_candidate,
          'collection_date','2026-08-13',
          'category_tree_sha256','aa4f9b781c0e437891df44acd66cbdefa5b06bf7a07df11c6cc3d05a338fa7c4',
          'mapping_candidates_sha256','404d009213f05b38b5e33faac7edafc6a522e6c5a961d0b5bfb164b5dec57e26',
          'production_release_eligible',false
        ),
        is_active = true,
        updated_at = now()
      where id = v_category_id;
    end if;
  end loop;

  insert into public.source_category_mappings (
    source_category_id, garment_type_id,
    default_sleeve_class_code, default_pants_length_code, default_body_length_code,
    resolution_mode, mapping_status, evidence, policy_version
  )
  select
    category.id, garment.id, null, seed.default_pants_length_code, null,
    seed.resolution_mode, seed.mapping_status,
    jsonb_build_object(
      'source','zara',
      'external_category_namespace','zara_kr_official_numeric_category_id',
      'tree_row_id',seed.tree_row_id,
      'original_mapping_status',seed.original_mapping_status,
      'fitmatch_major_candidate',seed.fitmatch_major_candidate,
      'fitmatch_detail_candidate',seed.fitmatch_detail_candidate,
      'collection_date','2026-08-13',
      'mapping_candidates_sha256','404d009213f05b38b5e33faac7edafc6a522e6c5a961d0b5bfb164b5dec57e26',
      'measurement_mapping_status','not_implemented',
      'production_release_eligible',false,
      'fail_closed',seed.mapping_status <> 'confirmed'
    ),
    'zara-official-tree-2026-08-13-v1'
  from _fitmatch_zara_official_seed seed
  join public.source_categories category
    on category.source_id = v_source_id and category.brand_id is null
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
    select count(*) from public.source_categories
    where source_id = v_source_id and brand_id is null
      and metadata->>'external_category_namespace' = 'zara_kr_official_numeric_category_id'
  ) <> 213 then
    raise exception 'Official ZARA source category count validation failed';
  end if;

  if (
    select count(*)
    from public.source_category_mappings mapping
    join public.source_categories category on category.id = mapping.source_category_id
    where category.source_id = v_source_id
      and category.metadata->>'external_category_namespace' = 'zara_kr_official_numeric_category_id'
      and mapping.mapping_status = 'confirmed'
  ) <> 26 then
    raise exception 'Expected 26 confirmed official ZARA mappings';
  end if;
end $$;

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
  where source.code = 'zara'
    and category.metadata->>'external_category_namespace' = 'zara_kr_official_numeric_category_id'
    and mapping.mapping_status = 'confirmed';

  if v_zara_count <> 26 then
    raise exception 'Expected 26 official ZARA runtime mappings, got %', v_zara_count;
  end if;

  insert into fitmatch_catalog.releases (
    id, release_key, taxonomy_version, policy_version, status,
    bundle_checksum, app_taxonomy_checksum,
    expected_mapping_count, expected_qa_count, metadata
  ) values (
    v_new_release_id,
    'fitmatch-active-with-zara-official-tree-2026-08-13-v1',
    v_old_release.taxonomy_version,
    v_old_release.policy_version || '+zara-official-tree-2026-08-13-v1',
    'loading',
    encode(extensions.digest(v_old_release.bundle_checksum || ':zara-official-tree-2026-08-13-v1', 'sha256'), 'hex'),
    v_old_release.app_taxonomy_checksum,
    v_old_count + v_zara_count,
    v_old_release.expected_qa_count,
    v_old_release.metadata || jsonb_build_object(
      'copied_from_release_id',v_old_release.id,
      'copied_from_release_key',v_old_release.release_key,
      'zara_official_tree_rows',213,
      'zara_official_confirmed_runtime_mappings',26,
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
    'zara', v_snapshot_id, category.external_category_id,
    case category.audience when 'MEN' then 'MALE' else 'FEMALE' end,
    category.original_path, 'confirmed', 'direct', true, true,
    garment.major_category_code, garment.code, garment.comparison_group_code,
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
      'resolutionMethod','verified_zara_official_numeric_category_tree',
      'policyVersion','zara-official-tree-2026-08-13-v1',
      'measurementMappingStatus','not_implemented',
      'productionReleaseEligible',false
    )
  from public.source_category_mappings mapping
  join public.source_categories category on category.id = mapping.source_category_id
  join public.sources source on source.id = category.source_id
  join public.garment_types garment on garment.id = mapping.garment_type_id
  where source.code = 'zara'
    and category.metadata->>'external_category_namespace' = 'zara_kr_official_numeric_category_id'
    and mapping.mapping_status = 'confirmed';

  select count(*) into v_new_count
  from fitmatch_catalog.source_category_mappings
  where release_id = v_new_release_id;
  if v_new_count <> v_old_count + v_zara_count then
    raise exception 'Runtime release count mismatch: expected %, got %', v_old_count + v_zara_count, v_new_count;
  end if;

  update fitmatch_catalog.releases set status = 'retired'
  where id = v_old_release.id;
  update fitmatch_catalog.releases
  set status = 'active', validated_at = now(), activated_at = now()
  where id = v_new_release_id;
end $$;

commit;
