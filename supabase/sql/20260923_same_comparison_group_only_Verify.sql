-- Read-only verification for 20260923110000_same_comparison_group_only.sql.
-- Run after the migration against the intended environment.
with functions(signature, required_fragment, forbidden_fragment) as (
  values
    (
      'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)',
      'Same FitMatch comparison group is required before policy evidence is evaluated.',
      'Explicit cross-group choice is evaluated by common canonical evidence below.'
    ),
    (
      'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)',
      'is distinct from effective_value->>''comparison_group_code'' then',
      'if not coalesce(p_manual_explicit, false) and'
    ),
    (
      'fitmatch_vnext.find_reference_candidates(uuid,uuid)',
      'elsif closet_group_code is distinct from target_group_code then',
      '다른 그룹의 옷도 공통 실측으로 직접 선택해 비교할 수 있습니다.'
    ),
    (
      'fitmatch_vnext.find_reference_candidates(uuid,uuid,text)',
      'if closet_group->>''group_code'' is distinct from target_group_code then',
      'SESSION_GROUP_WITH_EXPLICIT_CROSS_GROUP'
    )
)
select
  signature,
  position(required_fragment in definition) > 0 as required_group_gate_present,
  position(forbidden_fragment in definition) = 0 as cross_group_bypass_absent
from functions
cross join lateral (
  select replace(pg_get_functiondef(signature::regprocedure), E'\r\n', E'\n') as definition
) as inspected;

-- Functional checks require an authenticated disposable fixture containing
-- same-group, cross-group, no-common-measurement, and no-Closet cases. The
-- companion regression file is:
-- supabase/sql/tests/same_comparison_group_only_Regression.sql
