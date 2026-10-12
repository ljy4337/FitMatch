-- READ ONLY. Run on the explicitly selected target after authorized Apply.
select c.relname,c.relrowsecurity,
 has_table_privilege('authenticated',c.oid,'INSERT') authenticated_insert,
 has_table_privilege('authenticated',c.oid,'UPDATE') authenticated_update,
 has_table_privilege('anon',c.oid,'SELECT') anon_select
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='fitmatch_vnext' and c.relname in ('user_size_recoveries','active_user_size_recoveries');
select n.nspname,p.proname,p.prosecdef,p.proconfig,
 has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='public' and p.proname in ('fitmatch_vnext_save_user_size_recovery','fitmatch_vnext_get_user_size_recovery'))
 or (n.nspname='fitmatch_vnext' and p.proname in ('save_user_size_recovery','get_user_size_recovery','comparison_product_sizes','user_size_recovery_metadata'));
select conname,pg_get_constraintdef(oid) definition from pg_constraint
where conrelid='fitmatch_vnext.comparisons'::regclass
 and conname in ('comparisons_recommended_product_size_fkey','comparisons_recommended_user_recovery_size_id_fkey',
 'comparisons_single_recommended_identity_chk','comparisons_recommended_authority_chk');
select object_signature,md5(definition) before_hash,md5(applied_definition) applied_hash,
 case when object_signature='comparisons_recommended_authority_chk' then null
 else md5(pg_get_functiondef(object_signature::regprocedure))=md5(applied_definition) end still_matches_proposal
from fitmatch_vnext.bugfix1012_recovery_backups order by object_signature;
-- No SELECT of user payloads. Authentication/owner/readback is verified by isolated regression or approved QA account.
