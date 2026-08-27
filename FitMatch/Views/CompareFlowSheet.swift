import SwiftUI
import SwiftData
import UIKit

struct CompareFlowSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \Brand.name) private var brands: [Brand]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]

    let initialURL: String?
    @StateObject private var viewModel: ShoppingProductViewModel
    @State private var step: CompareFlowStep = .start
    @State private var productURL = ""
    @State private var errorMessage: String?
    @State private var selectedReferenceItemID: UUID?
    @State private var statusMessage: String?
    @State private var registrationRoute: CompareProductRegistrationRoute?
    @State private var insufficientEvidence: InsufficientComparisonEvidence?
    @State private var isShowingMeasurementGuide = false
    @State private var isShowingReferenceComparison = false
    @State private var isShowingManualProductEntry = false
    @State private var referenceRegistrationRoute: ReferenceRegistrationRoute?
    @State private var isPreparingManualComparison = false
    @State private var isShowingSizeTableRecovery = false
    @State private var usesLegacySizeFailureScreen = false
    @State private var showsAllReferenceCandidates = false
    @State private var hasConfirmedComparisonCategory = false
    @State private var isSheetHeaderVisible = true
    @State private var preparedComparison: PreparedComparison?
    @State private var loadTask: Task<Void, Never>?
    @State private var hasStartedInitialURL = false
    @State private var isProcessingReferenceSelection = false
    @FocusState private var isURLFocused: Bool

    init(initialURL: String? = nil) {
        self.initialURL = initialURL
        _viewModel = StateObject(wrappedValue: ShoppingProductViewModel(initialURL: initialURL))
        _productURL = State(initialValue: initialURL ?? "")
    }

    @ViewBuilder
    var body: some View {
        if case .result(let history) = step {
            RecommendationResultView(result: history)
        } else {
            comparisonInputContent
        }
    }

    private var comparisonInputContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                switch step {
                case .start:
                    startContent
                case .loading:
                    loadingContent
                case .categoryConfirmation:
                    categoryConfirmationContent
                case .missingReference:
                    missingReferenceContent
                case .closetSelection:
                    closetSelectionContent
                case .insufficientEvidence:
                    insufficientEvidenceContent
                case .result:
                    EmptyView()
                case .error:
                    errorContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .hidesTopChromeOnScroll($isSheetHeaderVisible)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isURLFocused = false
        }
        .onAppear {
            guard !hasStartedInitialURL,
                  let initialURL,
                  !initialURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            hasStartedInitialURL = true
            startCompareTask(with: initialURL)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            viewModel.cancelProductLoading()
        }
        .onChange(of: userFits.count) { _, _ in
            guard step == .missingReference || step == .closetSelection else { return }
            rebuildPreparedComparison()
        }
        .sheet(item: $registrationRoute) { route in
            AddComparedProductToClosetSheet(
                product: route.product,
                productDetailCategory: route.productDetailCategory,
                recommendedSize: route.recommendedSize,
                preselectedCategory: route.preselectedCategory,
                preselectedClassification: route.preselectedClassification,
                isParsedProductReadOnly: true,
                startsAtRegistrationConfirmation: true
            ) { savedItem in
                handleRegisteredClosetItem(savedItem, context: route.context)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingMeasurementGuide) {
            MeasurementMethodGuideSheet(
                missingKinds: insufficientEvidence?.missingKinds ?? [],
                category: viewModel.category
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let statusMessage {
                FitMatchSuccessToast(message: statusMessage)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $isShowingManualProductEntry) {
            NavigationStack {
                ManualComparisonProductEntrySheet(viewModel: viewModel) {
                    isShowingManualProductEntry = false
                    isPreparingManualComparison = true
                    setStep(.loading)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        continueComparisonAfterProductInput()
                        isPreparingManualComparison = false
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $referenceRegistrationRoute) { route in
            switch route {
            case .method:
                AddClosetMethodSheet(
                    onLink: { presentReferenceRegistration(.link) },
                    onManual: { presentReferenceRegistration(.manual) }
                )
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
            case .link:
                NavigationStack {
                    LinkClosetRegistrationView(prefersRepresentativeByDefault: true) {
                        completeReferenceRegistration()
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .manual:
                NavigationStack {
                    AddClosetItemView(
                        prefillCategory: viewModel.category,
                        prefillDetailCategory: viewModel.detailCategory,
                        prefillGender: currentProduct?.productTargetGender,
                        prefersRepresentativeByDefault: true
                    ) { item in
                        modelContext.insert(item)
                        do {
                            try modelContext.save()
                            completeReferenceRegistration()
                            return true
                        } catch {
                            modelContext.rollback()
                            return false
                        }
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingSizeTableRecovery) {
            NavigationStack {
                SizeTableRecoveryView(
                    viewModel: viewModel,
                    onCancel: {
                        usesLegacySizeFailureScreen = true
                    },
                    onComplete: {
                        isShowingSizeTableRecovery = false
                        isPreparingManualComparison = true
                        setStep(.loading)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            continueComparisonAfterProductInput()
                            isPreparingManualComparison = false
                        }
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
    }
}

private struct PreparedComparison {
    let product: Product
    let automaticMatchResult: AutomaticComparisonMatchResult
    let referenceSelectionPlan: ReferenceSelectionPlan
    let sourceCategoryHistoryMatches: [SourceCategoryHistoryMatch]
    let allSimilarClosetCandidates: [UserFit]
}

private extension CompareFlowSheet {
    var startContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: "상품 비교 시작", subtitle: "새 상품을 내 옷과 비교해 가장 비슷한 사이즈를 찾아보세요.")

            directURLInputCard
            shoppingShortcutCard
        }
    }

    var loadingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(
                title: isPreparingManualComparison ? "비교를 준비하고 있어요" : "상품을 분석하고 있어요",
                subtitle: "잠시만 기다려 주세요."
            )

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    FitMatchLoadingRow(
                        title: "상품 정보 불러오는 중",
                        state: loadingState(for: .loadingProductInfo)
                    )
                    FitMatchLoadingRow(
                        title: isPreparingManualComparison ? "입력한 사이즈 확인 완료" : "사이즈표 확인 중",
                        state: loadingState(for: .loadingSizeChart)
                    )
                    FitMatchLoadingRow(
                        title: "내 옷과 비교 준비 중",
                        state: loadingState(for: .preparingComparison)
                    )

                    Text(isPreparingManualComparison ? "입력한 실측 정보와 비교할 수 있는 내 옷을 확인하고 있어요." : "평균 10~20초 소요됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
    }

    func loadingState(for phase: ProductAnalysisPhase) -> FitMatchLoadingState {
        if isPreparingManualComparison {
            return phase == .preparingComparison ? .loading : .done
        }
        if viewModel.analysisPhase == phase {
            return .loading
        }
        return viewModel.analysisPhase.rawValue > phase.rawValue ? .done : .waiting
    }

    var missingReferenceContent: some View {
        VStack(spacing: 20) {
            Image(systemName: categorySymbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 86, height: 86)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())

            VStack(spacing: 8) {
                Text(missingReferencePresentation.title)
                    .font(.title2.weight(.black))
                    .multilineTextAlignment(.center)

                Text(missingReferencePresentation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if allSimilarClosetCandidates.isEmpty {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("가져온 상품")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(currentProduct?.name ?? viewModel.productName)
                            .font(.headline.weight(.bold))
                        Text("FitMatch 분류 · \(viewModel.category.serviceGroup.rawValue) / \(viewModel.detailCategory.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("현재 내 옷장")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(closetCategorySummary)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            VStack(spacing: 11) {
                if allSimilarClosetCandidates.isEmpty {
                    PrimaryButton(title: missingReferencePresentation.registrationButtonTitle, systemImage: "plus.circle.fill") {
                        referenceRegistrationRoute = .method
                    }

                    SecondaryButton(title: "다른 상품 비교하기", systemImage: "arrow.left.arrow.right") {
                        productURL = ""
                        preparedComparison = nil
                        errorMessage = nil
                        statusMessage = nil
                        setStep(.start)
                    }
                } else {
                    PrimaryButton(title: "내 옷장에서 기준 옷 선택", systemImage: "list.bullet.rectangle") {
                        showsAllReferenceCandidates = false
                        setStep(.closetSelection)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    var categoryConfirmationContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(
                title: "상품 종류 확인",
                subtitle: "이 상품의 종류를 선택해 주세요."
            )

            if viewModel.productAnalysisRecoveryAction == .confirmCategoryBeforeMeasurements,
               let notice = viewModel.parserNotice {
                FitMatchCard {
                    Label(notice, systemImage: "checklist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let product = currentProduct {
                productCompactCard(product)
            }

            FitMatchCard {
                VStack(alignment: .leading, spacing: 14) {
                    if sourceCategoryHistoryMatches.count > 1 {
                        CompareSheetSectionTitle(
                            title: "어떤 분류로 비교할까요?",
                            subtitle: "이 쇼핑몰 카테고리가 여러 종류의 옷으로 등록된 적이 있어요. 비교할 분류를 선택해 주세요."
                        )

                        VStack(spacing: 10) {
                            ForEach(sourceCategoryHistoryMatches) { match in
                                Button {
                                    applySourceCategoryHistoryMatch(match)
                                    confirmComparisonCategoryAndContinue()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(match.title)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.primary)
                                            Text(match.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 54)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()
                    }

                    CompareSheetSectionTitle(
                        title: "상품 분류",
                        subtitle: "선택한 분류는 이 상품에 저장되며 다음부터 자동으로 적용돼요."
                    )

                    CompareSelectionMenu(title: comparisonCategoryTitle) {
                        ForEach(comparisonCategoryOptions) { category in
                            Button(category.rawValue) {
                                viewModel.category = category
                                viewModel.detailCategory = .other
                                hasConfirmedComparisonCategory = false
                                rebuildPreparedComparison()
                            }
                        }
                    }

                    CompareSelectionMenu(title: comparisonDetailCategoryTitle) {
                        ForEach(comparisonDetailCategoryOptions) { detailCategory in
                            Button(detailCategory.rawValue) {
                                viewModel.detailCategory = detailCategory
                                hasConfirmedComparisonCategory = false
                                rebuildPreparedComparison()
                            }
                        }
                    }
                    .disabled(viewModel.category == .other)
                    .opacity(viewModel.category == .other ? 0.5 : 1)
                }
            }

            PrimaryButton(title: "비교하기", systemImage: "sparkles") {
                confirmComparisonCategoryAndContinue()
            }
            .disabled(!canConfirmComparisonCategory)
        }
    }

    var closetSelectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(
                title: "비교할 옷 선택",
                subtitle: "자동으로 선택할 기준 옷이 없어요. 내 옷장에서 비교할 옷을 직접 선택해 주세요."
            )

            if allSimilarClosetCandidates.isEmpty {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("비교 가능한 옷이 없습니다.")
                            .font(.headline.weight(.bold))
                        Text("실측 정보가 있는 옷을 내 옷장에 등록한 뒤 다시 시도해 주세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                referenceSelectionSituationCard

                if !recommendedReferenceCandidates.isEmpty {
                    recommendedCandidateSection
                }

                if showsAllReferenceCandidates || recommendedReferenceCandidates.isEmpty {
                    closetCandidateSection(title: "추가 비교 가능 옷", items: additionalDirectSelectionCandidates)
                    closetCandidateSection(
                        title: hasSleeveLengthExpansionCandidate ? "부분 비교 가능한 옷" : "유사한 종류의 옷",
                        items: extendedSelectionCandidates
                    )
                }

                if !manualSelectionCandidates.isEmpty, !recommendedReferenceCandidates.isEmpty {
                    SecondaryButton(
                        title: showsAllReferenceCandidates ? "비교 범위 접기" : "비교 범위 넓히기",
                        systemImage: showsAllReferenceCandidates ? "chevron.up" : "list.bullet"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsAllReferenceCandidates.toggle()
                        }
                    }
                }
            }
        }
    }

    var referenceSelectionSituationCard: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: hasMatchingStructureCandidate ? "hand.tap.fill" : "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(referenceSelectionSituationTitle)
                        .font(.headline.weight(.bold))
                    Text(referenceSelectionSituationDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !hasMatchingStructureCandidate {
                        Text(hasSleeveLengthExpansionCandidate
                            ? "소매 길이가 달라 자동으로 선택하지 않았어요."
                            : "옷의 종류가 달라 자동으로 선택하지 않았어요.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    var recommendedCandidateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompareSheetSectionTitle(
                title: hasMatchingStructureCandidate
                    ? "비교할 기준 옷"
                    : (hasSleeveLengthExpansionCandidate ? "부분 비교 가능한 옷" : "비교 가능한 유사한 옷"),
                subtitle: hasMatchingStructureCandidate
                    ? "같은 종류 중 실측 방식이 가까운 순서입니다."
                    : "공통 실측이 많고 측정 방식이 가까운 순서입니다."
            )
            ForEach(recommendedReferenceCandidates) { candidate in
                Button {
                    guard !isProcessingReferenceSelection else { return }
                    isProcessingReferenceSelection = true
                    selectedReferenceItemID = candidate.id
                    Task {
                        await calculateAndSaveTemporaryRecommendation(
                            selectedReferenceItem: candidate.userFit
                        )
                    }
                } label: {
                    ClosetReferenceChoiceCard(
                        item: candidate.userFit,
                        compatibilityNote: candidate.selectionReason,
                        recommendationBadge: recommendedCandidateBadge(candidate)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessingReferenceSelection)
            }
        }
    }

    @ViewBuilder
    func closetCandidateSection(title: String, items: [UserFit]) -> some View {
        if !items.isEmpty {
            LazyVStack(alignment: .leading, spacing: 12) {
                CompareSheetSectionTitle(title: title)
                ForEach(items) { item in
                    Button {
                        guard !isProcessingReferenceSelection else { return }
                        isProcessingReferenceSelection = true
                        selectedReferenceItemID = item.id
                        Task {
                            await calculateAndSaveTemporaryRecommendation(
                                selectedReferenceItem: item
                            )
                        }
                    } label: {
                        ClosetReferenceChoiceCard(
                            item: item,
                            compatibilityNote: currentProduct.flatMap {
                                RecommendationService().manualCandidateNote(
                                    product: $0,
                                    productDetailCategory: viewModel.detailCategory,
                                    item: item
                                )
                            },
                            recommendationBadge: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessingReferenceSelection)
                }
            }
        }
    }

    @ViewBuilder
    var errorContent: some View {
        if SizeTableRecoveryFeature.isEnabled,
           isAutomaticMusinsaSizeFailure,
           !usesLegacySizeFailureScreen {
            sizeTableRecoveryEntryContent
        } else {
            legacyErrorContent
        }
    }

    var sizeTableRecoveryEntryContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("사이즈표를 자동으로 확인하지 못했어요")
                    .font(.title2.weight(.black))
                Text("판매 페이지에 사이즈표가 있지만 제공 형식이나 이미지 구성 때문에 자동으로 읽지 못했어요. 사이즈표를 추가하면 바로 비교할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            failedProductCard

            PrimaryButton(
                title: recoveryPrimaryButtonTitle,
                systemImage: recoveryPrimaryButtonSystemImage
            ) {
                isShowingSizeTableRecovery = true
            }

            Button("기존 화면으로 돌아가기") {
                usesLegacySizeFailureScreen = true
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    var failedProductCard: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 14) {
                ProductThumbnailView(
                    imageURLString: viewModel.productImageURLString,
                    category: viewModel.category,
                    width: 82,
                    height: 98,
                    cornerRadius: 16
                )
                VStack(alignment: .leading, spacing: 7) {
                    Text(viewModel.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "브랜드 미상" : viewModel.brand)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "상품명 미상" : viewModel.productName)
                        .font(.headline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(currentSourceCategoryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var recoveryPrimaryButtonTitle: String {
        switch viewModel.sizeTableRecoveryContext?.failure {
        case .imageCandidatesAvailable: "사이즈표 이미지 선택"
        case .incompleteOCR: "인식 결과 확인"
        case .noImageCandidates, .none: "사진에서 불러오기"
        }
    }

    var recoveryPrimaryButtonSystemImage: String {
        switch viewModel.sizeTableRecoveryContext?.failure {
        case .imageCandidatesAvailable: "photo.on.rectangle.angled"
        case .incompleteOCR: "tablecells"
        case .noImageCandidates, .none: "photo.badge.plus"
        }
    }

    var legacyErrorContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if isUnsupportedTopBottomSet {
                    Text(MusinsaParser.unsupportedTopBottomSetNotice)
                        .font(.title2.weight(.black))
                        .multilineTextAlignment(.center)
                } else {
                    Text(viewModel.serverAuthorityState.productLoadFailureTitle
                         ?? (isAutomaticMusinsaSizeFailure
                             ? "상품 정보를 불러왔어요."
                             : "상품 정보를 불러오지 못했어요."))
                        .font(.title2.weight(.black))
                    Text(isAutomaticMusinsaSizeFailure
                         ? "판매 페이지에 사이즈표가 있지만 제공 형식이나 이미지 구성 때문에 자동으로 읽지 못했어요. 사이즈표를 확인한 뒤 직접 입력해 주세요."
                         : (errorMessage ?? "URL을 다시 확인해 주세요."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if isAutomaticMusinsaSizeFailure {
                FitMatchCard {
                    HStack(alignment: .top, spacing: 14) {
                        ProductThumbnailView(
                            imageURLString: viewModel.productImageURLString,
                            category: viewModel.category,
                            width: 82,
                            height: 98,
                            cornerRadius: 16
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            Text(viewModel.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "브랜드 미상" : viewModel.brand)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(viewModel.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "상품명 미상" : viewModel.productName)
                                .font(.headline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(currentSourceCategoryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            PrimaryButton(
                title: isAutomaticMusinsaSizeFailure
                    ? "상품 사이즈 직접 입력"
                    : (viewModel.isNetworkFailure ? "다시 시도" : "다시 입력하기"),
                systemImage: isAutomaticMusinsaSizeFailure ? "square.and.pencil" : "arrow.clockwise"
            ) {
                if isAutomaticMusinsaSizeFailure {
                    isShowingManualProductEntry = true
                } else if viewModel.isNetworkFailure {
                    startCompareTask(with: productURL)
                } else {
                    setStep(.start)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    var isAutomaticMusinsaSizeFailure: Bool {
        productURL.lowercased().contains("musinsa")
            && errorMessage == MusinsaParser.automaticSizeFailureNotice
    }

    var isUnsupportedTopBottomSet: Bool {
        errorMessage == MusinsaParser.unsupportedTopBottomSetNotice
    }

    @ViewBuilder
    var insufficientEvidenceContent: some View {
        if let evidence = insufficientEvidence {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    Text("추천 결과 아님")
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                        .foregroundStyle(.orange)

                    Image(systemName: "ruler")
                        .font(.system(size: 40, weight: .semibold))
                        .frame(width: 82, height: 82)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())

                    Text("추천하기에 실측 정보가 부족해요")
                        .font(.title2.weight(.black))
                        .multilineTextAlignment(.center)

                    Text(insufficientEvidenceRequirementText(evidence.comparisonResult))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                FitMatchCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CompareSheetSectionTitle(
                            title: "확인된 비교 근거",
                            subtitle: "현재 정보만으로는 사이즈를 추천하지 않아요."
                        )

                        Text("기준 옷 · \(evidence.referenceItem.displayName) / \(evidence.referenceItem.sizeName)")
                            .font(.subheadline.weight(.semibold))

                        if evidence.comparedKinds.isEmpty {
                            Text("같은 측정 기준으로 비교할 수 있는 실측 항목이 없어요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(evidence.comparedKinds.map(\.title).joined(separator: " · "))
                                .font(.subheadline.weight(.bold))
                        }

                        ForEach(evidence.comparisonResult.exclusions, id: \.kind) { exclusion in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(exclusion.kind.title) · 비교 제외")
                                    .font(.subheadline.weight(.semibold))
                                Text(exclusion.reason.userMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let detail = exclusion.definitionDetail {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if isShowingReferenceComparison {
                    referenceOnlyComparisonCard(evidence)
                }

                VStack(spacing: 11) {
                    PrimaryButton(title: "측정 방법 보기", systemImage: "ruler") {
                        isShowingMeasurementGuide = true
                    }

                    SecondaryButton(
                        title: isShowingReferenceComparison ? "참고용 비교 접기" : "참고용 비교 보기",
                        systemImage: "eye"
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isShowingReferenceComparison.toggle()
                        }
                    }

                    SecondaryButton(title: "다른 옷으로 비교", systemImage: "tshirt") {
                        selectedReferenceItemID = nil
                        setStep(.closetSelection)
                    }
                }

            }
        }
    }

    func referenceOnlyComparisonCard(_ evidence: InsufficientComparisonEvidence) -> some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                CompareSheetSectionTitle(
                    title: "참고용 비교",
                    subtitle: "현재 정보에서 가장 많은 실측을 비교할 수 있었던 사이즈는 \(evidence.productSize.name.displaySizeName)이에요. 추천 사이즈는 아니며 참고용으로만 확인해 주세요."
                )

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

    func insufficientEvidenceRequirementText(_ result: MeasurementComparisonResult) -> String {
        var text = "비교 가능한 실측은 \(result.comparedItems.count)개이며, 사이즈를 추천하려면 최소 \(result.minimumComparableCount)개가 필요해요."
        if result.minimumRequiredKindCount > 1 {
            let requiredNames = result.requiredKinds.map(\.title).joined(separator: "·")
            text += " 이 중 \(requiredNames)에서 \(result.minimumRequiredKindCount)개 이상 비교할 수 있어야 해요."
        }
        if !result.requiredAllKinds.isEmpty {
            let requiredNames = result.requiredAllKinds.map(\.title).joined(separator: "·")
            text += " \(requiredNames)은 꼭 필요한 비교 항목이에요."
        }
        return text
    }
}

private extension CompareFlowSheet {
    var directURLInputCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                CompareSheetSectionTitle(
                    title: "직접 링크 입력",
                    subtitle: "상품 URL을 붙여넣고 바로 비교합니다."
                )

                HStack(spacing: 10) {
                    TextField("상품 URL을 붙여넣어 주세요", text: $productURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .submitLabel(.search)
                        .focused($isURLFocused)
                        .onSubmit {
                            isURLFocused = false
                            startCompareTask(with: productURL)
                        }

                    Button {
                        productURL = UIPasteboard.general.string ?? ""
                    } label: {
                        Text("붙여넣기")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.5)
                }

                PrimaryButton(title: "비교하기", systemImage: "sparkles") {
                    isURLFocused = false
                    startCompareTask(with: productURL)
                }
                .disabled(productURL.trimmedForCompareFlow.isEmpty || viewModel.isLoadingProductInfo)
            }
        }
    }

    var shoppingShortcutCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                CompareSheetSectionTitle(title: "쇼핑몰 바로가기")

                HStack(alignment: .top, spacing: 10) {
                    ShoppingShortcutButton(title: "무신사", systemImage: "m.circle.fill", status: "상품추가", isEnabled: true) {
                        openMusinsa()
                    }

                    ShoppingShortcutButton(title: "유니클로", systemImage: "u.circle", status: "상품추가", isEnabled: true) {
                        openUniqlo()
                    }
                    ShoppingShortcutButton(title: "ZARA", systemImage: "z.circle", status: "준비중", isEnabled: false) {}
                }
            }
        }
    }

    func productCompactCard(_ product: Product) -> some View {
        FitMatchCard {
            productCompactRow(product: product)
        }
    }

    func productCompactRow(product: Product) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ProductThumbnailView(
                imageURLString: product.imageURLStringForDisplay,
                category: product.category,
                width: 72,
                height: 88,
                cornerRadius: 16
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(product.brand?.name ?? "브랜드 미상")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(product.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                Text("출처: \(product.sourceDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(productCompactCategoryText(for: product))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func sheetHeader(title: String, subtitle: String) -> some View {
        CollapsibleTopChrome(isVisible: isSheetHeaderVisible) {
            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }
}

private extension CompareFlowSheet {
    var currentProduct: Product? {
        preparedComparison?.product ?? makeProduct(insertBrandIfNeeded: false)
    }

    var automaticMatchResult: AutomaticComparisonMatchResult? {
        preparedComparison?.automaticMatchResult
    }

    var referenceSelectionPlan: ReferenceSelectionPlan? {
        preparedComparison?.referenceSelectionPlan
    }

    var comparisonCategoryOptions: [ClothingCategory] {
        ClothingCategory.closetCategories(for: comparisonTargetGender)
            .filter { $0 != .other }
    }

    var comparisonDetailCategoryOptions: [ClosetDetailCategory] {
        ClosetDetailCategory.options(for: viewModel.category, gender: comparisonTargetGender)
            .filter { $0 != .other }
    }

    var comparisonTargetGender: UserGender {
        UserGender.productTarget(from: viewModel.productMetadata.genderCodes)
    }

    var comparisonCategoryTitle: String {
        viewModel.category == .other ? "대분류 선택" : viewModel.category.rawValue
    }

    var comparisonDetailCategoryTitle: String {
        viewModel.detailCategory == .other ? "세부 카테고리 선택" : viewModel.detailCategory.rawValue
    }

    var canConfirmComparisonCategory: Bool {
        guard let classification = currentParsedClassification else { return false }
        return classification.isValid
    }

    var currentParsedClassification: ParsedClosetClassification? {
        if let product = currentProduct {
            return ParsedClosetClassification.resolve(product: product, detailCategory: viewModel.detailCategory)
        }
        return ParsedClosetClassification.resolve(
            category: viewModel.category,
            detailCategory: viewModel.detailCategory,
            sourceDepths: [viewModel.productMetadata.sourceCategoryDepth1,
                           viewModel.productMetadata.sourceCategoryDepth2,
                           viewModel.productMetadata.sourceCategoryDepth3,
                           viewModel.productMetadata.sourceCategoryDepth4],
            sourcePath: viewModel.productMetadata.sourceCategoryPath,
            productName: viewModel.productName
        )
    }

    func productCompactCategoryText(for product: Product) -> String {
        if hasConfirmedComparisonCategory, viewModel.detailCategory != .other {
            return "비교 분류: \(viewModel.category.serviceGroup.rawValue) / \(viewModel.detailCategory.rawValue)"
        }

        if let sourceCategoryText = strictSourceCategoryText(for: product) {
            return "쇼핑몰 카테고리: \(sourceCategoryText)"
        }

        return "쇼핑몰 카테고리: 카테고리 정보 없음"
    }

    func strictSourceCategoryText(for product: Product) -> String? {
        if let sourceCategoryPath = product.sourceCategoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceCategoryPath.isEmpty {
            return sourceCategoryPath
        }

        return nil
    }

    var sourceCategoryHistoryMatches: [SourceCategoryHistoryMatch] {
        preparedComparison?.sourceCategoryHistoryMatches ?? []
    }

    var currentSourceCategoryText: String {
        guard let product = currentProduct else { return "카테고리 정보 없음" }
        return strictSourceCategoryText(for: product) ?? "카테고리 정보 없음"
    }

    var allSimilarClosetCandidates: [UserFit] {
        preparedComparison?.allSimilarClosetCandidates ?? []
    }

    var recommendedReferenceCandidates: [FitMatchCandidate] {
        referenceSelectionPlan?.recommendedCandidates ?? []
    }

    var incomingComparisonProfile: ComparisonProfile? {
        guard let currentProduct else { return nil }
        return ComparisonProfileMatcher().profile(
            for: currentProduct,
            detailCategory: viewModel.detailCategory
        )
    }

    var matchingStructureCandidates: [UserFit] {
        guard let incomingComparisonProfile else { return [] }
        let matcher = ComparisonProfileMatcher()
        return allSimilarClosetCandidates.filter { item in
            let profile = matcher.profile(for: item)
            return profile.garmentFamily == incomingComparisonProfile.garmentFamily
                && (incomingComparisonProfile.lengthType == .unknown
                    || profile.lengthType == .unknown
                    || profile.lengthType == incomingComparisonProfile.lengthType)
        }
    }

    var hasMatchingStructureCandidate: Bool {
        !matchingStructureCandidates.isEmpty
    }

    var hasSleeveLengthExpansionCandidate: Bool {
        guard let currentProduct else { return false }
        return allSimilarClosetCandidates.contains { item in
            RecommendationService().manualCandidateNote(
                product: currentProduct,
                productDetailCategory: viewModel.detailCategory,
                item: item
            )?.contains("소매 길이가 달라") == true
        }
    }

    var comparisonGarmentDisplayName: String {
        guard let currentProduct, let profile = incomingComparisonProfile else {
            return viewModel.detailCategory.rawValue
        }
        let sourceText = [
            currentProduct.name,
            currentProduct.sourceCategoryPath,
            currentProduct.baseCategoryFullPath
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if ["카라티", "카라 티", "폴로셔츠", "폴로 셔츠", "polo shirt"]
            .contains(where: sourceText.contains) {
            return "카라티"
        }
        let length = profile.lengthType.displayName(for: profile.garmentFamily)
        if [.pants, .denim, .leggings].contains(profile.garmentFamily) {
            return length.isEmpty ? profile.garmentFamily.displayName : length
        }
        return length.isEmpty ? profile.garmentFamily.displayName : "\(length) \(profile.garmentFamily.displayName)"
    }

    var compatibleGarmentSummary: String {
        let matcher = ComparisonProfileMatcher()
        var names: [String] = []
        for item in allSimilarClosetCandidates {
            let profile = matcher.profile(for: item)
            let length = profile.lengthType.displayName(for: profile.garmentFamily)
            let name: String
            if [.pants, .denim, .leggings].contains(profile.garmentFamily) {
                name = length.isEmpty ? profile.garmentFamily.displayName : length
            } else {
                name = length.isEmpty ? profile.garmentFamily.displayName : "\(length) \(profile.garmentFamily.displayName)"
            }
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names.prefix(2).joined(separator: "·")
    }

    var referenceSelectionSituationTitle: String {
        if hasMatchingStructureCandidate {
            return "비교할 \(comparisonGarmentDisplayName)을 선택해 주세요"
        }
        if hasSleeveLengthExpansionCandidate {
            return "소매 길이가 다른 상의와 부분 비교할 수 있어요"
        }
        return "같은 종류의 기준 옷이 없어 유사한 옷을 보여드려요"
    }

    var referenceSelectionSituationDescription: String {
        if hasMatchingStructureCandidate {
            return "선택한 옷은 이번 비교에만 사용하며, 기존 기준 옷 설정은 변경되지 않아요."
        }
        if hasSleeveLengthExpansionCandidate {
            return "가슴·어깨·총장처럼 함께 비교할 수 있는 실측만 사용하고, 소매길이는 결과와 점수에서 제외해요. 비교할 옷을 직접 선택해 주세요."
        }
        return "같은 \(viewModel.category.serviceGroup.rawValue)에서 비교 가능한 실측 정보가 있는 \(compatibleGarmentSummary) \(allSimilarClosetCandidates.count)벌을 찾았어요. 비교할 옷을 직접 선택해 주세요."
    }

    var manualSelectionCandidates: [UserFit] {
        additionalDirectSelectionCandidates + extendedSelectionCandidates
    }

    var additionalDirectSelectionCandidates: [UserFit] {
        let recommendedIDs = Set(recommendedReferenceCandidates.map(\.id))
        return allSimilarClosetCandidates.filter { item in
            !recommendedIDs.contains(item.id)
        }
    }

    var extendedSelectionCandidates: [UserFit] {
        []
    }

    func referenceCompatibility(for item: UserFit) -> GarmentComparisonCompatibility? {
        guard let product = currentProduct else { return nil }
        return RecommendationService().comparisonCompatibility(
            product: product,
            productDetailCategory: viewModel.detailCategory,
            item: item
        )
    }

    func recommendedCandidateBadge(_ candidate: FitMatchCandidate) -> String? {
        guard let index = recommendedReferenceCandidates.firstIndex(where: { $0.id == candidate.id }) else {
            return nil
        }
        return index == 0 ? "가장 적합" : "추천 \(index + 1)"
    }

    var selectedReferenceItem: UserFit? {
        guard let selectedReferenceItemID else { return nil }
        return userFits.first { $0.id == selectedReferenceItemID }
    }

    var selectedReferenceComparisonNote: String {
        guard let product = currentProduct, let selectedReferenceItem else {
            return "호환 가능한 실측 항목만 비교합니다."
        }
        return RecommendationService().manualCandidateNote(
            product: product,
            productDetailCategory: viewModel.detailCategory,
            item: selectedReferenceItem
        ) ?? "호환 가능한 실측 항목만 비교합니다."
    }

    var categorySymbol: String {
        switch viewModel.category.serviceGroup {
        case .top: return "tshirt"
        case .bottom, .pants: return "figure.walk"
        case .outer: return "jacket"
        case .dress: return "figure.dress.line.vertical.figure"
        case .underwear: return "rectangle.on.rectangle"
        case .shirt, .knit: return "tshirt"
        case .shoes: return "shoeprints.fill"
        case .accessory: return "watch.analog"
        case .other: return "tshirt"
        }
    }

    var missingCompatibleGarmentMessage: String {
        guard !allSimilarClosetCandidates.isEmpty else {
            return "내 옷장에 이 상품과 비교할 수 있는 실측 옷이 아직 없어요."
        }
        guard let result = automaticMatchResult,
              result.state == .sameFamilyLengthConflict,
              result.incomingProfile.lengthType != .unknown,
              result.incomingProfile.garmentFamily != .unknown else {
            return "자동으로 선택할 기준 옷이 없어요. 내 옷장에서 비교할 옷을 직접 선택해 주세요."
        }
        return "자동으로 선택할 기준 옷이 없어요. 내 옷장에서 비교할 옷을 직접 선택해 주세요."
    }

    var missingReferencePresentation: MissingReferencePresentation {
        guard allSimilarClosetCandidates.isEmpty else {
            return MissingReferencePresentation(
                title: "비교할 옷 선택",
                message: missingCompatibleGarmentMessage,
                registrationButtonTitle: "비교할 기준 옷 등록하기"
            )
        }

        let productName = currentProduct?.name ?? viewModel.productName
        let garmentName = comparisonGarmentDisplayName
        if userFits.isEmpty {
            return MissingReferencePresentation(
                title: "\(garmentName)와 비교할 옷이 필요해요",
                message: "가져온 상품은 \(productName)이에요. 아직 내 옷장에 등록된 옷이 없어요. 평소 잘 맞는 \(garmentName)을 등록하면 이 상품과 비교할 수 있어요.",
                registrationButtonTitle: "\(garmentName) 등록하기"
            )
        }

        let targetGender = currentProduct?.productTargetGender ?? .unknown
        let targetIsChild = [UserGender.kids, .baby].contains(targetGender)
        let targetIsAdult = [UserGender.men, .women, .unisex].contains(targetGender)
        let hasChildGarment = userFits.contains {
            [UserGender.kids, .baby].contains($0.gender)
        }
        let hasAdultGarment = userFits.contains {
            [UserGender.men, .women, .unisex].contains($0.gender)
        }
        if targetIsChild, !hasChildGarment {
            return MissingReferencePresentation(
                title: "비교할 아동복이 없어요",
                message: "가져온 상품은 아동용 \(garmentName)이에요. 현재 내 옷장에는 성인 의류만 있어 서로 비교하지 않았어요. 평소 잘 맞는 아동용 \(garmentName)을 등록해 주세요.",
                registrationButtonTitle: "아동용 \(garmentName) 등록하기"
            )
        }
        if targetIsAdult, !hasAdultGarment {
            return MissingReferencePresentation(
                title: "비교할 성인 의류가 없어요",
                message: "가져온 상품은 성인용 \(garmentName)이에요. 현재 내 옷장에는 아동복만 있어 서로 비교하지 않았어요. 평소 잘 맞는 성인용 \(garmentName)을 등록해 주세요.",
                registrationButtonTitle: "성인용 \(garmentName) 등록하기"
            )
        }

        return MissingReferencePresentation(
            title: "비교할 \(garmentName)이 없어요",
            message: "가져온 상품은 \(productName)이에요. 현재 내 옷장에는 \(closetCategorySummary)이 있어요. 이 상품과 비교하려면 평소 잘 맞는 \(garmentName)을 등록해 주세요.",
            registrationButtonTitle: "\(garmentName) 등록하기"
        )
    }

    var closetCategorySummary: String {
        guard !userFits.isEmpty else { return "등록된 옷 없음" }
        let counts = Dictionary(grouping: userFits, by: { $0.category.serviceGroup.rawValue })
            .mapValues(\.count)
        let summaries = counts.keys.sorted().map { "\($0) \(counts[$0] ?? 0)벌" }
        if summaries.count <= 3 { return summaries.joined(separator: " · ") }
        return summaries.prefix(3).joined(separator: " · ") + " 외 \(summaries.count - 3)개 카테고리"
    }

}

private struct MissingReferencePresentation {
    let title: String
    let message: String
    let registrationButtonTitle: String
}

private enum ReferenceRegistrationRoute: String, Identifiable {
    case method
    case link
    case manual

    var id: String { rawValue }
}

private extension CompareFlowSheet {
    func presentReferenceRegistration(_ route: ReferenceRegistrationRoute) {
        referenceRegistrationRoute = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            referenceRegistrationRoute = route
        }
    }

    func completeReferenceRegistration() {
        referenceRegistrationRoute = nil
        statusMessage = "비교할 기준 옷을 등록했어요."
        rebuildPreparedComparison()
    }

    func startCompareTask(with urlString: String) {
        guard loadTask == nil, !viewModel.isLoadingProductInfo else { return }
        loadTask = Task {
            await startCompare(with: urlString)
            loadTask = nil
        }
    }

    func startCompare(with urlString: String) async {
        let trimmedURL = urlString.trimmedForCompareFlow
        guard !trimmedURL.isEmpty else { return }
        guard !viewModel.isLoadingProductInfo else { return }

        guard ProductURLSupport.isSupportedProductURL(trimmedURL) else {
            productURL = trimmedURL
            errorMessage = ProductURLParserError.unsupportedURL.errorDescription
            setStep(.error)
            return
        }

        productURL = trimmedURL
        viewModel.productURL = trimmedURL
        errorMessage = nil
        statusMessage = nil
        usesLegacySizeFailureScreen = false
        insufficientEvidence = nil
        isShowingReferenceComparison = false
        hasConfirmedComparisonCategory = false
        preparedComparison = nil
        setStep(.loading)

        let didLoad = await viewModel.loadProductInfoFromURL()
        guard !Task.isCancelled else { return }
        guard didLoad else {
            if viewModel.productAnalysisRecoveryAction == .confirmCategoryBeforeMeasurements {
                // Keep the parser's `.other` value as an internal fail-closed
                // sentinel only. The customer sees explicit category choices,
                // never a saved or comparable "기타/기타" product.
                viewModel.category = .other
                viewModel.detailCategory = .other
                errorMessage = nil
                setStep(.categoryConfirmation)
                return
            }
            errorMessage = viewModel.errorMessage ?? "상품 정보를 불러오지 못했어요. URL을 다시 확인해 주세요."
            #if DEBUG
            print("[화면: 상품 비교][동작: 상품 분석][상태: 실패] 오류=\(errorMessage ?? "알 수 없음")")
            #endif
            setStep(.error)
            return
        }

        continueComparisonAfterProductInput()
    }

    func continueComparisonAfterProductInput() {
        guard viewModel.hasServerConfirmedAuthority else {
            errorMessage = viewModel.errorMessage
                ?? "서버에서 상품 분류를 확정하지 못해 비교할 수 없습니다."
            setStep(.error)
            return
        }
        guard let product = makeProduct(insertBrandIfNeeded: false), !product.sizes.isEmpty else {
            errorMessage = "사이즈명과 실측값을 확인해 주세요."
            setStep(.error)
            return
        }
        guard product.classificationAuthorityProvenance == .serverConfirmed else {
            errorMessage = "서버에서 확정된 상품만 비교할 수 있습니다."
            setStep(.error)
            return
        }
        rebuildPreparedComparison(using: product)
        errorMessage = nil
        #if DEBUG
        print("[CompareFlowSheet] productName: \(product.name)")
        print("[CompareFlowSheet] category: \(viewModel.category.rawValue)")
        print("[CompareFlowSheet] detailCategory: \(viewModel.detailCategory.rawValue)")
        print("[CompareFlowSheet] automaticMatchState before user confirmation: \(String(describing: automaticMatchResult?.state))")
        print("[화면: 상품 비교][동작: 상품 분석][상태: 성공] 상품=\(product.name), 출처=\(product.sourceDisplayName), 사이즈수=\(product.sizes.count), 분류=\(viewModel.category.rawValue)/\(viewModel.detailCategory.rawValue)")
        #endif

        proceedWithServerConfirmedCategory(product: product)
    }

    func confirmComparisonCategoryAndContinue() {
        guard canConfirmComparisonCategory else {
            errorMessage = "내 옷장 분류를 선택해 주세요."
            return
        }

        if viewModel.productAnalysisRecoveryAction == .confirmCategoryBeforeMeasurements {
            resumeZARAComparisonAfterCategoryConfirmation()
            return
        }

        guard viewModel.hasServerConfirmedAuthority,
              let product = makeProduct(insertBrandIfNeeded: false),
              product.classificationAuthorityProvenance == .serverConfirmed else {
            errorMessage = "선택한 분류를 서버에서 확인하지 못했습니다."
            setStep(.error)
            return
        }
        proceedWithServerConfirmedCategory(product: product)
    }

    func proceedWithServerConfirmedCategory(product: Product) {
        hasConfirmedComparisonCategory = false
        rebuildPreparedComparison(using: product)

        guard let plan = referenceSelectionPlan else {
            logMissingReferenceDiagnostics(product: product)
            setStep(.missingReference)
            return
        }

        guard !plan.recommendedCandidates.isEmpty || !allSimilarClosetCandidates.isEmpty else {
            logMissingReferenceDiagnostics(product: product)
            setStep(.missingReference)
            return
        }

        if let automaticCandidate = plan.automaticallySelectedCandidate {
            selectedReferenceItemID = automaticCandidate.id
            Task {
                await calculateAndSaveRecommendation()
            }
            return
        }

        selectedReferenceItemID = nil
        showsAllReferenceCandidates = false
        setStep(.closetSelection)
    }

    func resumeZARAComparisonAfterCategoryConfirmation() {
        guard loadTask == nil, !viewModel.isLoadingProductInfo else { return }
        let confirmedCategory = viewModel.category
        let confirmedDetailCategory = viewModel.detailCategory
        errorMessage = nil
        setStep(.loading)

        loadTask = Task {
            let didLoad = await viewModel.resumeZARAParsingAfterCategoryConfirmation()
            guard !Task.isCancelled else {
                loadTask = nil
                return
            }

            if didLoad {
                rebuildPreparedComparison()
                loadTask = nil
                continueComparisonAfterProductInput()
                return
            }

            viewModel.category = confirmedCategory
            viewModel.detailCategory = confirmedDetailCategory

            loadTask = nil
            if viewModel.productAnalysisRecoveryAction == .enterMeasurementsManually {
                statusMessage = "상품 종류를 적용했어요. 비교할 실측값을 확인해 주세요."
                setStep(.categoryConfirmation)
                isShowingManualProductEntry = true
                return
            }

            errorMessage = viewModel.errorMessage ?? "ZARA 실측 정보를 불러오지 못했어요."
            setStep(.error)
        }
    }

    func applySourceCategoryHistoryMatch(_ match: SourceCategoryHistoryMatch) {
        viewModel.category = match.category
        viewModel.detailCategory = match.detailCategory
        hasConfirmedComparisonCategory = false
        rebuildPreparedComparison()
    }

    func rebuildPreparedComparison(using suppliedProduct: Product? = nil) {
        guard let product = suppliedProduct ?? makeProduct(insertBrandIfNeeded: false) else {
            preparedComparison = nil
            return
        }
        guard product.classificationAuthorityProvenance == .serverConfirmed else {
            preparedComparison = nil
            return
        }
        let comparableFits = userFits.filter {
            $0.classificationAuthorityProvenance?.isComparisonAuthority == true
                && hasComparableMeasurements($0)
        }
        let serverPendingPlan = serverPendingReferenceSelectionPlan(comparableFits)
        let pendingProfile = ComparisonProfileMatcher().profile(
            for: product,
            detailCategory: viewModel.detailCategory
        )
        preparedComparison = PreparedComparison(
            product: product,
            automaticMatchResult: AutomaticComparisonMatchResult(
                state: comparableFits.isEmpty ? .noCompatibleGarment : .compatible,
                incomingProfile: pendingProfile,
                compatibleCandidates: comparableFits
            ),
            referenceSelectionPlan: serverPendingPlan,
            sourceCategoryHistoryMatches: SourceCategoryHistoryMatcher.matches(
                for: product,
                detectedDetailCategory: viewModel.detailCategory,
                userFits: userFits
            ),
            allSimilarClosetCandidates: comparableFits.sorted {
                if $0.isRepresentative != $1.isRepresentative {
                    return $0.isRepresentative
                }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        )
    }

    func serverPendingReferenceSelectionPlan(
        _ items: [UserFit]
    ) -> ReferenceSelectionPlan {
        let sorted = items.sorted {
            if $0.isRepresentative != $1.isRepresentative {
                return $0.isRepresentative
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let candidates = sorted.map { item in
            let recordCount = item.measurementRecords.filter(\.isComparable).count
            let legacyCount = [
                item.shoulder, item.chest, item.totalLength, item.sleeveLength,
                item.waist, item.hip, item.thigh, item.rise, item.hem,
                item.footLength, item.underBust
            ].filter { $0.isFinite && $0 > 0 }.count
            return FitMatchCandidate(
                userFit: item,
                matchRate: 0,
                compatibleMeasurementCount: max(recordCount, legacyCount),
                selectionReason: "서버 비교 정책 확인 후 실측 비교"
            )
        }
        let representatives = candidates.filter(\.userFit.isRepresentative)
        return ReferenceSelectionPlan(
            recommendedCandidates: Array(candidates.prefix(3)),
            automaticallySelectedCandidate: representatives.count == 1
                ? representatives.first
                : nil
        )
    }

    func calculateAndSaveRecommendation() async {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        if let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }

        guard let history = await viewModel.calculateRecommendation(
            userFits: userFits,
            brand: brand,
            allowsGlobalFallback: false
        ) else {
            selectedReferenceItemID = nil
            if referenceSelectionPlan?.recommendedCandidates.isEmpty == false
                || !allSimilarClosetCandidates.isEmpty {
                errorMessage = nil
                statusMessage = viewModel.errorMessage
                showsAllReferenceCandidates = false
                setStep(.closetSelection)
            } else {
                errorMessage = viewModel.errorMessage
                    ?? "서버 비교 정책 또는 실측 조건을 충족하지 못했습니다."
                setStep(.error)
            }
            return
        }

        do {
            try saveUniqueHistory(history)
            #if DEBUG
            print("[화면: 상품 비교][동작: 추천 기록 저장][상태: 성공] 상품=\(history.product.name), 추천사이즈=\(history.recommendedSize.name), 기준옷=\(history.userFit.displayName)")
            #endif
            setStep(.result(history))
        } catch {
            modelContext.rollback()
            #if DEBUG
            print("[화면: 상품 비교][동작: 추천 기록 저장][상태: 실패] 오류=\(error.localizedDescription), 상품=\(history.product.name)")
            #endif
            errorMessage = "추천 결과를 저장하지 못했습니다. 다시 시도해 주세요."
            setStep(.error)
        }
    }

    func calculateAndSaveTemporaryRecommendation(selectedReferenceItem: UserFit) async {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        if let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }

        guard let history = await viewModel.calculateTemporaryRecommendation(
            selectedReferenceItem: selectedReferenceItem,
            brand: brand
        ) else {
            errorMessage = viewModel.errorMessage
                ?? "서버 비교 정책 또는 실측 조건을 충족하지 못했습니다."
            setStep(.error)
            isProcessingReferenceSelection = false
            return
        }

        do {
            try saveUniqueHistory(history)
            #if DEBUG
            print("[화면: 상품 비교][동작: 수동 비교 기록 저장][상태: 성공] 상품=\(history.product.name), 추천사이즈=\(history.recommendedSize.name), 기준옷=\(history.userFit.displayName)")
            #endif
            setStep(.result(history))
        } catch {
            modelContext.rollback()
            #if DEBUG
            print("[화면: 상품 비교][동작: 수동 비교 기록 저장][상태: 실패] 오류=\(error.localizedDescription), 상품=\(history.product.name)")
            #endif
            errorMessage = "추천 결과를 저장하지 못했습니다. 다시 시도해 주세요."
            isProcessingReferenceSelection = false
            setStep(.error)
        }
    }

    func makeProduct(insertBrandIfNeeded: Bool) -> Product? {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        if insertBrandIfNeeded, let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }
        return viewModel.makeProductForClosetRegistration(
            brand: brand,
            classificationWasUserConfirmed: hasConfirmedComparisonCategory
        )
    }

    func presentProductRegistration(
        product: Product? = nil,
        context: CompareProductRegistrationContext,
        productDetailCategory: ClosetDetailCategory? = nil,
        recommendedSize: ProductSize? = nil,
        preselectedCategory: ClothingCategory? = nil
    ) {
        guard let product = product ?? currentProduct else {
            errorMessage = "상품 정보를 찾을 수 없습니다. 다시 불러와 주세요."
            return
        }

        registrationRoute = CompareProductRegistrationRoute(
            product: product,
            context: context,
            productDetailCategory: productDetailCategory ?? viewModel.detailCategory,
            recommendedSize: recommendedSize,
            preselectedCategory: preselectedCategory,
            preselectedClassification: ParsedClosetClassification.resolve(
                product: product,
                detailCategory: productDetailCategory ?? viewModel.detailCategory
            )
        )
    }

    func handleRegisteredClosetItem(_: UserFit, context: CompareProductRegistrationContext) {
        registrationRoute = nil
        statusMessage = "보유한 옷으로 등록했어요."

        switch context {
        case .missingReference:
            withAnimation { statusMessage = "보유한 옷으로 등록했어요." }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            }
        case .result:
            break
        }
    }

    func hasComparableMeasurements(_ item: UserFit) -> Bool {
        if viewModel.measurementAvailability != .actualMeasurements {
            return item.category.serviceGroup == viewModel.category.serviceGroup
        }
        return viewModel.category
            .measurementKinds(detailCategory: viewModel.detailCategory, gender: item.gender)
            .contains { item.measurements.value(for: $0) > 0 }
    }

    func logMissingReferenceDiagnostics(product: Product) {
        #if DEBUG
        let sameCategory = userFits.filter { $0.category == product.category }
        let sameDetail = sameCategory.filter { $0.detailCategory == viewModel.detailCategory }
        let missingMeasurements = sameDetail.filter { !hasComparableMeasurements($0) }
        print("[CompareFlowSheet] missing reference diagnostics")
        print("[CompareFlowSheet] compare product category: \(product.category.rawValue)")
        print("[CompareFlowSheet] compare product detailCategory: \(viewModel.detailCategory.rawValue)")
        print("[CompareFlowSheet] total UserFit count: \(userFits.count)")
        print("[CompareFlowSheet] same category count: \(sameCategory.count)")
        print("[CompareFlowSheet] same category/detail count: \(sameDetail.count)")
        print("[CompareFlowSheet] excluded missing measurements count: \(missingMeasurements.count)")
        ComparisonProfileMatcher().candidateDiagnostics(
            product: product,
            productDetailCategory: viewModel.detailCategory,
            userFits: userFits
        ).forEach {
            print("[CompareFlowSheet] reference candidate diagnostic: \($0.logDescription)")
        }
        #endif
    }

    func existingBrand(named name: String) -> Brand? {
        let normalizedName = name.normalizedBrandName
        guard !normalizedName.isEmpty else { return nil }
        return brands.first { $0.normalizedName == normalizedName }
    }

    func saveUniqueHistory(_ history: RecommendationHistory) throws {
        try RecommendationHistoryStore.saveUnique(
            history,
            existing: histories,
            modelContext: modelContext
        )
    }

    func setStep(_ newStep: CompareFlowStep) {
        #if DEBUG
        print("[화면: 상품 비교][동작: 단계 전환][상태: 완료] 이전=\(step.koreanLogName), 다음=\(newStep.koreanLogName)")
        #endif
        withAnimation(.snappy(duration: 0.22)) {
            step = newStep
        }
    }

    func openMusinsa() {
        guard let url = URL(string: "https://musinsa.onelink.me/PvkC/7egjf3sd") else { return }
        UIApplication.shared.open(url)
    }

    func openCurrentMusinsaProduct() {
        let webValue = viewModel.productCanonicalURLString ?? productURL
        guard let webURL = URL(string: webValue), webURL.scheme != nil else {
            openMusinsa()
            return
        }

        let productID = viewModel.productCode
            ?? MusinsaURLResolver().extractProductID(from: webURL)
        guard let productID,
              let appURL = URL(string: "musinsa://goods/\(productID)"),
              UIApplication.shared.canOpenURL(appURL) else {
            UIApplication.shared.open(webURL)
            return
        }

        UIApplication.shared.open(appURL, options: [:]) { opened in
            if !opened {
                UIApplication.shared.open(webURL)
            }
        }
    }

    func openUniqlo() {
        guard let url = URL(string: "https://www.uniqlo.com/kr/ko/") else { return }
        UIApplication.shared.open(url)
    }
}

private enum CompareFlowStep: Equatable {
    case start
    case loading
    case categoryConfirmation
    case missingReference
    case closetSelection
    case insufficientEvidence
    case result(RecommendationHistory)
    case error

    static func == (lhs: CompareFlowStep, rhs: CompareFlowStep) -> Bool {
        lhs.logName == rhs.logName
    }

    var logName: String {
        switch self {
        case .start: return "start"
        case .loading: return "loading"
        case .categoryConfirmation: return "categoryConfirmation"
        case .missingReference: return "missingReference"
        case .closetSelection: return "closetSelection"
        case .insufficientEvidence: return "insufficientEvidence"
        case .result: return "result"
        case .error: return "error"
        }
    }

    var koreanLogName: String {
        switch self {
        case .start: return "비교 시작"
        case .loading: return "상품 분석"
        case .categoryConfirmation: return "분류 확인"
        case .missingReference: return "기준 옷 직접 선택 안내"
        case .closetSelection: return "기준 옷 직접 선택"
        case .insufficientEvidence: return "실측 정보 부족"
        case .result: return "비교 결과"
        case .error: return "오류"
        }
    }
}

private enum CompareProductRegistrationContext {
    case missingReference
    case result
}

private struct CompareProductRegistrationRoute: Identifiable {
    let id = UUID()
    let product: Product
    let context: CompareProductRegistrationContext
    let productDetailCategory: ClosetDetailCategory
    let recommendedSize: ProductSize?
    let preselectedCategory: ClothingCategory?
    let preselectedClassification: ParsedClosetClassification?
}

private struct ShoppingShortcutButton: View {
    let title: String
    let systemImage: String
    let status: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isEnabled ? Color(.systemBackground) : .secondary)
                    .frame(width: 44, height: 44)
                    .background(isEnabled ? Color.black : Color(.secondarySystemGroupedBackground), in: Circle())

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isEnabled ? Color(.systemBackground) : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isEnabled ? Color.black : Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isEnabled ? Color.black.opacity(0.12) : Color(.separator).opacity(0.14), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct CompareSheetSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompareSelectionMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ClosetReferenceChoiceCard: View {
    let item: UserFit
    let compatibilityNote: String?
    let recommendationBadge: String?

    var body: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 12) {
                ProductThumbnailView(
                    imageURLString: item.sourceProduct?.imageURLStringForDisplay,
                    category: item.category,
                    width: 58,
                    height: 70,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 6) {
                    if let recommendationBadge {
                        Text(recommendationBadge)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary, in: Capsule())
                    }

                    Text(item.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("\(item.sourceName) · \(item.sizeName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(item.category.rawValue) / \(item.detailCategory.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if item.isRepresentative {
                        Text("기준 옷")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }

                    if let compatibilityNote {
                        Label(compatibilityNote, systemImage: "info.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MeasurementMethodGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let missingKinds: [MeasurementKind]
    let category: ClothingCategory

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("추가로 확인하면 좋아요")
                            .font(.title2.weight(.black))
                        Text("기준 옷을 평평하게 놓고 FitMatch 기준으로 측정하면 비교 가능한 항목을 늘릴 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(uniqueMissingKinds) { kind in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "ruler")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 34, height: 34)
                                .background(.primary.opacity(0.08), in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(.subheadline.weight(.bold))
                                Text(guideText(for: kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("측정 방법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .font(.subheadline.weight(.bold))
                }
            }
        }
    }

    private var uniqueMissingKinds: [MeasurementKind] {
        var seen = Set<MeasurementKind>()
        return missingKinds.filter { seen.insert($0).inserted }
    }

    private func guideText(for kind: MeasurementKind) -> String {
        FitMatchMeasurementStandard.definition(for: kind, category: category).instruction
    }
}

private struct ManualComparisonProductEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ShoppingProductViewModel
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FitMatchCard {
                    HStack(alignment: .top, spacing: 14) {
                        ProductThumbnailView(
                            imageURLString: viewModel.productImageURLString,
                            category: viewModel.category,
                            width: 82,
                            height: 98,
                            cornerRadius: 16
                        )
                        VStack(alignment: .leading, spacing: 7) {
                            Text(viewModel.brand.isEmpty ? "브랜드 정보 없음" : viewModel.brand)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(viewModel.productName.isEmpty ? "상품명 정보 없음" : viewModel.productName)
                                .font(.headline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(viewModel.category.serviceGroup.rawValue) / \(viewModel.detailCategory.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                FitMatchCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(
                            title: "비교 분류 확인",
                            subtitle: "표시되는 실측 항목이 상품과 맞는지 확인해 주세요."
                        )

                        Menu {
                            ForEach(categoryOptions) { category in
                                Button(category.rawValue) {
                                    viewModel.category = category.serviceGroup
                                    viewModel.detailCategory = detailOptions(for: category).first ?? .other
                                }
                            }
                        } label: {
                            manualSelectionRow(title: "카테고리", value: viewModel.category.serviceGroup.rawValue)
                        }

                        Menu {
                            ForEach(detailOptions(for: viewModel.category)) { detail in
                                Button(detail.rawValue) {
                                    viewModel.detailCategory = detail
                                }
                            }
                        } label: {
                            manualSelectionRow(title: "세부 카테고리", value: viewModel.detailCategory.rawValue)
                        }
                    }
                }

                FitMatchCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(
                            title: "상품 사이즈 직접 입력",
                            subtitle: "판매 페이지의 사이즈표와 동일한 항목만 cm 단위로 입력해 주세요."
                        )

                        ForEach($viewModel.sizeOptions) { $option in
                            ManualComparisonSizeEditor(
                                option: $option,
                                category: viewModel.category,
                                detailCategory: viewModel.detailCategory,
                                canRemove: viewModel.sizeOptions.count > 1
                            ) {
                                viewModel.removeSizeOption(option)
                            }
                        }

                        SecondaryButton(title: "사이즈 추가", systemImage: "plus") {
                            viewModel.addSizeOption()
                        }

                        Text("둘레와 단면은 변환하지 말고, 화면에 표시된 항목과 같은 의미의 값만 입력해 주세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                PrimaryButton(title: "입력한 사이즈로 비교", systemImage: "sparkles") {
                    onContinue()
                }
                .disabled(!hasValidSize)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("상품 사이즈 입력")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") { dismiss() }
            }
        }
    }

    private var hasValidSize: Bool {
        viewModel.sizeOptions.contains {
            $0.makeSizeOption(
                category: viewModel.category,
                detailCategory: viewModel.detailCategory
            ) != nil
        }
    }

    private var categoryOptions: [ClothingCategory] {
        let gender = UserGender.productTarget(from: viewModel.productMetadata.genderCodes)
        let resolvedGender = gender == .unknown ? UserGender.unisex : gender
        return ClothingCategory.closetCategories(for: resolvedGender)
            .map(\.serviceGroup)
            .filter { $0 != .other }
            .reduce(into: []) { result, category in
                if !result.contains(category) { result.append(category) }
            }
    }

    private func detailOptions(for category: ClothingCategory) -> [ClosetDetailCategory] {
        let gender = UserGender.productTarget(from: viewModel.productMetadata.genderCodes)
        let resolvedGender = gender == .unknown ? UserGender.unisex : gender
        return ClosetDetailCategory.options(for: category.serviceGroup, gender: resolvedGender)
            .filter { $0 != .other }
    }

    private func manualSelectionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ManualComparisonSizeEditor: View {
    @Binding var option: ClothingSizeForm
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
    var allowsMeasurementShapeSelection: Bool = true
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("사이즈명 (예: M)", text: $option.sizeName)
                    .font(.headline)
                    .textInputAutocapitalization(.characters)
                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(measurementKinds) { kind in
                if kind == .chest, allowsMeasurementShapeSelection {
                    measurementShapePicker(
                        widthTitle: "가슴단면",
                        circumferenceTitle: "가슴둘레",
                        selection: $option.chestUsesCircumference
                    )
                } else if kind == .waist, allowsMeasurementShapeSelection {
                    measurementShapePicker(
                        widthTitle: "허리단면",
                        circumferenceTitle: "허리둘레",
                        selection: $option.waistUsesCircumference
                    )
                }
                MeasurementField(
                    title: measurementTitle(for: kind),
                    placeholder: kind.placeholder,
                    value: binding(for: kind)
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var measurementKinds: [MeasurementKind] {
        category.measurementKinds(detailCategory: detailCategory, gender: .unisex)
    }

    private func binding(for kind: MeasurementKind) -> Binding<String> {
        switch kind {
        case .shoulder: return $option.shoulder
        case .chest: return $option.chest
        case .totalLength: return $option.totalLength
        case .sleeveLength: return $option.sleeveLength
        case .upperAbdomen, .upperWaist: return .constant("")
        case .waist: return $option.waist
        case .hip: return $option.hip
        case .thigh: return $option.thigh
        case .rise: return $option.rise
        case .hem: return $option.hem
        case .footLength: return $option.footLength
        case .underBust: return $option.underBust
        }
    }

    private func measurementTitle(for kind: MeasurementKind) -> String {
        if kind == .chest {
            return option.chestUsesCircumference ? "가슴둘레" : "가슴단면"
        }
        if kind == .waist {
            return option.waistUsesCircumference ? "허리둘레" : "허리단면"
        }
        return kind.title
    }

    private func measurementShapePicker(
        widthTitle: String,
        circumferenceTitle: String,
        selection: Binding<Bool>
    ) -> some View {
        Picker("측정 형태", selection: selection) {
            Text(widthTitle).tag(false)
            Text(circumferenceTitle).tag(true)
        }
        .pickerStyle(.segmented)
    }
}

private extension String {
    var trimmedForCompareFlow: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displaySizeName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        let finalComponent = value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
        return SizeTokenNormalizer.displayName(for: finalComponent)
    }
}

private extension Double {
    var signedCmText: String {
        let sign = self > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", self))cm"
    }
}
