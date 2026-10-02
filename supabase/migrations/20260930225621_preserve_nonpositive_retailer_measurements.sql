-- Match the deployed QA migration version to prevent duplicate application.
-- The raw-receipt ingestion contract retains numeric retailer facts including
-- zero/negative placeholders. Canonical projection already excludes these.
begin;

do $preflight$
begin
    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'fitmatch_vnext.product_size_measurements'::regclass
          and conname = 'product_size_measurements_value_chk'
          and pg_get_constraintdef(oid) = 'CHECK ((raw_value > (0)::numeric))'
    ) then
        raise exception 'Unexpected raw measurement value constraint';
    end if;

    if position('m.raw_value > 0' in pg_get_functiondef(
        'fitmatch_vnext.canonical_measurements_for_size(uuid)'::regprocedure
    )) = 0 or position('m.raw_value > 0' in pg_get_functiondef(
        'fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)'::regprocedure
    )) = 0 then
        raise exception 'Nonpositive canonical exclusion is missing';
    end if;
end
$preflight$;

alter table fitmatch_vnext.product_size_measurements
    drop constraint product_size_measurements_value_chk;

commit;
