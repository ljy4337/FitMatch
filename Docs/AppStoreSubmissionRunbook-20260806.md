# FitMatch 1.0 App Store 제출 실행 순서

기준 빌드: FitMatch 1.0 (4)  
기준일: 2026-08-07

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

최신 자동 회귀 증거는 `/tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult`입니다.

## 4. 배포 서명 archive

Xcode에서 FitMatch scheme과 `Any iOS Device`를 선택하고 `Product → Archive`를 실행합니다. Organizer에서 Apple Distribution 인증서와 App Store 배포 프로파일로 서명됐는지 확인합니다.

archive 경로를 다음 감사 명령에 전달합니다.

```bash
scripts/audit-app-store-archive.sh /path/to/FitMatch.xcarchive
```

`RESULT: passed`가 아니면 업로드하지 않습니다. 이 명령은 앱·공유 확장 번들 ID와 버전, URL scheme, 공개 개인정보·지원 구성, arm64, Privacy Manifest, dSYM, Apple Distribution 서명을 검사합니다.

## 5. App Store Connect

- Privacy Policy URL과 Support URL에 1단계에서 검증한 주소 입력
- 현재 빌드 기준 App Privacy는 FitMatch 운영자에게 전송되는 데이터가 없음을 실제 코드와 다시 대조
- 비면제 암호화 사용 안 함 설정 확인
- 앱 설명과 심사 메모에 무신사·유니클로 상품 링크 비교 방식과 계정이 필요하지 않음을 설명
- 심사자가 재현할 수 있는 유효한 공개 상품 URL과 비교 절차 제공

Organizer에서 `Validate App`을 먼저 통과한 뒤 `Distribute App → App Store Connect → Upload`를 실행합니다.

## 6. 업로드 후

- App Store Connect 처리 완료 및 경고 유무 확인
- TestFlight 설치 후 신규 설치, MY 개인정보·지원 링크, 옷장 저장, 무신사·유니클로 비교, 공유 확장을 실제 기기에서 재확인
- 심사 제출 전 빌드 번호, 개인정보 답변, 공개 페이지의 내용이 같은 출시 버전을 가리키는지 최종 확인

세부 차단요소와 증거는 `Docs/AppStoreReadiness-20260806.md`를 기준으로 판단합니다.
