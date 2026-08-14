begin read only;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from fitmatch_taxonomy.classification_decisions d
  join fitmatch_taxonomy.source_categories c on c.id=d.source_category_id
  where d.policy_version='taxonomy-refined-2026-08-03' and c.source_code='musinsa'
    and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
    and d.decision_status='rejected' and not d.canonical_default_allowed
    and d.garment_type_code is null and d.comparison_family_code is null;
  if v_count <> 4 then raise exception 'Briefcase correction validation expected 4, found %',v_count; end if;

  if exists (
    select 1 from fitmatch_taxonomy.category_app_mappings m
    join fitmatch_taxonomy.classification_correction_backups b on b.decision_id=m.decision_id
    where b.correction_code='briefcase-not-underwear-v1'
  ) then raise exception 'Briefcase app mappings remain'; end if;
end $$;

commit;
