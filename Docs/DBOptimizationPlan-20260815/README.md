# FitMatch DB 최적화 SQL 실행 순서

Supabase SQL Editor에서 파일 단위로 실행한다. `40`은 기본 잠금 상태이며, `00`, `10`, `20`, `90` 결과가 정상일 때만 별도 승인 후 잠금을 해제한다.

1. `00_preflight_read_only.sql.txt` — 변경 없는 현황/안전 검사
2. `10_core_release_and_views.sql.txt` — 교정 릴리스 활성화, 활성 릴리스 전용 뷰, 필수 인덱스
3. `20_product_mapping_links.sql.txt` — 유니클로 880건과 릴리스 매핑의 FK 연결
4. `90_postflight_read_only.sql.txt` — 결과 검증
5. `30_archive_legacy.sql.txt` — 삭제 전 레거시 데이터 보관(선택)
6. `40_destructive_cleanup_LOCKED.sql.txt` — 파괴적 정리. 기본 실행 불가
7. `91_rollback_before_cleanup.sql.txt` — `40` 실행 전 `10`/`20`만 되돌릴 때 사용

중요:

- 각 파일 실행 결과를 저장한다.
- 오류가 나오면 다음 파일을 실행하지 않는다.
- `40`은 현재 앱의 DB 사용 계약을 확정하기 전에는 실행하지 않는다.
- `VACUUM FULL`, `DROP SCHEMA ... CASCADE`, 사용자 데이터 삭제는 포함하지 않는다.

