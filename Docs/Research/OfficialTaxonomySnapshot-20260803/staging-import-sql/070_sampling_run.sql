begin;
insert into fitmatch_staging.sampling_runs(id,import_run_id,sampling_key,status,category_count,product_count,collection_failure_count,started_at,completed_at,methodology) values ('6d15f604-5271-4309-a93a-1c7700f11fe3','40677f85-e8a0-4a72-ad27-45524f385bcf','risk-priority-1-v1','completed',100,906,0,'2026-08-03T02:09:10.656Z','2026-08-03T02:09:10.656Z','{"selection":"risk priority 1","max_products_per_category":10,"canonical_promotion":false}'::jsonb) on conflict do nothing;
commit;
