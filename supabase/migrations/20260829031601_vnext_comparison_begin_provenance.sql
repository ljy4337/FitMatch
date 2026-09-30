-- Purpose: bind comparison begin to the DB-generated candidate set and capture
-- complete reference/target/classification/policy/availability provenance.
-- Data impact: function replacement only; new rows use snapshot schema v3.
-- Rollback: restore begin_comparison from 20260829013409.
-- Verification: omitted client candidates succeed; a client subset, superset,
-- duplicate, unavailable, or expired candidate set is rejected.

create or replace function fitmatch_vnext.begin_comparison(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    client_id uuid;
    ref_id uuid;
    target_id uuid;
    target_variant uuid;
    authorization_size uuid;
    manual_explicit boolean;
    request_hash text;
    existing fitmatch_vnext.comparisons%rowtype;
    ref fitmatch_vnext.closet_items%rowtype;
    reference_product fitmatch_vnext.products%rowtype;
    target fitmatch_vnext.products%rowtype;
    selected_mapping fitmatch_vnext.classification_signal_mappings%rowtype;
    candidate_authority jsonb;
    candidates jsonb;
    authz jsonb;
    authorized_ids uuid[];
    authorized_ids_sorted uuid[];
    client_candidate_ids uuid[];
    client_candidate_ids_sorted uuid[];
    comparison_id uuid;
    taxonomy_checksum text;
    mapping_authority_checksum text;
    reference_data jsonb;
    target_data jsonb;
    policy_data jsonb;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;

    client_id := (p_request ->> 'client_comparison_id')::uuid;
    ref_id := (p_request ->> 'reference_closet_item_id')::uuid;
    target_id := (p_request ->> 'target_product_id')::uuid;
    target_variant := (p_request ->> 'target_variant_id')::uuid;
    authorization_size := nullif(
        btrim(p_request ->> 'authorization_product_size_id'), ''
    )::uuid;
    manual_explicit := coalesce((p_request ->> 'manual_explicit')::boolean, false);
    if client_id is null or ref_id is null or target_id is null
       or target_variant is null then
        raise exception 'Comparison identity, reference, target, and variant are required';
    end if;

    request_hash := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
    perform pg_advisory_xact_lock(hashtextextended(
        caller_id::text || ':' || client_id::text, 0
    ));

    select * into existing
    from fitmatch_vnext.comparisons
    where user_id = caller_id and client_comparison_id = client_id
    for update;
    if found then
        if existing.request_payload_hash is distinct from request_hash then
            raise exception 'Idempotency conflict for client_comparison_id';
        end if;
        return jsonb_build_object(
            'comparison_id', existing.id,
            'created', false,
            'idempotent', true,
            'result_status', existing.result_status,
            'authorized_candidate_product_size_ids',
                existing.target_snapshot -> 'authorized_candidate_product_size_ids'
        );
    end if;

    select * into ref
    from fitmatch_vnext.closet_items
    where id = ref_id and user_id = caller_id and deleted_at is null;
    if not found then
        raise exception 'Reference is missing or not owned';
    end if;
    if ref.product_id is not null then
        select * into reference_product
        from fitmatch_vnext.products where id = ref.product_id;
    end if;

    select * into target
    from fitmatch_vnext.products where id = target_id;
    if not found then
        raise exception 'Target product not found';
    end if;
    if not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = target_variant and pv.product_id = target_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    candidate_authority := fitmatch_vnext.eligible_candidate_sizes(
        ref_id, target_id, target_variant, manual_explicit
    );
    if not coalesce((candidate_authority ->> 'allowed')::boolean, false) then
        raise exception 'Comparison has no eligible candidate sizes: %',
            candidate_authority ->> 'reason';
    end if;
    candidates := candidate_authority -> 'candidates';
    select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
    into authorized_ids
    from jsonb_array_elements_text(
        candidate_authority -> 'authorized_candidate_product_size_ids'
    ) with ordinality item(value, ordinal);
    select coalesce(array_agg(id order by id), '{}'::uuid[])
    into authorized_ids_sorted from unnest(authorized_ids) id;
    if cardinality(authorized_ids) = 0 then
        raise exception 'Candidate authority returned an empty set';
    end if;

    if p_request ? 'candidate_product_size_ids' then
        if jsonb_typeof(p_request -> 'candidate_product_size_ids') <> 'array' then
            raise exception 'candidate_product_size_ids must be an array';
        end if;
        select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
        into client_candidate_ids
        from jsonb_array_elements_text(p_request -> 'candidate_product_size_ids')
             with ordinality item(value, ordinal);
        if cardinality(client_candidate_ids) <>
             (select count(distinct id) from unnest(client_candidate_ids) id) then
            raise exception 'Client candidate sizes contain duplicates';
        end if;
        select coalesce(array_agg(id order by id), '{}'::uuid[])
        into client_candidate_ids_sorted from unnest(client_candidate_ids) id;
        if client_candidate_ids_sorted is distinct from authorized_ids_sorted then
            raise exception 'Client candidate sizes do not equal the DB-authorized set';
        end if;
    end if;

    if authorization_size is null then
        authorization_size := authorized_ids[1];
    elsif not authorization_size = any(authorized_ids) then
        raise exception 'authorization_product_size_id is not DB-authorized';
    end if;

    select candidate -> 'authorization' into authz
    from jsonb_array_elements(candidates) candidate
    where (candidate ->> 'product_size_id')::uuid = authorization_size
    limit 1;
    if authz is null or not coalesce((authz ->> 'allowed')::boolean, false) then
        raise exception 'Selected authorization is invalid';
    end if;

    select * into selected_mapping
    from fitmatch_vnext.classification_signal_mappings m
    where m.id = target.classification_mapping_id;

    select encode(extensions.digest(coalesce(string_agg(concat_ws('|',
        gt.garment_type_code, gt.category_code, gt.comparison_policy_code,
        gt.uses_sleeve_length::text, gt.uses_lower_length::text,
        gt.uses_body_length::text, gt.is_active::text
    ), E'\n' order by gt.garment_type_code), ''), 'sha256'), 'hex')
    into taxonomy_checksum
    from fitmatch_vnext.garment_types gt;

    select encode(extensions.digest(coalesce(string_agg(concat_ws('|',
        m.id::text, m.mapping_version, m.mapping_checksum
    ), E'\n' order by m.id), ''), 'sha256'), 'hex')
    into mapping_authority_checksum
    from fitmatch_vnext.classification_signal_mappings m
    where m.is_active and m.is_verified;

    reference_data := jsonb_build_object(
        'closet_item_id', ref.id,
        'source_code', reference_product.source_code,
        'source_product_key', reference_product.source_product_key,
        'product_id', ref.product_id,
        'variant_id', ref.product_variant_id,
        'product_size_id', ref.product_size_id,
        'item_name', ref.item_name,
        'size_label', ref.size_label,
        'garment_type_code', ref.garment_type_code,
        'audience_code', ref.audience_code,
        'sleeve_length_code', ref.sleeve_length_code,
        'lower_length_code', ref.lower_length_code,
        'body_length_code', ref.body_length_code,
        'classification_source', ref.classification_source,
        'classification_fingerprint', ref.classification_fingerprint,
        'classification_resolver_version', ref.classification_resolver_version,
        'measurements', coalesce((
            select jsonb_agg(jsonb_build_object(
                'fitmatch_measurement_code', cm.fitmatch_measurement_code,
                'value', cm.value,
                'unit_code', cm.unit_code,
                'value_source', cm.value_source,
                'raw_label_snapshot', cm.raw_label_snapshot
            ) order by cm.fitmatch_measurement_code)
            from fitmatch_vnext.closet_item_measurements cm
            where cm.closet_item_id = ref.id
        ), '[]'::jsonb)
    );

    target_data := jsonb_build_object(
        'product_id', target.id,
        'source_code', target.source_code,
        'source_product_key', target.source_product_key,
        'variant_id', target_variant,
        -- Legacy key is retained as an alias, but its value is DB-generated.
        'candidate_product_size_ids', to_jsonb(authorized_ids),
        'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
        'candidate_authority_fingerprint',
            candidate_authority ->> 'candidate_authority_fingerprint',
        'candidate_authority_version',
            candidate_authority ->> 'candidate_authority_version',
        'classification_status', target.classification_status,
        'product_structure_code', target.product_structure_code,
        'garment_type_code', target.garment_type_code,
        'audience_code', target.audience_code,
        'sleeve_length_code', target.sleeve_length_code,
        'lower_length_code', target.lower_length_code,
        'body_length_code', target.body_length_code,
        'classification_fingerprint', target.input_fingerprint,
        'classification_evidence_fingerprint', target.evidence_fingerprint,
        'resolver_version', target.resolver_version,
        'ingestion_evidence_fingerprint',
            target.source_extra ->> 'latest_ingestion_fingerprint',
        'candidates', candidates
    );

    select to_jsonb(cp) || jsonb_build_object(
        'metrics', coalesce((
            select jsonb_agg(jsonb_build_object(
                'metric_mode', cm.metric_mode,
                'fitmatch_measurement_code', cm.fitmatch_measurement_code,
                'source_measurement_code', cm.source_measurement_code,
                'weight', cm.weight,
                'requirement_mode', cm.requirement_mode,
                'priority', cm.priority,
                'is_active', cm.is_active
            ) order by cm.priority, cm.fitmatch_measurement_code,
                     cm.source_measurement_code)
            from fitmatch_vnext.comparison_metrics cm
            where cm.comparison_policy_code = cp.policy_code and cm.is_active
        ), '[]'::jsonb)
    ) into policy_data
    from fitmatch_vnext.comparison_policies cp
    where cp.policy_code = authz ->> 'policy_code' and cp.is_active;
    if policy_data is null then
        raise exception 'Active policy disappeared during comparison begin';
    end if;

    insert into fitmatch_vnext.comparisons (
        user_id, client_comparison_id, reference_closet_item_id,
        target_product_id, target_variant_id,
        comparison_policy_code_snapshot, comparison_mode,
        reference_source_code_snapshot, target_source_code_snapshot,
        reference_item_name_snapshot, target_product_name_snapshot,
        target_image_url_snapshot, reference_garment_type_snapshot,
        target_garment_type_snapshot, reference_audience_snapshot,
        target_audience_snapshot, reference_sleeve_length_snapshot,
        target_sleeve_length_snapshot, reference_lower_length_snapshot,
        target_lower_length_snapshot, reference_body_length_snapshot,
        target_body_length_snapshot, result_status, engine_version,
        snapshot_schema_version, detail_snapshot, request_payload_hash,
        authorization_mode, excluded_measurement_codes, reference_snapshot,
        target_snapshot, authority_snapshot, policy_snapshot,
        authorization_snapshot, input_snapshot
    ) values (
        caller_id, client_id, ref.id, target.id, target_variant,
        authz ->> 'policy_code', 'CANONICAL',
        coalesce(reference_product.source_code, ref.source_code_snapshot),
        target.source_code, ref.item_name, target.product_name, target.image_url,
        ref.garment_type_code, target.garment_type_code,
        ref.audience_code, target.audience_code,
        ref.sleeve_length_code, target.sleeve_length_code,
        ref.lower_length_code, target.lower_length_code,
        ref.body_length_code, target.body_length_code,
        'PENDING', 'pending', 3, jsonb_build_object('phase', 'BEGIN'),
        request_hash, authz ->> 'mode',
        array(select jsonb_array_elements_text(
            authz -> 'excluded_measurement_codes'
        )),
        reference_data, target_data,
        jsonb_build_object(
            'classification_resolver_version', target.resolver_version,
            'classification_fingerprint', target.input_fingerprint,
            'classification_evidence_fingerprint', target.evidence_fingerprint,
            'classification_mapping_id', target.classification_mapping_id,
            'selected_mapping_version', selected_mapping.mapping_version,
            'selected_mapping_checksum', selected_mapping.mapping_checksum,
            'mapping_authority_checksum', mapping_authority_checksum,
            'taxonomy_schema_version', 'fitmatch-vnext-taxonomy-v1',
            'taxonomy_checksum', taxonomy_checksum,
            'ingestion_evidence_fingerprint',
                target.source_extra ->> 'latest_ingestion_fingerprint'
        ),
        policy_data, authz,
        jsonb_build_object(
            'client_request', p_request,
            'candidate_authority_fingerprint',
                candidate_authority ->> 'candidate_authority_fingerprint',
            'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
            'began_at', now()
        )
    ) returning id into comparison_id;

    return jsonb_build_object(
        'comparison_id', comparison_id,
        'created', true,
        'idempotent', false,
        'result_status', 'PENDING',
        'authorization', authz,
        'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
        'candidate_authority_fingerprint',
            candidate_authority ->> 'candidate_authority_fingerprint'
    );
end
$function$;

revoke all on function fitmatch_vnext.begin_comparison(jsonb) from public, anon;
grant execute on function fitmatch_vnext.begin_comparison(jsonb)
    to authenticated, service_role;

-- Verification query is exercised transactionally by
-- supabase/sql/121_vnext_final_remediation_tests.sql.
;
