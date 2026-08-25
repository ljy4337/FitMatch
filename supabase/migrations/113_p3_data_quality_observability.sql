begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:p3-data-quality-observability-v1'));

-- Keep subject-bound issues from migration 105, while allowing a single
-- source + issue_code + raw signature row to aggregate the same operational
-- problem across products. This deliberately extends the existing ledger
-- instead of creating a duplicate unmapped-observation table.
alter table fitmatch_catalog.data_quality_issues
  add column if not exists source_code text,
  add column if not exists raw_signature text,
  add column if not exists issue_fingerprint text;

alter table fitmatch_catalog.data_quality_issues
  drop constraint if exists data_quality_issues_one_subject_check;

alter table fitmatch_catalog.data_quality_issues
  add constraint data_quality_issues_subject_or_signature_check check (
    (
      issue_fingerprint is null
      and num_nonnulls(
        observation_id, product_id, classification_history_id, product_measurement_id
      ) = 1
    )
    or (
      issue_fingerprint is not null
      and num_nonnulls(
        observation_id, product_id, classification_history_id, product_measurement_id
      ) <= 1
      and btrim(coalesce(source_code, '')) <> ''
      and btrim(coalesce(raw_signature, '')) <> ''
    )
  ),
  add constraint data_quality_issues_source_code_check check (
    source_code is null or btrim(source_code) <> ''
  ),
  add constraint data_quality_issues_raw_signature_check check (
    raw_signature is null or btrim(raw_signature) <> ''
  ),
  add constraint data_quality_issues_fingerprint_check check (
    issue_fingerprint is null or issue_fingerprint ~ '^[0-9a-f]{32}$'
  );

create unique index if not exists data_quality_issues_signature_unique_idx
  on fitmatch_catalog.data_quality_issues (
    source_code, issue_code, issue_fingerprint
  )
  where issue_fingerprint is not null;

create index if not exists data_quality_issues_signature_reporting_idx
  on fitmatch_catalog.data_quality_issues (
    source_code, issue_code, occurrence_count desc, last_seen_at desc
  )
  where issue_fingerprint is not null
    and status in ('open', 'acknowledged');

comment on column fitmatch_catalog.data_quality_issues.issue_fingerprint is
  'MD5 of normalized source + issue code + raw signature for cross-product aggregation.';
comment on column fitmatch_catalog.data_quality_issues.raw_signature is
  'Normalized raw category, measurement, or conflict signature; never a canonical mapping.';

create or replace function fitmatch_catalog.runtime_record_signature_issue(
  p_source_code text,
  p_issue_code text,
  p_raw_signature text,
  p_severity text,
  p_evidence jsonb default '{}'
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_source_code text := lower(btrim(coalesce(p_source_code, '')));
  v_issue_code text := upper(btrim(coalesce(p_issue_code, '')));
  v_raw_signature text := lower(regexp_replace(
    btrim(coalesce(p_raw_signature, '')), E'\\s+', ' ', 'g'
  ));
  v_fingerprint text;
  v_issue_id uuid;
begin
  if v_source_code = ''
     or v_issue_code = ''
     or v_raw_signature = ''
     or p_severity not in ('low', 'medium', 'high', 'critical')
     or jsonb_typeof(coalesce(p_evidence, '{}'::jsonb)) <> 'object' then
    raise exception using
      errcode = '22023', message = 'invalid_signature_data_quality_issue';
  end if;

  v_fingerprint := md5(
    v_source_code || E'\n' || v_issue_code || E'\n' || v_raw_signature
  );

  insert into fitmatch_catalog.data_quality_issues (
    source_code, issue_code, raw_signature, issue_fingerprint,
    severity, evidence
  ) values (
    v_source_code, v_issue_code, v_raw_signature, v_fingerprint,
    p_severity, coalesce(p_evidence, '{}'::jsonb)
  )
  on conflict (source_code, issue_code, issue_fingerprint)
    where issue_fingerprint is not null
  do update set
    severity = excluded.severity,
    status = 'open',
    occurrence_count = fitmatch_catalog.data_quality_issues.occurrence_count + 1,
    evidence = fitmatch_catalog.data_quality_issues.evidence
      || case
        when fitmatch_catalog.data_quality_issues.status = 'resolved'
          and fitmatch_catalog.data_quality_issues.resolution <> '{}'::jsonb
        then jsonb_build_object(
          'previous_resolution', fitmatch_catalog.data_quality_issues.resolution
        )
        else '{}'::jsonb
      end
      || excluded.evidence,
    resolution = '{}'::jsonb,
    last_seen_at = now(),
    resolved_at = null,
    updated_at = now()
  returning id into v_issue_id;

  return v_issue_id;
end $$;

create or replace function fitmatch_catalog.runtime_resolve_signature_issue(
  p_source_code text,
  p_issue_code text,
  p_raw_signature text,
  p_resolution jsonb default '{}'
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_source_code text := lower(btrim(coalesce(p_source_code, '')));
  v_issue_code text := upper(btrim(coalesce(p_issue_code, '')));
  v_raw_signature text := lower(regexp_replace(
    btrim(coalesce(p_raw_signature, '')), E'\\s+', ' ', 'g'
  ));
  v_fingerprint text;
begin
  if v_source_code = ''
     or v_issue_code = ''
     or v_raw_signature = ''
     or jsonb_typeof(coalesce(p_resolution, '{}'::jsonb)) <> 'object' then
    raise exception using
      errcode = '22023', message = 'invalid_signature_data_quality_resolution';
  end if;

  v_fingerprint := md5(
    v_source_code || E'\n' || v_issue_code || E'\n' || v_raw_signature
  );

  update fitmatch_catalog.data_quality_issues
  set status = 'resolved',
      resolution = resolution || coalesce(p_resolution, '{}'::jsonb),
      resolved_at = now(),
      updated_at = now()
  where source_code = v_source_code
    and issue_code = v_issue_code
    and issue_fingerprint = v_fingerprint
    and status in ('open', 'acknowledged');
end $$;

revoke all on function fitmatch_catalog.runtime_record_signature_issue(
  text, text, text, text, jsonb
) from public, anon, authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_signature_issue(
  text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_catalog.runtime_record_signature_issue(
  text, text, text, text, jsonb
) to service_role;
grant execute on function fitmatch_catalog.runtime_resolve_signature_issue(
  text, text, text, jsonb
) to service_role;

create or replace function public.fitmatch_process_product_observation(
  p_observation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_observation fitmatch_catalog.product_observations%rowtype;
  v_promotion jsonb;
  v_ingest jsonb;
  v_summary jsonb;
  v_source_mapping jsonb;
  v_category_signature text;
  v_category_scope text;
  v_conflict_signature text;
  v_measurement record;
  v_issue_count integer := 0;
begin
  select * into v_observation
  from fitmatch_catalog.product_observations
  where id = p_observation_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'observation_not_found';
  end if;

  if v_observation.processing_status = 'promoted' then
    return jsonb_build_object(
      'observation_id', v_observation.id,
      'status', v_observation.processing_status,
      'product_id', v_observation.resolved_product_id,
      'summary', v_observation.normalization_summary,
      'idempotent', true
    );
  end if;

  update fitmatch_catalog.product_observations
  set processing_status = 'processing', error_code = null
  where id = v_observation.id;

  begin
    v_promotion := fitmatch_catalog.runtime_resolve_and_promote_product(
      v_observation.raw_payload
    );
    v_ingest := fitmatch_catalog.runtime_ingest_product_payload(
      v_observation.raw_payload
    );
    v_source_mapping := fitmatch_catalog.runtime_resolve_source_mapping(
      v_observation.raw_payload
    );
    v_category_scope := nullif(
      v_promotion->'classification'->>'category_code',
      ''
    );

    select concat_ws(
      '|',
      nullif(fitmatch_catalog.runtime_normalized_category_path(
        v_observation.raw_payload->>'source_category_path'
      ), ''),
      nullif((
        select string_agg(value, '>' order by ordinality)
        from jsonb_array_elements_text(
          case
            when jsonb_typeof(v_observation.raw_payload->'source_category_codes') = 'array'
              then v_observation.raw_payload->'source_category_codes'
            else '[]'::jsonb
          end
        ) with ordinality
      ), '')
    ) into v_category_signature;

    if btrim(coalesce(v_category_signature, '')) <> '' then
      if not coalesce((v_source_mapping->>'found')::boolean, false) then
        perform fitmatch_catalog.runtime_record_signature_issue(
          v_observation.source,
          'UNKNOWN_SOURCE_CATEGORY',
          v_category_signature,
          'medium',
          jsonb_build_object(
            'latest_observation_id', v_observation.id,
            'latest_product_id', v_promotion->>'product_id',
            'external_product_id', v_observation.external_product_id,
            'source_category_path', v_observation.raw_payload->>'source_category_path',
            'source_category_codes', coalesce(
              v_observation.raw_payload->'source_category_codes', '[]'::jsonb
            )
          )
        );
        v_issue_count := v_issue_count + 1;
      else
        perform fitmatch_catalog.runtime_resolve_signature_issue(
          v_observation.source,
          'UNKNOWN_SOURCE_CATEGORY',
          v_category_signature,
          jsonb_build_object(
            'resolved_by', 'source_category_mapping',
            'release_id', v_source_mapping->>'release_id'
          )
        );
      end if;
    end if;

    for v_measurement in
      with normalized as (
        select distinct
          concat_ws(
            '|',
            nullif(lower(btrim(m.raw_code)), ''),
            lower(regexp_replace(btrim(m.raw_label), E'\\s+', ' ', 'g')),
            nullif(lower(btrim(m.raw_representation)), '')
          ) as raw_signature,
          m.raw_code,
          m.raw_label,
          m.raw_unit,
          m.raw_representation,
          fitmatch_catalog.runtime_normalize_measurement_v2(
            v_observation.source,
            null,
            m.raw_code,
            m.raw_label,
            m.raw_value,
            m.raw_unit,
            v_category_scope
          ) as normalization
        from fitmatch_catalog.product_observation_measurements m
        where m.observation_id = v_observation.id
      )
      select * from normalized
    loop
      if coalesce((v_measurement.normalization->>'mapped')::boolean, false) then
        perform fitmatch_catalog.runtime_resolve_signature_issue(
          v_observation.source,
          'UNKNOWN_MEASUREMENT_ALIAS',
          v_measurement.raw_signature,
          jsonb_build_object(
            'resolved_by', 'source_measurement_alias',
            'policy_version', v_measurement.normalization->>'policy_version'
          )
        );
      elsif v_measurement.normalization->>'reason' = 'measurement_alias_not_found' then
        perform fitmatch_catalog.runtime_record_signature_issue(
          v_observation.source,
          'UNKNOWN_MEASUREMENT_ALIAS',
          v_measurement.raw_signature,
          'medium',
          jsonb_build_object(
            'latest_observation_id', v_observation.id,
            'latest_product_id', v_promotion->>'product_id',
            'external_product_id', v_observation.external_product_id,
            'raw_code', v_measurement.raw_code,
            'raw_label', v_measurement.raw_label,
            'raw_unit', v_measurement.raw_unit,
            'raw_representation', v_measurement.raw_representation,
            'category_scope', v_category_scope,
            'normalization_reason', v_measurement.normalization->>'reason'
          )
        );
        v_issue_count := v_issue_count + 1;
      else
        perform fitmatch_catalog.runtime_resolve_signature_issue(
          v_observation.source,
          'UNKNOWN_MEASUREMENT_ALIAS',
          v_measurement.raw_signature,
          jsonb_build_object(
            'resolved_by', 'alias_resolution_not_applicable',
            'normalization_reason', v_measurement.normalization->>'reason'
          )
        );
      end if;

      if v_measurement.normalization->>'reason' in (
        'unsupported_unit', 'comparison_basis_missing', 'measurement_kind_missing'
      ) then
        perform fitmatch_catalog.runtime_record_signature_issue(
          v_observation.source,
          'UNSUPPORTED_MEASUREMENT_BASIS',
          v_measurement.raw_signature,
          'high',
          jsonb_build_object(
            'latest_observation_id', v_observation.id,
            'latest_product_id', v_promotion->>'product_id',
            'external_product_id', v_observation.external_product_id,
            'raw_code', v_measurement.raw_code,
            'raw_label', v_measurement.raw_label,
            'raw_unit', v_measurement.raw_unit,
            'raw_representation', v_measurement.raw_representation,
            'category_scope', v_category_scope,
            'normalization_reason', v_measurement.normalization->>'reason'
          )
        );
        v_issue_count := v_issue_count + 1;
      else
        perform fitmatch_catalog.runtime_resolve_signature_issue(
          v_observation.source,
          'UNSUPPORTED_MEASUREMENT_BASIS',
          v_measurement.raw_signature,
          jsonb_build_object(
            'resolved_by', 'verified_measurement_basis',
            'policy_version', v_measurement.normalization->>'policy_version'
          )
        );
      end if;
    end loop;

    if coalesce(
      (v_observation.raw_payload->'raw_payload'->>'local_classification_conflict')::boolean,
      false
    ) then
      v_conflict_signature := concat_ws(
        '|',
        nullif(v_observation.raw_payload->'raw_payload'
          ->>'local_classification_conflict_dimensions', ''),
        nullif(v_observation.raw_payload->'raw_payload'
          ->>'local_classification_conflict_evidence', '')
      );
      if btrim(coalesce(v_conflict_signature, '')) <> '' then
        perform fitmatch_catalog.runtime_record_signature_issue(
          v_observation.source,
          'CLASSIFICATION_CONFLICT',
          v_conflict_signature,
          'high',
          jsonb_build_object(
            'latest_observation_id', v_observation.id,
            'latest_product_id', v_promotion->>'product_id',
            'latest_classification_history_id', v_promotion->>'classification_id',
            'external_product_id', v_observation.external_product_id,
            'source_category_path', v_observation.raw_payload->>'source_category_path',
            'dimensions', v_observation.raw_payload->'raw_payload'
              ->>'local_classification_conflict_dimensions',
            'conflict_evidence', v_observation.raw_payload->'raw_payload'
              ->>'local_classification_conflict_evidence',
            'policy_version', v_observation.raw_payload->'raw_payload'
              ->>'local_classification_safety_policy_version'
          )
        );
        v_issue_count := v_issue_count + 1;
      end if;
    end if;

    v_summary := v_promotion || jsonb_build_object(
      'variants_processed', coalesce((v_ingest->>'variants_processed')::integer, 0),
      'sizes_processed', coalesce((v_ingest->>'sizes_processed')::integer, 0),
      'measurements_processed', coalesce((v_ingest->>'measurements_processed')::integer, 0),
      'data_quality_issue_count', v_issue_count
    );

    update fitmatch_catalog.product_observations
    set processing_status = 'promoted',
        resolved_product_id = (v_promotion->>'product_id')::uuid,
        normalization_summary = v_summary,
        error_code = null,
        processed_at = now()
    where id = v_observation.id;

    perform fitmatch_catalog.runtime_resolve_observation_issue(
      v_observation.id,
      'observation_processing_failed',
      jsonb_build_object('resolved_by', 'successful_reprocessing')
    );

    return jsonb_build_object(
      'observation_id', v_observation.id,
      'status', 'promoted',
      'product_id', (v_promotion->>'product_id')::uuid,
      'summary', v_summary,
      'idempotent', false
    );
  exception when others then
    update fitmatch_catalog.product_observations
    set processing_status = 'rejected',
        error_code = left(sqlstate || ':' || sqlerrm, 500),
        processed_at = now()
    where id = v_observation.id;

    perform fitmatch_catalog.runtime_record_observation_issue(
      v_observation.id,
      'observation_processing_failed',
      'high',
      jsonb_build_object(
        'sqlstate', sqlstate,
        'error', left(sqlerrm, 400),
        'source', v_observation.source,
        'external_product_id', v_observation.external_product_id
      )
    );

    return jsonb_build_object(
      'observation_id', v_observation.id,
      'status', 'rejected',
      'error_code', left(sqlstate || ':' || sqlerrm, 500),
      'idempotent', false
    );
  end;
end $$;

revoke all on function public.fitmatch_process_product_observation(uuid)
  from public, anon, authenticated;
grant execute on function public.fitmatch_process_product_observation(uuid)
  to service_role;

do $$
declare
  v_rls_enabled boolean;
  v_signature_index boolean;
  v_anon_record_execute boolean;
  v_authenticated_record_execute boolean;
begin
  select relrowsecurity into v_rls_enabled
  from pg_class
  where oid = 'fitmatch_catalog.data_quality_issues'::regclass;

  select exists (
    select 1 from pg_indexes
    where schemaname = 'fitmatch_catalog'
      and indexname = 'data_quality_issues_signature_unique_idx'
  ) into v_signature_index;

  select has_function_privilege(
    'anon',
    'fitmatch_catalog.runtime_record_signature_issue(text,text,text,text,jsonb)',
    'EXECUTE'
  ) into v_anon_record_execute;
  select has_function_privilege(
    'authenticated',
    'fitmatch_catalog.runtime_record_signature_issue(text,text,text,text,jsonb)',
    'EXECUTE'
  ) into v_authenticated_record_execute;

  if not coalesce(v_rls_enabled, false)
     or not coalesce(v_signature_index, false)
     or coalesce(v_anon_record_execute, true)
     or coalesce(v_authenticated_record_execute, true) then
    raise exception 'P3 data-quality observability validation failed';
  end if;
end $$;

commit;
