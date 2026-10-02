> 후속 실행 완료: [정리 결과](cleanup-executed/README.md). 아래는 실행 전 후보 검수 기록이다.

# FitMatch 2차 제거 후보 검수

검수일: 2026-09-15. 로컬 `connectDB`, HEAD `a68c8496628eb0bc1223b34708fb88e8fe945de1`와 미커밋 변경 포함. Supabase `hnkplvyegonlhumlejst` 실제 배포 상태를 읽었다. **이번 작업에서 앱 파일·서버 객체·데이터는 삭제하지 않았다.**

## 결론

가장 먼저 정리할 것은 중복 산출물과 호출되지 않는 Swift 파일이다. 서버 함수 3개는 제거 검증 대상으로 좁혔다. 남은 vNext 상품 30개는 모두 보호 대상에 연결되어 있어 추가 상품 삭제를 권하지 않는다. 과거 catalog 전체와 상세분류 기능은 이름만 보고 삭제할 수 없다.

## 1. 로컬 파일 제거 후보

| 대상 | 근거 | 판정 / 제거 조건 |
|---|---|---|
| `maxOffset` | 루트의 0바이트 파일. Xcode 소스/리소스 그룹 외부 | 우선 제거 후보 |
| 루트 `*ChangedFiles*.zip` 등을 포함한 ZIP 9개 | 과거 전달용 묶음, 합계 2,582,589바이트. Xcode 빌드 대상 외부 | 별도 보관본 확인 후 작업 폴더에서 제거. 원본 소스나 migration으로 취급하지 않음 |
| `FitMatch_Hardcoded_Product_Classification_Ledger_20260828.jsonl` 또는 `..._parts/` 중 한쪽 | 각각 154,087,701바이트. 149,475개 행의 SHA-256 다중집합이 완전히 같음. 행 순서가 달라 파일 단위 해시는 다름 | 한 표현만 유지하면 약 147MiB 절감. 전체와 분할본 중 유지할 쪽을 정하고 관련 문서 경로 조정. 두 쪽 모두 삭제하지 않음 |
| `FitMatch/Views/BrandDatabaseView.swift` | 92줄. 이 파일 밖 앱 소스에서 `BrandDatabaseView`, `BrandProductCard` 참조 없음 | 제거 후보. 삭제 후 빌드·탭 이동 검사 |
| `FitMatch/Views/ShoppingProductFormView.swift` | 814줄. 파일의 최상위 화면/보조 타입이 다른 앱 파일에서 호출되지 않음. 현재 링크 흐름은 CompareFlowSheet 계열 | 제거 후보. `FitMatchP0RemediationRegressionTests.swift:270`에 파일 경로 기반 검사 참조가 있어 해당 검사를 현재 화면으로 이관한 뒤 삭제 |
| `FitMatch/Services/MusinsaWebViewParser.swift` | 322줄. 생성/주입 호출 없음. 현재 ProductURLParserService는 MusinsaParser 사용 | 제거 후보. 실제 무신사 링크 및 사이즈표 복구 회귀검사 후 확정 |
| `FitMatch/Services/COSParser.swift` | 617줄. 현재 URL 파서 진입점은 MUSINSA/UNIQLO/ZARA만 사용. COSParser는 테스트에서만 생성 | 조건부 후보. 현재 출시 범위에는 불필요하지만 향후 COS 지원용이라면 보관. 관련 COS 테스트도 함께 정리해야 함 |

Swift 후보는 정적 호출 검수 결과다. 제거한 소스로 컴파일·실행하지 않았으므로 제거 후 정상 동작이 입증된 상태는 아니다. Xcode의 FitMatch 폴더는 파일 시스템 동기화 그룹이므로 파일명이 project.pbxproj에 없다는 이유로 빌드 제외라고 판단하지 않았다.

## 2. 용량이 큰 자료: 보관 후 작업 폴더에서 분리

- `Docs/Research` 약 3.6GB, `Docs/TestEvidence` 약 1.1GB. 앱 런타임 번들 대상은 아니지만 검증 재현 자료다. 전체 삭제 후보로 확정하지 않는다.
- 큰 경로: `Docs/Research/NewClothingCorpus-320-Retest-20260806` 약 851MB, `NewClothingCorpus-320-Third-20260806` 약 563MB, `CategoryCorpus-live-uniqlo-full` 약 558MB, `NewClothingCorpus-320-20260806` 약 426MB. `Docs/TestEvidence/UniqloCatalogIncremental` 약 1.1GB.
- `scripts/build-new-clothing-corpus.py`, `scripts/build-reference-closet-target-candidates.py`, `scripts/run-uniqlo-incremental-catalog.py`와 `FitMatchTests/ReferenceClosetCandidates.json`에 실제 경로 참조가 있다. 마지막 파일의 경로는 provenance이며 런타임 파일 읽기와 동일하게 취급하지 않는다. 재생성 도구와 함께 외부 보관하고 경로를 조정하는 방식이 적절하다.
- 위 용량은 `du` 표시값이며 확보 공간 보장이 아니다. `.git` 약 265MB는 이번 제거 대상에서 제외한다. 파일 삭제와 Git 과거 객체 공간 회수는 별개다.

## 3. Supabase 함수 제거 후보: 3개

| 정확한 시그니처 | 현재 근거 | 판정 |
|---|---|---|
| `fitmatch_vnext.effective_target_classification_detail_legacy(uuid)` | 앱/로컬 Edge/배포 Edge 및 수집한 DB 함수 본문에서 외부 호출 없음. pg_depend 역참조 0. 현재 effective_target_classification은 별도 함수 | 제거 우선 검증 후보 |
| `fitmatch_vnext.legacy_comparison_group(text)` | 같은 범위에서 호출 없음, pg_depend 역참조 0. 현재 비교 그룹은 서버의 product/Closet group 함수가 담당 | 제거 우선 검증 후보 |
| `fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)` | 다른 함수 본문에서 호출 없음, pg_depend 역참조 0. 현재 경로는 authorize_comparison_with_context 계열 | 조건부 제거 후보. 외부 직접 RPC 사용 여부 확인 필요 |

세 함수 모두 authenticated/service_role 실행 권한이 남아 있다. DB `track_functions=none`이므로 통계의 0회 호출은 미사용 증거가 아니다. PostgreSQL의 의존성 목록은 PL/pgSQL 문자열 본문·동적 SQL·외부 소비자 전체를 증명하지 않는다. 따라서 **바로 DROP 가능하다는 판정이 아니라, 세 함수로 범위를 좁힌 제거 후보**다. 실제 제거 시 정의·권한을 보관하고 격리 DB에서 `DROP ... RESTRICT` 및 등록/비교/복구 회귀를 먼저 검증한다. CASCADE 삭제는 권하지 않는다.

## 4. Supabase 데이터 및 테이블

| 대상 | 현재 건수/연결 | 판정 |
|---|---|---|
| vNext 상품 | 30개, 미참조 상품 0개 | 유지. 옷장 product/variant/size, 비교 target/variant/recommended size, 사용자 override/feedback 참조를 합친 보호 집합으로 확인 |
| 상품 수집 영수증 `product_ingestion_receipts` | 104개, product_id 없음 0개, 상품 고아 0개 | 유지. 재시도 및 UNIQLO 원본 분류 경로 복원에서 실제 사용 |
| `fitmatch_catalog.product_classification_history`의 `is_current=false` 행 | 전체 145개 중 과거 118개, 현재 27개 | 보관 후 정리 후보. 현재 view는 is_current만 사용. 단 감사/복구 기록 가치와 별도 운영 도구 사용 여부 확인 전 삭제 금지 |
| `fitmatch_catalog.products`, `product_classification_history`, `releases`, `current_product_classifications` 및 관련 sync 함수 | 27상품/145이력/15release. 제품↔이력↔release FK, 현재 view와 body-length 동기화 트리거 연결 | 묶음 퇴역 검토 후보. 앱·Edge의 직접 참조는 발견되지 않았지만 연결 객체·과거 migration/운영 의존이 있어 개별 DROP하지 않음 |
| 카테고리 그룹 매핑 | 931개 | 유지. 방금 적용한 슬랙스 포함. 현재 저장 상품이 적다는 이유로 지우면 새 링크 처리가 퇴행함 |
| 상세분류 mapping/signal, garment types, 비교 정책/측정 매핑 | mapping 2,249개, source signal 2,481개, garment type 60개, 비교 policy 44개, 측정 mapping 45개 | 현재 classification_decision/ingestion/readiness/측정 검증 연결이 남아 있음. 상세분류 UX 폐기와 서버 내부 계약 제거를 동일하게 취급하지 않음 |
| 옷장·비교·사용자 피드백 | 옷장 46개, 비교 10개, override 4개, feedback 6개 | 사용자 데이터라 유지. 테스트용이라고 추정해 삭제하지 않음 |

1차 정리 후 회수 가능한 DB 물리 공간이 있을 수 있지만, 테이블 표시 크기를 곧바로 불필요 데이터 크기로 보지 않는다. 이번에는 VACUUM FULL이나 재작성도 수행하지 않았다.

## 5. 제거하면 안 되는 오인 후보

- `begin_comparison_legacy_20260914(jsonb)`: 현재 begin_comparison이 requested group 없는 요청을 이 함수로 전달한다. 이름에 legacy가 있어도 사용 중이다.
- `ingest_product_observation_v2`, `authorize_comparison_with_context_v1`, 기존 candidate/eligible 오버로드: wrapper/호환 경로에 연결되어 있다. 단순 버전명 기준 삭제 불가.
- `set_closet_reference`/`unset_closet_reference` 및 public bridge: UI의 영구 기준 옷 정책은 폐기됐지만 Swift sync/submission 경로와 resolver에 아직 호출 코드가 있다. 먼저 호환 경로를 정리해야 한다.
- `validate_garment_axis_values`, `protect_completed_comparison`, `handle_new_user` 등: 일반 함수 호출이 없어 보여도 실제 활성 트리거로 호출된다.
- `MeasurementSourceIdentity.swift`: 타입명 검색만으로는 미사용처럼 보이지만 extension의 `.sourceIdentity`를 MeasurementComparisonEngine/ComparisonProfileMatcher가 사용한다.
- `KeyboardDismissModifier.swift`, `ScrollPerformanceDiagnostics.swift`: extension modifier를 실제 화면이 사용한다. 보호 스크롤 동작과 관련된 변경은 별도 범위다.
- `CanonicalTaxonomyBundle`의 JSON 4개: CanonicalTaxonomyBundleStore가 리소스 읽기·해시 검사를 수행한다. 원시 조사 JSON과 구분해 유지한다.
- 배포 Edge `product-observation` v5와 `delete-account` v1: 앱 호출 존재. 둘 다 유지.
- `supabase/migrations`, 현재 테스트 fixture, 최신 QA 증거: 적용 이력/재현/회귀검증에 필요. 오래됐다는 이유만으로 제거하지 않음.

## 검증 범위와 한계

PASS: 현재 앱 소스의 타입/생성/extension/RPC 참조, Xcode 동기화 그룹, Supabase 사용자 함수 114개·테이블 33개·view 1개, 활성 트리거/함수 역참조, 실제 행 수, 배포 Edge 2개 내용, 중복 원장 행 일치 검수.

NOT RUN: 제거 후 빌드·테스트, 실제 로그인 계정 왕복, 외부 운영 클라이언트의 전체 호출 관찰. 이번 결과는 제거 후보 보고서이며 제거 완료 보고서가 아니다. 일부 목록은 여러 읽기 쿼리로 수집해 단일 트랜잭션 스냅샷은 아니다.

기계 판독 근거: [cleanup-review-evidence.json](cleanup-review-evidence.json). 상세 서버 함수 정의는 이번 검수의 임시 파일 `/tmp/fitmatch-cleanup-inventory.json`에 보관했다. 데이터·앱 코드는 변경하지 않았다.
