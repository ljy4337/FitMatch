import Combine
import Foundation

protocol FitMatchComparisonRemoteServicing: Sendable {
    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse
    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse
    func listClosetItems() async throws -> FitMatchClosetItemsResponse
    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse
    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse
    func completeComparison(_ request: FitMatchCompleteComparisonRequest) async throws
        -> FitMatchCompleteComparisonResponse
}

extension FitMatchSupabaseDomainClient: FitMatchComparisonRemoteServicing {}

enum FitMatchComparisonSyncState: Equatable {
    case idle
    case syncing
    case synced
    case pendingRetry
    case parityWarning
}

@MainActor
final class FitMatchComparisonSyncCoordinator: ObservableObject {
    @Published private(set) var state: FitMatchComparisonSyncState = .idle
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var parityWarningCount = 0

    private let remote: any FitMatchComparisonRemoteServicing
    private let defaults: UserDefaults
    private var isSynchronizing = false
    private var needsAnotherPass = false

    private static let processedPrefix = "FitMatch.comparisonProcessed.v1."

    init(
        remote: (any FitMatchComparisonRemoteServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.remote = remote ?? FitMatchSupabaseDomainClient.shared
        self.defaults = defaults
    }

    func synchronize(userID: UUID, histories: [RecommendationHistory]) async {
        if isSynchronizing {
            needsAnotherPass = true
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        repeat {
            needsAnotherPass = false
            await synchronizeOnce(userID: userID, histories: histories)
        } while needsAnotherPass
    }

    private func synchronizeOnce(userID: UUID, histories: [RecommendationHistory]) async {
        state = .syncing
        lastErrorMessage = nil
        parityWarningCount = 0

        var processed = processedHistoryIDs(for: userID)
        let pending = histories
            .filter { !processed.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        guard !pending.isEmpty else {
            state = .synced
            return
        }

        do {
            let closetResponse = try await remote.listClosetItems()
            guard closetResponse.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }
            let remoteClosetByClientID = Dictionary(
                uniqueKeysWithValues: closetResponse.items.map { ($0.clientItemID, $0) }
            )
            var hasRetryableFailure = false

            for history in pending {
                do {
                    let outcome = try await synchronize(
                        history: history,
                        remoteClosetByClientID: remoteClosetByClientID
                    )
                    switch outcome {
                    case .completed:
                        processed.insert(history.id)
                    case .parityWarning:
                        processed.insert(history.id)
                        parityWarningCount += 1
                    case .retryLater:
                        hasRetryableFailure = true
                    }
                } catch {
                    hasRetryableFailure = true
                    lastErrorMessage = error.localizedDescription
                    #if DEBUG
                    print("[FitMatchComparisonSync] history=\(history.id) failed: \(error.localizedDescription)")
                    #endif
                }
            }

            storeProcessedHistoryIDs(processed, for: userID)
            if hasRetryableFailure {
                state = .pendingRetry
                if lastErrorMessage == nil {
                    lastErrorMessage = "일부 비교 결과를 서버에 저장하지 못했습니다. 다음 동기화에서 다시 시도합니다."
                }
            } else if parityWarningCount > 0 {
                state = .parityWarning
                lastErrorMessage = "로컬 비교 결과와 서버 안전 정책이 다른 기록이 있습니다."
            } else {
                state = .synced
            }
        } catch {
            state = .pendingRetry
            lastErrorMessage = error.localizedDescription
            #if DEBUG
            print("[FitMatchComparisonSync] sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func synchronize(
        history: RecommendationHistory,
        remoteClosetByClientID: [UUID: FitMatchClosetItemRecord]
    ) async throws -> SyncOutcome {
        guard let reference = remoteClosetByClientID[history.userFit.id] else {
            return .retryLater
        }
        guard let request = databaseRequest(for: history) else {
            return .parityWarning
        }

        let resolution = try await remote.resolve(request)
        guard resolution.catalogState == "current",
              let targetProductID = resolution.productID else {
            return .retryLater
        }
        guard resolution.classification.status == "confirmed" else {
            return .parityWarning
        }

        let runtime = try await remote.fetchProductRuntime(request)
        guard runtime.runtimeState == "ready", runtime.comparisonReady else {
            return .parityWarning
        }
        guard let targetSizeID = uniqueRuntimeSizeID(
            in: runtime,
            matching: history.recommendedSize,
            colorName: history.selectedColorNameSnapshot ?? history.product.checkedColorName
        ) else {
            return .retryLater
        }

        let candidates = try await remote.findReferenceCandidates(targetProductID: targetProductID)
        let selectedCandidate = candidates.candidates.first {
            $0.closetItemID == reference.closetItemID
        }
        let allowExtended = selectedCandidate?.automaticReady == false
            && selectedCandidate?.manualReady == true

        let begin = try await remote.beginComparison(
            FitMatchBeginComparisonRequest(
                referenceItemID: reference.closetItemID,
                targetProductID: targetProductID,
                allowExtended: allowExtended,
                clientHistoryID: history.id
            )
        )
        if begin.status == "blocked" || !begin.compatibility.allowed {
            return .parityWarning
        }
        if begin.status == "completed" {
            return .completed
        }
        guard begin.status == "pending" else {
            return .retryLater
        }

        let snapshot = history.calculationSnapshot
        let quality = qualityMetrics(
            snapshot: snapshot,
            exclusions: history.measurementExclusions,
            comparisonStatus: history.comparisonStatus
        )
        let result = FitMatchComparisonResultSubmission(
            targetSizeID: targetSizeID,
            similarityScore: Double(history.recommendationScore),
            rank: 1,
            confidenceCode: quality.confidenceCode,
            coverageRatio: quality.coverageRatio,
            dataQualityScore: quality.dataQualityScore,
            confidenceScore: quality.confidenceScore,
            qualityMetricsVersion: quality.version,
            isRecommended: true,
            isComparable: history.comparisonStatus == .confirmed,
            exclusionReason: history.comparisonStatus == .confirmed
                ? nil
                : history.comparisonStatus.rawValue,
            snapshot: [
                "local_history_id": history.id.uuidString,
                "local_schema_version": String(history.comparisonSchemaVersion),
                "comparison_method": history.comparisonMethod,
                "database_policy_version": candidates.policyVersion ?? "unknown",
                "local_policy_version": history.canonicalPolicyVersionSnapshot ?? "unknown",
                "quality_metrics_version": quality.version
            ],
            measurements: measurementSubmissions(for: history)
        )
        _ = try await remote.completeComparison(
            FitMatchCompleteComparisonRequest(
                runID: begin.runID,
                results: [result],
                summary: [
                    "local_history_id": history.id.uuidString,
                    "recommended_size": history.recommendedSize.name,
                    "recommendation_score": String(history.recommendationScore),
                    "comparison_status": history.comparisonStatus.rawValue,
                    "comparison_coverage": snapshot.map {
                        String(format: "%.4f", $0.comparisonCoverage)
                    } ?? "unknown",
                    "data_quality_score": String(format: "%.4f", quality.dataQualityScore),
                    "confidence_score": String(format: "%.4f", quality.confidenceScore),
                    "quality_metrics_version": quality.version,
                    "excluded_measurement_count": String(history.measurementExclusions.count)
                ]
            )
        )
        return .completed
    }

    private func databaseRequest(
        for history: RecommendationHistory
    ) -> FitMatchProductResolutionRequest? {
        let product = history.product
        let externalProductID = (history.productCodeSnapshot ?? product.productCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let externalProductID, !externalProductID.isEmpty else { return nil }

        let source = sourceCode(for: product, snapshotName: history.productSourceNameSnapshot)
        guard source == "uniqlo" || source == "musinsa" || source == "zara" || source == "cos" else { return nil }
        let categoryCodes = [
            product.categoryDepth1Code,
            product.categoryDepth2Code,
            product.categoryDepth3Code,
            product.categoryDepth4Code
        ].compactMap { value -> String? in
            let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized?.isEmpty == false ? normalized : nil
        }
        let audience = product.genderCodes
            .split(separator: ",")
            .map(String.init)
            .first

        return FitMatchProductResolutionRequest(
            source: source,
            externalProductID: externalProductID,
            productName: history.productNameSnapshot ?? product.name,
            sourceCategoryPath: history.sourceCategoryPathSnapshot ?? product.sourceCategoryPath,
            audience: audience,
            sourceCategoryCodes: categoryCodes.isEmpty ? nil : categoryCodes
        )
    }

    private func sourceCode(for product: Product, snapshotName: String?) -> String {
        if let code = product.sourcePlatformCode?.lowercased(),
           code == "uniqlo" || code == "musinsa" || code == "zara" || code == "cos" {
            return code
        }
        let joined = [snapshotName, product.sourceName, product.sourceURLString]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if joined.contains("uniqlo") || joined.contains("유니클로") { return "uniqlo" }
        if joined.contains("musinsa") || joined.contains("무신사") { return "musinsa" }
        if joined.contains("zara") || joined.contains("자라") { return "zara" }
        if joined.contains("cos") { return "cos" }
        return "manual"
    }

    private func uniqueRuntimeSizeID(
        in runtime: FitMatchProductRuntimeResponse,
        matching localSize: ProductSize,
        colorName: String?
    ) -> UUID? {
        let allSizes = runtime.variants.flatMap(\.sizes)
        if allSizes.contains(where: { $0.productSizeID == localSize.id }) {
            return localSize.id
        }

        var variants = runtime.variants
        if let colorName = colorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !colorName.isEmpty {
            let colorMatches = variants.filter {
                $0.colorName?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
                    || $0.variantName?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
                    || $0.colorCode?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
            }
            if !colorMatches.isEmpty {
                variants = colorMatches
            }
        }

        let normalized = localSize.name.fitMatchDisplaySizeName.lowercased()
        let matches = variants.flatMap(\.sizes).filter {
            $0.sizeLabel.fitMatchDisplaySizeName.lowercased() == normalized
                || $0.normalizedSizeLabel.fitMatchDisplaySizeName.lowercased() == normalized
        }
        return matches.count == 1 ? matches[0].productSizeID : nil
    }

    private func measurementSubmissions(
        for history: RecommendationHistory
    ) -> [FitMatchComparisonMeasurementSubmission] {
        var seen = Set<String>()
        var submissions: [FitMatchComparisonMeasurementSubmission] = []

        for item in history.calculationSnapshot?.usedMeasurements ?? [] {
            let code = item.measurementCode.rawValue
            guard seen.insert(code).inserted else { continue }
            submissions.append(
                FitMatchComparisonMeasurementSubmission(
                    measurementCode: code,
                    referenceValue: item.referenceValue,
                    targetValue: item.productValue,
                    signedDifference: item.signedDifference,
                    absoluteDifference: item.absoluteDifference,
                    weight: item.effectiveWeight,
                    included: true,
                    exclusionReason: nil,
                    evidence: [
                        "kind": item.kind.rawValue,
                        "title": item.displayTitle ?? item.kind.title,
                        "local_schema": String(history.comparisonSchemaVersion)
                    ]
                )
            )
        }

        for exclusion in history.measurementExclusions {
            guard let code = exclusion.productCode ?? exclusion.referenceCode else { continue }
            guard seen.insert(code.rawValue).inserted else { continue }
            submissions.append(
                FitMatchComparisonMeasurementSubmission(
                    measurementCode: code.rawValue,
                    referenceValue: nil,
                    targetValue: nil,
                    signedDifference: nil,
                    absoluteDifference: nil,
                    weight: nil,
                    included: false,
                    exclusionReason: exclusion.reason.rawValue,
                    evidence: ["kind": exclusion.kind.rawValue]
                )
            )
        }
        return submissions
    }

    private func qualityMetrics(
        snapshot: RecommendationCalculationSnapshot?,
        exclusions: [MeasurementComparisonExclusion],
        comparisonStatus: MeasurementComparisonStatus
    ) -> ComparisonQualityMetrics {
        guard let snapshot else { return .unavailable }

        let usedCount = snapshot.usedMeasurements.count
        let semanticIssueCount = exclusions.filter {
            switch $0.reason {
            case .unverifiedProductDefinition,
                 .unverifiedReferenceDefinition,
                 .incompatibleMeasurementCode:
                return true
            default:
                return false
            }
        }.count
        let semanticEvidenceCount = usedCount + semanticIssueCount
        let dataQualityScore = semanticEvidenceCount > 0
            ? Double(usedCount) / Double(semanticEvidenceCount)
            : 0
        let coverageRatio = min(1, max(0, snapshot.comparisonCoverage))
        let evidenceBreadth = min(1, Double(usedCount) / 3)
        let confidenceScore = comparisonStatus == .confirmed
            ? min(coverageRatio, dataQualityScore) * evidenceBreadth
            : 0

        return ComparisonQualityMetrics(
            coverageRatio: coverageRatio,
            dataQualityScore: dataQualityScore,
            confidenceScore: confidenceScore
        )
    }

    private func processedHistoryIDs(for userID: UUID) -> Set<UUID> {
        Set(
            (defaults.stringArray(forKey: Self.processedPrefix + userID.uuidString) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    private func storeProcessedHistoryIDs(_ ids: Set<UUID>, for userID: UUID) {
        defaults.set(
            ids.map(\.uuidString).sorted(),
            forKey: Self.processedPrefix + userID.uuidString
        )
    }

    private enum SyncOutcome {
        case completed
        case parityWarning
        case retryLater
    }

    private struct ComparisonQualityMetrics {
        static let currentVersion = "fitmatch-comparison-quality-2026-08-20-v1"

        let coverageRatio: Double
        let dataQualityScore: Double
        let confidenceScore: Double

        static let unavailable = ComparisonQualityMetrics(
            coverageRatio: 0,
            dataQualityScore: 0,
            confidenceScore: 0
        )

        var confidenceCode: String {
            if confidenceScore >= 0.8 { return "high" }
            if confidenceScore >= 0.5 { return "medium" }
            return "low"
        }

        var version: String { Self.currentVersion }
    }
}
