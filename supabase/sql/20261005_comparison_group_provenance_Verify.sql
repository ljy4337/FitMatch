-- READ ONLY. Run against the intended project after applying the migration.
select md5(regexp_replace(pg_get_functiondef(p.oid),'\s+',' ','g')) definition_hash,position('source_value := resolved->>''mapping_source''' in p.prosrc)>0 reads_actual_mapping_source,position('Invalid comparison group mapping source' in p.prosrc)>0 rejects_unknown_source,position('coalesce(resolved->>''source'', ''RETAILER_CATEGORY'')' in p.prosrc)=0 removed_wrong_default,p.proacl::text acl,p.prosecdef,p.proconfig,pg_get_function_identity_arguments(p.oid) arguments,has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute from pg_proc p where p.oid='fitmatch_vnext.comparison_target_context(uuid,uuid,text)'::regprocedure;

select version, name from supabase_migrations.schema_migrations
where name = 'repair_comparison_group_provenance' order by version;
