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
    recovery_definition text;
begin
    if to_regclass('fitmatch_vnext.products') is null
       or to_regclass('fitmatch_vnext.product_ingestion_receipts') is null
       or to_regclass('fitmatch_vnext.source_classification_signals') is null
       or to_regclass('fitmatch_vnext.classification_signal_mappings') is null
       or to_regclass('fitmatch_vnext.comparison_policies') is null then
        raise exception 'Required live-retailer contract tables are missing';
    end if;
    if to_regprocedure('fitmatch_vnext.ingest_product_observation(jsonb,uuid)') is null
       or to_regprocedure('fitmatch_vnext.resolve_product_classification(text,text,boolean)') is null
       or to_regprocedure('fitmatch_vnext.classification_decision(text,text)') is null
       or to_regprocedure('fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)') is null
       or to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)') is null then
        raise exception 'Expected vNext ingress/classification contract is missing';
    end if;
    ingress_definition := pg_get_functiondef(
        to_regprocedure('fitmatch_vnext.ingest_product_observation(jsonb,uuid)')
    );
    if position('product_ingestion_receipts' in ingress_definition) = 0
       or position('Awaiting deterministic replay after new retailer evidence'
                   in ingress_definition) = 0 then
        raise exception 'Unexpected ingest_product_observation preimage';
    end if;
    recovery_definition := pg_get_functiondef(
        to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)')
    );
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
             when p.structure_code = 'SINGLE' then true
             when p.structure_code in ('MULTIPACK','UNKNOWN')
                and p.measurement_contract = 'SINGLE_COHERENT' then true
             else false
           end eligible,
           case
             when p.structure_code = 'SET' then 'MIXED_GARMENT_SET'
             when p.measurement_contract = 'MULTIPLE_COMPONENT'
                then 'MULTIPLE_COMPONENT_MEASUREMENT_CONTRACT'
             when p.structure_code = 'SINGLE' then 'EXPLICIT_SINGLE_STRUCTURE'
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
          upper(coalesce(p_product_structure_code, 'UNKNOWN')) = 'SINGLE'
          or (
             upper(coalesce(p_product_structure_code, 'UNKNOWN'))
                 in ('MULTIPACK','UNKNOWN')
             and upper(coalesce(p_measurement_contract, 'ABSENT'))
                 = 'SINGLE_COHERENT'
          )
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
           or (structure_code <> 'SINGLE'
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
    cross join lateral jsonb_array_elements_text(
      coalesce(r.retailer_facts -> 'source_category_codes', '[]'::jsonb)
    ) with ordinality code(value, ordinality)
    where btrim(code.value) <> ''
    group by r.id, t.external_key
), valid_paths as (
    select path from receipt_paths
    where cardinality(path) >= 3
      and path[cardinality(path)] = external_key
      and cardinality(path) = (
          select count(distinct code) from unnest(path) code
      )
)
select path from valid_paths
where (select count(distinct path) from valid_paths) = 1
limit 1;
$function$;

create or replace function fitmatch_vnext.uniqlo_category_parent_chain_safe(
    p_signal_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $function$
with recursive walk as (
    select s.id, s.parent_signal_id, 0 depth, array[s.id] visited, false cycle
    from fitmatch_vnext.source_classification_signals s
    where s.id = p_signal_id
    union all
    select parent.id, parent.parent_signal_id, w.depth + 1,
           w.visited || parent.id, parent.id = any(w.visited)
    from walk w
    join fitmatch_vnext.source_classification_signals parent
      on parent.id = w.parent_signal_id
    where w.parent_signal_id is not null
      and w.depth < 16
      and not w.cycle
)
select exists (select 1 from walk)
   and not exists (
       select 1 from walk w
       where w.cycle
          or (w.depth >= 16 and w.parent_signal_id is not null)
          or (w.parent_signal_id is not null and not exists (
              select 1 from fitmatch_vnext.source_classification_signals parent
              where parent.id = w.parent_signal_id
          ))
   );
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
    ), eligible as (
        select t.id target_signal_id, t.audience_code target_audience_code,
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
          and bool_and(m.resolution_mode = 'DIRECT')
          and count(distinct concat_ws('|', m.resolution_mode,
              coalesce(m.garment_type_code, '∅'),
              coalesce(m.sleeve_length_code, '∅'),
              coalesce(m.lower_length_code, '∅'),
              coalesce(m.body_length_code, '∅'))) = 1
          and bool_and(coalesce((fitmatch_vnext.classification_tuple_validation(
              m.garment_type_code, 'SINGLE', t.audience_code,
              m.sleeve_length_code, m.lower_length_code, m.body_length_code
          ) ->> 'valid')::boolean, false))
    )
    insert into fitmatch_vnext.classification_signal_mappings (
        source_signal_id, audience_code, garment_type_code, resolution_mode,
        sleeve_length_code, lower_length_code, body_length_code, priority,
        is_verified, is_active, mapping_version, mapping_checksum
    )
    select target_signal_id, target_audience_code, garment_type_code, 'DIRECT',
           sleeve_length_code, lower_length_code, body_length_code, priority,
           true, true, 'vnext-uniqlo-complete-path-20260902-v2', repeat('0',64)
    from eligible;

    get diagnostics inserted_count = row_count;
    return inserted_count;
end
$function$;

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
security definer
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
    if position('comparison_unit_tuple_validation' in new_definition) = 0
       or position('PRODUCT_COMPARISON_UNIT_NOT_ELIGIBLE' in new_definition) = 0 then
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
                or existing_product.source_extra -> 'product_structure_fact' ? 'value'
                or existing_product.source_extra -> 'structured_facts' ? 'product_structure',
                false
            );
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

    effective_structured_facts_value := structured_facts_value;
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
                'source', case when comparison_contract_state = 'MISSING'
                    then prior_contract_source
                    else structured_facts_value ->> 'comparison_measurement_contract_source' end,
                'evidence', case when comparison_contract_state = 'MISSING'
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

    if not preserve_existing_structure and structure_value <> 'UNKNOWN' then
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
        signal_order_value := signal_order_value + 1;
        signal_id_value := null;
        select s.id into signal_id_value
        from fitmatch_vnext.source_classification_signals s
        where s.source_code = source_value and s.signal_kind = 'CATEGORY'
          and s.external_key = category_value
          and s.audience_code in (audience_value, 'ANY')
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

    -- Promotion is driven only by immutable complete paths; no parent pointer
    -- is created or inferred by this ingress action.
    if source_value = 'uniqlo' and category_index >= 3 and category_value is not null then
        select signal.id into signal_id_value
        from fitmatch_vnext.source_classification_signals signal
        where signal.source_code = source_value
          and signal.signal_kind = 'CATEGORY'
          and signal.external_key = category_value
          and signal.audience_code in (audience_value, 'ANY')
        order by (signal.audience_code = audience_value) desc, signal.id
        limit 1;
        if signal_id_value is not null then
            promoted_count :=
                fitmatch_vnext.promote_uniqlo_audience_invariant_category_mapping(
                    signal_id_value
                );
        end if;
    end if;

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

-- Only immutable, complete official paths may add audience-scoped DIRECT
-- authority. No parent pointer is used as proof and no ANY mapping is created.
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
        where m.mapping_version = 'vnext-uniqlo-complete-path-20260902-v2'
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
end
$postflight$;

commit;
