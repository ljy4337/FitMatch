-- fitmatch_vnext P0-3: evidence-backed provider golden observations.
--
-- These are deliberately narrow, short-lived retailer observations captured
-- on 2026-08-29. UNKNOWN sizes are not promoted. Reapplying this migration is
-- idempotent because record_size_availability derives the same fingerprint
-- from the fixed observation timestamp and payload.

select fitmatch_vnext.record_size_availability(
    (select ps.id
     from fitmatch_vnext.products p
     join fitmatch_vnext.product_variants pv on pv.product_id = p.id
     join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
     where p.source_code = 'musinsa'
       and p.source_product_key = '6805433'
       and pv.source_variant_key = '__default__'
       and ps.source_size_key = 'xs'),
    'AVAILABLE',
    'RETAILER_OPTION_API',
    jsonb_build_object(
        'source_code', 'musinsa',
        'source_product_key', '6805433',
        'source_url', 'https://goods-detail.musinsa.com/api2/goods/6805433/options',
        'option_item_no', 31844231,
        'managed_code', 'XS',
        'activated', true,
        'is_deleted', false,
        'observation_semantics', 'exact option item active and not deleted'
    ),
    '2026-08-29 01:42:43.426905+00'::timestamptz,
    '2026-08-30 01:42:43.426905+00'::timestamptz
);

select fitmatch_vnext.record_size_availability(
    (select ps.id
     from fitmatch_vnext.products p
     join fitmatch_vnext.product_variants pv on pv.product_id = p.id
     join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
     where p.source_code = 'uniqlo'
       and p.source_product_key = 'E482856'
       and pv.source_variant_key = 'E482856-000'
       and ps.source_size_key = 'INS028'),
    'AVAILABLE',
    'RETAILER_PRODUCT_PAYLOAD',
    jsonb_build_object(
        'source_code', 'uniqlo',
        'source_product_key', 'E482856',
        'source_url', 'https://www.uniqlo.com/kr/ko/products/E482856-000/00',
        'communication_code', '485625-67-028-000',
        'source_size_key', 'INS028',
        'sales', true,
        'purchase_action_visible', true,
        'observation_semantics', 'selected representative SKU marked sales=true'
    ),
    '2026-08-29 01:42:43.426905+00'::timestamptz,
    '2026-08-30 01:42:43.426905+00'::timestamptz
);

select fitmatch_vnext.record_size_availability(
    (select ps.id
     from fitmatch_vnext.products p
     join fitmatch_vnext.product_variants pv on pv.product_id = p.id
     join fitmatch_vnext.product_sizes ps on ps.variant_id = pv.id
     where p.source_code = 'zara'
       and p.source_product_key = '561264931'
       and pv.source_variant_key = '561288459'
       and ps.source_size_key = '38'),
    'AVAILABLE',
    'RETAILER_PRODUCT_UI',
    jsonb_build_object(
        'source_code', 'zara',
        'source_product_key', '561264931',
        'source_variant_key', '561288459',
        'source_url', 'https://www.zara.com/kr/ko/aaron-levine-x-zara-%E1%84%91%E1%85%B3%E1%86%AF%E1%84%85%E1%85%B5%E1%84%8E%E1%85%B3-%E1%84%8E%E1%85%B5%E1%84%82%E1%85%A9-%E1%84%91%E1%85%A2%E1%86%AB%E1%84%8E%E1%85%B3-p06861011.html',
        'size_label', 'EU 38 (KR 30)',
        'size_button_enabled', true,
        'purchase_action_visible', true,
        'observation_semantics', 'exact size shown as enabled purchase option'
    ),
    '2026-08-29 01:42:43.426905+00'::timestamptz,
    '2026-08-30 01:42:43.426905+00'::timestamptz
);

do $verify$
begin
    if exists (
        select 1
        from (values
            ('musinsa', '6805433'),
            ('uniqlo', 'E482856'),
            ('zara', '561264931')
        ) expected(source_code, source_product_key)
        where not exists (
            select 1
            from fitmatch_vnext.products p
            where p.source_code = expected.source_code
              and p.source_product_key = expected.source_product_key
              and fitmatch_vnext.product_readiness(p.id) ->> 'status' = 'READY'
        )
    ) then
        raise exception 'Every provider golden product must be READY';
    end if;
end
$verify$;
