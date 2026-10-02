# Terra 실행 지시 — 원본 실측 표시·저장만 완성

## 범위
저장소 /Users/jinyoung/Developer/FitMatchLocal/FitMatch.
AGENTS.md, Docs/FitMatchMeasurementPolicy.md, Docs/CodexSessionHandoff.md와 관련 Behavior Map을 먼저 읽어라.
시작 시 HEAD와 dirty diff를 확인하고 기존 작업을 보존하라. ac08f64 기준 이후 변경이 있으므로 이미 해결된 부분을 다시 쓰지 마라.

이번 작업은 원본 실측 표시·저장·재조회 보완이다.
비교 엔진, 추천 점수, comparison mode, 카테고리 정책 변경은 하지 마라.
DB 사전/함수 보완 SQL은 사용자가 별도로 실행한다. 적용됐다고 가정하지 말고 실제 상태만 읽기 전용으로 확인하라.
commit/push/연결 Supabase write/migration 적용 금지.

## 완료 목표
정확히 선택한 product/variant/size의 원본 의류 실측에 대해:
API에서 수집한 원본 = 등록 화면 원본 = 저장된 원본 snapshot = 서버 재조회 후 원본.
개수뿐 아니라 원본 identity/code/label/value text/numeric value/unit/component/provenance가 일치해야 한다.
canonical mapping 성공 여부가 이 일치를 깨면 안 된다.
API가 원래 반환하지 않은 실측을 만들어내라는 뜻은 아니다.

## 구현할 것
1. 등록 화면
AddComparedProductToClosetSheet.registrationMeasurementRows의 ZARA/알려진 코드 제한을 제거하라.
MeasurementResolver.sourceDisplayRows 등 기존 공통 표시 경로를 재사용하라.
canonical 변환값을 쇼핑몰 원본으로 표시하지 마라.
쇼핑몰 원본 실측 영역에는 원본값과 원본단위를 표시하라.
표시명은 검증된 공식 표시명 → 사람이 읽는 rawLabel → 검증된 표시명 사전 → rawCode 순으로 선택하라.
표시명 선택은 semantic mapping이 아니다. unknown도 숨기지 마라.
원본에 단위가 없으면 cm를 만들어 붙이지 말고 단위 미확인으로 표시하라.
canonical 영역이 필요하면 별도로 유지하되 원본을 대체하지 마라.

2. 원본 보존
ShoppingProductViewModel의 runtime canonical/retailer record 합치기에서 원본을 잃지 않게 하라.
raw와 canonical projection을 별개로 유지하라.
canonical code/displayKind가 같다는 이유로 원본을 합치지 마라.
앞밑위/뒷밑위, 본체/안감/페티코트, 같은 코드의 서로 다른 구성품을 보존하라.
중복 판정은 정확한 source/variant/size/measurement identity로 하라.
값이 같다는 이유로도 별개 항목을 삭제하지 마라.

3. 저장과 재조회
Parser → observation → 선택 사이즈 → Closet payload/RPC → DB raw snapshot → hydration 경로를 추적하라.
상품 raw가 DB에 존재하는 것만으로 옷장 원본 snapshot 저장 성공이라고 판단하지 마라.
옷장에 저장한 원본은 상품 재수집 후에도 조용히 달라지면 안 된다.
기존 schema/payload/evidence 저장을 먼저 재사용하라.
원본 필드를 추가로 저장해야 한다면 backward-compatible migration과 Verify/Rollback을 작성하고 격리 로컬 DB에서 검증하라.
연결 DB에 직접 적용하지 마라.
연결 DB의 기존 RPC가 필드를 버린다면 Swift만 수정하고 완료라고 보고하지 마라.
서버 저장과 authoritative read-back을 확인한 뒤 성공 표시하라.

4. 원본 상태
정상 양수 의류 실측은 빠짐없이 표시·저장하라.
0/결측/비정상/단위 불명은 정책대로 원본 상태를 보존하고 정상 비교값으로 승격하지 마라.
신체 권장치/모델 정보는 상품 의류 실측과 분리하라.
rawLabel이 비어도 유효한 rawCode가 있는 정상 원본을 버리지 마라.
없는 label을 원본 사실처럼 덮어쓰지 말고 표시 단계에서만 대체하라.
rawValueText, source/parser/version, methodSource/methodProfile, 확인된 basis/representation/component 및 API provenance를 가능한 범위에서 보존하라.

## 금지
- 원본 표시를 늘리려고 canonical/비교 metric에 unknown을 추가
- rawLabel 추측으로 의미 확정
- 모든 항목을 cm로 처리
- 첫 번째 사이즈/variant/행으로 대체
- source 실측값을 canonical 변환값으로 덮어쓰기
- 기존 비교 점수에 raw-only 값을 추가
- 사용자의 기존 dirty 변경 덮어쓰기
- DB 배포 전인데 전체 기능 완료 보고

## 필수 테스트
현재 수정이 있다면 먼저 그 테스트를 재사용하라.

A. ZARA 상의 5개 전부, 바지 앞/뒷밑위 둘 다, 원피스 미매핑값 보존.
B. UNIQLO hip/neck/collar 및 unknown sizePart 보존.
C. MUSINSA 암홀/소매부리/unknown label 보존.
D. 코드만 있고 label 없는 정상 항목 표시·저장.
E. raw 40과 canonical 80이 함께 있을 때 원본에는40 표시.
F. 같은 displayKind로 들어오는 서로 다른 원본 항목 보존.
G. 단위 미확인/0/결측/비정상 값이 정상 비교값으로 둔갑하지 않음.
H. 사이즈/variant 재선택 시 이전 원본이 섞이지 않음.
I. 저장 → 서버 재조회 → 로컬 hydration 후 원본의 내용·개수 일치.
J. 상품 원본 재수집 이후에도 기존 옷장 snapshot 유지.
K. 기존 legacy 옷장/수동등록/편집 및 삭제의 회귀 없음.
L. canonical scoring 입력·점수가 기존과 동일함.

대표 fixture는 사용자 제공 상품의 보존 API 원문을 우선 사용하라.
향후 unknown 항목은 명시적인 합성 테스트 입력으로 추가하되 실상품이라고 보고하지 마라.
실제 production owner 함수를 사용하고 저장 계층을 mock으로 우회해 통합검증이라고 부르지 마라.

## 검증과 중단 기준
관련 focused tests/build + 격리 DB 저장/재조회 검사 + 보호 스크롤/diff 검사.
불필요한 전체 테스트 반복이나 시뮬레이터 UI 조작은 하지 마라.
실제 앱/연결 DB 등록 E2E 미실행은 NOT RUN으로 적어라.
DB migration이 필요하면 작성·로컬검증까지 진행하고 사용자 적용이 필요한 정확한 파일·순서를 남겨라.
외부 적용 대기를 제외한 허용된 작업을 끝까지 완료하라.

## 최종 보고
변경 파일 / 요약 / 검증(PASS·FAIL·NOT RUN·BLOCKED) / 남은 문제.
원본 수신·표시·저장·재조회 개수와 내용 비교 결과를 포함하라.
소스 수정 완료와 연결 DB 적용 완료를 구분하라.
인수인계서와 영향을 받은 지도만 갱신하라.

