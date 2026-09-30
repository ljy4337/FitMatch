# 운영 / QA 빌드

브랜치 이름은 DB 연결을 자동 변경하지 않는다. 아래 공유 Scheme을 명시적으로 선택한다.

| 용도 | Scheme | Run / Archive configuration | 앱 ID | Supabase |
|---|---|---|---|---|
| 운영 | FitMatch-Production | Debug / Release | com.ljy4337.fitmatch | aqhrupgjpmrtnystottx |
| QA | FitMatch-QA | Debug-QA / Release-QA | com.ljy4337.fitmatch.qa | hnkplvyegonlhumlejst |

기존 FitMatch Scheme도 Debug/Release이므로 이제 운영을 가리킨다. 개발용으로 사용하지 않는다. 기존 Live/Audit 전용 Scheme은 QA configuration으로 변경하여 개발 DB 연결을 유지한다. 실행 시 별도 환경변수 override도 확인한다. QA에서는 FitMatch-QA만 선택한다. QA와 운영 설정을 공통 소스로 유지하고 브랜치마다 주소를 덮어쓰지 않는다.

## 격리

- 앱 bundle ID와 extension ID가 달라 별도 설치 / 앱 샌드박스를 사용한다.
- QA App Group: group.com.ljy4337.fitmatch.qa. 운영 group.com.ljy4337.fitmatch 유지.
- QA URL scheme: fitmatch-qa. 운영 fitmatch 유지. 서로의 공유 링크를 소비하지 않는다.
- Supabase SDK의 기본 인증 저장 key는 프로젝트 ref별 namespace를 사용한다.
- 기존 개발 앱은 운영과 동일한 bundle ID였다. 첫 운영 테스트는 기존 앱의 필요한 데이터를 확인/보존한 후 깨끗한 설치로 수행한다. 이전 개발 캐시를 운영 테스트에 재사용하지 않는다. 이 작업은 기존 로컬 데이터를 삭제하지 않는다.

## 실기기 설치 전 외부 설정

Apple Developer / Xcode Signing에서 QA 앱 com.ljy4337.fitmatch.qa에 Sign in with Apple을 설정하고, QA extension com.ljy4337.fitmatch.qa.shareextension을 등록한다. 두 QA target에 App Group group.com.ljy4337.fitmatch.qa를 연결한다. 실제 provisioning 성공은 별도 검증한다.

개발 Supabase Apple provider Client IDs에 기존 값을 보존하면서 com.ljy4337.fitmatch.qa를 추가한다. 운영 Client IDs는 com.ljy4337.fitmatch. 비밀번호나 OAuth secret을 Client IDs에 넣지 않는다.

이 문서 작성 시 QA Apple portal/Supabase 설정은 미적용. 운영 Apple 설정 저장은 사용자 보고이며 로그인 성공 검증은 미실행.

## 키 / 실행

프로젝트 빌드 설정의 FITMATCH_SUPABASE_URL / FITMATCH_SUPABASE_PUBLISHABLE_KEY가 Info.plist로 확장된다. 포함된 키는 공개용 publishable key이며 service role은 사용하지 않는다. 기존 FITMATCH_SUPABASE_* 프로세스 환경변수 override가 있으면 번들 설정보다 우선하므로 Xcode Scheme/CI에서 오래된 override를 넣지 않는다.

Xcode에서 Scheme을 선택한 뒤 아이폰 대상으로 Run한다. Archive도 반드시 같은 목적의 Scheme을 선택한다. 원격 QA에 공유 설정을 반영하려면 검토한 변경을 커밋한 뒤 브랜치에 반영해야 한다. 로컬 변경만으로 원격 QA가 갱신되지는 않는다.
