-- Purpose: prevent product_readiness from counting canonical measurements that
-- are outside the product's current active comparison policy.
-- Data impact: none; function replacement only. Existing READY products remain
-- READY only when an evidence-backed, unexpired size satisfies current metrics.
-- Rollback: restore product_readiness from 20260829012618.
-- Verification: the three provider Golden sizes remain READY; adding an
-- out-of-policy canonical measurement cannot change readiness to READY.

create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with product_row as (
    select p.*, gt.comparison_policy_code, gt.is_active garment_active
    from fitmatch_vnext.products p
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where p.id = p_product_id
), policy as (
    select cp.*
    from product_row p
    join fitmatch_vnext.comparison_policies cp
      on cp.policy_code = p.comparison_policy_code and cp.is_active
), policy_metrics as (
    select cm.fitmatch_measurement_code, cm.requirement_mode
    from policy cp
    join fitmatch_vnext.comparison_metrics cm
      on cm.comparison_policy_code = cp.policy_code
     and cm.metric_mode = 'CANONICAL'
     and cm.is_active
), latest_availability as (
    select distinct on (o.product_size_id)
           o.product_size_id, o.availability_status, o.observed_at,
           o.valid_until, o.evidence_fingerprint
    from fitmatch_vnext.size_availability_observations o
    join fitmatch_vnext.product_sizes ps on ps.id = o.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where pv.product_id = p_product_id
    order by o.product_size_id, o.observed_at desc, o.id desc
), usable_sizes as (
    select ps.id product_size_id, ps.size_label, la.observed_at,
           la.valid_until, la.evidence_fingerprint
    from latest_availability la
    join fitmatch_vnext.product_sizes ps on ps.id = la.product_size_id
    where la.availability_status = 'AVAILABLE'
      and la.valid_until is not null
      and la.valid_until >= now()
), size_diagnostics as (
    select u.product_size_id, u.size_label, u.observed_at, u.valid_until,
           u.evidence_fingerprint,
           coalesce((canonical.payload ->> 'raw_measurement_count')::integer, 0)
               raw_measurement_count,
           coalesce((canonical.payload ->> 'semantic_conflict_count')::integer, 0)
               semantic_conflict_count,
           count(distinct pm.fitmatch_measurement_code) resolved_count,
           count(distinct pm.fitmatch_measurement_code) filter (
               where pm.requirement_mode = 'REQUIRED_ANY'
           ) required_any_count
    from usable_sizes u
    cross join lateral (
        select fitmatch_vnext.canonical_measurements_for_size(u.product_size_id) payload
    ) canonical
    left join lateral jsonb_array_elements(
        canonical.payload -> 'measurements'
    ) measurement on true
    left join policy_metrics pm
      on pm.fitmatch_measurement_code = measurement ->> 'fitmatch_measurement_code'
    group by u.product_size_id, u.size_label, u.observed_at, u.valid_until,
             u.evidence_fingerprint, canonical.payload
), ready_sizes as (
    select sd.*
    from size_diagnostics sd
    cross join policy cp
    where sd.semantic_conflict_count = 0
      and sd.resolved_count >= cp.min_common_measurements
      and sd.required_any_count >= cp.required_any_min
)
select case when not exists (select 1 from product_row) then
    jsonb_build_object(
        'status', 'CLASSIFICATION_REQUIRED',
        'ready', false,
        'reason', 'Unknown product',
        'readiness_version', 'fitmatch-vnext-readiness-v2'
    )
else (
    select jsonb_build_object(
        'product_id', p.id,
        'ready', p.classification_status = 'CONFIRMED'
            and exists (select 1 from ready_sizes),
        'status', case
            when p.classification_status = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
            when p.classification_status <> 'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
            when not coalesce((fitmatch_vnext.classification_tuple_validation(
                p.garment_type_code, p.product_structure_code, p.audience_code,
                p.sleeve_length_code, p.lower_length_code, p.body_length_code
              ) ->> 'valid')::boolean, false) then 'CLASSIFICATION_REQUIRED'
            when not exists (select 1 from policy) then 'POLICY_UNAVAILABLE'
            when not exists (select 1 from usable_sizes) then 'NO_AVAILABLE_SIZE'
            when not exists (
                select 1 from size_diagnostics where raw_measurement_count > 0
            ) then 'NO_MEASUREMENT_DATA'
            when not exists (
                select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0
            ) and exists (
                select 1 from size_diagnostics where semantic_conflict_count > 0
            ) then 'INSUFFICIENT_MEASUREMENTS'
            when not exists (
                select 1 from size_diagnostics where resolved_count > 0
            ) then 'MAPPING_REQUIRED'
            when not exists (select 1 from ready_sizes)
                then 'INSUFFICIENT_MEASUREMENTS'
            else 'READY' end,
        'reason', case
            when p.classification_status = 'NOT_APPLICABLE'
                then 'Product is not a comparable single garment'
            when p.classification_status <> 'CONFIRMED'
                then 'Classification is not CONFIRMED'
            when not coalesce((fitmatch_vnext.classification_tuple_validation(
                p.garment_type_code, p.product_structure_code, p.audience_code,
                p.sleeve_length_code, p.lower_length_code, p.body_length_code
              ) ->> 'valid')::boolean, false)
                then 'Classification tuple is invalid'
            when not exists (select 1 from policy)
                then 'No active comparison policy'
            when not exists (select 1 from usable_sizes)
                then 'No evidence-backed unexpired AVAILABLE size'
            when not exists (
                select 1 from size_diagnostics where raw_measurement_count > 0
            ) then 'Available size has no current raw measurement evidence'
            when not exists (
                select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0
            ) and exists (
                select 1 from size_diagnostics where semantic_conflict_count > 0
            ) then 'Available size has conflicting canonical semantics'
            when not exists (
                select 1 from size_diagnostics where resolved_count > 0
            ) then 'Current policy metrics cannot be resolved from raw evidence'
            when not exists (select 1 from ready_sizes)
                then 'Current policy minimum measurements are not satisfied'
            else 'Classification, availability, current policy metrics, and semantics are ready'
            end,
        'comparison_policy_code', p.comparison_policy_code,
        'ready_sizes', coalesce((
            select jsonb_agg(jsonb_build_object(
                'product_size_id', r.product_size_id,
                'size_label', r.size_label,
                'resolved_measurement_count', r.resolved_count,
                'required_any_count', r.required_any_count,
                'semantic_conflict_count', r.semantic_conflict_count,
                'availability_observed_at', r.observed_at,
                'availability_valid_until', r.valid_until,
                'availability_evidence_fingerprint', r.evidence_fingerprint
            ) order by r.size_label, r.product_size_id)
            from ready_sizes r
        ), '[]'::jsonb),
        'size_diagnostics', coalesce((
            select jsonb_agg(jsonb_build_object(
                'product_size_id', d.product_size_id,
                'size_label', d.size_label,
                'raw_measurement_count', d.raw_measurement_count,
                'policy_measurement_count', d.resolved_count,
                'required_any_count', d.required_any_count,
                'semantic_conflict_count', d.semantic_conflict_count,
                'availability_evidence_fingerprint', d.evidence_fingerprint
            ) order by d.size_label, d.product_size_id)
            from size_diagnostics d
        ), '[]'::jsonb),
        'readiness_version', 'fitmatch-vnext-readiness-v2'
    )
    from product_row p
)
end;
$function$;

revoke all on function fitmatch_vnext.product_readiness(uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness(uuid) to service_role;

-- Verification query:
-- select p.source_code, p.source_product_key,
--        fitmatch_vnext.product_readiness(p.id) ->> 'status' status
-- from fitmatch_vnext.products p
-- where (p.source_code,p.source_product_key) in
-- (('musinsa','6805433'),('uniqlo','E482856'),('zara','561264931'));
;
