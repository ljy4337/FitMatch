begin;

update fitmatch_catalog.comparison_group_policies
set metadata = jsonb_set(
      jsonb_set(
        jsonb_set(metadata, '{runtime_rpc_connected}', 'true'::jsonb, true),
        '{category_group_measurement_context}', 'true'::jsonb, true
      ),
      '{verified_example}',
      '"uniqlo:E487939:7-sizes:begin-and-idempotent-retry"'::jsonb,
      true
    ),
    validated_at = now()
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
