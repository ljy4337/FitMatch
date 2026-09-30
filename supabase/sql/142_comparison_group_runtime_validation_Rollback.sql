begin;

update fitmatch_catalog.comparison_group_policies
set metadata = (metadata - 'category_group_measurement_context' - 'verified_example')
      || jsonb_build_object('runtime_rpc_connected', false),
    validated_at = now()
where policy_version='retailer-comparison-groups-v3-seven-20260911';

commit;
