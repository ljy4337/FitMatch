# FitMatch 1차 출시 준비 체크리스트

## 2026-09-30 사용자 선택 그룹 복원 검증 완료

- [x] P08 SESSION_USER_SELECTED / SESSION_GROUP_CONFIRMED 기존 실제기록 복원 및 score/size/provenance 보존.
- [x] 상충된 상태·source·그룹·fingerprint 거절회귀.
- [x] 최신 offline878PASS/0FAIL/10NOT RUN, Debug build PASS.

아래 수동그룹 복원 미해결 기록은 수정 전 이력이다. [수정 근거](HistoryRestoreRepair-20260930.md). 물리기기 재설치 E2E는 NOT RUN.


## 2026-09-30 추가 확인 — 수동 그룹 선택 기록 복원 남음

- [ ] P08: SESSION_USER_SELECTED / SESSION_GROUP_CONFIRMED History 복원. 실제 기존 visible/current-head 완료1건과 배포함수로 계약불일치 확정. 직전 자동그룹 복원 수정에 포함되지 않은 분기다.
- 앱코드/DB 수정 없음. UI 재현테스트는 NOT RUN. 근거: VNextHistoryCacheHydrator.swift HistoricalTargetProjection의 source 필수guard(약136행) 및 배포 comparison_target_context / begin_comparison.


## 2026-09-30 History 복원 보완 완료

- [x] 정상 비교그룹 기록 복원: 기존3상품 PASS.
- [x] canonical 실측 code/value 보존 및 disk store 재개방: PASS.
- [x] 거절된 새 기록이 기존 local History를 지우지 않음: PASS.
- [x] 복원 공통값을 retailer 원문으로 재전송하지 않음: PASS.
- [x] 최종 offline 회귀876PASS/0FAIL/10NOT RUN; Debug app/test build PASS.
- [ ] 원본 없는 서버복원 기록에서 바로 옷장등록/재비교: 링크 재입력 필요. exact 원본 재취득 구현은 미완료.
- [ ] 물리기기·두기기E2E는 기존 미검증 유지.

[수정/실행 근거](HistoryRestoreRepair-20260930.md). 아래 감사 당시3FAIL은 위 수정 전 이력이다.


## 2026-09-30 기존 데이터 재감사 — P08/P09 출시 전 수정 필요

- [x] 신규 API 없이 기존 고정자료 자동회귀: 872PASS/0FAIL/10skip.
- [x] 기존 실제 완료3건의 추천 사이즈·점수 재생: 3/3PASS.
- [ ] **기록 없는 기기에 서버 History 복원: 3/3FAIL.** CATEGORY_GROUP 상태를 복원 코드가 거절한다. 기존 기기 재실행 성공으로 대체 불가.
- [ ] 복원 결함 수정 후 동일3건 및 기록→옷장등록 경로 재검증. canonical projection/교체 실패 보존도 같은 owner에서 확인.

[현재 감사 근거](FirstReleaseFrozenDataLogicAudit-20260930.md). 아래 과거 통과 기록은 당시 범위이며 새 실패를 대체하지 않는다. 이번 감사는 앱/DB를 수정하지 않았다.


## 2026-09-30 실제 검증 추가 — 발견 결함 수정·대표경로 재검증

**자라 중복 unknown 등록 crash와 false STALE_REFERENCE 비교차단 수정.** 등록→M100%비교→재실행→원본5개표시 및 DB저장 PASS. 회귀172tests/175runs PASS. 무신사/유니클로는 앞선 실제 대표경로 통과. [실행 근거](LiveReleaseProof-20260930/Report.md). 물리기기·전체 E2E·출시 승인까지 완료한 것은 아니므로 상위 체크는 해당 범위 충족 시 갱신한다.

## 완료 현황 — 2026-09-29, 1~3단계 반영

**체크는 실행한 범위만 뜻합니다.** 아래 본 체크리스트에서 자동검사와 실기기·출시 결정을 함께 요구하는 항목은, 일부 완료되어도 전체 체크를 하지 않았습니다.

- [x] 정책·핵심 소스와 실제 배포 DB의 주요 계약 읽기 전용 대조 — [감사 근거](FirstReleaseAudit-20260929.md). 전체 DB 복원·인증 E2E는 별도.
- [x] 과거 History 신뢰도 복원 호환성 수정 및 관련 73개 회귀 통과 — 1단계.
- [x] 구형 테스트 계약·테스트 실행 오류 정비 — 2단계.
- [x] 무신사 실측0 원본 보존, 비교 제외 회귀 및 격리 로컬 DB 검사 — 2단계.
- [x] 현재 로컬 소스 전체 FitMatchTests: **881 PASS / 0 FAIL / 42 NOT RUN** — [실행 근거](Phase2RepairVerification-20260929.md).
- [x] Debug 앱·테스트 빌드 및 실행 — 2단계.
- [x] 서명 없는 Release archive 생성 — 3단계, 앱/확장1.1(8).
- [x] 제출 검사 도구 버전 고정 제거 및 6개 회귀 사례 통과 — 3단계.
- [x] 실제 archive의 앱/확장 버전·번들·URL scheme·arm64·Privacy Manifest·dSYM 검사 — [실행 근거](Phase3ReleasePreparation-20260929.md). 배포 서명·공개URL은 실패하여 별도 미완료.
- [x] 개인정보 초안의 구형 수집없음·기준옷 안내 정리, 기록 숨김/영구삭제 구분 — 최종 운영정책 확정은 별도.
- [x] 출시 안내·인수인계 갱신, diff 및 보호 스크롤 검사.
- [ ] 실제 공개URL·연락처·시행일·보관정책 확정 및 앱/App Store Connect 반영.
- [ ] 최종 제출 버전·빌드 고정, 배포 서명된 archive 검사와 제출.
- [ ] 사용자 실기기 E2E 및 실제 운영 조건 확인.

작성일: 2026-09-29 / branch: connectDB / HEAD: db190a9c677da0181c4de2910c979a82ca59c1b8 + 현재 미커밋 변경.

## 사용법과 출시 기준

이 문서는 정책·지도·최근 인수인계 기록을 읽고 만든 준비 목록이다. 앱/DB 전수 감사나 오늘 실행한 테스트 결과가 아니다. 체크하지 않은 항목은 미구현 확정이 아니라 **출시 빌드에서 증거 확보 필요**를 뜻한다. 과거 PASS를 최신 빌드 PASS로 옮기지 않는다.

**출시 기준: 정상적인 핵심 흐름에서 잘못된 상품·사이즈·실측·점수가 나오지 않고, 저장된 사용자 데이터가 손상되지 않으며, 처리할 수 없는 입력은 이유를 설명하고 안전하게 종료한다. 모든 쇼핑몰 상품 지원이나 오류 발생 가능성 0%는 출시 조건이 아니다.**

담당: AI = 소스/자동검사/승인된 DB 확인, 사용자 = 실기기/운영정보/출시 결정, 공동 = 양쪽 증거 필요.
각 항목에 빌드번호·DB migration·일시·결과(PASS/FAIL/BLOCKED/NOT RUN)·증거를 기록한 뒤 체크한다.

## 1. 먼저 확정할 사항 — 우선순위 1

- [ ] R01 **1차 출시 비교 범위 확정** (사용자+AI): 현재 활성 canonical 비교와 제한된 verified-native 보완으로 출시할지, 전체 RETAILER_EXACT를 출시 전에 완성할지 결정. 최신 정책 4.3은 v2 실제 점수 활성화를 별도 검증 전까지 보류한다. Handoff 9/29도 전체 직접 비교 미완료를 명시한다. 전체 raw 비교를 이미 지원한다고 안내하지 않는다. 후속 출시로 미룬다면 출시 범위/안내를 명시하고 정책을 몰래 바꾸지 않는다.
- [ ] R02 **출시 빌드 고정** (AI+사용자): 현재 dirty 변경 포함 여부를 정하고 하나의 SHA/빌드로 검증·TestFlight·심사 제출을 연결한다. 이후 핵심 코드/DB 변경 시 영향받는 검증만 다시 한다. 업로드 성공과 처리 완료/심사 승인은 구분한다.
- [ ] R03 **운영 DB 결정** (사용자+AI): 같은 ref가 과거에는 개발, 최신 Handoff에는 Production으로 기록돼 있다. 실제 출시 endpoint·환경·접근권한·기준 데이터·테스트 데이터 처리 방침을 확정한다. 이 문서는 환경을 재판정하지 않는다. 새 DB 생성 자체가 항상 필수는 아니다.

## 2. 상품 수집·옷장 — 우선순위 2

- [ ] C01 세 쇼핑몰 각각 공식 상품 1개 이상을 공유/직접 링크로 가져와 상품·선택 색상·전체 사이즈가 실제 원문과 일치한다. 무신사 OneLink, 유니클로 color/size/PLD, 자라 v1 링크 포함. (공동)
- [ ] C02 선택 사이즈의 원본 코드/이름/값/단위가 수신→화면→서버 저장→재실행에서 유지된다. 미매핑 항목도 보존되며 신체 권장 치수를 옷 실측으로 저장하지 않는다. 0/비정상 값은 상태를 구분하고 비교에서 제외한다. (공동)
  - [x] 자동검사 부분: raw0/unknown 보존·비교 제외, Swift parser/observation/hydration 및 별도 로컬 SQL fixture 검증.
  - [ ] 실제 연결 서버 저장→실기기 재실행 전체 흐름 확인.
- [ ] C03 자동 그룹은 서버 출처를 유지하고, UNMAPPED만 A–G 사용자 선택으로 진행한다. 사용자 선택이 전역 쇼핑몰 사전을 바꾸지 않는다. (AI+실기기)
- [ ] C04 원본 카드가 먼저 보여도 서버 준비 중 저장이 잘못 실행되지 않는다. 서버 저장·정확한 read-back 전 성공 표시가 없으며, 중복 탭으로 중복 옷이 생기지 않는다. (공동)
- [ ] C05 링크 옷 M→L 수정 시 사이즈 ID·raw snapshot·canonical이 모두 L로 함께 갱신된다. 검증 실패 시 기존 M을 유지한다. (공동)
- [ ] C06 직접 입력 등록/수정에서 현재 A–G UI와 입력한 실측·메모 등이 유지된다. 과거 상세 종류 데이터는 호환 보존하되 폐기된 상세 picker를 다시 요구하지 않는다. (공동)
- [ ] C07 삭제 버튼/짧은 스와이프 확인/긴 스와이프 즉시 삭제가 현재 정책대로 동작하고 재실행 후 되살아나지 않는다. 삭제 중 동기화가 데이터를 복원하지 않는다. (공동)

## 3. 비교·결과·기록 — 우선순위 2

- [ ] P01 서버 승인 **같은 A–G 그룹** 후보만 보인다. 같은 그룹의 반팔↔긴팔은 semantic 조건을 만족하면 비교되고 다른 그룹은 통과하지 않는다. (AI+실기기)
- [ ] P02 후보는 사용자가 고른다. 자동 선택/자동 비교 시작이 없고, 옷장 없음·같은 그룹 없음·공통 실측 없음은 정확한 이유를 알린 뒤 종료한다. 등록하기/다른 상품 비교하기를 빈 후보 화면에 복원하지 않는다. (공동)
- [ ] P03 서버 승인 공통 실측 1개는 낮은 신뢰도로 비교 가능하고 0개는 차단한다. 품절/재고 UNKNOWN만으로 비교 점수나 후보를 바꾸지 않는다. (AI)
- [ ] P04 앞/뒤 기장, 일반/등중심 소매, 단면/둘레, 본체/안감이 잘못 섞이지 않는다. 검증된 변환만 사용하며 원본 표시 개수와 점수 사용 개수를 구분한다. (AI)
- [ ] P05 후보 미리보기와 최종 결과는 같은 근거라면 사이즈·점수가 같다. 서버 근거가 바뀌면 새 근거로 계산한다. 근거 없는 미리보기 숫자를 만들지 않는다. (공동)
- [ ] P06 최종 추천·차이·신뢰도는 begin 승인 snapshot만 사용하고 complete 저장 뒤 확정한다. 9/29 소매 보완도 새 비교에서 검증하며 과거 결과를 소급 변경하지 않는다. (공동)
- [ ] P07 ‘다른 옷 비교’에서 선택이 초기화되고 새로 고른 옷을 재검증한다. ‘다른 사이즈’는 해당 상품의 승인된 사이즈/실측만 표시한다. 이전 옷·이전 사이즈 값이 섞이지 않는다. (공동)
- [ ] P08 같은 target Product 재비교 완료 후 기록에는 최신 결과 1개가 표시된다. 진행 중/실패한 재비교가 이전 완료 결과를 지우지 않는다. 재실행·서버 동기화 후 동일하다. (공동)
  - [x] 자동검사 부분: 과거 신뢰도 replay, 동일target 최신head 교체·디스크 재실행 회귀 PASS.
  - [ ] 인증 서버·실기기 재비교/동기화 확인.
- [ ] P09 결과/기록에서 내 옷 등록 시 정확한 색상·선택 사이즈·원본을 저장한다. 옛 결과를 열어도 다른 상품 값으로 대체되지 않는다. (공동)
- [ ] P10 기록 삭제가 재실행·다른 기기에 반영되고 관계없는 기록·옷은 유지된다. 단순 응답 누락을 삭제로 추정하지 않는다. (공동)

## 4. 계정·실기기·실패 안내 — 우선순위 2

- [ ] U01 실제 Apple 로그인→온보딩 건너뛰기/나중에 등록→재실행이 정상이다. (사용자)
- [ ] U02 로그아웃→다른 계정 로그인 시 이전 사용자의 옷·기록·진행 중 응답이 노출되지 않는다. 서버 소유권/RLS도 별도로 확인한다. (공동)
- [ ] U03 전용 테스트 계정으로 앱 내 회원탈퇴→서버 사용자 데이터 정리→로컬 정리→재가입을 확인하고 Apple 토큰 철회 경로를 검증한다. 계정 파괴 검증은 별도 명시 승인 후 수행한다. (공동)
- [ ] U04 공유로 앱이 닫힌 상태/열린 상태에서 진입, 불러오기 취소→다른 링크 입력이 정상이다. 늦은 응답이 새 화면을 바꾸지 않는다. (사용자+자동검사)
- [ ] U05 잘못된 링크·실측 없음·지원 불가·인증 만료 등은 사용자가 이해할 안내가 나온다. 영구 로딩/허위 성공/작성 내용 불필요 삭제가 없다. 네트워크 장애의 복잡한 조합 전수검사는 이번 범위 밖이다. (공동)
- [ ] U06 실제 출시 빌드에서 상품 로딩→후보 표시→선택→결과, 다른 옷/사이즈 전환 시간을 측정한다. 무한 로딩·멈춤은 차단 결함, 추가 수초 최적화는 실제 영향에 따라 후순위. 근거 없이 ‘즉시’나 개선율을 약속하지 않는다. (사용자)

## 5. 배포·DB·검증 — 우선순위 3

- [ ] D01 출시 소스 전체 조합의 Debug/Release archive 및 관련 회귀검사 증거를 확보한다. 9/24 870 PASS와 9/28 focused PASS를 9/29 dirty 전체 PASS로 간주하지 않는다. skipped/환경 BLOCKED는 통과가 아니다. (AI)
  - [x] 현재 dirty 소스 조합의 Debug build/test 및 unsigned Release archive PASS.
  - [ ] 최종 출시 SHA/빌드 확정 후 해당 제출본 증거 연결. 42개 미실행은 PASS 아님.
- [ ] D02 출시 앱이 부르는 RPC/DTO/함수 권한/원본 저장/History sync/preview 계약과 실제 배포 DB를 대조한다. 준비 SQL과 적용 SQL, local version과 remote version/name을 구분한다. (AI, 읽기 전용 우선)
  - [x] 감사에서 지정한 주요 RPC/DTO·원본 snapshot·History/preview·권한·migration 이력 READ ONLY 대조 완료.
  - [ ] 최종 출시 범위 전체의 배포 일치 확인. 기존 대조를 전체 DB 재현 증거로 확대하지 않음.
- [ ] D03 필요한 schema·함수·사전·정책·Edge 설정의 Git/백업 복원 자료와 복구 절차를 확보한다. 새 출시 DB를 만들면 전체 복원/replay 검증이 전환 전 필수다. 기존 DB 유지 시에도 복구 가능성은 필요하며 새 DB를 만들기 위해 출시를 무조건 미루지는 않는다. (AI+사용자)
- [ ] D04 앱/공유 확장 버전·서명·App Group·Privacy Manifest·dSYM을 출시 archive에서 확인한다. TestFlight 처리 완료 후 그 빌드로 실기기 검증한다. (공동)
  - [x] unsigned archive 버전·Privacy Manifest·dSYM 등 검사 PASS.
  - [ ] 배포 서명·서명된 entitlement/App Group·TestFlight 및 실기기 확인.
- [ ] D05 다른 계정 데이터 접근 차단, 관리자 secret 미포함, 로그 민감정보 미노출을 확인한다. 운영용 DB 변경에는 승인·백업·rollback·읽기 전용 postflight가 있다. (AI)

## 6. App Store·운영 준비 — 우선순위 3

- [ ] A01 실제 공개 HTTPS 개인정보처리방침/지원 페이지와 연락처를 준비하고 앱 및 App Store Connect에 연결한다. 현재 소스 Info.plist 두 URL은 공란이다. 최종 archive의 override 여부는 별도 확인한다. (사용자+AI)
- [ ] A02 개인정보 초안의 기준옷 등 폐기 표현을 정리하고 실제 인증·옷장·비교·원본 보관/삭제 방식과 일치시킨다. 구형 문서의 ‘수집하지 않음’을 복사하지 않고 App Privacy를 데이터 유형별로 판단한다. (사용자+AI)
  - [x] 현재 코드 기준 개인정보·출시 문서 초안 정렬.
  - [ ] 보관/파기 등 운영정책 확정, 앱 내 안내 정렬 및 App Privacy 유형별 최종 답변.
- [ ] A03 설명·스크린샷·지원 쇼핑몰·이용연령 등 제출 정보를 실제 기능과 맞춘다. 실측 유사도 기반 결과를 착용 보장으로 광고하지 않는다. (사용자)
- [ ] A04 Apple 로그인 앱의 심사 진입 방법, 비교 가능한 테스트 절차/상품, 백엔드 접근을 심사 메모에 제공한다. 심사 접근 문제를 인증 우회 코드로 해결하지 않는다. (사용자)
- [ ] A05 상품정보·이미지·API 이용 및 보관에 필요한 쇼핑몰 조건/권한을 확인한다. 이번 문서 검토는 이용 허락이나 법적 적합성 판정이 아니다. (사용자)
- [ ] A06 무료 운영 대응 경로를 정한다: 문의 채널 + 앱 진단 내보내기 + 버전/쇼핑몰/실패 단계별 확인 절차 + 사전 보완/핫픽스 담당. 유료 오류수집 도입은 필수가 아니다. (공동)

## 사용자 실기기 최소 확인 묶음

1. 세 쇼핑몰 각 1개: 실제 링크 공유→보유 사이즈 등록→재실행→같은 그룹의 내 옷을 직접 선택→결과→기록 재열기.
2. 그중 1개로 사이즈 변경, 다른 옷/다른 사이즈 비교, 결과에서 등록, 재비교 최신 기록 교체, 옷/기록 삭제.
3. 후보 없는 상품, UNMAPPED 그룹 선택, 실측 부족 상품, 취소 후 다른 링크. 사례가 없으면 AI가 확인 가능한 fixture/상품을 준비하며 통과를 가정하지 않는다.
4. 계정 전환, 승인한 전용 계정 탈퇴, 가능하면 두 기기 삭제 동기화.

상품 수 3개는 대표 smoke 최소값이지 전체 지원 증거가 아니다. 정확성 경계는 고정 응답 자동 회귀로 보완한다. 출시 빌드번호·URL·선택 색상/사이즈·예상/실제 결과를 남긴다.

## 현재 문서에서 특히 주의할 점

- 9/29 raw direct 비교는 구조 근거 수집/제한된 canonical fallback까지이며 전체 최종 비교 활성화가 아니다. 출시 범위 결정 R01 필요.
- 9/28 preview 재사용/History 최신 1개, 9/29 소매 근거/온보딩/스와이프 변경의 인증 E2E는 최신 기록에서 NOT RUN이다. 미검증과 결함을 구분한다.
- 지도 헤더 baseline은 9/15지만 본문은 최근 변경을 포함한다. 헤더만으로 전부 구형이라 판단하지 않는다. 반대로 본문의 prepared/applied 문구도 Handoff 최신 기록과 대조해야 한다.
- HomeDeviceQAChecklist는 옛 브랜치와 기준옷 정책, AppStoreReadiness는 8월 버전/개인정보 답변을 포함한다. 현재 체크리스트에 그대로 승계하지 않는다.
- 과거 200쌍 사람 검수는 Apple 필수 요구가 아니다. 기존 내부 게이트를 조정하려면 명시적 결정이 필요하되, 임의 수량 달성보다 심각한 잘못된 실측/결과를 막는 대표 검증을 우선한다.

## 후속으로 미룰 수 있는 것

모든 쇼핑몰 카테고리 일괄 등록, 모든 raw 항목 점수화, 유료 분석 서비스, 전면 리팩터링, 실제 영향 미측정 미세 최적화, 복잡한 장애 조합 전수검사. 원본 직접 비교 전체 활성화는 R01에서 범위를 확정했을 때만 후속으로 미룬다.

## 출처

저장소: AGENTS.md; FitMatch Behavior Map.md; FitMatch Swift Feature Map.md 관련 소유자; Docs/FitMatchMeasurementPolicy.md; Docs/CodexSessionHandoff.md 최신 9/29–9/28 기록; Docs/QA/20260924-Release-Technical-Score.md(역사 기록); Docs/AppStorePrivacyPolicyDraft-20260806.md; Docs/AppStoreReadiness-20260806.md; Docs/HomeDeviceQAChecklist.md; Docs/ReleaseNote.md; FitMatch/Info.plist.

Apple 공식 기준(2026-09-29 검색 확인):
- 심사 완성도/접근/메타데이터: https://developer.apple.com/app-store/review/
- 앱 내 계정 삭제/Apple 토큰 철회: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- 개인정보 답변 관리: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/

이번 수행: 문서/일부 설정 읽기, 체크리스트 작성. 앱 테스트·실기기·DB 재조회·배포·commit/push 없음. 출시 승인/점수 평가를 수행한 문서가 아니다.

## 실행 담당 검토 — 2026-09-29 추가

이 절은 실행 가능성 검토다. 아래 검사를 실행하거나 통과했다는 뜻이 아니다. 현재 xcodebuild/swift 실행 파일, 관련 XCTest·SQL 검증 자료가 존재함을 확인했다. 시뮬레이터·서명·인증·외부 API 접근 가능성은 실행 때 확인한다.

### AI가 우선 수행할 수 있는 검증

| 순서 | 연결 항목 | 수행 범위 | 결과물/종료 기준 |
|---|---|---|---|
| 1 | R01, P03–P06 | 최신 active caller부터 DB 승인 evidence/점수/결과까지 추적. 정책상 의도된 보류와 실제 결함 분리 | 현재 지원/미지원/불일치 표. 정책 결정은 사용자에게 남김 |
| 2 | D02, C02–C07, P08–P10 | 연결 DB 환경 확인 후 읽기 전용으로 RPC/권한/원본 snapshot/History 계약과 Swift 대조 | 배포 일치/불일치 증거. 읽기 함수도 부작용 검사 후 호출 |
| 3 | C01–C07, P01–P10, U02/U04/U05 | 기존 parser/Closet/authority/History/measurement 테스트 우선 실행. 실제 production owner를 거치는 누락 회귀만 제안 | 실패 재현 및 root cause, fixture와 live 증거 구분. 모든 자동검사가 E2E를 대신하지 않음 |
| 4 | D01/D04/D05 | 고정한 로컬 상태에서 Debug/Release 빌드, 관련 전체 suite, archive 구성·secret/RLS 경계 검사 | 명령/종료코드/테스트 수/제외 목록. 서명·계정 접근 제한 시 BLOCKED |
| 5 | A01/A02/A04/A06, D03 | 개인정보/지원 초안 정합성, 심사 절차, 무료 진단 운영안, migration/복구 자료 점검 | 빠진 설정과 사용자 제공값 목록. 필요시 별도 문서/SQL 초안 작성 |

기존 진입점: FitMatchClosetTransportContractTests, FitMatchClosetSyncCoordinatorTests, FitMatchServerAuthorityIntegrationTests, FitMatchComparisonPermitSequencingTests, FitMatchComparisonSyncCoordinatorTests, MeasurementPolicyConsolidationTests, FitMatchAuthSessionStoreTests, 세 provider concurrency tests, FitMatchReleaseConfigurationTests. 보조 스크립트: scripts/test-candidate-envelope.sh, scripts/test-metrics-diagnostics.sh, scripts/audit-app-store-archive.sh. 파일 존재를 target 포함/실행 PASS로 간주하지 않는다.

### 조건이 갖춰지면 AI가 추가 수행할 수 있는 작업

- 실제 쇼핑몰 소량 조회(C01): 접근 허용 시 공식 원문과 parser 결과 비교. 봇 차단 시 BLOCKED; 저장된 fixture 통과로 live 성공을 대체하지 않음.
- 인증된 저장→비교→기록 통합 검사(C/P): 정확히 지정된 비운영 테스트 환경·계정·쓰기 범위 승인과 기존 안전한 인증 수단 필요. 인증 우회/사용자 impersonation 금지. 비밀번호·토큰을 채팅으로 요청하지 않음.
- 빈 DB 복원(D03): 일회용 로컬 환경이 가능하면 실행 가능. 운영 프로젝트 생성/데이터 이전/정리는 별도 결정·승인이 필요.
- 문서/코드 수정, DB 적용, 공개 페이지 배포, commit/push, TestFlight/심사 제출은 검토와 구분한다. 이번 요청은 체크리스트 문서화·담당 범위 검토이며, 이 작업들을 새로 실행한 것이 아니다.

### 사용자가 결정하거나 직접 확인할 것

- R01/R02/R03: 출시 기능 범위, 포함할 변경·빌드, 운영 DB 지정.
- A01/A02/A03/A05: 운영자명·지원 연락처·보관 방침·공개 주소·스토어 설명/스크린샷·쇼핑몰 이용 권한. AI는 초안과 정합성 검토를 돕고 사실을 임의 생성하지 않음.
- U01/U03/U04/U06 및 C/P의 실기기 부분: Apple 로그인, 실제 쇼핑몰 앱 공유, 재실행·계정 전환, 터치/스와이프·속도 체감, 별도 승인한 탈퇴. 두 기기 동기화는 실제 두 기기/계정 준비 필요.

### 권장 실행량

먼저 1–3에서 출시를 막는 실제 문제만 확인하고, 수정 필요성을 판정한다. 이후 출시 후보를 고정해 4의 최종 빌드/회귀를 한 번 실행하고 사용자에게 겹치지 않는 실기기 확인 목록을 준다. 문서의 35개 항목을 각각 별도 대규모 감사로 확대하지 않는다. 지금 단계에서 새 기능·추측성 리팩터링·성능 목표치 추정은 하지 않는다.

문서 보존 상태: 이 파일은 프로젝트 로컬에 저장되어 있고 현재 Git 미추적이다. 다른 기기/원격 저장소 공유는 별도 commit/push 후 가능하다.

## 2026-09-29 순차 검수 결과 연결

결과: [FirstReleaseAudit-20260929.md](FirstReleaseAudit-20260929.md).

- 1 정책/소스 대조 완료: v2 보류 범위 확인, 무신사0값 원본행 정책 불일치 확인.
- 2 연결 DB READ ONLY 계약 확인 완료: 주요 수정/History/preview 함수·권한·이력 존재. 새 FitMatch_PROD는 확인 대상 핵심 함수 없음. 실제 mutation E2E는 별도.
- 3 전체 자동검사 FAIL: 834 PASS / 42 FAIL / 42 skipped. History 단독 7 PASS / 11 FAIL. 과거 신뢰도 공식과 같은 엔진 버전을 재사용하는 replay 결함 확인; P08/P10/D01 완료 처리 금지.
- 표시 대상 서버 History 1건이 현재 신뢰도 재계산과 충돌. 수정 전 출시 검증 완료로 판정하지 않는다. 사용자 E2E로만 넘길 문제가 아니다.
- 기존 출시 준비/실기기 체크박스는 이번 정적/자동검사만으로 체크하지 않았다. 코드·DB 수정 및 Release archive 재생성은 하지 않았다.

## 2026-09-29 1단계 후속 결과

History 과거완료 복원 호환성 수정 및 관련3 suite73/73 PASS. 신규v2/과거v1 명시적 호환이며 점수정책 변경 없음. 전체회귀/실기기/출시체크리스트 완료로 승격하지 않음. 확대 Headless5실패와2·3단계는 별도 잔여. 상세 FirstReleaseAudit-20260929.md §7.

## 3단계 실행 결과 — 2026-09-29

도구6case PASS, unsigned Release archive PASS. 제출 gate FAIL: 공개URL2개·서명2개 미충족. 공개정책 초안 정렬 완료, 실제 운영정보·서명·실기기 미완료. DB/핵심앱 코드 변경 없음. [명령과 상세 근거](Phase3ReleasePreparation-20260929.md). 이전3단계 미진행/Release NOT RUN 기록은 이 결과로 갱신하며 과거기록은 유지한다.
