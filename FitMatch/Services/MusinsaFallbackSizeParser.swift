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
        let grid = rawGrid
            .map { $0.map(\.trimmedCell).filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        guard grid.count >= 3 else { return nil }
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
                let value = rawValue * unit
                guard value.isFinite, value > 0, value < 300 else { continue }
                let record = mapped.record(value: value, rawLabel: rawHeader, rawValue: row[index])
                records.append(record)
                if record.semanticStatus == .mapped,
                   mapped != .chestCircumference,
                   mapped != .waistCircumference {
                    measurements.set(value, for: record.displayKind)
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
                && columns.contains(where: { [.hip, .thigh, .rise, .outseam, .inseam].contains($0) })
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
        return Set(hits).count == 1 ? hits[0] : nil
    }

    nonisolated private static func isSizeHeader(_ text: String) -> Bool {
        ["사이즈", "size", "호칭", "옵션"].contains(text)
    }

    private static func isSizeValue(_ text: String) -> Bool {
        let value = text.uppercased().replacingOccurrences(of: " ", with: "")
        return value.range(
            of: #"^(XXS|XS|S|M|L|XL|XXL|XXXL|FREE|ONE|[0-9]{2,3}(?:[-/][0-9]{2,3})?)$"#,
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
        case "가슴단면", "가슴너비", "품", "chestwidth", "pit-to-pit", "pittopit": return .chestWidth
        case "가슴둘레", "chestcircumference", "bustcircumference": return .chestCircumference
        case "어깨", "어깨너비", "shoulder", "shoulderwidth": return .shoulder
        case "총장", "총기장", "옷길이", "옷길이아웃심", "length", "bodylength", "outseam":
            return family == .lower ? .outseam : .length
        case "소매", "소매길이", "sleeve", "sleevelength": return .sleeve
        case "허리단면", "허리너비", "waistwidth": return .waistWidth
        case "허리둘레", "waistcircumference": return .waistCircumference
        case "엉덩이단면", "엉덩이너비", "힙단면", "hipwidth": return .hip
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
    case waistWidth, waistCircumference, hip, thigh, rise, inseam, footLength

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
        switch self {
        case .chestWidth: (code, kind) = (.chestWidthPitToPit, .chest)
        case .chestCircumference: (code, kind) = (.chestCircumferenceGarment, .chest)
        case .shoulder: (code, kind) = (.shoulderWidthSeamToSeam, .shoulder)
        case .length: (code, kind) = (.bodyLengthBackNeckToHem, .totalLength)
        case .outseam: (code, kind) = (.pantsOutseamWaistToHem, .totalLength)
        case .sleeve: (code, kind) = (.sleeveShoulderSeamToCuff, .sleeveLength)
        case .waistWidth: (code, kind) = (.waistWidthEdgeToEdge, .waist)
        case .waistCircumference: (code, kind) = (.waistCircumferenceGarment, .waist)
        case .hip: (code, kind) = (.hipWidthAtWidest, .hip)
        case .thigh: (code, kind) = (.thighWidthCrotchToOuter, .thigh)
        case .rise: (code, kind) = (.riseCrotchToWaistFront, .rise)
        case .inseam: (code, kind) = (.pantsInseamCrotchToHem, .totalLength)
        case .footLength: (code, kind) = (.footLengthHeelToToe, .footLength)
        }
        return ParsedMeasurement(
            value: value,
            measurementCode: code,
            displayKind: kind,
            methodSource: "musinsa_fallback",
            methodProfile: "structured_size_table",
            inputSource: .importedSizeChart,
            mappingVersion: "musinsa_fallback_mapping_v1",
            rawLabel: rawLabel,
            rawValueText: rawValue,
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
    }
}

@MainActor
private enum MusinsaFallbackImageOCR {
    static func parse(
        url: URL,
        family: MusinsaFallbackGarmentFamily,
        requiresTableRectangle: Bool
    ) async -> [ParsedProductSize]? {
        guard let data = try? await fetch(url),
              data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let regions: [CGRect]
        if requiresTableRectangle {
            guard image.height >= image.width * 3 else { return nil }
            regions = tableRectangles(in: image)
            guard !regions.isEmpty else { return nil }
        } else {
            regions = [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        for region in regions.prefix(3) {
            let observations = recognizedText(in: image, region: region)
            guard observations.count >= 6 else { continue }
            let grid = gridRows(from: observations)
            let context = observations.map(\.text).joined(separator: " ")
            if let sizes = MusinsaFallbackTableParser.parseGrid(grid, context: context, family: family),
               !sizes.isEmpty {
                return sizes
            }
        }
        return nil
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = MusinsaNetworkPolicy.requestTimeout
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.musinsa.com", forHTTPHeaderField: "Referer")
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

    private static func recognizedText(in image: CGImage, region: CGRect) -> [(text: String, box: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        request.regionOfInterest = region
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap {
            guard let candidate = $0.topCandidates(1).first, candidate.confidence >= 0.8 else { return nil }
            return (candidate.string, $0.boundingBox)
        }
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
