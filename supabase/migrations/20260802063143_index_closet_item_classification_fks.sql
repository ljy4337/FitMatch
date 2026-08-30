
create index closet_items_garment_type_fk_idx
  on public.closet_items(garment_type_id)
  where garment_type_id is not null;

create index closet_items_sleeve_length_fk_idx
  on public.closet_items(sleeve_length_class_code)
  where sleeve_length_class_code is not null;

create index closet_items_pants_length_fk_idx
  on public.closet_items(pants_length_class_code)
  where pants_length_class_code is not null;

create index closet_items_body_length_fk_idx
  on public.closet_items(body_length_class_code)
  where body_length_class_code is not null;
;
