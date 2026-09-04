import Foundation
import Combine

enum FitMatchIOSServerAuthorityState: Equatable {
    case idle
    case resolving
    case confirmed(FitMatchServerProductAuthority)
    case reviewRequired(FitMatchServerProductAuthority)
    case notComparable(FitMatchServerProductAuthority)
    case unavailable(String)

    var productLoadFailureTitle: String? {
        switch self {
        case .reviewRequired:
            return "이 상품은 분류 확인이 필요해요."
        case .notComparable:
            return "이 상품은 비교할 수 없는 상품이에요."
        case .idle, .resolving, .confirmed, .unavailable:
            return nil
        }
    }
}

enum FitMatchReviewRecoveryState: Equatable {
    case idle
    case loading
    case choosingGarment(VNextClassificationRecoveryContractDTO)
    case choosingAxis(
        VNextClassificationRecoveryContractDTO,
        VNextClassificationRecoveryGarmentGroup
    )
    case unrecoverable(VNextClassificationRecoveryContractDTO)
    case saving
    case resuming
    case failed(String)
}

@MainActor
final class ShoppingProductViewModel: ObservableObject {
    @Published var productURL = ""
    @Published var sourceType: ProductSourceType = .manual
    @Published var sourceName = "직접 입력"
    @Published var brand = ""
    @Published var productName = ""
    @Published var category: ClothingCategory = .top
    @Published var detailCategory: ClosetDetailCategory = .other
    @Published var sizeOptions: [ClothingSizeForm] = [
        ClothingSizeForm()
    ]
    @Published var recommendation: RecommendationHistory?
    @Published var errorMessage: String?
    @Published var parserNotice: String?
    @Published var isLoadingProductInfo = false
    @Published var productImageURLString: String?
    @Published var productPrice: Int?
    @Published var productCanonicalURLString: String?
    @Published var productCode: String?
    @Published var productMetadata = ProductMetadata()
    @Published var hasLoadedProductInfo = false
    @Published var measurementAvailability: ProductMeasurementAvailability = .actualMeasurements
    @Published var sizeTableRecoveryContext: SizeTableRecoveryContext?
    @Published var isAnalyzingRecoveryImage = false
    @Published var recoveryErrorMessage: String?
    @Published var recoverySelectedSizeID: UUID?
    @Published var isNetworkFailure = false
    @Published var analysisPhase: ProductAnalysisPhase = .loadingProductInfo
    @Published private(set) var productAnalysisRecoveryAction: ProductAnalysisRecoveryAction?
    @Published private(set) var databaseShadowState: FitMatchDatabaseShadowState = .idle
    @Published private(set) var serverAuthorityState: FitMatchIOSServerAuthorityState = .idle
    @Published private(set) var reviewRecoveryState: FitMatchReviewRecoveryState = .idle
    @Published private(set) var classificationSafetyAudit: ParsedClosetClassificationSafetyAudit = .safe

    private let recommendationService: RecommendationService
    private let parserService: ProductURLParserService
    private let metricsRecorder: FitMatchMetricsRecording
    private let serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator?
    private var activeLoadID: UUID?
    private var parsedProductForServerAuthority: ParsedProductInfo?

    init(
        initialURL: String? = nil,
        recommendationService: RecommendationService? = nil,
        parserService: ProductURLParserService? = nil,
        metricsRecorder: FitMatchMetricsRecording? = nil,
        databaseProductResolver: (any FitMatchProductResolving)? = nil,
        serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator? = nil
    ) {
        productURL = initialURL ?? ""
        self.recommendationService = recommendationService ?? RecommendationService()
        self.parserService = parserService ?? ProductURLParserService()
        self.metricsRecorder = metricsRecorder ?? FitMatchMetricsRecorder.shared
        if let serverAuthorityCoordinator {
            self.serverAuthorityCoordinator = serverAuthorityCoordinator
        } else if let remote = databaseProductResolver as? any FitMatchServerAuthorityRemoteServicing {
            self.serverAuthorityCoordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        } else if databaseProductResolver == nil {
            self.serverAuthorityCoordinator = FitMatchServerAuthorityCoordinator()
        } else {
            // A legacy resolve-only test double cannot satisfy promotion and
            // runtime persistence. Treat it as unavailable instead of falling
            // back to a local canonical result.
            self.serverAuthorityCoordinator = nil
        }
    }

    // This view model owns only Sendable task state at teardown. Keeping the
    func addSizeOption() {
        sizeOptions.append(ClothingSizeForm())
    }

    func removeSizeOption(_ option: ClothingSizeForm) {
        guard sizeOptions.count > 1 else {
            return
        }

        sizeOptions.removeAll { $0.id == option.id }
    }

    func loadProductInfoFromURL() async -> Bool {
        let loadID = UUID()
        let metricProvider = FitMatchMetricProvider.resolve(urlString: productURL)
        metricsRecorder.record(.parserAttempt(provider: metricProvider))
        activeLoadID = loadID
        databaseShadowState = .idle
        serverAuthorityState = .idle
        reviewRecoveryState = .idle
        parsedProductForServerAuthority = nil
        classificationSafetyAudit = .safe
        errorMessage = nil
        parserNotice = nil
        productAnalysisRecoveryAction = nil
        hasLoadedProductInfo = false
        productCode = nil
        productMetadata = ProductMetadata()
        sizeTableRecoveryContext = nil
        isNetworkFailure = false
        analysisPhase = .loadingProductInfo
        isLoadingProductInfo = true
        defer {
            if activeLoadID == loadID {
                activeLoadID = nil
                isLoadingProductInfo = false
            }
        }

        do {
            let parsedProduct = try await parserService.parse(
                urlString: productURL,
                onProgress: { [weak self] phase in
                    guard self?.activeLoadID == loadID else { return }
                    self?.analysisPhase = phase
                }
            )
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            analysisPhase = .preparingComparison
            apply(parsedProduct)
            let isServerConfirmed = await resolveServerAuthority(for: parsedProduct)
            metricsRecorder.record(
                .parserSuccess(
                    provider: metricProvider,
                    category: FitMatchMetricMajorCategory(category: category),
                    detail: detailCategory == .other ? .catchAll : .specific,
                    measurement: FitMatchMetricMeasurementAvailability(measurementAvailability)
                )
            )
            return isServerConfirmed
        } catch let partialError as ProductURLParserPartialError {
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            apply(partialError.productInfo)
            _ = await resolveServerAuthority(for: partialError.productInfo)
            metricsRecorder.record(.parserFailure(provider: metricProvider, reason: .partial))
            if partialError.productInfo.sourceName == "무신사",
               partialError.productInfo.sizes.isEmpty {
                errorMessage = partialError.productInfo.parserNotice
                    ?? MusinsaParser.automaticSizeFailureNotice
            } else {
                errorMessage = partialError.productInfo.parserNotice ?? partialError.errorDescription
            }
            return false
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            let nsError = error as NSError
            isNetworkFailure = nsError.domain == NSURLErrorDomain
                || (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain == NSURLErrorDomain
            metricsRecorder.record(
                .parserFailure(
                    provider: metricProvider,
                    reason: parserFailureReason(error: error, isNetworkFailure: isNetworkFailure)
                )
            )
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "상품 정보를 불러오지 못했습니다."
            return false
        }
    }

    /// Starts a new comparison from an immutable History projection only when
    /// that projection retained enough official retailer identity for the
    /// existing server resolver.  It intentionally does not reconstruct a
    /// storefront URL or reuse historical authority: current authority is
    /// resolved through the same coordinator used by normal URL entry.
    func loadProductInfoFromHistoricalProduct(_ historicalProduct: Product) async -> Bool {
        guard let parsedProduct = historicalProduct.fitMatchStoredRetailerFactsForRecompare(),
              parsedProduct.fitMatchDatabaseResolutionRequest() != nil else {
            errorMessage = "이 비교 기록의 상품 정보를 다시 불러올 수 없어요. 상품 링크를 다시 열어 주세요."
            return false
        }

        let loadID = UUID()
        activeLoadID = loadID
        databaseShadowState = .idle
        serverAuthorityState = .idle
        reviewRecoveryState = .idle
        parsedProductForServerAuthority = nil
        classificationSafetyAudit = .safe
        errorMessage = nil
        parserNotice = nil
        productAnalysisRecoveryAction = nil
        hasLoadedProductInfo = false
        productCode = nil
        productMetadata = ProductMetadata()
        sizeTableRecoveryContext = nil
        isNetworkFailure = false
        analysisPhase = .preparingComparison
        isLoadingProductInfo = true
        defer {
            if activeLoadID == loadID {
                activeLoadID = nil
                isLoadingProductInfo = false
            }
        }

        apply(parsedProduct)
        // A retained canonical URL is presentation data, not a prerequisite
        // for the server resolver.  Do not surface the private invalid
        // placeholder used solely by the existing stored-facts request.
        productURL = historicalProduct.sourceURLString ?? ""
        productCanonicalURLString = historicalProduct.sourceURLString
        guard !Task.isCancelled, activeLoadID == loadID else { return false }
        return await resolveServerAuthority(for: parsedProduct)
    }

    func cancelProductLoading() {
        activeLoadID = nil
        databaseShadowState = .idle
        serverAuthorityState = .idle
        reviewRecoveryState = .idle
        parsedProductForServerAuthority = nil
        classificationSafetyAudit = .safe
        isLoadingProductInfo = false
    }

    /// Resumes the same ZARA import after an explicit user classification.
    /// The selected category remains authoritative for this recovery attempt;
    /// the retailer's ambiguous source path must not silently overwrite it.
    func resumeZARAParsingAfterCategoryConfirmation() async -> Bool {
        let selectedCategory = category
        let selectedDetailCategory = detailCategory
        guard productAnalysisRecoveryAction == .confirmCategoryBeforeMeasurements,
              selectedCategory != .other,
              selectedDetailCategory != .other else {
            errorMessage = "상품 종류를 먼저 선택해 주세요."
            return false
        }

        let loadID = UUID()
        activeLoadID = loadID
        errorMessage = nil
        analysisPhase = .loadingSizeChart
        isLoadingProductInfo = true
        defer {
            if activeLoadID == loadID {
                activeLoadID = nil
                isLoadingProductInfo = false
            }
        }

        do {
            let parsedProduct = try await parserService.resumeZARAParsing(
                urlString: productURL,
                confirmedCategory: selectedCategory,
                confirmedDetailCategory: selectedDetailCategory,
                onProgress: { [weak self] phase in
                    guard self?.activeLoadID == loadID else { return }
                    self?.analysisPhase = phase
                }
            )
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            analysisPhase = .preparingComparison
            apply(parsedProduct)
            category = selectedCategory
            detailCategory = selectedDetailCategory
            productAnalysisRecoveryAction = nil
            return await resolveServerAuthority(for: parsedProduct)
        } catch let partialError as ProductURLParserPartialError {
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            apply(partialError.productInfo)
            category = selectedCategory
            detailCategory = selectedDetailCategory
            productAnalysisRecoveryAction = partialError.productInfo.recoveryAction
                ?? .enterMeasurementsManually
            _ = await resolveServerAuthority(for: partialError.productInfo)
            errorMessage = partialError.productInfo.parserNotice ?? partialError.errorDescription
            return false
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            productAnalysisRecoveryAction = .enterMeasurementsManually
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "ZARA 실측 정보를 불러오지 못했어요."
            return false
        }
    }

    private func resolveServerAuthority(for product: ParsedProductInfo) async -> Bool {
        parsedProductForServerAuthority = product
        guard let request = product.fitMatchDatabaseResolutionRequest() else {
            databaseShadowState = .skipped
            serverAuthorityState = .unavailable("retailer_identity_missing")
            errorMessage = "서버에서 확인할 상품 식별 정보가 없습니다."
            return false
        }
        guard let serverAuthorityCoordinator else {
            databaseShadowState = .unavailable
            serverAuthorityState = .unavailable("server_authority_unavailable")
            errorMessage = "서버 상품 분류를 확인할 수 없습니다."
            return false
        }

        databaseShadowState = .checking
        serverAuthorityState = .resolving
        do {
            let authority = try await serverAuthorityCoordinator.resolveProductAuthority(
                request: request,
                observation: product.fitMatchProductObservationRequest()
            )
            guard !Task.isCancelled else { return false }
            switch authority.status {
            case .confirmed:
                applyServerClassification(authority.classification)
                applyServerRuntime(authority.runtime)
                serverAuthorityState = .confirmed(authority)
                // Kept only as a compatibility/debug signal. It is no longer a
                // shadow decision: the server tuple below is the actual input.
                databaseShadowState = .checking
                errorMessage = nil
                return true
            case .reviewRequired:
                serverAuthorityState = .reviewRequired(authority)
                databaseShadowState = .unavailable
                reviewRecoveryState = .loading
                do {
                    let contract = try await serverAuthorityCoordinator
                        .classificationRecoveryOptions(productID: authority.productID)
                    presentReviewRecovery(contract)
                } catch {
                    reviewRecoveryState = .failed(error.localizedDescription)
                    errorMessage = "상품 분류 선택지를 확인하지 못했습니다. 네트워크 연결 후 다시 시도해 주세요."
                }
                return false
            case .notComparable:
                serverAuthorityState = .notComparable(authority)
                databaseShadowState = .unavailable
                errorMessage = "세트 또는 비교 대상이 아닌 상품이라 비교를 진행할 수 없습니다."
                return false
            }
        } catch {
            guard !Task.isCancelled else { return false }
            databaseShadowState = .unavailable
            serverAuthorityState = .unavailable(error.localizedDescription)
            errorMessage = "서버 상품 분류를 확인하지 못했습니다. 네트워크 연결 후 다시 시도해 주세요."
            #if DEBUG
            FitMatchDebugLogger.event(
                screen: "상품 분석",
                action: "서버 v4 분류",
                state: "안전 차단",
                details: "오류=\(error.localizedDescription), 로컬 확정 fallback=사용 안 함"
            )
            #endif
            return false
        }
    }

    private func applyServerClassification(_ classification: FitMatchDatabaseClassification) {
        if let categoryCode = classification.categoryCode {
            category = ClothingCategory.fromTaxonomyCode(categoryCode)
        }
        if let detailCode = classification.detailCode {
            detailCategory = ClosetDetailCategory.fromTaxonomyCode(detailCode)
        }
    }

    private func applyServerRuntime(_ runtime: FitMatchProductRuntimeResponse) {
        guard let exact = runtime.vnext else { return }
        let observationVariant = parsedProductForServerAuthority?
            .fitMatchProductObservationRequest()?
            .payload.variants.first?.externalVariantID
        let variant: VNextRuntimeVariantDTO? = {
            if let observationVariant = observationVariant?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !observationVariant.isEmpty {
                return exact.variants.first(where: {
                    $0.sourceVariantKey == observationVariant
                })
            }
            return exact.variants.count == 1 ? exact.variants[0] : nil
        }()
        guard let variant else {
            sizeOptions = []
            return
        }

        sizeOptions = variant.sizes.enumerated().map { index, size in
            let parsedRecords = size.canonicalMeasurements.measurements.compactMap {
                measurement -> ParsedMeasurement? in
                guard let code = Self.runtimeMeasurementCode(
                    for: measurement.measurementCode,
                    basisCode: measurement.basisCode
                ), let displayKind = Self.displayKind(for: code) else {
                    return nil
                }
                return ParsedMeasurement(
                    value: measurement.value,
                    unit: .centimeter,
                    measurementCode: code,
                    displayKind: displayKind,
                    methodSource: "fitmatch_vnext_runtime",
                    methodProfile: exact.product?.resolverVersion,
                    inputSource: .importedSizeChart,
                    standardVersion: nil,
                    mappingVersion: exact.product?.resolverVersion
                        ?? "fitmatch-vnext-runtime-v1",
                    rawCode: measurement.sourceMeasurementCode,
                    rawLabel: measurement.sourceMeasurementCode
                        ?? measurement.measurementCode,
                    rawInfo: measurement.basisCode,
                    rawValueText: String(measurement.value),
                    evidenceLevel: .officialText,
                    semanticStatus: .mapped
                )
            }
            var form = Self.makeSizeForm(
                from: ParsedProductSize(
                    id: size.id,
                    name: size.sizeLabel,
                    measurements: GarmentMeasurements(
                        shoulder: 0,
                        chest: 0,
                        totalLength: 0,
                        sleeveLength: 0
                    ),
                    measurementRecords: parsedRecords,
                    availabilityStatus: size.availability.status,
                    availabilityObservedAt: Self.decodeRuntimeDate(
                        size.availability.observedAt
                    ),
                    availabilityValidUntil: Self.decodeRuntimeDate(
                        size.availability.validUntil
                    ),
                    availabilityEvidence: size.availability.evidenceFingerprint.map {
                        ["evidence_fingerprint": $0]
                    } ?? [:]
                ),
                displayOrder: index,
                allowsStandardSizeFallback: false
            )
            form.id = size.id
            return form
        }
    }

    private static func displayKind(for code: MeasurementCode) -> MeasurementDisplayKind? {
        switch code {
        case .standardBodyChestCircumference,
             .chestWidthPitToPit,
             .chestCircumferenceGarment,
             .chestWidthUniqloBodyWidth: return .chest
        case .shoulderWidthSeamToSeam: return .shoulder
        case .bodyLengthHPSToHemFront, .bodyLengthBackNeckToHem,
             .bodyLengthMusinsaType5, .bodyLengthMusinsaType20,
             .bodyLengthMusinsaType21, .bodyLengthUniqloBack,
             .bodyLengthUniqloShirt, .bodyLengthUniqloKnitFront,
             .pantsOutseamWaistToHem, .pantsInseamCrotchToHem,
             .skirtLengthWaistToHem: return .totalLength
        case .sleeveShoulderSeamToCuff, .sleeveCenterBackToCuff,
             .sleeveRaglanNeckToCuff: return .sleeveLength
        case .upperAbdomenWidthEdgeToEdge: return .upperAbdomen
        case .upperWaistWidthEdgeToEdge: return .upperWaist
        case .waistWidthEdgeToEdge, .waistCircumferenceGarment: return .waist
        case .hipWidthAtWidest: return .hip
        case .thighWidthCrotchToOuter: return .thigh
        case .riseCrotchToWaistFront, .riseCrotchToWaistBack: return .rise
        case .hemWidthEdgeToEdge: return .hem
        case .footLengthHeelToToe: return .footLength
        case .underBustWidthEdgeToEdge: return .underBust
        case .unknown, .legacyUnknown: return nil
        }
    }

    /// Converts the server's provider-independent measurement vocabulary into
    /// the app's method-specific storage vocabulary. The server remains the
    /// semantic authority; this is only a lossless transport adapter used by
    /// Closet registration and comparison product construction.
    static func runtimeMeasurementCode(
        for code: String,
        basisCode: String? = nil
    ) -> MeasurementCode? {
        if let exact = MeasurementCode(rawValue: code) {
            return exact
        }
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "back_length": return .bodyLengthBackNeckToHem
        case "total_length":
            switch basisCode {
            case "waist_to_skirt_hem": return .skirtLengthWaistToHem
            case "waist_to_hem", "waist_to_outseam": return .pantsOutseamWaistToHem
            default: return .bodyLengthBackNeckToHem
            }
        case "chest_width": return .chestWidthPitToPit
        case "shoulder_width": return .shoulderWidthSeamToSeam
        case "sleeve_length":
            return basisCode == "sleeve_center_back_to_cuff"
                ? .sleeveCenterBackToCuff : .sleeveShoulderSeamToCuff
        case "waist_width": return .waistWidthEdgeToEdge
        case "hip_width": return .hipWidthAtWidest
        case "thigh_width": return .thighWidthCrotchToOuter
        case "front_rise": return .riseCrotchToWaistFront
        case "hem_width": return .hemWidthEdgeToEdge
        case "inseam": return .pantsInseamCrotchToHem
        case "foot_length": return .footLengthHeelToToe
        case "under_bust_width": return .underBustWidthEdgeToEdge
        default: return nil
        }
    }

    private static func decodeRuntimeDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    var hasServerConfirmedAuthority: Bool {
        if case .confirmed = serverAuthorityState { return true }
        return false
    }

    var serverComparisonReadiness: FitMatchServerComparisonReadiness? {
        confirmedServerAuthority?.comparisonReadiness
    }

    var hasServerComparisonReadyAuthority: Bool {
        confirmedServerAuthority?.comparisonReadiness.isReady == true
    }

    var hasActiveUserExplicitClassification: Bool {
        guard case .confirmed(let authority) = serverAuthorityState else {
            return false
        }
        return authority.classification.authorityStatus == "user_explicit"
            && authority.runtime.vnext?.effectiveClassification?
                .isPersonalComparisonAuthority == true
    }

    var reviewRecoveryContract: VNextClassificationRecoveryContractDTO? {
        switch reviewRecoveryState {
        case .choosingGarment(let contract),
             .choosingAxis(let contract, _),
             .unrecoverable(let contract):
            return contract
        case .idle, .loading, .saving, .resuming, .failed:
            return nil
        }
    }

    var isReviewRecoverySaving: Bool {
        switch reviewRecoveryState {
        case .saving, .resuming: true
        default: false
        }
    }

    var hasServerReviewRequiredAuthority: Bool {
        if case .reviewRequired = serverAuthorityState { return true }
        return false
    }

    @discardableResult
    func beginReviewRecoveryReselection() async -> Bool {
        guard case .confirmed(let authority) = serverAuthorityState,
              authority.classification.authorityStatus == "user_explicit",
              authority.runtime.vnext?.effectiveClassification?
                .isPersonalComparisonAuthority == true,
              let coordinator = serverAuthorityCoordinator else {
            errorMessage = "현재 개인 분류를 다시 확인할 수 없습니다."
            return false
        }

        reviewRecoveryState = .loading
        errorMessage = nil
        do {
            let contract = try await coordinator.classificationRecoveryOptions(
                productID: authority.productID
            )
            guard contract.isSafelyRecoverable else {
                reviewRecoveryState = .unrecoverable(contract)
                errorMessage = "이 상품은 현재 안전한 선택지로 다시 분류할 수 없습니다."
                return false
            }
            presentReviewRecovery(contract)
            return true
        } catch {
            if let parsedProduct = parsedProductForServerAuthority {
                _ = await resolveServerAuthority(for: parsedProduct)
            }
            reviewRecoveryState = .failed(error.localizedDescription)
            errorMessage = "최신 상품 분류 선택지를 확인하지 못했습니다. 다시 시도해 주세요."
            return false
        }
    }

    @discardableResult
    func selectReviewRecoveryGarment(
        _ requestedGroup: VNextClassificationRecoveryGarmentGroup
    ) -> VNextClassificationRecoveryCandidateDTO? {
        guard case .choosingGarment(let contract) = reviewRecoveryState,
              let group = contract.garmentGroups.first(where: {
                  $0.garmentTypeCode == requestedGroup.garmentTypeCode
              }),
              group == requestedGroup else {
            errorMessage = "서버 상품 분류 선택지를 다시 불러와 주세요."
            return nil
        }

        if group.candidates.count == 1 {
            return group.candidates[0]
        }

        reviewRecoveryState = .choosingAxis(contract, group)
        errorMessage = nil
        return nil
    }

    func returnToReviewRecoveryGarmentSelection() {
        guard case .choosingAxis(let contract, _) = reviewRecoveryState else {
            return
        }
        reviewRecoveryState = .choosingGarment(contract)
        errorMessage = nil
    }

    @discardableResult
    func confirmReviewRecovery(
        _ candidate: VNextClassificationRecoveryCandidateDTO
    ) async -> Bool {
        let contract: VNextClassificationRecoveryContractDTO
        let permittedCandidates: [VNextClassificationRecoveryCandidateDTO]
        switch reviewRecoveryState {
        case .choosingGarment(let currentContract):
            guard let group = currentContract.garmentGroups.first(where: {
                $0.garmentTypeCode == candidate.garmentTypeCode
            }), group.candidates.count == 1 else {
                errorMessage = "상품 종류를 먼저 선택해 주세요."
                return false
            }
            contract = currentContract
            permittedCandidates = group.candidates
        case .choosingAxis(let currentContract, let group):
            contract = currentContract
            permittedCandidates = group.candidates
        case .idle, .loading, .unrecoverable, .saving, .resuming, .failed:
            errorMessage = "서버 상품 분류 선택지를 다시 불러와 주세요."
            return false
        }

        guard permittedCandidates.contains(candidate),
              let coordinator = serverAuthorityCoordinator,
              let parsedProduct = parsedProductForServerAuthority,
              let request = parsedProduct.fitMatchDatabaseResolutionRequest() else {
            errorMessage = "서버 상품 분류 선택지를 다시 불러와 주세요."
            return false
        }
        let expectedRevision: Int = {
            switch serverAuthorityState {
            case .confirmed(let authority), .reviewRequired(let authority):
                return authority.runtime.vnext?.effectiveClassification?
                    .overrideRevision ?? 0
            case .idle, .resolving, .notComparable, .unavailable:
                return 0
            }
        }()

        reviewRecoveryState = .saving
        errorMessage = nil
        do {
            _ = try await coordinator.setUserProductClassification(
                contract: contract,
                candidate: candidate,
                expectedRevision: expectedRevision
            )
            reviewRecoveryState = .resuming
            let authority = try await coordinator.resolveProductAuthority(
                request: request,
                observation: parsedProduct.fitMatchProductObservationRequest()
            )
            guard authority.status == .confirmed,
                  authority.classification.authorityStatus == "user_explicit" else {
                throw FitMatchServerAuthorityError.classificationRecoveryRejected(
                    "runtime_did_not_return_user_explicit_authority"
                )
            }
            applyServerClassification(authority.classification)
            applyServerRuntime(authority.runtime)
            serverAuthorityState = .confirmed(authority)
            databaseShadowState = .checking
            reviewRecoveryState = .idle
            errorMessage = nil
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "상품 분류를 저장하지 못했습니다. 다시 시도해 주세요."
            if let parsedProduct = parsedProductForServerAuthority {
                _ = await resolveServerAuthority(for: parsedProduct)
                if hasActiveUserExplicitClassification {
                    _ = await beginReviewRecoveryReselection()
                } else if reviewRecoveryContract == nil {
                    reviewRecoveryState = .failed(message)
                }
            } else {
                reviewRecoveryState = .failed(message)
            }
            errorMessage = message
            return false
        }
    }

    private func presentReviewRecovery(
        _ contract: VNextClassificationRecoveryContractDTO
    ) {
        guard contract.isSafelyRecoverable else {
            reviewRecoveryState = .unrecoverable(contract)
            errorMessage = "이 상품은 아직 정확하게 분류하기 어려워요. 현재는 비교할 수 없습니다."
            return
        }

        if contract.garmentGroups.count == 1,
           let group = contract.garmentGroups.first,
           group.candidates.count > 1 {
            reviewRecoveryState = .choosingAxis(contract, group)
        } else {
            reviewRecoveryState = .choosingGarment(contract)
        }
        errorMessage = nil
    }

    @discardableResult
    func clearReviewRecovery() async -> Bool {
        guard case .confirmed(let authority) = serverAuthorityState,
              authority.classification.authorityStatus == "user_explicit",
              let revision = authority.runtime.vnext?.effectiveClassification?
                .overrideRevision,
              let coordinator = serverAuthorityCoordinator,
              let parsedProduct = parsedProductForServerAuthority else {
            return false
        }
        reviewRecoveryState = .saving
        errorMessage = nil
        do {
            _ = try await coordinator.clearUserProductClassification(
                productID: authority.productID,
                expectedRevision: revision
            )
            reviewRecoveryState = .idle
            _ = await resolveServerAuthority(for: parsedProduct)
            switch serverAuthorityState {
            case .reviewRequired, .confirmed, .notComparable:
                return true
            case .idle, .resolving, .unavailable:
                return false
            }
        } catch {
            reviewRecoveryState = .idle
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "개인 분류를 해제하지 못했습니다."
            return false
        }
    }

    private var confirmedServerAuthority: FitMatchServerProductAuthority? {
        guard case .confirmed(let authority) = serverAuthorityState else { return nil }
        return authority
    }

    /// Fetches the complete DB-issued reference plan. Local Closet rows are
    /// only a projection for the UI, so a missing projection is fail-closed
    /// rather than an opportunity to choose a different representative item.
    func loadServerReferenceSelectionPlan(
        localClientItemIDs: Set<UUID>
    ) async -> FitMatchServerReferenceSelectionPlan? {
        guard let authority = confirmedServerAuthority else {
            errorMessage = "서버에서 상품 분류를 확정하지 못해 비교할 수 없습니다."
            return nil
        }
        guard authority.comparisonReadiness.isReady else {
            errorMessage = authority.comparisonReadiness.userMessage
            return nil
        }
        guard let coordinator = serverAuthorityCoordinator,
              let product = parsedProductForServerAuthority,
              let request = product.fitMatchDatabaseResolutionRequest() else {
            errorMessage = FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        }
        do {
            return try await coordinator.referenceSelectionPlan(
                targetRequest: request,
                targetObservation: product.fitMatchProductObservationRequest(),
                localClientItemIDs: localClientItemIDs
            )
        } catch let error as FitMatchServerAuthorityError {
            errorMessage = error.errorDescription
                ?? FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        } catch {
            errorMessage = FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        }
    }

    func authorizeReferenceForComparison(
        _ item: UserFit,
        allowsManualSelection: Bool
    ) async -> FitMatchServerComparisonPermit? {
        guard let readiness = serverComparisonReadiness,
              readiness.isReady else {
            errorMessage = serverComparisonReadiness?.userMessage
                ?? FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        }
        guard let coordinator = serverAuthorityCoordinator,
              let product = parsedProductForServerAuthority,
              let request = product.fitMatchDatabaseResolutionRequest(),
              let localReferenceSnapshot = item.fitMatchServerReferenceSnapshot() else {
            errorMessage = FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        }
        do {
            let usesExplicitUserAuthority = item.classificationAuthorityProvenance
                == .userExplicit
            let authorization = try await coordinator.authorizeReferenceCandidate(
                referenceClientItemID: item.id,
                localReferenceSnapshot: localReferenceSnapshot,
                targetRequest: request,
                targetObservation: product.fitMatchProductObservationRequest(),
                referenceRequest: usesExplicitUserAuthority
                    ? nil
                    : item.sourceProduct?.fitMatchDatabaseResolutionRequest(),
                referenceObservation: usesExplicitUserAuthority
                    ? nil
                    : item.sourceProduct?.fitMatchProductObservationRequest()
            )
            let allowed = authorization.decision == .automatic
                || (allowsManualSelection && authorization.decision == .manualSelection)
            guard allowed else {
                errorMessage = authorization.blockReason.userMessage
                return nil
            }
            return try await coordinator.beginAuthorizedComparison(authorization)
        } catch let error as FitMatchServerAuthorityError {
            errorMessage = error.errorDescription
                ?? FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        } catch {
            errorMessage = FitMatchComparisonBlockReason.serverUnavailable.userMessage
            return nil
        }
    }

    func analyzeRecoveryImage(url: URL) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                recoveryErrorMessage = "이미지를 불러오지 못했어요."
                return false
            }
            return await analyzeRecoveryImage(data: data)
        } catch {
            recoveryErrorMessage = "이미지를 불러오지 못했어요."
            return false
        }
    }

    func analyzeRecoveryImage(data: Data) async -> Bool {
        recoveryErrorMessage = nil
        isAnalyzingRecoveryImage = true
        defer { isAnalyzingRecoveryImage = false }
        let input = RecoveryImageAnalysisInput(
            data: data,
            category: category,
            categoryDepth2Name: productMetadata.categoryDepth2Name
        )
        let parsed = await Task.detached(priority: .userInitiated) {
            RecoveryImageAnalysisResult(
                sizes: MusinsaFallbackSizeParser().parseRecoveryImage(
                    data: input.data,
                    category: input.category,
                    categoryDepth2Name: input.categoryDepth2Name
                )
            )
        }.value.sizes
        guard !parsed.isEmpty else {
            recoveryErrorMessage = "표를 확정하지 못했어요. 값을 직접 입력해 주세요."
            return false
        }
        sizeOptions = parsed.enumerated().map {
            Self.makeSizeForm(from: $0.element, displayOrder: $0.offset, allowsStandardSizeFallback: false)
        }
        sizeTableRecoveryContext = SizeTableRecoveryContext(
            failure: .incompleteOCR,
            imageURLStrings: sizeTableRecoveryContext?.imageURLStrings ?? []
        )
        return true
    }

    @discardableResult
    func calculateRecommendation(
        userFits: [UserFit],
        brand: Brand? = nil,
        allowsGlobalFallback: Bool = false
    ) async -> RecommendationHistory? {
        errorMessage = nil
        let metricMode = FitMatchMetricComparisonMode.automatic
        metricsRecorder.record(.comparisonAttempt(mode: metricMode))

        guard !userFits.isEmpty else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .missingReference))
            errorMessage = "먼저 내 옷장에 기준 옷을 추가해 주세요."
            recommendation = nil
            return nil
        }

        guard hasServerComparisonReadyAuthority else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = serverComparisonReadiness?.userMessage
                ?? FitMatchComparisonBlockReason.serverUnavailable.userMessage
            recommendation = nil
            return nil
        }

        guard let product = makeProduct(brand: brand) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }

        guard product.classificationAuthorityProvenance?.isComparisonAuthority == true else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = "서버에서 확정된 상품만 비교할 수 있습니다."
            recommendation = nil
            return nil
        }

        guard let plan = await loadServerReferenceSelectionPlan(
            localClientItemIDs: Set(userFits.map(\.id))
        ) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .insufficientEvidence))
            recommendation = nil
            return nil
        }
        let automaticIDs = plan.automaticCandidates.map(\.clientItemID)
        let fitByID = Dictionary(uniqueKeysWithValues: userFits.map { ($0.id, $0) })
        let automaticCandidates = automaticIDs.compactMap { fitByID[$0] }
        guard automaticCandidates.count == automaticIDs.count else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .insufficientEvidence))
            errorMessage = "서버 기준 옷과 기기 옷장 정보가 동기화되지 않았습니다. 동기화한 뒤 다시 시도해 주세요."
            recommendation = nil
            return nil
        }
        guard !automaticCandidates.isEmpty else {
            // No automatic reference is not an error. The caller may present
            // only `plan.manualCandidates`, then performs a new server
            // authorization after the user's explicit choice.
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .missingReference))
            recommendation = nil
            return nil
        }

        for reference in automaticCandidates {
            guard let permit = await authorizeReferenceForComparison(
                reference,
                allowsManualSelection: false
            ) else { continue }
            guard let history = await completeVNextRecommendation(
                product: product,
                reference: reference,
                permit: permit
            ) else { continue }

            recommendation = history
            recordComparisonResult(history, mode: metricMode)
            return history
        }

        metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .insufficientEvidence))
        errorMessage = errorMessage
            ?? "서버 비교 정책 또는 실측 조건을 충족하는 기준 옷이 없습니다."
        recommendation = nil
        return nil
    }

    /// Executes only server-ordered AUTOMATIC references that the caller has
    /// already obtained from `loadServerReferenceSelectionPlan`. It never
    /// queries local `isRepresentative` state to construct that order.
    @discardableResult
    func calculateRecommendation(
        automaticReferenceCandidates: [UserFit],
        brand: Brand? = nil
    ) async -> RecommendationHistory? {
        errorMessage = nil
        let metricMode = FitMatchMetricComparisonMode.automatic
        metricsRecorder.record(.comparisonAttempt(mode: metricMode))

        guard hasServerComparisonReadyAuthority else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = serverComparisonReadiness?.userMessage
                ?? FitMatchComparisonBlockReason.serverUnavailable.userMessage
            recommendation = nil
            return nil
        }
        guard !automaticReferenceCandidates.isEmpty else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .missingReference))
            recommendation = nil
            return nil
        }
        guard let product = makeProduct(brand: brand),
              product.classificationAuthorityProvenance?.isComparisonAuthority == true else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = "서버에서 확정된 상품만 비교할 수 있습니다."
            recommendation = nil
            return nil
        }

        for reference in automaticReferenceCandidates {
            guard let permit = await authorizeReferenceForComparison(
                reference,
                allowsManualSelection: false
            ) else { continue }
            guard let history = await completeVNextRecommendation(
                product: product,
                reference: reference,
                permit: permit
            ) else { continue }

            recommendation = history
            recordComparisonResult(history, mode: metricMode)
            return history
        }

        metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .insufficientEvidence))
        errorMessage = errorMessage
            ?? "서버 비교 정책 또는 실측 조건을 충족하는 기준 옷이 없습니다."
        recommendation = nil
        return nil
    }

    @discardableResult
    func calculateTemporaryRecommendation(
        selectedReferenceItem: UserFit,
        brand: Brand? = nil
    ) async -> RecommendationHistory? {
        errorMessage = nil
        let metricMode = FitMatchMetricComparisonMode.selectedReference
        metricsRecorder.record(.comparisonAttempt(mode: metricMode))

        guard hasServerComparisonReadyAuthority else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = serverComparisonReadiness?.userMessage
                ?? FitMatchComparisonBlockReason.serverUnavailable.userMessage
            recommendation = nil
            return nil
        }

        guard let product = makeProduct(brand: brand) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }


        guard product.classificationAuthorityProvenance?.isComparisonAuthority == true,
              let permit = await authorizeReferenceForComparison(
                selectedReferenceItem,
                allowsManualSelection: true
              ) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .insufficientEvidence))
            recommendation = nil
            return nil
        }

        guard let history = await completeVNextRecommendation(
            product: product,
            reference: selectedReferenceItem,
            permit: permit
        ) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .insufficientEvidence))
            errorMessage = "측정 방식이 호환되는 실측 항목이 부족해 추천할 수 없습니다."
            recommendation = nil
            return nil
        }

        recommendation = history
        recordComparisonResult(history, mode: metricMode)
        return history
    }

    private func completeVNextRecommendation(
        product: Product,
        reference: UserFit,
        permit: FitMatchServerComparisonPermit
    ) async -> RecommendationHistory? {
        guard let serverAuthorityCoordinator else { return nil }
        do {
            let analysis = try recommendationService.analyzeVNextComparison(
                permit: permit
            )
            let completion = try await serverAuthorityCoordinator.completeAuthorizedComparison(
                permit: permit,
                analysis: analysis
            )
            guard let history = recommendationService.makeCompletedVNextHistory(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: detailCategory,
                permit: permit,
                analysis: analysis,
                completion: completion
            ) else {
                return nil
            }
            VNextComparisonSessionStore.shared.store(
                analysis,
                historyID: history.id
            )
            return history
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "서버 비교 결과를 완료하지 못했습니다. 같은 비교를 다시 시도해 주세요."
            return nil
        }
    }

    func needsDetailCategoryBasis(userFits: [UserFit]) -> Bool {
        // Reference eligibility is server authority.  In particular, a local
        // representative toggle must not divert a confirmed product away from
        // automatic reference discovery.
        false
    }

    func temporaryComparisonCandidates(userFits: [UserFit], brand: Brand? = nil) -> [UserFit] {
        guard makeProduct(brand: brand) != nil else {
            return []
        }

        return userFits.filter(\.isActiveClosetItem).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func needsFallbackDecision(userFits: [UserFit], brand: Brand? = nil) -> Bool {
        return makeProduct(brand: brand) != nil
            && userFits.filter(\.isActiveClosetItem).isEmpty
    }

    func makeBrand() -> Brand? {
        let trimmedBrand = brand.trimmed
        guard !trimmedBrand.isEmpty else {
            return nil
        }

        return Brand(name: trimmedBrand)
    }

    private func parserFailureReason(error: Error, isNetworkFailure: Bool) -> FitMatchMetricParserFailure {
        if isNetworkFailure {
            return .network
        }
        guard let parserError = error as? ProductURLParserError else {
            return .other
        }
        switch parserError {
        case .invalidURL: return .invalidURL
        case .unsupportedURL: return .unsupportedURL
        case .automaticParsingUnavailable: return .other
        }
    }

    private func recordComparisonResult(
        _ history: RecommendationHistory,
        mode: FitMatchMetricComparisonMode
    ) {
        let outcome: FitMatchMetricComparisonOutcome
        switch history.comparisonStatus {
        case .confirmed: outcome = .confirmed
        case .insufficientEvidence: outcome = .insufficientEvidence
        case .legacy: outcome = .legacy
        }
        metricsRecorder.record(
            .comparisonResult(
                mode: mode,
                outcome: outcome,
                reliability: FitMatchMetricComparisonReliability(history: history)
            )
        )
    }

    func makeProductForClosetRegistration(
        brand: Brand?,
        classificationWasUserConfirmed: Bool = false
    ) -> Product? {
        makeProduct(
            brand: brand,
            classificationWasUserConfirmed: classificationWasUserConfirmed
        )
    }

    private func makeProduct(
        brand: Brand?,
        classificationWasUserConfirmed: Bool = false
    ) -> Product? {
        let serverClassification = confirmedServerAuthority?.classification
        let localHint = ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [
                productMetadata.sourceCategoryDepth1,
                productMetadata.sourceCategoryDepth2,
                productMetadata.sourceCategoryDepth3,
                productMetadata.sourceCategoryDepth4
            ],
            sourcePath: productMetadata.sourceCategoryPath,
            productName: canonicalClassificationProductNameHint
        )
        let resolvedCategory = serverClassification?.categoryCode.map(
            ClothingCategory.fromTaxonomyCode
        ) ?? localHint?.category ?? category
        let resolvedDetailCategory = serverClassification?.detailCode.map(
            ClosetDetailCategory.fromTaxonomyCode
        ) ?? localHint?.detailCategory ?? detailCategory
        let validOptions = sizeOptions.compactMap {
            $0.makeSizeOption(
                category: resolvedCategory,
                detailCategory: resolvedDetailCategory
            )
        }
        guard !productName.trimmed.isEmpty, !validOptions.isEmpty else {
            return nil
        }

        let product = Product(
            id: confirmedServerAuthority?.productID ?? UUID(),
            name: productName.trimmed,
            brand: brand,
            category: resolvedCategory,
            productCode: productCode,
            sourceURLString: productCanonicalURLString ?? (productURL.trimmed.isEmpty ? nil : productURL.trimmed),
            imageURLString: productImageURLString,
            metadata: productMetadata,
            sourceType: sourceType,
            sourceName: resolvedSourceName,
            sizes: validOptions
        )

        if let serverClassification {
            product.category = resolvedCategory
            product.categoryCode = serverClassification.categoryCode
            product.normalizedProductTypeCode = serverClassification.detailCode
            product.garmentTypeRawValue = serverClassification.garmentTypeCode
            product.sleeveTypeRawValue = serverClassification.lengthCode
            if let exact = confirmedServerAuthority?.runtime.vnext?.product {
                let effectiveTuple = VNextRuntimeClassificationTuple(
                    product: exact,
                    effective: confirmedServerAuthority?.runtime.vnext?
                        .effectiveClassification
                )
                let garmentTypeCode = effectiveTuple.garmentTypeCode
                let categoryCode = effectiveTuple.categoryCode
                let policyCode = effectiveTuple.comparisonPolicyCode
                let sleeveLengthCode = effectiveTuple.sleeveLengthCode
                let lowerLengthCode = effectiveTuple.lowerLengthCode
                let bodyLengthCode = effectiveTuple.bodyLengthCode
                product.category = ClothingCategory.fromTaxonomyCode(categoryCode ?? "other")
                product.categoryCode = categoryCode
                product.normalizedProductTypeCode = garmentTypeCode
                product.garmentTypeRawValue = garmentTypeCode
                // These fields belong to the single server-issued effective
                // tuple. Do not retain parser or global fields when a current
                // personal authority replaces them (or intentionally omits an
                // axis).
                product.genderCodes = effectiveTuple.audienceCode
                product.sleeveTypeRawValue = sleeveLengthCode
                product.constructionTypeRawValue = effectiveTuple.productStructureCode
                product.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(
                    CanonicalComparisonProfile(
                        decision: .confirmed,
                        semanticCategoryCode: categoryCode,
                        semanticGarmentType: garmentTypeCode,
                        comparisonFamily: policyCode,
                        appComparisonFamily: policyCode,
                        lengthAxes: CanonicalLengthAxes(
                            sleeve: sleeveLengthCode ?? "not_applicable",
                            pants: lowerLengthCode ?? "not_applicable",
                            leggings: "not_applicable",
                            skirt: "not_applicable",
                            body: bodyLengthCode ?? "not_applicable"
                        ),
                        constructionType: effectiveTuple.productStructureCode,
                        eligibility: confirmedServerAuthority?.comparisonReady == true,
                        requiredMeasurements: [],
                        optionalMeasurements: [],
                        excludedMeasurements: [],
                        policyVersion: effectiveTuple.contractVersion ?? "fitmatch-vnext",
                        resolutionMethod: "fitmatch_vnext_runtime",
                        sourceIdentity: exact.inputFingerprint
                    )
                )
            }
            product.canonicalPolicyVersion = serverClassification.taxonomyPolicyVersion
                ?? serverClassification.decisionVersion
            product.markClassificationAuthority(
                serverClassification.authorityStatus == "user_explicit"
                    ? .userExplicit : .serverConfirmed,
                sourceIdentity: serverClassification.classificationID?.uuidString
                    ?? serverClassification.method
            )
            return product
        }

        // Local parsing may still populate a UI/offline hint, but it can never
        // manufacture persisted server authority for a sourced product.
        if let localHint {
            product.categoryCode = localHint.categoryCode
            product.normalizedProductTypeCode = localHint.normalizedProductTypeCode
            product.garmentType = localHint.garmentFamily
            product.sleeveType = localHint.lengthType
            product.constructionType = localHint.constructionType
        }
        let isExplicitManualEntry = sourceType == .manual
            && parsedProductForServerAuthority == nil
            && classificationWasUserConfirmed
        if isExplicitManualEntry {
            product.markClassificationAuthority(.userExplicit)
        } else {
            switch serverAuthorityState {
            case .reviewRequired:
                product.markClassificationAuthority(.serverReviewRequired)
            case .notComparable:
                product.markClassificationAuthority(.serverNotComparable)
            case .unavailable:
                product.markClassificationAuthority(.serverUnavailable)
            default:
                product.markClassificationAuthority(.localHint)
            }
        }
        return product
    }

    func apply(_ parsedProduct: ParsedProductInfo) {
        productURL = parsedProduct.sourceURL.absoluteString
        sourceType = parsedProduct.sourceType
        sourceName = parsedProduct.sourceName
        brand = parsedProduct.brandName
        productName = parsedProduct.productName
        productImageURLString = parsedProduct.imageURLString
        productPrice = parsedProduct.price
        productCanonicalURLString = parsedProduct.canonicalURLString
        productCode = parsedProduct.productID
        productMetadata = metadataWithSourceCategory(from: parsedProduct)
        classificationSafetyAudit = ParsedClosetClassification.auditExplicitContradictions(
            category: parsedProduct.category,
            detailCategory: parsedProduct.detailCategory,
            sourceDepths: [
                productMetadata.sourceCategoryDepth1,
                productMetadata.sourceCategoryDepth2,
                productMetadata.sourceCategoryDepth3,
                productMetadata.sourceCategoryDepth4
            ],
            sourcePath: productMetadata.sourceCategoryPath,
            productName: parsedProduct.productName
        )
        let canonical = ParsedClosetClassification.resolve(
            category: parsedProduct.category,
            detailCategory: parsedProduct.detailCategory,
            sourceDepths: [
                productMetadata.sourceCategoryDepth1,
                productMetadata.sourceCategoryDepth2,
                productMetadata.sourceCategoryDepth3,
                productMetadata.sourceCategoryDepth4
            ],
            sourcePath: productMetadata.sourceCategoryPath,
            productName: parsedProduct.usesStructuredCategoryAsCanonicalSource
                ? ""
                : parsedProduct.productName
        )
        category = canonical?.category ?? parsedProduct.category
        detailCategory = canonical?.detailCategory ?? parsedProduct.detailCategory
        measurementAvailability = parsedProduct.measurementAvailability
        sizeTableRecoveryContext = parsedProduct.sizeTableRecoveryContext
        parserNotice = parsedProduct.parserNotice
        productAnalysisRecoveryAction = parsedProduct.recoveryAction
        hasLoadedProductInfo = true
        #if DEBUG
        let classificationDescription = category == .other || detailCategory == .other
            ? "분류 미확정"
            : "\(category.rawValue)/\(detailCategory.rawValue)"
        FitMatchDebugLogger.event(
            screen: "상품 비교",
            action: "파싱 데이터 적용",
            state: "완료",
            details: "상품=\(productName), 브랜드=\(brand), 출처=\(sourceName), 성별=\(UserGender.productTarget(from: productMetadata.genderCodes).rawValue), 원본분류=\(productMetadata.sourceCategoryPath ?? "없음"), FitMatch분류=\(classificationDescription), 사이즈수=\(parsedProduct.sizes.count)"
        )
        #endif
        guard !parsedProduct.sizes.isEmpty else {
            sizeOptions = [ClothingSizeForm()]
            return
        }

        sizeOptions = parsedProduct.sizes.enumerated().map { index, size in
            Self.makeSizeForm(
                from: size,
                displayOrder: index,
                allowsStandardSizeFallback: parsedProduct.measurementAvailability != .actualMeasurements
            )
        }
    }

    private var canonicalClassificationProductNameHint: String {
        sourceName.localizedCaseInsensitiveContains("zara") ? "" : productName
    }

    static func makeSizeForm(
        from size: ParsedProductSize,
        displayOrder: Int,
        allowsStandardSizeFallback: Bool
    ) -> ClothingSizeForm {
        let chestCircumference = size.measurementRecords.first {
            $0.measurementCode == .chestCircumferenceGarment
                && $0.semanticStatus == .mapped
                && $0.value.isFinite
                && $0.value > 0
        }
        return ClothingSizeForm(
            sizeName: SizeTokenNormalizer.displayName(for: size.name),
            shoulder: MeasurementResolver.value(for: .shoulder, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            chest: MeasurementResolver.value(for: .chest, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            totalLength: MeasurementResolver.value(for: .totalLength, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            sleeveLength: MeasurementResolver.value(for: .sleeveLength, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            waist: MeasurementResolver.value(for: .waist, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            hip: MeasurementResolver.value(for: .hip, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            thigh: MeasurementResolver.value(for: .thigh, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            rise: MeasurementResolver.value(for: .rise, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            hem: MeasurementResolver.value(for: .hem, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            footLength: MeasurementResolver.value(for: .footLength, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            underBust: MeasurementResolver.value(for: .underBust, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            chestUsesCircumference: size.measurements.chest <= 0 && chestCircumference != nil,
            displayOrder: displayOrder,
            parsedMeasurementRecords: size.measurementRecords,
            standardBodyChestCircumferenceCm: size.standardBodyChestCircumferenceCm,
            allowsStandardSizeFallback: allowsStandardSizeFallback
        )
    }

    private func metadataWithSourceCategory(from parsedProduct: ParsedProductInfo) -> ProductMetadata {
        var metadata = parsedProduct.productMetadata
        metadata.sourceCategoryPath = parsedProduct.sourceCategoryPath ?? metadata.sourceCategoryPath ?? metadata.baseCategoryFullPath
        metadata.sourceCategoryDepth1 = parsedProduct.sourceCategoryDepth1 ?? metadata.sourceCategoryDepth1 ?? metadata.categoryDepth1Name
        metadata.sourceCategoryDepth2 = parsedProduct.sourceCategoryDepth2 ?? metadata.sourceCategoryDepth2 ?? metadata.categoryDepth2Name
        metadata.sourceCategoryDepth3 = parsedProduct.sourceCategoryDepth3 ?? metadata.sourceCategoryDepth3 ?? metadata.categoryDepth3Name
        metadata.sourceCategoryDepth4 = parsedProduct.sourceCategoryDepth4 ?? metadata.sourceCategoryDepth4 ?? metadata.categoryDepth4Name
        if metadata.baseCategoryFullPath == nil {
            metadata.baseCategoryFullPath = metadata.sourceCategoryPath
        }
        return metadata
    }

    var resolvedSourceName: String {
        switch sourceType {
        case .officialStore:
            return sourceName.trimmed.isEmpty ? "\(brand.trimmed) 공식몰" : sourceName.trimmed
        case .marketplace:
            return sourceName.trimmed
        case .manual:
            return sourceName.trimmed.isEmpty ? "직접 입력" : sourceName.trimmed
        }
    }

}

private final class RecoveryImageAnalysisInput: @unchecked Sendable {
    nonisolated let data: Data
    nonisolated let category: ClothingCategory
    nonisolated let categoryDepth2Name: String?

    nonisolated init(data: Data, category: ClothingCategory, categoryDepth2Name: String?) {
        self.data = data
        self.category = category
        self.categoryDepth2Name = categoryDepth2Name
    }
}

private final class RecoveryImageAnalysisResult: @unchecked Sendable {
    nonisolated let sizes: [ParsedProductSize]

    nonisolated init(sizes: [ParsedProductSize]) {
        self.sizes = sizes
    }
}

struct ClothingSizeForm: Identifiable, Equatable {
    var id = UUID()
    var sizeName = ""
    var shoulder = ""
    var chest = ""
    var totalLength = ""
    var sleeveLength = ""
    var waist = ""
    var hip = ""
    var thigh = ""
    var rise = ""
    var hem = ""
    var footLength = ""
    var underBust = ""
    var chestUsesCircumference = false
    var waistUsesCircumference = false
    var displayOrder = 0
    var parsedMeasurementRecords: [ParsedMeasurement] = []
    var standardBodyChestCircumferenceCm: Double? = nil
    var allowsStandardSizeFallback = false

    func makeSizeOption(category: ClothingCategory, detailCategory: ClosetDetailCategory = .other, gender: UserGender = .unisex) -> ProductSize? {
        guard !sizeName.trimmed.isEmpty else {
            return nil
        }

        let measurementKinds = category.measurementKinds(detailCategory: detailCategory, gender: gender)
        guard !measurementKinds.isEmpty else {
            return nil
        }

        let validMeasurementCount = measurementKinds.filter {
            numericValue(for: $0) > 0
        }.count
        let isStandardSizeOption = allowsStandardSizeFallback
        guard validMeasurementCount >= min(2, measurementKinds.count) || isStandardSizeOption else {
            return nil
        }

        let productSize = ProductSize(
            id: id,
            name: sizeName.trimmed,
            measurements: GarmentMeasurements(
                shoulder: numericValue(for: .shoulder),
                chest: chestUsesCircumference ? 0 : numericValue(for: .chest),
                totalLength: numericValue(for: .totalLength),
                sleeveLength: numericValue(for: .sleeveLength),
                waist: waistUsesCircumference ? 0 : numericValue(for: .waist),
                hip: numericValue(for: .hip),
                thigh: numericValue(for: .thigh),
                rise: numericValue(for: .rise),
                hem: numericValue(for: .hem),
                footLength: numericValue(for: .footLength),
                underBust: numericValue(for: .underBust)
            ),
            displayOrder: displayOrder
        )
        let sourceRecords = parsedMeasurementRecords.isEmpty
            ? manualMeasurementRecords(
                category: category,
                detailCategory: detailCategory,
                productSize: productSize
            )
            : parsedMeasurementRecords.map { $0.makeRecord(productSize: productSize) }
        let records = sourceRecords
        productSize.measurementRecords = records
        if !records.isEmpty {
            productSize.measurementSchemaVersion = 1
            productSize.measurementMigrationVersion = MeasurementLegacyBackfillService.migrationVersion
            productSize.measurementMigrationStatus = .completed
        }
        return productSize
    }

    private func manualMeasurementRecords(
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        productSize: ProductSize
    ) -> [GarmentMeasurementRecord] {
        category.measurementKinds(detailCategory: detailCategory, gender: .unisex).compactMap { kind in
            let value = numericValue(for: kind)
            guard value > 0, let code = manualMeasurementCode(for: kind, category: category) else {
                return nil
            }
            let label: String
            switch kind {
            case .chest: label = chestUsesCircumference ? "가슴둘레" : "가슴단면"
            case .waist: label = waistUsesCircumference ? "허리둘레" : "허리단면"
            default: label = kind.title
            }
            return ParsedMeasurement(
                value: value,
                measurementCode: code,
                displayKind: kind.displayKind,
                methodSource: "manual_product_size_entry",
                methodProfile: "transcribed_size_chart",
                inputSource: .transcribedSizeChart,
                mappingVersion: "manual_product_size_entry_v1",
                rawLabel: label,
                rawValueText: value.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(value))
                    : String(value),
                evidenceLevel: .officialText,
                semanticStatus: .mapped
            ).makeRecord(productSize: productSize)
        }
    }

    private func manualMeasurementCode(
        for kind: MeasurementKind,
        category: ClothingCategory
    ) -> MeasurementCode? {
        switch kind {
        case .shoulder: return .shoulderWidthSeamToSeam
        case .chest: return chestUsesCircumference ? .chestCircumferenceGarment : .chestWidthPitToPit
        case .totalLength:
            return category.serviceGroup == .bottom ? .pantsOutseamWaistToHem : .bodyLengthBackNeckToHem
        case .sleeveLength: return .sleeveShoulderSeamToCuff
        case .upperAbdomen: return .upperAbdomenWidthEdgeToEdge
        case .upperWaist: return .upperWaistWidthEdgeToEdge
        case .waist: return waistUsesCircumference ? .waistCircumferenceGarment : .waistWidthEdgeToEdge
        case .hip: return .hipWidthAtWidest
        case .thigh: return .thighWidthCrotchToOuter
        case .rise: return .riseCrotchToWaistFront
        case .hem: return .hemWidthEdgeToEdge
        case .footLength: return .footLengthHeelToToe
        case .underBust: return .underBustWidthEdgeToEdge
        }
    }

    func value(for kind: MeasurementKind) -> String {
        switch kind {
        case .shoulder: return shoulder
        case .chest: return chest
        case .totalLength: return totalLength
        case .sleeveLength: return sleeveLength
        case .upperAbdomen, .upperWaist: return ""
        case .waist: return waist
        case .hip: return hip
        case .thigh: return thigh
        case .rise: return rise
        case .hem: return hem
        case .footLength: return footLength
        case .underBust: return underBust
        }
    }

    private func numericValue(for kind: MeasurementKind) -> Double {
        Double(value(for: kind).trimmed) ?? 0
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    var formText: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(self)
    }

    var extractedFormText: String {
        self > 0 ? formText : ""
    }
}
