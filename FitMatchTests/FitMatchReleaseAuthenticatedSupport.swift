import Foundation
import Supabase
@testable import FitMatch

enum ReleaseAuthFailure: Error {
    case blocked(String)
    case failed(String)
    var code: String {
        switch self { case .blocked(let code), .failed(let code): return code }
    }
    var status: String {
        switch self { case .blocked: return "BLOCKED"; case .failed: return "FAIL" }
    }
}

struct ReleaseAuthConfiguration {
    static let project = "hnkplvyegonlhumlejst"
    static let base = "https://hnkplvyegonlhumlejst.supabase.co"
    struct Credential {
        let id: UUID
        let access: String
        let refresh: String
        let expiry: Double
    }
    let key: String
    let users: [String: Credential]
    let runID: UUID
    let output: URL
    let manifest: ReleaseAuthManifest?

    static func value(_ name: String, env: [String: String]) throws -> String {
        let direct = env[name], forwarded = env["TEST_RUNNER_" + name]
        if let direct, let forwarded, direct != forwarded {
            throw ReleaseAuthFailure.blocked("conflicting_environment_" + name)
        }
        guard let value = direct ?? forwarded, !value.isEmpty else {
            throw ReleaseAuthFailure.blocked("missing_environment_" + name)
        }
        return value
    }

    static func claims(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw ReleaseAuthFailure.blocked("malformed_jwt") }
        var body = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard let data = Data(base64Encoded: body),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReleaseAuthFailure.blocked("malformed_jwt")
        }
        return claims
    }

    static func load(full: Bool, env: [String: String]) throws -> Self {
        let url = try value("FITMATCH_QA_DB_URL", env: env)
        guard url == base || url == base + "/" else {
            throw ReleaseAuthFailure.blocked("exact_development_url_required")
        }
        guard try value("FITMATCH_QA_DB_DEDICATED_USERS", env: env) == "1" else {
            throw ReleaseAuthFailure.blocked("dedicated_account_attestation_required")
        }
        let key = try value("FITMATCH_QA_DB_PUBLIC_KEY", env: env)
        if !key.hasPrefix("sb_publishable_") {
            let decoded = try claims(key)
            guard decoded["role"] as? String == "anon", decoded["ref"] as? String == project else {
                throw ReleaseAuthFailure.blocked("development_public_key_required")
            }
        }
        var users: [String: Credential] = [:]
        for label in ["A", "B"] {
            let prefix = "FITMATCH_QA_DB_USER_" + label
            guard let id = UUID(uuidString: try value(prefix + "_ID", env: env)) else {
                throw ReleaseAuthFailure.blocked("invalid_expected_user_uuid")
            }
            let access = try value(prefix + "_TOKEN", env: env)
            let refresh = try value(prefix + "_REFRESH_TOKEN", env: env)
            let decoded = try claims(access)
            guard decoded["iss"] as? String == base + "/auth/v1",
                  decoded["role"] as? String == "authenticated",
                  UUID(uuidString: decoded["sub"] as? String ?? "") == id,
                  decoded["is_anonymous"] as? Bool == false,
                  let expiry = decoded["exp"] as? Double, expiry.isFinite,
                  expiry > Date().timeIntervalSince1970 + 600 else {
                throw ReleaseAuthFailure.blocked("normal_fresh_development_session_required")
            }
            users[label] = Credential(id: id, access: access, refresh: refresh, expiry: expiry)
        }
        guard users["A"]?.id != users["B"]?.id else {
            throw ReleaseAuthFailure.blocked("distinct_users_required")
        }
        guard let runID = UUID(uuidString: try value("FITMATCH_QA_AUTH_RUN_ID", env: env)) else {
            throw ReleaseAuthFailure.blocked("invalid_run_uuid")
        }
        let path = try value("FITMATCH_QA_AUTH_OUTPUT", env: env)
        guard path.hasPrefix("/"), !path.hasSuffix("/"), !path.contains("\0") else {
            throw ReleaseAuthFailure.blocked("absolute_output_file_required")
        }
        let manifest: ReleaseAuthManifest?
        if full {
            let path = try value("FITMATCH_QA_DB_CASE_MANIFEST", env: env)
            guard path.hasPrefix("/"),
                  let data = FileManager.default.contents(atPath: path),
                  let value = try? JSONDecoder().decode(ReleaseAuthManifest.self, from: data),
                  value.project == project, value.version == 1, !value.cases.isEmpty,
                  Set(value.cases.map(\.id)).count == value.cases.count else {
                throw ReleaseAuthFailure.blocked("verified_development_seed_manifest_required")
            }
            manifest = value
        } else { manifest = nil }
        return Self(key: key, users: users, runID: runID,
                    output: URL(fileURLWithPath: path), manifest: manifest)
    }
}

struct ReleaseAuthManifest: Decodable {
    let version: Int
    let project: String
    let cases: [Case]
    struct Case: Decodable {
        let id: String
        let expectedGroup: String
        let reference: Seed
        let secondReference: Seed
        let target: Seed
    }
    struct Seed: Decodable {
        let resolution: FitMatchProductResolutionRequest
        let productID: UUID
        let variantID: UUID
        let sourceObservationID: UUID
        let selectedSizeID: UUID
        let alternateSizeID: UUID
        let sizes: [Size]
    }
    struct Size: Decodable {
        let id: UUID
        let sourceMeasurementCount: Int
        let canonicalMeasurementCount: Int
    }
}

private final class ReleaseAuthMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }; values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }; values[key] = nil
    }
}

private final class ReleaseAuthTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return completed }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); defer { lock.unlock() }; completed += 1
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
private final class ReleaseAuthConnection {
    let client: SupabaseClient
    let domain: FitMatchSupabaseDomainClient
    let transport = ReleaseAuthTransport()
    let session: URLSession
    init(config: ReleaseAuthConfiguration) {
        let options = URLSessionConfiguration.ephemeral
        options.httpCookieStorage = nil
        options.timeoutIntervalForRequest = 30
        options.timeoutIntervalForResource = 60
        session = URLSession(configuration: options, delegate: transport, delegateQueue: nil)
        client = SupabaseClient(
            supabaseURL: URL(string: ReleaseAuthConfiguration.base)!, supabaseKey: config.key,
            options: .init(auth: .init(storage: ReleaseAuthMemoryStorage(),
                storageKey: "qa-" + UUID().uuidString, autoRefreshToken: false),
                global: .init(session: session))
        )
        domain = FitMatchSupabaseDomainClient(authenticatedClient: client)
    }
}

@MainActor
final class ReleaseAuthenticatedRun {
    struct CaseResult: Codable {
        let id: String
        let status: String
        let detail: String
    }
    struct Report: Codable {
        var version = 1
        var project = ReleaseAuthConfiguration.project
        var status = "BLOCKED"
        var evidence_kind = "authenticated_swift_domain_owners"
        var swift_owner_proof = false
        var request_count = 0
        var real_db_case_count = 0
        var mock_case_count = 0
        var run_id: String?
        var expected_case_ids: [String] = []
        var cases: [CaseResult] = []
        var reason: String?
        var cleanup = "NOT RUN"
        var full_ah_status = "BLOCKED"
    }
    struct Item: Codable {
        let clientID: UUID
        var serverID: UUID?
        let marker: String
        let productID: UUID?
        let variantID: UUID?
        var attempted = false
        var deleted = false
    }
    struct Comparison: Codable {
        let clientID: UUID
        let referenceClientID: UUID
        let targetID: UUID
        let variantID: UUID
        var serverID: UUID?
        var completed = false
        var hidden = false
    }
    struct Ledger: Codable {
        // Decodable must read these values from a restored ledger. A let with
        // an initial value would silently retain the local default on decode.
        var version = 1
        var project = ReleaseAuthConfiguration.project
        let runID: UUID
        let ownerID: UUID
        let observerID: UUID
        var items: [Item] = []
        var comparisons: [Comparison] = []
        var cleanup = "not_started"
    }

    let config: ReleaseAuthConfiguration
    var report = Report()
    var ledger: Ledger
    private var connections: [ReleaseAuthConnection] = []
    private var currentCase = "AUTH-VERIFY"
    private let restoredLedgerURL: URL?
    private var ledgerURL: URL { restoredLedgerURL ?? URL(fileURLWithPath: config.output.path + ".ledger.json") }

    init(config: ReleaseAuthConfiguration, restoring restored: Ledger? = nil, ledgerURL: URL? = nil) throws {
        self.config = config
        restoredLedgerURL = ledgerURL
        ledger = restored ?? Ledger(runID: config.runID, ownerID: config.users["A"]!.id,
                        observerID: config.users["B"]!.id)
        report.run_id = config.runID.uuidString.lowercased()
        report.expected_case_ids = ["AUTH-VERIFY"] + (config.manifest.map { manifest in
            manifest.cases.flatMap { seed in
                ["A", "ISOLATION", "D", "F", "B", "G", "H", "E", "C"].map { seed.id + "/" + $0 }
            }
        } ?? ["A-MANUAL", "ISOLATION", "B-MANUAL", "C-MANUAL"])
        guard !FileManager.default.fileExists(atPath: config.output.path),
              restored != nil || !FileManager.default.fileExists(atPath: self.ledgerURL.path) else {
            throw ReleaseAuthFailure.blocked("new_output_and_ledger_required")
        }
    }

    static func executeCleanup() async -> String {
        let env = ProcessInfo.processInfo.environment
        do {
            let config = try ReleaseAuthConfiguration.load(full: false, env: env)
            let path = try ReleaseAuthConfiguration.value("FITMATCH_QA_AUTH_LEDGER", env: env)
            guard path.hasPrefix("/") else { throw ReleaseAuthFailure.blocked("absolute_ledger_file_required") }
            let url = URL(fileURLWithPath: path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  url.standardizedFileURL != config.output.standardizedFileURL else {
                throw ReleaseAuthFailure.blocked("regular_distinct_ledger_file_required")
            }
            let ledger = try ReleaseAuthLedgerSafety.decode(Data(contentsOf: url),
                runID: config.runID, ownerID: config.users["A"]!.id, observerID: config.users["B"]!.id)
            let run = try Self(config: config, restoring: ledger, ledgerURL: url)
            return await run.resumeCleanup()
        } catch {
            var report = Report()
            report.evidence_kind = "authenticated_swift_ledger_cleanup"
            report.expected_case_ids = ["AUTH-VERIFY", "LEDGER-CLEANUP"]
            report.reason = (error as? ReleaseAuthFailure)?.code ?? "cleanup_configuration_invalid"
            if let text = try? ReleaseAuthConfiguration.value("FITMATCH_QA_AUTH_RUN_ID", env: env),
               let id = UUID(uuidString: text) { report.run_id = id.uuidString.lowercased() }
            if let path = try? ReleaseAuthConfiguration.value("FITMATCH_QA_AUTH_OUTPUT", env: env),
               path.hasPrefix("/"), !FileManager.default.fileExists(atPath: path) {
                try? write(report, to: URL(fileURLWithPath: path))
            }
            print("FITMATCH_QA_AUTH_RESULT BLOCKED: cleanup_configuration_missing_or_invalid")
            return "BLOCKED"
        }
    }

    private func resumeCleanup() async -> String {
        report.evidence_kind = "authenticated_swift_ledger_cleanup"
        report.expected_case_ids = ["AUTH-VERIFY", "LEDGER-CLEANUP"]
        do {
            let a = try await live("A")
            _ = try await live("B")
            passed("AUTH-VERIFY", "Both normal SDK identities match the original ledger")
            currentCase = "LEDGER-CLEANUP"
            // Validate the entire remote ownership plan before any mutation.
            // A restored file is untrusted; its recorded IDs alone authorize nothing.
            let rows = try await a.listClosetItems()
            let history = try await a.fetchVNextComparisonHistorySync()
            var verifiedActiveClients = Set<UUID>()
            var reconciled = ledger
            for index in ledger.items.indices {
                let item = ledger.items[index]
                let matches = rows.items.filter { $0.clientItemID == item.clientID }
                let proofs = matches.map { ReleaseAuthLedgerSafety.ItemProof(row: $0) }
                let serverID = try ReleaseAuthLedgerSafety.validateItem(item, proofs: proofs)
                if let serverID {
                    let exact = try await a.getClosetItem(closetItemID: serverID)
                    _ = try ReleaseAuthLedgerSafety.validateItem(item,
                        proofs: exact.items.map { ReleaseAuthLedgerSafety.ItemProof(row: $0) })
                    reconciled.items[index].serverID = serverID
                    verifiedActiveClients.insert(item.clientID)
                } else if let serverID = item.serverID {
                    let exact = try await a.getClosetItem(closetItemID: serverID)
                    try check(exact.items.isEmpty, "deleted_ledger_item_is_still_active")
                }
            }
            for index in ledger.comparisons.indices {
                let entry = ledger.comparisons[index]
                let active = history.histories.filter { $0.clientComparisonID == entry.clientID }
                let tombstones = history.tombstones.filter { $0.clientComparisonID == entry.clientID }
                reconciled.comparisons[index].hidden = try ReleaseAuthLedgerSafety.validateComparison(entry,
                    proofs: active.map { ReleaseAuthLedgerSafety.ComparisonProof(row: $0) },
                    tombstoneCount: tombstones.count,
                    verifiedActiveReference: verifiedActiveClients.contains(entry.referenceClientID))
            }
            ledger = reconciled
            try saveLedger()
            try await cleanup()
            passed("LEDGER-CLEANUP", "Exact validated run rows reconciled and no longer active; tombstones retained")
            report.cleanup = "PASS: no active run-owned rows; tombstones retained"
            report.status = "PASS"
            report.swift_owner_proof = true
        } catch {
            report.status = "BLOCKED"
            report.reason = (error as? ReleaseAuthFailure)?.code ?? "cleanup_auth_or_contract_unavailable"
            report.cleanup = "BLOCKED: preserve ownership ledger for exact reconciliation"
            report.cases.append(.init(id: currentCase, status: "BLOCKED", detail: report.reason!))
        }
        report.request_count = connections.reduce(0) { $0 + $1.transport.count }
        report.real_db_case_count = report.cases.filter { $0.id == "LEDGER-CLEANUP" && $0.status == "PASS" }.count
        for connection in connections { connection.session.invalidateAndCancel() }
        do { try Self.write(report, to: config.output) }
        catch { print("FITMATCH_QA_AUTH_RESULT BLOCKED: cleanup_report_write_failed"); return "BLOCKED" }
        print("FITMATCH_QA_AUTH_RESULT \(report.status)")
        return report.status
    }

    static func execute(full: Bool) async -> String {
        let env = ProcessInfo.processInfo.environment
        do {
            let config = try ReleaseAuthConfiguration.load(full: full, env: env)
            let run = try ReleaseAuthenticatedRun(config: config)
            return await run.run(full: full)
        } catch {
            var report = Report()
            report.reason = (error as? ReleaseAuthFailure)?.code ?? "configuration_invalid"
            if let path = try? ReleaseAuthConfiguration.value("FITMATCH_QA_AUTH_OUTPUT", env: env),
               path.hasPrefix("/"), !FileManager.default.fileExists(atPath: path) {
                try? write(report, to: URL(fileURLWithPath: path))
            }
            print("FITMATCH_QA_AUTH_RESULT BLOCKED: configuration_missing_or_invalid")
            return "BLOCKED"
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func saveLedger() throws { try Self.write(ledger, to: ledgerURL) }
    private func check(_ condition: Bool, _ code: String) throws {
        guard condition else { throw ReleaseAuthFailure.failed(code) }
    }
    private func passed(_ id: String, _ detail: String) {
        report.cases.append(.init(id: id, status: "PASS", detail: detail))
    }
    private func live(_ label: String) async throws -> FitMatchSupabaseDomainClient {
        guard let user = config.users[label], user.expiry > Date().timeIntervalSince1970 + 120 else {
            throw ReleaseAuthFailure.blocked("fresh_session_required_before_operation")
        }
        let connection = ReleaseAuthConnection(config: config)
        connections.append(connection)
        // Normal SDK verification calls /auth/v1/user. No synthetic Session,
        // admin key, impersonation, external session store or token fallback.
        let session = try await connection.client.auth.setSession(
            accessToken: user.access, refreshToken: user.refresh)
        try check(session.user.id == user.id && session.user.role == "authenticated"
                  && session.user.isAnonymous == false, "auth_identity_mismatch")
        return connection.domain
    }

    private func run(full: Bool) async -> String {
        do {
            let a = try await live("A"), b = try await live("B")
            let aItems = try await a.listClosetItems(), bItems = try await b.listClosetItems()
            let aHistory = try await a.fetchVNextComparisonHistory()
            let bHistory = try await b.fetchVNextComparisonHistory()
            try check(aItems.items.isEmpty && bItems.items.isEmpty
                      && aHistory.isEmpty && bHistory.isEmpty, "dedicated_accounts_must_be_empty")
            try saveLedger()
            passed("AUTH-VERIFY", "Two normal SDK sessions verified; both active accounts empty")
            if full, let manifest = config.manifest {
                for seed in manifest.cases { try await exercise(seed) }
                report.full_ah_status = "PASS"
            } else { try await manual() }
            try check(report.cases.map(\.id).sorted() == report.expected_case_ids.sorted()
                && report.cases.allSatisfy { $0.status == "PASS" }, "required_cases_incomplete")
            report.status = "PASS"
            report.swift_owner_proof = true
        } catch {
            let failure = error as? ReleaseAuthFailure
            report.status = failure?.status ?? "FAIL"
            report.reason = failure?.code ?? "sdk_or_contract_operation_failed"
            report.cases.append(.init(id: currentCase, status: report.status,
                detail: report.reason!))
        }
        if !ledger.items.isEmpty || !ledger.comparisons.isEmpty {
            do { try await cleanup(); report.cleanup = "PASS: no active run-owned rows; tombstones retained" }
            catch {
                report.cleanup = "BLOCKED: preserve ownership ledger for exact reconciliation"
                report.status = "BLOCKED"
                report.full_ah_status = "BLOCKED"
                ledger.cleanup = "blocked_reconcile_exact_ids"
                try? saveLedger()
            }
        }
        report.request_count = connections.reduce(0) { $0 + $1.transport.count }
        report.real_db_case_count = report.cases.filter { $0.status == "PASS" && $0.id != "AUTH-VERIFY" }.count
        for connection in connections { connection.session.invalidateAndCancel() }
        do { try Self.write(report, to: config.output) }
        catch { print("FITMATCH_QA_AUTH_RESULT BLOCKED: report_write_failed"); return "BLOCKED" }
        print("FITMATCH_QA_AUTH_RESULT \(report.status)")
        return report.status
    }

    private func marker(_ id: UUID) -> String {
        "fitmatch-release-qa:" + config.runID.uuidString.lowercased() + ":" + id.uuidString.lowercased()
    }
    private func manualRequest(id: UUID, satisfaction: Int = 3) -> FitMatchUpsertClosetItemRequest {
        let item = UserFit(id: id, sourceType: .manual, brandName: "QA", gender: .unisex,
            productName: marker(id), category: .top, detailCategory: .shortSleeve,
            sizeName: "M", measurements: .init(shoulder: 48, chest: 52, totalLength: 70, sleeveLength: 24),
            fitMemo: marker(id), satisfaction: satisfaction)
        item.categoryCode = "tops"; item.detailCategoryCode = "short_sleeve"
        item.garmentTypeRawValue = "tshirt"; item.sleeveTypeRawValue = "short_sleeve"
        item.markClassificationAuthority(.userExplicit)
        return .init(clientItemID: id, item: FitMatchClosetSyncCoordinator().payload(for: item),
            productID: nil, productSizeID: nil, override: nil)
    }
    private func create(_ request: FitMatchUpsertClosetItemRequest) async throws -> FitMatchClosetItemRecord {
        ledger.items.append(Item(clientID: request.clientItemID, serverID: nil,
            marker: request.item.fitMemo, productID: request.productID, variantID: request.productVariantID))
        let index = ledger.items.count - 1
        ledger.items[index].attempted = true
        try saveLedger() // Includes ambiguous create window before the RPC.
        let remote = try await live("A")
        let receipt = try await remote.upsertClosetItem(request)
        ledger.items[index].serverID = receipt.closetItemID
        try saveLedger()
        return try await read(item: ledger.items[index])
    }
    private func read(item: Item) async throws -> FitMatchClosetItemRecord {
        guard let id = item.serverID else { throw ReleaseAuthFailure.blocked("unknown_created_server_id") }
        let remote = try await live("A")
        let response = try await remote.getClosetItem(closetItemID: id)
        try check(response.items.count == 1, "exact_read_cardinality")
        let row = response.items[0]
        try ownership(row, item)
        return row
    }
    private func ownership(_ row: FitMatchClosetItemRecord, _ item: Item) throws {
        try check(row.clientItemID == item.clientID && row.fitMemo == item.marker
            && row.productID == item.productID && row.variantID == item.variantID
            && (item.serverID == nil || row.closetItemID == item.serverID), "run_identity_mismatch")
    }
    private func isolation(_ row: FitMatchClosetItemRecord,
                           request: FitMatchUpsertClosetItemRequest, caseID: String = "ISOLATION") async throws {
        currentCase = caseID
        let b = try await live("B")
        let found = try await b.getClosetItem(closetItemID: row.closetItemID)
        let listed = try await b.listClosetItems()
        try check(found.items.isEmpty && listed.items.isEmpty, "other_user_can_read")
        for operation in ["update", "delete"] {
            var rejected = false
            do {
                if operation == "update" { _ = try await b.updateClosetItem(request, closetItemID: row.closetItemID) }
                else { _ = try await b.deleteClosetItem(closetItemID: row.closetItemID) }
            } catch let error as PostgrestError {
                // Transport/auth failures do not establish ownership isolation.
                rejected = ["42501", "P0001", "P0002"].contains(error.code ?? "")
            }
            try check(rejected, "other_user_mutation_not_authoritatively_rejected")
            guard let item = ledger.items.first(where: { $0.clientID == row.clientItemID }) else {
                throw ReleaseAuthFailure.failed("missing_ownership_ledger")
            }
            let unchanged = try await read(item: item)
            try check(unchanged == row, "other_user_mutation_changed_owner_row")
        }
        passed(caseID, "B cannot read/update/delete A; A unchanged after each attempt")
    }
    private func delete(_ item: Item) async throws {
        _ = try await read(item: item)
        let a = try await live("A")
        var commits = 0
        try await FitMatchClosetDeletionTransaction.run(isCurrent: { true }, prepare: {},
            resolve: { item.serverID }, recordIntent: {}, delete: { id in
                let receipt = try await a.deleteClosetItem(closetItemID: id)
                return (receipt.closetItemID, receipt.deletedAt)
            }, commit: { commits += 1 })
        try check(commits == 1, "delete_transaction_commit_count")
        let fresh = try await live("A")
        let exact = try await fresh.getClosetItem(closetItemID: item.serverID!)
        let rows = try await fresh.listClosetItems()
        try check(exact.items.isEmpty && !rows.items.contains { $0.clientItemID == item.clientID },
                  "deleted_row_still_active")
        if let index = ledger.items.firstIndex(where: { $0.clientID == item.clientID }) {
            ledger.items[index].deleted = true; try saveLedger()
        }
    }
    private func manual() async throws {
        currentCase = "A-MANUAL"
        let request = manualRequest(id: UUID())
        let row = try await create(request)
        let sentinel = try await create(manualRequest(id: UUID()))
        try check(row.satisfaction == 3 && row.measurementRecords.contains { $0.value == 52 }, "manual_measurement_readback")
        let a = try await live("A")
        let repeated = try await a.upsertClosetItem(request)
        let rows = try await a.listClosetItems()
        try check(repeated.closetItemID == row.closetItemID
            && rows.items.filter { $0.clientItemID == request.clientItemID }.count == 1, "retry_identity_changed")
        passed("A-MANUAL", "Same request keeps exact server/client ID; fresh-client read-back")
        try await isolation(row, request: manualRequest(id: request.clientItemID, satisfaction: 1))
        currentCase = "B-MANUAL"
        _ = try await a.updateClosetItem(manualRequest(id: request.clientItemID, satisfaction: 4), closetItemID: row.closetItemID)
        let edited = try await read(item: ledger.items[0])
        let untouched = try await read(item: ledger.items[1])
        try check(edited.satisfaction == 4 && edited.measurementRecords == row.measurementRecords
                  && untouched == sentinel, "manual_edit_isolation")
        passed("B-MANUAL", "Only selected metadata changes; sentinel and measurements preserved")
        currentCase = "C-MANUAL"
        try await delete(ledger.items[0])
        try check(try await read(item: ledger.items[1]) == sentinel, "delete_changed_unrelated_row")
        passed("C-MANUAL", "Real deletion transaction and fresh exact read; sentinel preserved")
    }

    private func verifySeed(_ seed: ReleaseAuthManifest.Seed, group: String) async throws -> FitMatchProductRuntimeResponse {
        let a = try await live("A")
        let runtime = try await a.fetchProductRuntime(seed.resolution)
        try check(runtime.product.productID == seed.productID && runtime.comparisonReady
            && runtime.vnext?.comparisonGroup?.groupCode == group
            && runtime.classification?.status == "confirmed", "seed_runtime_not_ready_or_identity_mismatch")
        guard let variant = runtime.variants.first(where: { $0.variantID == seed.variantID }) else {
            throw ReleaseAuthFailure.blocked("seed_variant_not_in_runtime")
        }
        for id in [seed.selectedSizeID, seed.alternateSizeID] {
            try check(variant.sizes.contains { $0.productSizeID == id }
                && seed.sizes.contains { $0.id == id && $0.sourceMeasurementCount > 0 && $0.canonicalMeasurementCount > 0 },
                "seed_size_or_expected_measurement_counts_missing")
        }
        return runtime
    }
    private func linkedRequest(seed: ReleaseAuthManifest.Seed, runtime: FitMatchProductRuntimeResponse,
                               sizeID: UUID, clientID: UUID, satisfaction: Int = 3) throws -> FitMatchUpsertClosetItemRequest {
        guard let classification = runtime.classification, let category = classification.categoryCode,
              let garment = classification.garmentTypeCode, let audience = runtime.product.audience,
              let size = runtime.variants.first(where: { $0.variantID == seed.variantID })?.sizes.first(where: { $0.productSizeID == sizeID }) else {
            throw ReleaseAuthFailure.blocked("seed_server_tuple_incomplete")
        }
        let time = ISO8601DateFormatter().string(from: Date())
        let item = FitMatchClosetItemPayload(productName: marker(clientID), brand: nil,
            sizeName: size.sizeLabel, genderCode: audience, source: runtime.product.source,
            categoryCode: category, detailCode: garment, familyCode: garment,
            lengthCode: classification.lengthCode, bodyLengthCode: classification.bodyLengthCode,
            sourceCategoryPath: runtime.product.sourceCategoryPath, productURL: runtime.product.canonicalURL,
            imageURL: runtime.product.imageURL, measurements: [:], measurementRecords: [],
            fitMemo: marker(clientID), fitPreferenceCode: "regular", satisfaction: satisfaction,
            isReference: false, classificationVersion: nil, clientSnapshot: [:],
            clientCreatedAt: time, clientUpdatedAt: time)
        return .init(clientItemID: clientID, item: item, productID: seed.productID,
            productVariantID: seed.variantID, productSizeID: sizeID, override: nil,
            sourceObservationID: seed.sourceObservationID)
    }
    private func linkedRead(_ row: FitMatchClosetItemRecord, seed: ReleaseAuthManifest.Seed,
                            sizeID: UUID) throws {
        guard let snapshot = row.sourceMeasurementSnapshot,
              let raw = row.sourceMeasurements, let expected = seed.sizes.first(where: { $0.id == sizeID }) else {
            throw ReleaseAuthFailure.failed("linked_snapshot_missing")
        }
        try check(row.productID == seed.productID && row.variantID == seed.variantID
            && row.productSizeID == sizeID && snapshot.productID == seed.productID
            && snapshot.productVariantID == seed.variantID && snapshot.productSizeID == sizeID
            && snapshot.sourceObservationID == seed.sourceObservationID
            && snapshot.sourceMeasurementCount == expected.sourceMeasurementCount
            && raw.count == expected.sourceMeasurementCount
            && row.measurements.count == expected.canonicalMeasurementCount,
            "linked_identity_or_measurement_counts_mismatch")
    }

    private func compare(seed: ReleaseAuthManifest.Seed, reference: FitMatchClosetItemRecord,
                         group: String) async throws -> (VNextComparisonHistoryDTO, VNextComparisonBatchAnalysis) {
        let a = try await live("A")
        let eligibility = try await a.eligibleCandidateSizes(referenceClosetItemID: reference.closetItemID,
            targetProductID: seed.productID, targetVariantID: seed.variantID, manualExplicit: true)
        guard eligibility.allowed, eligibility.referenceClosetItemID == reference.closetItemID,
              eligibility.targetProductID == seed.productID, eligibility.targetVariantID == seed.variantID,
              eligibility.targetComparisonGroup?.groupCode == group,
              eligibility.authorizedCandidateProductSizeIDs.contains(seed.selectedSizeID),
              eligibility.authorizedCandidateProductSizeIDs.contains(seed.alternateSizeID),
              let fingerprint = eligibility.candidateAuthorityFingerprint, !fingerprint.isEmpty,
              let effective = eligibility.effectiveAuthorityFingerprint, !effective.isEmpty else {
            throw ReleaseAuthFailure.blocked("exact_seed_pair_not_server_authorized")
        }
        // Preserve each earlier completed row's ownership evidence before the
        // server's next completion advances this product's visible head.
        ledger = try await ReleaseAuthComparisonRetirement.beforeNextComparison(
            ledger: ledger, targetID: seed.productID,
            read: { entry in
                let fresh = try await self.live("A")
                let sync = try await fresh.fetchVNextComparisonHistorySync()
                var listed: [ReleaseAuthLedgerSafety.ItemProof] = []
                var exact: [ReleaseAuthLedgerSafety.ItemProof] = []
                if !sync.tombstones.contains(where: { $0.clientComparisonID == entry.clientID }) {
                    guard let item = self.ledger.items.first(where: { $0.clientID == entry.referenceClientID }),
                          let serverID = item.serverID else {
                        throw ReleaseAuthFailure.blocked("retirement_reference_missing")
                    }
                    listed = try await fresh.listClosetItems().items.map { .init(row: $0) }
                    exact = try await fresh.getClosetItem(closetItemID: serverID).items.map { .init(row: $0) }
                }
                return .init(listedItems: listed, exactItems: exact,
                    histories: sync.histories.map { .init(row: $0) },
                    tombstones: sync.tombstones.map(\.clientComparisonID))
            }, hide: { id in
                let receipt = try await a.hideVNextComparisonHistories(clientComparisonIDs: [id])
                guard receipt.hidden else { throw ReleaseAuthFailure.blocked("retirement_hide_not_confirmed") }
                return receipt.clientComparisonIDs
            }, persist: { try Self.write($0, to: self.ledgerURL) })
        let clientID = UUID()
        ledger.comparisons.append(Comparison(clientID: clientID, referenceClientID: reference.clientItemID,
            targetID: seed.productID, variantID: seed.variantID))
        let index = ledger.comparisons.count - 1
        try saveLedger()
        let begin = try await a.beginComparison(.init(referenceItemID: reference.closetItemID,
            targetProductID: seed.productID, allowExtended: true, clientHistoryID: clientID,
            targetVariantID: seed.variantID, authorizationProductSizeID: seed.selectedSizeID,
            candidateProductSizeIDs: eligibility.authorizedCandidateProductSizeIDs,
            candidateAuthorityFingerprint: fingerprint, effectiveAuthorityFingerprint: effective,
            personalOverrideRevision: eligibility.personalOverrideRevision))
        ledger.comparisons[index].serverID = begin.runID
        try saveLedger()
        guard let snapshot = begin.vnext else { throw ReleaseAuthFailure.failed("live_begin_snapshot_missing") }
        try check(snapshot.snapshot.target.productID == seed.productID
            && snapshot.snapshot.target.variantID == seed.variantID, "begin_target_identity_mismatch")
        let analysis = try VNextComparisonEngineAdapter().analyze(snapshot)
        let receipt = try await a.completeVNextComparison(comparisonID: begin.runID, payload: analysis.completionPayload)
        try check(receipt.completed && receipt.comparisonID == begin.runID
            && receipt.recommendedProductSizeID == analysis.recommended.productSizeID, "complete_receipt_mismatch")
        ledger.comparisons[index].completed = true
        try saveLedger()
        let again = try await a.completeVNextComparison(comparisonID: begin.runID, payload: analysis.completionPayload)
        try check(again.completed && again.comparisonID == begin.runID, "completion_retry_identity_changed")
        let fresh = try await live("A")
        let histories = try await fresh.fetchVNextComparisonHistory()
        let matches = histories.filter { $0.clientComparisonID == clientID }
        try check(matches.count == 1, "completed_history_cardinality")
        let row = matches[0]
        try check(row.id == begin.runID && row.targetProductID == seed.productID
            && row.targetVariantID == seed.variantID && row.referenceClientItemID == reference.clientItemID
            && row.resultEvidence == analysis.completionPayload, "completed_history_readback_mismatch")
        let b = try await live("B")
        try check(try await b.fetchVNextComparisonHistory().isEmpty, "other_user_history_visible")
        return (row, analysis)
    }

    private func exercise(_ seed: ReleaseAuthManifest.Case) async throws {
        currentCase = seed.id + "/SEED"
        try check(["A", "B", "C", "D", "E", "F", "G"].contains(seed.expectedGroup)
            && seed.reference.productID != seed.secondReference.productID
            && seed.target.selectedSizeID != seed.target.alternateSizeID,
            "seed_requires_distinct_references_and_target_sizes")
        let firstRuntime = try await verifySeed(seed.reference, group: seed.expectedGroup)
        let secondRuntime = try await verifySeed(seed.secondReference, group: seed.expectedGroup)
        let targetRuntime = try await verifySeed(seed.target, group: seed.expectedGroup)
        currentCase = seed.id + "/A"
        let firstRequest = try linkedRequest(seed: seed.reference, runtime: firstRuntime,
            sizeID: seed.reference.selectedSizeID, clientID: UUID())
        var first = try await create(firstRequest)
        let firstIndex = ledger.items.count - 1
        let second = try await create(linkedRequest(seed: seed.secondReference, runtime: secondRuntime,
            sizeID: seed.secondReference.selectedSizeID, clientID: UUID()))
        let secondIndex = ledger.items.count - 1
        try linkedRead(first, seed: seed.reference, sizeID: seed.reference.selectedSizeID)
        try linkedRead(second, seed: seed.secondReference, sizeID: seed.secondReference.selectedSizeID)
        let a = try await live("A")
        let retry = try await a.upsertClosetItem(firstRequest)
        try check(retry.closetItemID == first.closetItemID, "linked_retry_changed_identity")
        let retryRows = try await a.listClosetItems()
        try check(retryRows.items.filter { $0.clientItemID == first.clientItemID }.count == 1, "linked_retry_duplicate")
        passed(currentCase, "Exact linked identity/source snapshot/counts and same-request retry through real SDK")
        try await isolation(first, request: firstRequest, caseID: seed.id + "/ISOLATION")
        currentCase = seed.id + "/D"
        let (initialHistory, initialAnalysis) = try await compare(seed: seed.target, reference: first, group: seed.expectedGroup)
        passed(currentCase, "Live eligibility/begin; production engine; complete retry; fresh history read-back")
        currentCase = seed.id + "/F"
        let replay = try VNextHistoryCacheHydrator().validatedCompletedAnalysis(initialHistory)
        try check(replay.completionPayload == initialAnalysis.completionPayload
            && replay.analyses.contains { $0.productSizeID == seed.target.alternateSizeID }, "approved_alternative_replay_mismatch")
        passed(currentCase, "Cold completed snapshot replay retains exact approved alternative; no completion for selection")
        currentCase = seed.id + "/B"
        let edit = try linkedRequest(seed: seed.reference, runtime: firstRuntime,
            sizeID: seed.reference.alternateSizeID, clientID: first.clientItemID, satisfaction: 4)
        _ = try await a.updateClosetItem(edit, closetItemID: first.closetItemID)
        first = try await read(item: ledger.items[firstIndex])
        try linkedRead(first, seed: seed.reference, sizeID: seed.reference.alternateSizeID)
        try check(first.satisfaction == 4, "linked_edit_metadata")
        let untouched = try await read(item: ledger.items[secondIndex])
        try check(untouched == second, "linked_edit_changed_unrelated_item")
        let afterEditHistory = try await a.fetchVNextComparisonHistory()
        try check(afterEditHistory.first(where: { $0.id == initialHistory.id }) == initialHistory,
                  "closet_edit_changed_completed_snapshot")
        let (editedComparison, _) = try await compare(seed: seed.target, reference: first, group: seed.expectedGroup)
        try check(editedComparison.referenceClientItemID == first.clientItemID
            && editedComparison.id != initialHistory.id, "edited_closet_comparison_identity")
        passed(currentCase, "Exact linked size edit/read-back; unaffected rows preserved; fresh comparison uses edited item")
        currentCase = seed.id + "/G"
        let (secondHistory, _) = try await compare(seed: seed.target, reference: second, group: seed.expectedGroup)
        try check(secondHistory.id != initialHistory.id && secondHistory.referenceClientItemID == second.clientItemID,
                  "other_closet_did_not_create_new_comparison")
        try check(try VNextHistoryCacheHydrator().validatedCompletedAnalysis(initialHistory).completionPayload
                  == initialAnalysis.completionPayload, "prior_snapshot_replay_changed")
        passed(currentCase, "Explicit second Closet obtains new live eligibility/begin/complete; retained first snapshot stable")
        currentCase = seed.id + "/H"
        guard seed.target.alternateSizeID != secondHistory.recommendedProductSizeID else {
            throw ReleaseAuthFailure.blocked("seed_H_alternative_must_differ_from_recommendation")
        }
        let saved = try await create(linkedRequest(seed: seed.target, runtime: targetRuntime,
            sizeID: seed.target.alternateSizeID, clientID: UUID()))
        try linkedRead(saved, seed: seed.target, sizeID: seed.target.alternateSizeID)
        let beforeHide = try await a.fetchVNextComparisonHistory()
        try check(beforeHide.first(where: { $0.id == secondHistory.id }) == secondHistory,
                  "result_registration_changed_comparison_snapshot")
        let (registeredComparison, _) = try await compare(seed: seed.reference, reference: saved, group: seed.expectedGroup)
        try check(registeredComparison.referenceClientItemID == saved.clientItemID,
                  "registered_candidate_identity_mismatch")
        passed(currentCase, "Non-recommended explicit size persisted; original result unchanged; new row completes fresh comparison")
        currentCase = seed.id + "/E"
        let hidden = try await a.hideVNextComparisonHistories(clientComparisonIDs: [secondHistory.clientComparisonID])
        try check(hidden.hidden && hidden.clientComparisonIDs.contains(secondHistory.clientComparisonID), "hide_receipt_mismatch")
        let fresh = try await live("A")
        let sync = try await fresh.fetchVNextComparisonHistorySync()
        try check(!sync.histories.contains { $0.clientComparisonID == secondHistory.clientComparisonID }
            && sync.tombstones.contains { $0.clientComparisonID == secondHistory.clientComparisonID }, "history_tombstone_not_persisted")
        try check(sync.histories.first(where: { $0.id == registeredComparison.id }) == registeredComparison,
                  "history_hide_changed_unrelated_history")
        try check(try await read(item: ledger.items[secondIndex]) == second, "history_hide_changed_closet")
        passed(currentCase, "Exact history hide and fresh-client tombstone; Closet unchanged")
        currentCase = seed.id + "/C"
        try await delete(ledger.items[firstIndex])
        try check(try await read(item: ledger.items[secondIndex]) == second, "closet_delete_changed_sentinel")
        passed(currentCase, "Real deletion transaction, exact fresh read and unrelated Closet preservation")
    }

    private func cleanup() async throws {
        ledger.cleanup = "in_progress"; try saveLedger()
        let a = try await live("A")
        var unresolvedComparison = false
        for index in ledger.comparisons.indices {
            let entry = ledger.comparisons[index]
            if entry.hidden { continue }
            // IDs were freshly generated and journaled before begin. Never hide
            // a discovered/latest/user-wide ID. Pending/ambiguous begin cannot
            // be proved removed by the completed-History API: leave BLOCKED.
            guard entry.completed, entry.serverID != nil else {
                unresolvedComparison = true
                continue
            }
            let receipt = try await a.hideVNextComparisonHistories(clientComparisonIDs: [entry.clientID])
            try check(receipt.hidden && receipt.clientComparisonIDs.contains(entry.clientID), "cleanup_hide_receipt")
            ledger.comparisons[index].hidden = true; try saveLedger()
        }
        for index in ledger.items.indices where !ledger.items[index].deleted {
            let item = ledger.items[index]
            let rows = try await a.listClosetItems()
            let matches = rows.items.filter { $0.clientItemID == item.clientID }
            try check(matches.count <= 1, "cleanup_duplicate_client_id")
            if let row = matches.first {
                try ownership(row, item)
                ledger.items[index].serverID = row.closetItemID; try saveLedger()
                try await delete(ledger.items[index])
            } else if item.serverID == nil {
                throw ReleaseAuthFailure.blocked("ambiguous_create_requires_exact_reconciliation")
            }
        }
        let fresh = try await live("A")
        let remaining = try await fresh.listClosetItems()
        let histories = try await fresh.fetchVNextComparisonHistory()
        try check(!remaining.items.contains { row in ledger.items.contains { $0.clientID == row.clientItemID } }
            && !histories.contains { row in ledger.comparisons.contains { $0.clientID == row.clientComparisonID } },
            "active_run_rows_remain")
        if unresolvedComparison {
            throw ReleaseAuthFailure.blocked("pending_comparison_requires_exact_reconciliation")
        }
        ledger.cleanup = "no_active_run_rows_soft_deleted_storage_retained"; try saveLedger()
    }
}
