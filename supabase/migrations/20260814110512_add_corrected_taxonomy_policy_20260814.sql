
set lock_timeout='10s';
set statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('fitmatch_taxonomy:taxonomy-corrected-2026-08-14'));

do $$
begin
 if exists(select 1 from fitmatch_taxonomy.policy_versions where code='taxonomy-corrected-2026-08-14')
 then raise exception 'policy already exists'; end if;
 if (select count(*) from fitmatch_taxonomy.classification_decisions where policy_version='taxonomy-refined-2026-08-03')<>4008
 then raise exception 'base decision count mismatch'; end if;
end $$;

insert into fitmatch_taxonomy.policy_versions
(code,schema_version,taxonomy_version,manifest_checksum,status)
values ('taxonomy-corrected-2026-08-14','1.2','observed-official-2026-08-03',
'acb5d29f00840773f3283fc9ea5e8703078d7bb205a844e4da245940fdca0467','loading');

create temp table _decision_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
insert into _decision_map
select id,gen_random_uuid()
from fitmatch_taxonomy.classification_decisions
where policy_version='taxonomy-refined-2026-08-03';

insert into fitmatch_taxonomy.classification_decisions(
 id,source_category_id,decision_status,decision_method,confidence,decision_reason,evidence,
 sampling_status,reviewed_at,policy_version,legacy_policy_version,semantic_category_code,
 garment_type_code,comparison_family_code,app_support_status,fallback_required,fallback_inputs,
 canonical_default_allowed
)
select dm.new_id,d.source_category_id,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
  and c.normalized_lookup_path ~* '(가방|브리프\s*케이스|briefcase)'
 then 'rejected' else d.decision_status end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then 'explicit_non_garment_context_correction' else d.decision_method end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then 1 else d.confidence end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then 'briefcase is a bag and not a FitMatch-comparable garment' else d.decision_reason end,
 d.evidence || jsonb_build_object('predecessorPolicyVersion','taxonomy-refined-2026-08-03',
  'correctionPolicyVersion','taxonomy-corrected-2026-08-14'),
 d.sampling_status,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then transaction_timestamp() else d.reviewed_at end,
 'taxonomy-corrected-2026-08-14','taxonomy-refined-2026-08-03',
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then null else d.semantic_category_code end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then null else d.garment_type_code end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then null else d.comparison_family_code end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then 'not_applicable' else d.app_support_status end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then false else d.fallback_required end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then '{}'::text[] else d.fallback_inputs end,
 case when c.source_code='musinsa'
  and c.external_category_id in ('004008','105003002009','107003001007','108003001007')
 then false else d.canonical_default_allowed end
from fitmatch_taxonomy.classification_decisions d
join _decision_map dm on dm.old_id=d.id
join fitmatch_taxonomy.source_categories c on c.id=d.source_category_id
where d.policy_version='taxonomy-refined-2026-08-03';

insert into fitmatch_taxonomy.decision_length_axes(
 decision_id,sleeve_length_class,pants_length_class,leggings_length_class,skirt_length_class,
 body_length_class,construction_type,policy_version
)
select dm.new_id,a.sleeve_length_class,a.pants_length_class,a.leggings_length_class,
 a.skirt_length_class,a.body_length_class,a.construction_type,'taxonomy-corrected-2026-08-14'
from fitmatch_taxonomy.decision_length_axes a
join _decision_map dm on dm.old_id=a.decision_id
where a.policy_version='taxonomy-refined-2026-08-03';

insert into fitmatch_taxonomy.category_app_mappings(
 decision_id,app_category_code,app_detail_code,current_comparison_family,current_length_type,
 mapping_status,transformation_rule,lossiness,app_taxonomy_version,comparison_policy_version
)
select dm.new_id,a.app_category_code,a.app_detail_code,a.current_comparison_family,a.current_length_type,
 a.mapping_status,a.transformation_rule,a.lossiness,a.app_taxonomy_version,'taxonomy-corrected-2026-08-14'
from fitmatch_taxonomy.category_app_mappings a
join _decision_map dm on dm.old_id=a.decision_id
join fitmatch_taxonomy.classification_decisions nd on nd.id=dm.new_id and nd.decision_status='confirmed'
where a.comparison_policy_version='taxonomy-refined-2026-08-03';

insert into fitmatch_taxonomy.decision_evidence(
 decision_id,evidence_type,evidence,evidence_hash,policy_version
)
select dm.new_id,e.evidence_type,
 e.evidence || jsonb_build_object('predecessorPolicyVersion','taxonomy-refined-2026-08-03',
  'correctionPolicyVersion','taxonomy-corrected-2026-08-14'),
 encode(digest((e.evidence || jsonb_build_object(
  'predecessorPolicyVersion','taxonomy-refined-2026-08-03',
  'correctionPolicyVersion','taxonomy-corrected-2026-08-14'))::text,'sha256'),'hex'),
 'taxonomy-corrected-2026-08-14'
from fitmatch_taxonomy.decision_evidence e
join _decision_map dm on dm.old_id=e.decision_id
where e.policy_version='taxonomy-refined-2026-08-03';

insert into fitmatch_taxonomy.classification_audit_history(
 decision_id,legacy_source_category_id,legacy_status,canonical_status,changed,change_reason,
 legacy_policy_version,canonical_policy_version,evidence
)
select dm.new_id,a.legacy_source_category_id,d.decision_status,nd.decision_status,
 d.decision_status is distinct from nd.decision_status,
 case when d.decision_status is distinct from nd.decision_status
  then 'briefcase non-garment context correction'
  else 'Copied unchanged from predecessor policy' end,
 'taxonomy-refined-2026-08-03','taxonomy-corrected-2026-08-14',
 jsonb_build_object('predecessorDecisionID',d.id,'correctionCode','briefcase-not-underwear-v2')
from fitmatch_taxonomy.classification_decisions d
join _decision_map dm on dm.old_id=d.id
join fitmatch_taxonomy.classification_decisions nd on nd.id=dm.new_id
left join lateral (
 select x.legacy_source_category_id
 from fitmatch_taxonomy.classification_audit_history x
 where x.decision_id=d.id order by x.created_at limit 1
) a on true
where d.policy_version='taxonomy-refined-2026-08-03';

do $$
declare counts jsonb;
begin
 select jsonb_object_agg(decision_status,n) into counts
 from (select decision_status,count(*)::int n
  from fitmatch_taxonomy.classification_decisions
  where policy_version='taxonomy-corrected-2026-08-14'
  group by decision_status) s;
 if counts <> '{"confirmed":1327,"review_required":608,"rejected":1451,"unsupported":40,"navigation_only":582}'::jsonb
 then raise exception 'corrected counts mismatch: %',counts; end if;
 if (select count(*) from fitmatch_taxonomy.category_app_mappings
  where comparison_policy_version='taxonomy-corrected-2026-08-14')<>1327
 then raise exception 'corrected mapping count mismatch'; end if;
 if (select count(*) from fitmatch_taxonomy.decision_length_axes
  where policy_version='taxonomy-corrected-2026-08-14')<>4008
 then raise exception 'corrected axes count mismatch'; end if;
 if (select count(*) from fitmatch_taxonomy.classification_audit_history
  where canonical_policy_version='taxonomy-corrected-2026-08-14')<>4008
 then raise exception 'corrected audit count mismatch'; end if;
end $$;

update fitmatch_taxonomy.policy_versions
set status='validated',validated_at=transaction_timestamp()
where code='taxonomy-corrected-2026-08-14';
;
