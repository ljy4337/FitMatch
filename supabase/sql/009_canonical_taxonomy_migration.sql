begin;

create schema if not exists fitmatch_taxonomy;
revoke all on schema fitmatch_taxonomy from public, anon, authenticated;

create table if not exists fitmatch_taxonomy.policy_versions (
  code text primary key,
  schema_version text not null,
  taxonomy_version text not null,
  manifest_checksum text not null,
  status text not null check (status in ('loading','validated','active','failed','rolled_back')),
  created_at timestamptz not null default now(),
  validated_at timestamptz
);

create table if not exists fitmatch_taxonomy.source_snapshots (
  id uuid primary key,
  staging_snapshot_id uuid not null unique references fitmatch_staging.source_snapshots(id) on delete restrict,
  source_code text not null,
  snapshot_version text not null,
  collected_at timestamptz not null,
  activity_state text not null default 'unknown' check (activity_state='unknown'),
  node_count integer not null check (node_count>=0),
  raw_response_hash text not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  unique(source_code,snapshot_version,raw_response_hash)
);

create table if not exists fitmatch_taxonomy.source_categories (
  id uuid primary key,
  source_snapshot_id uuid not null references fitmatch_taxonomy.source_snapshots(id) on delete restrict,
  source_code text not null,
  external_category_id text not null,
  api_category_code text,
  raw_parent_external_category_id text,
  raw_name text not null,
  raw_full_path text not null,
  normalized_lookup_path text not null,
  target text not null,
  depth integer not null check(depth>=0),
  is_leaf boolean not null,
  is_navigation boolean not null,
  activity_state text not null check(activity_state='unknown'),
  source_url text,
  endpoint_kind text not null,
  source_evidence jsonb not null default '{}'::jsonb,
  raw_hash text not null,
  collected_at timestamptz not null,
  unique(source_snapshot_id,external_category_id,target,raw_hash),
  unique(source_snapshot_id,external_category_id,target,normalized_lookup_path)
);

create table if not exists fitmatch_taxonomy.category_hierarchy (
  source_snapshot_id uuid not null references fitmatch_taxonomy.source_snapshots(id) on delete restrict,
  parent_category_id uuid not null references fitmatch_taxonomy.source_categories(id) on delete restrict,
  child_category_id uuid not null references fitmatch_taxonomy.source_categories(id) on delete restrict,
  depth_delta smallint not null default 1 check(depth_delta=1),
  primary key(source_snapshot_id,parent_category_id,child_category_id),
  check(parent_category_id<>child_category_id)
);

create table if not exists fitmatch_taxonomy.semantic_garment_types (
  code text primary key,
  semantic_category_code text,
  comparison_family_code text,
  current_app_supported boolean not null,
  evidence jsonb not null default '{}'::jsonb,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.comparison_families (
  code text primary key,
  minimum_comparable_measurements smallint check(minimum_comparable_measurements>0),
  current_app_family_code text,
  is_active boolean not null default true,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.length_class_definitions (
  axis_code text not null,
  class_code text not null,
  is_unknown boolean not null default false,
  is_not_applicable boolean not null default false,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  primary key(axis_code,class_code),
  check(not(is_unknown and is_not_applicable))
);

create table if not exists fitmatch_taxonomy.classification_decisions (
  id uuid primary key default gen_random_uuid(),
  source_category_id uuid not null references fitmatch_taxonomy.source_categories(id) on delete restrict,
  decision_status text not null check(decision_status in ('navigation_only','confirmed','review_required','rejected','unsupported')),
  decision_method text not null,
  confidence numeric(5,4) check(confidence between 0 and 1),
  decision_reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  sampling_status text not null,
  reviewed_at timestamptz not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  legacy_policy_version text,
  semantic_category_code text,
  garment_type_code text references fitmatch_taxonomy.semantic_garment_types(code) on delete restrict,
  comparison_family_code text references fitmatch_taxonomy.comparison_families(code) on delete restrict,
  app_support_status text not null,
  fallback_required boolean not null,
  fallback_inputs text[] not null default '{}',
  canonical_default_allowed boolean not null,
  unique(source_category_id,policy_version),
  check(decision_status<>'confirmed' or (semantic_category_code is not null and garment_type_code is not null and comparison_family_code is not null and canonical_default_allowed)),
  check(decision_status<>'review_required' or (fallback_required and not canonical_default_allowed)),
  check(decision_status<>'rejected' or (comparison_family_code is null and not canonical_default_allowed)),
  check(decision_status<>'navigation_only' or (garment_type_code is null and comparison_family_code is null and not canonical_default_allowed))
);

create table if not exists fitmatch_taxonomy.decision_length_axes (
  decision_id uuid primary key references fitmatch_taxonomy.classification_decisions(id) on delete restrict,
  sleeve_length_class text not null,
  pants_length_class text not null,
  leggings_length_class text not null,
  skirt_length_class text not null,
  body_length_class text not null,
  construction_type text not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.category_app_mappings (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null unique references fitmatch_taxonomy.classification_decisions(id) on delete restrict,
  app_category_code text not null,
  app_detail_code text,
  current_comparison_family text,
  current_length_type text,
  mapping_status text not null check(mapping_status in ('direct','transform_required')),
  transformation_rule text not null,
  lossiness text not null,
  app_taxonomy_version text not null,
  comparison_policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.comparison_compatibility_rules (
  from_family_code text not null references fitmatch_taxonomy.comparison_families(code) on delete restrict,
  to_family_code text not null references fitmatch_taxonomy.comparison_families(code) on delete restrict,
  allowed boolean not null,
  directional boolean not null,
  length_match_required boolean not null,
  length_mismatch_excluded_measurements text[] not null,
  minimum_common_measurements smallint not null check(minimum_common_measurements>0),
  required_measurements text[] not null,
  measurement_weights jsonb not null,
  fallback_allowed boolean not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  primary key(from_family_code,to_family_code,policy_version)
);

create table if not exists fitmatch_taxonomy.measurement_definitions (
  code text primary key,
  display_name text,
  unit text not null default 'cm',
  representation text not null default 'linear',
  preserve_raw boolean not null default true,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.garment_measurement_policies (
  comparison_family_code text primary key references fitmatch_taxonomy.comparison_families(code) on delete restrict,
  required_measurements text[] not null,
  optional_measurements text[] not null,
  minimum_comparable_measurements smallint not null check(minimum_comparable_measurements>0),
  source_format_policy jsonb not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.source_measurement_aliases (
  id uuid primary key default gen_random_uuid(),
  source_code text not null,
  parser_code text,
  raw_code text,
  raw_label text not null,
  normalized_raw_label text,
  measurement_code text not null references fitmatch_taxonomy.measurement_definitions(code) on delete restrict,
  raw_representation text,
  comparison_basis text,
  conversion_multiplier numeric,
  category_scopes text[],
  is_comparable boolean not null,
  evidence text,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  unique(source_code,raw_label,measurement_code,policy_version)
);

create table if not exists fitmatch_taxonomy.decision_evidence (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references fitmatch_taxonomy.classification_decisions(id) on delete restrict,
  evidence_type text not null,
  evidence jsonb not null,
  evidence_hash text not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  unique(decision_id,evidence_type,evidence_hash)
);

create table if not exists fitmatch_taxonomy.legacy_identity_links (
  source_category_id uuid not null references fitmatch_taxonomy.source_categories(id) on delete restrict,
  legacy_source_category_id uuid not null references public.source_categories(id) on delete restrict,
  matching_method text not null,
  conflict_type text,
  evidence jsonb not null default '{}'::jsonb,
  primary key(source_category_id,legacy_source_category_id,matching_method)
);

create table if not exists fitmatch_taxonomy.classification_audit_history (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references fitmatch_taxonomy.classification_decisions(id) on delete restrict,
  legacy_source_category_id uuid references public.source_categories(id) on delete restrict,
  legacy_status text,
  canonical_status text not null,
  changed boolean not null,
  change_reason text not null,
  legacy_policy_version text,
  canonical_policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(decision_id,legacy_source_category_id)
);

create table if not exists fitmatch_taxonomy.extension_registry (
  decision_id uuid primary key references fitmatch_taxonomy.classification_decisions(id) on delete restrict,
  semantic_garment_type text,
  missing_app_category text,
  missing_app_detail text,
  missing_length_axis text,
  missing_comparison_family text,
  missing_measurement_policy text,
  recommended_code text,
  risk text not null,
  priority text not null,
  status text not null check(status in ('review_required','planned','approved','implemented')),
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict
);

create table if not exists fitmatch_taxonomy.promotion_manifests (
  id uuid primary key,
  migration_id text not null,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete restrict,
  schema_version text not null,
  taxonomy_version text not null,
  policy_version text not null references fitmatch_taxonomy.policy_versions(code) on delete restrict,
  manifest_checksum text not null,
  expected_counts jsonb not null,
  actual_counts jsonb,
  source_checksums jsonb not null,
  inserted_counts jsonb,
  skipped_counts jsonb,
  conflict_counts jsonb,
  validation_result jsonb,
  status text not null check(status in ('loading','validated','failed','rolled_back')),
  executed_at timestamptz not null default now(),
  validated_at timestamptz
);

create index if not exists canonical_source_external_idx on fitmatch_taxonomy.source_categories(source_code,external_category_id,target);
create index if not exists canonical_source_path_idx on fitmatch_taxonomy.source_categories(source_code,target,normalized_lookup_path);
create index if not exists canonical_decision_status_idx on fitmatch_taxonomy.classification_decisions(policy_version,decision_status);
create index if not exists canonical_decision_garment_idx on fitmatch_taxonomy.classification_decisions(garment_type_code,comparison_family_code) where decision_status='confirmed';
create index if not exists canonical_audit_legacy_idx on fitmatch_taxonomy.classification_audit_history(legacy_source_category_id);

alter table fitmatch_taxonomy.policy_versions enable row level security;
alter table fitmatch_taxonomy.source_snapshots enable row level security;
alter table fitmatch_taxonomy.source_categories enable row level security;
alter table fitmatch_taxonomy.category_hierarchy enable row level security;
alter table fitmatch_taxonomy.semantic_garment_types enable row level security;
alter table fitmatch_taxonomy.comparison_families enable row level security;
alter table fitmatch_taxonomy.length_class_definitions enable row level security;
alter table fitmatch_taxonomy.classification_decisions enable row level security;
alter table fitmatch_taxonomy.decision_length_axes enable row level security;
alter table fitmatch_taxonomy.category_app_mappings enable row level security;
alter table fitmatch_taxonomy.comparison_compatibility_rules enable row level security;
alter table fitmatch_taxonomy.measurement_definitions enable row level security;
alter table fitmatch_taxonomy.garment_measurement_policies enable row level security;
alter table fitmatch_taxonomy.source_measurement_aliases enable row level security;
alter table fitmatch_taxonomy.decision_evidence enable row level security;
alter table fitmatch_taxonomy.legacy_identity_links enable row level security;
alter table fitmatch_taxonomy.classification_audit_history enable row level security;
alter table fitmatch_taxonomy.extension_registry enable row level security;
alter table fitmatch_taxonomy.promotion_manifests enable row level security;

revoke all on all tables in schema fitmatch_taxonomy from public, anon, authenticated;

commit;
