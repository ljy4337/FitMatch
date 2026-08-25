# COS KR 연동 분석 — 2026-08-21

## 확인한 공식 데이터

- 상품 URL의 10자리 article 번호는 스타일 단위 식별자다. 실제 색상 상품 식별자는 페이지 데이터의 `slitmCd`다. 예시 URL `1349394002`는 `slitmCd=40B1490048`로 확인됐다.
- 사이즈 API는 `GET /ko-kr/pub/ncp/gb/v1/pd/gbProduct/getSizeGuide?slitmCd={slitmCd}&sectId={sectId}` 형식이다. 예시 상품의 페이지 데이터상 `sectId=254652`다.
- 같은 상품의 공식 UI에서 S–XXL 의류 실측을 확인했다. M 기준 어깨 43.0cm, 가슴단면 53.5cm, 등기장 64.0cm, 소매길이 25.25cm다. 이는 신체 권장 사이즈가 아니라 FitMatch 비교에 쓸 수 있는 의류 실측이다.
- COS는 Akamai로 비브라우저 요청을 403 처리할 수 있다. 따라서 API 응답이 실패하거나 식별자가 확인되지 않으면 추정값을 만들지 않고 자동 비교를 중단해야 한다.

## FitMatch 처리 계약

1. 공식 상품 페이지에서 이름·가격·이미지·`slitmCd`·`sectId`를 읽는다.
2. 해당 두 식별자로 공식 사이즈 API를 요청한다.
3. `Shoulder to shoulder`, `½ Chest`, `Back length`, `Sleeve length`만 비교 정의가 명확한 실측으로 매핑한다. 그 밖의 열은 원문과 함께 보존하되 비교에는 쓰지 않는다.
4. 원본 API·페이지·카테고리 중 하나라도 변하면 partial 상태로 반환하고 사용자에게 자동 비교 불가를 안내한다.

## 카테고리 범위

공식 GNB에는 여성·남성 합계 99개 노드가 있었으며, 그중 캠페인/에디트/신상품/모두보기처럼 다중 의류 구조를 섞는 랜딩 노드는 자동 분류 대상에서 제외했다. `fitmatch_supabase_seed_cos_categories.sql`은 FitMatch에 의미 있는 여성·남성 의류 60개 노드를 실제 COS `sectId`와 함께 저장한다.

주요 정규화는 다음과 같다.

| COS 분류 | FitMatch |
| --- | --- |
| 니트웨어 > 가디건 | outerwear / cardigan |
| 티셔츠 > 슬림·레귤러·릴랙스 | tops / short_sleeve |
| 베스트 & 슬리브리스 | tops / sleeveless |
| 트라우저 > 쇼츠 | bottoms / shorts |
| 트라우저·진 > 와이드·스트레이트·배럴 | bottoms / long_pants |
| 아우터웨어 > 재킷·코트·블레이저 | outerwear / jacket·coat·blazer |
| 드레스·스커트 | dresses / one_piece, skirts / skirt |

`셔츠 & 블라우스`처럼 구조가 섞인 메뉴는 `tops / other_tops`로만 저장한다. 이를 셔츠 또는 블라우스로 자동 확정하면 실제 상품 구조를 잃으므로, 상품명과 API 상세의 원본 분류를 추가로 확인한 뒤 최종 분류한다.

## DB 적용 순서

1. `public.sources`에 `code='cos'`가 있어야 한다.
2. `fitmatch_supabase_seed_cos_categories.sql`을 실행한다. 이 스크립트는 source category를 upsert하고 mapped leaf가 모두 채워졌는지 검증한다.
3. COS 상품 관측은 기존 `106_add_cos_observation_source.sql`의 authenticated 관측 경계를 사용한다. 앱은 원문 표·원문 라벨·`slitmCd`·`sectId`를 보존해 제출하고, 백엔드 검토 뒤에만 canonical catalog로 승격한다.

운영 Supabase에는 이 세션에서 SQL을 실행하지 않았다.
