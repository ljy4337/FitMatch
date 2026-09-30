-- Purpose: recover an already verified exact-product garment authority when
-- vNext still needs one bounded axis choice. Global authority stays
-- REVIEW_REQUIRED; only an authenticated USER_EXPLICIT choice can proceed.

begin;

do $preflight$
declare
    recovery_definition text;
begin
    if to_regclass('fitmatch_catalog.current_product_classifications') is null
       or to_regprocedure(
           'fitmatch_vnext.product_comparison_unit_decision(uuid)'
       ) is null
       or to_regprocedure(
           'fitmatch_vnext.comparison_unit_tuple_validation(text,text,text,text,text,text,text)'
       ) is null
       or to_regprocedure(
           'fitmatch_vnext.classification_recovery_options(uuid)'
       ) is null then
        raise exception 'Required exact-product recovery authority is missing';
    end if;

    recovery_definition := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );
    if position('product_comparison_unit_decision' in recovery_definition) = 0
       or position('comparison_unit_tuple_validation' in recovery_definition) = 0
       or position('fitmatch-vnext-recovery-candidates-v2-comparison-unit'
                   in recovery_definition) = 0 then
        raise exception 'Unexpected classification recovery preimage';
    end if;
end
$preflight$;

create or replace function fitmatch_vnext.exact_product_authority_recovery_options(
    p_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
with product_row as (
    select p.*,
           fitmatch_vnext.product_comparison_unit_decision(p.id) comparison_unit
    from fitmatch_vnext.products p
    where p.id = p_product_id
      and p.classification_status = 'REVIEW_REQUIRED'
), legacy_authority as (
    select legacy.classification_id, legacy.detail_code garment_type_code,
           gt.category_code, gt.comparison_policy_code, gt.display_name,
           gt.sort_order
    from product_row p
    join fitmatch_catalog.current_product_classifications legacy
      on lower(legacy.source) = lower(p.source_code)
     and legacy.external_product_id = p.source_product_key
    join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = legacy.detail_code
     and gt.is_active
    where lower(legacy.classification_status) = 'confirmed'
      and coalesce(legacy.confidence, 0) = 1
      and coalesce((legacy.evidence ->> 'exact_product_authority')::boolean,
                   false)
      and legacy.evidence ->> 'authority_status' = 'verified'
      and legacy.comparison_family_code = gt.comparison_policy_code
      and coalesce((p.comparison_unit ->> 'eligible')::boolean, false)
), unique_authority as (
    select min(classification_id::text)::uuid classification_id,
           min(garment_type_code) garment_type_code,
           min(category_code) category_code,
           min(comparison_policy_code) comparison_policy_code,
           min(display_name) display_name,
           min(sort_order) sort_order
    from legacy_authority
    having count(*) > 0
       and count(distinct garment_type_code) = 1
       and count(distinct category_code) = 1
       and count(distinct comparison_policy_code) = 1
), provider_axis_templates as (
    select distinct on (
        coalesce(mapping.sleeve_length_code, '∅'),
        coalesce(mapping.lower_length_code, '∅'),
        coalesce(mapping.body_length_code, '∅')
    )
        mapping.id mapping_id,
        mapping.mapping_checksum,
        authority.*,
        mapping.sleeve_length_code,
        mapping.lower_length_code,
        mapping.body_length_code
    from unique_authority authority
    join product_row p on true
    join fitmatch_vnext.classification_signal_mappings mapping
      on mapping.garment_type_code = authority.garment_type_code
     and mapping.is_verified
     and mapping.resolution_mode = 'DIRECT'
    join fitmatch_vnext.source_classification_signals signal
      on signal.id = mapping.source_signal_id
     and signal.source_code = p.source_code
    where coalesce((fitmatch_vnext.comparison_unit_tuple_validation(
        authority.garment_type_code,
        p.product_structure_code,
        p.comparison_unit ->> 'measurement_contract',
        p.audience_code,
        mapping.sleeve_length_code,
        mapping.lower_length_code,
        mapping.body_length_code
    ) ->> 'valid')::boolean, false)
    order by coalesce(mapping.sleeve_length_code, '∅'),
             coalesce(mapping.lower_length_code, '∅'),
             coalesce(mapping.body_length_code, '∅'),
             mapping.is_active desc, mapping.priority desc, mapping.id
), fingerprinted as (
    select template.*,
           encode(extensions.digest(concat_ws('|',
               p.id::text, p.input_fingerprint, p.evidence_fingerprint,
               p.resolver_version, template.classification_id::text,
               template.mapping_id::text, template.mapping_checksum,
               template.category_code, template.garment_type_code,
               coalesce(template.sleeve_length_code, '∅'),
               coalesce(template.lower_length_code, '∅'),
               coalesce(template.body_length_code, '∅'),
               template.comparison_policy_code,
               'fitmatch-vnext-recovery-candidates-v3-exact-product'
           ), 'sha256'), 'hex') candidate_fingerprint
    from provider_axis_templates template
    join product_row p on true
), aggregate_value as (
    select count(*)::integer candidate_count,
           count(distinct coalesce(sleeve_length_code, '∅'))::integer
               sleeve_count,
           count(distinct coalesce(lower_length_code, '∅'))::integer
               lower_count,
           count(distinct coalesce(body_length_code, '∅'))::integer
               body_count,
           min(category_code) category_code,
           min(garment_type_code) garment_type_code,
           min(comparison_policy_code) comparison_policy_code,
           coalesce(jsonb_agg(jsonb_build_object(
               'candidate_id', candidate_fingerprint,
               'candidate_fingerprint', candidate_fingerprint,
               'display_name', display_name,
               'category_code', category_code,
               'garment_type_code', garment_type_code,
               'sleeve_length_code', sleeve_length_code,
               'lower_length_code', lower_length_code,
               'body_length_code', body_length_code,
               'comparison_policy_code', comparison_policy_code
           ) order by sort_order, garment_type_code,
               coalesce(sleeve_length_code, '∅'),
               coalesce(lower_length_code, '∅'),
               coalesce(body_length_code, '∅')), '[]'::jsonb) candidates,
           encode(extensions.digest(coalesce(string_agg(
               candidate_fingerprint, E'\n' order by candidate_fingerprint
           ), ''), 'sha256'), 'hex') candidate_set_hash
    from fingerprinted
)
select jsonb_build_object(
    'recoverability', case when a.candidate_count between 1 and 3
        then 'RECOVERABLE' else 'UNRECOVERABLE' end,
    'unrecoverable_reason', case
        when a.candidate_count = 0 then 'NO_EXACT_PRODUCT_AXIS_CANDIDATE'
        when a.candidate_count > 3 then 'EXACT_PRODUCT_CANDIDATE_SET_NOT_BOUNDED'
        else null end,
    'fixed_facts', case when a.candidate_count between 1 and 3 then
        jsonb_strip_nulls(jsonb_build_object(
            'audience_code', p.audience_code,
            'product_structure_code', p.product_structure_code,
            'category_code', a.category_code,
            'garment_type_code', a.garment_type_code,
            'sleeve_length_code', case when a.sleeve_count = 1
                then (a.candidates -> 0 ->> 'sleeve_length_code') end,
            'lower_length_code', case when a.lower_count = 1
                then (a.candidates -> 0 ->> 'lower_length_code') end,
            'body_length_code', case when a.body_count = 1
                then (a.candidates -> 0 ->> 'body_length_code') end,
            'comparison_policy_code', a.comparison_policy_code
        )) else jsonb_strip_nulls(jsonb_build_object(
            'audience_code', p.audience_code,
            'product_structure_code', p.product_structure_code
        )) end,
    'unknown_fields', case when a.candidate_count between 1 and 3 then
        (select coalesce(jsonb_agg(field_name order by field_order), '[]'::jsonb)
         from (values
             ('sleeve_length', 1, a.sleeve_count > 1),
             ('lower_length', 2, a.lower_count > 1),
             ('body_length', 3, a.body_count > 1)
         ) fields(field_name, field_order, is_unknown)
         where is_unknown)
        else '[]'::jsonb end,
    'candidates', case when a.candidate_count between 1 and 3
        then a.candidates else '[]'::jsonb end,
    'candidate_count', case when a.candidate_count between 1 and 3
        then a.candidate_count else 0 end,
    'candidate_set_hash', case when a.candidate_count between 1 and 3
        then a.candidate_set_hash end,
    'candidate_contract_version',
        'fitmatch-vnext-recovery-candidates-v3-exact-product',
    'authority_source', 'VERIFIED_EXACT_PRODUCT_SERVER_AUTHORITY'
)
from aggregate_value a
cross join product_row p;
$function$;

revoke all on function fitmatch_vnext.exact_product_authority_recovery_options(uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.exact_product_authority_recovery_options(uuid)
    to service_role;

do $patch_recovery$
declare
    old_definition text;
    new_definition text;
begin
    old_definition := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );
    if position('exact_product_authority_recovery_options' in old_definition) = 0 then
        new_definition := replace(
            old_definition,
            '    if recoverability_value <> ''RECOVERABLE'' then',
            E'    if recoverability_value <> ''RECOVERABLE'' then\n'
            || E'        exact_fallback_value := fitmatch_vnext.'
            || E'exact_product_authority_recovery_options(product_row.id);\n'
            || E'        if exact_fallback_value ->> ''recoverability'' = '
            || E'''RECOVERABLE'' then\n'
            || E'            recoverability_value := ''RECOVERABLE'';\n'
            || E'            unrecoverable_reason_value := null;\n'
            || E'            candidates_value := exact_fallback_value -> ''candidates'';\n'
            || E'            candidate_count_value := coalesce('
            || E'(exact_fallback_value ->> ''candidate_count'')::integer, 0);\n'
            || E'            candidate_set_hash_value := exact_fallback_value ->> '
            || E'''candidate_set_hash'';\n'
            || E'            fixed_facts_value := exact_fallback_value -> ''fixed_facts'';\n'
            || E'            unknown_fields_value := exact_fallback_value -> ''unknown_fields'';\n'
            || E'            contract_version_value := exact_fallback_value ->> '
            || E'''candidate_contract_version'';\n'
            || E'        end if;\n'
            || E'    end if;\n\n'
            || E'    if recoverability_value <> ''RECOVERABLE'' then'
        );
        new_definition := replace(
            new_definition,
            '    current_decision jsonb;',
            E'    current_decision jsonb;\n    exact_fallback_value jsonb;'
        );
        new_definition := replace(
            new_definition,
            '    contract_version_value constant text :=',
            '    contract_version_value text :='
        );
        if position('exact_product_authority_recovery_options' in new_definition) = 0
           or position('exact_fallback_value jsonb' in new_definition) = 0 then
            raise exception 'Unable to patch classification recovery';
        end if;
        execute new_definition;
    end if;
end
$patch_recovery$;

do $postflight$
begin
    if has_function_privilege('public',
           'fitmatch_vnext.exact_product_authority_recovery_options(uuid)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('anon',
           'fitmatch_vnext.exact_product_authority_recovery_options(uuid)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('authenticated',
           'fitmatch_vnext.exact_product_authority_recovery_options(uuid)'::regprocedure,
           'EXECUTE')
       or not has_function_privilege('service_role',
           'fitmatch_vnext.exact_product_authority_recovery_options(uuid)'::regprocedure,
           'EXECUTE')
       or position('exact_product_authority_recovery_options' in pg_get_functiondef(
           'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
       )) = 0 then
        raise exception 'Exact-product bounded recovery postflight failed';
    end if;
end
$postflight$;

commit;
