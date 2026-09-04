import Foundation
import SwiftData

/// Stable local identities for immutable vNext presentation projections. The
/// server Product/size/reference IDs remain in the completed snapshot; these
/// IDs prevent separate comparison records from sharing mutable SwiftData
/// objects locally.
enum VNextHistoryProjectionIdentity {
    static func productID(comparisonID: UUID) -> UUID {
        comparisonID
    }

    static func productSizeID(comparisonID: UUID, productSizeID: UUID) -> UUID {
        derivedID(comparisonID: comparisonID, originalID: productSizeID, discriminator: 0x31)
    }

    static func referenceID(comparisonID: UUID, clientItemID: UUID) -> UUID {
        derivedID(comparisonID: comparisonID, originalID: clientItemID, discriminator: 0x51)
    }

    private static func derivedID(
        comparisonID: UUID,
        originalID: UUID,
        discriminator: UInt8
    ) -> UUID {
        let lhs = comparisonID.uuid
        let rhs = originalID.uuid
        return UUID(uuid: (
            lhs.0 ^ rhs.0 ^ discriminator,
            lhs.1 ^ rhs.1,
            lhs.2 ^ rhs.2,
            lhs.3 ^ rhs.3,
            lhs.4 ^ rhs.4,
            lhs.5 ^ rhs.5,
            lhs.6 ^ rhs.6,
            lhs.7 ^ rhs.7,
            lhs.8 ^ rhs.8,
            lhs.9 ^ rhs.9,
            lhs.10 ^ rhs.10,
            lhs.11 ^ rhs.11,
            lhs.12 ^ rhs.12,
            lhs.13 ^ rhs.13,
            lhs.14 ^ rhs.14,
            lhs.15 ^ rhs.15
        ))
    }
}

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

    /// A completed v4 comparison is an immutable, begin-time artifact.  It
    /// cannot be represented by the mutable current Product cache when the
    /// same retailer Product was compared under a different personal revision.
    private struct HistoricalTargetProjection {
        let localProductID: UUID
        let usesImmutableProjection: Bool
        let authority: FitMatchClassificationAuthorityProvenance
        let sourceIdentity: String
        let categoryCode: String?
        let garmentTypeCode: String?
        let audienceCode: String?
        let sleeveLengthCode: String?
        let lowerLengthCode: String?
        let bodyLengthCode: String?
        let policyCode: String?
        let policyVersion: String?
        let personalRevision: Int?
        let candidateFingerprint: String?

        private init(
            localProductID: UUID,
            usesImmutableProjection: Bool,
            authority: FitMatchClassificationAuthorityProvenance,
            sourceIdentity: String,
            categoryCode: String?,
            garmentTypeCode: String?,
            audienceCode: String?,
            sleeveLengthCode: String?,
            lowerLengthCode: String?,
            bodyLengthCode: String?,
            policyCode: String?,
            policyVersion: String?,
            personalRevision: Int?,
            candidateFingerprint: String?
        ) {
            self.localProductID = localProductID
            self.usesImmutableProjection = usesImmutableProjection
            self.authority = authority
            self.sourceIdentity = sourceIdentity
            self.categoryCode = categoryCode
            self.garmentTypeCode = garmentTypeCode
            self.audienceCode = audienceCode
            self.sleeveLengthCode = sleeveLengthCode
            self.lowerLengthCode = lowerLengthCode
            self.bodyLengthCode = bodyLengthCode
            self.policyCode = policyCode
            self.policyVersion = policyVersion
            self.personalRevision = personalRevision
            self.candidateFingerprint = candidateFingerprint
        }

        init(row: VNextComparisonHistoryDTO) throws {
            guard row.snapshotSchemaVersion >= 4 else {
                self = Self.legacy(row: row)
                return
            }

            guard let authorityRoot = row.authoritySnapshot.objectValue,
                  let effective = authorityRoot[
                    "effective_classification_at_begin"
                  ]?.objectValue,
                  let source = effective["source"]?.stringValue?.uppercased(),
                  let state = effective["state"]?.stringValue?.uppercased(),
                  let garment = effective["garment_type_code"]?.stringValue,
                  !garment.isEmpty else {
                throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
            }

            let personal = authorityRoot["personal_projection_at_begin"]?.objectValue
            let provenance: FitMatchClassificationAuthorityProvenance
            let revision: Int?
            let candidateFingerprint: String?
            switch source {
            case "USER_EXPLICIT":
                guard state == "PERSONAL_CONFIRMED",
                      let numericRevision = personal?["revision"]?.numberValue,
                      numericRevision >= 1,
                      let fingerprint = personal?["selected_candidate_fingerprint"]?.stringValue,
                      !fingerprint.isEmpty else {
                    throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
                }
                provenance = .userExplicit
                revision = Int(numericRevision)
                candidateFingerprint = fingerprint
            case "GLOBAL_CONFIRMED", "GLOBAL":
                guard state == "GLOBAL_CONFIRMED" || state == "CONFIRMED" else {
                    throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
                }
                provenance = .serverConfirmed
                revision = nil
                candidateFingerprint = nil
            default:
                throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
            }

            let category = effective["category_code"]?.stringValue
            let audience = effective["audience_code"]?.stringValue
            let sleeve = Self.axis(effective["sleeve_length_code"])
            let lower = Self.axis(effective["lower_length_code"])
            let body = Self.axis(effective["body_length_code"])
            let policyCode = row.policySnapshot?.policyCode
                ?? row.authorizationSnapshot?.policyCode
            let policyVersion = row.policySnapshot?.policyVersion
                ?? row.authorizationSnapshot?.policyVersion
            let authorityFingerprint = effective[
                "effective_authority_fingerprint"
            ]?.stringValue ?? row.inputSnapshot.objectValue?[
                "effective_authority_fingerprint"
            ]?.stringValue
            let revisionString = revision.map(String.init) ?? "none"
            let candidateString = candidateFingerprint ?? "none"
            let authorityString = authorityFingerprint ?? "none"
            let categoryString = category ?? "nil"
            let sleeveString = sleeve ?? "nil"
            let lowerString = lower ?? "nil"
            let bodyString = body ?? "nil"
            let identity = [
                "fitmatch_vnext_history_v4",
                "comparison=\(row.clientComparisonID.uuidString.lowercased())",
                "target=\(row.targetProductID.uuidString.lowercased())",
                "source=\(source.lowercased())",
                "revision=\(revisionString)",
                "candidate=\(candidateString)",
                "authority=\(authorityString)",
                "audience=\(audience ?? "nil")",
                "tuple=\(categoryString)/\(garment)/\(sleeveString)/\(lowerString)/\(bodyString)"
            ].joined(separator: ";")

            localProductID = VNextHistoryProjectionIdentity.productID(
                comparisonID: row.clientComparisonID
            )
            usesImmutableProjection = true
            authority = provenance
            sourceIdentity = identity
            categoryCode = category
            garmentTypeCode = garment
            audienceCode = audience
            sleeveLengthCode = sleeve
            lowerLengthCode = lower
            bodyLengthCode = body
            self.policyCode = policyCode
            self.policyVersion = policyVersion
            personalRevision = revision
            self.candidateFingerprint = candidateFingerprint
        }

        private static func legacy(row: VNextComparisonHistoryDTO) -> Self {
            Self(
                localProductID: row.targetProductID,
                usesImmutableProjection: false,
                authority: .serverConfirmed,
                sourceIdentity: "fitmatch_vnext_history",
                categoryCode: row.targetCategoryCode,
                garmentTypeCode: row.targetSnapshot?.garmentTypeCode,
                audienceCode: nil,
                sleeveLengthCode: row.targetSnapshot?.sleeveLengthCode,
                lowerLengthCode: row.targetSnapshot?.lowerLengthCode,
                bodyLengthCode: row.targetSnapshot?.bodyLengthCode,
                policyCode: row.policySnapshot?.policyCode,
                policyVersion: row.policySnapshot?.policyVersion,
                personalRevision: nil,
                candidateFingerprint: nil
            )
        }

        private static func axis(_ value: FitMatchJSONValue?) -> String? {
            guard case .string(let raw)? = value else { return nil }
            return raw
        }
    }

    func hydrateCompleted(
        _ rows: [VNextComparisonHistoryDTO],
        existingHistories: [RecommendationHistory],
        existingProducts: [Product],
        existingClosetItems: [UserFit],
        modelContext: ModelContext
    ) throws -> Set<UUID> {
        // Callers can legitimately hold stale @Query snapshots while SwiftData
        // has already inserted or deleted related rows.  Always rebuild the
        // hydration identity maps from this context instead of retaining an
        // invalidated model instance supplied by a previous render pass.
        _ = existingHistories
        _ = existingProducts
        _ = existingClosetItems
        let persistedHistories = try modelContext.fetch(
            FetchDescriptor<RecommendationHistory>()
        )
        let persistedProducts = try modelContext.fetch(FetchDescriptor<Product>())
        let persistedClosetItems = try modelContext.fetch(FetchDescriptor<UserFit>())
        let existingHistoryIDs = Set(persistedHistories.map(\.id))
        var productByID = Dictionary(uniqueKeysWithValues: persistedProducts.map { ($0.id, $0) })
        var closetByClientID = Dictionary(
            uniqueKeysWithValues: persistedClosetItems.map { ($0.id, $0) }
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

            let projection = try HistoricalTargetProjection(row: row)
            let product = productByID[projection.localProductID]
                ?? makeProduct(
                    from: row,
                    projection: projection,
                    modelContext: modelContext
                )
            productByID[projection.localProductID] = product
            let recommendedSize = try ensureRecommendedSize(
                id: recommendedID,
                row: row,
                projection: projection,
                product: product,
                modelContext: modelContext
            )

            guard let referenceClientID = row.referenceClientItemID else {
                throw VNextHistoryCacheHydrationError.missingReferenceIdentity(row.id)
            }
            let referenceProjectionID = projection.usesImmutableProjection
                ? VNextHistoryProjectionIdentity.referenceID(
                    comparisonID: row.clientComparisonID,
                    clientItemID: referenceClientID
                )
                : referenceClientID
            let reference = closetByClientID[referenceProjectionID]
                ?? makeReference(
                    id: referenceProjectionID,
                    snapshot: row.referenceSnapshot,
                    modelContext: modelContext
                )
            closetByClientID[referenceProjectionID] = reference

            let detail = detailCategory(
                garmentType: projection.garmentTypeCode,
                sleeve: projection.sleeveLengthCode,
                lower: projection.lowerLengthCode,
                body: projection.bodyLengthCode
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
                serverApprovedReliability: row.resultEvidence?.reliability
                    ?? row.reliabilityLevel,
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
            && evidence.reliability == analysis.completionPayload.reliability
            && abs(evidence.coverage - analysis.completionPayload.coverage) < tolerance
            && evidence.candidateSizeRanking == analysis.completionPayload.candidateSizeRanking
            && evidence.metricEvidence == analysis.completionPayload.metricEvidence
    }

    private func makeProduct(
        from row: VNextComparisonHistoryDTO,
        projection: HistoricalTargetProjection,
        modelContext: ModelContext
    ) -> Product {
        let category = ClothingCategory.fromTaxonomyCode(projection.categoryCode ?? "other")
        let source = sourcePresentation(row.targetSourceCode)
        let sizes = (row.targetSnapshot?.candidates ?? []).enumerated().map { index, candidate in
            makeProductSize(
                candidate: candidate,
                displayOrder: index,
                localID: projection.usesImmutableProjection
                    ? VNextHistoryProjectionIdentity.productSizeID(
                        comparisonID: row.clientComparisonID,
                        productSizeID: candidate.productSizeID
                    )
                    : candidate.productSizeID
            )
        }
        let product = Product(
            id: projection.localProductID,
            name: row.targetProductName,
            category: category,
            productCode: row.targetSourceProductKey,
            sourceURLString: supportedCanonicalURL(from: row),
            imageURLString: row.targetImageURL,
            metadata: ProductMetadata(
                genderCodes: [projection.audienceCode ?? "UNKNOWN"]
            ),
            sourceType: source.type,
            sourceName: source.name,
            source: .catalog,
            sizes: sizes,
            createdAt: decodeDate(row.createdAt) ?? Date(),
            updatedAt: decodeDate(row.createdAt) ?? Date()
        )
        product.sourcePlatformCode = row.targetSourceCode
        product.categoryCode = projection.categoryCode
        product.garmentTypeRawValue = projection.garmentTypeCode
        product.sleeveTypeRawValue = projection.sleeveLengthCode
        product.checkedSizeName = row.recommendedSizeLabel
        product.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(
            historicalCanonicalProfile(for: projection, row: row)
        )
        product.canonicalPolicyVersion = projection.policyVersion
        product.markClassificationAuthority(
            projection.authority,
            sourceIdentity: projection.sourceIdentity
        )
        modelContext.insert(product)
        return product
    }

    private func supportedCanonicalURL(from row: VNextComparisonHistoryDTO) -> String? {
        guard let raw = row.targetCanonicalURL?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        let url = URL(string: raw),
        FitMatchProductURLRouting.provider(for: url) != nil else {
            return nil
        }
        return url.absoluteString
    }

    private func ensureRecommendedSize(
        id: UUID,
        row: VNextComparisonHistoryDTO,
        projection: HistoricalTargetProjection,
        product: Product,
        modelContext: ModelContext
    ) throws -> ProductSize {
        let localID = projection.usesImmutableProjection
            ? VNextHistoryProjectionIdentity.productSizeID(
                comparisonID: row.clientComparisonID,
                productSizeID: id
            )
            : id
        if let existing = product.sizes.first(where: { $0.id == localID }) {
            return existing
        }
        guard let candidate = row.targetSnapshot?.candidates.first(where: {
            $0.productSizeID == id
        }) else {
            throw VNextHistoryCacheHydrationError.incompleteSnapshot(row.id)
        }
        let size = makeProductSize(
            candidate: candidate,
            displayOrder: product.sizes.count,
            localID: localID
        )
        size.product = product
        product.sizes.append(size)
        modelContext.insert(size)
        return size
    }

    private func makeProductSize(
        candidate: VNextAuthorizedCandidateDTO,
        displayOrder: Int,
        localID: UUID
    ) -> ProductSize {
        let values = candidate.comparisonMeasurements.reduce(into: [String: Double]()) {
            $0[$1.measurementCode] = $1.targetValue
        }
        let size = ProductSize(
            id: localID,
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
            isUserExplicitReference(classificationSource)
                ? .userExplicit
                : .serverConfirmed,
            sourceIdentity: classificationSource ?? "fitmatch_vnext_history"
        )
        item.markAsHistoryOnlyReferenceSnapshot(
            sourceIdentity: object["closet_item_id"]?.stringValue
        )
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

    /// The history cache may decorate a frozen server tuple for local display,
    /// but it never derives a replacement classification from the current
    /// Product.  Every meaningful axis below came from the begin snapshot.
    private func historicalCanonicalProfile(
        for projection: HistoricalTargetProjection,
        row: VNextComparisonHistoryDTO
    ) -> CanonicalComparisonProfile {
        let policyCode = projection.policyCode ?? "history_snapshot"
        let policyVersion = projection.policyVersion ?? "history_snapshot"
        return CanonicalComparisonProfile(
            decision: .confirmed,
            semanticCategoryCode: projection.categoryCode,
            semanticGarmentType: projection.garmentTypeCode,
            comparisonFamily: policyCode,
            appComparisonFamily: policyCode,
            lengthAxes: CanonicalLengthAxes(
                sleeve: projection.sleeveLengthCode ?? "not_applicable",
                pants: projection.lowerLengthCode ?? "not_applicable",
                leggings: "not_applicable",
                skirt: "not_applicable",
                body: projection.bodyLengthCode ?? "not_applicable"
            ),
            constructionType: "single",
            eligibility: true,
            requiredMeasurements: row.authorizationSnapshot?.requiredMeasurementCodes ?? [],
            optionalMeasurements: [],
            excludedMeasurements: row.excludedMeasurementCodes,
            policyVersion: policyVersion,
            resolutionMethod: projection.authority.rawValue,
            sourceIdentity: projection.sourceIdentity
        )
    }

    private func isUserExplicitReference(_ source: String?) -> Bool {
        switch source?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "USER_EXPLICIT", "MANUAL_OVERRIDE", "USER_EDITED":
            return true
        default:
            return false
        }
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
