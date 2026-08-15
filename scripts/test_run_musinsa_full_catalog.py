import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("run-musinsa-full-catalog.py")
SPEC = importlib.util.spec_from_file_location("run_musinsa_full_catalog", MODULE_PATH)
assert SPEC and SPEC.loader
batch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = batch
SPEC.loader.exec_module(batch)


class MusinsaFullCatalogTests(unittest.TestCase):
    def test_json_category_page_parses_products_and_signed_next_url(self):
        payload = {"data": {"list": [{"goodsNo": 123, "goodsName": "티셔츠"}], "pagination": {
            "page": 2, "totalPages": 3, "hasNext": True, "nextPageUrl": "https://api.musinsa.com/signed-page-3"
        }}}
        products, pagination = batch.parse_category_response(json.dumps(payload).encode(), "application/json")
        self.assertEqual(products[0]["goodsNo"], 123)
        self.assertEqual(pagination["nextPageUrl"], "https://api.musinsa.com/signed-page-3")

    def test_discovery_page_is_resumable_in_sqlite(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "state.sqlite3"
            connection = batch.connect(database)
            batch.initialize_categories(connection, ["001001"], False)
            batch.record_discovery_page(
                connection,
                "001001",
                1,
                [{"goodsNo": 123, "goodsName": "티셔츠", "goodsLinkUrl": "https://www.musinsa.com/products/123"}],
                {"hasNext": True, "nextPageUrl": "https://api.musinsa.com/signed-page-2", "totalPages": 2},
            )
            category = connection.execute("SELECT * FROM categories WHERE category_code='001001'").fetchone()
            product_count = connection.execute("SELECT COUNT(*) FROM products").fetchone()[0]
            connection.close()

        self.assertEqual(category["next_page"], 2)
        self.assertEqual(category["next_url"], "https://api.musinsa.com/signed-page-2")
        self.assertEqual(product_count, 1)

    def test_discovery_defers_failed_category_and_continues_with_next(self):
        with tempfile.TemporaryDirectory() as directory:
            connection = batch.connect(Path(directory) / "state.sqlite3")
            batch.initialize_categories(connection, ["001001", "001002"], False)
            good_page = json.dumps({"data": {"list": [{"goodsNo": 456}], "pagination": {
                "hasNext": False, "nextPageUrl": "", "totalPages": 1
            }}}).encode()
            with mock.patch.object(batch, "fetch", side_effect=[(b"not a product page", 200, "https://example.test/1"), (good_page, 200, "https://api.musinsa.com/2")]):
                fetched = batch.discover(connection, batch.RateLimiter(0), 0, 0)
            first = connection.execute("SELECT * FROM categories WHERE category_code='001001'").fetchone()
            second = connection.execute("SELECT * FROM categories WHERE category_code='001002'").fetchone()
            connection.close()

        self.assertEqual(fetched, 1)
        self.assertIsNotNone(first["last_error"])
        self.assertEqual(second["completed"], 1)

    def test_complete_index_does_not_require_every_product_detail(self):
        with tempfile.TemporaryDirectory() as directory:
            connection = batch.connect(Path(directory) / "state.sqlite3")
            batch.initialize_categories(connection, ["001001"], False)
            batch.record_discovery_page(
                connection,
                "001001",
                1,
                [{"goodsNo": 789, "goodsName": "미수집 상세 상품"}],
                {"hasNext": False, "nextPageUrl": "", "totalPages": 1},
            )
            summary = batch.summary_data(connection)
            connection.close()

        self.assertTrue(summary["index_complete"])
        self.assertFalse(summary["detail_collection_complete"])
        self.assertTrue(summary["collection_complete"])


if __name__ == "__main__":
    unittest.main()
