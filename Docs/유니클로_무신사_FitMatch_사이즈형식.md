# 유니클로·무신사·FitMatch 사이즈 형식

작성 기준: 2026-07-28  
구현 기준: `uniqlo_kr_size_chart_mapping_v6`, `musinsa_actual_size_mapping_v8`, `musinsa_fallback_mapping_v1`

## 1. 공통 저장 원칙

FitMatch는 플랫폼에서 받은 사이즈명과 사이즈표의 각 셀을 삭제하거나 표시용 이름으로 덮어쓰지 않는다.

- 사이즈명: 플랫폼이 제공한 값 그대로 저장한다.
- 원본 항목명: `rawLabel`
- 원본 항목 코드: `rawCode`
- 원본 값 문자열: `rawValueText`
- 원본 설명: `rawInfo`
- 플랫폼/수집 방식: `methodSource`
- 사이즈표 형식: `methodProfile`
- FitMatch 비교용 값과 코드: `value`, `measurementCode`

내 옷장에서는 플랫폼 원본 기록이 있으면 `rawLabel`과 `rawValueText`를 우선 표시한다. 둘레를 단면으로 변환하는 등 비교에 필요한 값은 별도로 보관하며 원본 값은 유지한다.

## 2. 비교 선택 규칙

| 조건 | 비교 방식 |
|---|---|
| 동일 플랫폼 + 동일 `methodSource` + 동일 `methodProfile` | 동일한 `rawCode`, 또는 원본 코드가 없으면 동일한 `rawLabel`끼리 직접 비교 |
| 동일 플랫폼 + 다른 형식 | FitMatch `measurementCode`가 호환되는 항목끼리 비교 |
| 다른 플랫폼 | FitMatch `measurementCode`가 호환되는 항목끼리 비교 |
| 원본 의미 또는 FitMatch 코드가 확인되지 않음 | 비교에서 제외하고 정보 부족으로 표시 |

예를 들어 무신사 API의 `musinsa_type_6`과 무신사 이미지/HTML 표의 `structured_size_table`은 같은 플랫폼이지만 다른 형식이므로 FitMatch 기준으로 변환한 후 비교한다.

## 3. 유니클로 기본 사이즈 형식

플랫폼 식별자는 `methodSource = uniqlo_kr`이다. `methodProfile`은 해당 상품 사이즈표에 포함된 원본 항목 코드의 구성으로 결정된다.

| 유니클로 원본 코드 | 일반적인 원본 항목 | FitMatch 비교 코드 | 변환 |
|---|---|---|---|
| `shoulder-width` | 어깨너비 | `shoulder_width_seam_to_seam` | 없음 |
| `body-width` | 가슴너비/몸 너비 | `chest_width_pit_to_pit` | 없음 |
| `body-length-back`, `body-length`, `knit-body-length-front` | 총장/몸길이 | `body_length_back_neck_to_hem` | 없음 |
| `sleeve-length` | 소매길이 | `sleeve_shoulder_seam_to_cuff` | 없음 |
| `sleeve-length-cb` | 등 중심부터 소매까지 | `sleeve_center_back_to_cuff` | 없음 |
| `waist-product-size` | 허리둘레(상품 사이즈) | `waist_width_edge_to_edge` | 둘레 × 0.5 |
| `hip-product-size` | 엉덩이둘레(상품 사이즈) | `hip_width_at_widest` | 둘레 × 0.5 |
| `thigh` | 허벅지 너비 | `thigh_width_crotch_to_outer` | 없음 |
| `rising-length` | 밑위 길이 | `rise_crotch_to_waist_front` | 없음 |
| `bottom-width` | 밑단 너비 | `hem_width_edge_to_edge` | 없음 |
| `inseam` | 다리 길이/인심 | `pants_inseam_crotch_to_hem` | 없음 |
| `skirt-length` | 스커트 길이 | `skirt_length_waist_to_hem` | 없음 |

## 4. 무신사 기본 사이즈 형식

### 4.1 무신사 실측 API

플랫폼 식별자는 `methodSource = musinsa`이며 형식은 `methodProfile = musinsa_type_{번호}`이다.

| 무신사 형식 | 주요 원본 항목 | FitMatch 비교 코드 |
|---|---|---|
| 타입 5, 7, 8, 9, 10, 20, 21, 38 | 총장, 어깨너비, 가슴단면, 소매길이 | 뒤목점 총장, 봉제선 어깨, 겨드랑이 가슴단면, 어깨선 소매 |
| 타입 11, 22, 31 | 총장, 가슴단면, 화장/소매 | 뒤목점 총장, 겨드랑이 가슴단면, 래글런/등 중심 소매 |
| 타입 24, 25 | 총장, 어깨너비, 가슴단면 | 뒤목점 총장, 봉제선 어깨, 겨드랑이 가슴단면 |
| 타입 6, 23, 42 | 허리단면, 엉덩이단면, 허벅지단면, 밑위, 밑단단면, 총장, 인심 | 허리단면, 엉덩이단면, 허벅지단면, 앞밑위, 밑단단면, 아웃심, 인심 |
| 타입 14 | 총장, 허리단면, 엉덩이단면, 밑단단면 | 스커트 길이, 허리단면, 엉덩이단면, 밑단단면 |
| 타입 19 | 허리단면, 엉덩이단면 | 허리단면, 엉덩이단면 |

### 4.2 쇼핑몰 제공 이미지·HTML 사이즈표

플랫폼 식별자는 `methodSource = musinsa_fallback`, 형식은 `methodProfile = structured_size_table`이다.

- 단면 항목은 원본 값을 그대로 비교용 값으로 사용한다.
- 둘레 항목은 원본 값을 보존하고 비교용 단면 값은 `둘레 × 0.5`로 만든다.
- mm 표기는 cm로 `× 0.1`, inch 표기는 cm로 `× 2.54` 변환한다.
- 변환 내역은 `rawInfo`에 기록한다.

지원하는 주요 원본 항목은 가슴단면/가슴둘레, 어깨, 총장/앞총장/뒤총장, 소매/화장, 허리단면/허리둘레, 엉덩이, 허벅지, 밑위/뒷밑위, 밑단, 인심, 발길이이다.

## 5. FitMatch 기본 비교 형식

| 표시 항목 | FitMatch 기본 측정 기준 |
|---|---|
| 어깨 | 좌우 어깨 봉제선 사이 |
| 가슴 | 겨드랑이 아래 가슴 단면 |
| 총장(상의/아우터) | 뒤목점부터 밑단 |
| 소매 | 어깨 봉제선부터 소매 끝. 등 중심/래글런 소매는 별도 코드 |
| 허리 | 허리 양 끝 단면 |
| 엉덩이 | 가장 넓은 지점의 단면 |
| 허벅지 | 가랑이점부터 바깥쪽까지 단면 |
| 밑위 | 가랑이점부터 앞 허리선 |
| 밑단 | 밑단 양 끝 단면 |
| 바지 총장 | 허리선부터 밑단까지 아웃심 |
| 인심 | 가랑이점부터 밑단 |
| 스커트 길이 | 허리선부터 밑단 |
| 발길이 | 뒤꿈치부터 발끝 |

가슴둘레는 가슴단면으로 변환해 비교할 수 있다. 그 외에는 측정 코드가 같거나 명시적인 변환 규칙이 있는 경우에만 비교한다. 총장과 인심, 어깨선 소매와 등 중심 소매처럼 측정 시작점이 다른 항목은 같은 값으로 간주하지 않는다.

