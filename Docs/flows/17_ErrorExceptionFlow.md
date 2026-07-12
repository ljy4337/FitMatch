# 17. 오류/예외 처리 목록

## 입력 예외

| 예외 | 처리 상태 | 코드 |
|---|---|---|
| 빈 URL | 처리 완료 | 버튼 disabled 또는 invalidURL |
| 공백 URL | 처리 완료 | trim |
| 비정상 URL | 처리 완료 | `ProductURLParserError.invalidURL` |
| 지원하지 않는 플랫폼 | 일부 처리 | Generic parser 실패 |
| 잘못된 실측 숫자 | 처리 완료 | `AddClosetItemViewModel.measurements nil` |
| 필수값 누락 | 처리 완료 | canSave false |
| 중복 옷장 상품 | 일부 처리 | URL/size/productCode 기준 |

## 네트워크 예외

| 예외 | 처리 상태 | 비고 |
|---|---|---|
| 인터넷 없음/DNS/타임아웃 | 일부 처리 | catch 후 parser error |
| HTTP 4xx/5xx | 일부 처리 | non-2xx throw |
| actual-size API 실패 | 일부 처리 | partial metadata |
| metadata API 실패 | 처리 완료 | HTML fallback |
| 느린 네트워크 | 일부 처리 | loading UI, timeout 별도 없음 |

## 파싱 예외

| 예외 | 처리 상태 |
|---|---|
| productID 추출 실패 | 일부 처리 |
| JSON 구조 변경 | 일부 처리 |
| 사이즈표 없음 | 일부 처리 |
| 일부 측정값 없음 | 처리 완료: 0 저장, Fit Confidence 제외 |
| 이미지 URL 상대경로 | 처리 완료 |
| Generic parsing | 미구현 |

## 데이터 예외

| 예외 | 상태 | 위험 |
|---|---|---|
| 기준 옷 없음 | 처리 완료 | MissingReference UI |
| same detail 없음 | 처리 완료 | 등록/다른 옷 선택 |
| same category도 없음 | 일부 처리 | 다른 옷 선택 disabled, 등록 유도 |
| 비교 항목 0개 | 일부 처리 | score 0 결과 가능 |
| SwiftData 저장 실패 | 미처리 | High |
| 삭제 대상 관계 누락 | 불명확 | Medium |

## UI/상태 예외

| 예외 | 상태 |
|---|---|
| Sheet 중복 | 최근 개선: Main activeSheet 단일, 단 내부 다른 화면에는 별도 sheet 존재 |
| 분석 중 재탭 | 일부 처리: loading step이나 버튼 disable 완전하지 않음 |
| 화면 이탈 중 Task 완료 | 미처리 |
| 앱 background 전환 | 일부 처리 |
| 공유 URL 중복 소비 | consume 시 삭제됨, 중복 방지 partial |
| 오류 메시지 잔존 | 일부 처리: errorMessage nil 초기화 있음 |

