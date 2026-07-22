# Codex Session Handoff

Updated: 2026-07-21 (Asia/Seoul)

## Resume instructions

Read this file and `AGENTS.md` before editing. Preserve the current working tree. Do not reset, clean, stash, amend, commit, or push unless the user explicitly requests it.

## Git state

- Branch: `fix/unified-musinsa-size-pipeline`
- HEAD: `eb241a705c7d2eef58d02367731dcf80faccabc8`
- HEAD message: `버그수정`
- Remote push was not performed in the completed work.
- Current uncommitted change:
  - `FitMatch/Views/MyClosetView.swift`
  - Closet list metadata changed from `대분류 · 세부 카테고리` to `대분류 · 세부 카테고리 / 사이즈`.
  - This is intentional and must be preserved.

## Most recent completed work

Commit `eb241a7` contains the fixes for the seven baseline test failures found during the full regression audit.

### Production fixes

- `FitMatch/Services/UniqloParser.swift`
  - Supports both Uniqlo `result: [...]` and `result: { items: [...] }` response shapes.
  - Replaced dictionary iteration-dependent measurement lookup with deterministic alias priority.
  - Prevents canonical `.other` from overwriting a more specific detected Uniqlo detail category such as cardigan.
- `FitMatch/Services/RecommendationHistoryStore.swift`
  - Reuses persisted product sizes during recompare.
  - Detaches and deletes transient replacement product/size graphs to prevent duplicate `ProductSize` persistence.
- `FitMatchTests/FitMatchTests.swift`
  - Recompare fixtures now use a matching long-sleeve detail category when testing long-sleeve products.
  - Product measurement-record duplication is checked within the product graph, excluding unrelated reference-garment records.
  - Cross-source Uniqlo/FitMatch comparison expectation reflects exact canonical-code compatibility.

### Seven original failures addressed

1. `musinsaRecompareReusesPersistedSizeByName`
2. `resultReferenceChangePersistsLatestSelectionWithoutDuplicatingProductGraph`
3. `uniqloRecompareWithDifferentReferenceKeepsSingleProductGraph`
4. `uniqloBottomCircumferencesBecomeWidthsAndPreserveRawValues`
5. `uniqloSizeAPIParserUsesSizeChartAndRemovesDuplicateSizeNames`
6. `uniqloJSONLDParserHandlesArrayAndBreadcrumb`
7. `uniqloJSONLDParserHandlesSingleProductObject`

## Verification results

- All seven targeted tests passed together.
- The Musinsa recompare persistence test passed three consecutive iterations.
- Deterministic unit suite: 177 passed, 0 failed, 0 skipped.
  - Result bundle: `/tmp/FitMatchSevenFixDeterministicFinal.xcresult`
- Live tests in the preceding full run both passed:
  - `LiveMusinsaValidationTests/circumferencePipelineSamples`
  - `LiveMusinsaValidationTests/rejectedImageSamples`
- A preceding 179-test run ended with one concurrency-sensitive Musinsa persisted-size duplicate failure; the transient graph cleanup was added afterward, and the deterministic suite plus three repeated targeted runs then passed.
- Protected scroll file and modifier-call diffs were empty after the work.

## Prior full regression audit

- Environment:
  - Xcode 26.3 (`17C529`)
  - macOS 15.7.7 (`24G720`)
  - Dedicated simulator: iPhone 17, iOS 26.3.1
  - Simulator UUID: `2D3180C9-2B32-4B9B-A8CB-0D40CB0FCB5E`
- Debug and Release builds passed, including Share Extension embedding.
- Existing UI tests were launch-only smoke tests and passed 6/6; they do not cover full interaction flows.
- Live Musinsa details succeeded for 6391245, 6219777, 6045676, and 6177065; all four actual-size responses returned `data: null`.
- Verified fallback results:
  - 6391245: XS/S/M garment chest circumference 90/95/100.
  - 6219777: five garment chest circumference values 110/115/120/125/130.
  - 6045676: seven garment chest circumference values 113/122/127/132/137/142/147; `화장` remains center-back sleeve meaning.
  - 6177065: separate front/back length records verified by fixture; live end-to-end parser coverage remains incomplete.

## Important architecture and product rules

- Keep actual-size API first; fallback only when null or invalid.
- Preserve measurement canonical codes and exact-code comparison.
- Do not equate chest circumference with chest width.
- Do not equate sleeve length with center-back sleeve length.
- Do not merge front and back lengths.
- Preserve Reference Garment selection policy, recommendation weights, UI architecture, and SwiftData schema unless explicitly requested.
- Never modify `FitMatch/Components/TabBarScrollVisibilityModifier.swift` or protected modifier call sites without explicit authorization naming that behavior/file.

## Current UI request status

- The latest user request was implemented but remains uncommitted:
  - In the closet list card beside the product image, keep the existing category text and append size.
  - Current format: `상의 · 반팔 / M` (values vary by item).
- Grid cards were not changed because the request specifically referred to information beside the product image.

## Known remaining coverage gaps

- No comprehensive UI automation for onboarding, tab navigation, manual closet CRUD, link registration, populated-data relaunch persistence, favorites, share-extension interaction, network error states, recovery PhotosPicker, Dynamic Type, or protected scroll bounce behavior.
- 6177065 lacks a dedicated live end-to-end parser test.
- Release build previously emitted a Swift 6 future actor-isolation warning involving `UserFit.replaceMeasurementRecords(with:)` and `MeasurementLegacyBackfillService.migrationVersion`; it was not part of the requested seven fixes.

## Required final safety checks for future tasks

Run before completion:

```bash
git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift
git diff | grep -E "hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll"
```

Both must show no unauthorized relevant diff.
