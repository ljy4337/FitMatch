# FitMatch 새 세션 인수인계

- 최종 갱신: 2026-08-07 (Asia/Seoul)
- 저장소: `/Users/jinyoung/Documents/Projects/FitMatch/FitMatch`
- 브랜치: `리뉴얼_1`
- 기준 HEAD: `5ec7fb7ee5cf97cf61de2b0e3af6611aaefb8fde` (`빌드버전 변경`)

## 1. 새 세션에서 가장 먼저 할 일

1. `AGENTS.md`와 이 문서를 끝까지 읽는다.
2. 현재 작업 트리를 보존한다. `reset`, `clean`, `stash`, `commit`, `push`를 사용자가 명시적으로 요청하지 않는 한 실행하지 않는다.
3. 다음 명령으로 현 상태만 확인한다.

```bash
cd /Users/jinyoung/Documents/Projects/FitMatch/FitMatch
git status --short
python3 scripts/review-fit-pair-candidates.py --summary
```

현재 작업 트리는 대규모 미커밋 상태다. 조사 원본과 회귀 코퍼스도 포함되어 있으므로 용량이 크다는 이유로 삭제하면 안 된다.

Supabase 작업은 사용자가 집에서 하기로 하고 보류했다. 사용자가 명시적으로 재개하기 전에는 원격 DB에 SQL을 적용하거나 보안 설정을 변경하지 않는다.

## 2. 사용자의 최종 목표

FitMatch로 들어온 무신사·유니클로 상품을 다음 순서로 안정적으로 처리하는 것이 목표다.

1. 브랜드 공식 URL/API/HTML에서 상품 정체성, 공식 카테고리, 사이즈표를 수집한다.
2. 브랜드 공식 카테고리를 우선 근거로 FitMatch 대분류·세부분류에 매핑한다.
3. 공식 카테고리만으로 길이·구조를 확정할 수 없을 때에만 상품명과 검증된 키워드를 보조 근거로 사용한다.
4. 내 옷장 기준 옷과 비교 상품이 같은 의류군·길이·구조이고 정확한 실측 코드가 호환될 때만 자동 비교한다.
5. 실측 근거가 부족하거나 의미가 다르면 높은 신뢰도를 표시하지 않고 비교 보류 또는 수동 선택으로 보낸다.
6. 현재 앱의 하드코딩 분류 동작과 DB 규칙을 동등하게 관리해, 나중에 하드코딩을 제거하고 DB 조회로 바꿔도 기존 동작이 유지되게 한다.
7. 향후 Zara, COS, H&M 등도 동일한 공급사 어댑터와 표준 분류·실측 계약에 붙일 수 있게 한다.

보존해야 하는 제품 원칙은 다음과 같다.

- Reference Garment 개념을 유지한다.
- `category`와 `detailCategory` 구조를 유지한다.
- 가슴둘레와 가슴단면, 일반 소매와 화장, 앞기장과 뒤기장을 같은 값으로 취급하지 않는다.
- 공급사가 제공하지 않은 실측값을 추정해서 만들지 않는다.
- 자동 비교가 불가능한 경우 억지로 추천하지 않는다.
- 기존 UX와 아키텍처는 사용자의 명시적 요청 없이 바꾸지 않는다.

## 3. 현재 상태 한눈에 보기

| 영역 | 현재 상태 | 해석 |
|---|---:|---|
| 전체 앱 완성도 | 약 95% | 방향성 평가이며 테스트 통과율이 아님 |
| 핵심 코드·자동검증 | 약 99% | 현재 정의된 자동 게이트는 실패 0 |
| 누적 고유 상품 분류 | 2,560건 | 무신사 1,545 + 유니클로 1,015 |
| 분류 의미 감사 | 오류 0건 | 명시적 상품 신호·유효 분류 감사 통과 |
| 실제 내 옷장–비교 상품 쌍 | 879쌍 | 무신사 699 + 유니클로 180 |
| 비교쌍 자동 무결성 감사 | 오류 0건 | 카테고리·실측 의미·산술·신뢰도 계약 통과 |
| 전체 자동 회귀 | 284개 | 279 통과, 실패 0, 실서버 전용 5 스킵 |
| 사람 독립 검수 | 0/200 | 아직 체감 핏 정확도를 확정할 수 없음 |
| 최신 Release archive | 성공 | 서명 제외 arm64 archive |
| App Store 제출 감사 | 4개 실패 | 공개 URL 2개 + 배포 서명 2개 |

중요한 해석:

- `2,560/2,560`은 현재 분류 로직이 유효한 결과를 만들고 명시적 의미 감사에서 오류가 없었다는 뜻이다. 사람 기준 분류 정확도 100%를 의미하지 않는다.
- `879/879`은 비교쌍의 구조, 측정 의미, 산술과 신뢰도 계약이 일관됐다는 뜻이다. 사용자가 느끼는 핏 만족도 100%를 의미하지 않는다.
- 과거 문서의 `915쌍`은 후속 의류군 우선순위·호환성 정제 전 수치다. 최신 기준은 `879쌍`이다.
- 더 많은 320/1,280건 상품 수집보다 200쌍 사람 검수와 실제 기기 QA가 지금 더 유의미하다.

## 4. 지금까지 완료한 작업

### 4.1 실제 상품 데이터 수집과 누적 회귀

- 첫 320건, 중복 없는 재검증 320건, 세 번째 320건, 무신사 네 번째 320건을 누적했다.
- 이후 기존 1,280건과 중복 없는 신규 1,280건을 추가했다.
  - 신규 무신사 1,037건
  - 신규 유니클로 243건
- 최종 누적 분류 코퍼스는 중복 없는 2,560건이다.
  - 무신사 1,545건
  - 유니클로 1,015건
- 상품 ID 색상 변형을 별도 상품으로 부풀리지 않았다.
- 분류 결과의 공급사 상품 ID, 상품명, 공식 카테고리 경로, FitMatch 대분류·세부분류를 JSON/CSV로 데이터화했다.
- 명시적 반팔·긴팔·민소매, 쇼트팬츠·크롭·긴바지, 가디건·레깅스·원피스 신호를 독립 감사하는 스크립트를 추가했다.

최신 분류 감사 근거:

- `Docs/Research/FitPairHumanReview-20260806/classification_semantic_audit_report.json`
- 결과: `passed`, 2,560건, 오류 0건

### 4.2 앱 분류 로직 보강

- 브랜드 공식 카테고리의 가장 구체적인 depth를 우선 사용한다.
- 공식 카테고리가 모호할 때만 상품명으로 길이·세부 의류군을 보완한다.
- 대분류, 세부분류, 의류군, 길이, 구조를 별도 축으로 유지한다.
- 반팔·긴팔·민소매·7부 상의, 쇼츠·크롭·7부·9부·긴바지, 레깅스 길이를 구분한다.
- 가디건, 후디, 스웨트셔츠, 셔츠, 티셔츠, 데님, 일반 팬츠, 레깅스, 스커트, 아우터, 레더 재킷 등의 비교 의류군을 구분한다.
- 파자마·홈웨어, 속옷, 원피스, 스커트, 유아 의류처럼 상위 경로만으로 오판하기 쉬운 사례의 우선순위를 교정했다.
- 개별 상품 ID 예외를 추가하는 대신 재사용 가능한 카테고리·의미 규칙으로 수정했다.

핵심 파일:

- `FitMatch/Models/ParsedClosetClassification.swift`
- `FitMatch/Models/ClothingCategory.swift`
- `FitMatch/Models/CanonicalComparisonProfile.swift`
- `FitMatch/Services/ComparisonProfileMatcher.swift`

### 4.3 무신사·유니클로 파서 보강

- 무신사는 actual-size API를 우선하고, 공식 응답이 없거나 유효하지 않을 때만 안전한 fallback을 사용한다.
- 공식 API에서 제공하는 `ONE SIZE`, `OS`, `1 (M)`, `블랙_S` 같은 비표준 사이즈명은 공식 근거가 있는 범위에서 허용한다.
- HTTP 성공이어도 실측 행이 없거나 값이 전부 0이면 임의 수치를 만들지 않는다.
- 유니클로 색상별 상품 ID에 사이즈표가 없으면 공통 `-000` ID를 한 번만 재조회한다.
- 유니클로의 `허리 [하의]` 둘레는 검증된 경우에만 0.5를 적용해 단면으로 변환한다.
- 의미가 다른 gathered body width, 속치마, 목둘레, 불명확한 측면 길이는 비교 근거에서 제외한다.
- 공식 호스트와 위장 도메인을 구분하고, 지원하지 않는 URL에 범용 파서를 호출하지 않도록 했다.
- 실질 구현 없이 실패하던 `GenericProductParser.swift`는 삭제했고 서비스 디스패치에서 사용하지 않는다. 일부 과거 아키텍처 문서에는 아직 이름이 남아 있어 코드가 우선이다.

핵심 파일:

- `FitMatch/Services/MusinsaActualSizeAPIParser.swift`
- `FitMatch/Services/MusinsaFallbackSizeParser.swift`
- `FitMatch/Services/MusinsaParser.swift`
- `FitMatch/Services/MusinsaProductMetadataParser.swift`
- `FitMatch/Services/MusinsaURLResolver.swift`
- `FitMatch/Services/MusinsaWebViewParser.swift`
- `FitMatch/Services/UniqloParser.swift`
- `FitMatch/Services/ProductURLParserService.swift`
- `FitMatch/Services/ParsedSizeValidator.swift`
- `FitMatch/Services/SizeTokenNormalizer.swift`

### 4.4 실제 내 옷장–비교 상품 쌍 검증

- 공급사 공식 실측을 앱 운영 파서, 검증기, 후보 선택기, 최종 비교 엔진 순서로 실행했다.
- 최종 독립 감사 대상은 879쌍이다.
  - 무신사 699쌍
  - 유니클로 180쌍
  - 상의 389, 하의 203, 아우터 284, 원피스 1, 기타 2
- 신뢰도 분포:
  - 높은 신뢰도 715
  - 충분한 비교 147
  - 최소 기준 충족 16
  - 근거 부족 1
- 근거 부족 1건은 실패를 숨긴 것이 아니라 앱 계약대로 확정 추천을 하지 않는 결과다.
- 대분류 불일치, 세부분류 불일치, 중복 쌍, 부호·절댓값 계산, 가중 점수, 커버리지, 신뢰도 라벨 계약을 독립 검사했다.
- 자동 후보는 같은 대분류, 호환 가능한 의류군·길이·구조·성별 정책과 최소 공통 실측을 충족해야 한다.
- 같은 세부분류를 기준 옷 여부나 실측 개수보다 먼저 선택하도록 했다.
- 교차 분류는 자동 매칭하지 않고, 사용자가 직접 선택한 임시 비교에서만 감점·안내와 함께 사용할 수 있다.

최신 근거:

- `Docs/Research/FitPairHumanReview-20260806/actual_fit_pairs_enriched.json`
- `Docs/Research/FitPairHumanReview-20260806/automated_integrity_report.json`
- `Docs/Research/FitPairHumanReview-20260806/fit_pair_human_review_candidates_200.json`
- `Docs/Research/FitPairHumanReview-20260806/README.md`

### 4.5 측정 의미와 추천 신뢰도

- canonical measurement code가 정확히 같은 항목만 직접 비교한다.
- 둘레와 단면, 아웃심과 인심, 일반 소매와 화장을 혼합하지 않는다.
- 비교 항목 수와 필수 항목 충족 여부에 따라 확정, 최소 근거, 근거 부족을 나눈다.
- 호환되지 않는 길이 측정은 제외하고 사용자에게 제외 사유를 설명한다.
- 근거가 부족하면 `추천 결과 아님` 또는 비교 불충분 화면을 보여 높은 신뢰도로 오인시키지 않는다.

핵심 파일:

- `FitMatch/Models/MeasurementCode.swift`
- `FitMatch/Services/MeasurementComparisonEngine.swift`
- `FitMatch/Services/MeasurementLegacyBackfillService.swift`
- `FitMatch/Services/RecommendationService.swift`
- `FitMatch/Views/CompareFlowSheet.swift`
- `FitMatch/Views/RecommendationResultView.swift`

### 4.6 공유 확장과 실제 사용자 여정

- 앱과 공유 확장 사이의 App Group URL 저장·소비 흐름을 보강했다.
- 앱 활성화와 딥링크가 연속으로 발생해 비교 요청이 사라지던 경합을 수정했다.
- 공유 URL은 비교 화면이 표시되기 전에 삭제하지 않는다.
- 공유 확장의 성공 문구를 실제 보장 범위에 맞췄다.
- 공유 확장 표시 이름을 `FitMatch`로 정리했다.
- 시뮬레이터에서 유니클로·무신사 링크 옷장 등록과 공유 URL 수신, 앱 복귀 후 분석 시작까지 확인했다.
- 실제 아이폰에서 개발 서명 빌드 설치, 앱 실행, 딥링크 수신 후 프로세스 생존까지 확인했다.
- 2026-08-07 실기기에서 `extensionContext.open`이 실패한 뒤 비활성화된 `FitMatch 앱을 직접 열어주세요` 버튼이 표시되는 회귀를 확인했다. 예전에 동작한 responder-chain 앱 열기를 다시 1순위로 복구하고 `extensionContext.open`은 fallback으로 내렸으며, 두 경로가 실패해도 `FitMatch 다시 열기` 버튼을 활성 상태로 유지하도록 수정했다.
- 공유 확장 `보러가기` 자동 전환과 두 쇼핑몰 최종 결과 화면은 실제 아이폰에서 최종 확인이 남았다.

핵심 파일과 증거:

- `FitMatch/Services/SharedURLStore.swift`
- `FitMatch/ContentView.swift`
- `FitMatchShareExtension/ShareViewController.swift`
- `FitMatchShareExtension/Info.plist`
- `FitMatchUITests/FitMatchLiveUserJourneyUITests.swift`
- `Docs/LiveUserJourneyBugReport-20260806.md`
- `Docs/TestEvidence/LiveUserJourney-Summary-20260806/`

### 4.7 개인정보·품질지표·App Store 준비

- 앱 실행, 공유 수신·소비, 파싱 시도·성공·실패, 비교 시도·결과·차단, 옷장 저장을 로컬 집계한다.
- 상품명, URL, 상품 ID, 실측값, 옷장 이름, 사용자 식별자를 집계 데이터에 저장하지 않는다.
- MY → 문의 및 지원에서 사용자가 품질 진단 정보를 직접 내보낼 수 있다.
- 자동 서버 전송은 없다. Supabase가 재개되기 전까지 로컬 저장·수동 내보내기 방식이다.
- 앱과 공유 확장에 Privacy Manifest를 추가했다.
- Release에서 상품·옷장·실측·비교 상세 진단 로그를 비활성화했다.
- 개인정보처리방침과 고객지원 화면 및 HTTPS 구성 검증을 추가했다.
- App Store archive 감사 스크립트가 번들 ID, 버전, URL scheme, arm64, Privacy Manifest, dSYM, 앱·확장 배포 서명을 확인한다.

새 파일:

- `FitMatch/Services/FitMatchMetricsRecorder.swift`
- `FitMatch/Views/ReleaseInformationView.swift`
- `FitMatch/PrivacyInfo.xcprivacy`
- `FitMatchShareExtension/PrivacyInfo.xcprivacy`
- `FitMatchTests/FitMatchMetricsRecorderTests.swift`
- `FitMatchTests/FitMatchReleaseConfigurationTests.swift`
- `scripts/audit-app-store-archive.sh`

## 5. 자동검증과 빌드 증거

### 5.1 최신 자동 회귀

- 결과 번들: `/tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult`
- 총 284개
- 통과 279개
- 실패 0개
- 스킵 5개
- 스킵 5개는 일반 회귀에서 의도적으로 제외한 실서버 전용 테스트다.

확인 명령:

```bash
xcrun xcresulttool get test-results summary \
  --path /tmp/FitMatchFullSuite-FamilyPriorityFinal-20260806.xcresult
```

### 5.2 품질 진단 추가 검증

- 단위 테스트: `/tmp/FitMatchMetricsExport-20260807.xcresult`, 5/5 통과
- UI 테스트: `/tmp/FitMatchMetricsExportUI-20260807.xcresult`, 1/1 통과

이 테스트는 최신 전체 회귀 이후 추가된 품질 진단 내보내기 변경을 별도로 검증한다. 해당 변경을 포함한 최신 Release archive도 성공했다.

### 5.3 최신 Release archive

- 경로: `/tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive`
- 상태: `ARCHIVE SUCCEEDED`
- 앱: `com.ljy4337.fitmatch`, 1.0 (4)
- 공유 확장: `com.ljy4337.fitmatch.shareextension`, 1.0 (4)
- arm64, 앱·확장 Privacy Manifest, 앱·확장 dSYM 포함
- 서명 제외 archive이므로 배포 서명 실패는 예상된 결과다.

감사 명령:

```bash
scripts/audit-app-store-archive.sh \
  /tmp/FitMatch-AppStoreUnsigned-MetricsExport-20260807.xcarchive
```

현재 실패는 정확히 4개다.

1. 공개 개인정보처리방침 HTTPS URL 없음
2. 공개 고객지원 HTTPS URL 없음
3. 앱 Apple Distribution 서명 없음
4. 공유 확장 Apple Distribution 서명 없음

`/tmp` 산출물은 재부팅이나 정리로 사라질 수 있다. 경로가 없으면 실패로 오해하지 말고 같은 소스에서 다시 실행해 새 증거를 만든다.

## 6. 만든 데이터·문서·도구 파일

### 6.1 주요 데이터 디렉터리

- `Docs/Research/NewClothingCorpus-320-20260806/`
  - 최초 320건 원본, 분류 입력·결과, 카테고리별 그룹 CSV/JSON, 차단 상품 보고
- `Docs/Research/NewClothingCorpus-320-Retest-20260806/`
  - 기존과 중복 없는 재검증 320건
- `Docs/Research/NewClothingCorpus-320-Third-20260806/`
  - 세 번째 320건과 누적 960 회귀
- `Docs/Research/MusinsaNew320Collection-20260806/`
  - 신규 무신사 320 수집 원본
- `Docs/Research/NewClothingCorpus-320-MusinsaFourth-20260806/`
  - 네 번째 320건, 누적 1,280 회귀와 무신사 실측 근거
- `Docs/Research/CategoryCorpus-live-uniqlo-1280-20260806/`
  - 유니클로 신규 후보 수집 원본
- `Docs/Research/NewClothingCorpus-1037-MusinsaFifthEighth-20260806/`
  - 신규 무신사 1,037건 분류 입력과 실측 근거
- `Docs/Research/NewClothingCorpus-243-UniqloFifth-20260806/`
  - 채택된 신규 유니클로 243건 분류 입력과 실측 근거
- `Docs/Research/NewClothingCorpus-300-UniqloFifth-20260806/`
  - 유니클로 후보 300건 조사 근거
- `Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/`
  - 신규 1,280건, 누적 2,560 Swift 분류 결과, 무신사·유니클로 실측 비교 결과
- `Docs/Research/FitPairHumanReview-20260806/`
  - 최종 879쌍, 자동 감사 결과, 사람 검수 후보 200쌍

위 디렉터리 일부는 raw HTML/API 응답 때문에 수백 MB다. 중복 상품 검증과 공식 근거 추적에 필요하므로 임의 삭제하지 않는다.

### 6.2 주요 보고 문서

- `Docs/FitMatch_무신사_유니클로_데이터_및_출시검증_리포트_20260806.md`
  - 초기부터의 장문 보고서. 앞부분 일부 수치는 과거 기준이므로 최신 수치는 이 인수인계 문서를 우선한다.
- `Docs/Research/NewClothingCorpus-1280-FifthEighth-20260806/progress_report.md`
  - 신규 1,280 및 누적 2,560 진행 상세. 이 문서의 915쌍은 후속 정제 전 수치다.
- `Docs/Research/RuntimeClassificationParity-20260806.md`
  - 앱 하드코딩과 DB 분류 규칙 동등화 설계·과거 실행 결과
- `Docs/AppStoreReadiness-20260806.md`
  - 최신 출시 준비 상태
- `Docs/AppStoreSubmissionRunbook-20260806.md`
  - URL 준비부터 서명·Validate·업로드까지 실행 순서
- `Docs/AppStorePrivacyPolicyDraft-20260806.md`
  - 실제 운영자 정보와 URL을 채워야 하는 초안
- `Docs/HomeDeviceQAChecklist.md`
  - 실제 아이폰에서 남은 검증 항목
- `Docs/Research/SupabaseSecurityReview-20260806.md`
  - 수행한 보안 검토와 대시보드 수동 조치

### 6.3 만든 자동화 스크립트

- `scripts/build-new-clothing-corpus.py`: 수집 결과를 회귀 코퍼스로 구성
- `scripts/group-new-clothing-by-fitmatch-category.py`: FitMatch 카테고리별 CSV/JSON 그룹 생성
- `scripts/validate-320-direct-logic.py`: 320건 직접 분류 검증
- `scripts/collect-new-uniqlo-retest.py`: 중복 없는 유니클로 재수집
- `scripts/collect-new-musinsa-balanced.py`: 무신사 카테고리 균형 수집
- `scripts/collect-musinsa-size-evidence.py`: 무신사 공식 실측 근거 수집
- `scripts/collect-uniqlo-size-evidence.py`: 유니클로 공식 실측 근거 수집
- `scripts/generate-regression-corpus-seed.py`: DB 회귀 seed 생성
- `scripts/generate-runtime-classification-parity-seed.py`: 런타임 규칙 동등성 seed 생성
- `scripts/generate-swift-classification-expectation-seed.py`: Swift 2,560 기대값 SQL 생성
- `scripts/build-musinsa-fit-pair-inputs.py`: 무신사 실제 비교쌍 입력 생성
- `scripts/build-uniqlo-fit-pair-inputs.py`: 유니클로 실제 비교쌍 입력 생성
- `scripts/audit-classification-semantics.py`: 2,560 분류 의미 감사
- `scripts/audit-fit-pair-integrity.py`: 879 비교쌍 독립 무결성 감사
- `scripts/build-fit-pair-human-review-set.py`: 위험도·계층 기반 사람 검수 200쌍 생성
- `scripts/review-fit-pair-candidates.py`: 사람 검수 입력·즉시 저장·재개 CLI
- `scripts/audit-app-store-archive.sh`: 제출 archive 자동 감사

### 6.4 추가한 회귀 입력과 테스트

- `FitMatchTests/LegacyMixed320ClassificationInputs.json`
- `FitMatchTests/LegacyUniqloRetest320ClassificationInputs.json`
- `FitMatchTests/LegacyUniqloThird320ClassificationInputs.json`
- `FitMatchTests/LegacyMusinsaFourth320ClassificationInputs.json`
- `FitMatchTests/Musinsa1037ClassificationInputs.json`
- `FitMatchTests/Musinsa1037FitPairInputs.json`
- `FitMatchTests/Uniqlo243ClassificationInputs.json`
- `FitMatchTests/Uniqlo243FitPairInputs.json`
- `FitMatchTests/FitMatchTests.swift`
- `FitMatchTests/LiveMusinsaValidationTests.swift`
- `FitMatchUITests/FitMatchUITests.swift`
- `FitMatchUITests/FitMatchLiveUserJourneyUITests.swift`

공유 scheme도 새로 만들었다.

- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatch.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchShareExtension.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveValidation.xcscheme`
- `FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatchLiveUserJourney.xcscheme`

일반 `FitMatch` scheme은 실서버 테스트를 스킵한다. 실서버 검증은 `FitMatchLiveValidation`, Safari 공유 전체 여정은 `FitMatchLiveUserJourney`를 명시적으로 사용한다.

## 7. 앱 하드코딩과 DB 규칙 상태

현재 앱은 DB에서 분류 규칙을 조회하지 않는다. `ParsedClosetClassification`과 관련 모델·서비스의 하드코딩 규칙이 실제 런타임 소스다.

DB 쪽에는 향후 전환을 위한 미러 구조와 평가기를 준비했다.

| 테이블 | 역할 |
|---|---|
| `fitmatch_taxonomy.runtime_rule_sets` | 앱 소스 체크섬, 규칙 버전, 실행 순서 |
| `fitmatch_taxonomy.runtime_classification_rules` | 공급사·단계·입력 범위·키워드·출력 매핑 |
| `fitmatch_staging.runtime_classification_regression_cases` | 현재 앱 기대 결과 |
| `fitmatch_staging.runtime_classification_parity_runs` | 일치·불일치·체크섬 이력 |

로컬 SQL:

- `supabase/sql/016_...`~`071_...`: 런타임 분류 미러, 독립 평가기, 코퍼스 seed, 2,560 Swift 기대값, 공급사 우선순위 정렬
- `supabase/sql/072_restrict_handle_new_user_execution.sql`: `handle_new_user()`의 불필요한 공개 실행 권한 회수

확인된 과거 상태:

- 당시 Swift↔DB 분류 category/detail은 2,560/2,560 일치했다.
- 이후 자동 비교 의류군·세부분류 호환 정책을 더 정제해 최종 비교쌍이 879개가 됐다.
- 이 최종 비교 호환 정책은 원격 DB에 미러링·검증했다고 간주하면 안 된다.
- `Docs/Research/SupabaseSecurityReview-20260806.md`에는 072 조치가 원격 적용되고 관련 Advisor 경고가 제거됐다고 기록돼 있다.
- 유출 비밀번호 보호는 Supabase Dashboard에서 사용자가 직접 활성화한 뒤 Auth 회귀가 필요하다.
- taxonomy/staging 스키마는 앱 클라이언트 공개용이 아니며 `anon`, `authenticated` 접근을 허용하지 않는 기본 거부 구조다.

주의:

- 로컬 SQL에 `038_runtime_musinsa_1037_seed_chunk_5.sql`과 `038_runtime_uniqlo_243_seed.sql`이라는 동일 번호 파일이 둘 있다. 자동 일괄 적용 전에 원격 migration ledger와 실제 실행 순서를 반드시 대조한다.
- 현재 원격 DB가 로컬 SQL 전체와 동일하다고 추정하지 않는다.
- DB 런타임 전환 전에는 현재 Swift 결과와 DB 평가 결과를 같은 고정 코퍼스에서 건별 비교하고, 한 건이라도 다르면 하드코딩 제거를 차단한다.
- 앱에서 DB를 직접 읽게 할 때는 읽기 전용 API 경계, 버전 고정, 캐시, timeout, 오프라인 fallback, RLS/권한을 별도로 설계한다.

## 8. 현재 작업 트리 상태

2026-08-07 점검 당시:

- tracked 수정: 48개
- tracked 삭제: 1개 (`FitMatch/Services/GenericProductParser.swift`)
- untracked 경로: 111개
- tracked diff: 49개 파일, 약 3,993줄 추가 / 722줄 삭제
- commit/push 없음

변경 범위는 모델, 파서, 비교 엔진, 공유 확장, 화면, 테스트, 문서, 조사 데이터, Supabase SQL 전반에 걸쳐 있다. 새 세션에서 일부만 보고 “나머지는 불필요하다”고 삭제하지 않는다.

보호 파일:

- `FitMatch/Components/TabBarScrollVisibilityModifier.swift`는 현재 diff가 없다.
- Swift modifier 호출부에도 추가·삭제 diff가 없다.
- 전체 diff grep에는 `Docs/CurrentSprint.md`의 설명 문장 하나가 잡히지만 Swift 호출부 변경은 아니다.
- 보호 파일이나 `hidesBottomTabBarOnScroll`, `tracksTabBarVisibilityOnScroll`, `hidesTopChromeOnScroll` 호출부는 사용자가 파일과 스크롤 동작을 명시적으로 승인하지 않는 한 수정하지 않는다.

현재 Release archive에서 보호 파일 관련 Swift actor-isolation 경고 4개가 있었지만 빌드·archive를 막지 않는다. 경고 제거를 이유로 보호 파일을 수정하면 안 된다.

## 9. 다음에 해야 할 일

### P0 — 사람 독립 검수 200쌍

현재 가장 먼저 할 일이다.

```bash
python3 scripts/review-fit-pair-candidates.py --summary
python3 scripts/review-fit-pair-candidates.py --reviewer "검수자 이름"
```

- 일부만 진행할 때는 `--limit 20`을 붙인다.
- 각 판정은 즉시 JSON에 저장되므로 중단 후 재개할 수 있다.
- 검수 항목은 카테고리 호환, 측정 의미, 차이 방향, 신뢰도 라벨, 전체 결과 수용 가능성이다.
- `category_compatibility`, `measurement_semantics_correct`, `signed_differences_correct`의 오류 허용치는 0건이다.
- 높은 신뢰도 표본의 `reliability_label_appropriate` 오류 허용치도 0건이다.
- 오류가 나오면 해당 규칙과 같은 계층 전체를 수정하고 879쌍 감사와 영향 범위 회귀를 다시 실행한다.
- 검수 완료 전에는 후보셋을 골드셋 또는 정확도 수치로 부르지 않는다.

예상 시간: 오류가 없으면 약 1~2시간. 오류가 있으면 규칙 수정·재검증 시간이 추가된다.

### P0 — 실제 아이폰 QA

`Docs/HomeDeviceQAChecklist.md`를 실제 기기에서 수행한다.

필수 항목:

- 기존 데이터가 앱 업데이트 후 유지되는지 확인
- 옷장 등록·수정·삭제와 기준 옷 교체
- 무신사·유니클로 URL 비교 완료
- Safari와 무신사 앱의 공유 확장 왕복
- 공유 확장 `보러가기` 후 FitMatch 자동 전환
- 앱 실행 중·백그라운드·완전 종료 상태의 공유 비교
- 네트워크 단절 안내와 복구 후 재시도
- 분석 취소, 빠른 연속 요청, 중복 기록 방지
- 하단 바운스·감속 중 헤더/탭바 스크롤 동작

예상 시간: 30~60분. 실패가 있으면 화면 녹화, URL, 시간, 기기·OS를 기록한다.

### P0 — App Store 외부 입력과 서명

사용자에게 필요한 입력:

- 실제 개인정보처리방침 HTTPS URL
- 실제 고객지원 HTTPS URL
- Apple Distribution 인증서와 App Store 배포 프로파일

URL을 받으면 `FitMatch/Info.plist`의 다음 빈 값을 채운다.

- `FitMatchPrivacyPolicyURL`
- `FitMatchSupportURL`

그 다음 Apple Distribution으로 앱과 공유 확장을 서명한 archive를 만들고 다음을 실행한다.

```bash
scripts/audit-app-store-archive.sh /path/to/FitMatch.xcarchive
```

`RESULT: passed` 확인 후 Organizer의 `Validate App`, 업로드, TestFlight 실기기 최종 검증 순으로 진행한다.

예상 시간: 공개 URL과 Apple 계정·프로파일이 준비돼 있으면 20~40분. URL 호스팅 준비 시간은 별도다.

### P1 — 출시 제품 결정

- 비교 화면의 ZARA 버튼은 현재 `준비중`이다.
- 앱의 추천 영역도 일부 로드맵/준비중 인상을 줄 수 있으므로 1.0에서 유지할지 숨길지 사용자가 결정해야 한다.
- 이는 기술적으로 임의 결정하지 않는다. UX 변경 전에 사용자 승인을 받는다.

### 보류 — Supabase

- 사용자가 재개할 때만 원격 상태를 먼저 읽기 전용으로 감사한다.
- 로컬 016~072를 무조건 재적용하지 않는다.
- 현재 Swift 분류 결과, DB 평가기, 최종 자동 비교 호환 규칙의 차이를 먼저 확인한다.
- 중앙 품질지표 전송을 추가한다면 전송 데이터, 보존기간, 동의, 개인정보처리방침, App Store Privacy 답변을 함께 바꾼다.

## 10. 더 이상 반복하지 않아도 되는 작업

- 특별한 신규 결함이나 신규 공급사 계약 검증이 없는 한 320개씩 무한 수집하지 않는다.
- 자동 감사 통과 수를 사람 정확도 100%라고 표현하지 않는다.
- 과거 242/248/265/273 테스트 수를 최신 전체 회귀 수로 보고하지 않는다. 최신 전체 회귀는 284개 기준이다.
- 과거 915쌍을 최신 비교쌍 수로 보고하지 않는다. 최신은 879쌍이다.
- `GenericProductParser`를 복구해 지원하지 않는 URL을 억지로 파싱하지 않는다.
- 원본 실측이 없는 상품에 임의 치수를 생성하지 않는다.
- DB 전환이 끝나기 전에 앱 하드코딩을 제거하지 않는다.

## 11. 출시 완료 정의

다음이 모두 충족돼야 1.0 출시 준비 완료로 본다.

- 전체 자동 회귀 실패 0
- 분류 의미 감사 오류 0
- 실제 비교쌍 독립 무결성 오류 0
- 200쌍 사람 검수 완료 및 중대 의미 오류 0
- 실제 아이폰 핵심 동선 전 항목 통과
- 공개 개인정보처리방침·고객지원 URL 실제 열림 확인
- 앱과 공유 확장 Apple Distribution 서명
- archive 감사 `RESULT: passed`
- App Store `Validate App` 통과
- TestFlight 신규 설치·업데이트·공유 확장·비교 재검증 통과

코드가 이후 변경되면 변경 영향 범위의 타깃 회귀를 실행하고, 출시 archive 직전에는 전체 회귀와 archive 감사를 다시 실행한다.

## 12. 작업 종료 전 필수 안전 확인

모든 새 세션은 작업 종료 전에 다음을 실행한다.

```bash
git diff --check
git diff -- FitMatch/Components/TabBarScrollVisibilityModifier.swift
git diff -- '*.swift' | grep -E \
  "hidesBottomTabBarOnScroll|tracksTabBarVisibilityOnScroll|hidesTopChromeOnScroll"
```

사용자 승인 없는 보호 파일·Swift modifier 호출부 변경이 없어야 한다. 문서 설명 문장이 전체 diff grep에 잡히는 것은 Swift 호출부 변경과 구분한다.
