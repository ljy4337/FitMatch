-- DEVELOPMENT CANDIDATE. Apply only after 129_*_Apply.sql and 132_*_Apply.sql.
-- Production application, data migration and Edge deployment are NOT performed.
-- Keeps public RPC/recovery contracts and existing rows unchanged.

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
    recovery_md5 text;
    provider_anchor constant text := '{"version":"fitmatch-provider-api-policy-20260910-u904-zara-v2-r1"';
    provider_start integer;
    provider_end_rel integer;
    provider_json_text text;
    provider_policy jsonb;
    transformed_rules jsonb;
    additions jsonb;
    replacement text;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('fitmatch_vnext.classification_decision(text,text)', 0)
    );
    if fn_oid is null then
        raise exception 'FM_MUSINSA_R1_MISSING_CLASSIFIER';
    end if;
    select pg_catalog.pg_get_functiondef(p.oid), p.prosrc,
           md5(replace(p.prosrc, chr(13), '')),
           p.prosecdef, p.proacl, p.proconfig, p.proowner
      into ddl, live_body, live_md5,
           baseline_security_definer, baseline_acl, baseline_config, baseline_owner
      from pg_catalog.pg_proc p where p.oid = fn_oid;
    select md5(replace(p.prosrc, chr(13), '')) into recovery_md5
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_recovery_options(uuid)'
     );

    if live_md5 = '10e98b939e3886bdabda5f48bbb3cdc6'
       and strpos(live_body, 'fitmatch-provider-api-policy-20260910-u904-zara-v2-musinsa-r1') > 0
       and strpos(live_body, $$r.provider IN ('any',p_observation->>'source_code')$$) > 0 then
        return;
    end if;
    if live_md5 <> 'c8cc257a2e2eaface85beae5cf593dd4' then
        raise exception 'FM_MUSINSA_R1_PREIMAGE_DRIFT: %', live_md5;
    end if;
    if recovery_md5 <> 'd01db739db96a46d5725fbfb8d215e61' then
        raise exception 'FM_MUSINSA_R1_RECOVERY_PREIMAGE_DRIFT: %', recovery_md5;
    end if;

    provider_start := strpos(ddl, provider_anchor);
    provider_end_rel := strpos(substring(ddl from provider_start), '$policy$::jsonb;');
    if provider_start = 0 or provider_end_rel = 0 then
        raise exception 'FM_MUSINSA_R1_POLICY_ANCHOR_MISSING';
    end if;
    provider_json_text := substring(ddl from provider_start for provider_end_rel - 1);
    provider_policy := provider_json_text::jsonb;
    if provider_policy->>'version' <> 'fitmatch-provider-api-policy-20260910-u904-zara-v2-r1'
       or jsonb_typeof(provider_policy->'rules') <> 'array'
       or jsonb_array_length(provider_policy->'rules') <> 248 then
        raise exception 'FM_MUSINSA_R1_BASELINE_POLICY_SHAPE';
    end if;
    if (select count(*) from jsonb_array_elements(provider_policy->'rules') r
        where r->>'rule_id' in ('scope.jacket','type.tshirt')) <> 2 then
        raise exception 'FM_MUSINSA_R1_BASE_RULE_TARGETS';
    end if;

    select jsonb_agg(
        case r->>'rule_id'
          when 'scope.jacket' then jsonb_set(
              r, '{values}',
              '["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton","cardigan","zip_hoodie"]'::jsonb,
              true)
          when 'type.tshirt' then jsonb_set(
              r, '{unless_pattern}',
              to_jsonb((r->>'unless_pattern') || '|(맨투맨|스웨트[ ]?셔츠|후드[ ]?티|후드티셔츠|hoodie|sweatshirt|collared)'::text),
              true)
          else r
        end order by ordinality)
      into transformed_rules
      from jsonb_array_elements(provider_policy->'rules') with ordinality q(r, ordinality);

    additions := jsonb_build_array(
      jsonb_build_object(
        'rule_id','musinsa.r1.category.safari_hunting_jacket','dimension','garment_type_code',
        'values',jsonb_build_array('jacket','coat'),'pattern','^사파리/헌팅 재킷$',
        'fields',jsonb_build_array('category'),'provider','musinsa','context','ANY','unless_pattern',''),
      jsonb_build_object(
        'rule_id','musinsa.r1.category.training_jacket','dimension','garment_type_code',
        'values',jsonb_build_array('jacket'),'pattern','^트레이닝 재킷$',
        'fields',jsonb_build_array('category'),'provider','musinsa','context','ANY','unless_pattern',''),
      jsonb_build_object(
        'rule_id','musinsa.r1.category.anorak_jacket','dimension','garment_type_code',
        'values',jsonb_build_array('anorak'),'pattern','^아노락 재킷$',
        'fields',jsonb_build_array('category'),'provider','musinsa','context','ANY','unless_pattern',''),
      jsonb_build_object(
        'rule_id','musinsa.r1.category.short_heavy_outer','dimension','garment_type_code',
        'values',jsonb_build_array('puffer_jacket'),'pattern','^숏 ?패딩/(숏 ?)?헤비 아우터$',
        'fields',jsonb_build_array('category'),'provider','musinsa','context','ANY','unless_pattern',''),
      jsonb_build_object(
        'rule_id','musinsa.r1.category.long_heavy_outer','dimension','garment_type_code',
        'values',jsonb_build_array('puffer_jacket'),'pattern','^롱 ?패딩/롱 ?헤비 아우터$',
        'fields',jsonb_build_array('category'),'provider','musinsa','context','ANY','unless_pattern',''),
      jsonb_build_object(
        'rule_id','musinsa.r1.category.long_heavy_outer_length','dimension','body_length_code',
        'values',jsonb_build_array('long_body'),'pattern','^롱 ?패딩/롱 ?헤비 아우터$',
        'fields',jsonb_build_array('category'),'provider','musinsa','context','ANY','unless_pattern','')
    );
    provider_policy := jsonb_set(provider_policy, '{rules}', transformed_rules || additions, true);
    provider_policy := jsonb_set(
      provider_policy, '{version}',
      to_jsonb('fitmatch-provider-api-policy-20260910-u904-zara-v2-musinsa-r1'::text), true);
    if jsonb_array_length(provider_policy->'rules') <> 254 then
        raise exception 'FM_MUSINSA_R1_RULE_COUNT_AFTER=%',
            jsonb_array_length(provider_policy->'rules');
    end if;
    replacement := '{"version":"fitmatch-provider-api-policy-20260910-u904-zara-v2-musinsa-r1","rules":'
                   || (provider_policy->'rules')::text || '}';
    ddl := replace(ddl, provider_json_text, replacement);

    execute ddl;

    if not exists (
        select 1 from pg_catalog.pg_proc p
        where p.oid = fn_oid
          and md5(replace(p.prosrc, chr(13), '')) = '10e98b939e3886bdabda5f48bbb3cdc6'
          and strpos(p.prosrc, 'fitmatch-provider-api-policy-20260910-u904-zara-v2-musinsa-r1') > 0
          and strpos(p.prosrc, 'musinsa.r1.category.training_jacket') > 0
          and strpos(p.prosrc, $$r.provider IN ('any',p_observation->>'source_code')$$) > 0
          and p.prosecdef is not distinct from baseline_security_definer
          and p.proacl is not distinct from baseline_acl
          and p.proconfig is not distinct from baseline_config
          and p.proowner is not distinct from baseline_owner
    ) then
        raise exception 'FM_MUSINSA_R1_POSTCHECK_FAILED';
    end if;
    if (select md5(replace(p.prosrc, chr(13), ''))
        from pg_catalog.pg_proc p
        where p.oid = to_regprocedure(
            'fitmatch_vnext.classification_recovery_options(uuid)'
        )) <> recovery_md5 then
        raise exception 'FM_MUSINSA_R1_RECOVERY_CHANGED';
    end if;
end
$apply$;

commit;
