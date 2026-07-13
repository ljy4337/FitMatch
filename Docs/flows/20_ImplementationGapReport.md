# 20. 구현 Gap / 버그 후보

| ID | 관련 파일 | 사용자 행동 | 예상 결과 | 실제/위험 | 위험도 | 권장안 |
|---|---|---|---|---|---|---|
| GAP-001 | `ShareViewController.swift` | 보러가기 탭 | 앱 열림 | `UIApplication.open` success와 무관하게 completeRequest 가능 | High | Universal Link 또는 extensionContext 방식 재검토, 실패 시 complete 금지 |
| GAP-002 | 여러 파일 | 저장 | 실패 시 알림 | `try? modelContext.save()`로 실패 무시 | High | do/catch, alert/toast 도입 |
| GAP-003 | `RecommendationService.swift` | 비교 항목 0개 | 계산 불가 | score 0 history 생성 가능 | High | comparedItems empty면 nil 반환 |
| GAP-004 | `RecommendationService.swift` | fallback 비교 | 점수 감점 | `scorePenalty` 실제 적용 확인 안 됨 | Medium | score 산출 시 penalty 적용 |
| GAP-005 | `CompareFlowSheet.swift` | 분석 중 sheet 닫기 | Task 취소 | 취소 처리 없음 | Medium | `Task` 핸들 저장/취소 |
| GAP-006 | `ProductURLParserService.swift` | 일반 URL 텍스트 입력 | URL 추출 | musinsa 패턴만 추출 | Medium | 일반 URL regex 추가 |
| GAP-007 | `ContentView.swift` | 앱 재실행 | 로그인 유지 | `isLoggedIn` 초기화 | Medium | UserDefaults/Keychain session 상태 |
| GAP-008 | `HomeView.swift` | 기존 CompareStartSheet | 미사용 제거 | 코드 잔존 | Low | 후속 정리 |
| GAP-009 | `RecommendationHistoryView.swift` | 기록 삭제 | 관계 정리 | product orphan 가능 | Medium | delete rule 확인/명시 |
| GAP-010 | `LinkClosetRegistrationView.swift` | 링크 등록 성공 | Product 관계 저장 | 저장 경로 일부만 확인 필요 | Medium | 통합 registration service 추출 |

