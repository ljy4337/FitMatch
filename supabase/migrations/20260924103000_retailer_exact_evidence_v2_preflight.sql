-- Additive, inactive v2 preflight for server-approved retailer-exact evidence.
--
-- It intentionally does not alter candidate lookup, authorization, begin,
-- complete, or History.  The live comparison path remains canonical-only
-- until the full immutable v2 snapshot contract is activated together.

begin;

do $required_raw_snapshot_owners$
begin
    if to_regclass('fitmatch_vnext.closet_item_source_measurement_snapshots') is null
       or to_regclass('fitmatch_vnext.closet_item_source_measurements') is null
       or to_regclass('fitmatch_vnext.product_size_measurements') is null then
        raise exception 'Retailer-exact v2 requires the raw Closet snapshot and product raw-measurement owners';
    end if;
end
$required_raw_snapshot_owners$;

-- A raw label/code is never enough to establish a direct-comparison meaning.
-- The collector/evidence owner must preserve every field below explicitly.
-- Missing fields fail closed rather than being inferred from a canonical
-- projection or a similarly named retailer row.
create or replace function fitmatch_vnext.retailer_exact_semantic_contract_v2(
    p_evidence jsonb
)
returns jsonb
language sql
immutable
set search_path = ''
as $function$
with semantic_source as (
    select coalesce(
        nullif(p_evidence -> 'measurement_semantics', '{}'::jsonb),
        nullif(p_evidence -> 'retailer_evidence' -> 'measurement_semantics', '{}'::jsonb),
        nullif(p_evidence -> 'semantic_contract', '{}'::jsonb),
        '{}'::jsonb
    ) as value
)
select jsonb_strip_nulls(jsonb_build_object(
    'source_schema_version', coalesce(
        nullif(btrim(value ->> 'source_schema_version'), ''),
        nullif(btrim(value ->> 'schema_version'), '')
    ),
    'basis_code', nullif(btrim(value ->> 'basis_code'), ''),
    'representation_code', nullif(btrim(value ->> 'representation_code'), ''),
    'component_code', nullif(btrim(value ->> 'component_code'), '')
))
from semantic_source;
$function$;

-- This is evidence discovery only, not authorization.  A future activation
-- must call it only after the existing same-group/ownership/context checks,
-- and must freeze the returned identity in begin/complete/history snapshots.
create or replace function fitmatch_vnext.retailer_exact_evidence_v2(
    p_reference_closet_item_id uuid,
    p_target_product_size_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
with reference_rows as (
    select
        ci.id as reference_closet_item_id,
        sm.source_code,
        sm.parser_code,
        sm.raw_measurement_key,
        sm.raw_code,
        sm.raw_value as reference_value,
        sm.raw_unit_code,
        sm.raw_representation,
        fitmatch_vnext.retailer_exact_semantic_contract_v2(sm.evidence_payload) as semantic_contract
    from fitmatch_vnext.closet_items ci
    join fitmatch_vnext.closet_item_source_measurement_snapshots ss
      on ss.closet_item_id = ci.id
     and ss.product_id = ci.product_id
     and ss.product_variant_id = ci.product_variant_id
     and ss.product_size_id = ci.product_size_id
    join fitmatch_vnext.closet_item_source_measurements sm
      on sm.closet_item_id = ci.id
    where ci.id = p_reference_closet_item_id
      and ci.user_id = auth.uid()
      and ci.deleted_at is null
), target_rows as (
    select
        psm.product_size_id as target_product_size_id,
        p.source_code,
        psm.parser_code,
        psm.raw_measurement_key,
        psm.raw_code,
        psm.raw_value as target_value,
        psm.raw_unit_code,
        psm.evidence_payload ->> 'raw_representation' as raw_representation,
        fitmatch_vnext.retailer_exact_semantic_contract_v2(psm.evidence_payload)
            as semantic_contract
    from fitmatch_vnext.product_size_measurements psm
    join fitmatch_vnext.product_sizes ps on ps.id = psm.product_size_id
    join fitmatch_vnext.product_variants pv on pv.id = ps.variant_id
    join fitmatch_vnext.products p on p.id = pv.product_id
    where psm.product_size_id = p_target_product_size_id
      and psm.is_current
), exact_rows as (
    select reference_rows.*, target_rows.target_product_size_id,
        target_rows.target_value, target_rows.raw_unit_code as target_unit_code,
        target_rows.raw_representation as target_raw_representation,
        target_rows.semantic_contract as target_semantic_contract
    from reference_rows
    join target_rows
      on target_rows.source_code = reference_rows.source_code
     and target_rows.parser_code = reference_rows.parser_code
     and target_rows.raw_measurement_key = reference_rows.raw_measurement_key
     and target_rows.raw_code = reference_rows.raw_code
     and lower(btrim(coalesce(target_rows.raw_unit_code, '')))
         = lower(btrim(coalesce(reference_rows.raw_unit_code, '')))
     and lower(btrim(coalesce(target_rows.raw_representation, '')))
         = lower(btrim(coalesce(reference_rows.raw_representation, '')))
     and target_rows.semantic_contract = reference_rows.semantic_contract
    where reference_rows.reference_value > 0
      and target_rows.target_value > 0
      and nullif(btrim(reference_rows.raw_code), '') is not null
      and nullif(btrim(reference_rows.raw_unit_code), '') is not null
      and nullif(btrim(reference_rows.raw_representation), '') is not null
      and nullif(btrim(reference_rows.semantic_contract ->> 'source_schema_version'), '') is not null
      and nullif(btrim(reference_rows.semantic_contract ->> 'basis_code'), '') is not null
      and nullif(btrim(reference_rows.semantic_contract ->> 'representation_code'), '') is not null
      and nullif(btrim(reference_rows.semantic_contract ->> 'component_code'), '') is not null
)
select coalesce(jsonb_agg(jsonb_build_object(
    'evidence_version', 'retailer-exact-evidence-v2',
    'mode', 'RETAILER_EXACT',
    'reference_closet_item_id', reference_closet_item_id,
    'target_product_size_id', target_product_size_id,
    'source_code', source_code,
    'parser_code', parser_code,
    'raw_measurement_key', raw_measurement_key,
    'raw_code', raw_code,
    'reference_value', reference_value,
    'target_value', target_value,
    'unit_code', lower(btrim(raw_unit_code)),
    'source_schema_version', semantic_contract ->> 'source_schema_version',
    'basis_code', semantic_contract ->> 'basis_code',
    'representation_code', semantic_contract ->> 'representation_code',
    'component_code', semantic_contract ->> 'component_code',
    -- v2 is deliberately not score evidence until full begin/complete
    -- activation pins a server-authorized policy weight and tolerance.
    'score_included', false
) order by parser_code, raw_measurement_key), '[]'::jsonb)
from exact_rows;
$function$;

revoke all on function fitmatch_vnext.retailer_exact_semantic_contract_v2(jsonb)
    from public, anon, authenticated;
revoke all on function fitmatch_vnext.retailer_exact_evidence_v2(uuid, uuid)
    from public, anon;
grant execute on function fitmatch_vnext.retailer_exact_evidence_v2(uuid, uuid)
    to authenticated, service_role;

commit;
