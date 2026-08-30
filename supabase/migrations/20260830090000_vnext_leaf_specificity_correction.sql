-- Purpose: stop a verified broad PRODUCT_REQUIRED ancestor from competing
-- with an equally-ranked verified DIRECT descendant carried by the same
-- product. This is a hierarchy-only correction; names, paths, and
-- evidence_order are not used as specificity authority.

create or replace function fitmatch_vnext.classification_decision(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with recursive product_row as (
    select p.*
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key
), evidence as (
    select p.id product_id, pcs.source_signal_id, pcs.evidence_order,
           ss.signal_kind, ss.external_key,
           case ss.signal_kind
             when 'PRODUCT_EXACT' then 600
             when 'PRODUCT_STRUCTURE' then 500
             when 'PRODUCT_TYPE' then 400
             when 'SUBFAMILY' then 300
             when 'FAMILY' then 250
             when 'CATEGORY' then 200
             when 'SECTION' then 150
             else 100
           end as evidence_rank
    from product_row p
    join fitmatch_vnext.product_classification_signals pcs
      on pcs.product_id = p.id
    join fitmatch_vnext.source_classification_signals ss
      on ss.id = pcs.source_signal_id
     and ss.source_code = p.source_code
     and ss.is_active
), raw_candidates as (
    select e.*, m.id mapping_id, m.resolution_mode, m.garment_type_code,
           m.sleeve_length_code, m.lower_length_code, m.body_length_code,
           m.priority, m.mapping_version, m.mapping_checksum
    from evidence e
    join product_row p on p.id = e.product_id
    join fitmatch_vnext.classification_signal_mappings m
      on m.source_signal_id = e.source_signal_id
     and m.is_active and m.is_verified
     and (m.audience_code = 'ANY' or m.audience_code = p.audience_code)
), signal_ancestry(descendant_id, ancestor_id, depth) as (
    select s.id, s.parent_signal_id, 1
    from fitmatch_vnext.source_classification_signals s
    where s.parent_signal_id is not null
    union all
    select a.descendant_id, s.parent_signal_id, a.depth + 1
    from signal_ancestry a
    join fitmatch_vnext.source_classification_signals s
      on s.id = a.ancestor_id
    where s.parent_signal_id is not null
      and a.depth < 16
), pruned as (
    select count(*)::integer pruned_ancestor_count
    from raw_candidates c
    where exists (
        select 1
        from raw_candidates d
        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id
        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
), candidates as (
    select c.*,
           max(c.evidence_rank) over () as max_evidence_rank
    from raw_candidates c
    where not exists (
        select 1
        from raw_candidates d
        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id
        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
), ranked as (
    select c.*, max(priority) over () as max_priority
    from candidates c
    where evidence_rank = max_evidence_rank
), top_candidates as (
    select r.*
    from ranked r
    where priority = max_priority
), summary as (
    select count(*) candidate_count,
           count(distinct concat_ws('|', resolution_mode,
               coalesce(garment_type_code, '∅'),
               coalesce(sleeve_length_code, '∅'),
               coalesce(lower_length_code, '∅'),
               coalesce(body_length_code, '∅'))) outcome_count,
           (select pruned_ancestor_count from pruned) pruned_ancestor_count
    from top_candidates
), chosen as (
    select t.*
    from top_candidates t
    order by t.evidence_order, t.source_signal_id, t.mapping_id
    limit 1
), resolved as (
    select p.*,
           c.source_signal_id,
           c.mapping_id,
           c.resolution_mode mapping_resolution_mode,
           c.garment_type_code mapped_garment_type_code,
           c.sleeve_length_code mapped_sleeve_length_code,
           c.lower_length_code mapped_lower_length_code,
           c.body_length_code mapped_body_length_code,
           c.mapping_version,
           c.mapping_checksum,
           coalesce(s.candidate_count, 0) candidate_count,
           coalesce(s.outcome_count, 0) outcome_count,
           coalesce(s.pruned_ancestor_count, 0) pruned_ancestor_count
    from product_row p
    left join summary s on true
    left join chosen c on true
), decision as (
    select r.*,
      case
        when r.product_structure_code in ('SET', 'MULTIPACK')
          then 'NOT_APPLICABLE'
        when r.product_structure_code <> 'SINGLE' then 'REVIEW_REQUIRED'
        when r.candidate_count = 0 then 'REVIEW_REQUIRED'
        when r.outcome_count > 1 then 'REVIEW_REQUIRED'
        when r.mapping_resolution_mode = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
        when r.mapping_resolution_mode = 'DIRECT'
          and (fitmatch_vnext.classification_tuple_validation(
              r.mapped_garment_type_code, r.product_structure_code,
              r.audience_code, r.mapped_sleeve_length_code,
              r.mapped_lower_length_code, r.mapped_body_length_code
          ) ->> 'valid')::boolean then 'CONFIRMED'
        else 'REVIEW_REQUIRED'
      end decision_status,
      case
        when r.product_structure_code in ('SET', 'MULTIPACK')
          then 'Retailer structure is SET or MULTIPACK'
        when r.product_structure_code <> 'SINGLE'
          then 'Product structure is not verified as SINGLE'
        when r.candidate_count = 0 then 'No active verified mapping candidate'
        when r.outcome_count > 1
          then 'Equal-top candidates have different outcomes'
        when r.mapping_resolution_mode = 'NOT_APPLICABLE'
          then 'Mapping is NOT_APPLICABLE'
        when r.mapping_resolution_mode = 'DIRECT'
          then 'Complete verified DIRECT mapping'
        when r.mapping_resolution_mode = 'PRODUCT_REQUIRED'
          then 'Product-exact verified evidence is required'
        else 'Mapping requires review'
      end decision_reason
    from resolved r
)
select case when not exists (select 1 from product_row) then
    jsonb_build_object(
        'found', false,
        'classification_status', 'REVIEW_REQUIRED',
        'resolution_mode', 'REVIEW_REQUIRED',
        'reason', 'Unknown source product identity',
        'resolver_version', 'fitmatch-vnext-resolver-v2'
    )
else (
    select jsonb_strip_nulls(jsonb_build_object(
        'found', true,
        'product_id', d.id,
        'source_code', d.source_code,
        'source_product_key', d.source_product_key,
        'classification_status', d.decision_status,
        'resolution_mode', case
            when d.decision_status = 'CONFIRMED' then 'DIRECT'
            when d.decision_status = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
            else coalesce(d.mapping_resolution_mode, 'REVIEW_REQUIRED') end,
        'garment_type_code', case when d.decision_status = 'CONFIRMED'
            then d.mapped_garment_type_code end,
        'product_structure_code', d.product_structure_code,
        'audience_code', d.audience_code,
        'sleeve_length_code', case when d.decision_status = 'CONFIRMED'
            then d.mapped_sleeve_length_code end,
        'lower_length_code', case when d.decision_status = 'CONFIRMED'
            then d.mapped_lower_length_code end,
        'body_length_code', case when d.decision_status = 'CONFIRMED'
            then d.mapped_body_length_code end,
        'primary_source_signal_id', d.source_signal_id,
        'mapping_id', d.mapping_id,
        'mapping_version', d.mapping_version,
        'mapping_checksum', d.mapping_checksum,
        'hierarchy_pruned_ancestor_count', d.pruned_ancestor_count,
        'reason', d.decision_reason,
        'resolver_version', 'fitmatch-vnext-resolver-v2',
        'input_fingerprint', encode(extensions.digest(
            concat_ws('|', d.source_code, d.source_product_key,
                d.audience_code, d.product_structure_code,
                coalesce(d.source_signal_id::text, '∅'),
                coalesce(d.mapping_checksum, '∅'),
                'fitmatch-vnext-resolver-v2'),
            'sha256'), 'hex')
    )) from decision d
)
end;
$function$;

revoke all on function fitmatch_vnext.classification_decision(text,text)
    from public;
grant execute on function fitmatch_vnext.classification_decision(text,text)
    to anon, authenticated, service_role;

drop table if exists pg_temp.vnext_leaf_specificity_decisions;
create temporary table vnext_leaf_specificity_decisions as
select p.id, p.classification_status old_status,
       fitmatch_vnext.classification_decision(
           p.source_code, p.source_product_key
       ) decision
from fitmatch_vnext.products p;

do $preflight$
begin
    if exists (
        select 1 from vnext_leaf_specificity_decisions d
        where d.old_status = 'CONFIRMED'
          and d.decision ->> 'classification_status' <> 'CONFIRMED'
    ) then
        raise exception 'Leaf-specificity correction would change a CONFIRMED product';
    end if;
    if exists (
        select 1 from vnext_leaf_specificity_decisions d
        where d.old_status = 'NOT_APPLICABLE'
          and d.decision ->> 'classification_status' <> 'NOT_APPLICABLE'
    ) then
        raise exception 'Leaf-specificity correction would change a NOT_APPLICABLE product';
    end if;
    if exists (
        select 1 from vnext_leaf_specificity_decisions d
        join fitmatch_vnext.products p on p.id = d.id
        where d.old_status = 'REVIEW_REQUIRED'
          and d.decision ->> 'classification_status' = 'CONFIRMED'
          and (
              coalesce((d.decision ->> 'hierarchy_pruned_ancestor_count')::integer, 0) = 0
              or not (fitmatch_vnext.classification_tuple_validation(
                  d.decision ->> 'garment_type_code', p.product_structure_code,
                  p.audience_code, d.decision ->> 'sleeve_length_code',
                  d.decision ->> 'lower_length_code',
                  d.decision ->> 'body_length_code'
              ) ->> 'valid')::boolean
          )
    ) then
        raise exception 'Leaf-specificity correction found an unsafe confirmation';
    end if;
end
$preflight$;

insert into fitmatch_vnext.classification_remediation_audit (
    product_id, remediation_version, old_status, old_tuple, evidence_source,
    selected_mapping_id, new_status, new_tuple, resolution_reason
)
select p.id, 'vnext-leaf-specificity-20260830-v1', p.classification_status,
       jsonb_build_object(
           'product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code,
           'garment_type_code', p.garment_type_code,
           'sleeve_length_code', p.sleeve_length_code,
           'lower_length_code', p.lower_length_code,
           'body_length_code', p.body_length_code
       ),
       d.decision,
       (d.decision ->> 'mapping_id')::uuid,
       'CONFIRMED',
       jsonb_build_object(
           'product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code,
           'garment_type_code', d.decision ->> 'garment_type_code',
           'sleeve_length_code', d.decision ->> 'sleeve_length_code',
           'lower_length_code', d.decision ->> 'lower_length_code',
           'body_length_code', d.decision ->> 'body_length_code'
       ),
       'Verified DIRECT descendant supersedes its equally-ranked PRODUCT_REQUIRED ancestor'
from vnext_leaf_specificity_decisions d
join fitmatch_vnext.products p on p.id = d.id
where d.old_status = 'REVIEW_REQUIRED'
  and d.decision ->> 'classification_status' = 'CONFIRMED'
on conflict (product_id, remediation_version) do nothing;

update fitmatch_vnext.products p
set classification_status = 'CONFIRMED',
    garment_type_code = d.decision ->> 'garment_type_code',
    sleeve_length_code = d.decision ->> 'sleeve_length_code',
    lower_length_code = d.decision ->> 'lower_length_code',
    body_length_code = d.decision ->> 'body_length_code',
    classification_source = 'SOURCE_DIRECT',
    primary_source_signal_id = (d.decision ->> 'primary_source_signal_id')::uuid,
    classification_mapping_id = (d.decision ->> 'mapping_id')::uuid,
    resolution_mode = 'DIRECT',
    resolver_version = d.decision ->> 'resolver_version',
    input_fingerprint = d.decision ->> 'input_fingerprint',
    evidence_fingerprint = encode(extensions.digest(d.decision::text, 'sha256'), 'hex'),
    classification_evidence = d.decision,
    classification_reason = d.decision ->> 'reason',
    classified_at = now()
from vnext_leaf_specificity_decisions d
where p.id = d.id
  and d.old_status = 'REVIEW_REQUIRED'
  and d.decision ->> 'classification_status' = 'CONFIRMED';

do $verify$
begin
    if exists (
        select 1 from fitmatch_vnext.products p
        where p.classification_status = 'CONFIRMED'
          and not (fitmatch_vnext.classification_tuple_validation(
              p.garment_type_code, p.product_structure_code, p.audience_code,
              p.sleeve_length_code, p.lower_length_code,
              p.body_length_code
          ) ->> 'valid')::boolean
    ) then
        raise exception 'Leaf-specificity correction left an invalid CONFIRMED tuple';
    end if;
end
$verify$;

drop table pg_temp.vnext_leaf_specificity_decisions;
