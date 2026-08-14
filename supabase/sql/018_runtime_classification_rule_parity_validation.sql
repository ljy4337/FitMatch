begin;
set local statement_timeout = '60s';

do $$
declare
  v_rules integer;
  v_cases integer;
  v_duplicates integer;
  v_latest fitmatch_staging.runtime_classification_parity_runs%rowtype;
begin
  select count(*) into v_rules
  from fitmatch_taxonomy.runtime_classification_rules
  where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1' and active;

  select count(*) into v_cases
  from fitmatch_staging.runtime_classification_regression_cases
  where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1';

  select count(*) into v_duplicates
  from (
    select source_code, external_product_id
    from fitmatch_staging.runtime_classification_regression_cases
    where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1'
    group by 1, 2 having count(*) > 1
  ) duplicated;

  select * into v_latest
  from fitmatch_staging.runtime_classification_parity_runs
  where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1'
  order by validated_at desc limit 1;

  if v_rules < 50 then raise exception 'Runtime rule mirror is incomplete: % rules', v_rules; end if;
  if v_cases <> 640 then raise exception 'Regression corpus must contain 640 rows, got %', v_cases; end if;
  if v_duplicates <> 0 then raise exception 'Regression corpus contains % duplicate products', v_duplicates; end if;
  if v_latest.id is null or not v_latest.passed or v_latest.matched_count <> 640 then
    raise exception 'Latest parity run did not pass all 640 cases: %', to_jsonb(v_latest);
  end if;
end $$;

select jsonb_build_object(
  'rule_set', rs.code,
  'status', rs.status,
  'active_rule_count', (select count(*) from fitmatch_taxonomy.runtime_classification_rules r where r.rule_set_code = rs.code and r.active),
  'regression_case_count', (select count(*) from fitmatch_staging.runtime_classification_regression_cases c where c.rule_set_code = rs.code),
  'latest_parity', (select to_jsonb(p) from fitmatch_staging.runtime_classification_parity_runs p where p.rule_set_code = rs.code order by p.validated_at desc limit 1),
  'validation_passed', true
) result
from fitmatch_taxonomy.runtime_rule_sets rs
where rs.code = 'app-hardcoded-parity-2026-08-06-v1';

rollback;
