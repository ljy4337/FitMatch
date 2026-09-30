with expected(signature,hash) as (values
('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb)','f836b497b0a9536ecd86e5205b234b7f'),
('fitmatch_vnext.authorize_comparison_with_context_v1(uuid,uuid,uuid,boolean,jsonb,text)','fa7f2992178f1f7f9936197cf889addd'),
('fitmatch_vnext.find_reference_candidates(uuid,uuid)','26c8a4e2d3b797280accc26135e848c9'),
('fitmatch_vnext.find_reference_candidates(uuid,uuid,text)','01e858c178895e6aa9f88a3a84a16943')
) select signature, md5(pg_get_functiondef(signature::regprocedure)) = hash as definition_matches_verified_local from expected;
