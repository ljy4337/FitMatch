# 21. 테스트 케이스 매트릭스

| 테스트 ID | 대상 | 사전 조건 | 사용자 행동 | 입력 데이터 | 예상 시스템 처리 | 예상 UI | 데이터 변경 | 실패 시나리오 | 자동화 |
|---|---|---|---|---|---|---|---|---|---|
| TC-APP-001 | 앱 실행 | clean install | 앱 실행 | 없음 | seed → splash → login | LoginView | sample data 생성 | seed 실패 | UI 가능 |
| TC-AUTH-001 | 로그인 | LoginView | Apple 버튼 | 없음 | isLoggedIn true | Home | 없음 | 상태 미저장 | UI 가능 |
| TC-NAV-001 | 하단 메뉴 | 로그인됨 | 홈/기록/추천/내 옷장 탭 | 없음 | selectedTab 변경 | 해당 화면 | 없음 | NavigationStack 초기화 | UI 가능 |
| TC-COMP-001 | URL 비교 happy | 기준 옷 있음 | + → URL → 계산 | 무신사 products URL | parser → recommend → save | 결과 | Product/History | 네트워크 실패 | UI+mock |
| TC-COMP-002 | OneLink | 기준 옷 있음 | + → URL | musinsa.onelink | redirect → productID | 결과 | History | productID 없음 | 통합 |
| TC-COMP-003 | Invalid URL | 로그인됨 | URL 입력 | `abc` | normalizedURL 또는 parser 실패 | error state | 없음 | 메시지 부정확 | UI |
| TC-COMP-004 | Unsupported URL | 로그인됨 | URL 입력 | non-musinsa | Generic throw | error state | 없음 | fallback 없음 | UI |
| TC-COMP-005 | Missing basis | 옷장 empty | 무신사 비교 | 반팔 URL | parse 성공, sameDetail empty | 등록/다른 옷 선택 | 없음 | 다른 옷 버튼 disabled | UI |
| TC-COMP-006 | Register then resume | 옷장 empty | 등록하기 → 사이즈 선택 → 저장 | parsed sizes | UserFit 저장 → temp recommend | 결과 | UserFit/History | save 실패 무시 | UI |
| TC-COMP-007 | Other reference | 같은 대분류 옷 있음 | 다른 옷 선택 | 선택 item | confirm → temp recommend | 결과 | History | 측정값 0개 | UI |
| TC-FIT-001 | Fit 100 | 기준/상품 동일 | 계산 | same measurements | score 100 | 100% | History | 없음 | unit |
| TC-FIT-002 | Partial measurement | 소매 없음 | 계산 | 3개 항목 | 소매 ignored | confidence 평균 | History | 0개 항목 | unit |
| TC-FIT-003 | 20cm diff | 큰 차이 | 계산 | diff 20 | item score 0 | 낮은 confidence | History | all zero | unit |
| TC-CLOSET-001 | 직접 등록 | 로그인됨 | 내 옷장 추가 | 정상 입력 | UserFit insert | 목록 갱신 | UserFit | save 실패 | UI |
| TC-CLOSET-002 | 숫자 오류 | 직접 등록 | 저장 | `abc` 실측 | canSave false | 저장 disabled | 없음 | 안내 부족 | UI |
| TC-CLOSET-003 | 기준 옷 변경 | 같은 detail 기준 있음 | 새 하트 | 확인 | 기존 false 새 true | 하트 갱신 | UserFit 수정 | save 실패 | UI |
| TC-CLOSET-004 | 삭제 | 옷 있음 | swipe delete | 없음 | delete/save | 목록 제거 | UserFit delete | 관계 잔존 | UI |
| TC-HIST-001 | 기록 목록 | 기록 있음 | 기록 탭 | 없음 | query/filter | 카드 목록 | 없음 | product nil 불가 | UI |
| TC-HIST-002 | 기록 삭제 | 기록 있음 | 삭제 | 없음 | delete/save | 목록 제거 | History delete | save 실패 | UI |
| TC-HIST-003 | 관심 필터 | 기록 있음 | heart → 관심 | 없음 | UserDefaults toggle | heart 변경 | Favorite IDs | 동기화 없음 | UI |
| TC-SHARE-001 | Share URL | Safari | 공유 FitMatch | URL item | App Group 저장 | 완료 UI | pending URL | URL 없음 | 수동 |
| TC-SHARE-002 | Share text | 공유 | plain text URL | text | URL init | 저장 | pending URL | 텍스트 내 URL 추출 미흡 | 수동 |
| TC-SHARE-003 | 직접 앱 실행 이어가기 | pending 있음 | 앱 실행 | pending URL | consume → compare | sheet loading/result | pending 삭제 | 중복 소비 | UI |
| TC-SHARE-004 | 보러가기 | extension 완료 | 탭 | fitmatch URL | responder open | 앱 전환 기대 | pending 유지/소비 | extension만 닫힘 | 수동 |
| TC-IMG-001 | 이미지 URL | history/product image | 화면 진입 | imageURL | AsyncImage | 썸네일 | 없음 | load failure placeholder | UI |
| TC-ERR-001 | Network fail | URL 비교 | 계산 | offline | parser catch | error state | 없음 | 로딩 고착 | 수동 |
| TC-ERR-002 | Parsing partial | metadata only | 계산 | no sizes | partial error | error/notice | product not saved | UX 불명확 | mock |
| TC-ERR-003 | App background | loading 중 | 홈 버튼 | 없음 | Task 계속 가능 | 복귀 후 상태 불명확 | possibly save | race | 수동 |

