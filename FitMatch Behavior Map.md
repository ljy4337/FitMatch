# FitMatch Behavior Map — Codex Edition

- Code baseline: `ae69b30ed37386f6361882d36bafbd972235ebd4` / `connectDB`
- Updated: 2026-09-15. Adapted from the user-supplied map based on `a68c8496628eb0bc1223b34708fb88e8fe945de1`.
- Supabase project: `hnkplvyegonlhumlejst`. This identifier is context, never write authorization.
- Local owners checked against this baseline. Server cleanup status comes from the dated handoff/postflight; this documentation update did not re-query or change Production.

## 0. Read protocol / authority

1. Read `AGENTS.md` and the current-state portion of `Docs/CodexSessionHandoff.md`. Use the flow index below to select the task's flow.
2. Read that flow's READ FIRST owners, then follow actual calls into downstream owners/RPCs. For deeper Swift ownership use `FitMatch Swift Feature Map.md` selectively.
3. Verify current Git state and actual implementation before edits. If a path or contract has drifted, search that subsystem narrowly and repair this map. Expand the search only when dependencies require it.

This is a navigation map, not a substitute for source, deployed function definitions, authorization, or test evidence. RPC existence in source/migrations does not prove deployment. Historical handoff entries may be superseded by newer entries. Update affected flows when ownership/contracts change; keep incident chronology and test counts in the handoff.

| ID | Invariant |
|---|---|
| P-AUTH-01 | Retailer API/parser supplies facts. Preserve raw evidence; do not infer FitMatch policy from names. |
| P-AUTH-02 | DB/server owns comparison groups, readiness, authorization and approved candidate context. |
| P-AUTH-03 | Swift routes, transports, validates and displays; required missing authority must fail closed or enter explicit recovery. |
| P-AUTH-04 | UNMAPPED routes to explicit A–G selection; user choice never silently rewrites global mappings. |
| P-ID-01 | Preserve exact product/variant/size and selected Closet identity. No first-item or visible-label substitution. |
| P-COMP-01 | Comparison Group + active group policy is authority; detailed garment classification is not the primary gate. |
| P-REF-01 | User chooses a server-approved Closet candidate. No automatic/permanent Reference Garment policy. Legacy names alone do not imply dead code. |
| P-MEAS-01 | At least one common authorized canonical measurement is necessary; ownership, group, structure, semantics, unit eligibility and fingerprints must also pass. |
| P-STOCK-01 | SOLD_OUT/UNKNOWN/expiry are availability facts; they must not change eligibility, scores, ranking, closest size or reliability. |
| P-SAVE-01 | Authoritative persistence precedes success UI/cache mutation. Retries preserve identity and idempotency. |

## 1. Flow index / app surface

| Task | Flow |
|---|---|
| Startup/login | FLOW-APP-BOOT |
| Share extension | FLOW-SHARE |
| Link/retailer loading | FLOW-PRODUCT-LOAD + provider section |
| A–G classification | FLOW-GROUP-AUTHORITY |
| Closet add by link / manual | FLOW-CLOSET-LINK / FLOW-CLOSET-MANUAL |
| Closet list/edit/delete | FLOW-CLOSET-MANAGE |
| Comparison orchestration | FLOW-COMPARE |
| Candidate list / begin failure | FLOW-CANDIDATES / FLOW-COMPARE-BEGIN |
| Result / history | FLOW-RESULT / FLOW-HISTORY |
| Search / favorite | FLOW-SEARCH-FAVORITE |
| Logout / account deletion | FLOW-MY-ACCOUNT |
| Measurements / cache / errors | FLOW-TAXONOMY-MEASURE / FLOW-SYNC / FLOW-ERROR-RECOVERY |

Tabs in `FitMatch/Views/AppTab.swift`: Home (`.home`), Compare (`.compare`), History (`.history`), Recommend (`.recommend`), My (`.my`). Primary views respectively: `FitMatch/Views/HomeView.swift`, `FitMatch/Views/CompareFlowSheet.swift`, `FitMatch/Views/RecommendationHistoryView.swift`, `FitMatch/Views/RecommendView.swift`, `FitMatch/Views/MyPageView.swift`. Closet is reached through app navigation, not a separate enum tab.

## 2. Flow catalog

### FLOW-APP-BOOT — 앱 시작·인증·루트

READ FIRST: `FitMatch/FitMatchApp.swift`, `FitMatch/ContentView.swift`, `FitMatch/Services/FitMatchAuthSessionStore.swift`, `FitMatch/Services/FitMatchAuthenticatedRootPresentationAction.swift`.

ModelContainer/environment → session observation/recovery → authenticated or unauthenticated root → tabs. Supabase Auth is the session authority; a UI mock login is not a real authenticated server session.

### FLOW-SHARE — 공유 링크 → 앱

READ FIRST: `FitMatchShareExtension/ShareViewController.swift`, `FitMatch/Services/SharedURLStore.swift`, `FitMatch/ContentView.swift`.

Read URL/plain text → App Group pending URL → active app consumes SharedURLStore → link/Compare routing. Verify consumption/routing separately from physical Share Sheet handoff.

### FLOW-PRODUCT-LOAD — 상품 링크 불러오기

READ FIRST: `FitMatch/Services/ProductURLParserService.swift`, `FitMatch/ViewModels/ShoppingProductViewModel.swift`, `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`.

Provider resolver → details/measurements → ParsedProductInfo → fitMatchProductObservationRequest() → resolveFreshRetailerProductAuthority() → product-observation Edge → public.fitmatch_vnext_ingest_product_observation → internal ingestion/v2 → public.fitmatch_vnext_get_product_runtime → get_product_runtime_for_swift → DTO/contract validation → validated UI state.

Downstream: `supabase/functions/product-observation/index.ts`, `FitMatch/Services/FitMatchVNextDTOs.swift`, `FitMatch/Services/FitMatchVNextContractValidator.swift`. Replay payload owner: `FitMatch/Services/FitMatchProductAuthorityPayloadBuilder.swift`; preserve retailer variant identity across persistence/replay. Storage: products, product_variants, product_sizes, product_size_measurements, product_ingestion_receipts, size_availability_observations in fitmatch_vnext.

### FLOW-GROUP-AUTHORITY — Comparison Group 판정

Applied to user-confirmed development project (2026-09-16, subsequent explicit approval): exact UNIQLO two-key renamed-path compatibility and ZARA skirts waist/hips aliases. Owner SQL: `supabase/sql/uniqlo_path_zara_skirt_20260916_Apply.sql`; current verification/authorization in handoff and `Docs/QA/ApprovedSafeRepair-20260916.md`.

READ FIRST: `FitMatch/Services/FitMatchVNextDTOs.swift`, `FitMatch/ViewModels/ShoppingProductViewModel.swift`, `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`.

fitmatch_vnext.product_comparison_group → product override / exact retailer category mapping → mapped A–G or unresolved state. ZARA official details product.id must match source_product_key; exact section/familyId/subfamilyId key lookup now precedes presentation-path compatibility. Unknown keys retain explicit user group selection. Applied development repair: supabase/sql/zara_exact_category_identity_Apply.sql; local regression: supabase/sql/tests/zara_exact_category_identity_LocalRegression.sql. comparison_target_context validates requested session group. Compare selection uses session context; explicit Closet choice is persisted with its provenance. Automatically displayed group is not an explicit user mutation. Tables: fitmatch_catalog.product_comparison_group_overrides, source_category_comparison_groups, comparison_groups, comparison_group_policies.

### FLOW-CLOSET-LINK — 링크 상품 → 내 옷장 추가

READ FIRST: `FitMatch/Views/LinkClosetRegistrationView.swift`, `FitMatch/Views/AddComparedProductToClosetSheet.swift`, `FitMatch/Services/FitMatchClosetFormAction.swift`.

FLOW-PRODUCT-LOAD → exact selected product/variant/size → linked creation payload (`use_server_measurements=true`, `measurements=[]`) → public.fitmatch_vnext_upsert_closet_item → server canonical snapshot → authoritative success/read-back → cache sync. `MeasurementResolver.sourceDisplayRows` owns registration display of every exact retailer row; canonical rows must not replace or coalesce raw rows. `20260921110000_closet_raw_measurement_snapshots.sql` prepares immutable linked Closet raw snapshots in `closet_item_source_measurements`; it is not applied to `hnkplvyegonlhumlejst`. If the automatic group is unchanged, omit comparison_group_code; if unresolved, require explicit A–G choice. Linked Closet size menus display every received Product size, preserving exact IDs even when registration evidence is missing. AddComparedProductToClosetSheet.selectableSizes no longer filters by isRegisterable; selected-size guidance and save-time eligibility/identity checks remain separate. Inspect ShoppingProductViewModel and SupabaseProductResolver for payload/identity contracts. Storage: closet_items + closet_item_measurements + (prepared) closet_item_source_measurements.

Payload owners: `closetCreationPayload` → deployed `apply_linked_closet_snapshot_for_swift`. The opt-in flag applies only to linked creation; manual creation and linked update keep the existing explicit measurement contract. Server still checks auth, exact hierarchy, group, semantic conflicts and canonical completeness. Preserve request fingerprint/idempotency. Review/apply/postflight: `supabase/sql/core_registration_candidate_contract_Apply.sql` / `_Verify.sql`.

### FLOW-CLOSET-MANUAL — 직접 입력 → 내 옷장 추가

READ FIRST: `FitMatch/Views/AddClosetItemView.swift`, `FitMatch/ViewModels/AddClosetItemViewModel.swift`, `FitMatch/Services/FitMatchClosetManualRegistrationAction.swift`, `FitMatch/Services/FitMatchClosetFormAction.swift`.

User enters item/size/measurements and explicit group → manual payload → public.fitmatch_vnext_upsert_closet_item → success → local projection. Do not fabricate linked retailer identities.

### FLOW-CLOSET-MANAGE — 옷장 조회·수정·삭제

READ FIRST: `FitMatch/Views/MyClosetView.swift`, `FitMatch/Views/ClosetItemDetailView.swift`, `FitMatch/Services/FitMatchClosetItemEditAction.swift`, `FitMatch/Services/FitMatchClosetDeletionAction.swift`.

public.fitmatch_vnext_list_closet_items → cache projection → exact item edit via fitmatch_vnext_update_closet_item / delete via fitmatch_vnext_delete_closet_item → authoritative success → cache update. Classification override set/clear transport remains in SupabaseProductResolver; verify actual call sites before treating it as current exposed UX or a removal candidate.

Deletion owner detail: `FitMatchClosetDeletionAction` → `FitMatchClosetSyncCoordinator.deleteServerFirst` → `FitMatchClosetDeletionTransaction`. Serializes with uploads: deletion waits for an active sync (100ms asynchronous checks, bounded at 300 waits), then acquires the same coordinator lock before any deletion work. Account-generation changes/cancellation stop waiting; a stalled sync returns explicit retry guidance. Validates account/exact receipt, journals ambiguous intent, then commits local deletion. Pending retry reconciles already-absent server rows and removes remaining local data before uploads. Missing deletion service never means success. Duplicate Closet client/server identities fail closed through `FitMatchVNextContractValidator.uniqueIdentityIndex`. Tests: `FitMatchClosetDeletionTransactionTests` and the no-Simulator contract script.

### FLOW-COMPARE — 상품 비교 전체

READ FIRST: `FitMatch/Views/CompareFlowSheet.swift`, `FitMatch/ViewModels/ShoppingProductViewModel.swift`, `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`, `FitMatch/Services/RecommendationService.swift`.

URL → FLOW-PRODUCT-LOAD → mapped group or explicit session group → FLOW-CANDIDATES → user picks Closet item → eligible sizes / authorization / begin → engine → complete → result/history. Comparison summary accessibility labels include the owned size to distinguish multiple Closet entries for the same product. Summary cards explicitly label local rankings/sizes as estimates; detail reauthorizes and computes from the server snapshot, so numeric parity is not yet verified. Card navigation hints/chevrons must not deny server-approved candidates solely because local preview evidence is insufficient. Never display a successfully saved result before completion persistence is confirmed.

### FLOW-CANDIDATES — 비교할 내 옷 후보

READ FIRST: `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`.

referenceSelectionPlan() → target/session context + server Closet data → public.fitmatch_vnext_find_reference_candidates → fitmatch_vnext.find_reference_candidates → server-filtered list. Swift displays approved candidates; user chooses one. Empty candidates are an explicit state, not permission for local fallback.

Candidate transport validates exact requested product/variant and unique Closet IDs across selectable/blocked arrays through `FitMatchVNextContractValidator.validateCandidateEnvelope` before projection (both RPC overloads). Regression: `FitMatchCandidateEnvelopeTests`; local no-Simulator runner: `scripts/test-candidate-envelope.sh`. Both deployed 2-arg functions now preserve same-group priority without legacy reference sorting/decision authority. Allowed candidates use explicit manual selection. SQL: `supabase/sql/retire_reference_candidate_authority_Apply.sql`; local regression: `supabase/sql/tests/retired_reference_candidates_LocalRegression.sql`. Historical reference facts remain read-only data, not a selection decision.

Mapped 2-argument candidates now call `eligible_candidate_sizes` for each exact target variant and return only authorized size IDs; zero eligible sizes exclude that Closet candidate. Requested-group overload retains its existing session-context validation. Same-group summary remains separate from explicit cross-group choices. Candidate eligibility uses >=1 common canonical policy metric for any A–G group pair after explicit selection; begin reauthorization remains mandatory.

A↔B domain repair: `unclassified_outerwear` is UPPER_BODY in comparison_domain_20260908. CompareFlowSheet row selection uses membership in the server-approved plan, not local preview evidenceState; explicit selection still reauthorizes through eligible/begin. User approved broader cross-group authorization on 2026-09-16: mapped and session-selected targets accept any valid Closet group on explicit selection, subject to common canonical policy evidence and existing ownership, identity, structure, audience and semantic checks. Do not restore same-group/A↔B-only candidate restrictions or domain-only rejection for explicit selection. Apply/verify owners: `supabase/sql/explicit_cross_group_comparison_Apply.sql`, `supabase/sql/explicit_cross_group_comparison_Verify.sql`; regression: `supabase/sql/tests/explicit_cross_group_comparison_Regression.sql`. Repair SQL: `supabase/sql/cross_group_outerwear_domain_Apply.sql`; isolated regression: `supabase/sql/tests/cross_group_outerwear_domain_Regression.sql`.

### FLOW-COMPARE-BEGIN — 선택 후보 → 비교 허가·Begin

READ FIRST: `FitMatch/Services/FitMatchServerAuthorityCoordinator.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`.

public.fitmatch_vnext_eligible_candidate_sizes → server eligible_candidate_sizes / authorize_comparison_with_context → public.fitmatch_vnext_begin_comparison → fitmatch_vnext.begin_comparison. Trace nested authorization in deployed SQL; do not assume it is a separate public Swift RPC. Validate owner, product/variant/size, common metrics, semantics, unit/structure/group and candidate/effective fingerprints. Stale or forged context fails closed. Legacy-named begin_comparison_legacy_20260914 remains required by the mapped/no-requested-group path at the reviewed baseline.

### FLOW-RESULT — 결과 표시·옷장 추가

READ FIRST: `FitMatch/Services/RecommendationService.swift`, `FitMatch/Views/RecommendationResultView.swift`, `FitMatch/Views/AddComparedProductToClosetSheet.swift`.

Server begin snapshot / approved metrics → local calculation of size scores, differences, confidence/coverage → public.fitmatch_vnext_complete_comparison → confirmed result presentation. Result-to-Closet uses FLOW-CLOSET-LINK and exact snapshot/selected identities.

Performance navigation: both result titles and the alternative-size sheet are owned by `FitMatch/Views/RecommendationResultView.swift` (alternativeSizeComparisonSheet). For rendering cost follow reportMeasurementPresentations → supplementalMeasurementItems → `FitMatch/Services/FitMatchResultSupplementalComparisonCache.swift` → MeasurementComparisonEngine.compare. This view-lifetime memo keys full measurement/provenance inputs and exact identities; it never authorizes or saves comparisons; for sheet entry follow presentAlternativeSizeComparison → prepareAlternativeSizeAnalyses. Performance repair and measurement boundaries: `Docs/ResultScreenPerformanceAudit.md`.

Sleeve exclusion diagnostics: `FitMatchVNextDTOs.VNextAuthorizedCandidateDTO` retains optional canonical measurements; `VNextComparisonEngineAdapter.sleevePresentationExclusions` uses frozen candidate/reference definitions only for display. `RecommendationResultView.alternativeMeasurementSummaries` shows the exclusion reason. `MeasurementComparisonEngine.authorizedMeasurementIdentity` keeps shoulder-seam, centre-back and raglan sleeve codes distinct. No inferred conversion or score change is permitted for mismatched bases.

### FLOW-HISTORY — 비교 기록

READ FIRST: `FitMatch/Views/RecommendationHistoryView.swift`, `FitMatch/Services/FitMatchComparisonSyncCoordinator.swift`, `FitMatch/Services/VNextHistoryCacheHydrator.swift`.

public.fitmatch_vnext_comparison_history → local projection → search/sort/filter/detail → recompare or result Closet registration. Visibility action uses public.fitmatch_vnext_hide_comparison_history. Transport: FitMatchSupabaseProductResolver. Local removal alone is not server deletion proof.

### FLOW-SEARCH-FAVORITE — 검색·즐겨찾기

READ FIRST: `FitMatch/Views/GlobalSearchView.swift`, `FitMatch/Services/FavoriteProductStore.swift`.

Search app content → display matching items → URL favorite state. Inspect concrete result sources in the view before assuming remote catalog search.

### FLOW-MY-ACCOUNT — My·계정 관리

READ FIRST: `FitMatch/Views/MyPageView.swift`, `FitMatch/Services/FitMatchAccountDeletionAction.swift`, `FitMatch/Services/FitMatchAuthSessionStore.swift`.

Help/support/privacy → logout or explicit account deletion → server deletion action → authenticated cache cleanup. Downstream Edge owner: `supabase/functions/delete-account/index.ts`. Account deletion requires explicit authorized test scope; never infer permission from general QA.

### FLOW-TAXONOMY-MEASURE — 실측 표준화

READ FIRST: `FitMatch/Services/CanonicalComparisonProfileResolver.swift`, `FitMatch/Services/ComparisonProfileMatcher.swift`, `FitMatch/Services/CanonicalTaxonomyBundleStore.swift`.

Raw retailer code/label/value/unit evidence → server source_measurements / source_measurement_mappings / source_measurement_aliases → canonical fitmatch_measurements → comparison_metrics / comparison_policies. Semantic conflicts are excluded or blocked; raw and canonical values remain separate. Group authority and measurement readiness are separate concerns.

Measurement semantic-context separation (prepared 2026-09-21): `supabase/migrations/20260921090000_measurement_semantic_context_separation.sql` resolves each raw row in its product-native context first. A category/group context is retained only as a verified fallback for an otherwise `UNMAPPED` native row, preserving detailed-category-missing recovery without overwriting resolved meaning. `product_measurement_readiness` reports canonical and policy-selected counts separately; comparison metrics remain the only score-input selector. Local regression: `supabase/sql/tests/measurement_semantic_context_separation_LocalRegression.sql`; read-only post-apply query: `supabase/sql/measurement_semantic_context_separation_Verify.sql`. Prepared only, not applied to `hnkplvyegonlhumlejst`.

UNIQLO front-length/AIRism repair (2026-09-17): `supabase/sql/uniqlo_front_length_airism_{Apply,Verify}.sql`, regression `supabase/sql/tests/uniqlo_front_length_airism_LocalRegression.sql`. See `Docs/QA/UniqloFrontLengthAirism-20260917.md` for applied/pending state. Preserve front/back and shoulder-seam/center-back sleeve distinctions. Canonical interpretation coverage is separate from active comparison metrics; never discard valid raw facts because a group mapping is absent. Owner policy now treats verified MEN AIRism upper-garment categories as A; do not extend that rule to AIRism briefs/trunks.

Verified ZARA dictionary additions (2026-09-16): current parser `zara_kr_size_measure_guide_v1`, sleeve zone in tops/outerwear → `sleeve_length`, hem zone in dresses → `hem_width`, chest zone in outerwear → existing `chest_width`. Apply/Verify: `supabase/sql/measurement_dictionary_verified_zara_{Apply,Verify}.sql`. No canonical/policy expansion. UNIQLO `front-rise` remains unverified by exact KR method/context; do not infer bottoms from its name or master proposal.

### FLOW-SYNC — 서버 ↔ SwiftData

READ FIRST: `FitMatch/Services/FitMatchClosetSyncCoordinator.swift`, `FitMatch/Services/FitMatchComparisonSyncCoordinator.swift`, `FitMatch/Services/VNextHistoryCacheHydrator.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`.

Authoritative persistence/read-back → exact Closet/history cache projection. Relaunch/account transitions must preserve ownership and hydrate from server. Cache is not authority; ambiguous transport must not display success.

### FLOW-ERROR-RECOVERY — 오류·회복

READ FIRST: `FitMatch/ViewModels/ShoppingProductViewModel.swift`, `FitMatch/Services/FitMatchVNextContractValidator.swift`, `FitMatch/Services/FitMatchDebugLogger.swift`.

Distinguish retailer URL/details/measurements failure from observation/auth/domain/runtime failure. CompareFlowSheet missing-candidate diagnostics report the server plan rather than legacy local detailed-category matching. ScrollPerformanceDiagnostics retains counters/summary; per-frame output is opt-in with FITMATCH_VERBOSE_SCROLL_DIAGNOSTICS=1. UNMAPPED → explicit group picker; missing sizes/measurements → supported recovery; NOT_APPLICABLE cannot be bypassed by picker. Preserve technical diagnostics internally and show actionable user copy. Do not mislabel contract/DB rejection as generic network failure.

Release diagnostics: `FitMatchMetricsRecorder` is the existing local aggregate/event owner, independent of DEBUG logging. `FitMatchSupportView` in `ReleaseInformationView.swift` exports app/build/OS metadata, counters and the latest 20 typed events on explicit user sharing; no automatic remote collection. ZARA domains resolve separately; no raw URL/product/measurement/user data enters events. Native recorder regression: `scripts/test-metrics-diagnostics.sh` (minimal unrelated domain stand-ins, no UI/server).

## 3. Provider contracts

### PROVIDER-MUSINSA

READ FIRST: `FitMatch/Services/MusinsaURLResolver.swift`, `FitMatch/Services/MusinsaParser.swift`, `FitMatch/Services/MusinsaProductMetadataParser.swift`; measurement recovery: `FitMatch/Services/MusinsaFallbackSizeParser.swift`.

- Inputs: musinsa.com/products/{id}, musinsa.onelink.me/PvkC/{token}. Resolve redirect/body evidence to exact product ID; canonicalize direct URL.
- Details: goods-detail.musinsa.com/api2/goods/{id}; measurements: same path /actual-size. Preserve official category paths/codes, goods identity, metadata and raw units/labels.
- Recovery uses actual retailer table/image evidence (including CREMA chart selection/cropped OCR). Preserve unknown raw columns and arm-circumference evidence; do not convert product-name guesses into group authority.
- `goodsContents` structure evidence must be extracted from visible HTML text. CSS, tags, and attributes are not garment-component declarations; a markup-only legacy composite match is emitted as explicit `UNKNOWN` so a fresh observation clears the stale `SET` fact without inventing `SINGLE`.
- Check size labels and numeric cells against the actual source image, not merely successful parsing. Preserve externalVariantID through saved/replayed facts.
- Closet snapshot rejection after successful loading: inspect `fitmatch_vnext.apply_linked_closet_snapshot_for_swift` and compare every transported metric against `canonical_measurements_for_size_with_context` for the exact selected size. MUSINSA `actual_size` / bottoms / 총장 maps to `musinsa.outseam.waist_to_outer_hem` → `outseam`; tops/outerwear 총장 remains back length. Repair and read-only regression: `supabase/sql/musinsa_bottom_total_length_Apply.sql`, `supabase/sql/musinsa_bottom_total_length_Verify.sql`. Deployment/test status lives in the handoff.

### PROVIDER-UNIQLO

READ FIRST: `FitMatch/Services/UniqloParser.swift` (also defines UniqloSizeAPIParser); transport: `FitMatch/Services/FitMatchSupabaseProductResolver.swift`.

- Preserve E###### core, input suffix, price-group path, colorDisplayCode, sizeDisplayCode and pldDisplayCode evidence.
- Details use the URL-resolved price group through `UniqloURLResolver.productDetailsURL`, matching stock context, at commerce/v5/ko/products/{product}/price-groups/{group}/details; derive exact size-chart/stock requests from the parser, not an invented endpoint.
- Compare official color-specific/generic charts when the specific chart is missing/incomplete; keep clothing measurements distinct from body-size recommendations.
- Stock failure leaves UNKNOWN; never infer measurements or comparison eligibility from availability.
- E491320 -000/-001/-002 semantic equivalence remains unverified. Do not assert equality solely because details requests normalize the core ID. Preserve official breadcrumb, audience, collection and length facts.

### PROVIDER-ZARA

READ FIRST: `FitMatch/Services/ZARAParser.swift`, `FitMatch/Services/FitMatchSupabaseProductResolver.swift`. Auxiliary audit owner: `FitMatch/Services/ZARAWebViewMetadataAudit.swift`.

Server canonical mapping is separate from local parser mapping. For zone-name-chest in TOPS, inspect source_measurement_aliases → zara.chest_width.chest_pit_to_pit → chest_width. Repair/postflight: `supabase/sql/zara_top_chest_alias_Apply.sql`, `supabase/sql/zara_top_chest_alias_Verify.sql`. A missing canonical alias can produce zero common measurements despite matching group A; sleeve/detail labels are not evidence of server rejection.

- URL style number is not automatically the server product identity.
- Detail product.id → internalProductID/source_product_key; selected colors[].productId → catentryID. These may differ.
- Parser success reports valid garment facts even with one metric or raw-only meanings. It does not impose a local two-metric/waist-plus-hip comparison gate. Canonical eligibility and missing-measurement recovery remain server-authoritative; body-only, invalid unit and empty garment guides still fail closed.
- Unresolved local category/detail must not discard a valid garment guide. Verified chest/sleeve semantic zones remain mapped for `.other`; other unverified zones remain raw-only. Both Closet and Compare consume this shared parser/observation path, with server A–G selection and eligibility unchanged.
- Measurement request must use the exact selected catentryID; distinguish garment measureGuideInfo from body sizeGuideInfo. Inspect parser-built official endpoints/parameters.

### Retired provider

COSParser.swift was removed in cleanup. COS is not an active supported parser owner or evidence of launch readiness. Do not restore it or its retired tests incidentally.

## 4. Group / readiness presentation matrix

These are conceptual UI states; actual DB/DTO enum spellings and state combinations must be checked in `FitMatch/Services/FitMatchVNextDTOs.swift` and the contract validator.

| Group / measurement state | Presentation | Comparison |
|---|---|---|
| Mapped / ready | Group shown, then candidate choice | Only after server candidate/begin authorization |
| Mapped / missing sizes | Keep group, offer size recovery | Block until valid |
| Mapped / missing measurements | Keep group, offer measurement recovery | Block until valid |
| Unmapped / eligible structure | Explicit A–G picker | Server validates selected session context and measurements |
| Excluded / not applicable | Explain inability to compare | Picker cannot bypass exclusion |
| Session user selected | Candidates for validated context | Target group/identity/fingerprints revalidated; no global write |

## 5. DB navigation and deployment checks

Use flow-specific RPCs above. Public fitmatch_vnext_* wrappers and internal fitmatch_vnext functions are distinct layers; inspect exact signatures/overloads, grants and callers before changes.

| Concern | DB owners |
|---|---|
| Group | fitmatch_catalog.comparison_groups, comparison_group_policies, source_category_comparison_groups, product_comparison_group_overrides; fitmatch_vnext.product_comparison_group / comparison_target_context |
| Runtime/readiness | get_product_runtime_for_swift, effective_target_classification, effective_product_readiness, product_readiness_with_context, product_measurement_readiness, product_comparison_unit_decision |
| Product evidence | fitmatch_vnext.products, product_variants, product_sizes, product_size_measurements, product_ingestion_receipts, size_availability_observations, source_identifiers |
| User persistence | fitmatch_vnext.closet_items, closet_item_measurements, comparisons |
| Measurement policy | fitmatch_vnext.source_measurements, source_measurement_mappings, source_measurement_aliases, fitmatch_measurements, comparison_metrics, comparison_policies |
| Classification compatibility | Existing catalog/history/axis/feedback tables are not removal candidates merely because detailed classification is no longer the primary gate. Follow callers and provenance dependencies. |

Reviewed cleanup: eligible product_readiness_with_context delegates to product_measurement_readiness while retaining unit/recovery guards and ACL. SET/multiple-component exclusion remains. Do not replace the entire effective readiness chain with an unconditional READY or metric-count check.

Retired signatures (not live routing): effective_target_classification_detail_legacy(uuid), legacy_comparison_group(text), authorize_comparison(uuid,uuid,uuid,boolean). The distinct authorize_comparison_with_context path remains current.

Read-only postflight source: `supabase/sql/cleanup_retired_paths_Verify.sql`. Applied repair sources: `supabase/sql/group_only_ingestion_axes_Apply.sql`, `supabase/sql/cleanup_retired_paths_Apply.sql`. File presence is not deployment evidence. The pending `supabase/migrations/20260915093000_align_confirmed_group_readiness_contract.sql` is now a read-only compatibility gate, not an outstanding readiness rewrite. Deployment dates/evidence belong in `Docs/CodexSessionHandoff.md`; do not automatically apply SQL while navigating this map.

## 6. Failure map / diagnostic labels

The IDs below are documentation labels, not claims about literal runtime error codes.

| ID | Stage / inspect | Expected handling |
|---|---|---|
| LOAD-F01 | URL resolver | Link correction |
| LOAD-F02 | Retailer details | Product-load failure |
| LOAD-F03 | Retailer measurements | Partial facts / measurement recovery |
| LOAD-F04 | Observation payload identity | Stop invalid transport |
| LOAD-F05 | Edge submit / auth / HTTP | Distinguish login, network and response failure |
| LOAD-F06 | DB ingestion / trigger/domain | Preserve domain diagnostics internally |
| LOAD-F07 | Runtime fetch / DTO | Explicit server-response failure |
| LOAD-F08 | Authority validation | Fail closed on invalid state combination |
| GROUP-F01 | Unmapped | A–G picker, not generic server error |
| GROUP-F02 | Excluded/not applicable | Comparison blocked |
| CLOSET-F01 | Exact identity mismatch | Save blocked |
| CLOSET-F02 | Automatic group sent as explicit | Correct payload provenance |
| COMP-F01 | No approved Closet candidates | Empty candidate state |
| COMP-F02 | No common authorized metric | Comparison blocked |
| COMP-F03 | Stale/forged context | Revalidate / retry |
| COMP-F04 | Completion snapshot/size mismatch | No confirmed result success |
| AUTH-F01 | Missing/expired/unauthorized session | Authentication recovery |

## 7. Focused verification entry points

| Area | Test source | Evidence boundary |
|---|---|---|
| URL/category / UNIQLO live regression | `FitMatchTests/LiveMusinsaValidationTests.swift` | Opt-in external retailer audit; not authenticated ingestion |
| Full supplied retailer parser corpus | `FitMatchTests/FitMatchReleaseLiveProductAuditTests.swift` | External URL corpus/configuration required; do not replace with fixtures |
| MUSINSA repair / labels and raw measurements | `FitMatchTests/FitMatchReleaseParserRepairTests.swift` | Inspect each test's live/fixture mode |
| Payload/DTO / exact identity / unmapped routing | `FitMatchTests/FitMatchSupabaseProductResolverTests.swift` | Includes suppliedUnmappedProductsRouteToExplicitGroupSelectionWithoutServerError; fixture routing is not live persistence |
| Server-authority orchestration | `FitMatchTests/FitMatchServerAuthorityIntegrationTests.swift` | Inspect injected remote boundary before claiming real-server coverage |
| Contract closure | `FitMatchTests/FitMatchContractClosureRegressionTests.swift` | Focused contract regression |
| ZARA | `FitMatchTests/ZARAParserPhase1_5Tests.swift` | Provider identity/facts; inspect mode |
| Closet / history synchronization | `FitMatchTests/FitMatchClosetSyncCoordinatorTests.swift`, `FitMatchTests/FitMatchComparisonSyncCoordinatorTests.swift` | Cache/transport contracts |
| Current UI | `FitMatchUITests/FitMatchReleaseCurrentUIAuditTests.swift` | Simulator UI; mock authentication is not actual login |

Discover available scheme/destination before execution. Record PASS/FAIL/NOT RUN/BLOCKED per layer. Parser success does not prove every numeric cell, server save or comparison completion. Real Apple login, authenticated save/read-back/relaunch, cross-account checks and physical Share Sheet/gestures require separate evidence. Device/iOS claims from a user are context, not executed compatibility tests.

## 8. Current-state pointers and fast recipes

The supplied pre-cleanup risk list is superseded for slacks mapping, mandatory legacy axes and the readiness wrapper by the 2026-09-15 applied-repair/cleanup entries in `Docs/CodexSessionHandoff.md`. Do not reapply old proposals from the original map. Remaining provider suffix uncertainty and physical/authenticated verification boundaries are recorded above; consult the latest handoff for changes.

- **Link fails:** exact provider/key → resolver/details → observation identity → Edge response → ingestion rejection → actual runtime DTO/validator → only then group/UI routing.
- **Unmapped:** inspect product_comparison_group → explicit Closet/session picker → DB revalidation; never require obsolete detailed recovery or write global mapping.
- **After candidate choice:** candidates → eligible → nested authorization → begin → complete; compare owner/product/variant/size/group/fingerprints at every boundary.
- **Old data suspected:** trace actual readers and deployed wrapper dependencies, then use read-only postflight; a legacy name or historical row alone does not authorize deletion.
