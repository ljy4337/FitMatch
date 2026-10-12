-- PROPOSAL ONLY. No remote application authorized by this file.
-- Owner-private, immutable user transcription. Official facts/FKs/scoring remain authoritative.
-- Apply transaction aborts on unrecognized deployed definitions (LF-normalized MD5); use matching Verify/Rollback.
-- Captured target: FitMatch-QA hnkplvyegonlhumlejst, 2026-10-12.
-- Selecting another environment, including Production, requires separate explicit authorization.
begin;

create table fitmatch_vnext.bugfix1012_recovery_backups (
  object_signature text primary key, definition text not null, applied_definition text
);
revoke all on fitmatch_vnext.bugfix1012_recovery_backups from public,anon,authenticated,service_role;
-- Guarded deployed function backups are populated below before any replacement.
do $official_fk$
begin
 if not exists(select 1 from pg_constraint where conrelid='fitmatch_vnext.comparisons'::regclass
 and conname='comparisons_recommended_product_size_fkey'
 and pg_get_constraintdef(oid)='FOREIGN KEY (recommended_product_size_id) REFERENCES fitmatch_vnext.product_sizes(id) ON DELETE RESTRICT') then
 raise exception 'Unrecognized official recommended size FK'; end if;
end $official_fk$;


create table fitmatch_vnext.user_size_recoveries (
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  product_id uuid not null references fitmatch_vnext.products(id) on delete restrict,
  variant_id uuid not null references fitmatch_vnext.product_variants(id) on delete restrict,
  official_size_id uuid references fitmatch_vnext.product_sizes(id) on delete restrict,
  recovery_size_id uuid not null unique default gen_random_uuid(),
  source_observation_id uuid not null references fitmatch_vnext.product_ingestion_receipts(id),
  input_source text not null check(input_source in ('USER_OCR','USER_MANUAL')),
  size_label text not null check(nullif(btrim(size_label),'') is not null),
  request_payload jsonb not null check(jsonb_typeof(request_payload)='object'),
  canonical_measurements jsonb not null check(jsonb_typeof(canonical_measurements)='array'),
  original_rows jsonb not null check(jsonb_typeof(original_rows)='array'),
  created_at timestamptz not null default now(),
  primary key(owner_id,request_id)
);
create table fitmatch_vnext.active_user_size_recoveries (
  owner_id uuid not null, product_id uuid not null, variant_id uuid not null,
  request_id uuid not null,
  primary key(owner_id,product_id,variant_id),
  foreign key(owner_id,request_id) references fitmatch_vnext.user_size_recoveries(owner_id,request_id) on delete cascade
);
alter table fitmatch_vnext.user_size_recoveries enable row level security;
alter table fitmatch_vnext.active_user_size_recoveries enable row level security;
create policy user_size_recovery_owner_read on fitmatch_vnext.user_size_recoveries
 for select to authenticated using(owner_id=(select auth.uid()));
create policy active_user_size_recovery_owner_read on fitmatch_vnext.active_user_size_recoveries
 for select to authenticated using(owner_id=(select auth.uid()));
revoke all on fitmatch_vnext.user_size_recoveries,fitmatch_vnext.active_user_size_recoveries from public,anon,authenticated,service_role;
grant select on fitmatch_vnext.user_size_recoveries,fitmatch_vnext.active_user_size_recoveries to authenticated;

create function fitmatch_vnext.protect_user_size_recovery() returns trigger
 language plpgsql set search_path='' as $$
begin raise exception 'User size recovery receipt is immutable'; end $$;
create trigger user_size_recovery_immutable before update on fitmatch_vnext.user_size_recoveries
 for each row execute function fitmatch_vnext.protect_user_size_recovery();

create function fitmatch_vnext.user_size_recovery_receipt(p_row fitmatch_vnext.user_size_recoveries)
 returns jsonb language sql stable set search_path='' as $$
select jsonb_build_object('owner_id',p_row.owner_id,'request_id',p_row.request_id,
 'product_id',p_row.product_id,'variant_id',p_row.variant_id,'official_size_id',p_row.official_size_id,
 'size_id',coalesce(p_row.official_size_id,p_row.recovery_size_id),
 'identity_kind',case when p_row.official_size_id is null then 'USER_RECOVERY' else 'RETAILER_SIZE' end,
 'request_payload',p_row.request_payload,'state','saved')
$$;

create function fitmatch_vnext.get_user_size_recovery(p_request_id uuid) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare r fitmatch_vnext.user_size_recoveries%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into r from fitmatch_vnext.user_size_recoveries where owner_id=auth.uid() and request_id=p_request_id;
 if not found then raise exception 'Recovery not found or not owned'; end if;
 return fitmatch_vnext.user_size_recovery_receipt(r);
end $$;

create function fitmatch_vnext.save_user_size_recovery(p_request jsonb) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare
 caller uuid:=auth.uid(); req uuid; pid uuid; vid uuid; official uuid; observation uuid;
 r fitmatch_vnext.user_size_recoveries%rowtype; measurement jsonb; dictionary fitmatch_vnext.fitmatch_measurements%rowtype;
 canonical jsonb:='[]'; effective jsonb;
begin
 if caller is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if jsonb_typeof(p_request) is distinct from 'object' then raise exception 'Recovery request object required' using errcode='22023'; end if;
 if (p_request->>'owner_id')::uuid is distinct from caller then raise exception 'Recovery owner mismatch' using errcode='42501'; end if;
 req:=(p_request->>'request_id')::uuid; pid:=(p_request->>'product_id')::uuid;
 vid:=(p_request->>'variant_id')::uuid; official:=(p_request->>'official_size_id')::uuid;
 observation:=(p_request->>'source_observation_id')::uuid;
 if req is null or pid is null or vid is null or observation is null or not(p_request ? 'official_size_id') then
  raise exception 'Exact request, product, variant, observation and official/user identity required' using errcode='22023'; end if;
 -- Serialize same request retries; a response lost after commit cannot create a new identity.
 perform pg_advisory_xact_lock(hashtextextended(caller::text||':'||req::text,0));
 select * into r from fitmatch_vnext.user_size_recoveries where owner_id=caller and request_id=req;
 if found then
  if r.request_payload is distinct from p_request then raise exception 'Recovery idempotency payload conflict' using errcode='22023'; end if;
  return fitmatch_vnext.user_size_recovery_receipt(r);
 end if;
 if not exists(select 1 from fitmatch_vnext.product_variants where id=vid and product_id=pid) then
  raise exception 'Recovery product variant hierarchy mismatch' using errcode='22023'; end if;
 if official is not null and not exists(select 1 from fitmatch_vnext.product_sizes where id=official and variant_id=vid) then
  raise exception 'Recovery official size hierarchy mismatch' using errcode='22023'; end if;
 if not exists(select 1 from fitmatch_vnext.product_ingestion_receipts where id=observation and product_id=pid and processing_status='COMPLETED') then
  raise exception 'Recovery source observation product mismatch' using errcode='22023'; end if;
 if p_request->>'input_source' is null or p_request->>'input_source' not in ('USER_OCR','USER_MANUAL')
    or nullif(btrim(p_request->>'size_label'),'') is null then raise exception 'Recovery source and size label required' using errcode='22023'; end if;
 effective:=fitmatch_vnext.effective_target_classification(pid);
 if effective->>'classification_status' is distinct from 'CONFIRMED' then raise exception 'Current server classification required' using errcode='22023'; end if;
 if jsonb_typeof(p_request->'measurements') is distinct from 'array' or jsonb_array_length(p_request->'measurements')=0
    or jsonb_typeof(p_request->'original_rows') is distinct from 'array' or jsonb_array_length(p_request->'original_rows')=0 then
  raise exception 'Recovery canonical measurements and original user rows required' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(p_request->'measurements') m group by m->>'fitmatch_measurement_code' having count(*)>1) then
  raise exception 'Duplicate recovery canonical code' using errcode='22023'; end if;
 for measurement in select value from jsonb_array_elements(p_request->'measurements') loop
  select * into dictionary from fitmatch_vnext.fitmatch_measurements where measurement_code=measurement->>'fitmatch_measurement_code' and is_active;
  if not found or jsonb_typeof(measurement->'value') is distinct from 'number'
    or (measurement->>'value')::numeric<=0 or (measurement->>'value')::numeric::text in ('NaN','Infinity','-Infinity')
    or measurement->>'unit_code' is distinct from dictionary.canonical_unit_code
    or (measurement->>'basis_code' is not null and measurement->>'basis_code' is distinct from dictionary.canonical_basis_code)
    or nullif(btrim(measurement->>'raw_label'),'') is null then
   raise exception 'Recovery active canonical code, finite positive value, exact unit and basis required' using errcode='22023'; end if;
  canonical:=canonical||jsonb_build_array(jsonb_build_object(
    'fitmatch_measurement_code',dictionary.measurement_code,'value',(measurement->>'value')::numeric,
    'unit_code',dictionary.canonical_unit_code,'basis_code',dictionary.canonical_basis_code,
    'source_measurement_code',null,'resolution_path',p_request->>'input_source',
    'raw_evidence_fingerprint',md5(p_request::text),'raw_label',measurement->>'raw_label',
    'raw_value_text',measurement->>'raw_value_text'));
 end loop;
 for measurement in select value from jsonb_array_elements(p_request->'original_rows') loop
  if jsonb_typeof(measurement) is distinct from 'object' or nullif(btrim(measurement->>'raw_label'),'') is null
    or jsonb_typeof(measurement->'value') is distinct from 'number' or (measurement->>'value')::numeric<0
    or (measurement->>'value')::numeric::text in ('NaN','Infinity','-Infinity') or measurement->>'unit_code' is distinct from 'cm' then
   raise exception 'Original user row label, finite nonnegative value and unit required' using errcode='22023'; end if;
 end loop;
 insert into fitmatch_vnext.user_size_recoveries(owner_id,request_id,product_id,variant_id,official_size_id,
 source_observation_id,input_source,size_label,request_payload,canonical_measurements,original_rows)
 values(caller,req,pid,vid,official,observation,p_request->>'input_source',p_request->>'size_label',p_request,canonical,p_request->'original_rows') returning * into r;
 insert into fitmatch_vnext.active_user_size_recoveries values(caller,pid,vid,req)
 on conflict(owner_id,product_id,variant_id) do update set request_id=excluded.request_id;
 return fitmatch_vnext.user_size_recovery_receipt(r);
exception when invalid_text_representation or numeric_value_out_of_range then
 raise exception 'Invalid recovery typed input' using errcode='22023';
end $$;

create function public.fitmatch_vnext_save_user_size_recovery(p_request jsonb) returns jsonb
 language sql security invoker set search_path='' as $$select fitmatch_vnext.save_user_size_recovery(p_request)$$;
create function public.fitmatch_vnext_get_user_size_recovery(p_request_id uuid) returns jsonb
 language sql security invoker set search_path='' as $$select fitmatch_vnext.get_user_size_recovery(p_request_id)$$;

create function fitmatch_vnext.comparison_product_sizes(p_include_inactive boolean default false)
 returns setof fitmatch_vnext.product_sizes language sql stable security definer set search_path='' as $$
 select ps.* from fitmatch_vnext.product_sizes ps
 union all
 select r.recovery_size_id,r.variant_id,'user-recovery:'||r.request_id::text,r.size_label,
 null::text,'UNKNOWN'::text,2147483647,r.created_at,r.created_at,r.created_at
 from fitmatch_vnext.user_size_recoveries r
 where r.owner_id=auth.uid() and r.official_size_id is null
 and (p_include_inactive or exists(select 1 from fitmatch_vnext.active_user_size_recoveries a
 where a.owner_id=r.owner_id and a.product_id=r.product_id and a.variant_id=r.variant_id and a.request_id=r.request_id))
$$;

create function fitmatch_vnext.user_size_recovery_metadata(p_size_id uuid) returns jsonb
 language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object(
 'identity_kind',case when r.official_size_id is null then 'USER_RECOVERY' else 'RETAILER_SIZE' end,
 'recovery_request_id',r.request_id,'owner_user_id',r.owner_id,'input_source',r.input_source,
 'source_observation_id',r.source_observation_id)
 from fitmatch_vnext.user_size_recoveries r join fitmatch_vnext.active_user_size_recoveries a
 on a.owner_id=r.owner_id and a.request_id=r.request_id
 where r.owner_id=auth.uid() and coalesce(r.official_size_id,r.recovery_size_id)=p_size_id),'{}'::jsonb)
$$;

-- Canonical wrapper is created after guard/backup of the existing resolver below.

do $guard$
declare r record; actual text;
begin
 for r in select * from (values
  ('fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)','3bad84cc862151e479946261126ec0e6'),
  ('fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)','3360061ebd04240f4704a4a1cd117277'),
  ('fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean,text)','2b4355e8478fa925a269f60d188dae9c'),
  ('fitmatch_vnext.get_product_runtime_for_swift(text,text)','385b78f0fea567c0367804260d253ce5'),
  ('fitmatch_vnext.product_measurement_readiness(uuid,jsonb)','4d9516769c12b658ab5ea05fae7b235f'),
  ('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)','dcab58b5a92f13e877deaeeaa2eae5a3'),
  ('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)','669db92dfa1baf41dba949d08f6f0fb2'),
  ('fitmatch_vnext.complete_comparison(uuid,jsonb)','73b596a1bda260e16834b03e9f7368f7'),
  ('fitmatch_vnext.get_product_runtime_base(text,text,boolean)','fd985da7af3436a0d17477d580d5786e'),
  ('fitmatch_vnext.protect_completed_comparison()','1e6e15dec62d631de4893b95c822e509'),
  ('fitmatch_vnext.comparison_history()','e7fbfff5b5ad7b2b547e655f1f0e437f'),
  ('fitmatch_vnext.validate_comparison_completion_payload()','55feee500250b836bd8a1eec36c4b9e1')
 ) expected(signature,expected_hash) loop
  actual:=pg_get_functiondef(r.signature::regprocedure);
  if md5(replace(actual,chr(13)||chr(10),chr(10)))<>r.expected_hash then raise exception 'Unrecognized recovery baseline: % hash %',r.signature,md5(actual); end if;
  insert into fitmatch_vnext.bugfix1012_recovery_backups values(r.signature,actual,null);
 end loop;
end $guard$;

alter table fitmatch_vnext.comparisons add column recommended_user_recovery_size_id uuid
 references fitmatch_vnext.user_size_recoveries(recovery_size_id) on delete restrict;
alter table fitmatch_vnext.comparisons add constraint comparisons_single_recommended_identity_chk
 check(recommended_product_size_id is null or recommended_user_recovery_size_id is null);

create function fitmatch_vnext.validate_recommended_user_recovery() returns trigger
 language plpgsql security definer set search_path='' as $identity$
begin
 if new.recommended_user_recovery_size_id is not null and not exists(
  select 1 from fitmatch_vnext.user_size_recoveries r
  where r.recovery_size_id=new.recommended_user_recovery_size_id and r.official_size_id is null
   and r.owner_id=new.user_id and r.product_id=new.target_product_id and r.variant_id=new.target_variant_id
   and exists(select 1 from jsonb_array_elements(new.target_snapshot->'candidates') c
    where (c->>'product_size_id')::uuid=r.recovery_size_id
      and c->>'identity_kind'='USER_RECOVERY' and (c->>'owner_user_id')::uuid=r.owner_id
      and (c->>'recovery_request_id')::uuid=r.request_id)
 ) then raise exception 'Recommended user recovery owner or snapshot identity mismatch'; end if;
 return new;
end $identity$;
create trigger validate_recommended_user_recovery before insert or update on fitmatch_vnext.comparisons
 for each row execute function fitmatch_vnext.validate_recommended_user_recovery();

do $constraint$
declare original text;
begin
 select pg_get_constraintdef(oid) into original from pg_constraint
 where conrelid='fitmatch_vnext.comparisons'::regclass and conname='comparisons_recommended_authority_chk';
 if original is null or position('recommended_product_size_id IS NOT NULL' in original)=0 then
 raise exception 'Unrecognized completed comparison authority constraint'; end if;
 insert into fitmatch_vnext.bugfix1012_recovery_backups values('comparisons_recommended_authority_chk',original,null);
 execute 'alter table fitmatch_vnext.comparisons drop constraint comparisons_recommended_authority_chk';
 execute 'alter table fitmatch_vnext.comparisons add constraint comparisons_recommended_authority_chk '||
 replace(replace(original,'recommended_product_size_id IS NOT NULL','COALESCE(recommended_product_size_id,recommended_user_recovery_size_id) IS NOT NULL'),
 'recommended_product_size_id IS NULL','COALESCE(recommended_product_size_id,recommended_user_recovery_size_id) IS NULL');
end $constraint$;

alter function fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)
 rename to canonical_measurements_for_size_with_context_before_user_recovery;
create function fitmatch_vnext.canonical_measurements_for_size_with_context(p_product_size_id uuid,p_effective_classification jsonb)
 returns jsonb language plpgsql stable security invoker set search_path='' as $canonical$
declare r fitmatch_vnext.user_size_recoveries%rowtype; original jsonb; result_rows jsonb;
begin
 select recovery.* into r from fitmatch_vnext.user_size_recoveries recovery
 join fitmatch_vnext.active_user_size_recoveries a on a.owner_id=recovery.owner_id and a.request_id=recovery.request_id
 where recovery.owner_id=auth.uid() and coalesce(recovery.official_size_id,recovery.recovery_size_id)=p_product_size_id;
 if not found then
  return fitmatch_vnext.canonical_measurements_for_size_with_context_before_user_recovery(p_product_size_id,p_effective_classification);
 end if;
 if r.product_id is distinct from (p_effective_classification->>'product_id')::uuid then raise exception 'Measurement context product mismatch'; end if;
 if p_effective_classification->>'classification_status' is distinct from 'CONFIRMED' then raise exception 'Current server classification required'; end if;
 if r.official_size_id is not null then
  original:=fitmatch_vnext.canonical_measurements_for_size_with_context_before_user_recovery(p_product_size_id,p_effective_classification);
 else original:=jsonb_build_object('measurements','[]'::jsonb,'raw_measurement_count',0,'semantic_conflict_count',0,'unresolved_count',0); end if;
 -- Explicit canonical identities supplement only the caller's projection; retailer rows remain immutable.
 select coalesce(jsonb_agg(value),'[]'::jsonb) into result_rows from (
  select value from jsonb_array_elements(original->'measurements') official
  where not exists(select 1 from jsonb_array_elements(r.canonical_measurements) user_row
    where user_row->>'fitmatch_measurement_code'=official->>'fitmatch_measurement_code')
  union all select value from jsonb_array_elements(r.canonical_measurements)
 ) combined;
 return original||jsonb_build_object('product_size_id',p_product_size_id,'measurements',result_rows,
 'raw_measurement_count',coalesce((original->>'raw_measurement_count')::int,0)+jsonb_array_length(r.original_rows),
 'classification_context_source',p_effective_classification->>'effective_source',
 'resolver_version','fitmatch-vnext-user-size-recovery-v1','identity_kind',case when r.official_size_id is null then 'USER_RECOVERY' else 'RETAILER_SIZE' end,
 'recovery_request_id',r.request_id,'owner_user_id',r.owner_id,'input_source',r.input_source,'source_observation_id',r.source_observation_id);
end $canonical$;
-- Preserve the preexisting resolver's exact executor grants and invoker security.
do $resolver_acl$
declare permission record; role_name text;
begin
 for permission in select acl.* from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
 where p.oid='fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)'::regprocedure loop
  role_name:=case when permission.grantee=0 then 'PUBLIC' else quote_ident(pg_get_userbyid(permission.grantee)) end;
  execute 'revoke all on function fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb) from '||role_name;
 end loop;
 for permission in select acl.* from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
 where p.oid='fitmatch_vnext.canonical_measurements_for_size_with_context_before_user_recovery(uuid,jsonb)'::regprocedure loop
  role_name:=case when permission.grantee=0 then 'PUBLIC' else quote_ident(pg_get_userbyid(permission.grantee)) end;
  execute 'grant '||permission.privilege_type||' on function fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb) to '||role_name||case when permission.is_grantable then ' with grant option' else '' end;
 end loop;
end $resolver_acl$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)';
 body:=replace(body,$old$        from fitmatch_vnext.product_sizes ps
$old$,$new$        from fitmatch_vnext.comparison_product_sizes() ps
$new$);
 body:=replace(body,$old$            'authorization', authorization_value
        );
$old$,$new$            'authorization', authorization_value
        );

        candidate_value := candidate_value || fitmatch_vnext.user_size_recovery_metadata(size_row.product_size_id);
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean,text)';
 body:=replace(body,$old$    from fitmatch_vnext.product_sizes ps
$old$,$new$    from fitmatch_vnext.comparison_product_sizes() ps
$new$);
 body:=replace(body,$old$      'authorization', authorization_value
    );
$old$,$new$      'authorization', authorization_value
    );
    candidate_value := candidate_value || fitmatch_vnext.user_size_recovery_metadata(size_row.product_size_id);
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.get_product_runtime_for_swift(text,text)';
 body:=replace(body,$old$            );
$old$,$new$            );
            size_value := size_value || fitmatch_vnext.user_size_recovery_metadata((size_value->>'id')::uuid);
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.product_measurement_readiness(uuid,jsonb)';
 body:=replace(body,$old$  join fitmatch_vnext.product_sizes ps on ps.variant_id=pv.id
$old$,$new$  join fitmatch_vnext.comparison_product_sizes() ps on ps.variant_id=pv.id
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)';
 body:=replace(body,$old$  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.product_sizes ps
$old$,$new$  IF NOT EXISTS (SELECT 1 FROM fitmatch_vnext.comparison_product_sizes() ps
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)';
 body:=replace(body,$old$    from fitmatch_vnext.product_sizes ps
$old$,$new$    from fitmatch_vnext.comparison_product_sizes() ps
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.complete_comparison(uuid,jsonb)';
 body:=replace(body,$old$            'recommended_product_size_id', row_value.recommended_product_size_id,
$old$,$new$            'recommended_product_size_id', coalesce(row_value.recommended_product_size_id,row_value.recommended_user_recovery_size_id),
$new$);
 body:=replace(body,$old$    from fitmatch_vnext.product_sizes ps
$old$,$new$    from fitmatch_vnext.comparison_product_sizes(true) ps
$new$);
 body:=replace(body,$old$    set recommended_product_size_id = recommended_id,
$old$,$new$    set recommended_product_size_id = case when exists(select 1 from fitmatch_vnext.product_sizes where id=recommended_id) then recommended_id end,
        recommended_user_recovery_size_id = case when not exists(select 1 from fitmatch_vnext.product_sizes where id=recommended_id) then recommended_id end,
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.get_product_runtime_base(text,text,boolean)';
 body:=replace(body,$old$                    from fitmatch_vnext.product_sizes ps
$old$,$new$                    from fitmatch_vnext.comparison_product_sizes() ps
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.protect_completed_comparison()';
 body:=replace(body,$old$        or new.recommended_product_size_id is distinct from old.recommended_product_size_id
$old$,$new$        or new.recommended_product_size_id is distinct from old.recommended_product_size_id
        or new.recommended_user_recovery_size_id is distinct from old.recommended_user_recovery_size_id
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.comparison_history()';
 body:=replace(body,$old$            to_jsonb(comparison_value) || jsonb_build_object(
$old$,$new$            to_jsonb(comparison_value) || jsonb_build_object(
                'recommended_product_size_id',coalesce(comparison_value.recommended_product_size_id,comparison_value.recommended_user_recovery_size_id),
$new$);
 execute body;
end $patch$;

do $patch$
declare body text;
begin
 select replace(definition,chr(13)||chr(10),chr(10)) into body from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='fitmatch_vnext.validate_comparison_completion_payload()';
 body:=replace(body,$old$            is distinct from new.recommended_product_size_id
$old$,$new$            is distinct from coalesce(new.recommended_product_size_id,new.recommended_user_recovery_size_id)
$new$);
 execute body;
end $patch$;

-- All private recovery helpers have explicit privileges; no default PUBLIC execute.
do $permissions$
declare r record;
begin
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='fitmatch_vnext' and p.proname in ('protect_user_size_recovery','user_size_recovery_receipt',
 'get_user_size_recovery','save_user_size_recovery','comparison_product_sizes','user_size_recovery_metadata','validate_recommended_user_recovery') loop
  execute 'revoke all on function '||r.signature||' from public,anon,authenticated,service_role';
 end loop;
end $permissions$;
grant execute on function fitmatch_vnext.get_user_size_recovery(uuid),fitmatch_vnext.save_user_size_recovery(jsonb)
 to authenticated;
revoke all on function public.fitmatch_vnext_save_user_size_recovery(jsonb),public.fitmatch_vnext_get_user_size_recovery(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.fitmatch_vnext_save_user_size_recovery(jsonb),public.fitmatch_vnext_get_user_size_recovery(uuid) to authenticated;
-- Existing SECURITY DEFINER comparison functions invoke internal helpers as their owner.
update fitmatch_vnext.bugfix1012_recovery_backups
set applied_definition=pg_get_functiondef(object_signature::regprocedure)
where object_signature<>'comparisons_recommended_authority_chk';
commit;
