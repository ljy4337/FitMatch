import PhotosUI
import SwiftUI

struct SizeTableRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ShoppingProductViewModel
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var selectedCandidateURLString: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isAnalyzing = false
    @State private var showsManualEditor = false
    @State private var validationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                productCard

                if !candidateURLStrings.isEmpty {
                    candidateSection
                }

                photoSection

                if showsManualEditor || hasRecognizedRows {
                    tableEditor
                }

                if let message = validationMessage ?? viewModel.recoveryErrorMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if hasRecognizedRows || showsManualEditor {
                    PrimaryButton(title: "이 사이즈표로 비교하기", systemImage: "sparkles") {
                        complete()
                    }
                }

                SecondaryButton(title: "직접 입력하기", systemImage: "square.and.pencil") {
                    prepareManualEntry()
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("사이즈표 복구")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") {
                    onCancel()
                    dismiss()
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    viewModel.recoveryErrorMessage = "선택한 사진을 불러오지 못했어요."
                    return
                }
                selectedImageData = data
                await analyze(data: data)
            }
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

    private var candidateSection: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "상세 이미지에서 사이즈표 선택",
                    subtitle: "사이즈표가 보이는 이미지를 하나 선택해 주세요."
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(candidateURLStrings, id: \.self) { value in
                            Button {
                                selectedCandidateURLString = value
                                selectedImageData = nil
                            } label: {
                                AsyncImage(url: URL(string: value)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 100, height: 124)
                                .clipped()
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            selectedCandidateURLString == value ? Color.accentColor : .clear,
                                            lineWidth: 3
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                PrimaryButton(title: "선택한 이미지 분석", systemImage: "viewfinder") {
                    guard let value = selectedCandidateURLString,
                          let url = URL(string: value) else { return }
                    Task { await analyze(url: url) }
                }
                .disabled(selectedCandidateURLString == nil || isAnalyzing)
                .opacity(selectedCandidateURLString == nil || isAnalyzing ? 0.45 : 1)
            }
        }
    }

    private var photoSection: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "다른 이미지 사용",
                    subtitle: "사이즈표 스크린샷이나 사진을 선택할 수 있어요."
                )
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("사진에서 불러오기", systemImage: "photo.badge.plus")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var tableEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedImageData, let image = UIImage(data: selectedImageData) {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "선택한 원본", subtitle: "확대해서 표와 인식값을 비교해 주세요.")
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(minWidth: 300)
                        }
                        .frame(maxHeight: 260)
                    }
                }
            } else if let value = selectedCandidateURLString {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "선택한 원본", subtitle: "확대해서 표와 인식값을 비교해 주세요.")
                        AsyncImage(url: URL(string: value)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 300)
                    }
                }
            }

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: hasRecognizedRows ? "인식 결과 확인" : "상품 사이즈 직접 입력",
                        subtitle: "빈칸과 잘못 인식된 값은 판매 페이지를 보고 수정해 주세요."
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
                    SecondaryButton(title: "사이즈 행 추가", systemImage: "plus") {
                        viewModel.addSizeOption()
                    }
                }
            }
        }
    }

    private var candidateURLStrings: [String] {
        viewModel.sizeTableRecoveryContext?.imageURLStrings ?? []
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
        showsManualEditor = true
        validationMessage = nil
    }

    @MainActor
    private func analyze(url: URL) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        _ = await viewModel.analyzeRecoveryImage(url: url)
        showsManualEditor = true
    }

    @MainActor
    private func analyze(data: Data) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        _ = viewModel.analyzeRecoveryImage(data: data)
        showsManualEditor = true
    }

    private func complete() {
        if let message = SizeTableRecoveryValidator.validationMessage(
            for: viewModel.sizeOptions,
            category: viewModel.category,
            detailCategory: viewModel.detailCategory
        ) {
            validationMessage = message
            return
        }
        validationMessage = nil
        onComplete()
    }
}
