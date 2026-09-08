import Foundation

/// Contract failures are intentionally distinct from a temporary transport
/// failure or an ordinary lack of measurements.  The associated values are
/// for diagnostics and tests; presentation remains at the feature boundary.
nonisolated enum FitMatchVNextContractError: Error, LocalizedError, Equatable, Sendable {
    case missingRequiredField(String)
    case unknownState(field: String, observed: String)
    case unsupportedSnapshotVersion(Int)
    case unsupportedEngineVersion(String)
    case snapshotVersionMismatch(topLevel: Int, nested: Int)
    case conflictingProof(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField:
            return "서버 비교 계약의 필수 값이 없습니다. 앱을 업데이트한 뒤 다시 시도해 주세요."
        case .unknownState:
            return "서버 비교 상태를 해석할 수 없습니다. 앱을 업데이트한 뒤 다시 시도해 주세요."
        case .unsupportedSnapshotVersion, .unsupportedEngineVersion,
             .snapshotVersionMismatch, .conflictingProof:
            return "이 비교 기록은 현재 앱에서 안전하게 재생할 수 없습니다. 앱을 업데이트한 뒤 다시 확인해 주세요."
        }
    }
}

/// The server string remains in its DTO for transport compatibility. This
/// enum is only the closed mapping used by the runtime domain boundary.
nonisolated enum VNextReadinessState: String, CaseIterable, Sendable {
    case ready = "READY"
    case classificationRequired = "CLASSIFICATION_REQUIRED"
    case notApplicable = "NOT_APPLICABLE"
    case policyUnavailable = "POLICY_UNAVAILABLE"
    case noAvailableSize = "NO_AVAILABLE_SIZE"
    case noMeasurementData = "NO_MEASUREMENT_DATA"
    case mappingRequired = "MAPPING_REQUIRED"
    case insufficientMeasurements = "INSUFFICIENT_MEASUREMENTS"

    init(status: String) throws {
        guard let value = Self(rawValue: status) else {
            throw FitMatchVNextContractError.unknownState(
                field: "readiness.status",
                observed: status
            )
        }
        self = value
    }
}

/// Owns the intentionally narrow vNext compatibility policy. Classification,
/// recovery, comparison snapshot, and engine versions are separate concepts
/// and are never coalesced here.
nonisolated enum FitMatchVNextContractValidator {
    static let supportedSnapshotSchemaVersions: Set<Int> = [3, 4]
    static let completedReplayEngineVersion = "fitmatch-ios-vnext-snapshot-v1"
    static let pendingEngineVersion = "pending"

    static func readinessState(
        _ readiness: VNextProductReadinessDTO
    ) throws -> VNextReadinessState {
        try VNextReadinessState(status: readiness.status)
    }

    /// Live RPC responses must carry an explicit lifecycle status and an
    /// explicit top-level schema when the nested snapshot is present.
    static func validateLiveBegin(_ begin: VNextBeginComparisonDTO) throws {
        try validateBeginLifecycle(begin)
        let isOwnedSameIDReplay = !begin.created && begin.idempotent
        guard begin.declaredSnapshotSchemaVersion != nil || isOwnedSameIDReplay else {
            throw FitMatchVNextContractError.missingRequiredField(
                "snapshot_schema_version"
            )
        }
        try validateBeginSnapshot(
            begin,
            allowsMissingTopLevelVersion: isOwnedSameIDReplay
        )
    }

    /// A history replay is read-only. Older owned rows may omit a duplicated
    /// begin-envelope field, in which case their nested immutable snapshot is
    /// the only version source. This never makes a new live request valid.
    static func validateReplayBegin(_ begin: VNextBeginComparisonDTO) throws {
        guard begin.resultStatus == "PENDING" else {
            throw FitMatchVNextContractError.unknownState(
                field: "result_status",
                observed: begin.resultStatus
            )
        }
        try validateBeginSnapshot(begin, allowsMissingTopLevelVersion: true)
    }

    static func validateCompletedReplay(
        _ row: VNextComparisonHistoryDTO
    ) throws {
        guard row.resultStatus == "COMPLETED" else {
            throw FitMatchVNextContractError.unknownState(
                field: "comparison_history.result_status",
                observed: row.resultStatus
            )
        }
        try validateSupportedSnapshotVersion(row.snapshotSchemaVersion)
        guard row.engineVersion == completedReplayEngineVersion else {
            throw FitMatchVNextContractError.unsupportedEngineVersion(
                row.engineVersion
            )
        }
        guard let evidence = row.resultEvidence else {
            throw FitMatchVNextContractError.missingRequiredField(
                "result_evidence"
            )
        }
        guard evidence.engineVersion == completedReplayEngineVersion else {
            throw FitMatchVNextContractError.unsupportedEngineVersion(
                evidence.engineVersion
            )
        }
        guard row.engineVersion == evidence.engineVersion else {
            throw FitMatchVNextContractError.conflictingProof(
                "engine_version"
            )
        }
    }

    static func validatePendingReplay(
        _ row: VNextComparisonHistoryDTO
    ) throws {
        guard row.resultStatus == "PENDING" else {
            throw FitMatchVNextContractError.unknownState(
                field: "comparison_history.result_status",
                observed: row.resultStatus
            )
        }
        try validateSupportedSnapshotVersion(row.snapshotSchemaVersion)
        guard row.engineVersion == pendingEngineVersion else {
            throw FitMatchVNextContractError.unsupportedEngineVersion(
                row.engineVersion
            )
        }
        guard let begin = row.snapshotBegin else {
            throw FitMatchVNextContractError.missingRequiredField(
                "comparison_history.begin_snapshot"
            )
        }
        try validateReplayBegin(begin)
    }

    static func validateEngineInput(_ begin: VNextBeginComparisonDTO) throws {
        try validateReplayBegin(begin)
    }

    static func validateSupportedSnapshotVersion(_ version: Int) throws {
        guard supportedSnapshotSchemaVersions.contains(version) else {
            throw FitMatchVNextContractError.unsupportedSnapshotVersion(version)
        }
    }

    private static func validateBeginLifecycle(
        _ begin: VNextBeginComparisonDTO
    ) throws {
        switch begin.resultStatus {
        case "PENDING", "COMPLETED":
            return
        default:
            throw FitMatchVNextContractError.unknownState(
                field: "result_status",
                observed: begin.resultStatus
            )
        }
    }

    private static func validateBeginSnapshot(
        _ begin: VNextBeginComparisonDTO,
        allowsMissingTopLevelVersion: Bool
    ) throws {
        let nested = begin.snapshot.snapshotSchemaVersion
        try validateSupportedSnapshotVersion(nested)

        if let topLevel = begin.declaredSnapshotSchemaVersion {
            try validateSupportedSnapshotVersion(topLevel)
            guard topLevel == nested else {
                throw FitMatchVNextContractError.snapshotVersionMismatch(
                    topLevel: topLevel,
                    nested: nested
                )
            }
        } else if !allowsMissingTopLevelVersion {
            throw FitMatchVNextContractError.missingRequiredField(
                "snapshot_schema_version"
            )
        }

        if usesPersonalAuthority(begin.snapshot.authoritySnapshot) {
            guard nested == 4 else {
                throw FitMatchVNextContractError.unsupportedSnapshotVersion(nested)
            }
        }
    }

    private static func usesPersonalAuthority(_ authority: FitMatchJSONValue) -> Bool {
        guard let root = authority.objectValue,
              let effective = root["effective_classification_at_begin"]?.objectValue,
              let source = effective["source"]?.stringValue else {
            return false
        }
        return source.uppercased() == "USER_EXPLICIT"
    }
}
