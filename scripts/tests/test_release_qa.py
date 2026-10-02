"""Runner safety/reporting tests, not product behavior tests."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('release_qa', Path(__file__).resolve().parents[1] / 'release_qa.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

class RunnerTests(unittest.TestCase):
    def test_cleanup_cannot_start_without_explicit_ledger_and_sessions(self):
        self.assertTrue(callable(getattr(module, 'run_swift_cleanup', None)))
        with tempfile.TemporaryDirectory() as temp, patch.dict(module.os.environ, {}, clear=True), \
             patch.object(module, 'logged') as logged:
            report={'mode':'cleanup','results':[]}
            module.run_swift_cleanup(report,Path(temp),None)
            logged.assert_not_called()
            self.assertEqual(report['results'][-1]['status'],'BLOCKED')

    def test_cleanup_receipt_cannot_impersonate_a_test_run(self):
        self.assertTrue(callable(getattr(module,'cleanup_receipt_status',None)))
        receipt={'status':'PASS','project':'hnkplvyegonlhumlejst','run_id':'current',
                 'cleanup':'PASS: no active owned rows','swift_owner_proof':True,
                 'evidence_kind':'authenticated_swift_ledger_cleanup',
                 'cases':[{'id':'AUTH-VERIFY','status':'PASS'},
                          {'id':'LEDGER-CLEANUP','status':'PASS'}]}
        self.assertEqual(module.cleanup_receipt_status(receipt,'current'),'PASS')
        for change in [{'evidence_kind':'authenticated_swift'}, {'cleanup':'BLOCKED'},
                       {'run_id':'stale'}, {'cases':[]}]:
            self.assertNotEqual(module.cleanup_receipt_status({**receipt,**change},'current'),'PASS')

    def test_interrupted_cleanup_always_persists_blocked_report(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch('sys.argv',['release_qa.py','cleanup','--output',temp]), \
                 patch.object(module,'run_swift_cleanup',side_effect=KeyboardInterrupt):
                code=module.main()
            self.assertNotEqual(code,0)
            report=json.loads((Path(temp)/'results.json').read_text())
            self.assertEqual(report['overall'],'BLOCKED')
            self.assertTrue(any(r['id']=='run.interrupted' for r in report['results']))

    def test_malformed_cleanup_receipt_cannot_escape_reporting(self):
        for receipt in [None, [], 'PASS', 123]:
            self.assertEqual(module.cleanup_receipt_status(receipt,'current'),'BLOCKED')

    def test_matrix_receipt_rejects_stale_binding_even_with_all_case_ids(self):
        binding=json.loads((module.DOC/'matrix-binding-v2.json').read_text())
        ids=binding['smoke_case_ids']
        receipt={'mode':'smoke','cases':[{'id':i,'status':'PASS'} for i in ids],
                 'binding_sha256':'stale-binding','corpus_sha256':binding['corpus_sha256'],
                 'evidence_scope':'synthetic_production_owner_probe'}
        with tempfile.TemporaryDirectory() as temp:
            (Path(temp)/'matrix-smoke.json').write_text(json.dumps(receipt))
            report={'results':[]}
            module.record_matrix_receipt(report,Path(temp),'smoke')
            self.assertEqual(report['results'][0]['status'],'FAIL')

    def test_case_receipt_requires_exact_unique_coverage(self):
        self.assertTrue(callable(getattr(module, 'validate_case_receipt', None)),
                        'Execution receipts must be validated, not treated as a completed matrix')
        self.assertEqual(module.validate_case_receipt({'cases':[
            {'id':'one','status':'PASS'}, {'id':'two','status':'PASS'}]}, ['one','two']), 'PASS')
        for cases in [[], [{'id':'one','status':'PASS'}]]:
            self.assertEqual(module.validate_case_receipt({'cases':cases}, ['one','two']), 'BLOCKED')
        for cases in [
            [{'id':'one','status':'PASS'}, {'id':'one','status':'PASS'}],
            [{'id':'one','status':'PASS'}, {'id':'unrequested','status':'PASS'}],
            [{'id':'one','status':'PASS'}, {'id':'two','status':'UNKNOWN'}],
        ]:
            self.assertEqual(module.validate_case_receipt({'cases':cases}, ['one','two']), 'FAIL')

    def test_case_receipt_propagates_failed_and_unexecuted_cases(self):
        self.assertTrue(callable(getattr(module, 'validate_case_receipt', None)))
        for state, expected in [('FAIL','FAIL'),('BLOCKED','BLOCKED'),('NOT RUN','BLOCKED')]:
            self.assertEqual(module.validate_case_receipt({'cases':[
                {'id':'one','status':'PASS'}, {'id':'two','status':state}]}, ['one','two']), expected)
        self.assertEqual(module.validate_case_receipt({'cases':[]}, []), 'FAIL')

    def test_authenticated_swift_never_starts_without_dedicated_sessions(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(module.os.environ, {}, clear=True), \
             patch.object(module, 'logged') as logged:
            report={'results':[], 'app_test_summary':{'passedTests':1}}
            module.run_authenticated_swift(report, Path(temp), 'smoke')
            logged.assert_not_called()
            self.assertEqual(report['results'][0]['status'],'BLOCKED')

    def test_matrix_receipt_missing_cannot_be_reported_as_executed(self):
        with tempfile.TemporaryDirectory() as temp:
            report={'results':[]}
            module.record_matrix_receipt(report, Path(temp), 'smoke')
            self.assertEqual(report['results'][0]['id'],'matrix.synthetic_coverage')
            self.assertEqual(report['results'][0]['status'],'BLOCKED')

    def test_authenticated_receipt_requires_current_run_subcases_and_cleanup(self):
        self.assertTrue(callable(getattr(module,'authenticated_receipt_status',None)))
        valid={'status':'PASS','project':'hnkplvyegonlhumlejst','run_id':'run-current',
               'cleanup':'PASS: run-owned rows absent','swift_owner_proof':True,
               'cases':[{'id':'AUTH-VERIFY','status':'PASS'},{'id':'A','status':'PASS'}]}
        self.assertEqual(module.authenticated_receipt_status(valid,'run-current',['AUTH-VERIFY','A']),'PASS')
        for replacement in [{'run_id':'stale'},{'cleanup':'BLOCKED'},{'cases':[]},
                            {'project':'aqhrupgjpmrtnystottx'},{'swift_owner_proof':False}]:
            self.assertNotEqual(module.authenticated_receipt_status(
                {**valid,**replacement},'run-current',['AUTH-VERIFY','A']),'PASS')
        self.assertNotEqual(module.authenticated_receipt_status({'status':'PASS'},'run-current',['AUTH-VERIFY','A']),'PASS')

    def test_missing_or_unknown_mode_cannot_report_success(self):
        for mode in [None, 'unexpected']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                report = {'run_id':'invalid-mode', 'results':[{'id':'tool.python3','status':'PASS'}]}
                if mode is not None:
                    report['mode'] = mode
                self.assertNotEqual(module.write_report(Path(temp), report), 0)
                self.assertEqual(report['overall'], 'FAIL')

    def test_interrupted_output_is_rejected_before_any_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'live-parser.json').write_text('[{"status":"PARSED_WITH_MEASUREMENTS"}]')
            with patch('sys.argv', ['release_qa.py','smoke','--output',temp]), \
                 patch.object(module,'preflight') as preflight, \
                 patch.object(module,'logged', return_value=1), \
                 patch.object(module,'run_xcode'), patch.object(module,'run_db'):
                with self.assertRaises(SystemExit) as error:
                    module.main()
                self.assertEqual(error.exception.code, 2)
                preflight.assert_not_called()
            self.assertFalse((root/'results.json').exists())

    def test_all_incomplete_statuses_fail_closed(self):
        for status in ['FAIL', 'BLOCKED', 'NOT RUN', 'UNRESOLVED']:
            self.assertNotEqual(module.overall_exit([{'status': status}]), 0)
        self.assertEqual(module.overall_exit([{'status': 'PASS'}]), 0)
        self.assertNotEqual(module.overall_exit([]), 0)

    def test_prod_or_lookalike_host_rejected(self):
        self.assertTrue(module.safe_database_url('https://hnkplvyegonlhumlejst.supabase.co'))
        for url in ['https://aqhrupgjpmrtnystottx.supabase.co', 'https://hnkplvyegonlhumlejst.supabase.co.evil.test', 'http://hnkplvyegonlhumlejst.supabase.co', 'https://user:secret@hnkplvyegonlhumlejst.supabase.co']:
            self.assertFalse(module.safe_database_url(url))

    def test_zero_or_skipped_tests_not_pass(self):
        self.assertEqual(module.xcode_status(0, {'passedTests': 2, 'failedTests': 0, 'skippedTests': 0, 'totalTestCount': 2}), 'PASS')
        self.assertEqual(module.xcode_status(0, {'passedTests': 0, 'failedTests': 0, 'skippedTests': 0}), 'BLOCKED')
        self.assertEqual(module.xcode_status(0, {'passedTests': 2, 'failedTests': 0, 'skippedTests': 1}), 'BLOCKED')
        self.assertEqual(module.xcode_status(65, {'passedTests': 1, 'failedTests': 1}), 'FAIL')

    def test_corpus_edit_requires_new_lock(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'data.json').write_text('{}')
            digest = hashlib.sha256(b'{}').hexdigest()
            (root/'SHA256SUMS').write_text(digest+'  data.json\n')
            self.assertEqual(module.verify_lock(root/'SHA256SUMS'), [])
            (root/'data.json').write_text('{"silently_changed":true}')
            self.assertTrue(module.verify_lock(root/'SHA256SUMS'))

    def test_controlled_fault_fails_report(self):
        records = [{'id':'A','status':'PASS'}, {'id':'fault','status':'FAIL'}]
        with tempfile.TemporaryDirectory() as temp:
            code = module.write_report(Path(temp), {'run_id':'isolated-tool-test', 'results':records})
            self.assertNotEqual(code, 0)
            self.assertEqual(json.loads((Path(temp)/'results.json').read_text())['overall'], 'FAIL')
            self.assertIn('fault', (Path(temp)/'report.md').read_text())

    def test_full_report_cannot_pass_with_missing_required_cases(self):
        with tempfile.TemporaryDirectory() as temp:
            code = module.write_report(Path(temp), {'run_id':'full-incomplete', 'mode':'full', 'results':[{'id':'tool.python3','status':'PASS'}]})
            self.assertNotEqual(code, 0)

    def test_empty_lock_is_not_frozen(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)/'SHA256SUMS'; p.write_text('')
            self.assertTrue(module.verify_lock(p))

    def test_swift_testing_selector_has_parentheses(self):
        self.assertEqual(module.xcode_selector('FitMatchTests/Suite/testOne'), 'FitMatchTests/Suite/testOne()')
        self.assertEqual(module.xcode_selector('FitMatchTests/Suite'), 'FitMatchTests/Suite')

    def test_discovery_errors_are_not_success(self):
        self.assertFalse(module.discovery_valid({'errors':['app crashed'], 'values':[]}, ['FitMatchTests/Suite/testOne']))
        self.assertFalse(module.discovery_valid({}, ['FitMatchTests/Suite/testOne']))

    def test_forwarded_production_override_rejected(self):
        self.assertFalse(module.safe_overrides({'TEST_RUNNER_FITMATCH_SUPABASE_URL':'https://aqhrupgjpmrtnystottx.supabase.co'}))
        self.assertFalse(module.safe_overrides({'TEST_RUNNER_FITMATCH_QA_DB_URL':'https://aqhrupgjpmrtnystottx.supabase.co'}))
        self.assertTrue(module.safe_overrides({}))

    def test_redacts_credentials(self):
        self.assertNotIn('abcdef', module.redact('Authorization: Bearer abcdef'))
        self.assertNotIn('person@example.com', module.redact('person@example.com'))

if __name__ == '__main__': unittest.main()
