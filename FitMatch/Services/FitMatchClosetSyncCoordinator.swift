import Combine
import Foundation
import SwiftData
import SwiftUI

protocol FitMatchClosetRemoteServicing: Sendable {
    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse
    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse
    func listClosetItems() async throws -> FitMatchClosetItemsResponse
    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse
}

extension FitMatchSupabaseDomainClient: FitMatchClosetRemoteServicing {}

enum FitMatchClosetSyncState: Equatable {
    case idle
    case syncing
    case synced
    case pendingRetry
}

@MainActor
final class FitMatchClosetSyncCoordinator: ObservableObject {
    @Published private(set) var state: FitMatchClosetSyncState = .idle
    @Published private(set) var lastErrorMessage: String?

    private let remote: any FitMatchClosetRemoteServicing
    private let defaults: UserDefaults
    private var activeUserID: UUID?
    private var isSynchronizing = false
    private var needsAnotherPass = false
    private var remoteItemsByClientID: [UUID: FitMatchClosetItemRecord] = [:]

    private static let cacheOwnerKey = "FitMatch.closetCacheOwnerUserID"
    private static let pendingDeletePrefix = "FitMatch.closetPendingDelete."

    init(
        remote: (any FitMatchClosetRemoteServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.remote = remote ?? FitMatchSupabaseDomainClient.shared
        self.defaults = defaults
    }

    func synchronize(userID: UUID, modelContext: ModelContext) async {
        activeUserID = userID
        if isSynchronizing {
            needsAnotherPass = true
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        repeat {
            needsAnotherPass = false
            await synchronizeOnce(userID: userID, modelContext: modelContext)
        } while needsAnotherPass
    }

    func enqueueDeletion(clientItemID: UUID) {
        guard let activeUserID else { return }
        var pending = pendingDeleteIDs(for: activeUserID)
        pending.insert(clientItemID)
        storePendingDeleteIDs(pending, for: activeUserID)
    }

    func cancelDeletion(clientItemID: UUID) {
        guard let activeUserID else { return }
        var pending = pendingDeleteIDs(for: activeUserID)
        pending.remove(clientItemID)
        storePendingDeleteIDs(pending, for: activeUserID)
    }

    func purgeLocalAccountData(modelContext: ModelContext) throws {
        let histories = try modelContext.fetch(FetchDescriptor<RecommendationHistory>())
        histories.forEach(modelContext.delete)
        let items = try modelContext.fetch(FetchDescriptor<UserFit>())
        items.forEach(modelContext.delete)
        try modelContext.save()

        let storedOwner = defaults.string(forKey: Self.cacheOwnerKey).flatMap(UUID.init(uuidString:))
        Set([activeUserID, storedOwner].compactMap { $0 }).forEach { userID in
            defaults.removeObject(forKey: Self.pendingDeletePrefix + userID.uuidString)
        }
        defaults.removeObject(forKey: Self.cacheOwnerKey)
        activeUserID = nil
        remoteItemsByClientID.removeAll()
        needsAnotherPass = false
        state = .idle
        lastErrorMessage = nil
    }

    private func synchronizeOnce(userID: UUID, modelContext: ModelContext) async {
        state = .syncing
        lastErrorMessage = nil

        do {
            try prepareLocalCache(for: userID, modelContext: modelContext)
            var remoteResponse = try await remote.listClosetItems()
            guard remoteResponse.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }

            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: remoteResponse.items.map { ($0.clientItemID, $0) }
            )
            try await flushPendingDeletes(userID: userID)
            remoteResponse = try await remote.listClosetItems()
            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: remoteResponse.items.map { ($0.clientItemID, $0) }
            )

            let localItems = try modelContext.fetch(FetchDescriptor<UserFit>())
            var failedUpsert = false
            for localItem in localItems {
                if let remoteItem = remoteItemsByClientID[localItem.id],
                   remoteDate(remoteItem) > localItem.updatedAt.addingTimeInterval(1) {
                    try apply(remoteItem, to: localItem, modelContext: modelContext)
                    continue
                }

                do {
                    let request = try await makeUpsertRequest(for: localItem)
                    _ = try await remote.upsertClosetItem(request)
                } catch {
                    failedUpsert = true
                    #if DEBUG
                    print("[FitMatchClosetSync] upsert failed item=\(localItem.id): \(error.localizedDescription)")
                    #endif
                }
            }

            let authoritative = try await remote.listClosetItems()
            guard authoritative.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }
            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: authoritative.items.map { ($0.clientItemID, $0) }
            )

            let currentLocalItems = try modelContext.fetch(FetchDescriptor<UserFit>())
            let currentByID = Dictionary(uniqueKeysWithValues: currentLocalItems.map { ($0.id, $0) })
            for remoteItem in authoritative.items {
                if let localItem = currentByID[remoteItem.clientItemID] {
                    try apply(remoteItem, to: localItem, modelContext: modelContext)
                } else {
                    let localItem = try makeLocalItem(from: remoteItem, modelContext: modelContext)
                    modelContext.insert(localItem)
                }
            }
            try modelContext.save()

            if failedUpsert {
                state = .pendingRetry
                lastErrorMessage = "일부 옷장 변경사항을 서버에 저장하지 못했습니다. 자동으로 다시 시도합니다."
            } else {
                state = .synced
            }
        } catch {
            modelContext.rollback()
            state = .pendingRetry
            lastErrorMessage = error.localizedDescription
            #if DEBUG
            print("[FitMatchClosetSync] sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func prepareLocalCache(for userID: UUID, modelContext: ModelContext) throws {
        let storedOwner = defaults.string(forKey: Self.cacheOwnerKey).flatMap(UUID.init(uuidString:))
        if let storedOwner, storedOwner != userID {
            let histories = try modelContext.fetch(FetchDescriptor<RecommendationHistory>())
            histories.forEach(modelContext.delete)
            let items = try modelContext.fetch(FetchDescriptor<UserFit>())
            items.forEach(modelContext.delete)
            try modelContext.save()
            remoteItemsByClientID.removeAll()
        }
        defaults.set(userID.uuidString, forKey: Self.cacheOwnerKey)
    }

    private func flushPendingDeletes(userID: UUID) async throws {
        var pending = pendingDeleteIDs(for: userID)
        guard !pending.isEmpty else { return }

        for clientItemID in pending {
            guard let remoteItem = remoteItemsByClientID[clientItemID] else {
                pending.remove(clientItemID)
                continue
            }
            _ = try await remote.deleteClosetItem(closetItemID: remoteItem.closetItemID)
            pending.remove(clientItemID)
            remoteItemsByClientID.removeValue(forKey: clientItemID)
        }
        storePendingDeleteIDs(pending, for: userID)
    }

    private func makeUpsertRequest(for item: UserFit) async throws -> FitMatchUpsertClosetItemRequest {
        var productID = remoteItemsByClientID[item.id]?.productID
        var productSizeID = remoteItemsByClientID[item.id]?.productSizeID
        var databaseClassification: FitMatchDatabaseClassification?

        if productID == nil, let request = databaseRequest(for: item) {
            let resolution = try await remote.resolve(request)
            if resolution.catalogState == "current", let resolvedProductID = resolution.productID {
                productID = resolvedProductID
                databaseClassification = resolution.classification
                if let runtime = try? await remote.fetchProductRuntime(request) {
                    productSizeID = uniqueRuntimeSizeID(
                        in: runtime,
                        matching: item.sizeName,
                        colorName: item.sourceProduct?.checkedColorName
                    )
                }
            }
        }

        var override: FitMatchClosetClassificationOverride?
        if productID != nil,
           let databaseClassification,
           databaseClassification.status == "confirmed",
           classificationDiffers(item, database: databaseClassification) {
            guard let familyCode = resolvedFamilyCode(for: item) else {
                productID = nil
                productSizeID = nil
                return FitMatchUpsertClosetItemRequest(
                    clientItemID: item.id,
                    item: payload(for: item),
                    productID: nil,
                    productSizeID: nil,
                    override: nil
                )
            }
            override = FitMatchClosetClassificationOverride(
                categoryCode: item.resolvedCategoryCode ?? item.category.taxonomyCode,
                detailCode: item.resolvedDetailCategoryCode ?? "other",
                familyCode: familyCode,
                lengthCode: resolvedLengthCode(for: item),
                reason: "user_confirmed_closet_classification",
                evidence: ["client_item_id": item.id.uuidString]
            )
        }

        return FitMatchUpsertClosetItemRequest(
            clientItemID: item.id,
            item: payload(for: item),
            productID: productID,
            productSizeID: productSizeID,
            override: override
        )
    }

    private func payload(for item: UserFit) -> FitMatchClosetItemPayload {
        let records = item.measurementRecords.map { record in
            FitMatchClosetMeasurementRecordPayload(
                value: record.value,
                unit: record.unitRawValue,
                measurementCode: record.measurementCodeRawValue,
                displayKind: record.displayKindRawValue,
                methodSource: record.methodSource,
                methodProfile: record.methodProfile,
                inputSource: record.inputSourceRawValue,
                standardVersion: record.standardVersion,
                mappingVersion: record.mappingVersion,
                rawCode: record.rawCode,
                rawLabel: record.rawLabel,
                rawInfo: record.rawInfo,
                rawValueText: record.rawValueText,
                evidenceLevel: record.evidenceLevelRawValue,
                semanticStatus: record.semanticStatusRawValue
            )
        }
        var clientSnapshot = [
            "local_model": "UserFit",
            "local_schema": "1"
        ]
        if let productCode = item.sourceProduct?.productCode, !productCode.isEmpty {
            clientSnapshot["external_product_id"] = productCode
        }

        return FitMatchClosetItemPayload(
            productName: item.productName,
            brand: item.brandName,
            sizeName: item.sizeName,
            genderCode: item.resolvedGenderCode,
            source: resolvedSourceCode(for: item),
            categoryCode: item.resolvedCategoryCode ?? item.category.taxonomyCode,
            detailCode: item.resolvedDetailCategoryCode ?? "other",
            familyCode: resolvedFamilyCode(for: item),
            lengthCode: resolvedLengthCode(for: item),
            bodyLengthCode: resolvedBodyLengthCode(for: item),
            sourceCategoryPath: item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath,
            productURL: item.sourceProduct?.sourceURLString,
            imageURL: item.sourceProduct?.imageURLString,
            measurements: measurementValues(for: item),
            measurementRecords: records,
            fitMemo: item.fitMemo,
            fitPreferenceCode: item.fitPreference.databaseCode,
            satisfaction: item.satisfaction,
            isReference: item.isRepresentative,
            classificationVersion: item.canonicalPolicyVersion,
            clientSnapshot: clientSnapshot,
            clientCreatedAt: encodeDate(item.createdAt),
            clientUpdatedAt: encodeDate(item.updatedAt)
        )
    }

    private func databaseRequest(for item: UserFit) -> FitMatchProductResolutionRequest? {
        guard let product = item.sourceProduct,
              let externalProductID = product.productCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !externalProductID.isEmpty else { return nil }
        let source = resolvedSourceCode(for: item)
        guard source == "uniqlo" || source == "musinsa" || source == "zara" || source == "cos" else { return nil }
        let categoryCodes = [
            product.categoryDepth1Code,
            product.categoryDepth2Code,
            product.categoryDepth3Code,
            product.categoryDepth4Code
        ].compactMap { $0?.nilIfBlank }
        return FitMatchProductResolutionRequest(
            source: source,
            externalProductID: externalProductID,
            productName: product.name,
            sourceCategoryPath: product.sourceCategoryPath?.nilIfBlank,
            audience: product.genderCodes
                .split(separator: ",")
                .map(String.init)
                .first,
            sourceCategoryCodes: categoryCodes.isEmpty ? nil : categoryCodes
        )
    }

    private func uniqueRuntimeSizeID(
        in runtime: FitMatchProductRuntimeResponse,
        matching sizeName: String,
        colorName: String?
    ) -> UUID? {
        let normalizedSize = sizeName.fitMatchDisplaySizeName.lowercased()
        var variants = runtime.variants
        if let colorName = colorName?.nilIfBlank {
            let colorMatches = variants.filter {
                $0.colorName?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
                    || $0.variantName?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
            }
            if !colorMatches.isEmpty { variants = colorMatches }
        }
        let matches = variants.flatMap(\.sizes).filter {
            $0.sizeLabel.fitMatchDisplaySizeName.lowercased() == normalizedSize
                || $0.normalizedSizeLabel.fitMatchDisplaySizeName.lowercased() == normalizedSize
        }
        return matches.count == 1 ? matches[0].productSizeID : nil
    }

    private func classificationDiffers(
        _ item: UserFit,
        database: FitMatchDatabaseClassification
    ) -> Bool {
        item.resolvedCategoryCode != database.categoryCode
            || item.resolvedDetailCategoryCode != database.detailCode
            || resolvedFamilyCode(for: item) != database.familyCode
            || resolvedLengthCode(for: item) != database.lengthCode
    }

    private func makeLocalItem(
        from record: FitMatchClosetItemRecord,
        modelContext: ModelContext
    ) throws -> UserFit {
        let category = ClothingCategory.fromTaxonomyCode(record.categoryCode)
        let detail = ClosetDetailCategory.fromTaxonomyCode(record.detailCode)
        let gender = UserGender.fromTaxonomyCode(record.genderCode ?? "unknown")
        let product = try restoredProduct(from: record, category: category, modelContext: modelContext)
        let size = try restoredProductSize(
            from: record,
            product: product,
            modelContext: modelContext
        )
        let item = UserFit(
            id: record.clientItemID,
            sourceType: sourceType(for: record.source),
            sourceName: sourceDisplayName(for: record.source),
            sourceCategoryPath: record.sourceCategoryPath,
            brandName: record.brand ?? "브랜드 없음",
            gender: gender,
            productName: record.productName,
            category: category,
            detailCategory: detail,
            sizeName: record.sizeName ?? "기준",
            measurements: restoredMeasurements(from: record),
            fitMemo: record.fitMemo,
            fitPreference: FitPreference.fromDatabaseCode(record.fitPreferenceCode),
            satisfaction: record.satisfaction,
            isRepresentative: record.isReference,
            sourceProduct: product,
            sourceProductSize: size,
            createdAt: decodeDate(record.clientCreatedAt ?? record.createdAt) ?? Date(),
            updatedAt: decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? Date()
        )
        applyClassification(record, to: item)
        item.replaceMeasurementRecords(with: restoredMeasurementRecords(from: record, item: item))
        item.updatedAt = decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? item.updatedAt
        return item
    }

    private func apply(
        _ record: FitMatchClosetItemRecord,
        to item: UserFit,
        modelContext: ModelContext
    ) throws {
        let category = ClothingCategory.fromTaxonomyCode(record.categoryCode)
        let detail = ClosetDetailCategory.fromTaxonomyCode(record.detailCode)
        item.sourceType = sourceType(for: record.source)
        item.sourceName = sourceDisplayName(for: record.source)
        item.sourcePlatformCode = record.source
        item.sourceCategoryPath = record.sourceCategoryPath
        item.brandName = record.brand ?? "브랜드 없음"
        item.gender = UserGender.fromTaxonomyCode(record.genderCode ?? "unknown")
        item.productName = record.productName
        item.category = category
        item.detailCategory = detail
        item.sizeName = record.sizeName ?? "기준"
        item.measurements = restoredMeasurements(from: record)
        item.fitMemo = record.fitMemo
        item.fitPreference = FitPreference.fromDatabaseCode(record.fitPreferenceCode)
        item.satisfaction = record.satisfaction
        item.isRepresentative = record.isReference
        item.measurementRecords.forEach(modelContext.delete)
        item.replaceMeasurementRecords(with: restoredMeasurementRecords(from: record, item: item))
        item.sourceProduct = try restoredProduct(from: record, category: category, modelContext: modelContext)
        item.sourceProductSize = try restoredProductSize(
            from: record,
            product: item.sourceProduct,
            modelContext: modelContext
        )
        applyClassification(record, to: item)
        item.createdAt = decodeDate(record.clientCreatedAt ?? record.createdAt) ?? item.createdAt
        item.updatedAt = decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? item.updatedAt
    }

    private func applyClassification(_ record: FitMatchClosetItemRecord, to item: UserFit) {
        item.categoryCode = record.categoryCode
        item.detailCategoryCode = record.detailCode
        item.garmentTypeRawValue = record.familyCode
        item.sleeveTypeRawValue = record.lengthCode
        item.canonicalEligibility = record.classificationStatus == "confirmed"
        item.canonicalResolutionMethod = record.classificationSource
        item.canonicalPolicyVersion = record.classificationSnapshot["decision_version"] ?? nil
    }

    private func restoredProduct(
        from record: FitMatchClosetItemRecord,
        category: ClothingCategory,
        modelContext: ModelContext
    ) throws -> Product? {
        guard let productID = record.productID else { return nil }
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == productID })
        if let existing = try modelContext.fetch(descriptor).first { return existing }

        let codes = record.sourceCategoryCodes
        let metadata = ProductMetadata(
            sourceCategoryPath: record.sourceCategoryPath,
            categoryDepth1Code: codes.indices.contains(0) ? codes[0] : nil,
            categoryDepth2Code: codes.indices.contains(1) ? codes[1] : nil,
            categoryDepth3Code: codes.indices.contains(2) ? codes[2] : nil,
            categoryDepth4Code: codes.indices.contains(3) ? codes[3] : nil,
            genderCodes: record.productAudience.map { [$0] } ?? []
        )
        let product = Product(
            id: productID,
            name: record.productName,
            category: category,
            productCode: record.externalProductID,
            sourceURLString: record.productURL,
            imageURLString: record.imageURL,
            metadata: metadata,
            sourceType: sourceType(for: record.source),
            sourceName: sourceDisplayName(for: record.source),
            source: .catalog
        )
        modelContext.insert(product)
        return product
    }

    private func restoredProductSize(
        from record: FitMatchClosetItemRecord,
        product: Product?,
        modelContext: ModelContext
    ) throws -> ProductSize? {
        guard let productSizeID = record.productSizeID, let product else { return nil }
        let descriptor = FetchDescriptor<ProductSize>(predicate: #Predicate { $0.id == productSizeID })
        if let existing = try modelContext.fetch(descriptor).first { return existing }
        let size = ProductSize(
            id: productSizeID,
            name: record.sizeName ?? "기준",
            measurements: restoredMeasurements(from: record),
            product: product
        )
        modelContext.insert(size)
        return size
    }

    private func restoredMeasurementRecords(
        from record: FitMatchClosetItemRecord,
        item: UserFit
    ) -> [GarmentMeasurementRecord] {
        record.measurementRecords.compactMap { payload in
            let code = localMeasurementCode(payload.measurementCode)
            guard code != .unknown else { return nil }
            return GarmentMeasurementRecord(
                value: payload.value,
                unit: MeasurementUnit(rawValue: payload.unit) ?? .centimeter,
                measurementCode: code,
                displayKind: MeasurementDisplayKind(rawValue: payload.displayKind) ?? .unknown,
                methodSource: payload.methodSource,
                methodProfile: payload.methodProfile,
                inputSource: MeasurementInputSource(rawValue: payload.inputSource) ?? .importedSizeChart,
                standardVersion: payload.standardVersion,
                mappingVersion: payload.mappingVersion,
                rawCode: payload.rawCode,
                rawLabel: payload.rawLabel,
                rawInfo: payload.rawInfo,
                rawValueText: payload.rawValueText,
                evidenceLevel: MeasurementEvidenceLevel(rawValue: payload.evidenceLevel) ?? .unknown,
                semanticStatus: MeasurementSemanticStatus(rawValue: payload.semanticStatus) ?? .unknownDefinition,
                userFit: item
            )
        }
    }

    private func measurementValues(for item: UserFit) -> [String: Double] {
        var result: [String: Double] = [:]
        for record in item.measurementRecords where record.value.isFinite && record.value > 0 {
            result[record.measurementCodeRawValue] = record.value
        }
        if result.isEmpty {
            let values: [(String, Double)] = [
                ("shoulder_width", item.shoulder),
                ("chest_width", item.chest),
                ("body_length", item.totalLength),
                ("sleeve_length", item.sleeveLength),
                ("waist_width", item.waist),
                ("hip_width", item.hip),
                ("thigh_width", item.thigh),
                ("rise", item.rise),
                ("hem_width", item.hem),
                ("foot_length", item.footLength),
                ("under_bust_width", item.underBust)
            ]
            for (key, value) in values where value.isFinite && value > 0 { result[key] = value }
        }
        return result
    }

    private func restoredMeasurements(from record: FitMatchClosetItemRecord) -> GarmentMeasurements {
        var values: [MeasurementDisplayKind: Double] = [:]
        for measurement in record.measurementRecords where measurement.value > 0 {
            guard let kind = MeasurementDisplayKind(rawValue: measurement.displayKind) else { continue }
            values[kind] = measurement.value
        }
        func value(_ kind: MeasurementDisplayKind, aliases: [String]) -> Double {
            if let value = values[kind] { return value }
            for alias in aliases {
                if let value = record.measurements[alias] { return value }
            }
            return 0
        }
        return GarmentMeasurements(
            shoulder: value(.shoulder, aliases: ["shoulder_width", "shoulder_width_seam_to_seam"]),
            chest: value(.chest, aliases: ["chest_width", "chest_width_pit_to_pit"]),
            totalLength: value(.totalLength, aliases: ["body_length", "body_length_back_neck_to_hem", "pants_outseam"]),
            sleeveLength: value(.sleeveLength, aliases: ["sleeve_length", "sleeve_shoulder_seam_to_cuff"]),
            waist: value(.waist, aliases: ["waist_width", "waist_width_edge_to_edge"]),
            hip: value(.hip, aliases: ["hip_width", "hip_width_at_widest"]),
            thigh: value(.thigh, aliases: ["thigh_width", "thigh_width_crotch_to_outer"]),
            rise: value(.rise, aliases: ["rise", "front_rise", "rise_crotch_to_waist_front"]),
            hem: value(.hem, aliases: ["hem_width", "hem_width_edge_to_edge"]),
            footLength: value(.footLength, aliases: ["foot_length", "foot_length_heel_to_toe"]),
            underBust: value(.underBust, aliases: ["under_bust_width", "under_bust_width_edge_to_edge"])
        )
    }

    private func localMeasurementCode(_ code: String) -> MeasurementCode {
        if let exact = MeasurementCode(rawValue: code) { return exact }
        switch code {
        case "shoulder_width": return .shoulderWidthSeamToSeam
        case "chest_width": return .chestWidthPitToPit
        case "body_length": return .bodyLengthBackNeckToHem
        case "sleeve_length": return .sleeveShoulderSeamToCuff
        case "waist_width": return .waistWidthEdgeToEdge
        case "hip_width": return .hipWidthAtWidest
        case "thigh_width": return .thighWidthCrotchToOuter
        case "rise", "front_rise": return .riseCrotchToWaistFront
        case "hem_width": return .hemWidthEdgeToEdge
        case "foot_length": return .footLengthHeelToToe
        case "under_bust_width": return .underBustWidthEdgeToEdge
        default: return .unknown
        }
    }

    private func resolvedSourceCode(for item: UserFit) -> String {
        if let value = item.sourcePlatformCode?.lowercased(), value == "uniqlo" || value == "musinsa" || value == "zara" || value == "cos" {
            return value
        }
        let text = "\(item.sourceName) \(item.sourceProduct?.sourceName ?? "")".lowercased()
        if text.contains("유니클로") || text.contains("uniqlo") { return "uniqlo" }
        if text.contains("무신사") || text.contains("musinsa") { return "musinsa" }
        if text.contains("zara") || text.contains("자라") { return "zara" }
        if text.contains("cos") { return "cos" }
        return "manual"
    }

    private func sourceType(for source: String) -> ProductSourceType {
        switch source {
        case "uniqlo": return .officialStore
        case "musinsa": return .marketplace
        case "zara": return .officialStore
        case "cos": return .officialStore
        default: return .manual
        }
    }

    private func sourceDisplayName(for source: String) -> String {
        switch source {
        case "uniqlo": return "유니클로 공식몰"
        case "musinsa": return "무신사"
        case "zara": return "ZARA 공식몰"
        case "cos": return "COS 공식몰"
        default: return "직접 입력"
        }
    }

    private func resolvedFamilyCode(for item: UserFit) -> String? {
        if let value = item.garmentTypeRawValue?.nilIfBlank, value != "unknown" { return value }
        return ParsedClosetClassification.resolve(
            category: item.category,
            detailCategory: item.detailCategory,
            sourceDepths: [item.sourceCategoryDepth1, item.sourceCategoryDepth2, item.sourceCategoryDepth3, item.sourceCategoryDepth4],
            sourcePath: item.sourceCategoryPath,
            productName: item.productName
        )?.garmentFamily.rawValue.nilIfBlank
    }

    private func resolvedLengthCode(for item: UserFit) -> String? {
        if let value = item.sleeveTypeRawValue?.nilIfBlank, value != "unknown" { return value }
        return ParsedClosetClassification.resolve(
            category: item.category,
            detailCategory: item.detailCategory,
            sourceDepths: [item.sourceCategoryDepth1, item.sourceCategoryDepth2, item.sourceCategoryDepth3, item.sourceCategoryDepth4],
            sourcePath: item.sourceCategoryPath,
            productName: item.productName
        )?.lengthType.rawValue.nilIfBlank
    }

    private func resolvedBodyLengthCode(for item: UserFit) -> String? {
        guard let value = item.canonicalProfileSnapshot?.lengthAxes.body,
              value != "unknown", value != "not_applicable" else { return nil }
        return value
    }

    private func remoteDate(_ record: FitMatchClosetItemRecord) -> Date {
        decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? .distantPast
    }

    private func encodeDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func decodeDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func pendingDeleteIDs(for userID: UUID) -> Set<UUID> {
        let key = Self.pendingDeletePrefix + userID.uuidString
        let values = defaults.stringArray(forKey: key) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func storePendingDeleteIDs(_ ids: Set<UUID>, for userID: UUID) {
        let key = Self.pendingDeletePrefix + userID.uuidString
        defaults.set(ids.map(\.uuidString).sorted(), forKey: key)
    }
}

private extension FitPreference {
    var databaseCode: String {
        switch self {
        case .slim: return "slim"
        case .regular: return "regular"
        case .semiOver: return "semi_over"
        case .over: return "over"
        case .boxy: return "boxy"
        }
    }

    static func fromDatabaseCode(_ code: String) -> FitPreference {
        switch code {
        case "slim": return .slim
        case "semi_over": return .semiOver
        case "over": return .over
        case "boxy": return .boxy
        default: return .regular
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct FitMatchClosetSyncCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: FitMatchClosetSyncCoordinator? = nil
}

extension EnvironmentValues {
    var fitMatchClosetSyncCoordinator: FitMatchClosetSyncCoordinator? {
        get { self[FitMatchClosetSyncCoordinatorEnvironmentKey.self] }
        set { self[FitMatchClosetSyncCoordinatorEnvironmentKey.self] = newValue }
    }
}
