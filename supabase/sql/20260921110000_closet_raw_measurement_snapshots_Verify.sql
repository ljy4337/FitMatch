-- READ ONLY post-apply verification for 20260921110000.
-- Run after the migration; it intentionally creates no fixture data.

begin transaction read only;

select to_regclass('fitmatch_vnext.closet_item_source_measurement_snapshots')
    as snapshot_manifest_table,
       to_regclass('fitmatch_vnext.closet_item_source_measurements')
    as source_measurement_table,
       to_regprocedure('fitmatch_vnext.upsert_closet_item_with_group_for_swift(jsonb)')
    as group_upsert,
       to_regprocedure('fitmatch_vnext.upsert_closet_item_with_group_for_swift_snapshot_base(jsonb)')
    as group_upsert_base,
       to_regprocedure('fitmatch_vnext.list_closet_items()') as source_list,
       to_regprocedure('fitmatch_vnext.list_closet_items_snapshot_base()') as source_list_base;

-- The public bridges must remain on the group-aware private upsert and must
-- continue to attach comparison_group to each list item.
select
    position('upsert_closet_item_with_group_for_swift(p_request)' in
        pg_get_functiondef('public.fitmatch_vnext_upsert_closet_item(jsonb)'::regprocedure)) > 0
        as public_upsert_uses_group_owner,
    position('closet_comparison_group' in
        pg_get_functiondef('public.fitmatch_vnext_list_closet_items()'::regprocedure)) > 0
        as public_list_preserves_comparison_group,
    position('source_measurements' in
        pg_get_functiondef('fitmatch_vnext.list_closet_items()'::regprocedure)) > 0
        as internal_list_adds_source_measurements;

-- One manifest means one frozen, complete raw row set. A nonzero difference
-- detects a partial/late append; the actual raw values are intentionally not
-- compared to current product rows because re-ingestion is allowed.
select
    s.closet_item_id,
    s.source_observation_id,
    s.source_measurement_count as expected_source_measurement_count,
    count(sm.*)::integer as stored_source_measurement_count,
    count(sm.*)::integer - s.source_measurement_count as count_difference
from fitmatch_vnext.closet_item_source_measurement_snapshots s
left join fitmatch_vnext.closet_item_source_measurements sm
  on sm.closet_item_id = s.closet_item_id
group by s.closet_item_id, s.source_observation_id, s.source_measurement_count
having count(sm.*)::integer <> s.source_measurement_count;

select
    count(*) filter (where btrim(raw_measurement_key) = '') as blank_identity_count,
    count(*) filter (where parser_code is null or btrim(parser_code) = '') as blank_parser_count,
    count(*) filter (where source_code is null or btrim(source_code) = '') as blank_source_count,
    count(*) filter (where evidence_payload is null or jsonb_typeof(evidence_payload) <> 'object')
        as invalid_evidence_count
from fitmatch_vnext.closet_item_source_measurements;

-- The retained raw receipt can contain zero/negative facts, but their current
-- product rows must not appear in either canonical path.
with invalid_raw as (
    select psm.id, psm.product_size_id
    from fitmatch_vnext.product_size_measurements psm
    where psm.is_current and psm.raw_value <= 0
), canonical_ids as (
    select (m ->> 'product_size_measurement_id')::uuid as measurement_id
    from invalid_raw r
    cross join lateral jsonb_array_elements(
        fitmatch_vnext.canonical_measurements_for_size(r.product_size_id) -> 'measurements'
    ) m
)
select count(*) as nonpositive_canonical_count
from invalid_raw r join canonical_ids c on c.measurement_id = r.id;

-- The actual list invocation needs an authenticated user context. Its group
-- and source-row behavior is exercised by the isolated regression rather
-- than making this read-only postflight depend on an operator JWT.

rollback;
