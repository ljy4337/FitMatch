import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchContractClosureRegressionTests {
    @Test func F01ReceiptMustBeHiddenAndExactlyMatchRequestedClientIDs() async throws {
        let requested = UUID()
        let remote = ContractClosureReceiptRemote(
            receipt: VNextComparisonHistoryVisibilityDTO(
                clientComparisonIDs: [requested, UUID()],
                hidden: false,
                idempotent: false
            )
        )
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote)

        do {
            try await coordinator.hideVNextComparisonHistories(
                clientComparisonIDs: [requested, requested]
            )
            Issue.record("A malformed hide receipt was accepted.")
        } catch {
            #expect(error is FitMatchSupabaseProductResolverError)
        }

        #expect(await remote.receivedClientIDs() == [requested])
    }

    @Test func F02InvalidatedSubmissionCannotClearNewerInFlightSubmission() async {
        let action = FitMatchComparisonSubmissionAction()
        let firstEntered = ContractClosureGate()
        let firstRelease = ContractClosureGate()
        let secondEntered = ContractClosureGate()
        let secondRelease = ContractClosureGate()

        let first = Task { @MainActor in
            await action.submit {
                await firstEntered.open()
                await firstRelease.wait()
                return nil
            }
        }
        await firstEntered.wait()

        let duplicate = await action.submit { nil }
        guard case .alreadyInFlight = duplicate else {
            Issue.record("The duplicate tap was not rejected.")
            return
        }

        action.invalidate()
        let second = Task { @MainActor in
            await action.submit {
                await secondEntered.open()
                await secondRelease.wait()
                return nil
            }
        }
        await secondEntered.wait()

        await firstRelease.open()
        let firstOutcome = await first.value
        guard case .cancelled = firstOutcome else {
            Issue.record("The invalidated first submission produced a result.")
            return
        }

        let secondDuplicate = await action.submit { nil }
        guard case .alreadyInFlight = secondDuplicate else {
            Issue.record("The first deferred cleanup unlocked the newer submission.")
            return
        }

        await secondRelease.open()
        let secondOutcome = await second.value
        guard case .finished = secondOutcome else {
            Issue.record("The current submission did not finish normally.")
            return
        }
    }

    @Test func F03SavedFrozenReferenceResolvesBackToItsOriginalClosetID() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let sourceReference = makeReference()
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 51,
                totalLength: 70,
                sleeveLength: 23
            )
        )
        let product = Product(name: "서버 상품", category: .top, sizes: [size])
        let history = makeServerCompletedHistory(
            product: product,
            size: size,
            reference: sourceReference
        )
        let sourceID = sourceReference.id

        context.insert(sourceReference)
        context.insert(product)
        try context.save()
        try RecommendationHistoryStore.saveCompletedVNext(
            history,
            existing: [],
            modelContext: context
        )

        let saved = try #require(
            context.fetch(FetchDescriptor<RecommendationHistory>()).first
        )
        #expect(saved.userFit.id != sourceID)
        #expect(saved.userFit.isHistoryOnlyReferenceSnapshot)
        #expect(saved.referencesClosetItem(clientItemID: sourceID))
        #expect(!saved.referencesClosetItem(clientItemID: UUID()))
    }

    @Test func F04ReadinessIsClosedAndMissingBeginStatusCannotDefaultToPending() throws {
        let supported = [
            "READY", "CLASSIFICATION_REQUIRED", "NOT_APPLICABLE",
            "POLICY_UNAVAILABLE", "NO_AVAILABLE_SIZE", "NO_MEASUREMENT_DATA",
            "MAPPING_REQUIRED", "INSUFFICIENT_MEASUREMENTS"
        ]
        for status in supported {
            let readiness: VNextProductReadinessDTO = try decode(
                "{\"status\":\"\(status)\",\"reason\":null}"
            )
            #expect(try FitMatchVNextContractValidator.readinessState(readiness)
                == VNextReadinessState(rawValue: status)!)
        }

        let unknown: VNextProductReadinessDTO = try decode(
            "{\"status\":\"FUTURE_STATE\",\"reason\":null}"
        )
        #expect(throws: FitMatchVNextContractError.unknownState(
            field: "readiness.status",
            observed: "FUTURE_STATE"
        )) {
            try FitMatchVNextContractValidator.readinessState(unknown)
        }

        let missingStatus = validBeginJSON().replacingOccurrences(
            of: "\"result_status\":\"PENDING\",",
            with: ""
        )
        #expect(throws: DecodingError.self) {
            let _: VNextBeginComparisonDTO = try decode(missingStatus)
        }
    }

    @Test func F05EngineRejectsDirectlyConstructedUnsupportedSnapshot() throws {
        let decoded: VNextBeginComparisonDTO = try decode(validBeginJSON())
        let unsupportedSnapshot = VNextComparisonBeginSnapshotDTO(
            snapshotSchemaVersion: 5,
            target: decoded.snapshot.target,
            policy: decoded.snapshot.policy,
            authorization: decoded.snapshot.authorization,
            excludedMeasurementCodes: decoded.snapshot.excludedMeasurementCodes,
            referenceSnapshot: decoded.snapshot.referenceSnapshot,
            authoritySnapshot: decoded.snapshot.authoritySnapshot,
            inputSnapshot: decoded.snapshot.inputSnapshot
        )
        let direct = VNextBeginComparisonDTO(
            comparisonID: decoded.comparisonID,
            created: false,
            idempotent: true,
            resultStatus: "PENDING",
            authorization: decoded.authorization,
            authorizedCandidateProductSizeIDs: decoded.authorizedCandidateProductSizeIDs,
            candidateAuthorityFingerprint: decoded.candidateAuthorityFingerprint,
            effectiveAuthorityFingerprint: decoded.effectiveAuthorityFingerprint,
            snapshotSchemaVersion: 5,
            snapshot: unsupportedSnapshot
        )

        #expect(throws: FitMatchVNextContractError.unsupportedSnapshotVersion(5)) {
            try VNextComparisonEngineAdapter().analyze(direct)
        }
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeReference() -> UserFit {
        let reference = UserFit(
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "테스트",
            productName: "기준 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 50,
                totalLength: 70,
                sleeveLength: 23
            ),
            fitMemo: "",
            satisfaction: 4,
            isRepresentative: true
        )
        reference.garmentTypeRawValue = "tshirt"
        reference.sleeveTypeRawValue = "short_sleeve"
        reference.markClassificationAuthority(.userExplicit, sourceIdentity: "test")
        return reference
    }

    private func makeServerCompletedHistory(
        product: Product,
        size: ProductSize,
        reference: UserFit
    ) -> RecommendationHistory {
        let compared = MeasurementComparisonItem(
            kind: .chest,
            measurementCode: .chestWidthPitToPit,
            productValue: size.chest,
            referenceValue: reference.chest,
            signedDifference: size.chest - reference.chest,
            absoluteDifference: abs(size.chest - reference.chest),
            score: 95,
            weight: 1
        )
        let result = MeasurementComparisonResult(
            status: .confirmed,
            score: 95,
            comparedItems: [compared],
            exclusions: [],
            averageDifference: compared.absoluteDifference,
            minimumComparableCount: 1,
            requiredKinds: [.chest],
            minimumRequiredKindCount: 1,
            requiredAllKinds: [],
            expectedWeightSum: 1,
            usedWeightSum: 1
        )
        return RecommendationHistory(
            product: product,
            recommendedSize: size,
            userFit: reference,
            totalDifference: result.averageDifference,
            measurementDifferences: result.signedDifferences,
            recommendationScore: result.score,
            comparisonMethod: "서버 승인 직접 비교",
            productDetailCategory: .shortSleeve,
            comparisonResult: result,
            reason: "contract closure test"
        )
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func validBeginJSON() -> String {
        let comparisonID = UUID()
        let productID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        return """
        {
          "comparison_id":"\(comparisonID)","created":true,"idempotent":false,
          "result_status":"PENDING","snapshot_schema_version":4,
          "authorization":{"decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC","reason":null,"excluded_measurement_codes":[],"required_measurement_codes":["chest_width"],"minimum_common":1,"common_measurement_count":1,"required_any_count":1,"policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"},
          "authorized_candidate_product_size_ids":["\(sizeID)"],"candidate_authority_fingerprint":"candidate-v1",
          "snapshot":{"snapshot_schema_version":4,"reference_snapshot":{},"authority_snapshot":{},"input_snapshot":{},"excluded_measurement_codes":[],"policy_snapshot":{"policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1","metrics":[{"metric_mode":"CANONICAL","fitmatch_measurement_code":"chest_width","weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,"is_active":true}]},"authorization_snapshot":{"decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC","reason":null,"excluded_measurement_codes":[],"required_measurement_codes":["chest_width"],"minimum_common":1,"common_measurement_count":1,"required_any_count":1,"policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"},"target_snapshot":{"product_id":"\(productID)","variant_id":"\(variantID)","authorized_candidate_product_size_ids":["\(sizeID)"],"candidate_authority_fingerprint":"candidate-v1","classification_status":"CONFIRMED","garment_type_code":"tshirt","sleeve_length_code":"short_sleeve","lower_length_code":null,"body_length_code":null,"candidates":[{"product_size_id":"\(sizeID)","size_label":"M","availability":{"status":"AVAILABLE","observed_at":"2026-08-29T00:00:00Z","valid_until":"2026-08-30T00:00:00Z","evidence_fingerprint":"stock"},"comparison_measurements":[{"measurement_code":"chest_width","reference_value":50,"target_value":51,"difference":1,"absolute_difference":1,"unit_code":"CM","basis_code":"WIDTH","weight":1,"requirement_mode":"REQUIRED_ANY","priority":1}],"authorization":{"decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC","reason":null,"excluded_measurement_codes":[],"required_measurement_codes":["chest_width"],"minimum_common":1,"common_measurement_count":1,"required_any_count":1,"policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"}}]}}
        }
        """
    }
}

private actor ContractClosureReceiptRemote: FitMatchComparisonRemoteServicing {
    private let receipt: VNextComparisonHistoryVisibilityDTO
    private var received: [UUID] = []

    init(receipt: VNextComparisonHistoryVisibilityDTO) {
        self.receipt = receipt
    }

    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO] { [] }

    func hideVNextComparisonHistories(
        clientComparisonIDs: [UUID]
    ) async throws -> VNextComparisonHistoryVisibilityDTO {
        received = clientComparisonIDs
        return receipt
    }

    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO {
        throw ContractClosureRemoteError.unexpectedCompletion
    }

    func receivedClientIDs() -> [UUID] { received }
}

private enum ContractClosureRemoteError: Error {
    case unexpectedCompletion
}

private actor ContractClosureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
