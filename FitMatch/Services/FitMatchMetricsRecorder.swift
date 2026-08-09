import Foundation

enum FitMatchMetricProvider: String, Equatable {
    case musinsa
    case uniqlo
    case unsupported

    static func resolve(urlString: String) -> Self {
        guard let host = URL(string: urlString)?.host?.lowercased() else {
            return .unsupported
        }
        if host == "musinsa.com" || host.hasSuffix(".musinsa.com") || host == "musinsa.onelink.me" {
            return .musinsa
        }
        if host == "uniqlo.com" || host.hasSuffix(".uniqlo.com") {
            return .uniqlo
        }
        return .unsupported
    }
}

enum FitMatchMetricMajorCategory: String, Equatable {
    case tops
    case bottoms
    case outerwear
    case dresses
    case underwear
    case shoes
    case accessories
    case other

    init(category: ClothingCategory) {
        self = Self(rawValue: category.taxonomyCode) ?? .other
    }
}

enum FitMatchMetricDetailResolution: String, Equatable {
    case specific
    case catchAll = "catch_all"
}

enum FitMatchMetricMeasurementAvailability: String, Equatable {
    case actual
    case standardFallback = "standard_fallback"
    case unavailable

    init(_ value: ProductMeasurementAvailability) {
        switch value {
        case .actualMeasurements: self = .actual
        case .standardSizeChart: self = .standardFallback
        case .unavailable: self = .unavailable
        }
    }
}

enum FitMatchMetricParserFailure: String, Equatable {
    case partial
    case invalidURL = "invalid_url"
    case unsupportedURL = "unsupported_url"
    case network
    case other
}

enum FitMatchMetricComparisonMode: String, Equatable {
    case automatic
    case selectedReference = "selected_reference"
}

enum FitMatchMetricComparisonOutcome: String, Equatable {
    case confirmed
    case insufficientEvidence = "insufficient_evidence"
    case legacy
}

enum FitMatchMetricComparisonReliability: String, Equatable {
    case high
    case sufficient
    case minimum
    case insufficient
    case legacy

    init(history: RecommendationHistory) {
        switch history.comparisonStatus {
        case .legacy:
            self = .legacy
        case .insufficientEvidence:
            self = .insufficient
        case .confirmed:
            let compatibilityPenalty = history.comparisonMethod.contains("확장 비교") ? 1 : 0
            let adjustedEvidenceCount = max(
                0,
                history.comparedMeasurementUsages.count - compatibilityPenalty
            )
            switch adjustedEvidenceCount {
            case 4...: self = .high
            case 3: self = .sufficient
            default: self = .minimum
            }
        }
    }
}

enum FitMatchMetricComparisonBlockReason: String, Equatable {
    case missingReference = "missing_reference"
    case invalidProduct = "invalid_product"
    case insufficientEvidence = "insufficient_evidence"
}

enum FitMatchMetricClosetOrigin: String, Equatable {
    case manual
    case linkedProduct = "linked_product"
    case comparedProduct = "compared_product"
}

enum FitMatchMetricEvent: Equatable {
    case appLaunch
    case shareReceived(provider: FitMatchMetricProvider)
    case shareConsumed(provider: FitMatchMetricProvider)
    case parserAttempt(provider: FitMatchMetricProvider)
    case parserSuccess(
        provider: FitMatchMetricProvider,
        category: FitMatchMetricMajorCategory,
        detail: FitMatchMetricDetailResolution,
        measurement: FitMatchMetricMeasurementAvailability
    )
    case parserFailure(provider: FitMatchMetricProvider, reason: FitMatchMetricParserFailure)
    case comparisonAttempt(mode: FitMatchMetricComparisonMode)
    case comparisonResult(
        mode: FitMatchMetricComparisonMode,
        outcome: FitMatchMetricComparisonOutcome,
        reliability: FitMatchMetricComparisonReliability
    )
    case comparisonBlocked(mode: FitMatchMetricComparisonMode, reason: FitMatchMetricComparisonBlockReason)
    case closetCreated(origin: FitMatchMetricClosetOrigin, category: FitMatchMetricMajorCategory)

    var counterKey: String {
        switch self {
        case .appLaunch:
            return "app.launch"
        case let .shareReceived(provider):
            return "share.received|provider=\(provider.rawValue)"
        case let .shareConsumed(provider):
            return "share.consumed|provider=\(provider.rawValue)"
        case let .parserAttempt(provider):
            return "parser.attempt|provider=\(provider.rawValue)"
        case let .parserSuccess(provider, category, detail, measurement):
            return "parser.success|provider=\(provider.rawValue)|category=\(category.rawValue)|detail=\(detail.rawValue)|measurement=\(measurement.rawValue)"
        case let .parserFailure(provider, reason):
            return "parser.failure|provider=\(provider.rawValue)|reason=\(reason.rawValue)"
        case let .comparisonAttempt(mode):
            return "comparison.attempt|mode=\(mode.rawValue)"
        case let .comparisonResult(mode, outcome, reliability):
            return "comparison.result|mode=\(mode.rawValue)|outcome=\(outcome.rawValue)|reliability=\(reliability.rawValue)"
        case let .comparisonBlocked(mode, reason):
            return "comparison.blocked|mode=\(mode.rawValue)|reason=\(reason.rawValue)"
        case let .closetCreated(origin, category):
            return "closet.created|origin=\(origin.rawValue)|category=\(category.rawValue)"
        }
    }
}

struct FitMatchMetricsSnapshot: Equatable {
    let schemaVersion: Int
    let counters: [String: Int]
    let lastUpdatedAt: Date?
}

protocol FitMatchMetricsRecording {
    func record(_ event: FitMatchMetricEvent)
}

final class FitMatchMetricsRecorder: FitMatchMetricsRecording {
    static let shared = FitMatchMetricsRecorder()
    static let schemaVersion = 1
    static let countersKey = "FitMatch.metrics.aggregate.v1"
    static let lastUpdatedAtKey = "FitMatch.metrics.lastUpdatedAt.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: AppGroupConfig.identifier)
            ?? .standard
    }

    func record(_ event: FitMatchMetricEvent) {
        lock.lock()
        defer { lock.unlock() }

        var counters = storedCounters()
        let current = counters[event.counterKey, default: 0]
        counters[event.counterKey] = current == Int.max ? Int.max : current + 1
        defaults.set(counters, forKey: Self.countersKey)
        defaults.set(Date(), forKey: Self.lastUpdatedAtKey)
    }

    func snapshot() -> FitMatchMetricsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return FitMatchMetricsSnapshot(
            schemaVersion: Self.schemaVersion,
            counters: storedCounters(),
            lastUpdatedAt: defaults.object(forKey: Self.lastUpdatedAtKey) as? Date
        )
    }

    func diagnosticReport(generatedAt: Date = Date()) -> String {
        let snapshot = snapshot()
        let formatter = ISO8601DateFormatter()
        var lines = [
            "FitMatch 품질 진단",
            "schema_version=\(snapshot.schemaVersion)",
            "generated_at=\(formatter.string(from: generatedAt))",
            "last_updated_at=\(snapshot.lastUpdatedAt.map(formatter.string(from:)) ?? "none")",
        ]
        if snapshot.counters.isEmpty {
            lines.append("counters=empty")
        } else {
            lines.append(contentsOf: snapshot.counters.keys.sorted().map {
                "\($0)=\(snapshot.counters[$0, default: 0])"
            })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func storedCounters() -> [String: Int] {
        defaults.dictionary(forKey: Self.countersKey)?.compactMapValues {
            ($0 as? NSNumber)?.intValue
        } ?? [:]
    }
}
