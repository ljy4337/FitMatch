-- Purpose: discover target-compatible closet references without client-side
-- garment, audience, axis, measurement, or availability policy reconstruction.
-- Data impact: none; adds a read-only authenticated domain RPC.
-- Rollback: drop find_reference_candidates(uuid,uuid).
-- Verification: response distinguishes AUTOMATIC, MANUAL_EXTENDED,
-- MEASUREMENTS_REQUIRED, and BLOCKED with deterministic exclusions/reasons.

create or replace function fitmatch_vnext.find_reference_candidates(
    p_target_product_id uuid,
    p_target_variant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    target_row fitmatch_vnext.products%rowtype;
    closet_row fitmatch_vnext.closet_items%rowtype;
    variant_row record;
    size_row record;
    automatic_result jsonb;
    manual_result jsonb;
    authorization_result jsonb;
    selected_authorization jsonb;
    automatic_ids uuid[] := '{}'::uuid[];
    manual_ids uuid[] := '{}'::uuid[];
    decision_value text;
    reason_value text;
    measurement_required_seen boolean;
    candidates_value jsonb := '[]'::jsonb;
    blocked_value jsonb := '[]'::jsonb;
    item_value jsonb;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    select * into target_row
    from fitmatch_vnext.products p where p.id = p_target_product_id;
    if not found then
        raise exception 'Target product not found';
    end if;
    if target_row.classification_status <> 'CONFIRMED' then
        return jsonb_build_object(
            'target_product_id', target_row.id,
            'target_variant_id', p_target_variant_id,
            'candidates', '[]'::jsonb,
            'blocked', '[]'::jsonb,
            'status', 'BLOCKED',
            'reason', 'Target classification is not CONFIRMED',
            'reference_candidate_version', 'fitmatch-vnext-reference-candidates-v1'
        );
    end if;
    if p_target_variant_id is not null and not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = p_target_variant_id and pv.product_id = target_row.id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    for closet_row in
        select * from fitmatch_vnext.closet_items ci
        where ci.user_id = caller_id and ci.deleted_at is null
        order by ci.created_at, ci.id
    loop
        automatic_ids := '{}'::uuid[];
        manual_ids := '{}'::uuid[];
        selected_authorization := null;
        measurement_required_seen := false;
        reason_value := null;

        for variant_row in
            select pv.id
            from fitmatch_vnext.product_variants pv
            where pv.product_id = target_row.id
              and (p_target_variant_id is null or pv.id = p_target_variant_id)
            order by pv.sort_order, pv.id
        loop
            automatic_result := fitmatch_vnext.eligible_candidate_sizes(
                closet_row.id, target_row.id, variant_row.id, false
            );
            if coalesce((automatic_result ->> 'allowed')::boolean, false) then
                automatic_ids := automatic_ids || coalesce((
                    select array_agg(value::uuid order by ordinal)
                    from jsonb_array_elements_text(
                        automatic_result -> 'authorized_candidate_product_size_ids'
                    ) with ordinality item(value, ordinal)
                ), '{}'::uuid[]);
                if selected_authorization is null then
                    selected_authorization := automatic_result -> 'candidates'
                        -> 0 -> 'authorization';
                end if;
            else
                reason_value := coalesce(reason_value, automatic_result ->> 'reason');
            end if;

            if cardinality(automatic_ids) = 0 then
                manual_result := fitmatch_vnext.eligible_candidate_sizes(
                    closet_row.id, target_row.id, variant_row.id, true
                );
                if coalesce((manual_result ->> 'allowed')::boolean, false)
                   and manual_result ->> 'decision' = 'MANUAL_EXTENDED' then
                    manual_ids := manual_ids || coalesce((
                        select array_agg(value::uuid order by ordinal)
                        from jsonb_array_elements_text(
                            manual_result -> 'authorized_candidate_product_size_ids'
                        ) with ordinality item(value, ordinal)
                    ), '{}'::uuid[]);
                    if selected_authorization is null then
                        selected_authorization := manual_result -> 'candidates'
                            -> 0 -> 'authorization';
                    end if;
                end if;
            end if;
        end loop;

        if cardinality(automatic_ids) > 0 then
            decision_value := 'AUTOMATIC';
            reason_value := selected_authorization ->> 'reason';
        elsif cardinality(manual_ids) > 0 then
            decision_value := 'MANUAL_EXTENDED';
            reason_value := selected_authorization ->> 'reason';
        else
            for size_row in
                select ps.id
                from fitmatch_vnext.product_sizes ps
                join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
                where pv.product_id = target_row.id
                  and (p_target_variant_id is null or pv.id = p_target_variant_id)
                order by pv.sort_order, ps.sort_order, ps.id
            loop
                authorization_result := fitmatch_vnext.authorize_comparison(
                    closet_row.id, target_row.id, size_row.id, false
                );
                if authorization_result ->> 'decision' = 'MEASUREMENTS_REQUIRED' then
                    measurement_required_seen := true;
                    selected_authorization := authorization_result;
                    exit;
                end if;
                if selected_authorization is null then
                    selected_authorization := authorization_result;
                end if;
            end loop;
            if measurement_required_seen then
                decision_value := 'MEASUREMENTS_REQUIRED';
                reason_value := selected_authorization ->> 'reason';
            else
                decision_value := 'BLOCKED';
                reason_value := coalesce(reason_value,
                    selected_authorization ->> 'reason',
                    'No target size can be authorized');
            end if;
        end if;

        item_value := jsonb_build_object(
            'closet_item_id', closet_row.id,
            'item_name', closet_row.item_name,
            'size_label', closet_row.size_label,
            'product_id', closet_row.product_id,
            'variant_id', closet_row.product_variant_id,
            'product_size_id', closet_row.product_size_id,
            'is_current_reference', closet_row.is_reference,
            'decision', decision_value,
            'allowed', decision_value in ('AUTOMATIC','MANUAL_EXTENDED'),
            'mode', case when decision_value in ('AUTOMATIC','MANUAL_EXTENDED')
                then decision_value else 'NONE' end,
            'manual_explicit_required', decision_value = 'MANUAL_EXTENDED',
            'reason', reason_value,
            'common_measurement_count',
                (selected_authorization ->> 'common_measurement_count')::integer,
            'required_any_count',
                (selected_authorization ->> 'required_any_count')::integer,
            'minimum_common',
                (selected_authorization ->> 'minimum_common')::integer,
            'excluded_measurement_codes', coalesce(
                selected_authorization -> 'excluded_measurement_codes', '[]'::jsonb
            ),
            'required_measurement_codes', coalesce(
                selected_authorization -> 'required_measurement_codes', '[]'::jsonb
            ),
            'policy_code', selected_authorization ->> 'policy_code',
            'policy_version', selected_authorization ->> 'policy_version',
            'policy_checksum', selected_authorization ->> 'policy_checksum',
            'eligible_product_size_ids', case
                when decision_value = 'AUTOMATIC' then to_jsonb(automatic_ids)
                when decision_value = 'MANUAL_EXTENDED' then to_jsonb(manual_ids)
                else '[]'::jsonb end
        );
        if decision_value = 'BLOCKED' then
            blocked_value := blocked_value || jsonb_build_array(item_value);
        else
            candidates_value := candidates_value || jsonb_build_array(item_value);
        end if;
    end loop;

    return jsonb_build_object(
        'target_product_id', target_row.id,
        'target_variant_id', p_target_variant_id,
        'candidates', candidates_value,
        'blocked', blocked_value,
        'candidate_count', jsonb_array_length(candidates_value),
        'blocked_count', jsonb_array_length(blocked_value),
        'status', case when jsonb_array_length(candidates_value) > 0
            then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
        'reference_candidate_version', 'fitmatch-vnext-reference-candidates-v1'
    );
end
$function$;

revoke all on function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    from public, anon;
grant execute on function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    to authenticated, service_role;

-- Verification query is exercised transactionally by
-- supabase/sql/121_vnext_final_remediation_tests.sql.
