import Foundation

/// Completed v1 rows were emitted by two shipped reliability formulas.
/// Accept only those formulas; never rewrite immutable historical evidence.
/// v2 separates the current count policy from that legacy ambiguity.
nonisolated enum VNextCompletedReplayPolicy {
    static let legacyVersion = "fitmatch-ios-vnext-snapshot-v1"
    static let currentVersion = "fitmatch-ios-vnext-snapshot-v2"
    static let supportedVersions: Set<String> = [legacyVersion, currentVersion]

    static func acceptsReliability(
        _ stored: Int, engineVersion: String, evidenceCount: Int, coverage: Double
    ) -> Bool {
        guard supportedVersions.contains(engineVersion), evidenceCount > 0,
              coverage.isFinite, coverage >= 0, coverage <= 1 else { return false }
        let current = min(5, max(1, evidenceCount))
        if stored == current { return true }
        guard engineVersion == legacyVersion else { return false }
        let legacy: Int
        if evidenceCount >= 4, coverage >= 0.75 { legacy = 5 }
        else if evidenceCount >= 3, coverage >= 0.5 { legacy = 4 }
        else if evidenceCount >= 2 { legacy = 3 }
        else { legacy = 2 }
        return stored == legacy
    }
}
