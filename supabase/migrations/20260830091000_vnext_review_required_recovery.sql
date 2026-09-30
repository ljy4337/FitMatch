-- FitMatch vNext REVIEW_REQUIRED recovery contract.
--
-- This migration adds a user-scoped, server-issued classification projection
-- for shopping targets. It never changes global Product authority. Recovery
-- choices come only from active, verified DIRECT descendants of the current
-- PRODUCT_REQUIRED evidence envelope and remain bounded to one through three.

create table if not exists fitmatch_vnext.user_product_classification_overrides (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    product_id uuid not null references fitmatch_vnext.products(id) on delete restrict,
    product_variant_id uuid,
    classification_source text not null default 'USER_EXPLICIT'
        check (classification_source = 'USER_EXPLICIT'),
    audience_code text not null,
    category_code text not null,
    garment_type_code text not null
        references fitmatch_vnext.garment_types(garment_type_code)
        on update cascade on delete restrict,
    comparison_policy_code text not null
        references fitmatch_vnext.comparison_policies(policy_code)
        on update cascade on delete restrict,
    sleeve_length_code text,
    lower_length_code text,
    body_length_code text,
    base_global_status text not null check (base_global_status = 'REVIEW_REQUIRED'),
    base_product_input_fingerprint text not null,
    base_product_evidence_fingerprint text not null,
    base_resolver_version text not null,
    selected_candidate_fingerprint text not null,
    candidate_contract_version text not null,
    candidate_set_hash text not null,
    revision integer not null default 1 check (revision > 0),
    last_mutation_id uuid not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    cleared_at timestamptz,
    constraint user_product_classification_product_scope_chk
        check (product_variant_id is null),
    constraint user_product_classification_user_product_key
        unique (user_id, product_id)
);

create index if not exists user_product_classification_active_user_idx
    on fitmatch_vnext.user_product_classification_overrides (user_id, product_id)
    where cleared_at is null;

create table if not exists fitmatch_vnext.user_classification_feedback_evidence (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    product_id uuid not null references fitmatch_vnext.products(id) on delete restrict,
    override_id uuid not null
        references fitmatch_vnext.user_product_classification_overrides(id)
        on delete restrict,
    override_revision integer not null check (override_revision > 0),
    event_code text not null
        check (event_code in ('SELECTED','EDITED','CLEARED','REAFFIRMED')),
    mutation_id uuid not null,
    global_status_snapshot text not null,
    product_input_fingerprint_snapshot text not null,
    product_evidence_fingerprint_snapshot text not null,
    resolver_version_snapshot text not null,
    fixed_facts_snapshot jsonb not null
        check (jsonb_typeof(fixed_facts_snapshot) = 'object'),
    candidate_set_snapshot jsonb not null
        check (jsonb_typeof(candidate_set_snapshot) = 'array'),
    candidate_set_hash text not null,
    selected_classification_snapshot jsonb
        check (selected_classification_snapshot is null
            or jsonb_typeof(selected_classification_snapshot) = 'object'),
    candidate_contract_version text not null,
    created_at timestamptz not null default now(),
    constraint user_classification_feedback_mutation_key unique (user_id, mutation_id)
);

create index if not exists user_classification_feedback_product_idx
    on fitmatch_vnext.user_classification_feedback_evidence
       (user_id, product_id, created_at desc);

alter table fitmatch_vnext.user_product_classification_overrides enable row level security;
alter table fitmatch_vnext.user_classification_feedback_evidence enable row level security;

drop policy if exists user_product_classification_override_select_own
    on fitmatch_vnext.user_product_classification_overrides;
create policy user_product_classification_override_select_own
    on fitmatch_vnext.user_product_classification_overrides
    for select to authenticated
    using (user_id = auth.uid() and cleared_at is null);

drop policy if exists user_classification_feedback_select_own
    on fitmatch_vnext.user_classification_feedback_evidence;
create policy user_classification_feedback_select_own
    on fitmatch_vnext.user_classification_feedback_evidence
    for select to authenticated
    using (user_id = auth.uid());

revoke all on table fitmatch_vnext.user_product_classification_overrides,
    fitmatch_vnext.user_classification_feedback_evidence
    from public, anon, authenticated;
grant select on table fitmatch_vnext.user_product_classification_overrides,
    fitmatch_vnext.user_classification_feedback_evidence
    to authenticated, service_role;
grant insert, update on table fitmatch_vnext.user_product_classification_overrides
    to service_role;
grant insert on table fitmatch_vnext.user_classification_feedback_evidence
    to service_role;

create or replace function fitmatch_vnext.validate_user_product_classification_override()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    garment_row fitmatch_vnext.garment_types%rowtype;
begin
    select * into garment_row
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code = new.garment_type_code
      and gt.is_active;
    if not found
       or garment_row.category_code is distinct from new.category_code
       or garment_row.comparison_policy_code is distinct from new.comparison_policy_code
       or not exists (
           select 1 from fitmatch_vnext.comparison_policies cp
           where cp.policy_code = new.comparison_policy_code and cp.is_active
       )
       or not coalesce((fitmatch_vnext.classification_tuple_validation(
           new.garment_type_code,
           'SINGLE',
           new.audience_code,
           new.sleeve_length_code,
           new.lower_length_code,
           new.body_length_code
       ) ->> 'valid')::boolean, false) then
        raise exception 'USER_EXPLICIT classification tuple is invalid';
    end if;
    new.updated_at := now();
    return new;
end
$function$;

-- Forward signatures for the mutually dependent recovery/runtime graph. The
-- complete bodies later in this migration replace every declaration before
-- commit; this is the PostgreSQL equivalent of forward declarations.
create or replace function fitmatch_vnext.classification_recovery_options(
    p_product_id uuid
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.effective_target_classification(
    p_product_id uuid
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.set_user_product_classification(
    p_product_id uuid,
    p_selected_candidate_fingerprint text,
    p_expected_candidate_set_hash text,
    p_expected_product_input_fingerprint text,
    p_expected_product_evidence_fingerprint text,
    p_mutation_id uuid,
    p_expected_revision integer default 0
)
returns jsonb language sql security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.clear_user_product_classification(
    p_product_id uuid,
    p_mutation_id uuid,
    p_expected_revision integer
)
returns jsonb language sql security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_product_size_id uuid,
    p_effective_classification jsonb
)
returns jsonb language sql stable set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.product_readiness_with_context(
    p_product_id uuid,
    p_effective_classification jsonb
)
returns jsonb language sql stable set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.effective_product_readiness(
    p_product_id uuid
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.authorize_comparison_with_context(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_product_size_id uuid,
    p_manual_explicit boolean,
    p_effective_classification jsonb
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.get_product_runtime_for_swift(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    runtime_value jsonb;
    effective_value jsonb;
    product_id_value uuid;
    category_value text;
    policy_value text;
    variant_value jsonb;
    size_value jsonb;
    variants_value jsonb := '[]'::jsonb;
    sizes_value jsonb;
begin
    runtime_value := fitmatch_vnext.get_product_runtime(
        p_source_code, p_source_product_key
    );
    if not coalesce((runtime_value ->> 'found')::boolean, false) then
        return runtime_value;
    end if;
    product_id_value := (runtime_value -> 'product' ->> 'id')::uuid;
    effective_value := fitmatch_vnext.effective_target_classification(
        product_id_value
    );

    select gt.category_code, gt.comparison_policy_code
    into category_value, policy_value
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code =
          runtime_value -> 'product' ->> 'garment_type_code'
      and gt.is_active;
    runtime_value := jsonb_set(runtime_value, '{product}',
        runtime_value -> 'product' || jsonb_build_object(
            'category_code', category_value,
            'comparison_policy_code', policy_value
        )
    );

    for variant_value in
        select value from jsonb_array_elements(runtime_value -> 'variants')
    loop
        sizes_value := '[]'::jsonb;
        for size_value in
            select value from jsonb_array_elements(variant_value -> 'sizes')
        loop
            size_value := jsonb_set(
                size_value,
                '{canonical_measurements}',
                fitmatch_vnext.canonical_measurements_for_size_with_context(
                    (size_value ->> 'id')::uuid,
                    effective_value
                )
            );
            sizes_value := sizes_value || jsonb_build_array(size_value);
        end loop;
        variant_value := jsonb_set(variant_value, '{sizes}', sizes_value);
        variants_value := variants_value || jsonb_build_array(variant_value);
    end loop;

    runtime_value := jsonb_set(runtime_value, '{variants}', variants_value);
    runtime_value := jsonb_set(
        runtime_value,
        '{readiness}',
        fitmatch_vnext.effective_product_readiness(product_id_value)
    );
    return runtime_value || jsonb_build_object(
        'effective_classification', effective_value
    );
end
$function$;

revoke all on function fitmatch_vnext.classification_recovery_options(uuid)
    from public, anon;
revoke all on function fitmatch_vnext.effective_target_classification(uuid)
    from public, anon;
revoke all on function fitmatch_vnext.set_user_product_classification(
    uuid,text,text,text,text,uuid,integer
) from public, anon;
revoke all on function fitmatch_vnext.clear_user_product_classification(
    uuid,uuid,integer
) from public, anon;
revoke all on function fitmatch_vnext.canonical_measurements_for_size_with_context(
    uuid,jsonb
) from public, anon, authenticated;
revoke all on function fitmatch_vnext.product_readiness_with_context(uuid,jsonb)
    from public, anon, authenticated;
revoke all on function fitmatch_vnext.effective_product_readiness(uuid)
    from public, anon, authenticated;
revoke all on function fitmatch_vnext.authorize_comparison_with_context(
    uuid,uuid,uuid,boolean,jsonb
) from public, anon, authenticated;
revoke all on function fitmatch_vnext.authorize_comparison(
    uuid,uuid,uuid,boolean
) from public, anon;
revoke all on function fitmatch_vnext.eligible_candidate_sizes(
    uuid,uuid,uuid,boolean
) from public, anon;
revoke all on function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    from public, anon;
revoke all on function fitmatch_vnext.begin_comparison(jsonb)
    from public, anon;
revoke all on function fitmatch_vnext.get_product_runtime_for_swift(text,text)
    from public, anon;

grant execute on function
    fitmatch_vnext.classification_recovery_options(uuid),
    fitmatch_vnext.effective_target_classification(uuid),
    fitmatch_vnext.set_user_product_classification(
        uuid,text,text,text,text,uuid,integer
    ),
    fitmatch_vnext.clear_user_product_classification(uuid,uuid,integer),
    fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean),
    fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean),
    fitmatch_vnext.find_reference_candidates(uuid,uuid),
    fitmatch_vnext.begin_comparison(jsonb),
    fitmatch_vnext.get_product_runtime_for_swift(text,text)
    to authenticated, service_role;
grant execute on function
    fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb),
    fitmatch_vnext.product_readiness_with_context(uuid,jsonb),
    fitmatch_vnext.effective_product_readiness(uuid),
    fitmatch_vnext.authorize_comparison_with_context(
        uuid,uuid,uuid,boolean,jsonb
    ) to service_role;

create or replace function public.fitmatch_vnext_get_classification_recovery_options(
    p_product_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.classification_recovery_options(p_product_id)
$function$;

create or replace function public.fitmatch_vnext_set_user_product_classification(
    p_product_id uuid,
    p_selected_candidate_fingerprint text,
    p_expected_candidate_set_hash text,
    p_expected_product_input_fingerprint text,
    p_expected_product_evidence_fingerprint text,
    p_mutation_id uuid,
    p_expected_revision integer default 0
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.set_user_product_classification(
        p_product_id,
        p_selected_candidate_fingerprint,
        p_expected_candidate_set_hash,
        p_expected_product_input_fingerprint,
        p_expected_product_evidence_fingerprint,
        p_mutation_id,
        p_expected_revision
    )
$function$;

create or replace function public.fitmatch_vnext_clear_user_product_classification(
    p_product_id uuid,
    p_mutation_id uuid,
    p_expected_revision integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.clear_user_product_classification(
        p_product_id, p_mutation_id, p_expected_revision
    )
$function$;

revoke all on function
    public.fitmatch_vnext_get_classification_recovery_options(uuid),
    public.fitmatch_vnext_set_user_product_classification(
        uuid,text,text,text,text,uuid,integer
    ),
    public.fitmatch_vnext_clear_user_product_classification(uuid,uuid,integer)
    from public, anon;
grant execute on function
    public.fitmatch_vnext_get_classification_recovery_options(uuid),
    public.fitmatch_vnext_set_user_product_classification(
        uuid,text,text,text,text,uuid,integer
    ),
    public.fitmatch_vnext_clear_user_product_classification(uuid,uuid,integer)
    to authenticated, service_role;

-- Forward signatures for mutually dependent runtime functions. Complete
-- implementations replace these declarations before the transaction commits.
create or replace function fitmatch_vnext.effective_target_classification(
    p_product_id uuid
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.eligible_candidate_sizes(
    p_reference_closet_item_id uuid,
    p_target_product_id uuid,
    p_target_variant_id uuid,
    p_manual_explicit boolean default false
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

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
    measurement_required_seen boolean;
    candidates_value jsonb := '[]'::jsonb;
    blocked_value jsonb := '[]'::jsonb;
    item_value jsonb;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    select * into target_row from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found then raise exception 'Target product not found'; end if;
    effective_value := fitmatch_vnext.effective_target_classification(
        target_row.id
    );
    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'target_product_id', target_row.id,
            'target_variant_id', p_target_variant_id,
            'effective_classification', effective_value,
            'candidates', '[]'::jsonb,
            'blocked', '[]'::jsonb,
            'status', 'BLOCKED',
            'reason', 'Target effective classification is not CONFIRMED',
            'reference_candidate_version',
                'fitmatch-vnext-reference-candidates-v2'
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
            select pv.id from fitmatch_vnext.product_variants pv
            where pv.product_id = target_row.id
              and (p_target_variant_id is null
                   or pv.id = p_target_variant_id)
            order by pv.sort_order, pv.id
        loop
            automatic_result := fitmatch_vnext.eligible_candidate_sizes(
                closet_row.id, target_row.id, variant_row.id, false
            );
            if coalesce((automatic_result ->> 'allowed')::boolean, false) then
                automatic_ids := automatic_ids || coalesce((
                    select array_agg(value::uuid order by ordinal)
                    from jsonb_array_elements_text(
                        automatic_result ->
                            'authorized_candidate_product_size_ids'
                    ) with ordinality item(value, ordinal)
                ), '{}'::uuid[]);
                if selected_authorization is null then
                    selected_authorization := automatic_result -> 'candidates'
                        -> 0 -> 'authorization';
                end if;
            else
                reason_value := coalesce(reason_value,
                                         automatic_result ->> 'reason');
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
                            manual_result ->
                                'authorized_candidate_product_size_ids'
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
                select ps.id from fitmatch_vnext.product_sizes ps
                join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
                where pv.product_id = target_row.id
                  and (p_target_variant_id is null
                       or pv.id = p_target_variant_id)
                order by pv.sort_order, ps.sort_order, ps.id
            loop
                authorization_result := fitmatch_vnext.authorize_comparison(
                    closet_row.id, target_row.id, size_row.id, false
                );
                if authorization_result ->> 'decision' =
                   'MEASUREMENTS_REQUIRED' then
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
            'mode', case when decision_value in
                ('AUTOMATIC','MANUAL_EXTENDED') then decision_value
                else 'NONE' end,
            'manual_explicit_required',
                decision_value = 'MANUAL_EXTENDED',
            'reason', reason_value,
            'common_measurement_count',
                (selected_authorization ->> 'common_measurement_count')::integer,
            'required_any_count',
                (selected_authorization ->> 'required_any_count')::integer,
            'minimum_common',
                (selected_authorization ->> 'minimum_common')::integer,
            'excluded_measurement_codes', coalesce(
                selected_authorization -> 'excluded_measurement_codes',
                '[]'::jsonb),
            'required_measurement_codes', coalesce(
                selected_authorization -> 'required_measurement_codes',
                '[]'::jsonb),
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
        'effective_classification', effective_value,
        'candidates', candidates_value,
        'blocked', blocked_value,
        'candidate_count', jsonb_array_length(candidates_value),
        'blocked_count', jsonb_array_length(blocked_value),
        'status', case when jsonb_array_length(candidates_value) > 0
            then 'READY' else 'NO_REFERENCE_CANDIDATE' end,
        'reference_candidate_version', case
            when effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED'
                then 'fitmatch-vnext-reference-candidates-v1'
            else 'fitmatch-vnext-reference-candidates-v2' end
    );
end
$function$;

-- PostgreSQL validates SQL-language bodies when they are declared. These
-- transaction-local forward declarations establish the final signatures used
-- by the mutually dependent effective-classification/readiness functions below;
-- each is replaced by its complete implementation later in this same migration.
create or replace function fitmatch_vnext.classification_recovery_options(
    p_product_id uuid
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.effective_target_classification(
    p_product_id uuid
)
returns jsonb language sql stable security definer set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_product_size_id uuid,
    p_effective_classification jsonb
)
returns jsonb language sql stable set search_path = ''
as $function$ select '{}'::jsonb $function$;

create or replace function fitmatch_vnext.product_readiness_with_context(
    p_product_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with context_row as (
    select p.*,
           p_effective_classification ->> 'classification_status'
               effective_status,
           p_effective_classification ->> 'effective_source' effective_source,
           p_effective_classification ->> 'garment_type_code'
               effective_garment_type_code,
           p_effective_classification ->> 'audience_code' effective_audience_code,
           p_effective_classification ->> 'sleeve_length_code'
               effective_sleeve_length_code,
           p_effective_classification ->> 'lower_length_code'
               effective_lower_length_code,
           p_effective_classification ->> 'body_length_code'
               effective_body_length_code,
           p_effective_classification ->> 'comparison_policy_code'
               effective_policy_code
    from fitmatch_vnext.products p
    where p.id = p_product_id
), policy as (
    select cp.*
    from context_row p
    join fitmatch_vnext.comparison_policies cp
      on cp.policy_code = p.effective_policy_code and cp.is_active
), policy_metrics as (
    select cm.fitmatch_measurement_code, cm.requirement_mode
    from policy cp
    join fitmatch_vnext.comparison_metrics cm
      on cm.comparison_policy_code = cp.policy_code
     and cm.metric_mode = 'CANONICAL' and cm.is_active
), latest_availability as (
    select distinct on (o.product_size_id)
           o.product_size_id, o.availability_status, o.observed_at,
           o.valid_until, o.evidence_fingerprint
    from fitmatch_vnext.size_availability_observations o
    join fitmatch_vnext.product_sizes ps on ps.id = o.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where pv.product_id = p_product_id
    order by o.product_size_id, o.observed_at desc, o.id desc
), usable_sizes as (
    select ps.id product_size_id, ps.size_label, la.observed_at,
           la.valid_until, la.evidence_fingerprint
    from latest_availability la
    join fitmatch_vnext.product_sizes ps on ps.id = la.product_size_id
    where la.availability_status = 'AVAILABLE'
      and la.valid_until is not null and la.valid_until >= now()
), size_diagnostics as (
    select u.product_size_id, u.size_label, u.observed_at, u.valid_until,
           u.evidence_fingerprint,
           coalesce((canonical.payload ->> 'raw_measurement_count')::integer, 0)
               raw_measurement_count,
           coalesce((canonical.payload ->> 'semantic_conflict_count')::integer, 0)
               semantic_conflict_count,
           count(distinct pm.fitmatch_measurement_code) resolved_count,
           count(distinct pm.fitmatch_measurement_code) filter (
               where pm.requirement_mode = 'REQUIRED_ANY'
           ) required_any_count
    from usable_sizes u
    cross join lateral (select
        fitmatch_vnext.canonical_measurements_for_size_with_context(
            u.product_size_id, p_effective_classification
        ) payload
    ) canonical
    left join lateral jsonb_array_elements(
        canonical.payload -> 'measurements'
    ) measurement on true
    left join policy_metrics pm
      on pm.fitmatch_measurement_code =
         measurement ->> 'fitmatch_measurement_code'
    group by u.product_size_id, u.size_label, u.observed_at, u.valid_until,
             u.evidence_fingerprint, canonical.payload
), ready_sizes as (
    select sd.* from size_diagnostics sd cross join policy cp
    where sd.semantic_conflict_count = 0
      and sd.resolved_count >= cp.min_common_measurements
      and sd.required_any_count >= cp.required_any_min
)
select case when not exists (select 1 from context_row) then
    jsonb_build_object(
        'status', 'CLASSIFICATION_REQUIRED', 'ready', false,
        'reason', 'Unknown product',
        'readiness_version', 'fitmatch-vnext-readiness-v2'
    )
else (
    select jsonb_build_object(
        'product_id', p.id,
        'ready', p.effective_status = 'CONFIRMED'
            and exists (select 1 from ready_sizes),
        'status', case
            when p.effective_status = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
            when p.effective_status <> 'CONFIRMED' then 'CLASSIFICATION_REQUIRED'
            when not coalesce((fitmatch_vnext.classification_tuple_validation(
                p.effective_garment_type_code, p.product_structure_code,
                p.effective_audience_code, p.effective_sleeve_length_code,
                p.effective_lower_length_code, p.effective_body_length_code
            ) ->> 'valid')::boolean, false) then 'CLASSIFICATION_REQUIRED'
            when not exists (select 1 from policy) then 'POLICY_UNAVAILABLE'
            when not exists (select 1 from usable_sizes) then 'NO_AVAILABLE_SIZE'
            when not exists (select 1 from size_diagnostics
                             where raw_measurement_count > 0)
                then 'NO_MEASUREMENT_DATA'
            when not exists (select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0)
             and exists (select 1 from size_diagnostics
                         where semantic_conflict_count > 0)
                then 'INSUFFICIENT_MEASUREMENTS'
            when not exists (select 1 from size_diagnostics
                             where resolved_count > 0)
                then 'MAPPING_REQUIRED'
            when not exists (select 1 from ready_sizes)
                then 'INSUFFICIENT_MEASUREMENTS'
            else 'READY' end,
        'reason', case
            when p.effective_status = 'NOT_APPLICABLE'
                then 'Product is not a comparable single garment'
            when p.effective_status <> 'CONFIRMED'
                then 'Effective classification is not CONFIRMED'
            when not coalesce((fitmatch_vnext.classification_tuple_validation(
                p.effective_garment_type_code, p.product_structure_code,
                p.effective_audience_code, p.effective_sleeve_length_code,
                p.effective_lower_length_code, p.effective_body_length_code
            ) ->> 'valid')::boolean, false)
                then 'Effective classification tuple is invalid'
            when not exists (select 1 from policy)
                then 'No active comparison policy'
            when not exists (select 1 from usable_sizes)
                then 'No evidence-backed unexpired AVAILABLE size'
            when not exists (select 1 from size_diagnostics
                             where raw_measurement_count > 0)
                then 'Available size has no current raw measurement evidence'
            when not exists (select 1 from size_diagnostics
                where semantic_conflict_count = 0 and resolved_count > 0)
             and exists (select 1 from size_diagnostics
                         where semantic_conflict_count > 0)
                then 'Available size has conflicting canonical semantics'
            when not exists (select 1 from size_diagnostics
                             where resolved_count > 0)
                then 'Current policy metrics cannot be resolved from raw evidence'
            when not exists (select 1 from ready_sizes)
                then 'Current policy minimum measurements are not satisfied'
            else 'Effective classification, availability, policy metrics, and semantics are ready'
            end,
        'comparison_policy_code', p.effective_policy_code,
        'classification_source', p.effective_source,
        'ready_sizes', coalesce((select jsonb_agg(jsonb_build_object(
            'product_size_id', r.product_size_id,
            'size_label', r.size_label,
            'resolved_measurement_count', r.resolved_count,
            'required_any_count', r.required_any_count,
            'semantic_conflict_count', r.semantic_conflict_count,
            'availability_observed_at', r.observed_at,
            'availability_valid_until', r.valid_until,
            'availability_evidence_fingerprint', r.evidence_fingerprint
        ) order by r.size_label, r.product_size_id) from ready_sizes r),
            '[]'::jsonb),
        'size_diagnostics', coalesce((select jsonb_agg(jsonb_build_object(
            'product_size_id', d.product_size_id,
            'size_label', d.size_label,
            'raw_measurement_count', d.raw_measurement_count,
            'policy_measurement_count', d.resolved_count,
            'required_any_count', d.required_any_count,
            'semantic_conflict_count', d.semantic_conflict_count,
            'availability_evidence_fingerprint', d.evidence_fingerprint
        ) order by d.size_label, d.product_size_id) from size_diagnostics d),
            '[]'::jsonb),
        'readiness_version', 'fitmatch-vnext-readiness-v2'
    ) from context_row p
)
end;
$function$;

create or replace function fitmatch_vnext.effective_product_readiness(
    p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    effective_value jsonb;
begin
    effective_value := fitmatch_vnext.effective_target_classification(
        p_product_id
    );
    if effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.product_readiness(p_product_id);
    end if;
    return fitmatch_vnext.product_readiness_with_context(
        p_product_id, effective_value
    );
end
$function$;

create or replace function fitmatch_vnext.authorize_comparison_with_context(
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
    target_measurements jsonb;
    excluded text[] := '{}'::text[];
    required_codes text[] := '{}'::text[];
    common_count integer := 0;
    required_any_count integer := 0;
    audience_ok boolean := false;
    structural_ok boolean := false;
    manual_cross_allowed boolean := false;
    cross_requires_same_sleeve boolean := false;
    manual_pair_a text;
    manual_pair_b text;
    manual_rule_fingerprint text;
    sleeve_mismatch boolean := false;
    lower_mismatch boolean := false;
    body_mismatch boolean := false;
    mismatch_block boolean := false;
    decision text;
    reason text;
    result_value jsonb;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    select * into ref from fitmatch_vnext.closet_items
    where id = p_reference_closet_item_id and user_id = caller_id
      and deleted_at is null;
    if not found then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Reference is missing or not owned');
    end if;
    select * into target from fitmatch_vnext.products
    where id = p_target_product_id;
    if not found
       or p_effective_classification ->> 'product_id' is distinct from
          p_target_product_id::text
       or p_effective_classification ->> 'classification_status' <>
          'CONFIRMED' then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Target effective classification is not CONFIRMED');
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
    where garment_type_code =
          p_effective_classification ->> 'garment_type_code'
      and is_active;
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
        and p_effective_classification ->> 'audience_code'
            in ('MEN','WOMEN','UNISEX')
      when 'SAME_ONLY' then ref.audience_code =
            p_effective_classification ->> 'audience_code'
      else ref.audience_code = p_effective_classification ->> 'audience_code'
        or ref.audience_code = 'UNISEX'
        or p_effective_classification ->> 'audience_code' = 'UNISEX' end;
    if not audience_ok then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Audience is incompatible');
    end if;

    sleeve_mismatch := ref.sleeve_length_code is distinct from
        (p_effective_classification ->> 'sleeve_length_code');
    lower_mismatch := ref.lower_length_code is distinct from
        (p_effective_classification ->> 'lower_length_code');
    body_mismatch := ref.body_length_code is distinct from
        (p_effective_classification ->> 'body_length_code');

    structural_ok := ref_gt.comparison_policy_code =
        target_gt.comparison_policy_code;
    if not structural_ok and p_manual_explicit then
        manual_pair_a := least(ref_gt.comparison_policy_code,
                               target_gt.comparison_policy_code);
        manual_pair_b := greatest(ref_gt.comparison_policy_code,
                                  target_gt.comparison_policy_code);
        select r.is_active, r.require_same_sleeve,
               encode(extensions.digest(concat_ws('|',
                   r.policy_code_a, r.policy_code_b, r.reason,
                   r.is_active::text, r.require_same_sleeve::text,
                   'fitmatch-vnext-manual-cross-rule-v1'
               ), 'sha256'), 'hex')
        into manual_cross_allowed, cross_requires_same_sleeve,
             manual_rule_fingerprint
        from fitmatch_vnext.manual_cross_comparison_rules r
        where r.policy_code_a = manual_pair_a
          and r.policy_code_b = manual_pair_b
          and r.is_active
        limit 1;
        manual_cross_allowed := coalesce(manual_cross_allowed, false)
            and not (coalesce(cross_requires_same_sleeve, false)
                     and sleeve_mismatch);
        structural_ok := manual_cross_allowed;
    end if;
    if not structural_ok then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','reason','Structural comparison policies are incompatible');
    end if;

    mismatch_block :=
        (sleeve_mismatch and policy.sleeve_mismatch_policy = 'REQUIRE_MATCH') or
        (lower_mismatch and policy.lower_length_mismatch_policy = 'REQUIRE_MATCH') or
        (body_mismatch and policy.body_length_mismatch_policy = 'REQUIRE_MATCH');
    if sleeve_mismatch then
        excluded := excluded || policy.sleeve_mismatch_excluded_codes;
    end if;
    if lower_mismatch then
        excluded := excluded || policy.lower_mismatch_excluded_codes;
    end if;
    if body_mismatch then
        excluded := excluded || policy.body_mismatch_excluded_codes;
    end if;
    select coalesce(array_agg(distinct code order by code), '{}'::text[])
    into excluded from unnest(excluded) code;

    if mismatch_block and not (p_manual_explicit and policy.allow_manual_extended) then
        return jsonb_build_object('decision','BLOCKED','allowed',false,
            'mode','NONE','excluded_measurement_codes',to_jsonb(excluded),
            'minimum_common',policy.min_common_measurements,
            'reason','Required axis mismatch; explicit manual extended selection is required');
    end if;

    target_measurements :=
        fitmatch_vnext.canonical_measurements_for_size_with_context(
            p_target_product_size_id, p_effective_classification
        );
    select coalesce(array_agg(cm.fitmatch_measurement_code order by cm.priority,
        cm.fitmatch_measurement_code) filter(
            where cm.requirement_mode = 'REQUIRED_ANY'
        ), '{}'::text[])
    into required_codes
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
        decision := 'MEASUREMENTS_REQUIRED';
        reason := 'Policy measurement minimum is not met';
    elsif manual_cross_allowed then
        decision := 'MANUAL_EXTENDED';
        reason := 'Explicit manual cross-category comparison is allowed';
    elsif mismatch_block then
        decision := 'MANUAL_EXTENDED';
        reason := 'Explicit manual extended comparison is allowed';
    else
        decision := 'AUTOMATIC';
        reason := 'Automatic comparison policy is satisfied';
    end if;

    result_value := jsonb_build_object(
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
        'authorization_version', 'fitmatch-vnext-authorization-v3'
    );
    if manual_cross_allowed then
        result_value := result_value || jsonb_build_object(
            'manual_cross_rule', jsonb_build_object(
                'policy_code_a', manual_pair_a,
                'policy_code_b', manual_pair_b,
                'require_same_sleeve', cross_requires_same_sleeve,
                'rule_fingerprint', manual_rule_fingerprint
            )
        );
    end if;
    if p_effective_classification ->> 'effective_source' = 'USER_EXPLICIT' then
        result_value := result_value || jsonb_build_object(
            'classification_source', 'USER_EXPLICIT',
            'effective_authority_fingerprint',
                p_effective_classification ->> 'effective_authority_fingerprint',
            'override_revision',
                (p_effective_classification ->> 'override_revision')::integer
        );
    end if;
    return result_value;
end
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
    return fitmatch_vnext.authorize_comparison_with_context(
        p_reference_closet_item_id,
        p_target_product_id,
        p_target_product_size_id,
        p_manual_explicit,
        effective_value
    );
end
$function$;


create or replace function fitmatch_vnext.effective_target_classification(
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
    override_row fitmatch_vnext.user_product_classification_overrides%rowtype;
    recovery_value jsonb;
    selected_candidate jsonb;
    state_value text;
    status_value text;
    source_value text;
    category_value text;
    policy_value text;
    garment_value text;
    sleeve_value text;
    lower_value text;
    body_value text;
    override_valid boolean := false;
    tuple_matches boolean := false;
    authority_fingerprint_value text;
    personal_snapshot jsonb;
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p where p.id = p_product_id;
    if not found then
        raise exception 'Product not found';
    end if;

    if caller_id is not null then
        select * into override_row
        from fitmatch_vnext.user_product_classification_overrides o
        where o.user_id = caller_id
          and o.product_id = product_row.id
          and o.cleared_at is null;
    end if;

    if override_row.id is not null then
        personal_snapshot := jsonb_build_object(
            'override_id', override_row.id,
            'revision', override_row.revision,
            'classification_source', override_row.classification_source,
            'category_code', override_row.category_code,
            'garment_type_code', override_row.garment_type_code,
            'audience_code', override_row.audience_code,
            'sleeve_length_code', override_row.sleeve_length_code,
            'lower_length_code', override_row.lower_length_code,
            'body_length_code', override_row.body_length_code,
            'comparison_policy_code', override_row.comparison_policy_code,
            'selected_candidate_fingerprint',
                override_row.selected_candidate_fingerprint,
            'candidate_contract_version', override_row.candidate_contract_version,
            'candidate_set_hash', override_row.candidate_set_hash,
            'base_product_input_fingerprint',
                override_row.base_product_input_fingerprint,
            'base_product_evidence_fingerprint',
                override_row.base_product_evidence_fingerprint,
            'base_resolver_version', override_row.base_resolver_version,
            'cleared_at', override_row.cleared_at,
            'created_at', override_row.created_at,
            'updated_at', override_row.updated_at
        );
    end if;

    if product_row.classification_status = 'CONFIRMED' then
        select gt.category_code, gt.comparison_policy_code
        into category_value, policy_value
        from fitmatch_vnext.garment_types gt
        where gt.garment_type_code = product_row.garment_type_code
          and gt.is_active;
        status_value := 'CONFIRMED';
        source_value := 'GLOBAL_CONFIRMED';
        garment_value := product_row.garment_type_code;
        sleeve_value := product_row.sleeve_length_code;
        lower_value := product_row.lower_length_code;
        body_value := product_row.body_length_code;
        if override_row.id is null then
            state_value := 'GLOBAL_CONFIRMED';
        else
            tuple_matches := override_row.audience_code = product_row.audience_code
                and override_row.garment_type_code = product_row.garment_type_code
                and override_row.sleeve_length_code is not distinct from
                    product_row.sleeve_length_code
                and override_row.lower_length_code is not distinct from
                    product_row.lower_length_code
                and override_row.body_length_code is not distinct from
                    product_row.body_length_code;
            state_value := case when tuple_matches
                then 'SUPERSEDED_MATCH' else 'SUPERSEDED_CONFLICT' end;
        end if;
    elsif product_row.classification_status = 'NOT_APPLICABLE' then
        state_value := 'GLOBAL_NOT_APPLICABLE';
        status_value := 'NOT_APPLICABLE';
        source_value := 'GLOBAL_NOT_APPLICABLE';
    elsif override_row.id is null or override_row.cleared_at is not null then
        state_value := 'REVIEW_REQUIRED';
        status_value := 'REVIEW_REQUIRED';
        source_value := 'NONE';
    else
        recovery_value := fitmatch_vnext.classification_recovery_options(
            product_row.id
        );
        select candidate into selected_candidate
        from jsonb_array_elements(recovery_value -> 'candidates') candidate
        where candidate ->> 'candidate_fingerprint' =
              override_row.selected_candidate_fingerprint
        limit 1;
        override_valid := recovery_value ->> 'recoverability' = 'RECOVERABLE'
            and recovery_value ->> 'candidate_set_hash' =
                override_row.candidate_set_hash
            and recovery_value ->> 'candidate_contract_version' =
                override_row.candidate_contract_version
            and product_row.input_fingerprint =
                override_row.base_product_input_fingerprint
            and product_row.evidence_fingerprint =
                override_row.base_product_evidence_fingerprint
            and product_row.resolver_version = override_row.base_resolver_version
            and selected_candidate is not null
            and selected_candidate ->> 'garment_type_code' =
                override_row.garment_type_code
            and selected_candidate ->> 'category_code' = override_row.category_code
            and selected_candidate ->> 'comparison_policy_code' =
                override_row.comparison_policy_code
            and (selected_candidate ->> 'sleeve_length_code') is not distinct from
                override_row.sleeve_length_code
            and (selected_candidate ->> 'lower_length_code') is not distinct from
                override_row.lower_length_code
            and (selected_candidate ->> 'body_length_code') is not distinct from
                override_row.body_length_code
            and coalesce((fitmatch_vnext.classification_tuple_validation(
                override_row.garment_type_code,
                product_row.product_structure_code,
                override_row.audience_code,
                override_row.sleeve_length_code,
                override_row.lower_length_code,
                override_row.body_length_code
            ) ->> 'valid')::boolean, false);

        if override_valid then
            state_value := 'PERSONAL_CONFIRMED';
            status_value := 'CONFIRMED';
            source_value := 'USER_EXPLICIT';
            category_value := override_row.category_code;
            policy_value := override_row.comparison_policy_code;
            garment_value := override_row.garment_type_code;
            sleeve_value := override_row.sleeve_length_code;
            lower_value := override_row.lower_length_code;
            body_value := override_row.body_length_code;
        else
            state_value := 'STALE_RECONFIRM_REQUIRED';
            status_value := 'REVIEW_REQUIRED';
            source_value := 'NONE';
        end if;
    end if;

    authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
        product_row.id::text,
        state_value,
        status_value,
        source_value,
        product_row.input_fingerprint,
        product_row.evidence_fingerprint,
        product_row.resolver_version,
        coalesce(override_row.id::text, '∅'),
        coalesce(override_row.revision::text, '∅'),
        coalesce(garment_value, '∅'),
        coalesce(sleeve_value, '∅'),
        coalesce(lower_value, '∅'),
        coalesce(body_value, '∅'),
        'fitmatch-vnext-effective-target-v1'
    ), 'sha256'), 'hex');

    return jsonb_strip_nulls(jsonb_build_object(
        'product_id', product_row.id,
        'state', state_value,
        'classification_status', status_value,
        'effective_source', source_value,
        'category_code', category_value,
        'garment_type_code', garment_value,
        'audience_code', product_row.audience_code,
        'sleeve_length_code', sleeve_value,
        'lower_length_code', lower_value,
        'body_length_code', body_value,
        'comparison_policy_code', policy_value,
        'product_structure_code', product_row.product_structure_code,
        'global_classification', jsonb_build_object(
            'status', product_row.classification_status,
            'garment_type_code', product_row.garment_type_code,
            'audience_code', product_row.audience_code,
            'sleeve_length_code', product_row.sleeve_length_code,
            'lower_length_code', product_row.lower_length_code,
            'body_length_code', product_row.body_length_code,
            'input_fingerprint', product_row.input_fingerprint,
            'evidence_fingerprint', product_row.evidence_fingerprint,
            'resolver_version', product_row.resolver_version
        ),
        'personal_projection', personal_snapshot,
        'override_revision', override_row.revision,
        'effective_authority_fingerprint', authority_fingerprint_value,
        'effective_contract_version', 'fitmatch-vnext-effective-target-v1'
    ));
end
$function$;

create or replace function fitmatch_vnext.set_user_product_classification(
    p_product_id uuid,
    p_selected_candidate_fingerprint text,
    p_expected_candidate_set_hash text,
    p_expected_product_input_fingerprint text,
    p_expected_product_evidence_fingerprint text,
    p_mutation_id uuid,
    p_expected_revision integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
    current_row fitmatch_vnext.user_product_classification_overrides%rowtype;
    saved_row fitmatch_vnext.user_product_classification_overrides%rowtype;
    recovery_value jsonb;
    selected_candidate jsonb;
    event_value text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_mutation_id is null then
        raise exception 'mutation_id is required';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
        caller_id::text || ':' || p_product_id::text, 0
    ));

    select * into product_row
    from fitmatch_vnext.products p where p.id = p_product_id
    for share;
    if not found then
        raise exception 'Product not found';
    end if;
    if product_row.classification_status <> 'REVIEW_REQUIRED' then
        raise exception 'Global classification no longer permits USER_EXPLICIT';
    end if;
    if product_row.input_fingerprint is distinct from
       p_expected_product_input_fingerprint then
        raise exception 'Stale product input fingerprint';
    end if;
    if product_row.evidence_fingerprint is distinct from
       p_expected_product_evidence_fingerprint then
        raise exception 'Stale product evidence fingerprint';
    end if;

    recovery_value := fitmatch_vnext.classification_recovery_options(p_product_id);
    if recovery_value ->> 'recoverability' <> 'RECOVERABLE' then
        raise exception 'Product does not have a safe recovery contract';
    end if;
    if recovery_value ->> 'candidate_set_hash' is distinct from
       p_expected_candidate_set_hash then
        raise exception 'Stale candidate set hash';
    end if;
    select candidate into selected_candidate
    from jsonb_array_elements(recovery_value -> 'candidates') candidate
    where candidate ->> 'candidate_fingerprint' =
          p_selected_candidate_fingerprint
    limit 1;
    if selected_candidate is null then
        raise exception 'Selected candidate is not server-authorized';
    end if;

    select * into current_row
    from fitmatch_vnext.user_product_classification_overrides o
    where o.user_id = caller_id and o.product_id = p_product_id
    for update;
    if found and current_row.last_mutation_id = p_mutation_id then
        return jsonb_build_object(
            'saved', true,
            'idempotent', true,
            'override', to_jsonb(current_row),
            'effective_classification',
                fitmatch_vnext.effective_target_classification(p_product_id)
        );
    end if;
    if coalesce(current_row.revision, 0) <> p_expected_revision then
        raise exception 'Stale override revision';
    end if;

    event_value := case
        when current_row.id is null or current_row.cleared_at is not null
            then 'SELECTED'
        when current_row.selected_candidate_fingerprint =
             p_selected_candidate_fingerprint then 'REAFFIRMED'
        else 'EDITED' end;

    insert into fitmatch_vnext.user_product_classification_overrides (
        user_id, product_id, product_variant_id, classification_source,
        audience_code, category_code, garment_type_code,
        comparison_policy_code, sleeve_length_code, lower_length_code,
        body_length_code, base_global_status,
        base_product_input_fingerprint, base_product_evidence_fingerprint,
        base_resolver_version, selected_candidate_fingerprint,
        candidate_contract_version, candidate_set_hash, revision,
        last_mutation_id, created_at, updated_at, cleared_at
    ) values (
        caller_id, product_row.id, null, 'USER_EXPLICIT',
        product_row.audience_code,
        selected_candidate ->> 'category_code',
        selected_candidate ->> 'garment_type_code',
        selected_candidate ->> 'comparison_policy_code',
        selected_candidate ->> 'sleeve_length_code',
        selected_candidate ->> 'lower_length_code',
        selected_candidate ->> 'body_length_code',
        product_row.classification_status,
        product_row.input_fingerprint,
        product_row.evidence_fingerprint,
        product_row.resolver_version,
        p_selected_candidate_fingerprint,
        recovery_value ->> 'candidate_contract_version',
        p_expected_candidate_set_hash,
        coalesce(current_row.revision, 0) + 1,
        p_mutation_id,
        coalesce(current_row.created_at, now()), now(), null
    )
    on conflict (user_id, product_id) do update
    set product_variant_id = null,
        classification_source = 'USER_EXPLICIT',
        audience_code = excluded.audience_code,
        category_code = excluded.category_code,
        garment_type_code = excluded.garment_type_code,
        comparison_policy_code = excluded.comparison_policy_code,
        sleeve_length_code = excluded.sleeve_length_code,
        lower_length_code = excluded.lower_length_code,
        body_length_code = excluded.body_length_code,
        base_global_status = excluded.base_global_status,
        base_product_input_fingerprint = excluded.base_product_input_fingerprint,
        base_product_evidence_fingerprint =
            excluded.base_product_evidence_fingerprint,
        base_resolver_version = excluded.base_resolver_version,
        selected_candidate_fingerprint = excluded.selected_candidate_fingerprint,
        candidate_contract_version = excluded.candidate_contract_version,
        candidate_set_hash = excluded.candidate_set_hash,
        revision = excluded.revision,
        last_mutation_id = excluded.last_mutation_id,
        updated_at = now(),
        cleared_at = null
    returning * into saved_row;

    insert into fitmatch_vnext.user_classification_feedback_evidence (
        user_id, product_id, override_id, override_revision, event_code,
        mutation_id, global_status_snapshot,
        product_input_fingerprint_snapshot,
        product_evidence_fingerprint_snapshot, resolver_version_snapshot,
        fixed_facts_snapshot, candidate_set_snapshot, candidate_set_hash,
        selected_classification_snapshot, candidate_contract_version
    ) values (
        caller_id, product_row.id, saved_row.id, saved_row.revision, event_value,
        p_mutation_id, product_row.classification_status,
        product_row.input_fingerprint, product_row.evidence_fingerprint,
        product_row.resolver_version,
        recovery_value -> 'fixed_facts', recovery_value -> 'candidates',
        p_expected_candidate_set_hash, selected_candidate,
        recovery_value ->> 'candidate_contract_version'
    );

    return jsonb_build_object(
        'saved', true,
        'idempotent', false,
        'event', event_value,
        'override', to_jsonb(saved_row),
        'effective_classification',
            fitmatch_vnext.effective_target_classification(p_product_id)
    );
end
$function$;

create or replace function fitmatch_vnext.clear_user_product_classification(
    p_product_id uuid,
    p_mutation_id uuid,
    p_expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
    current_row fitmatch_vnext.user_product_classification_overrides%rowtype;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    if p_mutation_id is null then
        raise exception 'mutation_id is required';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
        caller_id::text || ':' || p_product_id::text, 0
    ));
    select * into product_row
    from fitmatch_vnext.products p where p.id = p_product_id;
    if not found then
        raise exception 'Product not found';
    end if;
    select * into current_row
    from fitmatch_vnext.user_product_classification_overrides o
    where o.user_id = caller_id and o.product_id = p_product_id
    for update;
    if not found then
        raise exception 'Personal classification does not exist';
    end if;
    if current_row.last_mutation_id = p_mutation_id then
        return jsonb_build_object(
            'cleared', current_row.cleared_at is not null,
            'idempotent', true,
            'effective_classification',
                fitmatch_vnext.effective_target_classification(p_product_id)
        );
    end if;
    if current_row.cleared_at is not null then
        raise exception 'Personal classification is already cleared';
    end if;
    if current_row.revision <> p_expected_revision then
        raise exception 'Stale override revision';
    end if;

    update fitmatch_vnext.user_product_classification_overrides o
    set revision = o.revision + 1,
        last_mutation_id = p_mutation_id,
        cleared_at = now(),
        updated_at = now()
    where o.id = current_row.id
    returning * into current_row;

    insert into fitmatch_vnext.user_classification_feedback_evidence (
        user_id, product_id, override_id, override_revision, event_code,
        mutation_id, global_status_snapshot,
        product_input_fingerprint_snapshot,
        product_evidence_fingerprint_snapshot, resolver_version_snapshot,
        fixed_facts_snapshot, candidate_set_snapshot, candidate_set_hash,
        selected_classification_snapshot, candidate_contract_version
    ) values (
        caller_id, product_row.id, current_row.id, current_row.revision, 'CLEARED',
        p_mutation_id, product_row.classification_status,
        product_row.input_fingerprint, product_row.evidence_fingerprint,
        product_row.resolver_version, '{}'::jsonb, '[]'::jsonb,
        current_row.candidate_set_hash,
        jsonb_build_object(
            'category_code', current_row.category_code,
            'garment_type_code', current_row.garment_type_code,
            'sleeve_length_code', current_row.sleeve_length_code,
            'lower_length_code', current_row.lower_length_code,
            'body_length_code', current_row.body_length_code,
            'comparison_policy_code', current_row.comparison_policy_code
        ),
        current_row.candidate_contract_version
    );

    return jsonb_build_object(
        'cleared', true,
        'idempotent', false,
        'override_id', current_row.id,
        'revision', current_row.revision,
        'effective_classification',
            fitmatch_vnext.effective_target_classification(p_product_id)
    );
end
$function$;

create or replace function fitmatch_vnext.canonical_measurements_for_size_with_context(
    p_product_size_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
    actual_product_id uuid;
begin
    select pv.product_id into actual_product_id
    from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    where ps.id = p_product_size_id;
    if actual_product_id is null then
        raise exception 'Product size not found';
    end if;
    if actual_product_id is distinct from
       (p_effective_classification ->> 'product_id')::uuid then
        raise exception 'Measurement context product mismatch';
    end if;
    if p_effective_classification ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        return fitmatch_vnext.canonical_measurements_for_size(p_product_size_id);
    end if;
    if p_effective_classification ->> 'effective_source' <> 'USER_EXPLICIT' then
        return jsonb_build_object(
            'product_size_id', p_product_size_id,
            'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
            'measurements', '[]'::jsonb,
            'raw_measurement_count', 0,
            'unresolved_count', 0,
            'semantic_conflict_count', 0,
            'classification_context_source',
                p_effective_classification ->> 'effective_source'
        );
    end if;

    return (
        with raw_rows as (
            select m.*, p.source_code,
                   p_effective_classification ->> 'garment_type_code'
                       garment_type_code,
                   p_effective_classification ->> 'category_code' category_code
            from fitmatch_vnext.product_size_measurements m
            join fitmatch_vnext.product_sizes ps on ps.id = m.product_size_id
            join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
            join fitmatch_vnext.products p on p.id = pv.product_id
            where m.product_size_id = p_product_size_id and m.is_current
        ), decisions as (
            select r.*, fitmatch_vnext.resolve_measurement(
                r.source_code, r.parser_code, r.raw_code, r.raw_label,
                r.garment_type_code, r.category_code, r.raw_value
            ) decision
            from raw_rows r
        ), resolved as (
            select *, decision ->> 'fitmatch_measurement_code' canonical_code,
                   (decision ->> 'canonical_value')::numeric canonical_value
            from decisions
            where decision ->> 'resolution_status' = 'RESOLVED'
        ), conflicts as (
            select canonical_code from resolved group by canonical_code
            having count(distinct canonical_value) > 1
        )
        select jsonb_build_object(
            'product_size_id', p_product_size_id,
            'resolver_version', 'fitmatch-vnext-measurement-resolver-v1',
            'measurements', coalesce((select jsonb_agg(jsonb_build_object(
                'product_size_measurement_id', r.id,
                'fitmatch_measurement_code', r.canonical_code,
                'value', r.canonical_value,
                'unit_code', r.decision ->> 'canonical_unit_code',
                'basis_code', r.decision ->> 'canonical_basis_code',
                'source_measurement_code', r.decision ->> 'source_measurement_code',
                'resolution_path', r.decision ->> 'resolution_path',
                'raw_evidence_fingerprint', r.evidence_fingerprint
            ) order by r.canonical_code, r.id)
            from resolved r
            where not exists (select 1 from conflicts c
                              where c.canonical_code = r.canonical_code)),
                '[]'::jsonb),
            'raw_measurement_count', (select count(*) from raw_rows),
            'unresolved_count', (select count(*) from decisions
                where decision ->> 'resolution_status' <> 'RESOLVED'),
            'semantic_conflict_count', (select count(*) from conflicts),
            'classification_context_source', 'USER_EXPLICIT'
        )
    );
end
$function$;


drop trigger if exists user_product_classification_override_validate
    on fitmatch_vnext.user_product_classification_overrides;
create trigger user_product_classification_override_validate
before insert or update on fitmatch_vnext.user_product_classification_overrides
for each row execute function
    fitmatch_vnext.validate_user_product_classification_override();

create or replace function fitmatch_vnext.protect_user_classification_feedback_evidence()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    raise exception 'User classification feedback evidence is append-only';
end
$function$;

drop trigger if exists user_classification_feedback_append_only
    on fitmatch_vnext.user_classification_feedback_evidence;
create trigger user_classification_feedback_append_only
before update or delete on fitmatch_vnext.user_classification_feedback_evidence
for each row execute function
    fitmatch_vnext.protect_user_classification_feedback_evidence();

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
    candidate_count_value integer := 0;
    category_count_value integer := 0;
    candidates_value jsonb := '[]'::jsonb;
    fixed_facts_value jsonb := '{}'::jsonb;
    unknown_fields_value jsonb := '[]'::jsonb;
    candidate_set_hash_value text;
    recoverability_value text := 'UNRECOVERABLE';
    unrecoverable_reason_value text;
    contract_version_value constant text :=
        'fitmatch-vnext-recovery-candidates-v1';
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Authentication required';
    end if;

    select * into product_row
    from fitmatch_vnext.products p
    where p.id = p_product_id;
    if not found then
        raise exception 'Product not found';
    end if;

    current_decision := fitmatch_vnext.classification_decision(
        product_row.source_code,
        product_row.source_product_key
    );

    if product_row.classification_status <> 'REVIEW_REQUIRED' then
        unrecoverable_reason_value := 'GLOBAL_STATUS_NOT_REVIEW_REQUIRED';
    elsif product_row.product_structure_code <> 'SINGLE' then
        unrecoverable_reason_value := 'PRODUCT_STRUCTURE_NOT_SINGLE';
    elsif current_decision ->> 'reason' <>
          'Product-exact verified evidence is required' then
        unrecoverable_reason_value := 'REVIEW_REASON_NOT_PRODUCT_REQUIRED';
    else
        with recursive evidence as (
            select pcs.source_signal_id,
                   case ss.signal_kind
                     when 'PRODUCT_EXACT' then 600
                     when 'PRODUCT_STRUCTURE' then 500
                     when 'PRODUCT_TYPE' then 400
                     when 'SUBFAMILY' then 300
                     when 'FAMILY' then 250
                     when 'CATEGORY' then 200
                     when 'SECTION' then 150
                     else 100
                   end evidence_rank,
                   m.priority,
                   m.resolution_mode
            from fitmatch_vnext.product_classification_signals pcs
            join fitmatch_vnext.source_classification_signals ss
              on ss.id = pcs.source_signal_id
             and ss.source_code = product_row.source_code
             and ss.is_active
            join fitmatch_vnext.classification_signal_mappings m
              on m.source_signal_id = ss.id
             and m.is_active and m.is_verified
             and (m.audience_code = 'ANY'
                  or m.audience_code = product_row.audience_code)
            where pcs.product_id = product_row.id
        ), top_rank as (
            select * from evidence
            where evidence_rank = (select max(evidence_rank) from evidence)
        ), envelopes as (
            select source_signal_id
            from top_rank
            where priority = (select max(priority) from top_rank)
              and resolution_mode = 'PRODUCT_REQUIRED'
        ), descendants as (
            select s.id, s.parent_signal_id, 1 depth
            from fitmatch_vnext.source_classification_signals s
            join envelopes e on e.source_signal_id = s.parent_signal_id
            where s.source_code = product_row.source_code and s.is_active
            union all
            select s.id, s.parent_signal_id, d.depth + 1
            from fitmatch_vnext.source_classification_signals s
            join descendants d on d.id = s.parent_signal_id
            where s.source_code = product_row.source_code
              and s.is_active and d.depth < 16
        ), verified_candidates as (
            select distinct on (
                m.garment_type_code,
                coalesce(m.sleeve_length_code, '∅'),
                coalesce(m.lower_length_code, '∅'),
                coalesce(m.body_length_code, '∅')
            )
                m.id mapping_id,
                m.mapping_checksum,
                m.garment_type_code,
                m.sleeve_length_code,
                m.lower_length_code,
                m.body_length_code,
                gt.category_code,
                gt.comparison_policy_code,
                gt.display_name,
                gt.sort_order
            from descendants d
            join fitmatch_vnext.classification_signal_mappings m
              on m.source_signal_id = d.id
             and m.is_active and m.is_verified
             and m.resolution_mode = 'DIRECT'
             and (m.audience_code = 'ANY'
                  or m.audience_code = product_row.audience_code)
            join fitmatch_vnext.garment_types gt
              on gt.garment_type_code = m.garment_type_code
             and gt.is_active
            join fitmatch_vnext.comparison_policies cp
              on cp.policy_code = gt.comparison_policy_code
             and cp.is_active
            where coalesce((fitmatch_vnext.classification_tuple_validation(
                m.garment_type_code,
                product_row.product_structure_code,
                product_row.audience_code,
                m.sleeve_length_code,
                m.lower_length_code,
                m.body_length_code
            ) ->> 'valid')::boolean, false)
            order by m.garment_type_code,
                coalesce(m.sleeve_length_code, '∅'),
                coalesce(m.lower_length_code, '∅'),
                coalesce(m.body_length_code, '∅'),
                m.priority desc, m.id
        ), fingerprinted as (
            select v.*,
                encode(extensions.digest(concat_ws('|',
                    product_row.id::text,
                    product_row.input_fingerprint,
                    product_row.evidence_fingerprint,
                    product_row.resolver_version,
                    v.mapping_id::text,
                    v.mapping_checksum,
                    v.category_code,
                    v.garment_type_code,
                    coalesce(v.sleeve_length_code, '∅'),
                    coalesce(v.lower_length_code, '∅'),
                    coalesce(v.body_length_code, '∅'),
                    v.comparison_policy_code,
                    contract_version_value
                ), 'sha256'), 'hex') candidate_fingerprint
            from verified_candidates v
        ), aggregate_value as (
            select count(*)::integer candidate_count,
                   count(distinct category_code)::integer category_count,
                   count(distinct garment_type_code)::integer garment_count,
                   count(distinct coalesce(sleeve_length_code, '∅'))::integer
                       sleeve_count,
                   count(distinct coalesce(lower_length_code, '∅'))::integer
                       lower_count,
                   count(distinct coalesce(body_length_code, '∅'))::integer
                       body_count,
                   count(distinct comparison_policy_code)::integer policy_count,
                   min(category_code) category_code,
                   min(garment_type_code) garment_type_code,
                   min(sleeve_length_code) sleeve_length_code,
                   min(lower_length_code) lower_length_code,
                   min(body_length_code) body_length_code,
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
                       coalesce(body_length_code, '∅')),
                       '[]'::jsonb) candidates,
                   encode(extensions.digest(coalesce(string_agg(
                       candidate_fingerprint, E'\n' order by candidate_fingerprint
                   ), ''), 'sha256'), 'hex') candidate_set_hash
            from fingerprinted
        )
        select candidate_count, category_count, candidates, candidate_set_hash,
               jsonb_strip_nulls(jsonb_build_object(
                   'audience_code', product_row.audience_code,
                   'product_structure_code', product_row.product_structure_code,
                   'category_code', case when category_count = 1
                       then category_code end,
                   'garment_type_code', case when garment_count = 1
                       then garment_type_code end,
                   'sleeve_length_code', case when sleeve_count = 1
                       then sleeve_length_code end,
                   'lower_length_code', case when lower_count = 1
                       then lower_length_code end,
                   'body_length_code', case when body_count = 1
                       then body_length_code end,
                   'comparison_policy_code', case when policy_count = 1
                       then comparison_policy_code end
               )),
               (select coalesce(jsonb_agg(field_name order by field_order), '[]'::jsonb)
                from (values
                    ('garment_type', 1, garment_count > 1),
                    ('sleeve_length', 2, sleeve_count > 1),
                    ('lower_length', 3, lower_count > 1),
                    ('body_length', 4, body_count > 1)
                ) fields(field_name, field_order, is_unknown)
                where is_unknown)
        into candidate_count_value, category_count_value, candidates_value,
             candidate_set_hash_value, fixed_facts_value, unknown_fields_value
        from aggregate_value;

        if candidate_count_value = 0 then
            unrecoverable_reason_value := 'NO_VERIFIED_DESCENDANT_DIRECT_CANDIDATE';
        elsif candidate_count_value > 3 then
            unrecoverable_reason_value := 'CANDIDATE_SET_NOT_BOUNDED';
        elsif category_count_value <> 1 then
            unrecoverable_reason_value := 'CANDIDATES_CROSS_CATEGORIES';
        else
            recoverability_value := 'RECOVERABLE';
            unrecoverable_reason_value := null;
        end if;
    end if;

    if recoverability_value <> 'RECOVERABLE' then
        candidates_value := '[]'::jsonb;
        candidate_set_hash_value := null;
        fixed_facts_value := jsonb_strip_nulls(jsonb_build_object(
            'audience_code', product_row.audience_code,
            'product_structure_code', product_row.product_structure_code
        ));
        unknown_fields_value := '[]'::jsonb;
    end if;

    return jsonb_build_object(
        'product_id', product_row.id,
        'global_status', product_row.classification_status,
        'recoverability', recoverability_value,
        'unrecoverable_reason', unrecoverable_reason_value,
        'fixed_facts', fixed_facts_value,
        'unknown_fields', unknown_fields_value,
        'candidates', candidates_value,
        'candidate_count', jsonb_array_length(candidates_value),
        'product_input_fingerprint', product_row.input_fingerprint,
        'product_evidence_fingerprint', product_row.evidence_fingerprint,
        'resolver_version', product_row.resolver_version,
        'candidate_contract_version', contract_version_value,
        'candidate_set_hash', candidate_set_hash_value,
        'current_review_reason', current_decision ->> 'reason'
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
    candidate_value jsonb;
    available_count_value integer := 0;
    expired_count_value integer := 0;
    semantic_conflict_count_value integer := 0;
    authorization_rejected_count_value integer := 0;
    authority_fingerprint_value text;
    authority_version_value text;
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;
    select * into reference_row
    from fitmatch_vnext.closet_items ci
    where ci.id = p_reference_closet_item_id
      and ci.user_id = caller_id and ci.deleted_at is null;
    if not found then
        raise exception 'Reference is missing or not owned';
    end if;
    select * into target_row from fitmatch_vnext.products p
    where p.id = p_target_product_id;
    if not found then raise exception 'Target product not found'; end if;

    effective_value := fitmatch_vnext.effective_target_classification(
        target_row.id
    );
    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        return jsonb_build_object(
            'allowed', false,
            'decision', 'BLOCKED',
            'reason', 'Target effective classification is not CONFIRMED',
            'effective_classification', effective_value,
            'authorized_candidate_product_size_ids', '[]'::jsonb,
            'candidates', '[]'::jsonb,
            'candidate_authority_version', 'fitmatch-vnext-candidates-v2'
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
            order by o.observed_at desc, o.id desc limit 1
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

        canonical_value :=
            fitmatch_vnext.canonical_measurements_for_size_with_context(
                size_row.product_size_id, effective_value
            );
        if coalesce((canonical_value ->> 'semantic_conflict_count')::integer, 0) > 0 then
            semantic_conflict_count_value := semantic_conflict_count_value + 1;
            continue;
        end if;

        authorization_value :=
            fitmatch_vnext.authorize_comparison_with_context(
                reference_row.id, target_row.id, size_row.product_size_id,
                p_manual_explicit, effective_value
            );
        if not coalesce((authorization_value ->> 'allowed')::boolean, false) then
            authorization_rejected_count_value :=
                authorization_rejected_count_value + 1;
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
          and cm.metric_mode = 'CANONICAL' and cm.is_active
          and not (cm.fitmatch_measurement_code = any(coalesce(
              array(select jsonb_array_elements_text(
                  authorization_value -> 'excluded_measurement_codes'
              )), '{}'::text[]
          )));

        if jsonb_array_length(comparison_measurements_value) <
               (authorization_value ->> 'minimum_common')::integer
           or (select count(*)
               from jsonb_array_elements(comparison_measurements_value) evidence
               where evidence ->> 'requirement_mode' = 'REQUIRED_ANY')
              < coalesce((authorization_value ->> 'required_any_count')::integer, 0)
        then
            authorization_rejected_count_value :=
                authorization_rejected_count_value + 1;
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

    if effective_value ->> 'effective_source' = 'GLOBAL_CONFIRMED' then
        authority_version_value := 'fitmatch-vnext-candidates-v1';
        authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
            reference_row.id::text, target_row.id::text,
            p_target_variant_id::text, p_manual_explicit::text,
            candidates_value::text, authority_version_value
        ), 'sha256'), 'hex');
    else
        authority_version_value := 'fitmatch-vnext-candidates-v2';
        authority_fingerprint_value := encode(extensions.digest(concat_ws('|',
            reference_row.id::text, target_row.id::text,
            p_target_variant_id::text, p_manual_explicit::text,
            effective_value ->> 'effective_authority_fingerprint',
            effective_value ->> 'override_revision',
            candidates_value::text, authority_version_value
        ), 'sha256'), 'hex');
    end if;

    return jsonb_build_object(
        'allowed', jsonb_array_length(candidates_value) > 0,
        'decision', case when jsonb_array_length(candidates_value) > 0
            then coalesce(candidates_value -> 0 -> 'authorization' ->> 'decision',
                          'BLOCKED') else 'BLOCKED' end,
        'mode', case when jsonb_array_length(candidates_value) > 0
            then coalesce(candidates_value -> 0 -> 'authorization' ->> 'mode',
                          'NONE') else 'NONE' end,
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
            'latest_available_count', available_count_value,
            'expired_or_unbounded_count', expired_count_value,
            'semantic_conflict_count', semantic_conflict_count_value,
            'authorization_rejected_count', authorization_rejected_count_value
        ),
        'candidate_authority_fingerprint', authority_fingerprint_value,
        'candidate_authority_version', authority_version_value
    );
end
$function$;

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
    effective_value jsonb;
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
    global_classification_snapshot jsonb;
    personal_projection_snapshot jsonb;
    effective_classification_snapshot jsonb;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;
    if p_request ?| array[
        'garment_type_code', 'audience_code', 'category_code',
        'sleeve_length_code', 'lower_length_code', 'body_length_code',
        'comparison_policy_code', 'override_id'
    ] then
        raise exception 'Raw classification authority is not accepted at begin';
    end if;

    client_id := (p_request ->> 'client_comparison_id')::uuid;
    ref_id := (p_request ->> 'reference_closet_item_id')::uuid;
    target_id := (p_request ->> 'target_product_id')::uuid;
    target_variant := (p_request ->> 'target_variant_id')::uuid;
    authorization_size := nullif(
        btrim(p_request ->> 'authorization_product_size_id'), ''
    )::uuid;
    manual_explicit := coalesce(
        (p_request ->> 'manual_explicit')::boolean, false
    );
    if client_id is null or ref_id is null or target_id is null
       or target_variant is null then
        raise exception 'Comparison identity, reference, target, and variant are required';
    end if;

    request_hash := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
    perform pg_advisory_xact_lock(hashtextextended(
        caller_id::text || ':' || client_id::text, 0
    ));
    select * into existing from fitmatch_vnext.comparisons
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
                existing.target_snapshot ->
                    'authorized_candidate_product_size_ids'
        );
    end if;

    select * into ref from fitmatch_vnext.closet_items
    where id = ref_id and user_id = caller_id and deleted_at is null;
    if not found then raise exception 'Reference is missing or not owned'; end if;
    if ref.product_id is not null then
        select * into reference_product from fitmatch_vnext.products
        where id = ref.product_id;
    end if;
    select * into target from fitmatch_vnext.products where id = target_id;
    if not found then raise exception 'Target product not found'; end if;
    if not exists (
        select 1 from fitmatch_vnext.product_variants pv
        where pv.id = target_variant and pv.product_id = target_id
    ) then
        raise exception 'Target variant hierarchy mismatch';
    end if;

    effective_value := fitmatch_vnext.effective_target_classification(target.id);
    if effective_value ->> 'classification_status' <> 'CONFIRMED' then
        raise exception 'Target effective classification is not confirmed';
    end if;
    if effective_value ->> 'effective_source' = 'USER_EXPLICIT' then
        if nullif(p_request ->> 'effective_authority_fingerprint', '')
           is distinct from
           effective_value ->> 'effective_authority_fingerprint' then
            raise exception 'Stale personal classification authority fingerprint';
        end if;
        if nullif(p_request ->> 'personal_override_revision', '')::integer
           is distinct from
           (effective_value ->> 'override_revision')::integer then
            raise exception 'Stale personal classification revision';
        end if;
    end if;

    candidate_authority := fitmatch_vnext.eligible_candidate_sizes(
        ref_id, target_id, target_variant, manual_explicit
    );
    if not coalesce((candidate_authority ->> 'allowed')::boolean, false) then
        raise exception 'Comparison has no eligible candidate sizes: %',
            candidate_authority ->> 'reason';
    end if;
    if candidate_authority ->> 'effective_authority_fingerprint'
       is distinct from effective_value ->> 'effective_authority_fingerprint' then
        raise exception 'Candidate authority classification drift';
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
        from jsonb_array_elements_text(
            p_request -> 'candidate_product_size_ids'
        ) with ordinality item(value, ordinal);
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
    into taxonomy_checksum from fitmatch_vnext.garment_types gt;
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
        'measurements', coalesce((select jsonb_agg(jsonb_build_object(
            'fitmatch_measurement_code', cm.fitmatch_measurement_code,
            'value', cm.value,
            'unit_code', cm.unit_code,
            'value_source', cm.value_source,
            'raw_label_snapshot', cm.raw_label_snapshot
        ) order by cm.fitmatch_measurement_code)
        from fitmatch_vnext.closet_item_measurements cm
        where cm.closet_item_id = ref.id), '[]'::jsonb)
    );
    target_data := jsonb_build_object(
        'product_id', target.id,
        'source_code', target.source_code,
        'source_product_key', target.source_product_key,
        'variant_id', target_variant,
        'candidate_product_size_ids', to_jsonb(authorized_ids),
        'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
        'candidate_authority_fingerprint',
            candidate_authority ->> 'candidate_authority_fingerprint',
        'candidate_authority_version',
            candidate_authority ->> 'candidate_authority_version',
        'classification_status',
            effective_value ->> 'classification_status',
        'classification_source', effective_value ->> 'effective_source',
        'product_structure_code', target.product_structure_code,
        'garment_type_code', effective_value ->> 'garment_type_code',
        'audience_code', effective_value ->> 'audience_code',
        'sleeve_length_code', effective_value ->> 'sleeve_length_code',
        'lower_length_code', effective_value ->> 'lower_length_code',
        'body_length_code', effective_value ->> 'body_length_code',
        'classification_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'global_classification_fingerprint', target.input_fingerprint,
        'classification_evidence_fingerprint', target.evidence_fingerprint,
        'resolver_version', target.resolver_version,
        'ingestion_evidence_fingerprint',
            target.source_extra ->> 'latest_ingestion_fingerprint',
        'candidates', candidates
    );

    select to_jsonb(cp) || jsonb_build_object(
        'metrics', coalesce((select jsonb_agg(jsonb_build_object(
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
        where cm.comparison_policy_code = cp.policy_code and cm.is_active),
            '[]'::jsonb)
    ) into policy_data from fitmatch_vnext.comparison_policies cp
    where cp.policy_code = authz ->> 'policy_code' and cp.is_active;
    if policy_data is null then
        raise exception 'Active policy disappeared during comparison begin';
    end if;

    global_classification_snapshot :=
        effective_value -> 'global_classification';
    personal_projection_snapshot :=
        effective_value -> 'personal_projection';
    effective_classification_snapshot := jsonb_strip_nulls(jsonb_build_object(
        'source', effective_value ->> 'effective_source',
        'state', effective_value ->> 'state',
        'category_code', effective_value ->> 'category_code',
        'garment_type_code', effective_value ->> 'garment_type_code',
        'audience_code', effective_value ->> 'audience_code',
        'sleeve_length_code', effective_value ->> 'sleeve_length_code',
        'lower_length_code', effective_value ->> 'lower_length_code',
        'body_length_code', effective_value ->> 'body_length_code',
        'comparison_policy_code', effective_value ->> 'comparison_policy_code',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint'
    ));

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
        ref.garment_type_code, effective_value ->> 'garment_type_code',
        ref.audience_code, effective_value ->> 'audience_code',
        ref.sleeve_length_code, effective_value ->> 'sleeve_length_code',
        ref.lower_length_code, effective_value ->> 'lower_length_code',
        ref.body_length_code, effective_value ->> 'body_length_code',
        'PENDING', 'pending', 4, jsonb_build_object('phase', 'BEGIN'),
        request_hash, authz ->> 'mode',
        array(select jsonb_array_elements_text(
            authz -> 'excluded_measurement_codes'
        )),
        reference_data, target_data,
        jsonb_build_object(
            'global_classification_at_begin', global_classification_snapshot,
            'personal_projection_at_begin', personal_projection_snapshot,
            'effective_classification_at_begin',
                effective_classification_snapshot,
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
                target.source_extra ->> 'latest_ingestion_fingerprint',
            'manual_cross_rule_at_begin', authz -> 'manual_cross_rule'
        ),
        policy_data, authz,
        jsonb_build_object(
            'client_request', p_request,
            'candidate_authority_fingerprint',
                candidate_authority ->> 'candidate_authority_fingerprint',
            'authorized_candidate_product_size_ids', to_jsonb(authorized_ids),
            'effective_authority_fingerprint',
                effective_value ->> 'effective_authority_fingerprint',
            'personal_override_revision', effective_value -> 'override_revision',
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
            candidate_authority ->> 'candidate_authority_fingerprint',
        'effective_authority_fingerprint',
            effective_value ->> 'effective_authority_fingerprint',
        'snapshot_schema_version', 4
    );
end
$function$;
