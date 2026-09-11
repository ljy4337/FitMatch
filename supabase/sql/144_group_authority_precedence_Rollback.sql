begin;

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
  'classification_status','CONFIRMED','effective_source','CATEGORY_GROUP',
  'category_code',grouped->>'category_code',
  'garment_type_code',grouped->>'garment_type_code',
  'audience_code',grouped->>'audience_code',
  'sleeve_length_code',null,'lower_length_code',null,'body_length_code',null,
  'comparison_group_code',grouped->>'group_code',
  'comparison_group_policy_version',grouped->>'policy_version',
  'effective_authority_fingerprint',fingerprint,'override_revision',0
 );
end $function$;

update fitmatch_catalog.comparison_group_policies
set metadata=metadata-'group_authority_precedence',validated_at=now()
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
