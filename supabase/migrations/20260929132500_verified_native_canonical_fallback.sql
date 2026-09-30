-- Score a verified canonical alternate only when an active source-native policy
-- names the exact source semantic on both garments. This does not claim
-- RETAILER_EXACT evidence or relax the canonical comparison contract.
begin;

do $preflight$
declare
    existing_hash text;
begin
    select md5(pg_get_functiondef(p.oid)) into existing_hash
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='fitmatch_vnext'
      and p.proname='comparison_evidence_20260908'
      and pg_get_function_identity_arguments(p.oid)=
          'p_reference_closet_item_id uuid, p_policy text, p_canonical jsonb';
    if existing_hash is not null
       and existing_hash <> '9d51f058a2f01ed093f817846fb46ad4' then
        raise exception 'comparison_evidence_20260908 definition drift: %',
            existing_hash;
    end if;
end
$preflight$;

create or replace function fitmatch_vnext.comparison_evidence_20260908(
    p_reference_closet_item_id uuid,
    p_policy text,
    p_canonical jsonb
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with target_rows as (
    select e->>'fitmatch_measurement_code' code,
           e->>'source_measurement_code' source_code,
           (e->>'value')::numeric value,
           lower(e->>'unit_code') unit,
           e->>'basis_code' basis
    from jsonb_array_elements(coalesce(p_canonical->'measurements','[]'::jsonb)) e
    where coalesce((p_canonical->>'semantic_conflict_count')::integer,0)=0
), targets as (
    select code, min(source_code) source_code,
           count(distinct source_code) source_count, min(value) value,
           min(unit) unit, min(basis) basis
    from target_rows
    group by code
    having count(distinct (value,unit,basis))=1
), canonical_evidence as (
    select cm.fitmatch_measurement_code measurement_code,
           r.value reference_value, t.value target_value,
           t.value-r.value difference, abs(t.value-r.value) absolute_difference,
           fm.canonical_unit_code unit_code, fm.canonical_basis_code basis_code,
           cm.weight, cm.requirement_mode, cm.priority,
           fm.body_region_code
    from fitmatch_vnext.comparison_metrics cm
    join fitmatch_vnext.fitmatch_measurements fm
      on fm.measurement_code=cm.fitmatch_measurement_code and fm.is_active
    join fitmatch_vnext.closet_item_measurements r
      on r.closet_item_id=p_reference_closet_item_id
     and r.fitmatch_measurement_code=cm.fitmatch_measurement_code
    join targets t on t.code=cm.fitmatch_measurement_code
    where cm.comparison_policy_code=p_policy and cm.is_active
      and cm.metric_mode='CANONICAL'
      and r.value>0 and r.value::text not in ('NaN','Infinity','-Infinity')
      and t.value>0 and t.value::text not in ('NaN','Infinity','-Infinity')
      and cm.weight>0 and cm.weight::text not in ('NaN','Infinity','-Infinity')
      and lower(r.unit_code)=lower(fm.canonical_unit_code)
      and t.unit=lower(fm.canonical_unit_code)
      and t.basis=fm.canonical_basis_code
), native_candidates as (
    select smm.fitmatch_measurement_code measurement_code,
           r.value reference_value, t.value target_value,
           t.value-r.value difference, abs(t.value-r.value) absolute_difference,
           fm.canonical_unit_code unit_code, fm.canonical_basis_code basis_code,
           cm.weight, cm.requirement_mode, cm.priority,
           fm.body_region_code,
           row_number() over (
               partition by fm.body_region_code
               order by cm.priority, cm.source_measurement_code
           ) choice_rank
    from fitmatch_vnext.comparison_metrics cm
    join fitmatch_vnext.source_measurements sm
      on sm.source_measurement_code=cm.source_measurement_code
     and sm.is_active and sm.is_comparable
    join fitmatch_vnext.source_measurement_mappings smm
      on smm.source_measurement_code=sm.source_measurement_code
     and smm.is_active and smm.is_verified
     and smm.scale_factor=1 and smm.offset_value=0
    join fitmatch_vnext.fitmatch_measurements fm
      on fm.measurement_code=smm.fitmatch_measurement_code and fm.is_active
     and fm.canonical_basis_code=sm.measurement_basis_code
     and fm.representation_code=sm.representation_code
    join fitmatch_vnext.closet_item_measurements r
      on r.closet_item_id=p_reference_closet_item_id
     and r.fitmatch_measurement_code=smm.fitmatch_measurement_code
     and coalesce(r.source_measurement_code_snapshot,
                  r.source_measurement_code)=cm.source_measurement_code
    join fitmatch_vnext.closet_items ci
      on ci.id=r.closet_item_id and ci.deleted_at is null
     and ci.user_id=auth.uid()
    join fitmatch_vnext.products reference_product
      on reference_product.id=ci.product_id
     and reference_product.source_code=sm.source_code
    join fitmatch_vnext.product_sizes target_size
      on target_size.id=(p_canonical->>'product_size_id')::uuid
    join fitmatch_vnext.product_variants target_variant
      on target_variant.id=target_size.variant_id
    join fitmatch_vnext.products target_product
      on target_product.id=target_variant.product_id
     and target_product.source_code=sm.source_code
    join targets t
      on t.code=smm.fitmatch_measurement_code
     and t.source_code=cm.source_measurement_code
     and t.source_count=1
    where cm.comparison_policy_code=p_policy and cm.is_active
      and cm.metric_mode='SOURCE_NATIVE_OVERRIDE'
      and r.value>0 and r.value::text not in ('NaN','Infinity','-Infinity')
      and t.value>0 and t.value::text not in ('NaN','Infinity','-Infinity')
      and cm.weight>0 and cm.weight::text not in ('NaN','Infinity','-Infinity')
      and lower(r.unit_code)=lower(fm.canonical_unit_code)
      and t.unit=lower(fm.canonical_unit_code)
      and t.basis=fm.canonical_basis_code
      and exists (
          select 1
          from fitmatch_vnext.comparison_metrics policy_metric
          join fitmatch_vnext.fitmatch_measurements policy_measurement
            on policy_measurement.measurement_code=policy_metric.fitmatch_measurement_code
           and policy_measurement.is_active
          where policy_metric.comparison_policy_code=p_policy
            and policy_metric.metric_mode='CANONICAL'
            and policy_metric.is_active
            and policy_measurement.body_region_code=fm.body_region_code
      )
      and not exists (
          select 1 from canonical_evidence existing
          where existing.body_region_code=fm.body_region_code
      )
), evidence as (
    select measurement_code, reference_value, target_value, difference,
           absolute_difference, unit_code, basis_code, weight,
           requirement_mode, priority
    from canonical_evidence
    union all
    select measurement_code, reference_value, target_value, difference,
           absolute_difference, unit_code, basis_code, weight,
           requirement_mode, priority
    from native_candidates where choice_rank=1
)
select coalesce(jsonb_agg(to_jsonb(e) order by priority,measurement_code),'[]'::jsonb)
from evidence e;
$function$;

commit;
