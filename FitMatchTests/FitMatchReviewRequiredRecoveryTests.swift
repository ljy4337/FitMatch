import Foundation
import Testing
@testable import FitMatch

struct FitMatchReviewRequiredRecoveryTests {
    @Test func retailerRecoveryContractsAcceptOneThrough64ButReject65() {
        for version in [
            VNextClassificationRecoveryContractVersion.retailerAPIR1,
            .retailerAPIR2
        ] {
            for count in [1, 4, 64] {
                #expect(
                    makeRetailerRecoveryContract(
                        candidateCount: count,
                        contractVersion: version
                    ).isSafelyRecoverable
                )
            }
            #expect(
                !makeRetailerRecoveryContract(
                    candidateCount: 65,
                    contractVersion: version
                ).isSafelyRecoverable
            )
        }
    }

    @Test func retailerRecoveryRequiresCandidateAudienceToMatchFixedFacts() {
        #expect(
            !makeRetailerRecoveryContract(
                candidateCount: 1,
                candidateAudience: nil
            ).isSafelyRecoverable
        )
        #expect(
            !makeRetailerRecoveryContract(
                candidateCount: 1,
                candidateAudience: "WOMEN"
            ).isSafelyRecoverable
        )
    }

    @Test func recoveryContractKeepsKnownFactsAndOnlyBoundedServerCandidates() async throws {
        let fixture = try RecoveryContractFixture()
        let remote = RecoveryTransportStub(
            contract: fixture.contract,
            saved: fixture.savedMutation,
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let contract = try await coordinator.classificationRecoveryOptions(
            productID: fixture.productID
        )

        #expect(contract.isSafelyRecoverable)
        #expect(contract.fixedFacts.audienceCode == "MEN")
        #expect(contract.fixedFacts.categoryCode == "tops")
        #expect(contract.fixedFacts.sleeveLengthCode == "short_sleeve")
        #expect(contract.fixedFacts.garmentTypeCode == nil)
        #expect(contract.unknownFields == [.garmentType])
        #expect(contract.candidates.count == 3)
        #expect(Set(contract.candidates.map(\.garmentTypeCode)) == [
            "tshirt", "polo_shirt", "shirt_blouse"
        ])
    }

    @Test func completeCandidatesProjectToUniqueGarmentFirstGroups() throws {
        let productID = UUID()
        let contract = try makeGarmentFirstRecoveryContract(productID: productID)

        #expect(contract.isSafelyRecoverable)
        #expect(contract.garmentGroups.count == 2)
        #expect(contract.garmentGroups.map(\.garmentTypeCode) == [
            "knit_sweater", "cardigan"
        ])
        #expect(contract.garmentGroups.map(\.displayName) == [
            "니트/스웨터", "가디건"
        ])
        #expect(contract.presentationUnknownFields == [.garmentType])
        #expect(contract.garmentGroups.allSatisfy { group in
            group.candidates.count == 1
                && group.candidates[0].sleeveLengthCode == "long_sleeve"
                && group.differingFields.isEmpty
        })
    }

    @Test func v7RecoveryContractAcceptsWholeCandidateUnknownFieldsButKeepsGarmentFirstPresentation() async throws {
        let productID = UUID()
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )
        let fixture = try RecoveryContractFixture()
        let remote = RecoveryTransportStub(
            contract: contract,
            saved: fixture.savedMutation,
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let recovered = try await coordinator.classificationRecoveryOptions(
            productID: productID
        )

        #expect(
            recovered.supportedContractVersion == .v7ExplicitAuthority
        )
        #expect(recovered.isSafelyRecoverable)
        #expect(recovered.unknownFields == [
            .garmentType, .sleeveLength, .lowerLength
        ])
        // The v7 envelope reports cross-garment axis differences, but each
        // garment here maps to one exact candidate. The screen must not ask an
        // axis question after the user chooses either garment.
        #expect(recovered.presentationUnknownFields == [.garmentType])
        #expect(recovered.garmentGroups.allSatisfy {
            $0.differingFields.isEmpty && $0.candidates.count == 1
        })
    }

    @Test func v7RecoveryContractTreatsNilAndValueAsDifferentButAllNilAsKnown() throws {
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: UUID()
        )

        #expect(contract.isSafelyRecoverable)
        #expect(contract.unknownFields.contains(.lowerLength))
        #expect(!contract.unknownFields.contains(.bodyLength))
    }

    @Test func v7RecoveryContractRetainsAxisFollowUpOnlyWithinSelectedGarment() throws {
        let contract = try makeV7SingleGarmentAxisRecoveryContract(
            productID: UUID()
        )
        let group = try #require(contract.garmentGroups.first)

        #expect(contract.isSafelyRecoverable)
        #expect(contract.unknownFields == [.sleeveLength])
        #expect(contract.presentationUnknownFields == [.sleeveLength])
        #expect(contract.garmentGroups.count == 1)
        #expect(group.differingFields == [.sleeveLength])
    }

    @Test func v7CoordinatorSendsExactServerCandidateAndProvenance() async throws {
        let productID = UUID()
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )
        let candidate = try #require(contract.candidates.first)
        let fixture = try RecoveryContractFixture()
        let remote = RecoveryTransportStub(
            contract: contract,
            saved: try makeSavedRecoveryMutation(
                productID: productID,
                candidate: candidate
            ),
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        let issued = try await coordinator.classificationRecoveryOptions(
            productID: productID
        )
        _ = try await coordinator.setUserProductClassification(
            contract: issued,
            candidate: candidate,
            expectedRevision: 0,
            mutationID: UUID()
        )
        let request = try #require(await remote.capturedSetRequest())

        #expect(request.selectedCandidateFingerprint == candidate.candidateFingerprint)
        #expect(request.expectedCandidateSetHash == contract.candidateSetHash)
        #expect(
            request.expectedProductInputFingerprint
                == contract.productInputFingerprint
        )
        #expect(
            request.expectedProductEvidenceFingerprint
                == contract.productEvidenceFingerprint
        )
    }

    @MainActor
    @Test func v7SingleCandidateGarmentDoesNotCreateRedundantAxisQuestionOrMutation() async throws {
        let productID = UUID()
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract]
        )
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(await viewModel.beginReviewRecoveryReselection())
        let group = try #require(
            viewModel.reviewRecoveryContract?.garmentGroups.first(where: {
                $0.garmentTypeCode == "knit_sweater"
            })
        )
        let selected = try #require(viewModel.selectReviewRecoveryGarment(group))

        #expect(selected == group.candidates[0])
        #expect(selected.candidateFingerprint == "candidate-knit-v7")
        if case .choosingGarment = viewModel.reviewRecoveryState {
            // The exact candidate is ready to be explicitly confirmed; no
            // axis picker was entered because this garment has one candidate.
        } else {
            Issue.record("v7 교차-garment 축 차이가 불필요한 axis 질문을 만들었습니다.")
        }
        #expect(await remote.setCallCount() == 0)
    }

    @MainActor
    @Test func reviewRequiredLoadAcceptsV7RecoveryWithoutNetworkFailurePresentation() async throws {
        let productID = UUID()
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract],
            startsReviewRequired: true
        )
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        // REVIEW_REQUIRED is not comparison-ready, so the legacy Bool remains
        // false; the recovery contract itself must still reach its chooser.
        #expect(!(await viewModel.loadProductInfoFromURL()))
        #expect(viewModel.errorMessage == nil)
        if case .choosingGarment(let issuedContract) = viewModel.reviewRecoveryState {
            #expect(issuedContract == contract)
        } else {
            Issue.record("유효한 v7 REVIEW_REQUIRED contract가 chooser로 전환되지 않았습니다.")
        }
        #expect(await remote.setCallCount() == 0)
    }

    @Test func coordinatorRejectsUnknownVersionAndInvalidV7UnknownFieldsBeforeMutation() async throws {
        let productID = UUID()
        let fixture = try RecoveryContractFixture()
        let unsupported = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID,
            contractVersion: "fitmatch-vnext-recovery-v8-future"
        )
        let invalidUnknownFields = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID,
            unknownFields: "[\"garment_type\"]"
        )

        for (contract, expectedReason) in [
            (unsupported, "unsupported_candidate_contract_version"),
            (invalidUnknownFields, "unbounded_or_incomplete_candidate_set")
        ] {
            let remote = RecoveryTransportStub(
                contract: contract,
                saved: fixture.savedMutation,
                cleared: fixture.clearedMutation
            )
            let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
            var rejected = false
            do {
                _ = try await coordinator.classificationRecoveryOptions(
                    productID: productID
                )
            } catch let error as FitMatchServerAuthorityError {
                rejected = error == .invalidClassificationRecoveryContract(
                    expectedReason
                )
            }

            #expect(rejected)
            #expect(await remote.setCallCount() == 0)
        }
    }

    @Test func coordinatorRejectsV7BoundCountAndFixedFactViolationsBeforeMutation() async throws {
        let productID = UUID()
        let valid = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )
        let fixture = try RecoveryContractFixture()
        let extraCandidates = valid.candidates + [
            VNextClassificationRecoveryCandidateDTO(
                candidateID: "candidate-polo-v7",
                candidateFingerprint: "candidate-polo-v7",
                displayName: "폴로",
                categoryCode: "tops",
                garmentTypeCode: "polo_shirt",
                sleeveLengthCode: "short_sleeve",
                lowerLengthCode: "regular",
                bodyLengthCode: nil,
                comparisonPolicyCode: "polo_shirt"
            ),
            VNextClassificationRecoveryCandidateDTO(
                candidateID: "candidate-shirt-v7",
                candidateFingerprint: "candidate-shirt-v7",
                displayName: "셔츠/블라우스",
                categoryCode: "tops",
                garmentTypeCode: "shirt_blouse",
                sleeveLengthCode: "long_sleeve",
                lowerLengthCode: nil,
                bodyLengthCode: nil,
                comparisonPolicyCode: "shirt_blouse"
            )
        ]
        let fixedFactMismatch = VNextKnownClassificationFactsDTO(
            audienceCode: "MEN",
            productStructureCode: "SINGLE",
            categoryCode: "tops",
            garmentTypeCode: nil,
            sleeveLengthCode: "long_sleeve",
            lowerLengthCode: nil,
            bodyLengthCode: nil,
            comparisonPolicyCode: nil
        )
        let malformedContracts = [
            copiedRecoveryContract(
                valid,
                unknownFields: [],
                candidates: [],
                candidateCount: 0
            ),
            copiedRecoveryContract(valid, candidateCount: 1),
            copiedRecoveryContract(
                valid,
                candidates: extraCandidates,
                candidateCount: 4
            ),
            copiedRecoveryContract(valid, fixedFacts: fixedFactMismatch)
        ]

        for contract in malformedContracts {
            #expect(!contract.isSafelyRecoverable)
            let remote = RecoveryTransportStub(
                contract: contract,
                saved: fixture.savedMutation,
                cleared: fixture.clearedMutation
            )
            let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
            var rejected = false
            do {
                _ = try await coordinator.classificationRecoveryOptions(
                    productID: productID
                )
            } catch let error as FitMatchServerAuthorityError {
                rejected = error == .invalidClassificationRecoveryContract(
                    "unbounded_or_incomplete_candidate_set"
                )
            }
            #expect(rejected)
            #expect(await remote.setCallCount() == 0)
        }
    }

    @MainActor
    @Test func singleCandidateGarmentReturnsExactServerCandidateWithoutSaving() async throws {
        let productID = UUID()
        let contract = try makeGarmentFirstRecoveryContract(productID: productID)
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract]
        )
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(await viewModel.beginReviewRecoveryReselection())
        let sweaterGroup = try #require(
            viewModel.reviewRecoveryContract?.garmentGroups.first(where: {
                $0.garmentTypeCode == "knit_sweater"
            })
        )
        let selected = try #require(
            viewModel.selectReviewRecoveryGarment(sweaterGroup)
        )

        #expect(selected == sweaterGroup.candidates[0])
        #expect(selected.candidateFingerprint == "candidate-knit-long")
        #expect(await remote.setCallCount() == 0)
    }

    @MainActor
    @Test func oneGarmentWithTwoSleevesStartsAxisFollowUpAndResets() async throws {
        let productID = UUID()
        let contract = try makeSleeveFollowUpRecoveryContract(
            productID: productID
        )
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract]
        )
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(await viewModel.beginReviewRecoveryReselection())
        if case .choosingAxis(_, let group) = viewModel.reviewRecoveryState {
            #expect(group.garmentTypeCode == "shirt_blouse")
            #expect(group.differingFields == [.sleeveLength])
            #expect(Set(group.candidates.compactMap(\.sleeveLengthCode)) == [
                "short_sleeve", "long_sleeve"
            ])
        } else {
            Issue.record("단일 garment의 sleeve follow-up 상태가 아닙니다.")
        }
        #expect(await remote.setCallCount() == 0)

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(viewModel.reviewRecoveryState == .idle)
        #expect(await viewModel.beginReviewRecoveryReselection())
        if case .choosingAxis = viewModel.reviewRecoveryState {
            // A fresh contract request reconstructs, rather than retains, the step.
        } else {
            Issue.record("재로딩 후 새 recovery contract의 axis 단계가 없습니다.")
        }

        viewModel.returnToReviewRecoveryGarmentSelection()
        if case .choosingGarment = viewModel.reviewRecoveryState {
            // Back never writes or assembles a tuple.
        } else {
            Issue.record("상품 종류 단계로 돌아가지 못했습니다.")
        }
        let onlyGroup = try #require(
            viewModel.reviewRecoveryContract?.garmentGroups.first
        )
        #expect(viewModel.selectReviewRecoveryGarment(onlyGroup) == nil)
        if case .choosingAxis = viewModel.reviewRecoveryState {
            // Expected: two complete server candidates still need selection.
        } else {
            Issue.record("상품 종류 재선택 후 axis 단계가 복원되지 않았습니다.")
        }
        #expect(await remote.setCallCount() == 0)

        viewModel.cancelProductLoading()
        #expect(viewModel.reviewRecoveryState == .idle)
    }

    @Test func coordinatorRejectsDuplicateCandidateFingerprint() async throws {
        let fixture = try RecoveryContractFixture()
        let contract = try makeDuplicateFingerprintRecoveryContract(
            productID: fixture.productID
        )
        let remote = RecoveryTransportStub(
            contract: contract,
            saved: fixture.savedMutation,
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        var rejected = false
        do {
            _ = try await coordinator.classificationRecoveryOptions(
                productID: fixture.productID
            )
        } catch let error as FitMatchServerAuthorityError {
            rejected = error == .invalidClassificationRecoveryContract(
                "unbounded_or_incomplete_candidate_set"
            )
        }

        #expect(rejected)
        #expect(await remote.setCallCount() == 0)
    }

    @Test func coordinatorRejectsIncompleteServerCandidate() async throws {
        let fixture = try RecoveryContractFixture()
        let contract = try makeIncompleteRecoveryContract(
            productID: fixture.productID
        )
        let remote = RecoveryTransportStub(
            contract: contract,
            saved: fixture.savedMutation,
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)

        #expect(!contract.isSafelyRecoverable)
        var rejected = false
        do {
            _ = try await coordinator.classificationRecoveryOptions(
                productID: fixture.productID
            )
        } catch let error as FitMatchServerAuthorityError {
            rejected = error == .invalidClassificationRecoveryContract(
                "unbounded_or_incomplete_candidate_set"
            )
        }

        #expect(rejected)
        #expect(await remote.setCallCount() == 0)
    }

    @Test func coordinatorSendsOnlyOpaqueCandidateAndServerContractProvenance() async throws {
        let fixture = try RecoveryContractFixture()
        let remote = RecoveryTransportStub(
            contract: fixture.contract,
            saved: fixture.savedMutation,
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let contract = try await coordinator.classificationRecoveryOptions(
            productID: fixture.productID
        )
        let candidate = try #require(contract.candidates.first(where: {
            $0.garmentTypeCode == "polo_shirt"
        }))
        let mutationID = UUID()

        let result = try await coordinator.setUserProductClassification(
            contract: contract,
            candidate: candidate,
            expectedRevision: 0,
            mutationID: mutationID
        )
        let request = try #require(await remote.capturedSetRequest())

        #expect(result.effectiveClassification.isPersonalComparisonAuthority)
        #expect(request.productID == fixture.productID)
        #expect(request.selectedCandidateFingerprint == candidate.candidateFingerprint)
        #expect(request.expectedCandidateSetHash == contract.candidateSetHash)
        #expect(request.expectedProductInputFingerprint == contract.productInputFingerprint)
        #expect(request.expectedProductEvidenceFingerprint == contract.productEvidenceFingerprint)
        #expect(request.expectedRevision == 0)
        #expect(request.mutationID == mutationID)
        #expect(await remote.setCallCount() == 1)

        let clearMutationID = UUID()
        let cleared = try await coordinator.clearUserProductClassification(
            productID: fixture.productID,
            expectedRevision: 1,
            mutationID: clearMutationID
        )
        let clearRequest = try #require(await remote.capturedClearRequest())
        #expect(cleared.cleared == true)
        #expect(!cleared.effectiveClassification.isPersonalComparisonAuthority)
        #expect(clearRequest.productID == fixture.productID)
        #expect(clearRequest.expectedRevision == 1)
        #expect(clearRequest.mutationID == clearMutationID)
    }

    @Test func coordinatorRejectsClientCandidateOutsideServerContractBeforeMutation() async throws {
        let fixture = try RecoveryContractFixture()
        let remote = RecoveryTransportStub(
            contract: fixture.contract,
            saved: fixture.savedMutation,
            cleared: fixture.clearedMutation
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let forged: VNextClassificationRecoveryCandidateDTO = try decodeRecoveryJSON(
            """
            {
              "candidate_id":"forged","candidate_fingerprint":"forged",
              "display_name":"후드","category_code":"tops",
              "garment_type_code":"hoodie","sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"hoodie"
            }
            """
        )

        var rejected = false
        do {
            _ = try await coordinator.setUserProductClassification(
                contract: fixture.contract,
                candidate: forged,
                expectedRevision: 0
            )
        } catch let error as FitMatchServerAuthorityError {
            rejected = error == .invalidClassificationRecoveryContract(
                "candidate_not_in_server_contract"
            )
        }

        #expect(rejected)
        #expect(await remote.setCallCount() == 0)
    }

    @Test func snapshotV4PreservesPersonalProjectionAsImmutableJSONEvidence() throws {
        let productID = UUID()
        let variantID = UUID()
        let overrideID = UUID()
        let snapshot: VNextComparisonBeginSnapshotDTO = try decodeRecoveryJSON(
            """
            {
              "snapshot_schema_version":4,
              "target_snapshot":{
                "product_id":"\(productID)","variant_id":"\(variantID)",
                "authorized_candidate_product_size_ids":[],
                "classification_status":"CONFIRMED",
                "garment_type_code":"polo_shirt","sleeve_length_code":"short_sleeve",
                "candidates":[]
              },
              "policy_snapshot":{"metrics":[]},
              "authorization_snapshot":{
                "decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC"
              },
              "excluded_measurement_codes":[],
              "reference_snapshot":{},
              "authority_snapshot":{
                "personal_projection_at_begin":{
                  "override_id":"\(overrideID)","revision":1,
                  "classification_source":"USER_EXPLICIT",
                  "selected_candidate_fingerprint":"candidate-polo",
                  "candidate_contract_version":"recovery-v1",
                  "candidate_set_hash":"candidate-set-v1"
                },
                "effective_classification_at_begin":{
                  "source":"USER_EXPLICIT","garment_type_code":"polo_shirt"
                }
              },
              "input_snapshot":{
                "effective_authority_fingerprint":"effective-v1",
                "personal_override_revision":1
              }
            }
            """
        )

        let authority = try #require(snapshot.authoritySnapshot.objectValue)
        let personal = try #require(
            authority["personal_projection_at_begin"]?.objectValue
        )
        let effective = try #require(
            authority["effective_classification_at_begin"]?.objectValue
        )
        #expect(snapshot.snapshotSchemaVersion == 4)
        #expect(personal["override_id"]?.stringValue == overrideID.uuidString)
        #expect(personal["classification_source"]?.stringValue == "USER_EXPLICIT")
        #expect(effective["garment_type_code"]?.stringValue == "polo_shirt")
    }

    @MainActor
    @Test func activeUserExplicitReselectsWithFreshContractAndCurrentRevision() async throws {
        let productID = UUID()
        let contractV2 = try makeRecoveryContract(
            productID: productID,
            suffix: "v2"
        )
        let contractV3 = try makeRecoveryContract(
            productID: productID,
            suffix: "v3"
        )
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contractV2, contractV3, contractV3]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: coordinator
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(viewModel.hasActiveUserExplicitClassification)

        #expect(await viewModel.beginReviewRecoveryReselection())
        let latestContract = try #require(viewModel.reviewRecoveryContract)
        #expect(latestContract.candidateSetHash == contractV2.candidateSetHash)
        #expect(await remote.recoveryCallCount() == 1)
        let tshirt = try #require(latestContract.candidates.first(where: {
            $0.garmentTypeCode == "tshirt"
        }))

        #expect(await viewModel.confirmReviewRecovery(tshirt))
        let request = try #require(await remote.capturedSetRequest())
        #expect(request.expectedRevision == 1)
        #expect(request.expectedCandidateSetHash == contractV2.candidateSetHash)
        #expect(await remote.lastFeedbackEvent() == "EDITED")
        #expect(await remote.currentRevision() == 2)
        #expect(await remote.currentGarmentType() == "tshirt")
        #expect(await remote.globalClassificationStatus() == "REVIEW_REQUIRED")
        #expect(viewModel.hasActiveUserExplicitClassification)
        #expect(viewModel.reviewRecoveryState == .idle)
        if case .confirmed(let authority) = viewModel.serverAuthorityState {
            #expect(authority.classification.garmentTypeCode == "tshirt")
            #expect(authority.runtime.vnext?.effectiveClassification?.overrideRevision == 2)
        } else {
            Issue.record("재선택 후 USER_EXPLICIT confirmed authority가 없습니다.")
        }
        #expect(await remote.referenceDiscoveryCallCount() == 0)
        #expect(await remote.beginCallCount() == 0)

        // A subsequent edit must fetch a new server envelope. A candidate from
        // the prior envelope cannot be replayed into the new contract.
        #expect(await viewModel.beginReviewRecoveryReselection())
        let newerContract = try #require(viewModel.reviewRecoveryContract)
        #expect(newerContract.candidateSetHash == contractV3.candidateSetHash)
        #expect(await remote.recoveryCallCount() == 2)
        let callsBeforeStaleCandidate = await remote.setCallCount()
        #expect(!(await viewModel.confirmReviewRecovery(tshirt)))
        #expect(await remote.setCallCount() == callsBeforeStaleCandidate)
        #expect(await remote.currentGarmentType() == "tshirt")

        let freshTshirt = try #require(
            viewModel.reviewRecoveryContract?.candidates.first(where: {
                $0.garmentTypeCode == "tshirt"
            })
        )
        var staleRevisionRejected = false
        do {
            _ = try await coordinator.setUserProductClassification(
                contract: try #require(viewModel.reviewRecoveryContract),
                candidate: freshTshirt,
                expectedRevision: 1
            )
        } catch {
            staleRevisionRejected = true
        }
        #expect(staleRevisionRejected)
        #expect(await remote.currentRevision() == 2)
    }

    @MainActor
    @Test func clearInvalidatesPersonalAuthorityAndLeavesReviewFailClosed() async throws {
        let productID = UUID()
        let contract = try makeRecoveryContract(
            productID: productID,
            suffix: "clear"
        )
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: coordinator
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(viewModel.hasActiveUserExplicitClassification)
        let evidenceBefore = await remote.feedbackEventCount()

        #expect(await viewModel.clearReviewRecovery())
        let request = try #require(await remote.capturedClearRequest())
        #expect(request.expectedRevision == 1)
        #expect(!viewModel.hasActiveUserExplicitClassification)
        if case .reviewRequired = viewModel.serverAuthorityState {
            // Expected fail-closed state after the server runtime refresh.
        } else {
            Issue.record("초기화 후 Global REVIEW_REQUIRED로 복귀하지 않았습니다.")
        }
        #expect(await remote.lastFeedbackEvent() == "CLEARED")
        #expect(await remote.feedbackEventCount() == evidenceBefore + 1)
        #expect(await remote.globalClassificationStatus() == "REVIEW_REQUIRED")
        #expect(await remote.referenceDiscoveryCallCount() == 0)
        #expect(await remote.beginCallCount() == 0)
        if case .choosingGarment(let refreshedContract) =
            viewModel.reviewRecoveryState {
            #expect(refreshedContract == contract)
        } else {
            Issue.record("초기화 후 새 recovery contract로 재구성되지 않았습니다.")
        }
    }

    @MainActor
    @Test func reviewRecoveryOptionsPresentContractAndNetworkFailuresDifferently() async throws {
        let productID = UUID()
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )

        let contractRemote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract],
            recoveryFailure: .invalidContract,
            startsReviewRequired: true
        )
        let contractViewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: contractRemote)
        )

        #expect(!(await contractViewModel.loadProductInfoFromURL()))
        #expect(
            contractViewModel.errorMessage
                == "상품 분류 선택지를 현재 처리할 수 없습니다. 잠시 후 다시 시도하거나 앱을 업데이트해 주세요."
        )
        #expect(await contractRemote.setCallCount() == 0)

        let malformedRemote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract],
            recoveryFailure: .malformedResponse,
            startsReviewRequired: true
        )
        let malformedViewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: malformedRemote)
        )

        #expect(!(await malformedViewModel.loadProductInfoFromURL()))
        #expect(
            malformedViewModel.errorMessage
                == "상품 분류 선택지를 현재 처리할 수 없습니다. 잠시 후 다시 시도하거나 앱을 업데이트해 주세요."
        )
        #expect(await malformedRemote.setCallCount() == 0)

        let networkRemote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract],
            recoveryFailure: .network,
            startsReviewRequired: true
        )
        let networkViewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: networkRemote)
        )

        #expect(!(await networkViewModel.loadProductInfoFromURL()))
        #expect(
            networkViewModel.errorMessage
                == "상품 분류 선택지를 확인하지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        )
        #expect(await networkRemote.setCallCount() == 0)

        let cancelledRemote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract],
            recoveryFailure: .cancelled,
            startsReviewRequired: true
        )
        let cancelledViewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: cancelledRemote)
        )

        #expect(!(await cancelledViewModel.loadProductInfoFromURL()))
        #expect(cancelledViewModel.errorMessage == nil)
        #expect(await cancelledRemote.setCallCount() == 0)
    }

    @MainActor
    @Test func reviewRecoverySaveKeepsTransportFailureDistinctAndRefreshesSelection() async throws {
        let productID = UUID()
        let contract = try makeV7CrossGarmentAxisRecoveryContract(
            productID: productID
        )
        let remote = try RecoveryLifecycleTransportStub(
            productID: productID,
            contracts: [contract],
            setFailure: .network
        )
        let viewModel = makeRecoveryLifecycleViewModel(
            productID: productID,
            coordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(await viewModel.beginReviewRecoveryReselection())
        let group = try #require(
            viewModel.reviewRecoveryContract?.garmentGroups.first(where: {
                $0.garmentTypeCode == "knit_sweater"
            })
        )
        let candidate = try #require(viewModel.selectReviewRecoveryGarment(group))

        #expect(!(await viewModel.confirmReviewRecovery(candidate)))
        #expect(
            viewModel.errorMessage
                == "상품 분류 선택을 저장하지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        )
        #expect(await remote.setCallCount() == 1)
        #expect(viewModel.reviewRecoveryContract != nil)
    }
}

private func makeRetailerRecoveryContract(
    candidateCount: Int,
    candidateAudience: String? = "MEN",
    contractVersion: VNextClassificationRecoveryContractVersion = .retailerAPIR1
) -> VNextClassificationRecoveryContractDTO {
    let candidates = (0..<candidateCount).map { index in
        VNextClassificationRecoveryCandidateDTO(
            candidateID: "retailer-candidate-\(index)",
            candidateFingerprint: "retailer-candidate-\(index)",
            displayName: "후보 \(index)",
            audienceCode: candidateAudience,
            categoryCode: "tops",
            garmentTypeCode: "retailer-garment-\(index)",
            sleeveLengthCode: nil,
            lowerLengthCode: nil,
            bodyLengthCode: nil,
            comparisonPolicyCode: "retailer-policy-\(index)"
        )
    }
    return VNextClassificationRecoveryContractDTO(
        productID: UUID(),
        globalStatus: "REVIEW_REQUIRED",
        recoverability: .recoverable,
        unrecoverableReason: nil,
        fixedFacts: VNextKnownClassificationFactsDTO(
            audienceCode: "MEN",
            productStructureCode: "SINGLE",
            categoryCode: "tops",
            garmentTypeCode: nil,
            sleeveLengthCode: nil,
            lowerLengthCode: nil,
            bodyLengthCode: nil,
            comparisonPolicyCode: nil
        ),
        unknownFields: candidateCount > 1 ? [.garmentType] : [],
        candidates: candidates,
        candidateCount: candidateCount,
        productInputFingerprint: "retailer-input",
        productEvidenceFingerprint: "retailer-evidence",
        resolverVersion: "retailer-resolver",
        candidateContractVersion: contractVersion.rawValue,
        candidateSetHash: "retailer-candidate-set",
        currentReviewReason: "retailer evidence needs explicit selection"
    )
}

private struct RecoveryContractFixture {
    let productID: UUID
    let overrideID: UUID
    let contract: VNextClassificationRecoveryContractDTO
    let savedMutation: VNextUserClassificationMutationDTO
    let clearedMutation: VNextUserClassificationMutationDTO

    init() throws {
        let productID = UUID()
        let overrideID = UUID()
        self.productID = productID
        self.overrideID = overrideID
        contract = try decodeRecoveryJSON(
            """
            {
              "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
              "recoverability":"RECOVERABLE","unrecoverable_reason":null,
              "fixed_facts":{
                "audience_code":"MEN","product_structure_code":"SINGLE",
                "category_code":"tops","sleeve_length_code":"short_sleeve"
              },
              "unknown_fields":["garment_type"],
              "candidates":[
                {
                  "candidate_id":"candidate-tshirt","candidate_fingerprint":"candidate-tshirt",
                  "display_name":"티셔츠","category_code":"tops",
                  "garment_type_code":"tshirt","sleeve_length_code":"short_sleeve",
                  "comparison_policy_code":"tshirt"
                },
                {
                  "candidate_id":"candidate-polo","candidate_fingerprint":"candidate-polo",
                  "display_name":"폴로","category_code":"tops",
                  "garment_type_code":"polo_shirt","sleeve_length_code":"short_sleeve",
                  "comparison_policy_code":"polo_shirt"
                },
                {
                  "candidate_id":"candidate-shirt","candidate_fingerprint":"candidate-shirt",
                  "display_name":"셔츠","category_code":"tops",
                  "garment_type_code":"shirt_blouse","sleeve_length_code":"short_sleeve",
                  "comparison_policy_code":"shirt_blouse"
                }
              ],
              "candidate_count":3,"product_input_fingerprint":"input-v1",
              "product_evidence_fingerprint":"evidence-v1","resolver_version":"resolver-v2",
              "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
              "candidate_set_hash":"set-v1",
              "current_review_reason":"Product-exact verified evidence is required"
            }
            """
        )
        savedMutation = try decodeRecoveryJSON(
            """
            {
              "saved":true,"idempotent":false,"event":"SELECTED",
              "override":{
                "id":"\(overrideID)","product_id":"\(productID)",
                "classification_source":"USER_EXPLICIT","audience_code":"MEN",
                "category_code":"tops","garment_type_code":"polo_shirt",
                "comparison_policy_code":"polo_shirt","sleeve_length_code":"short_sleeve",
                "selected_candidate_fingerprint":"candidate-polo",
                "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
                "candidate_set_hash":"set-v1",
                "revision":1,"cleared_at":null
              },
              "effective_classification":{
                "product_id":"\(productID)","state":"PERSONAL_CONFIRMED",
                "classification_status":"CONFIRMED","effective_source":"USER_EXPLICIT",
                "category_code":"tops","garment_type_code":"polo_shirt",
                "audience_code":"MEN","sleeve_length_code":"short_sleeve",
                "comparison_policy_code":"polo_shirt","product_structure_code":"SINGLE",
                "override_revision":1,"effective_authority_fingerprint":"effective-v1",
                "effective_contract_version":"effective-v1"
              }
            }
            """
        )
        clearedMutation = try decodeRecoveryJSON(
            """
            {
              "cleared":true,"idempotent":false,"override_id":"\(overrideID)",
              "revision":2,
              "effective_classification":{
                "product_id":"\(productID)","state":"REVIEW_REQUIRED",
                "classification_status":"REVIEW_REQUIRED","effective_source":"NONE",
                "audience_code":"MEN","product_structure_code":"SINGLE",
                "effective_authority_fingerprint":"effective-v2",
                "effective_contract_version":"effective-v1"
              }
            }
            """
        )
    }
}

private actor RecoveryTransportStub: FitMatchServerAuthorityRemoteServicing {
    private let contract: VNextClassificationRecoveryContractDTO
    private let saved: VNextUserClassificationMutationDTO
    private let cleared: VNextUserClassificationMutationDTO
    private var setRequests: [FitMatchSetUserProductClassificationRequest] = []
    private var clearRequests: [FitMatchClearUserProductClassificationRequest] = []

    init(
        contract: VNextClassificationRecoveryContractDTO,
        saved: VNextUserClassificationMutationDTO,
        cleared: VNextUserClassificationMutationDTO
    ) {
        self.contract = contract
        self.saved = saved
        self.cleared = cleared
    }

    func classificationRecoveryOptions(productID: UUID) async throws
        -> VNextClassificationRecoveryContractDTO {
        contract
    }

    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        setRequests.append(request)
        return saved
    }

    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        clearRequests.append(request)
        return cleared
    }

    func capturedSetRequest() -> FitMatchSetUserProductClassificationRequest? {
        setRequests.last
    }

    func capturedClearRequest() -> FitMatchClearUserProductClassificationRequest? {
        clearRequests.last
    }

    func setCallCount() -> Int { setRequests.count }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse { throw StubError.unexpected }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse { throw StubError.unexpected }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse { throw StubError.unexpected }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        .init(state: "ready", items: [])
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse { throw StubError.unexpected }

    private enum StubError: Error { case unexpected }
}

@MainActor
private func makeRecoveryLifecycleViewModel(
    productID: UUID,
    coordinator: FitMatchServerAuthorityCoordinator
) -> ShoppingProductViewModel {
    let product = ParsedProductInfo(
        sourceURL: URL(string: "https://www.musinsa.com/products/recovery-patch")!,
        sourceType: .marketplace,
        sourceName: "무신사",
        brandName: "Recovery Test",
        productName: "Recovery Test Product",
        category: .top,
        detailCategory: .shortSleeve,
        sizes: [],
        productID: "recovery-patch",
        sourceCategoryPath: "상의 > 반소매",
        productTargetGender: .men,
        productMetadata: ProductMetadata(
            sourceCategoryPath: "상의 > 반소매",
            categoryDepth1Code: "001",
            categoryDepth2Code: "001001"
        )
    )
    let parser = RecoveryLifecycleParserStub(product: product)
    return ShoppingProductViewModel(
        initialURL: product.sourceURL.absoluteString,
        parserService: ProductURLParserService(
            musinsaParser: parser,
            uniqloParser: parser
        ),
        metricsRecorder: RecoveryLifecycleNoopMetricsRecorder(),
        serverAuthorityCoordinator: coordinator
    )
}

private func makeRecoveryContract(
    productID: UUID,
    suffix: String
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","sleeve_length_code":"short_sleeve"
          },
          "unknown_fields":["garment_type"],
          "candidates":[
            {
              "candidate_id":"candidate-tshirt-\(suffix)",
              "candidate_fingerprint":"candidate-tshirt-\(suffix)",
              "display_name":"티셔츠","category_code":"tops",
              "garment_type_code":"tshirt","sleeve_length_code":"short_sleeve",
              "comparison_policy_code":"tshirt"
            },
            {
              "candidate_id":"candidate-polo-\(suffix)",
              "candidate_fingerprint":"candidate-polo-\(suffix)",
              "display_name":"폴로","category_code":"tops",
              "garment_type_code":"polo_shirt","sleeve_length_code":"short_sleeve",
              "comparison_policy_code":"polo_shirt"
            }
          ],
          "candidate_count":2,
          "product_input_fingerprint":"input-\(suffix)",
          "product_evidence_fingerprint":"evidence-\(suffix)",
          "resolver_version":"resolver-v2",
          "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
          "candidate_set_hash":"set-\(suffix)",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

private func makeGarmentFirstRecoveryContract(
    productID: UUID
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","sleeve_length_code":"long_sleeve"
          },
          "unknown_fields":["garment_type"],
          "candidates":[
            {
              "candidate_id":"candidate-knit-long",
              "candidate_fingerprint":"candidate-knit-long",
              "display_name":"니트/스웨터","category_code":"tops",
              "garment_type_code":"knit_sweater",
              "sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"knit_sweater"
            },
            {
              "candidate_id":"candidate-cardigan-long",
              "candidate_fingerprint":"candidate-cardigan-long",
              "display_name":"가디건","category_code":"tops",
              "garment_type_code":"cardigan",
              "sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"cardigan"
            }
          ],
          "candidate_count":2,"product_input_fingerprint":"input-v6",
          "product_evidence_fingerprint":"evidence-v6",
          "resolver_version":"resolver-v6",
          "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
          "candidate_set_hash":"set-garment-v6",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

private func makeSleeveFollowUpRecoveryContract(
    productID: UUID
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","garment_type_code":"shirt_blouse",
            "comparison_policy_code":"shirt_blouse"
          },
          "unknown_fields":["sleeve_length"],
          "candidates":[
            {
              "candidate_id":"candidate-shirt-short",
              "candidate_fingerprint":"candidate-shirt-short",
              "display_name":"셔츠/블라우스","category_code":"tops",
              "garment_type_code":"shirt_blouse",
              "sleeve_length_code":"short_sleeve",
              "comparison_policy_code":"shirt_blouse"
            },
            {
              "candidate_id":"candidate-shirt-long",
              "candidate_fingerprint":"candidate-shirt-long",
              "display_name":"셔츠/블라우스","category_code":"tops",
              "garment_type_code":"shirt_blouse",
              "sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"shirt_blouse"
            }
          ],
          "candidate_count":2,"product_input_fingerprint":"input-axis-v6",
          "product_evidence_fingerprint":"evidence-axis-v6",
          "resolver_version":"resolver-v6",
          "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
          "candidate_set_hash":"set-axis-v6",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

private func makeV7CrossGarmentAxisRecoveryContract(
    productID: UUID,
    contractVersion: String =
        VNextClassificationRecoveryContractDTO.explicitAuthorityContractVersion,
    unknownFields: String =
        "[\"garment_type\",\"sleeve_length\",\"lower_length\"]"
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops"
          },
          "unknown_fields":\(unknownFields),
          "candidates":[
            {
              "candidate_id":"candidate-knit-v7",
              "candidate_fingerprint":"candidate-knit-v7",
              "display_name":"니트/스웨터","category_code":"tops",
              "garment_type_code":"knit_sweater",
              "sleeve_length_code":"long_sleeve",
              "lower_length_code":null,
              "comparison_policy_code":"knit_sweater"
            },
            {
              "candidate_id":"candidate-cardigan-v7",
              "candidate_fingerprint":"candidate-cardigan-v7",
              "display_name":"가디건","category_code":"tops",
              "garment_type_code":"cardigan",
              "sleeve_length_code":"short_sleeve",
              "lower_length_code":"regular",
              "comparison_policy_code":"cardigan"
            }
          ],
          "candidate_count":2,"product_input_fingerprint":"input-v7",
          "product_evidence_fingerprint":"evidence-v7",
          "resolver_version":"resolver-v7",
          "candidate_contract_version":"\(contractVersion)",
          "candidate_set_hash":"set-v7",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

private func makeV7SingleGarmentAxisRecoveryContract(
    productID: UUID
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","garment_type_code":"shirt_blouse",
            "comparison_policy_code":"shirt_blouse"
          },
          "unknown_fields":["sleeve_length"],
          "candidates":[
            {
              "candidate_id":"candidate-shirt-short-v7",
              "candidate_fingerprint":"candidate-shirt-short-v7",
              "display_name":"셔츠/블라우스","category_code":"tops",
              "garment_type_code":"shirt_blouse",
              "sleeve_length_code":"short_sleeve",
              "comparison_policy_code":"shirt_blouse"
            },
            {
              "candidate_id":"candidate-shirt-long-v7",
              "candidate_fingerprint":"candidate-shirt-long-v7",
              "display_name":"셔츠/블라우스","category_code":"tops",
              "garment_type_code":"shirt_blouse",
              "sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"shirt_blouse"
            }
          ],
          "candidate_count":2,"product_input_fingerprint":"input-axis-v7",
          "product_evidence_fingerprint":"evidence-axis-v7",
          "resolver_version":"resolver-v7",
          "candidate_contract_version":"fitmatch-vnext-recovery-v7-explicit-authority",
          "candidate_set_hash":"set-axis-v7",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

private func copiedRecoveryContract(
    _ contract: VNextClassificationRecoveryContractDTO,
    fixedFacts: VNextKnownClassificationFactsDTO? = nil,
    unknownFields: [VNextUnknownClassificationField]? = nil,
    candidates: [VNextClassificationRecoveryCandidateDTO]? = nil,
    candidateCount: Int? = nil
) -> VNextClassificationRecoveryContractDTO {
    VNextClassificationRecoveryContractDTO(
        productID: contract.productID,
        globalStatus: contract.globalStatus,
        recoverability: contract.recoverability,
        unrecoverableReason: contract.unrecoverableReason,
        fixedFacts: fixedFacts ?? contract.fixedFacts,
        unknownFields: unknownFields ?? contract.unknownFields,
        candidates: candidates ?? contract.candidates,
        candidateCount: candidateCount ?? contract.candidateCount,
        productInputFingerprint: contract.productInputFingerprint,
        productEvidenceFingerprint: contract.productEvidenceFingerprint,
        resolverVersion: contract.resolverVersion,
        candidateContractVersion: contract.candidateContractVersion,
        candidateSetHash: contract.candidateSetHash,
        currentReviewReason: contract.currentReviewReason
    )
}

private func makeSavedRecoveryMutation(
    productID: UUID,
    candidate: VNextClassificationRecoveryCandidateDTO
) throws -> VNextUserClassificationMutationDTO {
    try decodeRecoveryJSON(
        """
        {
          "saved":true,"idempotent":false,
          "effective_classification":{
            "product_id":"\(productID)","state":"PERSONAL_CONFIRMED",
            "classification_status":"CONFIRMED","effective_source":"USER_EXPLICIT",
            "category_code":"\(candidate.categoryCode)",
            "garment_type_code":"\(candidate.garmentTypeCode)",
            "audience_code":"MEN",
            "sleeve_length_code":\(recoveryJSONString(candidate.sleeveLengthCode)),
            "lower_length_code":\(recoveryJSONString(candidate.lowerLengthCode)),
            "body_length_code":\(recoveryJSONString(candidate.bodyLengthCode)),
            "comparison_policy_code":"\(candidate.comparisonPolicyCode)",
            "product_structure_code":"SINGLE",
            "effective_authority_fingerprint":"effective-v7",
            "effective_contract_version":"effective-v1"
          }
        }
        """
    )
}

private func recoveryJSONString(_ value: String?) -> String {
    guard let value else { return "null" }
    return "\"\(value)\""
}

private func makeDuplicateFingerprintRecoveryContract(
    productID: UUID
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","sleeve_length_code":"long_sleeve"
          },
          "unknown_fields":["garment_type"],
          "candidates":[
            {
              "candidate_id":"duplicate","candidate_fingerprint":"duplicate",
              "display_name":"니트/스웨터","category_code":"tops",
              "garment_type_code":"knit_sweater",
              "sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"knit_sweater"
            },
            {
              "candidate_id":"duplicate","candidate_fingerprint":"duplicate",
              "display_name":"가디건","category_code":"tops",
              "garment_type_code":"cardigan",
              "sleeve_length_code":"long_sleeve",
              "comparison_policy_code":"cardigan"
            }
          ],
          "candidate_count":2,"product_input_fingerprint":"input-duplicate",
          "product_evidence_fingerprint":"evidence-duplicate",
          "resolver_version":"resolver-v6",
          "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
          "candidate_set_hash":"set-duplicate",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

private func makeIncompleteRecoveryContract(
    productID: UUID
) throws -> VNextClassificationRecoveryContractDTO {
    try decodeRecoveryJSON(
        """
        {
          "product_id":"\(productID)","global_status":"REVIEW_REQUIRED",
          "recoverability":"RECOVERABLE","unrecoverable_reason":null,
          "fixed_facts":{
            "audience_code":"MEN","product_structure_code":"SINGLE",
            "category_code":"tops","garment_type_code":"shirt_blouse",
            "comparison_policy_code":"shirt_blouse"
          },
          "unknown_fields":["sleeve_length"],
          "candidates":[
            {
              "candidate_id":"candidate-incomplete",
              "candidate_fingerprint":"candidate-incomplete",
              "display_name":"셔츠/블라우스","category_code":"tops",
              "garment_type_code":"shirt_blouse",
              "sleeve_length_code":null,
              "comparison_policy_code":"shirt_blouse"
            }
          ],
          "candidate_count":1,"product_input_fingerprint":"input-incomplete",
          "product_evidence_fingerprint":"evidence-incomplete",
          "resolver_version":"resolver-v6",
          "candidate_contract_version":"fitmatch-vnext-recovery-v6-complete-tuple-garment-first",
          "candidate_set_hash":"set-incomplete",
          "current_review_reason":"Product-exact verified evidence is required"
        }
        """
    )
}

@MainActor
private final class RecoveryLifecycleParserStub: ProductURLParsing {
    let product: ParsedProductInfo

    init(product: ParsedProductInfo) {
        self.product = product
    }

    func canParse(_ url: URL) -> Bool { true }

    func parse(from url: URL) async throws -> ParsedProductInfo { product }
}

private final class RecoveryLifecycleNoopMetricsRecorder: FitMatchMetricsRecording {
    func record(_ event: FitMatchMetricEvent) {}
}

private enum RecoveryOptionsFailure: Sendable {
    case invalidContract
    case malformedResponse
    case network
    case cancelled
}

private enum RecoverySaveFailure: Sendable {
    case network
}

private actor RecoveryLifecycleTransportStub: FitMatchServerAuthorityRemoteServicing {
    private enum PersonalState {
        case active(garmentType: String, revision: Int)
        case cleared(revision: Int)
    }

    private enum StubError: Error {
        case unexpected
        case missingContract
        case staleRevision
        case staleContract
    }

    private let productID: UUID
    private var contracts: [VNextClassificationRecoveryContractDTO]
    private var lastIssuedContract: VNextClassificationRecoveryContractDTO?
    private let recoveryFailure: RecoveryOptionsFailure?
    private let setFailure: RecoverySaveFailure?
    private var state: PersonalState = .active(
        garmentType: "polo_shirt",
        revision: 1
    )
    private var setRequests: [FitMatchSetUserProductClassificationRequest] = []
    private var clearRequests: [FitMatchClearUserProductClassificationRequest] = []
    private var feedbackEvents = ["SELECTED"]
    private var recoveryCalls = 0
    private var referenceDiscoveryCalls = 0
    private var beginCalls = 0

    init(
        productID: UUID,
        contracts: [VNextClassificationRecoveryContractDTO],
        recoveryFailure: RecoveryOptionsFailure? = nil,
        setFailure: RecoverySaveFailure? = nil,
        startsReviewRequired: Bool = false
    ) throws {
        guard !contracts.isEmpty else { throw StubError.missingContract }
        self.productID = productID
        self.contracts = contracts
        self.recoveryFailure = recoveryFailure
        self.setFailure = setFailure
        if startsReviewRequired {
            state = .cleared(revision: 0)
        }
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        FitMatchProductResolutionResponse(
            productID: productID,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: classification(
                status: "review_required",
                garmentType: nil,
                revision: nil
            ),
            comparisonReady: false
        )
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        throw StubError.unexpected
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        switch state {
        case .active(let garmentType, let revision):
            return try runtime(
                status: "confirmed",
                garmentType: garmentType,
                revision: revision
            )
        case .cleared:
            return try runtime(
                status: "review_required",
                garmentType: nil,
                revision: nil
            )
        }
    }

    func classificationRecoveryOptions(productID: UUID) async throws
        -> VNextClassificationRecoveryContractDTO {
        guard productID == self.productID else { throw StubError.unexpected }
        if let recoveryFailure {
            switch recoveryFailure {
            case .invalidContract:
                throw FitMatchServerAuthorityError
                    .invalidClassificationRecoveryContract("fixture_invalid")
            case .malformedResponse:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "fixture")
                )
            case .network:
                throw URLError(.notConnectedToInternet)
            case .cancelled:
                throw CancellationError()
            }
        }
        recoveryCalls += 1
        let contract: VNextClassificationRecoveryContractDTO
        if contracts.count > 1 {
            contract = contracts.removeFirst()
        } else if let only = contracts.first {
            contract = only
        } else {
            throw StubError.missingContract
        }
        lastIssuedContract = contract
        return contract
    }

    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        setRequests.append(request)
        if let setFailure {
            switch setFailure {
            case .network:
                throw URLError(.notConnectedToInternet)
            }
        }
        guard let contract = lastIssuedContract,
              request.expectedCandidateSetHash == contract.candidateSetHash,
              request.expectedProductInputFingerprint
                == contract.productInputFingerprint,
              request.expectedProductEvidenceFingerprint
                == contract.productEvidenceFingerprint,
              let candidate = contract.candidates.first(where: {
                  $0.candidateFingerprint == request.selectedCandidateFingerprint
              }) else {
            throw StubError.staleContract
        }
        let currentRevision: Int
        let previousGarment: String?
        switch state {
        case .active(let garmentType, let revision):
            currentRevision = revision
            previousGarment = garmentType
        case .cleared(let revision):
            currentRevision = revision
            previousGarment = nil
        }
        guard request.expectedRevision == currentRevision else {
            throw StubError.staleRevision
        }
        let nextRevision = currentRevision + 1
        let event = previousGarment == nil
            ? "SELECTED"
            : previousGarment == candidate.garmentTypeCode
                ? "REAFFIRMED" : "EDITED"
        state = .active(
            garmentType: candidate.garmentTypeCode,
            revision: nextRevision
        )
        feedbackEvents.append(event)
        return try mutation(
            garmentType: candidate.garmentTypeCode,
            revision: nextRevision,
            event: event,
            contract: contract,
            candidate: candidate
        )
    }

    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        clearRequests.append(request)
        guard case .active(_, let revision) = state,
              request.expectedRevision == revision else {
            throw StubError.staleRevision
        }
        let nextRevision = revision + 1
        state = .cleared(revision: nextRevision)
        feedbackEvents.append("CLEARED")
        return try clearMutation(revision: nextRevision)
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        .init(state: "ready", items: [])
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        referenceDiscoveryCalls += 1
        throw StubError.unexpected
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse {
        beginCalls += 1
        throw StubError.unexpected
    }

    func capturedSetRequest() -> FitMatchSetUserProductClassificationRequest? {
        setRequests.last
    }

    func capturedClearRequest() -> FitMatchClearUserProductClassificationRequest? {
        clearRequests.last
    }

    func setCallCount() -> Int { setRequests.count }
    func recoveryCallCount() -> Int { recoveryCalls }
    func referenceDiscoveryCallCount() -> Int { referenceDiscoveryCalls }
    func beginCallCount() -> Int { beginCalls }
    func lastFeedbackEvent() -> String? { feedbackEvents.last }
    func feedbackEventCount() -> Int { feedbackEvents.count }
    func globalClassificationStatus() -> String { "REVIEW_REQUIRED" }

    func currentRevision() -> Int {
        switch state {
        case .active(_, let revision), .cleared(let revision): revision
        }
    }

    func currentGarmentType() -> String? {
        if case .active(let garmentType, _) = state { return garmentType }
        return nil
    }

    private func runtime(
        status: String,
        garmentType: String?,
        revision: Int?
    ) throws -> FitMatchProductRuntimeResponse {
        let isPersonal = status == "confirmed"
        let runtimeState = isPersonal ? "ready" : "classification_required"
        let classification = classification(
            status: status,
            garmentType: garmentType,
            revision: revision
        )
        let effectiveState = isPersonal ? "PERSONAL_CONFIRMED" : "REVIEW_REQUIRED"
        let effectiveSource = isPersonal ? "USER_EXPLICIT" : "NONE"
        let vnext: VNextProductRuntimeDTO = try decodeRecoveryJSON(
            """
            {
              "found":true,
              "product":{
                "id":"\(productID)","source_code":"musinsa",
                "source_product_key":"recovery-patch",
                "product_name":"Recovery Test Product",
                "classification_status":"\(status.uppercased())",
                "product_structure_code":"SINGLE","audience_code":"MEN",
                "category_code":"tops",
                "garment_type_code":\(jsonString(garmentType)),
                "comparison_policy_code":\(jsonString(garmentType)),
                "sleeve_length_code":"short_sleeve",
                "resolver_version":"resolver-v2","input_fingerprint":"input"
              },
              "readiness":{
                "status":"\(isPersonal ? "READY" : "CLASSIFICATION_REQUIRED")",
                "ready_size_count":\(isPersonal ? 1 : 0),"policy_metric_count":4
              },
              "variants":[],
              "effective_classification":{
                "product_id":"\(productID)","state":"\(effectiveState)",
                "classification_status":"\(status.uppercased())",
                "effective_source":"\(effectiveSource)","category_code":"tops",
                "garment_type_code":\(jsonString(garmentType)),"audience_code":"MEN",
                "sleeve_length_code":"short_sleeve",
                "comparison_policy_code":\(jsonString(garmentType)),
                "product_structure_code":"SINGLE",
                "override_revision":\(revision.map(String.init) ?? "null"),
                "effective_authority_fingerprint":"effective-\(revision ?? 0)",
                "effective_contract_version":"effective-v1"
              }
            }
            """
        )
        return FitMatchProductRuntimeResponse(
            runtimeState: runtimeState,
            comparisonReady: isPersonal,
            product: FitMatchRuntimeProduct(
                productID: productID,
                source: "musinsa",
                externalProductID: "recovery-patch",
                productName: "Recovery Test Product",
                canonicalURL: nil,
                audience: "MEN",
                sourceCategoryPath: "상의 > 반소매",
                sourceCategoryCodes: ["001", "001001"],
                imageURL: nil,
                lifecycleStatus: "active",
                inputFingerprint: "input"
            ),
            classification: classification,
            variants: [],
            vnext: vnext
        )
    }

    private func classification(
        status: String,
        garmentType: String?,
        revision: Int?
    ) -> FitMatchDatabaseClassification {
        FitMatchDatabaseClassification(
            classificationID: productID,
            categoryCode: garmentType == nil ? nil : "tops",
            detailCode: garmentType == nil ? nil : "short_sleeve",
            garmentTypeCode: garmentType,
            familyCode: garmentType,
            lengthCode: garmentType == nil ? nil : "short_sleeve",
            bodyLengthCode: nil,
            status: status,
            method: garmentType == nil ? "review_required" : "user_explicit",
            authorityStatus: garmentType == nil ? nil : "user_explicit",
            confidence: garmentType == nil ? nil : 1,
            requiresUserConfirmation: garmentType == nil,
            taxonomyPolicyVersion: "resolver-v2",
            decisionVersion: revision.map { "revision-\($0)" }
        )
    }

    private func mutation(
        garmentType: String,
        revision: Int,
        event: String,
        contract: VNextClassificationRecoveryContractDTO,
        candidate: VNextClassificationRecoveryCandidateDTO
    ) throws -> VNextUserClassificationMutationDTO {
        try decodeRecoveryJSON(
            """
            {
              "saved":true,"idempotent":false,"event":"\(event)",
              "override":{
                "id":"\(productID)","product_id":"\(productID)",
                "classification_source":"USER_EXPLICIT","audience_code":"MEN",
                "category_code":"tops","garment_type_code":"\(garmentType)",
                "comparison_policy_code":"\(garmentType)",
                "sleeve_length_code":"short_sleeve",
                "selected_candidate_fingerprint":"\(candidate.candidateFingerprint)",
                "candidate_contract_version":"\(contract.candidateContractVersion)",
                "candidate_set_hash":"\(contract.candidateSetHash ?? "")",
                "revision":\(revision),"cleared_at":null
              },
              "effective_classification":{
                "product_id":"\(productID)","state":"PERSONAL_CONFIRMED",
                "classification_status":"CONFIRMED","effective_source":"USER_EXPLICIT",
                "category_code":"tops","garment_type_code":"\(garmentType)",
                "audience_code":"MEN","sleeve_length_code":"short_sleeve",
                "comparison_policy_code":"\(garmentType)",
                "product_structure_code":"SINGLE","override_revision":\(revision),
                "effective_authority_fingerprint":"effective-\(revision)",
                "effective_contract_version":"effective-v1"
              }
            }
            """
        )
    }

    private func clearMutation(revision: Int) throws
        -> VNextUserClassificationMutationDTO {
        try decodeRecoveryJSON(
            """
            {
              "cleared":true,"idempotent":false,"override_id":"\(productID)",
              "revision":\(revision),
              "effective_classification":{
                "product_id":"\(productID)","state":"REVIEW_REQUIRED",
                "classification_status":"REVIEW_REQUIRED","effective_source":"NONE",
                "audience_code":"MEN","product_structure_code":"SINGLE",
                "effective_authority_fingerprint":"effective-\(revision)",
                "effective_contract_version":"effective-v1"
              }
            }
            """
        )
    }

    private func jsonString(_ value: String?) -> String {
        guard let value else { return "null" }
        return "\"\(value)\""
    }
}

private func decodeRecoveryJSON<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}
