-- Destructive rollback. Review dependencies before executing.
begin;

-- Refuse to delete same-named objects unless they carry this migration's
-- ownership markers.
do $$
declare
    app_categories_marker text;
    category_aliases_marker text;
    source_column_marker text;
begin
    select obj_description('public.app_categories'::regclass, 'pg_class')
      into app_categories_marker;
    select obj_description('public.category_aliases'::regclass, 'pg_class')
      into category_aliases_marker;
    select col_description(
        'public.source_categories'::regclass,
        (
            select attnum
            from pg_attribute
            where attrelid = 'public.source_categories'::regclass
              and attname = 'app_category_id'
              and not attisdropped
        )
    ) into source_column_marker;

    if app_categories_marker is distinct from 'Managed by FitMatch migration 001_app_categories_migration.sql'
       or category_aliases_marker is distinct from 'Managed by FitMatch migration 001_app_categories_migration.sql'
       or source_column_marker is distinct from 'Managed by FitMatch migration 001_app_categories_migration.sql' then
        raise exception 'Rollback ownership marker mismatch; no objects were removed';
    end if;
end;
$$;

alter table public.source_categories
    drop constraint if exists source_categories_app_category_fk;

drop index if exists public.source_categories_app_category_idx;

alter table public.source_categories
    drop column if exists app_category_id;

drop table if exists public.category_aliases;
drop table if exists public.app_categories;

drop function if exists public.fitmatch_validate_category_hierarchy();
drop function if exists public.fitmatch_set_updated_at();

commit;
