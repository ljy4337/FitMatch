import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchComparisonSyncCoordinatorTests {
    @Test func pendingServerSnapshotRecoversThenHydratesExactlyOnce() async throws {
        let fixture = try ComparisonHistoryFixture()
        let remote = ComparisonHistoryRemoteStub(
            pending: fixture.pending,
            completed: fixture.completed
        )
        let defaultsName = "FitMatchComparisonSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)

        await coordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            products: [],
            closetItems: [],
            modelContext: context
        )

        #expect(coordinator.state == .synced)
        #expect(await remote.completeCallCount() == 1)
        let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let history = try #require(histories.first)
        #expect(histories.count == 1)
        #expect(history.id == fixture.clientComparisonID)
        #expect(history.recommendedSize.id == fixture.productSizeID)
        #expect(history.recommendationScore == 95)
        #expect(history.comparisonMethod == "서버 승인 직접 비교")

        await coordinator.synchronize(
            userID: fixture.userID,
            histories: histories,
            products: try context.fetch(FetchDescriptor<Product>()),
            closetItems: try context.fetch(FetchDescriptor<UserFit>()),
            modelContext: context
        )
        #expect(await remote.completeCallCount() == 1)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
    }

    @Test func legacyLocalHistoryIsReadOnlyAndNeverUploaded() async throws {
        let history = makeLegacyHistory()
        let remote = ComparisonHistoryRemoteStub(pending: nil, completed: nil)
        let defaultsName = "FitMatchComparisonSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)

        await coordinator.synchronize(userID: UUID(), histories: [history])

        #expect(coordinator.state == .synced)
        #expect(await remote.completeCallCount() == 0)
        #expect(await remote.historyFetchCount() == 1)
    }

    @Test func orphanedServerApprovedLocalCacheFailsClosed() async throws {
        let history = makeLegacyHistory()
        history.comparisonMethod = "서버 승인 직접 비교"
        let remote = ComparisonHistoryRemoteStub(pending: nil, completed: nil)
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote)

        await coordinator.synchronize(userID: UUID(), histories: [history])

        #expect(coordinator.state == .parityWarning)
        #expect(coordinator.parityWarningCount == 1)
        #expect(await remote.completeCallCount() == 0)
    }

    /// CM-015: a delayed A history fetch must be discarded once the app has
    /// prepared B's user-owned cache.  A later B sync is queued through the
    /// same production coordinator; it cannot leave A's immutable history in
    /// B's observable SwiftData cache.
    @Test func overlappingAccountSwitchCannotHydrateOutgoingHistoryIntoNewAccount() async throws {
        let fixtureA = try ComparisonHistoryFixture()
        let fixtureB = try ComparisonHistoryFixture()
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let comparisonDefaultsName = "FitMatchComparisonSyncCoordinatorTests.OverlappingAccountSwitch.\(UUID().uuidString)"
        let comparisonDefaults = try #require(UserDefaults(suiteName: comparisonDefaultsName))
        defer { comparisonDefaults.removePersistentDomain(forName: comparisonDefaultsName) }
        let cacheDefaultsName = "FitMatchComparisonSyncCoordinatorTests.OverlappingCache.\(UUID().uuidString)"
        let cacheDefaults = try #require(UserDefaults(suiteName: cacheDefaultsName))
        defer { cacheDefaults.removePersistentDomain(forName: cacheDefaultsName) }

        let ownerA = UUID()
        let ownerB = UUID()
        let firstFetchGate = JourneyAsyncGate()
        let remote = ComparisonHistoryRemoteStub(
            pending: nil,
            completed: nil,
            historyResponses: [[fixtureA.completed], [fixtureB.completed]],
            historyGates: [1: firstFetchGate]
        )
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: comparisonDefaults)
        let cacheCoordinator = FitMatchClosetSyncCoordinator(defaults: cacheDefaults)

        #expect(
            try cacheCoordinator.prepareLocalCache(for: ownerA, modelContext: context)
                == .claimedEmptyOrUnownedCache
        )
        let oldSync = Task { @MainActor in
            await coordinator.synchronize(
                userID: ownerA,
                histories: [],
                modelContext: context
            )
        }
        await firstFetchGate.waitForArrival(atLeast: 1)

        #expect(
            try cacheCoordinator.prepareLocalCache(for: ownerB, modelContext: context)
                == .purgedForeignOwnerCache
        )
        // ContentView executes this production boundary in the same cache
        // preparation task, before B's comparison sync begins. It must make
        // the delayed A response stale immediately, not only after a later B
        // fetch happens to start.
        coordinator.prepareForAuthenticatedUser(ownerB)
        await coordinator.synchronize(
            userID: ownerB,
            histories: [],
            modelContext: context
        )
        await firstFetchGate.open()
        await oldSync.value

        let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        #expect(histories.map(\.id) == [fixtureB.clientComparisonID])
    }

    /// RX-015: a second same-user trigger that arrives during an in-flight
    /// history fetch gets its own follow-up production pass and hydrates the
    /// newest immutable server row exactly once.
    @Test func overlappingSameAccountHistorySyncUsesNewestFollowUpSnapshot() async throws {
        let fixture = try ComparisonHistoryFixture()
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let defaultsName = "FitMatchComparisonSyncCoordinatorTests.OverlappingSameAccount.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let firstFetchGate = JourneyAsyncGate()
        let remote = ComparisonHistoryRemoteStub(
            pending: nil,
            completed: nil,
            historyResponses: [[], [fixture.completed]],
            historyGates: [1: firstFetchGate]
        )
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)
        let userID = UUID()

        let first = Task { @MainActor in
            await coordinator.synchronize(userID: userID, histories: [], modelContext: context)
        }
        await firstFetchGate.waitForArrival(atLeast: 1)
        await coordinator.synchronize(userID: userID, histories: [], modelContext: context)
        await firstFetchGate.open()
        await first.value

        #expect(coordinator.state == .synced)
        #expect(
            try context.fetch(FetchDescriptor<RecommendationHistory>()).map(\.id)
                == [fixture.clientComparisonID]
        )
        #expect(await remote.historyFetchCount() == 2)
    }

    @Test func deletedReferenceHydratesAsHistoryOnlyForEveryAuthoritySource() async throws {
        let historyOnlyIdentity = UserFit.historyReferenceSnapshotSourceIdentity
        for classificationSource in [
            "USER_EXPLICIT",
            "USER_EDITED",
            "RETAILER_SNAPSHOT"
        ] {
            let fixture = try ComparisonHistoryFixture(
                classificationSource: classificationSource
            )
            let container = try inMemoryContainer()
            let context = ModelContext(container)
            _ = try VNextHistoryCacheHydrator().hydrateCompleted(
                [fixture.completed],
                existingHistories: [],
                existingProducts: [],
                existingClosetItems: [],
                modelContext: context
            )

            let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
            let items = try context.fetch(FetchDescriptor<UserFit>())
            let history = try #require(histories.first)
            let snapshot = try #require(items.first { $0.id == fixture.referenceClientItemID })

            #expect(histories.count == 1)
            #expect(history.userFit.id == fixture.referenceClientItemID)
            #expect(history.userFit.productName == "내 반팔 티셔츠")
            #expect(snapshot.canonicalSourceIdentity == historyOnlyIdentity)
            #expect(items.filter(\.isActiveClosetItem).isEmpty)
            #expect(snapshot.isRepresentative == false)
        }
    }

    @Test func completedServerHistoryHideSurvivesSyncAndModeledSecondSession() async throws {
        let fixture = try ComparisonHistoryFixture()
        let remote = ComparisonHistoryRemoteStub(pending: nil, completed: fixture.completed)
        let defaultsName = "FitMatchComparisonSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let firstContainer = try inMemoryContainer()
        let firstContext = ModelContext(firstContainer)
        let firstCoordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)
        await firstCoordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            modelContext: firstContext
        )
        let visibleHistory = try #require(
            firstContext.fetch(FetchDescriptor<RecommendationHistory>()).first
        )
        #expect(visibleHistory.isServerBackedVNextHistory)

        // HI-006 / HI-008 / HI-015: invoke the exact production action that
        // the History swipe-delete surface uses, not an equivalent test-side
        // hide/delete sequence.
        let deleteOutcome = await FitMatchHistoryVisibilityAction.delete(
            visibleHistory,
            in: firstContext,
            comparisonSync: firstCoordinator
        )
        #expect(deleteOutcome == .deleted)

        await firstCoordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            modelContext: firstContext
        )
        #expect(try firstContext.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(await remote.hiddenClientIDs() == Set([fixture.clientComparisonID]))

        let secondContainer = try inMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let secondCoordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)
        await secondCoordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            modelContext: secondContext
        )
        #expect(secondCoordinator.state == .synced)
        #expect(try secondContext.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
    }

    @Test func closetDeletionHidesAssociatedCompletedServerHistoryWithoutDeletingRemoteEvidence() async throws {
        let fixture = try ComparisonHistoryFixture()
        let remote = ComparisonHistoryRemoteStub(pending: nil, completed: fixture.completed)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote)
        let reference = UserFit(
            brandName: "내 브랜드",
            productName: "내 반팔 티셔츠",
            category: .top,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 50,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 3
        )
        reference.id = fixture.referenceClientItemID
        context.insert(reference)
        try context.save()

        await coordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            modelContext: context
        )
        let history = try #require(
            context.fetch(FetchDescriptor<RecommendationHistory>()).first
        )
        #expect(history.userFit.id == reference.id)
        #expect(history.isServerBackedVNextHistory)

        // CM-010 / HI-009: this is the same production action used by both
        // Closet delete surfaces.  Persist the user-owned hide first, then
        // remove local presentation/cache rows.  It never deletes the
        // immutable remote completed-comparison evidence.
        let outcome = await FitMatchClosetDeletionAction.delete(
            item: reference,
            histories: [history],
            in: context,
            comparisonSync: coordinator,
            closetSync: nil
        )
        #expect(outcome == .deleted)

        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(
            try context.fetch(FetchDescriptor<UserFit>())
                .filter(\.isActiveClosetItem)
                .isEmpty
        )
        #expect(await remote.completedHistoryRemainsImmutable())

        await coordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            modelContext: context
        )
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
    }

    @Test func closetDeletionActionRemovesOnlyTheRequestedActiveItemWhenNoHistoryExists() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let target = UserFit(
            brandName: "내 브랜드",
            productName: "삭제할 일반 옷",
            category: .top,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 50,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 3
        )
        let unrelated = UserFit(
            brandName: "내 브랜드",
            productName: "남아야 하는 옷",
            category: .bottom,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 100,
                sleeveLength: 0
            ),
            fitMemo: "",
            satisfaction: 3
        )
        context.insert(target)
        context.insert(unrelated)
        try context.save()

        // CM-008: the same production delete boundary used by MyCloset and
        // detail surfaces does not require a comparison-sync service when no
        // completed server History is associated with the item.
        let outcome = await FitMatchClosetDeletionAction.delete(
            item: target,
            histories: [],
            in: context,
            comparisonSync: nil,
            closetSync: nil
        )
        #expect(outcome == .deleted)
        let remaining = try context.fetch(FetchDescriptor<UserFit>())
        #expect(remaining.map(\.id) == [unrelated.id])
    }

    @Test func closetDeletionActionKeepsClosetAndHistoryWhenDurableHideFailsThenRetries() async throws {
        let fixture = try ComparisonHistoryFixture()
        let remote = ComparisonHistoryRemoteStub(
            pending: nil,
            completed: fixture.completed,
            hideError: .transportFailure
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote)
        let reference = UserFit(
            brandName: "내 브랜드",
            productName: "내 반팔 티셔츠",
            category: .top,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 50,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 3
        )
        reference.id = fixture.referenceClientItemID
        context.insert(reference)
        try context.save()

        await coordinator.synchronize(
            userID: fixture.userID,
            histories: [],
            modelContext: context
        )
        let history = try #require(
            context.fetch(FetchDescriptor<RecommendationHistory>()).first
        )

        let failed = await FitMatchClosetDeletionAction.delete(
            item: reference,
            histories: [history],
            in: context,
            comparisonSync: coordinator,
            closetSync: nil
        )
        #expect(failed == .serverHistoryHideFailed)
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
        #expect(await remote.visibilityRowCount() == 0)

        await remote.setHideError(nil)
        let retried = await FitMatchClosetDeletionAction.delete(
            item: reference,
            histories: [history],
            in: context,
            comparisonSync: coordinator,
            closetSync: nil
        )
        #expect(retried == .deleted)
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(await remote.completedHistoryRemainsImmutable())
    }

    @Test func historyDeletionActionKeepsLegacyRowsLocalAndDoesNotFabricateServerHide() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let history = makeLegacyHistory()
        context.insert(history)
        try context.save()

        let outcome = await FitMatchHistoryVisibilityAction.delete(
            history,
            in: context,
            comparisonSync: nil
        )
        #expect(outcome == .deleted)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
    }

    @Test func completedServerHistoryHideIsIdempotentAndRejectsUnknownIdentity() async throws {
        let fixture = try ComparisonHistoryFixture()
        let remote = ComparisonHistoryRemoteStub(pending: nil, completed: fixture.completed)
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote)

        try await coordinator.hideVNextComparisonHistories(
            clientComparisonIDs: [fixture.clientComparisonID, fixture.clientComparisonID]
        )
        try await coordinator.hideVNextComparisonHistories(
            clientComparisonIDs: [fixture.clientComparisonID]
        )

        #expect(await remote.hideCallCount() == 2)
        #expect(await remote.visibilityRowCount() == 1)
        #expect(await remote.lastHideWasIdempotent())

        await #expect(throws: ComparisonHistoryRemoteError.unknownComparison) {
            try await coordinator.hideVNextComparisonHistories(
                clientComparisonIDs: [UUID()]
            )
        }
    }

    @Test func failedServerHistoryHideLeavesLocalCacheUntouchedForRetry() async throws {
        let fixture = try ComparisonHistoryFixture()
        let remote = ComparisonHistoryRemoteStub(
            pending: nil,
            completed: fixture.completed,
            hideError: .transportFailure
        )
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let history = makeLegacyHistory()
        history.id = fixture.clientComparisonID
        history.comparisonSchemaVersion = 2
        history.comparisonMethod = "서버 승인 직접 비교"
        context.insert(history)
        try context.save()

        await #expect(throws: ComparisonHistoryRemoteError.transportFailure) {
            try await coordinator.hideVNextComparisonHistories(
                clientComparisonIDs: [history.id]
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
        #expect(await remote.visibilityRowCount() == 0)
    }

    @Test func localOnlyHistoryDoesNotClaimServerVisibilityAuthority() {
        #expect(!makeLegacyHistory().isServerBackedVNextHistory)
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeLegacyHistory() -> RecommendationHistory {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 51,
                totalLength: 69,
                sleeveLength: 22
            )
        )
        let product = Product(name: "과거 상품", category: .top, sizes: [size])
        let reference = UserFit(
            brandName: "과거",
            productName: "내 옷",
            category: .top,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 50,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 3
        )
        return RecommendationHistory(
            product: product,
            recommendedSize: size,
            userFit: reference,
            totalDifference: 1,
            measurementDifferences: GarmentMeasurements(
                shoulder: 0,
                chest: 1,
                totalLength: 0,
                sleeveLength: 0
            )
        )
    }
}

private struct ComparisonHistoryFixture: Sendable {
    let userID = UUID()
    let comparisonID = UUID()
    let clientComparisonID = UUID()
    let referenceClientItemID = UUID()
    let targetProductID = UUID()
    let targetVariantID = UUID()
    let productSizeID = UUID()
    let pending: VNextComparisonHistoryDTO
    let completed: VNextComparisonHistoryDTO

    init(classificationSource: String = "manual_override") throws {
        let identifiers = (
            comparisonID: comparisonID,
            clientComparisonID: clientComparisonID,
            referenceClientItemID: referenceClientItemID,
            targetProductID: targetProductID,
            targetVariantID: targetVariantID,
            productSizeID: productSizeID
        )
        pending = try Self.decode(
            Self.json(
                status: "PENDING",
                ids: identifiers,
                classificationSource: classificationSource
            )
        )
        completed = try Self.decode(
            Self.json(
                status: "COMPLETED",
                ids: identifiers,
                classificationSource: classificationSource
            )
        )
    }

    private static func json(
        status: String,
        ids: (
            comparisonID: UUID,
            clientComparisonID: UUID,
            referenceClientItemID: UUID,
            targetProductID: UUID,
            targetVariantID: UUID,
            productSizeID: UUID
        ),
        classificationSource: String
    ) -> String {
        let completedFields = status == "COMPLETED" ? """
          "recommended_product_size_id":"\(ids.productSizeID)",
          "recommended_size_label":"M",
          "fit_score":95,"reliability_level":2,"coverage_ratio":1,
          "engine_version":"fitmatch-ios-vnext-snapshot-v1",
          "result_evidence":{
            "recommended_product_size_id":"\(ids.productSizeID)",
            "score":95,"reliability":2,"coverage":1,
            "engine_version":"fitmatch-ios-vnext-snapshot-v1",
            "candidate_size_ranking":[{
              "product_size_id":"\(ids.productSizeID)","rank":1,"score":95
            }],
            "metric_evidence":[{
              "product_size_id":"\(ids.productSizeID)",
              "measurement_code":"chest_width_pit_to_pit",
              "reference_value":50,"target_value":51,"difference":1,
              "absolute_difference":1,"weight":1
            }]
          },
        """ : """
          "recommended_product_size_id":null,"recommended_size_label":null,
          "fit_score":null,"reliability_level":null,"coverage_ratio":null,
          "engine_version":"pending","result_evidence":{},
        """
        return """
        {
          "id":"\(ids.comparisonID)",
          "client_comparison_id":"\(ids.clientComparisonID)",
          "reference_client_item_id":"\(ids.referenceClientItemID)",
          "target_product_id":"\(ids.targetProductID)",
          "target_variant_id":"\(ids.targetVariantID)",
          "target_product_name_snapshot":"테스트 반팔 티셔츠",
          "target_image_url_snapshot":null,
          "target_source_code_snapshot":"uniqlo",
          "target_source_product_key":"E500001",
          "target_category_code":"tops",
          "result_status":"\(status)",
          \(completedFields)
          "created_at":"2026-08-29T01:00:00Z",
          "snapshot_schema_version":3,
          "excluded_measurement_codes":[],
          "reference_snapshot":{
            "source_code":"manual","item_name":"내 반팔 티셔츠","size_label":"M",
            "garment_type_code":"tshirt","audience_code":"male",
            "sleeve_length_code":"short_sleeve","lower_length_code":null,
            "body_length_code":null,"classification_source":"\(classificationSource)",
            "measurements":[{
              "fitmatch_measurement_code":"chest_width_pit_to_pit",
              "value":50,"unit_code":"CM","value_source":"USER"
            }]
          },
          "target_snapshot":{
            "product_id":"\(ids.targetProductID)",
            "variant_id":"\(ids.targetVariantID)",
            "authorized_candidate_product_size_ids":["\(ids.productSizeID)"],
            "candidate_authority_fingerprint":"candidate-v1",
            "classification_status":"CONFIRMED","garment_type_code":"tshirt",
            "sleeve_length_code":"short_sleeve","lower_length_code":null,
            "body_length_code":null,
            "candidates":[{
              "product_size_id":"\(ids.productSizeID)","size_label":"M",
              "availability":{"status":"AVAILABLE","observed_at":"2026-08-29T00:00:00Z",
                "valid_until":"2026-08-30T00:00:00Z","evidence_fingerprint":"stock-v1"},
              "comparison_measurements":[{
                "measurement_code":"chest_width_pit_to_pit",
                "reference_value":50,"target_value":51,"difference":1,
                "absolute_difference":1,"unit_code":"CM","basis_code":"WIDTH",
                "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1
              }],
              "authorization":{
                "decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC",
                "excluded_measurement_codes":[],
                "required_measurement_codes":["chest_width_pit_to_pit"],
                "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
                "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"
              }
            }]
          },
          "authority_snapshot":{},
          "policy_snapshot":{
            "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1",
            "metrics":[{
              "metric_mode":"CANONICAL",
              "fitmatch_measurement_code":"chest_width_pit_to_pit",
              "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,"is_active":true
            }]
          },
          "authorization_snapshot":{
            "decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC",
            "excluded_measurement_codes":[],
            "required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"
          },
          "input_snapshot":{}
        }
        """
    }

    private static func decode(_ json: String) throws -> VNextComparisonHistoryDTO {
        try JSONDecoder().decode(VNextComparisonHistoryDTO.self, from: Data(json.utf8))
    }
}

private actor ComparisonHistoryRemoteStub: FitMatchComparisonRemoteServicing {
    private let pending: VNextComparisonHistoryDTO?
    private let completed: VNextComparisonHistoryDTO?
    private var didComplete = false
    private var completionCalls = 0
    private var historyCalls = 0
    private var hiddenIDs = Set<UUID>()
    private var hideCalls = 0
    private var idempotentHide = false
    private var hideError: ComparisonHistoryRemoteError?
    private let historyResponses: [[VNextComparisonHistoryDTO]]?
    private let historyGates: [Int: JourneyAsyncGate]

    init(
        pending: VNextComparisonHistoryDTO?,
        completed: VNextComparisonHistoryDTO?,
        hideError: ComparisonHistoryRemoteError? = nil,
        historyResponses: [[VNextComparisonHistoryDTO]]? = nil,
        historyGates: [Int: JourneyAsyncGate] = [:]
    ) {
        self.pending = pending
        self.completed = completed
        self.hideError = hideError
        self.historyResponses = historyResponses
        self.historyGates = historyGates
    }

    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO] {
        historyCalls += 1
        if let gate = historyGates[historyCalls] {
            await gate.wait()
        }
        if let historyResponses {
            let responseIndex = min(historyCalls - 1, historyResponses.count - 1)
            return historyResponses[responseIndex].filter {
                !hiddenIDs.contains($0.clientComparisonID)
            }
        }
        if let completed, hiddenIDs.contains(completed.clientComparisonID) { return [] }
        if didComplete, let completed { return [completed] }
        if let pending { return [pending] }
        if let completed { return [completed] }
        return []
    }

    func hideVNextComparisonHistories(
        clientComparisonIDs: [UUID]
    ) async throws -> VNextComparisonHistoryVisibilityDTO {
        hideCalls += 1
        if let hideError { throw hideError }
        guard let completed,
              Set(clientComparisonIDs) == Set([completed.clientComparisonID]) else {
            throw ComparisonHistoryRemoteError.unknownComparison
        }
        idempotentHide = clientComparisonIDs.allSatisfy { hiddenIDs.contains($0) }
        hiddenIDs.formUnion(clientComparisonIDs)
        return VNextComparisonHistoryVisibilityDTO(
            clientComparisonIDs: Array(Set(clientComparisonIDs)),
            hidden: true,
            idempotent: idempotentHide
        )
    }

    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO {
        completionCalls += 1
        didComplete = true
        return VNextCompleteComparisonDTO(
            comparisonID: comparisonID,
            completed: true,
            idempotent: false,
            recommendedProductSizeID: payload.recommendedProductSizeID,
            recommendedSizeLabel: "M",
            validatedEvidenceCount: payload.metricEvidence.count,
            coverage: payload.coverage
        )
    }

    func completeCallCount() -> Int { completionCalls }
    func historyFetchCount() -> Int { historyCalls }
    func hiddenClientIDs() -> Set<UUID> { hiddenIDs }
    func hideCallCount() -> Int { hideCalls }
    func visibilityRowCount() -> Int { hiddenIDs.count }
    func lastHideWasIdempotent() -> Bool { idempotentHide }
    func completedHistoryRemainsImmutable() -> Bool { completed != nil }
    func setHideError(_ value: ComparisonHistoryRemoteError?) { hideError = value }
}

private enum ComparisonHistoryRemoteError: Error, Equatable {
    case unknownComparison
    case transportFailure
}
