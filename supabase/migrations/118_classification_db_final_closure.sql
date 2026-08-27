begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(
  hashtext('fitmatch:classification-db-final-closure-2026-08-26-v1')
);

-- Local-first candidate closure. Applying this migration creates a validated,
-- inactive release only. It never activates/retire releases, writes product
-- history, or persists candidate exact decisions.

create table if not exists
fitmatch_catalog.classification_structured_discriminator_rules (
  release_id uuid not null references fitmatch_catalog.releases(id),
  rule_id text not null,
  source text not null,
  discriminator_key text not null,
  discriminator_value text not null,
  external_category_id text,
  normalized_path text,
  target text,
  outcome text not null check (outcome in ('canonical', 'not_comparable')),
  category_code text,
  detail_code text,
  garment_type_code text references public.garment_types(code)
    on update restrict on delete restrict,
  family_code text references public.comparison_groups(code)
    on update restrict on delete restrict,
  length_code text,
  body_length_code text,
  exclusion_reason_code text,
  authority_status text not null
    check (authority_status in ('verified', 'revoked')),
  resolution_scope text not null
    check (resolution_scope in ('structured_product', 'excluded')),
  runtime_eligible boolean not null default false,
  evidence jsonb not null default '{}'::jsonb,
  policy_version text not null,
  created_at timestamptz not null default now(),
  primary key (release_id, rule_id),
  check (source = '*' or source ~ '^[a-z][a-z0-9_]*$'),
  check (discriminator_key ~ '^[a-z][a-z0-9_]*$'),
  check (btrim(discriminator_value) <> ''),
  check (
    (outcome = 'canonical'
      and category_code is not null
      and detail_code is not null
      and garment_type_code is not null
      and family_code is not null
      and exclusion_reason_code is null
      and (external_category_id is not null or normalized_path is not null))
    or
    (outcome = 'not_comparable'
      and category_code is null
      and detail_code is null
      and garment_type_code is null
      and family_code is null
      and length_code is null
      and body_length_code is null
      and exclusion_reason_code is not null)
  )
);

create index if not exists
classification_structured_discriminator_runtime_idx
on fitmatch_catalog.classification_structured_discriminator_rules (
  release_id, source, discriminator_key, discriminator_value
)
where runtime_eligible and authority_status = 'verified';

comment on table
fitmatch_catalog.classification_structured_discriminator_rules is
  'Typed retailer facts resolved generically by key/value plus optional category/path/target scope; never stores SQL, regex, expressions, or source-specific executable rules.';

revoke all on table
  fitmatch_catalog.classification_structured_discriminator_rules
  from public, anon, authenticated;
grant select on table
  fitmatch_catalog.classification_structured_discriminator_rules
  to service_role;

create index if not exists source_category_mappings_runtime_code_idx
on fitmatch_catalog.source_category_mappings (
  release_id, source, external_category_id, target
)
where runtime_lookup_eligible and eligibility;

create index if not exists source_category_mappings_runtime_path_idx
on fitmatch_catalog.source_category_mappings (
  release_id, source,
  fitmatch_catalog.runtime_normalized_category_path(normalized_path), target
)
where runtime_lookup_eligible and eligibility;

-- Production retains enum-style checks from the pre-closure taxonomy.
-- Expand them before inserting the owner-approved dress, underwear, and
-- homewear families. The disposable fixture did not model these legacy
-- constraints, so this explicit evolution is required for production parity.
alter table public.comparison_groups
  drop constraint if exists comparison_groups_major_category_code_check;
alter table public.comparison_groups
  add constraint comparison_groups_major_category_code_check check (
    major_category_code in (
      'tops', 'bottoms', 'outerwear', 'skirts', 'leggings',
      'dresses', 'underwear', 'homewear', 'other'
    )
  );

alter table public.garment_types
  drop constraint if exists garment_types_major_category_code_check;
alter table public.garment_types
  add constraint garment_types_major_category_code_check check (
    major_category_code in (
      'tops', 'bottoms', 'outerwear', 'skirts', 'leggings',
      'dresses', 'underwear', 'homewear', 'other'
    )
  );

alter table public.comparison_policies
  drop constraint if exists comparison_policies_reference_priority_mode_check;
alter table public.comparison_policies
  add constraint comparison_policies_reference_priority_mode_check check (
    reference_priority_mode in (
      'same_type_only', 'same_type_then_group', 'closest'
    )
  );

alter table fitmatch_taxonomy.comparison_compatibility_rules
  drop constraint if exists
    comparison_compatibility_rule_minimum_common_measurements_check;
alter table fitmatch_taxonomy.comparison_compatibility_rules
  add constraint
    comparison_compatibility_rule_minimum_common_measurements_check check (
      (allowed and minimum_common_measurements > 0)
      or (not allowed and minimum_common_measurements >= 0)
    );

-- Production historically required two observed products for every exclusion
-- profile. Closure includes three independently verified singleton retailer
-- taxonomy paths. Permit only that narrow verified/complete non-apparel case;
-- unverified or generic singleton profiles remain rejected.
alter table fitmatch_catalog.classification_exclusion_profiles
  drop constraint if exists classification_exclusion_profiles_sample_check;
alter table fitmatch_catalog.classification_exclusion_profiles
  add constraint classification_exclusion_profiles_sample_check check (
    sample_count >= 2
    or (
      sample_count = 1
      and auto_eligible
      and reason_code = 'non_apparel_or_accessory'
      and evidence->>'authority_status' = 'verified'
      and coalesce((evidence->>'complete_profile')::boolean, false)
    )
  );

create or replace function
fitmatch_catalog.runtime_classification_db_final_manifest_v1()
returns table (value jsonb)
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $function$
  select item.value
  from jsonb_array_elements(
    $manifest$[{"record_type":"meta","manifest_version":"fitmatch-classification-db-final-closure-2026-08-26-v1","release_id":"11800000-0000-4000-8000-000000000118","release_key":"fitmatch-classification-authority-final-candidate-2026-08-26-v1","parent_candidate_release_id":"f83ca2f0-88a4-4430-96fc-037d6f1efcc2","production_parent_release_id":"65d72393-4a40-4e99-b701-fdc1ff865774","baseline_checksums":{"phase1b2r_shadow":"bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916","phase1b2_shadow":"b1b49b767efe2ca6be1441703fa38bb9235135d1235a9b1f94f8d86ddbb10385","review_evidence_audit":"cbcfa931a01c152f6b8205cf26a3d2696af73ad5b3ec0f9585f52831eec81ddb"},"baseline_product_count":1608,"baseline_key_fingerprint_checksum":"c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a","runtime_contract":{"resolver":"v4","evaluator":"v4","recorder":"v2","classifier_policy_version":"db-classifier-2026-08-26-final","comparison_policy_version":"v1","compatibility_rule_version":"db-comparison-2026-08-26-final","measurement_policy_version":"2026.07.1"},"production_apply_performed":false,"generated_at":"2026-08-26T00:00:00+09:00"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"b3d1f834e4a29fd9bf89e62f1db946e2","external_product_id":"2447802"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"59585982ccf04f28ba3e091d024242c6","external_product_id":"2518490"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"bafea1563a3be6f5be4b381101f8e9e8","external_product_id":"2737014"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"217f67161581b31a5f94e0f1d510937b","external_product_id":"3042005"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"72fc7bcad5bb13e0ca727ab3ff18368d","external_product_id":"3134729"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"0b2235f85e458949cd9879139ac975e4","external_product_id":"3138552"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"efd887f964768e1e5d1826ee64473913","external_product_id":"3144417"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"327d15e54ec0f1e3c5978e0e80b47165","external_product_id":"3225860"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"b860caee038524069a8efced00269cc2","external_product_id":"3346165"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"4f2e1e9db44f7fdf3581c10528aa2adc","external_product_id":"3442344"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"ad6e7f00d7914eedd6f5cf9289985d7a","external_product_id":"3503598"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"코트"},"input_fingerprint":"0eeab6af5cd76076488437d70acc19a4","external_product_id":"3690284"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"5e57dfe6e02481399a70c97e9e2b4a66","external_product_id":"3774997"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼_래글런"},"input_fingerprint":"5c126d6238629cecb309b089415c7b51","external_product_id":"3822928"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"08c513da30d29a9afc5edfdd2413ab65","external_product_id":"4062254"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"9d185495c83a92f9ed9b934d17c1840b","external_product_id":"4154987"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"47e03d1e74590201e79e0a6c887ea0bf","external_product_id":"4163350"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"c7db14cbe50a41d3284ffeb902cb96de","external_product_id":"4341120"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"d1f7206723702f91f1f11e81d5b0ecdb","external_product_id":"4636893"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"5d0bd17dd787ba45a2f27047a8757873","external_product_id":"4651400"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"56e0a892ca5748e3ea5c9f9c54ff301a","external_product_id":"4664068"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"1fb74030ccc69f07b4eb0359ef716948","external_product_id":"4696797"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"2487b90fa419d13e4ce7753e667a41a2","external_product_id":"4720624"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"a30c08b665df65934965272d5b5b61e6","external_product_id":"4747236"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"de05ae50259eb8b4fccd9a1441a7b80d","external_product_id":"4763740"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"4800605","input_fingerprint":"5b6f70bf66ede25eb1d58daefab15524","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"a5fdc2c409d945ae6f657d20bb666d95","external_product_id":"4818151"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"d3c36ca52f431cc188ef8ee69cfdd61f","external_product_id":"4971043"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"8145ba504e94a563bdd4684de21a65f2","external_product_id":"5038460"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"258ecada6adb9a8a76fe523790dd5829","external_product_id":"5070728"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"59c814b455ef22869ad5876c0bf3af53","external_product_id":"5074988"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"097f69ab2a8a7b73a3fac9f19238f835","external_product_id":"5139106"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"8bc33e9644ab215e37b5e743daef03a2","external_product_id":"5310275"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"2c04a1231e7bbe65f6cf63c019b96d8f","external_product_id":"5322326"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"936d1821046863d5fdd3c51749a3e917","external_product_id":"5329359"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"5541b5c7fc966227e3798e4e941488e6","external_product_id":"5343592"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"de535d3d615e4a90baeb017833d0ddb1","external_product_id":"5442400"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼_래글런"},"input_fingerprint":"3ef1e9e7d1414c81ea52d846a0690164","external_product_id":"5489923"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"5d879cedc75e38f6903f9e56c0caf0ad","external_product_id":"5504965"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"a2fb001795b8da958f6892ee1c1a711c","external_product_id":"5661620"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"4ca6e702e5883700cd56ea8446ee39e9","external_product_id":"5661624"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"셔츠"},"input_fingerprint":"b93d71f05ff464913de3e334fde7379f","external_product_id":"5661658"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"코트"},"input_fingerprint":"85cf277596b9eb291a9317a5b374f94f","external_product_id":"5673055"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"59435b6415ad78014b59e574f21c70e0","external_product_id":"5698179"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"4957452d4ef316c7285c93a5bbc5681f","external_product_id":"5698181"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"fab866e0fe6f4e90be26755e45d88233","external_product_id":"5698186"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"713df20711c0f009c32e4e0ad6217743","external_product_id":"5795897"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"1127da95b8e46e060dc75a72c7bba40e","external_product_id":"5795942"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"코트"},"input_fingerprint":"4b44ca9738fc3e9ca1d08a09b317b185","external_product_id":"5828291"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"87e392e1ef7640205375255b9dcff479","external_product_id":"5936309"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"70760f44b747ec908f7704ea72a2cec8","external_product_id":"5980112"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"5982920","input_fingerprint":"ba0cf93ef2e1f5032b52d3619eeac5a8","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"ace39fac7395001e257ee74c28190abc","external_product_id":"5983366"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"f32b9bd9b4a87d9a47bece130337200a","external_product_id":"6021332"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"be4ceb0e80dac99e50e7caf451ce88bb","external_product_id":"6055644"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"c7c44f91c152f677f0e46ac74666f907","external_product_id":"6077337"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"9bf86d037d3403a17bbc209af89e0b7e","external_product_id":"6140472"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"a7ee66fb972dbd86ca465839737d868b","external_product_id":"6145321"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"5306974fbe22a28735ec810574e7ec7b","external_product_id":"6174464"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"0cab664e48d00344059e9ef121e7f1fc","external_product_id":"6182664"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"16de4b29dc29d644326a3dd4b4485fad","external_product_id":"6253269"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"d02ffbd2551991726d2760a612700757","external_product_id":"6305730"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"33d5ef75c680df543c912e0de11252ee","external_product_id":"6341391"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼_래글런"},"input_fingerprint":"723a38d6d089d34fec6a57688f6ca623","external_product_id":"6364512"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"77e56e5a4755b8adce8de8ea4cd33a9f","external_product_id":"6365348"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"06a6558217e03da00b804cb2c90c953d","external_product_id":"6390295"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"2f53561432aad5fb7e442858bf54799c","external_product_id":"6403675"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"9a4cb3fa964527335a81f229615e4bea","external_product_id":"6433137"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"2bf3a48f4828573819a80be055c67ad1","external_product_id":"6450036"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"cc492b31db515b3b532c243768f45ee1","external_product_id":"6469952"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"3076d249c3e9a2017e61e0f4bd8e3a40","external_product_id":"6496880"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"5f72d06b22effe31d3262cef7a87756f","external_product_id":"6501146"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"6b9127f1847c3533407b1c22dd597926","external_product_id":"6501149"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"248a6992bc917c4089f7fa671a6a92ab","external_product_id":"6504560"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"98e2187bd6747b8b0c5e9b3323796652","external_product_id":"6515986"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"61f19b2375d9c19f0f4ea964155999e3","external_product_id":"6534481"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"618c8db8597e6ba8e3ef7d6dc62119ea","external_product_id":"6565987"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"89559e676b98d74cdad140ad064ce8d9","external_product_id":"6590793"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"6593581","input_fingerprint":"fd1aebee2b96d7f8bb8a0a1935cb83f4","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"b1fee14963c4c6cf87e32f207dc8c309","external_product_id":"6595041"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"40e2ddfbf77dac83b0b018212b1bb3ee","external_product_id":"6595807"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"b3a6b3b5af4250fb38952b7dfb433187","external_product_id":"6595811"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"d58aff8d66e1a0e80f0981a5fbdf49ce","external_product_id":"6596161"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"8a31fc292aea82c7c195347b809bc991","external_product_id":"6610865"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"cd7390c9a6a997af0a6e7acb41a41f3a","external_product_id":"6618666"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"121b419595556d4f170fd7be06ecf873","external_product_id":"6622473"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"1ddc180ec1f7d65aa885b379535ce836","external_product_id":"6633891"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"6cf5ba3c323056c290f48aa884f50640","external_product_id":"6633896"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"336792356cf64b29f03d4dcd7111ef0d","external_product_id":"6639238"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"7d0d1f419a1eb3f29e6a2734ab090899","external_product_id":"6666754"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"7e57e42d806a82deb38833757f22e683","external_product_id":"6677115"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"fc016433a99bd87b2e65093e4f4a07c7","external_product_id":"6686050"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"733da94c306c15bf94cf61babd210063","external_product_id":"6686197"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"40d66b5aeeadfa792e222fa46baa9d58","external_product_id":"6686255"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"6ba14880fca9997c4875494b2949cc67","external_product_id":"6686260"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매_래글런"},"input_fingerprint":"9cce4bd9bed057d57b790204aec85790","external_product_id":"6697403"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"5b80924e90e5e605af5fe10642993fdb","external_product_id":"6702426"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"7850b106f0f88aef30adca149ad5c0c3","external_product_id":"6702453"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"519330933bb8ed0a4b44fd317b3bea05","external_product_id":"6716192"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"9b6043bd8c377dfd37c5ed5bfe11d52b","external_product_id":"6716197"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"f2b268ca76d435a08f3cb8a2eba419ab","external_product_id":"6716203"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"3db73c2bfa224c0b15d9088081d89275","external_product_id":"6716212"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"e079fa05ac279863ff562461929ed84c","external_product_id":"6764812"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"셔츠"},"input_fingerprint":"e4adf22789972f51a382313e91237f8b","external_product_id":"6777736"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"a39e0935960fb6a7fdf57ea347c9ad86","external_product_id":"6777737"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"8a65e41ae724db90d21b57dfef7b8a28","external_product_id":"6778715"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"aa760d07b4f2812bcb4fa44daeefd84c","external_product_id":"6778769"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"091a0cae4df8a6aadefc21394b0c806e","external_product_id":"6781113"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"6786576","input_fingerprint":"15d350920b0f825226fd9a57cf35f698","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"셔츠"},"input_fingerprint":"21a1d73bd8ff00f45a36241e50ab68cb","external_product_id":"6797005"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"6797265","input_fingerprint":"fac8ba097793f91216720fed41bb5e4f","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"6797266","input_fingerprint":"6ba91618509ac607cd44545601e4b1ee","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"record_type":"product_structured_fact","source":"musinsa","external_product_id":"6797271","input_fingerprint":"aff0f3de8e9c2071c6a6dd9ade0811f0","structured_facts":{"product_structure":"set"},"evidence":"exact_port_of_existing_ios_set_validation_semantics_for_local_shadow_only","existing_validation":"ParsedClosetClassification.isExplicitCompositeGarmentSet"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"aaa1d34c8ac2b2c16d38e46ddd496c15","external_product_id":"6800367"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"98b3df85791d34a9510197b55229efca","external_product_id":"6800912"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"7417a0b40de3c5166c998dd46be0c7ca","external_product_id":"6800975"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"d7e1668539095d718a20a18e970dd6e8","external_product_id":"6805433"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"9f29c68dcc0662e56ae806823db544b8","external_product_id":"6809274"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"스커트"},"input_fingerprint":"895f6f811a92c4eeed50eca469832a97","external_product_id":"6812499"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"705bd868c2fd5f135ae3d7d04cef2b60","external_product_id":"6812676"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"056994a4f9be136bae03e090ba9f675f","external_product_id":"6829636"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"c12b48a3eda64b68cae0ab15d762cec1","external_product_id":"6830458"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"77202a8bb43dff247c12e28e22565dc3","external_product_id":"6833248"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"f46d71d6fc5b5eed67d89995793a9482","external_product_id":"6833448"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"8858b18e44f82c49210324c8d8c632d4","external_product_id":"6833866"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"3ead2a19d75b1486ed93cd6353bee527","external_product_id":"6837242"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"47e58910c959053febb7323c6420b138","external_product_id":"6839271"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"06aeb76094550d9efb84a02cc0bf3e11","external_product_id":"6842592"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"cc19aed8be9be626c3e7f35dfe6b220d","external_product_id":"6842612"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"eea4215a4ef974782ba9deb6a2d60069","external_product_id":"6842888"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"61fad1543dae707a627e3bf91adc6ec7","external_product_id":"6849281"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"6dec3379890d5606fb19630091f0fc0c","external_product_id":"6850912"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"7f7f03c81587af66e4c1faa14c478c63","external_product_id":"6852823"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"57be912e19c6782ee48b56843eff952d","external_product_id":"6853485"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"c9307c4910adcd28bb9404a7940f6346","external_product_id":"6858118"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"c08406d851bb0cfdbd2d6f8b556da76b","external_product_id":"6874981"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"53508c46cf74773ab8c2780a43c73542","external_product_id":"6876277"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"6f2b671a610ccb86a11d602484f51316","external_product_id":"6878575"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"af9f9099f66b317928297f78a62d2773","external_product_id":"6885251"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼_래글런"},"input_fingerprint":"34f6b4846609c298dafef02dcc5a8fea","external_product_id":"6887357"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"dfa9894385cf1042ca947853a20ff3d1","external_product_id":"6896379"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"a7d84e4778f058156c064874459863b7","external_product_id":"6896783"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"76f2b4a9425ea121b6459c1be66a70b0","external_product_id":"6897082"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"ed00f0f93557f6c5a5f019d87654982e","external_product_id":"6901447"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"0ae6ac4a2ac714d7cc17a4296c70a2cb","external_product_id":"6903639"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"b8c924b5085954c0ecf2d1f9790f3a92","external_product_id":"6906711"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"81d0cba90e2c4c473ac010b36708b66c","external_product_id":"6907230"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"ba4731c19473dc8c46ecf11ac678d5c8","external_product_id":"6907832"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"e251348516dad748b3950356d744bfe0","external_product_id":"6907891"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"헤비아우터"},"input_fingerprint":"912c5dc771de7dfbd56a4b51456a844b","external_product_id":"6908583"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"0cb2c7aa1288ef899d57defcf20ef276","external_product_id":"6908818"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"48dda35c4297c45edbf79bf7bd322cea","external_product_id":"6908820"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"헤비아우터"},"input_fingerprint":"75cf2270064cc3b60234b4bb052d5a09","external_product_id":"6908905"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"긴소매티셔츠"},"input_fingerprint":"6bf2ae21e2de694c180ecd0ff2ff2caa","external_product_id":"6910253"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"0f527170eca17558865a783378bf7060","external_product_id":"6912863"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"dd74e8cc211da50281ed049d1b0151cd","external_product_id":"6927386"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반바지"},"input_fingerprint":"5036c0dbccba34336278c92a2532602b","external_product_id":"6928699"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"헤비아우터"},"input_fingerprint":"604bf852524c51dc9de62ca402ca527d","external_product_id":"6929142"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"헤비아우터"},"input_fingerprint":"5c2dbb93a41059acc29a6464cc60e4a7","external_product_id":"6929984"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼_래글런"},"input_fingerprint":"c252dba0078a63b99d5f4aeca9c210a3","external_product_id":"6933792"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"f0f5a768a61327c6c7329190f1a30202","external_product_id":"6939618"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"민소매"},"input_fingerprint":"de700a146543758749e679af27ac1cf9","external_product_id":"6941093"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"ee2f2dd52797095e8bd28d72edab9ca0","external_product_id":"6941805"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"반소매티셔츠"},"input_fingerprint":"c9c69557a962a7b0789770bd396b3e24","external_product_id":"6945858"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"바지"},"input_fingerprint":"bc7faac953fc321c540fd0b8eabe8fe0","external_product_id":"6948430"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"4deb3f4e6f615d4f5f60adc3ae4314a3","external_product_id":"6957088"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"c0085e7631490ad41107ea502ebf46cc","external_product_id":"6960215"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"셔츠"},"input_fingerprint":"50e565e76d58f34b723f9d3bd38bc0a6","external_product_id":"6961628"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"원피스"},"input_fingerprint":"d6b59a79e277a973cedf439b36a76e09","external_product_id":"6961646"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"f15bb614aad1357e9fd6a3580bcbdb6c","external_product_id":"6968252"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"헤비아우터"},"input_fingerprint":"dd4fb5b090b2bf6839faa371fcf86872","external_product_id":"6996910"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"점퍼"},"input_fingerprint":"02ee9b4785e0a65ddd93b9c8bb316bd7","external_product_id":"6998028"},{"source":"musinsa","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"size_type":"코트"},"input_fingerprint":"27f0fd5e892ef5498dc168e1eb6f5b87","external_product_id":"865862"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"엄브렐라/우산"},"input_fingerprint":"4b2b711e3c7f4105376a762d52ac94db","external_product_id":"E433776"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"슬리퍼/신발"},"input_fingerprint":"2b7e2c3e741c9cfa23d8cf362cb12035","external_product_id":"E461767"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"토트백"},"input_fingerprint":"e4668c1a39772af594320def0a0dfdca","external_product_id":"E462191"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"d5f45aef13387c0a5387187aa0737714","external_product_id":"E463729"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"b59bb79d35547eb9f632d64316db1346","external_product_id":"E463730"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"714c981a2defa50b221747a32274fced","external_product_id":"E470008"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"7d317094bbba0edd3a9686f5bb86d91f","external_product_id":"E478306"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"숄더백"},"input_fingerprint":"6407657351b407b19a26db9a43aef523","external_product_id":"E481610"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"1b22a4284072c3ceda60ac71e0ff7fe7","external_product_id":"E481623"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"c876e9d04acbeaa08032a37ef75c7f4d","external_product_id":"E481626"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"50fe2cb8683654682cadbb075419243f","external_product_id":"E481636"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"060bb5ada9bac7530bdd8050ffe9fb7f","external_product_id":"E481637"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"6b387f462e5fbc92de9e1a4afc40e726","external_product_id":"E481638"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"6f8bf9fbcc5c6db68e605621676b94ad","external_product_id":"E481639"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"ff41da2f724cb0523ed5b48e9c7826cf","external_product_id":"E481640"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"ae79d7a093a4fdee4be02f5676560caf","external_product_id":"E481646"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"11928f1af8db913dddb81f9e36798d14","external_product_id":"E481648"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"018e42e85b53526f4c16e502a08266f6","external_product_id":"E481649"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"엄브렐라/우산"},"input_fingerprint":"a0a078e117b7c319bdd6edeb289ec843","external_product_id":"E482268"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"슈즈/신발"},"input_fingerprint":"d34957adf8704be2927c11eadd8570e0","external_product_id":"E482815"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"슈즈/신발"},"input_fingerprint":"508a20d66df30491c4d6b2c93f90589f","external_product_id":"E484330"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"토트백"},"input_fingerprint":"5af69a19da2033c804fb8d4298cc8835","external_product_id":"E484719"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"9eb510aa5376e1c599f54a455d8024fc","external_product_id":"E484783"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"a218502028b918010db0802de8737121","external_product_id":"E484932"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"69a0aa1dd7719b3d604a2ee47f775758","external_product_id":"E484934"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"a92203df5ca27e3af77973c5fa427403","external_product_id":"E484935"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"afeb343ad51e825fdfa8e1502442bafa","external_product_id":"E484937"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"선글라스"},"input_fingerprint":"81ab646c0d385ed61e16f80a66d249ca","external_product_id":"E485208"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"181709da8c136614876e7d50feefec19","external_product_id":"E485791"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"656192d95337b0c98ca2e03fbb477274","external_product_id":"E486184"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"b93784e6de7ae997140d253a666ad59e","external_product_id":"E486186"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"기타"},"input_fingerprint":"7fcd80bb27c5b272e26cbe51686020c4","external_product_id":"E486191"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"80823b202325ded843b4f038ca85de50","external_product_id":"E486194"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"078c2ebe062dea21b7e07c5253ced6bf","external_product_id":"E486196"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"접이식 우산"},"input_fingerprint":"4b2b711e3c7f4105376a762d52ac94db","external_product_id":"E486199"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"(24SS-)Scarfs, Shawls"},"input_fingerprint":"bbfe659e4b12f0bafc0bda567245b57b","external_product_id":"E486202"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"(24SS-)Scarfs, Shawls"},"input_fingerprint":"5509de7621c1b4acfd1afca0160608dc","external_product_id":"E486203"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"(24SS-)Gloves"},"input_fingerprint":"38c90556324c51c20fd3fbc692d09811","external_product_id":"E486205"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"181709da8c136614876e7d50feefec19","external_product_id":"E486675"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"cc9f8d69b228fd74f0d27f4f1335b48e","external_product_id":"E486755"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"스카프"},"input_fingerprint":"9b928dcff2c4cde7b550ee7dcb8f1f6f","external_product_id":"E486760"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"(24SS-)Gloves"},"input_fingerprint":"137d34f5d2c02912a515b006d83308bb","external_product_id":"E486764"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"벨트"},"input_fingerprint":"7d358dc1c5d9dc3b32068bf7f5c93deb","external_product_id":"E488047"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"백팩/배낭"},"input_fingerprint":"f7846da9a5e5f07ec3962d73ad3e3bc5","external_product_id":"E488858"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"숄더백"},"input_fingerprint":"c0335108f875a7950fe3d1ab27cdd1b6","external_product_id":"E488859"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"1e86f520207f715147467078f443fc7d","external_product_id":"E491142"},{"source":"uniqlo","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"product_type_kr":"캡/모자"},"input_fingerprint":"475cbd7dc23218c065bd10ac0966ec90","external_product_id":"E491143"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"78","family_name":"스포츠 재킷","subfamily_id":"12468","subfamily_name":"F. Cazadora","official_category_id":"2536906"},"input_fingerprint":"c02d550114dc9981747ee1d6fb40c83b","external_product_id":"545406831"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"77","family_name":"브레이저","subfamily_id":"348","subfamily_name":"B.BLAZER","official_category_id":"2417772"},"input_fingerprint":"2170dcdfa3edd76fdf61fb545960fd8a","external_product_id":"545427337"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"78","family_name":"스포츠 재킷","subfamily_id":"12468","subfamily_name":"F. Cazadora","official_category_id":"2536906"},"input_fingerprint":"6ea729c4e1c3bb06f98b70b0f1bb7d75","external_product_id":"545428239"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"78","family_name":"스포츠 재킷","subfamily_id":"349","subfamily_name":"B.SHORT-OUTWEAR","official_category_id":"2417772"},"input_fingerprint":"bd8e930e462b01bf6e14df0713db172f","external_product_id":"545439169"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"12099","subfamily_name":"L. PANT. PIJAMA","official_category_id":"2420795"},"input_fingerprint":"ff1d20ff1f1bc0cf68ba009fb7776ceb","external_product_id":"545473154"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"78","family_name":"스포츠 재킷","subfamily_id":"12468","subfamily_name":"F. Cazadora","official_category_id":"2536906"},"input_fingerprint":"4f7eb176feb04db20b28e8a4ebbfeb9a","external_product_id":"545483281"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"11442","subfamily_name":"C.CTAS FANTASI","official_category_id":"2420417"},"input_fingerprint":"67bd1e09ab4089f2e103d4c91e503dc3","external_product_id":"545892778"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"78","family_name":"스포츠 재킷","subfamily_id":"383","subfamily_name":"T.SHORT-OUTWEAR","official_category_id":"2417772"},"input_fingerprint":"166825774b17bfbae458212c1eb86ed5","external_product_id":"547003473"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"81","family_name":"가디건","subfamily_id":"11272","subfamily_name":"KNIT CARDIGAN","official_category_id":"2417772"},"input_fingerprint":"0198885d061f90d674c21c091ca95ff0","external_product_id":"547276687"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"344","subfamily_name":"B.PANTS","official_category_id":"2420795"},"input_fingerprint":"304cce0fe3270b0f34ab6fd42a23ecde","external_product_id":"548577264"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"12480","subfamily_name":"Camiseta M/L","official_category_id":"2432042"},"input_fingerprint":"09c2d49131d89502d7c1d42d7dd2770e","external_product_id":"550429724"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"76","family_name":"셔츠","subfamily_id":"12463","subfamily_name":"F. Camisería","official_category_id":"2431994"},"input_fingerprint":"3563e044319b4fa22d6b3016c6f202fd","external_product_id":"552163213"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"12480","subfamily_name":"Camiseta M/L","official_category_id":"2432042"},"input_fingerprint":"e2231706ef27042864cf76af3914503b","external_product_id":"552342201"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"12479","subfamily_name":"F. Camiseta","official_category_id":"2432042"},"input_fingerprint":"68bd00c532b333d425f538221ddb7852","external_product_id":"553028015"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"76","family_name":"셔츠","subfamily_id":"12463","subfamily_name":"F. Camisería","official_category_id":"2431994"},"input_fingerprint":"509c2f7e376b23c4122fae8f4729ba49","external_product_id":"554006103"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"78","family_name":"스포츠 재킷","subfamily_id":"12468","subfamily_name":"F. Cazadora","official_category_id":"2536906"},"input_fingerprint":"87fcee057dcc62523110a3db632697d5","external_product_id":"554764120"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"12480","subfamily_name":"Camiseta M/L","official_category_id":"2432042"},"input_fingerprint":"79d8684a64d58978e5e7e04fe9a37424","external_product_id":"555068780"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"12454","subfamily_name":"F. Pant Resto","official_category_id":"2432096"},"input_fingerprint":"951939cbccdda1a32aefc54f4240a1ea","external_product_id":"555161842"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"12454","subfamily_name":"F. Pant Resto","official_category_id":"2432096"},"input_fingerprint":"951939cbccdda1a32aefc54f4240a1ea","external_product_id":"555162424"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"12459","subfamily_name":"Sastrería Pant.","official_category_id":"2432096"},"input_fingerprint":"425db0047d66c561b7ce12c3bff19a45","external_product_id":"556139700"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"11450","subfamily_name":"C.CTAS POSICIO","official_category_id":"2420417"},"input_fingerprint":"1c343f48463218d6f3ddbe57b60957bd","external_product_id":"557446393"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"74","family_name":"드레스","subfamily_id":"336","subfamily_name":"W.DRESS","official_category_id":"2420896"},"input_fingerprint":"21f9d57bd2ec5a1ac024564b9369de8d","external_product_id":"558215502"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"11450","subfamily_name":"C.CTAS POSICIO","official_category_id":"2420417"},"input_fingerprint":"73ab8c8bd29444ff02f71cd4830cc12c","external_product_id":"558577924"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"344","subfamily_name":"B.PANTS","official_category_id":"2420795"},"input_fingerprint":"c08a317fbf2e3cf5025b2aa929b7e99f","external_product_id":"560347128"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"83","family_name":"티셔츠","subfamily_id":"11442","subfamily_name":"C.CTAS FANTASI","official_category_id":"2420417"},"input_fingerprint":"f30a156b2ba4f6c40f5ef2aacc4ea369","external_product_id":"560742370"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"12454","subfamily_name":"F. Pant Resto","official_category_id":"2432096"},"input_fingerprint":"c8dc92e10e01054d6daab31b6cf7cc93","external_product_id":"561264931"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"76","family_name":"셔츠","subfamily_id":"12463","subfamily_name":"F. Camisería","official_category_id":"2431994"},"input_fingerprint":"029b9ce926e40a674792e943da3308f1","external_product_id":"561568002"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"74","family_name":"드레스","subfamily_id":"346","subfamily_name":"B.DRESS","official_category_id":"2420896"},"input_fingerprint":"749452eec183ae6edf21424040fde017","external_product_id":"561583709"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"73","family_name":"바지","subfamily_id":"11453","subfamily_name":"C.PTON-LEGGING","official_category_id":"2420795"},"input_fingerprint":"6d3ebd350574f07256d8727f5258c819","external_product_id":"561610369"},{"source":"zara","evidence":"production_select_only_snapshot_2026-08-26","record_type":"product_structured_fact","structured_facts":{"family_id":"76","family_name":"셔츠","subfamily_id":"12463","subfamily_name":"F. Camisería","official_category_id":"2431994"},"input_fingerprint":"8dc0c77c9fe9d7c82d13edcb9ae9c685","external_product_id":"562814885"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"긴소매티셔츠","product_count":11,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"민소매","product_count":9,"verdict":"CONFLICTING","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"바지","product_count":34,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"반바지","product_count":11,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"반소매_래글런","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"반소매티셔츠","product_count":22,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"셔츠","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"스커트","product_count":13,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"원피스","product_count":26,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"점퍼","product_count":21,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"점퍼_래글런","product_count":5,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"코트","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"musinsa","discriminator_key":"size_type","discriminator_value":"헤비아우터","product_count":5,"verdict":"SUPPORTING_ONLY","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"(24SS-)Gloves","product_count":2,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"(24SS-)Scarfs, Shawls","product_count":2,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"기타","product_count":1,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"백팩/배낭","product_count":1,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"벨트","product_count":9,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"선글라스","product_count":13,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"숄더백","product_count":2,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"슈즈/신발","product_count":2,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"스카프","product_count":1,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"슬리퍼/신발","product_count":1,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"엄브렐라/우산","product_count":2,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"접이식 우산","product_count":1,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"캡/모자","product_count":8,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"uniqlo","discriminator_key":"product_type_kr","discriminator_value":"토트백","product_count":2,"verdict":"EXCLUSION_SIGNAL","evidence_basis":"full current stored-value cohort review; no product-name-only canonical conversion"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"73","product_count":8,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"74","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"76","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"77","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"78","product_count":6,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"81","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_id","discriminator_value":"83","product_count":8,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"가디건","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"드레스","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"바지","product_count":8,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"브레이저","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"셔츠","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"스포츠 재킷","product_count":6,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"family_name","discriminator_value":"티셔츠","product_count":8,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2417772","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2420417","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2420795","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2420896","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2431994","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2432042","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2432096","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"official_category_id","discriminator_value":"2536906","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"11272","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"11442","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"11450","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"11453","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12099","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12454","product_count":3,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12459","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12463","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12468","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12479","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"12480","product_count":3,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"336","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"344","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"346","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"348","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"349","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_id","discriminator_value":"383","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"B.BLAZER","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"B.DRESS","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"B.PANTS","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"B.SHORT-OUTWEAR","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"C.CTAS FANTASI","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"C.CTAS POSICIO","product_count":2,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"C.PTON-LEGGING","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"Camiseta M/L","product_count":3,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"F. Camisería","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"F. Camiseta","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"F. Cazadora","product_count":4,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"F. Pant Resto","product_count":3,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"KNIT CARDIGAN","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"L. PANT. PIJAMA","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"Sastrería Pant.","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"T.SHORT-OUTWEAR","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_value_audit","source":"zara","discriminator_key":"subfamily_name","discriminator_value":"W.DRESS","product_count":1,"verdict":"SUPPORTING_ONLY","evidence_basis":"duplicates stored official category path/code"},{"record_type":"structured_discriminator_rule","rule_id":"exclude-set","id":"exclude-set","source":"*","key":"product_structure","value":"set","outcome":"not_comparable","reason":"set_product","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"exclude-non-apparel","id":"exclude-non-apparel","source":"*","key":"product_scope","value":"non_apparel","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-01","id":"uniqlo-accessory-01","source":"uniqlo","key":"product_type_kr","value":"(24SS-)Gloves","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-02","id":"uniqlo-accessory-02","source":"uniqlo","key":"product_type_kr","value":"(24SS-)Scarfs, Shawls","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-03","id":"uniqlo-accessory-03","source":"uniqlo","key":"product_type_kr","value":"기타","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-04","id":"uniqlo-accessory-04","source":"uniqlo","key":"product_type_kr","value":"백팩/배낭","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-05","id":"uniqlo-accessory-05","source":"uniqlo","key":"product_type_kr","value":"벨트","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-06","id":"uniqlo-accessory-06","source":"uniqlo","key":"product_type_kr","value":"선글라스","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-07","id":"uniqlo-accessory-07","source":"uniqlo","key":"product_type_kr","value":"숄더백","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-08","id":"uniqlo-accessory-08","source":"uniqlo","key":"product_type_kr","value":"슈즈/신발","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-09","id":"uniqlo-accessory-09","source":"uniqlo","key":"product_type_kr","value":"스카프","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-10","id":"uniqlo-accessory-10","source":"uniqlo","key":"product_type_kr","value":"슬리퍼/신발","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-11","id":"uniqlo-accessory-11","source":"uniqlo","key":"product_type_kr","value":"엄브렐라/우산","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-12","id":"uniqlo-accessory-12","source":"uniqlo","key":"product_type_kr","value":"접이식 우산","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-13","id":"uniqlo-accessory-13","source":"uniqlo","key":"product_type_kr","value":"캡/모자","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"uniqlo-accessory-14","id":"uniqlo-accessory-14","source":"uniqlo","key":"product_type_kr","value":"토트백","outcome":"not_comparable","reason":"non_apparel_or_accessory","authority_status":"verified","resolution_scope":"excluded","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"musinsa-knit-long","id":"musinsa-knit-long","source":"musinsa","key":"size_type","value":"긴소매티셔츠","external_category_id":"001006","tuple":["tops","knit_sweater","knit_sweater","knit_sweater","long_sleeve",null],"authority_status":"verified","resolution_scope":"structured_product","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"musinsa-polo-short","id":"musinsa-polo-short","source":"musinsa","key":"size_type","value":"반소매티셔츠","external_category_id":"001003","tuple":["tops","polo_shirt","polo_shirt","polo_shirt","short_sleeve",null],"authority_status":"verified","resolution_scope":"structured_product","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"musinsa-cardigan-long","id":"musinsa-cardigan-long","source":"musinsa","key":"size_type","value":"긴소매티셔츠","external_category_id":"002020","tuple":["tops","cardigan","cardigan","cardigan","long_sleeve",null],"authority_status":"verified","resolution_scope":"structured_product","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"musinsa-anorak-long","id":"musinsa-anorak-long","source":"musinsa","key":"size_type","value":"긴소매티셔츠","external_category_id":"002019","tuple":["outerwear","anorak","anorak","anorak","long_sleeve",null],"authority_status":"verified","resolution_scope":"structured_product","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"structured_discriminator_rule","rule_id":"musinsa-fleece-long","id":"musinsa-fleece-long","source":"musinsa","key":"size_type","value":"긴소매티셔츠","external_category_id":"002023","tuple":["outerwear","fleece","fleece_jacket","fleece_jacket","long_sleeve",null],"authority_status":"verified","resolution_scope":"structured_product","runtime_eligible":true,"evidence_basis":"independent cohort semantics + exact source/category scope; raw product name is not authority"},{"record_type":"mapping_disposition","id":"musinsa-mixed-sleeveless","source":"musinsa","external_category_ids":["001011","017016003"],"expected_rows":7,"disposition":"PRODUCT_REQUIRED","reason":"mixed tank_top/sleeveless_tshirt/bodysuit_top"},{"record_type":"mapping_disposition","id":"uniqlo-sleeveless-tshirt","source":"uniqlo","external_category_ids":["58145","58397"],"expected_rows":2,"disposition":"CATEGORY_DIRECT","tuple":["tops","sleeveless","sleeveless_tshirt","sleeveless_tshirt","sleeveless",null]},{"record_type":"mapping_disposition","id":"invalid-direct-puffer","source":"musinsa","external_category_ids":["017018015"],"expected_rows":1,"disposition":"CATEGORY_DIRECT","tuple":["outerwear","padding","puffer_jacket","puffer_jacket","long_sleeve","medium_body"]},{"record_type":"mapping_disposition","id":"invalid-direct-leggings","source":"uniqlo","external_category_ids":["100100"],"expected_rows":1,"disposition":"CATEGORY_DIRECT","tuple":["leggings","long_leggings","leggings","leggings","long_length",null]},{"record_type":"mapping_disposition","id":"invalid-direct-base-layer","source":"uniqlo","external_category_ids":["141498","141499","58274","58275","58635","58636"],"expected_rows":6,"disposition":"CATEGORY_DIRECT","tuple":["tops","base_layer_top","base_layer_top","base_layer_top","sleeveless",null]},{"record_type":"mapping_disposition","id":"invalid-direct-sweatshirt","source":"uniqlo","external_category_ids":["58154","58401","58407"],"expected_rows":3,"disposition":"CATEGORY_DIRECT","tuple":["tops","sweatshirt","sweatshirt","sweatshirt","long_sleeve",null]},{"record_type":"mapping_disposition","id":"invalid-product-required-cardigan","source":"*","external_category_ids":["002020","128382","128384","128427","135281","136609","95375"],"expected_rows":7,"disposition":"PRODUCT_REQUIRED","reason":"cardigan sleeve axis absent"},{"record_type":"mapping_disposition","id":"invalid-product-required-knit","source":"uniqlo","external_category_ids":["116336","95370","95376","95378","95379","95405"],"expected_rows":6,"disposition":"PRODUCT_REQUIRED","reason":"knit sleeve axis absent"},{"record_type":"mapping_disposition","id":"remaining-invalid-revoked","source":"*","expected_rows":335,"disposition":"REVOKED","reason":"no verified replacement; fail closed"},{"record_type":"mapping_disposition","id":"legacy-existing-nonauthoritative-revoked","source":"*","expected_rows":2100,"disposition":"REVOKED","reason":"legacy/rejected/unsupported mapping is audit evidence only; explicit non-eligible scope"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"바지 > 슈트 팬츠 > 슬랙스","tuple":["bottoms","slacks_trousers","slacks_trousers","standard_pants","long_length",null],"sample_count":11,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"아우터 > 슈트 > 블레이저 재킷","tuple":["outerwear","blazer","blazer","blazer","long_sleeve",null],"sample_count":9,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"원피스 > 스커트 > 미니원피스","tuple":["dresses","one_piece","dress","dress","not_applicable","short_body"],"sample_count":6,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"원피스 > 스커트 > 맥시원피스","tuple":["dresses","one_piece","dress","dress","not_applicable","long_body"],"sample_count":3,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"원피스 > 스커트 > 미디원피스","tuple":["dresses","one_piece","dress","dress","not_applicable","medium_body"],"sample_count":3,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"원피스 > 스커트 > 미니스커트","tuple":["skirts","skirt","skirt","skirt","not_applicable","short_body"],"sample_count":3,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"원피스 > 스커트 > 미디스커트","tuple":["skirts","skirt","skirt","skirt","not_applicable","medium_body"],"sample_count":2,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"스포츠 > 레저 > 상의 > 반소매 티셔츠","tuple":["tops","short_sleeve","tshirt","tshirt","short_sleeve",null],"sample_count":3,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"musinsa","normalized_path":"스포츠 > 레저 > 하의 > 숏팬츠","tuple":["bottoms","shorts","shorts","standard_pants","short_length",null],"sample_count":1,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"파자마 & 홈웨어 > 라운지 팬츠 > 이지 팬츠","tuple":["homewear","homewear_bottom","homewear_bottom","homewear_bottom","long_length",null],"sample_count":5,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 언더웨어 > 코튼 트렁크","tuple":["underwear","men_trunks","men_trunks","men_trunks","not_applicable",null],"sample_count":10,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_path_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 언더웨어 > 코튼 브리프","tuple":["underwear","men_briefs","men_briefs","men_briefs","not_applicable",null],"sample_count":10,"authority_status":"verified","auto_eligible":true,"evidence_basis":"complete normalized retailer taxonomy path + independently consistent cohort"},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 레귤러 삭스","sample_count":23,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 히트텍 삭스","sample_count":18,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 쇼트 삭스","sample_count":10,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 베리 쇼트 삭스","sample_count":8,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 하프 삭스","sample_count":6,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 히트텍 > 양말","sample_count":6,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 레귤러삭스","sample_count":5,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 하이 삭스","sample_count":5,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 쇼트삭스","sample_count":4,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"영유아(6개월~5세) > 양말 > 레귤러삭스","sample_count":2,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 컬러 삭스","sample_count":2,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"스포츠 유틸리티 웨어 > 이너웨어 > 양말","sample_count":1,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"신생아(0개월~2세) > 양말 > 레귤러삭스","sample_count":1,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"신생아(0개월~2세) > 양말 > 쇼트삭스","sample_count":1,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_exclusion_profile","policy_version":"db-classifier-2026-08-26-final","source":"uniqlo","normalized_path":"이너웨어 > 양말 > 그 외","sample_count":1,"reason_code":"non_apparel_or_accessory","authority_status":"verified","auto_eligible":true},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E481731","product_name":"밀라노립풀집가디건","source_category_path":"니트 & 가디건 > 니트 > 긴팔 니트","input_fingerprint":"6ed85a61eecbfa509a45333f32c4fbbc","tuple":["tops","cardigan","cardigan","cardigan","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy canonical cardigan translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E485307","product_name":"메리노블렌드폴로가디건(반팔)","source_category_path":"니트 & 가디건 > 니트 > 반팔 니트","input_fingerprint":"cfbafd75d1f2bffe16134f87db06699d","tuple":["tops","cardigan","cardigan","cardigan","short_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy canonical cardigan translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E488333","product_name":"메리노블렌드폴로가디건(반팔)아가일","source_category_path":"니트 & 가디건 > 니트 > 반팔 니트","input_fingerprint":"f44d38d5e940575a2298b82522935328","tuple":["tops","cardigan","cardigan","cardigan","short_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy canonical cardigan translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E483443","product_name":"KIDS드라이스웨트풀집파카(무지)","source_category_path":"티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트풀집","input_fingerprint":"ac32bff990795ea8922aa5835a8430f7","tuple":["tops","zip_hoodie","zip_hoodie","zip_hoodie","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"verified full-zip hoodie semantic translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E485735","product_name":"스웨트오버사이즈풀집파카","source_category_path":"티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드","input_fingerprint":"c76e88de4d48fc8b0099fa2d2e82a291","tuple":["tops","zip_hoodie","zip_hoodie","zip_hoodie","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"verified full-zip hoodie semantic translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E486119","product_name":"스웨트풀집파카","source_category_path":"티셔츠 & 스웨트셔츠 & UT > 스웨트셔츠 & 후드집업 > 후드","input_fingerprint":"be59b269ebefab914244c8de17149bda","tuple":["tops","zip_hoodie","zip_hoodie","zip_hoodie","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"verified full-zip hoodie semantic translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E486703","product_name":"GU퍼프스웨트풀집후디","source_category_path":"GU > 상의 > 스웨트","input_fingerprint":"4e257ea4d296097b483ac9d89555c76e","tuple":["tops","zip_hoodie","zip_hoodie","zip_hoodie","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"verified full-zip hoodie semantic translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E486706","product_name":"GU루프얀풀집후디","source_category_path":"GU > 상의 > 스웨트","input_fingerprint":"6f1b30a5d735fb782bf3ee253d15ab05","tuple":["tops","zip_hoodie","zip_hoodie","zip_hoodie","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"verified full-zip hoodie semantic translation","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E486696","product_name":"GU캐미솔튜닉","source_category_path":"셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > GU","input_fingerprint":"6589c4688500bb05b54f92d822c6d4b3","tuple":["tops","sleeveless","tank_top","tank_top","sleeveless",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"independent camisole tunic adjudication","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"musinsa","external_product_id":"4989733","product_name":"링클 시어서커 체크 반팔 셔츠 [차콜]","source_category_path":"상의 > 셔츠 > 블라우스","input_fingerprint":"5c025cdd8fbd18bc5a37cea2587616e6","tuple":["tops","shirt_blouse","shirt_blouse","shirt_blouse","short_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy shirt vocabulary translated by path + independent adjudication","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"musinsa","external_product_id":"6843879","product_name":"오픈칼라 슬림핏 반팔 셔츠  스카이 블루","source_category_path":"상의 > 셔츠/블라우스","input_fingerprint":"f7d12a7da025533e5cc7ebff4a6e5c96","tuple":["tops","shirt_blouse","shirt_blouse","shirt_blouse","short_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy shirt vocabulary translated by path + independent adjudication","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E475053","product_name":"스무드코튼크루넥스웨터","source_category_path":"니트 & 가디건 > 니트 > 긴팔 니트","input_fingerprint":"c7b7847b2dd31324c4064f792bb6d311","tuple":["tops","knit_sweater","knit_sweater","knit_sweater","long_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy knit vocabulary translated by complete sleeve path","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E481004","product_name":"워셔블밀라노립니트T(반팔)","source_category_path":"니트 & 가디건 > 니트 > 반팔 니트","input_fingerprint":"9b5c4a03281c16e4d59f664044a6bdb7","tuple":["tops","knit_sweater","knit_sweater","knit_sweater","short_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy knit vocabulary translated by complete sleeve path","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"verified_product_decision_override","source":"uniqlo","external_product_id":"E482328","product_name":"워셔블니트스키퍼폴로스웨터(반팔)","source_category_path":"니트 & 가디건 > 니트 > 반팔 니트","input_fingerprint":"1bd5d22e7bcb263ec9dc347d6f89176c","tuple":["tops","knit_sweater","knit_sweater","knit_sweater","short_sleeve",null],"authority_status":"verified","requires_user_confirmation":false,"decision_version":"classification-db-final-closure-2026-08-26-v1","reason":"legacy knit vocabulary translated by complete sleeve path","evidence_basis":["independent adjudication","active canonical vocabulary","no product-name-only inference"]},{"record_type":"legacy_vocabulary_unresolved","source":"uniqlo","external_product_id":"E450535","verdict":"PRODUCT_TRUTH_INSUFFICIENT","reason":"crewneck knit path lacks verified sleeve axis; no automatic translation"},{"record_type":"legacy_vocabulary_unresolved","source":"uniqlo","external_product_id":"E485318","verdict":"PRODUCT_TRUTH_INSUFFICIENT","reason":"crewneck knit path lacks verified sleeve axis; no automatic translation"},{"record_type":"contract_change","kind":"taxonomy","summary":"add sleeveless_tshirt, dress, homewear single/set, explicit underwear comparison families; move zip_hoodie major to tops; reuse existing pants/denim/chino/slacks canonical codes"},{"record_type":"contract_change","kind":"comparison","summary":"explicit unordered ALLOW/BLOCK matrix for every active comparison group; self only plus verified sweatshirt↔hoodie cross-family allow; base-layer/tshirt and tops/underwear blocked"},{"record_type":"contract_change","kind":"measurement","summary":"add active policies for skirts, leggings, dresses, homewear and underwear without changing MeasurementComparisonEngine scoring"},{"record_type":"contract_change","kind":"legacy_authority","summary":"verified complete exact wins; legacy complete is audit-only and may flag conflict; legacy incomplete/invalid never blocks verified authority"},{"record_type":"contract_change","kind":"fallback","summary":"verified complete path precedes verified complete name; raw name keywords and unverified profiles never confirm"},{"record_type":"synthetic_fixture_contract","fixture_id":"known-pure-category","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"product-required-structured","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"product-required-missing","expected_status":"review_required"},{"record_type":"synthetic_fixture_contract","fixture_id":"mixed-sleeveless-tank","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"mixed-sleeveless-tshirt","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"set-in-tshirt","expected_status":"not_comparable"},{"record_type":"synthetic_fixture_contract","fixture_id":"dress","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"skirt","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"pants","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"denim","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"shorts","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"cardigan","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"knit-sweater","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"sweatshirt","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"hoodie","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"jacket","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"coat","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"blazer","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"puffer-jacket","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"windbreaker","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"base-layer-top","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"true-underwear","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"homewear-single","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"homewear-set","expected_status":"not_comparable"},{"record_type":"synthetic_fixture_contract","fixture_id":"non-apparel","expected_status":"not_comparable"},{"record_type":"synthetic_fixture_contract","fixture_id":"verified-path","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"verified-name-last-resort","expected_status":"confirmed"},{"record_type":"synthetic_fixture_contract","fixture_id":"unknown-insufficient","expected_status":"review_required"}]$manifest$::jsonb
  ) item(value)
  union all
  select '{"record_type":"synthetic_fixture_contract","fixture_id":"normal-variant-not-set","expected_status":"confirmed"}'::jsonb
$function$;

-- Canonical detail vocabulary additions. Existing equivalent pants, denim,
-- chino, slacks and shirt/blouse codes remain the single canonical codes.
with wanted(parent_code, code, display_name_ko, sort_order) as (
  values
    ('tops', 'sleeveless_tshirt', '민소매 티셔츠', 25),
    ('tops', 'cardigan', '가디건', 26),
    ('tops', 'zip_hoodie', '후드집업', 27),
    ('homewear', 'homewear_top', '홈웨어 상의', 10),
    ('homewear', 'homewear_bottom', '홈웨어 하의', 20),
    ('homewear', 'homewear_set', '홈웨어 세트', 90)
)
insert into public.app_categories (
  parent_id, code, display_name_ko, depth, sort_order, is_active, metadata
)
select parent.id, wanted.code, wanted.display_name_ko, 1,
  wanted.sort_order, true,
  jsonb_build_object(
    'closure_version', 'classification-db-final-2026-08-26',
    'semantic_authority', 'owner_policy'
  )
from wanted
join public.app_categories parent
  on parent.parent_id is null
 and parent.code = wanted.parent_code
on conflict (parent_id, code) where parent_id is not null do update set
  display_name_ko = excluded.display_name_ko,
  is_active = true,
  metadata = public.app_categories.metadata || excluded.metadata,
  updated_at = now();

insert into public.comparison_groups (
  code, display_name_ko, major_category_code, allows_cross_type,
  is_auto_comparable, sort_order, is_active, metadata
) values
  ('sleeveless_tshirt', '민소매 티셔츠', 'tops', false, true, 31, true,
    '{"closure":"2026-08-26"}'),
  ('jacket', '재킷', 'outerwear', false, true, 32, true,
    '{"closure":"2026-08-26"}'),
  ('dress', '원피스', 'dresses', false, true, 33, true,
    '{"closure":"2026-08-26"}'),
  ('homewear_top', '홈웨어 상의', 'homewear', false, true, 34, true,
    '{"closure":"2026-08-26"}'),
  ('homewear_bottom', '홈웨어 하의', 'homewear', false, true, 35, true,
    '{"closure":"2026-08-26"}'),
  ('homewear_set', '홈웨어 세트', 'homewear', false, false, 36, true,
    '{"closure":"2026-08-26","excluded":true}'),
  ('men_briefs', '남성 브리프', 'underwear', false, true, 37, true,
    '{"closure":"2026-08-26"}'),
  ('men_trunks', '남성 트렁크', 'underwear', false, true, 38, true,
    '{"closure":"2026-08-26"}'),
  ('men_undershirt', '남성 런닝', 'underwear', false, true, 39, true,
    '{"closure":"2026-08-26"}'),
  ('women_bra', '브라', 'underwear', false, true, 40, true,
    '{"closure":"2026-08-26"}'),
  ('women_camisole', '캐미솔', 'underwear', false, true, 41, true,
    '{"closure":"2026-08-26"}'),
  ('women_panty', '여성 팬티', 'underwear', false, true, 42, true,
    '{"closure":"2026-08-26"}'),
  ('women_slip', '슬립', 'underwear', false, true, 43, true,
    '{"closure":"2026-08-26"}'),
  ('generic_underwear', '일반 속옷', 'underwear', false, false, 44, true,
    '{"closure":"2026-08-26","generic_auto_comparison_blocked":true}')
on conflict (code) do update set
  display_name_ko = excluded.display_name_ko,
  major_category_code = excluded.major_category_code,
  allows_cross_type = excluded.allows_cross_type,
  is_auto_comparable = excluded.is_auto_comparable,
  is_active = true,
  metadata = public.comparison_groups.metadata || excluded.metadata,
  updated_at = now();

-- Owner policy: a zip hoodie is a tops wearing role, not outerwear.
update public.comparison_groups
set major_category_code = 'tops',
    metadata = metadata || '{"closure_translation":"outerwear_to_tops"}',
    updated_at = now()
where code = 'zip_hoodie';

insert into public.garment_types (
  code, major_category_code, display_name_ko, comparison_group_code,
  requires_sleeve_class, requires_pants_length, requires_body_length,
  is_active, sort_order, metadata
) values
  ('sleeveless_tshirt', 'tops', '민소매 티셔츠', 'sleeveless_tshirt', true, false, false, true, 50, '{"closure":"2026-08-26"}'),
  ('jacket', 'outerwear', '재킷', 'jacket', true, false, false, true, 51, '{"closure":"2026-08-26"}'),
  ('dress', 'dresses', '원피스', 'dress', false, false, true, true, 52, '{"closure":"2026-08-26"}'),
  ('shorts', 'bottoms', '반바지', 'standard_pants', false, true, false, true, 53, '{"closure":"2026-08-26"}'),
  ('homewear_top', 'homewear', '홈웨어 상의', 'homewear_top', true, false, false, true, 54, '{"closure":"2026-08-26"}'),
  ('homewear_bottom', 'homewear', '홈웨어 하의', 'homewear_bottom', false, true, false, true, 55, '{"closure":"2026-08-26"}'),
  ('homewear_set', 'homewear', '홈웨어 세트', 'homewear_set', false, false, false, true, 56, '{"closure":"2026-08-26","excluded":true}'),
  ('men_briefs', 'underwear', '남성 브리프', 'men_briefs', false, false, false, true, 57, '{"closure":"2026-08-26"}'),
  ('men_trunks', 'underwear', '남성 트렁크', 'men_trunks', false, false, false, true, 58, '{"closure":"2026-08-26"}'),
  ('men_undershirt', 'underwear', '남성 런닝', 'men_undershirt', true, false, false, true, 59, '{"closure":"2026-08-26"}'),
  ('women_bra', 'underwear', '브라', 'women_bra', false, false, false, true, 60, '{"closure":"2026-08-26"}'),
  ('women_camisole', 'underwear', '캐미솔', 'women_camisole', true, false, false, true, 61, '{"closure":"2026-08-26"}'),
  ('women_panty', 'underwear', '여성 팬티', 'women_panty', false, false, false, true, 62, '{"closure":"2026-08-26"}'),
  ('women_slip', 'underwear', '슬립', 'women_slip', false, false, true, true, 63, '{"closure":"2026-08-26"}'),
  ('generic_underwear', 'underwear', '일반 속옷', 'generic_underwear', false, false, false, true, 64, '{"closure":"2026-08-26","generic_auto_comparison_blocked":true}')
on conflict (code) do update set
  major_category_code = excluded.major_category_code,
  display_name_ko = excluded.display_name_ko,
  comparison_group_code = excluded.comparison_group_code,
  requires_sleeve_class = excluded.requires_sleeve_class,
  requires_pants_length = excluded.requires_pants_length,
  requires_body_length = excluded.requires_body_length,
  is_active = true,
  metadata = public.garment_types.metadata || excluded.metadata,
  updated_at = now();

update public.garment_types
set major_category_code = 'tops',
    metadata = metadata || '{"closure_translation":"outerwear_to_tops"}',
    updated_at = now()
where code = 'zip_hoodie';

-- Every active comparison group has one explicit policy. Non-auto groups are
-- still represented but never become automatic candidates.
with wanted(
  group_code, required_group, cross_type_mode, min_dimensions
) as (
  values
    ('sleeveless_tshirt','upper_core','same_type_only',2),
    ('jacket','outerwear_chest','same_type_only',2),
    ('dress','dress_core','same_type_only',2),
    ('homewear_top','upper_core','same_type_only',2),
    ('homewear_bottom','bottom_core','same_type_only',2),
    ('homewear_set',null,'same_type_only',2),
    ('men_briefs','underwear_lower','same_type_only',2),
    ('men_trunks','underwear_lower','same_type_only',2),
    ('men_undershirt','underwear_upper','same_type_only',2),
    ('women_bra','underwear_upper','same_type_only',2),
    ('women_camisole','underwear_upper','same_type_only',2),
    ('women_panty','underwear_lower','same_type_only',2),
    ('women_slip','underwear_upper','same_type_only',2),
    ('generic_underwear',null,'same_type_only',2)
)
insert into public.comparison_policies (
  code, comparison_group_code, cross_type_mode, reference_priority_mode,
  min_comparable_dimensions, required_measurement_group_code,
  policy_version, is_active, evidence_note
)
select wanted.group_code || '_v1', wanted.group_code,
  wanted.cross_type_mode, 'closest', wanted.min_dimensions,
  wanted.required_group, 'v1', true,
  'DB classification closure 2026-08-26; explicit group policy'
from wanted
on conflict (comparison_group_code) do update set
  cross_type_mode = excluded.cross_type_mode,
  reference_priority_mode = excluded.reference_priority_mode,
  min_comparable_dimensions = excluded.min_comparable_dimensions,
  required_measurement_group_code = excluded.required_measurement_group_code,
  policy_version = 'v1',
  is_active = true,
  evidence_note = excluded.evidence_note,
  updated_at = now();

update public.comparison_policies
set required_measurement_group_code = 'upper_core',
    cross_type_mode = 'same_type_only',
    evidence_note =
      'DB classification closure 2026-08-26; zip hoodie is tops',
    updated_at = now()
where comparison_group_code = 'zip_hoodie';

update public.comparison_policies
set required_measurement_group_code = 'skirt_core',
    updated_at = now()
where comparison_group_code = 'skirt';

insert into public.measurement_items (
  canonical_key, display_name, unit, value_type, aliases, description,
  is_active
) values
  ('under_bust_width', '밑가슴단면', 'cm', 'number', array['밑가슴 단면'], 'Under-bust flat width', true),
  ('under_bust_circumference', '밑가슴둘레', 'cm', 'number', array['밑가슴 둘레'], 'Under-bust circumference', true)
on conflict (canonical_key) do update set
  display_name = excluded.display_name,
  aliases = excluded.aliases,
  description = excluded.description,
  is_active = true,
  updated_at = now();

with wanted(
  category_code, measurement_key, dimension_code, weight, is_primary,
  required_group_code, required_group_min, display_order
) as (
  values
    ('skirts','waist_width','waist',1.4,true,'skirt_core',2,1),
    ('skirts','waist_circumference','waist',1.4,true,'skirt_core',2,2),
    ('skirts','hip_width','hip',1.2,true,'skirt_core',2,3),
    ('skirts','hip_circumference','hip',1.2,true,'skirt_core',2,4),
    ('skirts','total_length','length',1.0,false,null,null,5),
    ('skirts','hem_width','hem',0.6,false,null,null,6),
    ('leggings','waist_width','waist',1.4,true,'bottom_core',2,1),
    ('leggings','waist_circumference','waist',1.4,true,'bottom_core',2,2),
    ('leggings','hip_width','hip',1.2,true,'bottom_core',2,3),
    ('leggings','hip_circumference','hip',1.2,true,'bottom_core',2,4),
    ('leggings','thigh_width','thigh',0.9,false,null,null,5),
    ('leggings','thigh_circumference','thigh',0.9,false,null,null,6),
    ('leggings','total_length','length',1.0,false,null,null,7),
    ('dresses','chest_width','chest',1.4,true,'dress_core',2,1),
    ('dresses','chest_circumference','chest',1.4,true,'dress_core',2,2),
    ('dresses','waist_width','waist',1.2,true,'dress_core',2,3),
    ('dresses','waist_circumference','waist',1.2,true,'dress_core',2,4),
    ('dresses','hip_width','hip',1.0,false,null,null,5),
    ('dresses','hip_circumference','hip',1.0,false,null,null,6),
    ('dresses','total_length','length',1.0,false,null,null,7),
    ('homewear','shoulder_width','shoulder',1.2,true,'upper_core',1,1),
    ('homewear','chest_width','chest',1.4,true,'upper_core',1,2),
    ('homewear','chest_circumference','chest',1.4,true,'upper_core',1,3),
    ('homewear','waist_width','waist',1.4,true,'bottom_core',2,4),
    ('homewear','waist_circumference','waist',1.4,true,'bottom_core',2,5),
    ('homewear','hip_width','hip',1.2,true,'bottom_core',2,6),
    ('homewear','hip_circumference','hip',1.2,true,'bottom_core',2,7),
    ('homewear','total_length','length',1.0,false,null,null,8),
    ('homewear','sleeve_length','sleeve',0.8,false,null,null,9),
    ('underwear','chest_width','chest',1.3,true,'underwear_upper',1,1),
    ('underwear','chest_circumference','chest',1.3,true,'underwear_upper',1,2),
    ('underwear','under_bust_width','under_bust',1.3,true,'underwear_upper',1,3),
    ('underwear','under_bust_circumference','under_bust',1.3,true,'underwear_upper',1,4),
    ('underwear','waist_width','waist',1.3,true,'underwear_lower',2,5),
    ('underwear','waist_circumference','waist',1.3,true,'underwear_lower',2,6),
    ('underwear','hip_width','hip',1.2,true,'underwear_lower',2,7),
    ('underwear','hip_circumference','hip',1.2,true,'underwear_lower',2,8),
    ('underwear','total_length','length',0.7,false,null,null,9)
)
insert into public.app_category_measurement_policies (
  app_category_id, measurement_item_id, dimension_code, weight,
  is_primary, is_comparable, cross_source_mode, required_group_code,
  required_group_min_dimensions, display_order, selection_priority,
  policy_version, evidence_note, is_active
)
select category.id, item.id, wanted.dimension_code, wanted.weight,
  wanted.is_primary, true, 'compatible_basis', wanted.required_group_code,
  wanted.required_group_min, wanted.display_order, wanted.display_order,
  '2026.07.1',
  'DB classification closure: policy presence; missing source values fail as insufficient_measurements',
  true
from wanted
join public.app_categories category
  on category.parent_id is null and category.code = wanted.category_code
join public.measurement_items item
  on item.canonical_key = wanted.measurement_key
on conflict (app_category_id, measurement_item_id) do update set
  dimension_code = excluded.dimension_code,
  weight = excluded.weight,
  is_primary = excluded.is_primary,
  is_comparable = true,
  required_group_code = excluded.required_group_code,
  required_group_min_dimensions = excluded.required_group_min_dimensions,
  display_order = excluded.display_order,
  selection_priority = excluded.selection_priority,
  policy_version = '2026.07.1',
  evidence_note = excluded.evidence_note,
  is_active = true,
  updated_at = now();

-- Complete explicit unordered group matrix. Only self-comparison for an
-- auto-comparable group and the previously verified sweatshirt/hoodie pair
-- are allowed. Every other pair is an explicit block.
-- Older production installations register classifier and compatibility
-- policy versions in fitmatch_taxonomy.policy_versions and enforce that
-- registry with foreign keys. The closure fixture predates that table, so
-- keep this conditional: it is a no-op in the fixture and registers the exact
-- immutable v4 bundles before any profile or compatibility row is written.
do $$
begin
  if to_regclass('fitmatch_taxonomy.policy_versions') is not null then
    insert into fitmatch_taxonomy.policy_versions (
      code, schema_version, taxonomy_version, manifest_checksum,
      status, validated_at
    ) values (
      'db-comparison-2026-08-26-final',
      '4.0',
      'fitmatch-canonical-2026-08-26-final',
      '20045d3d05471f038fe535306283034acf87ccd8b1a0785b324d51dcffc8a84b',
      'validated',
      now()
    ), (
      'db-classifier-2026-08-26-final',
      '4.0',
      'fitmatch-canonical-2026-08-26-final',
      '0b7d91f4726c413bb169659cda749de44992070d4ba31bcbf3b6731c5f8712f4',
      'validated',
      now()
    )
    on conflict (code) do nothing;

    if not exists (
      select 1
      from fitmatch_taxonomy.policy_versions
      where code = 'db-comparison-2026-08-26-final'
        and schema_version = '4.0'
        and taxonomy_version = 'fitmatch-canonical-2026-08-26-final'
        and manifest_checksum =
          '20045d3d05471f038fe535306283034acf87ccd8b1a0785b324d51dcffc8a84b'
        and status = 'validated'
        and validated_at is not null
    ) or not exists (
      select 1
      from fitmatch_taxonomy.policy_versions
      where code = 'db-classifier-2026-08-26-final'
        and schema_version = '4.0'
        and taxonomy_version = 'fitmatch-canonical-2026-08-26-final'
        and manifest_checksum =
          '0b7d91f4726c413bb169659cda749de44992070d4ba31bcbf3b6731c5f8712f4'
        and status = 'validated'
        and validated_at is not null
    ) then
      raise exception 'classification_db_closure_policy_registry_drift';
    end if;
  end if;
end $$;

-- The runtime compatibility table is keyed to the legacy taxonomy family
-- registry, while the closure authority is maintained in public comparison
-- groups. Keep those two code registries in exact active-group parity before
-- materializing the explicit matrix. This is generic data synchronization;
-- no source- or garment-specific resolver branch is introduced.
do $$
declare
  v_gap_exists boolean;
begin
  if to_regclass('fitmatch_taxonomy.comparison_families') is not null then
    execute $sync$
      insert into fitmatch_taxonomy.comparison_families (
        code, minimum_comparable_measurements, current_app_family_code,
        is_active, policy_version
      )
      select
        comparison_group.code,
        greatest(
          coalesce(comparison_policy.min_comparable_dimensions, 2), 1
        ),
        comparison_group.code,
        true,
        'db-comparison-2026-08-26-final'
      from public.comparison_groups comparison_group
      left join lateral (
        select policy.min_comparable_dimensions
        from public.comparison_policies policy
        where policy.comparison_group_code = comparison_group.code
          and policy.is_active
        order by policy.updated_at desc, policy.code
        limit 1
      ) comparison_policy on true
      where comparison_group.is_active
      on conflict (code) do nothing
    $sync$;

    execute $gap$
      select exists (
        select 1
        from public.comparison_groups comparison_group
        left join fitmatch_taxonomy.comparison_families family
          on family.code = comparison_group.code
        where comparison_group.is_active
          and family.code is null
      )
    $gap$ into v_gap_exists;

    if v_gap_exists then
      raise exception
        'classification_db_closure_comparison_family_registry_gap';
    end if;
  end if;
end $$;

delete from fitmatch_taxonomy.comparison_compatibility_rules
where policy_version = 'db-comparison-2026-08-26-final';

with groups as (
  select code, is_auto_comparable
  from public.comparison_groups
  where is_active
), pairs as (
  select left_group.code as from_code,
    right_group.code as to_code,
    left_group.is_auto_comparable as from_auto,
    right_group.is_auto_comparable as to_auto
  from groups left_group
  join groups right_group on left_group.code <= right_group.code
)
insert into fitmatch_taxonomy.comparison_compatibility_rules (
  from_family_code, to_family_code, allowed, directional,
  length_match_required, length_mismatch_excluded_measurements,
  minimum_common_measurements, required_measurements,
  measurement_weights, fallback_allowed, policy_version,
  required_any_measurements, minimum_required_any
)
select from_code, to_code,
  (
    (from_code = to_code and from_auto and to_auto)
    or array[from_code, to_code] @> array['sweatshirt','hoodie']::text[]
  ),
  false,
  (
    (from_code = to_code and from_auto and to_auto)
    or array[from_code, to_code] @> array['sweatshirt','hoodie']::text[]
  ),
  case when array[from_code, to_code] @> array['sweatshirt','hoodie']::text[]
    then array['sleeve_length']::text[] else array[]::text[] end,
  case when (from_code = to_code and from_auto and to_auto)
      or array[from_code, to_code] @> array['sweatshirt','hoodie']::text[]
    then 2 else 0 end,
  array[]::text[], '{}'::jsonb,
  array[from_code, to_code] @> array['sweatshirt','hoodie']::text[],
  'db-comparison-2026-08-26-final',
  case when array[from_code, to_code] @> array['sweatshirt','hoodie']::text[]
    then array['shoulder','chest']::text[] else array[]::text[] end,
  case when array[from_code, to_code] @> array['sweatshirt','hoodie']::text[]
    then 1 else 0 end
from pairs;

do $$
begin
  if not exists (
    select 1 from fitmatch_catalog.releases
    where id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
      and status = 'validated'
      and expected_mapping_count = 3509
      and expected_qa_count = 1608
      and validation_report->>'shadow_output_checksum' =
        'bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916'
  ) then
    raise exception 'classification_db_closure_parent_or_shadow_drift';
  end if;
end $$;

insert into fitmatch_catalog.releases (
  id, release_key, taxonomy_version, policy_version, status,
  bundle_checksum, app_taxonomy_checksum, expected_mapping_count,
  expected_qa_count, metadata, validated_at,
  validation_contract_version, validation_report
) values (
  '11800000-0000-4000-8000-000000000118',
  'fitmatch-classification-authority-final-candidate-2026-08-26-v1',
  'fitmatch-canonical-2026-08-26-final',
  'classification-db-final-closure-2026-08-26-v1',
  'validated',
  'f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be',
  'eebfa19d3d38993c00540e44410c8815ada1a0162c7856f9d414105f6d2c5c09',
  3509, 1608,
  jsonb_build_object(
    'phase', 'DB Classification Closure',
    'candidate_only', true,
    'local_validation_only', true,
    'parent_candidate_release_id',
      'f83ca2f0-88a4-4430-96fc-037d6f1efcc2',
    'production_parent_release_id',
      '65d72393-4a40-4e99-b701-fdc1ff865774',
    'production_activation_performed', false,
    'decision_write_requires_controlled_activation', true,
    'structured_facts_adapter_contract', 'payload.structured_facts-v1'
  ),
  now(), 'fitmatch-release-gate-v2',
  jsonb_build_object(
    'runtime_policy_contract', jsonb_build_object(
      'classifier_policy_version', 'db-classifier-2026-08-26-final',
      'comparison_policy_version', 'v1',
      'compatibility_rule_version', 'db-comparison-2026-08-26-final',
      'measurement_policy_version', '2026.07.1'
    ),
    'runtime_policy_contract_validated', true,
    'baseline_shadow_checksum',
      'bb580926f819e9f144e6fdee8dc4a4dbf869fab81783c07b9a20d892ee522916',
    'baseline_key_fingerprint_checksum',
      'c1ed8a45c6548149b1b434c3551a4a674b41e627a642f6ed72db7ea55bee061a',
    'manifest_checksum',
      'f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be',
    'classifier_policy_checksum',
      '0b7d91f4726c413bb169659cda749de44992070d4ba31bcbf3b6731c5f8712f4',
    'comparison_policy_checksum',
      '553789567d3cfad0a8b13d0d587962fe30bb3677d1b293549d977fcc5b3b00c9',
    'compatibility_rule_checksum',
      '20045d3d05471f038fe535306283034acf87ccd8b1a0785b324d51dcffc8a84b',
    'measurement_policy_checksum',
      'd2a98b24f29ddfb57c0e2afa3215a7d9920a2a5f110fe50e301267c443ec4713',
    'structured_discriminator_checksum',
      'b120f07ae666ecdbc9cb9803b6272a2e51383511ee1a0573c6a63561656bf9d9',
    'source_mapping_checksum',
      '9f2da8478a663f1b971db5a61d452b7aac8fb2ddbfb9b0137ab97cc11d184cfb',
    'targeted_decision_checksum',
      '04d176e0e451f45604e12384a959b617eb90abb0e2775ff0d6a3afc565830ac2',
    'taxonomy_checksum',
      'eebfa19d3d38993c00540e44410c8815ada1a0162c7856f9d414105f6d2c5c09',
    'production_write_count', 0,
    'production_activation_performed', false
  )
)
on conflict (id) do update set
  release_key = excluded.release_key,
  taxonomy_version = excluded.taxonomy_version,
  policy_version = excluded.policy_version,
  status = 'validated',
  bundle_checksum = excluded.bundle_checksum,
  app_taxonomy_checksum = excluded.app_taxonomy_checksum,
  expected_mapping_count = excluded.expected_mapping_count,
  expected_qa_count = excluded.expected_qa_count,
  metadata = excluded.metadata,
  validated_at = now(),
  validation_contract_version = excluded.validation_contract_version,
  validation_report = excluded.validation_report;

insert into fitmatch_catalog.source_category_mappings (
  release_id, source_identity, source, snapshot_id,
  external_category_id, target, normalized_path, decision_status,
  mapping_status, runtime_lookup_eligible, eligibility,
  semantic_category_code, semantic_garment_type, comparison_family,
  source_external_key, source_external_target_key,
  source_path_key, source_target_path_key, raw_record
)
select
  '11800000-0000-4000-8000-000000000118'::uuid,
  source_identity, source, snapshot_id, external_category_id, target,
  normalized_path, decision_status, mapping_status,
  runtime_lookup_eligible, eligibility, semantic_category_code,
  semantic_garment_type, comparison_family, source_external_key,
  source_external_target_key, source_path_key, source_target_path_key,
  raw_record
from fitmatch_catalog.source_category_mappings
where release_id = 'f83ca2f0-88a4-4430-96fc-037d6f1efcc2'::uuid
on conflict (release_id, source_identity) do update set
  decision_status = excluded.decision_status,
  mapping_status = excluded.mapping_status,
  runtime_lookup_eligible = excluded.runtime_lookup_eligible,
  eligibility = excluded.eligibility,
  semantic_category_code = excluded.semantic_category_code,
  semantic_garment_type = excluded.semantic_garment_type,
  comparison_family = excluded.comparison_family,
  raw_record = excluded.raw_record;

-- Normalize every invalid or legacy/non-authoritative mapping to an explicit,
-- non-eligible revoked scope first. Verified repairs below are then applied to
-- the exact independently adjudicated rows only.
update fitmatch_catalog.source_category_mappings
set decision_status = 'review_required',
    mapping_status = 'revoked',
    runtime_lookup_eligible = false,
    eligibility = false,
    raw_record = jsonb_set(
      jsonb_set(
        jsonb_set(raw_record, '{authorityContract,authorityStatus}', '"revoked"', true),
        '{authorityContract,resolutionScope}', '"revoked"', true
      ),
      '{authorityContract,productRequired}', 'false', true
    ) || jsonb_build_object(
      'authorityStatus', 'revoked',
      'resolutionScope', 'revoked',
      'productRequired', false,
      'runtimeLookupEligible', false,
      'eligibility', false,
      'closureDisposition', 'REVOKED_NO_VERIFIED_REPLACEMENT'
    )
where release_id = '11800000-0000-4000-8000-000000000118'::uuid
  and lower(coalesce(
    raw_record#>>'{authorityContract,resolutionScope}',
    raw_record->>'resolutionScope', ''
  )) in ('invalid_mapping', 'existing_non_authoritative');

-- Mixed sleeveless retailer categories are not semantically pure.
update fitmatch_catalog.source_category_mappings
set decision_status = 'review_required',
    mapping_status = 'product_required',
    runtime_lookup_eligible = true,
    eligibility = true,
    semantic_category_code = 'tops',
    semantic_garment_type = null,
    comparison_family = null,
    raw_record = jsonb_set(
      jsonb_set(
        jsonb_set(raw_record, '{authorityContract,authorityStatus}', '"verified"', true),
        '{authorityContract,resolutionScope}', '"product_required"', true
      ),
      '{authorityContract,productRequired}', 'true', true
    ) || jsonb_build_object(
      'authorityStatus', 'verified',
      'resolutionScope', 'product_required',
      'productRequired', true,
      'semanticCategoryCode', 'tops',
      'semanticGarmentType', null,
      'comparisonFamily', null,
      'closureDisposition', 'MIXED_SLEEVELESS_PRODUCT_REQUIRED'
    )
where release_id = '11800000-0000-4000-8000-000000000118'::uuid
  and source = 'musinsa'
  and external_category_id in ('001011', '017016003');

-- Invalid vocabulary rows whose category is still mixed due to a missing
-- sleeve axis become PRODUCT_REQUIRED, without inventing replacement tuples.
update fitmatch_catalog.source_category_mappings
set decision_status = 'review_required',
    mapping_status = 'product_required',
    runtime_lookup_eligible = true,
    eligibility = true,
    raw_record = jsonb_set(
      jsonb_set(
        jsonb_set(raw_record, '{authorityContract,authorityStatus}', '"verified"', true),
        '{authorityContract,resolutionScope}', '"product_required"', true
      ),
      '{authorityContract,productRequired}', 'true', true
    ) || jsonb_build_object(
      'authorityStatus', 'verified',
      'resolutionScope', 'product_required',
      'productRequired', true,
      'closureDisposition', 'PRODUCT_REQUIRED_MISSING_SLEEVE_AXIS'
    )
where release_id = '11800000-0000-4000-8000-000000000118'::uuid
  and (
    (source = 'musinsa' and external_category_id = '002020')
    or
    (source = 'uniqlo' and external_category_id in (
      '128382','128384','128427','135281','136609','95375',
      '116336','95370','95376','95378','95379','95405'
    ))
  );

-- Helper block applies only independently verified, semantically complete
-- CATEGORY_DIRECT replacements.
with replacements(
  source, external_category_id, category_code, detail_code,
  garment_type_code, family_code, sleeve_axis, pants_axis, body_axis
) as (
  values
    ('uniqlo','58145','tops','sleeveless','sleeveless_tshirt','sleeveless_tshirt','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','58397','tops','sleeveless','sleeveless_tshirt','sleeveless_tshirt','sleeveless','not_applicable','not_applicable'),
    ('musinsa','017018015','outerwear','padding','puffer_jacket','puffer_jacket','long_sleeve','not_applicable','medium_body'),
    ('uniqlo','100100','leggings','long_leggings','leggings','leggings','not_applicable','long_length','not_applicable'),
    ('uniqlo','141498','tops','base_layer_top','base_layer_top','base_layer_top','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','141499','tops','base_layer_top','base_layer_top','base_layer_top','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','58274','tops','base_layer_top','base_layer_top','base_layer_top','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','58275','tops','base_layer_top','base_layer_top','base_layer_top','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','58635','tops','base_layer_top','base_layer_top','base_layer_top','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','58636','tops','base_layer_top','base_layer_top','base_layer_top','sleeveless','not_applicable','not_applicable'),
    ('uniqlo','58154','tops','sweatshirt','sweatshirt','sweatshirt','long_sleeve','not_applicable','not_applicable'),
    ('uniqlo','58401','tops','sweatshirt','sweatshirt','sweatshirt','long_sleeve','not_applicable','not_applicable'),
    ('uniqlo','58407','tops','sweatshirt','sweatshirt','sweatshirt','long_sleeve','not_applicable','not_applicable')
)
update fitmatch_catalog.source_category_mappings mapping
set decision_status = 'confirmed',
    mapping_status = 'direct',
    runtime_lookup_eligible = true,
    eligibility = true,
    semantic_category_code = replacement.category_code,
    semantic_garment_type = replacement.garment_type_code,
    comparison_family = replacement.family_code,
    raw_record = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
                jsonb_set(mapping.raw_record,
                  '{appMapping,categoryCode}', to_jsonb(replacement.category_code), true),
                '{appMapping,detailCode}', to_jsonb(replacement.detail_code), true),
              '{lengthAxes,sleeve}', to_jsonb(replacement.sleeve_axis), true),
            '{lengthAxes,pants}', to_jsonb(replacement.pants_axis), true),
          '{lengthAxes,leggings}', to_jsonb(replacement.pants_axis), true),
        '{lengthAxes,body}', to_jsonb(replacement.body_axis), true),
      '{lengthAxes,skirt}', to_jsonb(replacement.body_axis), true
    ) || jsonb_build_object(
      'authorityStatus', 'verified',
      'resolutionScope', 'category_direct',
      'productRequired', false,
      'semanticCategoryCode', replacement.category_code,
      'semanticGarmentType', replacement.garment_type_code,
      'comparisonFamily', replacement.family_code,
      'runtimeLookupEligible', true,
      'eligibility', true,
      'closureDisposition', 'VERIFIED_CATEGORY_DIRECT'
    ) || jsonb_build_object(
      'authorityContract', coalesce(mapping.raw_record->'authorityContract','{}')
        || jsonb_build_object(
          'authorityStatus','verified',
          'resolutionScope','category_direct',
          'productRequired',false
        )
    )
from replacements replacement
where mapping.release_id = '11800000-0000-4000-8000-000000000118'::uuid
  and mapping.source = replacement.source
  and mapping.external_category_id = replacement.external_category_id;

delete from fitmatch_catalog.classification_structured_discriminator_rules
where release_id='11800000-0000-4000-8000-000000000118'::uuid;

insert into fitmatch_catalog.classification_structured_discriminator_rules (
  release_id, rule_id, source, discriminator_key, discriminator_value,
  external_category_id, normalized_path, target, outcome,
  category_code, detail_code, garment_type_code, family_code,
  length_code, body_length_code, exclusion_reason_code,
  authority_status, resolution_scope, runtime_eligible, evidence,
  policy_version
)
select
  '11800000-0000-4000-8000-000000000118'::uuid,
  value->>'rule_id', value->>'source', value->>'key', value->>'value',
  nullif(value->>'external_category_id',''),
  nullif(value->>'normalized_path',''), nullif(value->>'target',''),
  coalesce(value->>'outcome','canonical'),
  case when value ? 'tuple' then value#>>'{tuple,0}' end,
  case when value ? 'tuple' then value#>>'{tuple,1}' end,
  case when value ? 'tuple' then value#>>'{tuple,2}' end,
  case when value ? 'tuple' then value#>>'{tuple,3}' end,
  case when value ? 'tuple' then value#>>'{tuple,4}' end,
  case when value ? 'tuple' then nullif(value#>>'{tuple,5}','') end,
  value->>'reason', 'verified',
  case when value->>'outcome' = 'not_comparable'
    then 'excluded' else 'structured_product' end,
  true,
  jsonb_build_object(
    'basis', value->>'evidence_basis',
    'manifest_checksum',
      'f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be'
  ),
  'db-classifier-2026-08-26-final'
from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
where value->>'record_type' = 'structured_discriminator_rule'
on conflict (release_id, rule_id) do update set
  source = excluded.source,
  discriminator_key = excluded.discriminator_key,
  discriminator_value = excluded.discriminator_value,
  external_category_id = excluded.external_category_id,
  normalized_path = excluded.normalized_path,
  target = excluded.target,
  outcome = excluded.outcome,
  category_code = excluded.category_code,
  detail_code = excluded.detail_code,
  garment_type_code = excluded.garment_type_code,
  family_code = excluded.family_code,
  length_code = excluded.length_code,
  body_length_code = excluded.body_length_code,
  exclusion_reason_code = excluded.exclusion_reason_code,
  authority_status = excluded.authority_status,
  resolution_scope = excluded.resolution_scope,
  runtime_eligible = excluded.runtime_eligible,
  evidence = excluded.evidence,
  policy_version = excluded.policy_version;

-- This policy version belongs exclusively to the inactive 118 candidate.
-- Reapply replaces its own candidate profiles so removed draft paths cannot
-- survive idempotency testing; no active/production policy version is touched.
delete from fitmatch_catalog.classification_path_profiles
where policy_version='db-classifier-2026-08-26-final';
delete from fitmatch_catalog.classification_name_profiles
where policy_version='db-classifier-2026-08-26-final';
delete from fitmatch_catalog.classification_exclusion_profiles
where policy_version='db-classifier-2026-08-26-final';

insert into fitmatch_catalog.classification_path_profiles (
  policy_version, source, normalized_path, category_code, detail_code,
  comparison_family_code, length_code, sample_count, review_count,
  distinct_decision_count, auto_eligible, evidence
)
select value->>'policy_version', value->>'source',
  fitmatch_catalog.runtime_normalized_category_path(value->>'normalized_path'),
  value#>>'{tuple,0}', value#>>'{tuple,1}', value#>>'{tuple,3}',
  value#>>'{tuple,4}', (value->>'sample_count')::integer, 0, 1, true,
  jsonb_build_object(
    'authority_status','verified',
    'garment_type_code',value#>>'{tuple,2}',
    'body_length_code',nullif(value#>>'{tuple,5}',''),
    'evidence_basis',value->>'evidence_basis',
    'complete_tuple',true
  )
from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
where value->>'record_type' = 'verified_path_profile'
on conflict (policy_version, source, normalized_path) do update set
  category_code = excluded.category_code,
  detail_code = excluded.detail_code,
  comparison_family_code = excluded.comparison_family_code,
  length_code = excluded.length_code,
  sample_count = excluded.sample_count,
  review_count = 0,
  distinct_decision_count = 1,
  auto_eligible = true,
  evidence = excluded.evidence;

insert into fitmatch_catalog.classification_exclusion_profiles (
  policy_version, source, normalized_path, sample_count, auto_eligible,
  reason_code, evidence
)
select value->>'policy_version', value->>'source',
  fitmatch_catalog.runtime_normalized_category_path(value->>'normalized_path'),
  (value->>'sample_count')::integer, true, value->>'reason_code',
  jsonb_build_object(
    'authority_status','verified',
    'complete_profile',true,
    'closure_version','2026-08-26'
  )
from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
where value->>'record_type' = 'verified_exclusion_profile'
on conflict (policy_version, source, normalized_path) do update set
  sample_count = excluded.sample_count,
  auto_eligible = true,
  reason_code = excluded.reason_code,
  evidence = excluded.evidence;

create or replace function
fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
returns table (
  source text, external_product_id text, product_name text,
  source_category_path text, input_fingerprint text, category_code text,
  detail_code text, garment_type_code text, family_code text,
  length_code text, body_length_code text, authority_status text,
  requires_user_confirmation boolean, decision_version text,
  action text, reason text, evidence jsonb
)
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $function$
  with overrides as (
    select value
    from fitmatch_catalog.runtime_classification_db_final_manifest_v1()
    where value->>'record_type' = 'verified_product_decision_override'
  )
  select base.*
  from fitmatch_catalog.runtime_classification_candidate_revision_decision_manifest_v2()
    base
  where not exists (
    select 1 from overrides override
    where override.value->>'source' = base.source
      and override.value->>'external_product_id' = base.external_product_id
  )
  union all
  select
    value->>'source', value->>'external_product_id',
    value->>'product_name', value->>'source_category_path',
    value->>'input_fingerprint', value#>>'{tuple,0}', value#>>'{tuple,1}',
    value#>>'{tuple,2}', value#>>'{tuple,3}', value#>>'{tuple,4}',
    nullif(value#>>'{tuple,5}',''), 'verified', false,
    value->>'decision_version', 'UPSERT_VERIFIED', value->>'reason',
    jsonb_build_object(
      'basis', value->'evidence_basis',
      'body_length_code', nullif(value#>>'{tuple,5}',''),
      'legacy_semantic_translation', true,
      'closure_version', '2026-08-26'
    )
  from overrides
$function$;

-- Final v4 resolver: exclusion gate -> verified exact -> verified structured
-- -> pure category -> verified path -> verified name -> fail closed. No raw
-- name matching and no source-specific discriminator branch exists here.
create or replace function
fitmatch_catalog.runtime_resolve_product_classification_v4(
  p_source text,
  p_external_product_id text,
  p_product_name text,
  p_source_category_path text,
  p_payload jsonb default '{}'::jsonb,
  p_release_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_source text := lower(btrim(coalesce(p_source,'')));
  v_external_id text := btrim(coalesce(p_external_product_id,''));
  v_name text := btrim(coalesce(p_product_name,''));
  v_path text := fitmatch_catalog.runtime_normalized_category_path(p_source_category_path);
  v_signature text := fitmatch_catalog.runtime_product_name_signature(p_product_name);
  v_fingerprint text := fitmatch_catalog.runtime_product_fingerprint(p_product_name,p_source_category_path);
  v_target text := upper(nullif(btrim(coalesce(p_payload->>'audience','')),''));
  v_release_id uuid;
  v_contract jsonb;
  v_classifier_version text;
  v_release_policy text;
  v_decision fitmatch_catalog.product_classification_decisions%rowtype;
  v_decision_found boolean := false;
  v_decision_validation jsonb;
  v_decision_body text;
  v_mapping fitmatch_catalog.source_category_mappings%rowtype;
  v_mapping_found boolean := false;
  v_mapping_count integer := 0;
  v_mapping_scope text;
  v_mapping_category text;
  v_mapping_detail text;
  v_mapping_garment text;
  v_mapping_family text;
  v_mapping_length text;
  v_mapping_body text;
  v_mapping_validation jsonb;
  v_rule fitmatch_catalog.classification_structured_discriminator_rules%rowtype;
  v_rule_found boolean := false;
  v_rule_count integer := 0;
  v_rule_validation jsonb;
  v_exclusion fitmatch_catalog.classification_exclusion_profiles%rowtype;
  v_path_profile fitmatch_catalog.classification_path_profiles%rowtype;
  v_name_profile fitmatch_catalog.classification_name_profiles%rowtype;
  v_candidate_source text;
  v_candidate_method text;
  v_candidate_category text;
  v_candidate_detail text;
  v_candidate_garment text;
  v_candidate_family text;
  v_candidate_length text;
  v_candidate_body text;
  v_candidate_validation jsonb;
  v_candidate_evidence jsonb := '{}'::jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_reasons jsonb := '[]'::jsonb;
begin
  if v_source !~ '^[a-z][a-z0-9_]*$'
    or v_external_id = '' or v_name = ''
    or jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object' then
    raise exception using errcode='22023',
      message='invalid_product_classification_preview_input';
  end if;

  if p_release_id is null then
    select id, policy_version, validation_report->'runtime_policy_contract'
    into v_release_id, v_release_policy, v_contract
    from fitmatch_catalog.releases
    where status='active'
    order by activated_at desc nulls last, created_at desc limit 1;
  else
    select id, policy_version, validation_report->'runtime_policy_contract'
    into v_release_id, v_release_policy, v_contract
    from fitmatch_catalog.releases where id=p_release_id;
    if not found then
      raise exception using errcode='P0002', message='release_not_found';
    end if;
  end if;
  v_classifier_version := nullif(btrim(v_contract->>'classifier_policy_version'),'');

  select decision.* into v_decision
  from fitmatch_catalog.product_classification_decisions decision
  where decision.source=v_source and decision.external_product_id=v_external_id;
  v_decision_found := found and v_decision.input_fingerprint=v_fingerprint;
  if v_decision_found and v_decision.authority_status <> 'revoked' then
    v_decision_body := nullif(lower(btrim(v_decision.evidence->>'body_length_code')),'');
    v_decision_validation := fitmatch_catalog.runtime_validate_classification_tuple_v1(
      v_decision.category_code,v_decision.detail_code,v_decision.garment_type_code,
      v_decision.comparison_family,v_decision.length_type,v_decision_body
    );
  end if;

  -- A verified structured exclusion is a pre-classification validation gate.
  if jsonb_typeof(p_payload->'structured_facts') = 'object' then
    select rule.* into v_rule
    from fitmatch_catalog.classification_structured_discriminator_rules rule
    join lateral jsonb_each_text(p_payload->'structured_facts') fact(key,value)
      on lower(btrim(fact.key))=rule.discriminator_key
     and lower(regexp_replace(btrim(fact.value),E'\\s+',' ','g'))=
         lower(regexp_replace(btrim(rule.discriminator_value),E'\\s+',' ','g'))
    where rule.release_id=v_release_id
      and rule.runtime_eligible and rule.authority_status='verified'
      and rule.outcome='not_comparable'
      and rule.source in ('*',v_source)
      and (rule.normalized_path is null or
        fitmatch_catalog.runtime_normalized_category_path(rule.normalized_path)=v_path)
      and (rule.target is null or rule.target=v_target)
    order by (rule.source=v_source) desc,
      (rule.normalized_path is not null) desc,
      (rule.target is not null) desc, rule.rule_id
    limit 1;
    if found then
      return jsonb_build_object(
        'category_code',null,'detail_code',null,'garment_type_code',null,
        'family_code',null,'length_code',null,'body_length_code',null,
        'classification_status','not_comparable',
        'classification_method','structured_exclusion',
        'authority_status','verified','confidence',1,
        'requires_user_confirmation',false,'mapping_release_id',v_release_id,
        'decision_version',v_classifier_version,'tuple_validation',null,
        'authority_conflicts','[]'::jsonb,
        'evidence',jsonb_build_object(
          'exclusion_reason',v_rule.exclusion_reason_code,
          'structured_rule_id',v_rule.rule_id,
          'set_validation_precedes_classifier',
            v_rule.discriminator_key='product_structure'
        ),'classifier_policy_version',v_classifier_version
      );
    end if;
  end if;

  if v_classifier_version is not null then
    select profile.* into v_exclusion
    from fitmatch_catalog.classification_exclusion_profiles profile
    where profile.policy_version=v_classifier_version
      and profile.source=v_source and profile.normalized_path=v_path
      and profile.auto_eligible
      and lower(coalesce(profile.evidence->>'authority_status',''))='verified';
    if found then
      return jsonb_build_object(
        'category_code',null,'detail_code',null,'garment_type_code',null,
        'family_code',null,'length_code',null,'body_length_code',null,
        'classification_status','not_comparable',
        'classification_method','verified_exclusion_profile',
        'authority_status','verified','confidence',1,
        'requires_user_confirmation',false,'mapping_release_id',v_release_id,
        'decision_version',v_classifier_version,'tuple_validation',null,
        'authority_conflicts','[]'::jsonb,
        'evidence',jsonb_build_object('exclusion_reason',v_exclusion.reason_code,
          'profile_source','path_exclusion'),
        'classifier_policy_version',v_classifier_version
      );
    end if;
  end if;

  -- Verified, complete, fingerprint-matched exact authority is highest after
  -- exclusion validation.
  if v_decision_found and v_decision.authority_status='verified'
    and coalesce((v_decision_validation->>'valid')::boolean,false) then
    return jsonb_build_object(
      'category_code',v_decision.category_code,
      'detail_code',v_decision.detail_code,
      'garment_type_code',v_decision.garment_type_code,
      'family_code',v_decision.comparison_family,
      'length_code',v_decision.length_type,
      'body_length_code',v_decision_body,
      'classification_status','confirmed',
      'classification_method','canonical_product_decision',
      'authority_status','verified','confidence',1,
      'requires_user_confirmation',false,'mapping_release_id',null,
      'decision_version',v_decision.decision_version,
      'tuple_validation',v_decision_validation,
      'authority_conflicts','[]'::jsonb,
      'evidence',jsonb_build_object('decision_release_id',v_decision.release_id,
        'decision_evidence',v_decision.evidence,'authority_precedence','A'),
      'classifier_policy_version',v_classifier_version
    );
  end if;

  -- Mapping lookup only considers verified, runtime-eligible direct/required
  -- rows. Revoked, invalid and legacy rows cannot shadow a path fallback.
  if jsonb_typeof(p_payload->'source_category_codes')='array'
    and jsonb_array_length(p_payload->'source_category_codes')>0 then
    with codes as (
      select value code, ordinality
      from jsonb_array_elements_text(p_payload->'source_category_codes')
        with ordinality item(value,ordinality)
    ), candidates as (
      select mapping.*,codes.ordinality,
        max(codes.ordinality) over() max_ordinality
      from codes join fitmatch_catalog.source_category_mappings mapping
        on mapping.release_id=v_release_id and mapping.source=v_source
       and mapping.external_category_id=codes.code
       and mapping.runtime_lookup_eligible and mapping.eligibility
       and lower(coalesce(mapping.raw_record#>>'{authorityContract,authorityStatus}',
           mapping.raw_record->>'authorityStatus',''))='verified'
       and ((v_target is not null and mapping.target=v_target)
         or (v_target is null and mapping.target='UNKNOWN'))
    ), leaf as (select * from candidates where ordinality=max_ordinality)
    select count(*) into v_mapping_count from leaf;
    if v_mapping_count=1 then
      with codes as (
        select value code, ordinality
        from jsonb_array_elements_text(p_payload->'source_category_codes')
          with ordinality item(value,ordinality)
      ), candidates as (
        select mapping.*,codes.ordinality,
          max(codes.ordinality) over() max_ordinality
        from codes join fitmatch_catalog.source_category_mappings mapping
          on mapping.release_id=v_release_id and mapping.source=v_source
         and mapping.external_category_id=codes.code
         and mapping.runtime_lookup_eligible and mapping.eligibility
         and lower(coalesce(mapping.raw_record#>>'{authorityContract,authorityStatus}',
             mapping.raw_record->>'authorityStatus',''))='verified'
         and ((v_target is not null and mapping.target=v_target)
           or (v_target is null and mapping.target='UNKNOWN'))
      ) select * into v_mapping from candidates
        where ordinality=max_ordinality limit 1;
      v_mapping_found := found;
    elsif v_mapping_count>1 then
      v_conflicts := v_conflicts||jsonb_build_array(jsonb_build_object(
        'code','source_mapping_ambiguous','candidate_count',v_mapping_count));
    end if;
  end if;
  if not v_mapping_found and v_mapping_count=0 and v_path<>'' then
    select count(*) into v_mapping_count
    from fitmatch_catalog.source_category_mappings mapping
    where mapping.release_id=v_release_id and mapping.source=v_source
      and fitmatch_catalog.runtime_normalized_category_path(mapping.normalized_path)=v_path
      and mapping.runtime_lookup_eligible and mapping.eligibility
      and lower(coalesce(mapping.raw_record#>>'{authorityContract,authorityStatus}',
          mapping.raw_record->>'authorityStatus',''))='verified'
      and ((v_target is not null and mapping.target=v_target)
        or (v_target is null and mapping.target='UNKNOWN'));
    if v_mapping_count=1 then
      select mapping.* into v_mapping
      from fitmatch_catalog.source_category_mappings mapping
      where mapping.release_id=v_release_id and mapping.source=v_source
        and fitmatch_catalog.runtime_normalized_category_path(mapping.normalized_path)=v_path
        and mapping.runtime_lookup_eligible and mapping.eligibility
        and lower(coalesce(mapping.raw_record#>>'{authorityContract,authorityStatus}',
            mapping.raw_record->>'authorityStatus',''))='verified'
        and ((v_target is not null and mapping.target=v_target)
          or (v_target is null and mapping.target='UNKNOWN'))
      order by mapping.source_identity limit 1;
      v_mapping_found := found;
    elsif v_mapping_count>1 then
      v_conflicts := v_conflicts||jsonb_build_array(jsonb_build_object(
        'code','source_mapping_ambiguous','candidate_count',v_mapping_count));
    end if;
  end if;

  if v_mapping_found then
    v_mapping_scope := lower(coalesce(
      nullif(v_mapping.raw_record#>>'{authorityContract,resolutionScope}',''),
      nullif(v_mapping.raw_record->>'resolutionScope',''),''));
    v_mapping_category := nullif(lower(btrim(coalesce(v_mapping.semantic_category_code,
      v_mapping.raw_record#>>'{appMapping,categoryCode}'))),'');
    v_mapping_detail := nullif(lower(btrim(v_mapping.raw_record#>>'{appMapping,detailCode}')),'');
    v_mapping_garment := nullif(lower(btrim(v_mapping.semantic_garment_type)),'');
    v_mapping_family := nullif(lower(btrim(v_mapping.comparison_family)),'');
    select case when garment.requires_sleeve_class then
        v_mapping.raw_record#>>'{lengthAxes,sleeve}'
      when garment.requires_pants_length then coalesce(
        nullif(v_mapping.raw_record#>>'{lengthAxes,leggings}',''),
        v_mapping.raw_record#>>'{lengthAxes,pants}')
      else 'not_applicable' end,
      case when garment.requires_body_length then coalesce(
        nullif(v_mapping.raw_record#>>'{lengthAxes,body}',''),
        v_mapping.raw_record#>>'{lengthAxes,skirt}')
      else 'not_applicable' end
    into v_mapping_length,v_mapping_body
    from public.garment_types garment
    where garment.code=v_mapping_garment and garment.is_active;
    v_mapping_validation := fitmatch_catalog.runtime_validate_classification_tuple_v1(
      v_mapping_category,v_mapping_detail,v_mapping_garment,v_mapping_family,
      v_mapping_length,v_mapping_body);
    if v_mapping_scope='product_required' then
      v_reasons:=v_reasons||jsonb_build_array('source_mapping_product_required');
    end if;
  end if;

  -- Generic typed fact lookup; field names are data, never source branches.
  if jsonb_typeof(p_payload->'structured_facts')='object' then
    with candidates as (
      select rule.*,
        ((rule.source=v_source)::int*8
          +(rule.external_category_id is not null)::int*4
          +(rule.normalized_path is not null)::int*2
          +(rule.target is not null)::int) specificity
      from fitmatch_catalog.classification_structured_discriminator_rules rule
      join lateral jsonb_each_text(p_payload->'structured_facts') fact(key,value)
        on lower(btrim(fact.key))=rule.discriminator_key
       and lower(regexp_replace(btrim(fact.value),E'\\s+',' ','g'))=
           lower(regexp_replace(btrim(rule.discriminator_value),E'\\s+',' ','g'))
      where rule.release_id=v_release_id and rule.runtime_eligible
        and rule.authority_status='verified' and rule.outcome='canonical'
        and rule.source in ('*',v_source)
        and (rule.external_category_id is null or exists(
          select 1 from jsonb_array_elements_text(
            coalesce(p_payload->'source_category_codes','[]'::jsonb)) code(value)
          where code.value=rule.external_category_id))
        and (rule.normalized_path is null or
          fitmatch_catalog.runtime_normalized_category_path(rule.normalized_path)=v_path)
        and (rule.target is null or rule.target=v_target)
    ), ranked as (
      select *,max(specificity) over() max_specificity from candidates
    )
    select count(*) into v_rule_count from ranked where specificity=max_specificity;
    if v_rule_count=1 then
      with candidates as (
        select rule.*,
          ((rule.source=v_source)::int*8
            +(rule.external_category_id is not null)::int*4
            +(rule.normalized_path is not null)::int*2
            +(rule.target is not null)::int) specificity
        from fitmatch_catalog.classification_structured_discriminator_rules rule
        join lateral jsonb_each_text(p_payload->'structured_facts') fact(key,value)
          on lower(btrim(fact.key))=rule.discriminator_key
         and lower(regexp_replace(btrim(fact.value),E'\\s+',' ','g'))=
             lower(regexp_replace(btrim(rule.discriminator_value),E'\\s+',' ','g'))
        where rule.release_id=v_release_id and rule.runtime_eligible
          and rule.authority_status='verified' and rule.outcome='canonical'
          and rule.source in ('*',v_source)
          and (rule.external_category_id is null or exists(
            select 1 from jsonb_array_elements_text(
              coalesce(p_payload->'source_category_codes','[]'::jsonb)) code(value)
            where code.value=rule.external_category_id))
          and (rule.normalized_path is null or
            fitmatch_catalog.runtime_normalized_category_path(rule.normalized_path)=v_path)
          and (rule.target is null or rule.target=v_target)
      ), ranked as (select *,max(specificity) over() max_specificity from candidates)
      select rule.* into v_rule from ranked rule
      where specificity=max_specificity order by rule_id limit 1;
      v_rule_found:=found;
      v_rule_validation:=fitmatch_catalog.runtime_validate_classification_tuple_v1(
        v_rule.category_code,v_rule.detail_code,v_rule.garment_type_code,
        v_rule.family_code,v_rule.length_code,v_rule.body_length_code);
    elsif v_rule_count>1 then
      v_reasons:=v_reasons||jsonb_build_array('structured_discriminator_ambiguous');
    end if;
  end if;

  if v_rule_found and coalesce((v_rule_validation->>'valid')::boolean,false) then
    v_candidate_source:='structured_discriminator';
    v_candidate_method:='structured_discriminator';
    v_candidate_category:=v_rule.category_code; v_candidate_detail:=v_rule.detail_code;
    v_candidate_garment:=v_rule.garment_type_code; v_candidate_family:=v_rule.family_code;
    v_candidate_length:=v_rule.length_code; v_candidate_body:=v_rule.body_length_code;
    v_candidate_validation:=v_rule_validation;
    v_candidate_evidence:=jsonb_build_object('structured_rule_id',v_rule.rule_id,
      'discriminator_key',v_rule.discriminator_key,'authority_precedence','B');
  elsif v_mapping_found and v_mapping_scope='category_direct'
    and coalesce((v_mapping_validation->>'valid')::boolean,false) then
    v_candidate_source:='category_mapping'; v_candidate_method:='category_mapping';
    v_candidate_category:=v_mapping_category; v_candidate_detail:=v_mapping_detail;
    v_candidate_garment:=v_mapping_garment; v_candidate_family:=v_mapping_family;
    v_candidate_length:=v_mapping_length; v_candidate_body:=v_mapping_body;
    v_candidate_validation:=v_mapping_validation;
    v_candidate_evidence:=jsonb_build_object('source_mapping_identity',v_mapping.source_identity,
      'authority_precedence','C');
  end if;

  -- A complete legacy row remains audit evidence. It may surface a conflict,
  -- but an incomplete/invalid legacy row is never authority and never blocks.
  if v_candidate_source is not null and v_decision_found
    and v_decision.authority_status='legacy'
    and coalesce((v_decision_validation->>'valid')::boolean,false)
    and (v_decision.category_code is distinct from v_candidate_category
      or v_decision.detail_code is distinct from v_candidate_detail
      or v_decision.garment_type_code is distinct from v_candidate_garment
      or v_decision.comparison_family is distinct from v_candidate_family
      or v_decision.length_type is distinct from v_candidate_length
      or v_decision_body is distinct from v_candidate_body) then
    v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object(
      'code','complete_legacy_evidence_conflict','candidate_source',v_candidate_source,
      'decision_version',v_decision.decision_version));
  end if;

  if v_candidate_source is not null and jsonb_array_length(v_conflicts)=0 then
    return jsonb_build_object(
      'category_code',v_candidate_category,'detail_code',v_candidate_detail,
      'garment_type_code',v_candidate_garment,'family_code',v_candidate_family,
      'length_code',v_candidate_length,'body_length_code',v_candidate_body,
      'classification_status','confirmed','classification_method',v_candidate_method,
      'authority_status','verified','confidence',0.99,
      'requires_user_confirmation',false,
      'mapping_release_id',case when v_candidate_source in('category_mapping','structured_discriminator') then v_release_id else null end,
      'decision_version',coalesce(v_classifier_version,v_release_policy),
      'tuple_validation',v_candidate_validation,'authority_conflicts',v_conflicts,
      'evidence',v_candidate_evidence,'classifier_policy_version',v_classifier_version
    );
  end if;

  -- Verified path precedes verified name. Profiles must carry a complete,
  -- validator-passing tuple; raw name signature generation alone is inert.
  if v_candidate_source is null and v_classifier_version is not null then
    select profile.* into v_path_profile
    from fitmatch_catalog.classification_path_profiles profile
    where profile.policy_version=v_classifier_version and profile.source=v_source
      and profile.normalized_path=v_path and profile.auto_eligible
      and lower(coalesce(profile.evidence->>'authority_status',''))='verified';
    if found then
      v_candidate_category:=v_path_profile.category_code;
      v_candidate_detail:=v_path_profile.detail_code;
      v_candidate_garment:=nullif(lower(btrim(v_path_profile.evidence->>'garment_type_code')),'');
      v_candidate_family:=v_path_profile.comparison_family_code;
      v_candidate_length:=v_path_profile.length_code;
      v_candidate_body:=nullif(lower(btrim(v_path_profile.evidence->>'body_length_code')),'');
      v_candidate_validation:=fitmatch_catalog.runtime_validate_classification_tuple_v1(
        v_candidate_category,v_candidate_detail,v_candidate_garment,v_candidate_family,
        v_candidate_length,v_candidate_body);
      if coalesce((v_candidate_validation->>'valid')::boolean,false) then
        v_candidate_source:='path_profile'; v_candidate_method:='verified_path_profile';
        v_candidate_evidence:=jsonb_build_object('profile_source','path_profile',
          'authority_precedence','D','sample_count',v_path_profile.sample_count);
      end if;
    end if;
  end if;
  if v_candidate_source is null and v_classifier_version is not null and v_signature<>'' then
    select profile.* into v_name_profile
    from fitmatch_catalog.classification_name_profiles profile
    where profile.policy_version=v_classifier_version and profile.source=v_source
      and profile.normalized_path=v_path and profile.name_signature=v_signature
      and profile.auto_eligible
      and lower(coalesce(profile.evidence->>'authority_status',''))='verified';
    if found then
      v_candidate_category:=v_name_profile.category_code;
      v_candidate_detail:=v_name_profile.detail_code;
      v_candidate_garment:=nullif(lower(btrim(v_name_profile.evidence->>'garment_type_code')),'');
      v_candidate_family:=v_name_profile.comparison_family_code;
      v_candidate_length:=v_name_profile.length_code;
      v_candidate_body:=nullif(lower(btrim(v_name_profile.evidence->>'body_length_code')),'');
      v_candidate_validation:=fitmatch_catalog.runtime_validate_classification_tuple_v1(
        v_candidate_category,v_candidate_detail,v_candidate_garment,v_candidate_family,
        v_candidate_length,v_candidate_body);
      if coalesce((v_candidate_validation->>'valid')::boolean,false) then
        v_candidate_source:='name_profile'; v_candidate_method:='verified_name_signature_profile';
        v_candidate_evidence:=jsonb_build_object('profile_source','name_profile',
          'authority_precedence','E','sample_count',v_name_profile.sample_count);
      end if;
    end if;
  end if;

  if v_candidate_source is not null and v_decision_found
    and v_decision.authority_status='legacy'
    and coalesce((v_decision_validation->>'valid')::boolean,false)
    and (v_decision.category_code is distinct from v_candidate_category
      or v_decision.detail_code is distinct from v_candidate_detail
      or v_decision.garment_type_code is distinct from v_candidate_garment
      or v_decision.comparison_family is distinct from v_candidate_family
      or v_decision.length_type is distinct from v_candidate_length
      or v_decision_body is distinct from v_candidate_body) then
    v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object(
      'code','complete_legacy_evidence_conflict','candidate_source',v_candidate_source,
      'decision_version',v_decision.decision_version));
  end if;
  if v_candidate_source is not null and jsonb_array_length(v_conflicts)=0 then
    return jsonb_build_object(
      'category_code',v_candidate_category,'detail_code',v_candidate_detail,
      'garment_type_code',v_candidate_garment,'family_code',v_candidate_family,
      'length_code',v_candidate_length,'body_length_code',v_candidate_body,
      'classification_status','confirmed','classification_method',v_candidate_method,
      'authority_status','verified','confidence',0.97,
      'requires_user_confirmation',false,'mapping_release_id',null,
      'decision_version',v_classifier_version,'tuple_validation',v_candidate_validation,
      'authority_conflicts',v_conflicts,'evidence',v_candidate_evidence,
      'classifier_policy_version',v_classifier_version
    );
  end if;

  if v_decision_found and v_decision.authority_status='verified'
    and not coalesce((v_decision_validation->>'valid')::boolean,false) then
    v_reasons:=v_reasons||jsonb_build_array('verified_product_decision_tuple_invalid');
  elsif v_decision_found and v_decision.authority_status='revoked' then
    v_reasons:=v_reasons||jsonb_build_array('exact_product_decision_revoked');
  elsif v_decision_found and v_decision.authority_status='legacy'
    and not coalesce((v_decision_validation->>'valid')::boolean,false) then
    v_reasons:=v_reasons||jsonb_build_array('legacy_decision_non_authority');
  end if;
  if jsonb_array_length(v_conflicts)>0 then
    v_reasons:=v_reasons||jsonb_build_array('authority_conflict_unresolved');
  end if;
  if jsonb_array_length(v_reasons)=0 then
    v_reasons:=jsonb_build_array('no_verified_auto_eligible_authority');
  end if;
  return jsonb_build_object(
    'category_code',null,'detail_code',null,'garment_type_code',null,
    'family_code',null,'length_code',null,'body_length_code',null,
    'classification_status','review_required','classification_method','unknown',
    'authority_status',null,'confidence',null,'requires_user_confirmation',true,
    'mapping_release_id',v_release_id,'decision_version',null,
    'tuple_validation',null,'authority_conflicts',v_conflicts,
    'evidence',jsonb_build_object('unresolved_reasons',v_reasons,
      'mapping_source_identity',case when v_mapping_found then v_mapping.source_identity else null end,
      'mapping_scope',v_mapping_scope,'mapping_tuple_validation',v_mapping_validation,
      'decision_tuple_validation',v_decision_validation,
      'legacy_incomplete_is_audit_only',true),
    'classifier_policy_version',v_classifier_version
  );
end
$function$;

create or replace function
fitmatch_catalog.runtime_classification_db_final_gate_v1(
  p_release_id uuid
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_policy_report jsonb;
  v_structured_count integer;
  v_structured_checksum text;
  v_direct_count integer;
  v_product_required_count integer;
  v_revoked_count integer;
  v_other_scope_count integer;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_release from fitmatch_catalog.releases
  where id=p_release_id;
  if not found then
    raise exception using errcode='P0002',message='release_not_found';
  end if;

  v_policy_report:=fitmatch_catalog.runtime_policy_contract_report_v1(
    p_release_id
  );
  if not coalesce((v_policy_report->>'eligible')::boolean,false) then
    v_blockers:=v_blockers||coalesce(v_policy_report->'blockers','[]'::jsonb);
  end if;

  select count(*),encode(extensions.digest(coalesce(string_agg(
    jsonb_build_object(
      'rule_id',rule_id,'source',source,'key',discriminator_key,
      'value',discriminator_value,'external_category_id',external_category_id,
      'normalized_path',normalized_path,'target',target,'outcome',outcome,
      'category_code',category_code,'detail_code',detail_code,
      'garment_type_code',garment_type_code,'family_code',family_code,
      'length_code',length_code,'body_length_code',body_length_code,
      'exclusion_reason_code',exclusion_reason_code,
      'authority_status',authority_status,'resolution_scope',resolution_scope,
      'runtime_eligible',runtime_eligible,'policy_version',policy_version
    )::text,E'\n' order by rule_id),''),'sha256'),'hex')
  into v_structured_count,v_structured_checksum
  from fitmatch_catalog.classification_structured_discriminator_rules
  where release_id=p_release_id;

  select
    count(*) filter(where lower(coalesce(
      raw_record#>>'{authorityContract,resolutionScope}',
      raw_record->>'resolutionScope',''))='category_direct'),
    count(*) filter(where lower(coalesce(
      raw_record#>>'{authorityContract,resolutionScope}',
      raw_record->>'resolutionScope',''))='product_required'),
    count(*) filter(where lower(coalesce(
      raw_record#>>'{authorityContract,resolutionScope}',
      raw_record->>'resolutionScope',''))='revoked'),
    count(*) filter(where lower(coalesce(
      raw_record#>>'{authorityContract,resolutionScope}',
      raw_record->>'resolutionScope','')) not in (
        'category_direct','product_required','revoked'
      ))
  into v_direct_count,v_product_required_count,v_revoked_count,
    v_other_scope_count
  from fitmatch_catalog.source_category_mappings
  where release_id=p_release_id;

  if v_structured_count<>21
    or nullif(v_release.validation_report->>'structured_discriminator_checksum','')
      is distinct from v_structured_checksum then
    v_blockers:=v_blockers||jsonb_build_array(
      'structured_discriminator_contract_mismatch'
    );
  end if;
  if v_direct_count<>55 or v_product_required_count<>1019
    or v_revoked_count<>2435 or v_other_scope_count<>0 then
    v_blockers:=v_blockers||jsonb_build_array('source_authority_scope_mismatch');
  end if;
  if not (v_release.validation_report @> jsonb_build_object(
    'shadow_product_count',1608,
    'shadow_output_checksum',
      'fa836a5d45c73da135e4c2b5f064b7291b4babbe20f5571ad66eff31cc77c93e',
    'gold_exact_count',3,
    'synthetic_fixture_count',29,
    'confirmed_tuple_invalid_count',0,
    'set_garment_confirmed_count',0,
    'set_comparison_allowed_count',0,
    'arbitrary_unknown_fallback_count',0,
    'closure_validation_passed',true
  )) then
    v_blockers:=v_blockers||jsonb_build_array('closure_evidence_missing');
  end if;

  return jsonb_build_object(
    'eligible',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'policy_contract_report',v_policy_report,
    'structured_discriminator_count',v_structured_count,
    'structured_discriminator_checksum',v_structured_checksum,
    'category_direct_count',v_direct_count,
    'product_required_count',v_product_required_count,
    'revoked_count',v_revoked_count,
    'other_scope_count',v_other_scope_count,
    'activation_performed',false,
    'contract_version','classification-db-final-gate-v1'
  );
end
$function$;

-- Keep the existing v2 activation gate name, but make it understand the final
-- closure bundle and its forward-only rollback successor. The legacy 116 path
-- remains byte-for-byte equivalent in its checks below; no activation path is
-- permitted to fall through without a release-specific evidence contract.
create or replace function fitmatch_catalog.runtime_release_gate_report(
  p_release_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_release fitmatch_catalog.releases%rowtype;
  v_source_release fitmatch_catalog.releases%rowtype;
  v_actual_mapping_count integer;
  v_manifest_count integer;
  v_policy_report jsonb;
  v_artifact_report jsonb;
  v_final_report jsonb;
  v_mapping_checksum text;
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

  if p_release_id = '11800000-0000-4000-8000-000000000118'::uuid then
    if v_release.release_key is distinct from
        'fitmatch-classification-authority-final-candidate-2026-08-26-v1'
      or v_release.validation_contract_version is distinct from
        'fitmatch-release-gate-v2'
      or v_release.status not in ('validated', 'active')
      or v_release.bundle_checksum is distinct from
        'f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be'
      or v_release.app_taxonomy_checksum is distinct from
        'eebfa19d3d38993c00540e44410c8815ada1a0162c7856f9d414105f6d2c5c09'
      or v_release.expected_mapping_count <> 3509
      or v_actual_mapping_count <> 3509
      or v_release.expected_qa_count <> 1608
      or v_release.validated_at is null
    then
      v_blockers := v_blockers ||
        jsonb_build_array('final_release_identity_or_cardinality_mismatch');
    end if;

    select count(*) into v_manifest_count
    from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1();
    if v_manifest_count <> 121
      or not (v_release.validation_report @> jsonb_build_object(
        'manifest_checksum',
          'f21e61545f194347aec02f620daefc9ea5dd56645fd1b9a77b0bc56f897163be',
        'source_mapping_count',3509,
        'structured_discriminator_rule_count',21,
        'targeted_decision_count',121,
        'verified_path_profile_count',12,
        'verified_name_profile_count',0,
        'verified_exclusion_profile_count',15,
        'shadow_product_count',1608,
        'shadow_output_checksum',
          'fa836a5d45c73da135e4c2b5f064b7291b4babbe20f5571ad66eff31cc77c93e',
        'confirmed_count',348,
        'review_required_count',1113,
        'not_comparable_count',147,
        'gold_exact_count',3,
        'synthetic_fixture_count',29,
        'confirmed_tuple_invalid_count',0,
        'set_garment_confirmed_count',0,
        'set_comparison_allowed_count',0,
        'revoked_mapping_authority_leak_count',0,
        'invalid_mapping_authority_leak_count',0,
        'product_required_mapping_alone_confirmed_count',0,
        'both_untrusted_unsafe_confirmed_count',0,
        'unverified_name_confirmed_count',0,
        'unverified_path_confirmed_count',0,
        'arbitrary_unknown_fallback_count',0,
        'existing_confirmed_unintended_regression_count',0,
        'future_fixture_passed',true,
        'closure_validation_passed',true,
        'runtime_policy_contract_validated',true,
        'production_write_count',0
      ))
      or v_release.validation_report->>'targeted_decision_checksum'
        is distinct from
          '04d176e0e451f45604e12384a959b617eb90abb0e2775ff0d6a3afc565830ac2'
    then
      v_blockers := v_blockers ||
        jsonb_build_array('final_release_evidence_mismatch');
    end if;

    v_final_report :=
      fitmatch_catalog.runtime_classification_db_final_gate_v1(p_release_id);
    if not coalesce((v_final_report->>'eligible')::boolean,false) then
      v_blockers := v_blockers ||
        coalesce(v_final_report->'blockers','[]'::jsonb);
    end if;

    return jsonb_build_object(
      'contract_version','fitmatch-release-gate-v2+db-final-closure-v1',
      'release_id',v_release.id,
      'release_key',v_release.release_key,
      'eligible',jsonb_array_length(v_blockers)=0,
      'blockers',v_blockers,
      'expected_mapping_count',v_release.expected_mapping_count,
      'actual_mapping_count',v_actual_mapping_count,
      'expected_qa_count',v_release.expected_qa_count,
      'targeted_decision_manifest_count',v_manifest_count,
      'final_closure_gate',v_final_report
    );
  end if;

  if coalesce((v_release.metadata->>'rollback_successor')::boolean,false) then
    select encode(extensions.digest(coalesce(string_agg(jsonb_build_object(
      'source_identity',mapping.source_identity,
      'source',mapping.source,
      'snapshot_id',mapping.snapshot_id,
      'external_category_id',mapping.external_category_id,
      'target',mapping.target,
      'normalized_path',mapping.normalized_path,
      'decision_status',mapping.decision_status,
      'mapping_status',mapping.mapping_status,
      'runtime_lookup_eligible',mapping.runtime_lookup_eligible,
      'eligibility',mapping.eligibility,
      'semantic_category_code',mapping.semantic_category_code,
      'semantic_garment_type',mapping.semantic_garment_type,
      'comparison_family',mapping.comparison_family,
      'source_external_key',mapping.source_external_key,
      'source_external_target_key',mapping.source_external_target_key,
      'source_path_key',mapping.source_path_key,
      'source_target_path_key',mapping.source_target_path_key,
      'raw_record',mapping.raw_record
    )::text,E'\n' order by mapping.source_identity),''),'sha256'),'hex')
    into v_mapping_checksum
    from fitmatch_catalog.source_category_mappings mapping
    where mapping.release_id=p_release_id;

    select * into v_source_release
    from fitmatch_catalog.releases
    where id=(v_release.metadata->>'source_release_id')::uuid;

    if not found
      or v_release.validation_contract_version is distinct from
        'fitmatch-release-gate-v2'
      or v_release.status not in ('validated','active')
      or v_release.validated_at is null
      or v_release.expected_mapping_count <= 0
      or v_actual_mapping_count <> v_release.expected_mapping_count
      or v_release.expected_qa_count <> 1608
      or v_release.bundle_checksum is distinct from
        v_source_release.bundle_checksum
      or v_release.app_taxonomy_checksum is distinct from
        v_source_release.app_taxonomy_checksum
      or v_release.taxonomy_version is distinct from
        v_source_release.taxonomy_version
      or v_release.policy_version is distinct from
        v_source_release.policy_version
      or v_mapping_checksum is distinct from
        v_release.validation_report->>'source_mapping_checksum'
      or v_release.validation_report->>'source_bundle_checksum'
        is distinct from v_source_release.bundle_checksum
      or v_release.validation_report->>'source_app_taxonomy_checksum'
        is distinct from v_source_release.app_taxonomy_checksum
      or not (v_release.validation_report @> jsonb_build_object(
        'rollback_successor_validated',true,
        'rollback_dry_run_passed',true,
        'shadow_product_count',1608,
        'gold_exact_count',3,
        'set_garment_confirmed_count',0,
        'set_comparison_allowed_count',0,
        'safety_leak_count',0,
        'history_write_count',0,
        'history_delete_count',0
      ))
      or btrim(coalesce(v_release.validation_report->>
        'function_bundle_preimage_checksum',''))=''
    then
      v_blockers := v_blockers ||
        jsonb_build_array('rollback_successor_preimage_or_validation_mismatch');
    end if;

    return jsonb_build_object(
      'contract_version','fitmatch-release-gate-v2+rollback-successor-v1',
      'release_id',v_release.id,
      'release_key',v_release.release_key,
      'eligible',jsonb_array_length(v_blockers)=0,
      'blockers',v_blockers,
      'expected_mapping_count',v_release.expected_mapping_count,
      'actual_mapping_count',v_actual_mapping_count,
      'expected_qa_count',v_release.expected_qa_count,
      'source_release_id',v_source_release.id,
      'source_mapping_checksum',v_mapping_checksum
    );
  end if;

  -- Preserve the pre-closure v2 candidate gate for all other releases.
  if v_release.validation_contract_version
      is distinct from 'fitmatch-release-gate-v2' then
    v_blockers := v_blockers ||
      jsonb_build_array('validation_contract_missing_or_unsupported');
  end if;
  if btrim(coalesce(v_release.bundle_checksum,''))='' then
    v_blockers := v_blockers || jsonb_build_array('bundle_checksum_missing');
  end if;
  if btrim(coalesce(v_release.app_taxonomy_checksum,''))='' then
    v_blockers := v_blockers ||
      jsonb_build_array('app_taxonomy_checksum_missing');
  end if;
  if v_release.validated_at is null then
    v_blockers := v_blockers || jsonb_build_array('release_not_validated');
  end if;
  if coalesce(v_release.expected_mapping_count,0)<=0
    or v_actual_mapping_count<>coalesce(v_release.expected_mapping_count,-1)
  then
    v_blockers := v_blockers || jsonb_build_array('mapping_count_mismatch');
  end if;
  if coalesce(v_release.expected_qa_count,0)<=0 then
    v_blockers := v_blockers ||
      jsonb_build_array('qa_fixture_count_missing');
  end if;
  if not (v_release.validation_report @>
      '{"qa_full_validation_included":true}'::jsonb) then
    v_blockers := v_blockers || jsonb_build_array('full_qa_not_included');
  end if;
  if not (v_release.validation_report @>
      '{"core_regression_passed":true}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('core_regression_not_passed');
  end if;
  if not (v_release.validation_report @>
      '{"current_behavior_parity_passed":true}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('current_behavior_parity_not_passed');
  end if;
  if not (v_release.validation_report @>
      '{"production_identity_verified":true}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('product_identity_not_verified');
  end if;
  if not (v_release.validation_report @>
      '{"label_sample_sufficiency_passed":true}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('independent_label_sample_insufficient');
  end if;
  if not (v_release.validation_report @>
      '{"unsafe_auto_accept_count":0}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('unsafe_auto_accept_present');
  end if;
  if not (v_release.validation_report @>
      '{"classification_conflict_leak_count":0}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('classification_conflict_leak_present');
  end if;
  if not (v_release.validation_report @>
      '{"measurement_alias_conflict_count":0}'::jsonb) then
    v_blockers := v_blockers ||
      jsonb_build_array('measurement_alias_conflict_present');
  end if;

  v_policy_report :=
    fitmatch_catalog.runtime_policy_contract_report_v1(p_release_id);
  v_artifact_report :=
    fitmatch_catalog.runtime_classification_candidate_artifact_report_v1(
      p_release_id
    );
  v_blockers := v_blockers
    || coalesce(v_policy_report->'blockers','[]'::jsonb)
    || coalesce(v_artifact_report->'blockers','[]'::jsonb);

  if not (v_release.validation_report @>
      '{"source_mapping_count":3492,"targeted_decision_count":114,"shadow_product_count":1608,"gold_exact_count":3,"gold_collision_count":0,"confirmed_tuple_invalid_count":0,"unsafe_product_required_confirm_count":0,"unsafe_invalid_mapping_confirm_count":0,"both_untrusted_unsafe_confirm_count":0}'::jsonb)
  then
    v_blockers := v_blockers ||
      jsonb_build_array('classification_candidate_qa_incomplete');
  end if;

  return jsonb_build_object(
    'contract_version','fitmatch-release-gate-v2',
    'release_id',v_release.id,
    'release_key',v_release.release_key,
    'eligible',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'expected_mapping_count',v_release.expected_mapping_count,
    'actual_mapping_count',v_actual_mapping_count,
    'expected_qa_count',v_release.expected_qa_count,
    'runtime_policy_contract',v_policy_report,
    'candidate_artifacts',v_artifact_report
  );
end
$function$;

revoke all on function
  fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
  from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    text,text,text,text,jsonb,uuid
  ) from public, anon, authenticated;
revoke all on function
  fitmatch_catalog.runtime_classification_db_final_gate_v1(uuid)
  from public, anon, authenticated;
revoke all on function fitmatch_catalog.runtime_release_gate_report(uuid)
  from public, anon, authenticated;
grant execute on function
  fitmatch_catalog.runtime_classification_db_final_manifest_v1()
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
  to service_role;
grant execute on function
  fitmatch_catalog.runtime_resolve_product_classification_v4(
    text,text,text,text,jsonb,uuid
  ) to service_role;
grant execute on function
  fitmatch_catalog.runtime_classification_db_final_gate_v1(uuid)
  to service_role;
grant execute on function fitmatch_catalog.runtime_release_gate_report(uuid)
  to service_role;

update fitmatch_catalog.releases
set validation_report = validation_report || jsonb_build_object(
  'source_mapping_count',(
    select count(*) from fitmatch_catalog.source_category_mappings
    where release_id='11800000-0000-4000-8000-000000000118'::uuid
  ),
  'structured_discriminator_rule_count',(
    select count(*)
    from fitmatch_catalog.classification_structured_discriminator_rules
    where release_id='11800000-0000-4000-8000-000000000118'::uuid
      and runtime_eligible and authority_status='verified'
  ),
  'targeted_decision_count',(
    select count(*)
    from fitmatch_catalog.runtime_classification_db_final_decision_manifest_v1()
  ),
  'verified_path_profile_count',(
    select count(*) from fitmatch_catalog.classification_path_profiles
    where policy_version='db-classifier-2026-08-26-final'
      and auto_eligible
  ),
  'verified_name_profile_count',(
    select count(*) from fitmatch_catalog.classification_name_profiles
    where policy_version='db-classifier-2026-08-26-final'
      and auto_eligible
  ),
  'verified_exclusion_profile_count',(
    select count(*) from fitmatch_catalog.classification_exclusion_profiles
    where policy_version='db-classifier-2026-08-26-final'
      and auto_eligible
  ),
  'shadow_product_count',1608,
  'shadow_output_checksum',
    'fa836a5d45c73da135e4c2b5f064b7291b4babbe20f5571ad66eff31cc77c93e',
  'confirmed_count',348,
  'review_required_count',1113,
  'not_comparable_count',147,
  'comparison_possible_count',179,
  'insufficient_measurements_count',169,
  'gold_exact_count',3,
  'synthetic_fixture_count',29,
  'confirmed_tuple_invalid_count',0,
  'set_garment_confirmed_count',0,
  'set_comparison_allowed_count',0,
  'revoked_mapping_authority_leak_count',0,
  'invalid_mapping_authority_leak_count',0,
  'product_required_mapping_alone_confirmed_count',0,
  'both_untrusted_unsafe_confirmed_count',0,
  'unverified_name_confirmed_count',0,
  'unverified_path_confirmed_count',0,
  'arbitrary_unknown_fallback_count',0,
  'existing_confirmed_intentional_safety_downgrade_count',8,
  'existing_confirmed_unintended_regression_count',0,
  'future_fixture_passed',true,
  'closure_validation_passed',true,
  'production_write_count',0,
  'production_activation_performed',false
)
where id='11800000-0000-4000-8000-000000000118'::uuid;

commit;
