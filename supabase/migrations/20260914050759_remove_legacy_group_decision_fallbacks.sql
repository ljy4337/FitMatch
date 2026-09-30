begin;

create or replace function fitmatch_vnext.effective_target_classification(
  p_product_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $function$
declare
  product_row fitmatch_vnext.products%rowtype;
  resolved jsonb;
  grouped jsonb;
  status_value text;
  state_value text;
  source_value text;
  group_policy text;
  fingerprint text;
begin
  select * into product_row
  from fitmatch_vnext.products p
  where p.id=p_product_id;
  if not found then raise exception 'Product not found'; end if;

  resolved:=fitmatch_vnext.product_comparison_group(product_row.id);
  grouped:=fitmatch_vnext.comparison_group_tuple(product_row.id,null);

  if grouped is not null then
    select gt.comparison_policy_code into group_policy
    from fitmatch_vnext.garment_types gt
    where gt.garment_type_code=grouped->>'garment_type_code'
      and gt.category_code=grouped->>'category_code'
      and gt.is_active;
  end if;

  if grouped is not null and nullif(btrim(group_policy),'') is not null then
    status_value:='CONFIRMED';
    state_value:='CATEGORY_GROUP_CONFIRMED';
    source_value:='CATEGORY_GROUP';
  elsif resolved->>'status' in ('EXCLUDED','NOT_APPLICABLE') then
    status_value:='NOT_APPLICABLE';
    state_value:='GLOBAL_NOT_APPLICABLE';
    source_value:='GLOBAL_NOT_APPLICABLE';
  else
    status_value:='REVIEW_REQUIRED';
    state_value:='REVIEW_REQUIRED';
    source_value:='NONE';
  end if;

  fingerprint:=encode(extensions.digest(concat_ws('|',
    product_row.id::text,state_value,status_value,source_value,
    coalesce(grouped->>'group_code','none'),
    coalesce(grouped->>'policy_version','none'),
    coalesce(product_row.input_fingerprint,'none'),
    'fitmatch-vnext-group-only-effective-v1'
  ),'sha256'),'hex');

  return jsonb_strip_nulls(jsonb_build_object(
    'product_id',product_row.id,
    'state',state_value,
    'classification_status',status_value,
    'effective_source',source_value,
    'category_code',case when status_value='CONFIRMED'
      then grouped->>'category_code' end,
    'garment_type_code',case when status_value='CONFIRMED'
      then grouped->>'garment_type_code' end,
    'audience_code',coalesce(grouped->>'audience_code',
      nullif(product_row.audience_code,''),'UNKNOWN'),
    'sleeve_length_code',null,
    'lower_length_code',null,
    'body_length_code',null,
    'comparison_policy_code',case when status_value='CONFIRMED'
      then group_policy end,
    'comparison_group_code',case when status_value='CONFIRMED'
      then grouped->>'group_code' end,
    'comparison_group_policy_version',case when status_value='CONFIRMED'
      then grouped->>'policy_version' end,
    'product_structure_code',coalesce(
      nullif(product_row.product_structure_code,''),'UNKNOWN'
    ),
    'override_revision',0,
    'effective_authority_fingerprint',fingerprint,
    'effective_contract_version','fitmatch-vnext-group-only-effective-v1'
  ));
end
$function$;

create or replace function fitmatch_vnext.product_readiness(p_product_id uuid)
returns jsonb
language plpgsql
stable security invoker
set search_path=''
as $function$
declare
  effective_value jsonb;
begin
  effective_value:=fitmatch_vnext.effective_target_classification(p_product_id);
  return fitmatch_vnext.product_measurement_readiness(
    p_product_id,coalesce(effective_value,'{}'::jsonb)
  );
end
$function$;

create or replace function fitmatch_vnext.apply_closet_comparison_group(
  p_closet_item_id uuid,
  p_requested_group_code text,
  p_explicit boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  caller_id uuid:=auth.uid();
  item_row fitmatch_vnext.closet_items%rowtype;
  suggested jsonb;
  chosen_code text;
  chosen_source text;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into item_row
  from fitmatch_vnext.closet_items ci
  where ci.id=p_closet_item_id
    and ci.user_id=caller_id
    and ci.deleted_at is null;
  if not found then raise exception 'Closet item is missing or not owned'; end if;

  if p_explicit and p_requested_group_code is not null
     and p_requested_group_code not in ('A','B','C','D','E','F','G') then
    raise exception 'Unsupported comparison group';
  end if;

  if p_explicit and p_requested_group_code is not null then
    chosen_code:=p_requested_group_code;
    chosen_source:='USER_SELECTED';
  elsif not p_explicit and item_row.comparison_group_source='USER_SELECTED' then
    return jsonb_build_object(
      'group_code',item_row.comparison_group_code,
      'display_name',(select display_name
        from fitmatch_catalog.comparison_groups
        where group_code=item_row.comparison_group_code),
      'source',item_row.comparison_group_source,
      'policy_version',item_row.comparison_group_policy_version
    );
  else
    suggested:=fitmatch_vnext.product_comparison_group(item_row.product_id);
    chosen_code:=suggested->>'group_code';
    chosen_source:=case when chosen_code is null
      then null else 'RETAILER_CATEGORY' end;
  end if;

  update fitmatch_vnext.closet_items
  set comparison_group_code=chosen_code,
      comparison_group_source=chosen_source,
      comparison_group_policy_version=case when chosen_code is null then null
        else 'retailer-comparison-groups-v3-seven-20260911' end,
      updated_at=now()
  where id=item_row.id and user_id=caller_id;

  return jsonb_build_object(
    'group_code',chosen_code,
    'display_name',(select display_name
      from fitmatch_catalog.comparison_groups
      where group_code=chosen_code),
    'source',chosen_source,
    'policy_version',case when chosen_code is null then null
      else 'retailer-comparison-groups-v3-seven-20260911' end
  );
end
$function$;

do $verify$
declare
  definition text;
begin
  definition:=pg_get_functiondef(
    'fitmatch_vnext.effective_target_classification(uuid)'::regprocedure
  );
  if definition like '%effective_target_classification_detail_legacy%' then
    raise exception 'Legacy effective classification fallback remains';
  end if;

  definition:=pg_get_functiondef(
    'fitmatch_vnext.product_readiness(uuid)'::regprocedure
  );
  if definition like '%GLOBAL_CONFIRMED%'
     or definition like '%p.classification_status%' then
    raise exception 'Legacy product readiness fallback remains';
  end if;

  definition:=pg_get_functiondef(
    'fitmatch_vnext.apply_closet_comparison_group(uuid,text,boolean)'::regprocedure
  );
  if definition like '%legacy_comparison_group%' then
    raise exception 'Legacy Closet group fallback remains';
  end if;
end
$verify$;

commit;
