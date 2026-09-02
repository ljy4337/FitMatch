import Foundation

/// A retailer-supplied statement about how many garments a purchasable product
/// represents. This is deliberately an input fact, not an iOS classification:
/// the database remains responsible for all canonical garment authority.
enum RetailerProductStructure: String, CaseIterable, Equatable, Sendable {
    case single
    case set
    case multipack
    case unknown
}

/// Keeps the structure value together with the provider field or presentation
/// contract that established it. All three values are persisted as opaque
/// retailer facts so SwiftData replay never has to derive the fact again.
struct RetailerProductStructureFact: Equatable, Sendable {
    let structure: RetailerProductStructure
    let source: String
    let evidence: String

    var structuredFacts: [String: String] {
        [
            "product_structure": structure.rawValue,
            "product_structure_source": source,
            "product_structure_evidence": evidence
        ]
    }

    /// A product title, label, or detail sentence is retailer evidence only
    /// when it *positively declares* a composite.  The detector deliberately
    /// has no negative branch: a title that is not a set or pack is UNKNOWN,
    /// never SINGLE.
    static func explicitCompositeRetailerText(
        _ text: String,
        source: String,
        evidenceField: String
    ) -> RetailerProductStructureFact? {
        let normalized = RetailerCompositeRetailerText.normalize(text)
        guard !normalized.isEmpty else { return nil }

        // A mixed-garment declaration is stronger than a pack-count token.
        // For example, a top+bottom "2-piece" must never be treated as a
        // homogeneous multipack merely because it also contains a quantity.
        if RetailerCompositeRetailerText.declaresMixedSet(normalized) {
            return RetailerProductStructureFact(
                structure: .set,
                source: source,
                evidence: "\(evidenceField):explicit_mixed_garment_set"
            )
        }

        if RetailerCompositeRetailerText.declaresHomogeneousMultipack(normalized) {
            return RetailerProductStructureFact(
                structure: .multipack,
                source: source,
                evidence: "\(evidenceField):explicit_multipack"
            )
        }
        return nil
    }

    /// Compatibility spelling for existing provider parsers.  The input is
    /// still a retailer-provided text field; it is not a replay fallback.
    static func explicitCompositeRetailerName(
        _ productName: String,
        source: String
    ) -> RetailerProductStructureFact? {
        explicitCompositeRetailerText(
            productName,
            source: source,
            evidenceField: "retailer_product_name"
        )
    }
}

/// Deliberately narrow text normalization for *positive retailer composite
/// declarations*. It understands Korean and English PDP wording but never
/// derives a garment category, a global classification, or a SINGLE fact.
private enum RetailerCompositeRetailerText {
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func declaresHomogeneousMultipack(_ normalized: String) -> Bool {
        let fixedMarkers = [
            "multipack", "multi pack",
            "두팩", "투팩", "쓰리팩", "네팩", "다섯팩"
        ]
        if fixedMarkers.contains(where: normalized.contains) { return true }

        // Counts are only composite evidence when paired with an explicit
        // retailer packaging/unit word.  This catches "3P", "3장 세트",
        // "2팩", "5개입", and equivalent English PDP wording without
        // treating a bare number, product ID, or size name as a pack count.
        let pattern = #"(?:^|[^0-9])([2-9]|[1-9][0-9]+)\s*(?:p|pack|packs|pc|pcs|pair|pairs|팩|개입|매입|장\s*세트|켤레)(?:$|[^a-z0-9가-힣])"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    static func declaresMixedSet(_ normalized: String) -> Bool {
        let explicitMixedMarkers = [
            "상하의 세트", "상의 하의 세트", "상의 하의", "탑 바텀",
            "파자마 세트", "정장 세트", "수트 세트", "셋업 수트",
            "투피스", "top bottom set",
            "shirt pants set", "jacket pants set", "pajama set", "suit set"
        ]
        if explicitMixedMarkers.contains(where: normalized.contains) { return true }

        let hasSetWord = normalized.contains("세트")
            || normalized.contains("셋업")
            || normalized.contains(" set ")
            || normalized.hasPrefix("set ")
            || normalized.hasSuffix(" set")
        guard hasSetWord else { return false }

        // Korean "티셔츠" includes the substring "셔츠". They are one
        // garment family, never evidence of a top+bottom composition.
        let isTshirt = ["티셔츠", "t shirt", "tshirt"].contains(where: normalized.contains)
        let families = [
            isTshirt || ["탑", " top"].contains(where: normalized.contains),
            !isTshirt && ["셔츠", "shirt", "블라우스", "blouse"].contains(where: normalized.contains),
            ["니트", "sweater", "knit", "가디건", "cardigan"].contains(where: normalized.contains),
            ["재킷", "자켓", "jacket", "blazer", "코트", "coat"].contains(where: normalized.contains),
            ["팬츠", "바지", "pants", "trousers", "슬랙스"].contains(where: normalized.contains),
            ["스커트", "skirt"].contains(where: normalized.contains),
            ["레깅스", "leggings"].contains(where: normalized.contains),
            ["원피스", "dress"].contains(where: normalized.contains),
            ["점프수트", "점프 슈트", "jumpsuit", "overall"].contains(where: normalized.contains)
        ]
        return families.filter { $0 }.count >= 2
    }
}

/// A retailer/API fact about whether one product observation exposes one
/// coherent garment measurement table. This is intentionally independent from
/// product cardinality: a MULTIPACK can expose one coherent garment contract,
/// while an UNKNOWN structure is never rewritten as SINGLE.
enum RetailerComparisonMeasurementContract: String, CaseIterable, Equatable, Sendable {
    case singleCoherent = "single_coherent"
    case multipleComponent = "multiple_component"
    case absent
    case unknown
}

struct RetailerComparisonMeasurementContractFact: Equatable, Sendable {
    let contract: RetailerComparisonMeasurementContract
    let source: String
    let evidence: String

    var structuredFacts: [String: String] {
        [
            "comparison_measurement_contract": contract.rawValue,
            "comparison_measurement_contract_source": source,
            "comparison_measurement_contract_evidence": evidence
        ]
    }

    /// The provider must expose actual size-table records. A bare size list,
    /// local category, or guessed size schema is never enough to create a
    /// coherent-contract fact.
    static func retailerSizeTable(
        sizes: [ParsedProductSize],
        productStructure: RetailerProductStructure?
    ) -> RetailerComparisonMeasurementContractFact {
        let observedSchemas = sizes.compactMap { size -> Set<String>? in
            let fields = Set(size.measurementRecords.compactMap { record -> String? in
                guard record.inputSource == .importedSizeChart,
                      record.value.isFinite,
                      record.value > 0 else {
                    return nil
                }
                let raw = (record.rawCode ?? record.rawLabel)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return raw.isEmpty ? nil : raw
            })
            return fields.isEmpty ? nil : fields
        }

        guard !observedSchemas.isEmpty else {
            return RetailerComparisonMeasurementContractFact(
                contract: .absent,
                source: "retailer_size_table",
                evidence: "no_imported_measurement_records"
            )
        }

        if productStructure == .set {
            return RetailerComparisonMeasurementContractFact(
                contract: .multipleComponent,
                source: "retailer_size_table",
                evidence: "explicit_mixed_set_structure"
            )
        }

        // Separate component tables have no stable retailer field in common.
        // Optional columns may vary by size, so overlap—not exact equality—is
        // the conservative proof that all rows describe one table.
        let firstSchema = observedSchemas[0]
        let hasDisjointSchema = observedSchemas.dropFirst().contains {
            firstSchema.isDisjoint(with: $0)
        }
        if hasDisjointSchema {
            return RetailerComparisonMeasurementContractFact(
                contract: .multipleComponent,
                source: "retailer_size_table",
                evidence: "multiple_disjoint_provider_measurement_schemas"
            )
        }

        return RetailerComparisonMeasurementContractFact(
            contract: .singleCoherent,
            source: "retailer_size_table",
            evidence: "one_coherent_imported_measurement_schema"
        )
    }
}

struct ProductMetadata {
    var styleNo: String? = nil
    /// Provider variant identity when it is distinct from the product identity.
    /// ZARA uses this for the URL `v1` / analytics `catentryId` value.
    var externalVariantID: String? = nil
    /// Provider-native product reference kept separately from style, variant,
    /// and internal product identities. ZARA publishes this as `productRef`.
    var externalProductReference: String? = nil
    /// How a provider variant was selected. Kept as provenance rather than UI copy.
    var variantSelectionMethod: String? = nil
    /// Provider variant confidence in the closed 0...1 range.
    var variantSelectionConfidence: Double? = nil
    /// Versioned category mapping source used by the parser.
    var categoryMappingPolicyVersion: String? = nil
    var englishName: String? = nil
    var brandCode: String? = nil
    var brandEnglishName: String? = nil
    var brandLogoImageURLString: String? = nil
    var brandNationName: String? = nil
    var sourceCategoryPath: String? = nil
    var sourceCategoryDepth1: String? = nil
    var sourceCategoryDepth2: String? = nil
    var sourceCategoryDepth3: String? = nil
    var sourceCategoryDepth4: String? = nil
    var baseCategoryFullPath: String? = nil
    var categoryDepth1Code: String? = nil
    var categoryDepth1Name: String? = nil
    var categoryDepth2Code: String? = nil
    var categoryDepth2Name: String? = nil
    var categoryDepth3Code: String? = nil
    var categoryDepth3Name: String? = nil
    var categoryDepth4Code: String? = nil
    var categoryDepth4Name: String? = nil
    /// Typed retailer facts forwarded verbatim to the server classification authority.
    /// These facts remain evidence; the iOS parser does not turn them into canonical labels.
    var structuredFacts: [String: String] = [:]
    var sizeType: String? = nil
    var genderCodes: [String] = []
    var labelNames: [String] = []
    var imageURLStrings: [String] = []
    var normalPrice: Int? = nil
    var salePrice: Int? = nil
    var finalPrice: Int? = nil
    var currencyCode: String? = nil
    var discountRate: Double? = nil
    var isSale: Bool = false
    var isOutOfStock: Bool = false
    var stockStatusRawValue: String? = nil
    var isRestock: Bool = false
    var isSoonOutOfStock: Bool = false
    var isLimitedQuantity: Bool = false
    var reviewCount: Int? = nil
    var reviewSatisfactionScore: Double? = nil
    var seasonYear: String? = nil
    var season: String? = nil
    var checkedColorName: String? = nil
    var checkedSizeName: String? = nil

    var mostSpecificExternalCategoryID: String? {
        [categoryDepth4Code, categoryDepth3Code, categoryDepth2Code, categoryDepth1Code]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Persists parser-only structured retailer facts without adding a SwiftData
/// column. `Product.labelNames` is an existing raw-retailer metadata string;
/// normal labels remain readable while one reserved, versioned token carries
/// an opaque JSON payload. Replay always filters that token back out.
enum FitMatchStoredRetailerFacts {
    struct Decoded: Equatable {
        let labelNames: [String]
        let structuredFacts: [String: String]
        let hasVersionedPayload: Bool
    }

    private struct Envelope: Codable {
        let version: Int
        let structuredFacts: [String: String]
    }

    private static let tokenPrefix = "__fitmatch_retailer_facts_v1__:"
    private static let currentVersion = 1

    static func encode(
        labelNames: [String],
        structuredFacts: [String: String]
    ) -> String {
        let retailerLabels = labelNames.filter { !$0.hasPrefix(tokenPrefix) }
        let envelope = Envelope(
            version: currentVersion,
            structuredFacts: structuredFacts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(envelope) else {
            return retailerLabels.joined(separator: ",")
        }
        return (retailerLabels + [tokenPrefix + payload.base64EncodedString()])
            .joined(separator: ",")
    }

    static func decode(_ storage: String) -> Decoded {
        let tokens = storage.split(separator: ",").map(String.init)
        var labels: [String] = []
        var facts: [String: String] = [:]
        var hasVersionedPayload = false

        for token in tokens {
            guard token.hasPrefix(tokenPrefix) else {
                labels.append(token)
                continue
            }
            let payload = String(token.dropFirst(tokenPrefix.count))
            guard let data = Data(base64Encoded: payload),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.version == currentVersion else {
                // Reserved tokens are never surfaced as retailer labels, even
                // when corrupt or from an unsupported future version.
                continue
            }
            facts = envelope.structuredFacts
            hasVersionedPayload = true
        }

        return Decoded(
            labelNames: labels,
            structuredFacts: facts,
            hasVersionedPayload: hasVersionedPayload
        )
    }
}
