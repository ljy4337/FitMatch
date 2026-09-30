# FitMatch Classification DB Closure — 2026-08-26

Scope: set products excluded, supported single apparel, local-first full validation, Production apply/write/activation `0`.

## 1. FINAL GO / NO-GO

**DB CLASSIFICATION CLOSURE = GO.** This is the owner-defined completion case B: the DB taxonomy, authority precedence, generic structured-discriminator contract, comparison policy, measurement policy, exclusions, and fail-closed routes are complete. The remaining `1,113` rows lack independently verifiable product truth; they remain explicitly `review_required` and are not a DB-design blocker.

This GO does **not** authorize Production deployment, release activation, history backfill, or iOS integration. Those remain separate approved operations.

Baseline parity passed before modification:

- 117 shadow SHA-256: `bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916`
- product key + fingerprint SHA-256: `c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a`
- products / unique keys: `1,608 / 1,608`; fingerprint drift: `0`
- all earlier supplied checksums (Phase 1B-2, evidence audit, conflicts, DB-only 105, invalid rows, remediation, 117 shadow): exact parity

## 2. What changed

Migration 118 creates one local candidate release, `fitmatch-classification-authority-final-candidate-2026-08-26-v1`, with status `validated` and never `active`.

- Added one generic typed-evidence table, `fitmatch_catalog.classification_structured_discriminator_rules`. It stores source, key/value, optional category/path/target scope, canonical tuple or exclusion, evidence, status, policy/release, and runtime eligibility. It stores no SQL expression, regex, DSL, ML model, or source-specific executable logic.
- Updated resolver **v4 in place**. Order is verified exclusion → verified complete exact decision → verified structured rule → verified pure category → verified path → verified name → fail-closed review. No resolver v5 was created.
- Made incomplete/invalid legacy decisions audit-only. A complete legacy conflict still fails closed; legacy rows never confirm by themselves.
- Completed taxonomy vocabulary needed by the current data, explicit comparison matrix, and measurement-policy coverage.
- Reclassified mixed Musinsa sleeveless authorities to `PRODUCT_REQUIRED`; repaired independently verified mapping/vocabulary cohorts; revoked every remaining unverified mapping authority.
- Added verified path/exclusion profiles and 14 independently supported decision translations. No raw-name rule and no real name profile was added.
- Added generic set/non-apparel exclusion rules; the adapter contract is `payload.structured_facts-v1`.

Unchanged: migrations 113–117, Production state, Swift behavior, `MeasurementComparisonEngine` scoring/weight algorithm, public RPC call sites, and iOS integration.

## 3. Root causes closed

| 117 cause | Closure disposition |
|---|---|
| `AUTHORITY_CONFLICT` 717 | legacy incomplete/invalid rows are non-authority; complete conflicting evidence remains fail-closed. Final runtime authority conflicts: `0`. No cohort-wide arbitrary winner was selected. |
| structured evidence not consumed | all original typed values were inventoried; `7` canonical confirmations and `47` typed non-apparel exclusions are independently verified. The rest is supporting/conflicting and cannot confirm. |
| path incomplete/unverified | `12` verified-complete path profiles confirm `65`; unverified paths remain review. |
| product-required without product authority | category-alone confirmation remains `0`; verified structured/path/exact evidence can resolve generically. |
| legacy decision incomplete | invalid/incomplete legacy is audit-only and cannot block a stronger independently verified authority. |
| invalid mapping | verified replacements/scopes were applied; all unverified remainder is explicitly revoked. Runtime invalid/revoked authority leaks: `0`. |
| no mapping | independently provable categories were mapped; all unknown/untrusted input now has a deterministic `review_required` route. |
| name-only | no independent basis was sufficient for a real profile; all remain review. Verified-name-last-resort behavior is proven synthetically. |
| revoked exact decision | the one revoked exact row remains non-authoritative and review-required. |

## 4. Set validation proof

Existing semantics were reused, not reinvented:

- `ParsedClosetClassification.isExplicitCompositeGarmentSet` rejects explicit multi-garment bundles and preserves ordinary variants/coordination wording.
- `MusinsaUnsupportedProductPolicy.isTopBottomSet` rejects the retailer's exact `상하의세트` category before size processing.
- Server v4 now consumes the adapter fact `structured_facts.product_structure = set` through the generic verified exclusion rule before any exact/category/path/name authority.

Seven known set products resolve `not_comparable`, including the four required products `5982920`, `6797265`, `6797266`, and `6797271`. Counts: set garment-confirmed `0`, set comparison-allowed `0`. Synthetic `set-in-tshirt` and `homewear-set` also pass; `normal-variant-not-set` remains confirmed.

Actual iOS/adaptor wiring is intentionally deferred to the integration step; this migration does not duplicate keyword logic in SQL.

## 5. CATEGORY_DIRECT final list/count

Final count: **55 rows**, all verified, runtime eligible, and tuple-valid.

| Source | Rows | Unique category IDs | Final authorities |
|---|---:|---:|---|
| Musinsa | 21 | 9 | `001001` short-sleeve T-shirt (6 exact targets), `001010` long-sleeve T-shirt (5), `017016002` sport long-sleeve T-shirt (2), `017016005` sport short-sleeve T-shirt (3), `017018015` puffer (1), kids `106004001/2/3` (3), outlet `107001001007` (1) |
| UNIQLO | 34 | 34 | pure retailer leaves for T-shirts, sleeveless T-shirts, sweatshirts, shirts/polo, sports tops, base-layer tops, knit, leggings, kids/baby T-shirts; exact codes are listed below |
| ZARA | 0 | 0 | current official family/subfamily leaves remain mixed or not independently complete, so no direct authority |

UNIQLO exact category IDs: `100100`, `120302`, `126278`, `126279`, `136608`, `141498`, `141499`, `142638`, `58144`, `58145`, `58154`, `58255`, `58256`, `58274`, `58275`, `58394`, `58395`, `58397`, `58401`, `58407`, `58492`, `58493`, `58584`, `58585`, `58623`, `58624`, `58635`, `58636`, `58685`, `87958`, `95419`, `95437`, `98319`, `98378`.

The two mixed sleeveless categories `001011` and `017016003` are no longer direct: seven mapping rows were downgraded because tank top, sleeveless T-shirt, and bodysuit semantics coexist. Set/excluded products are removed before purity evaluation.

## 6. PRODUCT_REQUIRED final list/count

Final count: **1,019 rows**.

| Source | Rows | Unique category IDs | Unique paths |
|---|---:|---:|---:|
| Musinsa | 216 | 211 | 211 |
| UNIQLO | 738 | 738 | 604 |
| ZARA | 65 | 65 | 65 |

The exact machine list is the release-scoped mapping set in migration 118. Important final cohorts are mixed sleeveless (`7` rows), cardigan categories without a sleeve axis (`7` rows), and knit categories without a sleeve axis (`6` rows). A PRODUCT_REQUIRED mapping alone never confirmed a product (`0`).

## 7. REVOKED / EXCLUDED final list/count

Final mapping scope is exhaustive: `55 CATEGORY_DIRECT + 1,019 PRODUCT_REQUIRED + 2,435 REVOKED = 3,509`; other/legacy/invalid runtime scopes: `0`.

| Source | Revoked rows |
|---|---:|
| Musinsa | 1,702 |
| UNIQLO | 733 |
| ZARA | 0 |

The revoked total includes `335` unverified invalid/replacement-less mappings and `2,100` legacy/rejected/unsupported rows made explicitly non-eligible. Verified exclusions are `15` path profiles covering `93` sock products plus typed exclusions covering `47` UNIQLO accessories and `7` set products. Revoked/invalid lookup leaks: `0`.

## 8. Structured discriminator final contract

`classification_structured_discriminator_rules` is the only new table. Resolver v4 performs an exact generic key/value lookup, then applies optional source category, normalized path, and target scope. Only `verified + runtime_eligible` rows participate. Conflicting matches fail closed. Canonical outcomes must pass tuple validation; exclusion outcomes return `not_comparable` before garment classification.

The resolver contains no `if source == musinsa/uniqlo/zara` branch. Retailer adapters only transfer typed raw facts. Adding a source normally means adapter facts plus DB data, not redesigning taxonomy/classifier/comparison.

## 9. Structured field verified values/count

Original informative cohort was reviewed in full: Musinsa `size_type` 165 audit cohort (166 stored observations in the frozen snapshot), UNIQLO `product_type_kr` 47, and ZARA official taxonomy 30.

- Musinsa unique values: `바지 34`, `원피스 26`, `반소매티셔츠 22`, `점퍼 21`, `스커트 13`, `긴소매티셔츠 11`, `반바지 11`, `민소매 9`, `점퍼_래글런 5`, `헤비아우터 5`, `셔츠 4`, `코트 4`, `반소매_래글런 1`. Most are `SUPPORTING_ONLY`; `민소매` is `CONFLICTING`. Five category-scoped rules safely resolve exactly `7` products: knit-long, polo-short, cardigan-long, anorak-long, and fleece-long.
- UNIQLO has 14 exact accessory values, all `EXCLUSION_SIGNAL`, covering `47`: gloves, scarves/shawls, other, backpack, belt, sunglasses, shoulder bag, shoes, scarf, slippers, umbrella, folding umbrella, cap, and tote bag.
- ZARA `family/subfamily/official_category` values duplicate the stored official path and are `SUPPORTING_ONLY`; new authority rules: `0`.
- Generic rules: `product_structure=set` and `product_scope=non_apparel`.

Verified structured rules: `21`; current canonical confirmations: `7`; structured exclusions: `54`. No supporting/conflicting value contributes to a confirmed count.

## 10. Path fallback final contract

Only verified, complete, auto-eligible profiles under `db-classifier-2026-08-26-final` can resolve. They execute after category/structured authority and before name. Any conflict fails closed. Final profiles: `12`; current confirmed products: `65`. Covered semantics include slacks, blazer, dress length variants, skirt length variants, sports T-shirt/shorts, lounge pants, and cotton trunks/briefs.

## 11. Name fallback final contract

Name is last resort and requires source + normalized category/path context + normalized signature + policy version + verified complete tuple. Raw substring/keyword matches never confirm. Real final profiles: `0`; unverified-name confirmations: `0`. The 49 name-only candidates stay review because independent authority is absent. A synthetic verified profile proves the contract without changing production/candidate truth data.

## 12. Legacy decision final authority rule

1. Verified and complete exact product decision wins.
2. Complete legacy data remains audit evidence, not automatic authority; an independently unresolved semantic conflict returns review.
3. Incomplete/invalid legacy data is never authority and cannot block a stronger verified structured/category/path result.
4. Legacy data alone never confirms.
5. Set/non-apparel exclusion precedes every classification authority.

The decision manifest contains `121` rows (`120 verified`, `1 revoked`), including 14 final overrides. Independently supported translations cover cardigan, zip hoodie, tank top, shirt/blouse, and knit sweater. `E450535` and `E485318` remain unresolved because their paths do not prove a sleeve axis. Expected files were not rewritten.

## 13. Taxonomy completeness

Active comparison groups: `44`; auto-comparable: `39`; current supported single-apparel semantic types without canonical representation: `0`; newly duplicated semantics: `0`.

The final inventory represents tops (including sleeveless T-shirt, tank, cardigan, zip hoodie, knit, polo, sports top, base-layer top), outerwear, bottoms/leggings/skirts, dresses, concrete underwear families, and homewear top/bottom. `base_layer_top` remains under `tops`. `homewear_set`, generic underwear, unknown outerwear, sports-bottom aggregate, and other/non-apparel are non-auto-comparable/exclusion-style groups.

## 14. Comparison policy completeness

The policy version `db-comparison-2026-08-26-final` has the complete unordered matrix: `990 = 44 × 45 / 2` rows. `40` are explicit allows (39 comparable self-family rules plus verified sweatshirt↔hoodie cross-family); `950` are explicit blocks. Fallback allowed: `0`.

Required blocks pass: `tshirt ↔ base_layer_top`, tops ↔ generic underwear, and homewear cross-family. Every active family pair is DB-explicit; absent policy cannot create an accidental allow.

## 15. Measurement policy completeness

Active policy version `2026.07.1` contains `63` rows: tops 6, outerwear 8, bottoms 11, leggings 7, skirts 6, dresses 7, homewear 9, underwear 9. Active comparable families whose major family has no measurement policy: `0`.

The existing score/weight algorithm was not edited. Classification can remain confirmed when a retailer has no usable measurements; comparison returns `insufficient_measurements`.

## 16. 1,608 final shadow distribution

| Status | Count |
|---|---:|
| confirmed | 348 |
| review_required | 1,113 |
| not_comparable | 147 |
| total | 1,608 |

Confirmed authority: exact decision `120`, category direct `156`, verified structured `7`, verified path `65`. Exclusion authority: verified path exclusion `93`, structured exclusion `54`.

Comparison outcome: `comparison_possible 179`, `insufficient_measurements 169`, `review_required 1,113`, `not_comparable 147`.

117 → final transition matrix:

| 117 | Final | Count |
|---|---|---:|
| confirmed | confirmed | 248 |
| confirmed | review_required | 8 |
| review_required | confirmed | 100 |
| review_required | not_comparable | 147 |
| review_required | review_required | 1,105 |

The eight downgrades are intentional safety corrections for mixed sleeveless CATEGORY_DIRECT rows. Existing valid-confirmed unintended regression: `0`. Unexpected confirmed transition: `0`.

## 17. Source distribution

| Source | confirmed | review_required | not_comparable | total |
|---|---:|---:|---:|---:|
| Musinsa | 121 | 266 | 7 | 394 |
| UNIQLO | 227 | 817 | 140 | 1,184 |
| ZARA | 0 | 30 | 0 | 30 |
| Total | 348 | 1,113 | 147 | 1,608 |

## 18. Remaining review_required and exact reasons

Reasons overlap by design:

- `legacy_decision_non_authority`: 790
- `source_mapping_product_required`: 625
- `no_verified_auto_eligible_authority`: 212
- `exact_product_decision_revoked`: 1

Resolver-observed mapping state among review rows: Musinsa `PRODUCT_REQUIRED 11 / NO_MATCH 255`; UNIQLO `PRODUCT_REQUIRED 588 / NO_MATCH 229`; ZARA `PRODUCT_REQUIRED 26 / NO_MATCH 4`.

## 19. DB design issue vs product-truth shortage

DB design blockers: **0**. Every supported input has a deterministic route through exclusion, exact, structured, pure category, verified path/name, or review. Remaining `1,113` are product-truth shortages: stored evidence is incomplete, current categories are mixed, or independent evidence does not authorize a tuple. Live retailer lookup or owner/product adjudication would be required to reduce them safely.

“Any product can be handled” therefore means: supported single garments resolve canonically when verified evidence exists; otherwise they explicitly review; confirmed items with sufficient measurements compare; confirmed items without measurements return `insufficient_measurements`; set/non-apparel/unsupported inputs return an explicit exclusion. It does not mean every input is forced to confirmed.

## 20. Future synthetic fixture result

`29 / 29 PASS`. Coverage includes known pure category; PRODUCT_REQUIRED with/without verified discriminator; tank vs sleeveless T-shirt; set inside a T-shirt category; ordinary color variant; dress, skirt, pants, denim, shorts, cardigan, knit, sweatshirt, hoodie, jacket, coat, blazer, puffer, windbreaker, base layer, true underwear, homewear single/set, non-apparel, verified path, verified-name-last-resort, and unknown insufficient evidence. Arbitrary fallback: `0`.

## 21. Gold / independent regression

Gold exact `3/3`:

- `E482514`: `tops / short_sleeve / tshirt / tshirt / short_sleeve`
- `E454311`, `E456567`: `tops / base_layer_top / base_layer_top / base_layer_top / short_sleeve`

Independent adjudication/31-product/64-assertion expectations were not edited. Of the broader 207-row evidence inventory, 137 product keys occur in the current 1,608 snapshot; expected-review false confirmation is `0`. Twenty expected-confirmed legacy cases remain review instead of being coerced. Canonical vocabulary translations are recorded separately in the manifest.

## 22. Safety leak counts

All are `0`: confirmed invalid tuple; arbitrary fallback; set garment-confirmed; set comparison allowed; revoked/invalid mapping authority; PRODUCT_REQUIRED mapping-alone confirmed; unresolved BOTH_UNTRUSTED auto-confirm; unverified name/path confirmed; generic underwear/tops leak; T-shirt/base-layer leak; generic allow fallback.

## 23. Local PostgreSQL apply/reapply/idempotency

PostgreSQL `17.11`, disposable local cluster. Clean order passed:

`116 local fixture → 113 → 114 → 115 → 116 → 117 → 118 → validation (ROLLBACK) → 118 reapply → validation (ROLLBACK)`.

The final manifest adjustment was reapplied once more and the same full validation passed: products `1,608`, confirmed `348`, review `1,113`, not-comparable `147`, Gold `3/3`, synthetic `29`, category-direct `55`, product-required `1,019`, revoked `2,435`, structured rules `21`, path profiles `12`, exclusion profiles `15`, matrix `990`, all safety leaks `0`. Closure gate: `eligible=true`, blockers `[]`.

Checksums:

- manifest: `f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be`
- final shadow: `fa836a5d45c73da135e4c2b5f064b7291b4babbe20f5571ad66eff31cc77c93e`

## 24. Production unchanged evidence

Supabase project `hnkplvyegonlhumlejst` was queried with SELECT/introspection only.

| Metric | Preflight (06:49:01Z) | Postflight (08:06:32Z) |
|---|---:|---:|
| products | 1,608 | 1,608 |
| decisions | 5,056 | 5,056 |
| history / current | 1,860 / 1,608 | 1,860 / 1,608 |
| releases | 5 | 5 |
| active release | `65d72393-4a40-4e99-b701-fdc1ff865774` | same |
| active mappings | 3,492 | 3,492 |
| latest migration | `20260821090138` | same |

Production write/DDL/migration/apply/activation/history write: `0`. Live retailer/API calls: `0`. Swift/Resolver call-site production switch: `0`.

## 25. DB Classification Closure decision

**GO.** Canonical DB representation, authority scopes, generic structured evidence, legacy precedence, verified fallbacks, exclusions, comparison, measurement policy, current-universe shadow, future behavior, and release gate are complete. Remaining reviews are explicitly fail-closed product truth, not missing DB architecture. No further “classification DB audit phase” is required.

## 26. Production deployment readiness

The separate deployment runbook is `Docs/FitMatchClassificationProductionDeploymentReady-20260826.md`. It fixes migration order 113→118, preimage backups, atomic candidate activation, release gates, public/internal v3→v4 switches, Closet/Compare/iOS call sites, smoke fixtures, rollback successor, and rollback acceptance. Execution is not authorized in this task.
