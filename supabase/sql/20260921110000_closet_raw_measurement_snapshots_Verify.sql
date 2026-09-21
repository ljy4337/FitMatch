-- READ ONLY post-apply verification for
-- 20260921110000_closet_raw_measurement_snapshots.sql.
-- Run against the target database after the migration; this file writes no data.
begin transaction read only;

select to_regclass('fitmatch_vnext.closet_item_source_measurements')
    as source_snapshot_table,
       to_regprocedure('fitmatch_vnext.upsert_closet_item_for_swift(jsonb)')
    as linked_upsert,
       to_regprocedure('fitmatch_vnext.list_closet_items()')
    as closet_list;

select routine_schema, routine_name, security_type
from information_schema.routines
where (routine_schema, routine_name) in (
    ('fitmatch_vnext', 'upsert_closet_item_for_swift'),
    ('fitmatch_vnext', 'list_closet_items')
)
order by routine_schema, routine_name;

-- Every stored row must retain a stable source identity; values are not
-- compared to the current product table because re-ingestion is allowed to
-- change the current retailer observation without rewriting Closet history.
select
    count(*) filter (where btrim(raw_measurement_key) = '') as blank_identity_count,
    count(*) filter (where parser_code is null or btrim(parser_code) = '') as blank_parser_count,
    count(*) filter (where source_code is null or btrim(source_code) = '') as blank_source_count,
    count(*) filter (where evidence_payload is null or jsonb_typeof(evidence_payload) <> 'object')
        as invalid_evidence_count
from fitmatch_vnext.closet_item_source_measurements;

select closet_item_id, parser_code, raw_measurement_key, count(*) as duplicate_count
from fitmatch_vnext.closet_item_source_measurements
group by closet_item_id, parser_code, raw_measurement_key
having count(*) > 1;

-- List payload must expose the immutable raw snapshot without changing its
-- existing `measurements` contract. Inspect a linked item after an isolated
-- save/read-back fixture has created one.
select
    item ->> 'id' as closet_item_id,
    jsonb_array_length(coalesce(item -> 'measurements', '[]'::jsonb))
        as canonical_measurement_count,
    jsonb_array_length(coalesce(item -> 'source_measurements', '[]'::jsonb))
        as source_measurement_count
from jsonb_array_elements(fitmatch_vnext.list_closet_items()) item
where item ? 'product_size_id'
order by closet_item_id;

rollback;
