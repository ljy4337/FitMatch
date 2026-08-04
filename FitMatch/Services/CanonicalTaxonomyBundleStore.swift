import CryptoKit
import Foundation

struct CanonicalTaxonomyLookupInput {
    let source: String?
    let externalCategoryID: String?
    let target: String?
    let sourceCategoryPath: String?
}

final class CanonicalTaxonomyBundleStore {
    static let shared = CanonicalTaxonomyBundleStore()

    enum StoreError: Error {
        case missingResource(String)
        case checksumMismatch(String)
        case invalidCounts
    }

    private struct MappingFile: Decodable {
        let records: [MappingRecord]
    }

    private struct MappingRecord: Decodable {
        struct AppMapping: Decodable {
            let categoryCode: String?
            let currentComparisonFamily: String?
            let currentLengthType: String?
            let detailCode: String?
        }

        let appMapping: AppMapping?
        let comparisonFamily: String?
        let constructionType: String
        let decisionStatus: CanonicalTaxonomyDecision
        let eligibility: Bool
        let externalCategoryID: String?
        let lengthAxes: CanonicalLengthAxes
        let normalizedPath: String?
        let policyVersion: String
        let resolutionMethod: String
        let runtimeLookupEligible: Bool
        let semanticCategoryCode: String?
        let semanticGarmentType: String?
        let source: String
        let sourceIdentity: String?
        let target: String?
    }

    private struct ComparisonPolicyFile: Decodable {
        struct GarmentPolicy: Decodable {
            let comparisonFamily: String
            let excludedMeasurements: [String]
            let optionalMeasurements: [String]
            let requiredMeasurements: [String]
        }
        let garmentPolicies: [GarmentPolicy]
        let currentAppFamilyTransforms: [String: String]
    }

    private struct Manifest: Decodable {
        struct FileEntry: Decodable { let sha256: String }
        let runtimeMappingRowCount: Int
        let files: [String: FileEntry]
        let policyVersion: String
    }

    private let externalIndex: [String: [MappingRecord]]
    private let targetPathIndex: [String: [MappingRecord]]
    private let pathIndex: [String: [MappingRecord]]
    private let policies: [String: ComparisonPolicyFile.GarmentPolicy]
    private let familyTransforms: [String: String]
    let policyVersion: String

    convenience init() {
        do {
            try self.init(bundle: .main)
        } catch {
            assertionFailure("Canonical taxonomy bundle load failed: \(error)")
            self.init(emptyPolicyVersion: "unavailable")
        }
    }

    init(bundle: Bundle) throws {
        let names = [
            "FitMatchSourceCategoryMappings.json",
            "FitMatchComparisonPolicies.json",
            "FitMatchMeasurementPolicies.json",
            "FitMatchTaxonomyBundleManifest.json"
        ]
        let data = try Dictionary(uniqueKeysWithValues: names.map { name in
            guard let url = Self.resourceURL(named: name, bundle: bundle) else {
                throw StoreError.missingResource(name)
            }
            return (name, try Data(contentsOf: url))
        })
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(Manifest.self, from: data["FitMatchTaxonomyBundleManifest.json"]!)
        for (name, entry) in manifest.files {
            guard let fileData = data[name], Self.sha256(fileData) == entry.sha256 else {
                throw StoreError.checksumMismatch(name)
            }
        }
        let mappings = try decoder.decode(MappingFile.self, from: data["FitMatchSourceCategoryMappings.json"]!)
        guard mappings.records.count == manifest.runtimeMappingRowCount else { throw StoreError.invalidCounts }
        let comparison = try decoder.decode(ComparisonPolicyFile.self, from: data["FitMatchComparisonPolicies.json"]!)
        self.policyVersion = manifest.policyVersion
        self.policies = Dictionary(uniqueKeysWithValues: comparison.garmentPolicies.map { ($0.comparisonFamily, $0) })
        self.familyTransforms = comparison.currentAppFamilyTransforms
        let eligible = mappings.records.filter(\.runtimeLookupEligible)
        self.externalIndex = Dictionary(grouping: eligible.filter { $0.externalCategoryID != nil }) {
            Self.externalKey(source: $0.source, id: $0.externalCategoryID!)
        }
        self.targetPathIndex = Dictionary(grouping: eligible.filter { $0.normalizedPath != nil }) {
            Self.targetPathKey(source: $0.source, target: $0.target, path: $0.normalizedPath!)
        }
        self.pathIndex = Dictionary(grouping: eligible.filter { $0.normalizedPath != nil }) {
            Self.pathKey(source: $0.source, path: $0.normalizedPath!)
        }
    }

    private init(emptyPolicyVersion: String) {
        externalIndex = [:]
        targetPathIndex = [:]
        pathIndex = [:]
        policies = [:]
        familyTransforms = [:]
        policyVersion = emptyPolicyVersion
    }

    func profile(for input: CanonicalTaxonomyLookupInput) -> CanonicalComparisonProfile? {
        guard let source = Self.normalizedSource(input.source) else { return nil }
        let record: MappingRecord?
        if let id = Self.nonempty(input.externalCategoryID) {
            record = uniqueOutcome(externalIndex[Self.externalKey(source: source, id: id)])
        } else if let path = Self.nonempty(input.sourceCategoryPath) {
            record = uniqueOutcome(targetPathIndex[Self.targetPathKey(source: source, target: input.target, path: path)])
                ?? uniqueOutcome(pathIndex[Self.pathKey(source: source, path: path)])
        } else {
            record = nil
        }
        guard let record else { return nil }
        let family = record.comparisonFamily ?? record.appMapping?.currentComparisonFamily
        let policy = family.flatMap { policies[$0] }
        return CanonicalComparisonProfile(
            decision: record.decisionStatus,
            semanticCategoryCode: record.semanticCategoryCode ?? record.appMapping?.categoryCode,
            semanticGarmentType: record.semanticGarmentType ?? record.appMapping?.detailCode,
            comparisonFamily: family,
            appComparisonFamily: family.flatMap { familyTransforms[$0] },
            lengthAxes: record.lengthAxes,
            constructionType: record.constructionType,
            eligibility: record.eligibility,
            requiredMeasurements: policy?.requiredMeasurements ?? [],
            optionalMeasurements: policy?.optionalMeasurements ?? [],
            excludedMeasurements: policy?.excludedMeasurements ?? [],
            policyVersion: record.policyVersion,
            resolutionMethod: record.resolutionMethod,
            sourceIdentity: record.sourceIdentity
        )
    }

    private func uniqueOutcome(_ records: [MappingRecord]?) -> MappingRecord? {
        guard let records, let first = records.first else { return nil }
        let signature = outcomeSignature(first)
        return records.allSatisfy { outcomeSignature($0) == signature } ? first : nil
    }

    private func outcomeSignature(_ record: MappingRecord) -> String {
        [record.decisionStatus.rawValue, record.eligibility.description,
         record.comparisonFamily ?? "", record.semanticCategoryCode ?? "",
         record.semanticGarmentType ?? "", record.constructionType,
         record.lengthAxes.sleeve, record.lengthAxes.pants, record.lengthAxes.leggings,
         record.lengthAxes.skirt, record.lengthAxes.body].joined(separator: "|")
    }

    static func normalizePath(_ value: String) -> String {
        var result = value.precomposedStringWithCanonicalMapping
        let entities = ["&amp;": "&", "&gt;": ">", "&lt;": "<", "&quot;": "\"", "&#39;": "'"]
        for (entity, replacement) in entities { result = result.replacingOccurrences(of: entity, with: replacement) }
        result = result.replacingOccurrences(of: #"\s*(?:>|›|→)\s*"#, with: " > ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedSource(_ value: String?) -> String? {
        guard let value = nonempty(value)?.lowercased() else { return nil }
        if value.contains("musinsa") || value.contains("무신사") { return "musinsa" }
        if value.contains("uniqlo") || value.contains("유니클로") { return "uniqlo" }
        return value
    }

    private static func nonempty(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func externalKey(source: String, id: String) -> String { "\(source.lowercased())|\(id)" }
    private static func targetPathKey(source: String, target: String?, path: String) -> String {
        "\(source.lowercased())|\((nonempty(target) ?? "UNKNOWN").uppercased())|\(normalizePath(path))"
    }
    private static func pathKey(source: String, path: String) -> String { "\(source.lowercased())|\(normalizePath(path))" }

    private static func resourceURL(named name: String, bundle: Bundle) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return bundle.url(forResource: base, withExtension: ext, subdirectory: "CanonicalTaxonomyBundle")
            ?? bundle.url(forResource: base, withExtension: ext)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
