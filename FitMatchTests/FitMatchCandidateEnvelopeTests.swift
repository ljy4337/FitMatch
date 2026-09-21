import Foundation
import Testing
@testable import FitMatch

struct FitMatchCandidateEnvelopeTests {
    private let productID = UUID()
    private let variantID = UUID()

    @Test func duplicateServerRowsRejectInsteadOfTrappingOrChoosingFirst() throws {
        let id = UUID()
        #expect(throws: FitMatchVNextContractError.conflictingProof("duplicate_server_identity")) {
            _ = try FitMatchVNextContractValidator.uniqueIdentityIndex(
                [(id, "first"), (id, "conflicting")], id: { $0.0 }
            )
        }
        let valid = try FitMatchVNextContractValidator.uniqueIdentityIndex(
            [(id, "exact")], id: { $0.0 }
        )
        #expect(valid[id]?.1 == "exact")
    }

    @Test func exactEnvelopePreservesServerOrderAndLegacyFacts() throws {
        let ids = [UUID(), UUID()]
        let response = try envelope(candidates: ids, blocked: [UUID()])
        try validate(response)
        #expect(response.candidates.map(\.closetItemID) == ids)
        #expect(response.candidates.allSatisfy { $0.isCurrentReference })
    }

    @Test func emptyCandidateListRemainsValid() throws {
        try validate(envelope(candidates: [], blocked: []))
    }

    @Test func differentProductIsRejected() throws {
        let response = try envelope(candidates: [], blocked: [])
        #expect(throws: FitMatchVNextContractError.conflictingProof("candidate_target_identity")) {
            try FitMatchVNextContractValidator.validateCandidateEnvelope(
                response, targetProductID: UUID(), targetVariantID: variantID
            )
        }
    }

    @Test func differentVariantIsRejected() throws {
        let response = try envelope(candidates: [], blocked: [])
        #expect(throws: FitMatchVNextContractError.conflictingProof("candidate_target_identity")) {
            try FitMatchVNextContractValidator.validateCandidateEnvelope(
                response, targetProductID: productID, targetVariantID: UUID()
            )
        }
    }

    @Test func duplicateSelectableCandidateIsRejected() throws {
        let id = UUID()
        let response = try envelope(candidates: [id, id], blocked: [])
        #expect(throws: FitMatchVNextContractError.conflictingProof("candidate_closet_identity")) {
            try validate(response)
        }
    }

    @Test func candidateCannotAlsoBeBlocked() throws {
        let id = UUID()
        let response = try envelope(candidates: [id], blocked: [id])
        #expect(throws: FitMatchVNextContractError.conflictingProof("candidate_closet_identity")) {
            try validate(response)
        }
    }

    @Test func duplicateBlockedCandidateIsRejected() throws {
        let id = UUID()
        let response = try envelope(candidates: [], blocked: [id, id])
        #expect(throws: FitMatchVNextContractError.conflictingProof("candidate_closet_identity")) {
            try validate(response)
        }
    }

    private func validate(_ response: VNextReferenceCandidatesDTO) throws {
        try FitMatchVNextContractValidator.validateCandidateEnvelope(
            response, targetProductID: productID, targetVariantID: variantID
        )
    }

    private func envelope(candidates: [UUID], blocked: [UUID]) throws -> VNextReferenceCandidatesDTO {
        func row(_ id: UUID, allowed: Bool) -> [String: Any] {
            ["closet_item_id": id.uuidString, "item_name": "계약 검사",
             "is_current_reference": true, "decision": allowed ? "MANUAL_EXTENDED" : "BLOCKED",
             "allowed": allowed, "mode": allowed ? "MANUAL_EXTENDED" : "NONE",
             "manual_explicit_required": allowed, "eligible_product_size_ids": [] as [String]]
        }
        let json: [String: Any] = [
            "target_product_id": productID.uuidString, "target_variant_id": variantID.uuidString,
            "candidates": candidates.map { row($0, allowed: true) },
            "blocked": blocked.map { row($0, allowed: false) },
            "status": candidates.isEmpty ? "NO_REFERENCE_CANDIDATE" : "READY"
        ]
        return try JSONDecoder().decode(VNextReferenceCandidatesDTO.self,
                                       from: JSONSerialization.data(withJSONObject: json))
    }
}
