import Foundation
import Testing
@testable import FitMatch

/// Opt-in live development checks. The runner must complete credential preflight
/// before selecting these tests. Missing setup records BLOCKED and fails; never skips.
@MainActor
struct FitMatchReleaseAuthenticatedTests {
    @Test func dedicatedDevelopmentAccountsExerciseRealSwiftClosetLifecycle() async {
        await execute(full: false)
    }

    @Test func dedicatedDevelopmentAccountsExerciseRealSwiftAH() async {
        await execute(full: true)
    }

    @Test func interruptedDevelopmentRunCleansOnlyValidatedLedger() async {
        let result = await ReleaseAuthenticatedRun.executeCleanup()
        if result != "PASS" {
            Issue.record(Comment(rawValue: "\(result): interrupted ledger cleanup remains unresolved; no skipped success"))
        }
    }

    private func execute(full: Bool) async {
        let result = await ReleaseAuthenticatedRun.execute(full: full)
        if result != "PASS" {
            Issue.record(Comment(rawValue: "\(result): see sanitized authenticated QA report; no skipped success"))
        }
    }
}
