#!/usr/bin/env python3
"""Read-only FitMatch source export. Never connects to or restores Production."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'supabase/production-bootstrap'
SOURCE = 'hnkplvyegonlhumlejst'
TARGET = 'aqhrupgjpmrtnystottx'


def validate_endpoint(host, user):
    direct = host == f'db.{SOURCE}.supabase.co' and user == 'postgres'
    pooler = bool(re.fullmatch(r'[a-z0-9-]+\.pooler\.supabase\.com', host or '')) and user == f'postgres.{SOURCE}'
    if not (direct or pooler):
        raise ValueError('Only the exact development project direct/session-pooler endpoint is allowed.')


def load_manifest():
    manifest = json.loads((CONFIG / 'manifest.json').read_text())
    names = [row['table'] for row in manifest['tables']]
    if manifest['source_project'] != SOURCE or manifest['target_project'] != TARGET:
        raise ValueError('Project manifest mismatch.')
    if len(names) != 38 or len(set(names)) != len(names):
        raise ValueError('Expected 38 distinct audited tables; re-audit schema drift.')
    for row in manifest['tables']:
        if not re.fullmatch(r'(public|fitmatch_catalog|fitmatch_vnext)\.[a-z_]+', row['table']):
            raise ValueError('Invalid table identity.')
        if row['reference_candidate_export'] != (row['data_class'] in ('reference', 'catalog_evidence')):
            raise ValueError('Unsafe reference-data allowlist.')
    return manifest


def dump_command(binary, connection, output, manifest, with_reference_data):
    command = [str(binary), *connection, '--no-password', '--format=custom',
               '--strict-names', '--lock-wait-timeout=15s', '--no-publications',
               '--no-subscriptions', '--file', str(output)]
    for schema in ('public', 'fitmatch_catalog', 'fitmatch_vnext'):
        command += ['--schema', schema]
    if with_reference_data:
        # One pg_dump snapshot contains schema plus the bounded candidate data.
        for row in manifest['tables']:
            if not row['reference_candidate_export']:
                command += ['--exclude-table-data', row['table']]
    else:
        command += ['--schema-only']
    return command


def safe_environment(passfile):
    path = Path(passfile).expanduser()
    if not path.is_file() or path.stat().st_mode & 0o077:
        raise ValueError('Configure a local .pgpass/PGPASSFILE with permission 0600; do not send the password in chat.')
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    env.update(PGPASSFILE=str(path.resolve()), PGSSLMODE='require', PGCONNECT_TIMEOUT='15',
               PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=120000')
    return env


def run(command, env=None):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=300)
    if result.returncode:
        # No connection strings, raw command output, or credentials in shared logs.
        raise RuntimeError(f'{Path(command[0]).name} failed (exit {result.returncode}); no restore was attempted.')
    return result.stdout


def validate_inventory(inventory, manifest):
    actual = {r['name'] for r in inventory['relations'] if r['kind'] in ('r', 'p')}
    expected = {r['table'] for r in manifest['tables']}
    if actual != expected or len(inventory['functions']) != 128 or inventory['server_major'] != 17:
        raise ValueError('Source schema changed from audited scope; stop and update the manifest.')
    auth = [t for t in inventory['triggers'] if t['table'] == 'auth.users']
    if len(auth) != 1 or auth[0]['name'] != 'on_auth_user_created' or auth[0]['enabled'] != 'O':
        raise ValueError('Auth trigger changed; review before export.')
    return auth[0]['definition'] + ';\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', action='store_true', help='Without this flag, print the plan only.')
    parser.add_argument('--host')
    parser.add_argument('--user')
    parser.add_argument('--pg-bin', default='/usr/local/opt/postgresql@17/bin')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--with-reference-data', action='store_true', help='INCOMPLETE 19-table reference candidate, never a complete production seed.')
    args = parser.parse_args()
    manifest = load_manifest()
    if not args.export:
        print(json.dumps({'mode':'PLAN ONLY', 'source':SOURCE, 'target_not_connected':TARGET,
                          'tables':38, 'functions':128, 'reference_candidate_tables':19,
                          'ready_for_production':False}, indent=2))
        return
    validate_endpoint(args.host, args.user)
    if args.output is None:
        raise ValueError('--output is required and must be a new directory outside the repository.')
    output = args.output.expanduser().resolve()
    if output == ROOT or ROOT in output.parents or output.exists():
        raise ValueError('Use a new output directory outside the repository; existing files are never overwritten.')
    env = safe_environment(os.environ.get('PGPASSFILE', str(Path.home() / '.pgpass')))
    binaries = {name: Path(args.pg_bin) / name for name in ('pg_dump','pg_restore','psql')}
    for binary in binaries.values():
        if not re.search(r'\b17\.', run([str(binary), '--version'])):
            raise ValueError('Use PostgreSQL 17 tools for the PostgreSQL 17 target.')
    connection = ['--host',args.host,'--port','5432','--username',args.user,'--dbname','postgres']
    psql = [str(binaries['psql']), *connection, '--no-password','-X','-qAt','-v','ON_ERROR_STOP=1']
    inventory_sql = (CONFIG / 'inventory.sql').read_text()
    before = json.loads(run([*psql,'--command',inventory_sql],env))
    auth_sql = validate_inventory(before,manifest)
    if args.with_reference_data:
        count = run([*psql,'--file',str(CONFIG / 'seed-preflight.sql')],env).strip()
        if count != '0':
            raise ValueError('Catalog evidence now references auth users; reference export needs review.')
    os.umask(0o077)
    output.mkdir(mode=0o700,parents=True)
    # A failed/partial bundle never receives READY or manifest/checksum success.
    (output / 'NOT_READY_FOR_PRODUCTION.txt').write_text(
        'Preparation only. Observation evidence seed selection and isolated restore are pending.\n'
        'No Production restore, migration ledger import, or Edge deployment is authorized by this bundle.\n')
    archive = output / ('source.reference-candidate.dump' if args.with_reference_data else 'source.schema.dump')
    run(dump_command(binaries['pg_dump'],connection,archive,manifest,args.with_reference_data),env)
    after = json.loads(run([*psql,'--command',inventory_sql],env))
    if before != after:
        raise ValueError('Source metadata changed during export. Partial bundle is not valid; re-export after a change freeze.')
    (output / 'source-inventory.json').write_text(json.dumps(before,indent=2)+'\n')
    (output / 'auth-trigger.sql').write_text('-- Exact source trigger; restore only after public.handle_new_user and profiles.\n'+auth_sql)
    (output / 'archive.toc').write_text(run([str(binaries['pg_restore']),'--list',str(archive)]))
    run([str(binaries['pg_restore']),'--schema-only','--file',str(output / 'schema-review.sql'),str(archive)])
    (output / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    checksums = {f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in output.iterdir() if f.is_file()}
    (output / 'SHA256.json').write_text(json.dumps(checksums,indent=2)+'\n')
    print('Source export complete; production readiness remains FALSE. No target connection was made.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError,RuntimeError,OSError,subprocess.TimeoutExpired) as error:
        if isinstance(error, OSError):
            print('BLOCKED: required local file/tool could not be accessed.',file=sys.stderr)
        elif isinstance(error, subprocess.TimeoutExpired):
            print('BLOCKED: export/query timed out; any partial bundle is not ready.',file=sys.stderr)
        else:
            print(f'BLOCKED: {error}',file=sys.stderr)
        sys.exit(1)
