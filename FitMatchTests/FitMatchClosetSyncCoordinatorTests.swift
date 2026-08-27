import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchClosetSyncCoordinatorTests {
    @Test func remoteOnlyAutomaticItemRestoresIdentityButWaitsForActiveV4Authority() async throws {
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
        #expect(item.classificationAuthorityProvenance == .serverUnavailable)
        #expect(item.canonicalEligibility == false)
        #expect(item.isRepresentative == false)
        #expect(item.sourceProduct?.classificationAuthorityProvenance == .serverUnavailable)
    }

    @Test func remoteOnlyManualOverrideRetainsExplicitUserAuthority() async throws {
        let clientItemID = UUID()
        let record = remoteRecord(
            clientItemID: clientItemID,
            productID: UUID(),
            classificationSource: "manual_override"
        )
        let remote = ClosetSyncRemoteStub(items: [record])
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        let item = try #require(
            try context.fetch(FetchDescriptor<UserFit>()).first { $0.id == clientItemID }
        )
        #expect(item.classificationAuthorityProvenance == .userExplicit)
        #expect(item.canonicalEligibility == true)
        #expect(item.isRepresentative == true)
    }

    @Test func remoteOnlyReviewAndNotComparableStatesRemainFailClosed() async throws {
        let reviewID = UUID()
        let notComparableID = UUID()
        let remote = ClosetSyncRemoteStub(
            items: [
                remoteRecord(
                    clientItemID: reviewID,
                    productID: UUID(),
                    classificationSource: "product_metadata",
                    classificationStatus: "review_required"
                ),
                remoteRecord(
                    clientItemID: notComparableID,
                    productID: UUID(),
                    classificationSource: "verified_exclusion",
                    classificationStatus: "not_comparable"
                )
            ]
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        let items = try context.fetch(FetchDescriptor<UserFit>())
        let review = try #require(items.first { $0.id == reviewID })
        let notComparable = try #require(items.first { $0.id == notComparableID })
        #expect(review.classificationAuthorityProvenance == .serverReviewRequired)
        #expect(review.canonicalEligibility == false)
        #expect(review.isRepresentative == false)
        #expect(notComparable.classificationAuthorityProvenance == .serverNotComparable)
        #expect(notComparable.canonicalEligibility == false)
        #expect(notComparable.isRepresentative == false)
    }

    @Test func manualClosetFormStampsExplicitUserAuthority() throws {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "반팔 티셔츠"
        viewModel.shoulder = "48"
        viewModel.chest = "54"

        let item = try #require(viewModel.makeUserFit())

        #expect(item.classificationAuthorityProvenance == .userExplicit)
        #expect(item.canonicalEligibility == true)
    }

    @Test func manualCompositeSetCannotBecomeComparisonAuthorityOrReference() throws {
        let viewModel = AddClosetItemViewModel(prefersRepresentativeByDefault: true)
        viewModel.brand = "테스트"
        viewModel.productName = "SWEET DREAM LACE PAJAMA SET_PINK"
        viewModel.shoulder = "48"
        viewModel.chest = "54"

        let item = try #require(viewModel.makeUserFit())

        #expect(item.classificationAuthorityProvenance == .localHint)
        #expect(item.canonicalEligibility == false)
        #expect(item.isRepresentative == false)
        #expect(item.fitMatchServerReferenceSnapshot() == nil)
    }

    @Test func existingManualSetIsRejectedBeforeServerEvaluator() throws {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "Jenny Soft Drape Blouse&Pants Set-up (Shadow Black)"
        viewModel.shoulder = "48"
        viewModel.chest = "54"
        let item = try #require(viewModel.makeUserFit())

        // Simulate an item saved by a previous build before the set hard gate.
        item.markClassificationAuthority(.userExplicit)

        #expect(item.classificationAuthorityProvenance == .userExplicit)
        #expect(item.fitMatchServerReferenceSnapshot() == nil)
    }

    @Test func localHintNeverCreatesOverrideAndServerConfirmedWins() async throws {
        let productID = UUID()
        let classification = databaseClassification(status: "confirmed")
        let remote = ClosetSyncRemoteStub(
            items: [],
            resolution: resolution(productID: productID, classification: classification),
            runtime: runtime(productID: productID, classification: classification)
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(authority: .localHint)
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        let request = try #require(await remote.capturedUpsertRequest())
        #expect(request.override == nil)
        #expect(request.productID == productID)
        #expect(request.item.categoryCode == "tops")
        #expect(request.item.detailCode == "short_sleeve")
        #expect(item.classificationAuthorityProvenance == .serverConfirmed)
        #expect(item.resolvedCategoryCode == "tops")
        #expect(item.resolvedDetailCategoryCode == "short_sleeve")
        #expect(item.garmentTypeRawValue == "tshirt")
        #expect(coordinator.state == .synced)
    }

    @Test func onlyExplicitUserClassificationCreatesServerOverride() async throws {
        let productID = UUID()
        let classification = databaseClassification(status: "confirmed")
        let remote = ClosetSyncRemoteStub(
            items: [],
            resolution: resolution(productID: productID, classification: classification),
            runtime: runtime(productID: productID, classification: classification)
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(authority: .userExplicit)
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        let request = try #require(await remote.capturedUpsertRequest())
        let override = try #require(request.override)
        #expect(override.categoryCode == "bottoms")
        #expect(override.detailCode == "long_pants")
        #expect(override.familyCode == "pants")
        #expect(override.reason == "user_confirmed_closet_classification")
        #expect(override.evidence["classification_authority"] == "user_explicit")
        #expect(item.classificationAuthorityProvenance == .userExplicit)
        #expect(coordinator.state == .synced)
    }

    @Test func existingAutomaticRemoteHistoryIsRevalidatedThroughActiveRuntime() async throws {
        let clientItemID = UUID()
        let productID = UUID()
        let classification = databaseClassification(status: "confirmed")
        let record = remoteRecord(
            clientItemID: clientItemID,
            productID: productID,
            classificationSource: "product_metadata"
        )
        let remote = ClosetSyncRemoteStub(
            items: [record],
            resolution: resolution(productID: productID, classification: classification),
            runtime: runtime(productID: productID, classification: classification)
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(
            id: clientItemID,
            productID: productID,
            authority: .localHint
        )
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(await remote.runtimeFetchCount() == 1)
        let request = try #require(await remote.capturedUpsertRequest())
        #expect(request.productID == productID)
        #expect(request.item.categoryCode == "tops")
        #expect(request.item.detailCode == "short_sleeve")
        #expect(request.override == nil)
        #expect(coordinator.state == .synced)
    }

    @Test func serverNotComparableClearsReferenceAndNeverUpsertsLocalClassification() async throws {
        let productID = UUID()
        let classification = databaseClassification(status: "not_comparable")
        let remote = ClosetSyncRemoteStub(
            items: [],
            resolution: resolution(productID: productID, classification: classification),
            runtime: runtime(
                productID: productID,
                classification: classification,
                runtimeState: "not_comparable"
            )
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(authority: .localHint)
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(await remote.capturedUpsertRequest() == nil)
        #expect(item.classificationAuthorityProvenance == .serverNotComparable)
        #expect(item.canonicalEligibility == false)
        #expect(item.isRepresentative == false)
        #expect(coordinator.state == .pendingRetry)
    }

    @Test func serverReviewRequiredClearsReferenceAndNeverUpsertsLocalHint() async throws {
        let productID = UUID()
        let classification = databaseClassification(status: "review_required")
        let remote = ClosetSyncRemoteStub(
            items: [],
            resolution: resolution(productID: productID, classification: classification),
            runtime: runtime(
                productID: productID,
                classification: classification,
                runtimeState: "classification_required"
            )
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(authority: .localHint)
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(await remote.capturedUpsertRequest() == nil)
        #expect(item.classificationAuthorityProvenance == .serverReviewRequired)
        #expect(item.canonicalEligibility == false)
        #expect(item.isRepresentative == false)
        #expect(coordinator.state == .pendingRetry)
    }

    @Test func promotionRequiredUsesObservationThenPersistsServerAuthority() async throws {
        let productID = UUID()
        let classification = databaseClassification(status: "confirmed")
        let promotionRequired = runtime(
            productID: productID,
            classification: classification,
            runtimeState: "classification_promotion_required"
        )
        let promotedRuntime = runtime(
            productID: productID,
            classification: classification
        )
        let remote = ClosetSyncRemoteStub(
            items: [],
            resolution: resolution(productID: productID, classification: classification),
            runtimes: [promotionRequired, promotedRuntime],
            observation: observation(productID: productID)
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(authority: .localHint)
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(await remote.observationSubmissionCount() == 1)
        #expect(await remote.runtimeFetchCount() == 2)
        #expect(await remote.capturedUpsertRequest()?.productID == productID)
        #expect(item.classificationAuthorityProvenance == .serverConfirmed)
        #expect(coordinator.state == .synced)
    }

    @Test func runtimeFailureIsNotSwallowedAndCannotKeepLocalHintEligible() async throws {
        let productID = UUID()
        let classification = databaseClassification(status: "confirmed")
        let remote = ClosetSyncRemoteStub(
            items: [],
            resolution: resolution(productID: productID, classification: classification),
            runtime: nil,
            failsRuntime: true
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(authority: .localHint)
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(await remote.capturedUpsertRequest() == nil)
        #expect(item.classificationAuthorityProvenance == .serverUnavailable)
        #expect(item.canonicalEligibility == false)
        #expect(item.isRepresentative == false)
        #expect(coordinator.state == .pendingRetry)
    }

    @Test func finalStaleAutomaticHydrationCannotUndoFailedV4Resolve() async throws {
        let clientItemID = UUID()
        let productID = UUID()
        let classification = databaseClassification(status: "confirmed")
        let staleAutomatic = remoteRecord(
            clientItemID: clientItemID,
            productID: productID,
            classificationSource: "product_metadata"
        )
        let remote = ClosetSyncRemoteStub(
            items: [staleAutomatic],
            resolution: resolution(productID: productID, classification: classification),
            runtime: nil,
            failsRuntime: true
        )
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = localRetailerItem(
            id: clientItemID,
            productID: productID,
            authority: .localHint
        )
        context.insert(item)
        try context.save()
        let coordinator = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )

        await coordinator.synchronize(userID: UUID(), modelContext: context)

        #expect(await remote.capturedUpsertRequest() == nil)
        #expect(item.classificationAuthorityProvenance == .serverUnavailable)
        #expect(item.canonicalEligibility == false)
        #expect(item.isRepresentative == false)
        #expect(coordinator.state == .pendingRetry)
    }

    @Test func sourcedFailClosedPickerEditsCannotBecomeUserAuthority() {
        for authority in [
            FitMatchClassificationAuthorityProvenance.serverReviewRequired,
            .serverNotComparable,
            .serverUnavailable
        ] {
            let result = FitMatchClosetClassificationEditPolicy.resultingAuthority(
                current: authority,
                isSourced: true,
                isExplicitSet: false,
                didExplicitlyChangeClassification: true
            )

            #expect(result == authority)
            #expect(result.isComparisonAuthority == false)
        }
    }

    @Test func sourcedSetPickerEditRemainsFailClosed() {
        let result = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: .serverConfirmed,
            isSourced: true,
            isExplicitSet: true,
            didExplicitlyChangeClassification: true
        )

        #expect(result == .localHint)
        #expect(result.isComparisonAuthority == false)

        let excluded = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: .serverNotComparable,
            isSourced: true,
            isExplicitSet: true,
            didExplicitlyChangeClassification: true
        )
        #expect(excluded == .serverNotComparable)
    }

    @Test func manualSetPickerEditRemainsFailClosed() {
        let result = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: .userExplicit,
            isSourced: false,
            isExplicitSet: true,
            didExplicitlyChangeClassification: true
        )

        #expect(result == .localHint)
        #expect(result.isComparisonAuthority == false)
    }

    @Test func actualImportedPickerEditBecomesUserExplicitButSizeOnlyEditDoesNot() {
        let explicitEdit = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: .serverConfirmed,
            isSourced: true,
            isExplicitSet: false,
            didExplicitlyChangeClassification: true
        )
        let sizeOnlyEdit = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: .serverConfirmed,
            isSourced: true,
            isExplicitSet: false,
            didExplicitlyChangeClassification: false
        )

        #expect(explicitEdit == .userExplicit)
        #expect(sizeOnlyEdit == .serverConfirmed)
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

    private func localRetailerItem(
        id: UUID = UUID(),
        productID: UUID = UUID(),
        authority: FitMatchClassificationAuthorityProvenance
    ) -> UserFit {
        let product = Product(
            id: productID,
            name: "로컬 긴바지",
            category: .bottom,
            productCode: "E500000",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E500000-000/01",
            metadata: ProductMetadata(
                sourceCategoryPath: "하의 > 팬츠",
                categoryDepth1Code: "bottoms",
                genderCodes: ["MEN"]
            ),
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        product.garmentTypeRawValue = "pants"
        product.sleeveTypeRawValue = "long"
        product.markClassificationAuthority(.localHint)
        let item = UserFit(
            id: id,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: "하의 > 팬츠",
            brandName: "유니클로",
            gender: .men,
            productName: product.name,
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 100,
                sleeveLength: 0,
                waist: 40,
                hip: 52,
                thigh: 30,
                rise: 28,
                hem: 20
            ),
            fitMemo: "",
            satisfaction: 4,
            isRepresentative: true,
            sourceProduct: product
        )
        item.categoryCode = "bottoms"
        item.detailCategoryCode = "long_pants"
        item.garmentTypeRawValue = "pants"
        item.sleeveTypeRawValue = "long"
        item.markClassificationAuthority(authority)
        return item
    }

    private func remoteRecord(
        clientItemID: UUID,
        productID: UUID,
        classificationSource: String,
        classificationStatus: String = "confirmed"
    ) -> FitMatchClosetItemRecord {
        FitMatchClosetItemRecord(
            closetItemID: UUID(),
            clientItemID: clientItemID,
            productID: productID,
            externalProductID: "E500000",
            productAudience: "MEN",
            sourceCategoryCodes: ["bottoms"],
            variantID: nil,
            productSizeID: nil,
            brand: "유니클로",
            productName: "기존 원격 분류",
            sizeName: "M",
            genderCode: "men",
            source: "uniqlo",
            sourceCategoryPath: "하의 > 팬츠",
            productURL: "https://www.uniqlo.com/kr/ko/products/E500000-000/01",
            imageURL: nil,
            measurements: ["waist_width": 40],
            measurementRecords: [],
            fitMemo: "",
            fitPreferenceCode: "regular",
            satisfaction: 4,
            isReference: true,
            classificationStatus: classificationStatus,
            classificationSource: classificationSource,
            categoryCode: "bottoms",
            detailCode: "long_pants",
            canonicalCategoryCode: "bottoms",
            canonicalDetailCode: "long_pants",
            familyCode: "pants",
            lengthCode: "long",
            bodyLengthCode: nil,
            classificationSnapshot: ["decision_version": "legacy-v3"],
            clientSnapshot: ["local_model": "UserFit"],
            clientCreatedAt: "2026-08-18T12:00:00Z",
            clientUpdatedAt: "2099-08-18T12:30:00Z",
            syncRevision: 3,
            createdAt: "2026-08-18T12:00:00Z",
            updatedAt: "2099-08-18T12:30:00Z"
        )
    }

    private func databaseClassification(status: String) -> FitMatchDatabaseClassification {
        FitMatchDatabaseClassification(
            classificationID: UUID(),
            categoryCode: status == "not_comparable" ? nil : "tops",
            detailCode: status == "not_comparable" ? nil : "short_sleeve",
            garmentTypeCode: status == "not_comparable" ? nil : "tshirt",
            familyCode: status == "not_comparable" ? nil : "tshirt",
            lengthCode: status == "not_comparable" ? nil : "short_sleeve",
            bodyLengthCode: nil,
            status: status,
            method: status == "not_comparable" ? "verified_exclusion" : "verified_product_decision",
            confidence: 1,
            requiresUserConfirmation: status != "confirmed",
            taxonomyPolicyVersion: "db-classifier-2026-08-26-final",
            decisionVersion: "test-decision-v1"
        )
    }

    private func resolution(
        productID: UUID,
        classification: FitMatchDatabaseClassification,
        catalogState: String = "current"
    ) -> FitMatchProductResolutionResponse {
        FitMatchProductResolutionResponse(
            productID: productID,
            intakeRequestID: nil,
            catalogState: catalogState,
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: classification,
            comparisonReady: classification.status == "confirmed"
        )
    }

    private func runtime(
        productID: UUID,
        classification: FitMatchDatabaseClassification,
        runtimeState: String = "ready"
    ) -> FitMatchProductRuntimeResponse {
        FitMatchProductRuntimeResponse(
            runtimeState: runtimeState,
            comparisonReady: runtimeState == "ready",
            product: FitMatchRuntimeProduct(
                productID: productID,
                source: "uniqlo",
                externalProductID: "E500000",
                productName: "서버 반팔 티셔츠",
                canonicalURL: "https://www.uniqlo.com/kr/ko/products/E500000-000/01",
                audience: "MEN",
                sourceCategoryPath: "상의 > 티셔츠",
                sourceCategoryCodes: ["tops"],
                imageURL: nil,
                lifecycleStatus: "active",
                inputFingerprint: "test-fingerprint"
            ),
            classification: classification,
            variants: []
        )
    }

    private func observation(productID: UUID) -> FitMatchProductObservationResponse {
        let observationID = UUID()
        return FitMatchProductObservationResponse(
            observation: .init(
                observationID: observationID,
                status: "accepted",
                rawMeasurementCount: 0
            ),
            processing: .init(
                observationID: observationID,
                status: "promoted",
                productID: productID
            )
        )
    }
}

private actor ClosetSyncRemoteStub: FitMatchClosetRemoteServicing {
    let items: [FitMatchClosetItemRecord]
    let resolutionResponse: FitMatchProductResolutionResponse?
    private var runtimeResponses: [FitMatchProductRuntimeResponse]
    let observationResponse: FitMatchProductObservationResponse?
    let failsRuntime: Bool
    private var upsertRequest: FitMatchUpsertClosetItemRequest?
    private var submittedObservationCount = 0
    private var fetchedRuntimeCount = 0

    init(
        items: [FitMatchClosetItemRecord],
        resolution: FitMatchProductResolutionResponse? = nil,
        runtime: FitMatchProductRuntimeResponse? = nil,
        runtimes: [FitMatchProductRuntimeResponse]? = nil,
        observation: FitMatchProductObservationResponse? = nil,
        failsRuntime: Bool = false
    ) {
        self.items = items
        self.resolutionResponse = resolution
        self.runtimeResponses = runtimes ?? runtime.map { [$0] } ?? []
        self.observationResponse = observation
        self.failsRuntime = failsRuntime
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        guard let resolutionResponse else { throw ClosetSyncRemoteStubError.unsupported }
        return resolutionResponse
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        fetchedRuntimeCount += 1
        if failsRuntime { throw ClosetSyncRemoteStubError.runtimeUnavailable }
        guard !runtimeResponses.isEmpty else { throw ClosetSyncRemoteStubError.unsupported }
        if runtimeResponses.count == 1 { return runtimeResponses[0] }
        return runtimeResponses.removeFirst()
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        submittedObservationCount += 1
        guard let observationResponse else { throw ClosetSyncRemoteStubError.unsupported }
        return observationResponse
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        throw ClosetSyncRemoteStubError.unsupported
    }

    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse {
        upsertRequest = request
        return FitMatchUpsertClosetItemResponse(
            closetItemID: UUID(),
            clientItemID: request.clientItemID,
            syncRevision: 1,
            classificationStatus: "confirmed",
            categoryCode: request.item.categoryCode,
            detailCode: request.item.detailCode,
            familyCode: request.item.familyCode,
            lengthCode: request.item.lengthCode,
            bodyLengthCode: request.item.bodyLengthCode,
            isReference: request.item.isReference
        )
    }

    func capturedUpsertRequest() -> FitMatchUpsertClosetItemRequest? { upsertRequest }
    func observationSubmissionCount() -> Int { submittedObservationCount }
    func runtimeFetchCount() -> Int { fetchedRuntimeCount }

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
    case runtimeUnavailable
}
