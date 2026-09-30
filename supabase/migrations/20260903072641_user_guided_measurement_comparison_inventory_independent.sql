-- Purpose: make comparison authorization measurement-led and independent from
-- retailer availability.  This is a forward-only replacement for the current
-- vNext comparison gates; it does not alter completed comparison rows.
--
-- The authoritative decision remains in PostgreSQL.  Swift receives its
-- decision, evidence, exclusions and typed reason code, then invokes the
-- existing MeasurementComparisonEngine only after begin_comparison succeeds.

begin;

-- Fail before the first mutation if this is not the production contract that
-- was inspected for this migration.  These are deliberately semantic guards
-- instead of fragile whitespace-dependent source hashes.
do $preflight$
declare
    authorization_definition text;
    candidates_definition text;
    discovery_definition text;
    readiness_definition text;
begin
    if to_regprocedure(
        'fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)'
    ) is not null then
        raise exception 'User-guided comparison preflight: comparison_decision helper already exists';
    end if;

    if to_regclass('fitmatch_vnext.garment_types') is null
       or to_regclass('fitmatch_vnext.products') is null
       or to_regclass('fitmatch_vnext.closet_items') is null
       or to_regclass('fitmatch_vnext.closet_item_measurements') is null
       or to_regclass('fitmatch_vnext.product_variants') is null
       or to_regclass('fitmatch_vnext.product_sizes') is null
       or to_regclass('fitmatch_vnext.size_availability_observations') is null
       or to_regclass('fitmatch_vnext.comparison_policies') is null
       or to_regclass('fitmatch_vnext.comparison_metrics') is null
       or to_regclass('fitmatch_vnext.manual_cross_comparison_rules') is null
       or to_regprocedure('fitmatch_vnext.product_comparison_unit_decision(uuid)') is null
       or to_regprocedure('fitmatch_vnext.effective_target_classification(uuid)') is null
       or to_regprocedure('fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)') is null
       or to_regprocedure('fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)') is null
       or to_regprocedure('fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)') is null
       or to_regprocedure('fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)') is null
       or to_regprocedure('fitmatch_vnext.find_reference_candidates(uuid,uuid)') is null
       or to_regprocedure('fitmatch_vnext.product_readiness(uuid)') is null
       or to_regprocedure('fitmatch_vnext.product_readiness_with_context(uuid,jsonb)') is null then
        raise exception 'User-guided comparison preflight: required vNext contract is missing';
    end if;

    if exists (
        select 1
        from (values
            ('garment_types', 'garment_type_code'),
            ('garment_types', 'comparison_policy_code'),
            ('garment_types', 'is_active'),
            ('products', 'id'),
            ('products', 'classification_status'),
            ('products', 'garment_type_code'),
            ('products', 'audience_code'),
            ('products', 'sleeve_length_code'),
            ('products', 'lower_length_code'),
            ('products', 'body_length_code'),
            ('closet_items', 'id'),
            ('closet_items', 'user_id'),
            ('closet_items', 'deleted_at'),
            ('closet_items', 'product_id'),
            ('closet_items', 'product_variant_id'),
            ('closet_items', 'product_size_id'),
            ('closet_items', 'item_name'),
            ('closet_items', 'size_label'),
            ('closet_items', 'audience_code'),
            ('closet_items', 'garment_type_code'),
            ('closet_items', 'sleeve_length_code'),
            ('closet_items', 'lower_length_code'),
            ('closet_items', 'body_length_code'),
            ('closet_items', 'is_reference'),
            ('closet_items', 'updated_at'),
            ('closet_item_measurements', 'closet_item_id'),
            ('closet_item_measurements', 'fitmatch_measurement_code'),
            ('closet_item_measurements', 'value'),
            ('product_variants', 'id'),
            ('product_variants', 'product_id'),
            ('product_variants', 'sort_order'),
            ('product_sizes', 'id'),
            ('product_sizes', 'variant_id'),
            ('product_sizes', 'size_label'),
            ('product_sizes', 'sort_order'),
            ('size_availability_observations', 'id'),
            ('size_availability_observations', 'product_size_id'),
            ('size_availability_observations', 'availability_status'),
            ('size_availability_observations', 'observed_at'),
            ('size_availability_observations', 'valid_until'),
            ('size_availability_observations', 'evidence_fingerprint'),
            ('comparison_policies', 'policy_code'),
            ('comparison_policies', 'audience_policy_code'),
            ('comparison_policies', 'sleeve_mismatch_policy'),
            ('comparison_policies', 'lower_length_mismatch_policy'),
            ('comparison_policies', 'body_length_mismatch_policy'),
            ('comparison_policies', 'min_common_measurements'),
            ('comparison_policies', 'required_any_min'),
            ('comparison_policies', 'policy_version'),
            ('comparison_policies', 'policy_checksum'),
            ('comparison_policies', 'is_active'),
            ('comparison_metrics', 'comparison_policy_code'),
            ('comparison_metrics', 'metric_mode'),
            ('comparison_metrics', 'fitmatch_measurement_code'),
            ('comparison_metrics', 'weight'),
            ('comparison_metrics', 'requirement_mode'),
            ('comparison_metrics', 'priority'),
            ('comparison_metrics', 'is_active'),
            ('manual_cross_comparison_rules', 'policy_code_a'),
            ('manual_cross_comparison_rules', 'policy_code_b'),
            ('manual_cross_comparison_rules', 'reason'),
            ('manual_cross_comparison_rules', 'is_active'),
            ('manual_cross_comparison_rules', 'require_same_sleeve')
        ) as required_column(table_name, column_name)
        where not exists (
            select 1
            from information_schema.columns column_info
            where column_info.table_schema = 'fitmatch_vnext'
              and column_info.table_name = required_column.table_name
              and column_info.column_name = required_column.column_name
        )
    ) then
        raise exception 'User-guided comparison preflight: required vNext column is missing';
    end if;

    authorization_definition := pg_get_functiondef(
        'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure
    );
    candidates_definition := pg_get_functiondef(
        'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)'::regprocedure
    );
    discovery_definition := pg_get_functiondef(
        'fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure
    );
    readiness_definition := pg_get_functiondef(
        'fitmatch_vnext.product_readiness(uuid)'::regprocedure
    );

    if position('product_comparison_unit_decision' in authorization_definition) = 0
       or position('availability_status is distinct from ''AVAILABLE''' in candidates_definition) = 0
       or position('order by ci.created_at, ci.id' in discovery_definition) = 0
       or position('NO_AVAILABLE_SIZE' in readiness_definition) = 0 then
        raise exception 'User-guided comparison preflight: unexpected comparison gate preimage';
    end if;

    if exists (
        select 1
        from pg_proc p
        where p.oid in (
            'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
            'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
            'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)'::regprocedure,
            'fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure
        )
          and (not p.prosecdef or pg_get_userbyid(p.proowner) <> 'postgres')
    ) then
        raise exception 'User-guided comparison preflight: security-definer owner mismatch';
    end if;

    if has_function_privilege(
           'public',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       )
       or has_function_privilege(
           'anon',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       )
       or not has_function_privilege(
           'authenticated',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       )
       or not has_function_privilege(
           'service_role',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       ) then
        raise exception 'User-guided comparison preflight: public authorization ACL mismatch';
    end if;

    if to_regclass('supabase_migrations.schema_migrations') is not null
       and exists (
           select 1
           from supabase_migrations.schema_migrations
           where version = '20260903072641'
       ) then
        raise exception 'User-guided comparison migration ledger already contains 20260903072641';
    end if;
end
$preflight$;

-- A garment type, rather than a client category string, owns the coarse
-- measurement domain.  Existing same-policy comparisons remain unchanged;
-- this field is used only for user-selected cross-garment expansion.
alter table fitmatch_vnext.garment_types
    add column if not exists comparison_measurement_domain_code text;

update fitmatch_vnext.garment_types
set comparison_measurement_domain_code = case
    when comparison_policy_code in (
        'anorak', 'base_layer_top', 'blazer', 'blouson', 'bodysuit_top',
        'cardigan', 'coat', 'fleece_jacket', 'homewear_top', 'hoodie',
        'jacket', 'knit_sweater', 'knit_vest', 'ma1', 'mouton',
        'outer_vest', 'polo_shirt', 'puffer_jacket', 'puffer_vest',
        'shirt_blouse', 'sleeveless_tshirt', 'sports_top', 'sweatshirt',
        'tank_top', 'tshirt', 'windbreaker', 'zip_hoodie'
    ) then 'UPPER_BODY'
    when comparison_policy_code in (
        'homewear_bottom', 'leggings', 'skirt', 'standard_pants'
    ) then 'LOWER_BODY'
    when comparison_policy_code = 'dress' then 'FULL_BODY'
    when comparison_policy_code in (
        'men_briefs', 'men_trunks', 'men_undershirt', 'women_bra',
        'women_camisole', 'women_panty', 'women_slip'
    ) then 'OTHER'
    else 'UNKNOWN'
end
where comparison_measurement_domain_code is distinct from case
    when comparison_policy_code in (
        'anorak', 'base_layer_top', 'blazer', 'blouson', 'bodysuit_top',
        'cardigan', 'coat', 'fleece_jacket', 'homewear_top', 'hoodie',
        'jacket', 'knit_sweater', 'knit_vest', 'ma1', 'mouton',
        'outer_vest', 'polo_shirt', 'puffer_jacket', 'puffer_vest',
        'shirt_blouse', 'sleeveless_tshirt', 'sports_top', 'sweatshirt',
        'tank_top', 'tshirt', 'windbreaker', 'zip_hoodie'
    ) then 'UPPER_BODY'
    when comparison_policy_code in (
        'homewear_bottom', 'leggings', 'skirt', 'standard_pants'
    ) then 'LOWER_BODY'
    when comparison_policy_code = 'dress' then 'FULL_BODY'
    when comparison_policy_code in (
        'men_briefs', 'men_trunks', 'men_undershirt', 'women_bra',
        'women_camisole', 'women_panty', 'women_slip'
    ) then 'OTHER'
    else 'UNKNOWN'
end;

update fitmatch_vnext.garment_types
set comparison_measurement_domain_code = 'UNKNOWN'
where comparison_measurement_domain_code is null;

alter table fitmatch_vnext.garment_types
    alter column comparison_measurement_domain_code set default 'UNKNOWN',
    alter column comparison_measurement_domain_code set not null;

do $domain_constraint$
begin
    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'fitmatch_vnext.garment_types'::regclass
          and conname = 'garment_types_comparison_measurement_domain_check'
    ) then
        alter table fitmatch_vnext.garment_types
            add constraint garment_types_comparison_measurement_domain_check
            check (comparison_measurement_domain_code in (
                'UPPER_BODY', 'LOWER_BODY', 'FULL_BODY', 'OTHER', 'UNKNOWN'
            ));
    end if;
end
$domain_constraint$;

-- One authoritative pair decision.  It intentionally has no availability
-- predicate: availability is projected only as retailer metadata.
create or replace function fitmatch_vnext.comparison_decision(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean,
    p_effective_classification jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    ref fitmatch_vnext.closet_items%rowtype;
    target fitmatch_vnext.products%rowtype;
    ref_gt fitmatch_vnext.garment_types%rowtype;
    target_gt fitmatch_vnext.garment_types%rowtype;
    policy fitmatch_vnext.comparison_policies%rowtype;
    unit_value jsonb;
    target_measurements jsonb;
    availability_value jsonb;
    excluded text[] := '{}'::text[];
    used_codes text[] := '{}'::text[];
    required_codes text[] := '{}'::text[];
    excluded_reasons jsonb := '[]'::jsonb;
    common_count integer := 0;
    required_any_count integer := 0;
    audience_ok boolean := false;
    sleeve_mismatch boolean := false;
    lower_mismatch boolean := false;
    body_mismatch boolean := false;
    conservative_axis_mismatch boolean := false;
    same_policy boolean := false;
    manual_rule_exists boolean := false;
    manual_rule_requires_same_sleeve boolean := false;
    manual_rule_fingerprint text;
    reference_domain text := 'UNKNOWN';
    target_domain text := 'UNKNOWN';
    decision_value text := 'BLOCKED';
    mode_value text := 'NONE';
    reason_code_value text := 'INVALID_AUTHORITY';
    reason_value text := 'Comparison authority is invalid';
    allowed_value boolean := false;
    authority_fingerprint_value text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    select * into ref
    from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id
      and ci.deleted_at is null;
    if not found then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'INVALID_AUTHORITY',
            'reason', 'Reference is missing or not owned'
        );
    end if;

    select * into target
    from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found
       or p_effective_classification is null
       or jsonb_typeof(p_effective_classification) <> 'object'
       or p_effective_classification ->> 'product_id' is distinct from
            p_target_product_id::text
       or p_effective_classification ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'CLASSIFICATION_REQUIRED',
            'reason', 'Target effective classification is not CONFIRMED'
        );
    end if;

    unit_value := fitmatch_vnext.product_comparison_unit_decision(target.id);
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'STRUCTURALLY_NOT_COMPARABLE',
            'reason', coalesce(unit_value ->> 'reason',
                'Target is not a comparable single garment'),
            'comparison_unit', unit_value
        );
    end if;

    if not exists (
        select 1
        from fitmatch_vnext.product_sizes ps
        join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
        where ps.id = p_target_product_size_id
          and pv.product_id = target.id
    ) then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'NO_ELIGIBLE_TARGET_SIZE',
            'reason', 'Target size hierarchy mismatch'
        );
    end if;

    select * into ref_gt
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code = ref.garment_type_code
      and gt.is_active;
    select * into target_gt
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code = p_effective_classification ->> 'garment_type_code'
      and gt.is_active;
    if ref_gt.garment_type_code is null or target_gt.garment_type_code is null then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'INVALID_AUTHORITY',
            'reason', 'Reference or target garment authority is invalid'
        );
    end if;

    reference_domain := ref_gt.comparison_measurement_domain_code;
    target_domain := target_gt.comparison_measurement_domain_code;
    select * into policy
    from fitmatch_vnext.comparison_policies cp
    where cp.policy_code = target_gt.comparison_policy_code
      and cp.is_active;
    if not found then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'STRUCTURALLY_NOT_COMPARABLE',
            'reason', 'Comparison policy unavailable',
            'reference_measurement_domain', reference_domain,
            'target_measurement_domain', target_domain
        );
    end if;

    audience_ok := case policy.audience_policy_code
        when 'IGNORE' then true
        when 'ADULT_ANY' then ref.audience_code in ('MEN', 'WOMEN', 'UNISEX')
            and p_effective_classification ->> 'audience_code'
                in ('MEN', 'WOMEN', 'UNISEX')
        when 'SAME_ONLY' then ref.audience_code =
            p_effective_classification ->> 'audience_code'
        else ref.audience_code = p_effective_classification ->> 'audience_code'
            or ref.audience_code = 'UNISEX'
            or p_effective_classification ->> 'audience_code' = 'UNISEX'
    end;
    if not audience_ok then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason_code', 'INCOMPATIBLE_AUDIENCE',
            'reason', 'Reference and target audiences are incompatible',
            'reference_measurement_domain', reference_domain,
            'target_measurement_domain', target_domain
        );
    end if;

    sleeve_mismatch := ref.sleeve_length_code is distinct from
        p_effective_classification ->> 'sleeve_length_code';
    lower_mismatch := ref.lower_length_code is distinct from
        p_effective_classification ->> 'lower_length_code';
    body_mismatch := ref.body_length_code is distinct from
        p_effective_classification ->> 'body_length_code';
    conservative_axis_mismatch :=
        (sleeve_mismatch and policy.sleeve_mismatch_policy = 'REQUIRE_MATCH')
        or (lower_mismatch and policy.lower_length_mismatch_policy = 'REQUIRE_MATCH')
        or (body_mismatch and policy.body_length_mismatch_policy = 'REQUIRE_MATCH');

    if sleeve_mismatch then
        excluded := excluded || array['sleeve_length'];
    end if;
    if lower_mismatch then
        excluded := excluded || array[
            'total_length', 'back_length', 'front_length', 'inseam',
            'outseam', 'hem_width', 'hem_circumference'
        ];
    end if;
    if body_mismatch then
        excluded := excluded || array['total_length', 'back_length', 'front_length'];
    end if;
    select coalesce(array_agg(distinct code order by code), '{}'::text[])
    into excluded
    from unnest(excluded) code;
    select coalesce(jsonb_agg(jsonb_build_object(
        'measurement_code', code,
        'reason_code', 'DESIGN_AXIS_DIFFERENCE'
    ) order by code), '[]'::jsonb)
    into excluded_reasons
    from unnest(excluded) code;

    same_policy := ref_gt.comparison_policy_code = target_gt.comparison_policy_code;
    if not p_manual_explicit then
        if not same_policy or conservative_axis_mismatch then
            return jsonb_build_object(
                'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
                'reason_code', 'NO_AUTOMATIC_REFERENCE',
                'reason', 'Explicit reference selection is required',
                'manual_explicit_required', true,
                'reference_measurement_domain', reference_domain,
                'target_measurement_domain', target_domain,
                'excluded_measurement_codes', to_jsonb(excluded),
                'excluded_measurement_reasons', excluded_reasons,
                'exclusion_reasons', excluded_reasons
            );
        end if;
        decision_value := 'AUTOMATIC';
        mode_value := 'AUTOMATIC';
        allowed_value := true;
        reason_code_value := 'AUTOMATIC_MATCH';
        reason_value := 'Automatic comparison policy is satisfied';
    elsif same_policy then
        decision_value := 'MANUAL_EXTENDED';
        mode_value := 'MANUAL_EXTENDED';
        allowed_value := true;
        reason_code_value := 'USER_SELECTED_REFERENCE';
        reason_value := 'User-selected reference is structurally comparable';
    else
        select true, r.require_same_sleeve,
               encode(extensions.digest(concat_ws('|',
                   r.policy_code_a, r.policy_code_b, r.reason,
                   r.is_active::text, r.require_same_sleeve::text,
                   'fitmatch-vnext-manual-cross-rule-v1'
               ), 'sha256'), 'hex')
        into manual_rule_exists, manual_rule_requires_same_sleeve,
             manual_rule_fingerprint
        from fitmatch_vnext.manual_cross_comparison_rules r
        where r.policy_code_a = least(
                  ref_gt.comparison_policy_code,
                  target_gt.comparison_policy_code
              )
          and r.policy_code_b = greatest(
                  ref_gt.comparison_policy_code,
                  target_gt.comparison_policy_code
              )
          and r.is_active
        limit 1;

        if coalesce(manual_rule_exists, false)
           and coalesce(manual_rule_requires_same_sleeve, false)
           and sleeve_mismatch then
            return jsonb_build_object(
                'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
                'reason_code', 'DESIGN_AXIS_DIFFERENCE',
                'reason', 'The existing manual-cross rule requires matching sleeves',
                'reference_measurement_domain', reference_domain,
                'target_measurement_domain', target_domain,
                'excluded_measurement_codes', to_jsonb(excluded),
                'excluded_measurement_reasons', excluded_reasons,
                'exclusion_reasons', excluded_reasons
            );
        end if;

        if coalesce(manual_rule_exists, false) then
            decision_value := 'MANUAL_EXTENDED';
            mode_value := 'MANUAL_EXTENDED';
            allowed_value := true;
            reason_code_value := 'USER_SELECTED_REFERENCE';
            reason_value := 'Existing explicit manual-cross rule is satisfied';
        elsif (reference_domain = 'UPPER_BODY' and target_domain = 'LOWER_BODY')
           or (reference_domain = 'LOWER_BODY' and target_domain = 'UPPER_BODY') then
            return jsonb_build_object(
                'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
                'reason_code', 'INCOMPATIBLE_BODY_REGION',
                'reason', 'Upper-body and lower-body measurements are not comparable',
                'reference_measurement_domain', reference_domain,
                'target_measurement_domain', target_domain,
                'excluded_measurement_codes', to_jsonb(excluded),
                'excluded_measurement_reasons', excluded_reasons,
                'exclusion_reasons', excluded_reasons
            );
        elsif reference_domain = target_domain
           and reference_domain in ('UPPER_BODY', 'LOWER_BODY') then
            decision_value := 'MANUAL_EXTENDED';
            mode_value := 'MANUAL_EXTENDED';
            allowed_value := true;
            reason_code_value := 'USER_SELECTED_REFERENCE';
            reason_value := 'User-selected references share a server-owned measurement domain';
        else
            return jsonb_build_object(
                'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
                'reason_code', 'STRUCTURALLY_NOT_COMPARABLE',
                'reason', 'No supported manual comparison expansion exists for these domains',
                'reference_measurement_domain', reference_domain,
                'target_measurement_domain', target_domain,
                'excluded_measurement_codes', to_jsonb(excluded),
                'excluded_measurement_reasons', excluded_reasons,
                'exclusion_reasons', excluded_reasons
            );
        end if;
    end if;

    target_measurements := fitmatch_vnext.canonical_measurements_for_size_with_context(
        p_target_product_size_id, p_effective_classification
    );
    select coalesce(array_agg(cm.fitmatch_measurement_code order by cm.priority,
        cm.fitmatch_measurement_code) filter (where cm.requirement_mode = 'REQUIRED_ANY'),
        '{}'::text[])
    into required_codes
    from fitmatch_vnext.comparison_metrics cm
    where cm.comparison_policy_code = policy.policy_code
      and cm.metric_mode = 'CANONICAL'
      and cm.is_active
      and not (cm.fitmatch_measurement_code = any(excluded));

    with reference_codes as (
        select distinct fitmatch_measurement_code code
        from fitmatch_vnext.closet_item_measurements
        where closet_item_id = ref.id
          and fitmatch_measurement_code is not null
    ), target_codes as (
        select distinct measurement ->> 'fitmatch_measurement_code' code
        from jsonb_array_elements(target_measurements -> 'measurements') measurement
    ), policy_codes as (
        select distinct cm.fitmatch_measurement_code code, cm.requirement_mode
        from fitmatch_vnext.comparison_metrics cm
        where cm.comparison_policy_code = policy.policy_code
          and cm.metric_mode = 'CANONICAL'
          and cm.is_active
          and not (cm.fitmatch_measurement_code = any(excluded))
    ), common_codes as (
        select policy_codes.*
        from policy_codes
        join reference_codes using (code)
        join target_codes using (code)
    )
    select count(*),
           count(*) filter (where requirement_mode = 'REQUIRED_ANY'),
           coalesce(array_agg(code order by code), '{}'::text[])
    into common_count, required_any_count, used_codes
    from common_codes;

    if common_count < 1 then
        decision_value := 'MEASUREMENTS_REQUIRED';
        mode_value := 'NONE';
        allowed_value := false;
        reason_code_value := 'NO_COMMON_MEASUREMENTS';
        reason_value := 'No meaningful common canonical measurements remain';
    end if;

    select jsonb_build_object(
        'status', case
            when availability.availability_status is null then 'UNKNOWN'
            when availability.valid_until is not null
                 and availability.valid_until < now() then 'UNKNOWN'
            when availability.availability_status in ('AVAILABLE', 'SOLD_OUT', 'UNKNOWN')
                then availability.availability_status
            else 'UNKNOWN'
        end,
        'observed_at', availability.observed_at,
        'valid_until', availability.valid_until,
        'evidence_fingerprint', availability.evidence_fingerprint
    )
    into availability_value
    from (select 1) anchor
    left join lateral (
        select o.availability_status, o.observed_at, o.valid_until,
               o.evidence_fingerprint
        from fitmatch_vnext.size_availability_observations o
        where o.product_size_id = p_target_product_size_id
        order by o.observed_at desc, o.id desc
        limit 1
    ) availability on true;

    authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
        ref.id::text,
        target.id::text,
        p_target_product_size_id::text,
        p_manual_explicit::text,
        coalesce(p_effective_classification ->> 'effective_authority_fingerprint', '∅'),
        policy.policy_code,
        policy.policy_checksum,
        reference_domain,
        target_domain,
        array_to_string(used_codes, ','),
        array_to_string(excluded, ','),
        'fitmatch-vnext-comparison-decision-v4'
    ), 'sha256'), 'hex');

    return jsonb_strip_nulls(jsonb_build_object(
        'decision', decision_value,
        'allowed', allowed_value,
        'mode', mode_value,
        'reason_code', reason_code_value,
        'reason', reason_value,
        'manual_explicit_required', not p_manual_explicit
            and decision_value = 'BLOCKED'
            and reason_code_value = 'NO_AUTOMATIC_REFERENCE',
        'reference_measurement_domain', reference_domain,
        'target_measurement_domain', target_domain,
        'used_measurement_codes', to_jsonb(used_codes),
        'common_measurement_count', common_count,
        'excluded_measurement_codes', to_jsonb(excluded),
        'excluded_measurement_reasons', excluded_reasons,
        'exclusion_reasons', excluded_reasons,
        'required_measurement_codes', to_jsonb(required_codes),
        'minimum_common', 1,
        'required_any_count', required_any_count,
        'policy_minimum_common', policy.min_common_measurements,
        'policy_required_any_min', policy.required_any_min,
        'policy_code', policy.policy_code,
        'policy_version', policy.policy_version,
        'policy_checksum', policy.policy_checksum,
        'effective_availability', availability_value,
        'effective_authority_fingerprint',
            p_effective_classification ->> 'effective_authority_fingerprint',
        'override_revision', p_effective_classification -> 'override_revision',
        'authority_fingerprint', authority_fingerprint_value,
        'manual_cross_rule', case when manual_rule_exists then jsonb_build_object(
            'require_same_sleeve', manual_rule_requires_same_sleeve,
            'rule_fingerprint', manual_rule_fingerprint
        ) end,
        'authorization_version', 'fitmatch-vnext-authorization-v4'
    ));
end
$function$;

-- Retain the existing public signatures.  Context-aware and regular callers
-- now share one decision implementation, so policy cannot drift between them.
create or replace function fitmatch_vnext.authorize_comparison_with_context(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean,
    p_effective_classification jsonb
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
    select fitmatch_vnext.comparison_decision(
        p_reference_closet_item_id,
        p_target_product_id,
        p_target_product_size_id,
        p_manual_explicit,
        p_effective_classification
    )
$function$;

create or replace function fitmatch_vnext.authorize_comparison(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    effective_value jsonb;
begin
    effective_value := fitmatch_vnext.effective_target_classification(
        p_target_product_id
    );
    return fitmatch_vnext.comparison_decision(
        p_reference_closet_item_id,
        p_target_product_id,
        p_target_product_size_id,
        p_manual_explicit,
        effective_value
    );
end
$function$;

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
    effective_value jsonb;
    size_row record;
    canonical_value jsonb;
    authorization_value jsonb;
    comparison_measurements_value jsonb;
    candidates_value jsonb := '[]'::jsonb;
    fingerprint_candidates_value jsonb := '[]'::jsonb;
    candidate_value jsonb;
    fingerprint_candidate_value jsonb;
    semantic_conflict_count_value integer := 0;
    authorization_rejected_count_value integer := 0;
    rejected_reason_code_value text;
    total_size_count_value integer := 0;
    authority_fingerprint_value text;
    authority_version_value constant text := 'fitmatch-vnext-candidates-v3';
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

    effective_value := fitmatch_vnext.effective_target_classification(target_row.id);
    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'allowed', false,
            'decision', 'BLOCKED',
            'mode', 'NONE',
            'reason_code', 'CLASSIFICATION_REQUIRED',
            'reason', 'Target effective classification is not CONFIRMED',
            'effective_classification', effective_value,
            'authorized_candidate_product_size_ids', '[]'::jsonb,
            'candidates', '[]'::jsonb,
            'candidate_authority_version', authority_version_value
        );
    end if;
    if not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = p_target_variant_id
          and pv.product_id = p_target_product_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    for size_row in
        select ps.id product_size_id, ps.size_label, ps.sort_order
        from fitmatch_vnext.product_sizes ps
        where ps.variant_id = p_target_variant_id
        order by ps.sort_order, ps.id
    loop
        total_size_count_value := total_size_count_value + 1;
        canonical_value := fitmatch_vnext.canonical_measurements_for_size_with_context(
            size_row.product_size_id, effective_value
        );
        if coalesce((canonical_value ->> 'semantic_conflict_count')::integer, 0) > 0 then
            semantic_conflict_count_value := semantic_conflict_count_value + 1;
            continue;
        end if;

        authorization_value := fitmatch_vnext.comparison_decision(
            reference_row.id,
            target_row.id,
            size_row.product_size_id,
            p_manual_explicit,
            effective_value
        );
        if not coalesce((authorization_value ->> 'allowed')::boolean, false) then
            authorization_rejected_count_value := authorization_rejected_count_value + 1;
            rejected_reason_code_value := coalesce(
                rejected_reason_code_value,
                authorization_value ->> 'reason_code'
            );
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
        join lateral jsonb_array_elements(canonical_value -> 'measurements')
            target_measurement
          on target_measurement ->> 'fitmatch_measurement_code' =
             cm.fitmatch_measurement_code
        where cm.comparison_policy_code = authorization_value ->> 'policy_code'
          and cm.metric_mode = 'CANONICAL'
          and cm.is_active
          and cm.fitmatch_measurement_code = any(coalesce(
              array(select jsonb_array_elements_text(
                  authorization_value -> 'used_measurement_codes'
              )), '{}'::text[]
          ));

        -- The helper's execution threshold is the source of truth.  This
        -- guards malformed function output without re-applying policy minima.
        if jsonb_array_length(comparison_measurements_value) < 1 then
            authorization_rejected_count_value := authorization_rejected_count_value + 1;
            rejected_reason_code_value := coalesce(
                rejected_reason_code_value,
                'NO_COMMON_MEASUREMENTS'
            );
            continue;
        end if;

        candidate_value := jsonb_build_object(
            'product_size_id', size_row.product_size_id,
            'size_label', size_row.size_label,
            'availability', authorization_value -> 'effective_availability',
            'canonical_measurements', canonical_value,
            'comparison_measurements', comparison_measurements_value,
            'authorization', authorization_value
        );
        candidates_value := candidates_value || jsonb_build_array(candidate_value);

        -- Availability remains in the immutable presentation snapshot but is
        -- intentionally excluded from the authority fingerprint.
        fingerprint_candidate_value := candidate_value - 'availability';
        fingerprint_candidate_value := jsonb_set(
            fingerprint_candidate_value,
            '{authorization}',
            (candidate_value -> 'authorization') - 'effective_availability',
            true
        );
        fingerprint_candidates_value := fingerprint_candidates_value
            || jsonb_build_array(fingerprint_candidate_value);
    end loop;

    authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
        reference_row.id::text,
        target_row.id::text,
        p_target_variant_id::text,
        p_manual_explicit::text,
        coalesce(effective_value ->> 'effective_authority_fingerprint', '∅'),
        fingerprint_candidates_value::text,
        authority_version_value
    ), 'sha256'), 'hex');

    return jsonb_build_object(
        'allowed', jsonb_array_length(candidates_value) > 0,
        'decision', case when jsonb_array_length(candidates_value) > 0
            then coalesce(candidates_value -> 0 -> 'authorization' ->> 'decision', 'BLOCKED')
            else 'BLOCKED' end,
        'mode', case when jsonb_array_length(candidates_value) > 0
            then coalesce(candidates_value -> 0 -> 'authorization' ->> 'mode', 'NONE')
            else 'NONE' end,
        'reason_code', case
            when jsonb_array_length(candidates_value) > 0 then null
            when total_size_count_value = 0 then 'NO_ELIGIBLE_TARGET_SIZE'
            else coalesce(rejected_reason_code_value, 'NO_ELIGIBLE_TARGET_SIZE')
            end,
        'reason', case
            when jsonb_array_length(candidates_value) > 0
                then 'Database-generated measurement candidate set'
            when total_size_count_value = 0 then 'Target variant has no sizes'
            when semantic_conflict_count_value = total_size_count_value
                then 'Canonical measurement semantic conflict'
            else 'No size satisfies comparison authority and common measurement requirements'
            end,
        'reference_closet_item_id', reference_row.id,
        'target_product_id', target_row.id,
        'target_variant_id', p_target_variant_id,
        'manual_explicit', p_manual_explicit,
        'classification_source', effective_value ->> 'effective_source',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'override_revision', effective_value -> 'override_revision',
        'authorized_candidate_product_size_ids', coalesce((
            select jsonb_agg(candidate -> 'product_size_id')
            from jsonb_array_elements(candidates_value) candidate
        ), '[]'::jsonb),
        'candidates', candidates_value,
        'diagnostics', jsonb_build_object(
            'total_size_count', total_size_count_value,
            'semantic_conflict_count', semantic_conflict_count_value,
            'authorization_rejected_count', authorization_rejected_count_value
        ),
        'candidate_authority_fingerprint', authority_fingerprint_value,
        'candidate_authority_version', authority_version_value
    );
end
$function$;

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
    effective_value jsonb;
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
    reason_code_value text;
    measurement_required_seen boolean;
    candidates_value jsonb := '[]'::jsonb;
    blocked_value jsonb := '[]'::jsonb;
    item_value jsonb;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    select * into target_row
    from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found then
        raise exception 'Target product not found';
    end if;
    effective_value := fitmatch_vnext.effective_target_classification(target_row.id);
    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'target_product_id', target_row.id,
            'target_variant_id', p_target_variant_id,
            'effective_classification', effective_value,
            'candidates', '[]'::jsonb,
            'blocked', '[]'::jsonb,
            'status', 'BLOCKED',
            'reason_code', 'CLASSIFICATION_REQUIRED',
            'reason', 'Target effective classification is not CONFIRMED',
            'reference_candidate_version', 'fitmatch-vnext-reference-candidates-v3'
        );
    end if;
    if p_target_variant_id is not null and not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = p_target_variant_id
          and pv.product_id = target_row.id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    -- This is presentation/order authority for automatic selection.  A local
    -- isRepresentative value never determines eligibility.
    for closet_row in
        select *
        from fitmatch_vnext.closet_items ci
        where ci.user_id = caller_id
          and ci.deleted_at is null
        order by (ci.product_id = target_row.id) desc,
                 ci.is_reference desc,
                 ci.updated_at desc,
                 ci.id
    loop
        automatic_ids := '{}'::uuid[];
        manual_ids := '{}'::uuid[];
        selected_authorization := null;
        measurement_required_seen := false;
        reason_value := null;
        reason_code_value := null;

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
            if coalesce((automatic_result ->> 'allowed')::boolean, false)
               and automatic_result ->> 'decision' = 'AUTOMATIC' then
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
                reason_code_value := coalesce(
                    reason_code_value,
                    automatic_result ->> 'reason_code'
                );
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
                else
                    reason_value := coalesce(reason_value, manual_result ->> 'reason');
                    reason_code_value := coalesce(
                        reason_code_value,
                        manual_result ->> 'reason_code'
                    );
                end if;
            end if;
        end loop;

        if cardinality(automatic_ids) > 0 then
            decision_value := 'AUTOMATIC';
            reason_value := selected_authorization ->> 'reason';
            reason_code_value := selected_authorization ->> 'reason_code';
        elsif cardinality(manual_ids) > 0 then
            decision_value := 'MANUAL_EXTENDED';
            reason_value := selected_authorization ->> 'reason';
            reason_code_value := selected_authorization ->> 'reason_code';
        else
            for size_row in
                select ps.id
                from fitmatch_vnext.product_sizes ps
                join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
                where pv.product_id = target_row.id
                  and (p_target_variant_id is null or pv.id = p_target_variant_id)
                order by pv.sort_order, ps.sort_order, ps.id
            loop
                authorization_result := fitmatch_vnext.comparison_decision(
                    closet_row.id, target_row.id, size_row.id, true, effective_value
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
                reason_code_value := selected_authorization ->> 'reason_code';
            else
                decision_value := 'BLOCKED';
                reason_value := coalesce(
                    selected_authorization ->> 'reason', reason_value,
                    'No target size can be authorized'
                );
                reason_code_value := coalesce(
                    selected_authorization ->> 'reason_code', reason_code_value,
                    'NO_ELIGIBLE_TARGET_SIZE'
                );
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
            'allowed', decision_value in ('AUTOMATIC', 'MANUAL_EXTENDED'),
            'mode', case when decision_value in ('AUTOMATIC', 'MANUAL_EXTENDED')
                then decision_value else 'NONE' end,
            'manual_explicit_required', decision_value = 'MANUAL_EXTENDED',
            'reason_code', reason_code_value,
            'reason', reason_value,
            'common_measurement_count',
                (selected_authorization ->> 'common_measurement_count')::integer,
            'required_any_count',
                (selected_authorization ->> 'required_any_count')::integer,
            'minimum_common',
                (selected_authorization ->> 'minimum_common')::integer,
            'used_measurement_codes', coalesce(
                selected_authorization -> 'used_measurement_codes', '[]'::jsonb
            ),
            'excluded_measurement_codes', coalesce(
                selected_authorization -> 'excluded_measurement_codes', '[]'::jsonb
            ),
            'excluded_measurement_reasons', coalesce(
                selected_authorization -> 'excluded_measurement_reasons', '[]'::jsonb
            ),
            'reference_measurement_domain',
                selected_authorization ->> 'reference_measurement_domain',
            'target_measurement_domain',
                selected_authorization ->> 'target_measurement_domain',
            'policy_code', selected_authorization ->> 'policy_code',
            'policy_version', selected_authorization ->> 'policy_version',
            'policy_checksum', selected_authorization ->> 'policy_checksum',
            'eligible_product_size_ids', case
                when decision_value = 'AUTOMATIC' then to_jsonb(automatic_ids)
                when decision_value = 'MANUAL_EXTENDED' then to_jsonb(manual_ids)
                else '[]'::jsonb end,
            '_same_retailer_product', closet_row.product_id = target_row.id,
            '_is_reference_hint', closet_row.is_reference,
            '_updated_at', closet_row.updated_at,
            '_uuid', closet_row.id
        );
        if decision_value = 'BLOCKED' then
            blocked_value := blocked_value || jsonb_build_array(item_value);
        else
            candidates_value := candidates_value || jsonb_build_array(item_value);
        end if;
    end loop;

    select coalesce(jsonb_agg(value - array[
        '_same_retailer_product', '_is_reference_hint', '_updated_at', '_uuid'
    ] order by
        coalesce((value ->> '_same_retailer_product')::boolean, false) desc,
        coalesce((value ->> '_is_reference_hint')::boolean, false) desc,
        case value ->> 'decision'
            when 'AUTOMATIC' then 0
            when 'MANUAL_EXTENDED' then 1
            when 'MEASUREMENTS_REQUIRED' then 2
            else 3 end,
        coalesce((value ->> 'common_measurement_count')::integer, 0) desc,
        value ->> '_updated_at' desc,
        value ->> '_uuid'
    ), '[]'::jsonb)
    into candidates_value
    from jsonb_array_elements(candidates_value) value;

    select coalesce(jsonb_agg(value - array[
        '_same_retailer_product', '_is_reference_hint', '_updated_at', '_uuid'
    ] order by
        coalesce((value ->> '_same_retailer_product')::boolean, false) desc,
        coalesce((value ->> '_is_reference_hint')::boolean, false) desc,
        coalesce((value ->> 'common_measurement_count')::integer, 0) desc,
        value ->> '_updated_at' desc,
        value ->> '_uuid'
    ), '[]'::jsonb)
    into blocked_value
    from jsonb_array_elements(blocked_value) value;

    return jsonb_build_object(
        'target_product_id', target_row.id,
        'target_variant_id', p_target_variant_id,
        'effective_classification', effective_value,
        'candidates', candidates_value,
        'blocked', blocked_value,
        'candidate_count', jsonb_array_length(candidates_value),
        'blocked_count', jsonb_array_length(blocked_value),
        'status', case when jsonb_array_length(candidates_value) > 0
            then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
        'reason_code', case when jsonb_array_length(candidates_value) > 0
            then null else 'NO_AUTOMATIC_REFERENCE' end,
        'reference_candidate_version', 'fitmatch-vnext-reference-candidates-v3'
    );
end
$function$;

-- Product readiness remains product-level.  It only asks whether a confirmed
-- product has one semantically usable canonical metric; pair authorization is
-- left to comparison_decision above.
create or replace function fitmatch_vnext.product_measurement_readiness(
    p_product_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
with product_row as (
    select p.*,
           p_effective_classification ->> 'classification_status' effective_status,
           p_effective_classification ->> 'comparison_policy_code' effective_policy_code,
           fitmatch_vnext.product_comparison_unit_decision(p.id) comparison_unit
    from fitmatch_vnext.products p
    where p.id = p_product_id
), policy_metrics as (
    select cm.fitmatch_measurement_code
    from product_row p
    join fitmatch_vnext.comparison_policies cp
      on cp.policy_code = p.effective_policy_code
     and cp.is_active
    join fitmatch_vnext.comparison_metrics cm
      on cm.comparison_policy_code = cp.policy_code
     and cm.metric_mode = 'CANONICAL'
     and cm.is_active
), size_diagnostics as (
    select ps.id product_size_id,
           ps.size_label,
           coalesce((canonical.payload ->> 'raw_measurement_count')::integer, 0)
               raw_measurement_count,
           coalesce((canonical.payload ->> 'semantic_conflict_count')::integer, 0)
               semantic_conflict_count,
           count(distinct pm.fitmatch_measurement_code) resolved_count
    from product_row p
    join fitmatch_vnext.product_variants pv on pv.product_id = p.id
    join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
    cross join lateral (
        select fitmatch_vnext.canonical_measurements_for_size_with_context(
            ps.id, p_effective_classification
        ) payload
    ) canonical
    left join lateral jsonb_array_elements(canonical.payload -> 'measurements') measurement
      on true
    left join policy_metrics pm
      on pm.fitmatch_measurement_code = measurement ->> 'fitmatch_measurement_code'
    group by ps.id, ps.size_label, canonical.payload
), ready_sizes as (
    select *
    from size_diagnostics
    where semantic_conflict_count = 0
      and resolved_count >= 1
)
select case when not exists (select 1 from product_row) then
    jsonb_build_object(
        'status', 'CLASSIFICATION_REQUIRED',
        'ready', false,
        'reason_code', 'CLASSIFICATION_REQUIRED',
        'reason', 'Unknown product',
        'readiness_version', 'fitmatch-vnext-readiness-v4'
    )
else (
    select jsonb_build_object(
        'product_id', p.id,
        'ready', p.effective_status = 'CONFIRMED'
            and coalesce((p.comparison_unit ->> 'eligible')::boolean, false)
            and exists (select 1 from ready_sizes),
        'status', case
            when p.effective_status <> 'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
            when not coalesce((p.comparison_unit ->> 'eligible')::boolean, false)
                then 'NOT_APPLICABLE'
            when not exists (select 1 from policy_metrics) then 'POLICY_UNAVAILABLE'
            when not exists (select 1 from size_diagnostics) then 'NO_ELIGIBLE_TARGET_SIZE'
            when not exists (
                select 1 from size_diagnostics where raw_measurement_count > 0
            ) then 'NO_MEASUREMENT_DATA'
            when not exists (
                select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0
            ) then 'INSUFFICIENT_MEASUREMENTS'
            else 'READY'
        end,
        'reason_code', case
            when p.effective_status <> 'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
            when not coalesce((p.comparison_unit ->> 'eligible')::boolean, false)
                then 'STRUCTURALLY_NOT_COMPARABLE'
            when not exists (select 1 from policy_metrics) then 'INVALID_AUTHORITY'
            when not exists (select 1 from size_diagnostics) then 'NO_ELIGIBLE_TARGET_SIZE'
            when not exists (
                select 1 from size_diagnostics where raw_measurement_count > 0
            ) then 'NO_ELIGIBLE_TARGET_SIZE'
            when not exists (
                select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0
            ) then 'NO_COMMON_MEASUREMENTS'
            else null
        end,
        'reason', case
            when p.effective_status <> 'CONFIRMED'
                then 'Effective classification is not CONFIRMED'
            when not coalesce((p.comparison_unit ->> 'eligible')::boolean, false)
                then p.comparison_unit ->> 'reason'
            when not exists (select 1 from policy_metrics)
                then 'No active comparison policy metrics'
            when not exists (select 1 from size_diagnostics)
                then 'Product has no sizes'
            when not exists (
                select 1 from size_diagnostics where raw_measurement_count > 0
            ) then 'No raw measurement evidence'
            when not exists (
                select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0
            ) then 'No semantically usable canonical measurement'
            else 'Classification and canonical measurement evidence are ready'
        end,
        'comparison_policy_code', p.effective_policy_code,
        'comparison_unit', p.comparison_unit,
        'ready_sizes', coalesce((
            select jsonb_agg(jsonb_build_object(
                'product_size_id', r.product_size_id,
                'size_label', r.size_label,
                'resolved_measurement_count', r.resolved_count,
                'semantic_conflict_count', r.semantic_conflict_count
            ) order by r.size_label, r.product_size_id)
            from ready_sizes r
        ), '[]'::jsonb),
        'size_diagnostics', coalesce((
            select jsonb_agg(jsonb_build_object(
                'product_size_id', d.product_size_id,
                'size_label', d.size_label,
                'raw_measurement_count', d.raw_measurement_count,
                'policy_measurement_count', d.resolved_count,
                'semantic_conflict_count', d.semantic_conflict_count
            ) order by d.size_label, d.product_size_id)
            from size_diagnostics d
        ), '[]'::jsonb),
        'readiness_version', 'fitmatch-vnext-readiness-v4'
    )
    from product_row p
)
end
$function$;

create or replace function fitmatch_vnext.product_readiness_with_context(
    p_product_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
    select fitmatch_vnext.product_measurement_readiness(
        p_product_id, p_effective_classification
    )
$function$;

create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
    effective_value jsonb;
begin
    select jsonb_build_object(
        'product_id', p.id,
        'classification_status', p.classification_status,
        'comparison_policy_code', gt.comparison_policy_code,
        'garment_type_code', p.garment_type_code,
        'audience_code', p.audience_code,
        'sleeve_length_code', p.sleeve_length_code,
        'lower_length_code', p.lower_length_code,
        'body_length_code', p.body_length_code,
        'effective_source', 'GLOBAL_CONFIRMED'
    )
    into effective_value
    from fitmatch_vnext.products p
    left join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = p.garment_type_code
    where p.id = p_product_id;
    return fitmatch_vnext.product_measurement_readiness(
        p_product_id, coalesce(effective_value, '{}'::jsonb)
    );
end
$function$;

-- Explicit ACLs make the internal helpers non-bypassable while preserving the
-- existing authenticated public comparison RPC path.
alter function fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)
    owner to postgres;
alter function fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)
    owner to postgres;
alter function fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)
    owner to postgres;
alter function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)
    owner to postgres;
alter function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    owner to postgres;
alter function fitmatch_vnext.product_measurement_readiness(uuid,jsonb)
    owner to postgres;
alter function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    owner to postgres;
alter function fitmatch_vnext.product_readiness(uuid)
    owner to postgres;

revoke all on function fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)
    to service_role;
revoke all on function fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)
    to service_role;
revoke all on function fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)
    from public, anon;
grant execute on function fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)
    from public, anon;
grant execute on function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    from public, anon;
grant execute on function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    to authenticated, service_role;
revoke all on function fitmatch_vnext.product_measurement_readiness(uuid,jsonb)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_measurement_readiness(uuid,jsonb)
    to service_role;
revoke all on function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    to service_role;
revoke all on function fitmatch_vnext.product_readiness(uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness(uuid)
    to service_role;

do $postflight$
begin
    if exists (
        select 1
        from fitmatch_vnext.garment_types
        where comparison_measurement_domain_code not in (
            'UPPER_BODY', 'LOWER_BODY', 'FULL_BODY', 'OTHER', 'UNKNOWN'
        )
    ) then
        raise exception 'User-guided comparison postflight: invalid measurement domain';
    end if;
    if position('availability_status is distinct from ''AVAILABLE''' in pg_get_functiondef(
        'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)'::regprocedure
    )) > 0
       or position('NO_AVAILABLE_SIZE' in pg_get_functiondef(
        'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure
    )) > 0 then
        raise exception 'User-guided comparison postflight: availability still gates comparison';
    end if;
    if has_function_privilege(
           'public',
           'fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE'
       )
       or has_function_privilege(
           'anon',
           'fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE'
       )
       or has_function_privilege(
           'authenticated',
           'fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE'
       )
       or not has_function_privilege(
           'service_role',
           'fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE'
       )
       or has_function_privilege(
           'public',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       )
       or has_function_privilege(
           'anon',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       )
       or not has_function_privilege(
           'authenticated',
           'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
           'EXECUTE'
       ) then
        raise exception 'User-guided comparison postflight: function ACL mismatch';
    end if;
    if exists (
        select 1
        from pg_proc p
        where p.oid in (
            'fitmatch_vnext.comparison_decision(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
            'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure,
            'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
            'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)'::regprocedure,
            'fitmatch_vnext.find_reference_candidates(uuid,uuid)'::regprocedure
        )
          and (not p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '')
              not like '%search_path=%')
    ) then
        raise exception 'User-guided comparison postflight: security function search_path mismatch';
    end if;
end
$postflight$;

commit;
