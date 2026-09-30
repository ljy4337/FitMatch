-- Target: hnkplvyegonlhumlejst, user-designated development database.
-- Repair the existing A/B allowance; no group mappings or user data are changed.
begin;
set local lock_timeout = '5s';
do $preflight$
begin
 if md5(pg_get_functiondef('fitmatch_vnext.comparison_domain_20260908(text)'::regprocedure)) <> 'ea6f7c236d3d8a2f67ffa4975e52cd01' then
  raise exception 'Comparison domain definition changed; review before applying';
 end if;
end $preflight$;
CREATE OR REPLACE FUNCTION fitmatch_vnext.comparison_domain_20260908(p_policy text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
SELECT CASE
 WHEN p_policy IN ('anorak','base_layer_top','blazer','blouson','bodysuit_top',
 'cardigan','coat','fleece_jacket','homewear_top','hoodie','jacket','knit_sweater',
 'knit_vest','ma1','mouton','outer_vest','polo_shirt','puffer_jacket','puffer_vest',
 'shirt_blouse','sleeveless_tshirt','sports_top','sweatshirt','tank_top','tshirt',
 'windbreaker','zip_hoodie','unclassified_outerwear') THEN 'UPPER_BODY'
 WHEN p_policy IN ('homewear_bottom','leggings','skirt','standard_pants') THEN 'LOWER_BODY'
 WHEN p_policy='dress' THEN 'FULL_BODY'
 WHEN p_policy IN ('men_briefs','men_trunks','men_undershirt','women_bra',
 'women_camisole','women_panty','women_slip') THEN 'OTHER'
 ELSE 'UNKNOWN' END;
$function$
;
do $postflight$
begin
 if fitmatch_vnext.comparison_domain_20260908('unclassified_outerwear') <> 'UPPER_BODY'
 or fitmatch_vnext.comparison_domain_20260908('standard_pants') <> 'LOWER_BODY'
 or fitmatch_vnext.comparison_domain_20260908('unknown') <> 'UNKNOWN' then
  raise exception 'Comparison domain postflight failed';
 end if;
end $postflight$;
commit;
