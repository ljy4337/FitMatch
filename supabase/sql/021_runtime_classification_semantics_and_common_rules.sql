begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-classification-semantics-v2'));

insert into fitmatch_taxonomy.runtime_classification_rules
  (rule_set_code,stage,source_code,priority,input_scope,required_category_code,match_operator,
   include_terms,output_category_code,output_detail_code,source_file,source_anchor)
values
  ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',91,'source_path',null,'contains_any',array['니트','가디건','스웨터'],'tops',null,'FitMatch/Services/UniqloParser.swift','mapCategory:knit'),
  ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',92,'source_path',null,'contains_any',array['커버올'],'tops',null,'FitMatch/Services/UniqloParser.swift','mapCategory:coverall'),
  ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',93,'source_path',null,'contains_any',array['에어리즘','히트텍'],'underwear',null,'FitMatch/Services/UniqloParser.swift','mapCategory:innerwear'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',101,'combined','tops','contains_any',array['후드 티셔츠','후디','hoodie'],null,'hoodie','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',102,'combined','tops','contains_any',array['맨투맨','스웨트셔츠','sweatshirt'],null,'sweatshirt','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',103,'combined','tops','contains_any',array['가디건','카디건','cardigan'],null,'cardigan','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',104,'combined','tops','contains_any',array['블라우스','blouse'],null,'blouse','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',105,'combined','tops','contains_any',array['폴로셔츠','오버셔츠','셔츠','shirt'],null,'shirt','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',106,'combined','tops','contains_any',array['니트','스웨터','sweater','knit'],null,'knit_top','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:tops'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',501,'combined','underwear','contains_any',array['브라','bra'],null,'women_bra','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:underwear'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',502,'combined','underwear','contains_any',array['복서','트렁크','boxer','trunks'],null,'men_trunks','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:underwear'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',503,'combined','underwear','contains_any',array['브리프','brief'],null,'men_briefs','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:underwear'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',509,'combined','underwear','always',array[]::text[],null,'underwear','FitMatch/Models/ParsedClosetClassification.swift','canonicalDetailCode:underwear-default'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',601,'combined','leggings','contains_any',array['7부','크롭','cropped','three quarter'],null,'three_quarter_leggings','FitMatch/Models/ParsedClosetClassification.swift','resolve:leggings'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',602,'combined','leggings','contains_any',array['쇼트','숏','short'],null,'short_leggings','FitMatch/Models/ParsedClosetClassification.swift','resolve:leggings'),
  ('app-hardcoded-parity-2026-08-06-v1','detail','any',609,'combined','leggings','always',array[]::text[],null,'long_leggings','FitMatch/Models/ParsedClosetClassification.swift','resolve:leggings-default')
on conflict (rule_set_code,stage,source_code,priority) do update set
 input_scope=excluded.input_scope,required_category_code=excluded.required_category_code,
 match_operator=excluded.match_operator,include_terms=excluded.include_terms,
 output_category_code=excluded.output_category_code,output_detail_code=excluded.output_detail_code,
 source_file=excluded.source_file,source_anchor=excluded.source_anchor,active=true;

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
    and v_category <> 'other' and v_detail not in ('other','other_bottoms','other_outerwear'));
end; $$;

revoke all on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text) from public,anon,authenticated;
grant execute on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text) to service_role;
commit;
