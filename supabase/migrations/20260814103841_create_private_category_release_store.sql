
create schema if not exists fitmatch_catalog;
create schema if not exists fitmatch_qa;

revoke all on schema fitmatch_catalog from public, anon, authenticated;
revoke all on schema fitmatch_qa from public, anon, authenticated;
grant usage on schema fitmatch_catalog to service_role;
grant usage on schema fitmatch_qa to service_role;

create table fitmatch_catalog.releases (
  id uuid primary key default gen_random_uuid(),
  release_key text not null unique,
  taxonomy_version text not null,
  policy_version text not null,
  status text not null default 'loading'
    check (status in ('loading','validated','active','failed','retired')),
  bundle_checksum text not null check (bundle_checksum ~ '^[0-9a-f]{64}$'),
  app_taxonomy_checksum text not null check (app_taxonomy_checksum ~ '^[0-9a-f]{64}$'),
  expected_mapping_count integer not null check (expected_mapping_count >= 0),
  expected_qa_count integer not null check (expected_qa_count >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  validated_at timestamptz,
  activated_at timestamptz
);

create unique index releases_one_active_idx
  on fitmatch_catalog.releases ((status))
  where status = 'active';

create table fitmatch_catalog.documents (
  release_id uuid not null references fitmatch_catalog.releases(id) on delete cascade,
  document_type text not null
    check (document_type in ('manifest','app_taxonomy','comparison_policies','measurement_policies','source_mapping_metadata')),
  file_name text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  byte_count bigint not null check (byte_count >= 0),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (release_id, document_type)
);

create table fitmatch_catalog.source_category_mappings (
  release_id uuid not null references fitmatch_catalog.releases(id) on delete cascade,
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

create index source_mapping_external_idx
  on fitmatch_catalog.source_category_mappings
  (release_id, source, external_category_id, target);
create index source_mapping_path_idx
  on fitmatch_catalog.source_category_mappings
  (release_id, source, normalized_path);
create index source_mapping_status_idx
  on fitmatch_catalog.source_category_mappings
  (release_id, decision_status, runtime_lookup_eligible);
create index source_mapping_family_idx
  on fitmatch_catalog.source_category_mappings
  (release_id, comparison_family)
  where comparison_family is not null;

create table fitmatch_qa.classification_cases (
  release_id uuid not null references fitmatch_catalog.releases(id) on delete cascade,
  case_key text not null,
  source text not null,
  product_id text not null,
  product_name text,
  product_url text,
  requires_user_confirmation boolean not null,
  expected_category_code text,
  expected_detail_code text,
  expected_comparison_family text,
  expected_length_type text,
  input_payload jsonb not null,
  result_payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (release_id, case_key),
  unique (release_id, source, product_id)
);

create index classification_cases_outcome_idx
  on fitmatch_qa.classification_cases
  (release_id, requires_user_confirmation, expected_category_code, expected_detail_code);

create table fitmatch_qa.validation_runs (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references fitmatch_catalog.releases(id) on delete cascade,
  validator_version text not null,
  status text not null check (status in ('running','passed','failed')),
  mapping_count integer,
  qa_count integer,
  error_count integer not null default 0,
  result jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

alter table fitmatch_catalog.releases enable row level security;
alter table fitmatch_catalog.documents enable row level security;
alter table fitmatch_catalog.source_category_mappings enable row level security;
alter table fitmatch_qa.classification_cases enable row level security;
alter table fitmatch_qa.validation_runs enable row level security;

revoke all on all tables in schema fitmatch_catalog from public, anon, authenticated;
revoke all on all tables in schema fitmatch_qa from public, anon, authenticated;
grant all on all tables in schema fitmatch_catalog to service_role;
grant all on all tables in schema fitmatch_qa to service_role;

alter default privileges in schema fitmatch_catalog revoke all on tables from public, anon, authenticated;
alter default privileges in schema fitmatch_qa revoke all on tables from public, anon, authenticated;
alter default privileges in schema fitmatch_catalog grant all on tables to service_role;
alter default privileges in schema fitmatch_qa grant all on tables to service_role;
;
