-- Recovery for 20260914080000_group_policy_activation_bfg.sql.
-- Apply only before 20260914090000_session_requested_comparison_group_authority.sql
-- is deployed and while comparison traffic is stopped.

begin;

update fitmatch_vnext.comparison_policies
set is_active = false,
    min_common_measurements = 2,
    required_any_min = 1,
    audience_policy_code = 'SAME_OR_UNISEX',
    allow_manual_extended = false,
    policy_version = 'vnext-policy-20260829-v1',
    policy_checksum = '8db3317b56c43f1aa190db9d63a2a518030c5bd1cac0b5dbfbced94bee9e5033',
    updated_at = now()
where policy_code = 'unclassified_outerwear';

update fitmatch_vnext.comparison_policies
set is_active = false,
    min_common_measurements = 2,
    required_any_min = 0,
    audience_policy_code = 'SAME_OR_UNISEX',
    allow_manual_extended = false,
    policy_version = 'vnext-policy-20260829-v1',
    policy_checksum = '72a41609fbbb212e81b9bd4c636e3729cf9f76a244cd8cb2bf72dfc9b7a2257e',
    updated_at = now()
where policy_code = 'generic_underwear';

update fitmatch_vnext.comparison_policies
set is_active = false,
    min_common_measurements = 2,
    required_any_min = 0,
    audience_policy_code = 'SAME_OR_UNISEX',
    allow_manual_extended = false,
    policy_version = 'vnext-policy-20260829-v1',
    policy_checksum = '711f1b6d9258cfc1a5737eada15f82ac2b1b443068a1cca4a1b885973410dab8',
    updated_at = now()
where policy_code = 'homewear_set';

commit;
