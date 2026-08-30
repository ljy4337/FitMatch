-- fitmatch_vnext P0-4: DB-owned automatic/manual-extended authorization.

alter table fitmatch_vnext.comparison_policies
    add column if not exists allow_manual_extended boolean not null default false,
    add column if not exists sleeve_mismatch_excluded_codes text[] not null default '{}'::text[],
    add column if not exists lower_mismatch_excluded_codes text[] not null default '{}'::text[],
    add column if not exists body_mismatch_excluded_codes text[] not null default '{}'::text[],
    add column if not exists policy_version text not null default 'vnext-policy-v1',
    add column if not exists policy_checksum text;

update fitmatch_vnext.comparison_policies
set allow_manual_extended = is_active and (
        sleeve_mismatch_policy = 'REQUIRE_MATCH'
        or lower_length_mismatch_policy = 'REQUIRE_MATCH'
        or body_length_mismatch_policy = 'REQUIRE_MATCH'
    ),
    sleeve_mismatch_excluded_codes = case when sleeve_mismatch_policy = 'REQUIRE_MATCH'
        then array['sleeve_length']::text[] else '{}'::text[] end,
    lower_mismatch_excluded_codes = case when lower_length_mismatch_policy = 'REQUIRE_MATCH'
        then array['total_length','inseam','outseam','hem_width','hem_circumference']::text[]
        else '{}'::text[] end,
    body_mismatch_excluded_codes = case when body_length_mismatch_policy = 'REQUIRE_MATCH'
        then array['total_length','back_length','front_length']::text[]
        else '{}'::text[] end,
    policy_version = 'vnext-policy-20260829-v1';

update fitmatch_vnext.comparison_policies cp
set policy_checksum = encode(extensions.digest(concat_ws('|', cp.policy_code,
    cp.min_common_measurements::text, cp.required_any_min::text,
    cp.audience_policy_code, cp.sleeve_mismatch_policy,
    cp.lower_length_mismatch_policy, cp.body_length_mismatch_policy,
    cp.allow_manual_extended::text, cp.sleeve_mismatch_excluded_codes::text,
    cp.lower_mismatch_excluded_codes::text, cp.body_mismatch_excluded_codes::text,
    cp.policy_version, cp.is_active::text), 'sha256'), 'hex');

alter table fitmatch_vnext.comparison_policies
    alter column policy_checksum set not null;

-- These garment codes explicitly referenced inactive policies. They remain in
-- taxonomy history but are not supported comparison garments.
create temporary table vnext_unsupported_garments(code text primary key) on commit drop;
insert into vnext_unsupported_garments values
    ('generic_jacket'), ('generic_jumper'), ('generic_underwear'),
    ('homewear_set'), ('other_outerwear'), ('sports_bottom');

insert into fitmatch_vnext.classification_remediation_audit (
    product_id, remediation_version, old_status, old_tuple, evidence_source,
    selected_mapping_id, new_status, new_tuple, resolution_reason
)
select p.id, 'vnext-policy-20260829-v1', p.classification_status,
       jsonb_build_object('product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code, 'garment_type_code', p.garment_type_code,
           'sleeve_length_code', p.sleeve_length_code,
           'lower_length_code', p.lower_length_code,
           'body_length_code', p.body_length_code),
       jsonb_build_object('inactive_policy_code', gt.comparison_policy_code),
       p.classification_mapping_id, 'REVIEW_REQUIRED',
       jsonb_build_object('product_structure_code', p.product_structure_code,
           'audience_code', p.audience_code, 'garment_type_code', null,
           'sleeve_length_code', null, 'lower_length_code', null, 'body_length_code', null),
       'Garment is unsupported because its comparison policy is inactive'
from fitmatch_vnext.products p
join vnext_unsupported_garments u on u.code = p.garment_type_code
join fitmatch_vnext.garment_types gt on gt.garment_type_code = p.garment_type_code
where p.classification_status = 'CONFIRMED'
on conflict (product_id, remediation_version) do nothing;

update fitmatch_vnext.products p
set classification_status = 'REVIEW_REQUIRED', garment_type_code = null,
    sleeve_length_code = null, lower_length_code = null, body_length_code = null,
    classification_source = 'BACKEND', primary_source_signal_id = null,
    classification_mapping_id = null, resolution_mode = 'REVIEW_REQUIRED',
    classification_reason = 'Garment comparison policy is unsupported', classified_at = now()
from vnext_unsupported_garments u
where p.garment_type_code = u.code and p.classification_status = 'CONFIRMED';

update fitmatch_vnext.classification_signal_mappings m
set is_active = false, mapping_version = 'vnext-policy-20260829-v1'
from vnext_unsupported_garments u
where m.garment_type_code = u.code and m.is_active;

update fitmatch_vnext.garment_types gt
set is_active = false
from vnext_unsupported_garments u
where gt.garment_type_code = u.code and gt.is_active;

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
        'authorization_version', 'fitmatch-vnext-authorization-v1'
    );
end
$function$;

revoke all on function fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)
    from public, anon;
grant execute on function fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)
    to authenticated, service_role;

do $verify$
begin
    if exists (
        select 1 from fitmatch_vnext.garment_types gt
        join fitmatch_vnext.comparison_policies cp
          on cp.policy_code = gt.comparison_policy_code
        where gt.is_active and not cp.is_active
    ) then
        raise exception 'Active garment still references inactive comparison policy';
    end if;
end
$verify$;
