-- Roll back only the changes made by 134_*_Apply.sql.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $rollback$
declare
    fn_oid oid := to_regprocedure('fitmatch_vnext.classification_decision(text,text)');
    ddl text;
    live_body text;
    live_md5 text;
    recovery_md5 text;
    provider_anchor constant text := '{"version":"fitmatch-provider-api-policy-20260910-u904-zara-v2-musinsa-r1"';
    provider_start integer;
    provider_end_rel integer;
    provider_json_text text;
    provider_policy jsonb;
    restored_rules jsonb;
    replacement text;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('fitmatch_vnext.classification_decision(text,text)', 0)
    );
    select pg_catalog.pg_get_functiondef(p.oid), p.prosrc,
           md5(replace(p.prosrc, chr(13), ''))
      into ddl, live_body, live_md5
      from pg_catalog.pg_proc p where p.oid = fn_oid;
    select md5(replace(p.prosrc, chr(13), '')) into recovery_md5
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_recovery_options(uuid)'
     );
    if live_md5 = 'c8cc257a2e2eaface85beae5cf593dd4' then
        return;
    end if;
    if live_md5 <> '10e98b939e3886bdabda5f48bbb3cdc6' then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_PREIMAGE_DRIFT: %', live_md5;
    end if;
    if recovery_md5 <> 'd01db739db96a46d5725fbfb8d215e61' then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_RECOVERY_DRIFT: %', recovery_md5;
    end if;

    provider_start := strpos(ddl, provider_anchor);
    provider_end_rel := strpos(substring(ddl from provider_start), '$policy$::jsonb;');
    if provider_start = 0 or provider_end_rel = 0 then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_POLICY_ANCHOR_MISSING';
    end if;
    provider_json_text := substring(ddl from provider_start for provider_end_rel - 1);
    provider_policy := provider_json_text::jsonb;
    if jsonb_array_length(provider_policy->'rules') <> 254 then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_POLICY_SHAPE';
    end if;

    select jsonb_agg(
        case r->>'rule_id'
          when 'scope.jacket' then jsonb_set(
              r, '{values}',
              '["jacket","blouson","blazer","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","mouton"]'::jsonb,
              true)
          when 'type.tshirt' then jsonb_set(
              r, '{unless_pattern}',
              to_jsonb('(폴로|카라|니트|KNIT|민소매|슬리브리스|sleeveless|원피스|dress|셔츠\s*&|후리스)'::text),
              true)
          else r
        end order by ordinality)
      into restored_rules
      from jsonb_array_elements(provider_policy->'rules') with ordinality q(r, ordinality)
     where r->>'rule_id' not like 'musinsa.r1.%';
    if jsonb_array_length(restored_rules) <> 248 then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_RULE_COUNT=%',
            jsonb_array_length(restored_rules);
    end if;
    provider_policy := jsonb_set(provider_policy, '{rules}', restored_rules, true);
    provider_policy := jsonb_set(
      provider_policy, '{version}',
      to_jsonb('fitmatch-provider-api-policy-20260910-u904-zara-v2-r1'::text), true);
    replacement := '{"version":"fitmatch-provider-api-policy-20260910-u904-zara-v2-r1","rules":'
                   || (provider_policy->'rules')::text || '}';
    ddl := replace(ddl, provider_json_text, replacement);

    execute ddl;

    if (select md5(replace(p.prosrc, chr(13), ''))
        from pg_catalog.pg_proc p where p.oid = fn_oid)
       <> 'c8cc257a2e2eaface85beae5cf593dd4' then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_POSTCHECK_FAILED: %',
            (select md5(replace(p.prosrc, chr(13), ''))
             from pg_catalog.pg_proc p where p.oid = fn_oid);
    end if;
    if (select md5(replace(p.prosrc, chr(13), ''))
        from pg_catalog.pg_proc p
        where p.oid = to_regprocedure(
            'fitmatch_vnext.classification_recovery_options(uuid)'
        )) <> recovery_md5 then
        raise exception 'FM_MUSINSA_R1_ROLLBACK_RECOVERY_CHANGED';
    end if;
end
$rollback$;

commit;
