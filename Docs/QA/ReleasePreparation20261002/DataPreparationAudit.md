# Frozen data preparation audit — 2026-10-02

**PASS: offline structure/provenance validation. BLOCKED: real authorized comparison bindings.** QA baseline `086617f49cd19c8c3e2777e75efa820d7f886b5f`. This audit reads the existing frozen sources; it makes no HTTP/DB request and changes no corpus, product code or policy.

Machine-readable result: [data-audit-v1.json](data-audit-v1.json). Reproducible validator: [test_release_qa_data_inventory.py](../../../scripts/tests/test_release_qa_data_inventory.py).

## What the counts actually cover

| Provider | URLs / normal candidates / boundary | Real raw fixtures | Fixtures with garment table | Distinct nonempty raw structures | Garment size rows | Raw value cells |
|---|---:|---:|---:|---:|---:|---:|
| MUSINSA | 30 / 20 / 10 | 5 | 5 | 2 | 17 | 107 |
| UNIQLO | 30 / 20 / 10 | 25 | 23 | 5 | 161 | 1,486 |
| ZARA | 30 / 20 / 10 | 26 | 23 | 3 | 100 | 1,000 |
| Total | 90 / 60 / 30 | 56 | 51 | — | 278 | 2,593 |

The separate malformed synthetic fixture remains excluded from real counts. Rows/cells include archived snapshots and the three existing HTTP smoke receipts, so they are not distinct-product or executed-test counts. UNIQLO/ZARA retain both native unit representations; body guide values are excluded from garment counts. A structure means the observed raw code/label/unit set; equal signatures do **not** prove equivalent measurement semantics, verified parser schema or `RETAILER_EXACT` eligibility.

Known product IDs remain 29/27/30 for MUSINSA/UNIQLO/ZARA (86 total). All 90 original URLs are unique; suffix/color variants and the malformed mixed-retailer input remain unchanged. `normal-candidate` describes original test intent and does not certify health. All source category paths and boundary reasons are counted verbatim in the JSON. MUSINSA is concentrated in four known paths (11 short-sleeve, 10 long-sleeve, 5 knit and 3 denim inputs plus one unknown), which is not evidence of A–G coverage.

## Concrete raw facts now bound to fixtures

27 preparatory bindings contain an exact frozen fixture ID and JSON pointer, and the offline validator checks the referenced fact:

- MUSINSA raw zero and absent-unit examples. Across its five snapshots, 15 cells are zero and all 107 measurement cells lack an explicit raw unit field. Missing raw fields do not prove a missing verified parser/server unit; no `cm` assumption is inserted.
- UNIQLO `sleeve-length-cb` examples remain distinct from ordinary sleeve length. No canonical mapping is inferred.
- `uniqlo-missing-E486627-size-chart` retains `productId=E486627-000` with no `sizeChart`; the separate details fixture preserves the original error response.
- ZARA `553031685`, `553031686`, `555174282` retain null garment guides and present body guides. Body measurements never become garment measurements.

These bindings are executable **raw-fact checks**, not authenticated comparison seeds or substitutes for the twelve matrix assertions. The original 756 synthetic rows and existing matrix bindings remain unchanged. No new product/variant/size/Closet ID, canonical metric or group was created.

## Remaining data gaps

1. **All nine provider directions remain BLOCKED; 0/756 real authorized rows.** Every one of the 90 URL records lacks a current confirmed group and selected size ID; 75 lack a selected variant ID (30 MUSINSA, 30 UNIQLO, 15 ZARA). The raw archive does not provide authenticated Closet ownership, current eligible sizes, group A–G approval or common-metric begin receipts.
2. **Raw diversity is uneven.** Five MUSINSA snapshots supply two observed structures. More categories or code sets cannot establish comparison-group coverage. UNIQLO suffix/color identity equivalence and unresolved ZARA selected variants still require exact evidence; internal ZARA product IDs are never used as selected catentry IDs.
3. **Raw facts cannot establish server semantic exclusions.** Unit/basis/component conflicts, no common canonical metric, unknown canonical mapping, current UNMAPPED/different-group authorization, exact identity mismatch and verified same-retailer schema differences remain unbound to real server decisions. Similar labels or raw code sets are insufficient.
4. **Freshness and execution remain separate.** No fresh 90-URL parser batch, full 756 matrix, authenticated DB journey, device test or release approval ran here. Historical receipt/source equality does not establish current health.

## Verification

**PASS — 4 tests**, command:

```bash
python3 -m unittest discover -s scripts/tests -p test_release_qa_data_inventory.py -v
```

Validated all 69 frozen checksum entries, 90 unique URLs and per-provider cohorts, all 147 URL/fixture provenance records, full-file bytes or selected raw record equality, the three smoke receipt hashes, the expected-invalid synthetic fixture, 27 raw-fact bindings and deterministic audit contents. The original comparison corpus SHA-256 remains `6c1b712d806068cc3e44689149f8dd35421ac22a99c1bd964d690f48e3e114e0`.

Initial validator run: 2 PASS / 1 ERROR because the new checker assumed every ZARA JSONL source named its URL `product_url`; the production-sample source uses `canonical_url`. The checker now selects the explicit field for each known source schema. Frozen data and expectations were not changed. Final 4-test run passed.

**NOT RUN:** Xcode/Swift, HTTP, DB or full matrix execution in this data subtask. These four tests establish preparation integrity only.
