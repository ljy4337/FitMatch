begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-category-first-corrections'));

-- Provider-major classification must use the provider category, not words in the product name.
update fitmatch_taxonomy.runtime_classification_rules
set input_scope = 'source_path'
where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1'
  and stage = 'provider_major';

-- Special garment families mirror ParsedClosetClassification's recognized source-family search.
update fitmatch_taxonomy.runtime_classification_rules set input_scope='source_path'
where rule_set_code='app-hardcoded-parity-2026-08-06-v1' and stage='special_category'
  and priority in (10,30,40,50);
update fitmatch_taxonomy.runtime_classification_rules set input_scope='product_name'
where rule_set_code='app-hardcoded-parity-2026-08-06-v1' and stage='special_category' and priority=20;

insert into fitmatch_taxonomy.runtime_classification_rules
 (rule_set_code,stage,source_code,priority,input_scope,required_category_code,match_operator,
  include_terms,output_category_code,output_detail_code,source_file,source_anchor)
values
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',94,'source_path',null,'contains_any',array['파자마','홈웨어'],'homewear',null,'FitMatch/Services/UniqloParser.swift','mapCategory:homewear'),
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',701,'source_path','skirts','always',array[]::text[],null,'skirt','FitMatch/Models/ParsedClosetClassification.swift','resolve:skirt'),
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',702,'source_path','dresses','always',array[]::text[],null,'one_piece','FitMatch/Models/ParsedClosetClassification.swift','resolve:dress'),
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',703,'source_path','homewear','always',array[]::text[],null,'loungewear','FitMatch/Models/ParsedClosetClassification.swift','resolve:homewear')
on conflict (rule_set_code,stage,source_code,priority) do update set
 input_scope=excluded.input_scope,required_category_code=excluded.required_category_code,
 match_operator=excluded.match_operator,include_terms=excluded.include_terms,
 output_category_code=excluded.output_category_code,output_detail_code=excluded.output_detail_code,
 source_file=excluded.source_file,source_anchor=excluded.source_anchor,active=true;

-- Room shoes are not clothing and must be explicitly non-comparable in the regression truth set.
update fitmatch_staging.runtime_classification_regression_cases
set expected_category_code='other',expected_detail_code='other',expected_comparable=false,
    evidence=evidence || jsonb_build_object('review_correction','unsupported_room_shoes')
where rule_set_code='app-hardcoded-parity-2026-08-06-v1'
  and source_code='uniqlo' and external_product_id='E461767';

commit;
