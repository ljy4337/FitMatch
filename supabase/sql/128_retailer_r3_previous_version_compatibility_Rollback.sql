-- Manual rollback for 128_retailer_r3_previous_version_compatibility_Apply.sql.
-- Restores the exact 2026-09-09 classification_decision body preimage.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $rollback$
declare
    function_oid oid := to_regprocedure(
        'fitmatch_vnext.classification_decision(text,text)'
    );
    installed_body text;
    restored_body text;
    patch_position integer;
    patched_fragment constant text := $patched$ -- A previous resolver version does not invalidate current, identity-verified
 -- retailer API evidence. Stored rows still change only through the existing apply path.
$patched$;
    original_fragment constant text := $original$ -- Installing this function cannot invalidate existing personal choices or reclassify
 -- stored rows. Existing ingress clears resolver_version only for a NEW observation.
 IF product_row.resolver_version IS NOT NULL AND product_row.resolver_version<>version_value
 THEN RETURN base; END IF;$original$;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'fitmatch_vnext.classification_decision(text,text)', 0
        )
    );
    if function_oid is null then
        raise exception 'FM_R3_COMPAT_ROLLBACK_MISSING_FUNCTION';
    end if;
    select p.prosrc into installed_body
    from pg_catalog.pg_proc p
    where p.oid = function_oid;

    if md5(installed_body) = '0c0dabc519fa9d1f4ffb9b8ecf87ce95' then
        return;
    end if;
    if md5(installed_body) <> '291bf9bdf95b37d234f344e7d4d80303' then
        raise exception 'FM_R3_COMPAT_ROLLBACK_DRIFT: %', md5(installed_body);
    end if;

    patch_position := strpos(installed_body, patched_fragment);
    if patch_position = 0 then
        raise exception 'FM_R3_COMPAT_ROLLBACK_FRAGMENT_NOT_FOUND';
    end if;
    restored_body := overlay(
        installed_body placing original_fragment
        from patch_position for length(patched_fragment)
    );
    if md5(restored_body) <> '0c0dabc519fa9d1f4ffb9b8ecf87ce95' then
        raise exception 'FM_R3_COMPAT_ROLLBACK_CHECKSUM_MISMATCH: %', md5(restored_body);
    end if;

    execute format(
        'create or replace function fitmatch_vnext.classification_decision('
        || 'p_source_code text,p_source_product_key text) '
        || 'returns jsonb language plpgsql stable security invoker '
        || 'set search_path to '''' as %L',
        restored_body
    );
end
$rollback$;

commit;
