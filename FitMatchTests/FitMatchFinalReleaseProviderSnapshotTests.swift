import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// Provider-specific release evidence.  These tests do not relabel one generic
/// `ParsedProductInfo` as three retailers: each case first invokes the current
/// retailer parser component over a captured official response, then feeds its
/// exact output through the shared URL-dispatch and link-registration action.
@MainActor
struct FitMatchFinalReleaseProviderSnapshotTests {
    @Test func uniqloCapturedOfficialSizeResponseReachesTheLinkRegistrationAction() async throws {
        let parsed = try ProviderReleaseSnapshot.uniqloTShirt()

        #expect(parsed.productID == "E493045")
        #expect(parsed.sourceName == "유니클로 공식몰")
        #expect(parsed.sizes.contains { $0.name == "XS" })
        #expect(parsed.sizes.contains { $0.measurements.chest > 0 })

        let product = try await loadThroughLinkRegistration(
            provider: .uniqlo,
            parsed: parsed
        )
        #expect(product.productCode == "E493045")
        #expect(product.sourceName.contains("유니클로"))
        #expect(product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(product.sizes.contains { $0.measurements.chest > 0 })
    }

    @Test func musinsaCapturedOfficialActualSizeResponseReachesTheLinkRegistrationAction() async throws {
        let parsed = try ProviderReleaseSnapshot.musinsaTShirt()

        #expect(parsed.productID == "6294035")
        #expect(parsed.sourceName == "무신사")
        #expect(parsed.sizes.contains { $0.name == "XS" })
        #expect(parsed.sizes.contains { $0.measurementRecords.isEmpty == false })

        let product = try await loadThroughLinkRegistration(
            provider: .musinsa,
            parsed: parsed
        )
        #expect(product.productCode == "6294035")
        #expect(product.sourceName == "무신사")
        #expect(product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(product.sizes.contains { $0.measurementRecords.isEmpty == false })
    }

    @Test func zaraCapturedGarmentMeasureGuideReachesTheLinkRegistrationActionAndBodyOnlyGuideFailsClosed() async throws {
        let parsed = try await ProviderReleaseSnapshot.zaraGarmentMeasurements()

        #expect(parsed.productID == "555068780")
        #expect(parsed.sourceName == "ZARA 공식몰")
        #expect(parsed.measurementAvailability == .actualMeasurements)
        #expect(parsed.sizes.contains { $0.measurements.chest > 0 })

        let product = try await loadThroughLinkRegistration(
            provider: .zara,
            parsed: parsed
        )
        #expect(product.productCode == "555068780")
        #expect(product.sourceName.localizedCaseInsensitiveContains("zara"))
        #expect(product.classificationAuthorityProvenance == .serverConfirmed)

        await #expect(throws: ProductURLParserPartialError.self) {
            _ = try await ProviderReleaseSnapshot.zaraBodyGuideOnly()
        }
    }

    /// CP-001/002/003: each approved retailer's independently parsed capture
    /// drives the real ViewModel through authority, reference, eligibility,
    /// begin, engine, completion, and local History.  Only the remote server
    /// boundary is deterministic; retailer facts are parsed before that
    /// boundary and the captured resolver request proves that no generic
    /// product label stood in for a provider path.
    @Test func capturedProviderFactsReachTheFullServerAuthorizedComparisonPath() async throws {
        let cases: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, try ProviderReleaseSnapshot.uniqloTShirt()),
            (.musinsa, try ProviderReleaseSnapshot.musinsaTShirt()),
            (.zara, try await ProviderReleaseSnapshot.zaraGarmentMeasurements())
        ]

        for (provider, parsed) in cases {
            let run = try await completeThroughCapturedRetailerParser(
                provider: provider,
                parsed: parsed
            )
            guard let history = run.history else {
                throw ProviderReleaseSnapshotError.comparisonDidNotComplete(
                    provider.rawValue,
                    calls: await run.remote.calls(),
                    message: run.errorMessage
                )
            }
            #expect(history.product.productCode == parsed.productID)
            #expect(history.product.sourceURLString == parsed.canonicalURLString)

            let requests = await run.remote.resolutionRequests()
            let request = try #require(requests.first)
            #expect(request.source == provider.rawValue)
            #expect(request.externalProductID == parsed.productID)
            #expect(request.productName == parsed.productName)

            let calls = await run.remote.calls()
            let expected = [
                "resolve", "runtime", "list_closet", "reference_candidates",
                "eligible_sizes", "begin_comparison", "complete_comparison"
            ]
            var cursor = calls.startIndex
            for call in expected {
                let index = try #require(calls[cursor...].firstIndex(of: call))
                cursor = calls.index(after: index)
            }
        }
    }

    /// EN-001: direct retailer URLs and the valid custom compare route share
    /// one product-entry contract.  Each approved URL begins with its actual
    /// captured provider parser output before entering the normal
    /// server-authorized comparison flow; no provider enum or URL label is
    /// substituted for retailer facts.
    @Test func en001ApprovedDirectURLsAndCustomCompareRouteReachTheirExactTargets() async throws {
        let cases: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, try ProviderReleaseSnapshot.uniqloTShirt()),
            (.musinsa, try ProviderReleaseSnapshot.musinsaTShirt()),
            (.zara, try await ProviderReleaseSnapshot.zaraGarmentMeasurements())
        ]
        let handoffURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatch.EN001.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: handoffURL) }
        let handoffStore = SharedURLStore(fileURL: handoffURL)
        let compareRoute = try #require(URL(string: "fitmatch://compare"))
        #expect(FitMatchProductEntryRouting.action(for: compareRoute) == .openPendingProductCompare)

        for (provider, parsed) in cases {
            #expect(FitMatchProductURLRouting.provider(for: parsed.sourceURL)?.rawValue == provider.rawValue)
            handoffStore.savePendingProductURL(parsed.sourceURL)
            #expect(handoffStore.consumePendingProductURL() == parsed.sourceURL.absoluteString)

            let run = try await completeThroughCapturedRetailerParser(
                provider: provider,
                parsed: parsed
            )
            let history = try #require(run.history)
            #expect(history.product.sourceURLString == parsed.canonicalURLString)
            #expect(history.product.productCode == parsed.productID)
            #expect((await run.remote.resolutionRequests()).first?.externalProductID == parsed.productID)
        }
    }

    /// CR-011/CR-012/CR-013/CR-015/CR-016/CR-018: after each retailer's
    /// actual captured parser data has crossed the normal link-registration
    /// action, the production Closet boundary must persist only a presented
    /// owned size, preserve the server-backed source, and reject a second
    /// identical submit.  The loop deliberately keeps three independently
    /// parsed provider products; it never relabels a generic Product.
    @Test func capturedProviderLinkRegistrationsPersistOnlyPresentedSizesAndRejectDuplicateSubmit() async throws {
        let cases: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, try ProviderReleaseSnapshot.uniqloTShirt()),
            (.musinsa, try ProviderReleaseSnapshot.musinsaTShirt()),
            (.zara, try await ProviderReleaseSnapshot.zaraGarmentMeasurements())
        ]

        for (provider, parsed) in cases {
            let product = try await loadThroughLinkRegistration(
                provider: provider,
                parsed: parsed
            )
            let categoryCode = try #require(product.categoryCode)
            let detailCode = try #require(product.normalizedProductTypeCode)
            let selectedSize = try #require(product.sizes.first(where: {
                $0.measurementRecords.isEmpty == false
            }))
            let schema = Schema(FitMatchSchemaV1.models)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )]
            )
            let context = ModelContext(container)
            let request = FitMatchComparedProductClosetRegistration.SaveRequest(
                product: product,
                selectedSize: selectedSize,
                activeClosetItems: [],
                brandName: product.brand?.name ?? parsed.brandName,
                gender: .men,
                genderCode: "MEN",
                productName: product.name,
                category: product.category,
                categoryCode: categoryCode,
                detailCategory: ClosetDetailCategory.fromTaxonomyCode(detailCode),
                detailCategoryCode: detailCode,
                isRepresentative: false,
                didExplicitlyChangeClassification: false
            )
            guard case .saved(let item) = FitMatchComparedProductClosetRegistration.save(
                request,
                in: context
            ) else {
                Issue.record("\(provider.rawValue) captured link product did not persist through the production Closet action")
                continue
            }

            #expect(item.sourceProduct?.productCode == parsed.productID)
            #expect(item.sourceProductSize?.id == selectedSize.id)
            #expect(
                item.classificationAuthorityProvenance
                    == FitMatchClassificationAuthorityProvenance.serverConfirmed
            )
            #expect(item.measurementRecords.isEmpty == false)

            let duplicate = FitMatchComparedProductClosetRegistration.SaveRequest(
                product: product,
                selectedSize: selectedSize,
                activeClosetItems: [item],
                brandName: request.brandName,
                gender: request.gender,
                genderCode: request.genderCode,
                productName: request.productName,
                category: request.category,
                categoryCode: request.categoryCode,
                detailCategory: request.detailCategory,
                detailCategoryCode: request.detailCategoryCode,
                isRepresentative: false,
                didExplicitlyChangeClassification: false
            )
            if case .duplicate = FitMatchComparedProductClosetRegistration.save(
                duplicate,
                in: context
            ) {
                // Exact duplicate stays one owned Closet row.
            } else {
                Issue.record("\(provider.rawValue) duplicate link submit was not rejected by the production action")
            }
            #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
        }
    }

    /// CP-004/RX-012: a single real ShoppingProductViewModel receives three
    /// different captured provider parser outputs in sequence.  Its current
    /// product identity, source label, size state, and resolver request must
    /// change each time; no preceding retailer state may bleed into the next
    /// approved URL.
    @Test func sequentialCapturedProviderLoadsResetCurrentProductStateWithoutProviderLeakage() async throws {
        let uniqlo = try ProviderReleaseSnapshot.uniqloTShirt()
        let musinsa = try ProviderReleaseSnapshot.musinsaTShirt()
        let zara = try await ProviderReleaseSnapshot.zaraGarmentMeasurements()
        // CP-004 has two distinct facts: re-opening the exact same canonical
        // retailer product is idempotent, and a subsequent provider switch
        // cannot retain that product's state. Keep the actual UNIQLO capture
        // twice rather than relabelling a generic Product.
        let snapshots: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, uniqlo),
            (.uniqlo, uniqlo),
            (.musinsa, musinsa),
            (.zara, zara)
        ]
        let fixtures = snapshots.map {
            HeadlessJourneyFixture(provider: $0.0, parsedProductOverride: $0.1)
        }
        let remote = JourneyRecordingRemote(
            resolutions: fixtures.map { $0.resolution(globalStatus: .confirmed) },
            runtimes: try fixtures.map { try $0.runtime(globalStatus: .confirmed) }
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: uniqlo.sourceURL.absoluteString,
            parserService: ProductURLParserService(
                musinsaParser: ProviderReleaseSnapshotReplayParser(parsed: musinsa, provider: .musinsa),
                uniqloParser: ProviderReleaseSnapshotReplayParser(parsed: uniqlo, provider: .uniqlo),
                zaraParser: ProviderReleaseSnapshotReplayParser(parsed: zara, provider: .zara)
            ),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        for (_, parsed) in snapshots {
            viewModel.productURL = parsed.sourceURL.absoluteString
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(viewModel.productCode == parsed.productID)
            #expect(viewModel.productName == parsed.productName)
            #expect(viewModel.sourceName == parsed.sourceName)
            #expect(viewModel.sizeOptions.isEmpty == false)
            #expect(viewModel.hasServerConfirmedAuthority)
        }

        let requests = await remote.resolutionRequests()
        #expect(requests.map(\.source) == ["uniqlo", "uniqlo", "musinsa", "zara"])
        #expect(requests.map(\.externalProductID) == [
            uniqlo.productID,
            uniqlo.productID,
            musinsa.productID,
            zara.productID
        ])
    }

    /// CR-014: each approved retailer starts with a real captured parser
    /// result, but the first parser transport response fails. The same
    /// production ViewModel must clear the failed state and retry the exact
    /// retailer URL without retaining a preceding product identity.
    @Test func capturedProviderParserFailureThenRetryResetsStateForEveryApprovedProvider() async throws {
        let cases: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, try ProviderReleaseSnapshot.uniqloTShirt()),
            (.musinsa, try ProviderReleaseSnapshot.musinsaTShirt()),
            (.zara, try await ProviderReleaseSnapshot.zaraGarmentMeasurements())
        ]

        for (provider, parsed) in cases {
            let parser = ProviderReleaseSnapshotFailThenReplayParser(
                parsed: parsed,
                provider: provider
            )
            let viewModel = ShoppingProductViewModel(
                initialURL: parsed.sourceURL.absoluteString,
                parserService: providerParserService(for: provider, parser: parser),
                metricsRecorder: HeadlessNoopMetricsRecorder(),
                serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                    remote: FitMatchEchoServerAuthorityRemote()
                )
            )

            #expect(await viewModel.loadProductInfoFromURL() == false)
            #expect(viewModel.hasLoadedProductInfo == false)
            #expect(viewModel.productCode == nil)
            #expect(viewModel.errorMessage != nil)

            #expect(await viewModel.loadProductInfoFromURL())
            #expect(viewModel.productCode == parsed.productID)
            #expect(viewModel.productName == parsed.productName)
            #expect(viewModel.sourceName == parsed.sourceName)
            #expect(viewModel.sizeOptions.isEmpty == false)
        }
    }

    /// CR-013/CR-021/CP-033: a real ZARA body-size-only guide is rejected by
    /// ZARAParser. Its resulting partial product crosses the same link
    /// registration action and exposes only the existing recovery state; no
    /// fabricated garment size can be saved.
    @Test func zaraBodyOnlyGuideReachesTheProductionPartialRegistrationRecoveryState() async throws {
        let partial: ParsedProductInfo
        do {
            _ = try await ProviderReleaseSnapshot.zaraBodyGuideOnly()
            Issue.record("A body-only ZARA guide unexpectedly parsed as garment measurements")
            return
        } catch let error as ProductURLParserPartialError {
            partial = error.productInfo
        }

        let outcome = await FitMatchLinkClosetRegistrationAction.load(
            urlString: partial.sourceURL.absoluteString,
            makeViewModel: { urlString in
                ShoppingProductViewModel(
                    initialURL: urlString,
                    parserService: providerParserService(
                        for: .zara,
                        parser: ProviderReleaseSnapshotPartialParser(
                            product: partial,
                            provider: .zara
                        )
                    ),
                    metricsRecorder: HeadlessNoopMetricsRecorder(),
                    serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                        remote: FitMatchEchoServerAuthorityRemote(
                            categoryCode: "tops",
                            detailCode: "short_sleeve",
                            familyCode: "tshirt",
                            lengthCode: "short_sleeve"
                        )
                    )
                )
            },
            existingBrand: { _ in nil }
        )

        guard case .loaded(let preparation) = outcome else {
            Issue.record("The ZARA partial parser result did not reach link registration")
            return
        }
        #expect(preparation.parsedProduct == nil)
        #expect(preparation.partialProduct?.sizes.isEmpty == true)
        #expect(preparation.partialProduct?.classificationAuthorityProvenance == .serverConfirmed)
        #expect(preparation.recoveryViewModel != nil)
        #expect(preparation.errorMessage != nil)
    }

    /// CR-012: the MUSINSA recovery corridor starts with a captured official
    /// product, parses a repository fallback size table with the production
    /// parser, and completes through the same selected-size action used by
    /// the recovery view. An invalid recovery row remains blocked rather than
    /// being turned into a guessed owned size.
    @Test func cr012MusinsaCapturedFallbackRecoveryPersistsOnlyTheValidatedSelectedSize() async throws {
        let captured = try ProviderReleaseSnapshot.musinsaTShirt()
        let viewModel = ShoppingProductViewModel(
            initialURL: captured.sourceURL.absoluteString,
            parserService: providerParserService(for: .musinsa, parsed: captured),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                remote: FitMatchEchoServerAuthorityRemote()
            )
        )
        #expect(await viewModel.loadProductInfoFromURL())

        let recovered = MusinsaFallbackTableParser.parseHTML(
            MusinsaSizePipelineFixtures.product6219777HTML,
            family: .upper
        )
        let recoveredSize = try #require(recovered.first)
        let selected = ShoppingProductViewModel.makeSizeForm(
            from: recoveredSize,
            displayOrder: 0,
            allowsStandardSizeFallback: false
        )
        viewModel.sizeOptions = [selected]

        #expect(FitMatchSizeTableRecoveryAction.complete(
            selectedSize: selected,
            viewModel: viewModel
        ) == .completed(selectedSizeID: selected.id))
        #expect(viewModel.recoverySelectedSizeID == selected.id)

        let invalid = ClothingSizeForm(sizeName: "M")
        #expect(FitMatchSizeTableRecoveryAction.complete(
            selectedSize: invalid,
            viewModel: viewModel
        ) == .blocked("각 사이즈 행에 비교 가능한 치수를 입력해 주세요."))
        #expect(viewModel.recoverySelectedSizeID == selected.id)

        let product = try #require(viewModel.makeProductForClosetRegistration(
            brand: Brand(name: captured.brandName)
        ))
        let persistedSize = try #require(product.sizes.first { $0.id == selected.id })
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let request = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: product,
            selectedSize: persistedSize,
            activeClosetItems: [],
            brandName: captured.brandName,
            gender: .men,
            genderCode: "MEN",
            productName: captured.productName,
            category: product.category,
            categoryCode: try #require(product.categoryCode),
            detailCategory: ClosetDetailCategory.fromTaxonomyCode(
                try #require(product.normalizedProductTypeCode)
            ),
            detailCategoryCode: try #require(product.normalizedProductTypeCode),
            isRepresentative: false,
            didExplicitlyChangeClassification: false
        )
        guard case .saved(let saved) = FitMatchComparedProductClosetRegistration.save(
            request,
            in: context
        ) else {
            Issue.record("CR-012 recovery product did not reach production Closet persistence")
            return
        }
        #expect(saved.sourceProductSize?.id == selected.id)
        #expect(saved.measurementRecords.isEmpty == false)
    }

    /// CR-014: all three actual retailer parser dispatch paths fail once at
    /// their transport boundary and then retry the same provider URL. The
    /// retry cannot retain any old product state because the ViewModel resets
    /// before it asks the current parser again.
    @Test func cr014ApprovedProviderParserFailuresRetryTheExactRetailerPath() async throws {
        let cases: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, try ProviderReleaseSnapshot.uniqloTShirt()),
            (.musinsa, try ProviderReleaseSnapshot.musinsaTShirt()),
            (.zara, try await ProviderReleaseSnapshot.zaraGarmentMeasurements())
        ]

        for (provider, parsed) in cases {
            let viewModel = ShoppingProductViewModel(
                initialURL: parsed.sourceURL.absoluteString,
                parserService: providerParserService(
                    for: provider,
                    parser: ProviderReleaseSnapshotFailThenReplayParser(
                        parsed: parsed,
                        provider: provider
                    )
                ),
                metricsRecorder: HeadlessNoopMetricsRecorder(),
                serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                    remote: FitMatchEchoServerAuthorityRemote()
                )
            )
            #expect(await viewModel.loadProductInfoFromURL() == false)
            #expect(viewModel.productCode == nil)
            #expect(viewModel.errorMessage != nil)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(viewModel.productCode == parsed.productID)
            #expect(viewModel.sourceName == parsed.sourceName)
        }
    }

    /// CR-016: the selected owned size must already be in an actual parsed
    /// table. This exercises three independent captured provider tables and
    /// the same production registration action used by the confirmation sheet.
    @Test func cr016CapturedProviderOwnedSizeSelectionNeverFabricatesASize() async throws {
        let cases: [(HeadlessJourneyProvider, ParsedProductInfo)] = [
            (.uniqlo, try ProviderReleaseSnapshot.uniqloTShirt()),
            (.musinsa, try ProviderReleaseSnapshot.musinsaTShirt()),
            (.zara, try await ProviderReleaseSnapshot.zaraGarmentMeasurements())
        ]

        for (provider, parsed) in cases {
            let product = try await loadThroughLinkRegistration(provider: provider, parsed: parsed)
            let selectedSize = try #require(product.sizes.last)
            #expect(parsed.sizes.contains { $0.name == selectedSize.name })
            let schema = Schema(FitMatchSchemaV1.models)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            let context = ModelContext(container)
            let request = FitMatchComparedProductClosetRegistration.SaveRequest(
                product: product,
                selectedSize: selectedSize,
                activeClosetItems: [],
                brandName: parsed.brandName,
                gender: .men,
                genderCode: "MEN",
                productName: parsed.productName,
                category: product.category,
                categoryCode: try #require(product.categoryCode),
                detailCategory: ClosetDetailCategory.fromTaxonomyCode(
                    try #require(product.normalizedProductTypeCode)
                ),
                detailCategoryCode: try #require(product.normalizedProductTypeCode),
                isRepresentative: false,
                didExplicitlyChangeClassification: false
            )
            guard case .saved(let saved) = FitMatchComparedProductClosetRegistration.save(
                request,
                in: context
            ) else {
                Issue.record("CR-016 \(provider.rawValue) did not persist the presented owned size")
                continue
            }
            #expect(saved.sourceProductSize?.id == selectedSize.id)
            #expect(saved.sourceProductSize?.product?.id == product.id)
        }
    }

    /// CR-011/12/13 and CP-001/2/3 depend on the retailer parser and the
    /// normal URL dispatcher, not a test-side provider label.  The server
    /// response is the permitted remote boundary; the product facts are the
    /// captured parser output above.
    private func loadThroughLinkRegistration(
        provider: HeadlessJourneyProvider,
        parsed: ParsedProductInfo
    ) async throws -> Product {
        // This production test remote echoes the parsed retailer identity back
        // as a confirmed server authority. It owns no provider fact or
        // reference/size decision; the actual captured parser output above is
        // what reaches the production link-registration action.
        let remote: FitMatchEchoServerAuthorityRemote
        switch provider {
        case .zara:
            remote = FitMatchEchoServerAuthorityRemote(
                categoryCode: "tops",
                detailCode: "long_sleeve",
                familyCode: "tshirt",
                lengthCode: "long_sleeve"
            )
        case .uniqlo, .musinsa:
            remote = FitMatchEchoServerAuthorityRemote()
        }
        let outcome = await FitMatchLinkClosetRegistrationAction.load(
            urlString: parsed.sourceURL.absoluteString,
            makeViewModel: { urlString in
                ShoppingProductViewModel(
                    initialURL: urlString,
                    parserService: providerParserService(
                        for: provider,
                        parsed: parsed
                    ),
                    metricsRecorder: HeadlessNoopMetricsRecorder(),
                    serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                        remote: remote
                    )
                )
            },
            existingBrand: { _ in nil }
        )
        guard case .loaded(let preparation) = outcome,
              let product = preparation.parsedProduct else {
            throw ProviderReleaseSnapshotError.linkPreparationDidNotProduceProduct(provider.rawValue)
        }
        return product
    }

    private func providerParserService(
        for provider: HeadlessJourneyProvider,
        parsed: ParsedProductInfo
    ) -> ProductURLParserService {
        let replay = ProviderReleaseSnapshotReplayParser(parsed: parsed, provider: provider)
        return providerParserService(for: provider, parser: replay)
    }

    private func providerParserService(
        for provider: HeadlessJourneyProvider,
        parser: ProductURLParsing
    ) -> ProductURLParserService {
        switch provider {
        case .uniqlo:
            return ProductURLParserService(uniqloParser: parser)
        case .musinsa:
            return ProductURLParserService(musinsaParser: parser)
        case .zara:
            return ProductURLParserService(zaraParser: parser)
        }
    }

    private func completeThroughCapturedRetailerParser(
        provider: HeadlessJourneyProvider,
        parsed: ParsedProductInfo
    ) async throws -> (
        history: RecommendationHistory?,
        remote: JourneyRecordingRemote,
        errorMessage: String?
    ) {
        let fixture = HeadlessJourneyFixture(
            provider: provider,
            parsedProductOverride: parsed
        )
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let reference = fixture.localReference(
            garment: "tshirt",
            sleeve: "short_sleeve"
        )
        let remoteReference = fixture.closetRecord(for: reference)
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 3),
            runtimes: Array(repeating: runtime, count: 3),
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: Array(repeating: try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            ), count: 2),
            eligibleResponses: [try fixture.eligible(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                mode: "AUTOMATIC",
                allowed: true,
                effectiveSource: nil,
                overrideRevision: nil
            )],
            beginResponses: [try fixture.begin(
                mode: "AUTOMATIC",
                personal: false,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: "tshirt",
                personalRevision: 0,
                personalCandidateFingerprint: nil,
                personalCandidateSetHash: nil,
                personalInputFingerprint: nil,
                personalEvidenceFingerprint: nil
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: parsed.sourceURL.absoluteString,
            parserService: providerParserService(for: provider, parsed: parsed),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                remote: remote
            )
        )
        guard await viewModel.loadProductInfoFromURL() else {
            throw ProviderReleaseSnapshotError.comparisonLoadFailed(provider.rawValue)
        }
        return (
            await viewModel.calculateRecommendation(userFits: [reference]),
            remote,
            viewModel.errorMessage
        )
    }
}

private final class ProviderReleaseSnapshotBundleToken {}

private enum ProviderReleaseSnapshotError: Error, CustomStringConvertible {
    case missingFixture(String)
    case malformedFixture(String)
    case linkPreparationDidNotProduceProduct(String)
    case comparisonLoadFailed(String)
    case comparisonDidNotComplete(String, calls: [String], message: String?)

    var description: String {
        switch self {
        case .missingFixture(let value): "Missing repository fixture: \(value)"
        case .malformedFixture(let value): "Malformed repository fixture: \(value)"
        case .linkPreparationDidNotProduceProduct(let value):
            "Provider link preparation did not produce a product: \(value)"
        case .comparisonLoadFailed(let value):
            "Provider comparison load failed: \(value)"
        case let .comparisonDidNotComplete(provider, calls, message):
            "Provider comparison did not complete: \(provider), calls=\(calls), error=\(message ?? "nil")"
        }
    }
}

@MainActor
private final class ProviderReleaseSnapshotReplayParser: ProductURLParsing {
    private let parsed: ParsedProductInfo
    private let provider: HeadlessJourneyProvider

    init(parsed: ParsedProductInfo, provider: HeadlessJourneyProvider) {
        self.parsed = parsed
        self.provider = provider
    }

    /// Keep the replay adapter at the network boundary only. Routing remains
    /// the production parser's URL rule, so a captured ZARA URL cannot be
    /// claimed by the injected UNIQLO parser during a sequential load.
    func canParse(_ url: URL) -> Bool {
        switch provider {
        case .uniqlo:
            UniqloParser().canParse(url)
        case .musinsa:
            MusinsaParser().canParse(url)
        case .zara:
            ZARAParser().canParse(url)
        }
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        parsed
    }
}

/// Deterministic transport-only failure injection around a result that was
/// already obtained from the real retailer parser above. The retry therefore
/// exercises the production URL dispatcher/ViewModel reset rather than a
/// generic test Product.
@MainActor
private final class ProviderReleaseSnapshotFailThenReplayParser: ProductURLParsing {
    private let replay: ProviderReleaseSnapshotReplayParser
    private var shouldFail = true

    init(parsed: ParsedProductInfo, provider: HeadlessJourneyProvider) {
        replay = ProviderReleaseSnapshotReplayParser(parsed: parsed, provider: provider)
    }

    func canParse(_ url: URL) -> Bool { replay.canParse(url) }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        if shouldFail {
            shouldFail = false
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return try await replay.parse(from: url)
    }
}

/// Replays the exact partial product emitted by the real ZARA parser for a
/// body-only guide. It is intentionally a parser-boundary transport adapter;
/// `ProductURLParserService` and the link registration action still own the
/// partial/error/authority behavior under test.
@MainActor
private final class ProviderReleaseSnapshotPartialParser: ProductURLParsing {
    private let product: ParsedProductInfo
    private let replay: ProviderReleaseSnapshotReplayParser

    init(product: ParsedProductInfo, provider: HeadlessJourneyProvider) {
        self.product = product
        replay = ProviderReleaseSnapshotReplayParser(parsed: product, provider: provider)
    }

    func canParse(_ url: URL) -> Bool { replay.canParse(url) }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        throw ProductURLParserPartialError(productInfo: product)
    }
}

private struct ProviderReleaseZARAProductPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage

    func load(url: URL) async throws -> ZARAProductPage { page }
}

private struct ProviderReleaseZARASizeGuideLoader: ZARASizeGuideLoading {
    let data: Data

    func load(productID: String) async throws -> Data { data }
}

@MainActor
private enum ProviderReleaseSnapshot {
    static func uniqloTShirt() throws -> ParsedProductInfo {
        let input = try corpusInput(id: "E493045", resource: "Uniqlo243FitPairInputs")
        let productName = try string("product_name", in: input)
        let sourcePath = try string("source_path", in: input)
        let response = try value("response", in: input)
        let sizes = try UniqloSizeAPIParser().parseSizes(
            from: JSONSerialization.data(withJSONObject: response)
        )
        let metadataParser = UniqloProductMetadataParser()
        let category = metadataParser.mapCategory(from: "\(sourcePath) \(productName)")
        let detail = metadataParser.mapDetailCategory(from: "\(sourcePath) \(productName)")
        let genderCodes = input["gender_codes"] as? [String] ?? []
        let depths = sourcePath.components(separatedBy: ">")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let url = try requiredURL("https://www.uniqlo.com/kr/ko/products/E493045")

        return ParsedProductInfo(
            sourceURL: url,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "UNIQLO",
            productName: productName,
            category: category,
            detailCategory: detail,
            sizes: sizes,
            productID: "E493045",
            canonicalURLString: url.absoluteString,
            sourceCategoryPath: sourcePath,
            sourceCategoryDepth1: depths.indices.contains(0) ? depths[0] : nil,
            sourceCategoryDepth2: depths.indices.contains(1) ? depths[1] : nil,
            sourceCategoryDepth3: depths.indices.contains(2) ? depths[2] : nil,
            productTargetGender: UserGender.productTarget(from: genderCodes),
            productMetadata: ProductMetadata(
                brandEnglishName: "UNIQLO",
                sourceCategoryPath: sourcePath,
                sourceCategoryDepth1: depths.indices.contains(0) ? depths[0] : nil,
                sourceCategoryDepth2: depths.indices.contains(1) ? depths[1] : nil,
                sourceCategoryDepth3: depths.indices.contains(2) ? depths[2] : nil,
                genderCodes: genderCodes
            )
        )
    }

    static func musinsaTShirt() throws -> ParsedProductInfo {
        let input = try corpusInput(id: "6294035", resource: "Musinsa1037FitPairInputs")
        let productName = try string("product_name", in: input)
        let sourcePath = try string("source_path", in: input)
        let response = try value("response", in: input)
        let category = MusinsaProductMetadataParser.mapCategory(from: sourcePath)
        let detail = MusinsaProductMetadataParser.mapDetailCategory(from: sourcePath)
        let sizes = try MusinsaActualSizeAPIParser().parseActualSize(
            from: JSONSerialization.data(withJSONObject: response),
            isTopCategory: category.serviceGroup == .top
        ).sizes
        let genderCodes = input["gender_codes"] as? [String] ?? []
        let depths = sourcePath.components(separatedBy: ">")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let url = try requiredURL("https://www.musinsa.com/products/6294035")
        var metadata = ProductMetadata(
            brandEnglishName: "MUSINSA",
            sourceCategoryPath: sourcePath,
            sourceCategoryDepth1: depths.indices.contains(0) ? depths[0] : nil,
            sourceCategoryDepth2: depths.indices.contains(1) ? depths[1] : nil,
            sourceCategoryDepth3: depths.indices.contains(2) ? depths[2] : nil,
            genderCodes: genderCodes
        )
        metadata.sizeType = "captured_actual_size"
        let snapshot = MusinsaProductMetadata(
            sourceURL: url,
            productID: "6294035",
            brandName: "Nike",
            productName: productName,
            category: category,
            detailCategory: detail,
            categoryDepth1Name: depths.indices.contains(0) ? depths[0] : nil,
            categoryDepth2Name: depths.indices.contains(1) ? depths[1] : nil,
            canonicalURLString: url.absoluteString,
            productMetadata: metadata
        )
        return snapshot.parsedProductInfo(sizes: sizes)
    }

    static func zaraGarmentMeasurements() async throws -> ParsedProductInfo {
        let url = try requiredURL(
            "https://www.zara.com/kr/ko/zara-%ED%8B%B0%EC%85%94%EC%B8%A0-p01887423.html?v1=555080441"
        )
        let guideEnvelope = try JSONSerialization.jsonObject(
            with: repositoryData("ZARAAudit/production_sample_30_cache/555080441.json")
        ) as? [String: Any]
        let guide = try value("response", in: guideEnvelope ?? [:])
        let guideData = try JSONSerialization.data(withJSONObject: guide)
        let html = """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"아론 레빈 X ZARA 스트라이프 자카드 티셔츠","productGroupID":"01887423","hasVariant":[{"sku":"555080441"}]}</script>
        <script>zara.analyticsData = {"productId":555068780,"productRef":"01887423-044","catentryId":555080441,"section":"MAN","family":"티셔츠","subfamily":"Camiseta M/L"};</script>
        </head><body></body></html>
        """
        let parser = ZARAParser(
            pageLoader: ProviderReleaseZARAProductPageLoader(
                page: ZARAProductPage(url: url, statusCode: 200, html: html)
            ),
            sizeGuideLoader: ProviderReleaseZARASizeGuideLoader(data: guideData)
        )
        return try await parser.parse(from: url)
    }

    static func zaraBodyGuideOnly() async throws -> ParsedProductInfo {
        let url = try requiredURL(
            "https://www.zara.com/kr/ko/%EC%8A%A4%ED%8A%B8%EB%9D%BC%EC%9D%B4%ED%94%84-%ED%8B%B0%EC%85%94%EC%B8%A0-p01165305.html?v1=545486853"
        )
        let guideEnvelope = try JSONSerialization.jsonObject(
            with: repositoryData("ZARAAudit/cache/545486853.json")
        ) as? [String: Any]
        let guide = guideEnvelope?["response"] ?? guideEnvelope ?? [:]
        let guideData = try JSONSerialization.data(withJSONObject: guide)
        let html = """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"스트라이프 티셔츠","productGroupID":"01165305","hasVariant":[{"sku":"545486853"}]}</script>
        <script>zara.analyticsData = {"productId":545486852,"productRef":"01165305-000","catentryId":545486853,"section":"MAN","family":"티셔츠","subfamily":"Camiseta"};</script>
        </head><body></body></html>
        """
        let parser = ZARAParser(
            pageLoader: ProviderReleaseZARAProductPageLoader(
                page: ZARAProductPage(url: url, statusCode: 200, html: html)
            ),
            sizeGuideLoader: ProviderReleaseZARASizeGuideLoader(data: guideData)
        )
        return try await parser.parse(from: url)
    }

    private static func corpusInput(
        id: String,
        resource: String
    ) throws -> [String: Any] {
        let url = try requiredBundleURL(resource, extension: "json")
        let values = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        guard let value = values?.first(where: { $0["product_id"] as? String == id }) else {
            throw ProviderReleaseSnapshotError.missingFixture("\(resource):\(id)")
        }
        return value
    }

    private static func repositoryData(_ relativePath: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderReleaseSnapshotError.missingFixture(relativePath)
        }
        return try Data(contentsOf: url)
    }

    private static func requiredBundleURL(
        _ resource: String,
        extension fileExtension: String
    ) throws -> URL {
        guard let url = Bundle(for: ProviderReleaseSnapshotBundleToken.self)
            .url(forResource: resource, withExtension: fileExtension) else {
            throw ProviderReleaseSnapshotError.missingFixture("\(resource).\(fileExtension)")
        }
        return url
    }

    private static func requiredURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw ProviderReleaseSnapshotError.malformedFixture(value)
        }
        return url
    }

    private static func value(_ key: String, in dictionary: [String: Any]) throws -> Any {
        guard let value = dictionary[key] else {
            throw ProviderReleaseSnapshotError.malformedFixture(key)
        }
        return value
    }

    private static func string(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = dictionary[key] as? String, !value.isEmpty else {
            throw ProviderReleaseSnapshotError.malformedFixture(key)
        }
        return value
    }
}
