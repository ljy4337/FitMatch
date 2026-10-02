# QA 테스트 준비 재검증 — 2026-10-02

**부분 준비 완료: 실행 가능한 대표 검사는 통과했지만, 전용 개발 계정과 실제 인증 DB/일부 정책·본검사 연결이 남아 있습니다.**

QA HEAD `086617f49cd19c8c3e2777e75efa820d7f886b5f`, FitMatch-QA / Debug-QA / 개발 hnkpl 대상. 기존 변경 보존, production Swift·UI·DB 정책 수정 없음. 신규 자료는 로컬 미커밋이며 push/merge/deploy하지 않았습니다.

## 이번 실제 실행

| 명령 | 판정 | 정확한 범위 |
|---|---|---|
| `python3 scripts/release_qa.py preflight --output /tmp/FitMatchPrepResumePreflight` | BLOCKED, exit 2 | QA/도구/데이터 고정/시뮬레이터/공간 PASS. 정책·계정 BLOCKED |
| `python3 -m unittest discover -s scripts/tests -p test_release_qa.py -v` | RED exit 1 → GREEN exit 0, 13 PASS | 실행 종류 누락·중단 결과 재사용 결함 재현 후 수정. 제품 검사가 아님 |
| `python3 scripts/test_release_qa_db.py -v` | PASS, exit 0, 9개 | 운영 DB/잘못된 사용자·키 차단 등의 오프라인 보호 검사 |
| `python3 scripts/release_qa.py smoke --output /tmp/FitMatchPrepResumeSmoke` | FAIL, exit 2 | 새 연속 fixture의 코드·ID 가정 오류 확인. 이전 결과 보존 |
| 새 연속 suite 집중 실행 2회 | FAIL, exit 65 | 진단 → runtime fixture 보정 → local/server ID 가정 오류 확인. 정확한 명령은 evidence/Resume20261002 로그 |
| `python3 scripts/release_qa.py smoke --output /tmp/FitMatchPrepResumeFinal` | 전체 BLOCKED, exit 2 | **QA 앱 빌드·37개 메서드/49회 실행 PASS, 0 FAIL/0 skip.** 발견 검사 PASS. 실제3사 parser 각1URL PASS. DB·정책만 BLOCKED |

- 최종 [집계 JSON](evidence/FitMatchPrepResumeFinal/results.json), [앱 명령/로그](evidence/FitMatchPrepResumeFinal/app.log), [Xcode 요약](evidence/FitMatchPrepResumeFinal/app-summary.json), [발견 목록](evidence/FitMatchPrepResumeFinal/discovered-tests.json).
- Xcode 최상위 요약의37개는 메서드 수입니다. 두 매개변수 테스트의14회 실행을 펼치면 총49회입니다. 이를 중복 합산하지 않습니다.
- live parser는 별도 XCTest1개에 MUSINSA/UNIQLO/ZARA 각1URL이 포함됩니다. 각각2/7/4사이즈를 수집했습니다. DB ingestion/저장 증거는 아닙니다.
- 원본 xcresult: `/tmp/FitMatchPrepResumeFinal/app.xcresult`, `live-parser.xcresult`. 소스 해시: `evidence/resume-source-fingerprints.json`.
- 마무리 확인 PASS: `git diff --check`, 보호 스크롤 무변경, 실행한 소스9개 해시, 계획4개/데이터69개 해시 고정, 변경파일 목록 존재 확인. `report --output /tmp/FitMatchPrepResumeFinal` 재집계도 exit2이며 정책·DB 두 BLOCKED를 유지합니다. 마지막 디스크 조회 여유16GiB, 주간 사용량38%/잔여62%입니다.

## 추가된 준비물

- `FitMatchReleaseContinuationTests`: 같은 ViewModel에서 다른 내 옷으로 새 비교 후 승인된 대체 사이즈 batch 분리 검증; 결과에서 L 등록→정확 read-back 투영→등록한 옷으로 새 비교. 실제 production owners, synthetic RPC.
- `FitMatchReleaseTransportFaultTests`: 실제 Supabase SDK/앱 RPC에7종 오류×6경계 +삭제 성공 대조군. 15회 실행, 43개 가로챈 HTTP 요청. 실제 네트워크·DB 쓰기0. 삭제는 로컬 commit 금지까지 확인합니다. 나머지 mutation은 transport 실패 전파까지입니다.
- `AuthReadiness.md`: 현재 개발 Auth 설정과 전용2계정의 안전한 준비 방법.
- `PreparationChanges.md`: 입력/선택자 변경 이유, 오류 재현, fixture 보정, 이전 해시 보존.

## 발견과 판정

1. 테스트 실행기 결함2건 수정: mode 없는 보고서의 허위 성공, 중단된 출력 폴더의 과거 증거 재사용. 실패 주입→nonzero 검증 통과.
2. 신규 연속 테스트 입력의 오래된 canonical 코드 및 local History ID/server comparison ID 혼동을 바로잡았습니다. 앱의 차단/identity 검증은 정상 작동했으며 제품 결함으로 집계하지 않습니다.
3. **이번 실행 범위에서 확정된 제품 결함 없음.** 검사하지 않은 기능이나 환경까지 정상으로 확정하지 않습니다.
4. Mac 임시 빌드 캐시 정리로 공간 차단 해소. 소스·현재 QA 캐시·배포 아카이브·기존 검증 결과 유지.

## 기능별 준비 범위

| 기능 | 준비/실행 | 남은 경계 |
|---|---|---|
| A 등록·중복, B 수정, C 삭제 | 대표 production action/authoritative read-back/삭제 transaction PASS | 실제 인증 DB 및 모든 연속 CRUD 조합 미실행 |
| D 비교 | 독립 수기 계산91/82/94, 실제 adapter/preview/payload PASS | 숫자 공식·반올림·최종 동점 처리의 최신 독립 정책 UNRESOLVED |
| E 기록 삭제·새 인스턴스 | 실제 sync/visibility/hydrator PASS, synthetic remote | 실제 두 계정/두 기기 서버 전파 미실행 |
| F 다른 사이즈, G 다른 내 옷 | sequence.2 PASS: 새 begin/complete 및 이전/새 승인 batch 분리 | SwiftUI에서 선택 state 적용·이전 임시사이즈 유지 규칙 미검증 |
| H 보유 등록→새 비교 | sequence.3 PASS: 현재 선택L 저장, 새 영수증/로컬 item으로 비교 | 실제 원격 등록/재조회·후보화 미실행 |
| 오류·취소 | 새 SDK transport15회 및 기존 late response/취소/응답유실 검사 PASS | URLError.cancelled와 실제 Task.cancel/UI이탈은 별개 |

## 데이터와 남은 차단

- URL90개(쇼핑몰별30), 실제 원문56개+합성invalid1. 원문/정답 데이터 변경 없음. 현재90개 전체 정상/수집 완료라는 뜻이 아닙니다.
- 실제 사용자 권한 DB 검사: **BLOCKED, 쓰기0**. 개발 프로젝트 ACTIVE_HEALTHY이고 이메일 가입은 활성이나 확인이 필요합니다. 인증 완료된 서로 다른 전용2계정의 token/UUID가 없습니다. 개인 Keychain 세션을 가져오거나 인증/RLS를 완화하지 않았습니다.
- 실제 인증 Swift A–H, 3×3/A–G/누락패턴 본검사 연결은 미완료입니다. 현 full은 이를 BLOCKED로 보고하므로 출시 승인 PASS를 만들지 않습니다.
- 역사 문서에 점수 공식 설명이 있으나 오래된 자동 reference/가중치 규칙도 섞여 있어 현재 정책의 독립 승인을 대체하지 않습니다.
- UI·공유 확장·Apple 로그인·실기기 표시/제스처는 별도 E2E입니다. 대량 full/배포/출시 승인은 이번에 수행하지 않았습니다.

## 실행 명령

대표 재검증: `python3 scripts/release_qa.py smoke`

본검사 진입: `python3 scripts/release_qa.py full` — preflight부터 시작하며 현재 미완료 증거 때문에 전체 성공 종료하지 않습니다. 이번에는 실행하지 않았습니다.

DB 설정은 [AuthReadiness.md](AuthReadiness.md)와 [environment.example](environment.example)의 환경변수만 사용합니다. 보고서 재집계는 `python3 scripts/release_qa.py report --output /tmp/FitMatchPrepResumeFinal`입니다.
