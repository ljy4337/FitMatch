# 3단계 출시 준비 — 2026-09-29

기준 connectDB/db190a9 + 기존 dirty. 핵심 앱·DB 계약 변경 없음.

## 실행 기록

- 검사 도구: archive/expected-version/expected-build 필수. 앱과 공유 확장 모두 외부 기대값으로 검사. 서명/manifest/dSYM/URL 검사는 유지.
- RED: 새 shell 회귀 exit1. GREEN: 인수 누락/빈 버전/일치/불일치/공유확장 불일치 포함 6개 case PASS(exit0). 합성 archive는 서명 등이 없으므로 전체 gate는 계속 FAIL이어야 한다.
- Ruling: 기존 dirty 작업을 포함해야 하므로 사용자 지정 connectDB checkout 유지. commit/push 및 별도 checkout 복사 없음.
- Release unsigned archive: PASS(exit0), `/tmp/FitMatchPhase3-20260929.xcarchive`. 로그 `/tmp/fitmatch-phase3-archive.log`. 실제 archive gate FAIL(exit1): 공개URL2개 공란 + 앱/확장 서명2개 부재. 나머지 검사 PASS. 로그 `/tmp/fitmatch-phase3-audit.log`. 서명/실기기/업로드 성공과 구분한다.

## 사용자 확정 필요

- 공개 운영자명, 지원 이메일, 개인정보·지원 HTTPS URL, 시행일.
- History 숨김 후 서버 보관/완전삭제 시점, 백업 보관·처리 위탁/국외 이전 등 공개 정책의 실제 운영 조건. 구현만으로 법적 적합성을 확정하지 않는다.
- 제출 버전/빌드: 현재 앱·확장은 1.1(8). 새 업로드 번호는 별도 확정. 과거 업로드 번호를 재사용하여 제출하지 않는다.
- 출시 endpoint 및 전체 원본 직접비교를 포함할지 기존 제한 범위로 출시할지 결정. 이번에 자동 전환/활성화하지 않는다.

## 실기기 확인

최신 빌드에서 로그인/공유 → 3쇼핑몰 등록 → 비교/다른사이즈 → History → 재실행, 링크옷 사이즈수정, 삭제/다른기기 반영, 회원탈퇴를 확인한다. 자동검사881PASS는 이 사용자 여정의 PASS가 아니다.

## 재현 명령

```bash
bash scripts/tests/test-audit-app-store-archive.sh
bash -n scripts/audit-app-store-archive.sh scripts/tests/test-audit-app-store-archive.sh
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/FitMatchPhase3Release -archivePath /tmp/FitMatchPhase3-20260929.xcarchive -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO archive
bash scripts/audit-app-store-archive.sh /tmp/FitMatchPhase3-20260929.xcarchive 1.1 8
```

독립 read-only 리뷰: scoped script/test/docs에 material defect 지적 없음. 기존 실기기/계정삭제 검증을 대체하지 않음. 앱 내 삭제 안내·시행일은 정책 확정 후 정렬할 대상으로 남김. Swift/Info.plist는 이 단계에서 수정하지 않음. Behavior Map은 flow 변경이 없어 추가 수정 없음.

## 최종 범위

검사도구·문서 정비와 unsigned Release 생성 완료. 공개정보 확정/서명된 제출 artifact/실기기는 미완료. 전체881PASS는 직전2단계 결과이며 이번에 다시 실행하지 않음(앱코드 변경 없음). shell syntax/diff/protected-scroll PASS. 연결DB 변경·commit·push·업로드 없음. 신규 shell test와 QA 보고서 로컬 미추적.
