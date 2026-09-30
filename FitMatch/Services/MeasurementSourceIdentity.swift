import Foundation

enum MeasurementSourceIdentityResolution: String, Equatable, Hashable {
    case canonicalProductSource = "canonical_product_source"
    case legacyMethodSource = "legacy_method_source"
    case legacyLocalFallback = "legacy_local_fallback"
}

struct MeasurementSourceIdentity: Equatable, Hashable {
    let code: String
    let resolution: MeasurementSourceIdentityResolution

    static func canonical(sourceCode: String?) -> MeasurementSourceIdentity? {
        guard let normalized = sourceCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return MeasurementSourceIdentity(
            code: normalized,
            resolution: .canonicalProductSource
        )
    }

    static func resolve(methodSource: String) -> MeasurementSourceIdentity? {
        let tokens = methodSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard let first = tokens.first else { return nil }

        if first == "manual" {
            return MeasurementSourceIdentity(
                code: "fitmatch",
                resolution: .legacyLocalFallback
            )
        }

        guard !genericMethodPrefixes.contains(first) else { return nil }
        return MeasurementSourceIdentity(
            code: first,
            resolution: .legacyMethodSource
        )
    }

    private static let genericMethodPrefixes: Set<String> = [
        "actual", "api", "fixture", "html", "imported", "legacy",
        "parser", "test", "transcribed", "unknown", "web"
    ]
}

extension GarmentMeasurementRecord {
    var sourceIdentity: MeasurementSourceIdentity? {
        if let canonical = MeasurementSourceIdentity.canonical(
            sourceCode: productSize?.product?.sourcePlatformCode
                ?? userFit?.sourcePlatformCode
                ?? userFit?.sourceProduct?.sourcePlatformCode
        ) {
            return canonical
        }
        return MeasurementSourceIdentity.resolve(methodSource: methodSource)
    }
}
