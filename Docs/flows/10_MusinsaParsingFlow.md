# 10. 무신사 파싱 흐름

## Parser 우선순위

1. `ProductURLParserService.normalizedURL`.
2. URL 문자열에 `musinsa` 포함 여부.
3. 포함 시 `MusinsaParser`.
4. 실패 시 `GenericProductParser` fallback.
5. Generic은 현재 항상 `automaticParsingUnavailable`.

## OneLink 리다이렉트

### 시스템 처리
- `MusinsaURLResolver.resolve`.
- `followRedirects`: GET 요청, URLSession 자동 redirect.
- `response.url`와 body에서 productID 추출.
- 패턴:
  - `products/(\d+)`
  - `products%2[fF](\d+)`
  - `/goods/(\d+)`
  - `goods%2[fF](\d+)`
  - `goodsNo[=:](\d+)`

## actual-size API

### 호출 URL
`https://goods-detail.musinsa.com/api2/goods/{productID}/actual-size`

### 처리
- JSON decode: `MusinsaActualSizeResponse`.
- `data.sizes[]`.
- size.name empty면 제외.
- items name/value를 measurement alias로 매핑.
- 모든 측정값 0이면 size 제외.

## metadata API

### 호출 URL
`https://goods-detail.musinsa.com/api2/goods/{productID}`

### 처리
- 상품명 `goodsNm`.
- 브랜드 `brandInfo.brandName` → `brandEnglishName` → `brand` → `Musinsa`.
- 카테고리 depth1/2/base path에서 map.
- 이미지 URL normalize.
- API 실패 시 HTML fallback.

```mermaid
flowchart TD
    A[System: ProductURLParserService.parse]
    B{URL contains musinsa?}
    C[System: GenericProductParser]
    D[System: MusinsaURLResolver.resolve]
    E[System: GET OneLink/URL follow redirects]
    F{productID 추출 성공?}
    G[Error: unsupportedURL]
    H[System: metadata API 호출]
    I{metadata API 성공?}
    J[System: metadata 파싱]
    K[System: HTML fallback metadata]
    L[System: actual-size API 호출]
    M{HTTP 2xx?}
    N[PartialError: 상품정보만 있음]
    O{JSON decode 성공?}
    P[PartialError: 사이즈표 없음]
    Q[System: sizes/items -> ProductSize]
    R{size count > 0?}
    S[ParsedProductInfo 반환]
    T[Generic fallback]
    A --> B
    B -- NO --> C
    B -- YES --> D --> E --> F
    F -- NO --> G --> T
    F -- YES --> H --> I
    I -- YES --> J
    I -- NO --> K
    J --> L
    K --> L
    L --> M
    M -- NO --> N
    M -- YES --> O
    O -- NO --> P
    O -- YES --> Q --> R
    R -- NO --> P
    R -- YES --> S
```

## 예외 처리 상태

| 예외 | 상태 |
|---|---|
| OneLink redirect network failure | PARTIAL: catch 후 fallback |
| productID 없음 | PARTIAL: unsupported → Generic 실패 |
| actual-size 404/500 | PARTIAL: metadata partial error |
| JSON 구조 변경 | PARTIAL: partial error |
| metadata API 실패 | IMPLEMENTED: HTML fallback |
| image relative path | IMPLEMENTED: normalizeImageURL |

