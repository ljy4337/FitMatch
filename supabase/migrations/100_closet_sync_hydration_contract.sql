begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch:closet-sync-hydration-v1'));

-- A restored local cache needs the retailer identity, not only the internal
-- product UUID. Keep the private catalog hidden and expose only the product
-- facts already referenced by the authenticated user's closet row.
create or replace function public.fitmatch_list_closet_items()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when auth.uid() is null then
    jsonb_build_object('state', 'authentication_required', 'items', '[]'::jsonb)
  else jsonb_build_object(
    'state', 'ready',
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'closet_item_id', c.id,
      'client_item_id', c.client_item_id,
      'product_id', c.product_id,
      'external_product_id', p.external_product_id,
      'product_audience', p.audience,
      'source_category_codes', coalesce(p.source_category_codes, '{}'::text[]),
      'variant_id', c.variant_id,
      'product_size_id', c.product_size_id,
      'brand', c.brand,
      'product_name', c.product_name,
      'size_name', c.size_name,
      'gender_code', c.gender,
      'source', c.source,
      'source_category_path', c.original_category_path,
      'product_url', c.product_url,
      'image_url', c.image_url,
      'measurements', c.measurements,
      'measurement_records', c.measurement_records,
      'fit_memo', c.fit_memo,
      'fit_preference_code', c.fit_preference_code,
      'satisfaction', c.satisfaction,
      'is_reference', c.is_reference,
      'classification_status', c.classification_status,
      'classification_source', c.classification_source,
      'category_code', c.app_category,
      'detail_code', c.app_detail_category,
      'canonical_category_code', c.canonical_category_code,
      'canonical_detail_code', c.canonical_detail_code,
      'family_code', c.comparison_family_code,
      'length_code', c.comparison_length_code,
      'body_length_code', c.comparison_body_length_code,
      'classification_snapshot', c.classification_snapshot,
      'client_snapshot', c.client_snapshot,
      'client_created_at', c.client_created_at,
      'client_updated_at', c.client_updated_at,
      'sync_revision', c.sync_revision,
      'created_at', c.created_at,
      'updated_at', c.updated_at
    ) order by coalesce(c.client_created_at, c.created_at) desc), '[]'::jsonb)
  ) end
  from public.closet_items c
  left join fitmatch_catalog.products p on p.id = c.product_id
  where c.user_id = auth.uid() and c.deleted_at is null
$$;

revoke all on function public.fitmatch_list_closet_items() from public, anon;
grant execute on function public.fitmatch_list_closet_items() to authenticated;

commit;
