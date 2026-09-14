-- Read-only postflight. Run only after the prepared migration is applied.
select n.nspname, p.proname,
  pg_get_function_arguments(p.oid) as arguments,
  p.prosecdef as security_definer,
  p.proconfig as settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.oid in (
  'fitmatch_vnext.comparison_target_context(uuid,uuid,text)'::regprocedure,
  'fitmatch_vnext.canonical_measurements_for_session_group(uuid,jsonb)'::regprocedure,
  'fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure,
  'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean,text)'::regprocedure,
  'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure,
  'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure,
  'fitmatch_vnext.begin_comparison(jsonb)'::regprocedure,
  'public.fitmatch_vnext_find_reference_candidates(uuid,uuid,text)'::regprocedure,
  'public.fitmatch_vnext_eligible_candidate_sizes(uuid,uuid,uuid,boolean,text)'::regprocedure
)
order by n.nspname, p.proname;

-- Each public overload must have a distinct required parameter set so
-- PostgREST can select it without default-argument ambiguity.
select p.oid::regprocedure::text as function_name,
  p.pronargs as argument_count,
  p.pronargdefaults as default_argument_count,
  p.proargnames as argument_names
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'fitmatch_vnext_find_reference_candidates',
    'fitmatch_vnext_eligible_candidate_sizes'
  )
order by p.proname, p.pronargs;

select
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
  p.oid::regprocedure::text as function_name
from pg_proc p
where p.oid in (
  'fitmatch_vnext.comparison_target_context(uuid,uuid,text)'::regprocedure,
  'fitmatch_vnext.canonical_measurements_for_session_group(uuid,jsonb)'::regprocedure,
  'fitmatch_vnext.find_reference_candidates(uuid,uuid,text)'::regprocedure,
  'fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean,text)'::regprocedure,
  'fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure,
  'fitmatch_vnext.authorize_comparison_with_context(uuid,uuid,uuid,boolean,jsonb,text)'::regprocedure,
  'fitmatch_vnext.begin_comparison(jsonb)'::regprocedure
)
order by function_name;

-- The old signatures must remain for mapped-product compatibility.
select to_regprocedure('fitmatch_vnext.find_reference_candidates(uuid,uuid)'),
  to_regprocedure('fitmatch_vnext.eligible_candidate_sizes(uuid,uuid,uuid,boolean)'),
  to_regprocedure('public.fitmatch_vnext_find_reference_candidates(uuid,uuid)'),
  to_regprocedure('public.fitmatch_vnext_eligible_candidate_sizes(uuid,uuid,uuid,boolean)');

-- Persistence safety: the migration creates no trigger and performs no DML
-- against mappings, products, or user classification tables.
select count(*) as forbidden_trigger_count
from pg_trigger t
join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
  and p.proname in (
    'comparison_target_context',
    'canonical_measurements_for_session_group'
  );
