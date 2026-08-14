begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-classification-rule-parity'));

create table if not exists fitmatch_taxonomy.runtime_rule_sets (
  code text primary key,
  base_policy_version text not null references fitmatch_taxonomy.policy_versions(code),
  schema_version text not null,
  evaluator_version text not null,
  source_checksums jsonb not null,
  execution_semantics jsonb not null,
  status text not null check (status in ('loading', 'validated', 'active', 'retired', 'failed')),
  created_at timestamptz not null default now(),
  validated_at timestamptz
);

create table if not exists fitmatch_taxonomy.runtime_classification_rules (
  id uuid primary key default gen_random_uuid(),
  rule_set_code text not null references fitmatch_taxonomy.runtime_rule_sets(code) on delete restrict,
  stage text not null check (stage in ('provider_major', 'special_category', 'detail', 'normalized_type', 'family', 'length')),
  source_code text not null check (source_code in ('any', 'musinsa', 'uniqlo')),
  priority integer not null check (priority >= 0),
  input_scope text not null check (input_scope in ('specific_source', 'source_path', 'product_name', 'combined', 'detail_code', 'category_code')),
  required_category_code text,
  match_operator text not null check (match_operator in ('contains_any', 'exact_any', 'always')),
  include_terms text[] not null default '{}',
  exclude_terms text[] not null default '{}',
  output_category_code text,
  output_detail_code text,
  output_normalized_type_code text,
  output_family_code text,
  output_length_code text,
  source_file text not null,
  source_anchor text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (rule_set_code, stage, source_code, priority)
);

create index if not exists runtime_classification_rules_lookup_idx
  on fitmatch_taxonomy.runtime_classification_rules
  (rule_set_code, stage, source_code, priority)
  where active;

create table if not exists fitmatch_staging.runtime_classification_regression_cases (
  id uuid primary key default gen_random_uuid(),
  rule_set_code text not null references fitmatch_taxonomy.runtime_rule_sets(code) on delete restrict,
  corpus_key text not null,
  source_code text not null check (source_code in ('musinsa', 'uniqlo')),
  external_product_id text not null,
  product_name text not null,
  source_category_path text not null,
  expected_category_code text not null,
  expected_detail_code text not null,
  expected_comparable boolean not null,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (rule_set_code, source_code, external_product_id)
);

create index if not exists runtime_regression_cases_corpus_idx
  on fitmatch_staging.runtime_classification_regression_cases
  (rule_set_code, corpus_key);

create table if not exists fitmatch_staging.runtime_classification_parity_runs (
  id uuid primary key default gen_random_uuid(),
  rule_set_code text not null references fitmatch_taxonomy.runtime_rule_sets(code) on delete restrict,
  corpus_count integer not null check (corpus_count >= 0),
  matched_count integer not null check (matched_count >= 0),
  mismatch_count integer not null check (mismatch_count >= 0),
  unmatched_count integer not null check (unmatched_count >= 0),
  result_checksum text not null,
  details jsonb not null default '{}',
  passed boolean not null,
  validated_at timestamptz not null default now(),
  check (matched_count + mismatch_count + unmatched_count = corpus_count),
  check (passed = (mismatch_count = 0 and unmatched_count = 0))
);

alter table fitmatch_taxonomy.runtime_rule_sets enable row level security;
alter table fitmatch_taxonomy.runtime_classification_rules enable row level security;
alter table fitmatch_staging.runtime_classification_regression_cases enable row level security;
alter table fitmatch_staging.runtime_classification_parity_runs enable row level security;

revoke all on fitmatch_taxonomy.runtime_rule_sets from anon, authenticated;
revoke all on fitmatch_taxonomy.runtime_classification_rules from anon, authenticated;
revoke all on fitmatch_staging.runtime_classification_regression_cases from anon, authenticated;
revoke all on fitmatch_staging.runtime_classification_parity_runs from anon, authenticated;

commit;
