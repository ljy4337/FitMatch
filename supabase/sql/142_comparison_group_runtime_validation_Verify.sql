select policy_version, status, validated_at, activated_at,
       metadata->>'runtime_rpc_connected' as runtime_rpc_connected,
       metadata->>'category_group_measurement_context'
         as category_group_measurement_context,
       metadata->>'verified_example' as verified_example
from fitmatch_catalog.comparison_group_policies
where policy_version='retailer-comparison-groups-v3-seven-20260911';
