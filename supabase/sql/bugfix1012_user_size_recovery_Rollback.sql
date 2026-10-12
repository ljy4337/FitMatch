-- PROPOSAL ONLY. Refuses rollback after user receipts or results exist; never deletes user data.
begin;
do $guard$
declare r record;
begin
 if exists(select 1 from fitmatch_vnext.user_size_recoveries)
 or exists(select 1 from fitmatch_vnext.comparisons where recommended_user_recovery_size_id is not null) then
  raise exception 'Recovery rollback blocked: preserve accepted user receipts and comparison identities';
 end if;
 for r in select * from fitmatch_vnext.bugfix1012_recovery_backups
 where object_signature<>'comparisons_recommended_authority_chk' loop
  if pg_get_functiondef(r.object_signature::regprocedure) is distinct from r.applied_definition then
   raise exception 'Recovery rollback blocked: function changed since Apply: %',r.object_signature;
  end if;
 end loop;
end $guard$;
do $restore$
declare r record;
begin
 for r in select * from fitmatch_vnext.bugfix1012_recovery_backups
 where object_signature not in ('comparisons_recommended_authority_chk','fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)') loop execute r.definition; end loop;
 execute 'drop function fitmatch_vnext.canonical_measurements_for_size_with_context(uuid,jsonb)';
 execute 'alter function fitmatch_vnext.canonical_measurements_for_size_with_context_before_user_recovery(uuid,jsonb) rename to canonical_measurements_for_size_with_context';
 select * into r from fitmatch_vnext.bugfix1012_recovery_backups where object_signature='comparisons_recommended_authority_chk';
 execute 'alter table fitmatch_vnext.comparisons drop constraint comparisons_recommended_authority_chk';
 execute 'alter table fitmatch_vnext.comparisons add constraint comparisons_recommended_authority_chk '||r.definition;
end $restore$;
drop trigger validate_recommended_user_recovery on fitmatch_vnext.comparisons;
drop function fitmatch_vnext.validate_recommended_user_recovery();
alter table fitmatch_vnext.comparisons drop constraint comparisons_single_recommended_identity_chk;
alter table fitmatch_vnext.comparisons drop column recommended_user_recovery_size_id;
drop function public.fitmatch_vnext_save_user_size_recovery(jsonb),public.fitmatch_vnext_get_user_size_recovery(uuid);
drop function fitmatch_vnext.save_user_size_recovery(jsonb),fitmatch_vnext.get_user_size_recovery(uuid),
 fitmatch_vnext.user_size_recovery_metadata(uuid),fitmatch_vnext.comparison_product_sizes(boolean);
drop function fitmatch_vnext.user_size_recovery_receipt(fitmatch_vnext.user_size_recoveries);
drop table fitmatch_vnext.active_user_size_recoveries;
drop table fitmatch_vnext.user_size_recoveries;
drop function fitmatch_vnext.protect_user_size_recovery();
drop table fitmatch_vnext.bugfix1012_recovery_backups;
commit;
