# FitMatch Docs

작성일: 2026-07-07

이 폴더는 FitMatch의 제품 방향, 개발 결정, 아키텍처, 백로그, 릴리즈 기록을 보관한다.

ChatGPT와 Codex가 프로젝트 맥락을 잃지 않도록, 기능을 수정하기 전 이 문서들을 먼저 확인한다.

## 문서 목록

### `ProductVision.md`

FitMatch의 제품 철학과 장기 비전을 설명한다.

포함 내용:

- FitMatch가 해결하는 문제
- 핵심 해결 방식
- 현재 전략
- 핵심 기능
- 장기 비전

### `Decisions.md`

확정된 기획 및 개발 결정을 기록한다.

포함 내용:

- 하단 탭 구조
- 홈 역할
- 비교 탭 방향
- 내 옷장 접근 방식
- 무신사 우선 지원 결정
- 브랜드/플랫폼 분리
- sourceType/sourceName/brandName 분리
- 추천 결과 표시 원칙

새로운 주요 결정이 생기면 이 문서에 날짜, 결정, 이유, 영향을 추가한다.

### `Backlog.md`

앞으로 개발할 작업을 우선순위별로 정리한다.

우선순위:

- P0: 핵심 흐름 완성에 필요한 즉시 작업
- P1: MVP 사용성 개선
- P2: 쇼핑몰 확장
- P3: 서비스화와 장기 확장

### `Architecture.md`

현재 앱 구조를 설명한다.

포함 내용:

- SwiftUI + SwiftData 구조
- Models / Views / ViewModels / Services 역할
- URL Parser 구조
- MusinsaParser 흐름
- RecommendationService 흐름
- Share Extension 흐름
- sourceType/sourceName/brandName 개념
- 쇼핑몰별 parser 추가 방식

### `ReleaseNote.md`

현재까지의 변경 이력을 버전 형식으로 정리한다.

현재 기준:

- `v0.1-dev`

### `FitMatchDevelopmentReport.md`

현재 실제 코드 기준 상세 개발 현황 보고서다.

포함 내용:

- 프로젝트 구조
- 구현된 기능
- 화면 목록
- SwiftData 모델
- Service
- ViewModel
- URL Parser
- 무신사 관련
- 추천 알고리즘
- Share Extension
- Git 정보
- 현재 빌드 상태

### `FitMatchProjectStatus.md`

이전 프로젝트 상태 요약 문서다.

주의:

- 일부 내용은 최신 코드와 다를 수 있다.
- 최신 기준 문서는 `FitMatchDevelopmentReport.md`를 우선한다.

### `ShareExtensionSetup.md`

Share Extension을 Xcode target으로 추가하는 방법을 설명한다.

주의:

- 현재 코드 기준 Share Extension 파일은 존재한다.
- Xcode project target 연결은 별도 확인 및 작업이 필요하다.

## 문서 사용 원칙

- 코드 수정 전 `ProductVision.md`, `Decisions.md`, `Architecture.md`를 먼저 확인한다.
- 새 기능을 만들기 전 `Backlog.md`에서 우선순위를 확인한다.
- 큰 방향 변경이 생기면 `Decisions.md`에 기록한다.
- 배포 또는 큰 기능 변경 후 `ReleaseNote.md`를 갱신한다.
- 현재 코드 상태를 다시 정리할 때는 `FitMatchDevelopmentReport.md`를 갱신한다.
