import Testing
import Foundation
@testable import FitMatch

private let runsLiveMusinsaValidation =
    ProcessInfo.processInfo.arguments.contains("-fitmatchRunLiveTests")
    || ProcessInfo.processInfo.environment["FITMATCH_RUN_LIVE_TESTS"] == "1"

private let runsLiveUniqloValidation = runsLiveMusinsaValidation

@MainActor
@Suite(.enabled(
    if: runsLiveUniqloValidation,
    "유니클로 실서버 검증은 명시적으로만 실행합니다."
))
struct LiveUniqloValidationTests {
    @Test func koreanUnderwearProductsUseUnderwearBriefsClassification() async throws {
        let parser = ProductURLParserService()
        for productID in ["E478656", "E482565", "E484997"] {
            let url = "https://store-kr.uniqlo.com/kr/ko/products/\(productID)-000/00"
            let result = try await parser.parse(urlString: url)
            let canonical = try #require(ParsedClosetClassification.resolve(
                category: result.category,
                detailCategory: result.detailCategory,
                sourceDepths: [result.sourceCategoryDepth1, result.sourceCategoryDepth2,
                               result.sourceCategoryDepth3, result.sourceCategoryDepth4],
                sourcePath: result.sourceCategoryPath,
                productName: result.productName
            ))
            #expect(canonical.categoryCode == "underwear")
            #expect(canonical.detailCode == "men_briefs")
            #expect(canonical.category == .underwear)
            #expect(canonical.detailCategory == .menBriefs)
        }
    }

    @Test func graphicTeesUseOfficialCategoryAndMeasurementsForShortSleeve() async throws {
        let parser = ProductURLParserService()
        for productID in ["E493045", "E493046"] {
            let url = "https://store-kr.uniqlo.com/kr/ko/products/\(productID)-000/00"
            let result = try await parser.parse(urlString: url)

            #expect(result.productID == productID)
            #expect(result.sourceCategoryPath?.contains("그래픽") == true)
            #expect(result.detailCategory == .shortSleeve)

            let canonical = try #require(ParsedClosetClassification.resolve(
                category: result.category,
                detailCategory: result.detailCategory,
                sourceDepths: [result.sourceCategoryDepth1, result.sourceCategoryDepth2,
                               result.sourceCategoryDepth3, result.sourceCategoryDepth4],
                sourcePath: result.sourceCategoryPath,
                productName: result.productName
            ))
            #expect(canonical.detailCode == "short_sleeve")
            #expect(canonical.garmentFamily == .tshirt)
            #expect(canonical.lengthType == .short)
        }
    }
}

@MainActor
@Suite(.enabled(
    if: runsLiveUniqloValidation,
    "직접 확인 상품 분류는 실서버 검증에서만 실행합니다."
))
struct LiveManualProductClassificationTests {
    @Test func reclassifiesStoredUnknownsThroughLiveProductionAPI() async throws {
        struct Candidate {
            let source: String
            let productID: String
            let productName: String
            let sourcePath: String

            var url: String {
                source == "musinsa"
                    ? "https://www.musinsa.com/products/\(productID)"
                    : "https://store-kr.uniqlo.com/kr/ko/products/\(productID)-000/00"
            }
        }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = [
            "LegacyMixed320ClassificationInputs",
            "LegacyUniqloRetest320ClassificationInputs",
            "LegacyUniqloThird320ClassificationInputs",
            "LegacyMusinsaFourth320ClassificationInputs",
            "Musinsa1037ClassificationInputs",
            "Uniqlo243ClassificationInputs",
        ]
        let uniqloMetadataParser = UniqloProductMetadataParser()
        var candidates: [Candidate] = []

        for resource in resources {
            let inputURL = repositoryRoot
                .appendingPathComponent("FitMatchTests")
                .appendingPathComponent(resource)
                .appendingPathExtension("json")
            let inputs = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL)) as? [[String: Any]]
            )
            for input in inputs {
                let source = try #require(input["source"] as? String)
                let productID = try #require(input["product_id"] as? String)
                let productName = try #require(input["product_name"] as? String)
                let sourcePath = try #require(input["source_path"] as? String)
                let depths = sourcePath.components(separatedBy: ">").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                let providerCategory: ClothingCategory
                let providerDetail: ClosetDetailCategory
                if source == "musinsa" {
                    providerCategory = MusinsaProductMetadataParser.mapCategory(from: sourcePath)
                    providerDetail = MusinsaProductMetadataParser.mapDetailCategory(
                        from: depths.count > 1 ? depths[1] : sourcePath
                    )
                } else {
                    providerCategory = uniqloMetadataParser.mapCategory(from: "\(sourcePath) \(productName)")
                    providerDetail = uniqloMetadataParser.mapDetailCategory(from: "\(sourcePath) \(productName)")
                }
                if ParsedClosetClassification.resolve(
                    category: providerCategory,
                    detailCategory: providerDetail,
                    sourceDepths: depths.map(Optional.some),
                    sourcePath: sourcePath,
                    productName: productName
                ) == nil {
                    candidates.append(.init(
                        source: source,
                        productID: productID,
                        productName: productName,
                        sourcePath: sourcePath
                    ))
                }
            }
        }

        let parser = ProductURLParserService()
        var unknown: [[String: Any]] = []
        var apiFailures: [[String: Any]] = []
        var classifiedCount = 0

        for (index, candidate) in candidates.enumerated() {
            let result: ParsedProductInfo
            do {
                result = try await parser.parse(urlString: candidate.url)
            } catch let error as ProductURLParserPartialError {
                result = error.productInfo.normalizedSizes()
            } catch {
                apiFailures.append([
                    "source": candidate.source,
                    "product_id": candidate.productID,
                    "product_name": candidate.productName,
                    "product_url": candidate.url,
                    "error": error.localizedDescription,
                ])
                continue
            }

            let classification = ParsedClosetClassification.resolve(
                category: result.category,
                detailCategory: result.detailCategory,
                sourceDepths: [result.sourceCategoryDepth1, result.sourceCategoryDepth2,
                               result.sourceCategoryDepth3, result.sourceCategoryDepth4],
                sourcePath: result.sourceCategoryPath,
                productName: result.productName
            )
            if let classification {
                classifiedCount += 1
                #expect(classification.detailCode != "other_tops")
            } else {
                unknown.append([
                    "source": candidate.source,
                    "product_id": candidate.productID,
                    "product_name": result.productName,
                    "product_url": candidate.url,
                    "source_path": result.sourceCategoryPath ?? candidate.sourcePath,
                    "provider_category": result.category.rawValue,
                    "provider_detail": result.detailCategory.rawValue,
                    "size_count": result.sizes.count,
                    "reason": "현재 로컬 운영 파서가 API 원본과 실측을 적용한 뒤에도 세부 카테고리를 확정하지 못함",
                ])
            }

            if (index + 1).isMultiple(of: 25) || index + 1 == candidates.count {
                print("FITMATCH_LIVE_UNKNOWN_PROGRESS \(index + 1)/\(candidates.count)")
            }
        }

        let documentDirectory = try #require(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let unknownURL = documentDirectory.appendingPathComponent("fitmatch-live-api-unknown-2560.json")
        let failureURL = documentDirectory.appendingPathComponent("fitmatch-live-api-failures-2560.json")
        try JSONSerialization.data(withJSONObject: unknown, options: [.prettyPrinted, .sortedKeys])
            .write(to: unknownURL, options: .atomic)
        try JSONSerialization.data(withJSONObject: apiFailures, options: [.prettyPrinted, .sortedKeys])
            .write(to: failureURL, options: .atomic)

        print("FITMATCH_LIVE_UNKNOWN_RESULT candidates=\(candidates.count) classified=\(classifiedCount) unknown=\(unknown.count) api_failures=\(apiFailures.count)")
        print("FITMATCH_LIVE_UNKNOWN_PATH \(unknownURL.path)")
        print("FITMATCH_LIVE_FAILURE_PATH \(failureURL.path)")
        #expect(classifiedCount + unknown.count + apiFailures.count == candidates.count)
        #expect(apiFailures.isEmpty)
    }

    @Test func classifiesManualConfirmationProductsThroughProductionPipeline() async {
        let products: [(provider: String, id: String, url: String)] = [
            ("MUSINSA", "5005347", "https://www.musinsa.com/products/5005347"),
            ("UNIQLO", "E493045", "https://store-kr.uniqlo.com/kr/ko/products/E493045-000/00"),
            ("UNIQLO", "E493046", "https://store-kr.uniqlo.com/kr/ko/products/E493046-000/00"),
            ("UNIQLO", "E488206", "https://store-kr.uniqlo.com/kr/ko/products/E488206-000/00"),
            ("MUSINSA", "3666383", "https://www.musinsa.com/products/3666383"),
            ("UNIQLO", "E488652", "https://store-kr.uniqlo.com/kr/ko/products/E488652-000/00"),
            ("MUSINSA", "1108007", "https://www.musinsa.com/products/1108007"),
            ("UNIQLO", "E489074", "https://store-kr.uniqlo.com/kr/ko/products/E489074-000/00"),
            ("MUSINSA", "1572220", "https://www.musinsa.com/products/1572220"),
            ("UNIQLO", "E488397", "https://store-kr.uniqlo.com/kr/ko/products/E488397-000/00"),
            ("MUSINSA", "1945314", "https://www.musinsa.com/products/1945314"),
            ("UNIQLO", "E488202", "https://store-kr.uniqlo.com/kr/ko/products/E488202-000/00"),
            ("MUSINSA", "5166592", "https://www.musinsa.com/products/5166592"),
            ("MUSINSA", "3033915", "https://www.musinsa.com/products/3033915"),
            ("UNIQLO", "E488200", "https://store-kr.uniqlo.com/kr/ko/products/E488200-000/00"),
            ("MUSINSA", "3229386", "https://www.musinsa.com/products/3229386"),
            ("MUSINSA", "6555227", "https://www.musinsa.com/products/6555227"),
            ("MUSINSA", "4702435", "https://www.musinsa.com/products/4702435"),
            ("MUSINSA", "3452955", "https://www.musinsa.com/products/3452955"),
            ("UNIQLO", "E489075", "https://store-kr.uniqlo.com/kr/ko/products/E489075-000/00"),
            ("UNIQLO", "E489399", "https://store-kr.uniqlo.com/kr/ko/products/E489399-000/00"),
            ("UNIQLO", "E489398", "https://store-kr.uniqlo.com/kr/ko/products/E489398-000/00")
        ]
        let confirmedDetails: [String: ClosetDetailCategory] = [
            "5005347": .shortSleeve,
            "E489074": .sweatshirt,
            "3033915": .sweatshirt,
            "4702435": .sweatshirt,
            "E489075": .sweatshirt
        ]
        let parser = ProductURLParserService()
        var completedCount = 0
        var completedIDs = Set<String>()

        for product in products {
            do {
                let result = try await parser.parse(urlString: product.url)
                let canonical = ParsedClosetClassification.resolve(
                    category: result.category,
                    detailCategory: result.detailCategory,
                    sourceDepths: [result.sourceCategoryDepth1, result.sourceCategoryDepth2,
                                   result.sourceCategoryDepth3, result.sourceCategoryDepth4],
                    sourcePath: result.sourceCategoryPath,
                    productName: result.productName
                )
                if let expectedDetail = confirmedDetails[product.id] {
                    #expect(
                        canonical?.detailCategory == expectedDetail,
                        "\(product.id): 확인된 분류 \(expectedDetail.rawValue)와 달라졌습니다."
                    )
                }
                let fields = [
                    "LIVE_CATEGORY_RESULT", product.provider, product.id,
                    result.productName.replacingOccurrences(of: "\t", with: " "),
                    canonical?.category.rawValue ?? result.category.rawValue,
                    canonical?.detailCategory.rawValue ?? result.detailCategory.rawValue,
                    canonical?.categoryCode ?? "unresolved",
                    canonical?.detailCode ?? "unresolved",
                    canonical?.garmentFamily.rawValue ?? "unknown",
                    canonical?.lengthType.rawValue ?? "unknown",
                    result.sourceCategoryPath?.replacingOccurrences(of: "\t", with: " ") ?? ""
                ]
                print(fields.joined(separator: "\t"))
                completedCount += 1
                completedIDs.insert(product.id)
            } catch {
                print(["LIVE_CATEGORY_ERROR", product.provider, product.id,
                       error.localizedDescription.replacingOccurrences(of: "\t", with: " ")]
                    .joined(separator: "\t"))
            }
        }

        #expect(completedCount > 0)
        #expect(Set(confirmedDetails.keys).isSubset(of: completedIDs))
    }
}

@MainActor
@Suite(.enabled(
    if: runsLiveMusinsaValidation,
    "실서버 검증은 FitMatchLiveValidation scheme으로 명시적으로 실행합니다."
))
struct LiveMusinsaValidationTests {
    @Test func circumferencePipelineSamplesPreserveParsedValues() async {
        let parser = MusinsaParser()

        for id in ["6391245", "6219777", "6045676"] {
            do {
                let result = try await parser.parse(from: productURL(id))
                #expect(result.productID == id, "\(id): 상품 ID가 유지되어야 합니다.")
                #expect(!result.productName.trimmedForLiveValidation.isEmpty, "\(id): 상품명이 필요합니다.")
                #expect(!result.sizes.isEmpty, "\(id): 검증할 사이즈가 필요합니다.")

                let rowsWithCircumference = result.sizes.compactMap { size -> String? in
                    guard let parsedChest = size.measurementRecords.first(where: {
                        $0.measurementCode == .chestCircumferenceGarment
                    }) else {
                        return nil
                    }

                    let form = ShoppingProductViewModel.makeSizeForm(
                        from: size,
                        displayOrder: 0,
                        allowsStandardSizeFallback: false
                    )
                    guard let storedSize = form.makeSizeOption(
                        category: result.category,
                        detailCategory: result.detailCategory
                    ),
                    let storedChest = storedSize.measurementRecords.first(where: {
                        $0.measurementCode == .chestCircumferenceGarment
                    }) else {
                        Issue.record("\(id) \(size.name): 가슴둘레를 저장 모델로 변환하지 못했습니다.")
                        return nil
                    }

                    #expect(form.chestUsesCircumference, "\(id) \(size.name): 둘레 입력 의미가 유지되어야 합니다.")
                    #expect(
                        abs(storedChest.value - parsedChest.value) < 0.001,
                        "\(id) \(size.name): 파싱값 \(parsedChest.value)과 저장값 \(storedChest.value)이 다릅니다."
                    )
                    return "\(size.name)=\(parsedChest.value)"
                }

                #expect(
                    !rowsWithCircumference.isEmpty,
                    "\(id): 실제 의류 가슴둘레가 하나 이상 파싱되어야 합니다."
                )
                print("LIVE_CIRCUMFERENCE \(id) \(rowsWithCircumference.joined(separator: ","))")
            } catch {
                Issue.record("\(id): 실서버 가슴둘레 파이프라인 실패 - \(error.localizedDescription)")
            }
        }
    }

    @Test func imageRejectionSamplesNeverProduceInvalidSizes() async {
        let parser = MusinsaParser()

        for id in ["3838933", "4898098", "5058151"] {
            do {
                let result = try await parser.parse(from: productURL(id))
                validateMetadata(result, expectedID: id)
                #expect(!result.sizes.isEmpty, "\(id): 성공 결과에는 사이즈가 필요합니다.")
                #expect(
                    ParsedSizeValidator.hasUsableMeasurements(result.sizes, category: result.category),
                    "\(id): 성공으로 반환된 사이즈에는 비교 가능한 실측이 필요합니다."
                )
                print("LIVE_IMAGE_GUARD \(id) parsed sizes=\(result.sizes.map(\.name))")
            } catch let error as ProductURLParserPartialError {
                let result = error.productInfo
                validateMetadata(result, expectedID: id)
                #expect(result.sizes.isEmpty, "\(id): 부분 실패 결과에 검증되지 않은 사이즈가 포함되면 안 됩니다.")
                #expect(result.sizeTableRecoveryContext != nil, "\(id): 직접 복구 경로 정보가 필요합니다.")
                print("LIVE_IMAGE_GUARD \(id) safely-rejected")
            } catch {
                Issue.record("\(id): 실서버 이미지 거부 검증 실패 - \(error.localizedDescription)")
            }
        }
    }

    private func productURL(_ id: String) -> URL {
        URL(string: "https://www.musinsa.com/products/\(id)")!
    }

    private func validateMetadata(_ result: ParsedProductInfo, expectedID: String) {
        #expect(result.productID == expectedID, "\(expectedID): 상품 ID가 유지되어야 합니다.")
        #expect(!result.productName.trimmedForLiveValidation.isEmpty, "\(expectedID): 상품명이 필요합니다.")
        #expect(!result.brandName.trimmedForLiveValidation.isEmpty, "\(expectedID): 브랜드명이 필요합니다.")
    }
}

@MainActor
@Suite(.enabled(
    if: runsLiveMusinsaValidation,
    "320개 상품 코퍼스 검증은 FitMatchLiveValidation scheme으로 실행합니다."
))
struct LiveProductCorpusValidationTests {
    @Test func replays320StoredProductsThroughProductionClassification() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = repositoryRoot.appendingPathComponent("Docs/Research/NewClothingCorpus-320-20260806")
        let products = try CorpusInput.manifestProducts(at: directory.appendingPathComponent("clothing_product_manifest.json"))
        let expectedRows = try CorpusCSV.rows(from: directory.appendingPathComponent("fitmatch_category_grouped_products.csv"))
        let expected = Dictionary(uniqueKeysWithValues: expectedRows.compactMap { row -> (String, [String: String])? in
            guard let source = row["판매처"], let productID = row["상품ID"] else { return nil }
            return ("\(source):\(productID)", row)
        })
        let environment = ProcessInfo.processInfo.environment
        let offset = Int(environment["FITMATCH_STORED_OFFSET"] ?? "0") ?? 0
        let limit = Int(environment["FITMATCH_STORED_LIMIT"] ?? "320") ?? 320
        let upperBound = min(offset + max(limit, 1), products.count)
        let selected = offset < upperBound ? Array(products[offset..<upperBound]) : []

        var parsedCount = 0
        var categoryMatches = 0
        var detailMatches = 0
        var classificationComparable = 0
        var failures: [String] = []
        for (index, product) in selected.enumerated() {
            guard let source = product["source"] as? String,
                  let productID = product["product_key"] as? String,
                  let evidence = (product["raw_evidence"] as? [[String: Any]])?.first,
                  let path = evidence["path"] as? String else { continue }
            let fileURL = URL(fileURLWithPath: path, relativeTo: repositoryRoot).standardizedFileURL
            let sourceURL = URL(string: source == "musinsa"
                ? "https://www.musinsa.com/products/\(productID)"
                : "https://www.uniqlo.com/kr/ko/products/\(productID)")!
            do {
                print("STORED_CORPUS_START \(offset + index + 1)/\(products.count) \(source):\(productID) \(fileURL.path)")
                let info: ParsedProductInfo
                if source == "musinsa" {
                    let data = try Data(contentsOf: fileURL)
                    print("STORED_CORPUS_LOADED \(source):\(productID) bytes=\(data.count)")
                    let metadata = try MusinsaProductMetadataParser()
                        .parseStoredProductDetail(data: data, productID: productID, sourceURL: sourceURL)
                    print("STORED_CORPUS_METADATA \(source):\(productID) \(metadata.category.rawValue)/\(metadata.detailCategory.rawValue)")
                    info = metadata.parsedProductInfo(sizes: [])
                } else {
                    let observedID = (product["observed_ids"] as? [String])?.first ?? productID
                    let rawColor = observedID.components(separatedBy: "-").dropFirst().first ?? "000"
                    let resolver = UniqloURLResolver()
                    let resolved = ResolvedUniqloURL(
                        originalURL: sourceURL,
                        resolvedURL: sourceURL,
                        productID: productID,
                        goodsID: productID.hasPrefix("E") ? String(productID.dropFirst()) : productID,
                        apiColorCode: resolver.normalizeAPIColorCode(rawColor),
                        imageColorCode: resolver.normalizeImageColorCode(rawColor),
                        productIDWithColorCode: observedID,
                        html: try String(contentsOf: fileURL, encoding: .utf8)
                    )
                    info = UniqloProductMetadataParser().parse(resolved: resolved).parsedProductInfo(sizes: [])
                }
                parsedCount += 1
                let row = expected["\(source):\(productID)"]
                let actualCategory = info.category.serviceGroup.rawValue
                let actualDetail = info.detailCategory.rawValue
                if row?["핏매치_관리카테고리"] == actualCategory { categoryMatches += 1 }
                if row?["핏매치_세부카테고리"] == actualDetail { detailMatches += 1 }
                if info.category.serviceGroup != .other && info.detailCategory != .other {
                    classificationComparable += 1
                }
                if row?["핏매치_관리카테고리"] != actualCategory || row?["핏매치_세부카테고리"] != actualDetail {
                    print("STORED_CORPUS_MISMATCH \(source):\(productID) expected=\(row?["핏매치_관리카테고리"] ?? "nil")/\(row?["핏매치_세부카테고리"] ?? "nil") actual=\(actualCategory)/\(actualDetail)")
                }
                print("STORED_CORPUS_PROGRESS \(offset + index + 1)/\(products.count) \(source):\(productID)")
            } catch {
                failures.append("\(source):\(productID):\(error.localizedDescription)")
            }
        }
        print("STORED_CORPUS_RESULT offset=\(offset), total=\(selected.count), parsed=\(parsedCount), category=\(categoryMatches)/\(selected.count), detail=\(detailMatches)/\(selected.count), classificationComparable=\(classificationComparable)/\(selected.count), failures=\(failures.count)")
        failures.forEach { print("STORED_CORPUS_FAILURE \($0)") }
        #expect(products.count == 320)
        #expect(parsedCount == selected.count)
    }

    @Test func validatesAtLeast320LiveProductsThroughFitMatchParser() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let corpusDirectory = repositoryRoot
            .appendingPathComponent("Docs/Research/NewClothingCorpus-320-20260806")
        let manifestURL = corpusDirectory.appendingPathComponent("clothing_product_manifest.json")
        let expectedURL = corpusDirectory.appendingPathComponent("fitmatch_category_grouped_products.csv")
        let inputs = try CorpusInput.newClothingCorpus(manifestURL: manifestURL, expectedURL: expectedURL)

        #expect(inputs.count == 320, "신규 의류 코퍼스는 정확히 320개여야 합니다.")
        #expect(Set(inputs.map(\.deduplicationKey)).count == inputs.count, "검증 상품은 중복되면 안 됩니다.")

        let environment = ProcessInfo.processInfo.environment
        let offset = Int(environment["FITMATCH_CORPUS_OFFSET"] ?? "0") ?? 0
        let requestedLimit = Int(environment["FITMATCH_CORPUS_LIMIT"] ?? "20") ?? 20
        let upperBound = min(offset + max(requestedLimit, 1), inputs.count)
        #expect(offset >= 0 && offset < inputs.count, "코퍼스 시작 위치가 범위를 벗어났습니다.")
        let shardInputs = offset < upperBound ? Array(inputs[offset..<upperBound]) : []
        #expect(!shardInputs.isEmpty, "실행할 코퍼스 묶음이 비어 있습니다.")

        var results: [CorpusResult] = []
        let outputURL = URL(fileURLWithPath: "/tmp/FitMatchLiveCorpusValidation-20260806-\(offset)-\(upperBound).json")
        for (index, input) in shardInputs.enumerated() {
            let startedAt = Date()
            do {
                let parsed = try await parseWithTimeout(input: input, seconds: 45)
                results.append(CorpusResult(
                    input: input,
                    status: "success",
                    parsed: parsed,
                    error: nil,
                    durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                ))
            } catch let partial as ProductURLParserPartialError {
                results.append(CorpusResult(
                    input: input,
                    status: "partial",
                    parsed: partial.productInfo,
                    error: partial.localizedDescription,
                    durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                ))
            } catch {
                results.append(CorpusResult(
                    input: input,
                    status: "failure",
                    parsed: nil,
                    error: error.localizedDescription,
                    durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                ))
            }
            try write(CorpusOutput(generatedAt: Date(), corpusTotal: inputs.count, offset: offset, results: results), to: outputURL)
            print("LIVE_CORPUS_PROGRESS \(offset + index + 1)/\(inputs.count)")
        }

        let output = CorpusOutput(generatedAt: Date(), corpusTotal: inputs.count, offset: offset, results: results)
        try write(output, to: outputURL)

        print("LIVE_CORPUS_RESULT \(output.summary)")
        print("LIVE_CORPUS_OUTPUT \(outputURL.path)")
        #expect(results.count == shardInputs.count)
    }

    private func parse(input: CorpusInput) async throws -> ParsedProductInfo {
        guard let url = URL(string: input.url) else { throw ProductURLParserError.invalidURL }
        if input.source == "무신사" {
            return try await MusinsaActualSizeAPIParser().parse(from: url).normalizedSizes()
        }
        return try await UniqloParser().parse(from: url).normalizedSizes()
    }

    private func parseWithTimeout(input: CorpusInput, seconds: UInt64) async throws -> ParsedProductInfo {
        try await withThrowingTaskGroup(of: ParsedProductInfo.self) { group in
            group.addTask { @MainActor in
                try await parse(input: input)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw CorpusTimeoutError(seconds: seconds)
            }
            guard let first = try await group.next() else {
                throw CorpusTimeoutError(seconds: seconds)
            }
            group.cancelAll()
            return first
        }
    }

    private func write(_ output: CorpusOutput, to outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(output).write(to: outputURL, options: .atomic)
    }
}

private struct CorpusTimeoutError: LocalizedError {
    let seconds: UInt64
    var errorDescription: String? { "상품 파싱이 \(seconds)초를 초과했습니다." }
}

private struct CorpusInput: Codable {
    let source: String
    let productID: String
    let url: String
    let expectedCategory: String?
    let expectedDetailCategory: String?
    let expectedProductName: String?
    let sampleOrigin: String

    var deduplicationKey: String { "\(source):\(productID)" }

    init?(surveyRow: [String: String]) {
        guard let source = surveyRow["쇼핑몰"],
              let productID = surveyRow["상품 ID 또는 코드"],
              let url = surveyRow["상품 URL"],
              !source.isEmpty, !productID.isEmpty, !url.isEmpty else { return nil }
        self.source = source
        self.productID = productID
        self.url = url
        expectedCategory = surveyRow["조사자 앱 대분류 후보"]
        expectedDetailCategory = surveyRow["조사자 상세분류 후보"]
        expectedProductName = surveyRow["상품명"]
        sampleOrigin = "LiveProductSurvey-20260723"
    }

    private init(source: String, productID: String, url: String, sampleOrigin: String) {
        self.source = source
        self.productID = productID
        self.url = url
        expectedCategory = nil
        expectedDetailCategory = nil
        expectedProductName = nil
        self.sampleOrigin = sampleOrigin
    }

    private init(
        source: String,
        productID: String,
        url: String,
        expectedCategory: String?,
        expectedDetailCategory: String?,
        expectedProductName: String?,
        sampleOrigin: String
    ) {
        self.source = source
        self.productID = productID
        self.url = url
        self.expectedCategory = expectedCategory
        self.expectedDetailCategory = expectedDetailCategory
        self.expectedProductName = expectedProductName
        self.sampleOrigin = sampleOrigin
    }

    static func newClothingCorpus(manifestURL: URL, expectedURL: URL) throws -> [CorpusInput] {
        let expectedRows = try CorpusCSV.rows(from: expectedURL)
        let expected = Dictionary(uniqueKeysWithValues: expectedRows.compactMap { row -> (String, [String: String])? in
            guard let source = row["판매처"], let productID = row["상품ID"] else { return nil }
            return ("\(source):\(productID)", row)
        })
        return try manifestProducts(at: manifestURL).compactMap { product in
            guard let sourceCode = product["source"] as? String,
                  let productKey = product["product_key"] as? String else { return nil }
            let source = sourceCode == "musinsa" ? "무신사" : "유니클로"
            let observedID = (product["observed_ids"] as? [String])?.first ?? productKey
            let url = sourceCode == "musinsa"
                ? "https://www.musinsa.com/products/\(productKey)"
                : "https://www.uniqlo.com/kr/ko/products/\(observedID)/00"
            let row = expected["\(sourceCode):\(productKey)"]
            return CorpusInput(
                source: source,
                productID: productKey,
                url: url,
                expectedCategory: row?["핏매치_관리카테고리"],
                expectedDetailCategory: row?["핏매치_세부카테고리"],
                expectedProductName: row?["상품명"],
                sampleOrigin: "NewClothingCorpus-320-20260806"
            )
        }
    }

    static func additionalInputs(
        mediumManifestURL: URL,
        uniqloManifestURL: URL,
        excluding originalKeys: Set<String>,
        musinsaLimit: Int,
        uniqloLimit: Int
    ) throws -> [CorpusInput] {
        let musinsa = try manifestProducts(at: mediumManifestURL)
            .filter { $0["source"] as? String == "musinsa" }
            .compactMap { product -> CorpusInput? in
                guard let id = product["product_key"] as? String else { return nil }
                return CorpusInput(
                    source: "무신사",
                    productID: id,
                    url: "https://www.musinsa.com/products/\(id)",
                    sampleOrigin: "CategoryCorpus-live-medium"
                )
            }
            .filter { !originalKeys.contains($0.deduplicationKey) }
            .sorted { $0.productID < $1.productID }
            .prefix(musinsaLimit)

        let uniqlo = try manifestProducts(at: uniqloManifestURL)
            .filter { $0["source"] as? String == "uniqlo" }
            .compactMap { product -> CorpusInput? in
                guard let observed = (product["observed_ids"] as? [String])?.first else { return nil }
                return CorpusInput(
                    source: "유니클로",
                    productID: observed,
                    url: "https://www.uniqlo.com/kr/ko/products/\(observed)",
                    sampleOrigin: "CategoryCorpus-live-uniqlo-full"
                )
            }
            .filter { !originalKeys.contains($0.deduplicationKey) }
            .sorted { $0.productID < $1.productID }
            .prefix(uniqloLimit)

        return Array(musinsa) + Array(uniqlo)
    }

    static func manifestProducts(at url: URL) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["products"] as? [[String: Any]] ?? []
    }
}

private struct CorpusResult: Codable {
    let input: CorpusInput
    let status: String
    let parsedProductID: String?
    let parsedProductName: String?
    let parsedBrandName: String?
    let parsedCategory: String?
    let parsedDetailCategory: String?
    let sourceCategoryPath: String?
    let sizeCount: Int
    let measurementCount: Int
    let categoryMatchesExpected: Bool?
    let detailCategoryMatchesExpected: Bool?
    let productNameMatchesExpected: Bool?
    let error: String?
    let durationMilliseconds: Double

    @MainActor
    init(input: CorpusInput, status: String, parsed: ParsedProductInfo?, error: String?, durationMilliseconds: Double) {
        self.input = input
        self.status = status
        parsedProductID = parsed?.productID
        parsedProductName = parsed?.productName
        parsedBrandName = parsed?.brandName
        parsedCategory = parsed?.category.serviceGroup.rawValue
        parsedDetailCategory = parsed?.detailCategory.rawValue
        sourceCategoryPath = parsed?.sourceCategoryPath
        sizeCount = parsed?.sizes.count ?? 0
        measurementCount = parsed?.sizes.reduce(0) { $0 + $1.measurementRecords.count } ?? 0
        if let expected = input.expectedCategory, !expected.isEmpty, let actual = parsed?.category.serviceGroup.rawValue {
            categoryMatchesExpected = CorpusResult.normalizedExpectedCategory(expected) == actual
        } else {
            categoryMatchesExpected = nil
        }
        if let expected = input.expectedDetailCategory, !expected.isEmpty, let actual = parsed?.detailCategory.rawValue {
            detailCategoryMatchesExpected = expected == actual
        } else {
            detailCategoryMatchesExpected = nil
        }
        if let expected = input.expectedProductName, !expected.isEmpty, let actual = parsed?.productName {
            productNameMatchesExpected = CorpusResult.normalized(expected) == CorpusResult.normalized(actual)
        } else {
            productNameMatchesExpected = nil
        }
        self.error = error
        self.durationMilliseconds = durationMilliseconds
    }

    private static func normalizedExpectedCategory(_ value: String) -> String {
        value == "바지" || value == "팬츠" ? ClothingCategory.bottom.rawValue : value
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace }
    }
}

private struct CorpusOutput: Codable {
    let generatedAt: Date
    let corpusTotal: Int
    let offset: Int
    let results: [CorpusResult]

    var summary: String {
        let statuses = Dictionary(grouping: results, by: \.status).mapValues(\.count)
        let comparable = results.filter { $0.measurementCount > 0 }.count
        let categoryEvaluated = results.compactMap(\.categoryMatchesExpected)
        let categoryMatches = categoryEvaluated.filter { $0 }.count
        let detailEvaluated = results.compactMap(\.detailCategoryMatchesExpected)
        let detailMatches = detailEvaluated.filter { $0 }.count
        let successCount = statuses["success", default: 0]
        let partialCount = statuses["partial", default: 0]
        let failureCount = statuses["failure", default: 0]
        return "total=\(results.count), success=\(successCount), partial=\(partialCount), failure=\(failureCount), measurements=\(comparable), category=\(categoryMatches)/\(categoryEvaluated.count), detail=\(detailMatches)/\(detailEvaluated.count)"
    }
}

private enum CorpusCSV {
    static func rows(from url: URL) throws -> [[String: String]] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let records = parse(content)
        guard let headers = records.first else { return [] }
        return records.dropFirst().compactMap { values in
            guard values.count == headers.count else { return nil }
            return Dictionary(uniqueKeysWithValues: zip(headers, values))
        }
    }

    private static func parse(_ content: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field: [Character] = []
        var isQuoted = false
        let characters = Array(content)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                record.append(String(field))
                field.removeAll(keepingCapacity: true)
            } else if (character == "\n" || character == "\r"), !isQuoted {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                record.append(String(field))
                if !record.allSatisfy(\.isEmpty) { records.append(record) }
                record = []
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(String(field))
            records.append(record)
        }
        return records
    }
}

private extension String {
    var trimmedForLiveValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
