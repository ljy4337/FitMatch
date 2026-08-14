begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-remaining-generic-paths'));

insert into fitmatch_taxonomy.runtime_classification_rules
 (rule_set_code,stage,source_code,priority,input_scope,required_category_code,match_operator,
  include_terms,output_category_code,source_file,source_anchor)
values
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',1,'product_name',null,'contains_any',array['룸슈즈'],'other','FitMatch/Services/UniqloParser.swift','mapCategory:unsupported-shoes'),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',2,'product_name',null,'contains_any',array['재킷','자켓','jacket'],'outerwear','FitMatch/Services/UniqloParser.swift','mapCategory:product-structured-type'),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',3,'product_name',null,'contains_any',array['팬츠','바지','pants'],'bottoms','FitMatch/Services/UniqloParser.swift','mapCategory:product-structured-type')
on conflict (rule_set_code,stage,source_code,priority) do update set
 input_scope=excluded.input_scope,match_operator=excluded.match_operator,include_terms=excluded.include_terms,
 output_category_code=excluded.output_category_code,source_file=excluded.source_file,
 source_anchor=excluded.source_anchor,active=true;

create or replace function fitmatch_taxonomy.runtime_is_comparable(p_category text,p_detail text)
returns boolean language sql immutable security invoker
set search_path=pg_catalog as $$
 select p_category is not null and p_detail is not null
    and p_category <> 'other' and p_detail not in ('other','other_bottoms','other_outerwear')
$$;
revoke all on function fitmatch_taxonomy.runtime_is_comparable(text,text) from public,anon,authenticated;
grant execute on function fitmatch_taxonomy.runtime_is_comparable(text,text) to service_role;

-- Replace only the final comparability expression while retaining evaluator semantics from 021.
-- The evaluator remains private; callers use this predicate when auditing its JSON output.
commit;
