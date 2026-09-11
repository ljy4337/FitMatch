# FitMatch 측정 기준 정책 (2026-09-11)

대상 스냅샷: 유니클로 904개, 무신사 350개, ZARA 554개 원본에서 이미 집계한 측정항목 목록.

## 공통 원칙

- 원본 값·단위·항목명·측정 기준을 그대로 보존한다.
- 둘레와 단면은 서로 다른 값이다. 둘레에 `0.5`를 곱해 단면으로 승격하지 않는다.
- 어깨너비·등너비, 어깨 소매길이·등중심 화장·래글런 화장을 합치지 않는다.
- `저장 가능`과 `비교점수 사용 가능`을 분리한다.
- 비의류 및 겉옷이 아닌 안감·페티코트 값은 저장할 수 있지만 일반 의류 비교점수에서는 제외한다.

## 유니클로

### 비교 가능

| 원본 코드 | 확정 기준 |
|---|---|
| `shoulder-width` | 양쪽 어깨 봉제선 사이 |
| `body-width` | 겨드랑이 아래 가슴 단면 |
| `body-length-back` | 뒤 목점부터 뒤 밑단 |
| `body-length` | 상의·아우터·원피스의 뒤 기준 총장 |
| `knit-body-length-front` | 앞 목점부터 앞 밑단 |
| `sleeve-length` | 어깨 봉제선부터 소매 끝 |
| `sleeve-length-cb` | 등 중심부터 소매 끝 |
| `waist-product-size`, `waist-product-size-bottoms` | 옷의 허리 전체 둘레 |
| `hip-product-size` | 옷의 엉덩이 전체 둘레 |
| `thigh` | 가랑이 인접점부터 바깥선까지 허벅지 단면 |
| `rising-length`, `front-rise` | 가랑이점부터 앞 허리선 |
| `inseam` | 가랑이점부터 안쪽 밑단 |
| `bottom-width` | 밑단 좌우 단면 |
| `skirt-length` | 허리선부터 스커트 밑단 |
| `side-length` | 하의에서는 바깥총장, 스커트에서는 옆선 길이 |

### 저장·표시하되 기본 점수 제외

| 원본 코드 | 확정 기준/사유 |
|---|---|
| `neck-circumference` | 옷의 목둘레; 현재 핵심 점수축 아님 |
| `collar-point` | 칼라 밑점부터 끝까지의 높이 |
| `body-width-gather-and-tack` | 주름·턱 포함 몸판너비; 일반 가슴단면과 다름 |
| `total-length` | 그룹 문맥으로 세부 기준이 확정되지 않으면 원본 전체길이 |
| `body-length-back-back` | 뒤판 전용 길이 |
| `body-length-back-underdress`, `body-width-underdress` | 원피스 안감 실측 |
| `skirt-length-petticoat`, `waist-product-size-petticoat` | 페티코트 실측 |
| `waist-body-size`, `corresponding-size` | 권장 신체치수이며 상품 실측이 아님 |

### 비의류 비교 제외

`around-the-head-product`, `brim`, `crown-length`, `panel-width`,
`nearest-hole`, `farthest-hole`, `insole-length`, `ball-girth`,
`width-length`, `heel-height`, `boot-height`, `lens-width`, `bridge-width`,
`temple-length`, `goods-width`, `goods-height`, `diameter`,
`diameter-folded`, `rib-length`, `length-folded`, `length-of-strap`.

## 무신사

| 원본 항목 | 확정 기준 | 기본 점수 |
|---|---|---|
| 총장 | 유형별 공식 도식의 목점/허리선부터 밑단 | 사용 |
| 어깨너비 | 양쪽 어깨 봉제선 사이 | 사용 |
| 가슴단면 | 겨드랑이 아래 좌우 단면 | 사용 |
| 허리단면 | 허리 좌우 단면 | 사용 |
| 엉덩이단면 | 엉덩이 최대 좌우 단면 | 사용 |
| 허벅지단면 | 가랑이 인접점부터 바깥선까지 단면 | 사용 |
| 밑위 | 가랑이점부터 앞 허리선 | 사용 |
| 밑단단면 | 밑단 좌우 단면 | 사용 |
| 소매길이 | 세트인 어깨 봉제선부터 소매 끝 | 사용 |
| 전체소매길이/화장 | 래글런 목점부터 소매 끝 | 같은 기준끼리만 사용 |
| 소매부리단면 | 소매 끝단 좌우 너비 | 저장·표시, 기본 점수 제외 |
| 암홀 | 원본 암홀 측정값; 직선·곡선·둘레가 확정되지 않음 | 저장·표시, 점수 제외 |

`소매부리단면`은 `소매길이`가 아니며, 문자열 부분일치로 승격하지 않는다.

## ZARA

| 원본 코드 | 확정 기준 | 기본 점수 |
|---|---|---|
| `zone-name-chest` | 가슴 좌우 단면 | 사용 |
| `zone-name-back-width` | 뒤 암홀 사이 등너비; 어깨너비가 아님 | 같은 기준끼리 사용 |
| `zone-name-sleeve-length` | 어깨 봉제선부터 소매 끝 | 사용 |
| `zone-name-arm-width` | 위팔 좌우 단면 | 같은 기준끼리 사용 |
| `zone-name-front-length` | 앞쪽 어깨 기준점부터 앞 밑단 | 같은 기준끼리 사용 |
| `zone-name-waist` | 허리 좌우 단면 | 사용 |
| `zone-name-hips` | 엉덩이 최대 좌우 단면 | 사용 |
| `zone-name-front-rise` | 가랑이점부터 앞 허리선 | 사용 |
| `zone-name-back-rise` | 가랑이점부터 뒤 허리선 | 같은 기준끼리 사용 |
| `zone-name-front-length-lower` | 하의 앞 허리선부터 밑단 | 바깥총장으로 사용 |
| `zone-name-waist-full-body` | 원피스 허리 좌우 단면 | 사용 |
| `zone-name-front-length-full-body` | 원피스 앞쪽 어깨 기준점부터 밑단 | 같은 기준끼리 사용 |

## 오매핑 금지 규칙

1. 유니클로 허리·엉덩이둘레를 단면으로 변환하지 않는다.
2. 유니클로 `knit-body-length-front`를 뒷기장으로 매핑하지 않는다.
3. 무신사 `소매부리단면`을 소매길이로 매핑하지 않는다.
4. 무신사 `암홀`을 암홀깊이 또는 암홀둘레로 추정하지 않는다.
5. ZARA `back-width`를 어깨너비로 매핑하지 않는다.
6. 세트인·등중심·래글런 소매길이는 서로 다른 canonical 코드로 유지한다.
