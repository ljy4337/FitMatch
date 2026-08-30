import Foundation
import SwiftData

enum VNextHistoryCacheHydrationError: LocalizedError, Equatable {
    case incompleteSnapshot(UUID)
    case missingReferenceIdentity(UUID)
    case completionMismatch(UUID)

    var errorDescription: String? {
        switch self {
        case .incompleteSnapshot:
            return "서버 비교 기록의 immutable snapshot이 불완전합니다."
        case .missingReferenceIdentity:
            return "서버 비교 기록의 내 옷 식별자를 복원할 수 없습니다."
        case .completionMismatch:
            return "서버 완료 결과와 immutable begin snapshot 재생 결과가 다릅니다."
        }
    }
}

/// Rebuilds only the local/offline presentation cache. Every score, candidate,
/// metric, and weight comes from the immutable vNext comparison snapshots.
@MainActor
struct VNextHistoryCacheHydrator {
    private let adapter = VNextComparisonEngineAdapter()

    func hydrateCompleted(
        _ rows: [VNextComparisonHistoryDTO],
        existingHistories: [RecommendationHistory],
        existingProducts: [Product],
        existingClosetItems: [UserFit],
        modelContext: ModelContext
    ) throws -> Set<UUID> {
        let existingHistoryIDs = Set(existingHistories.map(\.id))
        var productByID = Dictionary(uniqueKeysWithValues: existingProducts.map { ($0.id, $0) })
        var closetByClientID = Dictionary(
            uniqueKeysWithValues: existingClosetItems.map { ($0.id, $0) }
        )
        var hydrated = Set<UUID>()

        for row in rows where row.resultStatus == "COMPLETED" {
            guard !existingHistoryIDs.contains(row.clientComparisonID),
                  !hydrated.contains(row.clientComparisonID) else {
                continue
            }
            guard let begin = row.snapshotBegin,
                  let recommendedID = row.recommendedProductSizeID else {
                throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
            }
            let analysis = try adapter.analyze(begin)
            guard analysis.recommended.productSizeID == recommendedID,
                  completionMatches(row, analysis: analysis) else {
                throw VNextHistoryCacheHydrationError.completionMismatch(row.id)
            }

            let product = productByID[row.targetProductID]
                ?? makeProduct(from: row, modelContext: modelContext)
            productByID[row.targetProductID] = product
            let recommendedSize = try ensureRecommendedSize(
                id: recommendedID,
                row: row,
                product: product,
                modelContext: modelContext
            )

            guard let referenceClientID = row.referenceClientItemID else {
                throw VNextHistoryCacheHydrationError.missingReferenceIdentity(row.id)
            }
            let reference = closetByClientID[referenceClientID]
                ?? makeReference(
                    id: referenceClientID,
                    snapshot: row.referenceSnapshot,
                    modelContext: modelContext
                )
            closetByClientID[referenceClientID] = reference

            let detail = detailCategory(
                garmentType: row.targetSnapshot?.garmentTypeCode,
                sleeve: row.targetSnapshot?.sleeveLengthCode,
                lower: row.targetSnapshot?.lowerLengthCode,
                body: row.targetSnapshot?.bodyLengthCode
            )
            let result = analysis.recommended.result
            let history = RecommendationHistory(
                id: row.clientComparisonID,
                product: product,
                recommendedSize: recommendedSize,
                userFit: reference,
                totalDifference: result.averageDifference,
                measurementDifferences: result.signedDifferences,
                recommendationScore: result.score,
                trueToSizeRecommendation:
                    "서버에 보존된 비교 근거에서 \(recommendedSize.name) 사이즈가 가장 유사합니다.",
                oversizedRecommendation: "",
                comparisonMethod: row.authorizationSnapshot?.mode == "MANUAL_EXTENDED"
                    ? "서버 승인 확장 비교" : "서버 승인 직접 비교",
                fallbackReason: row.authorizationSnapshot?.mode == "MANUAL_EXTENDED"
                    ? "서버 정책이 승인한 공통 실측만 사용했습니다." : "",
                productDetailCategory: detail,
                comparisonResult: result,
                reason: "vNext immutable comparison history에서 복원했습니다.",
                createdAt: decodeDate(row.createdAt) ?? Date()
            )
            modelContext.insert(history)
            hydrated.insert(row.clientComparisonID)
        }

        if !hydrated.isEmpty {
            try modelContext.save()
        }
        return hydrated
    }

    private func completionMatches(
        _ row: VNextComparisonHistoryDTO,
        analysis: VNextComparisonBatchAnalysis
    ) -> Bool {
        guard let evidence = row.resultEvidence else { return false }
        let tolerance = 0.000_001
        return evidence.recommendedProductSizeID == analysis.recommended.productSizeID
            && abs(evidence.score - analysis.completionPayload.score) < tolerance
            && evidence.candidateSizeRanking == analysis.completionPayload.candidateSizeRanking
            && evidence.metricEvidence == analysis.completionPayload.metricEvidence
    }

    private func makeProduct(
        from row: VNextComparisonHistoryDTO,
        modelContext: ModelContext
    ) -> Product {
        let category = ClothingCategory.fromTaxonomyCode(row.targetCategoryCode ?? "other")
        let source = sourcePresentation(row.targetSourceCode)
        let sizes = (row.targetSnapshot?.candidates ?? []).enumerated().map { index, candidate in
            makeProductSize(candidate: candidate, displayOrder: index)
        }
        let product = Product(
            id: row.targetProductID,
            name: row.targetProductName,
            category: category,
            productCode: row.targetSourceProductKey,
            imageURLString: row.targetImageURL,
            metadata: ProductMetadata(
                genderCodes: [row.targetSnapshot?.garmentTypeCode == nil ? "UNKNOWN" : "UNISEX"]
            ),
            sourceType: source.type,
            sourceName: source.name,
            source: .catalog,
            sizes: sizes,
            createdAt: decodeDate(row.createdAt) ?? Date(),
            updatedAt: decodeDate(row.createdAt) ?? Date()
        )
        product.sourcePlatformCode = row.targetSourceCode
        product.categoryCode = row.targetCategoryCode
        product.garmentTypeRawValue = row.targetSnapshot?.garmentTypeCode
        product.sleeveTypeRawValue = row.targetSnapshot?.sleeveLengthCode
        product.checkedSizeName = row.recommendedSizeLabel
        product.markClassificationAuthority(
            .serverConfirmed,
            sourceIdentity: "fitmatch_vnext_history"
        )
        modelContext.insert(product)
        return product
    }

    private func ensureRecommendedSize(
        id: UUID,
        row: VNextComparisonHistoryDTO,
        product: Product,
        modelContext: ModelContext
    ) throws -> ProductSize {
        if let existing = product.sizes.first(where: { $0.id == id }) {
            return existing
        }
        guard let candidate = row.targetSnapshot?.candidates.first(where: {
            $0.productSizeID == id
        }) else {
            throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
        }
        let size = makeProductSize(candidate: candidate, displayOrder: product.sizes.count)
        size.product = product
        product.sizes.append(size)
        modelContext.insert(size)
        return size
    }

    private func makeProductSize(
        candidate: VNextAuthorizedCandidateDTO,
        displayOrder: Int
    ) -> ProductSize {
        let values = candidate.comparisonMeasurements.reduce(into: [String: Double]()) {
            $0[$1.measurementCode] = $1.targetValue
        }
        let size = ProductSize(
            id: candidate.productSizeID,
            name: candidate.sizeLabel,
            measurements: measurements(from: values),
            displayOrder: displayOrder
        )
        size.measurementRecords = measurementRecords(
            from: values,
            valueSource: "fitmatch_vnext_history",
            productSize: size
        )
        return size
    }

    private func makeReference(
        id: UUID,
        snapshot: FitMatchJSONValue,
        modelContext: ModelContext
    ) -> UserFit {
        let object = snapshot.objectValue ?? [:]
        let garment = object["garment_type_code"]?.stringValue
        let sleeve = object["sleeve_length_code"]?.stringValue
        let lower = object["lower_length_code"]?.stringValue
        let body = object["body_length_code"]?.stringValue
        let category = category(for: garment)
        let detail = detailCategory(
            garmentType: garment,
            sleeve: sleeve,
            lower: lower,
            body: body
        )
        let measurementValues = Dictionary(uniqueKeysWithValues: (
            object["measurements"]?.arrayValue ?? []
        ).compactMap { entry -> (String, Double)? in
            guard let row = entry.objectValue,
                  let code = row["fitmatch_measurement_code"]?.stringValue,
                  let value = row["value"]?.numberValue else { return nil }
            return (code, value)
        })
        let sourceCode = object["source_code"]?.stringValue ?? "manual"
        let source = sourcePresentation(sourceCode)
        let classificationSource = object["classification_source"]?.stringValue
        let item = UserFit(
            id: id,
            sourceType: source.type,
            sourceName: source.name,
            brandName: source.name,
            gender: UserGender.fromTaxonomyCode(
                object["audience_code"]?.stringValue?.lowercased() ?? "unknown"
            ),
            productName: object["item_name"]?.stringValue ?? "내 옷",
            category: category,
            detailCategory: detail,
            sizeName: object["size_label"]?.stringValue ?? "기준",
            measurements: measurements(from: measurementValues),
            fitMemo: "",
            satisfaction: 3,
            isRepresentative: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        item.sourcePlatformCode = sourceCode
        item.garmentTypeRawValue = garment
        item.sleeveTypeRawValue = sleeve
        item.measurementRecords = measurementRecords(
            from: measurementValues,
            valueSource: "fitmatch_vnext_history",
            userFit: item
        )
        item.markClassificationAuthority(
            classificationSource == "manual_override" ? .userExplicit : .serverConfirmed,
            sourceIdentity: classificationSource ?? "fitmatch_vnext_history"
        )
        item.markAsHistoryOnlyReferenceSnapshot()
        modelContext.insert(item)
        return item
    }

    private func measurements(from values: [String: Double]) -> GarmentMeasurements {
        var result = GarmentMeasurements(
            shoulder: 0,
            chest: 0,
            totalLength: 0,
            sleeveLength: 0
        )
        for (rawCode, value) in values {
            guard let code = MeasurementCode(rawValue: rawCode),
                  let kind = MeasurementComparisonEngine.measurementKind(for: code) else {
                continue
            }
            switch kind {
            case .shoulder: result.shoulder = value
            case .chest: result.chest = value
            case .totalLength: result.totalLength = value
            case .sleeveLength: result.sleeveLength = value
            case .upperAbdomen: result.upperAbdomen = value
            case .upperWaist: result.upperWaist = value
            case .waist: result.waist = value
            case .hip: result.hip = value
            case .thigh: result.thigh = value
            case .rise: result.rise = value
            case .hem: result.hem = value
            case .footLength: result.footLength = value
            case .underBust: result.underBust = value
            }
        }
        return result
    }

    private func measurementRecords(
        from values: [String: Double],
        valueSource: String,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> [GarmentMeasurementRecord] {
        values.sorted(by: { $0.key < $1.key }).compactMap { rawCode, value in
            guard let code = MeasurementCode(rawValue: rawCode),
                  let kind = MeasurementComparisonEngine.measurementKind(for: code) else {
                return nil
            }
            return GarmentMeasurementRecord(
                value: value,
                measurementCode: code,
                displayKind: kind.displayKind,
                methodSource: valueSource,
                inputSource: .importedSizeChart,
                mappingVersion: "fitmatch-vnext-history-v1",
                rawCode: rawCode,
                rawLabel: kind.title,
                evidenceLevel: .fitmatchDefined,
                semanticStatus: .mapped,
                productSize: productSize,
                userFit: userFit
            )
        }
    }

    private func category(for garment: String?) -> ClothingCategory {
        guard let garment else { return .other }
        if ["tshirt", "base_layer_top", "shirt", "blouse", "knit_top",
            "sweatshirt", "hoodie", "polo_shirt"].contains(garment) { return .top }
        if ["pants", "denim", "shorts", "skirt", "leggings"].contains(garment) {
            return .bottom
        }
        if ["jacket", "coat", "padding", "cardigan", "outerwear"].contains(garment) {
            return .outer
        }
        if garment == "dress" { return .dress }
        if garment.contains("underwear") || garment == "bra" { return .underwear }
        if garment.contains("shoe") || garment == "sneakers" { return .shoes }
        return .other
    }

    private func detailCategory(
        garmentType: String?,
        sleeve: String?,
        lower: String?,
        body: String?
    ) -> ClosetDetailCategory {
        if let garmentType {
            let direct = ClosetDetailCategory.fromTaxonomyCode(garmentType)
            if direct != .other { return direct }
        }
        if category(for: garmentType).serviceGroup == .top, let sleeve {
            let direct = ClosetDetailCategory.fromTaxonomyCode(sleeve)
            if direct != .other { return direct }
        }
        if category(for: garmentType).serviceGroup == .bottom, let lower {
            let direct = ClosetDetailCategory.fromTaxonomyCode(lower)
            if direct != .other { return direct }
        }
        if category(for: garmentType) == .dress { return .onePiece }
        if body == "long" && category(for: garmentType) == .outer { return .longPadding }
        return .other
    }

    private func sourcePresentation(_ source: String) -> (type: ProductSourceType, name: String) {
        switch source.lowercased() {
        case "uniqlo": return (.officialStore, "유니클로 공식몰")
        case "zara": return (.officialStore, "ZARA 공식몰")
        case "cos": return (.officialStore, "COS 공식몰")
        case "musinsa": return (.marketplace, "무신사")
        default: return (.manual, "FitMatch")
        }
    }

    private func decodeDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
