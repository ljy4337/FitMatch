import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchClosetTransportContractTests {
    @Test func manualFactoryRecordsEncodeVerifiedCanonicalCodesForSharedUpsertAndUpdatePayload() throws {
        let item = manualItem()
        let factoryRecords = ManualMeasurementRecordFactory.records(
            source: .fitmatchMeasured,
            musinsaSleeveMethod: .setIn,
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 51,
                totalLength: 69,
                sleeveLength: 0
            ),
            rawValues: [.chest: "51", .totalLength: "69"],
            rawLabels: [:],
            kinds: [.chest, .totalLength],
            otherSourceName: "",
            userFit: item
        )
        let editedBackLength = GarmentMeasurementRecord(
            value: 70,
            measurementCode: .bodyLengthBackNeckToHem,
            displayKind: .totalLength,
            methodSource: "fitmatch",
            methodProfile: "fitmatch_standard_v1",
            inputSource: .userMeasured,
            standardVersion: FitMatchMeasurementStandard.version,
            mappingVersion: "manual_measurement_mapping_v1",
            rawLabel: "뒷기장",
            evidenceLevel: .fitmatchDefined,
            semanticStatus: .mapped,
            userFit: item
        )
        item.measurementRecords = factoryRecords + [editedBackLength]

        let sharedItemPayload = FitMatchClosetSyncCoordinator().payload(for: item)
        let request = FitMatchUpsertClosetItemRequest(
            clientItemID: item.id,
            item: sharedItemPayload,
            productID: nil,
            productSizeID: nil,
            override: nil
        )

        // `closetPayload` is the common adapter reached by both upsert and
        // update before either RPC is issued. Encode it twice to assert the
        // real JSON contract rather than rebuilding a test-side dictionary.
        let upsertJSON = try decodedJSON(
            FitMatchSupabaseDomainClient.encodedVNextClosetPayload(request)
        )
        let updateJSON = try decodedJSON(
            FitMatchSupabaseDomainClient.encodedVNextClosetPayload(request)
        )
        let upsertMeasurements = try #require(upsertJSON["measurements"] as? [[String: Any]])
        let updateMeasurements = try #require(updateJSON["measurements"] as? [[String: Any]])
        let upsertCodes = Set(upsertMeasurements.compactMap {
            $0["fitmatch_measurement_code"] as? String
        })
        let updateCodes = Set(updateMeasurements.compactMap {
            $0["fitmatch_measurement_code"] as? String
        })

        #expect(upsertCodes == Set(["chest_width", "total_length", "back_length"]))
        #expect(updateCodes == upsertCodes)
        #expect(!upsertCodes.contains("chest_width_pit_to_pit"))
        #expect(!upsertCodes.contains("body_length_back_neck_to_hem"))
        // A rejected/accepted transport must never mutate the user's draft.
        #expect(item.measurementRecords.map(\.measurementCodeRawValue) == [
            MeasurementCode.chestWidthPitToPit.rawValue,
            MeasurementCode.bodyLengthHPSToHemFront.rawValue,
            MeasurementCode.bodyLengthBackNeckToHem.rawValue
        ])
    }

    @Test func unmappableManualPositiveMeasurementFailsBeforePayloadRPCAndKeepsDraft() throws {
        let item = manualItem()
        let futureLookingManualRecord = GarmentMeasurementRecord(
            value: 12,
            measurementCode: .unknown,
            measurementCodeRawValue: "future_metric_v2",
            displayKind: .unknown,
            methodSource: "fitmatch",
            inputSource: .userMeasured,
            mappingVersion: "manual_measurement_mapping_v1",
            rawCode: "future_metric_v2",
            rawLabel: "알 수 없는 직접 입력",
            evidenceLevel: .fitmatchDefined,
            semanticStatus: .unknownDefinition,
            userFit: item
        )
        item.measurementRecords = [futureLookingManualRecord]
        let request = FitMatchUpsertClosetItemRequest(
            clientItemID: item.id,
            item: FitMatchClosetSyncCoordinator().payload(for: item),
            productID: nil,
            productSizeID: nil,
            override: nil
        )

        do {
            _ = try FitMatchSupabaseDomainClient.encodedVNextClosetPayload(request)
            Issue.record("An unmappable positive manual value must stop before the RPC payload")
        } catch let error as FitMatchClosetPayloadContractError {
            #expect(error == .unmappablePositiveMeasurement(code: "future_metric_v2"))
        }

        #expect(item.measurementRecords.count == 1)
        #expect(item.measurementRecords[0].measurementCodeRawValue == "future_metric_v2")
        #expect(item.measurementRecords[0].value == 12)
    }

    @Test func listDTOHydrationRetainsAllCanonicalRecordsAndDeterministicLengthProjection() throws {
        let activeCodes = [
            "back_length", "chest_circumference", "chest_width", "front_rise",
            "hem_circumference", "hem_width", "hip_circumference", "hip_width",
            "outseam", "shoulder_width", "sleeve_length", "thigh_circumference",
            "thigh_width", "total_length", "under_bust_circumference",
            "under_bust_width", "waist_circumference", "waist_width"
        ]
        let measurements = activeCodes.enumerated().map { index, code in
            (code, Double(index + 10))
        } + [("future_metric_v2", 99)]
        let dto = try listDTO(
            measurements: measurements,
            unitByCode: ["future_metric_v2": "future_unit_v2"]
        )
        let record = FitMatchSupabaseDomainClient.mapClosetItem(dto)

        #expect(Set(record.measurementRecords.map(\.measurementCode))
            == Set(activeCodes + ["future_metric_v2"]))
        #expect(record.measurementRecords.count == activeCodes.count + 1)

        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = try FitMatchClosetSyncCoordinator().projectAuthoritativeRegistration(
            record,
            expected: request(for: record),
            acceptedClosetItemID: record.closetItemID,
            modelContext: context
        )
        let byRawCode = Dictionary(uniqueKeysWithValues: item.measurementRecords.map {
            ($0.measurementCodeRawValue, $0)
        })

        #expect(Set(byRawCode.keys) == Set(activeCodes + ["future_metric_v2"]))
        #expect(byRawCode["chest_width"]?.measurementCode == .chestWidthPitToPit)
        #expect(byRawCode["chest_circumference"]?.measurementCode == .chestCircumferenceGarment)
        #expect(byRawCode["hip_circumference"]?.measurementCode == .unknown)
        #expect(byRawCode["future_metric_v2"]?.measurementCode == .unknown)
        #expect(byRawCode["future_metric_v2"]?.isComparable == false)
        #expect(byRawCode["future_metric_v2"]?.unitRawValue == "future_unit_v2")

        // `total_length` wins the display scalar by explicit code priority,
        // while both immutable source facts remain independent records.
        #expect(item.totalLength == 23) // total_length is the 14th active code.
        #expect(byRawCode["back_length"]?.value == 10)
        #expect(byRawCode["total_length"]?.value == 23)

        let copy = UserFit(
            brandName: "복원 복사",
            productName: "복원 복사",
            category: .top,
            sizeName: "M",
            measurements: .init(
                shoulder: 0,
                chest: 0,
                totalLength: 0,
                sleeveLength: 0
            ),
            fitMemo: "",
            satisfaction: 3
        )
        copy.replaceMeasurementRecords(with: item.measurementRecords)
        #expect(Set(copy.measurementRecords.map { $0.measurementCodeRawValue })
            == Set(activeCodes + ["future_metric_v2"]))
        #expect(copy.measurementRecords.first {
            $0.measurementCodeRawValue == "total_length"
        }?.value == 23)
        #expect(copy.measurementRecords.first {
            $0.measurementCodeRawValue == "future_metric_v2"
        }?.unitRawValue == "future_unit_v2")

        // A future code hydrated from the server remains an opaque fact on a
        // later manual-Closet round trip; the transport still cannot accept a
        // newly typed unknown code (covered above).
        let roundTripJSON = try decodedJSON(
            FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
                request(for: record)
            )
        )
        let futureRoundTrip = try #require((roundTripJSON["measurements"] as? [[String: Any]])?.first {
            $0["fitmatch_measurement_code"] as? String == "future_metric_v2"
        })
        #expect(futureRoundTrip["unit_code"] as? String == "future_unit_v2")
    }

    @Test func lengthProjectionDoesNotUseResponseOrderForTotalAndBackLength() throws {
        for fixture in [
            ([("total_length", 72.0)], 72.0),
            ([("back_length", 70.0)], 70.0),
            ([("back_length", 70.0), ("total_length", 72.0)], 72.0),
            ([("total_length", 72.0), ("back_length", 70.0)], 72.0)
        ] {
            let dto = try listDTO(measurements: fixture.0)
            let record = FitMatchSupabaseDomainClient.mapClosetItem(dto)
            let container = try inMemoryContainer()
            let item = try FitMatchClosetSyncCoordinator().projectAuthoritativeRegistration(
                record,
                expected: request(for: record),
                acceptedClosetItemID: record.closetItemID,
                modelContext: ModelContext(container)
            )
            #expect(item.totalLength == fixture.1)
            #expect(item.measurementRecords.count == fixture.0.count)
        }
    }

    @Test func storedRetailerReplayDoesNotRewriteCanonicalMeasurementRawIDs() throws {
        let product = Product(
            name: "재생 상품",
            category: .top,
            productCode: "replay-canonical-code",
            metadata: ProductMetadata(genderCodes: ["MEN"]),
            sourceType: .marketplace,
            sourceName: "무신사",
            source: .catalog
        )
        let size = ProductSize(
            name: "M",
            measurements: .init(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0),
            product: product
        )
        product.sizes = [size]
        size.measurementRecords = [
            GarmentMeasurementRecord(
                value: 101,
                measurementCode: .pantsOutseamWaistToHem,
                measurementCodeRawValue: "outseam",
                displayKind: .totalLength,
                methodSource: "fitmatch_vnext_snapshot",
                inputSource: .importedSizeChart,
                mappingVersion: "fixture",
                rawCode: "outseam",
                rawLabel: "outseam",
                evidenceLevel: .officialText,
                semanticStatus: .mapped,
                productSize: size
            ),
            GarmentMeasurementRecord(
                value: 9,
                measurementCode: .unknown,
                measurementCodeRawValue: "future_metric_v2",
                displayKind: .unknown,
                methodSource: "fitmatch_vnext_snapshot",
                inputSource: .importedSizeChart,
                mappingVersion: "fixture",
                rawCode: "future_metric_v2",
                rawLabel: "future_metric_v2",
                evidenceLevel: .officialText,
                semanticStatus: .unknownDefinition,
                productSize: size
            )
        ]

        let replay = try #require(product.fitMatchStoredRetailerFactsForRecompare())
        #expect(replay.sizes.first?.measurementRecords.map(\.canonicalMeasurementCode)
            == ["outseam", "future_metric_v2"])
    }

    @Test func classificationAxisPayloadKeepsVerifiedOuterwearAndExistingTopBottomAxes() throws {
        let jacket = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            request(for: closetPayload(
                categoryCode: "outerwear",
                familyCode: "jacket",
                lengthCode: "long_sleeve",
                bodyLengthCode: nil
            ))
        ))
        #expect(jacket["sleeve_length_code"] as? String == "long_sleeve")
        #expect(jacket["lower_length_code"] == nil)
        #expect(jacket["body_length_code"] == nil)

        let coat = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            request(for: closetPayload(
                categoryCode: "outerwear",
                familyCode: "coat",
                lengthCode: "long_sleeve",
                bodyLengthCode: "medium_body"
            ))
        ))
        #expect(coat["sleeve_length_code"] as? String == "long_sleeve")
        #expect(coat["body_length_code"] as? String == "medium_body")

        let nestedOverride = FitMatchClosetClassificationOverride(
            audienceCode: "MEN",
            categoryCode: "outerwear",
            detailCode: "jacket",
            familyCode: "jacket",
            lengthCode: "long_sleeve",
            reason: "explicit",
            evidence: [:]
        )
        let nested = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            request(
                for: closetPayload(
                    categoryCode: "outerwear",
                    familyCode: "jacket",
                    lengthCode: "long_sleeve",
                    bodyLengthCode: nil
                ),
                override: nestedOverride
            )
        ))
        let nestedJSON = try #require(nested["closet_classification_override"] as? [String: Any])
        #expect(nestedJSON["sleeve_length_code"] as? String == "long_sleeve")

        let standalone = try decodedJSON(
            FitMatchSupabaseDomainClient.encodedVNextClosetOverridePayload(nestedOverride)
        )
        #expect(standalone["sleeve_length_code"] as? String == "long_sleeve")

        let top = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            request(for: closetPayload(
                categoryCode: "tops",
                familyCode: "tshirt",
                lengthCode: "short_sleeve",
                bodyLengthCode: nil
            ))
        ))
        #expect(top["sleeve_length_code"] as? String == "short_sleeve")
        #expect(top["lower_length_code"] == nil)

        let bottom = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            request(for: closetPayload(
                categoryCode: "bottoms",
                familyCode: "standard_pants",
                lengthCode: "long_length",
                bodyLengthCode: nil
            ))
        ))
        #expect(bottom["lower_length_code"] as? String == "long_length")
        #expect(bottom["sleeve_length_code"] == nil)

        let vest = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            request(for: closetPayload(
                categoryCode: "outerwear",
                familyCode: "outer_vest",
                lengthCode: nil,
                bodyLengthCode: "medium_body"
            ))
        ))
        #expect(vest["sleeve_length_code"] == nil)
        #expect(vest["body_length_code"] as? String == "medium_body")

        for invalid in [
            closetPayload(
                categoryCode: "outerwear",
                familyCode: "jacket",
                lengthCode: nil,
                bodyLengthCode: nil
            ),
            closetPayload(
                categoryCode: "outerwear",
                familyCode: "coat",
                lengthCode: "long_sleeve",
                bodyLengthCode: nil
            )
        ] {
            do {
                _ = try FitMatchSupabaseDomainClient.encodedVNextClosetPayload(request(for: invalid))
                Issue.record("Missing required classification axes must stop before the RPC")
            } catch is FitMatchClosetPayloadContractError {
                // Expected: no synthetic axis value is produced.
            }
        }
    }

    @Test func historyVisibilityClassifiesOnlyExactServerCodes() {
        #expect(FitMatchSupabaseDomainClient.historyVisibilityError(
            code: "42501", message: "FM_HISTORY_AUTH_REQUIRED"
        ) == .authenticationRequired)
        #expect(FitMatchSupabaseDomainClient.historyVisibilityError(
            code: "42501", message: "FM_HISTORY_UNAVAILABLE"
        ) == .historyUnavailable)
        #expect(FitMatchSupabaseDomainClient.historyVisibilityError(
            code: "42501", message: "permission denied"
        ) == .rejected)
        #expect(FitMatchSupabaseDomainClient.historyVisibilityError(
            code: "PGRST202", message: "missing function"
        ) == .unavailable)
        #expect(FitMatchSupabaseDomainClient.historyVisibilityError(
            code: "22P02", message: "invalid uuid"
        ) == .invalidRequest)
    }

    private func manualItem() -> UserFit {
        let item = UserFit(
            sourceType: .manual,
            brandName: "직접 입력",
            gender: .men,
            productName: "직접 측정 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 51,
                totalLength: 69,
                sleeveLength: 0
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.categoryCode = "tops"
        item.detailCategoryCode = "short_sleeve"
        item.garmentTypeRawValue = "tshirt"
        item.sleeveTypeRawValue = "short_sleeve"
        item.markClassificationAuthority(
            FitMatchClassificationAuthorityProvenance.userExplicit
        )
        return item
    }

    private func closetPayload(
        categoryCode: String,
        familyCode: String?,
        lengthCode: String?,
        bodyLengthCode: String?
    ) -> FitMatchClosetItemPayload {
        FitMatchClosetItemPayload(
            productName: "축 전송 테스트",
            brand: "테스트",
            sizeName: "M",
            genderCode: "MEN",
            source: "manual",
            categoryCode: categoryCode,
            detailCode: familyCode ?? "other",
            familyCode: familyCode,
            lengthCode: lengthCode,
            bodyLengthCode: bodyLengthCode,
            sourceCategoryPath: nil,
            productURL: nil,
            imageURL: nil,
            measurements: ["chest_width": 52],
            measurementRecords: [],
            fitMemo: "",
            fitPreferenceCode: "regular",
            satisfaction: 3,
            isReference: false,
            classificationVersion: nil,
            clientSnapshot: [:],
            clientCreatedAt: "2026-09-08T00:00:00Z",
            clientUpdatedAt: "2026-09-08T00:00:00Z"
        )
    }

    private func request(
        for item: FitMatchClosetItemPayload,
        clientItemID: UUID = UUID(),
        override: FitMatchClosetClassificationOverride? = nil
    ) -> FitMatchUpsertClosetItemRequest {
        FitMatchUpsertClosetItemRequest(
            clientItemID: clientItemID,
            item: item,
            productID: nil,
            productSizeID: nil,
            override: override
        )
    }

    private func request(for record: FitMatchClosetItemRecord) -> FitMatchUpsertClosetItemRequest {
        request(
            for: FitMatchClosetItemPayload(
                productName: record.productName,
                brand: record.brand,
                sizeName: record.sizeName,
                genderCode: record.genderCode ?? "MEN",
                source: record.source,
                categoryCode: record.categoryCode,
                detailCode: record.detailCode,
                familyCode: record.familyCode,
                lengthCode: record.lengthCode,
                bodyLengthCode: record.bodyLengthCode,
                sourceCategoryPath: record.sourceCategoryPath,
                productURL: record.productURL,
                imageURL: record.imageURL,
                measurements: record.measurements,
                measurementRecords: record.measurementRecords,
                fitMemo: record.fitMemo,
                fitPreferenceCode: record.fitPreferenceCode,
                satisfaction: record.satisfaction,
                isReference: record.isReference,
                classificationVersion: nil,
                clientSnapshot: record.clientSnapshot,
                clientCreatedAt: record.clientCreatedAt ?? record.createdAt,
                clientUpdatedAt: record.clientUpdatedAt ?? record.updatedAt
            ),
            clientItemID: record.clientItemID
        )
    }

    private func listDTO(
        measurements: [(String, Double)],
        unitByCode: [String: String] = [:]
    ) throws -> VNextClosetItemDTO {
        let encodedMeasurements = measurements.map { code, value in
            let unit = unitByCode[code] ?? "cm"
            return """
            {"fitmatch_measurement_code":"\(code)","value":\(value),
            "unit_code":"\(unit)","value_source":"SERVER","raw_label_snapshot":"\(code)"}
            """
        }.joined(separator: ",")
        let id = UUID()
        let clientItemID = UUID()
        return try JSONDecoder().decode(
            VNextClosetItemDTO.self,
            from: Data(
                """
                {
                  "id":"\(id)","client_item_id":"\(clientItemID)",
                  "product_id":null,"product_variant_id":null,"product_size_id":null,
                  "item_name":"서버 옷장","brand_name":null,"image_url":null,
                  "product_url":null,"size_label":"M","audience_code":"MEN",
                  "category_code":"tops","garment_type_code":"tshirt",
                  "sleeve_length_code":"short_sleeve","lower_length_code":null,
                  "body_length_code":null,"classification_source":"USER_EXPLICIT",
                  "classification_fingerprint":"fixture","classification_resolver_version":"fixture-v1",
                  "source_code":"manual","source_product_key":null,"source_category_path":null,
                  "is_reference":false,"fit_preference_code":"regular","notes":null,
                  "satisfaction":3,"created_at":"2026-09-08T00:00:00Z",
                  "updated_at":"2026-09-08T00:00:00Z","measurements":[\(encodedMeasurements)]
                }
                """.utf8
            )
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
