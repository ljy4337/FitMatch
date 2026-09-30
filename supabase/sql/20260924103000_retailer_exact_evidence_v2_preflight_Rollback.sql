-- Safe rollback for the inactive v2 preflight only. It removes functions;
-- it never changes captured source rows, canonical data, or History.

begin;
drop function if exists fitmatch_vnext.retailer_exact_evidence_v2(uuid, uuid);
drop function if exists fitmatch_vnext.retailer_exact_semantic_contract_v2(jsonb);
commit;
