# FitMatch UNIQLO KR collection report

Collection window: 2026-08-12T22:54:33.246Z – 2026-08-12T22:55:41.844Z

## Scope and completeness

- Primary population: all 1,855 product URLs present in the official KR product sitemap at collection time.
- The sitemap URL set and every discovered URL were traversed. This verifies completion against that observed sitemap population only.
- Absolute completeness of every product that may exist in internal systems or outside the public sitemap cannot be proven; this dataset therefore does **not** claim an unconditional full-store census.
- Garment measurements came only from the official `sizeChart` array. `bodyMeasurements` and body-size fields found inside a garment chart were isolated in `BodyMeasurements`.

## Discovery

- 발견 상품 URL: 1,855
- 중복 제거 후 unique URL: 1,855
- 상세 성공 후 unique product ID: 1,689
- 탐색한 원본 category path: 491
- pagination/cursor 완주 여부: 공식 sitemap `</urlset>` 끝까지 파싱 완료; PLP 무한스크롤은 모집단 증명에 사용하지 않음

## Product Collection

- 성공: 1,689
- 실패: 166
- 성공률: 91.05%
- 동일상품 HTML fallback 복구: 0

## Size Data

- 제품 실측 확보 unique 상품: 1,560
- 미확보 상품: 129
- 확보율: 92.36%

## Measurements

- raw garment measurement: 41,644
- canonical mapped: 26,555
- unmapped / intentionally not normalized: 15,089
- mapping rate: 63.77%
- 별도 격리한 body measurement: 20,124

Official inch representations remain preserved in the raw API cache but are not duplicated as separate Excel rows when an official cm counterpart exists; no inch value was arithmetically reconverted. Circumference values were not mapped to flat-width keys. Missing values were never replaced with zero.

## Validation

- 남은 중복: 0
- 제거한 exact-key 중복: 1,197
- orphan record: 0
- conflicting measurement group: 3
- anomaly: 0
- validation errors: 0
- 원본 샘플 대조: 9/9 PASS
- Excel 재오픈 및 전 시트 상단 렌더 검증: PASS
- formula error scan: 0

Conflicting source values, if any, remain in `RawMeasurements`; their canonical key/value is blanked and the conflict group is recorded rather than silently corrected.

## Output

- Excel 파일: /workspace/scratch/6154e486a5ac/outputs/uniqlo_full_catalog/FitMatch_Uniqlo_Full_Catalog.xlsx
- 파일 크기: 7,322,171 bytes (6.98 MiB)
- Products rows: 4,664
- Sizes rows: 26,972
- RawMeasurements rows: 41,644
- Failures rows: 295

## Public source entry points

- https://www.uniqlo.com/robots.txt
- https://www.uniqlo.com/kr/sitemap_kr-ko.xml
- https://www.uniqlo.com/kr/sitemap_kr-ko_l1l2_hreflang.xml
- https://www.uniqlo.com/kr/sitemap_kr-ko_l3_hreflang.xml
