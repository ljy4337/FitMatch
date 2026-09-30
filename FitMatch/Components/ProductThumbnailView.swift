import SwiftUI
import UIKit
import Combine
import ImageIO

struct ProductThumbnailView: View {
    @Environment(\.displayScale) private var displayScale
    let imageURLString: String?
    var category: ClothingCategory? = nil
    var width: CGFloat = 80
    var height: CGFloat = 96
    var cornerRadius: CGFloat = 16
    var diagnosticContext: String? = nil
    @StateObject private var imageLoader = ProductThumbnailImageLoader()

    var body: some View {
        Group {
            if !imageURLs.isEmpty {
                if let image = imageLoader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if imageLoader.didFail {
                    placeholder {
                        placeholderIcon
                    }
                } else {
                    placeholder {
                        ProgressView()
                    }
                }
            } else {
                placeholder {
                    placeholderIcon
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: imageRequestIdentity) {
            await imageLoader.load(
                imageURLs,
                maxPixelSize: max(width, height) * displayScale,
                diagnosticContext: diagnosticContext
            )
        }
    }

    private var imageURL: URL? {
        guard let imageURLString = imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !imageURLString.isEmpty else {
            return nil
        }

        return URL(string: imageURLString)
    }

    private var imageURLs: [URL] {
        UniqloImageURLPolicy.candidateURLs(primaryURL: imageURL)
    }

    private var imageRequestIdentity: String {
        imageURLs.map(\.absoluteString).joined(separator: "|")
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay {
                content()
            }
    }

    private var placeholderIcon: some View {
        Image(systemName: placeholderSystemImage)
            .font(.system(size: min(width, height) * 0.28, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var placeholderSystemImage: String {
        switch category?.serviceGroup {
        case .top, .shirt, .knit:
            return "tshirt"
        case .bottom, .pants:
            return "figure.walk"
        case .outer:
            return "person.crop.rectangle"
        case .dress:
            return "figure.dress.line.vertical.figure"
        case .underwear:
            return "rectangle.roundedtop"
        case .shoes:
            return "shoeprints.fill"
        case .accessory:
            return "watch.analog"
        case .other, nil:
            return "photo"
        }
    }
}

@MainActor
private final class ProductThumbnailImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false

    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    private var currentURLs: [URL] = []

    func load(_ urls: [URL], maxPixelSize: CGFloat, diagnosticContext: String?) async {
        guard currentURLs != urls || image == nil else {
            return
        }

        currentURLs = urls
        image = nil
        didFail = false

        guard !urls.isEmpty else {
            return
        }
        let startedAt = DetailPerformanceDiagnostics.now()
        for (candidateIndex, url) in urls.enumerated() {
            if let cachedImage = Self.cache.object(forKey: url as NSURL) {
                image = cachedImage
                if let diagnosticContext {
                    DetailPerformanceDiagnostics.log(
                        screen: diagnosticContext,
                        event: "thumbnail_cache_hit",
                        startedAt: startedAt,
                        metadata: "candidate=\(candidateIndex + 1) pixels=\(Int(maxPixelSize))"
                    )
                }
                return
            }

            for attempt in 1...2 {
                do {
                    let networkStartedAt = DetailPerformanceDiagnostics.now()
                    let (data, response) = try await URLSession.shared.data(for: Self.request(for: url))
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                    if let diagnosticContext {
                        DetailPerformanceDiagnostics.log(
                            screen: diagnosticContext,
                            event: "thumbnail_downloaded",
                            startedAt: networkStartedAt,
                            metadata: "candidate=\(candidateIndex + 1) attempt=\(attempt) bytes=\(data.count) status=\(statusCode)"
                        )
                    }
                    guard (200..<400).contains(statusCode) else {
                        throw URLError(.badServerResponse)
                    }

                    let decodeStartedAt = DetailPerformanceDiagnostics.now()
                    guard !Task.isCancelled,
                          currentURLs == urls,
                          let loadedImage = await Self.decodeThumbnail(
                            data,
                            maxPixelSize: maxPixelSize
                          ) else {
                        throw CancellationError()
                    }
                    if let diagnosticContext {
                        DetailPerformanceDiagnostics.log(
                            screen: diagnosticContext,
                            event: "thumbnail_decoded",
                            startedAt: decodeStartedAt,
                            metadata: "width=\(Int(loadedImage.size.width * loadedImage.scale)) height=\(Int(loadedImage.size.height * loadedImage.scale))"
                        )
                    }

                    let pixelWidth = loadedImage.size.width * loadedImage.scale
                    let pixelHeight = loadedImage.size.height * loadedImage.scale
                    let cost = max(1, Int(pixelWidth * pixelHeight * 4))
                    Self.cache.setObject(loadedImage, forKey: url as NSURL, cost: cost)
                    image = loadedImage
                    if let diagnosticContext {
                        DetailPerformanceDiagnostics.log(
                            screen: diagnosticContext,
                            event: "thumbnail_ready",
                            startedAt: startedAt,
                            metadata: "cache=false candidate=\(candidateIndex + 1) attempt=\(attempt)"
                        )
                    }
                    return
                } catch {
                    guard !Task.isCancelled, currentURLs == urls else { return }
                    if attempt == 1 {
                        try? await Task.sleep(for: .milliseconds(250))
                        continue
                    }
                    if let diagnosticContext {
                        DetailPerformanceDiagnostics.log(
                            screen: diagnosticContext,
                            event: "thumbnail_candidate_failed",
                            startedAt: startedAt,
                            metadata: "candidate=\(candidateIndex + 1) attempts=\(attempt) error=\(String(describing: error))"
                        )
                    }
                }
            }
        }
        didFail = true
        if let diagnosticContext {
            DetailPerformanceDiagnostics.log(
                screen: diagnosticContext,
                event: "thumbnail_failed",
                startedAt: startedAt,
                metadata: "candidates=\(urls.count)"
            )
        }
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 15
        )
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        if url.host?.localizedCaseInsensitiveContains("uniqlo.com") == true {
            request.setValue("https://www.uniqlo.com/kr/ko/", forHTTPHeaderField: "Referer")
        }
        return request
    }

    private static func decodeThumbnail(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        let input = ThumbnailDecodeInput(data: data, maxPixelSize: maxPixelSize)
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(input.data as CFData, nil) else {
                return ThumbnailDecodeResult(image: nil)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(input.maxPixelSize)),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return ThumbnailDecodeResult(image: nil)
            }
            return ThumbnailDecodeResult(image: UIImage(cgImage: cgImage))
        }.value.image
    }
}

private final class ThumbnailDecodeInput: @unchecked Sendable {
    nonisolated let data: Data
    nonisolated let maxPixelSize: CGFloat

    nonisolated init(data: Data, maxPixelSize: CGFloat) {
        self.data = data
        self.maxPixelSize = maxPixelSize
    }
}

private final class ThumbnailDecodeResult: @unchecked Sendable {
    nonisolated let image: UIImage?

    nonisolated init(image: UIImage?) {
        self.image = image
    }
}
