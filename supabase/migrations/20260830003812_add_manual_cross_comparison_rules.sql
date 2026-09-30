create table if not exists fitmatch_vnext.manual_cross_comparison_rules (
    policy_code_a text not null,
    policy_code_b text not null,
    reason text not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint manual_cross_comparison_rules_order_chk check (policy_code_a < policy_code_b),
    constraint manual_cross_comparison_rules_pk primary key (policy_code_a, policy_code_b)
);

insert into fitmatch_vnext.manual_cross_comparison_rules(policy_code_a, policy_code_b, reason)
values
    (least('tshirt','polo_shirt'), greatest('tshirt','polo_shirt'), 'User-explicit comparison between T-shirt and polo shirt; automatic reference selection remains disabled'),
    (least('sweatshirt','hoodie'), greatest('sweatshirt','hoodie'), 'User-explicit comparison between sweatshirt and hoodie; automatic reference selection remains disabled'),
    (least('sweatshirt','knit_sweater'), greatest('sweatshirt','knit_sweater'), 'User-explicit comparison between sweatshirt and knit sweater; automatic reference selection remains disabled')
on conflict (policy_code_a, policy_code_b) do update
set reason = excluded.reason,
    is_active = true,
    updated_at = now();

create or replace function fitmatch_vnext.authorize_comparison(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    caller_id uuid := auth.uid();
    ref fitmatch_vnext.closet_items%rowtype;
    target fitmatch_vnext.products%rowtype;
    ref_gt fitmatch_vnext.garment_types%rowtype;
    target_gt fitmatch_vnext.garment_types%rowtype;
    policy fitmatch_vnext.comparison_policies%rowtype;
    target_measurements jsonb;
    excluded text[] := '{}'::text[];
    required_codes text[] := '{}'::text[];
    common_count integer := 0;
    required_any_count integer := 0;
    audience_ok boolean := false;
    structural_ok boolean := false;
    manual_cross_allowed boolean := false;
    sleeve_mismatch boolean := false;
    lower_mismatch boolean := false;
    body_mismatch boolean := false;
    mismatch_block boolean := false;
    decision text;
    reason text;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    select * into ref from fitmatch_vnext.closet_items
    where id = p_reference_closet_item_id and user_id = caller_id and deleted_at is null;
    if not found then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Reference is missing or not owned');
    end if;
    select * into target from fitmatch_vnext.products where id = p_target_product_id;
    if not found or target.classification_status <> 'CONFIRMED' then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Target classification is not CONFIRMED');
    end if;
    if not exists (
        select 1 from fitmatch_vnext.product_sizes ps
        join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
        where ps.id = p_target_product_size_id and pv.product_id = target.id
    ) then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Target size hierarchy mismatch');
    end if;

    select * into ref_gt from fitmatch_vnext.garment_types
    where garment_type_code = ref.garment_type_code and is_active;
    select * into target_gt from fitmatch_vnext.garment_types
    where garment_type_code = target.garment_type_code and is_active;
    if ref_gt.garment_type_code is null or target_gt.garment_type_code is null then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Unsupported garment');
    end if;
    select * into policy from fitmatch_vnext.comparison_policies
    where policy_code = target_gt.comparison_policy_code and is_active;
    if not found then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Comparison policy unavailable');
    end if;

    audience_ok := case policy.audience_policy_code
      when 'IGNORE' then true
      when 'ADULT_ANY' then ref.audience_code in ('MEN','WOMEN','UNISEX')
        and target.audience_code in ('MEN','WOMEN','UNISEX')
      when 'SAME_ONLY' then ref.audience_code = target.audience_code
      else ref.audience_code = target.audience_code
        or ref.audience_code = 'UNISEX' or target.audience_code = 'UNISEX' end;
    if not audience_ok then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Audience is incompatible');
    end if;

    structural_ok := ref_gt.comparison_policy_code = target_gt.comparison_policy_code;
    if not structural_ok and p_manual_explicit then
        select exists (
            select 1
            from fitmatch_vnext.manual_cross_comparison_rules r
            where r.policy_code_a = least(ref_gt.comparison_policy_code, target_gt.comparison_policy_code)
              and r.policy_code_b = greatest(ref_gt.comparison_policy_code, target_gt.comparison_policy_code)
              and r.is_active
        ) into manual_cross_allowed;
        structural_ok := manual_cross_allowed;
    end if;
    if not structural_ok then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Structural comparison policies are incompatible');
    end if;

    sleeve_mismatch := ref.sleeve_length_code is distinct from target.sleeve_length_code;
    lower_mismatch := ref.lower_length_code is distinct from target.lower_length_code;
    body_mismatch := ref.body_length_code is distinct from target.body_length_code;
    mismatch_block :=
        (sleeve_mismatch and policy.sleeve_mismatch_policy = 'REQUIRE_MATCH') or
        (lower_mismatch and policy.lower_length_mismatch_policy = 'REQUIRE_MATCH') or
        (body_mismatch and policy.body_length_mismatch_policy = 'REQUIRE_MATCH');

    if sleeve_mismatch then excluded := excluded || policy.sleeve_mismatch_excluded_codes; end if;
    if lower_mismatch then excluded := excluded || policy.lower_mismatch_excluded_codes; end if;
    if body_mismatch then excluded := excluded || policy.body_mismatch_excluded_codes; end if;
    select coalesce(array_agg(distinct code order by code), '{}'::text[]) into excluded
    from unnest(excluded) code;

    if mismatch_block and not (p_manual_explicit and policy.allow_manual_extended) then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','excluded_measurement_codes',to_jsonb(excluded),
            'minimum_common',policy.min_common_measurements,
            'reason','Required axis mismatch; explicit manual extended selection is required');
    end if;

    target_measurements := fitmatch_vnext.canonical_measurements_for_size(p_target_product_size_id);
    select coalesce(array_agg(cm.fitmatch_measurement_code order by cm.priority,
        cm.fitmatch_measurement_code) filter(where cm.requirement_mode = 'REQUIRED_ANY'),
        '{}'::text[]) into required_codes
    from fitmatch_vnext.comparison_metrics cm
    where cm.comparison_policy_code = policy.policy_code
      and cm.metric_mode = 'CANONICAL' and cm.is_active
      and not (cm.fitmatch_measurement_code = any(excluded));

    with ref_codes as (
      select distinct fitmatch_measurement_code code
      from fitmatch_vnext.closet_item_measurements
      where closet_item_id = ref.id and fitmatch_measurement_code is not null
    ), target_codes as (
      select distinct e ->> 'fitmatch_measurement_code' code
      from jsonb_array_elements(target_measurements -> 'measurements') e
    ), policy_codes as (
      select distinct cm.fitmatch_measurement_code code, cm.requirement_mode
      from fitmatch_vnext.comparison_metrics cm
      where cm.comparison_policy_code = policy.policy_code
        and cm.metric_mode = 'CANONICAL' and cm.is_active
        and not (cm.fitmatch_measurement_code = any(excluded))
    ), common as (
      select pc.* from policy_codes pc join ref_codes r using(code)
      join target_codes t using(code)
    )
    select count(*), count(*) filter(where requirement_mode='REQUIRED_ANY')
    into common_count, required_any_count from common;

    if common_count < policy.min_common_measurements
       or required_any_count < policy.required_any_min then
        decision := 'MEASUREMENTS_REQUIRED'; reason := 'Policy measurement minimum is not met';
    elsif manual_cross_allowed then
        decision := 'MANUAL_EXTENDED'; reason := 'Explicit manual cross-category comparison is allowed';
    elsif mismatch_block then
        decision := 'MANUAL_EXTENDED'; reason := 'Explicit manual extended comparison is allowed';
    else
        decision := 'AUTOMATIC'; reason := 'Automatic comparison policy is satisfied';
    end if;

    return jsonb_build_object(
        'decision', decision,
        'allowed', decision in ('AUTOMATIC','MANUAL_EXTENDED'),
        'mode', case when decision='MANUAL_EXTENDED' then 'MANUAL_EXTENDED'
            when decision='AUTOMATIC' then 'AUTOMATIC' else 'NONE' end,
        'excluded_measurement_codes', to_jsonb(excluded),
        'required_measurement_codes', to_jsonb(required_codes),
        'minimum_common', policy.min_common_measurements,
        'common_measurement_count', common_count,
        'required_any_count', required_any_count,
        'policy_code', policy.policy_code,
        'policy_version', policy.policy_version,
        'policy_checksum', policy.policy_checksum,
        'reason', reason,
        'authorization_version', 'fitmatch-vnext-authorization-v2'
    );
end
$function$;;
