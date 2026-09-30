begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:comparison-quality-and-data-issue-v1'));

-- A fit score answers "how similar?". Coverage, data quality, and confidence
-- answer different questions and must remain independently auditable.
alter table public.comparison_results
  add column if not exists coverage_ratio numeric(5,4),
  add column if not exists data_quality_score numeric(5,4),
  add column if not exists confidence_score numeric(5,4),
  add column if not exists used_measurement_count integer not null default 0,
  add column if not exists excluded_measurement_count integer not null default 0,
  add column if not exists quality_metrics_version text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'comparison_results_coverage_ratio_check'
      and conrelid = 'public.comparison_results'::regclass
  ) then
    alter table public.comparison_results
      add constraint comparison_results_coverage_ratio_check
      check (coverage_ratio is null or (coverage_ratio >= 0 and coverage_ratio <= 1));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'comparison_results_data_quality_score_check'
      and conrelid = 'public.comparison_results'::regclass
  ) then
    alter table public.comparison_results
      add constraint comparison_results_data_quality_score_check
      check (data_quality_score is null or (
        data_quality_score >= 0 and data_quality_score <= 1
      ));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'comparison_results_confidence_score_check'
      and conrelid = 'public.comparison_results'::regclass
  ) then
    alter table public.comparison_results
      add constraint comparison_results_confidence_score_check
      check (confidence_score is null or (
        confidence_score >= 0 and confidence_score <= 1
      ));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'comparison_results_measurement_counts_check'
      and conrelid = 'public.comparison_results'::regclass
  ) then
    alter table public.comparison_results
      add constraint comparison_results_measurement_counts_check
      check (used_measurement_count >= 0 and excluded_measurement_count >= 0);
  end if;
end $$;

comment on column public.comparison_results.similarity_score is
  'Fit similarity score from 0 to 100; independent from evidence quality.';
comment on column public.comparison_results.coverage_ratio is
  'Weighted share of comparison-profile measurements actually compared, from 0 to 1.';
comment on column public.comparison_results.data_quality_score is
  'Semantic measurement-definition quality, from 0 to 1.';
comment on column public.comparison_results.confidence_score is
  'Overall result confidence derived from coverage, data quality, and evidence breadth.';
comment on column public.comparison_results.quality_metrics_version is
  'Version of the algorithm that produced coverage/data-quality/confidence metrics.';

-- Backend-only issue ledger. It records observed facts; it is not a user-facing
-- error table and it never turns an uncertain product into a comparable one.
create table if not exists fitmatch_catalog.data_quality_issues (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid
    references fitmatch_catalog.product_observations(id) on delete cascade,
  product_id uuid
    references fitmatch_catalog.products(id) on delete cascade,
  classification_history_id uuid
    references fitmatch_catalog.product_classification_history(id) on delete cascade,
  product_measurement_id uuid
    references fitmatch_catalog.product_measurements(id) on delete cascade,
  issue_code text not null,
  severity text not null,
  status text not null default 'open',
  occurrence_count integer not null default 1,
  evidence jsonb not null default '{}',
  resolution jsonb not null default '{}',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint data_quality_issues_one_subject_check check (
    num_nonnulls(
      observation_id, product_id, classification_history_id, product_measurement_id
    ) = 1
  ),
  constraint data_quality_issues_code_check check (btrim(issue_code) <> ''),
  constraint data_quality_issues_severity_check check (
    severity in ('low','medium','high','critical')
  ),
  constraint data_quality_issues_status_check check (
    status in ('open','acknowledged','resolved','ignored')
  ),
  constraint data_quality_issues_occurrence_count_check check (occurrence_count > 0),
  constraint data_quality_issues_evidence_check check (jsonb_typeof(evidence) = 'object'),
  constraint data_quality_issues_resolution_check check (jsonb_typeof(resolution) = 'object'),
  constraint data_quality_issues_resolved_state_check check (
    (status = 'resolved' and resolved_at is not null)
    or (status <> 'resolved')
  )
);

create unique index if not exists data_quality_issues_observation_unique_idx
  on fitmatch_catalog.data_quality_issues (observation_id, issue_code)
  where observation_id is not null;
create unique index if not exists data_quality_issues_product_unique_idx
  on fitmatch_catalog.data_quality_issues (product_id, issue_code)
  where product_id is not null;
create unique index if not exists data_quality_issues_classification_unique_idx
  on fitmatch_catalog.data_quality_issues (classification_history_id, issue_code)
  where classification_history_id is not null;
create unique index if not exists data_quality_issues_measurement_unique_idx
  on fitmatch_catalog.data_quality_issues (product_measurement_id, issue_code)
  where product_measurement_id is not null;
create index if not exists data_quality_issues_active_idx
  on fitmatch_catalog.data_quality_issues (severity, last_seen_at desc)
  where status in ('open','acknowledged');

alter table fitmatch_catalog.data_quality_issues enable row level security;
revoke all on fitmatch_catalog.data_quality_issues from public, anon, authenticated;
grant select, insert, update, delete on fitmatch_catalog.data_quality_issues to service_role;

comment on table fitmatch_catalog.data_quality_issues is
  'Backend-only deduplicated quality issue ledger for observations and canonical runtime data.';

create or replace function fitmatch_catalog.runtime_record_observation_issue(
  p_observation_id uuid,
  p_issue_code text,
  p_severity text,
  p_evidence jsonb default '{}'
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_issue_id uuid;
begin
  if p_observation_id is null
     or btrim(coalesce(p_issue_code, '')) = ''
     or p_severity not in ('low','medium','high','critical')
     or jsonb_typeof(coalesce(p_evidence, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_data_quality_issue';
  end if;

  insert into fitmatch_catalog.data_quality_issues (
    observation_id, issue_code, severity, evidence
  ) values (
    p_observation_id, btrim(p_issue_code), p_severity, coalesce(p_evidence, '{}'::jsonb)
  )
  on conflict (observation_id, issue_code) where observation_id is not null
  do update set
    severity = excluded.severity,
    status = 'open',
    occurrence_count = fitmatch_catalog.data_quality_issues.occurrence_count + 1,
    evidence = fitmatch_catalog.data_quality_issues.evidence || excluded.evidence,
    last_seen_at = now(),
    resolved_at = null,
    updated_at = now()
  returning id into v_issue_id;

  return v_issue_id;
end $$;

create or replace function fitmatch_catalog.runtime_resolve_observation_issue(
  p_observation_id uuid,
  p_issue_code text,
  p_resolution jsonb default '{}'
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_observation_id is null
     or btrim(coalesce(p_issue_code, '')) = ''
     or jsonb_typeof(coalesce(p_resolution, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_data_quality_resolution';
  end if;

  update fitmatch_catalog.data_quality_issues
  set status = 'resolved',
      resolution = resolution || coalesce(p_resolution, '{}'::jsonb),
      resolved_at = now(),
      updated_at = now()
  where observation_id = p_observation_id
    and issue_code = btrim(p_issue_code)
    and status in ('open','acknowledged');
end $$;

revoke all on function fitmatch_catalog.runtime_record_observation_issue(uuid,text,text,jsonb)
  from public, anon, authenticated;
revoke all on function fitmatch_catalog.runtime_resolve_observation_issue(uuid,text,jsonb)
  from public, anon, authenticated;
grant execute on function fitmatch_catalog.runtime_record_observation_issue(uuid,text,text,jsonb)
  to service_role;
grant execute on function fitmatch_catalog.runtime_resolve_observation_issue(uuid,text,jsonb)
  to service_role;

create or replace function public.fitmatch_complete_comparison(
  p_run_id uuid,
  p_result_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_run public.comparison_runs%rowtype;
  v_result jsonb;
  v_measurement jsonb;
  v_measurements jsonb;
  v_result_id uuid;
  v_target_size_id uuid;
  v_used_measurement_count integer;
  v_excluded_measurement_count integer;
  v_result_count integer := 0;
begin
  if v_user_id is null then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  if jsonb_typeof(p_result_payload)<>'object'
     or jsonb_typeof(p_result_payload->'results')<>'array'
     or jsonb_array_length(p_result_payload->'results')=0 then
    raise exception using errcode='22023', message='invalid_result_payload';
  end if;
  select * into v_run
  from public.comparison_runs
  where id=p_run_id and user_id=v_user_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='comparison_run_not_found';
  end if;
  if v_run.status='blocked' then
    raise exception using errcode='22023', message='blocked_run_cannot_complete';
  end if;

  for v_result in select value from jsonb_array_elements(p_result_payload->'results')
  loop
    v_target_size_id := nullif(v_result->>'target_size_id','')::uuid;
    if v_target_size_id is null or not exists (
      select 1
      from fitmatch_catalog.product_sizes s
      join fitmatch_catalog.product_variants v on v.id=s.variant_id
      where s.id=v_target_size_id and v.product_id=v_run.target_product_id
    ) then
      raise exception using errcode='22023', message='target_size_mismatch';
    end if;

    v_measurements := case when jsonb_typeof(v_result->'measurements')='array'
      then v_result->'measurements' else '[]'::jsonb end;
    select
      count(*) filter (where coalesce((value->>'included')::boolean,true)),
      count(*) filter (where not coalesce((value->>'included')::boolean,true))
    into v_used_measurement_count, v_excluded_measurement_count
    from jsonb_array_elements(v_measurements);

    insert into public.comparison_results (
      run_id,user_id,target_size_id,similarity_score,rank,confidence_code,
      coverage_ratio,data_quality_score,confidence_score,
      used_measurement_count,excluded_measurement_count,quality_metrics_version,
      is_recommended,is_comparable,exclusion_reason,result_snapshot
    ) values (
      p_run_id,v_user_id,v_target_size_id,
      nullif(v_result->>'similarity_score','')::numeric,
      nullif(v_result->>'rank','')::integer,
      nullif(v_result->>'confidence_code',''),
      nullif(v_result->>'coverage_ratio','')::numeric,
      nullif(v_result->>'data_quality_score','')::numeric,
      nullif(v_result->>'confidence_score','')::numeric,
      v_used_measurement_count,v_excluded_measurement_count,
      nullif(v_result->>'quality_metrics_version',''),
      coalesce((v_result->>'is_recommended')::boolean,false),
      coalesce((v_result->>'is_comparable')::boolean,false),
      nullif(v_result->>'exclusion_reason',''),
      case when jsonb_typeof(v_result->'snapshot')='object'
        then v_result->'snapshot' else '{}'::jsonb end
    )
    on conflict (run_id,target_size_id) do update set
      similarity_score=excluded.similarity_score,
      rank=excluded.rank,
      confidence_code=excluded.confidence_code,
      coverage_ratio=excluded.coverage_ratio,
      data_quality_score=excluded.data_quality_score,
      confidence_score=excluded.confidence_score,
      used_measurement_count=excluded.used_measurement_count,
      excluded_measurement_count=excluded.excluded_measurement_count,
      quality_metrics_version=excluded.quality_metrics_version,
      is_recommended=excluded.is_recommended,
      is_comparable=excluded.is_comparable,
      exclusion_reason=excluded.exclusion_reason,
      result_snapshot=excluded.result_snapshot
    returning id into v_result_id;

    delete from public.comparison_measurement_results
    where result_id=v_result_id and user_id=v_user_id;
    for v_measurement in select value from jsonb_array_elements(v_measurements)
    loop
      if nullif(v_measurement->>'measurement_code','') is null then
        raise exception using errcode='22023', message='measurement_code_required';
      end if;
      insert into public.comparison_measurement_results (
        result_id,user_id,measurement_code,reference_value,target_value,
        signed_difference,absolute_difference,weight,included,
        exclusion_reason,evidence
      ) values (
        v_result_id,v_user_id,v_measurement->>'measurement_code',
        nullif(v_measurement->>'reference_value','')::numeric,
        nullif(v_measurement->>'target_value','')::numeric,
        nullif(v_measurement->>'signed_difference','')::numeric,
        nullif(v_measurement->>'absolute_difference','')::numeric,
        nullif(v_measurement->>'weight','')::numeric,
        coalesce((v_measurement->>'included')::boolean,true),
        nullif(v_measurement->>'exclusion_reason',''),
        case when jsonb_typeof(v_measurement->'evidence')='object'
          then v_measurement->'evidence' else '{}'::jsonb end
      );
    end loop;
    v_result_count := v_result_count + 1;
  end loop;

  update public.comparison_runs
  set status='completed',
      result_summary=case when jsonb_typeof(p_result_payload->'summary')='object'
        then p_result_payload->'summary' else '{}'::jsonb end,
      completed_at=now()
  where id=p_run_id and user_id=v_user_id;

  insert into public.comparison_history (
    user_id,reference_item_id,product_snapshot,result_snapshot,comparison_run_id
  ) values (
    v_user_id,v_run.reference_item_id,
    jsonb_build_object('target_product_id',v_run.target_product_id),
    p_result_payload,p_run_id
  );

  return jsonb_build_object(
    'run_id',p_run_id,'status','completed','result_count',v_result_count
  );
end $$;

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
    v_summary := v_promotion || jsonb_build_object(
      'variants_processed', coalesce((v_ingest->>'variants_processed')::integer, 0),
      'sizes_processed', coalesce((v_ingest->>'sizes_processed')::integer, 0),
      'measurements_processed', coalesce((v_ingest->>'measurements_processed')::integer, 0)
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
      jsonb_build_object('resolved_by','successful_reprocessing')
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

revoke all on function public.fitmatch_complete_comparison(uuid,jsonb)
  from public, anon, service_role;
grant execute on function public.fitmatch_complete_comparison(uuid,jsonb)
  to authenticated;
revoke all on function public.fitmatch_process_product_observation(uuid)
  from public, anon, authenticated;
grant execute on function public.fitmatch_process_product_observation(uuid)
  to service_role;

commit;
;
