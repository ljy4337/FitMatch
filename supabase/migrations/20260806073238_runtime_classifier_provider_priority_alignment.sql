begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-provider-priority-v4'));

-- Mirror UniqloProductMetadataParser.mapCategory's ordered combined-text checks.
update fitmatch_taxonomy.runtime_classification_rules
set active = false
where rule_set_code = 'app-hardcoded-parity-2026-08-06-v1'
  and stage = 'provider_major' and source_code = 'uniqlo';

insert into fitmatch_taxonomy.runtime_classification_rules
  (rule_set_code,stage,source_code,priority,input_scope,match_operator,
   include_terms,exclude_terms,output_category_code,source_file,source_anchor,active)
values
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',1,'combined','contains_any',
  array['홈웨어','라운지','파자마','homewear','loungewear'],array[]::text[],'other','FitMatch/Services/UniqloParser.swift','mapCategory:homewear',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',2,'combined','contains_any',
  array['overshirt','오버셔츠','shirt','셔츠'],array[]::text[],'tops','FitMatch/Services/UniqloParser.swift','mapCategory:shirt',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',3,'combined','contains_any',
  array['스커트','skirt'],array[]::text[],'bottoms','FitMatch/Services/UniqloParser.swift','mapCategory:skirt',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',4,'combined','contains_any',
  array['원피스','dress'],array[]::text[],'dresses','FitMatch/Services/UniqloParser.swift','mapCategory:dress',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',5,'combined','contains_any',
  array['bottoms','팬츠','바지','데님','쇼츠','pants','jeans','shorts'],array[]::text[],'bottoms','FitMatch/Services/UniqloParser.swift','mapCategory:bottoms',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',6,'combined','contains_any',
  array['아우터','재킷','자켓','코트','파카','점퍼','outer','jacket','coat'],array[]::text[],'outerwear','FitMatch/Services/UniqloParser.swift','mapCategory:outerwear',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',7,'combined','contains_any',
  array['tops','상의'],array[]::text[],'tops','FitMatch/Services/UniqloParser.swift','mapCategory:tops',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',8,'combined','contains_any',
  array['속옷','이너','inner','underwear'],array[]::text[],'underwear','FitMatch/Services/UniqloParser.swift','mapCategory:underwear',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',9,'combined','contains_any',
  array['신발','슈즈','shoes'],array[]::text[],'other','FitMatch/Services/UniqloParser.swift','mapCategory:shoes',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',10,'combined','contains_any',
  array['가방','모자','벨트','액세서리','accessories'],array[]::text[],'other','FitMatch/Services/UniqloParser.swift','mapCategory:accessory',true),
 ('app-hardcoded-parity-2026-08-06-v1','provider_major','uniqlo',99,'combined','always',
  array[]::text[],array[]::text[],'tops','FitMatch/Services/UniqloParser.swift','mapCategory:default-top',true)
on conflict (rule_set_code,stage,source_code,priority) do update set
 input_scope=excluded.input_scope,match_operator=excluded.match_operator,
 include_terms=excluded.include_terms,exclude_terms=excluded.exclude_terms,
 output_category_code=excluded.output_category_code,output_detail_code=null,
 source_file=excluded.source_file,source_anchor=excluded.source_anchor,active=true;

-- Homewear is the one special family Swift recognizes from the whole input,
-- including product names such as 파자마.
update fitmatch_taxonomy.runtime_classification_rules
set input_scope='combined',
    include_terms=array['홈웨어','라운지','파자마','잠옷','homewear','loungewear','pajama','pyjama']
where rule_set_code='app-hardcoded-parity-2026-08-06-v1'
  and stage='special_category' and priority=50;

-- Outerwear first uses the provider path. Product-name fallback is performed
-- only if no path rule matches, like deepestOuterwearDetail in Swift.
update fitmatch_taxonomy.runtime_classification_rules
set input_scope='source_path'
where rule_set_code='app-hardcoded-parity-2026-08-06-v1'
  and stage='detail' and required_category_code='outerwear'
  and match_operator <> 'always';

-- Korean 복서 is not a Swift trunks token; 복서브리프 resolves as briefs.
update fitmatch_taxonomy.runtime_classification_rules
set include_terms=array['트렁크','boxer','trunks']
where rule_set_code='app-hardcoded-parity-2026-08-06-v1'
  and stage='detail' and required_category_code='underwear' and priority=502;

insert into fitmatch_taxonomy.runtime_classification_rules
 (rule_set_code,stage,source_code,priority,input_scope,required_category_code,
  match_operator,include_terms,exclude_terms,output_detail_code,source_file,source_anchor,active)
values
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',500,'combined','underwear','contains_any',array['캐미솔','camisole'],array[]::text[],'women_camisole','FitMatch/Services/UniqloParser.swift','mapDetailCategory:camisole',true),
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',5001,'combined','underwear','contains_any',array['슬립','slip'],array[]::text[],'women_slip','FitMatch/Services/UniqloParser.swift','mapDetailCategory:slip',true),
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',504,'combined','underwear','contains_any',array['팬티','panty'],array[]::text[],'women_panty','FitMatch/Services/UniqloParser.swift','mapDetailCategory:panty',true),
 ('app-hardcoded-parity-2026-08-06-v1','detail','any',505,'combined','underwear','contains_any',array['런닝','undershirt'],array[]::text[],'men_undershirt','FitMatch/Services/UniqloParser.swift','mapDetailCategory:undershirt',true)
on conflict (rule_set_code,stage,source_code,priority) do update set
 input_scope=excluded.input_scope,required_category_code=excluded.required_category_code,
 match_operator=excluded.match_operator,include_terms=excluded.include_terms,
 exclude_terms=excluded.exclude_terms,output_detail_code=excluded.output_detail_code,
 source_file=excluded.source_file,source_anchor=excluded.source_anchor,active=true;

create or replace function fitmatch_taxonomy.evaluate_runtime_classification(
 p_rule_set_code text,p_source_code text,p_product_name text,p_source_category_path text
) returns jsonb language plpgsql security invoker
set search_path=pg_catalog,fitmatch_taxonomy as $$
declare
 v_path text:=lower(coalesce(p_source_category_path,'')); v_name text:=lower(coalesce(p_product_name,''));
 v_specific text:=lower(trim(regexp_replace(coalesce(p_source_category_path,''),'^.*>','')));
 v_candidate text; v_category text; v_detail text; v_family text; v_length text;
 v_rule fitmatch_taxonomy.runtime_classification_rules%rowtype;
 v_fallback fitmatch_taxonomy.runtime_classification_rules%rowtype;
 v_term text; v_matches boolean; v_done text[]:=array[]::text[];
begin
 for v_rule in select * from fitmatch_taxonomy.runtime_classification_rules
  where rule_set_code=p_rule_set_code and active and source_code in ('any',lower(p_source_code))
  order by case stage when 'provider_major' then 1 when 'special_category' then 2 when 'detail' then 3
   when 'normalized_type' then 4 when 'family' then 5 when 'length' then 6 end,priority
 loop
  if v_rule.stage=any(v_done) then continue; end if;
  if v_rule.required_category_code is not null and v_rule.required_category_code is distinct from v_category then continue; end if;
  -- If no outerwear path term matched, try the same DB rules on combined text
  -- immediately before accepting the generic fallback.
  if v_rule.stage='detail' and v_category='outerwear' and v_rule.match_operator='always' then
   for v_fallback in select * from fitmatch_taxonomy.runtime_classification_rules
    where rule_set_code=p_rule_set_code and active and stage='detail'
      and source_code in ('any',lower(p_source_code)) and required_category_code='outerwear'
      and match_operator<>'always' order by priority
   loop
    v_matches:=false;
    foreach v_term in array v_fallback.include_terms loop
     if concat_ws(' ',v_path,v_name) like '%'||lower(v_term)||'%' then v_matches:=true; exit; end if;
    end loop;
    if v_matches then v_detail:=v_fallback.output_detail_code; exit; end if;
   end loop;
   if v_detail is not null then v_done:=array_append(v_done,'detail'); continue; end if;
  end if;
  v_candidate:=case v_rule.input_scope when 'specific_source' then v_specific when 'source_path' then v_path
   when 'product_name' then v_name when 'category_code' then coalesce(v_category,'')
   when 'detail_code' then coalesce(v_detail,'') else concat_ws(' ',v_path,v_name) end;
  v_matches:=v_rule.match_operator='always';
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
   and v_category<>'other' and v_detail<>'other');
end; $$;

revoke all on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text)
 from public,anon,authenticated;
grant execute on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text)
 to service_role;
commit;
;
