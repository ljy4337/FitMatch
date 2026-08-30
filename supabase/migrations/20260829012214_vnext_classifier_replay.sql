-- Align every current product with the deterministic resolver result.

create temporary table vnext_replay_decisions on commit drop as
select p.id, fitmatch_vnext.classification_decision(
    p.source_code, p.source_product_key
) as decision
from fitmatch_vnext.products p;

insert into fitmatch_vnext.classification_remediation_audit (
    product_id, remediation_version, old_status, old_tuple, evidence_source,
    selected_mapping_id, new_status, new_tuple, resolution_reason
)
select p.id, 'vnext-replay-20260829-v1', p.classification_status,
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
       d.decision ->> 'classification_status',
       jsonb_build_object(
           'product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code,
           'garment_type_code', d.decision ->> 'garment_type_code',
           'sleeve_length_code', d.decision ->> 'sleeve_length_code',
           'lower_length_code', d.decision ->> 'lower_length_code',
           'body_length_code', d.decision ->> 'body_length_code'
       ),
       d.decision ->> 'reason'
from fitmatch_vnext.products p
join vnext_replay_decisions d on d.id = p.id
where p.classification_status <> d.decision ->> 'classification_status'
on conflict (product_id, remediation_version) do nothing;

update fitmatch_vnext.products p
set classification_status = d.decision ->> 'classification_status',
    garment_type_code = d.decision ->> 'garment_type_code',
    sleeve_length_code = d.decision ->> 'sleeve_length_code',
    lower_length_code = d.decision ->> 'lower_length_code',
    body_length_code = d.decision ->> 'body_length_code',
    classification_source = case
        when d.decision ->> 'classification_status' = 'CONFIRMED'
            then 'SOURCE_DIRECT' else 'BACKEND' end,
    primary_source_signal_id = (d.decision ->> 'primary_source_signal_id')::uuid,
    classification_mapping_id = (d.decision ->> 'mapping_id')::uuid,
    resolution_mode = d.decision ->> 'resolution_mode',
    resolver_version = d.decision ->> 'resolver_version',
    input_fingerprint = d.decision ->> 'input_fingerprint',
    evidence_fingerprint = encode(extensions.digest(d.decision::text, 'sha256'), 'hex'),
    classification_evidence = d.decision,
    classification_reason = d.decision ->> 'reason',
    classified_at = now()
from vnext_replay_decisions d
where p.id = d.id
  and p.classification_status <> d.decision ->> 'classification_status';

do $verify$
begin
    if exists (
        select 1
        from fitmatch_vnext.products p
        where p.classification_status <>
              fitmatch_vnext.classification_decision(
                  p.source_code, p.source_product_key
              ) ->> 'classification_status'
    ) then
        raise exception 'Current product replay did not converge';
    end if;
end
$verify$;
