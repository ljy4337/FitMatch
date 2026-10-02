> **Superseded current-status summary (scoped preparation revision 20):** The initial NOT RUN and missing-HTTP/continuous-chain statements below are preserved as historical notes. Current mapping is [PreparationCoverage20.md](PreparationCoverage20.md) and [requirement-coverage-v1.json](requirement-coverage-v1.json). Resume30 preserved evidence is 56 methods/75 executions PASS, including async lifecycle1/4, continuation3, mounted sequence2, seven status-specific save faults and actual Task.cancel. Numeric persisted History has one new focused preparation test pending root execution. Live Auth/DB, mass full and device/release evidence remain separate. No prior run is relabeled as a new run.

# Core function coverage — 2026-10-02

## Policy expectations fixed before implementation inspection

Source: current `AGENTS.md`, `Docs/FitMatchMeasurementPolicy.md`, current-state handoff, and the Behavior Map's Closet/Compare/Result/History flows. This is a test acceptance contract, not a new product policy.

1. Closet success requires authoritative persistence and exact read-back. Failed/ambiguous operations preserve retry identity; linked edits preserve the exact product, variant, selected size and observation receipt. Raw source facts remain separate from canonical comparison data. MUSINSA zero rows display `-`; other invalid display rows remain preserved as facts but are excluded from comparison.
2. Comparison requires a user-selected server-approved same-group Closet item, exact approved size identities and fresh begin authority. Only approved snapshot metrics contribute. No implicit first candidate, label-based identity repair, cross-group fallback or local category inference is acceptable.
3. Signed difference is candidate minus selected Closet measurement. The active server weights are authoritative. A deterministic numeric oracle must specify literal inputs and literal expected differences, weighted score, rank, coverage and reliability independently of the production engine. Every expected input must name its metric identity/basis/unit.
4. Completion persistence precedes successful result/history presentation. A failed retry cannot create duplicate visible histories. A newer completed result replaces only the current visible head for the exact target product; historical snapshot evidence stays immutable.
5. Alternative sizes can use only exact sizes approved in the current batch or restored from the exact completed History snapshot. Other-Closet selection must obtain new authorization/begin/completion; it cannot mutate the displayed old result. Result-to-Closet uses normal linked persistence with exact selected product/variant/size.
6. Closet and History deletion require server acknowledgement before local success. Failed/network-ambiguous operations remain retryable. Late responses after cancellation/account changes cannot commit outgoing-account data; unrelated/shared product identities remain intact.
7. MUSINSA, UNIQLO and ZARA must be accounted for separately. Synthetic snapshot fixtures, captured real retailer facts, current live APIs, authenticated development persistence and physical-device UI are distinct evidence layers. A local test does not prove the latter layers.

## Execution status

PASS: The initial 28 core smoke selector methods exist in their stated Swift test types; the added committed-response-loss method and both modified/new Swift test files pass `swiftc -frontend -parse`. Raw retailer replay selectors are added independently by the main task. This is syntax/manifest validation only. XCTest execution is coordinated by the main task to avoid concurrent Xcode builds; authoritative execution results belong to the main run report. All selector statuses initially remain NOT RUN.

## Production entrypoints inspected

| Core | Visible action → existing owner → remote boundary |
|---|---|
| A/H save | `AddComparedProductToClosetSheet.saveSelectedSize` → `prepareServerFirstSubmission` → `FitMatchComparedProductClosetSubmissionAction.submitServerFirst` → `fitmatch_vnext_upsert_closet_item` → exact `fitmatch_vnext_get_closet_item` → `projectAuthoritativeRegistration` → success. Manual new registration uses `registerManualServerFirst`. Result/History preparation returns to the same linked sheet. |
| B edit | `ClosetItemDetailView` edit sheet: imported `submitLinkedEdit` → `saveLinkedClosetEdit`; manual `onSaveAsync` → `saveManualClosetEdit` → `fitmatch_vnext_update_closet_item` → validated read-back → local projection. The older synchronous `FitMatchClosetItemEditAction.saveManual` test is only partial evidence for this active async path. |
| C delete | My Closet swipe / detail delete confirmation → `FitMatchClosetDeletionAction.delete` → `deleteServerFirst` → `FitMatchClosetDeletionTransaction` → associated completed History hide → exact `fitmatch_vnext_delete_closet_item` receipt → local commit. |
| D compare | Candidate tap in `CompareFlowSheet` → `calculateAndSaveTemporaryRecommendation` → ViewModel `calculateTemporaryRecommendation` → coordinator candidate authorization/begin → `RecommendationService.analyzeVNextComparison` → `VNextComparisonEngineAdapter` → `completeAuthorizedComparison` → `fitmatch_vnext_complete_comparison` → History projection/save → result step. |
| E History delete | `RecommendationHistoryView` confirmed delete → `FitMatchHistoryVisibilityAction.delete` → `hideVNextComparisonHistories` → `fitmatch_vnext_hide_comparison_history` → local delete → persisted tombstone. |
| F size | `RecommendationResultView.prepareAlternativeSizeAnalyses` → current session batch or `recoverVerifiedAlternativeSizeAnalysis` for exact completed row → `canPresentCurrentVNextAlternativeSizes` → exact selected size cache → temporary displayed analysis. No new completion occurs for a temporary size switch. |
| G other Closet | Current result callback returns to current candidate plan; explicit selected candidate runs fresh authorization/begin/complete. History callers enter `CompareFlowSheet(initialHistoricalProduct:)`; old History target remains detached. |

## Core A–H smoke mapping

Executable exact selectors and evidence labels are in `smoke-selectors.json`; broad follow-up types are in `full-selectors.json`. These are real production Swift owners with synthetic remote contracts unless marked otherwise.

| Requirement | Smoke IDs | Limit |
|---|---|---|
| A exact selected save / duplicate | A, A-duplicate/8 | Authenticated read-back / live UI NOT RUN. |
| B target-only edit, reread, next comparison | B, B-rejection, 4 | Async linked projection and manual stale read-back covered separately; combined edit→reread→compare chain NOT RUN. |
| C deletion isolation | C, C/6, fault-delete-ambiguous | Server transport scripted; physical UI and remote cross-device state NOT RUN. |
| D score/recommendation/confidence/delta parity | D, D-partial, D-tie, D-malformed, 5 | Independent numeric literal assertions cover preview/detail/completion payload. Same oracle through persisted History renderer NOT RUN. |
| E History deletion | E, E-failure | Modeled second session; actual second-device/authenticated propagation NOT RUN. |
| F alternative size | F, F-stale | Exact two-size History restoration; actual sheet interaction NOT RUN. |
| G other Closet | G | Fresh production recompare with scripted authority; chained UI switches NOT RUN. |
| H result-to-Closet | H, H-retry, A | Payload boundary, retry and server-first save covered separately; whole result→save→new compare chain NOT RUN. |

## Continuous scenarios 1–10

| ID | Reusable evidence | Remaining gap / status before main execution |
|---|---|---|
| 1 register→read→edit→read→delete→read | A + B + C | NOT RUN as one identity-preserving full chain; component selectors available. |
| 2 compare→size→other Closet→size | sequence.2 | PASS: same real ViewModel, fresh begin/complete for changed Closet, exact approved alternative batch and prior-result isolation. Synthetic remote; SwiftUI selected state NOT RUN. |
| 3 compare→Closet save→compare registered item | sequence.3 | PASS: result preparation → server-first submission → exact read-back projector → SwiftData → new comparison using registered item. Synthetic remote; live auth/DB NOT RUN. |
| 4 measurement edit→compare | 4 + B | Existing 4 test invokes older synchronous edit action; current async edit→server reread→fresh compare remains NOT RUN. |
| 5 saved History→new cache/container→read | 5 + F | Synthetic completed History hydration in new container; authenticated cold start NOT RUN. |
| 6 delete Closet→related History | C/6 | Synthetic hide and delete transaction; deployed behavior NOT RUN. |
| 7 request A→B→A late response | 7 + F-stale | ViewModel late request and account response seams; actual transport/UI timing NOT RUN. |
| 8 consecutive save | A-duplicate/8 | Real concurrent action tasks, injected persistence boundary; UI rapid taps NOT RUN. |
| 9 DB commit→response lost→retry | 9-committed-response-lost (+ prior partial tests 9-accepted-response / 9-timeout) | Newly prepared real submission action receives synthetic commit-then-timeout, then retries the identical complete request, performs exact read-back and projects one local row. XCTest NOT RUN here. Actual DB deduplication remains BLOCKED without authorized authenticated persistence evidence. |
| 10 no Closet / common metrics / sizes | 10-empty-closet, 10-no-common, 10-no-size | Synthetic component failures; no authenticated live product matrix. |

## Failure injection scope

| Failure | Current reusable proof | Missing requested proof |
|---|---|---|
| offline | `fault-offline`; scripted transport failure/reconnect in sync | Actual `URLError.notConnectedToInternet` at every save/edit/compare/delete boundary NOT RUN. |
| timeout | `9-timeout` and new `9-committed-response-lost`; real `URLError.timedOut` after synthetic transport acceptance | Deployed commit-before-timeout deduplication and every remaining boundary NOT RUN. |
| malformed | D-malformed, candidate-envelope/contract full suites | Every RPC malformed payload and UI recovery NOT RUN. |
| cancellation | `fault-cancel`, deletion transaction cancellation, F-stale | All View disappearance paths NOT RUN. |
| HTTP 403 / 429 / 500 | No exact status-specific mutation transport seam verified in smoke | BLOCKED for requested matrix; generic scripted error cannot be relabeled as these HTTP statuses. |

## Numeric oracle and policy boundary

`FitMatchReleasePreparationTests` supplies synthetic schema-3 approved replay snapshots directly to production scoring/preview owners. It does not claim current authenticated schema-4 begin or retailer ingestion proof. Literal inputs are chest/shoulder/back-length/shoulder-seam-sleeve in cm; widths/lengths stay distinct. Reference `[50,48,70,60]`, candidate A `[52,47,73,61]`, candidate B `[54,50,76,63]`, weights `[2,1.5,1,1]` give signed deltas `[2,-1,3,1]` / `[4,2,6,3]`, item scores `[90,95,85,95]` / `[80,90,70,85]`, totals 91 / 82, reliability 4, coverage 1. Partial chest/shoulder `[52,48]` gives 94 / reliability 2 / coverage .5. Same label `M` for both sizes is deliberate.

Weights and confidence/coverage separation are documented policy. The `100 − 5×|delta|` item formula, rounding, and UUID tie-break are observed implementation contracts; no separate approved product policy was found. Their tests are characterization, not independent product approval. `policy-expectations.json` marks those three policy gaps UNRESOLVED so a release gate cannot silently convert source behavior into a product decision.

## Retailer evidence boundary

The new numeric oracle is intentionally provider-neutral synthetic canonical evidence. It must not be counted three times by relabeling one fixture MUSINSA/UNIQLO/ZARA. Existing provider parser/captured replay tests and the separate retailer audit must establish each retailer's raw facts and exact identities. In particular ZARA internal product and selected catentry identities remain distinct. Current live source success and authenticated mutation/comparison are separate gates from this document.

## Remaining continuous-chain seams

- Sequence 2's actual alternative selection lives in private View state (`temporarySizeAnalysis`, `temporaryDisplayedProductSizeID`, `alternativePreparationGeneration`) while other-Closet transitions are private `CompareFlowSheet` callbacks. Existing service tests expose approved analysis/recompare boundaries, but cannot prove those state transitions as one chain. An honest complete test needs a UI runner or a separately approved extraction of those state owners; simply invoking two existing tests would not establish continuity.
- Sequence 3's existing History-to-Closet fixture is a private synthetic completed-row fixture; the registration receipt and the next comparison fixture currently allocate separate exact product/variant/size/Closet identities. Connecting them requires one end-to-end transport script that carries the accepted registration receipt into candidate discovery and begin, rather than substituting a pre-existing candidate. This session adds no broad harness and leaves the chain NOT RUN.
- Sequence 9 required only the existing private registration transport seam: its new `.commitThenTimeout` case stores the exact client identity before throwing. Both retry requests are compared as complete request values; the actual submission action's recovery/read-back/projector run unchanged. The fake's one-entry set cannot establish database uniqueness itself.

## Resume verification supplement

`FitMatchReleaseContinuationTests` now executes two continuous owner paths; `FitMatchReleaseTransportFaultTests` executes 15 parameter-expanded runs via real Supabase SDK and app RPC client, with 43 intercepted HTTP requests and zero live DB requests. See `TransportFaultCoverage.md`. Earlier NOT RUN statements above describe the initial preparation pass and are superseded only for these explicitly executed scopes. Final resumed app run: 37 methods / 49 executions PASS, 0 FAIL, 0 skip. Per-run evidence belongs in ResumeReport.md.
