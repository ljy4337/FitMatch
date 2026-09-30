import PhotosUI
import SwiftUI

struct SizeTableRecoveryView: View {
    enum Purpose {
        case comparison
        case closetRegistration
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ShoppingProductViewModel
    var purpose: Purpose = .comparison
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImageData: Data?
    @State private var selectedSizeID: UUID?
    @State private var isAnalyzing = false
    @State private var showsManualEditor = false
    @State private var isManualEntry = false
    @State private var showsAnalysisFailureAlert = false
    @State private var validationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                productCard

                photoSection

                if selectedImageData != nil {
                    selectedImageSection
                }

                if isAnalyzing {
                    FitMatchCard {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("사이즈표를 분석하고 있어요.")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                if hasRecognizedRows {
                    sizeSelectionSection
                }

                if showsManualEditor, selectedSizeID != nil {
                    sizeConfirmationSection
                }

                if let message = validationMessage ?? viewModel.recoveryErrorMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if hasRecognizedRows || showsManualEditor {
                    PrimaryButton(title: comparisonButtonTitle, systemImage: "sparkles") {
                        complete()
                    }
                    .disabled(selectedSizeID == nil || isAnalyzing)
                }

                SecondaryButton(title: "직접 입력하기", systemImage: "square.and.pencil") {
                    prepareManualEntry()
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("이미지 분석")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") {
                    onCancel()
                    dismiss()
                }
            }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard let item = items.first else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    viewModel.recoveryErrorMessage = "선택한 사진을 불러오지 못했어요."
                    selectedPhotoItems = []
                    return
                }
                selectedSizeID = nil
                showsManualEditor = false
                isManualEntry = false
                validationMessage = nil
                viewModel.recoveryErrorMessage = nil
                viewModel.sizeOptions = [ClothingSizeForm()]
                selectedImageData = data
                await analyze(data: data)
                selectedPhotoItems = []
            }
        }
        .alert("이미지를 분석할 수 없어요", isPresented: $showsAnalysisFailureAlert) {
            Button("직접 입력") {
                prepareManualEntry()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이미지에서 사이즈 정보를 확인하지 못했어요. 사이즈를 직접 입력해 주세요.")
        }
    }

    private var productCard: some View {
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
                }
            }
        }
    }

    private var photoSection: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "사이즈표 사진 추가",
                    subtitle: "판매 페이지의 사이즈표를 캡처한 사진을 선택해 주세요."
                )
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 1,
                    matching: .images
                ) {
                    Label("사진에서 불러오기", systemImage: "photo.badge.plus")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing)
                .opacity(isAnalyzing ? 0.45 : 1)
            }
        }
    }

    @ViewBuilder
    private var selectedImageSection: some View {
        if let selectedImageData, let image = UIImage(data: selectedImageData) {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "선택한 원본", subtitle: "선택한 이미지를 원본 비율로 표시해요.")
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("선택한 사이즈표 이미지")
                }
            }
        }
    }

    @ViewBuilder
    private var sizeConfirmationSection: some View {
        if let selectedSizeIndex {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "사이즈 확인",
                        subtitle: "선택한 사이즈의 인식값을 확인하고 필요한 값만 수정해 주세요."
                    )
                    ManualComparisonSizeEditor(
                        option: $viewModel.sizeOptions[selectedSizeIndex],
                        category: viewModel.category,
                        detailCategory: viewModel.detailCategory,
                        allowsMeasurementShapeSelection: isManualEntry,
                        canRemove: false
                    ) {}
                }
            }
        }
    }

    private var sizeSelectionSection: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: purpose == .closetRegistration ? "저장할 사이즈 선택" : "비교할 사이즈 선택",
                    subtitle: purpose == .closetRegistration
                        ? "내 옷장에 추가할 사이즈를 하나 선택해 주세요."
                        : "인식된 사이즈 중 확인할 사이즈를 하나 선택해 주세요."
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(viewModel.sizeOptions) { option in
                        sizeSelectionButton(option)
                    }
                }
            }
        }
    }

    private func sizeSelectionButton(_ option: ClothingSizeForm) -> some View {
        let name = option.sizeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSelected = selectedSizeID == option.id

        return Button {
            selectedSizeID = option.id
            validationMessage = nil
        } label: {
            HStack(spacing: 8) {
                Text(name.isEmpty ? "사이즈 미입력" : name.fitMatchDisplaySizeName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                isSelected ? Color.black : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.black : Color(.separator).opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name.isEmpty ? "사이즈 미입력" : "\(name) 사이즈")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var comparisonButtonTitle: String {
        guard let selectedSize = selectedSize else {
            return purpose == .closetRegistration
                ? "저장할 사이즈를 선택해 주세요"
                : "비교할 사이즈를 선택해 주세요"
        }
        let name = selectedSize.sizeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if purpose == .closetRegistration {
            return name.isEmpty
                ? "선택한 사이즈로 계속하기"
                : "\(name.fitMatchDisplaySizeName) 사이즈로 계속하기"
        }
        return name.isEmpty
            ? "선택한 사이즈로 비교하기"
            : "\(name.fitMatchDisplaySizeName) 사이즈 비교하기"
    }

    private var selectedSize: ClothingSizeForm? {
        guard let selectedSizeID else { return nil }
        return viewModel.sizeOptions.first { $0.id == selectedSizeID }
    }

    private var selectedSizeIndex: Int? {
        guard let selectedSizeID else { return nil }
        return viewModel.sizeOptions.firstIndex { $0.id == selectedSizeID }
    }

    private var hasRecognizedRows: Bool {
        viewModel.sizeOptions.contains {
            !$0.sizeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func prepareManualEntry() {
        if !hasRecognizedRows {
            viewModel.sizeOptions = [ClothingSizeForm()]
        }
        selectedSizeID = viewModel.sizeOptions.count == 1 ? viewModel.sizeOptions[0].id : nil
        showsManualEditor = true
        isManualEntry = true
        validationMessage = nil
        viewModel.recoveryErrorMessage = nil
    }

    @MainActor
    private func analyze(data: Data) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        let didAnalyze = await viewModel.analyzeRecoveryImage(data: data)
        if didAnalyze {
            selectedSizeID = nil
            showsManualEditor = true
            isManualEntry = false
        } else {
            showsManualEditor = false
            showsAnalysisFailureAlert = true
        }
    }

    private func complete() {
        switch FitMatchSizeTableRecoveryAction.complete(
            selectedSize: selectedSize,
            viewModel: viewModel
        ) {
        case .blocked(let message):
            validationMessage = message
        case .completed:
            validationMessage = nil
            onComplete()
        }
    }
}
