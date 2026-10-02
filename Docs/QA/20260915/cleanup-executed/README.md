# 정리 실행 결과

2026-09-15, 미커밋 작업을 포함한 connectDB/a68c849 기준. 기존 사용자 변경 보존, 커밋·푸시 없음.

## 제거 완료

- 사용하지 않는 Swift 4개: BrandDatabaseView, ShoppingProductFormView, MusinsaWebViewParser, COSParser. 현재 미지원 COS 내부 파서 테스트 2개와 전용 spy를 함께 보관·제거했다. 실제 지원 URL 거부/지원 브랜드 검사는 유지했다.
- 과거 전달용 ZIP 9개와 빈 maxOffset 파일 제거.
- 중복 원장 전체본 제거, **Git에 관리되는 분할본 46개 유지**. 전체/분할본의 149,475개 행 다중집합이 같음을 확인했다. 초기 작업 중 분할본을 제거했으나 Git 재현성을 위해 최종적으로 분할본을 원래 바이트 그대로 복원하고 ignored 전체본을 제거했다. 최종 결과는 15개 파일, 156,744,386바이트(약 149.5MiB)의 작업 폴더 감소다. Git 과거 용량 회수는 하지 않았다.
- Supabase 기존 FitMatch hnkplvyegonlhumlejst: 미사용 함수 3개를 DROP RESTRICT로 제거하고, 보관 완료한 is_current=false 분류 이력 118개 제거. 현재 이력 27개와 사용자 데이터는 유지했다.
- 실제 적용 migration: **20260915064910_cleanup_retired_paths_and_align_group_readiness**. 적용 SQL은 supabase/sql/cleanup_retired_paths_Apply.sql이다.

## 구형 경로 재사용 방지

1. effective_target_classification_detail_legacy(uuid), legacy_comparison_group(text), authorize_comparison(uuid,uuid,uuid,boolean) 진입점을 실제로 제거했다.
2. product_readiness_with_context의 준비상태 계산은 구형 product_readiness_with_context_v1에서 현재 product_measurement_readiness로 연결했다. 기존 상품 단위 검증·SET 차단·미확인 구조 복구 분기와 함수 실행 권한은 보존했다. 과거 데이터의 값 자체를 바꿔 정상인 것처럼 만들지 않았다.
3. 이미 현재 그룹을 사용하는 실제 effective_target_classification 함수에 구형 상세분류 값 변경을 넣는 격리 회귀검사를 수행했다. legacy garment/length/status/source를 바꿔도 그룹 C·CONFIRMED 및 권한 JSON 전체가 동일했다. 이 검사는 실제 함수와 격리된 그룹 의존성 fixture를 사용하며 실제 인증 E2E는 아니다.
4. 아직 배포되지 않은 20260915093000_align_confirmed_group_readiness_contract.sql은 원안을 보관하고 읽기 전용 계약 검사로 퇴역시켰다. 이 예전 원안은 미확인 상품 단위를 NOT_APPLICABLE로 표시하거나 권한을 덮어쓸 수 있었다. 앞으로 이 파일을 실행해도 함수/권한을 재작성하지 않는다. 전체 빈 DB migration 재생은 미검증이다.
5. supabase/sql/cleanup_retired_paths_Verify.sql을 추가하고 실제 서버에서 5개 항목 모두 PASS를 확인했다. 제거 진입점 재등장, 구형 준비상태 연결, 그룹 판단의 구형 의존, 슬랙스 매핑/검증 함수 변경을 재검수하는 읽기 전용 검사다. 예약 자동 실행을 설정한 것은 아니다.

## 검증 결과

- **PASS:** 삭제 후 전체 FitMatchTests 및 현재 UI 감사 4개 합계 779 PASS / 0 FAIL / 42 SKIP(미실행). 현재 UI는 온보딩/탭/개인정보·지원/잘못된 링크·비어 있는 링크 동작을 포함한다. 이전 778 집계는 live test 포함 및 COS 테스트 포함으로 분모가 달라 직접 비교하지 않는다.
- **PASS:** 삭제 후 실제 무신사 링크 3개 재조회(별도 테스트 1개). 6372903 사이즈명 3개·실측 15개 대조, 6372893, 슬랙스 5746364 실측 조회 유지. live-products.json 참조.
- **PASS:** 격리 PostgreSQL에서 정확한 삭제 SQL 실행. 구형 준비상태 호출 재현 후 새 분기로 전환, 미확인 구조 복구 유지, 세트/다중 컴포넌트 차단 유지, 측정 부족/정책 없음 차단 유지, 과거 이력만 118개 삭제, 현재 이력 유지, 함수 3개 제거 확인.
- **PASS:** 서버 사후 조회에서 함수 3개 없음, 과거 이력 0개, 현재 이력 27개, 기존 ACL 유지. 상품·옷장·비교·그룹 매핑·현재 분류 이력의 전후 내용 해시 모두 동일.
- **PASS:** 저장 상품 30개 전후 ready/status 변경 0개. 미매핑 상품의 그룹 선택이나 실제 실측 근거 부족으로 차단되는 상태는 정리로 임의 해제하지 않았다.
- **PASS:** 구형 상세분류 변경에 대한 현재 그룹/권한 결과 불변, 보호 스크롤 및 git diff --check.
- **BLOCKED / NOT RUN:** 실제 Apple 로그인 계정 등록·비교·저장 왕복, 실기기 점검, 빈 DB 전체 migration 재생. 로컬 검사나 읽기 조회를 실제 계정 E2E 성공으로 보고하지 않는다.

## 복구 및 유지 범위

보관 위치: `/Users/jinyoung/Developer/FitMatchLocal/CleanupArchive/20260915/`.

- removed-source-and-zips.tar.gz: 제거 전 코드·전달 파일 및 겹치는 테스트 파일 원문. SHA-256 c3195fe605f606f16c46173f2c2ed0e0b906fa268537bd80895f1f361d83f53d.
- server-preimage.json: 함수 정의/권한 및 과거 분류 이력의 의미상 보관본.
- history-exact.json: 서버 원문 바이트 보관본. SHA-256 b3697e52bc2e05935cd96182ab2c9d06b7caf4949a64aa72f17294905bdd74e1. JSON 숫자 스케일이 도구 중간 변환으로 바뀌는 것을 발견해 base64로 원문을 추출하고 서버 MD5 331f4f521fd5a0e1c001524a7d8cd4a4와 일치 검증 후에만 삭제했다.
- local-setup.sql / local-check.sql / old-detail-invariance.sql: 격리 회귀 재현 자료. 사용자 원문 이력이 포함된 setup은 저장소 안에 넣지 않았다. 임시 PostgreSQL은 종료했다.
- superseded-readiness-proposal.sql: 미배포 구형 수정안. 적용용이 아니라 보관용이다.

Docs/Research·Docs/TestEvidence, 사용자 데이터와 원시 실측, 그룹/측정 정책, 현재 호출되는 legacy 이름의 비교 wrapper, migration 과거 이력은 유지했다. 이 자료가 존재한다는 이유만으로 앱이 읽거나 권한을 갖는 것은 아니다. 확인한 실행 경로의 구형 의존을 제거했고 모든 향후 변경에 대한 무오류를 보장하는 것은 아니다.

상세 서버 전후 상태와 Xcode 결과 경로: [cleanup-executed-evidence.json](../cleanup-executed-evidence.json). 최종 삭제 목록: [removed-files.json](removed-files.json).
