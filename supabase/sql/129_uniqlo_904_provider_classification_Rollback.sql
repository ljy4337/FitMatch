-- Manual rollback for 129_uniqlo_904_provider_classification_Apply.sql.
-- Restores the r3 provider policy and removes only the 13 u904 rules/fact readers.
-- It intentionally retains the separate 128 previous-version compatibility fix.
-- To return all the way to md5 0c0dabc..., run 128_*_Rollback.sql afterwards.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $rollback$
declare
    fn_oid oid := to_regprocedure('fitmatch_vnext.classification_decision(text,text)');
    ddl text;
    live_body text;
    provider_anchor constant text := '{"version":"fitmatch-provider-api-policy-20260910-u904-r3"';
    provider_start integer;
    provider_end_rel integer;
    provider_json_text text;
    provider_policy jsonb;
    filtered_rules jsonb;
    old_text text;
    new_text text;
    hit_count integer;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('fitmatch_vnext.classification_decision(text,text)', 0)
    );
    if fn_oid is null then
        raise exception 'FM_U904_ROLLBACK_MISSING_FUNCTION';
    end if;
    select pg_catalog.pg_get_functiondef(p.oid), p.prosrc
      into ddl, live_body
      from pg_catalog.pg_proc p where p.oid = fn_oid;

    if strpos(live_body, 'fitmatch-provider-api-policy-20260910-u904-r3') = 0 then
        if md5(replace(live_body, chr(13), '')) in (
            '291bf9bdf95b37d234f344e7d4d80303',
            'a70ddfd0b3873486357d6f2022c2210a'
        ) then
            return;
        end if;
        raise exception 'FM_U904_ROLLBACK_PREIMAGE_DRIFT';
    end if;

    if (length(ddl) - length(replace(ddl, provider_anchor, ''))) / length(provider_anchor) <> 1 then
        raise exception 'FM_U904_ROLLBACK_POLICY_ANCHOR_COUNT';
    end if;
    provider_start := strpos(ddl, provider_anchor);
    provider_end_rel := strpos(substring(ddl from provider_start), '$policy$::jsonb;');
    provider_json_text := substring(ddl from provider_start for provider_end_rel - 1);
    provider_policy := provider_json_text::jsonb;

    if provider_policy->>'version' <> 'fitmatch-provider-api-policy-20260910-u904-r3'
       or jsonb_typeof(provider_policy->'rules') <> 'array'
       or jsonb_array_length(provider_policy->'rules') <> 243
       or (select count(*) from jsonb_array_elements(provider_policy->'rules') r
           where r->>'rule_id' like 'uniqlo.u904.%') <> 13 then
        raise exception 'FM_U904_ROLLBACK_POLICY_DRIFT';
    end if;

    select jsonb_agg(r order by ord)
      into filtered_rules
      from jsonb_array_elements(provider_policy->'rules') with ordinality t(r,ord)
     where r->>'rule_id' not like 'uniqlo.u904.%';
    if jsonb_array_length(filtered_rules) <> 230 then
        raise exception 'FM_U904_ROLLBACK_RULE_COUNT=%', jsonb_array_length(filtered_rules);
    end if;
    provider_policy := jsonb_set(provider_policy, '{rules}', filtered_rules, true);
    provider_policy := jsonb_set(
        provider_policy, '{version}',
        to_jsonb('fitmatch-provider-api-policy-20260909-r3'::text), true
    );
    new_text := '{"version":"fitmatch-provider-api-policy-20260909-r3","rules":'
                || (provider_policy->'rules')::text || '}';
    ddl := replace(ddl, provider_json_text, new_text);

    old_text := $old$
    OR jsonb_typeof(envelope->'details') IS DISTINCT FROM 'object'
    OR (product_row.source_code='uniqlo' AND (
          envelope#>>'{details,status}' IS DISTINCT FROM 'ok'
          OR jsonb_typeof(envelope#>'{details,result}') IS DISTINCT FROM 'object'
       ))
 THEN invalid_evidence:=true;
 ELSE
$old$;
    new_text := $new$
    OR jsonb_typeof(envelope->'details') IS DISTINCT FROM 'object'
 THEN invalid_evidence:=true;
 ELSE
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_U904_ROLLBACK_BODY_STATUS_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    old_text := $old$EXISTS(SELECT 1 FROM raw_hits WHERE dimension='garment_type_code' AND (
       field IN ('category','category_locale')
       OR (p_observation->>'source_code'='uniqlo' AND field IN ('category_path','category_id_path'))
     )) category_corroborated,$old$;
    new_text := $new$EXISTS(SELECT 1 FROM raw_hits WHERE dimension='garment_type_code' AND field IN ('category','category_locale')) category_corroborated,$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_U904_ROLLBACK_CATEGORY_CORROBORATION_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    old_text := $old$
     UNION ALL
     SELECT jsonb_build_object(
        'field','category_path',
        'value',concat_ws(' > ',
            nullif(api_product#>>'{breadcrumbs,class,name}',''),
            nullif(api_product#>>'{breadcrumbs,category,name}',''),
            nullif(api_product#>>'{breadcrumbs,subcategory,name}','')),
        'source_path','$.result.breadcrumbs')
     WHERE nullif(concat_ws(' > ',
            nullif(api_product#>>'{breadcrumbs,class,name}',''),
            nullif(api_product#>>'{breadcrumbs,category,name}',''),
            nullif(api_product#>>'{breadcrumbs,subcategory,name}','')),'') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object(
        'field','category_id_path',
        'value',concat_ws(' > ',
            nullif(api_product#>>'{breadcrumbs,class,id}',''),
            nullif(api_product#>>'{breadcrumbs,category,id}',''),
            nullif(api_product#>>'{breadcrumbs,subcategory,id}','')),
        'source_path','$.result.breadcrumbs[*].id')
     WHERE nullif(concat_ws(' > ',
            nullif(api_product#>>'{breadcrumbs,class,id}',''),
            nullif(api_product#>>'{breadcrumbs,category,id}',''),
            nullif(api_product#>>'{breadcrumbs,subcategory,id}','')),'') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','attribute','value',(tag->>'group')||'='||(tag->>'tag'),
        'source_path','$.result.tags['||(ordinality-1)||']')
$old$;
    new_text := $new$
     UNION ALL
     SELECT jsonb_build_object('field','attribute','value',(tag->>'group')||'='||(tag->>'tag'),
        'source_path','$.result.tags['||(ordinality-1)||']')
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_U904_ROLLBACK_CATEGORY_PATH_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    execute ddl;

    if not exists (
        select 1 from pg_catalog.pg_proc p
        where p.oid = to_regprocedure('fitmatch_vnext.classification_decision(text,text)')
          and strpos(p.prosrc, 'fitmatch-provider-api-policy-20260909-r3') > 0
          and strpos(p.prosrc, 'uniqlo.u904.') = 0
          and strpos(p.prosrc, 'category_id_path') = 0
          and strpos(p.prosrc, 'fitmatch-vnext-retailer-api-20260909-r3') > 0
    ) then
        raise exception 'FM_U904_ROLLBACK_POSTCHECK_FAILED';
    end if;
end
$rollback$;

commit;
