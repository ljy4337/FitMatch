-- FitMatch connectDB physical-device E2E read-only snapshot
-- 1. Replace only the first PASTE_TEST_USER_UUID below with the test user's UUID.
-- 2. Run before account deletion and save the single JSON result.
-- 3. Run again after account deletion with the same UUID.
-- This script performs SELECT only. It never inserts, updates, or deletes data.

with params as (
  select nullif(
    'PASTE_TEST_USER_UUID',
    'PASTE_TEST_USER_UUID'
  )::uuid as user_id
)
select jsonb_build_object(
  'checked_at', now(),
  'test_user_id', (select user_id from params),
  'target_configured', (select user_id is not null from params),
  'auth', jsonb_build_object(
    'user_exists', exists (
      select 1
      from auth.users u
      where u.id = (select user_id from params)
    ),
    'identity_count', (
      select count(*)
      from auth.identities i
      where i.user_id = (select user_id from params)
    ),
    'providers', coalesce((
      select jsonb_agg(i.provider order by i.provider)
      from auth.identities i
      where i.user_id = (select user_id from params)
    ), '[]'::jsonb),
    'session_count', (
      select count(*)
      from auth.sessions s
      where s.user_id = (select user_id from params)
    ),
    'last_sign_in_at', (
      select u.last_sign_in_at
      from auth.users u
      where u.id = (select user_id from params)
    )
  ),
  'user_owned_counts', jsonb_build_object(
    'profiles', (
      select count(*) from public.profiles
      where id = (select user_id from params)
    ),
    'user_settings', (
      select count(*) from public.user_settings
      where user_id = (select user_id from params)
    ),
    'active_closet_items', (
      select count(*) from public.closet_items
      where user_id = (select user_id from params)
        and deleted_at is null
    ),
    'soft_deleted_closet_items', (
      select count(*) from public.closet_items
      where user_id = (select user_id from params)
        and deleted_at is not null
    ),
    'closet_overrides', (
      select count(*) from public.closet_item_classification_overrides
      where user_id = (select user_id from params)
    ),
    'comparison_history', (
      select count(*) from public.comparison_history
      where user_id = (select user_id from params)
    ),
    'comparison_runs', (
      select count(*) from public.comparison_runs
      where user_id = (select user_id from params)
    ),
    'comparison_results', (
      select count(*) from public.comparison_results
      where user_id = (select user_id from params)
    ),
    'comparison_measurement_results', (
      select count(*) from public.comparison_measurement_results
      where user_id = (select user_id from params)
    ),
    'product_intake_requests', (
      select count(*) from public.product_intake_requests
      where user_id = (select user_id from params)
    ),
    'product_observation_submissions', (
      select count(*)
      from fitmatch_catalog.product_observation_submissions
      where user_id = (select user_id from params)
    )
  ),
  'recent_closet_items', coalesce((
    select jsonb_agg(to_jsonb(item) order by item.sort_at desc)
    from (
      select
        c.id,
        c.client_item_id,
        c.product_name,
        c.source,
        c.app_category,
        c.app_detail_category,
        c.canonical_category_code,
        c.canonical_detail_code,
        c.comparison_family_code,
        c.is_reference,
        c.classification_status,
        c.sync_revision,
        c.deleted_at,
        coalesce(c.client_updated_at, c.updated_at, c.created_at) as sort_at
      from public.closet_items c
      where c.user_id = (select user_id from params)
      order by coalesce(c.client_updated_at, c.updated_at, c.created_at) desc
      limit 10
    ) item
  ), '[]'::jsonb),
  'recent_comparisons', coalesce((
    select jsonb_agg(to_jsonb(run_row) order by run_row.created_at desc)
    from (
      select
        r.id,
        r.client_history_id,
        r.status,
        r.comparison_level,
        r.block_reason,
        r.created_at,
        r.completed_at,
        (select count(*) from public.comparison_results cr
          where cr.run_id = r.id and cr.user_id = r.user_id) as result_rows,
        (select count(*)
          from public.comparison_measurement_results cmr
          join public.comparison_results cr on cr.id = cmr.result_id
          where cr.run_id = r.id and cmr.user_id = r.user_id) as measurement_rows
      from public.comparison_runs r
      where r.user_id = (select user_id from params)
      order by r.created_at desc
      limit 10
    ) run_row
  ), '[]'::jsonb),
  'recent_product_observations', coalesce((
    select jsonb_agg(to_jsonb(observation_row) order by observation_row.last_submitted_at desc)
    from (
      select
        o.id,
        o.source,
        o.external_product_id,
        o.processing_status,
        o.error_code,
        o.resolved_product_id,
        s.submission_count,
        s.last_submitted_at,
        (select count(*)
          from fitmatch_catalog.product_observation_measurements rom
          where rom.observation_id = o.id) as raw_measurement_rows,
        (select count(*)
          from fitmatch_catalog.product_measurements pm
          join fitmatch_catalog.product_sizes ps on ps.id = pm.product_size_id
          join fitmatch_catalog.product_variants pv on pv.id = ps.variant_id
          where pv.product_id = o.resolved_product_id) as canonical_measurement_rows
      from fitmatch_catalog.product_observation_submissions s
      join fitmatch_catalog.product_observations o on o.id = s.observation_id
      where s.user_id = (select user_id from params)
      order by s.last_submitted_at desc
      limit 10
    ) observation_row
  ), '[]'::jsonb),
  'shared_catalog_counts', jsonb_build_object(
    'products', (select count(*) from fitmatch_catalog.products),
    'product_observations', (select count(*) from fitmatch_catalog.product_observations),
    'raw_observation_measurements', (
      select count(*) from fitmatch_catalog.product_observation_measurements
    ),
    'canonical_product_measurements', (
      select count(*) from fitmatch_catalog.product_measurements
    )
  )
) as fitmatch_e2e_snapshot;
