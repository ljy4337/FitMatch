import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchServerAuthorityIntegrationTests {
    @Test func changedPreviewPromotesThroughObservationAndRequeriesRuntime() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "changed")],
            observations: [fixture.observationResponse],
            runtimes: [fixture.runtime]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: fixture.request,
            observation: fixture.observationRequest
        )

        #expect(authority.status == FitMatchServerProductAuthorityStatus.confirmed)
        #expect(authority.productID == fixture.productID)
        #expect(authority.classification.familyCode == "tshirt")
        #expect(await remote.observationCallCount == 1)
        #expect(await remote.runtimeCallCount == 1)
    }

    @Test func currentPreviewWithoutPersistedAuthorityPromotesBeforeRuntime() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let unpersistedCurrent = FitMatchProductResolutionResponse(
            productID: fixture.productID,
            intakeRequestID: UUID(),
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: false,
            classification: fixture.classification,
            comparisonReady: false
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [unpersistedCurrent],
            observations: [fixture.observationResponse],
            runtimes: [fixture.runtime]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: fixture.request,
            observation: fixture.observationRequest
        )

        #expect(authority.status == FitMatchServerProductAuthorityStatus.confirmed)
        #expect(await remote.eventLog == ["resolve", "observation", "runtime"])
    }

    @Test func rejectedPromotionFailsClosedWithoutRuntimeFallback() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let rejected = FitMatchProductObservationResponse(
            observation: .init(
                observationID: fixture.observationID,
                status: "pending",
                rawMeasurementCount: 0
            ),
            processing: .init(
                observationID: fixture.observationID,
                status: "rejected",
                productID: nil
            )
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "new")],
            observations: [rejected],
            runtimes: []
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        do {
            _ = try await coordinator.resolveProductAuthority(
                request: fixture.request,
                observation: fixture.observationRequest
            )
            Issue.record("Rejected promotion must not produce local authority")
        } catch let error as FitMatchServerAuthorityError {
            #expect(
                error == FitMatchServerAuthorityError.promotionRejected("rejected")
            )
        }
        #expect(await remote.runtimeCallCount == 0)
    }

    @Test func promotionRequiredRuntimePromotesThenRequeriesPersistedAuthority() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let promotionRequired = FitMatchProductRuntimeResponse(
            runtimeState: "classification_promotion_required",
            comparisonReady: false,
            product: fixture.runtime.product,
            classification: FitMatchDatabaseClassification(
                classificationID: nil,
                categoryCode: "tops",
                detailCode: "short_sleeve",
                garmentTypeCode: "tshirt",
                familyCode: "tshirt",
                lengthCode: "short_sleeve",
                bodyLengthCode: nil,
                status: "confirmed",
                method: "category_direct",
                confidence: 1,
                requiresUserConfirmation: false,
                taxonomyPolicyVersion: "db-classifier-2026-08-26-final",
                decisionVersion: "classification-db-final-closure-2026-08-26-v1"
            ),
            variants: []
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [fixture.observationResponse],
            runtimes: [promotionRequired, fixture.runtime]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: fixture.request,
            observation: fixture.observationRequest
        )

        #expect(authority.status == FitMatchServerProductAuthorityStatus.confirmed)
        #expect(await remote.observationCallCount == 1)
        #expect(await remote.runtimeCallCount == 2)
    }

    @Test func currentMeasurementsRequiredSubmitsAvailableMeasurementsAndRequeries() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let measurementsRequired = FitMatchProductRuntimeResponse(
            runtimeState: "measurements_required",
            comparisonReady: false,
            product: fixture.runtime.product,
            classification: fixture.classification,
            variants: []
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [fixture.observationResponse],
            runtimes: [measurementsRequired, measurementsRequired]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: fixture.request,
            observation: fixture.observationRequestWithMeasurement
        )

        #expect(authority.status == FitMatchServerProductAuthorityStatus.confirmed)
        #expect(!authority.comparisonReady)
        #expect(await remote.observationCallCount == 1)
        #expect(await remote.runtimeCallCount == 2)
        #expect(await remote.eventLog == [
            "resolve", "runtime", "observation", "runtime"
        ])
    }

    @Test func measurementHydrationFailureDoesNotReturnConfirmedAuthority() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let measurementsRequired = FitMatchProductRuntimeResponse(
            runtimeState: "measurements_required",
            comparisonReady: false,
            product: fixture.runtime.product,
            classification: fixture.classification,
            variants: []
        )
        let rejected = FitMatchProductObservationResponse(
            observation: .init(
                observationID: fixture.observationID,
                status: "pending",
                rawMeasurementCount: 1
            ),
            processing: .init(
                observationID: fixture.observationID,
                status: "rejected",
                productID: nil
            )
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [rejected],
            runtimes: [measurementsRequired]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        do {
            _ = try await coordinator.resolveProductAuthority(
                request: fixture.request,
                observation: fixture.observationRequestWithMeasurement
            )
            Issue.record("Rejected measurement hydration must fail closed")
        } catch let error as FitMatchServerAuthorityError {
            #expect(
                error == FitMatchServerAuthorityError.promotionRejected("rejected")
            )
        }
        #expect(await remote.observationCallCount == 1)
        #expect(await remote.runtimeCallCount == 1)
    }

    @Test func currentReviewWithoutImprovedProviderEvidenceRemainsFailClosed() async throws {
        let fixture = AuthorityFixture.nonConfirmed(status: .reviewRequired)
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: fixture.request,
            observation: fixture.observationRequest
        )

        #expect(authority.status == .reviewRequired)
        #expect(!authority.comparisonReady)
        #expect(await remote.observationCallCount == 0)
    }

    @Test func currentReviewSubmitsNewCoherentProviderMeasurementsAndRequeries() async throws {
        let review = AuthorityFixture.nonConfirmed(status: .reviewRequired)
        let confirmed = AuthorityFixture.confirmed(
            externalProductID: review.request.externalProductID,
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let finalRuntime = FitMatchProductRuntimeResponse(
            runtimeState: "ready",
            comparisonReady: true,
            product: review.runtime.product,
            classification: confirmed.classification,
            variants: []
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [review.resolution(catalogState: "current")],
            observations: [review.observationResponse],
            runtimes: [review.runtime, finalRuntime]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: review.request,
            observation: review.observationRequestWithCoherentMeasurement
        )

        #expect(authority.status == .confirmed)
        #expect(authority.comparisonReady)
        #expect(await remote.observationCallCount == 1)
        #expect(await remote.eventLog == [
            "resolve", "runtime", "observation", "runtime"
        ])
    }

    @Test func currentNotComparableNeverPromotesMeasurementObservation() async throws {
        let fixture = AuthorityFixture.nonConfirmed(status: .notComparable)
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authority = try await coordinator.resolveProductAuthority(
            request: fixture.request,
            observation: fixture.observationRequestWithCoherentMeasurement
        )

        #expect(authority.status == .notComparable)
        #expect(!authority.comparisonReady)
        #expect(await remote.observationCallCount == 0)
    }

    @Test func goldProductsUsePersistedServerTuples() async throws {
        let gold: [(String, String, String, String)] = [
            ("E482514", "short_sleeve", "tshirt", "short_sleeve"),
            ("E454311", "base_layer_top", "base_layer_top", "short_sleeve"),
            ("E456567", "base_layer_top", "base_layer_top", "short_sleeve")
        ]

        for (externalID, detail, family, length) in gold {
            let fixture = AuthorityFixture.confirmed(
                externalProductID: externalID,
                detail: detail,
                family: family,
                length: length
            )
            let remote = ServerAuthorityRemoteStub(
                resolutions: [fixture.resolution(catalogState: "current")],
                observations: [],
                runtimes: [fixture.runtime]
            )
            let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
            let authority = try await coordinator.resolveProductAuthority(
                request: fixture.request,
                observation: fixture.observationRequest
            )

            #expect(authority.classification.categoryCode == "tops")
            #expect(authority.classification.detailCode == detail)
            #expect(authority.classification.familyCode == family)
            #expect(authority.classification.lengthCode == length)
            #expect(await remote.observationCallCount == 0)
        }
    }

    @Test func serverAutomaticCandidateIsAuthorized() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let referenceFixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-TEE",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [
                fixture.resolution(catalogState: "current"),
                referenceFixture.resolution(catalogState: "current")
            ],
            observations: [],
            runtimes: [fixture.runtime, referenceFixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: referenceFixture.productID,
                    classificationSource: "product_metadata",
                    externalProductID: referenceFixture.request.externalProductID,
                    productName: referenceFixture.request.productName
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: "automatic",
                closetItemID: closetItemID,
                automaticReady: true,
                manualReady: true,
                allowed: true
            )]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: clientItemID,
            localReferenceSnapshot: Self.localSnapshot(
                productName: referenceFixture.request.productName
            ),
            targetRequest: fixture.request,
            targetObservation: fixture.observationRequest,
            referenceRequest: referenceFixture.request,
            referenceObservation: referenceFixture.observationRequest
        )

        #expect(
            authorization.decision == FitMatchServerReferenceDecision.automatic
        )
        #expect(
            authorization.referenceAuthority
                == FitMatchServerReferenceAuthority.serverConfirmed
        )
        #expect(authorization.isAllowed)
    }

    @Test func referencePlanUsesDBAutomaticWhenLocalRepresentativeIsFalse() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-AUTO",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientID = UUID()
        let closetID = UUID()
        let localProjection = Self.localResultReference(
            id: clientID,
            name: "로컬 대표 아님",
            isRepresentative: false
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientID,
                    closetItemID: closetID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [(closetID, "AUTOMATIC", true)],
                blocked: []
            )]
        )

        let plan = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .referenceSelectionPlan(
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest,
                localClientItemIDs: [localProjection.id]
            )

        #expect(plan.automaticCandidates.map(\.clientItemID) == [clientID])
        #expect(plan.manualCandidates.isEmpty)
    }

    @Test func referencePlanKeepsRepresentativeManualOnly() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-MANUAL",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientID = UUID()
        let closetID = UUID()
        let localProjection = Self.localResultReference(
            id: clientID,
            name: "로컬 대표지만 수동",
            isRepresentative: true
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientID,
                    closetItemID: closetID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [(closetID, "MANUAL_EXTENDED", true)],
                blocked: []
            )]
        )

        let plan = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .referenceSelectionPlan(
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest,
                localClientItemIDs: [localProjection.id]
            )

        #expect(plan.automaticCandidates.isEmpty)
        #expect(plan.manualCandidates.map(\.clientItemID) == [clientID])
    }

    @Test func referencePlanKeepsBlockedRepresentativeOutOfEverySelectionSet() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-BLOCKED",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientID = UUID()
        let closetID = UUID()
        let localProjection = Self.localResultReference(
            id: clientID,
            name: "로컬 대표지만 차단",
            isRepresentative: true
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientID,
                    closetItemID: closetID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [],
                blocked: [(closetID, "BLOCKED", false)]
            )]
        )

        let plan = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .referenceSelectionPlan(
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest,
                localClientItemIDs: [localProjection.id]
            )

        #expect(plan.automaticCandidates.isEmpty)
        #expect(plan.manualCandidates.isEmpty)
        #expect(plan.allBlockedCandidates.map(\.clientItemID) == [clientID])
    }

    @Test func referencePlanKeepsMeasurementsRequiredOutsideSelectionSets() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-MEASUREMENTS",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientID = UUID()
        let closetID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientID,
                    closetItemID: closetID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [(closetID, "MEASUREMENTS_REQUIRED", false)],
                blocked: []
            )]
        )

        let plan = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .referenceSelectionPlan(
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest,
                localClientItemIDs: [clientID]
            )

        #expect(plan.automaticCandidates.isEmpty)
        #expect(plan.manualCandidates.isEmpty)
        #expect(plan.measurementRequiredCandidates.map(\.clientItemID) == [clientID])
    }

    @Test func referencePlanExposesOnlyServerManualCandidatesInServerOrder() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-MANUAL-ORDER",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let manualA = UUID()
        let manualB = UUID()
        let localOnlyC = UUID()
        let localOnlyD = UUID()
        let closetA = UUID()
        let closetB = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [
                    Self.closetRecord(clientItemID: manualA, closetItemID: closetA, productID: nil, classificationSource: "manual_override"),
                    Self.closetRecord(clientItemID: manualB, closetItemID: closetB, productID: nil, classificationSource: "manual_override")
                ]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [
                    (closetA, "MANUAL_EXTENDED", true),
                    (closetB, "MANUAL_EXTENDED", true)
                ],
                blocked: []
            )]
        )

        let plan = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .referenceSelectionPlan(
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest,
                localClientItemIDs: [manualA, manualB, localOnlyC, localOnlyD]
            )

        #expect(plan.automaticCandidates.isEmpty)
        #expect(plan.manualCandidates.map(\.clientItemID) == [manualA, manualB])
    }

    @Test func referencePlanFailsClosedWhenAutomaticProjectionIsMissing() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-MISSING-LOCAL",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let automaticClientID = UUID()
        let fallbackRepresentativeID = UUID()
        let closetID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: automaticClientID,
                    closetItemID: closetID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [(closetID, "AUTOMATIC", true)],
                blocked: []
            )]
        )

        do {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                .referenceSelectionPlan(
                    targetRequest: fixture.request,
                    targetObservation: fixture.observationRequest,
                    localClientItemIDs: [fallbackRepresentativeID]
                )
            Issue.record("Missing DB AUTOMATIC projection must not choose another local item")
        } catch let error as FitMatchServerAuthorityError {
            #expect(error == .localReferenceProjectionMissing(automaticClientID))
        }
    }

    @Test func referencePlanPreservesServerAutomaticCandidateOrder() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-PLAN-AUTO-ORDER",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let firstClientID = UUID()
        let secondClientID = UUID()
        let firstClosetID = UUID()
        let secondClosetID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [
                    Self.closetRecord(clientItemID: firstClientID, closetItemID: firstClosetID, productID: nil, classificationSource: "manual_override"),
                    Self.closetRecord(clientItemID: secondClientID, closetItemID: secondClosetID, productID: nil, classificationSource: "manual_override")
                ]
            ),
            candidateResponses: [try Self.vnextReferenceCandidateResponse(
                targetProductID: fixture.productID,
                candidates: [
                    (firstClosetID, "AUTOMATIC", true),
                    (secondClosetID, "AUTOMATIC", true)
                ],
                blocked: []
            )]
        )

        let plan = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .referenceSelectionPlan(
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest,
                localClientItemIDs: [firstClientID, secondClientID]
            )

        #expect(plan.automaticCandidates.map(\.clientItemID) == [firstClientID, secondClientID])
    }

    @Test func referenceDiscoveryDoesNotRunUntilConfirmedRuntimeIsReady() async throws {
        for state in ["sizes_required", "measurements_required"] {
            let fixture = AuthorityFixture.confirmed(
                externalProductID: "REFERENCE-PLAN-\(state)",
                detail: "short_sleeve",
                family: "tshirt",
                length: "short_sleeve"
            )
            let runtime = FitMatchProductRuntimeResponse(
                runtimeState: state,
                comparisonReady: false,
                product: fixture.runtime.product,
                classification: fixture.classification,
                variants: []
            )
            let remote = ServerAuthorityRemoteStub(
                resolutions: [fixture.resolution(catalogState: "current")],
                observations: [],
                runtimes: [runtime]
            )

            do {
                _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                    .referenceSelectionPlan(
                        targetRequest: fixture.request,
                        targetObservation: fixture.observationRequest,
                        localClientItemIDs: []
                    )
                Issue.record("\(state) must not begin reference discovery")
            } catch let error as FitMatchServerAuthorityError {
                #expect(error == .comparisonNotReady(state))
            }
            #expect(await remote.candidateCallCount == 0)
        }
    }

    @Test func beginAuthorizedComparisonPreservesPendingDirectPermitIdentities() async throws {
        let referenceItemID = UUID()
        let clientHistoryID = UUID()
        let runID = UUID()
        let authorization = try Self.beginComparisonAuthorization(
            referenceItemID: referenceItemID
        )
        let response = try Self.beginComparisonResponse(
            runID: runID,
            status: "pending",
            allowed: true,
            level: "direct"
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [],
            observations: [],
            runtimes: [],
            beginResponses: [response]
        )

        let permit = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .beginAuthorizedComparison(
                authorization,
                clientHistoryID: clientHistoryID
            )

        #expect(permit.isAllowed)
        #expect(permit.clientHistoryID == clientHistoryID)
        #expect(permit.runID == runID)
        #expect(permit.compatibility.allowed)
        #expect(permit.compatibility.level == "direct")
        #expect(await remote.beginCallCount == 1)
        #expect(await remote.beginRequests == [FitMatchBeginComparisonRequest(
            referenceItemID: referenceItemID,
            targetProductID: authorization.target.productID,
            allowExtended: false,
            clientHistoryID: clientHistoryID
        )])
    }

    @Test func beginAuthorizedComparisonRejectsServerBlock() async throws {
        let authorization = try Self.beginComparisonAuthorization()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [],
            observations: [],
            runtimes: [],
            beginResponses: [try Self.beginComparisonResponse(
                status: "blocked",
                allowed: false,
                level: "incompatible",
                reason: "compatibility_rule_denied"
            )]
        )

        do {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                .beginAuthorizedComparison(authorization)
            Issue.record("A server BLOCK must not produce a comparison permit")
        } catch let error as FitMatchServerAuthorityError {
            #expect(error == .comparisonBeginRejected("compatibility_rule_denied"))
        }
        #expect(await remote.beginCallCount == 1)
    }

    @Test func beginAuthorizedComparisonKeepsExactCandidateReasonCode() async throws {
        let authorization = try Self.beginComparisonAuthorization(
            targetVariantID: UUID()
        )
        let deniedData = Data(
            """
            {
              "allowed":false,"decision":"BLOCKED","mode":"NONE",
              "reason_code":"INCOMPATIBLE_BODY_REGION",
              "reason":"Upper-body and lower-body measurements are not comparable",
              "authorized_candidate_product_size_ids":[],"candidates":[]
            }
            """.utf8
        )
        let denied = try JSONDecoder().decode(
            VNextEligibleCandidateSizesDTO.self,
            from: deniedData
        )
        let remote = ServerAuthorityRemoteStub(
            resolutions: [],
            observations: [],
            runtimes: [],
            eligibleResponses: [denied]
        )

        do {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                .beginAuthorizedComparison(authorization)
            Issue.record("An exact server block must not produce a comparison permit")
        } catch let error as FitMatchServerAuthorityError {
            #expect(error == .comparisonAuthorizationRejected(.incompatibleBodyRegion))
        }
        #expect(await remote.beginCallCount == 0)
    }

    @Test func beginAuthorizedComparisonRejectsMalformedStatusAndCompatibility() async throws {
        let authorization = try Self.beginComparisonAuthorization()
        let malformedResponses: [
            (FitMatchBeginComparisonResponse, FitMatchServerAuthorityError)
        ] = [
            (
                try Self.beginComparisonResponse(
                    status: "pending",
                    allowed: false,
                    level: "incompatible",
                    reason: "compatibility_rule_denied"
                ),
                .comparisonBeginMalformed("allowed_status_with_denied_compatibility")
            ),
            (
                try Self.beginComparisonResponse(
                    status: "unexpected",
                    allowed: true,
                    level: "direct"
                ),
                .comparisonBeginMalformed("unknown_status_unexpected")
            )
        ]

        for (response, expectedError) in malformedResponses {
            let remote = ServerAuthorityRemoteStub(
                resolutions: [],
                observations: [],
                runtimes: [],
                beginResponses: [response]
            )

            do {
                _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                    .beginAuthorizedComparison(authorization)
                Issue.record("A malformed begin response must fail closed")
            } catch let error as FitMatchServerAuthorityError {
                #expect(error == expectedError)
            }
            #expect(await remote.beginCallCount == 1)
        }
    }

    @Test func beginAuthorizedComparisonRPCFailureProducesNoPermit() async throws {
        let authorization = try Self.beginComparisonAuthorization()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [],
            observations: [],
            runtimes: [],
            beginError: .comparisonBeginUnavailable
        )

        do {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                .beginAuthorizedComparison(authorization)
            Issue.record("An unavailable begin RPC must not produce a comparison permit")
        } catch let error as FitMatchServerAuthorityError {
            #expect(error == .comparisonBeginUnavailable)
        }
        #expect(await remote.beginCallCount == 1)
    }

    @Test func missingServerCandidateRemainsBlocked() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E454311",
            detail: "base_layer_top",
            family: "base_layer_top",
            length: "short_sleeve"
        )
        let referenceFixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-BASE-LAYER",
            detail: "base_layer_top",
            family: "base_layer_top",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [
                fixture.resolution(catalogState: "current"),
                referenceFixture.resolution(catalogState: "current")
            ],
            observations: [],
            runtimes: [fixture.runtime, referenceFixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: UUID(),
                    productID: referenceFixture.productID,
                    classificationSource: "product_metadata",
                    externalProductID: referenceFixture.request.externalProductID,
                    productName: referenceFixture.request.productName,
                    detailCode: "base_layer_top",
                    familyCode: "base_layer_top"
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: "no_compatible_garment",
                closetItemID: nil,
                automaticReady: false,
                manualReady: false,
                allowed: false
            )]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: clientItemID,
            localReferenceSnapshot: Self.localSnapshot(
                productName: referenceFixture.request.productName,
                detailCode: "base_layer_top",
                familyCode: "base_layer_top"
            ),
            targetRequest: fixture.request,
            targetObservation: fixture.observationRequest,
            referenceRequest: referenceFixture.request,
            referenceObservation: referenceFixture.observationRequest
        )

        #expect(
            authorization.decision == FitMatchServerReferenceDecision.blocked
        )
        #expect(!authorization.isAllowed)
        #expect(authorization.reason == "reference_not_authorized_by_server_evaluator")
    }

    @Test func locallyEditedReferenceCannotReuseStaleServerAuthorization() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "LOCAL-STALE-TARGET",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: "automatic",
                closetItemID: closetItemID,
                automaticReady: true,
                manualReady: true,
                allowed: true
            )]
        )

        let authorization = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .authorizeReferenceCandidate(
                referenceClientItemID: clientItemID,
                localReferenceSnapshot: Self.localSnapshot(
                    measurements: ["chest_width": 60]
                ),
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest
            )

        #expect(authorization.decision == FitMatchServerReferenceDecision.blocked)
        #expect(authorization.reason == "local_reference_snapshot_mismatch")
        #expect(await remote.candidateCallCount == 0)
    }

    @Test func staleSourcedReferenceWithoutRetailerFactsRemainsBlocked() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: UUID(),
                    productID: UUID(),
                    classificationSource: "product_metadata"
                )]
            )
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: clientItemID,
            localReferenceSnapshot: Self.localSnapshot(),
            targetRequest: fixture.request,
            targetObservation: fixture.observationRequest
        )

        #expect(authorization.decision == FitMatchServerReferenceDecision.blocked)
        #expect(authorization.reason == "reference_authority_unverified")
        #expect(await remote.candidateCallCount == 0)
    }

    @Test func sourcedReferencePromotionIsRequiredBeforeCandidateAuthorization() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let referenceFixture = AuthorityFixture.confirmed(
            externalProductID: "REFERENCE-CHANGED",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [
                fixture.resolution(catalogState: "current"),
                referenceFixture.resolution(catalogState: "changed")
            ],
            observations: [referenceFixture.observationResponse],
            runtimes: [fixture.runtime, referenceFixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: referenceFixture.productID,
                    classificationSource: "product_metadata",
                    externalProductID: referenceFixture.request.externalProductID,
                    productName: referenceFixture.request.productName
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: "automatic",
                closetItemID: closetItemID,
                automaticReady: true,
                manualReady: true,
                allowed: true
            )]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: clientItemID,
            localReferenceSnapshot: Self.localSnapshot(
                productName: referenceFixture.request.productName
            ),
            targetRequest: fixture.request,
            targetObservation: fixture.observationRequest,
            referenceRequest: referenceFixture.request,
            referenceObservation: referenceFixture.observationRequest
        )

        #expect(
            authorization.referenceAuthority
                == FitMatchServerReferenceAuthority.serverConfirmed
        )
        #expect(
            authorization.decision == FitMatchServerReferenceDecision.automatic
        )
        #expect(await remote.observationCallCount == 1)
        #expect(await remote.candidateCallCount == 1)
        #expect(await remote.eventLog == [
            "resolve", "runtime", "resolve", "observation", "runtime", "list",
            "candidates"
        ])
    }

    @Test func candidateAggregateStateMismatchFailsClosed() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "MALFORMED-CANDIDATE-STATE",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: "no_compatible_garment",
                closetItemID: closetItemID,
                automaticReady: true,
                manualReady: true,
                allowed: true
            )]
        )

        do {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                .authorizeReferenceCandidate(
                    referenceClientItemID: clientItemID,
                    localReferenceSnapshot: Self.localSnapshot(),
                    targetRequest: fixture.request,
                    targetObservation: fixture.observationRequest
                )
            Issue.record("An inconsistent aggregate state must fail closed")
        } catch let error as FitMatchServerAuthorityError {
            #expect(error == .inconsistentCandidateState(
                state: "no_compatible_garment",
                reason: "expected_automatic"
            ))
        }
    }

    @Test func candidateReadinessMismatchFailsClosed() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "MALFORMED-CANDIDATE-READINESS",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: nil,
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: "automatic",
                closetItemID: closetItemID,
                automaticReady: true,
                manualReady: false,
                allowed: false
            )]
        )

        do {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote)
                .authorizeReferenceCandidate(
                    referenceClientItemID: clientItemID,
                    localReferenceSnapshot: Self.localSnapshot(),
                    targetRequest: fixture.request,
                    targetObservation: fixture.observationRequest
                )
            Issue.record("A forged readiness flag must fail closed")
        } catch let error as FitMatchServerAuthorityError {
            #expect(error == .inconsistentCandidateState(
                state: "automatic",
                reason: "automatic_readiness_mismatch"
            ))
        }
    }

    @Test func tshirtToBaseLayerTopServerPolicyBlocks() async throws {
        let authorization = try await Self.policyAuthorization(
            targetCategory: "tops",
            targetDetail: "short_sleeve",
            targetFamily: "tshirt",
            referenceCategory: "tops",
            referenceDetail: "base_layer_top",
            referenceFamily: "base_layer_top",
            allowed: false
        )

        #expect(authorization.decision == FitMatchServerReferenceDecision.blocked)
        #expect(authorization.reason == "compatibility_rule_denied")
    }

    /// This validates only that the iOS coordinator consumes a server-issued
    /// AUTOMATIC response for a same-type candidate. Manual-cross policy is
    /// executed separately by the disposable vNext SQL contract assertions;
    /// it must never be "proved" by injecting an automatic cross-type DTO.
    @Test func sameTypeServerPolicyAllowsAutomaticResponse() async throws {
        let authorization = try await Self.policyAuthorization(
            targetCategory: "tops",
            targetDetail: "short_sleeve",
            targetFamily: "tshirt",
            referenceCategory: "tops",
            referenceDetail: "short_sleeve",
            referenceFamily: "tshirt",
            allowed: true
        )

        #expect(authorization.decision == FitMatchServerReferenceDecision.automatic)
    }

    @Test func homewearTopToBottomServerPolicyBlocks() async throws {
        let authorization = try await Self.policyAuthorization(
            targetCategory: "homewear",
            targetDetail: "homewear_bottom",
            targetFamily: "homewear_bottom",
            referenceCategory: "homewear",
            referenceDetail: "homewear_top",
            referenceFamily: "homewear_top",
            allowed: false
        )

        #expect(authorization.decision == FitMatchServerReferenceDecision.blocked)
        #expect(authorization.reason == "compatibility_rule_denied")
    }

    @Test func targetClassificationRequiredRetriesCandidateLookupOnce() async throws {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "E482514",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [
                fixture.resolution(catalogState: "current"),
                fixture.resolution(catalogState: "current")
            ],
            observations: [],
            runtimes: [fixture.runtime, fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: UUID(),
                    classificationSource: "manual_override"
                )]
            ),
            candidateResponses: [
                try Self.candidateResponse(
                    state: "target_classification_required",
                    closetItemID: nil,
                    automaticReady: false,
                    manualReady: false,
                    allowed: false
                ),
                try Self.candidateResponse(
                    state: "automatic",
                    closetItemID: closetItemID,
                    automaticReady: true,
                    manualReady: true,
                    allowed: true
                )
            ]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let authorization = try await coordinator.authorizeReferenceCandidate(
            referenceClientItemID: clientItemID,
            localReferenceSnapshot: Self.localSnapshot(),
            targetRequest: fixture.request,
            targetObservation: fixture.observationRequest
        )

        #expect(
            authorization.decision == FitMatchServerReferenceDecision.automatic
        )
        #expect(
            authorization.referenceAuthority
                == FitMatchServerReferenceAuthority.userExplicit
        )
        #expect(await remote.candidateCallCount == 2)
    }

    @Test func resultReferencePickerKeepsEveryActiveLocalClosetItemUntilSelection() {
        let currentClientID = UUID()
        let recentClientID = UUID()
        let olderClientID = UUID()
        let current = Self.localResultReference(
            id: currentClientID,
            name: "현재 기준 옷",
            isRepresentative: true
        )
        let recent = Self.localResultReference(
            id: recentClientID,
            name: "품절이어도 선택 가능한 옷",
            isRepresentative: false
        )
        let older = Self.localResultReference(
            id: olderClientID,
            name: "서버 사전검증 대상이 아닌 옷",
            isRepresentative: false
        )

        let selectable = ResultReferenceComparisonAction.fullActiveReferences(
            from: [older, current, recent],
            excluding: currentClientID
        )

        #expect(Set(selectable.map(\.id)) == [recentClientID, olderClientID])
    }

    private static func closetRecord(
        clientItemID: UUID,
        closetItemID: UUID,
        productID: UUID?,
        classificationSource: String,
        externalProductID: String = "reference-1",
        productName: String = "Reference Tee",
        categoryCode: String = "tops",
        detailCode: String = "short_sleeve",
        familyCode: String = "tshirt"
    ) -> FitMatchClosetItemRecord {
        FitMatchClosetItemRecord(
            closetItemID: closetItemID,
            clientItemID: clientItemID,
            productID: productID,
            externalProductID: externalProductID,
            productAudience: "UNISEX",
            sourceCategoryCodes: ["tops-test"],
            variantID: nil,
            productSizeID: nil,
            brand: "FitMatch",
            productName: productName,
            sizeName: "M",
            genderCode: "unisex",
            source: productID == nil ? "manual" : "uniqlo",
            sourceCategoryPath: "tops > test",
            productURL: nil,
            imageURL: nil,
            measurements: ["chest_width": 52],
            measurementRecords: [],
            fitMemo: "",
            fitPreferenceCode: "regular",
            satisfaction: 0,
            isReference: true,
            classificationStatus: "confirmed",
            classificationSource: classificationSource,
            categoryCode: categoryCode,
            detailCode: detailCode,
            canonicalCategoryCode: productID == nil ? nil : categoryCode,
            canonicalDetailCode: productID == nil ? nil : detailCode,
            familyCode: familyCode,
            lengthCode: "short_sleeve",
            bodyLengthCode: nil,
            classificationSnapshot: ["decision_version": "db-classifier-v4"],
            clientSnapshot: [:],
            clientCreatedAt: nil,
            clientUpdatedAt: nil,
            syncRevision: 1,
            createdAt: "2026-08-26T00:00:00Z",
            updatedAt: "2026-08-26T00:00:00Z"
        )
    }

    private static func resultTarget(externalProductID: String) -> Product {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 52,
                totalLength: 70,
                sleeveLength: 23
            )
        )
        let product = Product(
            name: "서버 승인 대상 상품",
            category: .top,
            productCode: externalProductID,
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/\(externalProductID)-000/00",
            metadata: ProductMetadata(
                sourceCategoryPath: "tops > short sleeve",
                genderCodes: ["UNISEX"]
            ),
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog,
            sizes: [size]
        )
        product.categoryCode = "tops"
        product.normalizedProductTypeCode = "short_sleeve"
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(.serverConfirmed)
        return product
    }

    private static func localResultReference(
        id: UUID,
        name: String,
        isRepresentative: Bool
    ) -> UserFit {
        let item = UserFit(
            id: id,
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "FitMatch",
            productName: name,
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 52,
                totalLength: 0,
                sleeveLength: 0
            ),
            fitMemo: "",
            satisfaction: 4,
            isRepresentative: isRepresentative
        )
        item.categoryCode = "tops"
        item.detailCategoryCode = "short_sleeve"
        item.garmentTypeRawValue = "tshirt"
        item.sleeveTypeRawValue = "short_sleeve"
        // This is a normal explicit Closet tuple, which the current server
        // contract represents as `manual_override`. The test is specifically
        // about the server—not this tuple—deciding which local item may enter
        // the Result picker.
        item.markClassificationAuthority(.userExplicit, sourceIdentity: "manual_override")
        return item
    }

    private static func policyAuthorization(
        targetCategory: String,
        targetDetail: String,
        targetFamily: String,
        referenceCategory: String,
        referenceDetail: String,
        referenceFamily: String,
        allowed: Bool
    ) async throws -> FitMatchServerReferenceAuthorization {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "POLICY-\(targetFamily)",
            category: targetCategory,
            detail: targetDetail,
            family: targetFamily,
            length: "long_sleeve"
        )
        let clientItemID = UUID()
        let closetItemID = UUID()
        let remote = ServerAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "current")],
            observations: [],
            runtimes: [fixture.runtime],
            closetResponse: .init(
                state: "ready",
                items: [Self.closetRecord(
                    clientItemID: clientItemID,
                    closetItemID: closetItemID,
                    productID: nil,
                    classificationSource: "manual_override",
                    categoryCode: referenceCategory,
                    detailCode: referenceDetail,
                    familyCode: referenceFamily
                )]
            ),
            candidateResponses: [try Self.candidateResponse(
                state: allowed ? "automatic" : "no_compatible_garment",
                closetItemID: closetItemID,
                automaticReady: allowed,
                manualReady: allowed,
                allowed: allowed
            )]
        )
        return try await FitMatchServerAuthorityCoordinator(remote: remote)
            .authorizeReferenceCandidate(
                referenceClientItemID: clientItemID,
                localReferenceSnapshot: Self.localSnapshot(
                    categoryCode: referenceCategory,
                    detailCode: referenceDetail,
                    familyCode: referenceFamily,
                    lengthCode: "short_sleeve"
                ),
                targetRequest: fixture.request,
                targetObservation: fixture.observationRequest
            )
    }

    private static func localSnapshot(
        productName: String = "Reference Tee",
        sizeName: String? = "M",
        categoryCode: String = "tops",
        detailCode: String = "short_sleeve",
        familyCode: String = "tshirt",
        lengthCode: String? = "short_sleeve",
        measurements: [String: Double] = ["chest_width": 52]
    ) -> FitMatchLocalReferenceSnapshot {
        FitMatchLocalReferenceSnapshot(
            productName: productName,
            sizeName: sizeName,
            categoryCode: categoryCode,
            detailCode: detailCode,
            familyCode: familyCode,
            lengthCode: lengthCode,
            bodyLengthCode: nil,
            measurements: measurements
        )
    }

    private static func vnextReferenceCandidateResponse(
        targetProductID: UUID,
        candidates: [(UUID, String, Bool)],
        blocked: [(UUID, String, Bool)],
        status: String = "READY"
    ) throws -> FitMatchReferenceCandidatesResponse {
        func encodedCandidate(_ value: (UUID, String, Bool)) -> [String: Any] {
            [
                "closet_item_id": value.0.uuidString,
                "item_name": "Server reference \(value.0.uuidString.prefix(6))",
                "size_label": "M",
                "is_current_reference": false,
                "decision": value.1,
                "allowed": value.2,
                "mode": value.1 == "MANUAL_EXTENDED" ? "MANUAL_EXTENDED" : "AUTOMATIC",
                "manual_explicit_required": value.1 == "MANUAL_EXTENDED",
                "reason_code": value.2 ? NSNull() : "NO_COMMON_MEASUREMENTS",
                "reason": value.2 ? NSNull() : "server blocked",
                "common_measurement_count": value.2 ? 3 : 0,
                "eligible_product_size_ids": []
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "target_product_id": targetProductID.uuidString,
            "target_variant_id": UUID().uuidString,
            "candidates": candidates.map(encodedCandidate),
            "blocked": blocked.map(encodedCandidate),
            "status": status
        ])
        let decoded = try JSONDecoder().decode(
            VNextReferenceCandidatesDTO.self,
            from: data
        )
        return FitMatchReferenceCandidatesResponse(vnext: decoded)
    }

    private static func candidateResponse(
        state: String,
        closetItemID: UUID?,
        automaticReady: Bool,
        manualReady: Bool,
        allowed: Bool
    ) throws -> FitMatchReferenceCandidatesResponse {
        let candidates: [[String: Any]] = closetItemID.map { id in
            [[
                "closet_item_id": id.uuidString,
                "product_name": "Reference Tee",
                "size_name": "M",
                "is_reference": true,
                "automatic_ready": automaticReady,
                "manual_ready": manualReady,
                "measurement_overlap_count": allowed ? 3 : 0,
                "automatic_compatibility": [
                    "allowed": allowed,
                    "level": allowed ? "direct" : "incompatible",
                    "reason": allowed ? NSNull() : "compatibility_rule_denied",
                    "excluded_measurements": [],
                    "minimum_common_measurements": 2
                ],
                "manual_compatibility": [
                    "allowed": allowed,
                    "level": allowed ? "direct" : "incompatible",
                    "reason": allowed ? NSNull() : "compatibility_rule_denied",
                    "excluded_measurements": [],
                    "minimum_common_measurements": 2
                ]
            ]]
        } ?? []
        let data = try JSONSerialization.data(withJSONObject: [
            "state": state,
            "automatic_count": automaticReady ? 1 : 0,
            "manual_count": manualReady ? 1 : 0,
            "structural_count": allowed ? 1 : 0,
            "candidates": candidates,
            "policy_version": "classification-comparison-v4"
        ])
        return try JSONDecoder().decode(
            FitMatchReferenceCandidatesResponse.self,
            from: data
        )
    }

    private static func beginComparisonAuthorization(
        referenceItemID: UUID = UUID(),
        targetVariantID: UUID? = nil
    ) throws -> FitMatchServerReferenceAuthorization {
        let fixture = AuthorityFixture.confirmed(
            externalProductID: "BEGIN-COMPARISON-TARGET",
            detail: "short_sleeve",
            family: "tshirt",
            length: "short_sleeve"
        )
        let candidate = try #require(candidateResponse(
            state: "automatic",
            closetItemID: referenceItemID,
            automaticReady: true,
            manualReady: true,
            allowed: true
        ).candidates.first)
        let reference = closetRecord(
            clientItemID: UUID(),
            closetItemID: referenceItemID,
            productID: UUID(),
            classificationSource: "product_metadata"
        )
        return FitMatchServerReferenceAuthorization(
            decision: .automatic,
            reason: nil,
            target: FitMatchServerProductAuthority(
                status: .confirmed,
                productID: fixture.productID,
                classification: fixture.classification,
                runtime: fixture.runtime
            ),
            reference: reference,
            referenceAuthority: .serverConfirmed,
            candidate: candidate,
            candidateState: "automatic",
            targetVariantID: targetVariantID
        )
    }

    private static func beginComparisonResponse(
        runID: UUID = UUID(),
        status: String,
        allowed: Bool,
        level: String,
        reason: String? = nil
    ) throws -> FitMatchBeginComparisonResponse {
        let data = try JSONSerialization.data(withJSONObject: [
            "run_id": runID.uuidString,
            "status": status,
            "compatibility": [
                "allowed": allowed,
                "level": level,
                "reason": reason.map { $0 as Any } ?? NSNull(),
                "excluded_measurements": [],
                "minimum_common_measurements": 2
            ]
        ])
        return try JSONDecoder().decode(FitMatchBeginComparisonResponse.self, from: data)
    }
}

private struct AuthorityFixture {
    let request: FitMatchProductResolutionRequest
    let observationRequest: FitMatchProductObservationRequest
    let productID: UUID
    let observationID: UUID
    let classification: FitMatchDatabaseClassification
    let runtime: FitMatchProductRuntimeResponse
    let observationResponse: FitMatchProductObservationResponse

    var observationRequestWithMeasurement: FitMatchProductObservationRequest {
        FitMatchProductObservationRequest(
            payload: FitMatchProductObservationPayload(
                source: observationRequest.payload.source,
                externalProductID: observationRequest.payload.externalProductID,
                productName: observationRequest.payload.productName,
                canonicalURL: observationRequest.payload.canonicalURL,
                audience: observationRequest.payload.audience,
                sourceCategoryPath: observationRequest.payload.sourceCategoryPath,
                sourceCategoryCodes: observationRequest.payload.sourceCategoryCodes,
                imageURL: observationRequest.payload.imageURL,
                observedAt: observationRequest.payload.observedAt,
                rawPayload: observationRequest.payload.rawPayload,
                structuredFacts: observationRequest.payload.structuredFacts,
                variants: [
                    FitMatchProductObservationVariant(
                        externalVariantID: "__default__",
                        variantName: nil,
                        colorCode: nil,
                        colorName: nil,
                        sizes: [
                            FitMatchProductObservationSize(
                                sizeIdentity: "M",
                                sizeLabel: "M",
                                normalizedSizeLabel: "M",
                                displayOrder: 0,
                                stockStatus: "available",
                                measurements: [
                                    FitMatchProductObservationMeasurement(
                                        measurementIdentity: "chest_width",
                                        parserCode: "size_chart",
                                        rawCode: "chest_width",
                                        rawLabel: "chest_width",
                                        rawValue: 52,
                                        rawUnit: "cm",
                                        rawRepresentation: "52",
                                        evidence: [:]
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        )
    }

    var observationRequestWithCoherentMeasurement: FitMatchProductObservationRequest {
        let measured = observationRequestWithMeasurement.payload
        var facts = measured.structuredFacts
        facts["comparison_measurement_contract"] = "single_coherent"
        facts["comparison_measurement_contract_source"] = "retailer_size_table"
        facts["comparison_measurement_contract_evidence"] = "provider_measurement_records"
        return FitMatchProductObservationRequest(
            payload: FitMatchProductObservationPayload(
                source: measured.source,
                externalProductID: measured.externalProductID,
                productName: measured.productName,
                canonicalURL: measured.canonicalURL,
                audience: measured.audience,
                sourceCategoryPath: measured.sourceCategoryPath,
                sourceCategoryCodes: measured.sourceCategoryCodes,
                imageURL: measured.imageURL,
                observedAt: measured.observedAt,
                rawPayload: measured.rawPayload,
                structuredFacts: facts,
                variants: measured.variants
            )
        )
    }

    static func confirmed(
        externalProductID: String,
        category: String = "tops",
        detail: String,
        family: String,
        length: String
    ) -> AuthorityFixture {
        make(
            externalProductID: externalProductID,
            status: .confirmed,
            category: category,
            detail: detail,
            family: family,
            length: length
        )
    }

    static func nonConfirmed(
        status: FitMatchServerProductAuthorityStatus
    ) -> AuthorityFixture {
        make(
            externalProductID: status.rawValue,
            status: status,
            category: nil,
            detail: nil,
            family: nil,
            length: nil
        )
    }

    private static func make(
        externalProductID: String,
        status: FitMatchServerProductAuthorityStatus,
        category: String?,
        detail: String?,
        family: String?,
        length: String?
    ) -> AuthorityFixture {
        let productID = UUID()
        let observationID = UUID()
        let request = FitMatchProductResolutionRequest(
            source: "uniqlo",
            externalProductID: externalProductID,
            productName: "Server Product",
            sourceCategoryPath: "tops > test",
            audience: "UNISEX",
            sourceCategoryCodes: ["tops-test"]
        )
        let observation = FitMatchProductObservationRequest(
            payload: FitMatchProductObservationPayload(
                source: request.source,
                externalProductID: request.externalProductID,
                productName: request.productName,
                canonicalURL: nil,
                audience: request.audience,
                sourceCategoryPath: request.sourceCategoryPath,
                sourceCategoryCodes: request.sourceCategoryCodes ?? [],
                imageURL: nil,
                observedAt: "2026-08-26T00:00:00Z",
                rawPayload: [:],
                structuredFacts: [:],
                variants: []
            )
        )
        let classification = FitMatchDatabaseClassification(
            classificationID: UUID(),
            categoryCode: status == .confirmed ? category : nil,
            detailCode: detail,
            garmentTypeCode: status == .confirmed ? family : nil,
            familyCode: family,
            lengthCode: length,
            bodyLengthCode: nil,
            status: status.rawValue,
            method: status == .notComparable
                ? "structured_exclusion"
                : status == .confirmed ? "canonical_product_decision" : "unknown",
            confidence: status == .confirmed ? 1 : nil,
            requiresUserConfirmation: status == .reviewRequired,
            taxonomyPolicyVersion: "db-classifier-2026-08-26-final",
            decisionVersion: "classification-db-final-closure-2026-08-26-v1"
        )
        let runtimeState: String
        switch status {
        case .confirmed: runtimeState = "ready"
        case .reviewRequired: runtimeState = "classification_required"
        case .notComparable: runtimeState = "not_comparable"
        }
        let runtime = FitMatchProductRuntimeResponse(
            runtimeState: runtimeState,
            comparisonReady: status == .confirmed,
            product: FitMatchRuntimeProduct(
                productID: productID,
                source: request.source,
                externalProductID: externalProductID,
                productName: request.productName,
                canonicalURL: nil,
                audience: request.audience,
                sourceCategoryPath: request.sourceCategoryPath,
                sourceCategoryCodes: request.sourceCategoryCodes ?? [],
                imageURL: nil,
                lifecycleStatus: "active",
                inputFingerprint: "fixture"
            ),
            classification: classification,
            variants: []
        )
        let observationResponse = FitMatchProductObservationResponse(
            observation: .init(
                observationID: observationID,
                status: "promoted",
                rawMeasurementCount: 0
            ),
            processing: .init(
                observationID: observationID,
                status: "promoted",
                productID: productID
            )
        )
        return AuthorityFixture(
            request: request,
            observationRequest: observation,
            productID: productID,
            observationID: observationID,
            classification: classification,
            runtime: runtime,
            observationResponse: observationResponse
        )
    }

    func resolution(catalogState: String) -> FitMatchProductResolutionResponse {
        FitMatchProductResolutionResponse(
            productID: catalogState == "new" ? nil : productID,
            intakeRequestID: catalogState == "current" ? nil : UUID(),
            catalogState: catalogState,
            categoryEvidenceMatches: catalogState == "current",
            authorityPersisted: catalogState == "current",
            classification: classification,
            comparisonReady: catalogState == "current"
                && classification.status == "confirmed"
        )
    }
}

private actor ServerAuthorityRemoteStub: FitMatchServerAuthorityRemoteServicing {
    private var resolutions: [FitMatchProductResolutionResponse]
    private var observations: [FitMatchProductObservationResponse]
    private var runtimes: [FitMatchProductRuntimeResponse]
    private let closetResponse: FitMatchClosetItemsResponse
    private var candidateResponses: [FitMatchReferenceCandidatesResponse]
    private var eligibleResponses: [VNextEligibleCandidateSizesDTO]
    private var beginResponses: [FitMatchBeginComparisonResponse]
    private let beginError: FitMatchServerAuthorityError?

    private(set) var observationCallCount = 0
    private(set) var runtimeCallCount = 0
    private(set) var candidateCallCount = 0
    private(set) var beginCallCount = 0
    private(set) var beginRequests: [FitMatchBeginComparisonRequest] = []
    private(set) var eventLog: [String] = []

    init(
        resolutions: [FitMatchProductResolutionResponse],
        observations: [FitMatchProductObservationResponse],
        runtimes: [FitMatchProductRuntimeResponse],
        closetResponse: FitMatchClosetItemsResponse = .init(state: "ready", items: []),
        candidateResponses: [FitMatchReferenceCandidatesResponse] = [],
        eligibleResponses: [VNextEligibleCandidateSizesDTO] = [],
        beginResponses: [FitMatchBeginComparisonResponse] = [],
        beginError: FitMatchServerAuthorityError? = nil
    ) {
        self.resolutions = resolutions
        self.observations = observations
        self.runtimes = runtimes
        self.closetResponse = closetResponse
        self.candidateResponses = candidateResponses
        self.eligibleResponses = eligibleResponses
        self.beginResponses = beginResponses
        self.beginError = beginError
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        eventLog.append("resolve")
        guard !resolutions.isEmpty else { throw StubError.missingResolution }
        return resolutions.removeFirst()
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        eventLog.append("observation")
        observationCallCount += 1
        guard !observations.isEmpty else { throw StubError.missingObservation }
        return observations.removeFirst()
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        eventLog.append("runtime")
        runtimeCallCount += 1
        guard !runtimes.isEmpty else { throw StubError.missingRuntime }
        return runtimes.removeFirst()
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        eventLog.append("list")
        return closetResponse
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        eventLog.append("candidates")
        candidateCallCount += 1
        guard !candidateResponses.isEmpty else { throw StubError.missingCandidates }
        return candidateResponses.removeFirst()
    }

    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO {
        guard !eligibleResponses.isEmpty else {
            throw StubError.missingEligibleResponse
        }
        return eligibleResponses.removeFirst()
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse {
        eventLog.append("begin")
        beginCallCount += 1
        beginRequests.append(request)
        if let beginError {
            throw beginError
        }
        guard !beginResponses.isEmpty else { throw StubError.missingBeginResponse }
        return beginResponses.removeFirst()
    }

    enum StubError: Error {
        case missingResolution
        case missingObservation
        case missingRuntime
        case missingCandidates
        case missingEligibleResponse
        case missingBeginResponse
    }
}
