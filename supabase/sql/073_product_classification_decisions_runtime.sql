-- FitMatch product-level canonical classification runtime (2026-08-16)
-- Prerequisite: 072_db_app_adjudication_qa_alignment.sql
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('fitmatch_catalog:product-classification-decisions-v1'));

do $$
declare
  v_cases integer;
  v_e492123 boolean;
begin
  select count(*) into v_cases
  from fitmatch_qa.classification_cases
  where release_id = '568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid;
  if v_cases <> 5026 then
    raise exception 'expected 5026 canonical QA cases, got %', v_cases;
  end if;

  select exists(
    select 1 from fitmatch_qa.classification_cases
    where release_id = '568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid
      and source='uniqlo' and product_id='E492123'
      and expected_category_code='tops' and expected_detail_code='shirt'
      and expected_comparison_family='shirt' and expected_length_type='long_sleeve'
      and not requires_user_confirmation
  ) into v_e492123;
  if not v_e492123 then
    raise exception '072 prerequisite is not applied: E492123 canonical decision differs';
  end if;
end $$;

create table if not exists fitmatch_catalog.product_classification_decisions (
  source text not null,
  external_product_id text not null,
  product_name text not null,
  source_category_path text not null,
  input_fingerprint text not null,
  category_code text,
  detail_code text,
  comparison_family text,
  length_type text,
  requires_user_confirmation boolean not null,
  release_id uuid not null references fitmatch_catalog.releases(id),
  decision_version text not null,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (source, external_product_id),
  check (source ~ '^[a-z][a-z0-9_]*$')
);

create index if not exists product_classification_decisions_release_idx
  on fitmatch_catalog.product_classification_decisions (release_id, source);

alter table fitmatch_catalog.product_classification_decisions enable row level security;
revoke all on fitmatch_catalog.product_classification_decisions from anon, authenticated;
grant select, insert, update on fitmatch_catalog.product_classification_decisions to service_role;

insert into fitmatch_catalog.product_classification_decisions (
  source, external_product_id, product_name, source_category_path,
  input_fingerprint, category_code, detail_code, comparison_family, length_type,
  requires_user_confirmation, release_id, decision_version, evidence
)
select
  c.source,
  c.product_id,
  coalesce(c.product_name,''),
  coalesce(c.input_payload->>'source_path',''),
  md5(lower(trim(coalesce(c.product_name,''))) || E'\n' ||
      lower(trim(coalesce(c.input_payload->>'source_path','')))),
  c.expected_category_code,
  c.expected_detail_code,
  c.expected_comparison_family,
  c.expected_length_type,
  c.requires_user_confirmation,
  c.release_id,
  'db-app-adjudicated-2026-08-16-v1',
  jsonb_build_object(
    'source','fitmatch_qa.classification_cases',
    'case_key',c.case_key,
    'adjudication',c.result_payload->'adjudicationVerdict',
    'confidence',c.result_payload->'adjudicationConfidence',
    'basis',c.result_payload->'adjudicationBasis'
  )
from fitmatch_qa.classification_cases c
where c.release_id = '568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid
on conflict (source,external_product_id) do update set
  product_name=excluded.product_name,
  source_category_path=excluded.source_category_path,
  input_fingerprint=excluded.input_fingerprint,
  category_code=excluded.category_code,
  detail_code=excluded.detail_code,
  comparison_family=excluded.comparison_family,
  length_type=excluded.length_type,
  requires_user_confirmation=excluded.requires_user_confirmation,
  release_id=excluded.release_id,
  decision_version=excluded.decision_version,
  evidence=excluded.evidence,
  updated_at=now();

create or replace function fitmatch_catalog.resolve_product_classification(
  p_source text,
  p_external_product_id text,
  p_product_name text,
  p_source_category_path text
) returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,fitmatch_catalog,fitmatch_taxonomy
as $$
declare
  v_decision fitmatch_catalog.product_classification_decisions%rowtype;
  v_fingerprint text;
  v_fallback jsonb;
begin
  v_fingerprint := md5(
    lower(trim(coalesce(p_product_name,''))) || E'\n' ||
    lower(trim(coalesce(p_source_category_path,'')))
  );

  select * into v_decision
  from fitmatch_catalog.product_classification_decisions
  where source=lower(p_source)
    and external_product_id=p_external_product_id;

  if found and v_decision.input_fingerprint=v_fingerprint then
    return jsonb_build_object(
      'category_code',v_decision.category_code,
      'detail_code',v_decision.detail_code,
      'family_code',v_decision.comparison_family,
      'length_code',v_decision.length_type,
      'requires_user_confirmation',v_decision.requires_user_confirmation,
      'comparable',not v_decision.requires_user_confirmation
        and v_decision.category_code is not null
        and v_decision.detail_code is not null
        and v_decision.category_code <> 'other'
        and v_decision.detail_code <> 'other',
      'decision_source','canonical_product_decision',
      'decision_version',v_decision.decision_version
    );
  end if;

  v_fallback := fitmatch_taxonomy.evaluate_runtime_classification(
    'app-hardcoded-parity-2026-08-06-v1',lower(p_source),p_product_name,p_source_category_path
  );

  -- A new or changed product must never be silently represented as parity-
  -- verified. Return the legacy suggestion only as review evidence.
  return jsonb_build_object(
    'category_code',null,
    'detail_code',null,
    'family_code',null,
    'length_code',null,
    'requires_user_confirmation',true,
    'comparable',false,
    'decision_source',case when found then 'changed_product_review' else 'new_product_review' end,
    'suggestion',v_fallback
  );
end $$;

revoke all on function fitmatch_catalog.resolve_product_classification(text,text,text,text)
  from public,anon,authenticated;
grant execute on function fitmatch_catalog.resolve_product_classification(text,text,text,text)
  to service_role;

do $$
declare
  v_rows integer;
  v_exact integer;
begin
  select count(*) into v_rows
  from fitmatch_catalog.product_classification_decisions
  where release_id='568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid;
  if v_rows <> 5026 then
    raise exception 'runtime decision seed must contain 5026 rows, got %',v_rows;
  end if;

  select count(*) into v_exact
  from fitmatch_qa.classification_cases c
  cross join lateral fitmatch_catalog.resolve_product_classification(
    c.source,c.product_id,c.product_name,c.input_payload->>'source_path'
  ) as x(result)
  where c.release_id='568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid
    and x.result->>'category_code' is not distinct from c.expected_category_code
    and x.result->>'detail_code' is not distinct from c.expected_detail_code
    and x.result->>'family_code' is not distinct from c.expected_comparison_family
    and x.result->>'length_code' is not distinct from c.expected_length_type
    and (x.result->>'requires_user_confirmation')::boolean
        is not distinct from c.requires_user_confirmation;
  if v_exact <> 5026 then
    raise exception 'DB runtime parity failed: expected 5026 exact rows, got %',v_exact;
  end if;
end $$;

commit;

select count(*) as total,
       count(*) filter (where not requires_user_confirmation) as auto_classified,
       count(*) filter (where requires_user_confirmation) as review_required
from fitmatch_catalog.product_classification_decisions
where release_id='568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid;

select fitmatch_catalog.resolve_product_classification(
  'uniqlo','E492123','데님릴렉스셔츠재킷',
  '셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔'
) as e492123_result;
