begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch:uniqlo-e482202-family-v1'));

do $$
begin
  if (select count(*) from fitmatch_catalog.product_classification_decisions
      where source='uniqlo' and external_product_id='E482202'
        and category_code='underwear' and detail_code='women_bra'
        and comparison_family='tshirt') <> 1 then
    raise exception 'E482202 canonical decision precondition failed';
  end if;
  if (select count(*) from fitmatch_qa.classification_cases
      where source='uniqlo' and product_id='E482202'
        and expected_category_code='underwear'
        and expected_detail_code='women_bra'
        and expected_comparison_family='tshirt') <> 1 then
    raise exception 'E482202 QA precondition failed';
  end if;
  if (select count(*) from fitmatch_catalog.current_product_classifications
      where source='uniqlo' and external_product_id='E482202'
        and category_code='underwear' and detail_code='women_bra'
        and comparison_family_code='tshirt') <> 1 then
    raise exception 'E482202 runtime precondition failed';
  end if;
end $$;

update fitmatch_catalog.product_classification_decisions
set comparison_family='underwear',
    decision_version='db-runtime-family-correction-2026-08-18-v1',
    evidence=evidence || jsonb_build_object(
      'family_correction','underwear category requires underwear family',
      'family_correction_version','db-runtime-family-correction-2026-08-18-v1'
    ),
    updated_at=now()
where source='uniqlo' and external_product_id='E482202';

update fitmatch_qa.classification_cases
set expected_comparison_family='underwear',
    result_payload=jsonb_set(
      jsonb_set(result_payload,'{garmentFamily}','"underwear"'::jsonb,true),
      '{canonicalSyncVersion}',
      '"db-runtime-family-correction-2026-08-18-v1"'::jsonb,
      true
    )
where source='uniqlo' and product_id='E482202'
  and expected_category_code='underwear'
  and expected_detail_code='women_bra'
  and expected_comparison_family='tshirt';

update fitmatch_catalog.product_classification_history h
set comparison_family_code='underwear',
    decision_version='db-runtime-family-correction-2026-08-18-v1',
    evidence=h.evidence || jsonb_build_object(
      'family_correction','underwear category requires underwear family',
      'family_correction_version','db-runtime-family-correction-2026-08-18-v1'
    )
from fitmatch_catalog.products p
where h.product_id=p.id and h.is_current
  and p.source='uniqlo' and p.external_product_id='E482202';

do $$
declare
  v_validation jsonb := fitmatch_qa.validate_product_runtime_v3();
begin
  if coalesce((v_validation->>'passed')::boolean,false) is not true then
    raise exception 'product runtime validation failed after E482202 correction: %',v_validation;
  end if;
  if (select count(*) from fitmatch_catalog.product_classification_decisions
      where source='uniqlo' and external_product_id='E482202'
        and category_code='underwear' and detail_code='women_bra'
        and comparison_family='underwear') <> 1 then
    raise exception 'E482202 canonical decision postcondition failed';
  end if;
end $$;

commit;
