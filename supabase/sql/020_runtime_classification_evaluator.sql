begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:runtime-classification-evaluator'));

create or replace function fitmatch_taxonomy.evaluate_runtime_classification(
  p_rule_set_code text,
  p_source_code text,
  p_product_name text,
  p_source_category_path text
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, fitmatch_taxonomy
as $$
declare
  v_text text := lower(concat_ws(' ', p_source_category_path, p_product_name));
  v_category text;
  v_detail text;
  v_family text;
  v_length text;
  v_rule fitmatch_taxonomy.runtime_classification_rules%rowtype;
  v_term text;
  v_matches boolean;
begin
  for v_rule in
    select * from fitmatch_taxonomy.runtime_classification_rules
    where rule_set_code = p_rule_set_code and active
      and source_code in ('any', lower(p_source_code))
    order by case stage when 'provider_major' then 1 when 'special_category' then 2
             when 'detail' then 3 when 'normalized_type' then 4
             when 'family' then 5 when 'length' then 6 end, priority
  loop
    if v_rule.required_category_code is not null
       and v_rule.required_category_code is distinct from v_category then continue; end if;
    v_matches := v_rule.match_operator = 'always';
    if v_rule.match_operator in ('contains_any', 'exact_any') then
      v_matches := false;
      foreach v_term in array v_rule.include_terms loop
        if (v_rule.match_operator = 'contains_any' and v_text like '%' || lower(v_term) || '%')
           or (v_rule.match_operator = 'exact_any' and v_text = lower(v_term)) then
          v_matches := true; exit;
        end if;
      end loop;
    end if;
    if v_matches and exists (
      select 1 from unnest(v_rule.exclude_terms) x where v_text like '%' || lower(x) || '%'
    ) then v_matches := false; end if;
    if not v_matches then continue; end if;
    v_category := coalesce(v_rule.output_category_code, v_category);
    v_detail := coalesce(v_rule.output_detail_code, v_detail);
    v_family := coalesce(v_rule.output_family_code, v_family);
    v_length := coalesce(v_rule.output_length_code, v_length);
  end loop;
  return jsonb_build_object(
    'category_code', v_category, 'detail_code', v_detail,
    'family_code', v_family, 'length_code', v_length,
    'comparable', v_category is not null and v_detail is not null
  );
end;
$$;

revoke all on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text)
  from public, anon, authenticated;
grant execute on function fitmatch_taxonomy.evaluate_runtime_classification(text,text,text,text)
  to service_role;

commit;
