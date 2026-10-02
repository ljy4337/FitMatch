create schema fitmatch_vnext;
create schema fitmatch_catalog;
create table fitmatch_vnext.garment_types(garment_type_code text primary key,is_active boolean,uses_sleeve_length boolean,uses_lower_length boolean,uses_body_length boolean);
insert into fitmatch_vnext.garment_types values ('slacks_trousers',true,false,true,false),('tshirt',true,true,false,false),('coat',true,true,false,true),('inactive',false,false,false,false);
create table fitmatch_vnext.products(garment_type_code text,classification_status text,sleeve_length_code text,lower_length_code text,body_length_code text,product_structure_code text,audience_code text);
create table fitmatch_vnext.closet_items(like fitmatch_vnext.products);
create table fitmatch_catalog.source_category_comparison_groups(policy_version text,source_code text,source_category_key text,group_code text,disposition text,category_path text[],source_ids jsonb,source_names jsonb,audience_codes text[],product_count int,sample_products jsonb,mapping_basis text,notes text[],source_record jsonb,unique(policy_version,source_code,source_category_key,group_code));
CREATE OR REPLACE FUNCTION fitmatch_vnext.validate_garment_axis_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    gt fitmatch_vnext.garment_types%rowtype;
    enforce_complete boolean := false;
    structure_code text;
    audience text;
begin
    if new.garment_type_code is null then
        if tg_table_name = 'products'
           and new.classification_status = 'CONFIRMED' then
            raise exception 'CONFIRMED product requires garment_type_code';
        end if;
        return new;
    end if;

    select * into gt
    from fitmatch_vnext.garment_types
    where garment_type_code = new.garment_type_code;

    if not found or not gt.is_active then
        raise exception 'Unknown or inactive garment_type_code %',
            new.garment_type_code;
    end if;
    if not gt.uses_sleeve_length and new.sleeve_length_code is not null then
        raise exception 'garment_type % does not use sleeve_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_lower_length and new.lower_length_code is not null then
        raise exception 'garment_type % does not use lower_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_body_length and new.body_length_code is not null then
        raise exception 'garment_type % does not use body_length_code',
            new.garment_type_code;
    end if;

    if tg_table_name = 'products' then
        enforce_complete := new.classification_status = 'CONFIRMED';
        structure_code := upper(coalesce(
            new.product_structure_code,
            'UNKNOWN'
        ));
        audience := new.audience_code;
    elsif tg_table_name = 'closet_items' then
        enforce_complete := true;
        structure_code := 'SINGLE';
        audience := new.audience_code;
    end if;

    if enforce_complete then
        if structure_code = 'SET'
           or structure_code not in ('SINGLE', 'MULTIPACK', 'UNKNOWN') then
            raise exception 'comparable classification requires an eligible product structure';
        end if;
        if audience is null or audience = 'UNKNOWN' then
            raise exception 'comparable classification requires known audience_code';
        end if;
        if gt.uses_sleeve_length
           and (
               new.sleeve_length_code is null
               or new.sleeve_length_code = 'UNKNOWN'
           ) then
            raise exception 'garment_type % requires a known sleeve_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_lower_length
           and (
               new.lower_length_code is null
               or new.lower_length_code = 'UNKNOWN'
           ) then
            raise exception 'garment_type % requires a known lower_length_code',
                new.garment_type_code;
        end if;
        if gt.uses_body_length
           and (
               new.body_length_code is null
               or new.body_length_code = 'UNKNOWN'
           ) then
            raise exception 'garment_type % requires a known body_length_code',
                new.garment_type_code;
        end if;
    end if;

    return new;
end
$function$
;
create trigger axes before insert on fitmatch_vnext.products for each row execute function fitmatch_vnext.validate_garment_axis_values();
create trigger axes before insert on fitmatch_vnext.closet_items for each row execute function fitmatch_vnext.validate_garment_axis_values();
do $$ begin
  begin
    insert into fitmatch_vnext.products values ('slacks_trousers','CONFIRMED',null,null,null,'SINGLE','MEN');
    raise exception 'Old trigger unexpectedly accepted missing length';
  exception when raise_exception then
    if sqlerrm not like '%requires a known lower_length_code%' then raise; end if;
  end;
end $$;
-- Group-only comparison does not require legacy length-axis facts.
begin;

-- Refuse to overwrite a concurrently changed trigger definition.
do $guard$
begin
  if md5(pg_get_functiondef('fitmatch_vnext.validate_garment_axis_values()'::regprocedure))
     <> '1eaf0cf9b69756335862218f770bb1f0' then
    raise exception 'Unexpected garment-axis trigger definition; re-audit before applying';
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION fitmatch_vnext.validate_garment_axis_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    gt fitmatch_vnext.garment_types%rowtype;
    enforce_complete boolean := false;
    structure_code text;
    audience text;
begin
    if new.garment_type_code is null then
        if tg_table_name = 'products'
           and new.classification_status = 'CONFIRMED' then
            raise exception 'CONFIRMED product requires garment_type_code';
        end if;
        return new;
    end if;

    select * into gt
    from fitmatch_vnext.garment_types
    where garment_type_code = new.garment_type_code;

    if not found or not gt.is_active then
        raise exception 'Unknown or inactive garment_type_code %',
            new.garment_type_code;
    end if;
    if not gt.uses_sleeve_length and new.sleeve_length_code is not null then
        raise exception 'garment_type % does not use sleeve_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_lower_length and new.lower_length_code is not null then
        raise exception 'garment_type % does not use lower_length_code',
            new.garment_type_code;
    end if;
    if not gt.uses_body_length and new.body_length_code is not null then
        raise exception 'garment_type % does not use body_length_code',
            new.garment_type_code;
    end if;

    if tg_table_name = 'products' then
        enforce_complete := new.classification_status = 'CONFIRMED';
        structure_code := upper(coalesce(
            new.product_structure_code,
            'UNKNOWN'
        ));
        audience := new.audience_code;
    elsif tg_table_name = 'closet_items' then
        enforce_complete := true;
        structure_code := 'SINGLE';
        audience := new.audience_code;
    end if;

    if enforce_complete then
        if structure_code = 'SET'
           or structure_code not in ('SINGLE', 'MULTIPACK', 'UNKNOWN') then
            raise exception 'comparable classification requires an eligible product structure';
        end if;
        if audience is null or audience = 'UNKNOWN' then
            raise exception 'comparable classification requires known audience_code';
        end if;
    end if;

    return new;
end
$function$;

insert into fitmatch_catalog.source_category_comparison_groups(
  policy_version,source_code,source_category_key,group_code,disposition,
  category_path,source_ids,source_names,audience_codes,product_count,
  sample_products,mapping_basis,notes,source_record
) values (
  'retailer-comparison-groups-v3-seven-20260911','musinsa',
  'musinsa-path:바지:슈트 팬츠/슬랙스','C','COMPARABLE',
  array['바지','슈트 팬츠/슬랙스'],'{}'::jsonb,
  jsonb_build_object('depth1','바지','depth2','슈트 팬츠/슬랙스'),
  array['MEN'],1,
  '[{"product_id":"5746364"}]'::jsonb,
  'EXACT_RETAILER_CATEGORY_PATH',
  array['Official pants path; no length-axis inference'],
  jsonb_build_object('source_category_path','바지 > 슈트 팬츠/슬랙스')
)
on conflict(policy_version,source_code,source_category_key,group_code) do nothing;

commit;

insert into fitmatch_vnext.products values ('slacks_trousers','CONFIRMED',null,null,null,'SINGLE','MEN'),('slacks_trousers','CONFIRMED',null,'UNKNOWN',null,'SINGLE','MEN'),('tshirt','CONFIRMED',null,null,null,'SINGLE','MEN'),('coat','CONFIRMED',null,null,null,'SINGLE','MEN');
insert into fitmatch_vnext.closet_items values ('slacks_trousers',null,null,null,null,null,'MEN');
do $$ declare entry record; begin
  for entry in select * from (values ('inactive',null::text,'MEN','SINGLE','Unknown or inactive'),('slacks_trousers','LONG','MEN','SINGLE','does not use sleeve'),('slacks_trousers',null,'UNKNOWN','SINGLE','known audience'),('slacks_trousers',null,'MEN','SET','eligible product structure')) as t(garment,sleeve,audience,structure,message) loop
    begin
      insert into fitmatch_vnext.products values(entry.garment,'CONFIRMED',entry.sleeve,null,null,entry.structure,entry.audience);
      raise exception 'Invalid input unexpectedly accepted';
    exception when raise_exception then
      if position(entry.message in sqlerrm)=0 then raise; end if;
    end;
  end loop;
  if (select count(*) from fitmatch_vnext.products) <> 4 then raise exception 'Wrong product count'; end if;
  if (select count(*) from fitmatch_catalog.source_category_comparison_groups where group_code='C') <> 1 then raise exception 'Mapping missing'; end if;
end $$;
select 'AXIS_REGRESSION_PASS' as result;
