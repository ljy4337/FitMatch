-- fitmatch_vnext P0-1/P0-2: deterministic mapping contract.

alter table fitmatch_vnext.classification_signal_mappings
    add column if not exists mapping_version text not null default 'vnext-mapping-v1',
    add column if not exists mapping_checksum text;

update fitmatch_vnext.classification_signal_mappings m
set mapping_checksum = encode(extensions.digest(
    concat_ws('|', m.source_signal_id::text, m.audience_code,
        m.resolution_mode, coalesce(m.garment_type_code, '∅'),
        coalesce(m.sleeve_length_code, '∅'), coalesce(m.lower_length_code, '∅'),
        coalesce(m.body_length_code, '∅'), m.priority::text,
        m.is_verified::text, m.is_active::text, m.mapping_version),
    'sha256'), 'hex')
where m.mapping_checksum is null;

alter table fitmatch_vnext.classification_signal_mappings
    alter column mapping_checksum set not null;

create table if not exists fitmatch_vnext.mapping_remediation_audit (
    id bigint generated always as identity primary key,
    mapping_id uuid not null references fitmatch_vnext.classification_signal_mappings(id) on delete restrict,
    remediation_version text not null,
    old_outcome jsonb not null,
    new_state jsonb not null,
    resolution_reason text not null,
    applied_at timestamptz not null default now(),
    unique (mapping_id, remediation_version)
);

alter table fitmatch_vnext.mapping_remediation_audit enable row level security;
revoke all on table fitmatch_vnext.mapping_remediation_audit from public, anon, authenticated;
grant select, insert on table fitmatch_vnext.mapping_remediation_audit to service_role;

create or replace function fitmatch_vnext.validate_classification_mapping()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
    gt fitmatch_vnext.garment_types%rowtype;
begin
    new.mapping_checksum := encode(extensions.digest(
        concat_ws('|', new.source_signal_id::text, new.audience_code,
            new.resolution_mode, coalesce(new.garment_type_code, '∅'),
            coalesce(new.sleeve_length_code, '∅'), coalesce(new.lower_length_code, '∅'),
            coalesce(new.body_length_code, '∅'), new.priority::text,
            new.is_verified::text, new.is_active::text, new.mapping_version),
        'sha256'), 'hex');

    if new.resolution_mode = 'NOT_APPLICABLE' and
       (new.garment_type_code is not null or new.sleeve_length_code is not null
        or new.lower_length_code is not null or new.body_length_code is not null) then
        raise exception 'NOT_APPLICABLE mapping cannot carry a garment tuple';
    end if;

    if not (new.is_active and new.is_verified and new.resolution_mode = 'DIRECT') then
        return new;
    end if;

    if new.garment_type_code is null then
        raise exception 'DIRECT mapping requires garment_type_code';
    end if;

    select * into gt
    from fitmatch_vnext.garment_types
    where garment_type_code = new.garment_type_code and is_active;

    if not found then
        raise exception 'DIRECT mapping references an unknown or inactive garment_type_code %',
            new.garment_type_code;
    end if;

    if gt.uses_sleeve_length and
       (new.sleeve_length_code is null or new.sleeve_length_code = 'UNKNOWN') then
        raise exception 'DIRECT mapping for % requires sleeve_length_code', new.garment_type_code;
    elsif not gt.uses_sleeve_length and new.sleeve_length_code is not null then
        raise exception 'DIRECT mapping for % cannot use sleeve_length_code', new.garment_type_code;
    end if;

    if gt.uses_lower_length and
       (new.lower_length_code is null or new.lower_length_code = 'UNKNOWN') then
        raise exception 'DIRECT mapping for % requires lower_length_code', new.garment_type_code;
    elsif not gt.uses_lower_length and new.lower_length_code is not null then
        raise exception 'DIRECT mapping for % cannot use lower_length_code', new.garment_type_code;
    end if;

    if gt.uses_body_length and
       (new.body_length_code is null or new.body_length_code = 'UNKNOWN') then
        raise exception 'DIRECT mapping for % requires body_length_code', new.garment_type_code;
    elsif not gt.uses_body_length and new.body_length_code is not null then
        raise exception 'DIRECT mapping for % cannot use body_length_code', new.garment_type_code;
    end if;

    return new;
end
$function$;

drop trigger if exists classification_signal_mappings_validate_contract
    on fitmatch_vnext.classification_signal_mappings;
create trigger classification_signal_mappings_validate_contract
before insert or update on fitmatch_vnext.classification_signal_mappings
for each row execute function fitmatch_vnext.validate_classification_mapping();

create index if not exists classification_signal_mappings_resolver_idx
    on fitmatch_vnext.classification_signal_mappings
        (source_signal_id, audience_code, priority desc, id)
    where is_active and is_verified;

revoke all on function fitmatch_vnext.validate_classification_mapping()
    from public, anon, authenticated;
;
