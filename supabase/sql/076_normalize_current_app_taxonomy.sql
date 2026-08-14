begin;

create table if not exists fitmatch_catalog.app_categories (
  release_id uuid not null references fitmatch_catalog.releases(id) on delete restrict,
  code text not null,
  display_name text not null,
  sort_order integer not null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  primary key (release_id, code)
);

create table if not exists fitmatch_catalog.app_category_details (
  release_id uuid not null,
  category_code text not null,
  code text not null,
  display_name text not null,
  sort_order integer not null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  primary key (release_id, category_code, code),
  foreign key (release_id, category_code)
    references fitmatch_catalog.app_categories(release_id, code) on delete restrict
);

create index if not exists app_category_details_code_idx
  on fitmatch_catalog.app_category_details(release_id, code);

alter table fitmatch_catalog.app_categories enable row level security;
alter table fitmatch_catalog.app_category_details enable row level security;
revoke all on fitmatch_catalog.app_categories from public, anon, authenticated;
revoke all on fitmatch_catalog.app_category_details from public, anon, authenticated;
grant all on fitmatch_catalog.app_categories to service_role;
grant all on fitmatch_catalog.app_category_details to service_role;

with doc as (
  select d.release_id, d.payload
  from fitmatch_catalog.documents d
  join fitmatch_catalog.releases r on r.id = d.release_id
  where d.document_type = 'app_taxonomy'
    and r.release_key = 'observed-official-2026-08-03__taxonomy-refined-2026-08-03'
)
insert into fitmatch_catalog.app_categories(release_id, code, display_name, sort_order, is_active)
select doc.release_id, c->>'code', c->>'displayName',
       (c->>'sortOrder')::integer, (c->>'isActive')::boolean
from doc cross join lateral jsonb_array_elements(doc.payload->'categories') c
on conflict (release_id, code) do update set
  display_name = excluded.display_name,
  sort_order = excluded.sort_order,
  is_active = excluded.is_active;

with doc as (
  select d.release_id, d.payload
  from fitmatch_catalog.documents d
  join fitmatch_catalog.releases r on r.id = d.release_id
  where d.document_type = 'app_taxonomy'
    and r.release_key = 'observed-official-2026-08-03__taxonomy-refined-2026-08-03'
)
insert into fitmatch_catalog.app_category_details
  (release_id, category_code, code, display_name, sort_order, is_active)
select doc.release_id, c->>'code', detail->>'code', detail->>'displayName',
       (detail->>'sortOrder')::integer, (detail->>'isActive')::boolean
from doc
cross join lateral jsonb_array_elements(doc.payload->'categories') c
cross join lateral jsonb_array_elements(c->'details') detail
on conflict (release_id, category_code, code) do update set
  display_name = excluded.display_name,
  sort_order = excluded.sort_order,
  is_active = excluded.is_active;

create or replace view fitmatch_catalog.source_to_fitmatch_mappings
with (security_invoker = true) as
select
  m.release_id, m.source_identity, m.source, m.snapshot_id,
  m.external_category_id, m.target, m.normalized_path,
  m.decision_status, m.runtime_lookup_eligible,
  case when m.decision_status = 'confirmed' then m.semantic_category_code end as app_category_code,
  null::text as app_detail_code,
  case when m.decision_status = 'confirmed' then m.semantic_garment_type end as semantic_garment_type,
  case when m.decision_status = 'confirmed' then m.comparison_family end as comparison_family,
  case
    when m.decision_status = 'confirmed' then 'product_classifier_required'
    when m.decision_status = 'review_required' then 'user_or_product_review_required'
    else 'not_applicable'
  end as detail_resolution_strategy,
  m.raw_record->'appMapping' as legacy_app_mapping
from fitmatch_catalog.source_category_mappings m;

revoke all on fitmatch_catalog.source_to_fitmatch_mappings from public, anon, authenticated;
grant select on fitmatch_catalog.source_to_fitmatch_mappings to service_role;

commit;
