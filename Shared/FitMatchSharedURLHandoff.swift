import Foundation

/// The single cross-process payload contract used by both the containing app
/// and the Share Extension.  A pending share is an ephemeral handoff, not a
/// user preference: one complete, versioned payload is atomically written to
/// the App Group container and acknowledgement is generation-aware.
enum FitMatchSharedURLHandoff {
    static let fileName = "FitMatchPendingProductURLHandoff-v1.json"
    static let timeToLive: TimeInterval = 15 * 60

    struct Payload: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let urlString: String
        let createdAt: Date
        let generation: String

        init(
            urlString: String,
            createdAt: Date,
            generation: String = UUID().uuidString
        ) {
            self.schemaVersion = 1
            self.urlString = urlString
            self.createdAt = createdAt
            self.generation = generation
        }
    }

    static func appGroupFileURL(identifier: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// File coordination gives the containing app and Share Extension a shared
/// critical section.  The payload itself is written atomically, so a reader
/// observes either the previous complete generation or the next complete
/// generation, never a partial collection of UserDefaults keys.
struct FitMatchSharedURLHandoffStore {
    struct Handoff: Equatable, Sendable {
        let urlString: String
        let token: String
    }

    enum PendingHandoffReadOutcome: Equatable, Sendable {
        case available(Handoff)
        case none
        case expired
        case malformed
        case storageUnavailable
    }

    private enum PayloadReadOutcome {
        case payload(FitMatchSharedURLHandoff.Payload)
        case none
        case malformed
        case storageUnavailable
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let coordinator: NSFileCoordinator

    init(
        fileURL: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default,
        coordinator: NSFileCoordinator = NSFileCoordinator()
    ) {
        self.fileURL = fileURL
        self.now = now
        self.fileManager = fileManager
        self.coordinator = coordinator
    }

    @discardableResult
    func save(_ url: URL) -> Bool {
        guard FitMatchProductURLRouting.provider(for: url) != nil else {
            return false
        }

        return (try? coordinateWrite { coordinatedURL in
            try ensureParentDirectory(for: coordinatedURL)
            let payload = FitMatchSharedURLHandoff.Payload(
                urlString: url.absoluteString,
                createdAt: now()
            )
            let data = try FitMatchSharedURLHandoff.makeEncoder().encode(payload)
            try data.write(to: coordinatedURL, options: .atomic)
            return true
        }) ?? false
    }

    func pendingHandoff() -> Handoff? {
        guard case .available(let handoff) = pendingHandoffOutcome() else {
            return nil
        }
        return handoff
    }

    func pendingHandoffOutcome() -> PendingHandoffReadOutcome {
        do {
            return try coordinateWrite { coordinatedURL in
                switch loadPayloadOrClearMalformed(at: coordinatedURL) {
                case .none:
                    return .none
                case .malformed:
                    return .malformed
                case .storageUnavailable:
                    return .storageUnavailable
                case .payload(let payload):
                    switch visibility(of: payload) {
                    case .visible:
                        return .available(
                            Handoff(urlString: payload.urlString, token: payload.generation)
                        )
                    case .expired:
                        try? removePayload(at: coordinatedURL)
                        return .expired
                    case .malformed:
                        try? removePayload(at: coordinatedURL)
                        return .malformed
                    }
                }
            }
        } catch {
            return .storageUnavailable
        }
    }

    @discardableResult
    func acknowledge(
        urlString expectedURLString: String? = nil,
        generation expectedGeneration: String? = nil
    ) -> Bool {
        (try? coordinateWrite { coordinatedURL in
            guard case .payload(let payload) = loadPayloadOrClearMalformed(
                at: coordinatedURL
            ) else {
                return false
            }
            guard case .visible = visibility(of: payload) else {
                try removePayload(at: coordinatedURL)
                return false
            }
            if let expectedURLString, payload.urlString != expectedURLString {
                return false
            }
            if let expectedGeneration, payload.generation != expectedGeneration {
                return false
            }
            try removePayload(at: coordinatedURL)
            return true
        }) ?? false
    }

    func consume() -> String? {
        guard let handoff = pendingHandoff(),
              acknowledge(
                urlString: handoff.urlString,
                generation: handoff.token
              ) else {
            return nil
        }
        return handoff.urlString
    }

    private enum PayloadVisibility {
        case visible
        case expired
        case malformed
    }

    private func visibility(of payload: FitMatchSharedURLHandoff.Payload) -> PayloadVisibility {
        guard payload.schemaVersion == 1,
              !payload.generation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: payload.urlString),
              FitMatchProductURLRouting.provider(for: url) != nil else {
            return .malformed
        }
        let age = now().timeIntervalSince(payload.createdAt)
        guard age >= 0 else { return .malformed }
        return age <= FitMatchSharedURLHandoff.timeToLive ? .visible : .expired
    }

    private func loadPayloadOrClearMalformed(
        at coordinatedURL: URL
    ) -> PayloadReadOutcome {
        guard fileManager.fileExists(atPath: coordinatedURL.path) else {
            return .none
        }
        do {
            let data = try Data(contentsOf: coordinatedURL)
            do {
                return .payload(
                    try FitMatchSharedURLHandoff.makeDecoder().decode(
                    FitMatchSharedURLHandoff.Payload.self,
                    from: data
                    )
                )
            } catch {
                try? removePayload(at: coordinatedURL)
                return .malformed
            }
        } catch {
            // A storage failure is not corrupt payload evidence. Keep it in
            // place for retry and let the app distinguish this from malformed
            // data in its user-facing recovery state.
            return .storageUnavailable
        }
    }

    private func removePayload(at coordinatedURL: URL) throws {
        guard fileManager.fileExists(atPath: coordinatedURL.path) else { return }
        try fileManager.removeItem(at: coordinatedURL)
    }

    private func ensureParentDirectory(for coordinatedURL: URL) throws {
        try fileManager.createDirectory(
            at: coordinatedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func coordinateWrite<T>(
        _ work: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                result = .success(try work(coordinatedURL))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try result.get()
    }
}
