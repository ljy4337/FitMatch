import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchLinkedClosetRoundTripTests {
    /// T1 and T7: an untouched linked size stays a retailer snapshot and keeps
    /// the exact runtime product / variant / size identities.
    @Test func linkedUntouchedSnapshotPreservesImportedRowsAndExactIdentity() throws {
        let fixture = linkedFixture()
        let sourceRecordIDs = fixture.size.measurementRecords.map(\.id)
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(
                linkedRequest(
                    fixture: fixture,
                    snapshot: .init(sourceSize: fixture.size),
                    explicitClassification: true
                )
            )

        #expect(submission.remoteRequest.productID == fixture.identity.productID)
        #expect(submission.remoteRequest.productVariantID == fixture.identity.productVariantID)
        #expect(submission.remoteRequest.productSizeID == fixture.identity.productSizeID)
        let rows = try encodedMeasurements(for: submission.remoteRequest)
        #expect(rows["chest_width"]?["value"] as? Double == 55)
        #expect(rows["shoulder_width"]?["value"] as? Double == 47)
        #expect(rows["back_length"]?["value"] as? Double == 70)
        #expect(rows["sleeve_length"]?["value"] as? Double == 23)
        #expect(rows.values.allSatisfy {
            $0["value_source"] as? String
                == FitMatchClosetMeasurementProvenance.retailerSnapshot
        })

        // The local source chart is shared product data and therefore never
        // receives a write during presentation or submission construction.
        #expect(fixture.size.chest == 55)
        #expect(fixture.size.measurementRecords.map(\.id) == sourceRecordIDs)
        #expect(fixture.size.measurementRecords.allSatisfy {
            $0.inputSourceRawValue == MeasurementInputSource.importedSizeChart.rawValue
        })
    }

    /// T2: changing only chest creates one USER_MANUAL row while all other
    /// size-chart rows are sent and preserved as retailer snapshots.
    @Test func linkedOneFieldEditKeepsMixedPerMeasurementProvenance() throws {
        let fixture = linkedFixture()
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        draft.setRawValue("56", for: .chest)
        let snapshot = try draft.snapshot()
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(
                linkedRequest(
                    fixture: fixture,
                    snapshot: snapshot,
                    explicitClassification: true
                )
            )
        let rows = try encodedMeasurements(for: submission.remoteRequest)

        #expect(rows["chest_width"]?["value"] as? Double == 56)
        #expect(rows["chest_width"]?["value_source"] as? String
            == FitMatchClosetMeasurementProvenance.userManual)
        for code in ["shoulder_width", "back_length", "sleeve_length"] {
            #expect(rows[code]?["value_source"] as? String
                == FitMatchClosetMeasurementProvenance.retailerSnapshot)
        }
        #expect(rows["shoulder_width"]?["value"] as? Double == 47)
        #expect(rows["back_length"]?["value"] as? Double == 70)
        #expect(rows["sleeve_length"]?["value"] as? Double == 23)

        // The correction is Closet-local; the API ProductSize still contains
        // the original imported fact for this and every other user.
        #expect(fixture.size.chest == 55)
        #expect(fixture.size.measurementRecords.first {
            $0.measurementCodeRawValue == "chest_width"
        }?.inputSourceRawValue == MeasurementInputSource.importedSizeChart.rawValue)
    }

    /// Multiple retailer facts may share a presentation axis. The selected
    /// category's existing exact definition chooses chest width here; changing
    /// it never converts the independent circumference fact into a user value.
    @Test func linkedEditUsesExactMeasurementDefinitionWithoutCollapsingSharedAxisFacts() throws {
        let fixture = linkedFixture()
        fixture.size.measurementRecords.append(importedRecord(
            value: 110,
            code: .chestCircumferenceGarment,
            rawCode: "chest_circumference",
            kind: .chest,
            productSize: fixture.size
        ))
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )

        #expect(draft.rawValue(for: .chest) == "55")
        draft.setRawValue("56", for: .chest)
        let snapshot = try draft.snapshot()
        let values = Dictionary(uniqueKeysWithValues: snapshot.measurementRecords.map {
            ($0.measurementCode, ($0.value, $0.valueSource))
        })
        #expect(values["chest_width"]?.0 == 56)
        #expect(values["chest_width"]?.1 == FitMatchClosetMeasurementProvenance.userManual)
        #expect(values["chest_circumference"]?.0 == 110)
        #expect(values["chest_circumference"]?.1
            == FitMatchClosetMeasurementProvenance.retailerSnapshot)
    }

    /// T3: a missing definition can be added through the selected FitMatch
    /// category without reclassifying or rewriting existing retailer facts.
    @Test func linkedMissingMeasurementAdditionPreservesImportedRows() throws {
        let fixture = linkedFixture()
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .bottom,
            detailCategory: .longPants,
            gender: .men
        )
        draft.setRawValue("24", for: .hem)
        let snapshot = try draft.snapshot()
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(
                linkedRequest(
                    fixture: fixture,
                    snapshot: snapshot,
                    category: .bottom,
                    categoryCode: "bottoms",
                    detailCategory: .longPants,
                    detailCategoryCode: "long_pants",
                    explicitClassification: true
                )
            )
        let rows = try encodedMeasurements(for: submission.remoteRequest)
        let hemCode = try #require(FitMatchCanonicalMeasurementCode.canonicalCode(
            forTransportRawCode: ManualMeasurementRecordFactory.fitmatchCode(
                for: .hem,
                category: .bottom
            ).rawValue
        ))

        #expect(rows[hemCode]?["value"] as? Double == 24)
        #expect(rows[hemCode]?["value_source"] as? String
            == FitMatchClosetMeasurementProvenance.userManual)
        for code in ["chest_width", "shoulder_width", "back_length", "sleeve_length"] {
            #expect(rows[code]?["value_source"] as? String
                == FitMatchClosetMeasurementProvenance.retailerSnapshot)
        }
    }

    /// T4: an RPC list DTO can hydrate the mixed snapshot more than once
    /// without changing either the value or each record's provenance.
    @Test func linkedRoundTripHydrationRestoresUserAndRetailerRowsIndependently() throws {
        let fixture = linkedFixture()
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        draft.setRawValue("56", for: .chest)
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(
                linkedRequest(
                    fixture: fixture,
                    snapshot: try draft.snapshot(),
                    explicitClassification: true
                )
            )
        let rows = try encodedMeasurements(for: submission.remoteRequest)
        let dto = try linkedListDTO(
            clientItemID: submission.remoteRequest.clientItemID,
            identity: fixture.identity,
            rows: rows.map { code, row in
                (code, try! #require(row["value"] as? Double),
                 try! #require(row["value_source"] as? String))
            }
        )
        let serverRecord = FitMatchSupabaseDomainClient.mapClosetItem(dto)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let coordinator = FitMatchClosetSyncCoordinator()

        let hydrated = try coordinator.projectAuthoritativeRegistration(
            serverRecord,
            expected: submission.remoteRequest,
            acceptedClosetItemID: serverRecord.closetItemID,
            modelContext: context
        )
        let rehydrated = try coordinator.projectAuthoritativeRegistration(
            serverRecord,
            expected: submission.remoteRequest,
            acceptedClosetItemID: serverRecord.closetItemID,
            modelContext: context
        )

        #expect(hydrated === rehydrated)
        #expect(rehydrated.chest == 56)
        #expect(rehydrated.shoulder == 47)
        #expect(rehydrated.totalLength == 70)
        #expect(rehydrated.sleeveLength == 23)
        let chest = try #require(rehydrated.measurementRecords.first {
            $0.measurementCodeRawValue == "chest_width"
        })
        #expect(chest.inputSourceRawValue == MeasurementInputSource.userMeasured.rawValue)
        #expect(chest.rawCode == "source_chest_width")
        for code in ["shoulder_width", "back_length", "sleeve_length"] {
            let row = try #require(rehydrated.measurementRecords.first {
                $0.measurementCodeRawValue == code
            })
            #expect(row.inputSourceRawValue == MeasurementInputSource.importedSizeChart.rawValue)
        }
    }

    /// T5: a user's Closet category wins even when the linked global Product
    /// remains classified as a top; no global Product field is changed.
    @Test func linkedExplicitClosetCategoryUsesPersonalOverrideWithoutChangingProduct() throws {
        let fixture = linkedFixture()
        let originalCategory = fixture.product.category
        let originalFamily = fixture.product.garmentTypeRawValue
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(
                linkedRequest(
                    fixture: fixture,
                    snapshot: .init(sourceSize: fixture.size),
                    category: .bottom,
                    categoryCode: "bottoms",
                    detailCategory: .longPants,
                    detailCategoryCode: "long_pants",
                    explicitClassification: true
                )
            )
        let override = try #require(submission.remoteRequest.override)
        let payload = try decodedJSON(
            FitMatchSupabaseDomainClient.encodedVNextClosetPayload(submission.remoteRequest)
        )
        let nested = try #require(payload["closet_classification_override"] as? [String: Any])

        #expect(override.categoryCode == "bottoms")
        #expect(override.detailCode == "long_pants")
        #expect(nested["category_code"] as? String == "bottoms")
        #expect(payload["garment_type_code"] as? String == "pants")
        #expect(fixture.product.category == originalCategory)
        #expect(fixture.product.garmentTypeRawValue == originalFamily)
    }

    /// T8: two local Closet items can use the same ProductSize source without
    /// one user's correction altering that source or the other user's copy.
    @Test func linkedClosetSnapshotDoesNotMutateSharedProductOrAnotherClosetItem() throws {
        let fixture = linkedFixture()
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        draft.setRawValue("56", for: .chest)
        let corrected = try draft.snapshot()
        let first = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: fixture.product,
            sourceSize: fixture.size,
            measurementSnapshot: corrected,
            authorityProduct: fixture.product,
            brandName: "Fixture",
            gender: .men,
            genderCode: "MEN",
            productName: fixture.product.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "short_sleeve",
            isRepresentative: false,
            didExplicitlyChangeClassification: true,
            didExplicitlySelectClosetClassification: true
        )
        let second = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: fixture.product,
            sourceSize: fixture.size,
            measurementSnapshot: .init(sourceSize: fixture.size),
            authorityProduct: fixture.product,
            brandName: "Fixture",
            gender: .men,
            genderCode: "MEN",
            productName: fixture.product.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "short_sleeve",
            isRepresentative: false,
            didExplicitlyChangeClassification: true,
            didExplicitlySelectClosetClassification: true
        )

        #expect(first.chest == 56)
        #expect(second.chest == 55)
        #expect(fixture.size.chest == 55)
        #expect(fixture.product.sizes.first === fixture.size)
        #expect(first.measurementRecords.first {
            $0.measurementCodeRawValue == "chest_width"
        }?.inputSourceRawValue == MeasurementInputSource.userMeasured.rawValue)
        #expect(second.measurementRecords.first {
            $0.measurementCodeRawValue == "chest_width"
        }?.inputSourceRawValue == MeasurementInputSource.importedSizeChart.rawValue)
    }

    /// T9: invalid numbers, units, and manual ranges are rejected before an
    /// RPC is encoded.  Nothing is silently treated as a successful save.
    @Test func linkedPayloadRejectsInvalidMeasurementValuesBeforeRPC() throws {
        for invalidValue in [Double.nan, Double.infinity] {
            do {
                _ = try FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
                    manualRequest(record: measurementRecord(value: invalidValue))
                )
                Issue.record("Non-finite measurement unexpectedly encoded")
            } catch let error as FitMatchClosetPayloadContractError {
                #expect(error == .invalidMeasurementValue(code: "chest_width"))
            }
        }

        do {
            _ = try FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
                manualRequest(record: measurementRecord(value: 55, unit: "in"))
            )
            Issue.record("Invalid measurement unit unexpectedly encoded")
        } catch let error as FitMatchClosetPayloadContractError {
            #expect(error == .invalidMeasurementUnit(code: "chest_width", unit: "in"))
        }

        do {
            _ = try FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
                manualRequest(record: measurementRecord(value: 10_000))
            )
            Issue.record("Out-of-range manual measurement unexpectedly encoded")
        } catch let error as FitMatchClosetPayloadContractError {
            #expect(error == .invalidUserMeasurementRange(code: "chest_width"))
        }
    }

    /// T10: the direct-input path remains a USER_MANUAL transport payload.
    @Test func directManualClosetTransportStillUsesUserProvenance() throws {
        let encoded = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            manualRequest(record: measurementRecord(value: 51))
        ))
        let row = try #require((encoded["measurements"] as? [[String: Any]])?.first)
        #expect(row["fitmatch_measurement_code"] as? String == "chest_width")
        #expect(row["value_source"] as? String
            == FitMatchClosetMeasurementProvenance.userManual)
    }

    private func linkedFixture() -> (
        product: Product,
        size: ProductSize,
        identity: FitMatchClosetRegistrationServerIdentity
    ) {
        let product = Product(
            name: "API 티셔츠",
            category: .top,
            productCode: "fixture-api-shirt",
            sourceURLString: "https://www.musinsa.com/products/fixture-api-shirt",
            metadata: ProductMetadata(
                sourceCategoryPath: "상의 > 반팔 티셔츠",
                genderCodes: ["MEN"]
            ),
            sourceType: .marketplace,
            sourceName: "무신사",
            source: .catalog
        )
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(.serverConfirmed)
        let size = ProductSize(
            name: "M",
            measurements: .init(
                shoulder: 47,
                chest: 55,
                totalLength: 70,
                sleeveLength: 23
            ),
            product: product
        )
        product.sizes = [size]
        size.measurementRecords = [
            importedRecord(
                value: 55,
                code: .chestWidthPitToPit,
                rawCode: "chest_width",
                kind: .chest,
                productSize: size
            ),
            importedRecord(
                value: 47,
                code: .shoulderWidthSeamToSeam,
                rawCode: "shoulder_width",
                kind: .shoulder,
                productSize: size
            ),
            importedRecord(
                value: 70,
                code: .bodyLengthBackNeckToHem,
                rawCode: "back_length",
                kind: .totalLength,
                productSize: size
            ),
            importedRecord(
                value: 23,
                code: .sleeveShoulderSeamToCuff,
                rawCode: "sleeve_length",
                kind: .sleeveLength,
                productSize: size
            )
        ]
        return (
            product,
            size,
            .init(
                productID: UUID(),
                productVariantID: UUID(),
                productSizeID: UUID()
            )
        )
    }

    private func importedRecord(
        value: Double,
        code: MeasurementCode,
        rawCode: String,
        kind: MeasurementKind,
        productSize: ProductSize
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            measurementCodeRawValue: rawCode,
            displayKind: kind.displayKind,
            methodSource: "musinsa",
            methodProfile: "size_chart",
            inputSource: .importedSizeChart,
            standardVersion: nil,
            mappingVersion: "fixture_verified_mapping",
            rawCode: rawCode,
            rawLabel: kind.title,
            rawInfo: "fixture API size chart",
            rawValueText: String(value),
            evidenceLevel: .officialText,
            semanticStatus: .mapped,
            productSize: productSize
        )
    }

    private func linkedRequest(
        fixture: (product: Product, size: ProductSize, identity: FitMatchClosetRegistrationServerIdentity),
        snapshot: FitMatchClosetMeasurementSnapshot,
        category: ClothingCategory = .top,
        categoryCode: String = "tops",
        detailCategory: ClosetDetailCategory = .shortSleeve,
        detailCategoryCode: String = "short_sleeve",
        explicitClassification: Bool
    ) -> FitMatchComparedProductClosetRegistration.SaveRequest {
        .init(
            clientItemID: UUID(),
            product: fixture.product,
            selectedSize: fixture.size,
            measurementSnapshot: snapshot,
            serverIdentity: fixture.identity,
            hasMeasurementEligibilityProof: true,
            activeClosetItems: [],
            brandName: "Fixture",
            gender: .men,
            genderCode: "MEN",
            productName: fixture.product.name,
            category: category,
            categoryCode: categoryCode,
            detailCategory: detailCategory,
            detailCategoryCode: detailCategoryCode,
            isRepresentative: false,
            didExplicitlyChangeClassification: explicitClassification,
            didExplicitlySelectClosetClassification: explicitClassification
        )
    }

    private func encodedMeasurements(
        for request: FitMatchUpsertClosetItemRequest
    ) throws -> [String: [String: Any]] {
        let json = try decodedJSON(
            FitMatchSupabaseDomainClient.encodedVNextClosetPayload(request)
        )
        let rows = try #require(json["measurements"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: try rows.map { row in
            (try #require(row["fitmatch_measurement_code"] as? String), row)
        })
    }

    private func linkedListDTO(
        clientItemID: UUID,
        identity: FitMatchClosetRegistrationServerIdentity,
        rows: [(String, Double, String)]
    ) throws -> VNextClosetItemDTO {
        let object: [String: Any] = [
            "id": UUID().uuidString,
            "client_item_id": clientItemID.uuidString,
            "product_id": identity.productID.uuidString,
            "product_variant_id": identity.productVariantID.uuidString,
            "product_size_id": identity.productSizeID.uuidString,
            "item_name": "API 티셔츠",
            "brand_name": "Fixture",
            "image_url": NSNull(),
            "product_url": "https://www.musinsa.com/products/fixture-api-shirt",
            "size_label": "M",
            "audience_code": "MEN",
            "category_code": "tops",
            "garment_type_code": "tshirt",
            "sleeve_length_code": "short_sleeve",
            "lower_length_code": NSNull(),
            "body_length_code": NSNull(),
            "classification_source": "USER_EXPLICIT",
            "classification_fingerprint": "fixture",
            "classification_resolver_version": "fixture-v1",
            "source_code": "musinsa",
            "source_product_key": "fixture-api-shirt",
            "source_category_path": "상의 > 반팔 티셔츠",
            "is_reference": false,
            "fit_preference_code": "regular",
            "notes": NSNull(),
            "satisfaction": 3,
            "created_at": "2026-09-08T00:00:00Z",
            "updated_at": "2026-09-08T00:00:00Z",
            "measurements": rows.map { code, value, source in
                [
                    "fitmatch_measurement_code": code,
                    "value": value,
                    "unit_code": "cm",
                    "value_source": source,
                    "source_measurement_code": "source_\(code)",
                    "raw_label_snapshot": code
                ]
            }
        ]
        return try JSONDecoder().decode(
            VNextClosetItemDTO.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func measurementRecord(
        value: Double,
        unit: String = "cm"
    ) -> FitMatchClosetMeasurementRecordPayload {
        .init(
            value: value,
            unit: unit,
            measurementCode: "chest_width",
            displayKind: MeasurementDisplayKind.chest.rawValue,
            methodSource: "fitmatch",
            methodProfile: FitMatchMeasurementStandard.version,
            inputSource: MeasurementInputSource.userMeasured.rawValue,
            standardVersion: FitMatchMeasurementStandard.version,
            mappingVersion: "manual_measurement_mapping_v1",
            rawCode: "chest_width",
            rawLabel: "가슴",
            rawInfo: nil,
            rawValueText: String(value),
            evidenceLevel: MeasurementEvidenceLevel.fitmatchDefined.rawValue,
            semanticStatus: MeasurementSemanticStatus.mapped.rawValue,
            valueSource: FitMatchClosetMeasurementProvenance.userManual
        )
    }

    private func manualRequest(
        record: FitMatchClosetMeasurementRecordPayload
    ) -> FitMatchUpsertClosetItemRequest {
        let item = FitMatchClosetItemPayload(
            productName: "직접 측정 티셔츠",
            brand: "Fixture",
            sizeName: "M",
            genderCode: "MEN",
            source: "manual",
            categoryCode: "tops",
            detailCode: "short_sleeve",
            familyCode: "tshirt",
            lengthCode: "short_sleeve",
            bodyLengthCode: nil,
            sourceCategoryPath: nil,
            productURL: nil,
            imageURL: nil,
            measurements: ["chest_width": record.value],
            measurementRecords: [record],
            fitMemo: "",
            fitPreferenceCode: "regular",
            satisfaction: 3,
            isReference: false,
            classificationVersion: nil,
            clientSnapshot: [:],
            clientCreatedAt: "2026-09-08T00:00:00Z",
            clientUpdatedAt: "2026-09-08T00:00:00Z"
        )
        return FitMatchUpsertClosetItemRequest(
            clientItemID: UUID(),
            item: item,
            productID: nil,
            productSizeID: nil,
            override: nil
        )
    }

    private func decodedJSON(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
