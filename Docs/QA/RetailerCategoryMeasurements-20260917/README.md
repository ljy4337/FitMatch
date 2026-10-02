# Retailer category and garment measurement normalization

This is a deduplicated inventory of **observed** retailer categories and the
garment measurement fields seen for products in each category. It is not a
FitMatch A-G group mapping and does not modify the database or app parser.

| Source | Products with retained captures | Categories | Category-field pairs | Distinct raw fields |
| --- | ---: | ---: | ---: | ---: |
| MUSINSA | 231 | 44 | 169 | 9 |
| UNIQLO | 302 | 101 | 456 | 31 |
| ZARA | 28 (42 variant captures) | 16 | 78 | 12 |

- `categories.csv`: one row per retailer/category ID/category path. The two
  capture columns identify the category evidence and a measurement response.
- `category_measurements.csv`: one row per retailer/category/raw measurement
  code/label/unit; repeated sizes and products are deduplicated.
- `summary.json`: machine-readable row counts.
- `upsert.sql`: SQL for two **private observation tables** in
  `fitmatch_catalog`. Applied to connected FitMatch Supabase project
  `hnkplvyegonlhumlejst` on 2026-09-17 after explicit user approval. It does
  not update active A-G category policy or canonical measurement mappings.
  It was first tested twice on isolated local PostgreSQL 17.
- `api-403-check-10.txt`: five MUSINSA and five ZARA official measurement API
  URLs. Each returned HTTP 403 from this environment on 2026-09-17. This does
  not establish that another device or network will receive 403.

Sources are retained official response captures. MUSINSA category paths come
from product-detail API JSON and measurement names from actual-size API JSON.
UNIQLO paths are official catalog exposure paths retained in the product
manifest, not inferred from the size-chart response; measurement codes/names
come from the official size-chart API. ZARA category ID/path and family names
come from the retained product manifest, and measurement zone codes from the
official garment `measureGuideInfo` response. These sources are kept distinct
in the CSV. The same UNIQLO product may appear in multiple catalog paths.

Only fields with at least one positive observed value are listed. UNIQLO and
ZARA use the observed `cm` entry, not converted inch values. MUSINSA's
actual-size response has no explicit unit, so its unit is `unknown` here.
`bodyMeasurements` and ZARA body-size guidance are not garment measurements.
Nine categories have no observed garment field: four MUSINSA categories and
five UNIQLO sock categories. This is not proof that all their products lack
measurements.

**Coverage limit:** The main URL ledgers contain 8,996 distinct URLs, but
retained category-plus-measurement captures cover only the products in the
table. Direct live checks on 2026-09-17 returned UNIQLO timeout, MUSINSA 403,
and ZARA 403 from this execution environment. The remaining URLs were not
freshly fetched, normalized, or marked successful. Once official API access is
available, rerun the existing collectors. This normalizer reads their current
MUSINSA/UNIQLO run layouts and the retained ZARA sample manifest; a new ZARA
capture layout must be connected explicitly before claiming broader coverage.
Do not treat these historical rows as a current catalog census.

The source raw captures are from the August 2026 collector runs and ZARA
sample. No new FitMatch comparison group, canonical measurement equivalence,
or policy was inferred from a product name or a shared label.

Connected DB postflight: observation categories 0 -> 161 (MUSINSA 44, UNIQLO
101, ZARA 16); category/measurement pairs 0 -> 703 (169, 456, 78).
Preexisting active category group rows 1,023 -> 1,023, source measurements
51 -> 51, source measurement mappings 48 -> 48. Both new tables have RLS
enabled; anon/authenticated SELECT is not granted. This is an observed-facts
snapshot, **not an expansion of automatic app group/measurement coverage**.

Rebuild locally:

```bash
python3 scripts/normalize-retailer-category-measurements.py \
  --output Docs/QA/RetailerCategoryMeasurements-20260917
```
