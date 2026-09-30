\set ON_ERROR_STOP on

do $roles$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end
$roles$;

create schema if not exists auth;
create schema if not exists fitmatch_vnext;

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

grant usage on schema public, fitmatch_vnext to anon, authenticated, service_role;
grant execute on function auth.uid() to public;

create table if not exists fitmatch_vnext.garment_types (
    garment_type_code text primary key,
    category_code text not null
);

create table if not exists fitmatch_vnext.products (
    id uuid primary key,
    source_product_key text,
    garment_type_code text references fitmatch_vnext.garment_types(garment_type_code)
);

create table if not exists fitmatch_vnext.closet_items (
    id uuid primary key,
    user_id uuid not null,
    client_item_id uuid not null
);

create table if not exists fitmatch_vnext.comparisons (
    id uuid primary key,
    user_id uuid not null,
    client_comparison_id uuid not null,
    reference_closet_item_id uuid,
    target_product_id uuid not null,
    result_status text not null,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    unique (user_id, client_comparison_id)
);

insert into fitmatch_vnext.garment_types (
    garment_type_code,
    category_code
) values ('tshirt', 'tops')
on conflict (garment_type_code) do nothing;

insert into fitmatch_vnext.products (
    id,
    source_product_key,
    garment_type_code
) values (
    '30000000-0000-0000-0000-000000000001',
    'E500001',
    'tshirt'
) on conflict (id) do nothing;

insert into fitmatch_vnext.closet_items (
    id,
    user_id,
    client_item_id
) values
    (
        '40000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        '50000000-0000-0000-0000-000000000001'
    ),
    (
        '40000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000002',
        '50000000-0000-0000-0000-000000000002'
    )
on conflict (id) do nothing;

insert into fitmatch_vnext.comparisons (
    id,
    user_id,
    client_comparison_id,
    reference_closet_item_id,
    target_product_id,
    result_status,
    deleted_at,
    created_at
) values
    (
        '60000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        'COMPLETED',
        null,
        '2026-08-31T00:00:00Z'
    ),
    (
        '60000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000002',
        '70000000-0000-0000-0000-000000000002',
        '40000000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-000000000001',
        'COMPLETED',
        null,
        '2026-08-31T00:01:00Z'
    ),
    (
        '60000000-0000-0000-0000-000000000003',
        '10000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000003',
        '40000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        'PENDING',
        null,
        '2026-08-31T00:02:00Z'
    )
on conflict (id) do nothing;

