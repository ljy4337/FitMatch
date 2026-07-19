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
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "HTML 사이즈표 탐색",
            details: "결과사이즈수=\(htmlSizes.count)"
        )
        #endif
        if !htmlSizes.isEmpty {
            logStandardization(htmlSizes, source: "html")
            return htmlSizes
        }

        let images = MusinsaFallbackImageExtractor.images(in: goodsContents)
            .sorted { $0.candidateScore > $1.candidateScore }
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "사이즈 이미지 선택",
            details: "전체=\(images.count), 후보=\(images.prefix(12).map { "\($0.candidateScore):\($0.url.lastPathComponent)" }.joined(separator: ","))"
        )
        #endif
        let explicitImages = images.filter(\.isExplicitSizeImage)
        for image in explicitImages.prefix(6) {
            if let sizes = await MusinsaFallbackImageOCR.parse(url: image.url, family: family, requiresTableRectangle: false),
               !sizes.isEmpty {
                logStandardization(sizes, source: image.url.absoluteString)
                return sizes
            }
        }

        let longImages = images
            .filter {
                !$0.isExplicitSizeImage
                    && ($0.isLongImageCandidate || $0.declaredHeight == nil || $0.declaredWidth == nil)
            }
            .prefix(12)
        for image in longImages {
            if let sizes = await MusinsaFallbackImageOCR.parse(url: image.url, family: family, requiresTableRectangle: true),
               !sizes.isEmpty {
                logStandardization(sizes, source: image.url.absoluteString)
                return sizes
            }
        }
        return []
    }

    private func logStandardization(_ sizes: [ParsedProductSize], source: String) {
        #if DEBUG
        let codes = Set(sizes.flatMap(\.measurementRecords).map(\.measurementCode.rawValue)).sorted()
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "측정 항목 표준화",
            details: "출처=\(source), 사이즈수=\(sizes.count), canonical=\(codes.joined(separator: ","))"
        )
        #endif
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
        let pattern = #"(^|[/_.\-\s])(actual[\-_]?size|size[\-_]?(guide|chart|spec|info)?|spec|실측|사이즈|치수)([/_.\-\s]|$)"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
            && !normalized.contains("modelspec")
    }

    var candidateScore: Int {
        let normalized = sourceText.lowercased()
        let keywords = ["actual-size", "actual_size", "size chart", "size guide", "실측", "사이즈", "치수",
                        "어깨", "가슴", "허리", "엉덩이", "소매", " cm"]
        var score = keywords.reduce(0) { $0 + (normalized.contains($1) ? 3 : 0) }
        if isExplicitSizeImage { score += 8 }
        if normalized.contains("tit_size") { score += 1 }
        if isLongImageCandidate { score += 2 }
        return score
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
            let nsHTML = html as NSString
            let contextStart = max(0, match.range.location - 240)
            let contextEnd = min(nsHTML.length, NSMaxRange(match.range) + 240)
            let nearbyText = nsHTML.substring(
                with: NSRange(location: contextStart, length: contextEnd - contextStart)
            ).strippingHTML
            return MusinsaFallbackImage(
                url: resolved,
                sourceText: "\(rawURL) \(attribute("alt", in: tag) ?? "") \(attribute("title", in: tag) ?? "") \(nearbyText)",
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
            let tableHTML = String(html[tableRange])
            let grid = rows(in: tableHTML)
            let nsHTML = html as NSString
            let start = max(0, tableMatch.range.location - 400)
            let end = min(nsHTML.length, NSMaxRange(tableMatch.range) + 400)
            let context = nsHTML.substring(with: NSRange(location: start, length: end - start)).strippingHTML
            let normalizedContext = context.replacingOccurrences(of: " ", with: "")
            guard !normalizedContext.contains("신체권장치수"),
                  !normalizedContext.contains("권장신체치수") else { continue }
            if let result = parseGrid(
                grid,
                context: tableHTML.strippingHTML,
                family: family
            ), !result.isEmpty {
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
        let normalizedContext = context.replacingOccurrences(of: " ", with: "")
        guard !normalizedContext.contains("신체권장치수"),
              !normalizedContext.contains("권장신체치수") else { return nil }
        var grid = rawGrid
            .map { $0.map(\.trimmedCell) }
            .filter { $0.contains(where: { !$0.isEmpty }) }
        guard grid.count >= 3 else { return nil }
        if family == .shoes,
           let shoeSizes = parseShoeConversionGrid(grid) {
            return shoeSizes
        }
        if let unitHeaderIndex = grid.firstIndex(where: { row in
            row.count >= 3
                && isUnitOnlyCell(row[0])
                && row.dropFirst().filter({ isSizeValue($0) }).count >= 2
        }) {
            grid = Array(grid.dropFirst(unitHeaderIndex))
            grid[0][0] = "size"
            let expectedColumnCount = grid[0].count
            grid = [grid[0]] + grid.dropFirst().map {
                normalizedTransposedRow(
                    $0,
                    expectedColumnCount: expectedColumnCount,
                    family: family
                )
            }
        }
        if let transposedHeaderIndex = grid.firstIndex(where: { row in
            row.count >= 3
                && isSizeHeader(row[0].normalizedSizeHeader)
                && row.dropFirst().filter({ isSizeValue($0) }).count >= 2
        }) {
            grid = Array(grid.dropFirst(transposedHeaderIndex))
        }
        grid = grid.map { mergedHeaderCells($0, family: family) }
        let normalized = grid.map { $0.map(\.normalizedSizeHeader) }
        let unit = unitMultiplier(in: "\(context) \(grid.flatMap { $0 }.joined(separator: " "))")
        guard let unit else { return nil }

        if let headerIndex = normalized.firstIndex(where: { row in
            row.contains(where: isSizeHeader) && row.contains(where: { column(for: $0, family: family) != nil })
        }) {
            let headers = grid[headerIndex]
            let rows = Array(grid.dropFirst(headerIndex + 1)).filter { $0.count == headers.count }
            return makeSizes(headers: headers, rows: rows, unit: unit, family: family)
        }
        if let recovered = recoverBrokenSizeHeader(in: grid, family: family) {
            return makeSizes(
                headers: recovered.headers,
                rows: recovered.rows,
                unit: unit,
                family: family
            )
        }

        let transposed = transpose(grid)
        let transposedNormalized = transposed.map { $0.map(\.normalizedSizeHeader) }
        if let headerIndex = transposedNormalized.firstIndex(where: { row in
            row.contains(where: isSizeHeader) && row.contains(where: { column(for: $0, family: family) != nil })
        }) {
            let headers = transposed[headerIndex]
            let rows = Array(transposed.dropFirst(headerIndex + 1)).filter { $0.count == headers.count }
            return makeSizes(headers: headers, rows: rows, unit: unit, family: family)
        }
        return nil
    }

    static func parseCandidateGrids(
        _ candidateGrids: [[[String]]],
        context: String,
        family: MusinsaFallbackGarmentFamily
    ) -> [ParsedProductSize]? {
        let cleaned = candidateGrids.map {
            $0.map { $0.map(\.trimmedCell) }
                .filter { $0.contains(where: { !$0.isEmpty }) }
        }
        let allRows = cleaned.flatMap { $0 }
        let headers = allRows.filter { row in
            row.count >= 3
                && row.dropFirst().filter {
                    column(for: $0.normalizedSizeHeader, family: family) != nil
                }.count >= 2
                && (isSizeHeader(row[0].normalizedSizeHeader)
                    || row[0].range(of: #"[^A-Za-z가-힣0-9]*(?:cm|mm)"#, options: [.regularExpression, .caseInsensitive]) != nil)
        }
        guard let header = headers.max(by: { lhs, rhs in
            let lhsMapped = lhs.dropFirst().filter {
                column(for: $0.normalizedSizeHeader, family: family) != nil
            }.count
            let rhsMapped = rhs.dropFirst().filter {
                column(for: $0.normalizedSizeHeader, family: family) != nil
            }.count
            return (lhsMapped, lhs.count) < (rhsMapped, rhs.count)
        }) else { return nil }

        var bestRows: [String: [String]] = [:]
        var order: [String] = []
        for row in allRows where row.count == header.count {
            let sizeName = row[0].trimmedCell
            guard isSizeValue(sizeName),
                  row.dropFirst().filter({
                      measurementValue($0, defaultUnit: 1) != nil
                  }).count >= 2 else { continue }
            let key = sizeName.uppercased()
            if bestRows[key] == nil {
                order.append(key)
                bestRows[key] = row
            } else if row.dropFirst().filter({ measurementValue($0, defaultUnit: 1) != nil }).count
                        > bestRows[key]!.dropFirst().filter({ measurementValue($0, defaultUnit: 1) != nil }).count {
                bestRows[key] = row
            }
        }
        guard bestRows.count >= 2 else { return nil }
        var recoveredHeader = header
        if !isSizeHeader(recoveredHeader[0].normalizedSizeHeader) {
            recoveredHeader[0] = "사이즈"
        }
        return parseGrid(
            [recoveredHeader] + order.compactMap { bestRows[$0] },
            context: context,
            family: family
        )
    }

    private static func recoverBrokenSizeHeader(
        in grid: [[String]],
        family: MusinsaFallbackGarmentFamily
    ) -> (headers: [String], rows: [[String]])? {
        for headerIndex in grid.indices {
            var headers = grid[headerIndex]
            guard headers.count >= 3,
                  !isSizeHeader(headers[0].normalizedSizeHeader) else { continue }
            let measurementHeaderCount = headers.dropFirst().filter {
                column(for: $0.normalizedSizeHeader, family: family) != nil
            }.count
            guard measurementHeaderCount >= 2 else { continue }
            let rows = Array(grid.dropFirst(headerIndex + 1))
                .filter { $0.count == headers.count }
            let validRows = rows.filter { row in
                guard isSizeValue(row[0]) else { return false }
                return row.dropFirst().filter {
                    measurementValue($0, defaultUnit: 1) != nil
                }.count >= 2
            }
            guard validRows.count >= 2 else { continue }
            headers[0] = "사이즈"
            return (headers, rows)
        }
        return nil
    }

    private static func normalizedTransposedRow(
        _ row: [String],
        expectedColumnCount: Int,
        family: MusinsaFallbackGarmentFamily
    ) -> [String] {
        let valueCount = expectedColumnCount - 1
        guard expectedColumnCount >= 3,
              row.count > expectedColumnCount,
              valueCount > 0 else { return row }
        let values = Array(row.suffix(valueCount))
        guard values.allSatisfy({ strictNumber($0) != nil }) else { return row }
        let labelCandidates = row.dropLast(valueCount)
        guard let label = labelCandidates.last(where: {
            column(for: $0.normalizedSizeHeader, family: family) != nil
        }) else { return row }
        return [label] + values
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
        let tableRange = NSRange(table.startIndex..<table.endIndex, in: table)
        let rowMatches = rowRegex.matches(in: table, range: tableRange)
        var parsedRows: [[String]] = rowMatches.compactMap { rowMatch -> [String]? in
            guard let range = Range(rowMatch.range(at: 1), in: table) else { return nil }
            let row = String(table[range])
            return cellRegex.matches(in: row, range: NSRange(row.startIndex..<row.endIndex, in: row)).compactMap { cell in
                guard let range = Range(cell.range(at: 1), in: row) else { return nil }
                return String(row[range]).strippingHTML
            }
        }
        if let firstRow = rowMatches.first, firstRow.range.location > 0 {
            let prefix = (table as NSString).substring(
                with: NSRange(location: 0, length: firstRow.range.location)
            )
            let looseHeader = cellRegex.matches(
                in: prefix,
                range: NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
            ).compactMap { cell -> String? in
                guard let range = Range(cell.range(at: 1), in: prefix) else { return nil }
                return String(prefix[range]).strippingHTML
            }
            if looseHeader.count >= 2 {
                parsedRows.insert(looseHeader, at: 0)
            }
        }
        return parsedRows
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
        guard let sizeIndex = headers.firstIndex(where: { isSizeHeader($0.normalizedSizeHeader) }) else { return nil }
        let mappedColumns = headers.enumerated().compactMap { index, header in
            column(for: header.normalizedSizeHeader, family: family).map { (index, $0, header) }
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
                guard row.indices.contains(index),
                      let sourceValue = measurementValue(row[index], defaultUnit: unit) else { continue }
                guard sourceValue.isFinite, sourceValue > 0, sourceValue < 300 else { continue }
                let record = mapped.record(
                    value: sourceValue,
                    rawLabel: rawHeader,
                    rawValue: row[index],
                    tableUnit: unit
                )
                records.append(record)
                if record.semanticStatus == .mapped,
                   ![.chestCircumference, .frontLength, .backLength].contains(mapped) {
                    measurements.set(record.value, for: record.displayKind)
                }
            }
            guard requiredRecords(records, family: family) else { return nil }
            return ParsedProductSize(name: sizeName, measurements: measurements, measurementRecords: records)
        }
        return parsed.count >= 2 ? parsed : nil
    }

    private static func parseShoeConversionGrid(_ grid: [[String]]) -> [ParsedProductSize]? {
        let countryMarkers = Set(["us", "uk", "eu", "eur", "jp", "cm", "china", "중국", "일본"])
        guard grid.contains(where: { row in
            guard let first = row.first else { return false }
            return countryMarkers.contains(first.normalizedSizeHeader)
        }), let koreaRow = grid.first(where: { row in
            guard let first = row.first else { return false }
            return ["한국", "korea", "kr"].contains(first.normalizedSizeHeader)
        }) else { return nil }
        let values = koreaRow.dropFirst().compactMap { cell -> (String, Double)? in
            guard let millimeters = strictNumber(cell),
                  (200...350).contains(millimeters) else { return nil }
            return (cell.trimmedCell, millimeters)
        }
        guard values.count >= 2 else { return nil }
        return values.map { rawName, millimeters in
            let centimeters = millimeters * 0.1
            let record = FallbackColumn.footLength.record(
                value: centimeters,
                rawLabel: koreaRow[0],
                rawValue: rawName,
                tableUnit: 0.1
            )
            var measurements = GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 0,
                sleeveLength: 0
            )
            measurements.footLength = centimeters
            return ParsedProductSize(
                name: rawName,
                measurements: measurements,
                measurementRecords: [record]
            )
        }
    }

    private static func requiredColumns(_ columns: [FallbackColumn], family: MusinsaFallbackGarmentFamily) -> Bool {
        switch family {
        case .upper:
            return columns.contains(where: { $0 == .chestWidth || $0 == .chestCircumference })
                && columns.contains(where: {
                    [.length, .frontLength, .backLength, .shoulder, .sleeve, .centerBackSleeve].contains($0)
                })
        case .lower:
            return columns.contains(where: { $0 == .waistWidth || $0 == .waistCircumference })
                && columns.contains(where: {
                    [.hip, .hipCircumference, .thigh, .thighCircumference, .rise, .backRise,
                     .hemWidth, .hemCircumference, .outseam, .inseam].contains($0)
                })
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
            .replacingOccurrences(
                of: #"\d{1,3}(?:[.,]\d+)?\s*(?:cm|mm)(?![a-z])"#,
                with: "",
                options: .regularExpression
            )
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
        ["사이즈", "size", "호칭", "옵션", "치수항목"].contains(text)
    }

    private static func isSizeValue(_ text: String) -> Bool {
        let value = text.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "~")
            .replacingOccurrences(of: "—", with: "~")
        return value.range(
            of: #"^(?:(?:XXS|XS|S|M|L|XL|XXL|XXXL|[2-5]XL|WM|FREE|ONE)(?:\([0-9]{2,3}\))?|[0-9]{2,3}(?:[-/][0-9]{2,3})?(?:\((?:XXS|XS|S|M|L|XL|XXL|XXXL|[2-5]XL|WM)\))?|[0-9]{2,3}/(?:XXS|XS|S|M|L|XL|XXL|XXXL|[2-5]XL|WM)/[0-9]{2,3}~[0-9]{2,3})$"#,
            options: .regularExpression
        ) != nil
    }

    private static func strictNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmedCell
        guard normalized.range(of: #"^\d{1,3}(?:\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(normalized)
    }

    private static func measurementValue(_ text: String, defaultUnit: Double) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmedCell
        guard normalized != "-",
              let regex = try? NSRegularExpression(
                pattern: #"^(\d{1,3}(?:\.\d+)?)\s*(cm|mm)?$"#,
                options: .caseInsensitive
              ),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
              ),
              let numberRange = Range(match.range(at: 1), in: normalized),
              let number = Double(normalized[numberRange]) else { return nil }
        let multiplier: Double
        if let unitRange = Range(match.range(at: 2), in: normalized) {
            multiplier = normalized[unitRange].lowercased() == "mm" ? 0.1 : 1
        } else {
            multiplier = defaultUnit
        }
        return number * multiplier
    }

    private static func column(for header: String, family: MusinsaFallbackGarmentFamily) -> FallbackColumn? {
        switch header {
        case "가슴", "가슴단면", "가슴너비", "품", "chest", "chestwidth", "pittopit": return .chestWidth
        case "가슴둘레", "chestcircumference", "bustcircumference": return .chestCircumference
        case "어깨", "어깨너비", "어깨폭", "어깨넓이", "shoulder", "shoulderwidth": return .shoulder
        case "앞기장", "앞길이": return family == .upper ? .frontLength : nil
        case "뒷기장", "뒷길이": return family == .upper ? .backLength : nil
        case "총장", "총기장", "총길이", "기장", "옷길이", "상의길이", "옷길이아웃심", "length", "bodylength", "outseam":
            return family == .lower ? .outseam : .length
        case "소매", "소매길이", "소매장", "sleeve", "sleevelength": return .sleeve
        case "화장", "목중심부터소매끝", "목중심소매길이": return family == .upper ? .centerBackSleeve : nil
        case "허리단면", "허리너비", "waistwidth": return .waistWidth
        case "허리둘레", "waistcircumference": return .waistCircumference
        case "엉덩이단면", "엉덩이너비", "힙단면", "hipwidth": return .hip
        case "엉덩이둘레", "힙둘레", "hipcircumference": return .hipCircumference
        case "허벅지단면", "허벅지너비", "thighwidth": return .thigh
        case "허벅지둘레": return .thighCircumference
        case "밑위", "밑위길이", "앞밑위", "앞밑위길이", "rise", "frontrise": return .rise
        case "뒤밑위", "뒤밑위길이", "backrise": return .backRise
        case "밑단", "밑단단면", "밑단너비": return .hemWidth
        case "밑단둘레": return .hemCircumference
        case "인심", "안쪽기장", "inseam": return .inseam
        case "바깥기장", "아웃심": return .outseam
        case "발길이", "발길이정보", "한국", "korea", "footlength", "feetlength": return family == .shoes ? .footLength : nil
        default: return nil
        }
    }
}

private enum FallbackColumn: Equatable {
    case chestWidth, chestCircumference, shoulder, length, frontLength, backLength, sleeve, centerBackSleeve
    case outseam
    case waistWidth, waistCircumference, hip, hipCircumference
    case thigh, thighCircumference, rise, backRise, hemWidth, hemCircumference, inseam, footLength

    init?(record: ParsedMeasurement) {
        switch record.measurementCode {
        case .chestWidthPitToPit: self = .chestWidth
        case .chestCircumferenceGarment: self = .chestCircumference
        case .shoulderWidthSeamToSeam: self = .shoulder
        case .bodyLengthBackNeckToHem: self = .length
        case .bodyLengthHPSToHemFront: self = .frontLength
        case .pantsOutseamWaistToHem: self = .outseam
        case .sleeveShoulderSeamToCuff: self = .sleeve
        case .sleeveCenterBackToCuff: self = .centerBackSleeve
        case .waistWidthEdgeToEdge: self = .waistWidth
        case .waistCircumferenceGarment: self = .waistCircumference
        case .hipWidthAtWidest: self = .hip
        case .thighWidthCrotchToOuter: self = .thigh
        case .riseCrotchToWaistFront: self = .rise
        case .riseCrotchToWaistBack: self = .backRise
        case .hemWidthEdgeToEdge: self = .hemWidth
        case .pantsInseamCrotchToHem: self = .inseam
        case .footLengthHeelToToe: self = .footLength
        default: return nil
        }
    }

    func record(
        value: Double,
        rawLabel: String,
        rawValue: String,
        tableUnit: Double
    ) -> ParsedMeasurement {
        let code: MeasurementCode
        let kind: MeasurementDisplayKind
        let multiplier: Double
        switch self {
        case .chestWidth: (code, kind, multiplier) = (.chestWidthPitToPit, .chest, 1)
        case .chestCircumference: (code, kind, multiplier) = (.chestCircumferenceGarment, .chest, 1)
        case .shoulder: (code, kind, multiplier) = (.shoulderWidthSeamToSeam, .shoulder, 1)
        case .length: (code, kind, multiplier) = (.bodyLengthBackNeckToHem, .totalLength, 1)
        case .frontLength: (code, kind, multiplier) = (.bodyLengthHPSToHemFront, .totalLength, 1)
        case .backLength: (code, kind, multiplier) = (.bodyLengthBackNeckToHem, .totalLength, 1)
        case .outseam: (code, kind, multiplier) = (.pantsOutseamWaistToHem, .totalLength, 1)
        case .sleeve: (code, kind, multiplier) = (.sleeveShoulderSeamToCuff, .sleeveLength, 1)
        case .centerBackSleeve: (code, kind, multiplier) = (.sleeveCenterBackToCuff, .sleeveLength, 1)
        case .waistWidth: (code, kind, multiplier) = (.waistWidthEdgeToEdge, .waist, 1)
        case .waistCircumference: (code, kind, multiplier) = (.waistWidthEdgeToEdge, .waist, 0.5)
        case .hip: (code, kind, multiplier) = (.hipWidthAtWidest, .hip, 1)
        case .hipCircumference: (code, kind, multiplier) = (.hipWidthAtWidest, .hip, 0.5)
        case .thigh: (code, kind, multiplier) = (.thighWidthCrotchToOuter, .thigh, 1)
        case .thighCircumference: (code, kind, multiplier) = (.thighWidthCrotchToOuter, .thigh, 0.5)
        case .rise: (code, kind, multiplier) = (.riseCrotchToWaistFront, .rise, 1)
        case .backRise: (code, kind, multiplier) = (.riseCrotchToWaistBack, .rise, 1)
        case .hemWidth: (code, kind, multiplier) = (.hemWidthEdgeToEdge, .hem, 1)
        case .hemCircumference: (code, kind, multiplier) = (.hemWidthEdgeToEdge, .hem, 0.5)
        case .inseam: (code, kind, multiplier) = (.pantsInseamCrotchToHem, .totalLength, 1)
        case .footLength: (code, kind, multiplier) = (.footLengthHeelToToe, .footLength, 1)
        }
        var transformations: [String] = []
        if rawValue.lowercased().range(
            of: #"^\s*\d{1,3}(?:[.,]\d+)?\s*mm\s*$"#,
            options: .regularExpression
        ) != nil {
            transformations.append("cell_unit_mm_to_cm_multiplier=0.1")
        } else if tableUnit == 0.1 {
            transformations.append("table_unit_mm_to_cm_multiplier=0.1")
        } else if tableUnit == 2.54 {
            transformations.append("table_unit_inch_to_cm_multiplier=2.54")
        }
        if multiplier == 0.5 {
            transformations.append("circumference_to_width_multiplier=0.5")
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
            rawInfo: transformations.isEmpty ? nil : transformations.joined(separator: ";"),
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
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width * height <= 60_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let effectiveRequiresTableRectangle = requiresTableRectangle || height >= width * 3

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "사이즈 이미지 로드",
            details: "URL=\(url.absoluteString), 크기=\(image.width)x\(image.height)"
        )
        #endif
        let documentSizes: [ParsedProductSize]?
        if #available(iOS 26.0, *) {
            documentSizes = await parseDocumentTables(
               image: image,
               family: family,
               requiresTableRectangle: effectiveRequiresTableRectangle,
               sourceDescription: url.absoluteString
            )
        } else {
            documentSizes = nil
        }
        if let documentSizes,
           documentSizes.count >= 4,
           documentSizes.filter({ isLetterSizeOCRCandidate($0.name) }).count >= 2 {
            return documentSizes
        }
        let textSizes = parse(
            image: image,
            family: family,
            requiresTableRectangle: effectiveRequiresTableRectangle,
            sourceDescription: url.absoluteString
        )
        return preferredSizes(documentSizes, textSizes)
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
            regions = candidateRegions(in: image)
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
        var bestSizes: [ParsedProductSize]?
        var candidateGrids: [[[String]]] = []
        var candidateContexts: [String] = []
        for (index, region) in ocrRegions.prefix(12).enumerated() {
            let isBoundedTopCandidate = region.maxY >= 0.96 && region.height > 0.12
            var confidenceAttempts: [VNConfidence] = [isBoundedTopCandidate ? 0.35 : 0.8]
            var attemptIndex = 0
            while attemptIndex < confidenceAttempts.count {
                let confidence = confidenceAttempts[attemptIndex]
                let observations = recognizedText(
                    in: image,
                    region: region,
                    minimumConfidence: confidence
                )
                let grid = gridRows(from: observations)
                let context = observations.map(\.text).joined(separator: " ")
                if !grid.isEmpty {
                    candidateGrids.append(grid)
                    candidateContexts.append(context)
                }
                #if DEBUG
                FitMatchDebugLogger.detail(
                    screen: "상품 분석",
                    action: "사이즈표 OCR",
                    details: "출처=\(sourceDescription), 후보=\(index), 신뢰도=\(confidence), 행=\(grid)"
                )
                #endif
                if observations.count >= 6,
                   let sizes = MusinsaFallbackTableParser.parseGrid(grid, context: context, family: family),
                   !sizes.isEmpty,
                   hasSizeNameEvidence(sizes, in: grid) {
                    #if DEBUG
                    FitMatchDebugLogger.detail(
                        screen: "상품 분석",
                        action: "사이즈 이미지 파싱",
                        details: "출처=\(sourceDescription), 최종사이즈수=\(sizes.count), 사이즈=\(sizes.map(\.name))"
                    )
                    #endif
                    bestSizes = preferredSizes(bestSizes, sizes)
                }
                if attemptIndex == 0,
                   !isBoundedTopCandidate,
                   region.height <= 0.04,
                   hasRepeatedNumericRows(grid) {
                    confidenceAttempts.append(0.35)
                }
                attemptIndex += 1
            }
        }
        if let mergedSizes = MusinsaFallbackTableParser.parseCandidateGrids(
            candidateGrids,
            context: candidateContexts.joined(separator: " "),
            family: family
        ), hasSizeNameEvidence(
            mergedSizes,
            in: candidateGrids.flatMap { $0 }
        ) {
            #if DEBUG
            FitMatchDebugLogger.detail(
                screen: "상품 분석",
                action: "분할 사이즈표 병합",
                details: "출처=\(sourceDescription), 후보수=\(candidateGrids.count), 최종사이즈=\(mergedSizes.map(\.name))"
            )
            #endif
            bestSizes = preferredSizes(bestSizes, mergedSizes)
        }
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "사이즈 이미지 파싱",
            details: "출처=\(sourceDescription), 최종사이즈수=0"
        )
        #endif
        return bestSizes
    }

    private static func hasSizeNameEvidence(
        _ sizes: [ParsedProductSize],
        in grid: [[String]]
    ) -> Bool {
        let letterSizeEvidence = grid.flatMap { $0 }.filter(isLetterSizeOCRCandidate).count
        let parsedNamesAreNumeric = sizes.allSatisfy {
            $0.name.trimmedCell.range(of: #"^\d{2,3}$"#, options: .regularExpression) != nil
        }
        if parsedNamesAreNumeric, letterSizeEvidence >= 2 {
            return false
        }
        let firstColumn = Set(grid.compactMap(\.first).map {
            $0.trimmedCell.uppercased().replacingOccurrences(of: " ", with: "")
        })
        let explicitSizeRows = grid.filter { row in
            guard let first = row.first else { return false }
            return ["사이즈", "사이즈(cm)", "SIZE", "SIZE(CM)", "호칭"].contains(
                first.trimmedCell.uppercased().replacingOccurrences(of: " ", with: "")
            )
        }
        let headerValues = Set(explicitSizeRows.flatMap { $0.dropFirst() }.map {
            $0.trimmedCell.uppercased().replacingOccurrences(of: " ", with: "")
        })
        return sizes.allSatisfy {
            let name = $0.name.trimmedCell.uppercased().replacingOccurrences(of: " ", with: "")
            return firstColumn.contains(name) || headerValues.contains(name)
        }
    }

    @available(iOS 26.0, *)
    private static func parseDocumentTables(
        image: CGImage,
        family: MusinsaFallbackGarmentFamily,
        requiresTableRectangle: Bool,
        sourceDescription: String
    ) async -> [ParsedProductSize]? {
        let regions = requiresTableRectangle
            ? candidateRegions(in: image)
            : [CGRect(x: 0, y: 0, width: 1, height: 1)]
        var bestSizes: [ParsedProductSize]?
        var candidateGrids: [[[String]]] = []
        for (index, region) in regions.prefix(6).enumerated() {
            guard let crop = croppedImage(image, region: region) else { continue }
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.automaticallyDetectLanguage = true
            request.textRecognitionOptions.useLanguageCorrection = true
            request.textRecognitionOptions.customWords = ocrCustomWords
            guard let documents = try? await ImageRequestHandler(crop).perform(request) else { continue }
            for table in documents.flatMap(\.document.tables) {
                let grid = documentGrid(from: table)
                candidateGrids.append(grid)
                let context = grid.flatMap { $0 }.joined(separator: " ")
                #if DEBUG
                FitMatchDebugLogger.detail(
                    screen: "상품 분석",
                    action: "문서 표 복원",
                    details: "출처=\(sourceDescription), 후보=\(index), 행=\(grid)"
                )
                #endif
                if let sizes = MusinsaFallbackTableParser.parseGrid(
                    grid,
                    context: context,
                    family: family
                ), !sizes.isEmpty,
                   hasSizeNameEvidence(sizes, in: grid) {
                    bestSizes = preferredSizes(bestSizes, sizes)
                }
            }
            let textGrid = gridRows(from: recognizedText(
                in: image,
                region: region,
                minimumConfidence: 0.35
            ))
            if !textGrid.isEmpty {
                candidateGrids.append(textGrid)
            }
        }
        if let mergedSizes = MusinsaFallbackTableParser.parseCandidateGrids(
            candidateGrids,
            context: candidateGrids.flatMap { $0 }.flatMap { $0 }.joined(separator: " "),
            family: family
        ), hasSizeNameEvidence(mergedSizes, in: candidateGrids.flatMap { $0 }) {
            bestSizes = preferredSizes(bestSizes, mergedSizes)
        }
        return bestSizes
    }

    private static func preferredSizes(
        _ lhs: [ParsedProductSize]?,
        _ rhs: [ParsedProductSize]?
    ) -> [ParsedProductSize]? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        let lhsLetterSizes = lhs.filter { isLetterSizeOCRCandidate($0.name) }.count
        let rhsLetterSizes = rhs.filter { isLetterSizeOCRCandidate($0.name) }.count
        if (lhsLetterSizes >= 2) != (rhsLetterSizes >= 2) {
            return lhsLetterSizes >= 2 ? lhs : rhs
        }
        if lhs.count != rhs.count {
            return lhs.count > rhs.count ? lhs : rhs
        }
        if lhsLetterSizes != rhsLetterSizes {
            return lhsLetterSizes > rhsLetterSizes ? lhs : rhs
        }
        let lhsRecords = lhs.reduce(0) { $0 + $1.measurementRecords.count }
        let rhsRecords = rhs.reduce(0) { $0 + $1.measurementRecords.count }
        return lhsRecords >= rhsRecords ? lhs : rhs
    }

    @available(iOS 26.0, *)
    private static func documentGrid(
        from table: DocumentObservation.Container.Table
    ) -> [[String]] {
        table.rows.map { row in
            let columnCount = (row.map { $0.columnRange.upperBound }.max() ?? -1) + 1
            var cells = [String](repeating: "", count: columnCount)
            for cell in row {
                let value = cell.content.text.transcript.trimmedCell
                for column in cell.columnRange where cells.indices.contains(column) {
                    cells[column] = value
                }
            }
            return cells
        }
    }

    private static func croppedImage(_ image: CGImage, region: CGRect) -> CGImage? {
        let pixelRect = CGRect(
            x: region.minX * Double(image.width),
            y: (1 - region.maxY) * Double(image.height),
            width: region.width * Double(image.width),
            height: region.height * Double(image.height)
        ).integral
        guard pixelRect.width >= 120, pixelRect.height >= 60 else { return nil }
        return image.cropping(to: pixelRect)
    }

    static func hasRepeatedNumericRows(_ grid: [[String]]) -> Bool {
        grid.filter { row in
            row.filter { cell in
                let normalized = cell.replacingOccurrences(of: ",", with: ".")
                return normalized.range(
                    of: #"^\d{1,3}(?:\.\d+)?$"#,
                    options: .regularExpression
                ) != nil
            }.count >= 3
        }.count >= 2
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

    private static func candidateRegions(in image: CGImage) -> [CGRect] {
        let detected = tableRectangles(in: image) + denseTableRegions(in: image)
        let joined = joinedTableRegions(detected)
        return prioritizedRegions(
            edgeTableRegions(in: image) + mergedRegions(detected) + joined
        )
    }

    private static func prioritizedRegions(_ regions: [CGRect]) -> [CGRect] {
        regions
            .filter { $0.width >= 0.35 && $0.height >= 0.015 }
            .reduce(into: []) { unique, region in
                let area = region.width * region.height
                guard !unique.contains(where: {
                    let overlap = $0.intersection(region)
                    let existingArea = $0.width * $0.height
                    let areaRatio = max(existingArea, area) / max(min(existingArea, area), 0.001)
                    return areaRatio <= 2
                        && overlap.width * overlap.height >= min(existingArea, area) * 0.8
                }) else { return }
                unique.append(region)
            }
    }

    static func joinedTableRegions(_ regions: [CGRect]) -> [CGRect] {
        var joined: [CGRect] = []
        for firstIndex in regions.indices {
            for secondIndex in regions.indices where secondIndex > firstIndex {
                let first = regions[firstIndex]
                let second = regions[secondIndex]
                let horizontalOverlap = first.intersection(
                    CGRect(x: second.minX, y: first.minY, width: second.width, height: first.height)
                ).width
                let horizontalAlignment = horizontalOverlap / max(min(first.width, second.width), 0.001)
                let verticalGap = max(0, max(first.minY, second.minY) - min(first.maxY, second.maxY))
                let overlapsVertically = first.intersects(second)
                guard horizontalAlignment >= 0.72,
                      overlapsVertically || verticalGap <= 0.045 else { continue }
                let union = first.union(second)
                guard union.height <= 0.35,
                      union.width >= 0.45 else { continue }
                joined.append(expandedTableRegion(union))
            }
        }
        return joined
    }

    private static func expandedTableRegion(_ region: CGRect) -> CGRect {
        let horizontalPadding = max(0.025, region.width * 0.04)
        let verticalPadding = max(0.018, region.height * 0.18)
        return CGRect(
            x: max(0, region.minX - horizontalPadding),
            y: max(0, region.minY - verticalPadding),
            width: min(1, region.maxX + horizontalPadding) - max(0, region.minX - horizontalPadding),
            height: min(1, region.maxY + verticalPadding) - max(0, region.minY - verticalPadding)
        )
    }

    private static func edgeTableRegions(in image: CGImage) -> [CGRect] {
        guard image.height >= image.width * 3 else { return [] }
        // Brand detail images commonly place a compact chart before the care copy.
        // This is a bounded candidate crop; the full long image is never OCRed.
        let normalizedHeight = min(0.24, Double(image.width) * 0.8 / Double(image.height))
        return [
            CGRect(x: 0.02, y: 1 - normalizedHeight, width: 0.96, height: normalizedHeight)
        ]
    }

    private static func mergedRegions(_ regions: [CGRect]) -> [CGRect] {
        regions
            .filter { $0.width >= 0.35 && $0.height >= 0.015 }
            .sorted {
                let lhsTop = $0.maxY >= 0.96
                let rhsTop = $1.maxY >= 0.96
                if lhsTop != rhsTop { return lhsTop }
                let lhsRows = $0.width / max($0.height, 0.001)
                let rhsRows = $1.width / max($1.height, 0.001)
                if abs(lhsRows - rhsRows) > 0.5 { return lhsRows > rhsRows }
                return $0.width * $0.height < $1.width * $1.height
            }
            .reduce(into: []) { unique, region in
                let regionArea = region.width * region.height
                guard !unique.contains(where: {
                    let overlap = $0.intersection(region)
                    return overlap.width * overlap.height
                        >= min($0.width * $0.height, regionArea) * 0.8
                }) else { return }
                unique.append(region)
            }
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
            if darkCount >= 12,
               darkCount <= Int(Double(width) * 0.55),
               groups >= 4,
               span >= Int(Double(width) * 0.32) {
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
                if selected.count >= 3 {
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
                          maxX - minX >= Int(Double(width) * 0.35) else { continue }
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
            .filter { $0.width >= 0.35 && $0.height >= 0.01 }
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
            .prefix(24)
            .map { $0 }
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
        let scale = croppedImage.height < 260 ? 4 : 2
        let recognitionImage = minimumConfidence < 0.8
            ? upscaledImage(croppedImage, scale: scale)
            : croppedImage
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        request.customWords = ocrCustomWords
        try? VNImageRequestHandler(cgImage: recognitionImage).perform([request])
        return (request.results ?? []).compactMap {
            let candidates = $0.topCandidates(3)
            guard let first = candidates.first,
                  first.confidence >= minimumConfidence else { return nil }
            let text: String
            if $0.boundingBox.midX <= 0.28,
               let sizeCandidate = candidates.first(where: {
                   $0.confidence >= minimumConfidence
                       && isLetterSizeOCRCandidate($0.string)
               }) {
                text = sizeCandidate.string
            } else if first.string.range(of: #"^\d$"#, options: .regularExpression) != nil,
                      let completeNumber = candidates.dropFirst().first(where: {
                          $0.confidence >= minimumConfidence
                              && $0.string.range(
                                  of: #"^\d{2,3}(?:[.,]\d+)?$"#,
                                  options: .regularExpression
                              ) != nil
                      }) {
                text = completeNumber.string
            } else {
                text = first.string
            }
            return (text, $0.boundingBox)
        }
    }

    private static func isLetterSizeOCRCandidate(_ text: String) -> Bool {
        text.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .range(
                of: #"^(?:XXS|XS|S|M|L|XL|XXL|XXXL|[2-5]XL|WM)$"#,
                options: .regularExpression
            ) != nil
    }

    private static let ocrCustomWords = [
            "XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL",
            "사이즈", "총장", "총기장", "총길이", "어깨", "어깨너비",
            "가슴", "가슴단면", "가슴둘레", "소매", "소매길이",
            "허리단면", "허리둘레", "엉덩이단면", "엉덩이둘레",
            "허벅지단면", "허벅지둘레", "밑위", "인심", "발길이", "한국", "KOREA"
    ]

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
