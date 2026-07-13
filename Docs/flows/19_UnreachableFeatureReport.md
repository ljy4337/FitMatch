# 19. 접근 불가/미사용 기능 보고서

## UNUSED / UNREACHABLE

| 기능 | 상태 | 파일 | 설명 |
|---|---|---|---|
| `AppTab.compare` | UNUSED | `Views/AppTab.swift`, `ContentView.swift` | enum case는 있으나 하단 메뉴에는 없음. switch에서 홈으로 흡수 |
| `ShoppingProductFormView(initialURL:)` | UNUSED | `Views/ShoppingProductFormView.swift` | 중앙 +/Share 흐름에서는 제거됨. 파일은 남아 있음 |
| `CompareStartSheet` | UNUSED | `Views/HomeView.swift` | 이전 + BottomSheet. 현재 `CompareFlowSheet` 사용 |
| `MusinsaWebViewParser` | UNUSED fallback 후보 | `Services/MusinsaWebViewParser.swift` | 현재 URL router에서 사용하지 않음. HTML/WKWebView fallback 코드 존재 |
| `BrandDatabaseView` | UNREACHABLE 가능성 | `Views/BrandDatabaseView.swift` | 현재 하단/홈 주요 메뉴에서 직접 진입 경로 없음 |
| `MyPageView` | PARTIAL/UNREACHABLE 가능성 | `Views/MyPageView.swift` | 하단은 `MyClosetView` 직접 연결. 별도 마이 페이지가 현재 내비게이션에 안 보일 수 있음 |

## 버튼 있으나 기능 제한

| 버튼 | 상태 | 비고 |
|---|---|---|
| RecommendView | PLANNED | 실제 추천 없음 |
| CompareFlowSheet 직접 입력하기 | PARTIAL | 내 옷장 추가 화면 안내만 표시 |
| Share Extension 보러가기 | BROKEN 가능성 | responder chain 앱 열기 불확실 |
| 29CM/유니클로 쇼핑몰 바로가기 | PLANNED | disabled/준비중 |

