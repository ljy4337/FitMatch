# 정상 로그인 앱 등록·비교 검증 — 2026-09-16

## 결과

| 단계 | 결과 | 실제 증거 |
|---|---|---|
| 무신사 ct27zw6f 상품 불러오기 | PASS | 5328103, 사이즈 4개, 서버 확인 후 다음 활성화 |
| 기존 XL 중복 등록 | PASS | 중복 안내, 기존 XL 보존 |
| 신규 M 등록 | PASS | 앱 완료 안내 + 서버 Closet 3e4f48d7-bed3-4a17-a42b-444fbd9dd9f2 재조회 |
| 실측 저장 | PASS | 6개 코드·값·단위가 선택한 서버 M과 정확히 일치 |
| M 선택 → UNIQLO E487214 상세 비교 | PASS | 추천 73, 유사도 85%, 서버 COMPLETED |
| 앱 재시작 → 기록 조회 | PASS | UI 자동 테스트에서 배럴치노팬츠 기록 확인 |

- 정상 Apple 로그인 세션 사용. 모의 인증·DB 사용자 사칭·직접 insert 사용 안 함.
- 처음 M 등록 후 테스트 조작 문제를 보정하여 비교만 재개했다. 최종 UI 테스트 한 번이 등록부터 모두 재수행한 것은 아니다.
- 최종 UI: 1 passed / 0 failed / 0 skipped. Result bundle: `/Users/jinyoung/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/result-bundles/test_sim_2026-09-15T22-20-28-249Z_pid62503_cbb1bdd4.xcresult`.
- 최종 comparison: 73a67ddd-d52c-4a3a-ae83-c8a1a485168a. exact_registered_closet / exact_recommended_identity / history_visible 모두 true.
- 실제 테스트 데이터: 새 M 옷 1개와 완료 비교 2개가 남아 있다. 기존 XL과 다른 사용자 데이터는 삭제하지 않았다.

## 수정한 테스트/접근성

- 사이즈 메뉴의 유효한 frame을 사용하여 iOS 자동화 hit-point 오류 회피.
- 화면 뒤쪽 홈 카드가 아닌 표시된 동일 M 후보만 선택.
- 비교 카드 접근성 설명에 보유 사이즈 추가. 같은 상품의 M/XL을 구분할 수 있음.
- 현재 화면 제목인 개별 비교 결과로 assertion 수정; 앱 재시작 후 기록 조회 추가.

## 아직 남은 문제

- 미리보기 79 / 89%와 상세 73 / 85%가 다름. 표시·계산 경로 일관성은 별도 수정/검증 필요.
- 구형 무신사 총장 6행의 원천 측정 근거 보완은 미완료.
- 자라를 포함한 전체 상품·전체 기능·실제 아이폰의 검증 완료를 뜻하지 않음.
