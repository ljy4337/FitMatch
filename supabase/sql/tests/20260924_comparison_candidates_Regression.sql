\set ON_ERROR_STOP on
create role anon; create role authenticated;
create schema auth; create schema fitmatch_vnext;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create table fitmatch_vnext.products(id uuid primary key);
create table fitmatch_vnext.product_variants(id uuid primary key,product_id uuid,sort_order integer);
create table fitmatch_vnext.closet_items(id uuid primary key,user_id uuid,deleted_at timestamptz,updated_at timestamptz,comparison_group_code text,item_name text,size_label text,product_id uuid,product_variant_id uuid,product_size_id uuid,is_reference boolean);
create table calls(id uuid);
create function fitmatch_vnext.product_comparison_group(uuid) returns jsonb language sql as $$ select '{"group_code":"A"}'::jsonb $$;
create function fitmatch_vnext.closet_comparison_group(uuid) returns jsonb language sql as $$ select jsonb_build_object('group_code',comparison_group_code) from fitmatch_vnext.closet_items where id=$1 $$;
create function fitmatch_vnext.effective_target_classification(uuid) returns jsonb language sql as $$ select '{}'::jsonb $$;
create function fitmatch_vnext.comparison_target_context(uuid,uuid,text) returns jsonb language plpgsql as $$ begin if $3 not in ('A','B') then raise exception 'invalid group'; end if; return jsonb_build_object('target_comparison_group',jsonb_build_object('group_code',$3),'effective_classification','{}'::jsonb); end $$;
create function fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean,text default null) returns jsonb language plpgsql as $$ begin insert into public.calls values($1); return jsonb_build_object('allowed',true,'decision','MANUAL_EXTENDED','mode','MANUAL_EXTENDED','authorized_candidate_product_size_ids',jsonb_build_array('00000000-0000-0000-0000-000000000031'),'candidates',jsonb_build_array(jsonb_build_object('comparison_measurements',jsonb_build_array(jsonb_build_object('value',42))))); end $$;
insert into fitmatch_vnext.products values('00000000-0000-0000-0000-000000000001');
insert into fitmatch_vnext.product_variants values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',0);
select set_config('test.uid','00000000-0000-0000-0000-000000000010',false);
insert into fitmatch_vnext.closet_items(id,user_id,updated_at,comparison_group_code,item_name,size_label,is_reference) values
('00000000-0000-0000-0000-000000000021',auth.uid(),now(),'A','First','M',false),
('00000000-0000-0000-0000-000000000022',auth.uid(),now(),'A','Second','L',false),
('00000000-0000-0000-0000-000000000023',auth.uid(),now(),'B','Outer','L',false),
('00000000-0000-0000-0000-000000000024','00000000-0000-0000-0000-000000000099',now(),'A','Other user','M',false);
\ir 20260924_comparison_candidates_Baseline.sql
-- RED adapter represents the previous whole-list selection path.
create function public.fitmatch_vnext_find_selected_reference_candidate(p_target_product_id uuid,p_target_variant_id uuid,p_reference_closet_item_id uuid,p_requested_group_code text default null) returns jsonb language sql as $$ select fitmatch_vnext.find_reference_candidates($1,$2,$4) $$;
create temp table baseline as select g,fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',g) payload from (values(null::text),('A'),('B')) t(g);
\if :apply
\ir ../../migrations/20260924130000_selected_comparison_candidate.sql
\endif

do $$
#variable_conflict use_variable
declare actual jsonb; expected jsonb; g text; rid uuid; begin
for g in select unnest(array[null,'A','B']::text[]) loop
 if fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',g) is distinct from (select payload from baseline where baseline.g is not distinct from g) then raise exception 'full list contract changed'; end if;
 for rid in select id from fitmatch_vnext.closet_items loop
 truncate calls;
 actual:=public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',rid,g);
 select jsonb_agg(v) into expected from baseline b cross join lateral jsonb_array_elements(b.payload->'candidates') v where b.g is not distinct from g and v->>'closet_item_id'=rid::text;
 if actual->'candidates' is distinct from coalesce(expected,'[]'::jsonb) then raise exception 'selected candidate differs from full-list exact item'; end if;
 select jsonb_agg(v) into expected from baseline b cross join lateral jsonb_array_elements(b.payload->'blocked') v where b.g is not distinct from g and v->>'closet_item_id'=rid::text;
 if actual->'blocked' is distinct from coalesce(expected,'[]'::jsonb) then raise exception 'selected block differs'; end if;
 if (select count(*) from calls)>1 or exists(select 1 from calls where id<>rid) then raise exception 'unselected candidate evaluated'; end if;
 end loop;
end loop;
update fitmatch_vnext.closet_items set deleted_at=now() where id='00000000-0000-0000-0000-000000000021';
actual:=public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000021',null);
if jsonb_array_length(actual->'candidates')<>0 then raise exception 'deleted item leaked'; end if;
begin perform public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',null,null); raise exception 'null accepted'; exception when others then if SQLERRM='null accepted' then raise; end if; end;
perform set_config('test.uid','',false);
begin perform public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000021',null); raise exception 'anonymous accepted'; exception when others then if SQLERRM='anonymous accepted' then raise; end if; end;
end $$;
select 'PASS: exact candidate parity, unrelated work excluded, group, ownership, deleted, null, unauthenticated' result;

\if :apply
select set_config('test.uid','00000000-0000-0000-0000-000000000010',false);
set role authenticated;
do $$ begin
 if jsonb_array_length(public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000022',null)->'candidates')<>1 then raise exception 'authenticated endpoint failed'; end if;
 if jsonb_array_length(public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000099',null)->'candidates')<>0 then raise exception 'missing item substituted'; end if;
 begin perform public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000022','INVALID'); raise exception 'bad group accepted'; exception when others then if SQLERRM='bad group accepted' then raise; end if; end;
 begin perform public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000099','00000000-0000-0000-0000-000000000022',null); raise exception 'bad variant accepted'; exception when others then if SQLERRM='bad variant accepted' then raise; end if; end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.fitmatch_vnext_find_selected_reference_candidate('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000022',null); raise exception 'anon privilege leaked'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: actual authenticated/anon role execution, missing row, invalid variant/group' result;
\ir ../20260924130000_selected_comparison_candidate_Rollback.sql
select set_config('test.uid','00000000-0000-0000-0000-000000000010',false);
update fitmatch_vnext.closet_items set deleted_at=null;
do $$ begin if exists(select 1 from baseline b where b.payload is distinct from fitmatch_vnext.find_reference_candidates('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',b.g)) then raise exception 'rollback changed output'; end if; end $$;
select 'PASS: rollback restores original JSON' result;
\endif
