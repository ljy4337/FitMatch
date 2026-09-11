-- FitMatch single comparison-group policy v2.
-- Preserves v1 and all product/user/classification data.
-- Creates one category-level group per source category plus two exact product overrides.

begin;

lock table fitmatch_catalog.comparison_group_policies in share row exclusive mode;
lock table fitmatch_catalog.source_category_comparison_groups in share row exclusive mode;

do $preflight$
declare
  v_v1_categories integer;
  v_v1_memberships integer;
begin
  if to_regclass('fitmatch_catalog.comparison_group_policies') is null
     or to_regclass('fitmatch_catalog.source_category_comparison_groups') is null then
    raise exception 'comparison group v1 tables are missing';
  end if;

  select count(distinct (source_code, source_category_key)), count(*)
    into v_v1_categories, v_v1_memberships
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v1-20260911';

  if v_v1_categories <> 418 or v_v1_memberships <> 468 then
    raise exception 'v1 preflight mismatch: categories %, memberships %',
      v_v1_categories, v_v1_memberships;
  end if;
end
$preflight$;

create table if not exists fitmatch_catalog.product_comparison_group_overrides (
  policy_version text not null
    references fitmatch_catalog.comparison_group_policies(policy_version)
    on update cascade on delete restrict,
  source_code text not null check (source_code ~ '^[a-z][a-z0-9_]*$'),
  external_product_id text not null check (btrim(external_product_id) <> ''),
  source_category_key text not null check (btrim(source_category_key) <> ''),
  group_code text not null check (group_code in ('A','B','C','D','E','F','X','R')),
  disposition text not null check (disposition in ('COMPARABLE','EXCLUDED','REVIEW')),
  reason text not null check (btrim(reason) <> ''),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence) = 'object'),
  created_at timestamptz not null default now(),
  primary key (policy_version, source_code, external_product_id),
  check (
    (group_code in ('A','B','C','D','E','F') and disposition = 'COMPARABLE')
    or (group_code = 'X' and disposition = 'EXCLUDED')
    or (group_code = 'R' and disposition = 'REVIEW')
  )
);

create index if not exists product_comparison_group_overrides_category_idx
  on fitmatch_catalog.product_comparison_group_overrides
    (policy_version, source_code, source_category_key);

create index if not exists product_comparison_group_overrides_group_idx
  on fitmatch_catalog.product_comparison_group_overrides
    (policy_version, group_code, source_code, external_product_id);

alter table fitmatch_catalog.product_comparison_group_overrides enable row level security;
revoke all on fitmatch_catalog.product_comparison_group_overrides from public, anon, authenticated;
grant select, insert, update, delete
  on fitmatch_catalog.product_comparison_group_overrides to service_role;

insert into fitmatch_catalog.comparison_group_policies (
  policy_version, status, source_checksum_sha256,
  expected_category_count, expected_membership_count, metadata
)
values (
  'retailer-comparison-groups-v2-single-20260911',
  'loading',
  'b28d59cfb8da62fee40a8af488e973a3e4eca56fff91dfaa86ba289de12d0842',
  418,
  418,
  jsonb_build_object(
    'derived_from', 'retailer-comparison-groups-v1-20260911',
    'single_group_per_category', true,
    'product_override_count', 2,
    'runtime_rpc_connected', false,
    'mixed_category_fallback', 'R',
    'group_definitions', jsonb_build_object(
      'A', '상의 비교군',
      'B', '아우터 비교군',
      'C', '바지·쇼츠 비교군',
      'D', '스커트 비교군',
      'E', '원피스·올인원 비교군',
      'F', '이너·홈웨어 비교군',
      'X', '비교 제외',
      'R', '분류 검토 필요'
    )
  )
)
on conflict (policy_version) do nothing;

do $policy_guard$
declare
  v_checksum text;
  v_expected_categories integer;
  v_expected_memberships integer;
begin
  select source_checksum_sha256, expected_category_count, expected_membership_count
    into strict v_checksum, v_expected_categories, v_expected_memberships
  from fitmatch_catalog.comparison_group_policies
  where policy_version = 'retailer-comparison-groups-v2-single-20260911';

  if v_checksum <> 'b28d59cfb8da62fee40a8af488e973a3e4eca56fff91dfaa86ba289de12d0842'
     or v_expected_categories <> 418
     or v_expected_memberships <> 418 then
    raise exception 'v2 policy version already exists with different content';
  end if;
end
$policy_guard$;

delete from fitmatch_catalog.product_comparison_group_overrides
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

delete from fitmatch_catalog.source_category_comparison_groups
where policy_version = 'retailer-comparison-groups-v2-single-20260911';

with choices(source_category_key, group_code) as (
  values
    ('musinsa:017018016', 'B'),
    ('musinsa:002021', 'B'),
    ('musinsa:002020', 'B'),
    ('musinsa:002022', 'B'),
    ('uniqlo:57894:81621:82095:82486', 'F'),
    ('uniqlo:57894:57978:58091:58636', 'F'),
    ('uniqlo:57894:57978:58091:58635', 'F'),
    ('uniqlo:57894:57978:58093:58646', 'F'),
    ('uniqlo:57894:57975:58084:58608', 'C'),
    ('uniqlo:57894:57974:58077:58581', 'B'),
    ('uniqlo:57894:57974:58077:96145', 'B'),
    ('uniqlo:57894:57974:58078:58587', 'A'),
    ('uniqlo:57894:103078:103082:103092', 'F'),
    ('uniqlo:57893:95355:128424:128427', 'B'),
    ('uniqlo:57893:57971:58067:98376', 'C'),
    ('uniqlo:57893:57971:58067:58545', 'C'),
    ('uniqlo:57893:95356:95360:95439', 'A'),
    ('uniqlo:57893:81620:82089:82144', 'F'),
    ('uniqlo:57893:57967:58039:58390', 'A'),
    ('uniqlo:57892:95353:128380:135281', 'B'),
    ('uniqlo:57892:95353:128380:128388', 'B'),
    ('uniqlo:57892:95353:128380:128382', 'B'),
    ('uniqlo:57892:95353:128380:136609', 'B'),
    ('uniqlo:57892:95353:128380:135282', 'B'),
    ('uniqlo:57892:95353:128380:128384', 'B'),
    ('uniqlo:57892:57961:58012:96141', 'C'),
    ('uniqlo:57892:57962:58013:105468', 'B'),
    ('uniqlo:57892:57962:58016:58266', 'F'),
    ('uniqlo:57892:81619:82085:82136', 'C'),
    ('uniqlo:57892:57963:58021:58304', 'F'),
    ('uniqlo:57892:57963:58021:58306', 'F'),
    ('uniqlo:57892:57963:58018:58280', 'F'),
    ('uniqlo:57892:57963:58018:58278', 'F'),
    ('uniqlo:57892:57963:58018:58275', 'F'),
    ('uniqlo:57892:57963:58018:58274', 'F'),
    ('uniqlo:57892:57963:141497:141498', 'F'),
    ('uniqlo:57892:57963:141497:141499', 'F'),
    ('uniqlo:57892:57959:57996:117295', 'F'),
    ('uniqlo:57892:57959:57996:117300', 'F'),
    ('uniqlo:57892:57964:58026:112811', 'C'),
    ('uniqlo:57892:57964:58026:58336', 'C'),
    ('uniqlo:57892:57964:58026:94359', 'C'),
    ('uniqlo:57892:57964:58026:94358', 'C'),
    ('uniqlo:57892:57964:58026:58335', 'C'),
    ('uniqlo:57892:57964:58025:141118', 'F'),
    ('uniqlo:57892:57964:58025:58332', 'F'),
    ('uniqlo:57892:57964:58025:74427', 'F'),
    ('zara:3:131:606', 'B'),
    ('zara:3:131:564', 'B'),
    ('uniqlo:57892:57964:58025:58334', 'R')
), v1_one_row_per_category as (
  select distinct on (source_code, source_category_key) *
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v1-20260911'
  order by source_code, source_category_key, group_code
), selected as (
  select
    base.*,
    coalesce(choice.group_code, base.group_code) as selected_group_code
  from v1_one_row_per_category base
  left join choices choice using (source_category_key)
)
insert into fitmatch_catalog.source_category_comparison_groups (
  policy_version, source_code, source_category_key, group_code, disposition,
  category_path, source_ids, source_names, audience_codes, product_count,
  sample_products, mapping_basis, notes, source_record
)
select
  'retailer-comparison-groups-v2-single-20260911',
  source_code,
  source_category_key,
  selected_group_code,
  case selected_group_code
    when 'X' then 'EXCLUDED'
    when 'R' then 'REVIEW'
    else 'COMPARABLE'
  end,
  category_path,
  source_ids,
  source_names,
  audience_codes,
  product_count,
  sample_products,
  mapping_basis || '; collapsed_to_single_group_v2',
  notes,
  source_record || jsonb_build_object(
    'group_codes', jsonb_build_array(selected_group_code),
    'group_labels', jsonb_build_array(
      case selected_group_code
        when 'A' then '상의 비교군'
        when 'B' then '아우터 비교군'
        when 'C' then '바지·쇼츠 비교군'
        when 'D' then '스커트 비교군'
        when 'E' then '원피스·올인원 비교군'
        when 'F' then '이너·홈웨어 비교군'
        when 'X' then '비교 제외'
        else '분류 검토 필요'
      end
    ),
    'disposition', case selected_group_code
      when 'X' then 'EXCLUDED'
      when 'R' then 'REVIEW'
      else 'COMPARABLE'
    end,
    'single_group_policy', true
  )
from selected;

insert into fitmatch_catalog.product_comparison_group_overrides (
  policy_version, source_code, external_product_id, source_category_key,
  group_code, disposition, reason, evidence
)
values
  (
    'retailer-comparison-groups-v2-single-20260911',
    'uniqlo', 'E461767', 'uniqlo:57892:57964:58025:58334',
    'X', 'EXCLUDED',
    'Mixed source category exact-product override: room shoes are not comparable apparel',
    '{"product_name":"룸슈즈","decision_basis":"exact_product_exception"}'::jsonb
  ),
  (
    'retailer-comparison-groups-v2-single-20260911',
    'uniqlo', 'E488014', 'uniqlo:57892:57964:58025:58334',
    'B', 'COMPARABLE',
    'Mixed source category exact-product override: rib V-neck cardigan is outerwear',
    '{"product_name":"립V넥가디건","decision_basis":"exact_product_exception"}'::jsonb
  );

do $validate$
declare
  v_categories integer;
  v_memberships integer;
  v_overrides integer;
  v_bad_providers integer;
  v_v1_categories integer;
  v_v1_memberships integer;
begin
  select count(distinct (source_code, source_category_key)), count(*)
    into v_categories, v_memberships
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v2-single-20260911';

  if v_categories <> 418 or v_memberships <> 418 then
    raise exception 'v2 validation mismatch: categories %, memberships %',
      v_categories, v_memberships;
  end if;

  select count(*) into v_overrides
  from fitmatch_catalog.product_comparison_group_overrides
  where policy_version = 'retailer-comparison-groups-v2-single-20260911';
  if v_overrides <> 2 then
    raise exception 'expected 2 exact product overrides, got %', v_overrides;
  end if;

  select count(*) into v_bad_providers
  from (
    select source_code, count(*) category_count
    from fitmatch_catalog.source_category_comparison_groups
    where policy_version = 'retailer-comparison-groups-v2-single-20260911'
    group by source_code
  ) counts
  where (source_code = 'uniqlo' and category_count <> 334)
     or (source_code = 'musinsa' and category_count <> 36)
     or (source_code = 'zara' and category_count <> 48)
     or source_code not in ('uniqlo','musinsa','zara');
  if v_bad_providers <> 0 then
    raise exception 'v2 provider category counts differ from v1';
  end if;

  select count(distinct (source_code, source_category_key)), count(*)
    into v_v1_categories, v_v1_memberships
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v1-20260911';
  if v_v1_categories <> 418 or v_v1_memberships <> 468 then
    raise exception 'v1 changed unexpectedly during v2 apply';
  end if;

  update fitmatch_catalog.comparison_group_policies
  set status = 'validated', validated_at = now()
  where policy_version = 'retailer-comparison-groups-v2-single-20260911';
end
$validate$;

commit;

with mappings as (
  select *
  from fitmatch_catalog.source_category_comparison_groups
  where policy_version = 'retailer-comparison-groups-v2-single-20260911'
), provider_counts as (
  select source_code, count(*) as category_count
  from mappings
  group by source_code
), override_counts as (
  select source_code, count(*) as override_count
  from fitmatch_catalog.product_comparison_group_overrides
  where policy_version = 'retailer-comparison-groups-v2-single-20260911'
  group by source_code
)
select
  policy.policy_version,
  policy.status,
  policy.source_checksum_sha256,
  count(*) as category_node_count,
  count(distinct (mappings.source_code, mappings.source_category_key)) as distinct_category_node_count,
  (select jsonb_object_agg(source_code, category_count order by source_code) from provider_counts)
    as provider_category_counts,
  (select coalesce(sum(override_count), 0) from override_counts) as product_override_count
from fitmatch_catalog.comparison_group_policies policy
join mappings on true
where policy.policy_version = 'retailer-comparison-groups-v2-single-20260911'
group by policy.policy_version, policy.status, policy.source_checksum_sha256;
