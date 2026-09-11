-- Bridges the seven-group policy to existing public Swift RPCs.
-- Existing RPC names and existing JSON fields are preserved.

begin;

create or replace function fitmatch_vnext.apply_closet_comparison_group(
  p_closet_item_id uuid,
  p_requested_group_code text,
  p_explicit boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  item_row fitmatch_vnext.closet_items%rowtype;
  suggested jsonb;
  chosen_code text;
  chosen_source text;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into item_row
  from fitmatch_vnext.closet_items ci
  where ci.id=p_closet_item_id and ci.user_id=caller_id and ci.deleted_at is null;
  if not found then raise exception 'Closet item is missing or not owned'; end if;

  if p_explicit and p_requested_group_code is not null
     and p_requested_group_code not in ('A','B','C','D','E','F','G') then
    raise exception 'Unsupported comparison group';
  end if;

  if p_explicit and p_requested_group_code is not null then
    chosen_code := p_requested_group_code;
    chosen_source := 'USER_SELECTED';
  elsif not p_explicit and item_row.comparison_group_source='USER_SELECTED' then
    return jsonb_build_object(
      'group_code', item_row.comparison_group_code,
      'display_name', (select display_name from fitmatch_catalog.comparison_groups
        where group_code=item_row.comparison_group_code),
      'source', item_row.comparison_group_source,
      'policy_version', item_row.comparison_group_policy_version
    );
  else
    suggested := fitmatch_vnext.product_comparison_group(item_row.product_id);
    chosen_code := suggested->>'group_code';
    if chosen_code is not null then
      chosen_source := 'RETAILER_CATEGORY';
    else
      chosen_code := fitmatch_vnext.legacy_comparison_group(item_row.garment_type_code);
      chosen_source := case when chosen_code is null then null else 'LEGACY_DERIVED' end;
    end if;
  end if;

  update fitmatch_vnext.closet_items
  set comparison_group_code=chosen_code,
      comparison_group_source=chosen_source,
      comparison_group_policy_version=case when chosen_code is null then null
        else 'retailer-comparison-groups-v3-seven-20260911' end,
      updated_at=now()
  where id=item_row.id and user_id=caller_id;

  return jsonb_build_object(
    'group_code', chosen_code,
    'display_name', (select display_name from fitmatch_catalog.comparison_groups
      where group_code=chosen_code),
    'source', chosen_source,
    'policy_version', case when chosen_code is null then null
      else 'retailer-comparison-groups-v3-seven-20260911' end
  );
end
$function$;

revoke all on function fitmatch_vnext.apply_closet_comparison_group(uuid,text,boolean)
  from public, anon;
grant execute on function fitmatch_vnext.apply_closet_comparison_group(uuid,text,boolean)
  to authenticated, service_role;

create or replace function fitmatch_vnext.closet_comparison_group(p_closet_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  item_row fitmatch_vnext.closet_items%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into item_row from fitmatch_vnext.closet_items ci
  where ci.id=p_closet_item_id and ci.user_id=caller_id and ci.deleted_at is null;
  if not found then return null; end if;
  return jsonb_build_object(
    'group_code', item_row.comparison_group_code,
    'display_name', (select display_name from fitmatch_catalog.comparison_groups
      where group_code=item_row.comparison_group_code),
    'source', item_row.comparison_group_source,
    'policy_version', item_row.comparison_group_policy_version
  );
end
$function$;

revoke all on function fitmatch_vnext.closet_comparison_group(uuid) from public, anon;
grant execute on function fitmatch_vnext.closet_comparison_group(uuid)
  to authenticated, service_role;

create or replace function public.fitmatch_vnext_list_comparison_groups()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'group_code', group_code,
    'display_name', display_name,
    'description', description,
    'display_order', display_order
  ) order by display_order)
  from fitmatch_catalog.comparison_groups where active), '[]'::jsonb);
end
$function$;

revoke all on function public.fitmatch_vnext_list_comparison_groups() from public, anon;
grant execute on function public.fitmatch_vnext_list_comparison_groups()
  to authenticated, service_role;

create or replace function public.fitmatch_vnext_get_product_runtime(
  p_source_code text, p_source_product_key text
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  result_value jsonb;
  product_id_value uuid;
begin
  result_value := fitmatch_vnext.get_product_runtime_for_swift(
    p_source_code, p_source_product_key
  );
  select p.id into product_id_value from fitmatch_vnext.products p
  where p.source_code=p_source_code and p.source_product_key=p_source_product_key;
  return result_value || jsonb_build_object(
    'comparison_group', fitmatch_vnext.product_comparison_group(product_id_value)
  );
end
$function$;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  result_value jsonb;
  item_id_value uuid;
  group_value jsonb;
begin
  if p_request is not null
     and nullif(btrim(p_request->>'product_id'),'') is not null
     and p_request ? 'measurements' then
    result_value := fitmatch_vnext.apply_linked_closet_snapshot_for_swift(p_request);
  else
    result_value := fitmatch_vnext.upsert_closet_item_for_swift(p_request);
    perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
      (result_value->>'item_id')::uuid, p_request
    );
  end if;
  item_id_value := coalesce(
    (result_value->>'closet_item_id')::uuid,
    (result_value->>'item_id')::uuid
  );
  group_value := fitmatch_vnext.apply_closet_comparison_group(
    item_id_value,
    nullif(btrim(p_request->>'comparison_group_code'),''),
    p_request ? 'comparison_group_code'
  );
  return result_value || jsonb_build_object('comparison_group',group_value);
end
$function$;

create or replace function public.fitmatch_vnext_update_closet_item(
  p_closet_item_id uuid, p_request jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  result_value jsonb;
  group_value jsonb;
begin
  if p_request is not null
     and nullif(btrim(p_request->>'product_id'),'') is not null
     and p_request ? 'measurements' then
    result_value := fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
      p_request, p_closet_item_id
    );
  else
    result_value := fitmatch_vnext.update_closet_item(p_closet_item_id,p_request);
    perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
      p_closet_item_id,p_request
    );
  end if;
  group_value := fitmatch_vnext.apply_closet_comparison_group(
    p_closet_item_id,
    nullif(btrim(p_request->>'comparison_group_code'),''),
    p_request ? 'comparison_group_code'
  );
  return result_value || jsonb_build_object('comparison_group',group_value);
end
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare result_value jsonb;
begin
  result_value := fitmatch_vnext.list_closet_items();
  return coalesce((
    select jsonb_agg(item || jsonb_build_object(
      'comparison_group',fitmatch_vnext.closet_comparison_group((item->>'id')::uuid)
    ) order by ordinal)
    from jsonb_array_elements(result_value) with ordinality rows(item,ordinal)
  ),'[]'::jsonb);
end
$function$;

create or replace function public.fitmatch_vnext_find_reference_candidates(
  p_target_product_id uuid, p_target_variant_id uuid default null
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  result_value jsonb;
  target_group jsonb;
  candidates_value jsonb;
  blocked_value jsonb;
begin
  result_value := fitmatch_vnext.find_reference_candidates(
    p_target_product_id,p_target_variant_id
  );
  target_group := fitmatch_vnext.product_comparison_group(p_target_product_id);

  select coalesce(jsonb_agg(enriched order by
      case when enriched->'comparison_group'->>'group_code'=target_group->>'group_code'
             and coalesce((enriched->>'is_current_reference')::boolean,false) then 0
           when enriched->'comparison_group'->>'group_code'=target_group->>'group_code' then 1
           when coalesce((enriched->>'is_current_reference')::boolean,false) then 2
           else 3 end,
      ordinal), '[]'::jsonb)
    into candidates_value
  from (
    select item || jsonb_build_object(
      'comparison_group',fitmatch_vnext.closet_comparison_group(
        (item->>'closet_item_id')::uuid
      ),
      'same_comparison_group',
        fitmatch_vnext.closet_comparison_group((item->>'closet_item_id')::uuid)
          ->>'group_code'=target_group->>'group_code'
    ) as enriched, ordinal
    from jsonb_array_elements(coalesce(result_value->'candidates','[]'::jsonb))
      with ordinality rows(item,ordinal)
  ) q;

  select coalesce(jsonb_agg(item || jsonb_build_object(
      'comparison_group',fitmatch_vnext.closet_comparison_group(
        (item->>'closet_item_id')::uuid
      )
    ) order by ordinal),'[]'::jsonb)
    into blocked_value
  from jsonb_array_elements(coalesce(result_value->'blocked','[]'::jsonb))
    with ordinality rows(item,ordinal);

  return result_value || jsonb_build_object(
    'comparison_group',target_group,
    'candidates',candidates_value,
    'blocked',blocked_value,
    'group_selection_policy','same_group_reference_then_same_group_then_all'
  );
end
$function$;

create or replace function public.fitmatch_vnext_eligible_candidate_sizes(
  p_reference_closet_item_id uuid,
  p_target_product_id uuid,
  p_target_variant_id uuid,
  p_manual_explicit boolean default false
)
returns jsonb
language sql
set search_path = ''
as $function$
  select fitmatch_vnext.eligible_candidate_sizes(
    p_reference_closet_item_id,p_target_product_id,p_target_variant_id,p_manual_explicit
  ) || jsonb_build_object(
    'reference_comparison_group',
      fitmatch_vnext.closet_comparison_group(p_reference_closet_item_id),
    'target_comparison_group',
      fitmatch_vnext.product_comparison_group(p_target_product_id)
  )
$function$;

update fitmatch_catalog.comparison_group_policies
set status='validated', activated_at=null,
    metadata=jsonb_set(
      jsonb_set(metadata,'{runtime_rpc_connected}','false'::jsonb,true),
      '{rpc_bridge_installed}','true'::jsonb,true
    )
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
