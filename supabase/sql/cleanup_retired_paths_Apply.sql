-- Approved cleanup: archived non-current legacy history; current records and user data retained.
begin;
lock table fitmatch_catalog.product_classification_history in share row exclusive mode;
do $guard$
begin
  if md5(pg_get_functiondef('fitmatch_vnext.effective_target_classification_detail_legacy(uuid)'::regprocedure)) <> '42a54c94a96fe72c829d07a860fc7f0b' then raise exception 'Concurrent function change: effective_target_classification_detail_legacy'; end if;
  if md5(pg_get_functiondef('fitmatch_vnext.legacy_comparison_group(text)'::regprocedure)) <> '7e3719f2e843a80eb33722d901b51c5e' then raise exception 'Concurrent function change: legacy_comparison_group'; end if;
  if md5(pg_get_functiondef('fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean)'::regprocedure)) <> 'ccb1b23c917046856da515765e1ee5fa' then raise exception 'Concurrent function change: authorize_comparison'; end if;
  if md5(pg_get_functiondef('fitmatch_vnext.product_readiness_with_context(uuid,jsonb)'::regprocedure)) <> '15b021520371aab2725e9cd5e8714578' then raise exception 'Concurrent function change: product_readiness_with_context'; end if;
  if exists(select 1 from pg_proc p where p.pronamespace in ('fitmatch_vnext'::regnamespace,'fitmatch_catalog'::regnamespace,'public'::regnamespace) and p.proname <> 'effective_target_classification_detail_legacy' and p.prosrc ~ E'\\meffective_target_classification_detail_legacy\\s*\\(') then raise exception 'New caller for effective_target_classification_detail_legacy; re-audit'; end if;
  if exists(select 1 from pg_proc p where p.pronamespace in ('fitmatch_vnext'::regnamespace,'fitmatch_catalog'::regnamespace,'public'::regnamespace) and p.proname <> 'legacy_comparison_group' and p.prosrc ~ E'\\mlegacy_comparison_group\\s*\\(') then raise exception 'New caller for legacy_comparison_group; re-audit'; end if;
  if exists(select 1 from pg_proc p where p.pronamespace in ('fitmatch_vnext'::regnamespace,'fitmatch_catalog'::regnamespace,'public'::regnamespace) and p.proname <> 'authorize_comparison' and p.prosrc ~ E'\\mauthorize_comparison\\s*\\(') then raise exception 'New caller for authorize_comparison; re-audit'; end if;
  if (select count(*) from fitmatch_catalog.product_classification_history where not is_current) <> 118 or (select md5(coalesce(jsonb_agg(to_jsonb(h) order by h.id)::text,'[]')) from fitmatch_catalog.product_classification_history h where not is_current) <> '331f4f521fd5a0e1c001524a7d8cd4a4' then raise exception 'Archived history preimage changed'; end if;
end
$guard$;

CREATE OR REPLACE FUNCTION fitmatch_vnext.product_readiness_with_context(p_product_id uuid, p_effective_classification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
    unit_value jsonb;
begin
    unit_value := fitmatch_vnext.product_comparison_unit_decision(p_product_id);
    if not coalesce((unit_value ->> 'eligible')::boolean, false) then
        return jsonb_build_object(
            'product_id', p_product_id,
            'ready', false,
            'status', case when unit_value ->> 'reason' in (
              'MIXED_GARMENT_SET','MULTIPLE_COMPONENT_MEASUREMENT_CONTRACT'
            ) then 'NOT_APPLICABLE' else 'CLASSIFICATION_REQUIRED' end,
            'reason', unit_value ->> 'reason',
            'comparison_unit', unit_value,
            'readiness_version', 'fitmatch-vnext-readiness-v3'
        );
    end if;
    return fitmatch_vnext.product_measurement_readiness(
        p_product_id, p_effective_classification
    );
end
$function$
;
drop function fitmatch_vnext.effective_target_classification_detail_legacy(uuid) restrict;
drop function fitmatch_vnext.legacy_comparison_group(text) restrict;
drop function fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean) restrict;
delete from fitmatch_catalog.product_classification_history where not is_current;
commit;
