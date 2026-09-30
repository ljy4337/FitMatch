> 보관 안내: 이 디렉터리와 기존 migrations/sql은 과거 적용·검증 자료입니다. 운영은 별도 57단계 bootstrap ledger를 사용합니다. Git에 추가됐다는 이유로 과거 migration을 운영에 재실행하지 마세요. 현재 배포 version/name 대응은 sql-bundle-manifest.json을 확인하세요. 원문 SQL/seed는 외부 임시 경로에 있으며 이 Git 자료만으로 전체 복원 가능하다는 뜻은 아닙니다. Edge 배포 완료 및 이후 앱 환경 분리는 Docs/CodexSessionHandoff.md 최신 기록을 확인하세요.

# FitMatch_PROD 덤프 준비 패키지

## 최신 상태: 운영 DB 이관 완료 — 57/57 PASS

마지막제약·RLS·트리거·권한단계까지실제적용하고read-only postflight완료. 상세결과는 [PRODUCTION-COMPLETE.md](PRODUCTION-COMPLETE.md). 아래차단/미완료표시는과거기록으로대체됨. Edge/Auth/앱endpoint전환은미진행.

## 최신: 55/57 적용, 마지막 제약·권한 단계 자동승인 차단

000~054 완료. 선정7167행/38테이블해시동일/FK38검사PASS. 900(제약·인덱스·RLS·트리거·시퀀스)와950(권한) 미적용. 사용자모두진행승인에도자동검토가구체보안스키마범위승인부족으로반복거절. 마지막2단계구체승인필요. 앱접근닫힘,운영전환불가. 최신기록은 production-apply-journal.json. 아래8/57상태는과거기록.

## 실제 운영 적용 상태: 8/57단계 적용, 자동 승인 검토 차단

000~007 적용됨(구조+seed80행). 008 무신사 draft mapping 보존 삽입이 자동 승인 검토에서 거절됨. 추가 구체 승인 전 중단. 대상 앱 접근권한은 닫혀 있고 운영전환 불가. `production-apply-journal.json`과 `sql-bundle-manifest.json`에 실제 version 기록. 000부터 재실행하지 말 것. 아래 미적용 표시는 이전 기록이다.

## 최신 상태: DB 이관 SQL 준비 완료 (2026-09-30)

이 절이 아래 과거 준비 상태를 대체한다. **운영 DB 적용은 아직 하지 않았다.**

- 57개 단계 SQL 생성 및 격리 PostgreSQL 17 전체 복원 PASS.
- 테이블38 / 함수128 / 인덱스116 / 제약275 / 트리거44 / RLS정책26 / 뷰1 / 시퀀스1.
- 선정 데이터27테이블7,167행과 나머지11테이블0행: UTC 기준38테이블 내용해시 일치.
- 128함수 정의와 실효권한 일치. NULL 기본 함수 ACL은 동등한 명시 ACL로 복원됨.
- CHECK1개는 PostgreSQL 재파싱으로 AND 괄호가 평탄화됨; 원본 정의를 그대로 실행했고 논리 변경 없음.
- 로컬 가상 사용자 트랜잭션으로 가입 트리거, 본인 프로필만 조회하는 RLS, 상품2건 runtime 확인 후 ROLLBACK. 실제 Apple 로그인/E2E 아님.
- 대상 플랫폼의 rls_auto_enable/ensure_rls는 보존. 로컬에 최소 auth fixture 사용; supabase_admin 플랫폼 기본권한은 운영 preflight에서 대조.

### 적용 파일과 순서

실제 원문 포함 SQL은 Git 밖 private `/tmp/fitmatch-production-sql-ready-v3-20260930`에 있다. 단계별 SHA256 및 적용 migration 이름은 `sql-bundle-manifest.json`, 검증 요약은 `full-restore-verification.json`.

1. 원본 선택 해시/함수 정의와 대상 프로젝트·빈 앱 테이블·플랫폼 기본권한을 READ ONLY 재확인. 변화 시 중단하고 재생성한다.
2. manifest 순서로 `000_schema_private` → seed54개 → `900_constraints_policies_triggers` → `950_access` 적용. 각 단계 트랜잭션. 마지막 권한 단계 전 공개 접근 제한. 실패 시 다음 단계 실행 금지, 자동 재실행/삭제 금지.
3. 각 원격 migration 실제 version/name과 파일 SHA256을 기록한다. 새 baseline이므로 과거 개발 migration136개를 다시 실행하지 않는다. 운영 schema/권한/행수·해시/개인자료0행 postflight 후 DB 이관 완료로 판정한다.

개발DB 변경·운영DB 쓰기·Edge 배포·앱 endpoint 전환 없음. .pgpass 불필요. Edge2개 배포, Apple Auth 설정, 실제 운영 로그인/등록/비교는 별도 운영 전환 검증이다. `/tmp` 파일이 삭제되면 추출부터 다시 해야 하며 manifest만으로 seed를 재생성할 수 없다.

## 이전 상태: MCP 이관 경로 확인

2026-09-30 후속검증에서 **.pgpass 없이 Supabase 연결 도구로 추출 가능한 경로를 실제 확인**했다. `mcp-export-snapshot.sql` 한 READ ONLY SELECT로27테이블7167행과128함수정의/메타데이터를 추출했다. 행은JSON문자열로전달하여큰정수/소수의JavaScript재해석을피했다. 기존선정해시27/27,함수정의해시128/128일치. 격리PostgreSQL17의원래컬럼타입으로7167행insert후해시27/27일치. 근거 `mcp-transfer-proof.json`.

이 로컬검사는 **데이터 타입/값 왕복검사**다. 전체 함수·constraint·RLS·trigger 복원이나 운영권한/E2E PASS가 아니다. 운영DB는여전히미변경. 대상postgres의schema/publicCREATE와auth.usersTRIGGER권한은READ ONLY확인했으나 실제원격write는미실행. 우선경로는MCP이므로사용자가비밀번호나맥을제공할필요없다. 아래.pgpass설명은기존로컬pg_dump대안에만적용한다.

실제원문은private `/tmp/fitmatch-mcp-transfer-proof-20260930` (디렉터리0700/추출파일0600)에만저장했고Git에넣지않았다. 로컬테스트서버는종료했다. SQL이관을계속하려면전체구조재현·권한·trigger·원격적용단위검증을완료해야한다. 원격production반영승인을받았다는것과검증gate통과는구분한다.

준비일: 2026-09-30. 소스 Git: `3b71f15a67e64b62c762fdfb9340ff7139a9e609`.

**후속 확정:** 이관 데이터 범위는 [DATA-SCOPE.md](DATA-SCOPE.md)와 `data-selection.json`으로 확정했다. 27테이블7,167행, 사용자·조사11테이블0행. 아래 초기19테이블 후보와 데이터응답대기 기록은 이 명세로 대체된다. 실제 export/restore는 미완료이며 기존추출기의19테이블 옵션은 최종seed가 아니다.

## 현재 완료 범위

- 원본: 개발 `FitMatch / hnkplvyegonlhumlejst`.
- 대상: 운영 `FitMatch_PROD / aqhrupgjpmrtnystottx`.
- 원본/대상 실제 구조 목록, 함수 정의 해시·권한, 회원가입 trigger 정의, migration 이력, Edge 목록을 READ ONLY로 보관했다.
- 덤프 도구: PostgreSQL 17.11 확인. PATH 기본 도구는18.4이므로 아래17 전용 경로를 사용한다.
- 추출 스크립트와 안전장치 단위검사 준비. **실제 pg_dump 아카이브는 아직 없다.** 직접 PostgreSQL 접속 인증(.pgpass/PGPASSFILE)이 설정되어 있지 않다. MCP 조회 권한과 pg_dump 연결 인증은 별개다.
- **운영 복원 준비 완료가 아니다.** 데이터 범위와 관측 근거 의존성 선정, 실제 추출, 격리 복원, 역할별 인증 검증이 남았다. 이 폴더의 SQL은 적용하지 않았다.

## 파일

| 파일 | 용도 |
|---|---|
| manifest.json | 38테이블 전체 구조 / 기준16 / catalog근거3 / 관측근거보류8 / 사용자9 / 조사2 분류 |
| inventory.sql | 원본·복원본의 구조/함수해시/권한/RLS/trigger/constraint/index/view 대조용 READ ONLY 조회 |
| source-inventory-audit.json | 준비 당시 원본 메타데이터. pg_dump 자체가 아님 |
| target-inventory-before.json | 준비 당시 운영DB 기본 객체. 복원 뒤에도 플랫폼 객체 보존 여부 대조 |
| auth-trigger-review.sql | 현재 `auth.users`의 앱 회원가입 trigger 정확한 정의. 독립 실행 승인/전체dump가 아님 |
| seed-preflight.sql | catalog 분류 이력이 auth 사용자를 참조하는지 확인하는 제한적 guard |
| remote-migration-ledger-audit.json | 원격 migration136건 감사용. 운영ledger에 그대로 INSERT하지 않음 |
| edge-functions-audit.json | 별도 배포할 product-observation/delete-account 현황 |
| ../../scripts/prepare-production-dump.py | 실제 경로는 저장소루트 `scripts/prepare-production-dump.py`. 원본 READ ONLY 추출 전용 |

## 구조 전략

먼저 38테이블·128함수 전체 구조를 보존한 원본 기준 아카이브를 준비한다. 조사2테이블/미사용후보2함수 정리는 이관 선행조건으로 삼지 않는다. 운영 산출물에서 조사2테이블을 제외하기로 결정하면 격리 복원 단계에서 제외목록과114인덱스를 검증한다. 원본DB는 지우지 않는다.

운영에는 `public.rls_auto_enable()`/`ensure_rls`가 이미 있다. `public` schema 전체를 DROP하거나 전체함수 수128에 맞추어 삭제하지 않는다. 앱객체는 동일 signature/정의/권한으로 대조하고 대상 플랫폼 객체는 별도로 보존한다.

## 데이터 전략 — 아직 확정 아님

- 정책16테이블은 현재 version/status/verified/제외 규칙 그대로 보존. `active`만 필터하거나 loading 초안을 승격하지 않는다.
- catalog.products/history/releases3개는 복구근거 후보. 현재history27건 reviewed_by는 전부NULL이며 exporter도 확인한다.
- 관측근거8테이블은 일괄제외 확정이 아니다. 자동승격 UNIQLO mapping1건의 target/peer signal2개에 연결된 상품후보2건과 최신 complete receipt후보2건을 READ ONLY 집계했다. 두 receipt 모두 actor_id_snapshot이 존재한다. 전체 유효성 조건을 통과한 최소closure와 provenance 처리 결정은 아직 미완료이며 임의NULL치환/익명화/UUID변경하지 않는다.
- 사용자9테이블의 기존행 비이관은 사용자 응답 대기. 구조는 항상 보존한다. 조사2테이블 데이터는 개발에 보존하고 기본 후보export에서는 제외한다.
- `--with-reference-data`는 **19테이블짜리 불완전한 검토용 후보**다. 관측근거가 없으므로 바로 운영에 넣지 않는다. 최종선정 후 manifest와 검사/데이터정책을 갱신하고 한 번의pg_dump로 재추출한다. 서로 다른 시각의 임시파일을 합쳐 최종dump라고 하지 않는다.

## 직접 연결 준비

1. 개발 프로젝트 Dashboard → Connect에서 Direct 또는 Session pooler 주소 확인. pooler는5432/session모드 사용. 주소를 추측하지 않는다.
2. 비밀번호는 대화나 Git/.env에 붙이지 않는다. 로컬 `~/.pgpass` 또는 별도 `PGPASSFILE`에 libpq 형식으로 설정하고 권한0600을 적용한다. 스크립트는 내용/비밀번호를 출력하지 않는다.
3. 이 패키지는 운영 연결 정보를 요구하지 않는다. 운영 주소/다른프로젝트사용자로 추출을 시도하면 거절한다.

공식 연결·이관 안내: https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore

## 실행

계획만 확인 — DB 연결 없음:

```bash
python3 scripts/prepare-production-dump.py
python3 scripts/tests/test-prepare-production-dump.py
```

개발 Direct 주소로 **구조만** 추출 — 인증설정 후, IPv6가 가능한 환경:

```bash
python3 scripts/prepare-production-dump.py --export \
  --host db.hnkplvyegonlhumlejst.supabase.co --user postgres \
  --pg-bin /usr/local/opt/postgresql@17/bin \
  --output /tmp/FitMatch-PROD-schema-candidate-20260930
```

Session pooler를 쓰면 실제 Dashboard host로 `--host`를 바꾸고 `--user postgres.hnkplvyegonlhumlejst`를 사용한다. pooler port는5432로 고정되어 있다.

19테이블 참고 데이터까지 포함하려면 **새 출력 경로**와 `--with-reference-data`를 사용한다. 별도19개dump가 아니라 스키마와 참고데이터를 하나의pg_dump snapshot으로 추출한다. 여전히 NOT_READY이다.

출력: custom archive, offline schema-review.sql, archive.toc, 정확한auth trigger, source metadata, manifest, SHA256, NOT_READY 표식. 디렉터리0700/파일0600, repo내출력/기존경로덮어쓰기 금지. 실패 산출물은 성공아카이브로 사용하지 않는다.

추출 중 schema/policy/seed 수정은 중지한다. 스크립트는 메타데이터 전후변경을 거절하지만 그검사가 DDL변경동결 또는 완전한데이터동시성검증을 대체하지 않는다. 실제데이터와schema는pg_dump 한 snapshot이며 별도메타데이터가동일snapshot이라는주장은 하지 않는다.

## 복원 순서 — 적용 전 검토용, 자동 적용 코드 없음

1. 최종 데이터명세 승인 → 원본 실제dump 추출 → checksum/TOC 확인. 권한/owner/RLS/정책을 제거하는 옵션 금지.
2. 격리된 PostgreSQL17 또는 승인된 테스트 환경에서 Supabase 역할/auth의존성을 준비한다. production 자체를 최초연습장으로 쓰지 않는다.
3. TOC를 검토해 대상에 이미 있는public schema/platform 객체만 충돌을 피하도록 처리한다. 새 플랫폼설정 전체를 source설정으로 덮지 않는다. 승인된 복원목록으로 pre-data → data → post-data의 의존순서를 유지한다. FK/트리거를 무조건 비활성화하여 오류를 숨기지 않는다.
4. 앱 함수/테이블 준비 후 `auth.users`의 앱trigger를 복원한다. auth schema나개발계정전체를 덤프범위에 추가하지 않는다. 오류즉시중단 및 가능한단일transaction을 적용한다.
5. `inventory.sql`로 포함객체별 signature/정의hash/owner/ACL/constraints/index/RLS/trigger를 대조한다. seed행수·정책버전·관측근거·실측변환·동일그룹권한·sequence 상태를 대조한다. 플랫폼기본함수1개가 더있는것은 오류가 아니다.
6. anon/인증사용자/다른사용자/서버역할별 허용·거절을 검사하고 로그인→등록→비교→History smoke를 실행한다. 구조복원성공과 E2E를 구분한다.
7. 격리검증 PASS 후 운영적용 범위/산출물hash/쓰기승인을 확정한다. 운영 사전상태 확인→복원→읽기전용postflight→Edge2개/AppleAuth/API설정→운영검증빌드 순서. 앱공개전환은 별도다.

## Git과 배포

현재 파일은 로컬 준비자료이며 commit/push하지 않았다. old migrations136건을 baseline위에 재실행하지 않는다. 최종검증한baseline에 대응하는 배포이력을 정하고 후속migration의 시작점을 문서화한다. 원격ledger136/local파일123 차이는 이패키지로 해결되었다고 주장하지 않는다.

Edge의 기존owner는 `supabase/functions/product-observation/index.ts`, `supabase/functions/delete-account/index.ts`. 별도배포하며 새 프로젝트 키/Apple 설정을 사용한다. 원본키복사/verify_jwt해제/앱endpoint변경을 이준비작업에 포함하지 않는다.
