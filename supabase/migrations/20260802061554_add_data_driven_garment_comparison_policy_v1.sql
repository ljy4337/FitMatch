
create table public.comparison_groups(
 code text primary key,display_name_ko text not null,major_category_code text not null,
 allows_cross_type boolean not null default false,is_auto_comparable boolean not null default true,
 sort_order int not null default 0,is_active boolean not null default true,metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(major_category_code in('tops','bottoms','outerwear','skirts','leggings','other')),
 check(btrim(display_name_ko)<>''),check(jsonb_typeof(metadata)='object')
);
create table public.comparison_length_classes(
 code text primary key,axis_code text not null,display_name_ko text not null,comparison_bucket_code text not null,
 sort_order int not null default 0,is_active boolean not null default true,metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(axis_code in('sleeve','leg','body')),check(btrim(display_name_ko)<>''),check(btrim(comparison_bucket_code)<>''),
 check(jsonb_typeof(metadata)='object')
);
create table public.garment_types(
 id uuid primary key default gen_random_uuid(),code text not null unique,major_category_code text not null,
 display_name_ko text not null,comparison_group_code text not null references public.comparison_groups(code),
 requires_sleeve_class boolean not null default false,requires_pants_length boolean not null default false,
 requires_body_length boolean not null default false,is_active boolean not null default true,sort_order int not null default 0,
 metadata jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(major_category_code in('tops','bottoms','outerwear','skirts','leggings','other')),
 check(btrim(code)<>''),check(btrim(display_name_ko)<>''),check(jsonb_typeof(metadata)='object')
);
create table public.comparison_policies(
 code text primary key,comparison_group_code text not null unique references public.comparison_groups(code) on delete cascade,
 cross_type_mode text not null,reference_priority_mode text not null,min_comparable_dimensions smallint not null,
 required_measurement_group_code text,policy_version text not null,is_active boolean not null default true,evidence_note text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(cross_type_mode in('same_type_only','within_group')),
 check(reference_priority_mode in('same_type_only','same_type_then_group')),check(min_comparable_dimensions>=1)
);
create table public.comparison_policy_length_axes(
 policy_code text not null references public.comparison_policies(code) on delete cascade,
 axis_code text not null,match_mode text not null,primary key(policy_code,axis_code),
 check(axis_code in('sleeve','leg','body')),check(match_mode in('exact_class','comparison_bucket'))
);
create table public.source_category_mappings(
 source_category_id uuid primary key references public.source_categories(id) on delete cascade,
 garment_type_id uuid references public.garment_types(id),
 default_sleeve_class_code text references public.comparison_length_classes(code),
 default_pants_length_code text references public.comparison_length_classes(code),
 default_body_length_code text references public.comparison_length_classes(code),
 resolution_mode text not null,mapping_status text not null,evidence jsonb not null default '{}'::jsonb,policy_version text not null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(resolution_mode in('legacy_app_category','explicit_original_path','manual_override','unresolved')),
 check(mapping_status in('confirmed','review_required','rejected')),check(jsonb_typeof(evidence)='object')
);
create index garment_types_group_idx on public.garment_types(comparison_group_code);
create index source_category_mappings_garment_type_idx on public.source_category_mappings(garment_type_id);
create index source_category_mappings_review_idx on public.source_category_mappings(mapping_status) where mapping_status='review_required';

insert into public.comparison_length_classes(code,axis_code,display_name_ko,comparison_bucket_code,sort_order,metadata) values
('sleeveless','sleeve','민소매','sleeveless',10,'{"policy_version":"v1"}'),
('short_sleeve','sleeve','반팔','short_sleeve',20,'{"policy_version":"v1"}'),
('three_quarter_sleeve','sleeve','7부소매','three_quarter_sleeve',30,'{"policy_version":"v1"}'),
('long_sleeve','sleeve','긴팔','long_sleeve',40,'{"policy_version":"v1"}'),
('unknown_sleeve','sleeve','판정불가','unknown_sleeve',90,'{"policy_version":"v1"}'),
('short_length','leg','반바지','short_pants',10,'{"policy_version":"v1"}'),
('three_quarter_length','leg','7부바지','long_pants',20,'{"policy_version":"v1"}'),
('cropped_length','leg','크롭','long_pants',25,'{"policy_version":"v1"}'),
('ankle_length','leg','9부/앵클','long_pants',30,'{"policy_version":"v1"}'),
('long_length','leg','긴바지','long_pants',40,'{"policy_version":"v1"}'),
('unknown_leg_length','leg','판정불가','unknown_leg_length',90,'{"policy_version":"v1"}'),
('short_body','body','숏','short_body',10,'{"policy_version":"v1"}'),
('medium_body','body','미디엄','medium_body',20,'{"policy_version":"v1"}'),
('long_body','body','롱','long_body',30,'{"policy_version":"v1"}'),
('unknown_body','body','판정불가','unknown_body',90,'{"policy_version":"v1"}');

insert into public.comparison_groups(code,display_name_ko,major_category_code,allows_cross_type,is_auto_comparable,sort_order,metadata)
select code,name,major,cross_type,auto_ok,ord,'{"policy_version":"v1"}'::jsonb from(values
 ('standard_pants','일반 바지','bottoms',true,true,10),('leggings','레깅스','leggings',false,true,20),
 ('skirt','스커트','skirts',false,true,30),('tshirt','티셔츠','tops',false,true,100),
 ('tank_top','나시/탱크톱','tops',false,true,110),('sweatshirt','맨투맨/스웨트','tops',false,true,120),
 ('knit_sweater','니트/스웨터','tops',false,true,130),('shirt_blouse','셔츠/블라우스','tops',false,true,140),
 ('polo_shirt','폴로/카라 티셔츠','tops',false,true,150),('hoodie','후드 티셔츠','tops',false,true,160),
 ('cardigan','가디건','tops',false,true,170),('knit_vest','니트 베스트','tops',false,true,180),
 ('base_layer_top','언더레이어 상의','tops',false,true,190),('sports_top','스포츠 상의','tops',false,true,200),
 ('bodysuit_top','바디수트형 상의','tops',false,true,210),('coat','코트','outerwear',true,true,300),
 ('blazer','블레이저','outerwear',false,true,310),('blouson','블루종','outerwear',false,true,320),
 ('ma1','MA-1/항공점퍼','outerwear',false,true,330),('windbreaker','바람막이','outerwear',false,true,340),
 ('anorak','아노락','outerwear',false,true,350),('fleece_jacket','플리스 재킷','outerwear',false,true,360),
 ('puffer_jacket','패딩 재킷','outerwear',false,true,370),('puffer_vest','패딩 조끼','outerwear',false,true,380),
 ('outer_vest','일반 조끼','outerwear',false,true,390),('zip_hoodie','후드집업','outerwear',false,true,400),
 ('mouton','무스탕','outerwear',false,true,410),('unclassified_outerwear','분류 미확정 아우터','outerwear',false,false,490),
 ('sports_bottom','스포츠 하의/유니폼','bottoms',false,false,500),('other_noncomparable','기타 비교 제외','other',false,false,900)
)v(code,name,major,cross_type,auto_ok,ord);

insert into public.garment_types
(code,major_category_code,display_name_ko,comparison_group_code,requires_sleeve_class,requires_pants_length,requires_body_length,sort_order,metadata)
select code,major,name,grp,sleeve,leg,body,ord,'{"policy_version":"v1"}'::jsonb from(values
 ('denim_pants','bottoms','데님/청바지','standard_pants',false,true,false,10),
 ('slacks_trousers','bottoms','슬랙스/트라우저','standard_pants',false,true,false,20),
 ('chino_cotton_pants','bottoms','치노/코튼팬츠','standard_pants',false,true,false,30),
 ('cargo_pants','bottoms','카고/유틸리티팬츠','standard_pants',false,true,false,40),
 ('casual_pants','bottoms','캐주얼팬츠','standard_pants',false,true,false,50),
 ('sweat_jogger_pants','bottoms','스웨트/조거팬츠','standard_pants',false,true,false,60),
 ('other_standard_pants','bottoms','기타 일반 바지','standard_pants',false,true,false,70),
 ('sports_bottom','bottoms','스포츠 하의/유니폼','sports_bottom',false,true,false,80),
 ('leggings','leggings','레깅스','leggings',false,true,false,90),('skirt','skirts','스커트','skirt',false,false,true,100),
 ('tshirt','tops','티셔츠','tshirt',true,false,false,200),('tank_top','tops','나시/탱크톱','tank_top',true,false,false,210),
 ('sweatshirt','tops','맨투맨/스웨트','sweatshirt',true,false,false,220),('knit_sweater','tops','니트/스웨터','knit_sweater',true,false,false,230),
 ('shirt_blouse','tops','셔츠/블라우스','shirt_blouse',true,false,false,240),('polo_shirt','tops','폴로/카라 티셔츠','polo_shirt',true,false,false,250),
 ('hoodie','tops','후드 티셔츠','hoodie',true,false,false,260),('cardigan','tops','가디건','cardigan',true,false,false,270),
 ('knit_vest','tops','니트 베스트','knit_vest',true,false,false,280),('base_layer_top','tops','언더레이어 상의','base_layer_top',true,false,false,290),
 ('sports_top','tops','스포츠 상의/유니폼','sports_top',true,false,false,300),('bodysuit_top','tops','바디수트형 상의','bodysuit_top',true,false,false,310),
 ('coat','outerwear','일반 코트','coat',true,false,true,400),('trench_coat','outerwear','트렌치코트','coat',true,false,true,410),
 ('blazer','outerwear','블레이저','blazer',true,false,false,420),('blouson','outerwear','블루종','blouson',true,false,false,430),
 ('ma1','outerwear','MA-1/항공점퍼','ma1',true,false,false,440),('generic_jacket','outerwear','종류 미확정 재킷','unclassified_outerwear',true,false,false,450),
 ('generic_jumper','outerwear','종류 미확정 점퍼','unclassified_outerwear',true,false,false,460),
 ('windbreaker','outerwear','바람막이','windbreaker',true,false,false,470),('anorak','outerwear','아노락','anorak',true,false,false,480),
 ('fleece_jacket','outerwear','플리스 재킷','fleece_jacket',true,false,false,490),('puffer_jacket','outerwear','패딩 재킷','puffer_jacket',true,false,true,500),
 ('puffer_vest','outerwear','패딩 조끼','puffer_vest',false,false,true,510),('outer_vest','outerwear','일반 조끼','outer_vest',false,false,true,520),
 ('zip_hoodie','outerwear','후드집업','zip_hoodie',true,false,false,530),('mouton','outerwear','무스탕','mouton',true,false,false,540),
 ('other_outerwear','outerwear','기타 아우터','unclassified_outerwear',false,false,false,590)
)v(code,major,name,grp,sleeve,leg,body,ord);

insert into public.comparison_policies
(code,comparison_group_code,cross_type_mode,reference_priority_mode,min_comparable_dimensions,required_measurement_group_code,policy_version,evidence_note)
select g.code||'_v1',g.code,case when allows_cross_type then 'within_group' else 'same_type_only' end,
 case when allows_cross_type then 'same_type_then_group' else 'same_type_only' end,2,
 case when major_category_code='tops' then 'upper_core' when major_category_code in('bottoms','leggings') then 'bottom_core'
 when major_category_code='outerwear' then 'outerwear_chest' end,'v1',
 case when g.code='standard_pants' then '일반 바지는 종류가 달라도 바지 길이 비교 버킷이 같을 때 대체 자동 비교'
 when g.code='coat' then '코트는 종류가 달라도 소매와 몸판 길이가 모두 같을 때 대체 자동 비교'
 when not is_auto_comparable then '세부 종류 확정 전 자동 비교 금지'
 else '같은 의류 종류에서 필수 길이 축이 일치할 때만 자동 비교' end
from public.comparison_groups g;
insert into public.comparison_policy_length_axes
select code,'leg','comparison_bucket' from public.comparison_policies where comparison_group_code in('standard_pants','leggings','sports_bottom');
insert into public.comparison_policy_length_axes
select code,'sleeve','exact_class' from public.comparison_policies where comparison_group_code in
('tshirt','tank_top','sweatshirt','knit_sweater','shirt_blouse','polo_shirt','hoodie','cardigan','knit_vest',
'base_layer_top','sports_top','bodysuit_top','coat','blazer','blouson','ma1','windbreaker','anorak','fleece_jacket','puffer_jacket','zip_hoodie','mouton');
insert into public.comparison_policy_length_axes
select code,'body','exact_class' from public.comparison_policies where comparison_group_code in('coat','puffer_jacket','puffer_vest','outer_vest','skirt');

insert into public.source_category_mappings(source_category_id,resolution_mode,mapping_status,evidence,policy_version)
select id,case when app_category_id is null then 'unresolved' else 'legacy_app_category' end,'review_required',
 jsonb_build_object('legacy_app_category',app_category,'legacy_app_detail_category',app_detail_category,'original_path',original_path),'v1'
from public.source_categories;

with cm(parent_code,app_code,type_code,status) as(values
 ('bottoms','jeans','denim_pants','confirmed'),('bottoms','slacks_trousers','slacks_trousers','confirmed'),
 ('bottoms','chino_cotton','chino_cotton_pants','confirmed'),('bottoms','cargo_utility','cargo_pants','confirmed'),
 ('bottoms','casual_pants','casual_pants','confirmed'),('bottoms','sweat_jogger','sweat_jogger_pants','confirmed'),
 ('bottoms','sports_bottom','sports_bottom','review_required'),('leggings','leggings','leggings','confirmed'),('skirts','skirt','skirt','confirmed'),
 ('tops','tshirt','tshirt','confirmed'),('tops','shirt_blouse','shirt_blouse','confirmed'),('tops','polo_shirt','polo_shirt','confirmed'),
 ('tops','knit_sweater','knit_sweater','confirmed'),('tops','sweatshirt','sweatshirt','confirmed'),('tops','hoodie','hoodie','confirmed'),
 ('tops','base_layer_top','base_layer_top','confirmed'),('tops','sports_top','sports_top','review_required'),('tops','bodysuit_top','bodysuit_top','confirmed'),
 ('outerwear','cardigan','cardigan','confirmed'),('outerwear','coat','coat','confirmed'),('outerwear','trench_coat','trench_coat','confirmed'),
 ('outerwear','blazer','blazer','confirmed'),('outerwear','blouson','blouson','confirmed'),('outerwear','jacket','generic_jacket','review_required'),
 ('outerwear','jumper','generic_jumper','review_required'),('outerwear','windbreaker','windbreaker','confirmed'),
 ('outerwear','anorak','anorak','confirmed'),('outerwear','fleece','fleece_jacket','confirmed'),
 ('outerwear','light_padding','puffer_jacket','review_required'),('outerwear','short_padding','puffer_jacket','confirmed'),
 ('outerwear','padding','puffer_jacket','confirmed'),('outerwear','long_padding','puffer_jacket','confirmed'),
 ('outerwear','padded_vest','puffer_vest','confirmed'),('outerwear','vest','outer_vest','confirmed'),
 ('outerwear','zip_hoodie','zip_hoodie','confirmed'),('outerwear','mouton','mouton','confirmed'),('outerwear','other_outerwear','other_outerwear','review_required')
)
update public.source_category_mappings m set garment_type_id=gt.id,mapping_status=cm.status,
 evidence=m.evidence||jsonb_build_object('mapping_basis','legacy_app_category','legacy_app_category_code',cm.app_code),updated_at=now()
from public.source_categories sc join public.app_categories a on a.id=sc.app_category_id join public.app_categories p on p.id=a.parent_id
join cm on cm.parent_code=p.code and cm.app_code=a.code join public.garment_types gt on gt.code=cm.type_code where m.source_category_id=sc.id;

update public.source_category_mappings m set
 default_sleeve_class_code=case when coalesce(a.code,sc.app_detail_category)='sleeveless' then 'sleeveless'
 when coalesce(a.code,sc.app_detail_category)='short_sleeve' then 'short_sleeve'
 when coalesce(a.code,sc.app_detail_category)='three_quarter_sleeve' then 'three_quarter_sleeve'
 when coalesce(a.code,sc.app_detail_category)='long_sleeve' then 'long_sleeve'
 when gl.axis_code='sleeve' then sc.length_class_code end,
 default_pants_length_code=case when coalesce(a.code,sc.app_detail_category) in('short_pants','shorts') then 'short_length'
 when coalesce(a.code,sc.app_detail_category)='cropped_pants' then 'cropped_length'
 when coalesce(a.code,sc.app_detail_category)='three_quarter_pants' then 'three_quarter_length'
 when coalesce(a.code,sc.app_detail_category)='nine_tenths_pants' then 'ankle_length'
 when coalesce(a.code,sc.app_detail_category)='long_pants' then 'long_length' when gl.axis_code='leg' then sc.length_class_code end,
 default_body_length_code=case when coalesce(a.code,sc.app_detail_category)='short_padding' then 'short_body'
 when coalesce(a.code,sc.app_detail_category)='long_padding' then 'long_body' end,updated_at=now()
from public.source_categories sc left join public.app_categories a on a.id=sc.app_category_id
left join public.garment_length_classes gl on gl.code=sc.length_class_code where m.source_category_id=sc.id;

create view public.v_category_mapping_review with(security_invoker=true) as
select sc.id source_category_id,s.code source_code,sc.audience,sc.original_path,sc.app_category legacy_app_category,
 sc.app_detail_category legacy_app_detail_category,gt.code garment_type_code,gt.display_name_ko garment_type_name_ko,
 cg.code comparison_group_code,cg.display_name_ko comparison_group_name_ko,m.default_sleeve_class_code,
 m.default_pants_length_code,m.default_body_length_code,m.mapping_status,m.resolution_mode,
 case when gt.id is null then 'unresolved_garment_type' when not cg.is_auto_comparable then 'specific_type_required'
 when gt.requires_sleeve_class and m.default_sleeve_class_code is null then 'product_sleeve_class_required'
 when gt.requires_pants_length and m.default_pants_length_code is null then 'product_pants_length_required'
 when gt.requires_body_length and m.default_body_length_code is null then 'product_body_length_required'
 else 'auto_comparison_ready' end readiness_status,m.evidence,m.policy_version,m.updated_at
from public.source_category_mappings m join public.source_categories sc on sc.id=m.source_category_id join public.sources s on s.id=sc.source_id
left join public.garment_types gt on gt.id=m.garment_type_id left join public.comparison_groups cg on cg.code=gt.comparison_group_code;

alter table public.comparison_groups enable row level security;
alter table public.comparison_length_classes enable row level security;
alter table public.garment_types enable row level security;
alter table public.comparison_policies enable row level security;
alter table public.comparison_policy_length_axes enable row level security;
alter table public.source_category_mappings enable row level security;
create policy comparison_groups_public_read on public.comparison_groups for select to anon,authenticated using(is_active);
create policy comparison_length_classes_public_read on public.comparison_length_classes for select to anon,authenticated using(is_active);
create policy garment_types_public_read on public.garment_types for select to anon,authenticated using(is_active);
create policy comparison_policies_public_read on public.comparison_policies for select to anon,authenticated using(is_active);
create policy comparison_policy_length_axes_public_read on public.comparison_policy_length_axes for select to anon,authenticated using(true);
grant select on public.comparison_groups,public.comparison_length_classes,public.garment_types,public.comparison_policies,public.comparison_policy_length_axes to anon,authenticated;
revoke all on public.source_category_mappings from anon,authenticated;
revoke all on public.v_category_mapping_review from anon,authenticated;
revoke insert,update,delete,truncate,references,trigger on public.comparison_groups,public.comparison_length_classes,public.garment_types,public.comparison_policies,public.comparison_policy_length_axes from anon,authenticated;
;
