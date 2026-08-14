begin read only;

do $$
declare
  v_counts jsonb;
begin
  if (select count(*) from fitmatch_catalog.app_categories) <> 11 then
    raise exception 'Expected 11 app categories';
  end if;
  if (select count(*) from fitmatch_catalog.app_category_details) <> 75 then
    raise exception 'Expected 75 app category details';
  end if;

  select jsonb_object_agg(decision_status, n) into v_counts
  from (
    select decision_status, count(*)::integer n
    from fitmatch_taxonomy.classification_decisions
    where policy_version = 'taxonomy-corrected-2026-08-14'
    group by decision_status
  ) s;
  if v_counts <> '{"confirmed":1327,"review_required":608,"rejected":1451,"unsupported":40,"navigation_only":582}'::jsonb then
    raise exception 'Corrected policy counts differ: %', v_counts;
  end if;

  if (select count(*) from fitmatch_catalog.source_to_fitmatch_mappings) <> 3426 then
    raise exception 'Expected 3426 runtime mappings';
  end if;
  if exists (
    select 1
    from fitmatch_catalog.source_to_fitmatch_mappings m
    left join fitmatch_catalog.app_categories c
      on c.release_id = m.release_id and c.code = m.app_category_code
    where m.decision_status = 'confirmed' and c.code is null
  ) then
    raise exception 'Confirmed mapping references an invalid app category';
  end if;
  if exists (
    select 1 from fitmatch_catalog.source_to_fitmatch_mappings
    where app_detail_code is not null
  ) then
    raise exception 'Source mapping must not force a product-level app detail';
  end if;
end $$;

commit;
