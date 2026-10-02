# 사용자 오류보고 상품 회귀 — 2026-09-17

현재 connectDB/ae69b30 + 미커밋 소스. 시뮬레이터 미사용, 개발 DB hnkplvyegonlhumlejst 읽기 전용.
대규모 수집목록 전체가 아니라 개별 오류보고가 명확한 10상품 우선 실행.

| 사용자 입력 식별 | 현재 확인 | 검증 범위 |
|---|---|---|
| musinsa.onelink.me/PvkC/ct27zw6f | redirect 상품5328103, C, DB4사이즈 | redirect 최종 페이지/actual-size403. live parser BLOCKED |
| UNIQLO E484080-000, color07,size004,pld000 | 상세HTTP200, 색상007 chart 없음, generic000 chart8개, DB color07 8사이즈/각4실측, A | API 수신/DB SELECT PASS. Swift fallback 코드 존재, 이번 Swift 실행 NOT RUN |
| ZARA p01957601 v1=565606719 | live실측4 → parser4 | product parent 미확정, DB exact variant 조회 결과 없음; 등록/비교 NOT RUN |
| ZARA p03443415 v1=564228855 | live4→parser4, DB4, A | 원본/size label/고유ID 보존 PASS |
| ZARA p04092354 v1=564205305 | live4→parser4, DB4, A | 동일 |
| ZARA p04092360 v1=551145185 | live5→parser5, DB5, UNMAPPED | 그룹 선택 정상 설계; UI 실행 NOT RUN |
| ZARA p03166306 v1=545456321 | live3→parser3, DB3, UNMAPPED | 동일 |
| ZARA p05585470 v1=547823527 | live7→parser7, DB7, UNMAPPED | 동일 |
| ZARA p06786003 v1=549838589 | live4→parser4, DB4, B | 원본/size label/고유ID 보존 PASS |
| ZARA p04764202 v1=553627099 | live6→parser6, DB6, E | 동일 |

## 실행 구분
- 공식 ZARA size-measure-guide를 정확한 selected catentry로 새 요청:8/8 HTTP200 및 garment guide 존재.
- 현재 production ZARASizeGuideParser/SizeTokenNormalizer/stableID를 추출한 격리 실행. unrelated value models는 stand-in. audit_category는 검사 문맥이며 서버 분류 결정이 아님.
- live8 fixture: FitMatchTests/Fixtures/zara_reported_live_20260917.json. audit_case_id/selected_catentry_id를 product parent로 취급하지 않음.
- 기존 저장5상품 fixture도 재실행. 같은 상품의 반복이므로13개 고유상품이라고 합산 금지.
- DB product_comparison_group 정의 확인 후 SELECT 실행; 읽기만 하는 현재 함수이며 mutation 없음.
- HTTP 로그/원문: /tmp/fitmatch-reported-links/. 공유 redirect query에는 추적정보가 있어 최종 문서에 복사하지 않음.
- initial sandbox 네트워크 실패 후 승인된 읽기 재실행. UNIQLO generic curl HTTP2 오류 뒤 urllib1회 HTTP200.

## 재실행
```bash
python3 scripts/prepare-zara-size-replay.py
swiftc -module-cache-path /tmp/fitmatch-phase1-module-cache /tmp/zara-size-replay.swift -o /tmp/zara-reported-replay
/tmp/zara-reported-replay FitMatchTests/Fixtures/zara_reported_live_20260917.json
```

## 남은 범위
- 모든 상품의 authenticated Closet write/read-back → candidate → begin/complete → History: NOT RUN.
- 목록/상세 계산 일치: NOT RUN. 상품 API/파서 성공으로 대신하지 않음.
- 원천 live garment guide와 DB raw 개수 일치가 canonical eligibility/최종 추천 성공을 보장하지 않음.
- 무신사403은 이번 요청 환경의 관측이며 앱 결함 또는 전체 사용자 장애로 확정하지 않음.
- 새 confirmed application defect 없음; 현재 parser에서8상품 사이즈 누락 재현 안됨. 불명확 사전/정책을 추측 수정하지 않음.
