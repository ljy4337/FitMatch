begin;

create or replace function fitmatch_vnext.product_measurement_readiness(
  p_product_id uuid,
  p_effective_classification jsonb
)
returns jsonb
language sql
stable security definer
set search_path=''
as $function$
with product_row as (
  select p.*,
    p_effective_classification->>'classification_status' effective_status,
    p_effective_classification->>'comparison_policy_code' effective_policy_code,
    fitmatch_vnext.product_comparison_unit_decision(p.id) comparison_unit
  from fitmatch_vnext.products p where p.id=p_product_id
), policy_metrics as (
  select cm.fitmatch_measurement_code
  from product_row p
  join fitmatch_vnext.comparison_policies cp
    on cp.policy_code=p.effective_policy_code and cp.is_active
  join fitmatch_vnext.comparison_metrics cm
    on cm.comparison_policy_code=cp.policy_code
   and cm.metric_mode='CANONICAL' and cm.is_active
), size_diagnostics as (
  select ps.id product_size_id,ps.size_label,
    coalesce((canonical.payload->>'raw_measurement_count')::integer,0) raw_measurement_count,
    coalesce((canonical.payload->>'semantic_conflict_count')::integer,0) semantic_conflict_count,
    count(distinct pm.fitmatch_measurement_code) resolved_count
  from product_row p
  join fitmatch_vnext.product_variants pv on pv.product_id=p.id
  join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id
  cross join lateral (
    select fitmatch_vnext.canonical_measurements_for_size_with_context(
      ps.id,p_effective_classification
    ) payload
  ) canonical
  left join lateral jsonb_array_elements(canonical.payload->'measurements') measurement on true
  left join policy_metrics pm
    on pm.fitmatch_measurement_code=measurement->>'fitmatch_measurement_code'
  group by ps.id,ps.size_label,canonical.payload
), ready_sizes as (
  select * from size_diagnostics
  where semantic_conflict_count=0 and resolved_count>=1
)
select case when not exists(select 1 from product_row) then
  jsonb_build_object(
    'status','CLASSIFICATION_REQUIRED','ready',false,
    'reason_code','CLASSIFICATION_REQUIRED','reason','Unknown product',
    'readiness_version','fitmatch-vnext-readiness-group-only-v1',
    'inventory_ignored_for_readiness',true
  )
else (
  select jsonb_build_object(
    'product_id',p.id,
    'ready',p.effective_status='CONFIRMED'
      and coalesce((p.comparison_unit->>'eligible')::boolean,false)
      and exists(select 1 from ready_sizes),
    'status',case
      when p.effective_status<>'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
      when not coalesce((p.comparison_unit->>'eligible')::boolean,false) then 'NOT_APPLICABLE'
      when not exists(select 1 from policy_metrics) then 'POLICY_UNAVAILABLE'
      when not exists(select 1 from size_diagnostics) then 'NO_AVAILABLE_SIZE'
      when not exists(select 1 from size_diagnostics where raw_measurement_count>0)
        then 'NO_MEASUREMENT_DATA'
      when not exists(select 1 from size_diagnostics
        where semantic_conflict_count=0 and resolved_count>0)
        then 'INSUFFICIENT_MEASUREMENTS'
      else 'READY' end,
    'reason',case
      when p.effective_status<>'CONFIRMED' then 'Comparison group is required'
      when not coalesce((p.comparison_unit->>'eligible')::boolean,false)
        then p.comparison_unit->>'reason'
      when not exists(select 1 from policy_metrics) then 'No active comparison group policy metrics'
      when not exists(select 1 from size_diagnostics) then 'Product has no size rows'
      when not exists(select 1 from size_diagnostics where raw_measurement_count>0)
        then 'Product sizes have no raw measurement evidence'
      when not exists(select 1 from size_diagnostics
        where semantic_conflict_count=0 and resolved_count>0)
        then 'No semantically usable group-policy measurement'
      else 'Comparison group and measurement evidence are ready' end,
    'comparison_policy_code',p.effective_policy_code,
    'comparison_unit',p.comparison_unit,
    'ready_sizes',coalesce((select jsonb_agg(jsonb_build_object(
      'product_size_id',r.product_size_id,'size_label',r.size_label,
      'resolved_measurement_count',r.resolved_count,'required_any_count',0,
      'semantic_conflict_count',r.semantic_conflict_count,
      'availability_status','UNKNOWN'
    ) order by r.size_label,r.product_size_id) from ready_sizes r),'[]'::jsonb),
    'size_diagnostics',coalesce((select jsonb_agg(jsonb_build_object(
      'product_size_id',d.product_size_id,'size_label',d.size_label,
      'raw_measurement_count',d.raw_measurement_count,
      'policy_measurement_count',d.resolved_count,'required_any_count',0,
      'semantic_conflict_count',d.semantic_conflict_count,
      'availability_status','UNKNOWN'
    ) order by d.size_label,d.product_size_id) from size_diagnostics d),'[]'::jsonb),
    'readiness_version','fitmatch-vnext-readiness-group-only-v1',
    'inventory_ignored_for_readiness',true,'minimum_common',1,'required_any_min',0
  ) from product_row p
)
end
$function$;

create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb
language plpgsql
stable security invoker
set search_path=''
as $function$
declare
  grouped jsonb;
  effective_value jsonb;
  policy_value text;
begin
  grouped:=fitmatch_vnext.comparison_group_tuple(p_product_id,null);
  if nullif(btrim(grouped->>'group_code'),'') is not null then
    select gt.comparison_policy_code into policy_value
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code=grouped->>'garment_type_code'
      and gt.category_code=grouped->>'category_code' and gt.is_active;
    effective_value:=grouped || jsonb_build_object(
      'product_id',p_product_id,'classification_status','CONFIRMED',
      'comparison_policy_code',policy_value,'effective_source','CATEGORY_GROUP'
    );
  else
    select jsonb_build_object(
      'product_id',p.id,'classification_status',p.classification_status,
      'comparison_policy_code',gt.comparison_policy_code,
      'garment_type_code',p.garment_type_code,'audience_code',p.audience_code,
      'sleeve_length_code',p.sleeve_length_code,
      'lower_length_code',p.lower_length_code,'body_length_code',p.body_length_code,
      'effective_source','GLOBAL_CONFIRMED'
    ) into effective_value
    from fitmatch_vnext.products p
    left join fitmatch_vnext.garment_types gt on gt.garment_type_code=p.garment_type_code
    where p.id=p_product_id;
  end if;
  return fitmatch_vnext.product_measurement_readiness(
    p_product_id,coalesce(effective_value,'{}'::jsonb)
  );
end
$function$;

alter function fitmatch_vnext.product_measurement_readiness(uuid,jsonb) owner to postgres;
revoke all on function fitmatch_vnext.product_measurement_readiness(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function fitmatch_vnext.product_measurement_readiness(uuid,jsonb)
  to service_role;

commit;
