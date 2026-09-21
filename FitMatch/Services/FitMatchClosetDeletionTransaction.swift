import Foundation

@MainActor
protocol FitMatchClosetDeleting {
    func deleteServerFirst(
        clientItemID: UUID,
        prepare: () async throws -> Void,
        commit: () throws -> Void
    ) async throws
}

/// The ordering used by Closet deletion and its queued retry. All callbacks
/// execute on the owning account's main actor; no local success precedes proof.
@MainActor
enum FitMatchClosetDeletionTransaction {
    enum Failure: Error, Equatable {
        case sessionChanged
        case invalidReceipt
        case synchronizationInProgress
    }

    /// Yield while the coordinator owns the sync lock. The caller must acquire
    /// that lock immediately after return, without another suspension point.
    static func waitForSynchronization(
        isCurrent: () -> Bool,
        isBusy: () -> Bool,
        maximumWaits: Int = 300,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }
    ) async throws {
        var waits = 0
        while true {
            try Task.checkCancellation()
            guard isCurrent() else { throw Failure.sessionChanged }
            guard isBusy() else { return }
            guard waits < maximumWaits else { throw Failure.synchronizationInProgress }
            waits += 1
            try await pause()
        }
    }

    static func run(
        isCurrent: () -> Bool,
        prepare: () async throws -> Void,
        resolve: () async throws -> UUID?,
        recordIntent: () -> Void,
        delete: (UUID) async throws -> (id: UUID, deletedAt: String),
        commit: () throws -> Void
    ) async throws {
        func check() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw Failure.sessionChanged }
        }
        try check()
        try await prepare()
        try check()
        let remoteID = try await resolve()
        try check()
        // Persist intent before a possibly ambiguous transport response.
        recordIntent()
        if let remoteID {
            let receipt = try await delete(remoteID)
            try check()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fractional = formatter.date(from: receipt.deletedAt)
            formatter.formatOptions = [.withInternetDateTime]
            guard receipt.id == remoteID,
                  fractional != nil || formatter.date(from: receipt.deletedAt) != nil else {
                throw Failure.invalidReceipt
            }
        }
        try check()
        try commit()
    }
}
