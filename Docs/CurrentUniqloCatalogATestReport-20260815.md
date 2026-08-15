# 유니클로 현재 판매 상품 전수 A테스트 보고서

- 실행일: 2026-08-15 (Asia/Seoul)
- 대상: 유니클로 한국 공식몰 MEN/WOMEN/KIDS/BABY 공개 카테고리 199페이지
- 실행 환경: 연결된 iPhone 14 Pro, iOS 26.6, FitMatch Debug production 코드 경로
- 제외 환경: Simulator, 개인 iPhone 옷장 데이터, Supabase 운영 데이터

## 결론

현재 공식몰에서 상세 페이지가 열리는 880개 상품을 대상으로 FitMatch 분류·사이즈 변환·기준 옷 유무·타 대분류 차단 흐름을 실행했다. 2,288개 A테스트 시나리오가 모두 예상 결과와 일치했다. 이번 검사 범위에서는 출시를 막는 유니클로 분류 또는 비교 결함이 남아 있지 않아 **유니클로 경로는 출시 가능(GO)** 으로 판정한다.

이 판정은 2026-08-15 당시 공식몰 노출 상품과 자동화 가능한 비교 정책을 대상으로 한다. 실제 공유 시트, 화면 문구, 네트워크 장애 복구와 사용자의 기존 옷장 데이터 마이그레이션은 별도의 실기기 수동 확인 범위다.

## 수집 결과

| 항목 | 결과 |
|---|---:|
| 공식 카테고리 노출 | 1,028건 |
| 관찰된 URL | 914개 상품 ID |
| 정규화된 상품 identity | 881개 |
| 현재 상세 페이지 정상 | 880개 |
| 공식 카테고리 잔존 404 | 1개 (`E479751-000`) |
| 원본 사이즈 행 | 5,193개 |
| FitMatch 해석 고유 사이즈 행 | 5,181개 |
| 사용할 수 있는 사이즈가 있는 상품 | 752개 |

원본과 고유 행의 차이 12개는 동일 상품·색상 안에 중복된 사이즈 표기이며 파싱 누락이 아니다. `E479751-000`은 공식 카테고리에는 남아 있지만 상세 페이지가 404를 반환해 활성 880개와 분리했다.

## 분류 결과

| FitMatch 대분류 | 상품 수 |
|---|---:|
| 상의 | 340 |
| 하의 | 108 |
| 아우터 | 95 |
| 속옷 | 98 |
| 홈웨어 | 36 |
| 레깅스 | 24 |
| 스커트 | 23 |
| 원피스 | 15 |
| 자동 분류·비교 제외/사용자 확인 | 141 |

141개는 실패로 숨기지 않았다. 양말·벨트·우산·모자·선글라스·신발 같은 비의류, 전용 비교 축이 없는 브라·바디수트·커버올, 아우터 카테고리에 섞인 수납 파우치 등을 자동 비교하지 않는 정상 차단으로 분리했다. 전 항목과 이유는 `CurrentUniqloSemanticReview.csv`에 있다.

## A테스트 결과

| 사용자 상태 | 예상 UX/로직 | 건수 | 결과 |
|---|---|---:|---:|
| 내 옷장 비어 있음 | 비교 옷 필요 안내 | 752 | 752 통과 |
| 기준 옷 없음, 호환 후보 있음 | 사용자가 비교 옷 직접 선택 | 512 | 512 통과 |
| 동일 프로필 기준 옷 있음 | 기준 옷 자동 비교 | 512 | 512 통과 |
| 다른 대분류 옷만 있음 | 잘못 비교하지 않고 차단 | 512 | 512 통과 |
| 합계 |  | 2,288 | **2,288 통과 / 0 실패** |

자동 비교 512건은 FitMatch가 실제로 자동 선택 가능한 동일 비교 프로필에서만 만들었다. 후보가 있다는 이유만으로 억지 자동 비교하지 않았으며, 기준 옷이 없는 512건은 추천 결과를 만들지 않고 수동 선택 후보만 제공하는지 확인했다.

## 검사 중 발견하여 수정한 결함

1. `니트 > 브이넥`, `니트 > 터틀넥`, `니트 > 워셔블`, GU 하위 경로처럼 마지막 카테고리가 일반 명칭인 니트가 분류 확인 상태로 빠지던 문제를 수정했다.
2. `Cut & Sewn` 하위 상의가 구조를 잃던 경계를 보완했다.
3. AIRism/HEATTECH 기능성 이름을 의류 종류로 오인하지 않도록 쇼핑몰 경로와 구조를 우선했다.
4. 일반 이너웨어 T의 canonical 분류를 사이즈 변환보다 먼저 결정해 가슴·총장 실측이 사라지던 문제를 수정했다.
5. AIRism 코튼 외출용 T 예외는 상의로 유지하고, 실제 이너웨어 T·탱크는 속옷으로 분리했다.

수정 후 활성 상품 수는 그대로 880개이고, 자동 비교 가능 검사 대상은 582개에서 610개로 증가했다. 최종 실기기 실행 로그는 `CURRENT_UNIQLO_CATALOG_SUMMARY products=880 raw_size_rows=5193 parsed_size_rows=5181 eligible=610 scenarios=2288 pass=2288 fail=0`이다.

## 증거 파일

- `Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloCatalogURLs.csv`: 현재 열리는 공식 상품 URL 전수
- `Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloCatalogUnavailableURLs.csv`: 404 공식 잔존 URL
- `Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloClassificationResults.csv`: 880개 쇼핑몰/FitMatch 분류와 사이즈 결과
- `Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloATestResults.csv`: 2,288개 사용자 상태별 판정
- `Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloSemanticReview.csv`: 자동 분류·비교 제외 141개와 사유
- `Docs/TestEvidence/CurrentUniqloCatalog-20260815/CurrentUniqloATestSummary.json`: 집계와 SHA-256
- `/tmp/FitMatchCurrentUniqloCatalog-20260815-7.xcresult`: 최종 실기기 원본 테스트 결과

## 남은 출시 전 수동 확인

자동화가 대신할 수 없는 다음 항목만 실제 앱에서 짧게 확인한다.

1. 유니클로 상품 공유 → FitMatch 진입과 URL/색상 썸네일 유지
2. 기준 옷 없음 안내에서 `등록하기`가 의도한 링크 등록 경로로 이동하는지
3. 기준 옷 있음/없음 결과 화면 문구와 뒤로 가기
4. 네트워크 끊김 후 재시도 UX

