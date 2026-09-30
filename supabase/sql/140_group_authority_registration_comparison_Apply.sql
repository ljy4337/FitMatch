-- Makes a resolved seven-group category sufficient for linked registration
-- and for the existing size/comparison calculation pipeline.

begin;

insert into fitmatch_vnext.garment_types (
  garment_type_code,category_code,comparison_policy_code,display_name,
  uses_sleeve_length,uses_lower_length,uses_body_length,sort_order,is_active
)
values
 ('comparison_group_top','tops','tshirt','상의 그룹',false,false,false,900,true),
 ('comparison_group_outerwear','outerwear','unclassified_outerwear','아우터 그룹',false,false,false,901,true),
 ('comparison_group_bottom','bottoms','standard_pants','바지 그룹',false,false,false,902,true),
 ('comparison_group_skirt','skirts','skirt','스커트 그룹',false,false,false,903,true),
 ('comparison_group_onepiece','dresses','dress','원피스·한벌옷 그룹',false,false,false,904,true),
 ('comparison_group_innerwear','underwear','generic_underwear','이너웨어 그룹',false,false,false,905,true),
 ('comparison_group_homewear','homewear','homewear_set','홈웨어·파자마 그룹',false,false,false,906,true)
on conflict (garment_type_code) do update set
 category_code=excluded.category_code,
 comparison_policy_code=excluded.comparison_policy_code,
 display_name=excluded.display_name,
 uses_sleeve_length=excluded.uses_sleeve_length,
 uses_lower_length=excluded.uses_lower_length,
 uses_body_length=excluded.uses_body_length,
 sort_order=excluded.sort_order,is_active=true,updated_at=now();

create or replace function fitmatch_vnext.comparison_group_tuple(
  p_product_id uuid,p_requested_group_code text default null
)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
 p fitmatch_vnext.products%rowtype;
 resolved jsonb;
 code text;
 garment text;
 category text;
begin
 select * into p from fitmatch_vnext.products where id=p_product_id;
 if not found then return null; end if;
 resolved:=fitmatch_vnext.product_comparison_group(p.id);
 code:=coalesce(nullif(btrim(p_requested_group_code),''),resolved->>'group_code');
 if code not in ('A','B','C','D','E','F','G') then return null; end if;
 garment:=case code
  when 'A' then 'comparison_group_top'
  when 'B' then 'comparison_group_outerwear'
  when 'C' then 'comparison_group_bottom'
  when 'D' then 'comparison_group_skirt'
  when 'E' then 'comparison_group_onepiece'
  when 'F' then 'comparison_group_innerwear'
  when 'G' then 'comparison_group_homewear' end;
 select category_code into category from fitmatch_vnext.garment_types
 where garment_type_code=garment;
 return jsonb_build_object(
  'group_code',code,'category_code',category,'garment_type_code',garment,
  'audience_code',case when p.audience_code in ('MEN','WOMEN','UNISEX','KIDS','BABY')
    then p.audience_code else 'UNKNOWN' end,
  'sleeve_length_code',null,'lower_length_code',null,'body_length_code',null,
  'policy_version','retailer-comparison-groups-v3-seven-20260911'
 );
end $function$;

revoke all on function fitmatch_vnext.comparison_group_tuple(uuid,text) from public,anon;
grant execute on function fitmatch_vnext.comparison_group_tuple(uuid,text) to authenticated,service_role;

do $rename$
begin
 if to_regprocedure('fitmatch_vnext.effective_target_classification_detail_legacy(uuid)') is null then
  alter function fitmatch_vnext.effective_target_classification(uuid)
    rename to effective_target_classification_detail_legacy;
 end if;
end $rename$;

create or replace function fitmatch_vnext.effective_target_classification(p_product_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
 detail jsonb;
 grouped jsonb;
 fingerprint text;
begin
 detail:=fitmatch_vnext.effective_target_classification_detail_legacy(p_product_id);
 if detail->>'classification_status'='CONFIRMED' then return detail; end if;
 grouped:=fitmatch_vnext.comparison_group_tuple(p_product_id,null);
 if grouped is null then return detail; end if;
 fingerprint:=encode(extensions.digest(concat_ws('|',p_product_id::text,
   grouped->>'group_code',grouped->>'policy_version'),'sha256'),'hex');
 return detail || jsonb_build_object(
  'classification_status','CONFIRMED',
  'effective_source','CATEGORY_GROUP',
  'category_code',grouped->>'category_code',
  'garment_type_code',grouped->>'garment_type_code',
  'audience_code',grouped->>'audience_code',
  'sleeve_length_code',null,'lower_length_code',null,'body_length_code',null,
  'comparison_group_code',grouped->>'group_code',
  'comparison_group_policy_version',grouped->>'policy_version',
  'effective_authority_fingerprint',fingerprint,
  'override_revision',0
 );
end $function$;

revoke all on function fitmatch_vnext.effective_target_classification(uuid) from public,anon;
grant execute on function fitmatch_vnext.effective_target_classification(uuid)
 to authenticated,service_role;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb language plpgsql set search_path='' as $function$
declare
 request_value jsonb:=p_request;
 result_value jsonb;
 item_id_value uuid;
 product_id_value uuid;
 group_tuple jsonb;
 generated_group_tuple boolean:=false;
 group_value jsonb;
begin
 if request_value is not null
    and nullif(btrim(request_value->>'product_id'),'') is not null
    and request_value ? 'measurements' then
  product_id_value:=(request_value->>'product_id')::uuid;
  if not request_value ? 'closet_classification_override' then
   group_tuple:=fitmatch_vnext.comparison_group_tuple(
    product_id_value,nullif(btrim(request_value->>'comparison_group_code'),'')
   );
   if group_tuple is null then raise exception 'Comparison group selection required'; end if;
   request_value:=jsonb_set(request_value,'{closet_classification_override}',
    jsonb_build_object(
     'audience_code',group_tuple->>'audience_code',
     'category_code',group_tuple->>'category_code',
     'garment_type_code',group_tuple->>'garment_type_code'
    ),true);
   generated_group_tuple:=true;
  end if;
  result_value:=fitmatch_vnext.apply_linked_closet_snapshot_for_swift(request_value);
 else
  result_value:=fitmatch_vnext.upsert_closet_item_for_swift(request_value);
  perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
   (result_value->>'item_id')::uuid,request_value);
 end if;
 item_id_value:=coalesce((result_value->>'closet_item_id')::uuid,
                         (result_value->>'item_id')::uuid);
 if generated_group_tuple then
  update fitmatch_vnext.closet_items set
   classification_source=case when p_request ? 'comparison_group_code'
     then 'USER_EDITED' else 'BACKEND' end,
   classification_resolver_version='comparison-group-v3',
   closet_detail_code_snapshot=null
  where id=item_id_value and user_id=auth.uid();
 end if;
 group_value:=fitmatch_vnext.apply_closet_comparison_group(item_id_value,
  nullif(btrim(p_request->>'comparison_group_code'),''),
  p_request ? 'comparison_group_code');
 return result_value || jsonb_build_object('comparison_group',group_value);
end $function$;

create or replace function public.fitmatch_vnext_update_closet_item(
 p_closet_item_id uuid,p_request jsonb
)
returns jsonb language plpgsql set search_path='' as $function$
declare
 request_value jsonb:=p_request;
 result_value jsonb;
 product_id_value uuid;
 group_tuple jsonb;
 generated_group_tuple boolean:=false;
 group_value jsonb;
begin
 if request_value is not null
    and nullif(btrim(request_value->>'product_id'),'') is not null
    and request_value ? 'measurements' then
  product_id_value:=(request_value->>'product_id')::uuid;
  if not request_value ? 'closet_classification_override' then
   group_tuple:=fitmatch_vnext.comparison_group_tuple(product_id_value,
    nullif(btrim(request_value->>'comparison_group_code'),''));
   if group_tuple is null then raise exception 'Comparison group selection required'; end if;
   request_value:=jsonb_set(request_value,'{closet_classification_override}',
    jsonb_build_object(
     'audience_code',group_tuple->>'audience_code',
     'category_code',group_tuple->>'category_code',
     'garment_type_code',group_tuple->>'garment_type_code'
    ),true);
   generated_group_tuple:=true;
  end if;
  result_value:=fitmatch_vnext.apply_linked_closet_snapshot_for_swift(
   request_value,p_closet_item_id);
 else
  result_value:=fitmatch_vnext.update_closet_item(p_closet_item_id,request_value);
  perform fitmatch_vnext.set_closet_detail_snapshot_for_swift(
   p_closet_item_id,request_value);
 end if;
 if generated_group_tuple then
  update fitmatch_vnext.closet_items set
   classification_source=case when p_request ? 'comparison_group_code'
     then 'USER_EDITED' else 'BACKEND' end,
   classification_resolver_version='comparison-group-v3',
   closet_detail_code_snapshot=null
  where id=p_closet_item_id and user_id=auth.uid();
 end if;
 group_value:=fitmatch_vnext.apply_closet_comparison_group(p_closet_item_id,
  nullif(btrim(p_request->>'comparison_group_code'),''),
  p_request ? 'comparison_group_code');
 return result_value || jsonb_build_object('comparison_group',group_value);
end $function$;

update fitmatch_catalog.comparison_group_policies
set metadata=jsonb_set(metadata,'{group_authority_bridge}','true'::jsonb,true)
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
