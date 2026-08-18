import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("run-uniqlo-incremental-catalog.py")
SPEC = importlib.util.spec_from_file_location("run_uniqlo_incremental_catalog", SCRIPT)
runner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runner)


class UniqloIncrementalCatalogTests(unittest.TestCase):
    def test_incomplete_discovery_does_not_report_missing_and_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkpoint = root / "discovery" / "checkpoint.json"
            checkpoint.parent.mkdir(parents=True)
            checkpoint.write_text(json.dumps({
                "sources": {
                    "uniqlo": {
                        "audiences": {
                            audience: {"discovered_products": {}}
                            for audience in runner.AUDIENCES
                        }
                    }
                }
            }), encoding="utf-8")
            (checkpoint.parent / "discovery_summary.json").write_text(json.dumps({
                "discovery_complete": False,
                "category_response_mismatches": 3,
                "category_response_failures": 1,
            }), encoding="utf-8")
            state = root / "state.json"
            state.write_text(json.dumps({
                "version": 1,
                "source": "uniqlo_kr",
                "products": {
                    "E123456": {
                        "status": "stored",
                        "first_seen_at": "2026-08-15T00:00:00+00:00",
                        "last_seen_at": "2026-08-15T00:00:00+00:00",
                        "observed_ids": ["E123456-000"],
                        "product_name": "기존 상품",
                        "canonical_url": "https://www.uniqlo.com/kr/ko/products/E123456-000",
                    }
                },
                "last_run": None,
            }), encoding="utf-8")

            arguments = [
                str(SCRIPT),
                "--state", str(state),
                "--run-root", str(root / "runs"),
                "--run-id", "incomplete",
                "--checkpoint", str(checkpoint),
                "--no-fetch-new",
                "--no-db-sync",
            ]
            with mock.patch.object(sys, "argv", arguments):
                self.assertEqual(runner.main(), 2)

            summary = json.loads(
                (root / "runs/incomplete/summary.json").read_text(encoding="utf-8")
            )
            self.assertFalse(summary["discovery_complete"])
            self.assertIsNone(summary["not_seen_this_run"])
            missing_rows = (root / "runs/incomplete/missing_product_ids.csv").read_text(
                encoding="utf-8-sig"
            ).splitlines()
            self.assertEqual(len(missing_rows), 1)


if __name__ == "__main__":
    unittest.main()
