
create table if not exists public.garment_length_classes (
  code text primary key,
  app_category_id uuid not null references public.app_categories(id),
  axis_code text not null check (axis_code in ('sleeve','leg')),
  display_name_ko text not null check (btrim(display_name_ko) <> ''),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.garment_length_classes enable row level security;

drop policy if exists garment_length_classes_public_read on public.garment_length_classes;
create policy garment_length_classes_public_read
on public.garment_length_classes for select
to anon, authenticated
using (true);

grant select on public.garment_length_classes to anon, authenticated;

alter table public.source_categories
  add column if not exists length_class_code text null
    references public.garment_length_classes(code),
  add column if not exists length_class_source text null
    check (length_class_source is null or length_class_source in ('original_path_explicit','measurement_inferred','manual_override')),
  add column if not exists length_class_evidence text null;

create index if not exists source_categories_length_class_idx
on public.source_categories(length_class_code)
where length_class_code is not null;

with roots as (
  select code,id from public.app_categories where parent_id is null
), new_categories(parent_code,code,display_name_ko,sort_order) as (
  values
    ('tops','tshirt','티셔츠',10),
    ('tops','shirt_blouse','셔츠/블라우스',20),
    ('tops','polo_shirt','폴로/카라 티셔츠',30),
    ('tops','knit_sweater','니트/스웨터',40),
    ('tops','sweatshirt','맨투맨/스웨트',50),
    ('tops','hoodie','후드 티셔츠',60),
    ('tops','base_layer_top','언더레이어 상의',70),
    ('tops','sports_top','스포츠 상의/유니폼',80),
    ('tops','bodysuit_top','바디수트형 상의',90),
    ('bottoms','jeans','데님/청바지',10),
    ('bottoms','slacks_trousers','슬랙스/트라우저',20),
    ('bottoms','chino_cotton','치노/코튼 팬츠',30),
    ('bottoms','sweat_jogger','스웨트/조거 팬츠',40),
    ('bottoms','cargo_utility','카고/유틸리티 팬츠',50),
    ('bottoms','casual_pants','캐주얼 팬츠',60),
    ('bottoms','sports_bottom','스포츠 하의/유니폼',70),
    ('leggings','leggings','레깅스',10),
    ('outerwear','zip_hoodie','후드집업',25),
    ('other','overalls_jumpsuit','오버올/점프슈트',20)
)
insert into public.app_categories(parent_id,code,display_name_ko,depth,sort_order,is_active,metadata)
select r.id,n.code,n.display_name_ko,1,n.sort_order,true,
       jsonb_build_object('taxonomy_version','v2','kind','garment_type')
from new_categories n join roots r on r.code=n.parent_code
on conflict (parent_id,code) where parent_id is not null
do update set display_name_ko=excluded.display_name_ko,
              sort_order=excluded.sort_order,
              is_active=true,
              metadata=public.app_categories.metadata || excluded.metadata,
              updated_at=now();

insert into public.garment_length_classes
(code,app_category_id,axis_code,display_name_ko,sort_order,is_active,metadata)
select v.code,r.id,v.axis_code,v.display_name_ko,v.sort_order,true,
       jsonb_build_object('taxonomy_version','v2')
from (values
 ('sleeveless','tops','sleeve','민소매',10),
 ('short_sleeve','tops','sleeve','반팔',20),
 ('three_quarter_sleeve','tops','sleeve','7부소매',30),
 ('long_sleeve','tops','sleeve','긴팔',40),
 ('unknown_sleeve','tops','sleeve','판정불가',90),
 ('short_length','bottoms','leg','반바지',10),
 ('three_quarter_length','bottoms','leg','7부바지',20),
 ('ankle_length','bottoms','leg','9부/앵클',30),
 ('long_length','bottoms','leg','긴바지',40),
 ('unknown_leg_length','bottoms','leg','판정불가',90)
) v(code,parent_code,axis_code,display_name_ko,sort_order)
join public.app_categories r on r.parent_id is null and r.code=v.parent_code
on conflict (code) do update
set app_category_id=excluded.app_category_id,
    axis_code=excluded.axis_code,
    display_name_ko=excluded.display_name_ko,
    sort_order=excluded.sort_order,
    is_active=true,
    metadata=public.garment_length_classes.metadata || excluded.metadata,
    updated_at=now();

with target as (
 select sc.id, sc.app_category, sc.app_detail_category, sc.app_category_id,
        lower(sc.original_path) p, sc.original_path
 from public.source_categories sc
 where sc.app_detail_category in ('other_tops','other_bottoms')
), classified as (
 select t.*,
 case
  when app_detail_category='other_tops' and (p like '%후드집업%' or p like '%후드 집업%' or p like '%zip hoodie%' or p like '%zip-up hoodie%') then 'zip_hoodie'
  when app_detail_category='other_tops' and (p like '%파카%' or p like '%parka%') then 'jumper'
  when app_detail_category='other_tops' and (p like '%가디건%' or p like '%cardigan%') then 'cardigan'
  when app_detail_category='other_tops' and (p like '%브라탑%' or p like '%bra top%') then 'women_bra'
  when app_detail_category='other_tops' and (p like '%래시가드%' or p like '%rash guard%') then 'swimwear'
  when app_detail_category='other_tops' and (p like '%폴로%' or p like '%카라 티%' or p like '%피케%' or p like '%polo%') then 'polo_shirt'
  when app_detail_category='other_tops' and (p like '%후드 티%' or p like '%후드티%' or p like '%후디%' or p like '%hoodie%' or p like '%hooded sweatshirt%') then 'hoodie'
  when app_detail_category='other_tops' and (p like '%맨투맨%' or p like '%스웨트%' or p like '%sweatshirt%' or p like '%sweats%' or p like '%> sweat') then 'sweatshirt'
  when app_detail_category='other_tops' and (p like '%셔츠%' or p like '%블라우스%' or p like '%shirt%' or p like '%blouse%') then 'shirt_blouse'
  when app_detail_category='other_tops' and (p like '%니트%' or p like '%스웨터%' or p like '%knit%' or p like '%sweater%') then 'knit_sweater'
  when app_detail_category='other_tops' and (p like '%언더레이어%' or p like '%base layer%') then 'base_layer_top'
  when app_detail_category='other_tops' and (p like '%유니폼%' or p like '%uniform%' or p like '%테니스%' or p like '%골프%' or p like '%football%' or p like '스포츠 유틸리티 웨어 > 상의%') then 'sports_top'
  when app_detail_category='other_tops' and (p like '%티셔츠%' or p like '%t-shirt%' or p like '%tshirt%' or p like '%graphic tee%' or p like '%그래픽티%') then 'tshirt'
  when app_detail_category='other_bottoms' and (p like '%래시가드%' or p like '%수영복%' or p like '%swim%') then 'swimwear'
  when app_detail_category='other_bottoms' and (p like '%치마바지%' or p like '%스커트 팬츠%' or p like '%스코츠%' or p like '%skort%') then 'skirt'
  when app_detail_category='other_bottoms' and (p like '%레깅스%' or p like '%leggings%') then 'leggings'
  when app_detail_category='other_bottoms' and (p like '%라운지%' or p like '%파자마%' or p like '%pajama%' or p like '%lounge pants%') then 'loungewear'
  when app_detail_category='other_bottoms' and (p like '%점프 슈트%' or p like '%점프슈트%' or p like '%오버롤%' or p like '%overall%' or p like '%jumpsuit%') then 'overalls_jumpsuit'
  when app_detail_category='other_bottoms' and (p like '%데님%' or p like '%청바지%' or p ~ '(^| > )진($| > )' or p like '%jeans%') then 'jeans'
  when app_detail_category='other_bottoms' and (p like '%슬랙스%' or p like '%트라우저%' or p like '%슈트 팬츠%' or p like '%감탄 팬츠%' or p like '%trouser%' or p like '%smart pants%') then 'slacks_trousers'
  when app_detail_category='other_bottoms' and (p like '%치노%' or p like '%코튼 팬츠%' or p like '%chino%') then 'chino_cotton'
  when app_detail_category='other_bottoms' and (p like '%조거%' or p like '%스웨트 팬츠%' or p like '%트레이닝 팬츠%' or p like '%jogger%' or p like '%sweat pants%' or p like '%쇼트 팬츠(반바지) > 스웨트%') then 'sweat_jogger'
  when app_detail_category='other_bottoms' and (p like '%카고%' or p like '%유틸리티%' or p like '%기어 팬츠%' or p like '%cargo%' or p like '%utility%') then 'cargo_utility'
  when app_detail_category='other_bottoms' and (p like '%유니폼%' or p like '%uniform%' or p like '%스포츠%' or p like '%sport%') then 'sports_bottom'
  when app_detail_category='other_bottoms' and (p like '%캐주얼 팬츠%' or p like '%일자 팬츠%' or p like '%와이드 팬츠%' or p like '%배럴 레그%' or p like '%팬츠 > 팬츠%') then 'casual_pants'
  else null end type_code,
 case
  when app_detail_category='other_tops'
   and not (p like '%반팔 & 긴팔%' or p like '%short%long%' or p like '%긴팔 & 반팔%')
   and (p like '%민소매%' or p like '%sleeveless%' or p like '%tank top%') then 'sleeveless'
  when app_detail_category='other_tops'
   and not (p like '%반팔 & 긴팔%' or p like '%short%long%' or p like '%긴팔 & 반팔%')
   and (p like '%7부%' or p like '%three-quarter sleeve%') then 'three_quarter_sleeve'
  when app_detail_category='other_tops'
   and not (p like '%반팔 & 긴팔%' or p like '%short%long%' or p like '%긴팔 & 반팔%')
   and (p like '%반팔%' or p like '%short sleeve%') then 'short_sleeve'
  when app_detail_category='other_tops'
   and not (p like '%반팔 & 긴팔%' or p like '%short%long%' or p like '%긴팔 & 반팔%')
   and (p like '%긴팔%' or p like '%long sleeve%') then 'long_sleeve'
  when app_detail_category='other_bottoms' and (p like '%7부%' or p like '%three-quarter%') then 'three_quarter_length'
  when app_detail_category='other_bottoms' and (p like '%9부%' or p like '%앵클%' or p like '%ankle%') then 'ankle_length'
  when app_detail_category='other_bottoms' and (p like '%반바지%' or p like '%쇼트 팬츠%' or p like '%short pants%' or p like '%shorts%') then 'short_length'
  when app_detail_category='other_bottoms' and (p like '%긴바지%' or p like '%긴 기장%' or p like '%long pants%' or p like '%long length%') then 'long_length'
  else null end length_code
 from target t
), resolved as (
 select c.*,
   ac.id new_category_id,
   parent.code new_parent_code
 from classified c
 left join public.app_categories ac on ac.code=c.type_code and ac.is_active
 left join public.app_categories parent on parent.id=ac.parent_id
), roots as (
 select code,id from public.app_categories where parent_id is null
)
update public.source_categories sc
set metadata = sc.metadata || jsonb_build_object(
      'taxonomy_v2_backup',
      coalesce(sc.metadata->'taxonomy_v2_backup',
        jsonb_build_object(
          'app_category',sc.app_category,
          'app_detail_category',sc.app_detail_category,
          'app_category_id',sc.app_category_id,
          'migrated_at',now()
        )
      )
    ),
    app_category = coalesce(r.new_parent_code,
       case when r.app_detail_category='other_tops' then 'tops' else 'bottoms' end),
    app_detail_category = r.type_code,
    app_category_id = coalesce(r.new_category_id,
       case when r.app_detail_category='other_tops'
            then (select id from roots where code='tops')
            else (select id from roots where code='bottoms') end),
    length_class_code = r.length_code,
    length_class_source = case when r.length_code is not null then 'original_path_explicit' else null end,
    length_class_evidence = case when r.length_code is not null then r.original_path else null end,
    updated_at = now()
from resolved r
where sc.id=r.id;

update public.app_categories
set is_active=false,
    metadata=metadata || jsonb_build_object('deprecated_by','taxonomy_v2','deprecated_at',now()),
    updated_at=now()
where code in ('other_tops','other_bottoms')
  and not exists (
    select 1 from public.source_categories sc
    where sc.app_category_id=public.app_categories.id
       or sc.app_detail_category=public.app_categories.code
  );
;
