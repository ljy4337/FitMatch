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

    /// The text field is an editing surface, not a one-decimal display.  An
    /// untouched retailer value must not be rounded and accidentally become a
    /// USER_MANUAL correction on the next save.
    @Test func linkedUntouchedDecimalMeasurementRetainsExactValueAndProvenance() throws {
        let fixture = linkedFixture()
        fixture.size.chest = 55.25
        let chestRecord = try #require(fixture.size.measurementRecords.first {
            $0.measurementCodeRawValue == "chest_width"
        })
        chestRecord.value = 55.25

        let draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        #expect(draft.rawValue(for: .chest) == "55.25")

        let snapshot = try draft.snapshot()
        let chest = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == "chest_width"
        })
        #expect(chest.value == 55.25)
        #expect(chest.valueSource == FitMatchClosetMeasurementProvenance.retailerSnapshot)
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

    @Test func linkedVerifiedAdditionalCanonicalMeasurementIsIndependentlyEditable() throws {
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

        let width = try #require(draft.fields.first { $0.id == "chest_width" })
        let circumference = try #require(
            draft.fields.first { $0.id == "chest_circumference" }
        )
        #expect(width.title == "가슴단면")
        #expect(circumference.title == "가슴둘레")
        #expect(draft.rawValue(for: width) == "55")
        #expect(draft.rawValue(for: circumference) == "110")

        draft.setRawValue("111", for: circumference)
        let snapshot = try draft.snapshot()
        let widthRow = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == "chest_width"
        })
        let circumferenceRow = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == "chest_circumference"
        })
        #expect(widthRow.value == 55)
        #expect(widthRow.valueSource == FitMatchClosetMeasurementProvenance.retailerSnapshot)
        #expect(circumferenceRow.value == 111)
        #expect(circumferenceRow.valueSource == FitMatchClosetMeasurementProvenance.userManual)
    }

    @Test func linkedCategoryReconfigurationPreservesUnsavedCompatibleValue() throws {
        let fixture = linkedFixture()
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        draft.setRawValue("56", for: .chest)

        draft.reconfigure(
            category: .bottom,
            detailCategory: .longPants,
            gender: .men
        )
        let retainedChest = try #require(draft.fields.first { $0.id == "chest_width" })
        #expect(draft.rawValue(for: retainedChest) == "56")

        draft.reconfigure(
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        #expect(draft.rawValue(for: .chest) == "56")
        let snapshot = try draft.snapshot()
        let chest = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == "chest_width"
        })
        #expect(chest.value == 56)
        #expect(chest.valueSource == FitMatchClosetMeasurementProvenance.userManual)
    }

    @Test func linkedTrueSizeChangeUsesNewRetailerBaseline() throws {
        let fixture = linkedFixture()
        var mDraft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        mDraft.setRawValue("56", for: .chest)
        mDraft.reconfigure(
            category: .top,
            detailCategory: .longSleeve,
            gender: .men
        )
        #expect(mDraft.rawValue(for: .chest) == "56")

        let lSize = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(
                shoulder: 49,
                chest: 60,
                totalLength: 72,
                sleeveLength: 25
            )
        )
        lSize.measurementRecords = [
            importedRecord(
                value: 60,
                code: .chestWidthPitToPit,
                rawCode: "chest_width",
                kind: .chest,
                productSize: lSize
            )
        ]
        let lDraft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: lSize,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        #expect(lDraft.rawValue(for: .chest) == "60")
    }

    /// A sole circumference fact cannot silently become a chest-width field
    /// just because both render on the chest axis.  The selected taxonomy's
    /// exact chest-width definition is added independently instead.
    @Test func linkedEditDoesNotTreatCircumferenceAsWidthByDisplayAxis() throws {
        let fixture = linkedFixture()
        fixture.size.chest = 0
        fixture.size.measurementRecords.removeAll {
            $0.measurementCodeRawValue == "chest_width"
        }
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
        #expect(draft.rawValue(for: .chest).isEmpty)
        draft.setRawValue("56", for: .chest)

        let snapshot = try draft.snapshot()
        let localCircumference = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == "chest_circumference"
        })
        #expect(localCircumference.value == 110)
        #expect(localCircumference.valueSource
            == FitMatchClosetMeasurementProvenance.retailerSnapshot)
        let localWidth = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == MeasurementCode.chestWidthPitToPit.rawValue
        })
        #expect(localWidth.value == 56)
        #expect(localWidth.valueSource == FitMatchClosetMeasurementProvenance.userManual)

        // The local method-specific code is intentionally normalized only at
        // the transport boundary. The server receives distinct canonical
        // circumference and width rows, with no display-axis substitution.
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(
                linkedRequest(
                    fixture: fixture,
                    snapshot: snapshot,
                    explicitClassification: true
                )
            )
        let rows = try encodedMeasurements(for: submission.remoteRequest)
        #expect(rows["chest_circumference"]?["value"] as? Double == 110)
        #expect(rows["chest_circumference"]?["value_source"] as? String
            == FitMatchClosetMeasurementProvenance.retailerSnapshot)
        #expect(rows["chest_width"]?["value"] as? Double == 56)
        #expect(rows["chest_width"]?["value_source"] as? String
            == FitMatchClosetMeasurementProvenance.userManual)
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
        #expect(rows[hemCode]?["source_measurement_code"] == nil)
        let addedRecord = try #require(snapshot.measurementRecords.first {
            $0.measurementCode == ManualMeasurementRecordFactory.fitmatchCode(
                for: .hem,
                category: .bottom
            ).rawValue
        })
        #expect(addedRecord.rawCode == nil)
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
                 try! #require(row["value_source"] as? String),
                 row["source_measurement_code"] as? String)
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
        #expect(rehydrated.category == .top)
        #expect(rehydrated.detailCategory == .shortSleeve)
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

    /// Re-opening a linked Closet item starts from its owned snapshot so a
    /// category-only change does not reconstruct measurements from ProductSize.
    @Test func linkedClosetEditBaselineRetainsExistingUserRowsForCategoryOnlyEdit() throws {
        let fixture = linkedFixture()
        var firstDraft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        firstDraft.setRawValue("56", for: .chest)
        let ownedSnapshot = try firstDraft.snapshot()
        let item = FitMatchComparedProductClosetRegistration.makeUserFit(
            sourceProduct: fixture.product,
            sourceSize: fixture.size,
            measurementSnapshot: ownedSnapshot,
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

        let reopeningDraft = FitMatchLinkedClosetMeasurementDraft(
            baseline: .init(sourceClosetItem: item),
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        let reopened = try reopeningDraft.snapshot()
        let values = Dictionary(uniqueKeysWithValues: reopened.measurementRecords.map {
            ($0.measurementCode, ($0.value, $0.valueSource))
        })
        #expect(values["chest_width"]?.0 == 56)
        #expect(values["chest_width"]?.1 == FitMatchClosetMeasurementProvenance.userManual)
        #expect(values["shoulder_width"]?.0 == 47)
        #expect(values["shoulder_width"]?.1
            == FitMatchClosetMeasurementProvenance.retailerSnapshot)
    }

    @Test func linkedMutationReceiptRejectsCategoryDetailValueAndProvenanceMismatch() throws {
        let fixture = linkedFixture()
        var draft = FitMatchLinkedClosetMeasurementDraft(
            sourceSize: fixture.size,
            category: .top,
            detailCategory: .shortSleeve,
            gender: .men
        )
        draft.setRawValue("56", for: .chest)
        let submission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(linkedRequest(
                fixture: fixture,
                snapshot: try draft.snapshot(),
                explicitClassification: true
            ))
        let encoded = try encodedMeasurements(for: submission.remoteRequest)
        let expectedRows = encoded.map { code, row in
            (
                code,
                try! #require(row["value"] as? Double),
                try! #require(row["value_source"] as? String),
                row["source_measurement_code"] as? String
            )
        }
        let acceptedDTO = try linkedListDTO(
            clientItemID: submission.remoteRequest.clientItemID,
            identity: fixture.identity,
            rows: expectedRows
        )
        let accepted = FitMatchSupabaseDomainClient.mapClosetItem(acceptedDTO)
        #expect(FitMatchClosetMutationReceiptValidator.matches(
            accepted,
            request: submission.remoteRequest,
            acceptedClosetItemID: accepted.closetItemID
        ))

        let wrongCategory = FitMatchSupabaseDomainClient.mapClosetItem(try linkedListDTO(
            clientItemID: submission.remoteRequest.clientItemID,
            identity: fixture.identity,
            rows: expectedRows,
            categoryCode: "bottoms"
        ))
        #expect(!FitMatchClosetMutationReceiptValidator.matches(
            wrongCategory,
            request: submission.remoteRequest
        ))
        let wrongDetail = FitMatchSupabaseDomainClient.mapClosetItem(try linkedListDTO(
            clientItemID: submission.remoteRequest.clientItemID,
            identity: fixture.identity,
            rows: expectedRows,
            closetDetailCode: "long_sleeve"
        ))
        #expect(!FitMatchClosetMutationReceiptValidator.matches(
            wrongDetail,
            request: submission.remoteRequest
        ))

        let wrongValueRows = expectedRows.map { row in
            row.0 == "chest_width" ? (row.0, 55.0, row.2, row.3) : row
        }
        let wrongValue = FitMatchSupabaseDomainClient.mapClosetItem(try linkedListDTO(
            clientItemID: submission.remoteRequest.clientItemID,
            identity: fixture.identity,
            rows: wrongValueRows
        ))
        #expect(!FitMatchClosetMutationReceiptValidator.matches(
            wrongValue,
            request: submission.remoteRequest
        ))

        let wrongProvenanceRows = expectedRows.map { row in
            row.0 == "chest_width"
                ? (
                    row.0,
                    row.1,
                    FitMatchClosetMeasurementProvenance.retailerSnapshot,
                    row.3
                )
                : row
        }
        let wrongProvenance = FitMatchSupabaseDomainClient.mapClosetItem(try linkedListDTO(
            clientItemID: submission.remoteRequest.clientItemID,
            identity: fixture.identity,
            rows: wrongProvenanceRows
        ))
        #expect(!FitMatchClosetMutationReceiptValidator.matches(
            wrongProvenance,
            request: submission.remoteRequest
        ))

        let wrongSourceIdentityRows = expectedRows.map { row in
            row.0 == "chest_width"
                ? (row.0, row.1, row.2, "fixture.other_chest_semantic")
                : row
        }
        let wrongSourceIdentity = FitMatchSupabaseDomainClient.mapClosetItem(
            try linkedListDTO(
                clientItemID: submission.remoteRequest.clientItemID,
                identity: fixture.identity,
                rows: wrongSourceIdentityRows
            )
        )
        #expect(!FitMatchClosetMutationReceiptValidator.matches(
            wrongSourceIdentity,
            request: submission.remoteRequest
        ))
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

    @Test func unratedLinkedPayloadOmitsSatisfactionAndDecodeRestoresUnratedState() throws {
        let encoded = try decodedJSON(FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
            manualRequest(record: measurementRecord(value: 51), satisfaction: 0)
        ))
        #expect(encoded["satisfaction"] is NSNull)

        let fixture = linkedFixture()
        let dto = try linkedListDTO(
            clientItemID: UUID(),
            identity: fixture.identity,
            rows: [(
                "chest_width",
                55,
                FitMatchClosetMeasurementProvenance.retailerSnapshot,
                "chest_width"
            )],
            satisfaction: NSNull()
        )
        #expect(FitMatchSupabaseDomainClient.mapClosetItem(dto).satisfaction == 0)
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
        rows: [(String, Double, String, String?)],
        categoryCode: String = "tops",
        closetDetailCode: String = "short_sleeve",
        satisfaction: Any = 3
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
            "category_code": categoryCode,
            "closet_detail_code": closetDetailCode,
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
            "satisfaction": satisfaction,
            "created_at": "2026-09-08T00:00:00Z",
            "updated_at": "2026-09-08T00:00:00Z",
            "measurements": rows.map { code, value, source, sourceMeasurementCode in
                [
                    "fitmatch_measurement_code": code,
                    "value": value,
                    "unit_code": "cm",
                    "value_source": source,
                    "source_measurement_code": sourceMeasurementCode.map { $0 as Any }
                        ?? NSNull(),
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
        record: FitMatchClosetMeasurementRecordPayload,
        satisfaction: Int = 3
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
            satisfaction: satisfaction,
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
