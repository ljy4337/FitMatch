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
            if imageURL != nil {
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
        .task(id: imageURL) {
            await imageLoader.load(
                imageURL,
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

    private var currentURL: URL?

    func load(_ url: URL?, maxPixelSize: CGFloat, diagnosticContext: String?) async {
        guard currentURL != url || (image == nil && !didFail) else {
            return
        }

        currentURL = url
        image = nil
        didFail = false

        guard let url else {
            return
        }
        let startedAt = DetailPerformanceDiagnostics.now()
        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            image = cachedImage
            if let diagnosticContext {
                DetailPerformanceDiagnostics.log(
                    screen: diagnosticContext,
                    event: "thumbnail_cache_hit",
                    startedAt: startedAt,
                    metadata: "pixels=\(Int(maxPixelSize))"
                )
            }
            return
        }

        do {
            let networkStartedAt = DetailPerformanceDiagnostics.now()
            let (data, response) = try await URLSession.shared.data(from: url)
            if let diagnosticContext {
                DetailPerformanceDiagnostics.log(
                    screen: diagnosticContext,
                    event: "thumbnail_downloaded",
                    startedAt: networkStartedAt,
                    metadata: "bytes=\(data.count) status=\((response as? HTTPURLResponse)?.statusCode ?? 0)"
                )
            }
            let decodeStartedAt = DetailPerformanceDiagnostics.now()
            guard !Task.isCancelled,
                  currentURL == url,
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let loadedImage = await Self.decodeThumbnail(
                    data,
                    maxPixelSize: maxPixelSize
                  ) else {
                if !Task.isCancelled, currentURL == url {
                    didFail = true
                }
                return
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
                    metadata: "cache=false"
                )
            }
        } catch {
            guard !Task.isCancelled, currentURL == url else { return }
            didFail = true
            if let diagnosticContext {
                DetailPerformanceDiagnostics.log(
                    screen: diagnosticContext,
                    event: "thumbnail_failed",
                    startedAt: startedAt,
                    metadata: "error=\(String(describing: error))"
                )
            }
        }
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
