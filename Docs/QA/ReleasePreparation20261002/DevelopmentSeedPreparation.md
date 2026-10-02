# 실제 DB 비교 데이터 연결 준비

**정확한 기존 데이터 후보 확보 PASS / 사용자 권한 승인·비교 정답 BLOCKED.**

개발 `hnkplvyegonlhumlejst`만 `BEGIN READ ONLY`로 조회했다. Auth·옷장·비교 기록 조회/생성/수정/삭제는 하지 않았다. 원래 요청의 자료 준비이며 대량 기능 검사가 아니다.

## 새로 확보한 것

- 사전에 명시한 상품6개: 무신사5068731/6948481, 유니클로E484080/E465185, 자라549678665/575944393.
- PROCESSED observation81개와 정확히 연결된 variant81쌍, size행620개, 실측원본2488개. 여러 시각의 같은 상품이 중복 포함되며, 독립 상품81개 또는 테스트2488개가 아니다.
- 원본 receipt의 product·variant·size 키와 현재 DB UUID를 직접 join했다. 최신 observation/첫 사이즈를 대신 선택하지 않고 해당6상품의 조건에 맞는 수집기록을 전부 보존했다.
- 파일 `development-seed-candidates-v1.json`과 `.sha256`, 재조회 SELECT는 `development-seed-candidates-readonly.sql`.
- 이 파일은 DB에 저장된 observation의 **필요 필드 추출본**이다. 쇼핑몰 API를 방금 수집한 원문 fixture가 아니다. retailer details/structured_facts·계정/actor 필드는 포함하지 않는다. 기존56개원문·90URL과 DB 원문은 그대로다.

## 아직 확정하면 안 되는 것

현재 사용자 runtime이 승인한 sourceObservationID, 선택/대체 size, 비교그룹, canonical 개수, 공통항목/추천점수는 미확정이다. 이 파일에는 `cases`가 없으며 인증 실행 manifest로 사용할 수 없다. `authority_verified=false`, `status=BLOCKED`를 유지한다.

전용계정 인증 후 기존 `ReleaseAuthManifest` 계약으로 명시적인 정확한seed를 선정·검증한다. 최소6상품은3×3방향의 데이터 후보일 뿐, 각 방향이나 A–G가 승인된 증거가 아니다. 관리자 읽기를 정상 사용자 RLS/등록·비교 성공으로 집계하지 않는다.

## 실행 검증

```bash
python3 -m unittest discover -s scripts/tests -p test_release_qa_seed_candidates.py -v
```

**PASS 2개**, exit0. 해시/정확identity 검사와 고의오류4경우(다른size identity/승인여부조작/운영프로젝트/실행manifest로위장) 거부를 확인했다. 고의변형은 메모리 복사본에만 수행했고 원본파일은 불변이다. 기존 단일runner의 `test_release_qa*.py` 발견 패턴에 자동 포함된다. 실제 Swift/Auth/DB mutation은 실행하지 않았다.
