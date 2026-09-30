import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('exporter',ROOT/'scripts/prepare-production-dump.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class ExportSafetyTests(unittest.TestCase):
    def test_source_direct_and_session_pooler(self):
        M.validate_endpoint(f'db.{M.SOURCE}.supabase.co','postgres')
        M.validate_endpoint('aws-0-ap-northeast-2.pooler.supabase.com',f'postgres.{M.SOURCE}')

    def test_production_and_wrong_project_rejected(self):
        for host,user in [(f'db.{M.TARGET}.supabase.co','postgres'),
                          ('aws-0-ap-northeast-2.pooler.supabase.com',f'postgres.{M.TARGET}'),
                          ('localhost','postgres'),(None,None)]:
            with self.assertRaises(ValueError): M.validate_endpoint(host,user)

    def test_schema_only_has_no_data(self):
        cmd=M.dump_command('pg_dump',[],Path('out.dump'),M.load_manifest(),False)
        self.assertIn('--schema-only',cmd)
        self.assertNotIn('--clean',cmd)
        self.assertNotIn('--create',cmd)
        self.assertNotIn('--no-privileges',cmd)

    def test_reference_export_excludes_users_research_pending_evidence(self):
        manifest=M.load_manifest()
        cmd=M.dump_command('pg_dump',[],Path('out.dump'),manifest,True)
        excluded={cmd[i+1] for i,v in enumerate(cmd) if v=='--exclude-table-data'}
        self.assertEqual(len(excluded),19)
        for row in manifest['tables']:
            self.assertEqual(row['table'] in excluded,not row['reference_candidate_export'])
        self.assertIn('public.profiles',excluded)
        self.assertIn('fitmatch_vnext.product_ingestion_receipts',excluded)
        self.assertNotIn('--schema-only',cmd)

    def test_environment_is_read_only_and_ignores_connection_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'pass';path.touch(mode=0o600)
            old=os.environ.get('PGSERVICE')
            try:
                os.environ['PGSERVICE']='wrong-target'
                env=M.safe_environment(str(path))
                self.assertNotIn('PGSERVICE',env)
                self.assertIn('default_transaction_read_only=on',env['PGOPTIONS'])
                self.assertEqual(env['PGSSLMODE'],'require')
            finally:
                if old is None: os.environ.pop('PGSERVICE',None)
                else: os.environ['PGSERVICE']=old

    def test_unprotected_passfile_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'pass';path.touch();path.chmod(0o644)
            with self.assertRaises(ValueError): M.safe_environment(str(path))

    def test_incomplete_manifest_never_claims_ready(self):
        manifest=M.load_manifest()
        self.assertFalse(manifest['ready_for_production'])
        self.assertFalse(manifest['reference_candidate_is_complete'])
        self.assertEqual(sum(r['reference_candidate_export'] for r in manifest['tables']),19)


if __name__=='__main__': unittest.main()
