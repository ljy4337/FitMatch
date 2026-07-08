# FitMatch Architecture

작성일: 2026-07-07

이 문서는 현재 FitMatch 코드 구조를 간결하게 설명한다.

## 전체 구조

FitMatch는 SwiftUI와 SwiftData를 사용하는 iOS 앱이다.

앱 진입 흐름은 다음과 같다.

1. `FitMatchApp`
2. `ContentView`
3. `SplashView`
4. `LoginView`
5. `MainTabView`

`FitMatchApp.swift`에서 SwiftData model container를 설정한다.

현재 등록된 SwiftData 모델:

- `Brand`
- `Product`
- `ProductSize`
- `UserFit`
- `RecommendationHistory`

## 폴더 역할

### Models

앱의 핵심 데이터 구조를 담당한다.

- `Brand`: 브랜드 정보
- `Product`: 쇼핑 상품 또는 비교 대상 상품
- `ProductSize`: 상품의 사이즈별 실측값
- `UserFit`: 사용자가 저장한 기준 옷/옷장 데이터
- `RecommendationHistory`: 추천 결과 기록
- `ClothingCategory`: 대분류 카테고리
- `UserFitMetadata`: 성별, 핏, 출처 유형, 세부 카테고리
- `GarmentMeasurements`: 실측값 구조와 측정 항목

### Views

SwiftUI 화면을 담당한다.

주요 화면:

- `HomeView`
- `ShoppingProductFormView`
- `RecommendationHistoryView`
- `RecommendView`
- `MyPageView`
- `MyClosetView`
- `AddClosetItemView`
- `ClosetItemDetailView`
- `RecommendationResultView`
- `BrandDatabaseView`

View는 SwiftData `@Query`로 데이터를 직접 읽거나, ViewModel을 통해 화면 상태를 관리한다.

### ViewModels

폼 상태와 화면 로직을 담당한다.

- `ShoppingProductViewModel`
  - URL 입력 상태
  - 파싱된 상품 정보
  - 사이즈 옵션
  - 추천 결과
  - 로딩/에러 상태

- `AddClosetItemViewModel`
  - 옷 등록/수정 폼 상태
  - 카테고리별 실측 입력 항목
  - 저장 가능 여부
  - `UserFit` 생성

### Services

비즈니스 로직과 외부 데이터 처리 흐름을 담당한다.

- `ProductURLParserService`
- `MusinsaParser`
- `MusinsaURLResolver`
- `MusinsaProductMetadataParser`
- `MusinsaActualSizeAPIParser`
- `MusinsaWebViewParser`
- `GenericProductParser`
- `RecommendationService`
- `SharedURLStore`
- `SampleDataService`

### Components

공통 UI 컴포넌트다.

- `FitMatchCard`
- `CardView`
- `PrimaryButton`
- `SecondaryButton`
- `SectionHeader`
- `SmallInfoCard`
- `MeasurementField`
- `SatisfactionPicker`
- `TabBarScrollVisibilityModifier`

## URL Parser 구조

URL 파싱은 `ProductURLParserService`가 라우터 역할을 한다.

현재 분기 기준:

```swift
url.absoluteString.lowercased().contains("musinsa")
```

위 조건이 true면 무신사 전용 파서로 보낸다. 그 외 URL은 `GenericProductParser`로 보낸다.

현재 Generic parser는 실제 파싱을 수행하지 않고 자동 추출 실패를 반환한다.

## MusinsaParser 흐름

무신사 URL 처리 흐름은 다음과 같다.

1. `ProductURLParserService`가 URL 문자열을 정규화한다.
2. URL에 `musinsa`가 포함되어 있으면 `MusinsaParser`를 호출한다.
3. `MusinsaURLResolver`가 GET 요청으로 리다이렉트를 따라간다.
4. 최종 URL, 원본 URL, body에서 상품번호를 추출한다.
5. `MusinsaProductMetadataParser`가 상품 메타데이터를 가져온다.
6. `MusinsaActualSizeAPIParser`가 actual-size API를 호출한다.
7. JSON 응답을 `ParsedProductSize` 배열로 변환한다.
8. `ShoppingProductViewModel`이 파싱 결과를 화면 상태에 반영한다.
9. `RecommendationService`가 추천 결과를 계산한다.

무신사 actual-size API:

```text
https://goods-detail.musinsa.com/api2/goods/{productID}/actual-size
```

무신사 상품 메타데이터 API:

```text
https://goods-detail.musinsa.com/api2/goods/{productID}
```

## RecommendationService 흐름

추천 계산은 `RecommendationService`가 담당한다.

입력:

- 비교 대상 `Product`
- 내 옷장 `UserFit` 목록
- 상품 세부 카테고리

처리:

1. 기준 옷 후보를 우선순위에 따라 선택한다.
2. 상품의 각 사이즈와 기준 옷을 비교한다.
3. 실측 차이를 계산한다.
4. 카테고리별 가중치를 적용한다.
5. weighted difference가 가장 작은 사이즈를 추천한다.
6. 추천도와 비교 방식을 기록한다.
7. `RecommendationHistory`를 생성한다.

기준 옷 선택 우선순위는 플랫폼, 브랜드, 세부 카테고리, 대분류, 대표 옷 여부를 반영한다.

## Share Extension 흐름

Share Extension 구조는 파일로 존재한다.

주요 파일:

- `FitMatchShareExtension/ShareViewController.swift`
- `FitMatchShareExtension/Info.plist`
- `FitMatchShareExtension/FitMatchShareExtension.entitlements`

App Group:

```text
group.io.github.ljy4337.FitMatch
```

동작 흐름:

1. 사용자가 Safari 또는 쇼핑앱에서 URL을 공유한다.
2. Share Extension이 URL 또는 plain text를 읽는다.
3. App Group UserDefaults에 `pendingProductURL`을 저장한다.
4. 메인 앱이 active 상태가 되면 `SharedURLStore`가 pending URL을 소비한다.
5. `ContentView`가 비교 탭으로 이동하고 URL을 전달한다.

현재 코드 기준으로 Share Extension 파일은 존재하지만, Xcode project target 연결은 확인되지 않는다.

## sourceType / sourceName / brandName 개념

FitMatch는 브랜드와 쇼핑 플랫폼을 구분한다.

### sourceType

상품 출처 유형이다.

- `officialStore`: 공식몰
- `marketplace`: 쇼핑 플랫폼
- `manual`: 직접 입력

### sourceName

상품이 들어온 출처 이름이다.

예:

- 무신사
- 유니클로 공식몰
- 직접 입력

### brandName

실제 상품 브랜드다.

예:

- 유니온스튜디오
- 유니클로
- 나이키

이 분리를 통해 무신사에 입점한 브랜드 상품과 공식몰 상품을 다르게 처리할 수 있다.

## 쇼핑몰별 Parser 확장 방식

새 쇼핑몰을 추가할 때는 다음 구조를 따른다.

1. `ProductURLParsing` 프로토콜을 구현하는 parser를 만든다.
2. URL 판별 로직을 `ProductURLParserService`에 추가한다.
3. 쇼핑몰별 URL resolver가 필요하면 별도 파일로 분리한다.
4. 상품 메타데이터 parser를 분리한다.
5. 사이즈표 parser를 분리한다.
6. 결과는 `ParsedProductInfo`로 통일한다.

예상 구조:

- `UniqloParser`
- `UniqloProductMetadataParser`
- `UniqloSizeParser`
- `TwentyNineCMParser`
- `CoupangParser`

중요 원칙:

- `ProductURLParserService`는 라우터 역할만 한다.
- 쇼핑몰별 세부 로직은 각 parser에 둔다.
- 추천 알고리즘은 parser와 분리한다.
