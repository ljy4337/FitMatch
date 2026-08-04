# 혼합·미확정 카테고리 상품 표본 검수 계획

## 표본 수

| 조건 | 최소 표본 | 확대 기준 |
|---|---:|---|
| 명확한 leaf, 단일 garment/length 예상 | 5 | 예외 1건 이상이면 15 |
| 이름이 혼합형(`A & B`, 기타, 전체, collection) | 15 | 두 garment type 또는 두 length가 관측되면 30 |
| 상품 수 30개 미만 | 전수 | 품절/판매예정도 별도 표시 |
| target별 동일 경로 | target별 5 | target 간 결과가 다르면 target별 15 |
| 비의류/의류 혼재 가능 | 15 | 의류가 1건이라도 있으면 30 또는 전수 |

표본은 추천순에 편향되지 않도록 신상품/판매량/가격 구간에서 deterministic stratified selection을 사용한다. 동일 상품 color variant는 한 표본으로 센다.

## 수집 필드

- product ID, target, 상품명, 공식 category ID/path
- 상세 설명과 구성/형태
- 공식 사이즈표 원본 label/code/unit/value
- garment type 후보
- sleeve/pants/leggings/skirt/body length 축
- 의류/비의류, 비교 가능 여부
- parser 확보 성공 여부와 raw response hash

## 분포와 예외

카테고리별로 `n`, garment type별 count/비율, 각 길이 class count/비율, 비의류 count, parser 실패 count를 계산한다. 예외율은 `주요 판정과 다른 유효 상품 수 / 판정 가능한 표본 수`다. 판정 불가능 상품은 분모에서 빼지 않고 별도 unknown 비율도 함께 보고한다.

## category-level 승격 기준

- confirmed: 판정 가능한 표본 15개 이상 또는 category 전수, semantic garment type 95% 이상 일치, 길이축을 확정한다면 해당 class 95% 이상, 비의류 0, unknown 5% 이하, 공식 경로 의미와 모순 없음.
- review_required: garment/length 혼재, 예외율 5% 초과, unknown 5% 초과, 표본 부족, 상품 정보가 필요한 경우.
- rejected: 전수 또는 최소 15개에서 의류 0이고 공식 category 의미도 비의류이며 사유가 명확한 경우.
- unsupported: 의미상 의류는 확정되지만 현재 앱/비교 engine 표현이 불가능한 경우.

상품 단위 결과는 `product_classification_override` 후보로만 보존하며 category 전체에 자동 확대하지 않는다. 신규 공식 snapshot마다 동일 deterministic 표본 규칙을 재실행한다.

