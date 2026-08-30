
create index if not exists garment_length_classes_app_category_idx
on public.garment_length_classes(app_category_id);

with root as (
  select id from public.app_categories where parent_id is null and code='leggings'
), detail as (
  select ac.id
  from public.app_categories ac join root r on ac.parent_id=r.id
  where ac.code='leggings'
)
update public.source_categories
set app_category='leggings',
    app_detail_category='leggings',
    app_category_id=(select id from detail),
    updated_at=now()
where metadata ? 'taxonomy_v2_backup'
  and app_detail_category='leggings';
;
