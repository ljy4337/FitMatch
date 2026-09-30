import Foundation
import Testing
@testable import FitMatch

@Suite("Audience Mapping P0 Regression")
struct FitMatchAudienceMappingRegressionTests {
    @Test func canonicalAudienceContractDoesNotCreateImplicitGeneric() {
        let matrix: [(String?, String)] = [
            ("M", "MEN"), ("MEN", "MEN"), ("MALE", "MEN"),
            ("W", "WOMEN"), ("WOMEN", "WOMEN"), ("FEMALE", "WOMEN"),
            ("M,W", "UNISEX"), ("UNISEX", "UNISEX"),
            ("KID", "KIDS"), ("KIDS", "KIDS"), ("BABY", "BABY"),
            (nil, "UNKNOWN"), ("", "UNKNOWN"), ("GENERIC", "UNKNOWN")
        ]
        for (raw, expected) in matrix {
            #expect(FitMatchCanonicalAudience.code(from: raw) == expected)
        }
        #expect(FitMatchCanonicalAudience.code(from: ["M", "W"]) == "UNISEX")
        #expect(FitMatchCanonicalAudience.code(from: ["MEN", "KIDS"]) == "UNKNOWN")
    }

    @Test func explicitUniqloUnisexProductsPreserveOfficialAudienceAnd58395Scope() throws {
        for (productID, productName) in [
            ("E422992", "크루넥T"),
            ("E487962", "박시크롭T")
        ] {
            let metadata = parsedUniqloMetadata(
                productID: productID,
                productName: productName,
                genderName: "unisex",
                genderCategory: "UNISEX"
            )
            let request = try #require(
                metadata.parsedProductInfo(sizes: [Self.size])
                    .fitMatchDatabaseResolutionRequest()
            )

            #expect(metadata.productMetadata.genderCodes == ["UNISEX"])
            #expect(request.audience == "UNISEX")
            #expect(request.sourceCategoryCodes == ["57967", "58039", "58395"])
            #expect(request.sourceCategoryPath == Self.path)
        }
    }

    @Test func same58395MenProductsRemainCanonicalMenRequests() throws {
        for productID in ["E455365", "E465187", "E475376", "E487898", "E489013"] {
            let metadata = parsedUniqloMetadata(
                productID: productID,
                productName: "대표 MEN 반팔T",
                genderName: "men",
                genderCategory: "MEN"
            )
            let request = try #require(
                metadata.parsedProductInfo(sizes: [Self.size])
                    .fitMatchDatabaseResolutionRequest()
            )
            #expect(request.audience == "MEN")
            #expect(request.sourceCategoryCodes?.last == "58395")
            #expect(request.sourceCategoryPath == Self.path)
        }
    }

    @Test func absentAndMixedAudienceFailClosedAsUnknownOrUnisex() {
        let unknown = FitMatchProductResolutionRequest(
            source: "uniqlo",
            externalProductID: "future-unknown",
            productName: "Future product",
            sourceCategoryPath: Self.path,
            audience: nil,
            sourceCategoryCodes: ["58395"]
        )
        let mixed = FitMatchProductResolutionRequest(
            source: "uniqlo",
            externalProductID: "future-unisex",
            productName: "Future product",
            sourceCategoryPath: Self.path,
            audience: "M,W",
            sourceCategoryCodes: ["58395"]
        )
        let attemptedGeneric = FitMatchProductResolutionRequest(
            source: "uniqlo",
            externalProductID: "future-generic",
            productName: "Future product",
            sourceCategoryPath: Self.path,
            audience: "GENERIC",
            sourceCategoryCodes: ["58395"]
        )

        #expect(unknown.audience == "UNKNOWN")
        #expect(mixed.audience == "UNISEX")
        #expect(attemptedGeneric.audience == "UNKNOWN")
    }

    @Test func classificationReviewAndNotComparableUseDistinctHeadlines() throws {
        let review = authority(status: .reviewRequired)
        let excluded = authority(status: .notComparable)

        #expect(
            FitMatchIOSServerAuthorityState.reviewRequired(review)
                .productLoadFailureTitle == "이 상품은 분류 확인이 필요해요."
        )
        #expect(
            FitMatchIOSServerAuthorityState.notComparable(excluded)
                .productLoadFailureTitle == "이 상품은 비교할 수 없는 상품이에요."
        )
        #expect(
            FitMatchIOSServerAuthorityState.unavailable("network")
                .productLoadFailureTitle == nil
        )
    }

    private func parsedUniqloMetadata(
        productID: String,
        productName: String,
        genderName: String,
        genderCategory: String
    ) -> UniqloProductMetadata {
        let html = """
        <script type="application/ld+json">
        [{"@type":"Product","name":"\(productName)","brand":{"name":"UNIQLO"}}]
        </script>
        <script>
        window.__PRELOADED_STATE__ = {"entity":{"pdpEntity":{
          "\(productID)-000": {"product":{
            "productId":"\(productID)-000",
            "genderName":"\(genderName)",
            "genderCategory":"\(genderCategory)",
            "breadcrumbs":{
              "gender":{"id":"MEN","locale":"MEN"},
              "class":{"id":"57967","locale":"티셔츠 & 스웨트셔츠 & UT"},
              "category":{"id":"58039","locale":"티셔츠 (반팔 & 긴팔)"},
              "subcategory":{"id":"58395","locale":"반팔"}
            }
          }}
        }}};
        </script>
        """
        let resolved = ResolvedUniqloURL(
            originalURL: URL(
                string: "https://www.uniqlo.com/kr/ko/products/\(productID)-000/00"
            )!,
            resolvedURL: URL(
                string: "https://www.uniqlo.com/kr/ko/products/\(productID)-000/00"
            )!,
            productID: productID,
            goodsID: String(productID.dropFirst()),
            apiColorCode: "000",
            imageColorCode: "00",
            productIDWithColorCode: "\(productID)-000",
            html: html
        )
        return UniqloProductMetadataParser().parse(resolved: resolved)
    }

    private func authority(
        status: FitMatchServerProductAuthorityStatus
    ) -> FitMatchServerProductAuthority {
        let productID = UUID()
        let classification = FitMatchDatabaseClassification(
            classificationID: UUID(),
            categoryCode: nil,
            detailCode: nil,
            familyCode: nil,
            lengthCode: nil,
            bodyLengthCode: nil,
            status: status.rawValue,
            method: status == .notComparable ? "structured_exclusion" : "unknown",
            confidence: nil,
            requiresUserConfirmation: status == .reviewRequired,
            taxonomyPolicyVersion: "db-classifier-2026-08-26-final",
            decisionVersion: nil
        )
        return FitMatchServerProductAuthority(
            status: status,
            productID: productID,
            classification: classification,
            runtime: FitMatchProductRuntimeResponse(
                runtimeState: status == .notComparable
                    ? "not_comparable"
                    : "classification_required",
                comparisonReady: false,
                product: FitMatchRuntimeProduct(
                    productID: productID,
                    source: "uniqlo",
                    externalProductID: "fixture",
                    productName: "Fixture",
                    canonicalURL: nil,
                    audience: "UNISEX",
                    sourceCategoryPath: Self.path,
                    sourceCategoryCodes: ["58395"],
                    imageURL: nil,
                    lifecycleStatus: "active",
                    inputFingerprint: "fixture"
                ),
                classification: classification,
                variants: []
            )
        )
    }

    private static let path =
        "티셔츠 & 스웨트셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 반팔"
    private static let size = ParsedProductSize(
        name: "M",
        measurements: GarmentMeasurements(
            shoulder: 46,
            chest: 52,
            totalLength: 68,
            sleeveLength: 22
        )
    )
}
