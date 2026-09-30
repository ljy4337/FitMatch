-- Read-only post-apply verification for the inactive retailer-exact v2 helper.
-- This does not activate any public candidate/authorize/begin contract.

select to_regprocedure(
    'fitmatch_vnext.retailer_exact_evidence_v2(uuid,uuid)'
) is not null as retailer_exact_v2_exists;

select has_function_privilege(
    'authenticated',
    'fitmatch_vnext.retailer_exact_evidence_v2(uuid,uuid)',
    'EXECUTE'
) as authenticated_can_discover_v2_evidence,
has_function_privilege(
    'anon',
    'fitmatch_vnext.retailer_exact_evidence_v2(uuid,uuid)',
    'EXECUTE'
) as anon_cannot_discover_v2_evidence;

-- Existing live owners must remain canonical-only until a separate activation
-- migration explicitly replaces their contracts.
select position(
    'retailer_exact_evidence_v2' in pg_get_functiondef(
        'fitmatch_vnext.begin_comparison(jsonb)'::regprocedure
    )
) = 0 as begin_remains_unactivated,
position(
    'retailer_exact_evidence_v2' in pg_get_functiondef(
        'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb)'::regprocedure
    )
) = 0 as authorization_remains_unactivated;
