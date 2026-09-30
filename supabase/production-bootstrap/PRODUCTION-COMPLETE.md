# FitMatch_PROD DB 이관 완료

대상: aqhrupgjpmrtnystottx. 원본: hnkplvyegonlhumlejst. 2026-09-30.

## 적용

- 승인된57단계전부실제적용. 기존단계재실행없음. 마지막900·950은사용자의제약/RLS/트리거/권한구체승인후적용.
- 테이블38, 함수128(플랫폼rls_auto_enable별도1유지), 인덱스116, 제약275, RLS정책26, 앱/auth트리거44, 뷰1, 시퀀스1.
- 기준·분류·필수관측근거27테이블7167행. 사용자·조사11테이블0행,auth.users0. 개발DB삭제·변경없음.
- 원격migration57개version/name/fileSHA256은sql-bundle-manifest.json에기록. 원본개발migration136개를재실행하지않았다.

## 검증 PASS

- 38테이블선정행수·내용MD5동일. 전체컬럼550,테이블/뷰/시퀀스권한·RLS상태,인덱스116,정책26,트리거44,뷰정의,스키마권한원본동일.
- 함수128권한·owner·security/search_path동일. 28함수CRLF→LF로rawMD5차이있지만128개모두줄바꿈정규화후정의일치. 단일인용SQL문자열안CRLF후보0. 로직변경아님.
- CHECK1개AND괄호표현평탄화만존재(격리복원과동일), 나머지제약정의동일. 기본ACL원본동일.
- security_invoker=true유지. bigint시퀀스최댓값9223372036854775807,마지막값1169=이관최대ID.
- 초안policy loading유지/기존policy validated유지. runtime함수authenticated실행허용/anon불허. 계정자료비이관.
- 기존플랫폼rls_auto_enable해시보존/ensure_rls유지. 무효인덱스·미검증제약0.

## 범위 밖 / NOT RUN

- 운영Edge2개배포,AppleAuth설정,앱endpoint전환,실제로그인·옷장등록·비교E2E는수행하지않았다.
- 이번운영postflight는읽기전용. 사용자세션을가장하여mutation하지않았다. 로컬가상사용자검사는운영E2E증거가아니다.
- SQL원문은private /tmp/fitmatch-production-sql-ready-v3-20260930. 외부영구백업/commit/push없음. 파일삭제시재추출필요.

DB 이관 완료와 앱 운영 전환 완료를 구분한다.

## 후속: 운영 Edge 배포

2026-09-30 product-observation/delete-account 각v1 ACTIVE/verify_jwt=true. 개발·운영소스동일,인증없는호출각401확인. 인증후동작은미검증. Apple설정은대시보드로그인필요로미변경. 앱연결전환/실기기검증은사용자결정에따라보류. 상세 production-edge-auth-status.json.
