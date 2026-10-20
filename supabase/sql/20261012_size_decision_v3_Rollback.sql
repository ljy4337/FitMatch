-- Use only after v3 clients stop issuing new comparisons.
-- Keep the pure validator available for audits; remove only its call.
begin;
do $rollback$
declare
 d text := pg_get_functiondef('fitmatch_vnext.complete_comparison(uuid,jsonb)'::regprocedure);
 addition text := $addition$    if p_result ->> 'engine_version' = 'fitmatch-ios-vnext-snapshot-v3' then
        recommended_evidence_count := fitmatch_vnext.validate_size_decision_v3(row_value.target_snapshot, p_result);
    end if;
$addition$;
begin
 if (length(d)-length(replace(d,addition,'')))/length(addition) <> 1 then
  raise exception 'Expected v3 completion seam missing or changed';
 end if;
 execute replace(d,addition,'');
end
$rollback$;
commit;
