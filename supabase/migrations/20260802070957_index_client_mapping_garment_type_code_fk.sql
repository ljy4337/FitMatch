create index client_source_category_mappings_garment_type_code_fk_idx
         on public.client_source_category_mappings(garment_type_code)
         where garment_type_code is not null;;
