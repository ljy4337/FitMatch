import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchClosetSyncCoordinatorTests {
    @Test func serverClosetItemRestoresStableLocalIdentityAndCatalogLink() async throws {
        let clientItemID = UUID()
        let productID = UUID()
        let productSizeID = UUID()
        let record = FitMatchClosetItemRecord(
            closetItemID: UUID(),
            clientItemID: clientItemID,
            productID: productID,
            externalProductID: "E492123",
            productAudience: "MEN",
            sourceCategoryCodes: ["95354", "95362", "95381"],
            variantID: nil,
            productSizeID: productSizeID,
            brand: "유니클로",
            productName: "데님릴렉스셔츠재킷",
            sizeName: "L",
            genderCode: "men",
            source: "uniqlo",
            sourceCategoryPath: "상의 > 셔츠 > 긴팔",
            productURL: "https://www.uniqlo.com/kr/ko/products/E492123-000/01",
            imageURL: "https://example.com/E492123.jpg",
            measurements: ["chest_width": 59, "body_length": 74],
            measurementRecords: [
                FitMatchClosetMeasurementRecordPayload(
                    value: 31,
                    unit: "cm",
                    measurementCode: "front_rise",
                    displayKind: "rise",
                    methodSource: "zara",
                    methodProfile: "zara_kr_measure_guide",
                    inputSource: "imported_size_chart",
                    standardVersion: nil,
                    mappingVersion: "zara_kr_measure_guide_verified_subset_v3",
                    rawCode: "zone-name-front-rise",
                    rawLabel: "zone-name-front-rise",
                    rawInfo: "raw_zone_id=D",
                    rawValueText: "31.0",
                    evidenceLevel: "official_text",
                    semanticStatus: "mapped"
                )
            ],
            fitMemo: "정핏",
            fitPreferenceCode: "regular",
            satisfaction: 4,
            isReference: true,
            classificationStatus: "confirmed",
            classificationSource: "canonical_product_decision",
            categoryCode: "tops",
            detailCode: "shirt",
            canonicalCategoryCode: "tops",
            canonicalDetailCode: "shirt",
            familyCode: "shirt",
            lengthCode: "long_sleeve",
            bodyLengthCode: nil,
            classificationSnapshot: ["decision_version": "db-app-adjudicated-2026-08-16-v1"],
            clientSnapshot: ["local_model": "UserFit"],
            clientCreatedAt: "2026-08-18T12:00:00Z",
            clientUpdatedAt: "2026-08-18T12:30:00Z",
            syncRevision: 3,
            createdAt: "2026-08-18T12:00:00Z",
            updatedAt: "2026-08-18T12:30:00Z"
        )
        let remote = ClosetSyncRemoteStub(items: [record])
        let defaultsName = "FitMatchClosetSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchClosetSyncCoordinator(remote: remote, defaults: defaults)

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(coordinator.state == .synced)
        let items = try context.fetch(FetchDescriptor<UserFit>())
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.id == clientItemID)
        #expect(item.productName == "데님릴렉스셔츠재킷")
        #expect(item.resolvedCategoryCode == "tops")
        #expect(item.resolvedDetailCategoryCode == "shirt")
        #expect(item.garmentTypeRawValue == "shirt")
        #expect(item.chest == 59)
        #expect(item.totalLength == 74)
        #expect(item.rise == 31)
        #expect(item.measurementRecords.first?.measurementCodeRawValue == "rise_crotch_to_waist_front")
        #expect(item.sourceProduct?.id == productID)
        #expect(item.sourceProduct?.productCode == "E492123")
        #expect(item.sourceProduct?.categoryDepth3Code == "95381")
        #expect(item.sourceProductSize?.id == productSizeID)
    }

    @Test func accountDeletionPurgesLocalClosetDataAndResetsSyncState() throws {
        let defaultsName = "FitMatchClosetSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: ClosetSyncRemoteStub(items: []),
            defaults: defaults
        )
        context.insert(
            UserFit(
                brandName: "유니클로",
                productName: "테스트 셔츠",
                category: .top,
                sizeName: "M",
                measurements: GarmentMeasurements(
                    shoulder: 45,
                    chest: 55,
                    totalLength: 70,
                    sleeveLength: 60
                ),
                fitMemo: "",
                satisfaction: 3
            )
        )
        try context.save()

        try coordinator.purgeLocalAccountData(modelContext: context)

        #expect(try context.fetch(FetchDescriptor<UserFit>()).isEmpty)
        #expect(coordinator.state == .idle)
        #expect(coordinator.lastErrorMessage == nil)
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private actor ClosetSyncRemoteStub: FitMatchClosetRemoteServicing {
    let items: [FitMatchClosetItemRecord]

    init(items: [FitMatchClosetItemRecord]) {
        self.items = items
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        throw ClosetSyncRemoteStubError.unsupported
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        throw ClosetSyncRemoteStubError.unsupported
    }

    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse {
        throw ClosetSyncRemoteStubError.unsupported
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        FitMatchClosetItemsResponse(state: "ready", items: items)
    }

    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse {
        throw ClosetSyncRemoteStubError.unsupported
    }
}

private enum ClosetSyncRemoteStubError: Error {
    case unsupported
}
