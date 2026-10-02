# 옷장 미등록 의류 URL 30개

확인일: 2026-09-16 (한국 시간)

- 무신사·유니클로·자라 각 10개. 현재 개발 DB `hnkplvyegonlhumlejst`의 옷장 상품 29종과 대조했고 겹치는 상품은 0개입니다.
- 각 쇼핑몰 공식 카테고리에서 후보를 찾고 상품 상세 페이지를 확인했습니다. 무신사 7119658은 웹 조회 오류 후 실제 브라우저 상세 페이지에서 확인했습니다. 자라 상세 확인에 실패한 후드 재킷 후보는 제외하고 다른 재킷으로 대체했습니다.
- 중복 기준: 무신사 상품번호, 유니클로 E상품번호(색상·사이즈 쿼리 및 suffix 변형은 별도 수량으로 세지 않음), 자라 URL 스타일번호. 자라 스타일번호는 DB internalProductID와 별개이며, 기존 옷장 canonical_url의 스타일번호와 대조했습니다.
- 상품명도 대조하여 동일 상품의 단순 색상 변형을 중복 선정하지 않았습니다. 서로 다른 쇼핑몰의 동일 실물 SKU 여부까지 교차 인증한 것은 아닙니다.
- 아래 카테고리는 수집·검토용 의류 분류입니다. 서버의 A~G 그룹 판정이나 매핑을 변경하지 않았습니다.
- 신규는 현재 옷장 미등록을 뜻합니다. 과거 테스트 이력 전체에서 처음 등장한 상품이라는 의미는 아닙니다.
- PASS: 공식 상품 페이지 확인, 10개씩 총 30개, 수집 목록 중복 0, 현재 옷장 중복 0.
- NOT RUN: 이 30개의 실측 API·앱 등록·비교 테스트. 상품 링크 수집 결과이며 등록 성공을 보장하는 목록은 아닙니다.

## 무신사 — 10개

|번호|카테고리|상품|URL|
|---|---|---|---|
|1|셔츠|덱스터 웨스턴 데님 셔츠 [BLACK]|[7035474](https://www.musinsa.com/products/7035474)|
|2|블라우스|Check frill pintuck blouse_2colors|[7119658](https://www.musinsa.com/products/7119658)|
|3|니트|플러피 브러쉬 카라 니트 [BROWN]|[7037384](https://www.musinsa.com/products/7037384)|
|4|니트|[소프트얀] 딥 브이넥 니트_SPKWG49G01|[7169307](https://www.musinsa.com/products/7169307)|
|5|티셔츠|Seoul College Address Tee_M/Grey|[7085209](https://www.musinsa.com/products/7085209)|
|6|데님 팬츠|레오파드 배색 아일렛 스트랩 포시즌 와이드 데님 팬츠 [흑청]|[7011736](https://www.musinsa.com/products/7011736)|
|7|데님 팬츠|[노미스 X 인템포무드] 빈티지 스트레이트 데님_빈티지인디고|[7024050](https://www.musinsa.com/products/7024050)|
|8|슬랙스|[AW] Santiago Slacks (Khaki Brown)|[7107117](https://www.musinsa.com/products/7107117)|
|9|스커트|프레이드 로즈 미디 스커트 (크림)|[7044828](https://www.musinsa.com/products/7044828)|
|10|재킷|[ON]스웨이드 스탠 에리 오버핏 바이커 트러커 - 2color|[6978446](https://www.musinsa.com/products/6978446)|

## 유니클로 — 10개

|번호|카테고리|상품|URL|
|---|---|---|---|
|11|긴팔 티셔츠|AIRism코튼크루넥T(긴팔)|[E465193](https://www.uniqlo.com/kr/ko/products/E465193-000/00)|
|12|반팔 티셔츠|크루넥T|[E422992](https://www.uniqlo.com/kr/ko/products/E422992-000/00)|
|13|니트|워셔블밀라노립크루넥스웨터|[E453754](https://www.uniqlo.com/kr/ko/products/E453754-000/00)|
|14|반팔 니트|워셔블밀라노립니트T(반팔)|[E481004](https://www.uniqlo.com/kr/ko/products/E481004-000/00)|
|15|셔츠|브러시드코튼셔츠|[E486610](https://www.uniqlo.com/kr/ko/products/E486610-000/00)|
|16|셔츠|드레이프셔츠|[E488801](https://www.uniqlo.com/kr/ko/products/E488801-000/00)|
|17|파카|포켓터블UV PROTECTION파카|[E469292](https://www.uniqlo.com/kr/ko/products/E469292-000/00)|
|18|재킷|해링턴재킷|[E484610](https://www.uniqlo.com/kr/ko/products/E484610-000/00)|
|19|치노 팬츠|배럴치노팬츠|[E487214](https://www.uniqlo.com/kr/ko/products/E487214-000/00)|
|20|이지 팬츠|저지이지워크팬츠|[E488739](https://www.uniqlo.com/kr/ko/products/E488739-000/00)|

## 자라 — 10개

|번호|카테고리|상품|URL|
|---|---|---|---|
|21|긴팔 티셔츠|인터록 긴소매 티셔츠|[04174639](https://www.zara.com/kr/ko/인터록-긴소매-티셔츠-p04174639.html)|
|22|반팔 티셔츠|크롭 반소매 티셔츠|[02335299](https://www.zara.com/kr/ko/크롭-반소매-티셔츠-p02335299.html)|
|23|블라우스|스웨이드 메쉬 자수 블라우스|[01008226](https://www.zara.com/kr/ko/스웨이드-메쉬-매듭-장식-자수-블라우스-p01008226.html)|
|24|셔츠|스카프 셔츠|[07970506](https://www.zara.com/kr/ko/스카프-셔츠-p07970506.html)|
|25|니트|울 브이넥 스웨터|[01509003](https://www.zara.com/kr/ko/울-브이넥-스웨터-p01509003.html)|
|26|카고 팬츠|ZW 콜렉션 카고 팬츠|[07627248](https://www.zara.com/kr/ko/zw-콜렉션-카고-팬츠-p07627248.html)|
|27|재킷|포켓 면 혼방 재킷|[05063840](https://www.zara.com/kr/ko/코튼-블렌드-포켓-재킷-p05063840.html)|
|28|원피스|나이론 드레이프 벌룬 원피스|[04772928](https://www.zara.com/kr/ko/나이론-드레이프-벌룬-원피스-p04772928.html)|
|29|원피스|플리츠 슬리브 미니 원피스|[07827777](https://www.zara.com/kr/ko/플리츠-소매-미니-원피스-p07827777.html)|
|30|재킷|페이크 레더 바이커 재킷|[04391892](https://www.zara.com/kr/ko/페이크-레더-점퍼-p04391892.html)|


