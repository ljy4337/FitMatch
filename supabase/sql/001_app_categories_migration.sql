begin;

-- Supabase's supported PostgreSQL versions provide gen_random_uuid().
-- Deliberately avoid creating or taking ownership of a shared extension.
create table public.app_categories (
    id uuid primary key default gen_random_uuid(),
    parent_id uuid null,
    code text not null,
    display_name_ko text not null,
    depth smallint not null,
    sort_order integer not null default 0,
    is_active boolean not null default true,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint app_categories_parent_fk
        foreign key (parent_id)
        references public.app_categories(id)
        on delete restrict,
    constraint app_categories_code_not_blank
        check (btrim(code) <> ''),
    constraint app_categories_display_name_ko_not_blank
        check (btrim(display_name_ko) <> ''),
    constraint app_categories_depth_check
        check (
            (depth = 0 and parent_id is null)
            or
            (depth = 1 and parent_id is not null)
        ),
    constraint app_categories_metadata_object_check
        check (jsonb_typeof(metadata) = 'object')
);

comment on table public.app_categories is
    'Managed by FitMatch migration 001_app_categories_migration.sql';

-- PostgreSQL UNIQUE constraints treat NULL values as distinct. Separate partial
-- indexes therefore enforce uniqueness for roots and children correctly.
create unique index app_categories_root_code_uidx
    on public.app_categories (code)
    where parent_id is null;

create unique index app_categories_child_code_uidx
    on public.app_categories (parent_id, code)
    where parent_id is not null;

create index app_categories_parent_sort_idx
    on public.app_categories (parent_id, sort_order, code);

create index app_categories_active_idx
    on public.app_categories (depth, is_active, sort_order, code);

create function public.fitmatch_set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger app_categories_set_updated_at
before update on public.app_categories
for each row execute function public.fitmatch_set_updated_at();

create table public.category_aliases (
    id uuid primary key default gen_random_uuid(),
    app_category_id uuid not null,
    alias text not null,
    normalized_alias text not null,
    alias_type text not null,
    source text not null default 'fitmatch_taxonomy',
    scope text not null default 'global',
    is_active boolean not null default true,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint category_aliases_category_fk
        foreign key (app_category_id)
        references public.app_categories(id)
        on delete cascade,
    constraint category_aliases_alias_not_blank
        check (btrim(alias) <> ''),
    constraint category_aliases_normalized_alias_not_blank
        check (btrim(normalized_alias) <> ''),
    constraint category_aliases_normalization_check
        check (normalized_alias = lower(btrim(alias))),
    constraint category_aliases_alias_type_check
        check (alias_type in ('category', 'detail_category', 'legacy_raw_value', 'parser_legacy')),
    constraint category_aliases_source_not_blank
        check (btrim(source) <> ''),
    constraint category_aliases_scope_not_blank
        check (btrim(scope) <> ''),
    constraint category_aliases_metadata_object_check
        check (jsonb_typeof(metadata) = 'object')
);

comment on table public.category_aliases is
    'Managed by FitMatch migration 001_app_categories_migration.sql';

-- An alias can resolve to only one target within the same type/source/scope.
-- Detail aliases such as "7부" may legitimately repeat under different scopes.
create unique index category_aliases_resolution_uidx
    on public.category_aliases (alias_type, source, scope, normalized_alias);

create index category_aliases_category_idx
    on public.category_aliases (app_category_id, is_active);

create function public.fitmatch_validate_category_hierarchy()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
    parent_depth smallint;
begin
    if new.parent_id is null then
        if new.depth <> 0 then
            raise exception 'Root app category must have depth 0';
        end if;
        return new;
    end if;

    if new.id = new.parent_id then
        raise exception 'App category cannot be its own parent';
    end if;

    select depth
      into parent_depth
      from public.app_categories
     where id = new.parent_id;

    if parent_depth is distinct from 0 then
        raise exception 'Detail app category parent must be a root category';
    end if;

    if new.depth <> 1 then
        raise exception 'Detail app category must have depth 1';
    end if;

    return new;
end;
$$;

create trigger app_categories_validate_hierarchy
before insert or update of parent_id, depth on public.app_categories
for each row execute function public.fitmatch_validate_category_hierarchy();

create trigger category_aliases_set_updated_at
before update on public.category_aliases
for each row execute function public.fitmatch_set_updated_at();

-- This operation is additive. Existing source_categories rows and legacy text
-- columns are not updated or removed.
alter table public.source_categories
    add column app_category_id uuid null;

comment on column public.source_categories.app_category_id is
    'Managed by FitMatch migration 001_app_categories_migration.sql';

alter table public.source_categories
    add constraint source_categories_app_category_fk
    foreign key (app_category_id)
    references public.app_categories(id)
    on delete set null;

create index source_categories_app_category_idx
    on public.source_categories (app_category_id);

alter table public.app_categories enable row level security;
alter table public.category_aliases enable row level security;

create policy app_categories_public_read
on public.app_categories
for select
to anon, authenticated
using (true);

create policy category_aliases_public_read
on public.category_aliases
for select
to anon, authenticated
using (true);

revoke all on table public.app_categories from anon, authenticated;
revoke all on table public.category_aliases from anon, authenticated;
grant select on table public.app_categories to anon, authenticated;
grant select on table public.category_aliases to anon, authenticated;

commit;
