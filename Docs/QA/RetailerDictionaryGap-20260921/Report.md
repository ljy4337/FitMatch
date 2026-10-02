# 쇼핑몰 관측값 ↔ 현재 DB 사전 누락 감사
기준: 2026-09-21 / connectDB ac08f64a413b37cc15a1acbcf5670f496b0ca18f. Supabase hnkplvyegonlhumlejst (FitMatch). READ ONLY. 앱 코드/DB/migration 수정 없음.

## 범위와 한계
- 현재 DB: 69상품, current 원본 실측 2,212행. source 51, alias 227, mapping 48, canonical 42. 실제 조회 정책 retailer-comparison-groups-v3-seven-20260911의 category 530행.
- 저장된 공식 API capture를 normalizer로 다시 읽어 161 관측 카테고리와 703 카테고리-항목 쌍을 재생성했다. 쇼핑몰별 쌍은 무신사169/유니클로456/자라78.
- 관측 raw code/label 쌍은 무신사9/유니클로33/자라12. 원본 collection에는 비의류도 포함된다.
- 현재 raw는 제품/원본 코드·label/parser/unit별 318개 조합으로 집계하고 native context와 group context resolver 결과를 별도로 저장했다.
- 과거 엑셀 추출 목록 545행과 검토보고서를 참조했다. 원본 XLSX 첨부는 현재 검색한 첨부 디렉터리에서 찾지 못했으므로 이번에 원본 12시트를 재검사했다고 주장하지 않는다.
- 모든 과거 URL의 최신 API를 재호출한 것은 아니다. 현재 DB에 없는 상품은 보존 capture 범위의 증거다. UI/Closet 저장/비교 E2E는 NOT RUN.
- observed-measurements.csv의 REGISTERED_CONTEXT_CHECK_REQUIRED는 어디엔가 alias/mapping이 있다는 뜻이며 그 관측 의류 문맥에서 사용 가능하다는 뜻이 아니다.
- observed-categories.csv는 관측 경로 문자열의 exact-match inventory다. 44/161만 exact path가 맞지만 나머지117개를 카테고리 누락이라고 단정하지 않는다. 노출 경로와 API runtime 분류경로/ID가 다를 수 있다.

## 결론
DB 누락은 존재한다. 그러나 canonical 미등록은 원본 표시 불가의 정당한 이유가 아니다. 현재 UI에는 ZARA/알려진 코드 제한 및 canonical 우선 합치기가 있어 별도의 표시 손실 위험이 있다. DB 보강과 원본 표시/보존 수정을 분리해야 한다.

## 1. 확인된 실측 연결 누락
|대상|원본 근거|현재 결과|누락 계층|조치|
|---|---|---|---|---|
|UNIQLO AIRism shoulder-width / sleeve-length-cb|E454311/E471717/E482514/E482522 각8사이즈|native tops에서 RESOLVED, F/underwear에서 UNMAPPED. 64행|context alias 및 그룹-표준화 결합|원본 의미 보존 구조 수정. 단순 그룹 확장으로 끝내지 않음|
|MUSINSA 아우터 밑단단면|5543646, 50cm 1 current row|B/outerwear UNMAPPED|source/canonical은 있으나 outerwear alias 없음|해당 원본의 측정방법 검증 후 문맥 연결. 원본 표시는 즉시 보존 대상|
|MUSINSA 상의 허리단면|현재 source/alias 존재; 입력 probe|MAPPING_REQUIRED|musinsa.upper_waist_width... source의 canonical mapping 없음|하의 허리로 연결 금지. 정의 검증 후 상의 전용 canonical/mapping 검토|
|MUSINSA 복부단면|현재 source/alias 존재; 입력 probe|MAPPING_REQUIRED|musinsa.upper_abdomen_width... source의 canonical mapping 없음|복부 측정 위치 확인 후 별도 매핑. 현재 실제 영향 row 수를 주장하지 않음|
|UNIQLO belt-length|보존 E483340 size chart, 16.5/18cm 등|dresses UNMAPPED|해당 raw alias 및 벨트 전용 source/canonical 없음|raw-only 보존 우선. 의류 본체 길이에 연결 금지|
|UNIQLO slit-length|보존 E482285 size chart, 17.5/18cm 등|skirts UNMAPPED|해당 raw alias 및 슬릿 전용 source/canonical 없음|raw-only 보존 우선. 점수에 자동 추가하지 않음|

상기 입력 probe의 40은 resolver 경로 검증용 입력이며 실상품 관측값으로 쓰지 않는다.
MUSINSA source에 발길이도 mapping이 없으나 의류 대상과 분리했다.

## 2. 누락으로 오인하면 안 되는 항목
- ZARA zone-name-front-rise: bottoms에서 front_rise로 RESOLVED. 실제 current 6상품/45 raw행에 연결됨.
- ZARA zone-name-back-rise: back_rise와 별도 source/alias/mapping 존재. 앞밑위와 합치지 않음.
- ZARA 앞기장/등너비/위팔단면도 source/mapping이 존재한다. 등록 표시 누락을 곧 DB 미등록으로 단정하면 안 된다.
- MUSINSA 암홀/소매부리단면: tops/outerwear alias 존재. 단 실제 비교 정책 참여와 사용자 표시 여부는 별도.
- UNIQLO 목둘레/칼라높이/엉덩이둘레 source도 존재한다.
- group가 확정된 current rows 중 resolver 미해결81행 = AIRism64 + 아우터 밑단1 + legacy_* 라벨16.
  legacy_* 16행은 5328103/6158959의 이전 내부 데이터이며 새 공식 쇼핑몰 항목으로 사전에 추가하지 않는다. 삭제/수정하지 않았다.
- 원본 미등록13 code 중 belt/slit 외11개는 머리둘레/모자/안경/가방/신발 계열. 전부 의류 canonical 등록 대상이라는 주장은 잘못이다.

## 3. 실제 자동 그룹 미결정 상품
현재 products69개 중 UNMAPPED24개:
- MUSINSA7 + UNIQLO10: 현재 조회용 source_category_path/codes가 비어 있음. 입력/보존 문제와 사전 누락을 구별해야 한다. 새 카테고리 추가만으로 고쳐진다고 볼 수 없다.
- ZARA7: 정확한 product identity가 있는 official section/family/subfamily 조합도 현재 활성 정책에 0행이며 실제 product_comparison_group 결과 UNMAPPED.

|ZARA product ID|카테고리 exact key|상품|
|---|---|---|
|575944393|zara:2:83:12480|릴렉스핏 긴소매 티셔츠|
|545964886|zara:1:78:383|포켓 면 혼방 재킷|
|549177451|zara:1:74:346|드레이프 미디 원피스|
|565594458|zara:2:2795:12465|워싱 이펙트 릴렉스핏 오버셔츠|
|551126671|zara:2:2796:12474|베이직 지퍼 하이넥 스웨트셔츠|
|545450451|zara:2:82:12490|오픈워크 스트럭처 니트 폴로셔츠|
|547804819|zara:2:73:12451|루즈 크롭 핏 청바지|

정확한 저장 URL은 unmapped-products.csv에 있다. product ID와 URL v1 색상 ID는 다를 수 있다.
이7개는 자동분류 보완 후보다. 기존 설계상 UNMAPPED는 사용자 그룹 선택 경로이므로 그 자체를 등록 불가 결함이라 하지 않는다. 이름만으로 그룹을 확정하지 않는다.
ZARA 가디건은 zara-legacy:81:11272 및 KID2개 연결이 이미 있다. '자라>아우터>가디건'이라는 예시만으로 누락 확정 불가. 실제 section/family/subfamily와 입력 evidence 필요.

## 4. 기존 잘못된 연결
현재 alias snapshot에는 이전 감사에서 확인한 앞기장3/주름포함너비5/페티코트2 잘못된 연결이 남아 있다. 누락이 아니라 오매핑이다. 기존 상세 감사의 10 UUID를 참고한다. 이번에 원본 측정방법을 새로 공식 사이트에서 확인한 것은 아니다.
준비된 semantic_context_separation migration과 현재 배포 with_context 함수는 구분해야 한다. 현재 배포 함수는 여전히 group context로 원본을 재해석한다.

## 5. 앱 표시 원인
현재 HEAD:
- AddComparedProductToClosetSheet.swift:1274 registrationMeasurementRows는 ZARA + 알려진 title에 제한된 raw 추가, 일부 canonical 값 재사용.
- MeasurementResolver.swift:60 sourceDisplayRows가 있지만 등록은 위 제한 경로를 사용.
- ShoppingProductViewModel.swift:1120 부근 mergedPresentationMeasurementRecords는 runtime canonical을 우선한다.
따라서 DB에 mapping을 더 넣는 것만으로 '모르는 원본도 전부 표시' 정책을 만족하지 못한다.
원본값과 canonical projection을 분리해 표시/저장하고, 비교는 서버 승인 항목만 사용해야 한다.

## 우선순위
1. 원본 표시·저장과 canonical 해석 분리: 미등록 항목이 있어도 원본은 보이게 함.
2. AIRism context 손실 및 아우터 밑단 등 확인된 연결 누락 보완.
3. ZARA7개 공식 category identity 검증 후 자동 그룹 연결 후보 검토.
4. source_category_path 누락17상품은 재수집/ingestion 보존 경로 확인.
5. belt/slit 및 보류 항목은 raw-only 유지. 의미·비교 정책 필요성을 검증하기 전 canonical/weight 신설 금지.

## 검증
PASS: 현재 DB 사전·배포 함수 읽기, 실제 current raw resolver, 그룹 조회, 보존 원문 정규화 재실행.
NOT RUN: 신규 공식 API 일괄 재수집, 원본 XLSX 재검사, 앱 UI·옷장 persistence·최종 비교 E2E.
DB write/migration/사용자 데이터 변경/commit/push 없음.

