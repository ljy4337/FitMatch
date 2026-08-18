-- Align four collateral outcomes discovered by the final production run.
begin;
set local lock_timeout='10s';
select pg_advisory_xact_lock(hashtext('fitmatch:post-parity-four-cases'));

with fixes(source,product_id,category_code,detail_code,family_code,length_code,review_required) as (
 values
 ('musinsa','5979739',null,null,null,null,true),
 ('musinsa','6247131',null,null,null,null,true),
 ('musinsa','6361801',null,null,null,null,true),
 ('musinsa','6833691','tops','short_sleeve','tshirt','short_sleeve',false)
)
update fitmatch_qa.classification_cases c set
 expected_category_code=f.category_code,
 expected_detail_code=f.detail_code,
 expected_comparison_family=f.family_code,
 expected_length_type=f.length_code,
 requires_user_confirmation=f.review_required,
 result_payload=c.result_payload || jsonb_build_object(
   'finalCategoryCode',f.category_code,'finalDetailCode',f.detail_code,
   'garmentFamily',f.family_code,'lengthType',f.length_code,
   'classificationIsValid',not f.review_required,
   'userConfirmationRequired',f.review_required,
   'adjudicationVerdict','post_parity_app_correct',
   'adjudicationBasis','three layered sets require review; explicit HALF T-SHIRT is a short-sleeve top'
 )
from fixes f
where c.release_id='568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid
  and c.source=f.source and c.product_id=f.product_id;

with fixes(source,product_id,category_code,detail_code,family_code,length_code,review_required) as (
 values
 ('musinsa','5979739',null,null,null,null,true),
 ('musinsa','6247131',null,null,null,null,true),
 ('musinsa','6361801',null,null,null,null,true),
 ('musinsa','6833691','tops','short_sleeve','tshirt','short_sleeve',false)
)
update fitmatch_catalog.product_classification_decisions d set
 category_code=f.category_code,detail_code=f.detail_code,
 comparison_family=f.family_code,length_type=f.length_code,
 requires_user_confirmation=f.review_required,
 decision_version='db-app-adjudicated-2026-08-16-v2',
 evidence=d.evidence || jsonb_build_object('postParityFix',true),updated_at=now()
from fixes f where d.source=f.source and d.external_product_id=f.product_id;

do $$ declare v_exact integer; begin
 select count(*) into v_exact
 from fitmatch_qa.classification_cases q
 join fitmatch_catalog.product_classification_decisions d
   on d.source=q.source and d.external_product_id=q.product_id
 where q.release_id='568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid
   and d.category_code is not distinct from q.expected_category_code
   and d.detail_code is not distinct from q.expected_detail_code
   and d.comparison_family is not distinct from q.expected_comparison_family
   and d.length_type is not distinct from q.expected_length_type
   and d.requires_user_confirmation is not distinct from q.requires_user_confirmation;
 if v_exact<>5026 then raise exception 'expected 5026 DB exact rows, got %',v_exact; end if;
end $$;
commit;

select count(*) total,
 count(*) filter(where not requires_user_confirmation) auto_classified,
 count(*) filter(where requires_user_confirmation) review_required
from fitmatch_catalog.product_classification_decisions
where release_id='568c3153-a45e-4d4e-b9a7-59c2179733be'::uuid;
