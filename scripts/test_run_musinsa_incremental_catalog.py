import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("run-musinsa-incremental-catalog.py")
SPEC = importlib.util.spec_from_file_location("run_musinsa_incremental_catalog", MODULE_PATH)
assert SPEC and SPEC.loader
batch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = batch
SPEC.loader.exec_module(batch)


class MusinsaIncrementalCatalogTests(unittest.TestCase):
    def test_initial_state_keeps_only_musinsa_products(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            manifest.write_text(json.dumps({"products": [
                {"source": "musinsa", "product_key": "123", "product_name": "셔츠"},
                {"source": "uniqlo", "product_key": "E456", "product_name": "팬츠"},
            ]}), encoding="utf-8")
            state = batch.initialize_state([manifest])

        self.assertEqual(set(state["products"]), {"123"})
        self.assertEqual(state["products"]["123"]["canonical_url"], "https://www.musinsa.com/products/123")

    def test_observations_preserve_all_exposure_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "checkpoint.json"
            checkpoint.write_text(json.dumps({
                "sources": {"musinsa": {"discovered_products": {
                    "123": ["https://www.musinsa.com/category/002/goods?gf=A", "https://www.musinsa.com/category/001/goods?gf=A"]
                }}}
            }), encoding="utf-8")
            rows = batch.observations(checkpoint)

        self.assertEqual(set(rows), {"123"})
        self.assertEqual(rows["123"]["exposure_urls"], sorted(rows["123"]["exposure_urls"]))


if __name__ == "__main__":
    unittest.main()
