> **최신 서버 상태: 적용 완료.** 사용자 재지시 후 슬랙스 수정안을 서버에 적용하고 읽기 검증을 마쳤다. 아래 BLOCKED 기록은 이전 상태다. [서버 적용 결과](slacks-server-applied.md).

# 출시 전 QA 수정 결과

## 범위

로컬 미커밋 작업을 보존한 상태에서 발견된 서비스 결함과 현재 정책에 뒤처진 검사를 수정했다. 기존 기준 커밋은 a68c849이며 커밋·푸시는 수행하지 않았다.

## 실제 앱 변경

- 무신사 표에서 비교 의미가 아직 매핑되지 않은 팔둘레 등의 원본 열도 보존한다. 비교용 항목으로 추정하지 않고 기존 unknownDefinition 경로로 전달한다.
- 공식 페이지에 포함된 CREMA 사이즈표를 긴 홍보 이미지보다 먼저 분석한다. 사이즈표 영역과 숫자 접미사가 명확한 OCR 후보를 사용하고 작업 취소를 확인한다.
- 명시된 쇼핑몰 옵션 식별자를 observation에 전달한다. 기존 버전형 원본 메타데이터에 선택적 필드로 보존하여 기록 재조회에서도 정확한 옵션을 확인한다. SwiftData 스키마 변경은 없고 예전 메타데이터도 읽는다.

## 서버 수정 상태: BLOCKED

대상은 기존 Supabase FitMatch hnkplvyegonlhumlejst다. 운영 환경일 가능성이 있는 동일 프로젝트로 취급했다. 길이축 필수조건 제거와 정확한 슬랙스 경로 C 매핑을 임시 로컬 PostgreSQL 17에서 검증했다. 기존 슬랙스 차단 재현, 수정 후 상품/옷장 허용, 잘못된 유형·축·audience·structure 거부 유지 및 매핑 삽입을 확인했다.

실제 apply_migration은 자동 승인 검토가 명시적 운영 프로젝트 수정 승인 부족으로 거절했다. 사용자에게 프로젝트 및 공통 검증 변경 범위를 적은 승인을 요청했다. 우회 적용하지 않았다. 읽기 재확인에서 기존 trigger hash 1eaf0cf9b69756335862218f770bb1f0와 슬랙스 매핑 0건을 확인했다. 따라서 서버의 슬랙스 차단은 아직 해결됐다고 볼 수 없다.

SQL: supabase/sql/group_only_ingestion_axes_Apply.sql. 동시 변경을 덮어쓰지 않도록 적용 전 함수 해시 검증을 추가했고 예시 상품 번호를 실제 확인한 5746364로 정정했다. 기존 서버 정의와 로컬 실행 SQL을 이 폴더에 보관했다. axis-regression.sql은 격리된 빈 로컬 DB에서만 실행하는 검증 자료다.

## 테스트 정비의 근거

가짜 서버에 현재 필수 observation 응답을 추가하고 옷장 수정 응답에 요청한 정확한 그룹을 포함했다. 서버 거부를 앱에서 성공으로 바꾸지 않았다. 둘레 원본 보존, 명시적 비교 환산, 정확한 canonical 의미, 별도 표시용 UUID, 현재 문구에 맞춰 기대를 정비했다.

폐기된 상세분류 선택·수정·초기화 화면을 요구하던 headless 검사 7개를 제거했다(목록: retired-tests.json). 대신 기존 45개 시나리오 중 해당 경로를 그룹 선택으로 갱신하고, 최신 선택 유지·서버 승인 전 권한 부여 금지·다시 불러올 때 미승인 선택 초기화를 검증한다. 서버 상세분류 계약 자체의 coordinator 검사는 유지했다. 과거 137개 시나리오/검사 수와 새 결과를 같은 집계로 취급하지 않는다.

기존 UI의 서버 없는 가짜 계정으로 등록 성공을 기대하던 검사는 상품 사실 표시와 서버 권한 없는 저장 차단으로 바꿨다. 소유자가 다른 초기 데이터 노출 차단을 확인하며, 폐기된 기준 옷 배지·상세분류 자동재사용 UI는 요구하지 않는다. 실제 인증·서버 저장 증거를 대신하지 않는다.

## 검증

- PASS: 수정 후 온보딩·최초 실행 화면 9개 검사 및 실제 링크 검사 1개, 총 10 PASS / 0 FAIL / 0 SKIP. MCP 호출은 300초 제한으로 종료됐지만 실제 Xcode 작업은 완료됐고 xcresult를 직접 읽어 확인했다(ui-strict-summary.json).
- PASS: 실제 6372903 원본 표의 사이즈명 S(090), M(095), L(100) 및 어깨·가슴둘레·팔둘레·소매·총장 15개 값 전부 대조. 6372903 35.67초, 6372893 39.61초(수정 전 157.33초/179.48초). 정확성을 확인한 최종 구현의 수치이며 중간 구현의 약 16초 수치는 사용하지 않는다. 시뮬레이터 CPU OCR 결과로 실제 아이폰 속도는 미검증이다.
- PASS: 실제 슬랙스 5746364 링크에서 9개 사이즈와 실측을 읽었다. 서버 등록 성공을 의미하지 않는다(live-repair-strict.json).
- PASS: 격리 로컬 PostgreSQL의 슬랙스 차단 재현·해제와 잘못된 값 거부 유지. 실제 Supabase 적용 BLOCKED.
- PASS: 최종 전체 FitMatchTests 778 PASS / 0 FAIL / 41 SKIP(미실행). 이 집계는 실제 MUSINSA 30개 링크를 순차 검사한 opt-in 테스트 1개를 포함한다. 30개 모두 실측 보유, 총 122개 사이즈·673개 실측. 6372903의 사이즈명/15개 값 대조 재통과. 최종 재검사 시간은 34.78초/39.14초다(full-final-summary.json, musinsa-final.json).
- PASS: 그 직전 UI 실행에서 현재 화면 감사 4개와 메인 화면 검사 5개 통과. 이후 실패했던 온보딩/최초 실행의 문구 기대를 현재 화면과 일치시켜 별도 재실행 9개 전부 통과했다. 서로 겹치는 중간 실행 수를 더하지 않는다.
- PASS: git diff --check 및 보호 스크롤 검사. 앱 변경은 원본 열 보존·공식 표 우선 분석·옵션 ID 보존을 담당하는 5개 파일이며 기존 사용자 작업을 보존했다. 테스트용 임시 로컬 PostgreSQL은 종료했다.
- 실제 Apple 로그인 및 계정별 등록·비교·저장·재조회는 BLOCKED. 아이폰 공유 시트/제스처와 iOS 17 실행은 NOT RUN.

## 재현 근거 경로

- 최종 빌드: /Users/jinyoung/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/test-products/test_sim_2026-09-15T06-15-03-008Z_pid66510_ff35db07.xctestproducts
- 전체 단위/실제 링크: /Users/jinyoung/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/result-bundles/test_sim_2026-09-15T06-20-56-857Z_pid66510_99d2f534.xcresult
- 수정 후 온보딩/최초 실행/원본 값 대조: /Users/jinyoung/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/result-bundles/test_sim_2026-09-15T06-15-03-008Z_pid66510_2e586dc9.xcresult
- 메인 화면/현재 UI 감사 통과 및 수정 전 온보딩 실패가 포함된 중간 실행: /Users/jinyoung/Library/Developer/XcodeBuildMCP/workspaces/FitMatch-26291420f5b2/result-bundles/test_sim_2026-09-15T06-07-07-149Z_pid66510_69f0ff53.xcresult

## 변경 파일

앱: FitMatch/Services/MusinsaFallbackSizeParser.swift, FitMatch/Services/FitMatchSupabaseProductResolver.swift, FitMatch/Services/FitMatchProductAuthorityPayloadBuilder.swift, FitMatch/Models/ProductMetadata.swift, FitMatch/Models/Product.swift.

서버 준비안: supabase/sql/group_only_ingestion_axes_Apply.sql(미적용). 검사: FitMatchTests/FitMatchReleaseParserRepairTests.swift 신규 및 현재 계약/정책과 불일치한 기존 단위·UI 테스트. 상세 파일 목록은 repair-changed-files.json. 문서: 본 보고서와 Docs/CodexSessionHandoff.md. 커밋/푸시는 하지 않았다.
