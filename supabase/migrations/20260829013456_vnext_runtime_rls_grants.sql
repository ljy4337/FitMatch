-- fitmatch_vnext P0-11: explicit Data API grants and ownership policies.

revoke usage on schema fitmatch_vnext from anon;
grant usage on schema fitmatch_vnext to authenticated, service_role;

revoke all on all tables in schema fitmatch_vnext from anon;
revoke all on all sequences in schema fitmatch_vnext from anon, authenticated;
grant usage, select on all sequences in schema fitmatch_vnext to service_role;

drop policy if exists profiles_select_own on fitmatch_vnext.profiles;
create policy profiles_select_own on fitmatch_vnext.profiles
for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists profiles_insert_own on fitmatch_vnext.profiles;
create policy profiles_insert_own on fitmatch_vnext.profiles
for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists profiles_update_own on fitmatch_vnext.profiles;
create policy profiles_update_own on fitmatch_vnext.profiles
for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists closet_items_select_own on fitmatch_vnext.closet_items;
create policy closet_items_select_own on fitmatch_vnext.closet_items
for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists closet_item_measurements_select_own
    on fitmatch_vnext.closet_item_measurements;
create policy closet_item_measurements_select_own
on fitmatch_vnext.closet_item_measurements
for select to authenticated using (exists (
    select 1 from fitmatch_vnext.closet_items ci
    where ci.id = closet_item_id and ci.user_id = (select auth.uid())
));
drop policy if exists comparisons_select_own on fitmatch_vnext.comparisons;
create policy comparisons_select_own on fitmatch_vnext.comparisons
for select to authenticated using (user_id = (select auth.uid()));

-- Function execution is deny-by-default. Trigger functions need no client grant.
revoke execute on all functions in schema fitmatch_vnext from public, anon, authenticated;

grant execute on function fitmatch_vnext.classification_decision(text,text)
    to authenticated, service_role;
grant execute on function fitmatch_vnext.get_product_runtime(text,text)
    to authenticated, service_role;
grant execute on function fitmatch_vnext.upsert_closet_item(jsonb),
    fitmatch_vnext.list_closet_items(),
    fitmatch_vnext.set_closet_reference(uuid),
    fitmatch_vnext.authorize_comparison(uuid,uuid,uuid,boolean),
    fitmatch_vnext.begin_comparison(jsonb),
    fitmatch_vnext.complete_comparison(uuid,jsonb),
    fitmatch_vnext.comparison_history()
    to authenticated, service_role;

grant execute on function fitmatch_vnext.classification_tuple_validation(text,text,text,text,text,text),
    fitmatch_vnext.resolve_product_classification(text,text,boolean),
    fitmatch_vnext.resolve_measurement(text,text,text,text,text,text,numeric),
    fitmatch_vnext.canonical_measurements_for_size(uuid),
    fitmatch_vnext.record_size_availability(uuid,text,text,jsonb,timestamptz,timestamptz),
    fitmatch_vnext.product_readiness(uuid)
    to service_role;

alter default privileges in schema fitmatch_vnext revoke execute on functions from public;
alter default privileges in schema fitmatch_vnext revoke all on tables from anon;
alter default privileges in schema fitmatch_vnext revoke all on sequences from anon, authenticated;
;
