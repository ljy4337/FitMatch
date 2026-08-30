-- fitmatch_vnext P0 measurement resolver: one fail-closed semantic path.

create or replace function fitmatch_vnext.normalize_measurement_label(p_label text)
returns text
language sql
immutable
set search_path = ''
as $function$
    select nullif(lower(regexp_replace(btrim(coalesce(p_label, '')), '\s+', ' ', 'g')), '');
$function$;

create or replace function fitmatch_vnext.resolve_measurement(
    p_source_code text,
    p_parser_code text,
    p_raw_measurement_code text,
    p_raw_label text,
    p_garment_type_code text default null,
    p_fitmatch_category_code text default null,
    p_raw_value numeric default null
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with exact_candidate as (
    select sm.source_measurement_code, 2147483647 effective_priority,
           'EXACT_CODE' resolution_path
    from fitmatch_vnext.source_measurements sm
    where p_raw_measurement_code is not null
      and sm.source_measurement_code = p_raw_measurement_code
      and sm.source_code = p_source_code
      and sm.is_active and sm.is_comparable
), alias_candidates as (
    select a.source_measurement_code, a.priority::integer effective_priority,
           case when a.raw_code is not null then 'ALIAS_CODE' else 'ALIAS_LABEL' end
               resolution_path
    from fitmatch_vnext.source_measurement_aliases a
    where a.source_code = p_source_code
      and a.parser_code = p_parser_code
      and a.is_active and a.is_verified
      and (a.garment_type_code is null or a.garment_type_code = p_garment_type_code)
      and (a.fitmatch_category_code is null
           or a.fitmatch_category_code = p_fitmatch_category_code)
      and (
          (p_raw_measurement_code is not null and a.raw_code = p_raw_measurement_code)
          or
          (a.raw_code is null and a.normalized_label =
              fitmatch_vnext.normalize_measurement_label(p_raw_label))
      )
), candidates as (
    select * from exact_candidate
    union all
    select * from alias_candidates
    where not exists (select 1 from exact_candidate)
), top_candidates as (
    select c.*
    from candidates c
    where c.effective_priority = (select max(effective_priority) from candidates)
), candidate_summary as (
    select count(*) candidate_count,
           count(distinct source_measurement_code) outcome_count
    from top_candidates
), chosen as (
    select * from top_candidates order by source_measurement_code limit 1
), resolved as (
    select c.source_measurement_code, c.resolution_path,
           smm.fitmatch_measurement_code, smm.scale_factor, smm.offset_value,
           fm.canonical_unit_code, fm.canonical_basis_code,
           fm.representation_code, fm.body_region_code,
           s.candidate_count, s.outcome_count
    from candidate_summary s
    left join chosen c on true
    left join fitmatch_vnext.source_measurement_mappings smm
      on smm.source_measurement_code = c.source_measurement_code
     and smm.is_active and smm.is_verified
    left join fitmatch_vnext.fitmatch_measurements fm
      on fm.measurement_code = smm.fitmatch_measurement_code
     and fm.is_active
)
select jsonb_strip_nulls(jsonb_build_object(
    'resolution_status', case
        when candidate_count = 0 then 'UNMAPPED'
        when outcome_count > 1 then 'AMBIGUOUS'
        when fitmatch_measurement_code is null then 'MAPPING_REQUIRED'
        else 'RESOLVED' end,
    'resolution_path', case when outcome_count = 1 then resolution_path end,
    'source_measurement_code', case when outcome_count = 1
        then source_measurement_code end,
    'fitmatch_measurement_code', case when outcome_count = 1
        then fitmatch_measurement_code end,
    'canonical_value', case when outcome_count = 1 and fitmatch_measurement_code is not null
        and p_raw_value is not null then p_raw_value * scale_factor + offset_value end,
    'canonical_unit_code', case when outcome_count = 1 then canonical_unit_code end,
    'canonical_basis_code', case when outcome_count = 1 then canonical_basis_code end,
    'representation_code', case when outcome_count = 1 then representation_code end,
    'body_region_code', case when outcome_count = 1 then body_region_code end,
    'scale_factor', case when outcome_count = 1 then scale_factor end,
    'offset_value', case when outcome_count = 1 then offset_value end,
    'candidate_count', candidate_count,
    'resolver_version', 'fitmatch-vnext-measurement-resolver-v1'
))
from resolved;
$function$;

create or replace function fitmatch_vnext.canonical_measurements_for_size(
    p_product_size_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with raw_rows as (
    select m.*, p.source_code, p.garment_type_code, gt.category_code
    from fitmatch_vnext.product_size_measurements m
    join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where m.product_size_id = p_product_size_id
), decisions as (
    select r.*,
           fitmatch_vnext.resolve_measurement(
               r.source_code, r.parser_code, r.raw_code, r.raw_label,
               r.garment_type_code, r.category_code, r.raw_value
           ) decision
    from raw_rows r
), resolved as (
    select *, decision ->> 'fitmatch_measurement_code' canonical_code,
           (decision ->> 'canonical_value')::numeric canonical_value
    from decisions
    where decision ->> 'resolution_status' = 'RESOLVED'
), conflicts as (
    select canonical_code
    from resolved
    group by canonical_code
    having count(distinct canonical_value) > 1
)
select jsonb_build_object(
    'product_size_id', p_product_size_id,
    'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
    'measurements', coalesce((
        select jsonb_agg(
            jsonb_build_object(
                'product_size_measurement_id', r.id,
                'fitmatch_measurement_code', r.canonical_code,
                'value', r.canonical_value,
                'unit_code', r.decision ->> 'canonical_unit_code',
                'basis_code', r.decision ->> 'canonical_basis_code',
                'source_measurement_code', r.decision ->> 'source_measurement_code',
                'resolution_path', r.decision ->> 'resolution_path'
            ) order by r.canonical_code, r.id
        )
        from resolved r
        where not exists (select 1 from conflicts c where c.canonical_code = r.canonical_code)
    ), '[]'::jsonb),
    'unresolved_count', (select count(*) from decisions
        where decision ->> 'resolution_status' <> 'RESOLVED'),
    'semantic_conflict_count', (select count(*) from conflicts)
);
$function$;

revoke all on function fitmatch_vnext.normalize_measurement_label(text) from public;
revoke all on function fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric)
    from public;
revoke all on function fitmatch_vnext.canonical_measurements_for_size(uuid)
    from public;
grant execute on function fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric)
    to service_role;
grant execute on function fitmatch_vnext.canonical_measurements_for_size(uuid)
    to service_role;
