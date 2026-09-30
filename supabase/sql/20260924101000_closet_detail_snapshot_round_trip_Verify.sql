-- Read-only post-apply checks for 20260924101000.
-- The first query validates the contract; the second shows exact snapshots
-- separately from the legacy coalesced detail projection for the caller.

select
    exists (
        select 1
        from pg_attribute
        where attrelid = 'fitmatch_vnext.closet_items'::regclass
          and attname = 'closet_detail_code_snapshot'
          and not attisdropped
    ) as detail_snapshot_column_exists,
    to_regprocedure('fitmatch_vnext.list_closet_items()') as private_list_owner,
    to_regprocedure('public.fitmatch_vnext_list_closet_items()') as public_list_rpc;

select
    item ->> 'id' as closet_item_id,
    item ->> 'detail_code' as legacy_detail_projection,
    item ->> 'closet_detail_code_snapshot' as explicit_detail_snapshot,
    item -> 'comparison_group' ->> 'group_code' as comparison_group_code
from jsonb_array_elements(public.fitmatch_vnext_list_closet_items()) item;
