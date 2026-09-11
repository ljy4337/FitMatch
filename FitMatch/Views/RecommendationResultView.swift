import SwiftUI
import SwiftData

struct RecommendationResultView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    @Query private var closetItems: [UserFit]
    let result: RecommendationHistory
    private let onShowComparisonList: (() -> Void)?
    private let onShowOtherClosetComparison: (() -> Void)?
    private let onReselectClassification: (() -> Void)?
    private let onClearClassification: (() -> Void)?
    private let resultCalculationSnapshot: RecommendationCalculationSnapshot?
    private let resultComparedMeasurementUsages: [MeasurementComparisonUsage]
    private let resultMeasurementExclusions: [MeasurementComparisonExclusion]
    private let resultProductSizes: [ProductSize]
    private let diagnosticsStartedAt: TimeInterval
    @State private var isShowingReliabilityInfo = false
    @State private var isShowingMeasurementInfo = false
    @State private var isShowingAlternativeSizeComparison = false
    @State private var isShowingOtherClosetComparison = false
    @State private var selectedAlternativeSizeID: UUID?
    @State private var temporarySizeAnalysis: TemporarySizeAnalysis?
    @State private var temporaryAnalysisCache: [TemporarySizeAnalysisCacheKey: TemporarySizeAnalysis] = [:]
    /// This is populated directly from the completed vNext batch.  It is
    /// deliberately separate from `ProductSize.id`, which can be a historical
    /// SwiftData projection outside a current server-runtime context.
    @State private var exactProductSizeIDByTemporaryAnalysisKey:
        [TemporarySizeAnalysisCacheKey: UUID] = [:]
    @State private var temporaryDisplayedProductSizeID: UUID?
    @State private var activeAlternativeAnalysisKeys: [UUID: TemporarySizeAnalysisCacheKey] = [:]
    @State private var unavailableAlternativeSizeKeys: Set<TemporarySizeAnalysisCacheKey> = []
    @State private var isAnalyzingAlternativeSize = false
    @State private var isPreparingAlternativeSizes = false
    @State private var alternativePreparationGeneration = UUID()
    @State private var alternativeSizeErrorMessage: String?
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    @State private var isShowingClosetSavedToast = false
    @State private var closetRegistrationPreparation:
        FitMatchResultClosetRegistrationPreparation?
    @State private var isPreparingClosetRegistration = false
    @State private var closetRegistrationPreparationErrorMessage: String?
    private let favoriteStore = FavoriteProductStore()

    init(
        result: RecommendationHistory,
        onShowComparisonList: (() -> Void)? = nil,
        onShowOtherClosetComparison: (() -> Void)? = nil,
        onReselectClassification: (() -> Void)? = nil,
        onClearClassification: (() -> Void)? = nil
    ) {
        let comparisonData = result.comparisonData
        self.diagnosticsStartedAt = DetailPerformanceDiagnostics.now()
        self.result = result
        self.onShowComparisonList = onShowComparisonList
        self.onShowOtherClosetComparison = onShowOtherClosetComparison
        self.onReselectClassification = onReselectClassification
        self.onClearClassification = onClearClassification
        self.resultCalculationSnapshot = comparisonData.calculationSnapshot
        self.resultComparedMeasurementUsages = comparisonData.comparedMeasurementUsages
        self.resultMeasurementExclusions = comparisonData.measurementExclusions
        self.resultProductSizes = result.product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private var currentResult: RecommendationHistory {
        result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    reportProductCard
                        .id("resultTop")
                    reportRecommendationCard
                    if currentResult.comparisonMode != .actualMeasurements {
                        standardSizeFallbackCard
                    }
                    reportReferenceCard
                    reportMeasurementCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .frame(maxWidth: .infinity)
            }
            .diagnosesScrollPerformance(screen: "recommendation_result")
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .background(Color(.systemBackground))
            .navigationTitle(onShowComparisonList == nil ? "비교 결과" : "개별 비교 결과")
            .toolbar {
                if let onShowComparisonList {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onShowComparisonList) {
                            Label("비교 목록", systemImage: "chevron.left")
                        }
                        .font(.subheadline.weight(.bold))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                resultBottomActionBar
            }
            .sheet(item: $closetRegistrationPreparation) { preparation in
                AddComparedProductToClosetSheet(
                    product: preparation.product,
                    productDetailCategory: preparation.productDetailCategory,
                    recommendedSize: preparation.preferredSize,
                    isParsedProductReadOnly: preparation.serverRegistrationContext != nil,
                    serverRegistrationContext: preparation.serverRegistrationContext,
                    startsAtRegistrationConfirmation: true,
                    requiresExplicitSizeSelection: preparation.requiresExplicitSizeSelection,
                    initialSizeSelectionMessage: preparation.initialSizeSelectionMessage
                ) { _ in
                    showClosetSavedToast()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .top) {
                if isShowingClosetSavedToast {
                    FitMatchSuccessToast(message: "보유한 옷으로 등록했어요.")
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $isShowingReliabilityInfo) {
                reliabilityInfoSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingMeasurementInfo) {
                measurementInfoSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingAlternativeSizeComparison) {
                alternativeSizeComparisonSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingOtherClosetComparison) {
                NavigationStack {
                    CompareFlowSheet(initialHistoricalProduct: currentResult.product)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert(
                "옷장 등록을 준비할 수 없어요",
                isPresented: Binding(
                    get: { closetRegistrationPreparationErrorMessage != nil },
                    set: { if !$0 { closetRegistrationPreparationErrorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(closetRegistrationPreparationErrorMessage ?? "")
            }
            .onAppear {
                DetailPerformanceDiagnostics.logHistoryResultNavigation(event: "result_on_appear")
                logInitialPerformance()
                #if DEBUG
                print("[화면: 비교 결과][동작: 결과 화면 진입][상태: 성공] 상품=\(currentResult.product.name), 추천사이즈=\(currentResult.recommendedSize.name), 선택한옷=\(currentResult.userFit.displayName)")
                #endif
                tabBarVisibilityController.hide(reason: .navigationDetail, source: "recommendation result")
            }
            .onDisappear {
                #if DEBUG
                print("[화면: 비교 결과][동작: 결과 화면 종료][상태: 완료]")
                #endif
                tabBarVisibilityController.release(reason: .navigationDetail, source: "recommendation result disappear")
            }
        }
    }

    private var reportProductCard: some View {
        CardView(radius: 20, padding: 12, shadowRadius: 10) {
            HStack(alignment: .top, spacing: 14) {
                reportProductImage
                VStack(alignment: .leading, spacing: 8) {
                    reportProductText
                    Spacer(minLength: 0)
                    Button(action: openShoppingMall) {
                        Label("쇼핑몰에서 보기", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                    .disabled(currentResult.product.sourceURLString == nil)
                    .opacity(currentResult.product.sourceURLString == nil ? 0.45 : 1)
                }
            }
        }
    }

    private var reportProductImage: some View {
        ProductThumbnailView(
            imageURLString: currentResult.productImageURLStringForDisplay,
            category: currentResult.product.category,
            width: 96,
            height: 112,
            cornerRadius: 16,
            diagnosticContext: "recommendation_result_product"
        )
        .overlay(alignment: .topTrailing) {
            Button {
                _ = favoriteStore.toggle(currentResult.product.sourceURLString)
                favoriteURLs = favoriteStore.favoriteURLs()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isFavorite ? .red : .primary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(currentResult.product.sourceURLString == nil)
            .accessibilityLabel(isFavorite ? "관심 해제" : "관심 등록")
            .padding(7)
        }
    }

    private var reportProductText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(currentResult.productBrandNameForDisplay)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(currentResult.productNameForDisplay)
                .font(.title3.weight(.black))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reportRecommendationCard: some View {
        let measurements = reportMeasurementPresentations
        let reliability = comparisonReliability

        return CardView(radius: 20, padding: 12, shadowRadius: 10) {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    let dividerWidth: CGFloat = 1
                    let availableWidth = geometry.size.width - (dividerWidth * 2)
                    let primaryMetricWidth = availableWidth * 0.30
                    let reliabilityWidth = availableWidth * 0.40

                    HStack(alignment: .top, spacing: 0) {
                        CenteredMetricColumn(
                            title: temporarySizeAnalysis == nil ? "추천 사이즈" : "비교 사이즈",
                            value: temporarySizeAnalysis?.productSize.name.displaySizeName ?? recommendedSizeName
                        ) {
                            Button {
                                presentAlternativeSizeComparison()
                            } label: {
                                Label("다른 사이즈 비교", systemImage: "arrow.left.arrow.right")
                                    .labelStyle(.titleAndIcon)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background(
                                        Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(availableProductSizes.count < 2)
                            .padding(.horizontal, 6)
                            .accessibilityHint("상품의 다른 사이즈를 임시로 비교합니다.")
                        }
                        .frame(width: primaryMetricWidth, height: 132)
                        Divider().frame(width: dividerWidth, height: 132)
                        CenteredMetricColumn(
                            title: "사이즈 유사도",
                            value: "\(displayedRecommendationScore)%"
                        ) {
                            Text(fitMatchDescription)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(fitMatchColor(for: displayedRecommendationScore))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    fitMatchColor(for: displayedRecommendationScore).opacity(0.1),
                                    in: Capsule()
                                )
                        }
                        .frame(width: primaryMetricWidth, height: 132)
                        Divider().frame(width: dividerWidth, height: 132)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text("신뢰도")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Button { isShowingReliabilityInfo = true } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("신뢰도 산정 기준")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 18)
                            Text(reliability.stars)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.orange.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 28)
                            Text(reliability.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 18)
                            Divider()
                            HStack(spacing: 3) {
                                Text("\(measurements.count)개 실측항목 표시")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .allowsTightening(true)
                                Button { isShowingMeasurementInfo = true } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("비교 실측 항목")
                            }
                            HStack(spacing: measurements.count > 4 ? 2 : 5) {
                                ForEach(measurements) { measurement in
                                    VStack(spacing: 2) {
                                        reportMeasurementIcon(for: measurement.kind)
                                        Text(reportShortTitle(for: measurement.kind))
                                            .font(.system(size: 8, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.leading, 10)
                        .frame(width: reliabilityWidth, alignment: .leading)
                    }
                }
                .frame(height: 132)

                if let temporarySizeAnalysis {
                    Text("\(temporarySizeAnalysis.productSize.name.displaySizeName) 사이즈를 임시로 비교한 결과예요.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var reportMeasurementCard: some View {
        let measurements = reportMeasurementPresentations
        let supplementalKinds = Set(
            measurements.filter(\.isSupplemental).map(\.kind)
        )
        let measurementExclusions = displayedMeasurementExclusions.filter {
            !supplementalKinds.contains($0.kind)
        }

        return CardView(radius: 20, padding: 12, shadowRadius: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(
                        title: currentResult.comparisonMode == .standardSizeFallback ? "기준표 비교 결과" : "실측 비교 결과",
                        subtitle: nil
                    )
                    Spacer()
                    if currentResult.comparisonMode != .standardSizeFallback {
                        Text("(단위: cm)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }

                if currentResult.comparisonMode == .standardSizeFallback {
                    InfoRow(title: "가슴", value: displayedTrueToSizeRecommendation)
                } else if measurements.isEmpty {
                    ContentUnavailableView(
                        "비교 가능한 항목이 없어요",
                        systemImage: "ruler",
                        description: Text("측정값이나 측정 기준을 확인해 주세요.")
                    )
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "ruler")
                            Text(displayedComparisonBasisTitle)
                            if displayedVerifiedConversionCount > 0 {
                                Text("환산 \(displayedVerifiedConversionCount)개")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(measurements) { measurement in
                            ReportMeasurementRow(
                                kind: measurement.kind,
                                title: measurement.title,
                                productValue: measurement.productValue,
                                referenceValue: measurement.referenceValue,
                                difference: measurement.difference,
                                inputMode: measurement.inputMode,
                                isSupplemental: measurement.isSupplemental
                            )
                        }
                        if measurements.contains(where: \.isSupplemental) {
                            Text("같은 쇼핑몰의 동일한 측정 기준 항목은 참고값으로 함께 표시하며, 추천 점수에는 반영하지 않습니다.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !measurementExclusions.isEmpty {
                    Divider().padding(.vertical, 3)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(measurementExclusions, id: \.kind) { exclusion in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(exclusion.kind.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(exclusion.reason.badgeTitle)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                                Text(exclusion.reason.userMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let detail = exclusion.definitionDetail {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var reportReferenceCard: some View {
        CardView(radius: 20, padding: 12, shadowRadius: 10) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "선택한 내 옷")
                HStack(spacing: 14) {
                    ProductThumbnailView(
                        imageURLString: referenceImageURLStringForDisplay,
                        category: currentResult.userFit.category,
                        width: 48,
                        height: 54,
                        cornerRadius: 12,
                        diagnosticContext: "recommendation_result_reference"
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentResult.userFit.brandName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(currentResult.userFit.productName)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("옵션 \(currentResult.userFit.sizeName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        if let onShowOtherClosetComparison {
                            onShowOtherClosetComparison()
                        } else {
                            isShowingOtherClosetComparison = true
                        }
                    } label: {
                        Text("다른 옷과 비교")
                    }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                }
            }
        }
    }

    private var reportMetadataCard: some View {
        CardView(radius: 20, padding: 12, shadowRadius: 10) {
            HStack(spacing: 16) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("비교 일자").font(.caption).foregroundStyle(.secondary)
                        Text(currentResult.createdAt.formatted(date: .numeric, time: .omitted)).font(.subheadline.weight(.bold))
                    }
                } icon: { Image(systemName: "calendar") }
                Spacer()
                Divider()
                Spacer()
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("비교 항목 수").font(.caption).foregroundStyle(.secondary)
                        Text("\(comparedMeasurementKinds.count)개 항목").font(.subheadline.weight(.bold))
                    }
                } icon: { Image(systemName: "ruler") }
            }
        }
    }

    private var reliabilityInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("사이즈 유사도는 선택한 상품 사이즈와 선택한 내 옷의 실측이 얼마나 비슷한지 나타냅니다.")
                if currentResult.serverApprovedVNextReliability != nil {
                    Text("이 결과의 신뢰도는 서버가 승인한 비교 근거 수와 coverage를 사용해 엔진이 계산한 값입니다.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("추천 신뢰도는 비교에 사용한 실측 항목 수, 측정 방식의 호환 여부, 누락·제외된 항목을 바탕으로 결과를 얼마나 참고할 수 있는지 보여줍니다.")
                        .foregroundStyle(.secondary)
                    if currentResult.comparisonMethod.contains("확장 비교") {
                        Text("서로 다른 종류의 유사한 옷을 비교한 결과라 구조 차이를 반영해 추천 신뢰도를 한 단계 낮췄어요.")
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                InfoRow(title: "현재 신뢰도", value: "\(comparisonReliability.stars) \(comparisonReliability.title)")
                Spacer()
            }
            .font(.subheadline)
            .padding(20)
            .navigationTitle("신뢰도 산정 기준")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var alternativeSizeComparisonSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(availableProductSizes) { size in
                        let analysis = cachedAnalysis(for: size)
                        let score = alternativeRecommendationScore(
                            for: size,
                            analysis: analysis
                        )
                        AlternativeSizeResultCard(
                            sizeName: size.name.displaySizeName,
                            isRecommended: size.id == currentResult.recommendedSize.id,
                            isSelected: size.id == selectedAlternativeSizeID,
                            score: score,
                            fitDescription: score.map(fitMatchDescription(for:)),
                            fitColor: score.map(fitMatchColor(for:)),
                            measurements: alternativeMeasurementSummaries(for: analysis)
                        ) {
                            selectedAlternativeSizeID = size.id
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 88)
            }
            .navigationTitle("다른 사이즈 비교")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: analyzeSelectedAlternativeSize) {
                    HStack(spacing: 8) {
                        if isAnalyzingAlternativeSize {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(alternativeAnalysisButtonTitle)
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(alternativeAnalysisHasValidSelection ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        alternativeAnalysisHasValidSelection ? Color.black : Color.secondary.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!alternativeAnalysisIsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .alert(
                "분석할 수 없어요",
                isPresented: Binding(
                    get: { alternativeSizeErrorMessage != nil },
                    set: { if !$0 { alternativeSizeErrorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(alternativeSizeErrorMessage ?? "")
            }
        }
    }

    private var measurementInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("추천 계산에 사용하거나 제외한 실측 항목입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(v1MeasurementKinds, id: \.id) { kind in
                            ComparisonCoverageRow(
                                title: kind.title,
                                isCompared: reportMeasurementPresentations.contains {
                                    $0.kind == kind
                                },
                                detail: comparisonCoverageDetail(for: kind)
                            )
                        }
                    }

                    calculationSnapshotSections
                }
                .font(.subheadline)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("실측 비교 항목")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var availableProductSizes: [ProductSize] {
        guard let batch = VNextComparisonSessionStore.shared.analysis(
            for: currentResult.id
        ) else { return [] }
        let authorized = Set(batch.authorizedCandidateProductSizeIDs.flatMap { sizeID in
            [
                sizeID,
                VNextHistoryProjectionIdentity.productSizeID(
                    comparisonID: currentResult.id,
                    productSizeID: sizeID
                )
            ]
        })
        return resultProductSizes.filter { authorized.contains($0.id) }
    }

    private var displayedProductSize: ProductSize {
        temporarySizeAnalysis?.productSize ?? currentResult.recommendedSize
    }

    private var referenceImageURLStringForDisplay: String? {
        if let snapshot = currentResult.referenceImageURLStringForDisplay {
            return snapshot
        }
        return closetItems.first { item in
            item.isActiveClosetItem
                && currentResult.referencesClosetItem(clientItemID: item.id)
        }?.imageURLStringForDisplay
    }

    private var activeReferenceItemForDisplay: UserFit? {
        closetItems.first { item in
            item.isActiveClosetItem
                && currentResult.referencesClosetItem(clientItemID: item.id)
        }
    }

    private func serverProductSizeID(
        for presentationSize: ProductSize,
        in batch: VNextComparisonBatchAnalysis
    ) -> UUID? {
        batch.authorizedCandidateProductSizeIDs.first { sizeID in
            sizeID == presentationSize.id
                || VNextHistoryProjectionIdentity.productSizeID(
                    comparisonID: currentResult.id,
                    productSizeID: sizeID
                ) == presentationSize.id
        }
    }

    /// The Result's visible size is a completed batch identity, not the
    /// rendered label.  A historical Result without that retained batch has no
    /// safe preferred identity and therefore intentionally returns nil.
    private var displayedServerProductSizeID: UUID? {
        if temporarySizeAnalysis != nil {
            return temporaryDisplayedProductSizeID
        }
        return VNextComparisonSessionStore.shared.analysis(
            for: currentResult.id
        )?.recommended.productSizeID
    }

    private func fitMatchDescription(for score: Int) -> String {
        switch score {
        case 90...: return "거의 완벽한 핏"
        case 80..<90: return "매우 잘 맞는 편"
        case 70..<80: return "잘 맞는 편"
        case 60..<70: return "약간의 차이가 있어요"
        case 50..<60: return "핏 차이를 확인해 보세요"
        case 40..<50: return "핏 차이가 큰 편이에요"
        default: return "추천하기 어려워요"
        }
    }

    private func fitMatchColor(for score: Int) -> Color {
        switch score {
        case 90...: return .green
        case 80..<90: return .mint
        case 70..<80: return .teal
        case 60..<70: return .orange
        case 50..<60: return .yellow
        case 40..<50: return .pink
        default: return .red
        }
    }

    private func alternativeMeasurementSummaries(
        for analysis: TemporarySizeAnalysis?
    ) -> [AlternativeSizeMeasurementSummary] {
        let kinds = currentResult.product.category.alternativeSizeSummaryKinds(
            detailCategory: currentResult.productDetailCategory,
            gender: currentResult.product.productTargetGender
        )
        return kinds.map { kind in
            guard let item = analysis?.comparisonResult.comparedItems.first(where: { $0.kind == kind }) else {
                return AlternativeSizeMeasurementSummary(
                    title: reportShortTitle(for: kind),
                    message: "비교 정보 없음",
                    status: .unavailable
                )
            }
            let status: AlternativeSizeMeasurementStatus
            switch item.absoluteDifference {
            case ...1: status = .close
            case ...4: status = .caution
            default: status = .negative
            }
            return AlternativeSizeMeasurementSummary(
                title: reportShortTitle(for: kind),
                message: compactAlternativeSizeMessage(
                    for: kind,
                    difference: item.signedDifference
                ),
                status: status
            )
        }
    }

    private func compactAlternativeSizeMessage(
        for kind: MeasurementKind,
        difference: Double
    ) -> String {
        let absoluteDifference = abs(difference)
        if absoluteDifference == 0 { return "차이 없음" }
        if absoluteDifference <= 1 { return "거의 비슷해요" }

        let isLength = kind == .totalLength
        if absoluteDifference <= 2 {
            if isLength { return difference > 0 ? "조금 길어요" : "조금 짧아요" }
            return difference > 0 ? "조금 여유로워요" : "조금 타이트해요"
        }
        if absoluteDifference <= 4 {
            if isLength { return difference > 0 ? "긴 편이에요" : "짧은 편이에요" }
            return difference > 0 ? "여유가 있어요" : "타이트한 편이에요"
        }
        if isLength { return difference > 0 ? "많이 길어요" : "많이 짧아요" }
        return difference > 0 ? "많이 커요" : "많이 작아요"
    }

    private var displayedRecommendationScore: Int {
        temporarySizeAnalysis?.recommendationScore ?? currentResult.recommendationScore
    }

    private var displayedTrueToSizeRecommendation: String {
        temporarySizeAnalysis?.comparisonSummary ?? currentResult.trueToSizeRecommendation
    }

    private var displayedMeasurementDifferences: GarmentMeasurements {
        temporarySizeAnalysis?.comparisonResult.signedDifferences ?? currentResult.measurementDifferences
    }

    private var displayedMeasurementUsages: [MeasurementComparisonUsage] {
        temporarySizeAnalysis?.comparisonResult.usages ?? persistedMeasurementUsages
    }

    private var displayedMeasurementExclusions: [MeasurementComparisonExclusion] {
        temporarySizeAnalysis?.comparisonResult.exclusions ?? persistedMeasurementExclusions
    }

    private var displayedCalculationSnapshot: RecommendationCalculationSnapshot? {
        temporarySizeAnalysis?.calculationSnapshot ?? persistedCalculationSnapshot
    }

    private var persistedMeasurementUsages: [MeasurementComparisonUsage] {
        resultComparedMeasurementUsages
    }

    private var persistedMeasurementExclusions: [MeasurementComparisonExclusion] {
        resultMeasurementExclusions
    }

    private var persistedCalculationSnapshot: RecommendationCalculationSnapshot? {
        resultCalculationSnapshot
    }

    private func displayedMeasurementValues(
        for kind: MeasurementKind
    ) -> (product: Double, reference: Double) {
        if let used = displayedCalculationSnapshot?.usedMeasurements.first(where: { $0.kind == kind }) {
            return (used.productValue, used.referenceValue)
        }
        return (
            displayedProductSize.measurements.value(for: kind),
            currentResult.userFit.measurements.value(for: kind)
        )
    }

    private var reportMeasurementPresentations: [ReportMeasurementPresentation] {
        var result = comparedMeasurementKinds.map { kind in
            let values = displayedMeasurementValues(for: kind)
            let usage = displayedMeasurementUsages.first { $0.kind == kind }
            return ReportMeasurementPresentation(
                kind: kind,
                title: reportMeasurementTitle(for: kind),
                productValue: values.product,
                referenceValue: values.reference,
                difference: displayedMeasurementDifferences.value(for: kind),
                inputMode: usage?.inputMode,
                isSupplemental: false
            )
        }
        result.append(contentsOf: supplementalMeasurementItems.map { item in
            ReportMeasurementPresentation(
                kind: item.kind,
                title: item.displayTitle ?? item.kind.title,
                productValue: item.productValue,
                referenceValue: item.referenceValue,
                difference: item.signedDifference,
                inputMode: item.inputMode,
                isSupplemental: true
            )
        })
        return result
    }

    private var displayedComparisonBasisTitle: String {
        let modes = Set(displayedMeasurementUsages.compactMap(\.inputMode))
        guard !modes.isEmpty else {
            return currentResult.comparisonMethod
        }
        if modes.contains(.verifiedConversion) {
            return MeasurementComparisonBasis.includesVerifiedConversion.displayName
        }
        if modes == [.retailerExact] {
            return MeasurementComparisonBasis.retailerExact.displayName
        }
        if modes == [.canonicalExact] {
            return MeasurementComparisonBasis.canonicalExact.displayName
        }
        return MeasurementComparisonBasis.mixed.displayName
    }

    private var displayedVerifiedConversionCount: Int {
        displayedMeasurementUsages.filter { $0.inputMode == .verifiedConversion }.count
    }

    /// The score remains limited to the immutable DB-authorized metrics. When
    /// both garments use the same retailer format, another exactly compatible
    /// source measurement can still be shown as read-only reference data.
    private var supplementalMeasurementItems: [MeasurementComparisonItem] {
        let referenceItem = activeReferenceItemForDisplay ?? currentResult.userFit
        guard currentResult.comparisonMode == .actualMeasurements,
              let productSource = currentResult.product.sourcePlatformCode?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let referenceSource = referenceItem.sourcePlatformCode?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !productSource.isEmpty,
              productSource == referenceSource else {
            return []
        }
        let authorizedKinds = Set(comparedMeasurementKinds)
        return MeasurementComparisonEngine().compare(
            productSize: displayedProductSize,
            referenceItem: referenceItem,
            productCategory: currentResult.product.category,
            productDetailCategory: currentResult.productDetailCategory
        ).comparedItems.filter { !authorizedKinds.contains($0.kind) }
    }

    private var originalScorePenalty: Int {
        switch currentResult.comparisonMethod {
        case "기준표 가슴둘레 비교":
            return 18
        case "사용자 선택 임시 비교":
            return RecommendationService().manualCandidateNote(
                product: currentResult.product,
                productDetailCategory: currentResult.productDetailCategory,
                item: currentResult.userFit
            ) == nil ? 12 : 20
        case "사용자 선택 직접 비교", "사용자 선택 확장 비교":
            return RecommendationService().manualComparisonScorePenalty(
                product: currentResult.product,
                selectedReferenceItem: currentResult.userFit
            )
        default:
            return 0
        }
    }

    private func alternativeRecommendationScore(
        for size: ProductSize,
        analysis: TemporarySizeAnalysis?
    ) -> Int? {
        if size.id == currentResult.recommendedSize.id {
            return currentResult.recommendationScore
        }
        return analysis?.recommendationScore
    }

    private func cachedAnalysis(for size: ProductSize) -> TemporarySizeAnalysis? {
        guard let key = activeAlternativeAnalysisKeys[size.id] else {
            return nil
        }
        return temporaryAnalysisCache[key]
    }

    @MainActor
    private func prepareAlternativeSizeAnalyses() async {
        let batch = VNextComparisonSessionStore.shared.analysis(
            for: currentResult.id
        )
        guard RecommendationService().canPresentCurrentVNextAlternativeSizes(
            for: currentResult,
            batch: batch
        ), let batch else {
            // Historical/local results retain their original persisted score,
            // but cannot run a fresh measurement comparison without a current
            // evaluator-v4 authorization for the exact target/reference pair.
            temporaryAnalysisCache = [:]
            unavailableAlternativeSizeKeys = []
            activeAlternativeAnalysisKeys = [:]
            isPreparingAlternativeSizes = false
            return
        }
        let generation = alternativePreparationGeneration
        let bySizeID = Dictionary(
            uniqueKeysWithValues: batch.analyses.map { ($0.productSizeID, $0) }
        )
        var preparedAnalyses = temporaryAnalysisCache
        var exactIDs = exactProductSizeIDByTemporaryAnalysisKey
        var unavailableKeys = unavailableAlternativeSizeKeys
        var activeKeys: [UUID: TemporarySizeAnalysisCacheKey] = [:]

        for size in availableProductSizes {
            await Task.yield()
            guard generation == alternativePreparationGeneration else {
                return
            }
            let key = TemporarySizeAnalysisCacheKey(
                productID: currentResult.product.id,
                sizeID: size.id,
                referenceID: currentResult.userFit.id,
                detailCategory: currentResult.productDetailCategory.rawValue,
                comparisonMethod: currentResult.comparisonMethod,
                excludedKindsSignature: "vnext_begin_snapshot",
                scorePenalty: 0
            )
            activeKeys[size.id] = key
            guard preparedAnalyses[key] == nil,
                  !unavailableKeys.contains(key) else {
                continue
            }
            if let serverSizeID = serverProductSizeID(for: size, in: batch),
               let authorized = bySizeID[serverSizeID] {
                preparedAnalyses[key] = TemporarySizeAnalysis(
                    productSize: size,
                    comparisonResult: authorized.result,
                    recommendationScore: authorized.result.score,
                    comparisonSummary: nil
                )
                // Keep the batch's exact product_size_id next to the local
                // presentation cache.  No size label participates here.
                exactIDs[key] = authorized.productSizeID
            } else {
                unavailableKeys.insert(key)
            }
        }

        guard generation == alternativePreparationGeneration else {
            return
        }
        temporaryAnalysisCache = preparedAnalyses
        exactProductSizeIDByTemporaryAnalysisKey = exactIDs
        unavailableAlternativeSizeKeys = unavailableKeys
        activeAlternativeAnalysisKeys = activeKeys
        isPreparingAlternativeSizes = false
    }

    private func presentAlternativeSizeComparison() {
        isShowingAlternativeSizeComparison = true
        guard !isPreparingAlternativeSizes else {
            return
        }
        isPreparingAlternativeSizes = true
        alternativePreparationGeneration = UUID()
        Task { @MainActor in
            await Task.yield()
            await prepareAlternativeSizeAnalyses()
        }
    }

    private var selectedAlternativeSize: ProductSize? {
        guard let selectedAlternativeSizeID else { return nil }
        return availableProductSizes.first { $0.id == selectedAlternativeSizeID }
    }

    private var alternativeAnalysisIsEnabled: Bool {
        !isAnalyzingAlternativeSize && alternativeAnalysisHasValidSelection
    }

    private var alternativeAnalysisHasValidSelection: Bool {
        guard let selectedAlternativeSize,
              selectedAlternativeSize.id != displayedProductSize.id else {
            return false
        }
        return cachedAnalysis(for: selectedAlternativeSize) != nil
    }

    private var alternativeAnalysisButtonTitle: String {
        guard let selectedAlternativeSize else { return "비교할 사이즈를 선택해 주세요" }
        return "\(selectedAlternativeSize.name.displaySizeName) 사이즈로 분석하기"
    }

    private func analyzeSelectedAlternativeSize() {
        guard alternativeAnalysisIsEnabled,
              !isAnalyzingAlternativeSize,
              let selectedAlternativeSize else {
            return
        }
        isAnalyzingAlternativeSize = true
        Task { @MainActor in
            await Task.yield()
            if selectedAlternativeSize.id == currentResult.recommendedSize.id {
                temporarySizeAnalysis = nil
                temporaryDisplayedProductSizeID = nil
                isAnalyzingAlternativeSize = false
                isShowingAlternativeSizeComparison = false
                return
            }
            guard let analysis = cachedAnalysis(for: selectedAlternativeSize) else {
                isAnalyzingAlternativeSize = false
                alternativeSizeErrorMessage = "선택한 사이즈는 비교 가능한 실측 정보가 부족합니다."
                return
            }
            guard let exactProductSizeID = exactProductSizeID(for: selectedAlternativeSize) else {
                isAnalyzingAlternativeSize = false
                alternativeSizeErrorMessage = "선택한 사이즈의 서버 식별자를 다시 확인해 주세요."
                return
            }
            temporarySizeAnalysis = analysis
            temporaryDisplayedProductSizeID = exactProductSizeID
            isAnalyzingAlternativeSize = false
            isShowingAlternativeSizeComparison = false
        }
    }

    private func resetTemporarySizeComparison() {
        alternativePreparationGeneration = UUID()
        selectedAlternativeSizeID = nil
        temporarySizeAnalysis = nil
        temporaryAnalysisCache.removeAll()
        exactProductSizeIDByTemporaryAnalysisKey.removeAll()
        temporaryDisplayedProductSizeID = nil
        activeAlternativeAnalysisKeys.removeAll()
        unavailableAlternativeSizeKeys.removeAll()
        isAnalyzingAlternativeSize = false
        isPreparingAlternativeSizes = false
        alternativeSizeErrorMessage = nil
    }

    @ViewBuilder
    private var calculationSnapshotSections: some View {
        if let snapshot = displayedCalculationSnapshot {
            let presentation = RecommendationCalculationPresentation(snapshot: snapshot)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("비교 정보 \(presentation.coveragePercent)%")
                    .font(.headline.weight(.bold))
                Text("추천 판단에 필요한 치수 중 실제로 비교한 정보의 비율이에요.")
                    .foregroundStyle(.secondary)
            }

            if !presentation.exclusionMessages.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("비교에서 제외된 실측")
                        .font(.headline.weight(.bold))
                    ForEach(presentation.exclusionMessages, id: \.self) { message in
                        Text(message)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var standardSizeFallbackCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "비교 기준", subtitle: "기준표 가슴둘레")

                Text(currentResult.comparisonMode == .unavailable
                     ? "해당 사이즈는 기준표로도 변환할 수 없습니다."
                     : "실측값이 아닌 한국 의류 기준표 기반 결과입니다.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                InfoRow(
                    title: "비교 가능한 항목",
                    value: currentResult.comparisonMode == .unavailable ? "없음" : "가슴"
                )
                InfoRow(title: "비교할 수 없는 항목", value: "총장, 소매 등 기준표에 없는 항목")
            }
        }
    }

    private var resultBottomActionBar: some View {
        VStack(spacing: 10) {
            if onReselectClassification != nil || onClearClassification != nil {
                HStack(spacing: 10) {
                    if let onReselectClassification {
                        Button(action: onReselectClassification) {
                            Label("상품 종류 다시 확인", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }

                    if let onClearClassification {
                        Button(role: .destructive, action: onClearClassification) {
                            Text("내 선택 초기화")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
            }

            Button {
                guard !isPreparingClosetRegistration else { return }
                Task { @MainActor in
                    await prepareClosetRegistration()
                }
            } label: {
                HStack(spacing: 8) {
                    if isPreparingClosetRegistration {
                        ProgressView()
                            .tint(Color(.systemBackground))
                    }
                    Label(
                        isPreparingClosetRegistration ? "등록 정보 확인 중" : "보유한 옷으로 등록",
                        systemImage: "plus"
                    )
                }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPreparingClosetRegistration)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private func showClosetSavedToast() {
        withAnimation { isShowingClosetSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { isShowingClosetSavedToast = false }
        }
    }

    @MainActor
    private func prepareClosetRegistration() async {
        guard !isPreparingClosetRegistration else {
            return
        }

        let resultSnapshot = currentResult
        let displayedSizeSnapshot = displayedProductSize
        let preferredProductSizeID = displayedServerProductSizeID
        isPreparingClosetRegistration = true
        defer { isPreparingClosetRegistration = false }

        let outcome = await FitMatchResultClosetRegistrationPreparationAction.prepare(
            historicalProduct: resultSnapshot.product,
            productDetailCategory: resultSnapshot.productDetailCategory,
            preferredProductSizeID: preferredProductSizeID,
            legacyPreferredSize: displayedSizeSnapshot,
            makeViewModel: { ShoppingProductViewModel() }
        )

        switch outcome {
        case .prepared(let preparation):
            closetRegistrationPreparation = preparation
        case .blocked(let message):
            closetRegistrationPreparationErrorMessage = message
        case .cancelled:
            break
        }
    }

    private func exactProductSizeID(for size: ProductSize) -> UUID? {
        guard let key = activeAlternativeAnalysisKeys[size.id] else {
            return nil
        }
        return exactProductSizeIDByTemporaryAnalysisKey[key]
    }

    private var productThumbnail: some View {
        ProductThumbnailView(
            imageURLString: currentResult.product.imageURLStringForDisplay,
            category: currentResult.product.category,
            width: 90,
            height: 104,
            cornerRadius: 18
        )
    }

    private var confidenceText: String {
        comparedMeasurementKinds.isEmpty
            ? "사이즈 유사도 계산 불가"
            : "사이즈 유사도 \(displayedRecommendationScore)%"
    }

    private var isFavorite: Bool {
        guard let urlString = currentResult.product.sourceURLString else { return false }
        return favoriteURLs.contains(urlString)
    }

    private var heroSummary: String {
        strongestMeasurementReasons.first ?? "내 옷장 기준으로 가장 가까운 사이즈예요."
    }

    private var recommendedSizeName: String {
        currentResult.recommendedSize.name.displaySizeName
    }

    private var selectedOptionName: String {
        let value = currentResult.selectedSizeNameSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? recommendedSizeName : value.displaySizeName
    }

    private func reportIcon(for kind: MeasurementKind) -> String {
        switch kind {
        case .shoulder: return "arrow.left.and.right"
        case .chest, .upperAbdomen, .upperWaist, .underBust: return "tshirt"
        case .totalLength: return "ruler"
        case .sleeveLength: return "ruler"
        case .waist: return "circle.dashed"
        case .hip: return "figure.stand"
        case .thigh, .rise: return "figure.walk"
        case .hem: return "line.3.horizontal"
        case .footLength: return "shoe"
        }
    }

    private func reportShortTitle(for kind: MeasurementKind) -> String {
        switch kind {
        case .shoulder: return "어깨"
        case .chest: return "가슴"
        case .totalLength: return "총장"
        case .sleeveLength: return "소매"
        case .upperAbdomen: return "복부"
        case .upperWaist: return "상의 허리"
        case .waist: return "허리"
        case .hip: return "엉덩이"
        case .thigh: return "허벅지"
        case .rise: return "밑위"
        case .hem: return "밑단"
        case .footLength: return "발길이"
        case .underBust: return "밑가슴"
        }
    }

    private func reportMeasurementTitle(for kind: MeasurementKind) -> String {
        guard let usage = displayedMeasurementUsages.first(where: { $0.kind == kind }) else {
            return kind.title
        }
        if let displayTitle = usage.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayTitle.isEmpty {
            return displayTitle
        }
        switch usage.measurementCode {
        case .pantsInseamCrotchToHem:
            return "인심"
        case .riseCrotchToWaistFront:
            return "앞밑위"
        case .riseCrotchToWaistBack:
            return "뒷밑위"
        case .skirtLengthWaistToHem:
            return "스커트 길이"
        default:
            return kind.title
        }
    }

    private func reportIconRotation(for kind: MeasurementKind) -> Angle {
        switch kind {
        case .totalLength: return .degrees(90)
        case .sleeveLength: return .degrees(-38)
        default: return .zero
        }
    }

    @ViewBuilder
    private func reportMeasurementIcon(for kind: MeasurementKind) -> some View {
        if kind == .shoulder {
            ShoulderMeasurementIcon()
                .frame(width: 18, height: 16)
        } else {
            Image(systemName: reportIcon(for: kind))
                .font(.caption.weight(.semibold))
                .rotationEffect(reportIconRotation(for: kind))
                .frame(width: 16, height: 16)
        }
    }

    private var comparedMeasurementTitle: String {
        let names = comparedMeasurementKinds.map(\.title)
        return names.isEmpty ? "비교 가능한 항목 없음" : names.joined(separator: " · ")
    }

    private var fitMatchDescription: String {
        fitMatchDescription(for: displayedRecommendationScore)
    }

    private var comparisonReliability: ComparisonReliability {
        if let serverApproved = currentResult.serverApprovedVNextReliability {
            return ComparisonReliability(serverApprovedLevel: serverApproved)
        }
        return ComparisonReliability(
            comparedCount: comparedMeasurementKinds.count,
            compatibilityLevel: currentResult.comparisonMethod.contains("확장 비교")
                ? .extended
                : .direct
        )
    }

    private var confidenceStatus: ConfidenceStatus {
        ConfidenceStatus(score: displayedRecommendationScore)
    }

    private var v1MeasurementKinds: [MeasurementKind] {
        switch currentResult.product.category.serviceGroup {
        case .top, .shirt, .knit:
            return [.shoulder, .chest, .totalLength, .sleeveLength]
        case .outer:
            return [.shoulder, .chest, .totalLength, .sleeveLength, .hem]
        case .bottom, .pants:
            return [.waist, .hip, .thigh, .rise, .hem, .totalLength]
        default:
            return currentResult.product.category.measurementKinds(detailCategory: currentResult.productDetailCategory, gender: .unisex)
        }
    }

    private var comparedMeasurementKinds: [MeasurementKind] {
        if temporarySizeAnalysis != nil {
            return displayedMeasurementUsages.map(\.kind)
        }
        if currentResult.comparisonSchemaVersion >= 1 {
            return displayedMeasurementUsages.map(\.kind)
        }
        return v1MeasurementKinds.filter {
            displayedProductSize.measurements.value(for: $0) > 0
                && currentResult.userFit.measurements.value(for: $0) > 0
        }
    }

    private var productSourceCategoryText: String {
        if let sourceCategoryPath = currentResult.product.sourceCategoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceCategoryPath.isEmpty {
            return sourceCategoryPath
        }

        return "카테고리 정보 없음"
    }

    private var productComparisonCategoryText: String {
        guard currentResult.product.category.serviceGroup != .other,
              currentResult.productDetailCategory != .other else {
            return "분류 미확정"
        }

        return "\(currentResult.product.category.serviceGroup.rawValue) / \(currentResult.productDetailCategory.rawValue)"
    }

    private var ignoredMeasurementKinds: [MeasurementKind] {
        v1MeasurementKinds.filter { !comparedMeasurementKinds.contains($0) }
    }

    private var referenceSelectionBadge: String {
        currentResult.comparisonMethod.contains("사용자 선택") ? "직접 선택" : "자동 선택"
    }

    private var referenceSelectionTitle: String {
        currentResult.comparisonMethod.contains("사용자 선택") ? "직접 선택한 내 옷" : "선택된 내 옷"
    }

    private var usedMeasurementSummary: String {
        if currentResult.comparisonMode == .standardSizeFallback {
            return "기준표 가슴둘레 기준으로 비교했어요."
        }
        guard !comparedMeasurementKinds.isEmpty else {
            return "추천에 사용할 수 있는 호환 실측 항목이 없습니다."
        }
        let names = comparedMeasurementKinds.map(\.title).joined(separator: "·")
        return "\(names) 기준으로 비교했어요."
    }

    private var excludedMeasurementSummary: String? {
        if !displayedMeasurementExclusions.isEmpty,
           let exclusion = displayedMeasurementExclusions.first {
            let suffix = displayedMeasurementExclusions.count > 1
                ? " 외 \(displayedMeasurementExclusions.count - 1)개 항목도 상세에서 확인할 수 있어요."
                : ""
            return "\(exclusion.kind.title): \(exclusion.reason.userMessage)\(suffix)"
        }
        guard let kind = ignoredMeasurementKinds.first else { return nil }
        let suffix = ignoredMeasurementKinds.count > 1 ? " 외 \(ignoredMeasurementKinds.count - 1)개 항목" : ""
        return "\(kind.title)\(suffix): 입력값이 없어 비교에서 제외했어요."
    }

    private func comparisonCoverageDetail(for kind: MeasurementKind) -> String {
        if comparedMeasurementKinds.contains(kind) {
            return "동일한 측정 기준으로 추천에 사용"
        }
        if supplementalMeasurementItems.contains(where: { $0.kind == kind }) {
            return "같은 쇼핑몰의 동일한 측정 기준으로 참고 비교 (추천 점수에는 미반영)"
        }
        if let exclusion = displayedMeasurementExclusions.first(where: { $0.kind == kind }) {
            return [exclusion.reason.userMessage, exclusion.definitionDetail]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        return "상품 또는 선택한 내 옷의 실측값이 없어 제외"
    }

    private var comparisonConditionRows: [ComparisonConditionItem] {
        let productDetail = currentResult.productDetailCategory == .other ? "분류 미확정" : currentResult.productDetailCategory.rawValue
        let referenceDetail = currentResult.userFit.detailCategory.rawValue
        let isSameDetail = currentResult.productDetailCategory != .other
            && currentResult.userFit.detailCategory == currentResult.productDetailCategory

        let productCategory = currentResult.product.category.serviceGroup == .other ? "분류 미확정" : currentResult.product.category.serviceGroup.rawValue
        let referenceCategory = currentResult.userFit.category.serviceGroup.rawValue
        let isSameCategory = currentResult.product.category.serviceGroup != .other
            && currentResult.product.category.serviceGroup == currentResult.userFit.category.serviceGroup

        let productBrand = currentResult.product.brand?.name ?? "브랜드 미상"
        let referenceBrand = currentResult.userFit.brandName
        let isSameBrand = productBrand.normalizedBrandName == referenceBrand.normalizedBrandName

        let productSource = currentResult.product.sourceDisplayName
        let referenceSource = currentResult.userFit.sourceName
        let isSameSource = productSource.normalizedBrandName == referenceSource.normalizedBrandName

        let measurementCount = comparedMeasurementKinds.count

        return [
            ComparisonConditionItem(
                isMatched: isSameDetail,
                title: isSameDetail ? "같은 \(productDetail)" : "\(productDetail) ↔ \(referenceDetail)"
            ),
            ComparisonConditionItem(
                isMatched: isSameCategory,
                title: isSameCategory ? "같은 \(productCategory)" : "\(productCategory) ↔ \(referenceCategory)"
            ),
            ComparisonConditionItem(
                isMatched: isSameBrand,
                title: isSameBrand ? "같은 브랜드" : "다른 브랜드"
            ),
            ComparisonConditionItem(
                isMatched: isSameSource,
                title: isSameSource ? "같은 출처" : "다른 출처"
            ),
            ComparisonConditionItem(
                isMatched: true,
                title: "선택한 내 옷"
            ),
            ComparisonConditionItem(
                isMatched: measurementCount >= 2,
                title: measurementCount > 0 ? "실측 \(measurementCount)개 비교" : "실측 부족"
            )
        ]
    }

    private var comparisonSummaryTitle: String {
        if currentResult.comparisonMethod.contains("확장 비교") {
            return "유사 의류 확장 비교"
        }
        if currentResult.productDetailCategory != .other,
           currentResult.userFit.detailCategory == currentResult.productDetailCategory {
            return "같은 \(currentResult.productDetailCategory.rawValue) 기준"
        }

        if currentResult.product.category.serviceGroup != .other,
           currentResult.userFit.category.serviceGroup == currentResult.product.category.serviceGroup {
            return "같은 \(currentResult.product.category.serviceGroup.rawValue) 기준"
        }

        return "참고용 비교"
    }

    private var legacyConfidenceText: String {
        displayedRecommendationScore > 0
            ? "사이즈 유사도 \(displayedRecommendationScore)%"
            : "사이즈 유사도 정보 부족"
    }

    private var recommendationReasons: [String] {
        var reasons = strongestMeasurementReasons

        if currentResult.productDetailCategory != .other,
           (currentResult.comparisonMethod.contains("세부카테고리") || currentResult.userFit.detailCategory == currentResult.productDetailCategory) {
            reasons.append("같은 \(currentResult.productDetailCategory.rawValue) 기준으로 비교했습니다.")
        } else if currentResult.product.category.serviceGroup != .other,
                  currentResult.comparisonMethod.contains("대분류") {
            reasons.append("같은 \(currentResult.product.category.serviceGroup.rawValue) 대분류 기준으로 비교했습니다.")
        } else if currentResult.comparisonMethod.contains("임시") {
            reasons.append("임시 비교라 일부 항목은 참고용입니다.")
        }

        if let weightingNotice {
            reasons.append(weightingNotice)
        }

        if currentResult.comparisonSchemaVersion >= 1 || temporarySizeAnalysis != nil {
            for exclusion in displayedMeasurementExclusions {
                reasons.append("\(exclusion.kind.title)은 \(exclusion.reason.userMessage)")
            }
        } else {
            for kind in ignoredMeasurementKinds {
                reasons.append("\(kind.title)은 입력값이 없어 비교에서 제외했습니다.")
            }
        }

        if !currentResult.fallbackReason.isEmpty {
            reasons.append(currentResult.fallbackReason)
        }

        if reasons.isEmpty, !currentResult.reason.isEmpty {
            reasons.append(currentResult.reason)
        }

        return Array(reasons.prefix(5))
    }

    private var strongestMeasurementReasons: [String] {
        visibleMeasurementKinds
            .map { kind in
                (kind: kind, difference: displayedMeasurementDifferences.value(for: kind))
            }
            .sorted { abs($0.difference) < abs($1.difference) }
            .prefix(3)
            .map { item in
                naturalReason(for: item.kind, difference: item.difference)
            }
    }

    private var visibleMeasurementKinds: [MeasurementKind] {
        comparedMeasurementKinds
    }

    private func openShoppingMall() {
        guard let destination = FitMatchProductURLOpeningAction.destination(
            for: currentResult.product
        ) else {
            return
        }

        switch destination {
        case .musinsaApp(let appURL, let fallbackWebURL):
            openURL(appURL) { accepted in
                if !accepted {
                    openURL(fallbackWebURL)
                }
            }
        case .web(let url):
            openURL(url)
        }
    }

    private func musinsaProductCode(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard let productsIndex = components.firstIndex(where: { $0 == "products" }),
              components.indices.contains(productsIndex + 1) else {
            return currentResult.product.productCode
        }
        let value = components[productsIndex + 1]
        return value.allSatisfy(\.isNumber) ? value : currentResult.product.productCode
    }

    private func logInitialPerformance() {
        DetailPerformanceDiagnostics.log(
            screen: "recommendation_result",
            event: "on_appear",
            startedAt: diagnosticsStartedAt,
            metadata: "sizes=\(resultProductSizes.count) usages=\(resultComparedMeasurementUsages.count) exclusions=\(resultMeasurementExclusions.count)"
        )
        DispatchQueue.main.async {
            DetailPerformanceDiagnostics.logHistoryResultNavigation(event: "first_main_runloop")
            DetailPerformanceDiagnostics.log(
                screen: "recommendation_result",
                event: "next_main_runloop",
                startedAt: diagnosticsStartedAt
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            DetailPerformanceDiagnostics.log(
                screen: "recommendation_result",
                event: "settled_250ms",
                startedAt: diagnosticsStartedAt
            )
        }
    }

    private var comparisonIcon: String {
        if currentResult.comparisonMethod.contains("fallback") || currentResult.comparisonMethod.contains("임시") {
            return "arrow.triangle.branch"
        }
        if currentResult.comparisonMethod.contains("대분류") {
            return "square.grid.2x2"
        }
        return "checkmark.seal"
    }

    private var weightingNotice: String? {
        guard currentResult.productDetailCategory == .shortSleeve || currentResult.productDetailCategory == .sleeveless else {
            return nil
        }

        if currentResult.userFit.detailCategory != currentResult.productDetailCategory {
            return "\(currentResult.productDetailCategory.rawValue) 상품이라 소매길이는 낮은 비중으로 계산했어요."
        }

        if currentResult.productDetailCategory == .sleeveless {
            return "민소매 상품이라 소매길이는 추천도 계산에서 제외했어요."
        }

        return nil
    }

    private func naturalReason(for kind: MeasurementKind, difference: Double) -> String {
        let subject = naturalSubject(for: kind)
        let subjectParticle = subject.hasFinalConsonant ? "은" : "는"
        let absoluteDifference = abs(difference)

        if absoluteDifference == 0 {
            return "\(subject)\(subjectParticle) 동일합니다."
        }

        if absoluteDifference <= 1 {
            return "\(subject)\(subjectParticle) 거의 동일합니다."
        }

        if absoluteDifference <= 2 {
            return compactDirectionalReason(
                subject: subject,
                particle: subjectParticle,
                kind: kind,
                difference: difference,
                positiveBodyText: "살짝 여유 있습니다.",
                negativeBodyText: "살짝 타이트할 수 있습니다.",
                positiveLengthText: "살짝 길 수 있습니다.",
                negativeLengthText: "살짝 짧을 수 있습니다."
            )
        }

        if absoluteDifference <= 4 {
            return compactDirectionalReason(
                subject: subject,
                particle: subjectParticle,
                kind: kind,
                difference: difference,
                positiveBodyText: "여유 있게 느껴질 수 있습니다.",
                negativeBodyText: "타이트하게 느껴질 수 있습니다.",
                positiveLengthText: "길게 느껴질 수 있습니다.",
                negativeLengthText: "짧게 느껴질 수 있습니다."
            )
        }

        if absoluteDifference <= 6 {
            return "\(subject)\(subjectParticle) 차이가 커서 핏이 달라질 수 있습니다."
        }

        return "\(subject)\(subjectParticle) 차이가 많이 커서 구매 전 확인이 필요합니다."
    }

    private func compactDirectionalReason(
        subject: String,
        particle: String,
        kind: MeasurementKind,
        difference: Double,
        positiveBodyText: String,
        negativeBodyText: String,
        positiveLengthText: String,
        negativeLengthText: String
    ) -> String {
        if kind == .totalLength || kind == .sleeveLength || kind == .rise || kind == .footLength {
            return difference > 0
                ? "\(subject)\(particle) \(positiveLengthText)"
                : "\(subject)\(particle) \(negativeLengthText)"
        }

        return difference > 0
            ? "\(subject)\(particle) \(positiveBodyText)"
            : "\(subject)\(particle) \(negativeBodyText)"
    }

    private func naturalSubject(for kind: MeasurementKind) -> String {
        switch kind {
        case .shoulder:
            return "어깨"
        case .chest:
            return "가슴"
        case .totalLength:
            return "총장"
        case .sleeveLength:
            return "소매"
        default:
            return kind.title
        }
    }

    #if DEBUG
    private func recommendedSizeName(for userFit: UserFit) -> String {
        RecommendationService()
            .recommend(
                product: currentResult.product,
                selectedReferenceItem: userFit,
                productDetailCategory: currentResult.productDetailCategory
            )?
            .recommendedSize
            .name
            .displaySizeName ?? "-"
    }
    #endif
}

private struct ConfidenceStatus {
    let stars: String
    let title: String

    init(score: Int) {
        switch score {
        case 90...100:
            stars = "★★★★★"
            title = "매우 높은 신뢰도"
        case 80..<90:
            stars = "★★★★☆"
            title = "높은 신뢰도"
        case 70..<80:
            stars = "★★★☆☆"
            title = "보통"
        case 60..<70:
            stars = "★★☆☆☆"
            title = "참고용"
        case 1..<60:
            stars = "★☆☆☆☆"
            title = "참고만 권장"
        default:
            stars = "정보 부족"
            title = "계산에 필요한 실측이 부족합니다"
        }
    }
}

private struct ComparisonReliability {
    let stars: String
    let title: String

    init(
        comparedCount: Int,
        compatibilityLevel: GarmentComparisonCompatibilityLevel
    ) {
        let baseStars: Int
        switch comparedCount {
        case 4...: baseStars = 5
        case 3: baseStars = 4
        case 2: baseStars = 3
        case 1: baseStars = 2
        default: baseStars = 1
        }
        let filledStars = max(1, baseStars - compatibilityLevel.reliabilityStarPenalty)
        stars = String(repeating: "★", count: filledStars)
            + String(repeating: "☆", count: 5 - filledStars)
        let baseTitle: String
        switch filledStars {
        case 5: baseTitle = "매우 높음"
        case 4: baseTitle = "높음"
        case 3: baseTitle = "보통"
        case 2: baseTitle = "낮음"
        default: baseTitle = "매우 낮음"
        }
        title = compatibilityLevel == .extended ? "확장 비교 · \(baseTitle)" : baseTitle
    }

    init(serverApprovedLevel: Int) {
        let filledStars = min(5, max(1, serverApprovedLevel))
        stars = String(repeating: "★", count: filledStars)
            + String(repeating: "☆", count: 5 - filledStars)
        switch filledStars {
        case 5: title = "매우 높음"
        case 4: title = "높음"
        case 3: title = "보통"
        case 2: title = "낮음"
        default: title = "매우 낮음"
        }
    }
}

private struct TemporarySizeAnalysisCacheKey: Hashable {
    let productID: UUID
    let sizeID: UUID
    let referenceID: UUID
    let detailCategory: String
    let comparisonMethod: String
    let excludedKindsSignature: String
    let scorePenalty: Int
}

private enum AlternativeSizeMeasurementStatus {
    case close
    case caution
    case negative
    case unavailable

    var color: Color {
        switch self {
        case .close: return .green
        case .caution: return .orange
        case .negative: return .red
        case .unavailable: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .close: return "checkmark"
        case .caution: return "minus"
        case .negative: return "exclamationmark"
        case .unavailable: return "questionmark"
        }
    }
}

private struct AlternativeSizeMeasurementSummary {
    let title: String
    let message: String
    let status: AlternativeSizeMeasurementStatus
}

private struct AlternativeSizeResultCard: View {
    let sizeName: String
    let isRecommended: Bool
    let isSelected: Bool
    let score: Int?
    let fitDescription: String?
    let fitColor: Color?
    let measurements: [AlternativeSizeMeasurementSummary]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(sizeName)
                                .font(.title2.weight(.black))
                            if isRecommended {
                                Text("추천")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.green.opacity(0.12), in: Capsule())
                            }
                        }
                        if let score {
                            Text("\(score)%")
                                .font(.title3.weight(.black))
                                .monospacedDigit()
                        }
                        if let fitDescription, let fitColor {
                            Text(fitDescription)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(fitColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(fitColor.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
                        GridItem(.flexible(), spacing: 8, alignment: .topLeading)
                    ],
                    alignment: .leading,
                    spacing: 9
                ) {
                    ForEach(Array(measurements.enumerated()), id: \.offset) { _, measurement in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: measurement.status.symbol)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 17, height: 17)
                                .background(measurement.status.color, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(measurement.title)
                                    .font(.caption2.weight(.bold))
                                Text(measurement.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isRecommended ? Color.green.opacity(0.08) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.primary : (isRecommended ? Color.green : Color.secondary.opacity(0.18)),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        var parts = ["\(sizeName) 사이즈"]
        if isRecommended { parts.append("핏매치 추천 사이즈") }
        if isSelected { parts.append("선택됨") }
        if let score { parts.append("사이즈 유사도 \(score)퍼센트") }
        if let fitDescription { parts.append(fitDescription) }
        parts.append(contentsOf: measurements.map { "\($0.title), \($0.message)" })
        return parts.joined(separator: ", ")
    }
}

private struct ComparisonCoverageRow: View {
    let title: String
    let isCompared: Bool
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCompared ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isCompared ? .green : .secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(isCompared ? "사용" : "제외")
                .font(.caption.weight(.bold))
                .foregroundStyle(isCompared ? .green : .secondary)
        }
        .padding(12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }
}

private struct ComparisonTargetColumn: View {
    let title: String
    let imageURLString: String?
    let category: ClothingCategory
    let brand: String
    let name: String
    let meta: String
    let badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.primary, in: Capsule())
                }
            }

            ProductThumbnailView(
                imageURLString: imageURLString,
                category: category,
                width: 128,
                height: 136,
                cornerRadius: 16
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text(brand)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ResultBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.08), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComparisonConditionItem: Identifiable {
    let id = UUID()
    let isMatched: Bool
    let title: String
}

private struct ComparisonConditionRow: View {
    let item: ComparisonConditionItem

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.isMatched ? "checkmark.circle.fill" : "minus.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.isMatched ? .primary : .secondary)
                .frame(width: 22)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ComparisonConditionChip: View {
    let item: ComparisonConditionItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isMatched ? "checkmark.circle.fill" : "minus.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.isMatched ? .primary : .secondary)

            Text(item.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + spacing + size.width > maxWidth {
                widestLine = max(widestLine, currentX)
                totalHeight += currentLineHeight + lineSpacing
                currentX = 0
                currentLineHeight = 0
            }

            if currentX > 0 {
                currentX += spacing
            }
            currentX += size.width
            currentLineHeight = max(currentLineHeight, size.height)
        }

        widestLine = max(widestLine, currentX)
        totalHeight += currentLineHeight

        return CGSize(width: maxWidth > 0 ? maxWidth : widestLine, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var currentLineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + spacing + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += currentLineHeight + lineSpacing
                currentLineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )

            currentX += size.width + spacing
            currentLineHeight = max(currentLineHeight, size.height)
        }
    }
}

private struct FitRecommendationRow: View {
    let title: String
    let value: String
    let detail: String
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(isPrimary ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isPrimary ? Color.primary : Color.primary.opacity(0.08), in: Capsule())
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReasonBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MeasurementGrid: View {
    let measurements: GarmentMeasurements
    var category: ClothingCategory = .top
    var detailCategory: ClosetDetailCategory = .other
    var gender: UserGender = .unisex
    var showsSignedDifference = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { kind in
                        MeasurementPill(
                            title: kind.title,
                            value: measurements.value(for: kind),
                            showsSignedDifference: showsSignedDifference
                        )
                    }
                    if row.count == 1 {
                        Color.clear
                    }
                }
            }
        }
    }

    private var rows: [[MeasurementKind]] {
        let kinds = category.measurementKinds(detailCategory: detailCategory, gender: gender)
        return stride(from: 0, to: kinds.count, by: 2).map {
            Array(kinds[$0..<min($0 + 2, kinds.count)])
        }
    }
}

private struct MeasurementPill: View {
    let title: String
    let value: Double
    let showsSignedDifference: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(showsSignedDifference ? value.signedCmText : value.cmText)
                .font(.headline.weight(.bold))
                .foregroundStyle(showsSignedDifference ? value.differenceColor : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProductMeasurementDifferenceGrid: View {
    let measurements: GarmentMeasurements
    let referenceMeasurements: GarmentMeasurements
    let differences: GarmentMeasurements
    let kinds: [MeasurementKind]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(kinds) { kind in
                ProductMeasurementDifferenceRow(
                    title: kind.title,
                    productValue: measurements.value(for: kind),
                    referenceValue: referenceMeasurements.value(for: kind),
                    difference: differences.value(for: kind)
                )
            }
        }
    }
}

private struct ShoulderMeasurementIcon: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: size.height * 0.82))
            path.addCurve(
                to: CGPoint(x: size.width * 0.36, y: size.height * 0.34),
                control1: CGPoint(x: size.width * 0.12, y: size.height * 0.55),
                control2: CGPoint(x: size.width * 0.25, y: size.height * 0.48)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.64, y: size.height * 0.34),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.72),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.72)
            )
            path.addCurve(
                to: CGPoint(x: size.width - 1, y: size.height * 0.82),
                control1: CGPoint(x: size.width * 0.75, y: size.height * 0.48),
                control2: CGPoint(x: size.width * 0.88, y: size.height * 0.55)
            )
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct CenteredMetricColumn<Detail: View>: View {
    let title: String
    let value: String
    var valueFontSize: CGFloat = 35.2
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.system(size: valueFontSize, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .multilineTextAlignment(.center)

            detail()
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct ReportMeasurementRow: View {
    let kind: MeasurementKind
    let title: String
    let productValue: Double
    let referenceValue: Double
    let difference: Double
    let inputMode: MeasurementComparisonInputMode?
    let isSupplemental: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(inputModeBadgeTitle)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 66, alignment: .leading)

            valueColumn(title: "상품", value: productValue, color: .blue)
            valueColumn(title: "내 옷", value: referenceValue, color: .primary)
            Spacer(minLength: 0)
            differenceColumn
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func valueColumn(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value > 0 ? String(format: "%.1f", value) : "정보 없음")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 54, alignment: .leading)
    }

    private var differenceColumn: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("차이")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(
                productValue > 0 && referenceValue > 0
                    ? MeasurementDifferenceReferenceText.text(
                        kind: kind,
                        difference: difference
                    )
                    : "비교 제외"
            )
                .font(.caption.weight(.black))
                .foregroundStyle(productValue > 0 && referenceValue > 0 ? differenceSeverityColor : .secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 112, alignment: .trailing)
    }

    private var differenceSeverityColor: Color {
        switch abs(difference) {
        case 5...: return .red
        case 2..<5: return .orange
        default: return .green
        }
    }

    private var inputModeBadgeTitle: String {
        if isSupplemental { return "참고" }
        switch inputMode {
        case .retailerExact: return "쇼핑몰 원본"
        case .canonicalExact: return "FitMatch"
        case .verifiedConversion: return "검증 환산"
        case .none: return "측정 기준"
        }
    }

}

private struct ReportMeasurementPresentation: Identifiable {
    let kind: MeasurementKind
    let title: String
    let productValue: Double
    let referenceValue: Double
    let difference: Double
    let inputMode: MeasurementComparisonInputMode?
    let isSupplemental: Bool

    var id: MeasurementKind { kind }
}

enum MeasurementDifferenceReferenceText {
    static func text(kind: MeasurementKind, difference: Double) -> String {
        guard difference != 0 else {
            return "내 옷과 같아요"
        }

        let value = formattedCentimeters(abs(difference))
        let direction: String
        switch kind {
        case .shoulder, .chest, .upperAbdomen, .upperWaist,
             .waist, .hip, .thigh, .hem, .underBust:
            direction = difference > 0 ? "넓어요" : "좁아요"
        case .totalLength, .sleeveLength, .rise, .footLength:
            direction = difference > 0 ? "길어요" : "짧아요"
        }
        return "내 옷보다 \(value) \(direction)"
    }

    private static func formattedCentimeters(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))cm"
        }
        return "\(String(format: "%.1f", value))cm"
    }
}

private struct ProductMeasurementDifferenceRow: View {
    let title: String
    let productValue: Double
    let referenceValue: Double
    let difference: Double

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: status.systemImage)
                .font(.headline)
                .foregroundStyle(status.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    measurementValueColumn(title: "상품", value: productValue)
                    measurementValueColumn(title: "내 옷", value: referenceValue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(difference.signedCmText)
                    .font(.headline.weight(.black))
                    .foregroundStyle(status.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(status.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            }
            .frame(minWidth: 70, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var status: MeasurementDifferenceStatus {
        MeasurementDifferenceStatus(difference: abs(difference))
    }

    private func measurementValueColumn(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value > 0 ? value.cmText : "-")
                .font(.subheadline.weight(.black))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(minWidth: 58, alignment: .leading)
    }
}

private struct MeasurementDifferenceStatus {
    let title: String
    let systemImage: String
    let color: Color

    init(difference: Double) {
        if difference <= 2 {
            title = "좋음"
            systemImage = "checkmark.circle.fill"
            color = .green
        } else if difference < 5 {
            title = "주의"
            systemImage = "exclamationmark.circle.fill"
            color = .orange
        } else {
            title = "차이 큼"
            systemImage = "xmark.circle.fill"
            color = .red
        }
    }
}

private struct FitMatchRankRow: View {
    let rank: Int
    let candidate: FitMatchCandidate
    let recommendedSizeName: String
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(rank)")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.primary, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.userFit.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(candidate.userFit.brandName) · \(candidate.userFit.sizeName) · \(candidate.userFit.category.rawValue) / \(candidate.userFit.detailCategory.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(candidate.selectionReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("추천 \(recommendedSizeName)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.08), in: Capsule())

                    if isCurrent {
                        Text("현재 비교 중")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(candidate.matchRate)%")
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum ResultReferenceComparisonOutcome {
    case success(RecommendationHistory)
    case insufficient(InsufficientComparisonEvidence?)
    case saveFailed(String)

    var shouldDismissPicker: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

/// Shared result-reference orchestration.  The result picker and the final
/// submission both use this exact server-authority action; it has no local
/// comparison-policy fallback.
@MainActor
enum ResultReferenceComparisonAction {
    enum AuthorizationOutcome {
        case allowed(FitMatchServerReferenceAuthorization)
        case rejected(String)
        case unavailable(String)
    }

    enum DiscoveryOutcome {
        case success([UUID: FitMatchServerReferenceSelectionCandidate])
        case blocked(String)
    }

    static func authorize(
        target: Product,
        reference: UserFit,
        coordinator: FitMatchServerAuthorityCoordinator
    ) async -> AuthorizationOutcome {
        guard let targetRequest = target.fitMatchDatabaseResolutionRequest(),
              let targetObservation = target.fitMatchProductObservationRequest(),
              let localReferenceSnapshot = reference.fitMatchServerReferenceSnapshot() else {
            return .unavailable("서버에서 대상 상품 또는 선택한 내 옷을 확인할 수 없습니다.")
        }

        let usesExplicitUserAuthority =
            reference.classificationAuthorityProvenance == .userExplicit
        do {
            let authorization = try await coordinator.authorizeReferenceCandidate(
                referenceClientItemID: reference.id,
                localReferenceSnapshot: localReferenceSnapshot,
                targetRequest: targetRequest,
                targetObservation: targetObservation,
                referenceRequest: usesExplicitUserAuthority
                    ? nil
                    : reference.sourceProduct?.fitMatchDatabaseResolutionRequest(),
                referenceObservation: usesExplicitUserAuthority
                    ? nil
                    : reference.sourceProduct?.fitMatchProductObservationRequest()
            )
            guard authorization.isAllowed else {
                return .rejected(
                    authorization.reason
                        ?? "서버 비교 정책상 선택한 옷과 비교할 수 없습니다."
                )
            }
            return .allowed(authorization)
        } catch {
            return .unavailable("서버 비교 가능 여부를 확인하지 못했습니다.")
        }
    }

    /// Maps server-authorized client IDs to the currently active local Closet
    /// items.  The local list is never treated as a comparison policy.
    static func discoverSelectableReferences(
        from localItems: [UserFit],
        excluding currentReferenceID: UUID,
        target: Product,
        coordinator: FitMatchServerAuthorityCoordinator
    ) async -> DiscoveryOutcome {
        guard let targetRequest = target.fitMatchDatabaseResolutionRequest(),
              let targetObservation = target.fitMatchProductObservationRequest() else {
            return .blocked("서버에서 대상 상품을 확인할 수 없습니다.")
        }

        do {
            let eligibleLocalClientItemIDs = Set(
                localItems
                    .filter {
                        $0.isActiveClosetItem
                            && $0.id != currentReferenceID
                            && $0.fitMatchServerReferenceSnapshot() != nil
                    }
                    .map(\.id)
            )
            let plan = try await coordinator.referenceSelectionPlan(
                targetRequest: targetRequest,
                targetObservation: targetObservation
            )
            let selectable = plan.candidates.filter {
                $0.isSelectable
                    && eligibleLocalClientItemIDs.contains($0.clientItemID)
            }
            return .success(
                Dictionary(uniqueKeysWithValues: selectable.map {
                    ($0.clientItemID, $0)
                })
            )
        } catch {
            return .blocked("서버 비교 가능 여부를 확인하지 못했습니다.")
        }
    }
}

@MainActor
enum ResultReferenceComparisonPersistence {
    static func resolveAndSave(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory,
        permit: FitMatchServerComparisonPermit,
        existingHistories: [RecommendationHistory],
        modelContext: ModelContext,
        coordinator: FitMatchServerAuthorityCoordinator,
        persistCompletedHistory: @MainActor (RecommendationHistory, [RecommendationHistory], ModelContext) throws -> Void = ResultReferenceComparisonPersistence.persistCompletedHistory
    ) async -> ResultReferenceComparisonOutcome {
        let service = RecommendationService()
        let analysis: VNextComparisonBatchAnalysis
        let completion: VNextCompleteComparisonDTO
        do {
            analysis = try service.analyzeVNextComparison(permit: permit)
            completion = try await coordinator.completeAuthorizedComparison(
                permit: permit,
                analysis: analysis
            )
        } catch {
            return .saveFailed(error.localizedDescription)
        }
        guard let history = service.makeCompletedVNextHistory(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            productDetailCategory: productDetailCategory,
            permit: permit,
            analysis: analysis,
            completion: completion
        ) else {
            return .insufficient(nil)
        }

        do {
            try persistCompletedHistory(history, existingHistories, modelContext)
            VNextComparisonSessionStore.shared.store(
                analysis,
                historyID: history.id
            )
            return .success(history)
        } catch {
            modelContext.rollback()
            return .saveFailed(error.localizedDescription)
        }
    }

    private static func persistCompletedHistory(
        _ history: RecommendationHistory,
        _ histories: [RecommendationHistory],
        _ context: ModelContext
    ) throws {
        try RecommendationHistoryStore.saveCompletedVNext(
            history,
            existing: histories,
            modelContext: context
        )
    }

    #if DEBUG
    // Retained only in debug builds for isolated legacy/manual unit coverage.
    // Release result-screen selection has no local pre-evaluator scoring API.
    static func resolveAndSave(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory,
        existingHistories: [RecommendationHistory],
        modelContext: ModelContext
    ) -> ResultReferenceComparisonOutcome {
        let outcome = ResultReferenceComparisonResolver.resolve(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            productDetailCategory: productDetailCategory
        )

        guard case .success(let history) = outcome else {
            return outcome
        }

        do {
            try RecommendationHistoryStore.saveUnique(
                history,
                existing: existingHistories,
                modelContext: modelContext
            )
            return .success(history)
        } catch {
            modelContext.rollback()
            return .saveFailed(error.localizedDescription)
        }
    }
    #endif
}

#if DEBUG
enum ResultReferenceComparisonResolver {
    static func resolve(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> ResultReferenceComparisonOutcome {
        let service = RecommendationService()
        if let history = service.recommend(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            productDetailCategory: productDetailCategory
        ) {
            return .success(history)
        }

        return .insufficient(
            service.insufficientEvidence(
                product: product,
                selectedReferenceItem: selectedReferenceItem,
                productDetailCategory: productDetailCategory
            )
        )
    }
}
#endif

private extension String {
    var displaySizeName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        let finalComponent = value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
        return SizeTokenNormalizer.displayName(for: finalComponent)
    }

    var hasFinalConsonant: Bool {
        guard let scalar = unicodeScalars.last?.value else {
            return false
        }

        let base: UInt32 = 0xAC00
        let end: UInt32 = 0xD7A3
        guard scalar >= base && scalar <= end else {
            return false
        }

        return (scalar - base) % 28 != 0
    }
}

private extension Double {
    var signedCmText: String {
        let sign = self > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", self))cm"
    }

    var differenceColor: Color {
        if self > 0 {
            return .orange
        }
        if self < 0 {
            return .blue
        }
        return .primary
    }

    var oneDecimalText: String {
        String(format: "%.1f", self)
    }
}
