# Continuous lifecycle smoke preparation

Scope: QA HEAD `086617f`, production owners with synthetic RPC receipts and an in-memory SwiftData store. No live DB, Auth, schema, policy, product-code, or UI mutation. These probes use only positive 50/56/61 cm facts and make no zero-display assertion. The current MUSINSA dash exception is documented in MeasurementPolicy and the later ExpectationAudit; earlier parent claims of a blanket zero-hidden override were corrected.

## Prepared selectors

| Scenario | Selector under `FitMatchTests/FitMatchReleaseLifecycleTests` | Executed owners and assertions |
|---|---|---|
| 1 register → read → async edit → read → delete → read | `manualRegistrationReadAsyncEditReadDeleteReadPreservesExactIdentity()` | `AddClosetItemViewModel.makeUserFit` → `registerManualServerFirst` → authoritative read-back/projector → fresh SwiftData context read → `saveManualClosetEdit` → current `updateClosetItem` and verified receipt → fresh context read → `FitMatchClosetDeletionAction.delete` → `deleteServerFirst`/`FitMatchClosetDeletionTransaction` → fresh local/remote reads. The same client and server Closet IDs survive the edit; a second registered row stays unchanged through deletion. |
| 4 measurement edit → compare | `asyncManualMeasurementEditRereadsBeforeExplicitNewComparison()` | Current asynchronous manual edit changes chest 50 → 56; authoritative receipt and fresh SwiftData read provide the next selected item. `loadServerReferenceSelectionPlan` returns the exact IDs and performs no eligible/begin/complete work. Explicit `calculateTemporaryRecommendation` then runs coordinator authorization/eligible/begin → production engine → complete; its approved evidence uses reference 56 and target 57. The saved old receipt remains 50. No independent numeric-score claim is made. |

Status: **PASS**, both selectors executed in `/tmp/FitMatchPendingSmokeChecked/app.xcresult`. The combined run had 39 passing methods and 1 separate matrix failure (51 passing parameter-expanded executions, 1 failure). This is synthetic remote evidence, not authenticated DB evidence.

## Alternative-size and other-Closet seams

- Existing sequence 2 already exercises the shared ViewModel's second explicit Closet selection and exact approved alternative batches. This file adds candidate discovery after asynchronous mutation and verifies discovery cannot start comparison automatically.
- The actual alternative-size selection state is **BLOCKED within this headless-only scope**: `RecommendationResultView` owns private `@State selectedAlternativeSizeID`, `temporarySizeAnalysis`, and `temporaryDisplayedProductSizeID`; `analyzeSelectedAlternativeSize`, `prepareAlternativeSizeAnalyses`, and their cache are private View methods. There is no public production action that owns this state transition. Changing visibility/extracting an owner would edit production UI code; copying the logic into a test would not exercise the actual state. A user-authorized XCUI run with a seeded/authorized result is required for the sheet selection/rendering claim.
- The actual other-Closet button transition is likewise **BLOCKED within this headless-only scope**: `CompareFlowSheet.showCurrentComparisonCandidates` is inside a private extension and clears private selection/step state. Its ViewModel comparison and candidate owners are covered, but the SwiftUI callback, rendered step, and tap state are not.
- Existing `FitMatchServerAuthorityIntegrationTests/resultReferencePickerUsesServerAuthorizationForEveryActiveLocalClosetItem()` separately covers the older Result discovery action. It is reused as evidence rather than duplicated or presented as proof of the current callback's UI state.

## Evidence limits

- The stateful actor records synthetic upsert/update/delete calls and returns typed receipts. It proves Swift sequencing, exact identities, local persistence, and isolation; it does not prove RLS, remote deduplication, SQL atomicity, real Auth, cross-device propagation, or deployed RPC policy.
- Lifecycle 1 uses manual registration/editing. Linked size-edit raw-snapshot and observation contracts remain separate existing tests; this is not a claim that every retailer's linked lifecycle ran.
- Lifecycle 4 uses an opaque same-group authorized begin fixture and invokes real scoring owners. It does not establish a new formula, rounding, tie policy, or independent score oracle.
- Fresh SwiftData contexts share one in-memory container. This verifies persisted local reads, not an application restart or physical-device cold start.
