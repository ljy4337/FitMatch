-- Read-only post-migration verification.
-- Every row must report passed=true. The actual column contains the measured
-- value, and details explains what to inspect when a check fails.
with checks as (
    select
        10 as check_order,
        'category_counts'::text as check_name,
        (
            count(*) filter (where parent_id is null and depth = 0) = 11
            and count(*) filter (where parent_id is not null and depth = 1) = 69
            and count(*) = 80
        ) as passed,
        jsonb_build_object(
            'roots', count(*) filter (where parent_id is null and depth = 0),
            'details', count(*) filter (where parent_id is not null and depth = 1),
            'total', count(*)
        ) as actual,
        'Expected roots=11, details=69, total=80'::text as details
    from public.app_categories

    union all

    select
        20,
        'category_hierarchy',
        count(*) = 0,
        jsonb_build_object('invalid_rows', count(*)),
        'No root may have a parent; every detail must have a depth-0 parent'
    from public.app_categories child
    left join public.app_categories parent on parent.id = child.parent_id
    where
        (child.depth = 0 and child.parent_id is not null)
        or
        (child.depth = 1 and (
            child.parent_id is null
            or parent.id is null
            or parent.depth <> 0
            or parent.parent_id is not null
        ))
        or child.depth not in (0, 1)

    union all

    select
        30,
        'category_code_uniqueness',
        count(*) = 0,
        jsonb_build_object('duplicate_groups', count(*)),
        'Root code must be globally unique; detail code must be unique per parent'
    from (
        select code
        from public.app_categories
        where parent_id is null
        group by code
        having count(*) > 1

        union all

        select code
        from public.app_categories
        where parent_id is not null
        group by parent_id, code
        having count(*) > 1
    ) duplicates

    union all

    select
        40,
        'alias_counts',
        (
            count(*) filter (where alias_type = 'category') = 14
            and count(*) filter (where alias_type = 'detail_category') = 10
            and count(*) = 24
        ),
        jsonb_build_object(
            'category', count(*) filter (where alias_type = 'category'),
            'detail_category', count(*) filter (where alias_type = 'detail_category'),
            'total', count(*)
        ),
        'Expected FitMatch taxonomy aliases: category=14, detail_category=10, total=24'
    from public.category_aliases
    where source = 'fitmatch_taxonomy'

    union all

    select
        50,
        'alias_resolution_uniqueness',
        count(*) = 0,
        jsonb_build_object('conflicting_groups', count(*)),
        'An alias may resolve to only one target within alias_type/source/scope'
    from (
        select alias_type, source, scope, normalized_alias
        from public.category_aliases
        group by alias_type, source, scope, normalized_alias
        having count(*) > 1
            or count(distinct app_category_id) > 1
    ) conflicts

    union all

    select
        60,
        'alias_normalization',
        count(*) = 0,
        jsonb_build_object('invalid_rows', count(*)),
        'normalized_alias must equal lower(btrim(alias))'
    from public.category_aliases
    where normalized_alias <> lower(btrim(alias))

    union all

    select
        70,
        'source_categories_preserved',
        count(*) = 9,
        jsonb_build_object(
            'rows', count(*),
            'business_data_md5', md5(coalesce(
                string_agg(payload::text, '|' order by payload::text),
                ''
            ))
        ),
        'Expected rows=9; compare business_data_md5 with the pre-migration snapshot'
    from (
        select to_jsonb(sc) - 'app_category_id' as payload
        from public.source_categories sc
    ) source_snapshot

    union all

    select
        80,
        'source_categories_fk_integrity',
        count(*) = 0,
        jsonb_build_object('orphan_rows', count(*)),
        'Every non-null source_categories.app_category_id must reference app_categories'
    from public.source_categories sc
    left join public.app_categories ac on ac.id = sc.app_category_id
    where sc.app_category_id is not null
      and ac.id is null

    union all

    select
        90,
        'source_categories_fk_definition',
        count(*) = 1
            and bool_and(pg_get_constraintdef(oid) ilike '%ON DELETE SET NULL%'),
        jsonb_build_object(
            'matching_constraints', count(*),
            'definitions', coalesce(jsonb_agg(pg_get_constraintdef(oid)), '[]'::jsonb)
        ),
        'Expected exactly one source_categories_app_category_fk with ON DELETE SET NULL'
    from pg_constraint
    where conrelid = 'public.source_categories'::regclass
      and conname = 'source_categories_app_category_fk'

    union all

    select
        100,
        'required_indexes',
        count(*) = 3
            and count(*) filter (
                where indexname = 'app_categories_root_code_uidx'
                  and indexdef ilike '%WHERE (parent_id IS NULL)%'
            ) = 1
            and count(*) filter (
                where indexname = 'app_categories_child_code_uidx'
                  and indexdef ilike '%WHERE (parent_id IS NOT NULL)%'
            ) = 1
            and count(*) filter (
                where indexname = 'category_aliases_resolution_uidx'
            ) = 1,
        jsonb_build_object(
            'matching_indexes', count(*),
            'indexes', coalesce(jsonb_agg(indexname order by indexname), '[]'::jsonb)
        ),
        'Expected both partial category unique indexes and the alias resolution unique index'
    from pg_indexes
    where schemaname = 'public'
      and indexname in (
          'app_categories_root_code_uidx',
          'app_categories_child_code_uidx',
          'category_aliases_resolution_uidx'
      )
      and indexdef ilike '%UNIQUE INDEX%'

    union all

    select
        110,
        'rls_enabled',
        count(*) = 2 and bool_and(c.relrowsecurity),
        jsonb_build_object(
            'tables_found', count(*),
            'rls_enabled_count', count(*) filter (where c.relrowsecurity)
        ),
        'RLS must be enabled on app_categories and category_aliases'
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('app_categories', 'category_aliases')
      and c.relkind = 'r'

    union all

    select
        120,
        'select_policies',
        count(*) = 2
            and bool_and(cmd = 'SELECT')
            and bool_and(roles @> array['anon', 'authenticated']::name[])
            and bool_and(qual = 'true'),
        jsonb_build_object(
            'matching_policies', count(*),
            'policies', coalesce(jsonb_agg(
                jsonb_build_object(
                    'table', tablename,
                    'policy', policyname,
                    'command', cmd,
                    'roles', roles
                )
                order by tablename
            ), '[]'::jsonb)
        ),
        'Expected one SELECT policy for anon/authenticated on each table'
    from pg_policies
    where schemaname = 'public'
      and (
          (tablename = 'app_categories' and policyname = 'app_categories_public_read')
          or
          (tablename = 'category_aliases' and policyname = 'category_aliases_public_read')
      )

    union all

    select
        130,
        'table_grants',
        count(*) = 4
            and bool_and(can_select and not can_insert and not can_update and not can_delete),
        jsonb_build_object(
            'role_table_pairs', count(*),
            'invalid_pairs', count(*) filter (
                where not can_select or can_insert or can_update or can_delete
            )
        ),
        'anon/authenticated must have SELECT and no INSERT/UPDATE/DELETE table privilege'
    from (
        select
            role_name,
            table_name,
            has_table_privilege(role_name, format('public.%I', table_name), 'SELECT') as can_select,
            has_table_privilege(role_name, format('public.%I', table_name), 'INSERT') as can_insert,
            has_table_privilege(role_name, format('public.%I', table_name), 'UPDATE') as can_update,
            has_table_privilege(role_name, format('public.%I', table_name), 'DELETE') as can_delete
        from
            (values ('anon'), ('authenticated')) roles(role_name)
        cross join
            (values ('app_categories'), ('category_aliases')) tables(table_name)
    ) privileges

    union all

    select
        140,
        'required_triggers',
        count(*) = 3 and bool_and(tgenabled <> 'D'),
        jsonb_build_object(
            'matching_triggers', count(*),
            'enabled_triggers', count(*) filter (where tgenabled <> 'D')
        ),
        'Expected three enabled triggers: two updated_at triggers and one hierarchy trigger'
    from pg_trigger
    where not tgisinternal
      and tgrelid in (
          'public.app_categories'::regclass,
          'public.category_aliases'::regclass
      )
      and tgname in (
          'app_categories_set_updated_at',
          'app_categories_validate_hierarchy',
          'category_aliases_set_updated_at'
      )
)
select
    check_name,
    passed,
    actual,
    details
from checks
order by check_order;

-- Failure details: all five queries below must return zero rows.

select child.id, child.code, child.depth, child.parent_id
from public.app_categories child
left join public.app_categories parent on parent.id = child.parent_id
where
    (child.depth = 0 and child.parent_id is not null)
    or
    (child.depth = 1 and (
        child.parent_id is null
        or parent.id is null
        or parent.depth <> 0
        or parent.parent_id is not null
    ))
    or child.depth not in (0, 1);

select 'root' as category_level, null::uuid as parent_id, code, count(*) as duplicate_count
from public.app_categories
where parent_id is null
group by code
having count(*) > 1
union all
select 'detail', parent_id, code, count(*)
from public.app_categories
where parent_id is not null
group by parent_id, code
having count(*) > 1;

select
    alias_type,
    source,
    scope,
    normalized_alias,
    array_agg(distinct app_category_id) as targets,
    count(*) as duplicate_count
from public.category_aliases
group by alias_type, source, scope, normalized_alias
having count(*) > 1
    or count(distinct app_category_id) > 1;

select sc.*
from public.source_categories sc
left join public.app_categories ac on ac.id = sc.app_category_id
where sc.app_category_id is not null
  and ac.id is null;

select *
from public.category_aliases
where normalized_alias <> lower(btrim(alias));
