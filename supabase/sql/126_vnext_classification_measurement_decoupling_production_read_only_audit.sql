-- Production READ-ONLY audit for project hnkplvyegonlhumlejst.
-- This file contains SELECT statements only. It does not apply the migration,
-- mutate products/overrides, backfill data, or deploy anything.

-- 1. Confirm the audited preimage and that downstream safety functions exist.
select
    md5(pg_get_functiondef(
        'fitmatch_vnext.validate_garment_axis_values()'::regprocedure
    )) trigger_definition_hash,
    position('comparison_measurement_contract' in pg_get_functiondef(
        'fitmatch_vnext.validate_garment_axis_values()'::regprocedure
    )) > 0 audited_trigger_is_still_coupled,
    md5(pg_get_functiondef(
        'fitmatch_vnext.product_readiness(uuid)'::regprocedure
    )) readiness_definition_hash,
    md5(pg_get_functiondef(
        'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure
    )) authorization_definition_hash,
    md5(pg_get_functiondef(
        'fitmatch_vnext.set_user_product_classification(uuid,text,text,text,text,uuid,integer)'::regprocedure
    )) set_user_definition_hash,
    position('classification_recovery_options' in pg_get_functiondef(
        'fitmatch_vnext.set_user_product_classification(uuid,text,text,text,text,uuid,integer)'::regprocedure
    )) > 0 set_user_reissues_current_contract,
    position('Selected candidate is not server-authorized' in pg_get_functiondef(
        'fitmatch_vnext.set_user_product_classification(uuid,text,text,text,text,uuid,integer)'::regprocedure
    )) > 0 set_user_rejects_non_contract_candidate,
    position('classification_tuple_validation' in pg_get_functiondef(
        'fitmatch_vnext.validate_user_product_classification_override()'::regprocedure
    )) > 0 override_trigger_requires_canonical_tuple;

-- 2. Project the v6 exact-product-precedence path for the six representative
-- products. The existing exact authority emits only server-evidenced complete
-- tuples. A known legacy sleeve is used to narrow, never broaden, that set.
with wanted(code) as (
    values
        ('E450259'), ('E450260'), ('E450535'),
        ('E450536'), ('E450540'), ('E450544')
), base as (
    select p.*,
           fitmatch_vnext.exact_product_authority_recovery_options(p.id)
               exact_contract
    from wanted w
    join fitmatch_vnext.products p
      on p.source_code = 'uniqlo'
     and p.source_product_key = w.code
), legacy as (
    select b.id,
           case when count(distinct c.length_code) filter (
                    where c.length_code in (
                        'short_sleeve', 'long_sleeve', 'sleeveless'
                    )
                ) = 1
                then min(c.length_code) filter (
                    where c.length_code in (
                        'short_sleeve', 'long_sleeve', 'sleeveless'
                    )
                ) end legacy_sleeve
    from base b
    left join fitmatch_catalog.current_product_classifications c
      on lower(c.source) = lower(b.source_code)
     and c.external_product_id = b.source_product_key
     and lower(c.classification_status) = 'confirmed'
     and coalesce(c.confidence, 0) = 1
     and coalesce((
         c.evidence ->> 'exact_product_authority'
     )::boolean, false)
     and c.evidence ->> 'authority_status' = 'verified'
    group by b.id
), raw as (
    select b.*,
           coalesce(
               nullif(b.sleeve_length_code, 'UNKNOWN'),
               legacy.legacy_sleeve
           ) known_sleeve,
           candidate
    from base b
    join legacy on legacy.id = b.id
    cross join lateral jsonb_array_elements(
        b.exact_contract -> 'candidates'
    ) candidate
    where b.exact_contract ->> 'recoverability' = 'RECOVERABLE'
), valid as (
    select raw.*,
           gt.sort_order,
           encode(extensions.digest(concat_ws('|',
               raw.id::text,
               raw.input_fingerprint,
               raw.evidence_fingerprint,
               raw.resolver_version,
               candidate ->> 'category_code',
               candidate ->> 'garment_type_code',
               coalesce(candidate ->> 'sleeve_length_code', '∅'),
               coalesce(candidate ->> 'lower_length_code', '∅'),
               coalesce(candidate ->> 'body_length_code', '∅'),
               candidate ->> 'comparison_policy_code',
               'fitmatch-vnext-recovery-v6-complete-tuple-garment-first'
           ), 'sha256'), 'hex') v6_fingerprint
    from raw
    join fitmatch_vnext.garment_types gt
      on gt.garment_type_code = candidate ->> 'garment_type_code'
     and gt.is_active
     and gt.category_code = candidate ->> 'category_code'
     and gt.comparison_policy_code =
         candidate ->> 'comparison_policy_code'
    join fitmatch_vnext.comparison_policies policy
      on policy.policy_code = gt.comparison_policy_code
     and policy.is_active
    where coalesce((
        fitmatch_vnext.classification_tuple_validation(
            candidate ->> 'garment_type_code',
            raw.product_structure_code,
            raw.audience_code,
            candidate ->> 'sleeve_length_code',
            candidate ->> 'lower_length_code',
            candidate ->> 'body_length_code'
        ) ->> 'valid'
    )::boolean, false)
      and (
          raw.known_sleeve is null
          or candidate ->> 'sleeve_length_code' = raw.known_sleeve
      )
)
select source_product_key,
       case when count(*) between 1 and 3
                  and bool_and(coalesce((
                      fitmatch_vnext.classification_tuple_validation(
                          candidate ->> 'garment_type_code',
                          product_structure_code,
                          audience_code,
                          candidate ->> 'sleeve_length_code',
                          candidate ->> 'lower_length_code',
                          candidate ->> 'body_length_code'
                      ) ->> 'valid'
                  )::boolean, false))
           then 'RECOVERABLE' else 'UNRECOVERABLE' end
           projected_recoverability,
       count(*)::integer candidate_count,
       bool_and(coalesce((
           fitmatch_vnext.classification_tuple_validation(
               candidate ->> 'garment_type_code',
               product_structure_code,
               audience_code,
               candidate ->> 'sleeve_length_code',
               candidate ->> 'lower_length_code',
               candidate ->> 'body_length_code'
           ) ->> 'valid'
       )::boolean, false)) all_candidates_valid,
       jsonb_agg(jsonb_build_object(
           'garment_type_code', candidate ->> 'garment_type_code',
           'sleeve_length_code', candidate ->> 'sleeve_length_code',
           'lower_length_code', candidate ->> 'lower_length_code',
           'body_length_code', candidate ->> 'body_length_code',
           'candidate_fingerprint', v6_fingerprint
       ) order by sort_order, candidate ->> 'sleeve_length_code') candidates
from valid
group by source_product_key
order by source_product_key;

-- 3. Classification recovery must not bypass measurement readiness.
with wanted(code) as (
    values
        ('E450259'), ('E450260'), ('E450535'),
        ('E450536'), ('E450540'), ('E450544')
), audited as (
    select p.source_product_key,
           fitmatch_vnext.product_comparison_unit_decision(p.id) unit
    from wanted w
    join fitmatch_vnext.products p
      on p.source_code = 'uniqlo'
     and p.source_product_key = w.code
)
select source_product_key,
       unit ->> 'measurement_contract' measurement_contract,
       (unit ->> 'eligible')::boolean comparison_unit_eligible,
       unit ->> 'reason' comparison_unit_reason
from audited
order by source_product_key;

-- 4. Audit active overrides without exposing user identifiers. The projected
-- result mirrors the migration's narrow legacy exact-authority compatibility.
select p.source_product_key,
       o.candidate_contract_version,
       o.selected_candidate_fingerprint,
       o.candidate_set_hash,
       actual.effective_value ->> 'state'
           current_effective_state,
       actual.effective_value ->> 'classification_status'
           current_effective_status,
       actual.effective_value ->> 'effective_source'
           current_effective_source,
       jsonb_strip_nulls(jsonb_build_object(
           'category_code', o.category_code,
           'garment_type_code', o.garment_type_code,
           'sleeve_length_code', o.sleeve_length_code,
           'lower_length_code', o.lower_length_code,
           'body_length_code', o.body_length_code,
           'comparison_policy_code', o.comparison_policy_code
       )) stored_tuple,
       coalesce((
           fitmatch_vnext.classification_tuple_validation(
               o.garment_type_code,
               p.product_structure_code,
               o.audience_code,
               o.sleeve_length_code,
               o.lower_length_code,
               o.body_length_code
           ) ->> 'valid'
       )::boolean, false) tuple_valid,
       p.input_fingerprint = o.base_product_input_fingerprint input_fresh,
       p.evidence_fingerprint = o.base_product_evidence_fingerprint
           evidence_fresh,
       p.resolver_version = o.base_resolver_version resolver_fresh,
       case when p.input_fingerprint = o.base_product_input_fingerprint
                  and p.evidence_fingerprint =
                      o.base_product_evidence_fingerprint
                  and p.resolver_version = o.base_resolver_version
                  and coalesce((
                      fitmatch_vnext.classification_tuple_validation(
                          o.garment_type_code,
                          p.product_structure_code,
                          o.audience_code,
                          o.sleeve_length_code,
                          o.lower_length_code,
                          o.body_length_code
                      ) ->> 'valid'
                  )::boolean, false)
                  and exists (
                      select 1
                      from fitmatch_catalog.current_product_classifications c
                      join fitmatch_vnext.garment_types gt
                        on gt.garment_type_code = case c.detail_code
                            when 'padding' then 'puffer_jacket'
                            when 'padded_vest' then 'puffer_vest'
                            when 'jeans' then 'denim_pants'
                            when 'fleece' then 'fleece_jacket'
                            when 'sweat_jogger' then 'sweat_jogger_pants'
                            when 'cargo_utility' then 'cargo_pants'
                            when 'chino_cotton' then 'chino_cotton_pants'
                            else c.detail_code
                        end
                       and gt.is_active
                      where lower(c.source) = lower(p.source_code)
                        and c.external_product_id = p.source_product_key
                        and gt.garment_type_code = o.garment_type_code
                        and gt.category_code = o.category_code
                        and gt.comparison_policy_code =
                            o.comparison_policy_code
                        and c.comparison_family_code =
                            o.comparison_policy_code
                        and lower(c.classification_status) = 'confirmed'
                        and coalesce(c.confidence, 0) = 1
                        and coalesce((
                            c.evidence ->> 'exact_product_authority'
                        )::boolean, false)
                        and c.evidence ->> 'authority_status' = 'verified'
                  )
            then 'PERSONAL_CONFIRMED'
            else 'STALE_RECONFIRM_REQUIRED' end projected_state_after_v6
from fitmatch_vnext.user_product_classification_overrides o
join fitmatch_vnext.products p on p.id = o.product_id
-- effective_target_classification is caller-scoped. This transaction-local
-- setting evaluates the real function as each owner without persisting data
-- or returning a user identifier.
cross join lateral (
    select fitmatch_vnext.effective_target_classification(p.id)
        effective_value
    from (
        select set_config(
            'request.jwt.claim.sub',
            o.user_id::text,
            true
        ) marker
        offset 0
    ) authenticated_claim
    where authenticated_claim.marker = o.user_id::text
) actual
where o.cleared_at is null
order by p.source_product_key;
