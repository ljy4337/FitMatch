"""Offline validation of frozen retailer evidence; never grants comparison authority."""
import hashlib
import json
import re
import unittest
from collections import Counter
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREP = ROOT / "Docs/QA/ReleasePreparation20261002"
DATA = PREP / "data"
PROVIDERS = ("musinsa", "uniqlo", "zara")


@lru_cache(None)
def read_json(path):
    return json.loads(Path(path).read_text())


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def raw_structure(item):
    body = read_json(ROOT / item["path"])
    provider = item["provider"]
    facts, signature, size_keys = [], set(), []
    if provider == "musinsa":
        for i, size in enumerate((body.get("data") or {}).get("sizes", [])):
            size_keys.append({k: size[k] for k in ("name", "sequence") if k in size})
            for j, metric in enumerate(size["items"]):
                signature.add((str(metric.get("sequence")), metric.get("name"), "unit_absent"))
                facts.append((f"/data/sizes/{i}/items/{j}", metric["value"], None, metric.get("name")))
    elif provider == "uniqlo":
        prefix = "/size_chart_payload" if "size_chart_payload" in body else ""
        for r, result in enumerate(body.get("size_chart_payload", body).get("result", [])):
            for i, size in enumerate(result.get("sizeChart", [])):
                size_keys.append({k: size[k] for k in ("sizeCode", "displayCode", "name") if k in size})
                for j, metric in enumerate(size["sizeParts"]):
                    for k, measure in enumerate(metric["measurements"]):
                        signature.add((metric["code"], measure.get("unit")))
                        facts.append((f"{prefix}/result/{r}/sizeChart/{i}/sizeParts/{j}/measurements/{k}", measure["value"], measure.get("unit"), metric["code"]))
    else:
        prefix = "/response" if "response" in body else ""
        for i, size in enumerate((body.get("response", body).get("measureGuideInfo") or {}).get("sizes", [])):
            size_keys.append({k: size[k] for k in ("id", "name") if k in size})
            for j, metric in enumerate(size["measures"]):
                for k, measure in enumerate(metric["dimensions"]):
                    signature.add((metric.get("zoneId"), metric.get("tableTitleZone"), measure.get("unitId")))
                    facts.append((f"{prefix}/measureGuideInfo/sizes/{i}/measures/{j}/dimensions/{k}", measure["value"], measure.get("unitId"), metric.get("tableTitleZone")))
    zeros = [p for p, v, _, _ in facts if str(v) in ("0", "0.0", "0.00")]
    missing_units = [p for p, _, u, _ in facts if not u]
    center_back = [p for p, _, _, code in facts if code == "sleeve-length-cb"]
    signature = [list(x) for x in sorted(signature)]
    return {"fixture_id": item["id"], "provider": provider, "path": item["path"], "sha256": item["sha256"],
            "size_keys": size_keys, "garment_size_count": len(size_keys), "raw_value_cell_count": len(facts),
            "structural_signature": signature, "zero_pointers": zeros,
            "absent_raw_unit_pointers": missing_units, "center_back_code_pointers": center_back}


def build_audit():
    manifest = read_json(DATA / "url-manifest.json")["items"]
    fixtures = read_json(DATA / "fixture-index.json")["items"]
    structures = [raw_structure(x) for x in fixtures if x["kind"] == "real_retailer_raw"]
    summaries = {}
    for provider in PROVIDERS:
        rows = [x for x in manifest if x["provider"] == provider]
        raw = [x for x in structures if x["provider"] == provider]
        summaries[provider] = {
            "url_count": len(rows), "cohorts": dict(Counter(x["cohort"] for x in rows)),
            "distinct_known_product_ids": len({x["identities"]["product_id"] for x in rows if x["identities"]["product_id"]}),
            "source_category_paths": dict(Counter(x["source_category_path"] or "<absent>" for x in rows)),
            "boundary_reasons": dict(Counter(r for x in rows for r in x["boundary_reasons"])),
            "missing_variant_ids": sum(x["identities"].get("variant_id") is None for x in rows),
            "missing_size_ids": sum(x["identities"].get("size_id") is None for x in rows),
            "current_confirmed_groups": sum(x["comparison_group_current"] is not None for x in rows),
            "real_fixture_count": len(raw), "garment_table_fixture_count": sum(x["garment_size_count"] > 0 for x in raw),
            "distinct_nonempty_raw_structures": len({json.dumps(x["structural_signature"]) for x in raw if x["structural_signature"]}),
            "garment_size_rows": sum(x["garment_size_count"] for x in raw),
            "raw_value_cells": sum(x["raw_value_cell_count"] for x in raw),
            "zero_cells": sum(len(x["zero_pointers"]) for x in raw),
            "absent_raw_unit_cells": sum(len(x["absent_raw_unit_pointers"]) for x in raw),
        }
    witnesses = []
    for row in structures:
        for key in ("zero_pointers", "absent_raw_unit_pointers", "center_back_code_pointers"):
            if row[key]:
                witnesses.append({"fixture_id": row["fixture_id"], "fact": key, "json_pointer": row[key][0],
                                  "evidence_scope": "raw_field_presence_only", "server_authorization_status": "BLOCKED"})
    witnesses.extend([
        {"fixture_id": "uniqlo-missing-E486627-size-chart", "fact": "sizeChart_key_absent", "json_pointer": "/result/0",
         "evidence_scope": "raw_field_presence_only", "server_authorization_status": "BLOCKED"},
        *[{"fixture_id": fid, "fact": "measureGuideInfo_null_sizeGuideInfo_present", "json_pointer": "/response",
           "evidence_scope": "raw_field_presence_only", "server_authorization_status": "BLOCKED"}
          for fid in ("zara-553031685", "zara-553031686", "zara-555174282")],
    ])
    return {"schema_version": "fitmatch-data-preparation-audit-v1", "baseline_commit": "086617f49cd19c8c3e2777e75efa820d7f886b5f",
            "scope": "Offline frozen-source structure and provenance; no current health, canonical mapping or group authority inferred.",
            "frozen_checksums_sha256": sha(DATA / "SHA256SUMS"),
            "corpus_sha256": sha(DATA / "comparison-cases.jsonl"), "providers": summaries,
            "raw_structures": structures, "preparatory_raw_fact_bindings": witnesses,
            "real_pair_bindings": [{"closet_provider": a, "target_provider": b, "status": "BLOCKED", "source_fixture_binding": None,
                                    "reason": "No authenticated exact Closet/product/variant/size, group A-G or approved common metric receipt."}
                                   for a in PROVIDERS for b in PROVIDERS],
            "authorized_matrix_rows": 0, "planned_matrix_rows": 756,
            "limitations": ["Structural signatures preserve raw codes/labels/units; equality is not verified semantic/schema equivalence.",
                            "MUSINSA absent raw unit is not evidence the deployed parser or server lacks a verified unit.",
                            "Raw fact bindings do not satisfy the synthetic matrix's canonical, group, conflict or exact-identity assertions.",
                            "Historical captures and duplicate snapshots do not establish current product health or distinct product counts."]}


class FrozenDataAuditTests(unittest.TestCase):
    def test_frozen_files_and_cohorts(self):
        lines = (DATA / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(lines), 69)
        for line in lines:
            expected, path = line.split(maxsplit=1)
            self.assertEqual(sha(ROOT / path), expected, path)
        rows = read_json(DATA / "url-manifest.json")["items"]
        self.assertEqual(len({x["url"] for x in rows}), 90)
        for p in PROVIDERS:
            self.assertEqual(Counter(x["cohort"] for x in rows if x["provider"] == p), {"normal-candidate": 20, "boundary": 10})

    def test_provenance_and_original_record_preservation(self):
        rows = read_json(DATA / "url-manifest.json")["items"]
        fixtures = read_json(DATA / "fixture-index.json")["items"]
        for item in rows + fixtures:
            proof = item["provenance"]
            source = ROOT / proof["path"]
            self.assertEqual(sha(source), proof["sha256"], item["id"])
            selector = proof["selector"]
            if selector and re.fullmatch(r"\$\[\d+\]", selector):
                selected = read_json(source)[int(selector[2:-1])]
                if item in fixtures:
                    self.assertEqual(read_json(ROOT / item["path"]), selected, item["id"])
                else:
                    self.assertEqual(item["url"], selected["url"], item["id"])
            elif selector and selector.startswith("line "):
                selected = json.loads(source.read_text().splitlines()[int(selector[5:]) - 1])
                field = {"zara_phase1_5_identity_samples.jsonl": "product_url",
                         "zara_production_sample_30_payloads.jsonl": "canonical_url"}[source.name]
                self.assertEqual(item["url"], selected[field], item["id"])
            elif selector and selector.startswith("results/provider="):
                receipt = [x for x in read_json(source)["results"] if x["provider"] == item["provider"]]
                self.assertEqual(len(receipt), 1)
                self.assertEqual(sha(ROOT / item["path"]), receipt[0]["response_sha256"])
            else:
                self.assertIsNone(selector)
                self.assertEqual((ROOT / item["path"]).read_bytes(), source.read_bytes())

    def test_preparatory_witnesses_are_concrete_raw_facts(self):
        audit = read_json(PREP / "data-audit-v1.json")
        fixtures = {x["id"]: x for x in read_json(DATA / "fixture-index.json")["items"]}
        with self.assertRaises(json.JSONDecodeError):
            read_json(ROOT / fixtures["synthetic-zara_malformed_synthetic"]["path"])
        for witness in audit["preparatory_raw_fact_bindings"]:
            value = read_json(ROOT / fixtures[witness["fixture_id"]]["path"])
            for key in witness["json_pointer"].strip("/").split("/"):
                value = value[int(key)] if isinstance(value, list) else value[key]
            if witness["fact"] == "zero_pointers":
                self.assertEqual(float(value["value"]), 0)
            elif witness["fact"] == "absent_raw_unit_pointers":
                self.assertNotIn("unit", value)
                self.assertNotIn("unitId", value)
            elif witness["fact"] == "center_back_code_pointers":
                self.assertIn(value["unit"], ("cm", "inch"))
                metric = read_json(ROOT / fixtures[witness["fixture_id"]]["path"])
                for key in witness["json_pointer"].strip("/").split("/")[:-2]:
                    metric = metric[int(key)] if isinstance(metric, list) else metric[key]
                self.assertEqual(metric["code"], "sleeve-length-cb")
            elif witness["fact"] == "sizeChart_key_absent":
                self.assertEqual(value["productId"], "E486627-000")
                self.assertNotIn("sizeChart", value)
            elif witness["fact"] == "measureGuideInfo_null_sizeGuideInfo_present":
                self.assertIsNone(value["measureGuideInfo"])
                self.assertIsNotNone(value["sizeGuideInfo"])
            else:
                self.fail("Unknown witness fact: " + witness["fact"])

    def test_saved_audit_matches_raw_and_never_grants_authority(self):
        audit = read_json(PREP / "data-audit-v1.json")
        self.assertEqual(audit, build_audit())
        self.assertEqual(len(audit["raw_structures"]), 56)
        self.assertEqual(audit["authorized_matrix_rows"], 0)
        self.assertEqual(len(audit["real_pair_bindings"]), 9)
        for item in audit["real_pair_bindings"]:
            self.assertEqual(item["status"], "BLOCKED")
            self.assertIsNone(item["source_fixture_binding"])


if __name__ == "__main__":
    unittest.main()
