
 create index source_category_mappings_sleeve_class_idx
   on public.source_category_mappings(default_sleeve_class_code)
   where default_sleeve_class_code is not null;
 create index source_category_mappings_pants_length_idx
   on public.source_category_mappings(default_pants_length_code)
   where default_pants_length_code is not null;
 create index source_category_mappings_body_length_idx
   on public.source_category_mappings(default_body_length_code)
   where default_body_length_code is not null;
 ;
