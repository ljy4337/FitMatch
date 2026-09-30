-- LOCAL/DISPOSABLE POSTGRESQL ONLY.
-- The original 2026-08-26 fixture predates both the Production-materialized
-- 118 exact decisions and the two product-level UNISEX facts. This script
-- reproduces those two already-deployed facts only in a disposable database.
-- It must never be run against Production.
\set ON_ERROR_STOP on

begin;

do $guard$
begin
  if current_setting('fitmatch.local_fixture', true) is distinct from 'on'
    or (select count(*) from fitmatch_catalog.products) <> 1608
    or (select count(*) from fitmatch_catalog.products
        where source='uniqlo'
          and external_product_id in ('E422992','E487962')
          and audience='MEN'
          and source_category_codes=array['57967','58039','58395']::text[]
          and source_category_path=
            '티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔') <> 2
  then
    raise exception '120_local_audience_snapshot_preimage_mismatch';
  end if;
end
$guard$;

insert into fitmatch_catalog.product_classification_decisions(
  source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,comparison_family,length_type,
  requires_user_confirmation,release_id,decision_version,evidence,
  garment_type_code,authority_status
)
select source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,family_code,length_code,
  requires_user_confirmation,
  '11800000-0000-4000-8000-000000000118'::uuid,
  decision_version,
  coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
    'body_length_code',body_length_code
  ),garment_type_code,authority_status
from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
on conflict(source,external_product_id) do update set
  product_name=excluded.product_name,
  source_category_path=excluded.source_category_path,
  input_fingerprint=excluded.input_fingerprint,
  category_code=excluded.category_code,
  detail_code=excluded.detail_code,
  garment_type_code=excluded.garment_type_code,
  comparison_family=excluded.comparison_family,
  length_type=excluded.length_type,
  requires_user_confirmation=excluded.requires_user_confirmation,
  release_id=excluded.release_id,
  decision_version=excluded.decision_version,
  evidence=excluded.evidence,
  authority_status=excluded.authority_status,
  updated_at=now();

do $decision_postcondition$
begin
  if (select count(*)
      from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
    )<>121
    or (select count(*)
        from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1() manifest
        join fitmatch_catalog.product_classification_decisions decision
          using(source,external_product_id)
        where decision.input_fingerprint is not distinct from manifest.input_fingerprint
          and decision.category_code is not distinct from manifest.category_code
          and decision.detail_code is not distinct from manifest.detail_code
          and decision.garment_type_code is not distinct from manifest.garment_type_code
          and decision.comparison_family is not distinct from manifest.family_code
          and decision.length_type is not distinct from manifest.length_code
          and decision.authority_status is not distinct from manifest.authority_status
    )<>121
  then
    raise exception '120_local_118_decision_materialization_failed';
  end if;
end
$decision_postcondition$;

update fitmatch_catalog.products
set audience='UNISEX'
where source='uniqlo'
  and external_product_id in ('E422992','E487962');

do $postcondition$
begin
  if (select count(*) from fitmatch_catalog.products
      where source='uniqlo'
        and external_product_id in ('E422992','E487962')
        and audience='UNISEX') <> 2
  then
    raise exception '120_local_audience_snapshot_overlay_failed';
  end if;
end
$postcondition$;

commit;
