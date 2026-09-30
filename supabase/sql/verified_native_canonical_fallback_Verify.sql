-- Read-only deployment check. Runtime calls need an authenticated user session.
select p.proname,
       md5(pg_get_functiondef(p.oid)) definition_md5,
       position('native_candidates as' in lower(pg_get_functiondef(p.oid))) > 0
           has_verified_native_fallback,
       p.prosecdef security_definer,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='fitmatch_vnext'
  and p.proname='comparison_evidence_20260908';

select count(*) active_verified_sleeve_mappings
from fitmatch_vnext.source_measurements sm
join fitmatch_vnext.source_measurement_mappings smm
  on smm.source_measurement_code=sm.source_measurement_code
 and smm.is_active and smm.is_verified
join fitmatch_vnext.fitmatch_measurements fm
  on fm.measurement_code=smm.fitmatch_measurement_code and fm.is_active
where sm.is_active and sm.is_comparable
  and fm.body_region_code='SLEEVE'
  and fm.canonical_basis_code=sm.measurement_basis_code
  and fm.representation_code=sm.representation_code;
