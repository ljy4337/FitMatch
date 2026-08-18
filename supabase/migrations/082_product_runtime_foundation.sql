begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-foundation-v1'));

-- Shared retailer product identity. Existing collection snapshots remain the
-- immutable observation log; this table is the current operational identity.
create table if not exists fitmatch_catalog.products (
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
  constraint products_source_format_check
    check (source ~ '^[a-z][a-z0-9_]*$'),
  constraint products_external_id_not_blank_check
    check (btrim(external_product_id) <> ''),
  constraint products_product_name_not_blank_check
    check (btrim(product_name) <> ''),
  constraint products_raw_payload_object_check
    check (jsonb_typeof(raw_payload) = 'object'),
  constraint products_lifecycle_status_check
    check (lifecycle_status in ('active','unavailable','unknown')),
  constraint products_source_external_unique
    unique (source, external_product_id)
);

create index if not exists products_source_updated_idx
  on fitmatch_catalog.products (source, updated_at desc);
create index if not exists products_fingerprint_idx
  on fitmatch_catalog.products (source, input_fingerprint);

alter table fitmatch_catalog.source_product_snapshots
  add column if not exists product_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'source_product_snapshots_product_id_fkey'
      and conrelid = 'fitmatch_catalog.source_product_snapshots'::regclass
  ) then
    alter table fitmatch_catalog.source_product_snapshots
      add constraint source_product_snapshots_product_id_fkey
      foreign key (product_id)
      references fitmatch_catalog.products(id)
      on delete restrict;
  end if;
end $$;

create index if not exists source_product_snapshots_product_id_idx
  on fitmatch_catalog.source_product_snapshots (product_id, collected_at desc)
  where product_id is not null;

-- Every classification change is auditable. Only one row per product may be
-- current, but old decisions remain immutable history.
create table if not exists fitmatch_catalog.product_classification_history (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null
    references fitmatch_catalog.products(id) on delete cascade,
  input_fingerprint text not null,
  category_code text,
  detail_code text,
  comparison_family_code text,
  length_code text,
  classification_status text not null,
  classification_method text not null,
  confidence numeric(5,4),
  requires_user_confirmation boolean not null default false,
  taxonomy_policy_version text,
  mapping_release_id uuid
    references fitmatch_catalog.releases(id) on delete set null,
  decision_version text not null,
  evidence jsonb not null default '{}',
  is_current boolean not null default true,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint product_classification_history_status_check
    check (classification_status in (
      'confirmed','review_required','not_comparable','unclassified'
    )),
  constraint product_classification_history_method_check
    check (classification_method in (
      'canonical_product_decision','category_mapping','product_classifier',
      'manual_review','user_override','migration','unknown'
    )),
  constraint product_classification_history_confidence_check
    check (confidence is null or (confidence >= 0 and confidence <= 1)),
  constraint product_classification_history_evidence_object_check
    check (jsonb_typeof(evidence) = 'object'),
  constraint product_classification_history_confirmed_values_check
    check (
      classification_status <> 'confirmed'
      or (
        category_code is not null
        and detail_code is not null
        and not requires_user_confirmation
      )
    )
);

create unique index if not exists product_classification_one_current_idx
  on fitmatch_catalog.product_classification_history (product_id)
  where is_current;
create index if not exists product_classification_lookup_idx
  on fitmatch_catalog.product_classification_history
    (product_id, input_fingerprint, is_current);
create index if not exists product_classification_status_idx
  on fitmatch_catalog.product_classification_history
    (classification_status, created_at desc);

create table if not exists fitmatch_catalog.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null
    references fitmatch_catalog.products(id) on delete cascade,
  external_variant_id text not null,
  variant_name text,
  color_code text,
  color_name text,
  sku text,
  raw_payload jsonb not null default '{}',
  input_fingerprint text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_variants_external_id_not_blank_check
    check (btrim(external_variant_id) <> ''),
  constraint product_variants_raw_payload_object_check
    check (jsonb_typeof(raw_payload) = 'object'),
  constraint product_variants_product_external_unique
    unique (product_id, external_variant_id)
);

create index if not exists product_variants_product_idx
  on fitmatch_catalog.product_variants (product_id, is_active);

create table if not exists fitmatch_catalog.product_sizes (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null
    references fitmatch_catalog.product_variants(id) on delete cascade,
  size_identity text not null,
  external_size_id text,
  size_label text not null,
  normalized_size_label text,
  display_order integer,
  stock_status text not null default 'unknown',
  raw_payload jsonb not null default '{}',
  input_fingerprint text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_sizes_identity_not_blank_check
    check (btrim(size_identity) <> ''),
  constraint product_sizes_label_not_blank_check
    check (btrim(size_label) <> ''),
  constraint product_sizes_display_order_check
    check (display_order is null or display_order >= 0),
  constraint product_sizes_stock_status_check
    check (stock_status in ('in_stock','out_of_stock','unknown')),
  constraint product_sizes_raw_payload_object_check
    check (jsonb_typeof(raw_payload) = 'object'),
  constraint product_sizes_variant_identity_unique
    unique (variant_id, size_identity)
);

create index if not exists product_sizes_variant_idx
  on fitmatch_catalog.product_sizes (variant_id, is_active, display_order);

create table if not exists fitmatch_catalog.product_measurements (
  id uuid primary key default gen_random_uuid(),
  product_size_id uuid not null
    references fitmatch_catalog.product_sizes(id) on delete cascade,
  measurement_identity text not null,
  measurement_code text,
  raw_code text,
  raw_label text not null,
  raw_value numeric not null,
  raw_unit text not null default 'cm',
  raw_representation text,
  normalized_value numeric,
  normalized_unit text,
  comparison_basis text,
  conversion_multiplier numeric,
  is_comparable boolean not null default false,
  exclusion_reason text,
  source_alias_id uuid,
  policy_version text,
  evidence jsonb not null default '{}',
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_measurements_identity_not_blank_check
    check (btrim(measurement_identity) <> ''),
  constraint product_measurements_raw_label_not_blank_check
    check (btrim(raw_label) <> ''),
  constraint product_measurements_raw_value_check
    check (raw_value > 0),
  constraint product_measurements_normalized_value_check
    check (normalized_value is null or normalized_value > 0),
  constraint product_measurements_evidence_object_check
    check (jsonb_typeof(evidence) = 'object'),
  constraint product_measurements_comparable_value_check
    check (not is_comparable or (
      measurement_code is not null and normalized_value is not null
    )),
  constraint product_measurements_size_identity_unique
    unique (product_size_id, measurement_identity)
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'product_measurements_source_alias_id_fkey'
      and conrelid = 'fitmatch_catalog.product_measurements'::regclass
  ) then
    alter table fitmatch_catalog.product_measurements
      add constraint product_measurements_source_alias_id_fkey
      foreign key (source_alias_id)
      references fitmatch_taxonomy.source_measurement_aliases(id)
      on delete set null;
  end if;
end $$;

create index if not exists product_measurements_size_idx
  on fitmatch_catalog.product_measurements
    (product_size_id, is_comparable, measurement_code);
create index if not exists product_measurements_code_idx
  on fitmatch_catalog.product_measurements (measurement_code)
  where measurement_code is not null;

-- Untrusted app payloads never mutate the shared catalog directly. A client
-- can request intake; a trusted batch/Edge Function validates and promotes it.
create table if not exists public.product_intake_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null,
  external_product_id text not null,
  input_fingerprint text not null,
  submitted_payload jsonb not null,
  status text not null default 'pending',
  resolved_product_id uuid
    references fitmatch_catalog.products(id) on delete set null,
  resolution jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint product_intake_requests_source_check
    check (source ~ '^[a-z][a-z0-9_]*$'),
  constraint product_intake_requests_external_id_check
    check (btrim(external_product_id) <> ''),
  constraint product_intake_requests_payload_object_check
    check (jsonb_typeof(submitted_payload) = 'object'),
  constraint product_intake_requests_resolution_object_check
    check (jsonb_typeof(resolution) = 'object'),
  constraint product_intake_requests_status_check
    check (status in ('pending','processing','resolved','rejected')),
  constraint product_intake_requests_user_fingerprint_unique
    unique (user_id, source, external_product_id, input_fingerprint)
);

create index if not exists product_intake_requests_user_recent_idx
  on public.product_intake_requests (user_id, created_at desc);
create index if not exists product_intake_requests_pending_idx
  on public.product_intake_requests (status, created_at)
  where status in ('pending','processing');

-- Link the existing user model to shared product facts without removing its
-- legacy snapshot columns. This keeps the current app backward compatible.
alter table public.closet_items
  add column if not exists product_id uuid,
  add column if not exists variant_id uuid,
  add column if not exists product_size_id uuid,
  add column if not exists canonical_classification_id uuid,
  add column if not exists canonical_category_code text,
  add column if not exists canonical_detail_code text,
  add column if not exists comparison_family_code text,
  add column if not exists comparison_length_code text,
  add column if not exists classification_snapshot jsonb not null default '{}';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_product_id_fkey'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items add constraint closet_items_product_id_fkey
      foreign key (product_id) references fitmatch_catalog.products(id)
      on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_variant_id_fkey'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items add constraint closet_items_variant_id_fkey
      foreign key (variant_id) references fitmatch_catalog.product_variants(id)
      on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_product_size_id_fkey'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items add constraint closet_items_product_size_id_fkey
      foreign key (product_size_id) references fitmatch_catalog.product_sizes(id)
      on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_canonical_classification_id_fkey'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_canonical_classification_id_fkey
      foreign key (canonical_classification_id)
      references fitmatch_catalog.product_classification_history(id)
      on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_classification_snapshot_object_check'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_classification_snapshot_object_check
      check (jsonb_typeof(classification_snapshot) = 'object');
  end if;
end $$;

alter table public.closet_items
  drop constraint if exists closet_items_confirmed_classification_requires_type;
alter table public.closet_items
  add constraint closet_items_confirmed_classification_requires_type
  check (
    classification_status <> 'confirmed'
    or garment_type_id is not null
    or canonical_classification_id is not null
  ) not valid;
alter table public.closet_items
  validate constraint closet_items_confirmed_classification_requires_type;

create index if not exists closet_items_product_idx
  on public.closet_items (user_id, product_id)
  where product_id is not null and deleted_at is null;
create index if not exists closet_items_product_size_idx
  on public.closet_items (product_size_id)
  where product_size_id is not null;
create index if not exists closet_items_canonical_classification_idx
  on public.closet_items (canonical_classification_id)
  where canonical_classification_id is not null;

create table if not exists public.closet_item_classification_overrides (
  id uuid primary key default gen_random_uuid(),
  closet_item_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  category_code text not null,
  detail_code text not null,
  comparison_family_code text,
  length_code text,
  reason text,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint closet_item_overrides_item_user_unique
    unique (closet_item_id, user_id),
  constraint closet_item_overrides_evidence_object_check
    check (jsonb_typeof(evidence) = 'object'),
  constraint closet_item_overrides_item_owner_fkey
    foreign key (closet_item_id, user_id)
    references public.closet_items(id, user_id)
    on delete cascade
);

create index if not exists closet_item_overrides_user_idx
  on public.closet_item_classification_overrides (user_id, updated_at desc);

create table if not exists public.comparison_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reference_item_id uuid not null,
  target_product_id uuid not null
    references fitmatch_catalog.products(id) on delete restrict,
  target_variant_id uuid
    references fitmatch_catalog.product_variants(id) on delete set null,
  status text not null default 'pending',
  comparison_level text,
  block_reason text,
  taxonomy_policy_version text,
  comparison_policy_version text,
  measurement_policy_version text,
  input_snapshot jsonb not null default '{}',
  result_summary jsonb not null default '{}',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint comparison_runs_id_user_unique unique (id, user_id),
  constraint comparison_runs_reference_owner_fkey
    foreign key (reference_item_id, user_id)
    references public.closet_items(id, user_id)
    on delete restrict,
  constraint comparison_runs_status_check
    check (status in ('pending','completed','blocked','failed')),
  constraint comparison_runs_level_check
    check (comparison_level is null or comparison_level in (
      'direct','extended','incompatible','insufficient_data'
    )),
  constraint comparison_runs_input_object_check
    check (jsonb_typeof(input_snapshot) = 'object'),
  constraint comparison_runs_result_object_check
    check (jsonb_typeof(result_summary) = 'object')
);

create index if not exists comparison_runs_user_recent_idx
  on public.comparison_runs (user_id, created_at desc);
create index if not exists comparison_runs_reference_idx
  on public.comparison_runs (reference_item_id, user_id);
create index if not exists comparison_runs_target_product_idx
  on public.comparison_runs (target_product_id, created_at desc);

create table if not exists public.comparison_results (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  target_size_id uuid
    references fitmatch_catalog.product_sizes(id) on delete set null,
  similarity_score numeric(7,4),
  rank integer,
  confidence_code text,
  is_recommended boolean not null default false,
  is_comparable boolean not null default false,
  exclusion_reason text,
  result_snapshot jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint comparison_results_id_user_unique unique (id, user_id),
  constraint comparison_results_run_owner_fkey
    foreign key (run_id, user_id)
    references public.comparison_runs(id, user_id)
    on delete cascade,
  constraint comparison_results_run_size_unique
    unique (run_id, target_size_id),
  constraint comparison_results_score_check
    check (similarity_score is null or (
      similarity_score >= 0 and similarity_score <= 100
    )),
  constraint comparison_results_rank_check
    check (rank is null or rank > 0),
  constraint comparison_results_snapshot_object_check
    check (jsonb_typeof(result_snapshot) = 'object')
);

create index if not exists comparison_results_run_rank_idx
  on public.comparison_results (run_id, rank);
create index if not exists comparison_results_user_idx
  on public.comparison_results (user_id, created_at desc);

create table if not exists public.comparison_measurement_results (
  id uuid primary key default gen_random_uuid(),
  result_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  measurement_code text not null,
  reference_value numeric,
  target_value numeric,
  signed_difference numeric,
  absolute_difference numeric,
  weight numeric,
  included boolean not null default true,
  exclusion_reason text,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint comparison_measurement_result_owner_fkey
    foreign key (result_id, user_id)
    references public.comparison_results(id, user_id)
    on delete cascade,
  constraint comparison_measurement_result_unique
    unique (result_id, measurement_code),
  constraint comparison_measurement_weight_check
    check (weight is null or weight >= 0),
  constraint comparison_measurement_abs_check
    check (absolute_difference is null or absolute_difference >= 0),
  constraint comparison_measurement_evidence_object_check
    check (jsonb_typeof(evidence) = 'object')
);

create index if not exists comparison_measurement_results_result_idx
  on public.comparison_measurement_results (result_id, included);
create index if not exists comparison_measurement_results_user_idx
  on public.comparison_measurement_results (user_id, created_at desc);

alter table public.comparison_history
  add column if not exists comparison_run_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'comparison_history_comparison_run_id_fkey'
      and conrelid = 'public.comparison_history'::regclass
  ) then
    alter table public.comparison_history
      add constraint comparison_history_comparison_run_id_fkey
      foreign key (comparison_run_id)
      references public.comparison_runs(id)
      on delete set null;
  end if;
end $$;

create index if not exists comparison_history_run_idx
  on public.comparison_history (comparison_run_id)
  where comparison_run_id is not null;

-- Private shared data is backend-only. Public user data is protected by RLS.
alter table fitmatch_catalog.products enable row level security;
alter table fitmatch_catalog.product_classification_history enable row level security;
alter table fitmatch_catalog.product_variants enable row level security;
alter table fitmatch_catalog.product_sizes enable row level security;
alter table fitmatch_catalog.product_measurements enable row level security;

revoke all on fitmatch_catalog.products from public, anon, authenticated;
revoke all on fitmatch_catalog.product_classification_history from public, anon, authenticated;
revoke all on fitmatch_catalog.product_variants from public, anon, authenticated;
revoke all on fitmatch_catalog.product_sizes from public, anon, authenticated;
revoke all on fitmatch_catalog.product_measurements from public, anon, authenticated;

grant select, insert, update on fitmatch_catalog.products to service_role;
grant select, insert, update on fitmatch_catalog.product_classification_history to service_role;
grant select, insert, update on fitmatch_catalog.product_variants to service_role;
grant select, insert, update on fitmatch_catalog.product_sizes to service_role;
grant select, insert, update on fitmatch_catalog.product_measurements to service_role;

alter table public.closet_item_classification_overrides enable row level security;
alter table public.product_intake_requests enable row level security;
alter table public.comparison_runs enable row level security;
alter table public.comparison_results enable row level security;
alter table public.comparison_measurement_results enable row level security;

drop policy if exists closet_item_overrides_select_own
  on public.closet_item_classification_overrides;
create policy closet_item_overrides_select_own
  on public.closet_item_classification_overrides for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists product_intake_requests_select_own
  on public.product_intake_requests;
create policy product_intake_requests_select_own
  on public.product_intake_requests for select
  to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists closet_item_overrides_insert_own
  on public.closet_item_classification_overrides;
create policy closet_item_overrides_insert_own
  on public.closet_item_classification_overrides for insert
  to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists closet_item_overrides_update_own
  on public.closet_item_classification_overrides;
create policy closet_item_overrides_update_own
  on public.closet_item_classification_overrides for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists closet_item_overrides_delete_own
  on public.closet_item_classification_overrides;
create policy closet_item_overrides_delete_own
  on public.closet_item_classification_overrides for delete
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists comparison_runs_select_own on public.comparison_runs;
create policy comparison_runs_select_own
  on public.comparison_runs for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists comparison_runs_insert_own on public.comparison_runs;
create policy comparison_runs_insert_own
  on public.comparison_runs for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists comparison_runs_update_own on public.comparison_runs;
create policy comparison_runs_update_own
  on public.comparison_runs for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists comparison_runs_delete_own on public.comparison_runs;
create policy comparison_runs_delete_own
  on public.comparison_runs for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists comparison_results_select_own on public.comparison_results;
create policy comparison_results_select_own
  on public.comparison_results for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists comparison_measurement_results_select_own
  on public.comparison_measurement_results;
create policy comparison_measurement_results_select_own
  on public.comparison_measurement_results for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.closet_item_classification_overrides
  from public, anon, authenticated;
revoke all on public.product_intake_requests
  from public, anon, authenticated;
revoke all on public.comparison_runs
  from public, anon, authenticated;
revoke all on public.comparison_results
  from public, anon, authenticated;
revoke all on public.comparison_measurement_results
  from public, anon, authenticated;

grant select on public.closet_item_classification_overrides to authenticated;
grant select on public.product_intake_requests to authenticated;
grant select, insert, update on public.product_intake_requests to service_role;
grant select on public.comparison_runs to authenticated;
grant select on public.comparison_results to authenticated;
grant select on public.comparison_measurement_results to authenticated;

-- Backfill shared products from the newest observation of every product.
insert into fitmatch_catalog.products (
  source, external_product_id, product_name, canonical_url, audience,
  source_category_path, source_category_codes, image_url, raw_payload,
  input_fingerprint, first_seen_at, last_seen_at
)
select distinct on (s.source, s.external_product_id)
  s.source,
  s.external_product_id,
  s.product_name,
  s.canonical_url,
  s.audience,
  s.source_category_path,
  s.source_category_codes,
  s.image_url,
  s.raw_summary,
  md5(lower(btrim(s.product_name)) || E'\n' ||
      lower(btrim(coalesce(s.source_category_path,'')))),
  min(s.collected_at) over (
    partition by s.source, s.external_product_id
  ),
  max(s.collected_at) over (
    partition by s.source, s.external_product_id
  )
from fitmatch_catalog.source_product_snapshots s
order by s.source, s.external_product_id, s.collected_at desc
on conflict (source, external_product_id) do update set
  product_name = excluded.product_name,
  canonical_url = excluded.canonical_url,
  audience = excluded.audience,
  source_category_path = excluded.source_category_path,
  source_category_codes = excluded.source_category_codes,
  image_url = excluded.image_url,
  raw_payload = excluded.raw_payload,
  input_fingerprint = excluded.input_fingerprint,
  first_seen_at = least(fitmatch_catalog.products.first_seen_at, excluded.first_seen_at),
  last_seen_at = greatest(fitmatch_catalog.products.last_seen_at, excluded.last_seen_at),
  updated_at = now();

update fitmatch_catalog.source_product_snapshots s
set product_id = p.id
from fitmatch_catalog.products p
where s.product_id is null
  and p.source = s.source
  and p.external_product_id = s.external_product_id;

insert into fitmatch_catalog.product_variants (
  product_id, external_variant_id, variant_name, raw_payload
)
select p.id, '__default__', '기본 옵션', '{}'::jsonb
from fitmatch_catalog.products p
on conflict (product_id, external_variant_id) do nothing;

-- Seed current classification history only where a product observation exists.
insert into fitmatch_catalog.product_classification_history (
  product_id, input_fingerprint, category_code, detail_code,
  comparison_family_code, length_code, classification_status,
  classification_method, confidence, requires_user_confirmation,
  mapping_release_id, decision_version, evidence
)
select
  p.id,
  d.input_fingerprint,
  d.category_code,
  d.detail_code,
  d.comparison_family,
  d.length_type,
  case
    when d.requires_user_confirmation then 'review_required'
    when d.category_code is null or d.detail_code is null then 'unclassified'
    when d.category_code = 'other' or d.detail_code = 'other' then 'review_required'
    else 'confirmed'
  end,
  'canonical_product_decision',
  null,
  d.requires_user_confirmation,
  d.release_id,
  d.decision_version,
  d.evidence || jsonb_build_object('backfill','082_product_runtime_foundation')
from fitmatch_catalog.product_classification_decisions d
join fitmatch_catalog.products p
  on p.source = d.source
 and p.external_product_id = d.external_product_id
where not exists (
  select 1
  from fitmatch_catalog.product_classification_history h
  where h.product_id = p.id and h.is_current
);

do $$
declare
  v_snapshot_products integer;
  v_linked_snapshots integer;
begin
  select count(distinct (source, external_product_id))
    into v_snapshot_products
  from fitmatch_catalog.source_product_snapshots;

  if (select count(*) from fitmatch_catalog.products) < v_snapshot_products then
    raise exception 'product backfill incomplete';
  end if;

  select count(*) into v_linked_snapshots
  from fitmatch_catalog.source_product_snapshots
  where product_id is not null;

  if v_linked_snapshots <> (
    select count(*) from fitmatch_catalog.source_product_snapshots
  ) then
    raise exception 'snapshot product links incomplete';
  end if;

  if exists (
    select 1
    from fitmatch_catalog.product_classification_history
    where is_current
    group by product_id
    having count(*) > 1
  ) then
    raise exception 'multiple current product classifications detected';
  end if;
end $$;

commit;
