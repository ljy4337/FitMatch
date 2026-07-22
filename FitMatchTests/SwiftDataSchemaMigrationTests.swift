import Foundation
import SwiftData
import Testing
@testable import FitMatch

@Suite(.serialized)
struct SwiftDataSchemaMigrationTests {
    @Test
    func legacyStorePreservesDataAndRelationshipsWhenOpenedWithV1() throws {
        let fixture = FixtureIDs()
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        try createLegacyStore(at: storeURL, fixture: fixture)
        try verifyV1Store(at: storeURL, fixture: fixture)
        try verifyV1Store(at: storeURL, fixture: fixture)
    }

    @Test
    func newInstallationCreatesAndReopensEmptyV1Store() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        do {
            let container = try v1Container(at: storeURL)
            let context = ModelContext(container)
            #expect(try context.fetchCount(FetchDescriptor<Brand>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<Product>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<ProductSize>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<GarmentMeasurementRecord>()) == 0)
        }

        let reopened = try v1Container(at: storeURL)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<Product>()) == 0)
    }

    private func createLegacyStore(at storeURL: URL, fixture: FixtureIDs) throws {
        let legacySchema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let container = try ModelContainer(for: legacySchema, configurations: [configuration])
        let context = ModelContext(container)

        let brand = Brand(id: fixture.brand, name: "Legacy Brand")
        let size = ProductSize(
            id: fixture.size,
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 47.5,
                chest: 55.25,
                totalLength: 69.75,
                sleeveLength: 61.5,
                waist: 48,
                hip: 52
            ),
            displayOrder: 1
        )
        let product = Product(
            id: fixture.product,
            name: "Legacy Product",
            brand: brand,
            category: .top,
            productCode: "legacy-001",
            sourceURLString: "https://example.com/legacy-001",
            sourceName: "Legacy Shop",
            sizes: [size]
        )
        let productMeasurement = GarmentMeasurementRecord(
            id: fixture.productMeasurement,
            value: 110.5,
            measurementCode: .chestCircumferenceGarment,
            displayKind: .chest,
            methodSource: "legacy fixture",
            inputSource: .importedSizeChart,
            mappingVersion: "legacy-v1",
            rawLabel: "가슴둘레",
            evidenceLevel: .officialText,
            semanticStatus: .mapped,
            productSize: size
        )
        size.measurementRecords = [productMeasurement]

        let referenceFit = UserFit(
            id: fixture.referenceFit,
            brandName: "Legacy Brand",
            productName: "Reference Shirt",
            category: .top,
            detailCategory: .shirt,
            sizeName: "L",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 56,
                totalLength: 71,
                sleeveLength: 62,
                waist: 49,
                hip: 53
            ),
            fitMemo: "기준 옷",
            satisfaction: 5,
            isRepresentative: true,
            sourceProduct: product,
            sourceProductSize: size
        )
        let closetFit = UserFit(
            id: fixture.closetFit,
            brandName: "Closet Brand",
            productName: "Closet Shirt",
            category: .top,
            detailCategory: .shirt,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 46,
                chest: 54,
                totalLength: 68,
                sleeveLength: 60
            ),
            fitMemo: "일반 내 옷",
            satisfaction: 4
        )
        let fitMeasurement = GarmentMeasurementRecord(
            id: fixture.fitMeasurement,
            value: 56,
            measurementCode: .chestWidthPitToPit,
            displayKind: .chest,
            methodSource: "legacy fixture",
            inputSource: .userMeasured,
            mappingVersion: "legacy-v1",
            rawLabel: "가슴단면",
            evidenceLevel: .fitmatchDefined,
            semanticStatus: .mapped,
            userFit: referenceFit
        )
        referenceFit.measurementRecords = [fitMeasurement]

        let history = RecommendationHistory(
            id: fixture.history,
            product: product,
            recommendedSize: size,
            userFit: referenceFit,
            totalDifference: 2.25,
            measurementDifferences: GarmentMeasurements(
                shoulder: -0.5,
                chest: -0.75,
                totalLength: -1.25,
                sleeveLength: -0.5
            ),
            recommendationScore: 91,
            reason: "legacy relationship"
        )

        context.insert(brand)
        context.insert(product)
        context.insert(referenceFit)
        context.insert(closetFit)
        context.insert(history)
        try context.save()
    }

    private func verifyV1Store(at storeURL: URL, fixture: FixtureIDs) throws {
        let container = try v1Container(at: storeURL)
        let context = ModelContext(container)
        let brands = try context.fetch(FetchDescriptor<Brand>())
        let products = try context.fetch(FetchDescriptor<Product>())
        let sizes = try context.fetch(FetchDescriptor<ProductSize>())
        let fits = try context.fetch(FetchDescriptor<UserFit>())
        let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let measurements = try context.fetch(FetchDescriptor<GarmentMeasurementRecord>())

        #expect(brands.count == 1)
        #expect(products.count == 1)
        #expect(sizes.count == 1)
        #expect(fits.count == 2)
        #expect(histories.count == 1)
        #expect(measurements.count == 2)

        let brand = try #require(brands.first)
        let product = try #require(products.first)
        let size = try #require(sizes.first)
        let referenceFit = try #require(fits.first(where: { $0.id == fixture.referenceFit }))
        let closetFit = try #require(fits.first(where: { $0.id == fixture.closetFit }))
        let history = try #require(histories.first)

        #expect(brand.id == fixture.brand)
        #expect(product.id == fixture.product)
        #expect(size.id == fixture.size)
        #expect(referenceFit.id == fixture.referenceFit)
        #expect(closetFit.id == fixture.closetFit)
        #expect(history.id == fixture.history)
        #expect(size.shoulder == 47.5)
        #expect(size.chest == 55.25)
        #expect(referenceFit.chest == 56)
        #expect(referenceFit.isRepresentative)
        #expect(!closetFit.isRepresentative)
        #expect(brand.products.first?.id == product.id)
        #expect(product.brand?.id == brand.id)
        #expect(product.sizes.first?.id == size.id)
        #expect(size.product?.id == product.id)
        #expect(referenceFit.sourceProduct?.id == product.id)
        #expect(referenceFit.sourceProductSize?.id == size.id)
        #expect(size.measurementRecords.first?.id == fixture.productMeasurement)
        #expect(referenceFit.measurementRecords.first?.id == fixture.fitMeasurement)
        #expect(history.product.id == product.id)
        #expect(history.recommendedSize.id == size.id)
        #expect(history.userFit.id == referenceFit.id)
        #expect(history.totalDifference == 2.25)
        #expect(history.reason == "legacy relationship")
    }

    private func v1Container(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: FitMatchSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchSchemaMigration-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    private func removeStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fileManager.removeItem(atPath: storeURL.path + suffix)
        }
    }
}

private struct FixtureIDs {
    let brand = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let product = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let size = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    let referenceFit = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    let closetFit = UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
    let history = UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
    let productMeasurement = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
    let fitMeasurement = UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
}
