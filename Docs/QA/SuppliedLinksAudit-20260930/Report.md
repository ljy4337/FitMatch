# 사용자 제공 링크 실데이터 감사 — 2026-09-30

## 결론

이번 실행에서 새로 확정한 앱 crash, 잘못된 상품/선택 색상 전송, 파서 이후 원본 실측 손실은 없음. 신규 186링크 전체의 DB 등록·비교 성공을 증명한 감사는 아니다. production 코드와 DB를 변경하지 않았다.

## 기준과 방법

- connectDB / HEAD db190a9c677da0181c4de2910c979a82ca59c1b8 + 기존 dirty 유지.
- AGENTS, Behavior Map FLOW-PRODUCT-LOAD/CLOSET-LINK/COMPARE 및 provider contracts, MeasurementPolicy, 최신 Handoff 확인.
- Superpowers using-superpowers / systematic-debugging 적용. Supabase skill에 따라 연결 project 식별 후 읽기 전용 조회.
- `urls.txt`: 중복 URL 제거 186개. UNIQLO 148 / MUSINSA 31 / ZARA 7. E491320 suffix, 명시 색상·가격그룹 및 공유 query 유지. 상품 수가 아니라 서로 다른 입력 URL 수.
- 기존 `FitMatchReleaseLiveProductAuditTests`가 실제 `ProductURLParserService`와 실제 네트워크를 순차 실행. 신규 ingestion/Closet/Comparison mutation 없음.
- `results.json`: 상품/실측/전송 payload 요약과 각 실패를 저장. 이 파일은 전체 HTTP body 아카이브가 아니다.

## 실제 수집 결과

| 쇼핑몰 | 실측 수집 | 부분 결과 | 실패 |
|---|---:|---:|---:|
| UNIQLO | 147 | 1 | 0 |
| MUSINSA | 30 | 0 | 1 |
| ZARA | 7 | 0 | 0 |
| 합계 | 184 | 1 | 1 |

- 총 1,138개 사이즈 / 파서 원본 실측 5,360행 / observation 실측 5,360행.
- 수집된 행의 label/value/unit 및 사이즈·실측 identity 중복, 명시 UNIQLO 색상과 ZARA v1 보존 1,329개 대조: PASS. `transport-verification.json` 참조.
- 이는 API가 제공한 모든 원문 행 수와의 전체 대조가 아니라 파서 출력→전송 데이터 대조다.
- UNIQLO E487688 color31은 variant31, E482522 가격그룹01/color63은 variant63 보존.
- ZARA 06786003: internal549829596 / selected549838589 / 4사이즈. 00774307: internal556140702 / selected556169729 / 7사이즈. 서로 다른 product/variant 값을 그대로 전송.

## 예외와 반증

### E486627 — 공급자 상품 상태/사이즈표 없음

공식 details HTTP200의 body는 `status=nok`, error.code25, embedded httpStatusCode404, `Product states or representative L2 states is invalid.`. size chart HTTP200은 result에 productId/imageUrl만 있고 sizeChart 없음. 원문 `E486627-details.json`, `E486627-size-chart.json` 저장.

파서는 PARTIAL_RECOVERY_REQUIRED/사이즈0으로 반환했다. ShoppingProductViewModel의 partial catch는 parserNotice를 표시하고 false 반환한다. 원문 실측을 앱이 잃었다는 증거 없음. 상품 상태가 바뀐 시간·이유는 확인 불가. 별도 사용자 UI 실행은 NOT RUN.

### 손상된 MUSINSA 공유 URL — 입력 오류

`rz4cmoa784%87...p00774307.html?v1=556169729...`는 ZARA 주소 조각이 붙어 있다. 주어진 문자열 그대로 실행했고 FAILED. 임의로 토큰을 추측해 다른 상품으로 바꾸지 않았다. 의도한 정상 무신사 주소는 확인 불가.

기존 live suite는 모든 입력이 성공해야 한다는 assertion 때문에 **FAIL / exit65**. 실패 입력을 지우거나 assertion을 낮춰 PASS로 재보고하지 않음. 다른184개 측정수집 성공, 1개 부분결과와 구분.

### 실제 느린 경로

MUSINSA6372903 37.6초 / 6372893 42.1초. 6372893 actual-size 직접 확인 HTTP200/data=null. 후속 HTML/image 복구가 존재하는 production 경로와 일치한다. 자라 일부 11~17초. 상품 수집 wall-clock이며 DB/최종 결과 시간을 포함하지 않음. 이번에 OCR 후보·timeout·복구를 변경하지 않았다. 사진별 비용 분해와 물리기기 시간은 미측정.

## DB 읽기 전용 대조

- 현재 연결 project hnkplvyegonlhumlejst / FitMatch ACTIVE_HEALTHY 확인. Production 안전기준으로 읽기만 수행.
- `resolve_measurement`, `normalize_measurement_label`, `product_comparison_group` 실제 정의 확인. group 함수는 SELECT만 수행함을 확인 후 기존 product에만 호출.
- active verified aliases223행과 active verified mappings 조회·보관. `db-aliases.json`, `db-mappings.json`.
- 이번 입력 중 기존 DB product23건 group 조회: 4건(E488397/E488630/E491294/E491297) UNMAPPED. 나머지는 `db-existing-product-groups.json`. 새 API응답 ingestion 결과가 아니라 기존 저장상품 기준이다.
- UNMAPPED는 사용자 그룹 선택으로 이어지는 현 정책이므로 결함으로 세지 않음.
- MUSINSA6372893/6372903의 `actual_size` 가슴둘레/팔둘레는 active verified alias에서 미발견. raw 전송은 보존됨. 단면 alias로 임의 연결하지 않음. 이 두 항목의 최종 DB 비교 승인 여부까지 실행하지 않았으므로 전체 비교불가 또는 새 결함으로 단정하지 않음.

## 고정 응답 / 회귀 실행

신규 `SuppliedLinkRawPreservationAuditTests`:
- 기존 `CurrentUniqloCatalogInputs.json` 중 제공 링크와 겹치는113상품 재생.
- 정확한 양수 숫자 cm 원문3,388행의 code/label/value가 production parser에 보존되는지 검사.
- 원본 표시 row 개수와 observation row 개수, rawCode/rawLabel/value/rawValueText 전송 검사.
- 범위 문자열·0·단위불명은 이 3,388행 수치대조 범위가 아님. canonical 분류를 검사하는 테스트가 아니며 transport용 최소 product scaffold 사용.

함께 실행: UniqloParserConcurrencyTests, MusinsaParserConcurrencyTests, ZARAParserConcurrencyTests, ClosetRegistrationDuplicateRawTests, FrozenReleaseHistoryAuditTests.

결과: **24tests / 34parameter runs PASS, 0FAIL, 0skip, exit0**. Debug 앱/테스트 build 및 실행 PASS. 과거 전체878PASS를 이번 실행으로 재보고하지 않음.

실행 명령:

```bash
bash /tmp/run-fitmatch-supplied-live.sh
# exit65, /tmp/FitMatchSuppliedLinksLive20260930.xcresult
bash /tmp/run-fitmatch-supplied-offline.sh
# exit0, /tmp/FitMatchSuppliedLinksOffline20260930.xcresult
```

두 script는 `xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO`에 명시 suite filter 및 resultBundlePath를 사용한다. 환경 TEST_RUNNER_FITMATCH_RELEASE_URLS는 본 폴더 urls.txt, live OUTPUT은 results.json. 재현용 scripts도 본 폴더에 복사 보관.

## 검증 경계 / 남은 작업

- 이번186링크의 실제 DB 저장→후보→begin/complete→History: NOT RUN. 이전 승인3옷 테스트를 확대 쓰기 권한으로 재사용하지 않음.
- comparison engine/History는 기존 실제 완료fixture 회귀를 재실행했으며 신규186링크의 최종 비교가 아님.
- 물리iPhone/전체UI/서로다른기기 E2E: NOT RUN.
- DB write/migration/deploy/commit/push: 없음.
- 기존 History raw 없는 재등록/재비교 제한은 이번에 해결하지 않음.
- 위 정상수집184개를 앱 전체 정상 또는 출시 보증으로 확대하지 않는다.
