import Foundation

/// Every candidate is ranked on the same approved facts. Missing dimensions
/// cannot improve a candidate's rank by removing a poor matching dimension.
enum VNextRankingEvidence {
    static func compare(
        _ evidence: [VNextAuthorizedMeasurementDTO], cache: VNextAuthorizedScoreCache
    ) -> MeasurementComparisonResult? {
        guard evidence.allSatisfy({
            [$0.absoluteDifference, $0.weight].allSatisfy {
                $0.isFinite && Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) != nil
            }
        }), let checked = cache.compare(evidence, minimum: 1) else { return nil }
        // Decimal arithmetic agrees with Postgres numeric, including .5 ties.
        // v1/v2 replay intentionally retains the original Double arithmetic.
        func decimal(_ value: Double) -> Decimal { Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))! }
        func rounded(_ value: Decimal, scale: Int = 0) -> Decimal {
            var input = value, output = Decimal()
            NSDecimalRound(&output, &input, scale, .plain)
            return output
        }
        let items = checked.comparedItems.map { item in
            let points = max(Decimal(0), min(Decimal(100), rounded(100 - decimal(item.absoluteDifference) * 5)))
            return MeasurementComparisonItem(
                kind: item.kind, measurementCode: item.measurementCode, displayTitle: item.displayTitle,
                productValue: item.productValue, referenceValue: item.referenceValue,
                signedDifference: item.signedDifference, absoluteDifference: item.absoluteDifference,
                score: NSDecimalNumber(decimal: points).intValue, weight: item.weight,
                inputMode: item.inputMode
            )
        }
        let weight = items.reduce(Decimal(0)) { $0 + decimal($1.weight) }
        let weightedScore = items.reduce(Decimal(0)) { $0 + Decimal($1.score) * decimal($1.weight) }
        let weightedDifference = items.reduce(Decimal(0)) { $0 + decimal($1.absoluteDifference) * decimal($1.weight) }
        return MeasurementComparisonResult(
            status: checked.status,
            score: NSDecimalNumber(decimal: rounded(weightedScore / weight)).intValue,
            comparedItems: items, exclusions: checked.exclusions,
            averageDifference: NSDecimalNumber(decimal: rounded(weightedDifference / weight, scale: 6)).doubleValue,
            minimumComparableCount: checked.minimumComparableCount, requiredKinds: checked.requiredKinds,
            minimumRequiredKindCount: checked.minimumRequiredKindCount, requiredAllKinds: checked.requiredAllKinds,
            expectedWeightSum: checked.expectedWeightSum, usedWeightSum: checked.usedWeightSum
        )
    }

    static func commonCodes(_ candidates: [VNextAuthorizedCandidateDTO]) throws -> Set<String> {
        guard let first = candidates.first else {
            throw VNextComparisonEngineAdapterError.emptyAuthorizedSet
        }
        var common = Set(first.comparisonMeasurements.map(\.measurementCode))
        for candidate in candidates.dropFirst() {
            common.formIntersection(candidate.comparisonMeasurements.map(\.measurementCode))
        }
        guard !common.isEmpty else { throw VNextComparisonEngineAdapterError.noCommonRankingEvidence }
        for code in common {
            let rows = candidates.compactMap { candidate in
                candidate.comparisonMeasurements.first { $0.measurementCode == code }
            }
            guard let anchor = rows.first, rows.allSatisfy({
                $0.unitCode.lowercased() == anchor.unitCode.lowercased()
                    && $0.basisCode == anchor.basisCode
                    && $0.weight == anchor.weight
                    && $0.referenceValue == anchor.referenceValue
            }) else { throw VNextComparisonEngineAdapterError.inconsistentRankingEvidence }
        }
        return common
    }
}
