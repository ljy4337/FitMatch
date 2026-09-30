begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:batch-product-ingest-api-v1'));

create or replace function public.fitmatch_batch_ingest_product(
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  v_ingest jsonb;
  v_promotion jsonb;
begin
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'payload_must_be_object';
  end if;
  if coalesce(p_payload->'raw_payload'->>'batch_ingest_version', '') = '' then
    raise exception using errcode = '22023', message = 'batch_ingest_version_required';
  end if;

  v_ingest := fitmatch_catalog.runtime_ingest_product_payload(p_payload);
  v_promotion := fitmatch_catalog.runtime_resolve_and_promote_product(p_payload);

  return v_promotion || jsonb_build_object(
    'variants_processed', coalesce((v_ingest->>'variants_processed')::integer, 0),
    'sizes_processed', coalesce((v_ingest->>'sizes_processed')::integer, 0),
    'measurements_processed', coalesce((v_ingest->>'measurements_processed')::integer, 0)
  );
end $$;

create or replace function public.fitmatch_batch_products_needing_ingest(
  p_source text,
  p_external_ids text[],
  p_batch_version text
) returns table(external_product_id text)
language plpgsql
stable
security invoker
set search_path = pg_catalog
as $$
declare
  v_source text := lower(btrim(coalesce(p_source, '')));
  v_version text := btrim(coalesce(p_batch_version, ''));
begin
  if v_source not in ('uniqlo', 'musinsa') then
    raise exception using errcode = '22023', message = 'unsupported_batch_source';
  end if;
  if v_version = '' or length(v_version) > 100 then
    raise exception using errcode = '22023', message = 'invalid_batch_version';
  end if;
  if p_external_ids is null
     or cardinality(p_external_ids) = 0
     or cardinality(p_external_ids) > 5000 then
    raise exception using errcode = '22023', message = 'external_id_chunk_must_contain_1_to_5000_items';
  end if;

  return query
  select distinct btrim(i.external_id)
  from unnest(p_external_ids) as i(external_id)
  left join fitmatch_catalog.products p
    on p.source = v_source
   and p.external_product_id = btrim(i.external_id)
  where btrim(coalesce(i.external_id, '')) <> ''
    and (
      p.id is null
      or coalesce(p.raw_payload->>'batch_ingest_version', '') <> v_version
      or not exists (
        select 1
        from fitmatch_catalog.product_classification_history h
        where h.product_id = p.id and h.is_current
      )
    );
end $$;

comment on function public.fitmatch_batch_ingest_product(jsonb) is
  'Backend batch only: atomically upsert product/size/measurements and persist canonical classification.';
comment on function public.fitmatch_batch_products_needing_ingest(text,text[],text) is
  'Backend batch only: return observed IDs not yet processed by the requested batch contract.';

revoke all on function public.fitmatch_batch_ingest_product(jsonb)
  from public, anon, authenticated;
revoke all on function public.fitmatch_batch_products_needing_ingest(text,text[],text)
  from public, anon, authenticated;
grant execute on function public.fitmatch_batch_ingest_product(jsonb)
  to service_role;
grant execute on function public.fitmatch_batch_products_needing_ingest(text,text[],text)
  to service_role;

commit;;
