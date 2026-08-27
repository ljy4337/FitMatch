import Foundation

struct ProductMetadata {
    var styleNo: String? = nil
    /// Provider variant identity when it is distinct from the product identity.
    /// ZARA uses this for the URL `v1` / analytics `catentryId` value.
    var externalVariantID: String? = nil
    /// Provider-native product reference kept separately from style, variant,
    /// and internal product identities. ZARA publishes this as `productRef`.
    var externalProductReference: String? = nil
    /// How a provider variant was selected. Kept as provenance rather than UI copy.
    var variantSelectionMethod: String? = nil
    /// Provider variant confidence in the closed 0...1 range.
    var variantSelectionConfidence: Double? = nil
    /// Versioned category mapping source used by the parser.
    var categoryMappingPolicyVersion: String? = nil
    var englishName: String? = nil
    var brandCode: String? = nil
    var brandEnglishName: String? = nil
    var brandLogoImageURLString: String? = nil
    var brandNationName: String? = nil
    var sourceCategoryPath: String? = nil
    var sourceCategoryDepth1: String? = nil
    var sourceCategoryDepth2: String? = nil
    var sourceCategoryDepth3: String? = nil
    var sourceCategoryDepth4: String? = nil
    var baseCategoryFullPath: String? = nil
    var categoryDepth1Code: String? = nil
    var categoryDepth1Name: String? = nil
    var categoryDepth2Code: String? = nil
    var categoryDepth2Name: String? = nil
    var categoryDepth3Code: String? = nil
    var categoryDepth3Name: String? = nil
    var categoryDepth4Code: String? = nil
    var categoryDepth4Name: String? = nil
    /// Typed retailer facts forwarded verbatim to the server classification authority.
    /// These facts remain evidence; the iOS parser does not turn them into canonical labels.
    var structuredFacts: [String: String] = [:]
    var sizeType: String? = nil
    var genderCodes: [String] = []
    var labelNames: [String] = []
    var imageURLStrings: [String] = []
    var normalPrice: Int? = nil
    var salePrice: Int? = nil
    var finalPrice: Int? = nil
    var currencyCode: String? = nil
    var discountRate: Double? = nil
    var isSale: Bool = false
    var isOutOfStock: Bool = false
    var stockStatusRawValue: String? = nil
    var isRestock: Bool = false
    var isSoonOutOfStock: Bool = false
    var isLimitedQuantity: Bool = false
    var reviewCount: Int? = nil
    var reviewSatisfactionScore: Double? = nil
    var seasonYear: String? = nil
    var season: String? = nil
    var checkedColorName: String? = nil
    var checkedSizeName: String? = nil

    var mostSpecificExternalCategoryID: String? {
        [categoryDepth4Code, categoryDepth3Code, categoryDepth2Code, categoryDepth1Code]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Persists parser-only structured retailer facts without adding a SwiftData
/// column. `Product.labelNames` is an existing raw-retailer metadata string;
/// normal labels remain readable while one reserved, versioned token carries
/// an opaque JSON payload. Replay always filters that token back out.
enum FitMatchStoredRetailerFacts {
    struct Decoded: Equatable {
        let labelNames: [String]
        let structuredFacts: [String: String]
        let hasVersionedPayload: Bool
    }

    private struct Envelope: Codable {
        let version: Int
        let structuredFacts: [String: String]
    }

    private static let tokenPrefix = "__fitmatch_retailer_facts_v1__:"
    private static let currentVersion = 1

    static func encode(
        labelNames: [String],
        structuredFacts: [String: String]
    ) -> String {
        let retailerLabels = labelNames.filter { !$0.hasPrefix(tokenPrefix) }
        let envelope = Envelope(
            version: currentVersion,
            structuredFacts: structuredFacts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(envelope) else {
            return retailerLabels.joined(separator: ",")
        }
        return (retailerLabels + [tokenPrefix + payload.base64EncodedString()])
            .joined(separator: ",")
    }

    static func decode(_ storage: String) -> Decoded {
        let tokens = storage.split(separator: ",").map(String.init)
        var labels: [String] = []
        var facts: [String: String] = [:]
        var hasVersionedPayload = false

        for token in tokens {
            guard token.hasPrefix(tokenPrefix) else {
                labels.append(token)
                continue
            }
            let payload = String(token.dropFirst(tokenPrefix.count))
            guard let data = Data(base64Encoded: payload),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.version == currentVersion else {
                // Reserved tokens are never surfaced as retailer labels, even
                // when corrupt or from an unsupported future version.
                continue
            }
            facts = envelope.structuredFacts
            hasVersionedPayload = true
        }

        return Decoded(
            labelNames: labels,
            structuredFacts: facts,
            hasVersionedPayload: hasVersionedPayload
        )
    }
}
