# FitMatch Release QA

Run: qa-20261002T091255Z-1290ad9c
Overall: **FAIL**

Preparation smoke is not release approval. Mock, live parser and DB evidence are separate.

| ID | Status | Evidence |
|---|---|---|
| environment.qa_target | PASS | QA branch required; actual=QA |
| tool.xcodebuild | PASS | Xcode 26.3 Build version 17C529 |
| tool.swift | PASS | Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2) Target: x86_64-apple-macosx15.0 |
| tool.python3 | PASS | Python 3.9.6 |
| safety.db_target | PASS | QA Run/Test + both QA build configurations + shell overrides checked |
| data.freeze | PASS | SHA-256 fixed corpus matches |
| data.urls | PASS | {'musinsa': 30, 'uniqlo': 30, 'zara': 30}; inventory only, not live validation |
| policy.expectations | BLOCKED | UNRESOLVED: score-formula,rounding,tie-break |
| environment.disk | PASS | Free bytes=18357886976; 700MiB minimum to attempt reused build, not a guarantee |
| environment.simulator | PASS | iPhone 17 Pro |
| tool.selftest | PASS | Includes controlled failure, unsafe target, zero tests, corpus drift |
| tool.db_selftest | PASS | Dedicated DB safety tests; not live RPC proof |
| app.build_execution | FAIL | exit=65; {'passedTests': 35, 'failedTests': 2, 'skippedTests': 0} |
| A | PASS | Synthetic remote; real server-first save action and exact authoritative projector; FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/serverFirstClosetSubmissionProjectsExactReadBackReceiptBeforeLocalSuccess |
| A-duplicate/8 | PASS | Two concurrent production action tasks; persistence boundary held; one accepted interaction; FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/comparedProductClosetSubmissionSerializesConcurrentDuplicateSave |
| B | PASS | Synthetic exact linked read-back; production edit projection; FitMatchTests/FitMatchClosetSyncCoordinatorTests/linkedClosetEditProjectsExactServerReadBackBeforeReportingSuccess |
| B-rejection | PASS | Synthetic stale read-back; save cannot publish success; FitMatchTests/FitMatchClosetSyncCoordinatorTests/manualEditDoesNotReportSavedWhenReadbackRetainsPreviousValues |
| C | PASS | Production deletion action; requested local identity only; FitMatchTests/FitMatchComparisonSyncCoordinatorTests/closetDeletionActionRemovesOnlyTheRequestedActiveItemWhenNoHistoryExists |
| C/6 | PASS | Synthetic server hide acknowledgement; original remote evidence retained; FitMatchTests/FitMatchComparisonSyncCoordinatorTests/closetDeletionHidesAssociatedCompletedServerHistoryWithoutDeletingRemoteEvidence |
| D | PASS | Synthetic approved snapshot; independent literal numeric oracle; preview/detail/completion; FitMatchTests/FitMatchReleasePreparationTests/weightedOracleAgreesWithPreviewDetailAndCompletionPayload |
| D-partial | PASS | Two of four policy metrics; literal score94, reliability2, coverage0.5; FitMatchTests/FitMatchReleasePreparationTests/partialOracleKeepsConfidenceSeparateFromCoverageAndSourceFacts |
| D-tie | PASS | Duplicate source label M; exact UUID tie-break with reversed input; FitMatchTests/FitMatchReleasePreparationTests/identicalScoreAndDeltaUseExactUUIDTieBreakIndependentOfInputOrder |
| D-malformed | PASS | Forged signed delta is rejected by production adapter; FitMatchTests/FitMatchReleasePreparationTests/inconsistentSignedDifferenceCannotProduceAnOracleResult |
| E | PASS | Synthetic tombstone; sync plus modeled second session; FitMatchTests/FitMatchComparisonSyncCoordinatorTests/completedServerHistoryHideSurvivesSyncAndModeledSecondSession |
| E-failure | PASS | Synthetic hide transport failure; local cache preserved; FitMatchTests/FitMatchComparisonSyncCoordinatorTests/failedServerHistoryHideLeavesLocalCacheUntouchedForRetry |
| F | PASS | Synthetic completed row; exact two approved IDs restored through production recovery; FitMatchTests/FitMatchComparisonSyncCoordinatorTests/savedHistoryRestoresTwoExactAuthorizedSizeIdentities |
| F-stale | PASS | Wrong comparison ID and account-switch late response fail closed; FitMatchTests/FitMatchComparisonSyncCoordinatorTests/savedHistoryRejectsAnotherComparisonAndLateAccountResponse |
| G | PASS | Production result recompare with synthetic transport; fresh begin/complete; old result intact; FitMatchTests/FitMatchHeadlessUserJourneyTests/resultRecompareRunsANewServerAuthorizedCompletionWithoutMutatingTheOldResultTarget |
| H | PASS | History-to-Closet production payload boundary; synthetic global/personal snapshots; not server persistence; FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests/hi014HistoryToClosetKeepsGlobalAndPersonalAuthorityBoundariesSeparate |
| H-retry | PASS | Production local persistence side-effect failure/retry; exactly one projected row; FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests/cr022ComparedProductSaveFailureThenRetryCreatesExactlyOneClosetRow |
| 4 | PASS | Production edit followed by synthetic current-authority comparison; not authenticated edit/read-back; FitMatchTests/FitMatchFinalReleaseScenarioExecutionTests/cm004ReferenceMeasurementEditFeedsOnlyTheNextComparisonSnapshot |
| 5 | PASS | Completed snapshot reconstructed in fresh SwiftData container; FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/v4PersonalHistoryProjectionSurvivesFreshContainerWithoutTupleSharing |
| 7 | PASS | Production ViewModel A request delayed until B wins; FitMatchTests/FitMatchP0ProductionPathTests/p0LateFirstRequestCannotOverwriteTheLatestProduct |
| 9-accepted-response | PASS | Server accepted response then local failure/retry; same ID no second upsert; not lost-response proof; FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/serverFirstClosetSubmissionReusesClientItemIDAfterLocalFailure |
| 9-timeout | PASS | URLError timedOut then deterministic replay rejection retains immutable request; no server commit proof; FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/timeoutThenReplayRejectKeepsOriginalImmutableRequestLocked |
| 10-empty-closet | PASS | Synthetic empty candidate/Closet receipt; no begin; FitMatchTests/FitMatchHeadlessUserJourneyTests/cp013EmptyClosetHasNoReferenceAndNeverStartsComparison |
| 10-no-common | PASS | Synthetic no eligible evidence; real authority gates block result; FitMatchTests/FitMatchHeadlessUserJourneyTests/cp024RequiredMeasurementAbsenceStatesBlockWithNoCompletedResult |
| 10-no-size | PASS | Synthetic missing size product then retry through actual ViewModel; FitMatchTests/FitMatchP0ProductionPathTests/p0PartialProductLoadExplainsMissingSizesAndRetryRecovers |
| fault-offline | PASS | Scripted remote transport failure and reconnect; production cache sync; FitMatchTests/FitMatchClosetSyncCoordinatorTests/rx006OfflineOwnedColdCacheThenReconnectRetainsOwnedRowsAndRecovers |
| fault-cancel | PASS | Cancellation injected during actual read-back boundary; FitMatchTests/FitMatchClosetSyncCoordinatorTests/manualRegistrationCancellationDuringReadbackDoesNotPublish |
| fault-delete-ambiguous | PASS | Ambiguous delete response then absent-row retry; production transaction; FitMatchTests/FitMatchClosetDeletionTransactionTests/ambiguousNetworkFailureKeepsIntentAndLocalItemThenRetryConfirmsAbsence |
| raw.uniqlo | PASS | Archived raw measurement replay; ZARA page shell synthetic; no live or DB proof; FitMatchTests/FitMatchReleaseRawFixtureTests/uniqloArchivedChartPreserves32RawFacts |
| raw.musinsa | PASS | Archived raw measurement replay; ZARA page shell synthetic; no live or DB proof; FitMatchTests/FitMatchReleaseRawFixtureTests/musinsaArchivedChartPreserves24RawFacts |
| raw.zara | PASS | Archived raw measurement replay; ZARA page shell synthetic; no live or DB proof; FitMatchTests/FitMatchReleaseRawFixtureTests/zaraArchivedGuidePreserves20RawFactsWithSyntheticPageShell |
| 9-committed-response-lost | PASS | Synthetic transport records commit then throws timedOut; real production submission retries same immutable ID and projects exact receipt once; no deployed DB idempotency proof; FitMatchTests/FitMatchFinalReleaseHeadlessAcceptanceTests/committedClosetResponseLostThenRetryReusesExactRequestAndReadback |
| fault.http_transport | PASS | Actual Supabase SDK and FitMatch RPC client via intercept-only URLSession; offline/403/429/500/timeout/malformed/cancelled over six mutation endpoints. Delete transaction failure and success control. No DB write.; FitMatchTests/FitMatchReleaseTransportFaultTests |
| sequence.2 | FAIL | Same real ViewModel compares two explicitly selected Closet items with fresh authority, then reads each exact alternative-size batch; synthetic RPC, not SwiftUI taps.; FitMatchTests/FitMatchReleaseContinuationTests/compareChangeSizeChangeClosetThenChangeSizeKeepsEachApprovedBatch |
| sequence.3 | FAIL | Real result registration preparation, server-first submission, exact readback projection and fresh comparison using the registered item; synthetic RPC, not live DB.; FitMatchTests/FitMatchReleaseContinuationTests/compareRegisterOwnedSizeThenCompareUsingAuthoritativeRegisteredItem |
| app.discovery | PASS | exit=0; parsed errors and requested selector coverage |
| parser.live_execution | PASS | exit=0; actual ProductURLParserService; no DB writes |
| parser.live.input_coverage | PASS | Exact requested URL multiset must match returned rows |
| parser.live.musinsa | PASS | [{'status': 'PARSED_WITH_MEASUREMENTS', 'sizes': 2}] |
| parser.live.uniqlo | PASS | [{'status': 'PARSED_WITH_MEASUREMENTS', 'sizes': 7}] |
| parser.live.zara | PASS | [{'status': 'PARSED_WITH_MEASUREMENTS', 'sizes': 4}] |
| db.contract | BLOCKED | Dedicated authenticated DB preflight exit=2; db-preflight.json |
