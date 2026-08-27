-- CONTROLLED PRODUCTION ROLLBACK TEMPLATE.
-- The operator must prepend, in the same database session, two temporary
-- tables populated by streaming the encrypted preimage (never a repo file):
--   pg_temp.fitmatch_decision_preimage(value jsonb) -- exactly 121 rows
--   pg_temp.fitmatch_function_preimage(value jsonb) -- exactly 19 rows
-- Then execute this transaction. Additive 113--118 schema remains installed.

begin;

set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtext('fitmatch:release-activation'));

do $preimage_guard$
declare
  v_successor_gate jsonb;
begin
  if to_regclass('pg_temp.fitmatch_decision_preimage') is null
    or to_regclass('pg_temp.fitmatch_function_preimage') is null
    or (select count(*) from pg_temp.fitmatch_decision_preimage)<>121
    or (select count(*) from pg_temp.fitmatch_function_preimage)<>19
    or exists(select 1 from pg_temp.fitmatch_decision_preimage
      where not coalesce((value->>'existed')::boolean,false))
  then raise exception 'rollback_secure_preimage_not_loaded_or_incomplete'; end if;
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or not exists(select 1 from fitmatch_catalog.releases
      where id='11800000-0000-4000-8000-000000000118'::uuid
        and status='active')
  then raise exception 'rollback_failed_release_not_exclusively_active'; end if;
  perform 1 from fitmatch_catalog.releases
  where id in(
    '11800000-0000-4000-8000-000000000118'::uuid,
    '11800000-0000-4000-8000-00000000b001'::uuid)
  for update;
  if (select count(*) from fitmatch_catalog.releases where id in(
      '11800000-0000-4000-8000-000000000118'::uuid,
      '11800000-0000-4000-8000-00000000b001'::uuid))<>2
  then raise exception 'rollback_release_lock_set_incomplete'; end if;
  v_successor_gate:=fitmatch_catalog.runtime_release_gate_report(
    '11800000-0000-4000-8000-00000000b001'::uuid);
  if not coalesce((v_successor_gate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(
      v_successor_gate->'blockers','[]'::jsonb))<>0
  then raise exception 'rollback_successor_gate_failed:%',v_successor_gate; end if;
end
$preimage_guard$;

with restored as (
  select jsonb_populate_record(
    null::fitmatch_catalog.product_classification_decisions,
    value->'row') row_value
  from pg_temp.fitmatch_decision_preimage
)
insert into fitmatch_catalog.product_classification_decisions(
  source,external_product_id,product_name,source_category_path,
  input_fingerprint,category_code,detail_code,comparison_family,length_type,
  requires_user_confirmation,release_id,decision_version,evidence,
  created_at,updated_at,garment_type_code,authority_status
)
select (row_value).source,(row_value).external_product_id,
  (row_value).product_name,(row_value).source_category_path,
  (row_value).input_fingerprint,(row_value).category_code,
  (row_value).detail_code,(row_value).comparison_family,
  (row_value).length_type,(row_value).requires_user_confirmation,
  (row_value).release_id,(row_value).decision_version,(row_value).evidence,
  (row_value).created_at,(row_value).updated_at,null,'legacy'
from restored
on conflict(source,external_product_id) do update set
  product_name=excluded.product_name,
  source_category_path=excluded.source_category_path,
  input_fingerprint=excluded.input_fingerprint,
  category_code=excluded.category_code,
  detail_code=excluded.detail_code,
  comparison_family=excluded.comparison_family,
  length_type=excluded.length_type,
  requires_user_confirmation=excluded.requires_user_confirmation,
  release_id=excluded.release_id,
  decision_version=excluded.decision_version,
  evidence=excluded.evidence,
  created_at=excluded.created_at,
  updated_at=excluded.updated_at,
  garment_type_code=null,
  authority_status='legacy';

do $restore_functions$
declare
  v_function record;
  v_acl record;
  v_signature text;
  v_role text;
begin
  for v_function in
    select value from pg_temp.fitmatch_function_preimage
    where (value->>'schema'='fitmatch_catalog'
        and value->>'name'='runtime_resolve_and_promote_product')
      or (value->>'schema'='public' and value->>'name' in(
        'fitmatch_resolve_product','fitmatch_get_product_runtime',
        'fitmatch_find_reference_candidates','fitmatch_begin_comparison'))
    order by value->>'schema',value->>'name',value->>'identity_arguments'
  loop
    execute v_function.value->>'definition';
    v_signature:=format('%I.%I(%s)',v_function.value->>'schema',
      v_function.value->>'name',v_function.value->>'identity_arguments');
    execute format('alter function %s owner to %I',v_signature,
      v_function.value->>'owner');
    execute format(
      'revoke all on function %s from public,anon,authenticated,service_role',
      v_signature);
    for v_acl in
      select exploded.grantee,exploded.privilege_type,exploded.is_grantable
      from aclexplode((v_function.value->>'acl')::aclitem[]) exploded
    loop
      if v_acl.grantee=0 then
        v_role:='public';
      else
        select rolname into strict v_role from pg_roles
        where oid=v_acl.grantee;
      end if;
      execute format('grant %s on function %s to %I%s',
        v_acl.privilege_type,v_signature,v_role,
        case when v_acl.is_grantable then ' with grant option' else '' end);
    end loop;
  end loop;
end
$restore_functions$;

do $pointer_restore$
begin
  update fitmatch_catalog.releases set status='retired'
  where id='11800000-0000-4000-8000-000000000118'::uuid
    and status='active';
  if not found then raise exception 'rollback_failed_release_retire_failed'; end if;
  update fitmatch_catalog.releases
  set status='active',activated_at=now(),
      metadata=metadata||jsonb_build_object(
        'rollback_activated',true,
        'rolled_back_release_id',
          '11800000-0000-4000-8000-000000000118')
  where id='11800000-0000-4000-8000-00000000b001'::uuid
    and status='validated';
  if not found then raise exception 'rollback_successor_activation_failed'; end if;
end
$pointer_restore$;

do $rollback_smoke$
declare
  v_entry jsonb;
  v_proc regprocedure;
begin
  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '11800000-0000-4000-8000-00000000b001'::uuid
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id=
          '11800000-0000-4000-8000-00000000b001'::uuid)<>3492
  then raise exception 'rollback_active_successor_postcondition_failed'; end if;
  if (select count(*) from fitmatch_catalog.product_classification_history)<>1860
    or (select count(*) from fitmatch_catalog.product_classification_history
        where is_current)<>1608
  then raise exception 'rollback_history_mutation_detected'; end if;
  if exists(
    select 1
    from pg_temp.fitmatch_decision_preimage preimage
    join fitmatch_catalog.product_classification_decisions decision
      on decision.source=preimage.value->>'source'
     and decision.external_product_id=preimage.value->>'external_product_id'
    where to_jsonb(decision)-'garment_type_code'-'authority_status'
        -'created_at'-'updated_at'
      is distinct from
        ((preimage.value->'row')-'created_at'-'updated_at')
      or decision.created_at is distinct from
        (preimage.value#>>'{row,created_at}')::timestamptz
      or decision.updated_at is distinct from
        (preimage.value#>>'{row,updated_at}')::timestamptz
      or decision.garment_type_code is not null
      or decision.authority_status<>'legacy'
  ) or (select count(*)
    from pg_temp.fitmatch_decision_preimage preimage
    join fitmatch_catalog.product_classification_decisions decision
      on decision.source=preimage.value->>'source'
     and decision.external_product_id=preimage.value->>'external_product_id')<>121
  then raise exception 'rollback_decision_preimage_restore_mismatch'; end if;
  if exists(
    select 1 from fitmatch_catalog.products product
    join fitmatch_catalog.product_classification_history history
      on history.product_id=product.id and history.is_current
    where product.source='musinsa'
      and product.external_product_id in(
        '4800605','5982920','6593581','6786576',
        '6797265','6797266','6797271')
      and history.classification_status='confirmed'
  ) then raise exception 'rollback_set_current_history_leak'; end if;
  for v_entry in
    select value from pg_temp.fitmatch_function_preimage
    where (value->>'schema'='fitmatch_catalog'
        and value->>'name'='runtime_resolve_and_promote_product')
      or (value->>'schema'='public' and value->>'name' in(
        'fitmatch_resolve_product','fitmatch_get_product_runtime',
        'fitmatch_find_reference_candidates','fitmatch_begin_comparison'))
  loop
    select function_row.oid::regprocedure into v_proc
    from pg_proc function_row
    join pg_namespace schema_row
      on schema_row.oid=function_row.pronamespace
    where schema_row.nspname=v_entry->>'schema'
      and function_row.proname=v_entry->>'name'
      and pg_get_function_identity_arguments(function_row.oid)=
        v_entry->>'identity_arguments';
    if v_proc is null or pg_get_functiondef(v_proc) is distinct from
      v_entry->>'definition'
      or pg_get_userbyid((select proowner from pg_proc where oid=v_proc))
        is distinct from v_entry->>'owner'
    then raise exception 'rollback_function_preimage_restore_mismatch:%',
      v_entry->>'logical_key'; end if;
  end loop;
end
$rollback_smoke$;

commit;
