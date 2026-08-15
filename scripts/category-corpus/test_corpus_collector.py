import csv
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
import urllib.parse
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("corpus_collector.py")
SPEC = importlib.util.spec_from_file_location("corpus_collector", MODULE_PATH)
assert SPEC and SPEC.loader
collector = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = collector
SPEC.loader.exec_module(collector)
LIVE_SMOKE = collector.REPO_ROOT / "Docs/Research/CategoryCorpus-live-smoke"
LIVE_MEDIUM = collector.REPO_ROOT / "Docs/Research/CategoryCorpus-live-medium"
BABY_RAW = LIVE_MEDIUM / "raw/uniqlo/category-pages/8f9b7efaf10ecb94841d.html"


class CategoryCorpusTests(unittest.TestCase):
    def make_live_source_state(self):
        config = collector.read_json(collector.CONFIG_PATH)
        return collector.initial_live_state(config)["sources"]["uniqlo"]

    def resolved_category(self, audience, path="상의 > 티셔츠"):
        return {
            "status": "resolved",
            "audience": audience,
            "path": path,
            "evidence_source": "uniqlo_hydration",
            "unresolved_reason": "",
        }

    def synthetic_baby_product_html(self, observed_id):
        hydration = {
            "entity": {
                "pdpEntity": {
                    f"{observed_id}-00": {
                        "product": {
                            "productId": observed_id,
                            "breadcrumbs": {
                                "gender": {
                                    "id": "57925", "name": "baby",
                                    "locale": "BABY", "level": 1,
                                },
                                "class": {
                                    "id": "57980", "name": "newborn",
                                    "locale": "신생아", "level": 2,
                                },
                                "category": {
                                    "id": "58102", "name": "bodysuits",
                                    "locale": "바디수트", "level": 3,
                                },
                                "subcategory": {
                                    "id": "58675", "name": "short-sleeve",
                                    "locale": "반팔", "level": 4,
                                },
                            },
                        }
                    }
                }
            }
        }
        return (
            "<script>window.__PRELOADED_STATE__ = "
            + json.dumps(hydration)
            + ";</script>"
        ).encode()

    def run_synthetic_probe(self, output, bad_suffix=False):
        plan = collector.baby_probe_plan(LIVE_MEDIUM)
        category_html = (
            '<a href="/kr/ko/baby/newborn/bodysuits">BABY</a>'
            '<a href="/kr/ko/products/E488861-000">product</a>'
        ).encode()
        responses = [
            collector.FetchResult(
                collector.BABY_PROBE_CATEGORY_URL, 200, "text/html", category_html
            )
        ]
        for index, item in enumerate(plan["product_requests"]):
            suffix = "99" if bad_suffix and index == 0 else item["raw_product_id"].rsplit("-", 1)[1]
            responses.append(
                collector.FetchResult(
                    item["url"] + "/" + suffix,
                    200,
                    "text/html",
                    self.synthetic_baby_product_html(item["observed_id"]),
                )
            )

        class FakeFetcher:
            def __init__(self, _delay, _retries, event_handler=None):
                self.event_handler = event_handler
                self.request_count = 0

            def fetch(self, url, referer=None, context=None):
                result = responses[self.request_count]
                self.request_count += 1
                if self.event_handler:
                    self.event_handler(
                        {
                            **(context or {}),
                            "url": url,
                            "final_url": result.url,
                            "attempt": 0,
                            "started_at": "test",
                            "duration_ms": 1,
                            "status": 200,
                            "outcome": "success",
                            "retry_after_seconds": 0,
                        }
                    )
                return result

        args = Namespace(
            output=output,
            medium_dir=LIVE_MEDIUM,
            delay_ms=250,
            retries=2,
        )
        with patch.object(collector, "RateLimitedFetcher", FakeFetcher):
            return collector.baby_probe(args)

    def test_restored_survey_integrity(self):
        result = collector.validate_survey(collector.DEFAULT_SURVEY_DIR)
        self.assertTrue(result["passed"])
        self.assertEqual(result["actual"]["file_count"], 11)
        self.assertEqual(result["actual"]["unique_products"], 300)
        self.assertEqual(result["actual"]["unique_base_products"], 295)
        self.assertEqual(result["actual"]["products_by_source"], {"musinsa": 200, "uniqlo": 100})
        self.assertEqual(
            result["actual"]["unique_category_paths_by_source"],
            {"musinsa": 30, "uniqlo": 5},
        )

    def test_known_db_paths_and_unresolved_rules_are_not_candidates(self):
        config = collector.read_json(collector.CONFIG_PATH)
        for path in (
            "니트 & 가디건",
            "니트 & 가디건 > 니트",
            "니트 & 가디건 > 니트 > 가디건",
        ):
            flags = collector.configured_flags("uniqlo", path, config)
            self.assertTrue(flags["is_existing_source_category"])
            self.assertFalse(flags["is_db_candidate"])

        self.assertEqual(
            collector.configured_flags("musinsa", "속옷/홈웨어 > 여성 속옷 > 브라", config)[
                "unresolved_rule"
            ],
            "bra",
        )
        self.assertEqual(
            collector.configured_flags("uniqlo", "Tops > Shirts", config)["unresolved_rule"],
            "uniqlo_tops_shirts",
        )
        self.assertEqual(
            collector.configured_flags("uniqlo", "니트 > 가디건", config)["unresolved_rule"],
            "uniqlo_cardigan",
        )

    def test_bootstrap_outputs_required_artifacts_without_raw_responses(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with patch.object(
                collector.urllib.request,
                "urlopen",
                side_effect=AssertionError("bootstrap must not access the network"),
            ):
                result = collector.bootstrap(collector.DEFAULT_SURVEY_DIR, output)
            self.assertEqual(result["network_requests"], 0)
            required = {
                "category_inventory.json",
                "product_manifest.json",
                "product_category_paths.csv",
                "category_exposures.csv",
                "unresolved_categories.csv",
                "collection_summary.md",
            }
            self.assertTrue(required.issubset({path.name for path in output.iterdir()}))
            manifest = json.loads((output / "product_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(len(manifest["products"]), 295)
            self.assertEqual(list((output / "raw").glob("*.json")), [])
            self.assertIn("Network requests: 0", (output / "collection_summary.md").read_text())

    def test_product_identity_and_multiple_exposures_remain_distinct(self):
        self.assertEqual(collector.product_identity("musinsa", "6708161"), ("6708161", None))
        self.assertEqual(collector.product_identity("uniqlo", "E484209-000"), ("E484209", "000"))
        self.assertEqual(
            collector.normalized_path("Women / Tops > Shirts"),
            "Women > Tops > Shirts",
        )

    def test_audience_limits_are_enforced_independently(self):
        state = self.make_live_source_state()
        limits = {"MEN": 1, "WOMEN": 2, "KIDS": 1, "BABY": 1}
        self.assertEqual(
            collector.record_uniqlo_audience_result(
                state, "E100001-000", "MEN", self.resolved_category("MEN"), limits
            ),
            ("MEN", True),
        )
        self.assertEqual(
            collector.record_uniqlo_audience_result(
                state, "E100002-000", "MEN", self.resolved_category("MEN"), limits
            ),
            ("MEN", False),
        )
        self.assertFalse(collector.audience_has_capacity(state, "MEN", limits))
        self.assertTrue(collector.audience_has_capacity(state, "WOMEN", limits))
        self.assertEqual(
            collector.record_uniqlo_audience_result(
                state, "E200001-000", "WOMEN", self.resolved_category("WOMEN"), limits
            ),
            ("WOMEN", True),
        )

    def test_queue_audience_mismatch_uses_hydration_audience(self):
        state = self.make_live_source_state()
        limits = {audience: 2 for audience in collector.AUDIENCE_ORDER}
        actual, accepted = collector.record_uniqlo_audience_result(
            state,
            "E300001-000",
            "MEN",
            self.resolved_category("WOMEN"),
            limits,
        )
        self.assertEqual((actual, accepted), ("WOMEN", True))
        self.assertEqual(state["audiences"]["MEN"]["confirmed_products"], [])
        self.assertEqual(state["audiences"]["WOMEN"]["confirmed_products"], ["E300001-000"])
        self.assertEqual(len(state["audience_mismatches"]), 1)

    def test_unknown_audience_is_unresolved_not_counted(self):
        state = self.make_live_source_state()
        limits = {audience: 2 for audience in collector.AUDIENCE_ORDER}
        actual, accepted = collector.record_uniqlo_audience_result(
            state,
            "E400001-000",
            "KIDS",
            {
                "status": "unresolved",
                "audience": "",
                "path": "",
                "evidence_source": "uniqlo_hydration",
                "unresolved_reason": "gender breadcrumb missing",
            },
            limits,
        )
        self.assertEqual((actual, accepted), ("", False))
        self.assertEqual(sum(
            len(value["confirmed_products"]) for value in state["audiences"].values()
        ), 0)
        self.assertEqual(state["unknown_audience_products"][0]["queue_audience"], "KIDS")

    def test_same_base_product_preserves_multiple_audience_observations(self):
        manifests = {}
        first = collector.update_product_manifest(
            manifests,
            "uniqlo",
            "E444557-000",
            {"path": "raw/one.html"},
            {"observed_id": "E444557-000", "actual_audience": "MEN", "path": "상의 > 티셔츠"},
        )
        second = collector.update_product_manifest(
            manifests,
            "uniqlo",
            "E444557-001",
            {"path": "raw/two.html"},
            {"observed_id": "E444557-001", "actual_audience": "WOMEN", "path": "상의 > 티셔츠"},
        )
        self.assertIs(first, second)
        self.assertEqual(len(manifests), 1)
        self.assertEqual(second["observed_ids"], ["E444557-000", "E444557-001"])
        self.assertEqual(
            {item["actual_audience"] for item in second["category_observations"]},
            {"MEN", "WOMEN"},
        )

    def test_resume_preserves_audience_counters(self):
        config = collector.read_json(collector.CONFIG_PATH)
        state = collector.initial_live_state(config)
        state["sources"]["uniqlo"]["audiences"]["MEN"]["confirmed_products"] = ["E1", "E2"]
        state["sources"]["uniqlo"]["audiences"]["BABY"]["confirmed_products"] = ["E3"]
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "checkpoint.json"
            collector.write_json(checkpoint, state)
            loaded = collector.load_live_state(checkpoint, True, config)
        self.assertEqual(
            loaded["sources"]["uniqlo"]["audiences"]["MEN"]["confirmed_products"],
            ["E1", "E2"],
        )
        self.assertEqual(
            loaded["sources"]["uniqlo"]["audiences"]["BABY"]["confirmed_products"],
            ["E3"],
        )

    def test_total_and_audience_limits_both_apply(self):
        state = self.make_live_source_state()
        limits = {"MEN": 1, "WOMEN": 3, "KIDS": 1, "BABY": 1}
        processed = set()
        for observed_id, audience in (
            ("E1", "MEN"),
            ("E2", "MEN"),
            ("E3", "WOMEN"),
            ("E4", "WOMEN"),
        ):
            if len(processed) >= 3:
                break
            collector.record_uniqlo_audience_result(
                state, observed_id, audience, self.resolved_category(audience), limits
            )
            processed.add(observed_id)
        self.assertEqual(len(processed), 3)
        self.assertEqual(len(state["audiences"]["MEN"]["confirmed_products"]), 1)
        self.assertEqual(len(state["audiences"]["WOMEN"]["confirmed_products"]), 1)
        self.assertEqual(len(state["over_quota_observations"]), 1)

    def test_invalid_legacy_checkpoint_is_not_overwritten(self):
        config = collector.read_json(collector.CONFIG_PATH)
        state = {
            "version": 1,
            "sources": {
                "uniqlo": {
                    "queue": ["https://example.invalid/category"],
                    "visited_categories": [],
                    "discovered_products": {},
                    "processed_products": [],
                }
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "checkpoint.json"
            collector.write_json(checkpoint, state)
            before = checkpoint.read_bytes()
            with self.assertRaisesRegex(RuntimeError, "not overwritten"):
                collector.load_live_state(checkpoint, True, config)
            self.assertEqual(checkpoint.read_bytes(), before)

    @unittest.skipUnless(BABY_RAW.is_file(), "saved BABY category raw fixture is unavailable")
    def test_baby_raw_discovers_grounded_child_categories_and_products(self):
        with patch.object(
            collector.urllib.request,
            "urlopen",
            side_effect=AssertionError("BABY offline extraction must not access the network"),
        ):
            evidence = collector.uniqlo_category_page_evidence(
                "https://www.uniqlo.com/kr/ko/baby",
                BABY_RAW.read_bytes(),
            )
        self.assertEqual(evidence["audience"], "BABY")
        self.assertIn(
            "https://www.uniqlo.com/kr/ko/baby/newborn/bodysuits",
            evidence["category_urls"],
        )
        self.assertIn(
            "https://www.uniqlo.com/kr/ko/baby/toddler/tops",
            evidence["category_urls"],
        )
        self.assertEqual(
            evidence["product_ids"],
            ["E481769-000", "E481772-000", "E486367-000", "E488861-000"],
        )
        self.assertTrue(all(
            item["audience"] == "BABY"
            and item["evidence_path"].startswith("cms./home/v2.components.body")
            for item in evidence["cms_product_observations"]
        ))

    @unittest.skipUnless(BABY_RAW.is_file(), "saved BABY category raw fixture is unavailable")
    def test_baby_extraction_excludes_other_audience_links(self):
        evidence = collector.uniqlo_category_page_evidence(
            "https://www.uniqlo.com/kr/ko/baby",
            BABY_RAW.read_bytes(),
        )
        self.assertTrue(evidence["category_urls"])
        self.assertTrue(all(
            collector.audience_from_uniqlo_url(url) == "BABY"
            for url in evidence["category_urls"]
        ))
        self.assertNotIn("https://www.uniqlo.com/kr/ko/men", evidence["category_urls"])
        self.assertNotIn("https://www.uniqlo.com/kr/ko/kids", evidence["category_urls"])

    def test_category_discovery_deduplicates_and_preserves_same_audience_queue(self):
        state = self.make_live_source_state()
        queue = collector.deque()
        visited = {"https://www.uniqlo.com/kr/ko/baby"}
        child = "https://www.uniqlo.com/kr/ko/baby/newborn"
        collector.merge_uniqlo_category_discovery(
            state["audiences"], "BABY", queue, visited, [child, child]
        )
        collector.merge_uniqlo_category_discovery(
            state["audiences"], "BABY", queue, visited, [child]
        )
        self.assertEqual(list(queue), [child])

    def test_resume_preserves_new_baby_queue(self):
        config = collector.read_json(collector.CONFIG_PATH)
        state = collector.initial_live_state(config)
        child = "https://www.uniqlo.com/kr/ko/baby/newborn"
        state["sources"]["uniqlo"]["audiences"]["BABY"]["queue"] = [child]
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "checkpoint.json"
            collector.write_json(checkpoint, state)
            loaded = collector.load_live_state(checkpoint, True, config)
        self.assertEqual(
            loaded["sources"]["uniqlo"]["audiences"]["BABY"]["queue"],
            [child],
        )

    def test_baby_cap_prevents_additional_category_hydration_work(self):
        state = self.make_live_source_state()
        limits = {"MEN": 20, "WOMEN": 20, "KIDS": 10, "BABY": 1}
        state["audiences"]["BABY"]["confirmed_products"] = ["E100000-000"]
        self.assertFalse(collector.audience_has_capacity(state, "BABY", limits))
        self.assertTrue(collector.audience_has_capacity(state, "MEN", limits))

    @unittest.skipUnless(BABY_RAW.is_file(), "saved BABY category raw fixture is unavailable")
    def test_baby_probe_plan_is_fixed_to_one_category_and_original_cms_order(self):
        plan = collector.baby_probe_plan(LIVE_MEDIUM)
        self.assertEqual(plan["logical_request_limit"], 5)
        self.assertEqual(
            plan["category_request"]["url"],
            "https://www.uniqlo.com/kr/ko/baby/newborn/bodysuits",
        )
        self.assertEqual(
            [item["raw_product_id"] for item in plan["product_requests"]],
            [
                "E488861-000-00",
                "E486367-000-00",
                "E481772-000-00",
                "E481769-000-00",
            ],
        )
        self.assertEqual(
            [item["observed_id"] for item in plan["product_requests"]],
            ["E488861-000", "E486367-000", "E481772-000", "E481769-000"],
        )

    def test_baby_probe_rejects_unexpected_final_url(self):
        with self.assertRaisesRegex(collector.CollectionStopped, "Unexpected final URL"):
            collector.validate_probe_result_url(
                "https://www.uniqlo.com/kr/ko/products/E488861-000",
                "https://www.uniqlo.com/kr/ko/products/E999999-000",
            )

    def test_cms_canonical_redirect_validation(self):
        expected = "https://www.uniqlo.com/kr/ko/products/E488861-000"
        allowed = collector.validate_probe_result_url(
            expected,
            expected + "/00",
            "E488861-000-00",
        )
        self.assertTrue(allowed["allowed"])
        self.assertEqual(allowed["variant_suffix"], "00")
        rejected = [
            (expected, "https://www.uniqlo.com/kr/ko/products/E999999-000/00"),
            (expected, expected + "/99"),
            (expected, "https://example.com/kr/ko/products/E488861-000/00"),
            (expected, "https://www.uniqlo.com/jp/ja/products/E488861-000/00"),
            (expected, expected + "/00?variant=00"),
            (expected, expected + "/00#variant"),
        ]
        for requested, final in rejected:
            with self.assertRaises(collector.CollectionStopped):
                collector.validate_probe_result_url(
                    requested, final, "E488861-000-00"
                )
        with self.assertRaises(collector.CollectionStopped):
            collector.validate_probe_result_url(
                expected, expected + "/00", "invalid"
            )

    def test_canonical_variant_selects_matching_later_raw_observation(self):
        observations = [
            {
                "raw_product_id": "E444812-000-01",
                "raw_order": 6,
                "evidence_path": "productIds[6]",
            },
            {
                "raw_product_id": "E444812-000-00",
                "raw_order": 9,
                "evidence_path": "productIds[9]",
            },
        ]
        result = collector.select_canonical_raw_variant(
            "E444812-000", "00", observations
        )
        self.assertFalse(result["unresolved"])
        self.assertEqual(
            [item["raw_product_id"] for item in result["raw_variant_observations"]],
            ["E444812-000-01", "E444812-000-00"],
        )
        self.assertEqual(result["first_observation_id"], "E444812-000-01")
        self.assertEqual(result["selected_observation_id"], "E444812-000-00")
        self.assertEqual(result["selected_observation_raw_order"], 9)
        self.assertFalse(result["selected_first_observation"])
        self.assertEqual(
            result["selection_reason"],
            "canonical_redirect_matches_raw_variant",
        )
        self.assertTrue(result["first_observation_replacement_reason"])

    def test_canonical_variant_selects_first_and_preserves_duplicates(self):
        observations = [
            {"raw_product_id": "E444812-000-01", "raw_order": 2},
            {"raw_product_id": "E444812-000-01", "raw_order": 5},
        ]
        result = collector.select_canonical_raw_variant(
            "E444812-000", "01", observations
        )
        self.assertTrue(result["selected_first_observation"])
        self.assertEqual(result["selected_observation_raw_order"], 2)
        self.assertEqual(len(result["raw_variant_observations"]), 2)
        self.assertEqual(len(result["unselected_observations"]), 1)

    def test_canonical_variant_rejects_unobserved_or_other_base_suffix(self):
        observations = [
            {"raw_product_id": "E444812-000-01", "raw_order": 0},
            {"raw_product_id": "E999999-000-00", "raw_order": 1},
            {"raw_product_id": "invalid", "raw_order": 2},
        ]
        result = collector.select_canonical_raw_variant(
            "E444812-000", "00", observations
        )
        self.assertTrue(result["unresolved"])
        self.assertEqual(result["selected_observation_id"], "")
        self.assertIn("was not observed", result["unresolved_reason"])
        malformed = collector.select_canonical_raw_variant(
            "E444812-000", "00", [{"raw_product_id": "invalid", "raw_order": 0}]
        )
        self.assertTrue(malformed["unresolved"])

    def test_uniqlo_category_href_validation_for_all_audiences(self):
        for audience in ("men", "women", "kids", "baby"):
            page = f"https://www.uniqlo.com/kr/ko/{audience}"
            relative, reason = collector.validated_uniqlo_category_href(
                page, f"/kr/ko/{audience}/tops"
            )
            self.assertEqual(
                relative,
                f"https://www.uniqlo.com/kr/ko/{audience}/tops",
            )
            self.assertEqual(reason, "")
            absolute, reason = collector.validated_uniqlo_category_href(
                page,
                f"https://www.uniqlo.com/kr/ko/{audience}/bottoms?lineup=1",
            )
            self.assertEqual(
                absolute,
                f"https://www.uniqlo.com/kr/ko/{audience}/bottoms?lineup=1",
            )
            self.assertEqual(reason, "")

    def test_uniqlo_category_href_rejects_invalid_components_and_locale_duplication(self):
        page = "https://www.uniqlo.com/kr/ko/baby/newborn"
        rejected = (
            "undefined/kr/ko",
            "/kr/ko/baby/null",
            "/kr/ko/baby/none",
            "/kr/ko/baby/newborn/kr/ko",
            "https://example.com/kr/ko/baby/newborn",
            "http://www.uniqlo.com/kr/ko/baby/newborn",
            "/jp/ja/baby/newborn",
        )
        for href in rejected:
            url, reason = collector.validated_uniqlo_category_href(page, href)
            self.assertIsNone(url, href)
            self.assertTrue(reason, href)

    def test_invalid_uniqlo_anchor_is_evidence_not_category_queue_input(self):
        page = "https://www.uniqlo.com/kr/ko/baby/newborn"
        body = (
            '<a href="/kr/ko/baby/newborn/bodysuits">valid</a>'
            '<a href="undefined/kr/ko">store finder</a>'
        ).encode()
        evidence = collector.uniqlo_category_page_evidence(page, body)
        self.assertEqual(
            evidence["category_urls"],
            ["https://www.uniqlo.com/kr/ko/baby/newborn/bodysuits"],
        )
        self.assertEqual(len(evidence["rejected_category_urls"]), 1)
        rejected = evidence["rejected_category_urls"][0]
        self.assertEqual(rejected["raw_href"], "undefined/kr/ko")
        self.assertIn("undefined/null", rejected["reason"])

    def test_strict_uniqlo_category_evidence_requires_matching_search_route(self):
        requested = "https://www.uniqlo.com/kr/ko/men/tops/t-shirts"
        matching_state = {
            "search": {
                "/v2/men/tops/t-shirts0.0.0": {
                    "search": {"productIds": ["E488001-000-00"]},
                    "pagination": {"count": 1, "total": 1, "offset": 0},
                }
            }
        }
        mismatched_state = {
            "search": {
                "/v2/women/innerwear0.0.0": {
                    "search": {"productIds": ["E499999-000-00"]},
                    "pagination": {"count": 1, "total": 1, "offset": 0},
                }
            }
        }
        matching_body = (
            "<script>window.__PRELOADED_STATE__ = "
            + json.dumps(matching_state)
            + ";</script>"
        ).encode()
        mismatched_body = (
            '<a href="/kr/ko/products/E499999-000">wrong</a>'
            "<script>window.__PRELOADED_STATE__ = "
            + json.dumps(mismatched_state)
            + ";</script>"
        ).encode()

        accepted = collector.strict_uniqlo_category_page_evidence(requested, matching_body)
        rejected = collector.strict_uniqlo_category_page_evidence(requested, mismatched_body)

        self.assertTrue(accepted["response_matches_requested_category"])
        self.assertEqual(accepted["product_ids"], ["E488001-000"])
        self.assertFalse(rejected["response_matches_requested_category"])
        self.assertEqual(rejected["product_ids"], [])

    def test_uniqlo_semantic_retry_url_preserves_path_and_replaces_cache_buster(self):
        original = (
            "https://www.uniqlo.com/kr/ko/men/shirts-and-polo-shirts/casual-shirts"
            "?color=blue&fitmatch_refresh=old"
        )
        retry = collector.uniqlo_semantic_retry_url(original, 2)
        parsed = urllib.parse.urlsplit(retry)
        query = urllib.parse.parse_qs(parsed.query)

        self.assertEqual(
            parsed.path,
            "/kr/ko/men/shirts-and-polo-shirts/casual-shirts",
        )
        self.assertEqual(query["color"], ["blue"])
        self.assertEqual(len(query["fitmatch_refresh"]), 1)
        self.assertTrue(query["fitmatch_refresh"][0].endswith("-2"))

    def test_resume_sanitizes_invalid_queue_and_preserves_rejection_provenance(self):
        state = {
            "sources": {
                "uniqlo": {
                    "audiences": {
                        audience: {
                            "queue": [],
                            "visited_categories": [],
                            "discovered_products": {},
                            "confirmed_products": [],
                        }
                        for audience in collector.AUDIENCE_ORDER
                    }
                }
            },
            "raw_records": [],
        }
        state["sources"]["uniqlo"]["audiences"]["BABY"]["queue"] = [
            "https://www.uniqlo.com/kr/ko/baby/newborn/undefined/kr/ko",
            "https://www.uniqlo.com/kr/ko/baby/newborn/bodysuits",
        ]
        collector.sanitize_uniqlo_checkpoint_category_queues(state)
        source = state["sources"]["uniqlo"]
        self.assertEqual(
            source["audiences"]["BABY"]["queue"],
            ["https://www.uniqlo.com/kr/ko/baby/newborn/bodysuits"],
        )
        self.assertEqual(len(source["rejected_category_urls"]), 1)
        self.assertTrue(source["rejected_category_urls"][0]["request_skipped"])

    def test_resume_does_not_retry_category_url_already_confirmed_as_404(self):
        state = {
            "sources": {
                "uniqlo": {
                    "audiences": {
                        audience: {
                            "queue": [],
                            "visited_categories": [],
                            "discovered_products": {},
                            "confirmed_products": [],
                        }
                        for audience in collector.AUDIENCE_ORDER
                    }
                }
            },
            "raw_records": [],
            "request_events": [
                {
                    "source": "uniqlo",
                    "kind": "category_page",
                    "url": "https://www.uniqlo.com/kr/ko/men/accessories/1",
                    "status": 404,
                }
            ],
        }
        state["sources"]["uniqlo"]["audiences"]["MEN"]["queue"] = [
            "https://www.uniqlo.com/kr/ko/men/accessories/1",
            "https://www.uniqlo.com/kr/ko/men/accessories",
        ]
        collector.sanitize_uniqlo_checkpoint_category_queues(state)
        source = state["sources"]["uniqlo"]
        self.assertEqual(
            source["audiences"]["MEN"]["queue"],
            ["https://www.uniqlo.com/kr/ko/men/accessories"],
        )
        rejected = source["rejected_category_urls"]
        self.assertEqual(len(rejected), 1)
        self.assertEqual(rejected[0]["evidence_source"], "http_404_category_response")
        self.assertIn("HTTP 404", rejected[0]["reason"])

    def test_base_canonical_url_validation_rejects_all_route_changes(self):
        expected = "https://www.uniqlo.com/kr/ko/products/E444812-000"
        result = collector.validate_canonical_product_url(
            expected, expected + "/00", "E444812-000"
        )
        self.assertEqual(result["canonical_suffix"], "00")
        rejected = [
            "http://www.uniqlo.com/kr/ko/products/E444812-000/00",
            "https://example.com/kr/ko/products/E444812-000/00",
            "https://www.uniqlo.com/jp/ja/products/E444812-000/00",
            "https://www.uniqlo.com/kr/ko/products/E999999-000/00",
            expected + "/00?variant=00",
            expected + "/00#variant",
        ]
        for actual in rejected:
            with self.assertRaises(collector.CollectionStopped):
                collector.validate_canonical_product_url(
                    expected, actual, "E444812-000"
                )
        with self.assertRaises(collector.CollectionStopped):
            collector.validate_canonical_product_url(
                expected, expected + "/00", "invalid"
            )

    def test_probe_url_failure_preserves_raw_and_all_outputs_and_stops(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "probe"
            result = self.run_synthetic_probe(output, bad_suffix=True)
            self.assertFalse(result["success"])
            self.assertEqual(result["logical_requests"], 2)
            self.assertTrue(
                (output / "raw/uniqlo/products/E488861-000.html").is_file()
            )
            for name in (
                "request_metrics.json",
                "probe_manifest.json",
                "unresolved.json",
                "baby_probe_summary.md",
            ):
                self.assertTrue((output / name).is_file(), name)
            manifest = collector.read_json(output / "probe_manifest.json")
            self.assertFalse(manifest["products"][0]["url_allowed"])
            self.assertFalse(manifest["products"][1]["requested"])

    def test_successful_probe_always_writes_all_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "probe"
            result = self.run_synthetic_probe(output)
            self.assertTrue(result["success"])
            self.assertEqual(result["logical_requests"], 5)
            self.assertEqual(result["resolved_baby_products"], 4)
            for name in (
                "request_metrics.json",
                "probe_manifest.json",
                "unresolved.json",
                "baby_probe_summary.md",
            ):
                self.assertTrue((output / name).is_file(), name)

    @unittest.skipUnless(
        (LIVE_MEDIUM.parent / "CategoryCorpus-live-baby-probe-v2").is_dir(),
        "saved BABY v2 category evidence is unavailable",
    )
    def test_baby_collection_plan_uses_raw_order_and_unique_core_products(self):
        evidence_dir = LIVE_MEDIUM.parent / "CategoryCorpus-live-baby-probe-v2"
        raw = evidence_dir / "raw/uniqlo/category-pages/baby-newborn-bodysuits.html"
        plan = collector.baby_collection_plan_from_raw(
            collector.BABY_PROBE_CATEGORY_URL,
            raw.read_bytes(),
            10,
        )
        self.assertEqual(plan["maximum_logical_requests"], 11)
        self.assertEqual(len(plan["selected"]), 10)
        self.assertEqual(
            [item["core_product_id"] for item in plan["selected"]],
            [
                "E481772", "E481769", "E487909", "E481764", "E481761",
                "E473721", "E444812", "E486378", "E486380", "E489530",
            ],
        )
        self.assertEqual(
            plan["selected"][6]["raw_product_id"],
            "E444812-000-01",
        )
        self.assertEqual(plan["selected"][6]["variant_suffix"], "01")

    @unittest.skipUnless(
        (LIVE_MEDIUM.parent / "CategoryCorpus-live-baby-probe-v2").is_dir(),
        "saved BABY v2 category evidence is unavailable",
    )
    def test_baby_collection_dry_run_is_network_free_and_within_cap(self):
        evidence_dir = LIVE_MEDIUM.parent / "CategoryCorpus-live-baby-probe-v2"
        with tempfile.TemporaryDirectory() as directory, patch.object(
            collector.urllib.request,
            "urlopen",
            side_effect=AssertionError("dry-run must not access network"),
        ):
            result = collector.baby_collect_10(
                Namespace(
                    output=Path(directory) / "output",
                    evidence_dir=evidence_dir,
                    baby_limit=10,
                    max_logical_requests=25,
                    delay_ms=250,
                    retries=2,
                    dry_run=True,
                )
            )
        self.assertEqual(result["network_requests"], 0)
        self.assertEqual(result["maximum_logical_requests"], 11)
        self.assertEqual(result["product_requests"], 10)

    def test_all_category_node_statuses_are_deterministic(self):
        cases = [
            ((1, 0, True, False), "direct_product_leaf"),
            ((0, 1, True, False), "intermediate"),
            ((1, 1, True, False), "leaf_and_parent"),
            ((0, 0, True, False), "navigation_only"),
            ((1, 1, True, True), "unresolved"),
        ]
        for arguments, expected in cases:
            self.assertEqual(collector.classify_node_status(*arguments), expected)

    @unittest.skipUnless(LIVE_SMOKE.is_dir(), "saved live smoke raw fixtures are unavailable")
    def test_all_twenty_saved_uniqlo_raw_files_resolve_from_hydration(self):
        raw_files = sorted((LIVE_SMOKE / "raw/uniqlo/products").glob("*.html"))
        self.assertEqual(len(raw_files), 20)
        for raw_file in raw_files:
            result = collector.uniqlo_category_evidence(raw_file.read_bytes(), raw_file.stem)
            self.assertEqual(result["status"], "resolved", raw_file.name)
            self.assertEqual(result["evidence_source"], "uniqlo_hydration", raw_file.name)
            self.assertTrue(result["path"], raw_file.name)
            self.assertEqual(
                [item["role"] for item in result["breadcrumb_items"]],
                ["gender", "class", "category", "subcategory"],
            )
            for item in result["breadcrumb_items"]:
                self.assertTrue(item["id"], (raw_file.name, item))
                self.assertTrue(item["name"], (raw_file.name, item))
                self.assertTrue(item["locale"], (raw_file.name, item))
                self.assertIsInstance(item["level"], int)
                self.assertIsInstance(item["raw_order"], int)

    def test_jsonld_and_hydration_conflict_is_unresolved(self):
        json_ld = {
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"position": 1, "name": "MEN"},
                {"position": 2, "name": "Tops"},
                {"position": 3, "name": "Shirts"},
            ],
        }
        hydration = {
            "entity": {
                "pdpEntity": {
                    "E123456-000-00": {
                        "product": {
                            "productId": "E123456-000",
                            "breadcrumbs": {
                                "gender": {"id": "1", "name": "men", "locale": "MEN", "level": 1},
                                "class": {"id": "2", "name": "outerwear", "locale": "아우터", "level": 2},
                                "category": {"id": "3", "name": "jackets", "locale": "재킷", "level": 3},
                                "subcategory": {"id": "4", "name": "utility", "locale": "유틸리티", "level": 4},
                            },
                        }
                    }
                }
            }
        }
        html = (
            '<script type="application/ld+json">'
            + json.dumps(json_ld)
            + "</script><script>window.__PRELOADED_STATE__ = "
            + json.dumps(hydration)
            + ";</script>"
        ).encode()
        result = collector.uniqlo_category_evidence(html, "E123456-000")
        self.assertEqual(result["status"], "unresolved")
        self.assertEqual(result["evidence_source"], "conflict")
        self.assertEqual(set(result["evidence_candidates"]), {"json_ld", "uniqlo_hydration"})

    def test_hydration_never_chooses_an_unmatched_first_entity(self):
        hydration = {
            "entity": {
                "pdpEntity": {
                    "E111111-000-00": {
                        "product": {"productId": "E111111-000", "breadcrumbs": {}}
                    },
                    "E222222-000-00": {
                        "product": {"productId": "E222222-000", "breadcrumbs": {}}
                    },
                }
            }
        }
        html = (
            "<script>window.__PRELOADED_STATE__ = "
            + json.dumps(hydration)
            + ";</script>"
        )
        result = collector.hydration_category_evidence(html, "E999999-000")
        self.assertEqual(result["status"], "unresolved")
        self.assertIn("0개", result["unresolved_reason"])

    def test_hydration_name_path_keeps_tops_shirts_unresolved(self):
        config = collector.read_json(collector.CONFIG_PATH)
        breadcrumbs = [
            {"role": "gender", "id": "1", "name": "men", "locale": "MEN", "level": 1},
            {"role": "class", "id": "2", "name": "tops", "locale": "상의", "level": 2},
            {"role": "category", "id": "3", "name": "shirts", "locale": "셔츠", "level": 3},
        ]
        nodes = collector.derive_live_inventory(
            [
                {
                    "source": "uniqlo",
                    "product_key": "E123456",
                    "category_path": "상의 > 셔츠",
                    "breadcrumb_evidence_json": json.dumps(breadcrumbs),
                }
            ],
            config,
        )
        leaf = next(node for node in nodes if node["path"] == "상의 > 셔츠")
        self.assertEqual(leaf["status"], "unresolved")
        self.assertEqual(leaf["unresolved_rule"], "uniqlo_tops_shirts")
        self.assertFalse(leaf["is_db_candidate"])

    @unittest.skipUnless(LIVE_SMOKE.is_dir(), "saved live smoke raw fixtures are unavailable")
    def test_offline_reprocess_preserves_checkpoint_raw_and_exposures(self):
        checkpoint = LIVE_SMOKE / "checkpoint.json"
        raw_files = sorted((LIVE_SMOKE / "raw").glob("*/*/*"))
        checkpoint_hash = collector.sha256_file(checkpoint)
        raw_hashes = {str(path): collector.sha256_file(path) for path in raw_files}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            shutil.copy2(checkpoint, output / "checkpoint.json")
            with patch.object(
                collector.urllib.request,
                "urlopen",
                side_effect=AssertionError("offline reprocess must not access the network"),
            ):
                result = collector.offline_reprocess(output)
            self.assertEqual(result["network_requests"], 0)
            self.assertEqual(result["resolved_paths"], 20)
            self.assertEqual(result["empty_paths"], 0)
            self.assertEqual(result["unresolved_products"], 0)
            self.assertEqual(collector.sha256_file(output / "checkpoint.json"), checkpoint_hash)
            manifest = json.loads((output / "product_manifest.json").read_text())
            products = manifest["products"]
            self.assertEqual(len(products), 39)
            e444557 = next(item for item in products if item["product_key"] == "E444557")
            self.assertEqual(e444557["observed_ids"], ["E444557-000", "E444557-001"])
            self.assertEqual(len(e444557["category_observations"]), 2)
            with (output / "category_exposures.csv").open(encoding="utf-8") as handle:
                self.assertEqual(len(list(csv.DictReader(handle))), 65)
        self.assertEqual(
            {str(path): collector.sha256_file(path) for path in raw_files},
            raw_hashes,
        )


if __name__ == "__main__":
    unittest.main()
