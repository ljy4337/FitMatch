begin;
delete from fitmatch_catalog.source_category_comparison_groups where policy_version='retailer-comparison-groups-v3-seven-20260911' and mapping_basis='RETAILER_API_CATEGORY_AUDIT_APPROVED_20260916';
do $$ begin if (select count(*) from fitmatch_catalog.source_category_comparison_groups where policy_version='retailer-comparison-groups-v3-seven-20260911' and mapping_basis='RETAILER_API_CATEGORY_AUDIT_APPROVED_20260916')<>0 then raise exception 'rollback verification failed'; end if; end $$;
commit;
