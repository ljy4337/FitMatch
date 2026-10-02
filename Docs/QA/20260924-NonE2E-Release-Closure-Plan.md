# E2E 제외 출시 기술 검증 완료 계획

기준: connectDB 3243e980bc0a304693d461e2e4279fc6f970c350. 분석만 수행; 기능/DB/테스트 assertion 변경 없음. 현재78점은 가중 검증표이며 버그 없는 확률이 아니다. 100점은 아래 고정한 범위의 검증 완료를 뜻한다.

## 1. 옷장 sync 실패2건 — 테스트 시나리오 불일치 확인

FitMatchClosetSyncCoordinatorTests.swift:1061,1227은 remoteRecord(:1986)를 사용한다. 원격 시각2099년(:2030)이 local보다 최신이므로 coordinator:1264가 apply한다. :1294 shouldUpload → :1632 matchesRemoteMutationContent에서 변경 없음이면 runtime/mutation을 생략한다. :1346은 이미 받은 서버 list를 최종 hydration에도 사용한다.
따라서 첫 테스트가 기대하는 runtime 재조회/upsert가 실행되지 않는다. 두 번째는 failsRuntime=true를 설정하지만 runtime 자체가 호출되지 않아 '실제 실패 이후 stale hydration'을 재현하지 않는다. 과거 문서의 병렬 fixture 불안정 설명보다 직접적인 결정적 원인이다.

권장: 변경 없는 서버 row는 list1회/runtime0회/mutation0회 및 exact identity 보존을 검사한다. 실패 후 상태 덮어쓰기 검사는 실제 makeUpsertRequest가 필요한 명시적 변경 또는 신규 row 조건으로 별도 구성하고 runtime 호출이 발생했음을 먼저 assert한다. 실제 실패를 유발한 뒤 local fail-closed와 stale hydration 차단을 검증한다. assertion 단순 삭제/항상재조회로 성능 되돌리기 금지. 현재 두 실패만으로 데이터 손상 결함을 확정하지 않음.

## 2. 비교 자동검사 — 현행 계약에 맞춘 fixture와 실제 caller

HeadlessUserJourneyTests.swift:3883 referenceResponse는 target_comparison_group/candidate group을 누락한다. Coordinator:1390은 필수 그룹 누락을 fail-closed한다. 따라서 eligible/begin/complete 실패 다수가 앞단에서 막힌 이차 증상일 수 있다. 모두 같은 원인이라고 확정하지 않는다.
또한 다수 검사가 calculateRecommendation을 호출하지만 production Swift 검색상 해당 함수는 정의만 있고 CompareFlowSheet:2369는 사용자가 고른 옷으로 calculateTemporaryRecommendation을 호출한다. automatic/cross-group 성공 기대는 최신 동일그룹/사용자선택 정책에 맞지 않는다.

대상: FitMatchHeadlessUserJourneyTests.swift, FitMatchFinalReleaseScenarioExecutionTests.swift, FitMatchFinalReleaseProviderSnapshotTests.swift. 최신 서버 계약 기반 fixture에 exact target/closet/group/fingerprint를 제공하고 사용자 선택 경로로 재작성한다. 다른 그룹/위조/만료/공통실측0개는 거절 검사로 유지. begin 이전 complete 금지, 1개 canonical 허용, 결과 저장/read-back, 재시도 중복 방지 검사를 실제 단계에 도달시킨다. 검사 복구 뒤 여전히 실패하는 production owner만 최소 수정한다.

## 3. 구형 UX 검사

AddClosetItemViewModel.swift:221은 신규 등록의 브랜드를 필수로 하지 않는다. 최신 Handoff의 신규등록 간소화 결정과 맞고 편집 필수값은 별도 유지한다. FinalReleaseHeadlessAcceptance/Scenario의 missingBrand 실패 기대는 신규/편집을 분리해 수정한다.
MyClosetSwipeDeletionInteractionTests.swift:15는 상세 편집에 onDelete가 없다는 소스 문자열을 검사하지만 현재 상세는 서버 우선 삭제 action을 연결한다. 이것은 계산/DB 무결성 결함 증거가 아니다. 삭제 버튼의 최종 UX 결정을 확인하고 실제 삭제확인/서버거절/로컬보존 action 검증으로 대체한다. 실기기 swipe 충돌은 별도 E2E로 제외.

## 4. DB 재현성과 자동 통합검증

배포3건은 확인됐지만 대응 SQL은 아직 untracked. Git tracked migration 최신은20260921110000이며 원격 적용시각과 로컬 파일명시각이 다르다. manifest만으로 재현성 PASS 불가. Docker/Supabase CLI는 현재 PATH에서 미발견.

권장: 원격 migration version/name/내용과 Git파일 대응표를 완성하고, 누락된 prerequisites/seed/roles/extensions까지 식별한다. 일회용 로컬 Supabase에서 빈 DB부터 순서대로 replay한다. 실제배포 함수의 정규화된 정의/grants/constraints/RLS와 비교한다. local authenticated identities로 M→L/raw/canonical 일치, 잘못된 receipt 전체rollback, 상세왕복, 소유자별 tombstone를 실제 함수 체인에서 검사한다. 최소 stub harness PASS를 전체 replay PASS로 대체하지 않는다. remote migration history 임의수정/사용자데이터 테스트쓰기 금지. Git publication은 별도 승인 필요.

## 5. 실제 쇼핑몰 응답 계약

이전 UNIQLO timeout 및 MUSINSA/ZARA403은 앱 결함 확정이 아니라 실행환경 공백이다. E2E와 별개인 provider contract 검사다. 접속 가능한 환경에서 각 쇼핑몰의 정상 의류, 복수색상/사이즈, 부분실측/unknown raw 대표응답을 새로 수집한다. production parser로 exact identity/원본 개수/선택사이즈/payload를 검사하고 민감정보 없는 고정회귀자료로 저장한다. 봇차단을 우회하거나 실패를PASS로 간주하지 않는다. 환경이 막히면100점이라고 보고할 수 없다.

## 종료 기준

1. 현재 정책의 실제 caller를 검사하는 관련 unit/SQL/integration 전부PASS. 기존 full suite41FAIL은 각 원인 및 조치가 추적되고 최종실행에 미분류FAIL 없음.
2. 42skipped는 core 필수검사/수동E2E/옵션live 등으로 사유분류. 필수자동검사 skip은 완료가 아님.
3. 마지막변경후 Debug build+전체관련회귀PASS; DB Git replay+배포대조PASS; 최신provider contract 확인.
4. code/DB identity/서버권한/비교정책/보호스크롤 보존. 실기기 화면/터치/재실행/실제 두기기 여정은 사용자E2E로 별도 표기하며 점수감점에서 제외.

순서: sync/fixture 정비 → 자동비교 전체경로 검증 → DB replay → live parser 계약 → 마지막전체검사. 단계통과전에 점수를미리 올리지 않는다. 이 목록을 닫았을 때만 이 검증범위100점이며 AppStore 출시보증/무결함보증이 아니다.
