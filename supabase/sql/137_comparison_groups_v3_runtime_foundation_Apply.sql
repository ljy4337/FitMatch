-- Seven user-facing comparison groups and server-side group projection.
-- Development rollout: v1/v2 category-group policies are replaced by v3.

begin;

lock table fitmatch_catalog.comparison_group_policies in share row exclusive mode;
lock table fitmatch_catalog.source_category_comparison_groups in share row exclusive mode;

alter table fitmatch_catalog.source_category_comparison_groups
  drop constraint if exists source_category_comparison_groups_group_code_check;
alter table fitmatch_catalog.source_category_comparison_groups
  add constraint source_category_comparison_groups_group_code_check
  check (group_code in ('A','B','C','D','E','F','G','X','R'));
alter table fitmatch_catalog.source_category_comparison_groups
  drop constraint if exists source_category_comparison_groups_check;
alter table fitmatch_catalog.source_category_comparison_groups
  add constraint source_category_comparison_groups_check check (
    (group_code in ('A','B','C','D','E','F','G') and disposition = 'COMPARABLE')
    or (group_code = 'X' and disposition = 'EXCLUDED')
    or (group_code = 'R' and disposition = 'REVIEW')
  );

alter table fitmatch_catalog.product_comparison_group_overrides
  drop constraint if exists product_comparison_group_overrides_group_code_check;
alter table fitmatch_catalog.product_comparison_group_overrides
  add constraint product_comparison_group_overrides_group_code_check
  check (group_code in ('A','B','C','D','E','F','G','X','R'));
alter table fitmatch_catalog.product_comparison_group_overrides
  drop constraint if exists product_comparison_group_overrides_check;
alter table fitmatch_catalog.product_comparison_group_overrides
  add constraint product_comparison_group_overrides_check check (
    (group_code in ('A','B','C','D','E','F','G') and disposition = 'COMPARABLE')
    or (group_code = 'X' and disposition = 'EXCLUDED')
    or (group_code = 'R' and disposition = 'REVIEW')
  );

create table if not exists fitmatch_catalog.comparison_groups (
  group_code text primary key check (group_code in ('A','B','C','D','E','F','G')),
  display_order smallint not null unique check (display_order between 1 and 7),
  display_name text not null check (btrim(display_name) <> ''),
  description text not null check (btrim(description) <> ''),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table fitmatch_catalog.comparison_groups enable row level security;
revoke all on fitmatch_catalog.comparison_groups from public, anon;
grant select on fitmatch_catalog.comparison_groups to authenticated, service_role;
grant insert, update, delete on fitmatch_catalog.comparison_groups to service_role;

insert into fitmatch_catalog.comparison_groups
  (group_code, display_order, display_name, description, active)
values
  ('A', 1, '상의', '티셔츠, 셔츠, 블라우스, 니트, 맨투맨, 후드', true),
  ('B', 2, '아우터', '재킷, 점퍼, 블루종, 코트, 패딩, 가디건, 조끼', true),
  ('C', 3, '바지', '청바지, 슬랙스, 조거팬츠, 반바지, 레깅스', true),
  ('D', 4, '스커트', '미니, 미디, 롱스커트', true),
  ('E', 5, '원피스·한벌옷', '원피스, 바디수트, 커버올, 우주복, 멜빵바지', true),
  ('F', 6, '이너웨어', '속옷, 브라탑, 내의, 기능성 이너', true),
  ('G', 7, '홈웨어·파자마', '잠옷, 라운지웨어, 홈웨어', true)
on conflict (group_code) do update set
  display_order = excluded.display_order,
  display_name = excluded.display_name,
  description = excluded.description,
  active = excluded.active,
  updated_at = now();

insert into fitmatch_catalog.comparison_group_policies (
  policy_version, status, source_checksum_sha256,
  expected_category_count, expected_membership_count, metadata,
  validated_at, activated_at
)
values (
  'retailer-comparison-groups-v3-seven-20260911',
  'validated',
  encode(extensions.digest('retailer-comparison-groups-v3-seven-20260911', 'sha256'), 'hex'),
  418,
  418,
  jsonb_build_object(
    'single_group_per_category', true,
    'runtime_rpc_connected', false,
    'user_selectable_group_count', 7,
    'group_definitions', jsonb_build_object(
      'A', '상의', 'B', '아우터', 'C', '바지', 'D', '스커트',
      'E', '원피스·한벌옷', 'F', '이너웨어', 'G', '홈웨어·파자마',
      'X', '비교 제외', 'R', '직접 선택 필요'
    )
  ),
  now(), null
)
on conflict (policy_version) do update set
  status = excluded.status,
  source_checksum_sha256 = excluded.source_checksum_sha256,
  expected_category_count = excluded.expected_category_count,
  expected_membership_count = excluded.expected_membership_count,
  metadata = excluded.metadata,
  validated_at = excluded.validated_at,
  activated_at = excluded.activated_at;

delete from fitmatch_catalog.product_comparison_group_overrides
where policy_version = 'retailer-comparison-groups-v3-seven-20260911';
delete from fitmatch_catalog.source_category_comparison_groups
where policy_version = 'retailer-comparison-groups-v3-seven-20260911';

insert into fitmatch_catalog.source_category_comparison_groups (
  policy_version, source_code, source_category_key, group_code, disposition,
  category_path, source_ids, source_names, audience_codes, product_count,
  sample_products, mapping_basis, notes, source_record
)
select
  'retailer-comparison-groups-v3-seven-20260911',
  source_code,
  source_category_key,
  case
    when group_code = 'F'
      and array_to_string(category_path, ' > ') ilike '%유아용 바디%'
      then 'E'
    when group_code = 'F'
      and array_to_string(category_path, ' > ') ~* '(파자마|홈웨어|라운지|PIJAMA|PAJAMA|LOUNGE)'
      then 'G'
    when group_code = 'E'
      and array_to_string(category_path, ' > ') = 'WOMEN > GU > 원피스 & 스커트 > 스커트'
      then 'D'
    else group_code
  end,
  disposition,
  category_path,
  source_ids,
  source_names,
  audience_codes,
  product_count,
  sample_products,
  mapping_basis || '; seven_group_v3',
  notes,
  source_record || jsonb_build_object(
    'group_codes', jsonb_build_array(case
      when group_code = 'F' and array_to_string(category_path, ' > ') ilike '%유아용 바디%' then 'E'
      when group_code = 'F' and array_to_string(category_path, ' > ') ~* '(파자마|홈웨어|라운지|PIJAMA|PAJAMA|LOUNGE)' then 'G'
      when group_code = 'E' and array_to_string(category_path, ' > ') = 'WOMEN > GU > 원피스 & 스커트 > 스커트' then 'D'
      else group_code end),
    'seven_group_policy', true
  )
from fitmatch_catalog.source_category_comparison_groups
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

insert into fitmatch_catalog.product_comparison_group_overrides (
  policy_version, source_code, external_product_id, source_category_key,
  group_code, disposition, reason, evidence
)
select
  'retailer-comparison-groups-v3-seven-20260911', source_code,
  external_product_id, source_category_key, group_code, disposition,
  reason, evidence
from fitmatch_catalog.product_comparison_group_overrides
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

-- The v1/v2 rows were development scaffolding and are no longer retained.
delete from fitmatch_catalog.product_comparison_group_overrides
where policy_version <> 'retailer-comparison-groups-v3-seven-20260911';
delete from fitmatch_catalog.source_category_comparison_groups
where policy_version <> 'retailer-comparison-groups-v3-seven-20260911';
delete from fitmatch_catalog.comparison_group_policies
where policy_version <> 'retailer-comparison-groups-v3-seven-20260911';

alter table fitmatch_vnext.closet_items
  add column if not exists comparison_group_code text,
  add column if not exists comparison_group_source text,
  add column if not exists comparison_group_policy_version text;

alter table fitmatch_vnext.closet_items
  drop constraint if exists closet_items_comparison_group_code_chk;
alter table fitmatch_vnext.closet_items
  add constraint closet_items_comparison_group_code_chk
  check (comparison_group_code is null or comparison_group_code in ('A','B','C','D','E','F','G'));
alter table fitmatch_vnext.closet_items
  drop constraint if exists closet_items_comparison_group_source_chk;
alter table fitmatch_vnext.closet_items
  add constraint closet_items_comparison_group_source_chk
  check (comparison_group_source is null or comparison_group_source in
    ('RETAILER_CATEGORY','USER_SELECTED','LEGACY_DERIVED'));

create index if not exists closet_items_user_comparison_group_idx
  on fitmatch_vnext.closet_items(user_id, comparison_group_code)
  where deleted_at is null;

create or replace function fitmatch_vnext.product_comparison_group(p_product_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  product_row fitmatch_vnext.products%rowtype;
  mapping_row record;
begin
  select * into product_row
  from fitmatch_vnext.products p where p.id = p_product_id;
  if not found then return null; end if;

  select o.group_code, o.disposition, o.source_category_key,
         'PRODUCT_OVERRIDE'::text as mapping_source
    into mapping_row
  from fitmatch_catalog.product_comparison_group_overrides o
  where o.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
    and o.source_code = product_row.source_code
    and o.external_product_id = product_row.source_product_key
  limit 1;

  if not found then
    select m.group_code, m.disposition, m.source_category_key,
           'RETAILER_CATEGORY'::text as mapping_source
      into mapping_row
    from fitmatch_catalog.source_category_comparison_groups m
    where m.policy_version = 'retailer-comparison-groups-v3-seven-20260911'
      and m.source_code = product_row.source_code
      and (
        array_to_string(m.category_path, ' > ') =
          product_row.source_extra ->> 'source_category_path'
        or array_to_string(
          m.category_path[2:cardinality(m.category_path)], ' > '
        ) = product_row.source_extra ->> 'source_category_path'
      )
    limit 1;
  end if;

  if not found then
    return jsonb_build_object(
      'status', 'REVIEW', 'group_code', null, 'display_name', null,
      'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
      'mapping_source', 'UNMAPPED'
    );
  end if;

  return jsonb_build_object(
    'status', mapping_row.disposition,
    'group_code', case when mapping_row.group_code in ('A','B','C','D','E','F','G')
      then mapping_row.group_code else null end,
    'display_name', (select g.display_name from fitmatch_catalog.comparison_groups g
      where g.group_code = mapping_row.group_code),
    'policy_version', 'retailer-comparison-groups-v3-seven-20260911',
    'mapping_source', mapping_row.mapping_source,
    'source_category_key', mapping_row.source_category_key
  );
end
$function$;

revoke all on function fitmatch_vnext.product_comparison_group(uuid) from public, anon;
grant execute on function fitmatch_vnext.product_comparison_group(uuid)
  to authenticated, service_role;

create or replace function fitmatch_vnext.legacy_comparison_group(p_garment_type_code text)
returns text
language sql
stable
set search_path = ''
as $function$
  select case gt.category_code
    when 'tops' then 'A'
    when 'outerwear' then 'B'
    when 'bottoms' then 'C'
    when 'leggings' then 'C'
    when 'skirts' then 'D'
    when 'dresses' then 'E'
    when 'underwear' then 'F'
    when 'homewear' then 'G'
    else null
  end
  from fitmatch_vnext.garment_types gt
  where gt.garment_type_code = p_garment_type_code
$function$;

revoke all on function fitmatch_vnext.legacy_comparison_group(text) from public, anon;
grant execute on function fitmatch_vnext.legacy_comparison_group(text)
  to authenticated, service_role;

update fitmatch_vnext.closet_items ci
set comparison_group_code = coalesce(
      fitmatch_vnext.product_comparison_group(ci.product_id) ->> 'group_code',
      fitmatch_vnext.legacy_comparison_group(ci.garment_type_code)
    ),
    comparison_group_source = case
      when fitmatch_vnext.product_comparison_group(ci.product_id) ->> 'group_code' is not null
        then 'RETAILER_CATEGORY'
      else 'LEGACY_DERIVED'
    end,
    comparison_group_policy_version = 'retailer-comparison-groups-v3-seven-20260911'
where ci.comparison_group_code is null;

do $validate$
declare
  v_categories integer;
  v_memberships integer;
  v_groups integer;
  v_bad integer;
begin
  select count(distinct (source_code, source_category_key)), count(*)
    into v_categories, v_memberships
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v3-seven-20260911';
  select count(*) into v_groups from fitmatch_catalog.comparison_groups where active;
  select count(*) into v_bad
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v3-seven-20260911'
    and ((group_code in ('A','B','C','D','E','F','G') and disposition <> 'COMPARABLE')
      or (group_code='R' and disposition <> 'REVIEW')
      or (group_code='X' and disposition <> 'EXCLUDED'));
  if v_categories <> 418 or v_memberships <> 418 or v_groups <> 7 or v_bad <> 0 then
    raise exception 'v3 validation failed: categories %, memberships %, groups %, bad %',
      v_categories, v_memberships, v_groups, v_bad;
  end if;
end
$validate$;

commit;
