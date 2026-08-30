
create table fitmatch_catalog.product_collection_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('uniqlo','musinsa')),
  run_kind text not null default 'scheduled' check (run_kind in ('scheduled','manual','document_import')),
  status text not null default 'queued' check (status in ('queued','running','succeeded','partial','failed')),
  snapshot_date date not null,
  mapping_release_id uuid references fitmatch_catalog.releases(id) on delete restrict,
  expected_count integer check (expected_count is null or expected_count >= 0),
  discovered_count integer not null default 0 check (discovered_count >= 0),
  stored_count integer not null default 0 check (stored_count >= 0),
  failed_count integer not null default 0 check (failed_count >= 0),
  cursor jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  error_summary text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  check (finished_at is null or started_at is null or finished_at >= started_at)
);

create table fitmatch_catalog.source_product_snapshots (
  run_id uuid not null references fitmatch_catalog.product_collection_runs(id) on delete cascade,
  source text not null check (source in ('uniqlo','musinsa')),
  external_product_id text not null,
  product_name text not null,
  canonical_url text not null,
  audience text,
  observed_ids text[] not null default '{}'::text[],
  source_category_path text,
  source_category_codes text[] not null default '{}'::text[],
  fitmatch_category_label text,
  fitmatch_detail_label text,
  classification_status text not null check (classification_status in ('comparable','conditional','excluded_review','unclassified')),
  size_count integer check (size_count is null or size_count >= 0),
  image_url text,
  raw_summary jsonb not null default '{}'::jsonb,
  collected_at timestamptz not null default now(),
  primary key (run_id, external_product_id)
);

create index product_collection_runs_source_date_idx
  on fitmatch_catalog.product_collection_runs (source, snapshot_date desc, created_at desc);

create index source_product_snapshots_product_idx
  on fitmatch_catalog.source_product_snapshots (source, external_product_id, collected_at desc);

create index source_product_snapshots_category_idx
  on fitmatch_catalog.source_product_snapshots (run_id, fitmatch_category_label, fitmatch_detail_label);

alter table fitmatch_catalog.product_collection_runs enable row level security;
alter table fitmatch_catalog.source_product_snapshots enable row level security;

revoke all on fitmatch_catalog.product_collection_runs from anon, authenticated;
revoke all on fitmatch_catalog.source_product_snapshots from anon, authenticated;
grant select, insert, update, delete on fitmatch_catalog.product_collection_runs to service_role;
grant select, insert, update, delete on fitmatch_catalog.source_product_snapshots to service_role;

create view fitmatch_catalog.current_source_products
with (security_invoker = true)
as
select p.*
from fitmatch_catalog.source_product_snapshots p
join lateral (
  select r.id
  from fitmatch_catalog.product_collection_runs r
  where r.source = p.source and r.status in ('succeeded','partial')
  order by r.snapshot_date desc, r.created_at desc
  limit 1
) current_run on current_run.id = p.run_id;

revoke all on fitmatch_catalog.current_source_products from anon, authenticated;
grant select on fitmatch_catalog.current_source_products to service_role;
;
