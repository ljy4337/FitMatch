-- Manual rollback for 132_zara_v2_current_r3_Apply.sql.
-- Restores the 129 u904-r3 classifier and leaves its Uniqlo rules intact.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $rollback$
declare
    fn_oid oid := to_regprocedure('fitmatch_vnext.classification_decision(text,text)');
    ddl text;
    live_body text;
    baseline_security_definer boolean;
    baseline_acl aclitem[];
    baseline_config text[];
    baseline_owner oid;
    recovery_md5 text;
    provider_anchor constant text :=
        '{"version":"fitmatch-provider-api-policy-20260910-u904-zara-v2-r1"';
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
        raise exception 'FM_ZARA_V2_ROLLBACK_MISSING_FUNCTION';
    end if;
    select pg_catalog.pg_get_functiondef(p.oid), p.prosrc,
           p.prosecdef, p.proacl, p.proconfig, p.proowner
      into ddl, live_body, baseline_security_definer, baseline_acl,
           baseline_config, baseline_owner
      from pg_catalog.pg_proc p where p.oid = fn_oid;
    select md5(replace(p.prosrc, chr(13), '')) into recovery_md5
      from pg_catalog.pg_proc p
     where p.oid = to_regprocedure(
         'fitmatch_vnext.classification_recovery_options(uuid)'
     );

    if strpos(live_body, 'fitmatch-provider-api-policy-20260910-u904-zara-v2-r1') = 0 then
        if strpos(live_body, 'fitmatch-provider-api-policy-20260910-u904-r3') > 0
           and strpos(live_body, 'provider_parent_with_selected_variant') = 0 then
            return;
        end if;
        raise exception 'FM_ZARA_V2_ROLLBACK_PREIMAGE_DRIFT';
    end if;
    if recovery_md5 <> 'd01db739db96a46d5725fbfb8d215e61' then
        raise exception 'FM_ZARA_V2_ROLLBACK_RECOVERY_DRIFT: %', recovery_md5;
    end if;

    if (length(ddl) - length(replace(ddl, provider_anchor, '')))
       / length(provider_anchor) <> 1 then
        raise exception 'FM_ZARA_V2_ROLLBACK_POLICY_ANCHOR_COUNT';
    end if;
    provider_start := strpos(ddl, provider_anchor);
    provider_end_rel := strpos(substring(ddl from provider_start), '$policy$::jsonb;');
    provider_json_text := substring(ddl from provider_start for provider_end_rel - 1);
    provider_policy := provider_json_text::jsonb;
    if provider_policy->>'version'
          <> 'fitmatch-provider-api-policy-20260910-u904-zara-v2-r1'
       or jsonb_typeof(provider_policy->'rules') <> 'array'
       or jsonb_array_length(provider_policy->'rules') <> 248
       or (select count(*) from jsonb_array_elements(provider_policy->'rules') r
           where r->>'rule_id' like 'zara.v2.%') <> 5 then
        raise exception 'FM_ZARA_V2_ROLLBACK_POLICY_DRIFT';
    end if;
    select jsonb_agg(r order by ord) into filtered_rules
      from jsonb_array_elements(provider_policy->'rules') with ordinality t(r,ord)
     where r->>'rule_id' not like 'zara.v2.%';
    if jsonb_array_length(filtered_rules) <> 243 then
        raise exception 'FM_ZARA_V2_ROLLBACK_RULE_COUNT=%',
            jsonb_array_length(filtered_rules);
    end if;
    provider_policy := jsonb_set(provider_policy, '{rules}', filtered_rules, true);
    provider_policy := jsonb_set(
        provider_policy, '{version}',
        to_jsonb('fitmatch-provider-api-policy-20260910-u904-r3'::text), true
    );
    new_text := '{"version":"fitmatch-provider-api-policy-20260910-u904-r3","rules":'
                || (provider_policy->'rules')::text || '}';
    ddl := replace(ddl, provider_json_text, new_text);

    old_text := $$'$.product.detail.colors[productId='||api_selected_key||'].description'$$;
    new_text := $$'$.product.detail.colors[productId='||product_row.source_product_key||'].description'$$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_ZARA_V2_ROLLBACK_SOURCE_PATH_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    old_text := $old$   ELSIF product_row.source_code='zara' THEN
    api_product:=envelope#>'{details,product}';
    IF envelope->>'contract_version'='fitmatch-retailer-api-v2' THEN
      api_selected_key:=envelope->>'selected_variant_key';
      IF envelope->>'identity_scheme' IS DISTINCT FROM 'provider_parent_with_selected_variant'
         OR coalesce(api_selected_key,'') !~ '^[0-9]+$'
         OR api_product->>'type' IS DISTINCT FROM 'Product'
         OR api_product->>'id' IS DISTINCT FROM product_row.source_product_key
         OR jsonb_typeof(api_product#>'{detail,colors}') IS DISTINCT FROM 'array'
         OR (SELECT count(*) FROM jsonb_array_elements(api_product#>'{detail,colors}') c
             WHERE c->>'productId'=api_selected_key)<>1
         OR envelope#>>'{requests,details,url}' !~ ('[?&]v1='||api_selected_key||'(&|$)')
         OR envelope#>>'{requests,details,url}' !~ '[?&]ajax=true(&|$)'
         OR ((envelope ? 'measurements') IS DISTINCT FROM
             ((envelope#>'{requests,measurements}') IS NOT NULL))
         OR (envelope ? 'measurements' AND (
             jsonb_typeof(envelope->'measurements') IS DISTINCT FROM 'object'
             OR jsonb_typeof(envelope#>'{requests,measurements}') IS DISTINCT FROM 'object'
             OR envelope#>>'{requests,measurements,http_status}' IS DISTINCT FROM '200'
             OR envelope#>>'{requests,measurements,url}' !~
                ('/product/'||api_selected_key||'/size-measure-guide([?]|$)')))
      THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ZARA_API_V2_IDENTITY_OR_SHAPE'; END IF;
    ELSE
      api_selected_key:=product_row.source_product_key;
      IF api_product->>'type' IS DISTINCT FROM 'Product'
         OR jsonb_typeof(api_product#>'{detail,colors}') IS DISTINCT FROM 'array'
         OR (SELECT count(*) FROM jsonb_array_elements(api_product#>'{detail,colors}') c
             WHERE c->>'productId'=product_row.source_product_key)<>1
      THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ZARA_API_IDENTITY_OR_SHAPE'; END IF;
    END IF;
    SELECT c INTO api_selected FROM jsonb_array_elements(api_product#>'{detail,colors}') c
      WHERE c->>'productId'=api_selected_key;
$old$;
    new_text := $new$   ELSIF product_row.source_code='zara' THEN
    api_product:=envelope#>'{details,product}';
    IF api_product->>'type' IS DISTINCT FROM 'Product'
       OR jsonb_typeof(api_product#>'{detail,colors}') IS DISTINCT FROM 'array'
       OR (SELECT count(*) FROM jsonb_array_elements(api_product#>'{detail,colors}') c
           WHERE c->>'productId'=product_row.source_product_key)<>1
    THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ZARA_API_IDENTITY_OR_SHAPE'; END IF;
    SELECT c INTO api_selected FROM jsonb_array_elements(api_product#>'{detail,colors}') c
      WHERE c->>'productId'=product_row.source_product_key;
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_ZARA_V2_ROLLBACK_IDENTITY_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    old_text := $old$   api_audience text; api_components jsonb := '[]'::jsonb; api_measure_codes jsonb;
   api_selected_key text;
$old$;
    new_text := $new$   api_audience text; api_components jsonb := '[]'::jsonb; api_measure_codes jsonb;
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_ZARA_V2_ROLLBACK_DECLARATION_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    old_text := $old$ IF jsonb_typeof(envelope) IS DISTINCT FROM 'object'
    OR envelope->>'contract_version' IS NULL
    OR envelope->>'contract_version' NOT IN (
         'fitmatch-retailer-api-v1','fitmatch-retailer-api-v2')
    OR (envelope->>'contract_version'='fitmatch-retailer-api-v2'
        AND product_row.source_code<>'zara')
    OR envelope->>'source_code' IS DISTINCT FROM product_row.source_code
$old$;
    new_text := $new$ IF jsonb_typeof(envelope) IS DISTINCT FROM 'object'
    OR envelope->>'contract_version' IS DISTINCT FROM 'fitmatch-retailer-api-v1'
    OR envelope->>'source_code' IS DISTINCT FROM product_row.source_code
$new$;
    hit_count := (length(ddl) - length(replace(ddl, old_text, ''))) / length(old_text);
    if hit_count <> 1 then
        raise exception 'FM_ZARA_V2_ROLLBACK_CONTRACT_TARGET_COUNT=%', hit_count;
    end if;
    ddl := replace(ddl, old_text, new_text);

    execute ddl;

    if not exists (
        select 1 from pg_catalog.pg_proc p
         where p.oid = fn_oid
           and strpos(p.prosrc,
               'fitmatch-provider-api-policy-20260910-u904-r3') > 0
           and strpos(p.prosrc, 'zara.v2.') = 0
           and strpos(p.prosrc, 'provider_parent_with_selected_variant') = 0
           and strpos(p.prosrc, 'fitmatch-retailer-api-v2') = 0
           and strpos(p.prosrc, 'uniqlo.u904.') > 0
           and p.prosecdef is not distinct from baseline_security_definer
           and p.proacl is not distinct from baseline_acl
           and p.proconfig is not distinct from baseline_config
           and p.proowner is not distinct from baseline_owner
    ) then
        raise exception 'FM_ZARA_V2_ROLLBACK_POSTCHECK_FAILED';
    end if;
    if (select md5(replace(p.prosrc, chr(13), ''))
          from pg_catalog.pg_proc p
         where p.oid = to_regprocedure(
             'fitmatch_vnext.classification_recovery_options(uuid)'
         )) <> recovery_md5 then
        raise exception 'FM_ZARA_V2_ROLLBACK_RECOVERY_CHANGED';
    end if;
end
$rollback$;

commit;
