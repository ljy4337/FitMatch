-- PRODUCTION BLOCKER 2
-- Requires the v6 complete-tuple recovery migration to be applied first.
-- Generic retailer leaves such as 유니섹스 / GU must not let one questionable
-- exact-product garment authority lock the user into a wrong garment type.

begin;

do $snapshot_core$
declare
    public_definition text;
    core_definition text;
begin
    if to_regprocedure(
        'fitmatch_vnext.classification_recovery_options(uuid)'
    ) is null then
        raise exception 'classification_recovery_options is missing';
    end if;

    public_definition := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );

    if position(
        'fitmatch-vnext-recovery-v6-complete-tuple-garment-first'
        in public_definition
    ) = 0 then
        raise exception 'Expected v6 complete-tuple recovery preimage';
    end if;

    if to_regprocedure(
        'fitmatch_vnext.classification_recovery_options_v6_core(uuid)'
    ) is not null then
        raise exception 'v6 recovery core already exists';
    end if;

    core_definition := regexp_replace(
        public_definition,
        'fitmatch_vnext\.classification_recovery_options\(p_product_id uuid\)',
        'fitmatch_vnext.classification_recovery_options_v6_core(p_product_id uuid)'
    );

    if core_definition = public_definition then
        raise exception 'Unable to snapshot v6 recovery core';
    end if;

    execute core_definition;
end
$snapshot_core$;

revoke all
on function fitmatch_vnext.classification_recovery_options_v6_core(uuid)
from public, anon, authenticated;

grant execute
on function fitmatch_vnext.classification_recovery_options_v6_core(uuid)
to service_role;

create or replace function fitmatch_vnext.classification_recovery_options(
    p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
    current_decision jsonb;

    terminal_parent_id uuid;
    terminal_name text;
    terminal_is_generic boolean := false;

    sibling_garment_type_count integer := 0;
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select *
    into product_row
    from fitmatch_vnext.products product
    where product.id = p_product_id;

    if not found then
        raise exception 'Product not found';
    end if;

    current_decision :=
        fitmatch_vnext.classification_decision(
            product_row.source_code,
            product_row.source_product_key
        );

    select
        signal.parent_signal_id,
        signal.signal_name,
        lower(btrim(coalesce(signal.signal_name, ''))) in (
            '유니섹스',
            'unisex',
            'gu',
            '기타',
            'other'
        )
    into
        terminal_parent_id,
        terminal_name,
        terminal_is_generic
    from fitmatch_vnext.product_classification_signals product_signal
    join fitmatch_vnext.source_classification_signals signal
      on signal.id = product_signal.source_signal_id
     and signal.source_code = product_row.source_code
     and signal.signal_kind = 'CATEGORY'
     and signal.is_active
    where product_signal.product_id = product_row.id
    order by product_signal.evidence_order desc, signal.id
    limit 1;

    if terminal_is_generic
       and terminal_parent_id is not null then

        select
            count(distinct mapping.garment_type_code)::integer
        into sibling_garment_type_count
        from fitmatch_vnext.source_classification_signals sibling
        join fitmatch_vnext.classification_signal_mappings mapping
          on mapping.source_signal_id = sibling.id
         and mapping.is_verified
         and mapping.resolution_mode = 'DIRECT'
         and mapping.garment_type_code is not null
         and (
             mapping.audience_code = 'ANY'
             or mapping.audience_code = product_row.audience_code
         )
        join fitmatch_vnext.garment_types garment
          on garment.garment_type_code = mapping.garment_type_code
         and garment.is_active
        where sibling.parent_signal_id = terminal_parent_id
          and sibling.source_code = product_row.source_code
          and sibling.signal_kind = 'CATEGORY'
          and sibling.is_active;
    end if;

    if product_row.classification_status = 'REVIEW_REQUIRED'
       and current_decision ->> 'reason'
           = 'Product-exact verified evidence is required'
       and terminal_is_generic
       and sibling_garment_type_count > 1 then

        return jsonb_build_object(
            'product_id', product_row.id,
            'global_status', product_row.classification_status,
            'recoverability', 'UNRECOVERABLE',
            'unrecoverable_reason',
                'GENERIC_LEAF_MULTI_GARMENT_AUTHORITY_AMBIGUOUS',

            'fixed_facts',
                jsonb_strip_nulls(
                    jsonb_build_object(
                        'audience_code', product_row.audience_code,
                        'product_structure_code',
                            product_row.product_structure_code
                    )
                ),

            'unknown_fields', '[]'::jsonb,
            'candidates', '[]'::jsonb,
            'candidate_count', 0,

            'product_input_fingerprint',
                product_row.input_fingerprint,
            'product_evidence_fingerprint',
                product_row.evidence_fingerprint,
            'resolver_version',
                product_row.resolver_version,

            'candidate_contract_version',
                'fitmatch-vnext-recovery-v6-complete-tuple-garment-first',

            'candidate_set_hash', null,
            'current_review_reason',
                current_decision ->> 'reason',

            'diagnostic',
                jsonb_build_object(
                    'terminal_signal_name', terminal_name,
                    'sibling_garment_type_count',
                        sibling_garment_type_count,
                    'guard_version',
                        'generic-leaf-multi-garment-v1'
                )
        );
    end if;

    return
        fitmatch_vnext.classification_recovery_options_v6_core(
            p_product_id
        );
end
$function$;

revoke all
on function fitmatch_vnext.classification_recovery_options(uuid)
from public, anon;

grant execute
on function fitmatch_vnext.classification_recovery_options(uuid)
to authenticated, service_role;

do $postflight$
declare
    definition text;
begin
    definition := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );

    if position(
        'GENERIC_LEAF_MULTI_GARMENT_AUTHORITY_AMBIGUOUS'
        in definition
    ) = 0
       or to_regprocedure(
           'fitmatch_vnext.classification_recovery_options_v6_core(uuid)'
       ) is null then
        raise exception 'Generic-leaf authority guard postflight failed';
    end if;
end
$postflight$;

commit;
