# App Store 준비 상태 — 2026-10-02

- 대상: clean main `086617f49cd19c8c3e2777e75efa820d7f886b5f`, FitMatch-Production / Release / 1.1 (14).
- PASS: xcodebuild archive 종료 0. 앱/공유 확장, arm64, dSYM, Privacy Manifest 및 버전 일치 확인.
- PASS: 생성된 앱의 Supabase URL은 운영 `https://aqhrupgjpmrtnystottx.supabase.co`.
- FAIL: archive audit 종료 1. 개인정보처리방침 URL과 지원 URL이 비어 있고 앱/확장이 App Store Distribution 서명이 아님. 서명 무효가 아니라 배포 서명 미적용이다.
- NOT RUN: App Store용 IPA export/re-sign, Apple 서버 Validate, 업로드, 심사 제출. 기존 build 14 업로드 여부도 미확인.
- NOT RUN: 추가 회귀/실기기 테스트. 사용자 결정에 따라 재개하지 않음.

## 생성물

- Archive: `/private/tmp/FitMatch-main-086617f-1.1-14.xcarchive`
- Build log: `/private/tmp/FitMatch-main-release-archive.log`
- Audit log: `/private/tmp/FitMatch-main-release-audit.log`

## 남은 준비

1. 실제 공개 개인정보처리방침/지원 주소 확정 및 연결. 임의 주소를 넣지 않음.
2. App Store export에서 배포 서명 적용 및 검증, 업로드된 빌드 번호 중복 확인.
3. App Store Connect 메타데이터/스크린샷/App Privacy/심사 안내 확인. 과거 제출 문서의 '계정 불필요'는 현재 제출 안내로 사용하면 안 됨.
4. Validate 후 업로드/심사 제출은 별도로 상태 보고.

주간 사용량 85% 사용(15% 잔여)에 도달하여 추가 작업 중단. 아카이브 성공은 제출 준비 완료나 출시 승인 의미가 아님. 앱 소스 변경 및 추가 commit/push 없음. 이 문서는 원래 QA 체크아웃의 로컬 파일이며 main에 반영되지 않음.
