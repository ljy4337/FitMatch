-- CONTROLLED PRODUCTION ROLLBACK ARTIFACT.
-- Resolver preimage restoration and rollback-successor activation are atomic.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';

select pg_advisory_xact_lock(hashtext('fitmatch:release-activation'));
select pg_advisory_xact_lock(
  hashtext('fitmatch:classification-audience-scope-2026-08-27-v1')
);

create temporary table fitmatch_120_rollback_guard on commit drop as
select
  (select count(*) from fitmatch_catalog.product_classification_history)
    history_count,
  (select count(*) from fitmatch_catalog.product_classification_history
    where is_current) current_history_count,
  encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex') resolver_checksum,
  procedure.proowner resolver_owner,
  procedure.proacl resolver_acl,
  procedure.prosecdef resolver_security_definer,
  procedure.proconfig resolver_config
from pg_catalog.pg_proc procedure
where procedure.oid=
  'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
    ::regprocedure;

select 1
from fitmatch_catalog.releases
where id in (
  '12000000-0000-4000-8000-000000000120'::uuid,
  '12000000-0000-4000-8000-00000000b001'::uuid
)
for update;

do $preflight$
declare v_candidate jsonb; v_successor jsonb;
begin
  v_candidate:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-000000000120'::uuid
  );
  v_successor:=fitmatch_catalog.runtime_release_gate_report(
    '12000000-0000-4000-8000-00000000b001'::uuid
  );

  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '12000000-0000-4000-8000-000000000120'::uuid
    or (select status from fitmatch_catalog.releases
        where id='12000000-0000-4000-8000-00000000b001'::uuid)<>'validated'
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id='12000000-0000-4000-8000-000000000120'::uuid)<>3510
    or (select resolver_checksum from fitmatch_120_rollback_guard)<>
      '3e99c584285b249c9adca76e1b8c0c8b68ec3f10f38dced306e392ef4a48b604'
    or not coalesce((v_candidate->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_candidate->'blockers','[]'::jsonb))<>0
    or not coalesce((v_successor->>'eligible')::boolean,false)
    or jsonb_array_length(coalesce(v_successor->'blockers','[]'::jsonb))<>0
  then
    raise exception
      '120_atomic_rollback_preflight_failed:candidate=%,successor=%,resolver=%',
      v_candidate,v_successor,
      (select resolver_checksum from fitmatch_120_rollback_guard);
  end if;
end
$preflight$;

-- Restore the exact resolver definition captured by the candidate-only
-- migration before activation. Reverse text transformation is intentionally
-- avoided: semantically equivalent formatting is not an exact preimage.
do $resolver_restore$
declare
  v_definition text;
  v_checksum text;
begin
  select validation_report->>'resolver_preimage_definition'
  into v_definition
  from fitmatch_catalog.releases
  where id='12000000-0000-4000-8000-00000000b001'::uuid;

  v_checksum:=encode(extensions.digest(coalesce(v_definition,''),'sha256'),'hex');
  if v_definition is null or v_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
  then
    raise exception '120_rollback_resolver_preimage_artifact_mismatch:%',v_checksum;
  end if;

  execute v_definition;
end
$resolver_restore$;

do $resolver_preimage_restored$
declare
  v_checksum text;
  v_owner oid;
  v_acl aclitem[];
  v_security_definer boolean;
  v_config text[];
begin
  select encode(extensions.digest(pg_get_functiondef(procedure.oid),
      'sha256'),'hex'),procedure.proowner,procedure.proacl,
    procedure.prosecdef,procedure.proconfig
  into v_checksum,v_owner,v_acl,v_security_definer,v_config
  from pg_catalog.pg_proc procedure
  where procedure.oid=
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure;

  if v_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
    or v_owner is distinct from
      (select resolver_owner from fitmatch_120_rollback_guard)
    or v_acl is distinct from
      (select resolver_acl from fitmatch_120_rollback_guard)
    or v_security_definer is distinct from
      (select resolver_security_definer from fitmatch_120_rollback_guard)
    or v_config is distinct from
      (select resolver_config from fitmatch_120_rollback_guard)
  then
    raise exception
      '120_resolver_preimage_restore_failed:checksum=%,owner=%,acl=%,security=%,config=%',
      v_checksum,v_owner,v_acl,v_security_definer,v_config;
  end if;
end
$resolver_preimage_restored$;

select fitmatch_catalog.runtime_activate_validated_release(
  '12000000-0000-4000-8000-00000000b001'::uuid
);

do $postcondition$
declare v_checksum text;
begin
  select encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex') into v_checksum;

  if (select count(*) from fitmatch_catalog.releases where status='active')<>1
    or (select id from fitmatch_catalog.releases where status='active')<>
      '12000000-0000-4000-8000-00000000b001'::uuid
    or (select count(*) from fitmatch_catalog.source_category_mappings
        where release_id=(select id from fitmatch_catalog.releases
          where status='active'))<>3509
    or v_checksum<>
      'b5ab26e1cfab6787f0c3397d40317a64b9c3ce9e02156ebcd9e9be592f87ec21'
    or (select count(*) from fitmatch_catalog.product_classification_history)<>
      (select history_count from fitmatch_120_rollback_guard)
    or (select count(*) from fitmatch_catalog.product_classification_history
        where is_current)<>
      (select current_history_count from fitmatch_120_rollback_guard)
  then
    raise exception
      '120_atomic_rollback_release_resolver_or_history_postcondition_failed:%',
      v_checksum;
  end if;
end
$postcondition$;

select jsonb_build_object(
  'atomic_rollback','PASS',
  'active_release_id',
    (select id from fitmatch_catalog.releases where status='active'),
  'active_mapping_count',
    (select count(*) from fitmatch_catalog.source_category_mappings
      where release_id=(select id from fitmatch_catalog.releases
        where status='active')),
  'resolver_postimage_checksum',
    (select resolver_checksum from fitmatch_120_rollback_guard),
  'resolver_rollback_checksum',encode(extensions.digest(pg_get_functiondef(
    'fitmatch_catalog.runtime_resolve_product_classification_v4(text,text,text,text,jsonb,uuid)'
      ::regprocedure
  ),'sha256'),'hex'),
  'history_write_count',0,
  'history_delete_count',0
) rollback_result;

commit;
