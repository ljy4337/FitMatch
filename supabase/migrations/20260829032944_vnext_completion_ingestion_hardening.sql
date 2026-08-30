-- Purpose: close two fail-closed input boundaries discovered during final
-- remediation verification: explicit product-identity/structure signals must
-- agree with their retailer facts, and completed ranking/reliability values must
-- be integers rather than values silently rounded by PostgreSQL casts.
-- Data impact: none for existing rows. New ingestion receipts and comparison
-- completion transitions receive additive validation triggers.
-- Rollback: drop the two validation triggers and their trigger functions.
-- Verification: spoofed PRODUCT_EXACT/PRODUCT_STRUCTURE inputs and fractional
-- rank/reliability completion payloads must fail inside their transactions.

create or replace function fitmatch_vnext.validate_ingestion_receipt_facts()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    signal_value jsonb;
    signal_kind_value text;
    signal_key_value text;
    structure_value text;
begin
    if lower(btrim(new.retailer_facts ->> 'source')) is distinct from new.source_code
       or btrim(new.retailer_facts ->> 'external_product_id')
            is distinct from new.source_product_key then
        raise exception 'Ingestion receipt identity does not match retailer facts';
    end if;

    if not exists (
        select 1
        from fitmatch_vnext.products p
        where p.id = new.product_id
          and p.source_code = new.source_code
          and p.source_product_key = new.source_product_key
    ) then
        raise exception 'Ingestion receipt product hierarchy mismatch';
    end if;

    structure_value := upper(btrim(coalesce(
        new.retailer_facts ->> 'product_structure',
        new.retailer_facts -> 'structured_facts' ->> 'product_structure',
        'UNKNOWN'
    )));
    if structure_value not in ('SINGLE','SET','MULTIPACK','UNKNOWN') then
        structure_value := 'UNKNOWN';
    end if;

    for signal_value in
        select value
        from jsonb_array_elements(coalesce(
            new.retailer_facts -> 'classification_signals', '[]'::jsonb
        ))
    loop
        signal_kind_value := upper(btrim(signal_value ->> 'kind'));
        signal_key_value := btrim(coalesce(
            signal_value ->> 'external_key', signal_value ->> 'key'
        ));

        if signal_kind_value = 'PRODUCT_EXACT'
           and signal_key_value is distinct from new.source_product_key then
            raise exception 'PRODUCT_EXACT signal must match the observed product identity';
        end if;

        if signal_kind_value = 'PRODUCT_STRUCTURE'
           and (
               structure_value = 'UNKNOWN'
               or upper(signal_key_value) is distinct from structure_value
           ) then
            raise exception 'PRODUCT_STRUCTURE signal must match structured retailer facts';
        end if;
    end loop;

    return new;
end
$function$;

drop trigger if exists product_ingestion_receipts_validate_facts
    on fitmatch_vnext.product_ingestion_receipts;
create trigger product_ingestion_receipts_validate_facts
before insert on fitmatch_vnext.product_ingestion_receipts
for each row execute function fitmatch_vnext.validate_ingestion_receipt_facts();

create or replace function fitmatch_vnext.validate_comparison_completion_payload()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    reliability_value numeric;
begin
    if new.result_status <> 'COMPLETED' then
        return new;
    end if;

    reliability_value := (new.result_evidence ->> 'reliability')::numeric;
    if reliability_value <> trunc(reliability_value)
       or reliability_value <> new.reliability_level::numeric then
        raise exception 'Completion reliability must be an integer matching the stored summary';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(
            new.result_evidence -> 'candidate_size_ranking'
        ) ranking
        where (ranking ->> 'rank')::numeric < 1
           or (ranking ->> 'rank')::numeric <>
                trunc((ranking ->> 'rank')::numeric)
    ) then
        raise exception 'Candidate ranks must be positive integers';
    end if;

    if (new.result_evidence ->> 'recommended_product_size_id')::uuid
            is distinct from new.recommended_product_size_id
       or (new.result_evidence ->> 'score')::numeric is distinct from new.fit_score
       or (new.result_evidence ->> 'coverage')::numeric
            is distinct from new.coverage_ratio
       or new.result_evidence ->> 'engine_version' is distinct from new.engine_version then
        raise exception 'Completion evidence summary must match stored comparison columns';
    end if;

    return new;
end
$function$;

drop trigger if exists comparisons_validate_completion_payload
    on fitmatch_vnext.comparisons;
create trigger comparisons_validate_completion_payload
before insert or update of result_status, result_evidence,
    recommended_product_size_id, fit_score, reliability_level,
    coverage_ratio, engine_version
on fitmatch_vnext.comparisons
for each row execute function fitmatch_vnext.validate_comparison_completion_payload();

revoke all on function fitmatch_vnext.validate_ingestion_receipt_facts()
    from public, anon, authenticated;
revoke all on function fitmatch_vnext.validate_comparison_completion_payload()
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.validate_ingestion_receipt_facts()
    to service_role;
grant execute on function fitmatch_vnext.validate_comparison_completion_payload()
    to service_role;
