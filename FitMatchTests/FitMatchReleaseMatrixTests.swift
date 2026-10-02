import CryptoKit
import Foundation
import Testing
@testable import FitMatch

/// Every original corpus ID is bound to a scoped synthetic production-owner
/// probe. Provider directions and A-G are requested metadata, not fabricated
/// retailer mappings or server authorization. Those evidence gates stay BLOCKED.
@MainActor
struct FitMatchReleaseMatrixTests {
    @Test func smokeRepresentativeCorpusCases() throws {
        let inputs = try ReleaseMatrixInputs.load()
        let selected = inputs.binding.smokeCaseIDs
        let rows = inputs.binding.cases.filter { selected.contains($0.id) }
        try inputs.verifyCoverage(rows: rows, expectedIDs: selected)
        let failures = try run(rows, mode: "smoke", inputs: inputs)
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: " | ")))
    }

    @Test func fullSyntheticCorpusCases() throws {
        let inputs = try ReleaseMatrixInputs.load()
        let rows = inputs.binding.cases
        try inputs.verifyCoverage(rows: rows, expectedIDs: inputs.corpus.map(\.id))
        let failures = try run(rows, mode: "full", inputs: inputs)
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: " | ")))
    }

    private func run(_ rows: [ReleaseMatrixBinding.Case], mode: String,
                     inputs: ReleaseMatrixInputs) throws -> [String] {
        var results: [[String: Any]] = []
        var failures: [String] = []
        for row in rows {
            var failure: String?
            do { try evaluate(row) }
            catch { failure = String(describing: error); failures.append("\(row.id): \(error)") }
            results.append([
                "id": row.id, "status": failure == nil ? "PASS" : "FAIL",
                "evidence_scope": "synthetic_production_owner_probe",
                "authenticated_authorization_status": "BLOCKED",
                "retailer_pair_authorization_status": "BLOCKED",
                "group_policy_authorization_status": "BLOCKED",
                "closet_provider": row.closetProvider, "target_provider": row.targetProvider,
                "requested_group": row.requestedGroup, "requested_group_is_metadata_only": true,
                "pattern": row.pattern, "probe": row.probe, "expected_mode": row.expectedMode,
                "evidence_source": row.evidenceSource, "source_fixture_binding": NSNull(),
                "identities": row.identities, "failure": failure as Any? ?? NSNull(),
                "limitation": row.limitation
            ])
        }
        let report: [String: Any] = [
            "schema_version": "fitmatch-release-matrix-result-v1", "mode": mode,
            "status": failures.isEmpty ? "BLOCKED" : "FAIL",
            "evidence_scope": "synthetic_production_owner_probe",
            "authenticated_authorization_status": "BLOCKED",
            "corpus_sha256": inputs.binding.corpusSHA256,
            "binding_sha256": inputs.bindingSHA256,
            "expected_case_ids": rows.map(\.id), "executed_case_ids": results.map { $0["id"]! },
            "expected_case_count": rows.count, "executed_case_count": results.count,
            "synthetic_pass_count": results.count - failures.count,
            "synthetic_fail_count": failures.count, "cases": results
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        let env = ProcessInfo.processInfo.environment
        if let output = env["FITMATCH_QA_MATRIX_OUTPUT"] ?? env["TEST_RUNNER_FITMATCH_QA_MATRIX_OUTPUT"] {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("matrix-\(mode).json"), options: .atomic)
        }
        print("FITMATCH_RELEASE_MATRIX_SUMMARY mode=\(mode) cases=\(rows.count) synthetic_pass=\(results.count - failures.count) synthetic_fail=\(failures.count) authenticated_authorization=BLOCKED corpus_sha256=\(inputs.binding.corpusSHA256)")
        return failures
    }

    private func evaluate(_ row: ReleaseMatrixBinding.Case) throws {
        let fixture = try ReleaseMatrixSnapshot(row: row)
        let adapter = VNextComparisonEngineAdapter()
        switch row.probe {
        case "approved_canonical_probe":
            let result = try adapter.analyze(fixture.begin())
            try require(result.recommended.productSizeID == fixture.sizeID, "Exact synthetic size identity changed")
            try require(result.completionPayload.score == 90, "Fixed canonical delta 2 expected current-contract score 90")
            try require(result.completionPayload.reliability == 1 && result.completionPayload.coverage == 1,
                        "One approved metric must keep count and coverage separate")
            try require(result.completionPayload.metricEvidence.map(\.measurementCode) == ["chest_width"],
                        "Only the supplied canonical metric may be scored")
        case "empty_evidence_rejected":
            try expectAdapterFailure(.invalidEvidence(fixture.sizeID)) { try adapter.analyze(fixture.begin()) }
        case "required_unit_decode_rejected":
            do {
                _ = try fixture.begin()
                throw ReleaseMatrixFailure("Missing unit decoded successfully")
            } catch DecodingError.keyNotFound(let key, _) {
                try require(key.stringValue == "unit_code", "Wrong required field rejected: \(key.stringValue)")
            }
        case "server_exclusion_enforced":
            try expectAdapterFailure(.excludedMetricUsed("chest_width")) { try adapter.analyze(fixture.begin()) }
        case "raw_zero_policy_display_preserved_unscored":
            for source in Set([row.closetProvider, row.targetProvider]).sorted() {
                let raw = rawMeasurement(source: source, value: 0)
                try require(raw.value == 0 && raw.rawValueText == "0.0", "Original zero source fact changed")
                let rows = MeasurementResolver.sourceDisplayRows(records: [raw])
                if source == "musinsa" {
                    try require(rows.count == 1 && rows.first?.valueText == "-"
                                && rows.first?.isCanonical == false,
                                "Policy requires one noncanonical MUSINSA dash row for received zero")
                } else {
                    try require(rows.isEmpty, "Policy requires other-provider zero rows hidden")
                }
            }
            try expectAdapterFailure(.invalidEvidence(fixture.sizeID)) { try adapter.analyze(fixture.begin()) }
        case "unknown_positive_visible_unscored":
            for source in Set([row.closetProvider, row.targetProvider]).sorted() {
                let raw = rawMeasurement(source: source, value: 17.3)
                let displayed = MeasurementResolver.sourceDisplayRows(records: [raw])
                try require(displayed.count == 1 && displayed.first?.value == 17.3,
                            "Unknown positive source fact was hidden or altered")
                try require(displayed.first?.isCanonical == false, "Unknown raw fact was promoted to canonical")
            }
            let result = try adapter.analyze(fixture.begin())
            try require(result.completionPayload.metricEvidence.map(\.measurementCode) == ["chest_width"],
                        "Unknown source fact entered canonical completion evidence")
        case "unconfirmed_target_rejected":
            try expectAdapterFailure(.classificationNotConfirmed) { try adapter.analyze(fixture.begin()) }
        case "server_denial_enforced":
            try expectAdapterFailure(.authorizationDenied("SYNTHETIC_DIFFERENT_GROUP")) {
                try adapter.analyze(fixture.begin())
            }
        case "candidate_set_mismatch_rejected":
            do {
                _ = try fixture.begin()
                throw ReleaseMatrixFailure("Mismatched authorized size identities decoded successfully")
            } catch let observed as FitMatchVNextContractError {
                try require(observed == .conflictingProof("authorized_candidate_product_size_ids"),
                            "Wrong identity-contract rejection: \(observed)")
            }
        default:
            throw ReleaseMatrixFailure("Unbound probe: \(row.probe)")
        }
    }

    private func rawMeasurement(source: String, value: Double) -> ParsedMeasurement {
        ParsedMeasurement(value: value, measurementCode: .unknown, displayKind: .unknown,
            methodSource: source, inputSource: .importedSizeChart,
            rawCode: "synthetic-unmapped-\(source)", rawLabel: "Synthetic raw fact",
            rawValueText: String(value), evidenceLevel: .unknown, semanticStatus: .unknownDefinition)
    }

    private func expectAdapterFailure(_ expected: VNextComparisonEngineAdapterError,
                                      operation: () throws -> VNextComparisonBatchAnalysis) throws {
        do {
            _ = try operation()
            throw ReleaseMatrixFailure("Expected adapter rejection: \(expected)")
        } catch let observed as VNextComparisonEngineAdapterError {
            try require(observed == expected, "Wrong rejection: \(observed), expected \(expected)")
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ReleaseMatrixFailure(message) }
    }
}

private struct ReleaseMatrixFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct ReleaseMatrixCorpusCase: Decodable {
    let id: String
    let closetProvider: String
    let targetProvider: String
    let requestedGroup: String
    let pattern: String
    let kind: String
}

private struct ReleaseMatrixBinding: Decodable {
    struct Case: Decodable {
        let id: String
        let closetProvider: String
        let targetProvider: String
        let requestedGroup: String
        let pattern: String
        let probe: String
        let expectedMode: String
        let evidenceSource: String
        let identities: [String: String]
        let authenticatedAuthorizationStatus: String
        let requestedGroupIsMetadataOnly: Bool
        let limitation: String
    }
    let corpusPath: String
    let corpusSha256: String
    let corpusCount: Int
    let datasetPath: String
    let datasetSha256: String
    let smokeCaseIds: [String]
    let caseBindings: [Case]
    var corpusSHA256: String { corpusSha256 }
    var smokeCaseIDs: [String] { smokeCaseIds }
    var cases: [Case] { caseBindings }
}

private struct ReleaseMatrixInputs {
    let binding: ReleaseMatrixBinding
    let bindingSHA256: String
    let corpus: [ReleaseMatrixCorpusCase]

    static func load() throws -> Self {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bindingData = try Data(contentsOf: root.appendingPathComponent("Docs/QA/ReleasePreparation20261002/matrix-binding-v2.json"))
        let binding = try decoder.decode(ReleaseMatrixBinding.self, from: bindingData)
        let corpusData = try Data(contentsOf: root.appendingPathComponent(binding.corpusPath))
        let datasetData = try Data(contentsOf: root.appendingPathComponent(binding.datasetPath))
        guard hash(corpusData) == binding.corpusSHA256,
              hash(datasetData) == binding.datasetSha256 else {
            throw ReleaseMatrixFailure("Frozen corpus/dataset hash changed")
        }
        let lines = String(decoding: corpusData, as: UTF8.self).split(separator: "\n")
        let corpus = try lines.map { try decoder.decode(ReleaseMatrixCorpusCase.self, from: Data($0.utf8)) }
        guard corpus.count == 756, binding.corpusCount == 756, binding.cases.count == 756 else {
            throw ReleaseMatrixFailure("756 original cases must remain present")
        }
        let originals = Dictionary(grouping: corpus, by: \.id)
        guard originals.count == 756, Set(binding.cases.map(\.id)).count == 756 else {
            throw ReleaseMatrixFailure("Duplicate original or bound case identity")
        }
        var identities = Set<String>()
        for row in binding.cases {
            guard let original = originals[row.id]?.first,
                  original.closetProvider == row.closetProvider,
                  original.targetProvider == row.targetProvider,
                  original.requestedGroup == row.requestedGroup,
                  original.pattern == row.pattern,
                  original.kind == "synthetic_contract_specification",
                  row.evidenceSource == "synthetic_contract_fixture",
                  row.authenticatedAuthorizationStatus == "BLOCKED",
                  row.requestedGroupIsMetadataOnly,
                  row.identities.count == 6 else {
                throw ReleaseMatrixFailure("Corpus binding or evidence boundary changed for \(row.id)")
            }
            for identity in row.identities.values {
                guard UUID(uuidString: identity) != nil, identities.insert(identity).inserted else {
                    throw ReleaseMatrixFailure("Malformed or reused synthetic identity for \(row.id)")
                }
            }
        }
        return Self(binding: binding, bindingSHA256: hash(bindingData), corpus: corpus)
    }

    func verifyCoverage(rows: [ReleaseMatrixBinding.Case], expectedIDs: [String]) throws {
        guard !rows.isEmpty, rows.count == expectedIDs.count,
              Set(rows.map(\.id)) == Set(expectedIDs) else {
            throw ReleaseMatrixFailure("Selected matrix IDs do not match expected coverage")
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ReleaseMatrixSnapshot {
    let row: ReleaseMatrixBinding.Case
    let sizeID: UUID
    init(row: ReleaseMatrixBinding.Case) throws {
        self.row = row
        guard let value = row.identities["target_product_size_id"], let id = UUID(uuidString: value) else {
            throw ReleaseMatrixFailure("Missing exact synthetic target size")
        }
        sizeID = id
    }

    func begin() throws -> VNextBeginComparisonDTO {
        let denied = row.probe == "server_denial_enforced"
        let excluded = row.probe == "server_exclusion_enforced" ? ["chest_width"] : []
        let authorization: [String: Any] = [
            "decision": "MANUAL_EXTENDED", "allowed": !denied, "mode": "MANUAL_EXTENDED",
            "reason": denied ? "SYNTHETIC_DIFFERENT_GROUP" : NSNull(),
            "excluded_measurement_codes": excluded, "required_measurement_codes": ["chest_width"],
            "minimum_common": 1, "common_measurement_count": 1, "required_any_count": 1,
            "policy_code": "synthetic-canonical-probe", "policy_version": "matrix-v1", "policy_checksum": "synthetic-only"
        ]
        var metric: [String: Any] = [
            "measurement_code": "chest_width", "reference_value": 50, "target_value": 52,
            "difference": 2, "absolute_difference": 2, "weight": 2,
            "unit_code": "CM", "basis_code": "WIDTH", "requirement_mode": "REQUIRED_ANY", "priority": 1
        ]
        if row.probe == "required_unit_decode_rejected" { metric.removeValue(forKey: "unit_code") }
        let empty = ["empty_evidence_rejected", "raw_zero_policy_display_preserved_unscored"].contains(row.probe)
        let ids = [sizeID.uuidString]
        let outerIDs = row.probe == "candidate_set_mismatch_rejected"
            ? [row.identities["unapproved_product_size_id"]!] : ids
        let object: [String: Any] = [
            "comparison_id": row.identities["comparison_id"]!, "created": true, "idempotent": false,
            "result_status": "PENDING", "authorization": authorization,
            "authorized_candidate_product_size_ids": outerIDs, "candidate_authority_fingerprint": row.id,
            "snapshot": [
                "snapshot_schema_version": 3,
                "reference_snapshot": ["closet_item_id": row.identities["reference_closet_item_id"]!],
                "authority_snapshot": [:], "input_snapshot": ["synthetic_requested_group": row.requestedGroup],
                // Keep one nonexcluded policy metric so exclusion rejection
                // reaches the production excluded-evidence guard, not an empty-policy error.
                "excluded_measurement_codes": excluded,
                "policy_snapshot": ["policy_code": "synthetic-canonical-probe", "policy_version": "matrix-v1",
                    "policy_checksum": "synthetic-only", "metrics": [
                        ["metric_mode": "CANONICAL", "fitmatch_measurement_code": excluded.isEmpty ? "chest_width" : "shoulder_width",
                         "weight": 2, "requirement_mode": "REQUIRED_ANY", "priority": 1, "is_active": true]]],
                "authorization_snapshot": authorization,
                "target_snapshot": ["product_id": row.identities["target_product_id"]!,
                    "variant_id": row.identities["target_variant_id"]!,
                    "authorized_candidate_product_size_ids": ids, "candidate_authority_fingerprint": row.id,
                    "classification_status": row.probe == "unconfirmed_target_rejected" ? "REVIEW_REQUIRED" : "CONFIRMED",
                    "garment_type_code": "tshirt", "candidates": [[
                        "product_size_id": sizeID.uuidString, "size_label": "synthetic-M",
                        "availability": ["status": "UNKNOWN"], "authorization": authorization,
                        "comparison_measurements": empty ? [] : [metric]]]]
            ]
        ]
        return try JSONDecoder().decode(VNextBeginComparisonDTO.self,
            from: JSONSerialization.data(withJSONObject: object))
    }
}
