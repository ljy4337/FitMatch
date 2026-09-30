#!/usr/bin/env python3
"""Build a reviewable, staged SQL bundle from the captured MCP source snapshot.

Does not connect to any database. Run the resulting files only after verification.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROLES = ['PUBLIC','anon','authenticated','service_role','supabase_auth_admin','postgres']
PRIVS = {'r':'SELECT','a':'INSERT','w':'UPDATE','d':'DELETE','D':'TRUNCATE',
         'x':'REFERENCES','t':'TRIGGER','m':'MAINTAIN','U':'USAGE','C':'CREATE','X':'EXECUTE'}


def ident(value):
    return '"'+value.replace('"','""')+'"'


def qualified(value):
    return '.'.join(ident(v) for v in value.split('.'))


def literal(value):
    return "'"+value.replace("'","''")+"'"


def role(value):
    return 'PUBLIC' if value in ('','PUBLIC') else ident(value)


def grants(kind, target, acl, owner='postgres'):
    # Source NULL ACL has built-in owner defaults and PUBLIC EXECUTE for functions.
    if acl is None:
        defaults = {'FUNCTION':'X','TABLE':'arwdDxtm','SEQUENCE':'rwU','SCHEMA':'UC'}
        acl = [owner+'='+defaults[kind]+'/'+owner]
        if kind == 'FUNCTION': acl += ['=X/'+owner]
    sql = [f'REVOKE ALL ON {kind} {target} FROM '+', '.join(role(r) for r in ROLES)+';']
    for entry in acl:
        grantee, tail = entry.split('=',1)
        permissions, grantor = tail.split('/',1)
        if grantor not in ('postgres','pg_database_owner'):
            raise ValueError('Unexpected grantor; explicit review required: '+grantor)
        for code, option in re.findall(r'([A-Za-z])(\*?)',permissions):
            sql.append(f'GRANT {PRIVS[code]} ON {kind} {target} TO {role(grantee)}'+
                       (' WITH GRANT OPTION' if option else '')+';')
    return sql


def build(source, output):
    if output.exists(): raise ValueError('Output already exists; refusing overwrite.')
    captured = json.loads((source/'metadata.json').read_text())
    meta = captured['metadata']
    extra = json.loads((source/'extra-metadata.json').read_text())
    if any(c['acl'] for c in extra['column_settings']):
        raise ValueError('Column grants need explicit support.')
    if any(t['enabled']!='O' for t in meta['triggers']):
        raise ValueError('Nonstandard trigger enablement requires review.')
    options = {r['name']:r for r in extra['relation_options']}
    if any(r['persistence']!='p' for r in options.values()):
        raise ValueError('Non-permanent relation requires review.')
    columns = {}
    for c in meta['columns']:
        table = c['table'] if '.' in c['table'] else 'public.'+c['table']
        columns.setdefault(table,[]).append(c)
    seq = extra['sequence_options'][0]
    assert seq['max']=='9223372036854775807'
    output.mkdir(mode=0o700,parents=True)
    files = []

    def write(name, lines):
        # Each stage is atomic. No stage can make a partially seeded app public.
        body = '\n'.join(['BEGIN;',"SET LOCAL TIME ZONE 'UTC';",
            'SET LOCAL standard_conforming_strings = on;',
            'SET LOCAL search_path = public, extensions;',
            'SET LOCAL check_function_bodies = false;',*lines,'COMMIT;',''])
        path = output/name; path.write_text(body); path.chmod(0o600)
        files.append({'file':name,'sha256':hashlib.sha256(body.encode()).hexdigest(),'bytes':len(body.encode())})

    schema = ["DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','fitmatch_catalog','fitmatch_vnext') AND c.relkind IN ('r','p')) THEN RAISE EXCEPTION 'Target contains app tables; fresh bootstrap only'; END IF; END $$;",
              'CREATE SCHEMA fitmatch_catalog AUTHORIZATION postgres;',
              'CREATE SCHEMA fitmatch_vnext AUTHORIZATION postgres;']
    identities = set()
    for rel in meta['relations']:
        if rel['kind']!='r': continue
        name=rel['name']; defs=[]
        for c in columns[name]:
            if c['generated']: raise ValueError('Generated column needs support.')
            value=ident(c['name'])+' '+c['type']
            if c['identity']:
                assert name=='fitmatch_vnext.size_availability_observations' and c['identity']=='a'
                identities.add(name)
                value+=' GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME '+qualified(seq['name'])+\
                       ' START WITH '+seq['start']+' INCREMENT BY '+seq['increment']+\
                       ' MINVALUE '+seq['min']+' MAXVALUE '+seq['max']+' CACHE '+seq['cache']+\
                       (' CYCLE' if seq['cycle'] else ' NO CYCLE')+')'
            elif c['default'] is not None: value+=' DEFAULT '+c['default']
            if c['not_null']: value+=' NOT NULL'
            defs.append(value)
        schema.append('CREATE TABLE '+qualified(name)+' ('+',\n'.join(defs)+');')
        schema.append('ALTER TABLE '+qualified(name)+' OWNER TO '+ident(rel['owner'])+';')
        if options[name]['options']:
            schema.append('ALTER TABLE '+qualified(name)+' SET ('+','.join(options[name]['options'])+');')
        if rel['rls']: schema.append('ALTER TABLE '+qualified(name)+' ENABLE ROW LEVEL SECURITY;')
        if rel['force_rls']: schema.append('ALTER TABLE '+qualified(name)+' FORCE ROW LEVEL SECURITY;')
        schema.append('REVOKE ALL ON TABLE '+qualified(name)+' FROM PUBLIC,anon,authenticated,service_role;')
    for f in captured['function_definitions']:
        signature=qualified(f['schema']+'.'+f['name'])+'('+f['args']+')'
        schema += [f['definition'].rstrip().rstrip(';')+';', 'ALTER FUNCTION '+signature+' OWNER TO postgres;',
                   'REVOKE ALL ON FUNCTION '+signature+' FROM PUBLIC,anon,authenticated,service_role;']
    for view in meta['views']:
        name=view['name']; opt=options[name]['options'] or []
        schema.append('CREATE VIEW '+qualified(name)+(' WITH ('+','.join(opt)+')' if opt else '')+' AS '+view['definition'])
        schema.append('ALTER VIEW '+qualified(name)+' OWNER TO postgres;')
        schema.append('REVOKE ALL ON TABLE '+qualified(name)+' FROM PUBLIC,anon,authenticated,service_role;')
    write('000_schema_private.sql',schema)

    seed_number=1
    for rel in meta['relations']:
        name=rel['name']; datafile=source/(name+'.json')
        if rel['kind']!='r' or not datafile.exists(): continue
        rows=json.loads(datafile.read_text()); batch=[]; size=0
        def flush():
            nonlocal seed_number,batch,size
            if not batch:return
            payload='['+','.join(batch)+']'
            sql='INSERT INTO '+qualified(name)+(' OVERRIDING SYSTEM VALUE' if name in identities else '')+\
                ' SELECT * FROM jsonb_populate_recordset(NULL::'+qualified(name)+','+literal(payload)+'::jsonb);'
            write(f'{seed_number:03d}_seed.sql',[sql]);seed_number+=1;batch=[];size=0
        for row in rows:
            assert isinstance(row,str)
            if batch and size+len(row.encode())>180000:flush()
            batch.append(row);size+=len(row.encode())
        flush()

    finish=[]
    # Add keys/checks first, then FK constraints once all rows exist.
    constraints=sorted(meta['constraints'],key=lambda c:c['definition'].startswith('FOREIGN'))
    for c in constraints:
        finish.append('ALTER TABLE '+qualified(c['table'])+' ADD CONSTRAINT '+ident(c['name'])+' '+c['definition']+';')
    constraint_indexes={v.split('.')[-1] for v in extra['constraint_indexes']}
    for index in meta['indexes']:
        match=re.match(r'CREATE (?:UNIQUE )?INDEX (\S+) ON ',index['definition'])
        if not match:raise ValueError('Unrecognized index definition.')
        if match[1].strip('"') not in constraint_indexes: finish.append(index['definition']+';')
    for policy in meta['policies']:
        sql='CREATE POLICY '+ident(policy['policyname'])+' ON '+qualified(policy['schemaname']+'.'+policy['tablename'])
        sql+=' AS '+policy['permissive']+' FOR '+policy['cmd']+' TO '+','.join(role(r) for r in policy['roles'])
        if policy['qual'] is not None:sql+=' USING ('+policy['qual']+')'
        if policy['with_check'] is not None:sql+=' WITH CHECK ('+policy['with_check']+')'
        finish.append(sql+';')
    for trigger in meta['triggers']:finish.append(trigger['definition']+';')
    finish.append("SELECT pg_catalog.setval('fitmatch_vnext.size_availability_observations_id_seq',coalesce((SELECT max(id) FROM fitmatch_vnext.size_availability_observations),1),EXISTS(SELECT 1 FROM fitmatch_vnext.size_availability_observations));")
    write('900_constraints_policies_triggers.sql',finish)

    access=[]
    for schema in meta['schemas']:
        access+=grants('SCHEMA',ident(schema['name']),schema['acl'],schema['owner'])
    for rel in meta['relations']:
        access+=grants('SEQUENCE' if rel['kind']=='S' else 'TABLE',qualified(rel['name']),rel['acl'],rel['owner'])
    for f in meta['functions']:
        access+=grants('FUNCTION',qualified(f['name'])+'('+f['args']+')',f['acl'],f['owner'])
    for entry in meta['default_acl']:
        # Platform-owned default ACLs must already match; do not impersonate its role.
        if entry['owner']!='postgres':continue
        kind={'r':'TABLES','S':'SEQUENCES','f':'FUNCTIONS'}[entry['kind']]
        prefix='ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA '+ident(entry['schema'])+' '
        access.append(prefix+'REVOKE ALL ON '+kind+' FROM '+','.join(role(r) for r in ROLES)+';')
        for acl in entry['acl']:
            grantee,tail=acl.split('=',1);permissions,grantor=tail.split('/',1)
            assert grantor=='postgres'
            for code,option in re.findall(r'([A-Za-z])(\*?)',permissions):
                access.append(prefix+'GRANT '+PRIVS[code]+' ON '+kind+' TO '+role(grantee)+(' WITH GRANT OPTION' if option else '')+';')
    write('950_access.sql',access)
    (output/'bundle.json').write_text(json.dumps({'source':'hnkplvyegonlhumlejst','target':'aqhrupgjpmrtnystottx',
        'captured_at':captured['captured_at'],'files':files,'production_applied':False},indent=2)+'\n')
    (output/'bundle.json').chmod(0o600)
    print(f'Prepared {len(files)} SQL stages; no DB connection performed.')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();build(a.source,a.output)
