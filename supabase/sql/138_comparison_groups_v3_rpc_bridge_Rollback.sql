begin;

create or replace function public.fitmatch_vnext_get_product_runtime(
  p_source_code text, p_source_product_key text
)
returns jsonb language sql set search_path = '' as $function$
  select fitmatch_vnext.get_product_runtime_for_swift(p_source_code,p_source_product_key)
$function$;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb language plpgsql set search_path = '' as $function$
declare result_value jsonb;
begin
  if p_request is not null
     and nullif(btrim(p_request->>'product_id'),'') is not null
     and p_request ? 'measurements' then
    return fitmatch_vnext.apply_linked_closet_snapshot_for_swift(p_request);
  end if;
  result_value := fitmatch_vnext.upsert_closet_item_for_swift(p_request);
  perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
    (result_value->>'item_id')::uuid,p_request
  );
  return result_value;
end
$function$;

create or replace function public.fitmatch_vnext_update_closet_item(
  p_closet_item_id uuid,p_request jsonb
)
returns jsonb language plpgsql set search_path = '' as $function$
declare result_value jsonb;
begin
  if p_request is not null
     and nullif(btrim(p_request->>'product_id'),'') is not null
     and p_request ? 'measurements' then
    return fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
      p_request,p_closet_item_id
    );
  end if;
  result_value := fitmatch_vnext.update_closet_item(p_closet_item_id,p_request);
  perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
    p_closet_item_id,p_request
  );
  return result_value;
end
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb language sql set search_path = '' as $function$
  select fitmatch_vnext.list_closet_items()
$function$;

create or replace function public.fitmatch_vnext_find_reference_candidates(
  p_target_product_id uuid,p_target_variant_id uuid default null
)
returns jsonb language sql set search_path = '' as $function$
  select fitmatch_vnext.find_reference_candidates(p_target_product_id,p_target_variant_id)
$function$;

create or replace function public.fitmatch_vnext_eligible_candidate_sizes(
  p_reference_closet_item_id uuid,p_target_product_id uuid,
  p_target_variant_id uuid,p_manual_explicit boolean default false
)
returns jsonb language sql set search_path = '' as $function$
  select fitmatch_vnext.eligible_candidate_sizes(
    p_reference_closet_item_id,p_target_product_id,p_target_variant_id,p_manual_explicit
  )
$function$;

drop function if exists public.fitmatch_vnext_list_comparison_groups();
drop function if exists fitmatch_vnext.closet_comparison_group(uuid);
drop function if exists fitmatch_vnext.apply_closet_comparison_group(uuid,text,boolean);

update fitmatch_catalog.comparison_group_policies
set status='validated',activated_at=null,
    metadata=jsonb_set(metadata,'{runtime_rpc_connected}','false'::jsonb,true)
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
