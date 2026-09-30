-- READ ONLY; fixed selection. Hashes/counts are evidence, not exported data.
SELECT 'fitmatch_catalog.comparison_group_policies' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.comparison_group_policies t WHERE TRUE
UNION ALL
SELECT 'fitmatch_catalog.comparison_groups' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.comparison_groups t WHERE TRUE
UNION ALL
SELECT 'fitmatch_catalog.product_classification_history' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.product_classification_history t WHERE TRUE
UNION ALL
SELECT 'fitmatch_catalog.product_comparison_group_overrides' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.product_comparison_group_overrides t WHERE TRUE
UNION ALL
SELECT 'fitmatch_catalog.products' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.products t WHERE TRUE
UNION ALL
SELECT 'fitmatch_catalog.releases' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.releases t WHERE TRUE
UNION ALL
SELECT 'fitmatch_catalog.retailer_observed_categories' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.retailer_observed_categories t WHERE FALSE
UNION ALL
SELECT 'fitmatch_catalog.retailer_observed_category_measurements' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.retailer_observed_category_measurements t WHERE FALSE
UNION ALL
SELECT 'fitmatch_catalog.source_category_comparison_groups' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_catalog.source_category_comparison_groups t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.classification_axis_value_authority' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.classification_axis_value_authority t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.classification_signal_mappings' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.classification_signal_mappings t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.closet_item_measurements' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.closet_item_measurements t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.closet_item_source_measurement_snapshots' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.closet_item_source_measurement_snapshots t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.closet_item_source_measurements' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.closet_item_source_measurements t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.closet_items' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.closet_items t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.comparison_metrics' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.comparison_metrics t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.comparison_policies' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.comparison_policies t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.comparison_result_heads' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.comparison_result_heads t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.comparisons' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.comparisons t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.fitmatch_categories' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.fitmatch_categories t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.fitmatch_measurements' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.fitmatch_measurements t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.garment_types' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.garment_types t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.product_classification_signals' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.product_classification_signals t WHERE product_id IN (SELECT id FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid))
UNION ALL
SELECT 'fitmatch_vnext.product_ingestion_receipts' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.product_ingestion_receipts t WHERE id IN ('aa4dc0fe-2fea-42e0-b0ba-55b0ffd0ce1b'::uuid,'1e43c06b-eb04-442c-a310-393cdc0fb8d1'::uuid)
UNION ALL
SELECT 'fitmatch_vnext.product_size_measurements' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.product_size_measurements t WHERE product_size_id IN (SELECT id FROM fitmatch_vnext.product_sizes WHERE variant_id IN (SELECT id FROM fitmatch_vnext.product_variants WHERE product_id IN (SELECT id FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid))))
UNION ALL
SELECT 'fitmatch_vnext.product_sizes' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.product_sizes t WHERE variant_id IN (SELECT id FROM fitmatch_vnext.product_variants WHERE product_id IN (SELECT id FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid)))
UNION ALL
SELECT 'fitmatch_vnext.product_variants' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.product_variants t WHERE product_id IN (SELECT id FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid))
UNION ALL
SELECT 'fitmatch_vnext.products' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.products t WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid)
UNION ALL
SELECT 'fitmatch_vnext.size_availability_observations' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.size_availability_observations t WHERE product_size_id IN (SELECT id FROM fitmatch_vnext.product_sizes WHERE variant_id IN (SELECT id FROM fitmatch_vnext.product_variants WHERE product_id IN (SELECT id FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid))))
UNION ALL
SELECT 'fitmatch_vnext.source_classification_signals' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.source_classification_signals t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.source_identifiers' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.source_identifiers t WHERE product_id IN (SELECT id FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7'::uuid,'723d2723-9f7e-4407-bf72-d6e882ee6fb4'::uuid))
UNION ALL
SELECT 'fitmatch_vnext.source_measurement_aliases' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.source_measurement_aliases t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.source_measurement_mappings' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.source_measurement_mappings t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.source_measurements' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.source_measurements t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.sources' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.sources t WHERE TRUE
UNION ALL
SELECT 'fitmatch_vnext.user_classification_feedback_evidence' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.user_classification_feedback_evidence t WHERE FALSE
UNION ALL
SELECT 'fitmatch_vnext.user_product_classification_overrides' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM fitmatch_vnext.user_product_classification_overrides t WHERE FALSE
UNION ALL
SELECT 'public.profiles' AS table_name, count(*) AS selected_rows, md5(coalesce(string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),'')) AS content_md5 FROM public.profiles t WHERE FALSE
ORDER BY table_name;
