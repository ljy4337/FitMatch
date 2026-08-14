# FitMatch 1.0 App Store 준비 상태

기준일: 2026-08-07  
대상: iPhone / iOS 17 이상 / 1.0 (4)

## 검증 완료

- 품질 진단 내보내기를 포함한 최신 코드 기준 서명 제외 Release archive 생성 성공: `/tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive`, arm64, 앱 `com.ljy4337.fitmatch` 1.0 (4), 공유 확장 `com.ljy4337.fitmatch.shareextension` 1.0 (4) 포함
- 앱과 공유 확장의 Privacy Manifest 포함 및 plist 검사 통과
- 앱 아이콘, dSYM, App Group entitlement, 암호화 사용 여부 설정 확인
- 전체 자동 회귀 284개: 통과 279개, 실패 0개, 실서버 전용 명시적 skip 5개
- 무신사 699쌍 + 유니클로 180쌍 = 실제 실측 비교 879쌍 독립 검사 오류 0건
- 무신사 1,545개 + 유니클로 1,015개 = 실제 상품 분류 2,560건 의미 감사 오류 0건
- 비교쌍 중 대분류 불일치 0건, 세부분류 불일치 0건, 중복·산술·신뢰도 오류 0건
- 로컬 품질지표 계측: 앱 실행, 공유 수신·소비, 파싱 성공·실패, 분류 해상도, 비교 결과·신뢰도, 옷장 저장
- 계측 데이터는 집계 숫자만 App Group에 저장하며 상품명·URL·상품 ID·실측값·사용자 식별자를 포함하지 않음
- MY → 문의 및 지원에서 사용자가 개인정보 없는 품질 진단을 직접 내보낼 수 있으며 단위 테스트 5/5와 UI 접근 테스트 1/1 통과
- Release 빌드에서 상품 URL·상품명·옷장 이름·원본 카테고리·사이즈표·비교 상세를 출력하던 진단 로그를 비활성화하고 전체 회귀 재검증 완료
- iPhone 14 Pro / iOS 26.5.2에서 개발 서명 빌드·설치·전면 실행·딥링크 수신·처리 후 프로세스 생존 확인
- 실기기 핵심 UI 자동화는 첫 기기에서 생체인증 취소, 최신 재시도에서 다른 앱의 전면 진입으로 각각 중단됐으며 앱 크래시로 계산하지 않음
- 최신 개발 서명 빌드는 이진영의 iPhone에 Xcode 테스트 경로로 설치·실행되고 홈 핵심 접근성 요소까지 확인됨
- URL scheme 이름과 식별자를 각각 `fitmatch`, `com.ljy4337.fitmatch`로 archive 내부에서 확인
- 활성 MY 화면에서 로컬 개인정보처리방침과 문의·지원 화면에 접근 가능하며 실제 화면 이동 UI 테스트 통과
- 개인정보·지원 구성은 HTTPS URL과 형식이 유효한 이메일만 허용하고, 미설정 상태를 숨기지 않음
- `scripts/audit-app-store-archive.sh` 제출 게이트 추가: 번들·버전·URL scheme·arm64·Privacy Manifest·dSYM·앱/공유 확장 Apple Distribution 서명을 검증함
- 최신 archive 감사 결과는 공개 URL 2개와 Apple Distribution 서명 2개만 실패했으며, 나머지 구조·번들·버전·arm64·Privacy Manifest·dSYM 검사는 통과함
- 최신 전체 회귀 결과: `/tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult`

## 제출 차단요소

1. 개인정보처리방침과 고객지원의 실제 공개 URL 및 연락처가 아직 없음
2. 배포 인증서로 서명한 archive 및 App Store Connect 업로드 검증이 남음
3. 실제 아이폰에서 공유 확장·데이터 보존·네트워크 복구·외부 앱 왕복 QA가 남음
4. 200쌍 사람 검수표 판정이 비어 있어 체감 핏 결과의 사람 기준 정확도는 아직 수치화할 수 없음

위 1은 임시 주소를 넣으면 심사 위험이 커지므로 실제 URL을 받은 뒤 `FitMatchPrivacyPolicyURL`, `FitMatchSupportURL`에 넣어야 합니다. 앱 내 개인정보처리방침과 지원 안내는 구현·검증됐습니다. Apple은 iOS 앱의 개인정보처리방침 URL과 사용자가 쉽게 접근할 수 있는 앱 내 개인정보처리방침을 요구하며, 지원 URL에는 실제 연락 가능한 수단이 있어야 합니다.

제출 순서는 `Docs/AppStoreSubmissionRunbook-20260806.md`를 따릅니다.

## App Store Connect 개인정보 답변

현재 빌드 기준 계측은 기기 밖으로 전송되지 않으므로 App Privacy의 데이터 수집 질문은 `수집하지 않음`으로 답할 수 있습니다. 이후 Supabase 등으로 집계값을 전송하기 전에 전송 항목·보존기간·동의·개인정보처리방침·App Privacy 답변을 함께 갱신해야 합니다.

## 출시 판정 게이트

- 자동 회귀: 284개 중 통과 279개, 실패 0개, 실서버 전용 명시적 skip 5개
- 실제 비교쌍 무결성: 오류 0건
- 서명된 Release archive와 업로드 검증: 통과
- 실제 아이폰 핵심 동선: 전 항목 통과
- 앱 내 개인정보처리방침·지원 화면: 통과
- 공개 개인정보처리방침·지원 URL 및 이메일: 실제 값 연결 후 동작 확인
- 200쌍 사람 검수: 중대 오판 0건, 미확신 결과는 자동 확정하지 않음

## Apple 공식 기준

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Review](https://developer.apple.com/app-store/review/)
- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
