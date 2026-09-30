-- Keep immutable comparison executions while exposing one current result per
-- user and target Product. A successful later completion atomically advances
-- the current-result pointer; failed or pending attempts leave the old result.
begin;

create table if not exists fitmatch_vnext.comparison_result_heads (
    user_id uuid not null,
    target_product_id uuid not null,
    comparison_id uuid not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, target_product_id),
    unique (user_id, comparison_id),
    constraint comparison_result_heads_product_fkey
        foreign key (target_product_id)
        references fitmatch_vnext.products(id)
        on delete restrict,
    constraint comparison_result_heads_comparison_fkey
        foreign key (comparison_id)
        references fitmatch_vnext.comparisons(id)
        on delete restrict
);

alter table fitmatch_vnext.comparison_result_heads enable row level security;
revoke all on table fitmatch_vnext.comparison_result_heads
from public, anon, authenticated;
grant select, insert, update, delete
on table fitmatch_vnext.comparison_result_heads to service_role;

insert into fitmatch_vnext.comparison_result_heads (
    user_id,
    target_product_id,
    comparison_id,
    updated_at
)
select distinct on (comparison_value.user_id, comparison_value.target_product_id)
    comparison_value.user_id,
    comparison_value.target_product_id,
    comparison_value.id,
    coalesce(comparison_value.completed_at, comparison_value.created_at)
from fitmatch_vnext.comparisons comparison_value
where comparison_value.result_status = 'COMPLETED'
order by
    comparison_value.user_id,
    comparison_value.target_product_id,
    coalesce(comparison_value.completed_at, comparison_value.created_at) desc,
    comparison_value.id desc
on conflict (user_id, target_product_id) do update
set comparison_id = excluded.comparison_id,
    updated_at = excluded.updated_at;

create or replace function fitmatch_vnext.advance_comparison_result_head()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if new.result_status = 'COMPLETED'
       and old.result_status is distinct from 'COMPLETED' then
        insert into fitmatch_vnext.comparison_result_heads (
            user_id,
            target_product_id,
            comparison_id,
            updated_at
        ) values (
            new.user_id,
            new.target_product_id,
            new.id,
            coalesce(new.completed_at, now())
        )
        on conflict (user_id, target_product_id) do update
        set comparison_id = excluded.comparison_id,
            updated_at = excluded.updated_at;
    end if;
    return new;
end
$function$;

drop trigger if exists comparisons_advance_result_head
on fitmatch_vnext.comparisons;
create trigger comparisons_advance_result_head
after update of result_status on fitmatch_vnext.comparisons
for each row execute function fitmatch_vnext.advance_comparison_result_head();

create or replace function fitmatch_vnext.comparison_history()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    return coalesce((
        select jsonb_agg(
            to_jsonb(comparison_value) || jsonb_build_object(
                'reference_client_item_id', closet_value.client_item_id,
                'target_source_product_key', product_value.source_product_key,
                'target_category_code', garment_value.category_code
            )
            order by comparison_value.created_at desc, comparison_value.id
        )
        from fitmatch_vnext.comparisons comparison_value
        left join fitmatch_vnext.comparison_result_heads head
          on head.user_id = comparison_value.user_id
         and head.target_product_id = comparison_value.target_product_id
         and head.comparison_id = comparison_value.id
        left join fitmatch_vnext.closet_items closet_value
          on closet_value.id = comparison_value.reference_closet_item_id
         and closet_value.user_id = comparison_value.user_id
        left join fitmatch_vnext.products product_value
          on product_value.id = comparison_value.target_product_id
        left join fitmatch_vnext.garment_types garment_value
          on garment_value.garment_type_code = product_value.garment_type_code
        where comparison_value.user_id = caller_id
          and comparison_value.deleted_at is null
          and (
              comparison_value.result_status <> 'COMPLETED'
              or head.comparison_id is not null
          )
    ), '[]'::jsonb);
end
$function$;

revoke all on function fitmatch_vnext.advance_comparison_result_head()
from public, anon, authenticated;
revoke all on function fitmatch_vnext.comparison_history()
from public, anon;
grant execute on function fitmatch_vnext.comparison_history()
to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
