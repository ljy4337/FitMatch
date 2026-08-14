begin;
set local lock_timeout='10s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:third-corpus-provider-extensibility'));

alter table fitmatch_taxonomy.runtime_classification_rules
  drop constraint if exists runtime_classification_rules_source_code_check;
alter table fitmatch_taxonomy.runtime_classification_rules
  add constraint runtime_classification_rules_source_code_check
  check (source_code='any' or source_code ~ '^[a-z][a-z0-9_]*$');
alter table fitmatch_staging.runtime_classification_regression_cases
  drop constraint if exists runtime_classification_regression_cases_source_code_check;
alter table fitmatch_staging.runtime_classification_regression_cases
  add constraint runtime_classification_regression_cases_source_code_check
  check (source_code ~ '^[a-z][a-z0-9_]*$');

insert into fitmatch_taxonomy.runtime_classification_rules
 (rule_set_code,stage,source_code,priority,input_scope,required_category_code,match_operator,
  include_terms,output_category_code,output_detail_code,source_file,source_anchor)
values
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',95,'source_path',null,'contains_any',
  array['cut & sewn','cut and sewn'],'tops',null,'FitMatch/Services/UniqloParser.swift','mapCategory:uniqlo-cut-and-sewn'),
 ('app-hardcoded-parity-2026-08-06-v1','detail','uniqlo',107,'source_path','tops','contains_any',
  array['cut & sewn','cut and sewn'],null,'short_sleeve','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:uniqlo-cut-and-sewn')
on conflict (rule_set_code,stage,source_code,priority) do update set
 input_scope=excluded.input_scope,required_category_code=excluded.required_category_code,
 match_operator=excluded.match_operator,include_terms=excluded.include_terms,
 output_category_code=excluded.output_category_code,output_detail_code=excluded.output_detail_code,source_file=excluded.source_file,
  source_anchor=excluded.source_anchor,active=true;

update fitmatch_taxonomy.runtime_classification_rules
set include_terms=array['파자마','홈웨어','라운지','homewear','loungewear']
where rule_set_code='app-hardcoded-parity-2026-08-06-v1'
  and stage='provider_major' and source_code='uniqlo' and priority=94;

commit;
