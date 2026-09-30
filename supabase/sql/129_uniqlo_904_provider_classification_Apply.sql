-- DEVELOPMENT CANDIDATE — review and apply manually to an isolated/development DB.
-- Production application, data migration, Edge deploy, commit and push: NOT DONE.
--
-- Evidence:
--   904 individual UNIQLO API response files were split offline into
--   752 clothing / 94 non-clothing / 58 review-needed records.
--   The review set is clothing-presence evidence only; it is NOT sufficient to
--   invent a FitMatch garment tuple. Consequently this patch adds only exact,
--   unambiguous provider facts/rules and keeps conflicting or incomplete cases
--   REVIEW_REQUIRED.
--
-- Compatibility:
--   * accepts either the deployed r3 preimage or the local 128 compatibility postimage;
--   * keeps public RPC names/signatures and the r3 Swift/recovery contract;
--   * does not update products, observations, user overrides or measurements;
--   * all new rules are provider='uniqlo'. MUSINSA/ZARA evaluation is unchanged.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $apply$
declare
    fn_oid oid := to_regprocedure('fitmatch_vnext.classification_decision(text,text)');
    ddl text;
    live_body text;
    live_md5 text;
    baseline_security_definer boolean;
    baseline_acl aclitem[];
    baseline_config text[];
    baseline_owner oid;
    after_security_definer boolean;
    after_acl aclitem[];
    after_config text[];
    after_owner oid;
    provider_anchor constant text := '{"version":"fitmatch-provider-api-policy-20260909-r3"';
    provider_start integer;
    provider_end_rel integer;
    provider_json_text text;
    provider_policy jsonb;
    additions jsonb;
    old_text text;
    new_text text;
    hit_count integer;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('fitmatch_vnext.classification_decision(text,text)', 0)
    );

    if fn_oid is null then
        raise exception 'FM_U904_MISSING_CLASSIFICATION_DECISION';
    end if;

    select pg_catalog.pg_get_functiondef(p.oid), p.prosrc,
           md5(replace(p.prosrc, chr(13), '')),
           p.prosecdef, p.proacl, p.proconfig, p.proowner
      into ddl, live_body, live_md5,
           baseline_security_definer, baseline_acl, baseline_config, baseline_owner
      from pg_catalog.pg_proc p
     where p.oid = fn_oid;

    if strpos(live_body, 'fitmatch-provider-api-policy-20260910-u904-r3') > 0 then
        if strpos(live_body, 'uniqlo.u904.room_shoes') = 0
           or strpos(live_body, 'category_id_path') = 0
           or strpos(live_body, '{details,status}') = 0
           or strpos(live_body, 'fitmatch-vnext-retailer-api-20260909-r3') = 0 then
            raise exception 'FM_U904_PARTIAL_INSTALLATION';
        end if;
        return;
    end if;

    if live_md5 not in (
        '0c0dabc519fa9d1f4ffb9b8ecf87ce95',
        '291bf9bdf95b37d234f344e7d4d80303',
        -- Semantic r3 postimage produced by this candidate's rollback. The
        -- provider policy JSON is reserialized, so its body checksum differs
        -- while rules, contract, volatility, ACL and owner are restored.
        'a70ddfd0b3873486357d6f2022c2210a'
    ) then
        raise exception 'FM_U904_PREIMAGE_DRIFT: %', live_md5;
    end if;

    -- Fold in the narrow previous-version compatibility correction when 128 has
    -- not yet been applied. Nested legacy guards remain untouched.
    if live_md5 = '0c0dabc519fa9d1f4ffb9b8ecf87ce95' then
        old_text := $old$ -- Installing this function cannot invalidate existing personal choices or reclassify
 -- stored rows. Existing ingress clears resolver_version only for a NEW observation.
 IF product_row.resolver_version IS NOT NULL AND product_row.resolver_version<>version_value
 THEN RETURN base; END IF;$old$;
        new_text := $new$ -- A previous resolver version does not invalidate current, identity-verified
 -- retailer API evidence. Stored rows still change only through the existing apply path.
$new$;
        hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
        if hit_count <> 1 then
            raise exception 'FM_U904_COMPAT_GUARD_TARGET_COUNT=%', hit_count;
        end if;
        ddl := replace(ddl, old_text, new_text);
    end if;

    -- Parse the existing policy as JSON. Do not rewrite unrelated rules manually.
    if (length(ddl) - length(replace(ddl, provider_anchor, ''))) / length(provider_anchor) <> 1 then
        raise exception 'FM_U904_PROVIDER_POLICY_ANCHOR_COUNT';
    end if;
    provider_start := strpos(ddl, provider_anchor);
    provider_end_rel := strpos(substring(ddl from provider_start), '$policy$::jsonb;');
    if provider_start = 0 or provider_end_rel <= 1 then
        raise exception 'FM_U904_PROVIDER_POLICY_PARSE';
    end if;
    provider_json_text := substring(ddl from provider_start for provider_end_rel - 1);
    provider_policy := provider_json_text::jsonb;

    if provider_policy->>'version' <> 'fitmatch-provider-api-policy-20260909-r3'
       or jsonb_typeof(provider_policy->'rules') <> 'array'
       or jsonb_array_length(provider_policy->'rules') <> 230 then
        raise exception 'FM_U904_PROVIDER_POLICY_BASELINE_SHAPE';
    end if;

    additions := jsonb_build_array(
        jsonb_build_object(
            'rule_id','uniqlo.u904.inner_crew','dimension','garment_type_code',
            'values',jsonb_build_array('base_layer_top'),
            'pattern','^airism > inner tops > crew neck$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','INNER_CONTEXT','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.special_polo','dimension','garment_type_code',
            'values',jsonb_build_array('polo_shirt'),
            'pattern','^special collaboration > .+ > polo$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.special_tshirt','dimension','garment_type_code',
            'values',jsonb_build_array('tshirt'),
            'pattern','^special collaboration > .+ > t-shirts$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','OUTER_CONTEXT','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.women_panty_path','dimension','garment_type_code',
            'values',jsonb_build_array('women_panty'),
            'pattern','^lounge and underwear collection > effortless charm > (bikini|hiphugger|just waist)$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','INNER_CONTEXT','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.shirt_blouse_path','dimension','garment_type_code',
            'values',jsonb_build_array('shirt_blouse'),
            'pattern','^shirts and blouses > shirts and blouses > (cotton|linen|rayon|sleeveles|three quarter sleeve|uniqlo and jw anderson)$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','OUTER_CONTEXT','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.shirt_sleeveless_axis','dimension','sleeve_length_code',
            'values',jsonb_build_array('sleeveless'),
            'pattern','^shirts and blouses > shirts and blouses > sleeveles$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.shirt_three_quarter_axis','dimension','sleeve_length_code',
            'values',jsonb_build_array('three_quarter_sleeve'),
            'pattern','^shirts and blouses > shirts and blouses > three quarter sleeve$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.bra_path','dimension','garment_type_code',
            'values',jsonb_build_array('women_bra'),
            'pattern','^airism > bras and bra tops > others$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','INNER_CONTEXT','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.room_shoes','dimension','exclusion',
            'values',jsonb_build_array('NON_APPAREL'),
            'pattern','^룸슈즈$',
            'fields',jsonb_build_array('name'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.hoodie_path','dimension','garment_type_code',
            'values',jsonb_build_array('hoodie'),
            'pattern','^tops > sweatshirts and hoodies > hoodies$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.sweat_pants_path','dimension','garment_type_code',
            'values',jsonb_build_array('sweat_jogger_pants'),
            'pattern','^bottoms > sweat pants > sweat$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.pocketable_parka','dimension','garment_type_code',
            'values',jsonb_build_array('windbreaker'),
            'pattern','^outerwear > parkas and blousons > pocketable$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','ANY','unless_pattern',''
        ),
        jsonb_build_object(
            'rule_id','uniqlo.u904.graphic_tshirt','dimension','garment_type_code',
            'values',jsonb_build_array('tshirt'),
            'pattern','^(tops|toddler) > (graphic tees ut|ut graphic tees) > .+$',
            'fields',jsonb_build_array('category_path'),'provider','uniqlo',
            'context','OUTER_CONTEXT','unless_pattern',''
        )
    );

    if exists (
        select 1 from jsonb_array_elements(provider_policy->'rules') r
        where r->>'rule_id' like 'uniqlo.u904.%'
    ) then
        raise exception 'FM_U904_RULE_ID_ALREADY_PRESENT';
    end if;

    provider_policy := jsonb_set(
        provider_policy, '{rules}', provider_policy->'rules' || additions, true
    );
    provider_policy := jsonb_set(
        provider_policy, '{version}',
        to_jsonb('fitmatch-provider-api-policy-20260910-u904-r3'::text), true
    );
    if jsonb_array_length(provider_policy->'rules') <> 243 then
        raise exception 'FM_U904_RULE_COUNT_AFTER=%', jsonb_array_length(provider_policy->'rules');
    end if;
    -- Keep version first so the policy remains independently addressable by a
    -- guarded rollback; jsonb::text alone reorders object keys.
    new_text := '{"version":"fitmatch-provider-api-policy-20260910-u904-r3","rules":'
                || (provider_policy->'rules')::text || '}';
    ddl := replace(ddl, provider_json_text, new_text);

    -- HTTP 200 is transport success only for UNIQLO. Preserve the raw object but
    -- do not elevate a soft-error body to verified evidence.
    old_text := $old$
    OR jsonb_typeof(envelope->'details') IS DISTINCT FROM 'object'
 THEN invalid_evidence:=true;
 ELSE
$old$;
    new_text := $new$
    OR jsonb_typeof(envelope->'details') IS DISTINCT FROM 'object'
    OR (product_row.source_code='uniqlo' AND (
          envelope#>>'{details,status}' IS DISTINCT FROM 'ok'
          OR jsonb_typeof(envelope#>'{details,result}') IS DISTINCT FROM 'object'
       ))
 THEN invalid_evidence:=true;
 ELSE
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_U904_BODY_STATUS_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    -- Keep all original breadcrumb nodes and additionally expose their ordered
    -- class/category/subcategory path to provider-scoped rules.
    old_text := $old$
     UNION ALL
     SELECT jsonb_build_object('field','attribute','value',(tag->>'group')||'='||(tag->>'tag'),
        'source_path','$.result.tags['||(ordinality-1)||']')
$old$;
    new_text := $new$
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
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_U904_CATEGORY_PATH_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    -- A provider-scoped rule matching the complete API breadcrumb is category
    -- evidence. Without this, the new exact paths can propose a garment but are
    -- always rejected as NO_CORROBORATED_TYPE_EVIDENCE. Name/attribute evidence
    -- remains insufficient on its own, and ambiguous paths still produce review.
    old_text := $old$EXISTS(SELECT 1 FROM raw_hits WHERE dimension='garment_type_code' AND field IN ('category','category_locale')) category_corroborated,$old$;
    new_text := $new$EXISTS(SELECT 1 FROM raw_hits WHERE dimension='garment_type_code' AND (
       field IN ('category','category_locale')
       OR (p_observation->>'source_code'='uniqlo' AND field IN ('category_path','category_id_path'))
     )) category_corroborated,$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_U904_CATEGORY_CORROBORATION_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    execute ddl;

    select p.prosecdef, p.proacl, p.proconfig, p.proowner
      into after_security_definer, after_acl, after_config, after_owner
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure('fitmatch_vnext.classification_decision(text,text)');

    if after_security_definer is distinct from baseline_security_definer
       or after_acl is distinct from baseline_acl
       or after_config is distinct from baseline_config
       or after_owner is distinct from baseline_owner then
        raise exception 'FM_U904_SECURITY_METADATA_CHANGED';
    end if;

    if not exists (
        select 1 from pg_catalog.pg_proc p
        where p.oid = to_regprocedure('fitmatch_vnext.classification_decision(text,text)')
          and strpos(p.prosrc, 'fitmatch-provider-api-policy-20260910-u904-r3') > 0
          and strpos(p.prosrc, 'uniqlo.u904.room_shoes') > 0
          and strpos(p.prosrc, 'category_id_path') > 0
          and strpos(p.prosrc, $$p_observation->>'source_code'='uniqlo' AND field IN ('category_path','category_id_path')$$) > 0
          and strpos(p.prosrc, '{details,status}') > 0
          and strpos(p.prosrc, 'fitmatch-vnext-retailer-api-20260909-r3') > 0
    ) then
        raise exception 'FM_U904_POSTCHECK_FAILED';
    end if;
end
$apply$;

commit;
