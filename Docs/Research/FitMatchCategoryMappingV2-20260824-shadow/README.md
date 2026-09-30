# FitMatch category mapping v2 shadow corpus

This directory absorbs only the useful product corpus from
`FitMatch_Category_Mapping_v2_20260824.zip`. It does not import the archive's
rule engine, database schema, release status model, comparison engine, or
generated classification results.

The corpus is deliberately shadow-only:

- Musinsa's 51 rows contain explicit expected garment labels and can be used as
  new regression candidates after FitMatch's own conflict checks.
- Uniqlo's 1,689 rows expand coverage, but their app-category fields are not
  independent human labels. They must not be auto-approved as Gold fixtures.
- ZARA's 3,983 rows are discovery inputs only. Their `ZARA_KR_*` IDs are
  archive-local pseudo IDs, not FitMatch's verified nine-digit runtime product
  identity, and 8 rows have no product name. No row may be imported into
  production identity or taxonomy tables without official-source revalidation.
- `live300-v2_3/live_products_300.jsonl` adds a balanced 100-row listing sample
  for each retailer. It contributes 57 Musinsa identities that were absent from
  the base corpus; its Uniqlo and ZARA rows are subsets with newer listing
  evidence. All 300 rows have zero independent human-approved labels.
- `live300-v2_3/official_source_evidence.json` records how the archive observed
  the official discovery pages. It does not preserve the remote response bodies,
  so it is provenance evidence rather than independently replayable proof.

The archive's generated classification outputs and `manual_semantic_audit` are
not absorbed. The audit generator assigns every row
`silent_misclassification_observed=false` without an independent answer key;
those values cannot be used as accuracy evidence or Gold labels.

Run the offline integrity and safety gate with:

```sh
node scripts/audit-category-mapping-shadow-corpus.mjs
```

The audit reads local files only and performs no database writes.

`CategoryLive300ShadowAuditTests` additionally runs the current FitMatch
classifier over the source facts in this sample. Its result is an anomaly list,
not a correctness score. ZARA rows still use archive-local source candidates and
must be revalidated through the official runtime parser before Gold promotion.

Latest current-classifier shadow result:

- 243 provisional confirmations
- 29 `review_required`
- 28 `unclassified`
- 57 human Gold-review candidates in
  `live300-v2_3/current_fitmatch_gold_review_candidates.json`
- 0 explicit conflicts silently confirmed
- 0 explicit conflicts admitted to strict comparison
- 0 ZARA rows verified through the current runtime parser, because the archive
  does not contain the required official PDP HTML or verified `catentryId`

The full 3,983-row ZARA corpus is also executed against the real embedded
`ZARACategoryClassifier` as an offline safety regression. Among 3,691 standard
products with a complete structured family/subfamily, the current v4 fallback
classifies 2,931 and leaves 760 unclassified. The audit found zero source-family
domain crossings and zero automatic classifications from the explicitly
ambiguous `OVERALL`, `TOPS AND OTHERS`, `WAISTCOAT`, and `OVERSHIRT` families.
This is a safety/coverage result, not a Gold accuracy score; the corpus still has
zero independent ZARA labels and cannot open the production release gate.
