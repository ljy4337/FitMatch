begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:authenticated-closet-crud-v1'));

-- The server owns the authenticated closet. client_item_id keeps SwiftData
-- migration and retry idempotent without exposing auth.users identifiers.
alter table public.closet_items
  add column if not exists client_item_id uuid,
  add column if not exists fit_memo text not null default '',
  add column if not exists fit_preference_code text not null default 'regular',
  add column if not exists satisfaction smallint not null default 0,
  add column if not exists measurement_records jsonb not null default '[]'::jsonb,
  add column if not exists client_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists client_created_at timestamptz,
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1;

update public.closet_items
set client_item_id = id
where client_item_id is null;

alter table public.closet_items
  alter column client_item_id set default gen_random_uuid(),
  alter column client_item_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_user_client_item_unique'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_user_client_item_unique
      unique (user_id, client_item_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_fit_preference_check'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_fit_preference_check
      check (fit_preference_code in ('slim','regular','semi_over','over','boxy'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_satisfaction_check'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_satisfaction_check
      check (satisfaction between 0 and 5);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_measurement_records_array_check'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_measurement_records_array_check
      check (jsonb_typeof(measurement_records) = 'array');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_client_snapshot_object_check'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_client_snapshot_object_check
      check (jsonb_typeof(client_snapshot) = 'object');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'closet_items_sync_revision_check'
      and conrelid = 'public.closet_items'::regclass
  ) then
    alter table public.closet_items
      add constraint closet_items_sync_revision_check
      check (sync_revision > 0);
  end if;
end $$;

-- Enforce the same rule as ReferenceGarmentPolicy: one reference item for a
-- user, gender, major category and detail category.
create unique index if not exists closet_items_one_reference_per_scope_idx
  on public.closet_items (user_id, gender, app_category, app_detail_category)
  where is_reference and deleted_at is null;

create index if not exists closet_items_user_active_recent_idx
  on public.closet_items (user_id, client_created_at desc, created_at desc)
  where deleted_at is null;

create or replace function public.fitmatch_upsert_closet_item(
  p_client_item_id uuid,
  p_item jsonb,
  p_product_id uuid default null,
  p_product_size_id uuid default null,
  p_override jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_product fitmatch_catalog.products%rowtype;
  v_classification fitmatch_catalog.product_classification_history%rowtype;
  v_size fitmatch_catalog.product_sizes%rowtype;
  v_item_id uuid;
  v_variant_id uuid;
  v_source_id uuid;
  v_garment_type_id uuid;
  v_product_name text;
  v_brand text;
  v_size_name text;
  v_gender text;
  v_source text;
  v_category text;
  v_detail text;
  v_family text;
  v_length text;
  v_body_length text;
  v_status text;
  v_classification_source text;
  v_policy_version text;
  v_measurements jsonb;
  v_measurement_records jsonb;
  v_client_snapshot jsonb;
  v_is_reference boolean;
  v_fit_preference text;
  v_satisfaction smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_client_item_id is null then
    raise exception using errcode = '22023', message = 'client_item_id_required';
  end if;
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_closet_item';
  end if;
  if p_override is not null and jsonb_typeof(p_override) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_override';
  end if;

  v_measurements := coalesce(p_item -> 'measurements', '{}'::jsonb);
  v_measurement_records := coalesce(p_item -> 'measurement_records', '[]'::jsonb);
  v_client_snapshot := coalesce(p_item -> 'client_snapshot', '{}'::jsonb);
  if jsonb_typeof(v_measurements) <> 'object'
     or jsonb_typeof(v_measurement_records) <> 'array'
     or jsonb_typeof(v_client_snapshot) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_closet_payload_shape';
  end if;
  if exists (
    select 1 from jsonb_each(v_measurements) m
    where jsonb_typeof(m.value) <> 'number'
       or (m.value #>> '{}')::numeric <= 0
       or (m.value #>> '{}')::numeric > 1000
  ) then
    raise exception using errcode = '22023', message = 'invalid_measurements';
  end if;

  v_is_reference := coalesce((p_item ->> 'is_reference')::boolean, false);
  v_fit_preference := coalesce(nullif(p_item ->> 'fit_preference_code', ''), 'regular');
  v_satisfaction := coalesce((p_item ->> 'satisfaction')::smallint, 0);
  if v_fit_preference not in ('slim','regular','semi_over','over','boxy') then
    raise exception using errcode = '22023', message = 'invalid_fit_preference';
  end if;
  if v_satisfaction < 0 or v_satisfaction > 5 then
    raise exception using errcode = '22023', message = 'invalid_satisfaction';
  end if;

  if p_product_id is not null then
    select * into v_product
    from fitmatch_catalog.products
    where id = p_product_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'product_not_found';
    end if;

    select * into v_classification
    from fitmatch_catalog.product_classification_history
    where product_id = p_product_id and is_current;
    if not found then
      raise exception using errcode = 'P0002', message = 'classification_not_found';
    end if;
    if p_override is null and v_classification.classification_status <> 'confirmed' then
      raise exception using errcode = '22023', message = 'user_classification_required';
    end if;

    if p_product_size_id is not null then
      select s.* into v_size
      from fitmatch_catalog.product_sizes s
      join fitmatch_catalog.product_variants v on v.id = s.variant_id
      where s.id = p_product_size_id and v.product_id = p_product_id;
      if not found then
        raise exception using errcode = '22023', message = 'product_size_mismatch';
      end if;
      v_variant_id := v_size.variant_id;
    end if;

    if p_override is not null and (
      nullif(p_override ->> 'category_code', '') is null
      or nullif(p_override ->> 'detail_code', '') is null
      or nullif(p_override ->> 'family_code', '') is null
    ) then
      raise exception using errcode = '22023', message = 'invalid_override';
    end if;

    v_product_name := v_product.product_name;
    v_brand := coalesce(nullif(p_item ->> 'brand', ''), v_product.raw_payload ->> 'brand');
    v_size_name := coalesce(v_size.size_label, nullif(p_item ->> 'size_name', ''));
    v_source := v_product.source;
    v_gender := case upper(coalesce(v_product.audience, p_item ->> 'gender_code', 'UNKNOWN'))
      when 'MEN' then 'male'
      when 'MALE' then 'male'
      when 'WOMEN' then 'female'
      when 'FEMALE' then 'female'
      when 'KIDS' then 'kids_unisex'
      when 'BABY' then 'kids_unisex'
      when 'UNISEX' then 'unisex'
      else lower(coalesce(v_product.audience, p_item ->> 'gender_code', 'unknown'))
    end;
    v_category := coalesce(nullif(p_override ->> 'category_code', ''), v_classification.category_code);
    v_detail := coalesce(nullif(p_override ->> 'detail_code', ''), v_classification.detail_code);
    v_family := case when p_override is null
      then v_classification.comparison_family_code
      else nullif(p_override ->> 'family_code', '') end;
    v_length := case when p_override is null
      then v_classification.length_code
      else nullif(p_override ->> 'length_code', '') end;
    v_body_length := case when p_override is null
      then v_classification.body_length_code
      else nullif(p_override ->> 'body_length_code', '') end;
    v_status := 'confirmed';
    v_classification_source := case when p_override is null
      then 'product_metadata' else 'manual_override' end;
    v_policy_version := v_classification.decision_version;
    select id into v_source_id from public.sources where code = v_source;

    if p_product_size_id is not null and v_measurements = '{}'::jsonb then
      select coalesce(jsonb_object_agg(m.measurement_code, m.normalized_value), '{}'::jsonb)
      into v_measurements
      from fitmatch_catalog.product_measurements m
      where m.product_size_id = p_product_size_id
        and m.is_comparable
        and m.measurement_code is not null
        and m.normalized_value is not null
        and m.normalized_value > 0;
    end if;
  else
    if p_product_size_id is not null then
      raise exception using errcode = '22023', message = 'product_id_required_for_size';
    end if;
    v_product_name := nullif(btrim(p_item ->> 'product_name'), '');
    v_brand := nullif(btrim(p_item ->> 'brand'), '');
    v_size_name := nullif(btrim(p_item ->> 'size_name'), '');
    v_source := lower(coalesce(nullif(btrim(p_item ->> 'source'), ''), 'manual'));
    v_gender := lower(coalesce(nullif(btrim(p_item ->> 'gender_code'), ''), 'unknown'));
    v_category := nullif(btrim(p_item ->> 'category_code'), '');
    v_detail := nullif(btrim(p_item ->> 'detail_code'), '');
    v_family := nullif(btrim(p_item ->> 'family_code'), '');
    v_length := nullif(btrim(p_item ->> 'length_code'), '');
    v_body_length := nullif(btrim(p_item ->> 'body_length_code'), '');
    v_classification_source := 'manual_override';
    v_policy_version := nullif(p_item ->> 'classification_version', '');

    if v_product_name is null or v_category is null or v_detail is null then
      raise exception using errcode = '22023', message = 'manual_item_fields_required';
    end if;
    if v_source !~ '^[a-z][a-z0-9_]*$' then
      raise exception using errcode = '22023', message = 'invalid_source';
    end if;
    if v_gender not in ('male','female','unisex','kids_unisex','unknown') then
      raise exception using errcode = '22023', message = 'invalid_gender';
    end if;

    select gt.id into v_garment_type_id
    from public.garment_types gt
    where gt.is_active
      and gt.major_category_code = v_category
      and (
        gt.code = v_family
        or gt.comparison_group_code = v_family
        or gt.code = case
          when v_family = 'shirt' then 'shirt_blouse'
          when v_family = 'pants' then 'other_standard_pants'
          when v_family = 'denim' then 'denim_pants'
          when v_family = 'knit_cardigan' and v_detail = 'cardigan' then 'cardigan'
          when v_family = 'knit_cardigan' then 'knit_sweater'
          when v_family = 'outerwear' then case v_detail
            when 'coat' then 'coat'
            when 'trench_coat' then 'trench_coat'
            when 'blazer' then 'blazer'
            when 'blouson' then 'blouson'
            when 'windbreaker' then 'windbreaker'
            when 'anorak' then 'anorak'
            when 'mouton' then 'mouton'
            when 'padded_vest' then 'puffer_vest'
            when 'vest' then 'outer_vest'
            when 'fleece' then 'fleece_jacket'
            when 'padding' then 'puffer_jacket'
            when 'light_padding' then 'puffer_jacket'
            when 'short_padding' then 'puffer_jacket'
            when 'long_padding' then 'puffer_jacket'
            else 'generic_jacket' end
          else null end
      )
    order by
      (gt.code = v_family) desc,
      (gt.comparison_group_code = v_family) desc,
      gt.sort_order,
      gt.code
    limit 1;
    v_status := case when v_garment_type_id is null
      then 'review_required' else 'confirmed' end;
    select id into v_source_id from public.sources where code = v_source;
  end if;

  if not exists (
    select 1 from public.app_categories major
    where major.code = v_category and major.depth = 0 and major.is_active
  ) then
    raise exception using errcode = '22023', message = 'invalid_category';
  end if;
  if (p_product_id is null or p_override is not null) and not exists (
    select 1
    from public.app_categories major
    join public.app_categories detail on detail.parent_id = major.id
    where major.code = v_category and major.depth = 0 and major.is_active
      and detail.code = v_detail and detail.depth = 1 and detail.is_active
    union all
    select 1
    from fitmatch_catalog.product_classification_history h
    where h.is_current and h.classification_status = 'confirmed'
      and h.category_code = v_category and h.detail_code = v_detail
  ) then
    raise exception using errcode = '22023', message = 'invalid_category_detail';
  end if;
  if p_product_id is null and v_family is not null and not exists (
    select 1 from public.comparison_groups cg
    where cg.code = v_family and cg.major_category_code = v_category and cg.is_active
    union all
    select 1 from fitmatch_catalog.product_classification_history h
    where h.is_current and h.classification_status = 'confirmed'
      and h.category_code = v_category
      and h.comparison_family_code = v_family
  ) then
    v_status := 'review_required';
    v_garment_type_id := null;
  end if;

  if v_is_reference then
    update public.closet_items
    set is_reference = false, updated_at = now(), sync_revision = sync_revision + 1
    where user_id = v_user_id
      and client_item_id <> p_client_item_id
      and deleted_at is null
      and is_reference
      and gender = v_gender
      and app_category = v_category
      and app_detail_category = v_detail;
  end if;

  insert into public.closet_items (
    user_id, client_item_id, source_id, brand, product_name, size_name, gender,
    app_category, app_detail_category, original_category_path, source,
    product_url, image_url, measurements, measurement_records, is_reference,
    fit_memo, fit_preference_code, satisfaction, client_snapshot,
    client_created_at, client_updated_at, sync_revision,
    garment_type_id, classification_status, classification_source,
    comparison_policy_version, product_id, variant_id, product_size_id,
    canonical_classification_id, canonical_category_code, canonical_detail_code,
    comparison_family_code, comparison_length_code,
    comparison_body_length_code, classification_snapshot, deleted_at
  ) values (
    v_user_id, p_client_item_id, v_source_id, v_brand, v_product_name, v_size_name, v_gender,
    v_category, v_detail,
    coalesce(v_product.source_category_path, nullif(p_item ->> 'source_category_path', '')),
    v_source, coalesce(v_product.canonical_url, nullif(p_item ->> 'product_url', '')),
    coalesce(v_product.image_url, nullif(p_item ->> 'image_url', '')),
    v_measurements, v_measurement_records, v_is_reference,
    coalesce(p_item ->> 'fit_memo', ''), v_fit_preference, v_satisfaction,
    v_client_snapshot,
    coalesce((p_item ->> 'client_created_at')::timestamptz, now()),
    coalesce((p_item ->> 'client_updated_at')::timestamptz, now()), 1,
    v_garment_type_id, v_status, v_classification_source, v_policy_version,
    p_product_id, v_variant_id, p_product_size_id,
    v_classification.id, v_classification.category_code, v_classification.detail_code,
    v_family, v_length, v_body_length,
    jsonb_build_object(
      'classification_id', v_classification.id,
      'canonical_category_code', v_classification.category_code,
      'canonical_detail_code', v_classification.detail_code,
      'effective_category_code', v_category,
      'effective_detail_code', v_detail,
      'family_code', v_family,
      'length_code', v_length,
      'body_length_code', v_body_length,
      'status', v_status,
      'decision_version', v_policy_version
    ), null
  )
  on conflict (user_id, client_item_id) do update set
    source_id = excluded.source_id,
    brand = excluded.brand,
    product_name = excluded.product_name,
    size_name = excluded.size_name,
    gender = excluded.gender,
    app_category = excluded.app_category,
    app_detail_category = excluded.app_detail_category,
    original_category_path = excluded.original_category_path,
    source = excluded.source,
    product_url = excluded.product_url,
    image_url = excluded.image_url,
    measurements = excluded.measurements,
    measurement_records = excluded.measurement_records,
    is_reference = excluded.is_reference,
    fit_memo = excluded.fit_memo,
    fit_preference_code = excluded.fit_preference_code,
    satisfaction = excluded.satisfaction,
    client_snapshot = excluded.client_snapshot,
    client_updated_at = excluded.client_updated_at,
    sync_revision = public.closet_items.sync_revision + 1,
    garment_type_id = excluded.garment_type_id,
    classification_status = excluded.classification_status,
    classification_source = excluded.classification_source,
    comparison_policy_version = excluded.comparison_policy_version,
    product_id = excluded.product_id,
    variant_id = excluded.variant_id,
    product_size_id = excluded.product_size_id,
    canonical_classification_id = excluded.canonical_classification_id,
    canonical_category_code = excluded.canonical_category_code,
    canonical_detail_code = excluded.canonical_detail_code,
    comparison_family_code = excluded.comparison_family_code,
    comparison_length_code = excluded.comparison_length_code,
    comparison_body_length_code = excluded.comparison_body_length_code,
    classification_snapshot = excluded.classification_snapshot,
    deleted_at = null,
    updated_at = now()
  returning id into v_item_id;

  if p_product_id is not null and p_override is not null then
    insert into public.closet_item_classification_overrides (
      closet_item_id, user_id, category_code, detail_code,
      comparison_family_code, length_code, body_length_code, reason, evidence
    ) values (
      v_item_id, v_user_id, v_category, v_detail, v_family, v_length, v_body_length,
      nullif(p_override ->> 'reason', ''),
      case when jsonb_typeof(p_override -> 'evidence') = 'object'
        then p_override -> 'evidence' else '{}'::jsonb end
    )
    on conflict (closet_item_id, user_id) do update set
      category_code = excluded.category_code,
      detail_code = excluded.detail_code,
      comparison_family_code = excluded.comparison_family_code,
      length_code = excluded.length_code,
      body_length_code = excluded.body_length_code,
      reason = excluded.reason,
      evidence = excluded.evidence,
      updated_at = now();
  elsif p_product_id is not null then
    delete from public.closet_item_classification_overrides
    where closet_item_id = v_item_id and user_id = v_user_id;
  end if;

  return jsonb_build_object(
    'closet_item_id', v_item_id,
    'client_item_id', p_client_item_id,
    'sync_revision', (
      select sync_revision from public.closet_items where id = v_item_id
    ),
    'classification_status', v_status,
    'category_code', v_category,
    'detail_code', v_detail,
    'family_code', v_family,
    'length_code', v_length,
    'body_length_code', v_body_length,
    'is_reference', v_is_reference
  );
end $$;

create or replace function public.fitmatch_list_closet_items()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when auth.uid() is null then
    jsonb_build_object('state', 'authentication_required', 'items', '[]'::jsonb)
  else jsonb_build_object(
    'state', 'ready',
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'closet_item_id', c.id,
      'client_item_id', c.client_item_id,
      'product_id', c.product_id,
      'variant_id', c.variant_id,
      'product_size_id', c.product_size_id,
      'brand', c.brand,
      'product_name', c.product_name,
      'size_name', c.size_name,
      'gender_code', c.gender,
      'source', c.source,
      'source_category_path', c.original_category_path,
      'product_url', c.product_url,
      'image_url', c.image_url,
      'measurements', c.measurements,
      'measurement_records', c.measurement_records,
      'fit_memo', c.fit_memo,
      'fit_preference_code', c.fit_preference_code,
      'satisfaction', c.satisfaction,
      'is_reference', c.is_reference,
      'classification_status', c.classification_status,
      'classification_source', c.classification_source,
      'category_code', c.app_category,
      'detail_code', c.app_detail_category,
      'canonical_category_code', c.canonical_category_code,
      'canonical_detail_code', c.canonical_detail_code,
      'family_code', c.comparison_family_code,
      'length_code', c.comparison_length_code,
      'body_length_code', c.comparison_body_length_code,
      'classification_snapshot', c.classification_snapshot,
      'client_snapshot', c.client_snapshot,
      'client_created_at', c.client_created_at,
      'client_updated_at', c.client_updated_at,
      'sync_revision', c.sync_revision,
      'created_at', c.created_at,
      'updated_at', c.updated_at
    ) order by coalesce(c.client_created_at, c.created_at) desc), '[]'::jsonb)
  ) end
  from public.closet_items c
  where c.user_id = auth.uid() and c.deleted_at is null
$$;

create or replace function public.fitmatch_set_closet_reference(
  p_closet_item_id uuid,
  p_is_reference boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_item public.closet_items%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select * into v_item from public.closet_items
  where id = p_closet_item_id and user_id = v_user_id and deleted_at is null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'closet_item_not_found';
  end if;

  if p_is_reference then
    update public.closet_items
    set is_reference = false, updated_at = now(), sync_revision = sync_revision + 1
    where user_id = v_user_id and id <> p_closet_item_id
      and deleted_at is null and is_reference
      and gender = v_item.gender
      and app_category = v_item.app_category
      and app_detail_category = v_item.app_detail_category;
  end if;
  update public.closet_items
  set is_reference = p_is_reference,
      updated_at = now(),
      sync_revision = sync_revision + 1
  where id = p_closet_item_id and user_id = v_user_id;

  return jsonb_build_object(
    'closet_item_id', p_closet_item_id,
    'is_reference', p_is_reference,
    'sync_revision', (
      select sync_revision from public.closet_items where id = p_closet_item_id
    )
  );
end $$;

create or replace function public.fitmatch_delete_closet_item(
  p_closet_item_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_deleted_at timestamptz := now();
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.closet_items
  set deleted_at = v_deleted_at,
      is_reference = false,
      updated_at = v_deleted_at,
      sync_revision = sync_revision + 1
  where id = p_closet_item_id and user_id = v_user_id and deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'closet_item_not_found';
  end if;
  return jsonb_build_object(
    'closet_item_id', p_closet_item_id,
    'deleted_at', v_deleted_at
  );
end $$;

revoke insert, update, delete on public.closet_items from public, anon, authenticated;
revoke all on function public.fitmatch_upsert_closet_item(uuid,jsonb,uuid,uuid,jsonb)
  from public, anon;
revoke all on function public.fitmatch_list_closet_items() from public, anon;
revoke all on function public.fitmatch_set_closet_reference(uuid,boolean)
  from public, anon;
revoke all on function public.fitmatch_delete_closet_item(uuid) from public, anon;

grant execute on function public.fitmatch_upsert_closet_item(uuid,jsonb,uuid,uuid,jsonb)
  to authenticated;
grant execute on function public.fitmatch_list_closet_items() to authenticated;
grant execute on function public.fitmatch_set_closet_reference(uuid,boolean)
  to authenticated;
grant execute on function public.fitmatch_delete_closet_item(uuid) to authenticated;

commit;
;
