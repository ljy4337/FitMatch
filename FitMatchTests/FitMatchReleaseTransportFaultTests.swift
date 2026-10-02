import Foundation
import Supabase
import SwiftData
import Testing
@testable import FitMatch

/// Intercepts URLSession only. The real Supabase SDK and FitMatch domain
/// client encode RPCs, process HTTP failures, and decode response bodies.
/// Synthetic auth is memory-only; every request is intercepted, including
/// unexpected URLs. No development/Production network or database is used.
@MainActor
struct FitMatchReleaseTransportFaultTests {
    /// User A / AGENTS persistence: an unacknowledged write cannot publish a
    /// Closet row. Retry must send the same immutable identity and payload.
    @Test(arguments: ReleaseTransportFault.allCases)
    func linkedSaveHTTPFailureKeepsLocalDataAndRetriesExactWireRequest(_ fault: ReleaseTransportFault) async throws {
        let fixture = try ReleaseTransportFixture(fault: fault)
        defer { fixture.close() }
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let control = UserFit(sourceType: .manual, brandName: "Control", gender: .men,
            productName: "Unrelated garment", category: .top, detailCategory: .shortSleeve,
            sizeName: "S", measurements: .init(shoulder: 48, chest: 61, totalLength: 70, sleeveLength: 60), fitMemo: "keep", satisfaction: 3)
        context.insert(control)
        try context.save()
        let submission = try fixture.linkedSubmission()
        let action = FitMatchComparedProductClosetSubmissionAction(remote: fixture.domain)
        let userID = UUID()
        var projected = 0
        var persisted = 0

        for _ in 0..<2 {
            let outcome = await action.submitServerFirst(submission, in: context,
                submissionUserID: userID, currentUserID: { userID },
                projectAuthoritativeReceipt: { _, _, _, _ in
                    projected += 1
                    throw URLError(.badServerResponse)
                }, persist: { _ in persisted += 1 })
            guard case .completed(.serverRejected(let message)) = outcome else {
                Issue.record("Injected HTTP failure must not report saved or remain in-flight")
                return
            }
            #expect(!message.isEmpty)
            #expect(projected == 0)
            #expect(persisted == 0)
            let freshRows = try ModelContext(container).fetch(FetchDescriptor<UserFit>())
            #expect(freshRows.map(\.id) == [control.id])
            #expect(freshRows.first?.chest == 61)
            #expect(freshRows.first?.fitMemo == "keep")
        }
        // 42501 proves a rejected transaction. Other injected responses do
        // not prove rollback; the current recovery contract locks the input.
        #expect(action.recovery == (fault == .forbidden403 ? .editable : .retrySameRequest))
        #expect(fixture.requests.map { $0.url?.path } == Array(
            repeating: "/rest/v1/rpc/fitmatch_vnext_upsert_closet_item", count: 2))
        let bodies = try fixture.requestBodies.map { try JSONSerialization.jsonObject(with: $0) as? NSDictionary }
        #expect(bodies.count == 2)
        let firstBody = try #require(bodies.first.flatMap { $0 })
        let lastBody = try #require(bodies.last.flatMap { $0 })
        #expect(firstBody == lastBody)
        let payload = try #require(firstBody["p_request"] as? [String: Any])
        for (key, identity) in [("client_item_id", submission.remoteRequest.clientItemID),
                                ("product_id", fixture.productID), ("product_variant_id", fixture.variantID),
                                ("product_size_id", fixture.sizeID)] {
            #expect((payload[key] as? String)?.lowercased() == identity.uuidString.lowercased())
        }
    }

    @Test(arguments: ReleaseTransportFault.allCases)
    func mutationRPCFaultsReachRealHTTPBoundaryAndNeverReturnSuccess(_ fault: ReleaseTransportFault) async throws {
        let fixture = try ReleaseTransportFixture(fault: fault)
        defer { fixture.close() }
        let item = UserFit(
            sourceType: .manual, brandName: "Transport fixture", gender: .men,
            productName: "Synthetic shirt", category: .top, detailCategory: .shortSleeve,
            sizeName: "M", measurements: .init(shoulder: 48, chest: 50, totalLength: 70, sleeveLength: 60),
            fitMemo: "", satisfaction: 3
        )
        item.categoryCode = "tops"
        item.detailCategoryCode = "short_sleeve"
        item.garmentTypeRawValue = "tshirt"
        item.sleeveTypeRawValue = "short_sleeve"
        item.markClassificationAuthority(.userExplicit)
        let request = FitMatchUpsertClosetItemRequest(
            clientItemID: item.id, item: FitMatchClosetSyncCoordinator().payload(for: item),
            productID: fixture.productID, productVariantID: fixture.variantID,
            productSizeID: fixture.sizeID, override: nil, sourceObservationID: UUID()
        )
        let completion = VNextComparisonCompletionPayload(
            recommendedProductSizeID: fixture.sizeID, score: 95, reliability: 1, coverage: 1,
            engineVersion: VNextComparisonEngineAdapter.engineVersion,
            candidateSizeRanking: [.init(productSizeID: fixture.sizeID, rank: 1, score: 95)],
            metricEvidence: [.init(productSizeID: fixture.sizeID, measurementCode: "chest_width",
                referenceValue: 50, targetValue: 51, difference: 1, absoluteDifference: 1, weight: 2)]
        )
        let begin = FitMatchBeginComparisonRequest(
            referenceItemID: fixture.closetID, targetProductID: fixture.productID,
            allowExtended: true, clientHistoryID: fixture.comparisonID,
            targetVariantID: fixture.variantID, authorizationProductSizeID: fixture.sizeID,
            candidateProductSizeIDs: [fixture.sizeID], candidateAuthorityFingerprint: "synthetic-candidate",
            effectiveAuthorityFingerprint: "synthetic-authority"
        )
        let operations: [(String, () async throws -> Void)] = [
            ("fitmatch_vnext_upsert_closet_item", { _ = try await fixture.domain.upsertClosetItem(request) }),
            ("fitmatch_vnext_update_closet_item", { _ = try await fixture.domain.updateClosetItem(request, closetItemID: fixture.closetID) }),
            ("fitmatch_vnext_begin_comparison", { _ = try await fixture.domain.beginComparison(begin) }),
            ("fitmatch_vnext_complete_comparison", { _ = try await fixture.domain.completeVNextComparison(comparisonID: fixture.comparisonID, payload: completion) }),
            ("fitmatch_vnext_hide_comparison_history", { _ = try await fixture.domain.hideVNextComparisonHistories(clientComparisonIDs: [fixture.comparisonID]) })
        ]
        for (rpc, operation) in operations {
            do {
                try await operation()
                Issue.record("\(rpc) returned success for injected \(fault.rawValue)")
            } catch {
                // The recorded HTTP request below ensures this was not an
                // unrelated local/auth preflight failure before transport.
            }
            let requests = fixture.requests.filter { $0.url?.path == "/rest/v1/rpc/\(rpc)" }
            #expect(requests.count == 1, "Expected exact real RPC request: \(rpc)")
            #expect(requests.first?.httpMethod == "POST")
        }
        #expect(fixture.requests.count == operations.count)
    }

    @Test(arguments: ReleaseTransportFault.allCases)
    func closetDeleteTransportFailurePreservesIntentAndPreventsLocalCommit(_ fault: ReleaseTransportFault) async throws {
        let fixture = try ReleaseTransportFixture(fault: fault)
        defer { fixture.close() }
        var intentRecorded = false
        var committed = false
        do {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { true }, prepare: {}, resolve: { fixture.closetID },
                recordIntent: { intentRecorded = true },
                delete: { id in
                    let receipt = try await fixture.domain.deleteClosetItem(closetItemID: id)
                    return (receipt.closetItemID, receipt.deletedAt)
                }, commit: { committed = true }
            )
            Issue.record("Deletion succeeded after injected \(fault.rawValue)")
        } catch {}
        #expect(intentRecorded)
        #expect(!committed)
        #expect(fixture.requests.map { $0.url?.path } == ["/rest/v1/rpc/fitmatch_vnext_delete_closet_item"])
        #expect(fixture.requests.first?.httpMethod == "POST")
    }

    @Test func successfulDeleteReceiptReachesRealDecoderAndCommitsExactlyOnce() async throws {
        let fixture = try ReleaseTransportFixture(fault: nil)
        defer { fixture.close() }
        var commitCount = 0
        try await FitMatchClosetDeletionTransaction.run(
            isCurrent: { true }, prepare: {}, resolve: { fixture.closetID }, recordIntent: {},
            delete: { id in
                let receipt = try await fixture.domain.deleteClosetItem(closetItemID: id)
                return (receipt.closetItemID, receipt.deletedAt)
            }, commit: { commitCount += 1 }
        )
        #expect(commitCount == 1)
        #expect(fixture.requests.count == 1)
    }
}

enum ReleaseTransportFault: String, CaseIterable, Sendable {
    case offline, forbidden403, rateLimited429, server500, timeout, malformed, cancelledTransport
}

private struct ReleaseTransportFixture {
    let productID = UUID()
    let variantID = UUID()
    let sizeID = UUID()
    let comparisonID = UUID()
    let closetID: UUID
    let domain: FitMatchSupabaseDomainClient
    private let host: String
    private let session: URLSession

    init(fault: ReleaseTransportFault?) throws {
        closetID = UUID()
        host = "release-\(UUID().uuidString.lowercased()).invalid"
        ReleaseFaultURLProtocol.registry.install(host: host, fault: fault, closetID: closetID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseFaultURLProtocol.self]
        session = URLSession(configuration: configuration)
        let date = Date()
        let storedSession = Session(
            accessToken: "synthetic-offline-token", tokenType: "bearer", expiresIn: 3600,
            expiresAt: date.addingTimeInterval(3600).timeIntervalSince1970,
            refreshToken: "synthetic-offline-refresh", user: .init(
                id: UUID(), appMetadata: [:], userMetadata: [:], aud: "authenticated",
                createdAt: date, role: "authenticated", updatedAt: date
            )
        )
        let storage = ReleaseFaultMemoryStorage(
            key: "release-test-session", value: try JSONEncoder().encode(storedSession)
        )
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "synthetic-offline-key",
            options: .init(
                auth: .init(storage: storage, storageKey: "release-test-session", autoRefreshToken: false),
                global: .init(session: session)
            )
        )
        domain = FitMatchSupabaseDomainClient(authenticatedClient: client)
    }

    var requests: [URLRequest] { ReleaseFaultURLProtocol.registry.requests(host: host) }
    var requestBodies: [Data] { ReleaseFaultURLProtocol.registry.bodies(host: host) }

    @MainActor
    func linkedSubmission() throws -> FitMatchComparedProductClosetRegistration.ServerFirstSubmission {
        let product = Product(id: UUID(), name: "Synthetic linked shirt", category: .top,
            productCode: "FAULT-FIXTURE", sourceURLString: "https://www.musinsa.com/products/1",
            metadata: ProductMetadata(genderCodes: ["MEN"]), sourceType: .marketplace,
            sourceName: "무신사", source: .catalog)
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(.serverConfirmed)
        let size = ProductSize(id: UUID(), name: "M", measurements: .init(shoulder: 48, chest: 50, totalLength: 70, sleeveLength: 60), product: product)
        product.sizes = [size]
        let request = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: product, selectedSize: size,
            serverIdentity: .init(productID: productID, productVariantID: variantID, productSizeID: sizeID),
            activeClosetItems: [], brandName: "Fixture", gender: .men, genderCode: "male",
            productName: product.name, category: .top, categoryCode: "tops",
            detailCategory: .shortSleeve, detailCategoryCode: "short_sleeve",
            sourceObservationID: UUID(), isRepresentative: false,
            didExplicitlyChangeClassification: false, didExplicitlySelectClosetClassification: false)
        return try FitMatchComparedProductClosetRegistration.prepareServerFirstSubmission(request)
    }

    func close() {
        session.invalidateAndCancel()
        ReleaseFaultURLProtocol.registry.remove(host: host)
    }
}

private final class ReleaseFaultMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    init(key: String, value: Data) { values = [key: value] }
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

private final class ReleaseFaultRegistry: @unchecked Sendable {
    private struct Entry {
        let fault: ReleaseTransportFault?
        let closetID: UUID
        var requests: [URLRequest] = []
        var bodies: [Data] = []
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    func install(host: String, fault: ReleaseTransportFault?, closetID: UUID) {
        lock.lock(); defer { lock.unlock() }
        entries[host] = Entry(fault: fault, closetID: closetID)
    }
    func remove(host: String) {
        lock.lock(); defer { lock.unlock() }; entries[host] = nil
    }
    func requests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return entries[host]?.requests ?? []
    }
    func bodies(host: String) -> [Data] {
        lock.lock(); defer { lock.unlock() }; return entries[host]?.bodies ?? []
    }
    func receive(_ request: URLRequest) -> (ReleaseTransportFault?, UUID)? {
        lock.lock(); defer { lock.unlock() }
        guard let host = request.url?.host, var entry = entries[host] else { return nil }
        entry.requests.append(request)
        if let body = request.httpBody {
            entry.bodies.append(body)
        } else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            entry.bodies.append(body)
        }
        entries[host] = entry
        return (entry.fault, entry.closetID)
    }
}

private final class ReleaseFaultURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = ReleaseFaultRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let (fault, closetID) = Self.registry.receive(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch fault {
        case .offline: fail(.notConnectedToInternet)
        case .timeout: fail(.timedOut)
        case .cancelledTransport: fail(.cancelled)
        case .forbidden403: respond(url, status: 403, body: #"{"code":"42501","message":"forbidden"}"#)
        case .rateLimited429: respond(url, status: 429, body: #"{"code":"rate_limit","message":"too many requests"}"#)
        case .server500: respond(url, status: 500, body: #"{"code":"XX000","message":"injected server error"}"#)
        case .malformed: respond(url, status: 200, body: "{malformed-json")
        case nil:
            respond(url, status: 200, body: "{\"closet_item_id\":\"\(closetID)\",\"deleted_at\":\"2026-10-02T00:00:00Z\"}")
        }
    }
    private func fail(_ code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }
    private func respond(_ url: URL, status: Int, body: String) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
