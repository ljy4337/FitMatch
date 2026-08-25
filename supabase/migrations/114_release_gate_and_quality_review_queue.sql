begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch:release-gate-quality-review-v1'));

-- A release may contain useful mappings while still lacking the evidence needed
-- to become the production runtime pointer. Keep that evidence on the existing
-- release instead of introducing another release/status table.
alter table fitmatch_catalog.releases
  add column if not exists validation_contract_version text,
  add column if not exists validation_report jsonb not null default '{}',
  add column if not exists release_gate_checked_at timestamptz,
  add column if not exists release_gate_result jsonb not null default '{}';

alter table fitmatch_catalog.releases
  drop constraint if exists releases_validation_report_object_check,
  drop constraint if exists releases_release_gate_result_object_check,
  add constraint releases_validation_report_object_check check (
    jsonb_typeof(validation_report) = 'object'
  ),
  add constraint releases_release_gate_result_object_check check (
    jsonb_typeof(release_gate_result) = 'object'
  );

-- A single production pointer is a hard runtime invariant. The partial unique
-- index also closes the race between two activation transactions.
create unique index if not exists releases_one_active_idx
  on fitmatch_catalog.releases ((true))
  where status = 'active';

comment on column fitmatch_catalog.releases.validation_report is
  'Evidence consumed by the production activation gate; never inferred from mapping count alone.';
comment on column fitmatch_catalog.releases.release_gate_result is
  'Last explicit activation-gate decision and blockers for operational audit.';

create or replace function fitmatch_catalog.runtime_release_gate_report(
  p_release_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_actual_mapping_count integer;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_release
  from fitmatch_catalog.releases
  where id = p_release_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'release_not_found';
  end if;

  select count(*) into v_actual_mapping_count
  from fitmatch_catalog.source_category_mappings
  where release_id = p_release_id;

  if v_release.validation_contract_version is distinct from 'fitmatch-release-gate-v1' then
    v_blockers := v_blockers || jsonb_build_array('validation_contract_missing_or_unsupported');
  end if;
  if btrim(coalesce(v_release.bundle_checksum, '')) = '' then
    v_blockers := v_blockers || jsonb_build_array('bundle_checksum_missing');
  end if;
  if btrim(coalesce(v_release.app_taxonomy_checksum, '')) = '' then
    v_blockers := v_blockers || jsonb_build_array('app_taxonomy_checksum_missing');
  end if;
  if v_release.validated_at is null then
    v_blockers := v_blockers || jsonb_build_array('release_not_validated');
  end if;
  if coalesce(v_release.expected_mapping_count, 0) <= 0
     or v_actual_mapping_count <> coalesce(v_release.expected_mapping_count, -1) then
    v_blockers := v_blockers || jsonb_build_array('mapping_count_mismatch');
  end if;
  if coalesce(v_release.expected_qa_count, 0) <= 0 then
    v_blockers := v_blockers || jsonb_build_array('qa_fixture_count_missing');
  end if;
  if not (v_release.validation_report @> '{"qa_full_validation_included":true}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('full_qa_not_included');
  end if;
  if not (v_release.validation_report @> '{"core_regression_passed":true}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('core_regression_not_passed');
  end if;
  if not (v_release.validation_report @> '{"current_behavior_parity_passed":true}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('current_behavior_parity_not_passed');
  end if;
  if not (v_release.validation_report @> '{"production_identity_verified":true}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('product_identity_not_verified');
  end if;
  if not (v_release.validation_report @> '{"label_sample_sufficiency_passed":true}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('independent_label_sample_insufficient');
  end if;
  if not (v_release.validation_report @> '{"unsafe_auto_accept_count":0}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('unsafe_auto_accept_present');
  end if;
  if not (v_release.validation_report @> '{"classification_conflict_leak_count":0}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('classification_conflict_leak_present');
  end if;
  if not (v_release.validation_report @> '{"measurement_alias_conflict_count":0}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('measurement_alias_conflict_present');
  end if;

  return jsonb_build_object(
    'contract_version', 'fitmatch-release-gate-v1',
    'release_id', v_release.id,
    'release_key', v_release.release_key,
    'eligible', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'expected_mapping_count', v_release.expected_mapping_count,
    'actual_mapping_count', v_actual_mapping_count,
    'expected_qa_count', v_release.expected_qa_count
  );
end $$;

create or replace function fitmatch_catalog.enforce_release_activation_gate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_report jsonb;
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.status = 'active' then
      return new;
    end if;
  end if;

  v_report := fitmatch_catalog.runtime_release_gate_report(new.id);
  if not coalesce((v_report->>'eligible')::boolean, false) then
    raise exception using
      errcode = '23514',
      message = 'release_activation_gate_failed',
      detail = v_report::text;
  end if;

  update fitmatch_catalog.releases
  set release_gate_checked_at = now(),
      release_gate_result = v_report
  where id = new.id;
  return new;
end $$;

drop trigger if exists releases_activation_gate_trigger
  on fitmatch_catalog.releases;
create trigger releases_activation_gate_trigger
after insert or update on fitmatch_catalog.releases
for each row execute function fitmatch_catalog.enforce_release_activation_gate();

create or replace function fitmatch_catalog.runtime_activate_validated_release(
  p_release_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_report jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('fitmatch:release-activation'));

  select status into v_status
  from fitmatch_catalog.releases
  where id = p_release_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'release_not_found';
  end if;
  if v_status <> 'validated' then
    raise exception using errcode = '22023', message = 'release_must_be_validated_before_activation';
  end if;

  v_report := fitmatch_catalog.runtime_release_gate_report(p_release_id);
  if not coalesce((v_report->>'eligible')::boolean, false) then
    raise exception using
      errcode = '23514',
      message = 'release_activation_gate_failed',
      detail = v_report::text;
  end if;

  update fitmatch_catalog.releases
  set release_gate_checked_at = now(), release_gate_result = v_report
  where id = p_release_id;
  update fitmatch_catalog.releases
  set status = 'retired'
  where status = 'active' and id <> p_release_id;
  update fitmatch_catalog.releases
  set status = 'active', activated_at = now()
  where id = p_release_id;

  return v_report || jsonb_build_object('activated', true, 'activated_at', now());
end $$;

revoke all on function fitmatch_catalog.runtime_release_gate_report(uuid)
  from public, anon, authenticated;
revoke all on function fitmatch_catalog.runtime_activate_validated_release(uuid)
  from public, anon, authenticated;
grant execute on function fitmatch_catalog.runtime_release_gate_report(uuid)
  to service_role;
grant execute on function fitmatch_catalog.runtime_activate_validated_release(uuid)
  to service_role;

-- Extend the existing deduplicated issue ledger into an operational review
-- queue. `product_intake_requests` remains the intake queue; this view is only
-- for classification/measurement/data-quality investigation.
alter table fitmatch_catalog.data_quality_issues
  add column if not exists triage_priority smallint,
  add column if not exists assigned_to uuid references auth.users(id) on delete set null,
  add column if not exists triage_note text,
  add column if not exists acknowledged_at timestamptz;

alter table fitmatch_catalog.data_quality_issues
  drop constraint if exists data_quality_issues_triage_priority_check,
  add constraint data_quality_issues_triage_priority_check check (
    triage_priority is null or (triage_priority between 0 and 100)
  );

create index if not exists data_quality_issues_review_queue_idx
  on fitmatch_catalog.data_quality_issues (
    status,
    triage_priority desc nulls last,
    last_seen_at desc
  )
  where status in ('open', 'acknowledged');

create or replace view fitmatch_catalog.data_quality_review_queue
with (security_invoker = true)
as
select
  issue.id,
  issue.source_code,
  issue.issue_code,
  issue.severity,
  issue.status,
  coalesce(
    issue.triage_priority,
    case issue.severity
      when 'critical' then 100
      when 'high' then 80
      when 'medium' then 50
      else 20
    end
  ) as effective_priority,
  issue.assigned_to,
  issue.triage_note,
  issue.occurrence_count,
  issue.raw_signature,
  issue.issue_fingerprint,
  issue.observation_id,
  issue.product_id,
  issue.classification_history_id,
  issue.product_measurement_id,
  issue.evidence,
  issue.resolution,
  issue.first_seen_at,
  issue.last_seen_at,
  issue.acknowledged_at,
  issue.resolved_at
from fitmatch_catalog.data_quality_issues issue
where issue.status in ('open', 'acknowledged');

revoke all on fitmatch_catalog.data_quality_review_queue
  from public, anon, authenticated;
grant select on fitmatch_catalog.data_quality_review_queue to service_role;

create or replace function fitmatch_catalog.runtime_triage_data_quality_issue(
  p_issue_id uuid,
  p_status text,
  p_priority smallint default null,
  p_assigned_to uuid default null,
  p_note text default null,
  p_resolution jsonb default '{}'
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_issue fitmatch_catalog.data_quality_issues%rowtype;
begin
  if p_issue_id is null
     or p_status not in ('open', 'acknowledged', 'resolved', 'ignored')
     or (p_priority is not null and (p_priority < 0 or p_priority > 100))
     or jsonb_typeof(coalesce(p_resolution, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_data_quality_triage';
  end if;
  if p_status in ('resolved', 'ignored')
     and coalesce(p_resolution, '{}'::jsonb) = '{}'::jsonb then
    raise exception using errcode = '22023', message = 'resolution_reason_required';
  end if;

  select * into v_issue
  from fitmatch_catalog.data_quality_issues
  where id = p_issue_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'data_quality_issue_not_found';
  end if;

  update fitmatch_catalog.data_quality_issues
  set status = p_status,
      triage_priority = coalesce(p_priority, triage_priority),
      assigned_to = p_assigned_to,
      triage_note = nullif(btrim(coalesce(p_note, '')), ''),
      acknowledged_at = case
        when p_status = 'acknowledged' then coalesce(acknowledged_at, now())
        when p_status = 'open' then null
        else acknowledged_at
      end,
      resolution = case
        when p_status in ('resolved', 'ignored')
          then resolution || coalesce(p_resolution, '{}'::jsonb)
        when p_status = 'open' then '{}'::jsonb
        else resolution
      end,
      resolved_at = case when p_status = 'resolved' then now() else null end,
      updated_at = now()
  where id = p_issue_id
  returning * into v_issue;

  return jsonb_build_object(
    'issue_id', v_issue.id,
    'status', v_issue.status,
    'priority', v_issue.triage_priority,
    'assigned_to', v_issue.assigned_to,
    'acknowledged_at', v_issue.acknowledged_at,
    'resolved_at', v_issue.resolved_at
  );
end $$;

revoke all on function fitmatch_catalog.runtime_triage_data_quality_issue(
  uuid, text, smallint, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function fitmatch_catalog.runtime_triage_data_quality_issue(
  uuid, text, smallint, uuid, text, jsonb
) to service_role;

comment on view fitmatch_catalog.data_quality_review_queue is
  'Backend review queue over the existing deduplicated data-quality issue ledger.';

commit;
