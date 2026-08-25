import Testing
@testable import FitMatch

@Suite(.serialized)
struct MeasurementPolicyConsolidationTests {
    @Test
    func sourceIdentityPrefersCanonicalProductMetadata() throws {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        )
        let product = Product(
            name: "신규 쇼핑몰 상품",
            category: .bottom,
            sourceName: "직접 입력",
            sizes: [size]
        )
        product.sourcePlatformCode = "futuremerchant"
        size.product = product
        let record = measurement(
            value: 40,
            code: .waistWidthEdgeToEdge,
            kind: .waist,
            methodSource: "html",
            rawCode: "waist",
            productSize: size
        )

        let identity = try #require(record.sourceIdentity)
        #expect(identity.code == "futuremerchant")
        #expect(identity.resolution == .canonicalProductSource)
    }

    @Test
    func legacyMethodSourceFallbackIsMerchantAgnosticAndUnknownChannelsFailClosed() throws {
        let future = try #require(MeasurementSourceIdentity.resolve(
            methodSource: "futuremerchant_official_chart"
        ))
        let local = try #require(MeasurementSourceIdentity.resolve(
            methodSource: "manual_product_size_entry"
        ))

        #expect(future.code == "futuremerchant")
        #expect(future.resolution == .legacyMethodSource)
        #expect(local.code == "fitmatch")
        #expect(local.resolution == .legacyLocalFallback)
        #expect(MeasurementSourceIdentity.resolve(methodSource: "html") == nil)
        #expect(MeasurementSourceIdentity.resolve(methodSource: "actual-size") == nil)
        #expect(MeasurementSourceIdentity.resolve(methodSource: "unknown") == nil)
    }

    @Test
    func canonicalNewMerchantSupportsVerifiedSameSourceRawComparisonWithoutEngineChanges() {
        let fixture = bottomFixture(sourceCode: "futuremerchant", methodSource: "html")

        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.reference,
            productCategory: .bottom,
            productDetailCategory: .slacks
        )

        #expect(result.status == .confirmed)
        #expect(result.comparedKinds == [.waist, .hip])
        #expect(result.score == 92)
        #expect(result.comparedItems.first { $0.kind == .waist }?.signedDifference == 2)
        #expect(result.comparedItems.first { $0.kind == .hip }?.signedDifference == 1)
    }

    @Test
    func unknownSourceDoesNotGainSameSourceRawCompatibility() {
        let fixture = bottomFixture(sourceCode: nil, methodSource: "html")

        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.reference,
            productCategory: .bottom,
            productDetailCategory: .slacks
        )

        #expect(result.status == .insufficientEvidence)
        #expect(result.comparedKinds == [.hip])
        #expect(result.exclusions.contains {
            $0.kind == .waist && $0.reason == .incompatibleMeasurementCode
        })
    }

    @Test
    func verifiedZARAUpperCodesCompareCrossSourceWithoutMerchantSpecificEngineLogic() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 40, chest: 46, totalLength: 0, sleeveLength: 17)
        )
        let product = Product(
            name: "ZARA 상의",
            category: .top,
            sourceName: "ZARA 공식몰",
            sizes: [size]
        )
        product.sourcePlatformCode = "zara"
        size.product = product

        let reference = UserFit(
            sourceName: "무신사",
            brandName: "테스트",
            productName: "기준 상의",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 39, chest: 45, totalLength: 0, sleeveLength: 17),
            fitMemo: "",
            satisfaction: 3
        )
        reference.sourcePlatformCode = "musinsa"

        size.measurementRecords = [
            measurement(value: 46, code: .chestWidthPitToPit, kind: .chest, methodSource: "zara", rawCode: "zone-name-chest", productSize: size),
            measurement(value: 40, code: .shoulderWidthSeamToSeam, kind: .shoulder, methodSource: "zara", rawCode: "zone-name-back-width", productSize: size),
            measurement(value: 17, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, methodSource: "zara", rawCode: "zone-name-sleeve-length", productSize: size)
        ]
        reference.measurementRecords = [
            measurement(value: 45, code: .chestWidthPitToPit, kind: .chest, methodSource: "musinsa", rawCode: "가슴단면", userFit: reference),
            measurement(value: 39, code: .shoulderWidthSeamToSeam, kind: .shoulder, methodSource: "musinsa", rawCode: "어깨너비", userFit: reference),
            measurement(value: 17, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, methodSource: "musinsa", rawCode: "소매길이", userFit: reference)
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: reference,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.status == .confirmed)
        #expect(Set(result.comparedKinds) == Set([.shoulder, .chest, .sleeveLength]))
        #expect(result.score == 95)
    }

    @Test
    func embeddedFallbackPolicyKeepsProductionWeightsAndExposesVersion() {
        let engine = MeasurementComparisonEngine()
        let snapshot = engine.policySnapshot
        let top = snapshot.policy(for: .top, detailCategory: .shortSleeve)
        let outer = snapshot.policy(for: .outer, detailCategory: .jacket)
        let bottom = snapshot.policy(for: .bottom, detailCategory: .slacks)

        #expect(engine.activePolicySource == .embeddedFallback)
        #expect(engine.activePolicyVersion == "fitmatch-production-measurement-policy-2026-08-24-v1")
        #expect(top.weights == [.shoulder: 1.2, .chest: 1.4, .totalLength: 1.0, .sleeveLength: 0.2])
        #expect(top.minimumComparableCount == 2)
        #expect(top.requiredAnyKinds == [.shoulder, .chest])
        #expect(outer.weights == [.shoulder: 1.1, .chest: 1.5, .totalLength: 0.8, .sleeveLength: 1.0, .hem: 0.6])
        #expect(outer.requiredAllKinds == [.chest])
        #expect(bottom.weights == [.waist: 1.4, .hip: 1.2, .thigh: 0.9, .rise: 0.7, .hem: 0.6, .totalLength: 1.0])
        #expect(bottom.minimumRequiredKindCount == 2)
    }

    private func bottomFixture(
        sourceCode: String?,
        methodSource: String
    ) -> (size: ProductSize, reference: UserFit) {
        let size = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0,
                waist: 80, hip: 51
            )
        )
        let product = Product(
            name: "후보 바지",
            category: .bottom,
            sourceName: "직접 입력",
            sizes: [size]
        )
        product.sourcePlatformCode = sourceCode
        size.product = product

        let reference = UserFit(
            sourceName: "직접 입력",
            brandName: "테스트",
            productName: "기준 바지",
            category: .bottom,
            detailCategory: .slacks,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0,
                waist: 78, hip: 50
            ),
            fitMemo: "",
            satisfaction: 3
        )
        reference.sourcePlatformCode = sourceCode

        size.measurementRecords = [
            measurement(
                value: 80,
                code: .waistWidthEdgeToEdge,
                kind: .waist,
                methodSource: methodSource,
                rawCode: "waist",
                productSize: size
            ),
            measurement(
                value: 51,
                code: .hipWidthAtWidest,
                kind: .hip,
                methodSource: methodSource,
                rawCode: "hip",
                productSize: size
            )
        ]
        reference.measurementRecords = [
            measurement(
                value: 78,
                code: .waistCircumferenceGarment,
                kind: .waist,
                methodSource: methodSource,
                rawCode: "waist",
                userFit: reference
            ),
            measurement(
                value: 50,
                code: .hipWidthAtWidest,
                kind: .hip,
                methodSource: methodSource,
                rawCode: "hip",
                userFit: reference
            )
        ]
        return (size, reference)
    }

    private func measurement(
        value: Double,
        code: MeasurementCode,
        kind: MeasurementKind,
        methodSource: String,
        rawCode: String,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind.displayKind,
            methodSource: methodSource,
            methodProfile: "official_bottom_v1",
            inputSource: .importedSizeChart,
            mappingVersion: "verified_mapping_v1",
            rawCode: rawCode,
            rawLabel: rawCode,
            rawValueText: String(value),
            evidenceLevel: .officialText,
            semanticStatus: .mapped,
            productSize: productSize,
            userFit: userFit
        )
    }
}
