import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// Continuous manual-Closet owner tests. The actor below is an in-memory RPC
/// boundary, not a second implementation of server authorization or scoring.
@MainActor
struct FitMatchReleaseLifecycleTests {
    @Test func manualRegistrationReadAsyncEditReadDeleteReadPreservesExactIdentity() async throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.defaultsName) }
        let targetDraft = try manualDraft(name: "연속 검사 대상", chest: "50")
        let controlDraft = try manualDraft(name: "보존할 다른 옷", chest: "61")
        let target = try await harness.coordinator.registerManualServerFirst(
            targetDraft, userID: harness.userID, modelContext: harness.context)
        let control = try await harness.coordinator.registerManualServerFirst(
            controlDraft, userID: harness.userID, modelContext: harness.context)
        let targetID = target.id
        let controlID = control.id
        let before = try await harness.remote.listClosetItems()
        let targetReceipt = try #require(before.items.first { $0.clientItemID == targetID })
        let controlReceipt = try #require(before.items.first { $0.clientItemID == controlID })
        #expect(targetID == targetDraft.id)
        #expect(targetReceipt.productID == nil)
        #expect(targetReceipt.variantID == nil)
        #expect(targetReceipt.productSizeID == nil)
        #expect(try reread(targetID, in: harness.container)?.chest == 50)
        #expect(try reread(controlID, in: harness.container)?.chest == 61)

        let editForm = AddClosetItemViewModel(item: target)
        editForm.productName = "서버 확인된 수정 이름"
        editForm.chest = "56"
        let editedDraft = try #require(editForm.makeUserFit())
        #expect(editedDraft.id != targetID)
        let editOutcome = await harness.coordinator.saveManualClosetEdit(
            item: target, editedItem: editedDraft, userID: harness.userID,
            modelContext: harness.context)
        #expect(editOutcome == .saved)
        let afterEdit = try await harness.remote.listClosetItems()
        let editedReceipt = try #require(afterEdit.items.first { $0.clientItemID == targetID })
        #expect(editedReceipt.closetItemID == targetReceipt.closetItemID)
        #expect(editedReceipt.clientItemID == targetID)
        #expect(editedReceipt.measurements["chest_width"] == 56)
        #expect(editedReceipt.productName == "서버 확인된 수정 이름")
        #expect(afterEdit.items.first { $0.clientItemID == controlID } == controlReceipt)
        let editedReadResult = try reread(targetID, in: harness.container)
        let editedRead = try #require(editedReadResult)
        #expect(editedRead.chest == 56)
        #expect(editedRead.productName == "서버 확인된 수정 이름")
        #expect(try reread(controlID, in: harness.container)?.chest == 61)

        let deletion = await FitMatchClosetDeletionAction.delete(item: target,
            histories: [], in: harness.context, comparisonSync: nil,
            closetSync: harness.coordinator)
        #expect(deletion == .deleted)
        let afterDelete = try await harness.remote.listClosetItems()
        #expect(afterDelete.items == [controlReceipt])
        #expect(try reread(targetID, in: harness.container) == nil)
        #expect(try reread(controlID, in: harness.container)?.chest == 61)
        let operations = await harness.remote.mutations()
        #expect(operations == [
            .init(kind: "upsert", clientID: targetID, serverID: targetReceipt.closetItemID),
            .init(kind: "upsert", clientID: controlID, serverID: controlReceipt.closetItemID),
            .init(kind: "update", clientID: targetID, serverID: targetReceipt.closetItemID),
            .init(kind: "delete", clientID: targetID, serverID: targetReceipt.closetItemID)
        ])
    }

    @Test func asyncManualMeasurementEditRereadsBeforeExplicitNewComparison() async throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.defaultsName) }
        let draft = try manualDraft(name: "수정 후 비교할 옷", chest: "50")
        let item = try await harness.coordinator.registerManualServerFirst(
            draft, userID: harness.userID, modelContext: harness.context)
        let before = try #require((try await harness.remote.listClosetItems()).items.first)
        let editForm = AddClosetItemViewModel(item: item)
        editForm.chest = "56"
        let editedDraft = try #require(editForm.makeUserFit())
        let outcome = await harness.coordinator.saveManualClosetEdit(item: item,
            editedItem: editedDraft, userID: harness.userID, modelContext: harness.context)
        #expect(outcome == .saved)
        let current = try #require((try await harness.remote.listClosetItems()).items.first)
        let rereadResult = try reread(item.id, in: harness.container)
        let rereadItem = try #require(rereadResult)
        #expect(current.closetItemID == before.closetItemID)
        #expect(current.clientItemID == before.clientItemID)
        #expect(before.measurements["chest_width"] == 50)
        #expect(current.measurements["chest_width"] == 56)
        #expect(rereadItem.chest == 56)

        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let candidates = [HeadlessServerCandidateFixture(
            productSizeID: fixture.productSizeID, sizeLabel: "M",
            metrics: [.init(code: "chest_width_pit_to_pit", referenceValue: 56, targetValue: 57)],
            runtimeMetrics: [.init(code: "chest_width", referenceValue: 56, targetValue: 57)])]
        let runtime = try fixture.runtime(globalStatus: .confirmed, runtimeCandidates: candidates)
        let candidateResponse = try fixture.referenceResponse(reference: rereadItem,
            closetItemID: current.closetItemID, decision: "MANUAL_EXTENDED")
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 3),
            runtimes: Array(repeating: runtime, count: 3),
            closetResponses: [.init(state: "ready", items: [current])],
            candidateResponses: [candidateResponse, candidateResponse],
            eligibleResponses: [try fixture.eligible(referenceClosetItemID: current.closetItemID,
                candidates: candidates, allowed: true, decision: "MANUAL_EXTENDED")],
            beginResponses: [try fixture.begin(mode: "MANUAL_EXTENDED", personal: false,
                referenceClosetItemID: current.closetItemID, candidates: candidates,
                policyMetricCodes: ["chest_width_pit_to_pit"])],
            completionResponses: [try fixture.complete()])
        let viewModel = ShoppingProductViewModel(initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(musinsaParser: HeadlessJourneyParser(product: fixture.parsedProduct())),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote))
        #expect(await viewModel.loadProductInfoFromURL())
        let planResult = await viewModel.loadServerReferenceSelectionPlan(localClientItemIDs: [rereadItem.id])
        let planDiagnostic = "\(viewModel.errorMessage ?? "no error"); calls=\(await remote.calls())"
        let plan = try #require(planResult, Comment(rawValue: planDiagnostic))
        #expect(plan.candidates.map(\.clientItemID) == [rereadItem.id])
        #expect(plan.candidates.map(\.closetItemID) == [current.closetItemID])
        let discoveryCalls = await remote.calls()
        #expect(!discoveryCalls.contains("eligible_sizes"))
        #expect(!discoveryCalls.contains("begin_comparison"))
        #expect(!discoveryCalls.contains("complete_comparison"))
        #expect(viewModel.recommendation == nil)

        let result = await viewModel.calculateTemporaryRecommendation(selectedReferenceItem: rereadItem)
        let diagnostic = "\(viewModel.errorMessage ?? "no error"); calls=\(await remote.calls())"
        let history = try #require(result, Comment(rawValue: diagnostic))
        defer { VNextComparisonSessionStore.shared.remove(historyID: history.id) }
        let batch = try #require(VNextComparisonSessionStore.shared.analysis(for: history.id))
        #expect(history.userFit.id == item.id)
        #expect(batch.comparisonID == fixture.comparisonID)
        #expect(batch.recommended.productSizeID == fixture.productSizeID)
        #expect(batch.recommended.result.comparedItems.map(\.referenceValue) == [56])
        #expect(batch.recommended.result.comparedItems.map(\.productValue) == [57])
        #expect(before.measurements["chest_width"] == 50)
        let calls = await remote.calls()
        #expect(calls.filter { $0 == "eligible_sizes" }.count == 1)
        #expect(calls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(calls.filter { $0 == "complete_comparison" }.count == 1)
    }

    private func manualDraft(name: String, chest: String) throws -> UserFit {
        let form = AddClosetItemViewModel(prefillCategory: .top,
            prefillDetailCategory: .shortSleeve, prefillGender: .men,
            prefillBrand: "QA", prefillProductName: name)
        form.measurementEntrySource = .fitmatchMeasured
        form.chest = chest
        form.shoulder = "48"
        form.totalLength = "70"
        form.sleeveLength = "24"
        form.size = "M"
        return try #require(form.makeUserFit())
    }

    private func reread(_ id: UUID, in container: ModelContainer) throws -> UserFit? {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<UserFit>(predicate: #Predicate { $0.id == id })).first
    }

    private func makeHarness() throws -> LifecycleHarness {
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let name = "FitMatchReleaseLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let remote = LifecycleClosetRemote()
        let coordinator = FitMatchClosetSyncCoordinator(remote: remote, defaults: defaults)
        let userID = UUID()
        coordinator.prepareForAuthenticatedUser(userID)
        _ = try coordinator.prepareLocalCache(for: userID, modelContext: context)
        return LifecycleHarness(container: container, context: context,
            defaults: defaults, defaultsName: name, userID: userID,
            remote: remote, coordinator: coordinator)
    }
}

@MainActor
private struct LifecycleHarness {
    let container: ModelContainer
    let context: ModelContext
    let defaults: UserDefaults
    let defaultsName: String
    let userID: UUID
    let remote: LifecycleClosetRemote
    let coordinator: FitMatchClosetSyncCoordinator
}

private struct LifecycleMutation: Equatable, Sendable {
    let kind: String
    let clientID: UUID
    let serverID: UUID
}

private actor LifecycleClosetRemote: FitMatchClosetRemoteServicing {
    private var rows: [UUID: FitMatchClosetItemRecord] = [:]
    private var mutationLog: [LifecycleMutation] = []
    func mutations() -> [LifecycleMutation] { mutationLog }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        .init(state: "ready", items: rows.values.sorted { $0.clientItemID.uuidString < $1.clientItemID.uuidString })
    }

    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws -> FitMatchUpsertClosetItemResponse {
        guard request.productID == nil, request.productVariantID == nil, request.productSizeID == nil else {
            throw LifecycleRemoteError.unexpectedLinkedIdentity
        }
        let serverID = rows[request.clientItemID]?.closetItemID ?? UUID()
        let record = try receipt(request: request, serverID: serverID, revision: 1)
        rows[request.clientItemID] = record
        mutationLog.append(.init(kind: "upsert", clientID: request.clientItemID, serverID: serverID))
        return accepted(record)
    }

    func updateClosetItem(_ request: FitMatchUpsertClosetItemRequest,
        closetItemID: UUID) async throws -> FitMatchUpsertClosetItemResponse {
        guard let before = rows[request.clientItemID], before.closetItemID == closetItemID else {
            throw LifecycleRemoteError.identityMismatch
        }
        let record = try receipt(request: request, serverID: closetItemID, revision: before.syncRevision + 1)
        rows[request.clientItemID] = record
        mutationLog.append(.init(kind: "update", clientID: request.clientItemID, serverID: closetItemID))
        return accepted(record)
    }

    func deleteClosetItem(closetItemID: UUID) async throws -> FitMatchDeleteClosetItemResponse {
        guard let current = rows.values.first(where: { $0.closetItemID == closetItemID }) else {
            throw LifecycleRemoteError.identityMismatch
        }
        rows.removeValue(forKey: current.clientItemID)
        mutationLog.append(.init(kind: "delete", clientID: current.clientItemID, serverID: closetItemID))
        return .init(closetItemID: closetItemID, deletedAt: "2026-10-02T00:00:00Z")
    }

    private func accepted(_ record: FitMatchClosetItemRecord) -> FitMatchUpsertClosetItemResponse {
        .init(closetItemID: record.closetItemID, clientItemID: record.clientItemID,
            syncRevision: record.syncRevision, classificationStatus: "confirmed",
            categoryCode: record.categoryCode, detailCode: record.detailCode,
            familyCode: record.familyCode, lengthCode: record.lengthCode,
            bodyLengthCode: record.bodyLengthCode, isReference: false)
    }

    /// The issued group A is fixed fixture authority for these upper-body
    /// rows. This stub deliberately does not infer any group or score policy.
    private func receipt(request: FitMatchUpsertClosetItemRequest,
        serverID: UUID, revision: Int) throws -> FitMatchClosetItemRecord {
        let p = request.item
        // The real RPC transport canonicalizes these manual fields before
        // storage. Return canonical receipt keys using that existing exact
        // mapper, rather than echoing local expanded codes as server facts.
        let canonicalRecords = try p.measurementRecords.map { record in
            guard let code = FitMatchCanonicalMeasurementCode.canonicalCode(
                forTransportRawCode: record.measurementCode) else {
                throw LifecycleRemoteError.unexpectedMeasurement
            }
            return FitMatchClosetMeasurementRecordPayload(value: record.value,
                unit: record.unit, measurementCode: code, displayKind: record.displayKind,
                methodSource: record.methodSource, methodProfile: record.methodProfile,
                inputSource: record.inputSource, standardVersion: record.standardVersion,
                mappingVersion: record.mappingVersion, rawCode: record.rawCode,
                rawLabel: record.rawLabel, rawInfo: record.rawInfo,
                rawValueText: record.rawValueText, evidenceLevel: record.evidenceLevel,
                semanticStatus: record.semanticStatus)
        }
        guard !canonicalRecords.isEmpty,
              Set(canonicalRecords.map(\.measurementCode)).count == canonicalRecords.count else {
            throw LifecycleRemoteError.unexpectedMeasurement
        }
        let measurements = Dictionary(uniqueKeysWithValues:
            canonicalRecords.map { ($0.measurementCode, $0.value) })
        return .init(closetItemID: serverID, clientItemID: request.clientItemID,
            productID: nil, externalProductID: nil, productAudience: nil,
            sourceCategoryCodes: [], variantID: nil, productSizeID: nil,
            brand: p.brand, productName: p.productName, sizeName: p.sizeName,
            genderCode: p.genderCode, source: p.source, sourceCategoryPath: p.sourceCategoryPath,
            productURL: nil, imageURL: p.imageURL, measurements: measurements,
            measurementRecords: canonicalRecords, fitMemo: p.fitMemo,
            fitPreferenceCode: p.fitPreferenceCode, satisfaction: p.satisfaction,
            isReference: false, classificationStatus: "confirmed", classificationSource: "manual_override",
            categoryCode: p.categoryCode, detailCode: p.detailCode,
            closetDetailCodeSnapshot: request.closetDetailCodeSnapshot,
            canonicalCategoryCode: p.categoryCode, canonicalDetailCode: p.detailCode,
            familyCode: p.familyCode, lengthCode: p.lengthCode, bodyLengthCode: p.bodyLengthCode,
            comparisonGroupCode: "A", comparisonGroupSource: "USER_SELECTED",
            comparisonGroupPolicyVersion: "lifecycle-fixture-v1", classificationSnapshot: [:],
            clientSnapshot: p.clientSnapshot, clientCreatedAt: p.clientCreatedAt,
            clientUpdatedAt: p.clientUpdatedAt, syncRevision: revision,
            createdAt: p.clientCreatedAt, updatedAt: p.clientUpdatedAt)
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductResolutionResponse {
        throw LifecycleRemoteError.unexpectedProductRequest
    }
    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws -> FitMatchProductObservationResponse {
        throw LifecycleRemoteError.unexpectedProductRequest
    }
    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductRuntimeResponse {
        throw LifecycleRemoteError.unexpectedProductRequest
    }
    func findReferenceCandidates(targetProductID: UUID) async throws -> FitMatchReferenceCandidatesResponse {
        throw LifecycleRemoteError.unexpectedProductRequest
    }
}

private enum LifecycleRemoteError: Error {
    case unexpectedProductRequest
    case unexpectedLinkedIdentity
    case identityMismatch
    case unexpectedMeasurement
}
