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

/// A transient, Closet-local measurement snapshot used while registering a
/// linked retailer product.  It is intentionally a value type: changing this
/// snapshot must never mutate the shared ProductSize size chart.
struct FitMatchClosetMeasurementSnapshot: Equatable {
    var measurements: GarmentMeasurements
    var measurementRecords: [FitMatchClosetMeasurementRecordPayload]

    init(
        measurements: GarmentMeasurements,
        measurementRecords: [FitMatchClosetMeasurementRecordPayload]
    ) {
        self.measurements = measurements
        self.measurementRecords = measurementRecords
    }

    init(sourceSize: ProductSize) {
        self.init(
            measurements: sourceSize.measurements,
            sourceRecords: sourceSize.measurementRecords
        )
    }

    /// Existing linked Closet edits must start from the owning user's current
    /// snapshot, not from the shared ProductSize chart.  This is what keeps a
    /// category-only edit from overwriting a previous one-field correction.
    init(sourceClosetItem: UserFit) {
        self.init(
            measurements: sourceClosetItem.measurements,
            sourceRecords: sourceClosetItem.measurementRecords
        )
    }

    private init(
        measurements: GarmentMeasurements,
        sourceRecords: [GarmentMeasurementRecord]
    ) {
        self.measurements = measurements
        measurementRecords = sourceRecords.map { Self.payload(from: $0) }
    }

    private static func payload(
        from record: GarmentMeasurementRecord
    ) -> FitMatchClosetMeasurementRecordPayload {
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
            semanticStatus: record.semanticStatusRawValue,
            valueSource: FitMatchClosetMeasurementProvenance.transportValueSource(
                valueSource: nil,
                inputSource: record.inputSourceRawValue
            )
        )
    }

    func makeGarmentMeasurementRecords() -> [GarmentMeasurementRecord] {
        measurementRecords.map { record in
            let inputSource = MeasurementInputSource(rawValue: record.inputSource)
                ?? FitMatchClosetMeasurementProvenance.inputSource(
                    for: record.valueSource
                        ?? FitMatchClosetMeasurementProvenance.retailerSnapshot
                )
            return GarmentMeasurementRecord(
                value: record.value,
                unit: MeasurementUnit(rawValue: record.unit) ?? .centimeter,
                unitRawValue: record.unit,
                measurementCode: MeasurementCode(rawValue: record.measurementCode)
                    ?? FitMatchCanonicalMeasurementCode
                        .projection(for: record.measurementCode)?.localCode
                    ?? .unknown,
                measurementCodeRawValue: record.measurementCode,
                displayKind: MeasurementDisplayKind(rawValue: record.displayKind)
                    ?? .unknown,
                methodSource: record.methodSource,
                methodProfile: record.methodProfile,
                inputSource: inputSource,
                standardVersion: record.standardVersion,
                mappingVersion: record.mappingVersion,
                rawCode: record.rawCode,
                rawLabel: record.rawLabel,
                rawInfo: record.rawInfo,
                rawValueText: record.rawValueText,
                evidenceLevel: MeasurementEvidenceLevel(rawValue: record.evidenceLevel)
                    ?? .unknown,
                semanticStatus: MeasurementSemanticStatus(rawValue: record.semanticStatus)
                    ?? .unknownDefinition
            )
        }
    }
}

/// Editable state for a single linked ProductSize.  It reuses the selected
/// Closet taxonomy's existing measurement definitions and only creates a new
/// user record when the app has an explicit transport mapping for that
/// definition.  Unknown retailer records stay intact as opaque source facts.
struct FitMatchLinkedClosetMeasurementDraft: Equatable {
    private let baseline: FitMatchClosetMeasurementSnapshot
    private let category: ClothingCategory
    private let measurementKinds: [MeasurementKind]
    private var rawValues: [MeasurementKind: String]

    init(
        sourceSize: ProductSize,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        gender: UserGender
    ) {
        self.init(
            baseline: FitMatchClosetMeasurementSnapshot(sourceSize: sourceSize),
            category: category,
            detailCategory: detailCategory,
            gender: gender
        )
    }

    init(
        baseline: FitMatchClosetMeasurementSnapshot,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        gender: UserGender
    ) {
        self.baseline = baseline
        self.category = category
        measurementKinds = category.measurementKinds(
            detailCategory: detailCategory,
            gender: gender
        )
        rawValues = Dictionary(uniqueKeysWithValues: measurementKinds.map { kind in
            (kind, Self.formatted(Self.baselineValue(
                for: kind,
                in: baseline,
                category: category
            )))
        })
    }

    var kinds: [MeasurementKind] { measurementKinds }

    func rawValue(for kind: MeasurementKind) -> String {
        rawValues[kind] ?? ""
    }

    mutating func setRawValue(_ value: String, for kind: MeasurementKind) {
        rawValues[kind] = value
    }

    func sourceLabel(for kind: MeasurementKind) -> String {
        if isUserEdited(kind) {
            return "직접 측정/수정 값"
        }
        if let source = Self.sourceRecord(for: kind, in: baseline, category: category),
           FitMatchClosetMeasurementProvenance.isUserValue(
                valueSource: source.valueSource,
                inputSource: source.inputSource
           ) {
            return "직접 측정/수정 값"
        }
        if Self.baselineValue(for: kind, in: baseline, category: category) != nil {
            return "쇼핑몰·API 자동 입력"
        }
        return "직접 추가 가능"
    }

    func isSupported(for kind: MeasurementKind) -> Bool {
        if let source = Self.sourceRecord(for: kind, in: baseline, category: category) {
            return FitMatchCanonicalMeasurementCode
                .canonicalCode(forTransportRawCode: source.measurementCode) != nil
        }
        guard let desiredCode = Self.desiredCanonicalCode(for: kind, category: category)
        else { return false }

        // Do not replace an existing canonical retailer fact whose detailed
        // local meaning is intentionally unknown (for example, an unspecified
        // sleeve basis) with a guessed user mapping. The source row remains
        // preserved, but this field is not editable until the definition is
        // explicitly supported.
        let hasUneditableExistingCode = baseline.measurementRecords.contains {
            Self.canonicalCode(for: $0) == desiredCode
        }
        return !hasUneditableExistingCode
    }

    func validationMessage() -> String? {
        for kind in measurementKinds {
            let raw = rawValue(for: kind).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            guard let value = Double(raw), value.isFinite, value > 0 else {
                return "(kind.title) 실측값은 0보다 큰 숫자로 입력해 주세요."
            }
            let definition = FitMatchMeasurementStandard.definition(
                for: kind,
                category: category
            )
            guard definition.validRange.contains(value) else {
                return "(kind.title)은 (definition.rangeDescription) 범위로 입력해 주세요."
            }
            guard isSupported(for: kind) else {
                return "(kind.title)은 현재 서버 실측 계약으로 추가 또는 수정할 수 없습니다."
            }
        }
        return nil
    }

    func snapshot() throws -> FitMatchClosetMeasurementSnapshot {
        if let message = validationMessage() {
            throw FitMatchLinkedClosetMeasurementDraftError.invalidInput(message)
        }

        var measurements = baseline.measurements
        var records = baseline.measurementRecords
        for kind in measurementKinds {
            let raw = rawValue(for: kind).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let value = Double(raw) else { continue }
            guard Self.baselineValue(for: kind, in: baseline, category: category) != value
            else { continue }

            if let source = Self.sourceRecord(for: kind, in: baseline, category: category),
               let index = records.firstIndex(of: source) {
                records[index] = Self.userRecord(
                    replacing: source,
                    value: value,
                    kind: kind
                )
            } else {
                records.append(Self.addedUserRecord(
                    value: value,
                    kind: kind,
                    category: category
                ))
            }
            measurements.set(value, for: kind)
        }

        return FitMatchClosetMeasurementSnapshot(
            measurements: measurements,
            measurementRecords: records
        )
    }

    private func isUserEdited(_ kind: MeasurementKind) -> Bool {
        let raw = rawValue(for: kind).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let value = Double(raw) else { return false }
        return Self.baselineValue(for: kind, in: baseline, category: category) != value
    }

    private static func baselineValue(
        for kind: MeasurementKind,
        in baseline: FitMatchClosetMeasurementSnapshot,
        category: ClothingCategory
    ) -> Double? {
        if let source = sourceRecord(for: kind, in: baseline, category: category) {
            return source.value
        }
        let hasSourceRecordForKind = baseline.measurementRecords.contains {
            $0.displayKind == kind.displayKind.rawValue
        }
        guard !hasSourceRecordForKind else { return nil }
        let value = baseline.measurements.value(for: kind)
        return value.isFinite && value > 0 ? value : nil
    }

    private static func sourceRecord(
        for kind: MeasurementKind,
        in baseline: FitMatchClosetMeasurementSnapshot,
        category: ClothingCategory
    ) -> FitMatchClosetMeasurementRecordPayload? {
        let records = baseline.measurementRecords.filter {
            $0.displayKind == kind.displayKind.rawValue
                && $0.value.isFinite
                && $0.value > 0
                && $0.semanticStatus == MeasurementSemanticStatus.mapped.rawValue
        }
        guard !records.isEmpty else { return nil }

        // A display axis is not a measurement semantic.  For example, chest
        // width and chest circumference can both be presented as “가슴”.  When
        // the selected Closet definition has a canonical code, only that
        // exact code may seed an editable field; an unmatched source row is
        // preserved and the user may add the selected definition separately.
        if let desiredCode = desiredCanonicalCode(for: kind, category: category) {
            let exact = records.filter { canonicalCode(for: $0) == desiredCode }
            if exact.count == 1 { return exact[0] }
            return nil
        }
        return records.count == 1 ? records[0] : nil
    }

    private static func desiredCanonicalCode(
        for kind: MeasurementKind,
        category: ClothingCategory
    ) -> String? {
        FitMatchCanonicalMeasurementCode.canonicalCode(
            for: ManualMeasurementRecordFactory.fitmatchCode(
                for: kind,
                category: category
            )
        )
    }

    private static func canonicalCode(
        for record: FitMatchClosetMeasurementRecordPayload
    ) -> String? {
        FitMatchCanonicalMeasurementCode.canonicalCode(
            forTransportRawCode: record.measurementCode
        )
    }

    private static func userRecord(
        replacing source: FitMatchClosetMeasurementRecordPayload,
        value: Double,
        kind: MeasurementKind
    ) -> FitMatchClosetMeasurementRecordPayload {
        FitMatchClosetMeasurementRecordPayload(
            value: value,
            unit: MeasurementUnit.centimeter.rawValue,
            measurementCode: source.measurementCode,
            displayKind: source.displayKind,
            methodSource: "fitmatch",
            methodProfile: FitMatchMeasurementStandard.version,
            inputSource: MeasurementInputSource.userMeasured.rawValue,
            standardVersion: FitMatchMeasurementStandard.version,
            mappingVersion: "manual_measurement_mapping_v1",
            rawCode: source.rawCode,
            rawLabel: kind.title,
            rawInfo: source.rawInfo,
            rawValueText: formatted(value),
            evidenceLevel: MeasurementEvidenceLevel.fitmatchDefined.rawValue,
            semanticStatus: MeasurementSemanticStatus.mapped.rawValue,
            valueSource: FitMatchClosetMeasurementProvenance.userManual
        )
    }

    private static func addedUserRecord(
        value: Double,
        kind: MeasurementKind,
        category: ClothingCategory
    ) -> FitMatchClosetMeasurementRecordPayload {
        let code = ManualMeasurementRecordFactory.fitmatchCode(
            for: kind,
            category: category
        )
        return FitMatchClosetMeasurementRecordPayload(
            value: value,
            unit: MeasurementUnit.centimeter.rawValue,
            measurementCode: code.rawValue,
            displayKind: kind.displayKind.rawValue,
            methodSource: "fitmatch",
            methodProfile: FitMatchMeasurementStandard.version,
            inputSource: MeasurementInputSource.userMeasured.rawValue,
            standardVersion: FitMatchMeasurementStandard.version,
            mappingVersion: "manual_measurement_mapping_v1",
            // A newly added FitMatch definition has no retailer/parser row.
            // Keep its source identity absent rather than using its canonical
            // code as a look-alike raw source identifier.
            rawCode: nil,
            rawLabel: kind.title,
            rawInfo: nil,
            rawValueText: formatted(value),
            evidenceLevel: MeasurementEvidenceLevel.fitmatchDefined.rawValue,
            semanticStatus: MeasurementSemanticStatus.mapped.rawValue,
            valueSource: FitMatchClosetMeasurementProvenance.userManual
        )
    }

    private static func formatted(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "" }
        return value.rounded() == value
            ? String(Int(value))
            // The editable field is persistence input, not a display label.
            // `String(Double)` round-trips the stored value, whereas a one
            // decimal display formatter would turn an untouched 55.25 into a
            // false user edit (55.2) on the next save.
            : String(value)
    }
}

enum FitMatchLinkedClosetMeasurementDraftError: LocalizedError, Equatable {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        }
    }
}

private extension GarmentMeasurements {
    mutating func set(_ value: Double, for kind: MeasurementKind) {
        switch kind {
        case .shoulder: shoulder = value
        case .chest: chest = value
        case .totalLength: totalLength = value
        case .sleeveLength: sleeveLength = value
        case .upperAbdomen: upperAbdomen = value
        case .upperWaist: upperWaist = value
        case .waist: waist = value
        case .hip: hip = value
        case .thigh: thigh = value
        case .rise: rise = value
        case .hem: hem = value
        case .footLength: footLength = value
        case .underBust: underBust = value
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
        /// A transient personal snapshot for a linked item.  It is never
        /// written back to `selectedSize` or the shared Product graph.
        let measurementSnapshot: FitMatchClosetMeasurementSnapshot?
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
            measurementSnapshot: FitMatchClosetMeasurementSnapshot? = nil,
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
            self.measurementSnapshot = measurementSnapshot
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
                measurementSnapshot: measurementSnapshot,
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
            measurementSnapshot: request.measurementSnapshot,
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
        measurementSnapshot: FitMatchClosetMeasurementSnapshot? = nil,
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
            measurements: measurementSnapshot?.measurements ?? sourceSize.measurements,
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
        item.replaceMeasurementRecords(with:
            measurementSnapshot?.makeGarmentMeasurementRecords()
                ?? sourceSize.measurementRecords
        )
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
        let measurementSnapshot = request.measurementSnapshot
            ?? FitMatchClosetMeasurementSnapshot(sourceSize: request.selectedSize)
        let records = measurementSnapshot.measurementRecords
        let values = measurementValues(
            measurementSnapshot.measurements,
            records: records
        )
        let categoryCode = request.categoryCode
        let serverFamily = request.product.garmentTypeRawValue?.nilIfBlank
        let serverAxes = request.product.canonicalProfileSnapshot?.lengthAxes
        let serverLength: String? = {
            switch categoryCode {
            case "tops": return meaningfulAxis(serverAxes?.sleeve)
                    ?? request.product.sleeveTypeRawValue?.nilIfBlank
            case "bottoms", "leggings", "skirts": return meaningfulAxis(serverAxes?.pants)
                    ?? request.product.sleeveTypeRawValue?.nilIfBlank
            case "dresses": return meaningfulAxis(serverAxes?.body)
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
        // A verified Product tuple remains useful for an automatic Closet
        // registration, but it is not authority once this user explicitly
        // selected a personal Closet category.  Mixing the Product's family
        // with the user's category makes an invalid hybrid tuple (for example
        // `bottoms` + `tshirt`) and lets automatic classification leak back
        // into the saved override.
        let usesExplicitClosetClassification = request.didExplicitlySelectClosetClassification
        let localFamily = localClassification?.garmentFamily.rawValue
        let localLength = localClassification?.lengthType == .unknown
            ? nil
            : localClassification?.lengthType.rawValue
        let familyCode = usesExplicitClosetClassification
            ? localFamily
            : serverFamily ?? localFamily
        let lengthCode = usesExplicitClosetClassification
            ? localLength
            : serverLength ?? localLength
        // A confirmed outerwear tuple can have both sleeve and body axes.
        // Keep the server-issued body axis distinct from `lengthCode`; using
        // the latter as a body fallback would invent a tuple the server did
        // not issue.  Dresses retain their existing single body-axis fallback
        // for the legacy local registration path.
        let bodyLengthCode: String?
        if usesExplicitClosetClassification {
            bodyLengthCode = categoryCode == "dresses" ? lengthCode : nil
        } else {
            bodyLengthCode = meaningfulAxis(serverAxes?.body)
                ?? (categoryCode == "dresses" ? lengthCode : nil)
        }
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
            bodyLengthCode: bodyLengthCode,
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
        _ measurements: GarmentMeasurements,
        records: [FitMatchClosetMeasurementRecordPayload]
    ) -> [String: Double] {
        let recordValues: [String: Double] = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, Double)? in
            guard record.value.isFinite, record.value > 0 else { return nil }
            return (record.measurementCode, record.value)
        })
        if !recordValues.isEmpty { return recordValues }

        let values: [(String, Double)] = [
            ("shoulder_width", measurements.shoulder),
            ("chest_width", measurements.chest),
            ("body_length", measurements.totalLength),
            ("sleeve_length", measurements.sleeveLength),
            ("waist_width", measurements.waist),
            ("hip_width", measurements.hip),
            ("thigh_width", measurements.thigh),
            ("rise", measurements.rise),
            ("hem_width", measurements.hem),
            ("foot_length", measurements.footLength),
            ("under_bust_width", measurements.underBust)
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
