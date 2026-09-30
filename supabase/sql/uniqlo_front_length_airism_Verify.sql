-- Read-only. resolve_measurement and normalize_measurement_label were inspected:
-- SELECT-only STABLE SQL; dependency is IMMUTABLE string normalization.
SELECT category,raw,fitmatch_vnext.resolve_measurement(
  'uniqlo','size_chart',raw,raw,NULL,category,65) result
FROM unnest(ARRAY['tops','outerwear','dresses','underwear','homewear']) category
CROSS JOIN unnest(ARRAY['knit-body-length-front','body-length-back','body-width',
  'shoulder-width','sleeve-length','sleeve-length-cb']) raw;

-- Existing stored retailer data, not freshly fetched API or authenticated app E2E.
SELECT p.source_product_key,ps.size_label,count(*) raw_count,
  count(*) FILTER (WHERE fitmatch_vnext.resolve_measurement('uniqlo',m.parser_code,
    m.raw_code,m.raw_label,NULL,'underwear',m.raw_value)->>'resolution_status'='RESOLVED') resolved_as_underwear,
  count(DISTINCT fitmatch_vnext.resolve_measurement('uniqlo',m.parser_code,
    m.raw_code,m.raw_label,NULL,'underwear',m.raw_value)->>'fitmatch_measurement_code') distinct_canonical_count
FROM fitmatch_vnext.products p
JOIN fitmatch_vnext.product_variants pv ON pv.product_id=p.id
JOIN fitmatch_vnext.product_sizes ps ON ps.variant_id=pv.id
JOIN fitmatch_vnext.product_size_measurements m ON m.product_size_id=ps.id
WHERE p.source_code='uniqlo' AND p.source_product_key IN ('E471717','E482514','E482522','E454311') AND m.is_current
GROUP BY p.source_product_key,ps.id,ps.size_label ORDER BY p.source_product_key,ps.size_label;

-- product_comparison_group definition inspected: dictionary/product SELECTs only.
SELECT source_product_key,fitmatch_vnext.product_comparison_group(id) result
FROM fitmatch_vnext.products
WHERE source_code='uniqlo' AND source_product_key IN ('E471717','E482514','E482522','E454311','E465185');

-- Compared with preflight hashes; repair must not expand comparison policies.
SELECT
 (SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY policy_code)) FROM fitmatch_vnext.comparison_policies t) policy_hash,
 (SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY id)) FROM fitmatch_vnext.comparison_metrics t) metrics_hash;
