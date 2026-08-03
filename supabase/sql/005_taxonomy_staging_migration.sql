begin;

create schema if not exists fitmatch_staging;
revoke all on schema fitmatch_staging from public, anon, authenticated;

create table if not exists fitmatch_staging.import_runs (
  id uuid primary key,
  import_key text not null unique,
  schema_version text not null,
  input_checksum text not null,
  output_checksum text,
  status text not null check (status in ('pending','loading','validating','completed','incomplete','failed','rolled_back')),
  started_at timestamptz not null,
  completed_at timestamptz,
  failure_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check ((status = 'completed') = (completed_at is not null))
);

create table if not exists fitmatch_staging.source_snapshots (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  source_code text not null,
  snapshot_version text not null,
  collected_at timestamptz not null,
  raw_collection_status text not null check (raw_collection_status in ('collected','failed','incomplete')),
  node_count integer not null check (node_count >= 0),
  raw_response_hash text not null,
  source_evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (import_run_id, source_code, snapshot_version),
  unique (source_code, snapshot_version, raw_response_hash)
);

create table if not exists fitmatch_staging.source_category_nodes (
  id uuid primary key,
  source_snapshot_id uuid not null references fitmatch_staging.source_snapshots(id) on delete cascade,
  node_identity text not null,
  external_category_id text not null,
  raw_parent_external_category_id text,
  raw_name text not null,
  raw_path text not null,
  normalized_path text not null,
  target text not null,
  depth integer not null check (depth >= 0),
  is_leaf boolean not null,
  activity_status text not null check (activity_status in ('active','inactive','activity_unknown')),
  endpoint_kind text not null,
  source_url text,
  raw_hash text not null,
  raw_evidence jsonb not null default '{}'::jsonb,
  collected_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (source_snapshot_id, node_identity),
  unique (source_snapshot_id, external_category_id, target, raw_hash)
);

create table if not exists fitmatch_staging.source_category_hierarchy (
  source_snapshot_id uuid not null references fitmatch_staging.source_snapshots(id) on delete cascade,
  parent_node_id uuid not null references fitmatch_staging.source_category_nodes(id) on delete cascade,
  child_node_id uuid not null references fitmatch_staging.source_category_nodes(id) on delete cascade,
  depth_delta integer not null default 1 check (depth_delta = 1),
  primary key (source_snapshot_id, parent_node_id, child_node_id),
  check (parent_node_id <> child_node_id)
);

create table if not exists fitmatch_staging.classification_candidates (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  source_node_id uuid not null references fitmatch_staging.source_category_nodes(id) on delete cascade,
  candidate_group text not null check (candidate_group in ('A','B','C','D','E','F')),
  raw_collection_status text not null check (raw_collection_status in ('collected','failed','incomplete')),
  identity_resolution_status text not null check (identity_resolution_status in ('matched_1_to_1','matched_complex','new_source_category','conflict','unresolved')),
  product_observation_status text not null check (product_observation_status in ('product_observed','navigation_only','no_product_observed','collection_failed','activity_unknown')),
  sampling_status text not null check (sampling_status in ('not_sampled','sampled_partial','sampled_sufficient','sampling_conflict','manual_review_required')),
  provisional_classification_status text not null check (provisional_classification_status in ('provisional_confirmed','review_required','provisional_rejected','provisional_unsupported','unknown')),
  canonical_promotion_status text not null default 'not_eligible' check (canonical_promotion_status in ('not_eligible','blocked','ready_for_review','approved','promoted')),
  semantic_garment_candidate text,
  length_axes jsonb not null default '{}'::jsonb,
  comparison_family_candidate text,
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  current_app_support text not null,
  manual_review_required boolean not null,
  policy_version text not null,
  created_at timestamptz not null default now(),
  unique (import_run_id, source_node_id),
  check (canonical_promotion_status not in ('approved','promoted'))
);

create table if not exists fitmatch_staging.identity_components (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  component_key text not null,
  relation_type text not null check (relation_type in ('1:1','1:N','N:1','N:N')),
  db_record_count integer not null check (db_record_count > 0),
  snapshot_node_count integer not null check (snapshot_node_count > 0),
  evidence jsonb not null default '{}'::jsonb,
  unique (import_run_id, component_key)
);

create table if not exists fitmatch_staging.identity_matching_edges (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  component_id uuid not null references fitmatch_staging.identity_components(id) on delete cascade,
  source_db_record_id uuid not null references public.source_categories(id) on delete restrict,
  snapshot_node_id uuid not null references fitmatch_staging.source_category_nodes(id) on delete cascade,
  matching_method text not null check (matching_method in ('id_target','id','path_target','path')),
  match_confidence numeric(5,4) not null check (match_confidence between 0 and 1),
  conflict_type text,
  adjudication_status text not null check (adjudication_status in ('not_required','pending','reviewed','resolved')),
  evidence jsonb not null default '{}'::jsonb,
  unique (import_run_id, source_db_record_id, snapshot_node_id, matching_method)
);

create table if not exists fitmatch_staging.identity_conflict_adjudications (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  conflict_key text not null,
  conflict_type text not null,
  source_db_record_id uuid references public.source_categories(id) on delete restrict,
  snapshot_node_id uuid references fitmatch_staging.source_category_nodes(id) on delete cascade,
  current_official_identity text,
  past_identity text,
  alias_relationship boolean not null,
  target_separation_required boolean not null,
  snapshot_version_change boolean not null,
  parent_change boolean not null,
  rename boolean not null,
  id_reissued boolean not null,
  manual_review_required boolean not null,
  canonical_action text not null,
  evidence jsonb not null default '{}'::jsonb,
  unique (import_run_id, conflict_key)
);

create table if not exists fitmatch_staging.sampling_runs (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  sampling_key text not null,
  status text not null check (status in ('loading','validating','completed','incomplete','failed')),
  category_count integer not null,
  product_count integer not null,
  collection_failure_count integer not null,
  started_at timestamptz not null,
  completed_at timestamptz,
  methodology jsonb not null default '{}'::jsonb,
  unique (import_run_id, sampling_key)
);

create table if not exists fitmatch_staging.sampled_category_results (
  id uuid primary key,
  sampling_run_id uuid not null references fitmatch_staging.sampling_runs(id) on delete cascade,
  candidate_id uuid not null references fitmatch_staging.classification_candidates(id) on delete cascade,
  sampled_product_count integer not null check (sampled_product_count >= 0),
  garment_distribution jsonb not null,
  length_distribution jsonb not null,
  exception_count integer not null check (exception_count >= 0),
  exception_rate numeric(7,6),
  category_level_consistent boolean not null,
  review_required boolean not null,
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  reviewed_at timestamptz not null,
  evidence jsonb not null default '{}'::jsonb,
  unique (sampling_run_id, candidate_id)
);

create table if not exists fitmatch_staging.sampled_product_evidence (
  id uuid primary key,
  sampling_run_id uuid not null references fitmatch_staging.sampling_runs(id) on delete cascade,
  candidate_id uuid not null references fitmatch_staging.classification_candidates(id) on delete cascade,
  source_code text not null,
  external_product_id text not null,
  product_name text not null,
  evidence_url text not null,
  observed_garment_type text,
  observed_length_class text,
  is_exception boolean not null,
  sampled_at timestamptz not null,
  raw_evidence_hash text not null,
  evidence jsonb not null default '{}'::jsonb,
  unique (sampling_run_id, candidate_id, external_product_id)
);

create table if not exists fitmatch_staging.validation_results (
  id uuid primary key,
  import_run_id uuid not null references fitmatch_staging.import_runs(id) on delete cascade,
  rule_code text not null,
  severity text not null check (severity in ('info','warning','error')),
  passed boolean not null,
  affected_count integer not null check (affected_count >= 0),
  expected_value jsonb,
  actual_value jsonb,
  details jsonb not null default '{}'::jsonb,
  validated_at timestamptz not null default now(),
  unique (import_run_id, rule_code)
);

create index if not exists staging_nodes_external_lookup on fitmatch_staging.source_category_nodes(source_snapshot_id, external_category_id, target);
create index if not exists staging_nodes_path_lookup on fitmatch_staging.source_category_nodes(source_snapshot_id, normalized_path, target);
create index if not exists staging_candidates_status_lookup on fitmatch_staging.classification_candidates(import_run_id, provisional_classification_status, canonical_promotion_status);
create index if not exists staging_edges_db_lookup on fitmatch_staging.identity_matching_edges(import_run_id, source_db_record_id);
create index if not exists staging_edges_node_lookup on fitmatch_staging.identity_matching_edges(import_run_id, snapshot_node_id);
create index if not exists staging_product_candidate_lookup on fitmatch_staging.sampled_product_evidence(sampling_run_id, candidate_id);

revoke all on all tables in schema fitmatch_staging from public, anon, authenticated;

commit;

