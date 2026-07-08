import Foundation

struct GenericProductParser: ProductURLParsing {
    func canParse(_ url: URL) -> Bool {
        true
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        // TODO: Add generic metadata extraction or site-specific parser routing.
        throw ProductURLParserError.automaticParsingUnavailable
    }
}
