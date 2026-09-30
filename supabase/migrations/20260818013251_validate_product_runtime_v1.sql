begin;

set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtext('fitmatch:product-runtime-validation-v1'));

-- The original 5,026-case artifact contained four internally contradictory
-- family values. Keep the cases, but correct their expected canonical family.
update fitmatch_qa.classification_cases
set expected_comparison_family=case
      when case_key in ('uniqlo:E482204','uniqlo:E489180') then 'underwear'
      else 'pants' end,
    result_payload=jsonb_set(
      jsonb_set(result_payload,'{garmentFamily}',to_jsonb(case
        when case_key in ('uniqlo:E482204','uniqlo:E489180') then 'underwear'
        else 'pants' end),true),
      '{canonicalSyncVersion}',to_jsonb('db-runtime-2026-08-18-v1'::text),true
    )
where case_key in (
  'uniqlo:E482204','uniqlo:E489180','uniqlo:E488163','uniqlo:E488426'
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='product_measurements_comparison_identity_check'
      and conrelid='fitmatch_catalog.product_measurements'::regclass
  ) then
    alter table fitmatch_catalog.product_measurements
      add constraint product_measurements_comparison_identity_check
      check (not is_comparable or (
        measurement_kind is not null and comparison_basis is not null
      )) not valid;
    alter table fitmatch_catalog.product_measurements
      validate constraint product_measurements_comparison_identity_check;
  end if;
end $$;

create or replace view fitmatch_catalog.current_product_classifications
with (security_invoker=true)
as
select
  p.id product_id,p.source,p.external_product_id,p.product_name,
  p.canonical_url,p.audience,p.source_category_path,p.source_category_codes,
  p.image_url,p.input_fingerprint,p.lifecycle_status,p.last_seen_at,
  h.id classification_id,h.category_code,h.detail_code,
  h.comparison_family_code,h.length_code,h.classification_status,
  h.classification_method,h.confidence,h.requires_user_confirmation,
  h.taxonomy_policy_version,h.mapping_release_id,h.decision_version,h.evidence
from fitmatch_catalog.products p
left join fitmatch_catalog.product_classification_history h
  on h.product_id=p.id and h.is_current;

revoke all on fitmatch_catalog.current_product_classifications
  from public,anon,authenticated;
grant select on fitmatch_catalog.current_product_classifications to service_role;

create or replace function fitmatch_qa.validate_product_runtime()
returns jsonb
language plpgsql
stable
security invoker
set search_path=pg_catalog,fitmatch_catalog,fitmatch_qa
as $$
declare
  v_snapshots bigint; v_linked bigint; v_products bigint;
  v_qa bigint; v_qa_matches bigint; v_current bigint;
  v_duplicate_current bigint; v_contradictions bigint; v_invalid_measurements bigint;
  v_public_rpc_leaks bigint;
begin
  select count(*),count(*) filter(where product_id is not null)
    into v_snapshots,v_linked
  from fitmatch_catalog.source_product_snapshots;
  select count(*) into v_products from fitmatch_catalog.products;
  select count(*) into v_current
  from fitmatch_catalog.product_classification_history where is_current;
  select count(*) into v_duplicate_current from (
    select product_id from fitmatch_catalog.product_classification_history
    where is_current group by product_id having count(*)>1
  ) d;
  select count(*) into v_contradictions
  from fitmatch_catalog.product_classification_history
  where is_current and classification_status='confirmed' and (
    (category_code='underwear' and comparison_family_code<>'underwear')
    or (category_code='bottoms' and comparison_family_code='tshirt')
  );
  select count(*) into v_invalid_measurements
  from fitmatch_catalog.product_measurements
  where is_comparable and (
    normalized_value is null or measurement_kind is null or comparison_basis is null
  );
  select count(*),count(*) filter(where
    q.expected_category_code is not distinct from d.category_code
    and q.expected_detail_code is not distinct from d.detail_code
    and q.expected_comparison_family is not distinct from d.comparison_family
    and q.expected_length_type is not distinct from d.length_type
    and q.requires_user_confirmation=d.requires_user_confirmation)
  into v_qa,v_qa_matches
  from fitmatch_qa.classification_cases q
  join fitmatch_catalog.product_classification_decisions d
    on d.source=q.source and d.external_product_id=q.product_id;
  select count(*) into v_public_rpc_leaks
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
  where p.prosecdef and n.nspname='public' and p.proname like 'fitmatch_%'
    and acl.grantee=0 and acl.privilege_type='EXECUTE';

  return jsonb_build_object(
    'passed',v_snapshots=v_linked and v_duplicate_current=0
      and v_contradictions=0 and v_invalid_measurements=0
      and v_qa>0 and v_qa=v_qa_matches and v_public_rpc_leaks=0,
    'products',v_products,'snapshots',v_snapshots,'linked_snapshots',v_linked,
    'current_classifications',v_current,'duplicate_current',v_duplicate_current,
    'category_family_contradictions',v_contradictions,
    'invalid_comparable_measurements',v_invalid_measurements,
    'classification_gold_cases',v_qa,'classification_gold_matches',v_qa_matches,
    'classification_gold_parity',case when v_qa=0 then null
      else round(v_qa_matches::numeric/v_qa*100,4) end,
    'public_security_definer_execute_leaks',v_public_rpc_leaks,
    'policy_version','db-runtime-2026-08-18-v1'
  );
end $$;

revoke all on function fitmatch_qa.validate_product_runtime()
  from public,anon,authenticated;
grant execute on function fitmatch_qa.validate_product_runtime() to service_role;

do $$
declare v_result jsonb;
begin
  v_result:=fitmatch_qa.validate_product_runtime();
  if not coalesce((v_result->>'passed')::boolean,false) then
    raise exception 'product runtime validation failed: %',v_result;
  end if;
end $$;

commit;
;
