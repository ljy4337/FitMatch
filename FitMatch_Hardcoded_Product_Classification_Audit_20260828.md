# FitMatch Hardcoded Product Classification Audit — 2026-08-28

## Executive Summary

- Audit base: `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`; branch: `connectDB`; verified before audit.
- Starting `git status --short`: clean (no output).
- Production-reachable explicit product-ID classification hardcodes: **2 occurrences / 2 unique products**, both ZARA style-number dictionary overrides. MUSINSA and UNIQLO contain **0** production product-ID classification hardcodes.
- Production name/keyword classifier rules under the rule granularity below: **199**.
- Production category/path classifier rules: **3577**, including **3426** runtime bundle mapping records. The bundle's `externalCategoryID` values are retailer **category IDs**, never product IDs.
- Measurement/local fallback classifier rules recorded separately: **8**.
- Non-production corpus: **6139** test/fixture-only unique source+product IDs and **25347** docs/research-only unique source+product IDs. The ledger preserves **14,682** test/fixture and **134,789** docs/research occurrences rather than deduplicating locations.
- No Supabase/production DB read or write was used. No web search was used. Product names were never used to invent an output.

## Counting Contract

The product ledger counts an occurrence only when a literal retailer product identity participates in production classification, or appears in a non-production test/QA/document/research product record. Duplicate IDs in different files/lines remain separate rows. Final product counts use unique `source + external_product_id` keys; explicit fixture variants such as an `E…-000` product-color identity remain distinct from their base product literal. Docs/research-only counts are disjoint from production and test/fixture IDs. A source-category ID, UUID, measurement code, URL example that does not change classification, and measurement `rawCode` equality are not product hardcodes.

For rules, one row means one precedence-distinct conditional branch or one static mapping-table entry. Synonyms inside one condition are one rule. The 3,426 bundled source-category mapping records are each a rule because each stores a distinct exact lookup condition and output. Pure call sites and authority routing are recorded as `AUTHORITY_PRECEDENCE` but excluded from the two requested rule counts. COS rules are recorded as `CATEGORY_OR_PATH_RULE_OUT_OF_SCOPE` and excluded from the requested MUSINSA/UNIQLO/ZARA denominator.

## Revalidation of 754 / 266 / 2

The previous **754 MUSINSA / 266 UNIQLO** figures were corpus-impact counts, not source-code hardcode counts: in the 5,026-row QA fixture, they counted rows whose local classification tuple changed when the same Swift classifier was run with the product name present versus blank (1,020 affected rows total). They therefore measured the reach of shared name semantics over a particular corpus, not distinct rules and not explicit product-ID overrides. The previous **ZARA 2** represented the two actual style-number entries in `exactProductMappings`; that number is reproduced by the source-only audit. The corrected explicit production product counts are MUSINSA 0, UNIQLO 0, ZARA 2.

## Production vs Non-production Product IDs

| Source | Explicit production occurrences | Explicit production unique IDs | Test/fixture-only unique IDs | Docs/research-only unique IDs |
|---|---:|---:|---:|---:|
| MUSINSA | 0 | 0 | 4014 | 20455 |
| UNIQLO | 0 | 0 | 2105 | 833 |
| ZARA | 2 | 2 | 20 | 4059 |
| **Total** | **2** | **2** | **6139** | **25347** |

The DEBUG onboarding fixture additionally contains pseudo-ID `onboarding-musinsa` and UNIQLO ID `E000001`, both behind `#if DEBUG`; these are in the product ledger as `DEBUG_ONLY` and excluded from production and test/fixture-only totals.

## Explicit Production Product-ID Group

### ZARA_PRODUCT_OVERRIDE_001

- File/symbol: `FitMatch/Services/ZARAParser.swift:1044-1050`, `ZARACategoryClassifier.exactProductMappings`.
- Mechanism: `identity.styleNumber` dictionary lookup at lines 1075-1083, reached from parsed URL identity at lines 629-634.
- Condition: stable ZARA URL style number; executed before exact structured path and generic fallbacks.
- Products: `01934230` → `bottoms / denim`; `07782343` → `outerwear / jacket`.
- Origin: `PRODUCT_OVERRIDE`. The comment says these are user-reviewed exceptions that must not rewrite the whole subfamily. No product name appears in the production mapping.

## Production Classifier Authority Inventory

### Category/path rules

- `FitMatch/CanonicalTaxonomyBundle/FitMatchSourceCategoryMappings.json`: 3426
- `FitMatch/Services/ZARAParser.swift`: 69
- `FitMatch/Services/MusinsaProductMetadataParser.swift`: 32
- `FitMatch/Models/ParsedClosetClassification.swift`: 24
- `FitMatch/Services/UniqloParser.swift`: 19
- `FitMatch/Services/ComparisonProfileMatcher.swift`: 4
- `FitMatch/Models/FitMatchTaxonomy.swift`: 2
- `FitMatch/Services/MusinsaParser.swift`: 1

Runtime bundle source split:

- MUSINSA: 1922
- UNIQLO: 1504

Important flow: `CanonicalTaxonomyBundleStore` indexes the bundled rows and accepts only a unique outcome. Product external-category lookup precedes target+path and path fallback. ZARA uses its own exact structured section/family/subfamily table and fail-closed generic fallback. MUSINSA and UNIQLO parsers also contain local path keyword classifiers before `ParsedClosetClassification` normalization.

### Name/keyword rules

- `FitMatch/Models/ParsedClosetClassification.swift`: 121
- `FitMatch/Services/ComparisonProfileMatcher.swift`: 44
- `FitMatch/Services/UniqloParser.swift`: 34

ZARA local classification intentionally passes an empty name to `ParsedClosetClassification.resolve`, so shared name rules do not replace ZARA's structured classification. The safety audit still reads the name and may produce a confirmation requirement. MUSINSA/UNIQLO parser and comparison-profile paths remain name-sensitive.

### Other local mechanisms (not in the two counts)

- `GarmentLengthInferencePolicy` and `ParsedProductInfo.normalizedSizes` infer sleeve/lower length from measurements when earlier detail evidence is unresolved (8 ledger rows).
- `SourceCategoryHistoryMatcher` reuses runtime user selections by exact product key, then compatible depth/path history. It has no static product IDs or static output and is excluded from hardcoding counts.
- `ShoppingProductViewModel.makeProduct` gives confirmed server authority precedence; local classification can still populate UI/offline model hints and comparison attributes.

## Brand Summary

### MUSINSA

No production product ID is mapped to a classification in Swift. Runtime classification comes from 1922 bundled source-category rows, MUSINSA path/type-name keyword mapping, shared name/path canonicalization, and measurement fallbacks. The DEBUG onboarding pseudo-product is non-production.

### UNIQLO

No production product ID is mapped to a classification in Swift. Runtime classification comes from 1504 bundled source-category rows, UNIQLO path plus combined path/name detail mapping, shared canonicalization, and measurement fallbacks. `E000001` is DEBUG-only.

### ZARA

Two style IDs are production overrides. In addition, 42 exact section/family/subfamily rows plus fail-closed path fallbacks classify other ZARA products. Name semantics are suppressed for ordinary ZARA local resolution, but the name-based contradiction audit remains reachable.

## Risk-ranked DB Migration Targets

1. `ZARACategoryClassifier.exactProductMappings`: direct per-product authority; migrate the two style decisions first and remove only after equivalent DB authority is verified.
2. `FitMatchSourceCategoryMappings.json`: 3,426 runtime-loaded category/path decisions; these are the largest repository authority surface and should move as versioned, checksum-verified DB mappings.
3. ZARA `exactMappings` and generic structured fallback: provider path authority embedded in Swift.
4. MUSINSA/UNIQLO parser `mapCategory` / `mapDetailCategory`: local source interpretation, including UNIQLO's combined product-name input.
5. `ParsedClosetClassification` and `ComparisonProfileMatcher`: shared name/path semantic inference that can change category, detail, family, length, review state, or local comparison eligibility.
6. Measurement thresholds: local non-DB classification fallback; move only if vNext DB is intended to own measurement-derived length semantics too.

## Exclusions and Uncertainty

- `FitMatch/ContentView.swift:438` contains a MUSINSA screenshot URL but does not affect classification; excluded.
- `FitMatch/Services/SampleDataService.swift:11-32` contains legacy sample identifiers, but uses them only to find and delete sample rows; they do not classify products and are excluded.
- `ComparisonProfileMatcher.swift:1514-1516` compares measurement raw codes, not product identities; excluded.
- Canonical bundle external IDs are category IDs; excluded from the product ledger and included only in the rules ledger.
- Test expected values and Docs/Research outcomes are preserved as non-production evidence only. They were never promoted to source intent.
- Docs/research counting selects structured product ID fields and retailer-specific URL/style literals. ZARA is normalized to the stable 8-digit style when a record provides it. Bare numbers without retailer/product context are excluded.
- Rule totals depend on the declared branch/mapping-entry granularity; the ledger is the reproducible machine-readable authority for recounting.

## Acceptance Verification

- Audit base HEAD matched before work: `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`.
- Production explicit IDs include file, line, symbol, condition, mechanism, output, and origin.
- Production and DEBUG/test/fixture/docs scopes are separated; duplicate occurrences are retained.
- Product output fields are populated only from literal source fields or deterministic enum-to-taxonomy mappings documented in notes; absent values remain null.
- Name/keyword, category/path, regex, fallback, measurement, authority-precedence, canonical bundle, and dynamic-history paths were inspected and recorded.
- No DB access/write, migration/seed execution, web lookup, Swift edit, expected-value edit, commit, or push occurred.
- Audit ended on branch `connectDB` at the unchanged HEAD `6246aede16d22ae8b08189a7ef9dd22a68bfbaf6`.
- Ending `git status --short` contained only the three requested untracked audit artifacts. `git diff --name-only` and `git diff --cached --name-only` were empty: tracked-file changes **0**.
- The protected `TabBarScrollVisibilityModifier.swift` diff and the protected tab-bar/top-chrome symbol diff scan were empty.
