-- LOCAL/STAGING ONLY. Run after migrations 113 and 114. Never run against
-- Production. All synthetic rows are rolled back.
begin;

do $$
declare
  v_active_release_id uuid;
  v_gate_report jsonb;
  v_issue_id uuid;
  v_triage jsonb;
  v_anon_activate boolean;
  v_authenticated_triage boolean;
begin
  if to_regclass('fitmatch_catalog.releases_one_active_idx') is null then
    raise exception 'single-active-release index is missing';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgname = 'releases_activation_gate_trigger' and not tgisinternal
  ) then
    raise exception 'release activation trigger is missing';
  end if;

  select id into strict v_active_release_id
  from fitmatch_catalog.releases
  where status = 'active'
  order by activated_at desc nulls last, created_at desc
  limit 1;

  v_gate_report := fitmatch_catalog.runtime_release_gate_report(v_active_release_id);
  if coalesce((v_gate_report->>'eligible')::boolean, true)
     or not (v_gate_report->'blockers' @> '["qa_fixture_count_missing"]'::jsonb) then
    raise exception 'known mapping-only release must fail the new production gate: %',
      v_gate_report;
  end if;

  v_issue_id := fitmatch_catalog.runtime_record_signature_issue(
    'verification',
    'UNKNOWN_SOURCE_CATEGORY',
    'verification > unmapped',
    'medium',
    '{"verification":true}'::jsonb
  );
  v_triage := fitmatch_catalog.runtime_triage_data_quality_issue(
    v_issue_id,
    'acknowledged',
    90,
    null,
    'verification assignment',
    '{}'::jsonb
  );
  if v_triage->>'status' <> 'acknowledged'
     or (v_triage->>'priority')::integer <> 90
     or not exists (
       select 1 from fitmatch_catalog.data_quality_review_queue
       where id = v_issue_id and effective_priority = 90
     ) then
    raise exception 'review queue acknowledgement failed: %', v_triage;
  end if;

  v_triage := fitmatch_catalog.runtime_triage_data_quality_issue(
    v_issue_id,
    'resolved',
    null,
    null,
    'verified resolution',
    '{"reason":"verification"}'::jsonb
  );
  if v_triage->>'status' <> 'resolved'
     or exists (
       select 1 from fitmatch_catalog.data_quality_review_queue where id = v_issue_id
     ) then
    raise exception 'review queue resolution failed: %', v_triage;
  end if;

  select has_function_privilege(
    'anon',
    'fitmatch_catalog.runtime_activate_validated_release(uuid)',
    'EXECUTE'
  ) into v_anon_activate;
  select has_function_privilege(
    'authenticated',
    'fitmatch_catalog.runtime_triage_data_quality_issue(uuid,text,smallint,uuid,text,jsonb)',
    'EXECUTE'
  ) into v_authenticated_triage;
  if coalesce(v_anon_activate, true) or coalesce(v_authenticated_triage, true) then
    raise exception 'app roles must not execute release or triage mutations';
  end if;
end $$;

rollback;
