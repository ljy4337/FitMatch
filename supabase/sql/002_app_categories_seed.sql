begin;

-- Source: FitMatch/FitMatchTaxonomy.json
-- schemaVersion=1, taxonomyVersion=2026.07.1
-- 11 root categories, 69 detail categories.
with roots(code, display_name_ko, sort_order, is_active) as (
    values
        ('tops', '상의', 0, true),
        ('bottoms', '하의', 1, true),
        ('leggings', '레깅스', 2, true),
        ('outerwear', '아우터', 3, true),
        ('skirts', '스커트', 4, true),
        ('dresses', '원피스', 5, true),
        ('underwear', '속옷', 6, true),
        ('shoes', '신발', 7, true),
        ('accessories', '액세서리', 8, true),
        ('homewear', '홈웨어', 9, true),
        ('other', '기타', 99, true)
)
insert into public.app_categories (
    parent_id, code, display_name_ko, depth, sort_order, is_active, metadata
)
select
    null,
    code,
    display_name_ko,
    0,
    sort_order,
    is_active,
    jsonb_build_object(
        'taxonomy_schema_version', 1,
        'taxonomy_version', '2026.07.1'
    )
from roots
on conflict (code) where parent_id is null
do update set
    display_name_ko = excluded.display_name_ko,
    depth = excluded.depth,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active,
    metadata = public.app_categories.metadata || excluded.metadata;

with details(parent_code, code, display_name_ko, sort_order, is_active) as (
    values
        ('tops', 'sleeveless', '민소매', 0, true),
        ('tops', 'short_sleeve', '반팔', 1, true),
        ('tops', 'three_quarter_sleeve', '7부', 2, true),
        ('tops', 'long_sleeve', '긴팔', 3, true),
        ('tops', 'other_tops', '기타 상의', 99, true),
        ('bottoms', 'short_pants', '숏팬츠', 0, true),
        ('bottoms', 'shorts', '반바지', 1, true),
        ('bottoms', 'cropped_pants', '크롭', 2, true),
        ('bottoms', 'three_quarter_pants', '7부', 3, true),
        ('bottoms', 'nine_tenths_pants', '9부', 4, true),
        ('bottoms', 'long_pants', '긴바지', 5, true),
        ('bottoms', 'other_bottoms', '기타 하의', 99, true),
        ('leggings', 'short_leggings', '숏', 0, true),
        ('leggings', 'three_quarter_leggings', '7부', 1, true),
        ('leggings', 'nine_tenths_leggings', '9부', 2, true),
        ('leggings', 'long_leggings', '롱', 3, true),
        ('leggings', 'other_leggings', '기타 레깅스', 99, true),
        ('outerwear', 'cardigan', '가디건', 0, true),
        ('outerwear', 'windbreaker', '바람막이', 1, true),
        ('outerwear', 'anorak', '아노락', 2, true),
        ('outerwear', 'jacket', '재킷', 3, true),
        ('outerwear', 'blazer', '블레이저', 4, true),
        ('outerwear', 'jumper', '점퍼', 5, true),
        ('outerwear', 'blouson', '블루종', 6, true),
        ('outerwear', 'fleece', '플리스', 7, true),
        ('outerwear', 'light_padding', '경량패딩', 8, true),
        ('outerwear', 'short_padding', '숏패딩', 9, true),
        ('outerwear', 'padding', '패딩', 10, true),
        ('outerwear', 'long_padding', '롱패딩', 11, true),
        ('outerwear', 'coat', '코트', 12, true),
        ('outerwear', 'trench_coat', '트렌치코트', 13, true),
        ('outerwear', 'mouton', '무스탕', 14, true),
        ('outerwear', 'vest', '조끼', 15, true),
        ('outerwear', 'padded_vest', '패딩조끼', 16, true),
        ('outerwear', 'other_outerwear', '기타 아우터', 99, true),
        ('skirts', 'skirt', '스커트', 0, true),
        ('skirts', 'other_skirts', '기타 스커트', 99, true),
        ('dresses', 'one_piece', '원피스', 0, true),
        ('dresses', 'other_dresses', '기타 원피스', 99, true),
        ('underwear', 'underwear', '속옷', 0, true),
        ('underwear', 'men_briefs', '남성 브리프', 1, true),
        ('underwear', 'men_trunks', '남성 트렁크', 2, true),
        ('underwear', 'men_undershirt', '남성 런닝', 3, true),
        ('underwear', 'women_bra', '브라', 4, true),
        ('underwear', 'women_panty', '팬티', 5, true),
        ('underwear', 'women_camisole', '캐미솔', 6, true),
        ('underwear', 'women_slip', '슬립', 7, true),
        ('shoes', 'sneakers', '스니커즈', 0, true),
        ('shoes', 'running_shoes', '러닝화', 1, true),
        ('shoes', 'loafers', '로퍼', 2, true),
        ('shoes', 'boots', '부츠', 3, true),
        ('shoes', 'sandals', '샌들', 4, true),
        ('shoes', 'heels', '힐', 5, true),
        ('accessories', 'watch', '시계', 0, true),
        ('accessories', 'ring', '반지', 1, true),
        ('accessories', 'bracelet', '팔찌', 2, true),
        ('accessories', 'necklace', '목걸이', 3, true),
        ('accessories', 'bag', '가방', 4, true),
        ('accessories', 'hat', '모자', 5, true),
        ('accessories', 'belt', '벨트', 6, true),
        ('accessories', 'scarf', '스카프', 7, true),
        ('accessories', 'socks', '양말', 8, true),
        ('homewear', 'loungewear', '라운지웨어', 0, true),
        ('homewear', 'other_homewear', '기타 홈웨어', 99, true),
        ('other', 'sportswear', '스포츠웨어', 0, true),
        ('other', 'swimwear', '수영복', 1, true),
        ('other', 'uniform', '유니폼', 2, true),
        ('other', 'costume', '코스튬', 3, true),
        ('other', 'other', '기타', 99, true)
)
insert into public.app_categories (
    parent_id, code, display_name_ko, depth, sort_order, is_active, metadata
)
select
    parent.id,
    details.code,
    details.display_name_ko,
    1,
    details.sort_order,
    details.is_active,
    jsonb_build_object(
        'taxonomy_schema_version', 1,
        'taxonomy_version', '2026.07.1'
    )
from details
join public.app_categories parent
  on parent.parent_id is null
 and parent.code = details.parent_code
on conflict (parent_id, code) where parent_id is not null
do update set
    display_name_ko = excluded.display_name_ko,
    depth = excluded.depth,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active,
    metadata = public.app_categories.metadata || excluded.metadata;

-- Only category-related legacyAliases are stored here:
-- 14 category aliases + 10 detailCategory aliases = 24.
-- The 9 gender aliases in the JSON intentionally do not target app_categories.
with aliases(
    parent_code,
    target_code,
    alias,
    alias_type,
    scope
) as (
    values
        (null, 'tops', '상의', 'category', 'global'),
        (null, 'tops', '셔츠', 'category', 'global'),
        (null, 'tops', '니트', 'category', 'global'),
        (null, 'bottoms', '하의', 'category', 'global'),
        (null, 'bottoms', '팬츠', 'category', 'global'),
        (null, 'leggings', '레깅스', 'category', 'global'),
        (null, 'outerwear', '아우터', 'category', 'global'),
        (null, 'skirts', '스커트', 'category', 'global'),
        (null, 'dresses', '원피스', 'category', 'global'),
        (null, 'underwear', '속옷', 'category', 'global'),
        (null, 'shoes', '신발', 'category', 'global'),
        (null, 'accessories', '액세서리', 'category', 'global'),
        (null, 'homewear', '홈웨어', 'category', 'global'),
        (null, 'other', '기타', 'category', 'global'),
        ('tops', 'sleeveless', '나시', 'detail_category', 'tops'),
        ('tops', 'sleeveless', '민소매', 'detail_category', 'tops'),
        ('tops', 'short_sleeve', '반팔', 'detail_category', 'tops'),
        ('tops', 'short_sleeve', '반팔티', 'detail_category', 'tops'),
        ('tops', 'short_sleeve', '반팔 티셔츠', 'detail_category', 'tops'),
        ('tops', 'long_sleeve', '긴팔', 'detail_category', 'tops'),
        ('tops', 'long_sleeve', '긴팔티', 'detail_category', 'tops'),
        ('tops', 'long_sleeve', '긴팔 티셔츠', 'detail_category', 'tops'),
        ('bottoms', 'shorts', '반바지', 'detail_category', 'bottoms'),
        ('leggings', 'long_leggings', '레깅스', 'detail_category', 'leggings')
),
resolved as (
    select
        target.id as app_category_id,
        aliases.alias,
        lower(btrim(aliases.alias)) as normalized_alias,
        aliases.alias_type,
        'fitmatch_taxonomy'::text as source,
        aliases.scope,
        true as is_active,
        jsonb_build_object(
            'taxonomy_schema_version', 1,
            'taxonomy_version', '2026.07.1'
        ) as metadata
    from aliases
    join public.app_categories target
      on target.code = aliases.target_code
     and (
         (aliases.parent_code is null and target.parent_id is null)
         or
         (
             aliases.parent_code is not null
             and target.parent_id = (
                 select parent.id
                 from public.app_categories parent
                 where parent.parent_id is null
                   and parent.code = aliases.parent_code
             )
         )
     )
)
insert into public.category_aliases (
    app_category_id,
    alias,
    normalized_alias,
    alias_type,
    source,
    scope,
    is_active,
    metadata
)
select
    app_category_id,
    alias,
    normalized_alias,
    alias_type,
    source,
    scope,
    is_active,
    metadata
from resolved
on conflict (alias_type, source, scope, normalized_alias)
do update set
    app_category_id = excluded.app_category_id,
    alias = excluded.alias,
    is_active = excluded.is_active,
    metadata = public.category_aliases.metadata || excluded.metadata;

-- Do not commit a partially resolved seed. This also proves that a second run
-- converges to the same 80 categories and 24 category-related aliases.
do $$
declare
    root_count integer;
    detail_count integer;
    alias_count integer;
begin
    select
        count(*) filter (where parent_id is null and depth = 0),
        count(*) filter (where parent_id is not null and depth = 1)
      into root_count, detail_count
      from public.app_categories;

    select count(*)
      into alias_count
      from public.category_aliases
     where source = 'fitmatch_taxonomy';

    if root_count <> 11 or detail_count <> 69 or alias_count <> 24 then
        raise exception
            'FitMatch taxonomy seed verification failed: roots=%, details=%, aliases=%',
            root_count, detail_count, alias_count;
    end if;
end;
$$;

commit;
