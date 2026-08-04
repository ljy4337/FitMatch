begin;

insert into fitmatch_staging.import_runs(id,import_key,schema_version,input_checksum,status,started_at,metadata)
values ('40677f85-e8a0-4a72-ad27-45524f385bcf','observed-official-taxonomy-20260803-v1','staging-v1','c65ff8700bed46840f12f70af4ed138a8319abf49b00dabc387d83e2efcdc4be','loading',now(),'{"expected":{"snapshot_nodes":4008,"candidates":1976,"edges":2034,"sampled_categories":100,"sampled_products":906},"canonical_promotion_authorized":false}'::jsonb)
on conflict (import_key) do nothing;
insert into fitmatch_staging.source_snapshots(id,import_run_id,source_code,snapshot_version,collected_at,raw_collection_status,node_count,raw_response_hash,source_evidence)
values ('0a0fab7a-e6a6-45b9-ab5c-3426aba173e3','40677f85-e8a0-4a72-ad27-45524f385bcf','musinsa','observed-2026-08-03','2026-08-03T02:01:21.580Z','collected',2277,'6bb0dbdfd64f715797b68aae979805a1901377d141823c40d20608a8eb13d4aa','{"roots":["001","002","003","004","017","026","100","101","102","103","104","105","106","107","108","109","111","112","113","114","115","116","117","118","119","120"],"pages":2277,"failures":[]}'::jsonb) on conflict do nothing;
insert into fitmatch_staging.source_snapshots(id,import_run_id,source_code,snapshot_version,collected_at,raw_collection_status,node_count,raw_response_hash,source_evidence)
values ('6b0627ec-e64b-44da-a403-6ae10976629c','40677f85-e8a0-4a72-ad27-45524f385bcf','uniqlo','observed-2026-08-03','2026-08-03T02:01:21.580Z','collected',1731,'6b534b68e52650e4593d7d29c8b70c28ee12db8018c3db81bd27902d80ad0ef9','{"url":"https://www.uniqlo.com/kr/ko/men_navigation","hash":"2dad9b2eaa9e0b3966064c40708d8fff9be454662a8eba631cdaf427266f1f53","counts":{"genders":4,"classes":43,"categories":180,"subcategories":1504}}'::jsonb) on conflict do nothing;
commit;
