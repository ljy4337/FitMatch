begin;
-- Recovery is scoped to this canonical schema and never touches legacy public data.
drop schema if exists fitmatch_taxonomy cascade;
commit;
