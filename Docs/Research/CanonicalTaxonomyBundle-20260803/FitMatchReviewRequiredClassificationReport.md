# Review-required classification proposal

- Input: 894
- Proposed confirmed: 242
- Proposed rejected: 44
- Product fallback retained: 608
- Proposal SHA-256: 1e3e31c248f9d28ebea1c5cbb32d4f0a4fa00830d17f094caa92cb8a31f8d59b
- Runtime bundle modified: no

## Family counts

```json
{
  "casual_pants": 53,
  "blouson": 30,
  "jacket": 18,
  "blazer": 13,
  "puffer_jacket": 11,
  "tshirt": 9,
  "dress": 9,
  "windbreaker": 8,
  "outer_vest": 8,
  "underwear_bottom": 7,
  "polo_shirt": 6,
  "sweat_jogger_pants": 6,
  "knit_sweater": 6,
  "base_layer_top": 6,
  "leggings": 6,
  "coat": 5,
  "shirt_blouse": 5,
  "fleece_jacket": 5,
  "sweatshirt": 5,
  "leather_jacket": 4,
  "denim_pants": 4,
  "mouton": 3,
  "skirt": 3,
  "puffer_vest": 3,
  "anorak": 2,
  "cardigan": 2,
  "slacks_trousers": 2,
  "tank_top": 2,
  "bra": 1
}
```

## Confirmed examples

- musinsa `002001`: 아우터 > 블루종/MA-1 → blouson
- musinsa `002002`: 아우터 > 레더/라이더스 재킷 → leather_jacket
- musinsa `002004`: 아우터 > 스타디움 재킷 → blouson
- musinsa `002006`: 아우터 > 나일론/코치 재킷 → windbreaker
- musinsa `002014`: 아우터 > 사파리/헌팅 재킷 → jacket
- musinsa `002018`: 아우터 > 트레이닝 재킷 → jacket
- musinsa `017018001`: 스포츠/레저 > 아우터 > 베스트 → outer_vest
- musinsa `017018003`: 스포츠/레저 > 아우터 > 나일론/코치 재킷 → windbreaker
- musinsa `017018006`: 스포츠/레저 > 아우터 > 스타디움 재킷 → blouson
- musinsa `017018008`: 스포츠/레저 > 아우터 > 트레이닝 재킷 → jacket
- musinsa `017018011`: 스포츠/레저 > 아우터 > 레인코트 → coat
- musinsa `017018013`: 스포츠/레저 > 아우터 > 롱 패딩/롱 헤비 아우터 → puffer_jacket
- musinsa `017018014`: 스포츠/레저 > 아우터 > 숏 패딩/숏 헤비 아우터 → puffer_jacket
- musinsa `017018015`: 스포츠/레저 > 아우터 > 하프 패딩/하프 헤비 아우터 → puffer_jacket
- musinsa `105001001004`: 부티크 > 의류 > 상의 > 셔츠/블라우스 → shirt_blouse
- musinsa `105001001005`: 부티크 > 의류 > 상의 > 피케/카라 티셔츠 → polo_shirt
- musinsa `105001002002`: 부티크 > 의류 > 아우터 > 블루종/MA-1 → blouson
- musinsa `105001002004`: 부티크 > 의류 > 아우터 > 무스탕/퍼 → mouton
- musinsa `105001002005`: 부티크 > 의류 > 아우터 > 슈트/블레이저 재킷 → blazer
- musinsa `105001002007`: 부티크 > 의류 > 아우터 > 플리스 → fleece_jacket

## Rejected examples

- musinsa `101007`: 소품 > 벨트
- musinsa `101008`: 소품 > 머플러
- musinsa `102002001002`: 디지털/라이프 > 가구/인테리어 > 가구 > 드레스룸가구
- musinsa `102005001002`: 디지털/라이프 > 반려동물 > 반려동물 의류 > 티셔츠
- musinsa `102005001009`: 디지털/라이프 > 반려동물 > 반려동물 의류 > 레인코트
- musinsa `104005002`: 뷰티 > 프레그런스 > 드레스퍼퓸
- musinsa `105004004001`: 부티크 > 악세서리 > 쥬얼리 > 팔찌
- musinsa `105004004002`: 부티크 > 악세서리 > 쥬얼리 > 반지
- musinsa `105004004003`: 부티크 > 악세서리 > 쥬얼리 > 목걸이/펜던트
- musinsa `105004004004`: 부티크 > 악세서리 > 쥬얼리 > 귀걸이
- musinsa `105005002002`: 부티크 > 라이프 스타일 > 테이블웨어 > 소스볼/찬기
- musinsa `105005002003`: 부티크 > 라이프 스타일 > 테이블웨어 > 샐러드볼/다용도볼
- musinsa `105005002004`: 부티크 > 라이프 스타일 > 테이블웨어 > 트레이/쟁반
- musinsa `105005002006`: 부티크 > 라이프 스타일 > 테이블웨어 > 유리컵
- musinsa `105005002007`: 부티크 > 라이프 스타일 > 테이블웨어 > 머그컵/찻잔
- musinsa `105005002008`: 부티크 > 라이프 스타일 > 테이블웨어 > 텀블러
- musinsa `105005003002`: 부티크 > 라이프 스타일 > 키친웨어 > 수저/커트러리
- musinsa `105005003008`: 부티크 > 라이프 스타일 > 키친웨어 > 기타 키친웨어
- musinsa `105005004001`: 부티크 > 라이프 스타일 > 텍스타일 > 러그/카페트
- musinsa `105005004003`: 부티크 > 라이프 스타일 > 텍스타일 > 쿠션/방석

## Product fallback examples

- musinsa `001008`: 상의 > 기타 상의
- musinsa `002015`: 아우터 > 기타 아우터
- musinsa `002017`: 아우터 > 트러커 재킷
- musinsa `003006`: 바지 > 기타 하의
- musinsa `017018002`: 스포츠/레저 > 아우터 > 기타 점퍼/재킷
- musinsa `017018017`: 스포츠/레저 > 아우터 > 유니폼
- musinsa `105001001009`: 부티크 > 의류 > 상의 > 기타 상의
- musinsa `105001002010`: 부티크 > 의류 > 아우터 > 기타 아우터
- musinsa `105001003009`: 부티크 > 의류 > 하의 > 기타 바지
- musinsa `105001006007`: 부티크 > 의류 > 속옷/홈웨어 > 잠옷
- musinsa `106004007`: 키즈 > 상의 > 기타 상의
- musinsa `106005004`: 키즈 > 아우터 > 점퍼/재킷
- musinsa `106005005`: 키즈 > 아우터 > 기타 아우터
- musinsa `106006009`: 키즈 > 바지 > 기타 바지
- musinsa `106009002`: 키즈 > 12개월 이하 > 기타
- musinsa `107001001009`: 아울렛 > 의류 > 상의 > 스포츠 상의
- musinsa `107001001010`: 아울렛 > 의류 > 상의 > 기타 상의
- musinsa `107001002008`: 아울렛 > 의류 > 아우터 > 겨울 기타 코트
- musinsa `107001002012`: 아울렛 > 의류 > 아우터 > 기타 아우터
- musinsa `107001002014`: 아울렛 > 의류 > 아우터 > 트러커 재킷
