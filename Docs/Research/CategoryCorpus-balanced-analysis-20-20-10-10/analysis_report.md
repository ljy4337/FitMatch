# Category corpus balanced offline analysis

- Network requests: 0
- Products: 60
- Unique base product IDs: 60
- DB candidates: 60/60 (100.0%)

## Audience summary

| Audience | Samples | Unique base | Empty | Mismatch | JSON-LD used | Hydration used | Both valid | Conflict | Unresolved | DB candidate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MEN | 20 | 20 | 0 | 0 | 0 | 20 | 0 | 0 | 0 | 20 |
| WOMEN | 20 | 20 | 0 | 0 | 0 | 20 | 0 | 0 | 0 | 20 |
| KIDS | 10 | 10 | 0 | 0 | 0 | 10 | 0 | 0 | 0 | 10 |
| BABY | 10 | 10 | 0 | 0 | 0 | 10 | 0 | 0 | 0 | 10 |

Detailed breadcrumbs and provenance are stored in `balanced_products.json` and `baby_variant_provenance.json`.
DB candidate means only that the path is not excluded by the current `known_categories.json` policy; it does not assert a final app-category mapping.
