# Share Extension Setup

FitMatch uses an iOS Share Extension so Safari and shopping apps can pass a product URL into the app.

## Xcode target setup

1. Open `FitMatch.xcodeproj`.
2. Select `File > New > Target...`.
3. Choose `iOS > Share Extension`.
4. Use:
   - Product Name: `FitMatchShareExtension`
   - Language: Swift
   - UI: none/custom view controller
5. Replace the generated extension files with the files in `FitMatchShareExtension/`.
6. In the main app target and extension target, enable `Signing & Capabilities > App Groups`.
7. Add this App Group to both targets:
   - `group.io.github.ljy4337.FitMatch`
8. Set entitlements:
   - Main app: `FitMatch/FitMatch.entitlements`
   - Extension: `FitMatchShareExtension/FitMatchShareExtension.entitlements`

## Runtime flow

1. User shares a product URL from Safari or a shopping app.
2. `ShareViewController` extracts the first URL or text URL.
3. The extension writes it to App Group `UserDefaults` under `pendingProductURL`.
4. The main app reads and removes that pending URL when it becomes active.
5. `ContentView` navigates to `ShoppingProductFormView(initialURL:)`.
6. Compare displays the URL and lets the user tap `상품 정보 불러오기`.
7. `ProductURLParserService` currently returns mock product data.

## Parser extension point

`ProductURLParserService` routes work through `ProductURLParsing`.

Add future parsers as separate implementations:

- `MusinsaParser`
- `CoupangParser`
- `UniqloParser`

Each parser should implement:

```swift
func canParse(_ url: URL) -> Bool
func parse(from url: URL) async throws -> ParsedProductInfo
```

Actual HTML parsing is intentionally left for the next sprint.
