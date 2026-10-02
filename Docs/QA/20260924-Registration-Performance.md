# 링크 등록 성능 개선 — 두 항목

## 범위

1. 최종 저장의 authoritative readback을 전체 옷장 목록에서 승인된 closet_item_id 단건으로 제한한다. 저장 확인, client_item_id, source snapshot, 계정 전환 및 재시도 검증을 유지한다.
2. get_product_runtime_for_swift가 덮어쓰는 기본 canonical/readiness 생성만 건너뛴다. 최종 context canonical/effective readiness와 기존 get_product_runtime 응답은 유지한다.

## 격리 검증

`python3 /tmp/run_fitmatch_performance_check.py performance` exit0 PASS.
로그 `/tmp/fitmatch-deploy-performance-zdbirp9s/run.log`.
실제 배포 함수 정의와 column type을 읽기 전용으로 수집한 fixture를 사용했다. underlying canonical/readiness/group 함수는 결정적 stub이므로 실제 전체 DB replay나 실제 상품 E2E 증거가 아니다.

- 기존/개선 전체 목록 JSON 동일.
- 단건 JSON이 기존 목록에서 해당 ID의 row와 동일: raw unknown, canonical, exact detail, observation receipt 포함.
- 다른 사용자, 삭제된 ID, 없는 ID는 빈 결과. 익명 권한 차단, 로그인 없는 호출 거절.
- 기본 runtime 응답 동일, 최종 runtime GLOBAL_CONFIRMED/USER_OVERRIDE 응답 동일.
- 2사이즈 fixture에서 최종 context 호출2회 유지. 버려질 base 호출0회, readiness1회.
- rollback 실행 PASS. 사용자 데이터 변경 없음.

## 운영 경계

DB 대상은 사용자 확인 개발 프로젝트 hnkplvyegonlhumlejst/FitMatch. migration preflight가 대상 기존 함수 해시를 검사하며 drift면 중단한다. 변경 자체에 INSERT/UPDATE/DELETE/사용자 row rewrite 없음.

실제 wall-clock 개선시간과 실기기 E2E는 NOT RUN. RPC 왕복 횟수는 저장1회+단건조회1회로 동일하고, 조회량/중간계산을 줄이는 작업이다.

## 최종 적용·검증

- 개발 DB 적용 완료: local 20260924120000 → remote 20260924035231 closet_single_item_readback; local 20260924121000 → remote 20260924035245 runtime_skip_discarded_projections.
- remote migration SQL과 local byte MD5 동일: a9a5ed873c74f57d10fbd86ebc76820d / 29ae7aef8fc7ccea68e330614ec26c4a.
- 읽기 전용 postflight 10/10 true: RPC 존재/로그인 허용/anon 차단/내부 불완전projection 비공개/owner/exactID/deleted 필터/중간계산 생략/최종context/readiness 유지.
- begin/complete/candidate2overloads/canonical2함수/product_measurement_readiness 정의 해시 변경 없음.
- Swift RED: SingleReceiptRed 45PASS/1FAIL, 기존 listCallCount=1. 변경후 production Action은 acceptedClosetItemID로 getClosetItem RPC를 호출하고 응답의 clientItemID와 closetItemID를 모두 검증한다. 동일 saved receipt projector 유지. 생산용 유일 conformer인 SupabaseDomainClient가 단건 RPC를 구현; protocol 기본 list 호환은 기존 injected test remotes용이며 생산 경로는 사용하지 않는다.
- 최종 전체 테스트 PASS exit0: 908 tests=866PASS/0FAIL/42skipped. `/tmp/FitMatchRegistrationPerformanceFinal.xcresult`, `/tmp/fitmatch-registration-performance-final.log`, `/tmp/fitmatch-registration-performance-summary.json`.
- 명령: `xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchSameGroupRetry -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests -resultBundlePath /tmp/FitMatchRegistrationPerformanceFinal.xcresult test`.
- 앱·테스트 컴파일 포함. 별도build/실기기E2E/인증된실물저장/실제시간측정 NOT RUN. SQL fixture는 위에 명시한 제한 유지.
- Rollback은runtime→single-item역순. 배포전단건조회앱을이전버전으로돌리거나호환계획없이단건RPC삭제금지. commit/push없음.
