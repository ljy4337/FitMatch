# FitMatch connectDB 실기기 E2E 체크표

## 목적

실제 iPhone에서 `로그인 → 옷장 → 비교 → DB 저장 → 회원 탈퇴`가 처음부터 끝까지 연결되는지만 확인한다.

이번에는 아래 5단계만 수행한다. 카카오·네이버와 DB 기본 엔진 전환은 이 검사가 끝난 뒤 진행한다.

## 준비

- 브랜치: `connectDB`
- Supabase 프로젝트: `hnkplvyegonlhumlejst`
- 회원 탈퇴에 사용해도 되는 Apple 테스트 계정
- Supabase SQL Editor에 다음 파일을 열어 둔다.
  - `supabase/sql/connectdb_e2e_readonly_verification.sql`
- Secret Key, access token, Apple private key는 화면 캡처나 채팅에 포함하지 않는다.

## 1. Apple 로그인

아이폰에서:

1. FitMatch를 설치하고 실행한다.
2. `Apple로 계속하기`를 누른다.
3. 홈 화면이 표시되는지 확인한다.
4. 앱을 완전히 종료하고 다시 실행한다.
5. 로그인 화면이 다시 나오지 않고 홈으로 복구되는지 확인한다.

Supabase에서:

1. `Authentication → Users`에서 방금 로그인한 테스트 사용자를 찾는다.
2. 사용자 UUID를 복사한다. UUID는 비밀번호나 token이 아니다.
3. 확인 SQL의 첫 번째 `PASTE_TEST_USER_UUID`만 UUID로 바꾸고 실행한다.

통과 조건:

- `auth.user_exists = true`
- `auth.providers`에 `apple` 존재
- 앱 재실행 후 로그인 유지

## 2. 내 옷장 저장

아이폰에서:

1. 실측값을 직접 입력한 옷 1개를 등록한다.
2. 쇼핑몰 링크로 옷 1개를 등록한다.
3. 둘 중 하나를 기준 옷으로 지정한다.
4. 앱을 종료하고 다시 실행해 두 옷이 그대로 보이는지 확인한다.
5. 확인 SQL을 다시 실행한다.

통과 조건:

- `active_closet_items >= 2`
- `recent_closet_items`에 등록한 두 상품 존재
- 기준 옷은 `is_reference = true`
- 같은 항목이 중복 저장되지 않음

## 3. 상품 비교와 실측 저장

아이폰에서:

1. 유니클로 실측 보유 상품 1개를 비교한다.
2. 무신사 실측 보유 상품 1개를 비교한다.
3. 두 결과가 비교 기록에 표시되는지 확인한다.
4. 실행 시각과 두 상품 코드를 기록한다.
5. 확인 SQL을 다시 실행한다.

통과 조건:

- `product_observation_submissions >= 2`
- 각 `recent_product_observations.processing_status = promoted`
- 실측 상품은 `raw_measurement_rows > 0`
- 정규화 성공 상품은 `canonical_measurement_rows > 0`
- `comparison_runs >= 2`
- 완료된 비교는 `status = completed`
- 완료된 비교의 `result_rows > 0`, `measurement_rows > 0`
- 같은 `client_history_id`가 중복 생성되지 않음

비교가 정책상 차단된 상품이면 `status = blocked`이고 결과 행이 없는 것이 정상이다. 차단을 억지로 완료 처리하면 실패다.

### 내일 세 쇼핑몰 빠른 확인표

반드시 2026-08-25 이후 새로 빌드한 앱을 설치한다. 이전 설치본에는 ZARA 공유 확장 허용과 UNIQLO 이미지 복구가 들어 있지 않을 수 있다.

1. 무신사 상품 URL을 Safari 또는 무신사 앱의 공유하기에서 FitMatch로 보낸다.
   - 상품명·카테고리·사이즈표가 표시되어야 한다.
   - 비교 가능한 실측이 있으면 비교 결과가 나오고, 부족하면 억지 비교하지 않고 직접 입력/보류 안내가 나와야 한다.
2. 유니클로에서 색상을 선택한 상품 URL을 공유한다.
   - 선택 색상 이미지가 우선 표시되어야 한다.
   - 선택 색상 이미지를 받을 수 없으면 같은 상품의 공식 기본 이미지가 표시되어야 하며 빈 이미지로 끝나면 실패다.
   - 저장 후 홈·내 옷장·상세 화면에서도 이미지가 보여야 한다.
3. ZARA 상품 URL을 공유하기와 직접 붙여넣기로 각각 한 번 실행한다.
   - `상품 정보 불러오기` 버튼이 활성화되어야 한다.
   - URL의 `p########` 상품과 `v1` 선택 색상이 서로 바뀌지 않아야 한다.
   - 상품명·ZARA 출처·카테고리가 표시되어야 한다.
   - 공식 상품 실측(`measureGuideInfo`)이 있으면 자동 비교하고, 신체 권장표만 있거나 실측이 부족하면 직접 입력/보류로 전환해야 한다.
4. 각 실행마다 시각, 전체 URL, 상품 코드, 선택 색상, 최종 화면을 기록한다.

정상적인 안전 동작:

- 알 수 없는 카테고리나 서로 충돌하는 분류는 자동 확정하지 않는다.
- 비교 가능한 공식 실측이 부족하면 높은 점수를 만들어 내지 않는다.
- ZARA가 401/403/429 또는 접근 제한을 반환하면 우회하지 않고 재시도/직접 입력 안내로 끝난다.

실패 판정:

- 공식 무신사·유니클로·ZARA URL인데 공유 확장에서 거부된다.
- ZARA URL을 붙여넣었는데 버튼이 비활성화된다.
- 유니클로 공식 이미지 후보가 있는데도 모든 화면이 빈 이미지다.
- 선택한 ZARA/유니클로 색상과 다른 variant가 조용히 저장된다.
- 분류 또는 실측 근거가 부족한데 자동 비교 결과로 넘어간다.

## 4. 탈퇴 직전 DB 기록

1. 확인 SQL을 실행한다.
2. 결과 JSON을 `탈퇴 전`으로 저장한다.
3. `shared_catalog_counts`의 네 숫자도 기록한다.

주의:

- 이 단계 전에는 회원 탈퇴를 누르지 않는다.
- 테스트 계정에 필요한 옷장·비교 데이터가 모두 생성됐는지 먼저 확인한다.

## 5. 회원 탈퇴

아이폰에서:

1. `MY → 회원 탈퇴`를 누른다.
2. 경고 내용을 확인하고 최종 탈퇴를 실행한다.
3. 로그인 화면으로 이동하는지 확인한다.
4. 앱을 종료하고 다시 실행해 이전 옷장과 비교 기록이 보이지 않는지 확인한다.

Supabase에서:

1. 같은 사용자 UUID로 확인 SQL을 다시 실행한다.
2. 결과 JSON을 `탈퇴 후`로 저장한다.

통과 조건:

- `auth.user_exists = false`
- `identity_count = 0`, `session_count = 0`
- `user_owned_counts`의 모든 값이 0
- `recent_closet_items`, `recent_comparisons`, `recent_product_observations`가 빈 배열
- `shared_catalog_counts`는 탈퇴 전보다 줄어들지 않음

`shared_catalog_counts`는 모든 사용자가 함께 쓰는 쇼핑몰 상품·실측 데이터다. 회원 탈퇴로 삭제되면 안 된다.

## 실패했을 때 전달할 내용

다음 네 가지만 전달한다.

1. 실패한 단계 번호
2. 실행 시각
3. 쇼핑몰과 상품 코드
4. 오류 화면 또는 확인 SQL 결과 JSON

token, Secret Key, Apple private key는 전달하지 않는다.

## 완료 판정

- 1~5단계가 모두 통과하면 `DEV-P0-01~04`와 `AI-P0-02`를 완료 처리한다.
- 하나라도 실패하면 해당 단계만 재현하고 `AI-P0-03`에서 원인을 수정한다.
