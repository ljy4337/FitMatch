-- READ ONLY. Actual deployed SQL body with only observation tables scoped to selected rows.
WITH selected_products AS (
 SELECT * FROM fitmatch_vnext.products WHERE id IN ('46b46806-b4c1-4507-889a-fdbf53b554a7','723d2723-9f7e-4407-bf72-d6e882ee6fb4')
), selected_signals AS (
 SELECT pcs.* FROM fitmatch_vnext.product_classification_signals pcs JOIN selected_products p ON p.id=pcs.product_id
), selected_receipts AS (
 SELECT * FROM fitmatch_vnext.product_ingestion_receipts WHERE id IN ('aa4dc0fe-2fea-42e0-b0ba-55b0ffd0ce1b','1e43c06b-eb04-442c-a310-393cdc0fb8d1')
), auto_keys AS (
 SELECT DISTINCT s.external_key FROM fitmatch_vnext.classification_signal_mappings m
 JOIN fitmatch_vnext.source_classification_signals s ON s.id=m.source_signal_id
 WHERE m.mapping_version='vnext-uniqlo-complete-path-20260902-v3'
 AND m.is_active AND m.is_verified AND m.resolution_mode='DIRECT'
 AND s.source_code='uniqlo' AND s.signal_kind='CATEGORY' AND s.is_active
)
SELECT audit_signal.id AS signal_id,
 fitmatch_vnext.uniqlo_complete_observed_category_path(audit_signal.id) IS NOT NULL AS original_has_path,
 selected.path IS NOT NULL AS selected_has_path,
 fitmatch_vnext.uniqlo_complete_observed_category_path(audit_signal.id) IS NOT DISTINCT FROM selected.path AS path_preserved
FROM fitmatch_vnext.source_classification_signals audit_signal
JOIN auto_keys k ON k.external_key=audit_signal.external_key
LEFT JOIN LATERAL (with target as (
    select s.id, s.external_key, s.audience_code
    from fitmatch_vnext.source_classification_signals s
    where s.id = audit_signal.id
      and s.source_code = 'uniqlo'
      and s.signal_kind = 'CATEGORY'
      and s.is_active
      and s.audience_code in ('MEN','WOMEN','UNISEX')
), receipt_paths as (
    select t.external_key,
           array_agg(btrim(code.value) order by code.ordinality) path
    from target t
    join selected_signals pcs
      on pcs.source_signal_id = t.id
    join selected_products p on p.id = pcs.product_id
     and p.source_code = 'uniqlo' and p.audience_code = t.audience_code
    join selected_receipts r
      on r.product_id = p.id and r.source_code = 'uniqlo'
     and r.processing_status = 'PROCESSED'
     and r.observed_at = p.last_seen_at
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(r.retailer_facts -> 'source_category_codes') = 'array'
        then r.retailer_facts -> 'source_category_codes'
        else '[]'::jsonb end
    ) with ordinality code(value, ordinality)
    where r.retailer_facts -> 'structured_facts'
            ->> 'source_category_path_completeness' = 'complete'
      and r.retailer_facts -> 'structured_facts'
            ->> 'source_category_path_source' = 'uniqlo_pdp_breadcrumbs'
      and case upper(btrim(r.retailer_facts ->> 'audience'))
            when 'M' then 'MEN' when 'MAN' then 'MEN' when 'MALE' then 'MEN'
            when 'W' then 'WOMEN' when 'WOMAN' then 'WOMEN' when 'FEMALE' then 'WOMEN'
            when 'U' then 'UNISEX' when 'COMMON' then 'UNISEX' when 'M,W' then 'UNISEX'
            else upper(btrim(r.retailer_facts ->> 'audience')) end = t.audience_code
      and btrim(code.value) <> ''
    group by r.id, t.external_key
), valid_paths as (
    select path from receipt_paths
    where cardinality(path) > 0
      and path[cardinality(path)] = external_key
      and cardinality(path) = (
          select count(distinct code) from unnest(path) code
      )
)
select path from valid_paths
where (select count(distinct path) from valid_paths) = 1
limit 1) selected ON true
WHERE audit_signal.source_code='uniqlo' AND audit_signal.signal_kind='CATEGORY'
 AND audit_signal.is_active AND audit_signal.audience_code IN ('MEN','WOMEN','UNISEX');
