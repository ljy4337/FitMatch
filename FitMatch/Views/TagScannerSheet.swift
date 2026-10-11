import SwiftUI
import VisionKit
import Vision
import AVFoundation

struct TagScannerSheet: View {
    let onResolved: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraAllowed = false
    @State private var errorMessage: String?
    @State private var isResolving = false
    @State private var scanGeneration = UUID()
    @State private var lookup: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("유니클로 바코드 또는 무신사 상품 안내 QR을 비춰 주세요.")
                    .font(.subheadline)
                    .padding(.horizontal)
                if isResolving {
                    ProgressView("상품 링크 확인 중")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("스캔을 완료하지 못했어요", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("다시 시도") {
                            self.errorMessage = nil
                            cameraAllowed = false
                            scanGeneration = UUID()
                        }
                        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                            Button("설정 열기") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                } else if cameraAllowed && scenePhase == .active {
                    TagCameraView(onCode: resolve, onError: { errorMessage = $0 })
                        .id(scanGeneration)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("태그 스캔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel(); dismiss() }
                }
            }
            .task(id: scanGeneration) { await prepareCamera() }
            .onDisappear { cancel() }
        }
    }

    private func prepareCamera() async {
        guard DataScannerViewController.isSupported else {
            errorMessage = "이 기기에서는 카메라 스캔을 사용할 수 없어요. 상품 링크로 불러와 주세요."
            return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else { return }
        guard granted else {
            errorMessage = "카메라 권한이 필요해요. 설정에서 카메라 접근을 허용해 주세요."
            return
        }
        guard DataScannerViewController.isAvailable else {
            errorMessage = "지금은 카메라를 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
            return
        }
        cameraAllowed = true
    }

    private func resolve(_ code: String) {
        guard !isResolving else { return }
        isResolving = true
        lookup = Task { @MainActor in
            do {
                let url = try await TagProductResolver().resolve(code)
                try Task.checkCancellation()
                onResolved(url)
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                isResolving = false
                errorMessage = (error as? TagProductResolver.ScanError)?.errorDescription
                    ?? "상품 링크를 불러오지 못했어요. 네트워크 연결을 확인하고 다시 시도해 주세요."
            }
        }
    }

    private func cancel() { lookup?.cancel(); lookup = nil }
}

private struct TagCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .ean13])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        do { try controller.startScanning() }
        catch { Task { @MainActor in onError("카메라를 시작하지 못했어요. 다시 시도해 주세요.") } }
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        controller.delegate = nil
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        private var consumed = false
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                guard !consumed, let value = barcode.payloadStringValue else { continue }
                consumed = true
                dataScanner.stopScanning()
                onCode(value)
                return
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError("카메라 스캔이 중단됐어요. 다시 시도해 주세요.")
        }
    }
}
