-- Purpose: make the database the sole authority for eligible target sizes.
-- Data impact: none; adds a user-owned domain RPC over existing availability,
-- measurement, policy, and comparison authorization authorities.
-- Rollback: drop eligible_candidate_sizes(uuid,uuid,uuid,boolean).
-- Verification: AVAILABLE+unexpired+policy-complete sizes are returned; UNKNOWN,
-- SOLD_OUT, expired, ambiguous, and insufficient sizes are absent.

create or replace function fitmatch_vnext.eligible_candidate_sizes(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_variant_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    reference_row fitmatch_vnext.closet_items%rowtype;
    target_row fitmatch_vnext.products%rowtype;
    size_row record;
    canonical_value jsonb;
    authorization_value jsonb;
    comparison_measurements_value jsonb;
    candidates_value jsonb := '[]'::jsonb;
    candidate_value jsonb;
    available_count_value integer := 0;
    expired_count_value integer := 0;
    semantic_conflict_count_value integer := 0;
    authorization_rejected_count_value integer := 0;
    authority_fingerprint_value text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    select * into reference_row
    from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;
    if not found then
        raise exception 'Reference is missing or not owned';
    end if;

    select * into target_row
    from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found then
        raise exception 'Target product not found';
    end if;
    if target_row.classification_status <> 'CONFIRMED' then
        return jsonb_build_object(
            'allowed', false,
            'decision', 'BLOCKED',
            'reason', 'Target classification is not CONFIRMED',
            'authorized_candidate_product_size_ids', '[]'::jsonb,
            'candidates', '[]'::jsonb,
            'candidate_authority_version', 'fitmatch-vnext-candidates-v1'
        );
    end if;
    if not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = p_target_variant_id and pv.product_id = p_target_product_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    for size_row in
        select ps.id product_size_id, ps.size_label, ps.sort_order,
               availability.availability_status,
               availability.observed_at availability_observed_at,
               availability.valid_until availability_valid_until,
               availability.evidence_fingerprint availability_evidence_fingerprint
        from fitmatch_vnext.product_sizes ps
        left join lateral (
            select o.availability_status, o.observed_at, o.valid_until,
                   o.evidence_fingerprint
            from fitmatch_vnext.size_availability_observations o
            where o.product_size_id = ps.id
            order by o.observed_at desc, o.id desc
            limit 1
        ) availability on true
        where ps.variant_id = p_target_variant_id
        order by ps.sort_order, ps.id
    loop
        if size_row.availability_status is distinct from 'AVAILABLE' then
            continue;
        end if;
        available_count_value := available_count_value + 1;
        if size_row.availability_valid_until is null
           or size_row.availability_valid_until < now() then
            expired_count_value := expired_count_value + 1;
            continue;
        end if;

        canonical_value := fitmatch_vnext.canonical_measurements_for_size(
            size_row.product_size_id
        );
        if coalesce((canonical_value ->> 'semantic_conflict_count')::integer, 0) > 0 then
            semantic_conflict_count_value := semantic_conflict_count_value + 1;
            continue;
        end if;

        authorization_value := fitmatch_vnext.authorize_comparison(
            reference_row.id,
            target_row.id,
            size_row.product_size_id,
            p_manual_explicit
        );
        if not coalesce((authorization_value ->> 'allowed')::boolean, false) then
            authorization_rejected_count_value := authorization_rejected_count_value + 1;
            continue;
        end if;

        select coalesce(jsonb_agg(jsonb_build_object(
            'measurement_code', cm.fitmatch_measurement_code,
            'reference_value', reference_measurement.value,
            'target_value', (target_measurement ->> 'value')::numeric,
            'difference', (target_measurement ->> 'value')::numeric
                - reference_measurement.value,
            'absolute_difference', abs((target_measurement ->> 'value')::numeric
                - reference_measurement.value),
            'unit_code', target_measurement ->> 'unit_code',
            'basis_code', target_measurement ->> 'basis_code',
            'weight', cm.weight,
            'requirement_mode', cm.requirement_mode,
            'priority', cm.priority
        ) order by cm.priority, cm.fitmatch_measurement_code), '[]'::jsonb)
        into comparison_measurements_value
        from fitmatch_vnext.comparison_metrics cm
        join fitmatch_vnext.closet_item_measurements reference_measurement
          on reference_measurement.closet_item_id = reference_row.id
         and reference_measurement.fitmatch_measurement_code =
             cm.fitmatch_measurement_code
        join lateral jsonb_array_elements(
            canonical_value -> 'measurements'
        ) target_measurement
          on target_measurement ->> 'fitmatch_measurement_code' =
             cm.fitmatch_measurement_code
        where cm.comparison_policy_code = authorization_value ->> 'policy_code'
          and cm.metric_mode = 'CANONICAL'
          and cm.is_active
          and not (cm.fitmatch_measurement_code = any(coalesce(
              array(select jsonb_array_elements_text(
                  authorization_value -> 'excluded_measurement_codes'
              )), '{}'::text[]
          )));

        if jsonb_array_length(comparison_measurements_value) <
               (authorization_value ->> 'minimum_common')::integer
           or (
                select count(*)
                from jsonb_array_elements(comparison_measurements_value) evidence
                where evidence ->> 'requirement_mode' = 'REQUIRED_ANY'
              ) < coalesce((authorization_value ->> 'required_any_count')::integer, 0) then
            authorization_rejected_count_value := authorization_rejected_count_value + 1;
            continue;
        end if;

        candidate_value := jsonb_build_object(
            'product_size_id', size_row.product_size_id,
            'size_label', size_row.size_label,
            'availability', jsonb_build_object(
                'status', size_row.availability_status,
                'observed_at', size_row.availability_observed_at,
                'valid_until', size_row.availability_valid_until,
                'evidence_fingerprint', size_row.availability_evidence_fingerprint
            ),
            'canonical_measurements', canonical_value,
            'comparison_measurements', comparison_measurements_value,
            'authorization', authorization_value
        );
        candidates_value := candidates_value || jsonb_build_array(candidate_value);
    end loop;

    authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
        reference_row.id::text, target_row.id::text, p_target_variant_id::text,
        p_manual_explicit::text, candidates_value::text,
        'fitmatch-vnext-candidates-v1'
    ), 'sha256'), 'hex');

    return jsonb_build_object(
        'allowed', jsonb_array_length(candidates_value) > 0,
        'decision', case when jsonb_array_length(candidates_value) > 0
            then coalesce(candidates_value -> 0 -> 'authorization' ->> 'decision', 'BLOCKED')
            else 'BLOCKED' end,
        'mode', case when jsonb_array_length(candidates_value) > 0
            then coalesce(candidates_value -> 0 -> 'authorization' ->> 'mode', 'NONE')
            else 'NONE' end,
        'reason', case
            when jsonb_array_length(candidates_value) > 0
                then 'Database-generated eligible candidate set'
            when available_count_value = 0
                then 'No size has latest AVAILABLE evidence'
            when expired_count_value = available_count_value
                then 'All AVAILABLE observations are expired or have no expiry contract'
            when semantic_conflict_count_value > 0
                then 'Canonical measurement semantic conflict'
            else 'No size satisfies comparison authorization and measurement minimums'
            end,
        'reference_closet_item_id', reference_row.id,
        'target_product_id', target_row.id,
        'target_variant_id', p_target_variant_id,
        'manual_explicit', p_manual_explicit,
        'authorized_candidate_product_size_ids', coalesce((
            select jsonb_agg(candidate -> 'product_size_id')
            from jsonb_array_elements(candidates_value) candidate
        ), '[]'::jsonb),
        'candidates', candidates_value,
        'diagnostics', jsonb_build_object(
            'latest_available_count', available_count_value,
            'expired_or_unbounded_count', expired_count_value,
            'semantic_conflict_count', semantic_conflict_count_value,
            'authorization_rejected_count', authorization_rejected_count_value
        ),
        'candidate_authority_fingerprint', authority_fingerprint_value,
        'candidate_authority_version', 'fitmatch-vnext-candidates-v1'
    );
end
$function$;

revoke all on function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)
    from public, anon;
grant execute on function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)
    to authenticated, service_role;

-- Verification query is exercised transactionally by
-- supabase/sql/121_vnext_final_remediation_tests.sql.
;
