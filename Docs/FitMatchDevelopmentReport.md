# FitMatch 개발 현황 보고서

작성 기준: 현재 실제 코드 기준
작성일: 2026-07-07

## 1. 프로젝트 구조

- 루트: `/Users/jinyoung/Documents/Projects/FitMatch/FitMatch`
- 앱 소스: `FitMatch/`
- 주요 폴더:
  - `Models`: SwiftData 모델, 카테고리, 측정값, 메타데이터 enum
  - `Views`: SwiftUI 화면
  - `ViewModels`: 화면 상태 관리
  - `Services`: URL 파서, 추천 알고리즘, 샘플 데이터, 공유 URL 저장
  - `Components`: 공통 UI 컴포넌트
  - `Assets.xcassets`: 앱 아이콘, 스플래시 이미지, 빈 옷장 이미지
  - `FitMatchShareExtension`: Share Extension용 파일 구조
  - `Docs`: 프로젝트 문서

주요 파일:

- `FitMatchApp.swift`: SwiftData `modelContainer` 설정
- `ContentView.swift`: Splash/Login/MainTab 진입 흐름
- `ShoppingProductFormView.swift`: 비교 탭
- `MyClosetView.swift`: 내 옷장
- `RecommendationService.swift`: 추천 계산
- `ProductURLParserService.swift`: URL 파서 라우터
- `MusinsaParser.swift`: 무신사 파싱 조율

아키텍처:

- SwiftUI + SwiftData
- MVVM에 가까운 구조
- View는 SwiftData `@Query`와 ViewModel을 혼합 사용
- Service 계층에서 URL 파싱과 추천 계산 담당

## 2. 현재 구현된 기능

구현 완료:

- Splash 화면
- Login UI
- 5개 하단 탭
- 내 옷장 등록/수정/삭제
- 대표 옷 지정/해제
- 카테고리별 실측 입력 항목 변경
- 무신사 URL 파싱
- 무신사 actual-size API 기반 사이즈표 로드
- 상품 URL 기반 사이즈 계산
- 추천 결과 시트 표시
- 추천 기록 저장/삭제
- 추천 탭에서 기록 기반 추천 카드 표시/삭제
- App Group 기반 pending URL 저장/소비 코드

일부 구현:

- Share Extension 파일 구조
- 브랜드 DB 화면
- 추천 화면
- 로그인
- 상품 메타데이터 파싱
- 무신사 OneLink 리다이렉트 처리

미구현:

- 실제 OAuth
- Generic 쇼핑몰 파싱
- 29CM/쿠팡/유니클로 전용 파서
- 실제 AI 추천
- 프로필/앱설정 상세 기능
- Share Extension Xcode target 연결

## 3. 화면(UI)

- `SplashView`
  - `SplashBackground` 이미지를 전체 화면으로 표시
  - 0.8초 후 로그인 화면으로 이동
- `LoginView`
  - Apple/Google/Kakao/Naver 로그인 버튼
  - 실제 OAuth 없음
- `MainTabView`
  - 홈 / 비교 / 기록 / 추천 / 마이
- `HomeView`
  - FIT MATCH 헤더
  - 알림 placeholder 버튼
  - 검정 Hero 카드: 새 상품 비교
  - 내 옷장 요약
  - 최근 비교 요약
  - 추천 미리보기
- `ShoppingProductFormView`
  - URL 입력 + `사이즈 계산` 버튼 중심
  - 쇼핑 상품 직접입력 섹션 제거됨
  - 사이즈별 실측 직접입력 영역 제거됨
  - 결과는 `RecommendationResultView` 시트로 표시
  - 기준 옷이 없으면 등록/선택 유도
- `MyClosetView`
  - 카드형 옷장 목록
  - 빈 상태: `옷장이 비었습니다.` + `EmptyCloset` 이미지
  - 상단 `My Closet` 타이틀 제거됨
  - 상단 우측 원형 플러스 버튼으로 등록
  - 좌측 스와이프: 대표 지정/해제
  - 기본 delete 동작: `.onDelete`
- `AddClosetItemView`
  - 출처 유형, 성별, 카테고리, 세부 카테고리, 상품명, 사이즈, 실측값, 핏, 만족도 입력
  - 대표 옷 설정은 현재 등록 화면에 없음
- `ClosetItemDetailView`
  - 옷 상세 정보
  - 수정 시 `AddClosetItemView(item:)` 재사용
- `RecommendationResultView`
  - 추천 사이즈 강조
  - 추천도 %
  - 비교 기준 정보
  - 상품 실측(차이)
  - 내 옷장의 다른 옷과 비교하기
- `RecommendationHistoryView`
  - 추천 기록 목록
  - 쇼핑몰 이동
  - 다시 비교
  - 삭제
  - 상단 큰 타이틀 제거됨
- `RecommendView`
  - 기록 기반 추천 상품 카드
  - 구매 버튼
  - 삭제
  - 상단 큰 타이틀/헤더 제거됨
- `MyPageView`
  - 내 정보
  - 내옷장관리
  - 앱설정
  - 로그아웃
- `BrandDatabaseView`
  - 브랜드와 상품 목록 표시용 임시 DB 화면

최근 변경된 UI:

- 비교/기록/추천 화면 상단 큰 navigation title 제거
- `MyClosetView` 상단 `My Closet` 제거
- 옷장 추가 버튼을 큰 검정 원형 버튼으로 변경
- 비교 화면은 URL 입력과 `사이즈 계산` 버튼만 남김
- 비교 화면의 직접입력/사이즈표 수동 입력 UI 제거
- 빈 옷장 이미지를 심플한 이미지로 교체

## 4. SwiftData 모델

### Brand

필드:

- `id`
- `name`
- `normalizedName`
- `countryCode`
- `websiteURL`
- `notes`
- `createdAt`
- `updatedAt`

관계:

- `products: [Product]`
- delete rule: Brand 삭제 시 Product cascade

### Product

필드:

- `id`
- `name`
- `categoryRawValue`
- `productCode`
- `sourceURLString`
- `sourceTypeRawValue`
- `sourceName`
- `sourceRawValue`
- `notes`
- `createdAt`
- `updatedAt`

관계:

- `brand: Brand?`
- `sizes: [ProductSize]`

계산 프로퍼티:

- `category`
- `source`
- `sourceType`
- `sourceDisplayName`
- `displayName`

### ProductSize

필드:

- `id`
- `name`
- `shoulder`
- `chest`
- `totalLength`
- `sleeveLength`
- `waist`
- `hip`
- `thigh`
- `rise`
- `hem`
- `footLength`
- `underBust`
- `displayOrder`
- `createdAt`
- `updatedAt`

관계:

- `product: Product?`

계산 프로퍼티:

- `measurements`

### UserFit

필드:

- `id`
- `sourceTypeRawValue`
- `sourceName`
- `brandName`
- `genderRawValue`
- `productName`
- `categoryRawValue`
- `detailCategoryRawValue`
- `sizeName`
- `shoulder`
- `chest`
- `totalLength`
- `sleeveLength`
- `waist`
- `hip`
- `thigh`
- `rise`
- `hem`
- `footLength`
- `underBust`
- `fitMemo`
- `fitPreferenceRawValue`
- `satisfaction`
- `isRepresentative`
- `createdAt`
- `updatedAt`

관계:

- `sourceProduct: Product?`
- `sourceProductSize: ProductSize?`

계산 프로퍼티:

- `sourceType`
- `gender`
- `category`
- `detailCategory`
- `fitPreference`
- `measurements`
- `displayName`

### RecommendationHistory

필드:

- `id`
- `totalDifference`
- `shoulderDifference`
- `chestDifference`
- `totalLengthDifference`
- `sleeveLengthDifference`
- `waistDifference`
- `hipDifference`
- `thighDifference`
- `riseDifference`
- `hemDifference`
- `footLengthDifference`
- `underBustDifference`
- `recommendationScore`
- `trueToSizeRecommendation`
- `oversizedRecommendation`
- `comparisonMethod`
- `fallbackReason`
- `productDetailCategoryRawValue`
- `reason`
- `createdAt`

관계:

- `product: Product`
- `recommendedSize: ProductSize`
- `userFit: UserFit`

계산 프로퍼티:

- `measurementDifferences`
- `productDetailCategory`

## 5. Service

- `ProductURLParserService`
  - URL 문자열 정규화
  - `musinsa` 포함 여부로 파서 라우팅
  - 무신사 실패 시 Generic fallback
- `MusinsaParser`
  - 무신사 전체 파싱 흐름 조율
  - URL resolve -> metadata parse -> actual-size parse
- `MusinsaURLResolver`
  - GET 요청으로 redirect 따라감
  - `response.url`과 body에서 상품번호 추출
  - `/products/{id}`, percent-encoded URL, `goodsNo`, nested query 대응
- `MusinsaActualSizeAPIParser`
  - actual-size API 호출
  - JSON 응답을 `ParsedProductSize`로 변환
- `MusinsaProductMetadataParser`
  - 상품 상세 API 호출
  - 브랜드/상품명/카테고리/이미지/가격/canonical URL 추출
  - 실패 시 HTML title/og:image/canonical fallback
- `MusinsaWebViewParser`
  - WKWebView 기반 DOM 사이즈표 추출 코드 존재
  - 현재 `ProductURLParserService` 기본 라우팅에는 연결되어 있지 않음
- `GenericProductParser`
  - 현재 항상 `automaticParsingUnavailable` throw
  - TODO 있음
- `RecommendationService`
  - 기준 옷 선택
  - 사이즈별 weighted difference 계산
  - 추천도 계산
  - 추천 기록 생성
- `SharedURLStore`
  - App Group UserDefaults에 pending URL 저장/소비
- `SampleDataService`
  - 최초 실행 시 샘플 Brand/Product/UserFit 삽입

## 6. ViewModel

### ShoppingProductViewModel

역할:

- 상품 URL 입력 상태 관리
- URL 파싱 호출
- 파싱 결과를 화면 상태로 반영
- 추천 계산 호출
- 임시 기준 옷 비교 처리

상태:

- `@Published productURL`
- `@Published sourceType`
- `@Published sourceName`
- `@Published brand`
- `@Published productName`
- `@Published category`
- `@Published detailCategory`
- `@Published sizeOptions`
- `@Published recommendation`
- `@Published errorMessage`
- `@Published parserNotice`
- `@Published isLoadingProductInfo`
- `@Published productImageURLString`
- `@Published productPrice`
- `@Published productCanonicalURLString`
- `@Published hasLoadedProductInfo`

### AddClosetItemViewModel

역할:

- 옷 등록/수정 폼 상태 관리
- 출처 유형, 브랜드, 성별, 카테고리, 세부 카테고리, 실측값, 핏, 만족도 관리
- 카테고리에 맞는 측정 항목 반환
- `makeUserFit()`으로 SwiftData 저장용 `UserFit` 생성

상태 관리 방식:

- `ObservableObject`
- 각 입력값을 `@Published`로 관리
- View에서 SwiftData `modelContext`로 insert/save 수행

## 7. URL Parser

현재 지원 쇼핑몰:

- 실질 지원: 무신사
- Generic parser는 구현되어 있으나 실제 파싱 없음

URL 처리 흐름:

1. `ShoppingProductViewModel.loadProductInfoFromURL()`
2. `ProductURLParserService.parse(urlString:)`
3. URL 문자열 정규화
4. `absoluteString.lowercased().contains("musinsa")`면 무신사 파서
5. 그 외 Generic parser

리다이렉트 처리:

- 무신사는 `MusinsaURLResolver.followRedirects()`에서 GET 요청 사용
- URLSession 기본 redirect 동작 사용

상품번호 추출 방식:

- `products/(\d+)`
- `products%2[fF](\d+)`
- `/goods/(\d+)`
- `goods%2[fF](\d+)`
- `goodsNo[=:](\d+)`
- query/nested query/percent-decoded variants 탐색

Parser 우선순위:

- 무신사 URL: `MusinsaParser`
- 무신사 실패: `GenericProductParser`
- 일반 URL: `GenericProductParser`

## 8. 무신사 관련

actual-size API 사용 여부:

- 사용 중

호출 URL:

- `https://goods-detail.musinsa.com/api2/goods/{productID}/actual-size`

상품 메타데이터 API:

- `https://goods-detail.musinsa.com/api2/goods/{productID}`

응답 처리:

- `data.sizes[]`
- size `name`
- `items[]`의 `name`, `value`
- `FlexibleString`으로 String/Double/null 대응

카테고리 처리:

- metadata API의 `categoryDepth1Name`, `categoryDepth2Name`, `baseCategoryFullPath`, 상품명 기반 매핑
- 상의/하의/아우터/원피스/속옷/셔츠/니트/기타로 매핑
- 세부 카테고리는 텍스트 포함 여부로 반팔/긴팔/후드/셔츠/슬랙스/데님/점퍼 등 매핑

사이즈 처리:

- 컬럼 alias 기반
- 어깨, 가슴, 총장, 소매, 허리, 힙, 허벅지, 밑위, 밑단 등 추출
- 값이 없는 실측은 0으로 모델에 저장되지만, 폼 텍스트 변환 시 0은 공란으로 표시

브랜드 처리:

- `brandInfo.brandName`
- 없으면 `brandEnglishName`
- 없으면 `brand`
- 없으면 `"Musinsa"`

이미지 처리:

- `thumbnailImageUrl` 추출
- `ParsedProductInfo.imageURLString`에 저장
- 현재 주요 UI에서 상품 이미지를 크게 렌더링하는 흐름은 확인되지 않음

## 9. 추천 알고리즘

현재 비교 방식:

- 상품의 sourceName/brand/detailCategory/category 기준으로 기준 옷 선택
- 사용자가 직접 기준 옷을 선택하는 임시 비교 지원

기준 옷 우선순위:

1. 같은 플랫폼 + 같은 브랜드 + 같은 세부카테고리 대표옷
2. 같은 플랫폼 + 같은 브랜드 + 같은 세부카테고리 일반 옷
3. 같은 브랜드 + 같은 세부카테고리 대표옷
4. 같은 브랜드 + 같은 세부카테고리 일반 옷
5. 같은 플랫폼 + 같은 세부카테고리 대표옷
6. 같은 플랫폼 + 같은 세부카테고리 일반 옷
7. 같은 세부카테고리 대표옷
8. 같은 세부카테고리 일반 옷
9. 같은 대분류 대표옷
10. 같은 대분류 일반 옷

계산식:

- 상품 사이즈 실측 - 기준 옷 실측 = signed difference
- 절댓값 차이에 카테고리별 weight 적용
- `weightedDifference = weightedSum / weightSum`

추천도 계산:

- `score = max(0, min(100, Int((100 - weightedDifference * 4).rounded())))`
- 비교 방식 penalty 차감
- 유효 비교 항목 2개 이상이고 score > 0이면 최소 30점 보정

추천 사이즈 결정 방식:

- 모든 ProductSize와 후보 UserFit 조합을 비교
- `weightedDifference`가 가장 작은 조합 선택

대표옷 우선순위:

- 후보 정렬 시 `isRepresentative`가 true인 옷 우선
- source/brand/detail/category 우선순위 그룹 안에서도 대표옷 조건이 먼저 평가됨

주요 weight:

- 상의/아우터: 어깨 1.2, 가슴 1.4, 총장 1.0, 소매 0.8
- 하의: 총장 1.0, 허리 1.4, 힙 1.2, 허벅지 0.9, 밑위 0.7, 밑단 0.6
- 신발: 발길이 1.6
- 반팔: 소매 weight 최대 0.2
- 민소매: 소매 weight 0
- 사용자 선택 임시 비교: penalty 12

## 10. Share Extension

구현 여부:

- 파일 구조는 있음
- `FitMatchShareExtension/ShareViewController.swift`
- `FitMatchShareExtension/Info.plist`
- `FitMatchShareExtension/FitMatchShareExtension.entitlements`

App Group:

- `group.io.github.ljy4337.FitMatch`
- 메인 앱 entitlements에도 동일 App Group 있음

URL 전달 흐름:

1. Share Extension이 `UTType.url` 또는 plain text에서 URL 추출
2. App Group UserDefaults에 `pendingProductURL` 저장
3. 메인 앱 `ContentView`가 active/task 시 `SharedURLStore.consumePendingProductURL()` 호출
4. pending URL 있으면 비교 탭으로 이동

Xcode Target 연결 여부:

- `FitMatch.xcodeproj/project.pbxproj`에서 `FitMatchShareExtension`, `ShareViewController`, `com.apple.product-type.app-extension` 문자열 검색 결과 없음
- 현재 코드 기준으로는 Share Extension 파일은 존재하지만 Xcode target 연결은 확인되지 않음

## 11. 현재 알려진 문제점

- GenericProductParser는 실제 파싱 미구현
- 무신사 외 쇼핑몰 URL은 자동 추출 실패
- Share Extension target이 Xcode 프로젝트에 연결된 상태로 확인되지 않음
- 실제 OAuth 없음
- 추천 탭은 AI가 아니라 RecommendationHistory 기반
- BrandDatabaseView는 기본 목록 표시 수준
- 상품 이미지 URL은 파싱되지만 주요 결과 UI에서 적극 표시되지 않음
- `MusinsaWebViewParser`는 존재하지만 기본 URL 라우팅에는 사용되지 않음
- 일부 Git status에 이상한 경로 `https:/www.musinsa.com/products/6003426/...`가 추가 파일로 잡혀 있음

## 12. 최근 작업 내역

마지막으로 수정된 기능:

- 비교/기록/추천 화면 상단 큰 navigation title 제거
- MyCloset 상단 `My Closet` 제거
- 옷장 추가 버튼을 더 큰 검정 원형 버튼으로 변경

최근 추가된 기능:

- 빈 옷장 이미지 `EmptyCloset`
- 상품 URL 기반 비교 화면 단순화
- 소스 타입/출처/브랜드 개념
- 무신사 actual-size API 파서
- 카테고리 기반 추천 기준 선택
- 추천 기록/추천 탭 삭제 기능

삭제된 기능/UI:

- 비교 화면의 쇼핑 상품 직접입력 카드
- 비교 화면의 사이즈별 실측 직접입력 영역
- 비교 화면의 별도 추천 계산 카드
- 추천 화면 상단 큰 추천 헤더

## 13. 현재 빌드 상태

빌드 명령:

```bash
xcodebuild build -project FitMatch.xcodeproj -scheme FitMatch -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/FitMatchDerivedDataClean2 CODE_SIGNING_ALLOWED=NO
```

결과:

- `BUILD SUCCEEDED`

Error:

- 없음

Warning/Note:

- 최신 빌드 출력에 `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.` note가 있음
- 빌드는 성공

## 14. 앞으로 개발 예정(Task)

- Share Extension target을 Xcode 프로젝트에 실제 연결
- 무신사 OneLink 실패 케이스 추가 검증
- 29CM/쿠팡/유니클로 parser 추가
- Generic parser 정책 결정
- 상품 이미지 UI 반영
- 추천 탭을 실제 추천 로직으로 확장
- 브랜드 DB 화면 고도화
- 로그인 실제 OAuth 연동
- 프로필/앱설정 상세 구현
- 추천 결과 저장/재비교 UX 정리
- 카테고리별 측정값 검증 강화
- Git status의 이상 경로 정리 여부 판단

## 15. Git 정보

현재 Branch:

- `main`
- `main...origin/main`

마지막 Commit:

- `5a6da29 Migrate project to SwiftData`

변경된 파일 상태 요약:

- 수정됨:
  - `FitMatch.xcodeproj/project.pbxproj`
  - scheme management plist
  - `ContentView.swift`
  - `FitMatchApp.swift`
  - 여러 모델/서비스/ViewModel/View 파일
- 삭제됨:
  - 기존 `BaselineFit.swift`
  - `ClosetItem.swift`
  - `ClothingSize.swift`
  - `RecommendationRecord.swift`
  - `ShoppingProduct.swift`
- 추가됨:
  - AppIcon PNG
  - SplashBackground asset
  - EmptyCloset asset
  - 새 SwiftData 모델들
  - 새 서비스들
  - Home/My/Recommend/History/BrandDatabase 화면들
  - Share Extension 폴더
- 추적 안 됨:
  - `Docs/`
  - `FitMatchShareExtension/`
  - 여러 신규 Swift 파일
- 특이 추가 경로:
  - `https:/www.musinsa.com/products/6003426/...`

## 16. ChatGPT에게 전달해야 하는 중요 사항

프로젝트 철학:

- FitMatch는 단순 사이즈 계산기가 아니라 “내 옷을 기준으로 쇼핑 상품의 핏과 사이즈를 비교하는 개인 맞춤 핏 플랫폼”

개발 방향:

- SwiftData 기반 로컬 DB 유지
- URL 자동 파싱 중심
- 내 옷장 기준 추천 중심
- 무신사 actual-size API는 현재 핵심 데이터 소스
- UI는 미니멀, 패션 플랫폼, Apple HIG 스타일

앞으로 수정하면 안 되는 규칙:

- SwiftData 구조를 무단으로 깨지 말 것
- `MusinsaParser`, actual-size API 흐름 삭제 금지
- `RecommendationService` 삭제 금지
- 공유 URL 처리 구조 삭제 금지
- 기존 Compare 흐름 삭제 금지
- 직접 입력은 옷장에서 처리하고, 비교 화면은 URL 기반 계산 중심 유지

현재 가장 중요한 우선순위:

- Share Extension target 연결
- 무신사 URL/OneLink 안정화
- 무신사 외 쇼핑몰 parser 확장
- 추천 결과 UI와 추천 신뢰도 개선

## 17. 현재 확정된 기획 사항

확정된 설계:

- 앱 진입은 Launch -> Splash -> Login -> MainTab
- 하단 탭은 홈 / 비교 / 기록 / 추천 / 마이
- 내 옷장은 독립 탭이 아니라 Home/My에서 접근
- 비교 탭은 URL 입력 중심
- 직접 상품/사이즈 입력은 비교 탭이 아니라 옷장 등록에서 처리
- 브랜드와 쇼핑 플랫폼은 분리
- `sourceType`, `sourceName`, `brandName`을 구분
- 무신사는 marketplace, sourceName은 `무신사`
- 기준 옷 선택은 소스/브랜드/세부카테고리/대분류 순서로 우선순위 적용

왜 이렇게 설계했는지:

- 브랜드와 플랫폼을 구분해야 “무신사에 입점한 브랜드”와 “공식몰 브랜드”를 정확히 비교할 수 있음
- UserDefaults보다 SwiftData가 누적되는 옷장/상품/추천 기록에 적합함
- 비교 화면을 URL 중심으로 단순화해야 실제 서비스 핵심 가치가 명확해짐
- 기준 옷은 같은 플랫폼/브랜드/카테고리일수록 추천 신뢰도가 높음

아직 확정되지 않은 부분:

- 실제 사용자 계정/프로필 데이터 모델
- AI 추천 방식
- 쇼핑몰별 parser 범위와 우선순위
- 브랜드 DB를 앱 내부 DB로 확장할지 여부
- 상품 이미지 활용 UI

향후 변경 예정인 부분:

- Generic parser 구현
- 쇼핑몰별 parser 추가
- Share Extension target 연결
- 추천 화면 고도화
- 로그인 실제 연동

절대 변경하면 안 되는 설계:

- SwiftData 기반 저장 구조
- `Brand / Product / ProductSize / UserFit / RecommendationHistory` 중심 데이터 구조
- 무신사 actual-size API 기반 사이즈표 로드
- 비교 화면 URL 기반 계산 흐름
- 내 옷장 기준 추천 철학
- sourceType/sourceName/brandName 분리 설계
