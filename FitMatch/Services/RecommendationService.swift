import Foundation

struct FitMatchCandidate: Identifiable {
    var id: UUID { userFit.id }
    let userFit: UserFit
    let matchRate: Int
    let compatibleMeasurementCount: Int
    let selectionReason: String
}

struct ReferenceSelectionPlan {
    let recommendedCandidates: [FitMatchCandidate]
    let automaticallySelectedCandidate: FitMatchCandidate?

    var requiresUserSelection: Bool {
        !recommendedCandidates.isEmpty && automaticallySelectedCandidate == nil
    }
}

struct InsufficientComparisonEvidence {
    let productSize: ProductSize
    let referenceItem: UserFit
    let comparisonResult: MeasurementComparisonResult

    var comparedKinds: [MeasurementKind] {
        comparisonResult.comparedKinds
    }

    var missingKinds: [MeasurementKind] {
        comparisonResult.exclusions.map(\.kind)
    }
}

struct TemporarySizeAnalysis {
    let productSize: ProductSize
    let comparisonResult: MeasurementComparisonResult
    let recommendationScore: Int
    let comparisonSummary: String?

    var calculationSnapshot: RecommendationCalculationSnapshot {
        RecommendationCalculationSnapshot.make(comparison: comparisonResult)
    }
}

struct RecommendationService {
    private let comparisonMatcher = ComparisonProfileMatcher()
    private let measurementComparisonEngine = MeasurementComparisonEngine()
    private let vnextComparisonAdapter = VNextComparisonEngineAdapter()

    func analyzeVNextComparison(
        permit: FitMatchServerComparisonPermit
    ) throws -> VNextComparisonBatchAnalysis {
        guard permit.isAllowed, let begin = permit.vnextBegin else {
            throw VNextComparisonEngineAdapterError.authorizationDenied(
                "begin_snapshot_missing"
            )
        }
        return try vnextComparisonAdapter.analyze(begin)
    }

    /// Builds a detached, current server-authorized target presentation for a
    /// replacement comparison. A completed Result may itself be a historical
    /// projection, so mutating it would rewrite old Result/History meaning.
    /// This maps the server-issued effective tuple as a whole; it never fills
    /// an absent effective axis from the older displayed Product.
    func makeServerAuthorizedComparisonTarget(
        from displayedProduct: Product,
        permit: FitMatchServerComparisonPermit
    ) -> Product? {
        guard permit.isAllowed,
              let begin = permit.vnextBegin,
              begin.comparisonID == permit.runID,
              begin.snapshot.target.productID == permit.referenceAuthorization.target.productID,
              let runtime = permit.referenceAuthorization.target.runtime.vnext,
              let runtimeProduct = runtime.product else {
            return nil
        }

        let tuple = VNextRuntimeClassificationTuple(
            product: runtimeProduct,
            effective: runtime.effectiveClassification
        )
        guard tuple.usesEffectiveClassification,
              tuple.classificationStatus == "CONFIRMED",
              let categoryCode = tuple.categoryCode,
              let garmentCode = tuple.garmentTypeCode,
              !categoryCode.isEmpty,
              !garmentCode.isEmpty,
              begin.snapshot.target.classificationStatus == "CONFIRMED",
              Set(begin.snapshot.target.authorizedCandidateProductSizeIDs)
                == Set(begin.authorizedCandidateProductSizeIDs),
              !begin.snapshot.target.candidates.isEmpty else {
            return nil
        }

        let authority: FitMatchClassificationAuthorityProvenance
        switch tuple.effectiveSource {
        case "GLOBAL_CONFIRMED":
            authority = .serverConfirmed
        case "USER_EXPLICIT":
            guard tuple.overrideRevision != nil,
                  tuple.authorityFingerprint?.isEmpty == false else {
                return nil
            }
            authority = .userExplicit
        default:
            return nil
        }

        let product = Product(
            id: permit.referenceAuthorization.target.productID,
            name: displayedProduct.name,
            brand: displayedProduct.brand,
            category: ClothingCategory.fromTaxonomyCode(categoryCode),
            productCode: displayedProduct.productCode,
            sourceURLString: displayedProduct.sourceURLString,
            imageURLString: displayedProduct.imageURLString,
            sourceType: displayedProduct.sourceType,
            sourceName: displayedProduct.sourceName,
            source: displayedProduct.source,
            notes: displayedProduct.notes,
            createdAt: displayedProduct.createdAt,
            updatedAt: Date()
        )
        copyRetailerPresentation(from: displayedProduct, to: product)
        product.categoryRawValue = ClothingCategory.fromTaxonomyCode(categoryCode).rawValue
        product.categoryCode = categoryCode
        product.normalizedProductTypeCode = garmentCode
        product.garmentTypeRawValue = garmentCode
        product.genderCodes = tuple.audienceCode
        // These nil values are intentional server tuple values. Do not
        // coalesce them with axes from the completed historical product.
        product.sleeveTypeRawValue = tuple.sleeveLengthCode
        product.constructionTypeRawValue = tuple.productStructureCode
        product.canonicalPolicyVersion = tuple.contractVersion
            ?? begin.snapshot.policy.policyVersion
        product.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(
            CanonicalComparisonProfile(
                decision: .confirmed,
                semanticCategoryCode: categoryCode,
                semanticGarmentType: garmentCode,
                comparisonFamily: tuple.comparisonPolicyCode,
                appComparisonFamily: tuple.comparisonPolicyCode,
                lengthAxes: CanonicalLengthAxes(
                    sleeve: tuple.sleeveLengthCode ?? "not_applicable",
                    pants: tuple.lowerLengthCode ?? "not_applicable",
                    leggings: "not_applicable",
                    skirt: "not_applicable",
                    body: tuple.bodyLengthCode ?? "not_applicable"
                ),
                constructionType: tuple.productStructureCode,
                eligibility: true,
                requiredMeasurements: begin.snapshot.policy.metrics.compactMap(
                    \.measurementCode
                ),
                optionalMeasurements: [],
                excludedMeasurements: begin.snapshot.excludedMeasurementCodes,
                policyVersion: tuple.contractVersion
                    ?? begin.snapshot.policy.policyVersion
                    ?? "fitmatch_vnext",
                resolutionMethod: authority.rawValue,
                sourceIdentity: tuple.authorityFingerprint
            )
        )
        product.markClassificationAuthority(
            authority,
            sourceIdentity: tuple.authorityFingerprint
        )

        product.sizes = begin.snapshot.target.candidates.enumerated().map {
            index,
            candidate in
            makeServerAuthorizedPresentationSize(
                candidate,
                displayOrder: index,
                product: product
            )
        }
        return product
    }

    /// Builds the local/offline cache only after the caller has received a
    /// successful `complete_comparison` response for this exact batch.
    func makeCompletedVNextHistory(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory,
        permit: FitMatchServerComparisonPermit,
        analysis: VNextComparisonBatchAnalysis,
        completion: VNextCompleteComparisonDTO
    ) -> RecommendationHistory? {
        guard completedVNextHistoryIsServerBacked(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            permit: permit,
            analysis: analysis,
            completion: completion
        ), let size = product.sizes.first(where: {
            $0.id == analysis.recommended.productSizeID
        }) else {
            return nil
        }
        let comparison = analysis.recommended.result
        let history = RecommendationHistory(
            id: permit.clientHistoryID,
            product: product,
            recommendedSize: size,
            userFit: selectedReferenceItem,
            totalDifference: comparison.averageDifference,
            measurementDifferences: comparison.signedDifferences,
            recommendationScore: comparison.score,
            trueToSizeRecommendation: "기준 옷과 서버 승인 실측이 가장 비슷한 \(size.name) 사이즈입니다.",
            oversizedRecommendation: "",
            comparisonMethod: permit.referenceAuthorization.decision == .manualSelection
                ? "서버 승인 확장 비교" : "서버 승인 직접 비교",
            fallbackReason: permit.referenceAuthorization.decision == .manualSelection
                ? "서버 정책이 승인한 공통 실측만 사용했습니다." : "",
            productDetailCategory: productDetailCategory,
            comparisonResult: comparison
        )
        return history
    }

    /// Alternative-size presentation is read-only. It can reuse only the
    /// exact batch already produced by a completed server-backed run; it never
    /// authorizes or invokes a fresh measurement comparison.
    func canPresentCurrentVNextAlternativeSizes(
        for history: RecommendationHistory,
        batch: VNextComparisonBatchAnalysis?
    ) -> Bool {
        let expectedRecommendedSizeIDs = batch.map {
            [
                $0.recommended.productSizeID,
                VNextHistoryProjectionIdentity.productSizeID(
                    comparisonID: history.id,
                    productSizeID: $0.recommended.productSizeID
                )
            ]
        } ?? []
        guard history.product.classificationAuthorityProvenance?
                .isComparisonAuthority == true,
              history.userFit.classificationAuthorityProvenance?
                .isComparisonAuthority == true,
              history.comparisonMethod.hasPrefix("서버 승인"),
              let batch,
              expectedRecommendedSizeIDs.contains(history.recommendedSize.id),
              batch.completionPayload.recommendedProductSizeID
                == batch.recommended.productSizeID,
              batch.authorizedCandidateProductSizeIDs.contains(
                batch.recommended.productSizeID
              ) else {
            return false
        }
        let authorized = batch.authorizedCandidateProductSizeIDs
        let analysisIDs = batch.analyses.map(\.productSizeID)
        return !authorized.isEmpty
            && Set(authorized).count == authorized.count
            && Set(analysisIDs) == Set(authorized)
            && analysisIDs.count == authorized.count
    }

    /// A local completed-history cache is allowed only for the exact server
    /// comparison that completed. In particular, `.userExplicit` alone is not
    /// authority: it must be the current effective authority proven by the
    /// server-created V4 begin snapshot.
    private func completedVNextHistoryIsServerBacked(
        product: Product,
        selectedReferenceItem: UserFit,
        permit: FitMatchServerComparisonPermit,
        analysis: VNextComparisonBatchAnalysis,
        completion: VNextCompleteComparisonDTO
    ) -> Bool {
        guard permit.isAllowed,
              permit.runID == analysis.comparisonID,
              completion.completed,
              completion.comparisonID == permit.runID,
              completion.recommendedProductSizeID == analysis.recommended.productSizeID,
              analysis.completionPayload.recommendedProductSizeID
                == analysis.recommended.productSizeID,
              let begin = permit.vnextBegin,
              begin.comparisonID == permit.runID,
              begin.resultStatus == "PENDING",
              begin.snapshot.authorization.allowed,
              begin.snapshot.target.classificationStatus == "CONFIRMED",
              permit.referenceAuthorization.target.status == .confirmed,
              permit.referenceAuthorization.target.productID == product.id,
              begin.snapshot.target.productID == product.id,
              let targetVariantID = permit.referenceAuthorization.targetVariantID,
              begin.snapshot.target.variantID == targetVariantID,
              let reference = permit.referenceAuthorization.reference,
              reference.clientItemID == selectedReferenceItem.id,
              permit.referenceAuthorization.referenceAuthority != nil,
              snapshotUUID(
                begin.snapshot.referenceSnapshot,
                key: "closet_item_id"
              ) == reference.closetItemID,
              product.sizes.contains(where: {
                $0.id == analysis.recommended.productSizeID
              }) else {
            return false
        }

        let authorizedIDs = begin.authorizedCandidateProductSizeIDs
        let authorizedSet = Set(authorizedIDs)
        let snapshotIDs = begin.snapshot.target.authorizedCandidateProductSizeIDs
        let snapshotCandidateIDs = begin.snapshot.target.candidates.map(\.productSizeID)
        let analysisIDs = analysis.authorizedCandidateProductSizeIDs
        guard !authorizedIDs.isEmpty,
              authorizedSet.count == authorizedIDs.count,
              Set(snapshotIDs) == authorizedSet,
              snapshotIDs.count == authorizedIDs.count,
              Set(snapshotCandidateIDs) == authorizedSet,
              snapshotCandidateIDs.count == authorizedIDs.count,
              Set(analysisIDs) == authorizedSet,
              analysisIDs.count == authorizedIDs.count,
              authorizedSet.contains(analysis.recommended.productSizeID),
              begin.snapshot.target.candidateAuthorityFingerprint
                == begin.candidateAuthorityFingerprint,
              let effectiveAuthorityFingerprint = begin.effectiveAuthorityFingerprint,
              !effectiveAuthorityFingerprint.isEmpty,
              snapshotString(
                begin.snapshot.inputSnapshot,
                key: "effective_authority_fingerprint"
              ) == effectiveAuthorityFingerprint else {
            return false
        }

        return currentServerAuthorityMatches(
            product: product,
            permit: permit,
            begin: begin,
            effectiveAuthorityFingerprint: effectiveAuthorityFingerprint
        )
    }

    private func currentServerAuthorityMatches(
        product: Product,
        permit: FitMatchServerComparisonPermit,
        begin: VNextBeginComparisonDTO,
        effectiveAuthorityFingerprint: String
    ) -> Bool {
        guard let effective = permit.referenceAuthorization.target.runtime.vnext?
            .effectiveClassification,
              effective.productID == product.id,
              effective.classificationStatus == "CONFIRMED",
              effective.effectiveAuthorityFingerprint == effectiveAuthorityFingerprint,
              effectiveClassificationSnapshotMatches(
                effective,
                begin: begin
              ) else {
            return false
        }
        let runtimeAuthorityStatus = permit.referenceAuthorization.target
            .classification.authorityStatus?.lowercased()

        switch product.classificationAuthorityProvenance {
        case .serverConfirmed:
            return effective.effectiveSource == "GLOBAL_CONFIRMED"
                && runtimeAuthorityStatus != "user_explicit"

        case .userExplicit:
            guard begin.snapshot.snapshotSchemaVersion >= 4,
                  effective.isPersonalComparisonAuthority,
                  runtimeAuthorityStatus == "user_explicit",
                  let revision = effective.overrideRevision,
                  snapshotNumber(
                    begin.snapshot.inputSnapshot,
                    key: "personal_override_revision"
                  ) == Double(revision),
                  let authority = begin.snapshot.authoritySnapshot.objectValue,
                  let effectiveAtBegin = authority[
                    "effective_classification_at_begin"
                  ]?.objectValue,
                  effectiveAtBegin["source"]?.stringValue == "USER_EXPLICIT",
                  effectiveAtBegin["effective_authority_fingerprint"]?.stringValue
                    == effectiveAuthorityFingerprint,
                  let beginProjection = authority[
                    "personal_projection_at_begin"
                  ]?.objectValue,
                  let runtimeProjection = effective.personalProjection?.objectValue,
                  personalProjectionIsActive(beginProjection),
                  beginProjection["revision"]?.numberValue == Double(revision),
                  runtimeProjection["revision"]?.numberValue == Double(revision),
                  personalProjectionMatches(
                    beginProjection,
                    runtimeProjection
                  ) else {
                return false
            }
            return true

        default:
            return false
        }
    }

    private func copyRetailerPresentation(from source: Product, to destination: Product) {
        destination.brand = source.brand
        destination.productCode = source.productCode
        destination.sourceURLString = source.sourceURLString
        destination.imageURLString = source.imageURLString
        destination.styleNo = source.styleNo
        destination.englishName = source.englishName
        destination.brandCode = source.brandCode
        destination.brandEnglishName = source.brandEnglishName
        destination.brandLogoImageURLString = source.brandLogoImageURLString
        destination.brandNationName = source.brandNationName
        destination.sourceCategoryPath = source.sourceCategoryPath
        destination.sourceCategoryDepth1 = source.sourceCategoryDepth1
        destination.sourceCategoryDepth2 = source.sourceCategoryDepth2
        destination.sourceCategoryDepth3 = source.sourceCategoryDepth3
        destination.sourceCategoryDepth4 = source.sourceCategoryDepth4
        destination.baseCategoryFullPath = source.baseCategoryFullPath
        destination.categoryDepth1Code = source.categoryDepth1Code
        destination.categoryDepth1Name = source.categoryDepth1Name
        destination.categoryDepth2Code = source.categoryDepth2Code
        destination.categoryDepth2Name = source.categoryDepth2Name
        destination.categoryDepth3Code = source.categoryDepth3Code
        destination.categoryDepth3Name = source.categoryDepth3Name
        destination.categoryDepth4Code = source.categoryDepth4Code
        destination.categoryDepth4Name = source.categoryDepth4Name
        destination.sizeType = source.sizeType
        destination.genderCodes = source.genderCodes
        destination.labelNames = source.labelNames
        destination.imageURLStrings = source.imageURLStrings
        destination.normalPrice = source.normalPrice
        destination.salePrice = source.salePrice
        destination.finalPrice = source.finalPrice
        destination.currencyCode = source.currencyCode
        destination.discountRate = source.discountRate
        destination.isSale = source.isSale
        destination.isOutOfStock = source.isOutOfStock
        destination.stockStatusRawValue = source.stockStatusRawValue
        destination.isRestock = source.isRestock
        destination.isSoonOutOfStock = source.isSoonOutOfStock
        destination.isLimitedQuantity = source.isLimitedQuantity
        destination.reviewCount = source.reviewCount
        destination.reviewSatisfactionScore = source.reviewSatisfactionScore
        destination.seasonYear = source.seasonYear
        destination.season = source.season
        destination.checkedColorName = source.checkedColorName
        destination.checkedSizeName = source.checkedSizeName
        destination.sourceTypeRawValue = source.sourceTypeRawValue
        destination.sourceName = source.sourceName
        destination.sourcePlatformCode = source.sourcePlatformCode
        destination.sourceRawValue = source.sourceRawValue
        destination.notes = source.notes
    }

    private func makeServerAuthorizedPresentationSize(
        _ candidate: VNextAuthorizedCandidateDTO,
        displayOrder: Int,
        product: Product
    ) -> ProductSize {
        var measurements = GarmentMeasurements(
            shoulder: 0,
            chest: 0,
            totalLength: 0,
            sleeveLength: 0
        )
        for measurement in candidate.comparisonMeasurements {
            guard let code = MeasurementCode(rawValue: measurement.measurementCode),
                  let kind = MeasurementComparisonEngine.measurementKind(for: code) else {
                continue
            }
            switch kind {
            case .shoulder: measurements.shoulder = measurement.targetValue
            case .chest: measurements.chest = measurement.targetValue
            case .totalLength: measurements.totalLength = measurement.targetValue
            case .sleeveLength: measurements.sleeveLength = measurement.targetValue
            case .upperAbdomen: measurements.upperAbdomen = measurement.targetValue
            case .upperWaist: measurements.upperWaist = measurement.targetValue
            case .waist: measurements.waist = measurement.targetValue
            case .hip: measurements.hip = measurement.targetValue
            case .thigh: measurements.thigh = measurement.targetValue
            case .rise: measurements.rise = measurement.targetValue
            case .hem: measurements.hem = measurement.targetValue
            case .footLength: measurements.footLength = measurement.targetValue
            case .underBust: measurements.underBust = measurement.targetValue
            }
        }
        return ProductSize(
            id: candidate.productSizeID,
            name: candidate.sizeLabel,
            measurements: measurements,
            displayOrder: displayOrder,
            product: product
        )
    }

    private func personalProjectionMatches(
        _ beginProjection: [String: FitMatchJSONValue],
        _ runtimeProjection: [String: FitMatchJSONValue]
    ) -> Bool {
        let requiredKeys = [
            "classification_source",
            "selected_candidate_fingerprint",
            "candidate_contract_version",
            "candidate_set_hash",
            "base_product_input_fingerprint",
            "base_product_evidence_fingerprint",
            "base_resolver_version"
        ]
        return requiredKeys.allSatisfy { key in
            guard let beginValue = beginProjection[key],
                  let runtimeValue = runtimeProjection[key] else {
                return false
            }
            return beginValue == runtimeValue
        }
    }

    private func personalProjectionIsActive(
        _ projection: [String: FitMatchJSONValue]
    ) -> Bool {
        guard let clearedAt = projection["cleared_at"] else { return true }
        return clearedAt == .null
    }

    /// The target tuple rendered locally must be the exact effective tuple that
    /// the server snapshotted at begin. This keeps a current server-backed
    /// personal projection distinct from a local `.userExplicit` label.
    private func effectiveClassificationSnapshotMatches(
        _ effective: VNextEffectiveTargetClassificationDTO,
        begin: VNextBeginComparisonDTO
    ) -> Bool {
        guard let authority = begin.snapshot.authoritySnapshot.objectValue,
              let snapshot = authority[
                "effective_classification_at_begin"
              ]?.objectValue else {
            return false
        }

        return snapshot["source"]?.stringValue == effective.effectiveSource
            && snapshot["state"]?.stringValue == effective.state
            && snapshot["category_code"]?.stringValue == effective.categoryCode
            && snapshot["garment_type_code"]?.stringValue
                == effective.garmentTypeCode
            && snapshot["audience_code"]?.stringValue == effective.audienceCode
            && snapshot["sleeve_length_code"]?.stringValue
                == effective.sleeveLengthCode
            && snapshot["lower_length_code"]?.stringValue
                == effective.lowerLengthCode
            && snapshot["body_length_code"]?.stringValue
                == effective.bodyLengthCode
            && snapshot["comparison_policy_code"]?.stringValue
                == effective.comparisonPolicyCode
            && begin.snapshot.target.classificationStatus
                == effective.classificationStatus
            && begin.snapshot.target.garmentTypeCode == effective.garmentTypeCode
            && begin.snapshot.target.sleeveLengthCode == effective.sleeveLengthCode
            && begin.snapshot.target.lowerLengthCode == effective.lowerLengthCode
            && begin.snapshot.target.bodyLengthCode == effective.bodyLengthCode
    }

    private func snapshotString(
        _ snapshot: FitMatchJSONValue,
        key: String
    ) -> String? {
        snapshot.objectValue?[key]?.stringValue
    }

    private func snapshotUUID(
        _ snapshot: FitMatchJSONValue,
        key: String
    ) -> UUID? {
        snapshotString(snapshot, key: key).flatMap(UUID.init(uuidString:))
    }

    private func snapshotNumber(
        _ snapshot: FitMatchJSONValue,
        key: String
    ) -> Double? {
        snapshot.objectValue?[key]?.numberValue
    }

    func recommend(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory = .other,
        allowsGlobalFallback: Bool = true
    ) -> RecommendationHistory? {
        guard product.canonicalEligibility != false else { return nil }
        let basis = selectBasis(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits,
            allowsGlobalFallback: allowsGlobalFallback
        )
        guard !basis.userFits.isEmpty else {
            return nil
        }

        let sortedFits = sortCandidates(basis.userFits)
        return bestRecommendation(
            product: product,
            userFits: sortedFits,
            productDetailCategory: productDetailCategory,
            basis: basis
        )
    }

    func analyzeSizeWithoutSaving(
        _ size: ProductSize,
        product: Product,
        referenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory,
        comparisonMethod: String,
        excludedKinds: [MeasurementKind],
        excludedKindReasons: [MeasurementKind: MeasurementExclusionReason] = [:],
        scorePenalty: Int
    ) -> TemporarySizeAnalysis? {
        guard product.canonicalEligibility != false,
              referenceItem.canonicalEligibility != false else {
            return nil
        }
        if comparisonMethod == "기준표 가슴둘레 비교" {
            guard let productChest = StandardBodySizeChart.chestCircumferenceCm(for: size.name),
                  let referenceChest = StandardBodySizeChart.chestCircumferenceCm(for: referenceItem.sizeName) else {
                return nil
            }
            let signedDifference = productChest - referenceChest
            let absoluteDifference = abs(signedDifference)
            let rawScore = max(0, min(100, Int((100 - absoluteDifference * 5).rounded())))
            let item = MeasurementComparisonItem(
                kind: .chest,
                measurementCode: .standardBodyChestCircumference,
                productValue: productChest,
                referenceValue: referenceChest,
                signedDifference: signedDifference,
                absoluteDifference: absoluteDifference,
                score: rawScore,
                weight: 1
            )
            let comparison = MeasurementComparisonResult(
                status: .confirmed,
                score: rawScore,
                comparedItems: [item],
                exclusions: standardSizeExclusions,
                averageDifference: absoluteDifference,
                minimumComparableCount: 1,
                requiredKinds: [.chest],
                minimumRequiredKindCount: 1,
                requiredAllKinds: [],
                expectedWeightSum: 1,
                usedWeightSum: 1
            )
            return TemporarySizeAnalysis(
                productSize: size,
                comparisonResult: comparison,
                recommendationScore: max(0, rawScore - scorePenalty),
                comparisonSummary: standardSizeReason(
                    productSize: size.name,
                    referenceSize: referenceItem.sizeName,
                    difference: signedDifference
                )
            )
        }

        let comparison = measurementComparisonEngine.compare(
            productSize: size,
            referenceItem: referenceItem,
            productCategory: product.category,
            productDetailCategory: productDetailCategory,
            excludedKinds: excludedKinds,
            excludedKindReasons: excludedKindReasons
        )
        guard comparison.status == .confirmed else { return nil }
        return TemporarySizeAnalysis(
            productSize: size,
            comparisonResult: comparison,
            recommendationScore: max(0, comparison.score - scorePenalty),
            comparisonSummary: nil
        )
    }

    func insufficientEvidence(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory = .other,
        allowsGlobalFallback: Bool = true
    ) -> InsufficientComparisonEvidence? {
        guard product.canonicalEligibility != false else { return nil }
        let profileResult = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        let candidates = profileResult.compatibleCandidates.isEmpty && allowsGlobalFallback
            ? comparisonMatcher.manualCandidates(
                product: product,
                productDetailCategory: productDetailCategory,
                userFits: userFits
            )
            : profileResult.compatibleCandidates
        return bestInsufficientEvidence(
            product: product,
            userFits: candidates,
            productDetailCategory: productDetailCategory,
            excludedKinds: []
        )
    }

    func insufficientEvidence(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> InsufficientComparisonEvidence? {
        let compatibility = comparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: selectedReferenceItem
        )
        guard compatibility.level.isAllowed else { return nil }
        let mismatch = comparisonMatcher.manualMismatch(
            product: product,
            productDetailCategory: productDetailCategory,
            selectedItem: selectedReferenceItem
        )
        return bestInsufficientEvidence(
            product: product,
            userFits: [selectedReferenceItem],
            productDetailCategory: productDetailCategory,
            excludedKinds: mismatch.excludedKinds,
            excludedKindReasons: exclusionReasons(for: mismatch.excludedKinds)
        )
    }

    func recommend(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> RecommendationHistory? {
        guard product.canonicalEligibility != false,
              selectedReferenceItem.canonicalEligibility != false else {
            return nil
        }
        let compatibility = comparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: selectedReferenceItem
        )
        guard compatibility.level.isAllowed else { return nil }
        let mismatch = comparisonMatcher.manualMismatch(
            product: product,
            productDetailCategory: productDetailCategory,
            selectedItem: selectedReferenceItem
        )
        let fallbackReason = mismatch.note
            ?? "\(productDetailCategory.rawValue) 기준 옷이 없어 선택한 옷으로 임시 비교했습니다."
        return bestRecommendation(
            product: product,
            userFits: [selectedReferenceItem],
            productDetailCategory: productDetailCategory,
            basis: RecommendationBasis(
                userFits: [selectedReferenceItem],
                methodText: compatibility.level == .extended
                    ? "사용자 선택 확장 비교"
                    : "사용자 선택 직접 비교",
                scorePenalty: manualComparisonScorePenalty(
                    product: product,
                    selectedReferenceItem: selectedReferenceItem
                ) + (compatibility.level == .extended ? 10 : 0),
                fallbackReason: fallbackReason,
                excludedMeasurementKinds: mismatch.excludedKinds,
                excludedMeasurementReasons: exclusionReasons(for: mismatch.excludedKinds)
            )
        )
    }

    #if DEBUG
    /// Debug-only compatibility seam for isolated scorer regressions. Runtime
    /// call sites must first create a server comparison run and pass a permit.
    func recommendAfterServerAuthorization(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory,
        authorization: FitMatchServerReferenceAuthorization
    ) -> RecommendationHistory? {
        let compatibility = authorization.decision == .automatic
            ? authorization.candidate?.automaticCompatibility
            : authorization.candidate?.manualCompatibility
        guard let compatibility else { return nil }
        return authorizedRecommendation(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            productDetailCategory: productDetailCategory,
            authorization: authorization,
            compatibility: compatibility,
            clientHistoryID: nil
        )
    }
    #endif

    private func authorizedRecommendation(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory,
        authorization: FitMatchServerReferenceAuthorization,
        compatibility: FitMatchDatabaseCompatibility,
        clientHistoryID: UUID?
    ) -> RecommendationHistory? {
        guard authorization.isAllowed,
              product.classificationAuthorityProvenance == .serverConfirmed,
              selectedReferenceItem.classificationAuthorityProvenance?
                .isComparisonAuthority == true else {
            return nil
        }

        guard compatibility.allowed else { return nil }

        let excludedKinds = serverExcludedMeasurementKinds(
            compatibility.excludedMeasurements
        )
        let isExtended = compatibility.level == "extended"
        let scorePenalty: Int
        if authorization.decision == .manualSelection {
            scorePenalty = manualComparisonScorePenalty(
                product: product,
                selectedReferenceItem: selectedReferenceItem
            ) + (isExtended ? 10 : 0)
        } else {
            scorePenalty = 0
        }

        guard let history = bestRecommendation(
            product: product,
            userFits: [selectedReferenceItem],
            productDetailCategory: productDetailCategory,
            basis: RecommendationBasis(
                userFits: [selectedReferenceItem],
                methodText: isExtended
                    ? "서버 승인 확장 비교"
                    : "서버 승인 직접 비교",
                scorePenalty: scorePenalty,
                fallbackReason: isExtended
                    ? "서버 비교 정책에서 허용한 공통 실측만 사용했습니다."
                    : "",
                excludedMeasurementKinds: excludedKinds,
                excludedMeasurementReasons: exclusionReasons(for: excludedKinds)
            )
        ) else { return nil }
        if let clientHistoryID {
            history.id = clientHistoryID
        }
        return history
    }

    private func serverExcludedMeasurementKinds(
        _ values: [String]
    ) -> [MeasurementKind] {
        var result: [MeasurementKind] = []
        for rawValue in values {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let kind: MeasurementKind?
            switch normalized {
            case "shoulder", "shoulder_width", "shoulder_width_seam_to_seam":
                kind = .shoulder
            case "chest", "chest_width", "chest_width_pit_to_pit",
                 "chest_width_uniqlo_body_width", "chest_circumference_garment":
                kind = .chest
            case "total_length", "body_length", "body_length_back_neck_to_hem",
                 "body_length_hps_to_hem_front", "pants_outseam_waist_to_hem",
                 "pants_inseam_crotch_to_hem", "skirt_length_waist_to_hem":
                kind = .totalLength
            case "sleeve_length", "sleeve_shoulder_seam_to_cuff",
                 "sleeve_center_back_to_cuff", "sleeve_raglan_neck_to_cuff":
                kind = .sleeveLength
            case "upper_abdomen", "upper_abdomen_width_edge_to_edge":
                kind = .upperAbdomen
            case "upper_waist", "upper_waist_width_edge_to_edge":
                kind = .upperWaist
            case "waist", "waist_width", "waist_width_edge_to_edge",
                 "waist_circumference_garment":
                kind = .waist
            case "hip", "hip_width", "hip_width_at_widest":
                kind = .hip
            case "thigh", "thigh_width", "thigh_width_crotch_to_outer":
                kind = .thigh
            case "rise", "front_rise", "rise_crotch_to_waist_front",
                 "rise_crotch_to_waist_back":
                kind = .rise
            case "hem", "hem_width", "hem_width_edge_to_edge":
                kind = .hem
            case "foot_length", "foot_length_heel_to_toe":
                kind = .footLength
            case "under_bust", "under_bust_width", "under_bust_width_edge_to_edge":
                kind = .underBust
            default:
                kind = nil
            }
            if let kind, !result.contains(kind) { result.append(kind) }
        }
        return result
    }

    private func exclusionReasons(
        for kinds: [MeasurementKind]
    ) -> [MeasurementKind: MeasurementExclusionReason] {
        Dictionary(uniqueKeysWithValues: kinds.map { kind in
            if kind == .sleeveLength {
                return (kind, .sleeveLengthMismatch)
            }
            if kind == .totalLength || kind == .hem {
                return (kind, .garmentLengthMismatch)
            }
            return (kind, .categoryPolicy)
        })
    }

    func automaticMatchResult(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> AutomaticComparisonMatchResult {
        let profileResult = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        guard !profileResult.compatibleCandidates.isEmpty else { return profileResult }
        let ranked = Array(rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: profileResult.compatibleCandidates
        ).prefix(3))
        let candidates = ranked.isEmpty
            ? profileResult.compatibleCandidates
            : ranked.map(\.userFit)
        return AutomaticComparisonMatchResult(
            state: .compatible,
            incomingProfile: profileResult.incomingProfile,
            compatibleCandidates: candidates
        )
    }

    func manualCandidateNote(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        item: UserFit
    ) -> String? {
        comparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: item
        ).reason
    }

    func comparisonCompatibility(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        item: UserFit
    ) -> GarmentComparisonCompatibility {
        guard product.canonicalEligibility != false,
              item.canonicalEligibility != false else {
            return .blocked("분류 검증이 완료되지 않아 비교할 수 없어요.")
        }
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            guard item.category.serviceGroup == product.category.serviceGroup else {
                return .blocked("착용 부위가 달라 비교할 수 없어요.")
            }
            return GarmentComparisonCompatibility(
                level: .direct,
                reason: "같은 의류군 · 기준표 가슴둘레 비교"
            )
        }
        return comparisonMatcher.manualComparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: item
        )
    }

    func manualComparisonScorePenalty(
        product: Product,
        selectedReferenceItem: UserFit
    ) -> Int {
        comparisonMatcher.hasSamePlatformOfficialFormat(
            product: product,
            selectedItem: selectedReferenceItem
        ) ? 0 : 12
    }

    func hasDetailCategoryClosetItem(
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        userFits.contains { $0.detailCategory == productDetailCategory }
    }

    func hasDetailCategoryBasis(
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        userFits.contains { $0.detailCategory == productDetailCategory && $0.isRepresentative }
    }

    func temporaryComparisonCandidates(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [UserFit] {
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            return standardSizeCandidates(product: product, userFits: userFits).map(\.userFit)
        }
        let manual = comparisonMatcher.manualCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        let recommended = rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: manual
        ).prefix(3).map(\.userFit)
        let recommendedIDs = Set(recommended.map(\.id))
        return recommended + manual.filter { !recommendedIDs.contains($0.id) }
    }

    func rankedFitMatches(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [FitMatchCandidate] {
        Array(rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).prefix(3))
    }

    func referenceSelectionPlan(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> ReferenceSelectionPlan {
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            let candidates = standardSizeCandidates(product: product, userFits: userFits)
            let representatives = candidates.filter {
                $0.userFit.isRepresentative && $0.compatibleMeasurementCount > 0
            }
            return ReferenceSelectionPlan(
                recommendedCandidates: candidates,
                automaticallySelectedCandidate: representatives.count == 1
                    ? representatives.first
                    : nil
            )
        }
        let compatible = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).compatibleCandidates
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        let candidates = Array(rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: compatible
        ).prefix(3))
        let automaticallySelected: FitMatchCandidate?
        if preferredRepresentativeIDs.isEmpty {
            automaticallySelected = nil
        } else {
            let preferredCandidates = candidates.filter {
                preferredRepresentativeIDs.contains($0.id)
            }
            automaticallySelected = preferredCandidates.count == 1
                ? preferredCandidates.first
                : nil
        }

        return ReferenceSelectionPlan(
            recommendedCandidates: candidates,
            automaticallySelectedCandidate: automaticallySelected
        )
    }

    private func sortCandidates(_ userFits: [UserFit]) -> [UserFit] {
        userFits.sorted { lhs, rhs in
            if lhs.isRepresentative != rhs.isRepresentative {
                return lhs.isRepresentative
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func bestRecommendation(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        basis: RecommendationBasis
    ) -> RecommendationHistory? {
        guard product.canonicalEligibility != false else { return nil }
        if usesStandardSizeFallback(product: product, userFits: userFits) {
            return standardSizeRecommendation(
                product: product,
                userFits: userFits,
                productDetailCategory: productDetailCategory,
                basis: basis
            )
        }

        var bestHistory: RecommendationHistory?
        var bestFitConfidence = -1
        var bestAverageDifference = Double.greatestFiniteMagnitude

        for size in product.sizes.sorted(by: { $0.displayOrder < $1.displayOrder }) where !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for userFit in userFits where userFit.canonicalEligibility != false {
                let fitConfidence = measurementComparisonEngine.compare(
                    productSize: size,
                    referenceItem: userFit,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory,
                    excludedKinds: basis.excludedMeasurementKinds,
                    excludedKindReasons: basis.excludedMeasurementReasons
                )
                guard fitConfidence.status == .confirmed else { continue }
                let signedDifferences = fitConfidence.signedDifferences

                let adjustedScore = max(0, fitConfidence.score - basis.scorePenalty)

                let history = RecommendationHistory(
                    product: product,
                    recommendedSize: size,
                    userFit: userFit,
                    totalDifference: fitConfidence.averageDifference,
                    measurementDifferences: signedDifferences,
                    recommendationScore: adjustedScore,
                    trueToSizeRecommendation: "기준 옷과 실측이 가장 비슷한 \(size.name) 사이즈입니다.",
                    oversizedRecommendation: "",
                    comparisonMethod: basis.methodText,
                    fallbackReason: basis.fallbackReason,
                    productDetailCategory: productDetailCategory,
                    comparisonResult: fitConfidence
                )

                printFitConfidenceDebug(
                    referenceItem: userFit,
                    sizeName: size.name,
                    signedDifferences: signedDifferences,
                    result: fitConfidence
                )

                if adjustedScore > bestFitConfidence ||
                    (adjustedScore == bestFitConfidence && fitConfidence.averageDifference < bestAverageDifference) {
                    bestHistory = history
                    bestFitConfidence = adjustedScore
                    bestAverageDifference = fitConfidence.averageDifference
                }
            }
        }

        if let bestHistory {
            #if DEBUG
            FitMatchDebugLogger.detail(
                screen: "추천 계산",
                action: "최종 후보 선택",
                details: "기준옷=\(bestHistory.userFit.displayName), 방식=\(bestHistory.comparisonMethod), 추천사이즈=\(bestHistory.recommendedSize.name), 신뢰도=\(bestHistory.recommendationScore)"
            )
            #endif
        }

        return bestHistory
    }

    private func usesStandardSizeFallback(product: Product, userFits: [UserFit]) -> Bool {
        product.sizeType == StandardBodySizeChart.metadataMarker
            || userFits.contains { $0.sourceProduct?.sizeType == StandardBodySizeChart.metadataMarker }
    }

    private func standardSizeRecommendation(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        basis: RecommendationBasis
    ) -> RecommendationHistory? {
        guard product.canonicalEligibility != false else { return nil }
        let sizes = product.sizes.sorted { $0.displayOrder < $1.displayOrder }
        var bestHistory: RecommendationHistory?
        var bestDifference = Double.greatestFiniteMagnitude

        for size in sizes {
            guard let productChest = StandardBodySizeChart.chestCircumferenceCm(for: size.name) else { continue }
            for userFit in userFits where userFit.canonicalEligibility != false {
                guard let referenceChest = StandardBodySizeChart.chestCircumferenceCm(for: userFit.sizeName) else { continue }
                let signedDifference = productChest - referenceChest
                let absoluteDifference = abs(signedDifference)
                let score = max(0, min(100, Int((100 - absoluteDifference * 5).rounded())))
                let item = MeasurementComparisonItem(
                    kind: .chest,
                    measurementCode: .standardBodyChestCircumference,
                    productValue: productChest,
                    referenceValue: referenceChest,
                    signedDifference: signedDifference,
                    absoluteDifference: absoluteDifference,
                    score: score,
                    weight: 1
                )
                let comparison = MeasurementComparisonResult(
                    status: .confirmed,
                    score: score,
                    comparedItems: [item],
                    exclusions: standardSizeExclusions,
                    averageDifference: absoluteDifference,
                    minimumComparableCount: 1,
                    requiredKinds: [.chest],
                    minimumRequiredKindCount: 1,
                    requiredAllKinds: [],
                    expectedWeightSum: 1,
                    usedWeightSum: 1
                )
                let history = RecommendationHistory(
                    product: product,
                    recommendedSize: size,
                    userFit: userFit,
                    totalDifference: absoluteDifference,
                    measurementDifferences: comparison.signedDifferences,
                    recommendationScore: max(0, score - basis.scorePenalty),
                    trueToSizeRecommendation: standardSizeReason(productSize: size.name, referenceSize: userFit.sizeName, difference: signedDifference),
                    oversizedRecommendation: "기준표에는 총장과 소매 정보가 없어 가슴둘레만 비교했습니다.",
                    comparisonMethod: "기준표 가슴둘레 비교",
                    fallbackReason: "실측값이 아닌 한국 의류 기준표 기반 결과입니다.",
                    productDetailCategory: productDetailCategory,
                    comparisonResult: comparison
                )
                if absoluteDifference < bestDifference {
                    bestDifference = absoluteDifference
                    bestHistory = history
                }
            }
        }

        return bestHistory
    }

    private var standardSizeExclusions: [MeasurementComparisonExclusion] {
        [.shoulder, .totalLength, .sleeveLength].map {
            MeasurementComparisonExclusion(
                kind: $0,
                reason: .missingProductValue,
                productCode: nil,
                referenceCode: nil
            )
        }
    }

    private func standardSizeReason(productSize: String, referenceSize: String, difference: Double) -> String {
        let absolute = abs(difference).formatted(.number.precision(.fractionLength(0...1)))
        if difference == 0 { return "두 사이즈의 기준표 가슴둘레가 같습니다." }
        let larger = difference > 0 ? productSize : referenceSize
        return "\(larger) 사이즈가 기준표 가슴둘레 기준 \(absolute)cm 큽니다."
    }

    private func bestInsufficientEvidence(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        excludedKinds: [MeasurementKind],
        excludedKindReasons: [MeasurementKind: MeasurementExclusionReason] = [:]
    ) -> InsufficientComparisonEvidence? {
        guard product.canonicalEligibility != false else { return nil }
        var bestEvidence: InsufficientComparisonEvidence?

        for size in product.sizes.sorted(by: { $0.displayOrder < $1.displayOrder })
        where !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for userFit in userFits where userFit.canonicalEligibility != false {
                let result = measurementComparisonEngine.compare(
                    productSize: size,
                    referenceItem: userFit,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory,
                    excludedKinds: excludedKinds,
                    excludedKindReasons: excludedKindReasons
                )
                guard result.status == .insufficientEvidence else { continue }

                let candidate = InsufficientComparisonEvidence(
                    productSize: size,
                    referenceItem: userFit,
                    comparisonResult: result
                )
                guard let current = bestEvidence else {
                    bestEvidence = candidate
                    continue
                }
                if result.comparedItems.count > current.comparisonResult.comparedItems.count
                    || (result.comparedItems.count == current.comparisonResult.comparedItems.count
                        && result.score > current.comparisonResult.score) {
                    bestEvidence = candidate
                }
            }
        }

        return bestEvidence
    }

    func hasRelevantClosetItem(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        automaticBasisExists(product: product, productDetailCategory: productDetailCategory, userFits: userFits)
    }

    private func selectBasis(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit],
        allowsGlobalFallback: Bool
    ) -> RecommendationBasis {
        guard product.canonicalEligibility != false else {
            return RecommendationBasis(
                userFits: [],
                methodText: "분류 검증 필요",
                scorePenalty: 0
            )
        }
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            let candidates = standardSizeCandidates(product: product, userFits: userFits)
            let representatives = candidates.filter {
                $0.userFit.isRepresentative && $0.compatibleMeasurementCount > 0
            }
            return RecommendationBasis(
                userFits: representatives.count == 1
                    ? representatives.map(\.userFit)
                    : [],
                methodText: "기준표 가슴둘레 비교",
                scorePenalty: 18,
                fallbackReason: "실측값이 아닌 한국 의류 기준표 기반 결과입니다."
            )
        }
        let result = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        let ranked = rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: result.compatibleCandidates
        )
        let preferredCandidates = ranked.filter {
            preferredRepresentativeIDs.contains($0.userFit.id)
        }
        let selected = preferredCandidates.count == 1
            ? preferredCandidates.first?.userFit
            : nil
        if let selected {
            return RecommendationBasis(
                userFits: [selected],
                methodText: "비교 프로필 호환 옷 비교",
                scorePenalty: 0
            )
        }

        return RecommendationBasis(userFits: [], methodText: "사용자 선택 임시 비교", scorePenalty: 12)
    }

    private func automaticBasisExists(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        guard product.canonicalEligibility != false else { return false }
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            return standardSizeCandidates(product: product, userFits: userFits)
                .filter { $0.userFit.isRepresentative && $0.compatibleMeasurementCount > 0 }
                .count == 1
        }
        let profileCandidates = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).compatibleCandidates
        let ranked = rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: profileCandidates
        )
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        return ranked.filter {
            preferredRepresentativeIDs.contains($0.userFit.id)
        }.count == 1
    }

    private func standardSizeCandidates(product: Product, userFits: [UserFit]) -> [FitMatchCandidate] {
        guard product.canonicalEligibility != false else { return [] }
        let sameCategory = userFits.filter {
            $0.canonicalEligibility != false
                && $0.category.serviceGroup == product.category.serviceGroup
                && StandardBodySizeChart.chestCircumferenceCm(for: $0.sizeName) != nil
        }
        let sorted = sameCategory.sorted { lhs, rhs in
            if lhs.isRepresentative != rhs.isRepresentative { return lhs.isRepresentative }
            return lhs.updatedAt > rhs.updatedAt
        }
        return sorted.map { item in
            return FitMatchCandidate(
                userFit: item,
                matchRate: 70,
                compatibleMeasurementCount: 1,
                selectionReason: "기준표 가슴둘레 비교 가능"
            )
        }
    }

    private func rankedReferenceCandidates(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [FitMatchCandidate] {
        let incomingProfile = comparisonMatcher.profile(for: product, detailCategory: productDetailCategory)
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        return userFits
            .compactMap { item -> RankedReferenceCandidate? in
                let compatibility = comparisonMatcher.comparisonCompatibility(
                    product: product,
                    productDetailCategory: productDetailCategory,
                    item: item
                )
                guard compatibility.level.isAllowed else { return nil }
                let candidateProfile = comparisonMatcher.profile(for: item)
                guard let comparison = bestFitConfidence(
                        product: product,
                        userFit: item,
                        productDetailCategory: productDetailCategory
                      ) else {
                    return nil
                }
                let constructionRank: Int
                if incomingProfile.constructionType != .unknown,
                   candidateProfile.constructionType == incomingProfile.constructionType {
                    constructionRank = 2
                } else if incomingProfile.constructionType == .unknown || candidateProfile.constructionType == .unknown {
                    constructionRank = 1
                } else {
                    constructionRank = 0
                }
                let sameBrand = matchesBrand(item, product: product)
                let sameDetail = item.detailCategory == productDetailCategory
                let directSourceMeasurementCount = comparisonMatcher.directSourceComparisonCount(
                    product: product,
                    selectedItem: item
                )
                let reasonParts = [
                    compatibility.reason,
                    incomingProfile.lengthType.displayName.isEmpty ? nil : "같은 \(incomingProfile.lengthType.displayName)",
                    directSourceMeasurementCount > 0 ? "측정 방식 \(directSourceMeasurementCount)개 일치" : nil,
                    constructionRank == 2 ? "같은 봉제 구조" : nil,
                    sameBrand ? "같은 브랜드" : nil
                ].compactMap { $0 }
                return RankedReferenceCandidate(
                    candidate: FitMatchCandidate(
                        userFit: item,
                        matchRate: comparison.score,
                        compatibleMeasurementCount: comparison.comparedItems.count,
                        selectionReason: reasonParts.joined(separator: " · ")
                    ),
                    compatibilityRank: compatibility.level.rawValue,
                    constructionRank: constructionRank,
                    directSourceMeasurementCount: directSourceMeasurementCount,
                    isSameDetail: sameDetail,
                    isSameBrand: sameBrand
                )
            }
            .sorted { lhs, rhs in
                let lhsPreferred = preferredRepresentativeIDs.contains(lhs.candidate.userFit.id)
                let rhsPreferred = preferredRepresentativeIDs.contains(rhs.candidate.userFit.id)
                if lhsPreferred != rhsPreferred { return lhsPreferred }
                if lhs.compatibilityRank != rhs.compatibilityRank {
                    return lhs.compatibilityRank > rhs.compatibilityRank
                }
                if lhs.isSameDetail != rhs.isSameDetail { return lhs.isSameDetail }
                if lhs.directSourceMeasurementCount != rhs.directSourceMeasurementCount {
                    return lhs.directSourceMeasurementCount > rhs.directSourceMeasurementCount
                }
                if lhs.constructionRank != rhs.constructionRank { return lhs.constructionRank > rhs.constructionRank }
                if lhs.candidate.compatibleMeasurementCount != rhs.candidate.compatibleMeasurementCount {
                    return lhs.candidate.compatibleMeasurementCount > rhs.candidate.compatibleMeasurementCount
                }
                if lhs.candidate.matchRate != rhs.candidate.matchRate { return lhs.candidate.matchRate > rhs.candidate.matchRate }
                if lhs.isSameBrand != rhs.isSameBrand { return lhs.isSameBrand }
                if lhs.candidate.userFit.updatedAt != rhs.candidate.userFit.updatedAt {
                    return lhs.candidate.userFit.updatedAt > rhs.candidate.userFit.updatedAt
                }
                return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString
            }
            .map(\.candidate)
    }

    private func preferredRepresentatives(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [UserFit] {
        let exactDetailRepresentatives = userFits.filter {
            $0.isRepresentative
                && $0.detailCategory == productDetailCategory
                && comparisonMatcher.comparisonCompatibility(
                    product: product,
                    productDetailCategory: productDetailCategory,
                    item: $0
                ).level == .direct
        }
        guard let selected = exactDetailRepresentatives.sorted(by: {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }).first else {
            return []
        }
        return [selected]
    }

    private func rankedCandidateScore(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Int {
        product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { size in
                measurementComparisonEngine.compare(
                    productSize: size,
                    referenceItem: item,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                )
            }
            .filter { $0.status == .confirmed }
            .map(\.score)
            .max() ?? 0
    }

    private func bestFitConfidence(
        product: Product,
        userFit: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> MeasurementComparisonResult? {
        product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                measurementComparisonEngine.compare(
                    productSize: $0,
                    referenceItem: userFit,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                )
            }
            .filter { $0.status == .confirmed }
            .max { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                return lhs.averageDifference > rhs.averageDifference
            }
    }

    private func v1MeasurementKinds(
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory
    ) -> [MeasurementKind] {
        switch productCategory.serviceGroup {
        case .top, .shirt, .knit:
            return [.shoulder, .chest, .totalLength, .sleeveLength]
        case .outer:
            return [.shoulder, .chest, .totalLength, .sleeveLength, .hem]
        case .bottom, .pants:
            return [.waist, .hip, .thigh, .rise, .hem, .totalLength]
        default:
            return productCategory.measurementKinds(detailCategory: productDetailCategory, gender: .unisex)
        }
    }

    private func printFitConfidenceDebug(
        referenceItem: UserFit,
        sizeName: String,
        signedDifferences: GarmentMeasurements,
        result: MeasurementComparisonResult
    ) {
        #if DEBUG
        let comparedNames = result.comparedItems.map { $0.kind.title }.joined(separator: ", ")
        let ignoredNames = result.exclusions.map { $0.kind.title }.joined(separator: ", ")
        let shoulderScore = result.score(for: .shoulder)?.description ?? "ignored"
        let chestScore = result.score(for: .chest)?.description ?? "ignored"
        let totalLengthScore = result.score(for: .totalLength)?.description ?? "ignored"
        let sleeveScore = result.score(for: .sleeveLength)?.description ?? "ignored"

        FitMatchDebugLogger.detail(
            screen: "추천 계산",
            action: "사이즈 후보 평가",
            details: "기준옷=\(referenceItem.displayName), 사이즈=\(sizeName), 비교=\(comparedNames), 제외=\(ignoredNames), 어깨=\(signedDifferences.shoulder)/\(shoulderScore), 가슴=\(signedDifferences.chest)/\(chestScore), 총장=\(signedDifferences.totalLength)/\(totalLengthScore), 소매=\(signedDifferences.sleeveLength)/\(sleeveScore), 신뢰도=\(result.score), 근거=\(result.reliabilityTitle)"
        )
        #endif
    }

    private func matchesSource(_ item: UserFit, product: Product) -> Bool {
        normalized(item.sourceName) == normalized(product.sourceName)
    }

    private func matchesBrand(_ item: UserFit, product: Product) -> Bool {
        guard let productBrand = product.brand?.name, !productBrand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return normalized(item.brandName) == normalized(productBrand)
    }

    private func matchesShoppingCategory(_ item: UserFit, product: Product) -> Bool {
        normalized(item.sourceCategoryNameForMatching) == normalized(product.sourceCategoryNameForMatching)
    }

    private func matchesInternalCategory(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Bool {
        item.category == product.category && item.detailCategory == productDetailCategory
    }

    private func hasComparableMeasurements(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Bool {
        let kinds = v1MeasurementKinds(productCategory: product.category, productDetailCategory: productDetailCategory)
        guard !kinds.isEmpty else { return true }
        return product.sizes.contains { size in
            kinds.contains {
                size.measurements.value(for: $0) > 0 && item.measurements.value(for: $0) > 0
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func measurementWeights(
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory,
        referenceDetailCategory: ClosetDetailCategory,
        comparisonMethod: String
    ) -> GarmentMeasurements {
        var weights: GarmentMeasurements

        switch productCategory.serviceGroup {
        case .bottom:
            weights = GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 1.0,
                sleeveLength: 0,
                waist: 1.4,
                hip: 1.2,
                thigh: 0.9,
                rise: 0.7,
                hem: 0.6
            )
        case .shoes:
            weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, footLength: 1.6)
        case .dress:
            weights = GarmentMeasurements(
                shoulder: 1.0,
                chest: 1.2,
                totalLength: 1.0,
                sleeveLength: 0.5,
                waist: 1.0,
                hip: 0.9
            )
        case .underwear:
            switch productDetailCategory {
            case .menBriefs, .menTrunks, .womenPanty:
                weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, waist: 1.3, hip: 1.2)
            case .menUndershirt:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.2, totalLength: 0.8, sleeveLength: 0)
            case .womenBra:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.2, totalLength: 0, sleeveLength: 0, underBust: 1.4)
            case .womenCamisole:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.1, totalLength: 0.7, sleeveLength: 0, underBust: 1.2)
            case .womenSlip:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.0, totalLength: 0.7, sleeveLength: 0, waist: 1.0, hip: 1.0, underBust: 1.1)
            case .socks:
                weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, footLength: 1.0)
            default:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.0, totalLength: 0.6, sleeveLength: 0, waist: 1.0, hip: 1.0)
            }
        case .accessory:
            weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        case .outer:
            weights = GarmentMeasurements(
                shoulder: 1.1,
                chest: 1.5,
                totalLength: 0.8,
                sleeveLength: 1.0,
                hem: 0.6
            )
        case .top, .other, .pants, .shirt, .knit:
            weights = GarmentMeasurements(
                shoulder: 1.2,
                chest: 1.4,
                totalLength: 1.0,
                sleeveLength: 0.8
            )
        }

        switch productDetailCategory {
        case .sleeveless:
            weights.sleeveLength = 0
        case .shortSleeve:
            weights.sleeveLength = min(weights.sleeveLength, 0.2)
        case .longSleeve, .shirt, .sweatshirt, .hoodie, .jumper, .jacket, .coat:
            weights.sleeveLength = max(weights.sleeveLength, 0.9)
        default:
            break
        }

        if comparisonMethod == "사용자 선택 임시 비교",
           productDetailCategory != referenceDetailCategory,
           (productDetailCategory == .shortSleeve || productDetailCategory == .sleeveless) {
            weights.sleeveLength = min(weights.sleeveLength, 0.2)
        }

        return weights
    }

    private func weightedDifference(differences: GarmentMeasurements, weights: GarmentMeasurements) -> Double {
        let weightedSum = differences.shoulder * weights.shoulder
            + differences.chest * weights.chest
            + differences.totalLength * weights.totalLength
            + differences.sleeveLength * weights.sleeveLength
            + differences.waist * weights.waist
            + differences.hip * weights.hip
            + differences.thigh * weights.thigh
            + differences.rise * weights.rise
            + differences.hem * weights.hem
            + differences.footLength * weights.footLength
            + differences.underBust * weights.underBust
        let weightSum = weights.shoulder + weights.chest + weights.totalLength + weights.sleeveLength
            + weights.waist + weights.hip + weights.thigh + weights.rise + weights.hem + weights.footLength + weights.underBust
        guard weightSum > 0 else {
            return .greatestFiniteMagnitude
        }
        return weightedSum / weightSum
    }

    private func validMeasurementCount(size: GarmentMeasurements, userFit: GarmentMeasurements, weights: GarmentMeasurements) -> Int {
        [
            (size.shoulder, userFit.shoulder, weights.shoulder),
            (size.chest, userFit.chest, weights.chest),
            (size.totalLength, userFit.totalLength, weights.totalLength),
            (size.sleeveLength, userFit.sleeveLength, weights.sleeveLength),
            (size.waist, userFit.waist, weights.waist),
            (size.hip, userFit.hip, weights.hip),
            (size.thigh, userFit.thigh, weights.thigh),
            (size.rise, userFit.rise, weights.rise),
            (size.hem, userFit.hem, weights.hem),
            (size.footLength, userFit.footLength, weights.footLength),
            (size.underBust, userFit.underBust, weights.underBust)
        ].filter { productValue, referenceValue, weight in
            productValue > 0 && referenceValue > 0 && weight > 0
        }.count
    }

}

private struct RecommendationBasis {
    let userFits: [UserFit]
    let methodText: String
    let scorePenalty: Int
    var fallbackReason: String = ""
    var excludedMeasurementKinds: [MeasurementKind] = []
    var excludedMeasurementReasons: [MeasurementKind: MeasurementExclusionReason] = [:]
}

private struct RankedReferenceCandidate {
    let candidate: FitMatchCandidate
    let compatibilityRank: Int
    let constructionRank: Int
    let directSourceMeasurementCount: Int
    let isSameDetail: Bool
    let isSameBrand: Bool
}
