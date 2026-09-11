begin;

create or replace function fitmatch_vnext.effective_target_classification(p_product_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $function$
declare
  detail jsonb;
  grouped jsonb;
  fingerprint text;
  group_policy text;
begin
  detail:=fitmatch_vnext.effective_target_classification_detail_legacy(p_product_id);
  grouped:=fitmatch_vnext.comparison_group_tuple(p_product_id,null);

  -- A known comparison group is the comparison authority regardless of the
  -- legacy detailed classifier state. The legacy state remains in the payload
  -- for diagnostics and is not rewritten in products.
  if grouped is null then return detail; end if;

  select gt.comparison_policy_code into group_policy
  from fitmatch_vnext.garment_types gt
  where gt.garment_type_code = grouped->>'garment_type_code'
    and gt.category_code = grouped->>'category_code'
    and gt.is_active;
  if nullif(btrim(group_policy),'') is null then
    raise exception 'Comparison group policy is missing';
  end if;

  fingerprint:=encode(extensions.digest(concat_ws('|',p_product_id::text,
    grouped->>'group_code',grouped->>'policy_version'),'sha256'),'hex');
  return detail || jsonb_build_object(
    'detail_classification_status',detail->>'classification_status',
    'classification_status','CONFIRMED',
    'effective_source','CATEGORY_GROUP',
    'comparison_policy_code',group_policy,
    'category_code',grouped->>'category_code',
    'garment_type_code',grouped->>'garment_type_code',
    'audience_code',grouped->>'audience_code',
    'sleeve_length_code',null,'lower_length_code',null,'body_length_code',null,
    'comparison_group_code',grouped->>'group_code',
    'comparison_group_policy_version',grouped->>'policy_version',
    'effective_authority_fingerprint',fingerprint,
    'override_revision',0
  );
end
$function$;

commit;

