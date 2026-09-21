-- Recovery for 20260921110000_closet_raw_measurement_snapshots.sql.
-- This recovery deliberately refuses to discard any immutable Closet source
-- snapshot. Archive or migrate those rows first; do not run this as a data
-- deletion shortcut.
begin;

do $guard_source_snapshots$
begin
    if exists (select 1 from fitmatch_vnext.closet_item_source_measurements) then
        raise exception
            'Cannot roll back raw Closet snapshots while snapshot rows exist; archive them first.';
    end if;
end
$guard_source_snapshots$;

-- Detach public wrappers from the replacement functions before restoring the
-- original implementations that the migration renamed with a `_v1` suffix.
create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_for_swift_v1(p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.list_closet_items_v1()
$function$;

drop function fitmatch_vnext.upsert_closet_item_for_swift(jsonb);
drop function fitmatch_vnext.list_closet_items();

alter function fitmatch_vnext.upsert_closet_item_for_swift_v1(jsonb)
    rename to upsert_closet_item_for_swift;
alter function fitmatch_vnext.list_closet_items_v1()
    rename to list_closet_items;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.upsert_closet_item_for_swift(p_request)
$function$;

create or replace function public.fitmatch_vnext_list_closet_items()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
    select fitmatch_vnext.list_closet_items()
$function$;

drop table fitmatch_vnext.closet_item_source_measurements;

commit;
