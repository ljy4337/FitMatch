# 승인된 개발 DB·안전 수정 — 2026-09-16

## 범위와 적용 상태

사용자가 hnkplvyegonlhumlejst를 **개발 DB**로 정정하고, 브리핑 후 코드/DB 수정을 승인했다. 이전 Release Audit v2의 이 프로젝트 READ ONLY 제한은 이번 승인 범위에 한해 대체됐다. get_project는 동일 FitMatch/ap-northeast-2를 확인했다. 사용자 옷장·History·계정 데이터를 직접 수정하는 테스트는 하지 않았다.

| 순서 | 문제 | 실제 수정 |
|---|---|---|
| 1 | 화면 삭제 완료가 서버보다 빠름 | 서버 목록/정확한 ID → 삭제 receipt → local commit 순서. 동기화와 직렬화, 계정 변경·오류·취소 시 local 성공 금지 |
| 1 | 서버는 삭제했지만 응답을 못 받은 재시도 | 계정별 삭제 intent 유지. retry는 최신 목록의 부재 또는 정확한 삭제 receipt 확인. 다음 sync에서 local 잔여행도 제거해 재업로드 방지 |
| 2 | 옛 기준옷 flag가 후보 순서/판정을 바꿈 | internal/public 2-arg candidate 함수에서 reference 기반 순서·AUTOMATIC 분기 제거. 사용자 explicit 선택, 같은 그룹 우선 유지 |
| 3 | UNIQLO 두 renamed breadcrumb 경로 누락 | 검증된 두 category key에만 옛/새 경로 호환 추가 |
| 3 | ZARA skirts 허리·엉덩이 연결 누락 | 현재 parser + skirts 문맥 alias 2개 추가. 기존 FLAT_WIDTH canonical/value 유지 |
| 4 | 중복 응답의 Dictionary 충돌 가능성 | Closet sync/삭제/candidate projection에서 duplicate client/server ID를 계약 오류로 거절. 임의 중복 제거/first 선택 없음 |
| 4 | 삭제 실패 이유 구분 | 동기화 중, 계정 변경, 완료 불확실, 서버 성공/local 실패를 구분하여 다음 행동 표시 |

## 개발 DB에 실제 적용한 것

1. migration `retire_reference_candidate_authority`: `fitmatch_vnext.find_reference_candidates(uuid,uuid)`와 public wrapper 교체.
2. migration `uniqlo_verified_path_compat_and_zara_skirt_aliases`: product_comparison_group 호환 변경 + ZARA alias 2개.

두 apply_migration 응답 모두 success. 사후 READ ONLY 확인에서 local 검증본과 두 후보 함수 MD5 일치, legacy 정렬/분기 제거 확인. 경로 patch 존재, 12개 resolver 조건 결과 확인. 새 canonical/policy metric/사용자 row 변경 없음. 3-arg requested-group 구현은 유지.

## 검증

| 검사 | 상태 | 정확한 범위 |
|---|---|---|
| 삭제 트랜잭션 | PASS | 실제 Foundation transaction 원문: 순서, 네트워크 불확실/재시도, history/list 실패, 잘못된 receipt, 계정 변경, local save 실패. 7 tests/10 parameter cases |
| 후보·중복 계약 | PASS | 실제 DTO/validator 원문: 기존7 + 중복 row index1 = 8 tests |
| 한 번에 재실행 | PASS | `bash scripts/test-candidate-envelope.sh`: 15 tests/2 suites. 독립 앱 사용 15건이 아님 |
| 후보 SQL 수정 전 | FAIL (예상 재현) | 격리 PostgreSQL의 실제 함수가 기준옷 flag 변경에 따라 다른 후보 반환 |
| 후보 SQL 수정 후 | PASS | 같은 검사: 7그룹×2 flag 상태 동일, 같은 그룹 우선, 공통실측1개, 타그룹, 무실측 제외, 다른 사용자/삭제행 제외, auth/variant 거절. 하위 eligibility는 통제 fixture |
| 경로/사전 인접 회귀 | PASS | 실제 사전 snapshot 기반 local PostgreSQL: 경로1,065조건 중 의도4개, 실측91조건 중 의도2개만 변경 |
| SQL 재적용 | PASS | 위 두 local DB에 동일 SQL 재적용, 회귀 그대로 통과 |
| 연결 개발 DB 사후검사 | PASS | 함수 hash/경로 marker 및 resolver12조건. 시험값17cm이며 실제 상품 비교 아님 |
| iOS build/test build | PASS | generic iOS, unsigned. 실제 앱 및 FitMatchTests/FitMatchUITests 컴파일 성공 |
| 보호 스크롤/diff | PASS | 기존 보호 파일/호출부 변경 없음, whitespace 검사 |
| SwiftData·History 전체 테스트 실행 | NOT RUN | test build만 수행. macOS Foundation tests와 구분 |
| 실제 앱 등록→비교→History→재실행 | NOT RUN | 합의대로 사용자가 최신 아이폰 빌드에서 진행 |

로그: `/tmp/fitmatch-approved-repair/`의 `final-contract-tests.log`, `final-test-build.log`, `final-build.log`, `candidate-before.log`, `candidate-after.log`, `mapping-regression.log`, `db-postflight.json`.

## 변경 파일

- FitMatch/Services/FitMatchClosetDeletionAction.swift
- FitMatch/Services/FitMatchClosetDeletionTransaction.swift (new, 실제 실행 ordering owner)
- FitMatch/Services/FitMatchClosetSyncCoordinator.swift
- FitMatch/Services/FitMatchServerAuthorityCoordinator.swift
- FitMatch/Services/FitMatchVNextContractValidator.swift
- FitMatchTests/FitMatchClosetDeletionTransactionTests.swift (new)
- FitMatchTests/FitMatchCandidateEnvelopeTests.swift
- FitMatchTests/FitMatchComparisonSyncCoordinatorTests.swift (nil service로 성공을 가정하던 fixture에 명시적인 server receipt mock 제공; 기존 성공/실패 assertion 유지)
- scripts/test-candidate-envelope.sh
- supabase/sql/retire_reference_candidate_authority_Apply.sql (new)
- supabase/sql/tests/retired_reference_candidates_LocalRegression.sql (new; local-only)
- supabase/sql/uniqlo_path_zara_skirt_20260916_Apply.sql (개발환경 주석 갱신; 기존 검증된 body 적용)
- 지도/인수인계/이 보고서.

## 사용자 아이폰 확인표

**새 빌드 설치 후** 진행한다. DB 변경은 이미 반영됐지만 삭제/오류 방어는 새 앱 바이너리가 필요하다.

1. 무신사·유니클로·자라 각각 상품1개 불러오기 → 정확한 사이즈로 옷장 등록 → 다시 열어 확인.
2. 내 옷 직접 선택 → 비교 → 다른 사이즈 결과 → History 확인 → 앱 종료/재실행 후 확인.
3. 다른 그룹의 옷 선택도 확인. 불가하면 그 이유가 이해되는지 확인.
4. 옷1개 삭제 → 목록/비교 후보에서 없어졌는지 → 재실행 후에도 없는지 확인.
5. 삭제 직전 인터넷을 끊고 시도 → 성공으로 사라지지 않는지, 안내 후 연결을 복구하고 재시도되는지 확인. 다시 연결되면 보류된 삭제가 동기화로 완료될 수 있음.
6. 유니클로 E488182/E483880 및 실측이 제공되는 자라 스커트에서 그룹/허리·엉덩이 확인.

실패만 `URL / 누른 버튼 / 실제 현상 / 사진`으로 전달. 모든 상품 무오류 또는 실기기 완료를 이번 코드검사로 주장하지 않는다. 새 실측을 인식하면 이후 비교 coverage/결과는 정상적으로 달라질 수 있다. 과거 완료 snapshot은 변경하지 않았다.

## Git

connectDB / ae69b30ed37386f6361882d36bafbd972235ebd4 유지. 기존 미커밋 작업 보존, commit/push 없음. 이번 실제 사용자 앱 테스트는 수행하지 않았다.
