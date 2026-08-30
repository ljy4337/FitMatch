
create table fitmatch_catalog.app_categories (
  release_id uuid not null references fitmatch_catalog.releases(id) on delete restrict,
  code text not null,
  display_name text not null,
  sort_order integer not null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  primary key (release_id, code)
);

create table fitmatch_catalog.app_category_details (
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

create index app_category_details_code_idx
  on fitmatch_catalog.app_category_details(release_id, code);

alter table fitmatch_catalog.app_categories enable row level security;
alter table fitmatch_catalog.app_category_details enable row level security;
revoke all on fitmatch_catalog.app_categories from public, anon, authenticated;
revoke all on fitmatch_catalog.app_category_details from public, anon, authenticated;
grant all on fitmatch_catalog.app_categories to service_role;
grant all on fitmatch_catalog.app_category_details to service_role;
;
