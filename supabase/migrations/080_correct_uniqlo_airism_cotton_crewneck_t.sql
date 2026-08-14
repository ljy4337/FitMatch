begin;

-- AIRism is a material/technology line, not a garment category. These products
-- are crew-neck T-shirts even though Uniqlo merchandises them under Innerwear.
update fitmatch_staging.runtime_classification_regression_cases
set expected_category_code = 'tops',
    expected_detail_code = 'short_sleeve',
    expected_comparable = true,
    evidence = evidence || jsonb_build_object(
      'classification_correction', 'airism_material_line_product_structure_wins',
      'corrected_at', '2026-08-14'
    )
where source_code = 'uniqlo'
  and external_product_id in ('E474244', 'E482522')
  and product_name = 'AIRism코튼크루넥T';

-- These are QA expectations. result_payload remains the immutable output of
-- the previous run so that the old misclassification stays auditable.
update fitmatch_qa.classification_cases
set expected_category_code = 'tops',
    expected_detail_code = 'short_sleeve',
    expected_comparison_family = 'tshirt',
    expected_length_type = 'unknown',
    requires_user_confirmation = false
where source = 'uniqlo'
  and product_id in ('E474244', 'E482522')
  and product_name = 'AIRism코튼크루넥T';

do $$
begin
  if (select count(*)
      from fitmatch_staging.runtime_classification_regression_cases
      where source_code = 'uniqlo'
        and external_product_id in ('E474244', 'E482522')
        and expected_category_code = 'tops'
        and expected_detail_code = 'short_sleeve') <> 2 then
    raise exception 'AIRism cotton crew-neck T regression correction incomplete';
  end if;

  if (select count(*)
      from fitmatch_qa.classification_cases
      where source = 'uniqlo'
        and product_id in ('E474244', 'E482522')
        and expected_category_code = 'tops'
        and expected_detail_code = 'short_sleeve'
        and expected_comparison_family = 'tshirt') <> 2 then
    raise exception 'AIRism cotton crew-neck T QA expectation correction incomplete';
  end if;
end $$;

commit;
