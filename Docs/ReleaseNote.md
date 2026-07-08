# FitMatch Release Note

작성일: 2026-07-07

## v0.1-dev

현재 개발 중인 MVP 버전이다.

### 데이터 구조

- SwiftData 모델 도입
- `Brand`, `Product`, `ProductSize`, `UserFit`, `RecommendationHistory` 구조 정리
- 기존 UserDefaults 기반 저장 구조에서 SwiftData 중심 구조로 전환
- 브랜드와 상품, 상품 사이즈 관계 구성
- 사용자 기준 옷 데이터 `UserFit`으로 정리
- 추천 결과를 `RecommendationHistory`로 저장

### 앱 구조

- Splash → Login → MainTab 흐름 구성
- 하단 탭을 홈 / 비교 / 기록 / 추천 / 마이로 구성
- 내 옷장은 독립 탭이 아니라 홈/마이에서 접근하도록 변경
- Home을 대시보드 + 빠른 비교 진입점으로 리뉴얼

### 내 옷장

- 내 옷장 목록 구현
- 옷 등록 구현
- 옷 상세 보기 구현
- 옷 수정 구현
- 옷 삭제 구현
- 대표 옷 지정/해제 구현
- 빈 옷장 상태 이미지와 안내 문구 추가
- 카테고리별 실측 입력 항목 분리
- 성별에 따른 카테고리/세부 카테고리 표시
- 만족도 별 UI 적용
- 대표 옷 설정을 등록 화면이 아니라 옷장 목록에서 처리하도록 변경

### 상품 출처 구조

- `sourceType` 추가
- `sourceName` 추가
- `brandName`과 플랫폼/출처 분리
- 공식몰 / 쇼핑 플랫폼 / 직접 입력 구분
- 무신사 파싱 결과를 marketplace 출처로 저장

### 비교

- 상품 비교 화면을 URL 입력 중심으로 단순화
- 쇼핑 상품 직접입력 UI 제거
- 사이즈별 실측 수동 입력 UI 제거
- `사이즈 계산` 버튼으로 상품 로드와 추천 계산을 연결
- 추천 결과를 시트로 표시
- 기준 옷이 없을 때 등록 또는 임시 비교 선택 유도
- 사용자가 기존 옷을 선택해 임시 비교할 수 있는 흐름 추가

### 무신사

- 무신사 URL 판별 로직 단순화
- `url.absoluteString.lowercased().contains("musinsa")` 기준 적용
- 무신사 OneLink 처리 일부 구현
- GET 요청으로 리다이렉트 따라가기 구현
- 최종 URL 또는 body에서 상품번호 추출
- 무신사 상품 메타데이터 API 연동
- 무신사 actual-size API 연동
- actual-size JSON을 `ProductSize`로 변환
- 상품명, 브랜드, 카테고리, 세부 카테고리, 이미지 URL, 가격, canonical URL 추출 구조 추가
- HTML/SwiftSoup 기반 방식은 핵심 경로에서 제외하고 actual-size API 중심으로 전환

### 추천

- `RecommendationService` 구현
- 카테고리 기반 추천 기준 선택
- 플랫폼/브랜드/세부카테고리 우선 매칭 추가
- 대표 옷 우선순위 반영
- weighted difference 기반 추천 계산
- 추천도 0~100% 계산
- 같은 대분류 fallback penalty 적용
- 사용자 선택 임시 비교 penalty 적용
- 반팔/민소매 등 소매길이 가중치 보정
- 추천 결과에 기준 옷, 상품 카테고리, 기준 옷 카테고리, 비교 방식 표시

### 기록

- 추천 기록 저장
- 추천 기록 목록 화면 구현
- 기록에서 쇼핑몰 이동 구현
- 기록에서 다시 비교 구현
- 기록 삭제 기능 구현
- 추천 탭에서도 추천 카드 삭제 기능 구현

### UI

- 미니멀 패션 플랫폼 느낌의 카드 UI 도입
- `FitMatchCard`, `CardView`, `PrimaryButton`, `SecondaryButton`, `SectionHeader`, `SmallInfoCard` 추가
- 홈 Hero 카드 리뉴얼
- 비교/기록/추천 화면 상단 큰 타이틀 제거
- MyCloset 상단 `My Closet` 제거
- 옷장 추가 버튼을 큰 원형 버튼으로 변경
- 다크모드 대응 가능한 system color 중심 UI 적용

### Share Extension

- Share Extension 파일 구조 추가
- App Group ID 정의
- 공유 URL을 App Group UserDefaults에 저장하는 구조 구현
- 메인 앱에서 pending URL을 읽어 비교 탭으로 이동하는 구조 구현
- Xcode project target 연결은 현재 코드 기준 확인되지 않음

### 알려진 미완성

- Generic parser 미구현
- 유니클로/29CM/W컨셉/쿠팡 parser 미구현
- 실제 OAuth 미구현
- Share Extension target 연결 필요
- 추천 탭은 아직 기록 기반
- 상품 이미지 UI 반영 필요
