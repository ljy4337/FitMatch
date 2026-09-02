import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import FitMatch

/// Final release-candidate probes that construct behaviorally distinct state at
/// production seams. These tests intentionally include policy assertions that
/// may fail: release acceptance must expose current defects instead of encoding
/// the implementation's output as the expected result.
@MainActor
struct FitMatchFinalReleaseHeadlessAcceptanceTests {
    @Test func frozenFinalCatalogHasEveryStableFeatureIDExactlyOnce() throws {
        let source = try sourceFile(
            "Docs/FitMatchFinalReleaseUserScenarioCatalog-20260831.txt"
        )
        let expected: [String] =
            (1...22).map { String(format: "CR-%03d", $0) }
            + (1...19).map { String(format: "CM-%03d", $0) }
            + (1...39).map { String(format: "CP-%03d", $0) }
            + (1...13).map { String(format: "RS-%03d", $0) }
            + (1...17).map { String(format: "HI-%03d", $0) }
            + (1...12).map { String(format: "EN-%03d", $0) }
            + (1...15).map { String(format: "RX-%03d", $0) }

        #expect(expected.count == 137)
        #expect(source.contains("TOTAL FINAL USER SCENARIOS: 137"))
        for id in expected {
            #expect(source.components(separatedBy: "| \(id) |").count == 2)
        }
    }

    /// EN-002's system Share Sheet presentation is physical-only, but the
    /// extension and test both call this production traversal action after the
    /// system `NSItemProvider` boundary. It must skip unsupported attachments
    /// and deterministically choose the first approved URL.
    @Test func shareAttachmentExtractionActionTraversesTheProductionAttachmentContractInOrder() async throws {
        let unsupported = try #require(
            URL(string: "https://www.cos.com/ko_kr/men/product.1229297007.html")
        )
        let supported = try #require(
            URL(string: "https://www.uniqlo.com/kr/ko/products/E450259")
        )
        let attachments: [any FitMatchShareAttachmentLoading] = [
            ShareAttachmentStub(url: unsupported),
            ShareAttachmentStub(url: supported)
        ]

        let selectedURL = try #require(
            await FitMatchShareAttachmentExtractionAction.firstSupportedURL(from: attachments)
        )
        #expect(selectedURL == supported)
        #expect(FitMatchProductURLRouting.provider(for: selectedURL)?.rawValue == "uniqlo")
    }

    @Test func directClosetRegistrationConstructsDistinctAdultAndChildState() throws {
        let upper = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "성인 반팔 티셔츠"
        )
        upper.shoulder = "45"
        upper.shoulder = "45"
        upper.chest = "52"
        upper.totalLength = "69"
        upper.sleeveLength = "22"
        upper.totalLength = "69"
        upper.sleeveLength = "22"

        let lower = configuredDirectItem(
            gender: .women,
            category: .bottom,
            detail: .longPants,
            productName: "성인 긴바지"
        )
        lower.waist = "36"
        lower.hip = "50"

        let child = configuredDirectItem(
            gender: .kids,
            category: .top,
            detail: .shortSleeve,
            productName: "키즈 반팔 티셔츠"
        )
        child.chest = "40"

        let baby = configuredDirectItem(
            gender: .baby,
            category: .top,
            detail: .shortSleeve,
            productName: "베이비 반팔 티셔츠"
        )
        baby.chest = "32"

        let items = try [upper, lower, child, baby].map { model in
            #expect(model.canSave)
            return try #require(model.makeUserFit())
        }

        #expect(items.map(\.gender) == [.men, .women, .kids, .baby])
        #expect(items[0].category == .top)
        #expect(items[1].category == .bottom)
        #expect(items[2].classificationAuthorityProvenance == .userExplicit)
        #expect(items[3].classificationAuthorityProvenance == .userExplicit)
        #expect(items.allSatisfy { !$0.measurementRecords.isEmpty })
    }

    @Test func directClosetRegistrationRequiredAndInvalidValuesFailClosed() {
        let base = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "검증용 티셔츠"
        )
        base.chest = "50"
        #expect(base.canSave)

        let missingBrand = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "검증용 티셔츠"
        )
        missingBrand.brand = ""
        missingBrand.chest = "50"
        #expect(!missingBrand.canSave)
        if case .blocked(let reason) = FitMatchClosetFormAction.save(
            from: missingBrand,
            persist: { _ in Issue.record("Blocked form must not persist"); return true }
        ) {
            #expect(reason == "브랜드명을 입력해 주세요.")
        } else {
            Issue.record("Expected missing-brand form to remain blocked")
        }

        let missingName = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: ""
        )
        missingName.chest = "50"
        #expect(!missingName.canSave)
        if case .blocked(let reason) = FitMatchClosetFormAction.save(
            from: missingName,
            persist: { _ in Issue.record("Blocked form must not persist"); return true }
        ) {
            #expect(reason == "상품명을 입력해 주세요.")
        } else {
            Issue.record("Expected missing-name form to remain blocked")
        }

        let missingMeasurementSource = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "출처 없는 실측"
        )
        missingMeasurementSource.chest = "50"
        missingMeasurementSource.measurementEntrySource = nil
        #expect(!missingMeasurementSource.canSave)
        #expect(missingMeasurementSource.makeUserFit() == nil)
        if case .blocked(let reason) = FitMatchClosetFormAction.save(
            from: missingMeasurementSource,
            persist: { _ in Issue.record("Blocked form must not persist"); return true }
        ) {
            #expect(reason == "실측 정보를 확인한 출처를 선택해 주세요.")
        } else {
            Issue.record("Expected missing-source form to remain blocked")
        }

        let malformed = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "문자 실측"
        )
        malformed.chest = "오십"
        #expect(!malformed.canSave)
        #expect(malformed.makeUserFit() == nil)
        #expect(
            FitMatchClosetFormValidation.message(for: malformed)
                == "실측값을 1개 이상 입력해 주세요. 입력한 값은 0보다 큰 숫자여야 합니다."
        )

        let negative = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "음수 실측"
        )
        negative.chest = "-1"
        #expect(!negative.canSave)
        #expect(negative.makeUserFit() == nil)
        #expect(
            FitMatchClosetFormValidation.message(for: negative)
                == "실측값을 1개 이상 입력해 주세요. 입력한 값은 0보다 큰 숫자여야 합니다."
        )

        let zero = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "0 실측"
        )
        zero.chest = "0"
        #expect(!zero.canSave)
        #expect(zero.makeUserFit() == nil)
        #expect(
            FitMatchClosetFormValidation.message(for: zero)
                == "실측값을 1개 이상 입력해 주세요. 입력한 값은 0보다 큰 숫자여야 합니다."
        )

        let unsafe = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "범위 밖 실측"
        )
        unsafe.chest = "9999"
        #expect(!unsafe.canSave)
        #expect(unsafe.directMeasurementValidationMessage != nil)
        #expect(unsafe.makeUserFit() == nil)

        let emptyMeasurement = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "빈 실측"
        )
        #expect(!emptyMeasurement.canSave)
        #expect(emptyMeasurement.makeUserFit() == nil)
        #expect(
            FitMatchClosetFormValidation.message(for: emptyMeasurement)
                == "실측값을 1개 이상 입력해 주세요. 입력한 값은 0보다 큰 숫자여야 합니다."
        )

        let invalidTuple = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "불일치 taxonomy"
        )
        invalidTuple.chest = "50"
        invalidTuple.categoryCode = "bottoms"
        #expect(!invalidTuple.hasValidTaxonomySelection)
        #expect(!invalidTuple.canSave)
        #expect(invalidTuple.makeUserFit() == nil)
        #expect(
            FitMatchClosetFormValidation.message(for: invalidTuple)
                == "선택한 카테고리와 세부 카테고리를 다시 확인해 주세요."
        )
    }

    @Test func directClosetSaveFailurePreservesFormAndRetriesThroughTheSameAction() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let model = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "재시도 티셔츠"
        )
        model.chest = "51"
        model.fitMemo = "실패 뒤에도 남아야 하는 입력"

        let first = FitMatchClosetFormAction.save(
            from: model,
            persist: { _ in false }
        )
        if case .persistenceFailed = first {
            // Expected production action outcome; the form instance remains
            // intact for the retry below.
        } else {
            Issue.record("Expected injected persistence boundary to fail")
        }
        #expect(model.productName == "재시도 티셔츠")
        #expect(model.fitMemo == "실패 뒤에도 남아야 하는 입력")
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 0)

        let second = FitMatchClosetFormAction.save(
            from: model,
            persist: { item in
                FitMatchClosetRegistrationPersistence.save(item, in: context)
            }
        )
        guard case .saved(let item) = second else {
            Issue.record("Expected retry to use the same production action and save once")
            return
        }
        #expect(item.productName == "재시도 티셔츠")
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
    }

    @Test func directClosetRegistrationPersistsValidUserOwnedFactsWithoutPromotingCompositeSets() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        // CR-001 / CR-002 / CR-003 / CR-007: each distinguishing form state
        // goes through the same production `makeUserFit` then save action the
        // View uses, rather than a test-side persistence copy.
        let upper = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "성인 반팔 티셔츠"
        )
        upper.chest = "52"
        upper.fitMemo = "어깨가 편해요"
        upper.fitPreference = .semiOver

        let bottom = configuredDirectItem(
            gender: .women,
            category: .bottom,
            detail: .longPants,
            productName: "성인 긴바지"
        )
        bottom.waist = "35"
        bottom.hip = "49"

        let child = configuredDirectItem(
            gender: .kids,
            category: .top,
            detail: .shortSleeve,
            productName: "키즈 티셔츠"
        )
        child.chest = "40"

        let baby = configuredDirectItem(
            gender: .baby,
            category: .top,
            detail: .shortSleeve,
            productName: "베이비 티셔츠"
        )
        baby.chest = "32"

        for model in [upper, bottom, child, baby] {
            guard case .saved = FitMatchClosetFormAction.save(
                from: model,
                persist: { item in
                    FitMatchClosetRegistrationPersistence.save(item, in: context)
                }
            ) else {
                Issue.record("Expected the production manual Closet action to persist a valid form")
                return
            }
        }

        // CR-005: an explicit composite/set may stay in Closet but remains
        // unavailable as reference/comparison authority.
        let composite = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "티셔츠+반바지 세트"
        )
        composite.chest = "51"
        composite.isRepresentative = true
        guard case .saved(let compositeItem) = FitMatchClosetFormAction.save(
            from: composite,
            persist: { item in
                FitMatchClosetRegistrationPersistence.save(item, in: context)
            }
        ) else {
            Issue.record("Expected the production manual Closet action to retain a composite item safely")
            return
        }
        #expect(compositeItem.classificationAuthorityProvenance == .localHint)
        #expect(!compositeItem.isRepresentative)
        #expect(compositeItem.canonicalEligibility == false)

        let restored = try context.fetch(FetchDescriptor<UserFit>())
        #expect(restored.count == 5)
        let restoredUpper = try #require(restored.first { $0.productName == "성인 반팔 티셔츠" })
        #expect(restoredUpper.fitMemo == "어깨가 편해요")
        #expect(restoredUpper.fitPreference == .semiOver)
        #expect(restored.contains { $0.gender == .kids })
        #expect(restored.contains { $0.gender == .baby })
        #expect(restored.contains { $0.category == .bottom && $0.hip == 49 })
    }

    @Test func referenceReplacementAndIndependentCategoriesUseTheProductionMutation() throws {
        let firstTopForm = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "첫 기준 상의"
        )
        firstTopForm.chest = "50"
        let firstTop = try #require(firstTopForm.makeUserFit())
        firstTop.isRepresentative = true

        let secondTopForm = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "새 기준 상의"
        )
        secondTopForm.chest = "51"
        let secondTop = try #require(secondTopForm.makeUserFit())

        let bottomForm = configuredDirectItem(
            gender: .men,
            category: .bottom,
            detail: .longPants,
            productName: "독립 하의 기준"
        )
        bottomForm.waist = "35"
        bottomForm.hip = "49"
        let bottom = try #require(bottomForm.makeUserFit())
        bottom.isRepresentative = true

        let items = [firstTop, secondTop, bottom]
        FitMatchClosetReferenceMutation.setRepresentative(
            secondTop,
            among: items,
            now: Date(timeIntervalSince1970: 1)
        )

        // CR-008 / CM-006 / CM-007: same detailed type is atomically
        // replaced, while a distinct category reference remains independent.
        #expect(!firstTop.isRepresentative)
        #expect(secondTop.isRepresentative)
        #expect(bottom.isRepresentative)

        FitMatchClosetReferenceMutation.clearRepresentative(
            secondTop,
            now: Date(timeIntervalSince1970: 2)
        )
        #expect(!secondTop.isRepresentative)
        #expect(bottom.isRepresentative)
    }

    @Test func directRegistrationReferenceReplacementPersistsOnlyTheCurrentSameScopeReference() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let existingForm = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "기존 기준 상의"
        )
        existingForm.chest = "50"
        existingForm.isRepresentative = true
        guard case .saved(let existing) = FitMatchClosetManualRegistrationAction.save(
            from: existingForm,
            activeClosetItems: [],
            persist: { item in
                FitMatchClosetRegistrationPersistence.save(item, in: context)
            }
        ) else {
            Issue.record("Expected the production manual registration action to save the first reference")
            return
        }

        let independentBottomForm = configuredDirectItem(
            gender: .men,
            category: .bottom,
            detail: .longPants,
            productName: "독립 하의 기준"
        )
        independentBottomForm.waist = "35"
        independentBottomForm.hip = "49"
        independentBottomForm.isRepresentative = true
        guard case .saved(let independentBottom) = FitMatchClosetManualRegistrationAction.save(
            from: independentBottomForm,
            activeClosetItems: [existing],
            persist: { item in
                FitMatchClosetRegistrationPersistence.save(item, in: context)
            }
        ) else {
            Issue.record("Expected an independent bottom reference to save")
            return
        }

        let incomingForm = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "새 기준 상의"
        )
        incomingForm.chest = "52"
        incomingForm.isRepresentative = true
        guard case .saved(let incoming) = FitMatchClosetManualRegistrationAction.save(
            from: incomingForm,
            activeClosetItems: [existing, independentBottom],
            persist: { item in
                FitMatchClosetRegistrationPersistence.save(item, in: context)
            }
        ) else {
            Issue.record("Expected the incoming reference to use the production registration action")
            return
        }

        // CR-008: registering a new same-scope reference replaces only the
        // conflicting top reference; the independent bottom reference stays.
        #expect(!existing.isRepresentative)
        #expect(incoming.isRepresentative)
        #expect(independentBottom.isRepresentative)
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 3)

        let failingForm = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "저장 실패 기준 상의"
        )
        failingForm.chest = "54"
        failingForm.isRepresentative = true
        // CR-009: an injected persistence failure must not report a new
        // reference or silently unset the existing persisted reference.
        if case .persistenceFailed = FitMatchClosetManualRegistrationAction.save(
            from: failingForm,
            activeClosetItems: [incoming, independentBottom],
            persist: { _ in false }
        ) {
            #expect(incoming.isRepresentative)
            #expect(independentBottom.isRepresentative)
        } else {
            Issue.record("Expected failed manual-reference save to preserve existing references")
        }
    }

    @Test func closetPresentationUsesOnlyActiveOwnedRowsAndPreservesFilterSortIdentity() {
        let oldestTop = UserFit(
            brandName: "Alpha",
            gender: .men,
            productName: "오래된 상의",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 50,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 3,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newestBottom = UserFit(
            brandName: "Beta",
            gender: .men,
            productName: "새 하의",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 100,
                sleeveLength: 0
            ),
            fitMemo: "",
            satisfaction: 3,
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let representativeTop = UserFit(
            brandName: "Gamma",
            gender: .men,
            productName: "기준 상의",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "L",
            measurements: GarmentMeasurements(
                shoulder: 47,
                chest: 53,
                totalLength: 70,
                sleeveLength: 23
            ),
            fitMemo: "",
            satisfaction: 3,
            isRepresentative: true,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let historyOnly = UserFit(
            brandName: "History",
            gender: .men,
            productName: "과거 기준 옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 46,
                chest: 51,
                totalLength: 68,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 3,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        historyOnly.markAsHistoryOnlyReferenceSnapshot()

        let cached = [oldestTop, newestBottom, representativeTop, historyOnly]
        // CM-001 / CM-013: 0/1/many is derived from the actual production
        // active-item rule, so a History-only reference cannot re-enter a
        // normal Closet or reference-picking surface.
        #expect(FitMatchClosetPresentation.activeItems(from: []).isEmpty)
        #expect(FitMatchClosetPresentation.activeItems(from: [oldestTop]).map(\.id) == [oldestTop.id])
        #expect(Set(FitMatchClosetPresentation.activeItems(from: cached).map(\.id))
            == Set([oldestTop.id, newestBottom.id, representativeTop.id]))

        // CM-018: category and brand filters retain the exact owned identity;
        // every current user-facing sort is exercised through the production
        // presentation action rather than a view-private duplicate.
        let topIDs = FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: .top,
            brand: nil,
            sort: .recent
        ).map(\.id)
        #expect(topIDs == [representativeTop.id, oldestTop.id])
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: "Beta",
            sort: .recent
        ).map(\.id) == [newestBottom.id])
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: nil,
            sort: .oldest
        ).map(\.id) == [oldestTop.id, representativeTop.id, newestBottom.id])
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: nil,
            sort: .brand
        ).map(\.id) == [oldestTop.id, newestBottom.id, representativeTop.id])
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: nil,
            sort: .category
        ).map(\.id) == [oldestTop.id, representativeTop.id, newestBottom.id])
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: nil,
            sort: .basisFirst
        ).map(\.id) == [representativeTop.id, newestBottom.id, oldestTop.id])
    }

    @Test func closetDetailEditActionsKeepSourcedAuthoritySeparateFromExplicitPickerIntent() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let originalForm = configuredDirectItem(
            gender: .men,
            category: .top,
            detail: .shortSleeve,
            productName: "직접 등록 원본"
        )
        originalForm.chest = "50"
        let original = try #require(originalForm.makeUserFit())
        context.insert(original)
        try context.save()

        let editedForm = configuredDirectItem(
            gender: .women,
            category: .top,
            detail: .shortSleeve,
            productName: "직접 등록 수정"
        )
        editedForm.chest = "53"
        editedForm.fitMemo = "수정한 메모"
        editedForm.fitPreference = .semiOver
        let edited = try #require(editedForm.makeUserFit())
        #expect(FitMatchClosetItemEditAction.saveManual(
            item: original,
            editedItem: edited,
            activeClosetItems: [original],
            in: context,
            now: Date(timeIntervalSince1970: 2)
        ) == .saved)
        #expect(original.productName == "직접 등록 수정")
        #expect(original.gender == .women)
        #expect(original.chest == 53)
        #expect(original.fitMemo == "수정한 메모")
        #expect(original.fitPreference == .semiOver)

        func importedItem(
            status: FitMatchClassificationAuthorityProvenance,
            code: String
        ) -> (item: UserFit, replacementSize: ProductSize) {
            let product = Product(
                name: "수입 상품 \(code)",
                category: .top,
                productCode: code,
                sourceType: .officialStore,
                sourceName: "공식몰",
                source: .catalog
            )
            product.garmentTypeRawValue = "tshirt"
            product.sleeveTypeRawValue = "short_sleeve"
            product.markClassificationAuthority(status)
            let initial = ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 45,
                    chest: 50,
                    totalLength: 69,
                    sleeveLength: 22
                ),
                product: product
            )
            let replacement = ProductSize(
                name: "L",
                measurements: GarmentMeasurements(
                    shoulder: 47,
                    chest: 54,
                    totalLength: 71,
                    sleeveLength: 23
                ),
                product: product
            )
            product.sizes = [initial, replacement]
            let item = UserFit(
                sourceType: .officialStore,
                sourceName: "공식몰",
                brandName: "브랜드",
                gender: .men,
                productName: product.name,
                category: .top,
                detailCategory: .shortSleeve,
                sizeName: initial.name,
                measurements: initial.measurements,
                fitMemo: "",
                satisfaction: 3,
                sourceProduct: product,
                sourceProductSize: initial
            )
            item.categoryCode = "tops"
            item.detailCategoryCode = "tshirt"
            item.markClassificationAuthority(status)
            context.insert(product)
            context.insert(item)
            return (item, replacement)
        }

        // CM-003: size-only edits preserve each current sourced state instead
        // of treating a picker/displayed tuple as new personal authority.
        let global = importedItem(status: .serverConfirmed, code: "global")
        let review = importedItem(status: .serverReviewRequired, code: "review")
        let unavailable = importedItem(status: .serverUnavailable, code: "unavailable")
        try context.save()
        for fixture in [global, review, unavailable] {
            #expect(FitMatchClosetItemEditAction.saveImported(
                item: fixture.item,
                selectedSize: fixture.replacementSize,
                category: .bottom,
                detailCategory: .longPants,
                categoryCode: "bottoms",
                detailCode: "long_pants",
                didExplicitlyChangeClassification: false,
                in: context,
                now: Date(timeIntervalSince1970: 3)
            ) == .saved)
        }
        #expect(global.item.classificationAuthorityProvenance == .serverConfirmed)
        #expect(review.item.classificationAuthorityProvenance == .serverReviewRequired)
        #expect(unavailable.item.classificationAuthorityProvenance == .serverUnavailable)
        #expect(global.item.category == .top)
        #expect(global.item.sizeName == "L")

        // A separate existing-Closet picker intent is the only path that can
        // become a personal Closet authority.
        #expect(FitMatchClosetItemEditAction.saveImported(
            item: global.item,
            selectedSize: global.replacementSize,
            category: .top,
            detailCategory: .shortSleeve,
            categoryCode: "tops",
            detailCode: "polo_shirt",
            didExplicitlyChangeClassification: true,
            in: context,
            now: Date(timeIntervalSince1970: 4)
        ) == .saved)
        #expect(global.item.classificationAuthorityProvenance == .userExplicit)
        #expect(global.item.resolvedDetailCategoryCode == "polo_shirt")
    }

    @Test func releasedProviderBoundaryAcceptsThreeAndRejectsCOS() async {
        let supported = [
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00",
            "https://www.musinsa.com/products/6781113",
            "https://www.zara.com/kr/ko/heart-stamping-t-shirt-p06224446.html?v1=498706001"
        ]
        for url in supported {
            #expect(ProductURLSupport.isSupportedProductURL(url))
            #expect(ProductURLSupport.supportedProviderName(for: url) != nil)
        }

        let cos = "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"
        #expect(!ProductURLSupport.isSupportedProductURL(cos))
        #expect(ProductURLSupport.supportedProviderName(for: cos) == nil)
        await #expect(throws: ProductURLParserError.unsupportedURL) {
            _ = try await ProductURLParserService().parse(urlString: cos)
        }
        #expect(!(ProductURLParserError.unsupportedURL.errorDescription ?? "").contains("COS"))

        // EN-006: the same production entry action used by CompareFlowSheet
        // turns every rejected Home/Compare input into an explainable terminal
        // outcome before a parser or server request is started.
        #expect(FitMatchProductLinkInput.entryOutcome(for: "   ") == .blocked(
            "상품 링크를 입력해 주세요."
        ))
        #expect(FitMatchProductLinkInput.entryOutcome(for: "not a url") == .blocked(
            ProductURLParserError.unsupportedURL.errorDescription
                ?? "지원하는 상품 링크인지 확인해 주세요."
        ))
        #expect(FitMatchProductLinkInput.entryOutcome(for: cos) == .blocked(
            ProductURLParserError.unsupportedURL.errorDescription
                ?? "지원하는 상품 링크인지 확인해 주세요."
        ))
        guard case .begin(let approvedURL) = FitMatchProductLinkInput.entryOutcome(
            for: supported[0]
        ) else {
            Issue.record("Approved provider URL was blocked before CompareFlow")
            return
        }
        #expect(approvedURL.absoluteString == supported[0])
    }

    @Test func shareRoutingSkipsAnUnsupportedAttachmentAndUsesTheFirstSupportedProductURL() throws {
        let unsupported = try #require(URL(string: "https://www.cos.com/ko-kr/product.example.1229297007.html"))
        let supportedUniqlo = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))
        let laterSupportedZara = try #require(URL(string:
            "https://www.zara.com/kr/ko/heart-stamping-t-shirt-p06224446.html?v1=498706001"
        ))

        // EN-002 / EN-003 / EN-012: this exact shared production routing
        // helper is compiled into both the extension and containing app.
        // Attachment order is preserved, COS remains unsupported, and a
        // later approved product URL is selected only once.
        #expect(
            FitMatchProductURLRouting.firstSupportedURL(
                in: [unsupported, supportedUniqlo, laterSupportedZara]
            ) == supportedUniqlo
        )
        #expect(FitMatchProductURLRouting.provider(for: unsupported) == nil)
    }

    @Test func sharedAttachmentExtractorUsesActualProviderOrderBeforeHandoff() async throws {
        let cos = try #require(URL(string:
            "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"
        ))
        let uniqlo = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))
        let zara = try #require(URL(string:
            "https://www.zara.com/kr/ko/heart-stamping-t-shirt-p06224446.html?v1=498706001"
        ))

        // EN-002 / EN-012: this is the production helper compiled into the
        // Share Extension. Real NSItemProvider callbacks preserve attachment
        // order, skip COS, and stop at the first official-provider URL.
        let selected: URL? = await withCheckedContinuation { continuation in
            FitMatchShareAttachmentExtractor.loadFirstSupportedURL(
                from: [
                    shareURLProvider(cos),
                    shareURLProvider(uniqlo),
                    shareURLProvider(zara)
                ]
            ) { url in
                continuation.resume(returning: url)
            }
        }
        #expect(selected == uniqlo)

        let noSupportedURL: URL? = await withCheckedContinuation { continuation in
            FitMatchShareAttachmentExtractor.loadFirstSupportedURL(
                from: [shareURLProvider(cos)]
            ) { url in
                continuation.resume(returning: url)
            }
        }
        #expect(noSupportedURL == nil)
    }

    @Test func sharedAttachmentRoutingCreatesOneApprovedEphemeralAppHandoff() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseHeadlessAcceptanceTests.SharedAttachment.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Date(timeIntervalSince1970: 1_788_220_800)
        let store = SharedURLStore(fileURL: fileURL, now: { now })
        let cos = try #require(URL(string:
            "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"
        ))
        let uniqlo = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))

        // EN-002 / EN-003 / EN-012: the extension-side writer and app-side
        // consumer use the same file-backed payload contract.
        let selected = try #require(
            FitMatchProductURLRouting.firstSupportedURL(in: [cos, uniqlo])
        )
        #expect(selected == uniqlo)
        #expect(
            FitMatchSharedURLHandoffStore(fileURL: fileURL, now: { now })
                .save(selected)
        )
        let handoff = try #require(store.pendingProductURLHandoff())
        #expect(handoff.urlString == uniqlo.absoluteString)
        let compareRoute = try #require(URL(string: "fitmatch://compare"))
        #expect(FitMatchProductEntryRouting.action(for: compareRoute) == .openPendingProductCompare)
        #expect(store.clearPendingProductURL(ifMatching: handoff.urlString, token: handoff.token))
        #expect(store.pendingProductURLHandoff() == nil)
    }

    @Test func linkRegistrationInputFailsClosedBeforeParserForEmptyMalformedAndUnsupportedURLs() async {
        #expect(FitMatchProductLinkInput.validate("   ") == .empty)
        #expect(FitMatchProductLinkInput.validate("not a URL") == .unsupported)
        #expect(FitMatchProductLinkInput.validate(
            "https://www.uniqlo.example/kr/ko/products/E450259-000/00"
        ) == .unsupported)
        #expect(FitMatchProductLinkInput.validate(
            "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"
        ) == .unsupported)

        let supported = FitMatchProductLinkInput.validate(
            " https://www.uniqlo.com/kr/ko/products/E450259-000/00 "
        )
        #expect(supported.canStartLoad)
        guard case .supported(let url) = supported else {
            Issue.record("Expected approved UNIQLO URL to reach the production link-input gate")
            return
        }
        #expect(url.host == "www.uniqlo.com")

        // CR-010: drive every invalid subfixture through the same production
        // action that the View calls. The factory is the parser/network
        // boundary; blocked input must never reach it.
        let invalidInputs: [(String, FitMatchProductLinkInput.Validation)] = [
            ("   ", .empty),
            ("not a URL", .unsupported),
            ("https://www.uniqlo.example/kr/ko/products/E450259-000/00", .unsupported),
            ("https://www.cos.com/ko-kr/product.example.1229297007.html", .unsupported)
        ]
        for (input, expected) in invalidInputs {
            var factoryCalls = 0
            let blocked = await FitMatchLinkClosetRegistrationAction.load(
                urlString: input,
                makeViewModel: { urlString in
                    factoryCalls += 1
                    return ShoppingProductViewModel(initialURL: urlString)
                },
                existingBrand: { _ in nil }
            )
            guard case .blocked(let actual) = blocked else {
                Issue.record("Expected the production link action to block invalid input before construction")
                return
            }
            #expect(actual == expected)
            #expect(factoryCalls == 0)
        }
    }

    @Test func homeAndCompareDirectEntryShareTheMeaningfulUnsupportedLinkContract() {
        // EN-006: Home and Compare both call this production entry action
        // before any parser or server task exists.  The test deliberately
        // asserts the terminal user message, not a view-private disabled
        // button state.
        if case .blocked(let message) = FitMatchProductLinkInput.entryOutcome(for: "") {
            #expect(message == "상품 링크를 입력해 주세요.")
        } else {
            Issue.record("EN-006 empty Home/Compare input unexpectedly began a product flow")
        }

        for value in [
            "not a url",
            "https://example.com/products/unknown",
            "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"
        ] {
            if case .blocked(let message) = FitMatchProductLinkInput.entryOutcome(for: value) {
                #expect(message.contains("무신사"))
                #expect(message.contains("유니클로"))
                #expect(message.contains("ZARA"))
                #expect(!message.localizedCaseInsensitiveContains("COS"))
            } else {
                Issue.record("EN-006 unsupported input unexpectedly began a parser flow: \(value)")
            }
        }

        for value in [
            "https://www.uniqlo.com/kr/ko/products/E450259",
            "https://www.musinsa.com/products/6805433",
            "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"
        ] {
            if case .begin(let url) = FitMatchProductLinkInput.entryOutcome(for: value) {
                #expect(url.absoluteString == value)
            } else {
                Issue.record("EN-006 approved provider did not reach the shared product-entry action: \(value)")
            }
        }
    }

    @Test func linkRegistrationActionRunsTheActualParserAuthorityAndPreparationPipeline() async throws {
        let fixture = AtomicEffectiveTupleFixture()
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(
                uniqloParser: AtomicEffectiveTupleParser(product: fixture.parsedProduct)
            ),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                remote: AtomicEffectiveTupleRemote(fixture: fixture)
            )
        )

        let outcome = await FitMatchLinkClosetRegistrationAction.load(
            urlString: fixture.url.absoluteString,
            makeViewModel: { _ in viewModel },
            existingBrand: { _ in nil }
        )
        guard case .loaded(let preparation) = outcome,
              let preparedProduct = preparation.parsedProduct else {
            Issue.record("Expected the production link action to reach parser → authority → registration preparation")
            return
        }

        // CR-020 boundary: the preparation preserves the server-issued
        // shopping authority and does not fabricate a Global Closet authority.
        #expect(preparedProduct.classificationAuthorityProvenance == .userExplicit)
        #expect(preparation.partialProduct == nil)
        #expect(preparation.recoveryViewModel == nil)
    }

    @Test func shoppingPersonalClassificationNeedsSeparateClosetIntent() {
        let shoppingProduct = Product(
            name: "쇼핑에서 확인한 폴로 셔츠",
            category: .top,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        shoppingProduct.garmentTypeRawValue = "polo_shirt"
        shoppingProduct.sleeveTypeRawValue = "short_sleeve"
        shoppingProduct.markClassificationAuthority(.userExplicit)
        let shoppingSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 47,
                chest: 52,
                totalLength: 69,
                sleeveLength: 23
            ),
            product: shoppingProduct
        )
        shoppingProduct.sizes = [shoppingSize]
        let shoppingRegistration = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: shoppingProduct,
            sourceSize: shoppingSize,
            authorityProduct: shoppingProduct,
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: shoppingProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "polo_shirt",
            isRepresentative: false,
            didExplicitlyChangeClassification: false
        )

        // The shopping Recovery choice is not itself a Closet-classification
        // edit. Without a distinct Closet picker action it must not become an
        // owned Closet USER_EXPLICIT authority.
        #expect(shoppingRegistration.classificationAuthorityProvenance == .localHint)
        #expect(shoppingRegistration.canonicalEligibility == false)

        let sizeOnlyExistingClosetItem = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: .userExplicit,
            isSourced: true,
            isExplicitSet: false,
            didExplicitlyChangeClassification: false,
            scope: .existingClosetItem
        )
        #expect(sizeOnlyExistingClosetItem == .userExplicit)

        let explicitClosetPicker = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: shoppingProduct,
            sourceSize: shoppingSize,
            authorityProduct: shoppingProduct,
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: shoppingProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "polo_shirt",
            isRepresentative: false,
            didExplicitlyChangeClassification: true
        )
        #expect(explicitClosetPicker.classificationAuthorityProvenance == .userExplicit)

        let reviewRequiredProduct = Product(
            name: "서버 검토가 필요한 스웨터",
            category: .top,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        reviewRequiredProduct.garmentTypeRawValue = nil
        reviewRequiredProduct.sleeveTypeRawValue = nil
        reviewRequiredProduct.markClassificationAuthority(.serverReviewRequired)
        let reviewRequiredSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 47,
                chest: 52,
                totalLength: 66,
                sleeveLength: 59
            ),
            product: reviewRequiredProduct
        )
        reviewRequiredProduct.sizes = [reviewRequiredSize]

        let explicitReviewRequiredRegistration = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: reviewRequiredProduct,
            sourceSize: reviewRequiredSize,
            authorityProduct: reviewRequiredProduct,
            brandName: "UNIQLO",
            gender: .women,
            genderCode: "WOMEN",
            productName: reviewRequiredProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .knitTop,
            detailCategoryCode: "knit_sweater",
            isRepresentative: true,
            didExplicitlyChangeClassification: true
        )
        #expect(explicitReviewRequiredRegistration.classificationAuthorityProvenance == .userExplicit)
        #expect(explicitReviewRequiredRegistration.canonicalEligibility)
        #expect(explicitReviewRequiredRegistration.isRepresentative)

        let globalProduct = Product(
            name: "전역 확정 티셔츠",
            category: .top,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        globalProduct.garmentTypeRawValue = "tshirt"
        globalProduct.sleeveTypeRawValue = "short_sleeve"
        globalProduct.markClassificationAuthority(.serverConfirmed)
        let globalSize = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(
                shoulder: 49,
                chest: 55,
                totalLength: 71,
                sleeveLength: 24
            ),
            product: globalProduct
        )
        globalProduct.sizes = [globalSize]
        let globalRegistration = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: globalProduct,
            sourceSize: globalSize,
            authorityProduct: globalProduct,
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: globalProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "tshirt",
            isRepresentative: false,
            didExplicitlyChangeClassification: false
        )
        #expect(globalRegistration.classificationAuthorityProvenance == .serverConfirmed)
    }

    @Test func comparedProductClosetSaveUsesTheProductionBoundaryAndRejectsDuplicateSubmit() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let shoppingProduct = Product(
            name: "쇼핑 개인확정 폴로",
            category: .top,
            productCode: "E-UE-1",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E-UE-1-000/00",
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        shoppingProduct.garmentTypeRawValue = "polo_shirt"
        shoppingProduct.sleeveTypeRawValue = "short_sleeve"
        shoppingProduct.markClassificationAuthority(.userExplicit)
        let shoppingSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 47,
                chest: 52,
                totalLength: 69,
                sleeveLength: 23
            ),
            product: shoppingProduct
        )
        shoppingProduct.sizes = [shoppingSize]

        let shoppingRequest = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: shoppingProduct,
            selectedSize: shoppingSize,
            activeClosetItems: [],
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: shoppingProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "polo_shirt",
            isRepresentative: true,
            didExplicitlyChangeClassification: false
        )

        guard case .saved(let savedShoppingItem) = FitMatchComparedProductClosetRegistration.save(
            shoppingRequest,
            in: context
        ) else {
            Issue.record("Expected the production compared-product save action to persist")
            return
        }

        // CR-017 / RS-012 / HI-014: a valid shopping-only Recovery choice is
        // not a Closet picker intent, and cannot become a reference merely by
        // selecting a size during registration.
        #expect(savedShoppingItem.classificationAuthorityProvenance == .localHint)
        #expect(savedShoppingItem.canonicalEligibility == false)
        #expect(!savedShoppingItem.isRepresentative)

        let duplicateRequest = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: shoppingProduct,
            selectedSize: shoppingSize,
            activeClosetItems: [savedShoppingItem],
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: shoppingProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "polo_shirt",
            isRepresentative: false,
            didExplicitlyChangeClassification: false
        )
        guard case .duplicate = FitMatchComparedProductClosetRegistration.save(
            duplicateRequest,
            in: context
        ) else {
            Issue.record("Expected an identical second save to remain a duplicate")
            return
        }
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)

        let globalProduct = Product(
            name: "전역 확정 티셔츠",
            category: .top,
            productCode: "E-GLOBAL-1",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E-GLOBAL-1-000/00",
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        globalProduct.garmentTypeRawValue = "tshirt"
        globalProduct.sleeveTypeRawValue = "short_sleeve"
        globalProduct.markClassificationAuthority(.serverConfirmed)
        let globalSize = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(
                shoulder: 49,
                chest: 55,
                totalLength: 71,
                sleeveLength: 24
            ),
            product: globalProduct
        )
        globalProduct.sizes = [globalSize]
        let globalRequest = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: globalProduct,
            selectedSize: globalSize,
            activeClosetItems: [savedShoppingItem],
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: globalProduct.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "tshirt",
            isRepresentative: true,
            didExplicitlyChangeClassification: false
        )
        guard case .saved(let savedGlobalItem) = FitMatchComparedProductClosetRegistration.save(
            globalRequest,
            in: context
        ) else {
            Issue.record("Expected the Global-confirmed product to save through the same action")
            return
        }
        #expect(savedGlobalItem.classificationAuthorityProvenance == .serverConfirmed)
        #expect(savedGlobalItem.isRepresentative)
    }

    /// CR-018/RX-007: two real submit tasks target the same storage request.
    /// The first is held only at the persistence side-effect boundary; the
    /// production action must reject the second task before it can call the
    /// real Closet registration operation.
    @Test func comparedProductClosetSubmissionSerializesConcurrentDuplicateSave() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let product = Product(
            name: "연속 등록 검증 티셔츠",
            category: .top,
            productCode: "E-CONCURRENT-SAVE",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E-CONCURRENT-SAVE",
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog
        )
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(.serverConfirmed)
        let size = ProductSize(
            name: "M",
            measurements: .init(shoulder: 47, chest: 52, totalLength: 69, sleeveLength: 23),
            product: product
        )
        product.sizes = [size]
        let request = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: product,
            selectedSize: size,
            activeClosetItems: [],
            brandName: "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: product.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "tshirt",
            isRepresentative: false,
            didExplicitlyChangeClassification: false
        )
        let gate = ComparedProductSubmissionGate()
        let action = FitMatchComparedProductClosetSubmissionAction()

        let first = Task { @MainActor in
            await action.submit {
                await gate.wait()
                return FitMatchComparedProductClosetRegistration.save(request, in: context)
            }
        }
        await gate.waitForArrival()

        let second = await action.submit {
            Issue.record("A duplicate linked save reached the registration operation")
            return FitMatchComparedProductClosetRegistration.save(request, in: context)
        }
        guard case .alreadyInFlight = second else {
            Issue.record("The second linked save was not blocked while the first was pending")
            return
        }

        await gate.open()
        guard case .completed(.saved) = await first.value else {
            Issue.record("The first linked save did not reach its normal production terminal")
            return
        }
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
    }

    @Test func stalePendingShareDoesNotReenterAProductFlow() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseHeadlessAcceptanceTests.StaleShare.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let url = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))

        let writer = SharedURLStore(
            fileURL: fileURL,
            now: { Date(timeIntervalSince1970: 0) }
        )
        writer.savePendingProductURL(url)
        let store = SharedURLStore(fileURL: fileURL)

        // A stale handoff must not reopen an unrelated product on a later app
        // entry. The timestamp is production state, not a scenario label.
        #expect(store.consumePendingProductURL() == nil)
    }

    /// EN-004: absence is not an error, but an actual failed Share handoff
    /// must give the app a production-used, user-visible recovery reason.
    @Test func sharedHandoffEntryActionDistinguishesNoIntentExpiredAndMalformedPayloads() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseHeadlessAcceptanceTests.ShareEntry.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let url = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))

        let empty = SharedURLStore(fileURL: fileURL)
        #expect(FitMatchPendingShareEntryAction.outcome(for: empty) == .none)

        let createdAt = Date(timeIntervalSince1970: 1_788_220_800)
        let writer = SharedURLStore(fileURL: fileURL, now: { createdAt })
        writer.savePendingProductURL(url)
        let expired = SharedURLStore(
            fileURL: fileURL,
            now: { createdAt.addingTimeInterval(SharedURLStore.pendingProductURLTimeToLive + 1) }
        )
        guard case .blocked(let expiredMessage) = FitMatchPendingShareEntryAction.outcome(for: expired) else {
            Issue.record("EN-004 expired handoff did not expose a recovery state")
            return
        }
        #expect(expiredMessage.contains("만료"))

        try Data("not-json".utf8).write(to: fileURL, options: .atomic)
        guard case .blocked(let malformedMessage) = FitMatchPendingShareEntryAction.outcome(for: empty) else {
            Issue.record("EN-004 malformed handoff did not expose a recovery state")
            return
        }
        #expect(malformedMessage.contains("다시 공유"))

        let unreadablePayloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseHeadlessAcceptanceTests.ShareUnavailable.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unreadablePayloadURL) }
        try FileManager.default.createDirectory(at: unreadablePayloadURL, withIntermediateDirectories: true)
        let unavailableStore = SharedURLStore(fileURL: unreadablePayloadURL)
        guard case .blocked(let unavailableMessage) = FitMatchPendingShareEntryAction.outcome(for: unavailableStore) else {
            Issue.record("EN-004 storage read failure did not expose a recovery state")
            return
        }
        #expect(unavailableMessage.contains("잠시 후"))

        writer.savePendingProductURL(url)
        guard case .open(let handoff) = FitMatchPendingShareEntryAction.outcome(for: writer) else {
            Issue.record("Fresh supported Share handoff did not reach the normal app entry action")
            return
        }
        #expect(handoff.urlString == url.absoluteString)
    }

    /// RX-005: the public replay envelope may omit duplicated top-level proof
    /// fields, but its owned immutable snapshot is still the exact begin
    /// proof. The production decoder must recover those fields from that
    /// snapshot so strict USER_EXPLICIT completion is not weakened or dropped.
    @Test func sameIDBeginReplayRecoversStrictProofOnlyFromItsImmutableSnapshot() throws {
        let comparisonID = UUID()
        let targetID = UUID()
        let variantID = UUID()
        let referenceID = UUID()
        let sizeID = UUID()
        let json = """
        {
          "comparison_id":"\(comparisonID)","created":false,"idempotent":true,
          "result_status":"PENDING",
          "snapshot":{
            "snapshot_schema_version":4,
            "reference_snapshot":{"closet_item_id":"\(referenceID)"},
            "authority_snapshot":{"effective_classification_at_begin":{
              "source":"USER_EXPLICIT","state":"PERSONAL_CONFIRMED",
              "category_code":"tops","garment_type_code":"polo_shirt",
              "audience_code":"WOMEN","sleeve_length_code":"short_sleeve",
              "comparison_policy_code":"polo_shirt",
              "effective_authority_fingerprint":"effective-r7"
            }},
            "input_snapshot":{"effective_authority_fingerprint":"effective-r7","personal_override_revision":7},
            "excluded_measurement_codes":[],
            "policy_snapshot":{"policy_code":"polo_shirt","policy_version":"v1","policy_checksum":"policy-v1","metrics":[{
              "metric_mode":"CANONICAL","fitmatch_measurement_code":"chest_width_pit_to_pit",
              "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,"is_active":true
            }]},
            "authorization_snapshot":{"decision":"MANUAL_EXTENDED","allowed":true,"mode":"MANUAL_EXTENDED",
              "reason":null,"excluded_measurement_codes":[],
              "required_measurement_codes":["chest_width_pit_to_pit"],
              "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
              "policy_code":"polo_shirt","policy_version":"v1","policy_checksum":"policy-v1"},
            "target_snapshot":{"product_id":"\(targetID)","variant_id":"\(variantID)",
              "authorized_candidate_product_size_ids":["\(sizeID)"],
              "candidate_authority_fingerprint":"candidate-r7","classification_status":"CONFIRMED",
              "garment_type_code":"polo_shirt","sleeve_length_code":"short_sleeve",
              "lower_length_code":null,"body_length_code":null,
              "candidates":[{
                "product_size_id":"\(sizeID)","size_label":"M",
                "availability":{"status":"AVAILABLE","observed_at":"2026-08-31T00:00:00Z",
                  "valid_until":"2026-09-01T00:00:00Z","evidence_fingerprint":"stock-r7"},
                "comparison_measurements":[{
                  "measurement_code":"chest_width_pit_to_pit","reference_value":50,"target_value":51,
                  "difference":1,"absolute_difference":1,"unit_code":"CM","basis_code":"WIDTH",
                  "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1
                }],
                "authorization":{"decision":"MANUAL_EXTENDED","allowed":true,"mode":"MANUAL_EXTENDED",
                  "reason":null,"excluded_measurement_codes":[],
                  "required_measurement_codes":["chest_width_pit_to_pit"],
                  "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
                  "policy_code":"polo_shirt","policy_version":"v1","policy_checksum":"policy-v1"}
              }]
            }
          }
        }
        """
        let response = try JSONDecoder().decode(
            FitMatchBeginComparisonResponse.self,
            from: Data(json.utf8)
        )
        let begin = try #require(response.vnext)
        #expect(begin.comparisonID == comparisonID)
        #expect(begin.idempotent)
        #expect(begin.authorization?.allowed == true)
        #expect(begin.authorization?.mode == "MANUAL_EXTENDED")
        #expect(begin.authorizedCandidateProductSizeIDs == [sizeID])
        #expect(begin.candidateAuthorityFingerprint == "candidate-r7")
        #expect(begin.effectiveAuthorityFingerprint == "effective-r7")
        #expect(begin.snapshotSchemaVersion == 4)
        #expect(begin.snapshot.target.productID == targetID)
        #expect(begin.snapshot.target.variantID == variantID)
    }

    @Test func deepLinkRoutingConsumesOnlyAnExplicitCompareRoute() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseHeadlessAcceptanceTests.EntryRouting.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = SharedURLStore(fileURL: fileURL)
        let productURL = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))
        let unknownRoute = try #require(URL(string: "fitmatch://unknown"))
        let compareRoute = try #require(URL(string: "fitmatch://compare"))

        store.savePendingProductURL(productURL)
        let firstHandoff = try #require(store.pendingProductURLHandoff())

        // EN-005: an unknown app route must not consume a valid pending Share.
        #expect(FitMatchProductEntryRouting.action(for: unknownRoute) == .ignore)
        #expect(store.pendingProductURLHandoff() == firstHandoff)

        // EN-001/EN-012: only the explicit compare route may request the exact
        // handoff; ContentView performs the generation-safe clear after it is
        // actually presented.
        #expect(FitMatchProductEntryRouting.action(for: compareRoute) == .openPendingProductCompare)
        #expect(store.pendingProductURLHandoff() == firstHandoff)
        #expect(store.clearPendingProductURL(
            ifMatching: firstHandoff.urlString,
            token: firstHandoff.token
        ))
        #expect(store.pendingProductURLHandoff() == nil)
    }

    @Test func pendingShareTTLAndGenerationCASFailClosedWithoutDroppingNewerShare() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseHeadlessAcceptanceTests.ShareTTL.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let createdAt = Date(timeIntervalSince1970: 1_788_220_800)
        let first = try #require(URL(string:
            "https://www.uniqlo.com/kr/ko/products/E450259-000/00"
        ))
        let second = try #require(URL(string:
            "https://www.zara.com/kr/ko/example-p06224446.html?v1=498706001"
        ))

        let writer = SharedURLStore(fileURL: fileURL, now: { createdAt })
        writer.savePendingProductURL(first)
        #expect(writer.pendingProductURL() == first.absoluteString)

        let justWithinTTL = SharedURLStore(
            fileURL: fileURL,
            now: { createdAt.addingTimeInterval(SharedURLStore.pendingProductURLTimeToLive - 1) }
        )
        #expect(justWithinTTL.pendingProductURL() == first.absoluteString)

        let expired = SharedURLStore(
            fileURL: fileURL,
            now: { createdAt.addingTimeInterval(SharedURLStore.pendingProductURLTimeToLive + 1) }
        )
        #expect(expired.pendingProductURL() == nil)
        #expect(expired.consumePendingProductURL() == nil)

        // Malformed or timestamp-less payloads fail closed and are removed as
        // one unit. A later valid B write is a new generation, not a partial
        // resurrection of A.
        try Data("{\"schemaVersion\":1,\"urlString\":\"\(first.absoluteString)\",\"generation\":\"missing-time\"}".utf8)
            .write(to: fileURL, options: .atomic)
        #expect(writer.pendingProductURL() == nil)
        writer.savePendingProductURL(second)
        #expect(writer.pendingProductURL() == second.absoluteString)

        // A's acknowledgement must not erase a newer B generation.
        try? FileManager.default.removeItem(at: fileURL)
        writer.savePendingProductURL(first)
        let firstHandoff = try #require(writer.pendingProductURLHandoff())
        writer.savePendingProductURL(second)
        #expect(
            writer.clearPendingProductURL(
                ifMatching: firstHandoff.urlString,
                token: firstHandoff.token
            ) == false
        )
        #expect(writer.pendingProductURL() == second.absoluteString)

        // Epoch-era payloads are explicitly stale, independent of the current
        // app process date.
        let epochWriter = SharedURLStore(
            fileURL: fileURL,
            now: { Date(timeIntervalSince1970: 0) }
        )
        epochWriter.savePendingProductURL(first)
        #expect(expired.pendingProductURL() == nil)
    }

    @Test func v4PersonalHistoryHydrationKeepsEachImmutableAuthorityProjection() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let productID = UUID()
        let firstReferenceID = UUID()
        let secondReferenceID = UUID()
        let first = try v4HistoryRow(
            targetProductID: productID,
            referenceClientItemID: firstReferenceID,
            garment: "polo_shirt",
            revision: 1,
            audience: "MEN"
        )
        let second = try v4HistoryRow(
            targetProductID: productID,
            referenceClientItemID: secondReferenceID,
            garment: "tshirt",
            revision: 2,
            audience: "WOMEN"
        )
        let third = try v4HistoryRow(
            targetProductID: productID,
            referenceClientItemID: UUID(),
            garment: "hoodie",
            revision: 3,
            audience: "KIDS"
        )

        _ = try VNextHistoryCacheHydrator().hydrateCompleted(
            [first, second, third],
            existingHistories: [],
            existingProducts: [],
            existingClosetItems: [],
            modelContext: context
        )
        let histories = try context.fetch(
            FetchDescriptor<RecommendationHistory>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )

        #expect(histories.count == 3)
        #expect(histories[0].product.classificationAuthorityProvenance == .userExplicit)
        #expect(histories[0].product.garmentTypeRawValue == "polo_shirt")
        #expect(histories[0].product.genderCodes == "MEN")
        #expect(histories[0].product.productTargetGender == .men)
        #expect(histories[1].product.classificationAuthorityProvenance == .userExplicit)
        #expect(histories[1].product.garmentTypeRawValue == "tshirt")
        #expect(histories[1].product.genderCodes == "WOMEN")
        #expect(histories[1].product.productTargetGender == .women)
        #expect(histories[2].product.classificationAuthorityProvenance == .userExplicit)
        #expect(histories[2].product.garmentTypeRawValue == "hoodie")
        #expect(histories[2].product.genderCodes == "KIDS")
        #expect(histories[2].product.productTargetGender == .kids)
        #expect(histories[0].product !== histories[1].product)
        #expect(histories[1].product !== histories[2].product)
        #expect(histories[0].userFit.id != histories[1].userFit.id)
        #expect(histories[0].userFit !== histories[1].userFit)
    }

    @Test func v4PersonalHistoryProjectionSurvivesFreshContainerWithoutTupleSharing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FitMatch-v4-history-projection-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema(FitMatchSchemaV1.models)
        let storeURL = directory.appendingPathComponent("history.store")
        let targetID = UUID()
        let first = try v4HistoryRow(
            targetProductID: targetID,
            referenceClientItemID: UUID(),
            garment: "polo_shirt",
            revision: 1,
            audience: "MEN"
        )
        let second = try v4HistoryRow(
            targetProductID: targetID,
            referenceClientItemID: UUID(),
            garment: "tshirt",
            revision: 2,
            audience: "WOMEN"
        )

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            _ = try VNextHistoryCacheHydrator().hydrateCompleted(
                [first, second],
                existingHistories: [],
                existingProducts: [],
                existingClosetItems: [],
                modelContext: context
            )
        }

        let reloadConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        let reloadContainer = try ModelContainer(for: schema, configurations: [reloadConfiguration])
        let reloadContext = ModelContext(reloadContainer)
        let histories = try reloadContext.fetch(FetchDescriptor<RecommendationHistory>())
        let menHistory = try #require(histories.first { $0.id == first.clientComparisonID })
        let womenHistory = try #require(histories.first { $0.id == second.clientComparisonID })

        // HI-001...HI-005: two completed comparisons of the same remote target
        // retain their independent begin-time tuple after rehydration.
        #expect(menHistory.product.id == VNextHistoryProjectionIdentity.productID(
            comparisonID: first.clientComparisonID
        ))
        #expect(womenHistory.product.id == VNextHistoryProjectionIdentity.productID(
            comparisonID: second.clientComparisonID
        ))
        #expect(menHistory.product !== womenHistory.product)
        #expect(menHistory.product.productTargetGender == .men)
        #expect(womenHistory.product.productTargetGender == .women)
        #expect(menHistory.product.sourceURLString == "https://www.uniqlo.com/kr/ko/products/E450259")
        #expect(womenHistory.product.sourceURLString == "https://www.uniqlo.com/kr/ko/products/E450259")
        #expect(menHistory.product.garmentTypeRawValue == "polo_shirt")
        #expect(womenHistory.product.garmentTypeRawValue == "tshirt")
        #expect(menHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(womenHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(menHistory.product.canonicalSourceIdentity?.contains("revision=1") == true)
        #expect(womenHistory.product.canonicalSourceIdentity?.contains("revision=2") == true)
        #expect(menHistory.product.canonicalSourceIdentity?.contains(
            "target=\(targetID.uuidString.lowercased())"
        ) == true)
        #expect(womenHistory.product.canonicalSourceIdentity?.contains(
            "target=\(targetID.uuidString.lowercased())"
        ) == true)
    }

    /// HI-005 / HI-013: an immutable hydrated History projection carries the
    /// authoritative catalog URL only when the server supplied one. The same
    /// production action either starts a new comparison or explains why an
    /// old record cannot be reopened; it never silently no-ops or invents a
    /// URL from an opaque product key.
    @Test func hydratedHistoryRecompareUsesCanonicalURLOrReturnsMeaningfulUnavailableState() throws {
        let product = makeHistoryRoutingProduct()
        product.sourceURLString = "https://www.uniqlo.com/kr/ko/products/E450259"
        let reference = makeHistoryRoutingReference()
        let history = RecommendationHistory(
            product: product,
            recommendedSize: product.sizes[0],
            userFit: reference,
            totalDifference: 1,
            measurementDifferences: .init(shoulder: 0, chest: 1, totalLength: 0, sleeveLength: 0),
            comparisonMethod: "서버 승인 직접 비교"
        )

        guard case .openCompare(.supportedURL(let canonicalURL)) =
            FitMatchHistoryRecompareAction.outcome(for: history) else {
            Issue.record("HI-005 canonical History URL did not start the normal URL flow")
            return
        }
        #expect(canonicalURL == "https://www.uniqlo.com/kr/ko/products/E450259")

        product.sourceURLString = nil
        guard case .openCompare(.storedOfficialProduct(let storedProduct)) =
            FitMatchHistoryRecompareAction.outcome(for: history) else {
            Issue.record("HI-005 stored official identity did not enter the resolver flow")
            return
        }
        #expect(storedProduct === product)

        product.sourceName = "직접 입력"
        product.productCode = nil
        guard case .unavailable(let message) = FitMatchHistoryRecompareAction.outcome(for: history) else {
            Issue.record("HI-005 missing identity unexpectedly started a comparison")
            return
        }
        #expect(message.contains("상품 링크를 다시 열어"))
    }

    @Test func effectivePersonalTupleIsConsumedAtomicallyWithoutGlobalFieldCoalescing() async throws {
        let fixture = AtomicEffectiveTupleFixture()
        let parser = AtomicEffectiveTupleParser(product: fixture.parsedProduct)
        let remote = AtomicEffectiveTupleRemote(fixture: fixture)
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(uniqloParser: parser),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        let product = try #require(
            viewModel.makeProductForClosetRegistration(brand: nil)
        )
        let profile = try #require(
            CanonicalProfileSnapshotCoder.decode(product.canonicalProfileSnapshotJSON)
        )

        #expect(product.classificationAuthorityProvenance == .userExplicit)
        #expect(profile.semanticGarmentType == "polo_shirt")
        #expect(product.garmentTypeRawValue == "polo_shirt")
        #expect(product.genderCodes == "WOMEN")
        #expect(product.productTargetGender == .women)
        #expect(product.constructionTypeRawValue == "SINGLE")
        // The effective USER_EXPLICIT contract explicitly has no body-length
        // axis. The Global Product field is deliberately conflicting. A
        // field-wise fallback creates a tuple the server never issued.
        #expect(profile.lengthAxes.body == "not_applicable")
    }

    private func shareURLProvider(_ url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.url.identifier,
            visibility: .all
        ) { completion in
            completion(Data(url.absoluteString.utf8), nil)
            return nil
        }
        return provider
    }

    private func configuredDirectItem(
        gender: UserGender,
        category: ClothingCategory,
        detail: ClosetDetailCategory,
        productName: String
    ) -> AddClosetItemViewModel {
        let model = AddClosetItemViewModel(
            prefillCategory: category,
            prefillDetailCategory: detail,
            prefillGender: gender,
            prefillSourceOption: .manual,
            prefillBrand: "테스트 브랜드",
            prefillProductName: productName
        )
        model.measurementEntrySource = .fitmatchMeasured
        return model
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func sourceFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    /// Fixture-only construction for HI-005 / HI-013. The production routing
    /// action, rather than this fixture, decides whether a history can begin a
    /// new comparison.
    private func makeHistoryRoutingProduct() -> Product {
        let size = ProductSize(
            id: UUID(),
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 51,
                totalLength: 70,
                sleeveLength: 24
            ),
            displayOrder: 0
        )
        let product = Product(
            id: UUID(),
            name: "History routing target",
            brand: Brand(name: "UNIQLO"),
            category: .top,
            productCode: "E450259",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E450259",
            metadata: ProductMetadata(
                sourceCategoryPath: "tops > short sleeve",
                categoryDepth1Code: "tops",
                categoryDepth2Code: "short_sleeve",
                genderCodes: ["MEN"]
            ),
            sourceType: .officialStore,
            sourceName: "UNIQLO",
            sizes: [size]
        )
        product.markClassificationAuthority(
            .serverConfirmed,
            sourceIdentity: "history-routing-fixture"
        )
        return product
    }

    private func makeHistoryRoutingReference() -> UserFit {
        UserFit(
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "테스트 브랜드",
            gender: .men,
            productName: "기준 옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 45,
                chest: 50,
                totalLength: 69,
                sleeveLength: 22
            ),
            fitMemo: "",
            satisfaction: 4,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func v4HistoryRow(
        targetProductID: UUID,
        referenceClientItemID: UUID,
        garment: String,
        revision: Int,
        audience: String = "MEN"
    ) throws -> VNextComparisonHistoryDTO {
        let comparisonID = UUID()
        let clientComparisonID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        let createdAt = String(format: "2026-08-31T00:%02d:00Z", revision)
        let candidateFingerprint = "candidate-\(garment)-r\(revision)"
        let json = """
        {
          "id":"\(comparisonID)",
          "client_comparison_id":"\(clientComparisonID)",
          "reference_client_item_id":"\(referenceClientItemID)",
          "target_product_id":"\(targetProductID)",
          "target_variant_id":"\(variantID)",
          "target_product_name_snapshot":"개인 확정 상품 r\(revision)",
          "target_image_url_snapshot":null,
          "target_source_code_snapshot":"uniqlo",
          "target_source_product_key":"E450259",
          "target_canonical_url":"https://www.uniqlo.com/kr/ko/products/E450259",
          "target_category_code":"tops",
          "result_status":"COMPLETED",
          "recommended_product_size_id":"\(sizeID)",
          "recommended_size_label":"M",
          "fit_score":95,
          "reliability_level":2,
          "coverage_ratio":1,
          "engine_version":"fitmatch-ios-vnext-snapshot-v1",
          "result_evidence":{
            "recommended_product_size_id":"\(sizeID)",
            "score":95,"reliability":2,"coverage":1,
            "engine_version":"fitmatch-ios-vnext-snapshot-v1",
            "candidate_size_ranking":[{
              "product_size_id":"\(sizeID)","rank":1,"score":95
            }],
            "metric_evidence":[{
              "product_size_id":"\(sizeID)",
              "measurement_code":"chest_width_pit_to_pit",
              "reference_value":50,"target_value":51,"difference":1,
              "absolute_difference":1,"weight":1
            }]
          },
          "created_at":"\(createdAt)",
          "snapshot_schema_version":4,
          "excluded_measurement_codes":[],
          "reference_snapshot":{
            "source_code":"manual","item_name":"내 반팔 티셔츠","size_label":"M",
            "garment_type_code":"tshirt","audience_code":"\(audience)",
            "sleeve_length_code":"short_sleeve","lower_length_code":null,
            "body_length_code":null,"classification_source":"USER_EXPLICIT",
            "measurements":[{
              "fitmatch_measurement_code":"chest_width_pit_to_pit",
              "value":50,"unit_code":"CM","value_source":"USER"
            }]
          },
          "target_snapshot":{
            "product_id":"\(targetProductID)","variant_id":"\(variantID)",
            "authorized_candidate_product_size_ids":["\(sizeID)"],
            "candidate_authority_fingerprint":"candidate-authority-r\(revision)",
            "classification_status":"CONFIRMED",
            "garment_type_code":"\(garment)",
            "sleeve_length_code":"short_sleeve",
            "lower_length_code":null,"body_length_code":null,
            "candidates":[{
              "product_size_id":"\(sizeID)","size_label":"M",
              "availability":{
                "status":"AVAILABLE","observed_at":"2026-08-31T00:00:00Z",
                "valid_until":"2026-09-01T00:00:00Z",
                "evidence_fingerprint":"stock-r\(revision)"
              },
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
                "policy_code":"\(garment)","policy_version":"v1",
                "policy_checksum":"policy-v1"
              }
            }]
          },
          "authority_snapshot":{
            "global_classification_at_begin":{
              "status":"REVIEW_REQUIRED","garment_type_code":null
            },
            "personal_projection_at_begin":{
              "classification_source":"USER_EXPLICIT",
              "garment_type_code":"\(garment)","revision":\(revision),
              "selected_candidate_fingerprint":"\(candidateFingerprint)",
              "cleared_at":null
            },
            "effective_classification_at_begin":{
              "source":"USER_EXPLICIT","state":"PERSONAL_CONFIRMED",
              "category_code":"tops","garment_type_code":"\(garment)",
              "audience_code":"\(audience)","sleeve_length_code":"short_sleeve"
            }
          },
          "policy_snapshot":{
            "policy_code":"\(garment)","policy_version":"v1",
            "policy_checksum":"policy-v1",
            "metrics":[{
              "metric_mode":"CANONICAL",
              "fitmatch_measurement_code":"chest_width_pit_to_pit",
              "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,
              "is_active":true
            }]
          },
          "authorization_snapshot":{
            "decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC",
            "excluded_measurement_codes":[],
            "required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"\(garment)","policy_version":"v1",
            "policy_checksum":"policy-v1"
          },
          "input_snapshot":{
            "personal_override_revision":\(revision),
            "selected_candidate_fingerprint":"\(candidateFingerprint)"
          }
        }
        """
        return try JSONDecoder().decode(
            VNextComparisonHistoryDTO.self,
            from: Data(json.utf8)
        )
    }
}

private struct AtomicEffectiveTupleFixture: Sendable {
    let productID = UUID()
    let variantID = UUID()
    let productSizeID = UUID()
    let url = URL(string: "https://www.uniqlo.com/kr/ko/products/EATOMIC-000/00")!

    var parsedProduct: ParsedProductInfo {
        ParsedProductInfo(
            sourceURL: url,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "UNIQLO",
            productName: "Atomic Personal Polo",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [
                ParsedProductSize(
                    id: productSizeID,
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 48,
                        chest: 51,
                        totalLength: 70,
                        sleeveLength: 24
                    ),
                    availabilityStatus: "AVAILABLE"
                )
            ],
            productID: "EATOMIC",
            canonicalURLString: url.absoluteString,
            sourceCategoryPath: "tops > short sleeve",
            productTargetGender: .men,
            productMetadata: ProductMetadata(
                sourceCategoryPath: "tops > short sleeve",
                categoryDepth1Code: "tops",
                categoryDepth2Code: "short_sleeve",
                genderCodes: ["MEN"]
            )
        )
    }

    var classification: FitMatchDatabaseClassification {
        FitMatchDatabaseClassification(
            classificationID: productID,
            categoryCode: "tops",
            detailCode: "polo_shirt",
            garmentTypeCode: "polo_shirt",
            familyCode: "polo_shirt",
            lengthCode: "short_sleeve",
            bodyLengthCode: nil,
            status: "confirmed",
            method: "effective-v1",
            authorityStatus: "user_explicit",
            confidence: 1,
            requiresUserConfirmation: false,
            taxonomyPolicyVersion: "effective-v1",
            decisionVersion: "personal-r1"
        )
    }

    var runtime: FitMatchProductRuntimeResponse {
        get throws {
            let json = """
            {
              "runtime_state":"ready","comparison_ready":true,
              "product":{
                "product_id":"\(productID)","source":"uniqlo",
                "external_product_id":"EATOMIC","product_name":"Atomic Personal Polo",
                "canonical_url":"\(url.absoluteString)","audience":"MEN",
                "source_category_path":"tops > short sleeve",
                "source_category_codes":["tops","short_sleeve"],
                "image_url":null,"lifecycle_status":"active","input_fingerprint":"global-input"
              },
              "classification":{
                "classification_id":"\(productID)","category_code":"tops",
                "detail_code":"polo_shirt","garment_type_code":"polo_shirt",
                "family_code":"polo_shirt","length_code":"short_sleeve",
                "body_length_code":null,"status":"confirmed","method":"effective-v1",
                "authority_status":"user_explicit","confidence":1,
                "requires_user_confirmation":false,"taxonomy_policy_version":"effective-v1",
                "decision_version":"personal-r1"
              },
              "variants":[],
              "vnext":{
                "found":true,
                "product":{
                  "id":"\(productID)","source_code":"uniqlo",
                  "source_product_key":"EATOMIC","product_name":"Atomic Personal Polo",
                  "classification_status":"REVIEW_REQUIRED","product_structure_code":"SINGLE",
                  "audience_code":"MEN","category_code":"tops","garment_type_code":"tshirt",
                  "comparison_policy_code":"tshirt","sleeve_length_code":"short_sleeve",
                  "lower_length_code":null,"body_length_code":"long_length",
                  "resolver_version":"global-v1","input_fingerprint":"global-input"
                },
                "readiness":{"status":"READY","reason":null,"ready_size_count":1,"policy_metric_count":1},
                "variants":[{
                  "id":"\(variantID)","source_variant_key":"__default__",
                  "variant_label":null,"color_name":null,
                  "sizes":[{
                    "id":"\(productSizeID)","source_size_key":"M","size_label":"M",
                    "availability":{"status":"AVAILABLE","observed_at":"2026-08-31T00:00:00Z",
                      "valid_until":"2026-09-01T00:00:00Z","evidence_fingerprint":"stock"},
                    "canonical_measurements":{"semantic_conflict_count":0,"measurements":[{
                      "fitmatch_measurement_code":"chest_width_pit_to_pit","value":51,
                      "unit_code":"CM","basis_code":"WIDTH","source_measurement_code":"chest"
                    },{
                      "fitmatch_measurement_code":"shoulder_width_seam_to_seam","value":48,
                      "unit_code":"CM","basis_code":"WIDTH","source_measurement_code":"shoulder"
                    }]}
                  }]
                }],
                "effective_classification":{
                  "product_id":"\(productID)","state":"PERSONAL_CONFIRMED",
                  "classification_status":"CONFIRMED","effective_source":"USER_EXPLICIT",
                  "category_code":"tops","garment_type_code":"polo_shirt","audience_code":"WOMEN",
                  "sleeve_length_code":"short_sleeve","lower_length_code":null,"body_length_code":null,
                  "comparison_policy_code":"polo_shirt","product_structure_code":"SINGLE",
                  "override_revision":1,"effective_authority_fingerprint":"effective-r1",
                  "effective_contract_version":"effective-v1"
                }
              }
            }
            """
            return try JSONDecoder().decode(
                FitMatchProductRuntimeResponse.self,
                from: Data(json.utf8)
            )
        }
    }
}

@MainActor
private final class AtomicEffectiveTupleParser: ProductURLParsing {
    let product: ParsedProductInfo

    init(product: ParsedProductInfo) { self.product = product }
    func canParse(_ url: URL) -> Bool { true }
    func parse(from url: URL) async throws -> ParsedProductInfo { product }
}

private enum AtomicEffectiveTupleError: Error { case unexpected }

private actor AtomicEffectiveTupleRemote: FitMatchServerAuthorityRemoteServicing {
    let fixture: AtomicEffectiveTupleFixture

    init(fixture: AtomicEffectiveTupleFixture) { self.fixture = fixture }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        FitMatchProductResolutionResponse(
            productID: fixture.productID,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: fixture.classification,
            comparisonReady: true
        )
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        throw AtomicEffectiveTupleError.unexpected
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        try fixture.runtime
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        FitMatchClosetItemsResponse(state: "ready", items: [])
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        throw AtomicEffectiveTupleError.unexpected
    }
}

/// Test-only timing control for the actual registration persistence boundary.
/// It supplies no save result or business decision.
private actor ComparedProductSubmissionGate {
    private var arrived = false
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        arrived = true
        let pendingArrivals = arrivalWaiters
        arrivalWaiters.removeAll()
        pendingArrivals.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitForArrival() async {
        guard !arrived else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
private struct ShareAttachmentStub: FitMatchShareAttachmentLoading {
    let url: URL?
    let plainText: String?

    init(url: URL? = nil, plainText: String? = nil) {
        self.url = url
        self.plainText = plainText
    }

    var hasURLItem: Bool { url != nil }
    var hasPlainTextItem: Bool { plainText != nil }

    func loadURLItem() async -> Any? { url }
    func loadPlainTextItem() async -> Any? { plainText }
}
