# 실제 API·앱·서버 검증 — 2026-09-30

## 최신 수정·재검증 (아래 최초 실패 기록을 대체)

- 등록 크래시 수정: `FitMatchComparedProductClosetRegistration.measurementValues`는 중복 코드/unknown을 scalar 요약에 억지로 병합하지 않는다. 원본 measurementRecords는 전부 유지하며 records가 있을 때 오래된 scalar로 되돌아가지 않는다. linked 서버 실측 선택 계약 유지.
- 실제 자라 등록 후 추가 확인된 false STALE_REFERENCE도 수정: 서버 canonical 5개 중 로컬 사전에 없는 back_width/front_length_shoulder_to_hem/upper_arm_width 3개를 freshness snapshot에서 버려 서버와 다르다고 판단했다. `UserFit.fitMatchServerReferenceSnapshot`은 fitmatch_vnext_snapshot 출처의 정확한 코드를 보존한다. raw retailer 행을 canonical로 승격하지 않으며 점수/가중치/DB authorization 변경 없음.
- 수정 전 재현: `/tmp/FitMatchRawCrashRed2.xcresult` exit65, 실제 등록 준비 함수 crash 1FAIL. `/tmp/FitMatchReferenceRed.xcresult` exit65, freshness 기대값 1FAIL(5개 기대/2개 반환). 첫 테스트 작성 중 initializer 컴파일 오류는 수정한 뒤 재현; 컴파일 실패를 버그 재현으로 계산하지 않음.
- 최종 회귀 **PASS**: `/tmp/FitMatchRawFinalGreen.xcresult`, exit0, 172 tests / parameter 포함175 runs, 0FAIL/0skip. 5 suites: ClosetRegistrationDuplicateRawTests, FitMatchClosetTransportContractTests, FitMatchSupabaseProductResolverTests, FitMatchServerAuthorityIntegrationTests, FitMatchClosetSyncCoordinatorTests. 모두 fixture/stub 기반이며 live DB test를 뜻하지 않음.
- 명령: `xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO`에 위 5개의 `-only-testing:FitMatchTests/<suite>`와 `-resultBundlePath /tmp/FitMatchRawFinalGreen.xcresult test` 적용. 로그 `/tmp/FitMatchRawFinalGreen.log`. Debug test build PASS. 기존 ClosetSubmissionAction.swift:77 actor-isolation warning 존재. Release/물리기기 검증 NOT RUN.
- 최신 앱 설치 후 실제 API/UI **PASS**: 같은 자라 p03443415/v1=564228855, M(KR95-100) 등록 → 같은 상품과 비교 M100%(서버승인 가슴/소매2개) → 앱 재실행 후 옷·결과 유지 → 상세 원본5개 표시. `ZaraFixUIEvidence.json`에 UI capture 보관.
- READ ONLY DB postflight **PASS**: source_product_key564222870, selected size aa3ecb75-2480-4376-8731-ad0fef03d846. raw chest56/front-length67.5/sleeve62.5/back-width50/arm-width21.5 cm 5행. parent↔raw snapshot product/variant/size 모두일치. 비교 COMPLETED, M(KR95-100),100, engine fitmatch-ios-vnext-snapshot-v2.
- 승인 범위 내 이번 자라옷1개 추가(앞선2개 포함 총3개), 비교결과1개 추가. 기존 옷/결과 수정·삭제 없음. DB schema/migration/배포 변경 없음. commit/push 없음. 신규 테스트는 로컬 untracked.
- 판정: **확인된 두 결함 수정·해당 경로 재검증 PASS**. 모든 상품/모든 기기/모든 E2E 정상 보장이 아니다. 무신사/유니클로 live 성공은 아래 최초 실행의 증거이며 이번 수정 후 새로 실행했다고 보고하지 않는다.

기준 connectDB/db190a9 + 기존 dirty. Simulator iPhone17Pro/iOS26.3.1, 기존 로그인 계정. 사용자는 hnkplvyegonlhumlejst(현재 Production 취급)에 테스트옷 최대3개/비교기록 생성 승인. 기존 데이터 수정/삭제 금지. DDL/migration/권한우회/사용자 impersonation 없음.

## 결과

| 대상 | 실제 입력·수집 | 등록 | 비교 | 재실행 |
|---|---|---|---|---|
| 무신사 ct27zw6f → 5328103 | 4사이즈 | M, raw6개 DB 확인 | 같은 상품 M100%,6항목,COMPLETED | 옷/결과 M100% 유지 |
| 유니클로 E484080-000,07 | 8사이즈,실측32개 | M,raw4개 DB 확인 | 같은 상품 M100%,4항목(소매포함),COMPLETED | 옷/결과 M100% 유지 |
| 자라 p03443415,v1=564228855 | 원래 전체 공유URL 4사이즈/20실측, internalProductID564222870 | **FAIL: M등록 클릭 시 crash** | NOT RUN | 재실행 성공,자라 옷장행 없음 |

- 무신사 다른사이즈 L93% 임시분석 확인. 저장된 추천 M100% 유지.
- 유니클로 상의 등록 전, 옷장 바지/아우터만 있을 때 같은그룹 없음 안내 확인. 등록 후 상의 후보1개 표시 및 비교성공.
- 실제 API → production parser → observation 검사 신규 opt-in `LiveReleaseRetailerProofTests`. 첫 실행 축약한 자라 URL은 실패(무신사/유니클로2개PASS). 축약 입력을 사용자가 준 전체 URL로 정정한 재검사 결과는 아래 추가. 첫 실패를 원래 공유URL의 결함이라고 판정하지 않음.
- Simulator UI와 실제 서버 실행 증거다. 물리 iPhone/Safari 공유확장/다른계정/두기기/삭제/사이즈수정 E2E를 대신하지 않는다. 동일상품 자가비교만으로 서로 다른 상품의 모든 추천 정확성을 입증하지 않는다.

## 확인된 출시 차단 결함

`FitMatch/Services/FitMatchComparedProductClosetRegistration.swift:799`, `measurementValues(for:records:)`는 모든 양수 record를 measurementCode로 Dictionary(uniqueKeysWithValues:) 변환한다. 자라 M raw5개 중 코드unknown이3개(67.5/50/21.5)이며 서로 다른 원본 사실이다. 이들을 같은 키로 구성하다 `Duplicate values for key: 'unknown'`로 trap.

호출: AddComparedProductToClosetSheet.saveSelectedSize line921 → prepareServerFirstSubmission line278 → closetItemPayload line718 → measurementValues line799. 원본 raw행을 버리거나 임의 첫값으로 덮어쓰는 방식은 금지. scalar canonical projection과 raw transport를 분리하고 unknown/semantic conflict를 안전하게 처리하는 회귀 필요. 이번 요청은 검증이므로 production fix는 적용하지 않음.

근거:
- `/Users/jinyoung/Library/Logs/DiagnosticReports/FitMatch-2026-09-30-002043.ips`: EXC_BAD_INSTRUCTION/SIGILL, Dictionary.init(uniqueKeysWithValues), 위 Swift frame.
- runtime log `~/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/logs/com.ljy4337.fitmatch_2026-09-29T15-18-06-837Z_helperpid81120_ownerpid77809_d0ea5504.log`: 원본20개 accepted 이후 Duplicate unknown. 상품관측은 저장됐으나 Closet mutation 준비 중 종료.
- READ ONLY postflight: 15:00~15:25 UTC 생성 옷장2개(raw6/4), 비교2개 COMPLETED/score100/engine snapshot-v2. 개인정보/인증값 보고서 미포함.

## 데이터 상태

테스트로 생성된 옷2개·결과2건은 승인 범위로 남겨둠. 기존옷 삭제/수정 없음. 자라를 포함한 상품 observation은 정상 앱 흐름에서 갱신됨. DB 읽기조회는 schema column inspection 및 위 시간범위 bounded SELECT만 수행.

## 최종 판단

전체 정상 증명 **FAIL**. 무신사/유니클로 대표경로의 실제 성공은 확보했지만 자라 원본unknown 복수항목 등록 crash가 확인되어 출시 통과 판정 불가. 이전881PASS는 이 raw 조합/실제 저장 버튼 경로를 충분히 덮지 못했다.

## 최종 live parser 재검사

정확한 원래 공유URL로 xcodebuild `-only-testing:FitMatchTests/LiveReleaseRetailerProofTests` 실행, `/tmp/FitMatchLiveProofExact20260930.xcresult`, exit0. parameter3개 PASS(테스트함수1개), skip0. 상품사이즈 존재/raw양수개수/observation 개수일치 검사. 이 테스트는 서버 옷장mutation을 수행하지 않으므로 UI에서 재현된 자라 저장crash를 반박하지 않는다. opt-in 임시파일 제거 완료. diff/protected-scroll PASS. 신규 test/report 로컬미추적, commit/push 없음.
