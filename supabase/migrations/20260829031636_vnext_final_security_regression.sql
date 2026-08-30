-- Purpose: final least-privilege and SECURITY DEFINER regression gate for the
-- remediation RPCs.
-- Data impact: privileges only; no row changes.
-- Rollback: restore grants from the preceding migrations.
-- Verification: anonymous and cross-user calls fail; global ingestion and
-- classification application remain service-role only.

grant usage on schema fitmatch_vnext to authenticated, service_role;
revoke create on schema fitmatch_vnext from public, anon, authenticated, service_role;

revoke all on table fitmatch_vnext.product_ingestion_receipts
    from public, anon, authenticated;
grant select, insert, update on table fitmatch_vnext.product_ingestion_receipts
    to service_role;

revoke all on function fitmatch_vnext.ingest_product_observation(jsonb,uuid)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.ingest_product_observation(jsonb,uuid)
    to service_role;

revoke all on function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)
    from public, anon;
revoke all on function fitmatch_vnext.find_reference_candidates(uuid,uuid)
    from public, anon;
revoke all on function fitmatch_vnext.begin_comparison(jsonb)
    from public, anon;
revoke all on function fitmatch_vnext.complete_comparison(uuid,jsonb)
    from public, anon;
grant execute on function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean),
    fitmatch_vnext.find_reference_candidates(uuid,uuid),
    fitmatch_vnext.begin_comparison(jsonb),
    fitmatch_vnext.complete_comparison(uuid,jsonb)
    to authenticated, service_role;

revoke all on function fitmatch_vnext.resolve_product_classification(text,text,boolean)
    from public, anon, authenticated;
grant execute on function fitmatch_vnext.resolve_product_classification(text,text,boolean)
    to service_role;

-- Authenticated users write their owned domain rows only through RPCs.
revoke insert, update, delete, truncate on table
    fitmatch_vnext.products,
    fitmatch_vnext.product_variants,
    fitmatch_vnext.product_sizes,
    fitmatch_vnext.product_size_measurements,
    fitmatch_vnext.source_identifiers,
    fitmatch_vnext.source_classification_signals,
    fitmatch_vnext.product_classification_signals,
    fitmatch_vnext.size_availability_observations,
    fitmatch_vnext.classification_signal_mappings,
    fitmatch_vnext.closet_items,
    fitmatch_vnext.closet_item_measurements,
    fitmatch_vnext.comparisons
from authenticated;

do $verify$
declare
    function_name text;
begin
    foreach function_name in array array[
        'fitmatch_vnext.ingest_product_observation(jsonb,uuid)',
        'fitmatch_vnext.get_product_runtime(text,text)',
        'fitmatch_vnext.upsert_closet_item(jsonb)',
        'fitmatch_vnext.list_closet_items()',
        'fitmatch_vnext.set_closet_reference(uuid)',
        'fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)',
        'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)',
        'fitmatch_vnext.find_reference_candidates(uuid,uuid)',
        'fitmatch_vnext.begin_comparison(jsonb)',
        'fitmatch_vnext.complete_comparison(uuid,jsonb)',
        'fitmatch_vnext.comparison_history()'
    ] loop
        if not exists (
            select 1
            from pg_proc p
            where p.oid = function_name::regprocedure
              and p.prosecdef
              and p.proconfig @> array['search_path=""']::text[]
        ) then
            raise exception 'SECURITY DEFINER search_path regression: %', function_name;
        end if;
    end loop;

    if has_function_privilege('anon',
        'fitmatch_vnext.ingest_product_observation(jsonb,uuid)', 'EXECUTE')
       or has_function_privilege('authenticated',
        'fitmatch_vnext.ingest_product_observation(jsonb,uuid)', 'EXECUTE') then
        raise exception 'Global ingestion is not service-role only';
    end if;

    if exists (
        select 1
        from information_schema.role_table_grants g
        where g.table_schema = 'fitmatch_vnext'
          and g.grantee = 'authenticated'
          and g.table_name in (
              'products','product_variants','product_sizes',
              'product_size_measurements','source_identifiers',
              'source_classification_signals','product_classification_signals',
              'size_availability_observations','classification_signal_mappings',
              'closet_items','closet_item_measurements','comparisons',
              'product_ingestion_receipts'
          )
          and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
    ) then
        raise exception 'Broad authenticated write grant remains';
    end if;
end
$verify$;

-- Read-only verification query:
-- select p.proname,p.prosecdef,p.proconfig
-- from pg_proc p join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='fitmatch_vnext' and p.prosecdef order by p.proname;
