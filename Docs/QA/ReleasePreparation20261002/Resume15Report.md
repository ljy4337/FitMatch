# 잔여 15%까지 재개 — DB 초기화 및 인증 차단

**부분 준비 완료: 실제 개발 DB 초기화는 자동 승인 검토에서 거부됐고 정상 사용자 인증은 아직 연결되지 않았다.**

## 수행한 내용

- QA / HEAD `086617f49cd19c8c3e2777e75efa820d7f886b5f`, 개발 `hnkplvyegonlhumlejst` 상태 ACTIVE_HEALTHY 재확인. 기존 작업 트리 보존.
- 사용자는 두 개발 계정의 데이터 초기화를 승인했다. 범위는 A/B의 활성 옷·완료 비교 기록이며 전체 개발 DB 삭제가 아니다.
- READ ONLY로 실제 FK, trigger, `soft_delete_closet_item`, `hide_comparison_history`, 완료 비교 보호 규칙을 확인했다. 활성 행은 A 0/0, B 6/9다. B의 삭제된 행 포함 전체는 옷 67/비교 38, result head 19다. 건수는 DB 행 수로 화면 카드 수를 의미하지 않는다.
- 앱의 삭제 방식과 동일한 필드 변경(삭제 시각, Closet의 is_reference=false)을 계획했다. 정확한 6/9건과 기존 데이터 보호 조건을 transaction에서 검사하며 계정·실측·결과 snapshot·기존 tombstone·다른 소유자 데이터는 보존하는 요청이었다.
- **자동 승인 검토가 관리자 SQL UPDATE를 거부했다.** 사유: 정상 사용자 권한/RLS 경로가 아니어서 기존 데이터 보호와 권한 경계를 확인할 수 없음. 실제 적용 0건. 다른 SQL/도구나 사용자 가장으로 우회하지 않았다. 범위를 명시한 재승인 질문을 사용자에게 제시했다.
- 거부 후 별도 READ ONLY로 A 0/0, B 6/9가 그대로임을 확인했다. 이 관리자 조회는 사용자 기능·RLS 검사의 성공 증거가 아니다.
- 독립 읽기 검토와 실제 Swift 소스를 확인해 이전 안내를 정정했다. Apple-only B도 정상 OAuth access/refresh session이 연결되면 기존 하네스가 사용할 수 있다. 이메일 계정 추가는 비밀번호 로그인 도우미를 쓰는 선택지일 뿐 필수 조건이 아니다.

## 실행 결과

| 검사/작업 | 결과 |
|---|---|
| 개발 환경 및 배포된 삭제 계약 READ ONLY 확인 | PASS |
| 두 계정 초기화 | BLOCKED — 자동 승인 거부, 적용 0건 |
| 거부 후 활성 데이터 불변 확인 | PASS — A 0/0, B 6/9 |
| 정상 인증 DB preflight | BLOCKED — exit 2, 요청 0, 실행 case 0 |
| 실제 사용자 CRUD/A–H/격리 | BLOCKED — 정상 세션 없음 |
| 문서 diff/보호 스크롤 | PASS |
| 새 앱 빌드/Swift 검사/실제 쇼핑몰 URL 검사 | NOT RUN — 이전 실행으로 대체 보고하지 않음 |
| 대량 full/실기기/배포/commit/push | NOT RUN |

실행한 명령:

```bash
python3 scripts/release_qa_db.py preflight --output /tmp/FitMatchResume15DBPreflight.json
```

증거: `evidence/Resume15/db-preflight.json`, `account-state.json`. 개인정보·자격값·상품별 개인 데이터는 저장하지 않았다.

## 남은 순서

1. 초기화는 자동 승인 검토를 해결하거나 정상 로그인 후 기존 사용자 삭제 경로로 수행해야 한다. 승인 사실과 실제 적용을 구분한다.
2. 정상 사용자 세션 2개를 안전하게 연결한다. UID와 아이폰 Supabase 관리자 로그인으로는 Mac에 세션이 생기지 않는다. 비밀번호·토큰을 채팅에 보내지 않는다.
3. 두 빈 계정 검증 후 실제 CRUD/격리/정리 대표 검사를 실행한다. 현재 authority를 받아 정확한 seed/3×3 방향·누락 패턴 정답을 완성하고 실제 Swift A–H 대표 검사를 수행한다.

계산 정책 결정은 이미 끝났다. 새 알고리즘/제품 결함 수정/일괄 SQL 테스트/대량 full을 새 범위로 추가하지 않는다. 데이터 초기화만으로 로그인 문제가 해결되는 것은 아니다.

마감 직전 주간 잔여량 19%. 15% 한도에는 도달하지 않았으나 위 두 차단 조건으로 새 DB 기능 검사를 시작하지 않았다.
