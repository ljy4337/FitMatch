import Foundation
import SwiftData

/// The three UUIDs returned by the vNext runtime are the only identity that a
/// linked Closet registration may send back to the server.  A display size
/// label is deliberately not part of this type: labels are presentation, not
/// database identity.
nonisolated struct FitMatchClosetRegistrationServerIdentity: Equatable, Sendable {
    let productID: UUID
    let productVariantID: UUID
    let productSizeID: UUID
}

/// Transient link-registration state. It is intentionally not persisted on
/// Product or ProductSize: those SwiftData identifiers also serve legacy and
/// offline paths, whereas this context exists only for one server-first link
/// submission.
nonisolated struct FitMatchClosetRegistrationServerContext: Equatable, Sendable {
    enum ClassificationState: Equatable, Sendable {
        case confirmed
        case reviewRequired
        case notApplicable
        case unavailable
    }

    let classificationState: ClassificationState
    let identitiesByDisplaySizeID: [UUID: FitMatchClosetRegistrationServerIdentity]
    /// Presentation eligibility derived from retailer garment facts before
    /// runtime forms replace parser data.  It remains separate from
    /// classificationState and from comparison readiness.
    let registerableDisplaySizeIDs: Set<UUID>

    init(
        classificationState: ClassificationState,
        identitiesByDisplaySizeID: [UUID: FitMatchClosetRegistrationServerIdentity] = [:],
        registerableDisplaySizeIDs: Set<UUID> = []
    ) {
        self.classificationState = classificationState
        self.identitiesByDisplaySizeID = identitiesByDisplaySizeID
        self.registerableDisplaySizeIDs = registerableDisplaySizeIDs
    }

    func identity(for displaySizeID: UUID) -> FitMatchClosetRegistrationServerIdentity? {
        identitiesByDisplaySizeID[displaySizeID]
    }

    func isRegisterable(displaySizeID: UUID) -> Bool {
        registerableDisplaySizeIDs.contains(displaySizeID)
    }

    var registrationBlockMessage: String? {
        switch classificationState {
        case .confirmed, .reviewRequired:
            return nil
        case .notApplicable:
            return "현재 이 상품은 옷장 등록 대상이 아닙니다."
        case .unavailable:
            return "서버 연결을 확인한 뒤 다시 저장해 주세요."
        }
    }
}

/// Builds the owned Closet row for a product that originated in the shopping
/// flow.  The sheet owns presentation, duplicate checks, and persistence; this
/// production action owns the classification-authority boundary shared by the
/// Result, History, Compare, and link-registration entry points.
///
/// In particular, a shopping USER_EXPLICIT classification is product-scoped.
/// It is not a Closet override unless the user separately changed the Closet
/// classification in that registration surface.
enum FitMatchComparedProductClosetRegistration {
    /// The production persistence action behind the compared-product Closet
    /// sheet.  The View owns the progress indicator, alert presentation, and
    /// dismissal; this action owns the existing identity, authority-boundary,
    /// reference, and save ordering so those semantics are available to every
    /// real entry point (and to headless tests) without a second implementation.
    struct SaveRequest {
        /// Created before the first RPC and reused for every retry. The local
        /// UserFit receives the exact same identifier after the server accepts
        /// the submission.
        let clientItemID: UUID
        let product: Product
        let selectedSize: ProductSize
        /// Non-nil only for the new server-first link path. It prevents normal
        /// registration from falling back to label based remote identity.
        let serverIdentity: FitMatchClosetRegistrationServerIdentity?
        /// True only when the selected exact display size retained a positive
        /// retailer garment measurement fact. The link View passes its
        /// transient server context proof; direct callers fall back to the
        /// shared ProductSize helper.
        let hasMeasurementEligibilityProof: Bool
        let activeClosetItems: [UserFit]
        let brandName: String
        let gender: UserGender
        let genderCode: String
        let productName: String
        let category: ClothingCategory
        let categoryCode: String
        let detailCategory: ClosetDetailCategory
        let detailCategoryCode: String
        let isRepresentative: Bool
        /// A user can change audience without having confirmed a Closet tuple.
        /// Keep that intent separate from the category/detail confirmation that
        /// may create USER_EXPLICIT.
        let didExplicitlyChangeAudience: Bool
        let didExplicitlySelectClosetClassification: Bool
        let didExplicitlyChangeClassification: Bool

        init(
            clientItemID: UUID = UUID(),
            product: Product,
            selectedSize: ProductSize,
            serverIdentity: FitMatchClosetRegistrationServerIdentity? = nil,
            hasMeasurementEligibilityProof: Bool? = nil,
            activeClosetItems: [UserFit],
            brandName: String,
            gender: UserGender,
            genderCode: String,
            productName: String,
            category: ClothingCategory,
            categoryCode: String,
            detailCategory: ClosetDetailCategory,
            detailCategoryCode: String,
            isRepresentative: Bool,
            didExplicitlyChangeClassification: Bool,
            didExplicitlyChangeAudience: Bool = false,
            didExplicitlySelectClosetClassification: Bool? = nil
        ) {
            self.clientItemID = clientItemID
            self.product = product
            self.selectedSize = selectedSize
            self.serverIdentity = serverIdentity
            self.hasMeasurementEligibilityProof = hasMeasurementEligibilityProof
                ?? FitMatchGarmentMeasurementPresence.hasAnyMeasurement(in: selectedSize)
            self.activeClosetItems = activeClosetItems
            self.brandName = brandName
            self.gender = gender
            self.genderCode = genderCode
            self.productName = productName
            self.category = category
            self.categoryCode = categoryCode
            self.detailCategory = detailCategory
            self.detailCategoryCode = detailCategoryCode
            self.isRepresentative = isRepresentative
            self.didExplicitlyChangeAudience = didExplicitlyChangeAudience
            self.didExplicitlySelectClosetClassification =
                didExplicitlySelectClosetClassification ?? didExplicitlyChangeClassification
            self.didExplicitlyChangeClassification = didExplicitlyChangeClassification
        }

        func replacingRepresentative(_ isRepresentative: Bool) -> SaveRequest {
            SaveRequest(
                clientItemID: clientItemID,
                product: product,
                selectedSize: selectedSize,
                serverIdentity: serverIdentity,
                hasMeasurementEligibilityProof: hasMeasurementEligibilityProof,
                activeClosetItems: activeClosetItems,
                brandName: brandName,
                gender: gender,
                genderCode: genderCode,
                productName: productName,
                category: category,
                categoryCode: categoryCode,
                detailCategory: detailCategory,
                detailCategoryCode: detailCategoryCode,
                isRepresentative: isRepresentative,
                didExplicitlyChangeClassification: didExplicitlyChangeClassification,
                didExplicitlyChangeAudience: didExplicitlyChangeAudience,
                didExplicitlySelectClosetClassification: didExplicitlySelectClosetClassification
            )
        }
    }

    enum SaveOutcome {
        case saved(UserFit)
        case savedWithoutReference(UserFit, String)
        case duplicate
        case storageLookupFailed
        case persistenceFailed
        case serverRejected(String)
        case serverAcceptedLocalPersistenceFailed(clientItemID: UUID)

        var userVisibleMessage: String? {
            switch self {
            case .saved:
                nil
            case .savedWithoutReference:
                nil
            case .duplicate:
                "이미 내 옷장에 등록된 사이즈입니다."
            case .storageLookupFailed:
                "저장된 상품 정보를 확인하지 못했습니다. 다시 시도해 주세요."
            case .persistenceFailed:
                "내 옷장에 저장하지 못했습니다. 다시 시도해 주세요."
            case .serverRejected(let message):
                message
            case .serverAcceptedLocalPersistenceFailed:
                "서버에는 등록됐지만 이 기기에 저장하지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    enum ServerPreparationError: LocalizedError, Equatable {
        case missingExactSizeIdentity
        case missingUsableMeasurement
        case invalidExplicitClassification

        var errorDescription: String? {
            switch self {
            case .missingExactSizeIdentity:
                return "서버 사이즈 정보를 다시 확인해 주세요."
            case .missingUsableMeasurement:
                return "선택한 사이즈는 실측 정보가 없어 내 옷장에 등록할 수 없습니다."
            case .invalidExplicitClassification:
                return "선택한 옷 분류를 서버에 안전하게 전달할 수 없습니다."
            }
        }
    }

    /// Immutable retry payload for a link registration. Keeping the local and
    /// remote requests together makes an ambiguous transport failure retry the
    /// same client_item_id rather than allocating a second Closet row.
    struct ServerFirstSubmission {
        let localRequest: SaveRequest
        let remoteRequest: FitMatchUpsertClosetItemRequest
    }

    static func prepareServerFirstSubmission(
        _ request: SaveRequest
    ) throws -> ServerFirstSubmission {
        guard request.hasMeasurementEligibilityProof else {
            throw ServerPreparationError.missingUsableMeasurement
        }
        guard let identity = request.serverIdentity else {
            throw ServerPreparationError.missingExactSizeIdentity
        }

        let override: FitMatchClosetClassificationOverride?
        if request.didExplicitlySelectClosetClassification {
            override = try closetClassificationOverride(for: request)
        } else {
            override = nil
        }

        return ServerFirstSubmission(
            localRequest: request,
            remoteRequest: FitMatchUpsertClosetItemRequest(
                clientItemID: request.clientItemID,
                item: closetItemPayload(for: request, isReference: false),
                productID: identity.productID,
                productVariantID: identity.productVariantID,
                productSizeID: identity.productSizeID,
                override: override
            )
        )
    }

    /// Performs the local half of the exact storage sequence previously owned by
    /// `AddComparedProductToClosetSheet.saveSelectedSize()`.  It deliberately
    /// does not infer a Closet classification: `makeUserFit` remains the
    /// single boundary that keeps shopping USER_EXPLICIT separate from an
    /// explicit Closet classification intent.
    @MainActor
    static func save(
        _ request: SaveRequest,
        in modelContext: ModelContext,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) -> SaveOutcome {
        if isDuplicate(request) {
            return .duplicate
        }

        let storedProducts: [Product]
        do {
            storedProducts = try modelContext.fetch(FetchDescriptor<Product>())
        } catch {
            return .storageLookupFailed
        }

        // ProductSize.id is a size-chart identifier, not a retailer-product
        // identity. Resolve an existing row by the retailer product first so
        // saving "M" never attaches this Closet item to another product's M.
        let storedProduct = storedProducts.first {
            isSameRetailerProduct($0, request.product)
        }
        let sourceProduct = storedProduct ?? request.product
        storedProduct?.refreshExternalPresentation(from: request.product)

        let sourceSize: ProductSize
        if request.serverIdentity != nil {
            // New link registrations carry exact runtime identity. Do not turn
            // an M/BLACK display label back into a database lookup while
            // selecting the SwiftData relationship either.
            sourceSize = storedProduct?.sizes.first {
                $0.id == request.selectedSize.id
            } ?? request.selectedSize
        } else {
            let selectedSizeKey = ParsedProductSizeNormalizer.normalizedSizeKey(
                for: request.selectedSize.name
            )
            sourceSize = storedProduct?.sizes.first {
                ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.name) == selectedSizeKey
            } ?? request.selectedSize
        }

        if sourceProduct.modelContext == nil {
            modelContext.insert(sourceProduct)
        }
        if sourceSize.product !== sourceProduct {
            sourceSize.product = sourceProduct
        }

        let item = makeUserFit(
            sourceProduct: sourceProduct,
            sourceSize: sourceSize,
            authorityProduct: request.product,
            brandName: request.brandName,
            gender: request.gender,
            genderCode: request.genderCode,
            productName: request.productName,
            category: request.category,
            categoryCode: request.categoryCode,
            detailCategory: request.detailCategory,
            detailCategoryCode: request.detailCategoryCode,
            isRepresentative: request.isRepresentative,
            didExplicitlyChangeClassification: request.didExplicitlyChangeClassification,
            didExplicitlySelectClosetClassification: request.didExplicitlySelectClosetClassification,
            serverApprovedAutomaticRegistration: request.serverIdentity != nil
                && !request.didExplicitlySelectClosetClassification,
            id: request.clientItemID
        )

        if request.isRepresentative,
           item.classificationAuthorityProvenance?.isComparisonAuthority == true {
            FitMatchClosetReferenceMutation.setRepresentative(
                item,
                among: request.activeClosetItems
            )
        }

        modelContext.insert(item)
        do {
            try persist(modelContext)
        } catch {
            modelContext.rollback()
            return .persistenceFailed
        }

        if item.classificationAuthorityProvenance == .userExplicit {
            SourceCategoryHistoryMatcher.saveMapping(
                for: sourceProduct,
                category: request.category,
                detailCategory: request.detailCategory
            )
        }
        FitMatchMetricsRecorder.shared.record(
            .closetCreated(
                origin: .comparedProduct,
                category: FitMatchMetricMajorCategory(category: item.category)
            )
        )
        return .saved(item)
    }

    static func isDuplicate(_ request: SaveRequest) -> Bool {
        isDuplicate(
            size: request.selectedSize,
            product: request.product,
            serverIdentity: request.serverIdentity,
            among: request.activeClosetItems
        )
    }

    static func makeUserFit(
        sourceProduct: Product,
        sourceSize: ProductSize,
        authorityProduct: Product,
        brandName: String,
        gender: UserGender,
        genderCode: String,
        productName: String,
        category: ClothingCategory,
        categoryCode: String,
        detailCategory: ClosetDetailCategory,
        detailCategoryCode: String,
        isRepresentative: Bool,
        didExplicitlyChangeClassification: Bool,
        didExplicitlySelectClosetClassification: Bool? = nil,
        serverApprovedAutomaticRegistration: Bool = false,
        id: UUID = UUID()
    ) -> UserFit {
        let item = UserFit(
            id: id,
            sourceType: sourceProduct.sourceType,
            sourceName: sourceProduct.sourceDisplayName,
            sourceCategoryPath: sourceProduct.sourceCategoryPath,
            sourceCategoryDepth1: sourceProduct.sourceCategoryDepth1,
            sourceCategoryDepth2: sourceProduct.sourceCategoryDepth2,
            sourceCategoryDepth3: sourceProduct.sourceCategoryDepth3,
            sourceCategoryDepth4: sourceProduct.sourceCategoryDepth4,
            brandName: brandName,
            gender: gender,
            productName: productName,
            category: category,
            detailCategory: detailCategory,
            sizeName: displaySizeName(for: sourceSize.name),
            measurements: sourceSize.measurements,
            fitMemo: "비교 상품에서 추가",
            fitPreference: .regular,
            satisfaction: 0,
            isRepresentative: isRepresentative,
            sourceProduct: sourceProduct,
            sourceProductSize: sourceSize
        )
        item.genderCode = genderCode
        item.categoryCode = categoryCode
        item.detailCategoryCode = detailCategoryCode

        let savedAuthority: FitMatchClassificationAuthorityProvenance
        if serverApprovedAutomaticRegistration {
            // A link registration whose runtime UUIDs were accepted without a
            // Closet override consumes the server's effective CONFIRMED tuple.
            // A product-scoped shopping USER_EXPLICIT must not leak into this
            // row as personal Closet authority, but it also must not degrade
            // the accepted server tuple to a local hint.
            savedAuthority = .serverConfirmed
        } else {
            savedAuthority = FitMatchClosetClassificationEditPolicy.resultingAuthority(
                current: authorityProduct.classificationAuthorityProvenance,
                isSourced: FitMatchClosetClassificationEditPolicy.isSourced(authorityProduct),
                isExplicitSet: FitMatchClosetClassificationEditPolicy.isExplicitSet(authorityProduct),
                didExplicitlyChangeClassification:
                    didExplicitlySelectClosetClassification ?? didExplicitlyChangeClassification,
                scope: .newSourcedRegistration
            )
        }
        applyAuthority(
            savedAuthority,
            to: item,
            authorityProduct: authorityProduct,
            category: category,
            detailCategory: detailCategory,
            productName: productName
        )
        item.replaceMeasurementRecords(with: sourceSize.measurementRecords)
        if item.classificationAuthorityProvenance
            == FitMatchClassificationAuthorityProvenance.userExplicit {
            _ = ComparisonProfileMatcher().profile(for: item)
        }
        return item
    }

    private static func applyAuthority(
        _ savedAuthority: FitMatchClassificationAuthorityProvenance,
        to item: UserFit,
        authorityProduct: Product,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        productName: String
    ) {
        if savedAuthority == .userExplicit {
            // Only the current registration surface's explicit Closet picker
            // may create this owned personal authority.  Product-derived
            // shopping Recovery facts are deliberately not reused here.
            let savedClassification = ParsedClosetClassification.resolve(
                category: category,
                detailCategory: detailCategory,
                sourceDepths: [],
                sourcePath: nil,
                productName: productName
            )
            item.normalizedProductTypeCode = savedClassification?.normalizedProductTypeCode
            if let savedClassification {
                item.garmentType = savedClassification.garmentFamily
                item.sleeveType = savedClassification.lengthType
                item.constructionType = savedClassification.constructionType
            }
            item.markClassificationAuthority(.userExplicit)
            return
        }

        if savedAuthority == .serverConfirmed {
            item.normalizedProductTypeCode = authorityProduct.normalizedProductTypeCode
            item.garmentTypeRawValue = authorityProduct.garmentTypeRawValue
            item.sleeveTypeRawValue = authorityProduct.sleeveTypeRawValue
            item.constructionTypeRawValue = authorityProduct.constructionTypeRawValue
            item.canonicalPolicyVersion = authorityProduct.canonicalPolicyVersion
            item.markClassificationAuthority(
                .serverConfirmed,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
            return
        }

        switch savedAuthority {
        case .serverReviewRequired:
            item.markClassificationAuthority(
                .serverReviewRequired,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
        case .serverNotComparable:
            item.markClassificationAuthority(
                .serverNotComparable,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
        case .serverUnavailable:
            item.markClassificationAuthority(
                .serverUnavailable,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
        default:
            item.markClassificationAuthority(.localHint)
        }
    }

    private static func displaySizeName(for rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalComponent = value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
        return SizeTokenNormalizer.displayName(for: finalComponent)
    }

    private static func isDuplicate(
        size: ProductSize,
        product: Product,
        serverIdentity: FitMatchClosetRegistrationServerIdentity?,
        among userFits: [UserFit]
    ) -> Bool {
        if let serverIdentity {
            return userFits.contains { item in
                item.sourceProductSize?.id == serverIdentity.productSizeID
            }
        }

        return userFits.contains { item in
            let selectedDisplaySize = displaySizeName(for: size.name)
            if item.sourceProductSize?.id == size.id {
                return true
            }

            if let sourceURL = product.sourceURLString,
               let itemURL = item.sourceProduct?.sourceURLString,
               sourceURL == itemURL,
               item.sizeName == selectedDisplaySize {
                return true
            }

            if let productCode = product.productCode,
               let itemProductCode = item.sourceProduct?.productCode,
               productCode == itemProductCode,
               item.sizeName == selectedDisplaySize {
                return true
            }

            if product.sourceURLString != nil,
               item.sourceProduct == nil,
               item.productName == product.name,
               item.sizeName == selectedDisplaySize,
               item.sourceName == product.sourceDisplayName,
               item.brandName == product.brand?.name {
                return true
            }

            return false
        }
    }

    private static func closetClassificationOverride(
        for request: SaveRequest
    ) throws -> FitMatchClosetClassificationOverride {
        let provider = FitMatchTaxonomyProvider.shared
        guard provider.isActiveCategory(request.categoryCode),
              provider.isValidDetail(
                request.detailCategoryCode,
                for: request.categoryCode
              ),
              ParsedClosetClassification.isConsistent(
                category: request.category,
                detailCategory: request.detailCategory,
                categoryCode: request.categoryCode,
                detailCode: request.detailCategoryCode
              ),
              let classification = ParsedClosetClassification.resolve(
                category: request.category,
                detailCategory: request.detailCategory,
                sourceDepths: [],
                sourcePath: nil,
                // The user-selected canonical taxonomy tuple is the input.
                // A display product name must not become a second authority.
                productName: ""
              ),
              classification.categoryCode == request.categoryCode,
              classification.detailCode == request.detailCategoryCode,
              classification.garmentFamily != .unknown else {
            throw ServerPreparationError.invalidExplicitClassification
        }

        let genericLength = classification.lengthType == .unknown
            ? nil
            : classification.lengthType.rawValue
        let bodyLength = request.categoryCode == "dresses" ? genericLength : nil
        return FitMatchClosetClassificationOverride(
            audienceCode: FitMatchCanonicalAudience.code(from: request.genderCode),
            categoryCode: request.categoryCode,
            detailCode: request.detailCategoryCode,
            // `garmentFamily` is the established app-to-vNext canonical
            // garment-type mapping. Its raw values are the same code family
            // consumed by the existing vNext sync adapter (tshirt, pants,
            // knit_cardigan, ...); it is not a display label.
            familyCode: classification.garmentFamily.rawValue,
            lengthCode: genericLength,
            bodyLengthCode: bodyLength,
            reason: "user_confirmed_closet_classification",
            evidence: [
                "classification_authority": FitMatchClassificationAuthorityProvenance
                    .userExplicit.rawValue,
                "client_item_id": request.clientItemID.uuidString
            ]
        )
    }

    private static func closetItemPayload(
        for request: SaveRequest,
        isReference: Bool
    ) -> FitMatchClosetItemPayload {
        let records = request.selectedSize.measurementRecords.map { record in
            FitMatchClosetMeasurementRecordPayload(
                value: record.value,
                unit: record.unitRawValue,
                measurementCode: record.measurementCodeRawValue,
                displayKind: record.displayKindRawValue,
                methodSource: record.methodSource,
                methodProfile: record.methodProfile,
                inputSource: record.inputSourceRawValue,
                standardVersion: record.standardVersion,
                mappingVersion: record.mappingVersion,
                rawCode: record.rawCode,
                rawLabel: record.rawLabel,
                rawInfo: record.rawInfo,
                rawValueText: record.rawValueText,
                evidenceLevel: record.evidenceLevelRawValue,
                semanticStatus: record.semanticStatusRawValue
            )
        }
        let values = measurementValues(for: request.selectedSize, records: records)
        let categoryCode = request.categoryCode
        let serverFamily = request.product.garmentTypeRawValue?.nilIfBlank
        let serverLength: String? = {
            let axes = request.product.canonicalProfileSnapshot?.lengthAxes
            switch categoryCode {
            case "tops": return meaningfulAxis(axes?.sleeve)
                    ?? request.product.sleeveTypeRawValue?.nilIfBlank
            case "bottoms", "leggings", "skirts": return meaningfulAxis(axes?.pants)
                    ?? request.product.sleeveTypeRawValue?.nilIfBlank
            case "dresses": return meaningfulAxis(axes?.body)
                    ?? request.product.sleeveTypeRawValue?.nilIfBlank
            default: return request.product.sleeveTypeRawValue?.nilIfBlank
            }
        }()
        let localClassification = ParsedClosetClassification.resolve(
            category: request.category,
            detailCategory: request.detailCategory,
            sourceDepths: [],
            sourcePath: nil,
            productName: ""
        )
        let familyCode = serverFamily ?? localClassification?.garmentFamily.rawValue
        let lengthCode = serverLength ?? (localClassification?.lengthType == .unknown
            ? nil
            : localClassification?.lengthType.rawValue)
        let source = sourceCode(for: request.product)
        return FitMatchClosetItemPayload(
            productName: request.productName,
            brand: request.brandName.nilIfBlank,
            sizeName: displaySizeName(for: request.selectedSize.name),
            genderCode: request.genderCode,
            source: source,
            categoryCode: categoryCode,
            detailCode: request.detailCategoryCode,
            familyCode: familyCode,
            lengthCode: lengthCode,
            bodyLengthCode: categoryCode == "dresses" ? lengthCode : nil,
            sourceCategoryPath: request.product.sourceCategoryPath,
            productURL: request.product.sourceURLString,
            imageURL: request.product.imageURLString,
            measurements: values,
            measurementRecords: records,
            fitMemo: "비교 상품에서 추가",
            fitPreferenceCode: "regular",
            satisfaction: 0,
            isReference: isReference,
            classificationVersion: request.product.canonicalPolicyVersion,
            clientSnapshot: [
                "local_model": "UserFit",
                "link_registration": "server_first",
                "client_item_id": request.clientItemID.uuidString
            ],
            clientCreatedAt: ISO8601DateFormatter().string(from: Date()),
            clientUpdatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private static func measurementValues(
        for size: ProductSize,
        records: [FitMatchClosetMeasurementRecordPayload]
    ) -> [String: Double] {
        let recordValues: [String: Double] = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, Double)? in
            guard record.value.isFinite, record.value > 0 else { return nil }
            return (record.measurementCode, record.value)
        })
        if !recordValues.isEmpty { return recordValues }

        let values: [(String, Double)] = [
            ("shoulder_width", size.shoulder),
            ("chest_width", size.chest),
            ("body_length", size.totalLength),
            ("sleeve_length", size.sleeveLength),
            ("waist_width", size.waist),
            ("hip_width", size.hip),
            ("thigh_width", size.thigh),
            ("rise", size.rise),
            ("hem_width", size.hem),
            ("foot_length", size.footLength),
            ("under_bust_width", size.underBust)
        ]
        return Dictionary(uniqueKeysWithValues: values.filter {
            $0.1.isFinite && $0.1 > 0
        })
    }

    private static func sourceCode(for product: Product) -> String {
        if let code = product.sourcePlatformCode?.nilIfBlank { return code.lowercased() }
        let name = product.sourceDisplayName.lowercased()
        if name.contains("무신사") { return "musinsa" }
        if name.contains("유니클로") { return "uniqlo" }
        if name.contains("zara") || name.contains("자라") { return "zara" }
        if name.contains("cos") { return "cos" }
        return "manual"
    }

    private static func meaningfulAxis(_ value: String?) -> String? {
        guard let value = value?.nilIfBlank,
              value != "unknown",
              value != "not_applicable" else {
            return nil
        }
        return value
    }

    static func isSameRetailerProduct(_ lhs: Product, _ rhs: Product) -> Bool {
        if let lhsURL = normalizedSourceURL(lhs.sourceURLString),
           let rhsURL = normalizedSourceURL(rhs.sourceURLString) {
            return lhsURL == rhsURL
        }

        guard let lhsCode = normalizedText(lhs.productCode), !lhsCode.isEmpty,
              let rhsCode = normalizedText(rhs.productCode), !rhsCode.isEmpty,
              lhsCode == rhsCode else {
            return false
        }

        let lhsPlatform = normalizedText(lhs.sourcePlatformCode)
        let rhsPlatform = normalizedText(rhs.sourcePlatformCode)
        return lhsPlatform == nil || rhsPlatform == nil || lhsPlatform == rhsPlatform
    }

    private static func normalizedSourceURL(_ value: String?) -> String? {
        guard var value = normalizedText(value)?.lowercased(), !value.isEmpty else {
            return nil
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func normalizedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
