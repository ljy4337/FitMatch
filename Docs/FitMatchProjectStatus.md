# FitMatch Project Status

Last updated: 2026-07-04

## 1. Current App Structure

FitMatch is an iOS SwiftUI app that uses SwiftData as the local database.

Main folders:

- `Models`
- `Views`
- `ViewModels`
- `Services`
- `Components`
- `Assets.xcassets`
- `FitMatchShareExtension`

App entry flow:

1. `FitMatchApp`
2. `ContentView`
3. Splash
4. Login
5. Main Tab

## 2. Current Bottom Tabs

The app currently has 5 bottom tabs:

- 홈
- 비교
- 기록
- 추천
- 마이

Closet is not a separate tab. It is opened from Home through `내 옷장 보기`.

## 3. Implemented Screens

- `ContentView`
- `SplashView`
- `LoginView`
- `HomeView`
- `MyClosetView`
- `AddClosetItemView`
- `ClosetItemDetailView`
- `ShoppingProductFormView`
- `RecommendationResultView`
- `RecommendationHistoryView`
- `RecommendView`
- `MyPageView`
- `BrandDatabaseView`
- `AppTab`

## 4. Implemented Features

- Splash screen
- Login UI
- 5-tab main navigation
- Home dashboard
- My Closet list
- Add closet item
- Closet item detail
- Edit closet item
- Delete closet item
- Mark/unmark representative clothes
- Show representative clothes on Home
- Save brand, gender, category, detail category, product name, size, measurements, fit, satisfaction
- Shopping product URL input
- Extract Musinsa product ID from URL
- Load Musinsa actual size data through actual-size API
- Auto-fill shopping product size table
- Manual size table input
- Calculate recommended size
- Save recommendation result
- Recommendation result detail
- Recommendation history list
- Open shopping mall from history
- Recompare from history
- Recommend tab product cards
- Delete recommendation item from Recommend tab
- App Group based shared URL storage structure

## 5. SwiftData Models

### `Brand`

Stores brand information.

Role:

- Brand name
- Normalized brand name
- Country code
- Website URL
- Notes
- Relationship to multiple `Product` records

### `Product`

Stores shopping products or user-entered products.

Role:

- Product name
- Brand relationship
- Category
- Product code
- Source URL
- Product source
- Relationship to multiple `ProductSize` records

### `ProductSize`

Stores product size measurements.

Role:

- Size name
- Shoulder
- Chest
- Total length
- Sleeve length
- Display order
- Relationship back to `Product`

### `UserFit`

Stores user closet and baseline fit data.

Role:

- Brand
- Gender
- Category
- Detail category
- Product name
- Size
- Measurements
- Fit memo
- Fit preference
- Satisfaction
- Representative clothes flag
- Optional source product and source size

### `RecommendationHistory`

Stores recommendation results.

Role:

- Compared product
- Recommended size
- Matched user fit
- Total difference
- Measurement differences
- Recommendation score
- True-to-size recommendation text
- Oversized recommendation text
- Reason
- Created date

## 6. Main Services

### `RecommendationService`

Calculates the best size recommendation.

Current behavior:

- Compares product sizes against user closet items
- Uses shoulder, chest, total length, and sleeve length differences
- Calculates signed and absolute differences
- Chooses the size with the smallest total difference
- Prioritizes representative clothes first
- Then prioritizes matching category service group
- Creates `RecommendationHistory`

### `ProductURLParserService`

Selects the correct parser for a URL.

Current parser order:

1. `MusinsaActualSizeAPIParser`
2. `MusinsaParser`
3. `GenericProductParser`

### `MusinsaActualSizeAPIParser`

Primary Musinsa parser.

Role:

- Extract Musinsa product ID
- Call actual-size API
- Decode JSON response
- Convert size data into `ParsedProductSize`

### `MusinsaParser`

Fallback Musinsa parser.

Role:

- Fetch Musinsa product HTML
- Extract basic product metadata from `__NEXT_DATA__`
- Parse HTML size table with SwiftSoup as fallback

### `MusinsaWebViewParser`

WKWebView based DOM parser file exists.

Current status:

- Exists in the codebase
- Not currently included in the default parser chain

### `GenericProductParser`

Fallback parser for unsupported or generic URLs.

Role:

- Provides automatic parsing unavailable behavior
- Allows manual entry flow to continue

### `SharedURLStore`

Stores and consumes shared URLs through App Group UserDefaults.

Role:

- Save pending product URL
- Consume pending product URL when main app opens

### `SampleDataService`

Seeds sample data on initial app launch.

Role:

- Sample brands
- Sample user fits

## 7. Current MusinsaParser Behavior

The primary current Musinsa flow is handled by `MusinsaActualSizeAPIParser`.

Flow:

1. Extract product ID from URL.
   - Example: `https://www.musinsa.com/products/6364516`
   - Product ID: `6364516`
2. Call API:
   - `https://goods-detail.musinsa.com/api2/goods/{productID}/actual-size`
3. Decode response JSON:
   - `data.sizes[]`
   - `sizes[].name`
   - `sizes[].items[]`
   - `items[].name`
   - `items[].value`
4. Map measurement names into FitMatch measurements.
5. Fill Compare size table.

Supported measurement aliases include:

- Shoulder: `어깨`, `어깨너비`, `shoulder`
- Chest: `가슴`, `가슴단면`, `품`, `chest`, `bust`
- Total length: `총장`, `기장`, `전체길이`, `length`, `bodylength`
- Sleeve: `소매`, `소매길이`, `화장`, `sleeve`
- Bottom-related fallback aliases: waist, hip, thigh, rise, inseam, hem

If the API fails, the parser chain falls back to `MusinsaParser`.

`MusinsaParser` behavior:

- Uses URLSession to fetch HTML
- Reads product metadata from `__NEXT_DATA__`
- Uses SwiftSoup fallback for `table[class*=ActualSizeTable]`
- If size table cannot be loaded, returns partial product info or automatic extraction failure

## 8. Current Compare Flow

1. User enters product URL in `ShoppingProductFormView`.
2. User taps `상품 정보 불러오기`.
3. `ShoppingProductViewModel` calls `ProductURLParserService`.
4. Parser fills:
   - URL
   - Brand
   - Product name
   - Category
   - Size options
5. If parsing fails, user can manually enter size measurements.
6. User taps `추천 사이즈 계산`.
7. ViewModel builds:
   - `Brand`
   - `Product`
   - `ProductSize`
8. `RecommendationService` compares product sizes with `UserFit` data.
9. Best recommendation is stored as `RecommendationHistory`.
10. Result is shown in `RecommendationResultView`.

## 9. Share Extension Status

Share Extension source files exist:

- `FitMatch/FitMatchShareExtension/ShareViewController.swift`
- `FitMatch/FitMatchShareExtension/Info.plist`
- `FitMatch/FitMatchShareExtension/FitMatchShareExtension.entitlements`

Current intended behavior:

1. Share Extension receives URL or plain text.
2. It extracts the first valid URL.
3. It saves the URL to App Group UserDefaults.
4. Main app checks `SharedURLStore.consumePendingProductURL()` when active.
5. If a pending URL exists, the app switches to Compare tab and injects the URL.

Important status:

- The source structure exists.
- `project.pbxproj` currently does not appear to include a native `FitMatchShareExtension` target.
- Xcode target setup still needs to be completed and verified.

## 10. Login and Splash Status

### Splash

Implemented.

Behavior:

- Black background
- Shows `SplashBackground` asset
- Waits about 0.8 seconds
- Then moves to Login

### Login

Implemented as UI only.

Buttons:

- Apple
- Google
- Kakao
- Naver

Current limitation:

- No real OAuth
- Button tap only sets `isLoggedIn = true`
- Login state is not persisted

## 11. Mock or Incomplete Features

- Real OAuth is not implemented.
- Login session persistence is not implemented.
- User profile/account data model is not implemented.
- Recommend tab is not a real AI recommendation engine yet.
- Recommend tab currently uses `RecommendationHistory`.
- Brand DB screen is mostly placeholder level.
- My Page menu items are mostly UI placeholders.
- Share Extension source exists, but Xcode target registration appears incomplete.
- Musinsa is the only real parser path currently implemented.
- Coupang, Uniqlo, and other shopping mall parsers are not implemented.
- Category detection is still basic keyword mapping.
- `MusinsaWebViewParser` exists but is not active in parser chain.
- No server sync or cloud storage.
- Automated test coverage is minimal or not meaningful yet.

## 12. Recent Changes

### Recommend Delete Feature

Added delete support to Recommend tab.

Changes:

- Added trash button to recommendation cards.
- Added delete confirmation dialog.
- Deletes `RecommendationHistory` through SwiftData.
- Calls `modelContext.save()`.

### Representative Clothes Fix

Fixed representative clothes not appearing reliably.

Changes:

- Added direct representative toggle button in closet cards.
- Added swipe action to mark/unmark representative clothes.
- Saves representative flag immediately through SwiftData.
- Explicitly saves new closet items after insert.
- Fixed edit flow to copy these fields back into existing `UserFit`:
  - `isRepresentative`
  - `gender`
  - `detailCategory`
  - `fitPreference`

## 13. Current Build Status

Last verified build succeeded.

Command:

```bash
xcodebuild build -project FitMatch/FitMatch.xcodeproj -scheme FitMatch -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/FitMatchDerivedDataClean2 CODE_SIGNING_ALLOWED=NO
```

Result:

```text
BUILD SUCCEEDED
```

## 14. Recommended Next Development Priorities

1. Register and verify the Share Extension as a real Xcode target.
2. Add login state persistence.
3. Add a simple user profile model.
4. Add delete support to Recommendation History if desired.
5. Separate Recommend tab into a real recommendation domain model.
6. Improve recommendation scoring using:
   - Representative clothes
   - Preferred brands
   - Preferred fit
   - Recent comparison history
   - Category match
7. Improve category detection from product metadata.
8. Stabilize Musinsa product basic info loading.
9. Add parsers for Uniqlo, Coupang, and other shopping malls.
10. Add SwiftData migration policy.
11. Test Musinsa actual-size API on real device.
12. Add unit tests for:
   - Musinsa product ID extraction
   - actual-size JSON decoding
   - recommendation algorithm
   - representative clothes priority
   - SharedURLStore save/consume behavior

