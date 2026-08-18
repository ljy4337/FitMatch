begin;

-- The trusted runtime classifiers are SECURITY INVOKER functions.  Their
-- service-role caller therefore needs read access to canonical policy data.
-- Client roles remain fully denied.
grant usage on schema fitmatch_taxonomy to service_role;
grant select on
  fitmatch_taxonomy.policy_versions,
  fitmatch_taxonomy.runtime_classification_rules,
  fitmatch_taxonomy.source_measurement_aliases
to service_role;

revoke usage on schema fitmatch_taxonomy from public, anon, authenticated;
revoke all on
  fitmatch_taxonomy.policy_versions,
  fitmatch_taxonomy.runtime_classification_rules,
  fitmatch_taxonomy.source_measurement_aliases
from public, anon, authenticated;

commit;
