import SwiftUI
import SwiftData

struct RecommendationResultView: View {
    @Environment(\.openURL) private var openURL
    let result: RecommendationHistory
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @State private var comparisonResult: RecommendationHistory?
    @State private var isShowingReferencePicker = false

    private var currentResult: RecommendationHistory {
        comparisonResult ?? result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                productInfoCard
                referenceFitCard
                measurementDifferenceCard
                reasonCard
                fitRecommendationCard
                actionCard
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("추천 결과")
        .hidesTabBarOnScroll()
        .sheet(isPresented: $isShowingReferencePicker) {
            NavigationStack {
                ResultReferencePickerView(
                    userFits: userFits,
                    currentUserFit: currentResult.userFit
                ) { item in
                    compare(with: item)
                    isShowingReferencePicker = false
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("추천 사이즈는 \(currentResult.recommendedSize.name)입니다")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.78)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                Text(confidenceText)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(confidenceStatus.stars)
                        .font(.subheadline.weight(.black))
                    Text(confidenceStatus.title)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.86))
                Text("내 옷장 기준으로 가장 가까운 사이즈예요.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
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
                        InfoRow(title: "카테고리", value: "\(currentResult.product.category.rawValue) / \(currentResult.productDetailCategory.rawValue)")
                    }
                }
            }
        }
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

                HStack(spacing: 8) {
                    if currentResult.userFit.isRepresentative {
                        ResultBadge(title: "대표핏", systemImage: "heart.fill")
                    }
                    ResultBadge(title: currentResult.comparisonMethod, systemImage: comparisonIcon)
                }
                .fixedSize(horizontal: false, vertical: true)
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
                SectionHeader(title: "실측 차이", subtitle: "상품 실측과 기준 옷의 차이입니다.")

                ProductMeasurementDifferenceGrid(
                    measurements: currentResult.recommendedSize.measurements,
                    differences: currentResult.measurementDifferences,
                    category: currentResult.product.category,
                    detailCategory: currentResult.productDetailCategory
                )
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
                        value: currentResult.recommendedSize.name,
                        detail: "현재 기준으로는 \(currentResult.recommendedSize.name)가 가장 적합합니다.",
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

    private var actionCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                PrimaryButton(title: "구매하기", systemImage: "safari") {
                    openShoppingMall()
                }
                .disabled(currentResult.product.sourceURLString == nil)
                .opacity(currentResult.product.sourceURLString == nil ? 0.35 : 1)

                SecondaryButton(title: "기록 보기", systemImage: "clock") {
                    // TODO: ResultView가 탭 선택 상태를 받을 수 있게 되면 기록 탭으로 이동한다.
                }
                .disabled(true)
                .opacity(0.72)

                SecondaryButton(title: "다른 옷과 비교", systemImage: "tshirt") {
                    isShowingReferencePicker = true
                }
            }
        }
    }

    private var productThumbnail: some View {
        Group {
            if let productImageURL {
                AsyncImage(url: productImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        productImagePlaceholder
                    }
                }
            } else {
                productImagePlaceholder
            }
        }
        .frame(width: 90, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var productImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private var productImageURL: URL? {
        // TODO: Product 또는 RecommendationHistory에 imageURLString을 저장하면 실제 상품 썸네일을 연결한다.
        nil
    }

    private var confidenceText: String {
        currentResult.recommendationScore > 0
            ? "Fit Confidence \(currentResult.recommendationScore)%"
            : "Fit Confidence 정보 부족"
    }

    private var confidenceStatus: ConfidenceStatus {
        ConfidenceStatus(score: currentResult.recommendationScore)
    }

    private var oversizedSize: String? {
        let value = currentResult.oversizedRecommendation
            .replacingOccurrences(of: "오버핏으로 입으려면", with: "")
            .replacingOccurrences(of: "추천", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty || value == currentResult.recommendedSize.name ? nil : value
    }

    private var recommendationReasons: [String] {
        var reasons = strongestMeasurementReasons

        if currentResult.comparisonMethod.contains("세부카테고리") || currentResult.userFit.detailCategory == currentResult.productDetailCategory {
            reasons.append("같은 \(currentResult.productDetailCategory.rawValue) 기준으로 비교했습니다.")
        } else if currentResult.comparisonMethod.contains("대분류") {
            reasons.append("같은 \(currentResult.product.category.serviceGroup.rawValue) 대분류 기준으로 비교했습니다.")
        } else if currentResult.comparisonMethod.contains("임시") {
            reasons.append("임시 비교라 일부 항목은 참고용입니다.")
        }

        if let weightingNotice {
            reasons.append(weightingNotice)
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
        currentResult.product.category
            .measurementKinds(detailCategory: currentResult.productDetailCategory, gender: .unisex)
            .filter {
                currentResult.recommendedSize.measurements.value(for: $0) > 0
                    && currentResult.userFit.measurements.value(for: $0) > 0
            }
    }

    private func openShoppingMall() {
        guard let urlString = currentResult.product.sourceURLString,
              let url = URL(string: urlString) else {
            return
        }
        openURL(url)
    }

    private func compare(with item: UserFit) {
        guard let history = RecommendationService().recommend(
            product: currentResult.product,
            selectedReferenceItem: item,
            productDetailCategory: currentResult.productDetailCategory
        ) else {
            return
        }

        comparisonResult = history
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
        let absoluteDifference = abs(difference)

        if absoluteDifference <= 1 {
            return "\(subject)은 거의 비슷합니다."
        }

        if absoluteDifference <= 2 {
            return "\(subject)은 안정적인 차이입니다."
        }

        if absoluteDifference < 5 {
            if kind == .totalLength || kind == .sleeveLength {
                return difference > 0
                    ? "\(subject)은 약간 길게 느껴질 수 있습니다."
                    : "\(subject)은 약간 짧게 느껴질 수 있습니다."
            }

            return difference > 0
                ? "\(subject)은 약간 여유 있게 느껴질 수 있습니다."
                : "\(subject)은 조금 더 타이트하게 느껴질 수 있습니다."
        }

        return "\(subject)은 차이가 커서 핏이 달라질 수 있습니다."
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

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct ResultBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.08), in: Capsule())
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
    let differences: GarmentMeasurements
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory

    var body: some View {
        VStack(spacing: 10) {
            ForEach(kindsToShow) { kind in
                ProductMeasurementDifferenceRow(
                    title: kind.title,
                    value: measurements.value(for: kind),
                    difference: differences.value(for: kind)
                )
            }
        }
    }

    private var kindsToShow: [MeasurementKind] {
        let visibleKinds = measurementKinds.filter {
            measurements.value(for: $0) > 0
        }
        return visibleKinds.isEmpty ? measurementKinds : visibleKinds
    }

    private var measurementKinds: [MeasurementKind] {
        category.measurementKinds(detailCategory: detailCategory, gender: .unisex)
    }
}

private struct ProductMeasurementDifferenceRow: View {
    let title: String
    let value: Double
    let difference: Double

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: status.systemImage)
                .font(.headline)
                .foregroundStyle(status.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Text(value.cmText)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 12)

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var status: MeasurementDifferenceStatus {
        MeasurementDifferenceStatus(difference: abs(difference))
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

private struct ResultReferencePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let userFits: [UserFit]
    let currentUserFit: UserFit
    let onSelect: (UserFit) -> Void

    var body: some View {
        List {
            if selectableFits.isEmpty {
                Text("선택할 수 있는 다른 옷이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectableFits) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(item.category.rawValue) / \(item.detailCategory.rawValue) · \(item.sizeName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if item.isRepresentative {
                                Text("대표옷")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("다른 옷 선택")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }
        }
    }

    private var selectableFits: [UserFit] {
        userFits.filter { $0.id != currentUserFit.id }
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
