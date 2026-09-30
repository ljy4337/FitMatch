-- LOCAL DISPOSABLE POSTGRESQL ONLY.
-- Minimal production-shaped schema and synthetic non-user data required to
-- compile and exercise migrations 113, 114, and 115. Never run in production.

\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (
    select 1 from pg_roles where rolname = 'authenticated'
  ) then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

create schema auth;
create schema fitmatch_catalog;
create schema fitmatch_taxonomy;
create schema fitmatch_qa;
create schema supabase_migrations;

create table auth.users (
  id uuid primary key default gen_random_uuid()
);

create table supabase_migrations.schema_migrations (
  version text primary key,
  name text not null,
  applied_at timestamptz not null default now()
);

create table public.app_categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.app_categories(id),
  code text not null,
  display_name_ko text not null,
  depth smallint not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (parent_id, code)
);

create unique index app_categories_major_code_unique_idx
  on public.app_categories(code)
  where parent_id is null;

create table public.comparison_groups (
  code text primary key,
  display_name_ko text not null,
  major_category_code text not null,
  allows_cross_type boolean not null default false,
  is_auto_comparable boolean not null default true,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.garment_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  major_category_code text not null,
  display_name_ko text not null,
  comparison_group_code text not null
    references public.comparison_groups(code) on update restrict on delete restrict,
  requires_sleeve_class boolean not null default false,
  requires_pants_length boolean not null default false,
  requires_body_length boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.comparison_length_classes (
  code text primary key,
  axis_code text not null,
  display_name_ko text not null,
  comparison_bucket_code text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.comparison_policies (
  code text primary key,
  comparison_group_code text not null unique
    references public.comparison_groups(code) on update restrict on delete restrict,
  cross_type_mode text not null,
  reference_priority_mode text not null,
  min_comparable_dimensions smallint not null,
  required_measurement_group_code text,
  policy_version text not null,
  is_active boolean not null default true,
  evidence_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.measurement_items (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique,
  display_name text not null,
  unit text not null default 'cm',
  value_type text not null default 'number',
  aliases text[] not null default '{}',
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_category_measurement_policies (
  id uuid primary key default gen_random_uuid(),
  app_category_id uuid not null references public.app_categories(id),
  measurement_item_id uuid not null references public.measurement_items(id),
  dimension_code text not null,
  weight numeric not null,
  is_primary boolean not null default false,
  is_comparable boolean not null default true,
  cross_source_mode text not null default 'compatible_basis',
  required_group_code text,
  required_group_min_dimensions smallint,
  display_order smallint not null default 0,
  selection_priority smallint not null default 0,
  policy_version text not null,
  evidence_note text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (app_category_id, measurement_item_id)
);

create table fitmatch_taxonomy.comparison_compatibility_rules (
  from_family_code text not null,
  to_family_code text not null,
  allowed boolean not null,
  directional boolean not null,
  length_match_required boolean not null,
  length_mismatch_excluded_measurements text[] not null,
  minimum_common_measurements smallint not null,
  required_measurements text[] not null,
  measurement_weights jsonb not null,
  fallback_allowed boolean not null,
  policy_version text not null,
  required_any_measurements text[] not null default '{}',
  minimum_required_any smallint not null default 0,
  primary key (from_family_code, to_family_code, policy_version),
  check (minimum_common_measurements >= 0),
  check (minimum_required_any >= 0)
);

create table fitmatch_catalog.releases (
  id uuid primary key default gen_random_uuid(),
  release_key text not null unique,
  taxonomy_version text not null,
  policy_version text not null,
  status text not null default 'loading'
    check (status in ('loading', 'validated', 'active', 'retired', 'failed')),
  bundle_checksum text not null,
  app_taxonomy_checksum text not null,
  expected_mapping_count integer not null,
  expected_qa_count integer not null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  validated_at timestamptz,
  activated_at timestamptz
);

create table fitmatch_catalog.source_category_mappings (
  release_id uuid not null references fitmatch_catalog.releases(id),
  source_identity text not null,
  source text not null,
  snapshot_id uuid not null,
  external_category_id text,
  target text not null,
  normalized_path text not null,
  decision_status text not null,
  mapping_status text,
  runtime_lookup_eligible boolean not null,
  eligibility boolean not null,
  semantic_category_code text,
  semantic_garment_type text,
  comparison_family text,
  source_external_key text,
  source_external_target_key text,
  source_path_key text,
  source_target_path_key text,
  raw_record jsonb not null,
  created_at timestamptz not null default now(),
  primary key (release_id, source_identity)
);

create table fitmatch_catalog.products (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  external_product_id text not null,
  product_name text not null,
  canonical_url text,
  audience text,
  source_category_path text,
  source_category_codes text[] not null default '{}',
  image_url text,
  raw_payload jsonb not null default '{}',
  input_fingerprint text not null,
  lifecycle_status text not null default 'active',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source, external_product_id)
);

create table fitmatch_catalog.product_classification_decisions (
  source text not null,
  external_product_id text not null,
  product_name text not null,
  source_category_path text not null,
  input_fingerprint text not null,
  category_code text,
  detail_code text,
  comparison_family text,
  length_type text,
  requires_user_confirmation boolean not null,
  release_id uuid not null references fitmatch_catalog.releases(id),
  decision_version text not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (source, external_product_id)
);

create table fitmatch_catalog.product_classification_history (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references fitmatch_catalog.products(id),
  input_fingerprint text not null,
  category_code text,
  detail_code text,
  comparison_family_code text,
  length_code text,
  classification_status text not null,
  classification_method text not null,
  confidence numeric,
  requires_user_confirmation boolean not null default false,
  taxonomy_policy_version text,
  mapping_release_id uuid references fitmatch_catalog.releases(id),
  decision_version text not null,
  evidence jsonb not null default '{}',
  is_current boolean not null default true,
  reviewed_by uuid,
  reviewed_at timestamptz,
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  body_length_code text
);

create unique index product_classification_history_one_current_idx
  on fitmatch_catalog.product_classification_history(product_id)
  where is_current;

create table fitmatch_catalog.product_measurements (
  id uuid primary key default gen_random_uuid()
);

create table fitmatch_catalog.classification_path_profiles (
  policy_version text not null,
  source text not null,
  normalized_path text not null,
  category_code text,
  detail_code text,
  comparison_family_code text,
  length_code text,
  sample_count integer not null,
  review_count integer not null,
  distinct_decision_count integer not null,
  auto_eligible boolean not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (policy_version, source, normalized_path)
);

create table fitmatch_catalog.classification_name_profiles (
  policy_version text not null,
  source text not null,
  normalized_path text not null,
  name_signature text not null,
  category_code text,
  detail_code text,
  comparison_family_code text,
  length_code text,
  sample_count integer not null,
  review_count integer not null,
  distinct_decision_count integer not null,
  auto_eligible boolean not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (policy_version, source, normalized_path, name_signature)
);

create table fitmatch_catalog.classification_exclusion_profiles (
  policy_version text not null,
  source text not null,
  normalized_path text not null,
  sample_count integer not null,
  auto_eligible boolean not null,
  reason_code text not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (policy_version, source, normalized_path)
);

create table fitmatch_catalog.product_observations (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  external_product_id text not null,
  payload_fingerprint text not null,
  observation_origin text not null default 'ios',
  raw_payload jsonb not null,
  processing_status text not null default 'pending',
  resolved_product_id uuid references fitmatch_catalog.products(id),
  normalization_summary jsonb not null default '{}',
  error_code text,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  observation_count integer not null default 1,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create table fitmatch_catalog.product_observation_measurements (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null
    references fitmatch_catalog.product_observations(id) on delete cascade,
  external_variant_id text not null,
  size_identity text not null,
  size_label text not null,
  measurement_ordinal integer not null,
  measurement_identity text not null,
  raw_code text,
  raw_label text not null,
  raw_value numeric not null,
  raw_unit text not null,
  raw_representation text,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table fitmatch_catalog.data_quality_issues (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid references fitmatch_catalog.product_observations(id),
  product_id uuid references fitmatch_catalog.products(id),
  classification_history_id uuid
    references fitmatch_catalog.product_classification_history(id),
  product_measurement_id uuid references fitmatch_catalog.product_measurements(id),
  issue_code text not null,
  severity text not null check (severity in ('low', 'medium', 'high', 'critical')),
  status text not null default 'open'
    check (status in ('open', 'acknowledged', 'resolved', 'ignored')),
  occurrence_count integer not null default 1 check (occurrence_count > 0),
  evidence jsonb not null default '{}',
  resolution jsonb not null default '{}',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint data_quality_issues_one_subject_check check (
    num_nonnulls(
      observation_id, product_id, classification_history_id, product_measurement_id
    ) = 1
  )
);

alter table fitmatch_catalog.data_quality_issues enable row level security;

create or replace function fitmatch_catalog.runtime_normalized_category_path(
  p_path text
) returns text language sql immutable set search_path = '' as $$
  select lower(regexp_replace(btrim(coalesce(p_path, '')), E'\\s+', ' ', 'g'))
$$;

create or replace function fitmatch_catalog.runtime_product_name_signature(
  p_name text
) returns text language sql immutable set search_path = '' as $$
  select lower(regexp_replace(btrim(coalesce(p_name, '')), E'\\s+', ' ', 'g'))
$$;

create or replace function fitmatch_catalog.runtime_product_fingerprint(
  p_name text,
  p_path text
) returns text language sql immutable set search_path = '' as $$
  select md5(
    fitmatch_catalog.runtime_product_name_signature(p_name)
    || E'\n'
    || fitmatch_catalog.runtime_normalized_category_path(p_path)
  )
$$;

create or replace function fitmatch_catalog.runtime_genders_are_compatible(
  p_reference_gender text,
  p_target_gender text,
  p_group text
) returns boolean language sql immutable set search_path = '' as $$
  select lower(coalesce(p_reference_gender, 'unisex')) = 'unisex'
    or lower(coalesce(p_target_gender, 'unisex')) = 'unisex'
    or lower(p_reference_gender) = lower(p_target_gender)
$$;

create or replace function fitmatch_catalog.runtime_resolve_product_classification_v2(
  text, text, text, text, jsonb
) returns jsonb language sql stable set search_path = '' as $$
  select '{"contract":"v2"}'::jsonb
$$;
create or replace function fitmatch_catalog.runtime_resolve_product_classification_v3(
  text, text, text, text, jsonb
) returns jsonb language sql stable set search_path = '' as $$
  select '{"contract":"v3"}'::jsonb
$$;
create or replace function fitmatch_catalog.runtime_record_product_classification(
  uuid, jsonb
) returns uuid language sql set search_path = '' as $$
  select null::uuid
$$;
create or replace function fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
  text, text, text, text, text, text,
  text, text, text, text, text, text, boolean
) returns jsonb language sql stable set search_path = '' as $$
  select '{"contract":"comparison-v3"}'::jsonb
$$;

create or replace function fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)
returns jsonb language sql set search_path = '' as $$
  select jsonb_build_object(
    'product_id', '00000000-0000-0000-0000-000000000001',
    'classification_id', null,
    'classification', '{}'::jsonb
  )
$$;
create or replace function fitmatch_catalog.runtime_ingest_product_payload(jsonb)
returns jsonb language sql set search_path = '' as $$
  select '{"variants_processed":0,"sizes_processed":0,"measurements_processed":0}'::jsonb
$$;
create or replace function fitmatch_catalog.runtime_resolve_source_mapping(jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select '{"found":false}'::jsonb
$$;
create or replace function fitmatch_catalog.runtime_normalize_measurement_v2(
  text, text, text, text, numeric, text, text
) returns jsonb language sql stable set search_path = '' as $$
  select '{"mapped":false,"reason":"measurement_alias_not_found"}'::jsonb
$$;
create or replace function fitmatch_catalog.runtime_resolve_observation_issue(
  uuid, text, jsonb
) returns void language plpgsql set search_path = '' as $$
begin
  return;
end
$$;
create or replace function fitmatch_catalog.runtime_record_observation_issue(
  uuid, text, text, jsonb
) returns uuid language sql set search_path = '' as $$ select null::uuid $$;

create or replace function fitmatch_qa.validate_product_runtime_v3()
returns jsonb language sql stable set search_path = '' as $$
  select '{"passed":true,"fixture":"local"}'::jsonb
$$;

create or replace function public.fitmatch_resolve_product(jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select '{"contract":"public-resolve"}'::jsonb
$$;
create or replace function public.fitmatch_get_product_runtime(jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select '{"contract":"public-runtime"}'::jsonb
$$;
create or replace function public.fitmatch_find_reference_candidates(uuid)
returns jsonb language sql stable set search_path = '' as $$
  select '[]'::jsonb
$$;
create or replace function public.fitmatch_begin_comparison(
  uuid, uuid, boolean, uuid
) returns jsonb language sql set search_path = '' as $$
  select '{"contract":"public-comparison"}'::jsonb
$$;

revoke all on all functions in schema fitmatch_catalog from public, anon, authenticated;
grant execute on all functions in schema fitmatch_catalog to service_role;
revoke all on function fitmatch_qa.validate_product_runtime_v3()
  from public, anon, authenticated;
grant execute on function fitmatch_qa.validate_product_runtime_v3()
  to service_role;
revoke all on function public.fitmatch_resolve_product(jsonb),
  public.fitmatch_get_product_runtime(jsonb),
  public.fitmatch_find_reference_candidates(uuid),
  public.fitmatch_begin_comparison(uuid, uuid, boolean, uuid)
  from public, anon;
grant execute on function public.fitmatch_resolve_product(jsonb),
  public.fitmatch_get_product_runtime(jsonb),
  public.fitmatch_find_reference_candidates(uuid),
  public.fitmatch_begin_comparison(uuid, uuid, boolean, uuid)
  to authenticated, service_role;

insert into public.app_categories (
  id, parent_id, code, display_name_ko, depth, sort_order
) values
  ('10000000-0000-0000-0000-000000000001', null, 'tops', '상의', 0, 1),
  ('10000000-0000-0000-0000-000000000002', null, 'bottoms', '하의', 0, 2),
  ('10000000-0000-0000-0000-000000000003', null, 'skirts', '스커트', 0, 3),
  ('10000000-0000-0000-0000-000000000004', null, 'homewear', '홈웨어', 0, 4),
  ('10000000-0000-0000-0000-000000000005', null, 'underwear', '언더웨어', 0, 5),
  ('10000000-0000-0000-0000-000000000006', null, 'dresses', '드레스', 0, 6),
  ('10000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000001', 'short_sleeve', '반소매', 1, 11),
  ('10000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-000000000001', 'long_sleeve', '긴소매', 1, 12),
  ('10000000-0000-0000-0000-000000000013', '10000000-0000-0000-0000-000000000001', 'base_layer_top', '베이스레이어', 1, 13),
  ('10000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000001', 'shirt', '셔츠', 1, 14),
  ('10000000-0000-0000-0000-000000000015', '10000000-0000-0000-0000-000000000001', 'knit', '니트', 1, 15),
  ('10000000-0000-0000-0000-000000000016', '10000000-0000-0000-0000-000000000001', 'polo_shirt', '폴로', 1, 16),
  ('10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000002', 'short_pants', '반바지', 1, 21),
  ('10000000-0000-0000-0000-000000000022', '10000000-0000-0000-0000-000000000002', 'jeans', '청바지', 1, 22),
  ('10000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000003', 'skirt', '스커트', 1, 31),
  ('10000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000004', 'homewear', '홈웨어', 1, 41),
  ('10000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000005', 'underwear', '언더웨어', 1, 51),
  ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000006', 'dress', '드레스', 1, 61);

insert into public.comparison_groups (
  code, display_name_ko, major_category_code, allows_cross_type,
  is_auto_comparable
) values
  ('tshirt', '티셔츠', 'tops', true, true),
  ('base_layer_top', '베이스레이어', 'tops', false, true),
  ('shirt', '셔츠', 'tops', true, true),
  ('knit', '니트', 'tops', true, true),
  ('short_pants', '반바지', 'bottoms', false, true),
  ('skirt', '스커트', 'skirts', false, true),
  ('homewear', '홈웨어', 'homewear', false, false),
  ('underwear', '언더웨어', 'underwear', false, false),
  ('dress', '드레스', 'dresses', false, false);

insert into public.garment_types (
  code, major_category_code, display_name_ko, comparison_group_code,
  requires_sleeve_class, requires_pants_length, requires_body_length
) values
  ('tshirt', 'tops', '티셔츠', 'tshirt', true, false, false),
  ('base_layer_top', 'tops', '베이스레이어', 'base_layer_top', true, false, false),
  ('shirt', 'tops', '셔츠', 'shirt', true, false, false),
  ('knit', 'tops', '니트', 'knit', true, false, false),
  ('short_pants', 'bottoms', '반바지', 'short_pants', false, true, false),
  ('skirt', 'skirts', '스커트', 'skirt', false, false, true),
  ('homewear', 'homewear', '홈웨어', 'homewear', false, false, false),
  ('underwear', 'underwear', '언더웨어', 'underwear', false, false, false),
  ('dress', 'dresses', '드레스', 'dress', false, false, true);

insert into public.comparison_length_classes (
  code, axis_code, display_name_ko, comparison_bucket_code
) values
  ('short_sleeve', 'sleeve', '반소매', 'short'),
  ('long_sleeve', 'sleeve', '긴소매', 'long'),
  ('short_pants', 'leg', '반바지', 'short'),
  ('long_pants', 'leg', '긴바지', 'long'),
  ('mini', 'body', '미니', 'short'),
  ('short_body', 'body', '숏', 'short'),
  ('midi', 'body', '미디', 'medium'),
  ('long', 'body', '롱', 'long');

insert into public.comparison_policies (
  code, comparison_group_code, cross_type_mode, reference_priority_mode,
  min_comparable_dimensions, required_measurement_group_code, policy_version
) values
  ('tshirt-policy', 'tshirt', 'cross_type_allowed', 'closest', 2, 'upper-core', 'comparison-policy-v1'),
  ('base-layer-policy', 'base_layer_top', 'same_type_only', 'closest', 2, 'upper-core', 'comparison-policy-v1'),
  ('shirt-policy', 'shirt', 'cross_type_allowed', 'closest', 2, 'upper-core', 'comparison-policy-v1'),
  ('knit-policy', 'knit', 'cross_type_allowed', 'closest', 2, 'upper-core', 'comparison-policy-v1'),
  ('short-pants-policy', 'short_pants', 'same_type_only', 'closest', 1, null, 'comparison-policy-v1'),
  ('skirt-policy', 'skirt', 'same_type_only', 'closest', 1, null, 'comparison-policy-v1'),
  ('homewear-policy', 'homewear', 'same_type_only', 'closest', 1, null, 'comparison-policy-v1'),
  ('underwear-policy', 'underwear', 'same_type_only', 'closest', 1, null, 'comparison-policy-v1'),
  ('dress-policy', 'dress', 'same_type_only', 'closest', 1, null, 'comparison-policy-v1');

insert into public.measurement_items (id, canonical_key, display_name) values
  ('20000000-0000-0000-0000-000000000001', 'chest-v1', '가슴'),
  ('20000000-0000-0000-0000-000000000002', 'shoulder-v1', '어깨'),
  ('20000000-0000-0000-0000-000000000003', 'sleeve-v1', '소매'),
  ('20000000-0000-0000-0000-000000000004', 'total-v1', '총장'),
  ('20000000-0000-0000-0000-000000000011', 'other-v2', '다른버전');

insert into public.app_category_measurement_policies (
  app_category_id, measurement_item_id, dimension_code, weight,
  is_primary, required_group_code, required_group_min_dimensions,
  display_order, policy_version
) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'chest', 1.50, true, 'upper-core', 2, 1, 'measure-v1'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'shoulder', 1.25, true, 'upper-core', 2, 2, 'measure-v1'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 'sleeve_length', 0.75, false, null, null, 3, 'measure-v1'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000004', 'total_length', 0.50, false, null, null, 4, 'measure-v1'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000011', 'other_only', 9.99, false, null, null, 11, 'measure-v2');

insert into fitmatch_taxonomy.comparison_compatibility_rules (
  from_family_code, to_family_code, allowed, directional,
  length_match_required, length_mismatch_excluded_measurements,
  minimum_common_measurements, required_measurements,
  measurement_weights, fallback_allowed, policy_version,
  required_any_measurements, minimum_required_any
) values
  ('tshirt', 'shirt', true, false, true, array['sleeve_length'], 2,
    array['chest'], '{"chest":2.5}', true, 'compatibility-rule-v1',
    array['shoulder','waist'], 1),
  ('tshirt', 'knit', false, false, false, array[]::text[], 1,
    array[]::text[], '{}', true, 'compatibility-rule-v1', array[]::text[], 0),
  ('shirt', 'knit', true, true, false, array['sleeve_length'], 2,
    array['chest'], '{"chest":1.75}', true, 'compatibility-rule-v1',
    array['shoulder'], 1),
  ('tshirt', 'shirt', true, false, false, array[]::text[], 1,
    array[]::text[], '{"wrong":99}', true, 'compatibility-rule-wrong',
    array[]::text[], 0);

insert into fitmatch_catalog.releases (
  id, release_key, taxonomy_version, policy_version, status,
  bundle_checksum, app_taxonomy_checksum, expected_mapping_count,
  expected_qa_count, activated_at
) values (
  '30000000-0000-0000-0000-000000000001',
  'synthetic-active-pre-114', 'taxonomy-v1', 'taxonomy-policy-v1', 'active',
  'synthetic-bundle', 'synthetic-app', 1, 1, now()
);

insert into fitmatch_catalog.source_category_mappings (
  release_id, source_identity, source, snapshot_id,
  external_category_id, target, normalized_path, decision_status,
  mapping_status, runtime_lookup_eligible, eligibility,
  semantic_category_code, semantic_garment_type, comparison_family,
  raw_record
) values (
  '30000000-0000-0000-0000-000000000001', 'fixture:tshirt', 'fixture',
  '30000000-0000-0000-0000-000000000099', 'tops/tshirt', 'UNISEX',
  'tops/tshirt', 'confirmed', 'direct', true, true,
  'tops', 'tshirt', 'tshirt',
  '{"appMapping":{"categoryCode":"tops","detailCode":"short_sleeve"},"authorityContract":{"authorityStatus":"verified","resolutionScope":"category_direct"},"lengthAxes":{"sleeve":"short_sleeve"}}'
);

insert into fitmatch_catalog.products (
  id, source, external_product_id, product_name, source_category_path,
  source_category_codes, input_fingerprint
) values (
  '40000000-0000-0000-0000-000000000001', 'fixture', 'legacy-product',
  'Legacy Product', 'legacy/path', array['legacy'],
  fitmatch_catalog.runtime_product_fingerprint('Legacy Product', 'legacy/path')
);

insert into fitmatch_catalog.product_classification_decisions (
  source, external_product_id, product_name, source_category_path,
  input_fingerprint, requires_user_confirmation, release_id,
  decision_version
) values (
  'fixture', 'legacy-product', 'Legacy Product', 'legacy/path',
  fitmatch_catalog.runtime_product_fingerprint('Legacy Product', 'legacy/path'),
  true, '30000000-0000-0000-0000-000000000001', 'legacy-v1'
);

insert into fitmatch_catalog.product_classification_history (
  id, product_id, input_fingerprint, classification_status,
  classification_method, requires_user_confirmation, decision_version
) values (
  '50000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  fitmatch_catalog.runtime_product_fingerprint('Legacy Product', 'legacy/path'),
  'review_required', 'unknown', true, 'legacy-v1'
);

comment on schema fitmatch_catalog is
  'Disposable local contract fixture; contains no production or user data.';
