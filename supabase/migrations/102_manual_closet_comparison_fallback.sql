begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:manual-closet-comparison-fallback-v1'));

-- Manual closet items have no catalog classification row. Their effective
-- category/detail live in app_category/app_detail_category, so comparison
-- lookup must fall back to those columns after override/canonical values.
create or replace function public.fitmatch_find_reference_candidates(
  p_target_product_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_target fitmatch_catalog.product_classification_history%rowtype;
  v_product fitmatch_catalog.products%rowtype;
  v_candidates jsonb;
  v_auto_count integer;
  v_manual_count integer;
  v_structural_count integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select * into v_product
  from fitmatch_catalog.products where id = p_target_product_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'target_product_not_found';
  end if;
  select * into v_target
  from fitmatch_catalog.product_classification_history
  where product_id = p_target_product_id and is_current;
  if not found or v_target.classification_status <> 'confirmed' then
    return jsonb_build_object(
      'state', 'target_classification_required',
      'automatic_count', 0, 'manual_count', 0, 'structural_count', 0,
      'candidates', '[]'::jsonb,
      'policy_version', 'db-comparison-2026-08-19-v3'
    );
  end if;

  with evaluated as (
    select c.id, c.product_name, c.size_name, c.gender, c.is_reference, c.updated_at,
      coalesce(o.category_code, c.canonical_category_code, c.app_category) category_code,
      coalesce(o.detail_code, c.canonical_detail_code, c.app_detail_category) detail_code,
      coalesce(o.comparison_family_code, c.comparison_family_code) family_code,
      coalesce(o.length_code, c.comparison_length_code) length_code,
      coalesce(o.body_length_code, c.comparison_body_length_code) body_length_code
    from public.closet_items c
    left join public.closet_item_classification_overrides o
      on o.closet_item_id = c.id and o.user_id = c.user_id
    where c.user_id = v_user_id and c.deleted_at is null
      and coalesce(o.comparison_family_code, c.comparison_family_code) is not null
  ), compat as (
    select e.*,
      fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
        e.category_code, e.gender, e.family_code, e.detail_code, e.length_code, e.body_length_code,
        v_target.category_code, v_product.audience, v_target.comparison_family_code,
        v_target.detail_code, v_target.length_code, v_target.body_length_code, false
      ) automatic,
      fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
        e.category_code, e.gender, e.family_code, e.detail_code, e.length_code, e.body_length_code,
        v_target.category_code, v_product.audience, v_target.comparison_family_code,
        v_target.detail_code, v_target.length_code, v_target.body_length_code, true
      ) manual
    from evaluated e
  ), measured as (
    select c.*,
      fitmatch_catalog.runtime_closet_measurement_overlap(
        c.id, p_target_product_id, c.manual -> 'excluded_measurements'
      ) overlap_count
    from compat c
  ), ranked as (
    select *,
      coalesce((automatic ->> 'allowed')::boolean, false)
        and automatic ->> 'level' = 'direct'
        and overlap_count >= coalesce(nullif(automatic ->> 'minimum_common_measurements', '')::integer, 2)
        as automatic_ready,
      coalesce((manual ->> 'allowed')::boolean, false)
        and overlap_count >= coalesce(nullif(manual ->> 'minimum_common_measurements', '')::integer, 2)
        as manual_ready,
      coalesce((manual ->> 'allowed')::boolean, false) as structurally_compatible
    from measured
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'closet_item_id', id, 'product_name', product_name, 'size_name', size_name,
      'is_reference', is_reference, 'automatic_ready', automatic_ready,
      'manual_ready', manual_ready, 'measurement_overlap_count', overlap_count,
      'automatic_compatibility', automatic, 'manual_compatibility', manual
    ) order by automatic_ready desc, manual_ready desc, is_reference desc, updated_at desc, id), '[]'::jsonb),
    count(*) filter (where automatic_ready),
    count(*) filter (where manual_ready),
    count(*) filter (where structurally_compatible)
  into v_candidates, v_auto_count, v_manual_count, v_structural_count
  from ranked
  where automatic_ready or manual_ready or structurally_compatible;

  return jsonb_build_object(
    'state', case
      when v_auto_count > 0 then 'automatic'
      when v_manual_count > 0 then 'manual_selection'
      when v_structural_count > 0 then 'measurements_required'
      else 'no_compatible_garment' end,
    'automatic_count', v_auto_count,
    'manual_count', v_manual_count,
    'structural_count', v_structural_count,
    'candidates', v_candidates,
    'policy_version', 'db-comparison-2026-08-19-v3'
  );
end $$;

create or replace function public.fitmatch_begin_comparison(
  p_reference_item_id uuid,
  p_target_product_id uuid,
  p_allow_extended boolean default false,
  p_client_history_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_reference record;
  v_target fitmatch_catalog.product_classification_history%rowtype;
  v_product fitmatch_catalog.products%rowtype;
  v_existing public.comparison_runs%rowtype;
  v_compatibility jsonb;
  v_run_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_client_history_id is null then
    raise exception using errcode = '22023', message = 'client_history_id_required';
  end if;

  select * into v_existing
  from public.comparison_runs
  where user_id = v_user_id and client_history_id = p_client_history_id;
  if found then
    if v_existing.reference_item_id <> p_reference_item_id
       or v_existing.target_product_id <> p_target_product_id then
      raise exception using errcode = '22023', message = 'client_history_identity_conflict';
    end if;
    return jsonb_build_object(
      'run_id', v_existing.id,
      'status', v_existing.status,
      'compatibility', coalesce(v_existing.input_snapshot -> 'compatibility', '{}'::jsonb)
    );
  end if;

  select c.id, c.gender,
    coalesce(o.category_code, c.canonical_category_code, c.app_category) category_code,
    coalesce(o.detail_code, c.canonical_detail_code, c.app_detail_category) detail_code,
    coalesce(o.comparison_family_code, c.comparison_family_code) family_code,
    coalesce(o.length_code, c.comparison_length_code) length_code,
    coalesce(o.body_length_code, c.comparison_body_length_code) body_length_code
  into v_reference
  from public.closet_items c
  left join public.closet_item_classification_overrides o
    on o.closet_item_id = c.id and o.user_id = c.user_id
  where c.id = p_reference_item_id
    and c.user_id = v_user_id
    and c.deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'reference_item_not_found';
  end if;

  select * into v_product
  from fitmatch_catalog.products where id = p_target_product_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'target_product_not_found';
  end if;
  select * into v_target
  from fitmatch_catalog.product_classification_history
  where product_id = p_target_product_id and is_current;

  if not found or v_target.classification_status <> 'confirmed' then
    v_compatibility := jsonb_build_object(
      'allowed', false, 'level', 'incompatible',
      'reason', 'target_classification_not_confirmed',
      'excluded_measurements', '[]'::jsonb
    );
  elsif v_reference.family_code is null then
    v_compatibility := jsonb_build_object(
      'allowed', false, 'level', 'incompatible',
      'reason', 'reference_classification_not_confirmed',
      'excluded_measurements', '[]'::jsonb
    );
  else
    v_compatibility := fitmatch_catalog.runtime_evaluate_comparison_profiles_v3(
      v_reference.category_code, v_reference.gender, v_reference.family_code,
      v_reference.detail_code, v_reference.length_code, v_reference.body_length_code,
      v_target.category_code, v_product.audience, v_target.comparison_family_code,
      v_target.detail_code, v_target.length_code, v_target.body_length_code,
      p_allow_extended
    );
    if coalesce((v_compatibility ->> 'allowed')::boolean, false)
       and fitmatch_catalog.runtime_closet_measurement_overlap(
         p_reference_item_id, p_target_product_id,
         v_compatibility -> 'excluded_measurements'
       ) < coalesce(nullif(v_compatibility ->> 'minimum_common_measurements', '')::integer, 2) then
      v_compatibility := v_compatibility || jsonb_build_object(
        'allowed', false, 'level', 'insufficient_data',
        'reason', 'insufficient_common_measurements'
      );
    end if;
  end if;

  v_status := case when coalesce((v_compatibility ->> 'allowed')::boolean, false)
    then 'pending' else 'blocked' end;

  insert into public.comparison_runs (
    user_id, client_history_id, reference_item_id, target_product_id,
    status, comparison_level, block_reason, comparison_policy_version,
    input_snapshot, completed_at
  ) values (
    v_user_id, p_client_history_id, p_reference_item_id, p_target_product_id,
    v_status, v_compatibility ->> 'level', v_compatibility ->> 'reason',
    'db-comparison-2026-08-19-v3',
    jsonb_build_object(
      'compatibility', v_compatibility,
      'client_history_id', p_client_history_id,
      'allow_extended', p_allow_extended
    ),
    case when v_status = 'blocked' then now() else null end
  ) returning id into v_run_id;

  return jsonb_build_object(
    'run_id', v_run_id,
    'status', v_status,
    'compatibility', v_compatibility
  );
end $$;

revoke all on function public.fitmatch_find_reference_candidates(uuid)
  from public, anon;
grant execute on function public.fitmatch_find_reference_candidates(uuid)
  to authenticated, service_role;

revoke all on function public.fitmatch_begin_comparison(uuid, uuid, boolean, uuid)
  from public, anon;
grant execute on function public.fitmatch_begin_comparison(uuid, uuid, boolean, uuid)
  to authenticated, service_role;

commit;
