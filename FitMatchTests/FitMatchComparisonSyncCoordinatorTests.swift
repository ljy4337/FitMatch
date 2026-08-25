import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchComparisonSyncCoordinatorTests {
    @Test func confirmedLocalHistoryIsPersistedWithCanonicalRunAndMeasurements() async throws {
        let userID = UUID()
        let clientClosetID = UUID()
        let serverClosetID = UUID()
        let targetProductID = UUID()
        let targetSizeID = UUID()
        let runID = UUID()
        let history = try makeHistory(referenceID: clientClosetID)
        let fixture = try RemoteFixture(
            clientClosetID: clientClosetID,
            serverClosetID: serverClosetID,
            targetProductID: targetProductID,
            targetSizeID: targetSizeID,
            runID: runID
        )
        let remote = ComparisonRemoteStub(fixture: fixture)
        let suiteName = "FitMatchComparisonSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)

        await coordinator.synchronize(userID: userID, histories: [history])

        #expect(coordinator.state == .synced)
        #expect(coordinator.parityWarningCount == 0)
        let begin = await remote.capturedBeginRequest()
        #expect(begin?.clientHistoryID == history.id)
        #expect(begin?.referenceItemID == serverClosetID)
        #expect(begin?.targetProductID == targetProductID)
        #expect(begin?.allowExtended == false)
        let complete = try #require(await remote.capturedCompleteRequest())
        #expect(complete.runID == runID)
        let submitted = try #require(complete.results.first)
        #expect(submitted.targetSizeID == targetSizeID)
        #expect(submitted.similarityScore == Double(history.recommendationScore))
        #expect(submitted.coverageRatio == history.calculationSnapshot?.comparisonCoverage)
        #expect(submitted.dataQualityScore == 1)
        #expect(submitted.confidenceScore == 1)
        #expect(submitted.confidenceCode == "high")
        #expect(submitted.qualityMetricsVersion == "fitmatch-comparison-quality-2026-08-20-v1")
        #expect(submitted.isComparable)
        #expect(submitted.measurements.count == history.calculationSnapshot?.usedMeasurements.count)
        #expect(submitted.measurements.allSatisfy { $0.included })
        let encoded = try JSONEncoder().encode(complete)
        let payload = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let encodedResults = try #require(payload["results"] as? [[String: Any]])
        let encodedResult = try #require(encodedResults.first)
        #expect(encodedResult["coverage_ratio"] as? Double == 1)
        #expect(encodedResult["data_quality_score"] as? Double == 1)
        #expect(encodedResult["confidence_score"] as? Double == 1)
        #expect(
            encodedResult["quality_metrics_version"] as? String
                == "fitmatch-comparison-quality-2026-08-20-v1"
        )

        await coordinator.synchronize(userID: userID, histories: [history])
        #expect(await remote.beginCallCount() == 1)
        #expect(await remote.completeCallCount() == 1)
    }

    @Test func blockedDatabaseRunIsRecordedAsParityWarningWithoutSubmittingResult() async throws {
        let clientClosetID = UUID()
        let history = try makeHistory(referenceID: clientClosetID)
        let fixture = try RemoteFixture(
            clientClosetID: clientClosetID,
            serverClosetID: UUID(),
            targetProductID: UUID(),
            targetSizeID: UUID(),
            runID: UUID(),
            beginStatus: "blocked",
            beginAllowed: false
        )
        let remote = ComparisonRemoteStub(fixture: fixture)
        let suiteName = "FitMatchComparisonSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = FitMatchComparisonSyncCoordinator(remote: remote, defaults: defaults)

        await coordinator.synchronize(userID: UUID(), histories: [history])

        #expect(coordinator.state == .parityWarning)
        #expect(coordinator.parityWarningCount == 1)
        #expect(await remote.completeCallCount() == 0)
    }

    private func makeHistory(referenceID: UUID) throws -> RecommendationHistory {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 46,
                chest: 54,
                totalLength: 70,
                sleeveLength: 23
            )
        )
        size.measurementRecords = measurementRecords(
            shoulder: 46,
            chest: 54,
            totalLength: 70,
            sleeveLength: 23,
            methodSource: "uniqlo_kr",
            inputSource: .importedSizeChart
        )
        let product = Product(
            name: "에어리즘 코튼 크루넥T",
            category: .top,
            productCode: "E499999",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E499999-000/01",
            metadata: ProductMetadata(
                sourceCategoryPath: "티셔츠 > 에어리즘 코튼 > 반팔",
                categoryDepth1Code: "100",
                categoryDepth2Code: "110",
                categoryDepth3Code: "111",
                genderCodes: ["MEN"],
                checkedColorName: "BLACK"
            ),
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog,
            sizes: [size]
        )
        let reference = UserFit(
            id: referenceID,
            brandName: "테스트",
            gender: .men,
            productName: "내 반팔 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 53,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 5,
            isRepresentative: true
        )
        reference.measurementRecords = measurementRecords(
            shoulder: 45,
            chest: 53,
            totalLength: 69,
            sleeveLength: 22,
            methodSource: "manual",
            inputSource: .userMeasured
        )
        let comparison = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: reference,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )
        #expect(comparison.status == MeasurementComparisonStatus.confirmed)
        return RecommendationHistory(
            product: product,
            recommendedSize: size,
            userFit: reference,
            totalDifference: comparison.averageDifference,
            measurementDifferences: comparison.signedDifferences,
            recommendationScore: comparison.score,
            comparisonMethod: "같은 종류 기준 비교",
            productDetailCategory: .shortSleeve,
            comparisonResult: comparison
        )
    }

    private func measurementRecords(
        shoulder: Double,
        chest: Double,
        totalLength: Double,
        sleeveLength: Double,
        methodSource: String,
        inputSource: MeasurementInputSource
    ) -> [GarmentMeasurementRecord] {
        [
            measurementRecord(
                value: shoulder,
                code: .shoulderWidthSeamToSeam,
                kind: .shoulder,
                label: "어깨너비",
                methodSource: methodSource,
                inputSource: inputSource
            ),
            measurementRecord(
                value: chest,
                code: .chestWidthPitToPit,
                kind: .chest,
                label: "가슴너비",
                methodSource: methodSource,
                inputSource: inputSource
            ),
            measurementRecord(
                value: totalLength,
                code: .bodyLengthBackNeckToHem,
                kind: .totalLength,
                label: "총장",
                methodSource: methodSource,
                inputSource: inputSource
            ),
            measurementRecord(
                value: sleeveLength,
                code: .sleeveShoulderSeamToCuff,
                kind: .sleeveLength,
                label: "소매길이",
                methodSource: methodSource,
                inputSource: inputSource
            )
        ]
    }

    private func measurementRecord(
        value: Double,
        code: MeasurementCode,
        kind: MeasurementDisplayKind,
        label: String,
        methodSource: String,
        inputSource: MeasurementInputSource
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind,
            methodSource: methodSource,
            inputSource: inputSource,
            mappingVersion: "comparison-sync-test-v1",
            rawLabel: label,
            evidenceLevel: .fitmatchDefined,
            semanticStatus: .mapped
        )
    }
}

private struct RemoteFixture: Sendable {
    let closet: FitMatchClosetItemsResponse
    let resolution: FitMatchProductResolutionResponse
    let runtime: FitMatchProductRuntimeResponse
    let candidates: FitMatchReferenceCandidatesResponse
    let begin: FitMatchBeginComparisonResponse
    let complete: FitMatchCompleteComparisonResponse

    init(
        clientClosetID: UUID,
        serverClosetID: UUID,
        targetProductID: UUID,
        targetSizeID: UUID,
        runID: UUID,
        beginStatus: String = "pending",
        beginAllowed: Bool = true
    ) throws {
        closet = try Self.decode(
            """
            {
              "state":"ready",
              "items":[{
                "closet_item_id":"\(serverClosetID.uuidString)",
                "client_item_id":"\(clientClosetID.uuidString)",
                "product_id":null,"external_product_id":null,"product_audience":null,
                "source_category_codes":[],"variant_id":null,"product_size_id":null,
                "brand":"테스트","product_name":"내 반팔 티셔츠","size_name":"M",
                "gender_code":"male","source":"manual","source_category_path":null,
                "product_url":null,"image_url":null,
                "measurements":{"shoulder_width":45,"chest_width":53,"body_length":69,"sleeve_length":22},
                "measurement_records":[],"fit_memo":"","fit_preference_code":"regular",
                "satisfaction":5,"is_reference":true,"classification_status":"confirmed",
                "classification_source":"manual_override","category_code":"tops",
                "detail_code":"short_sleeve","canonical_category_code":null,
                "canonical_detail_code":null,"family_code":"tshirt",
                "length_code":"short_sleeve","body_length_code":null,
                "classification_snapshot":{},"client_snapshot":{},
                "client_created_at":"2026-08-19T00:00:00Z",
                "client_updated_at":"2026-08-19T00:00:00Z","sync_revision":1,
                "created_at":"2026-08-19T00:00:00Z","updated_at":"2026-08-19T00:00:00Z"
              }]
            }
            """
        )
        resolution = FitMatchProductResolutionResponse(
            productID: targetProductID,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            classification: FitMatchDatabaseClassification(
                classificationID: UUID(),
                categoryCode: "tops",
                detailCode: "short_sleeve",
                familyCode: "tshirt",
                lengthCode: "short_sleeve",
                bodyLengthCode: nil,
                status: "confirmed",
                method: "verified",
                confidence: 1,
                requiresUserConfirmation: false,
                taxonomyPolicyVersion: "taxonomy-v1",
                decisionVersion: "decision-v1"
            ),
            comparisonReady: true
        )
        runtime = try Self.decode(
            """
            {
              "runtime_state":"ready","comparison_ready":true,
              "product":{"product_id":"\(targetProductID.uuidString)","source":"uniqlo",
                "external_product_id":"E499999","product_name":"에어리즘 코튼 크루넥T",
                "canonical_url":null,"audience":"MEN","source_category_path":"티셔츠 > 반팔",
                "source_category_codes":["100","110","111"],"image_url":null,
                "lifecycle_status":"active","input_fingerprint":"test"},
              "classification":null,
              "variants":[{"variant_id":"\(UUID().uuidString)","external_variant_id":"09",
                "variant_name":"BLACK","color_code":"09","color_name":"BLACK",
                "sizes":[{"product_size_id":"\(targetSizeID.uuidString)","external_size_id":"004",
                  "size_label":"M","normalized_size_label":"M","display_order":1,
                  "stock_status":"in_stock","measurements":[]}]}]
            }
            """
        )
        candidates = try Self.decode(
            """
            {
              "state":"automatic","automatic_count":1,"manual_count":1,"structural_count":1,
              "policy_version":"db-comparison-test-v1",
              "candidates":[{"closet_item_id":"\(serverClosetID.uuidString)",
                "product_name":"내 반팔 티셔츠","size_name":"M","is_reference":true,
                "automatic_ready":true,"manual_ready":true,"measurement_overlap_count":4,
                "automatic_compatibility":{"allowed":true,"level":"direct"},
                "manual_compatibility":{"allowed":true,"level":"extended"}}]
            }
            """
        )
        begin = try Self.decode(
            """
            {"run_id":"\(runID.uuidString)","status":"\(beginStatus)",
             "compatibility":{"allowed":\(beginAllowed),"level":"\(beginAllowed ? "direct" : "incompatible")"}}
            """
        )
        complete = FitMatchCompleteComparisonResponse(
            runID: runID,
            status: "completed",
            resultCount: 1
        )
    }

    private static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

private actor ComparisonRemoteStub: FitMatchComparisonRemoteServicing {
    private let fixture: RemoteFixture
    private var beginRequests: [FitMatchBeginComparisonRequest] = []
    private var completeRequests: [FitMatchCompleteComparisonRequest] = []

    init(fixture: RemoteFixture) {
        self.fixture = fixture
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse { fixture.resolution }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse { fixture.runtime }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse { fixture.closet }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse { fixture.candidates }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse {
        beginRequests.append(request)
        return fixture.begin
    }

    func completeComparison(_ request: FitMatchCompleteComparisonRequest) async throws
        -> FitMatchCompleteComparisonResponse {
        completeRequests.append(request)
        return fixture.complete
    }

    func capturedBeginRequest() -> FitMatchBeginComparisonRequest? { beginRequests.last }
    func capturedCompleteRequest() -> FitMatchCompleteComparisonRequest? { completeRequests.last }
    func beginCallCount() -> Int { beginRequests.count }
    func completeCallCount() -> Int { completeRequests.count }
}
