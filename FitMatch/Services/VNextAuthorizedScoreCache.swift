import Foundation

/// Reuses arithmetic only. Every final comparison still validates its fresh
/// begin snapshot before consulting this cache. No permit or ownership is cached.
final class VNextAuthorizedScoreCache {
    private struct Entry {
        let measurements: [VNextAuthorizedMeasurementDTO]
        let minimum: Int
        let result: MeasurementComparisonResult
    }
    private var entries: [Entry] = []
    private let engine = MeasurementComparisonEngine()
    private(set) var computationCount = 0

    func compare(_ measurements: [VNextAuthorizedMeasurementDTO], minimum: Int)
        -> MeasurementComparisonResult? {
        if let entry = entries.first(where: {
            $0.minimum == minimum && $0.measurements == measurements
        }) {
            return entry.result
        }
        guard let result = engine.compareAuthorizedEvidence(
            measurements, minimumComparableCount: minimum
        ) else { return nil }
        computationCount += 1
        if entries.count >= 512 { entries.removeFirst() }
        entries.append(Entry(measurements: measurements, minimum: minimum, result: result))
        return result
    }
}
