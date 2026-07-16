import SwiftUI
import SwiftData

struct RecommendationResultView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let result: RecommendationHistory
    private let opensReferencePickerOnAppear: Bool
    private let onResultPersisted: ((RecommendationHistory) -> Void)?
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var comparisonResult: RecommendationHistory?
    @State private var activeSheet: RecommendationResultActiveSheet?
    @State private var isShowingClosetSavedAlert = false
    @State private var isShowingComparisonDetails = false
    @State private var isShowingReliabilityInfo = false
    @State private var isShowingMeasurementInfo = false
    @State private var isComparisonCoverageExpanded = false
    @State private var didOpenInitialReferencePicker = false
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    private let favoriteStore = FavoriteProductStore()

    init(
        result: RecommendationHistory,
        opensReferencePickerOnAppear: Bool = false,
        onResultPersisted: ((RecommendationHistory) -> Void)? = nil
    ) {
        self.result = result
        self.opensReferencePickerOnAppear = opensReferencePickerOnAppear
        self.onResultPersisted = onResultPersisted
    }

    private var currentResult: RecommendationHistory {
        comparisonResult ?? result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 10) {
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
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .background(Color(.systemBackground))
            .navigationTitle("비교 결과")
            .safeAreaInset(edge: .bottom) {
                resultBottomActionBar
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .referencePicker:
                NavigationStack {
                    ResultReferencePickerView(
                        userFits: userFits,
                        currentUserFit: currentResult.userFit,
                        productDetailCategory: currentResult.productDetailCategory,
                        productCategory: currentResult.product.category
                    ) { item in
                        let outcome = compare(with: item)
                        if outcome.shouldDismissPicker {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo("resultTop", anchor: .top)
                                }
                            }
                        }
                        return outcome
                    }
                }
                .presentationDragIndicator(.visible)
                case .addToCloset:
                AddComparedProductToClosetSheet(
                    product: currentResult.product,
                    productDetailCategory: currentResult.productDetailCategory,
                    recommendedSize: currentResult.recommendedSize
                ) { _ in
                    isShowingClosetSavedAlert = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                }
            }
            .alert("내 옷장에 추가했어요.", isPresented: $isShowingClosetSavedAlert) {
                Button("확인", role: .cancel) {}
            }
            .sheet(isPresented: $isShowingReliabilityInfo) {
                reliabilityInfoSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingMeasurementInfo) {
                measurementInfoSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                #if DEBUG
                print("[화면: 비교 결과][동작: 결과 화면 진입][상태: 성공] 상품=\(currentResult.product.name), 추천사이즈=\(currentResult.recommendedSize.name), 기준옷=\(currentResult.userFit.displayName)")
                #endif
                tabBarVisibilityController.hide(reason: .navigationDetail, source: "recommendation result")
                guard opensReferencePickerOnAppear, !didOpenInitialReferencePicker else {
                    return
                }

                didOpenInitialReferencePicker = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presentActiveSheet(.referencePicker)
                }
            }
            .onDisappear {
                #if DEBUG
                print("[화면: 비교 결과][동작: 결과 화면 종료][상태: 완료]")
                #endif
                tabBarVisibilityController.release(reason: .navigationDetail, source: "recommendation result disappear")
            }
        }
    }

    // TODO: Legacy UI, 삭제 금지.
    // 원복 시 body의 report* 카드 묶음을 이 콘텐츠로 교체합니다.
    @ViewBuilder
    private var comparisonResultScreenLegacy: some View {
        heroCard
        comparisonTargetsCard
        comparisonBasisSummaryCard
        if currentResult.comparisonMode != .actualMeasurements {
            standardSizeFallbackCard
        }
        fitRecommendationCard
        comparisonDetailToggleCard
        if isShowingComparisonDetails {
            measurementDifferenceCard
            comparisonCoverageCard
            reasonCard
            comparisonConditionCard
            fitMatchRankingCard
        }
    }

    private var reportProductCard: some View {
        CardView(radius: 20, padding: 12) {
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
            cornerRadius: 16
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
        CardView(radius: 20, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    let dividerWidth: CGFloat = 1
                    let columnWidth = (geometry.size.width - (dividerWidth * 2)) / 3

                    HStack(alignment: .top, spacing: 0) {
                        RecommendationMetricColumn(
                            title: "추천 사이즈",
                            value: recommendedSizeName,
                            detail: nil,
                            isPrimary: true
                        )
                        .frame(width: columnWidth)
                        Divider().frame(width: dividerWidth, height: 150)
                        RecommendationMetricColumn(
                            title: "핏 매칭률",
                            value: comparedMeasurementKinds.isEmpty ? "정보 부족" : "\(currentResult.recommendationScore)%",
                            detail: fitMatchDescription,
                            isPrimary: false
                        )
                        .frame(width: columnWidth)
                        Divider().frame(width: dividerWidth, height: 150)
                        VStack(alignment: .center, spacing: 3) {
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
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 18)
                            Text(comparisonReliability.stars)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.orange.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(height: 42)
                            Text(comparisonReliability.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(height: 24)
                            Divider()
                            HStack(spacing: 3) {
                                Text("\(comparedMeasurementKinds.count)개 실측 항목 비교")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Button { isShowingMeasurementInfo = true } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("비교 실측 항목")
                            }
                            HStack(spacing: comparedMeasurementKinds.count > 4 ? 2 : 5) {
                                ForEach(comparedMeasurementKinds) { kind in
                                    VStack(spacing: 2) {
                                        reportMeasurementIcon(for: kind)
                                        Text(reportShortTitle(for: kind))
                                            .font(.system(size: 8, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(width: columnWidth, alignment: .center)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var reportMeasurementCard: some View {
        CardView(radius: 20, padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                SectionHeader(
                    title: currentResult.comparisonMode == .standardSizeFallback ? "기준표 비교 결과" : "실측 비교 결과",
                    subtitle: nil
                )

                if currentResult.comparisonMode == .standardSizeFallback {
                    InfoRow(title: "가슴", value: currentResult.trueToSizeRecommendation)
                } else if comparedMeasurementKinds.isEmpty {
                    ContentUnavailableView(
                        "비교 가능한 항목이 없어요",
                        systemImage: "ruler",
                        description: Text("측정값이나 측정 기준을 확인해 주세요.")
                    )
                } else {
                    VStack(spacing: 4) {
                        ForEach(comparedMeasurementKinds) { kind in
                            ReportMeasurementRow(
                                title: kind.title,
                                productValue: currentResult.recommendedSize.measurements.value(for: kind),
                                referenceValue: currentResult.userFit.measurements.value(for: kind),
                                difference: currentResult.measurementDifferences.value(for: kind)
                            )
                        }
                    }
                }
            }
        }
    }

    private var reportReferenceCard: some View {
        CardView(radius: 20, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "비교 기준 옷")
                HStack(spacing: 14) {
                    ProductThumbnailView(
                        imageURLString: currentResult.userFit.sourceProduct?.imageURLString,
                        category: currentResult.userFit.category,
                        width: 48,
                        height: 54,
                        cornerRadius: 12
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
                    Button("기준 옷 변경") { presentActiveSheet(.referencePicker) }
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
        CardView(radius: 20, padding: 12) {
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
                Text("핏 매칭률은 선택한 상품 사이즈와 기준 옷의 치수가 얼마나 유사한지 나타냅니다.")
                Text("신뢰도는 사용된 실측 항목 수와 측정 방식 호환 여부, 누락·제외 항목을 바탕으로 결과를 얼마나 참고할 수 있는지 보여줍니다.")
                    .foregroundStyle(.secondary)
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

    private var measurementInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("추천 계산에 사용하거나 제외한 실측 항목입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(v1MeasurementKinds, id: \.id) { kind in
                        ComparisonCoverageRow(
                            title: kind.title,
                            isCompared: comparedMeasurementKinds.contains(kind),
                            detail: comparisonCoverageDetail(for: kind)
                        )
                    }
                }
                Spacer()
            }
            .font(.subheadline)
            .padding(20)
            .navigationTitle("실측 비교 항목")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: 6) {
                    Text(recommendedSizeName)
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("추천 사이즈")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.62))
                }
                .frame(width: 118, height: 118)
                .background(.white, in: Circle())

                VStack(alignment: .leading, spacing: 10) {
                    Text("사이즈 유사도")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(comparedMeasurementKinds.isEmpty ? "정보 부족" : "\(currentResult.recommendationScore)%")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("추천 신뢰도 \(comparisonReliability.stars)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.86))
                    Text("\(comparisonReliability.title) · \(comparedMeasurementKinds.count)개 항목 비교")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var productInfoCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "상품 정보")

                HStack(alignment: .top, spacing: 14) {
                    productThumbnail

                    VStack(alignment: .leading, spacing: 9) {
                        Text(currentResult.product.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        InfoRow(title: "브랜드", value: currentResult.product.brand?.name ?? "브랜드 미상")
                        InfoRow(title: "출처", value: currentResult.product.sourceDisplayName)
                        InfoRow(title: "쇼핑몰 카테고리", value: productSourceCategoryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var comparisonTargetsCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "비교 대상")

                HStack(alignment: .top, spacing: 12) {
                    ComparisonTargetColumn(
                        title: "상품",
                        imageURLString: currentResult.product.imageURLString,
                        category: currentResult.product.category,
                        brand: currentResult.product.brand?.name ?? "브랜드 미상",
                        name: currentResult.product.name,
                        meta: productComparisonCategoryText,
                        badge: nil
                    )

                    ComparisonTargetColumn(
                        title: "내 옷",
                        imageURLString: currentResult.userFit.sourceProduct?.imageURLString,
                        category: currentResult.userFit.category,
                        brand: currentResult.userFit.brandName,
                        name: currentResult.userFit.displayName,
                        meta: "\(currentResult.userFit.detailCategory.rawValue) / \(currentResult.userFit.sizeName)",
                        badge: referenceSelectionBadge
                    )
                }
            }
        }
    }

    private var comparisonBasisSummaryCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "추천 근거")

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(usedMeasurementSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let excludedMeasurementSummary {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                        Text(excludedMeasurementSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                InfoRow(title: referenceSelectionTitle, value: currentResult.userFit.displayName)
                InfoRow(title: "기준 사이즈", value: currentResult.userFit.sizeName)
            }
        }
    }

    private var comparisonDetailToggleCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isShowingComparisonDetails.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.headline.weight(.bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isShowingComparisonDetails ? "상세 비교 접기" : "상세 비교 보기")
                        .font(.headline.weight(.bold))
                    Text("실측 차이와 제외된 항목의 이유를 확인할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isShowingComparisonDetails ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var referenceFitCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "기준 옷")

                VStack(spacing: 10) {
                    InfoRow(title: "기준 옷", value: currentResult.userFit.displayName)
                    InfoRow(title: "브랜드", value: currentResult.userFit.brandName)
                    InfoRow(title: "사이즈", value: currentResult.userFit.sizeName)
                    InfoRow(title: "카테고리", value: "\(currentResult.userFit.category.rawValue) / \(currentResult.userFit.detailCategory.rawValue)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    if currentResult.userFit.isRepresentative {
                        ResultBadge(title: "기준 옷", systemImage: "heart.fill")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var comparisonConditionCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "비교 근거")

                VStack(alignment: .leading, spacing: 10) {
                    Text(comparisonSummaryTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)

                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(comparisonConditionRows) { row in
                            ComparisonConditionChip(item: row)
                        }
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

    private var fitMatchRankingCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "내 옷장 Fit Match 순위")

                if fitMatchRanking.isEmpty {
                    Text("비교할 수 있는 옷장 데이터가 부족합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(fitMatchRanking.enumerated()), id: \.element.id) { index, candidate in
                            FitMatchRankRow(
                                rank: index + 1,
                                candidate: candidate,
                                recommendedSizeName: recommendedSizeName(for: candidate.userFit),
                                isCurrent: candidate.userFit.id == currentResult.userFit.id
                            )
                        }
                    }

                    if let betterCandidate {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("현재 상품은 ‘\(betterCandidate.userFit.displayName)’이 더 가까운 기준 옷으로 보입니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            SecondaryButton(title: "이번 비교에서 이 옷으로 보기", systemImage: "arrow.triangle.2.circlepath") {
                                _ = compare(with: betterCandidate.userFit)
                            }
                        }
                        .padding(14)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var reasonCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "추천 이유")

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(recommendationReasons, id: \.self) { reason in
                        ReasonBullet(text: reason)
                    }
                }
            }
        }
    }

    private var measurementDifferenceCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: currentResult.comparisonMode == .standardSizeFallback ? "기준표 차이" : "실측 차이",
                    subtitle: currentResult.comparisonMode == .standardSizeFallback
                        ? "선택한 두 사이즈의 기준표 가슴둘레 차이입니다."
                        : "상품 실측과 기준 옷의 차이입니다."
                )

                if currentResult.comparisonMode == .standardSizeFallback {
                    InfoRow(title: "가슴", value: currentResult.trueToSizeRecommendation)
                } else {
                    ProductMeasurementDifferenceGrid(
                        measurements: currentResult.recommendedSize.measurements,
                        referenceMeasurements: currentResult.userFit.measurements,
                        differences: currentResult.measurementDifferences,
                        kinds: comparedMeasurementKinds
                    )
                }
            }
        }
    }

    private var comparisonCoverageCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isComparisonCoverageExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("비교 항목")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(comparedMeasurementKinds.count)개 사용")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isComparisonCoverageExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isComparisonCoverageExpanded {
                    VStack(spacing: 8) {
                        ForEach(v1MeasurementKinds, id: \.id) { kind in
                            ComparisonCoverageRow(
                                title: kind.title,
                                isCompared: comparedMeasurementKinds.contains(kind),
                                detail: comparisonCoverageDetail(for: kind)
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var fitRecommendationCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "핏별 추천")

                VStack(spacing: 10) {
                        FitRecommendationRow(
                            title: currentResult.trueToSizeRecommendation.isEmpty ? "정핏 추천" : "정핏으로 입으려면",
                        value: recommendedSizeName,
                        detail: "현재 기준으로는 \(recommendedSizeName)가 가장 적합합니다.",
                        isPrimary: true
                    )

                    if let oversizedSize {
                        FitRecommendationRow(
                            title: "오버핏으로 입으려면",
                            value: oversizedSize,
                            detail: "조금 더 여유 있는 착용감을 원할 때 참고하세요.",
                            isPrimary: false
                        )
                    }
                }
            }
        }
    }

    private var resultBottomActionBar: some View {
        VStack(spacing: 0) {
            Button {
                presentActiveSheet(.addToCloset)
            } label: {
                Label("내 옷장에 추가", systemImage: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var productThumbnail: some View {
        ProductThumbnailView(
            imageURLString: currentResult.product.imageURLString,
            category: currentResult.product.category,
            width: 90,
            height: 104,
            cornerRadius: 18
        )
    }

    private var confidenceText: String {
        comparedMeasurementKinds.isEmpty
            ? "핏 매칭률 계산 불가"
            : "핏 매칭률 \(currentResult.recommendationScore)%"
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
        case .chest, .underBust: return "tshirt"
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
        case .waist: return "허리"
        case .hip: return "엉덩이"
        case .thigh: return "허벅지"
        case .rise: return "밑위"
        case .hem: return "밑단"
        case .footLength: return "발길이"
        case .underBust: return "밑가슴"
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
        guard !comparedMeasurementKinds.isEmpty else { return "계산 불가" }
        switch currentResult.recommendationScore {
        case 90...: return "매우 잘 맞아요"
        case 80..<90: return "잘 맞아요"
        case 70..<80: return "비슷해요"
        default: return "참고해 주세요"
        }
    }

    private var comparisonReliability: ComparisonReliability {
        ComparisonReliability(comparedCount: comparedMeasurementKinds.count)
    }

    private var confidenceStatus: ConfidenceStatus {
        ConfidenceStatus(score: currentResult.recommendationScore)
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
        if currentResult.comparisonSchemaVersion >= 1 {
            return currentResult.comparedMeasurementUsages.map(\.kind)
        }
        return v1MeasurementKinds.filter {
            currentResult.recommendedSize.measurements.value(for: $0) > 0
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
        currentResult.comparisonMethod.contains("사용자 선택") ? "직접 선택한 기준 옷" : "자동 선택된 기준 옷"
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
        if currentResult.comparisonSchemaVersion >= 1,
           let exclusion = currentResult.measurementExclusions.first {
            let suffix = currentResult.measurementExclusions.count > 1
                ? " 외 \(currentResult.measurementExclusions.count - 1)개 항목도 상세에서 확인할 수 있어요."
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
        if currentResult.comparisonSchemaVersion >= 1,
           let exclusion = currentResult.measurementExclusions.first(where: { $0.kind == kind }) {
            return exclusion.reason.userMessage
        }
        return "상품 또는 기준 옷의 실측값이 없어 제외"
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
                isMatched: currentResult.userFit.isRepresentative,
                title: currentResult.userFit.isRepresentative ? "내 기준 옷" : "일반 옷"
            ),
            ComparisonConditionItem(
                isMatched: measurementCount >= 2,
                title: measurementCount > 0 ? "실측 \(measurementCount)개 비교" : "실측 부족"
            )
        ]
    }

    private var comparisonSummaryTitle: String {
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
        currentResult.recommendationScore > 0
            ? "핏 매칭률 \(currentResult.recommendationScore)%"
            : "핏 매칭률 정보 부족"
    }

    private var oversizedSize: String? {
        let value = currentResult.oversizedRecommendation
            .replacingOccurrences(of: "오버핏으로 입으려면", with: "")
            .replacingOccurrences(of: "추천", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayValue = value.displaySizeName
        return displayValue.isEmpty || displayValue == recommendedSizeName ? nil : displayValue
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

        if currentResult.comparisonSchemaVersion >= 1 {
            for exclusion in currentResult.measurementExclusions {
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
                (kind: kind, difference: currentResult.measurementDifferences.value(for: kind))
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

    private var fitMatchRanking: [FitMatchCandidate] {
        let targetGroup = currentResult.product.category.serviceGroup
        let sameCategoryFits = userFits.filter {
            $0.category.serviceGroup == targetGroup
        }

        return Array(
            RecommendationService()
                .rankedFitMatches(
                    product: currentResult.product,
                    productDetailCategory: currentResult.productDetailCategory,
                    userFits: sameCategoryFits
                )
                .prefix(3)
        )
    }

    private var betterCandidate: FitMatchCandidate? {
        guard currentResult.userFit.isRepresentative,
              let first = fitMatchRanking.first,
              first.userFit.id != currentResult.userFit.id else {
            return nil
        }

        return first
    }

    private func openShoppingMall() {
        guard let urlString = currentResult.product.sourceURLString,
              let url = URL(string: urlString) else {
            return
        }

        if isMusinsaProduct,
           let productCode = musinsaProductCode(from: url),
           let appURL = URL(string: "musinsa://app/goods/\(productCode)") {
            openURL(appURL) { accepted in
                if !accepted {
                    openURL(url)
                }
            }
            return
        }

        openURL(url)
    }

    private var isMusinsaProduct: Bool {
        currentResult.product.sourceDisplayName.localizedCaseInsensitiveContains("무신사")
            || currentResult.product.sourceDisplayName.localizedCaseInsensitiveContains("musinsa")
            || currentResult.product.sourceURLString?.localizedCaseInsensitiveContains("musinsa") == true
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

    private func compare(with item: UserFit) -> ResultReferenceComparisonOutcome {
        #if DEBUG
        print("[화면: 비교 결과][동작: 기준 옷 변경][상태: 시작] 기존기준옷=\(currentResult.userFit.displayName), 선택기준옷=\(item.displayName)")
        #endif

        let outcome = ResultReferenceComparisonPersistence.resolveAndSave(
            product: currentResult.product,
            selectedReferenceItem: item,
            productDetailCategory: currentResult.productDetailCategory,
            existingHistories: histories,
            modelContext: modelContext
        )

        switch outcome {
        case .success(let history):
            comparisonResult = history
            onResultPersisted?(history)
            #if DEBUG
            print("[화면: 비교 결과][동작: 변경 결과 저장][상태: 성공] 상품=\(history.product.name), 기준옷=\(history.userFit.displayName), 추천사이즈=\(history.recommendedSize.name)")
            print("[화면: 비교 결과][동작: 기준 옷 변경][상태: 성공] 기준옷=\(history.userFit.displayName), 추천사이즈=\(history.recommendedSize.name), 신뢰도=\(history.recommendationScore)")
            #endif
        case .insufficient(let evidence):
            #if DEBUG
            print("[화면: 비교 결과][동작: 기준 옷 변경][상태: 근거 부족] 기준옷=\(item.displayName), 비교항목=\(evidence?.comparedKinds.map(\.title).joined(separator: ",") ?? "없음"), 제외항목=\(evidence?.missingKinds.map(\.title).joined(separator: ",") ?? "확인 불가")")
            #endif
        case .saveFailed(let message):
            #if DEBUG
            print("[화면: 비교 결과][동작: 변경 결과 저장][상태: 실패] 오류=\(message), 기준옷=\(item.displayName)")
            #endif
        }

        return outcome
    }

    private func presentActiveSheet(_ sheet: RecommendationResultActiveSheet) {
        print("[RecommendationResultView] activeSheet -> \(sheet.logName)")
        activeSheet = nil
        DispatchQueue.main.async {
            activeSheet = sheet
        }
    }

    private func dismissActiveSheet() {
        print("[RecommendationResultView] activeSheet -> nil")
        activeSheet = nil
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

    init(comparedCount: Int) {
        switch comparedCount {
        case 4...:
            stars = "★★★★★"
            title = "매우 높음"
        case 3:
            stars = "★★★★☆"
            title = "높음"
        case 2:
            stars = "★★★☆☆"
            title = "보통"
        case 1:
            stars = "★★☆☆☆"
            title = "낮음"
        default:
            stars = "★☆☆☆☆"
            title = "매우 낮음"
        }
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

private enum RecommendationResultActiveSheet: Identifiable {
    case referencePicker
    case addToCloset

    var id: String {
        switch self {
        case .referencePicker:
            return "referencePicker"
        case .addToCloset:
            return "addToCloset"
        }
    }

    var logName: String {
        id
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

private struct ReportMeasurementRow: View {
    let title: String
    let productValue: Double
    let referenceValue: Double
    let difference: Double

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
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
            Text(value > 0 ? value.cmText : "정보 없음")
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
            Text(productValue > 0 && referenceValue > 0 ? difference.signedCmText : "비교 제외")
                .font(.caption.weight(.black))
                .foregroundStyle(productValue > 0 && referenceValue > 0 ? differenceSeverityColor : .secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 60, alignment: .trailing)
    }

    private var differenceSeverityColor: Color {
        switch abs(difference) {
        case 5...: return .red
        case 2..<5: return .orange
        default: return .green
        }
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

                    if candidate.userFit.isRepresentative {
                        Text("기준 옷")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
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

enum ResultReferenceComparisonPersistence {
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
}

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

private struct ResultReferencePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let userFits: [UserFit]
    let currentUserFit: UserFit
    let productDetailCategory: ClosetDetailCategory
    let productCategory: ClothingCategory
    let onSelect: (UserFit) -> ResultReferenceComparisonOutcome
    @State private var selectedItemID: UUID?
    @State private var insufficientEvidence: InsufficientComparisonEvidence?
    @State private var isShowingInsufficientEvidence = false
    @State private var isShowingReferenceComparison = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isShowingInsufficientEvidence {
                    insufficientEvidenceContent
                } else {
                    pickerHeader

                    if selectableFits.isEmpty {
                        emptyStateCard
                    } else {
                        VStack(spacing: 12) {
                            ForEach(selectableFits) { item in
                                ResultReferencePickerCard(
                                    item: item,
                                    productDetailCategory: productDetailCategory,
                                    isSelected: selectedItemID == item.id
                                ) {
                                    selectedItemID = item.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isShowingInsufficientEvidence {
                insufficientActionBar
            } else {
                bottomActionBar
            }
        }
    }

    private var insufficientEvidenceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardView(radius: 26, padding: 22) {
                VStack(spacing: 14) {
                    Image(systemName: "ruler")
                        .font(.title2.weight(.semibold))
                        .frame(width: 58, height: 58)
                        .background(Color.orange.opacity(0.14), in: Circle())
                        .foregroundStyle(.orange)

                    Text(saveErrorMessage ?? "이 옷은 측정 방식이 달라 추천에 필요한 실측 정보가 부족해요")
                        .font(.title3.weight(.black))
                        .multilineTextAlignment(.center)

                    Text(saveErrorMessage == nil ? "기존 추천 결과는 변경하지 않았습니다." : "기존 결과와 저장 기록은 그대로 유지했습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if saveErrorMessage == nil {
                CardView(radius: 24, padding: 20) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("확인된 비교 근거")
                            .font(.headline.weight(.black))

                        if let evidence = insufficientEvidence {
                            Text("선택한 옷 · \(evidence.referenceItem.displayName) / \(evidence.referenceItem.sizeName)")
                                .font(.subheadline.weight(.semibold))

                            evidenceRows(evidence)
                        } else {
                            Text("동일한 측정 기준으로 비교할 수 있는 항목이 없습니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isShowingReferenceComparison, let evidence = insufficientEvidence {
                referenceComparisonCard(evidence)
            }
        }
    }

    @ViewBuilder
    private func evidenceRows(_ evidence: InsufficientComparisonEvidence) -> some View {
        if evidence.comparedKinds.isEmpty {
            Text("비교 가능한 항목 · 없음")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("비교 가능한 항목 · \(evidence.comparedKinds.map(\.title).joined(separator: " · "))")
                .font(.subheadline.weight(.bold))
        }

        ForEach(evidence.comparisonResult.exclusions, id: \.kind) { exclusion in
            VStack(alignment: .leading, spacing: 3) {
                Text("\(exclusion.kind.title) · 비교 제외")
                    .font(.subheadline.weight(.semibold))
                Text(exclusion.reason.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func referenceComparisonCard(_ evidence: InsufficientComparisonEvidence) -> some View {
        CardView(radius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 13) {
                Text("참고용 비교")
                    .font(.headline.weight(.black))
                Text("추천 결과가 아니며, 비교 가능한 실측만 표시합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if evidence.comparisonResult.comparedItems.isEmpty {
                    Text("수치로 참고할 수 있는 항목이 없습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(evidence.comparisonResult.comparedItems, id: \.kind) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.kind.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("상품 \(item.productValue.cmText) · 내 옷 \(item.referenceValue.cmText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.signedDifference.signedCmText)
                                .font(.subheadline.weight(.black))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var pickerHeader: some View {
        CardView(radius: 26, padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "tshirt")
                    .font(.title3.weight(.black))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 48, height: 48)
                    .background(Color.primary, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("다른 옷과 비교")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                    Text("\(productCategory.rawValue) 안에서 비교 기준 옷을 직접 선택하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var emptyStateCard: some View {
        CardView(radius: 24, padding: 24) {
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, height: 58)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())

                Text("선택할 수 있는 다른 옷이 없습니다.")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("\(productCategory.rawValue) 카테고리의 옷을 먼저 등록해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if selectedItemID == nil, !selectableFits.isEmpty {
                Label("비교할 옷을 선택해 주세요.", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard let selectedItem else {
                    return
                }

                switch onSelect(selectedItem) {
                case .success:
                    dismiss()
                case .insufficient(let evidence):
                    insufficientEvidence = evidence
                    saveErrorMessage = nil
                    isShowingReferenceComparison = false
                    isShowingInsufficientEvidence = true
                case .saveFailed:
                    insufficientEvidence = nil
                    saveErrorMessage = "변경 결과를 저장하지 못했어요. 다시 시도해 주세요."
                    isShowingReferenceComparison = false
                    isShowingInsufficientEvidence = true
                }
            } label: {
                Text("선택한 옷으로 비교")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(selectedItem == nil ? .secondary : Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        selectedItem == nil ? Color(.secondarySystemGroupedBackground) : Color.black,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var insufficientActionBar: some View {
        VStack(spacing: 10) {
            Button {
                isShowingInsufficientEvidence = false
                isShowingReferenceComparison = false
                insufficientEvidence = nil
                saveErrorMessage = nil
                selectedItemID = nil
            } label: {
                Text("다른 옷 선택")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingReferenceComparison.toggle()
                }
            } label: {
                Text(isShowingReferenceComparison ? "참고용 비교 접기" : "참고용 비교")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(insufficientEvidence == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var selectedItem: UserFit? {
        guard let selectedItemID else {
            return nil
        }

        return selectableFits.first { $0.id == selectedItemID }
    }

    private var selectableFits: [UserFit] {
        userFits
            .filter { $0.id != currentUserFit.id }
            .filter { $0.category.serviceGroup == productCategory.serviceGroup }
            .sorted { lhs, rhs in
                if lhs.detailCategory == productDetailCategory && rhs.detailCategory != productDetailCategory {
                    return true
                }
                if lhs.isRepresentative != rhs.isRepresentative {
                    return lhs.isRepresentative
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
}

private struct ResultReferencePickerCard: View {
    let item: UserFit
    let productDetailCategory: ClosetDetailCategory
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            CardView(
                radius: 22,
                padding: 14,
                background: isSelected ? Color.black : Color(.systemBackground)
            ) {
                HStack(alignment: .center, spacing: 14) {
                    thumbnail

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Text(item.brandName)
                                .font(.caption.weight(.black))
                                .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.72) : .secondary)
                                .lineLimit(1)

                            if item.isRepresentative {
                                pickerBadge("기준 옷", isEmphasized: isSelected)
                            }

                            if item.detailCategory == productDetailCategory {
                                pickerBadge("같은 종류", isEmphasized: isSelected)
                            }

                            Spacer(minLength: 0)
                        }

                        Text(item.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("\(item.category.rawValue) / \(item.detailCategory.rawValue) · \(item.sizeName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.72) : .secondary)
                            .lineLimit(1)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ProductThumbnailView(
            imageURLString: item.sourceProduct?.imageURLString,
            category: item.category,
            width: 68,
            height: 82,
            cornerRadius: 16
        )
    }

    private func pickerBadge(_ title: String, isEmphasized: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.black))
            .foregroundStyle(isEmphasized ? Color.primary : Color(.systemBackground))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(isEmphasized ? Color(.systemBackground) : Color.primary, in: Capsule())
    }
}

private extension String {
    var displaySizeName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("/") else {
            return value
        }

        return value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
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
