import Foundation
import Supabase
import Testing
@testable import FitMatch

/// Injected RPC boundary evidence. These tests do not apply SQL or write to a
/// connected server; the real coordinator, ViewModel and comparison actions run.
@MainActor
struct FitMatchUserSizeRecoveryTests {
    @Test func delayedPhotoTransferIsRejectedAfterContextAccountOrCancellationChange() async throws {
        for change in ["context", "account", "cancel", "unchanged"] {
            let viewModel = ShoppingProductViewModel()
            let gate = JourneyAsyncGate()
            let contextID = viewModel.sizeRecoveryContextID
            let ownerID = UUID()
            var currentUser: UUID? = ownerID
            let expected = Data([1, 2, 3])
            let pending = Task { @MainActor in
                await FitMatchSizeTableRecoveryAction.loadImage(
                    contextID: contextID, viewModel: viewModel, userID: ownerID,
                    currentUserID: { currentUser }, load: {
                        await gate.wait()
                        return expected
                    }
                )
            }
            await gate.waitForArrival(atLeast: 1)
            if change == "context" { viewModel.cancelProductLoading() }
            if change == "account" { currentUser = UUID() }
            if change == "cancel" { pending.cancel() }
            await gate.open()
            let result = await pending.value
            #expect(result == (change == "unchanged" ? expected : nil))
        }
    }

    @Test func coordinatorRequiresExplicitReadbackBeforeFreshReadyRuntime() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture, initialState: "measurements_required")
        let request = recoveryRequest(fixture: fixture)
        let result = try await FitMatchServerAuthorityCoordinator(remote: remote).recoverUserSize(
            request: request, targetRequest: try #require(fixture.parsedProduct().fitMatchDatabaseResolutionRequest())
        )
        #expect(result.receipt.requestPayload == request)
        #expect(result.authority.productID == fixture.productID)
        #expect(result.authority.sourceObservationID == request.sourceObservationID)
        #expect(result.authority.comparisonReadiness == .ready)
        #expect(await remote.events == ["recovery_submit", "recovery_readback", "runtime"])
    }

    @Test func coordinatorRejectsReadbackIdentityOrPayloadMismatchBeforeRuntime() async throws {
        for field in ["request_id", "owner_id", "product_id", "variant_id", "official_size_id", "size_id", "identity_kind", "request_payload"] {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let remote = try UserSizeRecoveryRemote(fixture: fixture, readbackFault: field)
            await #expect(throws: FitMatchUserSizeRecoveryError.self) {
                _ = try await FitMatchServerAuthorityCoordinator(remote: remote).recoverUserSize(
                    request: recoveryRequest(fixture: fixture),
                    targetRequest: try #require(fixture.parsedProduct().fitMatchDatabaseResolutionRequest())
                )
            }
            #expect(await remote.events == ["recovery_submit", "recovery_readback"])
        }
    }

    @Test func customReadbackCannotReplaceTheServerSizeIssuedBySave() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture, readbackFault: "size_id")
        let official = recoveryRequest(fixture: fixture)
        let custom = FitMatchUserSizeRecoveryRequest(
            requestID: official.requestID, ownerID: official.ownerID, productID: official.productID,
            variantID: official.variantID, officialSizeID: nil, sourceObservationID: official.sourceObservationID,
            inputSource: official.inputSource, sizeLabel: official.sizeLabel,
            measurements: official.measurements, originalRows: official.originalRows
        )
        await #expect(throws: FitMatchUserSizeRecoveryError.self) {
            _ = try await FitMatchServerAuthorityCoordinator(remote: remote).recoverUserSize(
                request: custom, targetRequest: try #require(fixture.parsedProduct().fitMatchDatabaseResolutionRequest())
            )
        }
        #expect(await remote.events == ["recovery_submit", "recovery_readback"])
    }

    @Test func coordinatorRejectsWrongRuntimeIdentityOwnerProvenanceAndValues() async throws {
        for field in ["variant_id", "size_id", "recovery_request_id", "owner_user_id", "identity_kind", "value", "unit_code", "basis_code", "semantic_conflict_count", "duplicate_code", "resolution_path", "missing_resolution_path"] {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let remote = try UserSizeRecoveryRemote(fixture: fixture, runtimeFault: field)
            await #expect(throws: FitMatchUserSizeRecoveryError.self) {
                _ = try await FitMatchServerAuthorityCoordinator(remote: remote).recoverUserSize(
                    request: recoveryRequest(fixture: fixture),
                    targetRequest: try #require(fixture.parsedProduct().fitMatchDatabaseResolutionRequest())
                )
            }
            #expect(await remote.events == ["recovery_submit", "recovery_readback", "runtime"])
        }
    }

    @Test func recoveredRuntimeMayRetainDistinctUntouchedOfficialMeasurements() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture, runtimeFault: "extra_official")
        let request = recoveryRequest(fixture: fixture)
        let result = try await FitMatchServerAuthorityCoordinator(remote: remote).recoverUserSize(
            request: request, targetRequest: try #require(fixture.parsedProduct().fitMatchDatabaseResolutionRequest())
        )
        let variant = try #require(result.authority.runtime.vnext?.variants.first)
        let size = try #require(variant.sizes.first)
        #expect(size.canonicalMeasurements.measurements.count == 3)
        #expect(size.canonicalMeasurements.measurements.contains {
            $0.measurementCode == "back_length" && $0.value == 70
        })
        #expect(result.authority.comparisonReadiness == .ready)
    }

    @Test func sizesAndMeasurementsRequiredBecomeReadyOnlyAfterPersistedRecovery() async throws {
        for initialState in ["sizes_required", "measurements_required"] {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let remote = try UserSizeRecoveryRemote(fixture: fixture, initialState: initialState)
            let (viewModel, selected) = try await loadedRecovery(fixture: fixture, remote: remote)
            #expect(viewModel.serverComparisonReadiness?.isReady == false)
            #expect(viewModel.recoverySelectedSizeID == nil)
            let outcome = await complete(selected, viewModel: viewModel)
            let submitted = try #require(await remote.requests.first)
            let expectedID = submitted.officialSizeID ?? UserSizeRecoveryContractFixture.recoveredSizeID
            #expect(outcome == .completed(selectedSizeID: expectedID))
            #expect(viewModel.serverComparisonReadiness == .ready)
            #expect(viewModel.recoverySelectedSizeID == expectedID)
            #expect(viewModel.sizeOptions.contains { $0.id == expectedID })
            #expect(submitted.ownerID == UserSizeRecoveryContractFixture.ownerID)
            #expect(submitted.inputSource == "USER_MANUAL")
            #expect(submitted.originalRows.isEmpty == false)
            #expect(submitted.originalRows.contains { $0.value == 51 && $0.rawValueText == "51" && $0.unitCode == "cm" })
            #expect(submitted.originalRows.contains { $0.value == 48 && $0.rawValueText == "48" && $0.unitCode == "cm" })
            #expect(submitted.measurements.contains { $0.fitmatchMeasurementCode == "chest_width" && $0.value == 51 })
            let recoveredForm = try #require(viewModel.sizeOptions.first { $0.id == expectedID })
            let userRow = try #require(recoveredForm.parsedMeasurementRecords.first {
                $0.canonicalMeasurementCode == "chest_width" && $0.methodSource == "user_size_recovery"
            })
            #expect(userRow.inputSource == .transcribedSizeChart)
            #expect(userRow.evidenceLevel == .fitmatchDefined)
            #expect(userRow.rawLabel == "가슴단면")
            #expect(userRow.rawValueText == "51")
            #expect(await remote.events == ["observation", "runtime", "recovery_submit", "recovery_readback", "runtime"])
        }
    }

    @Test func editedOCRValuesAndOriginalOCRRowsStaySeparateFromRetailerObservation() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture)
        let (viewModel, initial) = try await loadedRecovery(fixture: fixture, remote: remote)
        var selected = initial
        selected.parsedMeasurementRecords = [.init(
            value: 49, measurementCode: .chestWidthPitToPit, displayKind: .chest,
            methodSource: "user_ocr", inputSource: .transcribedSizeChart,
            rawCode: "ocr-chest", rawLabel: "OCR 가슴", rawValueText: "49",
            evidenceLevel: .officialText, semanticStatus: .mapped
        )]
        viewModel.sizeOptions = [selected]
        #expect(await FitMatchSizeTableRecoveryAction.complete(
            selectedSize: selected, viewModel: viewModel, userID: UserSizeRecoveryContractFixture.ownerID,
            currentUserID: { UserSizeRecoveryContractFixture.ownerID }, inputSource: "USER_OCR"
        ) == .completed(selectedSizeID: fixture.productSizeID))
        let request = try #require(await remote.requests.first)
        #expect(request.inputSource == "USER_OCR")
        #expect(request.originalRows.count == 1)
        #expect(request.originalRows.first?.rawCode == "ocr-chest")
        #expect(request.originalRows.first?.rawValueText == "49")
        #expect(request.originalRows.first?.value == 49)
        #expect(request.measurements.contains { $0.fitmatchMeasurementCode == "chest_width" && $0.value == 51 })
        #expect(await remote.events.filter { $0 == "observation" }.count == 1)
    }

    @Test func lostSubmitResponseRetriesTheSameRequestAndPreservesEditedInput() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture, loseFirstSaveResponse: true)
        let (viewModel, selected) = try await loadedRecovery(fixture: fixture, remote: remote)
        let before = viewModel.sizeOptions
        guard case .blocked = await complete(selected, viewModel: viewModel) else {
            Issue.record("Lost submit response must not complete recovery")
            return
        }
        #expect(viewModel.sizeOptions == before)
        #expect(viewModel.recoverySelectedSizeID == nil)
        #expect(viewModel.serverComparisonReadiness == .measurementsRequired)
        #expect(await complete(selected, viewModel: viewModel) == .completed(selectedSizeID: fixture.productSizeID))
        let requests = await remote.requests
        try #require(requests.count == 2)
        #expect(requests[0] == requests[1])
        #expect(await remote.events.filter { $0 == "recovery_readback" }.count == 1)
    }

    @Test func ambiguousSaveRejectsChangedInputWithoutCreatingAnotherRequest() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture, loseFirstSaveResponse: true)
        let (viewModel, selected) = try await loadedRecovery(fixture: fixture, remote: remote)
        _ = await complete(selected, viewModel: viewModel)
        var edited = selected
        edited.chest = "53.5"
        viewModel.sizeOptions = [edited]
        guard case .blocked = await complete(edited, viewModel: viewModel) else {
            Issue.record("Changed ambiguous input must remain pending")
            return
        }
        #expect(await remote.requests.count == 1)
        #expect(viewModel.sizeOptions == [edited])
        #expect(viewModel.recoverySelectedSizeID == nil)
    }

    @Test func definiteRejectionPreservesInputAndPermitsAnEditedNewRequest() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = try UserSizeRecoveryRemote(fixture: fixture, rejectFirstSave: true)
        let (viewModel, selected) = try await loadedRecovery(fixture: fixture, remote: remote)
        let before = viewModel.sizeOptions
        guard case .blocked = await complete(selected, viewModel: viewModel) else {
            Issue.record("Definite rejection must not complete recovery")
            return
        }
        #expect(viewModel.sizeOptions == before)
        #expect(viewModel.recoverySelectedSizeID == nil)
        #expect(await remote.events == ["observation", "runtime", "recovery_submit"])
        var edited = selected
        edited.chest = "53.5"
        viewModel.sizeOptions = [edited]
        #expect(await complete(edited, viewModel: viewModel) == .completed(selectedSizeID: fixture.productSizeID))
        let requests = await remote.requests
        try #require(requests.count == 2)
        #expect(requests[0].requestID != requests[1].requestID)
        #expect(requests[1].measurements.contains { $0.fitmatchMeasurementCode == "chest_width" && $0.value == 53.5 })
    }

    @Test func delayedRecoveryCannotApplyAfterAccountChangeOrLoadCancellation() async throws {
        for cancelsLoad in [false, true] {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let gate = JourneyAsyncGate()
            let remote = try UserSizeRecoveryRemote(fixture: fixture, saveGate: gate)
            let (viewModel, selected) = try await loadedRecovery(fixture: fixture, remote: remote)
            let before = viewModel.sizeOptions
            var currentUser: UUID? = UserSizeRecoveryContractFixture.ownerID
            let pending = Task { @MainActor in
                await FitMatchSizeTableRecoveryAction.complete(
                    selectedSize: selected, viewModel: viewModel,
                    userID: UserSizeRecoveryContractFixture.ownerID,
                    currentUserID: { currentUser }, inputSource: "USER_MANUAL"
                )
            }
            await gate.waitForArrival(atLeast: 1)
            if cancelsLoad { viewModel.cancelProductLoading() }
            else { currentUser = UUID() }
            await gate.open()
            guard case .blocked = await pending.value else {
                Issue.record("Stale account/load response must not complete recovery")
                continue
            }
            #expect(viewModel.recoverySelectedSizeID == nil)
            #expect(viewModel.hasServerComparisonReadyAuthority == false)
            #expect(viewModel.sizeOptions == before)
            #expect(viewModel.isSavingSizeRecovery == false)
        }
    }

    @Test func recoveredAuthorityContinuesThroughUserSelectedCandidateAndCompletion() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let record = fixture.closetRecord(for: reference)
        let base = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 4),
            runtimes: Array(repeating: try fixture.runtime(globalStatus: .confirmed), count: 6),
            closetResponses: [.init(state: "ready", items: [record])],
            candidateResponses: [try fixture.referenceResponse(reference: reference, closetItemID: record.closetItemID, decision: "MANUAL_EXTENDED")],
            eligibleResponses: [try fixture.eligible(reference: reference, closetItemID: record.closetItemID, mode: "MANUAL_EXTENDED", allowed: true, effectiveSource: nil, overrideRevision: nil)],
            beginResponses: [try fixture.begin(mode: "MANUAL_EXTENDED", personal: false, referenceClosetItemID: record.closetItemID, personalGarment: "tshirt", personalRevision: 0, personalCandidateFingerprint: nil, personalCandidateSetHash: nil, personalInputFingerprint: nil, personalEvidenceFingerprint: nil)],
            completionResponses: [try fixture.complete()]
        )
        let remote = try UserSizeRecoveryRemote(fixture: fixture, base: base)
        let (viewModel, selected) = try await loadedRecovery(fixture: fixture, remote: remote)
        #expect(await complete(selected, viewModel: viewModel) == .completed(selectedSizeID: fixture.productSizeID))
        // The exact Closet identity is explicitly chosen by the caller.
        let history = await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: reference)
        #expect(history != nil)
        let events = await remote.events
        var cursor = events.startIndex
        for event in ["recovery_submit", "recovery_readback", "runtime", "candidates", "begin", "complete"] {
            let index = try #require(events[cursor...].firstIndex(of: event))
            cursor = events.index(after: index)
        }
    }

    private func complete(_ form: ClothingSizeForm, viewModel: ShoppingProductViewModel) async -> FitMatchSizeTableRecoveryAction.Outcome {
        await FitMatchSizeTableRecoveryAction.complete(
            selectedSize: form, viewModel: viewModel, userID: UserSizeRecoveryContractFixture.ownerID,
            currentUserID: { UserSizeRecoveryContractFixture.ownerID }, inputSource: "USER_MANUAL"
        )
    }

    private func loadedRecovery(fixture: HeadlessJourneyFixture, remote: UserSizeRecoveryRemote) async throws -> (ShoppingProductViewModel, ClothingSizeForm) {
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(uniqloParser: HeadlessJourneyParser(product: fixture.parsedProduct())),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
        #expect(await viewModel.loadProductInfoFromURL())
        var selected = viewModel.sizeOptions.first ?? ClothingSizeForm(sizeName: "M")
        selected.shoulder = "48"
        selected.chest = "51"
        selected.parsedMeasurementRecords = []
        selected.totalLength = ""
        selected.sleeveLength = ""
        viewModel.sizeOptions = [selected]
        return (viewModel, selected)
    }

    private func recoveryRequest(fixture: HeadlessJourneyFixture) -> FitMatchUserSizeRecoveryRequest {
        let original = UserSizeRecoveryContractFixture.request(officialSizeID: fixture.productSizeID)
        return .init(requestID: original.requestID, ownerID: original.ownerID,
                     productID: fixture.productID, variantID: fixture.variantID,
                     officialSizeID: original.officialSizeID, sourceObservationID: original.sourceObservationID,
                     inputSource: original.inputSource, sizeLabel: original.sizeLabel,
                     measurements: original.measurements, originalRows: original.originalRows)
    }
}

private actor UserSizeRecoveryRemote: FitMatchServerAuthorityRemoteServicing {
    let fixture: HeadlessJourneyFixture
    let base: JourneyRecordingRemote
    let initialState: String
    let readbackFault: String?
    let runtimeFault: String?
    let saveGate: JourneyAsyncGate?
    var loseFirstSaveResponse: Bool
    var rejectFirstSave: Bool
    private(set) var events: [String] = []
    private(set) var requests: [FitMatchUserSizeRecoveryRequest] = []
    private var saved: FitMatchUserSizeRecoveryRequest?

    init(fixture: HeadlessJourneyFixture, initialState: String = "measurements_required",
         base: JourneyRecordingRemote? = nil, readbackFault: String? = nil,
         runtimeFault: String? = nil, loseFirstSaveResponse: Bool = false,
         rejectFirstSave: Bool = false, saveGate: JourneyAsyncGate? = nil) throws {
        self.fixture = fixture
        self.base = try base ?? JourneyRecordingRemote(runtimes: Array(repeating: fixture.runtime(globalStatus: .confirmed), count: 6))
        self.initialState = initialState
        self.readbackFault = readbackFault
        self.runtimeFault = runtimeFault
        self.loseFirstSaveResponse = loseFirstSaveResponse
        self.rejectFirstSave = rejectFirstSave
        self.saveGate = saveGate
    }

    func saveUserSizeRecovery(_ request: FitMatchUserSizeRecoveryRequest) async throws -> FitMatchUserSizeRecoveryReceipt {
        events.append("recovery_submit")
        requests.append(request)
        await saveGate?.wait()
        if rejectFirstSave {
            rejectFirstSave = false
            throw PostgrestError(code: "22023", message: "invalid user measurement")
        }
        saved = request
        if loseFirstSaveResponse {
            loseFirstSaveResponse = false
            throw URLError(.networkConnectionLost)
        }
        return try UserSizeRecoveryContractFixture.receipt(for: request)
    }

    func userSizeRecovery(requestID: UUID) async throws -> FitMatchUserSizeRecoveryReceipt {
        events.append("recovery_readback")
        let request = try #require(saved)
        #expect(requestID == request.requestID)
        let replacement: [String: Any]
        if let readbackFault {
            switch readbackFault {
            case "official_size_id": replacement = [readbackFault: NSNull()]
            case "identity_kind": replacement = [readbackFault: "USER_RECOVERY"]
            case "request_payload":
                var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
                payload["source_observation_id"] = UUID().uuidString
                replacement = [readbackFault: payload]
            default: replacement = [readbackFault: UUID().uuidString]
            }
        } else { replacement = [:] }
        return try UserSizeRecoveryContractFixture.receipt(for: request, replacing: replacement)
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductResolutionResponse {
        events.append("resolve")
        return try await base.resolve(request)
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws -> FitMatchProductObservationResponse {
        events.append("observation")
        return try await base.submitProductObservation(request)
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductRuntimeResponse {
        events.append("runtime")
        let runtime = try await base.fetchProductRuntime(request)
        return try recoveryRuntime(runtime, saved: saved)
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        events.append("list")
        return try await base.listClosetItems()
    }

    func findReferenceCandidates(targetProductID: UUID) async throws -> FitMatchReferenceCandidatesResponse {
        events.append("candidates")
        return try await base.findReferenceCandidates(targetProductID: targetProductID)
    }

    func eligibleCandidateSizes(referenceClosetItemID: UUID, targetProductID: UUID, targetVariantID: UUID, manualExplicit: Bool) async throws -> VNextEligibleCandidateSizesDTO {
        events.append("eligible")
        return try await base.eligibleCandidateSizes(referenceClosetItemID: referenceClosetItemID, targetProductID: targetProductID, targetVariantID: targetVariantID, manualExplicit: manualExplicit)
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws -> FitMatchBeginComparisonResponse {
        events.append("begin")
        return try await base.beginComparison(request)
    }

    func completeVNextComparison(comparisonID: UUID, payload: VNextComparisonCompletionPayload) async throws -> VNextCompleteComparisonDTO {
        events.append("complete")
        return try await base.completeVNextComparison(comparisonID: comparisonID, payload: payload)
    }

    private func recoveryRuntime(_ runtime: FitMatchProductRuntimeResponse, saved: FitMatchUserSizeRecoveryRequest?) throws -> FitMatchProductRuntimeResponse {
        let state = saved == nil ? initialState : "ready"
        var measurements: [[String: Any]] = saved?.measurements.map {
            ["fitmatch_measurement_code": $0.fitmatchMeasurementCode, "value": $0.value,
             "unit_code": $0.unitCode, "basis_code": $0.basisCode as Any? ?? NSNull(),
             "source_measurement_code": $0.fitmatchMeasurementCode,
             "resolution_path": saved!.inputSource, "raw_label": $0.rawLabel, "raw_value_text": $0.rawValueText]
        } ?? []
        var size: [String: Any] = [
            "id": (saved?.officialSizeID ?? (saved == nil ? fixture.productSizeID : UserSizeRecoveryContractFixture.recoveredSizeID)).uuidString,
            "source_size_key": "M", "size_label": "M", "availability": ["status": "AVAILABLE"]
        ]
        if let saved {
            size["recovery_request_id"] = saved.requestID.uuidString
            size["owner_user_id"] = saved.ownerID.uuidString
            size["identity_kind"] = saved.officialSizeID == nil ? "USER_RECOVERY" : "RETAILER_SIZE"
        }
        var conflictCount = 0
        if let runtimeFault, saved != nil {
            switch runtimeFault {
            case "resolution_path": measurements[0]["resolution_path"] = "RETAILER_API"
            case "missing_resolution_path": measurements[0].removeValue(forKey: "resolution_path")
            case "duplicate_code": measurements.append(measurements[0])
            case "extra_official": measurements.append([
                "fitmatch_measurement_code": "back_length", "value": 70.0,
                "unit_code": "cm", "basis_code": "LENGTH", "source_measurement_code": "official-body-length"
            ])
            case "value": measurements[0]["value"] = 999.0
            case "unit_code": measurements[0]["unit_code"] = "inch"
            case "basis_code": measurements[0]["basis_code"] = "CIRCUMFERENCE"
            case "semantic_conflict_count": conflictCount = 1
            case "identity_kind": size[runtimeFault] = "OTHER"
            case "size_id": size["id"] = UUID().uuidString
            case "variant_id": break
            default: size[runtimeFault] = UUID().uuidString
            }
        }
        size["canonical_measurements"] = ["measurements": measurements, "semantic_conflict_count": conflictCount]
        let variant: [String: Any] = [
            "id": runtimeFault == "variant_id" ? UUID().uuidString : fixture.variantID.uuidString,
            "source_variant_key": "__default__", "sizes": saved == nil && initialState == "sizes_required" ? [] : [size]
        ]
        let product: [String: Any] = [
            "id": fixture.productID.uuidString, "source_code": "uniqlo", "source_product_key": fixture.productCode,
            "product_name": "Headless target", "classification_status": "CONFIRMED", "product_structure_code": "SINGLE",
            "audience_code": "MEN", "category_code": "tops", "garment_type_code": "tshirt", "comparison_policy_code": "tshirt",
            "sleeve_length_code": "short_sleeve", "resolver_version": "headless-resolver-v1", "input_fingerprint": "input-v1"
        ]
        let effective: [String: Any] = [
            "product_id": fixture.productID.uuidString, "state": "GLOBAL_CONFIRMED", "classification_status": "CONFIRMED",
            "effective_source": "GLOBAL_CONFIRMED", "audience_code": "MEN", "category_code": "tops", "garment_type_code": "tshirt",
            "comparison_policy_code": "tshirt", "sleeve_length_code": "short_sleeve", "product_structure_code": "SINGLE",
            "effective_authority_fingerprint": "effective-0", "effective_contract_version": "effective-v1"
        ]
        let object: [String: Any] = [
            "found": true, "product": product, "variants": [variant], "effective_classification": effective,
            "readiness": ["status": saved == nil ? initialState.uppercased() : "READY", "ready_size_count": saved == nil ? 0 : 1, "policy_metric_count": 1],
            "comparison_group": ["status": "COMPARABLE", "group_code": "A", "source": "RETAILER_CATEGORY", "comparison_policy_code": "tshirt", "policy_version": "fixture-v1", "authority_version": "fixture-v1", "authority_fingerprint": "fixture-group-a"]
        ]
        let exact = try JSONDecoder().decode(VNextProductRuntimeDTO.self, from: JSONSerialization.data(withJSONObject: object))
        return .init(runtimeState: state, comparisonReady: saved != nil, product: runtime.product,
                     classification: runtime.classification, variants: runtime.variants, vnext: exact)
    }
}
