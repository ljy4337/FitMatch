import Darwin
import Foundation
import Security
import Supabase
import SwiftData

private let credentialService = "com.ljy4337.fitmatch.release-e2e"
private let overshirtURL = "https://www.zara.com/kr/ko/item-p01957601.html?v1=565606719"

private enum RunnerMode: String, Codable {
    case parserOnly = "parser-only"
    case smoke
    case full
}

private struct Catalog: Decodable {
    let items: [CatalogItem]
}

private struct CatalogItem: Codable, Hashable {
    let source: String
    let category: String
    let name: String
    let id: String
    let url: String
    let index: Int
}

private struct RunnerOptions {
    let mode: RunnerMode
    let inputURL: URL
    let outputDirectory: URL

    static func parse() throws -> RunnerOptions {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var mode = RunnerMode.smoke
        var input = "Docs/QA/ClothingURLs-20260916/products.json"
        var output: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--mode":
                index += 1
                guard index < arguments.count,
                      let parsed = RunnerMode(rawValue: arguments[index]) else {
                    throw RunnerError.invalidArguments("--mode는 parser-only, smoke, full 중 하나여야 합니다.")
                }
                mode = parsed
            case "--input":
                index += 1
                guard index < arguments.count else {
                    throw RunnerError.invalidArguments("--input 뒤에 파일 경로가 필요합니다.")
                }
                input = arguments[index]
            case "--output-dir":
                index += 1
                guard index < arguments.count else {
                    throw RunnerError.invalidArguments("--output-dir 뒤에 디렉터리 경로가 필요합니다.")
                }
                output = arguments[index]
            default:
                throw RunnerError.invalidArguments("알 수 없는 인자: \(arguments[index])")
            }
            index += 1
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let inputURL = URL(fileURLWithPath: input, relativeTo: cwd).standardizedFileURL
        let runStamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let outputDirectory = output.map {
            URL(fileURLWithPath: $0, relativeTo: cwd).standardizedFileURL
        } ?? URL(fileURLWithPath: "/tmp/FitMatchReleaseE2E/\(runStamp)")
        return RunnerOptions(mode: mode, inputURL: inputURL, outputDirectory: outputDirectory)
    }
}

private enum ResultState: String, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case blocked = "BLOCKED"
}

private struct CaseReport: Codable {
    let retailer: String
    let phase: String
    let referenceURL: String?
    let targetURL: String
    var state: ResultState
    var reason: String
    var evidence: [String: String]
}

private struct RunReport: Codable {
    let schemaVersion = 1
    let runID: UUID
    let startedAt: String
    let mode: RunnerMode
    let supabaseProject = "hnkplvyegonlhumlejst"
    var authenticatedUserID: UUID?
    var finishedAt: String?
    var cases: [CaseReport]
    var createdClosetItems: [String: String]
    var createdComparisonHistories: [String: String]
}

private enum RunnerError: LocalizedError {
    case invalidArguments(String)
    case missingCredentials
    case invalidCredentials
    case invalidConfiguration
    case invalidCatalog
    case registrationBlocked(String)
    case registrationFailed(String)
    case comparisonBlocked(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message),
             .registrationBlocked(let message),
             .registrationFailed(let message),
             .comparisonBlocked(let message):
            return message
        case .missingCredentials:
            return "전용 테스트 계정이 macOS 키체인에 없습니다."
        case .invalidCredentials:
            return "키체인에 저장된 전용 테스트 계정 정보를 읽을 수 없습니다."
        case .invalidConfiguration:
            return "FitMatch Supabase 설정을 읽을 수 없습니다."
        case .invalidCatalog:
            return "검증 URL 목록을 읽을 수 없습니다."
        }
    }
}

private struct KeychainCredential {
    let email: String
    let password: String

    static func load() throws -> KeychainCredential {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: credentialService,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnAttributes: true,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw RunnerError.missingCredentials }
        guard status == errSecSuccess,
              let dictionary = result as? [CFString: Any],
              let email = dictionary[kSecAttrAccount] as? String,
              let data = dictionary[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8),
              !email.isEmpty, !password.isEmpty else {
            throw RunnerError.invalidCredentials
        }
        return KeychainCredential(email: email, password: password)
    }
}

private struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static func load() throws -> SupabaseConfiguration {
        let plistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("FitMatch/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard let values = try PropertyListSerialization.propertyList(
            from: data, format: nil
        ) as? [String: Any],
              let urlText = values["FitMatchSupabaseURL"] as? String,
              let url = URL(string: urlText),
              let key = values["FitMatchSupabasePublishableKey"] as? String,
              !key.isEmpty else {
            throw RunnerError.invalidConfiguration
        }
        return SupabaseConfiguration(url: url, publishableKey: key)
    }
}

@MainActor
private final class ReleaseRunner {
    private let options: RunnerOptions
    private let catalog: Catalog
    private let runID = UUID()
    private var report: RunReport
    private var client: SupabaseClient?
    private var remote: FitMatchSupabaseDomainClient?
    private var authorityCoordinator: FitMatchServerAuthorityCoordinator?
    private var syncCoordinator: FitMatchClosetSyncCoordinator?
    private var modelContainer: ModelContainer?

    init(options: RunnerOptions) throws {
        self.options = options
        let data = try Data(contentsOf: options.inputURL)
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              Set(catalog.items.map(\.source)) == Set(["musinsa", "uniqlo", "zara"]) else {
            throw RunnerError.invalidCatalog
        }
        self.catalog = catalog
        report = RunReport(
            runID: runID,
            startedAt: ISO8601DateFormatter().string(from: Date()),
            mode: options.mode,
            authenticatedUserID: nil,
            finishedAt: nil,
            cases: [],
            createdClosetItems: [:],
            createdComparisonHistories: [:]
        )
        try FileManager.default.createDirectory(
            at: options.outputDirectory,
            withIntermediateDirectories: true
        )
        try persistReport()
    }

    func run() async -> Int32 {
        if options.mode == .parserOnly {
            await runParserOnly()
            finish()
            return report.cases.contains(where: { $0.state == .fail }) ? 1 : 0
        }

        do {
            try await configureAuthenticatedServices()
        } catch {
            append(CaseReport(
                retailer: "all",
                phase: "authentication",
                referenceURL: nil,
                targetURL: "",
                state: .blocked,
                reason: error.localizedDescription,
                evidence: ["keychain_service": credentialService]
            ))
            finish()
            return 2
        }

        await runOvershirtRegression()
        let selected = selectedItems()
        for source in ["musinsa", "uniqlo", "zara"] {
            let items = selected.filter { $0.source == source }
            for pairStart in stride(from: 0, to: items.count - 1, by: 2) {
                await runJourney(reference: items[pairStart], target: items[pairStart + 1])
                if options.mode == .smoke { break }
            }
        }
        finish()
        return report.cases.contains(where: { $0.state == .fail }) ? 1 : 0
    }

    private func configureAuthenticatedServices() async throws {
        let credentials = try KeychainCredential.load()
        let configuration = try SupabaseConfiguration.load()
        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
        try await client.auth.signIn(email: credentials.email, password: credentials.password)
        let session = try await client.auth.session
        let remote = FitMatchSupabaseDomainClient(authenticatedClient: client)
        let sync = FitMatchClosetSyncCoordinator(
            remote: remote,
            defaults: UserDefaults(suiteName: "FitMatchReleaseE2E.\(runID.uuidString)")!
        )
        sync.prepareForAuthenticatedUser(session.user.id)
        let schema = Schema(FitMatchSchemaV1.models)
        let configurationModel = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        self.client = client
        self.remote = remote
        authorityCoordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        syncCoordinator = sync
        modelContainer = try ModelContainer(
            for: schema,
            configurations: [configurationModel]
        )
        report.authenticatedUserID = session.user.id
        try persistReport()
        print("[RUNNER] authenticated user=\(session.user.id.uuidString)")
    }

    private func selectedItems() -> [CatalogItem] {
        let limit = options.mode == .smoke ? 2 : 10
        return ["musinsa", "uniqlo", "zara"].flatMap { source in
            catalog.items.filter { $0.source == source }.prefix(limit)
        }
    }

    private func runParserOnly() async {
        var items = selectedItems()
        items.append(CatalogItem(
            source: "zara",
            category: "오버셔츠 회귀",
            name: "ZARA 오버셔츠 회귀",
            id: "01957601:565606719",
            url: overshirtURL,
            index: Int.max
        ))
        let parser = ProductURLParserService()
        for item in items {
            do {
                let parsed = try await parser.parse(urlString: item.url)
                append(CaseReport(
                    retailer: item.source,
                    phase: "fresh-retailer-api",
                    referenceURL: nil,
                    targetURL: item.url,
                    state: parsed.sizes.isEmpty ? .fail : .pass,
                    reason: parsed.sizes.isEmpty ? "실제 API 응답에 사이즈가 없습니다." : "실제 API 파싱 완료",
                    evidence: parserEvidence(parsed)
                ))
            } catch let partial as ProductURLParserPartialError {
                var evidence = parserEvidence(partial.productInfo)
                evidence["partial_error"] = partial.localizedDescription
                append(CaseReport(
                    retailer: item.source,
                    phase: "fresh-retailer-api",
                    referenceURL: nil,
                    targetURL: item.url,
                    state: .blocked,
                    reason: "쇼핑몰 응답은 받았지만 일부 필수 데이터가 없습니다.",
                    evidence: evidence
                ))
            } catch {
                append(CaseReport(
                    retailer: item.source,
                    phase: "fresh-retailer-api",
                    referenceURL: nil,
                    targetURL: item.url,
                    state: .fail,
                    reason: error.localizedDescription,
                    evidence: [:]
                ))
            }
        }
    }

    private func runOvershirtRegression() async {
        guard let authorityCoordinator else { return }
        let viewModel = ShoppingProductViewModel(
            initialURL: overshirtURL,
            serverAuthorityCoordinator: authorityCoordinator
        )
        _ = await viewModel.loadProductInfoFromURL()
        let state: ResultState
        let reason: String
        if !viewModel.hasLoadedProductInfo {
            state = .fail
            reason = viewModel.errorMessage ?? "자라 오버셔츠 실제 API 파싱 실패"
        } else if case .unavailable(let message) = viewModel.serverAuthorityState {
            state = .fail
            reason = message
        } else {
            state = .pass
            reason = viewModel.requiresComparisonGroupSelection
                ? "실제 API/서버 수집 완료, 미매핑 그룹 선택 경로 진입"
                : "실제 API/서버 수집 완료"
        }
        append(CaseReport(
            retailer: "zara",
            phase: "overshirt-regression",
            referenceURL: nil,
            targetURL: overshirtURL,
            state: state,
            reason: reason,
            evidence: viewModelEvidence(viewModel)
        ))
    }

    private func runJourney(reference: CatalogItem, target: CatalogItem) async {
        var caseReport = CaseReport(
            retailer: reference.source,
            phase: "closet-save-to-comparison-history",
            referenceURL: reference.url,
            targetURL: target.url,
            state: .blocked,
            reason: "시작 전",
            evidence: [:]
        )
        do {
            let registered = try await registerReference(reference)
            caseReport.evidence.merge(registered.evidence) { _, new in new }
            let comparison = try await compare(
                target: target,
                reference: registered.item
            )
            caseReport.evidence.merge(comparison) { _, new in new }
            caseReport.state = .pass
            caseReport.reason = "실제 API → 서버 저장 영수증 → 직접 후보 선택 → 비교 완료 → 기록 조회 확인"
        } catch let error as RunnerError {
            switch error {
            case .registrationBlocked, .comparisonBlocked:
                caseReport.state = .blocked
            default:
                caseReport.state = .fail
            }
            caseReport.reason = error.localizedDescription
        } catch {
            caseReport.state = .fail
            caseReport.reason = error.localizedDescription
        }
        append(caseReport)
    }

    private struct RegisteredReference {
        let item: UserFit
        let evidence: [String: String]
    }

    private func registerReference(_ catalogItem: CatalogItem) async throws -> RegisteredReference {
        guard let authorityCoordinator, let remote, let syncCoordinator,
              let modelContext = modelContainer?.mainContext,
              let userID = report.authenticatedUserID else {
            throw RunnerError.registrationFailed("인증된 실행기 상태가 없습니다.")
        }
        let viewModel = ShoppingProductViewModel(
            initialURL: catalogItem.url,
            serverAuthorityCoordinator: authorityCoordinator
        )
        _ = await viewModel.loadProductInfoFromURL()
        guard viewModel.hasLoadedProductInfo else {
            throw RunnerError.registrationFailed(
                "상품 API 파싱 실패: \(viewModel.errorMessage ?? "원인 없음")"
            )
        }
        let context = viewModel.closetRegistrationServerContext
        switch context.classificationState {
        case .reviewRequired:
            throw RunnerError.registrationBlocked("서버 미매핑 상품이라 사용자 분류 입력이 필요합니다.")
        case .notApplicable:
            throw RunnerError.registrationBlocked("서버가 등록 대상이 아닌 상품으로 판정했습니다.")
        case .preparing, .unavailable:
            throw RunnerError.registrationFailed(
                viewModel.errorMessage ?? context.registrationBlockMessage ?? "서버 등록 문맥을 확인하지 못했습니다."
            )
        case .confirmed:
            break
        }
        guard let product = viewModel.makeProductForClosetRegistration(
            brand: viewModel.makeBrand()
        ),
              let categoryCode = context.categoryCode,
              let detailCode = context.detailCode else {
            throw RunnerError.registrationFailed("서버가 등록용 상품 분류를 완성하지 못했습니다.")
        }
        let selectable = product.sizes.compactMap { size -> (ProductSize, FitMatchClosetRegistrationServerIdentity)? in
            guard context.isRegisterable(displaySizeID: size.id),
                  let identity = context.identity(for: size.id) else { return nil }
            return (size, identity)
        }
        guard let (selectedSize, identity) = selectable.first else {
            throw RunnerError.registrationBlocked("실측과 정확한 서버 UUID가 함께 있는 등록 가능 사이즈가 없습니다.")
        }
        let before = try await remote.listClosetItems()
        guard before.state == "ready" else {
            throw RunnerError.registrationFailed("저장 전 옷장 영수증 상태가 ready가 아닙니다.")
        }
        guard !before.items.contains(where: {
            $0.productID == identity.productID
                && $0.variantID == identity.productVariantID
                && $0.productSizeID == identity.productSizeID
        }) else {
            throw RunnerError.registrationBlocked("전용 계정 옷장에 같은 상품·옵션·사이즈가 이미 있어 기존 데이터를 보존했습니다.")
        }
        let gender = UserGender.productTarget(from: product.genderCodes)
        let request = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: product,
            selectedSize: selectedSize,
            serverIdentity: identity,
            hasMeasurementEligibilityProof: true,
            activeClosetItems: [],
            brandName: product.brand?.name ?? viewModel.brand,
            gender: gender,
            genderCode: gender.taxonomyCode,
            productName: product.name,
            category: ClothingCategory.fromTaxonomyCode(categoryCode),
            categoryCode: categoryCode,
            detailCategory: ClosetDetailCategory.fromTaxonomyCode(detailCode),
            detailCategoryCode: detailCode,
            comparisonGroupCode: nil,
            isRepresentative: false,
            didExplicitlyChangeClassification: false,
            didExplicitlyChangeAudience: false,
            didExplicitlySelectClosetClassification: false
        )
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(request)
        let action = FitMatchComparedProductClosetSubmissionAction(remote: remote)
        let outcome = await action.submitServerFirst(
            submission,
            in: modelContext,
            submissionUserID: userID,
            currentUserID: { userID },
            projectAuthoritativeReceipt: { record, request, closetItemID, context in
                try syncCoordinator.projectAuthoritativeRegistration(
                    record,
                    expected: request,
                    acceptedClosetItemID: closetItemID,
                    modelContext: context
                )
            }
        )
        let item: UserFit
        switch outcome {
        case .completed(.saved(let saved)), .completed(.savedWithoutReference(let saved, _)):
            item = saved
        case .completed(let failure):
            throw RunnerError.registrationFailed(
                failure.userVisibleMessage ?? "서버 저장 결과가 성공이 아닙니다."
            )
        case .alreadyInFlight:
            throw RunnerError.registrationFailed("등록 요청이 중복 실행됐습니다.")
        }
        let after = try await remote.listClosetItems()
        let receipts = after.items.filter { $0.clientItemID == item.id }
        guard after.state == "ready", receipts.count == 1 else {
            throw RunnerError.registrationFailed("저장 후 동일 client_item_id 영수증을 하나만 확인하지 못했습니다.")
        }
        let receipt = receipts[0]
        guard receipt.productID == identity.productID,
              receipt.variantID == identity.productVariantID,
              receipt.productSizeID == identity.productSizeID,
              !receipt.measurementRecords.isEmpty else {
            throw RunnerError.registrationFailed("저장 영수증의 상품·옵션·사이즈 UUID 또는 실측이 요청과 다릅니다.")
        }
        report.createdClosetItems[item.id.uuidString] = receipt.closetItemID.uuidString
        try persistReport()
        return RegisteredReference(item: item, evidence: [
            "reference_client_item_id": item.id.uuidString,
            "reference_closet_item_id": receipt.closetItemID.uuidString,
            "reference_product_id": identity.productID.uuidString,
            "reference_variant_id": identity.productVariantID.uuidString,
            "reference_product_size_id": identity.productSizeID.uuidString,
            "reference_size": receipt.sizeName ?? selectedSize.name,
            "reference_measurement_records": String(receipt.measurementRecords.count),
            "reference_group": receipt.comparisonGroupCode ?? "nil",
            "explicit_group_sent": "false"
        ])
    }

    private func compare(target: CatalogItem, reference: UserFit) async throws -> [String: String] {
        guard let authorityCoordinator, let remote else {
            throw RunnerError.comparisonBlocked("인증된 비교 서비스가 없습니다.")
        }
        let viewModel = ShoppingProductViewModel(
            initialURL: target.url,
            serverAuthorityCoordinator: authorityCoordinator
        )
        _ = await viewModel.loadProductInfoFromURL()
        guard viewModel.hasLoadedProductInfo else {
            throw RunnerError.comparisonBlocked(
                "비교 상품 API 파싱 실패: \(viewModel.errorMessage ?? "원인 없음")"
            )
        }
        if viewModel.requiresComparisonGroupSelection {
            throw RunnerError.comparisonBlocked("비교 상품의 서버 그룹이 미매핑이라 사용자 A~G 선택이 필요합니다.")
        }
        guard viewModel.hasServerComparisonReadyAuthority else {
            throw RunnerError.comparisonBlocked(
                viewModel.serverComparisonReadiness?.userMessage
                    ?? viewModel.errorMessage
                    ?? "서버가 비교 준비 완료 상태를 승인하지 않았습니다."
            )
        }
        let requestID = UUID()
        viewModel.beginComparisonRequest(requestID)
        defer { viewModel.invalidateComparisonRequest(requestID) }
        guard let plan = await viewModel.loadServerReferenceSelectionPlan(
            localClientItemIDs: [reference.id],
            comparisonRequestID: requestID
        ) else {
            throw RunnerError.comparisonBlocked(
                viewModel.errorMessage ?? "서버 비교 후보 계획을 받지 못했습니다."
            )
        }
        guard let candidate = plan.candidates.first(where: {
            $0.clientItemID == reference.id && $0.isSelectable
        }) else {
            throw RunnerError.comparisonBlocked("방금 등록한 옷이 서버 승인 후보에 포함되지 않았습니다.")
        }
        guard let history = await viewModel.calculateTemporaryRecommendation(
            selectedReferenceItem: reference,
            brand: viewModel.makeBrand(),
            comparisonRequestID: requestID
        ) else {
            throw RunnerError.comparisonBlocked(
                viewModel.errorMessage ?? "비교 엔진 또는 완료 저장이 실패했습니다."
            )
        }
        let remoteHistory = try await remote.fetchVNextComparisonHistory()
        let matches = remoteHistory.filter { $0.clientComparisonID == history.id }
        guard matches.count == 1,
              matches[0].referenceClientItemID == reference.id,
              matches[0].targetProductID == plan.target.productID else {
            throw RunnerError.comparisonBlocked("비교 완료 후 동일 client comparison 영수증을 확인하지 못했습니다.")
        }
        let receipt = matches[0]
        report.createdComparisonHistories[history.id.uuidString] = receipt.id.uuidString
        try persistReport()
        return [
            "candidate_decision": String(describing: candidate.decision),
            "target_product_id": receipt.targetProductID.uuidString,
            "target_variant_id": receipt.targetVariantID.uuidString,
            "target_group": plan.targetComparisonGroupCode ?? "nil",
            "client_comparison_id": history.id.uuidString,
            "server_history_id": receipt.id.uuidString,
            "result_status": receipt.resultStatus,
            "recommended_product_size_id": receipt.recommendedProductSizeID?.uuidString ?? "nil",
            "recommended_size": receipt.recommendedSizeLabel ?? "nil",
            "engine_version": receipt.engineVersion
        ]
    }

    private func parserEvidence(_ product: ParsedProductInfo) -> [String: String] {
        [
            "product_id": product.productID ?? "nil",
            "product_name": product.productName,
            "source": product.sourceName,
            "category_path": product.metadata.sourceCategoryPath ?? "nil",
            "size_count": String(product.sizes.count),
            "measured_size_count": String(product.sizes.filter {
                !$0.measurementRecords.isEmpty
            }.count),
            "canonical_url": product.canonicalURLString ?? "nil"
        ]
    }

    private func viewModelEvidence(_ viewModel: ShoppingProductViewModel) -> [String: String] {
        let context = viewModel.closetRegistrationServerContext
        return [
            "product_code": viewModel.productCode ?? "nil",
            "product_name": viewModel.productName,
            "source": viewModel.sourceName,
            "category_path": viewModel.productMetadata.sourceCategoryPath ?? "nil",
            "display_size_count": String(viewModel.sizeOptions.count),
            "server_identity_count": String(context.identitiesByDisplaySizeID.count),
            "registerable_size_count": String(context.registerableDisplaySizeIDs.count),
            "server_group": context.comparisonGroupCode ?? "nil",
            "requires_group_selection": String(viewModel.requiresComparisonGroupSelection),
            "error_message": viewModel.errorMessage ?? "nil"
        ]
    }

    private func append(_ value: CaseReport) {
        report.cases.append(value)
        try? persistReport()
        print("[RUNNER] \(value.state.rawValue) retailer=\(value.retailer) phase=\(value.phase) reason=\(value.reason)")
    }

    private func finish() {
        report.finishedAt = ISO8601DateFormatter().string(from: Date())
        try? persistReport()
        let counts = Dictionary(grouping: report.cases, by: \.state).mapValues(\.count)
        print("[RUNNER] finished output=\(options.outputDirectory.path) PASS=\(counts[.pass, default: 0]) FAIL=\(counts[.fail, default: 0]) BLOCKED=\(counts[.blocked, default: 0])")
    }

    private func persistReport() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(
            to: options.outputDirectory.appendingPathComponent("summary.json"),
            options: .atomic
        )
    }
}

@main
@MainActor
private struct FitMatchReleaseE2ERunner {
    static func main() async {
        do {
            let options = try RunnerOptions.parse()
            let runner = try ReleaseRunner(options: options)
            exit(await runner.run())
        } catch {
            fputs("[RUNNER] FAIL \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
