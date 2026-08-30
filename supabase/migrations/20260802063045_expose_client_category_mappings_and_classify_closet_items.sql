
create table public.client_source_category_mappings (
  source_category_id uuid primary key
    references public.source_categories(id) on delete cascade,
  garment_type_id uuid
    references public.garment_types(id) on delete set null,
  default_sleeve_class_code text
    references public.comparison_length_classes(code) on delete set null,
  default_pants_length_code text
    references public.comparison_length_classes(code) on delete set null,
  default_body_length_code text
    references public.comparison_length_classes(code) on delete set null,
  mapping_status text not null
    check (mapping_status in ('confirmed', 'review_required', 'rejected')),
  policy_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.client_source_category_mappings is
  'Sanitized read-only category mappings for FitMatch clients. Administrative evidence remains in source_category_mappings.';

insert into public.client_source_category_mappings (
  source_category_id,
  garment_type_id,
  default_sleeve_class_code,
  default_pants_length_code,
  default_body_length_code,
  mapping_status,
  policy_version,
  created_at,
  updated_at
)
select
  source_category_id,
  garment_type_id,
  default_sleeve_class_code,
  default_pants_length_code,
  default_body_length_code,
  mapping_status,
  policy_version,
  created_at,
  updated_at
from public.source_category_mappings;

alter table public.client_source_category_mappings enable row level security;

create policy client_source_category_mappings_public_read
on public.client_source_category_mappings
for select
to anon, authenticated
using (true);

revoke all on table public.client_source_category_mappings from anon, authenticated;
grant select on table public.client_source_category_mappings to anon, authenticated;

create index client_source_category_mappings_garment_type_idx
  on public.client_source_category_mappings(garment_type_id)
  where garment_type_id is not null;

create index client_source_category_mappings_sleeve_idx
  on public.client_source_category_mappings(default_sleeve_class_code)
  where default_sleeve_class_code is not null;

create index client_source_category_mappings_pants_length_idx
  on public.client_source_category_mappings(default_pants_length_code)
  where default_pants_length_code is not null;

create index client_source_category_mappings_body_length_idx
  on public.client_source_category_mappings(default_body_length_code)
  where default_body_length_code is not null;

alter table public.closet_items
  add column source_category_id uuid
    references public.source_categories(id) on delete set null,
  add column garment_type_id uuid
    references public.garment_types(id) on delete set null,
  add column sleeve_length_class_code text
    references public.comparison_length_classes(code) on delete set null,
  add column pants_length_class_code text
    references public.comparison_length_classes(code) on delete set null,
  add column body_length_class_code text
    references public.comparison_length_classes(code) on delete set null,
  add column classification_status text not null default 'unclassified'
    check (classification_status in ('confirmed', 'review_required', 'unclassified')),
  add column classification_source text
    check (
      classification_source is null
      or classification_source in (
        'source_category',
        'product_metadata',
        'measurement_inferred',
        'manual_override',
        'migrated_legacy'
      )
    ),
  add column comparison_policy_version text,
  add constraint closet_items_confirmed_classification_requires_type
    check (classification_status <> 'confirmed' or garment_type_id is not null);

create index closet_items_source_category_idx
  on public.closet_items(source_category_id)
  where source_category_id is not null and deleted_at is null;

create index closet_items_garment_type_idx
  on public.closet_items(user_id, garment_type_id)
  where garment_type_id is not null and deleted_at is null;

create index closet_items_classification_status_idx
  on public.closet_items(user_id, classification_status)
  where deleted_at is null;
;
