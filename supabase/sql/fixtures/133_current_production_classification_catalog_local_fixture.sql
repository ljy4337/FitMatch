-- LOCAL TEST FIXTURE ONLY.
-- Minimal current Production classification catalog captured read-only on
-- 2026-09-10. It fixes the older synthetic fixture that only seeded a small
-- garment subset. It must never be applied as a Production migration.

begin;

insert into fitmatch_vnext.garment_types(
    garment_type_code, category_code, comparison_policy_code, display_name,
    uses_sleeve_length, uses_lower_length, uses_body_length, sort_order,
    is_active
) values
('anorak','outerwear','anorak','아노락',true,false,false,480,true),
('base_layer_top','tops','base_layer_top','언더레이어 상의',true,false,false,290,true),
('blazer','outerwear','blazer','블레이저',true,false,false,420,true),
('blouson','outerwear','blouson','블루종',true,false,false,430,true),
('bodysuit_top','tops','bodysuit_top','바디수트형 상의',true,false,false,310,true),
('cardigan','tops','cardigan','가디건',true,false,false,270,true),
('cargo_pants','bottoms','standard_pants','카고/유틸리티팬츠',false,true,false,40,true),
('casual_pants','bottoms','standard_pants','캐주얼팬츠',false,true,false,50,true),
('chino_cotton_pants','bottoms','standard_pants','치노/코튼팬츠',false,true,false,30,true),
('coat','outerwear','coat','일반 코트',true,false,true,400,true),
('denim_pants','bottoms','standard_pants','데님/청바지',false,true,false,10,true),
('dress','dresses','dress','원피스',false,false,true,52,true),
('fleece_jacket','outerwear','fleece_jacket','플리스 재킷',true,false,false,490,true),
('homewear_bottom','homewear','homewear_bottom','홈웨어 하의',false,true,false,55,true),
('homewear_top','homewear','homewear_top','홈웨어 상의',true,false,false,54,true),
('hoodie','tops','hoodie','후드 티셔츠',true,false,false,260,true),
('jacket','outerwear','jacket','재킷',true,false,false,51,true),
('knit_sweater','tops','knit_sweater','니트/스웨터',true,false,false,230,true),
('knit_vest','tops','knit_vest','니트 베스트',true,false,false,280,true),
('leggings','leggings','leggings','레깅스',false,true,false,90,true),
('ma1','outerwear','ma1','MA-1/항공점퍼',true,false,false,440,true),
('men_briefs','underwear','men_briefs','남성 브리프',false,false,false,57,true),
('men_trunks','underwear','men_trunks','남성 트렁크',false,false,false,58,true),
('men_undershirt','underwear','men_undershirt','남성 런닝',true,false,false,59,true),
('mouton','outerwear','mouton','무스탕',true,false,false,540,true),
('other_standard_pants','bottoms','standard_pants','기타 일반 바지',false,true,false,70,true),
('outer_vest','outerwear','outer_vest','일반 조끼',false,false,true,520,true),
('polo_shirt','tops','polo_shirt','폴로/카라 티셔츠',true,false,false,250,true),
('puffer_jacket','outerwear','puffer_jacket','패딩 재킷',true,false,true,500,true),
('puffer_vest','outerwear','puffer_vest','패딩 조끼',false,false,true,510,true),
('shirt_blouse','tops','shirt_blouse','셔츠/블라우스',true,false,false,240,true),
('shorts','bottoms','standard_pants','반바지',false,true,false,53,true),
('skirt','skirts','skirt','스커트',false,false,true,100,true),
('slacks_trousers','bottoms','standard_pants','슬랙스/트라우저',false,true,false,20,true),
('sleeveless_tshirt','tops','sleeveless_tshirt','민소매 티셔츠',true,false,false,50,true),
('sports_top','tops','sports_top','스포츠 상의/유니폼',true,false,false,300,true),
('sweat_jogger_pants','bottoms','standard_pants','스웨트/조거팬츠',false,true,false,60,true),
('sweatshirt','tops','sweatshirt','맨투맨/스웨트',true,false,false,220,true),
('tank_top','tops','tank_top','나시/탱크톱',true,false,false,210,true),
('trench_coat','outerwear','coat','트렌치코트',true,false,true,410,true),
('tshirt','tops','tshirt','티셔츠',true,false,false,200,true),
('windbreaker','outerwear','windbreaker','바람막이',true,false,false,470,true),
('women_bra','underwear','women_bra','브라',false,false,false,60,true),
('women_camisole','underwear','women_camisole','캐미솔',true,false,false,61,true),
('women_panty','underwear','women_panty','여성 팬티',false,false,false,62,true),
('women_slip','underwear','women_slip','슬립',false,false,true,63,true),
('zip_hoodie','tops','zip_hoodie','후드집업',true,false,false,530,true)
on conflict (garment_type_code) do update set
    category_code = excluded.category_code,
    comparison_policy_code = excluded.comparison_policy_code,
    display_name = excluded.display_name,
    uses_sleeve_length = excluded.uses_sleeve_length,
    uses_lower_length = excluded.uses_lower_length,
    uses_body_length = excluded.uses_body_length,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active;

insert into fitmatch_vnext.classification_axis_value_authority(
    axis_code, value_code, is_active, is_verified
) values
('body_length','short_body',true,true),
('body_length','medium_body',true,true),
('body_length','long_body',true,true),
('lower_length','short_length',true,true),
('lower_length','three_quarter_length',true,true),
('lower_length','cropped_length',true,true),
('lower_length','ankle_length',true,true),
('lower_length','long_length',true,true),
('sleeve_length','sleeveless',true,true),
('sleeve_length','short_sleeve',true,true),
('sleeve_length','three_quarter_sleeve',true,true),
('sleeve_length','long_sleeve',true,true)
on conflict (axis_code, value_code) do update set
    is_active = excluded.is_active,
    is_verified = excluded.is_verified;

commit;
