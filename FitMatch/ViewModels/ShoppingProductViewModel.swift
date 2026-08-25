import Foundation
import Combine

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
    @Published private(set) var classificationSafetyAudit: ParsedClosetClassificationSafetyAudit = .safe

    private let recommendationService: RecommendationService
    private let parserService: ProductURLParserService
    private let metricsRecorder: FitMatchMetricsRecording
    private let databaseProductResolver: any FitMatchProductResolving
    private var activeLoadID: UUID?
    private var databaseResolutionTask: Task<Void, Never>?
    private var databaseResolutionID: UUID?

    init(
        initialURL: String? = nil,
        recommendationService: RecommendationService? = nil,
        parserService: ProductURLParserService? = nil,
        metricsRecorder: FitMatchMetricsRecording? = nil,
        databaseProductResolver: (any FitMatchProductResolving)? = nil
    ) {
        productURL = initialURL ?? ""
        self.recommendationService = recommendationService ?? RecommendationService()
        self.parserService = parserService ?? ProductURLParserService()
        self.metricsRecorder = metricsRecorder ?? FitMatchMetricsRecorder.shared
        self.databaseProductResolver = databaseProductResolver
            ?? FitMatchSupabaseProductResolver.shared
    }

    // This view model owns only Sendable task state at teardown. Keeping the
    // destructor nonisolated avoids the back-deployed MainActor destructor
    // thunk that crashes when a fully populated imported size chart is
    // released on Intel simulators. It also prevents a detached DB shadow
    // lookup from outliving the screen that requested it.
    nonisolated deinit {
        databaseResolutionTask?.cancel()
    }

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
        databaseResolutionTask?.cancel()
        databaseResolutionID = nil
        databaseShadowState = .idle
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
            startDatabaseShadowResolution(for: parsedProduct)
            metricsRecorder.record(
                .parserSuccess(
                    provider: metricProvider,
                    category: FitMatchMetricMajorCategory(category: category),
                    detail: detailCategory == .other ? .catchAll : .specific,
                    measurement: FitMatchMetricMeasurementAvailability(measurementAvailability)
                )
            )
            return true
        } catch let partialError as ProductURLParserPartialError {
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            apply(partialError.productInfo)
            startDatabaseShadowResolution(for: partialError.productInfo)
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

    func cancelProductLoading() {
        activeLoadID = nil
        databaseResolutionTask?.cancel()
        databaseResolutionID = nil
        databaseShadowState = .idle
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
            startDatabaseShadowResolution(for: parsedProduct)
            return true
        } catch let partialError as ProductURLParserPartialError {
            guard !Task.isCancelled, activeLoadID == loadID else { return false }
            apply(partialError.productInfo)
            category = selectedCategory
            detailCategory = selectedDetailCategory
            productAnalysisRecoveryAction = partialError.productInfo.recoveryAction
                ?? .enterMeasurementsManually
            startDatabaseShadowResolution(for: partialError.productInfo)
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

    private func startDatabaseShadowResolution(for product: ParsedProductInfo) {
        guard let request = product.fitMatchDatabaseResolutionRequest() else {
            databaseShadowState = .skipped
            return
        }
        let resolutionID = UUID()
        let local = product.fitMatchLocalClassificationSnapshot()
        databaseResolutionID = resolutionID
        databaseShadowState = .checking
        databaseResolutionTask = Task { [weak self, databaseProductResolver] in
            do {
                if let submitter = databaseProductResolver as? any FitMatchProductObservationSubmitting,
                   let observation = product.fitMatchProductObservationRequest() {
                    do {
                        _ = try await submitter.submitProductObservation(observation)
                    } catch {
                        #if DEBUG
                        FitMatchDebugLogger.event(
                            screen: "상품 분석",
                            action: "상품 원본 관측 저장",
                            state: "저장 실패",
                            details: "오류=\(error.localizedDescription), 로컬 분류와 DB 조회는 계속 진행"
                        )
                        #endif
                    }
                }
                let response = try await databaseProductResolver.resolve(request)
                guard !Task.isCancelled,
                      let self,
                      self.databaseResolutionID == resolutionID else { return }
                if response.catalogState != "current"
                    || response.classification.status != "confirmed" {
                    self.databaseShadowState = .reviewRequired(response)
                } else if local.matches(response.classification) {
                    self.databaseShadowState = .matched(response)
                } else {
                    self.databaseShadowState = .mismatch(response, local)
                }
                #if DEBUG
                self.logDatabaseShadowResult(response: response, local: local)
                #endif
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.databaseResolutionID == resolutionID else { return }
                self.databaseShadowState = .unavailable
                #if DEBUG
                FitMatchDebugLogger.event(
                    screen: "상품 분석",
                    action: "DB shadow 분류",
                    state: "연결 실패",
                    details: "오류=\(error.localizedDescription), 로컬 분류 유지"
                )
                #endif
            }
        }
    }

    #if DEBUG
    private func logDatabaseShadowResult(
        response: FitMatchProductResolutionResponse,
        local: FitMatchLocalClassificationSnapshot
    ) {
        let state: String
        switch databaseShadowState {
        case .matched: state = "일치"
        case .mismatch: state = "불일치"
        case .reviewRequired: state = "검토 필요"
        default: state = "기타"
        }
        let databaseCodes = [
            response.classification.categoryCode,
            response.classification.detailCode,
            response.classification.familyCode,
            response.classification.lengthCode
        ].map { $0 ?? "nil" }.joined(separator: "/")
        let localCodes = [
            local.categoryCode,
            local.detailCode,
            local.familyCode,
            local.lengthCode
        ].map { $0 ?? "nil" }.joined(separator: "/")
        FitMatchDebugLogger.event(
            screen: "상품 분석",
            action: "DB shadow 분류",
            state: state,
            details: "상품=\(response.productID?.uuidString ?? "미등록"), catalog=\(response.catalogState), DB=\(databaseCodes), local=\(localCodes)"
        )
    }
    #endif

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
    ) -> RecommendationHistory? {
        errorMessage = nil
        let metricMode = FitMatchMetricComparisonMode.automatic
        metricsRecorder.record(.comparisonAttempt(mode: metricMode))

        guard !userFits.isEmpty else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .missingReference))
            errorMessage = "먼저 내 옷장에 기준 옷을 추가해 주세요."
            recommendation = nil
            return nil
        }

        guard let product = makeProduct(brand: brand) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }

        guard let history = recommendationService.recommend(
            product: product,
            userFits: userFits,
            productDetailCategory: detailCategory,
            allowsGlobalFallback: allowsGlobalFallback
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

    @discardableResult
    func calculateTemporaryRecommendation(
        selectedReferenceItem: UserFit,
        brand: Brand? = nil
    ) -> RecommendationHistory? {
        errorMessage = nil
        let metricMode = FitMatchMetricComparisonMode.selectedReference
        metricsRecorder.record(.comparisonAttempt(mode: metricMode))

        guard let product = makeProduct(brand: brand) else {
            metricsRecorder.record(.comparisonBlocked(mode: metricMode, reason: .invalidProduct))
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }

        guard let history = recommendationService.recommend(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            productDetailCategory: detailCategory
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

    func needsDetailCategoryBasis(userFits: [UserFit]) -> Bool {
        guard hasLoadedProductInfo else {
            return false
        }

        guard !userFits.isEmpty else {
            return true
        }

        guard let product = makeProduct(brand: makeBrand()) else {
            return false
        }

        return !recommendationService.hasRelevantClosetItem(
            product: product,
            productDetailCategory: detailCategory,
            userFits: userFits
        )
    }

    func temporaryComparisonCandidates(userFits: [UserFit], brand: Brand? = nil) -> [UserFit] {
        guard let product = makeProduct(brand: brand) else {
            return []
        }

        return recommendationService.temporaryComparisonCandidates(
            product: product,
            productDetailCategory: detailCategory,
            userFits: userFits
        )
    }

    func needsFallbackDecision(userFits: [UserFit], brand: Brand? = nil) -> Bool {
        guard let product = makeProduct(brand: brand), !userFits.isEmpty else {
            return false
        }

        return !recommendationService.hasRelevantClosetItem(
            product: product,
            productDetailCategory: detailCategory,
            userFits: userFits
        )
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
        // Resolve the canonical garment before converting parsed rows into
        // ProductSize. Provider buckets such as UNIQLO Innerwear/AIRism can
        // have a generic provider detail even though the source path and name
        // safely identify a supported garment. Waiting until after size
        // conversion used to discard those rows because `.other` exposes no
        // comparable measurement schema.
        let canonical = ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [productMetadata.sourceCategoryDepth1, productMetadata.sourceCategoryDepth2,
                           productMetadata.sourceCategoryDepth3, productMetadata.sourceCategoryDepth4],
            sourcePath: productMetadata.sourceCategoryPath,
            productName: canonicalClassificationProductNameHint
        )
        let resolvedCategory = canonical?.category ?? category
        let resolvedDetailCategory = canonical?.detailCategory ?? detailCategory
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
        if let canonical {
            product.categoryCode = canonical.categoryCode
            product.normalizedProductTypeCode = canonical.normalizedProductTypeCode
            product.garmentType = canonical.garmentFamily
            product.sleeveType = canonical.lengthType
            product.constructionType = canonical.constructionType
        }
        let canonicalTarget = productMetadata.genderCodes.first.map { code -> String in
            let value = code.uppercased()
            if value.contains("WOM") || value.contains("FEMALE") { return "WOMEN" }
            if value.contains("MEN") || value.contains("MALE") { return "MEN" }
            if value.contains("BABY") { return "BABY" }
            if value.contains("KID") { return "KIDS" }
            return value
        }
        let canonicalProfile = CanonicalComparisonProfileResolver().resolve(
            source: resolvedSourceName,
            externalCategoryID: productMetadata.mostSpecificExternalCategoryID,
            target: canonicalTarget,
            sourceCategoryPath: productMetadata.sourceCategoryPath ?? productMetadata.baseCategoryFullPath
        )
        CanonicalComparisonProfileResolver().apply(canonicalProfile, to: product)
        if classificationSafetyAudit.requiresReview,
           !classificationWasUserConfirmed {
            product.canonicalEligibility = false
            product.canonicalResolutionMethod = ParsedClosetClassificationSafetyAudit.conflictResolutionMethod
            product.canonicalPolicyVersion = product.canonicalPolicyVersion
                ?? ParsedClosetClassificationSafetyAudit.policyVersion
            #if DEBUG
            let dimensions = classificationSafetyAudit.conflicts
                .map(\.dimension.rawValue)
                .joined(separator: ",")
            FitMatchDebugLogger.event(
                screen: "상품 분석",
                action: "분류 충돌 안전 차단",
                state: "사용자 확인 필요",
                details: "상품=\(product.name), 충돌축=\(dimensions)"
            )
            #endif
        }
        _ = ComparisonProfileMatcher().profile(for: product, detailCategory: detailCategory)
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
