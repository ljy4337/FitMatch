import Foundation
import ImageIO
import Vision

struct MusinsaFallbackSizeParser {
    func parse(
        goodsContents: String,
        category: ClothingCategory,
        categoryDepth2Name: String?
    ) async -> [ParsedProductSize] {
        guard let family = MusinsaFallbackGarmentFamily(
            category: category,
            categoryDepth2Name: categoryDepth2Name
        ) else { return [] }

        let htmlSizes = MusinsaFallbackTableParser.parseHTML(goodsContents, family: family)
        if !htmlSizes.isEmpty { return htmlSizes }

        let images = MusinsaFallbackImageExtractor.images(in: goodsContents)
        let explicitImages = images.filter(\.isExplicitSizeImage)
        for image in explicitImages.prefix(3) {
            if let sizes = await MusinsaFallbackImageOCR.parse(url: image.url, family: family, requiresTableRectangle: false),
               !sizes.isEmpty {
                return sizes
            }
        }

        let longImages = images
            .filter {
                !$0.isExplicitSizeImage
                    && ($0.isLongImageCandidate || $0.declaredHeight == nil || $0.declaredWidth == nil)
            }
            .prefix(6)
        for image in longImages {
            if let sizes = await MusinsaFallbackImageOCR.parse(url: image.url, family: family, requiresTableRectangle: true),
               !sizes.isEmpty {
                return sizes
            }
        }
        return []
    }
}

enum MusinsaFallbackGarmentFamily {
    case upper
    case lower
    case shoes

    init?(category: ClothingCategory, categoryDepth2Name: String? = nil) {
        switch category.serviceGroup {
        case .top, .outer, .dress: self = .upper
        case .bottom: self = .lower
        case .shoes:
            guard categoryDepth2Name?.contains("용품") != true else { return nil }
            self = .shoes
        default: return nil
        }
    }
}

struct MusinsaFallbackImage {
    let url: URL
    let sourceText: String
    let declaredWidth: Double?
    let declaredHeight: Double?

    var isExplicitSizeImage: Bool {
        let normalized = sourceText.lowercased()
        let pattern = #"(^|[/_.\-])(actual[\-_]?size|size[\-_]?(guide|chart|spec|info)?|spec)([/_.\-]|$)"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
            && !normalized.contains("modelspec")
    }

    var isLongImageCandidate: Bool {
        guard let declaredWidth, let declaredHeight, declaredWidth > 0 else { return false }
        return declaredHeight / declaredWidth >= 3
    }
}

enum MusinsaFallbackImageExtractor {
    static func images(in html: String) -> [MusinsaFallbackImage] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard let sourceRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range(at: 0), in: html) else { return nil }
            let rawURL = String(html[sourceRange]).htmlEntityDecoded
            let resolved = normalizedURL(rawURL)
            guard let resolved, seen.insert(resolved.absoluteString).inserted else { return nil }
            let tag = String(html[tagRange])
            return MusinsaFallbackImage(
                url: resolved,
                sourceText: "\(rawURL) \(attribute("alt", in: tag) ?? "") \(attribute("title", in: tag) ?? "")",
                declaredWidth: numberAttribute("width", in: tag),
                declaredHeight: numberAttribute("height", in: tag)
            )
        }
    }

    private static func normalizedURL(_ value: String) -> URL? {
        if value.hasPrefix("//") { return URL(string: "https:\(value)") }
        if value.hasPrefix("/") { return URL(string: "https://image.msscdn.net\(value)") }
        return URL(string: value)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b\#(name)\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ), let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)),
           let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range]).htmlEntityDecoded
    }

    private static func numberAttribute(_ name: String, in tag: String) -> Double? {
        attribute(name, in: tag).flatMap(Double.init)
    }
}

enum MusinsaFallbackTableParser {
    static func parseHTML(_ html: String, family: MusinsaFallbackGarmentFamily) -> [ParsedProductSize] {
        guard let tableRegex = try? NSRegularExpression(
            pattern: #"<table\b[^>]*>(.*?)</table>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for tableMatch in tableRegex.matches(in: html, range: range) {
            guard let tableRange = Range(tableMatch.range(at: 1), in: html) else { continue }
            let grid = rows(in: String(html[tableRange]))
            let nsHTML = html as NSString
            let start = max(0, tableMatch.range.location - 400)
            let end = min(nsHTML.length, NSMaxRange(tableMatch.range) + 400)
            let context = nsHTML.substring(with: NSRange(location: start, length: end - start)).strippingHTML
            if let result = parseGrid(grid, context: context, family: family), !result.isEmpty {
                return result
            }
        }
        return []
    }

    static func parseGrid(
        _ rawGrid: [[String]],
        context: String,
        family: MusinsaFallbackGarmentFamily
    ) -> [ParsedProductSize]? {
        var grid = rawGrid
            .map { $0.map(\.trimmedCell).filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        guard grid.count >= 3 else { return nil }
        if grid[0].count >= 3,
           isUnitOnlyCell(grid[0][0]),
           grid[0].dropFirst().filter({ isSizeValue($0) }).count >= 2 {
            grid[0][0] = "size"
        }
        grid = grid.map { mergedHeaderCells($0, family: family) }
        let normalized = grid.map { $0.map(\.normalizedSizeHeader) }
        let unit = unitMultiplier(in: "\(context) \(grid.flatMap { $0 }.joined(separator: " "))")
        guard let unit else { return nil }

        if let headerIndex = normalized.firstIndex(where: { row in
            row.contains(where: isSizeHeader) && row.contains(where: { column(for: $0, family: family) != nil })
        }) {
            let headers = normalized[headerIndex]
            let rows = Array(grid.dropFirst(headerIndex + 1)).filter { $0.count == headers.count }
            return makeSizes(headers: headers, rows: rows, unit: unit, family: family)
        }

        let transposed = transpose(grid)
        let transposedNormalized = transposed.map { $0.map(\.normalizedSizeHeader) }
        if let headerIndex = transposedNormalized.firstIndex(where: { row in
            row.contains(where: isSizeHeader) && row.contains(where: { column(for: $0, family: family) != nil })
        }) {
            let headers = transposedNormalized[headerIndex]
            let rows = Array(transposed.dropFirst(headerIndex + 1)).filter { $0.count == headers.count }
            return makeSizes(headers: headers, rows: rows, unit: unit, family: family)
        }
        return nil
    }

    private static func mergedHeaderCells(
        _ row: [String],
        family: MusinsaFallbackGarmentFamily
    ) -> [String] {
        let normalized = row.map(\.normalizedSizeHeader)
        guard normalized.contains(where: isSizeHeader) else { return row }

        var result: [String] = []
        var index = 0
        while index < row.count {
            let maxLength = min(3, row.count - index)
            var merged: String?
            var consumed = 1
            if isSizeHeader(normalized[index]) {
                merged = row[index]
            } else {
                for length in stride(from: maxLength, through: 1, by: -1) {
                    let candidate = normalized[index..<(index + length)].joined()
                    if column(for: candidate, family: family) != nil {
                        merged = row[index..<(index + length)].joined()
                        consumed = length
                        break
                    }
                }
            }
            result.append(merged ?? row[index])
            index += consumed
        }
        return result
    }

    private static func rows(in table: String) -> [[String]] {
        guard let rowRegex = try? NSRegularExpression(
            pattern: #"<tr\b[^>]*>(.*?)</tr>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let cellRegex = try? NSRegularExpression(
            pattern: #"<t[hd]\b[^>]*>(.*?)</t[hd]>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        return rowRegex.matches(in: table, range: NSRange(table.startIndex..<table.endIndex, in: table)).compactMap { rowMatch in
            guard let range = Range(rowMatch.range(at: 1), in: table) else { return nil }
            let row = String(table[range])
            return cellRegex.matches(in: row, range: NSRange(row.startIndex..<row.endIndex, in: row)).compactMap { cell in
                guard let range = Range(cell.range(at: 1), in: row) else { return nil }
                return String(row[range]).strippingHTML
            }
        }
    }

    private static func transpose(_ grid: [[String]]) -> [[String]] {
        guard let count = grid.map(\.count).min(), count >= 3 else { return [] }
        return (0..<count).map { column in grid.map { $0[column] } }
    }

    private static func makeSizes(
        headers: [String],
        rows: [[String]],
        unit: Double,
        family: MusinsaFallbackGarmentFamily
    ) -> [ParsedProductSize]? {
        guard let sizeIndex = headers.firstIndex(where: isSizeHeader) else { return nil }
        let mappedColumns = headers.enumerated().compactMap { index, header in
            column(for: header, family: family).map { (index, $0, header) }
        }
        guard requiredColumns(mappedColumns.map(\.1), family: family) else { return nil }

        var seen = Set<String>()
        let parsed = rows.compactMap { row -> ParsedProductSize? in
            guard row.indices.contains(sizeIndex) else { return nil }
            let sizeName = row[sizeIndex].trimmedCell
            guard isSizeValue(sizeName), seen.insert(sizeName.uppercased()).inserted else { return nil }
            var measurements = GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 0,
                sleeveLength: 0
            )
            var records: [ParsedMeasurement] = []
            for (index, mapped, rawHeader) in mappedColumns {
                guard row.indices.contains(index), let rawValue = strictNumber(row[index]) else { continue }
                let sourceValue = rawValue * unit
                guard sourceValue.isFinite, sourceValue > 0, sourceValue < 300 else { continue }
                let record = mapped.record(value: sourceValue, rawLabel: rawHeader, rawValue: row[index])
                records.append(record)
                if record.semanticStatus == .mapped,
                   mapped != .chestCircumference {
                    measurements.set(record.value, for: record.displayKind)
                }
            }
            guard requiredRecords(records, family: family) else { return nil }
            return ParsedProductSize(name: sizeName, measurements: measurements, measurementRecords: records)
        }
        return parsed.count >= 2 ? parsed : nil
    }

    private static func requiredColumns(_ columns: [FallbackColumn], family: MusinsaFallbackGarmentFamily) -> Bool {
        switch family {
        case .upper:
            return columns.contains(where: { $0 == .chestWidth || $0 == .chestCircumference })
                && columns.contains(where: { [.length, .shoulder, .sleeve].contains($0) })
        case .lower:
            return columns.contains(where: { $0 == .waistWidth || $0 == .waistCircumference })
                && columns.contains(where: { [.hip, .hipCircumference, .thigh, .rise, .outseam, .inseam].contains($0) })
        case .shoes:
            return columns.contains(.footLength)
        }
    }

    private static func requiredRecords(_ records: [ParsedMeasurement], family: MusinsaFallbackGarmentFamily) -> Bool {
        requiredColumns(records.compactMap { FallbackColumn(record: $0) }, family: family)
    }

    private static func unitMultiplier(in text: String) -> Double? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        let hits = [
            normalized.range(of: #"(?<![a-z])cm(?![a-z])|센티미터"#, options: .regularExpression) != nil ? 1.0 : nil,
            normalized.range(of: #"(?<![a-z])mm(?![a-z])|밀리미터"#, options: .regularExpression) != nil ? 0.1 : nil,
            normalized.range(of: #"(?<![a-z])inch(?:es)?(?![a-z])|인치"#, options: .regularExpression) != nil ? 2.54 : nil
        ].compactMap { $0 }
        if hits.isEmpty { return 1 }
        return Set(hits).count == 1 ? hits[0] : nil
    }

    private static func isUnitOnlyCell(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["cm", "mm", "inch", "inches"].contains(normalized)
    }

    nonisolated private static func isSizeHeader(_ text: String) -> Bool {
        ["사이즈", "size", "호칭", "옵션"].contains(text)
    }

    private static func isSizeValue(_ text: String) -> Bool {
        let value = text.uppercased().replacingOccurrences(of: " ", with: "")
        return value.range(
            of: #"^(XXS|XS|S|M|L|XL|XXL|XXXL|[2-5]XL|FREE|ONE|[0-9]{2,3}(?:[-/][0-9]{2,3})?)$"#,
            options: .regularExpression
        ) != nil
    }

    private static func strictNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmedCell
        guard normalized.range(of: #"^\d{1,3}(?:\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(normalized)
    }

    private static func column(for header: String, family: MusinsaFallbackGarmentFamily) -> FallbackColumn? {
        switch header {
        case "가슴", "가슴단면", "가슴너비", "품", "chest", "chestwidth", "pit-to-pit", "pittopit": return .chestWidth
        case "가슴둘레", "chestcircumference", "bustcircumference": return .chestCircumference
        case "어깨", "어깨너비", "shoulder", "shoulderwidth": return .shoulder
        case "총장", "총기장", "총길이", "옷길이", "옷길이아웃심", "length", "bodylength", "outseam":
            return family == .lower ? .outseam : .length
        case "소매", "소매길이", "sleeve", "sleevelength": return .sleeve
        case "허리단면", "허리너비", "waistwidth": return .waistWidth
        case "허리둘레", "waistcircumference": return .waistCircumference
        case "엉덩이단면", "엉덩이너비", "힙단면", "hipwidth": return .hip
        case "엉덩이둘레", "힙둘레", "hipcircumference": return .hipCircumference
        case "허벅지단면", "허벅지너비", "thighwidth": return .thigh
        case "밑위", "앞밑위", "앞밑위길이", "rise", "frontrise": return .rise
        case "인심", "inseam": return .inseam
        case "발길이", "발길이정보", "footlength", "feetlength": return family == .shoes ? .footLength : nil
        default: return nil
        }
    }
}

private enum FallbackColumn: Equatable {
    case chestWidth, chestCircumference, shoulder, length, sleeve
    case outseam
    case waistWidth, waistCircumference, hip, hipCircumference, thigh, rise, inseam, footLength

    init?(record: ParsedMeasurement) {
        switch record.measurementCode {
        case .chestWidthPitToPit: self = .chestWidth
        case .chestCircumferenceGarment: self = .chestCircumference
        case .shoulderWidthSeamToSeam: self = .shoulder
        case .bodyLengthBackNeckToHem: self = .length
        case .pantsOutseamWaistToHem: self = .outseam
        case .sleeveShoulderSeamToCuff: self = .sleeve
        case .waistWidthEdgeToEdge: self = .waistWidth
        case .waistCircumferenceGarment: self = .waistCircumference
        case .hipWidthAtWidest: self = .hip
        case .thighWidthCrotchToOuter: self = .thigh
        case .riseCrotchToWaistFront: self = .rise
        case .pantsInseamCrotchToHem: self = .inseam
        case .footLengthHeelToToe: self = .footLength
        default: return nil
        }
    }

    func record(value: Double, rawLabel: String, rawValue: String) -> ParsedMeasurement {
        let code: MeasurementCode
        let kind: MeasurementDisplayKind
        let multiplier: Double
        switch self {
        case .chestWidth: (code, kind, multiplier) = (.chestWidthPitToPit, .chest, 1)
        case .chestCircumference: (code, kind, multiplier) = (.chestCircumferenceGarment, .chest, 1)
        case .shoulder: (code, kind, multiplier) = (.shoulderWidthSeamToSeam, .shoulder, 1)
        case .length: (code, kind, multiplier) = (.bodyLengthBackNeckToHem, .totalLength, 1)
        case .outseam: (code, kind, multiplier) = (.pantsOutseamWaistToHem, .totalLength, 1)
        case .sleeve: (code, kind, multiplier) = (.sleeveShoulderSeamToCuff, .sleeveLength, 1)
        case .waistWidth: (code, kind, multiplier) = (.waistWidthEdgeToEdge, .waist, 1)
        case .waistCircumference: (code, kind, multiplier) = (.waistWidthEdgeToEdge, .waist, 0.5)
        case .hip: (code, kind, multiplier) = (.hipWidthAtWidest, .hip, 1)
        case .hipCircumference: (code, kind, multiplier) = (.hipWidthAtWidest, .hip, 0.5)
        case .thigh: (code, kind, multiplier) = (.thighWidthCrotchToOuter, .thigh, 1)
        case .rise: (code, kind, multiplier) = (.riseCrotchToWaistFront, .rise, 1)
        case .inseam: (code, kind, multiplier) = (.pantsInseamCrotchToHem, .totalLength, 1)
        case .footLength: (code, kind, multiplier) = (.footLengthHeelToToe, .footLength, 1)
        }
        return ParsedMeasurement(
            value: value * multiplier,
            measurementCode: code,
            displayKind: kind,
            methodSource: "musinsa_fallback",
            methodProfile: "structured_size_table",
            inputSource: .importedSizeChart,
            mappingVersion: "musinsa_fallback_mapping_v1",
            rawLabel: rawLabel,
            rawInfo: multiplier == 0.5 ? "circumference_to_width_multiplier=0.5" : nil,
            rawValueText: rawValue,
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
    }
}

@MainActor
enum MusinsaFallbackImageOCR {
    static func parse(
        url: URL,
        family: MusinsaFallbackGarmentFamily,
        requiresTableRectangle: Bool
    ) async -> [ParsedProductSize]? {
        guard let data = try? await fetch(url),
              data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "사이즈 이미지 로드",
            details: "URL=\(url.absoluteString), 크기=\(image.width)x\(image.height)"
        )
        #endif
        return parse(
            image: image,
            family: family,
            requiresTableRectangle: requiresTableRectangle,
            sourceDescription: url.absoluteString
        )
    }

    static func parse(
        image: CGImage,
        family: MusinsaFallbackGarmentFamily,
        requiresTableRectangle: Bool,
        sourceDescription: String = "in-memory"
    ) -> [ParsedProductSize]? {
        let regions: [CGRect]
        if requiresTableRectangle {
            guard image.height >= image.width * 3 else { return nil }
            let rectangleRegions = tableRectangles(in: image)
            regions = rectangleRegions.isEmpty ? denseTableRegions(in: image) : rectangleRegions
        } else {
            regions = [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "사이즈표 후보 탐지",
            details: "출처=\(sourceDescription), 후보수=\(regions.count), 영역=\(regions.map(\.debugDescription).joined(separator: " | "))"
        )
        #endif
        guard !regions.isEmpty else {
            #if DEBUG
            FitMatchDebugLogger.detail(
                screen: "상품 분석",
                action: "사이즈 이미지 파싱",
                details: "출처=\(sourceDescription), 최종사이즈수=0"
            )
            #endif
            return nil
        }

        let ocrRegions = regions.flatMap { region -> [CGRect] in
            guard region.maxY >= 0.96, region.height > 0.12 else { return [region] }
            return [focusedTopTableRegion(region), region]
        }
        for (index, region) in ocrRegions.prefix(8).enumerated() {
            let isBoundedTopCandidate = region.maxY >= 0.96 && region.height > 0.12
            let observations = recognizedText(
                in: image,
                region: region,
                minimumConfidence: isBoundedTopCandidate ? 0.35 : 0.8
            )
            guard observations.count >= 6 else { continue }
            let grid = gridRows(from: observations)
            let context = observations.map(\.text).joined(separator: " ")
            #if DEBUG
            FitMatchDebugLogger.detail(
                screen: "상품 분석",
                action: "사이즈표 OCR",
                details: "출처=\(sourceDescription), 후보=\(index), 행=\(grid)"
            )
            #endif
            if let sizes = MusinsaFallbackTableParser.parseGrid(grid, context: context, family: family),
               !sizes.isEmpty {
                #if DEBUG
                FitMatchDebugLogger.detail(
                    screen: "상품 분석",
                    action: "사이즈 이미지 파싱",
                    details: "출처=\(sourceDescription), 최종사이즈수=\(sizes.count), 사이즈=\(sizes.map(\.name))"
                )
                #endif
                return sizes
            }
        }
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "사이즈 이미지 파싱",
            details: "출처=\(sourceDescription), 최종사이즈수=0"
        )
        #endif
        return nil
    }

    private static func focusedTopTableRegion(_ region: CGRect) -> CGRect {
        let topTrim = region.height * 0.18
        let bottomTrim = region.height * 0.08
        return CGRect(
            x: region.minX,
            y: region.minY + bottomTrim,
            width: region.width,
            height: region.height - topTrim - bottomTrim
        )
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = MusinsaNetworkPolicy.requestTimeout
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.musinsa.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return data
    }

    private static func tableRectangles(in image: CGImage) -> [CGRect] {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.85
        request.minimumAspectRatio = 0.15
        request.maximumAspectRatio = 1
        request.minimumSize = 0.08
        request.maximumObservations = 8
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .map(\.boundingBox)
            .filter { $0.width >= 0.35 && $0.height >= 0.08 }
            .sorted { $0.width * $0.height > $1.width * $1.height }
    }

    static func denseTableRegions(in image: CGImage) -> [CGRect] {
        let width = image.width
        let height = image.height
        guard width >= 300, height >= 900 else { return [] }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct InkRow {
            let y: Int
            let minX: Int
            let maxX: Int
        }
        var inkRows: [InkRow] = []
        for y in stride(from: 0, to: height, by: 2) {
            var darkCount = 0
            var groups = 0
            var minX = width
            var maxX = 0
            var previousDarkX: Int?
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let luminance = (
                    Int(pixels[offset]) * 30
                    + Int(pixels[offset + 1]) * 59
                    + Int(pixels[offset + 2]) * 11
                ) / 100
                guard luminance < 190 else { continue }
                darkCount += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                if previousDarkX == nil || x - previousDarkX! > 12 {
                    groups += 1
                }
                previousDarkX = x
            }
            let span = maxX - minX
            if darkCount >= 20,
               darkCount <= Int(Double(width) * 0.45),
               groups >= 5,
               span >= Int(Double(width) * 0.4) {
                inkRows.append(InkRow(y: y, minX: minX, maxX: maxX))
            }
        }

        struct InkBand {
            var minY: Int
            var maxY: Int
            var minX: Int
            var maxX: Int
        }
        var bands: [InkBand] = []
        for row in inkRows {
            if var last = bands.last, row.y - last.maxY <= 6 {
                last.maxY = row.y
                last.minX = min(last.minX, row.minX)
                last.maxX = max(last.maxX, row.maxX)
                bands[bands.count - 1] = last
            } else {
                bands.append(InkBand(minY: row.y, maxY: row.y, minX: row.minX, maxX: row.maxX))
            }
        }

        var regions: [CGRect] = []
        for start in bands.indices {
            var selected = [bands[start]]
            for next in bands.index(after: start)..<bands.endIndex {
                let gap = bands[next].minY - selected.last!.maxY
                if gap > 180 { break }
                if gap >= 8 {
                    selected.append(bands[next])
                }
                if selected.count >= 4 {
                    let minY = selected.map(\.minY).min()!
                    let maxY = selected.map(\.maxY).max()!
                    let minX = selected.map(\.minX).min()!
                    let maxX = selected.map(\.maxX).max()!
                    let regionHeight = maxY - minY
                    let verticalPadding = max(24, regionHeight / 3)
                    let y0 = max(0, minY - verticalPadding)
                    let regularHeightLimit = Int(Double(height) * 0.12)
                    let topHeightLimit = min(
                        Int(Double(height) * 0.30),
                        Int(Double(width) * 1.1)
                    )
                    let isBoundedTopCandidate = y0 <= Int(Double(height) * 0.04)
                        && regionHeight <= topHeightLimit
                    guard (regionHeight <= regularHeightLimit || isBoundedTopCandidate),
                          maxX - minX >= Int(Double(width) * 0.45) else { continue }
                    let horizontalPadding = Int(Double(width) * 0.04)
                    let x0 = max(0, minX - horizontalPadding)
                    let x1 = min(width, maxX + horizontalPadding)
                    let y1 = min(height, maxY + verticalPadding)
                    regions.append(CGRect(
                        x: Double(x0) / Double(width),
                        y: 1 - Double(y1) / Double(height),
                        width: Double(x1 - x0) / Double(width),
                        height: Double(y1 - y0) / Double(height)
                    ))
                }
            }
        }
        return regions
            .filter { $0.width >= 0.45 && $0.height >= 0.015 }
            .sorted {
                let lhsIsTop = $0.maxY >= 0.96
                let rhsIsTop = $1.maxY >= 0.96
                if lhsIsTop != rhsIsTop { return lhsIsTop }
                return $0.width * $0.height < $1.width * $1.height
            }
            .reduce(into: []) { unique, region in
                if !unique.contains(where: { $0.intersection(region).width * $0.intersection(region).height
                    >= min($0.width * $0.height, region.width * region.height) * 0.8 }) {
                    unique.append(region)
                }
            }
    }

    private static func recognizedText(
        in image: CGImage,
        region: CGRect,
        minimumConfidence: VNConfidence
    ) -> [(text: String, box: CGRect)] {
        let pixelRect = CGRect(
            x: region.minX * Double(image.width),
            y: (1 - region.maxY) * Double(image.height),
            width: region.width * Double(image.width),
            height: region.height * Double(image.height)
        ).integral
        guard pixelRect.width >= 120,
              pixelRect.height >= 60,
              let croppedImage = image.cropping(to: pixelRect) else { return [] }
        let recognitionImage = minimumConfidence < 0.8
            ? upscaledImage(croppedImage, scale: 2)
            : croppedImage
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        request.customWords = [
            "XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL",
            "사이즈", "총장", "총기장", "총길이", "어깨", "어깨너비",
            "가슴", "가슴단면", "가슴둘레", "소매", "소매길이",
            "허리단면", "허리둘레", "엉덩이단면", "엉덩이둘레",
            "허벅지단면", "밑위", "인심", "발길이"
        ]
        try? VNImageRequestHandler(cgImage: recognitionImage).perform([request])
        return (request.results ?? []).compactMap {
            guard let candidate = $0.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else { return nil }
            return (candidate.string, $0.boundingBox)
        }
    }

    private static func upscaledImage(_ image: CGImage, scale: Int) -> CGImage {
        guard scale > 1 else { return image }
        let width = image.width * scale
        let height = image.height * scale
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func gridRows(from observations: [(text: String, box: CGRect)]) -> [[String]] {
        let sorted = observations.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) > max(lhs.box.height, rhs.box.height) * 0.7 {
                return lhs.box.midY > rhs.box.midY
            }
            return lhs.box.minX < rhs.box.minX
        }
        var rows: [[(text: String, box: CGRect)]] = []
        for observation in sorted {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.box.midY - observation.box.midY) <= max(first.box.height, observation.box.height) * 0.7
            }) {
                rows[index].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows
            .map {
                $0.sorted { $0.box.minX < $1.box.minX }.flatMap { observation in
                    let cells = observation.text
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                    return cells.isEmpty ? [observation.text] : cells
                }
            }
            .filter { $0.count >= 2 }
    }
}

private extension GarmentMeasurements {
    mutating func set(_ value: Double, for kind: MeasurementDisplayKind) {
        switch kind {
        case .shoulder: shoulder = value
        case .chest: chest = value
        case .totalLength: totalLength = value
        case .sleeveLength: sleeveLength = value
        case .waist: waist = value
        case .hip: hip = value
        case .thigh: thigh = value
        case .rise: rise = value
        case .hem: hem = value
        case .footLength: footLength = value
        case .underBust: underBust = value
        case .unknown: break
        }
    }
}

private extension String {
    var trimmedCell: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }

    var normalizedSizeHeader: String {
        var value = trimmedCell.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        for unit in ["centimeters", "centimeter", "inches", "inch", "cm", "mm"] where value.hasSuffix(unit) {
            value.removeLast(unit.count)
            break
        }
        return value
    }

    var strippingHTML: String {
        replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .htmlEntityDecoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmedCell
    }

    var htmlEntityDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
