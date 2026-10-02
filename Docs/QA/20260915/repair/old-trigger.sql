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
