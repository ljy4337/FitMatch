begin;
do $test$
declare
 u uuid; p record; tuple jsonb; canonical jsonb; request jsonb; result jsonb;
 saved uuid; retry jsonb; count_before bigint;
begin
 select id into strict u from auth.users order by created_at limit 1;
 select count(*) into count_before from fitmatch_vnext.closet_items;
 select pr.id as product_id,ps.id as size_id,pv.id as variant_id into strict p
 from fitmatch_vnext.products pr
 join fitmatch_vnext.product_variants pv on pv.product_id=pr.id
 join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id
 where pr.source_product_key='E484080' order by ps.id limit 1;
 tuple:=fitmatch_vnext.comparison_group_tuple(p.product_id,null);
 canonical:=fitmatch_vnext.canonical_measurements_for_size_with_context(
 p.size_id,tuple || jsonb_build_object('product_id',p.product_id,'effective_source','USER_EXPLICIT'));
 request:=jsonb_build_object('client_item_id',gen_random_uuid(),'product_id',p.product_id,
 'product_variant_id',p.variant_id,'product_size_id',p.size_id,
 'measurements',canonical->'measurements','fit_preference_code','regular');
 perform set_config('request.jwt.claim.sub',u::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 result:=public.fitmatch_vnext_upsert_closet_item(request);
 saved:=(result->>'item_id')::uuid;
 if saved is null then raise exception 'Missing save receipt'; end if;
 retry:=public.fitmatch_vnext_upsert_closet_item(request);
 if (retry->>'item_id')::uuid<>saved then raise exception 'Retry changed identity'; end if;
 result:=public.fitmatch_vnext_update_closet_item(saved,request);
 if (result->>'closet_item_id')::uuid<>saved then raise exception 'Update receipt mismatch'; end if;
 if not exists(select 1 from fitmatch_vnext.closet_items where id=saved
 and user_id=u and classification_source='BACKEND'
 and classification_resolver_version='comparison-group-v3' and satisfaction is null)
 then raise exception 'Readback mismatch'; end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 perform set_config('request.jwt.claims','{}',true);
 begin
  perform public.fitmatch_vnext_update_closet_item(saved,request);
  raise exception 'Cross-user update incorrectly accepted';
 exception when others then
  if sqlerrm <> 'Closet item not found or not owned' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.fitmatch_vnext_upsert_closet_item(request);
  raise exception 'Missing session incorrectly accepted';
 exception when others then
  if sqlerrm <> 'Authentication required' then raise; end if;
 end;
 execute 'reset role';
 if (select count(*) from fitmatch_vnext.closet_items)<>count_before+1 then
  raise exception 'Unexpected fixture count';
 end if;
 perform set_config('fitmatch.permission_test','PASS: authenticated save, idempotent retry, update, readback, cross-user denial, missing-session denial',true);
end $test$;
select current_setting('fitmatch.permission_test') as result;
rollback;
