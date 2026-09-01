import Foundation

extension Product {
    /// Recreates the retailer-fact envelope needed by the existing v4 runtime
    /// from a sourced SwiftData product. It deliberately carries stored facts
    /// only; no local canonical classification is promoted as retailer truth.
    func fitMatchDatabaseResolutionRequest() -> FitMatchProductResolutionRequest? {
        fitMatchParsedRetailerFacts()?.fitMatchDatabaseResolutionRequest()
    }

    func fitMatchProductObservationRequest(
        observedAt: Date = Date()
    ) -> FitMatchProductObservationRequest? {
        fitMatchParsedRetailerFacts()?.fitMatchProductObservationRequest(observedAt: observedAt)
    }

    /// Reuses only persisted retailer facts for a History recompare when the
    /// immutable History projection did not retain a browser URL.  The server
    /// still resolves current authority; this never derives a URL or local
    /// classification from historical meaning.
    func fitMatchStoredRetailerFactsForRecompare() -> ParsedProductInfo? {
        fitMatchParsedRetailerFacts()
    }

    private func fitMatchParsedRetailerFacts() -> ParsedProductInfo? {
        guard let externalProductID = productCode?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !externalProductID.isEmpty else { return nil }

        // A hydrated History projection can retain the stable retailer code
        // while an older local label is no longer the canonical Korean
        // presentation string.  Reuse that stored source fact only to route
        // the existing server resolver; it does not derive any classification
        // or browser URL from the historical Product.
        let resolutionSourceName: String
        switch sourcePlatformCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "uniqlo":
            resolutionSourceName = "유니클로 공식몰"
        case "musinsa":
            resolutionSourceName = "무신사"
        case "zara":
            resolutionSourceName = "ZARA 공식몰"
        default:
            resolutionSourceName = sourceName
        }

        let sourceURL = sourceURLString.flatMap(URL.init(string:))
            ?? URL(string: "https://fitmatch.invalid/products/\(externalProductID)")!
        let parsedSizes = sizes.map { size in
            ParsedProductSize(
                id: size.id,
                name: size.name,
                measurements: size.measurements,
                measurementRecords: size.measurementRecords.map { record in
                    ParsedMeasurement(
                        value: record.value,
                        unit: MeasurementUnit(rawValue: record.unitRawValue) ?? .centimeter,
                        measurementCode: record.measurementCode,
                        displayKind: record.displayKind ?? .unknown,
                        methodSource: record.methodSource,
                        methodProfile: record.methodProfile,
                        inputSource: MeasurementInputSource(rawValue: record.inputSourceRawValue)
                            ?? .importedSizeChart,
                        standardVersion: record.standardVersion,
                        mappingVersion: record.mappingVersion,
                        rawCode: record.rawCode,
                        rawLabel: record.rawLabel,
                        rawInfo: record.rawInfo,
                        rawValueText: record.rawValueText,
                        evidenceLevel: MeasurementEvidenceLevel(
                            rawValue: record.evidenceLevelRawValue
                        ) ?? .unknown,
                        semanticStatus: record.semanticStatus
                    )
                }
            )
        }
        let persistedRetailerFacts = FitMatchStoredRetailerFacts.decode(labelNames)
        var storedStructuredFacts = persistedRetailerFacts.structuredFacts
        if !persistedRetailerFacts.hasVersionedPayload,
           resolutionSourceName.localizedCaseInsensitiveContains("zara")
            || resolutionSourceName.localizedCaseInsensitiveContains("자라") {
            let zaraFacts = [
                "section": categoryDepth1Code,
                "family": categoryDepth2Name,
                "subfamily": categoryDepth3Name
            ]
            for (key, rawValue) in zaraFacts {
                guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else { continue }
                storedStructuredFacts[key] = value
            }
        }
        let metadata = ProductMetadata(
            styleNo: styleNo,
            externalVariantID: nil,
            externalProductReference: nil,
            variantSelectionMethod: nil,
            variantSelectionConfidence: nil,
            categoryMappingPolicyVersion: nil,
            englishName: englishName,
            brandCode: brandCode,
            brandEnglishName: brandEnglishName,
            brandLogoImageURLString: brandLogoImageURLString,
            brandNationName: brandNationName,
            sourceCategoryPath: sourceCategoryPath,
            sourceCategoryDepth1: sourceCategoryDepth1,
            sourceCategoryDepth2: sourceCategoryDepth2,
            sourceCategoryDepth3: sourceCategoryDepth3,
            sourceCategoryDepth4: sourceCategoryDepth4,
            baseCategoryFullPath: baseCategoryFullPath,
            categoryDepth1Code: categoryDepth1Code,
            categoryDepth1Name: categoryDepth1Name,
            categoryDepth2Code: categoryDepth2Code,
            categoryDepth2Name: categoryDepth2Name,
            categoryDepth3Code: categoryDepth3Code,
            categoryDepth3Name: categoryDepth3Name,
            categoryDepth4Code: categoryDepth4Code,
            categoryDepth4Name: categoryDepth4Name,
            structuredFacts: storedStructuredFacts,
            sizeType: sizeType,
            genderCodes: genderCodes.split(separator: ",").map(String.init),
            labelNames: persistedRetailerFacts.labelNames,
            imageURLStrings: imageURLStrings.split(whereSeparator: \.isNewline).map(String.init),
            normalPrice: normalPrice,
            salePrice: salePrice,
            finalPrice: finalPrice,
            currencyCode: currencyCode,
            discountRate: discountRate,
            isSale: isSale,
            isOutOfStock: isOutOfStock,
            stockStatusRawValue: stockStatusRawValue,
            isRestock: isRestock,
            isSoonOutOfStock: isSoonOutOfStock,
            isLimitedQuantity: isLimitedQuantity,
            reviewCount: reviewCount,
            reviewSatisfactionScore: reviewSatisfactionScore,
            seasonYear: seasonYear,
            season: season,
            checkedColorName: checkedColorName,
            checkedSizeName: checkedSizeName
        )
        let storedDetailCategory: ClosetDetailCategory
        if let normalizedProductTypeCode {
            storedDetailCategory = ClosetDetailCategory.fromTaxonomyCode(
                normalizedProductTypeCode
            )
        } else {
            storedDetailCategory = .other
        }
        return ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: sourceType,
            sourceName: resolutionSourceName,
            brandName: brand?.name ?? resolutionSourceName,
            productName: name,
            category: category,
            detailCategory: storedDetailCategory,
            sizes: parsedSizes,
            productID: externalProductID,
            imageURLString: imageURLString,
            price: finalPrice ?? salePrice ?? normalPrice,
            canonicalURLString: sourceURLString,
            sourceCategoryPath: sourceCategoryPath,
            sourceCategoryDepth1: sourceCategoryDepth1,
            sourceCategoryDepth2: sourceCategoryDepth2,
            sourceCategoryDepth3: sourceCategoryDepth3,
            sourceCategoryDepth4: sourceCategoryDepth4,
            productTargetGender: productTargetGender,
            productMetadata: metadata,
            measurementAvailability: sizes.isEmpty ? .unavailable : .actualMeasurements,
            parserProvenance: ProductParserProvenance(
                parserCode: "swiftdata_replay",
                parserVersion: "ios-server-authority-v1",
                fieldSources: [
                    "product_id": "stored_retailer_fact",
                    "product_name": "stored_retailer_fact",
                    "source_category_path": "stored_retailer_fact",
                    "source_category_codes": "stored_retailer_fact",
                    "sizes": "stored_retailer_fact"
                ]
            )
        )
    }
}
