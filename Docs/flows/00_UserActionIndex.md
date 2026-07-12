# 00. 사용자 행동 인덱스

상태 표기: `IMPLEMENTED`, `PARTIAL`, `PLANNED`, `UNUSED`, `UNREACHABLE`, `BROKEN`, `UNKNOWN`.

## 앱 시작

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-APP-001 | 앱 실행 | IMPLEMENTED | `ContentView.body`, `.task` |
| ACT-APP-002 | Splash 0.8초 대기 | IMPLEMENTED | `Task.sleep`, `SplashView` |
| ACT-APP-003 | 로그인 버튼 탭 | IMPLEMENTED | `LoginView`, `onLogin` |
| ACT-APP-004 | 로그인 상태 복원 | BROKEN | `isLoggedIn`은 `@State`, 영구 저장 없음 |
| ACT-APP-005 | 앱 foreground 복귀 | IMPLEMENTED | `scenePhase == .active` |
| ACT-APP-006 | pending shared URL 소비 | IMPLEMENTED | `SharedURLStore.consumePendingProductURL` |
| ACT-APP-007 | URL Scheme `fitmatch://compare` 수신 | IMPLEMENTED | `ContentView.onOpenURL`, `handleDeepLink` |

## 하단 메뉴

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-NAV-001 | 홈 선택 | IMPLEMENTED | `BottomNavigationItem`, `selectedTab = .home` |
| ACT-NAV-002 | 기록 선택 | IMPLEMENTED | `selectedTab = .history` |
| ACT-NAV-003 | 중앙 + 탭 | IMPLEMENTED | `presentCompareFlow(initialURL:nil)` |
| ACT-NAV-004 | 추천 선택 | IMPLEMENTED | `selectedTab = .recommend` |
| ACT-NAV-005 | 내 옷장 선택 | IMPLEMENTED | `selectedTab = .my` |
| ACT-NAV-006 | 비교 탭 선택 | UNUSED | `AppTab.compare` 남음, UI 없음 |

## 홈

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-HOME-001 | 최근 복사한 링크 카드 보기 | IMPLEMENTED | `HomeView.recentClipboardCard` |
| ACT-HOME-002 | 바로 비교하기 | IMPLEMENTED | `onStartCompareWithURL` |
| ACT-HOME-003 | 최근 비교 전체보기 | IMPLEMENTED | `onOpenHistory` |
| ACT-HOME-004 | 최근 비교 카드 재비교 | IMPLEMENTED | `RecentProductPreviewCard.onRecompare` |
| ACT-HOME-005 | 관심 토글 | IMPLEMENTED | `FavoriteProductStore.toggle` |
| ACT-HOME-006 | 광고 placeholder 확인 | IMPLEMENTED | `AdvertisementPlaceholderCard` |

## 내 옷장

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-CLOSET-001 | 목록 조회 | IMPLEMENTED | `@Query UserFit`, `MyClosetView.filteredItems` |
| ACT-CLOSET-002 | 검색 | IMPLEMENTED | `searchText` |
| ACT-CLOSET-003 | 카테고리 필터 | IMPLEMENTED | `selectedCategory` |
| ACT-CLOSET-004 | 브랜드 필터 | IMPLEMENTED | `selectedBrand` |
| ACT-CLOSET-005 | 정렬 변경 | IMPLEMENTED | `sortOption` |
| ACT-CLOSET-006 | 옷 추가 방법 선택 | IMPLEMENTED | `AddClosetMethodSheet` |
| ACT-CLOSET-007 | 상품 링크로 불러오기 | IMPLEMENTED | `LinkClosetRegistrationView` |
| ACT-CLOSET-008 | 직접 입력 | IMPLEMENTED | `AddClosetItemView` |
| ACT-CLOSET-009 | 상세 열기 | IMPLEMENTED | `ClosetItemDetailView` |
| ACT-CLOSET-010 | 수정 | IMPLEMENTED | `ClosetItemDetailView` sheet |
| ACT-CLOSET-011 | 삭제 | IMPLEMENTED | `onDelete` / `deleteItems` |
| ACT-CLOSET-012 | 기준 옷 지정/변경/해제 | IMPLEMENTED | `basisSwipeButton`, heart button |

## 상품 비교

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-COMPARE-001 | 중앙 + 열기 | IMPLEMENTED | `CompareFlowSheet.step.start` |
| ACT-COMPARE-002 | URL 붙여넣기 | IMPLEMENTED | `UIPasteboard.general.string` |
| ACT-COMPARE-003 | 사이즈 계산 | IMPLEMENTED | `startCompare(with:)` |
| ACT-COMPARE-004 | 로딩 확인 | IMPLEMENTED | `step.loading` |
| ACT-COMPARE-005 | 같은 detailCategory 없음 | IMPLEMENTED | `sameDetailItems.isEmpty` |
| ACT-COMPARE-006 | 카테고리 옷 등록 | PARTIAL | URL 기반 등록 구현, 직접 입력은 내 옷장 안내 |
| ACT-COMPARE-007 | 다른 옷 선택 | IMPLEMENTED | `closetSelection`, `confirmReference` |
| ACT-COMPARE-008 | 결과 확인 | IMPLEMENTED | `step.result` |
| ACT-COMPARE-009 | 쇼핑몰 이동 | IMPLEMENTED | `UIApplication.shared.open` |
| ACT-COMPARE-010 | 결과 상품 내 옷장 추가 | IMPLEMENTED | `prepareRegistration` → `sizeSelection` |

## 기록

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-HISTORY-001 | 목록 조회 | IMPLEMENTED | `RecommendationHistoryView` |
| ACT-HISTORY-002 | 전체/관심 segmented | IMPLEMENTED | `selectedScope` |
| ACT-HISTORY-003 | 검색 | IMPLEMENTED | `searchText` |
| ACT-HISTORY-004 | 정렬 | IMPLEMENTED | `sortOption` |
| ACT-HISTORY-005 | 상세 보기 | IMPLEMENTED | `NavigationLink RecommendationResultView` |
| ACT-HISTORY-006 | 내 옷장에 추가 | IMPLEMENTED | `AddComparedProductToClosetSheet` |
| ACT-HISTORY-007 | 쇼핑몰 이동 | IMPLEMENTED | `openURL` |
| ACT-HISTORY-008 | 다시 비교 | IMPLEMENTED | `onRecompare` |
| ACT-HISTORY-009 | 삭제 | IMPLEMENTED | `deleteHistory` |

## 추천/마이

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-RECOMMEND-001 | 추천 탭 확인 | PARTIAL | `RecommendView` placeholder |
| ACT-MY-001 | 마이 통계 확인 | IMPLEMENTED | `MyPageView` |
| ACT-MY-002 | 내 옷장 관리 진입 | IMPLEMENTED | `NavigationLink MyClosetView` |
| ACT-MY-003 | 로그아웃 | IMPLEMENTED | `onLogout`, `isLoggedIn=false` |

## Share Extension

| 행동 ID | 사용자 행동 | 상태 | 주요 코드 |
|---|---|---|---|
| ACT-SHARE-001 | Safari/무신사 공유 | IMPLEMENTED | `ShareViewController.handleSharedContent` |
| ACT-SHARE-002 | URL 추출 | PARTIAL | URL/plainText만 첫 항목 처리 |
| ACT-SHARE-003 | App Group 저장 | IMPLEMENTED | `UserDefaults(suiteName:)` |
| ACT-SHARE-004 | 보러가기 | BROKEN 가능성 | responder chain `UIApplication.open` |
| ACT-SHARE-005 | 앱 직접 실행 후 이어가기 | IMPLEMENTED | `SharedURLStore.consumePendingProductURL` |

