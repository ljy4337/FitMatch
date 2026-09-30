-- READ ONLY. Same query may be used on source and target; compare app objects
-- by identity, retaining target platform objects such as rls_auto_enable.
WITH relations AS (
 SELECT c.*, n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','fitmatch_catalog','fitmatch_vnext')
 AND c.relkind IN ('r','p','v','m','S')
), functions AS (
 SELECT p.*, n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','fitmatch_catalog','fitmatch_vnext') AND p.prokind='f'
 AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
   AND d.objid=p.oid AND d.deptype='e')
)
SELECT jsonb_build_object(
 'server_major',current_setting('server_version_num')::int / 10000,
 'database',current_database(),
 'schemas',(SELECT jsonb_agg(jsonb_build_object('name',nspname,'owner',pg_get_userbyid(nspowner),'acl',nspacl) ORDER BY nspname)
   FROM pg_namespace WHERE nspname IN ('public','fitmatch_catalog','fitmatch_vnext')),
 'relations',(SELECT jsonb_agg(jsonb_build_object('name',nspname||'.'||relname,'kind',relkind,
   'owner',pg_get_userbyid(relowner),'rls',relrowsecurity,'force_rls',relforcerowsecurity,'acl',relacl) ORDER BY nspname,relname) FROM relations),
 'columns',(SELECT jsonb_agg(jsonb_build_object('table',a.attrelid::regclass::text,'position',a.attnum,
   'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
   'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid))
   ORDER BY a.attrelid::regclass::text,a.attnum)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid IN (SELECT oid FROM relations) AND a.attnum>0 AND NOT a.attisdropped),
 'sequence_definitions',(SELECT jsonb_agg(jsonb_build_object('name',s.seqrelid::regclass::text,
   'start',s.seqstart,'increment',s.seqincrement,'max',s.seqmax,'min',s.seqmin,'cache',s.seqcache,'cycle',s.seqcycle)
   ORDER BY s.seqrelid::regclass::text) FROM pg_sequence s WHERE s.seqrelid IN (SELECT oid FROM relations)),
 'default_acl',(SELECT jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),
   'schema',n.nspname,'kind',d.defaclobjtype,'acl',d.defaclacl) ORDER BY n.nspname,d.defaclrole,d.defaclobjtype)
   FROM pg_default_acl d JOIN pg_namespace n ON n.oid=d.defaclnamespace
   WHERE n.nspname IN ('public','fitmatch_catalog','fitmatch_vnext')),
 'event_triggers',(SELECT jsonb_agg(jsonb_build_object('name',e.evtname,'event',e.evtevent,
   'enabled',e.evtenabled,'function',e.evtfoid::regprocedure::text,'tags',e.evttags) ORDER BY e.evtname)
   FROM pg_event_trigger e WHERE e.evtfoid IN (SELECT oid FROM functions)),
 'functions',(SELECT jsonb_agg(jsonb_build_object('name',nspname||'.'||proname,
   'args',pg_get_function_identity_arguments(oid),'definition_md5',md5(pg_get_functiondef(oid)),
   'owner',pg_get_userbyid(proowner),'security_definer',prosecdef,'config',proconfig,'acl',proacl)
   ORDER BY nspname,proname,pg_get_function_identity_arguments(oid)) FROM functions),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('table',conrelid::regclass::text,
   'name',conname,'definition',pg_get_constraintdef(oid),'validated',convalidated) ORDER BY conrelid::regclass::text,conname)
   FROM pg_constraint WHERE conrelid IN (SELECT oid FROM relations)),
 'indexes',(SELECT jsonb_agg(jsonb_build_object('table',i.indrelid::regclass::text,
   'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid) ORDER BY i.indexrelid::regclass::text)
   FROM pg_index i WHERE i.indrelid IN (SELECT oid FROM relations)),
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname)
   FROM pg_policies p WHERE schemaname IN ('public','fitmatch_catalog','fitmatch_vnext')),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,
   'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) ORDER BY t.tgrelid::regclass::text,t.tgname)
   FROM pg_trigger t WHERE NOT t.tgisinternal AND (t.tgrelid IN (SELECT oid FROM relations)
   OR (t.tgrelid='auth.users'::regclass AND t.tgfoid IN (SELECT oid FROM functions)))),
 'views',(SELECT jsonb_agg(jsonb_build_object('name',nspname||'.'||relname,'definition',pg_get_viewdef(oid,true)) ORDER BY nspname,relname)
   FROM relations WHERE relkind IN ('v','m')),
 'extensions',(SELECT jsonb_agg(jsonb_build_object('name',e.extname,'version',e.extversion,'schema',n.nspname) ORDER BY e.extname)
   FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace)
);
