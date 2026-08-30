import Foundation

enum VNextComparisonEngineAdapterError: LocalizedError, Equatable {
    case comparisonNotPending(String)
    case authorizationDenied(String)
    case classificationNotConfirmed
    case emptyAuthorizedSet
    case candidateSetMismatch
    case duplicateCandidate
    case unavailableCandidate(UUID)
    case excludedMetricUsed(String)
    case invalidEvidence(UUID)
    case policySnapshotInvalid

    var errorDescription: String? {
        switch self {
        case .comparisonNotPending(let status):
            return "비교 실행 상태가 계산 대기 상태가 아닙니다: \(status)"
        case .authorizationDenied(let reason):
            return "서버 비교 승인이 거부되었습니다: \(reason)"
        case .classificationNotConfirmed:
            return "서버에서 확정한 상품만 비교할 수 있습니다."
        case .emptyAuthorizedSet:
            return "서버가 승인한 비교 사이즈가 없습니다."
        case .candidateSetMismatch, .duplicateCandidate:
            return "서버 비교 후보 스냅샷이 일관되지 않습니다."
        case .unavailableCandidate:
            return "판매 가능 근거가 없는 사이즈가 비교 후보에 포함됐습니다."
        case .excludedMetricUsed(let code):
            return "제외된 실측 항목이 비교에 포함됐습니다: \(code)"
        case .invalidEvidence:
            return "서버 실측 스냅샷을 검증할 수 없습니다."
        case .policySnapshotInvalid:
            return "서버 비교 정책 스냅샷이 올바르지 않습니다."
        }
    }
}

struct VNextComparisonCandidateAnalysis: Equatable, @unchecked Sendable {
    let productSizeID: UUID
    let sizeLabel: String
    let result: MeasurementComparisonResult
    let rank: Int
}

struct VNextComparisonBatchAnalysis: Equatable, @unchecked Sendable {
    let comparisonID: UUID
    let analyses: [VNextComparisonCandidateAnalysis]
    let recommended: VNextComparisonCandidateAnalysis
    let completionPayload: VNextComparisonCompletionPayload

    var authorizedCandidateProductSizeIDs: [UUID] {
        analyses.map(\.productSizeID)
    }
}

struct VNextComparisonEngineAdapter {
    static let engineVersion = "fitmatch-ios-vnext-snapshot-v1"

    private let engine: MeasurementComparisonEngine

    init(engine: MeasurementComparisonEngine = MeasurementComparisonEngine()) {
        self.engine = engine
    }

    func analyze(_ begin: VNextBeginComparisonDTO) throws -> VNextComparisonBatchAnalysis {
        guard begin.resultStatus == "PENDING" else {
            throw VNextComparisonEngineAdapterError.comparisonNotPending(begin.resultStatus)
        }
        guard begin.snapshot.authorization.allowed else {
            throw VNextComparisonEngineAdapterError.authorizationDenied(
                begin.snapshot.authorization.reason ?? "blocked"
            )
        }
        guard begin.snapshot.target.classificationStatus == "CONFIRMED" else {
            throw VNextComparisonEngineAdapterError.classificationNotConfirmed
        }

        let authorizedIDs = begin.authorizedCandidateProductSizeIDs
        guard !authorizedIDs.isEmpty else {
            throw VNextComparisonEngineAdapterError.emptyAuthorizedSet
        }
        guard Set(authorizedIDs).count == authorizedIDs.count else {
            throw VNextComparisonEngineAdapterError.duplicateCandidate
        }
        let snapshotIDs = begin.snapshot.target.authorizedCandidateProductSizeIDs
        let candidateIDs = begin.snapshot.target.candidates.map(\.productSizeID)
        guard Set(snapshotIDs) == Set(authorizedIDs),
              Set(candidateIDs) == Set(authorizedIDs),
              candidateIDs.count == authorizedIDs.count else {
            throw VNextComparisonEngineAdapterError.candidateSetMismatch
        }

        let excluded = Set(begin.snapshot.excludedMeasurementCodes)
        let activePolicyMetricCount = begin.snapshot.policy.metrics.filter {
            $0.metricMode == "CANONICAL"
                && $0.isActive
                && $0.measurementCode.map { !excluded.contains($0) } == true
        }.count
        guard activePolicyMetricCount > 0 else {
            throw VNextComparisonEngineAdapterError.policySnapshotInvalid
        }

        var unranked: [(candidate: VNextAuthorizedCandidateDTO, result: MeasurementComparisonResult)] = []
        for candidate in begin.snapshot.target.candidates {
            guard candidate.availability.status == "AVAILABLE" else {
                throw VNextComparisonEngineAdapterError.unavailableCandidate(
                    candidate.productSizeID
                )
            }
            guard candidate.authorization.allowed else {
                throw VNextComparisonEngineAdapterError.authorizationDenied(
                    candidate.authorization.reason ?? "candidate_blocked"
                )
            }
            if let excludedCode = candidate.comparisonMeasurements
                .map(\.measurementCode)
                .first(where: excluded.contains) {
                throw VNextComparisonEngineAdapterError.excludedMetricUsed(excludedCode)
            }
            guard let result = engine.compareAuthorizedEvidence(
                candidate.comparisonMeasurements,
                minimumComparableCount: candidate.authorization.minimumCommon
                    ?? begin.snapshot.authorization.minimumCommon
                    ?? 1
            ) else {
                throw VNextComparisonEngineAdapterError.invalidEvidence(
                    candidate.productSizeID
                )
            }
            unranked.append((candidate, result))
        }

        let ranked = unranked.sorted {
            if $0.result.score != $1.result.score {
                return $0.result.score > $1.result.score
            }
            if $0.result.averageDifference != $1.result.averageDifference {
                return $0.result.averageDifference < $1.result.averageDifference
            }
            return $0.candidate.productSizeID.uuidString
                < $1.candidate.productSizeID.uuidString
        }
        let analyses = ranked.enumerated().map { index, entry in
            VNextComparisonCandidateAnalysis(
                productSizeID: entry.candidate.productSizeID,
                sizeLabel: entry.candidate.sizeLabel,
                result: entry.result,
                rank: index + 1
            )
        }
        guard let recommended = analyses.first else {
            throw VNextComparisonEngineAdapterError.emptyAuthorizedSet
        }

        let evidence = begin.snapshot.target.candidates.flatMap { candidate in
            candidate.comparisonMeasurements.map { metric in
                VNextMetricEvidenceDTO(
                    productSizeID: candidate.productSizeID,
                    measurementCode: metric.measurementCode,
                    referenceValue: metric.referenceValue,
                    targetValue: metric.targetValue,
                    difference: metric.difference,
                    absoluteDifference: metric.absoluteDifference,
                    weight: metric.weight
                )
            }
        }
        let recommendedEvidenceCount = begin.snapshot.target.candidates
            .first(where: { $0.productSizeID == recommended.productSizeID })?
            .comparisonMeasurements.count ?? 0
        let coverage = (Double(recommendedEvidenceCount) / Double(activePolicyMetricCount))
            .rounded(toPlaces: 5)
        let reliability = Self.reliability(
            evidenceCount: recommendedEvidenceCount,
            coverage: coverage
        )
        let completion = VNextComparisonCompletionPayload(
            recommendedProductSizeID: recommended.productSizeID,
            score: Double(recommended.result.score),
            reliability: reliability,
            coverage: coverage,
            engineVersion: Self.engineVersion,
            candidateSizeRanking: analyses.map {
                VNextCandidateRankingDTO(
                    productSizeID: $0.productSizeID,
                    rank: $0.rank,
                    score: Double($0.result.score)
                )
            },
            metricEvidence: evidence
        )
        return VNextComparisonBatchAnalysis(
            comparisonID: begin.comparisonID,
            analyses: analyses,
            recommended: recommended,
            completionPayload: completion
        )
    }

    private static func reliability(evidenceCount: Int, coverage: Double) -> Int {
        if evidenceCount >= 4, coverage >= 0.75 { return 5 }
        if evidenceCount >= 3, coverage >= 0.5 { return 4 }
        if evidenceCount >= 2 { return 3 }
        if evidenceCount == 1 { return 2 }
        return 1
    }
}

@MainActor
final class VNextComparisonSessionStore {
    static let shared = VNextComparisonSessionStore()

    private var sessions: [UUID: VNextComparisonBatchAnalysis] = [:]

    func store(_ analysis: VNextComparisonBatchAnalysis, historyID: UUID) {
        sessions[historyID] = analysis
    }

    func analysis(for historyID: UUID) -> VNextComparisonBatchAnalysis? {
        sessions[historyID]
    }

    func remove(historyID: UUID) {
        sessions.removeValue(forKey: historyID)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
