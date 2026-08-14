# Current Sprint

Updated: 2026-08-07
Branch: `리뉴얼_1`

## Goal

기존 UX와 비교 구조를 유지하면서 저장 안정성, 비동기 요청 소유권, 파서 신뢰성, 자동 회귀 검증을 출시 가능한 수준으로 올립니다.

## Completed

- 비교 화면 종료 시 진행 중 분석 작업 취소
- 연속 분석 요청에서 최신 요청만 화면 상태를 소유하도록 보강
- 저장 실패 시 SwiftData rollback 및 사용자 오류 안내
- 저장소 생성 실패 시 데이터 삭제를 유도하지 않는 복구 화면
- 지원하지 않는 URL과 허위 범용 파서 fallback 제거
- 무신사·유니클로 분류 및 길이 프로파일 회귀 수정
- Share Extension 실행 성공·실패 처리 보강
- 앱과 공유 확장의 공유 scheme 구성
- 비보호 코드의 Swift 6 actor-isolation 경고 정리
- 취소된 요청과 최신 요청 소유권 자동 테스트
- 실서버 제외 로컬 단위 테스트 `237/237` 통과
- 무신사 대표 fallback 테스트 `2/2` 통과
- 무신사 실서버 검증을 전용 `FitMatchLiveValidation` scheme의 실패 판정 테스트로 교체
- 신규 설치, 하단 탭, 새 작업, 비교 입력, 미지원 URL UI 테스트 추가
- UI 테스트 실행 시 사용자 저장소와 분리된 메모리 저장소 사용
- 핵심 UI 테스트 `5/5` 시뮬레이터 실행 통과
- 전체 단위 테스트 재실행: 로컬 `237/237` 통과, 실서버 2개는 일반 실행에서 명시적 skip 확인
- `FitMatchLiveValidation` 실서버 검증 `2/2` 실제 실행 통과
- 범용 iOS 기기 대상 앱·단위 테스트·UI 테스트·공유 확장 `build-for-testing` 통과
- 보호된 스크롤 파일과 modifier 호출부 무변경 확인
- 신규 1,280건을 포함한 누적 고유 상품 2,560건 운영 분류 및 Swift↔DB 규칙 미러 2,560/2,560 일치
- 실제 공식 실측 비교 879쌍 독립 무결성 검사 오류 0건 및 사람 검수 후보 200쌍 준비
- 개인·상품 원문을 저장하지 않는 로컬 집계형 출시 품질지표와 사용자 선택형 진단 내보내기 추가
- 최신 전체 자동 회귀 `284개 / 통과 279개 / 실패 0개 / 실서버 전용 skip 5개`
- 최신 코드 기준 arm64 Release archive `/tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive` 생성, 앱·공유 확장 1.0 (4), Privacy Manifest, dSYM 포함 확인
- iPhone 14 Pro / iOS 26.5.2에서 개발 서명 빌드·설치·전면 실행·딥링크 수신 후 프로세스 생존 확인
- URL scheme 식별자를 현재 앱 번들 ID와 일치시키고 최신 Release archive에서 재검증
- Release 진단 로그의 상품·옷장·카테고리·실측·비교 상세 출력을 차단하고 전체 회귀와 arm64 archive 재검증
- 활성 MY 화면에 개인정보처리방침·문의 및 지원 진입점을 연결하고 HTTPS URL 구성 검증 및 UI 회귀 통과
- 최신 개인정보·지원 화면 포함 전체 284개 회귀와 arm64 Release archive 재검증
- App Store archive 제출 게이트에 Apple Distribution 서명 검사를 추가하고 현재 공개 URL 2개·서명 2개만 실패함을 자동 판정
- 품질 진단 내보내기 단위 테스트 `5/5`와 지원 화면 UI 테스트 `1/1` 통과

## Device-only QA

- 실제 아이폰 데이터 보존 및 CRUD
- Safari·무신사 앱·유니클로 공유 확장
- 네트워크 단절과 복구
- 하단 바운스·감속·방향 전환 스크롤 동작
- 실제 쇼핑몰 앱 이동과 복귀

상세 절차는 `Docs/HomeDeviceQAChecklist.md`에서 관리합니다.

## Known Remaining Product Decision

- 추천 탭은 현재 `준비중` 화면입니다. 출시 전에 실제 서비스로 구현할지 탭을 숨길지 기획 결정을 내려야 합니다.
- 보호된 탭바 스크롤 파일의 기존 Swift 6 경고는 명시적 변경 승인 전까지 유지합니다.

## Rules

- `AGENTS.md` 준수
- 보호된 스크롤 동작 변경 금지
- 사용자 요청 없이 커밋·푸시 금지
