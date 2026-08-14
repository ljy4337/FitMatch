begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:briefcase-correction-v1'));

create table if not exists fitmatch_taxonomy.classification_correction_backups (
  correction_code text not null,
  decision_id uuid not null references fitmatch_taxonomy.classification_decisions(id) on delete restrict,
  decision_before jsonb not null,
  app_mapping_before jsonb,
  extension_before jsonb,
  created_at timestamptz not null default now(),
  primary key (correction_code, decision_id)
);
alter table fitmatch_taxonomy.classification_correction_backups enable row level security;
revoke all on fitmatch_taxonomy.classification_correction_backups from public, anon, authenticated;

with targets as (
  select d.id as decision_id
  from fitmatch_taxonomy.classification_decisions d
  join fitmatch_taxonomy.source_categories c on c.id=d.source_category_id
  where d.policy_version='taxonomy-refined-2026-08-03'
    and c.source_code='musinsa'
    and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
    and c.normalized_lookup_path ~* '(가방|브리프\s*케이스|briefcase)'
)
insert into fitmatch_taxonomy.classification_correction_backups
  (correction_code,decision_id,decision_before,app_mapping_before,extension_before)
select 'briefcase-not-underwear-v1',d.id,to_jsonb(d),to_jsonb(m),to_jsonb(e)
from targets t
join fitmatch_taxonomy.classification_decisions d on d.id=t.decision_id
left join fitmatch_taxonomy.category_app_mappings m on m.decision_id=d.id
left join fitmatch_taxonomy.extension_registry e on e.decision_id=d.id
on conflict (correction_code,decision_id) do nothing;

do $$
declare v_count integer;
begin
  select count(*) into v_count from fitmatch_taxonomy.classification_correction_backups
  where correction_code='briefcase-not-underwear-v1';
  if v_count <> 4 then raise exception 'Expected 4 briefcase corrections, found %',v_count; end if;
end $$;

delete from fitmatch_taxonomy.category_app_mappings m
using fitmatch_taxonomy.classification_correction_backups b
where b.correction_code='briefcase-not-underwear-v1' and m.decision_id=b.decision_id;

delete from fitmatch_taxonomy.extension_registry e
using fitmatch_taxonomy.classification_correction_backups b
where b.correction_code='briefcase-not-underwear-v1' and e.decision_id=b.decision_id;

update fitmatch_taxonomy.classification_decisions d set
  decision_status='rejected', decision_method='explicit_non_garment_context_correction',
  confidence=1, decision_reason='briefcase is a bag and not a FitMatch-comparable garment',
  semantic_category_code=null, garment_type_code=null, comparison_family_code=null,
  app_support_status='not_applicable', fallback_required=false, fallback_inputs='{}',
  canonical_default_allowed=false
from fitmatch_taxonomy.classification_correction_backups b
where b.correction_code='briefcase-not-underwear-v1' and d.id=b.decision_id;

commit;
