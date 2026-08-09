# Supabase 보안 경고 검토

검토일: 2026-08-06
프로젝트: `hnkplvyegonlhumlejst`

## 결론

| 경고 | 판정 심각도 | 상태 | 판단 |
|---|---|---|---|
| `public.handle_new_user()` SECURITY DEFINER 공개 실행 | 높음에 가까운 중간 | 조치 완료 | 회원가입 트리거 외 직접 RPC 실행은 불필요한 권한 상승 공격면 |
| Auth 유출 비밀번호 보호 비활성화 | 중간 | 대시보드 조치 필요 | 알려진 유출 비밀번호의 재사용을 차단하지 못함 |
| 내부 taxonomy/staging 테이블의 RLS 정책 없음 | 정보 | 현 상태 안전 | `anon/authenticated`에 schema USAGE와 DML 권한이 모두 없어 접근 불가 |
| 미사용 인덱스 | 낮음/정보 | 관찰 | 새 검증 테이블과 초기 운영 DB에서는 통계가 쌓이지 않아 바로 삭제하면 안 됨 |
| 일부 FK 인덱스 없음 | 낮음~중간(성능) | 별도 성능 작업 | 보안 취약점은 아니며 실제 쿼리 경로를 확인한 뒤 추가 필요 |

## 적용한 조치

`public.handle_new_user()`는 `auth.users`의 `on_auth_user_created` 트리거에 연결된 함수다. 트리거 연결과 `SECURITY DEFINER`, 빈 `search_path`는 유지하고 직접 실행 권한만 최소화했다.

- `PUBLIC`: EXECUTE 회수
- `anon`: EXECUTE 회수
- `authenticated`: EXECUTE 회수
- `supabase_auth_admin`: EXECUTE 유지
- `service_role`: EXECUTE 유지
- 트리거 연결: 유지 확인

적용 SQL: `supabase/sql/072_restrict_handle_new_user_execution.sql`

조치 후 Supabase Security Advisor에서 `handle_new_user` 관련 WARN 두 건이 제거된 것을 확인했다.

## RLS 경고 해석

`fitmatch_taxonomy`와 `fitmatch_staging`은 앱 클라이언트가 직접 읽는 공개 API 스키마가 아니다. 확인 결과 두 스키마 모두 `anon/authenticated`에 schema USAGE가 없고, 대상 테이블 DML 권한도 없다. 따라서 “RLS는 켜졌지만 정책 없음”은 현재 구조에서는 기본 거부 상태를 뜻하는 정보성 경고다. 경고를 없애기 위해 불필요한 허용 정책을 추가하면 오히려 보안이 약해진다.

## 수동 조치 필요

유출 비밀번호 보호는 SQL 권한이 아니라 Supabase Auth 프로젝트 설정이다. Dashboard의 Authentication 보안 설정에서 활성화한 뒤 로그인·회원가입 회귀 테스트를 수행해야 한다.

- 공식 안내: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- RLS linter 설명: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- SECURITY DEFINER linter 설명: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
