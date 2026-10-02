# FitMatch App Store 제출 실행 순서

현재 준비 기준: main `f838763` 앱 소스, FitMatch-Production 1.1 (14), 2026-10-03.
아래 2026-08-07 품질 결과는 과거 실행 기록이며 현재 빌드의 통과 증거가 아니다.
현재 아카이브 생성은 PASS, App Store 내보내기는 `No Accounts` 및 iOS Distribution 인증서 부재로 BLOCKED, 공개 URL 2개는 미설정이다. 개발/운영 Edge 함수 두 개의 소스와 JWT 설정은 일치한다.

## 1. 공개 정보 확정

다음 실제 값을 준비합니다. 임시 주소나 공개에 동의하지 않은 개인 연락처는 사용하지 않습니다.

- 공개 운영자명
- 개인정보처리방침 HTTPS URL
- 고객지원 HTTPS URL
- 개인정보처리방침 시행일

`Docs/AppStorePrivacyPolicyDraft-20260806.md`의 대괄호 항목을 모두 채우고 공개 페이지의 내용과 앱의 실제 동작이 일치하는지 확인합니다.

## 2. 앱 출시 구성 입력

`FitMatch/Info.plist`의 다음 값을 입력합니다.

- `FitMatchPrivacyPolicyURL`
- `FitMatchSupportURL`

개인정보처리방침과 지원 URL은 `https://` 주소만 허용됩니다. 앱의 MY → 개인정보처리방침, MY → 문의 및 지원에서 각 링크와 이메일 버튼을 실제로 열어봅니다.

## 3. 품질 게이트

다음 항목을 모두 통과해야 합니다.

- `Docs/HomeDeviceQAChecklist.md`의 실제 기기 항목
- 실제 비교 200쌍 사람 판정: 중대 오판 0건
- 전체 자동 회귀: 실패 0개
- 실제 비교쌍 독립 무결성: 오류 0건

위 항목은 최신 출시 빌드에서 별도로 판정한다. `/tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult`는 과거 증거다.

## 4. 배포 서명 archive

Xcode에서 FitMatch-Production scheme과 `Any iOS Device`를 선택하고 `Product → Archive`를 실행합니다. 현재 아카이브는 Apple Development 서명이다. App Store export에서 Apple Distribution 서명과 프로파일을 적용한다.

archive 경로를 다음 감사 명령에 전달합니다.

```bash
scripts/audit-app-store-archive.sh /path/to/FitMatch.xcarchive 1.1 14
```

이 명령은 아카이브의 앱·공유 확장 번들 ID와 버전, URL scheme, 공개 개인정보·지원 구성, arm64, Privacy Manifest, dSYM과 **아카이브 당시 서명**을 검사한다. 개발 서명으로 만든 아카이브는 서명 항목에서 실패할 수 있으므로, export 후 실제 IPA의 Apple Distribution 서명과 Organizer의 Validate App 결과를 별도로 확인한다. 현재 미설정 URL을 임의로 채워 검사를 통과시키지 않는다.

## 5. App Store Connect

- Privacy Policy URL과 Support URL에 1단계에서 검증한 주소 입력
- Apple 로그인 계정, 옷장·비교 정보가 Supabase에 저장되는 실제 데이터 흐름을 App Privacy 답변에 반영
- 비면제 암호화 사용 안 함 설정 확인
- 앱 설명과 심사 메모에 무신사·유니클로·ZARA 링크 비교 방식 및 Apple 로그인이 필요한 흐름을 설명
- 심사자가 재현할 수 있는 유효한 공개 상품 URL과 비교 절차 제공

Organizer에서 `Validate App`을 먼저 통과한 뒤 `Distribute App → App Store Connect → Upload`를 실행합니다.

## 6. 업로드 후

- App Store Connect 처리 완료 및 경고 유무 확인
- TestFlight 설치 후 신규 설치, MY 개인정보·지원 링크, 옷장 저장, 무신사·유니클로·ZARA 비교, 공유 확장을 실제 기기에서 재확인
- 심사 제출 전 빌드 번호, 개인정보 답변, 공개 페이지의 내용이 같은 출시 버전을 가리키는지 최종 확인

현재 차단요소와 증거는 `Docs/CodexSessionHandoff.md`의 최신 기록을 기준으로 판단한다. `Docs/AppStoreReadiness-20260806.md`는 8월의 과거 증거다.
