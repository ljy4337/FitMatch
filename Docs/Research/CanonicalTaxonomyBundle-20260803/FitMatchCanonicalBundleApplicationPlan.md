# FitMatch canonical bundle application plan

## Decision

앱 적용 가능. 런타임 Supabase 연결 없이 번들 JSON을 한 번 decode하고, 내 옷장과 쇼핑 상품 모두 동일한 resolver를 사용한다.

## Parser lookup compatibility

| Platform | Parser evidence | Confirmed | Primary lookup | Path fallback | Unidentifiable |
|---|---|---:|---:|---:|---:|
| Musinsa | depth 1–4 category code/title, full path, genders | 255 | external ID 255 | 255 available | 0 |
| Uniqlo | breadcrumb/HTML path, target; no category ID | 834 | path+target 834 | path 834 | 0 |

- Musinsa: `categoryDepth4Code ?? categoryDepth3Code ?? categoryDepth2Code ?? categoryDepth1Code`를 external ID 입력으로 사용한다.
- Uniqlo: parser가 첫 audience segment를 target으로 분리하므로 target과 path를 함께 resolver에 전달한다.
- 정규화는 NFC, HTML entity decode, trim, 연속 공백 축소, depth 구분자 ` > ` 통일을 수행한다. 카테고리명 내부 `/`는 분리하지 않는다.
- ID+target 및 ID key 충돌은 0이다. target+path 중복 group 30, target 없는 path 중복 group 277은 결과 충돌 0이며 배열 lookup 후 모든 결과가 동일할 때만 수용한다.

## Runtime types

- `CanonicalTaxonomyBundleStore`: 네 JSON decode, checksum/policy/count 검증, immutable indexes 생성.
- `CanonicalComparisonProfileResolver`: 아래 단일 API 제공.
- `CanonicalComparisonProfile`: decision, semantic type, family, 5개 독립 길이축, construction, eligibility, required measurements, policy/resolution metadata를 보유.
- `CanonicalProfileSnapshot`: SwiftData에 저장할 source identity, resolved values, policy version, resolution method의 Codable snapshot.

```swift
resolveCanonicalComparisonProfile(
    source: String?,
    externalCategoryID: String?,
    target: String?,
    sourceCategoryPath: String?,
    productName: String,
    productDetails: String?,
    measurements: [CanonicalMeasurementValue]
) -> CanonicalComparisonProfile
```

Resolution order:

1. 구체적인 lookup key로 decision을 찾고 rejected/unsupported/navigation을 제외한다.
2. confirmed category mapping을 기본값으로 적용한다.
3. unknown/not-applicable을 구분하며 누락된 길이·construction만 기존 product resolver로 보완한다.
4. review_required는 상품명·상세·경로·공식 사이즈표·실측 fallback을 사용한다.
5. notFound는 기존 parser fallback을 사용한다.
6. family compatibility, required measurements, eligibility, policy version을 최종 검증한다.

## Exact Swift changes for the implementation phase

- `FitMatch/Models/ProductMetadata.swift`: most-specific external category ID 계산 속성 추가.
- `FitMatch/Services/MusinsaProductMetadataParser.swift` — `makeProductMetadata(from:)`, `categoryPath(from:)`: canonical resolver 입력을 보존하되 기존 parser 결과는 유지.
- `FitMatch/Services/UniqloParser.swift` — `UniqloProductMetadataParser.parse(resolved:)`, `categoryPath(...)`, `sourceCategoryPath(from:)`: 내부 slash를 보존하는 canonical lookup path 별도 생성.
- 신규 `FitMatch/Services/CanonicalTaxonomyBundleStore.swift`: bundle decode/index/checksum 검증.
- 신규 `FitMatch/Services/CanonicalComparisonProfileResolver.swift`: 단일 resolver 및 product fallback adapter.
- 신규 `FitMatch/Models/CanonicalComparisonProfile.swift`: 독립 길이축과 snapshot 모델.
- `FitMatch/Models/Product.swift`: canonical snapshot/policy/source identity 저장; 기존 category 필드는 표시 호환용 유지.
- `FitMatch/Models/UserFit.swift`: 같은 canonical snapshot 저장; 기존 Reference Garment 개념 유지.
- `FitMatch/Models/RecommendationHistory.swift`: 계산 당시 product/reference canonical snapshots와 policy version 저장.
- `FitMatch/Models/FitMatchSchema.swift`: V2 lightweight/custom migration stage 추가.
- `FitMatch/ViewModels/ShoppingProductViewModel.swift` — `makeProduct`, `metadataWithSourceCategory`: Product 생성 직전 resolver 1회 호출.
- `FitMatch/ViewModels/AddClosetItemViewModel.swift` — `makeUserFit()`: 동일 resolver 결과를 저장.
- `FitMatch/Services/ComparisonProfileMatcher.swift` — `match`, `profile(for:)`, `manualCandidates`: 재분류 대신 stored canonical profile 사용.
- `FitMatch/Services/SourceCategoryHistoryMatcher.swift`: canonical source identity 우선, legacy depth/path fallback 유지.
- `FitMatch/Services/MeasurementComparisonEngine.swift` — `compare`: canonical policy의 required/optional/excluded/weights를 입력으로 사용.
- `FitMatch/Services/RecommendationService.swift` — recommend/bestRecommendation/candidate paths: eligibility와 동일 canonical profile을 전달.
- `FitMatch/Services/RecommendationHistoryStore.swift` — `saveUnique`: canonical snapshots가 없는 legacy history도 보존.
- `FitMatch/Views/RecommendationResultView.swift`: current result와 다른 사이즈 비교에서 저장된 snapshot 재사용.

보호된 tab/header scroll modifier와 호출부는 변경하지 않는다.

## Screen consistency

최초 상품 분석 시 Product profile을 한 번 만들고, 내 옷장 저장 시 UserFit profile을 한 번 만든다. 기준 옷 선택, 후보 필터, 추천, 실측 점수, 다른 사이즈 비교, 상세 결과, 기록 저장·재진입은 이 두 snapshot을 전달받는다. 화면에서 category/family/length를 다시 추론하지 않는다.

## SwiftData migration

- V2에 Product/UserFit/RecommendationHistory용 optional canonical snapshot JSON, policyVersion, resolutionMethod 필드를 추가한다.
- 기존 Product/UserFit은 최초 접근 또는 명시적 backfill에서 source ID/path로 재분류한다.
- rejected/unsupported로 판정된 기존 항목은 삭제하지 않고 `eligibility=false`로 보존하며 기준 옷·후보·추천에서만 제외한다.
- 기존 대표 옷 flag와 관계는 유지한다. 제외된 대표 옷은 사용자에게 기존 alert로 대체 선택을 요구한다.
- 기존 RecommendationHistory는 계산 snapshot을 그대로 보존하고 재진입 시 과거 결과를 표시한다. 재비교할 때만 최신 policy로 새 snapshot을 만든다.
- source identity가 없는 수동 입력은 기존 product-level resolver로 backfill한다.

## Tests

- 네 JSON decode, manifest/file checksum, deterministic bundle generation.
- 4,008 상태 합계와 runtime 3,426 mapping row 검증.
- Musinsa ID 우선/path fallback, Uniqlo target+path, NFC/공백/HTML/internal slash fixtures.
- 30 target+path 및 277 target-less path multi-match가 동일 결과만 반환하는지 검사.
- confirmed 1,089 전수 필수값, review 894 fallback, rejected 1,403 차단, unsupported 40 차단·extension 보존.
- compatibility 14, measurement policy 14, alias 21과 circumference/flat 변환 테스트.
- Product/UserFit 동일 입력 profile equality 및 모든 화면 score snapshot equality.
- SwiftData V1→V2 migration, rejected/unsupported 보존, legacy history 재진입 회귀.
