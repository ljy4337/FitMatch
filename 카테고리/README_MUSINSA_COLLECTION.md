# FitMatch MUSINSA collection

This package collects publicly accessible MUSINSA clothing metadata and garment measurements, then builds a normalized Excel workbook for FitMatch.

## What it does

- Reads the official robots policy and sitemap index.
- Enumerates the ten official product sitemaps for a verifiable discovery count.
- Discovers the current direct child categories under 상의, 아우터, 바지, 원피스/스커트.
- Reads current PLP data from category pages and follows official `nextPageUrl` pagination in full mode.
- Collects public product detail, `actual-size`, and option responses.
- Preserves raw measurement names and values.
- Applies only exact, documented raw-name-to-canonical mappings.
- Keeps network failures separate from valid null/empty size responses.
- Caches public responses so an interrupted run can resume without redownloading completed items.

It does not log in, bypass CAPTCHA or access controls, rotate identities, use private credentials, or run OCR.

## Default reproducible run

```bash
node musinsa_collector.mjs --mode sample --per-category 8 --request-delay-ms 350 --concurrency 6
```

The default run selects up to eight products from each of the 45 current direct clothing subcategories. It is deliberately reported as `BEST_EFFORT_PARTIAL_NOT_FULL_CATALOG`.

## Full PLP pagination mode

```bash
node musinsa_collector.mjs --mode full --request-delay-ms 500 --concurrency 4
```

Full mode follows each public PLP `nextPageUrl` and then requests detail/size data for all unique products discovered there. This can take many hours and still does not prove whole-site completeness because no public global catalog contract guarantees that every product appears in the selected PLPs.

Use `--max-pages N` to cap pagination during testing. `0` means no page cap.

## Workbook build

The workbook builder uses the bundled Codex primary runtime and `@oai/artifact-tool`.

```bash
export FITMATCH_WORKSPACE="$PWD"
mkdir -p artifact_tmp
ln -s "$CODEX_PRIMARY_RUNTIME_NODE_MODULES" artifact_tmp/node_modules
cp build_musinsa_workbook.mjs artifact_tmp/build_musinsa_workbook.mjs
"$CODEX_PRIMARY_RUNTIME_NODE" artifact_tmp/build_musinsa_workbook.mjs
```

The workbook contains Products, Sizes, RawMeasurements, Categories, Failures, Metadata, MappingRules, and Validation sheets.

## Important semantics

- `raw_unit=cm` is based on the official actual-size UI table context. The API item itself has no unit field, and no numerical conversion is performed.
- Raw zero values are preserved but excluded from canonical measurement columns because they may be placeholders.
- `size_available` is left blank unless real-time stock can be verified. Option activation is recorded in `measurement_status`, not treated as inventory.
- Circumference is never divided by two to create flat width.
- Image-only size charts are not OCR'd.

