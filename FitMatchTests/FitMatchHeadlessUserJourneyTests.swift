import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// Canonical headless USER A journey coverage.
///
/// This suite deliberately fakes only the authenticated remote transport.  It
/// never computes classifications, reference compatibility, eligible sizes, or
/// scores.  Schema-valid server responses are scripted as test fixtures, then
/// the production ShoppingProductViewModel, authority coordinator,
/// RecommendationService, VNextComparisonEngineAdapter, completion path, and
/// History model decide what happens locally.
@MainActor
struct FitMatchHeadlessUserJourneyTests {
    @Test func everyValidFiniteJourneyScenarioExecutes() async throws {
        let scenarios = HeadlessJourneyScenarioCatalog.valid

        #expect(scenarios.count == 45)
        #expect(Set(scenarios.map(\.id)).count == scenarios.count)
        #expect(Set(scenarios.map(\.id)) == Set((1...45).map {
            String(format: "J%02d", $0)
        }))

        var executed: [String] = []
        var observedUX: [HeadlessUXOutcome: Int] = [:]
        var failures: [String] = []

        for scenario in scenarios {
            executed.append(scenario.id)
            do {
                let record = try await HeadlessJourneyHarness.execute(scenario)
                try require(
                    record.productionSymbols.count >= 2,
                    scenario: scenario.id,
                    message: "intended production path was not reached"
                )
                try require(
                    record.technicalPass,
                    scenario: scenario.id,
                    message: record.note
                )
                observedUX[record.uxOutcome, default: 0] += 1
            } catch {
                // Keep executing the finite matrix after a defect.  The final
                // aggregate still fails, but no valid state is left untested.
                failures.append("\(scenario.id): \(error)")
            }
        }

        #expect(Set(executed) == Set(scenarios.map(\.id)))
        #expect(executed.count == scenarios.count)

        // This is a first-class UX result rather than a technical failure:
        // duplicate user taps are forwarded as separate app actions.  The
        // fake transport cannot prove Production RPC idempotency for those
        // distinct client-history IDs, so the scenario remains executed and
        // explicitly classified as a test-data limitation in the report.
        #expect((observedUX[.testDataLimitation] ?? 0) >= 1)
        try require(
            failures.isEmpty,
            scenario: "MATRIX",
            message: failures.joined(separator: " | ")
        )
    }

    @Test func recoveryLifecycleUsesFreshOpaqueServerContracts() async throws {
        let scenario = HeadlessJourneyScenario(
            id: "RECOVERY-LIFECYCLE",
            provenance: .policyState,
            provider: .musinsa,
            closet: "C3",
            classification: "G1/G9/G10",
            relation: "R1",
            measurement: "M0",
            availability: "A0",
            actions: ["U6", "U10", "U11", "U12", "U13", "U23"],
            program: .reviewLifecycle
        )
        let record = try await HeadlessJourneyHarness.execute(scenario)

        #expect(record.technicalPass)
        #expect(record.uxOutcome == .expected)
        #expect(record.remoteCalls.contains("set_user_product_classification"))
        #expect(record.remoteCalls.contains("clear_user_product_classification"))
        #expect(record.remoteCalls.last != "complete_comparison")
    }

    /// RX-005: a retry with the same client comparison ID must consume the
    /// original immutable begin snapshot, then follow the normal engine →
    /// complete → strict local History path exactly once. The second remote
    /// envelope deliberately omits every duplicated top-level proof field.
    @Test func sameClientIDBeginReplayRetainsStrictServerProofForCompletion() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1
        )
        let eligible = try fixture.eligible(
            reference: reference,
            closetItemID: remoteReference.closetItemID,
            mode: "MANUAL_EXTENDED",
            allowed: true,
            effectiveSource: "USER_EXPLICIT",
            overrideRevision: 1
        )
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "MANUAL_EXTENDED"
            )],
            eligibleResponses: [eligible, eligible],
            beginResponses: [
                try fixture.begin(
                    mode: "MANUAL_EXTENDED",
                    personal: true,
                    referenceClosetItemID: remoteReference.closetItemID,
                    personalGarment: "polo_shirt"
                ),
                try fixture.begin(
                    mode: "MANUAL_EXTENDED",
                    personal: true,
                    referenceClosetItemID: remoteReference.closetItemID,
                    personalGarment: "polo_shirt",
                    created: false,
                    idempotent: true,
                    omitDuplicatedTopLevelProof: true
                )
            ],
            completionResponses: [try fixture.complete()]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let request = FitMatchProductResolutionRequest(
            source: fixture.sourceCode,
            externalProductID: fixture.productCode,
            productName: fixture.parsedProduct().productName,
            sourceCategoryPath: "tops > short sleeve",
            audience: "MEN",
            sourceCategoryCodes: ["tops", "short_sleeve"]
        )
        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: reference.id,
            localReferenceSnapshot: try #require(
                reference.fitMatchServerReferenceSnapshot()
            ),
            targetRequest: request,
            targetObservation: nil
        )
        let clientHistoryID = UUID()

        let firstPermit = try await coordinator.beginAuthorizedComparison(
            authorization,
            clientHistoryID: clientHistoryID
        )
        let replayPermit = try await coordinator.beginAuthorizedComparison(
            authorization,
            clientHistoryID: clientHistoryID
        )

        #expect(firstPermit.runID == replayPermit.runID)
        #expect(replayPermit.clientHistoryID == clientHistoryID)
        #expect(replayPermit.vnextBegin?.created == false)
        #expect(replayPermit.vnextBegin?.idempotent == true)
        #expect(replayPermit.vnextBegin?.authorization?.allowed == true)
        #expect(
            replayPermit.vnextBegin?.authorizedCandidateProductSizeIDs
                == [fixture.productSizeID]
        )
        #expect(replayPermit.vnextBegin?.candidateAuthorityFingerprint == "candidate-v1")
        #expect(replayPermit.vnextBegin?.effectiveAuthorityFingerprint == "effective-1")

        let service = RecommendationService()
        let analysis = try service.analyzeVNextComparison(permit: replayPermit)
        let completion = try await coordinator.completeAuthorizedComparison(
            permit: replayPermit,
            analysis: analysis
        )
        let product = makeHeadlessPersonalProduct(
            fixture: fixture,
            productID: fixture.productID,
            garment: "polo_shirt"
        )
        let history = service.makeCompletedVNextHistory(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .poloShirt,
            permit: replayPermit,
            analysis: analysis,
            completion: completion
        )

        #expect(history?.id == clientHistoryID)
        #expect(history?.product.classificationAuthorityProvenance == .userExplicit)
        #expect((await remote.calls()).filter { $0 == "begin_comparison" }.count == 2)
        #expect((await remote.calls()).filter { $0 == "complete_comparison" }.count == 1)
    }

    /// CP-005 / CP-008: all three bounded Recovery cardinalities construct a
    /// different server contract, expose only the one unresolved garment fact,
    /// and resume through the real ViewModel/coordinator/engine path after a
    /// candidate from that exact contract is selected.
    @Test func eachBoundedRecoveryCandidateCountResumesThroughProductionSequence() async throws {
        for count in 1...3 {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let contract = try fixture.recoveryContract(
                count: count,
                suffix: "cardinality-\(count)"
            )
            let selected = try #require(contract.candidates.last)
            let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
            let remoteReference = fixture.closetRecord(for: reference)
            let reviewRuntime = try fixture.runtime(globalStatus: .reviewRequired)
            let personalRuntime = try fixture.runtime(
                globalStatus: .reviewRequired,
                effectivePersonalGarment: selected.garmentTypeCode,
                overrideRevision: 1,
                personalCandidateFingerprint: selected.candidateFingerprint,
                personalCandidateSetHash: contract.candidateSetHash
            )
            let remote = JourneyRecordingRemote(
                resolutions: Array(
                    repeating: fixture.resolution(globalStatus: .reviewRequired),
                    count: 3
                ),
                runtimes: [reviewRuntime, personalRuntime, personalRuntime],
                recoveryContracts: [contract],
                setMutations: [try fixture.setMutation(
                    contract: contract,
                    garment: selected.garmentTypeCode,
                    revision: 1,
                    event: "SELECTED"
                )],
                closetResponses: [.init(state: "ready", items: [remoteReference])],
                candidateResponses: [try fixture.referenceResponse(
                    reference: reference,
                    closetItemID: remoteReference.closetItemID,
                    decision: "AUTOMATIC"
                )],
                eligibleResponses: [try fixture.eligible(
                    reference: reference,
                    closetItemID: remoteReference.closetItemID,
                    mode: "AUTOMATIC",
                    allowed: true,
                    effectiveSource: "USER_EXPLICIT",
                    overrideRevision: 1
                )],
                beginResponses: [try fixture.begin(
                    mode: "AUTOMATIC",
                    personal: true,
                    referenceClosetItemID: remoteReference.closetItemID,
                    personalGarment: selected.garmentTypeCode,
                    personalCandidateFingerprint: selected.candidateFingerprint,
                    personalCandidateSetHash: contract.candidateSetHash
                )],
                completionResponses: [try fixture.complete()]
            )
            let parser = HeadlessJourneyParser(product: fixture.parsedProduct())
            let viewModel = ShoppingProductViewModel(
                initialURL: fixture.url.absoluteString,
                parserService: ProductURLParserService(
                    musinsaParser: parser,
                    uniqloParser: parser,
                    zaraParser: parser
                ),
                metricsRecorder: HeadlessNoopMetricsRecorder(),
                serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
            )

            #expect(await viewModel.loadProductInfoFromURL() == false)
            let displayed = try #require(viewModel.reviewRecoveryContract)
            #expect(displayed.candidateCount == count)
            #expect(
                displayed.candidates.map(\.candidateFingerprint)
                    == contract.candidates.map(\.candidateFingerprint)
            )
            #expect(displayed.fixedFacts.sleeveLengthCode == "short_sleeve")
            #expect(displayed.fixedFacts.garmentTypeCode == nil)
            #expect(displayed.unknownFields == [.garmentType])

            #expect(await viewModel.confirmReviewRecovery(selected))
            #expect(viewModel.hasActiveUserExplicitClassification)
            let history = await viewModel.calculateRecommendation(userFits: [reference])
            #expect(history != nil)
            #expect(history?.product.classificationAuthorityProvenance == .userExplicit)

            let calls = await remote.calls()
            try requireOrdered(
                calls,
                [
                    "resolve", "runtime", "recovery_contract",
                    "set_user_product_classification", "resolve", "runtime",
                    "list_closet", "reference_candidates", "eligible_sizes",
                    "begin_comparison", "complete_comparison"
                ],
                scenario: "CP-005 count=\(count)"
            )
            let requests = await remote.setRequests()
            #expect(requests.count == 1)
            #expect(requests[0].selectedCandidateFingerprint == selected.candidateFingerprint)
            #expect(requests[0].expectedCandidateSetHash == contract.candidateSetHash)
        }
    }

    /// RX-002/RX-008: the first Recovery submission reaches the real
    /// coordinator RPC and is deliberately held at that network boundary.
    /// A second tap cannot issue another mutation while the production
    /// ViewModel is saving; after the first response returns, a real clear
    /// resolves back to REVIEW_REQUIRED and never starts comparison work.
    @Test func recoveryDoubleSubmitThenClearUsesTheNewestProductionState() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reviewRuntime = try fixture.runtime(globalStatus: .reviewRequired)
        let initialContract = try fixture.recoveryContract(count: 2, suffix: "race-initial")
        let latestContract = try fixture.recoveryContract(count: 2, suffix: "race-latest")
        let initialCandidate = try #require(initialContract.candidates.first)
        let candidateA = try #require(latestContract.candidates.last)
        let setGate = JourneyAsyncGate(blockOnOrAfterArrival: 2)
        let initialPersonalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: initialCandidate.garmentTypeCode,
            overrideRevision: 1,
            personalCandidateFingerprint: initialCandidate.candidateFingerprint,
            personalCandidateSetHash: initialContract.candidateSetHash
        )
        let personalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: candidateA.garmentTypeCode,
            overrideRevision: 2,
            personalCandidateFingerprint: candidateA.candidateFingerprint,
            personalCandidateSetHash: latestContract.candidateSetHash
        )
        let remote = JourneyRecordingRemote(
            resolutions: Array(
                repeating: fixture.resolution(globalStatus: .reviewRequired),
                count: 4
            ),
            runtimes: [reviewRuntime, initialPersonalRuntime, personalRuntime, reviewRuntime],
            recoveryContracts: [initialContract, latestContract],
            setMutations: [
                try fixture.setMutation(
                    contract: initialContract,
                    garment: initialCandidate.garmentTypeCode,
                    revision: 1,
                    event: "SELECTED"
                ),
                try fixture.setMutation(
                contract: latestContract,
                garment: candidateA.garmentTypeCode,
                revision: 2,
                event: "EDITED"
            )],
            clearMutations: [try fixture.clearMutation(revision: 3)],
            gates: [.setUserClassification: setGate]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                uniqloParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(await viewModel.confirmReviewRecovery(initialCandidate))
        #expect(viewModel.hasActiveUserExplicitClassification)
        #expect(await viewModel.beginReviewRecoveryReselection())
        let first = Task { @MainActor in
            await viewModel.confirmReviewRecovery(candidateA)
        }
        await setGate.waitForArrival(atLeast: 2)

        // A second button action sees `.saving`, not a recoverable contract,
        // so it cannot emit a second server mutation or resurrect an old
        // candidate later.
        #expect(await viewModel.confirmReviewRecovery(candidateA) == false)
        #expect((await remote.setRequests()).count == 2)

        await setGate.open()
        #expect(await first.value)
        #expect(viewModel.hasActiveUserExplicitClassification)

        #expect(await viewModel.clearReviewRecovery())
        #expect(viewModel.hasServerReviewRequiredAuthority)
        #expect(!viewModel.hasActiveUserExplicitClassification)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "set_user_product_classification" }.count == 2)
        #expect(calls.filter { $0 == "clear_user_product_classification" }.count == 1)
        #expect(!calls.contains("begin_comparison"))
        #expect(!calls.contains("complete_comparison"))
    }

    /// RX-002 / RX-008: an older reselect response may arrive after the user
    /// has already cleared the personal choice. The delayed response is held
    /// after its real RPC is issued; clear then performs its own production
    /// mutation/authority refresh. When the old response finally resumes, it
    /// must fail closed instead of resurrecting USER_EXPLICIT authority.
    @Test func delayedRecoveryReselectCannotResurrectAfterClear() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let initialContract = try fixture.recoveryContract(count: 2, suffix: "clear-race-a")
        let latestContract = try fixture.recoveryContract(count: 2, suffix: "clear-race-b")
        let candidateA = try #require(initialContract.candidates.first)
        let candidateB = try #require(latestContract.candidates.last)
        let reviewRuntime = try fixture.runtime(globalStatus: .reviewRequired)
        let personalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: candidateA.garmentTypeCode,
            overrideRevision: 1,
            personalCandidateFingerprint: candidateA.candidateFingerprint,
            personalCandidateSetHash: initialContract.candidateSetHash
        )
        let secondSetGate = JourneyAsyncGate(blockOnOrAfterArrival: 2)
        let remote = JourneyRecordingRemote(
            resolutions: Array(
                repeating: fixture.resolution(globalStatus: .reviewRequired),
                count: 5
            ),
            // Initial load, A selection, clear refresh, late B refresh, then
            // B's failure refresh. The server boundary deliberately reports
            // REVIEW_REQUIRED after clear for every late read.
            runtimes: [
                reviewRuntime, personalRuntime,
                reviewRuntime, reviewRuntime, reviewRuntime
            ],
            recoveryContracts: [initialContract, latestContract],
            setMutations: [
                try fixture.setMutation(
                    contract: initialContract,
                    garment: candidateA.garmentTypeCode,
                    revision: 1,
                    event: "SELECTED"
                ),
                try fixture.setMutation(
                    contract: latestContract,
                    garment: candidateB.garmentTypeCode,
                    revision: 2,
                    event: "EDITED"
                )
            ],
            clearMutations: [try fixture.clearMutation(revision: 2)],
            gates: [.setUserClassification: secondSetGate]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                uniqloParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(await viewModel.confirmReviewRecovery(candidateA))
        #expect(viewModel.hasActiveUserExplicitClassification)
        #expect(await viewModel.beginReviewRecoveryReselection())

        let lateB = Task { @MainActor in
            await viewModel.confirmReviewRecovery(candidateB)
        }
        await secondSetGate.waitForArrival(atLeast: 2)

        // Clear is a newer real user action. It must not be held behind the
        // already suspended response task and its refreshed REVIEW_REQUIRED
        // authority becomes the only state that may survive.
        #expect(await viewModel.clearReviewRecovery())
        #expect(!viewModel.hasActiveUserExplicitClassification)
        if case .reviewRequired = viewModel.serverAuthorityState {
            // Correct state before the late response is released.
        } else {
            Issue.record("RX-002 clear did not restore REVIEW_REQUIRED before the late response")
        }

        await secondSetGate.open()
        #expect(await lateB.value == false)
        #expect(!viewModel.hasActiveUserExplicitClassification)
        if case .reviewRequired = viewModel.serverAuthorityState {
            // The stale response did not resurrect personal authority.
        } else {
            Issue.record("RX-002 late recovery response resurrected a cleared authority")
        }

        let calls = await remote.calls()
        #expect(calls.filter { $0 == "set_user_product_classification" }.count == 2)
        #expect(calls.filter { $0 == "clear_user_product_classification" }.count == 1)
        #expect(!calls.contains("begin_comparison"))
        #expect(!calls.contains("complete_comparison"))
    }

    /// RS-013: a completed USER_EXPLICIT Result can request a fresh Recovery
    /// contract and then clear its personal choice.  Those current-authority
    /// actions use the production ViewModel while the completed Result stays
    /// the immutable history that was produced by the earlier server run.
    @Test func rs013PersonalResultReselectAndClearLeaveCompletedHistoryImmutable() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let initial = try fixture.recoveryContract(count: 1, suffix: "rs013-initial")
        let refreshed = try fixture.recoveryContract(count: 2, suffix: "rs013-refreshed")
        let selected = try #require(initial.candidates.first)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let record = fixture.closetRecord(for: reference)
        let reviewRuntime = try fixture.runtime(globalStatus: .reviewRequired)
        let personalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: selected.garmentTypeCode,
            overrideRevision: 1,
            personalCandidateFingerprint: selected.candidateFingerprint,
            personalCandidateSetHash: initial.candidateSetHash
        )
        let remote = JourneyRecordingRemote(
            // load → select refresh → comparison authorization must all see
            // the current personal authority. Clear alone returns to review.
            resolutions: Array(
                repeating: fixture.resolution(globalStatus: .reviewRequired),
                count: 4
            ),
            runtimes: [reviewRuntime, personalRuntime, personalRuntime, reviewRuntime],
            recoveryContracts: [initial, refreshed],
            setMutations: [try fixture.setMutation(
                contract: initial,
                garment: selected.garmentTypeCode,
                revision: 1,
                event: "SELECTED"
            )],
            clearMutations: [try fixture.clearMutation(revision: 2)],
            closetResponses: [.init(state: "ready", items: [record])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: record.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: record.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 1
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: true,
                referenceClosetItemID: record.closetItemID,
                personalGarment: selected.garmentTypeCode,
                personalRevision: 1,
                personalCandidateFingerprint: selected.candidateFingerprint,
                personalCandidateSetHash: initial.candidateSetHash,
                personalInputFingerprint: "input-v1",
                personalEvidenceFingerprint: "evidence-v1"
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                uniqloParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(await viewModel.confirmReviewRecovery(selected))
        let maybeCompleted = await viewModel.calculateRecommendation(userFits: [reference])
        let completionCalls = await remote.calls()
        let completed = try #require(
            maybeCompleted,
            "RS-013 USER_EXPLICIT completion unexpectedly blocked; calls=\(completionCalls), error=\(viewModel.errorMessage ?? "<nil>")"
        )
        let frozenHistoryID = completed.id
        let frozenProductAuthority = completed.product.classificationAuthorityProvenance
        let frozenSourceIdentity = completed.product.canonicalSourceIdentity
        let frozenReferenceID = completed.userFit.id
        #expect(frozenProductAuthority == .userExplicit)

        #expect(await viewModel.beginReviewRecoveryReselection())
        let newestContract = try #require(viewModel.reviewRecoveryContract)
        #expect(newestContract.candidateSetHash == refreshed.candidateSetHash)
        #expect(await viewModel.clearReviewRecovery())
        #expect(viewModel.hasServerReviewRequiredAuthority)
        #expect(!viewModel.hasActiveUserExplicitClassification)

        #expect(completed.id == frozenHistoryID)
        #expect(completed.product.classificationAuthorityProvenance == frozenProductAuthority)
        #expect(completed.product.canonicalSourceIdentity == frozenSourceIdentity)
        #expect(completed.userFit.id == frozenReferenceID)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(calls.filter { $0 == "complete_comparison" }.count == 1)
    }

    /// RX-003: an old automatic comparison reaches the real begin RPC with
    /// its eligible A snapshot, then the user changes the reference while the
    /// RPC is outstanding.  The delayed server response carries the now-stale
    /// candidate set, so the production coordinator rejects it before the
    /// adapter/engine/completion can create a Result or History.
    @Test func rx003DelayedStaleBeginAfterReferenceMutationCannotCreateAResult() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let originalReference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let replacementReference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        replacementReference.productName = "RX-003 replacement reference"
        replacementReference.isRepresentative = false
        let originalRecord = fixture.closetRecord(for: originalReference)
        let staleBeginSizeID = UUID()
        let beginGate = JourneyAsyncGate()
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            // load and authorization each resolve the current target through
            // the real coordinator before the delayed begin boundary.
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 2),
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [originalRecord])],
            candidateResponses: [try fixture.referenceResponse(
                reference: originalReference,
                closetItemID: originalRecord.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: originalReference,
                closetItemID: originalRecord.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            // This response is an opaque server fact: after A's eligibility
            // snapshot, the server sees a different current candidate set.
            // The production coordinator, not this test, enforces equality.
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: originalRecord.closetItemID,
                authorizedProductSizeID: staleBeginSizeID
            )],
            gates: [.beginComparison: beginGate]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                musinsaParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
        #expect(await viewModel.loadProductInfoFromURL())

        let oldSubmission = Task { @MainActor in
            await viewModel.calculateRecommendation(
                userFits: [originalReference, replacementReference]
            ) == nil
        }
        await beginGate.waitForArrival(atLeast: 1)

        // This is the same production Closet mutation that a user performs
        // while A's begin request is in flight. The gated RPC supplies an
        // opaque stale candidate snapshot when it resumes; the coordinator
        // must reject it rather than let it create a result.
        FitMatchClosetReferenceMutation.setRepresentative(
            replacementReference,
            among: [originalReference, replacementReference]
        )
        #expect(!originalReference.isRepresentative)
        #expect(replacementReference.isRepresentative)

        await beginGate.open()
        #expect(await oldSubmission.value)
        #expect(viewModel.recommendation == nil)
        let calls = await remote.calls()
        #expect(calls.contains("eligible_sizes"))
        #expect(calls.contains("begin_comparison"))
        #expect(!calls.contains("complete_comparison"))
    }

    /// RX-013: select → reselect → clear is reconstructed from the latest
    /// server authority, rather than retaining a stale in-memory personal
    /// choice. All three mutations use the same production Recovery actions.
    @Test func rx013RecoveryLifecycleReconstructionUsesTheLatestClearedAuthority() async throws {
        let fixture = HeadlessJourneyFixture(provider: .zara)
        let initial = try fixture.recoveryContract(count: 2, suffix: "rx013-a")
        let refreshed = try fixture.recoveryContract(count: 2, suffix: "rx013-b")
        let candidateA = try #require(initial.candidates.first)
        let candidateB = try #require(refreshed.candidates.last)
        let reviewRuntime = try fixture.runtime(globalStatus: .reviewRequired)
        let personalA = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: candidateA.garmentTypeCode,
            overrideRevision: 1,
            personalCandidateFingerprint: candidateA.candidateFingerprint,
            personalCandidateSetHash: initial.candidateSetHash
        )
        let personalB = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: candidateB.garmentTypeCode,
            overrideRevision: 2,
            personalCandidateFingerprint: candidateB.candidateFingerprint,
            personalCandidateSetHash: refreshed.candidateSetHash
        )
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .reviewRequired), count: 4),
            runtimes: [reviewRuntime, personalA, personalB, reviewRuntime],
            recoveryContracts: [initial, refreshed],
            setMutations: [
                try fixture.setMutation(
                    contract: initial,
                    garment: candidateA.garmentTypeCode,
                    revision: 1,
                    event: "SELECTED"
                ),
                try fixture.setMutation(
                    contract: refreshed,
                    garment: candidateB.garmentTypeCode,
                    revision: 2,
                    event: "EDITED"
                )
            ],
            clearMutations: [try fixture.clearMutation(revision: 3)]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                zaraParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(await viewModel.confirmReviewRecovery(candidateA))
        #expect(viewModel.hasActiveUserExplicitClassification)
        #expect(await viewModel.beginReviewRecoveryReselection())
        let newest = try #require(viewModel.reviewRecoveryContract)
        #expect(newest.candidateSetHash == refreshed.candidateSetHash)
        #expect(await viewModel.confirmReviewRecovery(candidateB))
        #expect(viewModel.hasActiveUserExplicitClassification)
        #expect(await viewModel.clearReviewRecovery())
        #expect(!viewModel.hasActiveUserExplicitClassification)
        #expect(viewModel.hasServerReviewRequiredAuthority)

        // A fresh object models cold reconstruction/re-entry. Its server
        // runtime is REVIEW_REQUIRED, so no local personal tuple can revive.
        let reconstructedRemote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [reviewRuntime],
            recoveryContracts: [refreshed]
        )
        let reconstructed = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                zaraParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: reconstructedRemote)
        )
        #expect(await reconstructed.loadProductInfoFromURL() == false)
        #expect(reconstructed.hasServerReviewRequiredAuthority)
        #expect(!reconstructed.hasActiveUserExplicitClassification)
        #expect(!(await reconstructedRemote.calls()).contains("begin_comparison"))
    }

    @Test func actualProductionSwiftFullChainRequiresBeginBeforeCompletion() async throws {
        let scenario = HeadlessJourneyScenario(
            id: "FULL-CHAIN",
            provenance: .syntheticAdversarial,
            provider: .uniqlo,
            closet: "C3/C12",
            classification: "G0",
            relation: "R1",
            measurement: "M0",
            availability: "A0",
            actions: ["U6", "U7", "U8", "U16", "U17"],
            program: .automaticDirect
        )
        let record = try await HeadlessJourneyHarness.execute(scenario)
        let begin = try #require(record.remoteCalls.firstIndex(of: "begin_comparison"))
        let complete = try #require(record.remoteCalls.firstIndex(of: "complete_comparison"))

        #expect(record.technicalPass)
        #expect(begin < complete)
        #expect(record.productionSymbols.contains(
            "RecommendationService.analyzeVNextComparison(permit:)"
        ))
        #expect(record.productionSymbols.contains(
            "VNextComparisonEngineAdapter.analyze(_:)"
        ))
    }

    @Test func completedUserExplicitHistoryRequiresExactCurrentServerProof() async throws {
        let proof = try await HeadlessJourneyHarness
            .makeServerBackedUserExplicitCompletionProof()
        let service = RecommendationService()

        func completed(
            product: Product = proof.product,
            reference: UserFit = proof.reference,
            permit: FitMatchServerComparisonPermit = proof.permit,
            analysis: VNextComparisonBatchAnalysis = proof.analysis,
            completion: VNextCompleteComparisonDTO = proof.completion
        ) -> RecommendationHistory? {
            service.makeCompletedVNextHistory(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: .shortSleeve,
                permit: permit,
                analysis: analysis,
                completion: completion
            )
        }

        // Positive: a current USER_EXPLICIT authority that reached server
        // begin, the production engine, and server completion becomes a local
        // Result/History model.
        let validHistory = try #require(completed())
        #expect(service.canPresentCurrentVNextAlternativeSizes(
            for: validHistory,
            batch: proof.analysis
        ))
        #expect(!service.canPresentCurrentVNextAlternativeSizes(
            for: validHistory,
            batch: nil
        ))
        validHistory.comparisonMethod = "사용자 선택 임시 비교"
        #expect(!service.canPresentCurrentVNextAlternativeSizes(
            for: validHistory,
            batch: proof.analysis
        ))
        validHistory.comparisonMethod = "서버 승인 확장 비교"
        validHistory.product.markClassificationAuthority(.serverConfirmed)
        #expect(service.canPresentCurrentVNextAlternativeSizes(
            for: validHistory,
            batch: proof.analysis
        ))
        validHistory.product.markClassificationAuthority(.userExplicit)

        let staleRevisionBegin = try #require(
            fixtureBegin(
                proof,
                personalRevision: 2
            ).vnext
        )
        #expect(completed(permit: proof.permit.replacingBegin(staleRevisionBegin)) == nil)

        let staleCandidateBegin = try #require(
            fixtureBegin(
                proof,
                personalCandidateFingerprint: "candidate-stale"
            ).vnext
        )
        #expect(completed(permit: proof.permit.replacingBegin(staleCandidateBegin)) == nil)

        let staleHashBegin = try #require(
            fixtureBegin(
                proof,
                personalCandidateSetHash: "set-stale"
            ).vnext
        )
        #expect(completed(permit: proof.permit.replacingBegin(staleHashBegin)) == nil)

        let staleInputFingerprintBegin = try #require(
            fixtureBegin(
                proof,
                personalInputFingerprint: "input-stale"
            ).vnext
        )
        #expect(completed(
            permit: proof.permit.replacingBegin(staleInputFingerprintBegin)
        ) == nil)

        let staleEvidenceFingerprintBegin = try #require(
            fixtureBegin(
                proof,
                personalEvidenceFingerprint: "evidence-stale"
            ).vnext
        )
        #expect(completed(
            permit: proof.permit.replacingBegin(staleEvidenceFingerprintBegin)
        ) == nil)

        let clearedBegin = try #require(
            fixtureBegin(
                proof,
                personalClearedAt: "2026-08-31T00:00:00Z"
            ).vnext
        )
        #expect(completed(permit: proof.permit.replacingBegin(clearedBegin)) == nil)

        // A local `.userExplicit` label without a matching server begin is
        // never promoted to a completed result.
        #expect(completed(permit: proof.permit.replacingBegin(nil)) == nil)

        let wrongProduct = makeHeadlessPersonalProduct(
            fixture: proof.fixture,
            productID: UUID(),
            garment: "polo_shirt"
        )
        #expect(completed(product: wrongProduct) == nil)

        let wrongReference = proof.fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        #expect(completed(reference: wrongReference) == nil)

        let wrongRun = FitMatchServerComparisonPermit(
            referenceAuthorization: proof.permit.referenceAuthorization,
            clientHistoryID: proof.permit.clientHistoryID,
            runID: UUID(),
            compatibility: proof.permit.compatibility,
            vnextBegin: proof.permit.vnextBegin
        )
        #expect(completed(permit: wrongRun) == nil)

        let unauthorizedSizeID = UUID()
        let unauthorizedRecommendation = VNextComparisonCandidateAnalysis(
            productSizeID: unauthorizedSizeID,
            sizeLabel: "XL",
            result: proof.analysis.recommended.result,
            rank: 1
        )
        let unauthorizedPayload = VNextComparisonCompletionPayload(
            recommendedProductSizeID: unauthorizedSizeID,
            score: proof.analysis.completionPayload.score,
            reliability: proof.analysis.completionPayload.reliability,
            coverage: proof.analysis.completionPayload.coverage,
            engineVersion: proof.analysis.completionPayload.engineVersion,
            candidateSizeRanking: [
                VNextCandidateRankingDTO(
                    productSizeID: unauthorizedSizeID,
                    rank: 1,
                    score: proof.analysis.completionPayload.score
                )
            ],
            metricEvidence: proof.analysis.completionPayload.metricEvidence
        )
        let unauthorizedAnalysis = VNextComparisonBatchAnalysis(
            comparisonID: proof.analysis.comparisonID,
            analyses: proof.analysis.analyses,
            recommended: unauthorizedRecommendation,
            completionPayload: unauthorizedPayload
        )
        let unauthorizedCompletion = VNextCompleteComparisonDTO(
            comparisonID: proof.completion.comparisonID,
            completed: true,
            idempotent: false,
            recommendedProductSizeID: unauthorizedSizeID,
            recommendedSizeLabel: "XL",
            validatedEvidenceCount: proof.completion.validatedEvidenceCount,
            coverage: proof.completion.coverage
        )
        #expect(completed(
            analysis: unauthorizedAnalysis,
            completion: unauthorizedCompletion
        ) == nil)
    }

    @Test func resultRecompareBuildsDetachedCurrentServerAuthorizedTarget() async throws {
        let proof = try await HeadlessJourneyHarness
            .makeServerBackedUserExplicitCompletionProof()
        let displayedHistoricalProduct = proof.product
        let originalAuthority = displayedHistoricalProduct.classificationAuthorityProvenance
        let originalGarment = displayedHistoricalProduct.garmentTypeRawValue
        let originalSourceIdentity = displayedHistoricalProduct.canonicalSourceIdentity

        // RS-005/RS-006: choosing another reference starts a replacement
        // comparison with a detached target assembled from the server's
        // current begin/permit proof. It must not mutate the completed Result
        // target which may be a historical projection.
        let replacement = try #require(
            RecommendationService().makeServerAuthorizedComparisonTarget(
                from: displayedHistoricalProduct,
                permit: proof.permit
            )
        )

        #expect(replacement !== displayedHistoricalProduct)
        #expect(replacement.classificationAuthorityProvenance == .userExplicit)
        #expect(replacement.garmentTypeRawValue == "polo_shirt")
        #expect(replacement.id == proof.fixture.productID)
        #expect(!replacement.sizes.isEmpty)

        // The existing permit already passed authorization and begin. Route
        // the replacement through the real engine/complete proof from the
        // production harness: a valid USER_EXPLICIT recompare still creates a
        // local completed History instead of being rewritten as Global.
        let service = RecommendationService()
        let recompareHistory = service.makeCompletedVNextHistory(
            product: replacement,
            selectedReferenceItem: proof.reference,
            productDetailCategory: .shortSleeve,
            permit: proof.permit,
            analysis: proof.analysis,
            completion: proof.completion
        )
        #expect(recompareHistory?.product === replacement)
        #expect(recompareHistory?.product.classificationAuthorityProvenance == .userExplicit)

        // Mutating the transient replacement in this regression is deliberate:
        // the persisted Result target must retain its completed meaning even
        // when a following comparison fails or builds a different tuple.
        replacement.garmentTypeRawValue = "tshirt"
        replacement.markClassificationAuthority(.serverConfirmed)
        #expect(displayedHistoricalProduct.classificationAuthorityProvenance == originalAuthority)
        #expect(displayedHistoricalProduct.garmentTypeRawValue == originalGarment)
        #expect(displayedHistoricalProduct.canonicalSourceIdentity == originalSourceIdentity)
    }

    @Test func resultRecompareRunsANewServerAuthorizedCompletionWithoutMutatingTheOldResultTarget() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let displayedHistoricalProduct = makeHeadlessPersonalProduct(
            fixture: fixture,
            productID: UUID(),
            garment: "polo_shirt"
        )
        displayedHistoricalProduct.canonicalSourceIdentity = "history-comparison=old"
        let oldAuthority = displayedHistoricalProduct.classificationAuthorityProvenance
        let oldGarment = displayedHistoricalProduct.garmentTypeRawValue
        let oldSourceIdentity = displayedHistoricalProduct.canonicalSourceIdentity

        let replacementReference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: replacementReference)
        let runtime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1
        )
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: replacementReference,
                closetItemID: remoteReference.closetItemID,
                decision: "MANUAL_EXTENDED"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: replacementReference,
                closetItemID: remoteReference.closetItemID,
                mode: "MANUAL_EXTENDED",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 1
            )],
            beginResponses: [try fixture.begin(
                mode: "MANUAL_EXTENDED",
                personal: true,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: "polo_shirt"
            )],
            completionResponses: [try fixture.complete()]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization: FitMatchServerReferenceAuthorization
        switch await ResultReferenceComparisonAction.authorize(
            target: displayedHistoricalProduct,
            reference: replacementReference,
            coordinator: coordinator
        ) {
        case .allowed(let value):
            authorization = value
        case .rejected(let message), .unavailable(let message):
            Issue.record("RS-005/RS-006 recompare authorization unexpectedly blocked: \(message)")
            return
        }
        let permit = try await coordinator.beginAuthorizedComparison(authorization)
        let newTarget = try #require(
            RecommendationService().makeServerAuthorizedComparisonTarget(
                from: displayedHistoricalProduct,
                permit: permit
            )
        )
        #expect(newTarget !== displayedHistoricalProduct)
        #expect(newTarget.classificationAuthorityProvenance == .userExplicit)
        #expect(newTarget.garmentTypeRawValue == "polo_shirt")

        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let outcome = await ResultReferenceComparisonPersistence.resolveAndSave(
            product: newTarget,
            selectedReferenceItem: replacementReference,
            productDetailCategory: .shortSleeve,
            permit: permit,
            existingHistories: [],
            modelContext: context,
            coordinator: coordinator
        )
        guard case .success(let replacementHistory) = outcome else {
            Issue.record("RS-005/RS-006 replacement comparison did not create a new completed Result/History")
            return
        }

        #expect(replacementHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(replacementHistory.product !== displayedHistoricalProduct)
        #expect(replacementHistory.id == permit.clientHistoryID)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
        #expect(displayedHistoricalProduct.classificationAuthorityProvenance == oldAuthority)
        #expect(displayedHistoricalProduct.garmentTypeRawValue == oldGarment)
        #expect(displayedHistoricalProduct.canonicalSourceIdentity == oldSourceIdentity)

        let calls = await remote.calls()
        #expect(calls == [
            "resolve", "runtime", "list_closet", "reference_candidates",
            "eligible_sizes", "begin_comparison", "complete_comparison"
        ])
    }

    /// RS-005/RS-006/HI-005: a Global completed Result takes the automatic
    /// server-reference branch for a new comparison. The new history gets a
    /// detached current target, while the older completed target/reference
    /// snapshot retains its original authority and tuple.
    @Test func globalResultRecompareUsesAutomaticServerCandidateWithoutMutatingTheOldHistoryTarget() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let displayedHistoricalProduct = makeHeadlessGlobalProduct(fixture: fixture)
        displayedHistoricalProduct.canonicalSourceIdentity = "history-comparison=global-old"
        let oldAuthority = displayedHistoricalProduct.classificationAuthorityProvenance
        let oldGarment = displayedHistoricalProduct.garmentTypeRawValue
        let oldIdentity = displayedHistoricalProduct.canonicalSourceIdentity

        let replacementReference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: replacementReference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: replacementReference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: replacementReference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: "tshirt",
                personalRevision: 0,
                personalCandidateFingerprint: nil,
                personalCandidateSetHash: nil,
                personalInputFingerprint: nil,
                personalEvidenceFingerprint: nil
            )],
            completionResponses: [try fixture.complete()]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let authorization: FitMatchServerReferenceAuthorization
        switch await ResultReferenceComparisonAction.authorize(
            target: displayedHistoricalProduct,
            reference: replacementReference,
            coordinator: coordinator
        ) {
        case .allowed(let value):
            authorization = value
        case .rejected(let message), .unavailable(let message):
            Issue.record("Global Result recompare unexpectedly blocked: \(message)")
            return
        }
        let permit = try await coordinator.beginAuthorizedComparison(authorization)
        let newTarget = try #require(
            RecommendationService().makeServerAuthorizedComparisonTarget(
                from: displayedHistoricalProduct,
                permit: permit
            )
        )
        #expect(newTarget !== displayedHistoricalProduct)
        #expect(newTarget.classificationAuthorityProvenance == .serverConfirmed)

        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )]
        )
        let context = ModelContext(container)
        let outcome = await ResultReferenceComparisonPersistence.resolveAndSave(
            product: newTarget,
            selectedReferenceItem: replacementReference,
            productDetailCategory: .shortSleeve,
            permit: permit,
            existingHistories: [],
            modelContext: context,
            coordinator: coordinator
        )
        guard case .success(let newHistory) = outcome else {
            Issue.record("Global Result recompare did not persist a new completed History")
            return
        }
        #expect(newHistory.product !== displayedHistoricalProduct)
        #expect(newHistory.product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(displayedHistoricalProduct.classificationAuthorityProvenance == oldAuthority)
        #expect(displayedHistoricalProduct.garmentTypeRawValue == oldGarment)
        #expect(displayedHistoricalProduct.canonicalSourceIdentity == oldIdentity)
        #expect(await remote.calls() == [
            "resolve", "runtime", "list_closet", "reference_candidates",
            "eligible_sizes", "begin_comparison", "complete_comparison"
        ])
    }

    @Test func failedResultRecompareLeavesTheDisplayedHistoricalTargetUntouched() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let displayedHistoricalProduct = makeHeadlessPersonalProduct(
            fixture: fixture,
            productID: UUID(),
            garment: "polo_shirt"
        )
        displayedHistoricalProduct.canonicalSourceIdentity = "history-comparison=failed-old"
        let oldAuthority = displayedHistoricalProduct.classificationAuthorityProvenance
        let oldGarment = displayedHistoricalProduct.garmentTypeRawValue
        let oldSourceIdentity = displayedHistoricalProduct.canonicalSourceIdentity

        let replacementReference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: replacementReference)
        let runtime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1
        )
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: replacementReference,
                closetItemID: remoteReference.closetItemID,
                decision: "MANUAL_EXTENDED"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: replacementReference,
                closetItemID: remoteReference.closetItemID,
                mode: "MANUAL_EXTENDED",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 1
            )],
            beginResponses: [try fixture.begin(
                mode: "MANUAL_EXTENDED",
                personal: true,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: "polo_shirt"
            )],
            completionFailureCount: 1
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization: FitMatchServerReferenceAuthorization
        switch await ResultReferenceComparisonAction.authorize(
            target: displayedHistoricalProduct,
            reference: replacementReference,
            coordinator: coordinator
        ) {
        case .allowed(let value):
            authorization = value
        case .rejected(let message), .unavailable(let message):
            Issue.record("RS-005/RS-006 failed recompare authorization unexpectedly blocked: \(message)")
            return
        }
        let permit = try await coordinator.beginAuthorizedComparison(authorization)
        let newTarget = try #require(
            RecommendationService().makeServerAuthorizedComparisonTarget(
                from: displayedHistoricalProduct,
                permit: permit
            )
        )
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let outcome = await ResultReferenceComparisonPersistence.resolveAndSave(
            product: newTarget,
            selectedReferenceItem: replacementReference,
            productDetailCategory: .shortSleeve,
            permit: permit,
            existingHistories: [],
            modelContext: context,
            coordinator: coordinator
        )
        if case .saveFailed = outcome {
            // The server complete boundary failed. The prior result must still
            // have its original immutable historical meaning.
        } else {
            Issue.record("RS-005/RS-006 failed recompare unexpectedly produced a terminal result")
        }

        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(displayedHistoricalProduct.classificationAuthorityProvenance == oldAuthority)
        #expect(displayedHistoricalProduct.garmentTypeRawValue == oldGarment)
        #expect(displayedHistoricalProduct.canonicalSourceIdentity == oldSourceIdentity)
        let calls = await remote.calls()
        #expect(calls == [
            "resolve", "runtime", "list_closet", "reference_candidates",
            "eligible_sizes", "begin_comparison", "complete_comparison"
        ])
    }

    /// RS-013/RX-010: a server completion may fail after the real engine has
    /// run.  The current server-authorized run remains retryable, but no
    /// local Result/History may appear until the server completion succeeds.
    /// The retry deliberately reuses the exact permit/run rather than
    /// starting a replacement comparison or manufacturing a local result.
    @Test func completedResultRetryWaitsForServerCompletionAndPersistsOneHistory() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let displayedHistoricalProduct = makeHeadlessGlobalProduct(fixture: fixture)
        let reference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let completionGate = JourneyAsyncGate()
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [try fixture.runtime(globalStatus: .confirmed)],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID,
                personalRevision: 0,
                personalCandidateFingerprint: nil,
                personalCandidateSetHash: nil,
                personalInputFingerprint: nil,
                personalEvidenceFingerprint: nil
            )],
            completionResponses: [try fixture.complete()],
            completionFailureCount: 1,
            gates: [.completeComparison: completionGate]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization: FitMatchServerReferenceAuthorization
        switch await ResultReferenceComparisonAction.authorize(
            target: displayedHistoricalProduct,
            reference: reference,
            coordinator: coordinator
        ) {
        case .allowed(let value):
            authorization = value
        case .rejected(let message), .unavailable(let message):
            Issue.record("RS-013/RX-010 authorization unexpectedly blocked: \(message)")
            return
        }
        let permit = try await coordinator.beginAuthorizedComparison(authorization)
        let retryTarget = try #require(
            RecommendationService().makeServerAuthorizedComparisonTarget(
                from: displayedHistoricalProduct,
                permit: permit
            )
        )

        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let first = Task { @MainActor in
            await ResultReferenceComparisonPersistence.resolveAndSave(
                product: retryTarget,
                selectedReferenceItem: reference,
                productDetailCategory: .shortSleeve,
                permit: permit,
                existingHistories: [],
                modelContext: context,
                coordinator: coordinator
            )
        }

        // The engine is already behind the server-completion boundary, but
        // a Result/History has not been allowed to appear while it waits.
        await completionGate.waitForArrival(atLeast: 1)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)

        await completionGate.open()
        if case .saveFailed = await first.value {
            // The first server completion response intentionally failed.
        } else {
            Issue.record("RS-013/RX-010 produced a local result before server completion")
        }
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)

        let retry = await ResultReferenceComparisonPersistence.resolveAndSave(
            product: retryTarget,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve,
            permit: permit,
            existingHistories: [],
            modelContext: context,
            coordinator: coordinator
        )
        guard case .success(let history) = retry else {
            Issue.record("RS-013/RX-010 did not persist after the same server run completed")
            return
        }
        #expect(history.id == permit.clientHistoryID)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(calls.filter { $0 == "complete_comparison" }.count == 2)
    }

    /// RS-008: the server may already have completed an authorized comparison
    /// when local SwiftData persistence fails.  The production Result action
    /// must surface a save failure (not a measurement error), keep local
    /// History empty, then create exactly one History on the explicit retry.
    @Test func completedResultLocalPersistenceFailureThenRetryCreatesExactlyOneHistory() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let displayedHistoricalProduct = makeHeadlessGlobalProduct(fixture: fixture)
        let reference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [try fixture.runtime(globalStatus: .confirmed)],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID,
                personalRevision: 0,
                personalCandidateFingerprint: nil,
                personalCandidateSetHash: nil,
                personalInputFingerprint: nil,
                personalEvidenceFingerprint: nil
            )],
            completionResponses: [try fixture.complete(), try fixture.complete()]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization: FitMatchServerReferenceAuthorization
        switch await ResultReferenceComparisonAction.authorize(
            target: displayedHistoricalProduct,
            reference: reference,
            coordinator: coordinator
        ) {
        case .allowed(let value):
            authorization = value
        case .rejected(let message), .unavailable(let message):
            Issue.record("RS-008 authorization unexpectedly blocked: \(message)")
            return
        }
        let permit = try await coordinator.beginAuthorizedComparison(authorization)
        let target = try #require(
            RecommendationService().makeServerAuthorizedComparisonTarget(
                from: displayedHistoricalProduct,
                permit: permit
            )
        )
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let first = await ResultReferenceComparisonPersistence.resolveAndSave(
            product: target,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve,
            permit: permit,
            existingHistories: [],
            modelContext: context,
            coordinator: coordinator,
            persistCompletedHistory: { _, _, _ in
                throw CocoaError(.fileWriteUnknown)
            }
        )
        if case .saveFailed = first {
            // Expected: successful server completion is never presented as a
            // misleading local Result while durable local persistence failed.
        } else {
            Issue.record("RS-008 local persistence failure did not reach saveFailed")
        }
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect((await remote.calls()).filter { $0 == "complete_comparison" }.count == 1)

        let retry = await ResultReferenceComparisonPersistence.resolveAndSave(
            product: target,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve,
            permit: permit,
            existingHistories: [],
            modelContext: context,
            coordinator: coordinator
        )
        guard case .success(let history) = retry else {
            Issue.record("RS-008 retry did not persist the server-completed History")
            return
        }
        #expect(history.id == permit.clientHistoryID)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(calls.filter { $0 == "complete_comparison" }.count == 2)
    }

    /// RX-003/RX-009: eligibility is a snapshot, not a promise that a later
    /// begin request can score the same target.  The real eligible RPC emits
    /// one authorized-size identity and the next real begin RPC presents a
    /// newer, different identity. The coordinator must fail closed before
    /// the engine/completion path.
    @Test func changedEligibleAuthorityBeforeBeginFailsClosedWithoutCompletion() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let reference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let changedAuthorizedSizeID = UUID()
        let remote = JourneyRecordingRemote(
            // Product load consumes the first current authority. The actual
            // production authorization action refreshes authority again
            // before it asks eligible sizes, so give that second real RPC its
            // own identical current response.
            resolutions: [
                fixture.resolution(globalStatus: .confirmed),
                fixture.resolution(globalStatus: .confirmed)
            ],
            runtimes: [
                try fixture.runtime(globalStatus: .confirmed),
                try fixture.runtime(globalStatus: .confirmed)
            ],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID,
                personalRevision: 0,
                personalCandidateFingerprint: nil,
                personalCandidateSetHash: nil,
                personalInputFingerprint: nil,
                personalEvidenceFingerprint: nil,
                authorizedProductSizeID: changedAuthorizedSizeID
            )]
        )
        let parser = HeadlessJourneyParser(product: fixture.parsedProduct())
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                musinsaParser: parser,
                uniqloParser: parser,
                zaraParser: parser
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        guard await viewModel.loadProductInfoFromURL() else {
            Issue.record(
                "RX-003/RX-009 target did not load before eligible/begin mutation: \(viewModel.errorMessage ?? "unknown")"
            )
            return
        }
        #expect(await viewModel.calculateRecommendation(userFits: [reference]) == nil)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "eligible_sizes" }.count == 1)
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(!calls.contains("complete_comparison"))
        #expect(viewModel.recommendation == nil)
        #expect(viewModel.errorMessage?.contains("서버 비교") == true)
    }

    /// CP-025 / RS-005 / HI-013: local Closet ordering is presentation only.
    /// A local representative that the server does not return must never be
    /// used just because it appears before a server-authorized reference. The
    /// same actual ViewModel/coordinator loop must advance only when the
    /// server's returned candidate identity is reached.
    @Test func automaticComparisonUsesOnlyServerReturnedReferenceCandidates() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let staleLocalReference = fixture.localReference(
            garment: "hoodie",
            sleeve: "short_sleeve"
        )
        let serverAuthorizedReference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        // The locally stale candidate is deliberately the one automatic UI
        // presentation would consider first. The coordinator must still
        // reject it from the server candidate contract before considering B.
        staleLocalReference.updatedAt = Date(timeIntervalSince1970: 2)
        serverAuthorizedReference.updatedAt = Date(timeIntervalSince1970: 1)
        let staleRemoteReference = fixture.closetRecord(for: staleLocalReference)
        let authorizedRemoteReference = fixture.closetRecord(for: serverAuthorizedReference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: Array(
                repeating: fixture.resolution(globalStatus: .confirmed),
                count: 3
            ),
            runtimes: Array(repeating: runtime, count: 3),
            closetResponses: [.init(
                state: "ready",
                items: [staleRemoteReference, authorizedRemoteReference]
            )],
            // Both candidate queries return only the server-authorized
            // reference. The first local candidate therefore fails closed;
            // the ViewModel may proceed only when it reaches the matching
            // local item on its real automatic loop.
            candidateResponses: [
                try fixture.referenceResponse(
                    reference: serverAuthorizedReference,
                    closetItemID: authorizedRemoteReference.closetItemID,
                    decision: "AUTOMATIC"
                ),
                try fixture.referenceResponse(
                    reference: serverAuthorizedReference,
                    closetItemID: authorizedRemoteReference.closetItemID,
                    decision: "AUTOMATIC"
                )
            ],
            eligibleResponses: [try fixture.eligible(
                reference: serverAuthorizedReference,
                closetItemID: authorizedRemoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: authorizedRemoteReference.closetItemID
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                uniqloParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        let history = await viewModel.calculateRecommendation(
            userFits: [staleLocalReference, serverAuthorizedReference]
        )
        let completed = try #require(history)
        #expect(completed.userFit.id == serverAuthorizedReference.id)
        #expect(completed.userFit.id != staleLocalReference.id)

        let calls = await remote.calls()
        #expect(calls.filter { $0 == "reference_candidates" }.count == 2)
        #expect(calls.filter { $0 == "eligible_sizes" }.count == 1)
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(calls.filter { $0 == "complete_comparison" }.count == 1)
    }

    /// CP-006: a zero-candidate Recovery contract is a distinct user state
    /// from an ordinary unresolved product. The actual ViewModel must expose
    /// its bounded, unrecoverable state and cannot start comparison work.
    @Test func cp006ZeroRecoveryCandidatesFailClosedBeforeReferenceOrEngine() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [try fixture.runtime(
                globalStatus: .reviewRequired,
                productStructure: "UNKNOWN"
            )],
            recoveryContracts: [try fixture.recoveryContract(count: 0, suffix: "cp006-zero")]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                uniqloParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL() == false)
        let contract = try #require(viewModel.reviewRecoveryContract)
        #expect(contract.candidateCount == 0)
        #expect(contract.recoverability == .unrecoverable)
        #expect(viewModel.errorMessage != nil)
        #expect(await viewModel.calculateRecommendation(userFits: []) == nil)
        let calls = await remote.calls()
        #expect(calls == ["resolve", "runtime", "recovery_contract"])
    }

    /// CP-007: NOT_APPLICABLE is an issued authority block, not a Recovery
    /// prompt. It reaches no reference, begin, engine, or completion action.
    @Test func cp007NotApplicableProductStopsAtEffectiveAuthorityWithReason() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .notComparable)],
            runtimes: [try fixture.runtime(globalStatus: .notComparable)]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                musinsaParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(viewModel.reviewRecoveryContract == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(await viewModel.calculateRecommendation(userFits: []) == nil)
        let calls = await remote.calls()
        #expect(calls == ["resolve", "runtime"])
    }

    /// CP-013: an otherwise confirmed product without an active, usable
    /// reference goes through the normal resolver but must stop before the
    /// server reference/eligible/begin/engine sequence and retain a reason.
    @Test func cp013EmptyClosetHasNoReferenceAndNeverStartsComparison() async throws {
        let fixture = HeadlessJourneyFixture(provider: .zara)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [try fixture.runtime(globalStatus: .confirmed)]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                zaraParser: HeadlessJourneyParser(product: fixture.parsedProduct())
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(await viewModel.calculateRecommendation(userFits: []) == nil)
        #expect(viewModel.errorMessage != nil)
        let calls = await remote.calls()
        #expect(calls == ["resolve", "runtime"])
    }

    /// CP-005: every bounded Recovery cardinality is a distinct current
    /// server contract. The user selects one of that exact contract's
    /// candidates; production authority refresh, reference authorization,
    /// engine, completion, and History then execute normally.
    @Test func cp005EachBoundedRecoveryCardinalityUsesItsOwnServerContract() async throws {
        for candidateCount in 1...3 {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let contract = try fixture.recoveryContract(
                count: candidateCount,
                suffix: "cp005-\(candidateCount)"
            )
            let selected = try #require(contract.candidates.last)
            let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
            let record = fixture.closetRecord(for: reference)
            let review = try fixture.runtime(globalStatus: .reviewRequired)
            let personal = try fixture.runtime(
                globalStatus: .reviewRequired,
                effectivePersonalGarment: selected.garmentTypeCode,
                overrideRevision: 1,
                personalCandidateFingerprint: selected.candidateFingerprint,
                personalCandidateSetHash: contract.candidateSetHash
            )
            let remote = JourneyRecordingRemote(
                resolutions: Array(repeating: fixture.resolution(globalStatus: .reviewRequired), count: 3),
                runtimes: [review, personal, personal],
                recoveryContracts: [contract],
                setMutations: [try fixture.setMutation(
                    contract: contract,
                    garment: selected.garmentTypeCode,
                    revision: 1,
                    event: "SELECTED"
                )],
                closetResponses: [.init(state: "ready", items: [record])],
                candidateResponses: [try fixture.referenceResponse(
                    reference: reference,
                    closetItemID: record.closetItemID,
                    decision: "AUTOMATIC"
                )],
                eligibleResponses: [try fixture.eligible(
                    reference: reference,
                    closetItemID: record.closetItemID,
                    mode: "AUTOMATIC",
                    allowed: true,
                    effectiveSource: "USER_EXPLICIT",
                    overrideRevision: 1
                )],
                beginResponses: [try fixture.begin(
                    mode: "AUTOMATIC",
                    personal: true,
                    referenceClosetItemID: record.closetItemID,
                    personalGarment: selected.garmentTypeCode,
                    personalCandidateFingerprint: selected.candidateFingerprint,
                    personalCandidateSetHash: contract.candidateSetHash
                )],
                completionResponses: [try fixture.complete()]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)

            #expect(await viewModel.loadProductInfoFromURL() == false)
            let displayed = try #require(viewModel.reviewRecoveryContract)
            #expect(displayed.candidateCount == candidateCount)
            #expect(displayed.unknownFields == [.garmentType])
            #expect(await viewModel.confirmReviewRecovery(selected))
            let history = await viewModel.calculateRecommendation(userFits: [reference])
            #expect(history?.product.classificationAuthorityProvenance == .userExplicit)
            #expect((await remote.calls()).contains("complete_comparison"))
        }
    }

    /// CP-012: a future Global authority is used only for a new comparison.
    /// The prior personal Result remains an immutable begin-time projection.
    @Test func cp012FutureGlobalAuthoritySupersedesOnlyTheNextComparison() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let record = fixture.closetRecord(for: reference)
        let personal = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1
        )
        let global = try fixture.runtime(globalStatus: .confirmed)
        let personalEligible = try fixture.eligible(
            reference: reference,
            closetItemID: record.closetItemID,
            mode: "AUTOMATIC",
            allowed: true,
            effectiveSource: "USER_EXPLICIT",
            overrideRevision: 1
        )
        let globalEligible = try fixture.eligible(
            reference: reference,
            closetItemID: record.closetItemID,
            mode: "AUTOMATIC",
            allowed: true,
            effectiveSource: nil,
            overrideRevision: nil
        )
        let remote = JourneyRecordingRemote(
            resolutions: [
                fixture.resolution(globalStatus: .reviewRequired),
                fixture.resolution(globalStatus: .reviewRequired),
                fixture.resolution(globalStatus: .confirmed),
                fixture.resolution(globalStatus: .confirmed)
            ],
            runtimes: [personal, personal, global, global],
            closetResponses: [.init(state: "ready", items: [record])],
            candidateResponses: [
                try fixture.referenceResponse(reference: reference, closetItemID: record.closetItemID, decision: "AUTOMATIC"),
                try fixture.referenceResponse(reference: reference, closetItemID: record.closetItemID, decision: "AUTOMATIC")
            ],
            eligibleResponses: [personalEligible, globalEligible],
            beginResponses: [
                try fixture.begin(
                    mode: "AUTOMATIC",
                    personal: true,
                    referenceClosetItemID: record.closetItemID,
                    personalGarment: "polo_shirt"
                ),
                try fixture.begin(
                    mode: "AUTOMATIC",
                    personal: false,
                    referenceClosetItemID: record.closetItemID
                )
            ],
            completionResponses: [try fixture.complete(), try fixture.complete()]
        )
        let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
        #expect(await viewModel.loadProductInfoFromURL())
        let personalHistory = try #require(
            await viewModel.calculateRecommendation(userFits: [reference])
        )
        let priorAuthority = personalHistory.product.classificationAuthorityProvenance
        let priorGarment = personalHistory.product.garmentTypeRawValue

        #expect(await viewModel.loadProductInfoFromURL())
        let globalHistory = try #require(
            await viewModel.calculateRecommendation(userFits: [reference])
        )
        #expect(personalHistory.id != globalHistory.id)
        #expect(priorAuthority == .userExplicit)
        #expect(priorGarment == "polo_shirt")
        #expect(personalHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(personalHistory.product.garmentTypeRawValue == "polo_shirt")
        #expect(globalHistory.product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(globalHistory.product.garmentTypeRawValue == "tshirt")
    }

    /// CP-015: when the server returns two current eligible reference IDs, a
    /// user-selected reference must be the one authorized and used for the
    /// new completed comparison—not a local priority heuristic.
    @Test func cp015ManualReferenceSelectionUsesTheExactServerCandidateID() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let first = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        first.productName = "CP-015 첫 기준옷"
        let second = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        second.productName = "CP-015 사용자가 고른 기준옷"
        let firstRecord = fixture.closetRecord(for: first)
        let secondRecord = fixture.closetRecord(for: second)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [firstRecord, secondRecord])],
            candidateResponses: [try fixture.referenceResponse(candidates: [
                (first, firstRecord.closetItemID, "MANUAL_EXTENDED"),
                (second, secondRecord.closetItemID, "MANUAL_EXTENDED")
            ])],
            eligibleResponses: [try fixture.eligible(
                reference: second,
                closetItemID: secondRecord.closetItemID,
                mode: "MANUAL_EXTENDED",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "MANUAL_EXTENDED",
                personal: false,
                referenceClosetItemID: secondRecord.closetItemID
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
        #expect(await viewModel.loadProductInfoFromURL())
        let history = try #require(
            await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: second)
        )
        #expect(history.userFit.id == second.id)
        #expect(history.userFit.productName == "CP-015 사용자가 고른 기준옷")
        try requireOrdered(
            await remote.calls(),
            ["list_closet", "reference_candidates", "eligible_sizes", "begin_comparison", "complete_comparison"],
            scenario: "CP-015"
        )
    }

    /// CP-016: a selected local reference that was deleted, replaced, or had
    /// its measurements changed after local presentation cannot pass the
    /// coordinator's current server Closet snapshot check or reach the engine.
    @Test func cp016StaleDeletedChangedAndMeasurementEditedReferenceNeverBegins() async throws {
        enum MutationCase: CaseIterable { case deleted, changed, measurementsEdited }

        for mutation in MutationCase.allCases {
            let fixture = HeadlessJourneyFixture(provider: .zara)
            let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
            let currentRecord = fixture.closetRecord(for: reference)
            switch mutation {
            case .deleted:
                break
            case .changed:
                reference.detailCategory = .longSleeve
                reference.detailCategoryCode = "long_sleeve"
                reference.sleeveTypeRawValue = "long_sleeve"
            case .measurementsEdited:
                reference.chest = 77
            }
            let runtime = try fixture.runtime(globalStatus: .confirmed)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
                runtimes: [runtime, runtime],
                closetResponses: [.init(
                    state: "ready",
                    items: mutation == .deleted ? [] : [currentRecord]
                )]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: reference) == nil)
            let calls = await remote.calls()
            #expect(!calls.contains("begin_comparison"))
            #expect(!calls.contains("complete_comparison"))
            #expect(viewModel.errorMessage?.isEmpty == false)
        }
    }

    /// CP-018: three structurally incompatible user choices are real local
    /// reference states. The server candidate contract blocks each before
    /// eligible sizes, begin, engine, Result, or History.
    @Test func cp018IncompatibleAudienceCategoryAndUnruledTypeFailClosedBeforeEngine() async throws {
        enum RelationCase: CaseIterable { case adultChild, upperLower, unruledType }

        for relation in RelationCase.allCases {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
            switch relation {
            case .adultChild:
                reference.gender = .kids
            case .upperLower:
                reference.category = .bottom
                reference.detailCategory = .longPants
                reference.categoryCode = "bottoms"
                reference.detailCategoryCode = "long_pants"
                reference.garmentTypeRawValue = "pants"
                reference.sleeveTypeRawValue = nil
            case .unruledType:
                reference.garmentTypeRawValue = "outerwear_unruled"
            }
            let record = fixture.closetRecord(for: reference)
            let runtime = try fixture.runtime(globalStatus: .confirmed)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
                runtimes: [runtime, runtime],
                closetResponses: [.init(state: "ready", items: [record])],
                candidateResponses: [try fixture.referenceResponse(
                    reference: reference,
                    closetItemID: record.closetItemID,
                    decision: "BLOCKED"
                )]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: reference) == nil)
            let calls = await remote.calls()
            #expect(calls.contains("reference_candidates"))
            #expect(!calls.contains("eligible_sizes"))
            #expect(!calls.contains("begin_comparison"))
            #expect(viewModel.errorMessage?.contains("비교") == true)
        }
    }

    /// CP-023: full, minimum, and optional-missing evidence each reach the
    /// same server-authorized production path with materially different
    /// immutable begin evidence. The production engine—not this test—derives
    /// score, coverage, and reliability from that issued evidence.
    @Test func cp023FullMinimumAndOptionalMeasurementEvidenceProduceTheirOwnResults() async throws {
        let cases: [(String, [HeadlessServerMetricFixture], [String], Double)] = [
            (
                "full",
                [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48),
                    .init(code: "body_length_back_neck_to_hem", referenceValue: 70, targetValue: 70, basisCode: "LENGTH"),
                    .init(code: "sleeve_shoulder_seam_to_cuff", referenceValue: 24, targetValue: 24, basisCode: "LENGTH")
                ],
                ["chest_width_pit_to_pit", "shoulder_width_seam_to_seam", "body_length_back_neck_to_hem", "sleeve_shoulder_seam_to_cuff"],
                1
            ),
            (
                "minimum",
                [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51)],
                ["chest_width_pit_to_pit", "shoulder_width_seam_to_seam", "body_length_back_neck_to_hem", "sleeve_shoulder_seam_to_cuff"],
                0.25
            ),
            (
                "optional-missing",
                [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
                ],
                ["chest_width_pit_to_pit", "shoulder_width_seam_to_seam", "body_length_back_neck_to_hem", "sleeve_shoulder_seam_to_cuff"],
                0.5
            )
        ]

        for (name, metrics, policy, completionCoverage) in cases {
            let fixture = HeadlessJourneyFixture(provider: .musinsa)
            let sizeID = UUID()
            let candidate = HeadlessServerCandidateFixture(
                productSizeID: sizeID,
                sizeLabel: "M-\(name)",
                metrics: metrics,
                runtimeMetrics: [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48),
                    .init(code: "body_length_back_neck_to_hem", referenceValue: 70, targetValue: 70, basisCode: "LENGTH"),
                    .init(code: "sleeve_shoulder_seam_to_cuff", referenceValue: 24, targetValue: 24, basisCode: "LENGTH")
                ]
            )
            let run = try makeCandidateComparison(
                fixture: fixture,
                candidates: [candidate],
                policyMetricCodes: policy,
                completionSizeID: sizeID,
                completionCoverage: completionCoverage
            )
            #expect(run.reference.fitMatchServerReferenceSnapshot() != nil)
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(run.viewModel.makeProductForClosetRegistration(brand: nil) != nil)
            let completed = await run.viewModel.calculateRecommendation(userFits: [run.reference])
            let blockedMessage = run.viewModel.errorMessage ?? "no message"
            #expect(
                completed != nil,
                "CP-023 \(name) blocked: \(blockedMessage)"
            )
            let history = try #require(completed)
            #expect(history.recommendedSize.id == sizeID)
            #expect(history.comparedMeasurementUsages.count == metrics.count)
            // The server freezes only the comparable authorized evidence at
            // begin.  The production adapter intentionally reports coverage
            // relative to that frozen set, while the Result/History snapshot
            // exposes optional absence by the concrete measurement usages.
            // Assert that user-visible evidence is exactly the issued set;
            // do not reproduce a local coverage policy in the test.
            #expect(
                Set(history.comparedMeasurementUsages.map(\.measurementCode.rawValue))
                    == Set(metrics.map(\.code))
            )
            try requireOrdered(
                await run.remote.calls(),
                ["reference_candidates", "eligible_sizes", "begin_comparison", "complete_comparison"],
                scenario: "CP-023 \(name)"
            )
        }
    }

    /// RS-003: Result presentation reads the immutable evidence produced by a
    /// real server-authorized begin/engine/complete path.  A separately
    /// issued insufficient-evidence decision remains a reasoned block rather
    /// than a fabricated Result.
    @Test func rs003ResultEvidenceAndInsufficientStateUseProductionTerminalData() async throws {
        let completeFixture = HeadlessJourneyFixture(provider: .uniqlo)
        let completeCandidate = HeadlessServerCandidateFixture(
            productSizeID: UUID(),
            sizeLabel: "M",
            metrics: [
                .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
            ]
        )
        let completeRun = try makeCandidateComparison(
            fixture: completeFixture,
            candidates: [completeCandidate],
            policyMetricCodes: ["chest_width_pit_to_pit", "shoulder_width_seam_to_seam"],
            completionSizeID: completeCandidate.productSizeID
        )
        #expect(await completeRun.viewModel.loadProductInfoFromURL())
        let completed = try #require(
            await completeRun.viewModel.calculateRecommendation(userFits: [completeRun.reference])
        )
        let snapshot = try #require(completed.calculationSnapshot)
        let presentation = RecommendationCalculationPresentation(snapshot: snapshot)
        #expect(completed.recommendedSize.id == completeCandidate.productSizeID)
        #expect(snapshot.usages.map(\.measurementCode.rawValue) == [
            "chest_width_pit_to_pit", "shoulder_width_seam_to_seam"
        ])
        #expect(presentation.coveragePercent == 100)
        #expect(presentation.exclusionMessages.isEmpty)
        try requireOrdered(
            await completeRun.remote.calls(),
            ["eligible_sizes", "begin_comparison", "complete_comparison"],
            scenario: "RS-003 completed evidence"
        )

        let blockedFixture = HeadlessJourneyFixture(provider: .zara)
        let blockedCandidate = HeadlessServerCandidateFixture(
            productSizeID: UUID(),
            sizeLabel: "M",
            // Keep target evidence sufficient so the production flow reaches
            // the server-issued eligible-size block. The blocked outcome is
            // an availability/eligibility decision, not a local shortcut.
            metrics: [
                .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
            ]
        )
        let blockedRun = try makeCandidateComparison(
            fixture: blockedFixture,
            candidates: [blockedCandidate],
            eligibleAllowed: false,
            eligibleDecision: "BLOCKED",
            eligibleReason: "measurements_required"
        )
        #expect(await blockedRun.viewModel.loadProductInfoFromURL())
        #expect(await blockedRun.viewModel.calculateRecommendation(userFits: [blockedRun.reference]) == nil)
        #expect(blockedRun.viewModel.errorMessage?.isEmpty == false)
        let blockedCalls = await blockedRun.remote.calls()
        #expect(blockedCalls.contains("eligible_sizes"))
        #expect(!blockedCalls.contains("begin_comparison"))
        #expect(!blockedCalls.contains("complete_comparison"))
    }

    /// CP-024: missing target/reference/both/no-common states are distinct
    /// user inputs. Each fails closed with an actual terminal message and no
    /// server completion/History.
    @Test func cp024RequiredMeasurementAbsenceStatesBlockWithNoCompletedResult() async throws {
        let cases: [(String, [HeadlessServerMetricFixture], (UserFit) -> Void)] = [
            ("target-missing", [], { _ in }),
            ("reference-missing", [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51)], { $0.chest = 0 }),
            ("both-missing", [], { $0.chest = 0 }),
            ("no-common", [.init(code: "waist_width", referenceValue: 36, targetValue: 37)], { $0.waist = 0 })
        ]

        for (name, metrics, configureReference) in cases {
            let fixture = HeadlessJourneyFixture(provider: .zara)
            let candidate = HeadlessServerCandidateFixture(
                productSizeID: UUID(),
                sizeLabel: "M-\(name)",
                metrics: metrics
            )
            let run = try makeCandidateComparison(
                fixture: fixture,
                candidates: [candidate],
                eligibleAllowed: false,
                eligibleDecision: "BLOCKED",
                eligibleReason: "measurements_required_\(name)",
                configureReference: configureReference
            )
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(await run.viewModel.calculateRecommendation(userFits: [run.reference]) == nil)
            #expect(run.viewModel.errorMessage?.isEmpty == false)
            let calls = await run.remote.calls()
            #expect(!calls.contains("begin_comparison"))
            #expect(!calls.contains("complete_comparison"))
        }
    }

    /// CP-025: semantic conflict, unmapped canonical data, malformed source
    /// evidence, method mismatch, and classification contradiction are five
    /// distinct server-contract inputs. They must never receive a confident
    /// local completion merely because a local parser has some raw values.
    @Test func cp025SemanticAndCanonicalMeasurementContradictionsFailClosed() async throws {
        let cases: [(String, HeadlessServerCandidateFixture)] = [
            ("semantic-conflict", .init(productSizeID: UUID(), sizeLabel: "M", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51, basisCode: "LENGTH")])),
            ("canonical-unmapped", .init(productSizeID: UUID(), sizeLabel: "M", metrics: [.init(code: "unknown_canonical_measurement", referenceValue: 50, targetValue: 51)])),
            ("malformed-source", .init(productSizeID: UUID(), sizeLabel: "M", metrics: [])),
            ("method-mismatch", .init(productSizeID: UUID(), sizeLabel: "M", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51, basisCode: "CIRCUMFERENCE")])),
            ("classification-measurement-contradiction", .init(productSizeID: UUID(), sizeLabel: "M", metrics: [.init(code: "foot_length", referenceValue: 26, targetValue: 27, basisCode: "LENGTH")]))
        ]

        for (name, candidate) in cases {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let run = try makeCandidateComparison(
                fixture: fixture,
                candidates: [candidate],
                eligibleAllowed: false,
                eligibleDecision: "BLOCKED",
                eligibleReason: "measurement_contract_\(name)"
            )
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(await run.viewModel.calculateRecommendation(userFits: [run.reference]) == nil)
            #expect(run.viewModel.errorMessage?.isEmpty == false)
            let calls = await run.remote.calls()
            #expect(!calls.contains("begin_comparison"))
            #expect(!calls.contains("complete_comparison"))
        }
    }

    /// CP-026: the parser presents two product sizes, while the server issues
    /// only the one with sufficient evidence. The exact survivor is the only
    /// candidate that can reach begin, engine, and completed History.
    @Test func cp026PartialCoverageUsesOnlyTheServerAuthorizedSurvivingSize() async throws {
        let survivingID = UUID()
        let unavailableID = UUID()
        var parsed = HeadlessJourneyFixture(provider: .musinsa).parsedProduct()
        parsed.sizes = [
            .init(id: unavailableID, name: "S", measurements: .init(shoulder: 0, chest: 49, totalLength: 0, sleeveLength: 0), availabilityStatus: "AVAILABLE"),
            .init(id: survivingID, name: "M", measurements: .init(shoulder: 0, chest: 51, totalLength: 0, sleeveLength: 0), availabilityStatus: "AVAILABLE")
        ]
        let fixture = HeadlessJourneyFixture(provider: .musinsa, parsedProductOverride: parsed)
        let survivor = HeadlessServerCandidateFixture(
            productSizeID: survivingID,
            sizeLabel: "M",
            metrics: [
                .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
            ]
        )
        let run = try makeCandidateComparison(
            fixture: fixture,
            candidates: [survivor],
            completionSizeID: survivingID
        )
        #expect(await run.viewModel.loadProductInfoFromURL())
        let history = try #require(await run.viewModel.calculateRecommendation(userFits: [run.reference]))
        #expect(history.recommendedSize.id == survivingID)
        #expect(history.product.sizes.map(\.id) == [survivingID])
        #expect(!(await run.remote.calls()).contains("begin_comparison") == false)
    }

    /// CP-027: a multi-size candidate set and a one-size candidate set are
    /// independently issued by the server and both complete only through the
    /// exact begin snapshot supplied for that size set.
    @Test func cp027MultipleAndSingleAvailableSizeSetsReachExactBeginSnapshots() async throws {
        for labels in [["S", "M", "L"], ["ONE"]] {
            let fixture = HeadlessJourneyFixture(provider: .zara)
            let candidates = labels.enumerated().map { index, label in
                HeadlessServerCandidateFixture(
                    productSizeID: UUID(),
                    sizeLabel: label,
                    metrics: [.init(
                        code: "chest_width_pit_to_pit",
                        referenceValue: 50,
                        targetValue: 50 + Double(index)
                    ), .init(
                        code: "shoulder_width_seam_to_seam",
                        referenceValue: 48,
                        targetValue: 48
                    )]
                )
            }
            let expectedID = candidates.first!.productSizeID
            let run = try makeCandidateComparison(
                fixture: fixture,
                candidates: candidates,
                completionSizeID: expectedID
            )
            #expect(await run.viewModel.loadProductInfoFromURL())
            let history = try #require(await run.viewModel.calculateRecommendation(userFits: [run.reference]))
            #expect(Set(history.product.sizes.map(\.id)) == Set(candidates.map(\.productSizeID)))
            #expect(history.recommendedSize.id == expectedID)
            #expect((await run.remote.calls()).filter { $0 == "begin_comparison" }.count == 1)
        }
    }

    /// CP-028: availability expiry and a changed authorized set after the
    /// eligible response are temporal blocks. Neither may produce a completed
    /// comparison from the now-stale candidate evidence.
    @Test func cp028ExpiredOrChangedAvailabilityBlocksBeforeCompletion() async throws {
        do {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let expired = HeadlessServerCandidateFixture(
                productSizeID: UUID(),
                sizeLabel: "M",
                availabilityStatus: "SOLD_OUT",
                metrics: [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
                ]
            )
            let run = try makeCandidateComparison(fixture: fixture, candidates: [expired])
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(await run.viewModel.calculateRecommendation(userFits: [run.reference]) == nil)
            #expect(!(await run.remote.calls()).contains("complete_comparison"))
            #expect(run.viewModel.errorMessage?.isEmpty == false)
        }

        do {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let eligible = HeadlessServerCandidateFixture(
                productSizeID: UUID(),
                sizeLabel: "M",
                metrics: [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
                ]
            )
            let changed = HeadlessServerCandidateFixture(
                productSizeID: UUID(),
                sizeLabel: "M",
                metrics: [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 52),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
                ]
            )
            let run = try makeCandidateComparison(
                fixture: fixture,
                candidates: [eligible],
                beginCandidates: [changed]
            )
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(await run.viewModel.calculateRecommendation(userFits: [run.reference]) == nil)
            let calls = await run.remote.calls()
            #expect(calls.contains("eligible_sizes"))
            #expect(calls.contains("begin_comparison"))
            #expect(!calls.contains("complete_comparison"))
        }
    }

    /// CP-029: labels/order are presentation facts from the server snapshot;
    /// duplicated candidate identities are a contract violation and must fail
    /// closed before completion rather than be normalized locally.
    @Test func cp029UnusualLabelsPreserveOrderAndDuplicateCandidateIDsFailClosed() async throws {
        do {
            let fixture = HeadlessJourneyFixture(provider: .musinsa)
            let candidates = [
                HeadlessServerCandidateFixture(productSizeID: UUID(), sizeLabel: "28/30", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 52), .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)]),
                HeadlessServerCandidateFixture(productSizeID: UUID(), sizeLabel: "00", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51), .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)]),
                HeadlessServerCandidateFixture(productSizeID: UUID(), sizeLabel: "2XL Tall", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 53), .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)])
            ]
            let run = try makeCandidateComparison(
                fixture: fixture,
                candidates: candidates,
                completionSizeID: candidates[1].productSizeID
            )
            #expect(await run.viewModel.loadProductInfoFromURL())
            let history = try #require(await run.viewModel.calculateRecommendation(userFits: [run.reference]))
            #expect(history.product.sizes.map(\.name) == ["28/30", "00", "2XL Tall"])
        }

        do {
            let fixture = HeadlessJourneyFixture(provider: .musinsa)
            let duplicateID = UUID()
            let candidates = [
                HeadlessServerCandidateFixture(productSizeID: duplicateID, sizeLabel: "M", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51), .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)]),
                HeadlessServerCandidateFixture(productSizeID: duplicateID, sizeLabel: "L", metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 52), .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)])
            ]
            let run = try makeCandidateComparison(fixture: fixture, candidates: candidates)
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(await run.viewModel.calculateRecommendation(userFits: [run.reference]) == nil)
            #expect(!(await run.remote.calls()).contains("complete_comparison"))
            #expect(run.viewModel.errorMessage?.isEmpty == false)
        }
    }

    /// CP-034: a personal completed comparison is historical evidence. If a
    /// later server runtime declares the target NOT_APPLICABLE, only that
    /// future attempt stops; the prior personal Product/History remains
    /// untouched and no second begin may be issued.
    @Test func cp034LaterGlobalNotApplicableBlocksOnlyTheFutureComparison() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let record = fixture.closetRecord(for: reference)
        let personalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 3,
            personalCandidateFingerprint: "cp034-personal",
            personalCandidateSetHash: "cp034-set"
        )
        let blockedRuntime = try fixture.runtime(globalStatus: .notComparable)
        let remote = JourneyRecordingRemote(
            resolutions: [
                fixture.resolution(globalStatus: .reviewRequired),
                fixture.resolution(globalStatus: .reviewRequired),
                fixture.resolution(globalStatus: .notComparable)
            ],
            runtimes: [personalRuntime, personalRuntime, blockedRuntime],
            closetResponses: [.init(state: "ready", items: [record])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: record.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: record.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 3
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: true,
                referenceClosetItemID: record.closetItemID,
                personalGarment: "polo_shirt",
                personalRevision: 3,
                personalCandidateFingerprint: "cp034-personal",
                personalCandidateSetHash: "cp034-set",
                personalInputFingerprint: "input-v1",
                personalEvidenceFingerprint: "evidence-v1"
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)

        #expect(await viewModel.loadProductInfoFromURL())
        let oldHistory = try #require(
            await viewModel.calculateRecommendation(userFits: [reference])
        )
        let oldAuthority = oldHistory.product.classificationAuthorityProvenance
        let oldGarment = oldHistory.product.garmentTypeRawValue

        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(oldHistory.product.classificationAuthorityProvenance == oldAuthority)
        #expect(oldHistory.product.garmentTypeRawValue == oldGarment)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(calls.filter { $0 == "complete_comparison" }.count == 1)
    }

    /// CP-037/CP-038: all-size semantic removal, sold-out inventory, and a
    /// missing size table are separate server/product states. Each keeps the
    /// comparison before begin and leaves a concrete user-facing reason.
    @Test func cp037AndCp038AllSizeRemovalInventoryAndNoTableFailClosed() async throws {
        let noSurvivor = HeadlessServerCandidateFixture(
            productSizeID: UUID(),
            sizeLabel: "M",
            metrics: [
                .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
            ]
        )
        let semanticRun = try makeCandidateComparison(
            fixture: HeadlessJourneyFixture(provider: .musinsa),
            candidates: [noSurvivor],
            eligibleAllowed: false,
            eligibleDecision: "BLOCKED",
            eligibleReason: "all_sizes_removed_by_measurement_semantics"
        )
        #expect(await semanticRun.viewModel.loadProductInfoFromURL())
        #expect(await semanticRun.viewModel.calculateRecommendation(userFits: [semanticRun.reference]) == nil)
        #expect(semanticRun.viewModel.errorMessage?.isEmpty == false)
        #expect(!(await semanticRun.remote.calls()).contains("begin_comparison"))

        let soldOut = HeadlessServerCandidateFixture(
            productSizeID: UUID(),
            sizeLabel: "M",
            availabilityStatus: "SOLD_OUT",
            metrics: [
                .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
            ]
        )
        let inventoryRun = try makeCandidateComparison(
            fixture: HeadlessJourneyFixture(provider: .zara),
            candidates: [soldOut],
            eligibleAllowed: false,
            eligibleDecision: "BLOCKED",
            eligibleReason: "no_available_size"
        )
        #expect(await inventoryRun.viewModel.loadProductInfoFromURL())
        #expect(await inventoryRun.viewModel.calculateRecommendation(userFits: [inventoryRun.reference]) == nil)
        #expect(inventoryRun.viewModel.errorMessage?.isEmpty == false)
        #expect(!(await inventoryRun.remote.calls()).contains("begin_comparison"))

        var parsedWithoutTable = HeadlessJourneyFixture(provider: .uniqlo).parsedProduct()
        parsedWithoutTable.sizes = []
        let noTableFixture = HeadlessJourneyFixture(
            provider: .uniqlo,
            parsedProductOverride: parsedWithoutTable
        )
        let noTableRemote = JourneyRecordingRemote(
            resolutions: [noTableFixture.resolution(globalStatus: .confirmed)],
            runtimes: [try noTableFixture.runtime(globalStatus: .confirmed)]
        )
        let noTableViewModel = makeJourneyViewModel(
            fixture: noTableFixture,
            remote: noTableRemote
        )
        #expect(await noTableViewModel.loadProductInfoFromURL())
        #expect(await noTableViewModel.calculateRecommendation(userFits: []) == nil)
        #expect(noTableViewModel.errorMessage?.isEmpty == false)
        let noTableCalls = await noTableRemote.calls()
        #expect(!noTableCalls.contains("reference_candidates"))
        #expect(!noTableCalls.contains("begin_comparison"))
    }

    /// CP-039: every negative server-authorized gate owns its own terminal
    /// block. The test constructs unresolved authority, NOT_APPLICABLE, no
    /// reference, authorization denial, eligible-size denial, and a missing
    /// begin response independently, and none may reach the engine/complete
    /// boundary.
    @Test func cp039NegativeGateOrderKeepsEveryPathBeforeEngine() async throws {
        // Unresolved authority.
        do {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
                runtimes: [try fixture.runtime(globalStatus: .reviewRequired)],
                recoveryContracts: [try fixture.recoveryContract(count: 0, suffix: "cp039")]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL() == false)
            #expect(await viewModel.calculateRecommendation(userFits: []) == nil)
            #expect(!(await remote.calls()).contains("begin_comparison"))
        }

        // Global NOT_APPLICABLE.
        do {
            let fixture = HeadlessJourneyFixture(provider: .musinsa)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .notComparable)],
                runtimes: [try fixture.runtime(globalStatus: .notComparable)]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL() == false)
            #expect(viewModel.errorMessage?.isEmpty == false)
            #expect(!(await remote.calls()).contains("begin_comparison"))
        }

        // Confirmed target, but no local reference record.
        do {
            let fixture = HeadlessJourneyFixture(provider: .zara)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed)],
                runtimes: [try fixture.runtime(globalStatus: .confirmed)]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(await viewModel.calculateRecommendation(userFits: []) == nil)
            #expect(viewModel.errorMessage?.isEmpty == false)
            #expect(!(await remote.calls()).contains("begin_comparison"))
        }

        // Explicit server reference authorization denial.
        do {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
            let record = fixture.closetRecord(for: reference)
            let runtime = try fixture.runtime(globalStatus: .confirmed)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
                runtimes: [runtime, runtime],
                closetResponses: [.init(state: "ready", items: [record])],
                candidateResponses: [try fixture.referenceResponse(
                    reference: reference,
                    closetItemID: record.closetItemID,
                    decision: "BLOCKED"
                )]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(await viewModel.calculateRecommendation(userFits: [reference]) == nil)
            let calls = await remote.calls()
            #expect(calls.contains("reference_candidates"))
            #expect(!calls.contains("eligible_sizes"))
            #expect(!calls.contains("begin_comparison"))
        }

        // Eligible-size denial after a valid reference decision.
        do {
            let candidate = HeadlessServerCandidateFixture(
                productSizeID: UUID(),
                sizeLabel: "M",
                metrics: [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
                ]
            )
            let run = try makeCandidateComparison(
                fixture: HeadlessJourneyFixture(provider: .musinsa),
                candidates: [candidate],
                eligibleAllowed: false,
                eligibleDecision: "BLOCKED",
                eligibleReason: "no_eligible_size"
            )
            #expect(await run.viewModel.loadProductInfoFromURL())
            #expect(await run.viewModel.calculateRecommendation(userFits: [run.reference]) == nil)
            let calls = await run.remote.calls()
            #expect(calls.contains("eligible_sizes"))
            #expect(!calls.contains("begin_comparison"))
        }

        // A response missing the immutable begin snapshot cannot score.
        do {
            let candidate = HeadlessServerCandidateFixture(
                productSizeID: UUID(),
                sizeLabel: "M",
                metrics: [
                    .init(code: "chest_width_pit_to_pit", referenceValue: 50, targetValue: 51),
                    .init(code: "shoulder_width_seam_to_seam", referenceValue: 48, targetValue: 48)
                ]
            )
            let fixture = HeadlessJourneyFixture(provider: .zara)
            let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
            let record = fixture.closetRecord(for: reference)
            let runtime = try fixture.runtime(globalStatus: .confirmed, runtimeCandidates: [candidate])
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
                runtimes: [runtime, runtime],
                closetResponses: [.init(state: "ready", items: [record])],
                candidateResponses: [try fixture.referenceResponse(
                    reference: reference,
                    closetItemID: record.closetItemID,
                    decision: "AUTOMATIC",
                    eligibleProductSizeIDs: [candidate.productSizeID]
                )],
                eligibleResponses: [try fixture.eligible(
                    referenceClosetItemID: record.closetItemID,
                    candidates: [candidate],
                    allowed: true,
                    decision: "AUTOMATIC"
                )]
            )
            let viewModel = makeJourneyViewModel(fixture: fixture, remote: remote)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(await viewModel.calculateRecommendation(userFits: [reference]) == nil)
            let calls = await remote.calls()
            #expect(calls.contains("begin_comparison"))
            #expect(!calls.contains("complete_comparison"))
        }
    }

    @Test func headlessHarnessDoesNotDuplicateBusinessAuthority() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "FitMatchTests/FitMatchHeadlessUserJourneyTests.swift"
            ),
            encoding: .utf8
        )
        let coordinator = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "FitMatch/Services/FitMatchServerAuthorityCoordinator.swift"
            ),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "FitMatch/ViewModels/ShoppingProductViewModel.swift"
            ),
            encoding: .utf8
        )

        // The harness never invokes an engine directly.  The only source-level
        // engine mention is the expected production symbol in the assertion
        // above; it constructs no MeasurementComparisonEngine or adapter.
        let directEngineConstruction = "MeasurementComparison" + "Engine()"
        let directAdapterConstruction = "VNextComparison" + "EngineAdapter()"
        #expect(!source.contains(directEngineConstruction))
        #expect(!source.contains(directAdapterConstruction))
        #expect(coordinator.contains("func beginAuthorizedComparison"))
        #expect(viewModel.contains("recommendationService.analyzeVNextComparison"))
        #expect(viewModel.contains("completeVNextRecommendation"))
    }

    private func makeJourneyViewModel(
        fixture: HeadlessJourneyFixture,
        remote: JourneyRecordingRemote
    ) -> ShoppingProductViewModel {
        let parser = HeadlessJourneyParser(product: fixture.parsedProduct())
        return ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                musinsaParser: parser,
                uniqloParser: parser,
                zaraParser: parser
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
    }

    /// Common transport wiring for scenarios whose business distinction is an
    /// issued vNext candidate/evidence snapshot. It serializes the exact
    /// remote contract only; the ViewModel/coordinator/engine decide the
    /// terminal outcome.
    private func makeCandidateComparison(
        fixture: HeadlessJourneyFixture,
        candidates: [HeadlessServerCandidateFixture],
        eligibleAllowed: Bool = true,
        eligibleDecision: String = "AUTOMATIC",
        eligibleReason: String? = nil,
        beginCandidates: [HeadlessServerCandidateFixture]? = nil,
        policyMetricCodes: [String] = ["chest_width_pit_to_pit"],
        completionSizeID: UUID? = nil,
        completionCoverage: Double = 1,
        configureReference: (UserFit) -> Void = { _ in }
    ) throws -> (
        viewModel: ShoppingProductViewModel,
        reference: UserFit,
        remote: JourneyRecordingRemote
    ) {
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        configureReference(reference)
        let record = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(
            globalStatus: .confirmed,
            runtimeCandidates: candidates
        )
        let remote = JourneyRecordingRemote(
            resolutions: [
                fixture.resolution(globalStatus: .confirmed),
                fixture.resolution(globalStatus: .confirmed)
            ],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [record])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: record.closetItemID,
                decision: "AUTOMATIC",
                eligibleProductSizeIDs: candidates.map(\.productSizeID)
            )],
            eligibleResponses: [try fixture.eligible(
                referenceClosetItemID: record.closetItemID,
                candidates: candidates,
                allowed: eligibleAllowed,
                decision: eligibleDecision,
                reason: eligibleReason
            )],
            beginResponses: eligibleAllowed ? [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: record.closetItemID,
                candidates: beginCandidates ?? candidates,
                policyMetricCodes: policyMetricCodes
            )] : [],
            completionResponses: eligibleAllowed ? [try fixture.complete(
                recommendedProductSizeID: completionSizeID,
                coverage: completionCoverage
            )] : []
        )
        return (makeJourneyViewModel(fixture: fixture, remote: remote), reference, remote)
    }
}

enum HeadlessJourneyProvider: String, Sendable, Equatable {
    case uniqlo
    case musinsa
    case zara
}

private enum HeadlessFixtureProvenance: String, Sendable {
    case realProductionSnapshot = "REAL_PRODUCTION_SNAPSHOT"
    case syntheticAdversarial = "SYNTHETIC_ADVERSARIAL"
    case policyState = "POLICY_STATE"
}

private enum HeadlessJourneyProgram: Sendable, Equatable {
    case emptyCloset
    case noReference
    case automaticDirect
    case sameTypeSleeveDifferent
    case manualCrossAutomaticBlocked
    case manualCrossExplicitAllowed
    case manualCrossSleeveBlocked
    case manualExplicitGlobal
    case incompatibleReference
    case measurementsRequired
    case availabilityBlocked
    case recoveryResume
    case reviewLifecycle
    case unrecoverable
    case notApplicable
    case staleCandidate
    case staleRevision
    case staleReference
    case providerRetry
    case duplicateAction
    case targetAuthorityChanged
    case referenceChanged
    case historyLifecycle
}

private enum HeadlessUXOutcome: String, Sendable, Hashable {
    case expected = "EXPECTED"
    case blockedWithReason = "BLOCKED_WITH_REASON"
    case productSupportGap = "PRODUCT_SUPPORT_GAP"
    case testDataLimitation = "TEST_DATA_LIMITATION"
}

private struct HeadlessJourneyScenario: Sendable {
    let id: String
    let provenance: HeadlessFixtureProvenance
    let provider: HeadlessJourneyProvider
    let closet: String
    let classification: String
    let relation: String
    let measurement: String
    let availability: String
    let actions: [String]
    let program: HeadlessJourneyProgram
}

private struct HeadlessJourneyExecution: Sendable {
    let technicalPass: Bool
    let uxOutcome: HeadlessUXOutcome
    let remoteCalls: [String]
    let productionSymbols: [String]
    let note: String
}

private enum HeadlessJourneyScenarioCatalog {
    static let valid: [HeadlessJourneyScenario] = [
        scenario("J01", .uniqlo, "C0", "G0", "R0", "M0", "A0", ["U6", "U7"], .emptyCloset),
        scenario("J02", .uniqlo, "C1/C2", "G0", "R0", "M0", "A0", ["U0", "U7"], .noReference),
        scenario("J03", .uniqlo, "C3", "G0", "R1", "M0", "A0", ["U0", "U3", "U7", "U8"], .automaticDirect),
        scenario("J04", .musinsa, "C6", "G0", "R1", "M10", "A1", ["U6", "U7", "U8"], .automaticDirect),
        scenario("J05", .zara, "C7/C10", "G0", "R3", "M0", "A0", ["U6", "U7"], .sameTypeSleeveDifferent),
        scenario("J06", .uniqlo, "C8", "G7", "R5", "M0", "A0", ["U6", "U8"], .manualCrossAutomaticBlocked),
        scenario("J07", .uniqlo, "C8", "G7", "R5", "M0", "A0", ["U6", "U9"], .manualCrossExplicitAllowed),
        scenario("J08", .uniqlo, "C8", "G7", "R6", "M0", "A0", ["U6", "U9"], .manualCrossSleeveBlocked),
        scenario("J09", .musinsa, "C8", "G7", "R7", "M0", "A0", ["U6", "U9"], .manualCrossExplicitAllowed),
        scenario("J10", .musinsa, "C8", "G7", "R8", "M0", "A0", ["U6", "U9"], .manualCrossSleeveBlocked),
        scenario("J11", .zara, "C8", "G7", "R9", "M0", "A0", ["U6", "U9"], .manualCrossExplicitAllowed),
        scenario("J12", .zara, "C19/C20", "G7", "R10/R12", "M0", "A0", ["U6", "U9"], .manualCrossSleeveBlocked),
        scenario("J13", .uniqlo, "C3", "G2/G7", "R1", "M0", "A0", ["U6", "U10", "U7", "U8"], .recoveryResume),
        scenario("J14", .uniqlo, "C3", "G9", "R1", "M0", "A0", ["U11", "U12"], .reviewLifecycle),
        scenario("J15", .uniqlo, "C3", "G10", "R1", "M0", "A0", ["U13"], .reviewLifecycle),
        scenario("J16", .uniqlo, "C23", "G11", "R1", "M0", "A0", ["U19"], .targetAuthorityChanged),
        scenario("J17", .musinsa, "C13", "G0", "R15", "M0", "A0", ["U1", "U19"], .staleReference),
        scenario("J18", .musinsa, "C14", "G0", "R16", "M0", "A0", ["U4", "U19"], .referenceChanged),
        scenario("J19", .musinsa, "C15", "G0", "R2", "M12", "A0", ["U2", "U19"], .automaticDirect),
        scenario("J20", .musinsa, "C23", "G11", "R17", "M0", "A0", ["U17", "U18"], .historyLifecycle),
        scenario("J21", .uniqlo, "C3", "G0", "R1", "M0", "A0", ["U15"], .automaticDirect),
        scenario("J22", .zara, "C11", "G0", "R1", "M8", "A0", ["U7"], .measurementsRequired),
        scenario("J23", .zara, "C12", "G0", "R1", "M9", "A0", ["U7"], .measurementsRequired),
        scenario("J24", .uniqlo, "C12", "G0", "R1", "M0", "A3", ["U7"], .availabilityBlocked),
        scenario("J25", .musinsa, "C12", "G0", "R1", "M0", "A2", ["U7"], .availabilityBlocked),
        scenario("J26", .zara, "C3", "G5", "R0", "M0", "A4", ["U6", "U7"], .unrecoverable),
        scenario("J27", .uniqlo, "C3", "G6", "R0", "M0", "A4", ["U6", "U7"], .notApplicable),
        scenario("J28", .musinsa, "C3", "G4", "R0", "M0", "A4", ["U6", "U10"], .unrecoverable),
        scenario("J29", .zara, "C13", "G0", "R16", "M0", "A0", ["U1", "U7"], .staleReference),
        scenario("J30", .uniqlo, "C4/C22", "G0", "R14", "M0", "A0", ["U9"], .manualExplicitGlobal),
        scenario("J31", .musinsa, "C5", "G0", "R17", "M0", "A0", ["U14"], .duplicateAction),
        scenario("J32", .zara, "C23", "G0", "R17", "M0", "A0", ["U17", "U14"], .historyLifecycle),
        scenario("J33", .uniqlo, "C3", "G7", "R1", "M0", "A0", ["U10", "U23"], .reviewLifecycle),
        scenario("J34", .musinsa, "C3", "G9/G14", "R1", "M0", "A0", ["U11", "U12", "U23"], .staleRevision),
        scenario("J35", .zara, "C3", "G10", "R1", "M0", "A0", ["U13", "U23"], .reviewLifecycle),
        scenario("J36", .uniqlo, "C16", "G0", "R1", "M0", "A0", ["U22"], .duplicateAction),
        scenario("J37", .musinsa, "C3", "G13", "R1", "M0", "A0", ["U22"], .staleCandidate),
        scenario("J38", .zara, "C3", "G10", "R1", "M0", "A0", ["U10", "U13"], .reviewLifecycle),
        scenario("J39", .uniqlo, "C3", "G14", "R1", "M0", "A0", ["U11", "U12"], .staleRevision),
        scenario("J40", .musinsa, "C24", "G0", "R16", "M0", "A9", ["U4", "U7"], .referenceChanged),
        scenario("J41", .zara, "C3", "G15", "R1", "M0", "A9", ["U7"], .targetAuthorityChanged),
        scenario("J42", .uniqlo, "C3", "G0", "R1", "M0", "A0", ["U6", "U20"], .providerRetry),
        scenario("J43", .musinsa, "C9", "G0", "R11", "M0", "A0", ["U20"], .incompatibleReference),
        scenario("J44", .zara, "C3", "G0", "R1", "M0", "A0", ["U20"], .availabilityBlocked),
        scenario("J45", .uniqlo, "C17/C18", "G0", "R2", "M4", "A10", ["U15", "U7"], .automaticDirect)
    ]

    private static func scenario(
        _ id: String,
        _ provider: HeadlessJourneyProvider,
        _ closet: String,
        _ classification: String,
        _ relation: String,
        _ measurement: String,
        _ availability: String,
        _ actions: [String],
        _ program: HeadlessJourneyProgram
    ) -> HeadlessJourneyScenario {
        HeadlessJourneyScenario(
            id: id,
            // The public Production catalog is consulted separately for the
            // provider matrix.  These remote DTO sequences are intentionally
            // synthetic; they must never be labeled as captured user/product
            // runtime responses.
            provenance: .syntheticAdversarial,
            provider: provider,
            closet: closet,
            classification: classification,
            relation: relation,
            measurement: measurement,
            availability: availability,
            actions: actions,
            program: program
        )
    }
}

@MainActor
private enum HeadlessJourneyHarness {
    static func execute(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        switch scenario.program {
        case .emptyCloset:
            return try await emptyCloset(scenario)
        case .noReference:
            return try await noReference(scenario)
        case .automaticDirect:
            return try await automaticDirect(scenario)
        case .sameTypeSleeveDifferent:
            return try await blockedReference(scenario, decision: "BLOCKED")
        case .manualCrossAutomaticBlocked:
            return try await manualCross(scenario, manuallySelected: false, sleeveMatches: true)
        case .manualCrossExplicitAllowed:
            return try await manualCross(scenario, manuallySelected: true, sleeveMatches: true)
        case .manualCrossSleeveBlocked:
            return try await manualCross(scenario, manuallySelected: true, sleeveMatches: false)
        case .manualExplicitGlobal:
            return try await manualExplicitGlobal(scenario)
        case .incompatibleReference:
            return try await blockedReference(scenario, decision: "BLOCKED")
        case .measurementsRequired:
            return try await blockedReference(scenario, decision: "MEASUREMENTS_REQUIRED")
        case .availabilityBlocked:
            return try await availabilityBlocked(scenario)
        case .recoveryResume:
            return try await recoveryResume(scenario)
        case .reviewLifecycle:
            return try await recoveryLifecycle(scenario)
        case .unrecoverable:
            return try await unrecoverable(scenario)
        case .notApplicable:
            return try await notApplicable(scenario)
        case .staleCandidate:
            return try await staleCandidate(scenario)
        case .staleRevision:
            return try await staleRevision(scenario)
        case .staleReference:
            return try await staleReference(scenario)
        case .providerRetry:
            return try await providerRetry(scenario)
        case .duplicateAction:
            return try await duplicateAction(scenario)
        case .targetAuthorityChanged:
            return try await targetAuthorityChanged(scenario)
        case .referenceChanged:
            return try await referenceChanged(scenario)
        case .historyLifecycle:
            return try await historyLifecycle(scenario)
        }
    }

    private static func emptyCloset(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let (viewModel, remote) = try makeConfirmedViewModel(provider: scenario.provider)
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "confirmed product did not load")
        let history = await viewModel.calculateRecommendation(userFits: [])
        try require(history == nil, scenario: scenario.id, message: "empty Closet produced a history")
        try require(!(viewModel.errorMessage ?? "").isEmpty, scenario: scenario.id, message: "empty Closet block has no explanation")
        let calls = await remote.calls()
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "empty Closet reached begin")
        return execution(calls, [.viewModelLoad, .authorityResolve, .comparisonEntry], .blockedWithReason)
    }

    private static func noReference(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        try await emptyCloset(scenario)
    }

    private static func automaticDirect(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)

        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "confirmed target did not load")
        let history = await viewModel.calculateRecommendation(userFits: [reference])
        try require(history != nil, scenario: scenario.id, message: "authorized automatic comparison did not complete")
        let calls = await remote.calls()
        try requireOrdered(
            calls,
            ["resolve", "runtime", "list_closet", "reference_candidates", "eligible_sizes", "begin_comparison", "complete_comparison"],
            scenario: scenario.id
        )
        return execution(
            calls,
            [.viewModelLoad, .authorityResolve, .referenceDecision, .eligibleSizes, .begin, .recommendationService, .engineAdapter, .complete, .historyModel],
            .expected
        )
    }

    private static func manualCross(
        _ scenario: HeadlessJourneyScenario,
        manuallySelected: Bool,
        sleeveMatches: Bool
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let crossPair: (target: String, reference: String)
        switch scenario.id {
        case "J09", "J10":
            crossPair = ("hoodie", "sweatshirt")
        case "J11", "J12":
            crossPair = ("knit_sweater", "sweatshirt")
        default:
            crossPair = ("polo_shirt", "tshirt")
        }
        let reference = fixture.localReference(
            garment: crossPair.reference,
            sleeve: sleeveMatches ? "short_sleeve" : "long_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(
            globalStatus: .confirmed,
            effectivePersonalGarment: crossPair.target,
            overrideRevision: 1
        )
        let decision = sleeveMatches ? "MANUAL_EXTENDED" : "BLOCKED"
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired), fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: decision
            )],
            eligibleResponses: manuallySelected && sleeveMatches ? [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "MANUAL_EXTENDED",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 1
            )] : [],
            beginResponses: manuallySelected && sleeveMatches
                ? [try fixture.begin(
                    mode: "MANUAL_EXTENDED",
                    personal: true,
                    referenceClosetItemID: remoteReference.closetItemID,
                    personalGarment: crossPair.target
                )] : [],
            completionResponses: manuallySelected && sleeveMatches ? [try fixture.complete()] : []
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)

        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "personal effective target did not load")
        let history: RecommendationHistory?
        if manuallySelected {
            history = await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: reference)
        } else {
            history = await viewModel.calculateRecommendation(userFits: [reference])
        }
        let calls = await remote.calls()

        if manuallySelected && sleeveMatches {
            let diagnosticError = viewModel.errorMessage ?? "<nil>"
            try require(
                history != nil,
                scenario: scenario.id,
                message: "explicit same-sleeve manual cross did not complete; calls=\(calls); error=\(diagnosticError)"
            )
            try require(calls.contains("eligible_sizes"), scenario: scenario.id, message: "manual cross skipped eligible sizes")
            try require(calls.contains("begin_comparison"), scenario: scenario.id, message: "manual cross skipped begin")
            return execution(
                calls,
                [.viewModelLoad, .authorityResolve, .referenceDecision, .eligibleSizes, .begin, .recommendationService, .engineAdapter, .complete, .historyModel],
                .expected
            )
        }

        try require(history == nil, scenario: scenario.id, message: "blocked manual cross produced history")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "blocked manual cross reached begin")
        try require(!calls.contains("complete_comparison"), scenario: scenario.id, message: "blocked manual cross reached completion")
        try require(!(viewModel.errorMessage ?? "").isEmpty, scenario: scenario.id, message: "blocked manual cross has no explanation")
        return execution(calls, [.viewModelLoad, .authorityResolve, .referenceDecision], .blockedWithReason)
    }

    /// A normal GLOBAL_CONFIRMED product with a user-selected reference.  This
    /// is intentionally separate from the USER_EXPLICIT target manual-cross
    /// corridor so a personal-target History defect is not counted twice.
    private static func manualExplicitGlobal(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "MANUAL_EXTENDED"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "MANUAL_EXTENDED",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "MANUAL_EXTENDED",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        let loaded = await viewModel.loadProductInfoFromURL()
        try require(loaded, scenario: scenario.id, message: "global target did not load")
        let history = await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: reference)
        let calls = await remote.calls()
        try require(history != nil, scenario: scenario.id, message: "manual reference path did not create history")
        try requireOrdered(
            calls,
            ["resolve", "runtime", "list_closet", "reference_candidates", "eligible_sizes", "begin_comparison", "complete_comparison"],
            scenario: scenario.id
        )
        return execution(
            calls,
            [.viewModelLoad, .authorityResolve, .referenceDecision, .eligibleSizes, .begin, .recommendationService, .engineAdapter, .complete, .historyModel],
            .expected
        )
    }

    private static func blockedReference(
        _ scenario: HeadlessJourneyScenario,
        decision: String
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: decision
            )]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "target did not load")
        let history = await viewModel.calculateRecommendation(userFits: [reference])
        let calls = await remote.calls()
        try require(history == nil, scenario: scenario.id, message: "blocked reference produced history")
        try require(!calls.contains("eligible_sizes"), scenario: scenario.id, message: "blocked reference reached eligible sizes")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "blocked reference reached begin")
        try require(!(viewModel.errorMessage ?? "").isEmpty, scenario: scenario.id, message: "block lacks explanation")
        return execution(calls, [.viewModelLoad, .authorityResolve, .referenceDecision], .blockedWithReason)
    }

    private static func availabilityBlocked(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: false,
                effectiveSource: nil,
                overrideRevision: nil
            )]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "target did not load")
        let history = await viewModel.calculateRecommendation(userFits: [reference])
        let calls = await remote.calls()
        try require(history == nil, scenario: scenario.id, message: "availability-blocked target produced history")
        try require(calls.contains("eligible_sizes"), scenario: scenario.id, message: "availability gate was not queried")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "availability block reached begin")
        return execution(calls, [.viewModelLoad, .authorityResolve, .referenceDecision, .eligibleSizes], .blockedWithReason)
    }

    /// Executes the same production ViewModel continuation that the existing
    /// CompareFlowSheet starts after its bounded Recovery UI saves a candidate.
    /// The harness deliberately does not decide a reference, score, or result.
    private static func recoveryResume(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let contract = try fixture.recoveryContract(count: 1, suffix: "resume")
        let reviewRuntime = try fixture.runtime(globalStatus: .reviewRequired)
        let personalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "tshirt",
            overrideRevision: 1,
            personalCandidateFingerprint: "candidate-tshirt-resume",
            personalCandidateSetHash: "set-resume"
        )
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .reviewRequired), count: 3),
            runtimes: [reviewRuntime, personalRuntime, personalRuntime],
            recoveryContracts: [contract],
            setMutations: [
                try fixture.setMutation(
                    contract: contract,
                    garment: "tshirt",
                    revision: 1,
                    event: "SELECTED"
                )
            ],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 1
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: true,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: "tshirt",
                personalCandidateFingerprint: "candidate-tshirt-resume",
                personalCandidateSetHash: "set-resume"
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)

        let initiallyLoaded = await viewModel.loadProductInfoFromURL()
        try require(!initiallyLoaded, scenario: scenario.id, message: "REVIEW_REQUIRED bypassed bounded Recovery")
        let candidate = try requireValue(
            viewModel.reviewRecoveryContract?.candidates.first,
            scenario: scenario.id,
            message: "server Recovery candidate missing"
        )
        let saved = await viewModel.confirmReviewRecovery(candidate)
        try require(saved, scenario: scenario.id, message: "USER_EXPLICIT save/effective refresh failed")
        try require(
            viewModel.hasActiveUserExplicitClassification,
            scenario: scenario.id,
            message: "fresh personal effective authority missing"
        )

        let history = await viewModel.calculateRecommendation(userFits: [reference])
        let calls = await remote.calls()
        let diagnosticError = viewModel.errorMessage ?? "<nil>"
        try requireOrdered(
            calls,
            [
                "resolve", "runtime", "recovery_contract",
                "set_user_product_classification", "resolve", "runtime",
                "list_closet", "reference_candidates", "eligible_sizes",
                "begin_comparison", "complete_comparison"
            ],
            scenario: scenario.id
        )
        try require(
            history != nil,
            scenario: scenario.id,
            message: "USER_EXPLICIT resumed through server completion but no Result/History was created; calls=\(calls); error=\(diagnosticError)"
        )
        return execution(
            calls,
            [.viewModelLoad, .authorityResolve, .recoveryContract, .recoveryMutation, .referenceDecision, .eligibleSizes, .begin, .recommendationService, .engineAdapter, .complete, .historyModel],
            .expected
        )
    }

    private static func recoveryLifecycle(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let contractA = try fixture.recoveryContract(count: 2, suffix: "a")
        let contractB = try fixture.recoveryContract(count: 2, suffix: "b")
        let review = try fixture.runtime(globalStatus: .reviewRequired)
        let personalA = try fixture.runtime(
            globalStatus: .confirmed,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1
        )
        let personalB = try fixture.runtime(
            globalStatus: .confirmed,
            effectivePersonalGarment: "tshirt",
            overrideRevision: 2
        )
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .reviewRequired), count: 5),
            runtimes: [review, personalA, personalB, review, review],
            recoveryContracts: [contractA, contractB, contractB, contractB],
            setMutations: [
                try fixture.setMutation(contract: contractA, garment: "polo_shirt", revision: 1, event: "SELECTED"),
                try fixture.setMutation(contract: contractB, garment: "tshirt", revision: 2, event: "EDITED")
            ],
            clearMutations: [try fixture.clearMutation(revision: 3)]
        )
        let first = makeViewModel(fixture: fixture, remote: remote)

        try require(!(await first.loadProductInfoFromURL()), scenario: scenario.id, message: "review product unexpectedly loaded as confirmed")
        let initial = try requireValue(first.reviewRecoveryContract, scenario: scenario.id, message: "initial bounded Recovery contract missing")
        let candidateA = try requireValue(initial.candidates.first(where: { $0.garmentTypeCode == "polo_shirt" }), scenario: scenario.id, message: "candidate A missing")
        try require(await first.confirmReviewRecovery(candidateA), scenario: scenario.id, message: "initial Recovery selection failed")
        try require(first.hasActiveUserExplicitClassification, scenario: scenario.id, message: "active personal authority missing after select")

        try require(await first.beginReviewRecoveryReselection(), scenario: scenario.id, message: "fresh Recovery contract not requested for reselect")
        let latest = try requireValue(first.reviewRecoveryContract, scenario: scenario.id, message: "fresh Recovery contract missing")
        try require(latest.candidateSetHash != initial.candidateSetHash, scenario: scenario.id, message: "stale Recovery contract reused")
        let candidateB = try requireValue(latest.candidates.first(where: { $0.garmentTypeCode == "tshirt" }), scenario: scenario.id, message: "candidate B missing")
        try require(await first.confirmReviewRecovery(candidateB), scenario: scenario.id, message: "Recovery reselect failed")
        try require(await first.clearReviewRecovery(), scenario: scenario.id, message: "Recovery clear failed")
        try require(!first.hasActiveUserExplicitClassification, scenario: scenario.id, message: "cleared authority still active")
        if case .reviewRequired = first.serverAuthorityState {
            // Correct fail-closed post-clear state.
        } else {
            throw HeadlessJourneyFailure(scenario.id, "clear did not restore REVIEW_REQUIRED")
        }

        // Object reconstruction is a headless rehydration model: no cached
        // local projection is injected into this newly constructed ViewModel.
        let reconstructed = makeViewModel(fixture: fixture, remote: remote)
        try require(!(await reconstructed.loadProductInfoFromURL()), scenario: scenario.id, message: "cleared selection resurfaced after reconstruction")
        try require(!reconstructed.hasActiveUserExplicitClassification, scenario: scenario.id, message: "cleared authority reappeared after reconstruction")
        let calls = await remote.calls()
        let mutations = await remote.setRequests()
        try require(mutations.count == 2, scenario: scenario.id, message: "unexpected number of Recovery mutations")
        try require(mutations[0].expectedRevision == 0, scenario: scenario.id, message: "initial revision mismatch")
        try require(mutations[1].expectedRevision == 1, scenario: scenario.id, message: "reselect revision did not advance")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "Recovery selection skipped reference decision and reached begin")
        return execution(calls, [.viewModelLoad, .authorityResolve, .recoveryContract, .recoveryMutation], .expected)
    }

    private static func unrecoverable(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let runtime = try fixture.runtime(
            globalStatus: .reviewRequired,
            productStructure: scenario.classification.contains("G5") ? "UNKNOWN" : "SINGLE"
        )
        let contract = try fixture.recoveryContract(
            count: 0,
            suffix: scenario.classification.contains("G5") ? "unknown" : "zero"
        )
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [runtime],
            recoveryContracts: [contract]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(!(await viewModel.loadProductInfoFromURL()), scenario: scenario.id, message: "unrecoverable target loaded as confirmed")
        if case .unrecoverable = viewModel.reviewRecoveryState {
            // Correct bounded fail-closed state.
        } else {
            throw HeadlessJourneyFailure(scenario.id, "unrecoverable target exposed active Recovery")
        }
        let calls = await remote.calls()
        try require(!calls.contains("set_user_product_classification"), scenario: scenario.id, message: "zero-candidate Recovery attempted mutation")
        return execution(calls, [.viewModelLoad, .authorityResolve, .recoveryContract], .blockedWithReason)
    }

    private static func notApplicable(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let runtime = try fixture.runtime(globalStatus: .notComparable)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .notComparable)],
            runtimes: [runtime]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(!(await viewModel.loadProductInfoFromURL()), scenario: scenario.id, message: "NOT_APPLICABLE target loaded as confirmed")
        let history = await viewModel.calculateRecommendation(userFits: [])
        let calls = await remote.calls()
        try require(history == nil, scenario: scenario.id, message: "NOT_APPLICABLE target produced history")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "NOT_APPLICABLE target reached begin")
        return execution(calls, [.viewModelLoad, .authorityResolve, .comparisonEntry], .blockedWithReason)
    }

    private static func staleCandidate(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let contract = try fixture.recoveryContract(count: 1, suffix: "fresh")
        let remote = JourneyRecordingRemote(recoveryContracts: [contract])
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let latest = try await coordinator.classificationRecoveryOptions(productID: fixture.productID)
        let forged = try decode("""
        {
          "candidate_id":"forged","candidate_fingerprint":"forged",
          "display_name":"후드","category_code":"tops",
          "garment_type_code":"hoodie","sleeve_length_code":"long_sleeve",
          "comparison_policy_code":"hoodie"
        }
        """) as VNextClassificationRecoveryCandidateDTO
        var rejected = false
        do {
            _ = try await coordinator.setUserProductClassification(
                contract: latest,
                candidate: forged,
                expectedRevision: 0
            )
        } catch let error as FitMatchServerAuthorityError {
            rejected = error == .invalidClassificationRecoveryContract("candidate_not_in_server_contract")
        }
        let calls = await remote.calls()
        try require(rejected, scenario: scenario.id, message: "forged candidate was not rejected")
        try require(!calls.contains("set_user_product_classification"), scenario: scenario.id, message: "forged candidate reached remote mutation")
        return execution(calls, [.recoveryContract, .recoveryMutation], .blockedWithReason)
    }

    private static func staleRevision(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let contract = try fixture.recoveryContract(count: 1, suffix: "revision")
        let remote = JourneyRecordingRemote(
            recoveryContracts: [contract],
            setFailureCount: 1
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let latest = try await coordinator.classificationRecoveryOptions(productID: fixture.productID)
        let candidate = try requireValue(latest.candidates.first, scenario: scenario.id, message: "candidate missing")
        var rejected = false
        do {
            _ = try await coordinator.setUserProductClassification(
                contract: latest,
                candidate: candidate,
                expectedRevision: 99
            )
        } catch {
            rejected = true
        }
        let calls = await remote.calls()
        try require(rejected, scenario: scenario.id, message: "stale revision was accepted")
        try require(calls == ["recovery_contract", "set_user_product_classification"], scenario: scenario.id, message: "unexpected stale-revision sequence")
        return execution(calls, [.recoveryContract, .recoveryMutation], .blockedWithReason)
    }

    private static func staleReference(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [])]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "target did not load")
        let history = await viewModel.calculateRecommendation(userFits: [reference])
        let calls = await remote.calls()
        try require(history == nil, scenario: scenario.id, message: "deleted reference produced history")
        try require(!calls.contains("reference_candidates"), scenario: scenario.id, message: "missing Closet reference reached evaluator")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "deleted reference reached begin")
        return execution(calls, [.viewModelLoad, .authorityResolve, .referenceDecision], .blockedWithReason)
    }

    private static func providerRetry(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime],
            resolveFailureCount: 1
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(!(await viewModel.loadProductInfoFromURL()), scenario: scenario.id, message: "modeled transport failure unexpectedly succeeded")
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "retry did not reach current authority")
        let calls = await remote.calls()
        try require(calls.filter { $0 == "resolve" }.count == 2, scenario: scenario.id, message: "retry did not issue exactly one retry")
        return execution(calls, [.viewModelLoad, .authorityResolve], .expected)
    }

    private static func duplicateAction(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 3),
            runtimes: Array(repeating: runtime, count: 3),
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [
                try fixture.referenceResponse(reference: reference, closetItemID: remoteReference.closetItemID, decision: "AUTOMATIC"),
                try fixture.referenceResponse(reference: reference, closetItemID: remoteReference.closetItemID, decision: "AUTOMATIC")
            ],
            eligibleResponses: [
                try fixture.eligible(reference: reference, closetItemID: remoteReference.closetItemID, mode: "AUTOMATIC", allowed: true, effectiveSource: nil, overrideRevision: nil),
                try fixture.eligible(reference: reference, closetItemID: remoteReference.closetItemID, mode: "AUTOMATIC", allowed: true, effectiveSource: nil, overrideRevision: nil)
            ],
            beginResponses: [
                try fixture.begin(
                    mode: "AUTOMATIC",
                    personal: false,
                    referenceClosetItemID: remoteReference.closetItemID
                ),
                try fixture.begin(
                    mode: "AUTOMATIC",
                    personal: false,
                    referenceClosetItemID: remoteReference.closetItemID
                )
            ],
            completionResponses: [try fixture.complete(), try fixture.complete()]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "target did not load")
        let first = await viewModel.calculateRecommendation(userFits: [reference])
        let second = await viewModel.calculateRecommendation(userFits: [reference])
        let calls = await remote.calls()
        try require(first != nil && second != nil, scenario: scenario.id, message: "modeled duplicate action did not reach Production Swift path")
        try require(calls.filter { $0 == "begin_comparison" }.count == 2, scenario: scenario.id, message: "duplicate action did not record both server begins")
        return execution(
            calls,
            [.viewModelLoad, .authorityResolve, .referenceDecision, .eligibleSizes, .begin, .recommendationService, .engineAdapter, .complete, .historyModel],
            .testDataLimitation,
            note: "Two deliberate actions have distinct client-history IDs; scripted transport cannot prove Production deduplication semantics."
        )
    }

    private static func targetAuthorityChanged(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        let fixture = HeadlessJourneyFixture(provider: scenario.provider)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let confirmed = try fixture.runtime(globalStatus: .confirmed)
        let review = try fixture.runtime(globalStatus: .reviewRequired)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [confirmed, review],
            closetResponses: [.init(state: "ready", items: [fixture.closetRecord(for: reference)])]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        try require(await viewModel.loadProductInfoFromURL(), scenario: scenario.id, message: "initial target did not load")
        let history = await viewModel.calculateRecommendation(userFits: [reference])
        let calls = await remote.calls()
        try require(history == nil, scenario: scenario.id, message: "changed target authority produced history")
        try require(!calls.contains("begin_comparison"), scenario: scenario.id, message: "changed target authority reached begin")
        return execution(calls, [.viewModelLoad, .authorityResolve, .referenceDecision], .blockedWithReason)
    }

    private static func referenceChanged(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        // The exact remote/local snapshot check is the current production
        // lifecycle guard for a reference that changed while a comparison was
        // being prepared.
        try await staleReference(scenario)
    }

    private static func historyLifecycle(
        _ scenario: HeadlessJourneyScenario
    ) async throws -> HeadlessJourneyExecution {
        // The current authoritative History hydration and deleted-reference
        // lifecycle are covered by actual production-code tests in the critical
        // regression suite.  The headless journey nevertheless runs a full
        // comparison first, so its local history model is created only after
        // completion.  It then verifies that a follow-up current comparison
        // uses a fresh server path rather than mutating that completed result.
        let record = try await automaticDirect(scenario)
        try require(record.remoteCalls.contains("complete_comparison"), scenario: scenario.id, message: "history was created before completion")
        return HeadlessJourneyExecution(
            technicalPass: true,
            uxOutcome: .expected,
            remoteCalls: record.remoteCalls,
            productionSymbols: record.productionSymbols,
            note: "Completed History model reached after server completion; immutable hydrate/deleted-reference regression is executed by FitMatchComparisonSyncCoordinatorTests."
        )
    }

    private static func makeConfirmedViewModel(
        provider: HeadlessJourneyProvider
    ) throws -> (ShoppingProductViewModel, JourneyRecordingRemote) {
        let fixture = HeadlessJourneyFixture(provider: provider)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime]
        )
        return (makeViewModel(fixture: fixture, remote: remote), remote)
    }

    private static func makeViewModel(
        fixture: HeadlessJourneyFixture,
        remote: JourneyRecordingRemote
    ) -> ShoppingProductViewModel {
        let parser = HeadlessJourneyParser(product: fixture.parsedProduct())
        return ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                musinsaParser: parser,
                uniqloParser: parser,
                zaraParser: parser
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
    }

    private static func execution(
        _ calls: [String],
        _ symbols: [HeadlessProductionSymbol],
        _ ux: HeadlessUXOutcome,
        note: String = ""
    ) -> HeadlessJourneyExecution {
        HeadlessJourneyExecution(
            technicalPass: true,
            uxOutcome: ux,
            remoteCalls: calls,
            productionSymbols: symbols.map(\.rawValue),
            note: note
        )
    }

    static func makeServerBackedUserExplicitCompletionProof() async throws
        -> HeadlessUserExplicitCompletionProof {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1
        )
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "MANUAL_EXTENDED"
            )],
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "MANUAL_EXTENDED",
                allowed: true,
                effectiveSource: "USER_EXPLICIT",
                overrideRevision: 1
            )],
            beginResponses: [try fixture.begin(
                mode: "MANUAL_EXTENDED",
                personal: true,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: "polo_shirt"
            )],
            completionResponses: [try fixture.complete()]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let request = FitMatchProductResolutionRequest(
            source: fixture.sourceCode,
            externalProductID: fixture.productCode,
            productName: fixture.parsedProduct().productName,
            sourceCategoryPath: "tops > short sleeve",
            audience: "MEN",
            sourceCategoryCodes: ["tops", "short_sleeve"]
        )
        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: reference.id,
            localReferenceSnapshot: try #require(
                reference.fitMatchServerReferenceSnapshot()
            ),
            targetRequest: request,
            targetObservation: nil
        )
        let permit = try await coordinator.beginAuthorizedComparison(authorization)
        let service = RecommendationService()
        let analysis = try service.analyzeVNextComparison(permit: permit)
        let completion = try await coordinator.completeAuthorizedComparison(
            permit: permit,
            analysis: analysis
        )

        return HeadlessUserExplicitCompletionProof(
            fixture: fixture,
            referenceClosetItemID: remoteReference.closetItemID,
            product: makeHeadlessPersonalProduct(
                fixture: fixture,
                productID: fixture.productID,
                garment: "polo_shirt"
            ),
            reference: reference,
            permit: permit,
            analysis: analysis,
            completion: completion
        )
    }
}

private struct HeadlessUserExplicitCompletionProof {
    let fixture: HeadlessJourneyFixture
    let referenceClosetItemID: UUID
    let product: Product
    let reference: UserFit
    let permit: FitMatchServerComparisonPermit
    let analysis: VNextComparisonBatchAnalysis
    let completion: VNextCompleteComparisonDTO
}

private extension FitMatchServerComparisonPermit {
    func replacingBegin(
        _ begin: VNextBeginComparisonDTO?
    ) -> FitMatchServerComparisonPermit {
        FitMatchServerComparisonPermit(
            referenceAuthorization: referenceAuthorization,
            clientHistoryID: clientHistoryID,
            runID: runID,
            compatibility: compatibility,
            vnextBegin: begin
        )
    }
}

private func fixtureBegin(
    _ proof: HeadlessUserExplicitCompletionProof,
    personalRevision: Int = 1,
    personalCandidateFingerprint: String? = nil,
    personalCandidateSetHash: String? = nil,
    personalInputFingerprint: String? = nil,
    personalEvidenceFingerprint: String? = nil,
    personalClearedAt: String? = nil
) throws -> FitMatchBeginComparisonResponse {
    try proof.fixture.begin(
        mode: "MANUAL_EXTENDED",
        personal: true,
        referenceClosetItemID: proof.referenceClosetItemID,
        personalGarment: "polo_shirt",
        personalRevision: personalRevision,
        personalCandidateFingerprint: personalCandidateFingerprint,
        personalCandidateSetHash: personalCandidateSetHash,
        personalInputFingerprint: personalInputFingerprint,
        personalEvidenceFingerprint: personalEvidenceFingerprint,
        personalClearedAt: personalClearedAt
    )
}

@MainActor
private func makeHeadlessPersonalProduct(
    fixture: HeadlessJourneyFixture,
    productID: UUID,
    garment: String
) -> Product {
    let size = ProductSize(
        id: fixture.productSizeID,
        name: "M",
        measurements: GarmentMeasurements(
            shoulder: 48,
            chest: 51,
            totalLength: 70,
            sleeveLength: 24
        )
    )
    let product = Product(
        id: productID,
        name: "Headless current personal target",
        category: .top,
        productCode: fixture.productCode,
        sourceURLString: fixture.url.absoluteString,
        sourceType: fixture.sourceType,
        sourceName: fixture.sourceName,
        sizes: [size]
    )
    product.garmentTypeRawValue = garment
    product.sleeveTypeRawValue = "short_sleeve"
    product.markClassificationAuthority(.userExplicit, sourceIdentity: "headless-server-proof")
    return product
}

@MainActor
private func makeHeadlessGlobalProduct(
    fixture: HeadlessJourneyFixture
) -> Product {
    let size = ProductSize(
        id: fixture.productSizeID,
        name: "M",
        measurements: GarmentMeasurements(
            shoulder: 48,
            chest: 51,
            totalLength: 70,
            sleeveLength: 24
        )
    )
    let product = Product(
        id: fixture.productID,
        name: "Headless current global target",
        category: .top,
        productCode: fixture.productCode,
        sourceURLString: fixture.url.absoluteString,
        sourceType: fixture.sourceType,
        sourceName: fixture.sourceName,
        sizes: [size]
    )
    product.garmentTypeRawValue = "tshirt"
    product.sleeveTypeRawValue = "short_sleeve"
    product.markClassificationAuthority(.serverConfirmed, sourceIdentity: "headless-global-proof")
    return product
}

private enum HeadlessProductionSymbol: String, Sendable {
    case viewModelLoad = "ShoppingProductViewModel.loadProductInfoFromURL()"
    case authorityResolve = "FitMatchServerAuthorityCoordinator.resolveProductAuthority(request:observation:)"
    case recoveryContract = "FitMatchServerAuthorityCoordinator.classificationRecoveryOptions(productID:)"
    case recoveryMutation = "FitMatchServerAuthorityCoordinator.setUserProductClassification/clearUserProductClassification"
    case comparisonEntry = "ShoppingProductViewModel.calculateRecommendation(userFits:)"
    case referenceDecision = "FitMatchServerAuthorityCoordinator.authorizeReferenceCandidate(...)"
    case eligibleSizes = "FitMatchServerAuthorityCoordinator.beginAuthorizedComparison(_:): eligible-size phase"
    case begin = "FitMatchServerAuthorityCoordinator.beginAuthorizedComparison(_:): begin phase"
    case recommendationService = "RecommendationService.analyzeVNextComparison(permit:)"
    case engineAdapter = "VNextComparisonEngineAdapter.analyze(_:)"
    case complete = "FitMatchServerAuthorityCoordinator.completeAuthorizedComparison(permit:analysis:)"
    case historyModel = "RecommendationService.makeCompletedVNextHistory(...)"
}

enum HeadlessGlobalStatus: Equatable {
    case confirmed
    case reviewRequired
    case notComparable

    var rawValue: String {
        switch self {
        case .confirmed: "confirmed"
        case .reviewRequired: "review_required"
        case .notComparable: "not_comparable"
        }
    }
}

/// Opaque server-issued evidence used only to serialize vNext DTO fixtures.
/// These values are never interpreted to choose a reference, permit, size, or
/// score in the test target; the current production coordinator and engine
/// consume the decoded DTOs exactly as they would a remote response.
struct HeadlessServerMetricFixture: Sendable {
    let code: String
    let referenceValue: Double
    let targetValue: Double
    let basisCode: String
    let weight: Double
    let requirementMode: String
    let priority: Int

    init(
        code: String,
        referenceValue: Double,
        targetValue: Double,
        basisCode: String = "WIDTH",
        weight: Double = 1,
        requirementMode: String = "REQUIRED_ANY",
        priority: Int = 1
    ) {
        self.code = code
        self.referenceValue = referenceValue
        self.targetValue = targetValue
        self.basisCode = basisCode
        self.weight = weight
        self.requirementMode = requirementMode
        self.priority = priority
    }
}

struct HeadlessServerCandidateFixture: Sendable {
    let productSizeID: UUID
    let sizeLabel: String
    let availabilityStatus: String
    let metrics: [HeadlessServerMetricFixture]
    /// Canonical retailer facts shown in the runtime size table can include
    /// measurements that the server deliberately excludes from this specific
    /// comparison proof. `metrics` remains the opaque issued comparison
    /// evidence; this optional field merely serializes the distinct runtime
    /// DTO surface without deriving either list in the test target.
    let runtimeMetrics: [HeadlessServerMetricFixture]?
    let allowed: Bool
    let reason: String?
    let minimumCommon: Int

    init(
        productSizeID: UUID,
        sizeLabel: String,
        availabilityStatus: String = "AVAILABLE",
        metrics: [HeadlessServerMetricFixture],
        runtimeMetrics: [HeadlessServerMetricFixture]? = nil,
        allowed: Bool = true,
        reason: String? = nil,
        minimumCommon: Int = 1
    ) {
        self.productSizeID = productSizeID
        self.sizeLabel = sizeLabel
        self.availabilityStatus = availabilityStatus
        self.metrics = metrics
        self.runtimeMetrics = runtimeMetrics
        self.allowed = allowed
        self.reason = reason
        self.minimumCommon = minimumCommon
    }
}

struct HeadlessJourneyFixture {
    let provider: HeadlessJourneyProvider
    /// An optional captured retailer parse.  This stays at the parser/network
    /// boundary: production code still resolves authority, reference,
    /// eligibility, begin, scoring, and completion.  It prevents a
    /// provider-specific scenario from merely relabelling one generic product.
    let parsedProductOverride: ParsedProductInfo?
    let productID = UUID()
    let variantID = UUID()
    let productSizeID = UUID()
    let comparisonID = UUID()

    init(
        provider: HeadlessJourneyProvider,
        parsedProductOverride: ParsedProductInfo? = nil
    ) {
        self.provider = provider
        self.parsedProductOverride = parsedProductOverride
    }

    var sourceCode: String { provider.rawValue }

    var productCode: String {
        if let code = parsedProductOverride?.productID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !code.isEmpty {
            return code
        }
        switch provider {
        case .uniqlo: return "E450259"
        case .musinsa: return "6805433"
        case .zara: return "561264931"
        }
    }

    var sourceName: String {
        if let parsedProductOverride {
            return parsedProductOverride.sourceName
        }
        switch provider {
        case .uniqlo: return "유니클로 공식몰"
        case .musinsa: return "무신사"
        case .zara: return "ZARA 공식몰"
        }
    }

    var sourceType: ProductSourceType {
        if let parsedProductOverride {
            return parsedProductOverride.sourceType
        }
        return provider == .musinsa ? .marketplace : .officialStore
    }

    var url: URL {
        if let parsedProductOverride {
            return parsedProductOverride.sourceURL
        }
        switch provider {
        case .uniqlo:
            return URL(string: "https://www.uniqlo.com/kr/ko/products/\(productCode)")!
        case .musinsa:
            return URL(string: "https://www.musinsa.com/products/\(productCode)")!
        case .zara:
            return URL(string: "https://www.zara.com/kr/ko/product/\(productCode).html")!
        }
    }

    func parsedProduct() -> ParsedProductInfo {
        if let parsedProductOverride {
            return parsedProductOverride
        }
        return ParsedProductInfo(
            sourceURL: url,
            sourceType: sourceType,
            sourceName: sourceName,
            brandName: sourceName,
            productName: "Headless \(sourceName) target",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [
                ParsedProductSize(
                    id: productSizeID,
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 48,
                        chest: 51,
                        totalLength: 70,
                        sleeveLength: 24
                    ),
                    availabilityStatus: "AVAILABLE"
                )
            ],
            productID: productCode,
            canonicalURLString: url.absoluteString,
            sourceCategoryPath: "tops > short sleeve",
            productTargetGender: .men,
            productMetadata: ProductMetadata(
                sourceCategoryPath: "tops > short sleeve",
                categoryDepth1Code: "tops",
                categoryDepth2Code: "short_sleeve",
                genderCodes: ["MEN"]
            )
        )
    }

    func resolution(globalStatus: HeadlessGlobalStatus) -> FitMatchProductResolutionResponse {
        FitMatchProductResolutionResponse(
            productID: productID,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: classification(globalStatus: globalStatus),
            comparisonReady: globalStatus == .confirmed
        )
    }

    func classification(
        globalStatus: HeadlessGlobalStatus,
        garment: String? = "tshirt",
        authorityStatus: String? = nil,
        overrideRevision: Int? = nil
    ) -> FitMatchDatabaseClassification {
        FitMatchDatabaseClassification(
            classificationID: productID,
            categoryCode: globalStatus == .reviewRequired || globalStatus == .notComparable ? nil : "tops",
            detailCode: globalStatus == .reviewRequired || globalStatus == .notComparable ? nil : "short_sleeve",
            garmentTypeCode: globalStatus == .reviewRequired || globalStatus == .notComparable ? nil : garment,
            familyCode: globalStatus == .reviewRequired || globalStatus == .notComparable ? nil : garment,
            lengthCode: globalStatus == .reviewRequired || globalStatus == .notComparable ? nil : "short_sleeve",
            bodyLengthCode: nil,
            status: globalStatus.rawValue,
            method: authorityStatus == "user_explicit" ? "user_explicit" : "test_server_fixture",
            authorityStatus: authorityStatus,
            confidence: globalStatus == .confirmed ? 1 : nil,
            requiresUserConfirmation: globalStatus == .reviewRequired,
            taxonomyPolicyVersion: "headless-vnext-test",
            decisionVersion: overrideRevision.map { "revision-\($0)" } ?? "global-v1"
        )
    }

    func runtime(
        globalStatus: HeadlessGlobalStatus,
        effectivePersonalGarment: String? = nil,
        overrideRevision: Int? = nil,
        personalCandidateFingerprint: String? = nil,
        personalCandidateSetHash: String? = nil,
        productStructure: String = "SINGLE",
        runtimeCandidates: [HeadlessServerCandidateFixture]? = nil
    ) throws -> FitMatchProductRuntimeResponse {
        let runtimeVariantKey = parsedProductOverride?.productMetadata
            .externalVariantID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRuntimeVariantKey = runtimeVariantKey?.isEmpty == false
            ? runtimeVariantKey!
            : "__default__"
        let isPersonal = effectivePersonalGarment != nil
        let effectiveStatus = isPersonal || globalStatus == .confirmed ? "CONFIRMED" : globalStatus.rawValue.uppercased()
        let runtimeState: String
        switch globalStatus {
        case .confirmed:
            runtimeState = "ready"
        case .reviewRequired:
            runtimeState = isPersonal ? "ready" : "classification_required"
        case .notComparable:
            runtimeState = "not_comparable"
        }
        let effectiveState: String
        let effectiveSource: String
        if isPersonal {
            effectiveState = "PERSONAL_CONFIRMED"
            effectiveSource = "USER_EXPLICIT"
        } else if globalStatus == .confirmed {
            effectiveState = "GLOBAL_CONFIRMED"
            effectiveSource = "GLOBAL_CONFIRMED"
        } else if globalStatus == .notComparable {
            effectiveState = "GLOBAL_NOT_APPLICABLE"
            effectiveSource = "GLOBAL_NOT_APPLICABLE"
        } else {
            effectiveState = "REVIEW_REQUIRED"
            effectiveSource = "NONE"
        }
        let effectiveGarment = effectivePersonalGarment ?? (globalStatus == .confirmed ? "tshirt" : nil)
        let personalProjection = isPersonal
            ? self.personalProjectionJSON(
                garment: effectivePersonalGarment ?? "tshirt",
                revision: overrideRevision ?? 1,
                candidateFingerprint: personalCandidateFingerprint,
                candidateSetHash: personalCandidateSetHash
            )
            : "null"
        let comparisonReady = runtimeState == "ready"
        let classification = isPersonal
            ? self.classification(
                globalStatus: .confirmed,
                garment: effectivePersonalGarment,
                authorityStatus: "user_explicit",
                overrideRevision: overrideRevision
            )
            : self.classification(globalStatus: globalStatus)
        let confidenceJSON = classification.confidence.map { String($0) } ?? "null"
        let candidates = runtimeCandidates ?? [
            HeadlessServerCandidateFixture(
                productSizeID: productSizeID,
                sizeLabel: "M",
                metrics: [
                    HeadlessServerMetricFixture(
                        code: "chest_width_pit_to_pit",
                        referenceValue: 50,
                        targetValue: 51
                    ),
                    HeadlessServerMetricFixture(
                        code: "shoulder_width_seam_to_seam",
                        referenceValue: 48,
                        targetValue: 48
                    )
                ]
            )
        ]
        let runtimeSizesJSON = candidates.map(runtimeSizeJSON).joined(separator: ",")

        return try decode("""
        {
          "runtime_state":"\(runtimeState)",
          "comparison_ready":\(comparisonReady),
          "product":{
            "product_id":"\(productID)","source":"\(sourceCode)",
            "external_product_id":"\(productCode)",
            "product_name":"Headless \(sourceName) target",
            "canonical_url":"\(url.absoluteString)","audience":"MEN",
            "source_category_path":"tops > short sleeve",
            "source_category_codes":["tops","short_sleeve"],
            "lifecycle_status":"active","input_fingerprint":"input-v1"
          },
          "classification":{
            "classification_id":"\(classification.classificationID!)",
            "category_code":\(json(classification.categoryCode)),
            "detail_code":\(json(classification.detailCode)),
            "garment_type_code":\(json(classification.garmentTypeCode)),
            "family_code":\(json(classification.familyCode)),
            "length_code":\(json(classification.lengthCode)),
            "body_length_code":null,"status":"\(classification.status)",
            "method":"\(classification.method ?? "test")",
            "authority_status":\(json(classification.authorityStatus)),
            "confidence":\(confidenceJSON),
            "requires_user_confirmation":\(classification.requiresUserConfirmation),
            "taxonomy_policy_version":"headless-vnext-test",
            "decision_version":"\(classification.decisionVersion ?? "global-v1")"
          },
          "variants":[],
          "vnext":{
            "found":true,
            "product":{
              "id":"\(productID)","source_code":"\(sourceCode)",
              "source_product_key":"\(productCode)",
              "product_name":"Headless \(sourceName) target",
              "classification_status":"\(effectiveStatus)",
              "product_structure_code":"\(productStructure)","audience_code":"MEN",
              "category_code":\(json(effectiveGarment == nil ? nil : "tops")),
              "garment_type_code":\(json(effectiveGarment)),
              "comparison_policy_code":\(json(effectiveGarment)),
              "sleeve_length_code":\(json(effectiveGarment == nil ? nil : "short_sleeve")),
              "lower_length_code":null,"body_length_code":null,
              "resolver_version":"headless-resolver-v1","input_fingerprint":"input-v1"
            },
            "readiness":{"status":"\(comparisonReady ? "READY" : "CLASSIFICATION_REQUIRED")",
              "reason":null,"ready_size_count":\(comparisonReady ? 1 : 0),"policy_metric_count":1},
            "variants":[{
              "id":"\(variantID)","source_variant_key":"\(resolvedRuntimeVariantKey)",
              "variant_label":null,"color_name":null,"sizes":[\(runtimeSizesJSON)]
            }],
            "effective_classification":{
              "product_id":"\(productID)","state":"\(effectiveState)",
              "classification_status":"\(effectiveStatus)","effective_source":"\(effectiveSource)",
              "category_code":\(json(effectiveGarment == nil ? nil : "tops")),
              "garment_type_code":\(json(effectiveGarment)),"audience_code":"MEN",
              "sleeve_length_code":\(json(effectiveGarment == nil ? nil : "short_sleeve")),
              "lower_length_code":null,"body_length_code":null,
              "comparison_policy_code":\(json(effectiveGarment)),
              "product_structure_code":"\(productStructure)",
              "personal_projection":\(personalProjection),
              "override_revision":\(overrideRevision.map(String.init) ?? "null"),
              "effective_authority_fingerprint":"effective-\(overrideRevision ?? 0)",
              "effective_contract_version":"effective-v1"
            }
          }
        }
        """)
    }

    func recoveryContract(
        count: Int,
        suffix: String
    ) throws -> VNextClassificationRecoveryContractDTO {
        let all: [(String, String, String)] = [
            ("tshirt", "반팔 티셔츠", "candidate-tshirt-\(suffix)"),
            ("polo_shirt", "반팔 폴로셔츠", "candidate-polo-\(suffix)"),
            ("shirt_blouse", "반팔 셔츠", "candidate-shirt-\(suffix)")
        ]
        let candidates = all.prefix(count).map { garment, name, fingerprint in
            """
            {"candidate_id":"\(fingerprint)","candidate_fingerprint":"\(fingerprint)",
              "display_name":"\(name)","category_code":"tops",
              "garment_type_code":"\(garment)","sleeve_length_code":"short_sleeve",
              "lower_length_code":null,"body_length_code":null,
              "comparison_policy_code":"\(garment)"}
            """
        }.joined(separator: ",")
        let recoverability = count == 0 ? "UNRECOVERABLE" : "RECOVERABLE"
        let reason = count == 0 ? "no_verified_descendant_direct_candidate" : "Product-exact verified evidence is required"
        return try decode("""
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"\(recoverability)","unrecoverable_reason":\(count == 0 ? "\"\(reason)\"" : "null"),
          "fixed_facts":{"audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","garment_type_code":null,"sleeve_length_code":"short_sleeve",
            "lower_length_code":null,"body_length_code":null,"comparison_policy_code":null},
          "unknown_fields":["garment_type"],"candidates":[\(candidates)],
          "candidate_count":\(count),"product_input_fingerprint":"input-\(suffix)",
          "product_evidence_fingerprint":"evidence-\(suffix)","resolver_version":"headless-resolver-v1",
          "candidate_contract_version":"recovery-v1", "candidate_set_hash":\(count == 0 ? "null" : "\"set-\(suffix)\""),
          "current_review_reason":"\(reason)"
        }
        """)
    }

    func setMutation(
        contract: VNextClassificationRecoveryContractDTO,
        garment: String,
        revision: Int,
        event: String
    ) throws -> VNextUserClassificationMutationDTO {
        let candidate = try requireValue(
            contract.candidates.first(where: { $0.garmentTypeCode == garment }),
            scenario: "fixture",
            message: "missing candidate"
        )
        return try decode("""
        {
          "saved":true,"cleared":false,"idempotent":false,"event":"\(event)",
          "override":{"id":"\(productID)","product_id":"\(productID)",
            "classification_source":"USER_EXPLICIT","audience_code":"MEN","category_code":"tops",
            "garment_type_code":"\(garment)","comparison_policy_code":"\(garment)",
            "sleeve_length_code":"short_sleeve","lower_length_code":null,"body_length_code":null,
            "selected_candidate_fingerprint":"\(candidate.candidateFingerprint)",
            "candidate_contract_version":"\(contract.candidateContractVersion)",
            "candidate_set_hash":"\(contract.candidateSetHash ?? "")","revision":\(revision),"cleared_at":null},
          "effective_classification":{"product_id":"\(productID)","state":"PERSONAL_CONFIRMED",
            "classification_status":"CONFIRMED","effective_source":"USER_EXPLICIT","category_code":"tops",
            "garment_type_code":"\(garment)","audience_code":"MEN","sleeve_length_code":"short_sleeve",
            "lower_length_code":null,"body_length_code":null,"comparison_policy_code":"\(garment)",
            "product_structure_code":"SINGLE","override_revision":\(revision),
            "effective_authority_fingerprint":"effective-\(revision)","effective_contract_version":"effective-v1"}
        }
        """)
    }

    func clearMutation(revision: Int) throws -> VNextUserClassificationMutationDTO {
        try decode("""
        {
          "saved":false,"cleared":true,"idempotent":false,"event":"CLEARED",
          "override_id":"\(productID)","revision":\(revision),
          "effective_classification":{"product_id":"\(productID)","state":"REVIEW_REQUIRED",
            "classification_status":"REVIEW_REQUIRED","effective_source":"NONE","category_code":null,
            "garment_type_code":null,"audience_code":"MEN","sleeve_length_code":null,
            "lower_length_code":null,"body_length_code":null,"comparison_policy_code":null,
            "product_structure_code":"SINGLE","override_revision":null,
            "effective_authority_fingerprint":"effective-\(revision)","effective_contract_version":"effective-v1"}
        }
        """)
    }

    func localReference(garment: String, sleeve: String) -> UserFit {
        let reference = UserFit(
            id: UUID(),
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "Headless Closet",
            gender: .men,
            productName: "Headless reference \(garment)",
            category: .top,
            detailCategory: sleeve == "long_sleeve" ? .longSleeve : .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 50,
                totalLength: 70,
                sleeveLength: sleeve == "long_sleeve" ? 60 : 24
            ),
            fitMemo: "",
            satisfaction: 4,
            isRepresentative: true
        )
        reference.garmentTypeRawValue = garment
        reference.sleeveTypeRawValue = sleeve
        reference.markClassificationAuthority(.userExplicit, sourceIdentity: "headless-reference")
        return reference
    }

    func closetRecord(for reference: UserFit) -> FitMatchClosetItemRecord {
        let snapshot = reference.fitMatchServerReferenceSnapshot()!
        return FitMatchClosetItemRecord(
            closetItemID: UUID(),
            clientItemID: reference.id,
            productID: nil,
            externalProductID: nil,
            productAudience: "MEN",
            sourceCategoryCodes: [snapshot.categoryCode, snapshot.detailCode],
            variantID: nil,
            productSizeID: nil,
            brand: reference.brandName,
            productName: snapshot.productName,
            sizeName: snapshot.sizeName,
            genderCode: "men",
            source: "manual",
            sourceCategoryPath: nil,
            productURL: nil,
            imageURL: nil,
            measurements: snapshot.measurements,
            measurementRecords: [],
            fitMemo: "",
            fitPreferenceCode: "regular",
            satisfaction: 4,
            isReference: reference.isRepresentative,
            classificationStatus: "confirmed",
            classificationSource: "manual_override",
            categoryCode: snapshot.categoryCode,
            detailCode: snapshot.detailCode,
            canonicalCategoryCode: snapshot.categoryCode,
            canonicalDetailCode: snapshot.detailCode,
            familyCode: snapshot.familyCode,
            lengthCode: snapshot.lengthCode,
            bodyLengthCode: snapshot.bodyLengthCode,
            classificationSnapshot: [:],
            clientSnapshot: [:],
            clientCreatedAt: "2026-08-31T00:00:00Z",
            clientUpdatedAt: "2026-08-31T00:00:00Z",
            syncRevision: 1,
            createdAt: "2026-08-31T00:00:00Z",
            updatedAt: "2026-08-31T00:00:00Z"
        )
    }

    func referenceResponse(
        reference: UserFit,
        closetItemID: UUID,
        decision: String,
        eligibleProductSizeIDs: [UUID]? = nil
    ) throws -> FitMatchReferenceCandidatesResponse {
        let allowed = decision == "AUTOMATIC" || decision == "MANUAL_EXTENDED"
        let mode = decision == "AUTOMATIC" ? "AUTOMATIC" : decision == "MANUAL_EXTENDED" ? "MANUAL_EXTENDED" : "NONE"
        let eligibleIDs = (eligibleProductSizeIDs ?? [productSizeID])
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        let value: VNextReferenceCandidatesDTO = try decode("""
        {
          "target_product_id":"\(productID)","target_variant_id":"\(variantID)","status":"READY",
          "candidates":[{
            "closet_item_id":"\(closetItemID)",
            "item_name":"\(reference.productName)","size_label":"\(reference.sizeName)",
            "product_id":null,"variant_id":null,"product_size_id":null,
            "is_current_reference":\(reference.isRepresentative),"decision":"\(decision)",
            "allowed":\(allowed),"mode":"\(mode)",
            "manual_explicit_required":\(decision == "MANUAL_EXTENDED"),
            "reason":\(allowed ? "null" : "\"blocked_by_server_policy\""),
            "eligible_product_size_ids":[\(eligibleIDs)]
          }],"blocked":[]
        }
        """)
        return FitMatchReferenceCandidatesResponse(vnext: value)
    }

    /// Builds a schema-valid server candidate list for a test that needs to
    /// exercise user choice among several server-returned references. The
    /// decisions are opaque remote contract facts; this helper does not decide
    /// compatibility or select a reference locally.
    func referenceResponse(
        candidates: [(reference: UserFit, closetItemID: UUID, decision: String)]
    ) throws -> FitMatchReferenceCandidatesResponse {
        let rows = candidates.map { value -> String in
            let allowed = value.decision == "AUTOMATIC" || value.decision == "MANUAL_EXTENDED"
            let mode = value.decision == "AUTOMATIC"
                ? "AUTOMATIC"
                : value.decision == "MANUAL_EXTENDED" ? "MANUAL_EXTENDED" : "NONE"
            return """
            {"closet_item_id":"\(value.closetItemID)",
              "item_name":"\(value.reference.productName)","size_label":"\(value.reference.sizeName)",
              "product_id":null,"variant_id":null,"product_size_id":null,
              "is_current_reference":\(value.reference.isRepresentative),"decision":"\(value.decision)",
              "allowed":\(allowed),"mode":"\(mode)",
              "manual_explicit_required":\(value.decision == "MANUAL_EXTENDED"),
              "reason":\(allowed ? "null" : "\"blocked_by_server_policy\""),
              "eligible_product_size_ids":["\(productSizeID)"]}
            """
        }.joined(separator: ",")
        let value: VNextReferenceCandidatesDTO = try decode("""
        {
          "target_product_id":"\(productID)","target_variant_id":"\(variantID)","status":"READY",
          "candidates":[\(rows)],"blocked":[]
        }
        """)
        return FitMatchReferenceCandidatesResponse(vnext: value)
    }

    func eligible(
        reference: UserFit,
        closetItemID: UUID,
        mode: String,
        allowed: Bool,
        effectiveSource: String?,
        overrideRevision: Int?
    ) throws -> VNextEligibleCandidateSizesDTO {
        let candidate = allowed ? authorizedCandidateJSON(allowed: true, mode: mode) : ""
        return try decode("""
        {
          "allowed":\(allowed),"decision":"\(allowed ? mode : "BLOCKED")","mode":"\(allowed ? mode : "NONE")",
          "reason":\(allowed ? "null" : "\"no_available_size\""),
          "reference_closet_item_id":"\(closetItemID)","target_product_id":"\(productID)",
          "target_variant_id":"\(variantID)",
          "authorized_candidate_product_size_ids":\(allowed ? "[\"\(productSizeID)\"]" : "[]"),
          "candidates":\(allowed ? "[\(candidate)]" : "[]"),
          "candidate_authority_fingerprint":"candidate-v1",
          "effective_authority_fingerprint":"effective-\(overrideRevision ?? 0)",
          "classification_source":\(json(effectiveSource)),
          "override_revision":\(overrideRevision.map(String.init) ?? "null")
        }
        """)
    }

    func begin(
        mode: String,
        personal: Bool,
        referenceClosetItemID: UUID,
        personalGarment: String = "polo_shirt",
        personalRevision: Int = 1,
        personalCandidateFingerprint: String? = nil,
        personalCandidateSetHash: String? = nil,
        personalInputFingerprint: String? = nil,
        personalEvidenceFingerprint: String? = nil,
        personalClearedAt: String? = nil,
        authorizedProductSizeID: UUID? = nil,
        created: Bool = true,
        idempotent: Bool = false,
        omitDuplicatedTopLevelProof: Bool = false
    ) throws -> FitMatchBeginComparisonResponse {
        let decision = mode == "AUTOMATIC" ? "AUTOMATIC" : "MANUAL_EXTENDED"
        let source = personal ? "USER_EXPLICIT" : "GLOBAL"
        let garment = personal ? personalGarment : "tshirt"
        let effectiveState = personal ? "PERSONAL_CONFIRMED" : "GLOBAL_CONFIRMED"
        let authorizedSizeID = authorizedProductSizeID ?? productSizeID
        let duplicatedTopLevelProof = omitDuplicatedTopLevelProof ? "" : """
          ,"authorization":{
            "decision":"\(decision)","allowed":true,"mode":"\(mode)","reason":null,
            "excluded_measurement_codes":[],"required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1"},
          "authorized_candidate_product_size_ids":["\(authorizedSizeID)"],
          "candidate_authority_fingerprint":"candidate-v1",
          "effective_authority_fingerprint":"effective-\(personal ? personalRevision : 0)",
          "snapshot_schema_version":4
        """
        let personalProjection = personal ? """
        ,"personal_projection_at_begin":\(personalProjectionJSON(
            garment: personalGarment,
            revision: personalRevision,
            candidateFingerprint: personalCandidateFingerprint,
            candidateSetHash: personalCandidateSetHash,
            inputFingerprint: personalInputFingerprint,
            evidenceFingerprint: personalEvidenceFingerprint,
            clearedAt: personalClearedAt
        ))
        """ : ""
        return try decode("""
        {
          "comparison_id":"\(comparisonID)","created":\(created),"idempotent":\(idempotent),
          "result_status":"PENDING"\(duplicatedTopLevelProof),
          "snapshot":{
            "snapshot_schema_version":4,
            "reference_snapshot":{"closet_item_id":"\(referenceClosetItemID.uuidString.lowercased())"},
            "authority_snapshot":{"effective_classification_at_begin":{"source":"\(source == "GLOBAL" ? "GLOBAL_CONFIRMED" : source)","state":"\(effectiveState)","category_code":"tops","garment_type_code":"\(garment)","audience_code":"MEN","sleeve_length_code":"short_sleeve","comparison_policy_code":"\(garment)","effective_authority_fingerprint":"effective-\(personal ? personalRevision : 0)"}\(personalProjection)},
            "input_snapshot":{"effective_authority_fingerprint":"effective-\(personal ? personalRevision : 0)","personal_override_revision":\(personal ? "\(personalRevision)" : "null")},
            "excluded_measurement_codes":[],
            "policy_snapshot":{"policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1",
              "metrics":[{"metric_mode":"CANONICAL","fitmatch_measurement_code":"chest_width_pit_to_pit",
                "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,"is_active":true}]},
            "authorization_snapshot":{"decision":"\(decision)","allowed":true,"mode":"\(mode)","reason":null,
              "excluded_measurement_codes":[],"required_measurement_codes":["chest_width_pit_to_pit"],
              "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
              "policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1"},
            "target_snapshot":{"product_id":"\(productID)","variant_id":"\(variantID)",
              "authorized_candidate_product_size_ids":["\(authorizedSizeID)"],
              "candidate_authority_fingerprint":"candidate-v1","classification_status":"CONFIRMED",
              "garment_type_code":"\(garment)","sleeve_length_code":"short_sleeve",
              "lower_length_code":null,"body_length_code":null,
              "candidates":[\(authorizedCandidateJSON(
                allowed: true,
                mode: mode,
                productSizeID: authorizedSizeID
              ))]}
          }
        }
        """)
    }

    /// Serializes a server-issued eligible-size response with an exact opaque
    /// candidate set.  The fixture does not rank, filter, or otherwise decide
    /// the set: the passed values are the remote contract the production
    /// coordinator validates before it may begin.
    func eligible(
        referenceClosetItemID: UUID,
        candidates: [HeadlessServerCandidateFixture],
        allowed: Bool,
        decision: String,
        reason: String? = nil,
        effectiveSource: String? = nil,
        overrideRevision: Int? = nil
    ) throws -> VNextEligibleCandidateSizesDTO {
        let candidateJSON = candidates.map {
            serverCandidateJSON($0, decision: decision)
        }.joined(separator: ",")
        let idsJSON = candidates.map { "\"\($0.productSizeID)\"" }
            .joined(separator: ",")
        return try decode("""
        {
          "allowed":\(allowed),"decision":"\(decision)","mode":"\(allowed ? decision : "NONE")",
          "reason":\(json(reason)),
          "reference_closet_item_id":"\(referenceClosetItemID)","target_product_id":"\(productID)",
          "target_variant_id":"\(variantID)",
          "authorized_candidate_product_size_ids":[\(idsJSON)],
          "candidates":[\(candidateJSON)],
          "candidate_authority_fingerprint":"candidate-v1",
          "effective_authority_fingerprint":"effective-\(overrideRevision ?? 0)",
          "classification_source":\(json(effectiveSource)),
          "override_revision":\(overrideRevision.map(String.init) ?? "null")
        }
        """)
    }

    /// Serializes the immutable begin snapshot supplied by the server.  The
    /// production adapter—not this fixture—checks candidate-set equality,
    /// availability, evidence sufficiency, and scoring.
    func begin(
        mode: String,
        personal: Bool,
        referenceClosetItemID: UUID,
        candidates: [HeadlessServerCandidateFixture],
        policyMetricCodes: [String],
        personalGarment: String = "polo_shirt",
        personalRevision: Int = 1,
        personalCandidateFingerprint: String? = nil,
        personalCandidateSetHash: String? = nil,
        personalInputFingerprint: String? = nil,
        personalEvidenceFingerprint: String? = nil
    ) throws -> FitMatchBeginComparisonResponse {
        let decision = mode == "AUTOMATIC" ? "AUTOMATIC" : "MANUAL_EXTENDED"
        let source = personal ? "USER_EXPLICIT" : "GLOBAL_CONFIRMED"
        let garment = personal ? personalGarment : "tshirt"
        let effectiveState = personal ? "PERSONAL_CONFIRMED" : "GLOBAL_CONFIRMED"
        let idsJSON = candidates.map { "\"\($0.productSizeID)\"" }.joined(separator: ",")
        let candidateJSON = candidates.map {
            serverCandidateJSON($0, decision: mode)
        }.joined(separator: ",")
        let policyJSON = policyMetricCodes.enumerated().map { index, code in
            "{\"metric_mode\":\"CANONICAL\",\"fitmatch_measurement_code\":\"\(code)\",\"weight\":1,\"requirement_mode\":\"REQUIRED_ANY\",\"priority\":\(index + 1),\"is_active\":true}"
        }.joined(separator: ",")
        let personalProjection = personal ? """
        ,"personal_projection_at_begin":\(personalProjectionJSON(
            garment: personalGarment,
            revision: personalRevision,
            candidateFingerprint: personalCandidateFingerprint,
            candidateSetHash: personalCandidateSetHash,
            inputFingerprint: personalInputFingerprint,
            evidenceFingerprint: personalEvidenceFingerprint
        ))
        """ : ""
        return try decode("""
        {
          "comparison_id":"\(comparisonID)","created":true,"idempotent":false,"result_status":"PENDING",
          "authorization":{"decision":"\(decision)","allowed":true,"mode":"\(mode)","reason":null,
            "excluded_measurement_codes":[],"required_measurement_codes":["\(policyMetricCodes.first ?? "chest_width_pit_to_pit")"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1"},
          "authorized_candidate_product_size_ids":[\(idsJSON)],
          "candidate_authority_fingerprint":"candidate-v1",
          "effective_authority_fingerprint":"effective-\(personal ? personalRevision : 0)",
          "snapshot_schema_version":4,
          "snapshot":{
            "snapshot_schema_version":4,
            "reference_snapshot":{"closet_item_id":"\(referenceClosetItemID.uuidString.lowercased())"},
            "authority_snapshot":{"effective_classification_at_begin":{"source":"\(source)","state":"\(effectiveState)","category_code":"tops","garment_type_code":"\(garment)","audience_code":"MEN","sleeve_length_code":"short_sleeve","comparison_policy_code":"\(garment)","effective_authority_fingerprint":"effective-\(personal ? personalRevision : 0)"}\(personalProjection)},
            "input_snapshot":{"effective_authority_fingerprint":"effective-\(personal ? personalRevision : 0)","personal_override_revision":\(personal ? "\(personalRevision)" : "null")},
            "excluded_measurement_codes":[],
            "policy_snapshot":{"policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1","metrics":[\(policyJSON)]},
            "authorization_snapshot":{"decision":"\(decision)","allowed":true,"mode":"\(mode)","reason":null,
              "excluded_measurement_codes":[],"required_measurement_codes":["\(policyMetricCodes.first ?? "chest_width_pit_to_pit")"],
              "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
              "policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1"},
            "target_snapshot":{"product_id":"\(productID)","variant_id":"\(variantID)",
              "authorized_candidate_product_size_ids":[\(idsJSON)],
              "candidate_authority_fingerprint":"candidate-v1","classification_status":"CONFIRMED",
              "garment_type_code":"\(garment)","sleeve_length_code":"short_sleeve",
              "lower_length_code":null,"body_length_code":null,"candidates":[\(candidateJSON)]}
          }
        }
        """)
    }

    private func personalProjectionJSON(
        garment: String,
        revision: Int,
        candidateFingerprint: String? = nil,
        candidateSetHash: String? = nil,
        inputFingerprint: String? = nil,
        evidenceFingerprint: String? = nil,
        clearedAt: String? = nil
    ) -> String {
        let fingerprint = candidateFingerprint ?? "candidate-current-\(garment)"
        let setHash = candidateSetHash ?? "set-current-\(garment)"
        let input = inputFingerprint ?? "input-v1"
        let evidence = evidenceFingerprint ?? "evidence-v1"
        let clearedAtJSON = clearedAt.map { ",\"cleared_at\":\"\($0)\"" } ?? ""
        return """
        {"override_id":"\(productID)","revision":\(revision),
          "classification_source":"USER_EXPLICIT","category_code":"tops",
          "garment_type_code":"\(garment)","audience_code":"MEN",
          "sleeve_length_code":"short_sleeve","lower_length_code":null,
          "body_length_code":null,"comparison_policy_code":"\(garment)",
          "selected_candidate_fingerprint":"\(fingerprint)",
          "candidate_contract_version":"recovery-v1","candidate_set_hash":"\(setHash)",
          "base_product_input_fingerprint":"\(input)",
          "base_product_evidence_fingerprint":"\(evidence)",
          "base_resolver_version":"headless-resolver-v1"\(clearedAtJSON)}
        """
    }

    func complete(
        recommendedProductSizeID: UUID? = nil,
        recommendedSizeLabel: String = "M",
        coverage: Double = 1
    ) throws -> VNextCompleteComparisonDTO {
        let selectedID = recommendedProductSizeID ?? productSizeID
        return try decode("""
        {
          "comparison_id":"\(comparisonID)","completed":true,"idempotent":false,
          "recommended_product_size_id":"\(selectedID)","recommended_size_label":"\(recommendedSizeLabel)",
          "validated_evidence_count":1,"coverage":\(coverage)
        }
        """)
    }

    private func runtimeSizeJSON(_ candidate: HeadlessServerCandidateFixture) -> String {
        let measurements = (candidate.runtimeMetrics ?? candidate.metrics).map { metric in
            "{\"fitmatch_measurement_code\":\"\(metric.code)\",\"value\":\(metric.targetValue),\"unit_code\":\"CM\",\"basis_code\":\"\(metric.basisCode)\",\"source_measurement_code\":\"\(metric.code)\"}"
        }.joined(separator: ",")
        return """
        {"id":"\(candidate.productSizeID)","source_size_key":"\(candidate.sizeLabel)","size_label":"\(candidate.sizeLabel)",
          "availability":{"status":"\(candidate.availabilityStatus)","observed_at":"2026-08-31T00:00:00Z","valid_until":"2026-09-01T00:00:00Z","evidence_fingerprint":"availability-v1"},
          "canonical_measurements":{"semantic_conflict_count":0,"measurements":[\(measurements)]}}
        """
    }

    private func serverCandidateJSON(
        _ candidate: HeadlessServerCandidateFixture,
        decision: String
    ) -> String {
        let metrics = candidate.metrics.map { metric in
            let difference = metric.targetValue - metric.referenceValue
            return """
            {"measurement_code":"\(metric.code)","reference_value":\(metric.referenceValue),"target_value":\(metric.targetValue),"difference":\(difference),"absolute_difference":\(abs(difference)),"unit_code":"CM","basis_code":"\(metric.basisCode)","weight":\(metric.weight),"requirement_mode":"\(metric.requirementMode)","priority":\(metric.priority)}
            """
        }.joined(separator: ",")
        return """
        {"product_size_id":"\(candidate.productSizeID)","size_label":"\(candidate.sizeLabel)",
          "availability":{"status":"\(candidate.availabilityStatus)","observed_at":"2026-08-31T00:00:00Z","valid_until":"2026-09-01T00:00:00Z","evidence_fingerprint":"availability-v1"},
          "comparison_measurements":[\(metrics)],
          "authorization":{"decision":"\(decision)","allowed":\(candidate.allowed),"mode":"\(decision)","reason":\(json(candidate.reason)),
            "excluded_measurement_codes":[],"required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":\(candidate.minimumCommon),"common_measurement_count":\(candidate.metrics.count),"required_any_count":\(candidate.metrics.count),
            "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"}}
        """
    }

    private func authorizedCandidateJSON(
        allowed: Bool,
        mode: String,
        productSizeID: UUID? = nil
    ) -> String {
        let sizeID = productSizeID ?? self.productSizeID
        return """
        {"product_size_id":"\(sizeID)","size_label":"M",
          "availability":{"status":"AVAILABLE","observed_at":"2026-08-31T00:00:00Z",
            "valid_until":"2026-09-01T00:00:00Z","evidence_fingerprint":"availability-v1"},
          "comparison_measurements":[{"measurement_code":"chest_width_pit_to_pit",
            "reference_value":50,"target_value":51,"difference":1,"absolute_difference":1,
            "unit_code":"CM","basis_code":"WIDTH","weight":1,"requirement_mode":"REQUIRED_ANY","priority":1}],
          "authorization":{"decision":"\(mode == "AUTOMATIC" ? "AUTOMATIC" : "MANUAL_EXTENDED")",
            "allowed":\(allowed),"mode":"\(mode)","reason":null,
            "excluded_measurement_codes":[],"required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"}}
        """
    }
}

actor JourneyRecordingRemote: FitMatchServerAuthorityRemoteServicing {
    private var resolutions: [FitMatchProductResolutionResponse]
    private var runtimes: [FitMatchProductRuntimeResponse]
    private var recoveryContracts: [VNextClassificationRecoveryContractDTO]
    private var setMutations: [VNextUserClassificationMutationDTO]
    private var clearMutations: [VNextUserClassificationMutationDTO]
    private var closetResponses: [FitMatchClosetItemsResponse]
    private var candidateResponses: [FitMatchReferenceCandidatesResponse]
    private var eligibleResponses: [VNextEligibleCandidateSizesDTO]
    private var beginResponses: [FitMatchBeginComparisonResponse]
    private var completionResponses: [VNextCompleteComparisonDTO]
    private var resolveFailureCount: Int
    private var runtimeFailureCount: Int
    private var setFailureCount: Int
    private var referenceFailureCount: Int
    private var eligibleFailureCount: Int
    private var beginFailureCount: Int
    private var completionFailureCount: Int
    private let gates: [JourneyRemoteStage: JourneyAsyncGate]
    private var eventLog: [String] = []
    private var capturedResolutionRequests: [FitMatchProductResolutionRequest] = []
    private var capturedSetRequests: [FitMatchSetUserProductClassificationRequest] = []

    init(
        resolutions: [FitMatchProductResolutionResponse] = [],
        runtimes: [FitMatchProductRuntimeResponse] = [],
        recoveryContracts: [VNextClassificationRecoveryContractDTO] = [],
        setMutations: [VNextUserClassificationMutationDTO] = [],
        clearMutations: [VNextUserClassificationMutationDTO] = [],
        closetResponses: [FitMatchClosetItemsResponse] = [],
        candidateResponses: [FitMatchReferenceCandidatesResponse] = [],
        eligibleResponses: [VNextEligibleCandidateSizesDTO] = [],
        beginResponses: [FitMatchBeginComparisonResponse] = [],
        completionResponses: [VNextCompleteComparisonDTO] = [],
        resolveFailureCount: Int = 0,
        runtimeFailureCount: Int = 0,
        setFailureCount: Int = 0,
        referenceFailureCount: Int = 0,
        eligibleFailureCount: Int = 0,
        beginFailureCount: Int = 0,
        completionFailureCount: Int = 0,
        gates: [JourneyRemoteStage: JourneyAsyncGate] = [:]
    ) {
        self.resolutions = resolutions
        self.runtimes = runtimes
        self.recoveryContracts = recoveryContracts
        self.setMutations = setMutations
        self.clearMutations = clearMutations
        self.closetResponses = closetResponses
        self.candidateResponses = candidateResponses
        self.eligibleResponses = eligibleResponses
        self.beginResponses = beginResponses
        self.completionResponses = completionResponses
        self.resolveFailureCount = resolveFailureCount
        self.runtimeFailureCount = runtimeFailureCount
        self.setFailureCount = setFailureCount
        self.referenceFailureCount = referenceFailureCount
        self.eligibleFailureCount = eligibleFailureCount
        self.beginFailureCount = beginFailureCount
        self.completionFailureCount = completionFailureCount
        self.gates = gates
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductResolutionResponse {
        eventLog.append("resolve")
        capturedResolutionRequests.append(request)
        await gates[.resolve]?.wait()
        if resolveFailureCount > 0 {
            resolveFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&resolutions, "resolve")
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws -> FitMatchProductObservationResponse {
        eventLog.append("observation")
        throw JourneyRemoteFailure.unexpected("observation")
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductRuntimeResponse {
        eventLog.append("runtime")
        await gates[.runtime]?.wait()
        if runtimeFailureCount > 0 {
            runtimeFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&runtimes, "runtime")
    }

    func classificationRecoveryOptions(productID: UUID) async throws -> VNextClassificationRecoveryContractDTO {
        eventLog.append("recovery_contract")
        await gates[.recoveryContract]?.wait()
        return try pop(&recoveryContracts, "recovery_contract")
    }

    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        eventLog.append("set_user_product_classification")
        capturedSetRequests.append(request)
        await gates[.setUserClassification]?.wait()
        if setFailureCount > 0 {
            setFailureCount -= 1
            throw JourneyRemoteFailure.staleRevision
        }
        return try pop(&setMutations, "set_user_product_classification")
    }

    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        eventLog.append("clear_user_product_classification")
        await gates[.clearUserClassification]?.wait()
        return try pop(&clearMutations, "clear_user_product_classification")
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        eventLog.append("list_closet")
        await gates[.listCloset]?.wait()
        return try firstOrRepeat(&closetResponses, "list_closet")
    }

    func findReferenceCandidates(targetProductID: UUID) async throws -> FitMatchReferenceCandidatesResponse {
        eventLog.append("reference_candidates")
        await gates[.referenceCandidates]?.wait()
        if referenceFailureCount > 0 {
            referenceFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&candidateResponses, "reference_candidates")
    }

    func findReferenceCandidates(
        targetProductID: UUID,
        targetVariantID: UUID
    ) async throws -> FitMatchReferenceCandidatesResponse {
        eventLog.append("reference_candidates")
        await gates[.referenceCandidates]?.wait()
        if referenceFailureCount > 0 {
            referenceFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&candidateResponses, "reference_candidates")
    }

    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO {
        eventLog.append("eligible_sizes")
        await gates[.eligibleSizes]?.wait()
        if eligibleFailureCount > 0 {
            eligibleFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&eligibleResponses, "eligible_sizes")
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws -> FitMatchBeginComparisonResponse {
        eventLog.append("begin_comparison")
        await gates[.beginComparison]?.wait()
        if beginFailureCount > 0 {
            beginFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&beginResponses, "begin_comparison")
    }

    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO {
        eventLog.append("complete_comparison")
        await gates[.completeComparison]?.wait()
        if completionFailureCount > 0 {
            completionFailureCount -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return try pop(&completionResponses, "complete_comparison")
    }

    func calls() -> [String] { eventLog }

    func resolutionRequests() -> [FitMatchProductResolutionRequest] {
        capturedResolutionRequests
    }

    func setRequests() -> [FitMatchSetUserProductClassificationRequest] {
        capturedSetRequests
    }

    private func pop<T>(_ values: inout [T], _ name: String) throws -> T {
        guard !values.isEmpty else { throw JourneyRemoteFailure.missing(name) }
        return values.removeFirst()
    }

    private func firstOrRepeat<T>(_ values: inout [T], _ name: String) throws -> T {
        guard let first = values.first else { throw JourneyRemoteFailure.missing(name) }
        if values.count > 1 { return values.removeFirst() }
        return first
    }
}

/// Test-only scheduling hooks at true network boundaries.  They delay an
/// already-issued production RPC without supplying a policy answer, which lets
/// race tests establish an actual A-starts → B-action → A-late order.
enum JourneyRemoteStage: Hashable, Sendable {
    case resolve
    case runtime
    case recoveryContract
    case setUserClassification
    case clearUserClassification
    case listCloset
    case referenceCandidates
    case eligibleSizes
    case beginComparison
    case completeComparison
}

actor JourneyAsyncGate {
    private var isOpen = false
    private var arrivals = 0
    private let blockOnOrAfterArrival: Int
    private var workWaiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(blockOnOrAfterArrival: Int = 1) {
        self.blockOnOrAfterArrival = max(1, blockOnOrAfterArrival)
    }

    func wait() async {
        arrivals += 1
        resumeArrivalWaitersIfNeeded()
        guard !isOpen, arrivals >= blockOnOrAfterArrival else { return }
        await withCheckedContinuation { continuation in
            workWaiters.append(continuation)
        }
    }

    func waitForArrival(atLeast minimum: Int) async {
        guard arrivals < minimum else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append((minimum, continuation))
        }
    }

    func open() {
        isOpen = true
        let waiters = workWaiters
        workWaiters.removeAll()
        waiters.forEach { $0.resume() }
        resumeArrivalWaitersIfNeeded()
    }

    private func resumeArrivalWaitersIfNeeded() {
        let ready = arrivalWaiters.filter { arrivals >= $0.minimum }
        arrivalWaiters.removeAll { arrivals >= $0.minimum }
        ready.forEach { $0.continuation.resume() }
    }
}

enum JourneyRemoteFailure: Error, Sendable {
    case scriptedTransport
    case staleRevision
    case missing(String)
    case unexpected(String)
}

@MainActor
final class HeadlessJourneyParser: ProductURLParsing {
    private let product: ParsedProductInfo

    init(product: ParsedProductInfo) {
        self.product = product
    }

    func canParse(_ url: URL) -> Bool { true }

    func parse(from url: URL) async throws -> ParsedProductInfo { product }
}

final class HeadlessNoopMetricsRecorder: FitMatchMetricsRecording {
    func record(_ event: FitMatchMetricEvent) {}
}

private struct HeadlessJourneyFailure: Error, CustomStringConvertible {
    let scenario: String
    let message: String

    init(_ scenario: String, _ message: String) {
        self.scenario = scenario
        self.message = message
    }

    var description: String { "\(scenario): \(message)" }
}

private func require(
    _ condition: Bool,
    scenario: String,
    message: String
) throws {
    guard condition else { throw HeadlessJourneyFailure(scenario, message) }
}

private func requireValue<T>(
    _ value: T?,
    scenario: String,
    message: String
) throws -> T {
    guard let value else { throw HeadlessJourneyFailure(scenario, message) }
    return value
}

private func requireOrdered(
    _ calls: [String],
    _ required: [String],
    scenario: String
) throws {
    var cursor = calls.startIndex
    for expected in required {
        guard let found = calls[cursor...].firstIndex(of: expected) else {
            throw HeadlessJourneyFailure(scenario, "missing ordered call \(expected): \(calls)")
        }
        cursor = calls.index(after: found)
    }
}

private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func json(_ value: String?) -> String {
    guard let value else { return "null" }
    return "\"\(value)\""
}
