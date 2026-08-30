-- fitmatch_vnext P0-5: additive begin/complete history with immutable snapshots.

alter table fitmatch_vnext.comparisons
    add column if not exists recommended_product_size_id uuid,
    add column if not exists request_payload_hash text,
    add column if not exists result_payload_hash text,
    add column if not exists authorization_mode text,
    add column if not exists excluded_measurement_codes text[] not null default '{}'::text[],
    add column if not exists reference_snapshot jsonb not null default '{}'::jsonb,
    add column if not exists target_snapshot jsonb not null default '{}'::jsonb,
    add column if not exists authority_snapshot jsonb not null default '{}'::jsonb,
    add column if not exists policy_snapshot jsonb not null default '{}'::jsonb,
    add column if not exists authorization_snapshot jsonb not null default '{}'::jsonb,
    add column if not exists input_snapshot jsonb not null default '{}'::jsonb,
    add column if not exists result_evidence jsonb not null default '{}'::jsonb,
    add column if not exists completed_at timestamptz;

do $migration$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'comparisons_recommended_product_size_fkey'
          and conrelid = 'fitmatch_vnext.comparisons'::regclass
    ) then
        alter table fitmatch_vnext.comparisons
            add constraint comparisons_recommended_product_size_fkey
            foreign key (recommended_product_size_id)
            references fitmatch_vnext.product_sizes(id) on delete restrict;
    end if;
end
$migration$;

alter table fitmatch_vnext.comparisons
    drop constraint if exists comparisons_result_status_chk;
alter table fitmatch_vnext.comparisons
    add constraint comparisons_result_status_chk
    check (result_status in ('PENDING','COMPLETED','NO_RECOMMENDATION','BLOCKED','FAILED'));
alter table fitmatch_vnext.comparisons
    drop constraint if exists comparisons_recommended_authority_chk;
alter table fitmatch_vnext.comparisons
    add constraint comparisons_recommended_authority_chk
    check (
        (result_status = 'COMPLETED' and recommended_product_size_id is not null
         and recommended_size_label is not null and fit_score is not null
         and completed_at is not null)
        or
        (result_status <> 'COMPLETED' and recommended_product_size_id is null
         and recommended_size_label is null)
    );

create index if not exists comparisons_recommended_size_idx
    on fitmatch_vnext.comparisons (recommended_product_size_id)
    where recommended_product_size_id is not null;

create or replace function fitmatch_vnext.protect_completed_comparison()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if old.result_status = 'COMPLETED' and (
        new.user_id is distinct from old.user_id
        or new.client_comparison_id is distinct from old.client_comparison_id
        or new.reference_closet_item_id is distinct from old.reference_closet_item_id
        or new.target_product_id is distinct from old.target_product_id
        or new.target_variant_id is distinct from old.target_variant_id
        or new.comparison_policy_code_snapshot is distinct from old.comparison_policy_code_snapshot
        or new.comparison_mode is distinct from old.comparison_mode
        or new.recommended_product_size_id is distinct from old.recommended_product_size_id
        or new.recommended_size_label is distinct from old.recommended_size_label
        or new.fit_score is distinct from old.fit_score
        or new.reliability_level is distinct from old.reliability_level
        or new.coverage_ratio is distinct from old.coverage_ratio
        or new.result_status is distinct from old.result_status
        or new.engine_version is distinct from old.engine_version
        or new.detail_snapshot is distinct from old.detail_snapshot
        or new.request_payload_hash is distinct from old.request_payload_hash
        or new.result_payload_hash is distinct from old.result_payload_hash
        or new.authorization_mode is distinct from old.authorization_mode
        or new.excluded_measurement_codes is distinct from old.excluded_measurement_codes
        or new.reference_snapshot is distinct from old.reference_snapshot
        or new.target_snapshot is distinct from old.target_snapshot
        or new.authority_snapshot is distinct from old.authority_snapshot
        or new.policy_snapshot is distinct from old.policy_snapshot
        or new.authorization_snapshot is distinct from old.authorization_snapshot
        or new.input_snapshot is distinct from old.input_snapshot
        or new.result_evidence is distinct from old.result_evidence
        or new.completed_at is distinct from old.completed_at
    ) then
        raise exception 'Completed comparison core history is immutable';
    end if;
    return new;
end
$function$;

drop trigger if exists comparisons_protect_completed on fitmatch_vnext.comparisons;
create trigger comparisons_protect_completed
before update on fitmatch_vnext.comparisons
for each row execute function fitmatch_vnext.protect_completed_comparison();

create or replace function fitmatch_vnext.begin_comparison(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    caller_id uuid := auth.uid();
    client_id uuid;
    ref_id uuid;
    target_id uuid;
    target_variant uuid;
    authorization_size uuid;
    manual_explicit boolean;
    request_hash text;
    existing fitmatch_vnext.comparisons%rowtype;
    ref fitmatch_vnext.closet_items%rowtype;
    target fitmatch_vnext.products%rowtype;
    authz jsonb;
    candidate_ids uuid[];
    comparison_id uuid;
    taxonomy_checksum text;
    mapping_checksum text;
    reference_data jsonb;
    target_data jsonb;
    policy_data jsonb;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    if p_request is null or jsonb_typeof(p_request) <> 'object' then
        raise exception 'Request must be a JSON object';
    end if;
    client_id := (p_request ->> 'client_comparison_id')::uuid;
    ref_id := (p_request ->> 'reference_closet_item_id')::uuid;
    target_id := (p_request ->> 'target_product_id')::uuid;
    target_variant := (p_request ->> 'target_variant_id')::uuid;
    authorization_size := (p_request ->> 'authorization_product_size_id')::uuid;
    manual_explicit := coalesce((p_request ->> 'manual_explicit')::boolean, false);
    if client_id is null or ref_id is null or target_id is null
       or target_variant is null or authorization_size is null then
        raise exception 'Comparison identity, reference, target, variant, and authorization size are required';
    end if;
    select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
    into candidate_ids
    from jsonb_array_elements_text(coalesce(p_request -> 'candidate_product_size_ids','[]'::jsonb))
         with ordinality x(value, ordinal);
    if cardinality(candidate_ids) = 0 or not authorization_size = any(candidate_ids) then
        raise exception 'Candidate sizes must include authorization_product_size_id';
    end if;
    request_hash := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
    perform pg_advisory_xact_lock(hashtextextended(caller_id::text || ':' || client_id::text, 0));

    select * into existing from fitmatch_vnext.comparisons
    where user_id = caller_id and client_comparison_id = client_id for update;
    if found then
        if existing.request_payload_hash is distinct from request_hash then
            raise exception 'Idempotency conflict for client_comparison_id';
        end if;
        return jsonb_build_object('comparison_id',existing.id,'created',false,
            'idempotent',true,'result_status',existing.result_status);
    end if;

    select * into ref from fitmatch_vnext.closet_items
    where id = ref_id and user_id = caller_id and deleted_at is null;
    if not found then raise exception 'Reference is missing or not owned'; end if;
    select * into target from fitmatch_vnext.products where id = target_id;
    if not found then raise exception 'Target product not found'; end if;
    if not exists (select 1 from fitmatch_vnext.product_variants
                   where id=target_variant and product_id=target_id) then
        raise exception 'Target variant hierarchy mismatch';
    end if;
    if exists (select 1 from unnest(candidate_ids) sid where not exists (
        select 1 from fitmatch_vnext.product_sizes ps
        where ps.id=sid and ps.variant_id=target_variant)) then
        raise exception 'Candidate size hierarchy mismatch';
    end if;

    authz := fitmatch_vnext.authorize_comparison(
        ref_id,target_id,authorization_size,manual_explicit);
    if not coalesce((authz ->> 'allowed')::boolean,false) then
        raise exception 'Comparison is not authorized: %', authz ->> 'reason';
    end if;

    select encode(extensions.digest(string_agg(concat_ws('|',gt.garment_type_code,
        gt.category_code,gt.comparison_policy_code,gt.uses_sleeve_length::text,
        gt.uses_lower_length::text,gt.uses_body_length::text,gt.is_active::text),
        E'\n' order by gt.garment_type_code), 'sha256'),'hex') into taxonomy_checksum
    from fitmatch_vnext.garment_types gt;
    select encode(extensions.digest(coalesce(string_agg(m.mapping_checksum,E'\n' order by m.id),''),
        'sha256'),'hex') into mapping_checksum
    from fitmatch_vnext.classification_signal_mappings m where m.is_active and m.is_verified;

    reference_data := jsonb_build_object(
        'closet_item_id',ref.id,'product_id',ref.product_id,
        'product_variant_id',ref.product_variant_id,'product_size_id',ref.product_size_id,
        'garment_type_code',ref.garment_type_code,'audience_code',ref.audience_code,
        'sleeve_length_code',ref.sleeve_length_code,'lower_length_code',ref.lower_length_code,
        'body_length_code',ref.body_length_code,
        'classification_fingerprint',ref.classification_fingerprint,
        'classification_resolver_version',ref.classification_resolver_version,
        'measurements',coalesce((select jsonb_agg(jsonb_build_object(
            'fitmatch_measurement_code',cm.fitmatch_measurement_code,'value',cm.value,
            'unit_code',cm.unit_code,'value_source',cm.value_source)
            order by cm.fitmatch_measurement_code)
            from fitmatch_vnext.closet_item_measurements cm where cm.closet_item_id=ref.id),'[]'::jsonb)
    );
    target_data := jsonb_build_object(
        'product_id',target.id,'variant_id',target_variant,
        'candidate_product_size_ids',to_jsonb(candidate_ids),
        'classification_status',target.classification_status,
        'garment_type_code',target.garment_type_code,'audience_code',target.audience_code,
        'sleeve_length_code',target.sleeve_length_code,
        'lower_length_code',target.lower_length_code,'body_length_code',target.body_length_code,
        'classification_fingerprint',target.input_fingerprint,
        'resolver_version',target.resolver_version,
        'candidate_measurements',(select jsonb_agg(jsonb_build_object(
            'product_size_id',sid,'canonical',fitmatch_vnext.canonical_measurements_for_size(sid))
            order by sid) from unnest(candidate_ids) sid)
    );
    select to_jsonb(cp) into policy_data from fitmatch_vnext.comparison_policies cp
    where cp.policy_code=authz->>'policy_code';

    insert into fitmatch_vnext.comparisons (
        user_id,client_comparison_id,reference_closet_item_id,target_product_id,target_variant_id,
        comparison_policy_code_snapshot,comparison_mode,reference_source_code_snapshot,
        target_source_code_snapshot,reference_item_name_snapshot,target_product_name_snapshot,
        target_image_url_snapshot,reference_garment_type_snapshot,target_garment_type_snapshot,
        reference_audience_snapshot,target_audience_snapshot,reference_sleeve_length_snapshot,
        target_sleeve_length_snapshot,reference_lower_length_snapshot,target_lower_length_snapshot,
        reference_body_length_snapshot,target_body_length_snapshot,result_status,engine_version,
        snapshot_schema_version,detail_snapshot,request_payload_hash,authorization_mode,
        excluded_measurement_codes,reference_snapshot,target_snapshot,authority_snapshot,
        policy_snapshot,authorization_snapshot,input_snapshot
    ) values (
        caller_id,client_id,ref.id,target.id,target_variant,authz->>'policy_code','CANONICAL',
        ref.source_code_snapshot,target.source_code,ref.item_name,target.product_name,target.image_url,
        ref.garment_type_code,target.garment_type_code,ref.audience_code,target.audience_code,
        ref.sleeve_length_code,target.sleeve_length_code,ref.lower_length_code,target.lower_length_code,
        ref.body_length_code,target.body_length_code,'PENDING','pending',2,
        jsonb_build_object('phase','BEGIN'),request_hash,authz->>'mode',
        array(select jsonb_array_elements_text(authz->'excluded_measurement_codes')),
        reference_data,target_data,jsonb_build_object(
            'classification_resolver_version',target.resolver_version,
            'classification_fingerprint',target.input_fingerprint,
            'classification_mapping_id',target.classification_mapping_id,
            'mapping_checksum',mapping_checksum,'taxonomy_checksum',taxonomy_checksum),
        policy_data,authz,p_request
    ) returning id into comparison_id;
    return jsonb_build_object('comparison_id',comparison_id,'created',true,
        'idempotent',false,'result_status','PENDING','authorization',authz);
end
$function$;

create or replace function fitmatch_vnext.complete_comparison(
    p_comparison_id uuid,
    p_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare caller_id uuid:=auth.uid(); row_value fitmatch_vnext.comparisons%rowtype;
    result_hash text; recommended_id uuid; recommended_label text;
begin
    if caller_id is null then raise exception 'Authentication required'; end if;
    if p_result is null or jsonb_typeof(p_result)<>'object' then
        raise exception 'Result must be a JSON object'; end if;
    result_hash:=encode(extensions.digest(p_result::text,'sha256'),'hex');
    select * into row_value from fitmatch_vnext.comparisons
    where id=p_comparison_id and user_id=caller_id for update;
    if not found then raise exception 'Comparison not found or not owned'; end if;
    if row_value.result_status='COMPLETED' then
        if row_value.result_payload_hash is distinct from result_hash then
            raise exception 'Completion idempotency conflict'; end if;
        return jsonb_build_object('comparison_id',row_value.id,'completed',true,'idempotent',true);
    end if;
    if row_value.result_status<>'PENDING' then raise exception 'Comparison is not pending'; end if;
    recommended_id:=(p_result->>'recommended_product_size_id')::uuid;
    if recommended_id is null or not exists (
        select 1 from jsonb_array_elements_text(row_value.target_snapshot->'candidate_product_size_ids') x(id)
        where x.id::uuid=recommended_id) then
        raise exception 'Recommended size is not a begin-snapshot candidate'; end if;
    select ps.size_label into recommended_label from fitmatch_vnext.product_sizes ps
    join fitmatch_vnext.product_variants pv on pv.id=ps.variant_id
    where ps.id=recommended_id and pv.product_id=row_value.target_product_id;
    if recommended_label is null then raise exception 'Recommended size hierarchy mismatch'; end if;
    if jsonb_typeof(coalesce(p_result->'candidate_size_ranking','null'::jsonb))<>'array'
       or jsonb_array_length(p_result->'candidate_size_ranking')=0
       or jsonb_typeof(coalesce(p_result->'metric_evidence','null'::jsonb))<>'array'
       or jsonb_array_length(p_result->'metric_evidence')=0 then
        raise exception 'Candidate ranking and metric evidence are required'; end if;

    update fitmatch_vnext.comparisons set
        recommended_product_size_id=recommended_id,recommended_size_label=recommended_label,
        fit_score=(p_result->>'score')::numeric,
        reliability_level=(p_result->>'reliability')::smallint,
        coverage_ratio=(p_result->>'coverage')::numeric,
        result_status='COMPLETED',engine_version=p_result->>'engine_version',
        detail_snapshot=jsonb_build_object('phase','COMPLETED','result',p_result),
        result_evidence=p_result,result_payload_hash=result_hash,completed_at=now()
    where id=row_value.id;
    return jsonb_build_object('comparison_id',row_value.id,'completed',true,
        'idempotent',false,'recommended_product_size_id',recommended_id,
        'recommended_size_label',recommended_label);
end
$function$;

create or replace function fitmatch_vnext.comparison_history()
returns jsonb language plpgsql security definer set search_path='' as $function$
declare caller_id uuid:=auth.uid();
begin
 if caller_id is null then raise exception 'Authentication required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc,c.id)
   from fitmatch_vnext.comparisons c where c.user_id=caller_id and c.deleted_at is null),'[]'::jsonb);
end $function$;

revoke all on function fitmatch_vnext.begin_comparison(jsonb) from public,anon;
revoke all on function fitmatch_vnext.complete_comparison(uuid,jsonb) from public,anon;
revoke all on function fitmatch_vnext.comparison_history() from public,anon;
grant execute on function fitmatch_vnext.begin_comparison(jsonb),
 fitmatch_vnext.complete_comparison(uuid,jsonb),fitmatch_vnext.comparison_history()
 to authenticated,service_role;
