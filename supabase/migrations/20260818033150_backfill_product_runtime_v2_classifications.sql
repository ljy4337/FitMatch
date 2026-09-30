begin;

set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('fitmatch:backfill-product-runtime-v2'));

do $$
declare r record;
begin
  for r in
    select p.* from fitmatch_catalog.products p
    where not exists (
      select 1 from fitmatch_catalog.product_classification_history h
      where h.product_id=p.id and h.is_current
    )
    order by p.source,p.external_product_id
  loop
    perform fitmatch_catalog.runtime_resolve_and_promote_product(
      jsonb_build_object(
        'source',r.source,
        'external_product_id',r.external_product_id,
        'product_name',r.product_name,
        'canonical_url',r.canonical_url,
        'audience',r.audience,
        'source_category_path',r.source_category_path,
        'source_category_codes',to_jsonb(r.source_category_codes),
        'image_url',r.image_url,
        'raw_payload',r.raw_payload,
        'lifecycle_status',r.lifecycle_status,
        'observed_at',r.last_seen_at
      )
    );
  end loop;
end $$;

do $$
declare
  v_products integer;
  v_current integer;
  v_duplicate integer;
  v_review integer;
begin
  select count(*) into v_products from fitmatch_catalog.products;
  select count(*) into v_current
    from fitmatch_catalog.product_classification_history where is_current;
  select count(*) into v_duplicate from (
    select product_id from fitmatch_catalog.product_classification_history
    where is_current group by product_id having count(*)>1
  ) d;
  select count(*) into v_review
    from fitmatch_catalog.product_classification_history
    where is_current and classification_status='review_required';
  if v_current<>v_products or v_duplicate<>0 then
    raise exception 'runtime v2 backfill incomplete: products %, current %, duplicate %',
      v_products,v_current,v_duplicate;
  end if;
  if v_review=0 then
    raise exception 'runtime v2 backfill unexpectedly removed fail-closed review rows';
  end if;
end $$;

commit;
;
