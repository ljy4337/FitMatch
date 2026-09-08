# FitMatch Contract Closure — 5 GAP implementation result (2026-09-07)

## Scope and source

- Start / end local HEAD: `43b10e2b88b4ebdaeefe51ab9a06a33cb7f245a4` on `connectDB` (`fix: repair closet edit compilation`). No commit or push was made, so the end source is the same uncommitted worktree on that HEAD.
- `origin/connectDB` was rechecked at start and matched `43b10e2b88b4ebdaeefe51ab9a06a33cb7f245a4`.
- The direct iCloud-managed checkout did not reliably load Xcode project state. A non-iCloud temporary copy of the changed source was used for compilation/XCTest. The changed production/test files were kept byte-identical with the worktree before each final test run.
- Final SHA-256 comparison confirmed all 22 production/test/SQL artifacts used by that temporary build match their worktree counterparts. Documentation was not part of the temporary build input.
- No Production DB/RPC write, migration apply, Edge deploy, account mutation, commit, push, reset, clean, stash, or branch change occurred.

## Implemented boundaries

| GAP | Before | After | Main production locations |
| --- | --- | --- | --- |
| F01 | Client attempted a public History-hide RPC not installed in Production; untyped RPC failures could only fall through to a generic failure. | Added the manual-only SQL artifact, typed RPC failure classification, and preserved exact receipt validation before any local delete. Missing RPC, auth, invalid receipt, and uncertain transport cannot delete local cache. | `supabase/sql/FitMatchContractClosureHistoryHide.sql`, `FitMatchHistoryVisibilityAction`, `FitMatchSupabaseProductResolver`, `FitMatchComparisonSyncCoordinator` |
| F02 | Foreground compare Tasks were not owned by the sheet lifetime and could complete after a later request or account change. | The sheet owns separate load/compare handles with UUID request generations and starting user ID. Every foreground UI/store/save transition is gated; old cleanup cannot clear a newer task. The persistent sheet root distinguishes normal input → Result from real dismissal. | `CompareFlowSheet`, `ShoppingProductViewModel`, `FitMatchComparisonSubmissionAction`, `FitMatchServerAuthorityCoordinator`, `RecommendationService` |
| F03 | Frozen vNext reference IDs did not directly equal their active Closet source ID, so delete/warning callers missed related histories. | Added deterministic projection-aware `referencesClosetItem(clientItemID:)`; Closet delete, list warning, and detail warning all use it. No SwiftData/DB column was added. | `RecommendationHistory`, `FitMatchClosetDeletionAction`, `MyClosetView`, `ClosetItemDetailView` |
| F04 | Begin could infer missing `result_status` as `PENDING`; readiness had a default measurement-required interpretation. | Begin status is required and closed (`PENDING`/`COMPLETED` only). Readiness uses an exhaustive eight-state enum; unknown/malformed values are contract failures and policy-unavailable remains blocked. | `FitMatchVNextDTOs`, `FitMatchVNextContractValidator`, `FitMatchSupabaseProductResolver`, `FitMatchServerAuthorityCoordinator` |
| F05 | Snapshot checks accepted future versions through lower-bound comparisons and replay could use the current engine. | Added exact supported snapshot set `{3, 4}`, schema-4 personal-authority requirement, exact completed engine `fitmatch-ios-vnext-snapshot-v1`, pending-engine rule, top/nested mismatch checks, and pre-insert hydrate/sync validation. Unsupported/broken rows become parity warnings, not pending network retries. | `FitMatchVNextContractValidator`, `VNextComparisonEngineAdapter`, `VNextHistoryCacheHydrator`, `FitMatchComparisonSyncCoordinator`, `FitMatchVNextDTOs` |

## Tests and verification actually run

The following ran against the non-iCloud source copy on simulator `FitMatch-Regression-20260721` (iOS 26.3):

| Command scope | Result | Evidence |
| --- | --- | --- |
| App build | PASS | `build_sim_2026-09-07T22-20-48-212Z_pid11758_8bc0e843.log` |
| `FitMatchContractClosureRegressionTests` + `FitMatchComparisonSyncCoordinatorTests` + `FitMatchVNextContractTests` + `FitMatchComparisonPermitSequencingTests` | **33 passed, 0 failed, 0 skipped** | `test_sim_2026-09-07T22-58-31-210Z_pid11758_6f81a395.xcresult` |
| Required existing eight classes (`FitMatchVNextContractTests`, `FitMatchComparisonPermitSequencingTests`, `FitMatchComparisonSyncCoordinatorTests`, `FitMatchServerAuthorityIntegrationTests`, `FitMatchSupabaseProductResolverTests`, `FitMatchReviewRequiredRecoveryTests`, `FitMatchP0ProductionPathTests`, `FitMatchHeadlessUserJourneyTests`) | **187 passed, 5 failed, 0 skipped** | `test_sim_2026-09-07T23-00-34-387Z_pid11758_59347cfa.xcresult` |

The five failures are all in `FitMatchSupabaseProductResolverTests` and concern existing variant/preferred-size preparation:

1. `resultClosetPreparationKeepsSoleVNextVariantWhenPreferredSizeHasGone`
2. `resultClosetPreparationLeavesInvalidExactPreferenceUnselected`
3. `resultClosetPreparationSelectsUniqueLegacyVariantByExactPreferredSizeID`
4. `resultClosetPreparationSelectsUniqueVNextVariantByExactPreferredSizeID`
5. `sourceVariantKeyStillWinsForMultiVariantURLLoadWithoutPreference`

They were reproduced on an exact `43b10e2b88b4ebdaeefe51ab9a06a33cb7f245a4` archive with only the current compile-compatible test fixture spelling (`brand`, not removed `brandName`), where `FitMatchSupabaseProductResolverTests` reported **41 passed / 5 failed**. They are therefore baseline failures, not claimed as fixed or introduced by this scope. The fixture spelling correction preserves its assertion semantics and was made only after the actual test-target compiler error was reproduced.

New `FitMatchContractClosureRegressionTests` covers the exact hide-receipt gate (F01), invalidated-vs-new submission ownership (F02), real `saveCompletedVNext` frozen-reference identity (F03), closed readiness/missing begin status (F04), and direct unsupported DTO rejection at the engine boundary (F05). Existing sync/permit/contract tests cover schema-4 hydrate → original-Closet relation, owned PENDING recovery, server-first deletion, account-switch sync isolation, and permit ordering.

## SQL deployment state

| Item | Status |
| --- | --- |
| Manual SQL prepared | **YES** — `supabase/sql/FitMatchContractClosureHistoryHide.sql` |
| Isolated local PostgreSQL H01–H08/H12 execution | **NOT RUN** — no separate local DB was provided for this task |
| Production applied | **NO** |

The requested attached `01_apply_history_hide.sql` was not available in the workspace or temporary work area. The prepared manual file was derived from the repository’s `20260906090000_vnext_hide_comparison_history.sql` plus the stated fixed-code/installation-guard contract; it requires operator review before any manual Production use. It does not claim migration-history application.

## Invariants and remaining verification

- No score, weight, required measurement, tie-breaking, parser classification/extraction, canonical mapping, unit conversion, stock/recommendation policy, completed snapshot numeric result, or policy/engine formula was changed.
- No SwiftData or DB schema/column was added.
- `FitMatch/Components/TabBarScrollVisibilityModifier.swift` and the protected scroll modifier call sites have no diff.
- The SQL behavior cases H01–H08/H12 remain **not run**, and no Production substitute was used.
- The full app test suite is not claimed green; only the stated classes were executed. The five baseline resolver failures remain separately reproducible.
