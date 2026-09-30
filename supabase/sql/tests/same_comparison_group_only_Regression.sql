-- LOCAL ONLY: run with psql against a disposable database named
-- fitmatch_all_groups_regression. The included fixture deliberately applies
-- the old explicit-cross-group policy first, then this regression proves the
-- follow-up migration restores same-group-only candidates and authorization.
\set ON_ERROR_STOP on
\ir explicit_cross_group_comparison_Regression.sql
\ir ../../migrations/20260923110000_same_comparison_group_only.sql

do $$
declare
  candidates jsonb;
  authorization_value jsonb;
  target_id constant uuid := '00000000-0000-0000-0000-000000000003';
  variant_id constant uuid := '00000000-0000-0000-0000-000000000004';
  size_id constant uuid := '00000000-0000-0000-0000-000000000005';
  outer_closet_id constant uuid := '00000000-0000-0000-0000-000000000002';
  top_closet_id constant uuid := '00000000-0000-0000-0000-000000000006';
begin
  -- Target F has no F Closet item. A/B/C must remain blocked even though the
  -- old migration made them selectable by common canonical evidence.
  candidates := fitmatch_vnext.find_reference_candidates(target_id, variant_id);
  if candidates->>'candidate_count' <> '0' then
    raise exception 'Cross-group native candidate leaked: %', candidates;
  end if;
  candidates := fitmatch_vnext.find_reference_candidates(
    target_id, variant_id, 'F'
  );
  if candidates->>'candidate_count' <> '0' then
    raise exception 'Cross-group session candidate leaked: %', candidates;
  end if;
  authorization_value := fitmatch_vnext.authorize_comparison_with_context_v1(
    outer_closet_id, target_id, size_id, true,
    fitmatch_vnext.effective_target_classification(target_id)
  );
  if coalesce((authorization_value->>'allowed')::boolean, false) then
    raise exception 'Cross-group native authorization leaked: %', authorization_value;
  end if;
  authorization_value := fitmatch_vnext.authorize_comparison_with_context_v1(
    outer_closet_id, target_id, size_id, true,
    fitmatch_vnext.comparison_target_context(target_id, variant_id, 'F')
      -> 'effective_classification',
    'F'
  );
  if coalesce((authorization_value->>'allowed')::boolean, false) then
    raise exception 'Cross-group session authorization leaked: %', authorization_value;
  end if;

  -- Same group A continues through candidate and authorization gates when one
  -- common canonical measurement exists.
  update fitmatch_vnext.products
  set comparison_group_code = 'A', garment_type_code = 'top'
  where id = target_id;
  candidates := fitmatch_vnext.find_reference_candidates(target_id, variant_id);
  if candidates->>'candidate_count' <> '1'
     or exists (
       select 1
       from jsonb_array_elements(candidates->'candidates') candidate
       where candidate->>'closet_item_id' is distinct from top_closet_id::text
          or candidate->>'same_comparison_group' is distinct from 'true'
     ) then
    raise exception 'Same-group native candidate did not remain selectable: %', candidates;
  end if;
  authorization_value := fitmatch_vnext.authorize_comparison_with_context_v1(
    top_closet_id, target_id, size_id, true,
    fitmatch_vnext.effective_target_classification(target_id)
  );
  if not coalesce((authorization_value->>'allowed')::boolean, false) then
    raise exception 'Same-group native authorization failed: %', authorization_value;
  end if;
end
$$;

select 'PASS: same-group candidates and authorization only' as result;
