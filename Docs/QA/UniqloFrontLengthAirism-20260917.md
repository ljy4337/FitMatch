# 앞기장·에어리즘 실측 보완

## 상태

- 코드 기준: connectDB / ae69b30ed37386f6361882d36bafbd972235ebd4 + 기존 미커밋 작업.
- 대상: hnkplvyegonlhumlejst / FitMatch / 사용자 지정 개발 DB.
- 수정 SQL 준비 및 격리 PostgreSQL 검증 **PASS**. 실제 연결 DB 적용 **BLOCKED**: 자동 승인 검토가 정확한 환경/변경 승인을 요구해 거절. 추가 승인 질문 대기.
- 앱 코드/사용자 옷장/History/원본 실측/비교 정책 변경 없음. commit/push 없음.

## 확인한 원인과 수정 범위

1. 현재 DB `size_chart`의 `knit-body-length-front (앞기장)`가 dresses (원피스), underwear (이너웨어), homewear (홈웨어) 3문맥에서 `back_length (뒷기장)`로 잘못 연결됨. 기존 검증된 `uniqlo.front_length.front_neck_to_hem`으로 3행 수정.
2. 어깨·일반 소매·등 중심 소매의 정확한 원문 코드는 상의/아우터에만 연결됨. 동일 의미의 기존 source/canonical을 E/F/G 문맥에 9행 연결. 새 canonical/비교 metric 추가 없음. 세트 구성품 혼합 금지와 서버 구조 검증 유지.
3. 남성 에어리즘 상의 4개 정확한 retailer category key만 F→A. 브리프/트렁크, 여성/키즈 및 상품명 추론 제외. `58510 (심리스)`에는 실제 브리프가 있어 수정 대상에서 제외함.

| 상품 | 현재 원문 경로 | 준비한 그룹 |
|---|---|---|
| E471717 AIRism메쉬크루넥T | 스포츠 유틸리티 웨어 > 이너웨어 > 에어리즘 | A (상의) |
| E482514 AIRism크루넥T | 에어리즘 > 이너웨어 상의 > 크루넥 | A (상의) |
| E482522 AIRism코튼크루넥T | 이너웨어 > 에어리즘 > 코튼 | A (상의) |
| E454311 AIRism V넥T | 이너웨어 > 에어리즘 > 에어리즘 | A (상의) |

## 원본 보존과 비교는 별개

실제 DB의 위 4상품은 32사이즈/128개의 원본 실측이 이미 남아 있다. F 문맥에서 64개만 RESOLVED (해석 성공)였음. 즉 이 사례는 raw 삭제가 아니라 연결 누락이다.

원문 `sleeve-length-cb`는 등 중심부터 소매 끝까지 잰 길이다. `sleeve_center_back_length (등 중심 소매길이)`로 해석하며 `sleeve_length (어깨 솔기 소매길이)`와 섞지 않는다. 앞기장과 뒷기장도 별개다. 4개 해석 성공은 항상 4개로 비교 점수를 계산한다는 뜻이 아니다. 비교는 기존 서버 metric/basis/policy의 교집합을 사용한다.

Swift 확인:

- `UniqloParser.makeParsedSize`, `MusinsaActualSizeAPIParser.makeParsedSize`, `ZARASizeGuideParser.parse`는 의미를 모르는 유효한 원본도 unknown (미정의) record로 보존한다.
- `fitMatchProductObservationRequest()`는 유효값/원문 label을 전송하며 category/canonical 여부로 제거하지 않는다. 유니클로 parser_code는 `size_chart`.
- `ShoppingProductViewModel.registrationPresentationMeasurementRecords`는 retailer 원문이 있으면 전체 양수 원문을 표시하는 기존 구현이다. 이 동작은 이번에 변경하지 않았다.
- 0/결측/비정상 숫자나 신체 권장표를 의류 실측으로 만들어 넣지 않는다. 전체 쇼핑몰의 모든 입력을 검증했다는 의미는 아니다.

## 검증

| 범위 | 상태 | 증거/한계 |
|---|---|---|
| 실제 DB 원본/alias/매핑/함수 조회 | PASS | 3개 오연결, F 어깨/소매 누락, 4상품 128 raw rows 확인 |
| 격리 DB 수정 전 재현 | PASS | 앞기장→뒷기장 3개, F 64/128 해석 |
| 격리 DB 수정 후 | PASS | 5문맥×6항목=30개 의미/값, F 32사이즈×4개 모두 해석 |
| 관련 회귀 | PASS | 기존 다른 alias 입력 224개 결과 불변, 다른 카테고리 526행 불변, 2회 적용시 alias 236개 유지 |
| 연결 DB 적용/적용 후 검증 | BLOCKED | 자동 승인 거절, 승인 대기 |
| 최신 쇼핑몰 API/인증된 옷장등록→비교→결과 | NOT RUN | 보관된 실제 DB 원본을 사용한 검증이며 live E2E 아님 |
| 앱 빌드/실기기 | NOT RUN | 이번 Swift 변경 없음 |

격리 검증은 실제 배포 함수 정의와 사전/원본 표본을 최소 fixture schema에 복사해 실행했다. 실제 DB의 모든 constraint/trigger/RLS 실행을 대체하지 않는다. 적용 대상 alias의 현재 trigger는 source/garment category 정합성 확인 및 updated_at 갱신뿐임을 확인했다. 첫 로컬 준비의 인코딩/정의 구분자/의존순서 오류를 수정한 후 테스트 전체 통과.

적용 전 비교 정책 hash `be5bea1f9eb7cc5c8b36242f9a391df5`, metric hash `9ee93a97d2d8192dd7492c5331d5e175`. 승인 후 Verify SQL로 재대조한다.

## 파일과 다음 작업

- `supabase/sql/uniqlo_front_length_airism_Apply.sql`: 사전 DML, drift guard, 의미 검증, 원자적 transaction.
- `supabase/sql/uniqlo_front_length_airism_Verify.sql`: 읽기 전용 적용 후 검증.
- `supabase/sql/tests/uniqlo_front_length_airism_LocalRegression.sql`: 격리 DB용 회귀, 실제 연결 DB에 실행 금지.
- 로컬 snapshot/준비/로그 `/tmp/fitmatch-uniqlo-repair/`; 개인정보/세션 제외.
- 승인되면 Apply → Verify → 데이터지원 snapshot/Excel 갱신. 기존 저장된 옷장/과거 비교 결과는 임의로 다시 쓰지 않으며, 필요한 재조회/등록 동작은 별도 확인한다.
