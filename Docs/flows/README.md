# FitMatch 사용자 행동 기반 흐름 문서

이 문서는 현재 FitMatch 코드 기준으로 작성한 사용자 행동, 시스템 처리, 데이터 흐름, 예외, 테스트 매트릭스 문서 묶음이다. 기획으로만 존재하는 기능은 실제 구현과 섞지 않고 `PLANNED`, `UNREACHABLE`, `PARTIAL`로 분리했다.

## 문서 링크

- [00_UserActionIndex.md](00_UserActionIndex.md): 전체 사용자 행동 인덱스
- [01_AppLifecycleFlow.md](01_AppLifecycleFlow.md): 앱 실행, foreground, deep link, pending URL
- [02_AuthenticationFlow.md](02_AuthenticationFlow.md): Splash/Login/OAuth placeholder
- [03_NavigationFlow.md](03_NavigationFlow.md): 커스텀 하단 메뉴와 시트 라우팅
- [04_HomeFlow.md](04_HomeFlow.md): 홈 행동과 최근 비교/클립보드/광고 영역
- [05_ClosetFlow.md](05_ClosetFlow.md): 내 옷장 조회/검색/필터/CRUD
- [06_ReferenceGarmentFlow.md](06_ReferenceGarmentFlow.md): 기준 옷 지정/변경/해제
- [07_ProductRegistrationFlow.md](07_ProductRegistrationFlow.md): URL 기반/직접 입력 옷장 등록
- [08_URLInputFlow.md](08_URLInputFlow.md): 중앙 + BottomSheet URL 입력
- [09_ShareExtensionFlow.md](09_ShareExtensionFlow.md): Share Extension/App Group/deep link
- [10_MusinsaParsingFlow.md](10_MusinsaParsingFlow.md): Musinsa OneLink/API/metadata/size parser
- [11_RecommendationFlow.md](11_RecommendationFlow.md): 기준 옷 선택과 추천 계산
- [12_FitConfidenceFlow.md](12_FitConfidenceFlow.md): Fit Confidence 공식과 코드 차이
- [13_ResultFlow.md](13_ResultFlow.md): 추천 결과 화면 행동
- [14_HistoryFlow.md](14_HistoryFlow.md): 기록 조회/검색/정렬/삭제/재비교
- [15_RecommendTabFlow.md](15_RecommendTabFlow.md): 추천 탭 placeholder
- [16_SwiftDataCRUDFlow.md](16_SwiftDataCRUDFlow.md): SwiftData 모델과 CRUD
- [17_ErrorExceptionFlow.md](17_ErrorExceptionFlow.md): 예외 처리 목록
- [18_StateTransitionFlow.md](18_StateTransitionFlow.md): 상태 전이
- [19_UnreachableFeatureReport.md](19_UnreachableFeatureReport.md): 코드 존재/진입 불가 기능
- [20_ImplementationGapReport.md](20_ImplementationGapReport.md): 구현 gap 및 위험도
- [21_TestCaseMatrix.md](21_TestCaseMatrix.md): 테스트 케이스 매트릭스

## 전체 기능 상태 요약

| 기능 | 상태 | 근거 |
|---|---|---|
| 앱 실행/Splash/Login UI | IMPLEMENTED | `ContentView`, `SplashView`, `LoginView` |
| 실제 OAuth 로그인 | PLANNED | 로그인 버튼은 모두 `onLogin`만 호출 |
| 커스텀 하단 메뉴 홈/기록/+액션/추천/내 옷장 | IMPLEMENTED | `MainTabView`, `FitMatchBottomNavigationBar` |
| 네이티브 Compare 탭 | UNUSED | `AppTab.compare`는 남아 있으나 현재 홈으로 흡수 |
| 중앙 + BottomSheet 비교 | IMPLEMENTED | `CompareFlowSheet` |
| 이전 전체화면 URL 입력 | UNUSED | `ShoppingProductFormView`는 파일 존재, 중앙 +에서는 미사용 |
| 무신사 URL/OneLink 파싱 | PARTIAL | resolver/API parser 구현, 실제 URL/서버 상태 의존 |
| Generic parser | PLANNED | `GenericProductParser.parse`는 항상 throw |
| SwiftData 옷장/상품/추천 기록 저장 | IMPLEMENTED | `UserFit`, `Product`, `ProductSize`, `RecommendationHistory` |
| 기준 옷 지정 | IMPLEMENTED | `MyClosetView` swipe/heart |
| 기준 옷 detailCategory 1개 제한 | IMPLEMENTED | `MyClosetView.confirmBasisChange()` |
| Share Extension URL 저장 | IMPLEMENTED | `ShareViewController.savePendingURL` |
| Share Extension에서 앱 자동 열기 | BROKEN 가능성 | responder chain private-ish 방식, 성공 여부 불명확 |
| Smart Clipboard | IMPLEMENTED | `SmartClipboardService`, `ContentView.inspectClipboardIfNeeded` |
| 추천 탭 실제 AI/광고 추천 | PLANNED | `RecommendView` placeholder |
| 가격 추적/할인/재입고 | PLANNED | Favorite만 UserDefaults |

## 전체 사용자 행동 목록

앱 시작, 로그인 버튼 탭, foreground 복귀, URL scheme 진입, Share Extension 보러가기, 홈 최근 링크 바로 비교, 중앙 + 탭, URL 붙여넣기, URL 직접 입력, 무신사 바로가기, 상품 분석, 기준 옷 없음 분기, 기준 옷 등록, 사이즈 선택, 등록 정보 확인, 다른 옷 선택, 추천 결과 확인, 쇼핑몰 이동, 내 옷장에 추가, 기록 상세 보기, 기록 검색/정렬/관심/삭제/재비교, 내 옷장 조회/검색/필터/정렬/추가/상세/수정/삭제/기준 옷 변경, 추천 탭 확인, 마이 로그아웃.

## 위험한 예외 처리

- `try? modelContext.save()` 사용이 많아 저장 실패 UI가 없다. 위험도 High.
- Share Extension `UIApplication.open` responder chain은 성공 여부를 신뢰할 수 없다. 위험도 High.
- `CompareFlowSheet`의 비동기 Task는 화면 이탈 시 취소 토큰을 갖지 않는다. 위험도 Medium.
- `ProductURLParserService.extractedURLString`은 musinsa 포함 URL만 추출한다. Generic URL 텍스트 내 추출은 제한적이다. 위험도 Medium.
- 기준 옷 자동 추천은 `CompareFlowSheet`에서 same detail item 존재만 확인하고 추천 서비스에는 same detail 배열을 넘긴다. “대표 기준 옷 우선”은 서비스 sort에서 유지되지만 same source/brand 조건은 후보가 제한되면 약화된다. 위험도 Low.

## 주요 버그 후보

- Share Extension에서 보러가기 후 extension만 닫히고 앱이 안 열릴 수 있음.
- `ShoppingProductFormView`가 UNUSED 상태지만 문서/기존 코드에 남아 있어 향후 중복 UX가 재등장할 수 있음.
- `AppTab.compare`가 enum에 남아 있어 외부 코드에서 선택하면 홈으로 표시됨.
- 저장 실패, 삭제 실패가 사용자에게 표시되지 않음.
- 추천 결과가 0%여도 결과 객체가 생성될 수 있음.

## 테스트가 필요한 기능

- 무신사 일반 URL, OneLink URL, 잘못된 URL, 사이즈표 없음, metadata만 성공.
- 기준 옷 없음 → 등록 → 자동 비교 재개.
- 기준 옷 없음 → 다른 옷 선택 → 확인 → 임시 비교.
- Share Extension 저장 후 앱 직접 실행 시 pending URL consume.
- 기록 삭제/관심 토글/재비교.
- 내 옷장 기준 옷 1개 제한.

