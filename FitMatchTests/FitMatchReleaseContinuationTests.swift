import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// Continuous production-owner probes with synthetic RPC receipts. These do
/// not exercise SwiftUI button presentation, authentication, or a live DB.
@MainActor
struct FitMatchReleaseContinuationTests {
    @Test func compareChangeSizeChangeClosetThenChangeSizeKeepsEachApprovedBatch() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let sizeIDs = [fixture.productSizeID, UUID()]
        let first = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let second = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        second.productName = "연속 비교 두 번째 내 옷"
        second.chest = 56
        first.isRepresentative = false
        second.isRepresentative = false
        let records = [fixture.closetRecord(for: first), fixture.closetRecord(for: second)]
        let firstCandidates = candidates(sizeIDs: sizeIDs, referenceChest: 50)
        let secondCandidates = candidates(sizeIDs: sizeIDs, referenceChest: 56)
        let secondComparisonID = UUID()
        let runtime = try fixture.runtime(globalStatus: .confirmed, runtimeCandidates: firstCandidates)
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 2),
            runtimes: Array(repeating: runtime, count: 3),
            closetResponses: [.init(state: "ready", items: records)],
            candidateResponses: [
                try fixture.referenceResponse(reference: first, closetItemID: records[0].closetItemID,
                    decision: "MANUAL_EXTENDED", eligibleProductSizeIDs: sizeIDs),
                try fixture.referenceResponse(reference: second, closetItemID: records[1].closetItemID,
                    decision: "MANUAL_EXTENDED", eligibleProductSizeIDs: sizeIDs)
            ],
            eligibleResponses: [
                try fixture.eligible(referenceClosetItemID: records[0].closetItemID,
                    candidates: firstCandidates, allowed: true, decision: "MANUAL_EXTENDED"),
                try fixture.eligible(referenceClosetItemID: records[1].closetItemID,
                    candidates: secondCandidates, allowed: true, decision: "MANUAL_EXTENDED")
            ],
            beginResponses: [
                try begin(fixture: fixture, comparisonID: fixture.comparisonID,
                    referenceID: records[0].closetItemID, candidates: firstCandidates),
                try begin(fixture: fixture, comparisonID: secondComparisonID,
                    referenceID: records[1].closetItemID, candidates: secondCandidates)
            ],
            completionResponses: [
                completion(id: fixture.comparisonID, sizeID: sizeIDs[0], label: "M"),
                completion(id: secondComparisonID, sizeID: sizeIDs[1], label: "L")
            ]
        )
        let viewModel = makeViewModel(fixture: fixture, remote: remote)
        #expect(await viewModel.loadProductInfoFromURL())
        let firstResult = await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: first)
        let firstDiagnostic = "\(viewModel.errorMessage ?? "no error"); calls=\(await remote.calls())"
        let firstHistory = try #require(firstResult, Comment(rawValue: firstDiagnostic))
        defer { VNextComparisonSessionStore.shared.remove(historyID: firstHistory.id) }
        let firstCalls = await remote.calls()
        let firstAlternative = try approvedAlternative(history: firstHistory,
            serverComparisonID: fixture.comparisonID, sizeID: sizeIDs[1])
        #expect(firstAlternative.result.comparedItems.first?.referenceValue == 50)
        #expect(firstAlternative.result.comparedItems.first?.productValue == 56)
        #expect(await remote.calls() == firstCalls)

        // The same loaded ViewModel receives the user's second Closet choice.
        // It must run fresh authorization/begin/complete, then expose the new
        // batch under its own immutable comparison ID.
        let secondResult = await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: second)
        let secondDiagnostic = "\(viewModel.errorMessage ?? "no error"); calls=\(await remote.calls())"
        let secondHistory = try #require(secondResult, Comment(rawValue: secondDiagnostic))
        defer { VNextComparisonSessionStore.shared.remove(historyID: secondHistory.id) }
        #expect(firstHistory.id != secondHistory.id)
        #expect(firstHistory.userFit.id == first.id)
        #expect(secondHistory.userFit.id == second.id)
        #expect(firstHistory.recommendedSize.id == sizeIDs[0])
        #expect(secondHistory.recommendedSize.id == sizeIDs[1])
        let secondCalls = await remote.calls()
        let secondAlternative = try approvedAlternative(history: secondHistory,
            serverComparisonID: secondComparisonID, sizeID: sizeIDs[0])
        #expect(secondAlternative.result.comparedItems.first?.referenceValue == 56)
        #expect(secondAlternative.result.comparedItems.first?.productValue == 50)
        #expect(await remote.calls() == secondCalls)
        #expect(secondCalls.filter { $0 == "eligible_sizes" }.count == 2)
        #expect(secondCalls.filter { $0 == "begin_comparison" }.count == 2)
        #expect(secondCalls.filter { $0 == "complete_comparison" }.count == 2)
        #expect(try approvedAlternative(history: firstHistory,
            serverComparisonID: fixture.comparisonID, sizeID: sizeIDs[1])
            .result.comparedItems.first?.referenceValue == 50)
    }

    @Test func compareRegisterOwnedSizeThenCompareUsingAuthoritativeRegisteredItem() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let sizeIDs = [fixture.productSizeID, UUID()]
        let initialReference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        initialReference.isRepresentative = false
        let initialRecord = fixture.closetRecord(for: initialReference)
        let initialCandidates = candidates(sizeIDs: sizeIDs, referenceChest: 50)
        let firstRun = try comparisonRun(fixture: fixture, reference: initialReference,
            record: initialRecord, candidates: initialCandidates,
            comparisonID: fixture.comparisonID, recommendedIndex: 0)
        #expect(await firstRun.viewModel.loadProductInfoFromURL())
        let firstResult = await firstRun.viewModel.calculateTemporaryRecommendation(selectedReferenceItem: initialReference)
        let firstDiagnostic = "\(firstRun.viewModel.errorMessage ?? "no error"); calls=\(await firstRun.remote.calls())"
        let firstHistory = try #require(firstResult, Comment(rawValue: firstDiagnostic))
        defer { VNextComparisonSessionStore.shared.remove(historyID: firstHistory.id) }

        let runtime = try fixture.runtime(globalStatus: .confirmed, runtimeCandidates: initialCandidates)
        let preparationRemote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)], runtimes: [runtime])
        let preparationOutcome = await FitMatchResultClosetRegistrationPreparationAction.prepare(
            historicalProduct: firstHistory.product,
            productDetailCategory: firstHistory.productDetailCategory,
            preferredProductSizeID: sizeIDs[1],
            legacyPreferredSize: firstHistory.product.sizes.first { $0.id == sizeIDs[1] },
            makeViewModel: { makeViewModel(fixture: fixture, remote: preparationRemote) }
        )
        guard case .prepared(let preparation) = preparationOutcome else {
            Issue.record("Result registration did not produce fresh server-backed inputs")
            return
        }
        let selectedSize = try #require(preparation.preferredSize)
        let serverContext = try #require(preparation.serverRegistrationContext)
        let identity = try #require(serverContext.identitiesByDisplaySizeID[selectedSize.id])
        #expect(identity.productSizeID == sizeIDs[1])
        #expect(serverContext.isRegisterable(displaySizeID: selectedSize.id))
        let saveRequest = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: preparation.product, selectedSize: selectedSize, serverIdentity: identity,
            hasMeasurementEligibilityProof: serverContext.isRegisterable(displaySizeID: selectedSize.id),
            activeClosetItems: [initialReference], brandName: fixture.sourceName,
            gender: .men, genderCode: "men", productName: preparation.product.name,
            category: .top, categoryCode: "tops", detailCategory: .shortSleeve,
            detailCategoryCode: "short_sleeve", sourceObservationID: serverContext.sourceObservationID,
            isRepresentative: false, didExplicitlyChangeClassification: false)
        let submission = try FitMatchComparedProductClosetRegistration.prepareServerFirstSubmission(saveRequest)
        let receipt = registrationReceipt(request: submission.remoteRequest,
            fixture: fixture, chest: 56)
        let registrationRemote = ContinuationRegistrationRemote(receipt: receipt)
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let sync = FitMatchClosetSyncCoordinator()
        let userID = UUID()
        let submissionOutcome = await FitMatchComparedProductClosetSubmissionAction(remote: registrationRemote)
            .submitServerFirst(submission, in: context, submissionUserID: userID,
                currentUserID: { userID },
                projectAuthoritativeReceipt: { record, request, closetItemID, context in
                    try sync.projectAuthoritativeRegistration(record, expected: request,
                        acceptedClosetItemID: closetItemID, modelContext: context)
                })
        guard case .completed(.saved(let registeredItem)) = submissionOutcome else {
            Issue.record("Registered item was not projected from authoritative read-back")
            return
        }
        #expect(registeredItem.id == submission.remoteRequest.clientItemID)
        #expect(registeredItem.id != initialReference.id)
        #expect(registeredItem.chest == 56)
        #expect(registeredItem.comparisonGroupCode == "A")
        #expect(!registeredItem.isRepresentative)
        #expect(await registrationRemote.events() == ["upsert", "get_exact_item"])
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)

        let secondID = UUID()
        let secondRun = try comparisonRun(fixture: fixture, reference: registeredItem,
            record: receipt, candidates: candidates(sizeIDs: sizeIDs, referenceChest: 56),
            comparisonID: secondID, recommendedIndex: 1, resolvesLinkedReference: true)
        #expect(await secondRun.viewModel.loadProductInfoFromURL())
        let secondResult = await secondRun.viewModel.calculateTemporaryRecommendation(selectedReferenceItem: registeredItem)
        let secondDiagnostic = "\(secondRun.viewModel.errorMessage ?? "no error"); calls=\(await secondRun.remote.calls())"
        let secondHistory = try #require(secondResult, Comment(rawValue: secondDiagnostic))
        defer { VNextComparisonSessionStore.shared.remove(historyID: secondHistory.id) }
        #expect(secondHistory.id != firstHistory.id)
        #expect(secondHistory.userFit.id == registeredItem.id)
        #expect(secondHistory.recommendedSize.id == sizeIDs[1])
        let batch = try #require(VNextComparisonSessionStore.shared.analysis(for: secondHistory.id))
        #expect(batch.comparisonID == secondID)
        #expect(batch.analyses.allSatisfy { $0.result.comparedItems.first?.referenceValue == 56 })
        #expect((await secondRun.remote.calls()).filter { $0 == "complete_comparison" }.count == 1)
    }

    private func approvedAlternative(history: RecommendationHistory,
        serverComparisonID: UUID, sizeID: UUID) throws
        -> VNextComparisonCandidateAnalysis {
        let batch = try #require(VNextComparisonSessionStore.shared.analysis(for: history.id))
        #expect(batch.comparisonID == serverComparisonID)
        #expect(RecommendationService().canPresentCurrentVNextAlternativeSizes(for: history, batch: batch))
        #expect(batch.authorizedCandidateProductSizeIDs.contains(sizeID))
        return try #require(batch.analyses.first { $0.productSizeID == sizeID })
    }

    func candidates(sizeIDs: [UUID], referenceChest: Double) -> [HeadlessServerCandidateFixture] {
        zip(sizeIDs, [("M", 50.0), ("L", 56.0)]).map { id, size in
            HeadlessServerCandidateFixture(productSizeID: id, sizeLabel: size.0,
                metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: referenceChest,
                    targetValue: size.1)],
                // Runtime transports the canonical code; the reused legacy
                // begin fixture carries its expanded measurement identity.
                runtimeMetrics: [.init(code: "chest_width", referenceValue: referenceChest,
                    targetValue: size.1)])
        }
    }

    private func makeViewModel(fixture: HeadlessJourneyFixture, remote: JourneyRecordingRemote)
        -> ShoppingProductViewModel {
        ShoppingProductViewModel(initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(musinsaParser: HeadlessJourneyParser(product: fixture.parsedProduct())),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote))
    }

    private func comparisonRun(fixture: HeadlessJourneyFixture, reference: UserFit,
        record: FitMatchClosetItemRecord, candidates: [HeadlessServerCandidateFixture],
        comparisonID: UUID, recommendedIndex: Int, resolvesLinkedReference: Bool = false) throws
        -> (viewModel: ShoppingProductViewModel, remote: JourneyRecordingRemote) {
        let runtime = try fixture.runtime(globalStatus: .confirmed, runtimeCandidates: candidates)
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 2),
            runtimes: Array(repeating: runtime, count: resolvesLinkedReference ? 3 : 2),
            closetResponses: [.init(state: "ready", items: [record])],
            candidateResponses: [try fixture.referenceResponse(reference: reference,
                closetItemID: record.closetItemID, decision: "MANUAL_EXTENDED",
                eligibleProductSizeIDs: candidates.map(\.productSizeID))],
            eligibleResponses: [try fixture.eligible(referenceClosetItemID: record.closetItemID,
                candidates: candidates, allowed: true, decision: "MANUAL_EXTENDED")],
            beginResponses: [try begin(fixture: fixture, comparisonID: comparisonID,
                referenceID: record.closetItemID, candidates: candidates)],
            completionResponses: [completion(id: comparisonID,
                sizeID: candidates[recommendedIndex].productSizeID,
                label: candidates[recommendedIndex].sizeLabel)])
        return (makeViewModel(fixture: fixture, remote: remote), remote)
    }

    func completion(id: UUID, sizeID: UUID, label: String) -> VNextCompleteComparisonDTO {
        .init(comparisonID: id, completed: true, idempotent: false,
            recommendedProductSizeID: sizeID, recommendedSizeLabel: label,
            validatedEvidenceCount: 1, coverage: 1)
    }

    /// Serializes opaque, issued transport evidence with a distinct run ID.
    /// Scoring, permission checks, candidate selection and persistence remain
    /// in the production owners invoked above.
    func begin(fixture: HeadlessJourneyFixture, comparisonID: UUID,
        referenceID: UUID, candidates: [HeadlessServerCandidateFixture]) throws -> FitMatchBeginComparisonResponse {
        let authorization: [String: Any] = [
            "decision": "MANUAL_EXTENDED", "allowed": true, "mode": "MANUAL_EXTENDED",
            "excluded_measurement_codes": [], "required_measurement_codes": ["chest_width_pit_to_pit"],
            "minimum_common": 1, "common_measurement_count": 1, "required_any_count": 1,
            "policy_code": "tshirt", "policy_version": "v1", "policy_checksum": "policy-v1"]
        let candidateRows: [[String: Any]] = candidates.map { candidate in
            ["product_size_id": candidate.productSizeID.uuidString, "size_label": candidate.sizeLabel,
             "availability": ["status": "AVAILABLE"], "authorization": authorization,
             "comparison_measurements": candidate.metrics.map { metric in
                ["measurement_code": metric.code, "reference_value": metric.referenceValue,
                 "target_value": metric.targetValue, "difference": metric.targetValue - metric.referenceValue,
                 "absolute_difference": abs(metric.targetValue - metric.referenceValue), "unit_code": "CM",
                 "basis_code": metric.basisCode, "weight": metric.weight,
                 "requirement_mode": metric.requirementMode, "priority": metric.priority] as [String: Any]
             }]
        }
        let sizeIDs = candidates.map { $0.productSizeID.uuidString }
        let snapshot: [String: Any] = [
            "snapshot_schema_version": 4,
            "reference_snapshot": ["closet_item_id": referenceID.uuidString.lowercased()],
            "authority_snapshot": ["effective_classification_at_begin": [
                "source": "GLOBAL_CONFIRMED", "state": "GLOBAL_CONFIRMED", "category_code": "tops",
                "garment_type_code": "tshirt", "audience_code": "MEN", "sleeve_length_code": "short_sleeve",
                "comparison_policy_code": "tshirt", "effective_authority_fingerprint": "effective-0"]],
            "input_snapshot": ["effective_authority_fingerprint": "effective-0"],
            "excluded_measurement_codes": [], "authorization_snapshot": authorization,
            "policy_snapshot": ["policy_code": "tshirt", "policy_version": "v1", "policy_checksum": "policy-v1",
                "metrics": [["metric_mode": "CANONICAL", "fitmatch_measurement_code": "chest_width_pit_to_pit",
                    "weight": 1, "requirement_mode": "REQUIRED_ANY", "priority": 1, "is_active": true]]],
            "target_snapshot": ["product_id": fixture.productID.uuidString, "variant_id": fixture.variantID.uuidString,
                "authorized_candidate_product_size_ids": sizeIDs, "candidate_authority_fingerprint": "candidate-v1",
                "classification_status": "CONFIRMED", "garment_type_code": "tshirt",
                "sleeve_length_code": "short_sleeve", "candidates": candidateRows]]
        let payload: [String: Any] = ["comparison_id": comparisonID.uuidString, "created": true,
            "idempotent": false, "result_status": "PENDING", "authorization": authorization,
            "authorized_candidate_product_size_ids": sizeIDs, "candidate_authority_fingerprint": "candidate-v1",
            "effective_authority_fingerprint": "effective-0", "snapshot_schema_version": 4, "snapshot": snapshot]
        return try JSONDecoder().decode(FitMatchBeginComparisonResponse.self,
            from: JSONSerialization.data(withJSONObject: payload))
    }

    private func registrationReceipt(request: FitMatchUpsertClosetItemRequest,
        fixture: HeadlessJourneyFixture, chest: Double) -> FitMatchClosetItemRecord {
        .init(closetItemID: UUID(), clientItemID: request.clientItemID,
            productID: request.productID, externalProductID: fixture.productCode,
            productAudience: "MEN", sourceCategoryCodes: ["tops", "short_sleeve"],
            variantID: request.productVariantID, productSizeID: request.productSizeID,
            brand: request.item.brand, productName: request.item.productName, sizeName: request.item.sizeName,
            genderCode: "men", source: "musinsa", sourceCategoryPath: "tops > short sleeve",
            productURL: request.item.productURL, imageURL: nil,
            measurements: ["chest_width": chest], measurementRecords: [
                .init(value: chest, unit: "cm", measurementCode: "chest_width", displayKind: "chest",
                    methodSource: "server", methodProfile: nil, inputSource: "imported_size_chart",
                    standardVersion: nil, mappingVersion: "v1", rawCode: "chest_width",
                    rawLabel: "Chest", rawInfo: nil, rawValueText: String(chest),
                    evidenceLevel: "official_text", semanticStatus: "mapped")],
            fitMemo: "", fitPreferenceCode: "regular", satisfaction: 4, isReference: false,
            classificationStatus: "confirmed", classificationSource: "product_metadata",
            categoryCode: "tops", detailCode: "short_sleeve", canonicalCategoryCode: "tops",
            canonicalDetailCode: "short_sleeve", familyCode: "tshirt", lengthCode: "short_sleeve",
            bodyLengthCode: nil, comparisonGroupCode: "A", comparisonGroupSource: "RETAILER_CATEGORY",
            comparisonGroupPolicyVersion: "fixture-v1", classificationSnapshot: [:], clientSnapshot: [:],
            clientCreatedAt: "2026-10-02T00:00:00Z", clientUpdatedAt: "2026-10-02T00:00:00Z",
            syncRevision: 1, createdAt: "2026-10-02T00:00:00Z", updatedAt: "2026-10-02T00:00:00Z")
    }
}

private actor ContinuationRegistrationRemote: FitMatchClosetRegistrationRemoteServicing {
    let receipt: FitMatchClosetItemRecord
    private var log: [String] = []
    init(receipt: FitMatchClosetItemRecord) { self.receipt = receipt }
    func events() -> [String] { log }
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws -> FitMatchUpsertClosetItemResponse {
        log.append("upsert")
        #expect(request.clientItemID == receipt.clientItemID)
        #expect(request.productID == receipt.productID)
        #expect(request.productVariantID == receipt.variantID)
        #expect(request.productSizeID == receipt.productSizeID)
        return .init(closetItemID: receipt.closetItemID, clientItemID: receipt.clientItemID,
            syncRevision: 1, classificationStatus: "confirmed", categoryCode: receipt.categoryCode,
            detailCode: receipt.detailCode, familyCode: receipt.familyCode,
            lengthCode: receipt.lengthCode, bodyLengthCode: nil, isReference: false)
    }
    func getClosetItem(closetItemID: UUID) async throws -> FitMatchClosetItemsResponse {
        log.append("get_exact_item")
        #expect(closetItemID == receipt.closetItemID)
        return .init(state: "ready", items: [receipt])
    }
    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws -> FitMatchSetClosetReferenceResponse {
        Issue.record("Registering an owned size must not restore deprecated reference mutation")
        throw URLError(.unsupportedURL)
    }
}
