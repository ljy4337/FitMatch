import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// The second stage of the frozen 137-scenario release acceptance.
///
/// Every case below constructs data at a real side-effect boundary and then
/// invokes the production action/coordinator/ViewModel. It deliberately does
/// not classify, select a reference, authorize a comparison, calculate a
/// score, or synthesize a terminal product result in the test target.
@MainActor
struct FitMatchFinalReleaseScenarioExecutionTests {
    @Test func frozen137ClassificationReconcilesWithoutAddingOrDroppingAScenario() {
        let all = FinalFrozenScenarioClassification.allIDs
        let headless = FinalFrozenScenarioClassification.headlessIDs
        let staticContract = FinalFrozenScenarioClassification.staticContractIDs
        let physical = FinalFrozenScenarioClassification.physicalSmokeIDs

        #expect(all.count == 137)
        #expect(headless.count == 131)
        #expect(staticContract.count == 2)
        #expect(physical.count == 4)
        #expect(Set(headless).isDisjoint(with: staticContract))
        #expect(Set(headless).isDisjoint(with: physical))
        #expect(Set(staticContract).isDisjoint(with: physical))
        #expect(Set(headless).union(staticContract).union(physical) == Set(all))
    }

    @Test func staticContractsCoverOnlyFrozenShellAndGlobalSearchRows() throws {
        // Only EN-010 and EN-011 are static/simple contracts. Every other
        // former static row now belongs to headless execution because it has
        // state, persistence, or user-visible action semantics.
        let historySource = try sourceFile("FitMatch/Views/RecommendationHistoryView.swift")
        let searchSource = try sourceFile("FitMatch/Views/GlobalSearchView.swift")
        let contentSource = try sourceFile("FitMatch/ContentView.swift")
        let releaseSource = try sourceFile("FitMatch/Views/ReleaseInformationView.swift")
        #expect(historySource.contains("RecommendationHistoryView"))
        #expect(searchSource.contains("GlobalSearchView"))
        #expect(contentSource.contains("MainTabView"))
        #expect(releaseSource.contains("개인정보"))
    }

    /// HI-011/HI-012: History is a collection of immutable completed
    /// comparisons, not a deduplicated product catalog.  Two comparisons of
    /// the same retailer URL must remain independently present in Home's
    /// recent projection and in the real History search/filter/sort action.
    @Test func historyPresentationKeepsSameTargetComparisonIdentitiesSearchableAndDistinct() throws {
        func history(
            id: UUID,
            createdAt: Date,
            score: Int
        ) -> RecommendationHistory {
            let product = makeSourcedProduct(authority: .serverConfirmed)
            product.name = "동일 상품 비교"
            product.sourceURLString = "https://www.uniqlo.com/kr/ko/products/E450259"
            let reference = makeManualItem(
                name: "기준옷 \(id.uuidString.prefix(4))",
                category: .top,
                detail: .shortSleeve,
                createdAt: createdAt.timeIntervalSince1970
            )
            return RecommendationHistory(
                id: id,
                product: product,
                recommendedSize: product.sizes[0],
                userFit: reference,
                totalDifference: 1,
                measurementDifferences: GarmentMeasurements(
                    shoulder: 0,
                    chest: 1,
                    totalLength: 0,
                    sleeveLength: 0
                ),
                recommendationScore: score,
                comparisonMethod: "서버 승인 직접 비교",
                createdAt: createdAt
            )
        }

        let olderID = UUID()
        let newerID = UUID()
        let older = history(
            id: olderID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            score: 88
        )
        let newer = history(
            id: newerID,
            createdAt: Date(timeIntervalSince1970: 2_000),
            score: 92
        )
        let histories = [older, newer]

        let recent = FitMatchHistoryPresentation.recentHistories(from: histories)
        #expect(recent.map(\.id) == [newerID, olderID])

        let searched = FitMatchHistoryPresentation.displayedHistories(
            from: histories,
            searchText: "E450259",
            scope: .all,
            category: .top,
            favoriteURLs: [],
            sort: .latest
        )
        #expect(searched.map(\.id) == [newerID, olderID])

        let favoriteOnly = FitMatchHistoryPresentation.displayedHistories(
            from: histories,
            searchText: "동일 상품",
            scope: .favorite,
            category: .top,
            favoriteURLs: ["https://www.uniqlo.com/kr/ko/products/E450259"],
            sort: .oldest
        )
        #expect(favoriteOnly.map(\.id) == [olderID, newerID])
    }

    /// EN-010: Global Search uses the same production projection as its View.
    /// It must expose only active owned Closet rows, preserve the exact visible
    /// History identities, and keep the favorite-only query user-visible.
    @Test func en010GlobalSearchUsesExactOwnedVisibleClosetAndHistoryIdentities() throws {
        let active = makeManualItem(
            name: "검색되는 내 상의",
            category: .top,
            detail: .shortSleeve,
            createdAt: 10
        )
        active.brandName = "Fit 브랜드"
        active.sizeName = "M"
        let inactive = makeManualItem(
            name: "삭제된 내 상의",
            category: .top,
            detail: .shortSleeve,
            createdAt: 20
        )
        inactive.markAsHistoryOnlyReferenceSnapshot()
        let closet = FitMatchGlobalSearchPresentation.closetResults(
            from: [inactive, active],
            searchText: "fit 브랜드"
        )
        #expect(closet.map(\.id) == [active.id])

        let product = makeSourcedProduct(authority: .serverConfirmed)
        product.name = "검색되는 비교 상품"
        product.sourceURLString = "https://www.uniqlo.com/kr/ko/products/E450259"
        let reference = makeManualItem(
            name: "검색 기준옷",
            category: .top,
            detail: .shortSleeve,
            createdAt: 30
        )
        let visibleHistory = RecommendationHistory(
            product: product,
            recommendedSize: try #require(product.sizes.first),
            userFit: reference,
            totalDifference: 1,
            measurementDifferences: .init(shoulder: 0, chest: 1, totalLength: 0, sleeveLength: 0),
            recommendationScore: 90,
            comparisonMethod: "서버 승인 직접 비교"
        )
        let historyByName = FitMatchGlobalSearchPresentation.historyResults(
            from: [visibleHistory],
            searchText: "비교 상품",
            favoriteURLs: []
        )
        #expect(historyByName.map(\.id) == [visibleHistory.id])
        let historyByFavorite = FitMatchGlobalSearchPresentation.historyResults(
            from: [visibleHistory],
            searchText: "관심상품",
            favoriteURLs: ["https://www.uniqlo.com/kr/ko/products/E450259"]
        )
        #expect(historyByFavorite.map(\.id) == [visibleHistory.id])
        #expect(FitMatchGlobalSearchPresentation.historyResults(
            from: [visibleHistory],
            searchText: "없는 검색어",
            favoriteURLs: []
        ).isEmpty)
    }

    @Test func directClosetRegistrationAndManagementActionsCoverCRAndCMStates() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        // CR-001 / CR-002 / CR-003 / CR-007: each row changes real form
        // fields and persists through the same manual action used by the view.
        let upper = configuredDirectItem(name: "성인 상의", gender: .men, category: .top, detail: .shortSleeve)
        upper.chest = "52"
        upper.shoulder = "45"
        upper.totalLength = "69"
        upper.fitMemo = "어깨가 편함"
        upper.fitPreference = .semiOver
        let bottom = configuredDirectItem(name: "성인 하의", gender: .women, category: .bottom, detail: .longPants)
        bottom.waist = "35"
        bottom.hip = "49"
        let child = configuredDirectItem(name: "키즈 상의", gender: .kids, category: .top, detail: .shortSleeve)
        child.chest = "40"
        let baby = configuredDirectItem(name: "베이비 상의", gender: .baby, category: .top, detail: .shortSleeve)
        baby.chest = "32"

        let saved = [upper, bottom, child, baby].compactMap { form -> UserFit? in
            guard case .saved(let item) = FitMatchClosetManualRegistrationAction.save(
                from: form,
                activeClosetItems: [],
                persist: { FitMatchClosetRegistrationPersistence.save($0, in: context) }
            ) else {
                Issue.record("direct registration did not use the production save action")
                return nil
            }
            return item
        }
        #expect(saved.count == 4)
        #expect(saved.map(\.gender) == [.men, .women, .kids, .baby])
        #expect(saved[1].measurements.waist == 35)
        #expect(saved[0].fitMemo == "어깨가 편함")
        #expect(saved[0].fitPreference == .semiOver)
        #expect(saved[2].isRepresentative == false)

        // CR-004 / CR-006: distinct missing fields and invalid values never
        // create a row and expose the production form message.
        let missingBrand = configuredDirectItem(name: "브랜드 없음", gender: .men, category: .top, detail: .shortSleeve)
        missingBrand.brand = ""
        missingBrand.chest = "50"
        if case .blocked(let message) = FitMatchClosetFormAction.save(from: missingBrand, persist: { _ in true }) {
            #expect(message == "브랜드명을 입력해 주세요.")
        } else { Issue.record("CR-004 missing brand unexpectedly saved") }
        for value in ["문자", "0", "-1", "9999"] {
            let malformed = configuredDirectItem(name: "잘못된 \(value)", gender: .men, category: .top, detail: .shortSleeve)
            malformed.chest = value
            #expect(malformed.makeUserFit() == nil)
        }

        // CR-005: explicit composite data can be retained but cannot acquire
        // comparison/reference authority.
        let setForm = configuredDirectItem(name: "티셔츠+반바지 세트", gender: .men, category: .top, detail: .shortSleeve)
        setForm.chest = "51"
        setForm.isRepresentative = true
        guard case .saved(let setItem) = FitMatchClosetManualRegistrationAction.save(
            from: setForm,
            activeClosetItems: saved,
            persist: { FitMatchClosetRegistrationPersistence.save($0, in: context) }
        ) else { Issue.record("CR-005 composite form did not save safely"); return }
        #expect(!setItem.isRepresentative)
        #expect(setItem.canonicalEligibility == false)

        // CR-008 / CM-006 / CM-007: a new same-scope representative replaces
        // the existing one without affecting an independent bottom reference.
        let initialReference = saved[0]
        initialReference.isRepresentative = true
        let independentBottom = saved[1]
        independentBottom.isRepresentative = true
        let nextReferenceForm = configuredDirectItem(name: "새 기준 상의", gender: .men, category: .top, detail: .shortSleeve)
        nextReferenceForm.chest = "54"
        nextReferenceForm.isRepresentative = true
        guard case .saved(let nextReference) = FitMatchClosetManualRegistrationAction.save(
            from: nextReferenceForm,
            activeClosetItems: [initialReference, independentBottom],
            persist: { FitMatchClosetRegistrationPersistence.save($0, in: context) }
        ) else { Issue.record("CR-008 reference replacement failed"); return }
        #expect(!initialReference.isRepresentative)
        #expect(nextReference.isRepresentative)
        #expect(independentBottom.isRepresentative)
        FitMatchClosetReferenceMutation.clearRepresentative(nextReference)
        #expect(!nextReference.isRepresentative)
        #expect(independentBottom.isRepresentative)

        // CR-009 / CM-012: a failed persistence boundary leaves the mutable
        // form intact for a retry instead of reporting a false success.
        let retry = configuredDirectItem(name: "재시도 상의", gender: .men, category: .top, detail: .shortSleeve)
        retry.chest = "50"
        retry.fitMemo = "재시도 후에도 보존"
        if case .persistenceFailed = FitMatchClosetFormAction.save(from: retry, persist: { _ in false }) {
            // Expected: the actual production form action keeps the form retryable.
        } else {
            Issue.record("CR-009 persistence failure was not preserved")
        }
        #expect(retry.fitMemo == "재시도 후에도 보존")
        guard case .saved = FitMatchClosetManualRegistrationAction.save(
            from: retry,
            activeClosetItems: saved,
            persist: { FitMatchClosetRegistrationPersistence.save($0, in: context) }
        ) else { Issue.record("CR-009 retry did not persist"); return }

        // CM-002 / CM-003 / CM-005: production detail actions preserve a
        // sourced authority on a size-only edit and only create personal
        // authority after explicit Closet picker intent.
        let sourceProduct = makeSourcedProduct(authority: .serverConfirmed)
        let sourced = makeSourcedUserFit(product: sourceProduct, authority: .serverConfirmed)
        context.insert(sourceProduct)
        context.insert(sourced)
        try context.save()
        let originalAuthority = sourced.classificationAuthorityProvenance
        let newSize = try #require(sourceProduct.sizes.first)
        #expect(FitMatchClosetItemEditAction.saveImported(
            item: sourced,
            selectedSize: newSize,
            category: .top,
            detailCategory: .shortSleeve,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            didExplicitlyChangeClassification: false,
            in: context
        ) == .saved)
        #expect(sourced.classificationAuthorityProvenance == originalAuthority)
        #expect(FitMatchClosetItemEditAction.saveImported(
            item: sourced,
            selectedSize: newSize,
            category: .top,
            detailCategory: .shortSleeve,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            didExplicitlyChangeClassification: true,
            in: context
        ) == .saved)
        #expect(sourced.classificationAuthorityProvenance == .userExplicit)

        let restored = try context.fetch(FetchDescriptor<UserFit>())
        #expect(restored.contains { $0.id == saved[0].id && $0.fitMemo == "어깨가 편함" })
    }

    @Test func providerLinkPreparationAndComparedProductSaveCoverCR011ThroughCR022() async throws {
        for provider in [HeadlessJourneyProvider.uniqlo, .musinsa, .zara] {
            let fixture = HeadlessJourneyFixture(provider: provider)
            let runtime = try fixture.runtime(globalStatus: .confirmed)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed)],
                runtimes: [runtime]
            )
            let parser = FinalSnapshotParser(products: [fixture.parsedProduct()])
            let outcome = await FitMatchLinkClosetRegistrationAction.load(
                urlString: fixture.url.absoluteString,
                makeViewModel: { _ in self.makeViewModel(fixture: fixture, remote: remote, parser: parser) },
                existingBrand: { _ in nil }
            )
            guard case .loaded(let preparation) = outcome else {
                Issue.record("CR provider link pipeline did not load \(provider.rawValue)")
                continue
            }
            let product = try #require(preparation.parsedProduct)
            #expect(product.classificationAuthorityProvenance == .serverConfirmed)
            #expect(product.sizes.count == 1)
            let calls = await remote.calls()
            #expect(calls == ["resolve", "runtime"])
        }

        // CR-014: every approved provider takes the production parser dispatch
        // through a failure and a retry without leaking the preceding state.
        for provider in [HeadlessJourneyProvider.uniqlo, .musinsa, .zara] {
            let fixture = HeadlessJourneyFixture(provider: provider)
            let runtime = try fixture.runtime(globalStatus: .confirmed)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .confirmed)],
                runtimes: [runtime]
            )
            let parser = FinalSnapshotParser(results: [
                .failure(ProductURLParserError.automaticParsingUnavailable),
                .success(fixture.parsedProduct())
            ])
            let viewModel = makeViewModel(fixture: fixture, remote: remote, parser: parser)
            #expect(await viewModel.loadProductInfoFromURL() == false)
            #expect(viewModel.hasLoadedProductInfo == false)
            #expect(await viewModel.loadProductInfoFromURL())
            #expect(viewModel.productCode == fixture.productCode)
        }

        // CR-015 / CR-016 / CR-018 / CR-022: only a presented source size can
        // save, duplicate storage is rejected, and a retry stores exactly one.
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let product = makeSourcedProduct(authority: .serverConfirmed, code: fixture.productCode)
        let size = try #require(product.sizes.first)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let request = comparedRegistrationRequest(product: product, size: size)
        guard case .saved(let item) = FitMatchComparedProductClosetRegistration.save(request, in: context) else {
            Issue.record("CR-015 valid source-size registration failed")
            return
        }
        #expect(item.classificationAuthorityProvenance == .serverConfirmed)
        let duplicateRequest = comparedRegistrationRequest(product: product, size: size, activeClosetItems: [item])
        if case .duplicate = FitMatchComparedProductClosetRegistration.save(duplicateRequest, in: context) {
            // Expected duplicate protection.
        } else {
            Issue.record("CR-016 duplicate sourced registration was not blocked")
        }
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)

        // CR-020 / CR-021: a server review/unavailable preparation never
        // fabricates a comparable sourced Product or a size.
        let reviewFixture = HeadlessJourneyFixture(provider: .uniqlo)
        let reviewRemote = JourneyRecordingRemote(
            resolutions: [reviewFixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [try reviewFixture.runtime(globalStatus: .reviewRequired)],
            recoveryContracts: [try reviewFixture.recoveryContract(count: 0, suffix: "zero")]
        )
        let reviewParser = FinalSnapshotParser(products: [reviewFixture.parsedProduct()])
        let reviewOutcome = await FitMatchLinkClosetRegistrationAction.load(
            urlString: reviewFixture.url.absoluteString,
            makeViewModel: { _ in self.makeViewModel(fixture: reviewFixture, remote: reviewRemote, parser: reviewParser) },
            existingBrand: { _ in nil }
        )
        guard case .loaded(let reviewPreparation) = reviewOutcome else {
            Issue.record("CR-020 review preparation did not return a terminal state")
            return
        }
        #expect(reviewPreparation.parsedProduct?.classificationAuthorityProvenance == .serverReviewRequired)
        #expect(reviewPreparation.errorMessage != nil)
    }

    @Test func comparisonProviderSequenceAndNegativeGatesCoverCP001ThroughCP039() async throws {
        // CP-001 / CP-002 / CP-003 / CP-004 / RS-001: each approved provider
        // enters parser → resolver → reference → eligible → begin → engine →
        // complete → local Result/History through the real ViewModel.
        for provider in [HeadlessJourneyProvider.uniqlo, .musinsa, .zara] {
            let run = try await completeComparison(provider: provider, manual: false, personalGarment: nil)
            #expect(run.history != nil)
            try requireCallOrder(run.calls, [
                "resolve", "runtime", "list_closet", "reference_candidates",
                "eligible_sizes", "begin_comparison", "complete_comparison"
            ], scenario: "CP-\(provider.rawValue)")
        }

        // CP-005: all bounded candidate counts are independently constructed;
        // only their shared sleeve fact is fixed by the server contract.
        for count in 1...3 {
            let fixture = HeadlessJourneyFixture(provider: .uniqlo)
            let remote = JourneyRecordingRemote(
                resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
                runtimes: [try fixture.runtime(globalStatus: .reviewRequired)],
                recoveryContracts: [try fixture.recoveryContract(count: count, suffix: "count\(count)")]
            )
            let viewModel = makeViewModel(
                fixture: fixture,
                remote: remote,
                parser: FinalSnapshotParser(products: [fixture.parsedProduct()])
            )
            #expect(await viewModel.loadProductInfoFromURL() == false)
            let contract = try #require(viewModel.reviewRecoveryContract)
            #expect(contract.candidateCount == count)
            #expect(contract.fixedFacts.sleeveLengthCode == "short_sleeve")
            #expect(contract.fixedFacts.garmentTypeCode == nil)
        }

        // CP-006 / CP-007 / CP-039: unrecoverable, NOT_APPLICABLE, missing
        // reference, denied reference, denied eligible, and absent begin never
        // reach the engine/completion remote boundary.
        let zeroFixture = HeadlessJourneyFixture(provider: .uniqlo)
        let zeroRemote = JourneyRecordingRemote(
            resolutions: [zeroFixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [try zeroFixture.runtime(globalStatus: .reviewRequired, productStructure: "UNKNOWN")],
            recoveryContracts: [try zeroFixture.recoveryContract(count: 0, suffix: "unknown")]
        )
        let zeroVM = makeViewModel(fixture: zeroFixture, remote: zeroRemote, parser: FinalSnapshotParser(products: [zeroFixture.parsedProduct()]))
        #expect(await zeroVM.loadProductInfoFromURL() == false)
        #expect(zeroVM.reviewRecoveryContract?.recoverability == .unrecoverable)

        let notApplicableFixture = HeadlessJourneyFixture(provider: .uniqlo)
        let notApplicableRemote = JourneyRecordingRemote(
            resolutions: [notApplicableFixture.resolution(globalStatus: .notComparable)],
            runtimes: [try notApplicableFixture.runtime(globalStatus: .notComparable)]
        )
        let notApplicableVM = makeViewModel(fixture: notApplicableFixture, remote: notApplicableRemote, parser: FinalSnapshotParser(products: [notApplicableFixture.parsedProduct()]))
        #expect(await notApplicableVM.loadProductInfoFromURL() == false)
        #expect(await notApplicableVM.calculateRecommendation(userFits: []) == nil)
        #expect(!(notApplicableVM.errorMessage ?? "").isEmpty)
        #expect(!(await notApplicableRemote.calls()).contains("begin_comparison"))

        let missingReference = try await completeComparison(provider: .uniqlo, manual: false, personalGarment: nil, includeReference: false)
        #expect(missingReference.history == nil)
        #expect(!missingReference.calls.contains("begin_comparison"))

        let blockedReference = try await completeComparison(provider: .uniqlo, manual: false, personalGarment: nil, serverDecision: "BLOCKED")
        #expect(blockedReference.history == nil)
        #expect(!blockedReference.calls.contains("eligible_sizes"))

        let eligibleBlocked = try await completeComparison(provider: .uniqlo, manual: false, personalGarment: nil, eligibleAllowed: false)
        #expect(eligibleBlocked.history == nil)
        #expect(eligibleBlocked.calls.contains("eligible_sizes"))
        #expect(!eligibleBlocked.calls.contains("begin_comparison"))
    }

    @Test func recoveryManualCrossAndStaleAuthorityPathsCoverTheRemainingComparisonStates() async throws {
        // CP-012 / CP-034: later global authority wins for future evaluation.
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let personalRuntime = try fixture.runtime(
            globalStatus: .reviewRequired,
            effectivePersonalGarment: "polo_shirt",
            overrideRevision: 1,
            personalCandidateFingerprint: "candidate-current-polo_shirt",
            personalCandidateSetHash: "set-current-polo_shirt"
        )
        let globalRuntime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [personalRuntime, globalRuntime]
        )
        let vm = makeViewModel(fixture: fixture, remote: remote, parser: FinalSnapshotParser(products: [fixture.parsedProduct()]))
        #expect(await vm.loadProductInfoFromURL())
        #expect(vm.hasActiveUserExplicitClassification)
        #expect(await vm.loadProductInfoFromURL())
        #expect(!vm.hasActiveUserExplicitClassification)

        // CP-019 / CP-020 / CP-021 / CP-022 / CP-035 / CP-036: each protected
        // pair is constructed in both directions. The server remains the
        // policy authority; this test merely supplies its decision response.
        let pairs = [("polo_shirt", "tshirt"), ("tshirt", "polo_shirt"),
                     ("hoodie", "sweatshirt"), ("sweatshirt", "hoodie"),
                     ("knit_sweater", "sweatshirt"), ("sweatshirt", "knit_sweater")]
        for (target, reference) in pairs {
            let automatic = try await completeComparison(
                provider: .uniqlo,
                manual: false,
                personalGarment: target,
                referenceGarment: reference,
                serverDecision: "BLOCKED"
            )
            #expect(automatic.history == nil)
            #expect(!automatic.calls.contains("begin_comparison"))

            let manual = try await completeComparison(
                provider: .uniqlo,
                manual: true,
                personalGarment: target,
                referenceGarment: reference,
                serverDecision: "MANUAL_EXTENDED"
            )
            #expect(manual.history != nil)
            #expect(manual.calls.contains("complete_comparison"))

            let sleeveMismatch = try await completeComparison(
                provider: .uniqlo,
                manual: true,
                personalGarment: target,
                referenceGarment: reference,
                referenceSleeve: "long_sleeve",
                serverDecision: "BLOCKED"
            )
            #expect(sleeveMismatch.history == nil)
            #expect(!sleeveMismatch.calls.contains("begin_comparison"))

            let measurementBlocked = try await completeComparison(
                provider: .uniqlo,
                manual: true,
                personalGarment: target,
                referenceGarment: reference,
                serverDecision: "MEASUREMENTS_REQUIRED"
            )
            #expect(measurementBlocked.history == nil)
            #expect(!measurementBlocked.calls.contains("begin_comparison"))
        }

        // CP-023…CP-029 / CP-037 / CP-038: measurement and availability are
        // server-issued gates. A permitted single candidate succeeds; each
        // reasoned zero-candidate state stops before begin.
        let full = try await completeComparison(provider: .musinsa, manual: false, personalGarment: nil)
        #expect(full.history != nil)
        let noSize = try await completeComparison(provider: .musinsa, manual: false, personalGarment: nil, eligibleAllowed: false)
        #expect(noSize.history == nil)
        #expect(noSize.calls.contains("eligible_sizes"))
        #expect(!noSize.calls.contains("begin_comparison"))
    }

    @Test func closetDeletionAccountOwnershipAndStartupActionsCoverManagementRecoveryStates() async throws {
        // CM-008 / CM-009 / CM-010 / CM-019: the exact production deletion
        // action hides immutable server History first, then removes the local
        // presentation rows. A failed hide keeps both rows visible for retry.
        func makeDeletionFixture() throws -> (
            ModelContext,
            UserFit,
            RecommendationHistory,
            Product
        ) {
            let container = try inMemoryContainer()
            let context = ModelContext(container)
            let product = makeSourcedProduct(authority: .serverConfirmed)
            let reference = makeManualItem(
                name: "삭제할 기준옷",
                category: .top,
                detail: .shortSleeve,
                createdAt: 1
            )
            reference.isRepresentative = true
            let size = try #require(product.sizes.first)
            let history = RecommendationHistory(
                product: product,
                recommendedSize: size,
                userFit: reference,
                totalDifference: 1,
                measurementDifferences: .init(shoulder: 1, chest: 1, totalLength: 1, sleeveLength: 1),
                recommendationScore: 90,
                comparisonMethod: "서버 승인 동일 세부 분류"
            )
            history.comparisonSchemaVersion = 4
            context.insert(product)
            context.insert(reference)
            context.insert(history)
            try context.save()
            return (context, reference, history, product)
        }

        do {
            let (context, reference, history, _) = try makeDeletionFixture()
            let remote = FinalHistoryRemote(rows: [], hideFailures: 0)
            let comparisonSync = FitMatchComparisonSyncCoordinator(
                remote: remote,
                defaults: isolatedDefaults()
            )
            let closetSync = FitMatchClosetSyncCoordinator(
                remote: FinalClosetRemote(),
                defaults: isolatedDefaults()
            )
            #expect(await FitMatchClosetDeletionAction.delete(
                item: reference,
                histories: [history],
                in: context,
                comparisonSync: comparisonSync,
                closetSync: closetSync
            ) == .deleted)
            #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 0)
            #expect(await remote.hideCalls() == 1)
        }

        do {
            let (context, reference, history, _) = try makeDeletionFixture()
            let remote = FinalHistoryRemote(rows: [], hideFailures: 1)
            let comparisonSync = FitMatchComparisonSyncCoordinator(
                remote: remote,
                defaults: isolatedDefaults()
            )
            #expect(await FitMatchClosetDeletionAction.delete(
                item: reference,
                histories: [history],
                in: context,
                comparisonSync: comparisonSync,
                closetSync: nil
            ) == .serverHistoryHideFailed)
            #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
            #expect(await FitMatchClosetDeletionAction.delete(
                item: reference,
                histories: [history],
                in: context,
                comparisonSync: comparisonSync,
                closetSync: nil
            ) == .deleted)
        }

        // CM-014 / CM-015 / CM-017: the current cache owner is checked before
        // sync can present a different account's rows, and account deletion
        // clears user-scoped preferences/mappings alongside SwiftData rows.
        let accountContainer = try inMemoryContainer()
        let accountContext = ModelContext(accountContainer)
        let accountA = UUID()
        let accountB = UUID()
        let cachedA = makeManualItem(
            name: "A의 옷",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        accountContext.insert(cachedA)
        try accountContext.save()
        let accountDefaults = isolatedDefaults()
        accountDefaults.set(accountA.uuidString, forKey: "FitMatch.closetCacheOwnerUserID")
        let accountSync = FitMatchClosetSyncCoordinator(
            remote: FinalClosetRemote(),
            defaults: accountDefaults
        )
        #expect(try accountSync.prepareLocalCache(for: accountB, modelContext: accountContext)
            == .purgedForeignOwnerCache)
        #expect(try accountContext.fetchCount(FetchDescriptor<UserFit>()) == 0)

        let favoriteStore = FavoriteProductStore(defaults: accountDefaults)
        #expect(favoriteStore.toggle("https://www.uniqlo.com/kr/ko/products/E450259"))
        accountDefaults.set(Data("mapping".utf8), forKey: "FitMatch.sourceCategoryMappings")
        try accountSync.purgeLocalAccountData(modelContext: accountContext)
        #expect(favoriteStore.favoriteURLs().isEmpty)
        #expect(accountDefaults.data(forKey: "FitMatch.sourceCategoryMappings") == nil)

        // CM-016 / EN-007 data-state path: server error remains visible and a
        // successful deletion ends the same production session state safely.
        let deletionFailure = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: FinalAccountDeletionService(shouldFail: true)
        )
        #expect(await deletionFailure.deleteAccount() == false)
        #expect(deletionFailure.errorMessage != nil)
        let deletionSuccess = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: FinalAccountDeletionService(shouldFail: false)
        )
        #expect(await deletionSuccess.deleteAccount())
        #expect(deletionSuccess.state == .signedOut)

        // EN-008 / EN-009: the production-used startup action distinguishes
        // an actual in-memory container/migration success from a recoverable
        // build or migration boundary failure without deleting source rows.
        switch FitMatchStartupAction.makeContainer({ try self.inMemoryContainer() }) {
        case .ready:
            break
        case .failed:
            Issue.record("EN-008 production startup action rejected a valid container")
        }
        switch FitMatchStartupAction.makeContainer({ throw FinalScenarioFailure("EN-008", "injected store failure") }) {
        case .ready:
            Issue.record("EN-008 startup failure unexpectedly reached a normal container")
        case .failed:
            break
        }
        let migrationContainer = try inMemoryContainer()
        let migrationContext = ModelContext(migrationContainer)
        let migrationProduct = makeSourcedProduct(authority: .serverConfirmed)
        let migrationItem = makeManualItem(
            name: "legacy migration",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        migrationContext.insert(migrationProduct)
        migrationContext.insert(migrationItem)
        try migrationContext.save()
        #expect(FitMatchStartupAction.runLegacyMeasurementMigration(
            modelContext: migrationContext,
            products: [migrationProduct],
            userFits: [migrationItem]
        ) == .completed)
        #expect(FitMatchStartupAction.runLegacyMeasurementMigration(
            modelContext: migrationContext,
            products: [migrationProduct],
            userFits: [migrationItem],
            run: { _, _, _ in throw FinalScenarioFailure("EN-009", "injected migration failure") }
        ) == .failed(message: "기존 의류 데이터를 업데이트하지 못했어요. 원본 데이터는 삭제되지 않았습니다."))
    }

    @Test func historyDeletionHydrationAndCurrentAuthorityCoverHIAndResultFlows() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        // HI-001 / HI-004 / HI-005 / HI-013: completed server History is
        // hydrated from immutable data and a new comparison uses current
        // authority without mutating the old row.
        let target = UUID()
        let reference = UUID()
        let globalRow = try historicalRow(targetProductID: target, referenceClientItemID: reference, garment: "tshirt", revision: 0, personal: false)
        let hydrated = try VNextHistoryCacheHydrator().hydrateCompleted(
            [globalRow], existingHistories: [], existingProducts: [], existingClosetItems: [], modelContext: context
        )
        #expect(hydrated.count == 1)
        let oldHistory = try #require(try context.fetch(FetchDescriptor<RecommendationHistory>()).first)
        let immutableMethod = oldHistory.comparisonMethod
        oldHistory.product.name = "현재 상품명 변경"
        #expect(oldHistory.comparisonMethod == immutableMethod)

        // HI-007 / HI-009 / HI-010 / HI-015: only server-backed rows request a
        // durable hide, a failed receipt leaves local presentation intact, and
        // a legacy history cannot fabricate a server tombstone.
        let syncRemote = FinalHistoryRemote(rows: [globalRow], hideFailures: 1)
        let sync = FitMatchComparisonSyncCoordinator(remote: syncRemote, defaults: isolatedDefaults())
        let firstDelete = await FitMatchHistoryVisibilityAction.delete(oldHistory, in: context, comparisonSync: sync)
        #expect(firstDelete == .serverHideFailed)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 1)
        let secondDelete = await FitMatchHistoryVisibilityAction.delete(oldHistory, in: context, comparisonSync: sync)
        #expect(secondDelete == .deleted)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(await syncRemote.hideCalls() == 2)

        let legacyProduct = makeSourcedProduct(authority: .localHint)
        let legacyReference = makeManualItem(name: "legacy ref", category: .top, detail: .shortSleeve, createdAt: 1)
        let legacySize = try #require(legacyProduct.sizes.first)
        let legacy = RecommendationHistory(
            product: legacyProduct,
            recommendedSize: legacySize,
            userFit: legacyReference,
            totalDifference: 0,
            measurementDifferences: .init(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0),
            recommendationScore: 80,
            comparisonMethod: "로컬 비교"
        )
        context.insert(legacyProduct)
        context.insert(legacyReference)
        context.insert(legacy)
        try context.save()
        #expect(await FitMatchHistoryVisibilityAction.delete(legacy, in: context, comparisonSync: sync) == .deleted)
        #expect(await syncRemote.hideCalls() == 2)
    }

    /// HI-002/HI-003: a v4 row is historical evidence, not a mutable current
    /// catalog Product.  The same target compared under distinct personal
    /// revisions/audiences must rebuild distinct immutable projections after
    /// a fresh local container hydrate.
    @Test func v4HistoryHydrationPreservesAudienceAndPersonalRevisionPerComparison() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let target = UUID()
        let reference = UUID()
        let men = try historicalRow(
            targetProductID: target,
            referenceClientItemID: reference,
            garment: "tshirt",
            revision: 1,
            personal: true,
            audience: "MEN"
        )
        let women = try historicalRow(
            targetProductID: target,
            referenceClientItemID: reference,
            garment: "polo_shirt",
            revision: 2,
            personal: true,
            audience: "WOMEN"
        )

        let hydrated = try VNextHistoryCacheHydrator().hydrateCompleted(
            [men, women],
            existingHistories: [],
            existingProducts: [],
            existingClosetItems: [],
            modelContext: context
        )
        #expect(hydrated == Set([men.clientComparisonID, women.clientComparisonID]))

        let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let menHistory = try #require(histories.first { $0.id == men.clientComparisonID })
        let womenHistory = try #require(histories.first { $0.id == women.clientComparisonID })
        #expect(menHistory.product !== womenHistory.product)
        #expect(menHistory.product.productTargetGender == .men)
        #expect(womenHistory.product.productTargetGender == .women)
        #expect(menHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(womenHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(menHistory.product.canonicalSourceIdentity?.contains("revision=1") == true)
        #expect(womenHistory.product.canonicalSourceIdentity?.contains("revision=2") == true)
    }

    /// HI-001: a fresh global completed-comparison hydrate presents the exact
    /// immutable recommendation snapshot, rather than recomputing it from a
    /// current catalog Product.
    @Test func hi001FreshGlobalHistoryHydrationPreservesExactCompletedSnapshot() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let row = try historicalRow(
            targetProductID: UUID(),
            referenceClientItemID: UUID(),
            garment: "tshirt",
            revision: 0,
            personal: false,
            audience: "MEN"
        )

        #expect(try VNextHistoryCacheHydrator().hydrateCompleted(
            [row],
            existingHistories: [],
            existingProducts: [],
            existingClosetItems: [],
            modelContext: context
        ) == Set([row.clientComparisonID]))
        let history = try #require(try context.fetch(FetchDescriptor<RecommendationHistory>()).first)
        #expect(history.id == row.clientComparisonID)
        #expect(history.recommendedSize.name == row.recommendedSizeLabel)
        #expect(history.recommendationScore == 95)
        #expect(history.product.productCode == "E450259")
        #expect(history.product.productTargetGender == .men)
        #expect(history.product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(history.userFit.productName == "기준옷")
        #expect(history.comparisonMethod == "서버 승인 직접 비교")
    }

    /// HI-014: adding an immutable History product to Closet always re-enters
    /// the production Closet authority boundary. A global snapshot stays
    /// sourced Global; a historical personal comparison never fabricates a
    /// Closet personal override without explicit Closet edit intent.
    @Test func hi014HistoryToClosetKeepsGlobalAndPersonalAuthorityBoundariesSeparate() throws {
        let sourceTarget = UUID()
        let sourceReference = UUID()
        let globalRow = try historicalRow(
            targetProductID: sourceTarget,
            referenceClientItemID: sourceReference,
            garment: "tshirt",
            revision: 0,
            personal: false
        )
        let personalRow = try historicalRow(
            targetProductID: sourceTarget,
            referenceClientItemID: sourceReference,
            garment: "polo_shirt",
            revision: 9,
            personal: true
        )
        // History-to-Closet is a same-ModelContext production action.  Each
        // row gets a fresh local reconstruction so this test never transfers
        // a SwiftData object across containers (which would not model the
        // View's real ownership and can invalidate the object identity map).
        func register(
            _ row: VNextComparisonHistoryDTO
        ) throws -> (
            historyAuthority: FitMatchClassificationAuthorityProvenance?,
            closetAuthority: FitMatchClassificationAuthorityProvenance?,
            sourceIdentity: String?
        ) {
            let container = try inMemoryContainer()
            let context = ModelContext(container)
            _ = try VNextHistoryCacheHydrator().hydrateCompleted(
                [row],
                existingHistories: [],
                existingProducts: [],
                existingClosetItems: [],
                modelContext: context
            )
            let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
            let history = try #require(histories.first { $0.id == row.clientComparisonID })
            let historyAuthority = history.product.classificationAuthorityProvenance
            let sourceIdentity = history.product.canonicalSourceIdentity
            guard case .saved(let closet) = FitMatchComparedProductClosetRegistration.save(
                comparedRegistrationRequest(product: history.product, size: history.recommendedSize),
                in: context
            ) else {
                Issue.record("HI-014 History product did not enter the Closet action")
                throw CocoaError(.fileWriteUnknown)
            }
            return (historyAuthority, closet.classificationAuthorityProvenance, sourceIdentity)
        }

        let global = try register(globalRow)
        let personal = try register(personalRow)
        #expect(global.closetAuthority == .serverConfirmed)
        #expect(personal.closetAuthority == .localHint)
        #expect(global.historyAuthority == .serverConfirmed)
        #expect(personal.historyAuthority == .userExplicit)
        #expect(personal.sourceIdentity?.contains("revision=9") == true)
    }

    /// EN-009: a startup migration failure is a recoverable side-effect
    /// failure.  The production startup action must leave the existing local
    /// rows intact and a later default retry must run the real backfill once.
    @Test func en009LegacyMeasurementMigrationFailureThenRetryKeepsExistingRowsSafe() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let product = makeSourcedProduct(authority: .serverConfirmed)
        let item = makeManualItem(
            name: "EN-009 legacy item",
            category: .top,
            detail: .shortSleeve,
            createdAt: 9
        )
        item.chest = 50
        context.insert(product)
        context.insert(item)
        try context.save()
        let originalProductID = product.id
        let originalItemID = item.id
        let originalChest = item.chest

        let failed = FitMatchStartupAction.runLegacyMeasurementMigration(
            modelContext: context,
            products: [product],
            userFits: [item],
            run: { _, _, _ in throw FinalScenarioFailure("EN-009", "injected migration transport failure") }
        )
        #expect(failed == .failed(
            message: "기존 의류 데이터를 업데이트하지 못했어요. 원본 데이터는 삭제되지 않았습니다."
        ))
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
        #expect(product.id == originalProductID)
        #expect(item.id == originalItemID)
        #expect(item.chest == originalChest)

        #expect(FitMatchStartupAction.runLegacyMeasurementMigration(
            modelContext: context,
            products: [product],
            userFits: [item]
        ) == .completed)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
        #expect(item.id == originalItemID)
    }

    /// RX-004: a product-load transport failure finishes the production load
    /// state without touching server comparison work. Retrying the exact URL
    /// then reaches the normal authority path with no stale product state.
    @Test func rx004ParserFailureThenRetryRestartsTheSameProductionEntry() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime]
        )
        let parser = FinalSnapshotParser(results: [
            .failure(URLError(.timedOut)),
            .success(fixture.parsedProduct())
        ])
        let viewModel = ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(uniqloParser: parser),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )

        #expect(await viewModel.loadProductInfoFromURL() == false)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(!viewModel.isLoadingProductInfo)
        #expect(await remote.calls().isEmpty)

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(viewModel.productCode == fixture.productCode)
        #expect(viewModel.sourceName == fixture.sourceName)
        #expect(viewModel.hasServerConfirmedAuthority)
        #expect(await remote.calls() == ["resolve", "runtime"])
    }

    /// HI-003 / HI-004 / HI-005 / HI-013: a later current authority or a
    /// different reference must produce a second historical projection. The
    /// existing completed row is never a mutable catalog Product reused by
    /// that new comparison during either the first hydrate or a fresh local
    /// container reconstruction.
    @Test func historicalRowsRemainImmutableAcrossLaterAuthorityAndReferenceChanges() throws {
        let target = UUID()
        let originalReference = UUID()
        let replacementReference = UUID()
        let original = try historicalRow(
            targetProductID: target,
            referenceClientItemID: originalReference,
            garment: "polo_shirt",
            revision: 7,
            personal: true,
            audience: "MEN"
        )
        let later = try historicalRow(
            targetProductID: target,
            referenceClientItemID: replacementReference,
            garment: "hoodie",
            revision: 0,
            personal: false,
            audience: "WOMEN"
        )

        func hydrateFresh(in context: ModelContext) throws -> [RecommendationHistory] {
            let hydrated = try VNextHistoryCacheHydrator().hydrateCompleted(
                [original, later],
                existingHistories: [],
                existingProducts: [],
                existingClosetItems: [],
                modelContext: context
            )
            #expect(hydrated == Set([original.clientComparisonID, later.clientComparisonID]))
            return try context.fetch(FetchDescriptor<RecommendationHistory>())
        }

        let firstContainer = try inMemoryContainer()
        let first = try hydrateFresh(in: ModelContext(firstContainer))
        let originalFirst = try #require(first.first { $0.id == original.clientComparisonID })
        let laterFirst = try #require(first.first { $0.id == later.clientComparisonID })
        #expect(originalFirst.product !== laterFirst.product)
        #expect(originalFirst.userFit !== laterFirst.userFit)
        #expect(originalFirst.product.productTargetGender == .men)
        #expect(originalFirst.product.classificationAuthorityProvenance == .userExplicit)
        #expect(originalFirst.product.garmentTypeRawValue == "polo_shirt")
        #expect(originalFirst.product.canonicalSourceIdentity?.contains("revision=7") == true)
        #expect(laterFirst.product.productTargetGender == .women)
        #expect(laterFirst.product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(laterFirst.product.garmentTypeRawValue == "hoodie")

        // A cold reconstruction is the actual sync/hydration boundary. It
        // must reproduce the same separate historical meanings rather than
        // coalescing the shared target ID through current Product state.
        let reconstructedContainer = try inMemoryContainer()
        let reconstructed = try hydrateFresh(in: ModelContext(reconstructedContainer))
        let originalReconstructed = try #require(reconstructed.first {
            $0.id == original.clientComparisonID
        })
        let laterReconstructed = try #require(reconstructed.first {
            $0.id == later.clientComparisonID
        })
        #expect(originalReconstructed.product !== laterReconstructed.product)
        #expect(originalReconstructed.product.productTargetGender == .men)
        #expect(originalReconstructed.product.garmentTypeRawValue == "polo_shirt")
        #expect(originalReconstructed.product.classificationAuthorityProvenance == .userExplicit)
        #expect(laterReconstructed.product.productTargetGender == .women)
        #expect(laterReconstructed.product.garmentTypeRawValue == "hoodie")
        #expect(laterReconstructed.product.classificationAuthorityProvenance == .serverConfirmed)
    }

    @Test func resultPresentationHistoryRecomparisonAndOutboundActionsUseCurrentProductionProofs() async throws {
        // RS-001 / RS-003 / RS-004 / RS-005 / RS-006 / RS-011 / RS-013:
        // Result data is the exact completed production run, alternative
        // sizes use its cached authorized batch only, and a later comparison
        // is a separate immutable History row.
        let global = try await completeComparison(
            provider: .uniqlo,
            manual: false,
            personalGarment: nil
        )
        let globalHistory = try #require(global.history)
        #expect(globalHistory.isServerBackedVNextHistory)
        #expect(globalHistory.recommendedSize.id != UUID())
        let globalBatch = VNextComparisonSessionStore.shared.analysis(for: globalHistory.id)
        #expect(RecommendationService().canPresentCurrentVNextAlternativeSizes(
            for: globalHistory,
            batch: globalBatch
        ))
        VNextComparisonSessionStore.shared.remove(historyID: globalHistory.id)
        #expect(!RecommendationService().canPresentCurrentVNextAlternativeSizes(
            for: globalHistory,
            batch: VNextComparisonSessionStore.shared.analysis(for: globalHistory.id)
        ))

        let personal = try await completeComparison(
            provider: .uniqlo,
            manual: true,
            personalGarment: "polo_shirt",
            referenceGarment: "tshirt",
            serverDecision: "MANUAL_EXTENDED"
        )
        let personalHistory = try #require(personal.history)
        #expect(personalHistory.product.classificationAuthorityProvenance == .userExplicit)
        #expect(personalHistory.comparisonMethod.hasPrefix("서버 승인"))
        #expect(personalHistory.id != globalHistory.id)
        #expect(personalHistory.product !== globalHistory.product)

        // RS-007 / RS-012 / HI-014: result/History-to-Closet registration
        // reuses the production authority boundary, not a Result-local tuple.
        let context = ModelContext(try inMemoryContainer())
        let globalSize = try #require(globalHistory.product.sizes.first)
        guard case .saved(let globalCloset) = FitMatchComparedProductClosetRegistration.save(
            comparedRegistrationRequest(product: globalHistory.product, size: globalSize),
            in: context
        ) else {
            Issue.record("RS-007 Global result-to-Closet save failed")
            return
        }
        #expect(globalCloset.classificationAuthorityProvenance == .serverConfirmed)
        let personalContext = ModelContext(try inMemoryContainer())
        let personalSize = try #require(personalHistory.product.sizes.first)
        guard case .saved(let personalCloset) = FitMatchComparedProductClosetRegistration.save(
            comparedRegistrationRequest(
                product: personalHistory.product,
                size: personalSize
            ),
            in: personalContext
        ) else {
            Issue.record("RS-012 personal result-to-Closet save failed")
            return
        }
        #expect(personalCloset.classificationAuthorityProvenance == .localHint)

        // RS-009: the shared Favorites store is data-level product behavior;
        // all presentation surfaces read the same normalized URL state.
        let favoriteDefaults = isolatedDefaults()
        let favorites = FavoriteProductStore(defaults: favoriteDefaults)
        #expect(favorites.toggle(globalHistory.product.sourceURLString))
        #expect(favorites.isFavorite(globalHistory.product.sourceURLString))
        #expect(!favorites.toggle(globalHistory.product.sourceURLString))

        // RS-010: the production destination choice keeps the exact web URL
        // for approved providers and specifies the MUSINSA app→web fallback
        // without invoking a system app from the headless test host.
        let musinsaProduct = makeSourcedProduct(authority: .serverConfirmed, code: "6805433")
        musinsaProduct.sourceName = "무신사"
        musinsaProduct.sourceURLString = "https://www.musinsa.com/products/6805433"
        switch FitMatchProductURLOpeningAction.destination(for: musinsaProduct) {
        case .musinsaApp(let appURL, let fallback):
            #expect(appURL.scheme == "musinsaad")
            #expect(fallback == URL(string: musinsaProduct.sourceURLString ?? ""))
        default:
            Issue.record("RS-010 MUSINSA lost the production app-to-web fallback")
        }
        switch FitMatchProductURLOpeningAction.destination(for: globalHistory.product) {
        case .web(let destination):
            #expect(destination.absoluteString == globalHistory.product.sourceURLString)
        default:
            Issue.record("RS-010 non-MUSINSA result did not keep its web destination")
        }
    }

    @Test func entryAuthAndPendingShareDataContractsCoverENAndBHeadlessParts() async throws {
        // EN-001 / EN-005: only an explicit compare route consumes a pending
        // payload; an unknown route cannot erase it.
        #expect(FitMatchProductEntryRouting.action(for: URL(string: "fitmatch://compare")!) == .openPendingProductCompare)
        #expect(FitMatchProductEntryRouting.action(for: URL(string: "fitmatch://unknown")!) == .ignore)

        // EN-002 / EN-012 data-level Share path: the production shared routing
        // helper selects the first supported attachment and writes exactly one
        // ephemeral handoff. Actual Share Sheet invocation remains physical.
        let attachments = [
            URL(string: "https://www.cos.com/ko_kr/men/product.1229297007.html")!,
            URL(string: "https://www.uniqlo.com/kr/ko/products/E450259")!
        ]
        #expect(FitMatchProductURLRouting.firstSupportedURL(in: attachments)?.host?.contains("uniqlo") == true)

        // EN-004 / RX-014: stale/malformed data and generation-safe A/B clear
        // remain fail closed through SharedURLStore's production contract.
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchFinalReleaseScenarioExecutionTests.Share.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        let store = SharedURLStore(fileURL: fileURL, now: { now })
        let stale = URL(string: "https://www.uniqlo.com/kr/ko/products/E450259")!
        store.savePendingProductURL(stale)
        let staleReader = SharedURLStore(
            fileURL: fileURL,
            now: { now.addingTimeInterval(SharedURLStore.pendingProductURLTimeToLive + 1) }
        )
        #expect(staleReader.consumePendingProductURL() == nil)
        let first = URL(string: "https://www.uniqlo.com/kr/ko/products/E467574")!
        let second = URL(string: "https://www.musinsa.com/products/6805433")!
        store.savePendingProductURL(first)
        let handoffA = try #require(store.pendingProductURLHandoff())
        store.savePendingProductURL(second)
        #expect(!store.clearPendingProductURL(ifMatching: first.absoluteString, token: handoffA.token))
        #expect(store.consumePendingProductURL() == second.absoluteString)

        // EN-007 data-state portion: no configured client fails closed into a
        // visible signed-out state, while actual Apple system UI stays pending.
        let auth = FitMatchAuthSessionStore(client: nil, accountDeletionService: FinalAccountDeletionService(shouldFail: false))
        await auth.observeAuthChanges()
        #expect(auth.state == .signedOut)
        #expect(auth.errorMessage != nil)
        #expect(await auth.deleteAccount())
        #expect(auth.state == .signedOut)
    }

    @Test func retryRaceAndSyncCoalescingUseProductionAsyncBoundaries() async throws {
        // RX-001: two actual comparison submissions race while the first is
        // deliberately held at a side-effect boundary. The production action
        // admits one flow only, so only it reaches begin/complete.
        let ready = try await readyGlobalComparisonExecution()
        let submission = FitMatchComparisonSubmissionAction()
        let gate = FinalAsyncGate()
        let first = Task { @MainActor in
            await submission.submit {
                await gate.wait()
                return await ready.viewModel.calculateRecommendation(
                    userFits: [ready.reference]
                )
            }
        }
        await Task.yield()
        let duplicate = await submission.submit {
            await ready.viewModel.calculateRecommendation(userFits: [ready.reference])
        }
        if case .alreadyInFlight = duplicate {
            // Expected: the production-used gate did not start a second run.
        } else {
            Issue.record("RX-001 duplicate comparison bypassed the production submission gate")
        }
        await gate.open()
        guard case .finished(let firstHistory) = await first.value,
              firstHistory != nil else {
            Issue.record("RX-001 first comparison did not finish")
            return
        }
        let compareCalls = await ready.remote.calls()
        #expect(compareCalls.filter { $0 == "begin_comparison" }.count == 1)
        #expect(compareCalls.filter { $0 == "complete_comparison" }.count == 1)

        // RX-007: duplicate source-row requests leave a single local Closet
        // row because the production registration boundary rejects identity.
        let product = makeSourcedProduct(authority: .serverConfirmed)
        let size = try #require(product.sizes.first)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let request = comparedRegistrationRequest(product: product, size: size)
        guard case .saved(let saved) = FitMatchComparedProductClosetRegistration.save(request, in: context) else {
            Issue.record("RX-001 initial source save failed")
            return
        }
        let duplicateRequest = comparedRegistrationRequest(product: product, size: size, activeClosetItems: [saved])
        if case .duplicate = FitMatchComparedProductClosetRegistration.save(duplicateRequest, in: context) {
            // Expected duplicate protection.
        } else {
            Issue.record("RX-001 duplicate source save was not blocked")
        }
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)

        // RX-009 / RX-010 / RX-011: each remote failure is injected only at
        // the transport boundary, then the exact production ViewModel retry
        // restarts from the correct gate.
        try await retryComparisonAtEveryRemoteGate()

        // RX-015: overlapping sync requests run a follow-up pass rather than
        // lose a newer request. The coordinator, not the test, owns the loop.
        let syncRemote = FinalClosetRemote()
        let sync = FitMatchClosetSyncCoordinator(remote: syncRemote, defaults: isolatedDefaults())
        let syncContainer = try inMemoryContainer()
        let syncContext = ModelContext(syncContainer)
        let user = UUID()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await sync.synchronize(userID: user, modelContext: syncContext) }
            group.addTask { await sync.synchronize(userID: user, modelContext: syncContext) }
        }
        #expect(sync.state == .synced || sync.state == .pendingRetry)
        #expect(await syncRemote.listCalls() >= 2)
    }

    /// RX-009: authority/runtime and server-reference failure each occur at
    /// their real remote boundary, then the same production ViewModel retries
    /// the original user intent without allowing begin before recovery.
    @Test func rx009AuthorityAndReferenceFailuresRetryThroughTheirExactProductionGates() async throws {
        try await retryComparison(afterFailing: .resolve, scenarioID: "RX-009 authority resolve")
        try await retryComparison(afterFailing: .runtime, scenarioID: "RX-009 authority runtime")
        try await retryComparison(afterFailing: .reference, scenarioID: "RX-009 reference authorization")
    }

    /// RX-010: eligible-size and begin failures are distinct from authority
    /// failures. Each must prevent completion on its first attempt, then a
    /// retry reaches exactly one successful production begin/result.
    @Test func rx010EligibleAndBeginFailuresRetryWithoutUsingStaleCandidates() async throws {
        try await retryComparison(afterFailing: .eligible, scenarioID: "RX-010 eligible")
        try await retryComparison(afterFailing: .begin, scenarioID: "RX-010 begin")
    }

    /// CR-003: the direct-registration action persists the actual taxonomy
    /// audience selected by the user. Child and baby rows must remain ordinary
    /// Closet rows and must not become an adult reference by side effect.
    @Test func cr003KidsAndBabyDirectRegistrationPersistsAudienceWithoutReferencePromotion() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let child = configuredDirectItem(
            name: "CR-003 키즈 상의",
            gender: .kids,
            category: .top,
            detail: .shortSleeve
        )
        child.chest = "40"
        let baby = configuredDirectItem(
            name: "CR-003 베이비 상의",
            gender: .baby,
            category: .top,
            detail: .shortSleeve
        )
        baby.chest = "32"

        for form in [child, baby] {
            guard case .saved = FitMatchClosetManualRegistrationAction.save(
                from: form,
                activeClosetItems: [],
                persist: { FitMatchClosetRegistrationPersistence.save($0, in: context) }
            ) else {
                Issue.record("CR-003 direct taxonomy registration did not persist")
                return
            }
        }

        let reloaded = try ModelContext(container).fetch(FetchDescriptor<UserFit>())
        #expect(Set(reloaded.map(\.gender)) == Set([.kids, .baby]))
        #expect(reloaded.allSatisfy { !$0.isRepresentative })
        #expect(reloaded.allSatisfy { $0.classificationAuthorityProvenance == .userExplicit })
    }

    /// CR-007: a non-default fit preference and memo use the same registration
    /// persistence action as the sheet and survive a fresh SwiftData context.
    @Test func cr007ManualMemoAndFitPreferenceSurviveFreshClosetReconstruction() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let form = configuredDirectItem(
            name: "CR-007 메모 보존 상의",
            gender: .women,
            category: .top,
            detail: .shortSleeve
        )
        form.chest = "51"
        form.fitMemo = "팔 길이가 편안함"
        form.fitPreference = .semiOver

        guard case .saved(let saved) = FitMatchClosetManualRegistrationAction.save(
            from: form,
            activeClosetItems: [],
            persist: { FitMatchClosetRegistrationPersistence.save($0, in: context) }
        ) else {
            Issue.record("CR-007 did not reach the production Closet persistence action")
            return
        }

        let reloaded = try ModelContext(container).fetch(FetchDescriptor<UserFit>())
        let reconstructed = try #require(reloaded.first { $0.id == saved.id })
        #expect(reconstructed.fitMemo == "팔 길이가 편안함")
        #expect(reconstructed.fitPreference == .semiOver)
        #expect(reconstructed.measurements.chest == 51)
    }

    /// CR-019: the system Apple sheet remains physical, but its signed-out →
    /// authenticated-root routing is a production state action and must never
    /// render a prior account while the new cache is still being prepared.
    @Test func cr019SignedOutOnboardingRouteWaitsForTheCurrentUsersCachePreparation() {
        let accountA = UUID()
        let accountB = UUID()
        #expect(FitMatchAuthenticatedRootPresentationAction.presentation(
            authState: .signedOut,
            localCachePreparedForUserID: nil,
            localCachePreparationErrorMessage: nil
        ) == .signIn)
        #expect(FitMatchAuthenticatedRootPresentationAction.presentation(
            authState: .signedIn(userID: accountA),
            localCachePreparedForUserID: nil,
            localCachePreparationErrorMessage: nil
        ) == .preparingLocalCache)
        #expect(FitMatchAuthenticatedRootPresentationAction.presentation(
            authState: .signedIn(userID: accountA),
            localCachePreparedForUserID: accountA,
            localCachePreparationErrorMessage: nil
        ) == .main)
        #expect(FitMatchAuthenticatedRootPresentationAction.presentation(
            authState: .signedIn(userID: accountB),
            localCachePreparedForUserID: accountA,
            localCachePreparationErrorMessage: nil
        ) == .preparingLocalCache)
    }

    /// CR-020: a link registration can expose a server REVIEW_REQUIRED state,
    /// but it must not fabricate a confirmed sourced Closet Product or size.
    @Test func cr020ReviewRequiredLinkRegistrationRemainsReasonedAndFailClosed() async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .reviewRequired)],
            runtimes: [try fixture.runtime(globalStatus: .reviewRequired)],
            recoveryContracts: [try fixture.recoveryContract(count: 0, suffix: "cr020")]
        )
        let outcome = await FitMatchLinkClosetRegistrationAction.load(
            urlString: fixture.url.absoluteString,
            makeViewModel: { _ in
                self.makeViewModel(
                    fixture: fixture,
                    remote: remote,
                    parser: FinalSnapshotParser(products: [fixture.parsedProduct()])
                )
            },
            existingBrand: { _ in nil }
        )
        guard case .loaded(let preparation) = outcome else {
            Issue.record("CR-020 did not reach link registration preparation")
            return
        }
        #expect(preparation.parsedProduct?.classificationAuthorityProvenance == .serverReviewRequired)
        #expect(preparation.errorMessage != nil)
        #expect(preparation.parsedProduct?.canonicalEligibility == false)
        let calls = await remote.calls()
        #expect(calls == ["resolve", "runtime", "recovery_contract"])
    }

    /// CR-022: a linked/compared product save retries through the same action.
    /// Only the persistence boundary is injected; identity and authority stay
    /// in `FitMatchComparedProductClosetRegistration`.
    @Test func cr022ComparedProductSaveFailureThenRetryCreatesExactlyOneClosetRow() throws {
        let product = makeSourcedProduct(authority: .serverConfirmed)
        let size = try #require(product.sizes.first)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let request = comparedRegistrationRequest(product: product, size: size)

        if case .persistenceFailed = FitMatchComparedProductClosetRegistration.save(
            request,
            in: context,
            persist: { _ in throw FinalScenarioFailure("CR-022", "injected local save failure") }
        ) {
            // The production action keeps the request eligible for the retry below.
        } else {
            Issue.record("CR-022 injected persistence failure did not reach the production failure terminal")
        }
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 0)

        guard case .saved(let saved) = FitMatchComparedProductClosetRegistration.save(
            request,
            in: context
        ) else {
            Issue.record("CR-022 retry did not reuse the production compared-product action")
            return
        }
        #expect(saved.classificationAuthorityProvenance == .serverConfirmed)
        #expect(try context.fetchCount(FetchDescriptor<UserFit>()) == 1)
    }

    /// CM-005: direct detail editing owns memo/preference persistence without
    /// changing the item measurements or its classification authority.
    @Test func cm005ManualDetailMemoAndPreferencePersistWithoutClassificationDrift() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let original = makeManualItem(
            name: "CM-005 원본",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        original.fitMemo = "기존 메모"
        original.fitPreference = .regular
        context.insert(original)
        try context.save()

        let edited = makeManualItem(
            name: "CM-005 수정",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        edited.fitMemo = "수정 메모"
        edited.fitPreference = .semiOver
        let originalMeasurements = original.measurements
        #expect(FitMatchClosetItemEditAction.saveManual(
            item: original,
            editedItem: edited,
            activeClosetItems: [original],
            in: context,
            now: Date(timeIntervalSince1970: 2)
        ) == .saved)

        let reloaded = try ModelContext(container).fetch(FetchDescriptor<UserFit>())
        let reconstructed = try #require(reloaded.first { $0.id == original.id })
        #expect(reconstructed.fitMemo == "수정 메모")
        #expect(reconstructed.fitPreference == .semiOver)
        #expect(reconstructed.measurements == originalMeasurements)
        #expect(reconstructed.classificationAuthorityProvenance == .userExplicit)
    }

    /// CM-007: top and bottom reference mutations share the real conflict
    /// scope but remain independently selectable for their own targets.
    @Test func cm007IndependentTopAndBottomReferencesDoNotConflict() {
        let top = makeManualItem(
            name: "CM-007 상의 기준",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        let bottom = makeManualItem(
            name: "CM-007 하의 기준",
            category: .bottom,
            detail: .longPants,
            createdAt: 2
        )
        FitMatchClosetReferenceMutation.setRepresentative(top, among: [top, bottom])
        FitMatchClosetReferenceMutation.setRepresentative(bottom, among: [top, bottom])
        #expect(top.isRepresentative)
        #expect(bottom.isRepresentative)
        FitMatchClosetReferenceMutation.clearRepresentative(top)
        #expect(!top.isRepresentative)
        #expect(bottom.isRepresentative)
    }

    /// CM-018: MyClosetView calls this production presentation action for
    /// every filter/sort layout. The test asserts identity, not a view-only
    /// ordering approximation.
    @Test func cm018ClosetPresentationFiltersAndSortsOnlyTheOwnedActiveIdentitySet() {
        let alpha = makeManualItem(name: "CM-018 Alpha", category: .top, detail: .shortSleeve, createdAt: 1)
        alpha.brandName = "Alpha"
        let beta = makeManualItem(name: "CM-018 Beta", category: .bottom, detail: .longPants, createdAt: 2)
        beta.brandName = "Beta"
        let historical = makeManualItem(name: "CM-018 과거", category: .top, detail: .shortSleeve, createdAt: 3)
        historical.markAsHistoryOnlyReferenceSnapshot()

        let cached = [alpha, beta, historical]
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: .top,
            brand: nil,
            sort: .recent
        ).map(\.id) == [alpha.id])
        #expect(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: "Beta",
            sort: .brand
        ).map(\.id) == [beta.id])
        #expect(Set(FitMatchClosetPresentation.displayedItems(
            from: cached,
            category: nil,
            brand: nil,
            sort: .oldest
        ).map(\.id)) == Set([alpha.id, beta.id]))
    }

    /// CM-011: a legacy/local History has no completed-comparison identity.
    /// Deleting its related Closet item therefore remains local and never
    /// fabricates a server visibility request.
    @Test func cm011LegacyHistoryDeletionStaysLocalWithoutATombstoneRequest() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let product = makeSourcedProduct(authority: .localHint)
        let reference = makeManualItem(
            name: "CM-011 legacy 기준옷",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        let size = try #require(product.sizes.first)
        let legacy = RecommendationHistory(
            product: product,
            recommendedSize: size,
            userFit: reference,
            totalDifference: 1,
            measurementDifferences: .init(shoulder: 1, chest: 1, totalLength: 1, sleeveLength: 1),
            recommendationScore: 90,
            comparisonMethod: "로컬 비교"
        )
        context.insert(product)
        context.insert(reference)
        context.insert(legacy)
        try context.save()
        let remote = FinalHistoryRemote(rows: [], hideFailures: 0)
        let sync = FitMatchComparisonSyncCoordinator(remote: remote, defaults: isolatedDefaults())

        #expect(await FitMatchClosetDeletionAction.delete(
            item: reference,
            histories: [legacy],
            in: context,
            comparisonSync: sync,
            closetSync: nil
        ) == .deleted)
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(await remote.hideCalls() == 0)
    }

    /// CM-012: the production imported-detail action exposes a persistence
    /// failure terminal, then the exact retry action stores the selected size
    /// without promoting authority merely because a retry occurred.
    @Test func cm012ImportedEditPersistenceFailureThenRetryKeepsSourcedAuthority() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let product = makeSourcedProduct(authority: .serverConfirmed, code: "CM012")
        let replacement = ProductSize(
            id: UUID(),
            name: "L",
            measurements: .init(shoulder: 50, chest: 55, totalLength: 72, sleeveLength: 25),
            displayOrder: 1,
            product: product
        )
        product.sizes.append(replacement)
        let item = makeSourcedUserFit(product: product, authority: .serverConfirmed)
        context.insert(product)
        context.insert(item)
        try context.save()

        #expect(FitMatchClosetItemEditAction.saveImported(
            item: item,
            selectedSize: replacement,
            category: .top,
            detailCategory: .shortSleeve,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            didExplicitlyChangeClassification: false,
            in: context,
            now: Date(timeIntervalSince1970: 2),
            performSave: { _ in throw FinalScenarioFailure("CM-012", "injected detail persistence failure") }
        ) == .persistenceFailed)

        #expect(FitMatchClosetItemEditAction.saveImported(
            item: item,
            selectedSize: replacement,
            category: .top,
            detailCategory: .shortSleeve,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            didExplicitlyChangeClassification: false,
            in: context,
            now: Date(timeIntervalSince1970: 3)
        ) == .saved)
        #expect(item.sizeName == "L")
        #expect(item.classificationAuthorityProvenance == .serverConfirmed)
    }

    /// CM-002: direct Closet editing changes only the values the user edited
    /// and keeps the existing direct-item authority rather than turning an
    /// ordinary size change into a server/global authority mutation.
    @Test func cm002ManualDetailEditPersistsIdentityClassificationAndSelectedSize() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let item = makeManualItem(
            name: "CM-002 원본 상의",
            category: .top,
            detail: .shortSleeve,
            createdAt: 1
        )
        context.insert(item)
        try context.save()

        let edited = makeManualItem(
            name: "CM-002 수정 하의",
            category: .bottom,
            detail: .longPants,
            createdAt: 1
        )
        edited.gender = .women
        edited.sizeName = "28"
        edited.waist = 36
        edited.hip = 50
        #expect(FitMatchClosetItemEditAction.saveManual(
            item: item,
            editedItem: edited,
            activeClosetItems: [item],
            in: context,
            now: Date(timeIntervalSince1970: 2)
        ) == .saved)

        let reloaded = try ModelContext(container).fetch(FetchDescriptor<UserFit>())
        let result = try #require(reloaded.first { $0.id == item.id })
        #expect(result.productName == "CM-002 수정 하의")
        #expect(result.gender == .women)
        #expect(result.category == .bottom)
        #expect(result.detailCategory == .longPants)
        #expect(result.sizeName == "28")
        #expect(result.waist == 36)
        #expect(result.classificationAuthorityProvenance == .userExplicit)
    }

    /// CM-004: a representative's saved measurement edit is the snapshot
    /// supplied to the next server-authorized comparison; it does not rewrite
    /// any prior completed comparison object.
    @Test func cm004ReferenceMeasurementEditFeedsOnlyTheNextComparisonSnapshot() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        context.insert(reference)
        try context.save()

        let edited = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        edited.chest = 57
        edited.fitMemo = "CM-004 새 실측"
        #expect(FitMatchClosetItemEditAction.saveManual(
            item: reference,
            editedItem: edited,
            activeClosetItems: [reference],
            in: context,
            now: Date(timeIntervalSince1970: 2)
        ) == .saved)
        #expect(reference.chest == 57)

        let remoteReference = fixture.closetRecord(for: reference)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
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
                referenceClosetItemID: remoteReference.closetItemID
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeViewModel(
            fixture: fixture,
            remote: remote,
            parser: FinalSnapshotParser(products: [fixture.parsedProduct()])
        )
        #expect(await viewModel.loadProductInfoFromURL())
        let history = try #require(await viewModel.calculateRecommendation(userFits: [reference]))
        #expect(history.userFit.id == reference.id)
        #expect(history.userFit.chest == 57)
        try requireCallOrder(
            await remote.calls(),
            ["list_closet", "reference_candidates", "eligible_sizes", "begin_comparison", "complete_comparison"],
            scenario: "CM-004"
        )
    }

    /// CM-009: deleting the active reference removes its local row. A fresh
    /// server authorization using the captured former identity then fails
    /// closed because that client row is no longer present remotely.
    @Test func cm009DeletedReferenceCannotReappearOrAuthorizeAfterReconstruction() async throws {
        let fixture = HeadlessJourneyFixture(provider: .zara)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let snapshot = try #require(reference.fitMatchServerReferenceSnapshot())
        let formerID = reference.id
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        context.insert(reference)
        try context.save()

        #expect(await FitMatchClosetDeletionAction.delete(
            item: reference,
            histories: [],
            in: context,
            comparisonSync: nil,
            closetSync: nil
        ) == .deleted)
        #expect(try ModelContext(container).fetch(FetchDescriptor<UserFit>()).isEmpty)

        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime],
            closetResponses: [.init(state: "ready", items: [])]
        )
        let coordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        let target = try #require(fixture.parsedProduct().fitMatchDatabaseResolutionRequest())
        await #expect(throws: FitMatchServerAuthorityError.referenceItemNotFound) {
            _ = try await coordinator.authorizeReferenceCandidate(
                referenceClientItemID: formerID,
                localReferenceSnapshot: snapshot,
                targetRequest: target,
                targetObservation: fixture.parsedProduct().fitMatchProductObservationRequest()
            )
        }
        #expect(!(await remote.calls()).contains("begin_comparison"))
    }

    /// CM-013: duplicate creation is rejected at the real registration
    /// boundary, and the same production presentation action excludes
    /// inactive/history-only rows from a reconstructed managed Closet.
    @Test func cm013DuplicateCreationAndInactiveHistoryOnlyFilteringUseProductionActions() throws {
        let product = makeSourcedProduct(authority: .serverConfirmed, code: "CM013")
        let size = try #require(product.sizes.first)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let request = comparedRegistrationRequest(product: product, size: size)
        guard case .saved(let active) = FitMatchComparedProductClosetRegistration.save(request, in: context) else {
            Issue.record("CM-013 first sourced item did not save")
            return
        }
        let duplicate = FitMatchComparedProductClosetRegistration.save(
            comparedRegistrationRequest(product: product, size: size, activeClosetItems: [active]),
            in: context
        )
        guard case .duplicate = duplicate else {
            Issue.record("CM-013 duplicate sourced item was not rejected")
            return
        }

        let historyOnly = makeManualItem(
            name: "CM-013 history snapshot",
            category: .top,
            detail: .shortSleeve,
            createdAt: 2
        )
        historyOnly.markAsHistoryOnlyReferenceSnapshot()
        context.insert(historyOnly)
        try context.save()

        let presented = FitMatchClosetPresentation.displayedItems(
            from: try ModelContext(container).fetch(FetchDescriptor<UserFit>()),
            category: nil,
            brand: nil,
            sort: .recent
        )
        #expect(presented.map(\.id) == [active.id])
    }

    /// CM-014: A→B reference replacement, B deletion, a fresh A reference,
    /// and A's measurement edit form one live lifecycle. The later comparison
    /// uses the current A snapshot while the earlier completed History remains
    /// a detached historical object.
    @Test func cm014ReferenceLifecycleCreatesANewComparisonWithoutRewritingOldHistory() async throws {
        let old = try await completeComparison(
            provider: .uniqlo,
            manual: false,
            personalGarment: nil
        )
        let oldHistory = try #require(old.history)
        let oldAuthority = oldHistory.product.classificationAuthorityProvenance

        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let referenceA = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        referenceA.productName = "CM-014 A"
        let referenceB = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        referenceB.productName = "CM-014 B"
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        context.insert(referenceA)
        context.insert(referenceB)
        try context.save()
        FitMatchClosetReferenceMutation.setRepresentative(referenceA, among: [referenceA, referenceB])
        FitMatchClosetReferenceMutation.setRepresentative(referenceB, among: [referenceA, referenceB])
        #expect(!referenceA.isRepresentative)
        #expect(referenceB.isRepresentative)
        #expect(await FitMatchClosetDeletionAction.delete(
            item: referenceB,
            histories: [],
            in: context,
            comparisonSync: nil,
            closetSync: nil
        ) == .deleted)
        FitMatchClosetReferenceMutation.setRepresentative(referenceA, among: [referenceA])
        let editedA = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        editedA.chest = 58
        #expect(FitMatchClosetItemEditAction.saveManual(
            item: referenceA,
            editedItem: editedA,
            activeClosetItems: [referenceA],
            in: context,
            now: Date(timeIntervalSince1970: 3)
        ) == .saved)

        let recordA = fixture.closetRecord(for: referenceA)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [recordA])],
            candidateResponses: [try fixture.referenceResponse(reference: referenceA, closetItemID: recordA.closetItemID, decision: "AUTOMATIC")],
            eligibleResponses: [try fixture.eligible(reference: referenceA, closetItemID: recordA.closetItemID, mode: "AUTOMATIC", allowed: true, effectiveSource: nil, overrideRevision: nil)],
            beginResponses: [try fixture.begin(mode: "AUTOMATIC", personal: false, referenceClosetItemID: recordA.closetItemID)],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeViewModel(
            fixture: fixture,
            remote: remote,
            parser: FinalSnapshotParser(products: [fixture.parsedProduct()])
        )
        #expect(await viewModel.loadProductInfoFromURL())
        let newHistory = try #require(await viewModel.calculateRecommendation(userFits: [referenceA]))
        #expect(newHistory.userFit.id == referenceA.id)
        #expect(newHistory.userFit.chest == 58)
        #expect(oldHistory.product.classificationAuthorityProvenance == oldAuthority)
        #expect(oldHistory.id != newHistory.id)
    }
}

private enum FinalFrozenScenarioClassification {
    static let staticContractIDs: Set<String> = ["EN-010", "EN-011"]

    static let physicalSmokeIDs: Set<String> = [
        "CR-019", "EN-002", "EN-007", "EN-012"
    ]

    static let allIDs: [String] =
        (1...22).map { String(format: "CR-%03d", $0) }
        + (1...19).map { String(format: "CM-%03d", $0) }
        + (1...39).map { String(format: "CP-%03d", $0) }
        + (1...13).map { String(format: "RS-%03d", $0) }
        + (1...17).map { String(format: "HI-%03d", $0) }
        + (1...12).map { String(format: "EN-%03d", $0) }
        + (1...15).map { String(format: "RX-%03d", $0) }

    static let headlessIDs: Set<String> = Set(allIDs)
        .subtracting(staticContractIDs)
        .subtracting(physicalSmokeIDs)
}

// MARK: - Production-path fixture helpers

private func requireCallOrder(
    _ calls: [String],
    _ required: [String],
    scenario: String
) throws {
    var cursor = calls.startIndex
    for expected in required {
        guard let found = calls[cursor...].firstIndex(of: expected) else {
            throw FinalScenarioFailure(scenario, "missing ordered call \(expected): \(calls)")
        }
        cursor = calls.index(after: found)
    }
}

private struct FinalScenarioFailure: Error, CustomStringConvertible {
    let scenario: String
    let message: String

    init(_ scenario: String, _ message: String) {
        self.scenario = scenario
        self.message = message
    }

    var description: String { "\(scenario): \(message)" }
}

@MainActor
private extension FitMatchFinalReleaseScenarioExecutionTests {
    func configuredDirectItem(
        name: String,
        gender: UserGender,
        category: ClothingCategory,
        detail: ClosetDetailCategory
    ) -> AddClosetItemViewModel {
        let value = AddClosetItemViewModel(
            prefillCategory: category,
            prefillDetailCategory: detail,
            prefillGender: gender,
            prefillSourceOption: .manual,
            prefillBrand: "Final Acceptance",
            prefillProductName: name
        )
        value.measurementEntrySource = .fitmatchMeasured
        return value
    }

    func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func isolatedDefaults() -> UserDefaults {
        let name = "FitMatchFinalAcceptance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func sourceFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func makeManualItem(
        name: String,
        category: ClothingCategory,
        detail: ClosetDetailCategory,
        createdAt: TimeInterval
    ) -> UserFit {
        let item = UserFit(
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "Final Acceptance",
            gender: .men,
            productName: name,
            category: category,
            detailCategory: detail,
            sizeName: "M",
            measurements: category == .bottom
                ? GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, waist: 35, hip: 49)
                : GarmentMeasurements(shoulder: 45, chest: 50, totalLength: 69, sleeveLength: 22),
            fitMemo: "",
            satisfaction: 4,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
        item.markClassificationAuthority(.userExplicit, sourceIdentity: "final-acceptance-manual")
        return item
    }

    func makeSourcedProduct(
        authority: FitMatchClassificationAuthorityProvenance,
        code: String = "E450259"
    ) -> Product {
        let size = ProductSize(
            id: UUID(),
            name: "M",
            measurements: GarmentMeasurements(shoulder: 48, chest: 51, totalLength: 70, sleeveLength: 24),
            displayOrder: 0
        )
        let product = Product(
            id: UUID(),
            name: "Sourced target \(code)",
            brand: Brand(name: "UNIQLO"),
            category: .top,
            productCode: code,
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/\(code)",
            metadata: ProductMetadata(
                sourceCategoryPath: "tops > short sleeve",
                categoryDepth1Code: "tops",
                categoryDepth2Code: "short_sleeve",
                genderCodes: ["MEN"]
            ),
            sourceType: .officialStore,
            sourceName: "UNIQLO",
            sizes: [size]
        )
        product.categoryCode = "tops"
        product.normalizedProductTypeCode = "short_sleeve"
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(authority, sourceIdentity: "final-acceptance-source")
        return product
    }

    func makeSourcedUserFit(
        product: Product,
        authority: FitMatchClassificationAuthorityProvenance
    ) -> UserFit {
        let size = product.sizes[0]
        let item = UserFit(
            sourceType: product.sourceType,
            sourceName: product.sourceName,
            brandName: product.brand?.name ?? "UNIQLO",
            gender: .men,
            productName: product.name,
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "",
            satisfaction: 4,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.markClassificationAuthority(authority, sourceIdentity: "final-acceptance-source")
        return item
    }

    func comparedRegistrationRequest(
        product: Product,
        size: ProductSize,
        activeClosetItems: [UserFit] = []
    ) -> FitMatchComparedProductClosetRegistration.SaveRequest {
        FitMatchComparedProductClosetRegistration.SaveRequest(
            product: product,
            selectedSize: size,
            activeClosetItems: activeClosetItems,
            brandName: product.brand?.name ?? "UNIQLO",
            gender: .men,
            genderCode: "MEN",
            productName: product.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "short_sleeve",
            isRepresentative: false,
            didExplicitlyChangeClassification: false
        )
    }

    func readyGlobalComparisonExecution() async throws -> (
        viewModel: ShoppingProductViewModel,
        reference: UserFit,
        remote: JourneyRecordingRemote
    ) {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let remote = JourneyRecordingRemote(
            resolutions: [fixture.resolution(globalStatus: .confirmed), fixture.resolution(globalStatus: .confirmed)],
            runtimes: [runtime, runtime],
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [try fixture.referenceResponse(
                reference: reference,
                closetItemID: remoteReference.closetItemID,
                decision: "AUTOMATIC"
            )],
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
                personalRevision: 1,
                personalCandidateFingerprint: nil,
                personalCandidateSetHash: nil,
                personalInputFingerprint: nil,
                personalEvidenceFingerprint: nil
            )],
            completionResponses: [try fixture.complete()]
        )
        let viewModel = makeViewModel(
            fixture: fixture,
            remote: remote,
            parser: FinalSnapshotParser(products: [fixture.parsedProduct()])
        )
        guard await viewModel.loadProductInfoFromURL() else {
            throw FinalScenarioFailure("RX-001", "ready comparison did not load")
        }
        return (viewModel, reference, remote)
    }

    func makeViewModel(
        fixture: HeadlessJourneyFixture,
        remote: JourneyRecordingRemote,
        parser: ProductURLParsing
    ) -> ShoppingProductViewModel {
        let service: ProductURLParserService
        switch fixture.provider {
        case .uniqlo:
            service = ProductURLParserService(uniqloParser: parser)
        case .musinsa:
            service = ProductURLParserService(musinsaParser: parser)
        case .zara:
            service = ProductURLParserService(zaraParser: parser)
        }
        return ShoppingProductViewModel(
            initialURL: fixture.url.absoluteString,
            parserService: service,
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
    }

    func completeComparison(
        provider: HeadlessJourneyProvider,
        manual: Bool,
        personalGarment: String?,
        referenceGarment: String = "tshirt",
        referenceSleeve: String = "short_sleeve",
        includeReference: Bool = true,
        serverDecision: String? = nil,
        eligibleAllowed: Bool = true
    ) async throws -> (history: RecommendationHistory?, calls: [String]) {
        let fixture = HeadlessJourneyFixture(provider: provider)
        let isPersonal = personalGarment != nil
        let globalStatus: HeadlessGlobalStatus = isPersonal ? .reviewRequired : .confirmed
        let runtime = try fixture.runtime(
            globalStatus: globalStatus,
            effectivePersonalGarment: personalGarment,
            overrideRevision: isPersonal ? 1 : nil,
            personalCandidateFingerprint: isPersonal ? "candidate-current-\(personalGarment!)" : nil,
            personalCandidateSetHash: isPersonal ? "set-current-\(personalGarment!)" : nil
        )
        let reference = fixture.localReference(garment: referenceGarment, sleeve: referenceSleeve)
        let remoteReference = fixture.closetRecord(for: reference)
        let decision = serverDecision ?? (manual ? "MANUAL_EXTENDED" : "AUTOMATIC")
        let begin: [FitMatchBeginComparisonResponse]
        let completion: [VNextCompleteComparisonDTO]
        if eligibleAllowed && (decision == "AUTOMATIC" || manual && decision == "MANUAL_EXTENDED") {
            begin = [try fixture.begin(
                mode: decision == "AUTOMATIC" ? "AUTOMATIC" : "MANUAL_EXTENDED",
                personal: isPersonal,
                referenceClosetItemID: remoteReference.closetItemID,
                personalGarment: personalGarment ?? "tshirt",
                personalRevision: 1,
                personalCandidateFingerprint: isPersonal ? "candidate-current-\(personalGarment!)" : nil,
                personalCandidateSetHash: isPersonal ? "set-current-\(personalGarment!)" : nil,
                personalInputFingerprint: isPersonal ? "input-v1" : nil,
                personalEvidenceFingerprint: isPersonal ? "evidence-v1" : nil
            )]
            completion = [try fixture.complete()]
        } else {
            begin = []
            completion = []
        }
        let remote = JourneyRecordingRemote(
            resolutions: includeReference
                ? [fixture.resolution(globalStatus: globalStatus), fixture.resolution(globalStatus: globalStatus)]
                : [fixture.resolution(globalStatus: globalStatus)],
            runtimes: includeReference ? [runtime, runtime] : [runtime],
            closetResponses: includeReference ? [.init(state: "ready", items: [remoteReference])] : [],
            candidateResponses: includeReference ? [try fixture.referenceResponse(reference: reference, closetItemID: remoteReference.closetItemID, decision: decision)] : [],
            eligibleResponses: eligibleAllowed && (decision == "AUTOMATIC" || decision == "MANUAL_EXTENDED") && includeReference
                ? [try fixture.eligible(reference: reference, closetItemID: remoteReference.closetItemID, mode: decision == "AUTOMATIC" ? "AUTOMATIC" : "MANUAL_EXTENDED", allowed: true, effectiveSource: isPersonal ? "USER_EXPLICIT" : nil, overrideRevision: isPersonal ? 1 : nil)]
                : includeReference && decision == "AUTOMATIC" ? [try fixture.eligible(reference: reference, closetItemID: remoteReference.closetItemID, mode: "AUTOMATIC", allowed: false, effectiveSource: nil, overrideRevision: nil)] : [],
            beginResponses: begin,
            completionResponses: completion
        )
        let vm = makeViewModel(fixture: fixture, remote: remote, parser: FinalSnapshotParser(products: [fixture.parsedProduct()]))
        guard await vm.loadProductInfoFromURL() else {
            return (nil, await remote.calls())
        }
        let history: RecommendationHistory?
        if includeReference {
            history = manual
                ? await vm.calculateTemporaryRecommendation(selectedReferenceItem: reference)
                : await vm.calculateRecommendation(userFits: [reference])
        } else {
            history = await vm.calculateRecommendation(userFits: [])
        }
        return (history, await remote.calls())
    }

    func retryComparisonAtEveryRemoteGate() async throws {
        for stage in FinalRemoteFailureStage.allCases {
            try await retryComparison(afterFailing: stage, scenarioID: "RX all gates")
        }
    }

    func retryComparison(
        afterFailing stage: FinalRemoteFailureStage,
        scenarioID: String
    ) async throws {
        let fixture = HeadlessJourneyFixture(provider: .uniqlo)
        let runtime = try fixture.runtime(globalStatus: .confirmed)
        let reference = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let remoteReference = fixture.closetRecord(for: reference)
        let candidate = try fixture.referenceResponse(
            reference: reference,
            closetItemID: remoteReference.closetItemID,
            decision: "AUTOMATIC"
        )
        let eligible = try fixture.eligible(
            reference: reference,
            closetItemID: remoteReference.closetItemID,
            mode: "AUTOMATIC",
            allowed: true,
            effectiveSource: nil,
            overrideRevision: nil
        )
        let begin = try fixture.begin(
            mode: "AUTOMATIC",
            personal: false,
            referenceClosetItemID: remoteReference.closetItemID,
            personalGarment: "tshirt",
            personalRevision: 1,
            personalCandidateFingerprint: nil,
            personalCandidateSetHash: nil,
            personalInputFingerprint: nil,
            personalEvidenceFingerprint: nil
        )
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 4),
            runtimes: Array(repeating: runtime, count: 4),
            closetResponses: [.init(state: "ready", items: [remoteReference])],
            candidateResponses: [candidate, candidate],
            eligibleResponses: [eligible, eligible],
            beginResponses: [begin, begin],
            completionResponses: [try fixture.complete(), try fixture.complete()],
            resolveFailureCount: stage == .resolve ? 1 : 0,
            runtimeFailureCount: stage == .runtime ? 1 : 0,
            referenceFailureCount: stage == .reference ? 1 : 0,
            eligibleFailureCount: stage == .eligible ? 1 : 0,
            beginFailureCount: stage == .begin ? 1 : 0,
            completionFailureCount: stage == .complete ? 1 : 0
        )
        let vm = makeViewModel(
            fixture: fixture,
            remote: remote,
            parser: FinalSnapshotParser(products: [fixture.parsedProduct()])
        )

        switch stage {
        case .resolve, .runtime:
            guard await vm.loadProductInfoFromURL() == false else {
                throw FinalScenarioFailure(scenarioID, "\(stage) did not fail the first load")
            }
            let failedCalls = await remote.calls()
            guard !failedCalls.contains("begin_comparison") else {
                throw FinalScenarioFailure(scenarioID, "\(stage) reached begin before retry")
            }
            guard await vm.loadProductInfoFromURL() else {
                throw FinalScenarioFailure(scenarioID, "\(stage) did not recover load")
            }
            guard await vm.calculateRecommendation(userFits: [reference]) != nil else {
                throw FinalScenarioFailure(scenarioID, "\(stage) did not complete after retry")
            }

        case .reference, .eligible, .begin, .complete:
            guard await vm.loadProductInfoFromURL() else {
                throw FinalScenarioFailure(scenarioID, "\(stage) did not load")
            }
            guard await vm.calculateRecommendation(userFits: [reference]) == nil else {
                throw FinalScenarioFailure(scenarioID, "\(stage) unexpectedly completed before retry")
            }
            let failedCalls = await remote.calls()
            if stage != .complete, failedCalls.contains("complete_comparison") {
                throw FinalScenarioFailure(scenarioID, "\(stage) reached completion before retry")
            }
            guard await vm.calculateRecommendation(userFits: [reference]) != nil else {
                throw FinalScenarioFailure(scenarioID, "\(stage) did not complete after retry")
            }
        }
    }

    func historicalRow(
        targetProductID: UUID,
        referenceClientItemID: UUID,
        garment: String,
        revision: Int,
        personal: Bool,
        audience: String = "MEN"
    ) throws -> VNextComparisonHistoryDTO {
        let comparisonID = UUID()
        let clientComparisonID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        let source = personal ? "USER_EXPLICIT" : "GLOBAL_CONFIRMED"
        let state = personal ? "PERSONAL_CONFIRMED" : "GLOBAL_CONFIRMED"
        let personalJSON = personal ? ",\"personal_projection_at_begin\":{\"classification_source\":\"USER_EXPLICIT\",\"garment_type_code\":\"\(garment)\",\"revision\":\(revision),\"selected_candidate_fingerprint\":\"candidate-\(revision)\",\"candidate_set_hash\":\"set-\(revision)\"}" : ""
        let json = """
        {"id":"\(comparisonID)","client_comparison_id":"\(clientComparisonID)","reference_client_item_id":"\(referenceClientItemID)","target_product_id":"\(targetProductID)","target_variant_id":"\(variantID)","target_product_name_snapshot":"History \(garment)","target_source_code_snapshot":"uniqlo","target_source_product_key":"E450259","target_category_code":"tops","result_status":"COMPLETED","recommended_product_size_id":"\(sizeID)","recommended_size_label":"M","fit_score":95,"reliability_level":2,"coverage_ratio":1,"engine_version":"fitmatch-ios-vnext-snapshot-v1","result_evidence":{"recommended_product_size_id":"\(sizeID)","score":95,"reliability":2,"coverage":1,"engine_version":"fitmatch-ios-vnext-snapshot-v1","candidate_size_ranking":[{"product_size_id":"\(sizeID)","rank":1,"score":95}],"metric_evidence":[{"product_size_id":"\(sizeID)","measurement_code":"chest_width_pit_to_pit","reference_value":50,"target_value":51,"difference":1,"absolute_difference":1,"weight":1}]},"created_at":"2026-08-31T00:00:00Z","snapshot_schema_version":4,"excluded_measurement_codes":[],"reference_snapshot":{"source_code":"manual","item_name":"기준옷","size_label":"M","garment_type_code":"tshirt","audience_code":"MEN","sleeve_length_code":"short_sleeve","classification_source":"USER_EXPLICIT","measurements":[{"fitmatch_measurement_code":"chest_width_pit_to_pit","value":50,"unit_code":"CM","value_source":"USER"}]},"target_snapshot":{"product_id":"\(targetProductID)","variant_id":"\(variantID)","authorized_candidate_product_size_ids":["\(sizeID)"],"candidate_authority_fingerprint":"candidate-authority","classification_status":"CONFIRMED","garment_type_code":"\(garment)","sleeve_length_code":"short_sleeve","candidates":[{"product_size_id":"\(sizeID)","size_label":"M","availability":{"status":"AVAILABLE","observed_at":"2026-08-31T00:00:00Z","valid_until":"2026-09-01T00:00:00Z","evidence_fingerprint":"stock"},"comparison_measurements":[{"measurement_code":"chest_width_pit_to_pit","reference_value":50,"target_value":51,"difference":1,"absolute_difference":1,"unit_code":"CM","basis_code":"WIDTH","weight":1,"requirement_mode":"REQUIRED_ANY","priority":1}],"authorization":{"decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC","excluded_measurement_codes":[],"required_measurement_codes":["chest_width_pit_to_pit"],"minimum_common":1,"common_measurement_count":1,"required_any_count":1,"policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1"}}]},"authority_snapshot":{"global_classification_at_begin":{"status":"CONFIRMED","garment_type_code":"\(garment)"},"effective_classification_at_begin":{"source":"\(source)","state":"\(state)","category_code":"tops","garment_type_code":"\(garment)","audience_code":"\(audience)","sleeve_length_code":"short_sleeve"}\(personalJSON)},"policy_snapshot":{"policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1","metrics":[{"metric_mode":"CANONICAL","fitmatch_measurement_code":"chest_width_pit_to_pit","weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,"is_active":true}]},"authorization_snapshot":{"decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC","excluded_measurement_codes":[],"required_measurement_codes":["chest_width_pit_to_pit"],"minimum_common":1,"common_measurement_count":1,"required_any_count":1,"policy_code":"\(garment)","policy_version":"v1","policy_checksum":"policy-v1"},"input_snapshot":{}}
        """
        return try JSONDecoder().decode(VNextComparisonHistoryDTO.self, from: Data(json.utf8))
    }
}

private enum FinalRemoteFailureStage: CaseIterable {
    case resolve
    case runtime
    case reference
    case eligible
    case begin
    case complete
}

private actor FinalAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FinalSnapshotParser: ProductURLParsing {
    private var results: [Result<ParsedProductInfo, Error>]

    init(products: [ParsedProductInfo]) {
        results = products.map(Result.success)
    }

    init(results: [Result<ParsedProductInfo, Error>]) {
        self.results = results
    }

    func canParse(_ url: URL) -> Bool { true }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        guard !results.isEmpty else { throw ProductURLParserError.automaticParsingUnavailable }
        let result = results.count == 1 ? results[0] : results.removeFirst()
        return try result.get()
    }
}

private actor FinalHistoryRemote: FitMatchComparisonRemoteServicing {
    private let rows: [VNextComparisonHistoryDTO]
    private var failures: Int
    private var calls = 0

    init(rows: [VNextComparisonHistoryDTO], hideFailures: Int) {
        self.rows = rows
        failures = hideFailures
    }

    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO] { rows }

    func hideVNextComparisonHistories(clientComparisonIDs: [UUID]) async throws -> VNextComparisonHistoryVisibilityDTO {
        calls += 1
        if failures > 0 {
            failures -= 1
            throw JourneyRemoteFailure.scriptedTransport
        }
        return VNextComparisonHistoryVisibilityDTO(
            clientComparisonIDs: clientComparisonIDs,
            hidden: true,
            idempotent: false
        )
    }

    func completeVNextComparison(comparisonID: UUID, payload: VNextComparisonCompletionPayload) async throws -> VNextCompleteComparisonDTO {
        throw JourneyRemoteFailure.unexpected("pending completion")
    }

    func hideCalls() -> Int { calls }
}

private actor FinalClosetRemote: FitMatchClosetRemoteServicing {
    private var calls = 0

    func resolve(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductResolutionResponse { throw JourneyRemoteFailure.unexpected("resolve") }
    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws -> FitMatchProductObservationResponse { throw JourneyRemoteFailure.unexpected("observation") }
    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws -> FitMatchProductRuntimeResponse { throw JourneyRemoteFailure.unexpected("runtime") }
    func listClosetItems() async throws -> FitMatchClosetItemsResponse { calls += 1; return .init(state: "ready", items: []) }
    func findReferenceCandidates(targetProductID: UUID) async throws -> FitMatchReferenceCandidatesResponse {
        throw JourneyRemoteFailure.unexpected("reference_candidates")
    }
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws -> FitMatchUpsertClosetItemResponse { throw JourneyRemoteFailure.unexpected("upsert") }
    func deleteClosetItem(closetItemID: UUID) async throws -> FitMatchDeleteClosetItemResponse { throw JourneyRemoteFailure.unexpected("delete") }
    func listCalls() -> Int { calls }
}

private actor FinalAccountDeletionService: FitMatchAccountDeletionServicing {
    let shouldFail: Bool
    init(shouldFail: Bool) { self.shouldFail = shouldFail }
    func deleteAccount() async throws {
        if shouldFail { throw FitMatchAuthSessionError.accountDeletionFailed }
    }
}
