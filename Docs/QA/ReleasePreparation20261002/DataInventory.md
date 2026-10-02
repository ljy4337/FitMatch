# Release preparation data inventory — 2026-10-02

Baseline: `QA` / `086617f`. This report covers the data preparation phase. Current Swift parser/replay results are separate runner evidence; HTTP receipts below do not establish Swift parsing, server persistence, comparison completion or release readiness.

## Prepared material

| Provider | Normal candidates | Boundary inputs | URLs | Distinct known product IDs | Frozen real raw fixtures |
|---|---:|---:|---:|---:|---:|
| MUSINSA | 20 | 10 | 30 | 29 | 5 |
| UNIQLO | 20 | 10 | 30 | 27 | 25 |
| ZARA | 20 | 10 | 30 | 30 | 26 |
| Total | 60 | 30 | 90 | 86 | 56 |

- [URL manifest](data/url-manifest.json): original URLs, exact known identities, source file/hash/selector, historical evidence and current status. Cohorts describe test intent; `normal-candidate` is not a verified healthy-product label. Categories never establish comparison groups.
- MUSINSA's 30 inputs include one original malformed mixed-retailer URL with unresolved product identity. UNIQLO deliberately retains E491320 `-000/-001/-002` and E487688 color-specific/generic URLs separately. Thus 90 unique URLs are not 90 unique products.
- [Fixture index](data/fixture-index.json): 57 entries = 56 real raw receipts/archived raw records plus one explicitly synthetic, intentionally invalid JSON fixture. Original bytes are retained for whole-file copies; array slices retain all selected record fields and identify the full source file hash. Derived Swift observations are separate in [historical-parser-observations.json](data/historical-parser-observations.json).
- [Source inventory](data/source-inventory.json): source hashes and discovered corpus counts. [SHA256SUMS](data/SHA256SUMS) freezes all 69 data files (2,428,696 bytes excluding the checksum list). Do not refresh in place; prepare another version/run directory when needed.
- [Comparison dataset](data/comparison-dataset.json) and [cases](data/comparison-cases.jsonl): nine Closet→target retailer directions × seven requested groups A–G × twelve measurement/identity/missing-data patterns = **756 synthetic contract specifications, NOT RUN**. They bind no invented live groups, selected sizes or measurements. Real source pointers are available, but authenticated fixture binding remains open.

## Existing evidence available

| Existing source | Observed inventory | Reuse boundary |
|---|---|---|
| SuppliedLinks audit, 2026-09-30 | 186 records: historical 184 parsed-with-measurements, 1 partial, 1 failed | Historical Swift output; no new run claimed |
| `CurrentUniqloCatalogInputs.json` | 880 archived chart records | Raw source facts usable; local classification fields are not current authority |
| MUSINSA incremental archive | 231 `actual_size` files; 231 separate `options` files | Options excluded from measurement replay evidence |
| ZARA production sample manifest | 45 variant receipts: 42 garment guides, 3 body-only guides | Selected `catentryID` differs from internal product ID; body guide is not garment data |
| August A-test reports | Present, versioned source reports | `reference_on/off`, automatic comparison and detailed-classification expectations are old policy; not reused as present acceptance criteria |
| External RetailerCatalogCollector fixture root | Missing at the documented local path | Existing generic replay shell cannot run from that absent root unchanged |

The old `run-fitmatch-fixture-tests.sh` and SuppliedLinks `run-live.sh` use `-scheme FitMatch`, whose current configuration targets Production. They were **not executed**. The current runner must explicitly select `FitMatch-QA` and `Debug-QA`.

## Limited real HTTP smoke

Three official measurement GETs completed at **2026-10-02 08:37:25–08:37:26 UTC**. Each request ran once in the network-enabled attempt; no discovery, fallback, retry loop, DB calls or challenge bypass ran.

| Provider / exact request identity | HTTP | Raw table shape | Status |
|---|---:|---|---|
| MUSINSA goods `4096130` | 200 | 2 size rows, 14 measurement columns across sizes | PASS |
| UNIQLO chart `E487688-000` (generic chart; original input color `31`) | 200 | 7 size rows, 28 measurement columns across sizes | PASS |
| ZARA selected catentry `549838589`; historical internal product `549829596` | 200 | 4 size rows, 20 measurement columns across sizes | PASS |

Evidence: [request plan](data/http-smoke-plan.json), [network results](data/http-smoke/network-20261002/results.json), raw `.body` files alongside it. Initial sandbox attempts returned DNS `curl exit 6` / HTTP 0 for all three and remain recorded separately in [sandbox results](data/http-smoke/sandbox-20261002/results.json). Network-enabled execution returned exit 0.

These are structural receipt checks, not full numeric-cell, semantic, current product-page identity or Swift parser validation. Exact request IDs come from archived source evidence; current PDP resolution remains a separate step.

## Verification and commands

- **PASS**: manifest 90 unique URLs and 20/10 cohorts for each provider; all 57 indexed fixture hashes; JSON/JSONL structure with the one declared negative fixture expected to fail JSON decoding; collector syntax; 69-file checksum validation. See [validation](data/validation.json).
- **PASS**: collector dry run makes zero requests; bounded real HTTP smoke returns three valid table-shaped responses.
- **NOT RUN**: full 90-URL current parser batch, 756 contract specifications, authenticated Closet/History/group/score E2E, performance and device matrix. No full batch, product fixes, DB writes, migration, commit or push occurred in this data phase.

```bash
python3 Docs/QA/ReleasePreparation20261002/data/collect-http-smoke.py
# Performed: DRY_RUN, 3 planned requests, 0 network requests.

python3 Docs/QA/ReleasePreparation20261002/data/collect-http-smoke.py --collect --run-id network-20261002
# Performed once with network permission. Existing run ID cannot be overwritten.

shasum -a 256 -c Docs/QA/ReleasePreparation20261002/data/SHA256SUMS
# Performed: all 69 files OK.
```

## Remaining coverage gaps

1. Fresh server-approved group A–G, variant and size bindings are absent across the real matrix. Historical UNMAPPED/group results are marked as historical. No current group or readiness is inferred from labels, categories or successful HTTP.
2. MUSINSA real raw snapshot coverage is much smaller than the 30-URL candidate list. Some UNIQLO candidates are absent from the older 880-record corpus. ZARA canonical URLs without `v1` require fresh exact identity resolution; known archived variants are never reduced to the first variant.
3. Boundary examples cover actual raw zero rows, missing charts, unresolved groups, center-back sleeve semantics, body-only guides and internal/selected ID differences. This does not prove all 10 boundary inputs per provider are historical failures, nor all real garment/group diversity is satisfied.
4. The synthetic malformed fixture and 756 scenario specifications supply negative contracts only. They must remain separate from retailer coverage and actual executed test counts.
