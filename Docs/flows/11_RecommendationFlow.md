# 11. 추천 계산 흐름

## 2026-10-12 치수 판단 변경

서버 승인 snapshot → VNextRankingEvidence 공통 항목/Decimal 계산 → VNextComparisonEngineAdapter 순위/전체 근거 보존 → 서버 v3 검증 → RecommendationCalculationSnapshot → SizeComparisonDecision → 결과·다른 사이즈·History 표시. 목록도 같은 공통 항목 기준을 사용한다.

핵심 부위가 빠지면 부분 비교와 실제 cm 차이를 표시하고 종합 점수는 숨긴다. 다른 후보에 없는 추가 승인 치수는 additionalMeasurements에 보존한다. 측정법은 접힌 상세에 표시한다. 사용자 선택·서버 권한·보호 스크롤은 그대로 유지한다.

[설계와 배포 순서](../Design/SizeDecision-20261012.md). 실제 개발·운영 DB에는 아직 적용하지 않았다.

## ACT-REC-001 자동 추천

### 시스템 처리
1. `CompareFlowSheet`에서 `sameDetailItems` 조회.
2. 같은 detailCategory가 하나라도 있으면 추천 진행.
3. `RecommendationService.recommend(product:userFits:productDetailCategory:allowsGlobalFallback:true)`.
4. `selectBasis`.
5. 각 product size × userFit 조합의 Fit Confidence 계산.
6. score 최대, 동점이면 평균 차이 작은 결과 선택.
7. `RecommendationHistory` 생성.
8. `saveUniqueHistory`.

### 기준 선택 우선순위
`RecommendationService.selectBasis`:
1. 같은 source + brand + detailCategory + 기준 옷.
2. 같은 brand + detailCategory + 기준 옷.
3. 같은 source + detailCategory + 기준 옷.
4. 같은 detailCategory + 기준 옷.
5. allowsGlobalFallback true면 `temporaryComparisonCandidates`.
6. 없으면 빈 basis.

주의: `CompareFlowSheet`가 same detail 목록만 넘기는 경우 source/brand 범위는 해당 목록 내에서만 평가된다.

## ACT-REC-002 사용자 선택 임시 비교

- `RecommendationService.recommend(product:selectedReferenceItem:)`.
- comparisonMethod: `사용자 선택 임시 비교`.
- fallbackReason 포함.
- scorePenalty 필드는 있으나 현재 Fit Confidence score에서 실제 감점 적용은 코드상 확인되지 않는다. 상태: PARTIAL.

```mermaid
flowchart TD
    A[System: Product + UserFit 후보]
    B{후보 비어 있음?}
    C[Return nil]
    D[System: selectBasis]
    E{기준 그룹 매칭?}
    F[System: 기준 후보 정렬]
    G{allowsGlobalFallback true?}
    H[System: temporaryComparisonCandidates]
    I{fallback 후보 있음?}
    J[Return nil]
    K[System: 각 size x userFit fitConfidence]
    L{비교 항목 있음?}
    M[score 0 가능]
    N[System: 최고 score 선택]
    O[Model: RecommendationHistory 생성]
    A --> B
    B -- YES --> C
    B -- NO --> D --> E
    E -- YES --> F --> K
    E -- NO --> G
    G -- NO --> J
    G -- YES --> H --> I
    I -- NO --> J
    I -- YES --> K
    K --> L
    L -- NO --> M --> N
    L -- YES --> N --> O
```

## 저장

- `CompareFlowSheet.saveUniqueHistory`는 같은 상품 기록을 삭제 후 새 기록을 insert.
- 중복 기준: sourceURL, productCode, brand+name.
- 삭제/저장 실패 UI 없음.

