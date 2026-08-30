-- fitmatch_vnext P0-1 data remediation. Existing decisions are retained only
-- when an exact stored adjudication or a complete verified DIRECT mapping exists.

create temporary table vnext_invalid_direct on commit drop as
select m.*
from fitmatch_vnext.classification_signal_mappings m
left join fitmatch_vnext.garment_types gt
  on gt.garment_type_code = m.garment_type_code
where m.is_active and m.is_verified and m.resolution_mode = 'DIRECT'
  and (
      m.garment_type_code is null
      or gt.garment_type_code is null
      or not gt.is_active
      or (gt.uses_sleeve_length and
          (m.sleeve_length_code is null or m.sleeve_length_code = 'UNKNOWN'))
      or (not coalesce(gt.uses_sleeve_length, false) and m.sleeve_length_code is not null)
      or (gt.uses_lower_length and
          (m.lower_length_code is null or m.lower_length_code = 'UNKNOWN'))
      or (not coalesce(gt.uses_lower_length, false) and m.lower_length_code is not null)
      or (gt.uses_body_length and
          (m.body_length_code is null or m.body_length_code = 'UNKNOWN'))
      or (not coalesce(gt.uses_body_length, false) and m.body_length_code is not null)
  );

insert into fitmatch_vnext.mapping_remediation_audit (
    mapping_id, remediation_version, old_outcome, new_state, resolution_reason
)
select id, 'vnext-p0-20260829-v1',
       jsonb_build_object(
           'resolution_mode', resolution_mode,
           'garment_type_code', garment_type_code,
           'sleeve_length_code', sleeve_length_code,
           'lower_length_code', lower_length_code,
           'body_length_code', body_length_code,
           'priority', priority,
           'is_verified', is_verified,
           'is_active', is_active
       ),
       jsonb_build_object('is_active', false, 'replacement_mode', 'PRODUCT_REQUIRED'),
       'DIRECT mapping did not determine the garment required-axis tuple'
from vnext_invalid_direct
on conflict (mapping_id, remediation_version) do nothing;

update fitmatch_vnext.classification_signal_mappings m
set is_active = false,
    mapping_version = 'vnext-p0-20260829-v1'
from vnext_invalid_direct bad
where m.id = bad.id;

create temporary table vnext_product_required_groups on commit drop as
select source_signal_id, audience_code, max(priority)::smallint as priority
from vnext_invalid_direct
group by source_signal_id, audience_code;

update fitmatch_vnext.classification_signal_mappings m
set is_active = true,
    is_verified = true,
    priority = greatest(m.priority, g.priority),
    mapping_version = 'vnext-p0-20260829-v1'
from vnext_product_required_groups g
where m.source_signal_id = g.source_signal_id
  and m.audience_code = g.audience_code
  and m.resolution_mode = 'PRODUCT_REQUIRED'
  and m.garment_type_code is null
  and m.sleeve_length_code is null
  and m.lower_length_code is null
  and m.body_length_code is null;

insert into fitmatch_vnext.classification_signal_mappings (
    source_signal_id, audience_code, garment_type_code, resolution_mode,
    sleeve_length_code, lower_length_code, body_length_code, priority,
    is_verified, is_active, mapping_version, mapping_checksum
)
select g.source_signal_id, g.audience_code, null, 'PRODUCT_REQUIRED',
       null, null, null, g.priority, true, true,
       'vnext-p0-20260829-v1', repeat('0', 64)
from vnext_product_required_groups g
where not exists (
    select 1
    from fitmatch_vnext.classification_signal_mappings m
    where m.source_signal_id = g.source_signal_id
      and m.audience_code = g.audience_code
      and m.resolution_mode = 'PRODUCT_REQUIRED'
      and m.garment_type_code is null
      and m.sleeve_length_code is null
      and m.lower_length_code is null
      and m.body_length_code is null
);

-- Any remaining equal-top outcome ambiguity is converted to one fail-closed
-- PRODUCT_REQUIRED outcome. The prior rows remain present but inactive.
create temporary table vnext_conflict_groups on commit drop as
with ranked as (
    select m.*,
           max(priority) over (partition by source_signal_id, audience_code) max_priority
    from fitmatch_vnext.classification_signal_mappings m
    where is_active and is_verified
), conflicting as (
    select source_signal_id, audience_code, max_priority
    from ranked
    where priority = max_priority
    group by source_signal_id, audience_code, max_priority
    having count(distinct concat_ws('|', resolution_mode,
        coalesce(garment_type_code, '∅'), coalesce(sleeve_length_code, '∅'),
        coalesce(lower_length_code, '∅'), coalesce(body_length_code, '∅'))) > 1
)
select * from conflicting;

insert into fitmatch_vnext.mapping_remediation_audit (
    mapping_id, remediation_version, old_outcome, new_state, resolution_reason
)
select m.id, 'vnext-p0-20260829-v1',
       jsonb_build_object(
           'resolution_mode', m.resolution_mode,
           'garment_type_code', m.garment_type_code,
           'sleeve_length_code', m.sleeve_length_code,
           'lower_length_code', m.lower_length_code,
           'body_length_code', m.body_length_code,
           'priority', m.priority,
           'is_verified', m.is_verified,
           'is_active', m.is_active
       ),
       jsonb_build_object('is_active', false, 'replacement_mode', 'PRODUCT_REQUIRED'),
       'Equal-top verified mappings had different outcomes'
from fitmatch_vnext.classification_signal_mappings m
join vnext_conflict_groups g
  on g.source_signal_id = m.source_signal_id
 and g.audience_code = m.audience_code
 and g.max_priority = m.priority
where m.is_active and m.is_verified
on conflict (mapping_id, remediation_version) do nothing;

update fitmatch_vnext.classification_signal_mappings m
set is_active = false,
    mapping_version = 'vnext-p0-20260829-v1'
from vnext_conflict_groups g
where m.source_signal_id = g.source_signal_id
  and m.audience_code = g.audience_code
  and m.priority = g.max_priority
  and m.is_active and m.is_verified;

update fitmatch_vnext.classification_signal_mappings m
set is_active = true,
    is_verified = true,
    priority = greatest(m.priority, g.max_priority),
    mapping_version = 'vnext-p0-20260829-v1'
from vnext_conflict_groups g
where m.source_signal_id = g.source_signal_id
  and m.audience_code = g.audience_code
  and m.resolution_mode = 'PRODUCT_REQUIRED'
  and m.garment_type_code is null
  and m.sleeve_length_code is null
  and m.lower_length_code is null
  and m.body_length_code is null;

insert into fitmatch_vnext.classification_signal_mappings (
    source_signal_id, audience_code, garment_type_code, resolution_mode,
    sleeve_length_code, lower_length_code, body_length_code, priority,
    is_verified, is_active, mapping_version, mapping_checksum
)
select g.source_signal_id, g.audience_code, null, 'PRODUCT_REQUIRED',
       null, null, null, g.max_priority, true, true,
       'vnext-p0-20260829-v1', repeat('0', 64)
from vnext_conflict_groups g
where not exists (
    select 1 from fitmatch_vnext.classification_signal_mappings m
    where m.source_signal_id = g.source_signal_id
      and m.audience_code = g.audience_code
      and m.resolution_mode = 'PRODUCT_REQUIRED'
      and m.garment_type_code is null
      and m.sleeve_length_code is null
      and m.lower_length_code is null
      and m.body_length_code is null
);

-- PRODUCT_EXACT is an existing-authority signal kind, not a parallel authority.
alter table fitmatch_vnext.source_classification_signals
    drop constraint if exists source_classification_signals_kind_chk;
alter table fitmatch_vnext.source_classification_signals
    add constraint source_classification_signals_kind_chk
    check (signal_kind in (
        'CATEGORY', 'SECTION', 'FAMILY', 'SUBFAMILY', 'PRODUCT_TYPE',
        'PRODUCT_STRUCTURE', 'PRODUCT_EXACT', 'SIZE_TYPE'
    ));

create temporary table vnext_trusted_exact_products on commit drop as
select p.id, p.source_code, p.source_product_key, p.product_name, p.audience_code,
       p.product_structure_code, p.garment_type_code, p.sleeve_length_code,
       p.lower_length_code, p.body_length_code, p.source_extra,
       jsonb_build_object(
           'review_zero_resolution', p.source_extra ->> '_review_zero_resolution',
           'review_zero_basis', p.source_extra ->> '_review_zero_basis',
           'bottom_reclassification_basis', p.source_extra ->> '_bottom_reclassification_basis',
           'mapping_status', p.source_extra ->> 'mapping_status',
           'legacy_category_id', p.source_extra ->> 'legacy_path_alias_external_category_id',
           'legacy_input_fingerprint', p.source_extra ->> '_legacy_input_fingerprint'
       ) as evidence
from fitmatch_vnext.products p
join fitmatch_vnext.garment_types gt
  on gt.garment_type_code = p.garment_type_code and gt.is_active
where p.classification_status = 'CONFIRMED'
  and (fitmatch_vnext.classification_tuple_validation(
       p.garment_type_code, p.product_structure_code, p.audience_code,
       p.sleeve_length_code, p.lower_length_code, p.body_length_code
      ) ->> 'valid')::boolean
  and (
      (p.source_extra ->> '_review_zero_resolution' like 'exact_product_adjudication%'
       and p.source_extra ? '_review_zero_basis')
      or
      (p.source_extra ->> '_review_zero_resolution' = 'legacy_migration_exact_v1'
       and (p.source_extra ? 'legacy_path_alias_external_category_id'
            or p.source_extra ? '_bottom_reclassification_basis'
            or p.source_extra ->> 'mapping_status' like '%LOCKED%'))
  );

insert into fitmatch_vnext.source_classification_signals (
    source_code, signal_kind, external_key, external_id, audience_code,
    signal_name, signal_path, is_active
)
select p.source_code, 'PRODUCT_EXACT', p.source_product_key, p.source_product_key,
       p.audience_code, p.product_name, 'product:' || p.source_product_key, true
from vnext_trusted_exact_products p
on conflict (source_code, signal_kind, external_key, audience_code)
do update set
    external_id = excluded.external_id,
    signal_name = excluded.signal_name,
    signal_path = excluded.signal_path,
    is_active = true,
    last_seen_at = now();

update fitmatch_vnext.product_classification_signals pcs
set is_primary = false
from vnext_trusted_exact_products p
where pcs.product_id = p.id and pcs.is_primary;

insert into fitmatch_vnext.product_classification_signals (
    product_id, source_signal_id, is_primary, evidence_order, observed_at
)
select p.id, s.id, true, 0, now()
from vnext_trusted_exact_products p
join fitmatch_vnext.source_classification_signals s
  on s.source_code = p.source_code
 and s.signal_kind = 'PRODUCT_EXACT'
 and s.external_key = p.source_product_key
 and s.audience_code = p.audience_code
on conflict (product_id, source_signal_id)
do update set is_primary = true, evidence_order = 0, observed_at = now();

insert into fitmatch_vnext.classification_signal_mappings (
    source_signal_id, audience_code, garment_type_code, resolution_mode,
    sleeve_length_code, lower_length_code, body_length_code, priority,
    is_verified, is_active, mapping_version, mapping_checksum
)
select s.id, p.audience_code, p.garment_type_code, 'DIRECT',
       p.sleeve_length_code, p.lower_length_code, p.body_length_code,
       1000, true, true, 'vnext-product-exact-20260829-v1', repeat('0', 64)
from vnext_trusted_exact_products p
join fitmatch_vnext.source_classification_signals s
  on s.source_code = p.source_code
 and s.signal_kind = 'PRODUCT_EXACT'
 and s.external_key = p.source_product_key
 and s.audience_code = p.audience_code
where not exists (
    select 1 from fitmatch_vnext.classification_signal_mappings m
    where m.source_signal_id = s.id
      and m.audience_code = p.audience_code
      and m.resolution_mode = 'DIRECT'
      and m.garment_type_code = p.garment_type_code
      and m.sleeve_length_code is not distinct from p.sleeve_length_code
      and m.lower_length_code is not distinct from p.lower_length_code
      and m.body_length_code is not distinct from p.body_length_code
);

create temporary table vnext_confirmed_remediation on commit drop as
select p.*,
       case when p.product_structure_code in ('SET', 'MULTIPACK')
            then 'NOT_APPLICABLE' else 'REVIEW_REQUIRED' end as new_status,
       case
         when p.product_structure_code in ('SET', 'MULTIPACK')
           then 'Retailer structure evidence marks a non-single product'
         when p.product_structure_code = 'UNKNOWN'
           then 'Product structure is not verified as SINGLE'
         when not gt.is_active
           then 'Garment type is inactive or unsupported'
         when not (fitmatch_vnext.classification_tuple_validation(
             p.garment_type_code, p.product_structure_code, p.audience_code,
             p.sleeve_length_code, p.lower_length_code, p.body_length_code
           ) ->> 'valid')::boolean
           then 'Required canonical tuple field is missing or invalid'
         else 'No verified exact-product authority for the current tuple'
       end as resolution_reason
from fitmatch_vnext.products p
left join fitmatch_vnext.garment_types gt on gt.garment_type_code = p.garment_type_code
where p.classification_status = 'CONFIRMED'
  and not exists (select 1 from vnext_trusted_exact_products keep where keep.id = p.id);

insert into fitmatch_vnext.classification_remediation_audit (
    product_id, remediation_version, old_status, old_tuple, evidence_source,
    selected_mapping_id, new_status, new_tuple, resolution_reason
)
select p.id, 'vnext-p0-20260829-v1', p.classification_status,
       jsonb_build_object(
           'product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code,
           'garment_type_code', p.garment_type_code,
           'sleeve_length_code', p.sleeve_length_code,
           'lower_length_code', p.lower_length_code,
           'body_length_code', p.body_length_code
       ),
       jsonb_build_object(
           'classification_source', p.classification_source,
           'source_extra', p.source_extra,
           'primary_signal_ids', coalesce((
               select jsonb_agg(pcs.source_signal_id order by pcs.evidence_order, pcs.source_signal_id)
               from fitmatch_vnext.product_classification_signals pcs
               where pcs.product_id = p.id and pcs.is_primary
           ), '[]'::jsonb)
       ),
       null, p.new_status,
       jsonb_build_object(
           'product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code,
           'garment_type_code', null,
           'sleeve_length_code', null,
           'lower_length_code', null,
           'body_length_code', null
       ),
       p.resolution_reason
from vnext_confirmed_remediation p
on conflict (product_id, remediation_version) do nothing;

update fitmatch_vnext.products p
set classification_status = r.new_status,
    garment_type_code = null,
    sleeve_length_code = null,
    lower_length_code = null,
    body_length_code = null,
    classification_source = 'BACKEND',
    primary_source_signal_id = null,
    classification_mapping_id = null,
    resolution_mode = r.new_status,
    resolver_version = 'fitmatch-vnext-resolver-v1',
    input_fingerprint = encode(extensions.digest(
        concat_ws('|', p.source_code, p.source_product_key, p.audience_code,
            p.product_structure_code, coalesce(p.source_extra ->> '_legacy_input_fingerprint', '∅')),
        'sha256'), 'hex'),
    evidence_fingerprint = encode(extensions.digest(r.resolution_reason, 'sha256'), 'hex'),
    classification_evidence = jsonb_build_object(
        'remediation_version', 'vnext-p0-20260829-v1',
        'prior_tuple_preserved_in', 'classification_remediation_audit'
    ),
    classification_reason = r.resolution_reason,
    classified_at = now()
from vnext_confirmed_remediation r
where p.id = r.id;

update fitmatch_vnext.products p
set primary_source_signal_id = s.id,
    classification_mapping_id = m.id,
    resolution_mode = 'DIRECT',
    resolver_version = 'fitmatch-vnext-resolver-v1',
    input_fingerprint = encode(extensions.digest(
        concat_ws('|', p.source_code, p.source_product_key, p.audience_code,
            p.product_structure_code, s.id::text, m.mapping_checksum), 'sha256'), 'hex'),
    evidence_fingerprint = encode(extensions.digest(t.evidence::text, 'sha256'), 'hex'),
    classification_evidence = t.evidence || jsonb_build_object(
        'source_signal_id', s.id,
        'mapping_id', m.id,
        'mapping_checksum', m.mapping_checksum,
        'authority', 'PRODUCT_EXACT'
    ),
    classification_reason = 'Verified stored exact-product adjudication',
    classification_source = 'SOURCE_DIRECT',
    classified_at = now()
from vnext_trusted_exact_products t
join fitmatch_vnext.source_classification_signals s
  on s.source_code = t.source_code
 and s.signal_kind = 'PRODUCT_EXACT'
 and s.external_key = t.source_product_key
 and s.audience_code = t.audience_code
join fitmatch_vnext.classification_signal_mappings m
  on m.source_signal_id = s.id
 and m.audience_code = t.audience_code
 and m.resolution_mode = 'DIRECT'
 and m.is_active and m.is_verified
where p.id = t.id;

do $verify$
begin
    if exists (
        select 1
        from fitmatch_vnext.classification_signal_mappings m
        left join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = m.garment_type_code
        where m.is_active and m.is_verified and m.resolution_mode = 'DIRECT'
          and (m.garment_type_code is null or gt.garment_type_code is null or not gt.is_active
            or (gt.uses_sleeve_length and (m.sleeve_length_code is null or m.sleeve_length_code = 'UNKNOWN'))
            or (not gt.uses_sleeve_length and m.sleeve_length_code is not null)
            or (gt.uses_lower_length and (m.lower_length_code is null or m.lower_length_code = 'UNKNOWN'))
            or (not gt.uses_lower_length and m.lower_length_code is not null)
            or (gt.uses_body_length and (m.body_length_code is null or m.body_length_code = 'UNKNOWN'))
            or (not gt.uses_body_length and m.body_length_code is not null))
    ) then
        raise exception 'P0 mapping remediation left an invalid DIRECT mapping';
    end if;

    if exists (
        select 1 from fitmatch_vnext.products p
        where p.classification_status = 'CONFIRMED'
          and (not (fitmatch_vnext.classification_tuple_validation(
              p.garment_type_code, p.product_structure_code, p.audience_code,
              p.sleeve_length_code, p.lower_length_code, p.body_length_code
          ) ->> 'valid')::boolean
          or p.primary_source_signal_id is null
          or p.classification_mapping_id is null)
    ) then
        raise exception 'P0 product remediation left an invalid or unproven CONFIRMED row';
    end if;
end
$verify$;
