# HTTP 오류 이후 저장 상태 검사

정답 근거: 사용자 A/연속8·9 및 AGENTS Persistence. 서버 저장 확인 전 로컬 성공을 표시하지 않으며 재시도는 같은 exact identity를 유지해야 한다. SQLSTATE 42501의 확정 거절과 응답 불명확 오류의 recovery 구분은 현 구현 계약 특성화다.

`FitMatchReleaseTransportFaultTests.linkedSaveHTTPFailureKeepsLocalDataAndRetriesExactWireRequest`는 실제 등록 action → 실제 DomainClient → Supabase SDK → URLSession 경계를 사용한다. URLProtocol은 모든 요청을 가로채므로 실제 서버로 전송하지 않는다.

입력은 합성 상품/선택 사이즈/observation과, 메모·실측이 있는 무관한 기존 옷1개다. offline/403/429/500/timeout/malformed/cancelled transport 각각에 대해 같은 저장을 두 번 호출한다. 두 번 모두 실패 결과여야 하며 authoritative projector와 local persist는 호출되지 않는다. 새 ModelContext에서 기존 옷1개·가슴61·메모keep만 유지되어야 한다. HTTP upsert 두 요청의 구조화한 JSON 전체와 client/product/variant/size UUID가 같아야 한다. JSON 키 순서는 비교하지 않는다.

실제 DB commit/rollback·RLS와 UI의 alert/dismiss 상태는 증명하지 않는다. cancelled transport는 실제 Task.cancel을 대신하지 않는다. 실행 결과는 Resume30Report.md에 별도 기록한다. 기존 cancellation/cleanup/원문 검사를 복제하지 않는다.

이번 실행 결과: **PASS**. 신규 7사례 전부 통과했으며 기존 15회를 포함해 transport suite는 22회 PASS다. 통합 명령 exit65의 원인은 다른 suite의 History ID 기대값 오류다. 상세는 Resume30Report.md 참조.
