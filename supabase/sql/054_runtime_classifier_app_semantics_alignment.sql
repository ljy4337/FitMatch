begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-app-semantics-v3'));

-- ParsedClosetClassification resolves special garments from the deepest
-- provider category, not from arbitrary product-name matches.
update fitmatch_taxonomy.runtime_classification_rules
set input_scope = 'specific_source'
where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1'
  and stage = 'special_category';

-- These legacy DB-only semantic details do not exist in the current Swift
-- canonical detail resolver. Swift preserves them as other_tops unless a
-- sleeve-length rule is present.
update fitmatch_taxonomy.runtime_classification_rules
set active = false
where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1'
  and stage = 'detail'
  and priority between 101 and 106;

insert into fitmatch_taxonomy.runtime_classification_rules
  (rule_set_code,stage,source_code,priority,input_scope,required_category_code,
   match_operator,include_terms,exclude_terms,output_detail_code,
   source_file,source_anchor,active)
values
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',199,'combined','tops',
   'always',array[]::text[],array[]::text[],'other_tops',
   'FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops-default',true),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',299,'combined','bottoms',
   'always',array[]::text[],array[]::text[],'other_bottoms',
   'FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:bottoms-default',true),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',499,'combined','outerwear',
   'always',array[]::text[],array[]::text[],'other_outerwear',
   'FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:outerwear-default',true)
on conflict (rule_set_code,stage,source_code,priority) do update set
  input_scope=excluded.input_scope,
  required_category_code=excluded.required_category_code,
  match_operator=excluded.match_operator,
  include_terms=excluded.include_terms,
  exclude_terms=excluded.exclude_terms,
  output_detail_code=excluded.output_detail_code,
  source_file=excluded.source_file,
  source_anchor=excluded.source_anchor,
  active=true;

create or replace function fitmatch_taxonomy.evaluate_runtime_classification(
  p_rule_set_code text, p_source_code text, p_product_name text, p_source_category_path text
) returns jsonb language plpgsql security invoker
set search_path = pg_catalog, fitmatch_taxonomy as $$
declare
 v_path text := lower(coalesce(p_source_category_path,''));
 v_name text := lower(coalesce(p_product_name,''));
 v_specific text := lower(trim(regexp_replace(coalesce(p_source_category_path,''), '^.*>', '')));
 v_candidate text; v_category text; v_detail text; v_family text; v_length text;
 v_rule fitmatch_taxonomy.runtime_classification_rules%rowtype; v_term text; v_matches boolean;
 v_done text[] := array[]::text[];
begin
 for v_rule in select * from fitmatch_taxonomy.runtime_classification_rules
  where rule_set_code=p_rule_set_code and active and source_code in ('any',lower(p_source_code))
  order by case stage when 'provider_major' then 1 when 'special_category' then 2 when 'detail' then 3
   when 'normalized_type' then 4 when 'family' then 5 when 'length' then 6 end, priority
 loop
  if v_rule.stage=any(v_done) then continue; end if;
  if v_rule.stage='special_category' and v_category='other' then continue; end if;
  if v_rule.required_category_code is not null and v_rule.required_category_code is distinct from v_category then continue; end if;
  v_candidate := case v_rule.input_scope when 'specific_source' then v_specific when 'source_path' then v_path
    when 'product_name' then v_name when 'category_code' then coalesce(v_category,'')
    when 'detail_code' then coalesce(v_detail,'') else concat_ws(' ',v_path,v_name) end;
  v_matches := v_rule.match_operator='always';
  if v_rule.match_operator in ('contains_any','exact_any') then
   v_matches:=false;
   foreach v_term in array v_rule.include_terms loop
    if (v_rule.match_operator='contains_any' and v_candidate like '%'||lower(v_term)||'%')
      or (v_rule.match_operator='exact_any' and v_candidate=lower(v_term)) then v_matches:=true; exit; end if;
   end loop;
  end if;
  if v_matches and exists(select 1 from unnest(v_rule.exclude_terms) x where v_candidate like '%'||lower(x)||'%') then v_matches:=false; end if;
  if not v_matches then continue; end if;
  v_category:=coalesce(v_rule.output_category_code,v_category); v_detail:=coalesce(v_rule.output_detail_code,v_detail);
  v_family:=coalesce(v_rule.output_family_code,v_family); v_length:=coalesce(v_rule.output_length_code,v_length);
  v_done:=array_append(v_done,v_rule.stage);
 end loop;
 return jsonb_build_object('category_code',v_category,'detail_code',v_detail,'family_code',v_family,
  'length_code',v_length,'comparable',v_category is not null and v_detail is not null
    and v_category <> 'other' and v_detail <> 'other');
end; $$;

revoke all on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text)
  from public,anon,authenticated;
grant execute on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text)
  to service_role;
commit;
