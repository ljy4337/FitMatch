-- Restore the pre-20260929132500 canonical-only evidence selector.
begin;
create or replace function fitmatch_vnext.comparison_evidence_20260908(
    p_reference_closet_item_id uuid, p_policy text, p_canonical jsonb
)
returns jsonb language sql stable set search_path = '' as $function$
with target_rows as (
 select e->>'fitmatch_measurement_code' code,(e->>'value')::numeric value,
        lower(e->>'unit_code') unit, e->>'basis_code' basis
 from jsonb_array_elements(coalesce(p_canonical->'measurements','[]'::jsonb)) e
 where coalesce((p_canonical->>'semantic_conflict_count')::integer,0)=0
), targets as (
 select code,min(value) value,min(unit) unit,min(basis) basis
 from target_rows
 group by code
 having count(distinct (value,unit,basis))=1
), evidence as (
 select cm.fitmatch_measurement_code measurement_code,r.value reference_value,
 t.value target_value,t.value-r.value difference,abs(t.value-r.value) absolute_difference,
 fm.canonical_unit_code unit_code,fm.canonical_basis_code basis_code,
 cm.weight,cm.requirement_mode,cm.priority
 from fitmatch_vnext.comparison_metrics cm
 join fitmatch_vnext.fitmatch_measurements fm
   on fm.measurement_code=cm.fitmatch_measurement_code and fm.is_active
 join fitmatch_vnext.closet_item_measurements r
   on r.closet_item_id=p_reference_closet_item_id
  and r.fitmatch_measurement_code=cm.fitmatch_measurement_code
 join targets t on t.code=cm.fitmatch_measurement_code
 where cm.comparison_policy_code=p_policy and cm.is_active and cm.metric_mode='CANONICAL'
   and r.value>0 and r.value::text not in ('NaN','Infinity','-Infinity')
   and t.value>0 and t.value::text not in ('NaN','Infinity','-Infinity')
   and cm.weight>0 and cm.weight::text not in ('NaN','Infinity','-Infinity')
   and lower(r.unit_code)=lower(fm.canonical_unit_code)
   and t.unit=lower(fm.canonical_unit_code) and t.basis=fm.canonical_basis_code
)
select coalesce(jsonb_agg(to_jsonb(e) order by priority,measurement_code),'[]'::jsonb)
from evidence e;
$function$;
commit;
