-- DEVELOPMENT candidate. The user applies this manually after reviewing Verify.sql.
-- Production application, data mutation, migration registration and Edge deploy: NOT DONE.
--
-- Exact installed preimage (2026-09-09):
--   fitmatch_vnext.classification_decision(text,text)
--   md5(prosrc) = 0c0dabc519fa9d1f4ffb9b8ecf87ce95
--
-- The outer r3 wrapper currently returns the legacy mapping decision whenever
-- products.resolver_version is r1/r2. That prevents its already-preserved,
-- identity-checked fitmatch-retailer-api-v1 object from reaching the r3 reader.
-- This patch removes only that first/outer guard. The two nested historical
-- guards remain byte-identical, public RPC names stay unchanged, and no row is
-- updated by this script.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $apply$
declare
    function_oid oid := to_regprocedure(
        'fitmatch_vnext.classification_decision(text,text)'
    );
    installed_body text;
    patched_body text;
    patch_position integer;
    old_fragment constant text := $old$ -- Installing this function cannot invalidate existing personal choices or reclassify
 -- stored rows. Existing ingress clears resolver_version only for a NEW observation.
 IF product_row.resolver_version IS NOT NULL AND product_row.resolver_version<>version_value
 THEN RETURN base; END IF;$old$;
    new_fragment constant text := $new$ -- A previous resolver version does not invalidate current, identity-verified
 -- retailer API evidence. Stored rows still change only through the existing apply path.
$new$;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'fitmatch_vnext.classification_decision(text,text)', 0
        )
    );
    if function_oid is null then
        raise exception 'FM_R3_COMPAT_MISSING_CLASSIFICATION_DECISION';
    end if;

    select p.prosrc into installed_body
    from pg_catalog.pg_proc p
    where p.oid = function_oid;

    if md5(installed_body) = '291bf9bdf95b37d234f344e7d4d80303' then
        return;
    end if;
    if md5(installed_body) <> '0c0dabc519fa9d1f4ffb9b8ecf87ce95' then
        raise exception 'FM_R3_COMPAT_PREIMAGE_DRIFT: %', md5(installed_body);
    end if;

    patch_position := strpos(installed_body, old_fragment);
    if patch_position = 0 then
        raise exception 'FM_R3_COMPAT_OUTER_GUARD_NOT_FOUND';
    end if;
    patched_body := overlay(
        installed_body placing new_fragment
        from patch_position for length(old_fragment)
    );
    if md5(patched_body) <> '291bf9bdf95b37d234f344e7d4d80303' then
        raise exception 'FM_R3_COMPAT_PATCH_CHECKSUM_MISMATCH: %', md5(patched_body);
    end if;

    execute format(
        'create or replace function fitmatch_vnext.classification_decision('
        || 'p_source_code text,p_source_product_key text) '
        || 'returns jsonb language plpgsql stable security invoker '
        || 'set search_path to '''' as %L',
        patched_body
    );

    if not exists (
        select 1
        from pg_catalog.pg_proc p
        where p.oid = to_regprocedure(
            'fitmatch_vnext.classification_decision(text,text)'
        )
          and md5(p.prosrc) = '291bf9bdf95b37d234f344e7d4d80303'
          and not p.prosecdef
          and p.provolatile = 's'
          and p.proconfig = array['search_path=""']::text[]
          and p.proacl::text =
              '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}'
    ) then
        raise exception 'FM_R3_COMPAT_POSTCHECK_FAILED';
    end if;
end
$apply$;

commit;
