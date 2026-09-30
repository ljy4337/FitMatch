# MUSINSA 공개 의류 데이터 수집 보고서

## 결론

이 산출물은 **전 상품 수집 완료본이 아니다.** 현재 공개적으로 확인된 공식 sitemap, 의류 카테고리 PLP, 상품 상세, actual-size, options 응답을 사용한 카테고리 층화 수집 결과이며 coverage 상태는 `BEST_EFFORT_PARTIAL_NOT_FULL_CATALOG`이다.

공식 상품 sitemap 10개에서 고유 상품 URL 9,621개를 확인했지만, PLP가 보고하는 현행 상품 수는 sitemap 열거량보다 훨씬 크다. 또한 검색·성별·스토어별 노출의 중복과 비노출 상품을 객관적으로 모두 제거/포함했는지 검증할 전역 카탈로그 계약이 공개되어 있지 않다. 따라서 전수성은 주장하지 않는다.

## 확인된 공개 데이터 경로

- robots 정책: https://www.musinsa.com/robots.txt
- sitemap index: https://www.musinsa.com/sitemap-musinsa-index.xml
- 상품 sitemap: `sitemap-goods-1.xml` ~ `sitemap-goods-10.xml`
- 카테고리 PLP: `https://www.musinsa.com/category/{categoryCode}`
- 상품 상세: `https://goods-detail.musinsa.com/api2/goods/{productId}`
- 구조화 실측: `https://goods-detail.musinsa.com/api2/goods/{productId}/actual-size`
- 판매 옵션: `https://goods-detail.musinsa.com/api2/goods/{productId}/options`

로그인, CAPTCHA 우회, credential 사용, 접근통제 우회, IP/identity rotation은 수행하지 않았다.

## 수집 범위

| 지표 | 값 |
|---|---:|
| sitemap 고유 상품 ID | 9621 |
| 확인한 의류 세부 카테고리 | 45 |
| PLP에서 발견한 고유 상품 | 2689 |
| 상세 수집 대상(중복 제거) | 358 |
| 상세 성공 | 358 |
| 상세 실패 | 0 |
| 구조화 실측 보유 상품 | 305 |
| 보수적으로 파싱한 HTML 실측 상품 | 0 |
| 판매 옵션만 확인된 상품 | 42 |
| 사이즈 데이터 미확인 상품 | 11 |
| 원본 측정값 | 4594 |
| exact canonical 매핑 | 4069 |
| 미매핑/제외 측정값 | 525 |
| 원본 0값(추천용 canonical 제외) | 525 |

### 루트 카테고리 PLP 보고 수

각 수치는 실행 시점 PLP가 반환한 값이며 sitemap 수와 동일한 개념이 아니다.

| 코드 | 공식 카테고리 | PLP 보고 수 |
|---|---|---:|
| 001 | 상의 | 349550 |
| 002 | 아우터 | 110362 |
| 003 | 바지 | 137201 |
| 100 | 원피스/스커트 | 42059 |

## 정확성 처리

- actual-size의 각 `sizes[].items[]` 값을 원본 측정 레코드로 보존했다.
- raw item에는 unit 필드가 없지만 공식 actual-size UI 표가 cm 문맥을 제공하므로 `raw_unit=cm`으로 기록했다. 숫자는 변환하지 않았다.
- canonical mapping은 exact raw-name 사전에만 적용했다. circumference를 flat width로 나누는 변환은 하지 않았다.
- 공식 응답의 0은 원본에 남겼지만 실제 의류 치수인지 placeholder인지 확정할 수 없어 canonical 추천 필드에서는 제외했다.
- `size_available`은 비워 두었다. options의 `activated`를 실시간 재고와 동일하다고 해석하지 않았다.
- BODY_MEASUREMENT는 수집하지 않았고 GARMENT_MEASUREMENT만 정규화했다.
- 이미지 사이즈표 OCR은 수행하지 않았다.

## 미확인 범위

- PLP 전체 pagination은 재실행 소스의 `--mode full`에서 지원하지만, 이번 기본 실행은 세부 카테고리당 8개 상세 수집으로 제한했다.
- sitemap에 없는 현행 PLP 노출 상품 전체와 검색/프로모션 전용 상품의 완전한 합집합은 검증하지 못했다.
- options 응답의 활성화 플래그는 실시간 사이즈별 재고 여부로 사용하지 않았다.
- 명확한 HTML 표가 아니거나 이미지에만 있는 사이즈표는 canonical 데이터에 넣지 않았다.

## 실패와 검증

- Failures 행: 0
- Validation 결과: 전 항목 PASS

Failures는 HTTP/파싱/endpoint 실패만 기록한다. 공식 응답이 정상이나 실측 데이터가 null/empty인 경우는 데이터 미제공 상태로 분리하며 네트워크 실패로 세지 않는다.
