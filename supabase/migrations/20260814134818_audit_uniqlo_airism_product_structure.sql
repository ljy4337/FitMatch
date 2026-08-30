begin;
create temporary table airism_classification_corrections (
  product_id text primary key, category_code text not null, detail_code text not null, comparison_family text not null
) on commit drop;
insert into airism_classification_corrections values
('E473944','underwear','women_panty','underwear'),('E473945','underwear','women_panty','underwear'),
('E478656','underwear','men_briefs','underwear'),('E480785','underwear','women_panty','underwear'),
('E481036','underwear','women_panty','underwear'),('E482006','underwear','women_bra','underwear'),
('E482015','underwear','women_panty','underwear'),('E482154','underwear','women_panty','underwear'),
('E482514','underwear','underwear','underwear'),('E482565','underwear','men_briefs','underwear'),
('E484940','underwear','women_panty','underwear'),('E484997','underwear','men_briefs','underwear'),
('E465193','tops','long_sleeve','tshirt'),('E474832','tops','long_sleeve','tshirt'),
('E486103','tops','long_sleeve','tshirt'),('E486651','tops','long_sleeve','tshirt'),
('E488762','tops','long_sleeve','tshirt');
update fitmatch_staging.runtime_classification_regression_cases r
set expected_category_code=c.category_code, expected_detail_code=c.detail_code, expected_comparable=true,
evidence=r.evidence||jsonb_build_object('classification_correction','airism_product_structure_audit','corrected_at','2026-08-14')
from airism_classification_corrections c
where r.source_code='uniqlo' and r.external_product_id=c.product_id;
update fitmatch_qa.classification_cases q
set expected_category_code=c.category_code, expected_detail_code=c.detail_code,
expected_comparison_family=c.comparison_family, expected_length_type='unknown', requires_user_confirmation=false
from airism_classification_corrections c
where q.source='uniqlo' and q.product_id=c.product_id;
do $$ begin
if exists (
select 1 from airism_classification_corrections c
left join fitmatch_staging.runtime_classification_regression_cases r
on r.source_code='uniqlo' and r.external_product_id=c.product_id
where r.external_product_id is null or r.expected_category_code<>c.category_code or r.expected_detail_code<>c.detail_code
) then raise exception 'AIRism regression correction incomplete'; end if;
if exists (
select 1 from airism_classification_corrections c
left join fitmatch_qa.classification_cases q on q.source='uniqlo' and q.product_id=c.product_id
where q.product_id is null or q.expected_category_code<>c.category_code or q.expected_detail_code<>c.detail_code or q.expected_comparison_family<>c.comparison_family
) then raise exception 'AIRism QA expectation correction incomplete'; end if;
end $$;
commit;;
