-- Purpose: preserve the parser identity of retailer measurement records when
-- the payload omits parser_code but the verified raw-code registry identifies
-- exactly one parser. Ambiguous records remain fail-closed.

begin;

do $patch_ingress$
declare
    old_definition text;
    new_definition text;
begin
    if to_regclass('fitmatch_vnext.source_measurement_aliases') is null
       or to_regclass('fitmatch_vnext.product_size_measurements') is null
       or to_regprocedure(
           'fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)'
       ) is null then
        raise exception 'Required measurement-ingestion contract is missing';
    end if;

    old_definition := pg_get_functiondef(
        'fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)'::regprocedure
    );
    if position('alias.raw_code = raw_code_value' in old_definition) = 0 then
        if position(
            'nullif(btrim(p_payload -> ''structured_facts'' ->> '
            || '''measurement_parser_code''), ''''),' || E'\n'
            || '                    default_parser_value,'
            in old_definition
        ) = 0
           or position('ingestion_unmapped' in old_definition) = 0 then
            raise exception 'Unexpected ingestion parser preimage';
        end if;

        new_definition := replace(
            old_definition,
            'nullif(btrim(p_payload -> ''structured_facts'' ->> '
            || '''measurement_parser_code''), ''''),' || E'\n'
            || '                    default_parser_value,',
            'nullif(btrim(p_payload -> ''structured_facts'' ->> '
            || '''measurement_parser_code''), ''''),' || E'\n'
            || '                    (' || E'\n'
            || '                        select case when count(distinct alias.parser_code) = 1'
            || E'\n' || '                            then min(alias.parser_code) end'
            || E'\n' || '                        from fitmatch_vnext.source_measurement_aliases alias'
            || E'\n' || '                        where alias.source_code = source_value'
            || E'\n' || '                          and alias.raw_code = raw_code_value'
            || E'\n' || '                          and alias.is_active and alias.is_verified'
            || E'\n' || '                    ),' || E'\n'
            || '                    default_parser_value,'
        );
        if position('alias.raw_code = raw_code_value' in new_definition) = 0 then
            raise exception 'Unable to patch ingestion parser inference';
        end if;
        execute new_definition;
    end if;
end
$patch_ingress$;

-- Correct only current rows whose source/raw-code registry has one verified
-- parser. This repairs parser attribution, not raw retailer evidence.
with inferred as (
    select measurement.id,
           min(alias.parser_code) inferred_parser
    from fitmatch_vnext.product_size_measurements measurement
    join fitmatch_vnext.product_sizes product_size
      on product_size.id = measurement.product_size_id
    join fitmatch_vnext.product_variants variant
      on variant.id = product_size.variant_id
    join fitmatch_vnext.products product on product.id = variant.product_id
    join fitmatch_vnext.source_measurement_aliases alias
      on alias.source_code = product.source_code
     and alias.raw_code = measurement.raw_code
     and alias.is_active and alias.is_verified
    where measurement.is_current
      and measurement.parser_code = 'ingestion_unmapped'
    group by measurement.id
    having count(distinct alias.parser_code) = 1
), safe_update as (
    select inferred.id, inferred.inferred_parser
    from inferred
    join fitmatch_vnext.product_size_measurements measurement
      on measurement.id = inferred.id
    where not exists (
        select 1
        from fitmatch_vnext.product_size_measurements existing
        where existing.product_size_id = measurement.product_size_id
          and existing.parser_code = inferred.inferred_parser
          and existing.raw_measurement_key = measurement.raw_measurement_key
          and existing.id <> measurement.id
    )
)
update fitmatch_vnext.product_size_measurements measurement
set parser_code = safe_update.inferred_parser,
    evidence_payload = coalesce(measurement.evidence_payload, '{}'::jsonb)
        || jsonb_build_object('parser_code_resolution', jsonb_build_object(
            'method', 'unique_verified_raw_code_alias',
            'previous_parser_code', 'ingestion_unmapped',
            'resolved_parser_code', safe_update.inferred_parser,
            'migration', '20260903105000'
        )),
    updated_at = now()
from safe_update
where measurement.id = safe_update.id;

-- If an equivalent correctly attributed row already exists, retain the raw
-- evidence row but remove the obsolete duplicate from current projection.
with inferred as (
    select measurement.id,
           min(alias.parser_code) inferred_parser
    from fitmatch_vnext.product_size_measurements measurement
    join fitmatch_vnext.product_sizes product_size
      on product_size.id = measurement.product_size_id
    join fitmatch_vnext.product_variants variant
      on variant.id = product_size.variant_id
    join fitmatch_vnext.products product on product.id = variant.product_id
    join fitmatch_vnext.source_measurement_aliases alias
      on alias.source_code = product.source_code
     and alias.raw_code = measurement.raw_code
     and alias.is_active and alias.is_verified
    where measurement.is_current
      and measurement.parser_code = 'ingestion_unmapped'
    group by measurement.id
    having count(distinct alias.parser_code) = 1
)
update fitmatch_vnext.product_size_measurements measurement
set is_current = false,
    evidence_payload = coalesce(measurement.evidence_payload, '{}'::jsonb)
        || jsonb_build_object('parser_code_resolution', jsonb_build_object(
            'method', 'superseded_by_existing_verified_parser_row',
            'resolved_parser_code', inferred.inferred_parser,
            'migration', '20260903105000'
        )),
    updated_at = now()
from inferred
where measurement.id = inferred.id
  and exists (
      select 1
      from fitmatch_vnext.product_size_measurements existing
      where existing.product_size_id = measurement.product_size_id
        and existing.parser_code = inferred.inferred_parser
        and existing.raw_measurement_key = measurement.raw_measurement_key
        and existing.id <> measurement.id
        and existing.is_current
  );

do $postflight$
begin
    if position('alias.raw_code = raw_code_value' in pg_get_functiondef(
        'fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)'::regprocedure
    )) = 0 then
        raise exception 'Ingress parser inference postflight failed';
    end if;
    if exists (
        select 1
        from fitmatch_vnext.product_size_measurements measurement
        join fitmatch_vnext.product_sizes product_size
          on product_size.id = measurement.product_size_id
        join fitmatch_vnext.product_variants variant
          on variant.id = product_size.variant_id
        join fitmatch_vnext.products product on product.id = variant.product_id
        join fitmatch_vnext.source_measurement_aliases alias
          on alias.source_code = product.source_code
         and alias.raw_code = measurement.raw_code
         and alias.is_active and alias.is_verified
        where measurement.is_current
          and measurement.parser_code = 'ingestion_unmapped'
        group by measurement.id
        having count(distinct alias.parser_code) = 1
    ) then
        raise exception 'Safely inferable current measurement remains unmapped';
    end if;
end
$postflight$;

commit;
