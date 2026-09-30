# 운영 DB 이관 최종 검토 — 2026-09-30

## 판정

DB SQL 이관 패키지는 적용 진행 가능. 이번 검토에서 추가 적용 차단 결함은 확인되지 않았다. 운영 이관·운영 서비스 전환 완료를 뜻하지 않는다.

## 이번에 직접 확인

- 개발 FitMatch / hnkplvyegonlhumlejst, 운영 FitMatch_PROD / aqhrupgjpmrtnystottx: ACTIVE_HEALTHY, PG17, 서울.
- 운영 앱 테이블0, auth 사용자0. ensure_rls 존재; 기존 플랫폼 객체 유지.
- 현재 개발 선정38테이블 행수/내용해시가 캡처와 일치. 이관27테이블7167행, 사용자·조사11테이블0행.
- 현재 개발 함수128개 identity/definition MD5 일치, 누락0.
- SQL57파일 SHA256 전부 일치, 파일권한0600. 가장 큰 schema단계805606바이트. MCP 원격 write의 실제 요청 크기 수용 여부는 미실행.
- 대상의 schema CREATE/public CREATE/auth.users TRIGGER·REFERENCES/auth·extensions USAGE/digest EXECUTE 확인.
- 대상 supabase_admin의 public 기본권한3종은 원본과 동일. postgres의 public 시퀀스 기본권한 차이는 마지막950단계에서 원본대로 명시 적용된다. auth/storage/기타 플랫폼 기본권한은 변경하지 않는다.
- 이전 로컬 복원은 superuser였다. 이번에는 새 로컬DB fitmatch_final_role_review에 NOSUPERUSER/BYPASSRLS 역할, 별도 소유 auth.users+TRIGGER/REFERENCES 권한으로57단계를 다시 적용하여PASS. 데이터 해시38/38일치. 로컬 서버종료.
- 함수본문에서 개발project ref 및 대표 외부호출(http/net/dblink/vault/cron) 정적검색 후보0. 동적SQL 외부의존성 부재까지 증명하는 검사는 아님.

## 남은 실행 및 한계

1. 원격적용은 NOT RUN. 즉시 적용 직전 빈대상/원본해시 재확인하고 manifest순서로 실행한다. 실패하면 다음단계를 중단하고 이미 성공한단계를 임의재실행하지 않는다.
2. 마지막950권한단계가 끝나기 전 앱/Edge를 운영으로 전환하지 않는다. 전체57단계는 하나의 트랜잭션이 아니라 각각 원자적이다.
3. 실제 원격 migration version/name/file SHA256을 적용단계마다 기록한다. 과거개발ledger 재실행금지. 운영 플랫폼 event trigger/MCP 전송제한의 실제영향은 원격실행 및postflight로확인한다.
4. SQL원문은 private /tmp 경로에 있다. 삭제되면 재추출·재검증해야 한다. 파일SHA256 명세만으로 원본을복원할수없다.
5. Edge배포/AppleAuth설정/앱endpoint전환/실제운영로그인·등록·비교는 별도이며NOT RUN. 이번검토에서개발/운영DB쓰기없음.

## 문서 정정

- DATA-SCOPE의추출·복원미완료표시는범위확정당시의과거상태였다. 최신상태와분리한다.
- 이전보고서의 JWT누락검사는 authenticated 역할의JWT없는호출거부였다. anon역할전체권한테스트로확대해석하지않는다.
