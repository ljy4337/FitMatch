-- Purpose: live retailer structure and comparison-unit contract correction.
-- This is an undeployed forward migration. It never rewrites historical
-- receipts and it does not deploy or mutate Production during repository work.
--
-- The contract deliberately separates retailer product cardinality from the
-- measured garment unit that FitMatch may authorize for comparison.

begin;

-- All state assumptions are checked before any DDL/data mutation. A mismatch
-- aborts the whole transaction rather than applying a partial authority change.
do $preflight$
declare
    active_policy_count integer;
    unexpected_policy_count integer;
    ingress_definition text;
    authorization_definition text;
    readiness_definition text;
    recovery_definition text;
    uniqlo_measurement_contract_count integer;
    is_security_definer boolean;
    ingress_proc regprocedure :=
        'fitmatch_vnext.ingest_product_observation(jsonb,uuid)'::regprocedure;
    authorization_proc regprocedure :=
        'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure;
    readiness_proc regprocedure :=
        'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure;
    recovery_proc regprocedure :=
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure;
begin
    if to_regclass('fitmatch_vnext.products') is null
       or to_regclass('fitmatch_vnext.product_ingestion_receipts') is null
       or to_regclass('fitmatch_vnext.source_classification_signals') is null
       or to_regclass('fitmatch_vnext.classification_signal_mappings') is null
       or to_regclass('fitmatch_vnext.source_measurement_aliases') is null
       or to_regclass('fitmatch_vnext.source_measurement_mappings') is null
       or to_regclass('fitmatch_vnext.comparison_policies') is null
       or to_regclass('fitmatch_catalog.current_product_classifications') is null then
        raise exception 'Required live-retailer contract tables are missing';
    end if;

    -- The iOS observation explicitly names `size_chart`; verify that the
    -- deployed resolver can translate the current official UNIQLO raw codes
    -- before replacing ingress. This is a provider contract guard, not a
    -- product-specific mapping.
    select count(distinct a.raw_code) into uniqlo_measurement_contract_count
    from fitmatch_vnext.source_measurement_aliases a
    join fitmatch_vnext.source_measurement_mappings m
      on m.source_measurement_code = a.source_measurement_code
     and m.is_active and m.is_verified
    where a.source_code = 'uniqlo'
      and a.parser_code = 'size_chart'
      and a.raw_code in (
        'body-width','shoulder-width','body-length-back',
        'knit-body-length-front'
      )
      and a.is_active and a.is_verified;
    if uniqlo_measurement_contract_count <> 4 then
        raise exception 'UNIQLO size-chart measurement contract preimage mismatch: %',
            uniqlo_measurement_contract_count;
    end if;
    if to_regprocedure('fitmatch_vnext.ingest_product_observation(jsonb,uuid)') is null
       or to_regprocedure('fitmatch_vnext.resolve_product_classification(text,text,boolean)') is null
       or to_regprocedure('fitmatch_vnext.classification_decision(text,text)') is null
       or to_regprocedure('fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)') is null
       or to_regprocedure('fitmatch_vnext.product_readiness_with_context(uuid,jsonb)') is null
       or to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)') is null then
        raise exception 'Expected vNext ingress/classification contract is missing';
    end if;

    -- These are intentionally independent preimage assertions over the
    -- deployed public contract: signature, security mode/ACL, and the
    -- critical body anchors that make the v1-to-v2 forward replacement safe.
    -- A stale or hand-edited authority function aborts before any rename,
    -- policy mutation, or data projection can occur.
    if to_regprocedure('fitmatch_vnext.ingest_product_observation_v1(jsonb,uuid)') is not null
       or to_regprocedure('fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)') is not null
       or to_regprocedure('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)') is not null
       or to_regprocedure('fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb)') is not null then
        raise exception 'Unexpected prior live-retailer wrapper collision';
    end if;

    select pg_get_functiondef(p.oid), p.prosecdef
    into ingress_definition, is_security_definer
    from pg_proc p where p.oid = ingress_proc;
    if not is_security_definer
       or has_function_privilege('public', ingress_proc, 'EXECUTE')
       or has_function_privilege('anon', ingress_proc, 'EXECUTE')
       or has_function_privilege('authenticated', ingress_proc, 'EXECUTE')
       or not has_function_privilege('service_role', ingress_proc, 'EXECUTE') then
        raise exception 'Unexpected ingest_product_observation security preimage';
    end if;
    if position('product_ingestion_receipts' in ingress_definition) = 0
       or position('Awaiting deterministic replay after new retailer evidence'
                   in ingress_definition) = 0 then
        raise exception 'Unexpected ingest_product_observation preimage';
    end if;

    select pg_get_functiondef(p.oid), p.prosecdef
    into authorization_definition, is_security_definer
    from pg_proc p where p.oid = authorization_proc;
    if not is_security_definer
       or has_function_privilege('public', authorization_proc, 'EXECUTE')
       or has_function_privilege('anon', authorization_proc, 'EXECUTE')
       or has_function_privilege('authenticated', authorization_proc, 'EXECUTE')
       or not has_function_privilege('service_role', authorization_proc, 'EXECUTE')
       or position('manual_cross_comparison_rules' in authorization_definition) = 0
       or position('ADULT_ANY' in authorization_definition) = 0 then
        raise exception 'Unexpected authorize_comparison_with_context preimage';
    end if;

    select pg_get_functiondef(p.oid), p.prosecdef
    into readiness_definition, is_security_definer
    from pg_proc p where p.oid = readiness_proc;
    if is_security_definer
       or has_function_privilege('public', readiness_proc, 'EXECUTE')
       or has_function_privilege('anon', readiness_proc, 'EXECUTE')
       or has_function_privilege('authenticated', readiness_proc, 'EXECUTE')
       or not has_function_privilege('service_role', readiness_proc, 'EXECUTE')
       or position('canonical_measurements_for_size_with_context' in readiness_definition) = 0
       or position('fitmatch-vnext-readiness-v2' in readiness_definition) = 0 then
        raise exception 'Unexpected product_readiness_with_context preimage';
    end if;

    select pg_get_functiondef(p.oid) into recovery_definition
    from pg_proc p where p.oid = recovery_proc;
    if position(
        'elsif product_row.product_structure_code <> ''SINGLE'' then'
        in recovery_definition
    ) = 0
       or position('PRODUCT_STRUCTURE_NOT_SINGLE' in recovery_definition) = 0
       or position('fitmatch_vnext.classification_tuple_validation('
                   in recovery_definition) = 0 then
        raise exception 'Unexpected classification_recovery_options preimage';
    end if;

    select count(*) into active_policy_count
    from fitmatch_vnext.comparison_policies where is_active;
    if active_policy_count <> 39 then
        raise exception 'Expected 39 active comparison policies, found %',
            active_policy_count;
    end if;
    select count(*) into unexpected_policy_count
    from fitmatch_vnext.comparison_policies cp
    where cp.is_active
      and cp.policy_code <> all(array[
        'anorak','base_layer_top','blazer','blouson','bodysuit_top',
        'cardigan','coat','dress','fleece_jacket','homewear_bottom',
        'homewear_top','hoodie','jacket','knit_sweater','knit_vest',
        'leggings','ma1','mouton','outer_vest','polo_shirt',
        'puffer_jacket','puffer_vest','shirt_blouse','skirt',
        'sleeveless_tshirt','sports_top','standard_pants','sweatshirt',
        'tank_top','tshirt','windbreaker','zip_hoodie',
        'men_briefs','men_trunks','men_undershirt','women_bra',
        'women_camisole','women_panty','women_slip'
      ]::text[]);
    if unexpected_policy_count <> 0 then
        raise exception 'Unreviewed active comparison policy scope: %',
            unexpected_policy_count;
    end if;
end
$preflight$;

-- Keep the deployed body available for rollback/forensics. The public action
-- below calls v2 directly; it never calls v1 and then repairs its result.
do $rename_ingest_v1$
begin
    if to_regprocedure('fitmatch_vnext.ingest_product_observation_v1(jsonb,uuid)') is null then
        execute 'alter function fitmatch_vnext.ingest_product_observation(jsonb,uuid) '
             || 'rename to ingest_product_observation_v1';
    end if;
end
$rename_ingest_v1$;

create or replace function fitmatch_vnext.product_comparison_unit_decision(
    p_product_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with product_row as (
    select p.id, upper(coalesce(p.product_structure_code, 'UNKNOWN')) structure_code,
           upper(coalesce(
               p.source_extra -> 'comparison_measurement_contract' ->> 'effective_value',
               p.source_extra -> 'structured_facts' ->> 'comparison_measurement_contract',
               'ABSENT'
           )) measurement_contract
    from fitmatch_vnext.products p
    where p.id = p_product_id
), decision as (
    select p.*,
           case
             when p.structure_code = 'SET' then false
             when p.measurement_contract = 'MULTIPLE_COMPONENT' then false
             when p.structure_code in ('SINGLE','MULTIPACK','UNKNOWN')
                and p.measurement_contract = 'SINGLE_COHERENT' then true
             else false
           end eligible,
           case
             when p.structure_code = 'SET' then 'MIXED_GARMENT_SET'
             when p.measurement_contract = 'MULTIPLE_COMPONENT'
                then 'MULTIPLE_COMPONENT_MEASUREMENT_CONTRACT'
             when p.structure_code = 'SINGLE'
                and p.measurement_contract = 'SINGLE_COHERENT'
                then 'EXPLICIT_SINGLE_ONE_COHERENT_CONTRACT'
             when p.structure_code = 'SINGLE'
                then 'SINGLE_CONTRACT_UNVERIFIED'
             when p.structure_code = 'MULTIPACK'
                and p.measurement_contract = 'SINGLE_COHERENT'
                then 'HOMOGENEOUS_MULTIPACK_ONE_COHERENT_CONTRACT'
             when p.structure_code = 'UNKNOWN'
                and p.measurement_contract = 'SINGLE_COHERENT'
                then 'UNKNOWN_STRUCTURE_ONE_COHERENT_CONTRACT'
             when p.structure_code = 'MULTIPACK' then 'MULTIPACK_CONTRACT_UNVERIFIED'
             else 'STRUCTURE_OR_MEASUREMENT_CONTRACT_UNVERIFIED'
           end reason
    from product_row p
)
select coalesce((
    select jsonb_build_object(
        'found', true,
        'product_id', id,
        'product_structure_code', structure_code,
        'measurement_contract', measurement_contract,
        'eligible', eligible,
        'reason', reason
    ) from decision
), jsonb_build_object('found', false, 'eligible', false,
    'reason', 'UNKNOWN_PRODUCT'));
$function$;

create or replace function fitmatch_vnext.comparison_unit_tuple_validation(
    p_garment_type_code text,
    p_product_structure_code text,
    p_measurement_contract text,
    p_audience_code text,
    p_sleeve_length_code text,
    p_lower_length_code text,
    p_body_length_code text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with gt as (
    select garment_type_code, is_active, uses_sleeve_length,
           uses_lower_length, uses_body_length
    from fitmatch_vnext.garment_types
    where garment_type_code = p_garment_type_code
), checks as (
    select
        gt.garment_type_code is not null garment_exists,
        coalesce(gt.is_active, false) garment_active,
        (
          upper(coalesce(p_product_structure_code, 'UNKNOWN'))
              in ('SINGLE','MULTIPACK','UNKNOWN')
          and upper(coalesce(p_measurement_contract, 'ABSENT'))
              = 'SINGLE_COHERENT'
        ) unit_valid,
        p_audience_code is not null and p_audience_code <> 'UNKNOWN' audience_valid,
        case when coalesce(gt.uses_sleeve_length, false)
          then p_sleeve_length_code is not null
            and p_sleeve_length_code <> 'UNKNOWN'
          else p_sleeve_length_code is null end sleeve_valid,
        case when coalesce(gt.uses_lower_length, false)
          then p_lower_length_code is not null
            and p_lower_length_code <> 'UNKNOWN'
          else p_lower_length_code is null end lower_valid,
        case when coalesce(gt.uses_body_length, false)
          then p_body_length_code is not null
            and p_body_length_code <> 'UNKNOWN'
          else p_body_length_code is null end body_valid
    from (select 1) seed left join gt on true
)
select jsonb_build_object(
    'valid', garment_exists and garment_active and unit_valid and audience_valid
       and sleeve_valid and lower_valid and body_valid,
    'garment_exists', garment_exists,
    'garment_active', garment_active,
    'comparison_unit_valid', unit_valid,
    'audience_valid', audience_valid,
    'sleeve_valid', sleeve_valid,
    'lower_valid', lower_valid,
    'body_valid', body_valid
) from checks;
$function$;

-- Existing callers retain this tuple API. It validates axes and a legal
-- cardinality domain; product-level comparison eligibility is additionally
-- enforced by product_comparison_unit_decision at ingress and authorization.
create or replace function fitmatch_vnext.classification_tuple_validation(
    p_garment_type_code text,
    p_product_structure_code text,
    p_audience_code text,
    p_sleeve_length_code text,
    p_lower_length_code text,
    p_body_length_code text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with gt as (
    select garment_type_code, is_active, uses_sleeve_length,
           uses_lower_length, uses_body_length
    from fitmatch_vnext.garment_types
    where garment_type_code = p_garment_type_code
), checks as (
    select
        gt.garment_type_code is not null garment_exists,
        coalesce(gt.is_active, false) garment_active,
        upper(coalesce(p_product_structure_code, 'UNKNOWN'))
            in ('SINGLE','MULTIPACK','UNKNOWN') structure_valid,
        p_audience_code is not null and p_audience_code <> 'UNKNOWN' audience_valid,
        case when coalesce(gt.uses_sleeve_length, false)
          then p_sleeve_length_code is not null
            and p_sleeve_length_code <> 'UNKNOWN'
          else p_sleeve_length_code is null end sleeve_valid,
        case when coalesce(gt.uses_lower_length, false)
          then p_lower_length_code is not null
            and p_lower_length_code <> 'UNKNOWN'
          else p_lower_length_code is null end lower_valid,
        case when coalesce(gt.uses_body_length, false)
          then p_body_length_code is not null
            and p_body_length_code <> 'UNKNOWN'
          else p_body_length_code is null end body_valid
    from (select 1) seed left join gt on true
)
select jsonb_build_object(
    'valid', garment_exists and garment_active and structure_valid
       and audience_valid and sleeve_valid and lower_valid and body_valid,
    'garment_exists', garment_exists,
    'garment_active', garment_active,
    'structure_valid', structure_valid,
    'audience_valid', audience_valid,
    'sleeve_valid', sleeve_valid,
    'lower_valid', lower_valid,
    'body_valid', body_valid
) from checks;
$function$;

create or replace function fitmatch_vnext.validate_garment_axis_values()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    gt fitmatch_vnext.garment_types%rowtype;
    enforce_complete boolean := false;
    structure_code text;
    audience text;
    comparison_contract text := 'ABSENT';
begin
    if new.garment_type_code is null then
        if tg_table_name = 'products'
           and new.classification_status = 'CONFIRMED' then
            raise exception 'CONFIRMED product requires garment_type_code';
        end if;
        return new;
    end if;
    select * into gt from fitmatch_vnext.garment_types
    where garment_type_code = new.garment_type_code;
    if not found or not gt.is_active then
        raise exception 'Unknown or inactive garment_type_code %', new.garment_type_code;
    end if;
    if not gt.uses_sleeve_length and new.sleeve_length_code is not null then
        raise exception 'garment_type % does not use sleeve_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_lower_length and new.lower_length_code is not null then
        raise exception 'garment_type % does not use lower_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_body_length and new.body_length_code is not null then
        raise exception 'garment_type % does not use body_length_code',
            new.garment_type_code;
    end if;
    if tg_table_name = 'products' then
        enforce_complete := new.classification_status = 'CONFIRMED';
        structure_code := upper(coalesce(new.product_structure_code, 'UNKNOWN'));
        audience := new.audience_code;
        comparison_contract := upper(coalesce(
            new.source_extra -> 'comparison_measurement_contract' ->> 'effective_value',
            new.source_extra -> 'structured_facts' ->> 'comparison_measurement_contract',
            'ABSENT'
        ));
    elsif tg_table_name = 'closet_items' then
        enforce_complete := true;
        structure_code := 'SINGLE';
        audience := new.audience_code;
    end if;
    if enforce_complete then
        if structure_code = 'SET'
           or structure_code not in ('SINGLE','MULTIPACK','UNKNOWN')
           or (tg_table_name = 'products'
               and comparison_contract <> 'SINGLE_COHERENT') then
            raise exception 'comparable classification requires an eligible comparison unit';
        end if;
        if audience is null or audience = 'UNKNOWN' then
            raise exception 'comparable classification requires known audience_code';
        end if;
        if gt.uses_sleeve_length and
           (new.sleeve_length_code is null or new.sleeve_length_code = 'UNKNOWN') then
            raise exception 'garment_type % requires a known sleeve_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_lower_length and
           (new.lower_length_code is null or new.lower_length_code = 'UNKNOWN') then
            raise exception 'garment_type % requires a known lower_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_body_length and
           (new.body_length_code is null or new.body_length_code = 'UNKNOWN') then
            raise exception 'garment_type % requires a known body_length_code',
                new.garment_type_code;
        end if;
    end if;
    return new;
end
$function$;

create or replace function fitmatch_vnext.uniqlo_complete_observed_category_path(
    p_signal_id uuid
)
returns text[]
language sql
stable
set search_path = ''
as $function$
with target as (
    select s.id, s.external_key, s.audience_code
    from fitmatch_vnext.source_classification_signals s
    where s.id = p_signal_id
      and s.source_code = 'uniqlo'
      and s.signal_kind = 'CATEGORY'
      and s.is_active
      and s.audience_code in ('MEN','WOMEN','UNISEX')
), receipt_paths as (
    select t.external_key,
           array_agg(btrim(code.value) order by code.ordinality) path
    from target t
    join fitmatch_vnext.product_classification_signals pcs
      on pcs.source_signal_id = t.id
    join fitmatch_vnext.products p on p.id = pcs.product_id
     and p.source_code = 'uniqlo' and p.audience_code = t.audience_code
    join fitmatch_vnext.product_ingestion_receipts r
      on r.product_id = p.id and r.source_code = 'uniqlo'
     and r.processing_status = 'PROCESSED'
     and r.observed_at = p.last_seen_at
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(r.retailer_facts -> 'source_category_codes') = 'array'
        then r.retailer_facts -> 'source_category_codes'
        else '[]'::jsonb end
    ) with ordinality code(value, ordinality)
    where r.retailer_facts -> 'structured_facts'
            ->> 'source_category_path_completeness' = 'complete'
      and r.retailer_facts -> 'structured_facts'
            ->> 'source_category_path_source' = 'uniqlo_pdp_breadcrumbs'
      and case upper(btrim(r.retailer_facts ->> 'audience'))
            when 'M' then 'MEN' when 'MAN' then 'MEN' when 'MALE' then 'MEN'
            when 'W' then 'WOMEN' when 'WOMAN' then 'WOMEN' when 'FEMALE' then 'WOMEN'
            when 'U' then 'UNISEX' when 'COMMON' then 'UNISEX' when 'M,W' then 'UNISEX'
            else upper(btrim(r.retailer_facts ->> 'audience')) end = t.audience_code
      and btrim(code.value) <> ''
    group by r.id, t.external_key
), valid_paths as (
    select path from receipt_paths
    where cardinality(path) > 0
      and path[cardinality(path)] = external_key
      and cardinality(path) = (
          select count(distinct code) from unnest(path) code
      )
)
select path from valid_paths
where (select count(distinct path) from valid_paths) = 1
limit 1;
$function$;

create or replace function fitmatch_vnext.uniqlo_category_parent_chain_matches_observed_path(
    p_signal_id uuid,
    p_path text[]
)
returns boolean
language sql
stable
set search_path = ''
as $function$
with recursive target as (
    select s.id, s.audience_code
    from fitmatch_vnext.source_classification_signals s
    where s.id = p_signal_id
      and s.source_code = 'uniqlo'
      and s.signal_kind = 'CATEGORY'
      and s.is_active
      and s.audience_code in ('MEN','WOMEN','UNISEX')
      and cardinality(p_path) > 0
      and s.external_key = p_path[cardinality(p_path)]
), expected as (
    select btrim(code.value) external_key, code.ordinality
    from unnest(p_path) with ordinality code(value, ordinality)
    where btrim(code.value) <> ''
), walk as (
    select s.id, s.parent_signal_id, s.external_key, s.audience_code,
           0 depth, array[s.id] visited, false cycle
    from fitmatch_vnext.source_classification_signals s
    join target t on t.id = s.id
    union all
    select parent.id, parent.parent_signal_id, parent.external_key,
           parent.audience_code, w.depth + 1,
           w.visited || parent.id, parent.id = any(w.visited)
    from walk w
    join fitmatch_vnext.source_classification_signals parent
      on parent.id = w.parent_signal_id
    where w.parent_signal_id is not null
      and w.depth < 16
      and not w.cycle
), chain as (
    select array_agg(w.external_key order by w.depth desc) path,
           bool_or(w.cycle) has_cycle,
           bool_or(w.depth >= 16 and w.parent_signal_id is not null) hit_depth_limit,
           bool_or(w.parent_signal_id is not null and not exists (
               select 1 from fitmatch_vnext.source_classification_signals parent
               where parent.id = w.parent_signal_id
           )) missing_parent,
           bool_and(w.audience_code = (select audience_code from target)) audience_consistent
    from walk w
)
select exists (select 1 from target)
   and (select path from chain) = p_path
   and not coalesce((select has_cycle from chain), true)
   and not coalesce((select hit_depth_limit from chain), true)
   and not coalesce((select missing_parent from chain), true)
   and coalesce((select audience_consistent from chain), false)
   and cardinality(p_path) = (select count(*) from expected)
   and not exists (
       select 1 from expected e
       where (select count(*) from fitmatch_vnext.source_classification_signals s
              join target t on t.audience_code = s.audience_code
              where s.source_code = 'uniqlo'
                and s.signal_kind = 'CATEGORY'
                and s.is_active
                and s.external_key = e.external_key) <> 1
   );
$function$;

create or replace function fitmatch_vnext.uniqlo_category_parent_chain_safe(
    p_signal_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $function$
with observed as (
    select fitmatch_vnext.uniqlo_complete_observed_category_path(p_signal_id) path
)
select path is not null
   and fitmatch_vnext.uniqlo_category_parent_chain_matches_observed_path(
       p_signal_id, path
   )
from observed;
$function$;

create or replace function fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(
    p_mapping_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $function$
with automatic_mapping as (
    select m.id, m.source_signal_id, m.audience_code, m.resolution_mode,
           m.garment_type_code, m.sleeve_length_code,
           m.lower_length_code, m.body_length_code,
           s.external_key, s.audience_code signal_audience_code,
           fitmatch_vnext.uniqlo_complete_observed_category_path(s.id) path
    from fitmatch_vnext.classification_signal_mappings m
    join fitmatch_vnext.source_classification_signals s on s.id = m.source_signal_id
    where m.id = p_mapping_id
      and m.mapping_version in (
          'vnext-uniqlo-complete-path-20260902-v3',
          'vnext-uniqlo-product-required-envelope-20260903-v1'
      )
      and m.is_active and m.is_verified
      and m.resolution_mode in ('DIRECT', 'PRODUCT_REQUIRED')
      and s.source_code = 'uniqlo' and s.signal_kind = 'CATEGORY' and s.is_active
), target as (
    select m.* from automatic_mapping m
    where m.path is not null
      and m.audience_code = m.signal_audience_code
      and fitmatch_vnext.uniqlo_category_parent_chain_matches_observed_path(
          m.source_signal_id, m.path
      )
      and not exists (
          select 1 from fitmatch_vnext.classification_signal_mappings target_mapping
          where target_mapping.source_signal_id = m.source_signal_id
            and target_mapping.is_active and target_mapping.is_verified
            and target_mapping.id <> m.id
      )
), peer_mappings as (
    select peer_mapping.*
    from target t
    join fitmatch_vnext.source_classification_signals peer
      on peer.source_code = 'uniqlo'
     and peer.signal_kind = 'CATEGORY'
     and peer.external_key = t.external_key
     and peer.id <> t.source_signal_id
     and peer.is_active
     and peer.audience_code in ('MEN','WOMEN','UNISEX')
     and fitmatch_vnext.uniqlo_complete_observed_category_path(peer.id) = t.path
     and fitmatch_vnext.uniqlo_category_parent_chain_matches_observed_path(peer.id, t.path)
    join fitmatch_vnext.classification_signal_mappings peer_mapping
      on peer_mapping.source_signal_id = peer.id
     and peer_mapping.is_active and peer_mapping.is_verified
     and peer_mapping.audience_code in (peer.audience_code, 'ANY')
     and coalesce(peer_mapping.mapping_version, '') not in (
         'vnext-uniqlo-complete-path-20260902-v3',
         'vnext-uniqlo-product-required-envelope-20260903-v1'
     )
), peer_summary as (
    select count(*) mapping_count,
           bool_and(resolution_mode = 'DIRECT') direct_only,
           count(distinct concat_ws('|', resolution_mode,
               coalesce(garment_type_code, '∅'),
               coalesce(sleeve_length_code, '∅'),
               coalesce(lower_length_code, '∅'),
               coalesce(body_length_code, '∅'))) tuple_count,
           min(concat_ws('|', resolution_mode,
               coalesce(garment_type_code, '∅'),
               coalesce(sleeve_length_code, '∅'),
               coalesce(lower_length_code, '∅'),
               coalesce(body_length_code, '∅'))) tuple_value
    from peer_mappings
), target_tuple as (
    select concat_ws('|', resolution_mode,
        coalesce(garment_type_code, '∅'),
        coalesce(sleeve_length_code, '∅'),
        coalesce(lower_length_code, '∅'),
        coalesce(body_length_code, '∅')) tuple_value
    from target
)
select exists (select 1 from target)
   and coalesce((select mapping_count from peer_summary), 0) > 0
   and (
       coalesce((select direct_only from peer_summary), false)
       or (select resolution_mode from target) = 'PRODUCT_REQUIRED'
   )
   and coalesce((select tuple_count from peer_summary), 0) = 1
   and (select tuple_value from peer_summary) = (select tuple_value from target_tuple);
$function$;

create or replace function fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(
    p_target_signal_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    inserted_count integer := 0;
begin
    with target as (
        select s.id, s.external_key, s.audience_code,
               fitmatch_vnext.uniqlo_complete_observed_category_path(s.id) path
        from fitmatch_vnext.source_classification_signals s
        where s.id = p_target_signal_id
          and s.source_code = 'uniqlo'
          and s.signal_kind = 'CATEGORY'
          and s.is_active
          and s.audience_code in ('MEN','WOMEN','UNISEX')
          and fitmatch_vnext.uniqlo_category_parent_chain_safe(s.id)
    ), peers as (
        select peer.id, peer.audience_code
        from target t
        join fitmatch_vnext.source_classification_signals peer
          on peer.source_code = 'uniqlo'
         and peer.signal_kind = 'CATEGORY'
         and peer.external_key = t.external_key
         and peer.id <> t.id
         and peer.is_active
         and peer.audience_code in ('MEN','WOMEN','UNISEX')
         and fitmatch_vnext.uniqlo_category_parent_chain_safe(peer.id)
         and fitmatch_vnext.uniqlo_complete_observed_category_path(peer.id) = t.path
        where t.path is not null
    ), peer_mappings as (
        select m.*
        from peers peer
        join fitmatch_vnext.classification_signal_mappings m
         on m.source_signal_id = peer.id
         and m.is_active and m.is_verified
         and m.audience_code in (peer.audience_code, 'ANY')
         and coalesce(m.mapping_version, '') not in (
             'vnext-uniqlo-complete-path-20260902-v3',
             'vnext-uniqlo-product-required-envelope-20260903-v1'
         )
    ), eligible as (
        select t.id target_signal_id, t.audience_code target_audience_code,
               min(m.resolution_mode) resolution_mode,
               min(m.garment_type_code) garment_type_code,
               min(m.sleeve_length_code) sleeve_length_code,
               min(m.lower_length_code) lower_length_code,
               min(m.body_length_code) body_length_code,
               max(m.priority)::smallint priority
        from target t join peer_mappings m on true
        where t.path is not null
          and not exists (
            select 1 from fitmatch_vnext.classification_signal_mappings existing
            where existing.source_signal_id = t.id
              and existing.is_active and existing.is_verified
          )
        group by t.id, t.audience_code
        having count(*) > 0
          and count(distinct concat_ws('|', m.resolution_mode,
              coalesce(m.garment_type_code, '∅'),
              coalesce(m.sleeve_length_code, '∅'),
              coalesce(m.lower_length_code, '∅'),
              coalesce(m.body_length_code, '∅'))) = 1
          and (
              (
                  bool_and(m.resolution_mode = 'DIRECT')
                  and bool_and(coalesce((fitmatch_vnext.classification_tuple_validation(
                      m.garment_type_code, 'SINGLE', t.audience_code,
                      m.sleeve_length_code, m.lower_length_code, m.body_length_code
                  ) ->> 'valid')::boolean, false))
              )
              or bool_and(m.resolution_mode = 'PRODUCT_REQUIRED')
          )
    )
    insert into fitmatch_vnext.classification_signal_mappings (
        source_signal_id, audience_code, garment_type_code, resolution_mode,
        sleeve_length_code, lower_length_code, body_length_code, priority,
        is_verified, is_active, mapping_version, mapping_checksum
    )
    select target_signal_id, target_audience_code,
           case when resolution_mode = 'DIRECT' then garment_type_code end,
           resolution_mode,
           case when resolution_mode = 'DIRECT' then sleeve_length_code end,
           case when resolution_mode = 'DIRECT' then lower_length_code end,
           case when resolution_mode = 'DIRECT' then body_length_code end,
           priority, true, true,
           case resolution_mode
             when 'DIRECT' then 'vnext-uniqlo-complete-path-20260902-v3'
             else 'vnext-uniqlo-product-required-envelope-20260903-v1'
           end,
           repeat('0',64)
    from eligible;

    get diagnostics inserted_count = row_count;
    return inserted_count;
end
$function$;

revoke all on function fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(uuid)
    to service_role;

create or replace function fitmatch_vnext.revalidate_uniqlo_auto_promoted_mappings(
    p_external_key text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    revoked_count integer := 0;
begin
    update fitmatch_vnext.classification_signal_mappings mapping
    set is_active = false
    from fitmatch_vnext.source_classification_signals signal
    where signal.id = mapping.source_signal_id
      and signal.source_code = 'uniqlo'
      and signal.signal_kind = 'CATEGORY'
      and signal.external_key = p_external_key
      and mapping.mapping_version in (
          'vnext-uniqlo-complete-path-20260902-v3',
          'vnext-uniqlo-product-required-envelope-20260903-v1'
      )
      and mapping.is_active
      and not fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(mapping.id);
    get diagnostics revoked_count = row_count;
    return revoked_count;
end
$function$;

revoke all on function fitmatch_vnext.revalidate_uniqlo_auto_promoted_mappings(text)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.revalidate_uniqlo_auto_promoted_mappings(text)
    to service_role;

create or replace function fitmatch_vnext.classification_decision(
    p_source_code text,
    p_source_product_key text
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
with recursive product_row as (
    select p.*
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key
), comparison_unit as (
    select p.id, fitmatch_vnext.product_comparison_unit_decision(p.id) unit
    from product_row p
), evidence as (
    select p.id product_id, pcs.source_signal_id, pcs.evidence_order,
           ss.signal_kind, ss.external_key,
           case ss.signal_kind
             when 'PRODUCT_EXACT' then 600
             when 'PRODUCT_STRUCTURE' then 500
             when 'PRODUCT_TYPE' then 400
             when 'SUBFAMILY' then 300
             when 'FAMILY' then 250
             when 'CATEGORY' then 200
             when 'SECTION' then 150
             else 100
           end evidence_rank
    from product_row p
    join fitmatch_vnext.product_classification_signals pcs
      on pcs.product_id = p.id
    join fitmatch_vnext.source_classification_signals ss
      on ss.id = pcs.source_signal_id
     and ss.source_code = p.source_code
     and ss.is_active
), raw_candidates as (
    select e.*, m.id mapping_id, m.resolution_mode, m.garment_type_code,
           m.sleeve_length_code, m.lower_length_code, m.body_length_code,
           m.priority, m.mapping_version, m.mapping_checksum
    from evidence e
    join product_row p on p.id = e.product_id
    join fitmatch_vnext.classification_signal_mappings m
      on m.source_signal_id = e.source_signal_id
     and m.is_active and m.is_verified
     and (m.audience_code = 'ANY' or m.audience_code = p.audience_code)
     and (
        coalesce(m.mapping_version, '') not in (
            'vnext-uniqlo-complete-path-20260902-v3',
            'vnext-uniqlo-product-required-envelope-20260903-v1'
        )
        or fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(m.id)
     )
), signal_ancestry(descendant_id, ancestor_id, depth) as (
    select s.id, s.parent_signal_id, 1
    from fitmatch_vnext.source_classification_signals s
    where s.parent_signal_id is not null
    union all
    select a.descendant_id, s.parent_signal_id, a.depth + 1
    from signal_ancestry a
    join fitmatch_vnext.source_classification_signals s
      on s.id = a.ancestor_id
    where s.parent_signal_id is not null and a.depth < 16
), candidates as (
    select c.*, max(c.evidence_rank) over () max_evidence_rank
    from raw_candidates c
    where not exists (
        select 1 from raw_candidates d
        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id
        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
), ranked as (
    select c.*, max(priority) over () max_priority
    from candidates c
    where evidence_rank = max_evidence_rank
), top_candidates as (
    select * from ranked where priority = max_priority
), summary as (
    select count(*) candidate_count,
           count(distinct concat_ws('|', resolution_mode,
             coalesce(garment_type_code, '∅'),
             coalesce(sleeve_length_code, '∅'),
             coalesce(lower_length_code, '∅'),
             coalesce(body_length_code, '∅'))) outcome_count
    from top_candidates
), chosen as (
    select * from top_candidates
    order by evidence_order, source_signal_id, mapping_id limit 1
), resolved as (
    select p.*, unit.unit comparison_unit,
           c.source_signal_id, c.mapping_id,
           c.resolution_mode mapping_resolution_mode,
           c.garment_type_code mapped_garment_type_code,
           c.sleeve_length_code mapped_sleeve_length_code,
           c.lower_length_code mapped_lower_length_code,
           c.body_length_code mapped_body_length_code,
           c.mapping_version, c.mapping_checksum,
           coalesce(s.candidate_count, 0) candidate_count,
           coalesce(s.outcome_count, 0) outcome_count
    from product_row p
    left join comparison_unit unit on unit.id = p.id
    left join summary s on true
    left join chosen c on true
), decision as (
    select r.*,
      case
        when not coalesce((r.comparison_unit ->> 'eligible')::boolean, false)
          and (r.product_structure_code = 'SET'
            or r.comparison_unit ->> 'measurement_contract' = 'MULTIPLE_COMPONENT')
          then 'NOT_APPLICABLE'
        when not coalesce((r.comparison_unit ->> 'eligible')::boolean, false)
          then 'REVIEW_REQUIRED'
        when r.candidate_count = 0 then 'REVIEW_REQUIRED'
        when r.outcome_count > 1 then 'REVIEW_REQUIRED'
        when r.mapping_resolution_mode = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
        when r.mapping_resolution_mode = 'DIRECT'
          and coalesce((fitmatch_vnext.comparison_unit_tuple_validation(
              r.mapped_garment_type_code, r.product_structure_code,
              r.comparison_unit ->> 'measurement_contract', r.audience_code,
              r.mapped_sleeve_length_code, r.mapped_lower_length_code,
              r.mapped_body_length_code
          ) ->> 'valid')::boolean, false) then 'CONFIRMED'
        else 'REVIEW_REQUIRED'
      end decision_status,
      case
        when not coalesce((r.comparison_unit ->> 'eligible')::boolean, false)
          then r.comparison_unit ->> 'reason'
        when r.candidate_count = 0 then 'No active verified mapping candidate'
        when r.outcome_count > 1
          then 'Equal-top candidates have different outcomes'
        when r.mapping_resolution_mode = 'NOT_APPLICABLE'
          then 'Mapping is NOT_APPLICABLE'
        when r.mapping_resolution_mode = 'DIRECT'
          then 'Complete verified DIRECT mapping'
        when r.mapping_resolution_mode = 'PRODUCT_REQUIRED'
          then 'Product-exact verified evidence is required'
        else 'Mapping requires review'
      end decision_reason
    from resolved r
)
select case when not exists (select 1 from product_row) then
    jsonb_build_object(
        'found', false, 'classification_status', 'REVIEW_REQUIRED',
        'resolution_mode', 'REVIEW_REQUIRED',
        'reason', 'Unknown source product identity',
        'resolver_version', 'fitmatch-vnext-resolver-v3'
    )
else (
    select jsonb_strip_nulls(jsonb_build_object(
        'found', true, 'product_id', d.id,
        'source_code', d.source_code, 'source_product_key', d.source_product_key,
        'classification_status', d.decision_status,
        'resolution_mode', case
          when d.decision_status = 'CONFIRMED' then 'DIRECT'
          when d.decision_status = 'NOT_APPLICABLE' then 'NOT_APPLICABLE'
          else coalesce(d.mapping_resolution_mode, 'REVIEW_REQUIRED') end,
        'garment_type_code', case when d.decision_status = 'CONFIRMED'
          then d.mapped_garment_type_code end,
        'product_structure_code', d.product_structure_code,
        'comparison_measurement_contract',
          d.comparison_unit ->> 'measurement_contract',
        'comparison_unit_eligible', d.comparison_unit -> 'eligible',
        'audience_code', d.audience_code,
        'sleeve_length_code', case when d.decision_status = 'CONFIRMED'
          then d.mapped_sleeve_length_code end,
        'lower_length_code', case when d.decision_status = 'CONFIRMED'
          then d.mapped_lower_length_code end,
        'body_length_code', case when d.decision_status = 'CONFIRMED'
          then d.mapped_body_length_code end,
        'primary_source_signal_id', d.source_signal_id,
        'mapping_id', d.mapping_id, 'mapping_version', d.mapping_version,
        'mapping_checksum', d.mapping_checksum, 'reason', d.decision_reason,
        'resolver_version', 'fitmatch-vnext-resolver-v3',
        'input_fingerprint', encode(extensions.digest(concat_ws('|',
          d.source_code, d.source_product_key, d.audience_code,
          d.product_structure_code,
          d.comparison_unit ->> 'measurement_contract',
          coalesce(d.source_signal_id::text, '∅'),
          coalesce(d.mapping_checksum, '∅'),
          'fitmatch-vnext-resolver-v3'), 'sha256'), 'hex')
    )) from decision d
)
end;
$function$;

-- The existing authorization action remains the single production policy path.
-- This wrapper adds only the product-level unit gate before delegating to its
-- previous implementation; no scorer, classifier, or manual-cross rule lives
-- in the wrapper.
do $rename_authorization_v1$
begin
    if to_regprocedure(
        'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'
    ) is null then
        execute 'alter function fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb) '
             || 'rename to authorize_comparison_with_context_v1';
    end if;
end
$rename_authorization_v1$;

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
    unit_value jsonb;
begin
    unit_value := fitmatch_vnext.product_comparison_unit_decision(
        p_target_product_id
    );
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'decision', 'BLOCKED', 'allowed', false, 'mode', 'NONE',
            'reason', unit_value ->> 'reason',
            'comparison_unit', unit_value
        );
    end if;
    return fitmatch_vnext.authorize_comparison_with_context_v1(
        p_reference_closet_item_id, p_target_product_id,
        p_target_product_size_id, p_manual_explicit, p_effective_classification
    );
end
$function$;

-- Preserve the deployed service-only authority boundary for both the wrapper
-- and its retained implementation. CREATE OR REPLACE would otherwise leave
-- the new wrapper with PostgreSQL's default PUBLIC EXECUTE ACL.
revoke all on function fitmatch_vnext.authorize_comparison_with_context(
    uuid, uuid, uuid, boolean, jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_vnext.authorize_comparison_with_context(
    uuid, uuid, uuid, boolean, jsonb
) to service_role;
revoke all on function fitmatch_vnext.authorize_comparison_with_context_v1(
    uuid, uuid, uuid, boolean, jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_vnext.authorize_comparison_with_context_v1(
    uuid, uuid, uuid, boolean, jsonb
) to service_role;

do $rename_readiness_context_v1$
begin
    if to_regprocedure(
        'fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb)'
    ) is null then
        execute 'alter function fitmatch_vnext.product_readiness_with_context(uuid,jsonb) '
             || 'rename to product_readiness_with_context_v1';
    end if;
end
$rename_readiness_context_v1$;

create or replace function fitmatch_vnext.product_readiness_with_context(
    p_product_id uuid,
    p_effective_classification jsonb
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
    unit_value jsonb;
begin
    unit_value := fitmatch_vnext.product_comparison_unit_decision(p_product_id);
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'product_id', p_product_id,
            'ready', false,
            'status', case when unit_value ->> 'reason' in (
              'MIXED_GARMENT_SET','MULTIPLE_COMPONENT_MEASUREMENT_CONTRACT'
            ) then 'NOT_APPLICABLE' else 'CLASSIFICATION_REQUIRED' end,
            'reason', unit_value ->> 'reason',
            'comparison_unit', unit_value,
            'readiness_version', 'fitmatch-vnext-readiness-v3'
        );
    end if;
    return fitmatch_vnext.product_readiness_with_context_v1(
        p_product_id, p_effective_classification
    );
end
$function$;

revoke all on function fitmatch_vnext.product_readiness_with_context(
    uuid, jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness_with_context(
    uuid, jsonb
) to service_role;
revoke all on function fitmatch_vnext.product_readiness_with_context_v1(
    uuid, jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_vnext.product_readiness_with_context_v1(
    uuid, jsonb
) to service_role;

-- Some already-verified exact-product classifications predate the vNext
-- sleeve/body-axis contract. They remain valid server authority for the
-- garment type, but must never be promoted directly when a required axis is
-- absent. Build a small USER_EXPLICIT candidate set from independently
-- verified provider mappings instead. This is source/product agnostic and
-- never changes the global REVIEW_REQUIRED decision.
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
               p.id::text,
               p.input_fingerprint,
               p.evidence_fingerprint,
               p.resolver_version,
               template.classification_id::text,
               template.mapping_id::text,
               template.mapping_checksum,
               template.category_code,
               template.garment_type_code,
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

-- Preserve the existing bounded USER_EXPLICIT recovery protocol while
-- replacing its obsolete cardinality-only precondition. This migration first
-- verifies the deployed v1 body and then changes only the structure gate and
-- tuple validator to use the persisted comparison-unit contract.
do $recovery_comparison_unit_contract$
declare
    old_definition text;
    new_definition text;
begin
    old_definition := pg_get_functiondef(
        'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
    );
    if position(
        'elsif product_row.product_structure_code <> ''SINGLE'' then'
        in old_definition
    ) = 0
       or position(
        'PRODUCT_STRUCTURE_NOT_SINGLE'
        in old_definition
    ) = 0
       or position(
        'fitmatch_vnext.classification_tuple_validation('
        in old_definition
    ) = 0 then
        raise exception 'Unexpected classification_recovery_options preimage';
    end if;

    new_definition := replace(
        old_definition,
        'elsif product_row.product_structure_code <> ''SINGLE'' then',
        'elsif not coalesce((fitmatch_vnext.product_comparison_unit_decision('
        || 'product_row.id) ->> ''eligible'')::boolean, false) then'
    );
    new_definition := replace(
        new_definition,
        'PRODUCT_STRUCTURE_NOT_SINGLE',
        'PRODUCT_COMPARISON_UNIT_NOT_ELIGIBLE'
    );
    new_definition := replace(
        new_definition,
        'fitmatch_vnext.classification_tuple_validation('
        || E'\n                m.garment_type_code,'
        || E'\n                product_row.product_structure_code,'
        || E'\n                product_row.audience_code,',
        'fitmatch_vnext.comparison_unit_tuple_validation('
        || E'\n                m.garment_type_code,'
        || E'\n                product_row.product_structure_code,'
        || E'\n                fitmatch_vnext.product_comparison_unit_decision(product_row.id)'
        || E'\n                    ->> ''measurement_contract'','
        || E'\n                product_row.audience_code,'
    );
    new_definition := replace(
        new_definition,
        'fitmatch-vnext-recovery-candidates-v1',
        'fitmatch-vnext-recovery-candidates-v2-comparison-unit'
    );
    new_definition := replace(
        new_definition,
        '    if recoverability_value <> ''RECOVERABLE'' then',
        E'    if recoverability_value <> ''RECOVERABLE'' then\n'
        || E'        exact_fallback_value := fitmatch_vnext.'
        || E'exact_product_authority_recovery_options(product_row.id);\n'
        || E'        if exact_fallback_value ->> ''recoverability'' = '
        || E'''RECOVERABLE'' then\n'
        || E'            recoverability_value := ''RECOVERABLE'';\n'
        || E'            unrecoverable_reason_value := null;\n'
        || E'            candidates_value := exact_fallback_value -> '
        || E'''candidates'';\n'
        || E'            candidate_count_value := coalesce('
        || E'(exact_fallback_value ->> ''candidate_count'')::integer, 0);\n'
        || E'            candidate_set_hash_value := exact_fallback_value ->> '
        || E'''candidate_set_hash'';\n'
        || E'            fixed_facts_value := exact_fallback_value -> '
        || E'''fixed_facts'';\n'
        || E'            unknown_fields_value := exact_fallback_value -> '
        || E'''unknown_fields'';\n'
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
    if position('comparison_unit_tuple_validation' in new_definition) = 0
       or position('PRODUCT_COMPARISON_UNIT_NOT_ELIGIBLE' in new_definition) = 0
       or position('exact_product_authority_recovery_options' in new_definition) = 0
       or position('exact_fallback_value jsonb' in new_definition) = 0 then
        raise exception 'Unable to amend classification_recovery_options';
    end if;
    execute new_definition;
end
$recovery_comparison_unit_contract$;

create or replace function fitmatch_vnext.ingest_product_observation_v2(
    p_payload jsonb,
    p_actor_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    source_value text;
    product_key text;
    product_name_value text;
    audience_value text;
    structure_value text;
    structured_facts_value jsonb := '{}'::jsonb;
    effective_structured_facts_value jsonb := '{}'::jsonb;
    structure_state text;
    explicit_structure_value text;
    structure_present boolean := false;
    comparison_contract_state text;
    explicit_contract_value text;
    contract_present boolean := false;
    effective_contract_value text := 'ABSENT';
    comparison_contract_claim_rejected boolean := false;
    payload_measurement_count integer := 0;
    prior_structure_links jsonb := '[]'::jsonb;
    prior_structure_source text;
    prior_structure_evidence text;
    prior_contract_source text;
    prior_contract_evidence text;
    preserve_existing_structure boolean := false;
    promoted_count integer := 0;
    observed_value timestamptz;
    payload_fingerprint_value text;
    product_id_value uuid;
    receipt_id_value uuid;
    existing_receipt fitmatch_vnext.product_ingestion_receipts%rowtype;
    existing_product fitmatch_vnext.products%rowtype;
    signal_id_value uuid;
    variant_id_value uuid;
    size_id_value uuid;
    variant_value jsonb;
    size_value jsonb;
    measurement_value jsonb;
    signal_value jsonb;
    category_value text;
    category_index integer := 0;
    category_codes_value text[] := '{}'::text[];
    category_path_complete boolean := false;
    previous_category_signal_id uuid;
    current_category_signal_id uuid;
    observed_parent_signal_id uuid;
    category_signal_count integer;
    parser_value text;
    default_parser_value text;
    raw_key_value text;
    raw_code_value text;
    raw_label_value text;
    raw_value_value numeric;
    measurement_fingerprint_value text;
    availability_value text;
    valid_until_value timestamptz;
    classification_value jsonb;
    readiness_value jsonb;
    runtime_value jsonb;
    raw_measurement_count_value integer := 0;
    signal_order_value integer := 0;
begin
    if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'service_role is required for global ingestion';
    end if;
    if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
        raise exception 'Retailer observation payload must be a JSON object';
    end if;

    source_value := lower(btrim(p_payload ->> 'source'));
    product_key := btrim(p_payload ->> 'external_product_id');
    product_name_value := btrim(p_payload ->> 'product_name');
    if source_value is null or source_value = ''
       or product_key is null or product_key = ''
       or product_name_value is null or product_name_value = '' then
        raise exception 'source, external_product_id, and product_name are required';
    end if;
    if length(source_value) > 64 or length(product_key) > 256
       or length(product_name_value) > 1000 then
        raise exception 'Retailer observation identity exceeds contract limits';
    end if;
    if not exists (
        select 1 from fitmatch_vnext.sources s
        where s.source_code = source_value and s.is_active
    ) then
        raise exception 'Unsupported or inactive source';
    end if;

    begin
        observed_value := (p_payload ->> 'observed_at')::timestamptz;
    exception when others then
        raise exception 'observed_at must be an ISO-8601 timestamp';
    end;
    if observed_value is null or observed_value > now() + interval '5 minutes' then
        raise exception 'observed_at is required and cannot be in the future';
    end if;

    if jsonb_typeof(coalesce(p_payload -> 'variants', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_payload -> 'variants', '[]'::jsonb)) > 100 then
        raise exception 'variants must be an array with at most 100 entries';
    end if;
    if jsonb_typeof(coalesce(p_payload -> 'source_category_codes', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_payload -> 'source_category_codes', '[]'::jsonb)) > 32 then
        raise exception 'source_category_codes must be an array with at most 32 entries';
    end if;
    if jsonb_typeof(coalesce(p_payload -> 'classification_signals', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_payload -> 'classification_signals', '[]'::jsonb)) > 64 then
        raise exception 'classification_signals must be an array with at most 64 entries';
    end if;
    if jsonb_typeof(coalesce(p_payload -> 'raw_payload', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(p_payload -> 'structured_facts', '{}'::jsonb)) <> 'object' then
        raise exception 'raw_payload and structured_facts must be JSON objects';
    end if;
    select count(*)::integer into payload_measurement_count
    from jsonb_array_elements(coalesce(p_payload -> 'variants', '[]'::jsonb)) variant
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(variant.value -> 'sizes') = 'array'
            then variant.value -> 'sizes' else '[]'::jsonb end
    ) size
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(size.value -> 'measurements') = 'array'
            then size.value -> 'measurements' else '[]'::jsonb end
    ) measurement
    where jsonb_typeof(variant.value) = 'object'
      and jsonb_typeof(size.value) = 'object'
      and jsonb_typeof(measurement.value) = 'object';

    audience_value := upper(btrim(coalesce(p_payload ->> 'audience', 'UNKNOWN')));
    audience_value := case audience_value
        when 'M' then 'MEN' when 'MAN' then 'MEN' when 'MALE' then 'MEN'
        when 'W' then 'WOMEN' when 'WOMAN' then 'WOMEN' when 'FEMALE' then 'WOMEN'
        when 'U' then 'UNISEX' when 'COMMON' then 'UNISEX' when 'M,W' then 'UNISEX'
        when 'KID' then 'KIDS'
        when 'MEN' then 'MEN' when 'WOMEN' then 'WOMEN' when 'UNISEX' then 'UNISEX'
        when 'KIDS' then 'KIDS' when 'BABY' then 'BABY'
        else 'UNKNOWN' end;

    structured_facts_value := coalesce(p_payload -> 'structured_facts', '{}'::jsonb);
    structure_present := (p_payload ? 'product_structure')
        or (structured_facts_value ? 'product_structure');
    if (p_payload ? 'product_structure')
       and (structured_facts_value ? 'product_structure')
       and coalesce(nullif(upper(btrim(p_payload ->> 'product_structure')), ''), 'UNKNOWN')
            is distinct from coalesce(nullif(upper(btrim(
                structured_facts_value ->> 'product_structure'
            )), ''), 'UNKNOWN') then
        raise exception 'Conflicting product_structure values in retailer observation';
    end if;
    explicit_structure_value := case
        when p_payload ? 'product_structure' then upper(btrim(p_payload ->> 'product_structure'))
        when structured_facts_value ? 'product_structure'
            then upper(btrim(structured_facts_value ->> 'product_structure'))
        else null
    end;
    if explicit_structure_value not in ('SINGLE','SET','MULTIPACK','UNKNOWN')
       or explicit_structure_value is null or explicit_structure_value = '' then
        explicit_structure_value := 'UNKNOWN';
    end if;
    structure_state := case
        when not structure_present then 'MISSING'
        when explicit_structure_value = 'UNKNOWN' then 'EXPLICIT_UNKNOWN'
        else 'EXPLICIT_VALUE'
    end;

    contract_present := (p_payload ? 'comparison_measurement_contract')
        or (structured_facts_value ? 'comparison_measurement_contract');
    if (p_payload ? 'comparison_measurement_contract')
       and (structured_facts_value ? 'comparison_measurement_contract')
       and coalesce(nullif(upper(btrim(
              p_payload ->> 'comparison_measurement_contract'
           )), ''), 'UNKNOWN') is distinct from coalesce(nullif(upper(btrim(
              structured_facts_value ->> 'comparison_measurement_contract'
           )), ''), 'UNKNOWN') then
        raise exception 'Conflicting comparison_measurement_contract values in retailer observation';
    end if;
    explicit_contract_value := case
        when p_payload ? 'comparison_measurement_contract'
            then upper(btrim(p_payload ->> 'comparison_measurement_contract'))
        when structured_facts_value ? 'comparison_measurement_contract'
            then upper(btrim(structured_facts_value ->> 'comparison_measurement_contract'))
        else null
    end;
    if explicit_contract_value not in (
        'SINGLE_COHERENT','MULTIPLE_COMPONENT','ABSENT','UNKNOWN'
    ) or explicit_contract_value is null or explicit_contract_value = '' then
        explicit_contract_value := 'UNKNOWN';
    end if;
    comparison_contract_state := case
        when not contract_present then 'MISSING'
        when explicit_contract_value = 'UNKNOWN' then 'EXPLICIT_UNKNOWN'
        else 'EXPLICIT_VALUE'
    end;

    payload_fingerprint_value := encode(
        extensions.digest(p_payload::text, 'sha256'), 'hex'
    );
    perform pg_advisory_xact_lock(hashtextextended(
        source_value || ':' || product_key, 0
    ));

    select * into existing_receipt
    from fitmatch_vnext.product_ingestion_receipts r
    where r.source_code = source_value
      and r.source_product_key = product_key
      and r.payload_fingerprint = payload_fingerprint_value
    for update;
    if found then
        update fitmatch_vnext.product_ingestion_receipts
        set submission_count = submission_count + 1,
            last_submitted_at = now()
        where id = existing_receipt.id;
        runtime_value := fitmatch_vnext.get_product_runtime(source_value, product_key);
        return jsonb_build_object(
            'observation', jsonb_build_object(
                'observation_id', existing_receipt.id,
                'status', 'accepted',
                'raw_measurement_count', coalesce(
                    (existing_receipt.result_summary ->> 'raw_measurement_count')::integer, 0
                ),
                'idempotent', true,
                'payload_fingerprint', payload_fingerprint_value
            ),
            'processing', jsonb_build_object(
                'observation_id', existing_receipt.id,
                'status', lower(existing_receipt.processing_status),
                'product_id', existing_receipt.product_id,
                'idempotent', true
            ),
            'runtime', runtime_value
        );
    end if;

    select * into existing_product
    from fitmatch_vnext.products p
    where p.source_code = source_value and p.source_product_key = product_key
    for update;

    if found and observed_value < existing_product.last_seen_at then
        insert into fitmatch_vnext.product_ingestion_receipts (
            product_id, source_code, source_product_key, payload_fingerprint,
            retailer_facts, observed_at, actor_id_snapshot, processing_status,
            result_summary
        ) values (
            existing_product.id, source_value, product_key, payload_fingerprint_value,
            p_payload, observed_value, p_actor_id, 'IGNORED_STALE',
            jsonb_build_object('reason', 'Older than current product evidence',
                'raw_measurement_count', 0)
        ) returning id into receipt_id_value;
        runtime_value := fitmatch_vnext.get_product_runtime(source_value, product_key);
        return jsonb_build_object(
            'observation', jsonb_build_object(
                'observation_id', receipt_id_value, 'status', 'ignored_stale',
                'raw_measurement_count', 0, 'idempotent', false,
                'payload_fingerprint', payload_fingerprint_value
            ),
            'processing', jsonb_build_object(
                'observation_id', receipt_id_value, 'status', 'ignored_stale',
                'product_id', existing_product.id, 'idempotent', false
            ),
            'runtime', runtime_value
        );
    end if;

    -- MISSING is a statement about this receipt, not UNKNOWN evidence. Preserve
    -- the prior effective fact before the current signal projection is rebuilt.
    if existing_product.id is not null then
        if structure_state = 'MISSING'
           and existing_product.product_structure_code in ('SINGLE','SET','MULTIPACK') then
            structure_value := existing_product.product_structure_code;
            select coalesce(jsonb_agg(jsonb_build_object(
                'source_signal_id', pcs.source_signal_id,
                'is_primary', pcs.is_primary,
                'evidence_order', pcs.evidence_order,
                'observed_at', pcs.observed_at
            ) order by pcs.evidence_order, pcs.source_signal_id), '[]'::jsonb)
            into prior_structure_links
            from fitmatch_vnext.product_classification_signals pcs
            join fitmatch_vnext.source_classification_signals signal
              on signal.id = pcs.source_signal_id
            where pcs.product_id = existing_product.id
              and signal.signal_kind = 'PRODUCT_STRUCTURE'
              and upper(signal.external_key) = existing_product.product_structure_code;
            prior_structure_source := coalesce(
                existing_product.source_extra -> 'product_structure_fact' ->> 'source',
                existing_product.source_extra -> 'structured_facts' ->> 'product_structure_source'
            );
            prior_structure_evidence := coalesce(
                existing_product.source_extra -> 'product_structure_fact' ->> 'evidence',
                existing_product.source_extra -> 'structured_facts' ->> 'product_structure_evidence'
            );
            preserve_existing_structure := coalesce(
                jsonb_array_length(prior_structure_links) > 0
                or (
                    existing_product.source_extra -> 'product_structure_fact' ? 'value'
                    and prior_structure_source is not null
                    and prior_structure_evidence is not null
                )
                or (
                    existing_product.source_extra -> 'structured_facts' ? 'product_structure'
                    and prior_structure_source is not null
                    and prior_structure_evidence is not null
                ),
                false
            );
            -- A legacy/current column alone is not a retailer observation.
            -- Preserve only existing observed provenance; otherwise this
            -- MISSING receipt must not promote the column into new evidence.
            if not preserve_existing_structure then
                structure_value := 'UNKNOWN';
            end if;
        else
            structure_value := explicit_structure_value;
        end if;

        prior_contract_source := coalesce(
            existing_product.source_extra -> 'comparison_measurement_contract' ->> 'source',
            existing_product.source_extra -> 'structured_facts'
                ->> 'comparison_measurement_contract_source'
        );
        prior_contract_evidence := coalesce(
            existing_product.source_extra -> 'comparison_measurement_contract' ->> 'evidence',
            existing_product.source_extra -> 'structured_facts'
                ->> 'comparison_measurement_contract_evidence'
        );
        effective_contract_value := case
            when comparison_contract_state = 'MISSING' then coalesce(
                upper(existing_product.source_extra
                    -> 'comparison_measurement_contract' ->> 'effective_value'),
                upper(existing_product.source_extra -> 'structured_facts'
                    ->> 'comparison_measurement_contract'),
                'ABSENT'
            )
            else explicit_contract_value
        end;
    else
        structure_value := explicit_structure_value;
        effective_contract_value := case
            when comparison_contract_state = 'MISSING' then 'ABSENT'
            else explicit_contract_value
        end;
    end if;

    -- A client/parser may report its coherent-table observation, but the
    -- server only accepts SINGLE_COHERENT as effective readiness evidence
    -- when this same immutable payload contains actual provider measurement
    -- records. The receipt retains the original claim; the effective state is
    -- downgraded rather than fabricating a table that was not observed.
    if comparison_contract_state = 'EXPLICIT_VALUE'
       and explicit_contract_value = 'SINGLE_COHERENT'
       and payload_measurement_count = 0 then
        effective_contract_value := 'ABSENT';
        comparison_contract_claim_rejected := true;
    end if;

    effective_structured_facts_value := structured_facts_value;
    if comparison_contract_claim_rejected then
        effective_structured_facts_value := effective_structured_facts_value
            - 'comparison_measurement_contract'
            - 'comparison_measurement_contract_source'
            - 'comparison_measurement_contract_evidence';
    end if;
    if preserve_existing_structure then
        effective_structured_facts_value := effective_structured_facts_value
            || jsonb_strip_nulls(jsonb_build_object(
                'product_structure', lower(structure_value),
                'product_structure_source', prior_structure_source,
                'product_structure_evidence', prior_structure_evidence
            ));
    end if;
    if comparison_contract_state = 'MISSING'
       and effective_contract_value <> 'ABSENT' then
        effective_structured_facts_value := effective_structured_facts_value
            || jsonb_strip_nulls(jsonb_build_object(
                'comparison_measurement_contract', lower(effective_contract_value),
                'comparison_measurement_contract_source', prior_contract_source,
                'comparison_measurement_contract_evidence', prior_contract_evidence
            ));
    end if;

    if existing_product.id is null then
        insert into fitmatch_vnext.products (
            source_code, source_product_key, product_name, brand_name,
            canonical_url, image_url, audience_code, product_structure_code,
            classification_status, classification_source, source_status,
            source_extra, first_seen_at, last_seen_at, last_fetched_at
        ) values (
            source_value, product_key, product_name_value,
            nullif(btrim(coalesce(p_payload ->> 'brand_name',
                p_payload -> 'raw_payload' ->> 'brand_name')), ''),
            nullif(btrim(p_payload ->> 'canonical_url'), ''),
            nullif(btrim(p_payload ->> 'image_url'), ''),
            audience_value, structure_value, 'REVIEW_REQUIRED', 'BACKEND',
            case upper(btrim(coalesce(p_payload ->> 'source_status', 'UNKNOWN')))
                when 'ACTIVE' then 'ACTIVE' when 'SOLD_OUT' then 'SOLD_OUT'
                when 'DELETED' then 'DELETED' else 'UNKNOWN' end,
            jsonb_build_object(
                'latest_ingestion_fingerprint', payload_fingerprint_value,
                'latest_ingestion_observed_at', observed_value,
                'source_category_path', p_payload ->> 'source_category_path',
                'structured_facts', coalesce(p_payload -> 'structured_facts', '{}'::jsonb)
            ),
            observed_value, observed_value, observed_value
        ) returning id into product_id_value;
    else
        product_id_value := existing_product.id;
        update fitmatch_vnext.products
        set product_name = product_name_value,
            brand_name = coalesce(nullif(btrim(coalesce(p_payload ->> 'brand_name',
                p_payload -> 'raw_payload' ->> 'brand_name')), ''), brand_name),
            canonical_url = coalesce(nullif(btrim(p_payload ->> 'canonical_url'), ''), canonical_url),
            image_url = coalesce(nullif(btrim(p_payload ->> 'image_url'), ''), image_url),
            audience_code = audience_value,
            product_structure_code = structure_value,
            classification_status = 'REVIEW_REQUIRED',
            classification_source = 'BACKEND',
            garment_type_code = null,
            sleeve_length_code = null,
            lower_length_code = null,
            body_length_code = null,
            classified_at = null,
            primary_source_signal_id = null,
            classification_mapping_id = null,
            resolution_mode = null,
            resolver_version = null,
            input_fingerprint = null,
            evidence_fingerprint = null,
            classification_evidence = '{}'::jsonb,
            classification_reason = 'Awaiting deterministic replay after new retailer evidence',
            source_status = case upper(btrim(coalesce(p_payload ->> 'source_status', 'UNKNOWN')))
                when 'ACTIVE' then 'ACTIVE' when 'SOLD_OUT' then 'SOLD_OUT'
                when 'DELETED' then 'DELETED' else source_status end,
            source_extra = source_extra || jsonb_build_object(
                'latest_ingestion_fingerprint', payload_fingerprint_value,
                'latest_ingestion_observed_at', observed_value,
                'source_category_path', p_payload ->> 'source_category_path',
                'structured_facts', coalesce(p_payload -> 'structured_facts', '{}'::jsonb)
            ),
            last_seen_at = observed_value,
            last_fetched_at = observed_value
        where id = product_id_value;
    end if;

    -- Current effective state and immutable observation are separate. The raw
    -- receipt inserted below remains p_payload, including an absent key.
    update fitmatch_vnext.products product_row
    set source_extra = coalesce(product_row.source_extra, '{}'::jsonb)
        || jsonb_build_object(
            'structured_facts', effective_structured_facts_value,
            'product_structure_observation', jsonb_strip_nulls(jsonb_build_object(
                'state', structure_state,
                'observed_value', case when structure_state = 'MISSING'
                    then null else explicit_structure_value end,
                'effective_value', structure_value,
                'preserved_existing_fact', preserve_existing_structure,
                'observed_at', p_payload ->> 'observed_at'
            )),
            'comparison_measurement_contract', jsonb_strip_nulls(jsonb_build_object(
                'state', comparison_contract_state,
                'observed_value', case when comparison_contract_state = 'MISSING'
                    then null else explicit_contract_value end,
                'effective_value', effective_contract_value,
                'preserved_existing_fact', comparison_contract_state = 'MISSING'
                    and existing_product.id is not null
                    and effective_contract_value <> 'ABSENT',
                'source', case when comparison_contract_claim_rejected
                    then 'server_contract_validation'
                when comparison_contract_state = 'MISSING'
                    then prior_contract_source
                    else structured_facts_value ->> 'comparison_measurement_contract_source' end,
                'evidence', case when comparison_contract_claim_rejected
                    then 'single_coherent_claim_without_provider_measurement_records'
                when comparison_contract_state = 'MISSING'
                    then prior_contract_evidence
                    else structured_facts_value ->> 'comparison_measurement_contract_evidence' end,
                'observed_at', p_payload ->> 'observed_at'
            ))
        )
        || case when structure_state <> 'MISSING' then
            jsonb_build_object('product_structure_fact', jsonb_strip_nulls(
                jsonb_build_object(
                    'value', explicit_structure_value,
                    'source', structured_facts_value ->> 'product_structure_source',
                    'evidence', structured_facts_value ->> 'product_structure_evidence',
                    'observed_at', p_payload ->> 'observed_at'
                )
            ))
           else '{}'::jsonb end
    where product_row.id = product_id_value;

    insert into fitmatch_vnext.product_ingestion_receipts (
        product_id, source_code, source_product_key, payload_fingerprint,
        retailer_facts, observed_at, actor_id_snapshot, processing_status
    ) values (
        product_id_value, source_value, product_key, payload_fingerprint_value,
        p_payload, observed_value, p_actor_id, 'PROCESSING'
    ) returning id into receipt_id_value;

    insert into fitmatch_vnext.source_identifiers (
        source_code, entity_scope, product_id, identifier_type_code, identifier_value
    ) values (
        source_value, 'PRODUCT', product_id_value, 'source_product_key', product_key
    ) on conflict do nothing;

    delete from fitmatch_vnext.product_classification_signals
    where product_id = product_id_value;

    -- Product-exact is observed evidence. It only classifies when an existing
    -- active, verified mapping grants that exact signal authority.
    select s.id into signal_id_value
    from fitmatch_vnext.source_classification_signals s
    where s.source_code = source_value and s.signal_kind = 'PRODUCT_EXACT'
      and s.external_key = product_key
      and s.audience_code in (audience_value, 'ANY')
    order by (s.audience_code = audience_value) desc, s.id
    limit 1;
    if signal_id_value is null then
        insert into fitmatch_vnext.source_classification_signals (
            source_code, signal_kind, external_key, external_id, audience_code,
            signal_name, signal_path, is_active, first_seen_at, last_seen_at
        ) values (
            source_value, 'PRODUCT_EXACT', product_key, product_key, audience_value,
            product_name_value, 'product:' || product_key, true,
            observed_value, observed_value
        ) returning id into signal_id_value;
    else
        update fitmatch_vnext.source_classification_signals
        set last_seen_at = greatest(last_seen_at, observed_value),
            signal_name = coalesce(signal_name, product_name_value),
            signal_path = coalesce(signal_path, 'product:' || product_key)
        where id = signal_id_value;
    end if;
    insert into fitmatch_vnext.product_classification_signals (
        product_id, source_signal_id, is_primary, evidence_order, observed_at
    ) values (product_id_value, signal_id_value, false, signal_order_value, observed_value);

    if preserve_existing_structure and jsonb_array_length(prior_structure_links) > 0 then
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        )
        select product_id_value,
               (link ->> 'source_signal_id')::uuid,
               coalesce((link ->> 'is_primary')::boolean, false),
               coalesce((link ->> 'evidence_order')::integer, 1),
               (link ->> 'observed_at')::timestamptz
        from jsonb_array_elements(prior_structure_links) link
        on conflict (product_id, source_signal_id) do update
        set is_primary = excluded.is_primary,
            evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
        select coalesce(max((link ->> 'evidence_order')::integer), 0)
        into signal_order_value
        from jsonb_array_elements(prior_structure_links) link;
    end if;

    if structure_state = 'EXPLICIT_VALUE'
       and not preserve_existing_structure
       and structure_value <> 'UNKNOWN' then
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value and s.signal_kind = 'PRODUCT_STRUCTURE'
          and s.external_key = structure_value
          and s.audience_code in (audience_value, 'ANY')
        order by (s.audience_code = audience_value) desc, s.id
        limit 1;
        if signal_id_value is null then
            insert into fitmatch_vnext.source_classification_signals (
                source_code, signal_kind, external_key, external_id, audience_code,
                signal_name, signal_path, is_active, first_seen_at, last_seen_at
            ) values (
                source_value, 'PRODUCT_STRUCTURE', structure_value, structure_value,
                audience_value, structure_value, 'structure:' || structure_value,
                true, observed_value, observed_value
            ) returning id into signal_id_value;
        else
            update fitmatch_vnext.source_classification_signals
            set last_seen_at = greatest(last_seen_at, observed_value)
            where id = signal_id_value;
        end if;
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        ) values (product_id_value, signal_id_value, false,
            signal_order_value, observed_value)
        on conflict (product_id, source_signal_id) do update
        set evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
    end if;

    for category_value in
        select btrim(value)
        from jsonb_array_elements_text(
            coalesce(p_payload -> 'source_category_codes', '[]'::jsonb)
        ) with ordinality c(value, ordinal)
        where btrim(value) <> ''
        order by ordinal
    loop
        category_index := category_index + 1;
        category_codes_value := array_append(category_codes_value, category_value);
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value and s.signal_kind = 'CATEGORY'
          and s.external_key = category_value
          and (
            s.audience_code = audience_value
            or (
                s.audience_code = 'ANY'
                and not (
                    source_value = 'uniqlo'
                    and structured_facts_value ->> 'source_category_path_completeness' = 'complete'
                    and structured_facts_value ->> 'source_category_path_source' = 'uniqlo_pdp_breadcrumbs'
                )
            )
          )
        order by (s.audience_code = audience_value) desc, s.id
        limit 1;
        if signal_id_value is null then
            insert into fitmatch_vnext.source_classification_signals (
                source_code, signal_kind, external_key, external_id, audience_code,
                signal_name, signal_path, is_active, first_seen_at, last_seen_at
            ) values (
                source_value, 'CATEGORY', category_value, category_value, audience_value,
                null, nullif(btrim(p_payload ->> 'source_category_path'), ''),
                true, observed_value, observed_value
            ) returning id into signal_id_value;
        else
            update fitmatch_vnext.source_classification_signals
            set last_seen_at = greatest(last_seen_at, observed_value),
                signal_path = coalesce(signal_path,
                    nullif(btrim(p_payload ->> 'source_category_path'), ''))
            where id = signal_id_value;
        end if;
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        ) values (product_id_value, signal_id_value, false,
            signal_order_value, observed_value)
        on conflict (product_id, source_signal_id) do update
        set evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
    end loop;

    -- A category hierarchy is authority evidence only when the selected
    -- UNIQLO PDP supplied the complete ordered breadcrumb marker. This links
    -- exactly that immutable path, never a leaf-only or guessed hierarchy.
    category_path_complete := source_value = 'uniqlo'
        and structured_facts_value ->> 'source_category_path_completeness' = 'complete'
        and structured_facts_value ->> 'source_category_path_source' = 'uniqlo_pdp_breadcrumbs'
        and audience_value in ('MEN','WOMEN','UNISEX')
        and cardinality(category_codes_value) > 0
        and cardinality(category_codes_value) = (
            select count(distinct code) from unnest(category_codes_value) code
        );
    if category_path_complete then
        previous_category_signal_id := null;
        foreach category_value in array category_codes_value
        loop
            select count(*) into category_signal_count
            from fitmatch_vnext.source_classification_signals signal
            where signal.source_code = 'uniqlo'
              and signal.signal_kind = 'CATEGORY'
              and signal.external_key = category_value
              and signal.audience_code = audience_value
              and signal.is_active;
            if category_signal_count <> 1 then
                category_path_complete := false;
                exit;
            end if;

            select signal.id, signal.parent_signal_id
            into current_category_signal_id, observed_parent_signal_id
            from fitmatch_vnext.source_classification_signals signal
            where signal.source_code = 'uniqlo'
              and signal.signal_kind = 'CATEGORY'
              and signal.external_key = category_value
              and signal.audience_code = audience_value
              and signal.is_active;

            if previous_category_signal_id is null then
                if observed_parent_signal_id is not null then
                    category_path_complete := false;
                    exit;
                end if;
            elsif observed_parent_signal_id is null then
                update fitmatch_vnext.source_classification_signals
                set parent_signal_id = previous_category_signal_id
                where id = current_category_signal_id
                  and parent_signal_id is null;
            elsif observed_parent_signal_id is distinct from previous_category_signal_id then
                category_path_complete := false;
                exit;
            end if;
            previous_category_signal_id := current_category_signal_id;
        end loop;
    end if;

    for signal_value in
        select value from jsonb_array_elements(
            coalesce(p_payload -> 'classification_signals', '[]'::jsonb)
        )
    loop
        if jsonb_typeof(signal_value) <> 'object'
           or upper(btrim(signal_value ->> 'kind')) not in (
               'PRODUCT_EXACT','PRODUCT_STRUCTURE','PRODUCT_TYPE',
               'SUBFAMILY','FAMILY','CATEGORY','SECTION','SIZE_TYPE'
           )
           or nullif(btrim(coalesce(signal_value ->> 'external_key',
                signal_value ->> 'key')), '') is null then
            raise exception 'Invalid explicit classification signal';
        end if;
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value
          and s.signal_kind = upper(btrim(signal_value ->> 'kind'))
          and s.external_key = btrim(coalesce(signal_value ->> 'external_key',
                signal_value ->> 'key'))
          and s.audience_code in (audience_value, 'ANY')
        order by (s.audience_code = audience_value) desc, s.id
        limit 1;
        if signal_id_value is null then
            insert into fitmatch_vnext.source_classification_signals (
                source_code, signal_kind, external_key, external_id, audience_code,
                signal_name, signal_path, is_active, first_seen_at, last_seen_at
            ) values (
                source_value, upper(btrim(signal_value ->> 'kind')),
                btrim(coalesce(signal_value ->> 'external_key', signal_value ->> 'key')),
                nullif(btrim(signal_value ->> 'external_id'), ''), audience_value,
                nullif(btrim(signal_value ->> 'name'), ''),
                nullif(btrim(signal_value ->> 'path'), ''), true,
                observed_value, observed_value
            ) returning id into signal_id_value;
        else
            update fitmatch_vnext.source_classification_signals
            set last_seen_at = greatest(last_seen_at, observed_value),
                signal_name = coalesce(signal_name,
                    nullif(btrim(signal_value ->> 'name'), '')),
                signal_path = coalesce(signal_path,
                    nullif(btrim(signal_value ->> 'path'), ''))
            where id = signal_id_value;
        end if;
        insert into fitmatch_vnext.product_classification_signals (
            product_id, source_signal_id, is_primary, evidence_order, observed_at
        ) values (product_id_value, signal_id_value, false,
            signal_order_value, observed_value)
        on conflict (product_id, source_signal_id) do update
        set evidence_order = excluded.evidence_order,
            observed_at = excluded.observed_at;
    end loop;

    select case when count(distinct a.parser_code) = 1 then min(a.parser_code) end
    into default_parser_value
    from fitmatch_vnext.source_measurement_aliases a
    where a.source_code = source_value and a.is_active and a.is_verified;

    if exists (
        select 1
        from jsonb_array_elements(coalesce(p_payload -> 'variants', '[]'::jsonb)) v
        group by btrim(v ->> 'external_variant_id')
        having btrim(v ->> 'external_variant_id') is null
            or btrim(v ->> 'external_variant_id') = '' or count(*) > 1
    ) then
        raise exception 'Variant identities must be non-empty and unique';
    end if;

    for variant_value in
        select value from jsonb_array_elements(
            coalesce(p_payload -> 'variants', '[]'::jsonb)
        )
    loop
        if jsonb_typeof(variant_value) <> 'object'
           or jsonb_typeof(coalesce(variant_value -> 'sizes', '[]'::jsonb)) <> 'array'
           or jsonb_array_length(coalesce(variant_value -> 'sizes', '[]'::jsonb)) > 200 then
            raise exception 'Each variant must contain a sizes array of at most 200 entries';
        end if;

        insert into fitmatch_vnext.product_variants (
            product_id, source_variant_key, variant_label, color_code, color_name,
            image_url, availability_status, sort_order, last_seen_at
        ) values (
            product_id_value, btrim(variant_value ->> 'external_variant_id'),
            nullif(btrim(variant_value ->> 'variant_name'), ''),
            nullif(btrim(variant_value ->> 'color_code'), ''),
            nullif(btrim(variant_value ->> 'color_name'), ''),
            nullif(btrim(variant_value ->> 'image_url'), ''), 'UNKNOWN',
            coalesce((variant_value ->> 'display_order')::integer, 0), observed_value
        )
        on conflict (product_id, source_variant_key) do update
        set variant_label = coalesce(excluded.variant_label,
                fitmatch_vnext.product_variants.variant_label),
            color_code = coalesce(excluded.color_code,
                fitmatch_vnext.product_variants.color_code),
            color_name = coalesce(excluded.color_name,
                fitmatch_vnext.product_variants.color_name),
            image_url = coalesce(excluded.image_url,
                fitmatch_vnext.product_variants.image_url),
            last_seen_at = greatest(fitmatch_vnext.product_variants.last_seen_at,
                excluded.last_seen_at)
        returning id into variant_id_value;

        insert into fitmatch_vnext.source_identifiers (
            source_code, entity_scope, variant_id, identifier_type_code, identifier_value
        ) values (
            source_value, 'VARIANT', variant_id_value,
            'source_variant_key', btrim(variant_value ->> 'external_variant_id')
        ) on conflict do nothing;

        if exists (
            select 1
            from jsonb_array_elements(coalesce(variant_value -> 'sizes', '[]'::jsonb)) s
            group by btrim(s ->> 'size_identity')
            having btrim(s ->> 'size_identity') is null
                or btrim(s ->> 'size_identity') = '' or count(*) > 1
        ) then
            raise exception 'Size identities must be non-empty and unique within a variant';
        end if;

        for size_value in
            select value from jsonb_array_elements(
                coalesce(variant_value -> 'sizes', '[]'::jsonb)
            )
        loop
            if jsonb_typeof(size_value) <> 'object'
               or nullif(btrim(size_value ->> 'size_label'), '') is null
               or jsonb_typeof(coalesce(size_value -> 'measurements', '[]'::jsonb)) <> 'array'
               or jsonb_array_length(coalesce(size_value -> 'measurements', '[]'::jsonb)) > 100 then
                raise exception 'Each size needs a label and at most 100 measurements';
            end if;

            insert into fitmatch_vnext.product_sizes (
                variant_id, source_size_key, size_label, normalized_size_label,
                availability_status, sort_order, last_seen_at
            ) values (
                variant_id_value, btrim(size_value ->> 'size_identity'),
                btrim(size_value ->> 'size_label'),
                nullif(btrim(size_value ->> 'normalized_size_label'), ''),
                'UNKNOWN', coalesce((size_value ->> 'display_order')::integer, 0),
                observed_value
            )
            on conflict (variant_id, source_size_key) do update
            set size_label = excluded.size_label,
                normalized_size_label = coalesce(excluded.normalized_size_label,
                    fitmatch_vnext.product_sizes.normalized_size_label),
                sort_order = excluded.sort_order,
                last_seen_at = greatest(fitmatch_vnext.product_sizes.last_seen_at,
                    excluded.last_seen_at)
            returning id into size_id_value;

            insert into fitmatch_vnext.source_identifiers (
                source_code, entity_scope, product_size_id,
                identifier_type_code, identifier_value
            ) values (
                source_value, 'SIZE', size_id_value,
                'source_size_key', btrim(size_value ->> 'size_identity')
            ) on conflict do nothing;

            update fitmatch_vnext.product_size_measurements
            set is_current = false
            where product_size_id = size_id_value and is_current;

            if exists (
                select 1
                from jsonb_array_elements(
                    coalesce(size_value -> 'measurements', '[]'::jsonb)
                ) m
                group by btrim(m ->> 'measurement_identity')
                having btrim(m ->> 'measurement_identity') is null
                    or btrim(m ->> 'measurement_identity') = '' or count(*) > 1
            ) then
                raise exception 'Measurement identities must be non-empty and unique within a size';
            end if;

            for measurement_value in
                select value from jsonb_array_elements(
                    coalesce(size_value -> 'measurements', '[]'::jsonb)
                )
            loop
                if jsonb_typeof(measurement_value) <> 'object' then
                    raise exception 'Measurement evidence must be a JSON object';
                end if;
                raw_key_value := btrim(measurement_value ->> 'measurement_identity');
                raw_code_value := nullif(btrim(measurement_value ->> 'raw_code'), '');
                raw_label_value := nullif(btrim(measurement_value ->> 'raw_label'), '');
                begin
                    raw_value_value := (measurement_value ->> 'raw_value')::numeric;
                exception when others then
                    raise exception 'raw_value must be numeric';
                end;
                if raw_value_value is null or raw_value_value <= 0
                   or (raw_code_value is null and raw_label_value is null) then
                    raise exception 'Measurement requires a positive value and code or label';
                end if;

                parser_value := coalesce(
                    nullif(btrim(measurement_value ->> 'parser_code'), ''),
                    nullif(btrim(measurement_value -> 'evidence' ->> 'parser_code'), ''),
                    nullif(btrim(size_value ->> 'parser_code'), ''),
                    nullif(btrim(variant_value ->> 'parser_code'), ''),
                    nullif(btrim(p_payload -> 'structured_facts' ->> 'measurement_parser_code'), ''),
                    (
                        select case when count(distinct alias.parser_code) = 1
                            then min(alias.parser_code) end
                        from fitmatch_vnext.source_measurement_aliases alias
                        where alias.source_code = source_value
                          and alias.raw_code = raw_code_value
                          and alias.is_active and alias.is_verified
                    ),
                    default_parser_value,
                    'ingestion_unmapped'
                );
                measurement_fingerprint_value := encode(extensions.digest(
                    concat_ws('|', payload_fingerprint_value, variant_id_value::text,
                        size_id_value::text, measurement_value::text), 'sha256'
                ), 'hex');

                insert into fitmatch_vnext.product_size_measurements (
                    product_size_id, parser_code, raw_measurement_key, raw_code,
                    raw_label, raw_value, raw_unit_code, observed_at,
                    evidence_payload, evidence_fingerprint, is_current
                ) values (
                    size_id_value, parser_value, raw_key_value, raw_code_value,
                    raw_label_value, raw_value_value,
                    coalesce(nullif(btrim(measurement_value ->> 'raw_unit'), ''), 'cm'),
                    observed_value,
                    jsonb_build_object(
                        'ingestion_receipt_id', receipt_id_value,
                        'retailer_evidence', coalesce(measurement_value -> 'evidence', '{}'::jsonb),
                        'raw_representation', measurement_value ->> 'raw_representation'
                    ),
                    measurement_fingerprint_value, true
                )
                on conflict (product_size_id, parser_code, raw_measurement_key)
                do update set
                    raw_code = excluded.raw_code,
                    raw_label = excluded.raw_label,
                    raw_value = excluded.raw_value,
                    raw_unit_code = excluded.raw_unit_code,
                    observed_at = excluded.observed_at,
                    evidence_payload = excluded.evidence_payload,
                    evidence_fingerprint = excluded.evidence_fingerprint,
                    is_current = true;
                raw_measurement_count_value := raw_measurement_count_value + 1;
            end loop;

            availability_value := upper(btrim(coalesce(
                size_value ->> 'availability_status', size_value ->> 'stock_status', 'UNKNOWN'
            )));
            availability_value := case availability_value
                when 'AVAILABLE' then 'AVAILABLE' when 'IN_STOCK' then 'AVAILABLE'
                when 'SOLD_OUT' then 'SOLD_OUT' when 'OUT_OF_STOCK' then 'SOLD_OUT'
                else 'UNKNOWN' end;
            begin
                valid_until_value := nullif(btrim(size_value ->> 'valid_until'), '')::timestamptz;
            exception when others then
                raise exception 'Size valid_until must be an ISO-8601 timestamp';
            end;
            if valid_until_value is null and availability_value <> 'UNKNOWN' then
                valid_until_value := observed_value + interval '24 hours';
            end if;
            perform fitmatch_vnext.record_size_availability(
                size_id_value, availability_value, 'RETAILER_OBSERVATION',
                jsonb_build_object(
                    'ingestion_receipt_id', receipt_id_value,
                    'payload_fingerprint', payload_fingerprint_value,
                    'source_variant_key', variant_value ->> 'external_variant_id',
                    'source_size_key', size_value ->> 'size_identity',
                    'retailer_stock_status', size_value ->> 'stock_status'
                ),
                observed_value, valid_until_value
            );
        end loop;
    end loop;

    -- The current receipt becomes hierarchy evidence only after all of its
    -- raw measurements and category links have been accepted. Transactional
    -- execution keeps this intermediate status invisible outside the ingress.
    if category_path_complete then
        update fitmatch_vnext.product_ingestion_receipts
        set processing_status = 'PROCESSED'
        where id = receipt_id_value;

        category_value := category_codes_value[cardinality(category_codes_value)];
        perform fitmatch_vnext.revalidate_uniqlo_auto_promoted_mappings(category_value);
        select signal.id into signal_id_value
        from fitmatch_vnext.source_classification_signals signal
        where signal.source_code = 'uniqlo'
          and signal.signal_kind = 'CATEGORY'
          and signal.external_key = category_value
          and signal.audience_code = audience_value
          and signal.is_active
        limit 1;
        if signal_id_value is not null
           and fitmatch_vnext.uniqlo_category_parent_chain_safe(signal_id_value) then
            promoted_count :=
                fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(
                    signal_id_value
                );
        end if;
    end if;

    classification_value := fitmatch_vnext.resolve_product_classification(
        source_value, product_key, true
    );
    update fitmatch_vnext.product_classification_signals
    set is_primary = coalesce(source_signal_id =
        (classification_value ->> 'primary_source_signal_id')::uuid, false)
    where product_id = product_id_value;

    readiness_value := fitmatch_vnext.product_readiness(product_id_value);
    update fitmatch_vnext.product_ingestion_receipts
    set processing_status = 'PROCESSED',
        result_summary = jsonb_build_object(
            'raw_measurement_count', raw_measurement_count_value,
            'classification', classification_value,
            'readiness', readiness_value,
            'structure_contract', jsonb_build_object(
                'state', structure_state,
                'effective_value', structure_value,
                'preserved_existing_fact', preserve_existing_structure
            ),
            'comparison_unit_contract', jsonb_build_object(
                'state', comparison_contract_state,
                'effective_value', effective_contract_value,
                'claim_rejected', comparison_contract_claim_rejected,
                'uniqlo_audience_mapping_promoted', promoted_count
            )
        )
    where id = receipt_id_value;

    runtime_value := fitmatch_vnext.get_product_runtime(source_value, product_key);
    return jsonb_build_object(
        'observation', jsonb_build_object(
            'observation_id', receipt_id_value,
            'status', 'accepted',
            'raw_measurement_count', raw_measurement_count_value,
            'idempotent', false,
            'payload_fingerprint', payload_fingerprint_value
        ),
        'processing', jsonb_build_object(
            'observation_id', receipt_id_value,
            'status', 'processed',
            'product_id', product_id_value,
            'idempotent', false
        ),
        'classification', classification_value,
        'readiness', readiness_value,
        'runtime', runtime_value,
        'structure_contract', jsonb_build_object(
            'state', structure_state,
            'effective_value', structure_value,
            'preserved_existing_fact', preserve_existing_structure
        ),
        'comparison_unit_contract', jsonb_build_object(
            'state', comparison_contract_state,
            'effective_value', effective_contract_value,
            'claim_rejected', comparison_contract_claim_rejected,
            'uniqlo_audience_mapping_promoted', promoted_count
        )
    );
end
$function$;

create or replace function fitmatch_vnext.ingest_product_observation(
    p_payload jsonb,
    p_actor_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
    return fitmatch_vnext.ingest_product_observation_v2(p_payload, p_actor_id);
end
$function$;

revoke all on function fitmatch_vnext.ingest_product_observation(jsonb,uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.ingest_product_observation(jsonb,uuid)
    to service_role;
revoke all on function fitmatch_vnext.ingest_product_observation_v1(jsonb,uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.ingest_product_observation_v1(jsonb,uuid)
    to service_role;
revoke all on function fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)
    to service_role;

-- Preserve the existing public PostgREST transport. Its sole responsibility is
-- authentication and dispatch to the public production ingress action.
create or replace function public.fitmatch_vnext_ingest_product_observation(
    p_payload jsonb,
    p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
        raise exception 'Service role required';
    end if;
    return fitmatch_vnext.ingest_product_observation(p_payload, p_actor_id);
end
$function$;
revoke all on function public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)
    from public, anon, authenticated;
grant execute on function public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)
    to service_role;

-- Only immutable, complete official paths may add audience-scoped authority.
-- A unique DIRECT tuple may be copied as DIRECT; a unanimously
-- PRODUCT_REQUIRED peer set may copy only that recovery envelope with no
-- semantic tuple. No parent pointer alone is proof and no ANY mapping is made.
do $backfill_complete_uniqlo_authority$
declare
    signal_row record;
begin
    for signal_row in
        select s.id from fitmatch_vnext.source_classification_signals s
        where s.source_code = 'uniqlo'
          and s.signal_kind = 'CATEGORY'
          and s.is_active
          and s.audience_code in ('MEN','WOMEN','UNISEX')
        order by s.id
    loop
        perform fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(
            signal_row.id
        );
    end loop;
end
$backfill_complete_uniqlo_authority$;

do $reclassify_safe_promotions$
declare
    candidate record;
begin
    perform set_config('request.jwt.claim.role', 'service_role', true);
    for candidate in
        select p.source_code, p.source_product_key
        from fitmatch_vnext.products p
        where p.source_code = 'uniqlo'
          and p.classification_status = 'REVIEW_REQUIRED'
          and coalesce((
            fitmatch_vnext.product_comparison_unit_decision(p.id) ->> 'eligible'
          )::boolean, false)
        order by p.source_code, p.source_product_key
    loop
        perform fitmatch_vnext.resolve_product_classification(
            candidate.source_code, candidate.source_product_key, true
        );
    end loop;
end
$reclassify_safe_promotions$;

update fitmatch_vnext.comparison_policies cp
set audience_policy_code = 'ADULT_ANY',
    policy_version = 'vnext-policy-20260902-adult-any-v1'
where cp.is_active
  and cp.policy_code = any(array[
    'anorak','base_layer_top','blazer','blouson','bodysuit_top',
    'cardigan','coat','dress','fleece_jacket','homewear_bottom',
    'homewear_top','hoodie','jacket','knit_sweater','knit_vest',
    'leggings','ma1','mouton','outer_vest','polo_shirt',
    'puffer_jacket','puffer_vest','shirt_blouse','skirt',
    'sleeveless_tshirt','sports_top','standard_pants','sweatshirt',
    'tank_top','tshirt','windbreaker','zip_hoodie'
  ]::text[]);

update fitmatch_vnext.comparison_policies cp
set policy_checksum = encode(extensions.digest(concat_ws('|', cp.policy_code,
    cp.min_common_measurements::text, cp.required_any_min::text,
    cp.audience_policy_code, cp.sleeve_mismatch_policy,
    cp.lower_length_mismatch_policy, cp.body_length_mismatch_policy,
    cp.allow_manual_extended::text, cp.sleeve_mismatch_excluded_codes::text,
    cp.lower_mismatch_excluded_codes::text, cp.body_mismatch_excluded_codes::text,
    cp.policy_version, cp.is_active::text), 'sha256'), 'hex')
where cp.is_active and cp.audience_policy_code = 'ADULT_ANY';

do $postflight$
begin
    if (select count(*) from fitmatch_vnext.comparison_policies
        where is_active and audience_policy_code = 'ADULT_ANY') <> 32 then
        raise exception 'Expected exactly 32 audited ADULT_ANY policies';
    end if;
    if (select count(*) from fitmatch_vnext.comparison_policies
        where is_active and policy_code = any(array[
            'men_briefs','men_trunks','men_undershirt','women_bra',
            'women_camisole','women_panty','women_slip'
        ]::text[]) and audience_policy_code = 'SAME_OR_UNISEX') <> 7 then
        raise exception 'Anatomy-specific policy audience gate changed';
    end if;
    if exists (
        select 1
        from fitmatch_vnext.classification_signal_mappings m
        join fitmatch_vnext.source_classification_signals s
          on s.id = m.source_signal_id
        where m.mapping_version = 'vnext-uniqlo-complete-path-20260902-v3'
          and (
            s.source_code <> 'uniqlo'
            or s.signal_kind <> 'CATEGORY'
            or m.resolution_mode <> 'DIRECT'
            or not m.is_active or not m.is_verified
            or not fitmatch_vnext.uniqlo_category_parent_chain_safe(s.id)
            or fitmatch_vnext.uniqlo_complete_observed_category_path(s.id) is null
          )
    ) then
        raise exception 'UNIQLO complete-path mapping safety postflight failed';
    end if;
    if has_function_privilege('public',
           'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('anon',
           'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('authenticated',
           'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or not has_function_privilege('service_role',
           'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('public',
           'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('anon',
           'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('authenticated',
           'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or not has_function_privilege('service_role',
           'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('public',
           'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('anon',
           'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('authenticated',
           'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or not has_function_privilege('service_role',
           'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('public',
           'fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('anon',
           'fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or has_function_privilege('authenticated',
           'fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb)'::regprocedure,
           'EXECUTE')
       or not has_function_privilege('service_role',
           'fitmatch_vnext.product_readiness_with_context_v1(uuid,jsonb)'::regprocedure,
           'EXECUTE') then
        raise exception 'Live-retailer wrapper ACL postflight failed';
    end if;
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
       )) = 0
       or position('fitmatch-vnext-recovery-candidates-v3-exact-product'
           in pg_get_functiondef(
               'fitmatch_vnext.classification_recovery_options(uuid)'::regprocedure
           )) = 0 then
        raise exception 'Exact-product bounded recovery postflight failed';
    end if;
    if not (select p.prosecdef from pg_proc p
            where p.oid = 'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure)
       or (select p.prosecdef from pg_proc p
           where p.oid = 'fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure) then
        raise exception 'Live-retailer wrapper security mode postflight failed';
    end if;
end
$postflight$;

commit;
