"""Release orchestration safety, not live product evidence."""
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / 'fitmatch_release_gate.py'
module = None
if PATH.exists():
    spec = importlib.util.spec_from_file_location('fitmatch_release_gate', PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)


class ReleaseGateTests(unittest.TestCase):
    def test_required_evidence_cannot_be_missing_or_skipped(self):
        self.assertIsNotNone(module, 'Single release gate is not implemented')
        self.assertEqual(module.overall([]), 'NOT RUN')
        records = [{'id': key, 'status': 'PASS'} for key in module.REQUIRED]
        self.assertEqual(module.overall(records), 'PASS')
        self.assertEqual(module.overall(records[:-1]), 'NOT RUN')
        for status in ('FAIL', 'BLOCKED', 'NOT RUN'):
            with self.subTest(status=status):
                changed = records[:-1] + [{'id': records[-1]['id'], 'status': status}]
                self.assertEqual(module.overall(changed), status)

    def test_failed_optional_probe_is_not_hidden(self):
        self.assertIsNotNone(module)
        records = [{'id': key, 'status': 'PASS'} for key in module.REQUIRED]
        records.append({'id': 'extra', 'status': 'FAIL'})
        self.assertEqual(module.overall(records), 'FAIL')

    def test_duplicate_or_unknown_state_fails_closed(self):
        self.assertIsNotNone(module)
        records = [{'id': key, 'status': 'PASS'} for key in module.REQUIRED]
        self.assertEqual(module.overall(records + [records[0]]), 'FAIL')
        self.assertEqual(module.overall(records + [{'id': 'extra', 'status': 'SKIPPED'}]), 'FAIL')

    def test_protected_scroll_checks_file_and_call_sites(self):
        self.assertIsNotNone(module)
        self.assertTrue(module.protected_diff('M\tFitMatch/Components/TabBarScrollVisibilityModifier.swift', ''))
        self.assertTrue(module.protected_diff('', '+ .hidesBottomTabBarOnScroll(tab: .history)'))
        self.assertTrue(module.protected_diff('', '- .hidesTopChromeOnScroll()'))
        self.assertFalse(module.protected_diff('M\tDocs/README.md', '+ plain documentation'))


if __name__ == '__main__':
    unittest.main()
