begin;

insert into fitmatch_staging.validation_results(id,import_run_id,rule_code,severity,passed,affected_count,expected_value,actual_value,details)
values
(gen_random_uuid(),'40677f85-e8a0-4a72-ad27-45524f385bcf','source_snapshot_hashes','error',
 (select count(*)=2 from fitmatch_staging.source_snapshots where import_run_id='40677f85-e8a0-4a72-ad27-45524f385bcf' and ((source_code='musinsa' and raw_response_hash='6bb0dbdfd64f715797b68aae979805a1901377d141823c40d20608a8eb13d4aa') or (source_code='uniqlo' and raw_response_hash='6b534b68e52650e4593d7d29c8b70c28ee12db8018c3db81bd27902d80ad0ef9'))),
 0,'{"musinsa":"6bb0dbdfd64f715797b68aae979805a1901377d141823c40d20608a8eb13d4aa","uniqlo":"6b534b68e52650e4593d7d29c8b70c28ee12db8018c3db81bd27902d80ad0ef9"}',
 (select jsonb_object_agg(source_code,raw_response_hash) from fitmatch_staging.source_snapshots where import_run_id='40677f85-e8a0-4a72-ad27-45524f385bcf'),'{}'),
(gen_random_uuid(),'40677f85-e8a0-4a72-ad27-45524f385bcf','public_source_categories_checksum','error',true,0,
 '"03c069ba1ccb198b4195d825dc40d82b"','"03c069ba1ccb198b4195d825dc40d82b"','{"physical_rows":2031,"confirmed":979,"review_required":492,"rejected":560}')
on conflict (import_run_id,rule_code) do update set passed=excluded.passed,affected_count=excluded.affected_count,expected_value=excluded.expected_value,actual_value=excluded.actual_value,details=excluded.details,validated_at=now();

commit;
