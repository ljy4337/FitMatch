# FitMatch 최신 누적 인수인계서

## 2026-08-16 DB·앱 207건 판정 적용

- 사용자 명시 승인으로 운영 DB에 074를 직접 실행했고, 이어 최신 production XCTest 첨부 5,026건 전체를 QA와 `product_classification_decisions` 양쪽에 `swift-production-2026-08-16-v3`로 직접 동기화했다. 최초 전 필드 대조에서 133건의 잔여 차이를 발견해 일부만 맞추는 방식을 중단하고 전수 결과를 canonical source로 사용했다.
- 최종 검증은 앱 첨부, DB decision, DB QA를 source/product/category/detail/family/length/confirmation 순으로 정렬하고 동일 NULL 표기 체크섬으로 비교했다. 세 집합 모두 5,026행, MD5 `d314b6d208ffed1d0d4282786e62ff94`, exact 5,026, mismatch 0, review_required 329다. 따라서 보유 corpus에서 앱↔DB 전 필드 동등성은 100%로 확정했다.
- 사용자가 072·073을 실행했다. DB QA↔canonical decision 자체는 5,026/5,026이었지만 최신 앱 첨부 결과와 확인 여부 총계가 DB 327/앱 329로 달라 추가 대조했다. 레이어드 세트 3개(5979739, 6247131, 6361801)는 앱처럼 확인 필요가 정답이고, 명시적 `METAL HALF T-SHIRT` 6833691은 앱의 `tops/short_sleeve/tshirt/short_sleeve` 자동확정이 정답이다.
- 위 4건을 QA와 product decision 양쪽에 맞추고 5,026 DB 내부 postcondition을 검사하는 `supabase/sql/074_post_parity_four_case_alignment.sql`을 생성했다. 사용자가 실행한 뒤 review_required=329인지 확인해야 최종 앱↔DB 완료다.
- 후속으로 `supabase/sql/073_product_classification_decisions_runtime.sql`을 추가했다. 072 적용을 선행조건으로 검사한 뒤 검증된 5,026개 상품 decision을 `fitmatch_catalog.product_classification_decisions`에 승격하고, 상품 ID뿐 아니라 상품명·공식 경로 fingerprint까지 동일할 때만 canonical 결과를 반환하는 service-role 전용 함수를 생성한다.
- 새 함수는 현재 5,026건을 전 필드로 다시 조회해 5,026/5,026이 아니면 transaction 전체를 예외로 중단한다. 신상품 또는 이름·경로 변경 상품은 오래된 규칙 결과를 자동 확정하지 않고 suggestion만 포함한 `requires_user_confirmation=true`로 반환한다.
- 운영 DB에는 072와 073 모두 아직 실행하지 않았다. 사용자가 순서대로 실행한 뒤 마지막 집계와 `E492123` 결과를 받아야 DB 100% 완료로 확정할 수 있다.
- 사용자 승인 후 `ParsedClosetClassification`의 일반 규칙을 보정했다. 셔츠·블라우스 family, 상의 경로 BRA-IN/브라탑, 명시적 T셔츠와 아우터 단어 충돌, `sweat shirt`, 9부 상의 길이, 속옷·홈웨어 길이 오염, 복합 레이어드 세트를 수정했으며 상품 ID별 예외는 추가하지 않았다.
- 독립 판정 207건을 번들 fixture와 XCTest로 고정했다. production parser와 resolver를 실제 실행해 207/207의 대분류·세부분류·family·길이·확인 여부가 모두 일치했고 실패 0이었다. 전체 5,026건도 입력/출력 5,026, 사용자 확인 329, invalid 0, 실패 0으로 다시 통과했다. xcresult는 `/tmp/FitMatchDBLogicAdjudication-After2.xcresult`, `/tmp/FitMatchDBLogicGlobal-20260816.xcresult`다.
- DB QA release `568c3153-a45e-4d4e-b9a7-59c2179733be`의 207건을 같은 정답으로 맞추는 idempotent transaction SQL을 `supabase/sql/072_db_app_adjudication_qa_alignment.sql`로 생성했다. 5,026행/207개 target 사전조건과 207개 postcondition을 포함한다. 운영 DB에는 아직 실행하지 않았다.
- 원격 읽기 전용 점검에서 `fitmatch_taxonomy.evaluate_runtime_classification`과 규칙 세트 `app-hardcoded-parity-2026-08-06-v1`(활성 84개)을 확인했다. 이 별도 DB 실행 함수는 최신 Swift 분류기보다 오래되어 현재 5,026 QA와 런타임 동등하지 않다. QA 정답 데이터 정렬과 DB 실행 함수 동등화를 같은 완료로 보고하면 안 된다.
- `E492123 데님릴렉스셔츠재킷`의 최종 정답은 사용자 확정대로 `tops / shirt / shirt / long_sleeve / 자동확정`이다.

## 2026-08-15 DB·앱 분류 신뢰성 감사

- Supabase와 앱 production 코드는 수정하지 않고 읽기 전용으로 비교했다. 기존 QA 5,026개와 오늘 최신 배치 중 QA에 없던 346개를 합쳐 총 5,372개 고유 상품을 검사했다.
- 현재 main 5,026건 XCTest는 5,026 output, 자동분류 4,703, 확인 필요 323, invalid 0으로 통과했다. DB QA 기대값과 대분류·세부분류·family·길이·확인 여부를 상품별 비교한 결과 4,819개 완전 일치, 207개 불일치, 동등성 95.88%였다.
- 공식 상품 의미 근거가 확정된 challenge 231개에서 앱은 220개, DB는 91개가 근거와 일치했다. 앱만 맞음 129, DB만 맞음 0, 양쪽 모두 맞음 91, 양쪽 모두 잔여 오류 11이다. 전체 신뢰도 우세 판정은 현재 앱 로직이다.
- 오늘 신규 346개는 무신사 148/유니클로 198이며 앱 자동분류 280, 확인 필요 66이다. raw 앱 분류기는 DB rejected 양말 88개를 속옷으로 분류하지만 실제 비교 경로에서는 내장 canonical eligibility가 차단한다. DB는 제외·버전 정책이 강하고 앱은 상품명 구조·세부분류가 강하다.
- 공식 경로·명시적 구조로 확정한 잔여 오류를 보수적으로 102/5,372로 잡은 제품 분류 신뢰도는 98.10%다. 사용자가 정한 90% 분류 기준은 통과하지만 앱 전체 출시 승인은 privacy/support URL, 전체 회귀, 실제 iPhone 동선, archive/TestFlight 게이트와 별개다.
- 근거는 `Docs/TestEvidence/DBLogicReliability-20260815/`의 `report.md`, `summary.json`, 207개 mismatch CSV, 신규 346개 JSON과 `/tmp/FitMatchDBLogicReliability-20260815.xcresult`, `/tmp/FitMatchCurrentBatchReliability-20260815.xcresult`다. 분류/DB 수정은 사용자 승인 전 수행하지 않는다.
- 207개 불일치를 상품명·공식 경로·FitMatch 비교 정책으로 전수 판정했다. 앱 정답 153, DB 정답 16, 양쪽 수정 38, 실물 확인 필요 0이다. `E492123 데님릴렉스셔츠재킷`은 사용자 결정으로 `상의 / 셔츠 / shirt family / 긴팔`로 확정했다. 정답 목표값과 근거는 `db-app-5026-adjudication.csv`에 있으며 아직 앱·DB에는 적용하지 않았다.

## 2026-08-15 커밋 대상 생성 SQL 정리

- 재생성 가능한 최신 누적/유니클로/무신사 스냅샷 SQL 출력 3개를 `../FitMatchArchive/Docs/GeneratedSQL/`로 이동하고 `.gitignore`에 패턴을 추가했다.
- SQL 생성기, 운영 복구·매핑 SQL, DB 최적화 계획, 보고서, 앱 코드와 테스트가 직접 읽는 `CurrentUniqloCatalogInputs.json`은 커밋 대상에 유지했다.
- 코드와 테스트 동작은 변경하지 않았으며 테스트는 실행하지 않았다.

## 2026-08-15 최신 누적 상품 스냅샷 운영 DB 실행 결과

- 사용자가 `FitMatch_LatestCumulativeSnapshots_20260815.sql.txt`를 Supabase SQL Editor에서 실행했다.
- 현재 무신사 스냅샷은 total/distinct 384/384, mapping gaps 0, conditional 342, excluded_review 28, unclassified 14다. 신규 `6842888`은 conditional이며 매핑 연결됐다.
- 현재 유니클로 스냅샷은 total/distinct 1,156/1,156, mapping gaps 5, conditional 326, excluded_review 221, unclassified 0이다. 나머지 609개는 comparable이다.
- 로컬 상세 반영 대상 53건은 유니클로 52 + 무신사 1이며 중복 0, 매핑 미연결 0이다. 유니클로 신규 52건은 conditional 27, excluded_review 25다.
- 유니클로 mapping gaps 5는 직전 운영 상태의 의도적 미연결 액세서리 5건과 수가 같지만, 최종 종료 전에 현재 5개 ID와 상태를 조회해 동일한지 확인해야 한다.

## 2026-08-15 최신 유니클로·무신사 누적 스냅샷 SQL 생성

- 바탕화면 최신 결과를 기반으로 `Docs/FitMatch_LatestCumulativeSnapshots_20260815.sql.txt`와 재생성기 `scripts/generate-latest-cumulative-snapshots-sql.mjs`를 추가했다. 운영 DB에는 실행하지 않았다.
- 유니클로 `20260815-181456`은 발견 1,157개 중 상세 실패 `E479751`을 제외한 1,156개를 `partial` 스냅샷으로 만든다. 로컬 상세 52개를 삽입하고 나머지 1,104개는 DB 전체 성공/부분성공 이력에서 상품별 최신 행을 복원한다. 최신 실행 한 건에만 의존하지 않아 재등장 상품을 보존한다.
- 무신사 `20260815-120901`은 기존 누적 383개를 유지하고 `6842888` 1개를 추가해 384개 성공 스냅샷을 만든다. 98만 건 전체 인덱스는 적재하지 않는다.
- SQL은 advisory transaction lock, 활성 릴리스/기존 행 수 preflight, 배치 범위 재실행, 총행·고유 ID·로컬 신규 수 검증을 포함한다. 하나라도 맞지 않으면 두 공급사 변경 전체가 롤백된다.
- 생성기 입력 검증 결과 유니클로 discovered 1,157/stored 1,156/local payload 52, 무신사 total 384/new 1이었다. SQL은 아직 Supabase에서 실행·검증되지 않았다.

## 2026-08-15 무신사 전체 인덱스·선택 상세 배치 전환

- `scripts/run-musinsa-full-catalog.py`의 기본 실행을 전상품 상세 수집에서 전체 상품 인덱스 탐색(`--phase discover`)으로 변경했다. 상품 상세·실측·옵션은 `--phase collect`와 명시적인 `--product-id` 또는 `--max-products`가 있을 때만 수집한다.
- 카테고리 한 건의 파싱·네트워크 실패가 전체 탐색을 중단하지 않고 해당 카테고리만 현재 실행에서 보류한 뒤 다음 카테고리를 계속 처리한다. 보류 카테고리는 다음 실행 시작 시 재시도된다.
- 상세 수집은 기본 500개 단위로만 메모리에 올려 기존처럼 수십만 개 Future를 한꺼번에 생성하지 않는다.
- 요약에 `index_complete`와 `detail_collection_complete`를 분리했다. 전체 상품 인덱스 완료가 배치 성공 기준이며, 모든 상품 상세 선행 수집은 완료 조건이 아니다.
- 기존 바탕화면 SQLite 약 62만 건은 삭제하지 않고 그대로 이어 쓸 수 있다. 다만 변경 전 이미 실행 중인 Python 프로세스에는 새 코드가 적용되지 않으므로 Control-C 종료 후 바탕화면 command를 다시 실행해야 한다.
- Python 컴파일과 전용 단위 테스트 3건이 통과했다. 새 테스트는 첫 카테고리 파싱 실패 후 다음 카테고리가 정상 완료되는 것을 검증한다. 실제 네트워크 전체 737개 재실행은 수행하지 않았다.

## 2026-08-15 카테고리 DB 적재·앱스토어 출시 진단 최신 상태

### Supabase 상품 스냅샷과 매핑

- 사용자가 Supabase SQL Editor에서 제공된 SQL을 직접 실행하는 방식으로 진행했다. Codex가 운영 DB를 직접 변경하지 않았다.
- 활성 카테고리 릴리스 기반 `fitmatch_catalog.product_collection_runs`, `source_product_snapshots`, `source_category_mappings` 연결을 사용한다. `current_source_products`는 공급사별 최신 `succeeded/partial` 실행 전체를 보여주므로, 신규 행만 별도 성공 실행으로 만들면 기존 상품이 최신 조회에서 사라진다는 점을 반드시 지킨다.
- 유니클로 증분 배치 `20260815-111623`은 현재 발견 1,039, 신규 상세 226/226 성공, 재시도 0, 이전 목록 미발견 67이었다. DB 실행 ID는 `6618738d-d0c5-4a7a-b630-848119c9bc9b`이며 최신 스냅샷 1,039개가 저장됐다.
- 최초 유니클로 SQL이 기존 813개를 carry-forward하면서 `source_mapping_identity`를 null로 복사한 결함이 있었고 복구 SQL로 기존 링크를 복원했다. 원본 생성기도 이후 기존 링크를 보존하도록 수정했다.
- 신규 유니클로 `E485389`의 leaf `150446`은 기존 KIDS 복서브리프 `58650`과 같은 `rejected / not_fitmatch_comparable` 정책으로 활성 릴리스에 명시적 거부 매핑을 추가했다. 상품은 `excluded_review`이며 매핑 identity가 연결됐다.
- 유니클로 최종 운영 의도는 1,039개 중 실제 매핑 누락 0이다. 스카프·장갑 5개는 `excluded_review` 상태의 의도적 미연결이며 오류로 세지 않는다.
- 무신사 증분 배치 `20260815-115051`은 상위 카테고리 4개 첫 페이지에서 188개를 발견했고, 기존 200과 중복 5, 신규 183/183 상세·실측·옵션 수집 성공, 재시도 0이었다. 이 탐색은 전체 무신사 카탈로그가 아니므로 미발견 195개를 판매 종료 또는 삭제로 처리하지 않는다.
- 무신사는 baseline 200개를 유지하고 신규 183개를 더한 누적 스냅샷 383개를 실행 ID `a141f6bf-5218-4c87-9ce2-e77557472f37`로 저장했다.
- baseline 200개 중 category code가 없던 legacy path 18종/80개를 의미가 같은 활성 confirmed mapping에 alias로 연결했다. 최종 무신사 결과는 total 383, linked 383, mapping gaps 0, conditional 341, excluded_review 28, unclassified 14, legacy alias linked 80이다.
- 무신사 unclassified 14개는 링크 실패가 아니라 연결된 `review_required` 정책 결과다. baseline 8, incremental 6이며 상품 분류기 또는 사용자 확인 대상이다.
- 현재 상품 스냅샷은 유니클로 1,039 + 무신사 383 = 1,422개다. DB는 카테고리 후보·정책·이력을 제공하지만 앱 런타임은 아직 DB를 조회하지 않는다.

관련 실행 SQL·생성기:

- `Docs/FitMatch_UniqloCurrentSnapshot_20260815_111623.sql.txt`
- `Docs/FitMatch_UniqloSnapshot_RestoreMappingLinks_20260815.sql.txt`
- `Docs/FitMatch_AddUniqlo150446RejectedMapping_20260815.sql.txt`
- `Docs/FitMatch_MusinsaCumulativeSnapshot_20260815_115051.sql.txt`
- `Docs/FitMatch_LinkMusinsaBaseline80_20260815.sql.txt`
- `scripts/generate-uniqlo-current-snapshot-sql.mjs`
- `scripts/generate-musinsa-cumulative-snapshot-sql.mjs`

### 배치 인수 규칙

- 이후 배치 결과를 받을 때 `summary.json`, `discovered_products.csv`, `new_product_inputs.json`, `pending_retry.csv`를 우선 확인한다.
- 신규 수, 상세 endpoint 성공, 중복 ID, retry, category mapping gap을 검증한다. 탐색이 전체 카탈로그임이 증명되지 않으면 미발견 상품을 삭제하거나 inactive로 확정하지 않는다.
- `current_source_products`에 노출할 성공 실행은 기존 유지 상품과 신규 상품이 모두 포함된 완전한 누적 스냅샷이어야 한다.
- 신규 category code는 기존 의미 동등 mapping을 확인한다. 확실하지 않으면 잘못 confirmed로 만들지 말고 `review_required` 또는 `excluded_review`로 남긴다.

### DB와 앱 통합 상태

- 현재 앱은 `ParsedClosetClassification`, canonical bundle, parser와 matcher의 로컬 규칙으로 동작한다. Supabase 카테고리·상품 스냅샷을 앱이 직접 조회하거나 DB procedure로 최종 분류하는 연결은 아직 없다.
- 권장 최종 흐름은 `상품 API 데이터 → DB category mapping/version 조회 → 기존 상품명·실측 classifier → category/detail/comparisonFamily/status 반환`이다.
- 상품명·실측 규칙 전체를 PL/pgSQL로 복제하면 Swift와 DB 규칙이 갈라질 위험이 크므로, 1차 출시 후 단일 앱 분류 서비스에 읽기 전용 DB lookup, 버전 고정, 캐시, timeout, 오프라인 embedded fallback을 붙이는 방향이 우선이다.

### 1차 App Store 출시 진단

- 진단 기준은 로컬 `main`, HEAD `9264814ea2a8c535ba82de495a69ce75336f16d0`과 현재 미커밋 작업 트리다. 앱·테스트·문서 변경과 untracked 생성물이 많으므로 출시 전 정확한 source revision을 커밋·태그로 고정해야 한다.
- `FitMatch/Info.plist`의 `FitMatchPrivacyPolicyURL`, `FitMatchSupportURL`은 여전히 빈 문자열이다. 공개 HTTPS URL을 넣기 전에는 archive 감사와 App Store 제출 게이트를 통과할 수 없다.
- 로그인 진입은 `ContentView`에서 의도적으로 비활성화됐고 MY의 계정·로그아웃 UI도 비활성화됐다. 현재 1.0은 계정 없는 로컬 SwiftData 앱으로 출시할 수 있으며 로그인은 필수 기능이 아니다.
- iPhone 17 Pro/iOS 26.3 Simulator에서 현재 작업본 Debug build/install/launch가 성공했다. Bundle ID는 `com.ljy4337.fitmatch`, 홈 화면 접근성 요소까지 확인했다. UI 자동화 중 지원 화면 탭 이후 예상과 다른 등록 온보딩 화면으로 전환돼 전체 핵심 흐름 통과로 계산하지 않는다.
- XcodeBuildMCP 전체 test 호출은 300초 제한으로 결과를 받지 못했다. 이후 `-only-testing:FitMatchTests`로 실행했으며 362개를 발견했지만 테스트 프로세스가 조기 종료돼 실제 집계는 passed 6, failed 7, skipped 0이었다. 결과 번들은 `~/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-e60223af795a/result-bundles/test_sim_2026-08-15T03-33-38-128Z_pid47700_95ea5f21.xcresult`이다.
- 실패 7건 중 `LiveReleaseQA1200Tests/testSelectedTenCaseBatchOnPhysicalDevice`는 `FITMATCH_LIVE_QA_BATCH` 환경변수 없이 일반 suite에 포함돼 unwrap 실패했다. `FitPairCorpusXCTests/testUniqlo243OfficialMeasurementCorpus`는 expectation failure다. Current Uniqlo audit와 여러 대형 live/corpus test는 signal kill 또는 test host early exit이므로 제품 실패로 단정할 수 없지만 통과로도 계산할 수 없다.
- 따라서 현재 상태는 빌드 가능이나 자동 회귀 green이 아니며, 오늘 즉시 제출은 NO다. 이전 2026-08-06의 279 pass/0 fail 기록은 최신 P0 수정 이후 현재 작업본의 출시 증거를 대신하지 않는다.

### 출시 전략 결정

- 권고는 DB·로그인을 기다리지 않고 현재 로컬형 MVP를 안정화해 1.0을 먼저 출시하는 것이다. 이미 일정이 약 2주 지연됐으므로 1.0에 Supabase Auth·동기화까지 추가하는 범위 확대는 권하지 않는다.
- 1.0 전 필수: 테스트를 빠른 오프라인 회귀/전수 분류/라이브 네트워크로 분리, 병렬 대형 테스트로 인한 signal kill 제거, 실제 expectation failure 해결, 전체 핵심 회귀 실패 0, 공개 privacy/support URL 연결, 실제 iPhone 6개 핵심 동선, Distribution archive 감사, TestFlight 확인이다.
- 1.1에서 DB mapping lookup과 오프라인 fallback을 연결한다. 로그인·다기기 동기화가 실제 제품 요구로 확정될 때 1.2에서 Auth/RLS/소유권 정책/로컬 데이터 migration/충돌 해결/앱 내 계정 삭제/개인정보 문서와 App Privacy 갱신을 함께 제공한다.
- 계획 추정은 1.0 안정화·제출 준비 2~4일, DB 연동 포함 시 추가 1~2주, DB+로그인+동기화 포함 시 추가 2~3주다. Apple 심사 시간은 별도다.

### 다음 테스트 순서

1. 빠른 오프라인 회귀: 외부 네트워크·환경변수 필요 테스트를 제외하고 병렬 비활성화, 실패 0을 만든다.
2. 상품 전수 분류: 기존 5,026 semantic oracle, 유니클로 현재 상품, 무신사 누적 상품을 공급사/fixture shard별 순차 실행한다. 위험 자동 확정·invalid·parser 계약 오류는 0이어야 하며 `review_required`는 별도 집계한다.
3. 실제 iPhone 수동 6개: 신규 설치/온보딩, 내 옷 직접 등록, 유니클로 링크 비교, 무신사 링크 비교, Share Sheet 왕복, 네트워크 단절·복구. 앱 재실행 후 옷장·기록 보존도 확인한다.
4. 공개 URL 입력 후 Release archive → `scripts/audit-app-store-archive.sh` → Validate App → TestFlight → 동일 핵심 동선 재확인 → 심사 제출 순으로 진행한다.

### 작업 안전 상태

- 이번 출시 진단과 인수인계 갱신에서 앱 소스·DB를 변경하지 않았다. `Docs/CodexSessionHandoff.md`만 갱신한다.
- 보호 파일 `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 보호 modifier call site에는 diff가 없다.
- commit, push, archive 업로드, App Store 제출은 수행하지 않았다.

## 2026-08-15 무신사 전체 공개 의류 수집 배치

- `scripts/run-musinsa-full-catalog.py`를 추가했다. canonical taxonomy에서 무신사 `confirmed` 및 `review_required` 의류 후보 카테고리 코드 737개를 구성하고, 각 공개 카테고리 응답이 제공하는 서명된 `nextPageUrl`을 마지막 페이지까지 따른다.
- 무신사 현재 목록 응답은 페이지당 60개였다. 서명 URL의 `size=60`을 임의로 `size=200`으로 바꾸면 HTTP 403이므로 고정 200 수집을 가정하지 않는다.
- 원본 HTML·API JSON·이미지는 영구 저장하지 않는다. 상품 메타데이터, 쇼핑몰 카테고리, 성별, 사이즈 실측, 옵션을 바탕화면 `무신사_전체의류_데이터/state.sqlite3`에 저장하고 gzip CSV 3개와 실패 CSV, `summary.json`을 생성한다.
- SQLite에 카테고리별 다음 서명 URL·페이지와 상품별 endpoint 완료 상태를 저장하므로 Control-C 중단 뒤 동일 배치를 다시 실행하면 이어서 수행한다. lock 파일로 동시 중복 실행을 차단한다.
- 실제 소량 검증에서 카테고리 `001001` 1페이지 60개 발견, 상품 1개 상세·실측·옵션 완료, 재실행 시 다음 상품 1개 완료로 58개가 남는 것을 확인했다. 2상품 기준 실측 20행, API 실패 0이며 gzip CSV를 실제 해제해 헤더·행을 확인했다.
- 바탕화면에 `무신사_전체의류_수집.command`를 생성했다. `caffeinate -i`로 실행 중 시스템 유휴 잠자기를 방지한다. 전체 배치는 아직 시작하지 않았다.

## 2026-08-15 무신사 증분 카탈로그 배치

- `scripts/run-musinsa-incremental-catalog.py`를 추가했다. 무신사 공개 카테고리에서 현재 노출 상품 ID를 찾고 누적 state와 비교한 뒤, 신규 ID에만 공식 상품 상세·실측·옵션 API를 요청한다.
- 결과는 `summary.json`, `new_products.csv`, `missing_product_ids.csv`, `pending_retry.csv`로 확인한다. 현재 카탈로그에서 사라진 상품은 검토 목록에만 기록하며 state에서 자동 삭제하지 않는다. 실패한 신규 상품도 state에 저장하지 않아 다음 실행에서 재시도된다.
- 공용 corpus collector의 Musinsa `--discovery-only`가 상세 API를 호출하지 않고 탐색 요약과 요청 지표를 저장하도록 수정했다. dry-run 상세 요청 예상치도 0으로 맞췄다.
- Python 컴파일, 과거 Musinsa checkpoint 기반 신규/누락 오프라인 비교, 실제 상품 994588의 상세·실측·옵션 HTTP 200과 8개 사이즈 행을 확인했다. 전용 단위 테스트 2건은 통과했다.
- 기존 category corpus 전체 단위 테스트 38건 중 29건 통과, 7건 skip, 2건은 아카이브로 이동된 `Docs/Research/CategoryCorpus-live-medium` 원본 fixture 부재로 오류였다. 이번 변경 로직 실패는 아니다.
- 실제 전체 무신사 증분 배치는 아직 실행하지 않았다. 첫 실행은 기본 baseline의 무신사 200개를 기준으로 현재 노출 상품을 신규 수집하므로 요청량과 실행 시간이 클 수 있다.

## 2026-08-14 상세 화면 실기기 성능 진단 로그

- Simulator를 사용하지 않고 실기기에서 내 옷 상세 및 비교 결과 상세 진입 버벅임을 구간별로 확인하도록 `[DetailPerformance]` 로그를 추가했다.
- 화면 생성 기준 `on_appear`, 다음 main run loop, 250ms 안정화까지 elapsed_ms와 SwiftData 조회 개수, 상품 사이즈·실측 사용·제외 개수를 기록한다.
- 상세 화면의 상품·기준 옷 썸네일에 한해 메모리 캐시 적중, 다운로드 시간·바이트·HTTP 상태, 백그라운드 디코딩 시간·픽셀, 전체 준비 시간을 기록한다. 목록 썸네일에는 로그를 켜지 않아 출력 폭증을 막았다.
- 현재 코드 검토상 두 상세 화면 모두 진입 즉시 전체 UserFit/RecommendationHistory 정렬 Query를 수행하는 점이 우선 의심 대상이지만, 로그 증거 전에는 구조를 변경하지 않는다.

## 2026-08-14 유니클로 에어리즘 크루넥 T 분류 보정

- 상품 `E482522`(`AIRism코튼크루넥T`)는 유니클로 원본 경로가 `이너웨어 > 에어리즘 > 코튼`이어서 기존 canonical resolver가 실제 티셔츠 구조를 속옷으로 확정했고, 티셔츠 기준 옷과의 비교가 차단됐다.
- 유니클로 `innerwear`는 실제 속옷과 일반 티셔츠가 섞인 판매 진열 분류임을 실제 E482522 페이지 데이터로 확인했다. `AIRism` 단어 자체는 분류 근거에서 제외하고, 명시적 속옷명 → 명시적 티셔츠 구조명 → 모호한 이너웨어 순서로 판정한다.
- 이너웨어 경로여도 상품명에 `티셔츠`, `크루넥T`, `V넥T`, `T-shirt`가 명시되면 `상의 / 반팔`, `tshirt` family로 분류한다. 상품명에 긴팔 표기가 있으면 `상의 / 긴팔`을 유지한다.
- 브라·브리프·복서 등 명시적 속옷 판정은 이 예외보다 먼저 적용되므로 기존 속옷 상품은 영향을 받지 않는다.
- 저장소의 유니클로 AIRism 고유 사례 79개를 점검했다. 공식 경로 기준 속옷계열 48, 상의 20, 하의 7, 원피스 2, 아우터 1, 기타 1이며 AIRism은 어느 대분류도 뜻하지 않는 기능·소재 라인임을 규칙으로 고정했다.
- 이너웨어 경로의 모든 `...T`를 상의로 올리지 않는다. 코튼 라인이면서 T 구조가 명시된 상품만 상의로 구제하고, 일반·메쉬 AIRism 및 HEATTECH 베이스레이어는 이너웨어를 유지한다. 탱크탑·캐미솔·브라탑·복서·브리프·트렁크·속바지도 속옷을 유지한다.
- 5,026건 1차 전수 검사는 5,026 output, invalid 0, classified 4,698, 사용자 확인 328로 통과했다. 결과 의미 검토에서 이전 실행 결과의 `AIRism속바지(E482154) → bottoms/long_pants`를 발견했으며, 현재 production resolver의 명시적 속옷 우선 규칙과 전용 회귀 테스트로 `underwear/women_panty`를 고정했다.
- AIRism 속옷·상의·조거팬츠·원피스가 각각 `underwear/tops/bottoms/dresses`로 유지되는 대분류 회귀 검사를 추가했다.
- 반팔 및 긴팔 에어리즘 코튼 크루넥 T 회귀 기대값을 추가했고, Simulator용 앱·단위 테스트·UI 테스트 target 전체 `build-for-testing`이 성공했다. 이번 명령은 테스트 실행이 아니라 테스트 바이너리 컴파일 검증이다.

## 2026-08-14 유니클로 공유 URL 선택 색상 썸네일 보정

- 유니클로 공유 URL이 `/E487957-000/00?colorDisplayCode=08` 형태일 때 기존 resolver가 경로의 `-000`을 query의 `08`보다 먼저 읽어 기본색 썸네일을 선택하는 오류를 수정했다.
- 색상 선택 우선순위는 원본 공유 URL `colorDisplayCode` → 최종 redirect URL `colorDisplayCode` → 경로/HTML fallback → 기본 `00`으로 변경했다.
- `colorDisplayCode=08`이 있으면 API 색상 `008`, 이미지 색상 `08`로 정규화되는 회귀 테스트를 추가했다.
- 변경 코드는 Simulator용 앱·테스트 target 전체 컴파일을 통과했다. 두 차례 단일 필터 실행은 Swift Testing 식별자가 매칭되지 않아 `Executed 0 tests`였으므로 단위 테스트 실행 통과로 계산하지 않는다.

## 2026-08-14 iPhone 실기기 A200 시도와 자동화 인프라 차단

- iPhone 14 Pro(iOS 26.6)에서 실제 무신사·유니클로 URL을 사용하는 200개 사용자 여정 테스트를 시작했다. 테스트 저장은 `-fitmatchUITesting` 메모리 전용이라 실제 사용자 옷장과 기록은 변경하지 않았다.
- 최초 실행에서 11개 여정이 오류 없이 완료됐다. 12번 유니클로 코듀로이쇼트재킷은 앱이 무신사 코트를 `사용자 선택 확장 비교 · 공통 실측 4개` 후보로 정상 표시했으나, 자동화가 지정 상품명만 찾도록 고정돼 후보를 누르지 못했다.
- 자동화가 화면의 대체 실측 후보를 선택하고 `추천 결과 아님`도 정상 차단으로 인정하도록 보완했다. A200 메서드는 첫 assertion에서 중단하도록 바꿔 실패 뒤의 케이스를 PASS로 잘못 출력하지 않는다.
- 보완 후 두 번 재실행했지만 UI 테스트 러너가 각각 약 197초, 95초 후 Xcode IDE 연결을 잃고 code 74로 종료됐다. 두 결과는 앱 비교 실패가 아니라 실기기 자동화 인프라 실패이며 200건 통과로 계산하지 않는다.
- 현재 유효 결과는 11건 통과, 앱 비교 실패 확정 0, 하네스 오판정 1, runner 종료 2회다. 상세 보고서는 `Docs/PhysicalA200Report-20260814.md`다.
- 후속은 기기 연결을 새로 만든 뒤 20건 단위 독립 xcresult 배치로 분할하고, 완결된 배치만 합산해 200건을 판정한다.

## 2026-08-14 실기기 URL 사용자 여정 및 기준 옷 재등록 UX

- 비교할 옷이 없는 화면의 등록 CTA가 수동 등록으로 바로 이동하던 연결을 수정했다. 이제 `상품 링크로 불러오기`와 `직접 입력하기`를 먼저 선택하며, 등록 완료 후 진행 중인 비교로 돌아와 후보를 다시 계산한다.
- 연결된 iPhone 14 Pro에서 `-fitmatchUITesting` 메모리 전용 저장소를 사용해 실제 사용자 데이터와 분리된 실기기 테스트를 수행했다.
- 유니클로·무신사 기준 옷 2벌 URL 등록과 비교 상품 2건 직접 URL 입력: 1 test / pass / 0 failures, `/tmp/FitMatchPhysicalDirectURL-20260814-v2.xcresult`.
- 실제 무신사 하의·아우터 10개 직접 URL 비교: 10/10 사용자 여정 완료, 1 test / pass / 0 failures, `/tmp/FitMatchPhysicalA10-20260814.xcresult`.
- 유니클로 옷 URL 등록 → 비교 → 비교 기록이 있는 옷 삭제 → 동일 상품 비교 시 필요한 옷 부재 안내 → 등록 방법 선택 → URL 재등록 → 비교 후보 복구: 1 test / pass / 0 failures, `/tmp/FitMatchPhysicalDeleteRecovery-20260814-v2.xcresult`.
- 첫 삭제 자동화는 상세 화면에서 바로 삭제 버튼을 찾는 잘못된 테스트 경로로 실패했다. 실제 사용자 경로인 `상세 → 편집 → 삭제`로 수정해 재실행한 결과 통과했다.
- 첫 직접 URL 자동화는 현재 UI의 `비교할 옷 선택` 문구를 인식하지 못해 중단했다. 현재 문구와 등록 CTA를 인식하도록 테스트를 보완한 뒤 재실행해 통과했다.

## 2026-08-14 저장소 대용량 생성 자료 외부 아카이브

- 앱 코드, 앱 번들 데이터, 테스트 입력 fixture, 설계·정책 문서와 이 누적 인수인계서는 저장소에 유지했다.
- 생성된 연구 코퍼스, 원본 수집 체크포인트, 테스트 증빙과 날짜별 과거 handoff 약 4.0GB를 저장소의 형제 폴더 `../FitMatchArchive/Docs/`로 이동했다.
- 동일 계열 생성물이 다시 Git 변경 목록에 잡히지 않도록 `.gitignore`에 경로 패턴을 추가했다.
- 기존에 Git이 추적하던 아카이브 대상은 다음 커밋에서 삭제로 기록되며, 과거 커밋의 용량은 별도 히스토리 정리 전까지 유지된다.
- 코드와 Xcode 프로젝트 파일은 이 정리에서 수정하지 않았고 빌드·테스트는 실행하지 않았다.

## 2026-08-14 공유 상품 선택 색상 썸네일 보존

- 유니클로 공유 URL에서 해석한 `colorDisplayCode`와 상품 번호가 일치하는 색상별 이미지 URL을 우선 사용하도록 수정했다.
- 색상별 사이즈표 조회가 실패해 `000` 기본색으로 재시도되더라도 기본색 이미지가 공유 URL의 선택 색상 썸네일을 덮어쓰지 않도록 했다.
- 무신사 공유 URL에 `goodsNo`, `goods_no`, `productId`, `product_id` variant 식별자가 있으면 경로의 대표 상품 번호보다 우선하도록 수정했다. 최종 상품 API의 해당 variant 썸네일을 사용한다.
- 회귀 테스트 2건(`uniqloSelectedColorThumbnailIsNotReplacedByGenericSizeChartImage`, `musinsaURLResolverPrefersExplicitVariantProductID`)을 iPhone 17 Pro Simulator에서 실행했고 2 tests / pass / 0 failures였다. 결과: `/tmp/FitMatchColorThumbnailDerivedData/Logs/Test/Test-FitMatch-2026.08.14_12-25-12-+0900.xcresult`.
- 실제 쇼핑 앱이 공유 payload에 색상 또는 variant 정보를 포함하지 않는 경우에는 선택 상태를 복원할 수 없다. 실제 iPhone Share Sheet 검수는 남아 있다.

## 2026-08-14 기준 옷 부재 안내 및 반팔·긴팔 부분 비교 (빌드 미확인)

- `CompareFlowSheet`의 기준 옷 부재 화면을 빈 옷장, 필요한 성인/아동 의류 부재, 필요한 의류 카테고리 부재로 구분했다.
- 화면에 가져온 상품명과 FitMatch 분류, 현재 옷장의 카테고리별 보유 수량을 표시하고, 필요한 기준 옷을 직접 등록하는 CTA를 추가했다. 등록 화면은 가져온 상품 자체가 아니라 사용자가 보유한 기준 옷을 수동 등록하며 기준 옷 토글을 기본 ON으로 연다.
- 반팔↔긴팔 상의는 같은 garment family이고 어깨·가슴·총장 중 공통 실측이 2개 이상일 때만 사용자가 직접 선택하는 확장 비교를 허용한다. 자동 기준 옷 선택은 여전히 동일 길이를 우선하며 길이가 다른 상의를 자동 선택하지 않는다.
- 반팔↔긴팔 확장 비교에서는 `sleeveLength`를 비교·점수에서 제외하고, 결과 근거에 소매 구조 차이와 몸판 공통 실측만 사용했음을 기록한다.
- 긴바지↔반바지와 아우터 몸판 길이 차이는 핵심 구조 차이이므로 계속 차단한다.
- 관련 회귀 기대값을 수정했으나 사용자가 회사에서 Xcode 빌드와 실기기 화면을 확인하기로 했으므로 이번 세션에서는 빌드·테스트를 실행하지 않았다. 컴파일 및 실제 레이아웃은 미확인 상태다.

### 사용자 지정 테스트 명칭

- 사용자가 말하는 `A테스트`는 2026-08-14 수행한 2,000건 사용자 여정 QA 방식을 뜻한다.
- 실제 무신사·유니클로 상품으로 가상 옷장을 구성하고 기준 옷 ON/OFF, 자동 비교, 수동 선택, 정상 차단, 분류 오류, 비교 오류를 현재 production 파서·분류·비교 로직과 실제 FitMatch UI/UX 문구까지 함께 검증한다.
- 사용자가 `A테스트 N건 진행`이라고 요청하면 같은 형식으로 N건을 수행하고, 쇼핑몰 분류와 FitMatch 분류를 명확히 구분하며 실제 상품명·링크·옷장 구성·기준 옷 상태·표시 UI·내부 QA 판정을 기록한다.

### 안내 문구 전수 정리 후속 수정

- 반팔↔긴팔 부분 비교에서 `sleeveLengthMismatch` 제외 사유를 별도로 저장해 결과 화면에 `반팔과 긴팔은 소매 구조가 달라 제외했습니다.`라고 표시한다. 일반 `categoryPolicy` 사유와 구분한다.
- 결과 화면에서 다른 기준 옷이 없을 때 빈 옷장, 아동복 부재, 성인 의류 부재, 필요한 세부 종류 부재를 구분해 안내하고 현재 옷장 카테고리 수량을 표시한다.
- 구형 `ShoppingProductFormView`의 `비교 가능한 상품이 없습니다`, `정확도가 낮아질 수 있습니다`, `내 옷장에 추가` 문구를 기준 옷 등록·호환 실측 제외 중심 문구로 교체했다.
- 비교한 쇼핑 상품 저장 기능은 실제 구매 완료 상품을 바로 등록하는 정상 흐름 때문에 제거하지 않았다. 대신 결과와 등록 시트 전체를 `보유한 옷으로 등록`으로 바꾸고 `실제로 가지고 있는 상품인 경우에만`, `구매 후보는 등록하지 마세요`를 명시했다.
- 이번 후속 수정도 사용자가 회사에서 Xcode 빌드와 실기기 UI를 확인하기로 한 상태라 빌드·테스트는 실행하지 않았다.

- 최종 갱신: 2026-08-13 (Asia/Seoul)
- 저장소: `/Users/jinyoung/Documents/Projects/FitMatch/FitMatch`
- 브랜치: `리뉴얼_1`
- 기준 HEAD: `49834c7`

> 이 파일이 새 세션에서 읽을 단일 최신 누적 인수인계서다. 아래 과거 수치와 최신 상태가 충돌하면 `0. 현재 최신 상태`와 실제 코드를 우선한다. 날짜가 붙은 `CodexSessionHandoff-YYYYMMDD.md`는 당시 상세 기록으로만 보존한다.

## 0. 현재 최신 상태

- 커밋·푸시하지 않은 대규모 로컬 변경이 존재한다. 사용자 작업과 조사 자료를 임의로 초기화·삭제·정리하지 않는다.
- `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 보호된 modifier 호출부는 변경하지 않았다.
- Supabase 작업은 사용자가 재개하기 전까지 보류한다.
- 커밋·푸시·배포는 사용자의 명시적 요청이 있어야 한다.

### 현재 작업 컨텍스트 — 다음 실행 전 읽기

- 2026-08-13 카테고리 분류 정책 수정이 완료됐다. 최신 정책은 `20. 2026-08-13 카테고리 증거 우선순위 데이터 감사`가 우선이다.
- 공식 URL/API production 파서를 사용하는 비-UI Simulator XCTest 비교 감사는 실행·구조화 증거 생성까지 완료했다. 최신 권위값은 이 절의 `비교 자격 정리 후 최종 재실행`을 따른다.
- 테스트 목표:
  1. 유니클로·무신사 공식 숫자 실측 상품만 production 파서로 분석한다.
  2. 유니클로 기준옷 → 유니클로·무신사 비교상품, 무신사 기준옷 → 유니클로·무신사 비교상품 순으로 각각 독립된 메모리 상태에서 비교한다.
  3. 기준옷 등록 가능 여부, 자동/수동 비교 가능 여부, 추천 생성 여부, 비교 불가 사유와 UX 복구 경로를 기록한다.
- 기준옷·비교상품은 실제 사용자 SwiftData 옷장에 저장하지 않는다. `Product → UserFit → ComparisonProfileMatcher → RecommendationService` production 경로의 테스트 객체만 사용한다.
- `기타`·복합·공식 경로 모호 상품은 새 정책대로 자동 43개 taxonomy에 억지 배정하지 않는다. 사용자 카테고리 선택 필요 상태로 따로 기록한다.
- 비교 불가 사유 분류: 공식 실측 없음, 파싱 실패, 분류 모호, 성별/연령 보호, 구조 불일치, 길이 불일치, 공통 실측 부족, 같은 구조 기준옷 없음.
- 비교 불가 UX는 실제 화면 실행으로 주장하지 않는다. 이번 범위에서는 ViewModel/View 분기의 안내 상태와 다음 행동(분류 선택, 기준옷 직접 선택, 유사 의류 수동 비교, 내 옷장 추가, 재시도)을 코드 기준으로 기록한다.
- 완료 기준: 허용 비교는 추천 생성까지 확인하고, 차단은 사유와 다음 행동이 모두 설명 가능해야 한다. production 수정은 사용자 승인 전 금지다.

### 최신 제품·UX 정책

- FitMatch는 체형 추정이 아니라 사용자가 잘 입는 기준 옷의 실측과 구매 상품의 실측을 비교한다.
- 온보딩에서 처음 등록하는 잘 맞는 옷만 기준 옷 토글을 기본 ON으로 제공하며 일반 등록은 기본 OFF다.
- 링크 상품 미리보기는 다른 URL을 다시 불러오기 위해 유지하지만 중복 읽기 전용 확인 화면은 제거했다.
- 기준 옷 후보를 누르면 중복 확인 없이 즉시 비교하고 처리 중에는 후보 입력을 잠근다.
- 기준 옷 순위는 브랜드보다 의류 구조·측정 방식·공통 실측·실측 유사도를 우선한다.
- 동일 종류 자동 후보가 없으면 기존 화면에서 유사 옷 직접 선택 또는 해당 상품 내 옷장 추가를 제공한다.
- 비교 상품 저장 후 자기 자신과 비교하지 않고 홈으로 복귀한다.
- 저장 성공은 Alert가 아니라 비차단 토스트로 표시하고 연속 저장을 막는다.
- 반팔·민소매 상의는 공통 핵심 실측 2개 이상일 때 사용자 선택 확장 비교를 허용한다. 자동 선택은 동일 구조 중심을 유지한다.
- 긴팔 티셔츠, 셔츠, 니트는 서로 별도 구조군이다. 스웨트셔츠와 후드는 직접 호환한다.
- 셔츠는 반팔·긴팔 티셔츠 세부군으로 덮어쓰지 않고 셔츠 구조를 보존하며 길이는 canonical 속성으로 관리한다.

### 최신 자동 검증 요약

- 무신사 3개 긴바지 상품: 6개 방향 × 기준 사이즈 4개 = 24개 조합을 production 경로로 두 차례 실행했고 결과가 일치했다.
- 카테고리 라이브 감사: 71개 선택, 70개 로드, 2,970개 전 방향·전 기준 사이즈 조합 실행.
- 비교 허용 1,757개는 모두 추천 완료, 정책상 차단 1,213개, 근거 부족 0개, 비결정성 0개, 최고점이 아닌 추천 0개다.
- 기존 저장 데이터 `0. S` 표시 정규화와 과거 `canonicalEligibility=false` 긴바지의 재진입·backfill·비교 회귀 6개가 통과했다.
- 혼합 유니클로 카테고리 수정 후 단위 회귀 2개, 실상품 라이브 3개, 전체 2,970개 조합 재검증이 통과했다.
- Safari 시스템 공유 시트 E2E는 Simulator에서 FitMatch 확장이 노출되지 않아 앱 비교 단계 이전 환경 차단으로 분류했다.

### 최신 남은 문제

- 유니클로 `E488923 BT릴랙스핏레깅스(10부·프린트)`는 공식 사이즈표는 있으나 베이비 상품 형식을 production 파서가 처리하지 못해 성인 비교에서 제외했다. 키즈·베이비 파서 지원 과제로 분리한다.
- 무신사 숏 레깅스와 유니클로 라운지웨어·블레이저·원피스·재킷·패딩은 실제 실측 표본이 플랫폼별 3개 미만이라 이번 카테고리 전수 감사에서 완료로 계산하지 않았다.
- 전체 핵심 스위트의 `manualLengthMismatchAllowsExplicitExtendedComparison` 기대값 2건은 긴팔 니트↔반팔 니트와 긴바지↔쇼츠를 허용하는 구형 정책이다. 현재 production 로직은 승인된 정책대로 두 조합을 차단하므로 로직 수정 대상이 아니며, 테스트 기대값 갱신만 보류돼 있다.
- 미구매 비교상품을 `내 옷장`에 저장하는 현재 기능은 사용자가 실제 보유한 옷과 구매 후보를 섞을 수 있다. 기능은 유지 중이지만 명칭 분리·저장 위치·정책은 아직 제품 결정이 필요하다.
- 실제 아이폰의 쇼핑몰 앱 Share Sheet → FitMatch → 저장 → 기록 재진입은 최종 사람 검수가 필요하다.

### 2026-08-13 공식 실측 교차 비교 최신 재실행

- 정확한 XCTest 브리지 2건을 공식 URL/API로 재실행해 2 tests / pass / 0 failures를 확인했다. 잘못된 메서드명으로 0건 실행된 첫 번들은 증거에서 제외했다.
- [확장 실행으로 대체됨] 유니클로 기준옷 17개 × 실제 로드 대상 70개의 비구조화 실행에서는 strict 59가 한 번 관찰됐으나 이후 동일 빌드에서 재현되지 않았다.
- 무신사 기준옷 30개 × 실제 로드 대상 70개: 2,097조합, strict 71, manual extended 134, blocked 1,892, recommendation failure 0.
- 공식 입력 71개 중 유니클로 `E488923` 1개는 사이즈 정보를 찾지 못해 두 실행 모두 제외됐다.
- 중간보고: `Docs/TestEvidence/OfficialMeasurementComparison-20260813/report.md`.
- [후속 보강 완료] 당시에는 조합별 차단 사유 JSON이 없었으나 아래 구조화·확장 실행에서 보강됐다.

#### 구조화 조합 증거 후속 보강

- `CategoryLiveComparisonAuditTests`가 각 조합마다 공식 실측/파싱/분류/등록/자동·수동 호환/추천/차단 사유/UX 상태/다음 행동을 JSON 한 줄로 출력하도록 보강했다. Production 앱 동작은 변경하지 않았다.
- 최신 권위 실행: `/tmp/FitMatchOfficialStructuredAuthoritative-20260813.xcresult`, 2 tests / pass / 0 failures.
- [확장 전 역사값] `combinations.json` 최초 구조화 실행은 3,287행, 자동 138, 수동 확장 186, 차단 2,963이었다. 현재 파일은 아래 확장 실행의 3,567행으로 교체됐다.
- production matcher의 실제 첫 차단 조건 기준 pair 분포: 의류 구조 2,638, 분류 모호 210, 길이 69, 성별·연령 46, 공통 실측 부족 0. 같은 구조 기준옷 없음은 target-level 상태로 유니클로 기준 31개, 무신사 기준 4개다.
- 유니클로 구조화 실행을 동일 빌드로 반복했고 사유·UX 표시를 제외한 1,190개 핵심 비교 결과 SHA-256 `a7cf8cb54e2751a38698ea83cca2e1ea33d128f85c897448cd6531fc6e956a0d`가 완전히 일치했다. strict 67, manual extended 52, blocked 1,071로 재현됐다. 앞선 strict 59 관찰은 최신 동일 빌드에서 재현되지 않았다.
- [확장 전 역사값] 당시 기준옷 커버리지는 유니클로 17/43, 무신사 30/43이었다. 최신은 아래 18/43, 33/43이다.

#### 확장 기준옷 후보 70개 후속 실행

- 기존 상위 3개 후보를 제외한 유니클로 35개와 무신사 35개를 공식 URL/API production 등록 probe로 검사했다.
- 신규 등록 성공:
  - 유니클로 `E450259 옥스포드셔츠` → `tops/shirt`.
  - 무신사 `4661063 우먼즈 코튼 자카드 퍼프 슬리브 블라우스` → `tops/blouse`.
  - 무신사 `4568168 멀티포켓 후드 다운 점퍼` → `outerwear/short_padding`.
  - 무신사 `5320032 2WAY 절개 라인 빈티지 피그먼트 스웨트 집업` → `outerwear/other_outerwear`.
- 확장 후 기준옷: 유니클로 18/43, 무신사 33/43.
- 확장 전체 교차 실행: `/tmp/FitMatchOfficialExpandedAuthoritative-20260813.xcresult`, 2 tests / pass / 0 failures.
- 3,567조합: 자동 153, 수동 확장 204, 차단 3,210, 추천 실패 0, UX 복구 경로 없음 0.
- pair 차단 분포: 의류 구조 2,798, 분류 모호 280, 길이 84, 성별·연령 48, 공통 실측 부족 0. 같은 세부 구조 기준옷 없음은 유니클로 기준 대상 16개, 무신사 기준 대상 3개.
- 최신 `combinations.json`과 `summary.json`은 확장 실행 결과로 교체했다.

#### 유니클로 공식 카테고리·무신사 심층 후보 후속

- 유니클로 공식 카테고리 탐색 체크포인트에서 기존 코퍼스에 없던 53개 후보를 추출해 production 등록 probe를 실행했다.
- 신규 확보: `E486703` → `tops/hoodie`, `E471808` → `tops/sweatshirt`. 유니클로 기준옷은 20/43이 됐다.
- 유니클로 `short_pants` 공식 카테고리 후보들은 production에서 대부분 `bottoms/shorts`로 저장됐고, 경량패딩 후보 `E489110`은 `outerwear/padding`으로 저장됐다.
- 무신사 코퍼스 후보 깊이를 target당 10→50으로 늘려 신규 80개(`short_pants` 40, `jumper` 40)를 probe했으나 등록 성공은 0개였다.
  - `short_pants`는 공식 숫자 실측이 있는 로드 상품이 모두 `bottoms/shorts`로 저장됐다.
  - `jumper`는 `jacket`, `windbreaker`, `anorak`, `padding`, `fleece`, `blazer` 등 더 구체적인 코드로 저장됐다.
  - 따라서 두 코드는 추가 상품 탐색만으로 채워질 가능성이 낮고, 43 taxonomy에서 독립 코드를 유지할지 병합할지 정책 결정이 필요하다. Production 코드는 수정하지 않았다.
- 최신 교차 실행: `/tmp/FitMatchOfficialExpanded20x33-20260813.xcresult`, 2 tests / pass / 0 failures.
- 유니클로 20개 + 무신사 33개 기준옷, 대상 70개, 3,707조합: 자동 173, 수동 확장 204, 차단 3,330, 추천 실패 0, UX 복구 없음 0.
- 최신 pair 차단 분포: 의류 구조 2,914, 분류 모호 280, 길이 86, 성별·연령 50, 공통 실측 부족 0. 동일 세부 구조 reference 없음은 유니클로 기준 대상 8개, 무신사 기준 대상 3개.

#### 비교 자격 정리 후 최종 재실행

- 공식 숫자 실측과 저장 taxonomy는 통과했지만 `canonicalEligibility=false`인 무신사 기준옷 4개(`1958464`, `4154987`, `1195307`, `5320032`)를 `ReferenceClosetRegisteredButIneligibleMusinsa.json`으로 분리했다.
- `outerwear/jacket`은 eligibility=true 후보 `1576682`로 대체했다. 따라서 무신사는 등록 성공 target code 33개와 실제 비교 가능한 기준옷 30개를 구분한다. 유니클로 비교 가능 기준옷은 20개다.
- 최신 권위 실행: `/tmp/FitMatchOfficialEligible20x30-20260813.xcresult`, `/tmp/FitMatchOfficialEligible20x30-20260813.log`; 정확한 XCTest 2건 / pass / 0 failures, 145.113초.
- 대상 70개에 대해 3,497조합을 기록했다. 이론상 3,500에서 무신사 기준옷과 동일 상품인 3쌍(`1108007`, `1572220`, `2387085`)은 자기 비교 방지로 제외됐다.
- 자동 171, 수동 확장 204, 차단 3,122, 추천 실패 0, 복구 경로 없음 0. pair 차단 사유는 의류 구조 2,986, 길이 85, 성별·연령 50, 분류 모호 1이다.
- target-level UX 상태는 자동 비교 결과 2,159, 기준옷 선택 728, 자동 후보 없음 590, 사용자 카테고리 선택 20이다. 동일 세부 구조 기준옷이 없는 고유 대상은 유니클로 기준 9개, 무신사 기준 3개다.
- `Docs/TestEvidence/OfficialMeasurementComparison-20260813/combinations.json`, `summary.json`, `report.md`를 이 실행으로 교체했다. 이전 20×33 수치는 eligibility 정리 전 역사값이다.

#### 로컬 전체 공식 코퍼스 누락 후보 보강 재실행

- 남은 사용량 78% 시점에서 체크포인트가 75% 잔여로 수정됐다.
- 로컬 전체 공식 실측 코퍼스 2,370개 ID와 cumulative production 분류를 43개 기준옷 taxonomy에 다시 대조했다. 과거 probe에서 빠진 57개(유니클로 27, 무신사 30)를 `ReferenceClosetRemainingLocalOfficialProbeCandidates.json`으로 전수 probe했다.
- probe는 `/tmp/FitMatchRemainingLocalOfficialProbe-20260813.xcresult`에서 1 test / pass. 등록 성공 22개 중 키즈·베이비를 제외하고 성인 단품 3개만 채택했다: 유니클로 `E487394` padding, 무신사 `5386464` jumper, `4787764` three_quarter_leggings.
- 최신 비교 가능 기준옷은 유니클로 21/43, 무신사 32/43이다. 공식 실측·저장 taxonomy 등록 target code는 무신사 35/43이나 canonical eligibility 때문에 실제 비교 가능 수와 구분한다.
- 최신 권위 교차 실행: `/tmp/FitMatchOfficialEligible21x32-20260813.xcresult`, `/tmp/FitMatchOfficialEligible21x32-20260813.log`; 2 tests / pass / 0 failures.
- 3,707조합: 자동 173, 수동 확장 219, 차단 3,315, 추천 실패 0, UX 복구 없음 0. 차단 사유는 의류 구조 3,176, 길이 86, 성별·연령 53, 분류 모호 0이다.
- 동일 세부 구조 기준옷 없는 대상은 유니클로 기준 8개, 무신사 기준 3개로 감소했다. `combinations.json`, `summary.json`, `report.md`를 최신 실행으로 교체했다.
- 목표의 “각 상품” 증거를 조합 원장과 분리하기 위해 `Docs/TestEvidence/OfficialMeasurementComparison-20260813/products.json`을 추가했다. 71개 입력(무신사 40, 유니클로 31), 로드 70, 파싱 실패 `E488923` 1개와 재시도 행동을 모두 기록한다.
- 보고서에 요구사항별 권위 증거 매트릭스를 추가했다. 3,707 pair 필수 필드 누락 0, 비교 허용 후 추천 누락 0, 차단 사유 누락 0, UX 복구 누락 0, 자기 비교 0을 재확인했다.
- 상품 유입 처리 방침과 실제 공식 상품 10개 예시는 `Docs/TestEvidence/OfficialMeasurementComparison-20260813/processing-policy-and-10-examples.md`에 정리했다. 조합 JSON의 `automaticComparisonAvailable`은 실제 대표 기준옷 자동 선택 여부가 아니라 pair 단위 기본 compatibility 허용값이므로, 화면 자동 선택(`referenceSelectionPlan`에서 선호 대표 기준옷 정확히 1개)과 구분해야 한다.
- 비교군 분류 마감에서 감사 필드를 `pairComparisonLevel`, `directComparisonAvailable`, `baseExtendedComparisonAvailable`, `automaticCandidateAvailable`, `automaticallySelectedReference`, `referenceSelectionRequired`로 분리했다. 기준옷 `UserFit`에는 실제 semantics대로 `isRepresentative=true`를 설정했다.
- 최신 권위 실행은 `/tmp/FitMatchOfficialRepresentativeFinal-20260813.xcresult`와 `.log`: 2 tests / pass. 3,707 pair 중 direct 130, 기본 확장 43, 수동 확장 219, 차단 3,315, 실제 자동 후보 pair 130, 실제 자동 선택 84, 추천 실패 0이다.
- 대표 기준옷 자동 선택, 복수 대표 결정성, 비대표 단일/복수 후보 사용자 선택, short-top 수동 확장, exact-product 기타 선택 재사용, polo↔티셔츠 호환 등 7개 경계 정책을 XCTest bridge로 실행했다. `/tmp/FitMatchComparisonClassificationBoundariesBridge-20260813.xcresult`, 1 test / pass(내부 정책 7개).

## 1. 새 세션에서 가장 먼저 할 일

1. `AGENTS.md`와 이 문서를 끝까지 읽는다.
2. 현재 작업 트리를 보존한다. `reset`, `clean`, `stash`, `commit`, `push`를 사용자가 명시적으로 요청하지 않는 한 실행하지 않는다.
3. 다음 명령으로 현 상태만 확인한다.

```bash
cd /Users/jinyoung/Documents/Projects/FitMatch/FitMatch
git status --short
python3 scripts/review-fit-pair-candidates.py --summary
```

현재 작업 트리는 대규모 미커밋 상태다. 조사 원본과 회귀 코퍼스도 포함되어 있으므로 용량이 크다는 이유로 삭제하면 안 된다.

Supabase 작업은 사용자가 집에서 하기로 하고 보류했다. 사용자가 명시적으로 재개하기 전에는 원격 DB에 SQL을 적용하거나 보안 설정을 변경하지 않는다.

## 2. 사용자의 최종 목표

FitMatch로 들어온 무신사·유니클로 상품을 다음 순서로 안정적으로 처리하는 것이 목표다.

1. 브랜드 공식 URL/API/HTML에서 상품 정체성, 공식 카테고리, 사이즈표를 수집한다.
2. 브랜드 공식 카테고리를 우선 근거로 FitMatch 대분류·세부분류에 매핑한다.
3. 공식 카테고리만으로 길이·구조를 확정할 수 없을 때에만 상품명과 검증된 키워드를 보조 근거로 사용한다.
4. 내 옷장 기준 옷과 비교 상품이 같은 의류군·길이·구조이고 정확한 실측 코드가 호환될 때만 자동 비교한다.
5. 실측 근거가 부족하거나 의미가 다르면 높은 신뢰도를 표시하지 않고 비교 보류 또는 수동 선택으로 보낸다.
6. 현재 앱의 하드코딩 분류 동작과 DB 규칙을 동등하게 관리해, 나중에 하드코딩을 제거하고 DB 조회로 바꿔도 기존 동작이 유지되게 한다.
7. 향후 Zara, COS, H&M 등도 동일한 공급사 어댑터와 표준 분류·실측 계약에 붙일 수 있게 한다.

보존해야 하는 제품 원칙은 다음과 같다.

- Reference Garment 개념을 유지한다.
- `category`와 `detailCategory` 구조를 유지한다.
- 가슴둘레와 가슴단면, 일반 소매와 화장, 앞기장과 뒤기장을 같은 값으로 취급하지 않는다.
- 공급사가 제공하지 않은 실측값을 추정해서 만들지 않는다.
- 자동 비교가 불가능한 경우 억지로 추천하지 않는다.
- 기존 UX와 아키텍처는 사용자의 명시적 요청 없이 바꾸지 않는다.

## 3. 현재 상태 한눈에 보기

| 영역 | 현재 상태 | 해석 |
|---|---:|---|
| 전체 앱 완성도 | 약 95% | 방향성 평가이며 테스트 통과율이 아님 |
| 핵심 코드·자동검증 | 약 99% | 현재 정의된 자동 게이트는 실패 0 |
| 누적 고유 상품 분류 | 2,560건 | 무신사 1,545 + 유니클로 1,015 |
| 분류 의미 감사 | 오류 0건 | 명시적 상품 신호·유효 분류 감사 통과 |
| 실제 내 옷장–비교 상품 쌍 | 879쌍 | 무신사 699 + 유니클로 180 |
| 비교쌍 자동 무결성 감사 | 오류 0건 | 카테고리·실측 의미·산술·신뢰도 계약 통과 |
| 전체 자동 회귀 | 284개 | 279 통과, 실패 0, 실서버 전용 5 스킵 |
| 사람 독립 검수 | 0/200 | 아직 체감 핏 정확도를 확정할 수 없음 |
| 최신 Release archive | 성공 | 서명 제외 arm64 archive |
| App Store 제출 감사 | 4개 실패 | 공개 URL 2개 + 배포 서명 2개 |

중요한 해석:

- `2,560/2,560`은 현재 분류 로직이 유효한 결과를 만들고 명시적 의미 감사에서 오류가 없었다는 뜻이다. 사람 기준 분류 정확도 100%를 의미하지 않는다.
- `879/879`은 비교쌍의 구조, 측정 의미, 산술과 신뢰도 계약이 일관됐다는 뜻이다. 사용자가 느끼는 핏 만족도 100%를 의미하지 않는다.
- 과거 문서의 `915쌍`은 후속 의류군 우선순위·호환성 정제 전 수치다. 최신 기준은 `879쌍`이다.
- 더 많은 320/1,280건 상품 수집보다 200쌍 사람 검수와 실제 기기 QA가 지금 더 유의미하다.

## 4. 지금까지 완료한 작업

### 4.1 실제 상품 데이터 수집과 누적 회귀

- 첫 320건, 중복 없는 재검증 320건, 세 번째 320건, 무신사 네 번째 320건을 누적했다.
- 이후 기존 1,280건과 중복 없는 신규 1,280건을 추가했다.
  - 신규 무신사 1,037건
  - 신규 유니클로 243건
- 최종 누적 분류 코퍼스는 중복 없는 2,560건이다.
  - 무신사 1,545건
  - 유니클로 1,015건
- 상품 ID 색상 변형을 별도 상품으로 부풀리지 않았다.
- 분류 결과의 공급사 상품 ID, 상품명, 공식 카테고리 경로, FitMatch 대분류·세부분류를 JSON/CSV로 데이터화했다.
- 명시적 반팔·긴팔·민소매, 쇼트팬츠·크롭·긴바지, 가디건·레깅스·원피스 신호를 독립 감사하는 스크립트를 추가했다.

최신 분류 감사 근거:

- `Docs/Research/FitPairHumanReview-20260806/classification_semantic_audit_report.json`
- 결과: `passed`, 2,560건, 오류 0건

### 4.2 앱 분류 로직 보강

- 브랜드 공식 카테고리의 가장 구체적인 depth를 우선 사용한다.
- 공식 카테고리가 모호할 때만 상품명으로 길이·세부 의류군을 보완한다.
- 대분류, 세부분류, 의류군, 길이, 구조를 별도 축으로 유지한다.
- 반팔·긴팔·민소매·7부 상의, 쇼츠·크롭·7부·9부·긴바지, 레깅스 길이를 구분한다.
- 가디건, 후디, 스웨트셔츠, 셔츠, 티셔츠, 데님, 일반 팬츠, 레깅스, 스커트, 아우터, 레더 재킷 등의 비교 의류군을 구분한다.
- 파자마·홈웨어, 속옷, 원피스, 스커트, 유아 의류처럼 상위 경로만으로 오판하기 쉬운 사례의 우선순위를 교정했다.
- 개별 상품 ID 예외를 추가하는 대신 재사용 가능한 카테고리·의미 규칙으로 수정했다.

핵심 파일:

- `FitMatch/Models/ParsedClosetClassification.swift`
- `FitMatch/Models/ClothingCategory.swift`
- `FitMatch/Models/CanonicalComparisonProfile.swift`
- `FitMatch/Services/ComparisonProfileMatcher.swift`

### 4.3 무신사·유니클로 파서 보강

- 무신사는 actual-size API를 우선하고, 공식 응답이 없거나 유효하지 않을 때만 안전한 fallback을 사용한다.
- 공식 API에서 제공하는 `ONE SIZE`, `OS`, `1 (M)`, `블랙_S` 같은 비표준 사이즈명은 공식 근거가 있는 범위에서 허용한다.
- HTTP 성공이어도 실측 행이 없거나 값이 전부 0이면 임의 수치를 만들지 않는다.
- 유니클로 색상별 상품 ID에 사이즈표가 없으면 공통 `-000` ID를 한 번만 재조회한다.
- 유니클로의 `허리 [하의]` 둘레는 검증된 경우에만 0.5를 적용해 단면으로 변환한다.
- 의미가 다른 gathered body width, 속치마, 목둘레, 불명확한 측면 길이는 비교 근거에서 제외한다.
- 공식 호스트와 위장 도메인을 구분하고, 지원하지 않는 URL에 범용 파서를 호출하지 않도록 했다.
- 실질 구현 없이 실패하던 `GenericProductParser.swift`는 삭제했고 서비스 디스패치에서 사용하지 않는다. 일부 과거 아키텍처 문서에는 아직 이름이 남아 있어 코드가 우선이다.

핵심 파일:

- `FitMatch/Services/MusinsaActualSizeAPIParser.swift`
- `FitMatch/Services/MusinsaFallbackSizeParser.swift`
- `FitMatch/Services/MusinsaParser.swift`
- `FitMatch/Services/MusinsaProductMetadataParser.swift`
- `FitMatch/Services/MusinsaURLResolver.swift`
- `FitMatch/Services/MusinsaWebViewParser.swift`
- `FitMatch/Services/UniqloParser.swift`
- `FitMatch/Services/ProductURLParserService.swift`
- `FitMatch/Services/ParsedSizeValidator.swift`
- `FitMatch/Services/SizeTokenNormalizer.swift`

### 4.4 실제 내 옷장–비교 상품 쌍 검증

- 공급사 공식 실측을 앱 운영 파서, 검증기, 후보 선택기, 최종 비교 엔진 순서로 실행했다.
- 최종 독립 감사 대상은 879쌍이다.
  - 무신사 699쌍
  - 유니클로 180쌍
  - 상의 389, 하의 203, 아우터 284, 원피스 1, 기타 2
- 신뢰도 분포:
  - 높은 신뢰도 715
  - 충분한 비교 147
  - 최소 기준 충족 16
  - 근거 부족 1
- 근거 부족 1건은 실패를 숨긴 것이 아니라 앱 계약대로 확정 추천을 하지 않는 결과다.
- 대분류 불일치, 세부분류 불일치, 중복 쌍, 부호·절댓값 계산, 가중 점수, 커버리지, 신뢰도 라벨 계약을 독립 검사했다.
- 자동 후보는 같은 대분류, 호환 가능한 의류군·길이·구조·성별 정책과 최소 공통 실측을 충족해야 한다.
- 같은 세부분류를 기준 옷 여부나 실측 개수보다 먼저 선택하도록 했다.
- 교차 분류는 자동 매칭하지 않고, 사용자가 직접 선택한 임시 비교에서만 감점·안내와 함께 사용할 수 있다.

최신 근거:

- `Docs/Research/FitPairHumanReview-20260806/actual_fit_pairs_enriched.json`
- `Docs/Research/FitPairHumanReview-20260806/automated_integrity_report.json`
- `Docs/Research/FitPairHumanReview-20260806/fit_pair_human_review_candidates_200.json`
- `Docs/Research/FitPairHumanReview-20260806/README.md`

### 4.5 측정 의미와 추천 신뢰도

- canonical measurement code가 정확히 같은 항목만 직접 비교한다.
- 둘레와 단면, 아웃심과 인심, 일반 소매와 화장을 혼합하지 않는다.
- 비교 항목 수와 필수 항목 충족 여부에 따라 확정, 최소 근거, 근거 부족을 나눈다.
- 호환되지 않는 길이 측정은 제외하고 사용자에게 제외 사유를 설명한다.
- 근거가 부족하면 `추천 결과 아님` 또는 비교 불충분 화면을 보여 높은 신뢰도로 오인시키지 않는다.

핵심 파일:

- `FitMatch/Models/MeasurementCode.swift`
- `FitMatch/Services/MeasurementComparisonEngine.swift`
- `FitMatch/Services/MeasurementLegacyBackfillService.swift`
- `FitMatch/Services/RecommendationService.swift`
- `FitMatch/Views/CompareFlowSheet.swift`
- `FitMatch/Views/RecommendationResultView.swift`

### 4.6 공유 확장과 실제 사용자 여정

- 앱과 공유 확장 사이의 App Group URL 저장·소비 흐름을 보강했다.
- 앱 활성화와 딥링크가 연속으로 발생해 비교 요청이 사라지던 경합을 수정했다.
- 공유 URL은 비교 화면이 표시되기 전에 삭제하지 않는다.
- 공유 확장의 성공 문구를 실제 보장 범위에 맞췄다.
- 공유 확장 표시 이름을 `FitMatch`로 정리했다.
- 시뮬레이터에서 유니클로·무신사 링크 옷장 등록과 공유 URL 수신, 앱 복귀 후 분석 시작까지 확인했다.
- 실제 아이폰에서 개발 서명 빌드 설치, 앱 실행, 딥링크 수신 후 프로세스 생존까지 확인했다.
- 2026-08-07 실기기에서 `extensionContext.open`이 실패한 뒤 비활성화된 `FitMatch 앱을 직접 열어주세요` 버튼이 표시되는 회귀를 확인했다. 예전에 동작한 responder-chain 앱 열기를 다시 1순위로 복구하고 `extensionContext.open`은 fallback으로 내렸으며, 두 경로가 실패해도 `FitMatch 다시 열기` 버튼을 활성 상태로 유지하도록 수정했다.
- 공유 확장 `보러가기` 자동 전환과 두 쇼핑몰 최종 결과 화면은 실제 아이폰에서 최종 확인이 남았다.

핵심 파일과 증거:

- `FitMatch/Services/SharedURLStore.swift`
- `FitMatch/ContentView.swift`
- `FitMatchShareExtension/ShareViewController.swift`
- `FitMatchShareExtension/Info.plist`
- `FitMatchUITests/FitMatchLiveUserJourneyUITests.swift`
- `Docs/LiveUserJourneyBugReport-20260806.md`
- `Docs/TestEvidence/LiveUserJourney-Summary-20260806/`

### 4.7 개인정보·품질지표·App Store 준비

- 앱 실행, 공유 수신·소비, 파싱 시도·성공·실패, 비교 시도·결과·차단, 옷장 저장을 로컬 집계한다.
- 상품명, URL, 상품 ID, 실측값, 옷장 이름, 사용자 식별자를 집계 데이터에 저장하지 않는다.
- MY → 문의 및 지원에서 사용자가 품질 진단 정보를 직접 내보낼 수 있다.
- 자동 서버 전송은 없다. Supabase가 재개되기 전까지 로컬 저장·수동 내보내기 방식이다.
- 앱과 공유 확장에 Privacy Manifest를 추가했다.
- Release에서 상품·옷장·실측·비교 상세 진단 로그를 비활성화했다.
- 개인정보처리방침과 고객지원 화면 및 HTTPS 구성 검증을 추가했다.
- App Store archive 감사 스크립트가 번들 ID, 버전, URL scheme, arm64, Privacy Manifest, dSYM, 앱·확장 배포 서명을 확인한다.

새 파일:

- `FitMatch/Services/FitMatchMetricsRecorder.swift`
- `FitMatch/Views/ReleaseInformationView.swift`
- `FitMatch/PrivacyInfo.xcprivacy`
- `FitMatchShareExtension/PrivacyInfo.xcprivacy`
- `FitMatchTests/FitMatchMetricsRecorderTests.swift`
- `FitMatchTests/FitMatchReleaseConfigurationTests.swift`
- `scripts/audit-app-store-archive.sh`

## 5. 자동검증과 빌드 증거

### 5.1 최신 자동 회귀

- 결과 번들: `/tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult`
- 총 284개
- 통과 279개
- 실패 0개
- 스킵 5개
- 스킵 5개는 일반 회귀에서 의도적으로 제외한 실서버 전용 테스트다.

확인 명령:

```bash
xcrun xcresulttool get test-results summary \
  --path /tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult
```

### 5.2 품질 진단 추가 검증

- 단위 테스트: `/tmp/FitMatchMetricsExport-20260807.xcresult`, 5/5 통과
- UI 테스트: `/tmp/FitMatchMetricsExportUI-20260807.xcresult`, 1/1 통과

이 테스트는 최신 전체 회귀 이후 추가된 품질 진단 내보내기 변경을 별도로 검증한다. 해당 변경을 포함한 최신 Release archive도 성공했다.

### 5.3 최신 Release archive

- 경로: `/tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive`
- 상태: `ARCHIVE SUCCEEDED`
- 앱: `com.ljy4337.fitmatch`, 1.0 (4)
- 공유 확장: `com.ljy4337.fitmatch.shareextension`, 1.0 (4)
- arm64, 앱·확장 Privacy Manifest, 앱·확장 dSYM 포함
- 서명 제외 archive이므로 배포 서명 실패는 예상된 결과다.

감사 명령:

```bash
scripts/audit-app-store-archive.sh \
  /tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive
```

현재 실패는 정확히 4개다.

1. 공개 개인정보처리방침 HTTPS URL 없음
2. 공개 고객지원 HTTPS URL 없음
3. 앱 Apple Distribution 서명 없음
4. 공유 확장 Apple Distribution 서명 없음

`/tmp` 산출물은 재부팅이나 정리로 사라질 수 있다. 경로가 없으면 실패로 오해하지 말고 같은 소스에서 다시 실행해 새 증거를 만든다.

## 6. 만든 데이터·문서·도구 파일

### 6.1 주요 데이터 디렉터리

- `Docs/Research/NewClothingCorpus-320-20260806/`
  - 최초 320건 원본, 분류 입력·결과, 카테고리별 그룹 CSV/JSON, 차단 상품 보고
- `Docs/Research/NewClothingCorpus-320-Retest-20260806/`
  - 기존과 중복 없는 재검증 320건
- `Docs/Research/NewClothingCorpus-320-Third-20260806/`
  - 세 번째 320건과 누적 960 회귀
- `Docs/Research/MusinsaNew320Collection-20260806/`
  - 신규 무신사 320 수집 원본
- `Docs/Research/NewClothingCorpus-320-MusinsaFourth-20260806/`
  - 네 번째 320건, 누적 1,280 회귀와 무신사 실측 근거
- `Docs/Research/CategoryCorpus-live-uniqlo-1280-20260806/`
  - 유니클로 신규 후보 수집 원본
- `Docs/Research/NewClothingCorpus-1037-MusinsaFifthEighth-20260806/`
  - 신규 무신사 1,037건 분류 입력과 실측 근거
- `Docs/Research/NewClothingCorpus-243-UniqloFifth-20260806/`
  - 채택된 신규 유니클로 243건 분류 입력과 실측 근거
- `Docs/Research/NewClothingCorpus-300-UniqloFifth-20260806/`
  - 유니클로 후보 300건 조사 근거
- `Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/`
  - 신규 1,280건, 누적 2,560 Swift 분류 결과, 무신사·유니클로 실측 비교 결과
- `Docs/Research/FitPairHumanReview-20260806/`
  - 최종 879쌍, 자동 감사 결과, 사람 검수 후보 200쌍

위 디렉터리 일부는 raw HTML/API 응답 때문에 수백 MB다. 중복 상품 검증과 공식 근거 추적에 필요하므로 임의 삭제하지 않는다.

### 6.2 주요 보고 문서

- `Docs/FitMatch_무신사_유니클로_데이터_및_출시검증_리포트_20260806.md`
  - 초기부터의 장문 보고서. 앞부분 일부 수치는 과거 기준이므로 최신 수치는 이 인수인계 문서를 우선한다.
- `Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/progress_report.md`
  - 신규 1,280 및 누적 2,560 진행 상세. 이 문서의 915쌍은 후속 정제 전 수치다.
- `Docs/Research/RuntimeClassificationParity-20260806.md`
  - 앱 하드코딩과 DB 분류 규칙 동등화 설계·과거 실행 결과
- `Docs/AppStoreReadiness-20260806.md`
  - 최신 출시 준비 상태
- `Docs/AppStoreSubmissionRunbook-20260806.md`
  - URL 준비부터 서명·Validate·업로드까지 실행 순서
- `Docs/AppStorePrivacyPolicyDraft-20260806.md`
  - 실제 운영자 정보와 URL을 채워야 하는 초안
- `Docs/HomeDeviceQAChecklist.md`
  - 실제 아이폰에서 남은 검증 항목
- `Docs/Research/SupabaseSecurityReview-20260806.md`
  - 수행한 보안 검토와 대시보드 수동 조치

### 6.3 만든 자동화 스크립트

- `scripts/build-new-clothing-corpus.py`: 수집 결과를 회귀 코퍼스로 구성
- `scripts/group-new-clothing-by-fitmatch-category.py`: FitMatch 카테고리별 CSV/JSON 그룹 생성
- `scripts/validate-320-direct-logic.py`: 320건 직접 분류 검증
- `scripts/collect-new-uniqlo-retest.py`: 중복 없는 유니클로 재수집
- `scripts/collect-new-musinsa-balanced.py`: 무신사 카테고리 균형 수집
- `scripts/collect-musinsa-size-evidence.py`: 무신사 공식 실측 근거 수집
- `scripts/collect-uniqlo-size-evidence.py`: 유니클로 공식 실측 근거 수집
- `scripts/generate-regression-corpus-seed.py`: DB 회귀 seed 생성
- `scripts/generate-runtime-classification-parity-seed.py`: 런타임 규칙 동등성 seed 생성
- `scripts/generate-swift-classification-expectation-seed.py`: Swift 2,560 기대값 SQL 생성
- `scripts/build-musinsa-fit-pair-inputs.py`: 무신사 실제 비교쌍 입력 생성
- `scripts/build-uniqlo-fit-pair-inputs.py`: 유니클로 실제 비교쌍 입력 생성
- `scripts/audit-classification-semantics.py`: 2,560 분류 의미 감사
- `scripts/audit-fit-pair-integrity.py`: 879 비교쌍 독립 무결성 감사
- `scripts/build-fit-pair-human-review-set.py`: 위험도·계층 기반 사람 검수 200쌍 생성
- `scripts/review-fit-pair-candidates.py`: 사람 검수 입력·즉시 저장·재개 CLI
- `scripts/audit-app-store-archive.sh`: 제출 archive 자동 감사

### 6.4 추가한 회귀 입력과 테스트

- `FitMatchTests/LegacyMixed320ClassificationInputs.json`
- `FitMatchTests/LegacyUniqloRetest320ClassificationInputs.json`
- `FitMatchTests/LegacyUniqloThird320ClassificationInputs.json`
- `FitMatchTests/LegacyMusinsaFourth320ClassificationInputs.json`
- `FitMatchTests/Musinsa1037ClassificationInputs.json`
- `FitMatchTests/Musinsa1037FitPairInputs.json`
- `FitMatchTests/Uniqlo243ClassificationInputs.json`
- `FitMatchTests/Uniqlo243FitPairInputs.json`
- `FitMatchTests/FitMatchTests.swift`
- `FitMatchTests/LiveMusinsaValidationTests.swift`
- `FitMatchUITests/FitMatchUITests.swift`
- `FitMatchUITests/FitMatchLiveUserJourneyUITests.swift`

공유 scheme도 새로 만들었다.

- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatch.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchShareExtension.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveValidation.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveUserJourney.xcscheme`

일반 `FitMatch` scheme은 실서버 테스트를 스킵한다. 실서버 검증은 `FitMatchLiveValidation`, Safari 공유 전체 여정은 `FitMatchLiveUserJourney`를 명시적으로 사용한다.

## 7. 앱 하드코딩과 DB 규칙 상태

현재 앱은 DB에서 분류 규칙을 조회하지 않는다. `ParsedClosetClassification`과 관련 모델·서비스의 하드코딩 규칙이 실제 런타임 소스다.

DB 쪽에는 향후 전환을 위한 미러 구조와 평가기를 준비했다.

| 테이블 | 역할 |
|---|---|
| `fitmatch_taxonomy.runtime_rule_sets` | 앱 소스 체크섬, 규칙 버전, 실행 순서 |
| `fitmatch_taxonomy.runtime_classification_rules` | 공급사·단계·입력 범위·키워드·출력 매핑 |
| `fitmatch_staging.runtime_classification_regression_cases` | 현재 앱 기대 결과 |
| `fitmatch_staging.runtime_classification_parity_runs` | 일치·불일치·체크섬 이력 |

로컬 SQL:

- `supabase/sql/016_...`~`071_...`: 런타임 분류 미러, 독립 평가기, 코퍼스 seed, 2,560 Swift 기대값, 공급사 우선순위 정렬
- `supabase/sql/072_restrict_handle_new_user_execution.sql`: `handle_new_user()`의 불필요한 공개 실행 권한 회수

확인된 과거 상태:

- 당시 Swift↔DB 분류 category/detail은 2,560/2,560 일치했다.
- 이후 자동 비교 의류군·세부분류 호환 정책을 더 정제해 최종 비교쌍이 879개가 됐다.
- 이 최종 비교 호환 정책은 원격 DB에 미러링·검증했다고 간주하면 안 된다.
- `Docs/Research/SupabaseSecurityReview-20260806.md`에는 072 조치가 원격 적용되고 관련 Advisor 경고가 제거됐다고 기록돼 있다.
- 유출 비밀번호 보호는 Supabase Dashboard에서 사용자가 직접 활성화한 뒤 Auth 회귀가 필요하다.
- taxonomy/staging 스키마는 앱 클라이언트 공개용이 아니며 `anon`, `authenticated` 접근을 허용하지 않는 기본 거부 구조다.

주의:

- 로컬 SQL에 `038_runtime_musinsa_1037_seed_chunk_5.sql`과 `038_runtime_uniqlo_243_seed.sql`이라는 동일 번호 파일이 둘 있다. 자동 일괄 적용 전에 원격 migration ledger와 실제 실행 순서를 반드시 대조한다.
- 현재 원격 DB가 로컬 SQL 전체와 동일하다고 추정하지 않는다.
- DB 런타임 전환 전에는 현재 Swift 결과와 DB 평가 결과를 같은 고정 코퍼스에서 건별 비교하고, 한 건이라도 다르면 하드코딩 제거를 차단한다.
- 앱에서 DB를 직접 읽게 할 때는 읽기 전용 API 경계, 버전 고정, 캐시, timeout, 오프라인 fallback, RLS/권한을 별도로 설계한다.

## 8. 현재 작업 트리 상태

2026-08-07 점검 당시:

- tracked 수정: 48개
- tracked 삭제: 1개 (`FitMatch/Services/GenericProductParser.swift`)
- untracked 경로: 111개
- tracked diff: 49개 파일, 약 3,993줄 추가 / 722줄 삭제
- commit/push 없음

변경 범위는 모델, 파서, 비교 엔진, 공유 확장, 화면, 테스트, 문서, 조사 데이터, Supabase SQL 전반에 걸쳐 있다. 새 세션에서 일부만 보고 “나머지는 불필요하다”고 삭제하지 않는다.

보호 파일:

- `FitMatch/Components/TabBarScrollVisibilityModifier.swift`는 현재 diff가 없다.
- Swift modifier 호출부에도 추가·삭제 diff가 없다.
- 전체 diff grep에는 `Docs/CurrentSprint.md`의 설명 문장 하나가 잡히지만 Swift 호출부 변경은 아니다.
- 보호 파일이나 `hidesBottomTabBarOnScroll`, `tracksTabBarVisibilityOnScroll`, `hidesTopChromeOnScroll` 호출부는 사용자가 파일과 스크롤 동작을 명시적으로 승인하지 않는 한 수정하지 않는다.

현재 Release archive에서 보호 파일 관련 Swift actor-isolation 경고 4개가 있었지만 빌드·archive를 막지 않는다. 경고 제거를 이유로 보호 파일을 수정하면 안 된다.

## 9. 다음에 해야 할 일

### P0 — 사람 독립 검수 200쌍

현재 가장 먼저 할 일이다.

```bash
python3 scripts/review-fit-pair-candidates.py --summary
python3 scripts/review-fit-pair-candidates.py --reviewer "검수자 이름"
```

- 일부만 진행할 때는 `--limit 20`을 붙인다.
- 각 판정은 즉시 JSON에 저장되므로 중단 후 재개할 수 있다.
- 검수 항목은 카테고리 호환, 측정 의미, 차이 방향, 신뢰도 라벨, 전체 결과 수용 가능성이다.
- `category_compatibility`, `measurement_semantics_correct`, `signed_differences_correct`의 오류 허용치는 0건이다.
- 높은 신뢰도 표본의 `reliability_label_appropriate` 오류 허용치도 0건이다.
- 오류가 나오면 해당 규칙과 같은 계층 전체를 수정하고 879쌍 감사와 영향 범위 회귀를 다시 실행한다.
- 검수 완료 전에는 후보셋을 골드셋 또는 정확도 수치로 부르지 않는다.

예상 시간: 오류가 없으면 약 1~2시간. 오류가 있으면 규칙 수정·재검증 시간이 추가된다.

### P0 — 실제 아이폰 QA

`Docs/HomeDeviceQAChecklist.md`를 실제 기기에서 수행한다.

필수 항목:

- 기존 데이터가 앱 업데이트 후 유지되는지 확인
- 옷장 등록·수정·삭제와 기준 옷 교체
- 무신사·유니클로 URL 비교 완료
- Safari와 무신사 앱의 공유 확장 왕복
- 공유 확장 `보러가기` 후 FitMatch 자동 전환
- 앱 실행 중·백그라운드·완전 종료 상태의 공유 비교
- 네트워크 단절 안내와 복구 후 재시도
- 분석 취소, 빠른 연속 요청, 중복 기록 방지
- 하단 바운스·감속 중 헤더/탭바 스크롤 동작

예상 시간: 30~60분. 실패가 있으면 화면 녹화, URL, 시간, 기기·OS를 기록한다.

### P0 — App Store 외부 입력과 서명

사용자에게 필요한 입력:

- 실제 개인정보처리방침 HTTPS URL
- 실제 고객지원 HTTPS URL
- Apple Distribution 인증서와 App Store 배포 프로파일

URL을 받으면 `FitMatch/Info.plist`의 다음 빈 값을 채운다.

- `FitMatchPrivacyPolicyURL`
- `FitMatchSupportURL`

그 다음 Apple Distribution으로 앱과 공유 확장을 서명한 archive를 만들고 다음을 실행한다.

```bash
scripts/audit-app-store-archive.sh /path/to/FitMatch.xcarchive
```

`RESULT: passed` 확인 후 Organizer의 `Validate App`, 업로드, TestFlight 실기기 최종 검증 순으로 진행한다.

예상 시간: 공개 URL과 Apple 계정·프로파일이 준비돼 있으면 20~40분. URL 호스팅 준비 시간은 별도다.

### P1 — 출시 제품 결정

- 비교 화면의 ZARA 버튼은 현재 `준비중`이다.
- 앱의 추천 영역도 일부 로드맵/준비중 인상을 줄 수 있으므로 1.0에서 유지할지 숨길지 사용자가 결정해야 한다.
- 이는 기술적으로 임의 결정하지 않는다. UX 변경 전에 사용자 승인을 받는다.

### 보류 — Supabase

- 사용자가 재개할 때만 원격 상태를 먼저 읽기 전용으로 감사한다.
- 로컬 016~072를 무조건 재적용하지 않는다.
- 현재 Swift 분류 결과, DB 평가기, 최종 자동 비교 호환 규칙의 차이를 먼저 확인한다.
- 중앙 품질지표 전송을 추가한다면 전송 데이터, 보존기간, 동의, 개인정보처리방침, App Store Privacy 답변을 함께 바꾼다.

## 10. 더 이상 반복하지 않아도 되는 작업

- 특별한 신규 결함이나 신규 공급사 계약 검증이 없는 한 320개씩 무한 수집하지 않는다.
- 자동 감사 통과 수를 사람 정확도 100%라고 표현하지 않는다.
- 과거 242/248/265/273 테스트 수를 최신 전체 회귀 수로 보고하지 않는다. 최신 전체 회귀는 284개 기준이다.
- 과거 915쌍을 최신 비교쌍 수로 보고하지 않는다. 최신은 879쌍이다.
- `GenericProductParser`를 복구해 지원하지 않는 URL을 억지로 파싱하지 않는다.
- 원본 실측이 없는 상품에 임의 치수를 생성하지 않는다.
- DB 전환이 끝나기 전에 앱 하드코딩을 제거하지 않는다.

## 11. 출시 완료 정의

다음이 모두 충족돼야 1.0 출시 준비 완료로 본다.

- 전체 자동 회귀 실패 0
- 분류 의미 감사 오류 0
- 실제 비교쌍 독립 무결성 오류 0
- 200쌍 사람 검수 완료 및 중대 의미 오류 0
- 실제 아이폰 핵심 동선 전 항목 통과
- 공개 개인정보처리방침·고객지원 URL 실제 열림 확인
- 앱과 공유 확장 Apple Distribution 서명
- archive 감사 `RESULT: passed`
- App Store `Validate App` 통과
- TestFlight 신규 설치·업데이트·공유 확장·비교 재검증 통과

코드가 이후 변경되면 변경 영향 범위의 타깃 회귀를 실행하고, 출시 archive 직전에는 전체 회귀와 archive 감사를 다시 실행한다.

## 12. 작업 종료 전 필수 안전 확인

모든 새 세션은 작업 종료 전에 다음을 실행한다.

```bash
git diff --check
git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift
git diff -- '*.swift' | grep -E \
  "hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll"
```

사용자 승인 없는 보호 파일·Swift modifier 호출부 변경이 없어야 한다. 문서 설명 문장이 전체 diff grep에 잡히는 것은 Swift 호출부 변경과 구분한다.

## 13. 2026-08-10 추가 작업

- 유니클로 `rising-length`가 일반 `length` 부분 일치 때문에 총장으로 오염되던 문제를 수정했다. 밑위·인심 상품 46개에서 수정 전 오염 37개, 수정 후 0개였다.
- P0 production 경로 22개, 일반 단위 테스트 248개를 당시 기준으로 통과했다.
- 누적 분류 코퍼스를 5,026건까지 확장하고 실제 실측 비교 706쌍을 검증했다.
- Simulator에서 링크 입력·옷장 등록·비교·기록 경로와 30쌍 실제 앱 UI 흐름을 자동화했다.
- UI 자동화는 element 존재와 실제 사용자 task 완료를 구분해 기록하도록 보완했다.
- 상세 당시 기록은 `Docs/CodexSessionHandoff-20260810.md`에 보존돼 있다.

## 14. 2026-08-11 UX 작업

### 반영 완료

- 온보딩의 첫 잘 맞는 옷만 기준 옷 기본 ON.
- URL 상품의 중복 읽기 전용 확인 화면 제거.
- 저장 성공 Alert 제거 및 `FitMatchSuccessToast` 도입.
- 저장 중 CTA 잠금과 빠른 연속 탭 중복 생성 방지.
- 기준 옷 선택 후 재확인 화면 제거 및 비교 중 입력 잠금.
- 브랜드보다 구조·측정 방식·실측 유사도를 우선하는 기준 옷 후보 순위.
- 후보 없음 화면과 기준 옷 선택 화면에 `이 상품을 내 옷장에 추가` 경로 제공.
- 유사 옷 직접 선택 후 기존 결과 화면에서 내 옷장 등록 가능.
- 저장한 비교 상품을 자기 자신과 즉시 비교하던 흐름 제거.
- 빈 홈 중복 안내 카드 제거.
- 파싱이 끝난 상품은 등록 중간 화면을 건너뛰도록 진입점 일관화.
- 반팔 니트·티셔츠·민소매 등 반팔/민소매 상의의 조건부 수동 확장 비교 허용.
- 긴팔 구조군 및 직접 반팔↔긴팔 비교는 차단.

### `E476997`가 정책 변경의 계기가 된 과정

- 유니클로 `E476997 워셔블니트폴로스웨터(반팔)`는 공식 분류가 `니트 & 가디건 > 니트 > 반팔 니트`여서 기존 matcher에서 AIRism·Umbro 반팔 티셔츠와 구조군이 다르다는 이유로 후보가 0개였다.
- 당시 아이폰에 최신 로컬 빌드가 설치되지 않은 문제도 있었지만, 최신 로컬 코드에서도 `knitCardigan ↔ tshirt`가 차단됐으므로 구버전 설치만의 문제는 아니었다.
- 이를 계기로 자동 기준 옷 선택은 같은 구조 중심으로 유지하되, 사용자가 직접 고르는 확장 비교에서는 반팔·민소매 상의끼리 공통 핵심 실측 2개 이상이면 구조군 간 비교를 허용했다.
- 정책 행렬에서 반팔 니트 ↔ 반팔티·민소매·반팔 셔츠·반팔 스웨트·반팔 후드는 허용하고, 긴팔티·긴팔 셔츠·긴팔 니트는 차단했다. 공통 핵심 실측 1개는 차단, 2개부터 허용한다.
- 저장된 canonical metadata나 measurement records가 비어 있어도 상품명·카테고리·scalar 실측으로 반팔 후보를 복원하는 기존 데이터 경로도 검증했다.

### 당시 검증

- 온보딩 UI 테스트 6개와 기본 UI 테스트 5개 통과.
- 빠른 저장 이중 탭 후 토스트 1회·옷장 상품 1개 생성 검증 통과.
- 관련 단위 테스트와 253개 분할 회귀를 수행했다. 마지막 production 수정 이후 단일 전체 스위트 재실행은 아니므로 전체 단일 통과로 표현하지 않는다.
- iPhone 17 Pro Simulator에서 저장 CTA `doubleTap()` 후 토스트 1회와 동일 옷장 상품 1개 생성을 함께 검증했다.
- 253개 분할 실행 중 발견한 긴팔 티↔셔츠, 반팔 니트↔긴팔 니트, 긴 재킷↔반소매 코트의 잘못된 수동 확장을 수정하고 관련 회귀 3개를 다시 통과시켰다.
- 상세 당시 기록은 `Docs/CodexSessionHandoff-20260811.md`에 보존돼 있다.

## 15. 2026-08-12 비교·분류·회귀 작업

### 세 무신사 상품 전수 비교

- 대상 상품 ID: `6566713`, `5020093`, `3467384`.
- production `ShoppingProductViewModel` 등록 경로를 사용하도록 테스트를 보완했다.
- 세 상품의 S/M/L/XL, 6개 하의 실측을 고정 fixture로 보존했다.
- 6개 방향 × 기준 사이즈 4개 = 24개를 실행하고 최고 점수 후보 선택을 검증했다.
- 라이브 전체 실행 2회의 결과가 동일했다.

### 긴바지 fallback 및 기존 데이터

- `product_level_fallback`으로 저장된 명확한 긴바지는 바지/데님 계열, 세트 아님, 긴 길이, 핵심 하의 실측 3개 이상일 때 과거 `canonicalEligibility=false`를 재평가한다.
- 세트, 반바지, 실측 부족, 다른 정책 결정은 복구하지 않는다.
- 무신사 옵션 순서 접두사 `0. S`, `1. M`은 유효 사이즈 토큰에만 적용해 `S`, `M`으로 표시한다.
- 신규 파싱 경로뿐 아니라 홈·비교·결과·기록·내 옷장 저장 화면의 기존 데이터 표시에도 같은 정규화를 적용했다.
- 과거 형태 데이터를 SwiftData에 저장하고 재로드한 뒤 앱 시작과 같은 measurement backfill, 비교, 추천까지 확인했다.

### 카테고리별 라이브 감사

- 입력: `FitMatchTests/CategoryLiveComparisonInputs.json`.
- 생성기: `scripts/build-category-live-comparison-inputs.py`.
- 테스트: `FitMatchTests/CategoryLiveComparisonAuditTests.swift`.
- 결과 문서: `Docs/TestEvidence/CategoryLiveAudit-20260812/report.md`.
- 무신사 일반 10개 세부군 × 3개 + 기타 유입 10개 = 40개.
- 유니클로 일반 7개 세부군 × 3개 + 기타 유입 10개 = 31개.
- 71개 중 70개 로드, 2,970개 조합, 허용 1,757개 모두 추천 성공, 차단 1,213개.
- 동일 파싱 입력의 추천을 두 번 계산했고 전체 라이브 실행도 두 차례 반복했다. 비결정성 및 최고점이 아닌 추천은 0개였다.

### 유니클로 혼합 카테고리 버그 수정

- 공급사 혼합 경로 `셔츠 & 블라우스`, `티셔츠 & 스웨트셔츠`의 특정 단어가 상품명을 덮어쓰던 문제를 수정했다.
- 구체적인 상품명 의류 구조를 혼합 공급사 bucket보다 우선한다.
- 셔츠를 `normalizedSizes()`와 유니클로 소매 추론 후처리에서 반팔·긴팔 티셔츠군으로 덮어쓰지 않는다.
- 최종 실상품 결과:
  - `E488520 옥스포드박시셔츠` → 셔츠
  - `E488448 나일론박시쇼트셔츠(5부)` → 셔츠
  - `E488648 AIRism코튼UT(그래픽T)` → 반팔
- 단위 회귀 2개, 실상품 라이브 회귀 1개, 전체 카테고리 2,970개 조합 재실행이 통과했다.

### 공유확장 자동화 한계

- Safari 상품 페이지와 공유 시트까지는 실행·캡처했다.
- Simulator 시스템 공유 시트가 FitMatch 확장을 노출하지 않아 확장 선택 이후 흐름은 미검증이다.
- 이를 앱 비교 실패로 기록하지 않고 환경 차단으로 분류했다.

## 16. 인수인계 관리 규칙

1. 새 세션은 `AGENTS.md`와 이 파일을 먼저 끝까지 읽는다.
2. 모든 의미 있는 production 수정, UX 정책 결정, 테스트 결과, 새 데이터·문서, 미해결 문제를 작업 종료 전에 이 파일에 누적한다.
3. 이전 내용을 삭제하지 않는다. 정책이 바뀌면 과거 내용은 이력으로 남기고 최신 상태에 변경·폐기 여부를 명시한다.
4. 날짜별 상세 문서는 선택적으로 추가하되, 날짜별 문서만 갱신하고 이 누적 문서를 빠뜨리면 안 된다.
5. 테스트는 실행한 범위와 미실행 범위를 구분하고, 중단·skip·환경 차단을 통과로 기록하지 않는다.
6. 새 세션이 이 파일 하나로 현재 상태·주의사항·다음 작업을 이해할 수 있어야 한다.

## 17. 마지막 날짜별 인수인계 이후 전체 작업 로그

이 절은 `CodexSessionHandoff-20260811.md` 작성 이후부터 2026-08-13 문서 갱신 시점까지 수행한 내용을 누락 없이 다시 정리한 것이다. 위 15절과 일부 중복되더라도 다음 세션이 작업의 이유와 실패했던 접근까지 알 수 있도록 보존한다.

### 17.1 협업·판단 원칙 확정

- 사용자는 무조건적인 찬성을 원하지 않는다. 제품·UX·테스트 제안에는 가장 강한 찬성 근거와 반대 근거를 모두 검토하고, 틀렸다면 명확히 반박해야 한다.
- 이 원칙을 `AGENTS.md`의 `Decision Collaboration` 규칙으로 저장했다.
- 실기기에서만 가능한 사람 검수와 Codex가 수행 가능한 코드·Simulator·실서버 자동 검증을 구분했다.
- 반복 테스트 수 자체를 품질로 보지 않고, production 경로·실제 데이터·기대 결과·부정 경계·결정성을 포함하는지 평가하기로 했다.

### 17.2 UX 감사에서 승인·반영한 흐름

- 첫 옷을 무조건 기준 옷으로 만들지 않고 온보딩에서 등록하는 잘 맞는 첫 옷만 기준 옷 기본 ON으로 처리했다.
- 상품 URL을 다시 입력할 수 있도록 첫 미리보기는 유지하고 중복 읽기 전용 확인 화면만 제거했다.
- 기준 옷 후보 선택 후 다시 확인하는 화면을 제거하고 즉시 비교한다.
- 같은 쇼핑몰·브랜드가 아니라 구조·실측 호환성·실측 유사도가 기준 옷 순위를 결정한다.
- 저장 성공 Alert를 제거하고 토스트로 대체했다.
- 저장 및 비교 후보의 연속 탭을 잠가 중복 저장·중복 계산을 막았다.
- 자동 비교 가능한 동일 종류가 없을 때 새 화면을 추가하지 않고 기존 화면에서 `다른 옷 직접 선택`, `이 상품을 내 옷장에 추가`, `다른 상품 비교하기`를 상태에 맞게 제공한다.
- 다른 상품군과 비교한 뒤에는 기존 결과 화면의 내 옷장 추가 경로를 사용한다.
- 비교 상품을 내 옷장에 저장한 직후 자기 자신을 기준으로 비교하지 않는다.
- 반팔 상품은 반팔티·민소매·반팔 니트처럼 구조가 달라도 공통 핵심 실측 2개 이상이면 사용자가 명시적으로 확장 비교할 수 있다.
- 긴팔은 티셔츠·셔츠·니트 구조를 분리하고 스웨트셔츠·후드만 호환한다.
- 후보가 실제로 0개이면 비활성 선택 버튼을 보여주지 않는다.

### 17.3 세 상품 비교에서 발견한 기존 테스트 방식의 문제와 보완

- 최초 회귀 방식은 테스트에서 `Product`를 직접 조립해 실제 `ShoppingProductViewModel` 변환 경로를 우회했다. 이 때문에 production 앱이 `0. S`를 유지하는 결함을 놓쳤다.
- 이후 라이브 파서 결과를 `ShoppingProductViewModel.apply`와 `makeProductForClosetRegistration`으로 변환하도록 바꿨다.
- 실제 production 경로에서 `makeSizeForm`도 사이즈 정규화를 적용하도록 수정했다.
- 세 상품의 공식 실측 응답을 `ThreeProductActualSizeFixtures.json`으로 고정했다.
- 단순히 추천이 존재하는지만 보지 않고 모든 대상 사이즈를 독립 분석해 선택 결과가 실제 최고 점수인지 검증했다.
- 명확한 긴바지 fallback 복구뿐 아니라 실측 부족, 세트, 반바지, 다른 resolution method는 복구되지 않는 부정 경계를 추가했다.
- 같은 호출 반복과 전체 라이브 재실행 결과를 비교해 비결정성을 검사했다.
- 최종 세 상품 라이브 결과는 24/24 완료됐고 두 실행의 결과 행이 동일했다.

### 17.4 기존 저장 데이터 호환

- 새 상품만 정규화하면 기존 SwiftData의 `0. S`가 홈·결과·기록·등록 화면에서 그대로 보이는 문제를 발견했다.
- `AddComparedProductToClosetSheet`, `CompareFlowSheet`, `RecommendationResultView`, `RecommendationHistoryView`, `HomeView`의 표시 경로를 동일한 `SizeTokenNormalizer` 규칙으로 연결했다.
- DB 원본 문자열은 파괴적으로 바꾸지 않고 사용자 표시와 새 저장값만 정상화한다.
- 구형 scalar 실측만 가진 데이터를 테스트 저장소에 넣고 재로드했을 때 처음에는 추천이 실패했다. 이는 실제 앱 시작 시 수행하는 `MeasurementLegacyBackfillService`를 테스트가 생략했기 때문이었다.
- 테스트에 실제 앱 시작 순서와 공식 measurement record를 반영한 뒤 재로드·backfill·eligibility 복구·추천까지 통과했다.
- 이 시행착오는 앞으로 저장 데이터 테스트에서 model 생성만 하지 말고 앱 lifecycle 보정 단계를 포함해야 한다는 근거다.

### 17.5 긴바지 product-level fallback 정책

- 무신사 상품의 공식 실측이 충분하지만 과거 `canonicalEligibility=false`와 `product_level_fallback`으로 저장돼 비교가 막히는 문제를 수정했다.
- 복구 조건은 하의 대분류, pants/denim family, 상품명에 명시적 바지 계열 표현, 세트 아님, 긴 길이, 허리·엉덩이·허벅지·밑위·밑단·총장 중 3개 이상이다.
- Product와 UserFit 모두 같은 조건으로 재평가하며 resolution method는 `product_level_fallback_resolved`로 기록한다.
- 정책상 거부된 상품을 무조건 허용하는 방식은 사용하지 않았다.

### 17.6 카테고리별 71개 라이브 감사 상세

- 기존 실제 실측 비교 자료에서 상품 ID 순으로 결정적인 표본 manifest를 생성했다.
- 일반 그룹은 플랫폼별 3개, 역사적으로 `기타`로 들어온 그룹은 플랫폼별 10개를 선택했다.
- 실측 증거가 요청 수보다 적은 카테고리는 다른 상품으로 부풀리지 않고 coverage gap으로 남겼다.
- live test는 `ProductURLParserService` → `ShoppingProductViewModel` → `Product/UserFit` → `ComparisonProfileMatcher` → `RecommendationService` production 경로를 사용했다.
- 일반 카테고리는 같은 역사적 세부군의 모든 방향을 실행했고 기타 20개도 모든 방향에서 허용·차단 정책을 확인했다.
- 각 허용 조합은 추천을 두 번 계산하고 대상의 모든 사이즈 분석 최고점과 대조했다.
- 1차와 2차 결과: 선택 71, 로드 70, 파싱 실패 1, 조합 2,970, 허용 1,757, 차단 1,213, 추천 1,757, 근거 부족 0, 비결정성 0, 비최고점 0으로 동일했다.
- 유니클로 `E488923`은 공식 사이즈표는 있으나 베이비 상품 형식을 production 파서가 처리하지 못해 지속 실패했다.

### 17.7 기타 유입 상품의 현재 분류

- 무신사 기타 표본 10개는 현재 후드 또는 스웨트셔츠로 구체화됐다.
- 유니클로 기타 표본 10개는 현재 긴팔 계열로 구체화됐다.
- 무신사 `4.5부 레깅스`, `바이커 레깅스`가 숏 레깅스로 바뀐 것은 상품명과 일치하는 정상 개선으로 판단했다.
- 유니클로 `데님블라우스`의 블라우스 분류와 `데님미니스코츠`의 반바지/스커트팬츠 분류도 합리적인 결과로 판단했다.
- 자동 변화 27건 전체를 무조건 오류로 보지 않고 상품 의미에 따라 정상 개선과 버그 후보를 분리했다.

### 17.8 유니클로 혼합 bucket 버그의 2단계 수정

- 1차 원인: 혼합 공급사 경로의 `블라우스`, `스웨트` 토큰이 명시적인 상품명을 이겼다.
- `ParsedClosetClassification`에서 명확한 상품명 의류 구조를 혼합 bucket보다 우선하고, 혼합 셔츠/블라우스 및 티셔츠/스웨트 bucket을 단일 의류 근거로 사용하지 않도록 수정했다.
- 1차 단위 테스트는 통과했지만 실상품에서는 두 셔츠가 `긴팔`, `반팔`로 다시 변환됐다.
- 2차 원인: `ParsedProductInfo.normalizedSizes()`와 `UniqloProductMetadata.withInferredSleeveDetail()`이 셔츠 구조를 소매 길이 티셔츠 detail로 덮어썼다.
- 두 후처리는 미분류 `.other`에만 길이 detail을 추론하도록 제한했다.
- 최종 라이브 결과는 옥스포드박시셔츠=셔츠, 나일론박시쇼트셔츠=셔츠, AIRism 코튼 UT=반팔이다.
- 수정 후 단위 회귀 2개, 실상품 라이브 3개, 전체 2,970개 조합이 통과했다.

### 17.9 테스트 실행 중 통과로 기록하지 않은 항목

- 개별 Swift Testing 함수 필터가 실제로 0개를 실행하고 `TEST SUCCEEDED`를 반환한 적이 있다. 실행 로그에서 test count를 확인해 이를 통과로 인정하지 않았다.
- 해당 테스트를 독립 suite로 분리해 실제 1개/2개 테스트가 실행됐음을 확인한 뒤에만 통과로 기록했다.
- 전체 `FitMatchTests` 스위트는 대형 코퍼스 테스트가 장시간 실행돼 중단했다.
- 중단 전 신규 혼합 bucket 테스트는 통과했지만, 기존 `manualLengthMismatchAllowsExplicitExtendedComparison` 기대값 2건이 현재 정책과 충돌하는 것도 확인했다.
- 따라서 마지막 production 수정 이후 전체 단일 suite 통과라고 주장하지 않는다.
- 시스템 공유 시트 E2E도 FitMatch 확장 미노출로 중단됐으므로 실행 완료로 기록하지 않는다.

### 17.10 이번 기간의 신규·수정 테스트 자산

- `FitMatchTests/LiveThreeProductComparisonTests.swift`
- `FitMatchTests/ThreeProductActualSizeFixtures.json`
- `FitMatchTests/CategoryLiveComparisonAuditTests.swift`
- `FitMatchTests/CategoryLiveComparisonInputs.json`
- `scripts/build-category-live-comparison-inputs.py`
- `Docs/TestEvidence/CategoryLiveAudit-20260812/report.md`
- 기존 `FitMatchTests/FitMatchTests.swift`, `FitMatchTests/LiveMusinsaValidationTests.swift`의 관련 회귀도 함께 보강했다.

### 17.11 이번 기간의 production 변경 범위

- 분류·정규화: `ParsedClosetClassification.swift`, `ProductURLParserService.swift`, `UniqloParser.swift`, `SizeTokenNormalizer.swift`, `ShoppingProductViewModel.swift`.
- 비교·추천: `ComparisonProfileMatcher.swift`, `RecommendationService.swift`.
- 기존 데이터 표시·저장: `AddComparedProductToClosetSheet.swift`, `CompareFlowSheet.swift`, `RecommendationResultView.swift`, `RecommendationHistoryView.swift`, `HomeView.swift`.
- 앞선 UX 승인 반영: `AddClosetItemViewModel.swift`, `AddClosetItemView.swift`, `FitMatchOnboardingView.swift`, `LinkClosetRegistrationView.swift`, `FitMatchSuccessToast.swift` 및 관련 UI 테스트.
- 현재 working tree에는 그 이전 분류·taxonomy·코퍼스 변경도 함께 존재한다. 위 목록만 선택해 되돌리거나 정리하지 않는다.

### 17.12 인수인계 체계 변경

- `Docs/CodexSessionHandoff.md`를 단일 최신 누적 인수인계서로 지정했다.
- 날짜별 `CodexSessionHandoff-YYYYMMDD.md`는 당시 세부 기록으로 보존한다.
- `AGENTS.md`에 새 세션 시작 시 누적 문서를 끝까지 읽고 의미 있는 작업 종료 전 반드시 갱신하도록 규칙을 추가했다.
- 이 절까지가 마지막 날짜별 인수인계서 이후 현재까지의 최신 작업 범위다.

## 18. 2026-08-13 플랫폼별 기준 옷장 비교 감사

### 목적과 실행 방식

- 사용자 요청에 따라 실제 공식 사이즈표를 production `ProductURLParserService → ShoppingProductViewModel → Product/UserFit → ComparisonProfileMatcher → RecommendationService` 경로로 실행했다.
- 1차는 유니클로 상품을 현재 세부 분류별 기준 옷 1개·대표 사이즈 1개로 `UserFit` 등록하고, 무신사·유니클로의 나머지 라이브 상품을 모두 비교했다.
- 2차는 같은 방법으로 무신사 상품을 기준 옷으로 등록했다.
- 기준 옷은 해당 공급사·현재 세부 분류별 상품 ID 오름차순 첫 상품이며, 여러 사이즈 중 중앙 index 사이즈를 사용했다. 비교 상품과 같은 ID인 기준 옷은 제외했다.
- 자동 후보, strict 직접 비교, 사용자 선택 확장 비교, 실제 추천 생성 실패를 각각 분리해 기록했다.
- 전용 실행 scheme: `FitMatchUniqloReferenceAudit.xcscheme`, `FitMatchMusinsaReferenceAudit.xcscheme`.
- 감사 테스트: `FitMatchTests/CategoryLiveComparisonAuditTests.swift`.

### 범위 한계

- 이번 실행은 기존 라이브 manifest의 71개 공식 실측 표본을 사용했다. 70개가 로드됐고 유니클로 `E488923` 1개는 공식 사이즈표는 있으나 베이비 형식 production 파싱에 실패했다.
- 따라서 활성 73개 전체 세부 카테고리를 채운 전수 감사가 아니다. 현재 공식 실측을 재확인할 수 있는 표본 안에서의 최대 비교이며, 유니클로 기준 9개·무신사 기준 14개만 실제 기준 옷으로 구성됐다.
- 43개 의류·신발 비교 세부 카테고리 전체를 채우려면 부족 카테고리의 공식 실측 상품을 별도 수집한 뒤 동일 harness를 재실행해야 한다.

### 1차 — 유니클로 기준 옷장

- Simulator: iPhone 17 Pro, iOS 26.3.1.
- 기준 옷 9개: 가디건, 긴바지, 긴팔, 롱 레깅스, 반바지, 반팔, 블라우스, 셔츠, 스커트.
- 70개 로드, 621개 쌍 비교.
- strict 직접 비교 허용 45개, 수동 확장 1개, 정책 차단 575개.
- 허용된 직접 비교에서 추천 생성 실패는 0개였다.
- 같은 세부 카테고리인데 자동 후보가 없는 사례 10개, 같은 세부 카테고리 pair 차단 9개가 관찰됐다.

### 2차 — 무신사 기준 옷장

- Simulator: iPhone 17 Pro, iOS 26.3.1.
- 기준 옷 14개: 블레이저, 긴바지, 후드, 코트, 스웨트, 민소매, 셔츠, 재킷, 반바지, 롱 레깅스, 숏 레깅스, 바람막이, 반팔, 긴팔.
- 70개 로드, 966개 쌍 비교.
- strict 직접 비교 허용 62개, 수동 확장 39개, 정책 차단 865개.
- 허용된 직접 비교에서 추천 생성 실패는 0개였다.
- 같은 세부 카테고리인데 자동 후보가 없는 사례 22개, 같은 세부 카테고리 pair 차단 17개가 관찰됐다.

### 발견 사항과 판정

- 정상 차단: 유니클로 유아·키즈 반팔/레깅스/반바지와 성인·공용 무신사 기준 옷의 차단은 성별·연령 정책에 따른 정상 결과다. `E488648`, `E488738`, `E488922`, `E488925` 등이 해당한다.
- 정상 차단: 유니클로 긴팔 셔츠 기준과 반팔·5부 셔츠(`E488280`, `E488448`)의 차단은 승인된 직접 반팔↔긴팔 차단 정책에 따른 정상 결과다.
- 수정 후보 P1: 무신사 `2080488 하프 집업 스웻셔츠`, `2738737 시그니처 레더 패치드 스웻셔츠`가 source category는 맨투맨/스웨트인데 화면상 세부 분류가 `셔츠`로 등록됐다. 실제 셔츠 기준과 비교하면 구조가 다르다며 차단된다.
  - 추정 원인: `스웻셔츠` 표기가 현재 명시 스웨트 키워드의 `스웨트셔츠`와 일치하지 않고, 뒤의 `셔츠` 토큰으로 분류되는 경로.
  - 권장 최소 수정: `ParsedClosetClassification`과 무신사 detail 추론에서 `스웻`, `스웻셔츠`를 스웨트셔츠의 선행 동의어로 처리하고 셔츠 판단보다 먼저 적용한다.
  - 이번 감사에서는 production 코드를 수정하지 않았다.
- `E488923 BT릴랙스핏레깅스(10부·프린트)`는 공식 사이즈표는 있으나 베이비 상품 형식을 production 파서가 처리하지 못해 기준 옷·비교 상품으로 만들 수 없었다. 공급사 데이터 부재가 아니라 키즈·베이비 지원 범위 문제로 확정했다.

### 실행 증거

- `/tmp/FitMatchUniqloReferenceAudit-2.xcresult`: 3개 중 실제 1개 실행·통과, 2개는 의도적으로 skip. 실실행 시간 약 51초.
- `/tmp/FitMatchMusinsaReferenceAudit.xcresult`: 3개 중 실제 1개 실행·통과, 2개는 의도적으로 skip.
- 전용 scheme의 실행 플래그가 없는 첫 시도는 3개 모두 skip됐으며 통과로 계산하지 않는다.

## 19. 2026-08-13 기준옷 선정 선행 원칙 및 등록 전용 검증

### 19.1 순서 정정

- 사용자 지시: 비교를 시작하기 전, 기준옷을 먼저 설정하고 설정한 개수부터 보고한다.
- 기존 9/14는 71개 역사 표본에서만 나온 수치였으므로 전체 기준옷 수로 사용하면 안 된다.
- 29개/26개 중간 후보안도 과거 비교 결과의 표시 detail을 기준으로 했으므로 폐기했다.

### 19.2 사용자 지정 1차 기준

- 총 43개 세부 코드: 상의 9 + 하의 7 + 레깅스 5 + 아우터 18 + 스커트 2 + 원피스 2.
- 길이·구조 변형을 추가해 61~81벌로 늘리는 것은 이 1차의 목표가 아니다. 43개 세부 코드당 한 벌이 먼저다.

### 19.3 현재 로컬 공식 실측 원본 기반 선정 결과

- 근거:
  - 무신사: `NewClothingCorpus-1037-MusinsaFifthEighth-20260806/raw/musinsa/actual_size`에서 실제 API sizes 행이 있는 상품.
  - 유니클로: 로컬 원본 상품 페이지 코퍼스 4개(`raw/uniqlo/products`).
  - 현행 분류: `swift_production_classification_results_cumulative_2560.json`.
- 후보:
  - 유니클로 21개: 상의 4, 하의 3, 레깅스 3, 아우터 9, 스커트 1, 원피스 1.
  - 무신사 22개: 상의 4, 하의 4, 레깅스 3, 아우터 11.
  - 합계 43개는 두 플랫폼에 중복된 세부 코드가 포함된 수다. 43개 세부 카테고리를 모두 커버했다는 뜻이 아니며, 고유 커버리지는 25/43이다.
  - 양쪽 로컬 공식 실측 원본에서 후보가 없는 18개: blouse, hoodie, knit_top, light_padding, long_padding, nine_tenths_leggings, nine_tenths_pants, other_dresses, other_leggings, other_outerwear, other_skirts, padded_vest, shirt, short_padding, short_pants, sweatshirt, three_quarter_pants, vest.

### 19.4 등록 전용 Simulator 실행

- 신규 후보 manifest: `FitMatchTests/ReferenceClosetCandidates.json`.
- 생성 스크립트: `scripts/build-reference-closet-candidates.py`.
- 전용 scheme: `FitMatchReferenceClosetSetup.xcscheme`.
- test: `CategoryLiveComparisonAuditTests.registersOneOfficialMeasurementReferencePerStoredCategoryWithoutComparing`.
- Simulator: iPhone 17 Pro, iOS 26.3.
- 결과: PASS, 182.6초. 43개 후보 모두 `URL parse → Product 생성 → 대표 사이즈 → UserFit 기준옷 객체 생성`에 성공했다.
- 이 테스트는 matcher/recommendation을 호출하지 않으며 비교 0회다. 실제 영구 SwiftData 옷장을 오염시키지 않는 테스트 런의 기준옷 객체 설정이다.

### 19.5 다음 단계 경계

- 이 결과만으로 “유니클로 기준옷 43개”, “무신사 기준옷 43개”가 완성됐다고 말하면 안 된다.
- 유니클로 1차 비교는 유니클로 쪽에 부족한 22개 세부 코드 후보를 공식 실측으로 추가 확보한 뒤 시작한다.
- 무신사 2차 비교도 무신사 쪽에 부족한 21개 세부 코드 후보를 추가 확보한 뒤 시작한다.
- 본 실행 전의 71개 표본 비교 및 9/14 기준옷 audit은 역사적 회귀 증거로만 남기며, 43개 기준옷 전수 테스트 성공으로 해석하지 않는다.

### 19.6 사용량 제안 순서 규칙 (사용자 지시)

- 사용량·시간·비용 또는 테스트 범위가 걸린 요청에서는 싼 절충안부터 제안하지 않는다.
- 앞으로 반드시 다음 순서로 보고한다.
  1. 사용자가 말한 목표를 제대로 완료하는 데 필요한 **충분 예산**.
  2. 재시도·수집 실패·회귀를 포함한 **안전 예산**.
  3. 사용자가 제시한 상한에서의 **절충안**.
  4. 절충으로 포기되는 정확한 범위·근거·위험.
- 예산 추정의 근거가 실제 실행값인지, 이전 실행 기반 추정인지, 계획 가정인지 구분하고, 사용량과 품질 효과를 별도로 설명한다.

### 19.7 등록 검증 정정 및 아노락 팬츠 분류 결함

- 19.4의 `43개 후보 모두 성공`은 Xcode 결과 번들상 테스트 실행 수가 0건이었던 실행을 잘못 해석한 것이므로 철회한다.
- 재설계: Swift Testing의 `-only-testing` 선택이 이 도구체인에서 0건 처리되는 문제를 피하려고 `ReferenceClosetSetupXCTests` XCTest 래퍼를 추가했다. 앱 production 코드는 변경하지 않았다.
- 실제 실행 증거: iPhone 17 Pro (iOS 26.3.1), `ReferenceClosetSetupXCTests/testOfficialMeasurementReferenceRegistration`, 106.074초, **1 test / pass**.
  - 후보 66개(유니클로 26, 무신사 40) 중 실제 기준옷 객체로 등록 가능한 것은 35개(유니클로 10, 무신사 25)였다.
  - 31개는 후보 추출 목표와 공식 실시간 분류가 다르거나 공식 실측이 없었다. 비교는 0회다.
  - 따라서 플랫폼별 43개 기준옷을 만든 뒤 비교한다는 1·2차 전수 비교는 아직 시작할 근거가 없다.
- `6032712 테크라인 립포켓 아노락 팬츠` 회귀 테스트도 실제 실행했다. 공식 경로는 `스포츠/레저 > 하의 > 일자 팬츠`인데 현재 `ParsedClosetClassification`이 이름의 `아노락`을 우선해 `outerwear/anorak`으로 반환한다.
  - `ReferenceClosetSetupXCTests/testAnorakPantsRetainsBottomTaxonomy`: **1 test / 2 failures**, 기대 `bottoms/long_pants`, 실제 `outerwear/anorak`.
  - 원인: `ParsedClosetClassification.resolve`에서 `crossCategoryOuterwearDetail(in: name)`가 명시적 하의 source path보다 먼저 평가된다.
  - 권장 최소 수정(미적용): source path가 하의/바지/팬츠이면 이름의 아우터 키워드로 교차 카테고리를 덮어쓰지 않도록 우선순위를 수정하고 위 회귀 테스트를 통과시킨다.

### 19.8 아노락 팬츠 분류 수정 (사용자 승인)

- 승인 후 `ParsedClosetClassification.resolve`의 아우터 교차 분류에 하의 공식 경로 보호 조건을 추가했다.
  - 하의/바지/팬츠/슬랙스/데님/레깅스/스커트 등 명시 lower-body source path는 상품명 안의 아노락·재킷·패딩 단어보다 우선한다.
  - 아우터 공식 경로에서의 기존 명시 아우터 상품명 보정은 유지된다.
- 검증: iPhone 17 Pro (iOS 26.3.1), `ReferenceClosetSetupXCTests/testAnorakPantsRetainsBottomTaxonomy`.
  - 실제 결과 번들: **1 test / pass / 0 failures**, 실행 0.026초.
  - `스포츠/레저 > 하의 > 일자 팬츠` + `테크라인 립포켓 아노락 팬츠`가 `bottoms/long_pants`로 확정됨.
- 보호 범위 재검증: 동일 XCTest 클래스의 최종 실행은 **3 tests / pass / 0 failures**, 96.041초였다.
  - 아노락 팬츠 하의 보존.
  - 일반 상의 경로의 `라이트 바람막이 재킷`은 여전히 `outerwear/windbreaker`로 교차 보정됨.
  - 기존 공식 실측 기준옷 등록 감사 1건도 함께 재실행됐으며, 비교는 0회다.

### 19.9 플랫폼별 기준옷 후보 재선정 및 실제 교차 비교

#### 테스트 하네스 정정

- 사용자 요청의 43개 코드 기준옷 검증을 위해, 상품명 키워드만으로 후보를 확정하지 않고 `URL parse → 공식 숫자 실측표 → Product/UserFit 등록 → 저장 taxonomy 일치`까지 Simulator에서 확인하도록 보강했다.
- 후보 생성: `scripts/build-reference-closet-target-candidates.py`.
  - 키즈·유아·이너웨어·세트 상품은 성인/공용 기준옷 대체 후보에서 제외한다.
  - 유니클로 상위 경로인 `반팔 & 긴팔`, `원피스 & 스커트`가 각각의 개별 세부 코드로 중복 해석되지 않도록 보정했다.
- 검증 통과 후보 저장: `scripts/build-validated-reference-manifest.py`, `FitMatchTests/ReferenceClosetValidatedUniqlo.json`, `FitMatchTests/ReferenceClosetValidatedMusinsa.json`.
- `CategoryLiveComparisonAuditTests`는 실제 통과한 위 매니페스트를 기준옷으로 로드하도록 변경했다. 이전처럼 71개 비교 샘플에서 임의로 같은 플랫폼 기준옷을 고르지 않는다.
- 무신사 기준옷 탐색은 `MusinsaActualSizeAPIParser`만 사용한다. API/HTML 숫자 실측이 없을 때 사용자 UI가 시도하는 이미지 OCR 복구는 이 카탈로그 감사에서는 실행하지 않는다. OCR 대기 때문에 전체 검증이 멈추거나, 공식 숫자표가 없는 상품을 기준옷으로 오인하지 않기 위한 테스트 경계다. Production 동작 변경은 없다.

#### 기준옷 실제 등록 결과

- Simulator: iPhone 17 Pro, iOS 26.3.1.
- 유니클로 후보 67개(목표 코드가 있는 23개, 현 로컬 표본에서 후보 자체가 없는 코드 20개): 33건 등록 성공, **고유 목표 코드 17개** 확정.
  - `ReferenceClosetValidatedUniqlo.json`에 저장했다.
  - 현재 로컬/공식 표본의 한계로 43개 플랫폼별 기준옷에는 도달하지 못했다.
- 무신사 후보 111개(목표 코드가 있는 38개, 현 로컬 표본에서 후보 자체가 없는 코드 5개): 68건 등록 성공, **고유 목표 코드 30개** 확정.
  - 실행 결과: `Test-FitMatchReferenceClosetSetup-2026.08.13_09-06-52-+0900.xcresult`, **1 test / pass / 0 failures**, 테스트 본문 20.770초.
  - `ReferenceClosetValidatedMusinsa.json`에 저장했다.
- 43개를 모두 채운 것으로 표현하면 안 된다. 현재 검증 가능한 플랫폼별 커버리지는 유니클로 17/43, 무신사 30/43이다.

#### 1차 — 유니클로 기준옷 교차 비교

- 기준옷: 검증 완료 유니클로 17개.
- 대상: 기존 공식 실측 라이브 manifest 71개 중 70개 로드(무신사 40, 유니클로 30). 유니클로 1개는 현재 사이즈표를 확보하지 못했다.
- 실행 결과: `Test-FitMatchReferenceClosetSetup-2026.08.13_09-09-32-+0900.xcresult`, **1 test / pass / 0 failures**, 테스트 본문 86.213초.
- 쌍 비교 1,190개:
  - strict 자동/직접 비교 허용 67개
  - 사용자 선택 확장 비교 52개
  - 정책 차단 1,071개
  - 추천 생성 실패 **0개**
  - 같은 세부 구조 기준옷이 없어 자동 후보가 없는 대상 13개
  - 기준옷 17개 한계 때문에 같은 세부 구조 reference 자체가 없는 대상 31개
- 차단의 예: 유니클로 베이비 반팔·반바지와 성인/공용 기준옷의 연령·성별 차단, 서로 길이 구조가 다른 스커트 차단은 정상 보호 결과다.

#### 2차 — 무신사 기준옷 교차 비교

- 기준옷: 검증 완료 무신사 30개.
- 대상: 동일하게 실제 로드된 70개.
- 실행 결과: `Test-FitMatchReferenceClosetSetup-2026.08.13_09-11-26-+0900.xcresult`, **1 test / pass / 0 failures**, 테스트 본문 52.072초.
- 쌍 비교 2,097개:
  - strict 자동/직접 비교 허용 71개
  - 사용자 선택 확장 비교 134개
  - 정책 차단 1,892개
  - 추천 생성 실패 **0개**
  - 자동 후보 없음 28개
  - 같은 세부 구조 reference 자체가 없는 대상 4개
- 자동 후보 없음이 유니클로 기준보다 늘어난 것은 버그로 단정하지 않는다. 무신사 기준옷의 카테고리 폭이 넓어 수동 확장으로는 비교 가능하지만, 자동 비교는 성별·길이·구조 안전 규칙에 따라 후보를 제외하는 경우가 있기 때문이다.

#### 발견된 수정 후보와 미확정 항목

- P1 후보: `short_pants` 공식 source 분류 상품(예: 무신사 `1388516`, `1884480`, `2273549`)이 현재 모두 `bottoms/shorts`로 저장된다. 사용자 정의 43개 taxonomy에서 `숏팬츠`와 `반바지`가 독립 코드라면 source-to-taxonomy 매핑 결함이다. 다만 두 코드를 제품 비교상 별도로 유지할지 먼저 정책 확인이 필요하다.
- P1 후보: `light_padding`, `short_padding`, `padding`, `padded_vest`는 후보의 이름·원본 경로와 현재 저장 코드가 여러 방식으로 엇갈린다. 일부는 후보 선택기의 상위 경로 오인, 일부는 `경량 패딩`을 `패딩`으로 합치는 실제 parser 결과다. production 수정 전 각 target에 대해 실제 공식 source path가 명시된 대체 후보를 더 확보해 재현해야 한다.
- P2 후보: `mouton` 공식 원본 경로가 레더/라이더 재킷으로만 온 상품은 현재 `jacket`으로 저장될 수 있다. 원본 쇼핑몰 taxonomy에 무스탕 전용 code가 없을 때 이름 기반 보정을 어디까지 허용할지 정책 결정이 필요하다.
- 테스트 하네스 발견: 한 XCTest에 이미지 OCR fallback 후보 111개를 묶으면 Simulator가 약 69초 후 재시작해 결과 번들이 손상됐다. 이 실행은 무효로 폐기했다. actual-size API 전용으로 바꾼 후 111개 probe는 20.770초에 정상 완료됐다.

#### 다음 작업 경계

- 아직 각 플랫폼 43개 기준옷을 채우지 못했으므로, 이 결과는 **검증 가능한 공식 실측 표본 70개에 대한 부분 교차 감사**다. 43×각 플랫폼 전수 비교 성공으로 표현하지 않는다.
- 다음 단계는 부족 코드별로 공개 공식 카탈로그에서 성인 단품·공식 숫자 실측 상품을 수집하고, 동일 Simulator 등록 probe를 통과한 뒤 유니클로 43개·무신사 43개 매니페스트를 확정하는 것이다.
- 그 후에만 1차/2차를 43개 기준옷 전체로 재실행한다. 이번 단계에서는 production 분류·비교 로직을 추가 수정하지 않았다.

## 20. 2026-08-13 카테고리 증거 우선순위 데이터 감사

- 사용자와 다음 방향을 합의했다: 공식 공급사 경로에서 명확한 의류 대분류를 찾으면 자동 분류에서 잠그고, 상품명·실측은 이를 몰래 뒤집지 않는다. 세부분류가 기타·복합·누락일 때만 상품명과 실측을 보조 근거로 사용하며, 끝까지 모호하거나 강하게 충돌하면 사용자에게 2~3개 후보와 사유를 제시한다. 사용자 선택은 우선 로컬에 저장한다.
- 구현 전에 기존 코퍼스로 정책 영향을 측정하기 위해 `scripts/audit-category-evidence-policy.py`와 `Docs/Research/CategoryEvidencePolicyAudit-20260813/`를 생성했다. Production 앱 코드는 이 단계에서 변경하지 않았다.
- 기준 모집단은 누적 5,026개 고유 상품이다: 기존 2,560 + 신규 2,000 + fresh 466. 별도 supplement 726개는 외부 검증군으로 분리했다.
- 휴리스틱 공식 경로만으로 대분류 잠금 후보 5,012/5,026, 미해결 13, 내부 충돌 1이 나왔다. 이 수치는 문자열 휴리스틱의 coverage 추정이지 정확도 확정값이 아니다.
- 기존 canonical decision bundle을 공식 ID/경로로 연결하면 4,563/5,026이 매칭됐다: confirmed 3,891, review_required 336, rejected 336, 미매칭 463.
- 현재 runtime 결과가 존재하면서 canonical bundle의 앱 매핑과 다른 행은 90개다. 대표적으로 아노락 팬츠, 언더웨어 쇼츠, 라운지 팬츠, 팬츠&레깅스 혼합 버킷이 포함된다.
- canonical bundle도 정답지로 취급하면 안 된다. 일부 니트/스웨터 공식 경로가 아우터/가디건으로 광범위하게 매핑되는 등 현재 제품 정책과 충돌하는 결정이 관찰됐다. 따라서 90개를 유형별로 사람 판정한 후 정책·코드를 변경해야 한다.
- 상품명과 공식 경로의 단순 어휘 충돌은 170개였지만 언더웨어 쇼츠·바이커 쇼츠처럼 실제 대분류 충돌이 아닌 문맥 사례가 많다. 단순 단어 충돌마다 사용자 확인을 띄우면 UX가 과도하게 방해되므로 복합 표현과 공급사 카테고리 ID를 우선해야 한다.
- 사용자 최종 목표를 다음으로 확정했다: 공식 카테고리 정규화로 내 옷장 카테고리 선택과 비교 기준 옷 선택 횟수를 최대한 줄이고, 자동화가 어쩔 수 없이 모호할 때는 사용자의 판단을 최종값으로 사용한다. 그 판단을 로컬에 저장해 동일 상품 재분석 시 다시 묻지 않는다.
- 기존 `SourceCategoryHistoryMatcher`가 사용자 선택을 로컬 `UserDefaults`에 저장하고 비교 흐름에서 재사용하는 기반을 이미 갖고 있음을 확인했다. 다만 이전 구현은 한 상품의 선택을 공급사 category path 전체에 저장해 `기타 상의` 같은 혼합 bucket의 다른 상품까지 잘못 자동 분류할 수 있었다.
- 이를 상품별 공급사 식별자(`sourceType + sourceName + productCode`) 우선 저장·조회로 변경했다. 안정적인 상품 ID가 있는 상품은 과거 path-wide 단일 선택을 적용하지 않고, 동일 경로의 다른 상품은 옷장 이력 집계가 실제로 일치할 때만 후보가 된다. 상품 ID가 없는 수동/구형 데이터만 기존 path fallback을 유지한다.
- 비교 흐름뿐 아니라 비교 상품을 내 옷장에 저장할 때 사용자가 확정한 카테고리도 동일 로컬 매핑에 저장하도록 연결했다.
- 회귀 검증:
  - `userCategoryChoiceIsReusedForTheExactProviderProductOnly`: 실제 1 test / pass. 동일 상품은 선택을 재사용하고 같은 기타 경로의 다른 상품에는 전파하지 않는다.
  - `shortSleeveSourceHistoryDoesNotOverrideDetectedLongSleeve`: 실제 1 test / pass. 저장 이력이 명확한 길이 충돌을 덮어쓰지 않는 기존 보호를 유지한다.
- 사용자 전제를 추가로 명확히 했다: 사용자는 해당 옷을 어느 내 옷장 카테고리에 넣고 어떤 옷과 비교할지 알고 있으며, 모호한 경우 사용자의 선택이 최종 정답이다. 시스템은 사용자를 대신해 속단하는 것이 아니라 반복 선택을 줄이고 안전한 비교 후보를 좁히는 역할이다.
- 이 전제에 맞춰 명확한 공식 상의/하의/아우터 대분류는 상품명으로 뒤집지 않도록 잠갔다. 상품명에 `아노락`, `바람막이`, `브라`, `홈웨어`가 포함되어도 공식 대분류가 명확하면 대분류를 변경하지 않고, 공식 대분류가 `.other`일 때만 제한적으로 보완한다.
- 유니클로 공식 경로에서 어떤 대분류 근거도 찾지 못했을 때 기존처럼 `.top`으로 기본 확정하지 않고 `.other`를 반환하도록 변경했다. 이후 제한적 보완으로도 확정되지 않으면 사용자 선택 단계로 넘겨야 한다.
- 관련 XCTest 3건(`testAnorakPantsRetainsBottomTaxonomy`, `testOfficialTopTaxonomyIsNotOverriddenByOuterwearName`, `testOuterwearNameCanResolveMissingOfficialMajorCategory`)은 iPhone 17 Pro Simulator에서 3/3 통과했다. 결과: `Test-FitMatch-2026.08.13_10-25-04-+0900.xcresult`.
- 동일 상품에 저장된 사용자 선택은 이후 파서 추정과 충돌해도 최종값으로 반환하도록 변경했다. 공식 경로별 옷장 이력 후보에는 기존 대분류·길이 충돌 보호를 유지하고, 정확한 공급사 상품 ID에 사용자가 직접 저장한 답만 이 보호보다 우선한다.
- 자동 정규화가 유효한 경우 `CompareFlowSheet`가 raw parser category가 아니라 `ParsedClosetClassification`의 canonical category/detail을 화면 상태에 반영한 뒤 진행하도록 수정했다. 공식 대분류 누락을 제한적 fallback으로 해결한 경우에도 실제 비교 분류와 UI 상태가 일치한다.
- 분류 선택 안내 문구는 “같은 쇼핑몰 카테고리” 전체에 적용된다는 잘못된 표현을 제거하고, 선택이 “이 상품”에 저장되어 재사용된다고 명시했다.
- 비교 상품을 옷장에 저장할 때 garment family/length/construction/normalized type을 과거 parser 결과가 아니라 사용자가 최종 선택한 category/detail로 다시 계산하도록 수정했다. 화면의 저장 카테고리와 내부 비교 프로필이 서로 다른 상태를 막는다.
- 추가 검증:
  - 사용자 선택/경로 보호/유니클로 unknown 기본값 관련 4 tests / pass. 결과: `test_sim_2026-08-13T01-31-55-448Z_pid17306_7e3a8aa7.xcresult`.
  - 자동 기준옷 선택 안전 조건 11 tests / pass. 유효한 대표 기준옷 하나만 자동 선택하고, 비대표 단일 후보·복수 유사 후보·근거 부족은 사용자 선택을 유지한다.
  - 2,560개 production 분류 export 회귀 1 test / pass. 결과: `test_sim_2026-08-13T01-35-25-491Z_pid17306_bc49f946.xcresult`.
  - P0 production path 전체 22 tests / pass. 여기에는 모호한 무신사 기타 상의가 사용자 확인을 요구하는 검증이 포함된다. 결과: `test_sim_2026-08-13T01-36-06-465Z_pid17306_1f1daf65.xcresult`.
  - 최종 수정 후 iOS Simulator app build / success.
- 5,026개 증거 감사 스크립트를 최종 수정 상태에서 다시 실행했다. 입력 5,026/고유 5,026/중복 0, 공식 경로 lock 후보 5,012, conflict 1, unresolved 13으로 재현됐다. 현재 runtime label과 경로 정책의 단순 mismatch는 138개이며, canonical bundle과 runtime mapping mismatch 90개는 그대로다. 앞 수치는 판정 정확도가 아니라 검토 대상을 찾는 coverage 지표다.
- 실제 UI 완료 감사를 위해 Debug 전용 `-fitmatchAmbiguousCategoryFixture`와 로컬 매핑 초기화 인자를 추가하고, `testAmbiguousCategoryChoiceIsReusedForTheExactProduct` UI 테스트를 만들었다. Release 동작에는 포함되지 않는다.
- UI 테스트는 첫 실행에서 `스포츠/레저 > 상의 > 기타상의` 상품이 `FitMatch 분류 연결` 화면을 표시하는지 확인하고, 사용자가 `상의/반팔`을 선택한 뒤 비교 단계까지 진행한다. 앱을 종료해 in-memory closet을 새로 만든 후 같은 공급사 상품 ID로 다시 분석했을 때 분류 연결 화면 없이 비교 단계로 바로 진행하고, 재질문하지 않는 것을 검증한다.
- 실제 실행 결과: `test_sim_2026-08-13T01-56-06-137Z_pid17306_492790b7.xcresult`, **1 UI test / pass / 0 failures**, 53.3초.
- 동일 구조의 안전한 대표 기준옷 하나가 있을 때 자동 선택되는 별도 회귀 `singleExactRepresentativeForUserResolvedCategoryIsAutomaticallySelected`도 통과했다. UI fixture에서는 비교 프로필이 확장 후보로 판정되어 사용자 기준옷 선택을 유지했으며, 이는 함부로 자동 선택하지 않는 안전 정책에 해당한다.
- 최종 `git diff --check` 통과. 보호 파일 `TabBarScrollVisibilityModifier.swift` 및 보호 modifier call site 변경 없음.

## 21. 2026-08-13 카테고리 병렬 정확도 감사

- 다른 세션의 공식 기준옷 교차 테스트와 중복되지 않게 공식 70개 runtime 결과, 5,026개 코퍼스 위험 보정, 사용자 선택/기준옷 회귀를 병렬 감사했다.
- 5,026개 감사의 `runtime-vs-heuristic 138건`은 검증된 오류 수가 아니다. 감사 휴리스틱이 `후드 집업`의 `후드`를 상의로 읽어 명백한 아우터 28건을 오탐했다. `name conflict 170건`도 부분 문자열 오탐을 포함하므로 정확도 지표로 사용하지 않는다.
- 고위험 후보는 언더웨어 쇼츠→하의 31건, 아노락/윈드브레이커 팬츠→아우터 4건, 쇼트 재킷/커버롤 재킷→하의 4건, 명시 상의 경로를 이름만으로 아우터화한 최소 8건이다. 라운지/파자마 26건은 형태 분류와 용도 분류 중 어느 쪽을 우선할지 정책 판정이 필요하다.
- canonical `review_required` 336건 중 332건과 canonical 미등록 463건 중 최소 437건은 공식 경로만으로 대분류를 잠글 수 있는 잠재치다. 현재 production UI가 canonical status 자체로 묻지는 않지만, 세부분류가 모호하다는 이유로 대분류까지 초기화하지 않도록 계속 보장해야 한다.
- 공식 70개 로그에서 실제 세부분류 오류를 발견했다. `상의 > 맨투맨/스웨트`의 `하프 집업 스웻셔츠`, `시그니처 ... 스웻셔츠`가 영문/한글 `셔츠` 부분 문자열 때문에 `셔츠`로 저장됐다. `스웻셔츠` 변형을 sweatshirt로 먼저 처리하고 영문 `shirt`는 단어 경계일 때만 인정하도록 수정했다.
- 회귀 `musinsaSweatshirtNamesDoNotBecomeShirtsBySubstring`은 iPhone 17 Pro Simulator에서 통과했다. 결과: `test_sim_2026-08-13T03-26-12-868Z_pid35760_e5b8d7a4.xcresult`.
- 최신 공식 70개(무신사 40/유니클로 30) source-path 대조 결과 대분류 역전 0, other/기타 0, 불필요 사용자 확인 0이다. 수정 전 live 결과의 명백 detail 오분류는 위 스웻셔츠 2/70이었다. 복합 세트 1건, 반소매 스웨트 1건, 반팔 니트 2건은 길이와 구조 taxonomy 중 무엇을 우선할지 정책 검토 대상으로 남겼다.
- 기존 handoff에 pass로 인용된 일부 Swift Testing 결과 번들(`01-20-07`, `01-21-45`, `01-31-55`, `01-33-38`, `01-35-25`)은 `xcresulttool` 직접 조회에서 totalTestCount=0/result=unknown이었다. 해당 주장은 유효 증거에서 철회한다. 유효한 증거는 UI persistence 1/1, P0 22/22, 분류 잠금 XCTest 3/3이다.
- 같은 공급사 경로의 다른 상품으로 사용자 선택이 전파되지 않음을 실제 실행으로 보강하기 위해 P0 XCTest `p0ExactProductCategoryChoiceDoesNotSpreadToSiblingProduct`를 추가했고 1 test / pass를 확인했다. 결과: `test_sim_2026-08-13T03-33-22-082Z_pid35760_1d31caf6.xcresult`.
- 기준옷 정책의 정확한 현재 동작: 복수 일반 후보는 사용자 선택을 유지하지만, exact detail/direct compatible로 사용자가 대표 기준옷을 여러 개 지정한 경우에는 가장 최근 대표옷 하나를 자동 선택한다. “모든 복수 후보는 수동”이라고 표현하면 안 된다.

## 22. 2026-08-13 카테고리 단독 최종 production 검증

- 사용자가 병렬 세션 대신 이 세션 단독 진행을 선택했다. 실행 ID는 `CategoryValidation-20260813T153530+0900`, 시작 HEAD는 `49834c7332e7d4f64639e6a7068373afc423d35c`, Simulator는 iPhone 17 Pro / iOS 26.3.1이다.
- 최종 보고서와 원본 증거는 `Docs/TestEvidence/CategoryValidation-20260813T153530+0900/`에 있다. 최종·수정 전 실패·0-test 제외 번들은 `test-evidence-index.json`에서 구분한다.
- 수정한 production 결함:
  - 혼합 니트/가디건 경로의 최하위 leaf와 명시적 가디건 보존.
  - 공식 major 누락 시 parser detail+상품명에 모두 명시된 스웨트만 제한 복구.
  - `other/other` placeholder 자동확정 금지.
  - 스웨트풀집파카를 패딩이 아닌 `outerwear/jumper`로 처리.
  - 명백한 복합 세트를 자동 단일 카테고리로 확정하지 않음.
  - 팬츠/레깅스 혼합 경로에서 아래에서 위로 가장 가까운 단일 가족 노드를 적용. 5,026개 전수 diff는 의도한 8개 팬츠만 교정됐고 명시 레깅스 3개는 보존됐다.
- 시작/종료 production hash 비교에서 변경된 production 파일은 `ParsedClosetClassification.swift`, `UniqloParser.swift`, DEBUG UI fixture용 `ProductURLParserService.swift` 세 개다. 다른 production 파일의 중간 동시 변경은 없었다.
- 공식 70개 최종 재수집:
  - 실제 XCTest 2/2 pass.
  - raw 142 = 71 manifest × 2 audits, 고유 71, 로드 70, 파싱 실패 `E488923` 1건.
  - 동일 실행에서 `products.json`, `combinations.json`, `summary.json`, `report.md` 생성, 교차 산출물 불일치 0.
  - 3,707 combinations = direct 135, base extended 43, manual extended 219, blocked 3,310.
  - 허용 비교 추천 실패 0, 차단 복구 경로 누락 0, 스웻셔츠 `2080488`/`2738737` 모두 `tops/sweatshirt`.
  - 기존 `Docs/TestEvidence/OfficialMeasurementComparison-20260813` 네 핵심 산출물도 이 동일 실행 파일로 교체했다.
- 현재 Swift production 분류기 5,026개 최종 전수:
  - 실제 XCTest 1/1 pass, 입력/고유/출력 모두 5,026, taxonomy invalid 0.
  - offline 자동 4,697, 후보 329. 후보 329개를 실제 `ProductURLParserService → ShoppingProductViewModel → canonical` 경로로 재수집했고 실제 XCTest 1/1 pass, live success 329/failure 0.
  - 최종 자동 진행 4,978, 사용자 확인 48, 위험 placeholder 자동확정 0.
  - 확인 48 = 베이비 커버올/살로페트 9, 복합 세트 36, 기타 진짜 모호 3.
- 감사 도구도 production 결과와 함께 검증했다. 과거 저장 경로와 live source path를 섞지 않게 overlay하고 후드집업 compound를 처리했다. 기존 138건은 버그 수가 아니며 최종 heuristic 후보는 18건, 후드집업 오탐은 0이다.
  - 남은 18건은 스코츠 8, 이너웨어 레깅스 7, 속바지 1, 이너웨어 크루넥T 1, 명시 가디건 1의 형태-vs-판매목적 정책 경계다. 검증된 자동 대분류 버그로 세지 않는다.
  - 라운지 공식 경로는 현재 목적 우선 `homewear/loungewear` 정책이다. 일반 팬츠 형태를 우선할지는 별도 제품 정책 변경이다.
- 고위험 실상품 결과: 아노락/윈드브레이커 팬츠 6개 `bottoms/long_pants`, 언더웨어 쇼츠 `underwear`, 쇼트 재킷/커버롤 4개 `outerwear/jacket`, `E488939` `outerwear/jumper`, `E450540` `outerwear/cardigan`, 복합 세트는 사용자 확인.
- Simulator UI XCTest 1/1 pass로 최초 선택 → 종료/재실행 → 동일 상품 재질문 없음 → 같은 경로 다른 product ID에는 전파 없음 → mapping 초기화 후 원상품 재질문을 한 흐름에서 증명했다.
- 최종 경계/고위험 XCTest 8/8 pass, P0 production 전체 23/23 pass. 잘못된 suite filter로 0건 실행된 두 번은 명시적으로 제외했고, 테스트 시작 전 샌드박스/빌드 실패도 성공 증거로 사용하지 않았다.
- 현재 판단: 이번 데이터와 회귀 범위의 성인 카테고리 로직 수정·자동 검증은 완료됐다. 실제 아이폰에서는 문구·화면 전환 체감만 소수 확인하면 된다. 베이비 전용 taxonomy/비교 정책은 아직 별도 작업이며 `E488923`도 공식 parser 실패라 베이비 완전 지원으로 표현하면 안 된다.
- `git diff --check` 통과. 보호 파일과 보호 modifier call site는 변경하지 않았다.

## 23. 2026-08-13 하의 길이 안내 문구 수정

- 비교 가능한 옷 안내에서 공용 길이 값 `long`이 항상 `긴팔`로 표시되어 팬츠가 `긴팔 팬츠`로 노출되던 문구 오류를 수정했다.
- 길이 표시를 의류군 문맥에 맞게 분리했다. 팬츠/데님은 `긴바지`, `반바지`, `7부 팬츠`, `9부 팬츠`, `크롭 팬츠`로, 레깅스는 레깅스 전용 문구로 표시한다. 상의의 `긴팔`/`반팔` 표현은 유지한다.
- 비교 가능 여부·카테고리 분류·추천 계산 로직은 변경하지 않았고 화면 표시 조합만 수정했다.
- 동일 오류 재발 방지를 위한 길이 문구 단위 테스트를 추가했다. 사용자 요청에 따라 Simulator는 실행하지 않았다.

## 24. 2026-08-13 기준 옷 직접 선택 UX 문구 수정

- 자동 기준 옷이 없는 상태가 오류처럼 보이지 않도록 `기준 옷을 직접 선택해 주세요`와 `내 옷장에서 기준 옷 선택` 중심의 다음 단계 안내로 변경했다.
- 직접 선택 화면은 `기준 옷 직접 선택`으로 제목을 바꾸고, 자동 선택할 기준 옷이 없어 사용자가 직접 고르는 단계임을 명시했다.
- 직접 선택한 옷은 이번 비교에만 기준으로 사용되며 기존 기준 옷 설정은 변경되지 않는다고 안내한다.
- 이 흐름의 `이 상품을 내 옷장에 추가` CTA를 모두 제거했다. 비교 가능한 옷 자체가 없을 때는 `다른 상품 비교하기`만 제공한다.
- 관련 UI 테스트와 비교 감사의 기대 문구를 새 UX에 맞게 갱신했다. 사용자 요청에 따라 Simulator는 실행하지 않았다.

## 25. 2026-08-13 폴로셔츠 비교군 정책 수정

- 폴로셔츠·피케셔츠·카라티를 일반 직물 셔츠가 아닌 `tshirt` 비교 구조군으로 변경했다.
- 같은 소매 길이의 폴로셔츠↔일반 티셔츠와 폴로셔츠↔폴로셔츠는 자동 비교할 수 있다.
- 폴로셔츠↔와이셔츠·옥스포드셔츠·블라우스의 기존 `tshirt↔shirt` 예외 허용을 제거해 자동 비교를 차단한다.
- 과거 `shirt`로 저장된 폴로셔츠도 상품명·원본 카테고리 증거가 있으면 런타임에서 `tshirt`로 교정한다. canonical `polo_shirt`의 앱 변환도 `tshirt`로 변경했다.
- 관련 회귀 테스트를 새 정책에 맞춰 변경하고 일반 셔츠 차단 테스트를 추가했다.
- Simulator를 실행하지 않은 iPhoneOS Debug 앱 빌드는 성공했다. 테스트 타깃 build-for-testing은 샌드박스의 SwiftPM 캐시 쓰기 제한으로 실행되지 않았으며 코드 실패 증거가 아니다.

## 26. 2026-08-13 폴로셔츠 앱 세부분류 보완

- 직전 수정은 폴로셔츠의 비교 구조군만 `tshirt`로 바꾸고 앱 세부분류를 `shirt`로 남긴 불완전한 수정이었다.
- 앱 taxonomy `2026.08.2`에 활성 `tops/polo_shirt`(`상의 > 폴로셔츠`)를 추가하고 `ClosetDetailCategory.poloShirt`를 연결했다.
- 무신사 `피케/카라 티셔츠`와 유니클로 `폴로셔츠(카라티)` 경로 및 명시적 폴로 상품명은 이제 `상의 > 폴로셔츠`로 저장·표시한다.
- 비교 구조군은 계속 `tshirt`이고 소매 길이는 별도 축으로 유지한다. 따라서 같은 소매 길이의 일반 티셔츠와 자동 비교하고 일반 직물 셔츠·블라우스와는 차단한다.
- 폴로 분류·길이·비교 구조군 회귀 기대값을 보강했다. Simulator 없이 iPhoneOS Debug 앱 빌드가 성공했다.

## 27. 2026-08-13 출시 전 1,200건 증거 재감사

- 사용자 요청으로 계정 잔여 사용량 75%에서 시작해 65% 도달 시 중단하는 목표를 설정했다. 계정 잔여율은 세션 도구에서 직접 조회할 수 없으므로 사용자 또는 시스템 표시값이 필요하다.
- Simulator를 새로 실행하지 않고, 기존에 production 경로로 실행된 실제 공식 실측 비교 결과와 matcher 차단 결과를 현재 5,026개 분류 원장에 다시 대조했다.
- `scripts/build-release-qa-1200.py`를 추가했다. 입력은 무신사 비교 엔진 실행 597건, 유니클로 비교 엔진 실행 180건, 공식 교차 matcher 3,707건, 현재 분류 5,026건이다.
- 과거 실행 카테고리와 현재 분류가 달라진 36건은 통과 증거로 사용하지 않고 `excluded-stale-evidence.json`으로 분리했다. 주요 변화는 하의→레깅스/스커트/홈웨어/아우터 정규화다.
- 최초 원장은 무신사/유니클로 대상 비율이 907/293으로 불균형해 완료 근거에서 제외하고 균형 원장으로 교체했다.
- 최종 원장은 무신사 대상 600건, 유니클로 대상 600건이며 기준 옷 ON 600건, OFF 600건이다.
- 최종 결과는 PASS 1,200 / FAIL 0이다. 실행된 실측 비교 엔진 771건, production matcher 허용 57건, production matcher 차단 372건이다. 차단은 길이 68, 성별·연령 54, 의류 구조 250이다.
- 흐름은 자동 기준 옷 414건, 수동 기준 옷 선택 414건, 기준 옷 ON 상태 차단 186건, 기준 옷 OFF 상태 자동 후보 없음 186건이다. 자동/수동 UI를 새 앱 바이너리로 다시 실행한 결과가 아니라 실행된 pair 증거에 현재 선택 정책을 적용한 시나리오임을 구분한다.
- 10건 단위 120개 배치 원장을 `Docs/TestEvidence/ReleaseQA-1200-20260813/batches.json`에 생성했고 모든 배치가 10/10 PASS다.
- 상세 원장과 요약은 `Docs/TestEvidence/ReleaseQA-1200-20260813/cases.json`, `summary.json`이다.
- 사람이 읽는 최종 판정은 `Docs/TestEvidence/ReleaseQA-1200-20260813/report.md`에 추가했다.
- Excel 생성에 필요한 Spreadsheets skill의 `load_workspace_dependencies` 기능이 현재 세션에 제공되지 않고 연결된 Excel document session도 없어 `.xlsx` 작성은 아직 완료하지 못했다. 다른 라이브러리로 우회하지 않았다.

## 28. 2026-08-13 실제 iPhone 1,280 fixture 추가 검사

- 연결된 `이진영의 iPhone`(iPhone 14 Pro, iOS 26.6, UDID `00008120-001E08612290C01E`)에 개발 서명 테스트 빌드를 설치해 무신사 1,037개와 유니클로 243개 공식 API fixture를 production 파서·분류·비교 경로로 검사했다. 개인 옷장이나 Supabase에 1,280개 상품을 저장한 검사가 아니라 테스트 호스트 메모리에서 처리한 검사다.
- 최초 설치는 무선 연결 중단으로 실패했으나 재연결 후 실행됐다. 이 실패는 로직 결과에 포함하지 않는다.
- 실기기에서 `lookbehind is not currently supported` 오류를 발견했다. `ParsedClosetClassification`, `ProductURLParserService`, `MusinsaFallbackSizeParser`의 lookbehind를 iOS 호환 경계식으로 교체했고 production/test 전체에서 lookbehind 패턴 0개를 확인했다.
- 유니클로 243개 최종 엄격 결과: 통과. 비교 가능 238개, 실측 행 1,574개, confirmed 비교 쌍 184개다. 제외 5개는 베이비 커버올 4개 taxonomy 미지원과 공식 실측 행이 없는 와이어리스 브라 1개다. 결과 번들 `/tmp/FitMatchPhysicalUniqlo243Excluded.xcresult`.
- Swift Testing 함수를 XCTest에서 직접 호출하면 `#expect` 실패가 XCTest 실패로 전파되지 않는 하네스 결함을 발견했다. corpus 핵심 검증을 `try #require`로 변경해 불일치가 반드시 실기기 테스트 실패가 되게 했다.
- 무신사 1,037개는 최초 비엄격 브리지 실행에서 173.829초에 처리 완료했지만, 엄격 브리지로 바꾼 통합 실행과 단독 재실행은 모두 약 76초에 테스트 호스트가 `signal kill`됐다. assertion 실패는 관찰되지 않았지만 엄격 통과로 주장하지 않는다.
- 다음 필수 작업은 무신사 1,037개를 100~200개 단위의 독립 XCTest 배치로 분할해 각 배치의 strict assertion을 실제 iPhone에서 실행하는 것이다. 현 상태에서 유니클로는 실기기 통과, 무신사는 실기기 하네스 안정성 때문에 미확정이다.
- 상세 요약은 `Docs/TestEvidence/ReleaseQA-1200-20260813/physical-device-1280-summary.json`, 사람용 설명은 같은 폴더의 `report.md`에 기록했다.
- `.xlsx`는 스프레드시트 스킬이 요구하는 `load_workspace_dependencies`가 이 세션에 없어 계속 차단 상태다. 우회 라이브러리는 사용하지 않았다.

## 29. 2026-08-14 사용자 안내 문구 31개 흐름 전수 정비

- 사용자가 확정한 온보딩, 홈, 내 옷장, 기준 옷 설정·삭제, 직접·링크 등록, 상품 분석·분류, 기준 옷 없음, 아동·성인 분리, 수동 후보 선택, 실측 부족·제외, 사이즈표 복구, 오류, 결과·기록·브랜드·추천 탭의 문구를 실제 SwiftUI 화면에 반영했다.
- 반팔↔긴팔은 의류 구조 전체를 차단하지 않고 가슴·어깨·총장 등 공통 실측으로 부분 비교하며, 소매길이는 점수와 결과에서 제외하고 `반팔과 긴팔은 소매 구조가 달라 비교에서 제외했어요.`라고 표시한다. 제외 사유는 추천 결과와 참고 비교에도 보존된다.
- 자동 기준 옷이 없을 때 오류처럼 보이지 않도록 `비교할 옷 선택`과 이번 비교에만 사용하는 수동 선택임을 명시했다. 빈 옷장, 필요한 종류 없음, 아동복 없음, 성인복 없음은 가져온 상품·현재 옷장 구성·등록해야 할 종류를 각각 안내한다.
- 결과 화면의 사용자 용어를 `핏 매칭률`에서 `사이즈 유사도`로 통일하고, 추천 신뢰도 산정과 확장 비교 신뢰도 하향 이유를 설명한다.
- 무신사 자동 사이즈표 분석 실패, 이미지 분석 실패, 유니클로 사이즈표 없음, 세트 상품, URL·네트워크 오류 문구를 확정안으로 교체했다.
- 비교 상품의 옷장 등록은 `보유한 옷으로 등록`으로 명확히 하고 실제 보유 상품만 등록하도록 확인 문구를 강화했다.
- 변경된 화면 문구를 참조하는 UI 테스트 기대값도 함께 갱신했다.
- 앱·단위 테스트·UI 테스트 Swift 파일 전체 `swiftc -frontend -parse`와 `git diff --check`를 통과했다. 사용자 요청에 따라 Xcode 빌드와 실기기 화면 확인은 회사에서 후속 수행한다.
- 보호 파일 `FitMatch/Components/TabBarScrollVisibilityModifier.swift`와 보호 modifier 호출부는 변경하지 않았다.

## 30. 2026-08-14 확장 A테스트 5,000건

- 사용자가 별도 건수를 지정하지 않아 직전 합의에서 권장한 확장형 A테스트 5,000건으로 진행했다.
- `scripts/build-release-qa-2000.py`에 `--count` 옵션을 추가하고 현재 안내 문구 계약, 플랫폼 균형, 기준 옷 ON/OFF 균형, 고유 상품 쌍·상태 및 커버리지 집계를 반영했다. `scripts/build-release-qa-1200.py`는 `insufficient_evidence`를 정상 추천 보류로 검증하도록 수정했다.
- 최초 실행은 4,998/5,000으로 표시됐다. 실패 2건은 같은 재킷 쌍의 ON/OFF 상태로, 앱 오류가 아니라 필수 실측 누락 때문에 정상 `insufficient_evidence`가 된 사례를 생성기가 실패로 잘못 센 것이었다. 생성기 판정을 바로잡고 재실행했다.
- 최종 결과는 5,000/5,000 PASS, 무신사/유니클로 2,500/2,500, 기준 옷 ON/OFF 2,500/2,500이다.
- 결과는 자동 비교 1,247, 수동 선택 1,247, 정상 추천 보류 6, 정상 차단 2,500이다. 차단 사유는 의류 구조 2,214, 길이 구조 178, 성별·연령 보호 108이다.
- 실제 상품 쌍은 2,500개이며 ON/OFF를 포함한 고유 상품 쌍·상태는 5,000개다. 중복 상품 쌍·상태는 0이다.
- 출처 교차는 무신사→무신사 2,348, 유니클로→무신사 152, 유니클로→유니클로 1,120, 무신사→유니클로 1,380이다.
- 10건 단위 500개 배치가 모두 10/10 PASS이며 `failures.json`과 `ux-explanation-gaps.json`은 각각 0건이다.
- 결과 위치는 `Docs/TestEvidence/ReleaseQA-5000-20260814/`이며 `cases.json`, `batches.json`, `summary.json`, `report.md`를 포함한다.
- 이 검사는 5,000회의 신규 네트워크 호출이나 실제 iPhone UI 자동화가 아니라, 이전에 production 파서·분류·비교 엔진으로 실행된 실상품 증거를 현재 UX 계약으로 재생한 A테스트다. 개인 iPhone과 옷장 데이터는 변경하지 않았다.
- 실상품 증거가 없는 taxonomy 세부분류, 빈 옷장, 파서 실패 화면은 이번 5,000건 통과 범위에 포함하지 않는다. 이 항목까지 포함한 완전 확장형 A테스트에는 별도 fixture/UI 검증이 필요하다.
- Python 구문 검사, `git diff --check`, 보호 파일 및 보호 modifier 호출부 검사를 통과했다. Simulator는 실행하지 않았다.
- 기존 A테스트 정의에 포함됐던 Excel 결과는 Spreadsheets skill이 요구하는 `load_workspace_dependencies`가 현재 세션에 없어 생성하지 못했다. JSON과 Markdown 원장은 완료됐다.

## 31. 2026-08-14 현재 production Swift 경로 A테스트 재실행

- 직전 5,000건 JSON 재생 결과와 구분하기 위해 현재 앱의 Swift production 분류·파서·matcher·추천 코드를 iOS Simulator 테스트 호스트에서 직접 실행했다. 개인 iPhone 옷장과 Supabase 데이터는 변경하지 않았다.
- 5,026개 production 분류 전수 XCTest는 통과했다. 처리 5,026, 분류 성공 4,698, 사용자 확인 328, invalid 0, placeholder other 80이며 폴로셔츠 190, 후드 126, 맨투맨 157을 식별했다. 결과 번들은 `/tmp/FitMatchA5000Category5026.xcresult`다.
- 전체 `FitMatchMusinsaReferenceAudit` scheme 재실행은 2,462초 동안 346개 테스트를 수행해 324 pass / 8 fail / 14 skip으로 끝났다. 무신사 기준 옷장 교차비교는 101.87초에 통과했고 유니클로 기준 옷장 교차비교도 91.97초에 통과했다. 무신사 1,037개 및 유니클로 243개 공식 실측 corpus 테스트와 5,026개 분류 테스트도 이 실행에서 통과했다. 결과 번들은 `/tmp/FitMatchA5000MusinsaFullRetry.xcresult`다.
- 실패 8개 중 `LiveReleaseQA1200Tests` 1개는 실기기 배치 번호 환경 변수가 없는 Simulator 전체-suite 실행으로 인한 하네스 실패다. 나머지 7개는 현재 앱 동작과 기존 회귀 기대값의 충돌로 출시 전 정리가 필요하다: 폴로 2개, 반팔·긴팔/확장 비교 정책 3개, source history 1개, 자동 기준 옷 선택 1개다.
- 잘못된 Swift Testing 식별자로 0건 실행된 두 번과 최초 Simulator test host launch 실패는 테스트 실적으로 계산하지 않았다.
- 현재 판정은 핵심 실상품 교차비교와 대규모 corpus는 통과했지만 전체 회귀 suite가 green은 아니다. 7개 정책 회귀의 기대값이 낡은 것인지 production 구현 결함인지 확인한 뒤 수정·재실행해야 출시 승인 근거가 된다.

## 32. 2026-08-14 A테스트 정책 회귀 보정

- 일반 셔츠가 혼합 쇼핑몰 경로의 `폴로셔츠` 문자열에 오염되지 않도록 상의 분류 증거 우선순위를 구체적인 공급사 leaf, 상품명의 명시적 소매 길이, 경로의 단일 길이, 상품명의 의류 구조 순으로 정리했다. 명확한 피케·카라·폴로 leaf는 `polo_shirt`로 유지한다.
- 반팔↔긴팔 상의는 자동 비교에서 제외하되 사용자가 직접 선택하면 소매길이를 제외한 공통 실측으로 참고용 부분 비교할 수 있다.
- 긴바지↔반바지는 자동 비교에서 제외하되 사용자가 직접 선택하면 총장·밑단을 제외하고 허리·엉덩이·허벅지 등 공통 실측으로 참고용 부분 비교할 수 있다.
- 같은 착용 부위의 아우터 길이·세부 종류 차이는 기존 P0 정책대로 자동 비교하지 않고 수동 참고 비교만 허용한다. 상의↔하의처럼 착용 부위가 다르면 수동 선택도 계속 차단한다.
- 현재 상품의 명확한 분류 증거와 과거 저장 선택이 충돌하면 현재 증거를 우선한다. 정상 측정 정의를 가진 정확한 대표 옷 1벌은 자동 선택된다는 회귀 fixture도 보강했다.
- 수정 전 실패했던 8개 집중 정책 테스트는 8/8 통과했다. 이후 전체 회귀 실행에서 5,026개 분류 감사 invalid 0, 무신사 공식 실측 1,037개 통과, 유니클로 243개 입력·238개 상품·1,574개 행·184개 비교쌍 복구를 확인했다.
- 전체 회귀 묶음은 실시간 네트워크/OCR 검사가 포함돼 30분 이상 소요되어 사용자 요청에 따라 마지막 저장 무신사 비교쌍 검사 도중 중단했다. 따라서 전체 suite 최종 green은 아직 주장하지 않는다.

## 33. 2026-08-14 실제 URL 균형 A테스트 100건

- `scripts/run-live-a-test-100.py`를 추가했다. iPhone·Simulator·DB를 사용하지 않고 무신사 상품/실측 API와 유니클로 사이즈 API를 새로 조회한 뒤 현재 FitMatch 정책으로 비교 시나리오를 재생한다.
- seed `2026081401`로 실제 접근·실측 가능한 고유 상품 206개를 확인하고 100개 비교쌍을 만들었다.
- 출처 조합은 무신사→무신사, 무신사→유니클로, 유니클로→무신사, 유니클로→유니클로 각각 25건이다. 기준 옷 ON 52 / OFF 48이다.
- 결과는 자동 비교 17, 수동 선택·참고 비교 25, 정상 차단 58이며 정책 모순 0건이다.
- 재감사 과정에서 실행기 자체의 아우터 대분류 과잉 허용, 상위 `반팔 & 긴팔` 경로 오염, 혼합 셔츠 경로의 폴로 오염을 발견해 앱과 동일한 증거 우선순위로 보정했다. 앱 production 로직 추가 변경은 없었다.
- 상세 실제 URL·상품명·쇼핑몰 분류·FitMatch 분류·UI 판정은 `Docs/TestEvidence/LiveA100-20260814/results.json`에 저장했다.

## 34. 2026-08-14 출시 전 최종 판정과 실기기 확인 항목

- 실제 URL A테스트 100건은 무신사·유니클로의 현재 상품/실측 API 가용성을 확인하고 별도 headless 실행기에서 현재 FitMatch 정책을 재생한 검사다. iPhone 앱 바이너리, Simulator, 개인 옷장, Supabase 데이터는 사용하지 않았다.
- 따라서 `100/100 PASS`는 실제 앱 전체 사용자 흐름이 100회 성공했다는 뜻이 아니다. 비교 정책상 모순을 찾지 못했다는 사전 감사 결과다.
- 특히 공유 확장 → 앱 열기 → 상품 파싱 → 옷장 조회 → 기준 옷 자동 선택/수동 선택 → 결과 UI → 기록 저장 → 재실행 후 복원은 실제 앱 환경에서 별도로 확인해야 한다.
- 출시 전 현재 App Store 제출용 Release 빌드와 동일한 버전으로 다음 6건을 iPhone에서 확인한다.
  1. 무신사 상품 공유 후 정상 자동 비교
  2. 유니클로 상품 공유 후 정상 자동 비교
  3. 반팔↔긴팔 조합에서 자동 비교 제외, 수동 부분 비교 제공, 소매길이 제외 문구 표시
  4. 기준 옷 OFF 상태에서 오류 화면이 아니라 `비교할 옷 선택` 화면 표시
  5. 비교 결과와 내 옷장 저장 정상 동작
  6. 앱 강제 종료·재실행 후 옷장 및 비교 기록 유지
- 위 6건에서 크래시, 멈춤, 잘못된 분류, 비정상 자동 비교, 저장 유실, 잘못된 안내 문구가 없으면 출시 승인 조건을 충족한 것으로 판단한다.
- 전체 네트워크/OCR 회귀 묶음은 앞서 장시간 실행 후 사용자 요청으로 중단했으므로 전체 suite green을 출시 근거로 주장하지 않는다.

## 35. 2026-08-14 브리프케이스 taxonomy 오분류 보정

- canonical bundle에서 무신사 `가방 > 브리프 케이스` 계열 4건이 `브리프` 키워드 때문에 남성 속옷으로 confirmed 처리된 것을 발견했다.
- 앱 내장 bundle과 연구 원본 bundle 모두 해당 4건을 `rejected / not_fitmatch_comparable`로 변경하고 앱 매핑·비교 family·extension을 제거했다.
- 상태 합계는 confirmed 1,327 / review_required 608 / rejected 1,451 / unsupported 40 / navigation_only 582로 바뀌었다. runtime mapping 3,426과 전체 4,008은 유지된다.
- 재생성 방지를 위해 taxonomy staging/refinement 생성 규칙에서 가방·브리프케이스 문맥을 속옷 키워드보다 우선하도록 수정했다.
- 운영 DB용 `073_briefcase_taxonomy_correction.sql`, 읽기 전용 검증 `074`, 백업 기반 rollback `075`를 추가했다. 운영 DB에는 아직 실행하지 않았다.
- 내장 bundle checksum과 manifest를 재생성했고 `canonicalTaxonomyRejectsMusinsaBriefcasesAsBags()` 회귀 테스트 1건이 Simulator에서 통과했다.
- 상의 611개는 상품 수가 아니라 confirmed 쇼핑몰 category path 수다. 분해 중 캐릭터 탐색 경로 2건이 `bra`, 유니클로 스웨트팬츠 1건이 상의/후드로 들어간 추가 이상 데이터도 발견했으며 후속 전수 정제가 필요하다.

## 36. 2026-08-14 DB 반영 전 canonical taxonomy 4,008건 전수검수

- 현재 production Swift 분류기로 5,026개 상품을 다시 실행했다. 5,026개 고유 입력, 분류 완료 4,697, 사용자 확인 329, invalid 0이며 테스트가 12.031초에 통과했다. xcresult는 `/tmp/FitMatchTaxonomyDBAudit5026.xcresult`다.
- 공식 taxonomy snapshot 4,008개 전체와 runtime mapping 3,426개를 current production 5,026건 및 Live A100의 200개 상품 관측과 교차검증했다. 상품 증거가 존재하는 고유 경로는 426개다.
- 구조 검증은 source 4,008, runtime 3,426, snapshot 매칭 3,426, source identity 고유성 모두 통과했다.
- 최종 감사 결과는 무변경 3,082, navigation 유지 582, confirmed 승격 후보 10, rejected 전환 9, review_required 전환 325다. high/critical 334건 중 실제 production/Live 상품 증거가 있는 행은 129, 없는 행은 205다.
- 명백한 rejected 전환 9건은 반려동물 의류 6건, 패딩/퍼 신발 2건, 드레스퍼퓸 1건이다. 이 외에는 자동 확정하지 않고 review_required로 보수적으로 제안했다.
- 산출물은 `Docs/Research/CanonicalTaxonomyAudit-20260814/`의 `audit-results.json`, `high-risk.json`, `db-candidate-audit.csv`, `report.md`, `manifest.json`, `current-production-5026-results.json`이다.
- `scripts/audit-canonical-taxonomy-for-db.mjs`와 검증기 `scripts/validate-canonical-taxonomy-audit.mjs`를 추가했다. 검증 결과 4,008행, runtime 3,426행, high-risk 334행, 4개 산출물 checksum 모두 통과했다.
- 운영 Supabase에는 쓰지 않았다. 334개 고위험 행의 정책 확정과 사용자 승인 후에만 새 버전 migration/validation/rollback을 생성한다.

## 37. 2026-08-14 taxonomy·A테스트 DB 적재 사전 브리핑 및 Excel 후속 작업

- 사용자 결정: A테스트에서 수집·검증한 5,026개 상품 데이터도 DB 적재 대상에서 제외하지 않는다. 다만 앱이 직접 사용하는 운영 taxonomy 데이터와 섞지 않고 회귀검증용 staging 데이터로 분리한다.
- 운영 taxonomy 원장은 `fitmatch_taxonomy` 스키마에 둔다. 공식 쇼핑몰 taxonomy node 4,008개, runtime mapping 3,426개, 분류 결정·앱 매핑·비교 family·실측 정책이 이 영역에 해당한다.
- A테스트 5,026개 상품은 기존 `fitmatch_staging.runtime_classification_regression_cases`에 적재하는 방향이다. 핵심 필드는 `rule_set_code`, `corpus_key`, `source_code`, `external_product_id`, `product_name`, `source_category_path`, 기대 대분류·세부분류·비교 가능 여부이며 URL·family·length·사용자 확인 필요 여부·원본 증거는 컬럼 확장 또는 `evidence jsonb` 사용을 검토한다.
- A테스트 실행 단위 요약은 기존 `fitmatch_staging.runtime_classification_parity_runs`에 보존한다. 현재 `details jsonb`만으로 개별 실행 결과 추적이 부족하면 별도 `runtime_classification_regression_results` staging 테이블 추가를 제안하되, 사용자 검토 전에는 생성하지 않는다.
- staging 회귀 데이터는 앱 런타임 조회 대상이 아니다. `anon`/`authenticated` CRUD는 계속 차단하고 backend batch 또는 `service_role`만 적재·검증한다. 추후 앱이 서버 taxonomy를 읽을 때도 좁은 RPC/view를 별도로 설계한다.
- Excel 사전 검수 파일에는 최소 다음 시트를 포함한다: `00_브리핑`, `01_테이블맵`, `02_Taxonomy요약`, `03_카테고리매핑샘플`, `04_A테스트적재설계`, `05_검수대상334`, `06_적재순서검증`, `07_전체4008`, `08_A테스트5026`.
- Excel에는 4,008개 taxonomy 전체 행, high/critical 검수 대상 334개 전체, current production A테스트 상품 5,026개 전체를 넣는다. 현재 수량은 confirmed 1,327 / review_required 608 / rejected 1,451 / unsupported 40 / navigation_only 582이며 감사 제안은 keep 3,082 / navigation 유지 582 / confirmed 후보 10 / rejected 전환 9 / review_required 전환 325다.
- 334개 제안은 자동 DB 정답이 아니다. 실제 상품 증거가 있는 행 129개와 없는 행 205개를 구분해 Excel에서 검토 상태로 표시하고, 사용자 승인 후 migration → read-only validation → promotion 순서로 진행한다.
- 현재 세션에는 Spreadsheets skill이 필수로 요구하는 `load_workspace_dependencies`가 노출되지 않았고 `@oai/artifact-tool` import도 실패했다. 규칙상 `openpyxl`, `xlsxwriter` 등으로 우회하지 않았으므로 `.xlsx`는 생성되지 않았다. 다음 세션에서 해당 도구가 제공되면 Excel 생성부터 재개한다.
- Excel 작성 전후 모두 Supabase에는 쓰지 않는다. Excel 검수·사용자 승인 후에만 schema 보완 여부와 seed/migration/validation/rollback SQL을 작성한다.

## 38. 2026-08-14 DB 적재 최종 설계 점검 및 실측 정책 보정

- 운영 데이터는 `fitmatch_catalog`의 release/document/source mapping 3개 테이블, 회귀 데이터는 `fitmatch_qa`의 classification case/validation run 2개 테이블로 분리하는 5테이블 설계로 정리했다. 기존 Supabase 테이블은 삭제하거나 변경하지 않았다.
- canonical runtime mapping은 4,008행이 아니라 실제 bundle의 `records` 3,426행이다. navigation 582개는 bundle에 개별 행이 없고 집계값만 있으므로 runtime mapping 행으로 생성하지 않는다.
- confirmed 1,327개 `appMapping.detailCode`를 현재 `FitMatchTaxonomy.json`과 전수 대조했다. 현재 detail과 직접 일치 558, NULL 186, 현재 taxonomy에 없는 legacy/semantic detail 583이다. 따라서 canonical `appMapping`은 `legacy_app_mapping`으로 원형 보존하고 현재 앱 `detailCategory` FK나 운영 기본값으로 사용하지 않는다. 최종 앱 detail은 기존 product classifier와 5,026개 회귀 결과로 검증한다.
- comparison family transform 31개와 confirmed 1,327개 resolved app family는 모두 현재 Swift `ComparisonGarmentFamily` 값으로 변환 가능했다.
- comparison/garment policy의 measurement 참조 137개를 전수 대조해 유일하게 정의가 없던 `foot_length` 3개 참조를 확인했다. `FitMatchMeasurementPolicies.json`의 canonical measurement definitions에 `foot_length`를 추가했으며 raw source alias는 공식 근거 없이 만들지 않았다.
- measurement definitions는 21→22개가 됐다. 새 measurement file SHA-256은 `5bcec02403caeb389efafffb7cd3dde6cefa15f49c8f6098ee1a40c036ce8883`, 새 canonical bundle checksum은 `acb5d29f00840773f3283fc9ea5e8703078d7bb205a844e4da245940fdca0467`이다. manifest의 bytes, count, checksum을 함께 갱신했다.
- 로컬 checksum·bytes·manifest·bundle checksum과 모든 comparison measurement 참조를 다시 검증했고 누락 0이었다. Source mapping 3,426개, source identity 고유 3,426개, QA 5,026개(확정 4,697, 사용자 확인 329)는 유지됐다.
- QA 329개 중 최종 분류 출력 전체 NULL은 249개, `other/other` placeholder가 있는 보류는 80개다. QA 기대 결과 컬럼은 조건부 nullable이어야 하며 원본에 없는 `canonicalEligibility`를 5,026개 기대값으로 만들지 않는다.
- 검수용 Excel 생성은 승인됐지만 이 세션의 callable tool 목록에 Spreadsheets skill 필수 도구인 `load_workspace_dependencies`가 실제로 노출되지 않아 계속 차단됐다. 다른 Excel 라이브러리로 우회하지 않았으며 Supabase에도 쓰지 않았다.

## 39. 2026-08-14 Supabase 카테고리 release store 생성 및 적재

- 사용자 최종 지시에 따라 Excel 단계는 제외하고 FitMatch Supabase 프로젝트(`hnkplvyegonlhumlejst`)에 직접 반영했다.
- 원격 의존성을 먼저 확인했다. 기존 `public`, `fitmatch_taxonomy`, `fitmatch_staging` 데이터는 사용자 옷장 및 기존 taxonomy FK와 연결돼 있어 삭제하거나 수정하지 않았다.
- migration `create_private_category_release_store`로 비공개 `fitmatch_catalog`, `fitmatch_qa` 스키마와 5개 테이블을 생성했다: `releases`, `documents`, `source_category_mappings`, `classification_cases`, `validation_runs`.
- `anon`, `authenticated`, `public`의 schema/table 권한을 모두 회수하고 RLS를 켰다. 의도적으로 client policy를 만들지 않아 앱 클라이언트는 접근할 수 없고 `service_role` backend만 접근한다. Supabase advisor의 `rls_enabled_no_policy` INFO는 이 deny-by-default 설계에 따른 예상 경고다.
- release `observed-official-2026-08-03__taxonomy-refined-2026-08-03`에 manifest, 앱 taxonomy, comparison policy, measurement policy, source mapping metadata 문서 5개를 checksum/byte 수와 함께 적재했다.
- 대형 source mapping 원문을 문서와 행 데이터로 이중 저장하지 않았다. runtime mapping 3,426개를 조회용 projection 컬럼과 `raw_record jsonb` 원형으로 각각 적재했다.
- 기존 `/tmp/FitMatchTaxonomyDBAudit5026.xcresult`에서 실제 production classifier 첨부 결과를 추출해 입력 fixture와 결합하고 `fitmatch_qa.classification_cases`에 5,026개를 적재했다. 원본에 없는 기대값은 생성하지 않았고 보류 행의 기대 분류 컬럼은 NULL을 허용했다.
- DB 자체 검증 결과 documents 5, mappings 3,426, source identity distinct 3,426, mapping projection error 0, QA 5,026, 사용자 확인 329, full NULL 249, `other/other` 80, QA projection error 0으로 모두 통과했다. release 상태는 `validated`, validation run은 `passed`다.
- Supabase performance advisor가 지적한 `validation_runs.release_id` FK 인덱스는 후속 migration `index_category_validation_release_fk`로 추가했다. 새 조회 인덱스의 unused 경고는 생성 직후라 정상이다.
- 기존 `fitmatch_staging` 일부 테이블의 RLS 비활성 보안 경고는 발견했지만, 기존 접근 계약을 모르는 상태에서 RLS를 켜면 기능이 중단될 수 있으므로 이번 작업에서는 변경하지 않았다.

## 40. 2026-08-14 현재 앱 taxonomy 정규화 및 corrected 정책 버전 반영

- 사용자 승인 후 기존 DB를 다시 감사했다. `fitmatch_taxonomy.source_categories` 4,008건은 무신사 2,277/유니클로 1,731이며 navigation 582, non-navigation 3,426이다. 새 bundle mapping 3,426건과 복합 identity를 대조해 3,426/3,426 일치, 누락 0을 확인했다.
- 기존 `taxonomy-refined-2026-08-03`은 confirmed 1,331/rejected 1,447로 현재 bundle보다 브리프케이스 4건이 뒤처져 있었다. 기존 버전을 update하지 않고 immutable successor `taxonomy-corrected-2026-08-14`를 생성했다.
- corrected 정책에는 decision 4,008, length axes 4,008, evidence 4,019, audit 4,008, confirmed legacy/semantic app mapping 1,327건을 복제했다. 브리프케이스 4건만 confirmed→rejected로 바꾸고 garment/family/default mapping을 제거했다. 최종 상태는 confirmed 1,327/review_required 608/rejected 1,451/unsupported 40/navigation_only 582이며 정책 상태는 `validated`다.
- 현재 앱 `FitMatchTaxonomy.json`을 release-scoped `fitmatch_catalog.app_categories` 11건과 `app_category_details` 75건으로 정규화했다. 기존 `public.app_categories` 99건은 semantic garment type이 섞인 legacy 구조라 삭제·수정하지 않았다.
- `fitmatch_catalog.source_to_fitmatch_mappings` security-invoker view를 추가했다. confirmed 1,327건은 유효한 앱 대분류만 연결하고 앱 세부분류는 강제로 확정하지 않는다. 모든 confirmed 행의 `detail_resolution_strategy`는 `product_classifier_required`이고 최종 detail은 API 상품명/경로를 사용하는 production classifier가 결정한다. 원래 appMapping은 `legacy_app_mapping`으로만 노출한다.
- corrected DB 3,426행과 현재 bundle을 status/category/garment/family 단위로 전수 대조해 불일치 0이었다. 앱 대분류 FK 불일치 0, 강제 app detail 0이며 `078_current_taxonomy_validation.sql`도 통과했다.
- 적용 migration은 `normalize_current_app_taxonomy`, `add_corrected_taxonomy_policy_20260814`, `add_source_to_fitmatch_mapping_view`다. 재현/검증/rollback SQL은 `supabase/sql/076_normalize_current_app_taxonomy.sql`, `077_add_corrected_taxonomy_policy.sql`, `078_current_taxonomy_validation.sql`, `079_current_taxonomy_rollback.sql`에 기록했다.
- QA 상품명 5,026건은 운영 taxonomy와 연결하지 않았고 `fitmatch_qa` 회귀 fixture로만 유지했다. 기존 사용자/Auth/public/legacy taxonomy 데이터는 삭제하거나 수정하지 않았다.
- Supabase advisor에서 새 구조의 unindexed FK 경고는 0이다. RLS policy 없음 INFO는 private schema에서 anon/authenticated를 의도적으로 전면 차단한 결과이고, unused index INFO는 생성 직후 예상 상태다.

## 41. 2026-08-14 DB 기반 A테스트 실행

- DB corrected 정책과 bundle runtime mapping을 먼저 전수 대조했다. 3,426건이 모두 identity로 결합됐고 identity/status/category/garment/family mismatch는 각각 0이었다. 정규 앱 taxonomy도 category 11/detail 75를 확인했다.
- DB의 `fitmatch_qa.classification_cases` 기대 집계는 5,026건, 사용자 확인 329, 전체 NULL 249, `other/other` 80, projection error 0이었다.
- 현재 Swift production classifier를 `CategoryValidation5026AuditTests/testCurrentProductionClassifierReclassifiesAll5026Products`로 새로 실행했다. 5,026 unique input/output, classified 4,697, 사용자 확인 329, invalid 0, placeholder 80이며 11.595초에 통과했다.
- DB 기대 집계와 새 XCTest 결과가 일치했다. 결과 bundle은 `/tmp/FitMatchDBBackedATest-20260814-2.xcresult`다.
- Supabase `fitmatch_qa.validation_runs`에 validator `db_backed_a_test_v1`, run id `51943e7b-9068-4dcb-8584-606181db2c8f`로 기록했다. status `passed`, mapping_count 3,426, qa_count 5,026, error_count 0이다.
- 최초 sandbox 실행은 CoreSimulatorService 권한 및 SwiftSoup 네트워크 해석 제한으로 실행 전 실패했다. 권한이 허용된 정상 환경에서 재실행한 결과만 A테스트 실적으로 기록했다.

## 42. 2026-08-14 실기기 비교 결과 화면 진입 성능 진단 및 1차 보완

- 실기기 로그 3건에서 비교 결과 화면 `on_appear`는 52.1~93.3ms, 다음 main runloop 도달은 30.7~65.2ms 추가 지연됐다. 등록 데이터는 user fit 3건/history 3건으로 작아 현재 병목을 대량 SwiftData 조회로 보기는 어렵다.
- 상품·기준 옷 썸네일은 cache hit 0.0ms였고 첫 기준 옷 이미지도 download 4.8ms + decode 3.1ms, 총 7.9ms였다. 따라서 이번 재현의 주 병목은 네트워크나 이미지가 아니라 결과 화면의 초기 SwiftUI 구성·계산·layout이다.
- `settled_250ms`의 311.6~355.9ms는 의도적으로 예약한 250ms 타이머를 포함하므로 300ms 정지 시간으로 해석하지 않는다.
- `RecommendationResultView`의 최상위 결과 카드 스택을 `LazyVStack`으로 바꿔 화면 아래 카드를 최초 프레임에 모두 만들지 않도록 했다. 추천 카드와 실측 카드에서는 실측 종류, 신뢰도, 차이·제외 목록을 한 렌더링 안에서 재사용하고 각 행의 실측값 조회 중복을 제거했다.
- 로그에 별도로 `<OnScrollGeometryChange Modifier> tried to update multiple times per frame` 경고가 1회 있다. 이는 결과 화면 진입 병목과 분리된 스크롤 상태 갱신 경고이므로 보호 대상 tab bar scroll modifier는 이번 변경에서 건드리지 않았다.
- Simulator는 사용하지 않았다. generic iOS device 무서명 빌드가 통과했으며, 동일한 실기기 동작을 다시 실행해 `on_appear`와 `next_main_runloop` 전후 수치를 비교해야 체감 개선을 확정할 수 있다.

## 43. 2026-08-14 상세 화면 스크롤 성능 진단 추가

- 비교 결과와 내 옷 상세의 실제 ScrollView에 DEBUG 전용 `ScrollPerformanceDiagnostics`를 추가했다. 공용 탭바/상단 헤더의 보호된 스크롤 modifier와 해당 call site는 변경하지 않았다.
- CADisplayLink 기준으로 스크롤 중 24ms 이상 프레임은 `long_frame`, 40ms 이상은 `severe_frame`으로 기록한다. 화면 종료 시 전체 프레임 수, 긴 프레임 수, 심한 프레임 수, 동일 프레임 geometry 중복 갱신 수, 최장 프레임을 `monitor_summary`로 출력한다.
- iOS 18 이상에서는 스크롤 phase 전환, 0.25초 간격 offset/velocity/content/container 표본, 한 display frame 안의 geometry 중복 갱신도 `[ScrollPerformance]` 로그로 남긴다. Release에서는 진단 modifier가 제거돼 출시 성능에 영향을 주지 않는다.
- Simulator는 사용하지 않았다. generic iOS device 무서명 빌드가 통과했다. 실기기에서 비교 결과와 내 옷 상세를 각각 위아래로 빠르게 2~3회 스크롤한 로그가 있어야 실제 병목 위치를 판정할 수 있다.

## 44. 2026-08-14 실기기 스크롤 로그 판정 및 ProMotion 허용

- 비교 결과 실제 스크롤 로그에서 40ms 이상 severe frame은 0건이었다. 대표 실행은 3.714초/229 frames/long frame 6/스크롤 중 worst 25.0ms, 다른 실행은 1.972초/117 frames/long frame 2였다. 반복적인 메인 스레드 정지가 스크롤 병목이라는 증거는 없었다.
- 실기기 `maximumFramesPerSecond`는 120인데 측정 cadence는 약 60fps였고 앱 Info.plist에 `CADisableMinimumFrameDurationOnPhone`이 없었다. Apple 공식 정의상 기본값 NO에서는 iPhone의 시스템 기본값보다 높은 프레임률에 접근할 수 없으므로 해당 키를 YES로 추가했다.
- 이 설정은 120Hz를 강제 고정하지 않고 높은 프레임률 접근만 허용한다. 실제 주사율은 저전력 모드, 발열, 화면 상태 등에 따라 iOS가 동적으로 조정한다.
- 최초 진단기의 `multiple_geometry_updates_in_frame` 14~73건은 120Hz geometry callback을 60Hz CADisplayLink tick으로 묶어 과대 집계했을 가능성이 높다. DEBUG monitor가 기기 최대 FPS를 요청하도록 보정하고 monitor 시작 전 callback은 무시하도록 수정했다.
- 내 옷 상세 기록에는 `interacting/decelerating` phase가 없어 실제 스크롤 동작이 포함되지 않았다. 화면 진입 성능만 확인됐고 내 옷 상세 스크롤 자체는 아직 미검증이다.
- plist lint와 generic iOS device 무서명 빌드가 통과했다. Simulator는 사용하지 않았고 보호된 tab bar scroll modifier와 call site는 변경하지 않았다.

## 45. 2026-08-14 기록→결과 전환 및 결과 스크롤 진단 보정

- ProMotion 적용 후 결과 화면의 대표 실제 드래그는 2.636초/291 frames로 약 110fps였고 long/severe frame은 모두 0, worst 19.0ms였다. 따라서 지속적인 렌더링 성능 부족은 재현되지 않았다.
- 결과 화면 콘텐츠 685pt/컨테이너 619pt로 실제 스크롤 범위가 약 66pt뿐인데 드래그는 bottom 150pt, top -69pt까지 overscroll했다. 사용자가 느낀 일부 저항감은 대부분 정상 스크롤보다 짧은 콘텐츠의 양 끝 bounce 구간일 가능성이 있다. UX 변경 없이 bounce 정책은 아직 바꾸지 않았다.
- DEBUG 진단기가 navigation transition 첫 260ms 동안 `multiple_geometry_updates_in_frame`을 26회 개별 print하고 있었다. 메인 스레드 콘솔 출력이 진입 애니메이션을 방해할 수 있어 개별 출력은 제거하고 summary 집계만 유지했다.
- 스크롤 monitor 시작을 화면 onAppear 즉시에서 350ms 뒤로 늦춰 navigation transition과 초기 safe-area/content layout 측정에 진단기가 개입하지 않도록 했다.
- 기록 카드 탭부터 결과 `onAppear`, 첫 main runloop까지 `[NavigationPerformance] route=history_to_result`로 측정하는 로그를 list/grid/recompare 경로에 추가했다. 다음 실기기 로그에서 실제 탭→화면 전환 지연과 결과 화면 내부 렌더 지연을 분리할 수 있다.
- generic iOS device 무서명 빌드가 통과했다. Simulator는 사용하지 않았고 보호된 tab bar scroll modifier와 call site는 변경하지 않았다.

## 46. 2026-08-14 결과 화면 초기 SwiftData 조회 지연 로딩

- 보정된 실기기 로그에서 기록 카드 탭→결과 onAppear는 58.1~107.1ms, 첫 main runloop는 95.9~155.9ms였다. 이미지 cache miss도 총 6.9ms뿐이라 전환 병목은 결과 화면 생성 전후의 메인 스레드 작업으로 확정했다.
- 결과 스크롤 monitor는 1.707초/194 frames와 2.739초/317 frames로 약 114~116fps였고 long/severe frame 0, duplicate update 0이었다. 지속적인 드래그 렌더링 병목은 재현되지 않았다.
- `RecommendationResultView`가 진입 즉시 실행하던 `UserFit` 전체 @Query와 `RecommendationHistory` 전체 @Query를 제거했다. 기준 옷 목록은 picker sheet 내부 @Query로 옮기고, 기존 비교 기록은 사용자가 실제로 다른 기준 옷을 선택해 저장할 때만 fetch한다.
- legacy ranking 계산도 해당 UI가 실제 평가될 때만 UserFit을 fetch하도록 바꿨다. 현재 결과 화면의 기능·저장 방식·추천 결과는 변경하지 않았다.
- generic iOS device 무서명 빌드가 통과했다. Simulator는 사용하지 않았고 보호된 tab bar scroll modifier와 call site는 변경하지 않았다.

## 47. 2026-08-14 root visibility 레이아웃 영향 대조 로그 판정

- 새 실기기 캡처에서 history root visibility가 true→false로 바뀔 때와 bottom overscroll 이후 false→true로 바뀔 때 `contentSize=1252`, `containerSize=852`, `insetTop=59`, `insetBottom=34`, `maxOffset=493`가 모두 유지됐다. visibility 변경이 ScrollView safe area/frame/padding/content size를 바꾸는 피드백 루프 증거는 이번 캡처에서 없었다.
- visibility 재표시는 bottom overscroll offset 498.3에서 새 upward drag로 460.7까지 돌아온 시점이었다. bottomLock 해제와 visibility=true가 같은 사용자 드래그에서 발생해 현재 요구 동작과 일치했다. 원인으로 확정되지 않았으므로 보호된 scroll modifier 및 UI는 변경하지 않았다.
- 결과 화면 실제 드래그 3건은 각각 401/299/210 frames, long 0, severe 0, duplicate 0, worst 19.8~22.1ms였다. 측정 구간 평균은 약 117~119fps로 카드 렌더링·LazyVStack·스크롤 엔진을 우선 수정할 근거가 없다.
- SwiftData 초기 조회 지연 적용 후 history→result warm path의 first main runloop는 70.3/97.4/86.1ms로 기존 95.9~155.9ms보다 개선됐다. 다만 첫 cold path는 152.7ms로 남아 있다.
- 남은 우선 조사 대상은 첫 cold navigation의 99.3ms pre-onAppear와 이후 53.4ms main-runloop 구간이다. 이미지 miss는 6.7ms라 우선순위가 낮고, UI 변경 전에 실제 기기 Time Profiler로 destination 생성, SwiftData relationship fault, SwiftUI body/layout, navigation transition stack을 분리해야 한다.

## 48. 2026-08-14 실제 iPhone Time Profiler 캡처

- 연결된 `iPhone 14 Pro`의 실행 중 FitMatch 프로세스(pid 29267)에 Instruments Time Profiler를 20초간 attach해 기록→결과 진입을 실제 기기에서 캡처했다. Simulator는 사용하지 않았다.
- trace는 `/tmp/FitMatchHistoryColdNavigation-2.trace`에 저장됐고 크기는 약 14MB다. 대상 OS는 iOS 26.6, Instruments/Xcode는 26.0이며 time-profile/time-sample/runloop/hang 테이블이 포함됐다.
- `xcrun xctrace export --toc`는 성공했지만 time-profile call tree를 XML로 내보내는 Xcode 26 CLI가 Bus error 10으로 종료됐다. 따라서 trace 캡처는 성공했으나 상위 CPU stack을 CLI에서 판독해 원인을 확정하지 못했다. Instruments GUI에서 해당 trace의 Main Thread, 기록 카드 탭 시점 전후 약 160ms 범위를 열어 SwiftUI/SwiftData/navigation stack을 확인해야 한다.
- call tree 증거가 아직 없으므로 카드, LazyVStack, root scroll visibility, safe area, bounce 동작은 추가 변경하지 않았다.

## 49. 2026-08-15 실제 iPhone Time Profiler GUI 1차 판독

- `/tmp/FitMatchHistoryColdNavigation-2.trace`를 Instruments GUI에서 열어 전체 22초 구간의 Main Thread call tree를 확인했다. FitMatch 전체 sample weight는 5.90초, Main Thread는 2.87초(48.7%)였다.
- Main Thread에서는 UIKit update sequence와 SwiftUI `AttributeGraph` 갱신, `NavigationStackCoordinator.update`, `UIHostingController`, layout/view-size cache 및 preference 결합 계열 stack이 주로 관찰됐다. 전체 구간 기준으로 SwiftData fetch나 이미지 decode가 최상위 CPU 병목이라는 증거는 보이지 않았다.
- 이 결과는 첫 cold navigation의 원인 후보를 SwiftUI destination 생성·AttributeGraph·UIKit layout/update로 좁히지만, 22초 전체 aggregate이므로 약 150ms 전환 구간의 단일 원인을 확정하는 증거는 아니다.
- macOS 화면 기록 권한은 정상 동작했지만 `System Events` 자동화가 오류 `-10827`로 응답하지 않았고, CoreGraphics 입력 이벤트도 Instruments 타임라인 선택에 반영되지 않았다. 선택 구간 call tree를 확보하기 전에는 UI/동작을 추가 변경하지 않는다.

## 50. 2026-08-15 무신사·유니클로 3시간 출시 A테스트 전수 감사

- 로컬 `main` HEAD `9264814` 기준으로 프로젝트의 공식 상품 corpus 5,026개(무신사 4,011/유니클로 1,015)를 production `ParsedClosetClassification`에 다시 통과시켰다. 입력/고유/출력 5,026, 구조적으로 유효 4,701, 사용자 확인 325, invalid 0, placeholder other 79였다. 상품별 쇼핑몰 경로→FitMatch 대분류/세부분류/family/length 내역은 archive CSV에 저장했다.
- 실제 iPhone 14 Pro(iOS 26.6, arm64)에서 5,026개 production 분류 테스트와 애매/other 325개 production live parser 재검증을 완료했다. 두 XCTest 모두 실패 0이었다. 325개는 parsing 325/325, 최종 사용자 확인 49, 위험한 other 자동 확정 0, parser 실패 0이었다. 이 중 최신 무신사 경로에서 `bottoms/other_bottoms`로 구조 분류된 점프수트·오버올 55개는 embedded canonical mapping이 `rejected`, `eligibility=false`, app mapping 없음이라 최종 비교 후보에서 제외된다. Simulator는 사용하지 않았다.
- 공식 endpoint 5,026개를 저속 재조회했다. 전체 도달, rate limit 0, unavailable 0, 공식 실측 즉시 확인 4,569(무신사 3,561/유니클로 1,008), 직접 실측 응답 없음 457(무신사 450/유니클로 7)이다. 무신사 450개는 HTML/OCR fallback 또는 수동 입력 대상이므로 곧바로 앱 parser 실패로 해석하지 않는다.
- 현재 의미 분류 결함은 고유 233개이며, canonical bundle과 matcher의 최종 product-level 교정을 적용한 뒤에도 비교 후보 선택·차단에 직접 영향을 주는 P0는 128개(무신사 113/유니클로 15)다. 이 중 116개는 현재 공식 실측까지 즉시 내려온다. family 방향 교차감사에서 `E480966`, `E485369`, `E487201` 히트텍 레깅스 3개가 `base_layer_top`/T-shirt family로 라우팅되는 결함도 확인했다.
- 가장 치명적인 회귀는 최신 로컬 커밋 `9264814`가 추가한 `explicitUnderwearDetail`의 부분 문자열 검사다. `브라운`/`브라이트`/`CHAMBRAY`/`무브라이트` 87개를 여성 브라로, `brief lined` 러닝 하의 3개를 남성 브리프로 바꿨다. 90개 모두 이전 corpus에서는 속옷이 아니었고 84개는 현재 공식 실측이 직접 제공된다. 안전한 `containsExplicitBra` 함수가 이미 있지만 새 helper가 그보다 먼저 실행된다.
- 기존 Swift Testing 회귀 `brownBottomNamesDoNotBecomeBras()`는 실제 두 브라운 팬츠를 하의로 요구하지만 현재 production 5,026 출력은 둘 다 `underwear/women_bra`다. 최신 HEAD가 기존 테스트 계약과 모순되므로 전체 suite green을 주장할 수 없다.
- 그 외 활성 P0는 명시적 가디건 10, 다중 구조 세트 11, 스코츠 major/family 8, 상의 경로 브라탑 major/family 6, 블라우스→T-shirt 4, 히트텍 레깅스→상체 base-layer 3, 하이픈 소매 길이 2, 옵션/레이어/다중 길이 3, 유니클로 코치재킷 1이다. 일반 셔츠 83, 블라우스 22 등의 구조 세부분류 손실과 긴바지를 `같은 긴팔`로 표시할 수 있는 문구 1곳은 P1이다.
- 유니클로 AIRism 이름 97개를 별도 전수 확인했다. 속옷 경로 54개만 속옷이고 나머지는 티셔츠·폴로·팬츠·원피스·레깅스·아우터 등 공식 경로대로 분리되어, AIRism 문자열만으로 모두 속옷 처리하는 문제는 재현되지 않았다.
- 명시적 폴로셔츠 140개(무신사 122/유니클로 18)를 추가 대조했다. bundle이 중간에 `shirt`를 저장하지만 비교 직전 `storedGarmentType`이 inferred T-shirt family로 교정하며 Product/UserFit 양쪽에 적용된다. 기존 테스트도 저장값 `shirt`인 폴로↔티셔츠 허용과 폴로↔우븐 셔츠 차단을 검증한다. 내장 정책과 생성 스크립트의 레거시 표기는 정리 권장이지만 실행 P0는 아니다.
- 무신사 상품 4534935는 공식 `goodsNm` 자체에 `https://bizest...detailCMD...` 관리자 URL이 붙어 있고 앱 parser가 이를 그대로 사용한다. 정상 `goodsNmEng`가 있으므로 URL/관리자 패턴 검출 후 fallback하는 방어가 필요하다.
- 기존 5,000건 A테스트는 위험 상품이 포함된 520건을 출시 근거에서 제외하고 안전한 4,480/4,480만 유효 PASS로 재판정했다. 신규 라이브 700건도 위험 상품 86건을 제외한 614/614가 유효 PASS다. 정상 분류 상품의 정책 흐름은 대체로 안정적이지만 현재 P0 때문에 전체 출시는 보류다.
- Release arm64 generic iPhone 무서명 빌드는 성공했다. Debug generic iPhone arm64 `build-for-testing`도 앱·Share Extension·unit/UI test 타깃 전부 컴파일되어 `TEST BUILD SUCCEEDED`를 확인했다. 추가 P0 실제 iPhone 회귀 실행은 build/sign까지 완료됐으나 기기가 잠겨 launch 전 대기하여 중단했으므로 테스트 실적으로 계산하지 않는다.
- 최종 보고서 정리 후에도 Simulator 없이 generic iOS Release를 새로 전체 빌드했고 앱·Share Extension 포함 `BUILD SUCCEEDED`와 store validation 단계를 다시 확인했다.
- 추적 보고서는 `Docs/ReleaseATestReport-20260815.md`, machine-readable evidence는 `../FitMatchArchive/Docs/TestEvidence/ReleaseATest-20260815/`에 있다. 앱 로직·DB는 이번 감사에서 수정하지 않았다. 다음 작업은 P0/P1 로직 수정 → 233개 fixture 고정 → 5,026 semantic oracle와 A테스트 재실행 → 실제 iPhone 핵심 사용자 여정 6건이다.
- 감사 기준 local `main`은 `origin/main`보다 1커밋 앞이고, 기존 상세 화면 성능 진단 관련 작업 트리가 미커밋 상태다. 분류기·matcher·canonical bundle의 미커밋 변경은 없지만 build 검증은 현재 작업 트리를 포함하므로, 출시 전 정확한 source revision을 커밋으로 고정해야 한다.

## 51. 2026-08-15 A테스트 P0 분류 결함 소스 보정

- 사용자 지시에 따라 재전수검사보다 소스 수정을 먼저 진행했다. `ParsedClosetClassification`에서 `브라운`·`브라이트`·`CHAMBRAY`를 브라로 보던 부분 문자열 검사를 명시적 브라 토큰 검사로 교체했고, 일반 하의의 `brief lined`는 속옷 경로에서만 브리프로 확정하도록 제한했다.
- 일반 셔츠·블라우스 상품명 구조가 반팔·긴팔 속성보다 먼저 세부분류에 반영되도록 우선순위를 고쳤다. `short-sleeve`/`long-sleeve` 하이픈 표기도 길이 속성으로 인식한다.
- 명시적 가디건은 쇼핑몰의 상의 merchandising bucket과 무관하게 아우터/가디건 구조로 통일했다. 스코츠는 팬츠 상위 경로에서도 스커트 family로 통일하고, canonical 저장값이 pants여도 비교 직전 스커트로 교정한다.
- 상품명에 명시된 레깅스는 히트텍/이너웨어 경로보다 우선해 하의 레깅스로 분류하며, 하의 화면 분류에 상체 canonical family가 저장된 경우 matcher가 하체 inferred family로 복구한다. 속옷 화면 분류는 비교 family도 underwear로 고정한다.
- 공식 metadata가 그래픽 티 경로로 내려온 `KIDS PEANUTS코치재킷` 같은 강한 아우터 상품명은 상의/기타 경로에서 아우터로 복구한다.
- `[SET] T-shirt + Shorts`, 탑+가디건 세트처럼 서로 다른 의류 구조가 함께 있는 세트와 민소매/반팔 옵션·레이어 충돌 상품은 단일 의류로 자동 확정하지 않고 사용자 분류 확인으로 보낸다.
- 무신사 `goodsNm`에 URL·관리자 경로가 섞인 경우 정상 `goodsNmEng`가 있으면 이를 표시 상품명으로 선택하는 방어를 추가했다.
- 위 정책을 고정하는 Swift Testing 회귀를 추가했다. Simulator와 실제 iPhone 데이터는 사용하지 않았다. generic iOS Debug `build-for-testing`을 두 번 실행했고 앱, Share Extension, unit/UI test 타깃이 모두 `TEST BUILD SUCCEEDED`로 컴파일됐다. 테스트 실행과 5,026건 semantic oracle 재검사는 다음 단계이며, 이 결과만으로 출시 가능 판정을 내리지는 않는다.

## 52. 2026-08-15 유니클로 현재 판매 상품 전수 A테스트

- 유니클로 한국 공식몰 MEN/WOMEN/KIDS/BABY 공개 카테고리 199페이지를 수집했다. 1,028개 노출, 상품 ID 914개, 정규화 identity 881개 중 상세 페이지가 현재 열리는 상품은 880개였다. `E479751-000` 한 건은 공식 카테고리에 남아 있지만 상세가 404라 활성 상품과 분리했다.
- 880개 원본 사이즈 행 5,193개를 production 파서로 통과시켜 고유 사이즈 행 5,181개를 만들었다. 차이 12개는 동일 상품·색상 안의 중복 사이즈 표기이며 파싱 누락이 아니다. 사용할 수 있는 사이즈가 있는 상품은 752개다.
- 중간 의미 감사에서 `니트 > 브이넥/터틀넥/워셔블/GU`처럼 일반 leaf 아래의 니트 구조가 사라지는 경계, `Cut & Sewn` 상의 경계, 일반 이너웨어 T가 canonical 분류 전에 사이즈 변환돼 가슴·총장 실측이 소실되는 결함을 발견해 수정했다. AIRism/HEATTECH 기능명은 의류 구조가 아니라 공식 경로를 우선하도록 유지했고, AIRism 코튼 외출용 T 예외도 보존했다.
- 연결된 iPhone 14 Pro(iOS 26.6)에서 최종 production 사용자 흐름을 실행했다. 활성 880개, raw 5,193, parsed 5,181, 자동 비교 정책 검사 대상 610개, A테스트 2,288건이 모두 통과했다. 구성은 빈 옷장 752, 기준 옷 없음/수동 후보 512, 동일 프로필 기준 옷 자동 비교 512, 타 대분류 오비교 차단 512다.
- FitMatch 대분류 결과는 상의 340, 하의 108, 아우터 95, 속옷 98, 홈웨어 36, 레깅스 24, 스커트 23, 원피스 15, 자동 분류·비교 제외 또는 사용자 확인 141이다. 마지막 141건은 양말·벨트·우산·모자·신발 등 비의류와 브라·바디수트·커버올·수납 파우치 등 현재 전용 비교 정책 밖 항목으로 별도 CSV에 이유를 전수 기록했다.
- Simulator, 개인 iPhone 옷장 데이터, Supabase 운영 데이터는 사용하지 않았다. 최종 원본 결과는 `/tmp/FitMatchCurrentUniqloCatalog-20260815-7.xcresult`, 보고서는 `Docs/CurrentUniqloCatalogATestReport-20260815.md`, 전수 CSV/JSON은 `Docs/TestEvidence/CurrentUniqloCatalog-20260815/`에 있다.
- 자동화 범위에서는 유니클로 경로를 출시 가능(GO)으로 판정했다. 실제 공유 시트 진입·색상 썸네일·안내 버튼 이동·네트워크 재시도는 화면/OS 통합 영역이라 출시 전 실기기 수동 4개 흐름을 별도로 확인해야 한다.

## 53. 2026-08-15 유니클로 증분 수집기 신뢰성 보정

- 동일한 유니클로 카테고리 URL이 HTTP 200을 반환하면서도 hydration에는 다른 카테고리 검색 결과가 들어오는 사례를 확인했다. 요청 경로와 정확히 일치하는 `search` hydration key가 있을 때만 해당 페이지의 상품 ID를 수집하도록 엄격 검증을 추가했다.
- 응답 경로가 다르면 고유 캐시 우회 query로 수집기가 허용하는 최대값인 기본 5회 의미 재시도를 수행하고 원본을 `category-page-mismatches`에 보존한다. 실제 동일 URL 병렬 표본 4회 중 정상 3회/오염 1회로 변동성이 확인됐다. 재시도 후에도 불일치하면 그 페이지의 상품·하위 카테고리를 합치지 않고 `category_response_failures`와 `discovery_complete=false`를 결과에 남긴 뒤 종료 코드 2로 실패를 알린다. 불완전 수집에서는 기존 상품을 `not seen`으로 판정하지 않는다.
- 증분 상태는 상세 HTML뿐 아니라 공식 사이즈 응답의 `result_found`까지 확인된 상품만 `stored`로 승격한다. 과거 `known_unavailable` 상품은 다시 노출되면 재수집하며 실제 상품명을 상태에 보존한다.
- 상태 JSON 저장을 임시 파일 교체 방식으로 바꾸고 state별 비차단 파일 잠금을 추가해 중단·동시 실행 시 손상 가능성을 줄였다. 결과 용어도 `newly_seen`, `not_seen_this_run`, `pending_retry`로 바꿔 판매 시작·종료를 단정하지 않도록 했다.

## 54. 2026-08-18 DB 기반 상품 런타임 기반 완성

- Supabase 운영 프로젝트 `hnkplvyegonlhumlejst`에 migration 5개를 적용했다: `create_product_runtime_foundation_v1`(20260818011818), `create_product_runtime_procedures_v1`(20260818012026), `align_product_runtime_policy_v1`(20260818013019), `validate_product_runtime_v1`(20260818013251), `index_product_runtime_foreign_keys_v1`(20260818013611).
- 공용 상품·분류 이력·variant·size·canonical measurement 저장소와 사용자별 상품 intake, 옷장 canonical snapshot/override, 비교 run/result/measurement result를 추가했다. 기존 `source_product_snapshots` 3,842건은 공용 상품 1,542개에 모두 연결했고 현재 분류 이력 1,195건을 생성했다.
- 앱 공개 RPC는 `fitmatch_resolve_product`, `fitmatch_register_closet_item`, `fitmatch_set_closet_classification_override`, `fitmatch_clear_closet_classification_override`, `fitmatch_begin_comparison`, `fitmatch_complete_comparison`이다. 신규/변경 상품은 공개 클라이언트가 공용 catalog를 직접 쓰지 않고 `product_intake_requests`에 넣으며, 검증된 batch/Edge Function/service role만 공용 상품과 실측을 승격한다.
- `SECURITY DEFINER` RPC는 빈 `search_path`, `auth.uid()` 검증, 소유권 검증, anon 실행권 제거를 적용했다. 공용 상품 내부 schema는 RLS+무정책 기본 거부이며 authenticated 직접 쓰기를 차단했다. FK 인덱스 advisor 지적은 `086`에서 해소했다.
- 최종 Supabase advisor의 신규 runtime 관련 보안 표시는 private table의 의도적 `RLS+무정책` INFO와, 위 6개 인증 사용자용 `SECURITY DEFINER` RPC WARN뿐이다. 둘 다 설계 의도이며 공개 권한 검증을 통과했다. 프로젝트 설정에는 별도로 leaked-password protection 미활성 WARN이 남아 있어 Auth 출시 점검에서 활성화해야 한다. 새 runtime FK의 미인덱스 지적은 0건이고, 막 생성된 인덱스의 unused INFO는 트래픽 전이므로 삭제 근거가 아니다.
- 정책 버전 `db-runtime-2026-08-18-v1`을 추가하고 비교 허용을 family compatibility뿐 아니라 `required_any_measurements`/최소 충족 개수로 fail-closed 처리했다. Uniqlo/Musinsa 실측 alias와 단면·둘레 변환을 검증했다.
- 명확한 기존 DB 모순 4건을 교정했다. Uniqlo `E482204`, `E489180`은 underwear family, `E488163`, `E488426`은 pants family가 정답이다. DB QA gold도 같은 기준으로 갱신됐으므로 앱 연결 브랜치에서 로컬 JSON fixture와 분류 출력의 4건 parity를 반드시 맞춰야 한다.
- 최종 `fitmatch_qa.validate_product_runtime()`은 `passed=true`, 상품 1,542, snapshot 3,842/연결 3,842, 현재 분류 1,195, duplicate current 0, gold 5,026/5,026(100%), category-family contradiction 0, invalid comparable measurement 0, 공개 definer 권한 누수 0을 반환했다.
- 실제 인증 사용자로 known/unknown resolve, 옷장 등록/override/복원, 비교 시작, idempotent ingest, 동시 upsert 동일 UUID, Uniqlo↔Musinsa canonical 실측 3개 비교를 검증했고 임시 데이터는 모두 제거했다. exact lookup은 약 0.204ms, 최근 상품+현재 분류 조회는 약 2.143ms였다.
- 현재 운영 `product_sizes`와 `product_measurements`는 0건이다. 기존 batch snapshot에 실제 사이즈표 행이 없기 때문이다. 따라서 DB 구조·권한·프로시저는 준비됐지만, 앱에서 DB 비교를 활성화하기 전에 신뢰된 backend/batch가 실제 variant/size/measurement payload를 적재해야 한다.
- 구현 계약과 AS-IS/TO-BE, RPC 입출력, Swift 연동 순서, 실패 상태는 `Docs/FitMatchDBRuntimeContract-20260818.md`에 정리했다. 앱 출시용 현재 로컬 엔진은 이번 작업에서 변경하지 않았다. DB 전환은 새 브랜치에서 feature flag/dual-run parity로 단계적으로 수행한다.
- 관련 파일: `supabase/migrations/082_product_runtime_foundation.sql`부터 `086_product_runtime_fk_indexes.sql`, 안전 rollback `supabase/sql/087_product_runtime_safe_rollback.sql`, 운영 검증 쿼리 `supabase/sql/088_product_runtime_validation_queries.sql`.

## 55. 2026-08-18 신규 상품 자동 분류·비교 후보 정책 보완

- 사용자의 `보완해` 지시에 따라 앱 코드는 수정하지 않고 Supabase DB 구조/프로시저만 보완했다. 운영 프로젝트 `hnkplvyegonlhumlejst`에 `trusted_product_auto_classification_v2`, `comparison_candidate_policy_parity_v2`, `validate_product_runtime_v2`, `fix_product_exclusion_resolution_v3`, `backfill_product_runtime_v2_classifications` 5개 migration을 적용했다. 로컬 재현 파일은 `supabase/migrations/089`~`093`이다.
- 신규/변경 상품 자동 분류는 공개 앱 payload와 신뢰된 backend payload를 분리했다. `public.fitmatch_resolve_product`는 API가 보낸 audience/category codes까지 기존 공용 상품과 비교하지만 불일치 시 intake만 만들고 공용 사실을 쓰지 않는다. 검증된 batch/Edge Function만 `fitmatch_catalog.runtime_resolve_and_promote_product(jsonb)`를 호출해 상품·분류 이력을 승격한다.
- 5,026 Gold에서 `source+normalized path` 및 `source+path+product-name structural signature`별로 최소 2건 이상, 사용자 확인 0건, 최종 tuple 1종인 경우만 immutable profile로 만들었다. 신상품 ID로 바꾼 재생 기준 자동 확정 2,536건, 2,536/2,536 일치, 자동 오답 0이다. 나머지는 old runtime suggestion으로 확정하지 않고 `review_required`다.
- 최신 snapshot에서 동일 상품이 `excluded_review`로 검증된 경우와 동일 path의 2개 이상 상품이 전부 제외인 경우를 `not_comparable`로 승격한다. 유니클로 스카프 5개 같은 의도적 제외가 mapping row 부재 때문에 단순 gap으로 보이지 않게 했다. 자동 제외 path는 40개다.
- 기존 공용 상품 1,542개 중 current 분류가 없던 347개를 새 정책으로 backfill했다. 최종 current는 1,542/1,542이고 confirmed 1,114, not_comparable 184, review_required 244, current 중복 0이다. review 244는 제거 대상 데이터가 아니라 자동 확정 근거가 부족해 의도적으로 막힌 상태다.
- 비교 정책에 major category, gender/age, family, detail, sleeve/pants length, outer body length, canonical measurement overlap을 모두 포함했다. `fitmatch_find_reference_candidates(uuid)`는 `automatic`, `manual_selection`, `measurements_required`, `no_compatible_garment`를 구분한다. 반팔↔긴팔 상의는 자동 차단 후 소매길이 제외 manual extended, 긴바지↔반바지는 총장·밑단 제외 manual extended, sweatshirt↔hoodie는 direct, 상의↔하의는 항상 차단한다.
- 실제 인증 사용자 컨텍스트의 rollback 통합 검사에서 유니클로 `E422992` 반팔 T를 옷장 기준으로, `E492123` 긴팔 셔츠를 대상으로 넣었을 때 후보 상태 `manual_selection`, 자동 begin `blocked`, manual begin `pending`, 공통 실측 3개를 확인했다. `E447780` 하의 대상은 `no_compatible_garment`였다. 생성한 size/measurement/closet/run은 rollback 후 모두 0건임을 확인했다.
- trusted promotion rollback 검사에서 신규 긴팔 셔츠는 `verified_path_profile`로 confirmed, 기존 `E492123`의 category code 일치는 current 재사용, 다른 code는 `catalog_state=changed`+intake로 분리됐다. 공용 데이터 오염 없이 모두 rollback됐다.
- 최종 `fitmatch_qa.validate_product_runtime_v3()`은 `passed=true`, Gold 5,026/5,026, 신상품 자동 profile mismatch 0, category-family contradiction 0, invalid comparable measurement 0, cross-major blocked true, manual extended supported true, anon candidate RPC execute false를 반환한다.
- Supabase advisor의 새 항목은 비공개 profile 세 테이블의 `RLS enabled/no policy` INFO와 인증 사용자용 `fitmatch_find_reference_candidates` SECURITY DEFINER WARN이다. 전자는 deny-by-default, 후자는 `auth.uid()`와 user ownership filter를 가진 의도된 공개 RPC다. 신규 migration 관련 performance advisor 항목은 없었다.
- 계약서는 `Docs/FitMatchDBRuntimeContract-20260818.md`에 v2 흐름/상태/수량을 반영했고, `supabase/sql/087_product_runtime_safe_rollback.sql`과 `088_product_runtime_validation_queries.sql`도 신규 RPC/validator/profile 검증을 포함하도록 갱신했다.
- 남은 핵심은 운영 size/measurement 적재다. 현재 이 두 테이블은 0건이므로 앱 연결 브랜치에서 retailer fetch 결과를 trusted ingest로 적재하기 전에는 실제 DB 비교 점수 경로를 켜면 안 된다. 또한 신상품 자동 분류는 검증 가능한 2,536 profile 범위만 자동이며 모든 미래 상품 100% 자동 확정을 보장하지 않는다. 미지원/충돌은 review로 막는 것이 현재의 의도된 안전 동작이다.

## 56. 2026-08-18 유니클로·무신사 로컬 증분 배치 실행

- 앱 코드와 Supabase 운영 DB는 변경하지 않고 로컬 배치만 실행했다. 유니클로는 `python3 scripts/run-uniqlo-incremental-catalog.py --run-id 20260818-152230`, 무신사는 `python3 scripts/run-musinsa-incremental-catalog.py --run-id 20260818-152745`로 실행했다.
- 유니클로 최초 실행 `20260818-152132`는 샌드박스 네트워크 연속 실패로 수집 시작 전에 종료됐다. 상태 원장은 갱신되지 않았고 실패 증거로 `Docs/TestEvidence/UniqloCatalogIncremental/runs/20260818-152132/discovery/checkpoint.json`만 남겼다. 외부 네트워크가 허용된 재실행은 정상 완료됐다.
- 유니클로 재실행은 카테고리 200페이지, 요청 248회, 고유 상품 1,223개를 관측했다. category hydration 경로 불일치 47회는 의미 재요청으로 모두 복구됐고 `category_response_failures=0`, `discovery_complete=true`다. 요청 상태는 HTTP 200 247회, 404 1회였으며 최종 탐색 완전성에는 영향을 주지 않았다.
- 유니클로 상태 원장은 1,159개에서 1,235개로 늘었다. 신규/재시도 후보 77개 중 76개는 상품명·경로·상세·공식 사이즈표를 모두 확보했고, 공식 사이즈 행 471개와 실측 항목 2,219개가 수집됐다. MEN 22, WOMEN 40, KIDS 8, BABY 6이며 상품 ID 중복과 빈 상품명·빈 경로는 0개다.
- 유니클로 미완료 1개 `E479751`은 신규 상품이 아니라 2026-08-15부터 반복 노출되지만 상세를 가져올 수 없는 기존 `known_unavailable` 항목이다. 이번에도 `pending_retry`로 유지했다. 이번 탐색에서 보이지 않은 기존 상품 12개는 `missing_product_ids.csv`에만 기록했으며 삭제나 판매 종료 처리는 하지 않았다.
- 무신사 실행은 카테고리 감시 페이지 5개, 요청 5회, 고유 상품 230개를 관측했다. HTTP 200 5/5, 신규 48개, 상품 상세 저장 48개, 재시도 0개이며 상태 원장은 384개에서 432개로 늘었다. 상품 ID 중복과 빈 상품명·빈 카테고리 경로는 0개다.
- 무신사 신규 48개 중 공식 실측 행이 있는 상품은 34개이고 총 121개 사이즈 행을 확보했다. 실측 행이 0개인 14개는 모두 나일론/코치 재킷 계열 상품이며 상세 정보는 정상 저장됐지만 현재 공식 actual-size 응답에 실측이 없다. 이 14개는 상품·카테고리 증거로는 쓸 수 있지만 DB 실측 비교 데이터로 승격하면 안 된다.
- 무신사 `missing_from_current_catalog=202`는 판매 종료 수가 아니다. 현재 증분 수집기가 무신사 전체 약 62만 상품을 탐색하지 않고 제한된 5개 감시 페이지만 확인하므로, 기존 원장에 있으나 이번 표본에 없던 수량일 뿐이다. 삭제·비활성 판단에 사용하지 않는다.
- 최종 산출물은 `Docs/TestEvidence/UniqloCatalogIncremental/runs/20260818-152230/`과 `Docs/TestEvidence/MusinsaCatalogIncremental/runs/20260818-152745/`에 있다. 핵심 인수 파일은 각 폴더의 `summary.json`, `discovered_products.csv`, `new_product_ids.csv`, `new_product_inputs.json`, `new_products.csv`, `missing_product_ids.csv`이며 무신사는 `pending_retry.csv`, 유니클로는 `new_products/uniqlo_size_evidence.json`을 추가 확인한다.
- 이번 단계는 수집과 로컬 상태 원장 갱신까지만 완료했다. 신규 124개(유니클로 76, 무신사 48)를 Supabase `products`/`product_sizes`/`product_measurements`에 적재하거나 canonical 분류 프로시저를 실행하지 않았다. 운영 DB 반영은 별도 승인 후 trusted ingest 경로에서 수행해야 한다.

## 57. 2026-08-18 retailer 배치의 Supabase 적재·자동 분류 연결

- 바탕화면 사용자 진입점을 유니클로 command 1개, 무신사 command 1개로 유지했고 결과 폴더도 쇼핑몰별 1개씩 유지했다. 관련 사용자 항목은 총 4개다. 내부 연구/테스트 helper는 삭제하지 않았다.
- 두 증분 배치가 Supabase에서 현재 관측 ID의 batch marker/current 분류 존재 여부를 먼저 확인한다. 로컬 신규와 DB 미적재를 합쳐 상세·공식 사이즈를 수집하고, 상품별 DB 적재가 성공한 경우에만 로컬 원장을 완료 처리한다. DB 미완료가 하나라도 있으면 종료 코드 3과 재시도 ID를 남긴다.
- 공통 Python adapter `scripts/catalog_batch_common.py`를 추가했다. 유니클로 official sizeChart와 무신사 actual-size를 공용 product/variant/size/measurement payload로 변환하며 key는 환경/Keychain에서만 읽는다.
- 운영 DB migration `batch_product_ingest_api_v1`, `batch_measurement_scope_and_uniqlo_aliases_v1`, `grant_batch_taxonomy_read_v1`을 적용했다. public batch RPC 두 개는 `service_role`만 실행 가능하고 anon/authenticated는 모두 false다.
- `fitmatch_batch_ingest_product`는 한 트랜잭션에서 trusted product promotion/canonical classification 후 실측 적재를 수행한다. 분류 category를 measurement scope로 주입해 무신사 `허리단면`의 tops/bottoms 의미를 구분한다. 유니클로 현재 official sizeChart raw label 12개를 canonical alias로 보강했고 등 중심~소매는 기준이 달라 비교 불가로 보수 처리했다.
- service-role rollback 통합 테스트에서 신규 유니클로 반팔 T가 `tops/short_sleeve`, `가슴너비 55cm`가 `chest_width=55`, comparable=true로 기록됐다. rollback 후 테스트 상품 0건, 운영 product 1,542/size 0/measurement 0은 유지됐다.
- 최근 로컬 결과 124건을 adapter로 변환한 결과 유니클로 76상품/471사이즈/2,216 numeric 실측, 무신사 48상품/121사이즈/398실측, 빈 상품명·경로 0이다. 아직 Keychain에 secret key가 없어 실제 124건 backfill 배치는 실행하지 않았다. 최초 command 실행 때 키를 한 번 입력하면 현재 관측 범위를 backfill하고 이후 batch version 기준 증분 처리한다.
- 유니클로 `E479751`처럼 base URL이 `/00` 404로 잘못 redirect되는 경우를 위해 상세 수집기가 base → `/01` → `/00` 후보를 순서대로 재시도하도록 보완했다.
- 앱/Swift 연결 로직은 이번 작업에서 수정하지 않았다. Supabase advisor에 새 batch 관련 보안/성능 경고는 없고 기존 private RLS INFO, 인증 사용자용 definer WARN, leaked-password protection WARN만 유지된다.
